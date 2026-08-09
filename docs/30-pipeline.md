# 從零重建

所有步驟都在 docker 內跑，不污染本機。工作目錄結構：

```
workplace/
  day_of_the_tentacle_cht/   ← 這個 repo
  docker/                    Dockerfile、Dockerfile.mingw、Dockerfile.osxcross
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
docker build -f docker/Dockerfile        -t dott-cht:latest   .   # Linux 開發／驗證
docker build -f docker/Dockerfile.mingw   -t dott-cht:mingw    .   # Windows 交叉編譯
docker build -f docker/Dockerfile.osxcross -t dott-cht:osxcross docker/   # macOS 交叉編譯
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

### Linux 包的可攜性

散布用的引擎是另編的 **slim** 版（`--disable-all-engines --enable-engine=scumm`，
關掉 curl/fluidsynth 與一堆 codec）：開發用那支完整配置 `ldd` 有 100 條，
塞進散布包等於要求玩家機器樣樣齊全；slim 剩 53 條。

其中 49 支 `.so` 收進包裡的 `lib/`，啟動腳本用 `LD_LIBRARY_PATH` 指過去。
只有兩類不收：

* **glibc 系列與 loader**（`libc`/`libm`/`libpthread`/`libdl`/`librt`/`ld-linux`）——
  跟系統的 `ld.so` 綁死，換版本必炸。
* **`libGL` / `libEGL` / `libGLX`** —— 跟顯示驅動綁死，帶自己的版本會跟 mesa/nvidia 打架。

X11、xcb、wayland 那些**要收**：它們是純協議庫，不碰驅動，而且不是每台機器都齊全。
第一版把它們一起排掉，在乾淨的 `ubuntu:24.04` 上就是
`libX11.so.6: cannot open shared object file`。

驗收方式是拿一個**沒裝過任何相依**的 image 跑：

```bash
docker run --rm -v "$PWD/dist-all":/d:ro ubuntu:24.04 bash -c '
  cd /tmp && cp -r /d/dott-cht-linux-patch-* p && cd p
  LD_LIBRARY_PATH=/tmp/p/lib ./scummvm --version'
```

要看到 `Features compiled in: FLAC ...`——FLAC 在，`monster.sof` 才讀得出來。

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

### 字型有兩份

`build_cht.sh` 一次烘兩份，字模尺寸與碼位完全相同，差別只在字形來源：

| 檔案 | 來源 | 用途 |
|---|---|---|
| `dumps/<產線>.fnt` | 倚天中文系統的原生點陣字 | 最清晰，但是商業字型的衍生物，**只進 full 包（本機）** |
| `dumps/<產線>-wqy.fnt` | WenQuanYi Zen Hei Sharp 的 embedded bitmap strike | GPL + 字體例外，**跟公開的 patch 包一起散布** |

WQY Zen Hei Sharp（`.ttc` 的 face index 2）帶 12/13/14/15/16 px 五個 embedded
bitmap strike，是設計師手繪的點陣，不是把 outline 描下來的——所以 16×14／16×15
兩種字模都有對得上的 strike。品質略遜倚天（筆畫較細，加粗後可讀），但這是可以
公開散布的版本。`package.sh` 依 `full`／`patch` 自動選，不必手動換檔。

## 10. macOS

兩條路，產出的 `.app` 一樣，都只含引擎——倚天字型衍生物與夾帶英文原文的譯文檔
都不進去，中文資料在本機注入之後才成為完整的包。

**本機交叉編（不需要 Mac，也不需要 CI 額度）**

```bash
mkdir -p macbuild && cd macbuild
git clone --no-hardlinks ../tools/scummvm-src scummvm    # 乾淨樹
( cd scummvm && git apply ../../day_of_the_tentacle_cht/patches/scummvm-zhtw.patch )
git clone --no-hardlinks ../tools/scummtr-src scummtr
( cd scummtr && git apply ../../day_of_the_tentacle_cht/patches/scummtr-maniacv1-lossless.patch )
cd .. && docker run --rm -v "$PWD/macbuild":/b -w /b -e JOBS=6 dott-cht:osxcross \
  bash /b/build-mac-osxcross.sh
```

`tools/build-mac-osxcross.sh` 會把 SDL2 / libogg / libFLAC / ScummVM / ScummTR
各編兩弧（arm64 + x86_64）再 `lipo` 合成，然後組 `.app`。arm64 的 ad-hoc 簽章由
ld64 在連結時加上——**沒有它，Apple Silicon 會直接把執行檔殺掉（`Killed: 9`）**，
而在 Linux 這端完全看不出異狀，所以腳本裡有一道守門檢查 `LC_CODE_SIGNATURE`。

bundle 層的 `codesign` 在 Linux 上做不出來，但 `package-macos.sh` 本來就會把
`_CodeSignature` 拔掉（「未簽」勝過「壞簽」），所以兩條路的最終產物一致。

**GitHub Actions（有額度時比較省事，而且能簽 bundle）**

```bash
gh workflow run build-mac.yml
gh run watch
gh run download <id> -n dott-cht-macos
```

`tools/build-mac.sh`（CI 原生版）與 `tools/build-mac-osxcross.sh`（交叉編版）的
configure 開關必須逐項對齊，**改一邊就要改另一邊**，否則兩條路的產物會悄悄不同。

**收工前驗**（Linux 上執行不了 macOS binary，只能靜態檢查）：

```bash
docker run --rm -v "$PWD":/w -w /w dott-cht:osxcross \
  bash /w/day_of_the_tentacle_cht/tools/verify-mac-binary.sh /w/macbuild/dist-ci/ScummVM.app
```

查的是雙弧、arm64 有簽章、最低系統版本、動態相依有沒有指到編譯機才有的路徑。
全過只代表不會因結構問題開不起來，**實際遊玩仍需要一台 Mac**。
