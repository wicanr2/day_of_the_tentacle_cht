#!/bin/bash
# 在 GitHub Actions 的 macos runner 上編瘋狂時代中文版的 ScummVM universal binary
# （arm64 + x86_64），只開 SCUMM 引擎。
#
# 為什麼是 CI 而不是本機：macOS 的 .app 需要 codesign / lipo，只有 macOS host 有；
# Linux 端做不出來也測不出來。
#
# 幾條沿用一代實戰的規則：
#   * 不要 brew install sdl2 —— 2026 年起那是 sdl2-compat shim，runtime 才 dlopen
#     libSDL3，打包抓不到 → 玩家端「Failed loading SDL3 library」。自源碼編 pinned SDL2。
#   * universal 不能單次雙 -arch（configure 的版本解析會炸）→ 每弧各編一次再 lipo。
#   * ScummVM 的 configure 不是 autoconf：CXXFLAGS/LDFLAGS 只能用環境變數前綴。
#
# 本作與一代的差別：**一定要 FLAC**。DOTT 的語音包 monster.sof 是 FLAC 壓縮，
# 沒有 USE_FLAC 就整片語音消失，而且不報錯。所以底下有一道守門把它擋住。
set -euxo pipefail
MIN=13.4
SDLVER=2.30.9
OGGVER=1.3.5
FLACVER=1.4.3
ROOT="$PWD"
SVM="$ROOT/scummvm"
WORK="$ROOT/_macbuild"; mkdir -p "$WORK"

# 下載：downloads.xiph.org 從 GitHub 的 macOS runner 連過去偶爾會斷在 TLS 握手
# （curl exit 35，LibreSSL SSL_ERROR_SYSCALL）。單純的 --retry 不管這種錯——
# curl 只重試它認定的「暫時性」狀況，35 不在其中——要 --retry-all-errors。
# 再備一個鏡像，兩邊都不通才算真的失敗。
fetch() {   # fetch <輸出檔> <主 URL> [備援 URL]
  local out=$1 url=$2 alt=${3:-}
  curl -fsSL --retry 5 --retry-all-errors --connect-timeout 20 -o "$out" "$url" && return 0
  [ -n "$alt" ] || return 1
  echo "主站失敗，改用鏡像：$alt"
  curl -fsSL --retry 5 --retry-all-errors --connect-timeout 20 -o "$out" "$alt"
}

# ---- 1. SDL2 per-arch，自源碼靜態編 ----
fetch "$WORK/SDL2.tar.gz" \
  "https://github.com/libsdl-org/SDL/releases/download/release-${SDLVER}/SDL2-${SDLVER}.tar.gz"
for arch in arm64 x86_64; do
  rm -rf "$WORK/sdl-src-$arch"; mkdir -p "$WORK/sdl-src-$arch"
  tar xf "$WORK/SDL2.tar.gz" -C "$WORK/sdl-src-$arch" --strip-components=1
  P="$WORK/deps-$arch"
  runner=""; [ "$arch" = x86_64 ] && runner="arch -x86_64"
  host="$( [ "$arch" = x86_64 ] && echo x86_64-apple-darwin || echo aarch64-apple-darwin )"
  ( cd "$WORK/sdl-src-$arch"
    $runner env CFLAGS="-arch $arch -mmacosx-version-min=$MIN" \
                LDFLAGS="-arch $arch -mmacosx-version-min=$MIN" \
      ./configure --prefix="$P" --disable-shared --enable-static --host="$host" >/dev/null
    $runner make -j"$(sysctl -n hw.ncpu)" >/dev/null
    make install >/dev/null )
done

# ---- 2. libogg → libFLAC per-arch（順序不能反，FLAC 的 configure 會找 ogg）----
fetch "$WORK/libogg.tar.gz" \
  "https://downloads.xiph.org/releases/ogg/libogg-${OGGVER}.tar.gz" \
  "https://ftp.osuosl.org/pub/xiph/releases/ogg/libogg-${OGGVER}.tar.gz"
