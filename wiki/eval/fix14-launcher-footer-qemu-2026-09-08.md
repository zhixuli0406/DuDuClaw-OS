# fix14 — shell 快照 v1.63.0（Launcher 頁腳「⌘K 隨時喚起」）QEMU 驗證（2026-09-08）

> L2 內部紀錄。對應 commit：平台 `50b5acc0`／`830191c1`／`35e99e89`，OS `73ab67b`／`b81ba3f`（＋本輪未 commit 的 `duduclaw-cli` recipe `-j 1`）。
> 主機：macOS，QEMU 10 TCG（`-accel tcg,thread=multi -smp 6 -m 4096`），builder 容器 `duduclaw-yocto`（4 vCPU、12 GB、`/yocto-vmfs` 89 GB）。

## 1. 為什麼有這一輪

demo 錄製時誤判「解鎖後 Launcher 叫不出來」是 shell bug；查證後（comp 日誌＋錄影幀＋四組受控重現）確認是量測錯誤，
真正的缺陷是 Launcher 頁腳文案「Super 鍵隨時喚起」——整個堆疊沒有綁定單擊 Super（comp 只處理 Super+字母、shell 綁 `cmd-k`、
文件寫 Cmd+K）。平台 `50b5acc0` 把文案改成「⌘K 隨時喚起」並加測試；這一輪把它烤進映像。

## 2. 烤製過程（七次才過，每次的坑都固化了）

| # | 結果 | 根因 | 固化 |
|---|---|---|---|
| 1 | `duduclaw-shell do_compile` exit 101：`Unable to update https://github.com/zed-industries/zed … offline mode (--frozen)` | 平台 bump 到 1.63.0 時 `release.sh` 只改各 detached crate 自己在 lock 裡的版本項，`crates/duduclaw-shell/Cargo.lock` 裡的 sibling 路徑依賴 `duduclaw-native-gui` 留在 1.62.0；`refresh-src.sh` 照樣 vendor，`cargo build --frozen` 不能自行同步 lock → 把 native-gui 的依賴當未鎖定 → 去載入 zed 的 git 來源 | 平台 `35e99e89`：release.sh awk 對 lock 中所有平台 crate 項改版本；OS `b81ba3f`：refresh-src.sh 版本不一致就拒絕 vendor |
| 2、3 | `duduclaw-cli do_compile` exit 101，rustc `(signal: 9, SIGKILL)`，無診斷 | `cargo.bbclass` 的 `CARGO_BUILD_FLAGS` 沒有 `-j`，cargo 照 nproc 開 rustc；`PARALLEL_MAKE`／`BB_NUMBER_THREADS` 都管不到 cargo；gateway lib 與 cli 兩支大 rustc 並行在 12 GB 容器被 OOM 殺 | `duduclaw-cli_1.62.0.bb`：`CARGO_BUILD_FLAGS:append = " -j 1"`（本輪，未 commit） |
| 4 | 同上（recipe 補丁的 python 因既有 `CARGO_BUILD_FLAGS:append` 行 assert 失敗、沒寫入，烤製卻照起） | 我的腳本錯誤 | 停掉重來 |
| 5、6 | `do_image_wic`／`-c clean` 都 `No space left on device` | `/yocto-vmfs` 89 GB 滿：`duduclaw-image-appliance` 舊 work 34 GB、test 映像 work 29 GB、deploy 裡未壓縮 26 GB `.wic`（test 映像 `IMAGE_FSTYPES = "wic"`，wic 檔 26 GB） | 手動清 work／deploy；正式版 appliance 的 26 GB wic 以 symlink 移到 `/workspace`（host 掛載）讓 wic.zst 轉檔與 ISO 組裝有空間 |
| 7 | test 映像完成；ISO 另烤（見 §4） | — | — |

其他觀察：`bitbake -c clean` 在 `/tmp` 同卷滿時自己也會失敗；`pkill -f "bitbake …"` 會殺掉呼叫它的 shell（要用 `deca[f]bad`／`bitbak[e]` 這種自我排除的 pattern）；
kas `-c "bitbake -e"` 會排隊等正在跑的 bitbake，別在烤製中查變數。

## 3. QEMU 驗證（appliance-test 映像）

- 產物：`artifacts/demo/fix14-test.wic.zst`（2.38 GB；容器內 `zstd -T4 -3` 壓自 deploy 的 26 GB wic）→ `qemu-img convert` 成 qcow2 開機。
- 流程：開機 → OOBE 語言畫面（約 3 分鐘）→ 首次設定走完（帳號 M／11111111、Claude 貼一把 demo 金鑰、Express 板模）→ 桌面「早安，M」→ `Super+K` 35 秒後 Launcher 出現 → 點「瀏覽器 安裝」讓面板變短 → 頁腳可見。
- 證據（`artifacts/demo/fix14-verify/`，gitignored）：`oobe-account.png`、`desktop.png`、`launcher.png`、`launcher-footer.png`——最後一張右下角讀到「⌘K 隨時喚起」。
- `/etc/os-release`：`VERSION_ID=1.62.0-y1-bringup`（`duduclaw-platform-version.inc` 未動；shell 是 1.63.0、cli／comp 仍 1.62.0，混版本，待整體快照更新對齊）。
- 量測提醒：TCG 下帳號欄位打字在主機同時烤映像時會掉鍵（第一次「M」與 7 個密碼字元沒進去），放慢到每鍵 1.5 秒才穩。

**判定：PASS**——修正已進 appliance-test 映像，且在真實開機的 shell 上以畫面確認。

## 4. 安裝器 ISO（live-desktop）

