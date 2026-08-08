#!/bin/bash
# 從批次譯文重建中文版遊戲資料（在 docker 內跑，工作目錄 = repo 根目錄）
#
#   tools/build_cht.sh dott      → 瘋狂時代
#   tools/build_cht.sh maniac-v1 → 泰德電腦裡的一代
#
# 需要的外部路徑（相對 repo 根目錄的上層 workplace）：
#   ../game-orig/  原版資料      ../game-cht/  產出
#   ../dumps/      中間檔        ../font-src/  倚天點陣字
set -euo pipefail

WHICH="${1:-dott}"
W=..
SCUMMTR="$W/tools/scummtr-src/build/bin/scummtr"

# 兩條產線的碼空間、字模尺寸都不同，見 tools/cht_common.py 的 PROFILES：
#   dott      lead 0xA1-0xF7、8178 字位、16x14（倚天 15 點裁掉全空的第 15 列）
#   maniac-v1 lead 0x88-0x9F、2232 字位、16x15（v1/v2 的空白壓縮吃掉 0xA0 以上的首碼）
case "$WHICH" in
  dott)
    GAMEID=tentacle; ORIG="$W/game-orig/dott"; DEST="$W/game-cht/dott"
    RAW="$W/dumps/dott_raw.txt"; BATCH="translations/dott"
    COPY='TENTACLE.00*'
    export CHT_PROFILE=dott; FONT_ROWS=14 ;;
  maniac-v1)
    GAMEID=maniacv1; ORIG="$W/game-orig/maniac-v1"; DEST="$W/game-cht/dott/maniac"
    RAW="$W/dumps/v1_raw.txt"; BATCH="translations/maniac-v1"
    COPY='*.LFL'
    export CHT_PROFILE=maniacv1; FONT_ROWS=15 ;;
  *) echo "未知的產線：$WHICH"; exit 2 ;;
esac

echo "=== 1. 檢查批次格式 ==="
python3 tools/check_batches.py "$BATCH"/*.tsv

echo "=== 2. 合併譯文 ==="
python3 tools/merge_batches.py "$RAW" "$BATCH"/*.tsv -o "$W/dumps/${WHICH}_zh.txt"

echo "=== 3. 蒐集字集、產碼表 ==="
python3 tools/collect_charset.py "$W/dumps/${WHICH}_zh.txt" -o "cht_table_${WHICH}.json"

echo "=== 4. 編碼 ==="
python3 tools/cht_codec.py encode-file -t "cht_table_${WHICH}.json" \
    "$W/dumps/${WHICH}_zh.txt" "$W/dumps/${WHICH}_enc.txt"

# 兩份字型，字模尺寸與碼位完全相同，差別只在字形來源與能不能公開散布：
#   ${WHICH}.fnt      倚天中文系統的原生點陣字 —— 最清晰，但是商業字型的衍生物，
#                     只能留本機（full 包）。
#   ${WHICH}-wqy.fnt  WenQuanYi Zen Hei Sharp 的 embedded bitmap strike（15px 手繪點陣），
#                     GPL + 字體例外條款，可以跟公開的 patch 包一起散布。
echo "=== 5a. 烘倚天 16x${FONT_ROWS} 字型（本機用）==="
python3 tools/build_eten_font.py "cht_table_${WHICH}.json" --eten-dir "$W/font-src" \
    --size 16 --rows "$FONT_ROWS" --embolden -o "$W/dumps/${WHICH}.fnt"

echo "=== 5b. 烘 WQY 16x${FONT_ROWS} 字型（可公開）==="
python3 tools/build_eten_font.py "cht_table_${WHICH}.json" --source wqy \
    --size 16 --rows "$FONT_ROWS" --embolden -o "$W/dumps/${WHICH}-wqy.fnt"

# 指令列（給予／打開／查看…）另外一套字型：華康少女體。它是圓體，跟倚天明體
# 的對比讓指令列一眼就分得出來，也貼近瘋狂大樓 Deluxe 的做法。
# [雷] 一定要走灰階光柵器再自己設門檻——FreeType 的 mono 光柵器會把少女體 W7
#      這種重量級字面的內白填掉，16x14 直接糊成一團。門檻 140 是實測的平衡點。
# 同樣是商業字型的衍生物，只進 full 包。
if [ "$WHICH" = dott ] && [ -f "$W/font-src/girl.ttc" ]; then
    echo "=== 5c. 烘華康少女體 16x${FONT_ROWS} 指令列字型（本機用）==="
    python3 tools/build_eten_font.py "cht_table_${WHICH}.json" \
        --source gray --gray-font "$W/font-src/girl.ttc" \
        --gray-px "$FONT_ROWS" --gray-threshold 140 \
        --size 16 --rows "$FONT_ROWS" -o "$W/dumps/${WHICH}-verb.fnt"

    # 對白字型：倚天 24 點原生點陣。對白畫在遊戲畫面上，沒有指令列那種列距限制，
    # 放大到 24x24 才看得清楚（對照極速天龍的字幕尺寸）。句子列仍用 16x14 的正文
    # 字型，所以不會擠到指令列。
    if [ -f "$W/font-src/STDFONT.24" ]; then
        echo "=== 5d. 烘倚天 24x24 對白字型（本機用）==="
        python3 tools/build_eten_font.py "cht_table_${WHICH}.json" --eten-dir "$W/font-src" \
            --size 24 -o "$W/dumps/${WHICH}-dialog.fnt"
    fi
fi

echo "=== 6. 回填 ==="
mkdir -p "$DEST"
rm -f "$DEST"/*scummio-tmp
# shellcheck disable=SC2086
cp $ORIG/$COPY "$DEST"/
cp "$W/dumps/${WHICH}_enc.txt" "$DEST/scummtr.txt"
( cd "$DEST" && "$OLDPWD/$SCUMMTR" -g "$GAMEID" -r -w -if )
rm -f "$DEST/scummtr.txt"
cp "$W/dumps/${WHICH}.fnt" "$DEST/chinese_gb16x12.fnt"
[ -f "$W/dumps/${WHICH}-verb.fnt" ]   && cp "$W/dumps/${WHICH}-verb.fnt"   "$DEST/chinese_verb.fnt"
[ -f "$W/dumps/${WHICH}-dialog.fnt" ] && cp "$W/dumps/${WHICH}-dialog.fnt" "$DEST/chinese_dialog.fnt"

echo "=== 完成：$DEST ==="
ls -la "$DEST" | head -8
