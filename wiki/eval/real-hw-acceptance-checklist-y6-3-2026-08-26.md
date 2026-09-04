# 真機到貨驗收清單（genericx86-64：N305 / 8845HS mini PC）

> **L2 內部驗收清單（已封存，前提過時）。** 2026-09-04 從 `meta-duduclaw/REAL-HW-CHECKLIST.md`
> 原文不動搬來。本清單寫於 Y6-3、針對 Y6 燒錄包；下列前提已不成立：IME 自 Y7 起已在 image、
> v0.1.0 已有 A/B 更新、唯讀 root＋dm-verity、Secure Boot 與圖形安裝器 ISO。v0.1.0 的驗簽／燒錄／
> 開機步驟以 repo 根 `README.md`「快速開始」為準；真機開機驗證至今仍未做過，這點沒有變。
> 文中 `crates/...` 指 DuDuClaw 平台 repo；`commercial/docs/...` 與 `research/...` 指維護者的
> 私有設計樹，不在本 repo、未公開。

> 產出於 Y6-3（2026-08-26）。目標：硬體到貨當天，照這份清單一步步跑，
> 不需要重新翻文件找指令。每一項都標「預期結果」＋「若不符合怎麼辦」。
> 這是**清單**，不是完整維修手冊——深入除錯請回頭查
> `commercial/docs/TODO-agent-first-os-2026-08.md`（Y1-Y6 各里程的踩坑紀錄）
> 與 `research/native-os-2026-08/`（各項機制的一手調研）。
>
> **誠實前提**：這條 Yocto 線目前只在 QEMU（Apple Silicon host、TCG 全軟體
> 模擬 x86_64）驗證過，從未在真實硬體上開機。清單裡標「⚠️ 未在真機驗證」
> 的項目，PASS/FAIL 都是這次到貨才會第一次產生的資料，不是重跑舊測試。
>
> **這份燒錄包不含 IME（fcitx5/fcitx5-chewing）**——Y6-1 的 fcitx5 recipe
> 建置期撞上真的 C++ 相容性錯誤（`fmt::localtime` 在新版 fmt 12.1.0 已被
> 移除，fcitx5 5.1.12 上游程式碼還在用），本輪為了不讓這個未完成的相依
> 卡死整包燒錄包產出，暫時把 `fcitx5 fcitx5-chewing` 從
> `meta-duduclaw/recipes-core/images/duduclaw-image.bb` 的 `IMAGE_INSTALL`
> 註解掉（recipe 本身沒有動，Y6-1 修完 fmt 相容性問題後直接取消註解、
> 重烤一次即可補上）。§4 IME 那一項按此現實填寫。

---

## 0. 開始前

- [ ] 硬體：N305（Alder Lake-N）或 8845HS（Phoenix）mini PC，兩者共用同一份
      映像（`duduclaw-genericx86-64` machine 的 `x86-64-v3` tune 兩者皆支援；
      `linux-firmware-i915`/`linux-firmware-amdgpu` 兩份 GPU 韌體都在 image
      裡，開機時哪顆內顯生效由實際硬體決定，不用選映像）。
- [ ] USB 隨身碟 ≥ 8GB（映像本體遠小於 Debian 線的 14.5GB，Yocto genericx86-64
      的 `duduclaw-image-flatpak` 目前 rootfs 落地量級是數 GB，見下方「燒錄」
      一節的實際檔案大小）。
- [ ] 一台能跑 `zstd -d`／`dd`／balenaEtcher 的機器（燒錄用）。
- [ ] 網路線（測「網路」項目最少要有一條有線網路可用——見下方 §4 的誠實
      揭露，這條線目前**沒有**確認任何 WiFi 連線管理套件在映像裡）。
- [ ] 螢幕＋鍵盤接到 mini PC（HDMI/DP + USB），或走 serial console（如果
      主機板有 debug UART header）。

---

## 1. 燒錄

```sh
# 解壓縮
zstd -d duduclaw-os-genericx86-64.wic.zst -o duduclaw-os-genericx86-64.wic

# sha256 核對（燒錄前務必核對，比對隨映像附上的 .sha256 檔）
sha256sum -c duduclaw-os-genericx86-64.wic.zst.sha256

# 方式一：dd（先用 diskutil list / lsblk 確認目標裝置代號！燒錯磁碟會整顆覆蓋）
sudo dd if=duduclaw-os-genericx86-64.wic of=/dev/diskN bs=4m status=progress
sync

# 方式二：balenaEtcher（GUI）——Flash from file → 選 .wic → 選 USB → Flash
```

**與 Debian appliance 線（`docs/todo/TODO-H1-ISO-x86-installer.md`）的差異，
沿用其燒錄慣例但有兩點不同，務必注意**：

