# cat3d — 低面數 3D 摺紙貓

把品牌吉祥物 `assets/brand/duduclaw-cat.svg` 做成真的 WebGL 幾何：八片可折疊面板，
進場播一次「展開」，之後隨游標微傾。獨立模組，不依賴網站其他 JS/CSS。

驗收頁：[`lab/cat3d.html`](../../../lab/cat3d.html)（左＝原始 SVG、中＝3D、右＝疊圖比對）。

```
assets/
├─ brand/duduclaw-cat.svg          ← 唯一來源（設計改這裡）
├─ js/cat3d/
│  ├─ cat3d.mjs                    ← 執行期模組（11 KB，僅依賴 vendor/ogl.mjs）
│  ├─ tools/build-panels.py        ← 離線幾何產生器（Python 標準庫，零依賴）
│  └─ README.md                    ← 本檔
├─ data/cat-panels.json            ← 產生出來的幾何（50 KB / gzip 6.6 KB）
└─ vendor/ogl.mjs                  ← 內嵌的 OGL 1.0.11（Unlicense）
```

## 幾何怎麼來的

執行期不解析 SVG、不做三角化——那些全在離線腳本裡做完。

1. **解析**：讀 clipPath `#cut`（貓的輪廓，三條 subpath 的三次貝茲）與 `<g clip-path>` 裡的
   七個 `<polygon>`，以及三個 `linearGradient`。
2. **攤平＋簡化**：貝茲用「弦距誤差」自適應細分（`FLATTEN_TOL = 0.08` SVG 單位），
   再用 Douglas-Peucker 簡化（`SIMPLIFY_TOL = 0.4`）。輪廓 400 點 → 131 點。
3. **掃描線梯形分解**：對輪廓（以及「輪廓 ∩ 面板」）用 SVG 同一套 nonzero winding 規則做
   掃描線切割，垂直相鄰且左右邊界同一條邊的梯形會合併，最後每個梯形拆兩個三角形。
4. **輸出**：頂點座標平移到「輪廓 bounding box 中心為原點、y 軸向上」，另外存下平面色、
   原始漸層（兩點兩色）、休息時的 z 偏移、鉸鏈邊與折角。

### 兩個設計決定，以及為什麼

**為什麼用掃描線而不是 ear clipping。** 輪廓裡有兩道近乎零寬度的「割縫」——爪子那條白色曲線
其實是填色畫出來的細長條，`... 80.37 123.53 L 80.32 123.63 ...` 只有 0.11 單位寬。
ear clipping 碰到割縫會退化；而且任何大於割縫寬度的簡化容差都會讓割縫兩側交叉，
產生自交多邊形。掃描線直接評估 winding 規則（跟 SVG 算繪器同一套），割縫與自交都由構造本身
處理掉，簡化容差就可以純粹依三角形數量來選。

**為什麼真的做裁剪，而不是靠深度遮住溢出。** 底板是覆蓋整個輪廓的不透明面，
放前面會把七片面板整個蓋掉，放後面則面板會溢出貓的輪廓外——深度順序沒有第三種可能。
只有真正的裁剪能同時得到「面板看得見」和「輪廓乾淨」，而且裁剪在離線做，執行期零成本。

### 重新產生

改了 SVG 之後跑：

```bash
python3 assets/js/cat3d/tools/build-panels.py            # 從 repo 的 website/ 目錄跑
python3 assets/js/cat3d/tools/build-panels.py --debug-svg /tmp/flat.svg   # 另外輸出平面版好肉眼比對
```

輸出（2026-09-09 實測）：

```
silhouette pts : 400 flattened -> 131 simplified (tol 0.4)
panels         : 8       triangles : 1086      out : 51329 bytes
  0 base  458   1 arm 86   2 arm-highlight 51   3 head 80
  4 ear-highlight 12   5 paw 122   6 body-fold 217   7 tail 60
```

