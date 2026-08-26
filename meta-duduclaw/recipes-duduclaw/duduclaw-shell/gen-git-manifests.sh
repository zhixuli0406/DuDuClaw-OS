#!/usr/bin/env bash
# gen-git-manifests.sh -- regenerates files/duduclaw-shell-git-manifests/,
# a small set of NORMALIZED (workspace-inheritance-resolved) Cargo.toml
# snapshots for the 26 zed-monorepo/wasm_thread/font-kit/scap git-sourced
# crates gen-git-deps.py already fetches raw via bitbake's git subpath
# fetcher.
#
# --- Why this exists (Y3-2/Y3-4, 2026-08-26 real build failure) ----------
# `bitbake duduclaw-image-flatpak` failed duduclaw-shell's do_compile with:
#   error: failed to load source for dependency `collections`
#   Caused by: failed to parse manifest at ".../sources/collections/Cargo.toml"
#   Caused by: error inheriting `edition` from workspace root manifest's
#              `workspace.package.edition`
#   Caused by: failed to find a workspace root
#
# Root cause: zed's own crates use Cargo workspace inheritance
# (`edition.workspace = true`, `[lints] workspace = true`,
# `foo.workspace = true` under [dependencies] for many deps) -- valid ONLY
# when the crate's Cargo.toml is read from inside its real workspace, where
# a workspace-root Cargo.toml's `[workspace.package]`/`[workspace.lints]`/
# `[workspace.dependencies]` are reachable a few directories up. This
# layer's SRC_URI git-fetches each crate via `subpath=crates/<name>`,
# which extracts ONLY that subdirectory -- the workspace root is never
# present on disk at all, so cargo cannot resolve ANY `.workspace = true`
# reference and hard-errors before compiling a single line.
#
# --- Why not "just switch the whole recipe to `cargo vendor`" ------------
# That was considered and rejected for THIS recipe's ~700 crates.io deps
# already (duduclaw-shell-crates.inc's own `cargo-update-recipe-crates`
# per-crate `crate://` mechanism, matching duduclaw-sysd/-cli/-comp) --
# see gen-git-deps.py's own header comment for the full reasoning (opaque
# blob, no per-crate SRCREV audit trail, still needs
# cargo_common_do_patch_paths underneath for the git-sourced subset
# anyway). That reasoning is still correct and is NOT reversed here.
#
# What actually breaks is narrower: `cargo_common_do_patch_paths`
# (openembedded-core/meta/classes-recipe/cargo_common.bbclass) generates
# its `[patch."<repo-url>"]` Cargo config entries ONLY for SRC_URI entries
# whose fetcher type is 'git'/'gitsm' (`if ud.type == 'git' or ud.type ==
# 'gitsm':`) -- switching these 26 entries to a `file://` vendor-directory
# fetch would silently DROP every one of their `[patch]` entries, and cargo
# would then try to resolve them from their real `git+https://...` Cargo.lock
# source at build time -- a hard network fetch inside `--frozen --offline`.
# So the git:// fetcher + subpath + destsuffix + name= architecture
# (gen-git-deps.py, SRCREV_<name> pins, SRCREV_FORMAT) MUST stay exactly as
# it is -- this script does not touch it.
#
# --- The actual fix: overlay ONLY the normalized Cargo.toml --------------
# `cargo vendor` is real cargo machinery that resolves EVERY
# `.workspace = true` reference into a literal value as part of producing a
# self-contained, publish-shaped manifest (the exact same normalization
# `cargo package`/crates.io publishing does) -- verified by actually running
# it (`cargo vendor --offline /tmp/shell-vendor-check` from
# crates/duduclaw-shell, fully offline since this Mac already has every
# dependency cached from prior local builds; 712 crates / 942MB total for
# the FULL graph, matching the Y2-1-era measurement gen-git-deps.py's
# comment cites). Its per-crate output directory layout
# (`<vendor-dir>/<crate-name>/`, with internal path deps REWRITTEN to flat
# sibling references like `path = "../gpui_util"`) happens to be BYTE-FOR-
# BYTE the same shape this recipe's `destsuffix=<name>` layout already
# produces (`${UNPACKDIR}/<name>/`, all git-sourced crates as flat
# siblings) -- so the ONLY file that needs replacing per crate is
# Cargo.toml itself; every real .rs source file, feature, and target-cfg
# dependency stays byte-identical to the raw git checkout.
#
# This script therefore harvests JUST the 26 needed Cargo.toml files from a
# `cargo vendor` run and checks them into
# files/duduclaw-shell-git-manifests/<name>/Cargo.toml -- 26 small, human-
# diffable TOML snapshots (not a 942MB blob), applied as a
# `do_unpack:append()` overwrite in duduclaw-shell_1.62.0.bb AFTER the raw
# git fetch lands, immediately before do_patch/do_configure run. Re-run
# this script (from a Mac with this crate already built locally at least
# once, so `--offline` has everything cached) whenever
# crates/duduclaw-shell/Cargo.toml's gpui/wasm_thread/font-kit/scap `rev =`
# pins move -- same trigger gen-git-deps.py's own header comment already
# documents for regenerating SRCREV_<name>.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHELL_SRC="$HERE/files/duduclaw-shell-src"
OUT_DIR="$HERE/files/duduclaw-shell-git-manifests"
VENDOR_TMP="$(mktemp -d)"

