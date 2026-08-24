#!/usr/bin/env bash
# Build the DuDuClaw OS appliance image (mkosi disk image).
#
# Two independent build phases:
#   1. Produce a Linux `duduclaw` release binary matching APPLIANCE_ARCH
#      (the image target defaults to Debian/x86-64 — the shipping target —
#      regardless of build host; on macOS, `cargo build --release` alone
#      produces a Mach-O binary that's useless inside the image either way).
#   2. Feed that binary into mkosi via --extra-tree=<path>:/usr/local/bin/
#      duduclaw (ExtraTrees= "SOURCE:TARGET" colon-pair CLI syntax,
#      verified against the upstream mkosi manual, 2026-08) and run the
#      actual mkosi build — natively on Linux, via Docker (Dockerfile.
#      mkosi-runner) everywhere else.
#
# Usage:
#   appliance/build.sh                 # builds the binary via Docker, then the image
#   DUDUCLAW_BIN_PATH=/path/to/duduclaw appliance/build.sh   # skip step 1, use an existing Linux binary
#
# Environment variables:
#   APPLIANCE_ARCH=x86-64|arm64  Target architecture (default: x86-64, the
#                                 shipping target). x86-64 is what
#                                 mkosi.conf's [Distribution] Architecture=
#                                 default expects — matches step-1's docker
#                                 build --platform and step-2's mkosi
#                                 --architecture= override. arm64 is for
#                                 building+booting natively on an Apple
#                                 Silicon host (no cross-arch QEMU emulation
#                                 penalty) for local smoke testing only —
#                                 see README.md for which path to use when.
#   DUDUCLAW_SHELL_BIN_PATH=<p>   Prebuilt Linux duduclaw-shell binary (gpui
#                                 shell). Unset -> kiosk shows the Chromium
#                                 dashboard instead. See step 1c.
#   DUDUCLAW_COMP_BIN_PATH=<p>    Prebuilt Linux duduclaw-comp binary (the
#                                 self-built Wayland compositor). Unset ->
#                                 the kiosk session keeps using cage. Only
#                                 meaningful together with the shell. Step 1d.
#   APPLIANCE_STRIP=0             Disable the default `strip --strip-debug`
#                                 applied to the staged copies of the two
#                                 binaries above (step 1b2). Off means a
#                                 bigger root partition footprint; the
#                                 caller's own files are never modified
#                                 either way.
#   CARGO_JOBS=<n>                Caps cargo's build parallelism inside
#                                 step 1's rust-builder Docker stage
#                                 (container/Dockerfile.server's
#                                 CARGO_JOBS build-arg). Defaults to 2 here
#                                 — Docker Desktop's default VM (8GB/4CPU)
#                                 OOMs (SIGKILL, "cannot allocate memory")
#                                 compiling duduclaw-cli + duduclaw-gateway
#                                 in parallel at cargo's own default
#                                 (num-cpus) job count. Raise it if your
#                                 Docker Desktop VM has more memory
#                                 allocated (see README.md).
#   APPLIANCE_BOOT_COUNTING=<n>   sd-boot boot counting on the factory UKI:
#                                 names it duduclaw-os_<ver>+<n>.efi and
#                                 stages /etc/kernel/tries. DEFAULT 3 (H3b,
#                                 2026-08-23 — this is the shipping default
#                                 now, it was OFF through H3a). n must be
#                                 1..9: sd-boot v257 does not zero-pad the
#                                 counter, so a two-digit value shortens the
#                                 filename on each rename, which is the
#                                 non-atomic-rename hazard the Boot Loader
#                                 Specification warns about on FAT32.
#                                 Set to 0 (or "off") to build an image with
#                                 no counting at all — an escape hatch for
#                                 bisecting, not a supported shipping shape.
#                                 THE TWO THINGS THAT MAKE THIS SAFE, both
#                                 landed before the default flipped:
#                                   * systemd-bless-boot is in the image
#                                     (H3a, package `systemd-boot`) — without
#                                     something to CLEAR the counter, every
#                                     boot decrements and a perfectly healthy
#                                     machine rolls itself back on the 3rd
#                                     reboot. Counting half-done is strictly
#                                     worse than no counting.
#                                   * duduclaw-health-check.service (H3c)
#                                     decides what "successful boot" means,
#                                     so blessing is not granted merely for
#                                     reaching sysinit.
#

# Not yet run end-to-end as of this writing (needs a Linux environment +
# long package downloads) — reviewed for syntax (`bash -n`) and
# cross-checked against mkosi's documented CLI/config surface, not
# live-executed. See README.md "Known open points" before relying on it.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APPLIANCE_DIR="$REPO_ROOT/appliance"
OUTPUT_DIR="$APPLIANCE_DIR/mkosi.output"

APPLIANCE_ARCH="${APPLIANCE_ARCH:-x86-64}"
CARGO_JOBS="${CARGO_JOBS:-2}"

# Docker's --platform vocabulary (linux/amd64, linux/arm64) differs from
# mkosi's Architecture= vocabulary (x86-64, arm64) — both are the upstream
# CLI-documented spellings for each tool, so this maps between them rather
# than picking one tool's spelling and hoping the other accepts it too.
case "$APPLIANCE_ARCH" in
    x86-64) DOCKER_PLATFORM="linux/amd64" ;;
    arm64)  DOCKER_PLATFORM="linux/arm64" ;;
    *)
        echo "[build] unsupported APPLIANCE_ARCH=$APPLIANCE_ARCH (expected x86-64 or arm64)" >&2
        exit 1
        ;;
