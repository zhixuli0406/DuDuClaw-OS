# fcitx5 core -- Y6-1, 2026-08-26. Version pinned to EXACTLY match Debian
# trixie's own `fcitx5` package (5.1.12-2, checked via sources.debian.org's
# API) -- same reasoning as libchewing_0.9.1.bb: reuse the Debian-line's
# already-proven candidate-window/profile/config semantics (D3-d/D3-f/W7-3)
# rather than a different upstream version's untested behavior.
#
# Zero recipe anywhere in the OE ecosystem for "fcitx5" (OpenEmbedded Layer
# Index wrynose/master both "No matching recipes in database"; meta-oe's
# checked-out tree at its pinned commit has zero hits) -- self-authored.
#
# Every dependency below except extra-cmake-modules-native (this layer's
# own new recipe, see that recipe's header for why it alone needed
# self-authoring) is confirmed already present in oe-core/meta-oe by
# listing the actual recipe files in the checked-out layers at their pinned
# commits, not assumed from fcitx5's docs: fmt (oe-core), iso-codes
# (oe-core), wayland-protocols (oe-core), expat (oe-core), util-linux/
# libuuid (oe-core), cairo/pango/gdk-pixbuf (oe-core), dbus/systemd
# (already pulled by this image). xcb-imdkit -- fcitx5's X11 frontend
# dependency -- is NOT present anywhere either, which is why ENABLE_X11 is
# turned off below rather than self-authoring a third recipe for a frontend
# this Wayland-only appliance (comp's text-input-v3, per the D3 design
# note "Chromium 零工作（M135 起 text-input-v3 預設開）") never uses.

SUMMARY = "fcitx5 -- flexible input method framework (core)"
DESCRIPTION = "${SUMMARY}. Wayland-only build (ENABLE_X11=OFF -- this \
appliance's compositor speaks text-input-v3, never X11) providing the \
fcitx5-chewing addon's host framework: addon loader, D-Bus control \
interface (fcitx5-remote, driven by crates/duduclaw-shell's ime_focus.rs \
per-field IM switching, W7-3), and the classicui candidate-window renderer \
this appliance seeds vertical (D3-f/P1-1) via /etc/xdg/fcitx5/conf/\
classicui.conf."
HOMEPAGE = "https://fcitx-im.org/wiki/Fcitx_5"
LICENSE = "LGPL-2.1-or-later"
LIC_FILES_CHKSUM = "file://LICENSES/LGPL-2.1-or-later.txt;md5=2a4f4fd2128ea2f65047ee63fbca9f68"

SRC_URI = "git://github.com/fcitx/fcitx5.git;protocol=https;branch=master \
    file://0001-log-fmt-localtime-removed-in-newer-fmt.patch \
    file://0002-cmake-install-interface-relative-includedir.patch \
    file://0003-cmake-resolve-libdatadir-relative-to-install-prefix.patch \
"
# 5.1.12 is a lightweight tag (object type "commit" in the GitHub API
# response, i.e. this SHA already IS the commit, unlike the annotated tags
# used for libchewing/extra-cmake-modules above).
SRCREV = "044238901f880461b45e98cba07187097a0b8218"
# No explicit S= -- see libchewing_0.9.1.bb's comment: this oe-core release's
# do_unpack sanity check rejects the "${WORKDIR}/git" override this recipe
# originally carried (real failure, caught live during the Y6-1 build).

inherit cmake pkgconfig gettext

DEPENDS = " \
    extra-cmake-modules-native \
    fmt \
    gettext-native \
    zlib \
    dbus \
    util-linux \
    libxkbcommon \
    wayland \
    wayland-native \
    wayland-protocols \
    iso-codes \
    xkeyboard-config \
    expat \
    cairo \
    pango \
    gdk-pixbuf \
    json-c \
"

