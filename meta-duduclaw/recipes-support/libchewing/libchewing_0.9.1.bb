# libchewing -- Y6-1, 2026-08-26. Zhuyin (bopomofo) input method core
# library, the engine fcitx5-chewing wraps. Version 0.9.1 pinned to EXACTLY
# match Debian trixie's own `libchewing3` package version (checked via
# sources.debian.org's API, not guessed) -- this is the same build already
# proven correct end-to-end on the Debian `appliance/` line (D3/D3-f/W7-3
# rounds), so the Yocto line inherits the same known-good candidate/config
# semantics instead of introducing a second, untested version's behavior.
#
# Zero recipe for this exists anywhere in the OE ecosystem (OpenEmbedded
# Layer Index wrynose/master branches both return "No matching recipes in
# database" for "chewing"/"libchewing"; meta-openembedded's checked-out tree
# at its pinned commit has zero hits either) -- self-authored per the task's
# own "沒有就評自建 recipe 量級" instruction.
#
# ---------------------------------------------------------------------
# Why this recipe does NOT use libchewing's own CMakeLists.txt/corrosion
# ---------------------------------------------------------------------
# libchewing 0.9.1's C ABI is produced almost entirely by a Rust crate
# (capi/, package name `chewing_capi`) exporting 130 `#[no_mangle] extern
# "C"` symbols directly -- `capi/src/chewing.c`, the one C source file
# CMakeLists.txt's `add_library(libchewing ...)` lists, is a LITERALLY
# EMPTY file (verified: `wc -l` = 0), confirmed by inspecting the actual
# v0.9.1 source tree, not assumed. Upstream's own CMakeLists.txt drives this
# Rust build via `corrosion_import_crate()` (the CMake/Cargo bridge project
# "corrosion-rs/corrosion"), which has ZERO OE recipe anywhere either and
# would need FetchContent-ing a git repo at CMake CONFIGURE time if not
# pre-packaged -- a live network fetch during do_configure that Yocto's
# BB_NO_NETWORK-after-do_fetch model forbids.
#
# Investigated whether packaging corrosion-native was worth it (it would
# let this recipe reuse upstream's CMakeLists.txt verbatim, including its
# `install(EXPORT ...)` CMake package config for downstream consumers to
# `find_package(Chewing)`) and found it UNNECESSARY: fcitx5-chewing 5.1.7's
# own CMakeLists.txt (fetched and read directly from the pinned tag)
# discovers libchewing via plain `pkg_check_modules(Chewing "chewing>=0.5.0"
# IMPORTED_TARGET REQUIRED)` -- pkg-config, not CMake's `find_package`. A
# correct `chewing.pc` + `.so` + headers at standard paths is therefore
# sufficient; no CMake package config, no corrosion, needed at all.
#
# So this recipe drives `cargo build` directly (oe-core's own `cargo`
# bbclass, the same mechanism this layer already uses for the five
# duduclaw-* binaries) against the `capi` workspace member only, then
# manually performs the two steps upstream's CMakeLists.txt would otherwise
# have corrosion+CMake do: link the resulting Rust staticlib into a
# properly SONAME'd/version-scripted .so, and (native-side) run the
# `chewing-cli` data-generation tool. Every step below (the plain `cargo
# build -p chewing_capi` command, the exact `gcc -shared -Wl,--version-
# script,capi/src/symbols-elf.map -Wl,-u,chewing_version -Wl,-soname,
# libchewing.so.3` invocation, and the `chewing-cli init-database` data
# pipeline) was validated ONCE, for real, natively inside the yocto-builder
# container (apt-installed cargo+rustc+libsqlite3-dev, zero cross-compile)
# before being written into this recipe -- not guessed from reading
# CMakeLists.txt alone. That validation run produced a working
# `libchewing.so.3.3.1` (`SONAME libchewing.so.3`, `chewing_new@@CHEWING_0.5`
# versioned symbol confirmed via `nm -D`) and real dictionary data
# (tsi.dat: 158037 phrases; word.dat: 26096 words, both via `chewing-cli
# init-database` against the real `data/tsi.src`/`data/word.src`).
#
# The `LIBCHEWING_BINARY_VERSION`/`SOVERSION 3`/`VERSION 3.3.1` values below
# are lifted verbatim from libchewing's own top-level CMakeLists.txt (its
# library's ABI version line, independent of the 0.9.1 project/release
# version) -- not invented, so a future consumer expecting upstream's own
# SONAME scheme sees the same one this recipe would have produced via the
# "real" CMake+corrosion path.