1. **這不是 A/B 自安裝媒介**——appliance 線的 `.raw` 映像身兼安裝媒介與成品
   （開機自我偵測「可移除媒介＋內建 NVMe」→ 自我 dd 安裝 → 關機，見
   `appliance/mkosi.extra/usr/local/sbin/duduclaw-usb-install.sh`）。**Yocto
   這條線目前沒有等價機制**——`meta-duduclaw/` 裡沒有對應的
   firstboot-install 腳本，這份 `.wic` 就是直接開機跑的完整系統，不會自動
   搬到內建碟。若要「裝到內建 NVMe/SSD」而不是「每次都插著 USB 開機」，
   目前**只能手動**在開機後對內建碟重複同一條 `dd` 指令（從 USB 上跑
   `dd if=/dev/sdX of=/dev/nvme0n1 ...`，`X` 是 USB 自己的裝置節點）——
   這是本輪誠實列出的差異，不是遺漏；等價的自動安裝機制若要做，屬於
   獨立票（比照 appliance 線的 `duduclaw-usb-install.sh` 移植）。
2. **UEFI + Secure Boot 關閉**，理由與 Debian 線相同：`systemd-boot` 鏈的
   UKI 未接 Secure Boot 簽章。開機模式務必是 **UEFI**（非 Legacy/CSM）。

---

## 2. 開機

- [ ] 進 BIOS/UEFI：關閉 Secure Boot、開機模式設 UEFI、開機順序調整為 USB
      優先（或用一次性開機選單）。
- [ ] 從 USB 開機，預期在數十秒內看到 systemd-boot 選單 → 核心啟動訊息
      （或直接跳過選單自動開進 UKI，視 `loader.conf` 逾時設定）→ 進入
      DuDuClaw OS。
- [ ] **預期成功訊號**：serial console 或螢幕上看到品牌開機字串
      `Welcome to DuDuClaw OS`（版本號見映像本身）＋ hostname 正確。
- [ ] 若卡在開機選單或黑畫面超過 2 分鐘：檢查 Secure Boot 是否真的關閉
      （最常見卡點）；檢查開機模式是否誤選 Legacy。
- [ ] ⚠️ 未在真機驗證：QEMU 上的開機序列已用 serial console 完整驗證過
      （`meta-duduclaw/qemu-boot-y1-1-PASS-evidence-2026-08-25.log`），但真機
      的 UEFI 韌體差異（不同主機板廠牌）可能有各自的怪癖，第一次開機留
      多一點觀察時間。

---

## 3. 殼（duduclaw-shell / duduclaw-comp，真 AVX2 裁決）

**這是本清單最重要的一項判定**——Y5-1／Y5-4 診斷過一個持續性的殼崩潰迴圈
（Mesa llvmpipe/lavapipe 的 LLVM JIT 在編某些 AVX2 256-bit 整數指令
——`fs_variant_partial`/`VBROADCAST_LOAD`/`VSRAI`——時產生錯誤程式碼），
**最終裁決是「Apple Silicon host 上 QEMU TCG 全軟體模擬 x86_64」這個組合本身
的編碼期缺陷，判定要靠真機（有實體 AVX2、非 TCG 模擬）才能分辨「QEMU
環境限制」vs「真實 Mesa/LLVM bug」**——這台真機到貨的**第一個、也是最關鍵
的判準**就是這個崩潰迴圈在真實硬體上是否還會發生。

- [ ] 開機後**不要**只看一眼就判定 PASS——蹲點觀察至少 3-5 分鐘（QEMU 上
      量到的崩潰週期是「約每 10-15 秒一次」，`StartLimitBurst=8` 在
      `StartLimitIntervalSec=0`（Y5-4 已修——見下方註）下會不斷重試而非
      permanently failed，真機上若同一個崩潰仍在，畫面會呈現反覆黑屏/
      重繪的抖動感，不是單純卡住）。
- [ ] **PASS 判準**：殼（duduclaw-shell 的 gpui 原生介面）穩定顯示，沒有
      週期性黑屏/重啟抖動。用 `systemctl status duduclaw-kiosk` 核對
      `NRestarts` 是否持續增加（若真機上這個計數穩定不動，代表崩潰迴圈在
      真機上消失，AVX2 JIT 缺陷的裁決落在「QEMU/TCG 環境限制」，不是真實
      Mesa/LLVM bug）。
- [ ] **FAIL 情境**（若真機上仍然崩潰）：代表 Y5-1/Y5-4 的裁決錯了，缺陷是
      真實的 lavapipe/llvmpipe AVX2 codegen bug，不是 TCG 模擬假象——這種
      情況下，kiosk 服務仍會靠 `Restart=always`＋`StartLimitIntervalSec=0`
      的「永不放棄自癒」語意持續重試（Y5-4 修法，值班機語意：寧可一直重試
      也不要永久 failed），畫面會維持抖動但系統不會完全掛死；請完整記錄
      `journalctl -u duduclaw-kiosk -b --no-pager` 供下一輪診斷。
