#!/usr/bin/env bash
# DuDuClaw OS (Yocto layer, meta-duduclaw/) — release-time image build,
# artifact collection, and signing.
#
# Usage:
#   ./scripts/release-os.sh audit                   OS-side version detail
#                                                    (DISTRO_VERSION incl.
#                                                    milestone suffix, per-
#                                                    machine recipe status)
#   ./scripts/release-os.sh plan v<version> [--machine <name>] [--image <recipe>]
#                                                    ALWAYS dry — prints the
#                                                    kas/bitbake/docker
#                                                    commands a real build
#                                                    would run, never
#                                                    executes them
#   ./scripts/release-os.sh build v<version> [--machine <name>] [--image <recipe>] [--dry-run]
#                                                    REAL: `kas build` (via
#                                                    KAS_TARGET=<recipe>)
#                                                    inside the already-
#                                                    running builder
#                                                    container. Guard-gated:
#                                                    refuses to run if the
#                                                    container is not up or
#                                                    already has a kas/
#                                                    bitbake process in
#                                                    flight (see "builder
#                                                    concurrency" below).
#                                                    Expensive (minutes with
#                                                    warm sstate, hours
#                                                    cold) — never called
#                                                    automatically by this
#                                                    script or by
#                                                    scripts/release.sh.
#   ./scripts/release-os.sh smoke v<version> [--machine <name>] [--image <recipe>] [--timeout <secs>]
#                                                    REAL: headless QEMU
#                                                    boot of an
#                                                    ALREADY-BUILT image,
#                                                    waits for a serial
#                                                    "login:" prompt (or
#                                                    <timeout>s, default
#                                                    300). This is the SAME
#                                                    gate `package` runs
#                                                    automatically before
#                                                    signing — exposed as
#                                                    its own subcommand so
#                                                    it can be run/re-run
#                                                    standalone. It only
#                                                    proves the image boots
#                                                    to a login prompt, NOT
#                                                    a full shell/kiosk
#                                                    regression pass.
#   ./scripts/release-os.sh package v<version> [--machine <name>] [--image <recipe>] [--dry-run] [--skip-smoke-test]
#                                                    collect the deploy
#                                                    artifact from an
#                                                    ALREADY-BUILT image,
#                                                    run the smoke-test
#                                                    gate (unless skipped),
#                                                    compress + sha256 +
#                                                    minisign, stage into a
#                                                    versioned output
#                                                    directory
#
# What this script is NOT:
#   - `build`/`smoke`/`package` are real, but none of them is invoked
#     automatically by this script's own other subcommands or by
#     scripts/release.sh's bump flow. That script only syncs OS-side
#     version METADATA (recipe PVs, DISTRO_VERSION's numeric prefix) on
#     every platform release — see its "yocto_inc"/"yocto_bb" kinds —
#     because a Yocto image build takes hours and cannot be a routine side
#     effect of a `patch` bump. Once the Y-line is ready to ship an image
#     for a given version, run this script's subcommands by hand, in
#     order: build -> smoke (optional standalone check) -> package.
#   - `build` never starts a NEW builder container (no `docker run`) — it
#     only execs into one that is already up, per meta-duduclaw/README.md
#     "Usage". Starting/stopping the builder container is a human decision
#     (disk/CPU cost, may be shared across sessions), never automated here.
#
# Builder concurrency (commercial/docs/DESIGN-os-release-pipeline-2026-08.md
# §3.5 — codifying a real incident, not a hypothetical): `build`, `smoke`,
# and `package`'s real paths all refuse to start if the shared builder
# container already has a kas/bitbake (build/package) or qemu-system
# (smoke) process in flight. Fail-closed, no queueing, no retrying — see
# check_builder_idle() below.
#
# Design: commercial/docs/DESIGN-unified-release-2026-08.md (version
# single-source + release.sh/release-os.sh split) and
# commercial/docs/DESIGN-os-release-pipeline-2026-08.md (this script's own
# end-to-end build->smoke->package design, incl. the manifest.json schema
# documented inline in write_manifest_json() below).
# Version single-source: meta-duduclaw/conf/distro/include/
#   duduclaw-platform-version.inc (see that file's own header comment)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

SEMVER='[0-9]+\.[0-9]+\.[0-9]+'
PLATFORM_VERSION_INC="meta-duduclaw/conf/distro/include/duduclaw-platform-version.inc"
DISTRO_CONF="meta-duduclaw/conf/distro/duduclaw-os.conf"

# Builder container convention, verbatim from meta-duduclaw/README.md
# "Usage" (the only place this is documented — not re-invented here).
BUILDER_CONTAINER="${DUDUCLAW_YOCTO_CONTAINER:-duduclaw-yocto}"

