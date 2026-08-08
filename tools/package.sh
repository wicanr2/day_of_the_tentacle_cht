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
  linux) BIN="$W/tools/scummvm-src/scummvm";     BINNAME=scummvm
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
    cp "$W/tools/scummvm-win/SDL2.dll" "$D/" 2>/dev/null ||         echo "警告：找不到 SDL2.dll，Windows 版會跑不起來"
fi

# ---- 中文資料：字型 ＋ 編碼後的譯文（兩條產線各一份）----
cp "$W/dumps/dott.fnt"       "$D/cht/dott-chinese_gb16x12.fnt"
cp "$W/dumps/maniac-v1.fnt"  "$D/cht/maniac-chinese_gb16x12.fnt"
cp "$W/dumps/dott_enc.txt"       "$D/cht/dott_zh.txt"
cp "$W/dumps/maniac-v1_enc.txt"  "$D/cht/maniac_zh.txt"

if [ "$KIND" = full ]; then
    mkdir -p "$D/game/dott/maniac"
    cp "$W/game-cht/dott/"TENTACLE.00* "$D/game/dott/"
    cp "$W/game-cht/dott/chinese_gb16x12.fnt" "$D/game/dott/"
    cp "$W/game-cht/dott/maniac/"*.LFL "$D/game/dott/maniac/"
    cp "$W/game-cht/dott/maniac/chinese_gb16x12.fnt" "$D/game/dott/maniac/"
    # monster.sof 有 95 MB，用連結而不是複製，避免 dist-all 爆掉
    ln -sf "$(cd "$W/game-orig/dott" && pwd)/monster.sof" "$D/game/dott/monster.sof"
else
    [ -f "$TR" ] && cp "$TR" "$D/$TRNAME" || echo "警告：找不到 $TR，patch 包沒有回填工具"
fi

# ---- ScummVM 設定 ----
sed -e 's|\./game/dott|./game/dott|' dist/scummvm-zhtw.ini.sample > "$D/scummvm.ini"

# ---- 啟動與套用腳本 ----
if [ "$PLATFORM" = linux ]; then
    cat > "$D/執行遊戲.sh" <<'SH'
#!/bin/sh
cd "$(dirname "$0")"
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
( cd "$OUT" && case "$PLATFORM" in
    linux) tar chf - "$NAME" | zstd -19 -T0 -q -o "$NAME.tar.zst" ;;
    win)   zip -qr9 "$NAME.zip" "$NAME" ;;
  esac )

echo "=== $D ==="
du -sh "$D"
ls -la "$OUT/$NAME".{tar.zst,zip} 2>/dev/null | sed "s|$OUT/||"
find "$D" -maxdepth 2 -type f | sed "s|$D/||" | sort | head -20
