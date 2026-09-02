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
# image. STALE AS OF T4 (2026-09-02), kept here only as history, NOT as
# current behavior: this paragraph used to say slot B keeps its
# wic-assigned random PARTUUID and that sysupdate/uki_patch.rs read that
# real value off the live disk at update time and rewrite the shipped UKI
# template's `root=PARTUUID=<this constant>` to point at it, on the
# device. That is no longer true — root-B is ALSO a build-time constant
# now (DUDUCLAW_AB_ROOTB_PARTUUID, immediately below) for Secure Boot
# compatibility reasons that constant's own comment explains in full; the
# on-device rewrite path survives only as uki_patch::rewrite_root_partuuid's
# legacy fallback for a release that ships no slot-B UKI variant. Deliberately
# NOT all-zeros
# (`00000000-0000-0000-0000-000000000000`) — the DESIGN doc's T3 test
# case reserves that exact string as the deliberately-unmountable
# fault-injection value; reusing it for a real, working slot A would make
# the two indistinguishable by grep in a serial log.
DUDUCLAW_AB_ROOTA_PARTUUID ?= "dedec1a0-0000-4000-8000-00000000000a"

# Root-B's GPT PARTUUID, ALSO fixed at build time (T4, 2026-09-02 修正案 --
# commercial/docs/DESIGN-os-trust-chain-2026-09.md's 2026-09-02 拍板紀錄
# entry). Root-B was deliberately left at wic's random default from Y9-2
# through the WS-3 wave -- the comment on DUDUCLAW_AB_ROOTA_PARTUUID above
# says as much ("Slot B keeps its wic-assigned random PARTUUID... uki_patch.rs
# read that real value off the live disk at update time and rewrite the
# shipped UKI template's root=PARTUUID=<this constant> to point at it, on the
# device"). That plan turned out to be incompatible with Secure Boot: SB's
# Authenticode signature covers the ENTIRE UKI PE image (stub + kernel +
# initrd + every embedded section, .cmdline included), so uki_patch.rs's
# device-side byte rewrite of .cmdline -- which never touched the signature
# itself -- corrupts it. An SB-enforcing firmware verifies the signature
# against the file AS SHIPPED and refuses to load a UKI whose bytes changed
# even by 36 ASCII characters. Discovered only once the SB pillar actually
# landed (DESIGN-os-security-line-2026-09.md's WS-3 wave), not at design
# time -- §3.2/§5.1 of the trust-chain design doc were written before this
# contradiction surfaced.
#
# THE FIX: stop rewriting root-B's PARTUUID on the device at all. Fix it to a
# build-time constant, exactly like root-A already is, so BOTH slots' UKIs
# can be fully assembled and Secure-Boot-signed on the BUILD HOST --
# recipes-core/images/duduclaw-image-ab.bb's do_uki_slotb task (see
# classes/duduclaw-ab-dualsign-uki.bbclass) bakes
# root=PARTUUID=${DUDUCLAW_AB_ROOTB_PARTUUID} into a SECOND signed UKI at
# build time, the same way the existing do_uki bakes
# root=PARTUUID=${DUDUCLAW_AB_ROOTA_PARTUUID} into the first one.
# crates/duduclaw-gateway/src/os_update.rs then SELECTS whichever pre-signed
# variant's baked PARTUUID already matches the live destination slot
# (uki_patch::verify_root_partuuid) instead of patching bytes --
# uki_patch::rewrite_root_partuuid is kept only as a fallback for a release
# that ships just one legacy UKI template (pre-T4, or a device without SB
# enforcement, where a corrupted-but-unverified signature still boots).
#
# Same "sacrifice global GPT uniqueness for build simplicity" trade-off
# DUDUCLAW_AB_ROOTA_PARTUUID's own comment already accepts, now applied
# symmetrically to both slots -- every device built from the same image
# shares the same two PARTUUIDs, which is fine precisely BECAUSE the boot
# selector is `root=PARTUUID=` baked into a per-slot UKI, never a
# device-unique identifier read back from live hardware (see that same
# comment's closing paragraph). Referenced from BOTH
# files/wic/duduclaw-ab-bootdisk.wks.in (p3's `--uuid=`) and
# recipes-core/images/duduclaw-image-ab.bb (its UKI_SLOTB_CMDLINE's
# `root=PARTUUID=`) so the two can never drift independently -- identical
# single-source-of-truth pattern to root-A's constant, one paragraph up.
# Deliberately NOT all-zeros for the same T3 fault-injection reason root-A's
# comment states, and deliberately ending in `...00b` (not `...00c`/`...00d`,
# reserved below for the dm-verity wave) so the two root slots' constants
# are visually adjacent and impossible to transpose by accident.
DUDUCLAW_AB_ROOTB_PARTUUID ?= "dedec1a0-0000-4000-8000-00000000000b"