SUMMARY = "libchewing -- intelligent Zhuyin (bopomofo) phonetic input method library"
DESCRIPTION = "${SUMMARY}. Provides the core algorithm/dictionary engine \
fcitx5-chewing wraps to give this appliance's kiosk session Chinese text \
input (D3/W7-3 Debian-line convention, ported to the Yocto base per Y6-1)."
HOMEPAGE = "https://chewing.im"
LICENSE = "LGPL-2.1-or-later"
LIC_FILES_CHKSUM = "file://COPYING;md5=4fbd65380cdd255951079008b364516c"

SRC_URI = "git://github.com/chewing/libchewing.git;protocol=https;branch=master"
# v0.9.1 tag is annotated -- this is the COMMIT it points at (resolved via
# GitHub API git/refs/tags/v0.9.1 -> git/tags/<tag-object-sha> -> object.sha),
# not the tag object's own sha.
SRCREV = "bab025039a24d610d5c327d6894356a3d645e441"
# No explicit S= : real do_unpack failure on this oe-core release caught it --
# "Recipes that set S = "${WORKDIR}/git" ... should remove that assignment,
# as S set by bitbake.conf in oe-core now works" -- bitbake.conf's own
# default (S = "${UNPACKDIR}/${BP}") already resolves correctly for a
# single git:// SRC_URI on this release; the explicit override this recipe
# originally carried is what modern oe-core now flags as redundant/wrong.

require libchewing-crates.inc

inherit cargo cargo-update-recipe-crates

# Two build shapes out of the SAME source, matching how upstream's own
# workspace splits it -- the target build produces just the runtime shared
# library (default cargo features: no sqlite, matching CMakeLists.txt not
# passing `corrosion_set_features(chewing_capi FEATURES sqlite)` unless its
# own `-DBUILD_SQL=1`-equivalent option is explicitly requested, which this
# recipe does not need), the native build produces the `chewing-cli` data
# preprocessor the target install step below invokes.
BBCLASSEXTEND = "native"

CARGO_SRC_DIR = "capi"
CARGO_SRC_DIR:class-native = "tools"

# native-only: chewing-cli's Cargo.toml unconditionally depends on
# `chewing = { features = ["sqlite"] }` (verified by reading tools/Cargo.toml
# at the pinned commit), which needs rusqlite -> libsqlite3-sys -> a real
# sqlite3 to link against. Validated live: the native sanity build failed
# with "cannot find -lsqlite3" until this was installed, then succeeded.
DEPENDS:append:class-native = " sqlite3-native"

# target-only: do_install below needs the NATIVE chewing-cli binary (a
# build-time data preprocessor, never shipped to target) to turn the
# checked-in tsi.src/word.src text tables into the tsi.dat/word.dat binary
# tries the runtime library actually loads. Same-recipe self-native-DEPENDS
# is the standard OE pattern for "one source produces both a host codegen
# tool and a target artifact" (matches e.g. how various cross toolchain
# support recipes depend on their own -native counterpart).
DEPENDS:append:class-target = " libchewing-native"

LIBCHEWING_SOVERSION = "3"
LIBCHEWING_LIBVERSION = "3.3.1"
LIBCHEWING_PV = "0.9.1"

