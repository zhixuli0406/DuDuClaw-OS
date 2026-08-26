#!/usr/bin/env bash
# DuDuClaw OS (Yocto layer, meta-duduclaw/) — release-time image build,
# artifact collection, and signing.
#
# Usage:
#   ./scripts/release-os.sh audit                   OS-side version detail
#                                                    (DISTRO_VERSION incl.
#                                                    milestone suffix, per-
#                                                    machine recipe status)
#   ./scripts/release-os.sh plan v<version> [--machine <name>]
#                                                    ALWAYS dry — prints the
#                                                    kas/bitbake/docker
#                                                    commands a real build
#                                                    would run, never
#                                                    executes them
#   ./scripts/release-os.sh package v<version> [--machine <name>] [--dry-run]
#                                                    collect the deploy
#                                                    artifacts from an
#                                                    ALREADY-BUILT image,
#                                                    sha256sum + minisign,
#                                                    stage into a versioned
#                                                    output directory
#
# What this script is NOT:
#   - It does not run `kas build` / `bitbake` for real under any subcommand
#     ("plan" only prints what those commands would be). Cutting an actual
#     OS image is a deliberate, separate, human-triggered step — see
#     meta-duduclaw/README.md "Usage" for the real build commands, run
#     inside the Docker builder container that repo doc describes.
#   - It is NOT invoked automatically by scripts/release.sh's bump flow.
#     That script only syncs OS-side version METADATA (recipe PVs,
#     DISTRO_VERSION's numeric prefix) on every platform release — see its
#     "yocto_inc"/"yocto_bb" kinds — because a Yocto image build takes
#     hours and cannot be a routine side effect of a `patch` bump. Once the
#     Y-line is ready to ship an image for a given version, run this
#     script's `package` subcommand by hand.
#
# Design: commercial/docs/DESIGN-unified-release-2026-08.md
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
    sed -n '2,25p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
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
    local version="$1" machine="$2" kas_cfg
    kas_cfg="$(kas_config_for_machine "$machine")"
    if [[ -z "$kas_cfg" ]]; then
        echo "Error: unknown machine '$machine' (known: ${DEFAULT_MACHINES[*]})" >&2
        return 1
    fi
    echo "[PLAN, not executed] DuDuClaw OS image build for $version / $machine"
    echo "------------------------------------------------------------------"
    echo "1. Version metadata must already be synced to $version (run"
    echo "   'scripts/release.sh <bump>' first — this script never bumps"
    echo "   versions itself, see 'audit' above to confirm)."
    echo ""
    echo "2. Build (inside the Docker builder container, see"
    echo "   meta-duduclaw/README.md \"Usage\" for how to start it):"
    echo "   docker exec -u 1000 $BUILDER_CONTAINER bash -c \\"
    echo "     \"cd /workspace && kas build $kas_cfg\""
    echo ""
    echo "3. Discover the real deploy dir (never hardcoded/guessed — bitbake"
    echo "   computes it from MACHINE/DISTRO, and it can change):"
    echo "   docker exec -u 1000 $BUILDER_CONTAINER bash -c \\"
    echo "     \"cd /workspace && kas shell $kas_cfg -c \\\""
    echo "      'bitbake -e duduclaw-image | grep ^DEPLOY_DIR_IMAGE='\\\"\""
    echo ""
    echo "4. Once built, collect + sign artifacts:"
    echo "   ./scripts/release-os.sh package v$version --machine $machine"
    echo "------------------------------------------------------------------"
    echo "This subcommand never touches the builder container or the"
    echo "network — it only prints the above."
}

