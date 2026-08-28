#!/usr/bin/env bash
# Y16 (2026-08-28) hybrid GPT+ISO9660 boot media builder.
#
# Takes a wic produced by a duduclaw-image-* recipe (ESP + root [+ data]
# GPT layout, UKI + systemd-boot boot chain) and repacks it as a hybrid
# GPT+ISO9660 image: same GPT partitions (byte-identical filesystem
# content, extracted via dd) wrapped in an ISO9660 shell via
# `xorriso -append_partition ... -appended_part_as_gpt`, bootable both as
# a raw-disk USB write (dd/balenaEtcher) and as burned optical media.
#
# Prerequisite: the image must have been built AFTER the Y16 initramfs fix
# (meta-duduclaw/recipes-core/images/core-image-minimal-initramfs.bbappend)
# landed and core-image-minimal-initramfs was rebuilt — without that fix,
# every image built on top of oe-core's stock INITRAMFS_SCRIPTS list
# carries `initramfs-module-setup-live` -> `udev-extraconf`, whose
# automount.rules/mount.sh races the initramfs's own root-mount logic and
# reliably wins on hybrid GPT+ISO9660 media (see the bbappend's comment
# block and commercial/docs/TODO-agent-first-os-2026-08.md Y16 section for
# the full root-cause chain). Building this script's output from a wic that
# still has the old initramfs baked into its UKI reproduces the Y13-2
# "Can't open blockdev" boot failure.
#
# Usage: build-hybrid-iso.sh <path-to-wic> <output.iso> [volume-id]
#
# Requires (apt-get install -y xorriso gdisk on the yocto-builder container):
#   xorriso, gdisk (for gdisk -l sector-boundary discovery)
set -euo pipefail

WIC="${1:?usage: build-hybrid-iso.sh <wic> <output.iso> [volume-id]}"
OUT_ISO="${2:?usage: build-hybrid-iso.sh <wic> <output.iso> [volume-id]}"
VOLID="${3:-DUDUCLAW_OS}"

command -v xorriso >/dev/null || { echo "xorriso not found (apt-get install -y xorriso)" >&2; exit 1; }
command -v gdisk >/dev/null || export PATH="$PATH:/usr/sbin:/sbin"
command -v gdisk >/dev/null || { echo "gdisk not found (apt-get install -y gdisk)" >&2; exit 1; }

WORKDIR="$(mktemp -d "$(dirname "$OUT_ISO")/hybrid-iso-work.XXXXXX")"
trap 'rm -rf "$WORKDIR"' EXIT

echo "[build-hybrid-iso] reading partition table from $WIC"
gdisk -l "$WIC" > "$WORKDIR/gdisk.txt"
cat "$WORKDIR/gdisk.txt"

# Parse the partition table: number, start sector, end sector, code (hex
# GPT type shorthand), name. gdisk -l's table columns are fixed-width but
# the Name field is free text, so match everything after the 4th
# whitespace-delimited column greedily.
mapfile -t PARTLINES < <(awk '/^Number/{f=1;next} f && NF>=6 {print}' "$WORKDIR/gdisk.txt")
[[ ${#PARTLINES[@]} -gt 0 ]] || { echo "[build-hybrid-iso] no partitions parsed from gdisk output" >&2; exit 1; }

declare -a APPEND_ARGS=()
declare -a CLEANUP_IMGS=()
PART_INDEX=0

code_to_guid() {
  case "$1" in
    EF00) echo "C12A7328-F81F-11D2-BA4B-00A0C93EC93B" ;;  # EFI System Partition
    8300) echo "0FC63DAF-8483-4772-8E79-3D69D8477DE4" ;;  # Linux filesystem data
    *) echo "" ;;
  esac
}

mkdir -p "$WORKDIR/isosrc/EFI"

while read -r num start end _size _unit code name; do
  guid="$(code_to_guid "$code")"
  if [[ -z "$guid" ]]; then
    echo "[build-hybrid-iso] skip partition $num (code=$code name=$name, no known GUID mapping)"
    continue
  fi
  PART_INDEX=$((PART_INDEX + 1))
  count=$((end - start + 1))
  img="$WORKDIR/part-$PART_INDEX.img"
  echo "[build-hybrid-iso] extracting partition $num ($name, $code) -> $img (start=$start count=$count sectors)"
  dd if="$WIC" of="$img" bs=512 skip="$start" count="$count" status=none conv=sparse
  APPEND_ARGS+=(-append_partition "$PART_INDEX" "$guid" "$img")
  CLEANUP_IMGS+=("$img")
done < <(awk '/^Number/{f=1;next} f && NF>=6 {print $1, $2, $3, $4, $5, $6, $7}' "$WORKDIR/gdisk.txt")

[[ ${#APPEND_ARGS[@]} -gt 0 ]] || { echo "[build-hybrid-iso] nothing to append (no ESP/Linux-typed partitions found)" >&2; exit 1; }

echo "[build-hybrid-iso] building hybrid ISO -> $OUT_ISO"
xorriso -as mkisofs \
  -V "$VOLID" \
  -partition_offset 16 \
  "${APPEND_ARGS[@]}" \
  -appended_part_as_gpt \
  -eltorito-alt-boot \
  -e --interval:appended_partition_1:all:: \
  -no-emul-boot \
  -o "$OUT_ISO" \
  "$WORKDIR/isosrc/"

echo "[build-hybrid-iso] done: $OUT_ISO"
ls -la "$OUT_ISO"
