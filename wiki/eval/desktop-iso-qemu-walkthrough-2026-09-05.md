# 桌面版安裝器 ISO：QEMU 全流程走查（2026-09-05）

> L2 驗收紀錄。在 macOS 主機（Apple Silicon，qemu-system-x86_64 11.1，TCG 全軟體模擬）
> 開一台 VM，從 `duduclaw-os-installer-desktop-duduclaw-qemux86-64-v0.1.0.iso` 開機、走完
> 圖形安裝精靈、寫入 32 GB 虛擬碟、移除安裝媒介重開、進桌面版；全程以 QMP 送鍵盤／滑鼠事件
> 並每秒抓一張畫面，剪成 demo 與宣傳短片。工具與畫面在 `artifacts/demo/`（gitignored）。

## 結果總表

| 階段 | 結果 | 備註 |
|---|---|---|
| ISO 開機 → live 環境 → 安裝精靈 | PASS | 開機到殼渲染約 4 分鐘（TCG） |
| 精靈七步：語言／Wi-Fi／帳號／外觀／選碟／確認／寫入 | PASS | 全部用滑鼠點擊＋鍵盤輸入完成；暗色主題即時換膚 |
| 寫入桌面版映像（24 GB 稀疏 wic，zstd 串流 dd） | PASS | 72 分鐘（TCG 解壓為瓶頸）；`pv` 進度正常；結尾修 GPT 備援標頭 |
| 「移除安裝媒介後重開」→ 從目標碟開機 | PASS | 以只掛目標碟的方式重啟 VM 模擬拔 USB |
| 首次開機：A/B 佈局、/data bind、遷移器、殼啟動 | PASS | 直接進桌面（精靈已收集語言／帳號／主題，OOBE 跳過）；安裝時選的暗色主題已套用 |
| 鎖定畫面顯示操作者帳號、密碼解鎖 | PASS | 帳號 `DuDu`＝安裝精靈輸入；密碼＝精靈輸入 |
| Cmd+L 鎖定 → 解鎖 | PASS | |
| 交辦列輸入（launcher／delegation palette） | PARTIAL | 能開、能打字，但受注音輸入法與合成鍵盤時序影響（見下） |
| 通知中心、控制中心（dock 鈴鐺／齒輪） | 未驗證 | 以 QMP 合成點擊 12 秒內無面板出現；未確認真實滑鼠是否相同 |

## 抓到的問題（依嚴重度）

1. **選碟清單把安裝光碟本身列為候選**：`/dev/vdb 1.8G`（virtio cdrom＝ISO）與目標 `/dev/vda 32G` 並列，
   使用者可能選錯。安裝器應排除唯讀／光碟／目前 live 媒介所在裝置。
2. **主畫面問候語與任務卡是假資料**：`晚上好，Louis`、三張任務卡、今日摘要皆為 `fake_data.rs` 占位內容；
   鎖定畫面卻正確顯示 `DuDu`。出貨前主畫面要接真實帳號與真實任務。
3. **時鐘不一致**：鎖定畫面顯示 `17:16 9月4日`，選單列顯示 `22:58`；`systemd-timesyncd` 在首次開機
   連續失敗（slirp 網路下 NTP 不可達）。兩處時區／時間來源要統一。
4. **輸入法附著時序**：palette 開啟後數秒 fcitx5 才附著，之後預設為注音（Chewing）模式；
   在此之前鍵入的字元直接進文字欄、之後的字元被當注音。Shift 無法切回英文，Ctrl+Space 可停用。
   繁中系統合理預設中文，但 launcher／交辦列這種以命令與英文為主的輸入面，建議預設英文或記住上次狀態。
5. **鎖定後解鎖，click＋打字不再開啟 palette**（第一次開機、未鎖定前可以）。疑似鍵盤焦點留在鎖定畫面的
   輸入元件；需真機用實體鍵盤複驗。
