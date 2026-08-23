#!/usr/bin/env bash
# A/B 更新測試專用 VM（H3a 起，2026-08-23）。
#
# 為什麼另開一支而不是共用 inject/boot-firstrun.sh：
#   1. **埠全錯開**——firstrun 那台佔 serial 47023／QMP 47024／VNC :1／
#      dashboard 18793，而 A/B 測試常常要跟其他線的活測同時進行。這支用
#      serial 47031／QMP 47032／VNC :2／dashboard 18795，兩台可並存。
#   2. **每個 case 都從 pristine 重新複製磁碟**（`AB_FRESH=1`，預設就是 fresh）。
#      A/B 狀態是有記憶的（槽位標籤、ESP 上的計數後綴、bless-boot 標記），
#      在同一顆磁碟上串接 case 會讓失敗無法歸因。
#   3. **沒有 `-no-reboot`**。boot counting 的整個生命週期都發生在重開機之間，
#      smoke-qemu.sh 的 `-no-reboot`（guest 重開機＝QEMU 結束）會讓這類測試
#      連跑都跑不起來。
#
# varstore 每次重置：run-vm.sh 記錄過的實測踩坑——用過的 varstore 可能留下
# 會掉進 UEFI Shell 的 BootOrder。這對 A/B 測試特別安全，因為 boot counting
# 的狀態存在 ESP 的**檔名**裡而不是 EFI 變數裡，重置 varstore 不會洗掉它。
#
# 用法：
#   appliance/.vm/ab-test/boot-ab.sh              # 從 pristine 複製乾淨磁碟後開機
#   AB_FRESH=0 appliance/.vm/ab-test/boot-ab.sh   # 沿用上次的磁碟（跨重開機的多輪測試）
#
# 關機：pkill -f duduclaw-os-vm-ab
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"   # appliance/
# 這支腳本住在 appliance/tools/ab-test/（會進 git），
# 但所有 VM 執行期狀態（磁碟複本、varstore、log）一律落在 appliance/.vm/
# ——那個目錄是 gitignore 的，13G+ 的磁碟不進 repo。
WORK="$DIR/.vm"
SRC="${VM_IMAGE:-$DIR/mkosi.output/duduclaw-os.raw}"
DISK="$WORK/duduclaw-os-ab.raw"
CODE=/opt/homebrew/share/qemu/edk2-aarch64-code.fd
VARS_TMPL=/opt/homebrew/share/qemu/edk2-arm-vars.fd
VARS="$WORK/vars-ab.fd"

[[ -f "$SRC" ]] || { echo "[ab] 找不到 image：$SRC（先跑 appliance/build.sh）" >&2; exit 1; }

if [[ "${AB_FRESH:-1}" != "0" || ! -f "$DISK" ]]; then
    echo "[ab] 從 pristine image 複製乾淨磁碟（APFS clone，瞬間完成、仍為 sparse）..."
    rm -f "$DISK"
    cp -c "$SRC" "$DISK" 2>/dev/null || cp "$SRC" "$DISK"
fi
cp "$VARS_TMPL" "$VARS"

echo "[ab] 序列 → 127.0.0.1:47031   QMP → 127.0.0.1:47032"
echo "[ab] 畫面 → VNC localhost:5902   儀表板 → http://localhost:18795"

exec qemu-system-aarch64 \
  -name duduclaw-os-vm-ab \
  -machine virt,accel=hvf -cpu host -smp 4 -m 4096 \
  -drive if=pflash,format=raw,readonly=on,file="$CODE" \
  -drive if=pflash,format=raw,file="$VARS" \
  -drive if=virtio,format=raw,file="$DISK" \
  -netdev user,id=net0,hostfwd=tcp:127.0.0.1:18795-:18789 \
  -device virtio-net-pci,netdev=net0 \
  -display none \
  -device virtio-gpu-pci -device qemu-xhci,id=usb -device usb-tablet -device usb-kbd \
  -vnc 127.0.0.1:2 \
  -qmp tcp:127.0.0.1:47032,server,nowait \
  -serial tcp:127.0.0.1:47031,server,nowait
