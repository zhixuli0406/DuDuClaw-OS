#!/usr/bin/env bash
# sync-platform.sh — bring the OS layer to one platform release in a single run.
#
#   scripts/sync-platform.sh <platform-version> [--src-root PATH] [--check] [--no-web-build] [--force]
#
# What "one platform release" means here (決策 B, 2026-09-08 — same release
# cadence as the platform, the OS keeps its own 0.x VERSION until GA):
#   1. the two PLATFORM-vendored snapshots (duduclaw-cli / -sysd, each
#      recipe's own refresh-src.sh) are regenerated from a platform checkout
#      that is AT that version. duduclaw-comp / -shell are refreshed in the
#      same pass but from THIS repo's own crates/ (the gpui/smithay crates
#      moved here on 2026-09-29, platform feature audit S16-B) — they no
#      longer follow the platform version;
#   2. meta-duduclaw/conf/distro/include/duduclaw-platform-version.inc is
#      bumped, and the two platform recipes are renamed <name>_<ver>.bb (PV)
#      with the comments that cite those filenames updated (comp / shell keep
#      their own PV);
#   3. CHANGELOG.md [Unreleased] gets a "### Changed" stub listing the platform
#      commits that came along.
#
# Everything that bit us doing this by hand on 2026-09-08 is a guard here,
# fail-closed, before anything is touched:
#   - platform checkout not at the requested version (vendoring the wrong code);
#   - uncommitted platform changes in crates/ or web/ (vendoring drift — --force
#     to accept knowingly);
#   - a detached crate's Cargo.lock out of step with its Cargo.toml
#     (release.sh's bump did not re-sync duduclaw-native-gui inside
#     crates/duduclaw-shell/Cargo.lock → `cargo build --frozen` in bitbake
#     re-resolved and tried to fetch the zed git source offline);
#   - a dependency-table version line rewritten to the platform version
#     (release.sh's whole-file sed turned `[dependencies.smithay] version =
#     "0.7.0"` into "1.63.0" → `failed to select a version for smithay`);
#   - a stale dashboard dist/ (the cli snapshot embeds it; a stale one silently
#     ships old UI) — rebuilt with `npm run build` unless --no-web-build.
# After the refresh it also diffs each snapshot's crates.io dependency SET
# against git HEAD: a change means the recipe's *-crates.inc must be
# regenerated before a bake (`bitbake -c update_crates duduclaw-cli`, or the
# recipe's gen-crates-inc.py) — reported loudly, exit 2.
#
# --check runs only the guards and reports; it changes nothing.
#
# It does NOT commit, bake, or bump the OS's own VERSION file. See
# docs/guides/platform-sync.md for the full procedure around it.
set -euo pipefail

usage() { sed -n '2,40p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit "${1:-1}"; }

NEW=""; SRC_ROOT="${DUDUCLAW_CLI_SRC_ROOT:-}"; CHECK=0; WEB_BUILD=1; FORCE=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --src-root) SRC_ROOT="$2"; shift 2 ;;
        --check) CHECK=1; shift ;;
        --no-web-build) WEB_BUILD=0; shift ;;
        --force) FORCE=1; shift ;;
        -h|--help) usage 0 ;;
        -*) echo "sync-platform: unknown option $1" >&2; usage 1 ;;
        *) if [[ -n "$NEW" ]]; then echo "sync-platform: one version only" >&2; usage 1; fi; NEW="${1#v}"; shift ;;
    esac
done
[[ -n "$NEW" ]] || usage 1
[[ "$NEW" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "sync-platform: '$NEW' is not a bare semver" >&2; exit 1; }

OS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ -n "$SRC_ROOT" ]] || SRC_ROOT="$(cd "$OS_ROOT/.." && pwd)/DuDuClaw"
if [[ ! -d "$SRC_ROOT/crates" || ! -f "$SRC_ROOT/Cargo.toml" ]]; then
    echo "sync-platform: platform workspace not found at $SRC_ROOT (need crates/ and Cargo.toml)." >&2
    echo "  Check out github.com/zhixuli0406/DuDuClaw as 'DuDuClaw' next to this repo, or pass --src-root." >&2
    exit 1
fi
export DUDUCLAW_CLI_SRC_ROOT="$SRC_ROOT"   # duduclaw-cli / -sysd refresh-src.sh honour this
# duduclaw-comp / -shell read DUDUCLAW_OS_SRC_ROOT (default: this repo) — never the platform root.

