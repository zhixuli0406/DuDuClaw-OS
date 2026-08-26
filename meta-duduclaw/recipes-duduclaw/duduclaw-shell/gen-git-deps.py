#!/usr/bin/env python3
"""Regenerate duduclaw-shell-git-deps.inc from crates/duduclaw-shell/Cargo.lock's
git-sourced packages -- the ones gen-crates-inc.py's `do_update_crates`-style
scan (see that class's own do_update_crates task, which literally filters on
`'crates.io' in c.get('source', '')`) skips and warns about.

Why this needs its own script, not just a hand-maintained .inc: bitbake's
git fetcher `subpath=`/`destsuffix=`/`name=` mechanism, combined with
cargo_common.bbclass's `cargo_common_do_patch_paths` (see that function's
source, meta/classes-recipe/cargo_common.bbclass in the pinned oe-core
checkout) generates `[patch."<repo-url>"]` Cargo config sections keyed
EXACTLY off each SRC_URI git entry's `name=` parameter -- so `name=` here is
not a free label, it MUST equal the real Cargo package name declared in that
subdirectory's own Cargo.toml, or the generated `[patch]` entry silently
patches the wrong (or a nonexistent) package.

Verified real, network-fetch-free, by inspecting this exact repo+rev already
present in this Mac's own `~/.cargo/git/checkouts/` (this crate has been
built locally before) -- NOT guessed from the crate names alone:
    ~/.cargo/git/checkouts/zed-a70e2ad075855582/7a7c3e1/crates/<dir>/Cargo.toml
Every (package name -> subpath-in-repo) pair below was found by grepping
`^name = "<pkg>"` inside that checkout's Cargo.toml files and recording the
containing directory relative to the repo root -- see the dict below.

One real gotcha this list encodes: `derive_refineable`'s Cargo.toml lives at
`crates/refineable/derive_refineable/`, NOT `crates/derive_refineable/` --
it's a proc-macro helper crate nested inside its own parent crate's
directory, not a sibling. `perf`'s Cargo.toml lives under `tooling/perf/`,
not `crates/perf/` -- the only two non-`crates/*` entries in the whole
closure. Both would silently 404 (empty/missing Cargo.toml) if guessed by
the naming convention the other 21 members follow.

Disk/network efficiency note (why subpath+destsuffix per crate, not one
single full-repo checkout): bitbake's git fetcher downloads exactly ONE
bare mirror clone per unique (host, path) repo URL, cached in DL_DIR,
REGARDLESS of how many SRC_URI entries reference it with different
`name=`/`subpath=`/`destsuffix=` -- confirmed by reading
lib/bb/fetch2/git.py's `gitsrcname` computation (keyed only on
`ud.host`+`ud.path`, never destsuffix/subpath/name). Each of the 23 zed-repo
entries below therefore triggers exactly one network fetch total (not 23),
and each per-crate unpack is a local `git clone -n -s` (shared/no-checkout,
hardlinked objects) from that one cached mirror followed by a
`read-tree <rev>:<subpath>` + `checkout-index` -- cheap in both disk and
time. This was verified against fetch2/git.py source before committing to
this design over the alternative (one single-destsuffix full-repo checkout
+ a hand-written custom do_configure step to inject 23 `[patch]` lines
ourselves) -- the alternative would have been more code for a worse (single
giant checkout, harder to audit which crate maps to which patch entry)
result, so subpath+destsuffix per crate is the one actually used here.

This script does NOT auto-derive the subpath map (would require a live
`~/.cargo/git/checkouts/` on the machine regenerating it, which is
host-state, not repo state) -- SUBPATH_MAP is a checked-in, hand-verified
constant. Re-verify it by hand (same grep-Cargo.toml-in-a-local-checkout
method) whenever crates/duduclaw-shell/Cargo.toml's `rev = "..."` pins move
to a new commit.

Third alternative considered and rejected -- a `cargo vendor` tarball
(the strategy an earlier Y-line round measured at 712 crates / 942MB for
this same dependency closure, folder-copied verbatim into a single
`file://` SRC_URI entry): this would have traded away the per-crate
`[patch]` audit trail entirely (one opaque 942MB blob instead of 26
individually-named, individually-`SRCREV`-pinned entries), given up
bitbake's own git-fetcher-level revision tracking (no `SRCREV_<name>` to
bump when a pin moves -- the whole vendor blob would need regenerating and
diffing by hand), and would still have needed the exact same
`cargo_common_do_patch_paths` `[patch]`-generation mechanism underneath
for anything vendor alone can't satisfy (a plain `[source.vendored-sources]`
directory replacement doesn't handle git-sourced deps whose Cargo.lock
`source` is still `git+...` -- cargo's vendoring model expects EITHER a
fully offline vendor dir with a matching `.cargo/config.toml`
`[source.crates-io] replace-with`, which is a different, non-bitbake-native
config surface than what `cargo_common.bbclass` already sets up and
maintains). The subpath+destsuffix approach reuses infrastructure this
layer's OTHER recipes (duduclaw-sysd/duduclaw-cli/duduclaw-comp) already
depend on and already had build-verified, at the cost of a longer (but
auditable, per-crate) SRC_URI list -- judged the more maintainable trade
for a layer with five sibling recipes that all need to keep working the
same way.
"""
import os
import sys