# REALIZED (VER-V, 2026-09-02 -- DESIGN-os-trust-chain-2026-09.md §3.1/
# §3.2 P1 + 2026-09-02 拍板紀錄): the two hash-tree partitions' PARTUUIDs,
# same build-time-constant treatment as the two root slots above and for
# the identical underlying reason (device-path UUID tokens baked into a
# Secure-Boot-signed UKI cmdline cannot be a wic-random value). Suffix
# sequence continues deliberately from root-A/root-B's own "...00a"/
# "...00b" (a reader diffing all four constants side by side should see
# one family, not four unrelated UUIDs) -- exactly the values this file's
# own comment reserved in the T4 wave, now defined for real. Consumed by
# files/wic/duduclaw-ab-bootdisk.wks.in's conditional
# ${DUDUCLAW_AB_ROOTA_VERITY_WKS_LINE}/${DUDUCLAW_AB_ROOTB_VERITY_WKS_LINE}
# (see classes/duduclaw-verity.bbclass, which is what actually turns these
# two lines from blank into real `part` lines when DUDUCLAW_VERITY_ENABLE=1
# -- unconditional `?=` defaults here so a build that never inherits that
# class still has these two constants resolve to *something* stable if
# ever queried, matching this file's own root-A/root-B precedent of always
# defining the constant even when a given build doesn't dereference it).
#
# NOTE ON CMDLINE VOCABULARY: despite the reasoning trail above (written
# during the T4 wave, before dm-verity's own initrd shape was decided),
# the actual cmdline token root-a-verity's/root-b-verity's own PARTUUID
# gets baked into is NOT systemd.verity_root_hash= -- the 2026-09-02
# "依賴鏈補記" decision found this UKI's initrd is initramfs-framework (no
# systemd binary reaches it at all), so that systemd-generator-only token
# name has zero consumer here. It is also NOT a fully self-chosen name:
# classes/duduclaw-verity.bbclass's own header ("WHY THE UKI CMDLINE
# VOCABULARY") found `root=PARTUUID=` and `roothash=` already consumed by
# crates/duduclaw-gateway/src/uki_patch.rs + os_update.rs (and
# appliance/tools/make-payload.py on the Debian line) before this wave
# ever touched the wks, and reused both verbatim -- only ONE genuinely new
# token was needed for the hash-tree partition these two constants feed:
# `hashdev=PARTUUID=<uuid>` (see recipes-core/initrdscripts/
# initramfs-module-duduclaw-verity_1.0.bb's own header for the full
# writeup). The UUID VALUES and the "why build-time-constant" reasoning
# are unaffected either way -- only the cmdline key name differs from what
# was anticipated when this comment was first written.
DUDUCLAW_AB_ROOTA_VERITY_PARTUUID ?= "dedec1a0-0000-4000-8000-00000000000c"
DUDUCLAW_AB_ROOTB_VERITY_PARTUUID ?= "dedec1a0-0000-4000-8000-00000000000d"

# ESP (p1) and /data (p6) join the fixed-PARTUUID doctrine (VER-V round-8,
# 2026-09-02 — real QEMU evidence, not tidiness): with root-A switched to
# wic's rawcopy plugin, wic's own fstab-injection step is bypassed
# entirely (partition.py only rewrites /etc/fstab inside partitions built
# by the `rootfs` source plugin; a rawcopy'd prebuilt ext4 is never
# touched), so the booted verity image's fstab carried NO /boot and NO
# /data line at all — "systemd-journald.socket: Failed to queue service
# startup job: Unit data.mount not found", verbatim from the failed boot,
# and with it the whole /data bind chain (journal, gateway home, update
# staging) silently gone. The fix ships those two fstab lines STATICALLY
# inside the hashed rootfs (duduclaw-verity.bbclass's own
# ROOTFS_POSTPROCESS hook), which is only possible if the mount sources
# are build-time constants — same "trade global GPT uniqueness for a
# deterministic build" call root-A made in Y9-2 and root-B/verity made
# this wave. Fixed unconditionally (not verity-gated): nothing ever
# depended on p1/p6 randomness, and one PARTUUID scheme across every build
# mode beats two.
DUDUCLAW_AB_ESP_PARTUUID ?= "dedec1a0-0000-4000-8000-00000000000e"
DUDUCLAW_AB_DATA_PARTUUID ?= "dedec1a0-0000-4000-8000-00000000000f"

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
# PARTITION NUMBERS (VER-V, 2026-09-02): root-B/data's numbers are NOT
# fixed constants any more -- they now depend on whether the two verity
# hash-tree partitions actually exist in the finished wks, which in turn
# depends on DUDUCLAW_VERITY_ENABLE. Partition numbers on a wic-built disk
# are assigned purely by the ORDER of non-blank `part` lines the finished
# wks template contains (see files/wic/duduclaw-ab-bootdisk.wks.in's own
# header for the direct.py citation on this) -- so when
# ${DUDUCLAW_AB_ROOTA_VERITY_WKS_LINE}/${DUDUCLAW_AB_ROOTB_VERITY_WKS_LINE}
# below are blank (the DUDUCLAW_VERITY_ENABLE-unset default), the wks
# collapses back to EXACTLY today's 4-partition text and root-B/data are
# still partitions 3/4 -- these two `?=` defaults are that exact,
# unchanged value. classes/duduclaw-verity.bbclass's own anonymous python
# block overrides both (to 4/6) with a strong `=` ONLY when
# DUDUCLAW_VERITY_ENABLE=1, at which point root-a-verity becomes partition
# 3 (between root-A and root-B) and root-b-verity becomes partition 5
# (between root-B and data) -- see that class's header for the full
# six-partition contract (ESP/root-A/root-a-verity/root-B/root-b-verity/
# data).
DUDUCLAW_AB_ROOTB_PARTNUM ?= "3"
DUDUCLAW_AB_DATA_PARTNUM ?= "4"

