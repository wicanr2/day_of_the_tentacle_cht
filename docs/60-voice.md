# 中文語音（TTS）

目標是把 CD 版的英文語音換成台灣中文 TTS，而且**角色音調貼近英文原音**。

這份文件記的是已經坐實的機制與量測，還沒做的部分寫在最後。

## monster.sof 的格式（已 byte-perfect 驗證）

由 ScummVM `engines/scumm/sound.cpp` 的 `setupSfxFile()` 與 `startTalkSound()`
推導：

```
u32be  index_size                     索引區的位元組數
index_size/16 筆，每筆 16 bytes：
    u32be org_offset                  原始 monster.sou 裡的 offset
    u32be new_offset                  本檔資料區的相對 offset
    u32be num_tags                    嘴型同步時間戳的位元組數
    u32be compressed_size             壓縮音訊的位元組數
資料區（緊接索引之後，每筆連續排列）：
    [num_tags bytes 的 uint16be 時間戳][compressed_size bytes 的 FLAC]
```

本作的實測值：

| | |
|---|---|
| 索引區 | 72,704 bytes → **4,544 筆語音** |
| 音訊 | 標準 FLAC，單聲道，11,025 或 22,050 Hz |
| 佈局 | 4,543 個相鄰對**全部**滿足 `new + tags + size = 下一筆的 new`，最後一筆結尾正好等於檔案大小 94,948,005 |
| round-trip | 解包再打包，md5 與原檔**完全一致** |

工具：[`tools/sof_pack.py`](../tools/sof_pack.py)（`list` / `verify` / `build --replace`）。

## 腳本索引：不用改腳本

每句配音台詞在腳本裡前綴 16 bytes，四組 `\255\010 XX YY`。
`ScummEngine::handleNextCharsetCode()` 的 `case 10` 這樣解：

```cpp
digiTalkieOffset = buffer[0] | (buffer[1] << 8) | (buffer[4] << 16) | (buffer[5] << 24);
digiTalkieLength = buffer[8] | (buffer[9] << 8) | (buffer[12] << 16) | (buffer[13] << 24);
```

（中間跳過的 `buffer[2]`/`buffer[3]` 是下一組的 `\255\010`。）

算出來的 `digiTalkieOffset` 就是索引表的 `org_offset`，`startTalkSound()`
拿它去二分搜尋。**驗證：把 dump 裡所有語音前綴解出來，5,269 行全部命中索引表，
0 未命中。**

這件事推翻了先前「換語音要重算 5,316 筆索引」的估計：**`org_offset` 只是查表的
key，重建時保留原值，腳本一個位元組都不用動。** 要換的只有音訊本身。

`digiTalkieLength` 只用來算嘴型同步的數量，而且與索引表不一致時引擎只印 warning
並改用索引表的 `num_tags`（`sound.cpp` 685 行），不會讓語音播不出來。

## 語音 ↔ 台詞 ↔ 譯文

`dumps/voice_map.json`（由 dump 與譯文批次併出來）：

| | |
|---|---|
| 腳本用到的語音 offset | 4,530 筆 |
| 其中有中文譯文 | 4,431 筆 |
| 原文為空（純控制碼，笑聲／驚呼之類無字幕語音） | 91 筆 |
| 有原文但譯文留空 | 8 筆 |

monster.sof 裡的 4,544 筆比腳本用到的多 14 筆，那些是沒被引用的。

## 音調：用原音的基頻決定 TTS 參數

使用者的要求是「人物音調要依照英文語音的音調」。做法是量原音的基頻（F0），
再據此挑 TTS 的基礎聲音與 pitch 偏移——**不需要先知道哪句是誰說的**。

120 段抽樣的實測分布：

```
min 67   p25 132   中位 180   p75 242   max 390 Hz
```

是明顯的多峰，聽感上分得開：

| F0 | 例句 |
|---|---|
| 67 Hz | `Fascinating.` |
| 87 Hz | `It's too complicated for me.` |
| 299 Hz | `^YESTERDAY!`（佛瑞德博士激動時） |
| 390 Hz | `Hahahaha!`（笑聲） |

## TTS 引擎的比較（都實測過）

### piper：腔調不對，出局

本地、離線、極快，但中文模型只有四個，**全部是 zh_CN**（大陸腔），
每個只有一位說話者：`zh_CN-chaowen-medium`、`zh_CN-huayan-medium`、
`zh_CN-huayan-x_low`、`zh_CN-xiao_ya-medium`。本專案要的是台灣語音。

### edge-tts：夠用

三個台灣聲音，實測各 pitch 下的**實際基頻**：

