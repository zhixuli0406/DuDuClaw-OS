#!/usr/bin/env bash
# 幫 VM 測試 clone 注入一個已知 root 密碼——只做密碼這一件事，不換任何
# duduclaw/duduclaw-sysd 二進位。
#
# 為什麼需要這支：`appliance/tests/lib/test_run.py` 的 `assert_no_failed_
# units` 得先能用序列主控台以 root 身分登入才跑得起來，但出貨 image 刻意
# 不設任何 root 密碼（`appliance/tests/lib/serial_console.py` 的 module
# doc、`commercial/docs/DESIGN-ab-update-rollback-2026-08.md` §11.6 都已現
# 場驗證過這件事——PAM 自己的 `res=failed` 稽核行）。`appliance/tests/
# ab-update/inject-binaries.sh` 已經有等價的 `AB_ROOT_PASSWORD` 機制，但那
# 支腳本同時要求 `duduclaw`/`duduclaw-sysd` 兩個 binary 存在（它的本職是
# 換二進位，密碼只是順便做的一步），而且它是 ab-update 那條測試線自己在
# 維護的檔案——沒必要為了「只想改密碼」去動它或替它加條件分支（本專案
# README 的既有慣例：「既有測試腳本不強制改寫」，`appliance/tests/
# README.md` 也已把「那條路徑需要 Docker + 已編譯的 duduclaw/duduclaw-
# sysd binary，超出本函式庫的範圍」寫成明確的已知缺口）。
#
# 這支腳本抽出同一套 Docker + losetup + `chroot chpasswd` 手法，做成一支
# 不需要任何已編譯 binary、專門且只做密碼注入的版本，讓 `assert_no_
# failed_units` 這類活測能在任何一顆「已 clone 出來的測試磁碟」上真的跑
# 起來，不必等一輪完整的 gateway/sysd Linux build。
#
# 安全界線（呼叫端不能繞過的部分）：
#   - 硬拒絕目標路徑的檔名等於母盤檔名（`duduclaw-os-vm.raw`）——這支腳本
#     只給「已經 clone 出來的測試磁碟」用，絕不碰母盤，寫死在腳本裡而不
#     是只靠呼叫端的紀律。
#   - 跟 `inject-binaries.sh` 一樣要求磁碟先關機（mount 進去跟開著的
#     QEMU 兩邊會打架），用同一招 pgrep 檢查，但比對的是磁碟自己的檔
#     名，不是寫死的某個波次 VM 名稱——這樣任何波次的 clone
#     （w53/w61/...）都能共用同一支腳本，不必各自約定命名。
#   - 出貨 image 建置（`appliance/build.sh` / mkosi）完全不會呼叫這支腳
#     本——它只活在 `appliance/tests/` 底下，不影響任何出貨路徑。
#
# 用法：
#   appliance/tests/lib/inject-root-password.sh <磁碟路徑> [密碼]
#   appliance/tests/lib/inject-root-password.sh appliance/.vm/w61.raw duduclaw
#   INJECT_IMAGE_MODE=partition inject-root-password.sh <root-fs.raw> duduclaw
#
# 密碼預設 `"duduclaw"`——`appliance/tests/lib/serial_console.py` 的
# `DEFAULT_ROOT_PASSWORD`，專案既有慣例，不另創第二套。
#
# 兩種目標形狀（`INJECT_IMAGE_MODE`，同 `inject-binaries.sh` 的
# `AB_IMAGE_MODE` 命名慣例）：
#   disk        （預設）整顆磁碟 image，有 GPT——losetup -fP 後掛 p2。
#   partition   單一 root 分割區 image——直接 mount -o loop。
#
# 前提：容器需要 privileged（losetup/mount），目標磁碟所在的 VM 必須先
# 關掉，且磁碟路徑必須落在這個 repo 底下（容器只掛 `$REPO_ROOT` 一棵
# 目錄樹）。
set -euo pipefail

APPLIANCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REPO_ROOT="$(cd "$APPLIANCE_DIR/.." && pwd)"

