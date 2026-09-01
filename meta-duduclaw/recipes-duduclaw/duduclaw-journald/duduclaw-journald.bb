SUMMARY = "DuDuClaw OS journald hardening (persistent + bounded + sealed)"
DESCRIPTION = "${SUMMARY}. WS-3/B2 (2026-09-01, DESIGN-os-security-line-\
2026-09.md §2 支柱二 B2 / G17: this Yocto line shipped with zero journald \
configuration until this recipe). Config-only package: installs \
/etc/systemd/journald.conf.d/duduclaw.conf (Storage=persistent, \
SystemMaxUse=200M, Seal=yes — see files/duduclaw.conf's own header for \
the exact reasoning per directive and the one honest known-limitation: \
the journal is not yet bound onto /data, so it survives a reboot but not \
an A/B slot switch). The Forward Secure Sealing key itself is generated \
by duduclaw-firstboot-provision.sh (recipes-duduclaw/duduclaw-firstboot/, \
same wave), not by this recipe — this package only turns the feature on. \
Mirrors this layer's own established config-only recipe shape \
(duduclaw-network-config.bb / duduclaw-polkit-flatpak.bb / \
duduclaw-firewall.bb: SRC_URI = file://<config>, S = \${UNPACKDIR}, plain \
do_install, no compiled payload)."
HOMEPAGE = "https://github.com/duduclaw/duduclaw"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://duduclaw.conf"

S = "${UNPACKDIR}"

do_install() {
    install -d ${D}${sysconfdir}/systemd/journald.conf.d
    install -m 0644 ${UNPACKDIR}/duduclaw.conf ${D}${sysconfdir}/systemd/journald.conf.d/duduclaw.conf
}

FILES:${PN} += "${sysconfdir}/systemd/journald.conf.d/duduclaw.conf"

# Config-only, no compiled payload, nothing arch-specific -- reusable on
# either machine this layer targets, matching this layer's other
# config-only recipes' own COMPATIBLE_MACHINE reasoning. No RDEPENDS on
# systemd itself: systemd-journald is always present on this distro
# (INIT_MANAGER=systemd, duduclaw-os.conf), same "always there, not
# listed" convention duduclaw-firstboot.bb already applies to coreutils.
COMPATIBLE_MACHINE = ".*"