- [ ] 若殼本身完全無法點亮（gpui 面板從未出現過任何畫面，不是抖動而是
      從未成功），改用 §3.1 的 Flatpak Chromium kiosk fallback 檢查（見下）
      判斷至少能不能有一個可用的降級畫面。

### 3.1 Flatpak Chromium kiosk fallback（Y6-3 離線預載，本票新增）

真機首次開機**零網路**的情況下，也應該有一個可用的 Chromium kiosk
fallback 可以手動點亮（尚未接成殼崩潰時的自動降級路徑——那是後續票，
見下方「欠帳」）：

```sh
systemctl start duduclaw-flatpak-kiosk-verify.service
journalctl -u duduclaw-flatpak-kiosk-verify --no-pager
cat /var/log/duduclaw-flatpak-kiosk-verify/duduclaw-flatpak-kiosk-verify.result
```

- [ ] 預期在 result 檔案裡看到 `PASS flatpak-install-offline org.chromium.Chromium`
      （代表吃到了 Y6-3 烤進映像的離線 repo，**完全沒有打網路**）而不是
      `PASS flatpak-install`（代表 fallback 到網路路徑，離線機制本身可能
      有問題，見下方 §6 欠帳）。
- [ ] 若看到 `SKIP flathub-offline-repo-absent`：代表這份映像沒有帶
      Y6-3 的離線 repo 套件（`duduclaw-flatpak-offline-repo` 沒進
      `IMAGE_INSTALL`）——核對這份映像是不是舊版重烤的。

---

## 4. IME（輸入法）

**誠實狀態（Y6-3 收官時點，2026-08-26 稍晚更新）**：Y6-1 的 recipe 已經
落地（`meta-duduclaw/recipes-support/{fcitx5,fcitx5-chewing,libchewing,
extra-cmake-modules}/`），但**建置期撞上真的 C++ 相容性錯誤**——
`fcitx5_5.1.12.bb:do_compile` 失敗於
`src/lib/fcitx-utils/log.cpp:225:27: error: 'localtime' is not a member
of 'fmt'`：fcitx5 5.1.12 上游程式碼呼叫 `fmt::localtime()`，但這條 Yocto
線釘的 fmt 版本是 12.1.0，這個版本已經移除/搬遷了那個相容性 helper——
是 fcitx5 上游與新版 fmt 的版本不相容，不是 Yocto 打包錯誤，需要 Y6-1
自己解（patch fcitx5 原始碼，或釘/patch fmt 版本）。**本輪燒錄包已把
`fcitx5 fcitx5-chewing` 從 `duduclaw-image.bb` 的 `IMAGE_INSTALL` 暫時
註解掉**（recipe 檔案本身沒有動，只是這次沒裝進映像），才讓 image build
能通過 do_rootfs——若不排除，`bitbake duduclaw-image-flatpak` 現在會
100% 在 fcitx5 的 do_compile 卡死。

- [ ] 到貨當天先確認 Y6-1 的 fmt 相容性問題是否已修好；若已修好，取消
      `duduclaw-image.bb` 裡 `# IMAGE_INSTALL:append = " fcitx5 fcitx5-chewing"`
      這行的註解，重烤一次即可，不需要重新設計任何東西。
- [ ] 若到貨當天還沒修好：這一項標記 **SKIP（上游相容性問題未解，非本機
      硬體問題）**，不是 FAIL——不要誤判成本次開機測試失敗。可以手動確認
      鍵盤基本輸入（英數）是否正常（`xkeyboard-config` 已在 Y5-4 之前就
      進了 image，鍵盤事件能正確解析成 keysym）。

---

## 5. 網路

**誠實狀態（Y7-3 更新，2026-08-26，取代 Y6-3 的舊誠實記錄）**：Y6-3
查證時點記錄的缺口（image 裡完全沒有 WiFi 連線管理套件）**已補上**——
`iwd`（meta-oe/recipes-connectivity，client+monitor+systemd
PACKAGECONFIG）＋`wireless-regdb-static`（oe-core 自帶，kernel 直接載入
regulatory.db 用的現代套件，**不是**裸的 `wireless-regdb`——那個名字在
這條線上其實是舊版 crda 導向的套件，二擇一互斥，見
`duduclaw-network-config.bb` 自己的說明）＋新的小 recipe
`duduclaw-network-config`（`recipes-connectivity/duduclaw-network-config/`，
帶 `25-wireless-dhcp.network`，`Type=wlan` 比對＋`RouteMetric=600`，
高於這條線 oe-core 內建 `systemd-conf` 的有線 `RouteMetric=10`，讓有線
優先、無線退居次要，比照 Debian appliance 線 D4a-1 的慣例但數值基準不同，
理由見該 `.network` 檔案自己的註解）都已進 `duduclaw-image.bb` 的
`IMAGE_INSTALL`。韌體（`linux-firmware-iwlwifi`／`-mediatek`／`-rtl-nic`）
Y2-2 已在機器層。gateway 端的 iwd D-Bus client（`network/iwd.rs`）**不需要
任何 Yocto 端改動**——確認與 Debian 線 D4a-3 用的是同一份原始碼，
在這個 Yocto image 的 vendored 快照裡逐位元組相同。

