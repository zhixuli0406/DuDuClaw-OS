# catwalk — 會走路的摺紙貓

把品牌吉祥物做成一隻真的會走、會潛行、會撲擊、會抓紙老鼠的低面數摺紙貓。
獨立模組，不依賴網站其他 JS/CSS，也還沒接進首頁。

驗收頁：[`lab/cat-walk.html`](../../../lab/cat-walk.html)

```
assets/
├─ brand/duduclaw-cat.svg          ← 視覺基準（摺紙、緋紅、無眼睛）
├─ brand/cat-512.png               ← 實驗室左側對照圖
├─ js/catwalk/
│  ├─ cat-model.mjs                ← 幾何、Transform 骨架、姿勢表
│  ├─ catwalk.mjs                  ← 掛載、狀態機、紙老鼠、相機
│  ├─ README.md                    ← 本檔
│  └─ REPORT.md                    ← 截圖迭代紀錄
└─ vendor/ogl.mjs                  ← 內嵌的 OGL 1.0.11（Unlicense）
```

## 幾何

執行期用程式生成，不解析 SVG、不用骨骼蒙皮。每個部件是少量平面的紙盒或菱柱：

- 身體：略扁的紙盒（寬 > 高），臀側加一片對角摺紙。
- 頭：短楔形紙盒（前窄後寬，高 < 寬）加一個小口鼻盒。沒有眼睛。
- 耳：兩片直立三角紙，間距約 0.20。
- 腿：細長紙條，截面 0.045，上段／下段差不多長。腳底由兩骨 IK 鎖在 y ≈ 0。
- 尾：三節矩形斷面，末端上翹。
- 老鼠：三角身體、兩隻小耳、細尾；灰 `#d4d4d8` / `#9f9fa9`。

每一面單一色，顏色由該面在模型空間的法線決定：朝上 `#ff7a7e`，朝下 `#b02e33`，側面走 `#f2565b` / `#e85055` / `#c6353a`。摺痕靠色階差，不用平滑光照。

比例（單位）：貓長約 1.0、站高約 0.5、頭寬約身長 0.28、腿長約站高 0.55、尾長約 0.9。

### Transform 階層

```
root
 └─ hips
     ├─ spine → chest → neck → head → earL, earR
     ├─ chest.shoulderL/R → upper → lower → paw
     ├─ hipL/R → upper → lower → foot
     └─ tailBase → tailMid → tailTip
```

每個關節有旋轉上限，避免膝關節反折、頭轉穿進身體。

## 狀態機

狀態之間用約 180 ms 的臨界阻尼彈簧過渡。尾巴擺動（3 s）與呼吸永遠疊加。

| 狀態 | 觸發 | 動作 |
|---|---|---|
| idle | 距離 ≤ 0.35、無目標走回 homeX、或抓住成功後 | 自然貓坐：臀貼地、前腿撐地、脊柱約 65°、尾繞身側 |
| enter | `enterFrom(x)` | 坐姿在 x 淡入 300 ms（scale 0.6→1、opacity 0→1） |
| follow | 距離 > 0.35 | 先轉身（≤ 240°/s），再對角步態 0.6–1.6 u/s、1.4–2.4 Hz |
| stalk | 距離 0.35–1.2 且目標靜止 ≥ 1.2 s | 臀部下降 40%，扭三下（0.8 s），尾尖抖 |
| pounce | stalk 滿 0.8 s | 0.45 s 拋物線跳向目標 |
| catch | 落地 | 前爪蓋住 1.0 s；目標移動 > 0.2 則逃走回 follow |
| flee | catch 期間目標跑掉 | 老鼠從側邊溜，貓改 follow |

走動範圍夾在地板線兩端（±1.70）。

紙老鼠沿地板線跟游標跑，120 ms 延遲；游標離開畫布就躲到邊緣。`targetMode: 'tap'` 時點一下放置；沒游標則每 6–10 s 自己換位置（`?autoplay=1` 強制）。被抓時縮成 0.7 倍，鬆爪後從側邊重新跑出。

## 模組 API

