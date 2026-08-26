SUMMARY = "DuDuClaw OS network config: wireless DHCP over iwd + systemd-networkd"
DESCRIPTION = "${SUMMARY}. Y7-3 (2026-08-26) port of the Debian appliance \
line's D4a-1 wireless networking decision (iwd owns 802.11 association, \
systemd-networkd owns the IP layer, RouteMetric keeps wired preferred over \
Wi-Fi when both are up) onto this Yocto image -- config-only, mirrors the \
duduclaw-polkit-flatpak recipe's shape (a single dropped-in file, no \
compiled payload). See files/25-wireless-dhcp.network for the full \
reasoning and the one deliberate numeric divergence from the Debian line \
(RouteMetric baseline is systemd-conf's wired.network=10 here, not the \
Debian line's own hand-written 20-wired-dhcp.network=100)."
HOMEPAGE = "https://github.com/duduclaw/duduclaw"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://25-wireless-dhcp.network"

S = "${UNPACKDIR}"

do_install() {
    install -d ${D}${sysconfdir}/systemd/network
    install -m 0644 ${UNPACKDIR}/25-wireless-dhcp.network \
        ${D}${sysconfdir}/systemd/network/25-wireless-dhcp.network
}

FILES:${PN} += "${sysconfdir}/systemd/network/25-wireless-dhcp.network"

# RDEPENDS, not DEPENDS: this is a plain config file with no compile-time
# relationship to iwd at all. The runtime dependency IS load-bearing though
# -- a .network file matching `Type=wlan` with no iwd/80-iwd.link present to
# ever produce a wlan-typed interface is inert but harmless; the real point
# of this RDEPENDS is documentation-as-code (one explicit source of truth
# for "this config file exists because iwd exists", same convention the
# Debian appliance line's mkosi.conf comments use for iproute2/seatd) plus
# guaranteeing this package is never installed standalone into an image that
# has no wireless stack at all.
#
# wireless-regdb-static, NOT bare wireless-regdb -- a real OE packaging trap
# caught by reading wireless-regdb_2026.05.30.bb directly, not by copying
# the Debian line's package name literally: oe-core's wireless-regdb recipe
# produces TWO packages declared RCONFLICTS of each other --
# `wireless-regdb-static` (the modern ${nonarch_base_libdir}/firmware/
# regulatory.db + .p7s the KERNEL loads directly via request_firmware(),
# needs kernel >= 4.15 -- this image's 6.18 kernel qualifies) and bare
# `wireless-regdb` (the legacy crda-DAEMON-oriented package --
# ${nonarch_libdir}/crda/regulatory.bin + pubkeys, for kernels too old to
# load the DB themselves). Debian's own `wireless-regdb` .deb ships the
# modern kernel-loadable file directly under one name with no such split,
# so a literal port of the Debian appliance line's package name here would
# have silently pulled the WRONG (legacy, non-functional-for-this-kernel)
# package. iwd's own RRECOMMENDS (meta-oe/recipes-connectivity/iwd/
# iwd_3.12.bb) already specifies `wireless-regdb-static` for exactly this
# reason, and Yocto RRECOMMENDS install by default (unlike apt's
# --no-install-recommends the Debian line's mkosi.conf relies on) -- this
# RDEPENDS is therefore redundant with what `iwd` alone would already pull
# in, kept explicit anyway per this project's established "one explicit
# source of truth, not a dependency-resolution assumption" convention (see
# appliance/mkosi.conf's own seatd/iproute2 comments).
RDEPENDS:${PN} += "iwd wireless-regdb-static"

# Config-only, no compiled payload -- reusable on any machine that carries
# iwd, matching duduclaw-polkit-flatpak's own COMPATIBLE_MACHINE reasoning.
COMPATIBLE_MACHINE = ".*"
