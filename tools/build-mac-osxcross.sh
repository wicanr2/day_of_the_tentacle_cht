#!/bin/bash
# 在 Linux 上用 osxcross 交叉編瘋狂時代中文版的 ScummVM universal binary
# （arm64 + x86_64），只開 SCUMM 引擎。要在 dott-cht:osxcross image 裡跑。
#
# 與 tools/build-mac.sh 的關係：那支跑在 GitHub Actions 的 macos runner 上，
# 是原生編譯；這支是同一份設定的交叉編譯版，兩者的 configure 開關要一致，
# 改一邊就要改另一邊。CI 額度用完時走這條。
#
# 交叉編與原生編差在哪：
#   * 沒有 `arch -x86_64` 這種東西可以切換執行架構——目標架構由 wrapper 決定
#     （o64-clang 是 x86_64、oa64-clang 是 arm64），兩者都在 Linux 上執行。
#   * autoconf 的套件要明講 --host 與 CC/CXX/AR/RANLIB/STRIP，不能讓它猜。
#   * ScummVM 的 configure 不是 autoconf，但它認 AR/AS/CXX/RANLIB/STRIP/NM/CXXFILT
#     這幾個環境變數（見 configure 開頭的 SAVED_* ），--host 只用來決定平台分支。
#   * `codesign` 是 macOS 的工具，Linux 上沒有。arm64 的 Mach-O 一定要帶簽章才
#     執行得起來（Apple 從 arm64 開始強制），這件事由 ld64 在連結時自己做——
#     底下有一道守門檢查 LC_CODE_SIGNATURE 真的在。bundle 層的簽章做不出來，
#     但 tools/package-macos.sh 本來就會把它拔掉（「未簽」勝過「壞簽」）。
#
# 沿用一代與 CI 版的規則：
#   * 不用系統 SDL——自源碼靜態編 pinned SDL2。
#   * universal 不能單次雙 -arch，每弧各編一次再 lipo。
#   * **一定要 FLAC**：DOTT 的語音包 monster.sof 是 FLAC 壓縮，沒有 USE_FLAC
#     整片語音會消失，而且不報錯。底下有守門擋住。
set -euxo pipefail

MIN=13.4
SDLVER=2.30.9
OGGVER=1.3.5
FLACVER=1.4.3
# 工具前綴帶次版號：SDK 15.5 → darwin24.5。寫成 darwin24 會找不到任何工具，
# 而症狀是 clang 報「unable to execute command」，看起來像編譯器壞掉。
DARWIN=${OSXCROSS_TARGET:-darwin24.5}
JOBS="${JOBS:-6}"

ROOT="$PWD"
SVM="$ROOT/scummvm"
WORK="$ROOT/_macbuild"; mkdir -p "$WORK"

# arch → (triple, autoconf host)。config.sub 會把 arm64 正規化成 aarch64，
# 但 osxcross 的工具前綴是 arm64-*，所以兩個名字都要留著。
triple_of() { [ "$1" = arm64 ] && echo "arm64-apple-$DARWIN" || echo "x86_64-apple-$DARWIN"; }
achost_of() { [ "$1" = arm64 ] && echo "aarch64-apple-$DARWIN" || echo "x86_64-apple-$DARWIN"; }

# 交叉編譯用的環境。每個套件都套同一組，少一個就會有東西悄悄用到 host 的工具，
# 產出 ELF 而不是 Mach-O（而且往往到連結那一步才爆）。
cross_env() {
  local arch=$1 t; t=$(triple_of "$arch")
  # cctools 沒有 objcopy 與 c++filt，別去指它們——指到不存在的檔案，
  # autoconf 的探測會失敗得很難懂。c++filt 用 host 的就好：
  # 名稱修飾是 Itanium ABI，兩邊一樣。
  echo "CC=$t-clang CXX=$t-clang++ AR=$t-ar RANLIB=$t-ranlib STRIP=$t-strip \
NM=$t-nm AS=$t-as LD=$t-ld \
MACOSX_DEPLOYMENT_TARGET=$MIN"
}

fetch() {   # fetch <輸出檔> <主 URL> [備援 URL]
  local out=$1 url=$2 alt=${3:-}
  [ -f "$out" ] && return 0
  curl -fsSL --retry 5 --retry-all-errors --connect-timeout 20 -o "$out" "$url" && return 0
  [ -n "$alt" ] || return 1
  echo "主站失敗，改用鏡像：$alt"
  curl -fsSL --retry 5 --retry-all-errors --connect-timeout 20 -o "$out" "$alt"
}

