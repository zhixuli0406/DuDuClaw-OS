#!/usr/bin/env bash
# Regenerates files/duduclaw-shell-src/ and files/duduclaw-native-gui/ -- a
# TWO-crate source snapshot (not a single flattened crate, not a full
# mini-workspace like duduclaw-cli's either). Neither crate needs Cargo.toml
# flattening (both are already standalone cargo projects -- own `[workspace]`
# empty table, same "detached from the main workspace" reasoning as
# duduclaw-comp: gpui pulls the entire zed-industries/zed monorepo plus
# wgpu/metal/font-kit, and the root Cargo.toml's `[workspace] exclude` list
# already accounts for both crates).
#
# Why TWO destsuffixes, not a nested mini-workspace: duduclaw-shell's own
# Cargo.toml has `duduclaw-native-gui = { path = "../duduclaw-native-gui" }`
# -- a SIBLING-directory path dependency, resolved relative to
# duduclaw-shell's own Cargo.toml location. Since duduclaw-native-gui also
# independently declares its own empty `[workspace]` table (see that crate's
# Cargo.toml header comment), cargo does NOT require it to be a workspace
# member of duduclaw-shell -- path dependencies outside a workspace root are
# simply built as ordinary (non-member) dependency packages. This is the
# EXACT setup already tested and working on macOS (`cargo build` inside
# crates/duduclaw-shell today), not a hypothetical -- so the recipe's SRC_URI
# just needs to reproduce the same on-disk sibling relationship: unpack
# duduclaw-shell's own files to `${UNPACKDIR}/duduclaw-shell-src` (S) and
# duduclaw-native-gui's files to `${UNPACKDIR}/duduclaw-native-gui` (the
# LITERAL name the `../duduclaw-native-gui` relative path needs to resolve
# to, sibling of S) via a second `file://` SRC_URI entry.
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
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SHELL_SRC="$REPO_ROOT/crates/duduclaw-shell"
SHELL_OUT="$HERE/files/duduclaw-shell-src"
GUI_SRC="$REPO_ROOT/crates/duduclaw-native-gui"
GUI_OUT="$HERE/files/duduclaw-native-gui"

rm -rf "$SHELL_OUT" "$GUI_OUT"
# --exclude target/: both crates' local dev target/ dirs were measured at
# 7.7G (duduclaw-shell) + 12G (duduclaw-native-gui) on this machine -- a
# naive `cp -R` then `rm -rf .../target` (comp's original refresh-src.sh
# pattern, copied here at first) copies ~20G to disk before deleting it,
# which is what made the first run of this script take minutes instead of
# seconds. rsync skips it outright.
for d in "$SHELL_SRC" "$GUI_SRC"; do [[ -d "$d" ]] || { echo "refresh-src: missing source dir $d" >&2; exit 1; }; done
rsync -a --exclude target "$SHELL_SRC/" "$SHELL_OUT/"
cp "$REPO_ROOT/LICENSE" "$SHELL_OUT/LICENSE" 2>/dev/null || true

rsync -a --exclude target "$GUI_SRC/" "$GUI_OUT/"
cp "$REPO_ROOT/LICENSE" "$GUI_OUT/LICENSE" 2>/dev/null || true

echo "Wrote $SHELL_OUT ($(grep -c '^name = ' "$SHELL_OUT/Cargo.lock") packages in Cargo.lock, unpruned)"
echo "Wrote $GUI_OUT (no separate Cargo.lock -- resolved as part of duduclaw-shell's graph)"
echo "NOTE: like duduclaw-comp's refresh-src.sh, this does NOT run a local 'cargo build' to"
echo "prune Cargo.lock or validate the build -- gpui_linux's wayland backend needs Linux"
echo "system libraries (libwayland/libxkbcommon/fontconfig dev headers, see this crate's"
echo "BUILD-LINUX.md) not present on this macOS host. First real build signal has to come"
echo "from bitbake itself."
