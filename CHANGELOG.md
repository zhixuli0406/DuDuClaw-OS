# Changelog

DuDuClaw OS 所有值得記錄的變更都在這裡。版號與 DuDuClaw 平台**獨立**（見
`VERSION` 檔），格式依 [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
與 [Semantic Versioning](https://semver.org/)。逐波的 bring-up 歷程（Y1–Y20）
在 git log 與 `wiki/impl/`。

## [Unreleased]

### Added
- **殼 crate 搬入本 repo `crates/`**（2026-09-29，平台功能盤點 S16-B）：`duduclaw-comp`（smithay compositor）、`duduclaw-shell`（gpui 殼）、`duduclaw-native-gui`（shell 的 sibling path 依賴）整組自平台 repo 搬入，維持各自的 detached `Cargo.lock` 與版本（1.65.1，暫不隨 OS `VERSION` 改，版本政策待定），**不**合併成一個 workspace——bitbake recipe 就是照「兩個 destsuffix 同層」快照的。`duduclaw-comp`／`duduclaw-shell` 的 `refresh-src.sh` 改從本 repo `crates/` 取源（覆寫變數 `DUDUCLAW_OS_SRC_ROOT`，不再吃 `DUDUCLAW_CLI_SRC_ROOT`）；`duduclaw-cli` 的 `refresh-src.sh` 偵測改錨定 `crates/duduclaw-cli/Cargo.toml`，避免把本 repo 新的 `crates/` 誤認成平台 workspace；`scripts/sync-platform.sh` 拆成平台 recipe（cli／sysd，改名跟平台版本）與 OS 自有 recipe（comp／shell，只重新快照、PV 不動）兩組，`docs/guides/platform-sync.md` 同步。連帶搬入 `.github/workflows/native-gui-desktop-release.yml`（tag `native-gui-v*`，平台 repo 從未打過此 tag）與 `scripts/desktop/bundle-native-gui-macos.sh`／`sign-notarize-macos.sh`。`.gitignore` 加 `crates/*/target/`。**版本政策（2026-09-29 拍板）**：三個 crate 維持自己的版本線（目前 1.65.1），只在程式碼真的變動時手動 bump，`release-os.sh` 一律不 bump（與 `VERSION` 檔同一套教義）；`release-os.sh audit` 新增「OS-owned crates」區塊，列出三個 crate 的 manifest 版本並檢查 detached `Cargo.lock` 的自身／sibling 項是否與 manifest 一致（不一致會讓 `cargo build --frozen` 的 bake 死掉），平台 PV 漂移檢查則只剩 `duduclaw-cli`／`duduclaw-sysd` 兩個平台 recipe。已知殘留：`crates/duduclaw-native-gui/src/screens/governance.rs` 仍呼叫平台同日移除的 `governance.list` RPC、`screens/security.rs` 仍渲染已移除的 `credential_proxy`／`mount_guard` 欄位（缺欄位退成零值不 panic）；本機缺 Xcode Metal Toolchain 無法編譯驗證，未盲改，列為待辦。
- **App 相容層文件搬入**：`docs/guides/app-compat.md`（en／zh-TW／ja-JP）自平台 repo 搬入。平台的 `duduclaw compat` 子命令族同日改為 Cargo feature `app-compat`（平台二進位預設不含），本 image 需要它：`duduclaw-shell` 會 spawn `duduclaw compat windows-vm app`，`compat.d/windows-vm.toml` 也以它為 `entrypoint`，所以 `duduclaw-cli_1.63.0.bb` 的 `CARGO_BUILD_FLAGS` 準備了 `--features app-compat` 的替換行（**先註解掉**：目前 vendored 的 cli 快照還沒有這個 feature，開了會死在 unknown feature；快照仍無條件編出 compat，image 不受影響）。**下次 `sync-platform.sh` 對齊到含此 feature 的平台版本時必須換成帶 `app-compat` 的那行**，否則對齊後的 image 會少掉 `duduclaw compat`。
- **正式站部署到 Cloud Run**：`deploy/cloudrun/`（nginx 靜態容器：CSP、快取標頭、`mjs`／`avif`／`wasm` MIME）與
  `scripts/deploy-cloudrun.sh`（建置 `_site/` 後以 deployer SA `gcloud run deploy --source`）；服務 `duduclaw-os-site`
  （`louis-460302`／`asia-east1`），網域 `os.duduclaw.dudustudio.monster`（domain mapping＋Cloud DNS CNAME 一次性設定）。
  `og:image` 改為正式網域絕對網址；文件站 `SITE_URL` 由 deploy 腳本帶入。
- **文件站 `docs-site/`（Astro 7 ＋ Starlight 0.42，發布在主站的 `/docs/`）**：把本 repo 的
  `docs/**` 與根目錄 `README.md`／`README.en.md`／`CHANGELOG.md`／`SECURITY.md`，加上平台 repo
  的公開白名單（`docs/` 底下的 `features`／`guides`／`architecture`／`spec`／`api`，其餘如
  `todo`／`rfc`／`adr` 一律不讀），組成 zh-TW（預設）／en／ja 三語系的靜態站，搜尋用
  Pagefind。**站內任何位置都不連 GitHub**：關掉 editLink、header 不放 GitHub 圖示、內文指向
  非公開檔案的連結一律降級成純文字（不留 GitHub 備援連結），只有指向 Releases 的連結保留。
  主題以 CSS 變數對接 `website/assets/css/site.css` 的既有 token（`#f3f3f3`／`#0c0c0e` 底、
  MDS 藍 `#2171cc`／`#4390ee`、Inter＋Noto Sans TC、JetBrains Mono、10–12px 圓角），緋紅
  `#e5484d` 只出現在 logo。`scripts/sync-docs.mjs` 每次建置前重建內容樹（注入 frontmatter、
  改寫相對 `.md` 連結、複製引用圖檔、印出統計），零額外相依、可重複執行。
- **`scripts/build-site.sh`**：本機把 `website/` ＋ `docs-site/dist` 組成 `_site/`（文件放
  `_site/docs/`），`SKIP_DOCS=1` 可重用既有 `dist`。
- **`.github/workflows/pages.yml`**：push 到 main 時 checkout 兩個 repo（平台以 sparse
  checkout 只取 `docs`）、建置文件站、組出 `_site/` 並發布到 GitHub Pages。
  `DOCS_BASE` 由 `configure-pages` 的 `base_path` 推出，因此自訂網域／使用者頁（`/docs`）
  與專案頁（`/<repo>/docs`）共用同一份設定；`docs-site/base.mjs` 是唯一的正規化點。
  網站主體維持零建置，只有文件站需要 Node。

### Changed
  （2026-09-09 補：Pages 尚未啟用時 `configure-pages` 會失敗，故改為僅 `workflow_dispatch` 手動觸發；正式站走 Cloud Run。啟用 Pages 後再恢復 push 觸發。）
- **`README.md`／`README.en.md`／`docs/README.md`：連到平台 repo 使用者文件的連結，從 GitHub
  blob 連結全部改連文件站** `https://os.duduclaw.dudustudio.monster/docs/...`（值班機、桌面版、
  OS 快捷鍵、硬體需求、app 相容層、mkosi 安裝指南六處）；GitHub 上只留 repo、Releases、Issues
  與 LICENSE 連結，與文件站「站內不連 GitHub」的原則對齊。
- **`docs/README.md`**：「Start here」補上正式站＋文件站連結；「Component references」補上
  `../website/README.md` 一列；使用者文件表格標題改為「發佈在文件站」，不再稱「currently
  published from the platform repo」。
- **`README.md`／`README.en.md`／`meta-duduclaw/README.md`：信任鏈與版本敘述全面更新到 v0.2.0**
  ——版本徽章、狀態列、需求對照表、信任鏈段落、Quick start 的 Secure Boot 提示、
  `duduclaw-genericx86-64` 驗證現況，原本綁死在「v0.1.0 未啟用／v0.1.0 只做過設定稽核」的
  措辭改為「截至 v0.2.0 仍未啟用／只做過設定稽核」，並補上 `scripts/release-os.sh build`
  目前預設只疊加 `kas/serial1.yml`（release overlay，不含 `sb-signing.yml`／`tpm-luks.yml`）
  這個先前沒寫清楚的細節。`meta-duduclaw/README.md` 的映像角色表格與 Status 一節同步更新，
  不再把仍持續適用的敘述（安裝器 ISO 的角色、三種產物形式）錯釘在 v0.1.0 單一版本上。
- **OS 版號說明與稽核對齊拆 repo 後流程**：`duduclaw-platform-version.inc` 和 distro 註解
  改指向 `scripts/sync-platform.sh`；`release-os.sh audit` 納入已存在的 `duduclaw-shell` recipe，
  不再錯稱它尚無 Yocto recipe，且顯示已展開的完整 `DISTRO_VERSION`。
  OS `VERSION` 仍獨立於內嵌平台版號。

### Fixed
- **`SECURITY.md`「Release Artifact Security」敘述漏掉第三種發布產物、且誤植兩種 ISO 都有
  `.manifest.json`**：改為正確描述每機型三種產物（wic 桌面版、installer 基礎版 ISO、
  installer-desktop 桌面版 ISO），三者皆附 `.sha256`／`.minisig`，但 `.manifest.json` 只有
  wic 才有（以 `artifacts/os/v0.2.0/` 下實際產物核對）。

## [0.2.0] - 2026-09-09 — 平台快照同步 v1.63.0×sync-platform 一鍵同步×release-os smoke 修復

### Added
- **`scripts/sync-platform.sh <平台版本>`（決策 B：與平台同步發版節奏、OS 保留 0.x）**：一次做完四份快照 refresh、`duduclaw-platform-version.inc` bump 與四個 recipe 改名（含引用註解）、crates.io 依賴集合比對（有變就要求重生 `*-crates.inc`，exit 2）、CHANGELOG 樣板；`--check` 只跑防呆。防呆項：平台 checkout 版本不符、平台有未提交變更（`--force` 放行）、detached lock 與 manifest 版本不一致、相依表格版本被 bump 改壞、dashboard dist 過期（預設自動 `npm run build`）。在 1.62.0 的 HEAD worktree 上實測一次 1.62.0→1.63.0，產出與手動對齊完全一致。文件：`docs/guides/platform-sync.md`。
- **`duduclaw-shell/refresh-src.sh` 拒絕 vendor 版本不一致的 Cargo.lock**：快照的 lock 裡 `duduclaw-shell`／`duduclaw-native-gui` 的版本若與各自 Cargo.toml 不符就停下並印出修法（`cargo metadata --offline`）。2026-09-08 fix14 烤製踩到：平台 bump 後 lock 的 native-gui 項未同步，`cargo build --frozen` 因此去要 zed 的 git 來源而離線失敗。
- **`scripts/release-os.sh` 烤前主機磁碟防呆**：新增 `check_host_disk_free`，`$HOME` 所在卷可用空間低於
  `DUDUCLAW_MIN_HOST_FREE_GB`（預設 30）就拒絕開烤。Docker Desktop 的 `Docker.raw` 是稀疏檔，主機卷滿時
  VM 內寫入失敗、Docker 引擎直接崩潰（2026-09-06 在 `do_image_ext4`／`do_image_wic` 階段連續三次），
  一次 appliance 烤製尖峰需要約 25 GB 新空間。
- **AI runtime 全部進映像（WP-F）**：新 recipe `duduclaw-ai-runtimes` 把十套廠商
  coding CLI 打包進 `/opt/duduclaw/runtimes`，`/usr/bin` 以 `claude`／`codex`／
  `gemini`／`qwen`／`kimi`／`copilot`／`grok`／`agent`（＝`cursor-agent`）／
  `cursor-agent`／`opencode`／`vibe` 十一個 symlink 指向同一支 dispatcher
  （`/usr/libexec/duduclaw/duduclaw-runtime-exec`，負責設定 `NODE_PATH`／`PATH`／
  `PYTHONPATH` 與 `HOME`）。payload 是宿主端 `gen-ai-runtimes-bundle.sh` 在
  `linux/amd64` 容器裡產生的 `.tar.zst`（606 MB 壓縮／1.9 GB 解開，已 gitignore），
  每個元件的版本、來源 URL、sha256 都寫在映像內的
  `/opt/duduclaw/runtimes/MANIFEST.txt`，授權逐項記在 recipe 的
  `files/LICENSE-MANIFEST`。**Kiro CLI 刻意未內建**（解開 1039 MB，佔掉 root 槽
  剩餘空間的 46%），也刻意不放 `/usr/bin/kiro-cli` 殘根——平台的 runtime 偵測看檔案
  存在與否，殘根會讓 dashboard／OOBE 誤報「已安裝」；安裝指令由平台 runtime catalog
  顯示（附 Kiro 條款警語），裝到 `/data/duduclaw/.local/bin` 後 gateway 自會偵測到。
  四套非開源元件（Claude Code、Copilot、Grok、Cursor）以
  `LICENSE_FLAGS` 擋住，由 `duduclaw-os.conf` 明文接受。
- **Node.js 進桌面版映像**：`nodejs` ＋ `nodejs-npm`（meta-oe `nodejs_22.23.2`），
  透過新的共用 payload `duduclaw-image-runtimes.inc`，只被
  `duduclaw-image-appliance` require——不放進 `desktop.inc`，避免安裝器 ISO 也扛
  2 GB 的 agent。
- **本機推理：llama.cpp**：新 recipe `llama-cpp` 0.4.0（上游 semver tag，SRCREV
  釘住 `5266f24`）建出 `llama-server`／`llama-cli`，`GGML_NATIVE=OFF` 走 distro 的
  x86-64-v3 tune；新 recipe `duduclaw-llama-server` 提供
  `duduclaw-llama-server.service`（`EnvironmentFile=-/data/duduclaw/llama-server.env`、
  沒有模型就 condition-fail 而非重啟迴圈、只綁 `127.0.0.1`）。**模型權重不進映像**，
  由後台下載到 `/data/duduclaw/models`。
- **`compat.d/llamafactory.toml`**：LLaMA-Factory LlamaBoard 微調工作台的 runner
  宣告（docker、127.0.0.1:7860），明示需要 NVIDIA 獨顯與 container toolkit——
  參考機種 N305／8845HS 只有內顯，跑不動，這一列存在就是為了講清楚為什麼。
- **`docs/guides/ai-runtimes.md`**：內建了哪些 runtime、哪些沒有與為什麼、憑證
  存在哪裡、本機模型怎麼開、bundle 怎麼重新產生、root 槽預算。

### Changed
- **平台快照全面同步到 v1.63.0（gateway 跟主 repo 對齊）**：`duduclaw-cli`／`duduclaw-comp`／`duduclaw-sysd` 快照重新 vendor（shell 已於 73ab67b 更新），`duduclaw-platform-version.inc` 1.62.0→1.63.0（連動 `DISTRO_VERSION`、os-release `VERSION_ID`、UKI 檔名 `duduclaw-os_1.63.0-y1-bringup.efi`、A/B loader 項），四個 recipe 檔名改為 `_1.63.0.bb`；dashboard `dist/` 依平台 111d748b 重建後才 vendor。帶進的平台變更：帳號憑證硬化（真探測取代 auth status 假陽性、auth-dead 退避、壞憑證載入排除、寫入前驗證、認證失效告警，b787c48a）、dashboard 帳號卡憑證狀態徽章＋新增帳號對話框顯示伺服器真實錯誤（111d748b）、Launcher 頁腳「⌘K 隨時喚起」（50b5acc0）。四份快照的 crates.io 依賴集合與 1.62.0 相同，`*-crates.inc` 未動。OS 自己的 release 版本（`VERSION` 0.1.0）不受影響。
- **root A/B 槽 7168 → 8192 MiB**（`duduclaw-image-appliance.bb`）：容納上述 AI
  payload。8192 是天花板不是階梯——它等於平台 repo `os_update.rs` 的
  `MAX_ROOT_BYTES`，該常數在同一波（WP-B）升到 9 GiB；在那之前對本映像做
  `device.update_apply` 會被 8589934592-byte ceiling 擋下，兩個改動必須成對。
  `duduclaw-verity.bbclass` 與 `duduclaw-journald` 內殘留的 7168 字面值一併加註
  說明（那是 fallback 預設，不是本映像的尺寸斷言）。
- **gateway 的真 `$HOME` 移到 `/data/duduclaw`**：新 drop-in
  `duduclaw-gateway.service.d/20-home.conf`（`duduclaw-firstboot` 提供）。
  十家 CLI 的 OAuth token／API key 都是從 `$HOME` 解析路徑的，先前會落在
  `/root`——出貨映像的 root 是唯讀、且每次 A/B 更新整槽覆寫。
  `duduclaw-firstboot-provision.sh` 同時把 `/data/duduclaw` 收成 0700 root
  （該目錄現在裝的是十家廠商的活憑證，`duduclaw-kiosk` 不該讀得到）。
- **Windows RemoteApp 登錄檔搬到 `/data/system/windows-vm/apps.toml`**：gateway 家目錄
  收緊為 `0700` 後，kiosk 殼（`duduclaw-shell`）讀不到原本的
  `/data/duduclaw/windows-vm/apps.toml`，釘選的 Windows 程式會從啟動器無聲消失。
  `duduclaw-data-binds` 的 tmpfiles 新增 `/data/system/windows-vm`（root 0755），
  `20-home.conf` 與 root 的 `duduclaw-home-profile.sh` 都設
  `DUDUCLAW_WINDOWS_VM_APPS_DIR=/data/system/windows-vm`（平台 CLI 同波新增的覆寫），
  殼的讀取路徑同步改到新位置；既有機器由遷移腳本 `1788717600.sh` 搬檔（新位置已有檔則
  不覆寫）。`compose.yaml` 與 VM 儲存仍在 `/data/duduclaw/windows-vm`。

- **`duduclaw-flatpak-setup` recipe**：`/etc/flatpak/installations.d/10-duduclaw-data.conf`（名為 `data`
  的 Flatpak 安裝區，路徑 `/data/flatpak`，殼與 polkit 規則都指向它）＋開機 oneshot
  `duduclaw-flatpak-setup.service`：建目錄、寫沙盒環境覆寫、把映像內建的離線倉庫註冊為
  `flathub-offline`（`file:///opt/duduclaw-flatpak-offline-repo`，同 kiosk-verify 的 `--no-gpg-verify` 理由）、
  再嘗試加 `flathub`（無網路就下次開機重試）。從凍結的 mkosi 線移植並補上離線倉庫。
- **gateway 的 `[codrive]` 設定**：首次開機 provision 的 `config.toml` 範本補上
  `socket_path`／`token_path` 指向 `/run/duduclaw-kiosk/duduclaw-codrive.{sock,token}`；
  已 provision 的機器由 `/data` 前向遷移 `1788591433.sh` 補上（有 `[codrive]` 就不動）。
- **文件制度對齊平台 repo**：新增 `CLAUDE.md`（專案守則＋「Documentation
  Classification & Placement」：L1 Public `docs/<type>/`／L2 Internal `wiki/`／
  L3 Confidential gitignored 三級分類、type 分類表、跨 repo 指標慣例、vendored
  快照內的文件不在本 repo 修改）、`CONTRIBUTING.md`、`SECURITY.md`（回報管道、
  範圍、發布產物驗簽方式）、`docs/README.md`（公開文件索引）與 `README.en.md`。
- `.gitignore` 預留 `commercial/`、`research/` 兩個 L3 樹（與平台 repo 同慣例）；
  設計文件若日後複製進來只能落在這裡。

- **桌面版安裝器 ISO recipe `duduclaw-image-live-desktop`**：與 `duduclaw-image-live`
  共用同一個 live 環境與圖形安裝精靈，差別只在寫入的安裝素材是桌面版
  `duduclaw-image-appliance`（原本只有寫入基礎版 `duduclaw-image-ab` 的 ISO）。
  `duduclaw-image-live.bb` 重構為以 `DUDUCLAW_INSTALL_PAYLOAD_IMAGE` 一個變數決定
  payload（跨 image 相依、wic 路徑、fallback glob、錯誤訊息全部由它推導），預設值不變；
  ISO 內多一個 `duduclaw-install.edition` 標記檔，安裝器會印出安裝素材版本。
  產物命名 `duduclaw-os-installer-desktop-<machine>-v<ver>.iso`；qemux86-64 版以
  `runqemu … iso ovmf slirp` 光碟開機驗證到 root autologin 後，簽章補進 v0.1.0 release
  （2026-09-04；安裝精靈實際寫碟流程未在此輪重跑）。
- **README 改以繁體中文為主**（英文版移至 `README.en.md`），章節對齊平台 repo：
  目錄／為什麼／映像裡有什麼／信任鏈／快速開始／建置／repo 結構／文件／授權。
  補上兩式產物的差異（`.wic.zst`＝`duduclaw-image-appliance` 完整桌面；`.iso`＝
  live 安裝器，寫入無頭的 `duduclaw-image-ab`）、v0.1.0 的驗簽與燒錄步驟，以及
  「真機尚未開機驗證」的狀態。
- **`meta-duduclaw/README.md` 改寫為精簡的 layer 參考**（layout、各 image 的角色、
  builder 容器與 `kas build`、QEMU 開機、machine 別名陷阱）；原本 482 行的
  bring-up 敘事原文不動搬到 `wiki/impl/meta-duduclaw-bring-up-notes-2026-08.md`。
- **重新歸檔 L2 文件**：`meta-duduclaw/REAL-HW-CHECKLIST.md` →
  `wiki/eval/real-hw-acceptance-checklist-y6-3-2026-08-26.md`（加註前提已過時：
  IME 自 Y7 起已在 image、v0.1.0 已有 A/B＋唯讀 root＋Secure Boot＋安裝器 ISO）；
  layer 根目錄的五份 QEMU／bitbake 證據 log → `wiki/reports/bring-up-evidence/`。
  recipe、kas 設定與 `duduclaw-kiosk.service` 內的註解指標同步改指新路徑。
- `appliance/README.md` 頂部加註「已凍結」與跨 repo 指標說明（`crates/` 指平台
  repo；`commercial/docs/`、`research/` 指維護者私有設計樹）。
- 本檔改以繁體中文撰寫，對齊平台 repo 的 CHANGELOG。
- **README／SECURITY 修正信任鏈與版本敘述（拆開 v0.1.0 發布 wic 查證）**：兩槽 UKI
  與 systemd-boot 皆無簽章、GPT 無 verity 分割、rootfs 無 TPM 套件，因為 `release-os.sh
  build` 只用基本 kas 設定，未帶 `sb-signing.yml`／`tpm-luks.yml` overlay。文件改為
  「layer 已接好、v0.1.0 發布映像未啟用」，快速開始改為「Secure Boot 關閉」開機。
  另修正安裝器 ISO 的敘述：v0.1.0 寫入的 `duduclaw-image-ab` 並非無頭，它有同一個
  桌面殼與 gateway，只是沒有應用層、app 相容層、唯讀 root 與防火牆（基礎版）。
- **README 補上桌面環境**：先前把整個 OS 寫成無頭值班機，漏掉自家 compositor／殼（首頁、視窗切換、鎖定畫面、控制中心、Cmd+K 交辦列）、首次設定精靈、IME／音訊／XWayland、app 相容層（Flatpak／Bottles／Windows VM／Waydroid）。首段改為「AI 原生住民的桌面作業系統，另有無頭版」，新增「桌面環境」一節，並標清兩式產物的差別：整碟 `.wic.zst`＝桌面版、安裝器 `.iso`＝無頭版；桌面版無螢幕時的行為尚未在真機定義。


### Fixed
- **`release-os.sh smoke` 在 rm_work 的樹上起不來、起不來還會等滿 timeout**：runqemu 需要 `qemu-helper-native` 的 recipe sysroot，rm_work 把它清掉後 runqemu 立刻以「Native sysroot directory … doesn't exist」退出，smoke 卻繼續輪詢到 timeout（20 分鐘）。現在啟動前先 `bitbake -C addto_recipe_sysroot qemu-helper-native`（`-C` 強制：stamp 在 rm_work 後還在、目錄卻沒了，`-c` 會判定不用重做），`duduclaw-os.yml` 把 `qemu-helper-native` 加進 `RM_WORK_EXCLUDE`（否則同一趟 rm_work 又把剛補好的 sysroot 刪掉），輪詢看到 `runqemu - ERROR` 立即失敗並印 log。
- **`release-os.sh` 的 builder 並行檢查與 smoke 的 QEMU 檢查在「沒東西在跑」時把整個腳本殺掉**：兩處 `docker exec … pgrep …; rc=$?` 在 `set -e` 下，pgrep 沒比對到（正常的閒置狀態）回 1 就直接結束腳本，`rc` 從未被讀到——`smoke` 每次都在印出橫幅後靜默 exit 1（2026-09-08 對 v1.63.0 appliance 跑 smoke 時發現）。改為 `|| rc=$?`。
- **`duduclaw-sysd/refresh-src.sh` 產出可重現**：flattened Cargo.toml 的註解改標平台 commit 而非產生時間；先前每跑一次 refresh 就改到 Cargo.toml、`file://` checksum 變了，sysd 就白白重編一次，`sync-platform.sh` 也因此無法「再跑一次沒差異」。
- **`duduclaw-cli` recipe 限制 cargo 單一 rustc（`CARGO_BUILD_FLAGS:append = " -j 1"`）**：`cargo.bbclass` 不帶 `-j`，cargo 照 nproc 開 rustc，`PARALLEL_MAKE`／`BB_NUMBER_THREADS` 都管不到；gateway lib 與 cli 兩支大 rustc 並行在 12 GB builder 上被 SIGKILL（cargo exit 101、無診斷），2026-09-08 fix14 連續兩次。
- **shell 快照更新至平台 v1.63.0（僅 `duduclaw-shell`／`duduclaw-native-gui` 兩個 crate）**：帶入平台 50b5acc0——Launcher 底部提示「Super 鍵隨時喚起」改為真實綁定「⌘K 隨時喚起」（整個堆疊沒有綁定單擊 Super；2026-09-08 在 fix13 VM 實測單擊 Super 無反應、Super+K 與選單列膠囊皆可開啟）。`duduclaw-cli`／`duduclaw-comp` 快照與 `duduclaw-platform-version.inc` 仍為 1.62.0，待下一次整體快照更新一併對齊。
- **內建 AI CLI 全數「cannot execute: required file not found」**：claude（SEA）、opencode、
  Cursor 內附的 node、Copilot 平台二進位的 PT_INTERP 都是 `/lib64/ld-linux-x86-64.so.2`，
  本映像非 usrmerge、glibc 只裝 `/lib/ld-linux-x86-64.so.2`。`duduclaw-ai-runtimes` 現在
  補一個相對 symlink `/lib64/ld-linux-x86-64.so.2 → ../lib/…`；QEMU 活體先手動補上後十套 CLI
  `--version` 全部回答（claude 2.1.261、copilot 1.0.83、cursor-agent 2026.09.02、opencode 1.18.29…）。
- **`compat.d/llamafactory.toml` 被 `duduclaw compat list` 判為 malformed**：`from_os = "linux-gpu"`
  不在平台 `FromOs` 列舉裡。平台同波新增 `linux-container` 變體，宣告檔改用之。
- **出貨映像上任何 app 都裝不起來**（2026-09-05 三功能走查）：Yocto 線遺失了 mkosi 線的
  `installations.d` 設定與開機設定腳本，機器上沒有 `data` 安裝區、沒有任何 remote，殼的
  `flatpak install --installation=data …` 立刻失敗且無回饋，3.4 GB 離線倉庫從未被用到。
  由上面的 `duduclaw-flatpak-setup` 修復；殼端同時改為離線倉庫優先並回報安裝結果（見平台 repo CHANGELOG）。
- **桌面帳號不能開啟任何 Flatpak app**：`flatpak run` 會列舉所有 installations.d 的安裝區，而 `verify`
  安裝區的目錄是 0750（`duduclaw-flatpak-verify:duduclaw`），`duduclaw-kiosk` 一碰到就
  「opendir(/data/system/flatpak-verify/repo): Permission denied」直接放棄，連 `data` 裡裝好的 Chromium 都開不了。
  tmpfiles 改 0755（倉庫只含公開 app 位元組）。
- **桌面帳號不能安裝 app（polkit）**：`duduclaw-polkit-flatpak` 的規則只放行 `duduclaw` 群組（Yocto 線上不存在），
  殼以 `duduclaw-kiosk` 執行 `flatpak install --installation=data` 時被拒「Deploy not allowed for user」
  （bake 5 走查時由新的安裝失敗通知卡抓到）。規則補上該 session 使用者。
- **共駕從 gateway 永遠連不到 compositor**：gateway 是 root 系統服務、環境沒有 `XDG_RUNTIME_DIR`，
  `[codrive]` 又沒設 socket 路徑，`resolved_socket_path()` 直接報錯。由 `[codrive]` 設定＋遷移修復；
  gateway→MCP 端另有平台側修正（能力閘門誤用 client_id）。
- **唯讀 root 下 `systemd-timesyncd` 每次開機 crash-loop**（QEMU 走查抓到，
  `status=238/STATE_DIRECTORY`）：其 `StateDirectory=systemd/timesync` 在 EROFS 的
  `/var/lib/systemd` 建不出來，導致出貨映像完全沒有 NTP、時鐘漂移。`duduclaw-data-binds`
  新增 `var-lib-systemd-timesync.mount`（`/data/system/timesync` → `/var/lib/systemd/timesync`，
  與 iwd 同一套 bind 機制、`RequiredBy=systemd-timesyncd.service`），early 服務與 tmpfiles
  同步建目錄，`duduclaw-ro-root.inc` 在映像內預建掛載點。`/var/lib/systemd` 其餘部分維持不綁。
- **`refresh-src.sh`（shell／comp／sysd 三份）拆分後仍指向本 repo 不存在的 `crates/`**：來源目錄
  不存在時 rsync 直接把已 vendor 的快照刪光（實際發生過一次，靠 git 還原）。三份改為與 cli 版相同的
  跨 repo 解析（`DUDUCLAW_CLI_SRC_ROOT` 覆寫 → monorepo → sibling `../DuDuClaw`），來源缺失時拒絕動快照。
- **`duduclaw-shell` recipe 的品牌 PNG 路徑手術移除**：上游 shell 改為 `assets/branding/` 隨 crate vendor，
  recipe 不再 sed 改寫 `home.rs`、不再另帶 `duduclaw-shell-branding` 檔案；改為若快照仍用舊路徑就 bbfatal。
- **文字安裝器 `duduclaw-os-install.sh` 候選磁碟補過濾唯讀裝置**（`RO=1`，例如 virtio 光碟）；
  安裝媒介所在磁碟的排除原本就有。
- shell 與 cli 快照同步：含桌面殼七項走查修正、三功能走查的殼／gateway／MCP 修正（見平台 repo CHANGELOG）。

### Removed
- `meta-duduclaw/recipes-duduclaw/duduclaw-sysd/PLAN.md`：Y1-2 時期的「尚未實作」
  占位文件，但同目錄的 `duduclaw-sysd_1.62.0.bb` 早已建置驗證通過，內容與事實相反。
- **live 安裝 ISO 載荷壓縮改 `zstd -19 --long=27`**（`DUDUCLAW_INSTALL_PAYLOAD_ZSTD` 可調）：desktop 版 ISO 在舊的 -3 下達 2.66GB，超過 GitHub 單資產 2GiB 上限；改後 qemu 1.996GB／generic 2.006GB，兩機的 desktop ISO 照常隨 0.2.0 出貨。`--long=27` 為 zstd 解壓端預設視窗上限，安裝程式不需改。
- **`release-os.sh build/smoke/package` 預設串 release overlay `serial1.yml`**：先前只吃機型 kas 設定，deploy/spdx 被清後開烤即死於 `do_create_recipe_spdx`；現由 `kas_cfg_chain` 統一串上（`DUDUCLAW_OS_KAS_OVERLAY=` 可關）。
- **wic.zst 壓縮改 `zstd -19 --long=27`＋2GiB 資產上限硬檢查**：level 3 壓出 2.38GB 撞 GitHub 422；同一顆 wic 以 -19 為 1.72GB。package 壓完先量、超限拒簽，publish 上傳前再查；manifest 加 `decompress_hint`，解壓需 `zstd -d --long=27`。

## [0.1.0] - 2026-09-04 — 首個 tagged bring-up release

DuDuClaw OS 成為獨立 repo 後的第一個版本。標記 bring-up 里程碑，不是 GA
（見 README 狀態說明與 `VERSION` 檔）。

### Added
- **可開機的 Yocto 值班機映像**（`duduclaw-image-appliance`），支援
  `duduclaw-qemux86-64` 與 `duduclaw-genericx86-64`：A/B 原子更新＋回滾、唯讀
  root、完整 DuDuClaw gateway＋dashboard 載荷。
- **圖形 live 安裝器 ISO**（`duduclaw-image-live`），兩種 machine 皆有：從 USB／
  光碟開機進 squashfs live root，把生產用的 A/B 系統寫進目標機內建磁碟。
  `qemux86-64` 版已 QEMU 開機驗證，`genericx86-64` 版為真機目標。修正 live root
  的 squashfs 掛載：`CONFIG_SQUASHFS` 改經由 oe-core 正規的 `cfg/fs/squashfs.scc`
  kernel feature 開啟（先前的裸 `.cfg` 片段沒有生效）。
- **安全信任鏈**：自簽 Secure Boot（每槽雙簽 UKI）、唯讀 root＋dm-verity 區塊
  完整性、TPM2/LUKS PCR 7+11 金鑰密封（fail-open 路徑可用；自動 enroll 為待解
  缺陷，需真機 TPM）。
- machine-id 與 entropy seed 在唯讀 root 下跨開機持久化。
- **OS 獨立 release 版號**：repo 根 `VERSION` 檔是 release 產物名與 GitHub Release
  tag 的唯一來源，與內嵌平台版號脫鉤。
- **`scripts/release-os.sh publish`**：把打包好的映像（`.wic.zst`＋`.sha256`＋
  `.minisig`＋`manifest.json`）上傳到 GitHub Release，上傳前 fail-closed 重驗簽章
  與 checksum。
- 獨立 repo 的基本檔：README、本 changelog、LICENSE、`.gitignore`。

### Changed
- **自 DuDuClaw 主 repo 拆出（2026-09）**：`meta-duduclaw/`、`appliance/`、
  `scripts/release-os.sh` 移入本 repo；Rust workspace 留在平台 repo，經
  `refresh-src.sh` 以剪枝快照 vendor 進來。
- `appliance/`（早期 Debian/mkosi 線）凍結，只作參考／過渡產物。
