# 把 OS 對齊到一個平台版本（`scripts/sync-platform.sh`）

DuDuClaw OS 映像裡跑的 gateway（`duduclaw-cli`）與 sysd 是平台 repo
（`zhixuli0406/DuDuClaw`）的 Rust crate，以「快照」形式 vendor 在
`meta-duduclaw/recipes-duduclaw/<name>/files/<name>-src/`。compositor（`duduclaw-comp`）
與 shell（`duduclaw-shell`＋`duduclaw-native-gui`）自 2026-09-29 起住在**本 repo** 的
`crates/`（平台功能盤點 S16-B：它們本來就是平台 workspace `exclude` 的獨立 crate，平台沒有任何
crate 依賴它們），快照同樣放在各自 recipe 的 `files/`，但來源是本 repo、不跟平台版本走。
平台每出一版，OS 這邊要做的事是固定的四步，`scripts/sync-platform.sh` 一次做完：

1. 用 `duduclaw-cli`／`duduclaw-sysd` 各自的 `refresh-src.sh` 從平台 checkout 重新產生快照
   （`duduclaw-comp`／`duduclaw-shell` 的 `refresh-src.sh` 同一趟也會跑，但讀的是本 repo `crates/`，
   覆寫路徑用 `DUDUCLAW_OS_SRC_ROOT`，不吃 `DUDUCLAW_CLI_SRC_ROOT`）；
2. 把 `meta-duduclaw/conf/distro/include/duduclaw-platform-version.inc` 改成該版本
   （它連動 `DISTRO_VERSION`、os-release 的 `VERSION_ID`、UKI 檔名、A/B loader 項），
   兩個平台 recipe 檔名改成 `<name>_<版本>.bb`，引用這些檔名的註解一併更新
   （comp／shell 的 recipe 檔名保留自己的 PV，不隨平台版本改）；
3. 比對每份快照的 crates.io 依賴集合有沒有變（變了就得重生 `*-crates.inc`）；
4. 在 `CHANGELOG.md` 的 `[Unreleased]` 放一段 `### Changed` 樣板，列出帶進來的平台 commit。

OS 自己的 release 版本（repo 根目錄 `VERSION`，0.x 直到 GA）不在此腳本的範圍，
兩條線是解耦的：平台版本決定映像裡跑什麼，`VERSION` 決定 GitHub Release 的 tag 與產物檔名。

## 用法

```bash
# 平台 checkout 要在同層（../DuDuClaw）或用 --src-root 指定，且已 checkout 到該版本
git -C ../DuDuClaw checkout v1.63.0

scripts/sync-platform.sh 1.63.0 --check   # 只跑防呆，不改任何東西
scripts/sync-platform.sh 1.63.0           # 真做
```

選項：`--src-root PATH`（平台 checkout 路徑，等同環境變數 `DUDUCLAW_CLI_SRC_ROOT`）、
`--check`（只驗證）、`--no-web-build`（dashboard dist 過期時不自動 `npm run build`，改為失敗）、
`--force`（接受平台 checkout 裡未提交的變更被 vendor 進來）。

## 它會擋下什麼（都是 2026-09-08 手動做時真的踩到的）

| 防呆 | 沒擋會發生什麼 |
|---|---|
| 平台 checkout 的 `[workspace.package] version` 不是你要的版本 | vendor 到錯的程式碼 |
| 平台 `crates/`、`web/`、`Cargo.*` 有未提交變更（`--force` 可放行） | 快照混進沒進版控的東西 |
| 本 repo `crates/` 三個 detached crate 的 `Cargo.lock` 與 `Cargo.toml` 版本不一致（含 shell lock 裡的 `duduclaw-native-gui`） | bitbake 的 `cargo build --frozen` 無法自行同步 lock，改去要 zed 的 git 來源而離線失敗 |
| 某個相依表格（`[dependencies.xxx]`）的 `version` 被改成平台版本 | comp 的 smithay 被改成 `^1.63.0`，編譯死在版本解析 |
| `crates/duduclaw-dashboard/dist/` 比 `web/` 最後一次 commit 舊 | cli 快照把舊的 dashboard 靜態檔烤進映像 |

對齊到 **2026-09-29 之後**的平台版本時多一步：`meta-duduclaw/recipes-duduclaw/duduclaw-cli/duduclaw-cli_<版本>.bb`
裡 `CARGO_BUILD_FLAGS` 要換成帶 `app-compat` 的那行（檔內已備好註解掉的替換行）。平台把 `duduclaw compat`
子命令族改成了預設不編的 feature，而本 image 的殼與 `compat.d/windows-vm.toml` 都會呼叫它；不換的話對齊後的 image 會少掉這個子命令。

跑完後若 crates.io 依賴集合有變，腳本會以 exit code 2 結束並列出 recipe：
`duduclaw-cli` 用 `kas shell … -c 'bitbake -c update_crates duduclaw-cli'`，
`duduclaw-comp`／`duduclaw-sysd` 用各自目錄的 `gen-crates-inc.py`，做完再烤。

腳本可重複執行：同一版本再跑一次不會產生任何差異（每份 refresh 的輸出都是確定性的；sysd 的 flattened Cargo.toml 標的是平台 commit，不是產生時間）。

## 之後

1. `git diff` 看一遍，改 CHANGELOG 樣板的措辭。
2. 烤映像，一次一個（build 卷 89 GB，兩個映像一起烤會滿）：
   `bitbake duduclaw-image-appliance-test`，再 `bitbake duduclaw-image-live-desktop`。
   `duduclaw-cli` 的 recipe 已固定 cargo `-j 1`，gateway 大 crate 不會再和別的 rustc 搶記憶體。
3. QEMU 開 test 映像驗：`/etc/os-release` 的 `VERSION_ID`、`duduclaw --version`、
   `bootctl status` 的 Current Entry 是新的 UKI 檔名。實例見
   `wiki/eval/fix14-launcher-footer-qemu-2026-09-08.md` §5。
4. commit（快照更新與版本對齊一個 commit，其他修正另拆）。
