SUMMARY = "DuDuClaw OS maintenance SSH account (duduclaw-maint, uid/gid 4800)"
DESCRIPTION = "The account a support technician logs in as over SSH during \
a maintenance window the Admin opened in the dashboard. No password \
(shadow field '*'), no supplementary groups, a read-only empty home, and \
a login shell that is a fixed menu, not a general shell. The key that \
lets someone in exists only while the window is open, written by \
duduclaw-sysd to a tmpfs directory. The menu's two restarts (gateway, \
local model server) go through a root helper service, not polkit. \
Authority: commercial/docs/DESIGN-maintenance-ssh-account-2026-10.md \
(private platform tree) sections 3 and 5."
HOMEPAGE = "https://github.com/duduclaw/duduclaw"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"


SRC_URI = " \
    file://maint-ssh-close \
    file://60-duduclaw-maint-nftables.conf \
"

S = "${UNPACKDIR}"

inherit useradd allarch

# --- The account ------------------------------------------------------------
#
# Fixed uid/gid 4800, NOT a dynamic system id. Every dynamic system account
# on this image (duduclaw-kiosk, duduclaw-rescue, polkitd, ...) gets its id
# from shadow counting down from 999 in package install order; adding one
# more dynamic account can move the ones installed after it to a different
# id, and after an A/B update the files on /data would then belong to the
# wrong account. An explicit id is not counted, so nothing else moves.
# 4800 was picked to stay outside four ranges at once:
#   - the host's dynamic system range 101-999 (login.defs),
#   - the gateway's subordinate ids 100000-165535 (duduclaw-image-compat.inc),
#   - the Android ids Waydroid uses on the host (its LXC container has no
#     lxc.idmap, so an Android uid IS a host uid): 4000-4999 is unassigned
#     in AOSP's android_filesystem_config.h (not yet checked against the
#     Android image Waydroid actually downloads),
#   - systemd's reserved ranges (60001-60513, 61184-65519, 65534, 524288+).
# r2 of the design used 1001, which is Android's AID_RADIO.
# The image build re-checks all of this (duduclaw_check_maint_account in
# recipes-core/images/duduclaw-maint-checks.inc), plus that no other account
# changed its id against the previous release.
#
# `--system` keeps shadow from allocating subordinate ids for it; with an
# explicit --uid the system range does not apply.
#
# Password field '*', not '!': dropbear treats both the same (it checks the
# shadow field only on the password path, which -s turns off anyway), but
# OpenSSH without PAM treats '!' as "account locked" and would refuse the
# key login too, so '*' keeps working if the server is ever swapped.
#
# Home /usr/share/duduclaw-maint: an empty root:root 0555 directory on the
# read-only root, so the account owns no writable directory anywhere.
# dropbear reads authorized keys from /run/duduclaw-maint-ssh (its -D
# option), never from this home.
#
# Shell /usr/libexec/duduclaw/maint-shell: the fixed menu from the
# platform's duduclaw-maint-tools crate. It is NOT built by this recipe and
# NOT in the image yet: the platform snapshot that carries it comes with
# the last PR of this series (O-5), which also installs the readiness
# marker /usr/lib/duduclaw/maint-ssh.ready. Until then the account exists
# but cannot log in (no shell binary, and the vendored sysd has no verb that
# writes a key). The image check turns a missing shell into a build failure
# as soon as the readiness marker is present.
USERADD_PACKAGES = "${PN}"
DUDUCLAW_MAINT_ID = "4800"
DUDUCLAW_MAINT_HOME = "${datadir}/duduclaw-maint"
DUDUCLAW_MAINT_SHELL = "${libexecdir}/duduclaw/maint-shell"
GROUPADD_PARAM:${PN} = "--system --gid ${DUDUCLAW_MAINT_ID} duduclaw-maint"
USERADD_PARAM:${PN} = "--system --uid ${DUDUCLAW_MAINT_ID} --gid duduclaw-maint --home-dir ${DUDUCLAW_MAINT_HOME} --no-create-home --shell ${DUDUCLAW_MAINT_SHELL} --password '*' duduclaw-maint"

do_install() {
    # Read-only, empty home.
    install -d -m 0555 ${D}${DUDUCLAW_MAINT_HOME}

    # Root-only fallback close, run by the transient timer duduclaw-sysd
    # starts with every window (see the script's header). 0700: nothing but
    # root (PID 1's oneshot) runs it.
    install -d ${D}${libexecdir}/duduclaw
    install -m 0700 ${UNPACKDIR}/maint-ssh-close ${D}${libexecdir}/duduclaw/maint-ssh-close

    # Loopback egress rule for uid 4800, re-added whenever nftables.service
    # (re)loads the ruleset (see the drop-in's header). Inert on an image
    # without duduclaw-firewall: a drop-in for a unit that does not exist
    # is never loaded.
    install -d ${D}${systemd_system_unitdir}/nftables.service.d
    install -m 0644 ${UNPACKDIR}/60-duduclaw-maint-nftables.conf \
        ${D}${systemd_system_unitdir}/nftables.service.d/60-duduclaw-maint.conf
}

# dropbear refuses a login whose shell is not listed in /etc/shells. Written
# at rootfs time ($D set); it has no on-target branch, so it never becomes a
# deferred first-boot postinst (the desktop edition's duduclaw_check_filecaps
# would fail the build on one, and duduclaw_check_maint_account fails both
# editions if the line is missing). The grep keeps it idempotent, the same
# pattern oe-core's bash recipe uses.
pkg_postinst:${PN} () {
	grep -qxF '${DUDUCLAW_MAINT_SHELL}' $D${sysconfdir}/shells 2>/dev/null || \
		echo '${DUDUCLAW_MAINT_SHELL}' >> $D${sysconfdir}/shells
}

FILES:${PN} += " \
    ${DUDUCLAW_MAINT_HOME} \
    ${libexecdir}/duduclaw/maint-ssh-close \
    ${systemd_system_unitdir}/nftables.service.d/60-duduclaw-maint.conf \
"

# No polkit (owner decision 2026-10-16): the menu's two restarts go through
# the root helper service the platform ships with the menu, so this package
# adds no polkit daemon or rule to either edition, and no new dynamic
# system account with it. base-files owns /etc/shells; listing it orders
# its install before this package's postinst appends to the file.
RDEPENDS:${PN} += "base-files"
# maint-ssh-close is a bash script (arrays, [[ ]]); nft and systemctl come
# with the firewall and systemd, and the script reports a missing firewall
# set instead of failing on it. flock (the audit lock it shares with sysd)
# is busybox's applet (CONFIG_FLOCK=y in oe-core's defconfig);
# duduclaw_check_maint_dropbear fails the image if no flock is installed.
RDEPENDS:${PN} += "bash"

COMPATIBLE_MACHINE = ".*"
