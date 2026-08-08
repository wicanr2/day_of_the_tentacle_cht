# 從零重建

所有步驟都在 docker 內跑，不污染本機。工作目錄結構：

```
workplace/
  day_of_the_tentacle_cht/   ← 這個 repo
  docker/                    Dockerfile、Dockerfile.mingw
  game-orig/dott/            原版資料（TENTACLE.00*、monster.sof）
  game-orig/maniac-v1/       原版一代（54 個 .LFL）
  game-cht/                  產出的中文版資料
  dumps/                     抽字、編碼、字型的中間檔
  font-src/                  倚天點陣字（商業字型，不入 repo）
  tools/scummvm-src/         ScummVM 原始碼（已套 patch）
  tools/scummvm-win/         Windows 交叉編譯用的另一棵樹
  tools/scummtr-src/         ScummTR 原始碼（已套 patch）
  dist-all/                  打包產物
```

## 1. 兩個 docker image

```bash
docker build -f docker/Dockerfile      -t dott-cht:latest .   # Linux 開發／驗證
docker build -f docker/Dockerfile.mingw -t dott-cht:mingw  .   # Windows 交叉編譯
```

mingw 那個會自己編 libogg / libFLAC / zlib 的 mingw 版。**libFLAC 不能省**：
DOTT 的語音包 `monster.sof` 是 FLAC 壓縮，沒有 `USE_FLAC` 的話 ScummVM 讀不出來，
而且**不會報錯**，只是整片語音消失。

## 2. ScummVM

```bash
git clone https://github.com/scummvm/scummvm tools/scummvm-src
cd tools/scummvm-src && git checkout e37bbe20
patch -p1 < ../../day_of_the_tentacle_cht/patches/scummvm-zhtw.patch
./configure --disable-all-engines --enable-engine=scumm && make -j
```

## 3. ScummTR

```bash
git clone https://github.com/dwatteau/scummtr tools/scummtr-src
cd tools/scummtr-src
patch -p1 < ../../day_of_the_tentacle_cht/patches/scummtr-maniacv1-lossless.patch
mkdir build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release -DCMAKE_CXX_FLAGS="\
  -DSCUMMTR_PRESERVE_AMBIGUOUS_OI \
  -DSCUMMTR_KEEP_DANGLING_INDEX_ENTRIES \
  -DSCUMMTR_CJK_CUSTOM_CODESPACE \
  -DSCUMMTR_PRESERVE_V1_ROOM_OFFSETS \
  -DSCUMMTR_PRESERVE_DUP_INDEX_ENTRIES \
  -DSCUMMRP_OK_TO_CORRUPT_MANIACV2"
make -j
```

六個開關少一個都會出事，理由見 [`00-engine-verification.md`](00-engine-verification.md) 的 F8、F9。

## 4. 抽字（只有第一次要做）

```bash
scummtr -g tentacle -r -w -of dumps/dott_raw.txt     # 在 game-orig/dott 下
scummtr -g maniacv1 -r -w -of dumps/v1_raw.txt       # 在 game-orig/maniac-v1 下
python3 tools/make_batches.py dumps/dott_raw.txt -o translations/dott --size 120
```

帶 `-h` 再抽一份（`dumps/*_ctx.txt`）給 `lint_translation.py` 判斷區塊類型用。

**動文字之前先做 round-trip**：原封抽出、原封回填、逐檔 byte 比對，差 0 才往下走。

## 5. 建中文版資料

```bash
tools/build_cht.sh dott        # 瘋狂時代
tools/build_cht.sh maniac-v1   # 泰德電腦裡的一代
```

一支腳本走完「檢查格式 → 合併譯文 → 蒐集字集產碼表 → 編碼 → 烘字型 → 回填」。
兩條產線的碼空間與字模不同，靠 `CHT_PROFILE` 環境變數切換（腳本自己設）。

## 6. 檢查

```bash
python3 tools/check_batches.py translations/dott/*.tsv          # 會出事的格式問題
python3 tools/lint_translation.py --ctx dumps/dott_ctx.txt \
        translations/dott/*.tsv                                  # 讀起來不對的問題
```

回填後的 round-trip 驗證（抽回來跟送進去的比）：

```
送入行數 6648  抽回行數 6648   不一致 0
回填後中文字數 56048   孤兒高位元組 0
```