# The exact 26 names gen-git-deps.py's REPOS dict enumerates (kept as a
# literal list here, not imported, so this script has zero Python/tomllib
# dependency and can run with just bash+cargo) -- keep in sync by hand if
# gen-git-deps.py's REPOS dict ever gains/loses an entry; a stale name here
# just means that one crate's manifest silently doesn't get the overlay it
# needs, so also cross-check duduclaw-shell-git-deps.inc's own name= list
# after editing either file.
NAMES=(
    collections derive_refineable gpui gpui_apple gpui_linux gpui_macos
    gpui_macros gpui_platform gpui_shared_string gpui_util gpui_web
    gpui_wgpu gpui_windows http_client media perf refineable scheduler
    sum_tree util_macros zlog ztracing ztracing_macro
    wasm_thread zed-font-kit zed-scap
)

echo "Running 'cargo vendor --offline' from $SHELL_SRC (this covers the FULL" >&2
echo "~700-crate closure, not just the 26 git-sourced ones -- only the 26" >&2
echo "Cargo.toml files below are actually kept)..." >&2
( cd "$SHELL_SRC" && cargo vendor --offline "$VENDOR_TMP" >/dev/null )

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"
missing=0
for name in "${NAMES[@]}"; do
    src="$VENDOR_TMP/$name/Cargo.toml"
    if [[ ! -f "$src" ]]; then
        echo "MISSING: $name (no $src -- did the Cargo.lock dependency graph change?)" >&2
        missing=1
        continue
    fi
    mkdir -p "$OUT_DIR/$name"
    cp "$src" "$OUT_DIR/$name/Cargo.toml"
done

# --- Nested-vs-sibling path-dep fixup (2026-08-26 real build failure) ----
# `bitbake -k duduclaw-image-flatpak` got past the workspace-inheritance
# class of errors this script's overlay already fixes, then died deeper:
#   error: failed to get `derive_refineable` as a dependency of package
#   `refineable v0.1.0 (.../sources/refineable)`
#   Caused by: failed to parse manifest at
#   `.../sources/refineable/derive_refineable/Cargo.toml`
# Root cause: `cargo vendor` does NOT rewrite plain `path = "..."`
# dependency strings (only `.workspace = true` inheritance) -- it preserves
# whatever the ORIGINAL repo's manifest literally says. `derive_refineable`
# genuinely lives NESTED inside refineable's own directory in the real repo
# (`crates/refineable/derive_refineable/`, gen-git-deps.py's own header
# comment already flags this as "the only two non-crates/* entries"), so
# `refineable`'s Cargo.toml says `path = "derive_refineable"` (a
# child-relative reference, no `../`). But gen-git-deps.py fetches
# derive_refineable to a FLAT SIBLING location
# (`destsuffix=derive_refineable`, i.e. `${UNPACKDIR}/derive_refineable/`,
# not `${UNPACKDIR}/refineable/derive_refineable/`) -- matching the
# convention every OTHER crate in this closure already uses. `path =`
# dependencies are resolved by cargo as LITERAL filesystem paths relative
# to the declaring manifest, never through `[patch]` (that mechanism only
# intercepts git/registry-sourced dependency declarations, never a plain
# `path =` string) -- so this mismatch cannot be fixed by anything in
# cargo_common_do_patch_paths, only by making the manifest's path string
# match our actual flat-sibling fetch layout.
#
# Second real finding, same root cause, different depth: workspace-
# inherited path deps (`foo.workspace = true`) resolve to a path relative
# to the WORKSPACE ROOT (`[workspace.dependencies] collections = { path =
# "crates/collections" }`), and cargo vendor substitutes that literal
# value recomputed relative to the DECLARING crate's real position in the
# source tree -- NOT relative to vendor's own flat output layout. `perf`
# (real position `tooling/perf/`, two directories removed from the
# `crates/` tree) ends up with `path = "../../crates/collections"`;
# `util_macros` (real position `crates/util_macros/`) ends up with
# `path = "../../tooling/perf"`. Neither matches our flat-sibling
# destsuffix layout (`../collections`, `../perf`) any more than
# `derive_refineable`'s bare name did.
#
# Fix generalizes to any prefix depth: for each of our 26 known crate
# names, rewrite ANY `path = "...<name>"` line (optional garbage prefix,
# exact crate name as the final path component, quote immediately after)
# into `path = "../<name>"`. Anchoring on the closing quote right after
# <name> is what keeps this from ever matching a `[lib]`/`[[bin]]`/
# `[[example]]`/`[[test]]`/`[[bench]]` source-file path (those always end
# `.rs"`, never bare `<name>"`), and is naturally idempotent -- the 20+
# entries already correctly reading exactly `path = "../<name>"` collapse
# to the same value after rewriting, no `[[ ]]` guard needed.
for manifest in "$OUT_DIR"/*/Cargo.toml; do
    for name in "${NAMES[@]}"; do
        # BSD sed (macOS default) requires an explicit (here empty) backup
        # suffix argument to -i; matches this repo's existing sed -i
        # conventions elsewhere (e.g. scripts/release.sh).
        sed -i '' -E "s#^path = \"([^\"]*/)?${name}\"\$#path = \"../${name}\"#" "$manifest"
    done
done

rm -rf "$VENDOR_TMP"

if [[ "$missing" -ne 0 ]]; then
    echo "One or more manifests missing -- see above. Not all overlays were written." >&2
    exit 1
fi

echo "Wrote $OUT_DIR: ${#NAMES[@]} normalized Cargo.toml snapshots" >&2