# Machine -> kas config file. Matches meta-duduclaw/kas/*.yml (qemux86-64 is
# the bring-up/QEMU-verifiable target; genericx86-64 is the real-hardware
# target that can only be config-audited, not QEMU-booted, per the Y2-3
# handoff notes in commercial/docs/TODO-agent-first-os-2026-08.md).
kas_config_for_machine() {
    case "$1" in
        duduclaw-qemux86-64) echo "meta-duduclaw/kas/duduclaw-os.yml" ;;
        duduclaw-genericx86-64) echo "meta-duduclaw/kas/duduclaw-os-genericx86-64.yml" ;;
        *) echo "" ;;
    esac
}
DEFAULT_MACHINES=(duduclaw-qemux86-64 duduclaw-genericx86-64)

# The Y10-2 image-convergence shipping target (commercial/docs/
# DESIGN-image-convergence-2026-08.md, landed Y14 2026-08-27/28,
# meta-duduclaw/recipes-core/images/duduclaw-image-appliance.bb — A/B
# atomic update + full flatpak desktop payload, IMAGE_FEATURES hardened,
# A/B T2/T6 update+rollback PASS against this exact recipe). This is a
# `KAS_TARGET=` override (same env-var mechanism the Y8-1/Y11-2 sessions
# already used by hand for duduclaw-image-ab), NOT an edit to
# meta-duduclaw/kas/*.yml's own `target:` field — that field still reads
# the Y11-3 interim value (duduclaw-image-flatpak) and is deliberately
# left alone here: it is a shared config other in-flight sessions may be
# relying on, and DESIGN §4's own migration note already earmarks bumping
# it as a separate, explicit follow-up once Y10-2 is fully adopted as the
# default everywhere, not something a release-os.sh edit should do as a
# side effect of one release run.
DEFAULT_IMAGE="${DUDUCLAW_OS_IMAGE:-duduclaw-image-appliance}"

# Same minisign keypair convention as appliance/tools/make-payload.py (the
# Debian line's H3d payload signer) — "沿用 OS 金鑰 minisign 慣例" means the
# SAME KEY namespace, kept independent from duduclaw-release.key (CE binary)
# and duduclaw-pro-release.key (Pro binary) per that script's own key-
# isolation comment. Public half copied verbatim from that script's
# RELEASE_PUBKEY constant (not re-derived/guessed) so a signature this
# script produces verifies against the exact same trust anchor an
# appliance-line payload would.
OS_SIGN_KEY="${DUDUCLAW_OS_SIGN_KEY:-$HOME/.minisign/duduclaw-os-release.key}"
OS_RELEASE_PUBKEY="RWQyI00ugZ/+WVisQ2ZnKeTqFs8Ze8h2X11FO9Z8le0YubFMXYTwQD7n"