# The target variant only needs to produce+link the shared library -- the
# default cargo_do_install (cargo.bbclass) only knows how to install *.so/
# *.rlib (gated behind CARGO_INSTALL_LIBRARIES, unset here) or executables;
# a bare *.a staticlib with no executable in the release dir would hit its
# `die "Did not find anything to install"` path. Full custom override.
#
# The native variant is left at cargo.bbclass's DEFAULT do_install: tools/
# builds an actual [[bin]] (chewing-cli), which the default install loop's
# `*)` executable-file branch already picks up and installs to
# ${D}${bindir}/chewing-cli correctly -- verified by the same native
# sanity-build round (ls target/release/chewing-cli, real 19MB ELF).
do_install:class-target() {
    local capi_dir="${B}/target/${CARGO_TARGET_SUBDIR}"
    local capi_lib="${capi_dir}/libchewing_capi.a"
    local sofile="libchewing.so.${LIBCHEWING_LIBVERSION}"
    local soname="libchewing.so.${LIBCHEWING_SOVERSION}"

    [ -f "${capi_lib}" ] || die "libchewing_capi.a not found at ${capi_lib} -- cargo build output layout changed?"

    install -d ${D}${libdir}
    # Mirrors the CMakeLists.txt link line this recipe deliberately does not
    # run via CMake+corrosion (see header comment): version-scripted,
    # SONAME'd shared object built straight from the Rust staticlib. The
    # empty capi/src/chewing.c contributes no symbols and is intentionally
    # not compiled/linked here (see header comment -- verified empty, not
    # assumed). `-Wl,-u,chewing_version` mirrors CMakeLists.txt's own
    # `LINKER:-u,chewing_version` -- keeps a symbol alive that the version
    # script needs but nothing else in this link references.
    ${CC} ${LDFLAGS} -shared \
        -Wl,--whole-archive "${capi_lib}" -Wl,--no-whole-archive \
        -Wl,--version-script,${S}/capi/src/symbols-elf.map \
        -Wl,-u,chewing_version \
        -Wl,-soname,${soname} \
        -o ${D}${libdir}/${sofile} \
        -lpthread -ldl -lm
    ln -sf ${sofile} ${D}${libdir}/${soname}
    ln -sf ${soname} ${D}${libdir}/libchewing.so

    install -d ${D}${includedir}/chewing
    install -m 0644 ${S}/include/*.h ${D}${includedir}/chewing/

    install -d ${D}${libdir}/pkgconfig
    sed \
        -e 's|@prefix@|${prefix}|g' \
        -e 's|@exec_prefix@|${exec_prefix}|g' \
        -e 's|@libdir@|${libdir}|g' \
        -e 's|@includedir@|${includedir}|g' \
        -e 's|@datarootdir@|${datadir}|g' \
        -e 's|@sysconfdir@|${sysconfdir}|g' \
        -e 's|@LIBCHEWING_BINARY_VERSION@|${LIBCHEWING_LIBVERSION}|g' \
        -e 's|@PACKAGE_VERSION@|${LIBCHEWING_PV}|g' \
        ${S}/chewing.pc.in > ${D}${libdir}/pkgconfig/chewing.pc

    # Data pipeline: mirrors data/CMakeLists.txt's `ALL_DATA` target
    # (tsi.dat + word.dat, generated) plus `ALL_STATIC_DATA` (swkb.dat +
    # symbols.dat, copied verbatim) -- deliberately excludes the separate
    # mini.dat side-outputs that same CMakeLists.txt's custom_command also
    # produces, since data/CMakeLists.txt's own `install(FILES ${ALL_DATA}
    # ...)` line never installs mini.dat either (it exists only for
    # libchewing's own embedded/self-test use, confirmed by reading the
    # full data/CMakeLists.txt, not assumed from the target name alone).
    install -d ${D}${datadir}/libchewing
    ${STAGING_BINDIR_NATIVE}/chewing-cli init-database \
        -c "Copyright (c) 2022 libchewing Core Team" \
        -l "LGPL-2.1-or-later" \
        -r "${LIBCHEWING_PV}" \
        -t trie \
        -n "內建詞庫" \
        ${S}/data/tsi.src ${D}${datadir}/libchewing/tsi.dat
    ${STAGING_BINDIR_NATIVE}/chewing-cli init-database \
        -c "Copyright (c) 2022 libchewing Core Team" \
        -l "LGPL-2.1-or-later" \
        -r "${LIBCHEWING_PV}" \
        -t trie \
        -n "內建字庫" \
        ${S}/data/word.src ${D}${datadir}/libchewing/word.dat
    install -m 0644 ${S}/data/swkb.dat ${D}${datadir}/libchewing/swkb.dat
    install -m 0644 ${S}/data/symbols.dat ${D}${datadir}/libchewing/symbols.dat
}

# Default bitbake.conf FILES classification (SOLIBS=".so.*" -> ${PN},
# SOLIBSDEV=".so" + ${includedir} + ${libdir}/pkgconfig -> ${PN}-dev,
# ${datadir}/${BPN} -> ${PN}) already produces the right split with zero
# custom FILES lines: libchewing.so.3.3.1 + libchewing.so.3 + the
# datadir/libchewing tree go to the main package, libchewing.so +
# include/chewing/*.h + pkgconfig/chewing.pc go to -dev. Not overridden --
# if a real bitbake run proves this wrong, fix it then (see Y6-1 TODO entry
# for verification status), not with a preemptive INSANE_SKIP.
