SUMMARY = "DuDuClaw OS Entry B (實體救援開機項) rescue mode target + account"
DESCRIPTION = "${SUMMARY}. A standalone systemd target reachable ONLY via \
the rescue UKI's own embedded kernel cmdline (systemd.unit=duduclaw-\
rescue.target — see meta-duduclaw/classes/duduclaw-rescue-boot.bbclass), \
never pulled in by the normal boot graph. Provides a restricted, non-root, \
autologin diagnostic shell account, an automatic boot-time tamper-evident \
audit marker, a read-only remount of root, and masks systemd's own \
built-in emergency.target/rescue.target so there is exactly ONE rescue \
corridor into this OS, not two overlapping and differently-audited ones. \
Authority: commercial/docs/DESIGN-maintenance-mode-2026-08.md §3."
HOMEPAGE = "https://github.com/duduclaw/duduclaw"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = " \
    file://duduclaw-rescue.target \
    file://duduclaw-rescue-shell@.service \
    file://duduclaw-rescue-root-lock.service \
    file://duduclaw-rescue-audit.service \
    file://duduclaw-rescue-audit.sh \
"

inherit systemd useradd allarch

do_install() {
	install -d ${D}${systemd_system_unitdir}
	install -m 0644 ${UNPACKDIR}/duduclaw-rescue.target ${D}${systemd_system_unitdir}/duduclaw-rescue.target
	install -m 0644 ${UNPACKDIR}/duduclaw-rescue-shell@.service ${D}${systemd_system_unitdir}/duduclaw-rescue-shell@.service
	install -m 0644 ${UNPACKDIR}/duduclaw-rescue-root-lock.service ${D}${systemd_system_unitdir}/duduclaw-rescue-root-lock.service
	install -m 0644 ${UNPACKDIR}/duduclaw-rescue-audit.service ${D}${systemd_system_unitdir}/duduclaw-rescue-audit.service

	install -d ${D}${sbindir}
	install -m 0755 ${UNPACKDIR}/duduclaw-rescue-audit.sh ${D}${sbindir}/duduclaw-rescue-audit.sh

	# DRAFT-no-linux-surface-2026-08.md item 5 realization for this line
	# (2026-08-26, Y7-2): Entry B is the FORMAL replacement for systemd's
	# own emergency.target/rescue.target, not a second door alongside
	# them — both the .target units AND their backing .service units are
	# masked. This is a real, deliberate decision, not a leftover: it
	# sidesteps entirely the open question DRAFT item 5 raised ("sulogin
	# 對一個鎖定但非空白密碼欄的反應") by removing sulogin from every
	# reachable boot-failure path — masked units cannot be started by
	# anything, including systemd's own internal
	# default.target-failed-so-try-rescue-then-emergency fallback chain
	# (empirically confirmed via a Red Hat KB describing the exact
	# observed log line "Default target masked. Trying to load rescue
	# target..." for the analogous default.target-masked case — WebFetch,
	# 2026-08-26, not assumed). Declared as a build-time `/dev/null`
	# symlink (the same mechanism `systemctl mask` creates at runtime) so
	# the mask survives a full rootfs rebuild/re-flash rather than
	# depending on a postinst step that would not even re-run after an
	# A/B slot switch onto a freshly-built rootfs.
	install -d ${D}${sysconfdir}/systemd/system
	ln -sf /dev/null ${D}${sysconfdir}/systemd/system/emergency.target
	ln -sf /dev/null ${D}${sysconfdir}/systemd/system/emergency.service
	ln -sf /dev/null ${D}${sysconfdir}/systemd/system/rescue.target
	ln -sf /dev/null ${D}${sysconfdir}/systemd/system/rescue.service
}

# Deliberately NOT using SYSTEMD_SERVICE/SYSTEMD_AUTO_ENABLE for any of the
# 4 unit files this recipe ships: none of them (duduclaw-rescue.target
# itself, duduclaw-rescue-shell@.service, duduclaw-rescue-root-lock.service,
# duduclaw-rescue-audit.service) have an [Install] section — they are ALL
# pulled in exclusively via duduclaw-rescue.target's own static `Wants=`
# line, which systemd resolves the moment that target is started (via the
# rescue UKI's `systemd.unit=` cmdline override) regardless of any
# unit's "enabled" state. `systemd.bbclass`'s SYSTEMD_SERVICE/AUTO_ENABLE
# machinery (`systemctl preset`) exists specifically for [Install]-bearing
# units reached through the normal enable/wants-symlink mechanism — listing
# these here would just print "unit has no installation config" warnings at
# rootfs postinst time for no benefit. `inherit systemd` below is kept
# anyway purely for the ${systemd_system_unitdir} variable used in
# do_install/FILES.

