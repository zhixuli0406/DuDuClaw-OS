SUMMARY = "Rootless Podman API service for the DuDuClaw gateway (uid 1000)"
DESCRIPTION = "duduclaw-podman.socket/.service run `podman system service` \
as the gateway account with a delegated cgroup subtree, a hardened sandbox \
and an nftables loopback guard; plus the store directory, the socket's \
runtime directory, a root-shell CONTAINER_HOST export and the kernel \
module preload list for the rootless container stack. Desktop edition only \
(installed by duduclaw-image-compat.inc). See files/duduclaw-podman.service \
for the threat model and each hardening line."
HOMEPAGE = "https://github.com/duduclaw/duduclaw"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = " \
    file://duduclaw-podman.socket \
    file://duduclaw-podman.service \
    file://podman-egress-guard \
    file://duduclaw-podman.conf \
    file://duduclaw-containers.conf \
    file://duduclaw-podman-profile.sh \
    file://duduclaw-containers-modules.conf \
    file://50-duduclaw-podman-guard.conf \
"

S = "${UNPACKDIR}"

inherit systemd allarch

do_install() {
    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${UNPACKDIR}/duduclaw-podman.socket ${D}${systemd_system_unitdir}/duduclaw-podman.socket
    install -m 0644 ${UNPACKDIR}/duduclaw-podman.service ${D}${systemd_system_unitdir}/duduclaw-podman.service

    install -d ${D}${libexecdir}/duduclaw
    install -m 0755 ${UNPACKDIR}/podman-egress-guard ${D}${libexecdir}/duduclaw/podman-egress-guard

    # Socket parent dir: generic tmpfiles.d (a /run path, needed every boot
    # before sockets.target).
    install -d ${D}${nonarch_libdir}/tmpfiles.d
    install -m 0644 ${UNPACKDIR}/duduclaw-podman.conf ${D}${nonarch_libdir}/tmpfiles.d/duduclaw-podman.conf
    # Store dirs on /data: private path, applied by the service itself
    # after /data is mounted (same convention as duduclaw-cli's
    # duduclaw-home.conf).
    install -d ${D}${datadir}/duduclaw/tmpfiles.d
    install -m 0644 ${UNPACKDIR}/duduclaw-containers.conf ${D}${datadir}/duduclaw/tmpfiles.d/duduclaw-containers.conf

    install -d ${D}${sysconfdir}/profile.d
    install -m 0644 ${UNPACKDIR}/duduclaw-podman-profile.sh ${D}${sysconfdir}/profile.d/duduclaw-podman.sh

    # Re-load the loopback guard whenever nftables.service (re)loads the
    # ruleset (see the drop-in's header).
    install -d ${D}${systemd_system_unitdir}/nftables.service.d
    install -m 0644 ${UNPACKDIR}/50-duduclaw-podman-guard.conf ${D}${systemd_system_unitdir}/nftables.service.d/50-duduclaw-podman-guard.conf

    install -d ${D}${nonarch_libdir}/modules-load.d
    install -m 0644 ${UNPACKDIR}/duduclaw-containers-modules.conf ${D}${nonarch_libdir}/modules-load.d/duduclaw-containers.conf
}

# Only the socket is enabled; the service is socket-activated and has no
# [Install] section (listing it here would ask systemctl to enable a unit
# with nothing to enable).
SYSTEMD_SERVICE:${PN} = "duduclaw-podman.socket"
SYSTEMD_AUTO_ENABLE:${PN} = "enable"

FILES:${PN} += " \
    ${systemd_system_unitdir}/duduclaw-podman.socket \
    ${systemd_system_unitdir}/duduclaw-podman.service \
    ${libexecdir}/duduclaw/podman-egress-guard \
    ${nonarch_libdir}/tmpfiles.d/duduclaw-podman.conf \
    ${datadir}/duduclaw/tmpfiles.d/duduclaw-containers.conf \
    ${sysconfdir}/profile.d/duduclaw-podman.sh \
    ${nonarch_libdir}/modules-load.d/duduclaw-containers.conf \
    ${systemd_system_unitdir}/nftables.service.d/50-duduclaw-podman-guard.conf \
"

# podman (engine, `docker` shim via PODMAN_FEATURES), passt (pasta),
# nftables (the egress guard), duduclaw-cli (the `duduclaw` account, its
# /run/duduclaw-gateway runtime dir and duduclaw-home-owner.service),
# duduclaw-firewall (nftables.conf with the duduclaw_podman_egress chain the
# guard fills; the service Requires nftables.service).
RDEPENDS:${PN} += "podman passt nftables duduclaw-cli duduclaw-firewall"

COMPATIBLE_MACHINE = ".*"
