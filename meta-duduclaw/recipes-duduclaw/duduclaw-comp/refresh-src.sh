#!/usr/bin/env bash
# Regenerates files/duduclaw-comp-src/ -- a source snapshot of
# crates/duduclaw-comp. Unlike duduclaw-sysd/duduclaw-cli, this crate needs
# NO Cargo.toml flattening (it's already a standalone cargo project -- its
# own `[workspace]` empty table + hardcoded version/edition, detached from
# the main workspace since it was created because smithay is Linux-only).
# Straight copy + Cargo.lock prune only.
set -euo pipefail

# Cross-repo source resolution (2026-09-05, same contract as duduclaw-cli's
# refresh-src.sh): the Rust workspace lives in the DuDuClaw platform repo,
# not here. DUDUCLAW_CLI_SRC_ROOT overrides; otherwise try the monorepo
# layout (this script three levels below a checkout that has crates/) and
# fall back to a sibling checkout named DuDuClaw next to this OS repo.
_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -n "${DUDUCLAW_CLI_SRC_ROOT:-}" ]]; then
    REPO_ROOT="$DUDUCLAW_CLI_SRC_ROOT"
elif [[ -d "$_SCRIPT_DIR/../../../crates" ]]; then
    REPO_ROOT="$(cd "$_SCRIPT_DIR/../../.." && pwd)"          # monorepo
else
    REPO_ROOT="$(cd "$_SCRIPT_DIR/../../../.." && pwd)/DuDuClaw"  # split: sibling checkout
fi
if [[ ! -d "$REPO_ROOT/crates" ]]; then
    echo "refresh-src: platform workspace not found at $REPO_ROOT/crates" >&2
    echo "  Check out github.com/zhixuli0406/DuDuClaw as 'DuDuClaw' next to this OS repo," >&2
    echo "  or set DUDUCLAW_CLI_SRC_ROOT to its path. Refusing to touch the snapshot." >&2
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