usage() {
    sed -n '2,60p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

# --- concurrency guard (DESIGN §3.5) ----------------------------------------
# Fails CLOSED: a detection error (pgrep exit code other than "found" (0) or
# "no match" (1) — e.g. docker exec itself failing) is treated as "cannot
# prove idle", never as "assume idle". Never queues, never retries — the
# caller must re-run once the other process is done.
check_builder_idle() {
    local rc
    docker exec "$BUILDER_CONTAINER" pgrep -f 'bitbake|kas ' >/dev/null 2>&1
    rc=$?
    if [[ $rc -eq 0 ]]; then
        echo "Error: builder container '$BUILDER_CONTAINER' has an in-flight" >&2
        echo "       kas/bitbake process. Refusing to start a concurrent" >&2
        echo "       build/package — not queueing, not retrying. See" >&2
        echo "       commercial/docs/DESIGN-os-release-pipeline-2026-08.md §3.5" >&2
        echo "       for the real incident this check exists to prevent." >&2
        return 1
    elif [[ $rc -eq 1 ]]; then
        return 0
    else
        echo "Error: could not determine whether $BUILDER_CONTAINER is idle" >&2
        echo "       (docker exec/pgrep exited $rc) — failing closed, not" >&2
        echo "       assuming idle." >&2
        return 1
    fi
}

# --- audit: OS-side version detail, read-only -------------------------------
run_os_audit() {
    local platform_v inc_v distro_line distro_v
    platform_v="$(grep -m1 -E "^version = \"$SEMVER\"" Cargo.toml \
        | sed -E "s/version = \"($SEMVER)\".*/\1/")"
    echo "DuDuClaw OS version audit (source of truth: Cargo workspace = $platform_v)"
    echo "------------------------------------------------------------------"

    if [[ -f "$PLATFORM_VERSION_INC" ]]; then
        inc_v="$(grep -m1 -E "^DUDUCLAW_PLATFORM_VERSION = \"$SEMVER\"" "$PLATFORM_VERSION_INC" \
            | sed -E "s/.*\"($SEMVER)\".*/\1/")"
        if [[ "$inc_v" == "$platform_v" ]]; then
            printf "  %-60s %-12s OK\n" "$PLATFORM_VERSION_INC" "$inc_v"
        else
            printf "  %-60s %-12s DRIFT (expected %s)\n" "$PLATFORM_VERSION_INC" "${inc_v:-?}" "$platform_v"
        fi
    else
        echo "  $PLATFORM_VERSION_INC: MISSING"
    fi

    if [[ -f "$DISTRO_CONF" ]]; then
        distro_line="$(grep -m1 '^DISTRO_VERSION = ' "$DISTRO_CONF" || true)"
        distro_v="$(echo "$distro_line" | sed -E 's/^DISTRO_VERSION = "(.*)"$/\1/')"
        echo "  DISTRO_VERSION (full, incl. milestone suffix): ${distro_v:-?}"
        if [[ "$distro_v" != "\${DUDUCLAW_PLATFORM_VERSION}"* ]]; then
            echo "    NOTE: not composed from \${DUDUCLAW_PLATFORM_VERSION} — either"
            echo "    this file predates the Y3-3 wiring or was hand-edited back to a"
            echo "    literal. See that file's own comment for the intended form."
        fi
    fi

    local pn bb_path bb_v
    for pn in duduclaw-cli duduclaw-sysd duduclaw-comp; do
        bb_path="$(find "meta-duduclaw/recipes-duduclaw/$pn" -maxdepth 1 -name "${pn}_*.bb" 2>/dev/null | head -1)"
        if [[ -z "$bb_path" ]]; then
            printf "  %-60s %-12s MISSING (no recipe found)\n" "$pn" "-"
            continue
        fi
        bb_v="$(basename "$bb_path" .bb | sed -E "s/^${pn}_($SEMVER)\$/\1/")"
        if [[ "$bb_v" == "$platform_v" ]]; then
            printf "  %-60s %-12s OK\n" "$bb_path" "$bb_v"
        else
            printf "  %-60s %-12s DRIFT (expected %s)\n" "$bb_path" "${bb_v:-?}" "$platform_v"
        fi
    done

    echo "------------------------------------------------------------------"
    echo "duduclaw-cli-worker / duduclaw-shell have no Yocto recipe yet (Y2-1"
    echo "handoff, zero work item) — not audited here, nothing to drift."
    echo ""
    echo "Kernel version (linux-yocto_6.18.bbappend) tracks Yocto LTS"
    echo "independently of the platform version — NOT part of this audit by"
    echo "design (see kernel-self-maintain-2026-08.md research doc)."
}

# --- plan: print, never execute ----------------------------------------------
run_plan() {
    local version="$1" machine="$2" image="$3" kas_cfg
    kas_cfg="$(kas_config_for_machine "$machine")"
    if [[ -z "$kas_cfg" ]]; then
        echo "Error: unknown machine '$machine' (known: ${DEFAULT_MACHINES[*]})" >&2
        return 1
    fi
    echo "[PLAN, not executed] DuDuClaw OS image build for $version / $machine / $image"
    echo "------------------------------------------------------------------"
    echo "1. Version metadata must already be synced to $version (run"
    echo "   'scripts/release.sh <bump>' first — this script never bumps"
    echo "   versions itself, see 'audit' above to confirm)."
    echo ""
    echo "2. Build (real command — or just run './scripts/release-os.sh"
    echo "   build v$version --machine $machine --image $image'):"
    echo "   docker exec -u 1000 $BUILDER_CONTAINER bash -c \\"
    echo "     \"cd /workspace && KAS_TARGET=$image kas build $kas_cfg\""
    echo ""
    echo "3. Discover the real deploy dir (never hardcoded/guessed — bitbake"
    echo "   computes it from MACHINE/DISTRO, and it can change):"
    echo "   docker exec -u 1000 $BUILDER_CONTAINER bash -c \\"
    echo "     \"cd /workspace && kas shell $kas_cfg -c \\\""
    echo "      'bitbake -e duduclaw-image | grep ^DEPLOY_DIR_IMAGE='\\\"\""
    echo ""
    echo "4. Smoke-test gate (or let 'package' run it automatically):"
    echo "   ./scripts/release-os.sh smoke v$version --machine $machine --image $image"
    echo ""
    echo "5. Once built (and, ideally, smoke-tested), collect + sign artifacts:"
    echo "   ./scripts/release-os.sh package v$version --machine $machine --image $image"
    echo "------------------------------------------------------------------"
    echo "This subcommand never touches the builder container or the"
    echo "network — it only prints the above."
}

