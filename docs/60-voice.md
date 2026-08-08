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

[細節] 產出的 FLAC 檔頭寫的是 16-bit，不是 8-bit：**ffmpeg 的 flac 編碼器只吃
`s16`／`s32`**（`ffmpeg -h encoder=flac` 可查），餵 8-bit wav 給它會自動升成
s16。省下來的空間仍然是真的——量化到 256 階這件事發生在 `pcm_u8` 那一步，
FLAC 只是把低位元組全為零的資料壓得很好。原版那些段是用 libFLAC 直接寫的，
檔頭才是真正的 `bits_per_raw_sample=8`（且取樣率多為 11,025 Hz）。
引擎讀出來一律是 s16，兩種都正常播。

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

## 全量合成：兩組語音都跑完了

| | edge-tts（台式中文） | F5-TTS（原音克隆） |
|---|---|---|
| 句數 | 4,431 | 4,431 |
| 失敗 | 0 | — |
| 耗時 | 12 分 50 秒（併發 4） | 約 80 分（L40S，1.1 秒/句） |
| 機器 | 本機 | 東京 GPU（`login_tokyo_g6_issac-sim.sh`） |
| 產物 | `monster-tw.sof` 122 MB | `monster-cl.sof` |

實際比 edge-tts 的估計（2–3 小時）快得多——併發 4 沒有被限流，每句平均 0.17 秒。

F5-TTS 在 CPU 上是死路：`torchcodec` 要 `libavutil.so.56`（FFmpeg 4）加 CUDA
runtime，而 torchaudio 2.13 沒有 fallback。GPU 機器上用 `cu124` index 裝
torch 2.6.0 就沒這個問題。

## 響度：中文比原音小聲，要逐段對齊

實機錄音比對，同一段落原版 RMS 1,835，換上 TTS 只剩 477——聽起來就是「語音變小聲」。
原因是 1993 年的錄音經過壓縮、動態範圍窄，而 TTS 直出的動態範圍寬、平均音量低。

`tools/voice_normalize.py` 逐段量原版的 RMS，把對應的中文語音線性放大到同一個
RMS，再用 0.9 滿刻度的峰值上限夾住避免削波。**逐段而不是整批統一**，因為原版
本身各段音量就不一樣——耳語跟大吼不該被拉成一樣大。

4,430 段的結果：

```
增益  中位 1.60x   p10 1.29   p90 1.92   max 4.11（上限 8.0，沒有觸頂）
```

## 遊戲中切換語音包

三份 `.sof` 的索引表 `org_offset` 完全一致（差別只有音訊本身），所以切換語音
等於「換一個檔名再重讀一次索引」，腳本與存檔都不受影響。

引擎改了四個檔（都在 `patches/scummvm-zhtw.patch` 裡）：

| 檔 | 做什麼 |
|---|---|
| `scumm.h` | `ScummAction` 加 `kScummActionChtVoicePack` |
| `sound.h` | `ChtVoicePack` 列舉、`cycleChtVoicePack()`、`_chtVoicePack` |
| `sound.cpp` | `setupSfxFile()` 依 `_chtVoicePack` 先試 `monster-tw.*` / `monster-cl.*`；切換函式；讀寫 `cht_voice_pack` 設定 |
| `metaengine.cpp` | `initKeymaps()` 對 gameid `tentacle` 掛上 Ctrl+T |
| `input.cpp` | `EVENT_CUSTOM_ENGINE_ACTION_START` 直接處理（一次性動作，不進 `_actionMap`） |

幾個做法上的理由：

- **切換前要先 `stopTalkSound()` 並停掉 mixer channel。** 舊的 `_offsetTable`
  一釋放，還在解碼的串流就會指到已經釋放的記憶體。
- **檔名選擇失敗時靜靜退回原版**，並在 OSD 說明退回了哪一組。玩家沒放中文語音
  時一切照舊，不會因為設定檔殘留而沒有聲音。
- **OSD 訊息用英文。** 散布包刻意不帶 `fonts-cjk.dat`（ScummVM 自己的選單也是
  英文的），寫中文只會變成問號。
- **Ctrl+T**：SCUMM 引擎、全域 keymap、SDL 圖形後端都沒有人用這個組合。
  掛在 `engine-default` 上，玩家可以在 ScummVM 的按鍵設定裡改。

驗收（headless，`import -window root`）：

| 檢查 | 結果 |
|---|---|
| Ctrl+T 第一次 | OSD `Voice: Taiwanese Mandarin` |
| Ctrl+T 第二次（`monster-cl.sof` 還沒放） | OSD `Voice pack Cloned voices not found - using Original (English)` |
| 設定檔寫 `cht_voice_pack=1` 重開 | 播放期間 `/proc/<pid>/fd` 開的是 `monster-tw.sof` |

第三項是關鍵：OSD 只證明狀態變了，`/proc/<pid>/fd` 才證明引擎真的去讀了那個檔。

## 嘴型同步：保留原值

中文語音長度與英文不同，原本的時間戳對不上嘴型。目前保留原值——嘴型跟著英文
節奏動，看起來像是在講話但對不上音節。依中文長度重算會比較準，還沒做。

## 授權：語音包不散布

兩條界線都踩到：

1. `monster-tw.sof` 是原版 `monster.sof` 的改造版，4,431 段換成中文，
   **剩下 113 段仍是原音**。
2. `edge-tts` 走的是微軟 Edge 的線上服務，拿它的輸出散布屬灰色地帶。
   離線替代是 `piper`（MIT），但只有 zh_CN 模型，腔調不對。

所以**語音包不論用哪個引擎都不進公開 repo，也不進 patch 散布包**，只留本機的
`dist-all/` full 包。公開包只有英文原音會運作，切換鍵按下去會顯示「找不到」。
