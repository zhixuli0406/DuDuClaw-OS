# GCP Yocto builder（2026-10-13 建立）

Owner 拍板：DuDuClaw OS 的 Yocto builder 改跑在 GCP（取代 Mac Docker Desktop arm64 builder）。

## VM

| 項目 | 值 |
|---|---|
| 名稱 | `duduclaw-os-builder` |
| 專案／區域 | `louis-460302` / `asia-east1-b` |
| 機型 | `n2-standard-16`（16 vCPU / 64 GB，無 swap） |
| 開機碟 | Ubuntu 24.04 LTS（`ubuntu-2404-noble-amd64-v20261009`），600 GB `pd-balanced`，root 581 GB 可用 |
| 網路 | default VPC；內部 IP 10.140.0.3；**臨時外部 IP**（stop 後會換）——只用於對外抓取（GitHub、Docker Hub、Yocto mirrors），專案無 Cloud NAT。防火牆沿用 default（22/icmp/3389 對外，3389 VM 上沒有服務聽）；VM 上沒有開任何服務 |
| 標籤 | `purpose=duduclaw-os-build` |
| Shielded VM | Secure Boot + vTPM + integrity monitoring |
| 登入 | `gcloud compute ssh duduclaw-os-builder --zone asia-east1-b --project louis-460302`（使用者 `lizhixu`，uid 1001） |

建立指令：

```bash
gcloud compute instances create duduclaw-os-builder \
  --project louis-460302 --zone asia-east1-b \
  --machine-type n2-standard-16 \
  --image-family ubuntu-2404-lts-amd64 --image-project ubuntu-os-cloud \
  --boot-disk-size 600GB --boot-disk-type pd-balanced \
  --network default \
  --labels purpose=duduclaw-os-build \
  --shielded-secure-boot --shielded-vtpm --shielded-integrity-monitoring
```

## VM 上的設定

```bash
# Docker Engine（官方 apt repo）
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu noble stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list
sudo apt-get update && sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo usermod -aG docker $USER          # Docker 29.9.0

git clone https://github.com/zhixuli0406/DuDuClaw-OS.git ~/DuDuClaw-OS   # 7101142

cd ~/DuDuClaw-OS
docker build -f meta-duduclaw/docker/Dockerfile.yocto-builder -t duduclaw-yocto-builder meta-duduclaw/docker
# → amd64 image，Dockerfile 不必改（沒有寫死 arm64；只是註解提到 Apple Silicon）

# 快取放 VM ext4（大小寫敏感，普通目錄即可）
sudo mkdir -p /srv/yocto-cache/downloads /srv/yocto-cache/sstate-cache

# uid 對齊：VM 使用者是 uid 1001，容器內 yocto 是 uid 1000（= VM 的 ubuntu 群組）。
# Linux bind mount 不像 Docker Desktop 會轉換擁有者，所以把工作樹與快取交給 1000:1000，
# 並讓 lizhixu（屬於 gid 1000 群組）可寫：
sudo chown -R 1000:1000 /srv/yocto-cache ~/DuDuClaw-OS
sudo chmod -R g+w /srv/yocto-cache ~/DuDuClaw-OS
sudo find /srv/yocto-cache ~/DuDuClaw-OS -type d -exec chmod g+s {} +
git config --global --add safe.directory /home/lizhixu/DuDuClaw-OS
chmod o+x /home/lizhixu

docker volume create duduclaw-yocto-tmpdir
docker run -d --name duduclaw-yocto --restart unless-stopped \
    -v /home/lizhixu/DuDuClaw-OS:/workspace \
    -v /srv/yocto-cache:/yocto-cache \
    -v duduclaw-yocto-tmpdir:/yocto-vmfs \
    -w /workspace \
    duduclaw-yocto-builder -c "sleep infinity"
docker exec -u 0 duduclaw-yocto chown 1000:1000 /yocto-vmfs   # 新 named volume 預設 root:root
```

驗證（2026-10-13）：

```
$ docker exec -u 1000 duduclaw-yocto id
uid=1000(yocto) gid=1000(yocto) groups=1000(yocto)
$ docker exec -u 1000 duduclaw-yocto kas --version
kas 5.5 (configuration format version 23, earliest compatible version 1)
$ kas checkout meta-duduclaw/kas/duduclaw-os.yml && kas shell ... -c "bitbake --version"
BitBake Build Tool Core version 2.18.0   (/workspace/bitbake/bin/bitbake)
```

建立當下 `kas checkout` 只抓了 layer repo（gitignored）。第一次真正的建置是下面「v0.3.0 建置紀錄」那一輪。VM 上從頭到尾沒有任何簽章金鑰或其他 secret。