# --- build: REAL kas build inside the already-running builder container ----
run_build() {
    local version="$1" machine="$2" image="$3" dry_run="$4" kas_cfg
    kas_cfg="$(kas_config_for_machine "$machine")"
    if [[ -z "$kas_cfg" ]]; then
        echo "Error: unknown machine '$machine' (known: ${DEFAULT_MACHINES[*]})" >&2
        return 1
    fi

    echo "Building DuDuClaw OS image: v$version / $machine / $image"
    echo "  kas config: $kas_cfg"

    if $dry_run; then
        echo ""
        echo "[DRY RUN] Would:"
        echo "  1. Check builder container '$BUILDER_CONTAINER' is running AND"
        echo "     idle (no in-flight kas/bitbake process — DESIGN §3.5)."
        echo "  2. docker exec -u 1000 $BUILDER_CONTAINER bash -c \\"
        echo "       \"cd /workspace && KAS_TARGET=$image kas build $kas_cfg\""
        echo "  3. On success, resolve + print DEPLOY_DIR_IMAGE for the next"
        echo "     'smoke'/'package' step."
        echo ""
        echo "No docker/network calls were made."
        return 0
    fi

    if ! command -v docker >/dev/null 2>&1; then
        echo "Error: docker not found — cannot reach the Yocto builder container." >&2
        return 1
    fi
    if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$BUILDER_CONTAINER"; then
        echo "Error: builder container '$BUILDER_CONTAINER' is not running." >&2
        echo "       Start it per meta-duduclaw/README.md \"Usage\" first (this" >&2
        echo "       script never starts one itself)." >&2
        return 1
    fi
    if ! check_builder_idle; then
        return 1
    fi

    echo ""
    echo "Starting real build inside $BUILDER_CONTAINER (KAS_TARGET=$image)..."
    echo "  (warm sstate: minutes; cold cache: hours — see meta-duduclaw/README.md)"
    if ! docker exec -u 1000 "$BUILDER_CONTAINER" bash -c \
        "cd /workspace && KAS_TARGET=$image kas build $kas_cfg"; then
        echo "Error: kas build failed for target '$image' / $machine." >&2
        return 1
    fi

    echo ""
    echo "Build succeeded. Resolving DEPLOY_DIR_IMAGE..."
    local deploy_dir
    deploy_dir="$(docker exec -u 1000 "$BUILDER_CONTAINER" bash -c \
        "cd /workspace && kas shell $kas_cfg -c 'bitbake -e duduclaw-image | grep ^DEPLOY_DIR_IMAGE='" \
        2>/dev/null | sed -E 's/^DEPLOY_DIR_IMAGE="(.*)"$/\1/')"
    if [[ -z "$deploy_dir" ]]; then
        echo "Warning: build succeeded but DEPLOY_DIR_IMAGE could not be resolved." >&2
    else
        echo "  DEPLOY_DIR_IMAGE = $deploy_dir"
    fi
    echo ""
    echo "Next: ./scripts/release-os.sh smoke v$version --machine $machine --image $image"
    echo "  (or skip straight to package, which runs the same gate automatically)"
    echo "      ./scripts/release-os.sh package v$version --machine $machine --image $image"
}

