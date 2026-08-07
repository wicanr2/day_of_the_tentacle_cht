# 引擎與工具鏈驗證結論

驗證日期 2026-08-07。結論以 ScummVM 源碼、ScummTR 源碼、光碟映像的實際內容與 md5 比對為依據，
不引用其他 SCUMM 版本的經驗推論。尚未驗證的項目集中在最後一節，標為「待驗」。

## 素材盤點

`Day_of_the_Tentacle_1993.zip`（306 MB）解出來是三份互不重疊的東西：

| 路徑 | 內容 | 用途 |
|---|---|---|
| `dott/TENTACLE.000`(7,932) `TENTACLE.001`(11 MB) `monster.sof`(95 MB) | 硬碟安裝的 CD 語音版 | 中文化主用。`.sof` 是 FLAC 壓縮語音 |
| `dott/DOTT/CD/Day Of The Tentacle.BIN`(342 MB) | 原始光碟映像，MODE1/2352 單軌 | 內含一代資料，以及 DOTT 與 Indy4 的試玩版 |
| `dott/MT32_CONTROL.ROM` `MT32_PCM.ROM` | Roland MT-32 音色 ROM | 本機完整版打包用，不入公開 repo |

光碟映像是 raw 2352，要先每 2352 bytes 取 `[16:2064]` 剝成 2048 的 ISO 才能掛載或用 7z 展開。
展開後 `DOTT/MANIAC/` 底下是 54 個 `.LFL` 加一個 `MANIAC.OVL`，檔案日期 1988-04-14。

## F1：easter egg 的機制是「另開一個 target」

`ScummEngine::startManiac()`（`engines/scumm/scumm.cpp:4370`）在已加入 ScummVM 的遊戲裡尋找一個
「路徑是目前遊戲夾底下的 `Maniac` 子目錄」的 target，找到就：

```cpp
_saveLoadFlag = 1; _saveLoadSlot = 100; _saveTemporaryState = true;
ChainedGamesMan.push(Common::move(maniacTarget));
ChainedGamesMan.push(ConfMan.getActiveDomainName(), 100);
// 送 EVENT_RETURN_TO_LAUNCHER，由 chained games 依序啟動
```

找不到時跳訊息框，內容是「game files for Maniac Mansion have to be in the 'Maniac' directory
inside the Tentacle game directory, and the game has to be added to ScummVM」。

三個推論：

1. 泰德電腦裡的那一代**是完整、獨立跑起來的 ScummVM 遊戲**。要它變成中文，就得做一次完整的中文化，
   不是在《瘋狂時代》裡貼一張字串表。
2. 兩個 target **各有自己的遊戲夾，各放各的 `chinese_gb16x12.fnt`**，字模尺寸與碼表可以完全不同，
   互不干擾。
3. `ConfMan` 有 `easter_egg` key 時直接吃那個 target 名，繞過路徑搜尋（同檔 4403 行）。
   打包時這比「必須放在 `Maniac/` 子目錄」有彈性，但兩種寫法都要求該 target 在設定檔裡真的存在。

## F2：光碟裡附的一代是 SCUMM V1，不是一代專案做的 V2

| 檔案 | md5（整檔） | `scumm-md5.h` 對應 |
|---|---|---|
| 光碟 `DOTT/MANIAC/00.LFL`（1,972 bytes） | `7f45ddd6dbfbf8f80c0c0efea4c295bc` | 第 439 行 `"maniac", "V1", "V1", 1972, EN_ANY, DOS` |
| 一代專案 `mansiond/00.LFL`（1,988 bytes） | `b250d0f9cc83f80ced56fe11a4fb057c` | 第 595 行 `"maniac", "V2", "V2", 1988, EN_ANY, DOS` |

檔案大小差距也支持這個判定（`01.LFL`：V1 版 8,290 vs V2 版 20,833）。
檔案日期雖然是 1988，但 md5 是決定性的一手證據。

