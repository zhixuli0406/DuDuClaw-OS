SUMMARY = "DuDuClaw OS default-deny firewall (nftables ruleset)"
DESCRIPTION = "${SUMMARY}. WS-3/A4 (2026-09-01, DESIGN-os-security-line-\
2026-09.md §2 支柱一 A4 / G10: this Yocto line shipped with zero firewall \
until this recipe). Config-only package: installs /etc/nftables.conf \
(ported from the Debian appliance line's own appliance/mkosi.extra/etc/ \
nftables.conf, see files/nftables.conf's own header for the exact \
divergences checked and the one known-risk item flagged for QEMU \
verification) and pulls in nftables (meta-networking, already reachable \
in this layer's pinned set per kas/duduclaw-os.yml — confirmed via the \
OpenEmbedded layer index before writing this recipe, not assumed) plus \
the matching kernel nf_tables backend \
(recipes-kernel/linux/linux-yocto/duduclaw-nftables.cfg, wired in the \
same wave). Mirrors this layer's own established config-only recipe shape \
(duduclaw-network-config.bb / duduclaw-polkit-flatpak.bb: SRC_URI = \
file://<config>, S = \${UNPACKDIR}, plain do_install, RDEPENDS on the \
runtime package that actually reads the file)."
HOMEPAGE = "https://github.com/duduclaw/duduclaw"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://nftables.conf \
           file://nftables.service"

S = "${UNPACKDIR}"

inherit systemd

do_install() {
    install -d ${D}${sysconfdir}
    install -m 0644 ${UNPACKDIR}/nftables.conf ${D}${sysconfdir}/nftables.conf
    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${UNPACKDIR}/nftables.service ${D}${systemd_system_unitdir}/nftables.service
}

SYSTEMD_SERVICE:${PN} = "nftables.service"
SYSTEMD_AUTO_ENABLE:${PN} = "enable"

FILES:${PN} += "${sysconfdir}/nftables.conf ${systemd_system_unitdir}/nftables.service"

# RDEPENDS, not DEPENDS: config-only, no compile-time relationship to
# nftables at all -- same "documentation-as-code" convention
# duduclaw-network-config.bb's own RDEPENDS comment already establishes
# for this layer (one explicit source of truth: this package existing
# means nftables must too, not a bare dependency-resolution assumption).
# Service ownership correction (2026-09-01 SEC2 live-fire FAIL): the
# original plan put SYSTEMD_AUTO_ENABLE in a nftables_%.bbappend on the
# assumption upstream ships a unit defaulted to disable -- WRONG: the
# pinned meta-networking nftables_1.1.6.bb inherits no systemd class and
# installs NO service file at all (verified by reading it after
# `systemctl is-active nftables` came back `inactive` on the appliance),
# so that bbappend was configuring thin air and has been deleted. This
# recipe now owns the unit outright: a oneshot RemainAfterExit
# `nft -f /etc/nftables.conf` load, the same shape Debian's own
# nftables.service uses (already cited in files/nftables.conf's header).
RDEPENDS:${PN} += "nftables"

# Config-only, no compiled payload, nothing arch-specific -- reusable on
# either machine this layer targets, matching duduclaw-network-config.bb /
# duduclaw-polkit-flatpak.bb's own COMPATIBLE_MACHINE reasoning.
COMPATIBLE_MACHINE = ".*"
