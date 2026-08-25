#!/usr/bin/env bash
# Regenerates files/duduclaw-cli-src/ -- a standalone MINI-WORKSPACE snapshot
# (not a single flattened crate, unlike duduclaw-sysd's refresh-src.sh)
# containing the `duduclaw` binary (crates/duduclaw-cli, produces the
# `duduclaw` ELF -- this is both "duduclaw gateway" and "duduclaw-cli" in the
# Y2-1 task brief: duduclaw-gateway has no [[bin]] of its own, it's a lib
# duduclaw-cli depends on and re-exports via `duduclaw run`) plus every
# DuDuClaw workspace member it actually reaches by path, built with
# `--no-default-features --features duduclaw-gateway/dashboard` (appliance
# convention -- see container/Dockerfile.server's rust-builder stage --
# avoids enigo/xcap and their wayland/pipewire/gbm transitive pull-in).
#
# Why a mini-workspace instead of duduclaw-sysd's single-flattened-crate
# approach: duduclaw-cli has real PATH dependencies on 20 other DuDuClaw
# crates (duduclaw-core, duduclaw-gateway, duduclaw-memory, ...), so there's
# no way to inline everything into one Cargo.toml the way sysd's ~10 purely
# EXTERNAL deps allowed. Instead this reconstructs a trimmed COPY of the
# real workspace: same root Cargo.toml (just `members` narrowed to the 21
# crates actually needed -- verified by walking `cargo metadata`'s resolve
# graph from duduclaw-cli with the exact --no-default-features/--features
# flags the appliance build uses, not guessed), each member's real Cargo.toml
# UNCHANGED (workspace = true shorthand keeps working because this snapshot
# has its own real [workspace] root, same mechanism the real monorepo uses).
#
# Re-run whenever any of the 21 member crates' deps change, or after
# `cd web && npm run build` produces a new crates/duduclaw-dashboard/dist/
# (rust-embed reads that folder at COMPILE time -- see that crate's
# `#[folder = "dist/"]` -- so a stale/missing dist/ silently ships an old or
# empty embedded dashboard; this script copies whatever's on disk verbatim,
# it does NOT run npm itself, matching the sysd script's "vendor a snapshot,
# don't fetch/build inside the refresh step" convention).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
OUT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/files/duduclaw-cli-src"

# The 21-member closure -- computed 2026-08-25 via `cargo metadata
# --no-default-features --features duduclaw-gateway/dashboard` + a BFS from
# the duduclaw-cli resolve node (scratchpad gen_cli_closure.py), NOT
# hand-guessed. Re-derive with the same command if this list ever goes
# stale (a missing member shows up immediately as a cargo "failed to load
# source for dependency" error, so silent staleness isn't a real risk here).
MEMBERS=(
    duduclaw-agent duduclaw-auth duduclaw-cli duduclaw-cli-runtime
    duduclaw-cli-worker duduclaw-container duduclaw-core duduclaw-dashboard
    duduclaw-fork duduclaw-gateway duduclaw-identity duduclaw-inference
    duduclaw-license duduclaw-llm duduclaw-memory duduclaw-odoo duduclaw-os
    duduclaw-redaction duduclaw-sandbox duduclaw-security duduclaw-sysd
    # duduclaw-desktop is NOT in the 21-member closure (its `optional = true`
    # feature stays off -- see CARGO_BUILD_FLAGS in the .bb). Included anyway
    # (verified by hitting the alternative): cargo still needs to LOAD the
    # manifest of every declared path-dependency, active or not, to build
    # its initial workspace graph -- `cargo build` failed with "failed to
    # read .../crates/duduclaw-desktop/Cargo.toml: No such file or
    # directory" when it was left out. Its own transitive deps (enigo/xcap)
    # are never pulled into the resolve graph because the feature gating it
    # stays inactive -- confirmed absent from the crates.io closure below.
    duduclaw-desktop
    # Same reasoning as duduclaw-desktop above: duduclaw-gateway declares an
    # optional `duduclaw-relay = { workspace = true }` path dependency that
    # stays inactive under the dashboard-only feature set, but cargo still
    # needs its manifest present to load the workspace graph (hit the same
    # "failed to read .../duduclaw-relay/Cargo.toml" error without this).
    # Cross-checked against the FULL duduclaw-*-path set in the real root
    # Cargo.toml's [workspace.dependencies] afterward -- duduclaw-pets is
    # the only entry not referenced by any of these 23 crates' manifests,
    # so it's correctly left out.
    duduclaw-relay
)

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR/crates"