try:
    import tomllib
except ImportError:
    import tomli as tomllib  # type: ignore

HERE = os.path.dirname(os.path.abspath(__file__))
LOCK_PATH = os.path.join(HERE, "files", "duduclaw-shell-src", "Cargo.lock")
OUT_PATH = os.path.join(HERE, "duduclaw-shell-git-deps.inc")

# repo (owner/name, no https:// prefix, no .git suffix -- matches the git =
# "https://github.com/..." string verbatim as written in Cargo.toml, so
# cargo's own [patch."<url>"] canonicalization has the least distance to
# travel) -> package name -> subpath-in-repo. `None` subpath means the
# package's Cargo.toml sits at the repo root (a single-crate repo, not a
# monorepo member).
REPOS = {
    "github.com/zed-industries/zed": {
        "collections": "crates/collections",
        "derive_refineable": "crates/refineable/derive_refineable",
        "gpui": "crates/gpui",
        "gpui_apple": "crates/gpui_apple",
        "gpui_linux": "crates/gpui_linux",
        "gpui_macos": "crates/gpui_macos",
        "gpui_macros": "crates/gpui_macros",
        "gpui_platform": "crates/gpui_platform",
        "gpui_shared_string": "crates/gpui_shared_string",
        "gpui_util": "crates/gpui_util",
        "gpui_web": "crates/gpui_web",
        "gpui_wgpu": "crates/gpui_wgpu",
        "gpui_windows": "crates/gpui_windows",
        "http_client": "crates/http_client",
        "media": "crates/media",
        "perf": "tooling/perf",
        "refineable": "crates/refineable",
        "scheduler": "crates/scheduler",
        "sum_tree": "crates/sum_tree",
        "util_macros": "crates/util_macros",
        "zlog": "crates/zlog",
        "ztracing": "crates/ztracing",
        "ztracing_macro": "crates/ztracing_macro",
    },
    "github.com/zed-industries/wasm_thread": {
        "wasm_thread": None,
    },
    "github.com/zed-industries/font-kit": {
        "zed-font-kit": None,
    },
    "github.com/zed-industries/scap": {
        "zed-scap": None,
    },
}


