#!/usr/bin/env bash
# Regenerates files/duduclaw-comp-src/ -- a source snapshot of
# crates/duduclaw-comp. Unlike duduclaw-sysd/duduclaw-cli, this crate needs
# NO Cargo.toml flattening (it's already a standalone cargo project -- its
# own `[workspace]` empty table + hardcoded version/edition, detached from
# the main workspace since it was created because smithay is Linux-only).
# Straight copy + Cargo.lock prune only.
set -euo pipefail

# Source resolution (rewritten 2026-09-29): the three gpui/smithay crates
# (duduclaw-comp among them) moved OUT of the DuDuClaw platform repo into this OS
# repo's own crates/ (2026-09-29 feature audit, S16-B) -- they were always
# `[workspace] exclude`d standalone cargo projects with their own Cargo.lock,
# and nothing in the platform workspace depends on them. So REPO_ROOT is now
# THIS repo (three levels above this script), not a sibling platform
# checkout. DUDUCLAW_OS_SRC_ROOT overrides for a non-standard layout
# (deliberately NOT DUDUCLAW_CLI_SRC_ROOT: sync-platform.sh exports that one
# pointing at the PLATFORM checkout, which no longer holds these crates).
_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -n "${DUDUCLAW_OS_SRC_ROOT:-}" ]]; then
    REPO_ROOT="$DUDUCLAW_OS_SRC_ROOT"
else
    REPO_ROOT="$(cd "$_SCRIPT_DIR/../../.." && pwd)"
fi
if [[ ! -f "$REPO_ROOT/crates/duduclaw-comp/Cargo.toml" ]]; then
    echo "refresh-src: duduclaw-comp source not found at $REPO_ROOT/crates/duduclaw-comp" >&2
    echo "  Since 2026-09-29 it lives in this OS repo's crates/ directory; set" >&2
    echo "  DUDUCLAW_OS_SRC_ROOT only for a non-standard checkout. Refusing to touch the snapshot." >&2
    exit 1
fi
SRC_CRATE="$REPO_ROOT/crates/duduclaw-comp"
OUT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/files/duduclaw-comp-src"

rm -rf "$OUT_DIR"
cp -R "$SRC_CRATE" "$OUT_DIR"
rm -rf "$OUT_DIR/target"
cp "$REPO_ROOT/LICENSE" "$OUT_DIR/LICENSE" 2>/dev/null || true

echo "Wrote $OUT_DIR ($(grep -c '^name = ' "$OUT_DIR/Cargo.lock") packages in Cargo.lock, unpruned)"
echo "NOTE: unlike duduclaw-sysd/duduclaw-cli, this script does NOT run a local"
echo "'cargo build' to prune Cargo.lock or validate the build -- smithay's"
echo "backend_libinput/backend_udev/backend_gbm/backend_session_libseat"
echo "features need Linux system libraries (libinput/libudev/libgbm/libseat"
echo "dev headers) not present on this macOS host. First real build+prune"
echo "signal has to come from bitbake itself (or a Linux dev container with"
echo "those -dev packages installed) -- tracked honestly as unverified in"
echo "the Y2-1 handoff, not silently skipped."