FILES:${PN} += " \
    ${systemd_system_unitdir}/duduclaw-rescue.target \
    ${systemd_system_unitdir}/duduclaw-rescue-shell@.service \
    ${systemd_system_unitdir}/duduclaw-rescue-root-lock.service \
    ${systemd_system_unitdir}/duduclaw-rescue-audit.service \
    ${sbindir}/duduclaw-rescue-audit.sh \
    ${sysconfdir}/systemd/system/emergency.target \
    ${sysconfdir}/systemd/system/emergency.service \
    ${sysconfdir}/systemd/system/rescue.target \
    ${sysconfdir}/systemd/system/rescue.service \
"

# duduclaw-rescue-audit.sh uses chattr (e2fsprogs) as a best-effort,
# already-`|| true`-guarded nicety — not a hard RDEPENDS, matching that
# script's own "silently skipped if unavailable" comment. journalctl/logger
# come from systemd/util-linux, already guaranteed present (this recipe's
# own unit files require systemd to interpret them at all).
RDEPENDS:${PN} += "bash"

# --- duduclaw-rescue account ---------------------------------------------
#
# Identity model decision (commercial/docs/DESIGN-maintenance-mode-2026-08.md
# §3.3, 2026-08-26, Y7-2 — executed ahead of formal pact, per the same
# "implement now, record the choice for ratification" precedent Y4-1 used
# for Entry A; see that design doc's own decision-record section for the
# matching write-up). Chosen: option (a) "獨立救援帳號" — a dedicated
# NON-root account — NOT option (b) "保留 root 鎖定 + 驗證 sulogin 行為".
# Reasoning:
#
#   - (b) would make Entry B's safety depend on an empirical, version-
#     fragile fact (exactly how THIS systemd/util-linux release's sulogin
#     reacts to a locked-but-non-empty /etc/shadow field) that could
#     silently change on a future version bump with no test ever catching
#     the regression. This ticket's own research into item 5 (see
#     do_install's mask comment above) found the actually-robust fix is to
#     remove sulogin from the path ENTIRELY, which makes (b)'s premise
#     moot even if it had been chosen.
#   - (a) has a fixed, auditable, testable security boundary (Unix account
#     permissions + a locked shadow field) that does not shift under a
#     systemd/util-linux version bump, and leaves the existing Q1
#     root-lock invariant (root's own shadow field) completely untouched —
#     Entry B adds a NEW, narrower door; it does not reopen the old one.
#   - Locked password (`--password '!'`), not empty: there is no remote OR
#     local path that ever PROMPTS this account for a password (the getty
#     template autologs it in — see duduclaw-rescue-shell@.service), so
#     the locked shadow field is pure defense-in-depth on top of that,
#     one step past the existing duduclaw/duduclaw-kiosk accounts' own
#     nologin-by-default philosophy — this account DOES get a real
#     interactive shell, by design (DESIGN doc §1: Full Maintenance is
#     "唯一能真正拿到 Linux shell...的入口"; the restriction here is
#     PRIVILEGE level, not "no shell at all").
#   - `systemd-journal` group only: read-only diagnostic journal access
#     without root. No `wheel`/`sudo`/`video`/`render`/`seat` — this
#     account has no GPU/session/privilege-escalation access, only text
#     diagnostics plus whatever plain-user filesystem permissions already
#     allow (which, combined with duduclaw-rescue-root-lock.service's
#     read-only `/`, is intentionally very little).
#   - Home dir under /var/lib (not /data, which does not exist yet on this
#     Yocto line — see duduclaw-rescue-audit.service's own comment — and
#     not /root, which is reserved for the separately-tracked bring-up-only
#     autologin-root escape hatch this ticket does not touch).
USERADD_PACKAGES = "${PN}"
GROUPADD_PARAM:${PN} = "-r duduclaw-rescue"
USERADD_PARAM:${PN} = "--system --gid duduclaw-rescue --home-dir /var/lib/duduclaw-rescue --create-home --shell /bin/bash --groups systemd-journal --password '!' duduclaw-rescue"

# `systemd-journal` (GROUPADD_PARAM:systemd = "-r systemd-journal" per
# systemd_259.5.bb) must already exist in the shared sysroot's synthetic
# passwd/group database by the time THIS recipe's own useradd_sysroot check
# runs — exact same class of ordering bug the duduclaw-kiosk recipe already
# hit and documented for `render`/`seat` (RDEPENDS alone only orders the
# FINAL rootfs-time postinst, not the earlier build-time sysroot check;
# USERADD_DEPENDS is useradd.bbclass's own documented mechanism for this).
USERADD_DEPENDS = "systemd"