- [ ] **有線網路（優先測這個）**：接上網路線，開機後跑
      `ip addr show` 確認拿到 DHCP IP；`curl -sS http://127.0.0.1:18789/healthz`
      確認 gateway 對外可達（呼應 §6 dashboard 項）。這條路徑走的是
      `systemd-networkd`（`INIT_MANAGER = "systemd"` 已含 networkd，
      oe-core 的 `systemd-conf` 套件內建 `wired.network`，
      `RouteMetric=10`，理論上開箱即通，但**本輪未在真機上驗證過乙太
      網路埠是否真的被 kernel 正確辨識**——列 ⚠️。
- [x] **無線連線管理套件已補齊，QEMU 上已驗證服務本身活著**：
      `systemctl is-active iwd` → `active`；`iwctl device list` 印出正確
      表頭且成功連上 D-Bus（QEMU 無 Wi-Fi 網卡故清單為空，誠實的環境
      限制，見上方「QEMU 驗證記錄」）。真機上若網卡被韌體正確載入，
      `iwctl station <dev> scan` +
      `iwctl station <dev> get-networks` 應該能看到附近熱點；
      `iwctl station <dev> connect <SSID>` 走互動式密碼輸入。
- [ ] **無線連線本身仍是 ⚠️ 未在真機驗證**：套件補齊≠已在真實無線網卡
      上跑過一次完整關聯流程——這條線目前沒有比照 Debian appliance 線
      D4a-9 那樣的 mac80211_hwsim 自動走查（掃描→連線→forget→重開機
      自動重連），到貨當天請按上面的 `iwctl` 指令手動走一次，若失敗
      請完整記錄 `journalctl -u iwd -b --no-pager` 供除錯。
- [ ] `dmesg | grep -iE "iwlwifi|mt7921e|mt7925e|rtl8"`（視主機板實際
      無線網卡而定）：確認韌體正確載入、沒有 firmware-load 錯誤——這是
      判斷「網卡認到了但連不上」vs「韌體本身選錯」的第一道分野。
- [ ] dashboard 的網路設定頁（`os_wifi` 三工具）目前**沒有接到這條
      Yocto 線的 OS 層**——iwd D-Bus client 程式碼雖然共用，但這條線
      尚未做 Debian appliance 線 D4b 那樣的設定頁 UI 串接活測；到貨當天
      請先用 `iwctl` 手動驗證連線能力本身，不要預期設定頁上能操作。
      這是本票故意不擴大範圍的部分，非本票要修，已記入 §8 欠帳。
- [ ] **netdev 群組機制刻意沒有移植**：這是與 Debian appliance 線 D4a-1
      的真實架構差異，不是遺漏——這條線的 `duduclaw-gateway.service`
      目前以 root 執行（Y2-1 拍板，尚未有非特權服務帳號），root 本身已
      能通過 iwd 預設的 D-Bus 政策，不需要額外的 netdev 群組授權。等這條
      線的 gateway 改成非特權使用者執行時，才需要補上 netdev 機制。

---

## 6. 音訊

**誠實狀態（Y7-3 更新，2026-08-26，取代 Y6-3 的舊誠實記錄）**：
Y6-3 查證時點記錄的缺口（image 裡沒有 pipewire／wireplumber／
alsa-utils 任何一個套件）**已補上**——`pipewire`＋`wireplumber`
（來自新加入的 `meta-multimedia` sublayer，見 `kas/duduclaw-os.yml`）
已進 `duduclaw-image.bb` 的 `IMAGE_INSTALL`。**這裡抓到一個真的、如果
沒抓到會讓整個修法悄悄失效的洞**：這條 distro 的 `DISTRO_FEATURES`
沒有 `alsa` 這個 token，而 pipewire 上游 recipe 把「真正讀寫硬體音效卡」
的 SPA ALSA plugin（`PACKAGECONFIG[alsa]`）用
`bb.utils.filter('DISTRO_FEATURES', 'alsa ...')` 閘住——若不處理，
pipewire 會建置成功、`wpctl` 也存在，但**永遠看不到任何一個 sink**，
和「套件根本沒裝」在真機上難以區分卻同樣無法出聲。已用新的
`pipewire_%.bbappend`（`recipes-multimedia/pipewire/`）明確覆寫
`PACKAGECONFIG:class-target` 修正，同時把上游其餘不需要的預設項
（gstreamer／libcamera／jack／avahi／webrtc-echo-cancelling／raop 等）
一併關掉，比照 Debian appliance 線 D5 的「wpctl-only、無 ALSA-app
shim、無 PulseAudio shim、無藍牙」精簡精神，只是在 meson flag 層面做，
比 Debian 只能在 apt 套件層面做能砍得更乾淨。kiosk 使用者
（`duduclaw-kiosk`）已加入 `audio` 群組（stock 群組，一手核對
`base-passwd` 原始碼的 `group.master` 確認 GID 29 存在，無需額外
`USERADD_DEPENDS`）；`duduclaw-kiosk-launch.sh` 已比照 D5 移植
`start_audio_session`（compositor 之前手動起 pipewire→等 socket→起
wireplumber，全程 fail-open）。

