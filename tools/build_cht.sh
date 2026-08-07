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

case "$WHICH" in
  dott)
    GAMEID=tentacle; ORIG="$W/game-orig/dott"; DEST="$W/game-cht/dott"
    RAW="$W/dumps/dott_raw.txt"; BATCH="translations/dott"
    COPY='TENTACLE.00*' ;;
  maniac-v1)
    GAMEID=maniacv1; ORIG="$W/game-orig/maniac-v1"; DEST="$W/game-cht/dott/maniac"
    RAW="$W/dumps/v1_raw.txt"; BATCH="translations/maniac-v1"
    COPY='*.LFL' ;;
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

echo "=== 5. 烘倚天 16x14 字型 ==="
python3 tools/build_eten_font.py "cht_table_${WHICH}.json" --eten-dir "$W/font-src" \
    --size 16 --rows 14 --embolden -o "$W/dumps/${WHICH}.fnt"

echo "=== 6. 回填 ==="
mkdir -p "$DEST"
rm -f "$DEST"/*scummio-tmp
# shellcheck disable=SC2086
cp $ORIG/$COPY "$DEST"/
cp "$W/dumps/${WHICH}_enc.txt" "$DEST/scummtr.txt"
( cd "$DEST" && "$OLDPWD/$SCUMMTR" -g "$GAMEID" -r -w -if )
rm -f "$DEST/scummtr.txt"
cp "$W/dumps/${WHICH}.fnt" "$DEST/chinese_gb16x12.fnt"

echo "=== 完成：$DEST ==="
ls -la "$DEST" | head -8
