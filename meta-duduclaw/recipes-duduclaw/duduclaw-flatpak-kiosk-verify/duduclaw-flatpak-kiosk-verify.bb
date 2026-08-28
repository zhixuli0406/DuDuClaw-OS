SUMMARY = "Flatpak Chromium + LibreOffice + Steam kiosk verification under a no-logind systemd service"
DESCRIPTION = "One-shot, NOT-auto-enabled diagnostic units + scripts that \
prove the Yocto-built Flatpak/bubblewrap/ostree/dbus/polkit chain can \
install and run real Flatpak apps under this OS's actual kiosk shape: a \
plain systemd SYSTEM service with no logind session. Two independent \
checks share the one verify identity/state directory this recipe owns: \
(1) duduclaw-flatpak-kiosk-verify.service (Y3-2, LibreOffice added Y14-B) \
-- headless Chromium --dump-dom AND headless LibreOffice --cat, predates \
duduclaw-comp/-shell having a Yocto recipe at all, so it never touches a \
real Wayland socket; (2) duduclaw-steam-kiosk-verify.service \
(Y5-2) -- a REAL Wayland client of the now-existing duduclaw-kiosk.service, \
launching Steam and checking it reaches its login screen (map judgment ⑥). \
Run manually with `systemctl start <unit>` and read \
/var/log/<unit-basename>/<unit-basename>.result afterwards; every check is \
tagged PASS/FAIL/SKIP on its own line, no silent partial success."
HOMEPAGE = "https://github.com/duduclaw/duduclaw"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

# Needs the actual flatpak/dbus/polkit runtime present to do anything
# useful, and the polkit rule so the install step it runs does not need an
# interactive polkit-agent prompt that this headless image has no way to
# answer.
#
# duduclaw-shell (Y5-2 addition): the Steam verify path is a REAL Wayland
# client of duduclaw-kiosk.service -- it needs that service's socket to
# exist at all, AND (see USERADD_PARAM below) this recipe's own verify user
# now joins the `duduclaw-kiosk` GROUP that duduclaw-shell's own useradd
# creates, which is a real rootfs-postinst ordering dependency, not just a
# runtime want (same reasoning duduclaw-shell.bb's own comment gives for why
# ITS RDEPENDS on seatd is load-bearing for ITS OWN --groups to succeed).
# duduclaw-steam-devices (Y5-2): the /dev/uinput udev rule this identity's
# `input` group membership below is meaningless without.
RDEPENDS:${PN} = "flatpak bubblewrap ostree dbus duduclaw-polkit-flatpak duduclaw-shell duduclaw-steam-devices"

# duduclaw-flatpak-offline-repo (Y6-3): RRECOMMENDS, not RDEPENDS -- unlike
# every dependency above, duduclaw-flatpak-kiosk-verify.sh's own "Offline
# preload repo" section is written to gracefully SKIP (not FAIL) when
# /opt/duduclaw-flatpak-offline-repo is absent and fall through to the
# live network flathub path, so this is genuinely optional at the package
# level too -- a hard RDEPENDS here would be dishonest about what actually
# happens at runtime if it's missing. duduclaw-image-flatpak.bb still
# lists it explicitly in IMAGE_INSTALL (belt-and-suspenders, same as every
# other package in that list), so on THIS image it is always present in
# practice.
RRECOMMENDS:${PN} = "duduclaw-flatpak-offline-repo"

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
# Y5-2 additions to the secondary group list -- `duduclaw-kiosk` and
# `input`, both formalizing manual fixes Y4-2 only ever did by hand inside a
# live QEMU session:
#   duduclaw-kiosk: lets this identity connect() to duduclaw-kiosk.service's
#                   Wayland socket at /run/duduclaw-kiosk/wayland-1 (that
#                   directory is now RuntimeDirectoryMode=0750 group
#                   duduclaw-kiosk -- see duduclaw-kiosk.service's own
#                   comment). Does NOT by itself solve the D-Bus ownership
#                   check that also blocked Y4-2 -- that is a separate
#                   per-identity XDG_RUNTIME_DIR problem, solved in
#                   duduclaw-steam-kiosk-verify.service below.
#   input:          lets this identity actually use the access
#                   duduclaw-steam-devices' udev rule grants to
#                   GROUP="input" devices (/dev/uinput and Valve USB/hidraw
#                   nodes) -- membership alone does nothing without that
#                   rule, and the rule does nothing without this membership;
#                   see USERADD_DEPENDS below for why both cross-recipe
#                   groups are safe to reference here at useradd time.
USERADD_PARAM:${PN} = "--system --no-create-home --gid duduclaw --groups duduclaw-kiosk,input --shell /sbin/nologin duduclaw-flatpak-verify"