fetch "$WORK/flac.tar.xz" \
  "https://downloads.xiph.org/releases/flac/flac-${FLACVER}.tar.xz" \
  "https://ftp.osuosl.org/pub/xiph/releases/flac/flac-${FLACVER}.tar.xz"
for arch in arm64 x86_64; do
  P="$WORK/deps-$arch"
  runner=""; [ "$arch" = x86_64 ] && runner="arch -x86_64"
  host="$( [ "$arch" = x86_64 ] && echo x86_64-apple-darwin || echo aarch64-apple-darwin )"

  rm -rf "$WORK/ogg-src-$arch"; mkdir -p "$WORK/ogg-src-$arch"
  tar xf "$WORK/libogg.tar.gz" -C "$WORK/ogg-src-$arch" --strip-components=1
  ( cd "$WORK/ogg-src-$arch"
    $runner env CFLAGS="-arch $arch -mmacosx-version-min=$MIN" \
                LDFLAGS="-arch $arch -mmacosx-version-min=$MIN" \
      ./configure --prefix="$P" --enable-static --disable-shared --host="$host" >/dev/null
    $runner make -j"$(sysctl -n hw.ncpu)" >/dev/null
    make install >/dev/null )

  rm -rf "$WORK/flac-src-$arch"; mkdir -p "$WORK/flac-src-$arch"
  tar xf "$WORK/flac.tar.xz" -C "$WORK/flac-src-$arch" --strip-components=1
  ( cd "$WORK/flac-src-$arch"
    $runner env CFLAGS="-arch $arch -mmacosx-version-min=$MIN" \
                LDFLAGS="-arch $arch -mmacosx-version-min=$MIN" \
                PKG_CONFIG_PATH="$P/lib/pkgconfig" \
      ./configure --prefix="$P" --enable-static --disable-shared --host="$host" \
        --disable-programs --disable-examples --disable-doxygen-docs --disable-ogg >/dev/null
    $runner make -j"$(sysctl -n hw.ncpu)" >/dev/null
    make install >/dev/null )
done

# ---- 3. ScummVM per-arch ----
for arch in arm64 x86_64; do
  P="$WORK/deps-$arch"
  runner=""; [ "$arch" = x86_64 ] && runner="arch -x86_64"
  rm -rf "$WORK/svm-$arch"; cp -R "$SVM" "$WORK/svm-$arch"
  ( cd "$WORK/svm-$arch"
    $runner env CXXFLAGS="-arch $arch -mmacosx-version-min=$MIN" \
                LDFLAGS="-arch $arch -mmacosx-version-min=$MIN" \
      ./configure --disable-all-engines --enable-engine=scumm \
        --enable-release --disable-debug \
        --with-sdl-prefix="$P/bin" \
        --with-flac-prefix="$P" --with-ogg-prefix="$P" \
        --enable-flac --enable-zlib \
        --disable-fluidsynth --disable-vorbis --disable-mad --disable-mpeg2 \
        --disable-png --disable-jpeg --disable-gif --disable-vpx --disable-tremor \
        --disable-mikmod --disable-openmpt --disable-fribidi --disable-retrowave \
        --disable-faad --disable-theoradec --disable-a52 --disable-freetype2 \
        --disable-libcurl --disable-sndio --disable-timidity --disable-sparkle \
        --disable-tts --disable-eventrecorder
    # 守門一：引擎要在
    grep -qiE "Disabling engine SCUMM" config.log && { echo "### SCUMM 被剔除"; exit 13; } || true
    # 守門二：FLAC 要編進去。少了它 monster.sof 讀不出來，遊戲會安靜地變成無語音。
    grep -qE "^USE_FLAC = 1" config.mk || { echo "### 沒編進 FLAC，語音會消失"; exit 15; }
    $runner make -j"$(sysctl -n hw.ncpu)"
    cp scummvm "$WORK/scummvm-$arch" )
