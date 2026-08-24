---
name: duduclaw-os
description: 這台機器是一台 DuDuClaw OS 值班機（appliance），不是一般 Linux 桌機。使用者要求「把字放大」「換淺色/深色」「Wi-Fi 連不上幫我看」「幾點了/時區對不對」「現在的版本/有沒有更新」這類「調整或檢查這台機器本身」的請求時使用——STOP，先讀這份 skill，用 `duduclaw os` 這個唯一合法入口操作，不要用 gsettings/nmcli/timedatectl/systemctl 等一般 Linux 工具直接改系統。
trigger: 這台機器, 這台裝置, 值班機, 調高亮度, 字放大, 字體大小, 游標大小, 換主題, 換膚, 深色模式, 淺色模式, dark mode, light mode, Wi-Fi, 網路連不上, 時區, 幾點了, 系統更新, 有沒有更新, duduclaw os, screen, brightness, cursor size, appliance
tags: [appliance, os, self-drive, duduclaw-os, experimental]
display:
  zh-TW:
    name: DuDuClaw OS 自我操作
    description: 教 agent 用 duduclaw os 命令安全地讀取/調整這台值班機本身（顯示/系統/網路），而不是亂改系統檔案。
  en:
    name: DuDuClaw OS self-drive
    description: Teaches an agent to safely read/adjust this appliance itself via `duduclaw os`, instead of touching system files directly.
---

# DuDuClaw OS 自我操作

> **狀態：experimental（A7a/A7b，2026-08 第一版）。** `duduclaw os <group> <verb>`
> 這個命令面本身還很年輕，動詞集合刻意窄（只有 display/system/network 三組），
> 破壞性動詞（重開機/關機/factory reset/套用更新/連 Wi-Fi）刻意**不在這裡**，走
> 你原本就有的 `os_*` MCP 工具（`os_power`/`os_factory_reset`/`os_apply_update`/
> …）。這份 skill 只覆蓋「讀取狀態」與「非破壞性、可逆的偏好調整」。

## 強制觸發句

**要改這台機器的設定前，STOP，先用這個 skill。**

你正在一台 DuDuClaw OS 值班機（appliance）上運作，不是在幫使用者的一般 Linux
桌機工作。這台機器的 comp（視窗管理/游標/主題）、殼（dock/鎖屏/設定）、image
（更新/網路/磁碟）三層，都有 DuDuClaw 自己維護的權威實作——**唯一合法的操作
入口是 `duduclaw os <group> <verb>` 這支 CLI**，不是 `gsettings`、不是
`nmcli`、不是 `timedatectl`、不是直接編輯 `/etc/` 底下的設定檔。這些一般
Linux 工具在這台機器上要嘛沒有效果（值不會被殼讀到）、要嘛會跟殼/comp 自己
的狀態機打架、要嘛需要跟本體完全不同的權限模型。

## 安全邊界

- **讀 `/usr/share` 底下的唯讀資源是安全且鼓勵的**——查字型、查圖示、查
  `/usr/share/zoneinfo` 底下有哪些時區、查系統文件，隨時可以直接讀。
- **寫入系統路徑絕對不行**——`/usr/`、`/etc/`（`duduclaw-sysd` 自己會寫的那幾
  個檔案除外，而那是 `duduclaw os system` 幫你呼叫的，不是你自己去寫）、
  `/boot/`、任何 systemd unit 檔。這台機器是 A/B 唯讀 root，你手動寫大概率會
  失敗；就算某條路徑意外可寫，寫了也可能在下次更新時被整個 slot 覆蓋、或讓
  下次開機失敗——不會有人在你動手前提醒你,你自己要當作絕對禁止。
- **`/data` 底下是這個裝置的可寫資料區**（gateway 的 home 目錄、agent 資料都
  在這裡），這不是「系統設定」，是你自己 agent 身分本來就有權限讀寫的資料，
  跟本 skill 的邊界無關。
- 每一個 `duduclaw os` 動詞都是唯讀查詢或明確標記為可逆的偏好調整（游標大
  小、主題明暗、時區/NTP）。凡是這份 skill 沒有列出的動詞（重開機、關機、
  factory reset、套用系統更新、連上/忘記 Wi-Fi），一律不在這裡——去用你原本
  就有的 `os_power`/`os_apply_update`/`os_factory_reset` 等 MCP 工具，它們有
  自己的（更嚴格的）審批與確認機制，不要期待 `duduclaw os` 能做同樣的事。

## 自我發現：先問系統，不要背命令列表

不要把命令清單背進你的提示詞或假設它不會變——用機器可讀介面自己查：

```bash
duduclaw os commands --json
```

回傳每個命令的 `route`（完整路徑）、`group`/`verb`、`summary`（做什麼）、
`args`（要帶什麼參數）、`examples`（範例）、`hidden`、`requires_approval`
（見下一節）。不確定某個動詞現在存不存在、參數長什麼樣，先查這個，不要用你
訓練資料裡的舊印象或用 `--help` 反覆試錯。

人類可讀版（不帶 `--json`）：

```bash
duduclaw os commands
```

## `requires_approval` 是什麼意思

