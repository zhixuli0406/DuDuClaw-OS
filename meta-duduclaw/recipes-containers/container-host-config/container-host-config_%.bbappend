# DuDuClaw OS: container host configuration for rootless Podman
# (2026-10-15, WP-O2).
#
# A bbappend, not a recipe of our own: container-host-config is what
# meta-virtualization's container-host.bbclass makes podman RDEPEND on, and
# it owns /etc/containers/storage.conf. A second recipe installing the same
# path would collide at rootfs time.
#
# storage.conf: replaces upstream's `driver = "vfs"` (full copy of every
# layer, unusable for real images) with overlay, and points the rootless
# store at /data/system/containers/$USER (see the file's header).
# containers.conf.d/50-duduclaw.conf: cgroupfs cgroup manager, pasta
# networking with --no-map-gw, nftables firewall driver, tmp/events paths
# that work under the podman unit's ProtectSystem=strict.
#
# Native/nativesdk variants (BBCLASSEXTEND upstream) get the same
# storage.conf, which is harmless; the drop-in is target-only.
FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI += "file://50-duduclaw.conf"

do_install:append:class-target() {
	install -d ${D}${sysconfdir}/containers/containers.conf.d
	install -m 0644 ${UNPACKDIR}/50-duduclaw.conf ${D}${sysconfdir}/containers/containers.conf.d/50-duduclaw.conf
}

FILES:${PN}:append:class-target = " ${sysconfdir}/containers/containers.conf.d/50-duduclaw.conf"