# Root-b-verity's own partition number, ONLY meaningful when
# DUDUCLAW_VERITY_ENABLE=1 (there is no partition 5 at all otherwise) --
# consumed by classes/duduclaw-verity.bbclass's own IMAGE_CMD:wic:append()
# hook (NoAuto+ReadOnly bits, same mechanism this file's own hook below
# already applies to root-B). Harmless to always define: an sfdisk call
# against a partition number that does not exist on a given build never
# runs in the first place, because that hook's own body is itself gated
# on the same DUDUCLAW_VERITY_ENABLE check.
DUDUCLAW_AB_ROOTB_VERITY_PARTNUM ?= "5"

# root-A's own `--source` clause (VER-V, 2026-09-02) -- default is
# BYTE-IDENTICAL to what files/wic/duduclaw-ab-bootdisk.wks.in's p2 line
# has always hard-coded (`--source rootfs --exclude-path boot/`), now
# factored out into a variable so classes/duduclaw-verity.bbclass can
# override it (strong `=`) to `--source rawcopy --sourceparams="file=..."`
# when DUDUCLAW_VERITY_ENABLE=1 -- see that class's own header for why
# root-A itself, not just the two new verity partitions, has to switch
# source mechanisms for dm-verity to be correct at all (byte-identity
# between what gets hashed at build time and what wic actually writes into
# the partition is unreachable with two independent `mkfs.ext4`
# invocations -- rawcopy makes it a literal file copy instead, provably
# identical by construction).
DUDUCLAW_AB_ROOTA_WIC_SOURCE ?= "rootfs --exclude-path boot/"

# Cosmetic ext4 label for root-A (p2's own comment above has always called
# --label "purely cosmetic"). A VARIABLE, not a literal in the wks, because
# the verity path must set it EMPTY: wic's rawcopy plugin ends
# do_prepare_partition() with `if part.label:
# RawCopyPlugin.do_image_label(...)` (read from the pinned wic-native
# source, plugins/source/rawcopy.py) — a post-copy relabel that rewrites
# the ext4 superblock (primary + every backup, s_wtime included) INSIDE
# the partition image AFTER the bytes were hashed by `veritysetup format`.
# QEMU round-6 live evidence: "device-mapper: verity: data block 0 is
# corrupted" on every boot, with the deployed hash-source ext4 and the
# wic p2 content differing in exactly the nine superblock locations. A
# cosmetic label is not worth a broken root hash; duduclaw-verity.bbclass
# blanks this when DUDUCLAW_VERITY_ENABLE=1.
DUDUCLAW_AB_ROOTA_LABEL_OPT ?= "--label \"root-a\""

# The two verity hash-tree partitions' own `part ...` lines, each a WHOLE
# line of wks kickstart text as a single variable (VER-V, 2026-09-02).
# Blank by default -- files/wic/duduclaw-ab-bootdisk.wks.in references
# each of these ALONE on its own line, so an empty value collapses to a
# blank line (wic's kickstart parser tolerates blank lines; wic never
# assigns a partition number to a line that produced no `part` directive
# at all) and the wks is byte-identical to its pre-verity 4-partition
# shape. classes/duduclaw-verity.bbclass's own anonymous python block
# builds the real text (fully Python-side string formatting, not nested
# `${VAR}` expansion, deliberately -- see that class's header for why) and
# `d.setVar()`s these two variables ONLY when DUDUCLAW_VERITY_ENABLE=1.
DUDUCLAW_AB_ROOTA_VERITY_WKS_LINE ?= ""
DUDUCLAW_AB_ROOTB_VERITY_WKS_LINE ?= ""

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
