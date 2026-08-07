# 進度與待辦

最後更新：2026-08-08。

## 兩條產線

| | 瘋狂時代（SCUMM v6, 1993 CD） | 泰德電腦裡的一代（SCUMM v1, 1987） |
|---|---|---|
| ScummVM 偵測 | ✅ `Day of the Tentacle (CD/English)` | ✅ `Maniac Mansion (V1/DOS/English)` |
| 抽字 | ✅ 6,647 行（SCRP 2340／VERB 1921／LSCR 1859／OBNA 509／ENCD 15／EXCD 1） | ✅ 1,121 行 |
| round-trip byte-perfect | ✅ 2 檔全過 | ✅ 53 個 LFL 全過 |
| 翻譯 | ⬜ 未開始（小樣 33 行已驗證） | ⬜ 未開始 |
| 字型 | 小樣用 12×12（WQY 內嵌點陣）驗通；正式版走倚天 24×24 | 同左 |
| 引擎修補 | ⬜ 待評估（見下） | ⬜ 待評估 |
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

## 眼前的決策點：版面

句子列與指令列只差 8 個邏輯像素，而 CJK 模式下 `getFontHeight()` 回
`MAX(_2byteHeight + 1, _fontHeight)` = 13，直接溢出。這與一代（v2）踩到的是同一類問題，
一代的解法是把畫布加高、指令區從 56 個邏輯像素擴到 84。

**所以「12×12 零修補」對本作不成立**——不是碼空間的問題，是版面幾何。這反而讓
「既然都要動版面，不如直接上倚天 24×24」變成合理選擇（使用者已選定這條）。

hi-res 在 v6 的可行性已初步查證，骨架是現成的：

- `CharsetRendererClassic::printCharIntern()` 本來就把 `_textSurfaceMultiplier` 算進
  `_textSurface.getBasePtr()`（upstream 給 FM-Towns／Mac 用的路徑）。
- 一代補在 `drawStripToScreen()` 的「底圖 2× nearest 放大」是通用碼，外層條件是
  `_game.version < 7`，v6 進得去；只是內層條件夾了 `GID_MANIAC && version == 2`，要放寬。

待實作與驗證：`loadCJKFont()` 給 `GID_TENTACLE` 設 24×24＋multiplier=2、
邏輯／字模尺寸換算（Classic 版的 `getCharWidth`／`getFontHeight`）、指令列與句子列的版面。

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
