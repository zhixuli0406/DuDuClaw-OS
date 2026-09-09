# catwalk 截圖迭代紀錄

對照基準：`assets/brand/duduclaw-cat.svg` 與 `assets/brand/cat-512.png`。
舞台：`lab/cat-walk.html`，headless Chrome + SwiftShader。
`--screenshot` 在 macOS 上不會自己退出，必須包 `timeout`；沒加 `--virtual-time-budget=4000` 的第一次 25 秒 timeout 沒寫出檔案。

## 第 1 輪

截圖：`/tmp/grok-cat-1.png`（當下是降級畫面，不是貓）

發現：

- 紙老鼠色盤缺 `shade` / `body`，`colorFromNormal` 回傳 `undefined`，`pushTri` 炸掉。模組掛載失敗，舞台只剩「需要 WebGL」那行字。HUD 停在 `state …`。
- 修好色盤之後再截：貓是一條細長菱柱，頭尖、脖子長、尾巴穿地板。看起來像恐龍或紙飛機，不像吉祥物。
- 原因：身體用菱形管沿 X 拉太長；尾巴沿 -X，正的 `rotation.z` 其實是往下折（右手定則）；坐姿脊柱幾乎水平，後腿沒摺起來。

## 第 2 輪

改：身體改紙盒；尾巴改負的 `rotation.z` 才上翹；頭加大、幾乎沒脖子、口鼻縮成小盒子；相機拉近、略 3/4。

發現：

- 顏色對了（緋紅、亮面上、暗面下），尖耳出來了，尾巴不再穿地。
- 坐姿仍是香蕉形：頭和尾巴兩頭翹、肚子貼地，比較像撲擊預備，不像貓坐。
- 地板左邊被裁掉，相機 X 偏移太大。
- 老鼠從灰點變成看得出的三角紙。

## 第 3 輪

改：坐姿脊柱 +42°、臀部降到 0.112；關節距離縮短；相機拉回、提高 headroom。

發現：

- 走路（`?pose=walk`）第一次看得出是同一隻摺紙貓：紙盒身體、尖耳、粗尾、細腿、沒有眼睛、側腹那片摺紙。
- 潛行後腿穿地板（hips 降 40% 但腿沒摺夠，有效腿長 0.21 > hipsY 0.16）。
- 走路尾巴出畫面上緣。撲擊整隻被裁頭。
- 頭還是正立方體，比 SVG 的短圓梯形硬。

## 第 4 輪

改：頭改短菱柱；走路尾巴捲度降低；潛行腿摺到 upper ~50° / lower ~-95°；撲擊凍結高度 0.16。

走路看得出是摺紙貓。潛行後腿仍可能穿地（姿勢表沒鎖腳底）。idle 仍是香蕉形，不是品牌那隻坐直舉爪。

## 第 5 輪

目標：idle 對齊品牌招牌坐姿、IK 鎖腳、楔形頭、3/4 鏡頭、catch / pounce 姿勢、深淺主題、autoplay 一整輪。

改：

- idle：hips.z ≈ 78°（脊柱相對地面約 80°）、臀部貼地、FL 用 IK 伸向肩上方、FR 摺在胸前、尾巴沿地再上翹。
- `plantFeet`：兩骨 IK，腳底目標 y = 0.017。走路用步態位移；潛行只降臀、膝多摺；idle 三隻腳落地、一隻舉起。
- 頭：`taperBoxGeo` 前窄後寬，寬 0.26、高 0.20，小口鼻盒，兩耳直立三角、z = ±0.10。
- 身體扁盒（寬 > 高），腿截面 0.045，尾三節矩形。
- 相機在貓前方偏左 `(-1.15, 0.78, ~1.6)`，看 `(0.02, 0.30, 0)`，fov 30。貓 yaw = π，頭在畫面左前。
- catch：兩前爪 IK 到老鼠，老鼠 scale 0.7，身體前傾。
- pounce：空中前後伸展，不落地 IK。
- `?theme=light|dark`；`?autoplay=1` 用時間軸逼出 idle→follow→stalk→pounce→catch→idle。

截圖結論：

- **walk / stalk**：3/4 正面清楚，腳在地板上，沒穿模。stalk 壓低但腳底貼地。這兩張最像同一隻貓。
- **pounce**：在空中拉直，前伸後蹬，老鼠在落點前方，沒被裁切。
- **catch**：前爪壓在灰老鼠上（看得到一角），腳在地上。
- **idle**：已經是直立坐姿 + 一爪舉起 + 一爪下垂，和品牌圖同一種站坐，不是香蕉形。舉起的那爪在 3/4 鏡頭裡仍偏短、有一點被頭擋住；尾巴在鏡頭側但不如 SVG 那塊矩形顯眼。
- **光影**：深淺兩張 idle 都能讀出亮面朝上、暗面朝下。淺色底摺痕更清楚。

