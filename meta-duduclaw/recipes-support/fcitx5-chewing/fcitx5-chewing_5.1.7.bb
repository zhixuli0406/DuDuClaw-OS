# fcitx5-chewing -- Y6-1, 2026-08-26. The fcitx5 addon module wrapping
# libchewing into an IM engine. Version pinned to EXACTLY match Debian
# trixie's own `fcitx5-chewing` package (5.1.7-1, checked via
# sources.debian.org's API) -- same reasoning as fcitx5_5.1.12.bb and
# libchewing_0.9.1.bb: reuse the already-VM-verified Debian-line behavior
# (D3/D3-f/W7-3 rounds) rather than a different upstream version's
# untested one.
#
# Zero recipe anywhere in the OE ecosystem -- checked the same way as
# fcitx5/libchewing above (OpenEmbedded Layer Index + meta-openembedded
# tree at pinned commit, both empty).
#
# Discovers libchewing via plain pkg-config (`pkg_check_modules(Chewing
# "chewing>=0.5.0" IMPORTED_TARGET REQUIRED)`, verified by reading this
# exact tag's CMakeLists.txt directly), NOT CMake's `find_package(Chewing)`
# -- this is WHY libchewing_0.9.1.bb's manual link approach (a correct
# chewing.pc + .so + headers, no CMake package config) is sufficient; see
# that recipe's own header comment for the fuller investigation.

SUMMARY = "fcitx5-chewing -- Zhuyin (bopomofo) input method addon for fcitx5"
DESCRIPTION = "${SUMMARY}. Wraps libchewing as a selectable fcitx5 input \
method (chewing) -- the D3-d appliance profile seed \
(/etc/xdg/fcitx5/profile) lists this as Groups/0/Items/1, DefaultIM."
HOMEPAGE = "https://github.com/fcitx/fcitx5-chewing"
LICENSE = "LGPL-2.1-or-later"
LIC_FILES_CHKSUM = "file://LICENSES/LGPL-2.1-or-later.txt;md5=2a4f4fd2128ea2f65047ee63fbca9f68"

SRC_URI = "git://github.com/fcitx/fcitx5-chewing.git;protocol=https;branch=master \
    file://0001-CMakeLists-sysroot-prefix-for-Fcitx5CompilerSettings.patch \
"
# 5.1.7 is a lightweight tag (object type "commit"), same as fcitx5's own.
SRCREV = "d7841970d1225e89d4d1684c30536326301a274d"
# No explicit S= -- see libchewing_0.9.1.bb's comment: this oe-core release's
# do_unpack sanity check rejects the "${WORKDIR}/git" override this recipe
# originally carried (real failure, caught live during the Y6-1 build).

inherit cmake pkgconfig gettext

DEPENDS = " \
    extra-cmake-modules-native \
    fcitx5 \
    libchewing \
    gettext-native \
"

# ENABLE_TEST=OFF skips building/running fcitx5-chewing's OWN test binary
# (its `find_package(... COMPONENTS TestFrontend)` call is unconditional
# regardless of this flag -- see fcitx5_5.1.12.bb's own comment on why
# ENABLE_TESTING_ADDONS stays on for fcitx5 core -- this flag only gates
# whether fcitx5-chewing's `add_subdirectory(test)` actually builds/runs).
EXTRA_OECMAKE = " \
    -DENABLE_TEST=OFF \
    -DENABLE_COVERAGE=OFF \
"

FILES:${PN} += "${datadir}/fcitx5 ${datadir}/metainfo ${datadir}/locale"
