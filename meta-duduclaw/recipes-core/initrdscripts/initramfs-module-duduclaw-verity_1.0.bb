# initramfs-module-duduclaw-verity — dm-verity root activation module for
# initramfs-framework (VER-V, 2026-09-02 — DESIGN-os-trust-chain-2026-09.md
# §3 + 2026-09-02 拍板紀錄 "依賴鏈補記"). See files/duduclaw-verity's own
# header for the full mechanism/cmdline-vocabulary writeup; this recipe's
# job is purely the packaging shape.
#
# Shaped like oe-core's own initramfs-framework recipe
# (openembedded-core/meta/recipes-core/initrdscripts/
# initramfs-framework_1.0.bb, read in full before writing this) — a plain
# `S = "${UNPACKDIR}"`, `do_install` copying one file into `/init.d/`,
# `allarch` (pure shell, no compiled content) — but as its OWN,
# SEPARATE recipe rather than a PACKAGES split added to that oe-core file,
# for the same "many small files, don't fork upstream" reasoning
# classes/duduclaw-rescue-boot.bbclass's own header already states for a
# comparable choice (hand-rolled second do_uki-shaped task instead of
# patching uki.bbclass). Matches the SAME shape
# openembedded-core/meta/recipes-core/initrdscripts/
# initramfs-live-install_1.0.bb uses for its own single-purpose
# `/install.sh` module (also read before writing this) — one recipe, one
# file, one package, `INITRAMFS_SCRIPTS` reaches it by this recipe's own
# PN literally, exactly like every other `initramfs-module-*` entry in
# that variable already does.
#
# INSTALLED FILENAME IS NOT THE SOURCE FILENAME, AND THIS IS LOAD-BEARING:
# initramfs-framework/init's own module-name extraction is
# `module=$(basename $m | cut -d'-' -f2)` — the basename's SECOND
# dash-delimited field, nothing else. A source file named
# "duduclaw-verity" (this recipe's SRC_URI entry, kept dashed for
# repo-readability) installed VERBATIM as e.g. "/init.d/50-duduclaw-verity"
# would extract module="duduclaw" (cut stops at the SECOND dash, silently
# dropping "-verity"), and init would then call the WRONG functions
# (`duduclaw_enabled`/`duduclaw_run`, which do not exist) instead of this
# module's own `duduclaw_verity_enabled`/`duduclaw_verity_run` — a
# guaranteed-silent, hard-to-diagnose boot-time failure if missed. Every
# existing single-word module name in that same directory (udev, e2fs,
# rootfs, debug, lvm, mdev, exec, finish, overlayroot, nfsrootfs) sidesteps
# this by having NO internal dash at all; this module's own concept name
# genuinely needs two words, so the fix is to use an UNDERSCORE between
# them in the INSTALLED name only — `cut -d'-' -f2` does not treat `_` as
# a delimiter, so "50-duduclaw_verity" extracts module="duduclaw_verity"
# whole, matching the shell function names files/duduclaw-verity actually
# defines. do_install below renames on install for exactly this reason —
# not a typo.
SUMMARY = "initramfs-framework module: activate dm-verity root before mounting"
DESCRIPTION = "${SUMMARY}. Reads the roothash=/hashdev= kernel cmdline \
tokens classes/duduclaw-verity.bbclass bakes into a Secure-Boot-signed \
UKI (alongside the already-existing root=PARTUUID=, reused verbatim as \
the dm-verity data device), runs `veritysetup open` to construct \
/dev/mapper/duduclaw-vroot, and redirects initramfs-framework's own \
rootfs module at it -- fail-closed on any verification failure (refuses \
to fall back to mounting the plaintext root partition). Absent cmdline \
tokens (DUDUCLAW_VERITY_ENABLE unset at build time) make this module a \
complete no-op."
HOMEPAGE = "https://github.com/duduclaw/duduclaw"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://duduclaw-verity"

S = "${UNPACKDIR}"

inherit allarch

do_install() {
    install -d ${D}/init.d
    # See this recipe's own header: the installed name MUST use an
    # underscore, not a dash, between "duduclaw" and "verity" --
    # initramfs-framework/init's own `cut -d'-' -f2` module-name
    # extraction depends on it.
    install -m 0755 ${UNPACKDIR}/duduclaw-verity ${D}/init.d/50-duduclaw_verity
}

FILES:${PN} = "/init.d/50-duduclaw_verity"

# initramfs-framework-base: this module's `fatal`/`info`/`debug`/
# `load_kernel_module` helper functions and the `bootparam_*` variable
# convention all come from initramfs-framework/init's own top-level body
# (RRECOMMENDS'd in by every INITRAMFS_SCRIPTS entry, matching e.g.
# `RDEPENDS:initramfs-module-udev = "${PN}-base udev"` in oe-core's own
# initramfs-framework_1.0.bb -- ${PN} there resolves to
# "initramfs-framework", not this recipe's own PN, so it must be spelled
# out literally here).
#
# initramfs-module-udev: this module reads /dev/disk/by-partuuid/*
# symlinks that only exist once initramfs-framework's own udev module has
# run `udevadm trigger --action=add && udevadm settle` (see
# files/duduclaw-verity's own header) -- a real ordering dependency, not
# just a "happens to be listed" one, though INITRAMFS_SCRIPTS' own
# lexical-filename module ordering is what actually enforces the ordering
# at boot; this RDEPENDS only guarantees the udev module's PACKAGE (and
# therefore its /dev-populating binaries) ends up installed at all.
#
# cryptsetup: provides the target `veritysetup` binary this module
# execs directly (bare, on PATH -- no DEPENDS-native involved here, this
# is the TARGET package landing inside the initramfs rootfs image, a
# completely separate concern from classes/duduclaw-verity.bbclass's own
# `cryptsetup-native` DEPENDS used for the BUILD-TIME `veritysetup format`
# step). CONFIG_DM_VERITY=y is compiled directly into the kernel
# (recipes-kernel/linux/linux-yocto/duduclaw-verity.cfg) -- no dm-verity
# kernel MODULE needs loading, so no `kernel-module-dm-*` RDEPENDS is
# needed the way e.g. RRECOMMENDS:${PN}:class-target on cryptsetup's own
# recipe lists `kernel-module-dm-crypt` for its OWN (LUKS, not verity)
# use case.
RDEPENDS:${PN} = "initramfs-framework-base initramfs-module-udev cryptsetup"

# Same host-arch restriction as initramfs-framework itself (allarch
# content, but the CONSUMING initramfs image is machine-specific) -- not
# copied blindly, this recipe genuinely has no compiled content and no
# machine-specific text, matching `inherit allarch` above.
COMPATIBLE_HOST = '(x86_64.*|i.86.*|arm.*|aarch64.*)-(linux.*|freebsd.*)'
