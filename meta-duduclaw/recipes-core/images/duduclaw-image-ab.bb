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

# duduclaw-firstboot (Y11-2, 2026-08-27): this image's /data partition (p4,
# files/wic/duduclaw-ab-bootdisk.wks.in) has had a mountpoint since Y8-1 but,
# until this line, NOTHING that ever provisioned it — Y10-2's own structural
# finding ("三個額外挖到的結構性發現" ②) already named this gap: an empty,
# correctly-mounted /data is still useless without `config.toml`/
# `device.key`/the duduclaw-kiosk home tree that duduclaw-firstboot-
# provision.sh creates, and Y9-1 already ported+QEMU-verified that exact
# mechanism onto files/wic/duduclaw-data-bootdisk.wks.in's own /data
# partition (recipes-core/images/duduclaw-image-data.bb). This line makes
# THIS image pull in the same recipe rather than fork a second copy of it —
# duduclaw-firstboot has no partition-NUMBER assumption anywhere (checked
# this round, not assumed): its systemd units key off the generically-named
# `data.mount` unit (systemd derives that name from the /data MOUNTPOINT in
# fstab, not from which partition number backs it — 3 on the data wks, 4
# here), and its `usr/lib/repart.d/30-data.conf` matches by GPT
# `Type=linux-generic`+`Label=duduclaw-data`, both of which
# files/wic/duduclaw-ab-bootdisk.wks.in's own p4 line already sets
# identically to the data wks's p3 line. Only reachable now because THIS
# ticket's own wks edit above (`--use-uuid` on p4) is what makes /data
# actually mount at all on this image — installing duduclaw-firstboot
# without that fix would have shipped `Requires=data.mount` units waiting
# on a mount unit that generates but never activates, and (per Y9-1's own
# Requires= finding on the data line) turned the pre-existing "empty" gap
# into a hard `duduclaw-gateway.service` boot failure the moment
# recipes-duduclaw/duduclaw-firstboot/files/10-data.conf's
# `Requires=duduclaw-firstboot-provision.service` drop-in landed alongside
# this recipe's own pre-existing recipes-duduclaw/duduclaw-ab-update/files/
# 10-ab-home.conf (same directory, different filename, both setting the
# identical `Environment=DUDUCLAW_HOME=/data/duduclaw` — benign duplication,
# not a conflict, per Y10-2's own §6 disposition on the two drop-ins).
# RESIDUAL, NOT-YET-VERIFIED RISK (honestly flagged, not silently assumed
# fine): `duduclaw-firstboot-repart.sh` runs `systemd-repart --dry-run=no
# --definitions=/usr/lib/repart.d /dev/<root-disk>` against the WHOLE disk,
# not just /data — Y9-1's own QEMU evidence for this script is on the
# THREE-partition data wks (ESP+root+data, no reserved root-B slot); this
# image's FOUR-partition disk additionally carries root-B (p3, GUID:63/60
# NoAuto+ReadOnly, Type=root, `_empty` GPT name). Reasoned-through-but-
# UNTESTED-on-this-exact-layout: systemd-repart only creates/grows
# partitions that have a matching `[Partition]` definition under the
# `--definitions=` directory (only 30-data.conf lives there, matching
# Type=linux-generic — root-B's Type=root+NoAuto/ReadOnly bits are never
# touched by a directory that contains no Type=root definition at all), so
# root-B should be left untouched by this first-boot pass exactly as it is
# on every A/B-line boot today — but "should be, by inspection" is not the
# same bar this recipe's own header already holds itself to ("real QEMU
# boot, not inferred"), and this specific interaction (repart run alongside
# a live reserved root-B slot) has never actually been exercised end to end.
# See this ticket's own TODO-agent-first-os-2026-08.md Y11-2 entry for the
# exact verification status reached this round.
IMAGE_INSTALL:append = " duduclaw-firstboot"

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
#
# WS-3/A6 (2026-09-01, DESIGN-os-security-line-2026-09.md §2 支柱一 A6):
# `${DISTRO_VERSION}`, not the bare `${DUDUCLAW_PLATFORM_VERSION}` this
# line used from Y9-2 through the WS-3 wave. Same root cause and same fix
# as p2's `--part-name` in files/wic/duduclaw-ab-bootdisk.wks.in (see that
# file's own A6 comment for the full writeup) — this UKI's filename is
# what `20-duduclaw-uki.transfer`'s own `[Transfer] ProtectVersion=%A` /
# `[Source] MatchPattern=duduclaw-os_@v.efi` compares against, the exact
# same %A-vs-baked-in-string mismatch class as the root partition's GPT
# name, just on the ESP side instead of the root-partition side. Fixed the
# same way, for the same self-consistency reason: whatever DISTRO_VERSION
# is at build time is, by construction, what THAT build's own os-release
# IMAGE_VERSION= reports too (recipes-core/os-release/os-release.bbappend,
# same wave).
FILESEXTRAPATHS:prepend := "${THISDIR}/duduclaw-image-ab:"
DUDUCLAW_LOADER_CONF_SRC = "duduclaw-ab-loader.conf"
SRC_URI += "file://duduclaw-ab-loader.conf"
UKI_FILENAME = "duduclaw-os_${DISTRO_VERSION}.efi"

COMPATIBLE_MACHINE = "duduclaw-genericx86-64|duduclaw-qemux86-64"
