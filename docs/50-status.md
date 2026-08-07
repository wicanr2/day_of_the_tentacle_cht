# 進度與待辦

最後更新：2026-08-08。

## 兩條產線

| | 瘋狂時代（SCUMM v6, 1993 CD） | 泰德電腦裡的一代（SCUMM v1, 1987） |
|---|---|---|
| ScummVM 偵測 | ✅ `Day of the Tentacle (CD/English)` | ✅ `Maniac Mansion (V1/DOS/English)` |
| 抽字 | ✅ 6,647 行（SCRP 2340／VERB 1921／LSCR 1859／OBNA 509／ENCD 15／EXCD 1） | ✅ 1,121 行 |
| round-trip byte-perfect | ✅ 2 檔全過 | ✅ 53 個 LFL 全過 |
| 翻譯 | ⬜ 未開始（小樣 33 行已驗證） | ⬜ 未開始 |
| 字型 | **倚天 16×14 hi-res**（見下） | 待做 |
| 引擎修補 | ✅ 3 檔 +97 行（`patches/scummvm-tentacle-zhtw.patch`） | ⬜ 待評估 |
| 中文語音（TTS） | ⬜ 未開始，見〈語音〉 | 無語音 |

其中 1,038 行去掉語音前綴後是空的（純控制碼），不需翻譯。

## 已完成

**工具鏈**：docker image、patched ScummVM（`--disable-all-engines --enable-engine=scumm`，
`USE_FLAC = 1` 已反查）、含五個開關的 ScummTR。

**ScummTR 的兩個新 bug 已查明並修掉**（`patches/scummtr-maniacv1-lossless.patch`）。
根因與驗收見 [`00-engine-verification.md`](00-engine-verification.md) 的 F8、F9。
重點是 v1 這條路**沒有保護傘**：scummtr 只擋 V2（`Modifying Maniac Mansion V2 is known to
corrupt it`），v1 會安靜地把 00.LFL 改壞。

**小樣驗證（12×12 零修補）**：翻了指令列 24 行 ＋ 開場對白 9 行，走完
「蒐集字集 → 碼表 → 編碼 → 烘字型 → 回填 → 實機」整條路徑。實機截圖確認：

- ✅ 指令列九個 verb 全中文：給予／拿起／使用、打開／查看／推、關上／交談／拉
- ✅ 句子列會組句（「走到 Chuck the Plant」）
- ✅ 無字元級亂碼、無截字 —— 碼空間與字型索引都正確
- ❌ **句子列壓在指令列第一列上，把「使用」蓋掉**

## 畫面與字型已定案：倚天 16×14 hi-res

12×12 零修補對本作不成立——不是碼空間問題，是幾何：句子列到指令第一列只有 7 個邏輯像素，
而 CJK 行高 13。改走 hi-res 之後，實測倚天 15 點的**第 15 列完全沒有筆劃**，裁掉變成 16×14、
邏輯高剛好 7，與原版英文幾何一致，**版面一處都不必改**。

24×24（邏輯高 12）在本作行不通，那 7 個像素放不下；字型檔仍支援，但不是預設。

實機驗收（`screenshots/verb-zh-16x14.png`）：指令列九格中文齊全、句子列共存、
底圖無雪花、無截字、無殘影。

排查過程中最花時間的一個雷（`clearTextSurface()` 清整片 vs v6 的 verb 不重畫）
寫在 [`20-patches.md`](20-patches.md)。

## 語音（使用者需求，尚未開始）

目標是用台灣中文 TTS 配中文語音，角色音色貼近英文原音。已知的工程輪廓：

1. 譯文必須先完成 —— TTS 吃的是譯文。
2. 每句台詞在腳本裡帶 16 bytes 的語音索引（F6），指向 `monster.sof` 內的位置。
   換成中文語音後，這 5,316 筆索引全部要重算並改寫。
3. `monster.sof` 是 FLAC 壓縮版（95 MB）；ScummVM 也吃 `.sou`／`.sog`／`.so3`。
4. 角色與台詞的對應要先建（哪一句是誰說的），才能分配音色。

尚未驗證：`monster.sof` 的解包與重新打包、索引重算的可行性、TTS 音色與音調的對應方式。

## 待辦

1. 引擎修補：hi-res（24×24）＋版面，先回報範圍再動手。
2. 倚天字型烘製（`STD.24M`；字形來源倚天為主，缺字用華康／WQY 補）。
3. 全量翻譯：瘋狂時代 6,647 行、一代 1,121 行；一代可從
   [一代專案](https://github.com/wicanr2/maniac_mansion_cht) 的 v2 譯文移植對位。
4. 譯名表：一代角色沿用既有譯名；新角色（Laverne、Hoagie、開國元勳等）待定。
   開國元勳採通用中文譯名（華盛頓、富蘭克林、傑佛遜等）。
5. easter egg 完整鏈路驗證（DOTT → 泰德的電腦 → 一代 → 返回且進度還在）。
6. 中文語音（TTS）。
7. 打包（雙 target ini）、README、宣傳片。
