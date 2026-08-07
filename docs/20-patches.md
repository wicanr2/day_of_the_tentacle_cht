# 修補清單

| 檔案 | 對象 | 規模 |
|---|---|---|
| `patches/scummvm-tentacle-zhtw.patch` | ScummVM（`engines/scumm/`，3 個檔） | +97 |
| `patches/scummtr-maniacv1-lossless.patch` | ScummTR（`src/ScummRp/`，3 個檔） | +107 |

兩份都以「預設行為與上游完全相同」為前提：ScummTR 那份全部包在巨集開關裡，
ScummVM 那份的每一處都夾在 `isChtHiResCJK()`（= 本作 ＋ 中文 ＋ hi-res）之內。

`scummvm-tentacle-zhtw.patch` 的基準是**已套用一代（Maniac Mansion V2）修補的樹**，
因為 easter egg 那條產線要用到一代的 v1/v2 修補。重建順序見 `30-pipeline.md`。

## 字型與畫面：倚天 16×14，畫在 2 倍的文字表面上

中文字用倚天中文系統（ETEN 3.53）的 15 點原生點陣字，**裁掉全空的最後一列**變成 16×14，
畫在放大 2 倍的文字表面上。與 SCI 引擎中文化的 `GFX_SCREEN_UPSCALED_640x400` 同源：
原始美術照舊 2× nearest 放大，中文字直接畫進 display buffer，所以同一畫面
「美術照原樣、中文銳利」。

### 為什麼是 16×14 而不是 24×24 或 12×12

先做過 12×12（WQY 內嵌點陣，零引擎修補）。中文能出來、碼空間也對，但**版面塞不下**：

| 位置 | y（邏輯像素） |
|---|---|
| 指令區起點 | 144 |
| 句子列 | 145 |
| 指令第一列 | 152 |
| 指令第二列 | 168 |
| 指令第三列 | 184 |

三列指令之間有 16 個邏輯像素、很寬鬆，但**句子列到第一列只有 7**。
12×12 的 CJK 行高是 13，直接壓在第一列上。

倚天 15 點的字模是 16×15（邏輯 7.5），仍然超過 7。而實測倚天 15 點的**第 15 列完全沒有筆劃**
（25 個測試字裡 0 個用到），裁掉之後邏輯高剛好 7 —— 與原版英文的幾何一致，
**版面一處都不必改**，也不必動畫布高度。

24×24（邏輯 12）在本作行不通：句子列與第一列只差 7，必然重疊，得整套重排版面。
字型檔仍支援它（見下），但預設出 16×14。

### 字模尺寸由字型檔大小決定

`loadCJKFont()` 對 `GID_TENTACLE` 依 `檔案大小 / numChar`（numChar 固定 8178）決定：

| 每字 bytes | 字模 | 說明 |
|---|---|---|
| ≥ 72 | 24×24 | 倚天 24 點，hi-res |
| ≥ 30 | 16×15 | 倚天 15 點原尺寸，hi-res |
| ≥ 28 | **16×14** | 倚天 15 點裁掉全空的末列，hi-res（**預設**） |
| 其他 | 12×12 | 原版 ZH_CHN 規格，不走 hi-res |

換字型檔就等於換尺寸，不必另外開設定，也不必重編引擎。

## ScummVM 的三個檔

### `scumm.h`（1 處）

1. **`isChtHiResCJK()`** — hi-res CJK 是否生效（`_textSurfaceMultiplier == 2 && _useCJKMode &&
   GID_TENTACLE`）。所有修補都夾在這個條件裡，其他遊戲與英文版完全不受影響。

### `charset.cpp`（4 處）

2. **`loadCJKFont()` 的 `GID_TENTACLE` 分支** — 依字型檔大小決定字模尺寸，24/16 兩種尺寸
   設 `_textSurfaceMultiplier = 2`。
3. **`CharsetRenderer::getStringWidth()`** — 雙位元組累加的是**邏輯**寬（字模寬 / 2）。
   直接加 `_2byteWidth` 會讓換行與置中都以兩倍寬計算，長句提早折行。
