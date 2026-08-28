SUMMARY = "DuDuClaw OS live-environment-only tweaks (Y20-P1 desktop-in-live spike)"
DESCRIPTION = "${SUMMARY}. Two small, config-only overrides that must apply \
ONLY to duduclaw-image-live and must never leak onto the production \
duduclaw-image/duduclaw-image-ab chain -- kept as their own package (not an \
edit to duduclaw-shell's own duduclaw-kiosk.service, not a change to \
duduclaw-image.bb) so the production kiosk unit and image stay byte- \
identical to before this ticket touched anything: \
\
(1) duduclaw-kiosk.service.d/10-live-root.conf -- a systemd drop-in \
overriding User=/Group= from duduclaw-kiosk (an unprivileged service \
account on the production image, see duduclaw-shell's own kiosk.service \
comment) to root. The live installer environment's whole reason to exist \
(Y20-P2..P4, not yet built by this ticket) is to run disk-writing tools \
(dd/sgdisk/mkfs) from inside the graphical installer wizard the kiosk \
session hosts -- an unprivileged duduclaw-kiosk user has no path to those \
syscalls at all (no CAP_SYS_ADMIN, no raw block device access, no polkit \
rule granting either). Y20-P1 establishes and verifies this override in \
isolation (does root-uid kiosk still bring up comp+shell+fcitx5+pipewire/ \
wireplumber/seatd/dbus cleanly?) before any installer-wizard code exists to \
actually need the elevated uid -- a drop-in, not editing duduclaw-shell's \
own unit file, is the only way to do that without the production image \
inheriting the same privilege change. \
\
(2) /etc/duduclaw-live -- an empty, read-only marker file. Not consumed by \
anything yet (Y20-P1 scope is proving the desktop stack boots under this \
image, not wiring shell-side live-mode detection) -- laid down now so P2's \
shell-side 'am I running from a live/installer image, not the installed \
product?' check has a stable, already-shipped file to stat() rather than \
needing its own follow-up image-layer change."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://10-live-root.conf file://duduclaw-live"

# This pinned oe-core hard-fatals on S = "${WORKDIR}" (insane.bbclass's
# unconditional bb.fatal, not skippable via INSANE_SKIP) -- same fix already
# applied across every other config-only recipe in this layer (see
# duduclaw-os-installer.bb / duduclaw-network-config.bb's own identical
# comment). file:// sources unpack into UNPACKDIR now, not the WORKDIR root.
S = "${UNPACKDIR}"

do_install() {
    install -d ${D}${systemd_system_unitdir}/duduclaw-kiosk.service.d
    install -m 0644 ${UNPACKDIR}/10-live-root.conf \
        ${D}${systemd_system_unitdir}/duduclaw-kiosk.service.d/10-live-root.conf

    install -d ${D}${sysconfdir}
    # 0444: read-only marker, matches the read-only-by-nature squashfs root
    # this ends up on -- mode is set explicitly anyway rather than relying on
    # the medium's own read-only-ness, so `stat` on a tmpfs-overlaid live
    # root (P1's own overlay-vs-tmpfs verification target) still reports the
    # intended permission bits.
    install -m 0444 ${UNPACKDIR}/duduclaw-live ${D}${sysconfdir}/duduclaw-live
}

FILES:${PN} += " \
    ${systemd_system_unitdir}/duduclaw-kiosk.service.d/10-live-root.conf \
    ${sysconfdir}/duduclaw-live \
"

# Documentation-as-code, same convention duduclaw-network-config.bb's own
# RDEPENDS comment uses: this package is inert (a drop-in directory + a
# no-op marker file) without duduclaw-shell actually owning
# duduclaw-kiosk.service for the drop-in to attach to. Not a hard build-time
# DEPENDS -- systemd resolves .service.d/ drop-ins purely by unit *name*
# string match at daemon-reload time, so build order between the two
# packages does not matter, only that both end up installed on the same
# image (duduclaw-image-live.bb's own IMAGE_INSTALL:append is what actually
# guarantees that).
RDEPENDS:${PN} += "duduclaw-shell"

# Config-only, no compiled payload -- same INHIBIT pair
# duduclaw-os-installer.bb uses for the identical reason (pure data/config
# files, nothing for strip/sysroot-strip to do).
INHIBIT_PACKAGE_STRIP = "1"
INHIBIT_SYSROOT_STRIP = "1"

# duduclaw-image-live-only by convention (this package is never referenced
# by any other image recipe's IMAGE_INSTALL), not by COMPATIBLE_MACHINE --
# left unrestricted like duduclaw-network-config.bb's own "config-only,
# reusable" COMPATIBLE_MACHINE reasoning, since nothing here is actually
# machine-specific.
COMPATIBLE_MACHINE = ".*"
