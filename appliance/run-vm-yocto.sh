#!/usr/bin/env bash
# Boot the Yocto/Agent-Native-OS "開機即殼" image as a long-lived host-side VM
# for hands-on testing. Distinct from run-vm.sh (the Debian/mkosi appliance
# line, ports 47023/47024) -- this is the Yocto line, its own dedicated
# port block (Y5-1, 2026-08-26): serial 47025 / QMP 47026 / VNC 5902.
#
# Runs on the HOST (macOS, Apple Silicon) via qemu-system-x86_64 + TCG
# (no HVF/KVM possible cross-arch), NOT inside the Yocto builder container --
# the builder is only for pulling/rebuilding the image, per the standing
# rule not to run long-lived delivery VMs inside a container shared with
# other concurrent build sessions.
#
# Usage:
#   appliance/run-vm-yocto.sh              # boot in the background, detached
#   appliance/run-vm-yocto.sh fg           # boot attached to this terminal (serial on stdio)
#
# Connect:
#   Serial console: nc 127.0.0.1 47025      (or: telnet 127.0.0.1 47025)
#   QMP control:    nc 127.0.0.1 47026      (send `{"execute":"qmp_capabilities"}` first)
#   VNC display:    open vnc://127.0.0.1:5902   (Screen Sharing.app on macOS, or any VNC client)
#
# Stop it: pkill -f duduclaw-os-yocto-vm
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VM_DIR="$DIR/.vm"
WIC="${VM_IMAGE:-$VM_DIR/duduclaw-os-yocto.wic}"
VARS="$VM_DIR/vars-yocto.fd"
CODE_CANDS=(/opt/homebrew/share/qemu/edk2-x86_64-code.fd /usr/local/share/qemu/edk2-x86_64-code.fd /usr/share/OVMF/OVMF_CODE.fd)
VARS_TMPL_CANDS=(/opt/homebrew/share/qemu/edk2-i386-vars.fd /usr/local/share/qemu/edk2-i386-vars.fd /usr/share/OVMF/OVMF_VARS.fd)

[[ -f "$WIC" ]] || { echo "[run-vm-yocto] image not found: $WIC — pull it from the builder first" >&2; exit 1; }

pick() { for c in "$@"; do [[ -n "${c:-}" && -f "$c" ]] && { echo "$c"; return; }; done; }
CODE="$(pick "${CODE_CANDS[@]}")"
VARS_TMPL="$(pick "${VARS_TMPL_CANDS[@]}")"
[[ -n "$CODE" && -n "$VARS_TMPL" ]] || { echo "[run-vm-yocto] UEFI firmware not found" >&2; exit 1; }
# Reset from the pristine template on EVERY launch, not just when missing --
# same reasoning as appliance/run-vm.sh's own VARS handling: a varstore that
# has already been booted once can accumulate a BootOrder that falls through
# to PXE instead of the disk (observed directly, 2026-08-26: a reused
# vars-yocto.fd looped "Start PXE over IPv4" -> "over IPv6" forever after an
# earlier run). No NVRAM state is meant to persist across launches -- the
# ESP's removable-fallback path is what boots the disk every time.
cp "$VARS_TMPL" "$VARS"

MEM="${VM_MEM:-2048}"
SMP="${VM_SMP:-4}"
SERIAL_PORT="${SERIAL_PORT:-47025}"
QMP_PORT="${QMP_PORT:-47026}"
VNC_DISPLAY="${VNC_DISPLAY:-2}"   # :2 -> TCP 5900+2 = 5902

MODE="${1:-bg}"

ARGS=(
  -name duduclaw-os-yocto-vm
  -machine q35,i8042=off -accel tcg -cpu Skylake-Client -smp "$SMP" -m "$MEM"
  -drive if=pflash,format=raw,readonly=on,file="$CODE"
  -drive if=pflash,format=raw,file="$VARS"
  -drive file="$WIC",if=virtio,format=raw
  -netdev user,id=net0
  -device virtio-net-pci,netdev=net0
  -object rng-random,filename=/dev/urandom,id=rng0
  -device virtio-rng-pci,rng=rng0
  # No explicit GPU device: q35's own default VGA-compatible adapter
  # (Linux driver name "bochs-drm") is what duduclaw-comp's smithay/udev
  # backend actually renders to and what QEMU's own VNC/screendump reads
  # from -- confirmed empirically (2026-08-26): adding an EXTRA
  # virtio-gpu-pci device creates a second, ambiguous DRM card (card0
  # virtio-pci + card1 bochs-drm) and comp picks whichever udev enumerates
  # first, which is not reliably the one QEMU's display frontend shows,
  # producing a black VNC/screendump even though the compositor is running
  # fine. `-vga none` would also "fix" the ambiguity but removes the only
  # device that actually works here, so the right fix is simply not adding
  # a second GPU at all.
  -usb -device usb-tablet -device usb-kbd
  -vnc "127.0.0.1:${VNC_DISPLAY}"
  -qmp "tcp:127.0.0.1:${QMP_PORT},server,nowait"
)

echo "[run-vm-yocto] wic=$WIC"
echo "[run-vm-yocto] serial -> 127.0.0.1:${SERIAL_PORT}  qmp -> 127.0.0.1:${QMP_PORT}  vnc -> 127.0.0.1:$((5900+VNC_DISPLAY))"

if [[ "$MODE" == "fg" ]]; then
    exec qemu-system-x86_64 "${ARGS[@]}" -serial mon:stdio -nographic
else
    nohup qemu-system-x86_64 "${ARGS[@]}" \
        -serial "tcp:127.0.0.1:${SERIAL_PORT},server,nowait" \
        -display none \
        > "$VM_DIR/yocto-vm.log" 2>&1 &
    echo "[run-vm-yocto] started in background, pid $!"
    echo "[run-vm-yocto] logs: $VM_DIR/yocto-vm.log"
fi
