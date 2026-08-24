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

[[ -f "$SRC" ]] || { echo "[ab] 找不到 image：${SRC}（先跑 appliance/build.sh）" >&2; exit 1; }

if [[ "${AB_FRESH:-1}" != "0" || ! -f "$DISK" ]]; then
    echo "[ab] 從 pristine image 複製乾淨磁碟（APFS clone，瞬間完成、仍為 sparse）..."
    rm -f "$DISK"
    cp -c "$SRC" "$DISK" 2>/dev/null || cp "$SRC" "$DISK"
    # H3d：/data 在原尺寸 image 裡只有 4GiB，但一份 root payload 的表面大小就是
    # 5GiB（sparse 落地後仍約 3.7GiB）——放不下。把磁碟檔撐大，開機時
    # duduclaw-firstboot-repart.service 會照 /usr/lib/repart.d 把 /data 長到
    # 剩餘空間，這正是真硬體（USB→NVMe）走的同一條路，順便也把那條從沒在
    # 大磁碟上實測過的路徑一起測掉。
    # AB_DISK_GROW=0 可關掉（例如只跑 h3bc 的 T0-T4，不需要空間）。
    GROW_GIB="${AB_DISK_GROW:-10}"
    if [[ "$GROW_GIB" != "0" ]]; then
        CUR=$(stat -f %z "$DISK" 2>/dev/null || stat -c %s "$DISK")
        NEW=$(( CUR + GROW_GIB * 1024 * 1024 * 1024 ))
        # truncate 只改檔案長度，不寫任何位元組——sparse 檔案不會因此佔空間。
        # GPT 備份表頭因此不再位於磁碟末端；systemd-repart 開機時會把它搬到
        # 正確位置（這也是它成長分割區的必經步驟）。
        if command -v truncate >/dev/null 2>&1; then
            truncate -s "$NEW" "$DISK"
        else
            python3 -c "import sys; f=open(sys.argv[1],'r+b'); f.truncate(int(sys.argv[2]))" "$DISK" "$NEW"
        fi
        echo "[ab] 磁碟由 $CUR 撐到 $NEW bytes（+${GROW_GIB}GiB，/data 開機時自動成長）"
    fi
fi
# AB_PREPARE_ONLY=1：只準備磁碟就結束，不開機。給「開機前還要離線動磁碟」的
# 流程用（H3d 的 inject-binaries.sh 要在 VM 沒開的時候 mount slot A）。
if [[ "${AB_PREPARE_ONLY:-0}" == "1" ]]; then
    echo "[ab] AB_PREPARE_ONLY=1——磁碟已就緒（${DISK}），不開機。"
    exit 0
fi

cp "$VARS_TMPL" "$VARS"

# 儀表板轉發埠可覆寫：其他線的 VM 也在跑時 18795 會被佔住，而 QEMU 對
# hostfwd 佔用是硬失敗（整台開不起來）。序列/QMP 埠不動——探針靠的是那兩個。
DASH_PORT="${AB_DASH_PORT:-18795}"

echo "[ab] 序列 → 127.0.0.1:47031   QMP → 127.0.0.1:47032"
echo "[ab] 畫面 → VNC localhost:5902   儀表板 → http://localhost:${DASH_PORT}"

exec qemu-system-aarch64 \
  -name duduclaw-os-vm-ab \
  -machine virt,accel=hvf -cpu host -smp 4 -m 4096 \
  -drive if=pflash,format=raw,readonly=on,file="$CODE" \
  -drive if=pflash,format=raw,file="$VARS" \
  -drive if=virtio,format=raw,file="$DISK" \
  -netdev user,id=net0,hostfwd=tcp:127.0.0.1:${DASH_PORT}-:18789 \
  -device virtio-net-pci,netdev=net0 \
  -display none \
  -device virtio-gpu-pci -device qemu-xhci,id=usb -device usb-tablet -device usb-kbd \
  -vnc 127.0.0.1:2 \
  -qmp tcp:127.0.0.1:47032,server,nowait \
  -serial tcp:127.0.0.1:47031,server,nowait
