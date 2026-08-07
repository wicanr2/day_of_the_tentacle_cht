#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
collect_charset.py — 從譯文蒐集 CJK 字元，產生碼表 cht_table.json

用法：
    python3 collect_charset.py [-o cht_table.json] 譯文檔 [譯文檔 ...]

設計要點：
- 輸入為 UTF-8 譯文（容許混入 scummtr 匯出檔遺留的 latin-1 高位元組）
- 蒐集所有 CJK／全形字元（見 cht_common.is_cjk_char），統計出現頻率
- 排序：頻率降冪 → 同頻按 Unicode 碼位升冪（讓常用字拿到較小的碼位，
  且同頻時結果穩定可重現）
- 依序指派碼位 (lead, trail)：idx 由 0 起，依 cht_common.CODE_POINTS
  順序取用（已避開 scummtr `-c` 會 remap 的 27 個位元組）
- 輸出 JSON：char → {idx, lead, trail}，附產生時間與來源檔清單
"""
import argparse
import datetime
import json
import os
import sys

from cht_common import (
    CODE_POINTS, MAX_CHARS, bytes_to_idx, is_cjk_char, read_mixed_text,
)


def collect_chars(paths):
    """回傳 {字元: 出現次數}，只統計 CJK／全形字元"""
    freq = {}
    for path in paths:
        text = read_mixed_text(path)
        for ch in text:
            if is_cjk_char(ch):
                freq[ch] = freq.get(ch, 0) + 1
    return freq


def build_table(freq):
    """頻率降冪 → Unicode 升冪排序，依序指派碼位"""
    ordered = sorted(freq.items(), key=lambda kv: (-kv[1], ord(kv[0])))
    if len(ordered) > MAX_CHARS:
        raise SystemExit(
            '錯誤：字集共 %d 字，超過碼空間上限 %d，請精簡用字或調整碼空間'
            % (len(ordered), MAX_CHARS))
    chars = {}
    for i, (ch, count) in enumerate(ordered):
        lead, trail = CODE_POINTS[i]
        chars[ch] = {
            'idx': bytes_to_idx(lead, trail),
            'lead': lead,
            'trail': trail,
            'count': count,
        }
    return chars


def main():
    ap = argparse.ArgumentParser(description='從譯文蒐集 CJK 字元，產生 cht_table.json')
    ap.add_argument('inputs', nargs='+', help='譯文文字檔（UTF-8）')
    ap.add_argument('-o', '--output', default='cht_table.json', help='輸出碼表路徑')
    args = ap.parse_args()

    freq = collect_chars(args.inputs)
    chars = build_table(freq)

    table = {
        'generated': datetime.datetime.now().isoformat(timespec='seconds'),
        'sources': [os.path.basename(p) for p in args.inputs],
        'count': len(chars),
        'chars': chars,
    }
    with open(args.output, 'w', encoding='utf-8') as f:
        json.dump(table, f, ensure_ascii=False, indent=1, sort_keys=False)
        f.write('\n')

    print('字集統計：%d 個 CJK 字元（上限 %d）→ %s' % (len(chars), MAX_CHARS, args.output))


if __name__ == '__main__':
    sys.exit(main())