esac

echo "[build] repo root: $REPO_ROOT"
echo "[build] target architecture: $APPLIANCE_ARCH (docker platform: $DOCKER_PLATFORM, cargo jobs: $CARGO_JOBS)"

# --- A/B update layout knobs (H3a) ----------------------------------------
# The image version is the identity everything in the A/B chain agrees on:
# the UKI filename (mkosi.conf UnifiedKernelImageFormat=&e_%v), slot A's
# partition label (mkosi.repart/20-root-a.conf), and systemd-sysupdate's @v
# token. mkosi.version is the single source; read it here so the post-build
# assertions can check the other two against it.
IMAGE_VERSION="$(tr -d '[:space:]' < "$APPLIANCE_DIR/mkosi.version")"
if [[ -z "$IMAGE_VERSION" ]]; then
    echo "[build] appliance/mkosi.version is empty — cannot determine the image version" >&2
    exit 1
fi
echo "[build] image version: $IMAGE_VERSION"

# Boot counting is ON by default as of H3b (2026-08-23) — see the
# APPLIANCE_BOOT_COUNTING note in the usage block above for the two
# preconditions that had to land first (bless-boot in the image; a real
# health gate deciding what "successful" means).
UKI_FORMAT_ARGS=()
BOOT_COUNTING="${APPLIANCE_BOOT_COUNTING-3}"
# An explicitly empty value, 0, or "off" all mean "build without counting".
# `${VAR-3}` (no colon) above is deliberate so that only an *unset* variable
# takes the default and an explicit `APPLIANCE_BOOT_COUNTING=` is honoured as
# the opt-out it reads like.
case "$BOOT_COUNTING" in
    ""|0|off|OFF) BOOT_COUNTING="" ;;
esac
if [[ -n "$BOOT_COUNTING" ]]; then
    if [[ ! "$BOOT_COUNTING" =~ ^[1-9]$ ]]; then
        echo "[build] APPLIANCE_BOOT_COUNTING must be a single digit 1-9, or 0/off (got '$BOOT_COUNTING')" >&2
        exit 1
    fi
    # %v is expanded only when mkosi parses it out of a config FILE; on the
    # command line it stays literal (verified against `mkosi summary`, mkosi
    # 25.3), so the version is substituted here instead. `&c` expands to the
    # contents of /etc/kernel/tries, staged just below.
    UKI_FORMAT_ARGS=("--unified-kernel-image-format=&e_${IMAGE_VERSION}+&c")
    echo "[build] boot counting ARMED: factory UKI will be duduclaw-os_${IMAGE_VERSION}+${BOOT_COUNTING}.efi"
    echo "[build]   (requires systemd-bless-boot in the image to ever clear the counter)"
fi

# --- Step 1: Linux duduclaw binary (arch = $APPLIANCE_ARCH) ---------------
if [[ -n "${DUDUCLAW_BIN_PATH:-}" ]]; then
    if [[ ! -f "$DUDUCLAW_BIN_PATH" ]]; then
        echo "[build] DUDUCLAW_BIN_PATH=$DUDUCLAW_BIN_PATH does not exist" >&2
        exit 1
    fi
    echo "[build] (1/2) using existing binary: $DUDUCLAW_BIN_PATH"
    echo "[build]       (caller-supplied — not verified to match APPLIANCE_ARCH=$APPLIANCE_ARCH)"
else
    echo "[build] (1/2) building linux/$APPLIANCE_ARCH duduclaw release binary via Docker"
    echo "[build]       (reusing container/Dockerfile.server's rust-builder stage —"
    echo "[build]        same pipeline scripts/release.sh already relies on for"
    echo "[build]        linux-x64 pro-binary extraction; no separate build recipe"
    echo "[build]        to keep in sync)"
    # --platform pins the build to $DOCKER_PLATFORM instead of defaulting to
    # the Docker daemon's host platform — without this, a build on Apple
    # Silicon silently produced an aarch64 binary even when the target
    # image (mkosi.conf's [Distribution] Architecture=x86-64) was amd64,
    # which is a binary the built image cannot execute (wrong ELF machine
    # type). --build-arg CARGO_JOBS threads through to Dockerfile.server's
    # ARG CARGO_JOBS="" (see that file) to cap parallel rustc/linker jobs —
    # Docker Desktop's default VM (8GB/4CPU) OOM-kills (SIGKILL) an
    # uncapped `cargo build --release -p duduclaw-cli -p duduclaw-gateway`
    # partway through linking duduclaw-gateway.
    docker build \
        --platform "$DOCKER_PLATFORM" \
        --build-arg "CARGO_JOBS=$CARGO_JOBS" \
        --build-arg "EXTRA_PACKAGES=-p duduclaw-sysd" \
        --target rust-builder \
        -t duduclaw-appliance-rust-builder \
        -f "$REPO_ROOT/container/Dockerfile.server" \
        "$REPO_ROOT"
    CID="$(docker create duduclaw-appliance-rust-builder)"
    trap 'docker rm -f "$CID" >/dev/null 2>&1 || true' EXIT
    mkdir -p "$APPLIANCE_DIR/.build"
    DUDUCLAW_BIN_PATH="$APPLIANCE_DIR/.build/duduclaw"
    docker cp "$CID:/build/target/release/duduclaw" "$DUDUCLAW_BIN_PATH"
    # The privileged helper ships alongside the gateway (duduclaw-sysd.service
    # runs it as root; see mkosi.extra/etc/systemd/system/duduclaw-sysd.service).
    docker cp "$CID:/build/target/release/duduclaw-sysd" "$APPLIANCE_DIR/.build/duduclaw-sysd"
    docker rm -f "$CID" >/dev/null 2>&1 || true
    trap - EXIT
    echo "[build]       extracted: $DUDUCLAW_BIN_PATH (+ duduclaw-sysd)"
