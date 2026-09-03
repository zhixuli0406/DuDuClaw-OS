# initramfs-module-duduclaw-persist — machine-id + entropy-seed cross-boot
# persistence module for initramfs-framework (VER-P, 信任鏈 P1 殘項,
# 2026-09-03). See files/duduclaw-persist's own header for the full
# mechanism/ordering/citation writeup; this recipe's job is purely the
# packaging shape, mirrored deliberately from
# initramfs-module-duduclaw-verity_1.0.bb (read that recipe in full before
# writing this one — same `S = "${UNPACKDIR}"`, same `allarch`, same
# do_install-time filename rename for the identical module-name-extraction
# reason).
#
# INSTALLED FILENAME IS NOT THE SOURCE FILENAME, AND THIS IS LOAD-BEARING
# — same rule, same reason, as initramfs-module-duduclaw-verity_1.0.bb's
# own header already documents in full (initramfs-framework/init's own
# `module=$(basename $m | cut -d'-' -f2)` extraction, verified directly
# against that exact line this round): a source file named
# "duduclaw-persist" installed VERBATIM would extract module="duduclaw",
# not "duduclaw_persist" — the underscore in the INSTALLED name
# ("92-duduclaw_persist") is what keeps `cut -d'-' -f2` from splitting
# after the first dash.
SUMMARY = "initramfs-framework module: persist machine-id + entropy seed across reboots on a read-only root"
DESCRIPTION = "${SUMMARY}. Runs AFTER initramfs-framework's own rootfs \
module (90-rootfs) has mounted the real root at \$ROOTFS_DIR, and BEFORE \
finish (99-finish) calls switch_root -- see files/duduclaw-persist's own \
header, 'MODULE ORDERING', for the full citation trail on why this \
ordering (the OPPOSITE of initramfs-module-duduclaw-verity, which runs \
BEFORE 90-rootfs) is required. Bind-mounts a persisted machine-id file \
from /data onto \${ROOTFS_DIR}/etc/machine-id (surviving switch_root the \
same way finish's own /dev,/proc,/sys,/run moves already do) and loads a \
persisted entropy seed into /dev/urandom. Skips cleanly (fail-open, \
console-logged, non-fatal) when /data is not yet reachable, or when /data \
has already been converted to TPM2+LUKS2 by the separate TPM wave (this \
initrd has no TPM2 unlock path -- that lives in the main system's own \
duduclaw-data-open generator/service, which runs after switch_root)."
HOMEPAGE = "https://github.com/duduclaw/duduclaw"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://duduclaw-persist"

S = "${UNPACKDIR}"

inherit allarch

# duduclaw-ab-partflags: the ONLY reason is DUDUCLAW_AB_DATA_PARTUUID,
# reused verbatim from the SAME build-time constant
# recipes-duduclaw/duduclaw-data-open.bb's own do_install already bakes
# into its two runtime scripts via the identical `@TOKEN@` + sed
# mechanism (see that recipe's own header for why this mechanism, not
# bitbake ${VAR} expansion, is correct for a SRC_URI file destined to be
# read by the RUNNING system rather than consumed by a later bitbake
# task). Round-4 TPM live evidence (cited in duduclaw-data-open.bb's own
# header) already showed what happens when this inherit is missing:
# `${DUDUCLAW_AB_DATA_PARTUUID}` resolves empty, sed substitutes it away
# to nothing, and the module ends up probing `/dev/disk/by-partuuid/` (a
# DIRECTORY, which `[ -e ... ]` happily accepts) instead of the real
# device file. The same belt-and-braces empty-substitution guard that
# recipe's own do_install uses is reused below for the identical reason.
inherit duduclaw-ab-partflags