autoplay 20 s：`/tmp/grok-cat-r2-states.txt`。原始 log 在 stalk 之前有 idle/follow 來回（老鼠 120 ms 延遲 vs 立刻 `enter('follow')`）。子序列 `idle > follow > stalk > pounce > catch > idle` 有出現。之後已改成 chase 時直接把 `mouseX` 彈到目標。

## 最後參數

| 項 | 值 |
|---|---|
| 身長 | 0.56 |
| 頭寬 / 頭高 | 0.26 / 0.20（楔形，前 0.20 寬） |
| 腿 | upper 0.132 + lower 0.128 + paw 0.034，截面 0.045 |
| 尾 | 0.62，三節，斷面約 0.055 × 0.085 |
| 站高 / 坐臀高 | 0.30 / 0.155 |
| idle 脊柱 | hips.z 78° + spine 8° + chest 6° |
| 色 | `#ff7a7e` / `#f2565b` / `#e85055` / `#c6353a` / `#b02e33` |
| 相機 | fov 30，3/4 正面偏左 |
| 地板 | ±1.40 |
| IK 腳底 | y = 0.017（±0.01） |

## 還不像的地方（誠實）

1. **idle 舉爪仍不夠長。** 品牌那隻前爪舉過頭頂很多；IK 目標在肩上 0.42，腿總長只有 0.29，3/4 透視又吃掉一截。看起來是「坐直、旁邊伸出一截」，不是「整條手臂舉過耳朵」。
2. **idle 從 3/4 看仍偏紙雕疊盒。** 垂直量感對了，但 SVG 的圓頭、斜摺一整片，3D 還是方的。
3. **尾巴在 idle 不夠「貼地往後」。** 有往鏡頭側甩，可是被身體擋住，不如品牌左下那塊粗矩形。
4. **catch 的老鼠要靠側移才看得到一角**，正下方會被肚子蓋住。

## 第 5 輪截圖

| 姿勢 | 路徑 |
|---|---|
| idle（深） | `/tmp/grok-cat-r2-idle.png` |
| idle（淺） | `/tmp/grok-cat-r2-idle-light.png` |
| walk | `/tmp/grok-cat-r2-walk.png` |
| stalk | `/tmp/grok-cat-r2-stalk.png` |
| pounce | `/tmp/grok-cat-r2-pounce.png` |
| catch | `/tmp/grok-cat-r2-catch.png` |
| 並排（左品牌、右 idle） | `/tmp/grok-cat-r2-compare.png` |
| 狀態序列 | `/tmp/grok-cat-r2-states.txt` |

## 第 6 輪（第三輪需求）

放棄把 idle 硬擺成品牌「舉爪」：四足骨架硬舉會變成一疊紙盒。idle 改回自然貓坐。

改：

- idle：hips.z 22° + spine 36° + chest 8° ≈ 66°；前腿 IK 撐地、後腿摺著貼地、尾繞身側上翹；頭略朝鏡頭。四腳都 `plantFeet({ sit: true })`，不再舉爪。
- `enterFrom(x)` / `leaveTo(x, cb)`：300 ms scale 0.6↔1、opacity 0↔1。shader `uOpacity`，`transparent: true`，每 mesh `onBeforeRender` 分開貓／鼠／地板。
- `setTarget(null)` 走回 `homeX`（預設 0.35）坐下；`setTarget(x)` 設老鼠。`targetMode: 'external'` 不聽 pointer。
- yaw 用彈簧（ω = 9）；轉身時速度 ×0.4、步頻 ×0.5，腳繼續踏、不滑。
- `?pose=enter`：坐姿、scale 0.78、opacity 0.55、在 homeX。

截圖：

- idle：3/4 看得出是坐著的紙貓，前腿撐地，不是紙盒圖騰。
- enter：同一坐姿，比較小、半透明、偏右（homeX）。
- walk / stalk / catch：維持第 5 輪的摺紙貓，腳在地板上。
- autoplay 20 s 乾淨一輪：`idle > follow > stalk > pounce > catch > idle`（`/tmp/grok-cat-r3-states.txt`）。

還不像：idle 尾巴仍常被身體擋住；坐姿從 3/4 看頭偏方。沒再走舉爪那條路。

| 姿勢 | 路徑 |
|---|---|
| idle | `/tmp/grok-cat-r3-idle.png` |
| enter | `/tmp/grok-cat-r3-enter.png` |
| walk | `/tmp/grok-cat-r3-walk.png` |
| stalk | `/tmp/grok-cat-r3-stalk.png` |
| pounce | `/tmp/grok-cat-r3-pounce.png` |
| catch | `/tmp/grok-cat-r3-catch.png` |
| 狀態序列 | `/tmp/grok-cat-r3-states.txt` |