fi

# --- Step 1b: vendor the AI CLIs (network here, not in mkosi postinst) -----
# claude-code/codex/gemini-cli come from npm, and mkosi's postinst sandbox
# has no network — so fetch them in a Docker build (which does) and hand the
# resulting /usr/local tree to mkosi as an ExtraTree. --platform must match
# APPLIANCE_ARCH because claude-code ships a native arch-specific launcher.
CLIS_TREE="$APPLIANCE_DIR/.build/clis"
if [[ -z "${SKIP_CLI_VENDOR:-}" ]]; then
    echo "[build] (1b) vendoring AI CLIs (claude-code/codex/gemini-cli) for $APPLIANCE_ARCH"
    docker build \
        --platform "$DOCKER_PLATFORM" \
        -t duduclaw-appliance-cli-vendor \
        -f "$APPLIANCE_DIR/Dockerfile.cli-vendor" \
        "$APPLIANCE_DIR"
    VCID="$(docker create --platform "$DOCKER_PLATFORM" duduclaw-appliance-cli-vendor)"
    trap 'docker rm -f "$VCID" >/dev/null 2>&1 || true' EXIT
    rm -rf "$CLIS_TREE"
    mkdir -p "$CLIS_TREE"
    docker cp "$VCID:/clis/." "$CLIS_TREE/"
    docker rm -f "$VCID" >/dev/null 2>&1 || true
    trap - EXIT
    echo "[build]       vendored: $CLIS_TREE (→ /usr/local in image)"
else
    echo "[build] (1b) SKIP_CLI_VENDOR set — image will lack the AI CLIs"
fi

# --- Step 1b2: staging + optional strip for caller-supplied binaries -------
# The two big binaries this script does NOT build (duduclaw-shell, ~553MB;
# duduclaw-comp, ~146MB as a debug build) are handed in by the caller as
# prebuilt Linux ELFs. Both go on the fixed-size 5G read-only root, which
# was already at ~3.6G before duduclaw-comp existed — so they are staged
# through a copy under .build/staged/ and, by default, `strip --strip-debug`
# is applied to that COPY.
#
#   - The caller's file is never modified. Ever. Staging is a copy first,
#     strip second, and any strip failure restores the copy from the
#     original — a build must not mutate an artifact someone else produced.
#   - `--strip-debug`, NOT plain `strip`/`--strip-all`: it drops the
#     .debug_* sections (the bulk of an unoptimized Rust binary) but keeps
#     .symtab, so a panic backtrace still resolves FUNCTION NAMES. What is
#     lost is file:line resolution in backtraces. That is the deliberate
#     trade: an appliance image with no room for the compositor is a worse
#     debugging position than a backtrace without line numbers.
#   - APPLIANCE_STRIP=0 turns the whole thing off (staging still happens,
#     so the rest of the script has one code path either way).
#   - Fail-open by construction: no usable strip tool, no Docker, no
#     network — every one of those prints a warning and ships the
#     unstripped copy. Stripping is a size optimization, never a build gate.
STAGE_DIR="$APPLIANCE_DIR/.build/staged"
STRIP_IMAGE="duduclaw-appliance-strip:$APPLIANCE_ARCH"

# True when $1 still starts with the ELF magic (7f 45 4c 46) and is
# non-empty — the post-strip sanity check. `head -c` + `od` are used
# because `file(1)` is not guaranteed on a stripped-down build host.
elf_ok() {
    [[ -s "$1" ]] || return 1
    local magic
    magic="$(head -c 4 "$1" | od -An -tx1 | tr -d ' \n')"
    [[ "$magic" == "7f454c46" ]]
}

# Strip $1 in place, returning non-zero if nothing worked. Host binutils
# first (the native-Linux build host case), then a tiny cached Docker image
# built for $DOCKER_PLATFORM — GNU strip is built for one target, so the
# container has to match the IMAGE's architecture, not the build host's.
strip_elf() {
    local f="$1" tool
    for tool in llvm-strip strip; do
        if command -v "$tool" >/dev/null 2>&1; then
            # macOS's /usr/bin/strip is the Mach-O one and simply errors out
            # on an ELF; that's why this is a try-and-verify, not a
            # try-and-assume (and why elf_ok runs after every attempt).
            if "$tool" --strip-debug "$f" 2>/dev/null && elf_ok "$f"; then
                return 0
            fi
        fi
    done
    command -v docker >/dev/null 2>&1 || return 1
    if ! docker image inspect "$STRIP_IMAGE" >/dev/null 2>&1; then
        printf 'FROM debian:trixie-slim\nRUN apt-get update && apt-get install -y --no-install-recommends binutils && rm -rf /var/lib/apt/lists/*\n' \
            | docker build --platform "$DOCKER_PLATFORM" -t "$STRIP_IMAGE" - >/dev/null 2>&1 || return 1
    fi
    # Bind mount is fine HERE (unlike the mkosi runner below, which avoids
    # them because Docker Desktop misreports permission bits on macOS):
    # only the file CONTENT crosses the boundary, and every consumer below
    # re-chmods explicitly.
    docker run --rm --platform "$DOCKER_PLATFORM" \
        -v "$STAGE_DIR:/stage" "$STRIP_IMAGE" \
        strip --strip-debug "/stage/${f##*/}" >/dev/null 2>&1 || return 1
    elf_ok "$f"
}

