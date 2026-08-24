#!/usr/bin/env bash
# 為 A/B 測試編出 Linux 二進位（duduclaw ＋ duduclaw-sysd），不重烤 image。
#
# 為什麼不直接用 appliance/build.sh：那支會跑整套 mkosi（15GB、半小時起跳）。
# 測 gateway/sysd 的程式碼改動只需要那兩個檔，編完用 inject-binaries.sh 換進
# 測試磁碟就好。
#
# 為什麼要有這支而不是每次手打 docker run（2026-08-24 的教訓）：
#   * **`libssl-dev` 不能漏**。rust:slim 每次 `--rm` 都是乾淨的，少了它
#     `duduclaw-cli` 會在最後 link 階段死在 `cannot find -lcrypto`——而且是
#     在編完整個 workspace 之後才死，一次浪費 40 分鐘。手打指令重試時漏掉
#     這行，正是這樣浪費掉的。
#   * **CARGO_TARGET_DIR 必須指向具名 volume**，不能讓它落在掛進去的 /src
#     上：host 的 target/ 是 macOS 建置用的，被 Linux 產物覆蓋會同時弄壞
#     其他正在跑的 session。
#   * **job 數要壓**。Docker Desktop 的 VM 只有 ~7.7GiB，link duduclaw-gateway
#     時吃很兇；與其他 session 的容器並存時 3 個 job 會被 OOM killer 砍
#     （signal: 9），實測 1 個 job 穩。
#
# 具名 volume 讓重跑只重編改動的 crate，第二次通常幾分鐘就好。
#
# 用法：
#   appliance/tests/ab-update/build-linux-bins.sh          # 預設 arm64、1 job
#   BIN_ARCH=x86-64 BIN_JOBS=2 build-linux-bins.sh
set -euo pipefail

APPLIANCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REPO_ROOT="$(cd "$APPLIANCE_DIR/.." && pwd)"
ARCH="${BIN_ARCH:-arm64}"
JOBS="${BIN_JOBS:-1}"

case "$ARCH" in
    arm64)  PLATFORM="linux/arm64" ;;
    x86-64) PLATFORM="linux/amd64" ;;
    *) echo "[bins] BIN_ARCH 只能是 arm64 或 x86-64（收到 ${ARCH}）" >&2; exit 1 ;;
esac

mkdir -p "$APPLIANCE_DIR/.build"
LOG="$APPLIANCE_DIR/.build/linux-bins-${ARCH}.log"
echo "[bins] 目標 ${PLATFORM}，jobs=${JOBS}，log → ${LOG}"

docker run --rm --platform "$PLATFORM" \
    -e CARGO_BUILD_JOBS="$JOBS" \
    -e CARGO_TARGET_DIR=/target \
    -v "$REPO_ROOT:/src" \
    -v "duduclaw-${ARCH}-target:/target" \
    -v "duduclaw-${ARCH}-registry:/usr/local/cargo/registry" \
    -w /src rust:slim bash -euo pipefail -c '
# 這兩個套件是 link 期才需要的，少了會在整包編完之後才爆。
apt-get update -qq
apt-get install -y -qq --no-install-recommends pkg-config libssl-dev >/dev/null
cargo build --release --no-default-features \
    --features duduclaw-gateway/dashboard \
    -p duduclaw-cli -p duduclaw-gateway -p duduclaw-sysd
cp /target/release/duduclaw      /src/appliance/.build/duduclaw.new
cp /target/release/duduclaw-sysd /src/appliance/.build/duduclaw-sysd.new
echo BUILD_OK
' 2>&1 | tee "$LOG" | grep -E "^(BUILD_OK|error|warning: unused)" || true

if ! grep -q "^BUILD_OK" "$LOG"; then
    echo "[bins] 建置失敗，完整訊息在 ${LOG}" >&2
    tail -20 "$LOG" >&2
    exit 1
fi

# 只有真的成功才動既有檔案——半成品覆蓋掉上一版可用的二進位是最難查的狀態。
mv "$APPLIANCE_DIR/.build/duduclaw.new"      "$APPLIANCE_DIR/.build/duduclaw"
mv "$APPLIANCE_DIR/.build/duduclaw-sysd.new" "$APPLIANCE_DIR/.build/duduclaw-sysd"
echo "[bins] 完成："
ls -la "$APPLIANCE_DIR/.build/duduclaw" "$APPLIANCE_DIR/.build/duduclaw-sysd"
