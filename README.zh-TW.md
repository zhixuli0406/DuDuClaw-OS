# DuDuClaw OS

<div align="center">

**繁體中文** · [English](README.md)

</div>

DuDuClaw OS 是一套用 Yocto 建出來的 Linux 作業系統，AI agent 是原生住民：把一台 x86-64 主機變成 [DuDuClaw](https://github.com/zhixuli0406/DuDuClaw) AI 員工的值班機。它有自己的桌面（自家 Wayland compositor 與桌面殼、鎖定畫面、首次設定精靈、隨時交辦的 Cmd+K），人和 AI 共用同一台機器，而且不影響日常使用：agent 的 GUI 工作預設在影子工作區跑，你一動鍵盤滑鼠，正在你桌面上操作的 agent 立刻讓位。管理後台由 gateway 提供，接不接螢幕都能從區網的瀏覽器操作。

![DuDuClaw OS 桌面：首頁交辦列與 Dock](website/assets/screens/home-dark.png)

<sub>桌面版首頁（v0.2.0 畫面，v0.3.0 與 v0.4.0 尚未重拍）。</sub>

這個 repo 是 **base-OS 線**：`meta-duduclaw/` Yocto layer（distro 政策、機器定義、`duduclaw-*` binary 的 recipe）加上 `scripts/release-os.sh` 建置／簽章／發布產線。DuDuClaw 平台的 Rust workspace 在另一個 repo，這裡以剪枝過的快照 vendor 進來。

[![Version](https://img.shields.io/badge/version-0.4.0-blue)](https://github.com/zhixuli0406/DuDuClaw-OS/releases)
[![License: Apache-2.0](https://img.shields.io/badge/License-Apache--2.0-blue.svg)](LICENSE)

> **狀態：bring-up（0.4.0，pre-GA，內嵌平台 v1.73.4）。** 映像能開機、能 A/B 更新並回滾；信任鏈在 layer 已接好，但截至 v0.4.0，發布映像仍未啟用簽章／verity／TPM（見信任鏈一節）。這不是正式版：`0.x` 追蹤 bring-up，`1.0.0` 才是第一個 GA。目前所有驗證都在 QEMU 上完成，**尚未在真實 x86-64 硬體上開機過**。

**v0.4.0 的變更**（2026-10-16）：gateway 不再以 root 執行，改用 `duduclaw` 帳號（uid 1000）；桌面版的容器（任務沙箱、腳本沙箱、電腦操作、Discovery）從 root 的 Docker 換成 rootless Podman，引擎不執行資源上限時這些功能會自動關閉。唯一的 root 輔助程式 `duduclaw-sysd` 只接受 gateway 主行程的請求，系統更新由它自己驗證簽章、雜湊與版本後才安裝。SSH 預設關閉，只能從後台的維護模式打開；基礎版也有了和桌面版相同的預設拒絕防火牆。工廠重置改在下次開機、任何服務啟動前清資料。**升級是單向的**：裝置成功開過 v0.4.0 之後，就不能再回到 v0.3.0 或更早的版本。v0.4.0 發布映像沒有能透過 SSH 登入的帳號，該版維護模式的 SSH 只控制連接埠。完整清單見 [CHANGELOG](CHANGELOG.md) 的 0.4.0 一節。

**尚未發版的原始碼：**layer 已同步平台 v1.74.0 的
`c7068c508ae9ab5afc4392b58237cf86afdb9f2c`，包含臨時金鑰 SSH 的閘道、
root 輔助服務與儀表板。CLI recipe 同時編譯受限選單 `maint-shell` 與
root 服務 `maint-helper`，帳號套件安裝 SSH 就緒標記。映像檢查會確認
工具、帳號、服務沙箱與防火牆齊備，並拒絕任何烤進映像的 `authorized_keys`。
管理員須提供一把技術人員公鑰，維修視窗最長 24 小時；不開放密碼登入
或任意 shell。**這份候選原始碼尚未通過 Yocto 映像建置與 QEMU 驗證。**
已發布的下載仍是內嵌平台 v1.73.4 的 v0.4.0。限制見 [安全說明](SECURITY.md)。

## 目錄

- [為什麼需要 DuDuClaw OS？](#why)
- [映像裡有什麼](#whats-inside)
- [桌面環境](#desktop)
- [信任鏈](#trust)
- [快速開始：下載、驗簽、燒錄](#quickstart)
- [從原始碼建置](#build)
- [Repo 結構](#layout)
- [文件](#docs)
- [授權](#license)

<a id="why"></a>

## 為什麼需要 DuDuClaw OS？

自己裝一套 Linux 再裝 `duduclaw` 當然可以。但要放在櫃台後面當值班機、或交給沒有工程師的客戶，更新、回滾、防竄改、首次設定就全得自己處理。DuDuClaw OS 把這些做進映像：

| 需求 | 自己裝 Linux + duduclaw | DuDuClaw OS |
|---|---|---|
| 首次設定 | SSH 進去手動改設定 | 首次開機自動 provision，後台直接出現在區網 |
| 系統更新 | 套件管理器，失敗要自己救 | A/B 雙槽原子更新，開機失敗自動回滾 |
| 防竄改 | 自行設定 | 唯讀 root（桌面版出貨預設）；dm-verity 逐塊驗證已接好，由建置 overlay 啟用（截至 v0.4.0 仍未啟用） |
| 開機信任 | 多半直接關掉 Secure Boot | 自簽 Secure Boot、每槽雙簽 UKI、首次開機自動 enroll 已接好，由建置 overlay 啟用（截至 v0.4.0，發布映像仍未簽章，開機需關閉 Secure Boot） |
| 磁碟金鑰 | 手動 LUKS | TPM2 PCR 7+11 密封（建置 overlay 選項，部分完成，截至 v0.4.0 仍未啟用） |
| 桌面與應用 | 逐一安裝 | 自家 compositor/shell、Flatpak 離線倉庫（Chromium、LibreOffice 從 Launcher 一鍵安裝，不需網路）、注音輸入法 |
| 人與 AI 共用一台機器 | 各開各的視窗，互不知情 | 桌面殼內建交辦列（Cmd+K）；agent 的 GUI 工作預設在影子工作區跑，不碰你的視窗與游標；你一動鍵盤滑鼠，正在你桌面上操作的 agent 立刻凍結 |
| AI 工具鏈 | 一家一家 `npm install -g`，換機重來 | 十套廠商 CLI 直接在映像裡：`claude`／`codex`／`gemini`／`qwen`／`kimi`／`copilot`／`grok`／`agent`（Cursor）／`opencode`／`vibe`，開機即可用，憑證存在 `/data`，更新不會被洗掉 |
| 離線推理 | 自己編 llama.cpp、自己寫 service | 內建 llama.cpp `llama-server`；模型從後台一鍵下載到 `/data/duduclaw/models`，斷網也能交辦 |

<a id="whats-inside"></a>

## 映像裡有什麼

- **Yocto Project 6.0 "wrynose"**（LTS），預設 kernel Linux 6.18。
- 兩種 machine：`duduclaw-qemux86-64`（QEMU 可開機的 bring-up 目標）與 `duduclaw-genericx86-64`（真實 x86-64 硬體，x86-64-v3 tune）。
- 每個 release、每種 machine 各有三個產物，都附 `.sha256` 與 minisign `.minisig`：

| 產物 | 內容 | 用途 |
|---|---|---|
| `duduclaw-os-<machine>-v<ver>.wic.zst` | **桌面版** `duduclaw-image-appliance`：A/B 更新鏈＋桌面殼＋Flatpak 離線倉庫（Chromium／LibreOffice）＋注音 IME＋app 相容層＋唯讀 root＋防火牆＋登入硬化 | 整碟燒錄，日常主力機 |
| `duduclaw-os-installer-<machine>-v<ver>.iso` | `duduclaw-image-live`：squashfs live 環境＋圖形安裝精靈，寫入的是**基礎版** `duduclaw-image-ab`：同樣的 A/B 佈局、桌面殼與 gateway，但沒有應用層、app 相容層與唯讀 root（防火牆從 v0.4.0 起與桌面版相同），屬 bring-up 產物 | 燒成 USB 開機安裝 |
| `duduclaw-os-installer-desktop-<machine>-v<ver>.iso` | `duduclaw-image-live-desktop`：同一個安裝精靈，寫入的是桌面版 `duduclaw-image-appliance`（v0.1.0／2026-09-04 首度隨版補上，之後每版持續提供） | 燒成 USB 開機安裝，得到與整碟映像相同的桌面版 |

<a id="desktop"></a>

## 桌面環境

每一種 DuDuClaw OS 映像開機都直接進自家桌面，全部用鍵盤就能操作（桌面版多了應用層與出貨硬化，見上表）：

- **自家 compositor 與殼**：`duduclaw-comp`（Wayland compositor）＋`duduclaw-shell`（桌面殼），有首頁、視窗切換、鎖定畫面與控制中心；Cmd+K 在任何 app 上叫出交辦列，把工作直接丟給 AI 員工。快捷鍵總表見文件站的 [OS 快捷鍵](https://os.duduclaw.dudustudio.monster/docs/features/51-os-keyboard-shortcuts/)。
- **首次設定精靈**：語言、帳號、主題、Wi-Fi 在第一次開機的圖形精靈裡完成；安裝器 ISO 同樣是圖形精靈（選碟、確認、寫入進度、重開）。
- **輸入與音訊**：fcitx5 注音輸入法、PipeWire／WirePlumber 音訊、XWayland 跑 X11 程式。
- **人機共用，不影響日常使用**：agent 有自己的輸入 seat；GUI 任務預設在 headless 影子工作區執行（可開子母畫面旁觀），不碰你的視窗、焦點與游標；人輸入永遠優先，compositor 層強制凍結正在你桌面上操作的 agent（QEMU 實測 3–4 ms）；Super+Enter 交還、Super+Esc 急停；共駕能力預設關閉、後果性動作先審批、登入與付款一律交人。完整說明見文件站的 [桌面版](https://os.duduclaw.dudustudio.monster/docs/features/52-desktop-edition/)。
- **AI 工具鏈內建**（桌面版）：十套廠商 coding CLI 打包在 `/opt/duduclaw/runtimes`，`/usr/bin` 直接有 `claude`、`codex`、`gemini`、`qwen`、`kimi`、`copilot`、`grok`、`agent`、`opencode`、`vibe`；憑證統一寫在 `/data/duduclaw`（0700），系統更新不會清掉。平台自 v1.67.0 起把 Gemini CLI runtime 標為棄用；v0.4.0 內嵌的平台 1.73.4 仍保留這個 runtime，平台之後把移除版本再延到 v1.75.0，等 OS 同步到移除後的平台版本時 `gemini` 會跟著退出這份清單。平台 1.73.4 的 runtime 清單裡另有 Google Antigravity（`agy`），映像沒有內建，後台會顯示官方安裝指令。本機推理由 llama.cpp `llama-server` 負責，權重不進映像、由後台下載到 `/data/duduclaw/models`。哪些沒內建、為什麼、怎麼重新產生這包，見 [AI runtimes 指南](docs/guides/ai-runtimes.md)。
- **應用程式**（桌面版）：映像內建 Flatpak 離線倉庫，Chromium、LibreOffice 在 Launcher 按「安裝」即從本機倉庫裝好，不需網路；其他 app 走 Flathub。app 相容層以 `compat.d` 宣告：Bottles 跑 Windows 桌面程式、KVM 虛擬機＋RDP 跑完整 Windows、Waydroid 跑 Android（不含 GApps，需自行設定）；macOS 程式不做本機執行。範圍與明確不承諾的項目見 [app 相容層指南](docs/guides/app-compat.md)（文件站：<https://os.duduclaw.dudustudio.monster/docs/os/guides/app-compat/>）。

安裝器 ISO（`installer` 變體）寫進磁碟的基礎版 `duduclaw-image-ab` 有同一個桌面殼與 gateway，只是沒有應用層；管理後台由 gateway 提供，有沒有接螢幕都能從區網瀏覽器操作。沒接螢幕時桌面本身的行為（會不會自動退回純無頭）還沒在真機上定義，屬 bring-up 待辦。

<a id="trust"></a>

## 信任鏈

layer 已接好整條鏈，但截至 v0.4.0，發布的映像都只啟用了一部分。出貨即有：**A/B 原子更新與回滾**、**唯讀 root**（桌面版）。下列三項是建置期 overlay 選項，**截至 v0.4.0 的發布映像都沒有啟用**；v0.4.0 的 Release 說明寫明了這點，它在 GCP builder 上的測試建置也和 v0.3.0 一樣用 `kas/release-linux-builder.yml`。v0.3.0 用 `kas/release-linux-builder.yml` 建置，沒有疊加 `sb-signing.yml`／`tpm-luks.yml`；拆開兩個發布 wic 查證（2026-10-14）：兩槽 UKI、rescue UKI 與 systemd-boot 的 PE 簽章表都是空的，ESP 沒有 enroll 用的金鑰，GPT 只有 ESP、兩個 root 槽與 data 四個分割（沒有 verity 分割），UKI 的 initrd 裡沒有 tpm2／cryptsetup。v0.2.0 發布時拆開查證的結果相同（兩槽 UKI 與 systemd-boot 無簽章、無 verity 分割、無 TPM 套件）：

- **Secure Boot＋dm-verity**（`kas/sb-signing.yml`）：自簽 PK/KEK/db、每槽雙簽 UKI、首次開機自動 enroll；rootfs 逐塊驗證，竄改即讀取失敗。
- **TPM2 + LUKS**（`kas/tpm-luks.yml`，部分完成）：PCR 7+11 量測開機的金鑰密封與 fail-open 復原路徑已接好；自動 enroll 是待解缺陷，要等真機 TPM 才能完成（QEMU/swtpm 做不到）。
- **發布產物簽章**（已啟用）：每個檔案附 `.sha256` 與 minisign `.minisig`，公鑰釘在 `scripts/release-os.sh`，上傳前 fail-closed 重驗。漏洞回報方式見 [SECURITY.md](SECURITY.md)。

`scripts/release-os.sh build` 目前預設只會疊加 `kas/serial1.yml`（release overlay：`-j1` 序列建置＋SPDX off；大型 Linux builder 改用 `kas/release-linux-builder.yml`），不含 `sb-signing.yml`／`tpm-luks.yml`；要出簽章版必須手動疊加這兩個 overlay 建置，列為下一版待辦。

<a id="quickstart"></a>

## 快速開始：下載、驗簽、燒錄

從 [GitHub Releases](https://github.com/zhixuli0406/DuDuClaw-OS/releases) 下載想要的產物與同名 `.sha256`、`.minisig`，先驗簽再燒：

```bash
minisign -V -P RWQyI00ugZ/+WVisQ2ZnKeTqFs8Ze8h2X11FO9Z8le0YubFMXYTwQD7n -m <檔案>
shasum -a 256 -c <檔案>.sha256
```

**安裝器 ISO：`installer-desktop`＝桌面版；`installer`＝基礎版（桌面殼＋gateway，無應用層）**

```bash
dd if=<iso> of=/dev/<usb> bs=4M conv=fsync    # 或用 balenaEtcher
```

目標機用 UEFI 開機，**Secure Boot 關閉**（截至 v0.4.0，發布映像仍未簽章；簽章版才會在首次開機自動 enroll 金鑰）。從 USB 開機進圖形安裝精靈，選目標 SSD 安裝；重開機後就是 A/B UKI + systemd-boot 系統，用同一區網的瀏覽器開後台。

**尚未發布的安裝器修正**：開發版原始碼在解壓、進度管線或寫碟失敗時會停止，完整串流與同步成功後才報 100%。失敗可能留下部分寫入的磁碟，請重新安裝後再從該磁碟開機。host 回歸測試已過；重新建置與兩版正式 ISO 的真空白磁碟安裝仍待驗證。見[安裝器測試](appliance/tests/installer/README.md)。

**整碟映像（桌面版：桌面＋應用程式＋出貨硬化）**

```bash
zstd -d --long=27 <wic.zst>
dd if=<wic> of=/dev/<目標磁碟> bs=4M conv=fsync    # 或 bmaptool copy
```

> v0.4.0 發布前，QEMU 版（`duduclaw-qemux86-64`）的整碟映像在 GCP builder 上以無頭 QEMU（純軟體模擬、沒有 KVM）開到登入畫面（約 65 秒）；同機型的兩個安裝器 ISO 也各自開到 live 環境的 root 自動登入（約 125 秒）。這一版**沒有跑安裝精靈**，跑完整段安裝的 QEMU 紀錄仍停在 v0.1.0 與 2026-09-06 的開發版。另外，桌面版的 qemux86-64 測試映像跑了兩輪 rootless gateway 驗證，第二輪 36 項過 35 項（沒過的一項是 doctor 標題文字，已在平台 main 修好）。還沒驗證的：v0.3.0 裝置經 A/B 更新升級、需要 LLM 憑證的任務沙箱／電腦操作／Discovery 完整流程、Windows 虛擬機（需要 KVM）、真機的 Wi-Fi 與音訊。`duduclaw-genericx86-64` 是真機目標，QEMU 開不起來，v0.4.0 只建置、沒有開機（整碟映像與兩個 ISO 都是）；真機開機是目前最重要的待驗證項目。
>
> **升級是單向的。** 裝置成功開過 v0.4.0 之後，就不能再退回 v0.3.0 或更早的版本（那些版本的 gateway 以 root 執行）。之後的版本如果出問題，只能安裝修好的新版，或用救援開機項目。

<a id="build"></a>

## 從原始碼建置

前置需求：

- Docker。Yocto 建置在 `duduclaw-yocto-builder` 容器裡跑（macOS 沒有原生 bitbake）。
- 平台 repo 的 sibling checkout。只有要重整 vendored 快照時才需要（整套對齊用 `scripts/sync-platform.sh <平台版本>`，見 `docs/guides/platform-sync.md`；單一 recipe 用 `meta-duduclaw/recipes-duduclaw/duduclaw-cli/refresh-src.sh`，路徑可用 `DUDUCLAW_CLI_SRC_ROOT` 覆寫）。`duduclaw-comp`／`duduclaw-shell` 的快照來源是本 repo 的 `crates/`，不需要平台 checkout。
- `minisign` 與 `gh`，簽章與發布用。

```bash
./scripts/release-os.sh audit      # 顯示 OS 版本與內嵌平台版本
./scripts/release-os.sh build      # 在已啟動的 builder 容器內 kas build
./scripts/release-os.sh smoke      # 無頭 QEMU 開機到 login prompt
./scripts/release-os.sh package    # smoke 閘門 + 壓縮 + sha256 + minisign
./scripts/release-os.sh sign       # 簽 builder 上以 package --no-sign 產出、複製回來的檔案
./scripts/release-os.sh publish    # 上傳到 GitHub Release
```

generic 映像會要求內建 KVM guest 支援；最終核心 `.config` 缺少 guest／時鐘前置選項、必要 VirtIO 或 PCI MSI 時，建置會停止。host KVM 模組沿用既有設定。這項組態檢查不能取代原生 GCE 開機與安裝驗收，詳見 [layer 建置參考](meta-duduclaw/README.md#build)。

遠端 builder（例如 GCP）不放簽章金鑰：在 builder 上跑 `package --no-sign`，把 `artifacts/os/v<版本>/<機型>/` 複製回持有金鑰的機器，再跑 `sign` 與 `publish`。大記憶體的 Linux builder 可以用 `DUDUCLAW_OS_KAS_OVERLAY=meta-duduclaw/kas/release-linux-builder.yml` 取代預設的 `serial1.yml`（同樣關掉 SPDX，但不做 `-j1`），`build`／`smoke`／`package` 要帶同一個值。

smoke 判斷「到了登入畫面」與「QEMU／kas 已經放棄」用的 log 樣式有自己的測試：`scripts/tests/smoke-patterns.sh`（不需要 Docker 或 QEMU，對 `scripts/tests/fixtures/smoke/` 的範例逐行比對）。

每個子命令的 `v<version>` 都可省略，預設讀 `VERSION` 檔（OS 自己的版號，與內嵌平台版號無關）。不帶參數執行可看完整說明。builder 容器怎麼起、磁碟與快取怎麼掛、各 image 的用途，見 [`meta-duduclaw/README.md`](meta-duduclaw/README.md)。

<a id="layout"></a>

## Repo 結構

| 路徑 | 內容 |
|---|---|
| `meta-duduclaw/` | Yocto layer（distro、machine、image、`duduclaw-*` recipe、kas 設定） |
| `crates/` | OS 自有的 Rust crate：`duduclaw-comp`（smithay compositor）、`duduclaw-shell`（gpui 殼）、`duduclaw-native-gui`（shell 的 path 依賴）。2026-09-29 自平台 repo 搬入（它們本來就是平台 workspace `exclude` 的獨立 crate），各自 detached `Cargo.lock`，recipe 以 `refresh-src.sh` 從這裡快照 |
| `scripts/release-os.sh` | `build → smoke → package → publish` 產線 |
| `VERSION` | OS 的獨立 release 版號 |
| `docs/` | 公開文件，依類型分子目錄，索引在 `docs/README.md` |
| `wiki/` | 內部 bring-up 筆記、驗收清單、證據 log |
| `appliance/` | 早期 Debian/mkosi 值班機線，**已凍結**，只作參考與過渡產物；產品不從這裡建 |

<a id="docs"></a>

## 文件

- 官網與文件站：<https://os.duduclaw.dudustudio.monster>（首頁與下載頁；文件站在同網域的 `/docs/`，彙整本 repo 與平台 repo 的公開文件，zh-TW／en／ja 三語系，站內不連 GitHub）。GitHub 上只留 repo、Releases、Issues 與 LICENSE。
- [`docs/README.md`](docs/README.md)：本 repo 的文件索引（公開文件、元件參考、內部筆記、分級規則）。
- [`meta-duduclaw/README.md`](meta-duduclaw/README.md)：layer 參考，含 layout、各 image 用途、builder 容器與 `kas build`。
- [`CHANGELOG.md`](CHANGELOG.md)：版本紀錄，依 Keep a Changelog。
- [`CONTRIBUTING.md`](CONTRIBUTING.md)、[`SECURITY.md`](SECURITY.md)：貢獻方式與漏洞回報。
- 使用者視角的功能說明（原始碼在平台 repo，發佈在文件站）：[DuDuClaw OS appliance](https://os.duduclaw.dudustudio.monster/docs/features/50-duduclaw-os-appliance/)、[硬體需求與相容性](https://os.duduclaw.dudustudio.monster/docs/guides/hardware-requirements/)。[app 相容層指南](docs/guides/app-compat.md) 在本 repo。

<a id="license"></a>

## 授權

Apache License 2.0，與 DuDuClaw 平台相同。見 [LICENSE](LICENSE)。
