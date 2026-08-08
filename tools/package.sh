#!/bin/bash
# 打包成可散布的目錄包。在 docker 內跑，工作目錄 = repo 根目錄。
#
#   tools/package.sh linux full    含中文化後的遊戲資料（本機留存，不可公開）
#   tools/package.sh linux patch   只有引擎＋中文資料＋套用腳本（可公開）
#   tools/package.sh win   full|patch
#
# 產物一律進 ../dist-all/。
#
# 為什麼 patch 包要附「編碼後的整份譯文」而不是差異檔：中文化是把文字**回填進
# TENTACLE.001／*.LFL**，不是外掛檔案，所以玩家端一定要跑一次 scummtr。
# 附整份 enc 檔（未翻的行沿用原文）是唯一能讓 scummtr 逐行對位回填的形式。
set -euo pipefail

PLATFORM="${1:-linux}"
KIND="${2:-patch}"
W=..
STAMP=$(date +%Y%m%d)
OUT="$W/dist-all"
NAME="dott-cht-${PLATFORM}-${KIND}-${STAMP}"
D="$OUT/$NAME"

case "$PLATFORM" in
  # 散布用的是 scummvm-slim（--disable-all-engines --enable-engine=scumm，
  # 關掉 curl/fluidsynth/一堆 codec）：開發用那支完整配置的 ldd 有 100 條，
  # 塞進散布包等於要求玩家機器上樣樣齊全。slim 版剩 53 條，其中大半是 SDL2
  # 自己的 X11/wayland/pulse 相依，桌面環境本來就有。
  linux) BIN="$W/tools/scummvm-slim/scummvm"
         [ -f "$BIN" ] || BIN="$W/tools/scummvm-src/scummvm"
         BINNAME=scummvm
         TR="$W/tools/scummtr-src/build/bin/scummtr"; TRNAME=scummtr ;;
  win)   BIN="$W/tools/scummvm-win/scummvm.exe"; BINNAME=scummvm.exe
         TR="$W/tools/scummtr-win/build/bin/scummtr.exe"; TRNAME=scummtr.exe ;;
  *) echo "未知平台：$PLATFORM"; exit 2 ;;
esac

[ -f "$BIN" ] || { echo "找不到 $BIN，先編引擎"; exit 1; }

rm -rf "$D"; mkdir -p "$D/cht"
cp "$BIN" "$D/$BINNAME"

# Windows 版動態連結 SDL2，少了這支 DLL 會安靜地跳出（exit 53，畫面上什麼都沒有）。
# 其餘相依（GDI32/KERNEL32/SHELL32/USER32/WINMM/WINSPOOL/msvcrt/ole32）都是系統 DLL。
if [ "$PLATFORM" = win ]; then
    cp "$W/tools/scummvm-win/SDL2.dll" "$D/" 2>/dev/null || \
        echo "警告：找不到 SDL2.dll，Windows 版會跑不起來"
else
    # 把非系統的 .so 收進 lib/，啟動腳本再指 LD_LIBRARY_PATH。
    #
    # 只排除兩類：
    #   glibc 系列與 loader —— 跟系統的 ld.so 綁死，換版本必炸。
    #   libGL / libEGL / libGLX —— 跟顯示驅動綁死，帶自己的版本會跟 mesa/nvidia 打架。
    # X11 / xcb / wayland 那些**要收**：它們是純協議庫，不碰驅動，而且不是每台
    # 目標機器都齊全（第一版把它們排掉，在乾淨的 ubuntu 上就是
    # 「libX11.so.6: cannot open shared object file」）。
    mkdir -p "$D/lib"
    ldd "$BIN" | awk '/=> \//{print $3}' | sort -u | while read -r so; do
        case "$(basename "$so")" in
            libc.so.*|libm.so.*|libpthread.so.*|libdl.so.*|librt.so.*) continue ;;
            ld-linux*|libGL.so.*|libGLdispatch*|libGLX*|libEGL*) continue ;;
        esac
        cp -L "$so" "$D/lib/" 2>/dev/null || true
    done
    echo "自帶 $(ls "$D/lib" | wc -l) 支 .so"
fi

# ---- 中文資料：字型 ＋ 編碼後的譯文（兩條產線各一份）----
#
# 公開的 patch 包用 WQY Zen Hei Sharp 烘的字型（GPL + 字體例外，可散布）；
# full 包留本機，用倚天中文系統的原生點陣字（更清晰，但是商業字型的衍生物）。
# 兩份的字模尺寸與碼位完全相同，換檔就換字形，不必重編引擎也不必重新回填。
if [ "$KIND" = full ]; then FONTSFX=""; else FONTSFX="-wqy"; fi
cp "$W/dumps/dott${FONTSFX}.fnt"       "$D/cht/dott-chinese_gb16x12.fnt"
cp "$W/dumps/maniac-v1${FONTSFX}.fnt"  "$D/cht/maniac-chinese_gb16x12.fnt"
cp "$W/dumps/dott_enc.txt"       "$D/cht/dott_zh.txt"
cp "$W/dumps/maniac-v1_enc.txt"  "$D/cht/maniac_zh.txt"