6. 進度畫面一開始短暫顯示「進度未知（無 pv）」，數秒後才變成百分比；文案應改為「準備中」。
7. 從硬殺（未正常關機）狀態重開後，殼花了 8 分鐘以上才渲染；正常關機後重開約 2 分鐘。未查根因（TCG 下難分辨）。
8. QEMU 11.1 在 `-device virtio-keyboard-pci` 上以 QMP `input-send-event device=vkbd` 送鍵會讓 QEMU 直接結束
   （宿主端問題，非 OS 問題）；USB HID 鍵盤在 TCG 負載下會掉 key-up 造成按鍵重複，需每字 1 秒間隔。

## 修復狀態（2026-09-05，重烤四次後的 fix4 映像：`artifacts/demo/fix4-*`）

修法細節見平台 repo `CHANGELOG.md [Unreleased]`（shell 七項）與本 repo `CHANGELOG.md [Unreleased] Fixed`。
下表的「活體」欄是在同一套 QEMU 工具上重跑得到的結果；沒跑到的就寫沒跑到。截圖在 `artifacts/demo/screens/fix4-*.png`（gitignored）。

| # | 問題 | 修法 | 活體驗證 |
|---|---|---|---|
| 1 | 選碟清單列出安裝媒介 | 安裝精靈改 `lsblk -J` 全樹過濾（rom／唯讀／有掛載點／live 媒介所在碟），偵測失敗顯式提示；文字安裝器補 RO 過濾 | PASS：fix4 ISO 選碟頁只列 `/dev/vda 32G`，下方註「已排除安裝媒介 /dev/vdb」（`screens/fix4-04-iso-disk-picker-excludes-medium.png`）。註：進入選碟頁先顯示「尚未列出磁碟」＋「掃描磁碟」鈕，點一下才列出 |
| 2 | 主畫面假資料 | 問候語＝時段＋真實名稱；任務卡接真實 feed；真時鐘；電池讀 sysfs | PASS：首次設定完成後主畫面「早安，Mina」、空狀態任務卡、時鐘 05:01（`screens/fix4-01-home-greeting-mina.png`） |
| 2b | 名稱在 OOBE 完成當下沒帶進殼（重烤第三版才發現） | 四個完成路徑收斂為 `ShellView::complete_oobe` | PASS：滑鼠點「開始使用」後主畫面與鎖定畫面立即顯示 Mina（先前要重開機才有；`screens/fix4-02-lock-mina.png`） |
| 3 | 時鐘不一致／timesyncd crash-loop | `/data/system/timesync` bind mount | PASS：`Started Network Time Synchronization`，鎖定畫面與選單列時間一致 |
| 4 | 輸入法附著時序 | 未改（見下） | — |
| 5 | 解鎖後交辦列失焦 | 解鎖時立 focus-reclaim 旗標 | PASS：Cmd+L 鎖定 → 密碼解鎖 → 點交辦列開出 launcher 面板（`screens/fix4-03-after-unlock-composer-opens-launcher.png`）；解鎖後第一下點擊曾被略過一次，第二下即開（與精靈「繼續」鈕同一種慢點擊現象） |
| 6 | 「進度未知（無 pv）」文案 | 改「準備中…」（三語） | PASS：按「開始安裝」後前 10 秒顯示「準備中… — [installer] 正在寫入映像到 /dev/vda…」（`screens/fix4-05-iso-progress-preparing.png`） |
| 7 | 硬殺後重開慢 | 未查 | — |
| 新 | 遮罩欄位字元溢出欄外（按鍵自動重複時發現） | Boxed 文字欄加 `overflow_hidden` | 未活體驗證（fix4 烤在此修正之前；快照已同步，要再烤一次）。缺陷截圖 `screens/fix3-06-lock-field-overflow.png` |

### 輸入法：這輪新確認的事實