# stage_binary <source-path> <basename> — prints the staged path on stdout;
# all human-facing output goes to stderr so the caller can capture it.
stage_binary() {
    local src="$1" name="$2" dest="$STAGE_DIR/$2" before after
    mkdir -p "$STAGE_DIR"
    cp "$src" "$dest"
    chmod 755 "$dest"
    if [[ "${APPLIANCE_STRIP:-1}" == "0" ]]; then
        echo "[build]       $name: APPLIANCE_STRIP=0 — staged unstripped ($(wc -c < "$dest") bytes)" >&2
        printf '%s' "$dest"
        return 0
    fi
    before="$(wc -c < "$dest")"
    if strip_elf "$dest"; then
        after="$(wc -c < "$dest")"
        chmod 755 "$dest"
        echo "[build]       $name: stripped $before -> $after bytes (--strip-debug; symbol names kept)" >&2
    else
        cp "$src" "$dest"
        chmod 755 "$dest"
        echo "[build]       WARNING: $name could not be stripped (no usable strip tool / docker) — shipping $before bytes unstripped" >&2
    fi
    printf '%s' "$dest"
}

# --- Step 1c: DuDuClaw OS gpui shell (optional, Shell-S2 wave) -------------
# The native shell is built from the detached `crates/duduclaw-shell`
# workspace (gpui pulls the whole zed monorepo — deliberately NOT rebuilt
# by this script; the one-shot container build lives in
# crates/duduclaw-shell/BUILD-LINUX.md). Pass a prebuilt Linux binary in:
#   DUDUCLAW_SHELL_BIN_PATH=/path/to/duduclaw-shell appliance/build.sh
# When set, the image ships it at /usr/local/bin/duduclaw-shell and the
# kiosk session runs the shell instead of the Chromium dashboard (see
# mkosi.extra/usr/local/sbin/duduclaw-kiosk-launch.sh's selection order,
# incl. the /etc/duduclaw/kiosk-app escape hatch). When unset, nothing
# changes: Chromium kiosk, byte-identical to before this step existed.
STAGED_SHELL_BIN=""
if [[ -n "${DUDUCLAW_SHELL_BIN_PATH:-}" ]]; then
    if [[ ! -f "$DUDUCLAW_SHELL_BIN_PATH" ]]; then
        echo "[build] DUDUCLAW_SHELL_BIN_PATH=$DUDUCLAW_SHELL_BIN_PATH does not exist" >&2
        exit 1
    fi
    echo "[build] (1c) shell binary: $DUDUCLAW_SHELL_BIN_PATH → /usr/local/bin/duduclaw-shell (kiosk runs the gpui shell)"
    echo "[build]       (caller-supplied — not verified to match APPLIANCE_ARCH=$APPLIANCE_ARCH)"
    STAGED_SHELL_BIN="$(stage_binary "$DUDUCLAW_SHELL_BIN_PATH" duduclaw-shell)"
else
    echo "[build] (1c) DUDUCLAW_SHELL_BIN_PATH unset — kiosk stays on the Chromium dashboard"
fi

# --- Step 1d: DuDuClaw OS compositor (optional, A4 wave) -------------------
# duduclaw-comp is DuDuClaw OS's own Wayland compositor (smithay-based; see
# crates/duduclaw-comp/BUILD.md). Like the shell it lives in a DETACHED
# workspace and is deliberately NOT rebuilt here — hand in a prebuilt Linux
# binary matching APPLIANCE_ARCH:
#   DUDUCLAW_COMP_BIN_PATH=/path/to/duduclaw-comp appliance/build.sh
# When set, the image ships it at /usr/local/bin/duduclaw-comp and the kiosk
# session prefers it over cage as the session compositor, with an automatic
# fallback to the cage path when it fails to come up (full decision tree +
# escape hatches: mkosi.extra/usr/local/sbin/duduclaw-kiosk-launch.sh).
# When unset, nothing changes: the binary is simply absent and the launch
# script's selection lands on exactly the pre-A4 behavior.
#
# Note it is only ever USED together with the shell — comp with no client
# would be a blank screen — but the two variables are kept independent so
# an image can be built with the shell alone (the verified Shell-S2 shape)
# without this step having an opinion about it.
STAGED_COMP_BIN=""
if [[ -n "${DUDUCLAW_COMP_BIN_PATH:-}" ]]; then
    if [[ ! -f "$DUDUCLAW_COMP_BIN_PATH" ]]; then
        echo "[build] DUDUCLAW_COMP_BIN_PATH=$DUDUCLAW_COMP_BIN_PATH does not exist" >&2
        exit 1
    fi
    echo "[build] (1d) compositor binary: $DUDUCLAW_COMP_BIN_PATH → /usr/local/bin/duduclaw-comp (kiosk prefers duduclaw-comp over cage)"
    echo "[build]       (caller-supplied — not verified to match APPLIANCE_ARCH=$APPLIANCE_ARCH)"
    if [[ -z "${DUDUCLAW_SHELL_BIN_PATH:-}" ]]; then
        echo "[build]       WARNING: DUDUCLAW_SHELL_BIN_PATH is unset — duduclaw-comp will be installed but never selected" >&2
        echo "[build]                (the launch script only picks comp when the shell is present to be its client)" >&2
    fi
    STAGED_COMP_BIN="$(stage_binary "$DUDUCLAW_COMP_BIN_PATH" duduclaw-comp)"
