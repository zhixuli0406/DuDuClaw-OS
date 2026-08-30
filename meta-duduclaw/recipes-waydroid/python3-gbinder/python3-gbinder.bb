# python3-gbinder — Cython bindings for libgbinder; the module Waydroid's
# own Python codebase does `import gbinder` against (CP-1, commercial/docs/
# DESIGN-app-compat-layer-2026-08.md §2.4 / TODO-compat-cp1-2026-08.md A5).
#
# Upstream is github.com/waydroid/gbinder-python, NOT
# github.com/erfanoabdi/gbinder-python — checked, not assumed: the task
# brief named erfanoabdi's repo, but that repo's own commit history shows
# development moved to the waydroid org (its "1.3.x" tags live there;
# erfanoabdi's own copy last saw a real content bump in 2022 under the old
# `upstream/1.1.1`-style tags before the project moved). waydroid/waydroid
# issue #214 and the OpenEmbedded Layer Index both point at the waydroid-org
# repo as the one actually consumed by real Waydroid packaging today.
#
# This recipe is a documented, cross-checked port of an ALREADY-REAL Yocto
# recipe: meta-luneos/recipes-support/waydroid/python3-gbinder_git.bb
# (webOS-ports/meta-webos-ports, MIT-licensed recipe metadata by Khem Raj) —
# found via the OpenEmbedded Layer Index while researching this package,
# not written from scratch. Every load-bearing value below (LIC_FILES_CHKSUM
# md5, SRCREV, the ERROR_QA workaround) was independently reproduced first
# (curl+md5sum on the raw LICENSE file; a real `git fetch` of the tag; a
# real repo clone showing setup.py's own `cythonize()` call is now
# unconditional) and only then cross-checked against meta-luneos's numbers
# — they matched exactly.
SUMMARY = "Cython extension module for gbinder"
DESCRIPTION = "${SUMMARY} — lets Waydroid's Python codebase call into \
libgbinder directly (`import gbinder`) instead of shelling out."
HOMEPAGE = "https://github.com/waydroid/gbinder-python"
LICENSE = "GPL-3.0-only"
SECTION = "devel/python"
LIC_FILES_CHKSUM = "file://LICENSE;md5=1ebbd3e34237af26da5dc08a4e440464"

PV = "1.3.1"
SRCREV = "86b8feba4cacd0952b010d1c3af6a29a0c146ced"
SRC_URI = "git://github.com/waydroid/gbinder-python.git;branch=main;protocol=https"

DEPENDS = "libgbinder libglibutil python3-cython-native"

inherit setuptools3 pkgconfig

# setup.py's own `pkgconfig('libgbinder', ...)` helper shells out to
# `pkg-config --cflags --libs libgbinder` at build time — DEPENDS on
# libgbinder (this recipe's own sysroot providing libgbinder.pc/headers)
# and pkgconfig (for the pkg-config binary itself, native variant via the
# inherited class) are both load-bearing, not just "linked against it".
# python3-cython-native is load-bearing too: this project's own real repo
# clone (tag 1.3.1) confirms setup.py now does `from Cython.Build import
# cythonize` unconditionally — the old `--cython` opt-in flag branch meta-
# luneos's own comment describes as removed is gone in the version pinned
# here as well, so Cython is not optional at build time.

# QA workaround, carried forward from meta-luneos's own recipe verbatim:
# Cython emits the absolute build-tree TMPDIR path into the generated
# gbinder.c's #line/comment directives, which oe-core's `buildpaths` QA
# check flags as an error by default (their own recorded error text:
# "File .../gbinder.c in package python3-gbinder-src contains reference to
# TMPDIR"). This is Cython's own well-known codegen behavior, not a bug in
# this package — downgrading to a warning (not silencing entirely) is the
# same trade-off meta-luneos made.
ERROR_QA:remove = "buildpaths"
WARN_QA:append = " buildpaths"

# meta-luneos's own recipe also carries `BBCLASSEXTEND = "native"` (with a
# `DEPENDS:append:class-native = " python-native "` / `RDEPENDS:${PN}:class-
# native = ""` pair). Deliberately NOT carried forward here: nothing in
# this appliance's own recipe set builds or runs python3-gbinder at
# build/native time — only the target-side `waydroid` package imports it —
# so a native variant would be unused surface, not a needed capability.
# Add it back if a future recipe genuinely needs to `import gbinder` from
# a native/host-side Python tool.

COMPATIBLE_MACHINE = ".*"
