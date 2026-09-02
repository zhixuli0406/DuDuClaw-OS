SUMMARY = "DuDuClaw OS A/B update chain config: sysupdate transfers + boot health gate"
DESCRIPTION = "${SUMMARY}. Y8-1 (2026-08-27) Yocto port of the Debian \
appliance line's A/B update mechanism \
(commercial/docs/DESIGN-ab-update-rollback-2026-08.md, §11 落地補記) -- \
ships the two systemd-sysupdate .transfer definitions (root partition + \
UKI), the duduclaw-health-check boot gate that stands between a finished \
boot and sd-boot's Automatic Boot Assessment, and a systemd drop-in \
pointing the gateway's DUDUCLAW_HOME at the /data partition this same \
ticket's wks (files/wic/duduclaw-ab-bootdisk.wks.in) adds. Config/script \
only -- the actual A/B mechanics (root/UKI writes, boot counting, bless) \
are all upstream systemd (systemd-sysupdate, systemd-bless-boot) or already \
in duduclaw-cli's own vendored duduclaw-gateway/duduclaw-sysd crates (see \
each .transfer/.service file's own header for exactly what was verified \
against the pinned systemd 259.5 source vs. carried over unmodified from \
the Debian line). Requires \
recipes-core/systemd/systemd_%.bbappend's PACKAGECONFIG additions to be \
built for systemd-sysupdate/systemd-bless-boot to actually exist on the \
target -- this recipe installs CONFIG for tools that must be present \
separately, it does not build them."
HOMEPAGE = "https://github.com/duduclaw/duduclaw"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = " \
    file://10-duduclaw-root.transfer \
    file://20-duduclaw-uki.transfer \
    file://15-duduclaw-root-verity.transfer \
    file://duduclaw-health-check.service \
    file://duduclaw-health-check.sh \
    file://10-ab-home.conf \
"

S = "${UNPACKDIR}"

inherit systemd

do_install() {
    install -d ${D}${sysconfdir}/sysupdate.d
    install -m 0644 ${UNPACKDIR}/10-duduclaw-root.transfer ${D}${sysconfdir}/sysupdate.d/
    install -m 0644 ${UNPACKDIR}/20-duduclaw-uki.transfer ${D}${sysconfdir}/sysupdate.d/
    # VER-V (2026-09-02): only when the flag that actually produces a
    # root-verity partition/payload is on -- see
    # 15-duduclaw-root-verity.transfer's own header for the full "off =
    # byte-identical /etc/sysupdate.d/ listing" reasoning. SRC_URI above
    # still always fetches the file (fetching costs nothing and keeps this
    # recipe's do_fetch/do_unpack task signatures independent of the
    # flag); only its INSTALLATION is conditional.
    if [ "${DUDUCLAW_VERITY_ENABLE}" = "1" ]; then
        install -m 0644 ${UNPACKDIR}/15-duduclaw-root-verity.transfer ${D}${sysconfdir}/sysupdate.d/
    fi

    install -d ${D}/usr/local/sbin
    install -m 0755 ${UNPACKDIR}/duduclaw-health-check.sh ${D}/usr/local/sbin/duduclaw-health-check.sh

    install -d ${D}${systemd_unitdir}/system
    install -m 0644 ${UNPACKDIR}/duduclaw-health-check.service ${D}${systemd_unitdir}/system/

    # Drop-in for a DIFFERENT recipe's unit (duduclaw-cli's
    # duduclaw-gateway.service) -- installing a .service.d/*.conf here is
    # the systemd-native way to layer one recipe's config onto another
    # recipe's unit without a bbappend on that other recipe, matching the
    # reasoning in 10-ab-home.conf's own header comment.
    install -d ${D}${systemd_unitdir}/system/duduclaw-gateway.service.d
    install -m 0644 ${UNPACKDIR}/10-ab-home.conf \
        ${D}${systemd_unitdir}/system/duduclaw-gateway.service.d/10-ab-home.conf
}

FILES:${PN} += " \
    ${sysconfdir}/sysupdate.d/10-duduclaw-root.transfer \
    ${sysconfdir}/sysupdate.d/20-duduclaw-uki.transfer \
    /usr/local/sbin/duduclaw-health-check.sh \
    ${systemd_unitdir}/system/duduclaw-health-check.service \
    ${systemd_unitdir}/system/duduclaw-gateway.service.d/10-ab-home.conf \
"

# VER-V (2026-09-02): FILES var, not do_install's own install path,
# because a file listed by do_install but omitted from every package's
# FILES would fail do_package's own "installed-but-not-packaged" QA check
# -- conditional packaging needs BOTH conditional install (above) AND
# conditional FILES membership, matching this project's convention
# elsewhere (e.g. classes/duduclaw-secure-boot.bbclass's own
# IMAGE_EFI_BOOT_FILES:append being conditional on the identical kind of
# "did the matching install step actually run" question).
FILES:${PN} += "${@ ' ${sysconfdir}/sysupdate.d/15-duduclaw-root-verity.transfer' if d.getVar('DUDUCLAW_VERITY_ENABLE') == '1' else ''}"

# bash: duduclaw-health-check.sh uses bash-only syntax ([[ ]], (( )),
# process substitution-free but still non-POSIX enough to need real bash,
# not /bin/sh -> busybox ash. curl: both probe_gateway() and probe_sysd()
# shell out to it directly, including --unix-socket and --http0.9, which
# not every curl build enables -- an explicit RDEPENDS documents that
# requirement rather than relying on it already being present for other
# reasons (both packages ARE already on this image today, confirmed via
# pkgdata during this ticket, but per this layer's own established
# "explicit over implicit dependency assumption" convention, that is not a
# reason to omit the RDEPENDS).
#
# duduclaw-cli: this package's own drop-in
# (duduclaw-gateway.service.d/10-ab-home.conf) targets duduclaw-cli's unit
# file by name; without duduclaw-cli installed, systemd would still accept
# the drop-in but it would have no unit to apply to.
RDEPENDS:${PN} += "bash curl duduclaw-cli"

# duduclaw-health-check.service is RequiredBy=boot-complete.target in its
# own [Install] section (not WantedBy=) -- see that file's header comment
# for why the distinction is load-bearing (a Wants= dependency would let
# boot-complete.target succeed even if this gate failed, defeating the
# entire point). SYSTEMD_AUTO_ENABLE enable() creates the matching
# boot-complete.target.requires/ symlink at image build time via
# `systemctl --root=... enable`, which honours [Install] RequiredBy= the
# same way it honours WantedBy= (systemctl(1) makes no distinction in how
# `enable` resolves either key, only in what kind of unit-file symlink it
# writes).
SYSTEMD_SERVICE:${PN} = "duduclaw-health-check.service"
SYSTEMD_AUTO_ENABLE:${PN} = "enable"

# x86_64 only -- see files/wic/duduclaw-ab-bootdisk.wks.in's own header for
# why (SD_GPT_ROOT_X86_64 baked into both .transfer files' comments and the
# wks's own --part-type, no arm64 equivalent maintained on this line).
COMPATIBLE_MACHINE = "duduclaw-genericx86-64|duduclaw-qemux86-64"
