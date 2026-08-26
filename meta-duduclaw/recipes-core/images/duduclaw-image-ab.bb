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

COMPATIBLE_MACHINE = "duduclaw-genericx86-64|duduclaw-qemux86-64"