## 在 Linux builder 上要調整的地方

- **簽章拆到 Mac（已落地，PR #11）**：`release-os.sh package --no-sign` 在 VM 上做 smoke 閘門、壓縮、sha256、manifest；`artifacts/os/v<版本>/<機型>/` 複製回 Mac 後 `release-os.sh sign` 先核對 `.sha256` 與 manifest 的 sha256／大小，再 `minisign -S` 並以釘住的公鑰自驗。金鑰（`~/.minisign/duduclaw-os-release.key`）不上 VM。
- `check_host_disk_free` 用 `df -Pk "$HOME"`，Linux 上可以跑，但它檢查的是 `$HOME` 所在磁碟；這台 named volume、快取、工作樹都在同一顆 root 碟，所以剛好有意義。註解裡的 Docker.raw 說法不適用。
- `shasum` 在 Ubuntu 由 perl 提供（存在）；`stat -f%z || stat -c%s` 已有 Linux fallback。
- **`serial1.yml` 是給 8 GB VM 的 -j1 節流**，release-os.sh 預設會串上。已另做 `meta-duduclaw/kas/release-linux-builder.yml`（只關 SPDX，`BB_NUMBER_THREADS` 8、`PARALLEL_MAKE` `-j 8`），以 `DUDUCLAW_OS_KAS_OVERLAY=` 指定，`build`／`smoke`／`package` 都帶同一個值。實測記憶體最低剩 30 GB 可用，還有餘裕。
- 無 swap；若 OOM 再考慮加 swapfile。

## 費用（估算，非 gcloud 報價）

依 GCE 公開牌價推估（asia-east1 約比 us-central1 貴 15%）：

- n2-standard-16：約 US$0.88–0.90／小時
- 600 GB pd-balanced：約 US$66／月 ≈ US$0.09／小時（停機也照算）
- 臨時外部 IPv4：約 US$0.005／小時（停機時釋放不收）
- **運轉中合計約 US$1.0／小時；停機只剩磁碟約 US$0.09／小時（約 US$66／月）**
- 下載是 ingress 免費；把 wic 拉回 Mac 算 internet egress（約 US$0.12／GB）。

## 停機／刪除

```bash
gcloud compute instances stop   duduclaw-os-builder --zone asia-east1-b --project louis-460302   # 停算力，保留磁碟
gcloud compute instances start  duduclaw-os-builder --zone asia-east1-b --project louis-460302   # 容器 restart=unless-stopped 會自動起來
gcloud compute instances delete duduclaw-os-builder --zone asia-east1-b --project louis-460302   # 連同開機碟一起刪（快取/sstate 全失）
```

## v0.3.0 建置紀錄（2026-10-13～14）

內嵌平台 v1.73.1、`duduclaw-shell` 1.65.3、OS `VERSION` 0.3.0（PR #11，merge `4db8ee7`）。產物矩陣同 v0.2.0：兩機型 × wic.zst＋基礎版 ISO＋桌面版 ISO，共 20 個資產。Release：<https://github.com/zhixuli0406/DuDuClaw-OS/releases/tag/v0.3.0>。

### 前置

- 兩個 gitignored 的大檔不在 clone 裡，要從 Mac 傳上去：`duduclaw-ai-runtimes-20260905.tar.zst`（606 MB，附 `.sha256`）與 `duduclaw-flatpak-offline-repo.tar.zst`（932 MB）。`gcloud compute scp` 傳 1.5 GB 約 1 分鐘，VM 上 sha256 與 Mac 一致。
- `sync-platform.sh 1.73.1` 對新 worktree 會先 `npm run build` dashboard，worktree 要先 `npm ci`。
- 平台 1.63.0→1.73.1 之間 workspace 有變，`duduclaw-cli/refresh-src.sh` 跟著改：成員閉包重算（少 `duduclaw-cli-worker`、`duduclaw-desktop`，多 `duduclaw-db`）、補 `fixtures/`（gateway 非測試程式碼 `include_str!`）與 `vendor/`（根 `[patch.crates-io] serenity`）。
- cli 的 crates.io 集合大換，`bitbake -c update_crates duduclaw-cli` 在 VM 上跑（冷啟動要先建 python3-native，約 15 分鐘）。它只產生 crates.io 項目；新出現的 git 依賴 `ucci`（`duduclaw-inference`，crate 在該 repo 的 `rust/`）改在 recipe 裡加 `git://…;name=ucci;subpath=rust;destsuffix=ucci`，並把 `CARGO_LOCK_PATH` 指到快照根目錄（預設值找 `crates/duduclaw-cli/Cargo.lock`，不存在會 fatal）。

### 時間軸（UTC）

