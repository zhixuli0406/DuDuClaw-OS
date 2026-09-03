# DuDuClaw OS — read-only-root bind-mount infrastructure (VER-RO, P1 Wave,
# 2026-09-02).
#
# Authority: commercial/docs/DESIGN-os-trust-chain-2026-09.md, "依賴鏈補記"
# (2026-09-02 addendum to the T4 拍板紀錄): dm-verity forces root to be
# mounted `ro`, and this OS line's own P1/P2 debt list already named
# "journal 搬 /data" as an open item — the addendum reclassifies the WHOLE
# class of problem (every unit that currently writes somewhere under
# root's /var) as a HARD PREREQUISITE of dm-verity, not an independent
# nice-to-have, and folds it into a dedicated VER-RO sub-wave that must go
# green (this recipe's own RO1-RO6 harness, private_scratch/
# os-security-harness/wavero.py) BEFORE dm-verity itself is attempted.
#
# WHAT THIS PACKAGE IS: a config-only recipe (no compiled payload, same
# shape as duduclaw-journald.bb/duduclaw-network-config.bb) shipping:
#   (1) one tmpfiles.d file creating the /data/system/<component>
#       bind-mount SOURCE directories (files/duduclaw-data-binds-dirs.conf)
#   (2) four .mount units (log / iwd / docker / waydroid — see below for
#       the evidence trail on each), each binding /data/system/<component>
#       onto the /var/... path its consumers hardcode, plus one early
#       oneshot (duduclaw-data-binds-early.service) that provisions the
#       journal chain's source directory — tmpfiles-setup cannot do that
#       job for journald specifically (ordering cycle through
#       tmpfiles-setup's own After=systemd-journald.service; round-2
#       QEMU-evidenced, see that unit's header).
#
# WHY A SEPARATE RECIPE, NOT FOLDED INTO duduclaw-journald/-network-config/
# an existing one: none of journal/iwd/docker/waydroid's OWN recipes are
# ours to add a bind-mount concern to without either (a) reaching into a
# recipe this layer does not own at all (iwd/docker/waydroid all come from
# meta-oe/meta-virtualization, upstream layers this project does not fork),
# or (b) scattering four unrelated ownership concerns across four
# unrelated existing files. One recipe, one responsibility ("make root
# read-only-safe for the write points this wave found"), matches this
# layer's own "one explicit source of truth" convention — see e.g.
# duduclaw-network-config.bb's own RDEPENDS comment for the same
# philosophy applied elsewhere.
#
# EVIDENCE TRAIL (one-hand, not guessed) for each bind target's default
# path — full write-up lives in each individual files/*.mount unit's own
# header comment, summarized here:
#   journal:  recipes-duduclaw/duduclaw-journald/files/duduclaw.conf (WS-3/
#             B2, same layer) + openembedded-core/meta/recipes-core/
#             systemd/systemd_259.5.bb do_install (chowns a REAL, already-
#             shipped /var/log/journal directory at build time — read
#             directly from the pinned oe-core source this round).
#   iwd:      meta-openembedded/meta-oe/recipes-connectivity/iwd/
#             iwd_3.12.bb (StateDirectory=iwd in iwd's own upstream unit,
#             built via --with-systemd-unitdir) — StateDirectory= always
#             resolves under /var/lib relative to the real root, no
#             redirection knob exists short of RootDirectory=/RootImage=
#             sandboxing this project does not use here.
#   docker:   meta-virtualization/recipes-containers/docker/docker.inc
#             (ships upstream's own src/import/contrib/init/systemd/
#             docker.service verbatim, no --data-root override anywhere in
#             this layer — grepped, zero hits) — dockerd's own compiled-in
#             default data-root is /var/lib/docker.
#   waydroid: meta-duduclaw/recipes-waydroid/waydroid/waydroid.bb's own
#             pinned upstream source, tools/config/__init__.py's
#             `defaults["work"] = "/var/lib/waydroid"` — read directly from
#             the vendored source tree at this recipe's own pinned SRCREV.
#
# WHAT THIS WAVE DELIBERATELY DID NOT TOUCH (see the harness/report
# accompanying this ticket for the full plenary write-point survey):
#   - /var/lib/duduclaw-flatpak-verify (duduclaw-flatpak-kiosk-verify.bb's
#     own diagnostic, SYSTEMD_AUTO_ENABLE=disable, never started at boot):
#     fixed directly in that recipe (verify.conf's own Path=, plus its own
#     small tmpfiles addition) rather than a fifth .mount unit here — a
#     static config value pointed at /data needs no bind-mount machinery
#     at all, and the target path's embedded hyphens
#     (var-lib-duduclaw\x2dflatpak\x2dverify.mount) would have been an
#     ugly, easy-to-typo unit filename for zero benefit over editing the
#     one line that names the path in the first place.
#   - /var/lib/systemd (random-seed, timesync clock) — NOT bound to /data
#     this round; systemd-random-seed.service is instead MASKED at image
#     build time by duduclaw-ro-root.inc's rootfs hook (see that file for
#     the full reasoning — a bind here would hide the shipped journal
#     catalog and add another very-early ordering edge). UPDATE
#     (2026-09-03, VER-P): cross-reboot entropy-seed persistence — flagged
#     here as a P1 residual at the time this recipe was written — is now
#     handled OUTSIDE this recipe entirely, by
#     recipes-core/initrdscripts/initramfs-module-duduclaw-persist (load,
#     initrd-side) + recipes-duduclaw/duduclaw-persist-seed (refresh,
#     main-system-side). See duduclaw-ro-root.inc's own
#     duduclaw_ro_root_hook() comment for the full writeup; nothing in
#     THIS recipe changed.
#   - /etc/machine-id — NOT this recipe's concern at all: oe-core's own
#     rootfs-postcommands.bbclass::systemd_handle_machine_id() already
#     ships an EMPTY /etc/machine-id in every systemd image unconditionally
#     (verified by reading that bbclass directly — the exact three-option
#     tradeoff it quotes from systemd's own author is option (b), "have /
#     read-only and an empty file there"), which is precisely what
#     machine-id(5) requires for systemd's own built-in read-only handling
#     (a transient bind-mounted ID for that boot only) to activate without
#     erroring. UPDATE (2026-09-03, VER-P): cross-reboot machine-id
#     STABILITY — flagged here as a known, separate limitation at the time
#     this recipe was written — is now fixed by the SAME
#     initramfs-module-duduclaw-persist named above (it bind-mounts a
#     persisted machine-id file onto /etc/machine-id before switch_root,
#     from inside the initrd — see that module's own header for why an
#     initrd module, not a recipe-level rootfs hook, was the required
#     shape). This recipe's own scope is still unaffected.
#
# ROLLOUT GATING (per this wave's own instructions, NOT this recipe's own
# concern): this package is only ever pulled in by
# recipes-core/images/duduclaw-ro-root.inc, which
# duduclaw-image-appliance-test.bb requires and duduclaw-image-appliance.bb
# (the shipping target) deliberately does NOT this round — see that .inc
# file's own header.
SUMMARY = "DuDuClaw OS read-only-root bind-mount infrastructure (dm-verity prerequisite)"
DESCRIPTION = "${SUMMARY}. See this recipe's own header for the full \
write-point evidence trail and commercial/docs/DESIGN-os-trust-chain-\
2026-09.md '依賴鏈補記' for the design authority."
HOMEPAGE = "https://github.com/duduclaw/duduclaw"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = " \
    file://duduclaw-data-binds-dirs.conf \
    file://duduclaw-data-binds-early.service \
    file://var-log.mount \
    file://var-lib-iwd.mount \
    file://var-lib-docker.mount \
    file://var-lib-waydroid.mount \
"

