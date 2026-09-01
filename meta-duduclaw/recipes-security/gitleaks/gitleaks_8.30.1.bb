# gitleaks — WS-3/S1 (2026-09-01, DESIGN-os-security-line-2026-09.md §2
# secaudit 遷入 D1' P0: "gitleaks recipe＋git 入像＋which_cli 補 /usr/bin
# 候選＋[secaudit] config 段"). `duduclaw secaudit` orchestrates gitleaks
# as one of its scanner backends (crates/duduclaw-cli/src/secaudit/, the
# "S1 掃描器 recipe" gap the design doc's own §1.1 table names: "gitleaks
# （Go 單檔靜態，投報比最高）...meta-duduclaw 全無"). No existing recipe
# anywhere reachable from this layer's pinned set — checked via the
# OpenEmbedded Layer Index (layers.openembedded.org, "No matching recipes
# in database" for a "gitleaks" search across the master branch) before
# writing a new one from scratch, per this ticket's own "查有無現成 recipe
# 先" instruction.
#
# UPSTREAM IDENTITY (verified against the real v8.30.1 tag's own go.mod,
# NOT assumed from the current GitHub org name): the project moved from
# github.com/zricethezav/gitleaks to github.com/gitleaks/gitleaks at some
# point, but the go.mod module path itself is STILL
# `github.com/zricethezav/gitleaks/v8` — GO_IMPORT below matches the
# module path (what every gomod:// dependency's own go.sum entries
# reference this module AS), while SRC_URI fetches from the CURRENT
# canonical repo location. Getting this wrong would not just be
# cosmetic — go.bbclass lays fetched source out under
# ${S}/src/${GO_IMPORT}/, and the go toolchain resolves internal imports
# against go.mod's own `module` line, not the fetch URL.
SUMMARY = "Gitleaks -- fast, single-binary secret detection (Go, static regex+entropy)"
DESCRIPTION = "${SUMMARY}. Used by \`duduclaw secaudit\` as its gitleaks \
scanner backend (S1 掃描器編排 step). Pure Go, statically linked, no \
runtime data-file dependency -- config/gitleaks.toml (the default \
detection ruleset) is compiled in via Go's own //go:embed directive \
(confirmed by reading config/config.go at the pinned tag), so only the \
single binary needs installing."
HOMEPAGE = "https://github.com/gitleaks/gitleaks"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://src/${GO_IMPORT}/LICENSE;md5=5a4f873709ce4943d549fca97cf7398b"

GO_IMPORT = "github.com/zricethezav/gitleaks/v8"

SRCREV = "83d9cd684c87d95d656c1458ef04895a7f1cbd8e"
SRC_URI = "git://github.com/gitleaks/gitleaks.git;protocol=https;nobranch=1;destsuffix=${GO_SRCURI_DESTSUFFIX} \
           file://gitleaks-vendor-${PV}.tar.zst;subdir=${GO_SRCURI_DESTSUFFIX}"

# SRCREV is v8.30.1's own tag commit (github.com/gitleaks/gitleaks git/
# refs/tags/v8.30.1 -> object.sha, fetched via the GitHub API directly,
# not guessed). `nobranch=1`, NOT `branch=master`: the tag commit is not
# reachable from master (live fetch attempt on the builder failed with
# "Unable to find revision ... in branch master even from upstream" --
# release tags on this repo point at commits off the branch tip), and
# nobranch=1 is bitbake's documented escape hatch for exactly this shape.
#
# No `S =` assignment: wrynose's do_unpack now hard-errors on the old
# `S = "${WORKDIR}/git"` idiom (bitbake.conf sets the git default itself
# — live bake error 2026-09-01, not a style preference). basename(S) is
# still "git", so GO_SRCURI_DESTSUFFIX's layout math is unchanged.

inherit go-mod

# go-mod (not plain go): its `do_compile[dirs] += ${B}/src/${GO_WORKDIR}`
# is what puts the go tool's cwd inside the module directory (go.bbclass's
# configure symlinks ${S}/src into ${B}) — plain `inherit go` left cwd at
# ${B} and died with "go.mod file not found" (live bake 2026-09-01). The
# class's GOMODCACHE stays empty and unused here: the vendored tree makes
# the go tool run fully offline, pinned explicitly below rather than
# relying on auto-detection.
GOBUILDFLAGS:append = " -mod=vendor"

# go 1.24.11 required by go.mod (checked, not assumed) -- this layer's
# pinned go_1.26.5.bb (meta/recipes-devtools/go/, wrynose branch) is
# comfortably newer, no toolchain gap.

# Root package only — NOT the class default `${GO_IMPORT}/...`: the `...`
# wildcard also builds cmd/generate/config (gitleaks' internal ruleset
# generator, a second `package main`) and shipped a stray 9.9MB
# /usr/bin/config into the image (found by extracting the actual built RPM,
# 2026-09-01, not by reading the tree — the earlier "default covers this"
# comment here was wrong). main.go at the repo root is the one binary
# secaudit needs.
GO_INSTALL = "${GO_IMPORT}"

# Version stamping, mirrors the upstream Makefile's own `$(LDFLAGS)`
# (`-ldflags "-X=github.com/zricethezav/gitleaks/v8/version.Version=$(VERSION)"`,
# read directly from the pinned tag's Makefile) so `gitleaks version`
# reports this recipe's own PV instead of upstream's git-describe
# fallback (which would read "unknown"/empty in a tarball/SRCREV build
# with no .git metadata carried into ${S}).
GO_EXTRA_LDFLAGS = "-X=${GO_IMPORT}/version.Version=${PV}"

# ---------------------------------------------------------------------
# VENDORED DEPENDENCIES (replaces the earlier "gomod:// list pending"
# state -- three recipetool attempts on the builder all failed for
# independent reasons: [src-uri-bad] fatal QA on GitHub archive URLs,
# "revision not in branch master" on the git form, and an
# IsADirectoryError inside create_go.py's version guessing when it hits
# gitleaks' own version/ source directory). Instead of hand-transcribing
# dozens of gomod:// module/version/checksum triples, this recipe ships
# the standard Go vendoring escape hatch: a vendor/ tree generated by the
# real Go toolchain against the pinned tag, packed as a file:// tarball
# that unpacks into ${S}/src/${GO_IMPORT}/vendor. The go tool auto-detects
# vendor/modules.txt and builds fully offline (-mod=vendor is implied for
# go >= 1.14 when the directory is present; go.bbclass sets no conflicting
# -mod flag -- checked). Same files/ big-artifact precedent as
# duduclaw-flatpak-offline-repo's tar.zst.
#
# REPRODUCTION (how gitleaks-vendor-8.30.1.tar.zst was made, 2026-09-01):
#   git clone --depth 1 --branch v8.30.1 https://github.com/gitleaks/gitleaks
#   cd gitleaks && git rev-parse HEAD   # = SRCREV above, verified
#   go mod vendor                        # go 1.26.1, host toolchain
#   tar --no-xattrs -cf - vendor | zstd -19 -T0 -o gitleaks-vendor-8.30.1.tar.zst
#   sha256 = 518b23084c0a8699b7065100a2e5a69c52f875fd7023b6d3dbbb7bce1d7fdc9c
# ---------------------------------------------------------------------

FILES:${PN} += "${bindir}/gitleaks"
