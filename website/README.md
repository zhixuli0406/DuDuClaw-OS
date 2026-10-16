# DuDuClaw OS 官方網站

這是 DuDuClaw OS 的官方網站原始檔：兩頁靜態網站（首頁與下載頁），純 HTML／CSS／vanilla JS，
沒有框架、沒有建置步驟。除了 Google Fonts 的 Nunito Sans 之外不載入任何外部資源。

## 目錄結構

```
website/
├── index.html              首頁
├── download.html           v0.4.0 下載頁（六個資產、驗簽、燒錄）
├── favicon.svg             C1 貓 mark（深色瀏覽器介面下 ink 層轉米白）
├── favicon.ico             Codex 的 duduclaw-os app-icon.ico
├── apple-touch-icon.png    180×180，由 duduclaw-os avatar-1024.png 縮出
├── site.webmanifest        manifest，圖示指向 assets/brand/icon-192／512.png
├── robots.txt              允許所有爬蟲（含 AI 爬蟲），列出兩份 sitemap
├── sitemap.xml             首頁、下載頁與 /docs/；文件站另有 Starlight 產生的 docs/sitemap-index.xml
├── llms.txt                給 LLM 讀的站點摘要（llmstxt.org 格式）
├── llms-full.txt           llms.txt 的完整版：版本差異、資產、硬體、安全界線
├── .nojekyll               讓 GitHub Pages 原樣輸出，不跑 Jekyll
├── README.md               這份說明
└── assets/
    ├── css/site.css        C1 設計 token 與全站樣式
    ├── js/site.js          主題切換、導覽、分頁、複製、捲動進場、下載篩選
    ├── brand/              C1 品牌資產（見下方「品牌與視覺」）
    └── screens/            OS 實際畫面截圖（v0.2.0）
```

所有連結都是相對路徑，所以放在網域根目錄或 GitHub Pages 子路徑都能正常運作。
例外是給搜尋引擎與 AI 爬蟲的部分，一律寫正式網域的絕對網址：`og:image`、canonical、hreflang、
JSON-LD，以及 `robots.txt`、`sitemap.xml`、`llms.txt`、`llms-full.txt`。GitHub Pages 備援站因此也會把 canonical 指回正式站。

## SEO 與 GEO

- 兩頁都有 `<meta name="robots" content="index, follow">`、canonical 與 hreflang（`zh-TW` 加 `x-default`，目前只有繁中一種語言）。
- 首頁的 JSON-LD 是 `@graph`：`Organization`（Dudu Technology Ltd.／嘟嘟數位科技有限公司）與 `SoftwareApplication`
  （版本、pre-GA 與 QEMU 驗證範圍、Apache-2.0）。下載頁只放 `BreadcrumbList`。
- `robots.txt` 明列 GPTBot、ClaudeBot、PerplexityBot、Google-Extended 等 AI 爬蟲為允許，並列出 `sitemap.xml` 與文件站的 `docs/sitemap-index.xml`。
- `llms.txt`／`llms-full.txt` 的事實只能取自兩頁現有文案與 `site.js` 的 `RELEASE`，不另外加宣稱。
- `scripts/build-site.sh` 組完 `_site/` 會檢查這四個檔案都在，缺一個就失敗。
- Cloud Run 的 nginx 以 `text/plain; charset=utf-8` 送 `.txt`、`application/xml; charset=utf-8` 送 `.xml`
  （`deploy/cloudrun/mime.types` 與 `nginx.conf` 的 `charset`）；沒有 charset 時瀏覽器可能把中文的 llms.txt 解成亂碼。
- 改完 JSON-LD 跑一次下面這行，每個 `application/ld+json` 區塊都要能解析：

```bash
python3 -c 'import re,json,sys; n=[json.loads(b) for f in sys.argv[1:] for b in re.findall(r"<script type=\"application/ld\+json\">(.*?)</script>", open(f).read(), re.S)]; print(len(n), "JSON-LD blocks ok")' website/index.html website/download.html
```

## 品牌與視覺（C1，2026-10-16）

依公司的 Dudu C1 網頁設計規範（`Dudu_Brand_C1_Web/WEB-DESIGN-SPEC.md`）：米白底 `#F5F4F0`、
海軍藍文字 `#102B48`、琥珀 `#CC8B2D` 只用在色條、圖示與 focus ring，琥珀色的文字與連結用
`#8A5A10`（深色主題 `#E0A54F`）。深色主題底色 `#0B1E33`、卡片 `#102B48`。程式碼區塊兩種主題都是海軍藍底。
字體是 Avenir Next（Apple 裝置內建）＋ Google Fonts 的 Nunito Sans，中文走系統字（PingFang TC、Noto Sans TC、微軟正黑體）。
反覆出現的細節是左側 4px 的琥珀色條：hero 文字區、下載頁標題、狀態卡與核心能力卡。

