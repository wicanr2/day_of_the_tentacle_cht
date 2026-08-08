# 進度與待辦

最後更新：2026-08-08。

## 兩條產線

| | 瘋狂時代（SCUMM v6, 1993 CD） | 泰德電腦裡的一代（SCUMM v1, 1987） |
|---|---|---|
| ScummVM 偵測 | ✅ `Day of the Tentacle (CD/English)` | ✅ `Maniac Mansion (V1/DOS/English)` |
| 抽字 | ✅ 6,647 行（SCRP 2340／VERB 1921／LSCR 1859／OBNA 509／ENCD 15／EXCD 1） | ✅ 1,121 行 |
| round-trip byte-perfect | ✅ 2 檔全過 | ✅ 53 個 LFL 全過 |
| 翻譯 | ✅ **4,239 / 4,386 句（96.6%）**，未翻的 147 句全是除錯訊息與工作人員名單 | ✅ **859 / 872 句（98.5%）**，未翻的 13 句是媒體名與殘留字串 |
| 字型 | ✅ **倚天 16×14 hi-res**，2,149 字 | ✅ **倚天 16×15**，1,041 字 |
| 引擎修補 | ✅ 合併為單一 `patches/scummvm-zhtw.patch`（13 檔 +432 −23） | ✅ 14 處閘門放寬到 `version <= 2` |
| 全量回填 | ✅ 6,648 行 byte-perfect、56,048 個中文字、0 孤兒高位元組 | ✅ 1,122 行 byte-perfect、7,803 個中文字、0 孤兒首碼 |
| 中文語音（TTS） | ✅ 兩組（台式中文／原音克隆）各 4,431 句，遊戲中 Ctrl+T 切換 | 無語音 |

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

## 語音：兩組中文語音包已完成，遊戲中可切換

細節見 [`60-voice.md`](60-voice.md)。摘要：

| | |
|---|---|
| 台式中文（edge-tts） | 4,431 句，0 失敗，`monster-tw.sof` 122 MB |
| 原音克隆（F5-TTS，東京 GPU） | 4,431 句，0 失敗，`monster-cl.sof` 121 MB |
| 音高 | 依原音基頻分 10 帶挑聲音與 pitch，不必先知道哪句是誰說的 |
| 響度 | 逐段對齊原版 RMS，中位增益 1.60x |
| 切換 | 遊戲中 Ctrl+T 循環，選擇記進 `cht_voice_pack` |

先前這一節寫的「5,316 筆索引全部要重算」是**錯的**：`org_offset` 只是查表的
key，重建時保留原值即可，腳本一個位元組都不用動。證據是把 dump 裡所有語音前綴
解出來，5,269 行全部命中索引表、0 未命中。

還沒做：嘴型同步的時間戳仍是英文的節奏，沒有依中文長度重算。

## 一代（v1）：翻譯與實機驗收已完成

