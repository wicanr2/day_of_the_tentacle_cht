#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把同一句台詞的三個版本並排剪成一段對照音檔。

    voice_demo.py voice_map.json -o demo.wav \
        --sof 原音=game-orig/dott/monster.sof \
        --sof 台式中文=game-cht/dott/monster-tw.sof \
        --sof 原音克隆=game-cht/dott/monster-cl.sof \
        --offsets 241851264,242150623,243274831

直接從 .sof 取段拼接，不錄遊戲畫面——錄影會混進配樂與音效，而且 SDL 的
disk driver 不是即時的（75 秒實際時間會寫出 150 秒的音訊），拿來做 A/B
比較會失真。

沒給 `--offsets` 就自動挑：從中文譯文長度 8–25 字、原音 2–6 秒的句子裡，
每個音高帶各取一句，這樣男聲女聲都聽得到。
"""
import argparse
import json
import os
import struct
import subprocess
import sys
import tempfile


def read_sof(path):
    with open(path, 'rb') as f:
        isz = struct.unpack('>I', f.read(4))[0]
        raw = f.read(isz)
    table = {}
    for i in range(isz // 16):
        o, n, t, s = struct.unpack('>IIII', raw[i * 16:(i + 1) * 16])
        table[o] = (n + isz + 4, t, s)
    return table


def extract(sof, table, org, out):
    """取出一段 FLAC，轉成 22,050 Hz 單聲道 wav。找不到就回 False。"""
    if org not in table:
        return False
    base, tags, size = table[org]
    with open(sof, 'rb') as f:
        f.seek(base + tags)
        data = f.read(size)
    flac = out + '.flac'
    with open(flac, 'wb') as g:
        g.write(data)
    subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', flac,
                    '-ar', '22050', '-ac', '1', out], check=True)
    os.remove(flac)
    return True


def pick(vm, bands, tables, n_per_band=1):
    """每個音高帶挑一句：中文 8–25 字、三份都有的。"""
    assign = bands['assign']
    got = {}
    for off, rec in vm.items():
        zh = rec.get('zh', '')
        if not (8 <= len(zh) <= 25):
            continue
        org = int(off)
        if not all(org in t for t in tables):
            continue
        b = assign.get(off, 4)
        got.setdefault(b, []).append(org)
    out = []
    for b in sorted(got):
        out.extend(got[b][:n_per_band])
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('voice_map')
    ap.add_argument('--sof', action='append', required=True,
                    help='標籤=路徑，可重複；順序就是播放順序')
    ap.add_argument('--bands', help='voice_bands.json，用來自動挑句')
    ap.add_argument('--offsets', help='逗號分隔的 org_offset，指定要哪幾句')
    ap.add_argument('-o', '--output', default='voice-demo.wav')
    ap.add_argument('--gap', type=float, default=0.4, help='每個版本之間的靜音秒數')
    args = ap.parse_args()

    labels, paths = [], []
    for spec in args.sof:
        lab, _, p = spec.partition('=')
        labels.append(lab)
        paths.append(p)
    tables = [read_sof(p) for p in paths]
    vm = json.load(open(args.voice_map, encoding='utf-8'))

    if args.offsets:
        offs = [int(x) for x in args.offsets.split(',')]
    else:
        if not args.bands:
            print('沒給 --offsets 就要給 --bands', file=sys.stderr)
            return 2
        offs = pick(vm, json.load(open(args.bands, encoding='utf-8')), tables)
    print(f'{len(offs)} 句 × {len(labels)} 個版本')

    tmp = tempfile.mkdtemp(prefix='vdemo')
    parts = []
    silence = os.path.join(tmp, 'gap.wav')
    subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-f', 'lavfi',
                    '-i', f'anullsrc=r=22050:cl=mono', '-t', str(args.gap),
                    silence], check=True)
    for i, org in enumerate(offs):
        rec = vm.get(str(org), {})
        print(f'  {org}  {rec.get("zh","")[:30]}')
        for j, (lab, p, t) in enumerate(zip(labels, paths, tables)):
            w = os.path.join(tmp, f'{i}-{j}.wav')
            if extract(p, t, org, w):
                parts.append(w)
                parts.append(silence)
        parts.append(silence)      # 句與句之間多一段間隔

    lst = os.path.join(tmp, 'list.txt')
    with open(lst, 'w') as f:
        for p in parts:
            f.write(f"file '{p}'\n")
    subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-f', 'concat',
                    '-safe', '0', '-i', lst, '-ar', '22050', '-ac', '1',
                    args.output], check=True)
    print(f'→ {args.output}')
    print('順序：' + ' / '.join(labels))


if __name__ == '__main__':
    sys.exit(main() or 0)
