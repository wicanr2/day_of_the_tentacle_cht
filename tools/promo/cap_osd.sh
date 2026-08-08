#!/bin/bash
# 抓 Ctrl+T 切換語音包的實機 OSD（640x400 全螢幕，與其他素材同尺寸）
set -e
export HOME=/root
mkdir -p /root/.config/scummvm /cap
cat > /root/.config/scummvm/scummvm.ini <<INI
[scummvm]
cht_voice_pack=0
fullscreen=true
aspect_ratio=false
[dott-zh]
engineid=scumm
gameid=tentacle
path=/w/game-cht/dott
easter_egg=maniac-zh
subtitles=true
INI
Xvfb :99 -screen 0 640x400x24 >/dev/null 2>&1 &
sleep 2
export DISPLAY=:99 SDL_AUDIODRIVER=dummy
/w/tools/scummvm-src/scummvm -f -e adlib dott-zh >/dev/null 2>&1 &
PID=$!
sleep 100                       # 等到開場的觸手場景（畫面好看）
for i in 1 2 3; do
  xdotool key --clearmodifiers ctrl+t
  sleep 0.5
  import -window root /cap/osd$i.png
  sleep 2.5
done
kill $PID 2>/dev/null || true
ls /cap/osd*.png