折角、鉸鏈邊與出場順序寫在腳本開頭的 `PANEL_SPEC` 表：預設鉸鏈取該面板**原始多邊形的最長邊**，
只有兩處覆寫（body-fold 走它自己的對角摺線、tail 走貼著身體那條邊），因為那兩片的最長邊
不是畫面上讀得出來的摺線。

### `cat-panels.json` 欄位

| 欄位 | 意義 |
|---|---|
| `meta.size` / `meta.centre_svg` | 輪廓 bbox 的尺寸，以及它在原 viewBox 裡的中心（對位用） |
| `panels[].vertices` | 平坦陣列，每 6 個數字一個三角形，**一律逆時針**（見下） |
| `panels[].color` | 面板重心處的漸層取樣值（單色 fallback） |
| `panels[].gradient` | `{p0, p1, c0, c1}`，shader 用它重現 SVG 的漸層 |
| `panels[].z` | 休息時的堆疊高度（`order × 0.6`），讓面板讀起來像疊起來的紙 |
| `panels[].hinge` | `{a, b}` 鉸鏈線段 |
| `panels[].fold` | `{angle, sign, delay}`：折角 40–70°、旋轉方向、出場延遲（0–1） |

三角形一律逆時針是硬性的：順時針的話在 shader 裡 `gl_FrontFacing` 會是 false、
法線被翻到背面、整片面板的主光就等於關掉（實測整體亮度掉到 74%）。產生器在
**座標轉換之後**才判定繞向（`T()` 會翻 y，翻 y 會改變手性）。

## 執行期模組

```js
import { mountCat3D } from './assets/js/cat3d/cat3d.mjs';

const api = mountCat3D(container, {
  scale: 1,          // 1 = 貓的 bbox 填滿容器（留 6% 邊）
  tiltDegrees: 4,    // 游標微傾上限
  autoplay: true,    // 進入視窗時自動播一次展開；false 則自己叫 api.play()
  // src: '...'      // 換一份幾何檔（預設相對於模組位置）
});
```

回傳 `false` 代表**不該跑**，且容器完全沒被動過——呼叫端維持原本的 SVG 就好。三種情況：
WebGL 不可用（含 `failIfMajorPerformanceCaveat` 擋掉的軟體算繪）、
`prefers-reduced-motion: reduce`、或測試用的 `?nowebgl=1` / `?reducedmotion=1` query。

回傳物件：

| 成員 | 說明 |
|---|---|
| `ready` | `Promise<boolean>`；幾何載入並掛上畫布後 resolve。載入失敗會自己 `destroy()` 並 resolve `false` |
| `play()` | 重播一次展開（不循環） |
| `pause()` | 停 rAF。畫布開著 `preserveDrawingBuffer`，最後一幀留在畫面上，交叉淡出時不會中途變空白 |
| `resume()` | 先同步畫一幀再重新跑 rAF，所以淡入的第一格就有畫面 |
| `destroy()` | 停 rAF、解除所有 observer/listener、移除 canvas、`WEBGL_lose_context` |
| `canvas` | 那張 `<canvas>` |
| `pxPerUnit` | 目前每個 SVG 單位對應幾個 CSS px；把原 SVG 對齊疊在畫布下方時會用到 |

行為：

- **展開**：820ms、ease-out、七片依 `delay` 錯開，**只播一次**。面板平時是攤平的，
  只有 `play()` 真的開始那一刻才被擺到折疊姿勢——所以被 rAF 餓死的分頁（背景分頁、
  被遮住的視窗）顯示的是完成品，不是卡住的半成品，而分頁一被看見展開仍會完整播一次。
- **微傾**：只在 `(hover: hover) and (pointer: fine)` 啟用，上限 `tiltDegrees`，
  臨界阻尼（`x'' = -2ωx' - ω²(x-target)`，ω = 9）所以不會過衝。
- **省電**：DPR 上限 2；`(pointer: coarse)` 時鎖 30fps；
  離開視窗（IntersectionObserver）或分頁隱藏（Page Visibility）就停 rAF；
  **傾斜停下後 rAF 完全停止**（實測：靜置 900ms 期間 drawArrays 增加 0 次）。