do_install() {
    install -d ${D}/init.d
    # See this recipe's own header: the installed name MUST use an
    # underscore, not a dash, between "duduclaw" and "persist" --
    # initramfs-framework/init's own `cut -d'-' -f2` module-name
    # extraction depends on it. "92" sits strictly between 90-rootfs
    # (must run after) and 99-finish (must run before) -- see
    # files/duduclaw-persist's own header, "MODULE ORDERING", for the
    # full reasoning.
    install -m 0755 ${UNPACKDIR}/duduclaw-persist ${D}/init.d/92-duduclaw_persist

    # Bake the build-time-constant /data GPT PARTUUID into the installed
    # module -- same `@TOKEN@` + sed mechanism, same belt-and-braces
    # empty-substitution guard, as recipes-duduclaw/duduclaw-data-open.bb's
    # own do_install (see this recipe's own header for the citation).
    [ -n "${DUDUCLAW_AB_DATA_PARTUUID}" ] || bbfatal "DUDUCLAW_AB_DATA_PARTUUID resolved empty -- refusing to install a module that would end up probing /dev/disk/by-partuuid/ (a directory, not a device). Check the duduclaw-ab-partflags inherit."
    sed -i "s|@DUDUCLAW_AB_DATA_PARTUUID@|${DUDUCLAW_AB_DATA_PARTUUID}|" \
        ${D}/init.d/92-duduclaw_persist
}

FILES:${PN} = "/init.d/92-duduclaw_persist"

# initramfs-framework-base: `msg`/`info`/`debug`/`fatal` helper functions
# and the `bootparam_*`/`ROOTFS_DIR` variable convention this module reads
# all come from initramfs-framework/init's own top-level body -- spelled
# out literally here for the same reason
# initramfs-module-duduclaw-verity_1.0.bb's own RDEPENDS comment already
# gives (${PN} inside THAT recipe's context would resolve to THIS
# recipe's own PN, not "initramfs-framework", so it cannot be left
# implicit).
#
# initramfs-module-rootfs: a REAL ordering dependency, not just a
# "happens to be listed" one -- this module's own machine-id bind-mount
# target ($ROOTFS_DIR/etc/machine-id) only exists once that module's own
# rootfs_run() has mounted the real root. INITRAMFS_SCRIPTS' own
# lexical-filename module ordering (92 after 90) is what actually
# enforces the ordering at boot; this RDEPENDS only guarantees the
# rootfs module's PACKAGE (and therefore initramfs-framework-base's own
# RRECOMMENDS chain that already pulls it in on this image, see
# files/duduclaw-persist's own header) is genuinely present at all --
# same belt-and-braces posture initramfs-module-duduclaw-verity_1.0.bb's
# own RDEPENDS on initramfs-module-udev already established for an
# analogous ordering dependency.
#
# util-linux-blkid: `blkid -o value -s TYPE` (the LUKS-compatibility
# skip check, files/duduclaw-persist's own header, "LUKS compatibility
# skip"). A genuinely NEW tool for this initramfs (not already pulled in
# by anything else in this image's own INITRAMFS_SCRIPTS list) -- named
# explicitly rather than assumed present, same "name the split package
# explicitly" discipline recipes-duduclaw/duduclaw-data-open.bb's own
# header already states for the identical tool.
#
# No cryptsetup/veritysetup RDEPENDS here -- unlike
# initramfs-module-duduclaw-verity, this module never opens a dm-verity
# or dm-crypt device itself; the LUKS case is a clean SKIP, not an
# unlock attempt (see files/duduclaw-persist's own header for why an
# unlock attempt here would be wrong even if it were technically
# possible).
RDEPENDS:${PN} = "initramfs-framework-base initramfs-module-rootfs util-linux-blkid"

# Same host-arch restriction as initramfs-module-duduclaw-verity_1.0.bb
# for the identical reason: allarch content (plain POSIX shell, no
# compiled payload), but the CONSUMING initramfs image is
# machine-specific.
COMPATIBLE_HOST = '(x86_64.*|i.86.*|arm.*|aarch64.*)-(linux.*|freebsd.*)'