fix3／fix4 上，帳號頁與鎖定畫面的密碼欄仍會被注音（fcitx5-chewing）攔截：`d`、`u` 之後再打 `d`
會被丟掉（ㄎㄧ 後不能再接聲母，chewing 拒收），連續打同一個字母只留一個。名稱欄反而正常。
這和 W7-3 `ime_focus.rs` 的設計（ASCII 欄位取得焦點時 `fcitx5-remote -s keyboard-us`）不符。
guest 端證據（live ISO 的 root 序列埠，用殼程序自己的 `DBUS_SESSION_BUS_ADDRESS` 查）：安裝精靈密碼欄
聚焦時 `fcitx5-remote -n` 回 `keyboard-us`，也就是切換本身有效；journal 沒有 `[oobe/ime_focus]` 錯誤。
所以「第三個 d 被丟」的根因未定：可能是 chewing 在切換前就接管了第一個輸入情境、也可能只是合成鍵盤在
guest 高延遲下的 key 遺失。**要用實體鍵盤在真機或 VNC 手打一次才能定案**；在那之前不改程式。

本輪為了繞過它，密碼改用純數字（chewing 沒有 preedit 時數字直通）。

### 合成鍵盤（宿主端）

- TCG 下 USB HID 鍵盤（`usb-kbd`）會漏 key-up、打字幾乎不可用；改 PS/2（`i8042`）＋ QMP `send-key`
  （hold-time 5 ms）後每個按鍵可靠進一個字元，但殼在軟體渲染下處理 key-up 慢，仍偶發自動重複；
  驅動腳本改成「每鍵後量測字元數，超出即退格、遺漏即重打」的前綴不變式迴圈。
- 「繼續」鈕第一次點常沒反應（游標移動與按下落在同一批事件，命中測試用舊位置），先 hover 再點即可。

## 第二輪：交辦／共駕／相容層功能走查（2026-09-05 下午，fix4 映像＋root 序列埠測試映像）

在 fix4 appliance（一般映像）上實際操作，再烤一份 `duduclaw-image-appliance-test`（root 序列埠自動登入，
永不出貨）拿 guest 端證據。宿主端工具改用 PS/2 鍵盤＋QMP `send-key`、slirp HTTP（10.0.2.2）把腳本送進 guest。

| 功能 | 觀察到的問題 | 根因 | 修法 |
|---|---|---|---|
| 交辦 | launcher「交辦給 財務助理」是假資料；`agents.list` 回 0 個 agent；按 Enter 後 gateway 有建任務但主畫面仍顯示「還沒有交辦的任務」、無任何回饋；dock 兩位 agent、控制中心「2 位在值」、通知中心「審批 2」與「今天」活動列全是假的 | OOBE「套用 Express」與「AI Runtime 授權」只寫本機旗標；主畫面只查 `in_progress`；多處 `fake_data` 未接真資料 | 殼：OOBE 完成即建立預設「總管助理」、runtime 步驟真的收 API 金鑰（`accounts.add`）、任務 feed 含 todo／needs_human、交辦即發通知卡、agents feed 接 launcher／dock／控制中心／分頁（平台 repo CHANGELOG ①–⑤） |
| 交辦（執行） | 任務停在 `todo`：journal 顯示 goal loop 有派工，但 `error=Claude CLI not found` | appliance 不裝 Claude CLI，agent 預設 `api_mode = "cli"` | gateway：沒有 CLI 就走 Direct API（⑥）；真正執行仍需 Anthropic 金鑰（OOBE 現在可輸入） |
| 共駕 | comp 端 socket 正常（root 直連：auth ok、status 回 mode/frozen）；gateway 端 `codrive_status` 一律「此代理未啟用」 | ① gateway 是 root 服務、無 `XDG_RUNTIME_DIR`、config 無 `[codrive]` → 連不到 socket；② MCP 能力閘門用 `client_id`（`gateway-internal`）當 agent id 讀 agent.toml | OS：provision 範本＋前向遷移補 `[codrive]` 路徑；平台：閘門改以實際 agent 為準（⑦） |
| 相容層 | 瀏覽器「安裝」按了 5 分鐘無下文、無任何回饋；Waydroid 可啟動（出現 Initialize Waydroid 視窗，需下載 Android 映像，未續做）；windows-vm 需 KVM（TCG 下必拒，符合設計） | 映像上沒有 `data` Flatpak 安裝區、沒有任何 remote（Yocto 線遺失 mkosi 的 installations.d 與 setup 腳本），3.4 GB 離線倉庫從未被用；殼的安裝 fire-and-forget | OS：新 `duduclaw-flatpak-setup` recipe（安裝區＋`flathub-offline`＋`flathub`）；殼：離線倉庫優先、等 flatpak 結束後以通知卡回報成功／失敗（⑤） |
| 其他 | Waydroid 初始化視窗的標題列被殼的選單列蓋住（視窗貼齊 y=0） | 未查（comp 放置邏輯） | 未改，列入下一輪 |

