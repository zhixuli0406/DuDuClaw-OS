# WS-3/A4 (2026-09-01, DESIGN-os-security-line-2026-09.md §2 支柱一 A4).
#
# Upstream's own nftables_1.1.6.bb (meta-networking/recipes-filter/nftables/,
# read directly from git.openembedded.org before writing this file, not
# recalled from memory) sets:
#   SYSTEMD_SERVICE:${PN} = "${@bb.utils.contains('PACKAGECONFIG', 'systemd', 'nftables.service', '', d)}"
#   SYSTEMD_AUTO_ENABLE:${PN} = "${@bb.utils.contains('PACKAGECONFIG', 'systemd', 'disable', '', d)}"
# i.e. the unit ships but stays DISABLED by default even when the systemd
# PACKAGECONFIG is on (which it is here — this distro's DISTRO_FEATURES
# includes systemd) — a conservative default for a package with no config
# file of its own opinion about what to allow/deny.
#
# duduclaw-firewall (recipes-duduclaw/duduclaw-firewall/, same wave) is
# the ONLY thing in this layer that installs nftables at all (grepped
# before writing this file: nftables is not referenced by any other
# recipe or image's IMAGE_INSTALL) and it always ships a real
# /etc/nftables.conf alongside it — so overriding the auto-enable default
# here is safe in practice: there is no image in this layer where
# nftables the package is present without duduclaw-firewall's own config
# file also being present. Debian's own nftables package explicitly does
# NOT auto-enable either (appliance/postinst.d/20-users-and-units.sh's own
# comment: "Debian's nftables package does not enable nftables.service by
# default... to avoid a package install silently locking out the admin")
# and instead relies on a separate, explicit enable step in its own
# postinst-equivalent (that same script's `systemctl enable
# nftables.service` line) — this .bbappend is the Yocto-side equivalent of
# that same explicit step, not a change to upstream's own conservative
# packaging default (which stays correct in isolation; this override only
# fires the moment this layer's own duduclaw-firewall recipe is what pulls
# nftables in).
SYSTEMD_AUTO_ENABLE:${PN} = "enable"
