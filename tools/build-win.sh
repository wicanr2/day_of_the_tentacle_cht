#!/bin/bash
# 交叉編 Windows 版 ScummVM（只開 SCUMM 引擎）
set -eu
SRC=/w/tools/scummvm-src
WORK=/w/tools/scummvm-win
PREFIX=/usr/x86_64-w64-mingw32

# 另複製一棵樹：configure 會在 source tree 產檔，跟 Linux build 共用會互相覆蓋。
#
# [雷 1] 不能排除 config.guess / config.sub，少了它們 configure 判不出 endianness 直接失敗。
# [雷 2] 排除規則必須錨定在**根目錄**。原本寫 `--exclude=config.h`，tar 會比對路徑的
#        任何一段，於是 audio/softsynth/mt32/config.h 也一起被排掉——那支帶著
#        MT32EMU_VERSION_MAJOR 等巨集，缺了它 Synth.cpp 編不過（而錯誤訊息被
#        `| tail -6` 吃掉，看起來只像「Error 1」）。rsync 的 /path 寫法才是錨定根目錄。
if [ ! -d "$WORK" ]; then
    mkdir -p "$WORK"
    # --anchored 讓 pattern 從路徑開頭比對（只排根目錄那幾個），
    # --no-anchored 之後的 pattern 才回到「路徑任何一段」的預設語意。
    (cd "$SRC" && tar cf - \
        --anchored --exclude='./config.h' --exclude='./config.mk' \
                   --exclude='./config.log' --exclude='./scummvm' \
        --no-anchored --exclude='.git' --exclude='*.o' --exclude='*.a' \
        .) | (cd "$WORK" && tar xf -)
    # 正對照：這支是 tar --exclude 誤傷過的檔案，缺了它 Synth.cpp 編不過
    [ -f "$WORK/audio/softsynth/mt32/config.h" ] || { echo "複製漏了 mt32/config.h"; exit 1; }
fi

cd "$WORK"
export PATH="$PREFIX/bin:$PATH"
if [ ! -f config.mk ]; then
    ./configure --host=x86_64-w64-mingw32 \
        --disable-all-engines --enable-engine=scumm \
        --with-sdl-prefix="$PREFIX" \
        --disable-fluidsynth --disable-libcurl --disable-sdlnet --disable-cloud \
        --disable-tts --disable-vorbis --disable-mad --disable-mpeg2 \
        --enable-flac --enable-zlib --disable-debug --enable-release \
        > /tmp/win-conf.log 2>&1 || { tail -40 /tmp/win-conf.log; exit 1; }
fi
grep -E '^(USE_FLAC|USE_ZLIB|ENABLE_SCUMM)' config.mk || true
# 不要接 tail：編譯失敗時錯誤訊息會被過濾器吃掉，只剩一行 "Error 1"
make -j"$(( $(nproc) - 2 ))"
ls -la scummvm.exe
