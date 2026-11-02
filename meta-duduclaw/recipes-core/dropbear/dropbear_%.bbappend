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

# Stopping a session unit ends the whole session (see the drop-in's header).
# duduclaw-sysd also kills everything under system-dropbear.slice when a
# maintenance window closes, so images without this drop-in are covered too.
FILESEXTRAPATHS:prepend := "${THISDIR}/files:"
SRC_URI += "file://duduclaw-session-killmode.conf"

# Maintenance SSH account (2026-10-16). Authority:
# commercial/docs/DESIGN-maintenance-ssh-account-2026-10.md (private
# platform tree) section 4.4. Three more drop-ins, all named 60-* so they
# sort after anything at 50-:
#   dropbear@.service.d/60-duduclaw-maint.conf
#       the per-connection server: only group duduclaw-maint may log in,
#       public key only, keys from the window's tmpfs directory, the fixed
#       menu as forced command, no forwarding, no IP sockets of its own,
#       stops with duduclaw-sysd (BindsTo=);
#   dropbear.socket.d/60-duduclaw-maint.conf
#       the listener stops with duduclaw-sysd too, connection caps;
#   dropbearkey.service.d/60-duduclaw-maint.conf
#       one ed25519 host key in /data/system/dropbear instead of an RSA key
#       in /etc/dropbear, which is read-only on the desktop edition.
# duduclaw-sysd checks the first two (ExecStart token by token, BindsTo=)
# before it opens a window, and the image build checks them too
# (duduclaw_check_maint_dropbear in recipes-core/images/
# duduclaw-maint-checks.inc). -G names a group that duduclaw-maint creates;
# on an image without that package dropbear exits at start, so nobody can
# log in, which is the intended direction. Every image built on
# duduclaw-image installs duduclaw-maint.
SRC_URI += " \
    file://60-duduclaw-maint-dropbear.conf \
    file://60-duduclaw-maint-socket.conf \
    file://60-duduclaw-maint-dropbearkey.conf \
"

do_install:append() {
	install -d ${D}${systemd_system_unitdir}/dropbear@.service.d
	install -m 0644 ${UNPACKDIR}/duduclaw-session-killmode.conf \
		${D}${systemd_system_unitdir}/dropbear@.service.d/duduclaw-session-killmode.conf
	install -m 0644 ${UNPACKDIR}/60-duduclaw-maint-dropbear.conf \
		${D}${systemd_system_unitdir}/dropbear@.service.d/60-duduclaw-maint.conf

	install -d ${D}${systemd_system_unitdir}/dropbear.socket.d
	install -m 0644 ${UNPACKDIR}/60-duduclaw-maint-socket.conf \
		${D}${systemd_system_unitdir}/dropbear.socket.d/60-duduclaw-maint.conf

	install -d ${D}${systemd_system_unitdir}/dropbearkey.service.d
	sed -e 's,@BASE_BINDIR@,${base_bindir},g' \
		-e 's,@SBINDIR@,${sbindir},g' \
		${UNPACKDIR}/60-duduclaw-maint-dropbearkey.conf \
		> ${D}${systemd_system_unitdir}/dropbearkey.service.d/60-duduclaw-maint.conf
	chmod 0644 ${D}${systemd_system_unitdir}/dropbearkey.service.d/60-duduclaw-maint.conf
	if grep -q '@[A-Z_]*@' ${D}${systemd_system_unitdir}/dropbearkey.service.d/60-duduclaw-maint.conf; then
		bbfatal "dropbearkey drop-in still has an unexpanded @...@ placeholder"
	fi
}

FILES:${PN} += " \
    ${systemd_system_unitdir}/dropbear@.service.d \
    ${systemd_system_unitdir}/dropbear.socket.d \
    ${systemd_system_unitdir}/dropbearkey.service.d \
"
