#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把翻好的批次 TSV 併回 scummtr 可回填的完整檔。

    merge_batches.py raw.txt translations/dott/*.tsv -o dumps/dott_zh.txt

規則：
  - 逐行對位，行數與原檔完全一致（scummtr 不收多行少行）
  - 句首語音前綴原樣保留（本作 16 bytes，動到就對不上 monster.sof）
  - 譯文欄留空 = 沿用原文
  - 同一句原文在多行出現時，全部套用同一則譯文
"""
import argparse
import glob
import re
import sys

VOICE_RE = re.compile(r'^(?:\\255\\010(?:\\\d{3}){2})+')


def split_voice(line):
    m = VOICE_RE.match(line)
    return (m.group(0), line[m.end():]) if m else ('', line)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('raw')
    ap.add_argument('tsv', nargs='+', help='批次檔（可用萬用字元）')
    ap.add_argument('-o', '--output', required=True)
    args = ap.parse_args()

    paths = []
    for pat in args.tsv:
        paths.extend(sorted(glob.glob(pat)) or [pat])

    table = {}
    dup = 0
    for p in paths:
        for ln, line in enumerate(open(p, encoding='utf-8'), 1):
            line = line.rstrip('\n')
            if not line or line.startswith('#'):
                continue
            if '\t' not in line:
                sys.exit(f'{p}:{ln} 缺少 TAB 分隔')
            src, dst = line.split('\t', 1)
            if not dst.strip():
                continue
            if src in table and table[src] != dst:
                dup += 1
            table[src] = dst

    raw = open(args.raw, 'rb').read().decode('latin-1').split('\r\n')
    out, n_hit = [], 0
    for r in raw:
        if r.startswith(';;'):
            out.append(r)
            continue
        prefix, body = split_voice(r)
        if body in table:
            out.append(prefix + table[body])
            n_hit += 1
        else:
            out.append(r)

    open(args.output, 'w', encoding='utf-8', newline='').write('\r\n'.join(out))
    print(f'譯文 {len(table)} 則 → 命中 {n_hit} 行 / 共 {len(out)} 行 → {args.output}')
    if dup:
        print(f'警告：{dup} 則原文在不同批次有不一致的譯文，後者覆蓋前者', file=sys.stderr)


if __name__ == '__main__':
    main()