else
    echo "[build] (1d) DUDUCLAW_COMP_BIN_PATH unset — kiosk compositor stays on cage"
fi

# --- Step 1e: DuDuClaw brand cursor theme (CUR-2 wave) ---------------------
# A prebuilt XCursor theme (crates/duduclaw-comp/assets/cursors/DuDuClaw —
# built artifacts checked into the repo, because this image-build environment
# has neither rsvg-convert nor xcursorgen; build-theme.sh in the same dir
# regenerates them from the SVG masters). Installing it does NOT enable it:
# the session default stays the system cursor (user decision, 2026-08-22);
# the theme only takes effect when comp is switched to `brand` via the
# shell-control op or DUDUCLAW_COMP_CURSOR_SOURCE. `cp -a` matters — the
# theme's legacy-name entries (arrow → default, openhand → grab, …) are
# symlinks, and flattening them would triple the payload and break nothing
# visibly until a legacy-name lookup silently resolved to a stale copy.
CURSOR_THEME_SRC="$REPO_ROOT/crates/duduclaw-comp/assets/cursors/DuDuClaw"
STAGED_CURSOR_THEME=""
if [[ -d "$CURSOR_THEME_SRC" ]]; then
    STAGED_CURSOR_THEME="$APPLIANCE_DIR/.build/staged/cursor-theme"
    rm -rf "$STAGED_CURSOR_THEME"
    mkdir -p "$STAGED_CURSOR_THEME"
    cp -a "$CURSOR_THEME_SRC" "$STAGED_CURSOR_THEME/DuDuClaw"
    echo "[build] (1e) brand cursor theme staged → /usr/share/icons/DuDuClaw (installed, NOT default)"
else
    # In-repo asset, so this only happens on a mutilated checkout — warn
    # rather than fail: the image is fully functional on the system cursor.
    echo "[build] (1e) WARNING: $CURSOR_THEME_SRC not found — image will lack the brand cursor theme" >&2
fi

# --- Step 1f: boot-counting tries file (H3a, opt-in) ----------------------
# mkosi's `&c` UKI-filename specifier expands to the contents of
# /etc/kernel/tries inside the image, so arming boot counting means shipping
# that file. Staged (not committed under mkosi.extra/) precisely so the image
# cannot acquire boot counting by accident — it exists only for a build that
# explicitly asked for it.
STAGED_TRIES_TREE=""
if [[ -n "$BOOT_COUNTING" ]]; then
    STAGED_TRIES_TREE="$APPLIANCE_DIR/.build/staged/boot-counting"
    rm -rf "$STAGED_TRIES_TREE"
    mkdir -p "$STAGED_TRIES_TREE/etc/kernel"
    printf '%s\n' "$BOOT_COUNTING" > "$STAGED_TRIES_TREE/etc/kernel/tries"
    echo "[build] (1f) staged /etc/kernel/tries = $BOOT_COUNTING"
fi

# --- Step 2: mkosi build ---------------------------------------------------
mkdir -p "$OUTPUT_DIR"

HOST_OS="$(uname -s)"
if [[ "$HOST_OS" == "Linux" ]]; then
    echo "[build] (2/2) native Linux host — running mkosi directly"
    if ! command -v mkosi >/dev/null 2>&1; then
        echo "[build] mkosi not found on PATH. Install it first, e.g.:" >&2
        echo "[build]   apt-get install mkosi   (Debian/Ubuntu)" >&2
        echo "[build]   dnf install mkosi        (Fedora)" >&2
        exit 1
    fi
    # --architecture= is passed explicitly (not left to mkosi.conf's own
    # [Distribution] Architecture=x86-64 default) so the actual target is
    # never implicit — CLI-configured settings always override
    # file-configured ones (mkosi manual, config parsing order), so this
    # is safe to pass even when APPLIANCE_ARCH matches the file default.
    # OPTIONS BEFORE THE VERB (bitten for real, 2026-08-18): mkosi's usage
    # is `mkosi [options…] build [command line…]` — anything AFTER `build`
    # is treated as the build-script command line and silently swallowed,
    # which produced a full amd64 tree from an "--architecture=arm64" run.
    NATIVE_CLI_TREE_ARG=()
    if [[ -d "$CLIS_TREE" ]]; then
        NATIVE_CLI_TREE_ARG=("--extra-tree=${CLIS_TREE}:/usr/local")
    fi
    # Both of these point at the STAGED copies (step 1b2), never at the
    # caller's own file — that's what makes the optional strip safe.
    NATIVE_SHELL_TREE_ARG=()
    if [[ -n "$STAGED_SHELL_BIN" ]]; then
        NATIVE_SHELL_TREE_ARG=("--extra-tree=${STAGED_SHELL_BIN}:/usr/local/bin/duduclaw-shell")
    fi
    NATIVE_COMP_TREE_ARG=()
    if [[ -n "$STAGED_COMP_BIN" ]]; then
        NATIVE_COMP_TREE_ARG=("--extra-tree=${STAGED_COMP_BIN}:/usr/local/bin/duduclaw-comp")
    fi
    NATIVE_CURSOR_TREE_ARG=()
    if [[ -n "$STAGED_CURSOR_THEME" ]]; then
        NATIVE_CURSOR_TREE_ARG=("--extra-tree=${STAGED_CURSOR_THEME}/DuDuClaw:/usr/share/icons/DuDuClaw")
    fi
    NATIVE_TRIES_TREE_ARG=()
    if [[ -n "$STAGED_TRIES_TREE" ]]; then
        NATIVE_TRIES_TREE_ARG=("--extra-tree=${STAGED_TRIES_TREE}:/")
    fi
    # APPLIANCE_DEBUG=1 sets a root password so you can log in on the serial
    # console (`root` / the value of APPLIANCE_DEBUG_PASSWORD, default
    # "duduclaw") to inspect the running VM — journalctl, systemctl status,
    # etc. DEFAULT OFF: a shipping image keeps root locked (no password).
    DEBUG_ARGS=()
    if [[ -n "${APPLIANCE_DEBUG:-}" ]]; then
        DEBUG_ARGS=(--root-password="${APPLIANCE_DEBUG_PASSWORD:-duduclaw}")
        echo "[build] APPLIANCE_DEBUG set — serial root login enabled (NOT for shipping)"
    fi
    # --force: rebuild even if mkosi.output/ already holds a previous image
    # (otherwise mkosi prints "Output path ... exists already" and skips).
    (cd "$APPLIANCE_DIR" && mkosi \
        --force \
        "--architecture=${APPLIANCE_ARCH}" \
        "--extra-tree=${DUDUCLAW_BIN_PATH}:/usr/local/bin/duduclaw" \
        "${NATIVE_CLI_TREE_ARG[@]}" \
        "${NATIVE_SHELL_TREE_ARG[@]}" \
        "${NATIVE_COMP_TREE_ARG[@]}" \
        "${NATIVE_CURSOR_TREE_ARG[@]}" \
        "${NATIVE_TRIES_TREE_ARG[@]}" \
        "${UKI_FORMAT_ARGS[@]}" \
        "${DEBUG_ARGS[@]}" \
        build)