for m in "${MEMBERS[@]}"; do
    cp -R "$REPO_ROOT/crates/$m" "$OUT_DIR/crates/$m"
    rm -rf "$OUT_DIR/crates/$m/target"
done

cp "$REPO_ROOT/LICENSE" "$OUT_DIR/LICENSE"

# Repo-root assets several crates embed at COMPILE time via `include_str!`
# with a `../../../<path>` traversal from crates/X/src/ -- found by grepping
# all 23 members for `include_str!`/`include_bytes!` string literals
# (`grep -rn 'include_str!\|include_bytes!' ... | grep -oE '"\.\./[^"]+"'`),
# not guessed. Without these, `cargo build` fails at duduclaw-core's own
# compile step with "couldn't read .../templates/presets/system-operator/
# preset.toml: No such file or directory" -- hit this for real before adding
# the copy. `../features.toml`-style single-level-up refs are already
# covered by the whole-crate-dir copy above; only the 3-levels-up
# (crates/X/src/../../../<path> == repo root) refs need this extra step.
mkdir -p "$OUT_DIR/templates" "$OUT_DIR/docs"
cp -R "$REPO_ROOT/templates/." "$OUT_DIR/templates/"
cp "$REPO_ROOT/docs/README.md" "$OUT_DIR/docs/README.md"

# Root Cargo.toml: copy the REAL one verbatim, then narrow `members = [...]`
# to just our 21 -- [workspace.package]/[workspace.dependencies]/
# [workspace.lints] stay byte-identical to the real workspace (same version
# pins, same edition, same lint config), only the member LIST differs.
python3 - "$REPO_ROOT/Cargo.toml" "$OUT_DIR/Cargo.toml" "${MEMBERS[@]}" <<'PYEOF'
import re, sys
src_path, out_path = sys.argv[1], sys.argv[2]
members = sys.argv[3:]
text = open(src_path).read()

# Replace the `members = [ ... ]` array (multi-line) with just our subset.
new_members = "members = [\n" + "".join(f'    "crates/{m}",\n' for m in members) + "]\n"
text = re.sub(r"members = \[.*?\]\n", new_members, text, count=1, flags=re.DOTALL)

# Drop the `exclude = [ ... ]` array entirely -- none of the excluded dirs
# (duduclaw-comp/duduclaw-shell/duduclaw-native-gui/src-tauri/tools/...) are
# in our member list anyway, and cargo errors on an exclude entry that
# doesn't exist relative to this trimmed root.
text = re.sub(r"exclude = \[.*?\]\n", "", text, count=1, flags=re.DOTALL)

open(out_path, "w").write(text)
PYEOF

# Cargo.lock: same "start from the real lock, let a real build prune it"
# approach as duduclaw-sysd/refresh-src.sh -- see that script's comment for
# why (a plain `cargo build` respects existing pins far more conservatively
# than `cargo generate-lockfile`, which was observed re-resolving to newer
# versions instead of just pruning unreachable entries).
cp "$REPO_ROOT/Cargo.lock" "$OUT_DIR/Cargo.lock"

echo "Wrote $OUT_DIR (root Cargo.toml narrowed to ${#MEMBERS[@]} members, Cargo.lock copied verbatim -- NOT pruned yet, run the build step separately, it's slow)"
