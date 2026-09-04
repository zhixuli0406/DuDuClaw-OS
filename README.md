# DuDuClaw OS

<div align="center">

**繁體中文** · [English](README.en.md)

</div>

DuDuClaw OS 是一套用 Yocto 建出來的 Linux 映像，把一台小型 x86-64 主機變成常駐的 [DuDuClaw](https://github.com/zhixuli0406/DuDuClaw) AI 員工值班機。燒進去、接上電源和網路線，DuDuClaw 管理後台就出現在區網上；之後的所有設定都在瀏覽器裡完成，主機本身不需要螢幕和鍵盤，也沒有互動式安裝。

這個 repo 是 **base-OS 線**：`meta-duduclaw/` Yocto layer（distro 政策、機器定義、`duduclaw-*` binary 的 recipe）加上 `scripts/release-os.sh` 建置／簽章／發布產線。DuDuClaw 平台的 Rust workspace 在另一個 repo，這裡以剪枝過的快照 vendor 進來。

[![Version](https://img.shields.io/badge/version-0.1.0-blue)](https://github.com/zhixuli0406/DuDuClaw-OS/releases)
[![License: Apache-2.0](https://img.shields.io/badge/License-Apache--2.0-blue.svg)](LICENSE)

> **狀態：bring-up（0.1.0，pre-GA）。** 映像能開機、能 A/B 更新並回滾、信任鏈大致就位，但這不是正式版：`0.x` 追蹤 bring-up，`1.0.0` 才是第一個 GA。目前所有驗證都在 QEMU 上完成，**尚未在真實 x86-64 硬體上開機過**。

## 目錄

- [為什麼需要 DuDuClaw OS？](#why)
- [映像裡有什麼](#whats-inside)
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
| 防竄改 | 自行設定 | 唯讀 root + dm-verity 逐塊驗證，被改過的資料直接讀取失敗 |
| 開機信任 | 多半直接關掉 Secure Boot | 自簽 Secure Boot，每個槽各自雙簽 UKI，首次開機自動 enroll 金鑰 |
| 磁碟金鑰 | 手動 LUKS | TPM2 PCR 7+11 密封（部分完成，見下） |
| 桌面與應用 | 逐一安裝 | 自家 compositor/shell、Flatpak 離線預載（Chromium、LibreOffice、Steam）、注音輸入法 |

<a id="whats-inside"></a>

## 映像裡有什麼

- **Yocto Project 6.0 "wrynose"**（LTS），預設 kernel Linux 6.18。
- 兩種 machine：`duduclaw-qemux86-64`（QEMU 可開機的 bring-up 目標）與 `duduclaw-genericx86-64`（真實 x86-64 硬體，x86-64-v3 tune）。
- 每個 release、每種 machine 各有兩式產物，都附 `.sha256` 與 minisign `.minisig`：

| 產物 | 內容 | 用途 |
|---|---|---|
| `duduclaw-os-<machine>-v<ver>.wic.zst` | `duduclaw-image-appliance`：A/B 更新鏈＋完整桌面（compositor/shell、Chromium、LibreOffice、Steam、注音 IME） | 整碟燒錄，直接當日常主力機 |
| `duduclaw-os-installer-<machine>-v<ver>.iso` | `duduclaw-image-live`：squashfs live 環境＋圖形安裝精靈，把 `duduclaw-image-ab`（無頭 gateway＋dashboard）寫進目標機的內建磁碟 | 燒成 USB 開機安裝 |

<a id="trust"></a>

## 信任鏈

- **Secure Boot**：自簽 PK/KEK/db，每個 A/B 槽一份雙簽 UKI，首次開機自動 enroll 金鑰。
- **唯讀 root + dm-verity**：rootfs 不可寫且逐塊驗證，竄改的結果是讀取失敗，連開機都過不了。
- **TPM2 + LUKS（部分完成）**：PCR 7+11 量測開機的金鑰密封與 fail-open 復原路徑已接好；自動 enroll 是待解缺陷，要等真機 TPM 才能完成（QEMU/swtpm 做不到）。
- **發布產物簽章**：每個檔案附 `.sha256` 與 minisign `.minisig`，公鑰釘在 `scripts/release-os.sh`，上傳前 fail-closed 重驗。漏洞回報方式見 [SECURITY.md](SECURITY.md)。

<a id="quickstart"></a>

## 快速開始：下載、驗簽、燒錄

從 [GitHub Releases](https://github.com/zhixuli0406/DuDuClaw-OS/releases) 下載想要的產物與同名 `.sha256`、`.minisig`，先驗簽再燒：

```bash
minisign -V -P RWQyI00ugZ/+WVisQ2ZnKeTqFs8Ze8h2X11FO9Z8le0YubFMXYTwQD7n -m <檔案>
shasum -a 256 -c <檔案>.sha256
```

**安裝器 ISO（真機建議走這條）**

```bash
dd if=<iso> of=/dev/<usb> bs=4M conv=fsync    # 或用 balenaEtcher
```

目標機用 UEFI 開機，Secure Boot 先設成 setup mode 或暫時關閉（首次開機會自動 enroll DuDuClaw 金鑰）。從 USB 開機進圖形安裝精靈，選目標 SSD 安裝；重開機後就是 A/B UKI + systemd-boot 系統，用同一區網的瀏覽器開後台。

**整碟映像（跳過安裝器）**

```bash
zstd -d <wic.zst>
dd if=<wic> of=/dev/<目標磁碟> bs=4M conv=fsync    # 或 bmaptool copy
```

> QEMU 版（`duduclaw-qemux86-64`）兩式都已實際開機驗證。`duduclaw-genericx86-64` 是真機目標，QEMU 開不起來，v0.1.0 只做過設定稽核；真機開機是目前最重要的待驗證項目。

<a id="build"></a>

## 從原始碼建置

前置需求：

- Docker。Yocto 建置在 `duduclaw-yocto-builder` 容器裡跑（macOS 沒有原生 bitbake）。
- 平台 repo 的 sibling checkout。只有要重整 vendored 快照時才需要（`meta-duduclaw/recipes-duduclaw/duduclaw-cli/refresh-src.sh`，路徑可用 `DUDUCLAW_CLI_SRC_ROOT` 覆寫）。
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
| `scripts/release-os.sh` | `build → smoke → package → publish` 產線 |
| `VERSION` | OS 的獨立 release 版號 |
| `docs/` | 公開文件，依類型分子目錄，索引在 `docs/README.md` |
| `wiki/` | 內部 bring-up 筆記、驗收清單、證據 log |
| `appliance/` | 早期 Debian/mkosi 值班機線，**已凍結**，只作參考與過渡產物；產品不從這裡建 |

<a id="docs"></a>

## 文件

- [`docs/README.md`](docs/README.md)：本 repo 的文件索引（公開文件、元件參考、內部筆記、分級規則）。
- [`meta-duduclaw/README.md`](meta-duduclaw/README.md)：layer 參考，含 layout、各 image 用途、builder 容器與 `kas build`。
- [`CHANGELOG.md`](CHANGELOG.md)：版本紀錄，依 Keep a Changelog。
- [`CONTRIBUTING.md`](CONTRIBUTING.md)、[`SECURITY.md`](SECURITY.md)：貢獻方式與漏洞回報。
- 使用者視角的功能說明在平台 repo：[DuDuClaw OS appliance](https://github.com/zhixuli0406/DuDuClaw/blob/main/docs/features/50-duduclaw-os-appliance.md)、[硬體需求與相容性](https://github.com/zhixuli0406/DuDuClaw/blob/main/docs/guides/hardware-requirements.md)、[app 相容層](https://github.com/zhixuli0406/DuDuClaw/blob/main/docs/guides/app-compat.md)。

<a id="license"></a>

## 授權

Apache License 2.0，與 DuDuClaw 平台相同。見 [LICENSE](LICENSE)。
