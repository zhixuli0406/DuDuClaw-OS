#!/usr/bin/env bash
# 把剛編好的 Linux 二進位換進一份 root 檔案系統（離線注入）。
#
# 為什麼需要這支：image 裡的 `duduclaw` / `duduclaw-sysd` 是烤 image 當下編進去的。
# 要測 gateway/sysd 的新程式碼，不必重烤一顆 15GB 的 image（半小時起跳），
# 把檔案系統 mount 起來換掉那兩個檔就好。這是 appliance/.vm/inject-s4/do_inject.sh
# 已經驗證過的手法，這裡收斂成可重複、帶參數、兩種目標形狀的一支。
#
# 兩種目標（AB_IMAGE_MODE）：
#   disk        （預設）整顆磁碟 image，有 GPT——losetup -fP 後掛 p2（slot A）。
#   partition   單一 root 分割區 image，例如 H3d payload 產線吐出來的
#               duduclaw-os_<ver>.root-<arch>.raw——直接 mount -o loop。
#
#               **payload 也要注入，不是可選項**：payload 是從舊 image 切出來的，
#               裡面那顆 gateway 是舊的。不換的話，T2 更新完開進新槽跑的是舊
#               gateway、舊 sysd（沒有 UpdateRollback 動詞），T6 手動回退當場就
#               沒東西可測。
#
# 容器裡要 privileged：losetup / mount 需要。容器內沒有 udev，所以 disk 模式的
# 分割區 device node 要自己 mknod（do_inject.sh 踩過這個坑，照抄）。
#
# 環境變數：
#   AB_ROOT_PASSWORD   設了才會改 root 密碼（出貨 image 沒設密碼，探針要靠這個
#                      才進得了序列 shell）。未設＝完全不碰 /etc/shadow。
#
# 用法：
#   appliance/tests/ab-update/inject-binaries.sh                          # .vm/duduclaw-os-ab.raw 的 slot A
#   AB_DISK=/path/to/x.raw AB_IMAGE_MODE=partition inject-binaries.sh     # payload 的 root 檔案系統
#
# 前提：對應的 VM **必須先關掉**（磁碟被 QEMU 開著時 mount 進去會兩邊打架）。
set -euo pipefail

APPLIANCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REPO_ROOT="$(cd "$APPLIANCE_DIR/.." && pwd)"
DISK="${AB_DISK:-$APPLIANCE_DIR/.vm/duduclaw-os-ab.raw}"
MODE="${AB_IMAGE_MODE:-disk}"
BIN="${DUDUCLAW_BIN_PATH:-$APPLIANCE_DIR/.build/duduclaw}"
SYSD="${DUDUCLAW_SYSD_PATH:-$APPLIANCE_DIR/.build/duduclaw-sysd}"

for f in "$DISK" "$BIN" "$SYSD"; do
    [[ -f "$f" ]] || { echo "[inject] 找不到 $f" >&2; exit 1; }
done
case "$MODE" in
    disk|partition) ;;
    *) echo "[inject] AB_IMAGE_MODE 只能是 disk 或 partition（收到 ${MODE}）" >&2; exit 1 ;;
esac
if [[ "$MODE" == "disk" ]] && pgrep -f "duduclaw-os-vm-ab" >/dev/null 2>&1; then
    echo "[inject] AB 測試 VM 還在跑——先關掉（pkill -f duduclaw-os-vm-ab）再注入" >&2
    exit 1
fi

# 容器內只看得到 /work，所以路徑一律轉成 repo 相對。
rel() { echo "${1#"$REPO_ROOT/"}"; }
echo "[inject] 目標：${DISK}（模式 ${MODE}）"
echo "[inject] duduclaw：$(shasum -a 256 "$BIN" | cut -c1-16)…  sysd：$(shasum -a 256 "$SYSD" | cut -c1-16)…"