**結論**：easter egg 這條產線是一次全新的 **v1** 中文化。一代的譯文可以移植參考，
但引擎修補的條件式與版面數字不能直接套用。

## F3：v1 與 v2 在 ScummVM 裡是同一個引擎類別

- `metaengine.cpp:471` 起：`case 0:` → `ScummEngine_v0`（C64 版），**`case 1:` 與 `case 2:` 都走
  `ScummEngine_v2`**。
- `setupCharsetRenderer()`：`_game.version <= 2` 且非 NES → `CharsetRendererV2`（繼承 `CharsetRendererV3`）。

所以一代推導出的空白壓縮規則與碼空間（首碼 `0x88–0x9F`、尾碼 `0xA1–0xFD`）**在同一支
`decodeParseString()` 上，對 v1 應該同樣成立**。這是機制層面的推論，仍要用 v1 的實際字串驗一次。

已知的 v1 專屬分支至少三處：`Player_V1` 音樂（`scumm.cpp:2553`）、
`VAR_TIMER_NEXT` 要進位到 3 的倍數（`2899`）、若干 gfx 判斷（`3528`）。

## F4：`GID_TENTACLE` 早就在 ZH_CHN 白名單裡

`engines/scumm/charset.cpp` 的 `case Common::ZH_CHN:` 分支列了
FT / LOOM / INDY3 / INDY4 / MONKEY / MONKEY2 / **TENTACLE**，設
`fontFile = "chinese_gb16x12.fnt"`、`numChar = 8178`、字模 12×12。

也就是說**《瘋狂時代》走 12×12 標準路徑是零引擎修補的**。
本專案改用倚天 24×24 是為了字形品質而自選的成本，不是被迫的。

對照之下，一代（v2）連外層的版本 gate 都過不了：

```cpp
} else if (_language == Common::KO_KOR ||
           (_game.version >= 7 && (…)) ||
           (_game.version >= 3 && _language == Common::ZH_CHN)) {
```

一代為此加了 `_game.version == 2 && _game.id == GID_MANIAC` 的放行條件與專屬分支。
**v1 走不到那個條件**，要放寬成 `<= 2`（待驗，見 U5）。

字型偵測那一側沒有版本限制：`detectLanguage()`（`detection_internal.h`）只要在遊戲夾看到
`chinese_gb16x12.fnt` 就回 `ZH_CHN`，所以中文開關對 v1／v2／v6 都有效。

## F5：ScummTR 兩條產線都支援，但 v1 沒有保護傘

`src/ScummRp/scummrp.cpp` 的遊戲定義表裡有 `maniacv1`(636)、`maniacv2`(638)、`tentacle`(674)。
`maniacv1` 與 `maniacv2` 的旗標同為 `GF_OLD_BUNDLE`，結構處理走同一份程式碼。

而 `src/ScummTr/scummtr.cpp:399` 的保護：

```
ERROR: Modifying Maniac Mansion V2 is known to corrupt it
```

**只擋 V2**。一代查出的兩個損壞根因都在與版本無關的共用碼裡：

- `OldRoom::_cleanup()` 把判定不出歸屬的物件圖位移（共用影像、零長度影像）清成 0；
- `LFLFile` / `OldLFLFile` 建構時抹掉「位移超過檔尾」的索引項，而原版資料本來就帶著兩筆這種死索引。

**推論：v1 會出現同樣的損壞，而且沒有任何錯誤訊息。**
處理方式是套用一代的 `scummtr-maniacv2-lossless.patch`（三處都以巨集開關包住，預設行為與上游相同），
並且在動文字之前先跑「抽 → 原封回填 → 逐檔 byte 比對」。

## F6：v6 talkie 的語音控制碼不可更動（本作是 16 bytes，不是 8）

《妙探闖通關》（同為 SCUMM v6 CD 版）的語音前綴是兩組 `\255\010`、共 8 bytes。
**本作實測是四組、共 16 bytes**：

```
\255\010\024\123  \255\010\009\000  \255\010\010\000  \255\010\000\000
```

