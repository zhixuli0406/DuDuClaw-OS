#!/usr/bin/env bash
# D4a-9 stage 1 — put the TEST-ONLY wireless packages into a COPY of the built
# image, without putting them in the shipping image.
#
# Decision G-② (commercial/docs/DESIGN-network-settings-2026-08.md section 9):
# hostapd / iw / iproute2 exist only to fake an access point and to poke at the
# result. Shipping them would add ~3.7 MB and, worse, put an AP daemon on a
# device whose entire security posture assumes it is a client. So CI takes the
# real shipping artifact and injects them offline into a throwaway copy.
#
# Offline dpkg is the only option: the image has no /etc/apt/sources.list at
# all (verified — /etc/apt contains only apt.conf.d/70debconf), so `apt-get
# install` inside it fails on every package, always.
#
# Runs on the HOST (macOS or Linux) and needs Docker with privileged
# containers — loop-mounting a raw disk image is a kernel operation macOS
# cannot do natively.
#
# Usage:
#     ./inject-test-packages.sh [path/to/duduclaw-os.raw] [output.raw]
# Defaults to appliance/mkosi.output/duduclaw-os.raw -> appliance/.vm/wifi-ci.raw
#
# After this, boot the output image (appliance/run-vm.sh or smoke-qemu.sh) and
# run run-hwsim-wifi.sh inside it.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SRC="${1:-$REPO_ROOT/appliance/mkosi.output/duduclaw-os.raw}"
DST="${2:-$REPO_ROOT/appliance/.vm/wifi-ci.raw}"

# root-a starts at LBA 1050624 (from `sfdisk -J` on the built image). If the
# partition layout in appliance/mkosi.repart/ ever changes, this constant is
# the thing that breaks — loudly, at mount time, not silently.
ROOT_A_OFFSET_LBA=1050624
SECTOR=512

# Test-only. iproute2 is included because the shipping image has no `ip`
# command at all, which the first spike round only discovered when every
# `ip link set ...` in a script died with "command not found".
PACKAGES=(hostapd iw iproute2 libnl-3-200 libnl-genl-3-200 libnl-route-3-200)

[[ -f "$SRC" ]] || { echo "source image not found: $SRC" >&2; exit 2; }
command -v docker >/dev/null || { echo "docker is required" >&2; exit 2; }

mkdir -p "$(dirname "$DST")"
echo "[1/3] copying $SRC -> $DST"
# -c asks APFS for a copy-on-write clone: instant, and it costs no extra disk
# until the copy diverges. Falls back to a plain copy on filesystems without it.
cp -c "$SRC" "$DST" 2>/dev/null || cp "$SRC" "$DST"

# The packages must match the IMAGE's architecture, not the host's — and on
# macOS `uname -m` lies under a Rosetta shell (returns x86_64 on Apple
# Silicon; this repo's documented trap, hit live here on 2026-08-23, which
# injected amd64 debs into an arm64 root). Honor an explicit override first,
# then ask the platform directly.
ARCH="${APPLIANCE_ARCH:-}"
if [[ -z "$ARCH" ]]; then
    if [[ "$(uname -s)" == "Darwin" ]] && [[ "$(sysctl -n hw.optional.arm64 2>/dev/null)" == "1" ]]; then
        ARCH=arm64
    else
        ARCH="$(uname -m)"
    fi
fi
case "$ARCH" in
    arm64|aarch64) PLATFORM=linux/arm64 ;;
    x86_64|amd64)  PLATFORM=linux/amd64 ;;
    *) echo "unsupported arch $ARCH (set APPLIANCE_ARCH=arm64|x86_64)" >&2; exit 2 ;;
esac
echo "[inject] target architecture: $ARCH ($PLATFORM)"

echo "[2/3] injecting: ${PACKAGES[*]}"
docker run --rm --privileged --platform "$PLATFORM" \
    -v "$(cd "$(dirname "$DST")" && pwd):/vm" \
    -e IMG="/vm/$(basename "$DST")" \
    -e OFFSET="$((ROOT_A_OFFSET_LBA * SECTOR))" \
    -e PKGS="${PACKAGES[*]}" \
    debian:trixie-slim bash -euxc '
        mkdir -p /mnt/root /debs
        mount -o loop,offset="$OFFSET" "$IMG" /mnt/root
        apt-get update -qq
        cd /debs && apt-get download $PKGS
        cp /debs/*.deb /mnt/root/root/
        mount --bind /proc /mnt/root/proc
        mount --bind /sys  /mnt/root/sys
        mount --bind /dev  /mnt/root/dev
        # The glob must expand INSIDE the chroot (the container'\''s own /root
        # is empty, so expanding it out here passes dpkg a literal star —
        # caught on this harness'\''s first live run, 2026-08-23).
        chroot /mnt/root sh -c "dpkg -i /root/*.deb"
        chroot /mnt/root sh -c "rm -f /root/*.deb"
        umount /mnt/root/proc /mnt/root/sys /mnt/root/dev
        umount /mnt/root
    '

echo "[3/3] done: $DST"
echo
echo "Next: boot it and run the walkthrough inside the VM, e.g."
echo "  appliance/run-vm.sh --image $DST"
echo "  # then, on the serial console, as root:"
echo "  /path/to/run-hwsim-wifi.sh"
