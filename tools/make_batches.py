#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把 scummtr 匯出的原文切成可翻譯的批次（去重）。

同一句原文在遊戲裡常出現很多次（"Bernard" 88 次、"door" 45 次），
去重之後只需要翻一次，回填時再展開回每一行。

流程：
    make_batches.py raw.txt ctx.txt -o translations/dott -n 100
    → translations/dott/b001.tsv … 每行 `原文<TAB>譯文`（譯文欄留空待填）
    merge_batches.py raw.txt translations/dott/*.tsv -o zh.txt

不切出來翻的行（`SKIP` 欄標記）：
  - 去掉語音前綴後是空的（純控制碼）
  - 完全不含英文字母（純數字、純符號）
  - 版本字串、除錯訊息
"""
import argparse
import os
import re
import sys
from collections import Counter

# 句首語音前綴：\255\010 後接兩個 \ddd，可重複數組（本作是四組共 16 bytes）
VOICE_RE = re.compile(r'^(?:\\255\\010(?:\\\d{3}){2})+')

# 不翻的樣態
SKIP_PATTERNS = [
    re.compile(r'^Heap Status'),
    re.compile(r'^WARNING: (Memory low|EMS detects)'),
    re.compile(r'^(Day Of The Tentacle|Maniac Mansion), (CD|Version)', re.I),
    re.compile(r'^[\W\d\\]*$'),          # 沒有任何字母
]


def split_voice(line):
    """回傳 (語音前綴, 本體)"""
    m = VOICE_RE.match(line)
    return (m.group(0), line[m.end():]) if m else ('', line)


def should_skip(body):
    if not body.strip():
        return True
    if not re.search(r'[A-Za-z]', body):
        return True
    return any(p.search(body) for p in SKIP_PATTERNS)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('raw', help='scummtr -of 匯出的原文（無 TAG）')
    ap.add_argument('ctx', nargs='?', help='scummtr -h 匯出的同一份（帶 TAG，只用來標註出處）')
    ap.add_argument('-o', '--outdir', required=True)
    ap.add_argument('-n', '--per-batch', type=int, default=100)
    args = ap.parse_args()

    raw = open(args.raw, 'rb').read().decode('latin-1').split('\r\n')
    ctx = (open(args.ctx, 'rb').read().decode('latin-1').split('\r\n')
           if args.ctx else [''] * len(raw))
    if len(raw) != len(ctx):
        sys.exit(f'行數不一致：raw {len(raw)} vs ctx {len(ctx)}')

    # 去重：原文本體 → (出現次數, 第一次出現的 TAG)
    seen = {}
    order = []
    counts = Counter()
    for r, c in zip(raw, ctx):
        if r.startswith(';;'):
            continue
        _, body = split_voice(r)
        if should_skip(body):
            continue
        counts[body] += 1
        if body not in seen:
            tag = re.match(r'^\[[^\]]+\]', c)
            seen[body] = tag.group(0) if tag else ''
            order.append(body)

    os.makedirs(args.outdir, exist_ok=True)
    n = args.per_batch
    for i in range(0, len(order), n):
        chunk = order[i:i + n]
        path = os.path.join(args.outdir, f'b{i // n + 1:03d}.tsv')
        with open(path, 'w', encoding='utf-8', newline='\n') as f:
            f.write('# 原文\\t譯文　　譯文欄留空 = 沿用原文；escape（\\ddd）與 ^ 原樣保留\n')
            for body in chunk:
                f.write(f'{body}\t\n')
        print(f'{path}  {len(chunk)} 句')

    total_occ = sum(counts[b] for b in order)
    print(f'\n唯一句 {len(order)}，覆蓋 {total_occ} 行；'
          f'批次 {(len(order) + n - 1) // n} 個 → {args.outdir}')


if __name__ == '__main__':
    main()