譯文 820 句從[一代專案](https://github.com/wicanr2/maniac_mansion_cht)的 v2
譯文移植（以**原文字串**對位，不靠行號；觸手譯名統一成本作的紫色／綠色觸手），
另手補 39 句。留原文的 13 句是媒體名（Analog、COMPUTE!'s Gazette、The New York
Times…）、`THX 1138` 彩蛋，以及那三行沒被用到的整行 verb 表。

指令列已逐像素量過，單字 16、雙字 32 實體像素，沒有重疊或溢出（見
[`20-patches.md`](20-patches.md)）。

## easter egg：已在遊戲內驗證

不必真的玩到遊戲中段——電腦在 **room 42**（怪異愛德的房間），用 ScummVM 的
debugger `room 42` 跳過去就行。房間號是從 `scummtr -h` 的 dump 反查的：
`[042:OBNA#0432]computer`。

證據鏈三條：

1. `screenshots/egg-1-ed-room-zh.png` —— room 42 的中文畫面（伯納對電腦說
   「雖然你只有 64K 記憶體，我還是尊敬你。」）
2. 對電腦下「使用」之後，log 出現
   `User picked target 'maniac-zh'` 與 `Classic V1 game detected`
3. `screenshots/egg-2-maniac-launched.png` —— 一代的選角畫面跳出來，
   而且是中文的（「請再選兩個人。」）

回程沒有模擬玩家按 F5（GUI 點擊在 headless 下不穩），改成檢查它的憑據：
`startManiac()` 會先把 DOTT 的狀態存進 slot 100 再推 chained games，
而那個檔確實生出來了——`~/.local/share/scummvm/saves/dott-zh.c100`，21 KB。
回程要用的資料備妥了，切換本身是 ScummVM 的既有機制，本專案沒有動它。

### headless 點擊的兩個雷

* `xdotool click` 太快，ScummVM 常常收不到。要拆成 `mousedown` / `mouseup`
  並留 0.25 秒間隔。
* 進房間後的**第一次點擊會被吃掉**（進場腳本還在跑）。沒有先點一次空白處消化，
  句子列會停在「走到」而不是選好的指令，看起來像座標算錯。

## 校對第二輪：已完成

`tools/lint_translation.py` 查四件 `check_batches.py` 管不到的事：譯名一致、
半形標點、物件名長度、疑似未翻。兩條產線都四項全過。

物件名的長度判定不靠猜——用 `scummtr -h` 抽一份帶區塊類型的 dump，只對
`OBNA`（v6）與 `ONv1`（v1）做檢查。第一版憑「看起來像不像物件名」猜，30 條裡
26 條是誤判；換成區塊類型之後收斂到 2 條真問題（都已改短）。

檢查器本身以故意違規的檔做過正對照，四項都抓得到。

## 打包：三平台都有了

| | Linux | Windows | macOS |
|---|---|---|---|
| 引擎 | ✅ slim 版（53 相依，自帶 49 支 .so） | ✅ mingw 交叉編譯 + SDL2.dll | ✅ CI 出 universal（arm64+x86_64） |
| ScummTR | ✅ | ✅ 交叉編譯 | ✅ CI 一併編 universal |
| patch 包 | ✅ 12 MB | ✅ 14 MB | ✅ 19 MB |
| full 包（含三組語音） | ✅ 254 MB | ✅ 265 MB | ✅ 270 MB |
| 實測 | ✅ 乾淨的 `ubuntu:24.04` 跑得起來 | ✅ wine 下 `--version` 與 `--detect` 都對 | ⚠ 兩支都驗過是 fat binary，但**沒有實體 Mac 可測** |

macOS 的 `.app` 精簡過：CI 會把 ScummVM 樹裡的 engine-data 整批塞進去（`ultima.dat`
15 MB、`fonts-cjk.dat` 37 MB…），而這支 binary 只編了 SCUMM，那些永遠不會被讀。
只留 `fonts.dat` 與 `classicmacfonts.dat` 之後，Resources 從 72 MB 降到 7.1 MB，
patch 包從 82 MB 降到 18 MB。

三平台的 binary 都用正對照確認過含語音切換（`strings | grep CHTVOICE`，
macOS 的 universal binary 會出現兩次，每個架構各一）。查的是
`ScummVM.app/Contents/MacOS/scummvm.bin`——同目錄的 `scummvm` 是啟動用的
shell script，對它做 `strings` 永遠是 0。

`Features compiled in: FLAC` 兩個平台都確認過——沒有它 `monster.sof` 讀不出來，
而且**不會報錯**，只是整片語音消失。

### 字型分兩份

公開的 patch 包用 **WenQuanYi Zen Hei Sharp 的 15px embedded bitmap**
（GPL + 字體例外，可散布）；倚天那份筆畫更銳利，但是商業字型的衍生物，
只進留本機的 full 包。兩份字模尺寸與碼位完全相同，換檔就換字形。
這條界線沿用一代專案的做法。

### 端到端驗收

拿 patch 包走一次玩家的路徑：`套用中文化.sh` 吃原版目錄 → 回填 → 啟動。
回填後 `TENTACLE.001` 數得出 549,985 個中文字組、`maniac/01.LFL` 數得出 87 個，
遊戲正常進到開場動畫。`Unrecognized game`（ini 註解用了 `;`）那個雷就是在這一步抓到的。

### mac CI 的下載會偶爾斷

`downloads.xiph.org` 從 GitHub 的 macOS runner 連過去偶爾斷在 TLS 握手
（curl exit 35，LibreSSL `SSL_ERROR_SYSCALL`）。`--retry 3` 救不了——curl 只
重試它認定的暫時性狀況，35 不在其中——要 `--retry-all-errors`。已改，並加了
osuosl 鏡像當備援。

## Release

**v1.0 已釋出**，只上三個 patch 包（Linux `.tar.zst`／Windows `.zip`／
macOS `.tar.gz`）。**full 包與語音包不進 Release**——full 包含中文化後的遊戲
資料，語音包是原版 `monster.sof` 的改造版（113 段仍是原音）且 edge-tts 的輸出
散布屬灰色地帶。兩者只留本機 `dist-all/`。

## 待辦

1. 嘴型同步：中文語音的時間戳仍是英文節奏，沒有依中文長度重算。
2. 宣傳片（含兩組中文語音的 A/B 展示）。