- [x] 開機後跑 `which wpctl pipewire wireplumber` 確認存在——**QEMU 上
      已驗證存在**（`/bin/wpctl` `/bin/pipewire` `/bin/wireplumber`）。
- [x] `systemctl is-active duduclaw-kiosk` → **QEMU 上已驗證 `active`**；
      `/run/duduclaw-kiosk/` 下 `pipewire-0`／`pipewire-0-manager`／
      `wayland-1` 均為真實 socket（`srwxr-xr-x`），確認 PipeWire＋
      WirePlumber 真的在 kiosk session 裡跑起來，不是「binary 存在但
      沒人啟動它」。
- [ ] **`wpctl status`（在 kiosk session 內部執行）本輪未達成**——注意
      指令不是 `runuser`（這條線的 busybox `sh` 沒有 `runuser`），也不能
      單靠裸的 `su -s /bin/sh duduclaw-kiosk -c 'wpctl status'`：本輪這樣
      測會回 `Could not connect to PipeWire`（缺 session bus，是這個
      臨時指令本身的限制，不是 PipeWire 沒起來——見上方「QEMU 驗證記錄」
      的說明）。真機到貨當天若要看到真實裝置＋`Sinks:` 清單，走 dashboard
      設定頁的聲音頁籤（會用正確的 session 上下文呼叫 wpctl），或等殼本身
      點亮後直接用控制中心的音量滑桿。
- [ ] 用 dashboard 設定頁的音量滑桿確認能真的調整（`wpctl get-volume`
      前後對照）——需殼本身能點亮，本輪 QEMU 驗證只到 D-Bus/systemd 層，
      未到殼 UI 層（§3 AVX2/TCG 崩潰迴圈裁決尚待真機）。
- [x] `speaker-test` 這條線**沒有** `alsa-utils`（比照 Debian D5 的判斷，
      靠 wpctl 生態不需要它）——改用 pipewire 自帶的 `pw-play`/`pw-cat`
      （本票的 `pipewire_%.bbappend` 已明確開啟 `pw-cat` PACKAGECONFIG，
      二進位應存在，QEMU 上 `which` 已確認存在，實際播放未測——
      `-audiodev none` 下 QEMU 主機本身不出聲，這項要留給真機）。
- [x] **QEMU 層級的音效卡辨識已驗證**：`cat /proc/asound/cards` →
      `0 [Intel]: HDA-Intel - HDA Intel`，`lsmod | grep -c snd` → `7`。
      真機上實際聽到聲音、dashboard 滑桿真的調得動——**仍是 ⚠️ 未在真機
      驗證**，見下方 QEMU 驗證記錄的「QEMU 環境天花板」說明。

---

## QEMU 驗證記錄（Y7-3，2026-08-26）

**狀態：COMPLETE（QEMU 層級）**。在 `duduclaw-qemux86-64` 機器上完整重烤
`duduclaw-image`（`kas shell meta-duduclaw/kas/duduclaw-os.yml -c "bitbake
duduclaw-image"`，`Tasks Summary: Attempted 7497 tasks ... all succeeded`），
用獨立於既有兩台常駐 VM（47023／47025，未觸碰）的私有 QEMU 實例
（serial 47031→47033、qmp 47032→47034、dashboard 18798→18799，兩輪，見下）
在真實序列主控台上逐項活測，不是讀 log 推論。

