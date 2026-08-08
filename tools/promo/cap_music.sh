#!/bin/bash
# 錄原版遊戲音樂：SDL disk driver。它不是即時的（會比實際時間快很多），
# 所以錄完要掃整段找有聲窗，不能假設音樂在前 N 秒。
set -e
export HOME=/root
mkdir -p /root/.config/scummvm /cap
cat > /root/.config/scummvm/scummvm.ini <<INI
[scummvm]
cht_voice_pack=0
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
export SDL_AUDIODRIVER=disk SDL_DISKAUDIOFILE=/cap/music.raw
rm -f /cap/music.raw
timeout ${1:-100} /w/tools/scummvm-src/scummvm -e adlib --music-volume=255 --speech-volume=0 dott-zh >/dev/null 2>&1 || true
ls -la /cap/music.raw