if [ "$KIND" = full ]; then
    mkdir -p "$D/game/dott/maniac"
    cp "$W/game-cht/dott/"TENTACLE.00* "$D/game/dott/"
    cp "$W/game-cht/dott/chinese_gb16x12.fnt" "$D/game/dott/"
    # 指令列的華康少女體。與倚天同一條界線：商業字型的衍生物，只進 full 包。
    [ -f "$W/game-cht/dott/chinese_verb.fnt" ] &&
        cp "$W/game-cht/dott/chinese_verb.fnt" "$D/game/dott/" || true
    cp "$W/game-cht/dott/maniac/"*.LFL "$D/game/dott/maniac/"
    cp "$W/game-cht/dott/maniac/chinese_gb16x12.fnt" "$D/game/dott/maniac/"
    # monster.sof 有 95 MB，用連結而不是複製，避免 dist-all 爆掉
    ln -sf "$(cd "$W/game-orig/dott" && pwd)/monster.sof" "$D/game/dott/monster.sof"
    # 中文語音包（遊戲中 Ctrl+T 循環切換）。有才連，沒有就只有原音英文。
    # 這兩個檔只進 full 包，patch 包（公開）不含任何語音資料。
    for v in tw cl; do
        if [ -f "$W/game-cht/dott/monster-$v.sof" ]; then
            ln -sf "$(cd "$W/game-cht/dott" && pwd)/monster-$v.sof" "$D/game/dott/monster-$v.sof"
        fi
    done
    # MT-32 音源。binary 已經編進 mt32emu，但那只是模擬器；要真出聲還得有 ROM。
    # ROM 是 Roland 的著作，只進留本機的 full 包，公開的 patch 包一個位元組都沒有。
    if [ -f "$W/mt32rom/MT32_CONTROL.ROM" ] && [ -f "$W/mt32rom/MT32_PCM.ROM" ]; then
        mkdir -p "$D/mt32rom"
        cp "$W/mt32rom/MT32_CONTROL.ROM" "$W/mt32rom/MT32_PCM.ROM" "$D/mt32rom/"
        MT32=1
    else
        echo "警告：找不到 MT-32 ROM，full 包會用 AdLib"
        MT32=0
    fi
else
    [ -f "$TR" ] && cp "$TR" "$D/$TRNAME" || echo "警告：找不到 $TR，patch 包沒有回填工具"
    MT32=0
fi

# ---- ScummVM 設定 ----
sed -e 's|\./game/dott|./game/dott|' dist/scummvm-zhtw.ini.sample > "$D/scummvm.ini"

# 有 ROM 才設 mt32 —— 沒 ROM 卻指定 mt32，ScummVM 會先彈一個阻擋對話框才回退 AdLib。
# 只設在 dott-zh：一代（SCUMM v1 DOS）在偵測表裡是 MDT_PCSPK|MDT_PCJR 且帶 GUIO_NOMIDI，
# 根本沒有 MIDI 這條路。
if [ "$MT32" = 1 ]; then
    awk '
      /^\[scummvm\]$/ { print; print "extrapath=./mt32rom"; next }
      /^\[dott-zh\]$/ { print; print "music_driver=mt32"; next }
      { print }
    ' "$D/scummvm.ini" > "$D/scummvm.ini.tmp" && mv "$D/scummvm.ini.tmp" "$D/scummvm.ini"
    grep -q '^music_driver=mt32$' "$D/scummvm.ini" || { echo "ini 沒寫進 mt32"; exit 1; }
fi

# ---- 啟動與套用腳本 ----
if [ "$PLATFORM" = linux ]; then
    cat > "$D/執行遊戲.sh" <<'SH'
#!/bin/sh
cd "$(dirname "$0")"
# lib/ 裡是這包自帶的 .so（SDL2、FLAC 等）；放在系統路徑之後，
# 系統上已有較新版本時優先用系統的。
LD_LIBRARY_PATH="${LD_LIBRARY_PATH:+$LD_LIBRARY_PATH:}$(pwd)/lib" \
  ./scummvm --config=./scummvm.ini dott-zh
SH
    chmod +x "$D/執行遊戲.sh"
    if [ "$KIND" = patch ]; then
        cat > "$D/套用中文化.sh" <<'SH'