**第一輪活測（修 kernel-modules 之前）揪出兩個真的、會讓整個修法悄悄
失效的洞**（兩者都不是網路/音訊套件本身的問題，是同一類「kernel
.config 有开但沒打包成 image 裡的模組」的缺口）：
1. `systemctl is-active iwd` → `failed`；`journalctl -u iwd` 明說
   `No HMAC(SHA1) support found` 等一長串 crypto 缺失，並列出
   `CONFIG_CRYPTO_USER_API_HASH` 等一串「kernel 缺少的選項」。順著查
   `/proc/config.gz` 才發現這些其實**都有**開（`CONFIG_CRYPTO_AES=y`
   `CONFIG_CRYPTO_USER_API_HASH=m` 等）——只是編成**模組**，而模組檔案
   `algif_hash.ko`/`algif_skcipher.ko` 根本沒被打包進 image
   （`modprobe algif_hash` 在開機的 VM 上直接回
   `FATAL: Module algif_hash not found`）。根因：iwd 上游/OE recipe 自己的
   `RRECOMMENDS` 只列了 PKCS7/PKCS8/X509 憑證解析模組，沒列 AF_ALG 這組
   iwd 自己 crypto 後端真正要用的模組——是上游 recipe 的疏漏，不是這條
   Yocto 線寫錯。
2. `cat /proc/asound/cards` → `--- no soundcards ---`，`lsmod | grep snd`
   → 空。同一類根因：`CONFIG_SND_HDA_INTEL=m`／`CONFIG_SND_HDA_CODEC_*=m`
   全部編成模組但同樣沒打包進 image。
3. 修法：`duduclaw-image.bb` 新增 `IMAGE_INSTALL:append = "
   kernel-modules"`（oe-core 標準的「這顆 kernel 建出的每一個模組都打包」
   umbrella package，不是逐一手點 `kernel-module-algif-hash`
   `kernel-module-snd-hda-codec-realtek` ……——刻意不逐一列舉，因為這條線
   目前還不知道 N305/8845HS 真機實際是哪顆 HDA codec 晶片，逐一列舉會重演
   同一種「猜漏就悄悄失效」的洞）。重烤後 `Tasks Summary: 7497 attempted,
   all succeeded`。

**第二輪活測（kernel-modules 修法之後，最終結果）**：
- `systemctl is-active iwd` → **`active`**（PASS，由 `failed` 轉為
  `active`，實錘 kernel-modules 修法有效）。
- `iwctl device list` → 印出正確的表頭（`Name Address Powered Adapter
  Mode`）且成功連上 iwd 的 D-Bus 服務，清單本身是空的——**這是誠實的
  QEMU 限制，不是失敗**：qemux86-64 這個 QEMU machine 沒有任何模擬的
  Wi-Fi 網卡，iwd 找不到「一張都沒有」是預期行為，真機驗收要看的是
  「iwd 服務本身活著、iwctl 連得上」，這兩項都 PASS 了。
- `cat /proc/asound/cards` → **`0 [Intel]: HDA-Intel - HDA Intel / HDA
  Intel at 0x81040000 irq 35`**（PASS，QEMU 的 `-device intel-hda -device
  hda-duplex` 模擬裝置被 kernel 真的認到並掛上 `snd-hda-intel` 驅動）；
  `lsmod | grep -c snd` → `7`（snd 核心系列模組全數載入）。
- `systemctl is-active duduclaw-kiosk` → **`active`**；
  `/run/duduclaw-kiosk/` 下確認看到 `pipewire-0`／`pipewire-0-manager`／
  `wayland-1` 均為真實 socket（`srwxr-xr-x`），代表 `duduclaw-kiosk-launch.sh`
  的 `start_audio_session` 真的把 PipeWire＋WirePlumber 起在 kiosk session
  裡、且 comp/shell 的 Wayland socket 也活著。
- **未達成一項，誠實記錄**：透過臨時 `su -s /bin/sh duduclaw-kiosk -c
  'wpctl status'` 手動驗證失敗於 `Could not connect to PipeWire`——這是
  我這次手動下的 `su` 指令本身沒有 kiosk session 自己那條
  `dbus-run-session` 包出來的 session bus（RTKit 相關警告印證了這點：
  `Unable to autolaunch a dbus-daemon without a $DISPLAY`），**不是**
  PipeWire/WirePlumber 本身沒起來——上一行已經用 socket 存在證明它們真的
  在跑。真正對等於「進到 kiosk session 內部跑 wpctl」需要重放
  `duduclaw-kiosk-launch.sh` 自己的 dbus-run-session 包法（或等殼本身
  真的點亮再從殼內測 UI），本輪未做到那一步，留給真機到貨當天或殼本身
  的 AVX2/TCG 崩潰迴圈裁決之後一併驗證（見 §3 既有揭露）。

**QEMU 環境天花板（誠實界線，這是本輪能拿到的驗證上限，非本輪失誤）**：
- 殼（duduclaw-comp/duduclaw-shell）本身仍受 §3 已經記錄的 Apple
  Silicon+TCG+AVX2 JIT 崩潰迴圈影響——這次驗證全程用 serial console 讀
  systemd/D-Bus 層狀態，沒有嘗試看畫面，兩者互不影響（誠實地說：這代表
  這次驗證證明的是「dbus/systemd 這一層的網路與音訊管線是通的」，不是
  「使用者在畫面上真的看得到/摸得到」）。