`assets/brand/` 的檔案全部來自 Codex 的 C1 輸出，不要手改幾何：

| 檔案 | 來源 | 用途 |
|---|---|---|
| `duduclaw-os-mark.svg` | `svg/duduclaw-os-mark.svg`（與 DuDuClaw mark 相同） | 原檔備查；頁面用的是 inline `<symbol id="mark-os">` |
| `duduclaw-os-mark-reverse.svg` | 同上，ink 層改米白 | 深色底用 |
| `company-mark-mono.svg` | `svg/company-mark-mono.svg` | 原檔備查；頁尾用 inline `<symbol id="mark-company">` |
| `og.png` | `png/final-duduclaw-os-social.png` | 1200×630 社群卡：先縮成 1260×630，再拿掉文字區與貓之間 60px 的空白欄，左右邊距維持一致 |
| `icon-192.png`、`icon-512.png` | `png/duduclaw-os/avatar-1024.png` | manifest 圖示 |

頁面上的 logo 是 inline SVG：`<svg class="brand-mark"><use href="#mark-os"></use></svg>`，
ink 層填 `var(--logo-ink)`（淺色海軍藍、深色米白），琥珀層固定不變。「OS」以文字寫在 wordmark 裡，貓不重畫。

舊的緋紅摺紙貓、3D 貓、走路貓、`lab/` 驗收頁、hero WebGL 色塊、影子工作區的粒子示範與捲動進度條都已移除
（C1 規範：不留吉祥物動畫、不用漸層與光暈、動態只用 150–200ms 的透明度與位移）。要找回舊實作請看 git 歷史。

## 截圖的格式與裁切

每張截圖都出三種格式，`<picture>` 由上而下試 AVIF、WebP，最後才是 PNG，
所以舊瀏覽器仍然拿得到圖。桌面版一律 1280×800。

截圖資產另保留一組直式細部裁切（640×670）：`home-desktop-mobile`、`home-dark-mobile` 用於首頁圖集的淺／深色首頁分頁，
600px 以下顯示交辦列與 Dock 的細部裁切，桌機呈現完整 1280×800 桌面，其餘分頁保持完整畫面。
`launcher-mobile` 是首頁 hero 右側的產品畫面，取 `launcher.png` 的 `(400, 130)–(1040, 800)`，讓交辦面板置中，各種寬度都用這張。

換截圖時三種格式都要重出，尺寸寫進 `width` / `height` 屬性避免版面跳動。

目前這組截圖是 2026-10-07 用 v0.2.0 發布映像在 QEMU（TCG、q35、預設 bochs 顯示卡，
解析度就是 1280×800）上重拍的：`installer-language` 來自 QEMU 版桌面安裝器 ISO，其餘來自
QEMU 版整碟映像的首次開機（示範帳號「Demo」、不設定任何 AI 授權、套用 Express 板模；深色那張
是在精靈的外觀步驟選暗色後重開一次拍的）。畫面用 QMP `screendump` 取得，滑鼠與鍵盤用 QMP
`input-send-event`／`send-key` 送；重拍前先用 Release 上的 `.sha256` 與 `.minisig` 核對映像。
v0.3.0（2026-10-14 發布）與 v0.4.0（2026-10-16 發布）都還沒重拍，首頁、圖集上方標籤與 alt 文字照實標成 v0.2.0 的畫面。

**待辦：重拍。** 這 24 個檔案（加上 hero 用的 3 個 `launcher-mobile`）是 v0.2.0 的畫面，桌面上還是舊的緋紅貓與舊 logo。
OS 殼層換成 C1 之後要用新的發布映像照上面的 QMP 程序重拍，三種格式與手機裁切一起重出，再把頁面上的 v0.2.0 標示改掉。
手機版裁切固定取 1280×800 原圖的 `(320, 130)–(960, 800)`。WebP 用 `cwebp -q 82 -m 6`，
AVIF 用 `avifenc -q 60 -s 4`。

## 互動

只有 `assets/js/site.js` 一支腳本：主題切換、手機導覽、桌面圖集分頁、複製按鈕、捲動進場、
下載頁篩選，以及捲動後在導覽列下緣加一條細線。關掉 JavaScript 時頁面內容與下載連結完全不受影響。
動態只有進場的 200ms 淡入位移與連結卡圖示的 150ms 位移，`prefers-reduced-motion: reduce` 時全部關閉。

## 本機預覽

```bash
cd website
python3 -m http.server 8000
```

然後開 <http://localhost:8000/>。改完檔案重新整理即可，不需要重啟伺服器。

檢查清單：

