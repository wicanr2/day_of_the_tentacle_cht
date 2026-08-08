#!/bin/bash
# 錄開場動畫（自動播放，不必操作）：x11grab 影像 + 之後另跑一次錄音訊
set -e
export HOME=/root
SECS=${1:-210}
PACK=${2:-1}
mkdir -p /root/.config/scummvm /cap
cat > /root/.config/scummvm/scummvm.ini <<INI
[scummvm]
cht_voice_pack=$PACK
fullscreen=true
aspect_ratio=false
[dott-zh]
engineid=scumm
gameid=tentacle
path=/w/game-cht/dott
easter_egg=maniac-zh
subtitles=true
speech_mute=false
talkspeed=60
INI
Xvfb :99 -screen 0 640x400x24 >/dev/null 2>&1 &
sleep 2
export DISPLAY=:99
# [雷] 容器裡沒有音效卡，ALSA 開啟失敗 → mixer 不前進 → 靠語音計時的過場永遠卡住。
# dummy 驅動會以即時速率消耗緩衝，過場才會照原本節奏走。
export SDL_AUDIODRIVER=dummy
/w/tools/scummvm-src/scummvm -f -e adlib --music-volume=255 dott-zh >/cap/run.log 2>&1 &
PID=$!
sleep 6
xdotool search --name ScummVM 2>/dev/null | head -1
timeout $((SECS+30)) ffmpeg -y -loglevel error -f x11grab -framerate 25 -video_size 640x400 -i :99 \
  -t $SECS -threads 2 -c:v libx264 -preset veryfast -crf 18 -pix_fmt yuv420p /cap/intro-pack$PACK.mp4
kill $PID 2>/dev/null || true
ls -la /cap/intro-pack$PACK.mp4