def main():
    with open(LOCK_PATH, "rb") as f:
        lock = tomllib.load(f)

    git_pkgs = {}  # name -> (repo, rev)
    for pkg in lock["package"]:
        src = pkg.get("source", "")
        if not src.startswith("git+"):
            continue
        # e.g. "git+https://github.com/zed-industries/zed?rev=<sha>#<sha>"
        url_part = src[len("git+") :]
        base, _, query = url_part.partition("?")
        rev = None
        if "rev=" in query:
            rev = query.split("rev=", 1)[1].split("&", 1)[0].split("#", 1)[0]
        repo_key = base.removeprefix("https://").removeprefix("http://")
        git_pkgs[pkg["name"]] = (repo_key, rev)

    lines = [
        "# Autogenerated by gen-git-deps.py from files/duduclaw-shell-src/Cargo.lock's\n",
        "# git-sourced packages. Re-run after refresh-src.sh whenever crates/duduclaw-shell's\n",
        "# or crates/duduclaw-native-gui's gpui/wasm_thread/font-kit/scap pins change.\n",
        "# See this script's own header comment for the subpath-per-crate mechanism and\n",
        "# why it's structured this way (bitbake git fetcher dedup + cargo_common.bbclass's\n",
        "# name<->path [patch] generation).\n\n",
        'SRC_URI += " \\\n',
    ]

    missing = []
    entries = []  # (name, repo, subpath, rev)
    for repo_key, members in REPOS.items():
        for name, subpath in members.items():
            if name not in git_pkgs:
                missing.append(name)
                continue
            locked_repo, rev = git_pkgs[name]
            if locked_repo != repo_key:
                print(
                    f"WARNING: {name} locked to {locked_repo}, SUBPATH_MAP says {repo_key}",
                    file=sys.stderr,
                )
            entries.append((name, repo_key, subpath, rev))

    seen_names = {e[0] for e in entries}
    for name in git_pkgs:
        if name not in seen_names:
            print(
                f"WARNING: {name} is git-sourced in Cargo.lock but has no entry in "
                "REPOS -- add its (repo, subpath) or this crate silently won't build",
                file=sys.stderr,
            )

    for name, repo, subpath, rev in entries:
        parm = "protocol=https;nobranch=1;name=%s" % name
        if subpath:
            parm += ";subpath=%s;destsuffix=%s" % (subpath, name)
        else:
            parm += ";destsuffix=%s" % name
        lines.append("    git://%s;%s \\\n" % (repo, parm))
    lines.append('"\n\n')

    for name, repo, subpath, rev in entries:
        lines.append('SRCREV_%s = "%s"\n' % (name, rev))

    # bb.fetch2._get_srcrev() hard-requires SRCREV_FORMAT whenever a recipe
    # has more than one SCM in SRC_URI (verified against
    # bitbake/lib/bb/fetch2/__init__.py: "The SRCREV_FORMAT variable must be
    # set when multiple SCMs are used", raised as a FetchError, not a
    # warning -- this recipe has 26). The mechanism (same source file): the
    # string just needs to CONTAIN every SRC_URI entry's `name=` token
    # somewhere in it -- bitbake regex-replaces each token with that SCM's
    # own resolved short revision, trying longer names before their
    # prefixes (its own re.sub is fed alternatives sorted by
    # `len(name)` descending) specifically so "gpui_platform" is matched
    # whole rather than as "gpui" + a leftover "_platform". Joining every
    # name with "_" here is therefore not just cosmetic formatting -- it's
    # what makes each name a distinct, unambiguous substring for that
    # matching to find. Value is otherwise never read by anything else (no
    # other part of this recipe or PV depends on the format string's exact
    # shape).
    lines.append('\nSRCREV_FORMAT = "%s"\n' % "_".join(name for name, _, _, _ in entries))

    if missing:
        print(f"WARNING: SUBPATH_MAP names not found in Cargo.lock: {missing}", file=sys.stderr)

    with open(OUT_PATH, "w") as f:
        f.writelines(lines)

    print(f"Wrote {OUT_PATH}: {len(entries)} git deps across {len(REPOS)} repos", file=sys.stderr)


if __name__ == "__main__":
    main()