# ---- 1. SDL2 per-arch，自源碼靜態編 ----
fetch "$WORK/SDL2.tar.gz" \
  "https://github.com/libsdl-org/SDL/releases/download/release-${SDLVER}/SDL2-${SDLVER}.tar.gz"
for arch in arm64 x86_64; do
  P="$WORK/deps-$arch"
  [ -f "$P/lib/libSDL2.a" ] && continue
  rm -rf "$WORK/sdl-src-$arch"; mkdir -p "$WORK/sdl-src-$arch"
  tar xf "$WORK/SDL2.tar.gz" -C "$WORK/sdl-src-$arch" --strip-components=1
  ( cd "$WORK/sdl-src-$arch"
    env $(cross_env "$arch") \
        CFLAGS="-arch $arch -mmacosx-version-min=$MIN" \
        LDFLAGS="-arch $arch -mmacosx-version-min=$MIN" \
      ./configure --prefix="$P" --disable-shared --enable-static \
        --host="$(achost_of "$arch")" >/dev/null
    make -j"$JOBS" >/dev/null
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

  if [ ! -f "$P/lib/libogg.a" ]; then
    rm -rf "$WORK/ogg-src-$arch"; mkdir -p "$WORK/ogg-src-$arch"
    tar xf "$WORK/libogg.tar.gz" -C "$WORK/ogg-src-$arch" --strip-components=1
    ( cd "$WORK/ogg-src-$arch"
      env $(cross_env "$arch") \
          CFLAGS="-arch $arch -mmacosx-version-min=$MIN" \
          LDFLAGS="-arch $arch -mmacosx-version-min=$MIN" \
        ./configure --prefix="$P" --enable-static --disable-shared \
          --host="$(achost_of "$arch")" >/dev/null
      make -j"$JOBS" >/dev/null
      make install >/dev/null )
  fi

  if [ ! -f "$P/lib/libFLAC.a" ]; then
    rm -rf "$WORK/flac-src-$arch"; mkdir -p "$WORK/flac-src-$arch"
    tar xf "$WORK/flac.tar.xz" -C "$WORK/flac-src-$arch" --strip-components=1
    ( cd "$WORK/flac-src-$arch"
      env $(cross_env "$arch") \
          CFLAGS="-arch $arch -mmacosx-version-min=$MIN" \
          LDFLAGS="-arch $arch -mmacosx-version-min=$MIN" \
          PKG_CONFIG_PATH="$P/lib/pkgconfig" \
        ./configure --prefix="$P" --enable-static --disable-shared \
          --host="$(achost_of "$arch")" \
          --disable-programs --disable-examples --disable-doxygen-docs --disable-ogg >/dev/null
      make -j"$JOBS" >/dev/null
      make install >/dev/null )
  fi
done

# ---- 3. ScummVM per-arch ----
for arch in arm64 x86_64; do
  P="$WORK/deps-$arch"
  t=$(triple_of "$arch")
  rm -rf "$WORK/svm-$arch"; cp -R "$SVM" "$WORK/svm-$arch"
  ( cd "$WORK/svm-$arch"
    # [雷] 這裡不要自己補 ar 的旗標。ScummVM 的 configure 是 `_ar="$AR cr"`，
    # 傳 AR="...-ar cr" 會變成 `ar cr cr -S`，ar 把第二個 cr 當成保存檔名，
    # 報的卻是「engines/scumm/libscumm.a: No such file or directory」——
    # 看起來像檔案沒產生，其實是參數多了一組。
    env $(cross_env "$arch") \
        CXXFLAGS="-arch $arch -mmacosx-version-min=$MIN" \
        LDFLAGS="-arch $arch -mmacosx-version-min=$MIN" \
      ./configure --host="$t" \
        --disable-all-engines --enable-engine=scumm \
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
    # 守門三：要是有哪個變數沒傳到，編出來的會是 Linux 的 ELF。這裡先確認
    # configure 自己也認為目標是 darwin。
    grep -qE "^MACOSX = 1" config.mk || { echo "### configure 沒走 macOS 分支"; exit 16; }
    make -j"$JOBS"
    cp scummvm "$WORK/scummvm-$arch" )
done

# ---- 4. lipo 合成 universal ----
LIPO="x86_64-apple-$DARWIN-lipo"
OTOOL="x86_64-apple-$DARWIN-otool"
$LIPO -create "$WORK/scummvm-arm64" "$WORK/scummvm-x86_64" -output "$WORK/scummvm-universal"
$LIPO -info "$WORK/scummvm-universal"
$LIPO -info "$WORK/scummvm-universal" | grep -q arm64 && \
$LIPO -info "$WORK/scummvm-universal" | grep -q x86_64 || { echo "### 非雙弧"; exit 20; }

# 守門四：arm64 一定要帶簽章。Apple 從 arm64 開始強制，沒有 LC_CODE_SIGNATURE
# 的執行檔在 Apple Silicon 上會直接被核心殺掉（Killed: 9），而且在 Linux 上
# 完全看不出異狀——檔案格式是對的，只是不能跑。
$OTOOL -l "$WORK/scummvm-arm64" | grep -q LC_CODE_SIGNATURE \
  || { echo "### arm64 沒有 LC_CODE_SIGNATURE，在 Apple Silicon 上會被殺掉"; exit 21; }

# ---- 5. 組 .app ----
# 這裡不 codesign：Linux 上沒有那個工具，做不出 bundle 層的 _CodeSignature。
# 執行檔本身的 ad-hoc 簽章由 ld64 在連結時加（守門四驗過），這是能不能跑的關鍵；
# bundle 層的簽章 tools/package-macos.sh 本來就會拔掉。
APP="$ROOT/dist-ci/ScummVM.app"; rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$ROOT/dist-ci"
cp "$WORK/scummvm-universal" "$APP/Contents/MacOS/scummvm"
cp "$SVM"/gui/themes/*.zip "$APP/Contents/Resources/" 2>/dev/null || true
cp "$SVM"/dists/engine-data/*.dat "$APP/Contents/Resources/" 2>/dev/null || true

# 這裡**不放**任何中文資料：烘出來的倚天字型是商業字型的衍生物，
# 譯文檔又夾帶英文原文。中文資料在本機組包時才注入。

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

# ---- 5b. ScummTR 也一起編（universal）----
# patch 包要在玩家的 Mac 上回填，所以需要一支 macOS 版 scummtr。
# 六個開關必須跟 Linux 端完全一致，少一個回填出來的檔就不是 byte-perfect。
TRFLAGS="-DSCUMMTR_PRESERVE_AMBIGUOUS_OI -DSCUMMTR_KEEP_DANGLING_INDEX_ENTRIES \
-DSCUMMTR_CJK_CUSTOM_CODESPACE -DSCUMMTR_PRESERVE_V1_ROOM_OFFSETS \
-DSCUMMTR_PRESERVE_DUP_INDEX_ENTRIES -DSCUMMRP_OK_TO_CORRUPT_MANIACV2"
if [ -d "$ROOT/scummtr" ]; then
  for arch in arm64 x86_64; do
    t=$(triple_of "$arch")
    rm -rf "$WORK/tr-$arch"; mkdir -p "$WORK/tr-$arch"
    ( cd "$WORK/tr-$arch"
      cmake "$ROOT/scummtr" -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_SYSTEM_NAME=Darwin \
        -DCMAKE_C_COMPILER="$t-clang" -DCMAKE_CXX_COMPILER="$t-clang++" \
        -DCMAKE_AR="/osxcross/bin/$t-ar" \
        -DCMAKE_RANLIB="/osxcross/bin/$t-ranlib" \
        -DCMAKE_OSX_ARCHITECTURES="$arch" \
        -DCMAKE_OSX_DEPLOYMENT_TARGET="$MIN" \
        -DCMAKE_CXX_FLAGS="$TRFLAGS"
      make -j"$JOBS" )
    cp "$WORK/tr-$arch/bin/scummtr" "$WORK/scummtr-$arch"
  done
  $LIPO -create "$WORK/scummtr-arm64" "$WORK/scummtr-x86_64" -output "$ROOT/dist-ci/scummtr"
  $LIPO -info "$ROOT/dist-ci/scummtr"
fi

# ---- 6. 打包（tar.gz 保 perm；APFS dmg 在 Windows/WSL 讀不到）----
OUTNAME="${OUTNAME:-dott-cht-macos-app.tar.gz}"
tar czf "$ROOT/dist-ci/$OUTNAME" -C "$ROOT/dist-ci" ScummVM.app $( [ -f "$ROOT/dist-ci/scummtr" ] && echo scummtr )
echo "=== BUILD_OK:dist-ci/$OUTNAME ==="
ls -la "$ROOT/dist-ci"
