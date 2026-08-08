#!/usr/bin/env bash
# 瘋狂時代繁中化推廣片 —— 靜態卡 + 實機片段 + 原版配樂
#
# 敘事骨架：對白精選輯（本作是黑色喜劇，靠台詞吃飯）
# 全程 docker、不開剪輯軟體、可重跑。
#
# [雷] 不用 zoompan：`-loop 1 -t S` + 前置 fps 會讓 zoompan 算成 (FPS*S)² 幀。
#      靜態圖 + fade 對推廣片完全夠看。
set -eu
. /p/theme.sh

SRC=/p/cap/intro-pack1.mp4
TMP=/tmp/c; OUT=/p/out; mkdir -p "$TMP" "$OUT"

# ---------- 版面函式 ----------

bg() {   # $1 out —— 夜空徑向漸層 + 底部地平線暗帶
  convert -size ${W}x${H} "radial-gradient:${BG_LITE}-${BG_DEEP}" \
    -fill "#00000066" -draw "rectangle 0,$((H-90)) ${W},${H}" "$1"
}

zh() { # $1 out(透明層)  $2 文字  $3 字級  $4 旋轉角度
  # 中文字放大＋螢光綠描邊＋微幅旋轉＝貼紙感。分兩層畫：先畫粗描邊的，
  # 再把無描邊的疊上去，筆畫內部才不會被描邊侵蝕。
  local SW=$(( $3 / 13 ))
  convert -background none -font "$FONT_TITLE" -pointsize "$3" \
    -stroke "$ACCENT" -strokewidth "$SW" -fill "$TEXT" label:"$2" "$TMP/_z1.png"
  convert -background none -font "$FONT_TITLE" -pointsize "$3" \
    -stroke none -fill "$TEXT" label:"$2" "$TMP/_z2.png"
  convert "$TMP/_z1.png" "$TMP/_z2.png" -gravity center -composite \
    -background none -rotate "$4" +repage "$1"
}

card() { # $1 out  $2 中文大標  $3 英文標  $4 副標  [$5 英文字級=88]  [$6 中文字級=100]
  bg "$TMP/_bg.png"
  local PS=${5:-88} ZS=${6:-100}
  zh "$TMP/_zh.png" "$2" "$ZS" -2.5
  convert "$TMP/_bg.png" -gravity center \
    -font "$FONT_TITLE" \
    -fill "$ACCENT_DK" -pointsize $PS -annotate +4-116 "$3" \
    -fill "$ACCENT"    -pointsize $PS -annotate +0-120 "$3" \
    "$TMP/_zh.png" -gravity center -geometry +0+22 -composite \
    -font "$FONT_BODY" -fill "$ACCENT2" -pointsize 32 -gravity center -annotate +0+134 "$4" \
    "$1"
}

dcard() { # $1 out  $2 中文台詞  $3 英文原文  $4 說話者
  bg "$TMP/_bg.png"
  zh "$TMP/_zh.png" "$2" 84 1.8
  convert "$TMP/_bg.png" \
    -font "$FONT_TITLE" -fill "#ffffff1f" -pointsize 300 \
      -gravity northwest -annotate +36+10 '“' \
    "$TMP/_zh.png" -gravity west -geometry +130-56 -composite \
    -font "$FONT_BODY"  -fill "$DIM"     -pointsize 30 \
      -gravity west -annotate +150+52 "$3" \
    -font "$FONT_BODY"  -fill "$ACCENT"  -pointsize 32 \
      -gravity southeast -annotate +70+56 "— $4" \
    "$1"
}

slide() { # $1 out  $2 截圖  $3 字幕
  # 素材來源尺寸不一（640x400 實錄、640x480 舊截圖），先等比縮進同一個框再補底，
  # 每張的畫框才會一樣大。畫框刻意留在字幕條之上，不讓字幕吃到畫面。
  bg "$TMP/_bg.png"
  convert "$2" -filter point -resize 1024x640 \
    -background "$BG_DEEP" -gravity center -extent 1024x640 \
    -bordercolor "$ACCENT" -border 3 "$TMP/_sc.png"
  convert "$TMP/_bg.png" "$TMP/_sc.png" -gravity center -geometry +0-38 -composite \
    -fill "#000000cc" -draw "rectangle 0,$((H-78)) ${W},${H}" \
    -font "$FONT_TITLE" -fill "$TEXT" -gravity south -pointsize 38 -annotate +0+18 "$3" \
    "$1"
}

