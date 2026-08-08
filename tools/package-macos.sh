#!/bin/bash
# 把 CI 產出的 engine-only .app 注入中文資料，打成可交付的 tar.gz。
#
#   tools/package-macos.sh <CI 下載的 dott-cht-macos-app.tar.gz> [patch|full]
#
# 為什麼要分兩步：.app 只能在 macOS host 上組（codesign / lipo），而 CI 拿不到
# 遊戲資料，也不該拿到倚天字型衍生物。所以 CI 只出引擎，中文資料在本機注入。
#
# [雷] 改動已簽名的 .app 之後簽章就失效。這裡直接把 _CodeSignature 移除
#      （「未簽」勝過「壞簽」），並在 README 附上重簽指令。
set -euo pipefail

SRC="${1:?用法: package-macos.sh <CI 下載的 tar.gz> [patch|full]}"
KIND="${2:-patch}"
W=..
STAMP=$(date +%Y%m%d)
OUT="$W/dist-all"
NAME="dott-cht-macos-${KIND}-${STAMP}"
D="$OUT/$NAME"

rm -rf "$D"; mkdir -p "$D"
tar xzf "$SRC" -C "$D"
APP="$D/ScummVM.app"
[ -d "$APP" ] || { echo "解開後沒有 ScummVM.app"; exit 1; }

RES="$APP/Contents/Resources"
mkdir -p "$D/cht"

# CI 把 ScummVM 樹裡的 engine-data 整批複製進 .app，其中大半是別的引擎在用的
# （ultima.dat 15 MB、titanic.dat 3 MB、kyra.dat 2 MB…），而這支 binary 只編了
# SCUMM，永遠不會去讀它們。fonts-cjk.dat 有 37 MB，是 GUI 中文介面用的；
# 本包的 GUI 維持英文（三平台一致），所以也一併拿掉。
# 留下的是 SCUMM 真的會碰的：GUI 預設字型、Mac 版 SCUMM 遊戲的字型、主題 zip。
find "$RES" -maxdepth 1 -name '*.dat' \
     ! -name 'fonts.dat' ! -name 'classicmacfonts.dat' -delete
echo "Resources 精簡後：$(du -sh "$RES" | cut -f1)"

# 字型：full 用倚天（本機），patch 用 WQY（可散布）——與 package.sh 同一條界線
if [ "$KIND" = full ]; then FONTSFX=""; else FONTSFX="-wqy"; fi
cp "$W/dumps/dott${FONTSFX}.fnt"      "$D/cht/dott-chinese_gb16x12.fnt"
cp "$W/dumps/maniac-v1${FONTSFX}.fnt" "$D/cht/maniac-chinese_gb16x12.fnt"
cp "$W/dumps/dott_enc.txt"      "$D/cht/dott_zh.txt"
cp "$W/dumps/maniac-v1_enc.txt" "$D/cht/maniac_zh.txt"

if [ "$KIND" = full ]; then
    mkdir -p "$D/game/dott/maniac"
    cp "$W/game-cht/dott/"TENTACLE.00* "$D/game/dott/"
    cp "$W/game-cht/dott/chinese_gb16x12.fnt" "$D/game/dott/"
    # 指令列的華康少女體。與倚天同一條界線：商業字型的衍生物，只進 full 包。
    [ -f "$W/game-cht/dott/chinese_verb.fnt" ] &&
        cp "$W/game-cht/dott/chinese_verb.fnt" "$D/game/dott/" || true
    [ -f "$W/game-cht/dott/chinese_dialog.fnt" ] &&
        cp "$W/game-cht/dott/chinese_dialog.fnt" "$D/game/dott/" || true
    cp "$W/game-cht/dott/maniac/"*.LFL "$D/game/dott/maniac/"
    cp "$W/game-cht/dott/maniac/chinese_gb16x12.fnt" "$D/game/dott/maniac/"
    ln -sf "$(cd "$W/game-orig/dott" && pwd)/monster.sof" "$D/game/dott/monster.sof"
    # 中文語音包（遊戲中 Ctrl+T 循環切換），與 package.sh 同一條界線：只進 full 包
    for v in tw cl; do
        if [ -f "$W/game-cht/dott/monster-$v.sof" ]; then
            ln -sf "$(cd "$W/game-cht/dott" && pwd)/monster-$v.sof" "$D/game/dott/monster-$v.sof"
        fi
    done
    # MT-32 ROM，與 package.sh 同一條界線：只進 full 包
    if [ -f "$W/mt32rom/MT32_CONTROL.ROM" ] && [ -f "$W/mt32rom/MT32_PCM.ROM" ]; then
        mkdir -p "$D/mt32rom"
        cp "$W/mt32rom/MT32_CONTROL.ROM" "$W/mt32rom/MT32_PCM.ROM" "$D/mt32rom/"
        MT32=1
    else
        echo "警告：找不到 MT-32 ROM，full 包會用 AdLib"
        MT32=0
    fi
else
    MT32=0
    # scummtr 的 macOS 版由同一個 CI 產出（tools/build-mac.sh 一併編）
    if [ -f "$D/scummtr" ]; then chmod +x "$D/scummtr"; else
        echo "警告：CI 產物裡沒有 macOS 版 scummtr，patch 包無法在玩家端回填"
    fi
fi

cp dist/scummvm-zhtw.ini.sample "$D/scummvm.ini"
if [ "$MT32" = 1 ]; then
    awk '
      /^\[scummvm\]$/ { print; print "extrapath=./mt32rom"; next }
      /^\[dott-zh\]$/ { print; print "music_driver=mt32"; next }
      { print }
    ' "$D/scummvm.ini" > "$D/scummvm.ini.tmp" && mv "$D/scummvm.ini.tmp" "$D/scummvm.ini"
    grep -q '^music_driver=mt32$' "$D/scummvm.ini" || { echo "ini 沒寫進 mt32"; exit 1; }
fi
cp README-dist.md "$D/README.txt"

cat > "$D/套用中文化.command" <<'SH'
#!/bin/sh
# 用法：把原版 DOTT 資料夾拖進終端機接在這個檔案後面，或直接雙擊再輸入路徑。
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
cd "$HERE"
SRC=${1:-}
if [ -z "$SRC" ]; then printf "原版 DOTT 資料夾路徑："; read -r SRC; fi
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
echo "完成。雙擊 ScummVM.app 開始玩。"
SH
chmod +x "$D/套用中文化.command"

# .app 內建一個啟動 wrapper，讓它讀包裡的 scummvm.ini 與 game/
BIN="$APP/Contents/MacOS/scummvm"
mv "$BIN" "$APP/Contents/MacOS/scummvm.bin"
cat > "$BIN" <<'SH'
#!/bin/sh
# 包的根目錄在 .app 的上兩層（ScummVM.app/Contents/MacOS/ → ../../..）
D=$(cd "$(dirname "$0")/../../.." && pwd)
exec "$(dirname "$0")/scummvm.bin" --config="$D/scummvm.ini" dott-zh
SH
chmod +x "$BIN"

# 改過 .app 之後原本的簽章就失效了；留著壞簽比沒簽更麻煩（Gatekeeper 直接擋）
rm -rf "$APP/Contents/_CodeSignature"

( cd "$OUT" && rm -f "$NAME.tar.gz" && tar czhf "$NAME.tar.gz" "$NAME" )
echo "=== $D ==="
du -sh "$D"
ls -la "$OUT/$NAME.tar.gz"