### 活體驗證（bake 5，含以上全部修正）

bake 5（含全部修正）的測試映像上：

| 項目 | 結果 |
|---|---|
| Flatpak `data` 安裝區 + `flathub-offline`／`flathub` remote（開機自動註冊） | PASS（`flatpak remotes --installation=data` 列出兩個 remote；setup service 日誌完整） |
| `[codrive]` 設定進 config.toml、遷移腳本隨映像出貨 | PASS |
| OOBE 完成即建立預設 agent | PASS（`agents.list` = `assistant`／總管助理／main） |
| 板模頁改為誠實的 Pro 鎖定提示 | PASS（截圖 `screens/fix5-*`） |
| launcher 交辦卡顯示真實 agent、dock 顯示真實名單（無假 agent） | PASS（「交辦給 總管助理」、dock 只有「總」一顆） |
| AI Runtime 金鑰步驟：空值驗證 | PASS（「請先貼上金鑰」） |
| AI Runtime 金鑰步驟：輸入金鑰→`accounts.add` | PARTIAL：合成鍵盤第一下沒點進欄位、金鑰沒打進去；改從宿主直接呼叫 `accounts.add`／`accounts.list` 驗證 RPC 路徑可用 |
| 共駕 gateway→compositor（`codrive_status` 經 MCP） | PASS（回 `{"ok":true,"codrive":{"mode":"handover","frozen":true,…}}`，之前一律「此代理未啟用」） |
| 相容層：從離線倉庫安裝 Chromium | PASS（guest 端 `flatpak install flathub-offline org.chromium.Chromium` 數分鐘完成、零網路；launcher 安裝鈕走同一條路） |
| 交辦→已交辦卡＋排隊中卡；Direct API 缺金鑰訊息；Chromium 從 launcher 開啟 | 待 bake 6（見下） |

bake 6（含 OOBE 網路頁修正）的測試映像上再跑一輪：

| 項目 | 結果 |
|---|---|
| AI Runtime 金鑰步驟：輸入→儲存→`accounts.list` 出現 `oobe-anthropic` | PASS（截圖 `screens/fix6-*`） |
| 交辦「ABC」→ 通知卡「已交辦」→ 主畫面「排隊中」卡（指派給 assistant）→ dock「總」亮進行中點 | PASS（feed 30 秒同步後出現） |
| 通知中心分頁「進度 1」、假「今天」列消失、「你的第一位 AI 員工已就位」卡 | PASS |
| gateway 派工：沒有 Claude CLI 時改走 Direct API | PASS（日誌 `Direct API`），但接著 `No API key available for Direct API`——Direct API 只讀 env／`[api]`，不讀 `accounts.add` 存的 `[[accounts]]` 金鑰 → 修正進 bake 7 |
| launcher 安裝瀏覽器 | 第一次 FAIL→抓到根因：polkit 規則沒放行 `duduclaw-kiosk`（「Deploy not allowed for user」，由新的安裝失敗卡直接顯示原因）。把修正後的規則即時套進測試機（測試用 rw remount）再按一次：約 3.5 分鐘後「安裝完成」卡、dock 出現 Chromium 圖示（`screens/fix6-04-*`）；規則進 bake 7 |

