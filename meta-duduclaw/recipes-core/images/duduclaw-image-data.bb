# DuDuClaw OS -- product image + /data (Y9-1, 2026-08-27).
#
# `require`s duduclaw-image.bb (NOT an edit to it, NOT a WKS_FILE override
# slipped into duduclaw-image.bb directly) for the same "each step keeps
# the previous QEMU-verified step's behavior completely intact" reason this
# layer's own image-recipe chain already uses throughout
# (duduclaw-image.bb `require`s duduclaw-image-minimal.bb,
# duduclaw-image-flatpak.bb `require`s this file as of this ticket,
# duduclaw-image-ab.bb `require`s duduclaw-image.bb directly and is
# UNAFFECTED by this file's own existence -- see below). Everything Y3-Y8
# already proved on duduclaw-image.bb (kiosk, fcitx5/IME, iwd/network,
# pipewire/audio, kernel-modules, rescue boot) stays reachable and
# buildable; this recipe only adds a /data partition + its first-boot
# provisioning on top.
#
# WHY A SEPARATE RECIPE FROM duduclaw-image-ab.bb, NOT A SHARED BASE: the
# two solve DIFFERENT, unrelated risk profiles at different maturity
# levels. duduclaw-image-ab.bb's own STATUS note says its four-partition
# GPT layout + systemd-sysupdate chain is "design + code complete, NOT YET
# verified by an actual build or QEMU boot" (Y8-1, same day this recipe was
# written) -- gating this ticket's much more basic, currently
# actively-blocking fix (Y8-2: fcitx5/libchewing user-dict persistence,
# gateway config, any future agent state -- all currently unable to survive
# a reboot at all) behind that unrelated mechanism clearing its own
# verification bar would tie two independent things together for no
# reason. If a future ticket wants ONE image with both A/B AND first-boot
# provisioning, the right move is teaching duduclaw-image-ab.bb to also
# `require` this file's provisioning recipe (duduclaw-firstboot) while
# keeping its own four-partition wks/bbclass -- NOT merging this file's wks
# into that one. Not attempted this round (out of scope, and would need
# duduclaw-image-ab.bb's own repart.d entries adjusted for a 4th vs 3rd
# partition position, which is exactly the kind of coupling this comment
# is arguing against).
#
# duduclaw-image-ab.bb itself is UNCHANGED and UNAFFECTED by this file:
# it `require`s duduclaw-image.bb directly (never this file), so it never
# inherits duduclaw-data-partflags below and never sees this file's
# WKS_FILE override -- confirmed by inspection, not merely assumed, since a
# double `inherit` of two different *-partflags classes into the same
# image (had duduclaw-image-ab.bb been rebased onto this file instead)
# would have made BOTH classes' IMAGE_CMD:wic:append() shell snippets run
# against the SAME `.wic` file with two different, incompatible
# partition-numbering assumptions for what partition 3 is (root-B there,
# /data here) -- a real conflict this recipe design avoids structurally
# rather than by convention.
SUMMARY = "DuDuClaw OS product image with /data partition + first-boot provisioning (Y9-1)"
DESCRIPTION = "${SUMMARY}. See commercial/docs/TODO-agent-first-os-2026-08.md \
Y9-1 entry and files/wic/duduclaw-data-bootdisk.wks.in / \
classes/duduclaw-data-partflags.bbclass / recipes-duduclaw/duduclaw-firstboot/ \
for the pieces this recipe wires together."
LICENSE = "MIT"

require recipes-core/images/duduclaw-image.bb

inherit duduclaw-data-partflags

WKS_FILE = "duduclaw-data-bootdisk.wks.in"

# Y14-A (2026-08-27): the single `IMAGE_INSTALL:append = " duduclaw-firstboot"`
# line this recipe carried since Y9-1 moved verbatim into a shared `.inc` so
# duduclaw-image-appliance.bb (the new A/B + full-payload convergence image,
# see commercial/docs/DESIGN-image-convergence-2026-08.md) can `require` the
# exact same fact without also `require`-ing this file's own
# `inherit duduclaw-data-partflags`/`WKS_FILE` (which assume a 3-partition
# layout incompatible with the A/B line's 4-partition one). Zero behavior
# change here: `bitbake -e` before/after this edit was diffed and
# IMAGE_INSTALL's final expansion is byte-identical.
require recipes-core/images/duduclaw-image-data.inc

COMPATIBLE_MACHINE = "duduclaw-genericx86-64|duduclaw-qemux86-64"
