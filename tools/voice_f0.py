#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""量每段英文原音的基頻，用來決定中文 TTS 的聲音與 pitch。

    voice_f0.py monster.sof voice_map.json -o voice_f0.json [--limit N]

使用者的要求是「人物音調要依照英文語音的音調」。這支不去猜哪句是誰說的——
直接量原音的基頻中位數，後面的合成再依這個值挑基礎聲音與 pitch 偏移。
好處是不必先有角色標註，而且同一句永遠得到同一組參數（決定性）。

基頻用自相關估：只取 RMS 過門檻的 frame（避開靜音與氣音），搜尋範圍
60–400 Hz，並要求自相關峰值高於零延遲值的 30%，濾掉沒有明顯週期的雜訊段。
"""
import argparse
import json
import os
import struct
import subprocess
import sys
import wave

import numpy as np

SILENCE_RMS = 400        # int16 尺度下的靜音門檻
PEAK_RATIO = 0.3         # 自相關峰值 / 零延遲值，低於此視為無週期
F0_MIN, F0_MAX = 60, 400


def read_index(path):
    with open(path, 'rb') as f:
        index_size = struct.unpack('>I', f.read(4))[0]
        raw = f.read(index_size)
    n = index_size // 16
    ent = [struct.unpack('>IIII', raw[i * 16:(i + 1) * 16]) for i in range(n)]
    return ent, index_size + 4


def estimate_f0(wav_path):
    w = wave.open(wav_path)
    sr = w.getframerate()
    d = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(np.float32)
    w.close()
    if len(d) < sr // 10:
        return None, len(d) / sr
    win, hop = 1024, 512
    lo, hi = sr // F0_MAX, sr // F0_MIN
    out = []
    for i in range(0, len(d) - win, hop):
        fr = d[i:i + win]
        if np.sqrt((fr ** 2).mean()) < SILENCE_RMS:
            continue
        fr = fr - fr.mean()
        ac = np.correlate(fr, fr, 'full')[win - 1:]
        if hi >= len(ac):
            continue
        k = int(np.argmax(ac[lo:hi])) + lo
        if ac[k] > PEAK_RATIO * ac[0]:
            out.append(sr / k)
    return (float(np.median(out)) if out else None), len(d) / sr


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('sof')
    ap.add_argument('voice_map')
    ap.add_argument('-o', '--output', default='voice_f0.json')
    ap.add_argument('--limit', type=int, default=0, help='只跑前 N 筆（除錯用）')
    ap.add_argument('--tmp', default='/tmp/voice_f0')
    args = ap.parse_args()

    ent, base = read_index(args.sof)
    table = {e[0]: e for e in ent}
    vm = json.load(open(args.voice_map, encoding='utf-8'))
    targets = [int(k) for k, v in vm.items() if v['text'].strip() and int(k) in table]
    if args.limit:
        targets = targets[:args.limit]

    os.makedirs(args.tmp, exist_ok=True)
    flac = os.path.join(args.tmp, 'a.flac')
    wav = os.path.join(args.tmp, 'a.wav')
    res = {}
    with open(args.sof, 'rb') as f:
        for i, org in enumerate(targets, 1):
            _, new, tags, size = table[org]
            f.seek(base + new + tags)
            with open(flac, 'wb') as g:
                g.write(f.read(size))
            subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', flac,
                            '-ar', '16000', '-ac', '1', wav], check=True)
            f0, dur = estimate_f0(wav)
            res[str(org)] = {'f0': f0, 'dur': round(dur, 3)}
            if i % 200 == 0:
                print(f'  {i}/{len(targets)}', file=sys.stderr)

    json.dump(res, open(args.output, 'w', encoding='utf-8'), ensure_ascii=False)
    vals = np.array([v['f0'] for v in res.values() if v['f0']])
    print(f'{len(res)} 段（{len(vals)} 段量得到 F0）→ {args.output}')
    if len(vals):
        print(f'F0：min {vals.min():.0f}  p25 {np.percentile(vals,25):.0f}  '
              f'中位 {np.median(vals):.0f}  p75 {np.percentile(vals,75):.0f}  '
              f'max {vals.max():.0f} Hz')


if __name__ == '__main__':
    main()