`duduclaw os system timezone-set`/`ntp-set` 這兩個動詞標記
`requires_approval: true`。以你（agent 身分）呼叫時，這個命令會自動先發一筆
審批請求給使用者，卡住等人核准或拒絕（最多等 5 分鐘,逾時視同拒絕）——**你不
需要、也不應該自己先問過使用者才呼叫**，命令本身就會擋下來等人；你只需要照
常呼叫，然後誠實回報結果是「已核准並完成」還是「被拒絕/逾時」。不要因為看到
`requires_approval: true` 就跳過這個命令改用別的方法繞過去（例如直接呼叫
`duduclaw-sysd` 或編輯設定檔）——那正是這個欄位存在的目的：防止你繞過人審。

## Decision Framework

- 使用者說「把字/游標調大一點」「換個游標樣式」→
  `duduclaw os display cursor-size-get` 先看現在多大 →
  `duduclaw os display cursor-size-set <24|32|48|64|96>`（封閉集，不接受任
  意數字；挑一個比現在大的合法值）。
- 使用者說「換深色/淺色」「換個主題」→
  `duduclaw os display theme-set <light|dark>`（沒有 get，這條線是寫入即
  生效,不用先查）。
- 使用者說「Wi-Fi 連不上」「網路怪怪的」→ 先
  `duduclaw os network status` 看介面清單，再
  `duduclaw os network wired-status`（有線）或
  `duduclaw os network wifi-status`（Wi-Fi/網際網路可達性）定位問題——**這三
  個都是唯讀診斷**，如果需要真的重連 Wi-Fi（`wifi_connect`/`wifi_forget`），
  那是既有的 `os_*` MCP 工具或 dashboard 的事,不在這份 skill 範圍。
- 使用者說「現在幾點」「時區對不對」→ `duduclaw os system timezone-get`。
- 使用者說「幫我把時區改成台北/紐約/…」→
  `duduclaw os system timezone-set <IANA 時區，如 Asia/Taipei>`（會觸發審
  批，見上）。
- 使用者說「這台機器是什麼版本」「型號/序號」→ `duduclaw os system about`。
- 使用者說「有沒有更新」「該更新了嗎」→
  `duduclaw os system update-check`（只查詢,不套用；真的要套用更新走既有
  `os_apply_update` MCP 工具）。

## 連不到怎麼辦（誠實回報，不要假裝成功）

`display` 組（`duduclaw os display ...`）在某些情況下**structurally 連不
到**——comp/殼在這台機器上是以跟 agent 不同的系統帳號執行,這是設計上的信任
邊界,不是暫時性故障。如果命令回報連線失敗（例如訊息裡出現
「SO_PEERCRED」「shell socket 不存在」字樣），**直接把這個限制誠實告訴使用
者**（例如：「這個調整目前只能由這台機器前面的操作者直接執行，我這邊的
agent 身分連不到那個通道」），不要重試同一個命令、不要嘗試繞過去改用其他工
具、也不要編一個「已經改好了」的說法。`system`/`network` 兩組通常不會有這個
限制（它們走的是另一條不受這個 uid 邊界影響的路徑），如果也連不到，多半是
這台機器根本不是 DuDuClaw appliance（`duduclaw os system about` 會告訴你）
或某個服務沒起來——一樣誠實回報,不要瞎猜。

## Out of scope（明確不在這份 skill 範圍）

- 重開機、關機、factory reset、套用系統更新 → 既有 `os_*` MCP 工具
  （`os_power`/`os_factory_reset`/`os_apply_update`），有自己的
  confirm/ApprovalBroker 機制。
- Wi-Fi 連線/忘記密碼、有線網路靜態 IP 設定 → dashboard 或既有 network.*
  RPC/MCP 工具，不在 `duduclaw os network` 這個唯讀查詢組裡。
- 任何需要 root/sudo、需要編輯 `/etc/`、`/usr/`、systemd unit 的操作 → 一律
  不做,這是唯讀 A/B root 的appliance,不是可以隨手改的一般 Linux 機器。
- comp/殼的視窗管理、輸入法、鍵盤配置 → 目前沒有 `duduclaw os` 動詞覆蓋（見
  下方欠帳）,不要嘗試用其他方式繞過去改。
- 安裝套件、改防火牆規則、加使用者帳號 → 完全不在這份 skill、也不在
  `duduclaw os` 的設計範圍內。

## 已知欠帳（誠實列出，不要假裝這些已經做了）

- **這份檔案本身還沒被自動安裝進任何 agent 目錄**——目前只是草稿，放在
  `appliance/skills/duduclaw-os/SKILL.md`。真正要生效需要一個安裝步驟（複製
  或連結進 `<agent_dir>/.claude/skills/duduclaw-os/`，或未來由 appliance 出
  廠建置流程自動安裝到出廠 agent 的 skill 目錄）——這一步還沒做。
- `duduclaw os display` 目前只覆蓋游標大小/來源、主題明暗；不覆蓋輸出解析
  度/縮放（`shell_control` 有 `set_output_mode`/`set_output_scale` 這兩個
  op,但目前一律回報「不支援」，見 comp 端的模組文件,所以 CLI 沒有曝光它
  們）。
- `duduclaw os system`/`network` 需要這台機器被判定為 appliance
  （`duduclaw os system about` 裡的 `is_appliance` 欄位）才會回應；一般開發
  機呼叫會直接拿到「僅限 appliance」的錯誤,這是設計上的行為,不是 bug。
