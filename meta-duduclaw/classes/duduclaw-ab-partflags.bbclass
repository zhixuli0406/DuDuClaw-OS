# DuDuClaw OS — GPT attribute bits for the A/B layout (Y8-1, 2026-08-27).
#
# WHY THIS EXISTS: wic's kickstart-style `part` line has no way to set raw
# GPT partition attribute bits at all — confirmed by reading wic's own
# argparse definitions (`ksparser.py`'s `part.add_argument(...)` list has
# `--active`/`--hidden`/`--part-type`/`--no-table` but nothing for NoAuto/
# ReadOnly/GrowFileSystem). mkosi.repart/ (the Debian appliance line's tool)
# has first-class `NoAuto=`/`ReadOnly=`/`GrowFileSystem=` directives; wic
# does not, and there is no drop-in equivalent to reach for.
#
# THE MECHANISM THAT MAKES THIS POSSIBLE ANYWAY: wic's own `--hidden` option
# (the only kickstart flag that DOES touch a GPT attribute bit) is
# implemented in `wic/plugins/imager/direct.py` as a plain shell-out:
#   sfdisk --sector-size <n> --part-attrs <disk> <num> RequiredPartition
# — i.e. wic already trusts `sfdisk --part-attrs` to do real GPT attribute
# writes, it just never exposed a kickstart syntax for anything past the
# three UEFI-generic bits (RequiredPartition/NoBlockIOProtocol/
# LegacyBIOSBootable). `sfdisk`'s own attribute parser
# (`libfdisk/src/gpt.c`, verified against the actual pinned util-linux
# 2.41.3 source under this builder's downloads/ cache — util-linux-native is
# already a real dependency of this same build) accepts `GUID:<bit>` for any
# bit in [48,64) — exactly the "type-specific" range the UEFI GPT spec
# reserves, which is where systemd's Discoverable Partitions Specification
# defines NoAuto=63, ReadOnly=60, GrowFileSystem=59. There is NO symbolic
# name for these three in util-linux itself (grepped the whole 2.41.3
# tarball for the literal strings "NoAuto"/"ReadOnly"/"GrowFileSystem" —
# zero hits; those names are a systemd-side convention over generic numbered
# bits, not something sfdisk understands by name), so the numeric form is
# the only option, not a fallback.
#
# So: run the exact same class of `sfdisk --part-attrs` call wic's own
# --hidden support already makes, as a plain `IMAGE_CMD:wic:append ()`
# shell snippet AFTER wic has produced the final `.wic` file — no patch to
# the wic-native recipe itself, no fork of upstream's Python. `$out` is
# still in scope here because bitbake concatenates `:append`'d shell
# function bodies into the SAME `{ ... }` block as the base
# `IMAGE_CMD:wic ()` definition in image_types_wic.bbclass (verified by
# reading that class — this is a standard, well-trodden oe-core pattern,
# not a guess), and that base definition's very last line is
# `mv ... "$out.wic"`, so `"$out.wic"` is exactly the file this hook must
# operate on.
#
# inherit this class from an A/B-capable image recipe only (not from every
# image recipe in the layer) — see recipes-core/images/duduclaw-image-ab.bb.
DEPENDS:append = " util-linux-native"

