# DuDuClaw OS — entropy-seed cross-reboot write-back recipe (VER-P, 信任鏈
# P1 殘項, 2026-09-03).
#
# WHY A SEPARATE RECIPE, NOT FOLDED INTO duduclaw-data-binds: matches this
# layer's own "one recipe, one responsibility" convention (see
# recipes-duduclaw/duduclaw-data-binds.bb's own header for the same
# reasoning applied to ITS scope) — duduclaw-data-binds is specifically
# "bind-mount infrastructure for the write points VER-RO's own survey
# found necessary"; this recipe's own single unit is a periodic-refresh
# oneshot, a different class of concern entirely (no bind mount, no
# tmpfiles source directory), even though both ship under the same
# rollout gate (see this recipe's own IMAGE_INSTALL:append site in
# recipes-core/images/duduclaw-ro-root.inc).
SUMMARY = "DuDuClaw OS entropy-seed cross-reboot persistence (trust chain P1 residual, VER-P)"
DESCRIPTION = "${SUMMARY}. Companion to \
recipes-core/initrdscripts/initramfs-module-duduclaw-persist, which LOADS \
/data/duduclaw/system/random-seed into /dev/urandom during early boot \
(before /data is even mounted by the main system) -- this recipe's own \
single oneshot unit is what keeps that seed file itself fresh: it writes \
a new sample from /dev/urandom back to /data both once boot reaches \
multi-user.target AND again on every shutdown (RemainAfterExit=yes + \
ExecStop -- see files/duduclaw-persist-seed.service's own header on why a \
oneshot's ExecStop runs at stop time), so cross-reboot entropy-seed \
persistence is a genuine full loop (load -> use -> refresh -> persist), \
not just a one-time carry-over. See recipes-core/images/duduclaw-ro-root.inc's \
own header for why systemd-random-seed.service itself stays masked rather \
than being unmasked for this purpose (its own hard-coded /var/lib path has \
no equivalent on a read-only root without yet another bind mount)."
HOMEPAGE = "https://github.com/duduclaw/duduclaw"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://duduclaw-persist-seed.service"

S = "${UNPACKDIR}"

inherit systemd allarch

do_install() {
    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${UNPACKDIR}/duduclaw-persist-seed.service \
        ${D}${systemd_system_unitdir}/duduclaw-persist-seed.service
}

FILES:${PN} += "${systemd_system_unitdir}/duduclaw-persist-seed.service"

SYSTEMD_SERVICE:${PN} = "duduclaw-persist-seed.service"
SYSTEMD_AUTO_ENABLE:${PN} = "enable"

# ROLLOUT GATING: pulled in only via recipes-core/images/duduclaw-ro-root.inc's
# own IMAGE_INSTALL:append, matching duduclaw-data-binds' own scope-note
# for the identical "only duduclaw-image-appliance-test.bb requires this
# .inc today" gating — not this recipe's own concern, see that .inc's own
# header.
COMPATIBLE_MACHINE = ".*"