4. **`CharsetRendererClassic::getCharWidth()`** — 同理再除以 multiplier。
5. **`CharsetRendererClassic::printChar()` / `printCharIntern()`** — 畫用**字模**尺寸、
   推進與 `_str` 邊界用**邏輯**尺寸；中文一律畫到 2 倍的文字表面。
   - [雷] 文字表面的 y 要跟原路徑畫到的**絕對**位置一致：走虛擬螢幕分支時原本畫在
     `drawTop = _top - vs->topline`，換算回整個畫面是 `_top`；只有走文字表面分支
     （房間畫面，可能有垂直捲動）才扣 `_screenTop`。一律扣的話指令列的中文會整批
     往上偏 7 個像素、疊到句子列上。
6. **`CharsetRendererCommon::getFontHeight()`** — CJK 模式回**邏輯**行高。

### `gfx.cpp`（3 處）

7. **`drawStripToScreen()` 的合成條件放寬到本作** — 一代補的「底圖 2× nearest 放大」
   是通用碼（外層條件是 `_game.version < 7`，v6 進得去），只是內層夾了 `GID_MANIAC`。
   沒有這一步，`_textSurfaceMultiplier = 2` 會讓底圖整片錯位變成雪花。
8. **`restoreBackground()` 一併清對應的文字表面** — 指令列這種沒有雙緩衝的虛擬螢幕，
   原本靠 `fill()` 把文字一起蓋掉，而 hi-res 的中文畫在文字表面上，`fill` 碰不到。
9. **`restoreCharsetBg()` 改成只清「當前虛擬螢幕」對應的那一塊** — 見下。

## [雷·必看] `clearTextSurface()` 清的是整片，而 v6 的 verb 不會自己重畫

**症狀**：指令列九格中文，只有「使用」那一格憑空消失；其他八格都在，滑過去還會反白。

**排查過程中三個誤判**（都靠實機資料推翻）：

1. 「是行高溢出」→ 換 16×14 讓幾何與英文一致，症狀不變。
2. 「是句子列的清除範圍咬到它」→ 印出實際矩形：句子列 `(108,145)-(211,153)`、
   「使用」`(116,152)-(132,159)`，只重疊 1 個邏輯像素，不足以讓整格消失。
3. 「是字沒被畫」→ 印出繪製座標，`left=116/124, top=152` 都有畫，位置正確。

**真正的根因**要把文字表面 dump 出來才看得到：整個指令區的文字表面上**只剩「走到」與「查看」**
（剛重畫過的那兩個），其餘七格的中文全被清空——畫面上看得到的只是先前合成留在螢幕上的殘影。

`clearTextSurface()` 清的是**整片**文字表面，而它在 `restoreCharsetBg()` 裡的觸發條件是
`vs->hasTwoBuffers`——也就是**主畫面**每重畫一次，就把指令區那塊也清掉。
一代（v2）沒事，因為 v2 的指令列每幀重畫，下一幀就補回來；**v6 的 verb 只在狀態改變時才重畫**，
清掉就再也不會回來。

至於為什麼偏偏是「使用」：它是九格裡唯一與句子列橫向範圍（108–211）重疊的。
其他格所在的 strip 沒有被重新合成，螢幕上的殘影就一直留著，看起來像是正常的。

**修法**：hi-res CJK 時，`restoreCharsetBg()` 只清當前虛擬螢幕對應的那一塊文字表面，
不清整片。主畫面清主畫面、指令列清指令列，互不干擾。

**教訓**：一代那段「清整塊文字表面」的修補是為 v2 的重畫時機寫的。
照抄到 v6 時前提已經不成立——柵欄原則反過來用也一樣要問「它當初為什麼這樣寫」。

## ScummTR 的兩個開關

見 [`00-engine-verification.md`](00-engine-verification.md) 的 F8、F9。
建置時要同時帶一代的三個開關：

```bash
cmake .. -DCMAKE_BUILD_TYPE=Release -DCMAKE_CXX_FLAGS="\
  -DSCUMMTR_PRESERVE_AMBIGUOUS_OI \
  -DSCUMMTR_KEEP_DANGLING_INDEX_ENTRIES \
  -DSCUMMTR_CJK_CUSTOM_CODESPACE \
  -DSCUMMTR_PRESERVE_V1_ROOM_OFFSETS \
  -DSCUMMTR_PRESERVE_DUP_INDEX_ENTRIES \
  -DSCUMMRP_OK_TO_CORRUPT_MANIACV2"
```

## 回歸測試

每次改完 ScummTR 都要重跑「英文原封回填 → 逐檔 byte 比對」：
v1 的 53 個 LFL 與 `TENTACLE.000/.001` 全部 byte-perfect。
