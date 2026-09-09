# DuDuClaw OS 官方網站

這是 DuDuClaw OS 的官方網站原始檔：兩頁靜態網站（首頁與下載頁），純 HTML／CSS／vanilla JS，
沒有框架、沒有建置步驟。除了 Google Fonts（Inter、Noto Sans TC、JetBrains Mono）之外不載入任何外部資源。

## 目錄結構

```
website/
├── index.html              首頁
├── download.html           v0.2.0 下載頁（六個資產、驗簽、燒錄）
├── .nojekyll               讓 GitHub Pages 原樣輸出，不跑 Jekyll
├── README.md               這份說明
├── lab/cat3d.html          品牌剪影 3D 貓的驗收頁（左＝SVG、中＝3D、右＝疊圖比對）
├── lab/cat-walk.html       四足走路貓的驗收頁（六個狀態、凍結姿勢、autoplay）
└── assets/
    ├── css/site.css        設計 token 與全站樣式
    ├── js/site.js          主題切換、導覽、分頁、複製、捲動進場、下載篩選
    ├── js/hero-shader.js   首頁 hero 背景的 WebGL2 色塊
    ├── js/freeze-demo.js   影子工作區示意圖的凍結示範
    ├── js/hero-cat.js      吉祥物編排：剪影與走路貓共用同一個盒子，游標進 hero 就換人
    ├── js/cat3d/           品牌剪影 3D 貓模組（見該目錄的 README.md）
    ├── js/catwalk/         四足走路貓模組（見該目錄的 README.md）
    ├── data/cat-panels.json 3D 貓的幾何，由 cat3d/tools/build-panels.py 離線產生
    ├── vendor/ogl.mjs      內嵌的 OGL 1.0.11（Unlicense），生產站不從 CDN 載
    ├── brand/              吉祥物、logo mark、favicon
    └── screens/            OS 實際畫面截圖
```

所有連結都是相對路徑，所以放在網域根目錄或 GitHub Pages 子路徑都能正常運作。

`lab/` 只是開發用的驗收頁，不上線：`scripts/build-site.sh` 組完 `_site/` 後會把它刪掉。

## 截圖的格式與裁切

每張截圖都出三種格式，`<picture>` 由上而下試 AVIF、WebP，最後才是 PNG，
所以舊瀏覽器仍然拿得到圖。桌面版一律 1280×800。

首頁 hero 那張還多一組直式細部裁切（`home-desktop-mobile`、`home-dark-mobile`，
640×670）：600px 以下換上它，讓交辦列、任務卡與 Dock 的字仍然讀得出來，
而不是把整個桌面縮成一團雜訊。深淺主題各一組，換主題時 CSS 直接切。

換截圖時三種格式都要重出，尺寸寫進 `width` / `height` 屬性避免版面跳動。

## 互動模組

六個模組彼此獨立，各自偵測能力、各自降級，關掉任何一個其他照常運作。
關掉 JavaScript 時六個都不存在，頁面內容與下載連結完全不受影響。

| 模組 | 做什麼 | 降級後看到什麼 | 測試開關 |
|---|---|---|---|
| `js/hero-shader.js` | hero 背景兩塊緩慢漂移的色塊，WebGL2 全螢幕 quad，顏色讀 `--hero-circle-a` / `--hero-circle-b` / `--hero-ground` | `.hero-bg` 原本的兩個 CSS 大圓 | `?nogl=1` |
| `js/freeze-demo.js` | 影子輸出框裡 agent 游標的六顆粒子軌跡，滑鼠移入左框就原地凍結 | 原本靜態的 `.shadow-cursor-agent` | `?nodemo=1`、`?nohover=1`（強制觸控版） |
| `js/hero-cat.js` | 吉祥物編排：靜止時是品牌剪影，游標進 hero 換成四足走路貓去追紙老鼠，游標離開 2 秒後走回原位換回剪影 | hero 裡那份 inline SVG | `?nocat=1`（兩個都不掛）、`?nowalk=1`（只留剪影） |
| `js/cat3d/cat3d.mjs` | 品牌剪影的低面數 3D 版，進場展開一次後隨游標微傾 | hero 裡那份 inline SVG | `?nowebgl=1`、`?reducedmotion=1` |
| `js/catwalk/catwalk.mjs` | 四足走路貓：走、潛行、撲擊、抓紙老鼠，六個狀態 | 不掛就維持剪影 | `?nowebgl=1`、`?reducedmotion=1`、`?pose=`、`?autoplay=1` |
| `js/site.js` | 主題、導覽、分頁、複製、捲動進場、下載篩選 | 靜態 HTML 全部可讀可點 | 無 |

