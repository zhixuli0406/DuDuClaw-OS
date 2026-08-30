# libgbinder — GLib-style binder client library; the piece Waydroid (CP-1,
# commercial/docs/DESIGN-app-compat-layer-2026-08.md §2.4 /
# TODO-compat-cp1-2026-08.md A5) and python3-gbinder both sit on top of to
# talk to the kernel binder driver (a separate agent owns getting
# binder_linux itself into the kernel config — recipes-kernel is out of
# this recipe's scope, see the CP-0 finding in the design doc that
# binder_linux is currently missing from the appliance kernel).
#
# mer-hybris/libgbinder on GitHub. Same plain-Makefile shape as
# libglibutil (same author/project family, verified independently by
# fetching this repo's own Makefile rather than assumed from libglibutil's).
#
# Recipe shape is a cross-checked port of meta-luneos's libgbinder.bb
# (webOS-ports/meta-webos-ports) — same "independently recomputed, then
# matched" verification as libglibutil.bb's own header comment describes:
# LIC_FILES_CHKSUM's md5 and SRCREV were both derived here first (curl+
# md5sum, git fetch + git log) and only then compared against meta-luneos's
# values.
SUMMARY = "GLib-style interface to binder"
DESCRIPTION = "${SUMMARY} — the library Waydroid's lxc container and the \
python3-gbinder Cython bindings both link against to speak the Android \
binder IPC protocol to the host kernel's binder driver."
HOMEPAGE = "https://github.com/mer-hybris/libgbinder"
LICENSE = "BSD-3-Clause"
LIC_FILES_CHKSUM = "file://LICENSE;md5=6b4103b77e6fa766a75a1c2c3ba715c8"

SRC_URI = "git://github.com/mer-hybris/libgbinder.git;branch=master;protocol=https"

PV = "1.1.52"
SRCREV = "e906afcffbfa51b7fbefe042a13b933d9e8dfdd9"

DEPENDS = "glib-2.0 libglibutil"

inherit pkgconfig

# Same two reasons as libglibutil.bb — this Makefile is the same author's
# same convention (KEEP_SYMBOLS defeats the upstream Makefile's own
# `install:`-time $(STRIP) call so bitbake's split-debug pass gets real
# symbols; PARALLEL_MAKE blank matches the same non-parallel-safe
# install-dev prerequisite chain).
EXTRA_OEMAKE = "KEEP_SYMBOLS=1"
PARALLEL_MAKE = ""

# GCC pointer-type-mismatch fix, carried forward from meta-luneos's own
# recipe verbatim (their comment cites the exact errors: gbinder_writer.c
# passing an incompatible pointer type into gbinder_cleanup_add/
# gbinder_writer_alloc). NOT independently re-verified against a real build
# this wave (this ticket does not run bitbake — see this layer's own A5
# task brief) — carried forward as a documented, credible risk mitigation,
# not silently dropped and not presented as re-confirmed. This distro's
# own oe-core pin defaults to GCC 15 (tcmode-default.inc GCCVERSION ?=
# "15.%", checked directly in the builder container), a toolchain new
# enough that -Wincompatible-pointer-types defaulting to a hard error in C
# is exactly the failure class meta-luneos's fix targets, so the risk this
# is still needed is real, not theoretical.
CFLAGS += "-std=gnu17"

# Same default-do_compile reasoning as libglibutil.bb.
do_install() {
    oe_runmake install DESTDIR=${D}
    oe_runmake install-dev DESTDIR=${D}
}

# No Halium `/etc/gbinder.conf` override here (meta-luneos's recipe installs
# one via do_install:append:halium/:pinephone/... for ApiLevel quirks on
# those targets) — deliberately omitted: CP-0's own LINE-on-Waydroid PoC
# (commercial/docs/DESIGN-app-compat-layer-2026-08.md §8, 2026-08-21) ran
# the full Waydroid chain on a mainline kernel + generic binder driver with
# no gbinder.conf at all, so this appliance's real prior evidence says it
# is not needed for the qemux86-64/genericx86-64 target family. Left as a
# TODO for whoever hits an ApiLevel mismatch on real Android guest images:
# add the file back the same way if it turns out to be needed here too.

COMPATIBLE_MACHINE = ".*"