- iwd 的「連上一個真的 Wi-Fi 熱點」半段（掃描→WPA2 握手→取得 IP）需要
  真實無線網卡，QEMU 沒有等價的 mac80211_hwsim 走查腳本（Debian
  appliance 線的 D4a-9 有，這條 Yocto 線目前沒有移植），留待真機。
- 音訊的「真的聽到聲音」半段同理需要真實喇叭/耳機，`-audiodev none`
  代表 QEMU 主機本身不出聲，這次驗證證明的是「kernel 認得到裝置、
  PipeWire 找得到 sink」，不是「有聲音真的播出來」。

---

## 7. Dashboard

- [ ] 有線網路連上後，同網段另一台機器瀏覽器打開
      `http://<mini-pc-ip>:18789/`（或看螢幕上 kiosk 直接顯示的畫面，
      Y5-4 已把 gateway bind 改成 `0.0.0.0`，區網內其他裝置應該也連得到，
      不只 localhost）。
- [ ] 預期看到 OOBE 首次設定精靈或（若已設定過）主控台畫面。
- [ ] `curl http://127.0.0.1:18789/healthz` 應回 200。
- [ ] 若打不到：檢查 `systemctl status duduclaw-gateway`；檢查
      Y5-4 的 `DUDUCLAW_BIND=0.0.0.0` 環境變數是否真的在真機上生效
      （這是 QEMU 驗證過的修法，真機上理論同構，但列 ⚠️ 未在真機驗證）。

---

## 8. A/B 更新一輪

**誠實狀態（Y6-3 查證時點）**：`conf/distro/duduclaw-os.conf` 的決策註解
寫著「更新引擎＝留 systemd-sysupdate 鏈」，且 EFI/systemd-boot 的基礎設施
（UKI + boot-counting 檔名慣例）已經在 distro 層決定好了——但這只是**地基
決策**，搜尋整個 `meta-duduclaw/` **找不到任何 `.transfer` 定義檔或
`sysupdate.d/` 內容**，也沒有等價於 appliance 線 H3d 那一整套簽章驗證鏈
（`duduclaw-gateway` 裡的 `os_update.rs`／`device_ops.rs` 是 Rust 端的
API/協定程式碼，需要底下有真正的 systemd-sysupdate transfer 定義才能
實際執行一次更新，這塊目前對 Yocto 線是空的）。

- [ ] **這一項目前無法在真機上跑「一輪真實 A/B 更新」**——不是本清單的
      操作失誤，是機制本身還沒有從 appliance（Debian）線移植/重新實作到
      這條 Yocto 線。標記 **SKIP（機制未實作）**。
- [ ] 可以做的替代驗證：確認 `bootctl status`（systemd-boot 自己的工具）
      能正確列出目前的 boot entry，這是 A/B 機制最終會依賴的底層能力，
      先確認地基没問題。
- [ ] 若到貨當天這塊有新進度（另一票補上），改用該票自己的驗收步驟。

---

## 9. 驗收結果記錄格式

到貨當天請把每一項的 PASS/FAIL/SKIP 直接寫回
`commercial/docs/TODO-agent-first-os-2026-08.md`（新增一個「Y7 真機驗證」
或類似編號的條目），格式比照既有各輪紀錄——狀態詞彙用 COMPLETE/DEGRADED/
PARTIAL 分級，不要用「大致沒問題」這種模糊字眼；SKIP 的項目要註明是
「功能未實作」還是「本次沒條件測」，兩者意義不同。

---

## 附：燒錄包產出方式與本輪實際交付物

```sh
# 在 duduclaw-yocto builder 容器內（單獨跑，不要跟其他 kas 設定的 build
# 併發——不同 MACHINE 的 kas 設定會搶著改寫同一份 build/conf/local.conf，
# 併發會導致 bitbake 大量「metadata not deterministic」骨牌式錯誤，本輪
# 已活體撞過這個坑）：
kas shell meta-duduclaw/kas/duduclaw-os-genericx86-64.yml \
    -c "bitbake duduclaw-image-flatpak"

# 取出 .wic（builder 容器的
# tmp-duduclaw-qemux86-64/deploy/images/duduclaw-genericx86-64/ 下）
# 在 host 端壓縮＋算 checksum：
zstd -T0 -6 --long=27 duduclaw-image-flatpak-duduclaw-genericx86-64.rootfs-<timestamp>.wic \
    -o duduclaw-os-genericx86-64.wic.zst
shasum -a 256 duduclaw-os-genericx86-64.wic.zst > duduclaw-os-genericx86-64.wic.zst.sha256
shasum -a 256 duduclaw-image-flatpak-duduclaw-genericx86-64.rootfs-<timestamp>.wic \
    > duduclaw-os-genericx86-64.wic.sha256
```

