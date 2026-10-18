# Changelog

DuDuClaw OS 所有值得記錄的變更都在這裡。版號與 DuDuClaw 平台**獨立**（見
`VERSION` 檔），格式依 [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
與 [Semantic Versioning](https://semver.org/)。逐波的 bring-up 歷程（Y1–Y20）
在 git log 與 `wiki/impl/`。

## [Unreleased]

### Security
- **ZIP 相依安全修補快照**：由未修改的 `scripts/sync-platform.sh` 同步平台 v1.74.0@`a1f5fd6a964a17c2d3ad9e1165f6df3a8586c213`，保留 Dropbear 空原始指令選單修正，ZIP 改用 9.0.4、rust_xlsxwriter 改用 0.100.0，並帶入平台以 checksum 固定來源的 calamine 相容性修補。CLI 的 crates.io 集合有變，`duduclaw-cli-crates.inc` 已在固定版本的 BitBake 環境實際執行原 `update_crates` 任務產生；785 筆 registry 項目與 checksum 逐筆符合快照 lock。原中間 commit 缺少新 fetch 的失敗紀錄保留；這次來源與下載清單核對通過，尚不能作為映像驗收結果。現有 344 個 dashboard 資產逐檔與前一快照相同，未重新執行 npm build。安全修補仍須後續映像建置及實際安裝驗證。

### Fixed
- **通知登入憑證遭拒後會重新登入**：gateway 明確回覆 `AuthRejected` 時，桌面通知會清除被拒絕的憑證，下一輪依原本的重試間隔重新取得本機 session；一般連線錯誤與業務拒絕不會清除憑證。審批操作失敗仍顯示失敗，不會自動重送。已完成純 feed／backoff 回歸測試；完整映像編譯與 GUI 恢復仍待驗收。
- **Dropbear 互動選單入口**：以原同步腳本更新平台快照至 v1.74.0@`99aeee9c8d819314f72287a8fef6fc72bd733dde`。Dropbear 的 forced command 在客戶端要求 shell 時會傳入空的 `SSH_ORIGINAL_COMMAND`；維修程式將缺省與恰好空字串送入固定選單，非空指令仍沿用白名單。平台 binary 回歸測試與獨立原始碼審查通過；本次快照仍需真實映像建置、安裝與 SSH 互動驗證。

### Added
- **基礎版本機模型引擎與服務**：未發版的基礎版補入與桌面版相同的 CPU 模型服務及引擎，不加入桌面版的 coding CLI 套件。兩版在產生映像時都檢查實際模型程式、包裝器與服務檔案。權重仍放在 `/data`；新映像、模型載入與維修重啟仍待實測。
- **維修 SSH 最後整合檢查**：讀取實際 rootfs 的就緒標記、0755 選單與 root-only helper、閘道與 sysd ELF 程式及其 SSH 協定字串；缺件、不安全權限、符號連結、任何位置的 `authorized_keys` 都讓建置失敗。原有帳號、dropbear、防火牆與服務沙箱檢查仍須全部通過。新增就緒檢查正反例 fixture 測試（直接執行相同 rootfs 檢查函式）與平台快照來源／相依 checksum 核對腳本；fixture 不代表真實工具或真實映像已通過。
- **官網的 SEO／GEO 檔案**（`website/`）：兩頁加上 `robots` meta、canonical 與 hreflang（`zh-TW`、`x-default`）；首頁加 JSON-LD（`Organization` 為 Dudu Technology Ltd.／嘟嘟數位科技有限公司，`SoftwareApplication` 寫 v0.4.0、pre-GA、所有驗證在 QEMU、Apache-2.0），下載頁加 `BreadcrumbList`。新增 `robots.txt`（明列允許 GPTBot、ClaudeBot、PerplexityBot、Google-Extended 等 AI 爬蟲，列出 `sitemap.xml` 與文件站的 `docs/sitemap-index.xml`）、`sitemap.xml`、`llms.txt` 與 `llms-full.txt`，內容取自兩頁現有文案與 `site.js` 的 `RELEASE`。這組檔案原本寫在 #15 的分支上（v0.3.0 時的內容），#15 關閉沒有合併，正式站的 `/robots.txt`、`/llms.txt` 一直是 404；這次在 C1 版面上重做，版本與公司名稱改成現況。`scripts/build-site.sh` 組完 `_site/` 會檢查這四個檔案都在。`deploy/cloudrun/mime.types` 的 `.xml` 改送 `application/xml`，`nginx.conf` 加 `charset utf-8`，`.txt` 送 `text/plain; charset=utf-8`。`website/README.md` 補上 SEO 一節與出新版時要改的地方。
- **維修 SSH 專用帳號 `duduclaw-maint`（已接入候選映像，尚未活驗）**：新 recipe `meta-duduclaw/recipes-duduclaw/duduclaw-maint/`，由 `duduclaw-image.bb` 裝進兩版。這是維修視窗期間技術人員用 SSH 登入的身分，取代「SSH 只控制連接埠、沒有帳號可登入」的現況。固定 uid／gid 4800（`useradd --system --uid 4800`），不用動態系統 uid：shadow 從 999 往下依安裝順序配號，多一個動態帳號可能讓 kiosk 等帳號換號，A/B 更新後 `/data` 上的檔案就歸錯人。4800 同時避開主機動態系統區（101–999）、gateway 的 subuid（100000–165535）、Waydroid 內 Android 的 AID（特權容器，Android uid 就是主機 uid；設計 r2 的 1001 是 `AID_RADIO`）與 systemd 保留區。密碼欄 `*`（不是 `!`，換成 OpenSSH 時 `!` 會連金鑰登入一起擋）、沒有附加群組、home 是唯讀空目錄 `/usr/share/duduclaw-maint`（root 0555）、shell 是 `/usr/libexec/duduclaw/maint-shell`（固定選單，`pkg_postinst` 在建 rootfs 時寫進 `/etc/shells`）。不裝 polkit（owner 2026-10-16 拍板）：選單的兩個重啟（gateway、本地模型）交給平台出的 root 小服務代做，兩版都不新增 polkit 常駐程式、規則或隨之而來的動態系統帳號。
  - 選單 `maint-shell` 與 root 小服務 `maint-helper` 已隨平台 v1.74.0@`c7068c508ae9ab5afc4392b58237cf86afdb9f2c` 快照接入。CLI recipe 同次編譯兩個 crate，把工具拆成 `duduclaw-maint-tools` 套件，帳號套件依賴它並安裝內容為 `1\n` 的 `/usr/lib/duduclaw/maint-ssh.ready`。診斷工具明列 iproute2、procps、coreutils 與 systemd 相依。這是候選原始碼，尚未經 BitBake 建置或 QEMU 開機，不能視為已可登入。
  - **新的建置檢查** `recipes-core/images/duduclaw-maint-checks.inc`（rootfs 最後一步，讀實際產出的 `/etc/passwd`、`group`、`shadow`、`shells`、`subuid`／`subgid`、`login.defs`）：4800 只屬於 `duduclaw-maint`；帳號的主群組、home、shell、密碼欄符合設計且沒有附加群組；4800 不在上面四類範圍內；home 是空的 root 0555 目錄；映像裡任何 polkit 規則檔都不得提到 `duduclaw-maint`；**與上一版比對帳號數字**，任何帳號或群組換號、消失，或出現 `DUDUCLAW_ACCOUNT_IDS_ADDED`（目前只有 `duduclaw-maint`）以外的新帳號，建置就失敗。上一版的表是從已發布的 v0.4.0 資產直接讀出來的（`recipes-core/images/duduclaw-image-ab/account-ids.txt` 給基礎版、`duduclaw-image-appliance/account-ids.txt` 給桌面版；兩種機器的 `/etc/passwd`、`/etc/group` 逐位元組相同），每次發版後要照檔頭的方法重產並清空 `DUDUCLAW_ACCOUNT_IDS_ADDED`。檢查邏輯以 v0.4.0 的帳號表跑過 19 個情境（含換號、新帳號、4800 撞號、附加群組、密碼欄、`/etc/shells`、home 權限、subuid、就緒標記、提到 maint 的 polkit 規則；桌面版的 Flatpak 規則不受影響）。每個版本只跟自己的上一版比；沒有設定上一版帳號表的開發用映像會發警告並略過比對。
  - **兩版的動態帳號號碼本來就不同**：v0.4.0 的基礎版與桌面版在每一個動態帳號上號碼都不一樣（11 個使用者、16 個群組，例如 `duduclaw-kiosk` 基礎版 999:997、桌面版 998:996，`polkitd` 基礎版 996:991、桌面版 999:999；桌面版的 polkit 套件比其他帶系統帳號的套件都先安裝，後面全部少一號）。所以不用 `useradd-staticids`：它對整個建置改寫每個 recipe 的 `useradd` 參數，兩版共用一張表，只保得住其中一版。維持動態配號，靠上面的上一版比對把關。原本最可能讓基礎版換號的來源是加裝 polkit，現在不裝了；其他新進的套件若帶來動態帳號，比對會讓建置失敗。新增帳號的規則寫在 `meta-duduclaw/README.md`。
  - 用 kas 依釘選的 layer 跑過 `bitbake -e duduclaw-maint`、`duduclaw-image-ab`、`duduclaw-image-appliance`，解析與變數展開都正常（拿掉 polkit 後重跑過）（兩版的 `DUDUCLAW_ACCOUNT_BASELINE` 指向各自的表，檢查排在 rootfs 後處理最後一步）。尚未以 kas build 建置，也沒有在 QEMU 開機驗證。
- **dropbear 只給維修帳號用（還不能登入，同上）**：`recipes-core/dropbear/dropbear_%.bbappend` 多三個 `60-` 開頭的 drop-in。`dropbear@.service.d/60-duduclaw-maint.conf` 把指令換成 `dropbear -i -r /data/system/dropbear/dropbear_ed25519_host_key -w -s -j -k -m -T 3 -I 1800 -G duduclaw-maint -D /run/duduclaw-maint-ssh -c /usr/libexec/duduclaw/maint-shell`：只有 `duduclaw-maint` 群組能登入（少了 `-G`，`-D` 會讓 `duduclaw-rescue` 也能用維修金鑰登入）、只收公鑰、金鑰只從 sysd 為單一視窗寫在 tmpfs 的目錄讀、每個連線都跑固定選單（scp、sftp 也一樣）、不能轉送；並加上 `IPAddressDeny=any`、`NoNewPrivileges`、`ProtectProc=invisible`、`ProtectHome`、`PrivateTmp`、`ProtectSystem=strict`、對 gateway／kiosk home、Wi-Fi 設定與容器儲存區的 `InaccessiblePaths`，清掉 `/etc/default/dropbear`。`dropbear.socket.d/60-duduclaw-maint.conf` 與前者都 `BindsTo=`／`After=duduclaw-sysd.service`（sysd 停掉或停在 failed 時 socket 與所有連線一起停），socket 限總數 16、每來源 4。
  - **主機金鑰搬到 `/data/system/dropbear`**：上游 `dropbearkey.service` 在 `/etc/dropbear` 產生 RSA 金鑰，桌面版 root 唯讀會寫不進去（layer 沒用 oe-core 的 `read-only-rootfs`，oe-core 把金鑰改到 `/var/lib/dropbear` 那段不會套用；v0.4.0 兩版映像的 `/etc/dropbear` 都是空目錄）。drop-in 清掉上游條件，改在 `/data/system/dropbear`（root 0700，已存在的目錄也會 `chmod` 回 0700）產生一把 ed25519，重開機與 A/B 更新後指紋不變。dropbear 2025.89 的 `dropbearkey` 先寫暫存檔再 `link` 到位（讀過 `gensignkey.c`），中斷不會留下半個金鑰。
  - **工廠重置清掉主機金鑰與維修 SSH 稽核紀錄**：`duduclaw-factory-reset.sh` 多移除 `/data/system/dropbear` 與 `/data/system/maint-ssh-audit.log`、sysd 輪替出來的 `.1` 到 `.5` 以及 `.lock`，還有 sysd 保存視窗狀態、journal 游標與待寫稽核紀錄的 `/data/system/maint-ssh`（路徑依平台 P-1 的通知，P-1 定案前若改名要跟著改；設計 §11 的工程預設：新使用者不承接舊紀錄）；是符號連結就拒絕、保留標記。在 Alpine bash 跑過 7 個情境。
  - **PID 1 的後備關窗腳本** `/usr/libexec/duduclaw/maint-ssh-close`（root 0700，隨 `duduclaw-maint` 出貨）：sysd 開窗時會掛一個 `systemd-run` 計時器，sysd 自己沒在時限內關窗時由它執行。依序刪金鑰、停 `dropbear.socket` 與所有 `dropbear@*.service`、寫 `system-dropbear.slice` 的 `cgroup.kill`、把 22 從 `maintenance_tcp_ports` 拿掉（元素或集合已不在都算成功），再逐項讀回確認，最後在 `/data/system/maint-ssh-audit.log` 附加一筆 close 紀錄。**稽核介面照平台 P-1（#142）定案的版本**（`crates/duduclaw-sysd/src/maint_ssh/audit.rs` 的介面說明）：欄位就是 sysd close 紀錄的形狀（`ts` 為 UTC 的整數 Unix 秒、`event: "close"`、`trigger: "fallback_timer"`、`window_id`、`removed_fingerprint`、`done`、`problems`、四個登入／登出計數、`auth_failures`、`auth_failure_sources`、`sessions_open_at_close`、`last_cursor`、`events_complete`），`window_id`、指紋、計數與 `last_cursor` 取自 sysd 寫的 `window.json`（沒有就是 `null`）；腳本不讀 journal，所以 `events_complete` 為 `false`、`auth_failure_sources` 為 `null`，由 sysd 下次啟動時重播。寫入規則：只附加、不輪替（輪替只由 sysd 做）；在 `umask 077` 下開 `<檔>.lock` 並在整次附加期間持有排他 `flock`；稽核檔與鎖檔都必須是 root 擁有、沒有群組／其他人權限的一般檔，符號連結或權限不對就不寫、把原因寫進 journal，視窗照樣關。映像的 `flock` 是 busybox 1.37 的，沒有 `-w`，所以 10 秒上限用 `flock -n` 每秒重試實作（util-linux 的 `flock` 也適用），10 秒拿不到鎖就不寫。關窗後、寫稽核紀錄之前，另以原子方式取代 `/data/system/maint-ssh/last-close.json`（P-1 `0f7d26c0` 的介面：在同一目錄 `umask 077` 下建暫存檔再改名，內容固定為 `{"window_id":…,"trigger":"fallback_timer","events_complete":false,"events_lost":false,"ts":<整數秒>}`，`window_id` 取自 `window.json` 且必須符合 `[A-Za-z0-9-]{1,64}`，否則為 null）；目錄不是 root 擁有、0700 的真目錄，或既有檔案是符號連結，就不寫並記為問題。sysd 之後清理視窗時，只要 `ts` 不早於開窗時間就保留 `fallback_timer` 這個原因。沒有視窗也沒有金鑰時，last-close.json 與稽核紀錄都不寫（與 sysd 相同）。OE 的 busybox 預設沒有 `sha256sum` 與 `base64`，所以指紋只在 `window.json` 不見時才嘗試自己算，算不出來記 `null`。`window.json` 留給 sysd 下次啟動時補寫登入紀錄。可重複執行；任一步失敗後面照跑，最後回非零。稽核寫入只試一次，失敗不重試（殘留風險寫在 `SECURITY.md`）。shellcheck 乾淨；在 Alpine 容器以真的 nft、busybox `flock` 與替身 systemctl 跑過 27 個情境（含 last-close.json 的 10 個：形狀與欄位順序、0600、沒有殘留暫存檔、window_id 為 null 的兩種情況、0755 目錄、符號連結的檔案與目錄都拒絕、既有檔案被取代、沒有視窗時不動它）（欄位集合與 P-1 close 紀錄逐一相同、`last_cursor` 與計數取自 `window.json`、`events_complete` 為 false、搶鎖時等到放鎖才寫、10 秒拿不到鎖就不寫但金鑰與埠照關、超過 1 MiB 也只附加不輪替、新建的鎖檔在 umask 000 下仍是 0600、0640 的鎖、0644 或符號連結的稽核檔、符號連結的鎖都拒絕、停止失敗照實記錄）。
  - **建置檢查**：`linux-yocto_6.18.bbappend` 在 `do_configure` 最後確認 `.config` 有 `CONFIG_CGROUP_BPF=y`（沒有時 systemd 只警告、`IPAddressDeny=` 直接失效；`duduclaw-rootless.cfg` 已有這行）。`duduclaw-maint-checks.inc` 新增 `duduclaw_check_maint_dropbear`：`ExecStart` 必須逐 token 等於 `DUDUCLAW_MAINT_DROPBEAR_ARGV`（與 sysd 開窗前比對的常數同一串）、兩個 unit 都有 `BindsTo=duduclaw-sysd.service`、有 `IPAddressDeny=any`、沒有別的 drop-in 改 `ExecStart`、`dropbearkey` 寫到 `/data/system/dropbear`、映像裡 `/etc/dropbear` 與 `/data/system/dropbear` 必須是空的（烤進去的主機金鑰會讓每台機器共用）、後備腳本存在、映像裡有 `flock`；dropbear@ drop-in 的沙箱設定（`NoNewPrivileges`、`ProtectSystem=strict`、`ProtectProc=invisible`、`ProtectHome`、`PrivateTmp`、`InaccessiblePaths`、`RequiresMountsFor=/data`）逐項比對；`/usr/sbin/dropbear`（oe-core 裝成指向 `dropbearmulti` 的連結）在 rootfs 內解析後必須是 sbindir 底下 root 擁有、只有 root 能寫的一般執行檔，解析結果印在建置紀錄裡（sysd 在執行期會再做一次 canonicalize）。以 22 個情境測過檢查邏輯。
  - 尚未以 kas build 建置，也沒有在 QEMU 開機驗證（L1、L3、L4、L7–L11、L14、L15、L17 都要映像）。
- **防火牆：22 埠只收區網與 VPN 來源，維修帳號連不到 loopback（還不能登入，同上）**：`duduclaw-firewall` 的 `nftables.conf` 新增 `maintenance_src4`（10.0.0.0/8、172.16.0.0/12、192.168.0.0/16、169.254.0.0/16、100.64.0.0/10）與 `maintenance_src6`（fc00::/7、fe80::/10）兩個集合，原本「`maintenance_tcp_ports` 對所有來源放行」那條換成三條：IPv4 來源在 src4 才放行、IPv6 來源在 src6 才放行，其他來源一律回 TCP reset（全域 IPv6 也是，`ssh` 會立刻改走 IPv4）。100.64.0.0/10 是 owner 2026-10-16 拍板加入的 VPN（Tailscale 等）位址；代價寫在檔頭：視窗期間網際網路掃描者能從 reset 看出埠是開的，WAN 直接拿到 ISP CGNAT 或 10.x 位址時同一 ISP 的其他用戶也在範圍內。output 鏈多一個空的 `duduclaw_maint_egress` 鏈，`oif "lo"` 跳轉排在 output 鏈第一條、podman 的跳轉之前（維修帳號的拒絕不受 podman 鏈影響；sysd 開窗前會確認它是第一條）；`duduclaw-maint` 附的 `nftables.service.d/60-duduclaw-maint.conf` 在每次 start 與 reload 後以 `-` 前綴加入 `meta skuid 4800 counter reject`（用數字，不用帳號名稱：nft 載入時解析不到名稱整份規則就會失敗；規則不放進 `nftables.conf`，防火牆也不必依賴這個套件）。排在 podman 的 `50-` 之後，不會擋到它的守門規則；反過來，podman 的 `50-duduclaw-podman-guard.conf` 兩行也改成 `-` 前綴：systemd 遇到第一個沒有 `-` 的失敗指令就停下，守門腳本失敗時原本會連帶跳過後面的 maint 規則。守門腳本失敗時自己會停掉 `duduclaw-podman.service`（fail closed 不受影響），差別只在 `nftables.service` 不再因此顯示 failed，改由守門腳本的錯誤與停掉的 Podman 呈現；sysd 每個 tick 也會重新確認 maint 鏈。`duduclaw-maint-checks.inc` 新增 `duduclaw_check_maint_nft`：drop-in 的兩行必須完全等於預期（數字 uid、`-` 前綴），`nftables.conf` 不得在 skuid／skgid 用名稱、必須有空鏈、跳轉必須是 output 鏈的第一條、兩個集合的元素必須等於常數、三條規則都在、舊的全開放行不得留著。
  - 驗證：Debian 容器的 nft 1.1.3 `nft -c -f` 通過；在兩個 network namespace 之間實際載入規則、加 22 進集合後，10.x、100.64.x、fd00:: 來源連得上，100.128.0.1、203.0.113.5、2001:db8:: 收到 reset；22 移出集合後回到靜默丟棄；以 `setpriv` 切成 uid 4800 連 127.0.0.1 被拒、uid 1000 可以，計數器有動；`nft -f` 重載後鏈變空（所以要靠 `ExecReload` 加回）；載入後 output 鏈第一條是 maint 跳轉。檢查邏輯 11 個情境。映像用的是 nft 1.1.6 與 kernel 6.18，這些是在 Docker Desktop 的 kernel 上跑的。尚未 kas build，L9（reload 後規則仍在）、L21、L25 要映像。
- **維修選單唯一的 root 入口 `duduclaw-maint-helper`（還不能登入，同上）**：`duduclaw-maint` 多出 `duduclaw-maint-helper.socket`（`/run/duduclaw-maint-helper.sock`，root:duduclaw-maint 0660、`Accept=yes`、最多 4 條連線，開機即啟用）與 `duduclaw-maint-helper@.service`（每條連線一個 root instance，跑平台的 `/usr/libexec/duduclaw/maint-helper`；能力邊界清空（`CapabilityBoundingSet=`）、`NoNewPrivileges`、`ProtectSystem=strict`、`ProtectProc=invisible`、`PrivateNetwork`、`IPAddressDeny=any`、`RestrictAddressFamilies=AF_UNIX`、`SystemCallFilter=@system-service`、`ProtectKernelTunables/Modules/Logs`、`ProtectControlGroups`、`ProtectClock`、`ProtectHostname`、`PrivateDevices`、`ProtectHome`、`PrivateTmp`、`RestrictNamespaces`、`RestrictRealtime`、`RestrictSUIDSGID`、`LockPersonality`、`MemoryDenyWriteExecute`、`RuntimeMaxSec=3600`，唯一可寫的是保留在 instance 之間的 `RuntimeDirectory=duduclaw-maint-helper`，平台 P-2 的 helper 把重啟頻率上限的狀態放在這裡，所以是必要設定；stderr 進 journal 不回給連線端；`CollectMode=inactive-or-failed`，失敗的 instance 不會堆成 failed unit；不在 `system-dropbear.slice`，重啟 gateway 引發的關窗不會砍掉進行中的重啟）。設計 r4 把原本的 `maint-logs` 改名，並在 owner 撤回 polkit 後多負責兩個重啟：維修帳號不在 `systemd-journal`、沒有 polkit、沒有 sudo，讀 gateway 與本地模型紀錄、重啟這兩個 unit 都只能經過它；對端 uid 檢查、六個封閉 token、頻率上限、丟掉 bootstrap 密碼行與遮罩都在平台程式裡。程式要等平台快照同步才進映像，在那之前連進來的 instance 會執行失敗（也沒人能以這個帳號登入）。`duduclaw-maint-checks.inc` 新增 `duduclaw_check_maint_helper`：兩個 unit 的設定逐項比對（含保留的 0700 `RuntimeDirectory`）、不得放進 `system-dropbear.slice`、socket 必須已啟用、上述沙箱設定逐項比對（檢查邏輯 13 個情境）。在 Debian 容器（systemd 257）以 `systemd-analyze verify` 驗過這兩個 unit，以及 dropbear 三個 unit、`nftables.service` 加上本系列 drop-in 之後的組合；另在容器裡以 systemd 257 當 PID 1 實際開機測 socket 啟動（helper 用替身程式）：`duduclaw-maint`（uid 4800）連得上，instance 以 root 執行、在自己的 `system-duduclaw\x2dmaint\x2dhelper.slice`、`/run/duduclaw-maint-helper` 為 0700 且可寫、`/etc` 唯讀，加上全部沙箱設定、能力邊界為空（`CapBnd`／`CapEff` 都是 0）時，`systemctl restart` 照樣成功（unit 換了新的主行程）、`journalctl` 讀得到該 unit 的紀錄（同一帳號直接跑 `journalctl` 則因權限不足讀不到）；`systemd-analyze security` 評分 0.9 SAFE；uid 1000 的帳號被 socket 權限擋下。尚未 kas build，L5、L6 要映像與平台程式。

### Changed
- **平台快照同步到 v1.74.0（1.73.4→1.74.0，`scripts/sync-platform.sh`）**：`duduclaw-cli`／`duduclaw-sysd` 快照自平台重新 vendor（`duduclaw-comp`／`duduclaw-shell` 自本 repo `crates/` 重新快照），`duduclaw-platform-version.inc` 1.73.4→1.74.0（連動 `DISTRO_VERSION`、os-release `VERSION_ID`、UKI 檔名、A/B loader 項），兩個平台 recipe 改名 `_1.74.0.bb`。sysd 新增 base64，`duduclaw-sysd-crates.inc` 已由實際 lock 重生；CLI 的 registry 相依集合不變。OS 自己的 release 版本（`VERSION`）不受影響。
  帶進的平台 commit：
    - 1cb8cdc3 chore: bump v1.74.0
    - 1af8f746 Merge pull request #135 from zhixuli0406/feat/subscription-risk-disclosure
    - f0521cbb Merge pull request #134 from zhixuli0406/feat/brand-c1
    - 3a47abbd Merge remote-tracking branch 'origin/feat/brand-c1' into feat/subscription-risk-disclosure
    - 18844c39 docs: drop the duplicate C1 CHANGELOG entry left by a rebase
    - 5e5cd1f2 docs: file the os_doctor_repair and wiki_export entries under Changed
    - c11f394e Merge origin/main into feat/brand-c1
    - f7121934 Merge pull request #136 from zhixuli0406/fix/wiki-path-hardening
    - ab1aa7f4 Merge origin/main into feat/subscription-risk-disclosure
    - ded7ba06 test: move the README vendor-claim guard to a Rust test
    - bddbde92 Merge pull request #137 from zhixuli0406/chore/gemini-cli-removal-v1.75
    - ce6b0f26 fix: drop the remaining 'Google blocks' claim, name the OS shell in BREAKING
    - 07577d83 docs: subscription-risk review follow-up (BREAKING note, cited Google terms)
    - dd626a4f fix(gateway): gate raw config and device-flow writes of subscription accounts
    - 54c2b231 fix: cite each vendor's own terms in the subscription-risk notice
- **官網與文件站換成公司的 C1 視覺**（`website/`、`docs-site/`）：米白底、海軍藍文字、琥珀色條（4px）、細線分隔、Avenir Next／Nunito Sans；深淺兩種主題都照 C1 色票（深色 `#0B1E33`）。logo 改成 C1 貓 mark 加文字「DuDuClaw OS」，inline SVG 的 ink 層在深色底轉米白；頁尾加公司 mono mark 與「Dudu Technology Ltd. · 嘟嘟數位科技有限公司 · 統編 94139082」及公司隱私權政策、服務條款連結。favicon（`favicon.svg`／`favicon.ico`）、apple-touch-icon、manifest 圖示與 `og:image` 換成 Codex 的 C1 檔案；`og:image` 原本是 v0.2.0 的 `home-dark.png` 截圖，改為由 `final-duduclaw-os-social.png` 裁成 1200×630 的 `assets/brand/og.png`。首頁 hero 右側由吉祥物改為 v0.2.0 Launcher 的實拍局部（新增 `launcher-mobile` 三種格式），圖說與桌面圖集上方都標明是 v0.2.0 畫面、v0.3.0 尚未重拍。下載頁 QR code 中央的貓換成 C1 mark，QR 模組路徑逐位元組不變，headless Chrome 截圖後以 jsQR 在 1x／2x、淺色／深色都解出原本的 v0.3.0 ISO 網址。文件站 Starlight 的 logo、hero 圖與 favicon 一起換，程式碼區塊兩種主題都是海軍藍底。影子工作區示意圖的圖說配合新配色，把「藍色箭頭／黃色方形游標」改成「一般箭頭／琥珀色方形游標」。文案其餘不動。`deploy/cloudrun/mime.types` 補 `webmanifest`。`website/README.md`、`docs-site/README.md` 同步。

- **文件與官網改成 v0.4.0 已發布的事實**（`README.md`、`README.zh-TW.md`、`SECURITY.md`、`meta-duduclaw/README.md`、`docs/README.md`、`docs/guides/ai-runtimes.md`、`docs/guides/app-compat.md` 三語、`website/`）：版本徽章與狀態列改成 0.4.0／平台 v1.73.4；兩份 README 在狀態列後加「v0.4.0 的變更」一段，快速開始加上單向升級的說明，`zstd -d` 補 `--long=27`（照 Release 說明）。測試範圍照 Release 寫：qemux86-64 整碟映像約 65 秒到登入、兩個 qemux86-64 安裝器 ISO 約 125 秒到 live 自動登入、桌面版測試映像兩輪 rootless 驗證（第二輪 35／36）；沒驗證的是從 v0.3.0 經 A/B 升級、需要 LLM 憑證的流程、Windows VM、真機與 genericx86-64 開機。基礎版的描述拿掉「沒有防火牆、SSH 區網連得到」，改成防火牆與桌面版相同、SSH 預設關閉。`SECURITY.md` 的權限模型與 layer README 的「Service accounts and privileges」從「尚未出貨」改成 v0.4.0 已出貨，回滾下限寫明 `1.73.4-y1-bringup`，另加 SSH 一條。`ai-runtimes.md` 同步 rootless 後的事實：`/data/duduclaw` 擁有者是 `duduclaw`、root 登入 shell 的 AI CLI 經 `setpriv` 降權、`duduclaw-llama-server` 不再以 root 執行（刪掉原本的「已知缺口」段）。官網：`site.js` 的 `RELEASE`（v0.4.0、2026-10-16、平台 1.73.4、上一版 v0.3.0、`downloadBase` 與六個資產的檔名、位元組、大小）、兩頁的版本列、狀態卡（加單向升級與 SSH）、下載卡、`dd` 範例、回舊版卡片（改指 v0.3.0，註明開過 v0.4.0 的裝置不能經 A/B 退回）、首頁信任界線一句（拿掉「gateway 目前仍以 root 執行」）。下載頁 QR code 照 `website/README.md` 的規則重產：同一支腳本先重產 v0.3.0 網址，與頁面上的 path 逐位元組相同後才產 v0.4.0；headless Chrome 截圖後以 jsQR 在 1x／2x、淺色／深色都解出 v0.4.0 的 ISO 網址。`wiki/impl/gcp-builder-2026-10.md` 加上 v0.4.0 建置紀錄，`wiki/eval/rootless-verification-2026-10.md` 標明已執行。截圖仍是 v0.2.0 的畫面，說明文字照實標示。文件站沒有寫死版本號，不用改。
- **CHANGELOG 0.4.0 一節更正**：那一節有幾條是開發期間寫的（「內嵌的平台仍是 v1.73.1」「變數目前為空」「這些修正都還沒重新烤圖驗證」），與發版事實矛盾，已改成發版時的實際狀態。

- **`docs/guides/ai-runtimes.md` 與兩份 README 跟上平台 v1.74.0 的文件**：Gemini CLI runtime 的移除，平台已延到 v1.75.0（v0.4.0 內嵌的 1.73.4 仍帶著它），README 的 AI 工具鏈一條與 ai-runtimes 都改了。ai-runtimes 的訂閱登入一段拿掉「Anthropic 與 Google 自 2026 年 3 月起在伺服器端擋掉」這個找不到一手出處的說法，改引 Anthropic 的規範與 Google Gemini CLI／Antigravity 條款，文字與 #21 改的同一段相同。OS 映像沒有變，v0.4.0 仍內嵌平台 v1.73.4。

### Removed
- **官網的吉祥物與裝飾動畫**：緋紅摺紙貓（hero inline SVG、CTA 背景貓、QR 中央的貓）、3D 貓（`assets/js/cat3d/`、`assets/data/cat-panels.json`、`assets/vendor/ogl.mjs`）、走路貓（`assets/js/catwalk/`、`assets/js/hero-cat.js`）、驗收頁 `website/lab/`、hero 的 WebGL 色塊（`assets/js/hero-shader.js`）、影子工作區的粒子凍結示範（`assets/js/freeze-demo.js`）、捲動進度條、磁吸按鈕與截圖傾斜效果，以及 `assets/brand/` 的舊 logo 與 favicon（`duduclaw-cat.svg`、`duduclaw-mark-circle.svg`、`duduclaw-tile.svg`、`favicon.svg`、`mark-{16,32,64,512}.png`、`cat-512.png`）和文件站的 `src/assets/duduclaw-mark-circle.svg`。C1 規範不留吉祥物動畫，也不用漸層與光暈。`scripts/build-site.sh` 移除刪 `lab/` 的步驟。

### Fixed
- **DHCPv6 啟動回覆遭預設拒絕防火牆擋下**：新增僅限 link-local 來源與目的位址、UDP 547 → 546 的放行規則；多播 Solicit 對應的單播回覆可能是 `ct NEW`，無法只靠 established/related 放行。Yocto 與凍結的 Debian 防火牆參考副本同步。隔離 Linux 核心封包測試重現舊規則丟棄、新規則接收，錯誤來源埠與非 link-local 來源仍被拒絕；尚待重建映像後確認 GCP 自動取得 IPv6 位址，未宣稱實機問題已閉合。
- **平台同步流程不再吞掉 refresh 失敗或改動回滾下限**：任何 refresh 失敗立即中止；CLI refresh 從 CLI 與維修工具兩個入口計算完整 path 相依閉包，sysd refresh 加入 base64、改以離線 metadata 剪 lock，不再為同步來源在本機編譯。同步後記錄精確來源 commit；crates include 尚待再生時不會寫成「已重生」。這次 sysd 的 include 已由既有 `gen-crates-inc.py` 依實際 lock 重生；CLI 的 registry 相依集合未變。
- **原廠重設與維修 SSH 啟動的競態**：重設資料的 oneshot 現在排在 `duduclaw-sysd.service` 與 `dropbearkey.service` 之前，避免 sysd 在清除後寫回舊維修紀錄，或主機金鑰先產生卻又被重設刪除。只增加啟動排序，不要求重設成功才啟動這兩項服務，重設失敗時仍可進後台排查。新增 `scripts/tests/maint-reset-order.py`，從實際 unit 原始碼檢查排序圖、循環與失敗依賴；這是靜態回歸測試，尚未以映像建置或 QEMU 開機驗證。
- **維修 SSH 後備關窗腳本讀錯視窗狀態路徑**：`maint-ssh-close` 改讀 sysd 實際寫入的 `/data/system/maint-ssh/window.json`，不再從 tmpfs 金鑰目錄找，讓關窗稽核與 `last-close.json` 保留正確的視窗 ID、指紋、游標與計數。狀態檔留給 sysd 重播 journal；即使重開機後金鑰消失，仍記錄持久視窗的關閉；沒有持久視窗也沒有金鑰時，不新增稽核紀錄、不覆寫最後關閉原因。新增 `scripts/tests/maint-ssh-close.py` 與完整 `WindowFile` 範例，核對平台目前的欄位與路徑，並測試上述行為；Linux 容器使用真正的 Bash、檔案與 flock，systemctl／nft 為替身，尚未建置映像或在 QEMU 開機驗證。
- **安裝串流失敗不再誤報成功**：安裝器改用 Bash（recipe 明確依賴 `bash`）與 `pipefail`，三條寫入路徑的解壓、`pv` 或 `dd` 任一步失敗就停止，不進入 GPT 修復或初始設定注入。進度樣本最高 99，完整串流、進度讀取與同步成功後才發 100；FIFO 改放在私有暫存目錄，失敗會清理並等待背景讀取行程。主程序收到 TERM／INT 會終止並等待本次寫入專用的程序群組，不波及呼叫者的群組；fork 後尚未記錄 PID 時收到的取消會先暫存，記錄後立即處理。新增 29 個 host 路徑案例，直接讀取正式 script 的實際寫入段落；紅測試先重現 6 處串流失敗、6 處取消失敗與 6 處啟動競態，修正後全過。尚待重新建置與兩版正式 ISO 的真空白磁碟安裝，這些 host 測試不代表映像驗收完成。
- **generic 核心補齊 GCE guest 支援**：新增 generic 專用的 `HYPERVISOR_GUEST`／`PARAVIRT`／`KVM_GUEST`／`PARAVIRT_CLOCK` 設定，並在核心配置後檢查最終 `.config`；缺少必要 guest、VirtIO 或 PCI MSI built-in 就停止建置。既有 host KVM 模組設定不變。回歸測試涵蓋原始 guest 選項缺漏、模組／停用值、缺檔與路徑空白；這項檢查不能取代原生 GCE 開機及安裝驗收。
- **installed initramfs 的 `/run` 權限**：掛載 tmpfs 時明確指定 `mode=0755`，避免沿用核心預設的 1777 後被嚴格公鑰路徑祖先檢查拒絕。只改 initramfs-framework 的掛載選項；不放寬 Dropbear。真正客體的 runtime `/run` 與正常維修登入仍須另外驗證。
- **下載頁的升級說明寫錯版本**：狀態卡寫「從 v0.4.0 經 A/B 更新升上來…還沒驗證」，實際未驗證的是從 v0.3.0 升到 v0.4.0（首頁與 v0.4.0 的 CHANGELOG 都這樣寫），改正。

## [0.4.0] - 2026-10-16 — gateway 改用一般帳號×rootless Podman×SSH 預設關閉（內嵌平台 v1.73.4）

gateway 不再以 root 執行（uid 1000 `duduclaw`），容器改用 rootless Podman，`duduclaw-sysd` 只接受 gateway 主行程並拒絕回退到 gateway 以 root 執行的映像，系統更新改由 sysd 以 root 驗證簽章，SSH 預設關閉、基礎版也有防火牆。實測範圍：qemux86-64 的 `duduclaw-image-appliance-test` 在 GCP builder 的 QEMU（TCG，無 KVM）上跑兩輪驗證（`wiki/reports/rootless-verification/2026-10-15.md`），第二輪 36 項中 35 項通過，唯一未過的是平台 doctor 的標題文字（容器功能已正確停用，標題仍寫 PASS）。**尚未驗證**：從 v0.3.0 經 A/B 更新升到 0.4.0 的路徑（資料擁有權遷移、回退清理）、需要 LLM 憑證的任務沙箱／電腦操作／Discovery 完整流程、Windows VM（需要 KVM）、真機的 Wi-Fi 與音訊、genericx86-64 開機。Secure Boot、dm-verity、TPM2 在發布映像上仍未啟用。


### Added
- **README 首屏加上桌面截圖**：中英兩份 README 第一段說明後面放桌面版首頁截圖（`website/assets/screens/home-dark.png`，與官網共用），圖說標明是 v0.2.0 畫面、v0.3.0 尚未重拍。
- **工廠重置的 root 端**：`duduclaw-factory-reset.service`（`/usr/lib/systemd/system/`）。`duduclaw-sysd` 的 FactoryReset 寫下 `/data/system/factory-reset.pending`（一行 `clear_network=0` 或 `clear_network=1`）後重開機，這個 oneshot 在首開機設定、home-owner、data-migrate、Podman、gateway、kiosk 之前清空 `/data/duduclaw`、`/data/duduclaw-kiosk`，移除 `/data/system/containers/duduclaw`，`clear_network=1` 時清空 `/data/system/iwd`，刪掉 `/data/system/machine-id`（machine-id 搬出 home 之前，重置一向會換新的），重新啟用首開機設定，最後才刪標記。標記格式不對（多一行、內容不符、不是一般檔案、過大）時什麼都不刪、標記保留、unit 失敗；清到一半失敗也保留標記，下次開機重試。目標目錄是符號連結或底下有掛載點就拒絕；內容用 bash glob 列舉、`rm -rf --` 逐項刪，busybox 與 GNU `rm` 都不會跟著連結走。在 Alpine（busybox rm／stat）跑過 18 個情境的腳本測試，全過。需要平台把 wipe 從 gateway 移進 sysd（P6）後才會被用到。

### Security
- **SSH 預設關閉，基礎版也有防火牆**：dropbear 原本在每個映像開機就在 22 埠監聽；基礎版（`duduclaw-image-ab`，一般 `installer` ISO）沒有防火牆，所以區網上連得到。現在 dropbear 預設不啟用（`recipes-core/dropbear/dropbear_%.bbappend`），防火牆從桌面版移到兩版共用的 `duduclaw-image-ab.bb`。
- **維護模式的 SSH 開關可以開關連接埠了**：防火牆新增空的 `maintenance_tcp_ports` 集合，只放行這個集合裡的埠。維護模式開啟時由 `duduclaw-sysd` 啟動 `dropbear.socket` 並把 22 加入集合，視窗關閉時停掉 dropbear、結束連線並移除 22。這段平台程式從平台 v1.73.3 起提供；舊版平台操作的是映像裡不存在的 `ssh.service`，開關不會有作用。
- **關閉 SSH 時結束整個連線**：上游 `dropbear@.service` 是 `KillMode=process`，停掉連線單元只會結束 dropbear 本身，shell 的背景程式、`nohup`、tmux 都會留下。新增 drop-in 改成 `KillMode=control-group`（平台 sysd 關閉時也會清掉 `system-dropbear.slice` 底下所有行程）。
- 目前映像上沒有能透過 SSH 登入的帳號（root 已鎖定，dropbear 預設 `-w` 禁止 root 登入），所以維護模式的 SSH 目前只能控制連接埠；用什麼帳號登入還沒決定。以上已在 QEMU 驗證（見本節開頭）。
- **gateway 改用一般帳號執行（兩版）**：`duduclaw-gateway.service` 原本以 root 執行，現在是固定 uid／gid 1000 的 `duduclaw`（`duduclaw-cli` 以 `inherit useradd` 建立，與 Debian 線同一個 id），保留 `NoNewPrivileges`，新增 `RestrictNamespaces=yes`、`SupplementaryGroups=duduclaw-ipc duduclaw-kiosk`、`XDG_RUNTIME_DIR=/run/duduclaw-gateway`、`TMPDIR=/data/duduclaw/tmp`，以及指向 Podman API socket 的 `DOCKER_HOST`／`CONTAINER_HOST`。AI 員工與 gateway 同一個 uid，所以整套設計以「攻擊者就是 uid 1000」為前提。`duduclaw-sysd` 改成只接受 uid 1000（`--allowed-uid 1000`）。平台正在替 sysd 加 `--require-main-pid-of duduclaw-gateway.service`（只接受 gateway 主程序的請求）與 `--min-rollback-version`；目前內嵌的 v1.73.1 sysd 兩個都不認得，加上去 sysd 會起不來。兩個旗標由 `duduclaw-sysd` recipe 在 `do_install` 依單一變數 `DUDUCLAW_MIN_ROLLBACK_VERSION`（`conf/distro/include/duduclaw-rollback-floor.inc`，目前為空）附加；變數有值但快照沒有這兩個旗標時建置直接失敗。平台快照更新時在同一個 commit 設定這個變數。在那之前，任何 uid 1000 的程序（每個 AI 員工、mcp-server）都能直接呼叫 sysd 的 verb，這是這個階段已知的剩餘風險。這個檢查靠 `kernel.yama.ptrace_scope=1`（AI CLI 不能 ptrace 祖先程序），新增 `50-duduclaw-ptrace.conf` 把它固定下來。
- **`/data/duduclaw` 的擁有者改用 `systemd-tmpfiles` 修正，不再 `chown -R`**：busybox 的 `chown` 會跟著符號連結走，uid 1000 只要在 home 放一個指向 `/etc/shadow` 的連結，下次開機的 `chown -R` 就會把它交出去。新增 `duduclaw-home-owner.service`（root oneshot），在 gateway、Podman、data-migrate、secaudit 啟動前跑一次 `systemd-tmpfiles --create`（`d` 加 `Z`，以 fd 走訪、不跟連結）；設定檔放在 `/usr/share/duduclaw/tmpfiles.d/`，不放 `/usr/lib/tmpfiles.d/`，避免開機早期或手動的 tmpfiles 在 `/data` 還沒掛上、或 gateway 正在跑的時候套用。首開機的 `duduclaw-firstboot-provision.sh` 也改呼叫同一份檔案，kiosk home 的 `chown -R` 換成另一份 tmpfiles 檔。hardlink 仍能讓 `Z` 改到別的 inode，所以同時出貨 `fs.protected_hardlinks=1`、`fs.protected_symlinks=1`（`50-duduclaw-protected-links.conf`）。
- **root 專用的狀態搬出 gateway home**：開機亂數種子（`duduclaw-persist-seed`）、initramfs 綁到 `/etc/machine-id` 的 machine-id、救援模式稽核紀錄都從 `/data/duduclaw/...` 搬到 `/data/system/...`。留在原處的話，任何 AI 員工都能改下次開機的 machine-id 或改稽核紀錄。既有檔案只在仍屬 root 時搬一次（initramfs 與 `duduclaw-home-owner.service` 的 `relocate-root-state.sh`），不跟符號連結，路徑上任何一層是符號連結就不動；新位置已經有檔案時，舊的 root 檔移到 `/data/system/legacy/`，不留在 home 裡被交給 uid 1000。搬移失敗只記 log、不擋 gateway 啟動（root 端已經只讀新路徑）。`duduclaw-data-migrate.service` 與 `duduclaw-secaudit-scan.service` 改以 `duduclaw` 執行：前者的完成標記放在 uid 1000 可刪的目錄，以 root 執行等於讓 AI 員工決定哪支遷移腳本要以 root 重跑；後者原本沒設 `DUDUCLAW_HOME`，`--save` 寫到 root 自己的 `~/.duduclaw`，一併修正。首開機腳本寫進 gateway home 的檔案改經 `setpriv` 以 `duduclaw` 寫入（`runuser` 需要 PAM，這個 distro 沒有）。
- **Flatpak 系統安裝授權與 gateway 脫鉤**：polkit 規則原本對 `duduclaw` 群組放行所有 Flatpak 動作，gateway 改成真的 `duduclaw` 帳號後，等於每個 AI 員工都能不經審批安裝或移除系統 Flatpak。規則改認 `duduclaw-flatpak`（`duduclaw-polkit-flatpak` 建立，不放服務帳號）；平台目前沒有任何 Flatpak 呼叫，功能不受影響。診斷用的 `duduclaw-flatpak-verify` 主群組改成 `duduclaw-flatpak`，不再與 gateway 共用群組。kiosk 那一條（Launcher 的「安裝」）不變。
- **桌面版不再有 setuid 程式**：AI 員工能打到 Podman API，而 Podman 那個 unit 不能設 `NoNewPrivileges`（`newuidmap`／`newgidmap` 要靠 setuid），透過 API 可以讓 podman 在該 unit 裡執行任意主機程式。映像裡只要還有一支 setuid 程式，就離 root 只差一步。`duduclaw-image-compat.inc` 在 rootfs 階段清掉 `newuidmap`／`newgidmap` 以外所有一般檔案的 setuid／setgid 位（shadow 的 su／passwd 等、busybox.suid、fusermount3），並斷言：還有別的 setuid 檔，或白名單那兩支不見了、沒有 setuid，建置就失敗。可能受影響、要在映像上確認的：kiosk 的 `xdg-document-portal` 要靠 `fusermount3` 掛 FUSE（Flatpak app 經 portal 開檔），`dbus-daemon-launch-helper` 只影響沒有 `SystemdService=` 的系統服務啟動。
- **容器連不到主機上的服務**：pasta 以 uid 1000 在主機上替容器開 socket，容器連主機任何位址都從 `lo` 進來，`iif "lo" accept` 會放行，沙箱因此碰得到儀表板（0.0.0.0:18789）與 llama-server（127.0.0.1:8080）。`nftables.conf` 的 output 鏈多了一個空的 `duduclaw_podman_egress` 鏈，`duduclaw-podman.service` 每次啟動時（`ExecStartPre=+`）填入規則：丟掉這個 unit 的 cgroup 在原方向送往 loopback 的封包，放行送往 systemd-resolved stub 的 DNS 與回應方向的封包（主機連進 pasta 發布的連接埠仍可用）。規則沒寫進 `nftables.conf` 本身：nft 載入時會把 cgroup 路徑換成 inode 編號，開機載入防火牆時這個 cgroup 還不存在，整份規則會載入失敗（在 nft 1.1.6 實測：`cgroupv2 path fails: No such file or directory`），而且 unit 重啟後編號會變。規則載不進去時 Podman 不啟動。防火牆以 `systemctl start／restart／reload` 重新載入（`flush ruleset`）時，`duduclaw-podman` 附的 `nftables.service` drop-in 在同一個 job 裡、規則一載入就重新加回守門規則（防火牆重載不會重啟 Podman，容器照常在跑，不能等服務重啟才補）；直接手動 `nft -f` 不會。需要 `CONFIG_NFT_SOCKET`，新增 `duduclaw-rootless.cfg`（另含 `CGROUP_BPF`、`TUN`、netavark 與容器內 iptables 用的 nft／xt 模組）；Docker Desktop 的 linuxkit kernel 沒有 `NFT_SOCKET`，在那裡規則被 kernel 拒絕，正是預期的 fail-closed 路徑。
- **不能再回滾到 gateway 以 root 執行的映像**：新增 `duduclaw-rollback-prune.service`（`duduclaw-ab-update`）。在目前的開機項目通過健康閘門（`boot-complete.target`，之後 `systemd-bless-boot` 才會 bless）之後，刪掉 ESP 上版本低於回滾下限的 `duduclaw-os_<version>.efi`；目前執行中的項目、等於或高於下限的項目、版本解析不出來的項目、救援 UKI 都不碰，執行中的項目本身低於下限或認不出來時什麼都不刪。sysd 的 `--min-rollback-version` 擋得住手動回滾，擋不住 systemd-boot 在新項目連續開機失敗時自動退回上一個項目；bless 之後把舊項目刪掉，這條路也關上。代價是刻意的：rootless 映像一旦證明開得起來，就回不去任何 rootless 之前的映像，出問題只能出更新的版本修。下限比較的是 UKI 裡的 `IMAGE_VERSION`（等於 `DISTRO_VERSION`，形如 `1.73.4-y1-bringup`），不是 repo 根目錄的 OS `VERSION`（0.x 不出現在 UKI 裡，拿它當下限永遠不會擋到東西），所以變數要填第一個 rootless 版本的完整 `DISTRO_VERSION`，寫死一次，不跟著每次建置變動。發版時設為 `1.73.4-y1-bringup`（第一個 rootless 映像）。版本比較（含 `-y1-bringup` 視為 pre-release、boot counter 後綴）在 Alpine bash 跑過 16 個情境測試。
- **工廠重置標記只認 root 寫的**：`duduclaw-factory-reset.sh` 要求標記、`/data/system`、`/data` 都屬 root 且沒有群組／其他人的寫入權限，否則當成格式不對處理（不刪、保留標記）。`/data/system` 由 tmpfiles 以 `0755 root:root` 建立，uid 1000 寫不進去，要清資料只能經過 sysd。
- **本地模型服務不再以 root 執行，root 不再讀 home 裡的設定**：`duduclaw-llama-server.service` 原本以 root 執行，並用 `EnvironmentFile=` 讀 `/data/duduclaw/llama-server.env`，這個檔案 uid 1000 寫得進去，寫一行 `LD_PRELOAD=` 就是 root。改成 `User=duduclaw`，拿掉 `EnvironmentFile=`；新的 `/usr/libexec/duduclaw/llama-server-run` 以 uid 1000 讀這個檔，只認 `LLAMA_MODEL`（須在 `/data/duduclaw/models` 底下）、`LLAMA_CTX`、`LLAMA_PORT`、`LLAMA_EXTRA_ARGS`（拒絕 `--host`／`--port`），固定綁 127.0.0.1；另加空的能力邊界、`RestrictSUIDSGID` 與 kernel 相關的 Protect 選項。重啟走平台 sysd 的 LocalModelService verb。7 個情境在 Alpine bash 測過。同一類的還有兩處：root shell 裡打 `duduclaw`（`profile.d` 的函式）與內建的 AI CLI（`duduclaw-runtime-exec`，root 呼叫且 HOME 指向 `/data/duduclaw` 時）都改經 `setpriv` 以 `duduclaw` 執行，否則 root 會載入 uid 1000 可改的設定與 hook。`/usr/bin/duduclaw` 寫完整路徑仍以 root 執行，這是刻意留下、看得出來的例外。
- **A/B 更新改從 root 擁有的目錄安裝**：三個 sysupdate transfer 原本從 `/data/duduclaw/updates` 安裝，那是 uid 1000 的目錄，sysupdate 對 `Type=regular-file` 來源不做任何驗證。平台快照更新後（同一個變數 `DUDUCLAW_MIN_ROLLBACK_VERSION`），`duduclaw-ab-update` 會把 `Path=` 改成 `/data/system/updates`（tmpfiles 建 0700 root），由 sysd 的 `SysupdateStageApply` 清空、驗證 minisign 簽章的 SHA256SUMS、只複製驗證過的檔案，並檢查 UKI 的 `IMAGE_VERSION` 不低於下限且新於目前版本，再執行 sysupdate。transfer 檔頭說「驗證是 gateway 的事」的段落已更新。
- **沒有平台守門就烤不出映像**：`duduclaw-image-ab`（桌面版也 require 它）在 `do_rootfs` 前檢查 `DUDUCLAW_MIN_ROLLBACK_VERSION`，空的就停，沒有開關可以略過。這個分支在平台快照更新前不能產出 rootless 映像。sysd 旗標的偵測改成兩道：`src/main.rs` 裡緊接在 `#[arg(long` 下的欄位宣告，以及編好的 sysd 執行檔裡的長選項字串（clap 會把它編成字串常數），兩者都不能靠註解滿足；拿平台分支的 sysd 實際編譯驗證過兩個旗標都偵測得到、v1.73.1 快照偵測不到。
- **建置時也擋 file capability 與延後的 postinst**：`duduclaw-image-compat.inc` 新增 `duduclaw_check_filecaps`，rootfs 裡任何一般檔案帶 `security.capability` 就讓建置失敗（`newuidmap`／`newgidmap` 維持 setuid，不用 fcaps）；`/etc/*-postinsts` 裡還有第一次開機才跑的 postinst 也失敗，因為它們會在檢查之後才執行。這個檢查靠 bitbake 的 fakeroot worker 讓 `os.getxattr` 看得到 pseudo 記錄的 xattr，要在實際建置時刻意放一個帶 capability 的檔案確認它真的會擋。Podman unit 加上 `InaccessiblePaths=`（systemd 私有 socket、系統 D-Bus socket、`/run/duduclaw`、`/run/duduclaw-kiosk`），Podman API socket 移到 root 擁有的 0711 目錄 `/run/duduclaw-podman/`，uid 1000 拿不掉也換不掉它。
- **`/data` 掛載加上 `nosuid,nodev`**：兩份 wks、LUKS 的 data-open generator 都加；initramfs 暫時掛載 `/data` 時另加 `noexec`。`/data` 上沒有東西需要 setuid 或裝置節點（不加 `noexec`，使用者自裝的 AI runtime 與 Flatpak app 要能執行）。Waydroid 在 `nodev` 下還沒重測。
- **TPM 狀態檔搬出 home**：`duduclaw-data-status.service` 改寫 `/data/system/tpm-status.json`（0644、先寫暫存檔再改名）。平台目前沒有任何程式讀這個檔。
- **工廠重置也清 Windows 虛擬機登記與遷移留下的舊檔**：清空 `/data/system/windows-vm`、移除 `/data/system/legacy`（22 個情境測過）。
- **已知缺口（設計取捨）**：第一個 rootless 映像還沒 bless 之前，systemd-boot 的自動回退仍以舊的 root gateway 項目為備援。新映像上的 AI 員工以 uid 1000 執行，可以故意讓試開機失敗（讓 gateway 不回應 `/healthz`），三次後裝置就回到 gateway 以 root 執行的映像。要關掉這條路，就得在新項目證明開得起來之前刪掉舊項目，等於放棄壞掉更新的回滾；窗口只有幾次開機，而且需要新映像上已經有 agent 程式在跑。第一次 bless 之後 rollback-prune 會刪掉舊項目。
- **再審後的收尾**：root shell 與 AI CLI 降到 uid 1000 時加上 `--no-new-privs`；stdin 不是終端機時另以 `setsid -w` 開新 session、不帶 root shell 的終端機；互動式 CLI 需要終端機而保留，改靠 kernel 拒絕非特權的 TIOCSTI（`duduclaw-rootless.cfg` 設 `CONFIG_LEGACY_TIOCSTI` 為關、`50-duduclaw-tiocsti.conf` 設 `dev.tty.legacy_tiocsti = 0`），hook 或 MCP server 不能把按鍵塞回 root shell。`profile.d` 的函式只在登入 shell 生效，`sh -c duduclaw` 仍以 root 執行，文件寫明。A/B 健康閘門讀 `config.toml` 的 port 改以 uid 1000、最多 64 KiB、5 秒逾時讀取（uid 1000 原本可以把它指向 `/dev/zero` 或 FIFO 讓健康檢查卡住，觸發試開機回退）。Podman unit 的 `InaccessiblePaths` 再加 systemd 的 varlink socket 與 udev 控制 socket。`SECURITY.md` 改寫：只有 A/B 映像會在沒有下限時拒絕建置，非 A/B 的開發映像 sysd 只檢查 uid。
- **第一次實機 QEMU 驗證後的修正（F1–F6）**：證據在 `wiki/reports/rootless-verification/2026-10-15.md`。那次建出的映像上 `duduclaw-podman.service` 根本起不來，以下全部修好前不能出貨。
  - F1：首開機與每次工廠重置後，`ReadWritePaths=/data/system/containers/duduclaw` 指向還不存在的目錄，連 `ExecStartPre=+` 都在建 namespace 時失敗（226/NAMESPACE）。容器儲存區目錄改由 `/usr/lib/tmpfiles.d/duduclaw-containers.conf` 在開機時建立，`ExecStartPre` 照樣重跑一次（工廠重置後才補得回來），`ReadWritePaths` 這一項加上 `-`。
  - F2：能力邊界只留 `CAP_SETUID CAP_SETGID` 時，setuid 的 `newuidmap` 打不開也寫不進別的程序的 `uid_map`。實機二分的結果是要 `CAP_SETUID CAP_SETGID CAP_DAC_OVERRIDE CAP_SYS_ADMIN`（不需要 `CAP_SETFCAP`）。映像裡只有 `newuidmap`／`newgidmap` 是 setuid、沒有任何 file capability，uid 1000 的程序本身在這個 unit 裡沒有任何能力，所以邊界放寬到這四個可以接受。
  - F3：`podman run` 要寫 `$HOME/.cache/containers`，被 `ProtectSystem=strict` 擋下。`XDG_CACHE_HOME` 改指到儲存區裡的 `.cache`，gateway home 對這個 unit 維持唯讀。
  - F4：`ProtectKernelTunables=yes` 讓 netavark 設不了 `ip_forward`，也讓 crun 掛不上容器的 `/proc`（kernel：`Mount too revealing`），已從 Podman unit 拿掉。拿掉之後 netavark 的 bridge 網路與對外連線都正常，所以不需要平台的 pasta 模式備案（P11）。
  - F5：kernel 沒開 `CONFIG_CFS_BANDWIDTH`，cgroup 沒有 `cpu.max`，所有帶 CPU 上限的容器（任務沙箱、電腦操作、discovery、腳本沙箱）都會失敗。`duduclaw-rootless.cfg` 加上 `CONFIG_CFS_BANDWIDTH=y`（相依的 `FAIR_GROUP_SCHED` 原本就有）。
  - F6：有容器在跑時 Podman unit 重啟不了（`Failed to spawn executor: Device or resource busy`），`systemctl restart nftables` 會透過 `PartOf=` 觸發這個狀況。改成 `KillMode=mixed`（停止或重啟時連同委派出去的容器 cgroup 一起清掉，正在跑的沙箱會被終止，這是刻意的）、`TimeoutStopSec=30`，並拿掉對 `nftables.service` 的 `PartOf=`／`Requires=`（只留 `Wants=` 與 `After=`）。防火牆重載後由 `nftables.service` 的 drop-in 重新加回守門規則，不會重啟 Podman；規則加不回去時，守門腳本會停掉 Podman（連同所有容器）並讓 `nftables.service` 失敗。
  - 另外：`modules-load` 加上實測會自動載入的 `nft_chain_nat`；gateway 加上空的 `CapabilityBoundingSet=` 與 `AmbientCapabilities=`（實測 `CapInh` 有 `CAP_SETPCAP`／`CAP_SYS_ADMIN`，來源推測是 systemd executor 為了安裝 seccomp 過濾而保留，未確認；gateway 不需要任何能力）；`duduclaw-sysd` 與 `duduclaw-llama-server` 的 `StartLimit*` 搬到 `[Unit]`（放在 `[Service]` 會被忽略）；兩個 unit 的相對路徑 `Documentation=` 改成註解；驗證清單的 `as_gw` 補上 `HOME`／`USER`／`LOGNAME` 與工作目錄，並避開映像上沒有的 BusyBox applet。
  - `duduclaw-rootless.cfg` 裡以 `CONFIG_` 開頭的註解行改寫，kernel-cache 稽核不再把它們誤報成設定。
  - 這些修正在第二輪 QEMU 驗證（`5d332c8`）確認過。
- 除了上面那次實機驗證涵蓋的部分，其餘 gateway 去 root 與容器堆疊的項目都還沒在建好的映像上建置或開機。做過的只有靜態檢查（`bash -n`／`sh -n`）與容器裡的行為測試：tmpfiles 設定（systemd 259 的 `systemd-tmpfiles`）、工廠重置（21 個情境）、`relocate-root-state.sh`（8 個）與回滾清理（16 個），後三者在 Alpine 的 busybox 上跑；Podman unit 的硬化組合在 systemd 257 容器裡確認不會隱含 `NoNewPrivileges`、`ExecStartPre=+` 執行時 unit 的 cgroup 已存在。審查後加的 comp 音量 verb 在 Linux 容器裡跑過 `cargo test`。

### Changed
- **平台快照同步到 v1.73.4（1.73.1→1.73.4，`scripts/sync-platform.sh`）**：`duduclaw-cli`／`duduclaw-sysd` 快照自平台重新 vendor（`duduclaw-comp`／`duduclaw-shell` 自本 repo `crates/` 重新快照），`duduclaw-platform-version.inc` 1.73.1→1.73.4（連動 `DISTRO_VERSION`、os-release `VERSION_ID`、UKI 檔名、A/B loader 項），兩個平台 recipe 改名 `_1.73.4.bb`。crates.io 依賴集合有變（duduclaw-cli duduclaw-sysd），`*-crates.inc` 已重生。OS 自己的 release 版本（`VERSION`）不受影響。
  帶進的平台 commit：
    - b8d16c87 chore: bump v1.73.4
    - 11837055 Merge pull request #127 from zhixuli0406/docs/next-os-image-qualifiers
    - e87e08ba docs: say the rootless notes apply from the next DuDuClaw OS image
    - a6b75534 Merge pull request #126 from zhixuli0406/docs/sysd-verb-count
    - cd199bfe docs: duduclaw-sysd has 18 fixed commands, not 17
    - 102f7a00 Merge pull request #125 from zhixuli0406/feat/os-rootless-platform
    - 4a9b689c fix(sysd): remove leftover staging directories at the start of each stage
    - f25d7641 Merge origin/main (v1.73.3) into feat/os-rootless-platform
    - 7d058585 fix(sysd): serialise update verbs, verify before placing, openat source; e2e tests
    - 0f2dbd6f feat(audio): drive volume through comp's shell_control verbs on the appliance
    - 6a9ed425 feat(sysd): verify and stage OS updates as root (SysupdateStageApply)
    - d008345c fix(sysd): pidfd-based main-process check, bounded verification, Type #1 guard
    - f3704a78 feat(sysd): refuse rollbacks to images older than a configured floor
    - 01dbab46 feat(os): route the os_* MCP tools to sysd through the gateway
    - 351680b6 fix(sysd,container): address the security review of the rootless platform work
- **README 改以英文為主**：`README.md` 換成英文版，繁中版移到 `README.zh-TW.md`，兩份頂端互相切換（反轉 0.1.0 前「改以繁體中文為主」的決定，讓 GitHub 首頁對海外讀者可讀，與平台 repo 一致）。文件站對應同步：`docs-site/scripts/sync-docs.mjs` 改讀 `README.zh-TW.md` 產生 `/docs/os/readme/`、`README.md` 產生 `/docs/en/os/readme/`，網址不變；`docs-site/README.md`、`docs/README.md`、`CLAUDE.md` 與 `pages.yml` 的路徑註解一併更新。本機 `astro build` 確認兩個語言頁的內容與截圖正確。
- **文件與官網改成 v0.3.0 的事實**（`README.md`、`README.en.md`、`meta-duduclaw/README.md`、`SECURITY.md`、`docs/README.md`）：版本徽章、狀態列、信任鏈與測試範圍從 v0.2.0 改到 v0.3.0。測試範圍照 Release 與 `wiki/impl/gcp-builder-2026-10.md` 寫：qemux86-64 整碟映像在無頭 QEMU（TCG、無 KVM）開到登入畫面，同機型兩個安裝器 ISO 開到 live 環境的自動登入；安裝精靈沒有跑；genericx86-64 只建置、沒有開機；沒有真機。Secure Boot／dm-verity／TPM 在 v0.3.0 仍未啟用：建置用的是 `kas/release-linux-builder.yml`，沒有疊加 `sb-signing.yml`／`tpm-luks.yml`；2026-10-14 拆開兩個發布 wic 查證，兩槽 UKI、rescue UKI 與 systemd-boot 的 PE 簽章表都是空的、ESP 沒有 enroll 金鑰、GPT 沒有 verity 分割、UKI initrd 沒有 tpm2／cryptsetup。`meta-duduclaw/README.md` 原本寫「QEMU 機型三種產物都開機驗證過」，與 v0.2.0 的實際紀錄不符，一併改正。
- **`docs/guides/ai-runtimes.md`**：拿掉「清單對應映像內嵌的平台版本（v0.2.0 為 1.63.0）」。v0.3.0 與 v0.2.0 用的是同一份 2026-09-05 產生的 AI runtime 包（recipe 的 `DUDUCLAW_AI_RUNTIMES_DATE` 兩版都是 `20260905`），表格補上各 CLI 的版本（取自包內 `MANIFEST.txt`）；十個 CLI 都在平台 1.73.1 的 runtime catalog 裡。Gemini CLI runtime 的移除版本照 1.73.1 快照改為 v1.74.0（原寫 v1.71.0）；「未內建」補上 Google Antigravity（`agy`），在 v0.3.0 映像上安裝它沒有測過。README 的 AI 工具鏈段落同步。
- **官網換成 v0.3.0**（`website/`）：`site.js` 的 `RELEASE`（版本、日期 2026-10-14、平台 1.73.1、上一版 v0.2.0、`downloadBase` 與六個資產的檔名、位元組、大小），下載頁與首頁的版本列、標題、按鈕、狀態卡、測試範圍徽章、`dd` 範例檔名與回舊版卡片（改指 v0.2.0）。下載頁的 QR code 原本編的是 v0.2.0 的 ISO 網址，改用同一套規則重產（version 11、錯誤修正 H，規則寫在 `website/README.md`；用同規則重產 v0.2.0 網址與原 path 逐位元組相同）。首頁六張截圖仍是 v0.2.0 的畫面，說明文字標明 v0.3.0 還沒重拍。全部 18 個資產網址與兩個 Release 頁以 `curl -sIL` 確認都是 200，資產的 Content-Length 與 Release 記錄的大小相同。本機 `scripts/build-site.sh` 建置後，全站內部連結與錨點檢查 0 個斷掉；headless Chromium 在桌機 1440 與手機 390 寬度開下載頁，沒有 console 錯誤、沒有水平捲動，QR code 截圖以 jsQR 解出的正是 v0.3.0 的 ISO 網址。
- **`/data/system/windows-vm` 改由 gateway 擁有**：Windows RemoteApp 登記檔由 gateway 寫入，gateway 不再是 root，所以目錄改成 `0755 duduclaw:duduclaw`（tmpfiles 行從 `duduclaw-data-binds` 移到 `duduclaw-cli`，基礎版也有），遷移 1788717600 不再 `install -o root`。
- **kiosk 讓 comp 認得 gateway**：`duduclaw-kiosk.service` 設 `DUDUCLAW_SHELL_CONTROL_AGENT_UID=1000`，comp 的 shell-control socket 才會把 uid 1000 當成 AI 代理端。
- **comp 的 IPC 交給 `duduclaw-ipc` 群組**（`duduclaw-comp` 1.65.2）：shell-control 與 codrive 兩個 socket 從 0600 改成 0660、codrive token 從 0600 改成 0640，群組都是 `duduclaw-ipc`（成員只有 kiosk 帳號與 gateway）。gateway 不再是 root，0600 會把它擋在外面；開給 `duduclaw-kiosk` 群組又會連 `duduclaw-flatpak-verify`（以及它跑的 Flatpak app）一起放進來。先改群組再放寬權限，token 用同一個 fd 改，不留空窗。群組不存在或 chown 被拒時維持 0600，並在 journal 記一行原因。驗證邏輯不變（SO_PEERCRED、bearer token）。新增 `src/ipc_access.rs` 與 11 個單元測試，macOS 上單獨編譯這個模組的測試也全過。
- **gateway 可以呼叫 iwd，只限網路頁用到的介面**：`duduclaw-network-config` 新增 D-Bus policy，`duduclaw` 只能呼叫 iwd 的 Station、Network、KnownNetwork、AgentManager 介面，以及 GetManagedObjects 與 Properties 的 Get／GetAll（iwd 自己的 policy 只放行 root 與本映像沒有的 `netdev` 群組）。AccessPoint、WPS、DPP、AdHoc、P2P 與任何 Properties.Set 都不放行；介面清單對應平台 v1.73.x 的 `network/iwd.rs`。
- **gateway 的音量控制改走 comp**（`duduclaw-comp` 1.65.2）：PipeWire socket 是全有或全無，連得上就能錄麥克風、接螢幕串流，不能交給 AI 員工共用的 uid 1000。comp 的 shell-control socket 新增三個代理端可用的 verb：`get_audio`（預設輸出的音量、靜音與 `wpctl status` 原文）、`set_audio`（`volume_pct` 0–100 及／或 `muted`）、`set_audio_output`（以數字 id 切換預設輸出），由 comp 以 kiosk 帳號、固定參數呼叫 `wpctl`，在 socket 執行緒上跑、3 秒逾時，設定類操作寫入稽核。kiosk 啟動腳本把 `pipewire-0`／`pipewire-0-manager` 改成 0600。平台的 `audio_bridge.rs` 要改成呼叫這三個 verb，在那之前 rootless 的 gateway 調不了音量。
- **桌面版的容器引擎換成 rootless Podman**：`docker runc docker-compose` 換成 `podman crun podman-compose passt duduclaw-podman shadow`。`duduclaw-os.conf` 設 `CONTAINER_PROFILE = "podman"` 與四個 `VIRTUAL-RUNTIME_container_*`、`PACKAGECONFIG:append:pn-podman = " rootless"`、`SYSTEMD_AUTO_ENABLE:pn-podman = "disable"`（不啟用 root 的 `podman.socket`）。新 recipe `duduclaw-podman`：`duduclaw-podman.socket`（`/run/duduclaw-podman/podman.sock`，0600，uid 1000）與 `duduclaw-podman.service`（`podman system service --time=0`，以 `duduclaw` 執行，`Delegate=yes` 加 `DelegateSubgroup=supervisor`，只有 `Delegate=yes` 時 `--memory` 等限制會靜默失效；`KillMode`（實機驗證後為 `mixed`）、`ProtectSystem=strict`、`CapabilityBoundingSet`（實機驗證後為 `CAP_SETUID CAP_SETGID CAP_DAC_OVERRIDE CAP_SYS_ADMIN`）、`RestrictSUIDSGID=yes`、`ProtectKernelModules`，不設 NNP），root shell 的 `CONTAINER_HOST`（`/etc/profile.d/duduclaw-podman.sh`，讓操作者 `podman pull` 的映像進 gateway 的儲存區），以及暫定的 `modules-load.d` 清單（要在映像上用 `lsmod` 差分確認）。`container-host-config` 的 bbappend 把 `storage.conf` 改成 overlay、`rootless_storage_path = "/data/system/containers/duduclaw"`（寫死帳號名，經 `setpriv` 或沒有 `USER` 環境變數的 shell 啟動的 podman 才不會解析到別的路徑），並加 `containers.conf.d/50-duduclaw.conf`（cgroupfs、pasta 加 `--no-map-gw`、nftables 防火牆驅動、tmp 與事件檔放在共用的 runtime 目錄）。`/etc/subuid`、`/etc/subgid` 在 rootfs 階段寫入 `duduclaw:100000:65536`。Windows 虛擬機改在 rootless Podman 下跑，標為實驗功能（`docs/guides/app-compat.md` 三語同步）。
- **內嵌平台更新到 v1.73.4**：用 `scripts/sync-platform.sh` 更新快照，帶入平台端的 rootless 修改（Docker 探測改用 `version`、工廠重置由 sysd 處理、本地模型改經 sysd 重啟等）；`duduclaw-sysd.service` 依回退下限帶上 `--require-main-pid-of duduclaw-gateway.service` 與 `--min-rollback-version`。驗證清單：`wiki/eval/rootless-verification-2026-10.md`（設計的 V1–V25 對應到 GCP QEMU 上要跑的指令，加上實作新增的檢查）。說明文件：`meta-duduclaw/README.md` 新增「Service accounts and privileges」，`SECURITY.md` 新增「Runtime Privilege Model」。

### Removed
- 桌面版移除 `docker`、`runc`、`docker-compose` 與 `var-lib-docker.mount`（`/data/system/docker` 的 tmpfiles 行與 early 服務的建立步驟一併拿掉）。既有的 `/data/system/docker` 不刪，回滾到舊映像時資料還在；新舊兩邊的儲存區互不相干。

### Fixed
- **`release-os.sh smoke` 不再被無害的 kernel 訊息判成失敗**：提早結束輪詢的樣式原本包含裸字串 `failed with error`，guest kernel 找不到 `regulatory.db` 時印的「Direct firmware load for regulatory.db failed with error -2」也會命中。2026-10-14 在 GCP builder 上測 v0.3.0 安裝器 ISO 時，同一個樣式把正常開機的 QEMU 提早砍掉（`wiki/impl/gcp-builder-2026-10.md`）；`release-os.sh` 自己的 wic smoke 這次是先到登入畫面才沒中。現在只認 runqemu 與 kas 自己的錯誤行：`runqemu - ERROR`、kas 的 `- ERROR … - Shell returned non-zero exit status`，以及 kas 的 `Command "…" failed with error <n>`／`Command "…" failed:` 兩種寫法；guest 端的 systemd unit 失敗照舊不列入（smoke 只檢查能不能到登入畫面）。樣式漏掉的真實失敗仍會走 timeout 分支、一樣判失敗，只是比較慢，不會放行壞映像。兩個樣式改成 `SMOKE_LOGIN_RE`／`SMOKE_DIED_RE` 變數，新增 `scripts/tests/smoke-patterns.sh` 與 `scripts/tests/fixtures/smoke/` 範例（runqemu／kas 錯誤行取自 `wiki/reports/bring-up-evidence/` 的實際 log；kernel 那幾行是上游 kernel 的訊息格式，v0.3.0 當時的原始 log 沒有留下）。macOS 的 BSD grep 與 GNU grep 3.11 都跑過，22 個案例全過；改回舊樣式時這支測試會失敗 4 個案例。

## [0.3.0] - 2026-10-13 — 內嵌平台 v1.73.1×鎖定畫面免信箱解鎖（shell 1.65.3）×GCP builder

內嵌的 DuDuClaw 平台從 v1.63.0 跳到 v1.73.1；鎖定畫面改用平台 v1.73.1 新增的本機擁有者驗證端點，換過信箱的擁有者也能解鎖（`duduclaw-shell` 1.65.3）。這一版第一次在 GCP 的 Linux builder 上建置，簽章仍只在維護者的 Mac 上進行。產物矩陣與 v0.2.0 相同：兩個機型各一份整碟映像 `.wic.zst`、基礎版與桌面版安裝 ISO。

### Added
- **`scripts/release-os.sh package --no-sign` 與 `sign` 子命令**：遠端 builder 不放簽章金鑰。builder 上 `package --no-sign` 只做 smoke 閘門、壓縮、sha256 與 manifest；複製回持有金鑰的機器後 `sign` 先核對 `.sha256` 與 manifest 記錄的 sha256／大小，再 `minisign -S` 並以釘住的公鑰自驗。簽章與自驗邏輯與 `package` 共用同一個函式。
- **`meta-duduclaw/kas/release-linux-builder.yml`**：給 16 vCPU／64 GB Linux builder 的 release overlay，和 `serial1.yml` 一樣關掉 SPDX，但不做 `-j1`（`BB_NUMBER_THREADS` 8、`PARALLEL_MAKE` `-j 8`）。以 `DUDUCLAW_OS_KAS_OVERLAY` 指定。
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
  Pagefind。**站內任何位置都不連 GitHub**（2026-10 起頁首例外放 OS repo 的 GitHub 圖示，見 Fixed）：關掉 editLink、內文指向
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

### Security
- **Static-site CSP (2026-10)**: permit only `https://img.shields.io` as the additional image origin for existing public documentation badges; other CSP directives and OS image/platform versions are unchanged.
- **Static-site response headers (2026-10-11)**: preserve server-level CSP and security headers on cacheable assets; use relative redirects behind the Cloud Run proxy and hide nginx version details. Site bytes, OS images, and release metadata are unchanged.
- **Website build dependencies (2026-10-11)**: refresh the documentation lockfile, pin the patched selector parser to 7.1.6, and update sharp to 0.35.5. This changes the static site build tooling only; OS images, embedded platform version, and release asset URLs remain unchanged.

### Fixed
- **鎖定畫面不再需要知道擁有者信箱**（`duduclaw-shell` 1.65.3）：解鎖時先呼叫平台 v1.73.1 起提供的 `POST /api/owner/verify`（只收本機連線、只送密碼），所以非個人版或關掉自動登入、又換過信箱的擁有者也能解鎖。只有收到 200 且內容是 `{"ok":true}` 才算通過；舊版平台不認得這個路徑時退回原本的信箱登入流程，不會因為後備頁面而誤判解鎖。
- **鎖定畫面改用擁有者目前的信箱驗證密碼**（`duduclaw-shell` 1.65.2）：平台 v1.73.0 起擁有者可以把預設的 `admin@local` 換成自己的信箱（首次設定表單、儀表板提示或帳號設定頁）。殼的鎖定畫面原本固定用 `admin@local` 呼叫 `/api/login`，換過信箱後正確密碼也會被拒。現在每次解鎖前先從本機 session（`/api/session/local` 回應的 `user.email`）讀出擁有者信箱再登入；拿不到本機 session 時（自動登入關閉、非個人版、舊版 gateway）退回 `admin@local`，原因寫到 stderr。代價是每次解鎖嘗試多一次本機往返和一筆 `login_local_auto` 稽核紀錄。已知限制：非個人版或關掉自動登入、又換過信箱的值班機，鎖定畫面仍會用 `admin@local`，需要平台另外提供不需信箱的擁有者驗證。
- **Website links (2026-10-11)**: resolve raw HTML documentation links through the same public-page mapping as Markdown and correct stale localized section links. Keep the download navigation linked to an existing home section. No platform documents or OS release artifacts are modified.
- **官網與文件站事實查核（2026-10）**：對照 GitHub Release、layer 原始碼與 `wiki/` 證據修正首頁與下載頁。
  安裝器 ISO 不再標「QEMU 實開機驗證」（v0.2.0 只有整碟映像跑過開機測試）；Steam 不在離線倉庫，改說走 Flathub；
  管理後台在 18789 埠（`duduclaw.local` 沒有任何元件提供）；防火牆開 18789 與 mDNS、映像內有 dropbear SSH
  （桌面版被防火牆擋、基礎版可連），不再寫「所有連入埠關閉、SSH 出廠關閉」；`duduclaw-sysd` 是 15 個固定指令不是 6 個；
  gateway 仍以 root 執行；自動回滾只在早期 Debian 線做過故障注入，這套映像實測的是套用與手動回滾；
  首頁六張桌面截圖改用 v0.2.0 發布映像在 QEMU 上重拍（2026-10-07，映像核對過 Release 的 SHA-256 與 minisign 簽章；示範帳號「Demo」、未設定 AI 授權，原本深色首頁那張的示範任務卡因此拿掉，說明文字同步）；拿掉「安裝 8 分鐘」與硬體售價。
  首頁與下載頁頁首、頁尾加上平台網站 <https://duduclaw.dudustudio.monster/> 連結，文件站頁首加上平台網站文字連結與 OS repo 的 GitHub 圖示按鈕（和主站頁首同一個單線圖示）。
- **文件站 app 相容層連結斷掉**：指南 2026-09-29 搬進本 repo 後，`/docs/guides/app-compat/` 已無來源；
  首頁、下載頁、三個語言的文件站首頁、入門側欄、`README*.md` 與 `docs/README.md` 改指 `/docs/os/guides/app-compat/`。
  `sync-docs.mjs` 補上本 repo `docs/<dir>/zh-TW/`、`ja-JP/` 的語系對應（先前譯文被當成獨立頁面掛在 `os/guides/zh-TW/…`），
  並保留 `SECURITY.md` 的 Security Advisories 連結（先前被轉成純文字，私下回報的首選管道在文件站上沒有網址）。
- **README／指南內容**：`README.en.md` 誤寫 Steam 預載（中文版正確）、兩份 README「兩式產物」改為三個；
  補上平台 Gemini CLI runtime 棄用（預定平台 v1.71.0 移除）的說明；app 相容層指南拿掉過時的 CP-1 註記並寫明各元件驗證程度，
  日文版「ランダムに出荷」誤譯與中文版簡體字一併修正。本檔 0.2.0／0.1.0 段落內互相矛盾的「無頭」「Secure Boot 已有」敘述加註更正，
  誤歸在 Removed 底下的發布產線變更移到 Changed。
- **`SECURITY.md`「Release Artifact Security」敘述漏掉第三種發布產物、且誤植兩種 ISO 都有
  `.manifest.json`**：改為正確描述每機型三種產物（wic 桌面版、installer 基礎版 ISO、
  installer-desktop 桌面版 ISO），三者皆附 `.sha256`／`.minisig`，但 `.manifest.json` 只有
  wic 才有（以 `artifacts/os/v0.2.0/` 下實際產物核對）。

### Changed
- **內嵌平台同步到 v1.73.1（1.63.0→1.73.1，`scripts/sync-platform.sh`）**：`duduclaw-cli`／`duduclaw-sysd` 快照自平台 tag `v1.73.1` 重新 vendor（含依 `web/` 重建的 dashboard `dist/`），`duduclaw-comp`／`duduclaw-shell` 自本 repo `crates/` 重新快照；`duduclaw-platform-version.inc` 1.63.0→1.73.1（連動 `DISTRO_VERSION` `1.73.1-y1-bringup`、os-release `VERSION_ID`、UKI 檔名、A/B loader 項），兩個平台 recipe 改名 `_1.73.1.bb`。兩份平台快照的 crates.io 依賴集合都變了，`duduclaw-cli-crates.inc`（`bitbake -c update_crates`）與 `duduclaw-sysd-crates.inc`（`gen-crates-inc.py`）已重生。平台這段期間的變更（去識別化、Discovery、任務／腳本沙箱、`computer_*` 工具、授權修補、代理平台 P0～P2、擁有者信箱與本機擁有者驗證端點等）見平台 repo 的 `CHANGELOG.md`。
- **`duduclaw-cli/refresh-src.sh` 對齊 v1.73.1 的 workspace**：成員閉包重新推導（平台移除 `duduclaw-cli-worker`、新增 `duduclaw-db`，`duduclaw-desktop` 已無成員引用而移出，現為 22 個）；快照多帶 repo 根目錄的 `fixtures/`（gateway 非測試程式碼以 `include_str!` 內嵌）與 `vendor/`（根 `Cargo.toml` 的 `[patch.crates-io] serenity` 指向它）。
- **`duduclaw-cli` recipe 接上第一個 git 依賴 `ucci`**：v1.73.1 的 `duduclaw-inference` 以 git rev 無條件依賴 `ucci`（MIT，crate 在該 repo 的 `rust/` 子目錄）。`bitbake -c update_crates` 只產生 crates.io 項目，所以 recipe 另加 `git://…;name=ucci;subpath=rust;destsuffix=ucci` 與 `SRCREV_ucci`，由 oe-core `cargo_common.bbclass` 轉成 cargo `[patch]` 並從 lock 拿掉 git source 行；`CARGO_LOCK_PATH` 指到快照根目錄的 workspace lock。
- **`duduclaw-cli` recipe 開啟 `app-compat` feature**：v1.73.1 的快照定義了這個 feature，不開的話映像會少掉殼與 `compat.d/windows-vm.toml` 會呼叫的 `duduclaw compat`。
- **官網資訊呈現（2026-10-11）**：首頁改依用途 → pre-GA 狀態 → 內附 AI 工具 → 真實 QEMU 桌面 → 交辦與接手 → 核心能力 → 版本／硬體／入門 → 資料安全 → FAQ → 試用的閱讀路徑，移除「第一」與概括競品比較，合併重複技術說明。下載頁提前版本與安裝方式選擇、補閱讀結尾 CTA；資料說明區分本機儲存與雲端模型傳送，企業 DuDuClaw 導向既有總經銷。保留原有視覺與互動，FAQ 原生可展開，無 JS 時桌面六張圖集全部可讀。發布 metadata、資產 URL 與驗簽公鑰不變。
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
- **平台快照全面同步到 v1.63.0（gateway 跟主 repo 對齊）**：`duduclaw-cli`／`duduclaw-comp`／`duduclaw-sysd` 快照重新 vendor（shell 已於 73ab67b 更新），`duduclaw-platform-version.inc` 1.62.0→1.63.0（連動 `DISTRO_VERSION`、os-release `VERSION_ID`、UKI 檔名 `duduclaw-os_1.63.0-y1-bringup.efi`、A/B loader 項），四個 recipe 檔名改為 `_1.63.0.bb`；dashboard `dist/` 依平台 111d748b 重建後才 vendor。帶進的平台變更：帳號憑證硬化（真探測取代 auth status 假陽性、auth-dead 退避、壞憑證載入排除、寫入前驗證、認證失效告警，b787c48a）、dashboard 帳號卡憑證狀態徽章＋新增帳號對話框顯示伺服器真實錯誤（111d748b）、Launcher 頁腳「⌘K 隨時喚起」（50b5acc0）。四份快照的 crates.io 依賴集合與 1.62.0 相同，`*-crates.inc` 未動。OS 自己的 release 版本（`VERSION` 檔）不隨平台同步改動。
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
  live 安裝器，寫入 `duduclaw-image-ab`；當時寫成「無頭」，同版下方「README／SECURITY 修正信任鏈與版本敘述」一條已更正：基礎版有同一個桌面殼）、v0.1.0 的驗簽與燒錄步驟，以及
  「真機尚未開機驗證」的狀態。
- **`meta-duduclaw/README.md` 改寫為精簡的 layer 參考**（layout、各 image 的角色、
  builder 容器與 `kas build`、QEMU 開機、machine 別名陷阱）；原本 482 行的
  bring-up 敘事原文不動搬到 `wiki/impl/meta-duduclaw-bring-up-notes-2026-08.md`。
- **重新歸檔 L2 文件**：`meta-duduclaw/REAL-HW-CHECKLIST.md` →
  `wiki/eval/real-hw-acceptance-checklist-y6-3-2026-08-26.md`（加註前提已過時：
  IME 自 Y7 起已在 image、v0.1.0 已有 A/B＋唯讀 root＋安裝器 ISO；Secure Boot 只在 layer 接好，發布映像未啟用）；
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
- **README 補上桌面環境**：先前把整個 OS 寫成無頭值班機，漏掉自家 compositor／殼（首頁、視窗切換、鎖定畫面、控制中心、Cmd+K 交辦列）、首次設定精靈、IME／音訊／XWayland、app 相容層（Flatpak／Bottles／Windows VM／Waydroid）。首段改為「AI 原生住民的桌面作業系統，另有無頭版」，新增「桌面環境」一節，並標清兩式產物的差別：整碟 `.wic.zst`＝桌面版、安裝器 `.iso`＝基礎版（此處原寫「無頭版」，已由上方「README／SECURITY 修正信任鏈與版本敘述」一條更正）；桌面版無螢幕時的行為尚未在真機定義。


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

### Changed（發布產線；原誤歸在 Removed 底下，2026-10 移到這裡）
- **live 安裝 ISO 載荷壓縮改 `zstd -19 --long=27`**（`DUDUCLAW_INSTALL_PAYLOAD_ZSTD` 可調）：desktop 版 ISO 在舊的 -3 下達 2.66GB，超過 GitHub 單資產 2GiB 上限；改後 qemu 1.996GB／generic 2.006GB，兩機的 desktop ISO 照常隨 0.2.0 出貨。`--long=27` 為 zstd 解壓端預設視窗上限，安裝程式不需改。
- **`release-os.sh build/smoke/package` 預設串 release overlay `serial1.yml`**：先前只吃機型 kas 設定，deploy/spdx 被清後開烤即死於 `do_create_recipe_spdx`；現由 `kas_cfg_chain` 統一串上（`DUDUCLAW_OS_KAS_OVERLAY=` 可關）。
- **wic.zst 壓縮改 `zstd -19 --long=27`＋2GiB 資產上限硬檢查**：level 3 壓出 2.38GB 撞 GitHub 422；同一顆 wic 以 -19 為 1.72GB。package 壓完先量、超限拒簽，publish 上傳前再查；manifest 加 `decompress_hint`（`zstd -d --long=27`）。`--long=27` 等於 zstd 解壓端的預設視窗上限，新版 zstd 直接 `zstd -d` 即可，舊版提示視窗不足時才補參數。

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
- **安全信任鏈（layer 層）**：自簽 Secure Boot（每槽雙簽 UKI）、唯讀 root＋dm-verity 區塊
  完整性、TPM2/LUKS PCR 7+11 金鑰密封（fail-open 路徑可用；自動 enroll 為待解
  缺陷，需真機 TPM）。發布映像只用基本 kas 設定，Secure Boot、dm-verity 與 TPM
  都未啟用（0.2.0 Changed 有拆開發布 wic 的查證）。
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