「孤兒高位元組 = 0」是不會有字元級亂碼的證明。

## 7. 打包

```bash
tools/package.sh linux patch    # 可公開：引擎＋中文資料＋套用腳本
tools/package.sh linux full     # 本機留存：含中文化後的遊戲資料
tools/package.sh win   patch
tools/package.sh win   full
```

產物進 `dist-all/`。**full 包含遊戲資料，不可公開散布。**

Windows 版的引擎另外編：

```bash
docker run --rm -v "$PWD":/w -w /w dott-cht:mingw bash tools/build-win.sh
```

### 交叉編譯踩過的三個雷

1. **複製源碼樹的排除規則要錨定根目錄。** 原本用 `tar --exclude=config.h`，
   tar 會比對路徑的任何一段，於是 `audio/softsynth/mt32/config.h` 也被排掉——
   那支帶著 `MT32EMU_VERSION_MAJOR` 等巨集，缺了它 `Synth.cpp` 編不過。
   正解是 `--anchored --exclude='./config.h'`（`--anchored` 讓 pattern 從路徑
   開頭比對），之後要恢復預設語意再加 `--no-anchored`。腳本裡跟著加了一行正對照：
   複製完檢查 `mt32/config.h` 在不在，不在就直接停。
2. **`make` 後面不要接 `| tail -N`。** 上面那個錯誤第一次出現時，畫面上只剩
   `make: *** [Makefile.common:177] Error 1`，完整的 `error:` 全被過濾器吃掉，
   看起來像無從查起。把管線拿掉重跑，三行就看到根因。
3. **Windows 版要一起帶 `SDL2.dll`。** 引擎是動態連結 SDL2，少了那支 DLL
   `scummvm.exe` 會**安靜地跳出**（exit 53，畫面上什麼都不印）。其餘相依
   （GDI32／KERNEL32／SHELL32／USER32／WINMM／WINSPOOL／msvcrt／ole32）都是系統 DLL。
   查法：`x86_64-w64-mingw32-objdump -p scummvm.exe | grep "DLL Name"`。

## 8. 實機驗證（headless）

```bash
Xvfb :99 -screen 0 640x480x24 &
DISPLAY=:99 scummvm --config=/tmp/svm.ini dott-zh &
import -window root shot.png
```

設定檔要點見 [`../dist/scummvm-zhtw.ini.sample`](../dist/scummvm-zhtw.ini.sample)。
那份範本裡的三個雷都是實際踩過才寫進去的：

1. **註解只能用 `#`，不能用 `;`。** ScummVM 的 `loadFromStream` 只認 `#`；
   遇到 `;` 開頭的行會判定檔案有問題而**整份丟掉**，症狀是啟動時說
   `Unrecognized game 'dott-zh'`，看起來像 target 名字打錯。
2. **`easter_egg` 要明確指定 target 名。** 不寫的話走路徑搜尋，同一份 LFL 同時
   符合 C64／V1 DOS／NES，auto-detect 挑到 C64 就是 assertion 中止。
3. **兩個 target 都不要寫 `language`。** ScummVM 看到 `chinese_gb16x12.fnt`
   自己會判 ZH_CHN；手寫 `language=zh` 反而變成別的中文變體，不載字型、整片亂碼。

## 9. 端到端驗收

打完包要走一次玩家的路徑，不能只看包裡有哪些檔：

```bash
cp -r dist-all/dott-cht-linux-patch-* /tmp/e2e && cd /tmp/e2e
./套用中文化.sh /path/to/原版          # 回填
./執行遊戲.sh                          # 啟動
```

驗收點：回填後的 `TENTACLE.001` 裡數得出中文字組（首碼 0xA1–0xF7 接尾碼
0xA1–0xFD）、`maniac/01.LFL` 也數得出（首碼 0x88–0x9F），而且遊戲真的進得去。
`Unrecognized game` 那個雷就是在這一步抓到的——只看包內容永遠看不出來。

## 10. macOS

Linux 端做不出 `.app`（需要 `codesign` / `lipo`），所以走 GitHub Actions 的
macos runner：

```bash
gh workflow run build-mac.yml
gh run watch
gh run download <id> -n dott-cht-macos
```

CI 只出 **engine-only 的 `.app`**——倚天字型衍生物與夾帶英文原文的譯文檔都不上 CI，
中文資料在本機注入之後才成為完整的包。
