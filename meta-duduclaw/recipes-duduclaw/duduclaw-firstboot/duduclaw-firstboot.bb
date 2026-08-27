SUMMARY = "DuDuClaw OS /data first-boot provisioning + H3g migrations (Y9-1)"
DESCRIPTION = "${SUMMARY}. Yocto port of the Debian appliance line's \
duduclaw-firstboot-provision.sh / duduclaw-firstboot-repart.sh / H3g \
/data forward-only settings migrator -- creates the durable device-state \
tree under /data (config.toml, device.key, machine-id, the \
duduclaw-kiosk home directory), grows /data to fill a real disk via \
systemd-repart, and replays baked-in /usr/share/duduclaw/migrations/*.sh \
scripts against it on every later boot. Only meaningful on an image that \
also uses files/wic/duduclaw-data-bootdisk.wks.in (see \
recipes-core/images/duduclaw-image-data.bb) -- installing this recipe \
without that wks would ship units that wait forever on a data.mount that \
never gets generated (Requires=data.mount would simply never resolve; not \
independently verified this round, tracked as an open point for anyone \
reusing this recipe outside that image chain). See \
recipes-duduclaw/duduclaw-firstboot/files/*.service for the boot-ordering \
argument and each script's own header for the line-by-line port rationale \
and the two deliberate divergences from the Debian line (root not yet \
read-only; no unprivileged 'duduclaw' service account on this line yet)."
HOMEPAGE = "https://github.com/duduclaw/duduclaw"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = " \
    file://duduclaw-firstboot-provision.sh \
    file://duduclaw-firstboot-repart.sh \
    file://duduclaw-firstboot-repart.service \
    file://duduclaw-firstboot-provision.service \
    file://duduclaw-data-migrate.service \
    file://10-data.conf \
    file://30-data.conf \
    file://1787540626.sh \
"

inherit systemd allarch

do_install() {
    install -d ${D}${sbindir}
    install -m 0755 ${UNPACKDIR}/duduclaw-firstboot-provision.sh ${D}${sbindir}/duduclaw-firstboot-provision.sh
    install -m 0755 ${UNPACKDIR}/duduclaw-firstboot-repart.sh ${D}${sbindir}/duduclaw-firstboot-repart.sh

    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${UNPACKDIR}/duduclaw-firstboot-repart.service ${D}${systemd_system_unitdir}/duduclaw-firstboot-repart.service
    install -m 0644 ${UNPACKDIR}/duduclaw-firstboot-provision.service ${D}${systemd_system_unitdir}/duduclaw-firstboot-provision.service
    install -m 0644 ${UNPACKDIR}/duduclaw-data-migrate.service ${D}${systemd_system_unitdir}/duduclaw-data-migrate.service

    # duduclaw-gateway.service.d/ drop-in -- see 10-data.conf's own header
    # for why this is a drop-in and not an edit to duduclaw-cli's unit, and
    # for why ${systemd_system_unitdir} (not ${sysconfdir}/systemd/system)
    # is the right directory -- matches the precedent Y8-1's own
    # 10-ab-home.conf already set for the identical class of override.
    install -d ${D}${systemd_system_unitdir}/duduclaw-gateway.service.d
    install -m 0644 ${UNPACKDIR}/10-data.conf ${D}${systemd_system_unitdir}/duduclaw-gateway.service.d/10-data.conf

    # systemd-repart definition -- read by duduclaw-firstboot-repart.sh at
    # first real boot, not by wic at build time (see that .conf file's own
    # header).
    install -d ${D}${nonarch_libdir}/repart.d
    install -m 0644 ${UNPACKDIR}/30-data.conf ${D}${nonarch_libdir}/repart.d/30-data.conf

    # H3g baseline migration script -- byte-for-byte identical to the
    # Debian appliance line's own copy (appliance/mkosi.extra/usr/share/
    # duduclaw/migrations/1787540626.sh), content is pure bash against
    # $DUDUCLAW_HOME with no Debian-specific assumption.
    install -d ${D}${datadir}/duduclaw/migrations
    install -m 0644 ${UNPACKDIR}/1787540626.sh ${D}${datadir}/duduclaw/migrations/1787540626.sh
}

# duduclaw-firstboot-provision.service/duduclaw-data-migrate.service/
# duduclaw-firstboot-repart.service all carry [Install] sections and are
# reached through the normal enable/wants-symlink mechanism (unlike
# duduclaw-rescue's units, which are only ever pulled in by an explicit
# rescue-target Wants=) -- SYSTEMD_SERVICE/AUTO_ENABLE is the right
# mechanism here, matching duduclaw-cli/duduclaw-shell/duduclaw-sysd's own
# convention.
SYSTEMD_SERVICE:${PN} = "duduclaw-firstboot-repart.service duduclaw-firstboot-provision.service duduclaw-data-migrate.service"
SYSTEMD_AUTO_ENABLE:${PN} = "enable"

FILES:${PN} += " \
    ${sbindir}/duduclaw-firstboot-provision.sh \
    ${sbindir}/duduclaw-firstboot-repart.sh \
    ${systemd_system_unitdir}/duduclaw-firstboot-repart.service \
    ${systemd_system_unitdir}/duduclaw-firstboot-provision.service \
    ${systemd_system_unitdir}/duduclaw-data-migrate.service \
    ${systemd_system_unitdir}/duduclaw-gateway.service.d/10-data.conf \
    ${nonarch_libdir}/repart.d/30-data.conf \
    ${datadir}/duduclaw/migrations/1787540626.sh \
"

# bash: every script here uses `set -euo pipefail` / `[[ ]]` (bash-isms,
# not POSIX sh) -- same requirement the Debian line's own scripts state.
#
# util-linux-findmnt / util-linux-lsblk, NOT bare `util-linux`
# (duduclaw-firstboot-repart.sh's only two external tool calls beyond
# systemd-repart itself): read util-linux_2.41.3.bb's own
# `util_linux_binpackages()` directly this round -- it auto-splits EVERY
# binary under bindir/sbindir into its OWN package (`${PN}-<binary>`,
# `extra_depends=''`) and only wires the split packages back to the main
# `util-linux` package via RRECOMMENDS, never RDEPENDS. A bare `util-linux`
# RDEPENDS would likely still pull findmnt/lsblk in on an image that honors
# recommends (the common case), but "likely still works because recommends
# usually aren't disabled" is exactly the kind of implicit dependency this
# layer's own recipes consistently avoid elsewhere (see e.g.
# duduclaw-image.bb's mesa-megadriver/libegl-mesa/vulkan-loader comments,
# each one a real boot failure caused by trusting an implicit pull that
# didn't happen) -- naming the two split packages this script actually
# calls is the same discipline applied here before it becomes a live bug
# instead of a comment.
#
# systemd: systemd-repart itself (Y8-1's systemd_%.bbappend already enables
# PACKAGECONFIG[repart] layer-wide, so this is a version constraint, not a
# new package pull).
#
# coreutils (id/head/base64/chmod/chown/mkdir/cp) is always present on any
# image this recipe targets, not listed explicitly per this layer's
# existing convention (see duduclaw-rescue.bb, which does not list
# coreutils either).
RDEPENDS:${PN} += "bash util-linux-findmnt util-linux-lsblk systemd"
