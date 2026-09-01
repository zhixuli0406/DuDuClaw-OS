# DuDuClaw OS — sbsigntool (classic sbsigntools, "sbsign"/"sbverify"),
# WS-3/SB-2/SB-3 Secure Boot signing-chain wiring (2026-09-02).
#
# WHY THIS RECIPE EXISTS AT ALL — three build-time-verified facts, not
# guesses, ruled out the two alternatives before landing on "vendor this
# one recipe":
#
#   1. oe-core's own uki.bbclass (meta/classes-recipe/uki.bbclass, this
#      layer's pinned commit) says outright in its header comment: "for
#      UEFI secure boot, systemd-boot and uki (including kernel) can be
#      signed but require sbsign-tool-native (recipe available from
#      meta-secure-core...)". uki.bbclass's own DEPENDS never lists it —
#      the class only ever *consumes* UKI_SB_KEY/UKI_SB_CERT if a signing
#      tool happens to already be on PATH; providing that tool is left to
#      whoever turns Secure Boot on, which on this line is this recipe +
#      classes/duduclaw-secure-boot.bbclass.
#
#   2. systemd's own ukify (src/ukify/ukify.py at this line's pinned
#      SRCREV b3d8fc43e9cb531d958c17ef2cd93b374bc14e8a — read directly from
#      the builder's own git2 download cache before writing this, not
#      assumed) infers `--signtool=sbsign` — i.e. the CLASSIC sbsigntools
#      `sbsign` binary this recipe builds, NOT systemd's own
#      `systemd-sbsign` — whenever only `--secureboot-private-key=` and
#      `--secureboot-certificate=` are given with no certificate NAME
#      (ukify.py's own opts-inference block: "both param given, infer
#      sbsign ... if not opts.signtool: opts.signtool = 'sbsign'"). That is
#      EXACTLY the call shape uki.bbclass's do_uki and
#      classes/duduclaw-rescue-boot.bbclass's do_uki_rescue both already
#      make (UKI_SB_KEY/UKI_SB_CERT only, no --signtool, no certificate
#      name) — so `sbsign` being on PATH, with zero further ukify
#      configuration, is sufficient. See classes/duduclaw-secure-boot.bbclass's
#      own header for why `systemd-sbsign` (the OTHER tool ukify supports)
#      was ruled out instead of vendored: it requires a real native meson
#      build of systemd itself (`src/sbsign/meson.build`'s
#      `systemd-sbsign` executable links systemd's own internal
#      libbasic/libshared, confirmed by reading `src/sbsign/sbsign.c`'s
#      own #include list), but `systemd-boot-native_259.5.bb` — the ONLY
#      native systemd recipe this layer already builds — deliberately
#      `deltask do_configure` + `deltask do_compile` and installs nothing
#      but the pure-Python `ukify.py` script. Reversing that to grow a full
#      native systemd meson build, just to get one binary ukify does not
#      even prefer by default, would be a large, high-risk change working
#      against that recipe's own designed-lean shape — not "minimal diff".
#
#   3. This is upstream's own answer to the same question: meta-secure-core
#      (github.com/Wind-River/meta-secure-core,
#      meta-signing-key/recipes-devtools/sbsigntool/sbsigntool_0.9.5.bb,
#      fetched directly and read before writing this file, not
#      reconstructed from memory) ships exactly this — classic upstream
#      sbsigntools (git.kernel.org/pub/scm/linux/kernel/git/jejb/
#      sbsigntools.git) + a small, already-proven patch set, built via
#      `BBCLASSEXTEND = "native nativesdk"` rather than a hand-forked
#      "-native"-suffixed recipe file. This recipe VENDORS that one recipe
#      + its 6 patches byte-for-byte (SRCREVs, patch content, DEPENDS all
#      unchanged) — not the whole meta-secure-core layer, which also
#      carries pesign/tpm2/ima/IMA-signing recipes this line has no use
#      for and no evidence base to maintain.
#
# ONLY the native variant is actually consumed by this layer today (see
# classes/duduclaw-secure-boot.bbclass's DEPENDS:append and
# recipes-core/systemd/systemd-boot_%.bbappend's own DEPENDS:append, both
# name `sbsigntool-native`) — BBCLASSEXTEND still offers the plain target
# variant too, unchanged from upstream, in case a future on-device
# signature-verification story wants `sbverify` in the rootfs; nothing in
# this ticket's own image recipes installs it.

SUMMARY = "Utilities for signing UEFI binaries for use with secure boot"

LICENSE = "GPL-3.0-or-later"
LIC_FILES_CHKSUM = "\
    file://LICENSE.GPLv3;md5=9eef91148a9b14ec7f9df333daebc746 \
    file://COPYING;md5=a7710ac18adec371b84a9594ed04fd20 \
"

DEPENDS = "binutils openssl gnu-efi util-linux-libuuid"

SRC_URI = " \
    git://git.kernel.org/pub/scm/linux/kernel/git/jejb/sbsigntools.git;protocol=https;name=sbsigntools;branch=master \
    git://github.com/rustyrussell/ccan.git;protocol=https;destsuffix=${BB_GIT_DEFAULT_DESTSUFFIX}/lib/ccan.git;name=ccan;branch=master \
    file://0001-configure-Dont-t-check-for-gnu-efi.patch \
    file://0002-docs-Don-t-build-man-pages.patch \
    file://0003-sbsign-add-x-option-to-avoid-overwrite-existing-sign.patch \
    file://0004-src-Makefile.am-Add-read_write_all.c-to-common_SOURC.patch \
    file://0005-fileio.c-initialize-local-variables-before-use-in-fu.patch \
    file://0006-Makefile.am-do-not-use-Werror.patch \
"

SRCREV_sbsigntools  = "9cfca9fe7aa7a8e29b92fe33ce8433e212c9a8ba"
SRCREV_ccan         = "b1f28e17227f2320d07fe052a8a48942fe17caa5"
SRCREV_FORMAT       =  "sbsigntools_ccan"

COMPATIBLE_HOST = "(x86_64.*|i.86.*|aarch64.*|arm.*|riscv64.*)-linux"
COMPATIBLE_HOST:armv4 = 'null'

inherit autotools pkgconfig

do_configure:prepend() {
    if [ ! -e ${S}/lib/ccan ]; then
        CC="${BUILD_CC}" CFLAGS="${BUILD_CFLAGS}" LDFLAGS="${BUILD_LDFLAGS}" \
            ${S}/lib/ccan.git/tools/create-ccan-tree \
            --build-type=automake ${S}/lib/ccan \
            talloc read_write_all build_assert array_size endian
    fi

    # Not shipped in the sbsigntools git tree but required because
    # configure.ac uses gnu strictness (automake refuses to configure
    # without them) — same upstream-recipe fix, unchanged.
    touch ${S}/AUTHORS ${S}/ChangeLog
}

BBCLASSEXTEND = "native nativesdk"
