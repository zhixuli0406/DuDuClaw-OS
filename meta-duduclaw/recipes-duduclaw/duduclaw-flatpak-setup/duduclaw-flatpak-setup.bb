SUMMARY = "DuDuClaw OS: register the /data Flatpak installation and its remotes"
DESCRIPTION = "${SUMMARY}. Ships /etc/flatpak/installations.d/10-duduclaw-data.conf \
(the named 'data' installation at /data/flatpak the desktop shell and the \
polkit rule are scoped to) and a boot-time oneshot that creates the tree, \
registers the shipped offline repo as 'flathub-offline' and Flathub as \
'flathub'. 2026-09-05 QEMU walkthrough finding: without this the Yocto \
appliance had NO 'data' installation and NO remotes at all, so every app \
install from the Launcher failed silently and the 3.4 GB offline repo \
under /opt was dead weight. Ported from the frozen mkosi line."
HOMEPAGE = "https://github.com/duduclaw/duduclaw"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = " \
    file://10-duduclaw-data.conf \
    file://duduclaw-flatpak-setup.sh \
    file://duduclaw-flatpak-setup.service \
"

S = "${UNPACKDIR}"

inherit systemd allarch

RDEPENDS:${PN} = "flatpak bash"

do_install() {
    install -d ${D}${sysconfdir}/flatpak/installations.d
    install -m 0644 ${UNPACKDIR}/10-duduclaw-data.conf ${D}${sysconfdir}/flatpak/installations.d/10-duduclaw-data.conf
    install -d ${D}${sbindir}
    install -m 0755 ${UNPACKDIR}/duduclaw-flatpak-setup.sh ${D}${sbindir}/duduclaw-flatpak-setup.sh
    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${UNPACKDIR}/duduclaw-flatpak-setup.service ${D}${systemd_system_unitdir}/duduclaw-flatpak-setup.service
}

SYSTEMD_SERVICE:${PN} = "duduclaw-flatpak-setup.service"
SYSTEMD_AUTO_ENABLE = "enable"

FILES:${PN} += " \
    ${sysconfdir}/flatpak/installations.d/10-duduclaw-data.conf \
    ${sbindir}/duduclaw-flatpak-setup.sh \
    ${systemd_system_unitdir}/duduclaw-flatpak-setup.service \
"
