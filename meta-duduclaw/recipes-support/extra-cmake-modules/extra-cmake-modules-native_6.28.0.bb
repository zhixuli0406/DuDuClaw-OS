# extra-cmake-modules (KDE's "ECM") -- Y6-1, 2026-08-26.
#
# Native-build-time-only dependency of fcitx5/fcitx5-chewing: both projects'
# top-level CMakeLists.txt do `find_package(ECM REQUIRED 1.0.0)` unconditionally
# (fcitx5 5.1.12 CMakeLists.txt line 5; fcitx5-chewing 5.1.7 CMakeLists.txt
# line 4 -- verified by fetching both files directly from the exact pinned
# tags, not assumed from fcitx5's own docs). Zero recipe for this exists
# anywhere in the OE ecosystem -- checked both the wrynose-branch and
# master-branch OpenEmbedded Layer Index (layers.openembedded.org) for
# "extra-cmake-modules"/"ECM", both returned "No matching recipes in
# database", and grepping the actual checked-out meta-openembedded tree at
# its pinned commit (6bf0d8ad57) found zero hits too. This is the one
# self-authored recipe fcitx5's dependency chain needed beyond what oe-core/
# meta-oe already ship (fmt/iso-codes/wayland-protocols/expat/util-linux/
# cairo/pango/gdk-pixbuf are all already present -- verified by listing
# openembedded-core/meta-openembedded's actual recipe files, not guessed).
#
# -native only, no target variant: ECM is a pure build-time CMake find-module
# + macro collection (no runtime library, nothing ships to the image) --
# every consumer (fcitx5, fcitx5-chewing) uses it only inside their own
# CMakeLists.txt at *their* configure time, which always runs on the build
# host regardless of which architecture is being cross-compiled for.

SUMMARY = "Extra CMake Modules -- KDE's CMake find-modules and macros"
DESCRIPTION = "${SUMMARY}. Build-time-only dependency of fcitx5 and \
fcitx5-chewing (find_package(ECM REQUIRED 1.0.0) in both projects' \
top-level CMakeLists.txt) -- provides ECMSetupVersion, ECMUninstallTarget, \
ECMGenerateExportHeader and the other cmake/*.cmake modules those two \
projects' build systems require. Ships no runtime artifact of its own."
HOMEPAGE = "https://invent.kde.org/frameworks/extra-cmake-modules"
LICENSE = "BSD-3-Clause"
LIC_FILES_CHKSUM = "file://COPYING-CMAKE-SCRIPTS;md5=54c7042be62e169199200bc6477f04d1"

# KDE/extra-cmake-modules mirrors the invent.kde.org tree 1:1 on GitHub;
# using the GitHub mirror matches this layer's existing convention of
# fetching third-party sources over plain https git rather than KDE's own
# gitlab (no other recipe in this layer talks to invent.kde.org yet).
SRC_URI = "git://github.com/KDE/extra-cmake-modules.git;protocol=https;branch=master"
# v6.28.0 tag, resolved from its annotated-tag object to the actual commit
# via the GitHub API (git/refs/tags/v6.28.0 -> git/tags/<sha> -> object.sha) --
# not the tag's own SHA, which points at the tag object, not the commit.
SRCREV = "01dc9a0c05dd4851b01b93e961c9aa33b1e96056"
# No explicit S= -- see libchewing_0.9.1.bb's comment: this oe-core release's
# do_unpack sanity check rejects the "${WORKDIR}/git" override this recipe
# originally carried (real failure, caught live during the Y6-1 build).

inherit cmake native

# No runtime code, no docs/tests worth spending build time on in this
# bring-up -- both are off by default upstream anyway (BUILD_TESTING,
# BUILD_HTML_DOCS default to the ECM project's own OFF), listed explicitly
# so a future ECM release flipping a default doesn't silently grow this
# native-only build.
EXTRA_OECMAKE = " \
    -DBUILD_TESTING=OFF \
    -DBUILD_HTML_DOCS=OFF \
    -DBUILD_MAN_DOCS=OFF \
    -DBUILD_QTHELP_DOCS=OFF \
"
