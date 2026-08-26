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