else
    echo "[build] (2/2) non-Linux host ($HOST_OS) — running mkosi inside Docker"
    echo "[build]       (Dockerfile.mkosi-runner; --privileged for loop/mount access —"
    echo "[build]        RepartOffline= defaults to enabled, which mkosi's own docs say"
    echo "[build]        should avoid *needing* this, but Docker Desktop's VM makes"
    echo "[build]        --privileged cheap insurance rather than something to prove"
    echo "[build]        unnecessary on the first attempt)"
    docker build -t duduclaw-mkosi-runner -f "$APPLIANCE_DIR/Dockerfile.mkosi-runner" "$APPLIANCE_DIR"
    # NO bind mounts here, on purpose (first real run, 2026-08-18): Docker
    # Desktop's macOS file sharing misreports permission bits on mounted
    # files (mkosi.version showed up executable inside the container, so
    # mkosi tried to *run* it per its exec-bit rule and died on
    # PermissionError) — and the same lie would leak into the built image's
    # file modes via ExtraTrees. `docker cp` streams a tar with the host's
    # true modes, so we copy the sources in, run mkosi against the
    # container's own filesystem, and copy the output back out.
    # OPTIONS BEFORE THE VERB — same trap as the native branch above:
    # args after `build` are silently swallowed as the build-script
    # command line (this produced one full amd64 image from an arm64 run
    # before being caught).
    # APPLIANCE_DEBUG=1 → serial root login for VM inspection (default off,
    # shipping image keeps root locked). See the native branch above.
    DEBUG_ARGS=()
    if [[ -n "${APPLIANCE_DEBUG:-}" ]]; then
        DEBUG_ARGS=(--root-password="${APPLIANCE_DEBUG_PASSWORD:-duduclaw}")
        echo "[build] APPLIANCE_DEBUG set — serial root login enabled (NOT for shipping)"
    fi
    CID="$(docker create --privileged \
        -w /workspace/appliance \
        duduclaw-mkosi-runner \
        --force \
        "--architecture=${APPLIANCE_ARCH}" \
        "--extra-tree=/workspace/bin-tree:/" \
        "${UKI_FORMAT_ARGS[@]}" \
        "${DEBUG_ARGS[@]}" \
        build)"
    trap 'docker rm -f "$CID" >/dev/null 2>&1 || true' EXIT
    # Copy ONLY the mkosi sources into the container — NOT mkosi.output/ (the
    # 12.5G raw from a prior run) or .build/ (binaries + logs). Copying those
    # in both wasted the VM's disk (a second 12.5G raw) and made mkosi see an
    # existing output and skip the build. rsync --exclude stages a clean tree.
    SRC_STAGE="$(mktemp -d)"
    # `.vm` joined the exclude list 2026-08-20: run-vm.sh keeps its 13G
    # persistent working disk (plus logs/screenshots) there, and copying it
    # into the runner container filled Docker Desktop's VM disk ("no space
    # left on device") — the dir didn't exist yet when this staging step was
    # first written, so the trap only fired once VM testing had happened.
    rsync -a --exclude 'mkosi.output' --exclude '.build' --exclude '.vm' \
        "$APPLIANCE_DIR/" "$SRC_STAGE/appliance/"
    # mkosi writes into mkosi.output/ only if that dir EXISTS; since the
    # rsync above excluded the (stale, huge) host copy, recreate it empty so
    # the build output lands where the docker cp-back below looks for it —
    # otherwise mkosi writes duduclaw-os.raw into the CWD and the copy-back
    # finds nothing.
    mkdir -p "$SRC_STAGE/appliance/mkosi.output"
    docker cp "$SRC_STAGE/appliance" "$CID:/workspace"    # → /workspace/appliance
    rm -rf "$SRC_STAGE"
    BIN_TREE="$(mktemp -d)"
    mkdir -p "$BIN_TREE/usr/local/bin"
    cp "$DUDUCLAW_BIN_PATH" "$BIN_TREE/usr/local/bin/duduclaw"
    chmod 755 "$BIN_TREE/usr/local/bin/duduclaw"
    if [[ -f "$APPLIANCE_DIR/.build/duduclaw-sysd" ]]; then
        cp "$APPLIANCE_DIR/.build/duduclaw-sysd" "$BIN_TREE/usr/local/bin/duduclaw-sysd"
        chmod 755 "$BIN_TREE/usr/local/bin/duduclaw-sysd"
    else
        # Caller-supplied DUDUCLAW_BIN_PATH path skips step 1, so the helper
        # may be absent — the unit would then fail visibly at boot. Warn, do
        # not fabricate.
        echo "[build] WARNING: duduclaw-sysd binary not found; image will lack the privileged helper" >&2
    fi
    # Fold the vendored AI CLIs into the same staging tree at /usr/local
    # (step 1b produced /clis with bin/ + lib/node_modules/; cp -a preserves
    # the relative symlinks so /usr/local/bin/{claude,codex,gemini} resolve).
    if [[ -d "$CLIS_TREE" ]]; then
        cp -a "$CLIS_TREE/." "$BIN_TREE/usr/local/"
    fi
    # Steps 1c/1d: the gpui shell and the compositor, when supplied (see the
    # validation blocks above step 2 — the kiosk launch script switches on
    # their presence). Copied from the STAGED path, not the caller's file.
    if [[ -n "$STAGED_SHELL_BIN" ]]; then
        cp "$STAGED_SHELL_BIN" "$BIN_TREE/usr/local/bin/duduclaw-shell"
        chmod 755 "$BIN_TREE/usr/local/bin/duduclaw-shell"
    fi
    if [[ -n "$STAGED_COMP_BIN" ]]; then
        cp "$STAGED_COMP_BIN" "$BIN_TREE/usr/local/bin/duduclaw-comp"
        chmod 755 "$BIN_TREE/usr/local/bin/duduclaw-comp"
    fi
    # Step 1e: the brand cursor theme rides the same single extra-tree —
    # cp -a preserves its legacy-name symlinks (see the staging block above).
    if [[ -n "$STAGED_CURSOR_THEME" ]]; then
        mkdir -p "$BIN_TREE/usr/share/icons"
        cp -a "$STAGED_CURSOR_THEME/DuDuClaw" "$BIN_TREE/usr/share/icons/DuDuClaw"
    fi
    # Step 1f: /etc/kernel/tries rides the same single extra-tree (the docker
    # branch passes exactly one --extra-tree, unlike the native branch).
    if [[ -n "$STAGED_TRIES_TREE" ]]; then
        mkdir -p "$BIN_TREE/etc/kernel"
        cp "$STAGED_TRIES_TREE/etc/kernel/tries" "$BIN_TREE/etc/kernel/tries"
    fi
    docker cp "$BIN_TREE" "$CID:/workspace/bin-tree"      # → /workspace/bin-tree/usr/local/bin/duduclaw
    rm -rf "$BIN_TREE"
    docker start -a "$CID" || { docker rm -f "$CID" >/dev/null 2>&1; trap - EXIT; echo "[build] mkosi failed" >&2; exit 1; }
    mkdir -p "$OUTPUT_DIR"
    docker cp "$CID:/workspace/appliance/mkosi.output/." "$OUTPUT_DIR/"
    docker rm -f "$CID" >/dev/null 2>&1 || true
    trap - EXIT
