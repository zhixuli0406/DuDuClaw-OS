#!/usr/bin/env bash
# Regenerates files/duduclaw-comp-src/ -- a source snapshot of
# crates/duduclaw-comp. Unlike duduclaw-sysd/duduclaw-cli, this crate needs
# NO Cargo.toml flattening (it's already a standalone cargo project -- its
# own `[workspace]` empty table + hardcoded version/edition, detached from
# the main workspace since it was created because smithay is Linux-only).
# Straight copy + Cargo.lock prune only.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
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
