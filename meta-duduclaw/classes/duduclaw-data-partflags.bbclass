# DuDuClaw OS -- GPT attribute bit for the root+/data layout (Y9-1, 2026-08-27).
#
# Sibling of duduclaw-ab-partflags.bbclass, deliberately NOT a shared/
# parameterized single class: the two wks files this pair covers have
# different partition counts and different partition ROLES at the same
# numeric positions (files/wic/duduclaw-ab-bootdisk.wks.in's partition 3 is
# root-B, requiring NoAuto+ReadOnly bits that make no sense here; THIS
# file's wks -- duduclaw-data-bootdisk.wks.in -- has no root-B at all, and
# its /data partition sits at position 3, not 4). Sharing one
# parameterized class between them would need a config flag per call site
# distinguishing "does this image have a root-B" anyway, which is no
# simpler than two small classes that can each be read start-to-finish
# without cross-referencing the other's partition-number contract. See
# duduclaw-ab-partflags.bbclass's own header for the full argument for WHY
# a GPT attribute bit needs a post-`do_image_wic` `sfdisk --part-attrs`
# shell-out at all (wic's kickstart `part` syntax has no equivalent of
# mkosi.repart's `GrowFileSystem=`) -- not re-derived here.
DEPENDS:append = " util-linux-native"

# Partition number is a 1-indexed position in
# files/wic/duduclaw-data-bootdisk.wks.in's declaration order (p1=ESP,
# p2=root, p3=data). Overridable per-image in case a future variant
# reorders partitions; not auto-derived from the wks file itself (parsing
# it here would be more machinery than this narrow fix needs -- same
# trade-off duduclaw-ab-partflags.bbclass already made).
DUDUCLAW_DATA_PARTNUM ?= "3"

# Build-time /data size (megabytes, plain integer -- wic's sizetype("M")
# parser accepts a bare number). This is the GOLDEN/DEV image size, sized
# for QEMU dev/test disks; real hardware grows /data past this via the
# on-target systemd-repart pass (recipes-duduclaw/duduclaw-firstboot/files/
# duduclaw-firstboot-repart.sh + usr/lib/repart.d/30-data.conf), not by
# raising this default. 1024 matches Y8-1's own DUDUCLAW_AB_DATA_SIZE_MB
# default for the same class of image (duduclaw-image.bb's built rootfs is
# ~1.2G per that ticket's own measurement -- /data does not need to be
# anywhere near that size on the dev image, it only needs to hold config/
# state/user-dict-sized content until a real disk lets it grow).
DUDUCLAW_DATA_SIZE_MB ?= "1024"

IMAGE_CMD:wic:append () {
	# GUID:59 = GrowFileSystem (systemd Discoverable Partitions Spec,
	# verified against the actual pinned systemd source the same way
	# duduclaw-ab-partflags.bbclass did -- src/systemd/sd-gpt.h /
	# docs/DISCOVERABLE_PARTITIONS.md numbering table). Setting the bit
	# alone does not grow anything without the on-target systemd-repart
	# pass actually consuming it -- see this class's own header and the
	# firstboot-repart script for the piece that does.
	sfdisk --sector-size 512 --part-attrs "$out.wic" ${DUDUCLAW_DATA_PARTNUM} "GUID:59"
}