INC="$OS_ROOT/meta-duduclaw/conf/distro/include/duduclaw-platform-version.inc"
RECIPES_DIR="$OS_ROOT/meta-duduclaw/recipes-duduclaw"
RECIPES=(duduclaw-cli duduclaw-sysd)               # vendored from the platform checkout
OS_LOCAL_RECIPES=(duduclaw-comp duduclaw-shell)    # vendored from $OS_ROOT/crates/ (since 2026-09-29)
OLD="$(sed -n 's/^DUDUCLAW_PLATFORM_VERSION = "\(.*\)"/\1/p' "$INC")"
[[ -n "$OLD" ]] || { echo "sync-platform: cannot read DUDUCLAW_PLATFORM_VERSION from $INC" >&2; exit 1; }

fail=0
say()  { printf '%s\n' "$*"; }
bad()  { printf 'FAIL  %s\n' "$*" >&2; fail=1; }
ok()   { printf 'ok    %s\n' "$*"; }

# ── Guard 1: platform checkout is at the requested version ────────────────
PLAT="$(awk '/^\[/{s=$0} s=="[workspace.package]" && /^version = "/{gsub(/"/,"",$3); print $3; exit}' "$SRC_ROOT/Cargo.toml")"
if [[ "$PLAT" != "$NEW" ]]; then
    bad "platform checkout $SRC_ROOT is at $PLAT, not $NEW — \`git -C $SRC_ROOT checkout v$NEW\` first (or ask for $PLAT)"
else
    ok "platform checkout at $NEW ($(git -C "$SRC_ROOT" rev-parse --short HEAD 2>/dev/null || echo 'no git'))"
fi

# ── Guard 2: nothing uncommitted in what gets vendored ────────────────────
if dirty="$(git -C "$SRC_ROOT" status --porcelain -- crates Cargo.toml Cargo.lock web 2>/dev/null)" && [[ -n "$dirty" ]]; then
    if [[ $FORCE -eq 1 ]]; then
        say "warn  vendoring UNCOMMITTED platform changes (--force):"; printf '%s\n' "$dirty" | head -10 | sed 's/^/        /'
    else
        bad "platform checkout has uncommitted changes under crates/ web/ Cargo.*; commit them or pass --force (they would be vendored as-is):"
        printf '%s\n' "$dirty" | head -10 | sed 's/^/        /' >&2
    fi
else
    ok "platform working tree clean under crates/ web/ Cargo.*"
fi

# ── Guard 3: detached crates' Cargo.lock agree with their Cargo.toml ─────
lock_ver() { awk -v n="$2" '$0 == "name = \"" n "\"" { getline; sub(/^version = "/, ""); sub(/"$/, ""); print; exit }' "$1"; }
manifest_ver() { awk '/^\[/{s=$0} (s=="[package]" || s=="[workspace.package]") && /^version = "/{gsub(/"/,"",$3); print $3; exit}' "$1"; }
g3=0
# These three crates live in THIS repo since 2026-09-29 (OS_ROOT, not SRC_ROOT).
for c in duduclaw-shell duduclaw-comp duduclaw-native-gui; do
    lock="$OS_ROOT/crates/$c/Cargo.lock"; [[ -f "$lock" ]] || continue
    for entry in duduclaw-shell duduclaw-comp duduclaw-native-gui; do
        lv="$(lock_ver "$lock" "$entry")"; [[ -n "$lv" ]] || continue
        mv_="$(manifest_ver "$OS_ROOT/crates/$entry/Cargo.toml")"
        if [[ "$lv" != "$mv_" ]]; then
            bad "crates/$c/Cargo.lock has $entry $lv but crates/$entry/Cargo.toml says $mv_ — run: (cd $OS_ROOT/crates/$c && cargo metadata --offline --format-version 1 >/dev/null) and commit"; g3=1
        fi
    done
done
[[ $g3 -eq 0 ]] && ok "detached Cargo.lock files agree with their manifests"

# ── Guard 4: no dependency-table version line carries the platform version ─
g4=0
for m in "$SRC_ROOT"/crates/*/Cargo.toml "$SRC_ROOT/Cargo.toml"; do
    hit="$(awk -v v="version = \"$NEW\"" '/^\[/{s=$0} $0==v && s!="[package]" && s!="[workspace.package]" {print s}' "$m")"
    [[ -z "$hit" ]] || { bad "$m: '$hit' has version = \"$NEW\" — a dependency was clobbered by the bump (release.sh); restore it before vendoring"; g4=1; }
done
[[ $g4 -eq 0 ]] && ok "no dependency table carries the platform version"

# ── Guard 5: dashboard dist/ is newer than the last web/ commit ───────────
DIST="$SRC_ROOT/crates/duduclaw-dashboard/dist/index.html"
web_ts="$(git -C "$SRC_ROOT" log -1 --format=%ct -- web/src web/index.html web/package.json web/package-lock.json 2>/dev/null || echo 0)"
dist_ts="$( [[ -f "$DIST" ]] && stat -f %m "$DIST" 2>/dev/null || stat -c %Y "$DIST" 2>/dev/null || echo 0 )"
if [[ "${dist_ts:-0}" -lt "${web_ts:-0}" ]]; then
    if [[ $CHECK -eq 1 ]]; then
        bad "dashboard dist/ is stale (or missing) vs the last web/ commit — sync would rebuild it (cd $SRC_ROOT/web && npm run build)"
    elif [[ $WEB_BUILD -eq 1 ]]; then
        say "info  dashboard dist/ stale — rebuilding (cd web && npm run build)"
        (cd "$SRC_ROOT/web" && npm run build >/dev/null 2>&1) || { bad "npm run build failed in $SRC_ROOT/web"; }
        [[ -f "$DIST" ]] && ok "dashboard dist/ rebuilt"
    else
        bad "dashboard dist/ is stale and --no-web-build was given"
    fi
else
    ok "dashboard dist/ is fresh"
fi

if [[ $fail -ne 0 ]]; then echo "sync-platform: guards failed — nothing changed." >&2; exit 1; fi
if [[ $CHECK -eq 1 ]]; then say "check: all guards pass for $OLD → $NEW (nothing changed)"; exit 0; fi

# ── 1. Refresh the snapshots (platform-vendored + OS-local) ───────────────
for r in "${RECIPES[@]}" "${OS_LOCAL_RECIPES[@]}"; do
    say "==> refresh $r"
    bash "$RECIPES_DIR/$r/refresh-src.sh" 2>&1 | grep -E '^(Wrote|refresh-src:)' || true
done

# ── 2. crates.io dependency sets vs HEAD (→ *-crates.inc regeneration?) ───
NEED_INC=()
for r in "${RECIPES[@]}" "${OS_LOCAL_RECIPES[@]}"; do
    lock="meta-duduclaw/recipes-duduclaw/$r/files/$r-src/Cargo.lock"
    diff_out="$(cd "$OS_ROOT" && python3 - "$lock" <<'PY'
import subprocess, sys
p=sys.argv[1]
def pkgs(t):
    out=set(); n=v=None
    for l in t.splitlines():
        if l.startswith("[[package]]"): n=v=None
        elif l.startswith('name = "'): n=l.split('"')[1]
        elif l.startswith('version = "'): v=l.split('"')[1]
        elif l.startswith('source = "') and "crates.io" in l: out.add((n,v))
    return out
old=subprocess.run(["git","show",f"HEAD:{p}"],capture_output=True,text=True).stdout
a,b=pkgs(old),pkgs(open(p).read())
if a!=b: print("added="+",".join(f"{n}@{v}" for n,v in sorted(b-a))+" removed="+",".join(f"{n}@{v}" for n,v in sorted(a-b)))
PY
)"
    if [[ -n "$diff_out" ]]; then NEED_INC+=("$r"); say "warn  $r crates.io set changed: $diff_out"; else ok "$r crates.io dependency set unchanged"; fi
done

# ── 3. Embedded platform version + recipe names ───────────────────────────
if [[ "$OLD" != "$NEW" ]]; then
    sed -i.bak "s/^DUDUCLAW_PLATFORM_VERSION = \"$OLD\"/DUDUCLAW_PLATFORM_VERSION = \"$NEW\"/" "$INC" && rm -f "$INC.bak"
    ok "duduclaw-platform-version.inc $OLD → $NEW"
    for r in "${RECIPES[@]}"; do
        if [[ -f "$RECIPES_DIR/$r/${r}_$OLD.bb" ]]; then
            git -C "$OS_ROOT" mv "meta-duduclaw/recipes-duduclaw/$r/${r}_$OLD.bb" "meta-duduclaw/recipes-duduclaw/$r/${r}_$NEW.bb"
            ok "renamed ${r}_$OLD.bb → ${r}_$NEW.bb"
        else
            say "warn  $RECIPES_DIR/$r/${r}_$OLD.bb not found (already renamed?)"
        fi
    done
    # comments that cite the recipe filenames / the DISTRO_VERSION example
    # (only the two platform recipes: comp / shell keep their own PV)
    while IFS= read -r f; do
        sed -i.bak -E "s/(duduclaw-(cli|sysd))_${OLD//./\\.}\.bb/\1_$NEW.bb/g; s/${OLD//./\\.}-y1-bringup/$NEW-y1-bringup/g" "$f" && rm -f "$f.bak"
    done < <(grep -rlE "duduclaw-(cli|sysd)_${OLD//./\\.}\.bb|${OLD//./\\.}-y1-bringup" "$OS_ROOT/meta-duduclaw" "$OS_ROOT/scripts" 2>/dev/null | grep -v "/files/" || true)
    sed -i.bak -E "s/e\.g\. \"${OLD//./\\.}\" — the vendored/e.g. \"$NEW\" — the vendored/" "$OS_ROOT/scripts/release-os.sh" && rm -f "$OS_ROOT/scripts/release-os.sh.bak"
    left="$(grep -rnE "\b${OLD//./\\.}\b" "$OS_ROOT/meta-duduclaw" "$OS_ROOT/scripts" --include='*.bb' --include='*.inc' --include='*.conf' --include='*.bbappend' --include='*.bbclass' --include='*.sh' 2>/dev/null | grep -v "/files/" || true)"
    [[ -z "$left" ]] && ok "no '$OLD' left in the layer outside snapshots" || { say "warn  '$OLD' still mentioned (review by hand):"; printf '        %s\n' "$left" | cut -c1-140; }
else
    ok "embedded platform version already $NEW — no rename"
fi

# ── 4. CHANGELOG stub ─────────────────────────────────────────────────────
CL="$OS_ROOT/CHANGELOG.md"
if grep -qE "同步到 v$NEW" "$CL"; then
    ok "CHANGELOG already mentions the v$NEW sync"
else
    commits="$(git -C "$SRC_ROOT" log --format='%h %s' "v$OLD..v$NEW" 2>/dev/null | head -15 | sed 's/^/    - /' || true)"
    inc_note="快照的 crates.io 依賴集合與 $OLD 相同，\`*-crates.inc\` 未動"
    [[ ${#NEED_INC[@]} -eq 0 ]] || inc_note="crates.io 依賴集合有變（${NEED_INC[*]}），\`*-crates.inc\` 已重生"
    python3 - "$CL" "$OLD" "$NEW" "$inc_note" "$commits" <<'PY'
import sys
p,old,new,inc_note,commits=sys.argv[1:6]
s=open(p).read()
head,sep,rest=s.partition("## [Unreleased]")
line=(f"- **平台快照同步到 v{new}（{old}→{new}，`scripts/sync-platform.sh`）**：`duduclaw-cli`／`duduclaw-sysd` 快照自平台重新 vendor（`duduclaw-comp`／`duduclaw-shell` 自本 repo `crates/` 重新快照），"
      f"`duduclaw-platform-version.inc` {old}→{new}（連動 `DISTRO_VERSION`、os-release `VERSION_ID`、UKI 檔名、A/B loader 項），兩個平台 recipe 改名 `_{new}.bb`。{inc_note}。OS 自己的 release 版本（`VERSION`）不受影響。"
      + ("\n  帶進的平台 commit：\n"+commits if commits.strip() else "") + "\n")
if "### Changed\n" in rest.split("\n## [",1)[0]:
    i=rest.index("### Changed\n")+len("### Changed\n"); rest=rest[:i]+line+rest[i:]
else:
    rest=rest.replace("\n\n","\n\n### Changed\n"+line+"\n",1)
open(p,"w").write(head+sep+rest)
PY
    ok "CHANGELOG [Unreleased] stub added"
fi

# ── Summary ───────────────────────────────────────────────────────────────
say ""
say "sync-platform: $OLD → $NEW done. Changed (snapshot files collapsed):"
git -C "$OS_ROOT" status --short | grep -v '/files/' | sed 's/^/    /'
say "    + $(git -C "$OS_ROOT" status --short | grep -c '/files/') snapshot files"
say ""
say "Next:"
if [[ ${#NEED_INC[@]} -gt 0 ]]; then
    say "  !! regenerate crates .inc for: ${NEED_INC[*]}  (duduclaw-cli: kas shell … -c 'bitbake -c update_crates duduclaw-cli'; comp/sysd: their gen-crates-inc.py) — the bake fails otherwise"
fi
say "  1. review \`git diff\`, then bake ONE image at a time (build volume is 89 GB):"
say "       kas shell meta-duduclaw/kas/duduclaw-os.yml:meta-duduclaw/kas/serial1.yml -c 'bitbake duduclaw-image-appliance-test'"
say "       kas shell meta-duduclaw/kas/duduclaw-os.yml:meta-duduclaw/kas/serial1.yml -c 'bitbake duduclaw-image-live-desktop'"
say "  2. boot the test image under QEMU and check os-release, \`duduclaw --version\`, bootctl's UKI name (wiki/eval/fix14-launcher-footer-qemu-2026-09-08.md §5)"
say "  3. commit; the OS VERSION file stays on its own 0.x line until GA"
[[ ${#NEED_INC[@]} -eq 0 ]] || exit 2
