#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""用 edge-tts 合成中文語音，輸出成可直接餵給 sof_pack.py 的 <offset>.flac。

    tts_synth.py voice_map.json voice_bands.json -o voice/tts [--limit N] [--jobs 4]

每段的聲音與 pitch 由音高帶決定（見 voice_bands.py），所以同一句永遠得到同一組
參數，重跑結果一致。已經產好的檔會跳過，可以分批續跑。

輸出規格對齊原版語音：22,050 Hz 單聲道 FLAC。取樣率不必跟原本那一段一模一樣
（引擎是照 FLAC 檔頭解的），但維持在原版的量級可以避免檔案膨脹太多。
"""
import argparse
import asyncio
import json
import os
import re
import subprocess
import sys

ESC = re.compile(r'\\\d{3}')


def to_speech_text(zh):
    """把譯文裡的排版控制碼換成唸得出來的停頓。

    `\\255\\003` 是換頁（原本要玩家按鍵），語音裡當成句子邊界；
    `^` 在本作顯示成省略號；`@` 是物件名的長度 padding，唸出來只會多一個怪音。
    """
    s = zh.replace('\\255\\003', '。').replace('\\255\\001', '，')
    s = ESC.sub('', s)
    s = s.replace('^', '…').replace('@', '').replace('`', '')
    s = re.sub(r'…{2,}', '…', s)
    return s.strip()


async def synth_one(sem, edge_tts, off, text, voice, pitch, outdir, retries=3):
    mp3 = os.path.join(outdir, f'{off}.mp3')
    flac = os.path.join(outdir, f'{off}.flac')
    if os.path.exists(flac):
        return 'skip'
    async with sem:
        for attempt in range(retries):
            try:
                await edge_tts.Communicate(text, voice, pitch=pitch).save(mp3)
                break
            except Exception as e:
                if attempt == retries - 1:
                    print(f'  {off} 失敗：{e}', file=sys.stderr)
                    return 'fail'
                await asyncio.sleep(2 * (attempt + 1))
    # 音訊規格對齊原版：22,050 Hz 單聲道、**8 bit**。
    # 原版是 1993 年的 8-bit 錄音（ffprobe 的 bits_per_raw_sample=8），FLAC 壓起來
    # 每秒約 7.2 KB。TTS 直出的 24-bit 每秒要 35 KB，全量換完 monster.sof 會從
    # 95 MB 膨脹到 550 MB；降成 8 bit 之後每秒 8.6 KB，總量回到跟原版相當的量級，
    # 而且音色的顆粒感反而更貼近遊戲本身的錄音。
    wav = os.path.join(outdir, f'{off}.wav')
    subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', mp3,
                    '-ar', '22050', '-ac', '1', '-c:a', 'pcm_u8', wav], check=True)
    subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', wav,
                    '-c:a', 'flac', '-compression_level', '12', flac], check=True)
    os.remove(mp3)
    os.remove(wav)
    return 'ok'


async def main_async(args):
    sys.path.insert(0, '/opt/edge/lib')
    import edge_tts

    vm = json.load(open(args.voice_map, encoding='utf-8'))
    bands = json.load(open(args.bands, encoding='utf-8'))
    binfo = bands['bands']
    assign = bands['assign']

    jobs = []
    for off, rec in vm.items():
        zh = rec['zh']
        if not zh.strip():
            continue
        text = to_speech_text(zh)
        if not text:
            continue
        b = binfo[assign.get(off, 4)]
        jobs.append((off, text, b['voice'], b['pitch']))
    if args.limit:
        jobs = jobs[:args.limit]

    os.makedirs(args.output, exist_ok=True)
    sem = asyncio.Semaphore(args.jobs)
    done = {'ok': 0, 'skip': 0, 'fail': 0}
    tasks = [synth_one(sem, edge_tts, o, t, v, p, args.output) for o, t, v, p in jobs]
    for i, coro in enumerate(asyncio.as_completed(tasks), 1):
        done[await coro] += 1
        if i % 100 == 0:
            print(f'  {i}/{len(jobs)}  ok={done["ok"]} skip={done["skip"]} '
                  f'fail={done["fail"]}', file=sys.stderr)
    print(f'合成完成：新增 {done["ok"]}、沿用 {done["skip"]}、失敗 {done["fail"]}')
    return 1 if done['fail'] else 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('voice_map')
    ap.add_argument('bands')
    ap.add_argument('-o', '--output', default='voice/tts')
    ap.add_argument('--limit', type=int, default=0)
    ap.add_argument('--jobs', type=int, default=4, help='同時併發數，太高會被服務端限流')
    args = ap.parse_args()
    sys.exit(asyncio.run(main_async(args)))


if __name__ == '__main__':
    main()