```js
import { mountCatWalk } from './assets/js/catwalk/catwalk.mjs';

const api = mountCatWalk(container, {
  floorY: 0,
  theme: 'light',          // 或 'dark'；畫布底 #f3f3f3 / #0c0c0e
  targetMode: 'pointer',   // 'tap' | 'external'（首頁用 setTarget 驅動）
  homeX: 0.35,             // 沒有老鼠時走回這裡坐下
  speedScale: 1,
});
```

首頁 hero 那種「疊在既有版面上、舞台很小」的用法另外有六個選項，全部省略時行為與
實驗室逐一相同：

| 選項 | 預設 | 說明 |
|---|---|---|
| `transparent` | `false` | 畫布改成 alpha、清成全透明，並且不建地板板子。疊在別人的底色上要開這個 |
| `showFloor` | `!transparent` | 單獨關掉地板板子。透明舞台預設就是關的 |
| `floorHalf` | `1.40` | 可走地板線的半寬。狀態機的距離門檻（arrive、stalk 近遠界、逃走位移、回家容差）會按 `floorHalf / 1.40` 一起縮放，否則在小舞台上「老鼠在半個畫面外」也算走到了，貓永遠不走路。**步速不縮放**：步幅是腿的性質，跟著縮會讓腳底在地上滑 |
| `stillSeconds` | `1.20` | 老鼠靜止多久才算「停住」，也就是潛行的觸發條件。小舞台上貓幾秒內就走到，1.2 s 的門檻會讓潛行永遠來不及發生 |
| `startPaused` / `startHidden` | `false` | 掛好之後不跑 rAF／貓先縮小到 0.6 且透明度 0。兩個一起用就是「已經掛上但完全不佔畫面」，等 `enterFrom()` 才登場 |
| `camera` | 無 | 明確指定取景。給了就走下面這組算式，沒給就照原本那套啟發式（實驗室是照那套調的） |

```js
camera: {
  frameWidth: 2.25,     // 橫向要看得到的地板單位數
  frameHeight: 0.95,    // 縱向要看得到的單位數（撲擊弧線的高度）
  floorAnchor: 0.045,   // 地板線落在畫布高度的幾成（從底部量）
  azimuthDeg: 0,        // 0 = 正側面。步態是照側視做的，轉太多腿會交錯成一團
  elevationDeg: 12,     // 俯角
  lookX: 0,             // 對準的地板 x
}
```

回傳 `false` 代表不該跑（`prefers-reduced-motion: reduce`、沒有 WebGL、`?nowebgl=1` / `?reducedmotion=1`）。失敗時容器不被改動，呼叫端維持原本內容即可。

回傳物件：

| 成員 | 說明 |
|---|---|
| `ready` | `Promise<boolean>`，第一幀畫完後 resolve |
| `setTheme(name)` | `'light'` / `'dark'` |
| `setTargetMode(mode)` | `'pointer'` / `'tap'` / `'external'` |
| `setTarget(x\|null)` | 設老鼠的 x；`null` 時貓走回 `homeX` 坐下 |
| `enterFrom(x)` | 坐姿出現在 x，300 ms 淡入 |
| `leaveTo(x, cb)` | 走到 x、坐下、300 ms 淡出後呼叫 cb |
| `reset()` | 貓坐回 `homeX` |
| `pause()` | 停 rAF。畫布開著 `preserveDrawingBuffer`，最後一幀會留在畫面上 |
| `resume()` | 重新跑 rAF |
| `destroy()` | 停 rAF、解除 observer、移除 canvas、`WEBGL_lose_context` |
| `onState(cb)` | 每幀回報 `{ state, speed, dist, catX, mouseX }`，回傳取消函式 |
| `canvas` | 那張 `<canvas>` |
| `pxPerUnit` | 目前一個地板單位對應幾個 CSS px（第一次 layout 前是 0）。把畫面座標換算成 `setTarget` 的 x 時會用到 |

行為守則：DPR 上限 2；離開視窗（IntersectionObserver）或分頁隱藏就停 rAF。相機 fov 30、輕微俯視，走路時看得到腳步與尾巴。

查詢參數（實驗室用）：

