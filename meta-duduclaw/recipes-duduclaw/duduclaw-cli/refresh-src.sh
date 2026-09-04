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

# REPO_ROOT = the DuDuClaw PLATFORM repo (the Cargo workspace this script
# vendors a trimmed snapshot of). Two layouts are auto-detected so this
# works both before and after the 2026-09 repo split (wiki/pm/
# repo-split-runbook-2026-09.md):
#   - Monorepo (pre-split): crates/ is a sibling of meta-duduclaw/, i.e.
#     three levels up from this script. Detected by that crates/ existing.
#   - Split: meta-duduclaw/ is the top of the DuDuClaw-OS repo and the
#     platform lives in a SEPARATE checkout. Default to a sibling directory
#     named `DuDuClaw` next to the OS repo (…/DuDuClaw-OS + …/DuDuClaw under
#     the same parent) — the user's actual layout.
# DUDUCLAW_CLI_SRC_ROOT overrides both for any non-standard checkout path.
_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -n "${DUDUCLAW_CLI_SRC_ROOT:-}" ]]; then
    REPO_ROOT="$DUDUCLAW_CLI_SRC_ROOT"
elif [[ -d "$_SCRIPT_DIR/../../../crates" ]]; then
    REPO_ROOT="$(cd "$_SCRIPT_DIR/../../.." && pwd)"          # monorepo
else
    REPO_ROOT="$(cd "$_SCRIPT_DIR/../../../.." && pwd)/DuDuClaw"  # split: sibling checkout
fi
if [[ ! -d "$REPO_ROOT/crates" ]]; then
    echo "ERROR: DuDuClaw platform source not found at $REPO_ROOT/crates" >&2
    echo "  This OS repo vendors a snapshot of the DuDuClaw platform's Cargo" >&2
    echo "  workspace, which lives in a SEPARATE repo since the 2026-09 split." >&2
    echo "  Fix: check out the DuDuClaw platform repo as a sibling named" >&2
    echo "  'DuDuClaw' next to this OS repo, or set DUDUCLAW_CLI_SRC_ROOT to" >&2
    echo "  its path. See wiki/pm/repo-split-runbook-2026-09.md §4." >&2
    exit 1
fi
OUT_DIR="$_SCRIPT_DIR/files/duduclaw-cli-src"

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

# Prune the lock NOW, not "in a separate build step someone remembers to run"
# (2026-08-29 incident: a refresh without the prune shipped a lock still
# carrying entries for workspace members OUTSIDE the narrowed set -- e.g.
# duduclaw-pets and its kamadak-exif/mutate_once deps -- and bitbake's
# `cargo build --frozen` refused with "cannot update the lock file", failing
# the whole image bake). `cargo metadata` runs the exact same resolver a
# build would (same conservative pin-respecting behavior the comment above
# wants) and rewrites the lock without compiling anything, so the prune is
# cheap enough to fold in here instead of trusting a follow-up step.
(cd "$OUT_DIR" && cargo metadata --format-version 1 >/dev/null)

echo "Wrote $OUT_DIR (root Cargo.toml narrowed to ${#MEMBERS[@]} members, Cargo.lock pruned via cargo metadata to this narrowed workspace)"