# --- smoke: REAL headless QEMU boot, gate on a serial login prompt ---------
# DESIGN §3.2: this is deliberately a LOW bar — "does this image reach a
# login prompt at all" — not a full shell/kiosk regression pass (which
# needs a human watching NRestarts for several minutes and would make every
# `package` run fail today on the known QEMU/TCG shell-crash limitation).
# Reused verbatim invocation shape from the Y1-1/Y4-0 README-documented
# command: `runqemu <image> nographic serial wic ovmf slirp` — slirp because
# the builder container is unprivileged (no /dev/net/tun for tap
# networking), exactly as meta-duduclaw/README.md's own "Usage" section
# explains.
run_smoke_test() {
    local machine="$1" image="$2" timeout_s="${3:-300}" kas_cfg
    kas_cfg="$(kas_config_for_machine "$machine")"
    if [[ -z "$kas_cfg" ]]; then
        echo "Error: unknown machine '$machine' (known: ${DEFAULT_MACHINES[*]})" >&2
        return 1
    fi

    local poll_interval=5 elapsed=0
    local log_path="/workspace/.release-os-smoke-$$-$(date +%s).log"

    echo "Smoke test: booting $image / $machine under headless QEMU" \
         "(waiting up to ${timeout_s}s for a serial login prompt)..."

    # Never touch a qemu-system process we didn't start ourselves — could
    # belong to another session's own test. Fail closed on detection error
    # too (same discipline as check_builder_idle).
    local rc
    docker exec "$BUILDER_CONTAINER" pgrep -f 'qemu-system' >/dev/null 2>&1
    rc=$?
    if [[ $rc -eq 0 ]]; then
        echo "Error: a qemu-system process is already running inside" >&2
        echo "       $BUILDER_CONTAINER — not touching it (may belong to" >&2
        echo "       another session). Refusing to start a second QEMU" >&2
        echo "       instance concurrently." >&2
        return 1
    elif [[ $rc -ne 1 ]]; then
        echo "Error: could not check for an existing qemu-system process" >&2
        echo "       (docker exec/pgrep exited $rc) — failing closed." >&2
        return 1
    fi

    echo "  Ensuring OVMF firmware is built (sstate-cached, idempotent, separate"
    echo "  host tool per meta-duduclaw/README.md \"Usage\")..."
    if ! docker exec -u 1000 "$BUILDER_CONTAINER" bash -c \
        "cd /workspace && kas shell $kas_cfg -c 'bitbake ovmf'" >/dev/null 2>&1; then
        echo "Error: 'bitbake ovmf' failed — cannot smoke-test without UEFI firmware." >&2
        return 1
    fi

    echo "  Launching runqemu (detached, serial console -> $log_path inside container)..."
    docker exec -u 1000 -d "$BUILDER_CONTAINER" bash -c \
        "cd /workspace && kas shell $kas_cfg -c 'runqemu $image nographic serial wic ovmf slirp' > $log_path 2>&1"

    local seen_login=false
    while (( elapsed < timeout_s )); do
        if docker exec "$BUILDER_CONTAINER" grep -qE '(^| )login:' "$log_path" 2>/dev/null; then
            seen_login=true
            break
        fi
        sleep "$poll_interval"
        elapsed=$((elapsed + poll_interval))
    done

    # Terminate our own QEMU regardless of outcome. Safe to assume it's
    # "ours": the pre-flight pgrep above already returned "no match" (rc=1)
    # before we launched anything, so any qemu-system process found now was
    # started by this call.
    docker exec "$BUILDER_CONTAINER" pkill -f 'qemu-system' >/dev/null 2>&1 || true
    docker exec "$BUILDER_CONTAINER" pkill -f 'bin/runqemu' >/dev/null 2>&1 || true

    if ! $seen_login; then
        echo "Error: smoke test timed out after ${timeout_s}s without a login prompt." >&2
        echo "       Last 40 lines of $log_path (inside $BUILDER_CONTAINER):" >&2
        docker exec "$BUILDER_CONTAINER" tail -n 40 "$log_path" >&2 2>/dev/null || true
        return 1
    fi

    echo "Smoke test PASS: login prompt reached (~${elapsed}s)."
    docker exec "$BUILDER_CONTAINER" rm -f "$log_path" >/dev/null 2>&1 || true
    return 0
}