6,647 行裡有 **5,316 行**帶這個前綴（配音台詞）。翻譯時整段原樣保留。

這條是「凡蒸餾自其他遊戲的規則，一律先在本作驗證再引用」的實例：照抄 8 bytes 會把後半段
控制碼當成台詞內文一起翻掉。

## F8：scummtr 會把 v1 的 room offsets 全部寫成 0

`GlobalRoomIndex::load()`（`src/ScummRp/toc.cpp`）對 V1 有一段自承的 hack：

```cpp
// hack for V1
if (size > 0) // means V1
    for (int i = 0; i < _size; ++i)
        _toc[i].offset = 0;
```

清零是 scummtr 內部模型需要的（V1 每個 room 自成一個 LFL 檔，內部一律以 offset 0 起算），
但 `save()` 會把清零後的值原樣寫回 00.LFL。而 ScummVM 的 `readClassicIndexFile()`
確實會讀這個欄位（`_res->_types[rtRoom][i]._roomoffs`）。

實測：原封回填後 00.LFL 有 **103 bytes** 差異，全部是 55 個 room offset 中的非零值被寫成 0
（另外 3 個原本就是 0、1 個 byte 恰好為 0，103 這個數字與此完全吻合）。

## F9：scummtr 會把原版自帶的重複索引寫成無效

`RoomPack::_checkDupOffset()`（`src/ScummRp/block.cpp`）有一批寫死的修正，其中兩條的註解
就叫 **"Hack for Maniac Mansion V1"**：原版資料裡

| 索引 | roomId | offset |
|---|---|---|
| script #7 ≡ #12 | 8 | 3524 |
| script #8 ≡ #13 | 8 | 3592 |

是重複的（同 room 同 offset，已逐 byte 驗過）。scummtr 的內部模型不允許重複位移
（否則丟 `Duplicate offset in index`），於是把編號較小那筆設成 -1。

抑制本身是必要的，**但它同樣被寫回檔案**：`0xFFFF` 是 ScummVM 的「無效索引」標記，
於是 script #7、#8 在遊戲裡就此消失。而那兩個位移經 block 鏈驗證都是**合法的 block 起點**
（鏈：0 → 3524 → 3592 → 3614 → …），不是原版的死索引。

實測：修掉 F8 之後，剩下的差異正好是這 **4 bytes**。

### 修法（`patches/scummtr-maniacv1-lossless.patch`，3 檔 107 行新增）

兩者同構：**內部照樣抑制，寫回時還原原值**。都以巨集開關包住，預設行為與上游完全相同。

- `SCUMMTR_PRESERVE_V1_ROOM_OFFSETS` — `GlobalRoomIndex` 留一份 room offset 原值，`save()` 時放回。
- `SCUMMTR_PRESERVE_DUP_INDEX_ENTRIES` — `_checkDupOffset()` 改呼叫新的 `suppressOffset()`，
  記下原值；`TableOfContent::save()` 進入時還原、離開時再抑制。這條同時修掉 Sam & Max、
  Loom、Monkey1 的同類 hack，不只本作。

還要一併套用一代查出的三個開關（`SCUMMTR_PRESERVE_AMBIGUOUS_OI`、
`SCUMMTR_KEEP_DANGLING_INDEX_ENTRIES`、`SCUMMTR_CJK_CUSTOM_CODESPACE`）。

### 驗收（正對照完整）

| 開關 | 00.LFL 差異 |
|---|---|
| 只有一代那三個 | 103 bytes |
| ＋ `PRESERVE_V1_ROOM_OFFSETS` | 4 bytes |
| ＋ `PRESERVE_DUP_INDEX_ENTRIES` | **0 bytes** |

**兩條產線的 round-trip 都是 byte-perfect**：v1 的 53 個 LFL 全過（抽出 1,121 行）、
《瘋狂時代》的 `TENTACLE.000/.001` 全過（抽出 6,647 行）。

## F7：SMUSH 字幕吃的是同一份 CJK 字型

`engines/scumm/nut_renderer.cpp`：