# --- package: collect + sha256sum + minisign + versioned output dir --------
run_package() {
    local version="$1" machine="$2" dry_run="$3" kas_cfg deploy_dir out_dir tmp_dir cid
    kas_cfg="$(kas_config_for_machine "$machine")"
    if [[ -z "$kas_cfg" ]]; then
        echo "Error: unknown machine '$machine' (known: ${DEFAULT_MACHINES[*]})" >&2
        return 1
    fi
    out_dir="artifacts/os/v${version}/${machine}"

    echo "Packaging DuDuClaw OS artifacts: v$version / $machine"
    echo "  Output directory: $out_dir"
    echo "  Signing key:      $OS_SIGN_KEY"

    if $dry_run; then
        echo ""
        echo "[DRY RUN] Would:"
        echo "  1. docker exec -u 1000 $BUILDER_CONTAINER bash -c \\"
        echo "       \"cd /workspace && kas shell $kas_cfg -c \\\""
        echo "        'bitbake -e duduclaw-image | grep ^DEPLOY_DIR_IMAGE='\\\"\""
        echo "     -> resolves the real DEPLOY_DIR_IMAGE (never assumed)"
        echo "  2. Collect *.wic / *.efi (UKI) / kernel modules tarball from"
        echo "     that directory, plus the RPM feed (sibling 'rpm/' dir under"
        echo "     the same DEPLOY_DIR's parent tmp/deploy/)"
        echo "  3. sha256sum every collected file -> $out_dir/SHA256SUMS"
        echo "  4. minisign -S -s $OS_SIGN_KEY -m $out_dir/SHA256SUMS"
        echo "     -> $out_dir/SHA256SUMS.minisig"
        echo "  5. minisign -V -m $out_dir/SHA256SUMS -P $OS_RELEASE_PUBKEY"
        echo "     -> self-verify before declaring success (make-payload.py's"
        echo "        own discipline: a payload that can't prove its own"
        echo "        integrity on the build host must never reach a machine)"
        echo "  6. Write $out_dir/manifest.json (version, machine, build"
        echo "     timestamp, source file list) — convenience provenance,"
        echo "     NOT part of the trust chain (SHA256SUMS + .minisig are)"
        echo ""
        echo "No files were read or written by this dry run."
        return 0
    fi

    # Real path. Fails closed at every step — never fabricates an artifact
    # list, never signs an empty/partial set silently.
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

    echo ""
    echo "Resolving DEPLOY_DIR_IMAGE inside $BUILDER_CONTAINER..."
    deploy_dir="$(docker exec -u 1000 "$BUILDER_CONTAINER" bash -c \
        "cd /workspace && kas shell $kas_cfg -c 'bitbake -e duduclaw-image | grep ^DEPLOY_DIR_IMAGE='" \
        2>/dev/null | sed -E 's/^DEPLOY_DIR_IMAGE="(.*)"$/\1/')"
    if [[ -z "$deploy_dir" ]]; then
        echo "Error: could not resolve DEPLOY_DIR_IMAGE — has 'kas build $kas_cfg'" >&2
        echo "       actually completed for this machine yet?" >&2
        return 1
    fi
    echo "  DEPLOY_DIR_IMAGE = $deploy_dir"

    tmp_dir="$(mktemp -d)"
    mkdir -p "$out_dir"
    # Copy out of the container rather than assuming a host bind-mount path
    # -- meta-duduclaw/README.md's documented run command DOES bind-mount
    # the repo at /workspace, but TMPDIR/build output lives on a Docker
    # named volume (see kas/duduclaw-os.yml's disk-strategy comment), not
    # necessarily reachable from the host filesystem directly.
    if ! docker exec -u 1000 "$BUILDER_CONTAINER" bash -c \
        "find '$deploy_dir' -maxdepth 1 \( -name '*.wic' -o -name '*.efi' -o -name 'rpm' \) -print" \
        > "$tmp_dir/filelist.txt" 2>/dev/null; then
        echo "Error: could not list deploy dir contents inside the container." >&2
        rm -rf "$tmp_dir"
        return 1
    fi
    if [[ ! -s "$tmp_dir/filelist.txt" ]]; then
        echo "Error: no .wic/.efi/rpm artifacts found under $deploy_dir — build" >&2
        echo "       incomplete or wrong machine/version." >&2
        rm -rf "$tmp_dir"
        return 1
    fi
    while IFS= read -r src; do
        docker cp "$BUILDER_CONTAINER:$src" "$out_dir/$(basename "$src")"
    done < "$tmp_dir/filelist.txt"
    rm -rf "$tmp_dir"

    ( cd "$out_dir" && shasum -a 256 -- * > SHA256SUMS )
    if ! minisign -S -s "$OS_SIGN_KEY" -m "$out_dir/SHA256SUMS" -t "DuDuClaw OS v$version ($machine)"; then
        echo "Error: minisign signing failed." >&2
        return 1
    fi
    if ! minisign -V -m "$out_dir/SHA256SUMS" -P "$OS_RELEASE_PUBKEY" >/dev/null; then
        echo "Error: self-verification against OS_RELEASE_PUBKEY failed — a" >&2
        echo "       payload that cannot verify itself must never ship." >&2
        return 1
    fi
    python3 - "$out_dir" "$version" "$machine" <<'PYEOF'
import json, sys, datetime, pathlib
out_dir, version, machine = sys.argv[1], sys.argv[2], sys.argv[3]
files = sorted(p.name for p in pathlib.Path(out_dir).iterdir()
                if p.name not in ("manifest.json",))
manifest = {
    "version": version,
    "machine": machine,
    "generated_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    "files": files,
}
pathlib.Path(out_dir, "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
PYEOF
    echo ""
    echo "Packaged + signed: $out_dir (SHA256SUMS + .minisig verified, manifest.json written)"
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
        shift || true
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --machine) shift; MACHINE="${1:-}" ;;
                *) echo "Error: unknown option '$1'" >&2; exit 1 ;;
            esac
            shift
        done
        if [[ -z "$VERSION" ]]; then
            echo "Error: 'plan' requires a version, e.g. v1.63.0" >&2
            exit 1
        fi
        run_plan "${VERSION#v}" "$MACHINE"
        exit $?
        ;;
    package)
        shift
        VERSION="${1:-}"
        MACHINE="${DEFAULT_MACHINES[0]}"
        DRY_RUN=false
        shift || true
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --machine) shift; MACHINE="${1:-}" ;;
                --dry-run) DRY_RUN=true ;;
                *) echo "Error: unknown option '$1'" >&2; exit 1 ;;
            esac
            shift
        done
        if [[ -z "$VERSION" ]]; then
            echo "Error: 'package' requires a version, e.g. v1.63.0" >&2
            exit 1
        fi
        run_package "${VERSION#v}" "$MACHINE" "$DRY_RUN"
        exit $?
        ;;
    *)
        usage
        exit 1
        ;;
esac