# --- package: collect + smoke-test gate + compress + sha256 + minisign -----
#
# manifest.json SCHEMA (DESIGN §3.3/§3.4 — documented here, not just in the
# design doc, so the next reader finds it next to the code that writes it):
#   {
#     "schema": 1,                          this schema's own version
#     "version": "<version arg as given>",  e.g. "1.62.0-y1-bringup"
#     "distro_version_full": "<DISTRO_VERSION>", numeric + milestone suffix,
#                                            read from duduclaw-os.conf —
#                                            may differ from "version" above
#                                            if the operator packages under
#                                            a different label than what's
#                                            baked into the image; this
#                                            field is the ground truth for
#                                            "what did the image actually
#                                            report at build time"
#     "machine": "<duduclaw-qemux86-64|duduclaw-genericx86-64>",
#     "image": "<bitbake recipe name>",     e.g. "duduclaw-image-appliance"
#     "generated_at": "<ISO-8601 UTC>",
#     "artifact": {"name","size","sha256"}, the ONE signed artifact
#                                            (duduclaw-os-<machine>-v<version>.wic.zst)
#     "signed_with": "<pubkey file basename>",
#     "rpm_feed": {"note","file_count","total_bytes"}
#                                            AUXILIARY ONLY — the RPM feed
#                                            (tmp/deploy/rpm/, a SIBLING of
#                                            DEPLOY_DIR_IMAGE, not nested
#                                            inside it — the pre-WP-c
#                                            version of this function
#                                            looked in the wrong place and
#                                            would have found nothing) is
#                                            counted/sized here but NOT
#                                            packaged as a separate signed
#                                            artifact this round — see
#                                            DESIGN §5 item 2. A future
#                                            ticket that wants to ship a
#                                            local package mirror /
#                                            incremental-update
#                                            infrastructure would build on
#                                            this field, not invent a new
#                                            lookup.
#   }
# manifest.json is convenience provenance, same discipline as
# make-payload.py's own manifest: NOT part of the trust chain. The
# artifact's own .sha256 + .minisig are what an installer must verify.
#
# This is a DIFFERENT schema from make-payload.py's manifest.json (that one
# lists "files": [...] for a root.raw + .efi PAIR, because it packages an
# OTA delta payload, not a bootable whole-disk image) — DESIGN §3.4
# deliberately does not unify the two; both are documented on their own
# terms so a future consumer doesn't have to reverse-engineer either.
run_package() {
    local version="$1" machine="$2" image="$3" dry_run="$4" skip_smoke="$5"
    local kas_cfg out_dir artifact_base artifact_wic
    kas_cfg="$(kas_config_for_machine "$machine")"
    if [[ -z "$kas_cfg" ]]; then
        echo "Error: unknown machine '$machine' (known: ${DEFAULT_MACHINES[*]})" >&2
        return 1
    fi
    out_dir="artifacts/os/v${version}/${machine}"
    artifact_base="duduclaw-os-${machine}-v${version}"
    artifact_wic="${artifact_base}.wic.zst"

    echo "Packaging DuDuClaw OS artifacts: v$version / $machine / $image"
    echo "  Output directory: $out_dir"
    echo "  Artifact base:    $artifact_base"
    echo "  Signing key:      $OS_SIGN_KEY"

    if $dry_run; then
        echo ""
        echo "[DRY RUN] Would:"
        echo "  1. Resolve the built '$image' wic for $machine via the 'latest'"
        echo "     Yocto convenience symlink (must already exist — this"
        echo "     subcommand never triggers a build; run 'release-os.sh build'"
        echo "     first)."
        echo "  2. Run the headless-QEMU smoke-test gate (see 'smoke' subcommand"
        echo "     / DESIGN §3.2) unless --skip-smoke-test is passed — fails"
        echo "     closed if no serial login prompt within its timeout."
        echo "  3. Compress the resolved .wic with zstd INSIDE the builder"
        echo "     container, writing straight into the bind-mounted \$out_dir"
        echo "     (avoids docker-cp'ing the full sparse .wic — its apparent"
        echo "     size can be far larger than its real content) as:"
        echo "       $out_dir/$artifact_wic"
        echo "  4. shasum -a 256 -> $out_dir/$artifact_wic.sha256"
        echo "  5. minisign -S -s $OS_SIGN_KEY -m $out_dir/$artifact_wic"
        echo "     -> $out_dir/$artifact_wic.minisig"
        echo "  6. minisign -V self-verify against the pinned OS_RELEASE_PUBKEY"
        echo "     (a payload that can't prove its own integrity on the build"
        echo "     host must never reach a machine — make-payload.py's own"
        echo "     discipline)"
        echo "  7. Write $out_dir/$artifact_base.manifest.json — schema"
        echo "     documented in this script's run_package() header comment"
        echo "     and in DESIGN §3.3/§3.4. NOT part of the trust chain."
        echo "  8. Count (not package) the RPM feed at tmp/deploy/rpm/ as"
        echo "     auxiliary manifest metadata (DESIGN §5 item 2)."
        echo ""
        echo "No files were read or written by this dry run."
        return 0
    fi

    # Real path. Fails closed at every step — never fabricates an artifact
    # list, never signs an empty/partial/unbooted image silently.
    if ! command -v docker >/dev/null 2>&1; then
        echo "Error: docker not found — cannot reach the Yocto builder container." >&2
        return 1
    fi
    if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$BUILDER_CONTAINER"; then
        echo "Error: builder container '$BUILDER_CONTAINER' is not running." >&2
        echo "       Start it per meta-duduclaw/README.md \"Usage\" first." >&2
        return 1
    fi
    if [[ ! -f "$OS_SIGN_KEY" ]]; then
        echo "Error: OS signing key not found at $OS_SIGN_KEY" >&2
        echo "       (set DUDUCLAW_OS_SIGN_KEY to override the path)." >&2
        return 1
    fi
    if ! command -v minisign >/dev/null 2>&1; then
        echo "Error: minisign not found in PATH." >&2
        return 1
    fi
    if ! check_builder_idle; then
        return 1
    fi

    echo ""
    echo "Resolving DEPLOY_DIR_IMAGE inside $BUILDER_CONTAINER..."
    local deploy_dir
    deploy_dir="$(docker exec -u 1000 "$BUILDER_CONTAINER" bash -c \
        "cd /workspace && kas shell $kas_cfg -c 'bitbake -e duduclaw-image | grep ^DEPLOY_DIR_IMAGE='" \
        2>/dev/null | sed -E 's/^DEPLOY_DIR_IMAGE="(.*)"$/\1/')"
    if [[ -z "$deploy_dir" ]]; then
        echo "Error: could not resolve DEPLOY_DIR_IMAGE — has 'release-os.sh" >&2
        echo "       build' actually completed for '$image' / $machine yet?" >&2
        return 1
    fi
    echo "  DEPLOY_DIR_IMAGE = $deploy_dir"

    local wic_symlink="$deploy_dir/${image}-${machine}.rootfs.wic"
    local wic_real
    wic_real="$(docker exec -u 1000 "$BUILDER_CONTAINER" readlink -f "$wic_symlink" 2>/dev/null || true)"
    if [[ -z "$wic_real" ]] || ! docker exec -u 1000 "$BUILDER_CONTAINER" test -f "$wic_real" 2>/dev/null; then
        echo "Error: no built .wic found at $wic_symlink" >&2
        echo "       (expected the 'latest' convenience symlink Yocto writes" >&2
        echo "       for image '$image' — has that EXACT image (not just any" >&2
        echo "       recipe in its require chain) been built for $machine?)" >&2
        return 1
    fi
    echo "  Resolved wic: $wic_real"

    if ! $skip_smoke; then
        echo ""
        if ! run_smoke_test "$machine" "$image"; then
            echo "Error: smoke-test gate failed — refusing to sign an image that" >&2
            echo "       did not prove it can boot to a login prompt." >&2
            return 1
        fi
    else
        echo "" >&2
        echo "WARNING: --skip-smoke-test passed — packaging an image that was" >&2
        echo "         NOT verified to boot this run. Debugging use only, never" >&2
        echo "         for a real release." >&2
    fi

    mkdir -p "$out_dir"
    echo ""
    echo "Compressing (inside $BUILDER_CONTAINER, writing straight to the"
    echo "bind-mounted $out_dir — no docker-cp of the uncompressed sparse .wic)..."
    if ! docker exec -u 1000 "$BUILDER_CONTAINER" bash -c \
        "command -v zstd >/dev/null 2>&1 || { echo 'zstd not found in $BUILDER_CONTAINER' >&2; exit 1; }; \
         mkdir -p '/workspace/$out_dir' && \
         zstd -T0 -f -o '/workspace/$out_dir/$artifact_wic' '$wic_real'"; then
        echo "Error: zstd compression failed inside $BUILDER_CONTAINER." >&2
        return 1
    fi
    if [[ ! -s "$out_dir/$artifact_wic" ]]; then
        echo "Error: expected compressed artifact not found on host at" >&2
        echo "       $out_dir/$artifact_wic" >&2
        return 1
    fi

    ( cd "$out_dir" && shasum -a 256 "$artifact_wic" > "$artifact_wic.sha256" )
    if ! minisign -S -s "$OS_SIGN_KEY" -m "$out_dir/$artifact_wic" -t "DuDuClaw OS v$version ($machine, $image)"; then
        echo "Error: minisign signing failed." >&2
        return 1
    fi
    if ! minisign -V -m "$out_dir/$artifact_wic" -P "$OS_RELEASE_PUBKEY" >/dev/null; then
        echo "Error: self-verification against OS_RELEASE_PUBKEY failed — a" >&2
        echo "       payload that cannot verify itself must never ship." >&2
        return 1
    fi

    # RPM feed: auxiliary metadata only this round (see run_package()'s own
    # header comment + DESIGN §5 item 2). Sibling of deploy/images/, NOT
    # nested inside DEPLOY_DIR_IMAGE — the pre-WP-c version of this
    # function searched only inside DEPLOY_DIR_IMAGE itself and would have
    # silently found nothing; fixed here, and its output is actually read
    # (not just "path looks right") before being trusted.
    local rpm_dir rpm_count rpm_size
    rpm_dir="$(dirname "$(dirname "$deploy_dir")")/rpm"
    rpm_count="$(docker exec -u 1000 "$BUILDER_CONTAINER" bash -c "find '$rpm_dir' -type f 2>/dev/null | wc -l" 2>/dev/null | tr -d ' ')"
    rpm_size="$(docker exec -u 1000 "$BUILDER_CONTAINER" bash -c "du -sb '$rpm_dir' 2>/dev/null | cut -f1" 2>/dev/null | tr -d ' ')"
    echo "  RPM feed ($rpm_dir): ${rpm_count:-0} files, ${rpm_size:-0} bytes (auxiliary, not shipped as a signed artifact this round)"

    local artifact_sha version_full platform_v
    artifact_sha="$(shasum -a 256 "$out_dir/$artifact_wic" | awk '{print $1}')"
    platform_v="$(grep -m1 -E "^DUDUCLAW_PLATFORM_VERSION = \"$SEMVER\"" "$PLATFORM_VERSION_INC" 2>/dev/null | sed -E "s/.*\"($SEMVER)\".*/\1/")"
    version_full="$(grep -m1 '^DISTRO_VERSION = ' "$DISTRO_CONF" 2>/dev/null \
        | sed -E 's/^DISTRO_VERSION = "(.*)"$/\1/' \
        | sed "s/\${DUDUCLAW_PLATFORM_VERSION}/${platform_v}/")"

    python3 - "$out_dir" "$artifact_base" "$version" "$version_full" "$machine" "$image" "$artifact_wic" "$artifact_sha" "${rpm_count:-0}" "${rpm_size:-0}" "$OS_SIGN_KEY" <<'PYEOF'
