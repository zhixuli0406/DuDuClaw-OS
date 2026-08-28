# DuDuClaw OS — Y18 live installer environment (2026-08-28).
#
# NOT the production A/B image. This is a throwaway, unsigned "live CD"
# environment whose only job is: boot on temporary media (optical disc or
# USB) far enough to run an installer that writes the REAL, already-built,
# already-signed A/B image (duduclaw-image-ab.bb's .wic output, produced by
# scripts/release-os.sh) onto the target machine's internal SSD. It carries
# no gateway payload, no UKI/Secure-Boot signing chain, and is deliberately
# decoupled from the production image's build+release cadence — see
# commercial/docs/DESIGN-live-installer-iso-2026-08.md §3.3.
#
# Why oe-core's image-live.bbclass and not our own wic+UKI machinery:
# Y17 (2026-08-28, TODO-agent-first-os-2026-08.md) proved that a hybrid
# GPT+ISO9660 disk can never boot when handed to a real optical/`-cdrom`
# device — the Linux `sr` driver (drivers/scsi/sr.c:sr_probe())
# unconditionally sets GENHD_FL_NO_PART on every TYPE_ROM device, so GPT
# partition device nodes for /dev/sr0 never exist, no matter how root= is
# spelled. image-live.bbclass's live-CD architecture never touches a
# partition table on the boot medium in the first place — the initramfs
# mounts /dev/sr0 itself as a whole ISO9660 filesystem and finds a plain
# file (rootfs.img) inside it. See the design doc §1 for the full contrast
# table.
#
# EFI_PROVIDER = "systemd-boot" is already the distro-wide default
# (meta-duduclaw/conf/distro/duduclaw-os.conf) and openembedded-core's own
# systemd-boot.bbclass documents itself as the switch that makes
# image-live.bbclass emit systemd-boot loader.conf/entries instead of
# grub-efi — no override needed here, this recipe inherits that policy for
# free and stays on the same bootloader family as the production A/B image
# (just not the same UKI/signing mechanism — see below).

SUMMARY = "DuDuClaw OS live installer environment (Y18)"
DESCRIPTION = "${SUMMARY} — boots a squashfs-backed live root off optical \
media or USB via systemd-boot, as a vehicle for an installer that writes \
the production A/B image onto the target's internal SSD. Not signed, not \
part of the trusted A/B boot chain."
LICENSE = "MIT"

require recipes-core/images/core-image-minimal.bb

# Passwordless root console login — this is a disposable installer
# environment, not the trusted production system; matches the convenience
# Y16/Y17's QEMU verification runs relied on ("root (automatic login)") on
# the production image, made explicit here rather than inherited implicitly.
# NOTE: this pinned oe-core does not expose the meta-poky "debug-tweaks"
# alias (confirmed via `bitbake -n` dry-run error listing valid
# IMAGE_FEATURES) — spelled out as its constituent primitives instead.
IMAGE_FEATURES += "allow-empty-password allow-root-login empty-root-password serial-autologin-root"

inherit image-live

# Override, not append: this recipe must never accidentally pick up wic/uki
# tasks meant for the production image (duduclaw-image-minimal.bb /
# duduclaw-image-ab.bb). image-live.bbclass's own do_bootimg produces both
# an .iso (the Y18 cdrom target) and an .hddimg (dd-to-USB, free bonus from
# the same build — see design doc §6 open question on whether to ship it).
IMAGE_FSTYPES = "live"

# squashfs, not the image-live.bbclass default of ext4: read-only,
# compressed, and it's what init-live.sh's mount_and_boot() already expects
# to fall back to a tmpfs overlay for (a squashfs "rw,loop" mount attempt is
# silently read-only, the script's own `touch` probe fails, and it builds
# the overlay branch automatically — no script changes needed on our side).
LIVE_ROOTFS_TYPE = "squashfs"

# Deliberately NOT core-image-minimal-initramfs (the production A/B
# initramfs) — see duduclaw-image-live-initramfs.bb's own header comment
# for why the two must never be shared.
INITRD_IMAGE_LIVE = "duduclaw-image-live-initramfs"

# First cut: only the plain "boot straight into the live environment"
# label. The "install" label (initramfs-live-install-efi, target-disk
# partitioning + copy) is explicitly out of scope for this round — see
# design doc §4.2. Boot-only lets us isolate and verify the one thing Y16/
# Y17 could never get past: a real `-cdrom`/media=cdrom QEMU boot reaching
# a live login, with zero installer logic in the critical path yet.
LABELS_LIVE = "boot"

# image-live.bbclass's ROOT_LIVE default (root=/dev/ram0) matches
# init-live.sh's own expectations (it does not use the kernel root= value
# at all for live boot — it scans /run/media/* for rootfs.img regardless).
# Left at the class default deliberately; not overridden.

# First real QEMU cdrom attempt (2026-08-28) reached the systemd-boot menu
# on the serial console fine (OVMF mirrors its own UEFI ConOut to serial
# regardless of kernel cmdline) but went silent the instant the kernel took
# over. Root cause, found by extracting and reading the generated
# loader/entries/boot.conf directly off the built ISO (`options LABEL=boot `
# — no console= at all): `APPEND_LIVE` is NOT one of the vars
# live-vm-common.bbclass's set_live_vm_vars() aliases into their bare form.
# Reading that function's source: `vars = ['GRUB_CFG', 'SYSLINUX_CFG',
# 'ROOT', 'LABELS', 'INITRD']` — APPEND is simply absent from the list, so
# `APPEND_LIVE` is a dead variable name here, silently ignored (no error,
# no warning). This differs from duduclaw-image-minimal.bb's UKI path,
# which bakes `console=${KERNEL_CONSOLE}` directly into UKI_CMDLINE (a
# recipe-level var with no live/vm aliasing indirection at all). The fix
# for image-live.bbclass is to set the bare `APPEND` directly — this image
# never inherits image-vm.bbclass, so there is no competing consumer of the
# unsuffixed name that `_LIVE` would need to disambiguate against.
# KERNEL_CONSOLE is machine-level (duduclaw-qemux86-64.conf
# SERIAL_CONSOLES="115200;ttyS0") and already resolves to "ttyS0,115200".
# Also note: because set_live_vm_vars() reads variable names built by
# runtime string concatenation (`var + '_' + suffix`), bitbake's static
# codeparser cannot see "APPEND_LIVE" as a literal do_bootimg input — a
# change to any *_LIVE var this class aliases does NOT automatically bump
# do_bootimg's task signature. Verified live: after the APPEND_LIVE ->
# APPEND edit, a plain `bitbake duduclaw-image-live` reported do_bootimg
# "didn't need to rerun" and reused the stale sstate artifact; only
# `bitbake -c bootimg -f duduclaw-image-live` (explicit force) followed by
# a normal `bitbake duduclaw-image-live` (to propagate to do_image_complete
# and the ISO/hddimg outputs) actually regenerated it. Anyone iterating on
# LABELS_LIVE/ROOT_LIVE/INITRD_LIVE/APPEND/etc. on this recipe must force
# do_bootimg the same way — bitbake will not detect the change on its own.
APPEND = "console=${KERNEL_CONSOLE}"

# No `inherit uki`, no IMAGE_CLASSES:append = " uki", no WKS_FILE — this
# image never goes through wic or the signed-UKI chain. Its kernel+initrd
# are plain deployed artifacts that image-live.bbclass's do_bootimg copies
# directly into the ISO/EFI layout.