### 本輪（Y6-3，2026-08-26）實際交付物

路徑：`meta-duduclaw/.build/y6-3-genericx86-64/`（未 commit——是建置產物，
不進 git；若要留存請自行搬到別處備份，這個目錄下次重烤會被覆蓋）。

| 檔案 | 大小 | sha256 |
|---|---|---|
| `duduclaw-os-genericx86-64.wic` | 10,856,438,784 bytes（約 10.1 GiB，大部分是 sparse 空洞） | `1346f3ed991c29b2f80f88f919fdb643be5d6a985406b6b3bbe23a7bf881ee1f` |
| `duduclaw-os-genericx86-64.wic.zst` | 864,414,760 bytes（約 824 MiB，`zstd -6 --long=27` 壓縮，壓縮率 7.96%——這麼低是因為原始映像本身多是 sparse 零值區塊，不是壓縮效果差） | `c420763c503d30b6c59ffd6c6787b2238069ab482c120a49d89caef6ff09f6c7` |

`file` 核對過檔頭是合法的 GPT protective MBR（`ID=0xee`），不是空檔或截斷檔。

**這次重烤含 Y5-4 三修正**（`vulkan-loader` 補裝／gateway `0.0.0.0` bind／
kiosk `StartLimitIntervalSec=0` 永不放棄自癒）**與 Y6-3 本票的離線 flatpak
repo**（`/opt/duduclaw-flatpak-offline-repo`），**不含 Y6-1 的 IME**（見本
文件開頭說明——fcitx5 上游與新版 fmt 相容性問題，暫時從 `duduclaw-image.bb`
註解掉，等 Y6-1 修完可直接取消註解重烤）。

**建置過程踩的坑（誠實記錄，供下一棒參考）**：
1. 第一次重烤在 `do_rootfs` 失敗——建置期間 Y6-1 併發把 `fcitx5 fcitx5-chewing`
   加進了共用的 `duduclaw-image.bb`，bitbake 的 metadata 一致性檢查抓到
   `basehash` 中途改變，改用新清單重跑 dnf install 時這兩個套件根本還沒
   建出來。
2. 第二次重烤（在 Y6-1 的 build 還在跑時，用不同 MACHINE 的 kas 設定併發
   啟動）觸發大規模「metadata not deterministic」骨牌錯誤（連 `linux-yocto`
   都遭殃）——kas 每次呼叫會覆寫共用的 `build/conf/local.conf`，兩個不同
   `MACHINE` 設定的 kas 呼叫不能同時跑在同一個 build 目錄下，即使 bitbake
   本身的 server/queue 機制看似能排隊執行不同目標，MACHINE 不一致這件事
   仍然不安全。
3. 上述併發也連帶讓 `duduclaw-cli` 的 vendored 原始碼（`files/duduclaw-cli-src/`）
   被另一個並行 session 尚未 commit 的 WIP 程式碼（`crates/duduclaw-gateway/
   handlers.rs` 等大量修改）污染，導致 `cargo build --frozen` 因為
   Cargo.lock 與新依賴對不上而失敗（`cannot update the lock file`）。修法：
   `git checkout -- meta-duduclaw/recipes-duduclaw/duduclaw-cli/files/duduclaw-cli-src/`
   還原成上次 commit 的乾淨快照（這份 vendored 內容是純衍生檔案，真正的
   WIP 原始碼仍安全留在 `crates/`，不受影響）。
4. `duduclaw-flatpak-offline-repo.bb` 第一版 `COMPATIBLE_MACHINE` 寫成裸的
   `qemux86-64|genericx86-64`，但實際 `${MACHINE}` 值有 `duduclaw-` 前綴，
   `re.match` 不吃，導致 `bitbake duduclaw-flatpak-offline-repo` 直接找不到
   套件——改成 `^duduclaw-qemux86-64$|^duduclaw-genericx86-64$`（與既有
   kernel bbappend 同款已記錄的坑）。
5. `gen-flatpak-offline-repo.sh` 第一版 `flatpak remote-add` 忘了帶
   `--installation=gen`，導致 remote 只加進預設安裝、具名安裝找不到
   remote，`flatpak install` 秒退。
6. 磁碟一度跌破 6G 紅線（最低到 4.5G），靠刪除一份已核對 checksum 確認
   「大小相同但內容不同、且已早於本次改動的過時 qemux86-64 部署副本」
   （`duduclaw-image-flatpak-duduclaw-qemux86-64.rootfs-20260826063656.wic`，
   6.6GB）與對已知失敗 recipe 做 `cleansstate`（`duduclaw-cli`、
   `duduclaw-image-flatpak`）化解，兩次都是清理「確定過時／確定會被重建」
   的內容，沒有動任何 Y6-1 或其他 session 仍在用的東西。