fi

# --- Step 3: A/B layout assertions + per-slot UKI derivation (H3a) --------
# Everything the A/B update chain depends on is checked here against the
# artifact that was actually produced, not against the config that was meant
# to produce it. Each assertion covers a failure that is invisible until an
# update is attempted on a real box:
#   * slot A's partition label must equal duduclaw-os_<version> and slot B's
#     must be `_empty`, or systemd-sysupdate sees no installed version and no
#     free slot;
#   * the ESP's UKI must be named duduclaw-os_<version>.efi, or the UKI
#     transfer's MatchPattern never matches it;
#   * the UKI's baked root=PARTUUID= must be slot A's, or a rollback boots a
#     kernel against the wrong root.
# Then the slot-B twin of the UKI is derived (identical bytes, slot B's
# PARTUUID) — that pair is what the future signed payload pipeline (H3d) will
# sign and ship. See appliance/tools/uki-slots.py.
UKI_OUT="$OUTPUT_DIR/duduclaw-os.efi"
RAW_OUT="$OUTPUT_DIR/duduclaw-os.raw"
if [[ -f "$RAW_OUT" && -f "$UKI_OUT" ]]; then
    echo "[build] (3/3) verifying A/B layout and deriving per-slot UKIs"
    python3 "$APPLIANCE_DIR/tools/uki-slots.py" \
        --raw "$RAW_OUT" \
        --uki "$UKI_OUT" \
        --version "$IMAGE_VERSION" \
        --outdir "$OUTPUT_DIR"
else
    # Not a soft warning: without these two artifacts nothing above was
    # actually produced, and silently "succeeding" here is how a broken build
    # reaches a flash drive.
    echo "[build] expected $RAW_OUT and $UKI_OUT after the mkosi build; one or both are missing" >&2
    exit 1
fi