S = "${UNPACKDIR}"

inherit systemd allarch

do_install() {
    install -d ${D}${nonarch_libdir}/tmpfiles.d
    install -m 0644 ${UNPACKDIR}/duduclaw-data-binds-dirs.conf \
        ${D}${nonarch_libdir}/tmpfiles.d/duduclaw-data-binds-dirs.conf

    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${UNPACKDIR}/duduclaw-data-binds-early.service ${D}${systemd_system_unitdir}/
    install -m 0644 ${UNPACKDIR}/var-log.mount ${D}${systemd_system_unitdir}/
    install -m 0644 ${UNPACKDIR}/var-lib-iwd.mount ${D}${systemd_system_unitdir}/
    install -m 0644 ${UNPACKDIR}/var-lib-docker.mount ${D}${systemd_system_unitdir}/
    install -m 0644 ${UNPACKDIR}/var-lib-waydroid.mount ${D}${systemd_system_unitdir}/
}

FILES:${PN} += " \
    ${nonarch_libdir}/tmpfiles.d/duduclaw-data-binds-dirs.conf \
    ${systemd_system_unitdir}/duduclaw-data-binds-early.service \
    ${systemd_system_unitdir}/var-log.mount \
    ${systemd_system_unitdir}/var-lib-iwd.mount \
    ${systemd_system_unitdir}/var-lib-docker.mount \
    ${systemd_system_unitdir}/var-lib-waydroid.mount \
"

# Each .mount unit's own [Install] RequiredBy= is what actually wires it to
# its consumer (systemd-journald.service / iwd.service / docker.service /
# waydroid-container.service) — none of those four targets have an
# [Install] section of their own that this package could instead hook via
# WantedBy=, and RequiredBy= is what makes a failed bind stop the consumer
# rather than let it silently fall through to writing on (or failing
# EROFS-silently against) the read-only root slot. All four are listed in
# SYSTEMD_SERVICE so systemd.bbclass processes their [Install] sections at
# rootfs postinst time (creating the `<target>.service.requires/<this>`
# symlinks) the same way it already does for every other unit in this
# layer with a non-trivial [Install] section (e.g.
# duduclaw-secaudit-scan.timer's WantedBy=timers.target).
SYSTEMD_SERVICE:${PN} = "duduclaw-data-binds-early.service var-log.mount var-lib-iwd.mount var-lib-docker.mount var-lib-waydroid.mount"
SYSTEMD_AUTO_ENABLE:${PN} = "enable"

# Doc-only RDEPENDS (this project's own "one explicit source of truth,
# not a dependency-resolution assumption" convention — see
# duduclaw-network-config.bb's identical-shaped comment): none of these
# four packages are DEPENDS/RDEPENDS in the sense of "this package needs
# them to function" (a .mount unit whose consumer is absent is simply
# inert — same "declared runner, harmless if the runner itself is missing"
# posture duduclaw-image-compat.inc's own header already establishes for
# this layer's optional-payload packages). Left unlisted rather than
# RDEPENDS-ing on iwd/docker/waydroid/systemd-journald (the last of which
# is not even a separate package to depend on) for exactly that reason:
# this package must stay installable on any image regardless of which of
# the four consumers that image happens to carry.
COMPATIBLE_MACHINE = ".*"
