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

# The installer itself (Y19) — a shell script + its runtime tools (sgdisk,
# zstd, parted, util-linux). This is what makes the live environment an
# *installer* environment rather than just a bootable throwaway: it writes the
# production A/B .wic (carried in the ISO as duduclaw-install.wic.zst, see
# populate_live:append below) onto the target disk. Run manually as
# `duduclaw-os-install` from the live root login — deliberately NOT an
# auto-running service, because writing to disk is a destructive operation
# that must stay behind an explicit human trigger (this project's own gate:
# overwriting non-self-created data is a human decision, never automatic).
IMAGE_INSTALL:append = " duduclaw-os-installer"

# ---------------------------------------------------------------------------
# Y20-P1 (2026-08-28): desktop stack spike -- "can the full graphical
# installer wizard (Y20-P2..P4, not built yet) even boot inside THIS live
# environment's squashfs+tmpfs-overlay+kiosk shape at all?" Four unknowns
# this ticket exists to answer: ISO/RAM footprint, whether mesa's llvmpipe
# software rasterizer survives (Y12 already fixed one llvmpipe crash class
# on the production line; this is the first time that code path runs from a
# read-only squashfs root instead of an ext4 one), and whether the kiosk
# session still comes up clean once its service account changes from the
# unprivileged duduclaw-kiosk to root (see duduclaw-live-tweaks.bb's own
# header for why root is required at all).
#
# COPIED, not `require`d, from duduclaw-image.bb's own five desktop-stack
# IMAGE_INSTALL:append lines (comp/shell/mesa, dbus/fcitx5, pipewire) --
# deliberate, not an oversight: extracting a shared
# duduclaw-image-desktop.inc now would put this throwaway spike recipe in
# the same edit blast radius as the production image line before P1 has even
# proven the desktop stack works here at all. Deduping into an .inc is
# explicitly deferred to P4 (see DESIGN-live-installer-iso-2026-08.md).
# kernel-modules is copied too (needed at runtime for the same audio/crypto
# module-splitting reasons duduclaw-image.bb's own comment documents, not
# specific to the installer).
#
# Wi-Fi is the one deliberate CUT, not copied: `iwd wireless-regdb-static
# duduclaw-network-config` from duduclaw-image.bb's Y7-3 block is left out
# entirely -- the graphical installer wizard this stack is being spiked for
# writes a local A/B image already carried inside the ISO (see
# populate_live:append below), it has no network-dependent step, and cutting
# it saves ISO/squashfs bytes on a recipe whose whole point is to stay small
# enough to fit on optical media.
IMAGE_INSTALL:append = " duduclaw-comp duduclaw-shell mesa-megadriver mesa-vulkan-drivers vulkan-loader libegl-mesa xkeyboard-config"
IMAGE_INSTALL:append = " dbus fcitx5 fcitx5-chewing"
IMAGE_INSTALL:append = " pipewire wireplumber"
IMAGE_INSTALL:append = " kernel-modules"

# duduclaw-live-tweaks (meta-duduclaw/recipes-duduclaw/duduclaw-live-tweaks/)
# -- the User=root kiosk override + the /etc/duduclaw-live marker file. Live-
# image-only by construction: this package is referenced from nowhere except
# this IMAGE_INSTALL:append, so duduclaw-image.bb / duduclaw-image-ab.bb stay
# byte-identical to before this ticket touched anything.
IMAGE_INSTALL:append = " duduclaw-live-tweaks"

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

# ---------------------------------------------------------------------------
# Y19: carry the production A/B image as install material INSIDE the ISO.
#
# image-live.bbclass's populate_live() installs rootfs.img into the ISO tree
# ($1 = ISODIR for build_iso, HDDDIR for build_hddimg) just before mkisofs /
# the FAT image is assembled. Appending to it drops one more file — the
# zstd-compressed production A/B .wic — into that same tree, so it ends up in
# the ISO9660 filesystem next to rootfs.img and the live installer finds it at
# /run/media/<label>/duduclaw-install.wic.zst (design doc §3.2/§3.3: the live
# ISO is a *vehicle* — it ships the finished, signed A/B artifact, it does not
# rebuild the system). Compress here (not in duduclaw-image-ab.bb) to keep the
# production release chain byte-for-byte untouched — the A/B image is consumed
# as an opaque input. mkisofs runs with -iso-level 3 automatically once the ISO
# exceeds 3.8GB (image-live.bbclass build_iso), so a multi-GB install payload
# is handled without extra flags.
#
# do_bootimg[depends]: force the A/B image's do_image_complete to finish first,
# so its .wic exists in DEPLOY_DIR_IMAGE before populate_live runs. bitbake's
# codeparser cannot infer this cross-image dependency (the .wic path is built
# by shell string expansion at task time), so it is declared explicitly.
# zstd-native: populate_live:append below runs `zstd` in the build-host
# context to compress the install material; the binary must be staged into
# do_bootimg's native sysroot (image-live.bbclass's own do_bootimg deps —
# mkisofs/syslinux/etc. — do not pull it in).
do_bootimg[depends] += "duduclaw-image-ab:do_image_complete zstd-native:do_populate_sysroot"

DUDUCLAW_INSTALL_AB_WIC ?= "${DEPLOY_DIR_IMAGE}/duduclaw-image-ab-${MACHINE}.rootfs.wic"

populate_live:append() {
    ab_wic="${DUDUCLAW_INSTALL_AB_WIC}"
    if [ ! -e "$ab_wic" ]; then
        # symlink name can vary with IMAGE_NAME_SUFFIX; fall back to a glob on
        # the stable prefix rather than guessing the timestamped basename.
        ab_wic="$(ls -1 ${DEPLOY_DIR_IMAGE}/duduclaw-image-ab-${MACHINE}*.wic 2>/dev/null | grep -v '\-[0-9]\{14\}\.wic$' | head -n1 || true)"
        [ -n "$ab_wic" ] && [ -e "$ab_wic" ] || ab_wic="$(ls -1t ${DEPLOY_DIR_IMAGE}/duduclaw-image-ab-${MACHINE}*.wic 2>/dev/null | head -n1 || true)"
    fi
    if [ -z "$ab_wic" ] || [ ! -s "$ab_wic" ]; then
        bbfatal "duduclaw-image-live: production A/B install material not found (looked for ${DUDUCLAW_INSTALL_AB_WIC} and duduclaw-image-ab-${MACHINE}*.wic in ${DEPLOY_DIR_IMAGE}). Build duduclaw-image-ab first."
    fi
    bbnote "duduclaw-image-live: embedding install material $ab_wic -> $1/duduclaw-install.wic.zst"
    # -T0 multi-thread, -3 fast level (the .wic is mostly already-compact ext4
    #  + a small ESP; a higher level buys little and costs minutes on every ISO
    #  rebuild). -f overwrite, stream to the ISO tree.
    zstd -T0 -3 -f "$ab_wic" -o "$1/duduclaw-install.wic.zst"
}