- 產物：`artifacts/demo/fix14-installer-desktop.iso`（2.66 GB，sha256 `e96311882bb40be1…`），deploy 名 `duduclaw-image-live-desktop-duduclaw-qemux86-64.rootfs-20260908113302.iso`。
- 內嵌的安裝 payload 是同一輪重烤的 `duduclaw-image-appliance`（同一份 shell 1.63.0 套件；appliance 的 26 GB wic 在轉 wic.zst 時暫放 host 掛載、烤完已刪）。
- **這次沒有用 ISO 走完整安裝流程再開機**（TCG 下安裝約 35 分鐘＋首次開機）；shell 修正的活體驗證以 §3 的 appliance-test 映像為準。ISO 本身的安裝流程上一次驗證是 fix13（`desktop-iso-qemu-walkthrough-2026-09-05.md`＋ demo 錄影），本輪只有 recipe 未改的 shell／cli 套件與 payload 更新。

**判定：BUILT, NOT BOOTED**。

## 5. 續：平台快照全面同步 v1.63.0（同日下午）

拍板「OS gateway 要跟主 repo 同步」後，把 cli／comp／sysd 三份快照也更新到平台 v1.63.0（830191c1 ＋ 35e99e89），
`duduclaw-platform-version.inc` 1.62.0→1.63.0，四個 recipe 改名 `_1.63.0.bb`，dashboard `dist/` 依 111d748b 重建後 vendor。
四份快照的 crates.io 依賴集合與 1.62.0 完全相同，`*-crates.inc` 未動。

再踩一坑：`duduclaw-comp do_compile` 死於 `failed to select a version for the requirement smithay = "^1.63.0"`——平台 `release.sh` 的 bump
用 `sed 's/^version = "<semver>"/…/'` 掃整個檔案，把 comp `[dependencies.smithay]` 表格裡的 `version = "0.7.0"` 也改成 1.63.0
（shell 的表格依賴寫的是 `"1"`／`"0.4"` 這種不完整 semver 才沒中）。修法：Cargo.toml 還原 0.7.0；release.sh 改成只改
`[package]`／`[workspace.package]`／`[project]` 區段內第一個 version 行（awk，含測試）。

**QEMU 驗證（appliance-test，`artifacts/demo/v163-test.wic.zst`，證據在 `artifacts/demo/v163-verify/`）**

| 檢查 | 結果 |
|---|---|
| 開機到 OOBE → 走完 → 桌面 | PASS（帳號 M、Claude demo 金鑰、Express 板模） |
| `/etc/os-release` `VERSION_ID` | `1.63.0-y1-bringup` |
| `duduclaw --version` | `duduclaw 1.63.0` |
| A/B 開機鏈 | `bootctl status` Current Entry `duduclaw-os_1.63.0-y1-bringup.efi`；`/boot/EFI/Linux/` 有 `duduclaw-os_1.63.0-y1-bringup.efi` ＋ `duduclaw-os-rescue.efi`；root `/dev/vda2`、`/data` `/dev/vda4` |
| Launcher 頁腳 | 「⌘K 隨時喚起」（`launcher-footer.png`） |

量測提醒：`duduclaw-shell --version` 不存在——它會直接再啟動一個 shell（`[main] starting duduclaw-shell S0`），別在 serial 上這樣探版本，用 `grep -a` 二進位或 os-release。

**安裝器 ISO（v1.63.0）**

- 產物：`artifacts/demo/v163-installer-desktop.iso`（sha256 `f758cc8b3e5a2d65…`，deploy 名 `duduclaw-image-live-desktop-duduclaw-qemux86-64.rootfs-20260908125313.iso`），內嵌同輪的 `duduclaw-image-appliance` 1.63.0 wic。與 §4 相同：**BUILT, NOT BOOTED**（沒有跑完整安裝流程），shell／gateway／A/B 鏈的活體驗證以上表的 appliance-test 映像為準。

## 6. `release-os.sh smoke`（repo 定義的 QEMU 測試）— v1.63.0 appliance

`scripts/release-os.sh smoke v0.1.0 --image duduclaw-image-appliance --timeout 1500`：在 builder 容器裡 `runqemu … nographic serial wic ovmf slirp`
開 12:53 烤出的正式 appliance wic（ISO 內嵌的那份），等 serial 出現 login 提示。**PASS，約 145 秒到 login**（x86-64 TCG 跑在 aarch64 容器裡）。

在能跑到這一步之前，smoke 本身修了三處（都在 `scripts/release-os.sh`，CHANGELOG Fixed 有記）：

| 症狀 | 根因 | 修法 |
|---|---|---|
| 印出橫幅後靜默 exit 1 | `set -e` 下 `docker exec … pgrep …; rc=$?`：pgrep 沒比對到（正常閒置）回 1 就終止腳本；builder 並行檢查那處也一樣 | `|| rc=$?` |
| runqemu 立刻退出「Native sysroot directory … qemu-helper-native/… doesn't exist」，smoke 卻等滿 20 分鐘 | rm_work 把 helper 的 work 目錄刪了；輪詢只看 login | 啟動前 `bitbake -C addto_recipe_sysroot qemu-helper-native`（`-C` 強制，`-c` 因 stamp 還在會判定不用重做）；`duduclaw-os.yml` 加 `RM_WORK_EXCLUDE += "qemu-helper-native"`；輪詢看到 `runqemu - ERROR` 立即失敗 |

注意這個 smoke 只證明「開機到 serial login 提示」，桌面／gateway 的活體驗證仍以 §3、§5 的 test 映像走查為準。
