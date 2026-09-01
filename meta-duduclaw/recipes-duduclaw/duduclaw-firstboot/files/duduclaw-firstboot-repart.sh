#!/usr/bin/env bash
# Re-evaluate the shipped /data partition definition
# (usr/lib/repart.d/30-data.conf, this recipe) against the real disk.
#
# Yocto port of the Debian appliance line's
# duduclaw-firstboot-repart.sh (appliance/mkosi.extra/usr/local/sbin/) --
# same mechanism, same reasoning, same idempotency stamp convention. On
# duduclaw-image-data.bb's own golden/QEMU image this is a no-op (every
# partition already matches its definition at whatever size wic built it
# at). On real hardware (duduclaw-genericx86-64), after the golden image
# has been written onto a disk larger than it was built for, the /data
# definition here (highest practical growth target -- no SizeMaxBytes=,
# Weight=1000) is what actually grows: systemd-repart resizes the GPT
# partition itself to consume whatever space is left after ESP+root, and
# the /data fstab entry's `x-systemd.growfs` option (see
# files/wic/duduclaw-data-bootdisk.wks.in) then resizes the ext4
# filesystem inside it at the next mount.
#
# CLI syntax verified against systemd-repart(8) the same way the Debian
# line's script was: `systemd-repart [OPTIONS...] [BLOCKDEVICE]`,
# `--definitions=<path>` overrides the default /usr/lib/repart.d search
# path. `systemd-repart` itself is present on this image because Y8-1
# (2026-08-27) already enabled PACKAGECONFIG[repart] on the shared
# recipes-core/systemd/systemd_%.bbappend -- that bbappend applies to
# every image built from this layer's systemd recipe, not only the A/B
# image it was written for, so no further systemd changes are needed here.
#
# NOTE on root's CopyFiles=/Format=: unlike the Debian line's read-only
# root-a, this line's root partition (files/wic/duduclaw-data-bootdisk.wks.in
# p2, `--source rootfs`) has no CopyFiles=/Format= directive in
# systemd-repart's own definition language at all -- it is not represented
# as a repart.d/*.conf file, only wic's own kickstart line built it. Only
# /data has a repart.d definition (30-data.conf), so there is nothing for
# systemd-repart to reinterpret as "recreate root" the way the Debian
# line's own comment worries about for its root-a/root-b pair -- this
# script's re-run against the live boot disk can only ever touch /data.
set -euo pipefail

STAMP=/var/lib/duduclaw/.repart-grown
# Best-effort, NOT set -e-fatal (VER-RO, 2026-09-02): on a read-only root
# (duduclaw-ro-root.inc images) /var/lib is unwritable and this unit runs
# Before=local-fs-pre.target -- i.e. before /data (the only writable
# persistent fs) is mounted, so there is nowhere durable to stamp at all.
# The QEMU round-3 probe caught the old unconditional mkdir failing the
# whole unit with "mkdir: can't create directory '/var/lib/duduclaw':
# Read-only file system" -- which then cascaded (failed unit -> health
# gate -> rescue-boot oneshot on the NEXT boot). Degrading the stamp to
# best-effort keeps the once-only optimization on rw-root images
# byte-identically, while ro-root images simply re-run this script every
# boot -- safe by design: the grow operation below is idempotent (nothing
# to grow => explicit no-op) and its own comment already declares failure
# non-fatal.
mkdir -p "$(dirname "$STAMP")" 2>/dev/null || true

ROOT_SOURCE="$(findmnt -n -o SOURCE / || true)"
if [[ -z "$ROOT_SOURCE" ]]; then
    echo "duduclaw-firstboot-repart: could not resolve the root filesystem source, skipping" >&2
    touch "$STAMP" 2>/dev/null || true
    exit 0
fi

ROOT_DISK="$(lsblk -no PKNAME "$ROOT_SOURCE" 2>/dev/null | head -n1)"
if [[ -z "$ROOT_DISK" ]]; then
    echo "duduclaw-firstboot-repart: could not resolve the parent disk of $ROOT_SOURCE, skipping" >&2
    touch "$STAMP" 2>/dev/null || true
    exit 0
fi

echo "duduclaw-firstboot-repart: re-applying /usr/lib/repart.d against /dev/${ROOT_DISK}"
# Best-effort: growing /data on real hardware is a nice-to-have, NOT a
# reason to fail the boot. --dry-run=no makes repart actually resize (its
# default is a no-op dry run). On the golden/QEMU exact-size image there is
# nothing to grow, so a failure/no-op here is expected and must not drop
# the machine to emergency.
if ! systemd-repart --dry-run=no --definitions=/usr/lib/repart.d "/dev/${ROOT_DISK}"; then
    echo "duduclaw-firstboot-repart: systemd-repart did not complete; /data left at its" \
         "current size (image is fully usable)." >&2
fi

# Stamp regardless so this doesn't re-run (and re-log the same outcome)
# every boot -- ConditionPathExists=! on the stamp gates the unit. On a
# read-only root the stamp cannot be written (see the STAMP comment above)
# and the unit deliberately re-runs each boot instead of failing.
touch "$STAMP" 2>/dev/null || true
