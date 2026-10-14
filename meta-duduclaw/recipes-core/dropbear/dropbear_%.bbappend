# Keep dropbear off until maintenance mode turns it on (2026-10-15).
#
# ssh-server-dropbear is an IMAGE_FEATURE of duduclaw-image-minimal.bb and
# every image built on it. Upstream enables dropbear.socket by default
# (SYSTEMD_AUTO_ENABLE defaults to "enable"), so until this file every image
# listened on port 22 from first boot: reachable on the LAN in the base
# edition, which had no firewall, and blocked only by the firewall in the
# desktop edition. SSH is now off until an Admin opens a maintenance window
# in the dashboard; duduclaw-sysd then starts dropbear.socket and adds port
# 22 to the firewall's maintenance_tcp_ports set, and takes both back when
# the window closes (platform crates/duduclaw-sysd, from platform v1.73.3).
SYSTEMD_AUTO_ENABLE:${PN} = "disable"
