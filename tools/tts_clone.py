#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""用 F5-TTS 的 zero-shot voice cloning 合成中文語音（需要 GPU）。

    tts_clone.py voice_map.json voice_bands.json refs.json -o out_dir [--limit N]

跟 `tts_synth.py`（edge-tts）產出的是同一種東西——以 `<org_offset>.flac` 命名、
8-bit 22,050 Hz 的 FLAC，可以直接餵給 `sof_pack.py build --replace`。兩者的差別
只在音色來源：

  edge-tts    台灣腔的合成聲音，靠 pitch 對齊原音的音高帶
  F5-TTS      拿英文原音當 reference，讓角色用**自己的聲音**講中文
              （代價是帶著英文母語者的中文口音）

reference 是每個音高帶挑出來的一段 3–8 秒原音（`voice_bands.py --ref-dir`），
所以同一帶的句子音色一致，跨帶則明顯不同。

CPU 上跑得動但很慢（即時率 2–5x）；L40S 這類 GPU 上大約 0.1–0.3x。
"""
import argparse
import json
import os
import re
import subprocess
import sys
import time

ESC = re.compile(r'\\\d{3}')


def clean_ref(t):
    """reference 的英文原文：控制碼換成空白，模型只需要知道那段音在唸什麼。"""
    return ESC.sub(' ', t).replace('^', ' ').replace('`', '').replace('@', '').strip()


def to_speech_text(zh):
    """跟 tts_synth.py 同一套規則，兩個引擎的輸入才是一致的。"""
    s = zh.replace('\\255\\003', '。').replace('\\255\\001', '，')
    s = ESC.sub('', s)
    s = s.replace('^', '…').replace('@', '').replace('`', '')
    s = re.sub(r'…{2,}', '…', s)
    return s.strip()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('voice_map')
    ap.add_argument('bands')
    ap.add_argument('refs')
    ap.add_argument('-o', '--output', default='voice/clone')
    ap.add_argument('--limit', type=int, default=0)
    ap.add_argument('--ref-dir', default=None, help='refs.json 裡 wav 路徑的前綴（換機器時用）')
    args = ap.parse_args()

    import soundfile as sf
    import torch
    from f5_tts.api import F5TTS

    vm = json.load(open(args.voice_map, encoding='utf-8'))
    bands = json.load(open(args.bands, encoding='utf-8'))
    refs = json.load(open(args.refs, encoding='utf-8'))
    assign = bands['assign']

    dev = 'cuda' if torch.cuda.is_available() else 'cpu'
    print(f'device={dev}', file=sys.stderr)
    t0 = time.time()
    model = F5TTS(device=dev)
    print(f'模型載入 {time.time()-t0:.1f}s', file=sys.stderr)

    jobs = []
    for off, rec in vm.items():
        if not rec['zh'].strip():
            continue
        text = to_speech_text(rec['zh'])
        if not text:
            continue
        jobs.append((off, text, str(assign.get(off, 4))))
    if args.limit:
        jobs = jobs[:args.limit]

    os.makedirs(args.output, exist_ok=True)
    ok = skip = fail = 0
    t_start = time.time()
    for i, (off, text, band) in enumerate(jobs, 1):
        flac = os.path.join(args.output, f'{off}.flac')
        if os.path.exists(flac):
            skip += 1
            continue
        r = refs.get(band) or refs['4']
        wav_ref = r['wav']
        if args.ref_dir:
            wav_ref = os.path.join(args.ref_dir, os.path.basename(wav_ref))
        try:
            wav, sr, _ = model.infer(ref_file=wav_ref, ref_text=clean_ref(r['text']),
                                     gen_text=text, remove_silence=False, show_info=lambda *a: None)
        except Exception as e:
            print(f'  {off} 失敗：{e}', file=sys.stderr)
            fail += 1
            continue
        raw = os.path.join(args.output, f'{off}.wav')
        sf.write(raw, wav, sr)
        # 與 edge-tts 那條線同規格：8-bit 22,050 Hz，壓完跟原版同一個量級
        u8 = os.path.join(args.output, f'{off}.u8.wav')
        subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', raw,
                        '-ar', '22050', '-ac', '1', '-c:a', 'pcm_u8', u8], check=True)
        subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', u8,
                        '-c:a', 'flac', '-compression_level', '12', flac], check=True)
        os.remove(raw)
        os.remove(u8)
        ok += 1
        if i % 50 == 0:
            el = time.time() - t_start
            print(f'  {i}/{len(jobs)}  ok={ok} skip={skip} fail={fail}  '
                  f'{el/max(ok,1):.2f}s/句  預估剩 {(len(jobs)-i)*el/max(ok,1)/60:.0f} 分',
                  file=sys.stderr)
    print(f'完成：新增 {ok}、沿用 {skip}、失敗 {fail}')
    return 1 if fail else 0


if __name__ == '__main__':
    sys.exit(main())