if [[ $# -lt 1 ]]; then
    echo "用法：inject-root-password.sh <磁碟路徑> [密碼]" >&2
    exit 1
fi
DISK_ARG="$1"
PASSWORD="${2:-duduclaw}"
MODE="${INJECT_IMAGE_MODE:-disk}"

case "$DISK_ARG" in
    /*) DISK="$DISK_ARG" ;;
    *) DISK="$(pwd)/$DISK_ARG" ;;
esac
DISK="$(cd "$(dirname "$DISK")" 2>/dev/null && pwd)/$(basename "$DISK")" || {
    echo "[inject-root-password] 找不到磁碟：$DISK_ARG" >&2
    exit 1
}

[[ -f "$DISK" ]] || { echo "[inject-root-password] 找不到磁碟：$DISK" >&2; exit 1; }

# 硬拒絕母盤——見檔頭「安全界線」。用 basename 比對，不用完整路徑，因為
# 母盤在不同呼叫端可能用不同的相對/絕對路徑指到同一個檔案。
if [[ "$(basename "$DISK")" == "duduclaw-os-vm.raw" ]]; then
    echo "[inject-root-password] 拒絕：$DISK 是母盤檔名（duduclaw-os-vm.raw），這支腳本只給已 clone 出來的測試磁碟用" >&2
    exit 1
fi

case "$MODE" in
    disk|partition) ;;
    *) echo "[inject-root-password] INJECT_IMAGE_MODE 只能是 disk 或 partition（收到 ${MODE}）" >&2; exit 1 ;;
esac

# 同 inject-binaries.sh 的防呆：mount 進去跟開著的 QEMU 兩邊會打架。比對
# 磁碟自己的檔名而非寫死的 VM 名稱，見檔頭說明。
DISK_BASENAME="$(basename "$DISK")"
if pgrep -f "qemu-system-aarch64.*${DISK_BASENAME}" >/dev/null 2>&1; then
    echo "[inject-root-password] 這顆磁碟目前有 QEMU 行程掛著——先關掉對應的 VM 再注入" >&2
    exit 1
fi

# 容器內只看得到 /work，所以路徑一律轉成 repo 相對——同 inject-binaries.sh
# 的 rel()。磁碟不在 repo 底下就直接拒絕，而不是把一個 /work 外的路徑
# 悄悄傳進容器（容器裡什麼都找不到，會用一個看起來像 bug 的方式失敗）。
rel() {
    case "$1" in
        "$REPO_ROOT"/*) echo "${1#"$REPO_ROOT"/}" ;;
        *)
            echo "[inject-root-password] 磁碟必須落在 repo 底下（$REPO_ROOT），收到：$1" >&2
            exit 1
            ;;
    esac
}
DISK_REL="$(rel "$DISK")"

echo "[inject-root-password] 目標：${DISK}（模式 ${MODE}）"

docker run --rm --privileged --platform linux/arm64 \
    -e "TARGET=/work/${DISK_REL}" \
    -e "MODE=$MODE" \
    -e "ROOTPW=$PASSWORD" \
    -v "$REPO_ROOT:/work" \
    debian:trixie bash -euo pipefail -c '
apt-get update -qq
apt-get install -y -qq --no-install-recommends util-linux e2fsprogs >/dev/null

mkdir -p /mnt/root
LOOP=""
if [ "$MODE" = "disk" ]; then
  LOOP=$(losetup -fP --show "$TARGET")
  echo "[inject-root-password] LOOP=$LOOP"
  sleep 1
  partprobe "$LOOP" || true
  # 容器內沒有 udev，分割區 device node 不會自己出現——照 sysfs 的
  # major:minor 自己補（同 inject-binaries.sh 踩過的坑）。
  for i in 1 2 3 4; do
    SYSP="/sys/class/block/$(basename $LOOP)/$(basename $LOOP)p$i"
    if [ -d "$SYSP" ]; then
      DEVNUM=$(cat "$SYSP/dev"); MAJ=${DEVNUM%:*}; MIN=${DEVNUM#*:}
      [ -e "${LOOP}p$i" ] || mknod "${LOOP}p$i" b "$MAJ" "$MIN"
    fi
  done
  mount "${LOOP}p2" /mnt/root
else
  mount -o loop "$TARGET" /mnt/root
fi

echo "root:$ROOTPW" | chroot /mnt/root /usr/sbin/chpasswd

# 正面斷言：確認 root 那一行真的有 hash，不是空欄位或 ! 鎖定
# （同 inject-binaries.sh 的把關，抄同一套；不用 awk 是因為整段容器腳本
# 本身包在單引號裡，內嵌單引號會提前截斷）。
ROOTHASH=$(grep ^root: /mnt/root/etc/shadow | cut -d: -f2)
case "$ROOTHASH" in
  \$*) echo "[inject-root-password] shadow root 欄位已是雜湊" ;;
  *)   echo "[inject-root-password] shadow root 欄位不是雜湊，登入仍會失敗" >&2; exit 1 ;;
esac

sync
umount /mnt/root
[ -n "$LOOP" ] && losetup -d "$LOOP"
echo "INJECT_DONE"
'
echo "[inject-root-password] 完成。"
