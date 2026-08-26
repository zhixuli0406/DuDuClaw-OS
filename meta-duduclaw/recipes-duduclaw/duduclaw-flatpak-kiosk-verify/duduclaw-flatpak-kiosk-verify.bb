SUMMARY = "Y3-2 first-light verification: Flatpak Chromium kiosk under a no-logind systemd service"
DESCRIPTION = "One-shot, NOT-auto-enabled diagnostic unit + script that \
proves the Yocto-built Flatpak/bubblewrap/ostree/dbus/polkit chain can \
install and run a real Flatpak Chromium, wrapped in dbus-run-session, \
under a plain systemd SYSTEM service with no logind session -- the exact \
shape this OS's kiosk services run as. This is deliberately separate from \
production kiosk wiring (duduclaw-kiosk.service does not exist on this \
Yocto line yet -- duduclaw-comp has an untested recipe and duduclaw-shell \
has none, per the Y2-3 status table). Run manually with `systemctl start \
duduclaw-flatpak-kiosk-verify.service` and read \
/var/log/duduclaw-flatpak-kiosk-verify/duduclaw-flatpak-kiosk-verify.result \
afterwards; every check is \
tagged PASS/FAIL/SKIP on its own line, no silent partial success."
HOMEPAGE = "https://github.com/duduclaw/duduclaw"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

# Needs the actual flatpak/dbus/polkit runtime present to do anything
# useful, and the polkit rule so the install step it runs does not need an
# interactive polkit-agent prompt that this headless image has no way to
# answer.
RDEPENDS:${PN} = "flatpak bubblewrap ostree dbus duduclaw-polkit-flatpak"

inherit systemd useradd

# --- Why this recipe creates a user, when duduclaw-cli/-sysd don't --------
# Running this verification AS ROOT would "pass" even if the
# duduclaw-polkit-flatpak rule were completely broken -- root's own flatpak
# CLI invocation may not even reach polkit the same way an unprivileged
# caller's does, so a root-run test proves nothing about the actual thing
# item 4 of the Y3-2 ticket asks for ("agent 裝 app 操作面"). The real
# target identity is the gateway/agent account, "duduclaw" -- but on THIS
# Yocto line that account does not exist yet (duduclaw-cli's
# duduclaw-gateway.service comment: "No User=duduclaw ... this Yocto image
# doesn't [create it]", deferred as its own follow-up, matching the Y2-3
# bring-up scope). Rather than reach into duduclaw-cli/-sysd to add that
# (a different recipe's ticket -- privilege separation, not Flatpak
# carriage) or test against a rule that can never fire on this image, this
# recipe creates the "duduclaw" GROUP now (idempotent -- oe-core's
# useradd.bbclass no-ops if the group already exists, the same
# multiple-recipes-share-one-group pattern used elsewhere in oe/meta-oe)
# plus a dedicated unprivileged runner user in that group, so
# duduclaw-polkit-flatpak's `subject.isInGroup("duduclaw")` check is
# exercised for real. When the real duduclaw user eventually lands here,
# it joins a group that already exists -- zero rework, and the group name
# was chosen to match that account from day one specifically for this
# reason.
USERADD_PACKAGES = "${PN}"
GROUPADD_PARAM:${PN} = "--system duduclaw"
USERADD_PARAM:${PN} = "--system --no-create-home --gid duduclaw --shell /sbin/nologin duduclaw-flatpak-verify"

SRC_URI = " \
    file://duduclaw-flatpak-kiosk-verify.sh \
    file://duduclaw-flatpak-kiosk-verify.service \
    file://verify.conf \
"

S = "${UNPACKDIR}"

do_install() {
    # /usr/local/sbin, NOT ${sbindir} (/usr/sbin) -- matches the existing
    # appliance/ (Debian) line's own convention for this exact class of
    # script (duduclaw-kiosk-launch.sh lives at
    # appliance/mkosi.extra/usr/local/sbin/), and matches what the
    # .service file's ExecStart= and this recipe's own DESCRIPTION already
    # say. A stray ${sbindir} here would silently ship the script at
    # /usr/sbin/... while the unit looks for it at /usr/local/sbin/... --
    # unit would fail to start with nothing but "status=203/EXEC" to go on.
    # ${UNPACKDIR}, NOT ${WORKDIR}, for all three files below -- same class
    # of bug caught and fixed in duduclaw-polkit-flatpak.bb (its own
    # comment has the full explanation): this OE-core release unpacks
    # file:// SRC_URI content into ${UNPACKDIR} (== ${S} above), not
    # directly into ${WORKDIR}. Caught by `bitbake duduclaw-image-flatpak`
    # itself failing do_install, not by re-reading the recipe.
    install -d ${D}/usr/local/sbin
    install -m 0755 ${UNPACKDIR}/duduclaw-flatpak-kiosk-verify.sh \
        ${D}/usr/local/sbin/duduclaw-flatpak-kiosk-verify.sh

    install -d ${D}${systemd_unitdir}/system
    install -m 0644 ${UNPACKDIR}/duduclaw-flatpak-kiosk-verify.service \
        ${D}${systemd_unitdir}/system/

    # Named flatpak installation config (Path=/var/lib/duduclaw-flatpak-
    # verify) -- see the .service/.sh files' own comments for why this is
    # NOT /data/flatpak on this Yocto line yet.
    install -d ${D}${sysconfdir}/flatpak/installations.d
    install -m 0644 ${UNPACKDIR}/verify.conf \
        ${D}${sysconfdir}/flatpak/installations.d/verify.conf
}

FILES:${PN} += " \
    /usr/local/sbin/duduclaw-flatpak-kiosk-verify.sh \
    ${systemd_unitdir}/system/duduclaw-flatpak-kiosk-verify.service \
    ${sysconfdir}/flatpak/installations.d/verify.conf \
"

SYSTEMD_SERVICE:${PN} = "duduclaw-flatpak-kiosk-verify.service"
# Ships present but inert -- see the .service file's own [Unit] comment for
# why a multi-GB live download must never sit on the boot-critical path.
SYSTEMD_AUTO_ENABLE:${PN} = "disable"

COMPATIBLE_MACHINE = ".*"