docker run --rm --privileged --platform linux/arm64 \
    -e "TARGET=/work/$(rel "$DISK")" \
    -e "MODE=$MODE" \
    -e "BIN=/work/$(rel "$BIN")" \
    -e "SYSD=/work/$(rel "$SYSD")" \
    -e "ROOTPW=${AB_ROOT_PASSWORD:-}" \
    -v "$REPO_ROOT:/work" \
    debian:trixie bash -euo pipefail -c '
apt-get update -qq
apt-get install -y -qq --no-install-recommends util-linux e2fsprogs >/dev/null

mkdir -p /mnt/root
LOOP=""
if [ "$MODE" = "disk" ]; then
  LOOP=$(losetup -fP --show "$TARGET")
  echo "[inject] LOOP=$LOOP"
  sleep 1
  partprobe "$LOOP" || true
  # 容器內沒有 udev，partition device node 不會自己出現——照 sysfs 的 major:minor 自己補。
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

echo "[inject] 換之前："
sha256sum /mnt/root/usr/local/bin/duduclaw /mnt/root/usr/local/bin/duduclaw-sysd

install -m 0755 "$BIN"  /mnt/root/usr/local/bin/duduclaw.new
mv /mnt/root/usr/local/bin/duduclaw.new  /mnt/root/usr/local/bin/duduclaw
install -m 0755 "$SYSD" /mnt/root/usr/local/bin/duduclaw-sysd.new
mv /mnt/root/usr/local/bin/duduclaw-sysd.new /mnt/root/usr/local/bin/duduclaw-sysd

echo "[inject] 換之後："
sha256sum /mnt/root/usr/local/bin/duduclaw /mnt/root/usr/local/bin/duduclaw-sysd

# 序列主控台的 root 密碼。**出貨 image 沒有設任何 root 密碼**（刻意的），
# 所以測試磁碟得自己補一個已知值，否則探針連 shell 都進不去。
# 先前幾輪是在 shell 裡手打 awk 改 /etc/shadow（.vm/inject/set_root_pw.awk
# 就是那次留下的、沒有任何呼叫端的殘骸）——收斂進來才可重跑。
#
# 預設不設（AB_ROOT_PASSWORD 未給就整段跳過），出貨路徑逐位不變；
# 用目標系統自己的 chpasswd 而不是自己刻 hash，雜湊格式與演算法就一定
# 跟那顆 image 相容。
if [ -n "${ROOTPW:-}" ]; then
  if echo "root:$ROOTPW" | chroot /mnt/root /usr/sbin/chpasswd 2>/dev/null; then
    echo "[inject] 已設定 root 序列登入密碼（測試磁碟專用）"
  else
    echo "[inject] chroot chpasswd 失敗——探針將無法登入" >&2
    exit 1
  fi
  # 正面斷言：確認 root 那一行真的有 hash，不是空欄位或 ! 鎖定。
  # 刻意不用 awk——整段容器腳本本身就包在單引號裡，任何內嵌單引號都會提前
  # 把它截斷（第一版就是這樣壞的）。
  ROOTHASH=$(grep ^root: /mnt/root/etc/shadow | cut -d: -f2)
  case "$ROOTHASH" in
    \$*) echo "[inject] shadow root 欄位已是雜湊" ;;
    *)   echo "[inject] shadow root 欄位不是雜湊，登入仍會失敗" >&2; exit 1 ;;
  esac
fi

# .transfer 檔也一起換上最新的：staging 路徑在 H3d 從 /var/lib 改成 /data，
# image 裡那兩份還是舊的，不換的話 sysupdate 會去看一個永遠空的目錄。
install -m 0644 /work/appliance/mkosi.extra/etc/sysupdate.d/10-duduclaw-root.transfer \
    /mnt/root/etc/sysupdate.d/10-duduclaw-root.transfer
install -m 0644 /work/appliance/mkosi.extra/etc/sysupdate.d/20-duduclaw-uki.transfer \
    /mnt/root/etc/sysupdate.d/20-duduclaw-uki.transfer
grep -H "^Path=" /mnt/root/etc/sysupdate.d/*.transfer

sync
umount /mnt/root
[ -n "$LOOP" ] && losetup -d "$LOOP"
echo "INJECT_DONE"
'
echo "[inject] 完成。"
