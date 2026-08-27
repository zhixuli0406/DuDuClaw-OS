# DuDuClaw OS — A/B update-capable image (Y8-1, 2026-08-27).
#
# `require`s duduclaw-image.bb (NOT an edit to it, NOT a new WKS_FILE
# override slipped into duduclaw-image.bb directly) for the same reason
# duduclaw-image.bb itself `require`s duduclaw-image-minimal.bb and
# duduclaw-image-flatpak.bb `require`s duduclaw-image.bb: each step in this
# layer's own image-recipe chain keeps the previous, QEMU-verified step's
# behavior completely intact and only adds what is genuinely new on top —
# here, a four-partition GPT layout and its associated config/services,
# instead of the single-partition layout every other image recipe in this
# layer still uses and has real boot evidence for. If the A/B mechanism
# turns out to need further iteration, the existing
# duduclaw-image[-minimal|-flatpak].bb recipes and their QEMU evidence are
# never put at risk by that iteration.
SUMMARY = "DuDuClaw OS product image with A/B GPT layout + update chain (Y8-1)"
DESCRIPTION = "${SUMMARY}. See commercial/docs/DESIGN-ab-update-rollback-2026-08.md \
for the full design and files/wic/duduclaw-ab-bootdisk.wks.in / \
classes/duduclaw-ab-partflags.bbclass / \
recipes-duduclaw/duduclaw-ab-update/ for the pieces this recipe wires \
together. STATUS (2026-08-27): design + code complete, NOT YET verified by \
an actual `bitbake duduclaw-image-ab` build or QEMU boot in this session -- \
see the Y8-1 handoff notes for exactly what layer of verification was \
reached and why (disk pressure on the shared builder, see the ticket's own \
environment constraints)."
LICENSE = "MIT"

require recipes-core/images/duduclaw-image.bb

inherit duduclaw-ab-partflags

WKS_FILE = "duduclaw-ab-bootdisk.wks.in"

# Y9-2 (2026-08-27): duduclaw-image.bb -> duduclaw-image-minimal.bb's
# UKI_CMDLINE bakes `root=LABEL=root`, matching the single-partition
# efi-uki-bootdisk.wks.in's `part / ... --label root`. That label does not
# exist anywhere on THIS image's four-partition disk (root-A's ext4 label
# is now the purely cosmetic `root-a` — see
# files/wic/duduclaw-ab-bootdisk.wks.in's p2 comment), so an unmodified
# inherited UKI_CMDLINE boots into dracut's
# "root '/dev/disk/by-label/root' doesn't exist or does not contain a
# /dev." dead end every time — confirmed by an actual QEMU boot of a
# `duduclaw-image-ab` build during this ticket, not inferred from reading
# the cmdline alone. Override it to the PARTUUID scheme the whole A/B
# design requires (DESIGN-ab-update-rollback-2026-08.md §4.2: root mount
# is by PARTUUID baked into the UKI, not by GPT label/fstab, precisely so
# gpt-auto-generator's label-based tie-break can never pick the wrong
# slot). ${DUDUCLAW_AB_ROOTA_PARTUUID} is the SAME constant
# files/wic/duduclaw-ab-bootdisk.wks.in's p2 sets as root-A's actual GPT
# PARTUUID via `--uuid=` — see duduclaw-ab-partflags.bbclass's own comment
# on that variable for why a fixed constant, not a build-time readback of
# wic's usual random UUID, is what makes this work at all (do_uki runs
# before do_image_wic).
UKI_CMDLINE = "rootwait root=PARTUUID=${DUDUCLAW_AB_ROOTA_PARTUUID} console=${KERNEL_CONSOLE}"

# See duduclaw-ab-partflags.bbclass's own comment for what these control and
# why the inherited defaults (calibrated for duduclaw-image.bb's ~1.2G
# rootfs) are almost certainly too small for THIS specific image once it
# also carries duduclaw-image-flatpak.bb's payload -- this recipe currently
# `require`s the NON-flatpak duduclaw-image.bb, so the inherited 3072M/1024M
# defaults are the right starting point for it; a future
# duduclaw-image-ab-flatpak.bb (not created in this wave) would need larger
# values, sized against that image's own measured rootfs the same way this
# comment states the reasoning for THIS one, not copied blindly.

IMAGE_INSTALL:append = " duduclaw-ab-update"

# Y9-2 (2026-08-27): factory UKI naming + loader.conf default, so the very
# first boot's own UKI competes in the SAME sysupdate-managed namespace as
# every future update instead of permanently winning by static pin.
#
# Root cause this closes: uki.bbclass's own UKI_FILENAME default is the
# bare `uki.efi` (inherited unchanged from duduclaw-image.bb through
# duduclaw-rescue-boot.bbclass), while systemd-sysupdate only ever writes
# and recognises entries named `duduclaw-os_<version>[+tries[-left]].efi`
# (recipes-duduclaw/duduclaw-ab-update/files/20-duduclaw-uki.transfer's
# own `[Target] MatchPattern=` — three variants, none of them `uki.efi`).
# duduclaw-image/duduclaw-loader.conf's `default uki*` line (Entry B,
# Y7-2) was written before this A/B naming scheme existed and pins boot
# selection to `uki.efi` unconditionally — confirmed live during this
# ticket: a real `device.update_apply` correctly staged, labelled, and
# PARTUUID-patched a new counted entry with tries left, and the machine
# still rebooted straight back into the factory `uki.efi` every time
# (`bootctl status`: `Current Entry: uki.efi`) until a manual
# `bootctl set-oneshot` proved the underlying write was otherwise correct.
#
# UKI_FILENAME here gives THIS image's own factory UKI the same
# `duduclaw-os_<version>.efi` shape root-A's own GPT name already uses
# (p2's `--part-name` in files/wic/duduclaw-ab-bootdisk.wks.in) — the
# single source of truth is the same DUDUCLAW_PLATFORM_VERSION either
# way. duduclaw-ab-loader.conf (this recipe's own files/ dir, NOT
# duduclaw-image/'s) then only has to say `default duduclaw-os_*` for
# every entry — factory and every future update alike — to compete on
# boot-counting's own tries-left comparison, never on which happened to
# be built first. `duduclaw-os-rescue.efi` (this class's separate
# UKI_RESCUE_FILENAME, untouched by this override) still never matches
# either glob, so 判準①(rescue never becomes the ambient default) holds
# on both the pre- and post-A/B loader.conf.
FILESEXTRAPATHS:prepend := "${THISDIR}/duduclaw-image-ab:"
DUDUCLAW_LOADER_CONF_SRC = "duduclaw-ab-loader.conf"
SRC_URI += "file://duduclaw-ab-loader.conf"
UKI_FILENAME = "duduclaw-os_${DUDUCLAW_PLATFORM_VERSION}.efi"

COMPATIBLE_MACHINE = "duduclaw-genericx86-64|duduclaw-qemux86-64"
