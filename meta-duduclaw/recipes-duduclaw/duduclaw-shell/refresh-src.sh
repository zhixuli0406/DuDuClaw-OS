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

# Source resolution (rewritten 2026-09-29): the three gpui/smithay crates
# (duduclaw-shell among them) moved OUT of the DuDuClaw platform repo into this OS
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
if [[ ! -f "$REPO_ROOT/crates/duduclaw-shell/Cargo.toml" ]]; then
    echo "refresh-src: duduclaw-shell source not found at $REPO_ROOT/crates/duduclaw-shell" >&2
    echo "  Since 2026-09-29 it lives in this OS repo's crates/ directory; set" >&2
    echo "  DUDUCLAW_OS_SRC_ROOT only for a non-standard checkout. Refusing to touch the snapshot." >&2
    exit 1
fi
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SHELL_SRC="$REPO_ROOT/crates/duduclaw-shell"
SHELL_OUT="$HERE/files/duduclaw-shell-src"
GUI_SRC="$REPO_ROOT/crates/duduclaw-native-gui"
GUI_OUT="$HERE/files/duduclaw-native-gui"

# Fail closed on a stale detached lockfile (2026-09-08, fix14 bake): the
# platform's release.sh bumps every Cargo.toml and each excluded crate's OWN
# self-version entry in its sibling Cargo.lock, but duduclaw-shell's lock also
# carries duduclaw-native-gui (a path dependency) and that entry was left at
# the old version. Vendored as-is, bitbake's `cargo build --frozen` cannot
# re-sync the lock, treats native-gui's deps as unlocked, tries to load the
# zed git source and dies with "Unable to update https://github.com/
# zed-industries/zed ... offline mode (--frozen)". Cheap to catch here:
# every path package in the lock must carry its manifest's version.
for crate in duduclaw-shell duduclaw-native-gui; do
    manifest_ver="$(sed -n 's/^version = "\(.*\)"/\1/p' "$REPO_ROOT/crates/$crate/Cargo.toml" | head -1)"
    lock_ver="$(awk -v n="$crate" '$0 == "name = \"" n "\"" { getline; sub(/^version = "/, ""); sub(/"$/, ""); print; exit }' "$SHELL_SRC/Cargo.lock")"
    if [[ -z "$manifest_ver" || -z "$lock_ver" ]]; then
        echo "refresh-src: could not read $crate version (manifest='$manifest_ver' lock='$lock_ver')" >&2
        exit 1
    fi
    if [[ "$manifest_ver" != "$lock_ver" ]]; then
        echo "refresh-src: $SHELL_SRC/Cargo.lock has $crate $lock_ver but crates/$crate/Cargo.toml says $manifest_ver." >&2
        echo "  The detached lockfile is stale (release.sh bump did not re-sync it). Run" >&2
        echo "    (cd $SHELL_SRC && cargo metadata --offline --format-version 1 >/dev/null)" >&2
        echo "  commit the Cargo.lock change, then re-run this script. Refusing to vendor a lock that --frozen cannot build." >&2
        exit 1
    fi
done

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