panel3() { # $1 out  $2 亮起哪一格(0/1/2)  —— 三組語音橫排
  bg "$TMP/_bg.png"
  local names=('原版英文' '台式中文' '原音克隆')
  local subs=('1993 年的錄音' 'edge-tts 台灣聲音\n音高照原音的基頻挑' 'F5-TTS 聲音克隆\n角色用自己的聲音講中文')
  local cmd=(convert "$TMP/_bg.png")
  cmd+=( -font "$FONT_BODY"  -fill "$DIM"  -pointsize 30 -gravity north -annotate +0+36  "遊戲中按 Ctrl+T 循環切換" )
  cmd+=( -font "$FONT_TITLE" -fill "$TEXT" -pointsize 58 -gravity north -annotate +0+96  "這全都是你的錯，伯納。" )
  cmd+=( -font "$FONT_BODY"  -fill "$DIM"  -pointsize 24 -gravity north -annotate +0+172 "This is all your fault, Bernard." )
  local i x
  for i in 0 1 2; do
    x=$(( 112 + i * 368 ))
    if [ "$i" = "$2" ]; then
      cmd+=( -fill "#49f57126" -stroke "$ACCENT"  -strokewidth 3 )
    else
      cmd+=( -fill "#ffffff08" -stroke "#ffffff22" -strokewidth 2 )
    fi
    cmd+=( -draw "roundrectangle $x,240 $((x+320)),470 14,14" -stroke none )
    if [ "$i" = "$2" ]; then cmd+=( -fill "$ACCENT" ); else cmd+=( -fill "$DIM" ); fi
    cmd+=( -font "$FONT_TITLE" -pointsize 50 -gravity northwest
           -annotate +$((x+22))+290 "${names[$i]}" )
    if [ "$i" = "$2" ]; then cmd+=( -fill "$TEXT" ); else cmd+=( -fill "#6b74a5" ); fi
    cmd+=( -font "$FONT_BODY" -pointsize 22 -gravity northwest
           -annotate +$((x+24))+362 "$(printf '%b' "${subs[$i]}")" )
  done
  cmd+=( -font "$FONT_BODY" -fill "$ACCENT2" -pointsize 28 -gravity south
         -annotate +0+38 "語音包本機自建，不隨安裝包散布" )
  "${cmd[@]}" "$1"
}

still() { # $1 png  $2 mp4  $3 秒 —— 靜態 + 淡入淡出
  local FO; FO=$(awk "BEGIN{print $3-0.5}")
  ffmpeg -y -loglevel error -loop 1 -i "$1" -t "$3" -r $FPS \
    -vf "fade=t=in:st=0:d=0.4,fade=t=out:st=$FO:d=0.5,format=yuv420p" \
    -threads 2 -c:v libx264 -preset veryfast -pix_fmt yuv420p "$2"
}

clip() { # $1 out.mp4  $2 起點秒  $3 長度 —— 實機片段，加綠框置中
  bg "$TMP/_bgplate.png"
  local FO; FO=$(awk "BEGIN{print $3-0.5}")
  ffmpeg -y -loglevel error -ss "$2" -t "$3" -i "$SRC" -loop 1 -i "$TMP/_bgplate.png" \
    -filter_complex "[0:v]scale=1120:700:flags=neighbor,pad=1126:706:3:3:color=${ACCENT}[g];\
[1:v][g]overlay=(W-w)/2:(H-h)/2,fade=t=in:st=0:d=0.4,fade=t=out:st=$FO:d=0.5,format=yuv420p" \
    -t "$3" -r $FPS -threads 2 -c:v libx264 -preset veryfast -pix_fmt yuv420p "$1"
}

# ---------- 分鏡 ----------
# TOTAL 由 add() 累加，語音段的插入點直接從它讀，不必手算（手算會隨改秒數而失準）
: > "$TMP/list.txt"
TOTAL=0
add() { echo "file '$1'" >> "$TMP/list.txt"; TOTAL=$(awk "BEGIN{print $TOTAL+$2}"); }

card  "$TMP/01.png" '瘋狂時代' 'Day of the Tentacle' '繁體中文化　·　連泰德電腦裡的一代一起'
still "$TMP/01.png" "$TMP/v01.mp4" 5.0;  add "$TMP/v01.mp4" 5.0

clip  "$TMP/v02.mp4" 30 9.0;             add "$TMP/v02.mp4" 9.0

dcard "$TMP/03.png" '看起來對身體不太好。' 'It looks bad for you.' '綠色觸手'
still "$TMP/03.png" "$TMP/v03.mp4" 4.2;  add "$TMP/v03.mp4" 4.2

clip  "$TMP/v04.mp4" 84 8.0;             add "$TMP/v04.mp4" 8.0

dcard "$TMP/05.png" '更聰明！更有侵略性！' 'Smarter!  More aggressive!' '紫色觸手'
still "$TMP/05.png" "$TMP/v05.mp4" 4.2;  add "$TMP/v05.mp4" 4.2

clip  "$TMP/v06.mp4" 126 8.0;            add "$TMP/v06.mp4" 8.0

card  "$TMP/07.png" '四千兩百三十九句台詞' '4,239 LINES' '回填逐行 byte-perfect　·　零孤兒高位元組'
still "$TMP/07.png" "$TMP/v07.mp4" 4.0;  add "$TMP/v07.mp4" 4.0

