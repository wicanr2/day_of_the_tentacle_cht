#!/bin/bash
# 錄原版音樂的 MT-32 版本。
# [雷] --enable-mt32emu 只是把模擬器編進 binary；要真出聲還要
#      ROM（檔名須為 MT32_CONTROL.ROM / MT32_PCM.ROM）＋ --extrapath 指到 ROM 目錄。
set -e
export HOME=/root
mkdir -p /root/.config/scummvm /cap
cat > /root/.config/scummvm/scummvm.ini <<INI
[scummvm]
[dott-zh]
engineid=scumm
gameid=tentacle
path=/w/game-cht/dott
easter_egg=maniac-zh
subtitles=true
speech_mute=true
INI
Xvfb :99 -screen 0 640x400x24 >/dev/null 2>&1 &
sleep 2
export DISPLAY=:99
export SDL_AUDIODRIVER=disk SDL_DISKAUDIOFILE=/cap/music-mt32.raw
rm -f /cap/music-mt32.raw
timeout ${1:-260} /w/tools/scummvm-src/scummvm \
  --music-driver=mt32 --extrapath=/rom \
  --music-volume=255 --speech-volume=0 dott-zh > /cap/mt32.log 2>&1 || true
ls -la /cap/music-mt32.raw
grep -aiE 'mt32|rom|midi' /cap/mt32.log | head -10 || true