import json, sys, datetime, pathlib
out_dir, artifact_base, version, version_full, machine, image, artifact_wic, artifact_sha, rpm_count, rpm_size, sign_key = sys.argv[1:12]
wic_path = pathlib.Path(out_dir, artifact_wic)
manifest = {
    "schema": 1,
    "version": version,
    "distro_version_full": version_full,
    "machine": machine,
    "image": image,
    "generated_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    "artifact": {
        "name": artifact_wic,
        "size": wic_path.stat().st_size,
        "sha256": artifact_sha,
    },
    "signed_with": pathlib.Path(sign_key).name.replace(".key", ".pub"),
    "rpm_feed": {
        "note": ("auxiliary provenance only -- NOT part of the signed artifact "
                 "set this round, see DESIGN-os-release-pipeline-2026-08.md §5 item 2"),
        "file_count": int(rpm_count) if rpm_count.isdigit() else None,
        "total_bytes": int(rpm_size) if rpm_size.isdigit() else None,
    },
}
pathlib.Path(out_dir, f"{artifact_base}.manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
PYEOF
    echo ""
    echo "Packaged + signed: $out_dir"
    echo "  $artifact_wic"
    echo "  $artifact_wic.sha256"
    echo "  $artifact_wic.minisig"
    echo "  $artifact_base.manifest.json"
}