slide "$TMP/08.png" /p/cap/osd1.png '字幕之外，還有兩組中文配音'
still "$TMP/08.png" "$TMP/v08.mp4" 4.5;  add "$TMP/v08.mp4" 4.5

V0=$TOTAL                      # 語音段起點：三個版本從這裡依序播
panel3 "$TMP/09.png" 0; still "$TMP/09.png" "$TMP/v09.mp4" 3.0; add "$TMP/v09.mp4" 3.0
panel3 "$TMP/10.png" 1; still "$TMP/10.png" "$TMP/v10.mp4" 3.5; add "$TMP/v10.mp4" 3.5
panel3 "$TMP/11.png" 2; still "$TMP/11.png" "$TMP/v11.mp4" 2.6; add "$TMP/v11.mp4" 2.6
V_END=$TOTAL

slide "$TMP/12.png" /p/shots/egg-1-ed-room-zh.png '遊戲中期打開泰德房間那台電腦'
still "$TMP/12.png" "$TMP/v12.mp4" 4.5;  add "$TMP/v12.mp4" 4.5

slide "$TMP/13.png" /p/cap/v1-pick.png '一代《瘋狂大樓》整套跳出來——七個可選主角，介紹全中文'
still "$TMP/13.png" "$TMP/v13.mp4" 4.5;  add "$TMP/v13.mp4" 4.5

slide "$TMP/14.png" /p/shots/v1-verbs-zh.png '連 1987 年那套 SCUMM v1 的指令列都是中文'
still "$TMP/14.png" "$TMP/v14.mp4" 4.5;  add "$TMP/v14.mp4" 4.5

card  "$TMP/15.png" 'day_of_the_tentacle_cht' 'github.com/wicanr2' '免費 · 開源 · patch-only　·　需自備 1993 CD 版資料' 62 58
still "$TMP/15.png" "$TMP/v15.mp4" 6.0;  add "$TMP/v15.mp4" 6.0

# ---------- 合成 ----------
ffmpeg -y -loglevel error -f concat -safe 0 -i "$TMP/list.txt" \
  -threads 2 -c:v libx264 -preset veryfast -pix_fmt yuv420p "$TMP/silent.mp4"
DUR=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$TMP/silent.mp4")
echo "分鏡總長 ${DUR}s"

# 語音段：三個版本依序插進來，同時把配樂壓到 12%
V1=$(awk "BEGIN{print $V0+3.0}")
V2=$(awk "BEGIN{print $V0+6.5}")
DUCK_A=$(awk "BEGIN{print $V0-0.4}")
DUCK_B=$(awk "BEGIN{print $V_END+0.3}")
echo "語音段 $V0 → $V_END 秒"
FO=$(awk "BEGIN{print $DUR-3}")

# [雷] 配樂比影片短時不能靠 -shortest：先 aloop 無限循環再 atrim 到影片長度。
# [雷] alimiter 預設 `level=true` 會自動把輸出補回滿刻度——把 limit 調低反而更大聲。
#      要留 headroom 必須同時關掉 level。
ffmpeg -y -loglevel error -i "$TMP/silent.mp4" -i /p/bgm-mt32.wav \
  -i /p/voice/en.wav -i /p/voice/tw.wav -i /p/voice/cl.wav \
  -filter_complex "\
[1:a]aloop=loop=-1:size=2000000000,atrim=0:$DUR,asetpts=N/SR/TB,\
afade=t=in:st=0:d=2,afade=t=out:st=$FO:d=3,\
volume=enable='between(t,$DUCK_A,$DUCK_B)':volume=0.12[bg];\
[2:a]adelay=$(awk "BEGIN{printf \"%d\", $V0*1000}")|$(awk "BEGIN{printf \"%d\", $V0*1000}"),volume=1.45[a0];\
[3:a]adelay=$(awk "BEGIN{printf \"%d\", $V1*1000}")|$(awk "BEGIN{printf \"%d\", $V1*1000}"),volume=1.45[a1];\
[4:a]adelay=$(awk "BEGIN{printf \"%d\", $V2*1000}")|$(awk "BEGIN{printf \"%d\", $V2*1000}"),volume=1.45[a2];\
[bg][a0][a1][a2]amix=inputs=4:duration=first:normalize=0,alimiter=limit=0.89:level=false[a]" \
  -map 0:v -map "[a]" -threads 2 -c:v libx264 -preset veryfast -pix_fmt yuv420p \
  -c:a aac -b:a 192k -movflags +faststart "$OUT/dott-cht-promo.mp4"

echo "=== 產出 ==="
ffprobe -v error -select_streams v -show_entries stream=width,height,duration -of csv=p=0 "$OUT/dott-cht-promo.mp4"
ffprobe -v error -select_streams a -show_entries stream=duration -of csv=p=0 "$OUT/dott-cht-promo.mp4"
ls -la "$OUT/dott-cht-promo.mp4"
