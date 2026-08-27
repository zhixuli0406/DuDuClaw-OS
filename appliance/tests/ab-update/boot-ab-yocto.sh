#!/usr/bin/env bash
# A/B 更新測試專用 VM —— Yocto 線版本（Y9-2，2026-08-27）。
#
# 逐字對照 appliance/tests/ab-update/boot-ab.sh（Debian/mkosi 線）移植，三處
# 必須不同、其餘邏輯（fresh-copy-per-case、無 -no-reboot、varstore 處理）逐字
#照抄：
#
#   1. **架構／加速器**：Debian 線是 arm64 image（`qemu-system-aarch64
#      -accel hvf`，本機原生跑）；Yocto 線的 MACHINE=duduclaw-qemux86-64 是
#      x86_64（見 appliance/run-vm-yocto.sh 同一決策），跨架構在 Apple
#      Silicon 上沒有 HVF 可用，只能 `-accel tcg`（明顯更慢，符合預期，非
#      bug）。CPU 型號沿用 run-vm-yocto.sh 已驗證過的 `-cpu Skylake-Client`
#      （DEFAULTTUNE=x86-64-v3 需要 AVX2 基準線，不可拿掉）。
#   2. **埠全部改用 47051/47052**（serial/QMP）——任務指示保留 47023/47025
#      給既有交付機（firstrun／run-vm-yocto 常駐台），47031/47032 是 Debian
#      線自己的 A/B 測試埠，這裡再錯開一組，四台可同時並存互不干擾。
#   3. **UEFI 韌體是 x86_64 版**（edk2-x86_64-code.fd + edk2-i386-vars.fd，
#      與 run-vm-yocto.sh 一致），不是 Debian 線的 edk2-aarch64-*。
#
# varstore 每次重置（不持久）：這是刻意跟 Debian 線 boot-ab.sh 不同的一點
# ——那支保留「NVRAM 可持久」的空間但從沒真的靠它；run-vm-yocto.sh 則有
# 實測踩坑紀錄（重用過的 vars-yocto.fd 讓 BootOrder 掉進 PXE 迴圈，見該檔
# 註解）。boot counting 的狀態本身活在 ESP 的檔名裡而非 EFI 變數
# （DESIGN-ab-update-rollback-2026-08.md §6.1「好消息」一段），所以每次
# reset varstore 不影響任何一個 T 案的正確性，反而規避掉那個已知踩坑。
#
# 用法：
#   VM_IMAGE=<path-to-.wic> appliance/tests/ab-update/boot-ab-yocto.sh
#   AB_FRESH=0 appliance/tests/ab-update/boot-ab-yocto.sh   # 沿用上次磁碟（跨重開機多輪測試）
#
# 關機：pkill -f duduclaw-os-vm-ab-yocto
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"   # appliance/
WORK="$DIR/.vm"
mkdir -p "$WORK"
# 預設來源：build 完成後用 `docker cp` 從 builder 容器的 named volume
# 拉出來的落地檔（見任務紀錄——deploy 目錄在 /yocto-vmfs，不是 bind mount，
# host 端本來就看不到，必須先 docker cp 出來）。
SRC="${VM_IMAGE:-$WORK/duduclaw-os-ab-yocto-src.wic}"
DISK="$WORK/duduclaw-os-ab-yocto.wic"
CODE=/opt/homebrew/share/qemu/edk2-x86_64-code.fd
VARS_TMPL=/opt/homebrew/share/qemu/edk2-i386-vars.fd
VARS="$WORK/vars-ab-yocto.fd"

[[ -f "$SRC" ]] || { echo "[ab-yocto] 找不到來源 image：${SRC}（先從 builder 容器 docker cp 出 .wic）" >&2; exit 1; }
[[ -f "$CODE" && -f "$VARS_TMPL" ]] || { echo "[ab-yocto] 找不到 UEFI 韌體" >&2; exit 1; }

if [[ "${AB_FRESH:-1}" != "0" || ! -f "$DISK" ]]; then
    echo "[ab-yocto] 從 pristine image 複製乾淨磁碟（APFS clone，瞬間完成、仍為 sparse）..."
    rm -f "$DISK"
    cp -c "$SRC" "$DISK" 2>/dev/null || cp "$SRC" "$DISK"
fi

if [[ "${AB_PREPARE_ONLY:-0}" == "1" ]]; then
    echo "[ab-yocto] AB_PREPARE_ONLY=1——磁碟已就緒（${DISK}），不開機。"
    exit 0
fi

cp "$VARS_TMPL" "$VARS"

SERIAL_PORT="${AB_SERIAL_PORT:-47051}"
QMP_PORT="${AB_QMP_PORT:-47052}"
DASH_PORT="${AB_DASH_PORT:-18797}"
MEM="${VM_MEM:-2048}"
SMP="${VM_SMP:-4}"

echo "[ab-yocto] 序列 → 127.0.0.1:${SERIAL_PORT}   QMP → 127.0.0.1:${QMP_PORT}"
echo "[ab-yocto] 儀表板 → http://localhost:${DASH_PORT}"

exec qemu-system-x86_64 \
  -name duduclaw-os-vm-ab-yocto \
  -machine q35,i8042=off -accel tcg -cpu Skylake-Client -smp "$SMP" -m "$MEM" \
  -drive if=pflash,format=raw,readonly=on,file="$CODE" \
  -drive if=pflash,format=raw,file="$VARS" \
  -drive file="$DISK",if=virtio,format=raw \
  -netdev user,id=net0,hostfwd=tcp:127.0.0.1:${DASH_PORT}-:18789 \
  -device virtio-net-pci,netdev=net0 \
  -object rng-random,filename=/dev/urandom,id=rng0 \
  -device virtio-rng-pci,rng=rng0 \
  -display none \
  -usb -device usb-tablet -device usb-kbd \
  -qmp tcp:127.0.0.1:${QMP_PORT},server,nowait \
  -serial tcp:127.0.0.1:${SERIAL_PORT},server,nowait