- 淺色與深色主題各走一次（右上角切換鈕，選擇會存在 `localStorage`）
- 桌機 1440px 與手機 390px 兩種寬度
- 關掉 JavaScript 再看一次下載頁，六個資產應該全部看得到（篩選器會整組隱藏）
- 用鍵盤走一次：Tab 到「跳到主要內容」、桌面分頁用左右方向鍵切換、FAQ 用 Enter／Space 展開
- 關掉 JavaScript 看首頁，六張桌面圖集、FAQ 與試用 CTA 仍可使用

## 發佈到 GitHub Pages

在 DuDuClaw-OS repo 的 **Settings → Pages**：

1. Source 選 **Deploy from a branch**
2. Branch 選 `main`，資料夾選 `/website`
3. 按 Save，等幾分鐘後網站會出現在 `https://<帳號>.github.io/DuDuClaw-OS/`

`.nojekyll` 已經放好，Jekyll 不會處理這些檔案。網站用的是相對路徑，
所以掛在 `/DuDuClaw-OS/` 這種子路徑底下也不會壞。

之後如果要換成自訂網域，在同一頁填 Custom domain，並在 `website/` 下加一個 `CNAME` 檔。

## 出新版要改哪裡

版本資訊刻意同時存在 HTML（靜態文字，關掉 JS 也看得到）與 `site.js` 的 `RELEASE` 常數（篩選器用）。
出新版時兩邊都要改，順序建議如下：

**1. `assets/js/site.js` 最上方的 `RELEASE` 物件**

`version`、`date`、`platform`、`kernel`、`previous`、`downloadBase`、`assets[]`
（六筆的 `file`、`bytes`、`size`、`edition`、`form`、`machine`）。
`minisignKey` 只有在換簽章金鑰時才需要動。

**2. `download.html`**

- `<title>` 與 `og:title` / `twitter:title` 的版本號
- `.release-band` 那一列（版本、日期、平台版、kernel）
- `<h1>` 與 `.badge-row` 的徽章
- `#assets` 區塊的六張 `.asset` 卡：檔名、大小、三個下載連結
  （本體、`.sha256`、`.minisig`）都要換成新版本的網址
- `#flash` 區塊指令範例裡的檔名
- `#rollback` 區塊的「要回舊版」連到上一版的 Release

**3. `index.html`**

- `.release-band` 那一列（版本、日期、平台版、kernel）
- Hero 與 CTA 兩顆「下載 v<版本>」按鈕的文字
- 誠實狀態卡：驗證範圍、Secure Boot、GA 進度如果有變就一起改
- 信任鏈區塊：某項保護從「已接好、未啟用」變成「出貨即有」時要搬過去

**4. SEO 檔案**

- `index.html` 的 JSON-LD：`softwareVersion` 與 `description` 裡的版本、驗證範圍
- `download.html` 的 JSON-LD `BreadcrumbList` 第二項名稱（「下載 v<版本>」）
- `llms.txt`、`llms-full.txt`：版本、發布日、內嵌平台版、驗證範圍、六個資產檔名
- `sitemap.xml` 首頁與下載頁的 `<lastmod>`

**5. 全站搜一次舊版本號**

```bash
grep -rn "v0\.2\.0" website/   # 換成上一版的版本號
```

確認沒有漏掉的字串（刻意保留的舊版字樣：截圖說明與 alt、回舊版卡片、公鑰「舊版也是這一把」），接著在本機起站點過一次六個下載連結。

**6. 下載頁的 QR code**

`download.html` 的 QR code 編的是預設推薦資產（桌面版安裝器 ISO、真機目標）的直連網址，換版一定要重產。
格式：version 11、錯誤修正 H、segno 自動選 mask，`qr-dots` 只畫一般模組（跳過三個定位圖案、六個對齊圖案與
中間 `[28,40]×[28,40]` 的 logo 區，座標含 4 格 quiet zone），每個點寫成 `M<x> <y>h0`／`m<dx> <dy>h0`。
用 segno 1.6.6 照這個規則重產 v0.2.0 的網址，結果與原本的 path 逐位元組相同，v0.3.0 就是照同一規則產的。v0.4.0 換版時先用同一支腳本重產 v0.3.0 的網址，確認與頁面上的 path 逐位元組相同（9979 個字元），再產 v0.4.0。

中間的 logo 區放 C1 貓 mark（白色圓角方塊上的 `#mark-os`，ink 固定海軍藍），QR 本體固定白底海軍藍點，不跟主題反轉。
`.qr-frame` 維持 200px 寬、10px 內距：2026-10-16 實測 8px 內距在 1x 螢幕上 jsQR 解不出來，10px 在 1x 與 2x、淺色與深色都解得出 v0.3.0 的 ISO 網址。換成 v0.4.0 後（2026-10-16）以 headless Chrome 截整頁、jsQR 1.4.0 解碼，1x／2x、淺色／深色四張都解出 v0.4.0 的 ISO 網址。
改 QR 的尺寸或內距後，用 headless Chrome 截 `.qr-frame`，再用 jsQR 解一次確認。