| 時間 | 事件 |
|---|---|
| 10-13 14:17 | VM 開機（`uptime -s`） |
| 15:27 | 冷建置開始：qemux86-64 `duduclaw-image-appliance`，8914 個 task |
| 18:40 | `duduclaw-cli` 開始 do_compile（recipe 固定 cargo `-j 1`，772 個 crate 序列編） |
| 20:22–21:00 | `duduclaw_gateway` 單一 rustc 約 40 分鐘（RSS 約 9 GB） |
| 21:00–21:45 | `duduclaw_cli` crate 約 45 分鐘 |
| 21:52 | qemux86-64 appliance 完成（冷建置 6 小時 25 分，其中約 3 小時是 cli 序列編譯） |
| 22:03 / 22:38 | qemux86-64 live ISO（10 分）／live-desktop ISO（35 分，大半是 payload `zstd -19 --long=27`） |
| 23:01 / 23:10 / 23:44 | genericx86-64 appliance（22 分，兩機型同為 x86-64-v3 tune，只重建 kernel 與映像）／live／live-desktop |
| 23:44–00:29 | smoke（qemux86-64 wic，65 秒到 login）＋兩機型 `package --no-sign`（每個 wic 的 zstd -19 約 15 分）＋ISO 複製 |
| 00:10–00:40 | 逐機型拉回 Mac（4.2 GB 約 1 分鐘）→ `sign` → 上傳到 draft release → GitHub digest 比對 → 刪本機大檔；00:40 轉正式 |
| 00:30–00:45 | 加測兩個 qemux86-64 ISO 開機（各約 125 秒到 `login: root (automatic login)`，kiosk 啟動） |
| 00:45–01:10 | 從 Release 串流重新下載六個映像資產（不落地），以發布的 `.minisig`／`.sha256` 驗證，全部通過 |
| 01:12 | VM 內 `sudo shutdown -h now`；約 20 秒後外部 22 埠不再回應 |

峰值：記憶體最低剩 30 GB 可用（64 GB 機），root 碟最多用到 133 GB（581 GB）。

### 踩到的坑

1. **driver 連跑兩個 `release-os.sh build` 被並行防呆擋下**：`kas build` 結束後 bitbake-server 還會留幾秒，下一個 build 的 `check_builder_idle` 看到它就拒絕（防呆是對的）。driver 每次 build 前先輪詢到容器裡沒有 bitbake/kas 再開始。
2. **ISO 開機測試誤判失敗**：沿用 `release-os.sh` smoke 的失敗樣式 `failed with error`，被 kernel 的 `cfg80211: … regulatory.db failed with error -2`（無害）命中，QEMU 被提早砍掉。改成只認 `runqemu - ERROR|Shell returned non-zero` 後兩個 ISO 都通過。`release-os.sh` 本身的 smoke 迴圈也有同一個樣式；這次 wic 在那行訊息出現前就到了 login，所以沒觸發，但它是潛在的假失敗（fail closed，不會放行壞映像），待修。
3. **gcloud 憑證中途失效**：使用者帳號 session 過期（Workspace 短 session 政策），改啟用的部署 SA `xuanhe-deployer` 沒有 Compute 角色（只有 run／cloudbuild／storage／iam.serviceAccountUser／artifactregistry），`gcloud compute ssh` 被拒。之後改用 gcloud 先前放進 VM 的 `~/.ssh/google_compute_engine` 金鑰直接 SSH 外部 IP（host key 用 `google_compute_known_hosts` 裡該 VM 的 `compute.<id>` 項驗證）繼續工作。
4. **VM 刪不掉**：同上，SA 沒有 `compute.instances.delete`，使用者帳號與 ADC 都過期。建置證據收回後從 VM 內 `sudo shutdown -h now` 停機（停算力，開機碟仍計費約 US$0.09／小時）。GCE 端的實例狀態（應為 TERMINATED）因同樣沒有權限而無法用 gcloud 查證，只確認了外部 SSH 不再回應。**刪除要 owner 重新 `gcloud auth login` 後執行**：
   `gcloud compute instances delete duduclaw-os-builder --zone asia-east1-b --project louis-460302 --quiet`
5. cargo `-j 1`（`duduclaw-cli` recipe，為 12 GB Mac builder 設的 OOM 防護）在 64 GB 機上是最大瓶頸：cli 序列編譯約 3 小時，期間其他 CPU 大多閒置。下次可以讓 overlay 能放寬它（目前 recipe 寫死 append）。

### 費用（估算）

VM 運轉約 10.9 小時（14:17 → 01:12 停機），以 US$1.0／小時估約 US$11；egress 約 8.7 GB 下載到 Mac，約 US$1。停機後到刪除前，磁碟每小時約 US$0.09。