- `?pose=idle\|enter\|walk\|stalk\|pounce\|catch` 把貓釘在該姿勢
- `?autoplay=1` 讓老鼠自己跑（時間軸會逼出完整 idle→follow→stalk→pounce→catch→idle）
- `?theme=light\|dark` 畫布底色
- `?nowebgl=1` / `?reducedmotion=1` 強制降級

## 併進首頁 hero 的方式（已經接好）

首頁的編排在 [`assets/js/hero-cat.js`](../hero-cat.js)：品牌剪影（`cat3d`）與這隻走路貓
共用同一個吉祥物盒子，游標進 hero 就換人。要點：

1. 走路貓有自己的舞台 `div.hero-cat-stage`（絕對定位、比盒子寬、只佔盒底那一條），
   `mountCatWalk` 掛在那個 div 上。**不要**把畫布掛在盒子上再去改畫布的 left/right：
   OGL 的 `setSize()` 會把 `style.width`／`height` 寫成 px，之後畫布就不再跟著容器縮放。
2. SVG／`cat3d` 仍是無 JS、無 WebGL、減少動態效果時的最終畫面。走路版 `mountCatWalk`
   回傳 `false` 時什麼都不要藏。
3. 疊在既有底色上要 `transparent: true`（地板板子同時關掉，接觸陰影自動變淡）。
   要放實心底的獨立舞台就照舊，淺 `#f3f3f3`、深 `#0c0c0e`。
4. 用 `<script type="module">` 載入，hero 文字先畫（canvas 不是 LCP 候選）。
5. 剪影切走路貓：`api.enterFrom(x)`；切回去：`api.setTarget(null)` 再
   `api.leaveTo(x, () => { /* 顯示剪影 */ })`。游標投影：`targetMode: 'external'`
   加 `api.setTarget(x)`。
6. 兩個模組不要同時跑 rAF：淡出的那一個 `pause()` 之後最後一幀還在（兩個模組都開了
   `preserveDrawingBuffer`），CSS 就在兩張靜止畫面之間做交叉淡入淡出。

```js
import { mountCatWalk } from './assets/js/catwalk/catwalk.mjs';

const api = mountCatWalk(stage, {
  targetMode: 'external', transparent: true,
  startPaused: true, startHidden: true,
  floorHalf: 0.72, stillSeconds: 0.6, speedScale: 0.6,
  camera: { frameWidth: 2.25, frameHeight: 0.95, floorAnchor: 0.045, azimuthDeg: 0, elevationDeg: 12 },
});
```

獨立舞台（實驗室那種）維持原樣即可：

```html
<div class="walk-stage" style="height:420px;position:relative;background:#f3f3f3">
  <!-- 降級時可放一句說明或靜態 PNG；模組成功後呼叫端再藏 -->
</div>
```

## 姿勢的左右鏡射

`applyPose(cat, pose, mirrorY)` 的第三個參數會把姿勢表裡所有 yaw 角乘上 `mirrorY`
（預設 1，凍結姿勢與其他呼叫端逐一不變）。坐姿與抓住的姿勢刻意把頭和尾巴轉一點朝鏡頭，
那些角度寫在貓自己的座標系裡；貓掉頭往另一邊走之後就變成轉開，坐姿會讀成一個方盒子背面。
狀態機每幀傳 `-Math.cos(yaw)`：面向 -X 時是 +1、面向 +X 時是 -1，轉身過程中連續滑過去，
所以不會在中途跳一下。

## 已知限制

- 坐姿（idle）從 3/4 看仍偏方，頭與尾巴容易被身體擋住，是 W6 第三輪就記在 `REPORT.md`
  裡的殘留問題。左右鏡射之後兩個方向讀起來一樣，但沒有把姿勢本身變好看。
- 姿勢是程序生成，不是動作捕捉。對角步態在側視成立，從正前方看腿會交叉得比較假。
- 地板是一條線，貓只沿 X 走，不會繞過相機。
- `?pose=` 會關掉狀態機，尾巴與呼吸仍在動（idle / catch 比較明顯）。
- OGL 是 Unlicense；只內嵌 core + math，沒用 extras。