## 首頁資訊路徑（2026-10-11）

首頁依讀者試用路徑呈現：用途與下載／預覽 → pre-GA 狀態 → 內附 AI 工具 → 真實桌面圖集 →
交辦、追蹤與接手 → 六項核心能力 → 版本 → 硬體 → 入門 → 資料與安全界線 → FAQ → 文件與試用。
下載頁先解釋版本與安裝形式，再列資產、驗簽與寫入步驟。

- 視覺在 2026-10-16 換成 C1（見「品牌與視覺」）；資訊路徑與文案沿用，參考網站只用於資訊結構。
- 移除「第一」與一般 Linux 的概括比較，將重複技術說明合併為核心能力；深入細節導向文件。
- 工具名稱列依 `docs/guides/ai-runtimes.md` 與 `duduclaw-ai-runtimes.bb` 的打包內容（v0.2.0、v0.3.0 與 v0.4.0 是同一份 2026-09-05 的包），
  展示 Claude Code、Codex、Grok Build 與 Qwen Code；使用純文字、不稱合作夥伴或供應商背書，
  並提醒需自行授權，以及映像版本與現今服務狀態可能不同。
- 六張圖集仍是 v0.2.0 在 QEMU 的實拍；交辦／接手圖示明確標為示意，沒有宣稱模型已完成任務。
- FAQ 使用原生 `details`，鍵盤與關閉 JS 都能展開；關閉 JS 時六個桌面分頁全部顯示，
  手機導覽改為可水平捲動的連結列。
- 資料界線區分本機 OS 資料與雲端模型傳送，不承諾所有資料都不出機。
- OS 採 Apache-2.0；DuDuClaw 企業導入、培訓與支援導向總經銷未來企業股份有限公司，
  不將企業平台服務解讀為 OS GA、硬體相容認證或支援承諾。
- 版本、資產 URL、minisign 公鑰與 `site.js` 的 `RELEASE` 均沿用現有發布資料。

## 內容原則

- 繁體中文（zh-TW），技術名詞保留英文
- 零 emoji，圖示一律用 inline monoline SVG（1.75px stroke、24 網格）
- 主要按鈕海軍藍底米白字（深色主題反過來），次要按鈕 1px 外框；琥珀 `#CC8B2D` 不拿來當內文顏色
- 不寫「enterprise-grade」「production-ready」「最好」「第一」這類沒有根據的說法
- 產品事實以 OS repo 的 `README.md`、`CHANGELOG.md` 與 GitHub Release 為準
- pre-GA 現況（QEMU 驗證、真機未開機、Secure Boot 需關閉）在兩頁都要看得到，照實寫

## 正式站：Cloud Run 與子網域

正式站掛在 GCP 專案 `louis-460302`（region `asia-east1`）的 Cloud Run 服務 `duduclaw-os-site`，
以 nginx 靜態服務整個 `_site/`（首頁、下載頁、`/docs/` 文件站），網域 **https://os.duduclaw.dudustudio.monster**。

```bash
scripts/deploy-cloudrun.sh              # 建置 _site/ 並以 deployer SA 部署（Cloud Build，約 3–5 分鐘）
SKIP_BUILD=1 scripts/deploy-cloudrun.sh # 沿用現有 _site/
```

- 容器定義在 `deploy/cloudrun/`（`Dockerfile`、`nginx.conf` 含 CSP、快取標頭與 `charset utf-8`、`mime.types` 補 `mjs`／`avif`／`wasm`，`.xml` 送 `application/xml`）。
  `deploy/cloudrun/_site/` 是部署時的暫存副本，已 gitignore。
- 文件站的絕對網址由 `SITE_URL` 決定（deploy 腳本預設帶正式網域）；`og:image` 已寫成正式網域的絕對網址。
- **一次性設定（已完成 2026-09-09）**：Cloud Run domain mapping `os.duduclaw.dudustudio.monster → duduclaw-os-site`
  必須用「已驗證網域」的帳號建立（deployer SA 沒有驗證網域，所以這一步是用擁有者帳號做的）；
  Cloud DNS zone `dudustudio` 的 CNAME `os.duduclaw → ghs.googlehosted.com.` 由 SA 建立。
  之後每次部署只需要跑腳本，mapping 與 DNS 不必再動。憑證由 Google 自動簽發，首次約需 15 分鐘到 1 小時。
- GitHub Pages 的 workflow（`.github/workflows/pages.yml`）仍保留作為備援發布路徑；兩者建置同一份 `_site/`。
