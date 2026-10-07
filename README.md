# DuDuClaw OS

<div align="center">

**繁體中文** · [English](README.en.md)

</div>

DuDuClaw OS 是一套用 Yocto 建出來的 Linux 作業系統，AI agent 是原生住民：把一台 x86-64 主機變成 [DuDuClaw](https://github.com/zhixuli0406/DuDuClaw) AI 員工的值班機。它有自己的桌面（自家 Wayland compositor 與桌面殼、鎖定畫面、首次設定精靈、隨時交辦的 Cmd+K），人和 AI 共用同一台機器，而且不影響日常使用：agent 的 GUI 工作預設在影子工作區跑，你一動鍵盤滑鼠，正在你桌面上操作的 agent 立刻讓位。管理後台由 gateway 提供，接不接螢幕都能從區網的瀏覽器操作。

這個 repo 是 **base-OS 線**：`meta-duduclaw/` Yocto layer（distro 政策、機器定義、`duduclaw-*` binary 的 recipe）加上 `scripts/release-os.sh` 建置／簽章／發布產線。DuDuClaw 平台的 Rust workspace 在另一個 repo，這裡以剪枝過的快照 vendor 進來。

[![Version](https://img.shields.io/badge/version-0.2.0-blue)](https://github.com/zhixuli0406/DuDuClaw-OS/releases)
[![License: Apache-2.0](https://img.shields.io/badge/License-Apache--2.0-blue.svg)](LICENSE)

> **狀態：bring-up（0.2.0，pre-GA）。** 映像能開機、能 A/B 更新並回滾；信任鏈在 layer 已接好，但截至 v0.2.0，發布映像仍未啟用簽章／verity／TPM（見信任鏈一節）。這不是正式版：`0.x` 追蹤 bring-up，`1.0.0` 才是第一個 GA。目前所有驗證都在 QEMU 上完成，**尚未在真實 x86-64 硬體上開機過**。

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
| 防竄改 | 自行設定 | 唯讀 root（桌面版出貨預設）；dm-verity 逐塊驗證已接好，由建置 overlay 啟用（截至 v0.2.0 仍未啟用） |
| 開機信任 | 多半直接關掉 Secure Boot | 自簽 Secure Boot、每槽雙簽 UKI、首次開機自動 enroll 已接好，由建置 overlay 啟用（截至 v0.2.0，發布映像仍未簽章，開機需關閉 Secure Boot） |
| 磁碟金鑰 | 手動 LUKS | TPM2 PCR 7+11 密封（建置 overlay 選項，部分完成，截至 v0.2.0 仍未啟用） |
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
| `duduclaw-os-installer-<machine>-v<ver>.iso` | `duduclaw-image-live`：squashfs live 環境＋圖形安裝精靈，寫入的是**基礎版** `duduclaw-image-ab`：同樣的 A/B 佈局、桌面殼與 gateway，但沒有應用層、app 相容層、唯讀 root 與防火牆，屬 bring-up 產物 | 燒成 USB 開機安裝 |
| `duduclaw-os-installer-desktop-<machine>-v<ver>.iso` | `duduclaw-image-live-desktop`：同一個安裝精靈，寫入的是桌面版 `duduclaw-image-appliance`（v0.1.0／2026-09-04 首度隨版補上，之後每版持續提供） | 燒成 USB 開機安裝，得到與整碟映像相同的桌面版 |

<a id="desktop"></a>

## 桌面環境

每一種 DuDuClaw OS 映像開機都直接進自家桌面，全部用鍵盤就能操作（桌面版多了應用層與出貨硬化，見上表）：

- **自家 compositor 與殼**：`duduclaw-comp`（Wayland compositor）＋`duduclaw-shell`（桌面殼），有首頁、視窗切換、鎖定畫面與控制中心；Cmd+K 在任何 app 上叫出交辦列，把工作直接丟給 AI 員工。快捷鍵總表見文件站的 [OS 快捷鍵](https://os.duduclaw.dudustudio.monster/docs/features/51-os-keyboard-shortcuts/)。
- **首次設定精靈**：語言、帳號、主題、Wi-Fi 在第一次開機的圖形精靈裡完成；安裝器 ISO 同樣是圖形精靈（選碟、確認、寫入進度、重開）。
- **輸入與音訊**：fcitx5 注音輸入法、PipeWire／WirePlumber 音訊、XWayland 跑 X11 程式。
- **人機共用，不影響日常使用**：agent 有自己的輸入 seat；GUI 任務預設在 headless 影子工作區執行（可開子母畫面旁觀），不碰你的視窗、焦點與游標；人輸入永遠優先，compositor 層強制凍結正在你桌面上操作的 agent（QEMU 實測 3–4 ms）；Super+Enter 交還、Super+Esc 急停；共駕能力預設關閉、後果性動作先審批、登入與付款一律交人。完整說明見文件站的 [桌面版](https://os.duduclaw.dudustudio.monster/docs/features/52-desktop-edition/)。
- **AI 工具鏈內建**（桌面版）：十套廠商 coding CLI 打包在 `/opt/duduclaw/runtimes`，`/usr/bin` 直接有 `claude`、`codex`、`gemini`、`qwen`、`kimi`、`copilot`、`grok`、`agent`、`opencode`、`vibe`；憑證統一寫在 `/data/duduclaw`（0700），系統更新不會清掉。平台自 v1.67.0 起把 Gemini CLI runtime 標為棄用、預定 v1.71.0 移除；v0.2.0 內嵌的是平台 1.63.0，不受影響，之後同步到移除後的平台版本時 `gemini` 會跟著退出這份清單。本機推理由 llama.cpp `llama-server` 負責，權重不進映像、由後台下載到 `/data/duduclaw/models`。哪些沒內建、為什麼、怎麼重新產生這包，見 [AI runtimes 指南](docs/guides/ai-runtimes.md)。
- **應用程式**（桌面版）：映像內建 Flatpak 離線倉庫，Chromium、LibreOffice 在 Launcher 按「安裝」即從本機倉庫裝好，不需網路；其他 app 走 Flathub。app 相容層以 `compat.d` 宣告：Bottles 跑 Windows 桌面程式、KVM 虛擬機＋RDP 跑完整 Windows、Waydroid 跑 Android（不含 GApps，需自行設定）；macOS 程式不做本機執行。範圍與明確不承諾的項目見 [app 相容層指南](docs/guides/app-compat.md)（文件站：<https://os.duduclaw.dudustudio.monster/docs/os/guides/app-compat/>）。

安裝器 ISO（`installer` 變體）寫進磁碟的基礎版 `duduclaw-image-ab` 有同一個桌面殼與 gateway，只是沒有應用層；管理後台由 gateway 提供，有沒有接螢幕都能從區網瀏覽器操作。沒接螢幕時桌面本身的行為（會不會自動退回純無頭）還沒在真機上定義，屬 bring-up 待辦。

<a id="trust"></a>

## 信任鏈

layer 已接好整條鏈，但截至 v0.2.0，發布的映像都只啟用了一部分。出貨即有：**A/B 原子更新與回滾**、**唯讀 root**（桌面版）。下列三項是建置期 overlay 選項，**截至 v0.2.0 的發布映像都沒有啟用**（拆開發布 wic 查證：兩槽 UKI 與 systemd-boot 皆無簽章、GPT 無 verity 分割、無 TPM 套件）：

- **Secure Boot＋dm-verity**（`kas/sb-signing.yml`）：自簽 PK/KEK/db、每槽雙簽 UKI、首次開機自動 enroll；rootfs 逐塊驗證，竄改即讀取失敗。
- **TPM2 + LUKS**（`kas/tpm-luks.yml`，部分完成）：PCR 7+11 量測開機的金鑰密封與 fail-open 復原路徑已接好；自動 enroll 是待解缺陷，要等真機 TPM 才能完成（QEMU/swtpm 做不到）。
- **發布產物簽章**（已啟用）：每個檔案附 `.sha256` 與 minisign `.minisig`，公鑰釘在 `scripts/release-os.sh`，上傳前 fail-closed 重驗。漏洞回報方式見 [SECURITY.md](SECURITY.md)。

`scripts/release-os.sh build` 目前預設只會疊加 `kas/serial1.yml`（release overlay：`-j1` 序列建置＋SPDX off），不含 `sb-signing.yml`／`tpm-luks.yml`；要出簽章版必須手動疊加這兩個 overlay 建置，列為下一版待辦。

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

目標機用 UEFI 開機，**Secure Boot 關閉**（截至 v0.2.0，發布映像仍未簽章；簽章版才會在首次開機自動 enroll 金鑰）。從 USB 開機進圖形安裝精靈，選目標 SSD 安裝；重開機後就是 A/B UKI + systemd-boot 系統，用同一區網的瀏覽器開後台。

**整碟映像（桌面版：桌面＋應用程式＋出貨硬化）**

```bash
zstd -d <wic.zst>
dd if=<wic> of=/dev/<目標磁碟> bs=4M conv=fsync    # 或 bmaptool copy
```

> QEMU 版（`duduclaw-qemux86-64`）的整碟映像在 v0.2.0 發布前跑過 QEMU 開機測試（到登入畫面）；安裝器 ISO 發布前沒有重跑開機，跑完安裝的 QEMU 紀錄停在 v0.1.0 與 2026-09-06 的開發版；發布後（2026-10-07）桌面版安裝器在 QEMU 開到安裝精靈第一頁，沒有跑完安裝。`duduclaw-genericx86-64` 是真機目標，QEMU 開不起來，截至 v0.2.0 只做過設定稽核；真機開機是目前最重要的待驗證項目。

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
./scripts/release-os.sh publish    # 上傳到 GitHub Release
```

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