# useradd.bbclass's own documented mechanism (see duduclaw-shell.bb's
# identical USERADD_DEPENDS comment for the full "why RDEPENDS alone is not
# enough" writeup -- this recipe hit the SAME class of would-be sysroot-time
# "group does not exist" failure and copies that fix verbatim): `duduclaw-
# kiosk` is created by duduclaw-shell's own useradd (implicit same-named
# group, no separate GROUPADD_PARAM there); `input` is one of systemd's own
# standard hardware-access groups (verified against systemd's upstream
# sysusers.d/basic.conf -- render/video/input/kvm/... are all the same
# class of group oe-core's systemd_259.5.bb package provides, same as
# duduclaw-shell.bb's own `render` dependency already established for this
# exact Yocto release).
USERADD_DEPENDS = "systemd duduclaw-shell"

SRC_URI = " \
    file://duduclaw-flatpak-kiosk-verify.sh \
    file://duduclaw-flatpak-kiosk-verify.service \
    file://verify.conf \
    file://duduclaw-steam-kiosk-verify.sh \
    file://duduclaw-steam-kiosk-verify.service \
    file://duduclaw-zenity-stub \
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

    # Y5-2: Steam-specific verify script + unit, same /usr/local/sbin +
    # ${systemd_unitdir}/system convention as the pair above.
    install -m 0755 ${UNPACKDIR}/duduclaw-steam-kiosk-verify.sh \
        ${D}/usr/local/sbin/duduclaw-steam-kiosk-verify.sh
    install -m 0644 ${UNPACKDIR}/duduclaw-steam-kiosk-verify.service \
        ${D}${systemd_unitdir}/system/

    # Y5-2 zenity bypass (see duduclaw-zenity-stub's own header comment for
    # the full "why not STEAM_ZENITY, why not XWayland" reasoning).
    #
    # /opt/duduclaw-steam-stubs, NOT /usr/local/libexec/... (real build/QEMU-
    # verified correction, not the original design): a live QEMU run of this
    # exact mechanism failed with `flatpak run`'s own stderr --
    #   F: Not sharing "/usr/local/libexec/duduclaw-steam-stubs" with
    #   sandbox: Path "/usr" is reserved by Flatpak
    # -- flatpak's `--filesystem=` unconditionally refuses ANY path rooted
    # under /usr (the sandbox's /usr is entirely runtime-controlled content,
    # not something a host bind-mount is allowed to overlay), independent of
    # what that path's own permissions look like. /opt is a plain FHS
    # location outside every directory Flatpak reserves for itself
    # (/usr, /app, /proc, ...). duduclaw-steam-kiosk-verify.sh hardcodes
    # this exact path as ZENITY_STUB_DIR, so do_install here must match it.
    install -d ${D}/opt/duduclaw-steam-stubs
    install -m 0755 ${UNPACKDIR}/duduclaw-zenity-stub \
        ${D}/opt/duduclaw-steam-stubs/zenity
}

FILES:${PN} += " \
    /usr/local/sbin/duduclaw-flatpak-kiosk-verify.sh \
    ${systemd_unitdir}/system/duduclaw-flatpak-kiosk-verify.service \
    ${sysconfdir}/flatpak/installations.d/verify.conf \
    /usr/local/sbin/duduclaw-steam-kiosk-verify.sh \
    ${systemd_unitdir}/system/duduclaw-steam-kiosk-verify.service \
    /opt/duduclaw-steam-stubs/zenity \
"

SYSTEMD_SERVICE:${PN} = "duduclaw-flatpak-kiosk-verify.service duduclaw-steam-kiosk-verify.service"
# Ships present but inert -- see each .service file's own [Unit] comment for
# why neither belongs on the boot-critical path (a multi-GB live download
# for the first; a real GUI app under kiosk supervision for the second).
SYSTEMD_AUTO_ENABLE:${PN} = "disable"

COMPATIBLE_MACHINE = ".*"