# Root-A's GPT PARTUUID, fixed at build time (Y9-2, 2026-08-27) — the
# missing piece that makes this image bootable at all. mkosi's own
# KernelCommandLine= (appliance/mkosi.conf) can write a bare
# `root=PARTUUID` token and have mkosi substitute the real value itself,
# because mkosi coordinates repart + ukify in one invocation and can read
# back the partition UUID it just assigned before baking the UKI. wic has
# no equivalent specifier — do_uki (which bakes UKI_CMDLINE) runs BEFORE
# do_image_wic (which is what actually calls wic and assigns PARTUUIDs via
# `sfdisk --part-uuid`, confirmed by reading
# openembedded-core/scripts/lib/wic/plugins/imager/direct.py's
# `assign_uuids`/`_get_part_uuid`-equivalent block at this layer's pinned
# oe-core commit), so there is no build-time moment at which a
# wic-generated random PARTUUID could be read back and baked into the UKI
# without a fragile do_image_wic:append step that patches an
# already-built PE binary's .cmdline section AND the copy wic embeds in
# the ESP's FAT32 filesystem. wic's kickstart `--uuid=<value>` option
# (confirmed in scripts/lib/wic/ksparser.py's `part` argument list and
# partition.py's `self.uuid = args.uuid`) sidesteps that entirely by
# fixing the value at wks-authoring time instead of leaving it to
# `uuid.uuid4()` — direct.py's imager only auto-generates a UUID
# `if not part.uuid`, so an explicit `--uuid=` always wins, and it reaches
# the actual GPT entry via `sfdisk --part-uuid <disk> <num> <uuid>`
# unconditionally once set (independent of `--use-uuid`, which only
# controls what device fstab lines reference). This constant is
# referenced from BOTH files/wic/duduclaw-ab-bootdisk.wks.in (p2's
# `--uuid=`) and recipes-core/images/duduclaw-image-ab.bb (its
# UKI_CMDLINE override's `root=PARTUUID=`) so the two can never drift
# independently — the same single-source-of-truth pattern this file
# already uses for DUDUCLAW_AB_SLOT_SIZE_MB.
#
# This is a real, build-tested value (not a template placeholder that
# still needs patching): root-A boots directly from it on THIS factory
# image. Slot B keeps its wic-assigned random PARTUUID — sysupdate/
# uki_patch.rs read that real value off the live disk at update time and
# rewrite the shipped UKI template's `root=PARTUUID=<this constant>` to
# point at it, on the device, exactly as designed
# (recipes-duduclaw/duduclaw-ab-update/files/20-duduclaw-uki.transfer's
# own comment). Deliberately NOT all-zeros
# (`00000000-0000-0000-0000-000000000000`) — the DESIGN doc's T3 test
# case reserves that exact string as the deliberately-unmountable
# fault-injection value; reusing it for a real, working slot A would make
# the two indistinguishable by grep in a serial log.
DUDUCLAW_AB_ROOTA_PARTUUID ?= "dedec1a0-0000-4000-8000-00000000000a"

# Partition numbers are 1-indexed positions in
# files/wic/duduclaw-ab-bootdisk.wks.in's declaration order (GPT partition
# numbers are stable and never reordered by wic/parted, matching the same
# "partition numbers remain stable" guarantee the Debian design doc cites
# for systemd-repart — verified true for wic too by inspection of
# direct.py's `part.num` assignment, which is a simple enumerate() over the
# parsed partition list). Overridable per-wks in case a future variant
# reorders partitions; NOT auto-derived from the wks file (that would need
# actually parsing it here, which is more machinery than this narrow fix
# needs).
DUDUCLAW_AB_ROOTB_PARTNUM ?= "3"
DUDUCLAW_AB_DATA_PARTNUM ?= "4"

# Slot / data sizing (megabytes, plain numbers — wic's sizetype("M") parser
# accepts a bare integer as MB). Defaults are calibrated for the SMALL
# duduclaw-qemux86-64 dev/test image (duduclaw-image.bb's own built rootfs
# measured ~1.2G on 2026-08-26), not the much heavier
# duduclaw-image-flatpak.bb / genericx86-64 real-hardware variant (whose
# single-partition wic was measured at 10G on the same date) — a real-
# hardware A/B image recipe MUST override both to comfortably exceed its
# own rootfs size with headroom for future package growth, or root-A itself
# will fail to fit at do_image_wic time. Root-A and root-B MUST stay equal
# (systemd-sysupdate dd's a slot-A-sized payload into slot B with no resize
# step — same invariant the Debian line's mkosi.repart pair enforces via
# identical SizeMinBytes=SizeMaxBytes=5G on both slots).
DUDUCLAW_AB_SLOT_SIZE_MB ?= "3072"
DUDUCLAW_AB_DATA_SIZE_MB ?= "1024"