- **光**：一盞固定在視圖空間的方向光加環境光，`0.74 + 0.34 × max(dot(N,L),0)`。
  休息時所有法線都是 (0,0,1)，係數 0.978——所以靜止畫面幾乎等於 SVG
  （實測平均色差 1.74/255，輪廓 IoU 98.76%）；折的時候法線轉開，面板才會明暗分明。

## 併進 hero 的做法

首頁實際的掛載與交接寫在 [`assets/js/hero-cat.js`](../hero-cat.js)：這個模組畫品牌剪影，
`catwalk` 畫四足走路貓，游標進 hero 就換人。下面是這個模組單獨用的最小寫法。

SVG 是預設狀態，canvas 只是**疊上去**，而且只有在 `mountCat3D` 真的成功之後才把 SVG 藏起來
——順序反過來（先藏 SVG 再掛 3D）會讓無 JS／無 WebGL／reduced-motion 的訪客看到一個空洞。

```html
<div class="hero-cat">
  <!-- 這份 inline SVG 是 no-JS / reduced-motion / 無 WebGL 時的最終畫面 -->
  <svg viewBox="0 0 135 262" aria-label="DuDuClaw" >…</svg>
</div>
```

```css
.hero-cat { position: relative; }         /* 模組自己也會補，但寫出來比較清楚 */
.hero-cat > svg { display: block; width: 100%; height: auto; }
```

```js
import { mountCat3D } from './assets/js/cat3d/cat3d.mjs';

const box = document.querySelector('.hero-cat');
const svg = box.querySelector('svg');
const api = mountCat3D(box, { tiltDegrees: 4 });

if (api) {
  api.ready.then((ok) => {
    if (!ok) return;                      // 幾何載不到 → 什麼都不做，SVG 留著
    svg.style.visibility = 'hidden';      // 只有這時候才藏；保留佈局高度
  });
}
```

不要用 `<script src>` 直接載——這是 ES module，用 `<script type="module">`；
也別在阻塞的位置初始化（研究 D.3 第 6 點：hero 文字要先畫，canvas 不是 LCP 候選元素）。

## 已知限制

- **貓的 bbox ≠ SVG viewBox**：幾何以輪廓 bbox（109.08 × 241.65）為中心，
  SVG viewBox 是 135 × 262。要把兩者疊在一起對位，用 `api.pxPerUnit` 加上
  `meta.centre_svg` 與 viewBox 中心的差值換算（`lab/cat3d.html` 裡有現成寫法）。
- **±4° 在靜態截圖上幾乎看不出來**。相機 fov 24°、距離約 600 單位，接近正投影，
  這是為了讓靜止畫面精準等於 SVG。想要更立體的傾斜就調大 `tiltDegrees`；
  調小 fov 距離（更強透視）會讓不同 z 的面板放大率不一致，輪廓就對不上 SVG 了。
- **面板 z 間距 0.6 單位**造成最上層（tail）比底板大約 0.7%。目前量到的輪廓 IoU 98.76%
  已經含這一項；再加大 `Z_STEP` 會開始看得出來。
- **摺紙姿勢是猜的**，不是真的摺紙展開圖：每片繞自己的鉸鏈轉，彼此沒有共用摺痕約束
  （georgiee/origami 的 rigid-panel 作法，不是 crease-pattern 物理）。
- **背景分頁不播展開**（見上），所以自動化截圖必須讓分頁真的可見，否則抓到的是完成品。
- **`?nowebgl=1` / `?reducedmotion=1` 是測試用後門**，正式頁面不需要，但也無害
  （只會讓效果關掉，不會開啟任何東西）。
- OGL 是 **Unlicense（公眾領域）**，不是 MIT；`assets/vendor/ogl.mjs` 開頭有完整授權條文
  與重現指令。只內嵌了 core + math，`extras/`（Orbit、GLTFLoader、Post、Text…）沒有帶。
