# 進度與待辦

最後更新：2026-08-08。

## 兩條產線

| | 瘋狂時代（SCUMM v6, 1993 CD） | 泰德電腦裡的一代（SCUMM v1, 1987） |
|---|---|---|
| ScummVM 偵測 | ✅ `Day of the Tentacle (CD/English)` | ✅ `Maniac Mansion (V1/DOS/English)` |
| 抽字 | ✅ 6,647 行（SCRP 2340／VERB 1921／LSCR 1859／OBNA 509／ENCD 15／EXCD 1） | ✅ 1,121 行 |
| round-trip byte-perfect | ✅ 2 檔全過 | ✅ 53 個 LFL 全過 |
| 翻譯 | ✅ **4,239 / 4,386 句（96.6%）**，未翻的 147 句全是除錯訊息與工作人員名單 | ⬜ 未開始（8 批 872 句） |
| 字型 | ✅ **倚天 16×14 hi-res**，2,149 字 | 待做 |
| 引擎修補 | ✅ 3 檔 +97 行（`patches/scummvm-tentacle-zhtw.patch`） | ⬜ 待評估（U5） |
| 全量回填 | ✅ 6,648 行 byte-perfect、56,048 個中文字、0 孤兒高位元組 | ⬜ |
| 中文語音（TTS） | ⬜ 未開始，見〈語音〉 | 無語音 |

其中 1,038 行去掉語音前綴後是空的（純控制碼），不需翻譯。

## 瘋狂時代：翻譯已完成

37 個批次全部翻畢，`tools/check_batches.py` 格式全數通過。刻意留空（沿用原文）的 147 句是：

- SCUMM 內部除錯訊息（`ambience debugging on`、`q-sound:`、`copy-protect: point 3`…）
- 工作人員名單中夾人名與空白對齊的行 —— 名字不翻，且那些行靠空白排版，改動會破版。
  純標題行（`編劇與設計`、`動畫師`、`音樂`、`數位特效剪輯`、`iMUSE 技術提供`、`劇終`）已翻。
- 時光膠囊上的密碼字母 `F` / `R` / `W`

### 回填驗收（2026-08-08）

```
送入行數 6648  抽回行數 6648
不一致行數: 0
回填後中文字數: 56048   孤兒高位元組: 0
```

抽回用 `scummtr -g tentacle -r -w -of`，與回填同模式。**孤兒高位元組 = 0** 表示沒有任何
落在 0xA1–0xFD 卻不成對的位元組，也就是不會有字元級亂碼。

### 字型缺字

倚天 15pt 字庫覆蓋 2,149 字中的 2,148 字。唯一缺的是 **`・`（U+30FB）**，人名間隔號，
用 WQY Zen Hei 描補。原本另有兩字缺（`噻`、`〇`），已改寫譯文避開：
`哇噻`→`哇塞`、`一七九〇年`→`一七九零年`。

## 畫面與字型已定案：倚天 16×14 hi-res

12×12 零修補對本作不成立——不是碼空間問題，是幾何：句子列到指令第一列只有 7 個邏輯像素，
而 CJK 行高 13。改走 hi-res 之後，實測倚天 15 點的**第 15 列完全沒有筆劃**，裁掉變成 16×14、
邏輯高剛好 7，與原版英文幾何一致，**版面一處都不必改**。

24×24（邏輯高 12）在本作行不通，那 7 個像素放不下；字型檔仍支援，但不是預設。

實機驗收：指令列九格中文齊全、句子列共存、底圖無雪花、無截字、無殘影。

排查過程中最花時間的一個雷（`clearTextSurface()` 清整片 vs v6 的 verb 不重畫）
寫在 [`20-patches.md`](20-patches.md)。

## 已完成的工具鏈

docker image、patched ScummVM（`--disable-all-engines --enable-engine=scumm`，
`USE_FLAC = 1` 已反查）、含五個開關的 ScummTR。

**ScummTR 的兩個新 bug 已查明並修掉**（`patches/scummtr-maniacv1-lossless.patch`）。
根因與驗收見 [`00-engine-verification.md`](00-engine-verification.md) 的 F8、F9。
重點是 v1 這條路**沒有保護傘**：scummtr 只擋 V2（`Modifying Maniac Mansion V2 is known to
corrupt it`），v1 會安靜地把 00.LFL 改壞。

## 語音（使用者需求，尚未開始）

目標是用台灣中文 TTS 配中文語音，角色音色貼近英文原音。已知的工程輪廓：

1. 譯文必須先完成 —— 已完成，這一項不再擋路。
2. 每句台詞在腳本裡帶 16 bytes 的語音索引（F6），指向 `monster.sof` 內的位置。
   換成中文語音後，這 5,316 筆索引全部要重算並改寫。
3. `monster.sof` 是 FLAC 壓縮版（95 MB）；ScummVM 也吃 `.sou`／`.sog`／`.so3`。
4. 角色與台詞的對應要先建（哪一句是誰說的），才能分配音色。

尚未驗證：`monster.sof` 的解包與重新打包、索引重算的可行性、TTS 音色與音調的對應方式。

## 待辦

1. **一代（v1）翻譯**：8 批 872 句。可從
   [一代專案](https://github.com/wicanr2/maniac_mansion_cht) 的 v2 譯文移植，
   但 v1 與 v2 行數不同，要逐行重新對位。
2. **v1 引擎修補**：`loadCJKFont()` 目前的閘門是 `_game.version == 2 && GID_MANIAC`，
   要放寬到涵蓋 v1；v1 的版面數字（句子列與指令列間距）待實測（U5／U6）。
3. 瘋狂時代譯文校對第二輪。
4. easter egg 完整鏈路驗證（DOTT → 泰德的電腦 → 一代 → 返回且進度還在）。
5. 中文語音（TTS）。
6. 打包（雙 target ini）、README 補實機圖、宣傳片。
