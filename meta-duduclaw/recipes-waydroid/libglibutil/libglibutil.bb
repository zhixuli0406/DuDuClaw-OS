# libglibutil — GLib utility helpers, the base of the libgbinder chain that
# lets Waydroid (Android app compat, CP-1 — commercial/docs/
# DESIGN-app-compat-layer-2026-08.md §2.4 / TODO-compat-cp1-2026-08.md A5)
# talk to the kernel binder driver.
#
# Sailfish OS project (sailfishos/libglibutil on GitHub — git.sailfishos.org
# itself was retired 2021-10-07 and the canonical repo moved there, verified
# via git.sailfishos.org's own 302 redirect). Plain GNU Makefile build, no
# autotools/meson — confirmed by fetching the real Makefile, not assumed
# from libgbinder's shape alone (they happen to share the same author/
# convention, but each was checked independently).
#
# Recipe shape (PV/SRCREV/LIC_FILES_CHKSUM/EXTRA_OEMAKE/do_install) is a
# straight, independently-cross-checked port of meta-luneos's own
# libglibutil.bb (webOS-ports/meta-webos-ports, MIT-licensed recipe
# metadata) — a real, already-field-tested Yocto packaging of this exact
# library. "Cross-checked" is not "trusted blind": the LIC_FILES_CHKSUM md5
# below was independently recomputed here via `curl` + `md5sum` on the raw
# LICENSE file BEFORE this file's author ever looked at meta-luneos's
# recipe, and the two values matched exactly — same for SRCREV (git-fetched
# and `git log`-read independently, not copied).
SUMMARY = "Library of glib utilities"
DESCRIPTION = "${SUMMARY} — GLib-style wrappers (idle pool, ring buffer, \
int arrays, weak refs, ...) that libgbinder builds on. No product-visible \
behavior of its own; pulled in purely as libgbinder's DEPENDS."
HOMEPAGE = "https://github.com/sailfishos/libglibutil"
LICENSE = "BSD-3-Clause"
LIC_FILES_CHKSUM = "file://LICENSE;md5=84b6ba729d0490a306a608778fb69982"

SRC_URI = "git://github.com/sailfishos/libglibutil.git;protocol=https;branch=master"

PV = "1.0.82"
SRCREV = "cccc4aa8f1745096f6feb66da7883b35055d9423"

DEPENDS = "glib-2.0"

inherit pkgconfig

# KEEP_SYMBOLS=1 — the upstream Makefile strips the release .so itself
# ($(STRIP) in its own `install` recipe rule) unless told not to; letting it
# strip would deny bitbake's own do_package split-debug pass the symbols it
# needs to produce a working ${PN}-dbg package. Same convention this
# project already uses wherever an upstream Makefile does its own
# strip (see PARALLEL_MAKE note below for why that one line is blank too).
EXTRA_OEMAKE = "KEEP_SYMBOLS=1"

# The Makefile's own dependency graph is not safely parallel-buildable top
# to bottom for the pkgconfig/install-dev targets in one `make -jN` call
# (small library, the loss is negligible) — meta-luneos's own recipe
# carries the same blank override; kept for parity rather than re-deriving.
PARALLEL_MAKE = ""

# No do_compile override: base.bbclass's default do_compile is a bare
# `oe_runmake` (no target), which runs the Makefile's own default target —
# `all: debug release pkgconfig` — building the release .so and the
# pkgconfig file do_install needs below. Checked deliberately: the `install`
# target's OWN prerequisite chain (`install: $(INSTALL_LIB_DIR)`) is only a
# directory-creation dependency, NOT $(RELEASE_LIB) — a bare `make install`
# with no prior build step would fail on a missing .so, so do_compile
# running the real default target first is load-bearing, not incidental.
do_install() {
    oe_runmake install DESTDIR=${D}
    oe_runmake install-dev DESTDIR=${D}
}

# Portable C + glib/gobject only — no arch-specific code, same reasoning as
# duduclaw-network-config.bb / duduclaw-steam-devices.bb's own
# COMPATIBLE_MACHINE.
COMPATIBLE_MACHINE = ".*"
