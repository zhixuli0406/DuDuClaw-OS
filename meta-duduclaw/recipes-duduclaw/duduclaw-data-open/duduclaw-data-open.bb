SUMMARY = "DuDuClaw OS /data TPM2+LUKS2 unlock (trust chain P1 wave TPM)"
DESCRIPTION = "${SUMMARY}. commercial/docs/DESIGN-os-trust-chain-2026-09.md \
§4 + 2026-09-02 拍板紀錄 T5(靜態 PCR 7+11)/T6(LUKS /data 解鎖優先)/ \
T7(TPM 缺席 fail-open). A systemd generator (installed to \
${nonarch_libdir}/systemd/system-generators/) decides, on every boot, \
whether /data needs a TPM2+LUKS2 unit graph in place of the plain \
PARTUUID mount classes/duduclaw-verity.bbclass's own static /etc/fstab \
line already provides — writing into the HIGHEST-priority generator \
output directory (generator.early) only when relevant, so a device with \
no TPM chip stays byte-identical to the pre-existing plain path (T7). \
The actual first-boot conversion (wipe+luksFormat+TPM2-enroll+recovery-key) \
and every-boot unlock (fail-closed on a PCR mismatch) live in a separate \
oneshot service the generator writes, never in the generator itself \
(generators must stay fast; see files/duduclaw-data-open-generator's own \
header). See files/duduclaw-data-open.sh's own header for the full \
four-cell fail-open/fail-closed truth table and one-hand CLI citations \
for every cryptsetup/systemd-cryptenroll/systemd-cryptsetup invocation."
HOMEPAGE = "https://github.com/duduclaw/duduclaw"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = " \
    file://duduclaw-data-open-generator \
    file://duduclaw-data-open.sh \
    file://duduclaw-data-status.service \
"

inherit systemd allarch
# duduclaw-ab-partflags: the ONLY reason is DUDUCLAW_AB_DATA_PARTUUID.
# TPM round-4 live evidence (rpm2cpio of the actually-shipped package):
# without this inherit the recipe-scope getVar was EMPTY, do_install's
# sed silently substituted @DUDUCLAW_AB_DATA_PARTUUID@ -> "" and both
# the generator and the script probed /dev/disk/by-partuuid/ (a
# DIRECTORY, which [[ -e ]] happily accepts) — the service then died in
# 0.29s with no usable device and took the whole /data chain down.
# bitbake has no "sed with an unset variable" guard; the inherit is what
# makes the constant real in THIS recipe's datastore. A belt-and-braces
# assertion below refuses to install an empty substitution ever again.
inherit duduclaw-ab-partflags

do_install() {
    # Generator — NOT a systemd unit, installed to the generator
    # directory, not ${systemd_system_unitdir}. ${nonarch_libdir}/systemd/
    # system-generators/ is the exact path systemd's OWN recipe installs
    # its own generators to (systemd_259.5.bb: systemd-gpt-auto-generator
    # lands at literally that path — confirmed by reading that recipe
    # directly, not guessed from a plausible-looking oe-core convention).
    install -d ${D}${nonarch_libdir}/systemd/system-generators
    install -m 0755 ${UNPACKDIR}/duduclaw-data-open-generator \
        ${D}${nonarch_libdir}/systemd/system-generators/duduclaw-data-open-generator

    install -d ${D}${sbindir}
    install -m 0755 ${UNPACKDIR}/duduclaw-data-open.sh ${D}${sbindir}/duduclaw-data-open.sh

    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${UNPACKDIR}/duduclaw-data-status.service \
        ${D}${systemd_system_unitdir}/duduclaw-data-status.service

    # Bake the build-time-constant /data GPT PARTUUID into both shipped
    # scripts (classes/duduclaw-ab-partflags.bbclass's own
    # DUDUCLAW_AB_DATA_PARTUUID — "dedec1a0-...-000f", the SAME constant
    # classes/duduclaw-verity.bbclass's own static-fstab hook already
    # bakes into /etc/fstab). Plain `@TOKEN@` placeholder + sed, not
    # bitbake's own ${VAR} expansion inside the SRC_URI file (SRC_URI
    # files are copied verbatim by the fetcher, never datastore-expanded —
    # this is the standard, simplest mechanism for baking a build-time
    # constant into an installed runtime script this layer's other
    # recipes reach for when they need one; classes/duduclaw-verity
    # .bbclass's own cmdline injection solves the analogous problem a
    # different way — Python string formatting into a bitbake variable at
    # TASK time — because ITS target is a bitbake variable
    # (UKI_CMDLINE/UKI_RESCUE_CMDLINE/UKI_SLOTB_CMDLINE) consumed by a
    # LATER bitbake task, not an installed file read by the running
    # system; the two problems are only superficially similar).
    [ -n "${DUDUCLAW_AB_DATA_PARTUUID}" ] || bbfatal "DUDUCLAW_AB_DATA_PARTUUID resolved empty -- refusing to bake a generator probing /dev/disk/by-partuuid/ (a directory). Check the duduclaw-ab-partflags inherit."
    sed -i "s|@DUDUCLAW_AB_DATA_PARTUUID@|${DUDUCLAW_AB_DATA_PARTUUID}|" \
        ${D}${nonarch_libdir}/systemd/system-generators/duduclaw-data-open-generator \
        ${D}${sbindir}/duduclaw-data-open.sh
}