| 聲音 | −40Hz | +0Hz | +40Hz | 同一句的長度 |
|---|---|---|---|---|
| `zh-TW-YunJheNeural`（男） | 82 | 110 | 140 Hz | 5.9 s |
| `zh-TW-HsiaoYuNeural`（女） | 138 | 188 | 239 Hz | 6.7 s |
| `zh-TW-HsiaoChenNeural`（女） | 158 | 216 | 271 Hz | 5.8 s |

**連續覆蓋 82–271 Hz，中間沒有斷層**；HsiaoYu 的語速明顯較慢，是額外的音色維度。
原音的 F0 分布是 66–390 Hz（中位 180），兩端各有一小塊超出覆蓋範圍，
可以用後製調 pitch 補。

[雷] 裝在 `dott-cht:latest` 的 `/opt/venv` 會相依衝突（那個 venv 帶
`--system-site-packages`），要另開一個乾淨的 venv。

### voice cloning（F5-TTS 等）

質的不同——用英文原音當 reference，讓角色**用自己的聲音講中文**。
本機沒有 NVIDIA GPU（只有 Intel Meteor Lake 內顯），14 核 CPU，
所以只能跑 CPU 版。速度實測見下。

## 音高帶：不必先知道哪句是誰說的

全量 F0（4,436 段量得到）：

```
十分位  66 / 105 / 121 / 139 / 160 / 179 / 205 / 225 / 244 / 266 / 390 Hz
音訊總長 201 分鐘，平均每句 2.72 秒，最長 21.4 秒
```

依 edge-tts 的實測覆蓋範圍切成 10 帶，每帶 192–661 句，分布相當均勻
（`tools/voice_bands.py`）。同一角色的句子多半落在同一帶，聽感自然一致；
帶的中心頻率就是那組句子該有的音高。每帶另外挑一段 3–8 秒的原音當
voice cloning 的 reference。

## 音訊規格：8 bit，跟原版同一個量級

原版語音是 1993 年的 **8-bit 22,050 Hz** 錄音（`ffprobe` 的
`bits_per_raw_sample=8`），FLAC 壓完每秒約 7.2 KB。

TTS 直出的 24-bit 每秒要 35 KB，全量換完 `monster.sof` 會從 95 MB 膨脹到
**550 MB**。降成 8 bit（`-c:a pcm_u8` 再壓 FLAC）之後每秒 8.6 KB，
30 句實測平均 25.6 KB，**全量推估 111 MB**——與原版音訊的 90.5 MB 同一個量級。
顆粒感反而更貼近遊戲本身的錄音。

## 小樣（已跑通）

開場五句換成中文，走完「edge-tts → mp3 → ffmpeg 轉 22050 Hz 單聲道 FLAC →
`sof_pack.py build --replace` → 新的 monster.sof」：

| offset | 譯文 | 參數 |
|---|---|---|
| 241851264 | 這全都是你的錯，伯納。 | YunJhe, -15Hz |
| 242150623 | 等等！ | YunJhe, +25Hz, +10% |
| 243274831 | 到時光機去！ | YunJhe, -25Hz, -5% |
| 241215647 | 唉呀。 | YunJhe, +30Hz |
| 240982514 | 喔，對喔。 | YunJhe, +30Hz |

## [雷] 差點毀掉原版資料

第一版的小樣腳本直接 `open('game-cht/dott/monster.sof', 'wb')`，而那個路徑是
**硬連結**回 `game-orig` 的同一個 inode——`ls` 看起來就是一般檔案，只有
`st_nlink = 2` 會透露。寫下去等於把原版一起改掉，md5 當場就變了。

原版是從 `Day_of_the_Tentacle_1993.zip` 重新解出來復原的，損失為零。
`sof_pack.py` 的 `write_sof()` 現在會先檢查 `islink` 或 `st_nlink > 1`，
是連結就先 `unlink` 再寫新檔。

## 還沒做的

1. **全量合成**：4,431 句。edge-tts 是線上服務，每句約 1–2 秒，估
   **2–3 小時**，要分批與重試（大量呼叫可能被限流）。
2. **嘴型同步**：中文語音長度與英文不同，原本的時間戳會對不上嘴型。
   保留原值最省事（嘴型跟著英文節奏動），依中文長度重算比較準。
3. **授權**：`edge-tts` 走的是微軟 Edge 的線上服務，拿它的輸出散布屬灰色地帶。
   離線替代是 `piper`（MIT），但台灣腔的中文模型品質較差。
   **語音包不論用哪個引擎都不會進公開 repo**（跟遊戲資料同一條界線）。