- `NutRenderer::getCharWidth/getCharHeight()` 對 `c >= 0x80 && _vm->_useCJKMode` 直接回
  `_vm->_2byteWidth + _spacing` / `_vm->_2byteHeight`；
- `NutRenderer::draw2byte()` 用同樣的兩個值決定繪製範圍。

所以片頭那段 SMUSH 動畫的字幕會跟著我們烘的字型走。字模從 12 變成 24 之後，
這是最需要盯的地方——SMUSH 影格的座標是遊戲原生解析度算出來的。

## 待驗

> **U1、U4、U7 已驗完，結論併入上面各節；U2/U3 由小樣實測收斂成具體的版面問題，見
> `50-status.md`。以下是還沒有結論的項目。**
>
> - **U1（已驗）**：`--detect` 回 `scumm:tentacle → Day of the Tentacle (CD/English)`，
>   v1 回 `scumm:maniac → Maniac Mansion (V1/DOS/English)`。偵測正常，不必處理。
>   （中文化後 md5 改變，會走 fallback 並印 `Your game version appears to be unknown`，
>   屬預期行為，發佈包用 ini 指定 gameid。）
> - **U4（已驗）**：指令列是**文字**，在 `[061:SCRP#0097]` 與 `#0123`，各 14 個字串——
>   Walk to／Give／Open／Close／Pick up／`L\xb0k at`／Talk to／Use／Push／`Pu\xb8`
>   ＋介系詞 in／with／on／to。其中 `0xB0`＝“oo”、`0xB8`＝“ll” 是原文自用的合字，
>   兩者都落在 CJK 碼空間 `0xA1–0xFD` 內；全檔只有這 7 處（另有 3 處 `0x82`/`0x90`
>   不在碼空間、無害），翻成中文後自然消失。v1 的原文完全沒有高位元組。
> - **U7（已驗）**：見 F6，本作是 16 bytes。

| # | 項目 | 驗證方式 |
|---|---|---|
| U2 | **倚天 24×24 hi-res 在 v6 上成不成立**。v2 的作法是 `_textSurfaceMultiplier=2` 加上補齊 `drawStripToScreen()` 的底圖 2× 放大；v6 的對應路徑、`CharsetRendererClassic`、SMUSH（F7）、verb 版面都是另一套 | 先讀 v6 的對應程式碼；小樣回填後截圖看底圖有無雪花、SMUSH 字幕有無爆框、對白有無超出畫面 |
| U3 | v6 的對白是畫在房間畫面上的浮動文字，字大一倍後長句的換行與置中 | 小樣長句實測；必要時在譯文端做像素級斷行 |
| U4 | 《瘋狂時代》的指令列是文字還是圖 | descumm 反編 verb script ＋ 實機截圖 |
| U5 | v1 是否吃一代那套碼空間；`loadCJKFont()` 的放行條件要放寬到 `version <= 2` | 抽 v1 文字後統計實際出現的位元組分布；小樣回填截圖 |
| U6 | v1 的畫面版面。一代為了 24×24 把畫布從 200 加高到 240（字幕帶 28 ＋ 房間 128 ＋ 指令區 84），v1 的 verb 區佈局與 v2 不同 | descumm 看 v1 的 `verbOps` 絕對座標；實機逐列量測 |
| U7 | 語音控制碼在本作的實際格式（F6 是另一款遊戲的實測） | 抽字後 grep 開頭的 `\255` 序列，統計長度分布 |
| U8 | `monster.sof`（FLAC）ScummVM 認不認、要不要改名 | 實機跑，看 log；建置時反查 `USE_FLAC = 1` |
| U9 | 存讀檔介面、F5 選單、MT-32 音色 | 實機 |

**驗證順序的取捨**：先讓《瘋狂時代》用 12×12 零修補跑通一次端到端，證明碼空間、抽字、回填、
字型偵測全都正確，再把字型換成倚天 24×24。這樣 U2 出問題時手上有一個「已知會動」的對照組，
而不是同時面對兩個未知。