# -DENABLE_X11=OFF: no xcb-imdkit recipe exists anywhere (see header
# comment) and this appliance is Wayland-only -- matches the same judgment
# already applied to the whole comp/shell IME design (D3 series).
# -DENABLE_ENCHANT=OFF / -DBUILD_SPELL_DICT=OFF: English word-prediction/
# spell-check, not needed for a Chinese-Zhuyin-focused appliance IME and
# would need enchant2 (meta-oe has it, but skipped to keep this bring-up's
# dependency surface minimal -- can be revisited if English autocomplete is
# ever wanted).
# -DENABLE_TEST=OFF / -DENABLE_DOC=OFF: this is an image-build recipe, not
# a ptest/doc-generation target.
# -DENABLE_TESTING_ADDONS is deliberately LEFT AT ITS DEFAULT (On): despite
# the name suggesting it is test-only tooling, fcitx5-chewing's own
# CMakeLists.txt does an UNCONDITIONAL `find_package(Fcitx5Module REQUIRED
# COMPONENTS TestFrontend)` at configure time (verified by reading
# fcitx5-chewing 5.1.7's actual CMakeLists.txt) -- turning this off here
# would break fcitx5-chewing's build even with ITS OWN ENABLE_TEST=OFF.
# Y7-1 (2026-08-26) real do_package_qa "buildpaths" fix, root-caused by
# reading the actual generated build/config.h (not guessed): fcitx5's own
# cmake/FindIsoCodes.cmake does `find_file(ISOCODES_ISO639_JSON
# iso_639-3.json HINTS "${PC_ISOCODES_PREFIX}/share/iso-codes/json/")`
# guarded by `if(NOT DEFINED ISOCODES_ISO639_JSON)` -- under cross-compile,
# find_file()'s CMAKE_FIND_ROOT_PATH redirection makes it discover the file
# inside THIS recipe's staging sysroot and returns that absolute,
# TMPDIR-rooted path as the variable's value, which config.h then bakes in
# as a runtime C-string literal ("<TMPDIR>/.../recipe-sysroot/usr/share/
# iso-codes/json/iso_639-3.json" -- confirmed verbatim in the generated
# config.h). That path does not exist on the real target rootfs. Since the
# guard is `if(NOT DEFINED ...)`, pre-defining the cache variable via
# EXTRA_OECMAKE bypasses the broken find_file() entirely and supplies the
# CORRECT target runtime path directly -- iso-codes (already an RDEPENDS
# below) installs its json data to ${datadir}/iso-codes/json/ via its own
# default meson FILES (confirmed: the leaked sysroot string's suffix after
# "recipe-sysroot" is exactly "usr/share/iso-codes/json/...", i.e. this IS
# where the real target file lands once resolved against / instead of the
# sysroot). This is a functional fix, not just QA-silencing -- without it
# fcitx5's ISO language/country name lookups would fail open on real
# hardware (the file genuinely wouldn't exist at the baked-in path).
EXTRA_OECMAKE = " \
    -DENABLE_X11=OFF \
    -DENABLE_ENCHANT=OFF \
    -DBUILD_SPELL_DICT=OFF \
    -DENABLE_TEST=OFF \
    -DENABLE_DOC=OFF \
    -DISOCODES_ISO639_JSON=${datadir}/iso-codes/json/iso_639-3.json \
    -DISOCODES_ISO3166_JSON=${datadir}/iso-codes/json/iso_3166-1.json \
"

# ${datadir}/icons: real do_package QA failure caught this ("30 installed
# and not shipped files [installed-vs-shipped]") -- fcitx5's own install
# rules ship hicolor icon theme assets (org.fcitx.Fcitx5.png/fcitx.png at
# six sizes + one scalable SVG, both name variants) for its own/
# configtool's desktop entries; this recipe's original FILES list simply
# didn't account for them.
FILES:${PN} += "${datadir}/fcitx5 ${datadir}/dbus-1 ${datadir}/applications ${datadir}/metainfo ${datadir}/icons ${systemd_user_unitdir}"
FILES:${PN}-dev += "${libdir}/cmake/Fcitx5*"

# fcitx5-remote is what W7-3's ime_focus.rs actually shells out to
# (`fcitx5-remote -s keyboard-us` / `-s chewing`) -- confirmed present in
# the main package by this recipe's own default packaging (it is a normal
# ${bindir} executable target, no separate PACKAGES split for it upstream).
RDEPENDS:${PN} += "iso-codes xkeyboard-config"