done

# ---- 4. lipo 合成 universal ----
lipo -create "$WORK/scummvm-arm64" "$WORK/scummvm-x86_64" -output "$WORK/scummvm-universal"
lipo -info "$WORK/scummvm-universal"
lipo -info "$WORK/scummvm-universal" | grep -q arm64 && \
lipo -info "$WORK/scummvm-universal" | grep -q x86_64 || { echo "### 非雙弧"; exit 20; }

# ---- 5. 組 .app 並 ad-hoc 簽章 ----
APP="$ROOT/dist-ci/ScummVM.app"; rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$ROOT/dist-ci"
cp "$WORK/scummvm-universal" "$APP/Contents/MacOS/scummvm"
cp "$SVM"/gui/themes/*.zip "$APP/Contents/Resources/" 2>/dev/null || true
cp "$SVM"/dists/engine-data/*.dat "$APP/Contents/Resources/" 2>/dev/null || true

# 這裡**不放**任何中文資料：烘出來的倚天字型是商業字型的衍生物，
# 譯文檔又夾帶英文原文，兩者都不上 CI。CI 只出 engine-only 的 .app，
# 中文資料在本機組包時才注入（與遊戲資料同一個道理）。

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>scummvm</string>
<key>CFBundleIdentifier</key><string>org.scummvm.dottcht</string>
<key>CFBundleName</key><string>ScummVM 瘋狂時代中文版</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>dott-cht</string>
<key>LSMinimumSystemVersion</key><string>$MIN</string>
</dict></plist>
PLIST
codesign --force --deep --sign - "$APP"
lipo -info "$APP/Contents/MacOS/scummvm"

# ---- 5b. ScummTR 也一起編（universal）----
# patch 包要在玩家的 Mac 上回填，所以需要一支 macOS 版 scummtr。
# 六個開關必須跟 Linux 端完全一致，少一個回填出來的檔就不是 byte-perfect。
TRFLAGS="-DSCUMMTR_PRESERVE_AMBIGUOUS_OI -DSCUMMTR_KEEP_DANGLING_INDEX_ENTRIES \
-DSCUMMTR_CJK_CUSTOM_CODESPACE -DSCUMMTR_PRESERVE_V1_ROOM_OFFSETS \
-DSCUMMTR_PRESERVE_DUP_INDEX_ENTRIES -DSCUMMRP_OK_TO_CORRUPT_MANIACV2"
if [ -d "$ROOT/scummtr" ]; then
  for arch in arm64 x86_64; do
    rm -rf "$WORK/tr-$arch"; mkdir -p "$WORK/tr-$arch"
    ( cd "$WORK/tr-$arch"
      cmake "$ROOT/scummtr" -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_OSX_ARCHITECTURES="$arch" \
        -DCMAKE_OSX_DEPLOYMENT_TARGET="$MIN" \
        -DCMAKE_CXX_FLAGS="$TRFLAGS"
      make -j"$(sysctl -n hw.ncpu)" )
    cp "$WORK/tr-$arch/bin/scummtr" "$WORK/scummtr-$arch"
  done
  lipo -create "$WORK/scummtr-arm64" "$WORK/scummtr-x86_64" -output "$ROOT/dist-ci/scummtr"
  lipo -info "$ROOT/dist-ci/scummtr"
fi

# ---- 6. 打包（tar.gz 保 perm；APFS dmg 在 Windows/WSL 讀不到）----
OUTNAME="${OUTNAME:-dott-cht-macos-app.tar.gz}"
tar czf "$ROOT/dist-ci/$OUTNAME" -C "$ROOT/dist-ci" ScummVM.app $( [ -f "$ROOT/dist-ci/scummtr" ] && echo scummtr )
echo "=== BUILD_OK:dist-ci/$OUTNAME ==="
ls -la "$ROOT/dist-ci"