# ESP size (Y9-2, 2026-08-27) — fixed, NOT left to wic's auto-sizing.
# files/wic/duduclaw-ab-bootdisk.wks.in's p1 is otherwise a byte-for-byte
# copy of oe-core's own efi-uki-bootdisk.wks.in, whose `part /boot --source
# bootimg_efi ... --overhead-factor=1` (no --fixed-size) sizes the ESP off
# whatever files happen to be staged into it AT BUILD TIME — one UKI +
# duduclaw-os-rescue.efi, ~62MiB combined, sized to ~91.3MiB with that 1x
# overhead. That is enough for a single-partition image that never
# receives a second UKI. It is NOT enough for THIS image: a real
# `device.update_apply` run during this ticket measured the ESP at
# 91.3M/75.6M-used/15.8M-free after a fresh factory boot, then failed
# systemd-sysupdate's UKI write partway (`Importing
# .../duduclaw-os_1.62.1.efi ... Imported 43%. Failed to write file:
# Input/output error`) — reproduced directly and unambiguously with `dd
# if=/dev/zero of=/boot/EFI/Linux/testfile bs=1M count=32`, which failed
# with the plain `No space left on device` after 16MiB (systemd-sysupdate's
# own "Input/output error" wording is `sd-import-raw`'s classification of
# the same underlying ENOSPC, not a different failure mode). The A/B
# design's whole point is that BOTH the running UKI and an incoming
# update's UKI must fit in the ESP AT THE SAME TIME (`InstancesMax=2`
# elsewhere in this design is exactly this — the old one is only removed
# after the new one is confirmed good), so this line's ESP needs headroom
# for 3 UKIs at once (rescue + slot-A/running + incoming update), not 2.
# 256 (MiB) gives ~8x this build's actual combined UKI weight (~93MiB for
# 3 copies at ~31MiB each) — deliberately generous rather than tightly
# calculated, matching DESIGN-ab-update-rollback-2026-08.md §6.2's own T9
# case and its Debian-line reference point (145.6MiB UKI x 512MiB ESP,
# ~3.5x headroom over 2 copies) rather than trying to shave this to the
# minimum that happens to pass today.
DUDUCLAW_AB_ESP_SIZE_MB ?= "256"

IMAGE_CMD:wic:append () {
	# GUID:63 = NoAuto, GUID:60 = ReadOnly — matches the Debian appliance
	# line's factory-state 21-root-b.conf (`NoAuto=yes` + `ReadOnly=yes`).
	# Comma-separated multi-bit form confirmed supported by reading
	# libfdisk/src/gpt.c's `gpt_entry_attrs_from_string()` parse loop (it
	# tokenizes on `,`/whitespace, not a single-bit-per-call API).
	sfdisk --sector-size 512 --part-attrs "$out.wic" ${DUDUCLAW_AB_ROOTB_PARTNUM} "GUID:63,GUID:60"
	# GUID:59 = GrowFileSystem — matches the Debian line's /data partition
	# (30-data.conf `GrowFileSystem=yes`). Setting the bit alone does not
	# make anything grow at boot without an on-target systemd-repart
	# `repart.d/` config actually consuming it (not wired up in this wave —
	# see systemd_%.bbappend's PACKAGECONFIG[repart] comment); this line
	# only ensures the bit itself is correct once that follow-up lands, so
	# the two pieces of work don't have to be sequenced against each other.
	sfdisk --sector-size 512 --part-attrs "$out.wic" ${DUDUCLAW_AB_DATA_PARTNUM} "GUID:59"
}

# NOT YET VERIFIED BY AN ACTUAL BUILD (2026-08-27): this hook has not been
# exercised end to end (no `bitbake duduclaw-image-ab` has been run in this
# session — see the Y8-1 handoff notes for why: disk on the shared builder
# was already past this project's 6G red line). Before trusting the
# resulting .wic's attribute bits, verify with the same forensic method the
# design doc itself used on the Debian line (`sgdisk -i <partnum>
# duduclaw-*.wic` or a raw GPT attribute-field read) rather than assuming
# this shell-out succeeds just because it type-checks.
