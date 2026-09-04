# Changelog

DuDuClaw OS 所有值得記錄的變更都在這裡。版號與 DuDuClaw 平台**獨立**（見
`VERSION` 檔），格式依 [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
與 [Semantic Versioning](https://semver.org/)。逐波的 bring-up 歷程（Y1–Y20）
在 git log 與 `wiki/impl/`。

## [Unreleased]

### Added
- **文件制度對齊平台 repo**：新增 `CLAUDE.md`（專案守則＋「Documentation
  Classification & Placement」：L1 Public `docs/<type>/`／L2 Internal `wiki/`／
  L3 Confidential gitignored 三級分類、type 分類表、跨 repo 指標慣例、vendored
  快照內的文件不在本 repo 修改）、`CONTRIBUTING.md`、`SECURITY.md`（回報管道、
  範圍、發布產物驗簽方式）、`docs/README.md`（公開文件索引）與 `README.en.md`。
- `.gitignore` 預留 `commercial/`、`research/` 兩個 L3 樹（與平台 repo 同慣例）；
  設計文件若日後複製進來只能落在這裡。

### Changed
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

### Removed
- `meta-duduclaw/recipes-duduclaw/duduclaw-sysd/PLAN.md`：Y1-2 時期的「尚未實作」
  占位文件，但同目錄的 `duduclaw-sysd_1.62.0.bb` 早已建置驗證通過，內容與事實相反。

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
