#!/bin/bash
# 把 full 包做成單檔 AppImage（本機留存，含遊戲資料與語音，不可公開散布）。
#
#   tools/build-appimage.sh [appimagetool 路徑]
#
# 在 docker 內跑，工作目錄 = repo 根目錄。
#
# [雷] appimagetool 本身就是一個 AppImage，容器裡沒有 FUSE 會直接死在
#      「No suitable fusermount binary found on the $PATH」。設
#      APPIMAGE_EXTRACT_AND_RUN=1 讓它先自解到暫存目錄再執行，就不需要 FUSE。
#
# 為什麼 AppRun 要每次改寫 ini 的路徑：AppImage 每次執行的掛載點都不同
# （/tmp/.mount_XXXXXX），寫死的絕對路徑下次就失效。但設定檔要能保留玩家自己
# 的選擇（語音包、音量、存檔），所以不是整份重寫，而是只改「由掛載點推導出來」
# 的那幾行。
set -euo pipefail

TOOL="${1:-/tmp/appimagetool}"
W=..
STAMP=$(date +%Y%m%d)
OUT="$W/dist-all"
APPDIR="$OUT/DOTT-CHT.AppDir"
BIN="$W/tools/scummvm-slim/scummvm"
[ -f "$BIN" ] || BIN="$W/tools/scummvm-src/scummvm"
[ -f "$BIN" ] || { echo "找不到 scummvm binary"; exit 1; }
[ -x "$TOOL" ] || { echo "找不到可執行的 appimagetool：$TOOL"; exit 1; }

rm -rf "$APPDIR"
mkdir -p "$APPDIR/usr/bin" "$APPDIR/usr/lib" "$APPDIR/usr/share/game/dott/maniac" \
         "$APPDIR/usr/share/mt32rom" "$APPDIR/usr/share/icons/hicolor/256x256/apps"

cp "$BIN" "$APPDIR/usr/bin/scummvm"

# 相依 .so：排除 glibc 系列（跟系統 ld.so 綁死）與 GL（跟顯示驅動綁死）。
# X11/xcb/wayland 要收——純協議庫，而且不是每台機器都齊全。
ldd "$BIN" | awk '/=> \//{print $3}' | sort -u | while read -r so; do
    case "$(basename "$so")" in
        libc.so.*|libm.so.*|libpthread.so.*|libdl.so.*|librt.so.*) continue ;;
        ld-linux*|libGL.so.*|libGLdispatch*|libGLX*|libEGL*) continue ;;
    esac
    cp -L "$so" "$APPDIR/usr/lib/" 2>/dev/null || true
done
echo "自帶 $(ls "$APPDIR/usr/lib" | wc -l) 支 .so"

# ---- 遊戲資料（中文化後）----
cp "$W/game-cht/dott/"TENTACLE.00*            "$APPDIR/usr/share/game/dott/"
cp "$W/game-cht/dott/chinese_gb16x12.fnt"     "$APPDIR/usr/share/game/dott/"
[ -f "$W/game-cht/dott/chinese_verb.fnt" ] &&
    cp "$W/game-cht/dott/chinese_verb.fnt"    "$APPDIR/usr/share/game/dott/" || true
cp "$W/game-cht/dott/maniac/"*.LFL            "$APPDIR/usr/share/game/dott/maniac/"
cp "$W/game-cht/dott/maniac/chinese_gb16x12.fnt" "$APPDIR/usr/share/game/dott/maniac/"
# [重要] 這裡要複製實體檔，不能像目錄包那樣用符號連結——AppImage 打包成 squashfs
# 之後，指向本機路徑的連結在別台機器上就是死連結。
cp -L "$W/game-orig/dott/monster.sof"         "$APPDIR/usr/share/game/dott/"
for v in tw cl; do
    [ -f "$W/game-cht/dott/monster-$v.sof" ] &&
        cp -L "$W/game-cht/dott/monster-$v.sof" "$APPDIR/usr/share/game/dott/" || true
done