#!/bin/sh
# 用法：套用中文化.sh <原版 DOTT 資料夾>
#
# 會做的事（不會動到你的原版，全部複製到 ./game/ 之後才改）：
#   1. 複製 TENTACLE.000/001 與 monster.sof
#   2. 用 scummtr 把中文譯文回填進 TENTACLE.001
#   3. 放中文字型
#   4. 對 MANIAC/ 底下的一代做同樣的事
set -e
[ $# -eq 1 ] || { echo "用法：$0 <原版 DOTT 資料夾>"; exit 1; }
SRC=$1
HERE=$(cd "$(dirname "$0")" && pwd)
cd "$HERE"

[ -f "$SRC/TENTACLE.001" ] || [ -f "$SRC/tentacle.001" ] || {
    echo "在 $SRC 找不到 TENTACLE.001"; exit 1; }

mkdir -p game/dott/maniac
cp "$SRC"/[Tt][Ee][Nn][Tt][Aa][Cc][Ll][Ee].00* game/dott/
[ -f "$SRC/monster.sof" ] && cp "$SRC/monster.sof" game/dott/ || \
    echo "（沒有 monster.sof，遊戲會沒有語音，字幕照常）"

echo "== 回填瘋狂時代 =="
cp cht/dott_zh.txt game/dott/scummtr.txt
( cd game/dott && "$HERE/scummtr" -g tentacle -r -w -if )
rm -f game/dott/scummtr.txt game/dott/*scummio-tmp
cp cht/dott-chinese_gb16x12.fnt game/dott/chinese_gb16x12.fnt

# 一代的 LFL 在原版光碟的 MANIAC 子資料夾
MAN=""
for c in "$SRC/MANIAC" "$SRC/maniac" "$SRC/Maniac"; do [ -d "$c" ] && MAN=$c; done
if [ -n "$MAN" ]; then
    echo "== 回填泰德電腦裡的一代 =="
    cp "$MAN"/*.[Ll][Ff][Ll] game/dott/maniac/
    cp cht/maniac_zh.txt game/dott/maniac/scummtr.txt
    ( cd game/dott/maniac && "$HERE/scummtr" -g maniacv1 -r -w -if )
    rm -f game/dott/maniac/scummtr.txt game/dott/maniac/*scummio-tmp
    cp cht/maniac-chinese_gb16x12.fnt game/dott/maniac/chinese_gb16x12.fnt
else
    echo "（沒找到 MANIAC 資料夾，泰德的電腦會是英文的）"
fi

echo
echo "完成。執行 ./執行遊戲.sh 開始玩。"
SH
        chmod +x "$D/套用中文化.sh"
    fi
else
    cat > "$D/執行遊戲.bat" <<'BAT'
@echo off
cd /d "%~dp0"
scummvm.exe --config=.\scummvm.ini dott-zh
BAT
    if [ "$KIND" = patch ]; then
        cat > "$D/套用中文化.bat" <<'BAT'
@echo off
rem 用法：把原版 DOTT 資料夾拖到這個檔案上，或 套用中文化.bat "D:\DOTT"
setlocal
cd /d "%~dp0"
if "%~1"=="" ( echo 用法：套用中文化.bat ^<原版 DOTT 資料夾^> & pause & exit /b 1 )
set SRC=%~1

if not exist "%SRC%\TENTACLE.001" if not exist "%SRC%\tentacle.001" (
    echo 在 %SRC% 找不到 TENTACLE.001 & pause & exit /b 1 )

mkdir game\dott\maniac 2>nul
copy /y "%SRC%\TENTACLE.00*" game\dott\ >nul
if exist "%SRC%\monster.sof" copy /y "%SRC%\monster.sof" game\dott\ >nul

echo == 回填瘋狂時代 ==
copy /y cht\dott_zh.txt game\dott\scummtr.txt >nul
pushd game\dott & "%~dp0scummtr.exe" -g tentacle -r -w -if & popd
del game\dott\scummtr.txt game\dott\*scummio-tmp 2>nul
copy /y cht\dott-chinese_gb16x12.fnt game\dott\chinese_gb16x12.fnt >nul

if exist "%SRC%\MANIAC" (
    echo == 回填泰德電腦裡的一代 ==
    copy /y "%SRC%\MANIAC\*.LFL" game\dott\maniac\ >nul
    copy /y cht\maniac_zh.txt game\dott\maniac\scummtr.txt >nul
    pushd game\dott\maniac & "%~dp0scummtr.exe" -g maniacv1 -r -w -if & popd
    del game\dott\maniac\scummtr.txt game\dott\maniac\*scummio-tmp 2>nul
    copy /y cht\maniac-chinese_gb16x12.fnt game\dott\maniac\chinese_gb16x12.fnt >nul
) else (
    echo （沒找到 MANIAC 資料夾，泰德的電腦會是英文的）
)
echo.
echo 完成。執行 執行遊戲.bat 開始玩。
pause
BAT
    fi
fi

cp README-dist.md "$D/README.txt" 2>/dev/null || true

# ---- 壓縮 ----
# full 包裡的 monster.sof 是符號連結（95 MB，不重複複製），tar 要 -h 解引用；
# 沒有 -h 的話玩家端解出來會是一條指向本機路徑的死連結。
( cd "$OUT" && rm -f "$NAME.tar.zst" "$NAME.zip" && case "$PLATFORM" in
    linux) tar chf - "$NAME" | zstd -19 -T0 -q -o "$NAME.tar.zst" ;;
    win)   zip -qr9 "$NAME.zip" "$NAME" ;;
  esac )

echo "=== $D ==="
du -sh "$D"
ls -la "$OUT/$NAME".{tar.zst,zip} 2>/dev/null | sed "s|$OUT/||"
find "$D" -maxdepth 2 -type f | sed "s|$D/||" | sort | head -20