| 開啟已安裝的 Chromium（dock 圖示） | 第一次 FAIL→根因：`flatpak run` 列舉所有安裝區，`verify` 安裝區目錄 0750 讓 `duduclaw-kiosk` 一路 Permission denied（殼原本 spawn 後不等、只留殭屍行程、無任何 log）。測試機 `chmod 755` 後再點：約 100 秒出現 Chromium 首次執行視窗（`screens/fix6-05-*`）。tmpfiles 改 0755＋殼改為 reap 子行程並記錄非零退出，進 bake 8 |
| 應用視窗貼齊 y=0、標題列被殼的選單列蓋住（Waydroid、Chromium 皆如此） | 未改（comp 放置邏輯），列入下一輪 |

bake 8（最終版，含 polkit／verify 目錄權限／Direct API 金鑰／reap／OOBE 網路頁全部修正）的測試映像上：

| 項目 | 結果 |
|---|---|
| OOBE 全程（含金鑰步驟）→ 主畫面 | PASS |
| 交辦「BC」→ 排隊中卡、dock 狀態點、通知徽章 | PASS |
| gateway 用 OOBE 存的金鑰走 Direct API | PASS：日誌 `Anthropic API error (401 Unauthorized): invalid x-api-key`——占位金鑰被實際送出，換真金鑰即可執行 |
| 以桌面帳號安裝瀏覽器（`flatpak install --installation=data flathub-offline org.chromium.Chromium`，映像內 polkit＋verify 目錄修正、無 hack）→ dock 出現圖示 → 點擊開啟 | PASS（約 4 分鐘裝好、100 秒內出視窗；`screens/fix8-01-*`） |
| launcher 的「安裝」→「開始安裝」UI 路徑 | 第一次同一路徑在 bake 6 已 PASS；bake 8 上兩次都在按到「開始安裝」前 launcher 自己關掉——**新發現**：只要有任何 app 視窗開著（這次是誤點 dock 第一格開了 Fcitx 設定），launcher 打開幾秒內就被關閉（app 視窗搶回焦點）；沒有 app 視窗時 launcher 可停留 47 秒以上。列入下一輪 |
| 通知中心分頁「進度 1」、殭屍行程清掉（bake 8 起 spawn 後 reap） | PASS（`ps` 無 `[flatpak] <defunct>`） |

**bake 5 上新抓到的問題**：OOBE 重跑（殼重啟或狀態被清）時網路頁卡死——gateway 的首次設定網路 API
在 admin 帳號建立後一律回 403，殼把它當「找不到網路服務」。修法：gateway 回明確 `code`
（`first_run_completed`／`not_loopback`／`not_appliance`），殼把「首次設定已完成」視為網路已就緒並顯示
說明文字，直接可按「繼續」。進 bake 6。

## 本輪未涵蓋

- 真機（`duduclaw-genericx86-64`）仍未開機驗證。
- 交辦送出（Enter）：此 VM 未設定 AI 後端，未實際建立目標。
- 通知中心／控制中心／Bottles／Waydroid／Flatpak 應用的開啟。

## 產出

- `artifacts/demo/duduclaw-os-desktop-install-demo.mp4`：全流程 time-lapse（安裝寫碟以 90 秒取一幀加速）。
- `artifacts/demo/duduclaw-os-desktop-promo.mp4`：宣傳短版。
- `artifacts/demo/screens/`：13 張關鍵畫面。
- 驅動腳本（scratchpad，可重建）：`launch_vm.sh`（q35＋OVMF＋virtio cdrom／qcow2 目標碟＋雙 QMP＋cocoa/VNC）、
  `demo_vm.py`（QMP 截圖／按鍵／點擊／錄影）、`make_video.py`（去重、章節卡、字幕、剪除區間、time-lapse 取樣）。