# --- Step 3.5: shipping root-lock assertion (Q1, 2026-08-24) --------------
# Static analysis established this invariant but it was never checked
# against a real built artifact until now (see the Q1 row in
# commercial/docs/TODO-agent-first-os-2026-08.md and the precedent recorded
# at crates/duduclaw-shell/BUILD-LINUX.md:483): `--root-password` is set
# ONLY in the two APPLIANCE_DEBUG branches above (this file); nothing in
# mkosi.conf/mkosi.conf.d/postinst.d/mkosi.extra ever touches /etc/shadow.
# A shipping build (no APPLIANCE_DEBUG) must therefore always produce a
# locked root account — asserted here against slot A's actual filesystem
# so a future accidental `chpasswd`/`passwd` call anywhere in the tree
# fails the build instead of shipping a silent backdoor. Reuses the same
# losetup+manual-mknod idiom as appliance/tests/ab-update/inject-binaries.sh
# (no udev inside the container, so partition device nodes must be created
# by hand from sysfs).
if [[ -z "${APPLIANCE_DEBUG:-}" ]]; then
    echo "[build] (3.5) asserting shipping root is locked (no APPLIANCE_DEBUG)"
    ROOT_SHADOW_LINE="$(docker run --rm --privileged --platform "$DOCKER_PLATFORM" \
        -v "$RAW_OUT:/image.raw:ro" \
        debian:trixie-slim bash -euo pipefail -c '
            apt-get update -qq >/dev/null
            apt-get install -y -qq --no-install-recommends util-linux e2fsprogs >/dev/null
            mkdir -p /mnt/root
            LOOP="$(losetup -fP --show /image.raw)"
            sleep 1
            partprobe "$LOOP" >/dev/null 2>&1 || true
            for i in 1 2 3 4; do
                SYSP="/sys/class/block/$(basename "$LOOP")/$(basename "$LOOP")p$i"
                if [ -d "$SYSP" ]; then
                    DEVNUM=$(cat "$SYSP/dev"); MAJ=${DEVNUM%:*}; MIN=${DEVNUM#*:}
                    [ -e "${LOOP}p$i" ] || mknod "${LOOP}p$i" b "$MAJ" "$MIN"
                fi
            done
            # p2 = slot A (p1 = ESP, per mkosi.repart/10-esp.conf sorting
            # before 20-root-a.conf) — same slot inject-binaries.sh targets.
            mount -o ro "${LOOP}p2" /mnt/root
            grep "^root:" /mnt/root/etc/shadow
            umount /mnt/root
            losetup -d "$LOOP"
        ' 2>/dev/null)"
    if [[ -z "$ROOT_SHADOW_LINE" ]]; then
        echo "[build] shipping root-lock check FAILED: could not read /etc/shadow from the built image (see above for the container's stderr)" >&2
        exit 1
    fi
    echo "[build]       /etc/shadow root line: $ROOT_SHADOW_LINE"
    # shadow(5): a locked/disabled account's password field is `*` or a
    # leading `!` (optionally `!` + an old hash, from `passwd -l`). Anything
    # else — a bare `$id$...` hash, or an empty field (no password at all,
    # which is worse) — means the shipping image has a usable root login.
    ROOT_PW_FIELD="$(echo "$ROOT_SHADOW_LINE" | cut -d: -f2)"
    case "$ROOT_PW_FIELD" in
        '*'|'!'*) echo "[build]       root is locked (password field: $ROOT_PW_FIELD) — OK" ;;
        *)
            echo "[build] SHIPPING SAFETY VIOLATION: root password field is '$ROOT_PW_FIELD' (not locked) in a non-APPLIANCE_DEBUG build — refusing to ship" >&2
            exit 1
            ;;
    esac
else
    echo "[build] (3.5) APPLIANCE_DEBUG set — skipping root-lock assertion (root is expected to have a password in this build)"
fi

# --- Step 4: signed A/B update payload (H3d) -----------------------------
# Opt-in, because it is a RELEASE step, not a build step: it costs a full
# 5 GiB pass over the image and it touches the OS signing key, neither of
# which belongs in every local smoke build.
#
#   APPLIANCE_MAKE_PAYLOAD=1 appliance/build.sh
#
# What it produces (appliance/tools/make-payload.py writes the layout; the
# names are the ones mkosi.extra/etc/sysupdate.d/*.transfer match on, so a
# payload this step emits is a payload sysupdate can find):
#
#   mkosi.output/payload/duduclaw-os_<ver>/
#       duduclaw-os_<ver>.root-<arch>.raw   slot A's bytes, written sparsely
#       duduclaw-os_<ver>.efi               the UKI template
#       SHA256SUMS                          both files
#       SHA256SUMS.minisig                  the ONLY signature, OS key
#       manifest.json                       provenance, deliberately unsigned
#
# The UKI is a *template*: its baked root=PARTUUID= belongs to this build's
# own slot A, and mkosi seeds repart with a fresh random UUID per build, so
# that value is meaningless on any other machine. The appliance rewrites
# those 36 characters to its own destination slot at staging time
# (crates/duduclaw-gateway/src/uki_patch.rs). See the H3d note in
# 20-duduclaw-uki.transfer.
if [[ "${APPLIANCE_MAKE_PAYLOAD:-0}" == "1" ]]; then
    echo "[build] (4/4) building the signed A/B update payload"
    python3 "$APPLIANCE_DIR/tools/make-payload.py" \
        --raw "$RAW_OUT" \
        --uki "$UKI_OUT" \
        --version "$IMAGE_VERSION" \
        --force
fi

echo "[build] done. Output in: $OUTPUT_DIR"
ls -la "$OUTPUT_DIR" 2>/dev/null || true
