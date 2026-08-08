#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把語音依原音基頻分成音高帶，並替每帶挑一段參考音。

    voice_bands.py voice_f0.json voice_map.json monster.sof -o bands.json \
                   [--ref-dir voice/ref]

為什麼是「分帶」而不是「認角色」：遊戲資料裡沒有「哪句是誰說的」，而使用者要的
是**音調貼近英文原音**。分帶同時解決兩件事——同一角色的句子多半落在同一帶，
聽感一致；而帶的中心頻率就是那組句子該有的音高。

帶的邊界取 edge-tts 三個台灣聲音的實測覆蓋範圍（YunJhe 82–140 Hz、
HsiaoYu 138–239 Hz、HsiaoChen 158–271 Hz），讓每一帶都落在某個聲音
加減 40 Hz 就能達到的位置。

`--ref-dir` 會替每帶輸出一段參考音（wav）與其英文原文，給 voice cloning 引擎
（F5-TTS 之類）當 reference 用。挑的是該帶裡長度 3–8 秒、字數適中的句子。
"""
import argparse
import json
import os
import struct
import subprocess

# (下界, 上界, edge-tts 聲音, pitch)
BANDS = [
    (0,   95,   'zh-TW-YunJheNeural',    '-40Hz'),
    (95,  105,  'zh-TW-YunJheNeural',    '-30Hz'),
    (105, 118,  'zh-TW-YunJheNeural',    '-10Hz'),
    (118, 132,  'zh-TW-YunJheNeural',    '+10Hz'),
    (132, 150,  'zh-TW-YunJheNeural',    '+40Hz'),
    (150, 175,  'zh-TW-HsiaoYuNeural',   '-30Hz'),
    (175, 200,  'zh-TW-HsiaoChenNeural', '-30Hz'),
    (200, 228,  'zh-TW-HsiaoChenNeural', '-5Hz'),
    (228, 255,  'zh-TW-HsiaoChenNeural', '+20Hz'),
    (255, 1e9,  'zh-TW-HsiaoChenNeural', '+40Hz'),
]


def band_of(f0):
    if f0 is None:
        return 4          # 量不到就丟中間偏低的男聲帶
    for i, (lo, hi, _, _) in enumerate(BANDS):
        if lo <= f0 < hi:
            return i
    return len(BANDS) - 1


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('f0')
    ap.add_argument('voice_map')
    ap.add_argument('sof')
    ap.add_argument('-o', '--output', default='bands.json')
    ap.add_argument('--ref-dir')
    args = ap.parse_args()

    f0 = json.load(open(args.f0, encoding='utf-8'))
    vm = json.load(open(args.voice_map, encoding='utf-8'))

    assign = {}
    per_band = [[] for _ in BANDS]
    for off, rec in f0.items():
        b = band_of(rec['f0'])
        assign[off] = b
        per_band[b].append((off, rec['f0'] or 0, rec['dur']))

    out = {
        'bands': [{'lo': lo, 'hi': None if hi > 1e8 else hi, 'voice': v, 'pitch': p,
                   'count': len(per_band[i])}
                  for i, (lo, hi, v, p) in enumerate(BANDS)],
        'assign': assign,
    }
    json.dump(out, open(args.output, 'w', encoding='utf-8'), ensure_ascii=False)
    print(f'{len(assign)} 段分到 {len(BANDS)} 帶 → {args.output}')
    for i, (lo, hi, v, p) in enumerate(BANDS):
        print(f'  帶{i} {lo:>3}-{"+" if hi>1e8 else int(hi):>4} Hz  '
              f'{v.split("-")[2]:<12}{p:>6}  {len(per_band[i]):>5} 句')

    if not args.ref_dir:
        return
    os.makedirs(args.ref_dir, exist_ok=True)
    with open(args.sof, 'rb') as f:
        isz = struct.unpack('>I', f.read(4))[0]
        raw = f.read(isz)
        base = isz + 4
        table = {}
        for i in range(isz // 16):
            o, n, t, s = struct.unpack('>IIII', raw[i * 16:(i + 1) * 16])
            table[o] = (n, t, s)

        refs = {}
        for i, items in enumerate(per_band):
            # 挑 3–8 秒、原文長度適中的：太短沒有足夠的音色資訊，太長容易夾雜音效
            cand = [(o, d) for o, _, d in items
                    if 3.0 <= d <= 8.0 and 25 <= len(vm[o]['text']) <= 90]
            if not cand:
                cand = [(o, d) for o, _, d in items if 1.5 <= d <= 12.0]
            if not cand:
                print(f'  帶{i} 沒有合適的參考音')
                continue
            org = int(cand[len(cand) // 2][0])
            n, t, s = table[org]
            f.seek(base + n + t)
            flac = os.path.join(args.ref_dir, f'band{i}.flac')
            wav = os.path.join(args.ref_dir, f'band{i}.wav')
            open(flac, 'wb').write(f.read(s))
            subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', flac,
                            '-ar', '24000', '-ac', '1', wav], check=True)
            os.remove(flac)
            refs[str(i)] = {'offset': org, 'text': vm[str(org)]['text'], 'wav': wav}
            print(f'  帶{i} 參考音 offset={org}  {vm[str(org)]["text"][:50]!r}')
        json.dump(refs, open(os.path.join(args.ref_dir, 'refs.json'), 'w',
                             encoding='utf-8'), ensure_ascii=False, indent=1)


if __name__ == '__main__':
    main()
