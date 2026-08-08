#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把合成語音的響度對齊原版每一段的音量。

    voice_normalize.py monster.sof voice_dir [--target-headroom 0.9]

為什麼需要這一步：實機錄音比對發現，同一段落原版的 RMS 是 1,835，換上 TTS 之後
只剩 477——聽起來就是「語音變小聲了」。原因是 1993 年的錄音經過壓縮、動態範圍窄，
而 TTS 直出的動態範圍寬、平均音量低。

做法是逐段量原版的 RMS，把對應的中文語音線性放大到同一個 RMS，再用峰值上限
（預設 0.9 滿刻度）夾住避免削波。逐段而不是整批統一，是因為原版本身各段音量
就不一樣——耳語跟大吼不該被拉成一樣大。
"""
import argparse
import json
import os
import struct
import subprocess
import sys
import wave

import numpy as np


def read_index(path):
    with open(path, 'rb') as f:
        isz = struct.unpack('>I', f.read(4))[0]
        raw = f.read(isz)
    n = isz // 16
    return [struct.unpack('>IIII', raw[i * 16:(i + 1) * 16]) for i in range(n)], isz + 4


def flac_stats(path, tmp):
    """→ (rms, peak)，都是 0–1 的相對值"""
    subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', path,
                    '-ar', '22050', '-ac', '1', '-c:a', 'pcm_s16le', tmp], check=True)
    w = wave.open(tmp)
    d = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(np.float32)
    w.close()
    if len(d) == 0:
        return 0.0, 0.0
    return float(np.sqrt((d ** 2).mean()) / 32768), float(np.abs(d).max() / 32768)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('sof')
    ap.add_argument('voice_dir')
    ap.add_argument('--target-headroom', type=float, default=0.9)
    ap.add_argument('--max-gain', type=float, default=8.0, help='放大倍率上限，避免把靜音段的雜訊拉爆')
    ap.add_argument('--tmp', default='/tmp/vnorm')
    args = ap.parse_args()

    ent, base = read_index(args.sof)
    table = {e[0]: e for e in ent}
    os.makedirs(args.tmp, exist_ok=True)
    ref_flac = os.path.join(args.tmp, 'ref.flac')
    ref_wav = os.path.join(args.tmp, 'ref.wav')
    cur_wav = os.path.join(args.tmp, 'cur.wav')
    out_wav = os.path.join(args.tmp, 'out.wav')

    files = sorted(x for x in os.listdir(args.voice_dir) if x.endswith('.flac'))
    gains = []
    with open(args.sof, 'rb') as f:
        for i, name in enumerate(files, 1):
            org = int(name.split('.')[0])
            if org not in table:
                continue
            _, new, tags, size = table[org]
            f.seek(base + new + tags)
            with open(ref_flac, 'wb') as g:
                g.write(f.read(size))
            r_rms, _ = flac_stats(ref_flac, ref_wav)

            path = os.path.join(args.voice_dir, name)
            c_rms, c_peak = flac_stats(path, cur_wav)
            if c_rms <= 0 or r_rms <= 0:
                continue
            gain = min(r_rms / c_rms, args.max_gain)
            if c_peak * gain > args.target_headroom:      # 夾住避免削波
                gain = args.target_headroom / c_peak
            gains.append(gain)
            if abs(gain - 1.0) < 0.05:
                continue
            subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', cur_wav,
                            '-af', f'volume={gain:.4f}', '-c:a', 'pcm_u8', out_wav], check=True)
            subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', out_wav,
                            '-c:a', 'flac', '-compression_level', '12', path], check=True)
            if i % 200 == 0:
                print(f'  {i}/{len(files)}  中位增益 {np.median(gains):.2f}x', file=sys.stderr)

    g = np.array(gains)
    print(f'{len(g)} 段對齊完成：增益 中位 {np.median(g):.2f}x  '
          f'p10 {np.percentile(g,10):.2f}  p90 {np.percentile(g,90):.2f}  max {g.max():.2f}')


if __name__ == '__main__':
    main()