# --- arg parsing --------------------------------------------------------
if [[ $# -lt 1 ]]; then
    usage
    exit 1
fi

case "$1" in
    audit)
        run_os_audit
        exit 0
        ;;
    plan)
        shift
        VERSION="${1:-}"
        MACHINE="${DEFAULT_MACHINES[0]}"
        IMAGE="$DEFAULT_IMAGE"
        shift || true
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --machine) shift; MACHINE="${1:-}" ;;
                --image) shift; IMAGE="${1:-}" ;;
                *) echo "Error: unknown option '$1'" >&2; exit 1 ;;
            esac
            shift
        done
        if [[ -z "$VERSION" ]]; then
            echo "Error: 'plan' requires a version, e.g. v1.63.0" >&2
            exit 1
        fi
        run_plan "${VERSION#v}" "$MACHINE" "$IMAGE"
        exit $?
        ;;
    build)
        shift
        VERSION="${1:-}"
        MACHINE="${DEFAULT_MACHINES[0]}"
        IMAGE="$DEFAULT_IMAGE"
        DRY_RUN=false
        shift || true
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --machine) shift; MACHINE="${1:-}" ;;
                --image) shift; IMAGE="${1:-}" ;;
                --dry-run) DRY_RUN=true ;;
                *) echo "Error: unknown option '$1'" >&2; exit 1 ;;
            esac
            shift
        done
        if [[ -z "$VERSION" ]]; then
            echo "Error: 'build' requires a version, e.g. v1.63.0" >&2
            exit 1
        fi
        run_build "${VERSION#v}" "$MACHINE" "$IMAGE" "$DRY_RUN"
        exit $?
        ;;
    smoke)
        shift
        VERSION="${1:-}"
        MACHINE="${DEFAULT_MACHINES[0]}"
        IMAGE="$DEFAULT_IMAGE"
        TIMEOUT=300
        shift || true
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --machine) shift; MACHINE="${1:-}" ;;
                --image) shift; IMAGE="${1:-}" ;;
                --timeout) shift; TIMEOUT="${1:-}" ;;
                *) echo "Error: unknown option '$1'" >&2; exit 1 ;;
            esac
            shift
        done
        if [[ -z "$VERSION" ]]; then
            echo "Error: 'smoke' requires a version, e.g. v1.63.0 (used only for" >&2
            echo "       log messages — the actual boot target is --image/--machine)." >&2
            exit 1
        fi
        if ! command -v docker >/dev/null 2>&1; then
            echo "Error: docker not found — cannot reach the Yocto builder container." >&2
            exit 1
        fi
        if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$BUILDER_CONTAINER"; then
            echo "Error: builder container '$BUILDER_CONTAINER' is not running." >&2
            exit 1
        fi
        run_smoke_test "$MACHINE" "$IMAGE" "$TIMEOUT"
        exit $?
        ;;
    package)
        shift
        VERSION="${1:-}"
        MACHINE="${DEFAULT_MACHINES[0]}"
        IMAGE="$DEFAULT_IMAGE"
        DRY_RUN=false
        SKIP_SMOKE=false
        shift || true
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --machine) shift; MACHINE="${1:-}" ;;
                --image) shift; IMAGE="${1:-}" ;;
                --dry-run) DRY_RUN=true ;;
                --skip-smoke-test) SKIP_SMOKE=true ;;
                *) echo "Error: unknown option '$1'" >&2; exit 1 ;;
            esac
            shift
        done
        if [[ -z "$VERSION" ]]; then
            echo "Error: 'package' requires a version, e.g. v1.63.0" >&2
            exit 1
        fi
        run_package "${VERSION#v}" "$MACHINE" "$IMAGE" "$DRY_RUN" "$SKIP_SMOKE"
        exit $?
        ;;
    *)
        usage
        exit 1
        ;;
esac