# ---- MT-32 ROM ----
if [ -f "$W/mt32rom/MT32_CONTROL.ROM" ] && [ -f "$W/mt32rom/MT32_PCM.ROM" ]; then
    cp "$W/mt32rom/MT32_CONTROL.ROM" "$W/mt32rom/MT32_PCM.ROM" "$APPDIR/usr/share/mt32rom/"
    MT32=1
else
    echo "警告：找不到 MT-32 ROM"; MT32=0
fi

# ---- 設定檔範本 ----
cp dist/scummvm-zhtw.ini.sample "$APPDIR/usr/share/scummvm.ini"
if [ "$MT32" = 1 ]; then
    awk '
      /^\[scummvm\]$/ { print; print "extrapath=./mt32rom"; next }
      /^\[dott-zh\]$/ { print; print "music_driver=mt32"; next }
      { print }
    ' "$APPDIR/usr/share/scummvm.ini" > "$APPDIR/usr/share/scummvm.ini.tmp"
    mv "$APPDIR/usr/share/scummvm.ini.tmp" "$APPDIR/usr/share/scummvm.ini"
fi

# ---- 圖示：直接用遊戲自己的標題 logo（實機畫格裁下來）----
ICON_SRC="${ICON_SRC:-$W/promo-icon.png}"
if [ -f "$ICON_SRC" ]; then
    cp "$ICON_SRC" "$APPDIR/dott-cht.png"
else
    # 沒有現成圖就畫一個：夜空底 + 螢光綠字
    convert -size 256x256 "radial-gradient:#292884-#05050D" \
        -font /usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc -gravity center \
        -fill '#2A8C42' -pointsize 88 -annotate +3+3 '瘋狂' \
        -fill '#49F571' -pointsize 88 -annotate +0+0 '瘋狂' \
        -fill '#EAF4FF' -pointsize 56 -annotate +0+72 '時代' \
        "$APPDIR/dott-cht.png"
fi
cp "$APPDIR/dott-cht.png" "$APPDIR/usr/share/icons/hicolor/256x256/apps/dott-cht.png"
ln -sf dott-cht.png "$APPDIR/.DirIcon"

cat > "$APPDIR/dott-cht.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=Day of the Tentacle 瘋狂時代（繁體中文）
Comment=LucasArts 1993 年的《瘋狂時代》繁體中文版，內含泰德電腦裡的一代
Exec=AppRun
Icon=dott-cht
Categories=Game;AdventureGame;
Terminal=false
DESKTOP

cat > "$APPDIR/AppRun" <<'APPRUN'
#!/bin/sh
# AppImage 每次掛載點都不同，所以「由掛載點推導出來」的路徑欄位每次重寫；
# 玩家自己的設定（語音包、音量）與存檔留在家目錄，不受影響。
set -e
HERE=$(dirname "$(readlink -f "$0")")
DATA="${XDG_DATA_HOME:-$HOME/.local/share}/dott-cht"
mkdir -p "$DATA/saves"
CFG="$DATA/scummvm.ini"
[ -f "$CFG" ] || cp "$HERE/usr/share/scummvm.ini" "$CFG"

sed -i \
  -e "s|^path=.*/game/dott/maniac$|path=$HERE/usr/share/game/dott/maniac|" \
  -e "s|^path=.*/game/dott$|path=$HERE/usr/share/game/dott|" \
  -e "s|^extrapath=.*|extrapath=$HERE/usr/share/mt32rom|" \
  "$CFG"

export LD_LIBRARY_PATH="$HERE/usr/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
exec "$HERE/usr/bin/scummvm" --config="$CFG" --savepath="$DATA/saves" dott-zh "$@"
APPRUN
chmod +x "$APPDIR/AppRun"

NAME="dott-cht-full-${STAMP}-x86_64.AppImage"
rm -f "$OUT/$NAME"
ARCH=x86_64 APPIMAGE_EXTRACT_AND_RUN=1 "$TOOL" --no-appstream "$APPDIR" "$OUT/$NAME"
chmod +x "$OUT/$NAME"
rm -rf "$APPDIR"

echo "=== $OUT/$NAME ==="
ls -la "$OUT/$NAME"