共同的防護：`prefers-reduced-motion: reduce` 一律不啟動、DPR 上限 2、
離開視窗或分頁隱藏就停 rAF、觸控裝置鎖 30fps。

吉祥物那兩個模組再多幾條：

- 3D 剪影掛上之後 `.hero-cat` 會多一個 `data-cat3d="on"`，site.js 與 site.css
  靠它停用 SVG 版的展開與傾斜；掛不上就什麼都不動。
- 走路貓登場時 `.hero-cat` 再多一個 `data-catwalk="on"`，CSS 靠它把剪影那張畫布淡出。
- **同一時間只有一個模組在跑 rAF**：淡出的那一個 `pause()` 之後最後一幀還留著，
  交叉淡入淡出是在兩張靜止畫面之間做的。hero 離開視窗或分頁隱藏時兩個都停。
- 桌機（>780px 且 `pointer: fine`）走游標互動，吉祥物盒子維持「點一下重播摺紙展開」。
  觸控或 ≤780px 改成舞台上一顆透明按鈕（`放一隻紙老鼠`，至少 44px），點一下放老鼠、
  20 秒沒互動就換回剪影；這種情況下不會再掛重播按鈕，同一塊畫面不會疊兩個控制項。
- 走路貓的站高大約是剪影高度的三成。四足貓的鼻子到尾巴約是站高的兩倍多，
  吉祥物那一欄只有 480 px 左右，要讓整隻貓不被裁切又留得下走路空間，這是幾何上的上限。

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
- 用鍵盤走一次：Tab 到「跳到主要內容」、桌面分頁用左右方向鍵切換

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
- Hero 與 CTA 兩顆「下載 v0.2.0」按鈕的文字
- 誠實狀態卡：驗證範圍、Secure Boot、GA 進度如果有變就一起改
- 信任鏈區塊：某項保護從「已接好、未啟用」變成「出貨即有」時要搬過去

**4. 全站搜一次舊版本號**

```bash
grep -rn "v0\.2\.0" website/
```

確認沒有漏掉的字串，接著在本機起站點過一次六個下載連結。

## 內容原則

- 繁體中文（zh-TW），技術名詞保留英文
- 零 emoji，圖示一律用 inline monoline SVG（2px stroke、24 網格）
- 緋紅 `#E5484D` 只給貓、logo mark 與每頁最多一個強調詞；UI 的按鈕、連結與 focus ring 一律用 MDS 藍 `#2171cc`
- 產品事實以 OS repo 的 `README.md`、`CHANGELOG.md` 與 GitHub Release 為準
- pre-GA 現況（QEMU 驗證、真機未開機、Secure Boot 需關閉）在兩頁都要看得到，照實寫

## 正式站：Cloud Run 與子網域

正式站掛在 GCP 專案 `louis-460302`（region `asia-east1`）的 Cloud Run 服務 `duduclaw-os-site`，
以 nginx 靜態服務整個 `_site/`（首頁、下載頁、`/docs/` 文件站），網域 **https://os.duduclaw.dudustudio.monster**。

```bash
scripts/deploy-cloudrun.sh              # 建置 _site/ 並以 deployer SA 部署（Cloud Build，約 3–5 分鐘）
SKIP_BUILD=1 scripts/deploy-cloudrun.sh # 沿用現有 _site/
```

- 容器定義在 `deploy/cloudrun/`（`Dockerfile`、`nginx.conf` 含 CSP 與快取標頭、`mime.types` 補 `mjs`／`avif`／`wasm`）。
  `deploy/cloudrun/_site/` 是部署時的暫存副本，已 gitignore。
- `lab/` 驗收頁不會進 `_site/`（`scripts/build-site.sh` 會移除）。
- 文件站的絕對網址由 `SITE_URL` 決定（deploy 腳本預設帶正式網域）；`og:image` 已寫成正式網域的絕對網址。
- **一次性設定（已完成 2026-09-09）**：Cloud Run domain mapping `os.duduclaw.dudustudio.monster → duduclaw-os-site`
  必須用「已驗證網域」的帳號建立（deployer SA 沒有驗證網域，所以這一步是用擁有者帳號做的）；
  Cloud DNS zone `dudustudio` 的 CNAME `os.duduclaw → ghs.googlehosted.com.` 由 SA 建立。
  之後每次部署只需要跑腳本，mapping 與 DNS 不必再動。憑證由 Google 自動簽發，首次約需 15 分鐘到 1 小時。
- GitHub Pages 的 workflow（`.github/workflows/pages.yml`）仍保留作為備援發布路徑；兩者建置同一份 `_site/`。
