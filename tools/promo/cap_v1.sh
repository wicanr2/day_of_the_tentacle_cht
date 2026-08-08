#!/bin/bash
# 抓一代（SCUMM v1）的中文畫面，尺寸與其他素材一致
set -e
export HOME=/root
mkdir -p /root/.config/scummvm /cap
cat > /root/.config/scummvm/scummvm.ini <<INI
[scummvm]
fullscreen=true
aspect_ratio=false
[maniac-zh]
engineid=scumm
gameid=maniac
path=/w/game-cht/dott/maniac
platform=pc
extra=V1
subtitles=true
INI
Xvfb :99 -screen 0 640x400x24 >/dev/null 2>&1 &
sleep 2
export DISPLAY=:99 SDL_AUDIODRIVER=dummy
/w/tools/scummvm-src/scummvm -f -e adlib maniac-zh >/dev/null 2>&1 &
PID=$!
sleep 8;  import -window root /cap/v1-a.png     # 開場／選角
sleep 12; import -window root /cap/v1-b.png
xdotool key --clearmodifiers Return; sleep 3
import -window root /cap/v1-c.png
sleep 8;  import -window root /cap/v1-d.png
kill $PID 2>/dev/null || true
ls /cap/v1-*.png