# duduclaw-data-status.service carries its own [Install] section and is
# reached through the normal enable/wants-symlink mechanism (SYSTEMD_SERVICE/
# SYSTEMD_AUTO_ENABLE), matching recipes-duduclaw/duduclaw-firstboot.bb's
# own convention for its own always-installed units. duduclaw-data-open
# .service and data.mount are DELIBERATELY NOT listed here — they have no
# static unit files at all (this recipe's own generator writes them
# dynamically, only on a boot where they are relevant — see this recipe's
# own DESCRIPTION and the generator script's own header for why a static
# [Install] entry for either would defeat the entire point of this
# design).
SYSTEMD_SERVICE:${PN} = "duduclaw-data-status.service"
SYSTEMD_AUTO_ENABLE:${PN} = "enable"

FILES:${PN} += " \
    ${nonarch_libdir}/systemd/system-generators/duduclaw-data-open-generator \
    ${sbindir}/duduclaw-data-open.sh \
    ${systemd_system_unitdir}/duduclaw-data-status.service \
"

# bash: both shipped scripts use `set -euo pipefail`/`[[ ]]` (bash-isms),
# same requirement recipes-duduclaw/duduclaw-firstboot.bb's own scripts
# already state (and the SAME shell this recipe's own generator runs
# under too — see that script's own header for why a generator being
# written in bash, not POSIX /bin/sh, is a deliberate, documented choice,
# not an oversight).
#
# cryptsetup: `cryptsetup luksFormat` (duduclaw-data-open.sh's own first-
# boot conversion path). Listed explicitly here even though classes/
# duduclaw-verity.bbclass's own IMAGE_INSTALL:append ALSO pulls this
# package in when DUDUCLAW_VERITY_ENABLE=1 (a hard prerequisite state for
# DUDUCLAW_TPM_ENABLE=1 to make sense at all per this design's own §5.1
# SB→verity→TPM order) — this recipe does not rely on that cross-wave
# coupling staying true; RDEPENDS document the ACTUAL, direct dependency,
# duplicate RDEPENDS across two packages on the same image are harmless.
#
# systemd-crypt: `systemd-cryptenroll` (${bindir}/systemd-cryptenroll,
# FILES:${PN}-crypt in systemd_259.5.bb) — the enrollment side. See
# classes/duduclaw-tpm.bbclass's own header for why this is an EXPLICIT
# RDEPENDS rather than relying on systemd's own RRECOMMENDS-only pull.
# `systemd-cryptsetup` (the unlock side) needs no separate RDEPENDS — it
# lands in the main, always-installed `systemd` package (unclaimed by any
# PACKAGE_BEFORE_PN entry, confirmed by reading systemd_259.5.bb
# directly).
#
# util-linux-blkid: `blkid -o value -s TYPE` (both this recipe's own
# generator AND duduclaw-data-open.sh call it). Same "name the split
# package explicitly, don't trust an implicit pull" discipline
# recipes-duduclaw/duduclaw-firstboot.bb's own header already states for
# util-linux-findmnt/util-linux-lsblk — confirmed via util-linux_2.41.3.bb
# directly: `blkid` is in that recipe's own `sbinprogs_a` list, auto-split
# into `${PN}-blkid` by `util_linux_binpackages()` (the SAME mechanism
# that produces -findmnt/-lsblk), package name confirmed via that same
# recipe's own `RCONFLICTS:${PN}-blkid`/`RREPLACES:${PN}-blkid` lines
# (which would be meaningless if the package were not named exactly
# that).
RDEPENDS:${PN} += "bash cryptsetup systemd-crypt util-linux-blkid"
