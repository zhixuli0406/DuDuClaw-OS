# Y16 (2026-08-28) hybrid GPT+ISO9660 boot fix.
#
# Root cause of Y13-2's "kernel enumerates all 5 GPT partitions fine, then
# every partition device node fails to open (`Can't open blockdev`) and root
# mount never succeeds" failure on hybrid GPT+ISO9660 media: oe-core's
# stock INITRAMFS_SCRIPTS list (see core-image-minimal-initramfs.bb) pulls in
# `initramfs-module-setup-live`, whose RDEPENDS drags in `udev-extraconf`
# (automount.rules -> /etc/udev/scripts/mount.sh). That script's own
# "skip if this is the root device" guard compares against `stat -c %d /`,
# which inside the initramfs is the tmpfs, never the real target root
# partition -- so the guard is a no-op there and mount.sh races to
# auto-mount every new partition (including our real root/data) under
# `/run/media/*` concurrently with initramfs-framework's own `rootfs`
# module trying to mount the SAME device by LABEL. Confirmed via a
# `systemd.log_level=debug` UKI rebuild: `/etc/udev/rules.d/automount.rules`
# fires `mount.sh` on ACTION=="add" for every block device unconditionally,
# and its `mount /dev/vdaN /run/media/...` attempts (with no explicit
# fstype, so the kernel's new mount-API iterates ext3/ext2/ext4/iso9660/
# btrfs against the SAME device -- hence the "Unknown parameter 'umask'"
# noise seen on EVERY boot, hybrid or not) collide with our own root mount.
# This latent race exists on the plain (non-hybrid) wic too -- the same
# "Unknown parameter 'umask'" + a couple of transient "Can't open blockdev"
# retries are visible in known-good plain-wic serial logs -- but there it
# clears within one or two ~1s retries. On the hybrid GPT+ISO9660 disk the
# extra housekeeping (El Torito / ISO9660 probing on the whole-disk device)
# shifts the race enough that it never resolves inside the initramfs
# `rootfs` module's default 5s retry budget, and boot fails.
#
# `initramfs-module-setup-live` itself is a hard no-op for every boot this
# project ships: its `setup_run()` (initramfs-framework/setup-live) only
# does anything when `bootparam_root` is empty or "/dev/ram0" (i.e. a
# live-CD boot with no root= given) -- every DuDuClaw UKI bakes an explicit
# `root=LABEL=root` into UKI_CMDLINE, so the module's entire body is
# unreachable for us. Dropping it removes the dead module AND its
# problematic transitive `udev-extraconf` dependency, with no functional
# loss. Verified fix: manually rebuilt the initramfs cpio with
# etc/udev/rules.d/automount.rules removed, re-packed a UKI, rebuilt the
# same hybrid GPT+ISO9660 test ISO -- boot went clean to
# `duduclaw-qemux86-64 login: root (automatic login)` with zero
# "Can't open blockdev" / "Unknown parameter 'umask'" noise. This
# INITRAMFS_SCRIPTS override reproduces that fix through the recipe
# instead of a hand-patched cpio.

INITRAMFS_SCRIPTS = "\
    initramfs-framework-base \
    initramfs-module-udev \
    initramfs-module-install \
    initramfs-module-install-efi \
"

# --- Trust chain P1 dm-verity (VER-V, 2026-09-02) -----------------------
# recipes-core/initrdscripts/initramfs-module-duduclaw-verity_1.0.bb only
# when DUDUCLAW_VERITY_ENABLE=1 -- off (unset), INITRAMFS_SCRIPTS stays
# the exact four-entry list above, byte-identical to before this wave
# (this bbappend's own initramfs cpio contents, and therefore this
# recipe's own sstate signature, are completely unaffected on a build that
# never sets the flag). classes/duduclaw-verity.bbclass's own header
# explains why nothing ELSE in this wave can be made conditional this
# cleanly (a wks partition line, a kernel .cfg) -- this one genuinely can,
# because INITRAMFS_SCRIPTS is a plain package list with no equivalent of
# a signed-artifact ordering constraint standing in the way.
#
# Positioned after 01-udev in the resulting /init.d/ (this module's own
# recipe installs it as 50-duduclaw_verity) and before whichever module
# actually mounts root -- see that module's own do_install comment for why
# the INSTALLED name differs from its SOURCE filename (a real, load-
# bearing correctness requirement, not a style choice).
INITRAMFS_SCRIPTS:append = "${@ ' initramfs-module-duduclaw-verity' if d.getVar('DUDUCLAW_VERITY_ENABLE') == '1' else ''}"
