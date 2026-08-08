#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""monster.so* 語音包的解包與重打包。

    sof_pack.py list    monster.sof                     列出索引
    sof_pack.py verify  monster.sof                     解包再打包，比對 md5
    sof_pack.py build   monster.sof out.sof --replace 目錄
                                                        用目錄裡的 <offset>.flac 換掉對應語音

檔案格式（由 ScummVM `engines/scumm/sound.cpp` 的 `setupSfxFile()` 與
`startTalkSound()` 推導，並以 byte-perfect 的 round-trip 驗證過）：

    u32be  index_size                       索引區的位元組數
    index_size/16 筆，每筆 16 bytes：
        u32be org_offset                    原始 monster.sou 裡的 offset
        u32be new_offset                    本檔資料區的相對 offset
        u32be num_tags                      嘴型同步時間戳的位元組數
        u32be compressed_size               壓縮音訊的位元組數
    資料區（緊接索引之後，每筆連續排列）：
        [num_tags bytes 的 uint16be 時間戳][compressed_size bytes 的 FLAC]

**`org_offset` 是查表用的 key**：腳本裡每句台詞前面那 16 bytes 控制碼
（四組 `\\xFF\\x0A`）算出來的就是它，`startTalkSound()` 拿它去索引表二分搜尋。
只要重建時保留原本的 `org_offset`，**腳本一個位元組都不用改**——這是中文語音
能夠只換音訊、不動 5,269 行腳本索引的關鍵。

`num_tags` 不一致時引擎只會 warning 並改用索引表的值（同檔 685 行），
所以嘴型時間戳的數量可以調整，不會讓語音播不出來。
"""
import argparse
import hashlib
import os
import struct
import sys


def read_sof(path):
    """→ (entries, items)；items = [(org, sync_bytes, audio_bytes)]"""
    with open(path, 'rb') as f:
        index_size = struct.unpack('>I', f.read(4))[0]
        raw = f.read(index_size)
        n = index_size // 16
        base = index_size + 4
        entries = [struct.unpack('>IIII', raw[i * 16:(i + 1) * 16]) for i in range(n)]
        items = []
        for org, new, tags, size in entries:
            f.seek(base + new)
            items.append((org, f.read(tags), f.read(size)))
    return entries, items


def write_sof(path, items):
    """items = [(org, sync, audio)]，new_offset 依實際內容重算。"""
    idx = bytearray()
    dat = bytearray()
    cur = 0
    for org, sync, audio in items:
        idx += struct.pack('>IIII', org, cur, len(sync), len(audio))
        dat += sync + audio
        cur += len(sync) + len(audio)
    blob = struct.pack('>I', len(idx)) + bytes(idx) + bytes(dat)

    # [雷] 寫之前先斷開連結。game-cht 下的 monster.sof 可能是**硬連結**回
    # game-orig 的同一個 inode，直接 open(...,'wb') 會把原版一起改掉——
    # 而 `ls` 看起來就是一般檔案，只有 st_nlink 會透露。踩過一次。
    if os.path.lexists(path):
        st = os.lstat(path)
        if os.path.islink(path) or st.st_nlink > 1:
            print(f'注意：{path} 是連結（nlink={st.st_nlink}），先移除再寫新檔',
                  file=sys.stderr)
        os.unlink(path)
    with open(path, 'wb') as f:
        f.write(blob)
    return len(blob)


def cmd_list(args):
    entries, _ = read_sof(args.sof)
    print(f'{len(entries)} 筆語音')
    bad = sum(1 for i in range(len(entries) - 1)
              if entries[i][1] + entries[i][2] + entries[i][3] != entries[i + 1][1])
    print(f'佈局連續性：{len(entries)-1} 個相鄰對，不連續 {bad} 個')
    for org, new, tags, size in entries[:args.head]:
        print(f'  org={org:<10} new={new:<10} tags={tags:<4} size={size}')


def cmd_verify(args):
    _, items = read_sof(args.sof)
    tmp = args.sof + '.roundtrip'
    write_sof(tmp, items)
    a = hashlib.md5(open(args.sof, 'rb').read()).hexdigest()
    b = hashlib.md5(open(tmp, 'rb').read()).hexdigest()
    os.unlink(tmp)
    print(f'原始 {a}\n重建 {b}\n{"一致 ✓" if a == b else "不一致 ✗"}')
    return 0 if a == b else 1


def cmd_build(args):
    _, items = read_sof(args.sof)
    repl = {}
    if args.replace:
        for name in os.listdir(args.replace):
            if name.endswith('.flac'):
                repl[int(name.split('.')[0])] = os.path.join(args.replace, name)
    out = []
    n = 0
    for org, sync, audio in items:
        if org in repl:
            audio = open(repl[org], 'rb').read()
            n += 1
        out.append((org, sync, audio))
    size = write_sof(args.out, out)
    print(f'替換 {n} / {len(items)} 筆 → {args.out}（{size/1048576:.1f} MB）')
    if repl and n != len(repl):
        print(f'警告：{len(repl)-n} 個 .flac 的 offset 不在索引表裡', file=sys.stderr)


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest='cmd', required=True)
    p = sub.add_parser('list'); p.add_argument('sof'); p.add_argument('--head', type=int, default=5)
    p.set_defaults(func=cmd_list)
    p = sub.add_parser('verify'); p.add_argument('sof'); p.set_defaults(func=cmd_verify)
    p = sub.add_parser('build'); p.add_argument('sof'); p.add_argument('out')
    p.add_argument('--replace', help='放 <org_offset>.flac 的目錄')
    p.set_defaults(func=cmd_build)
    args = ap.parse_args()
    sys.exit(args.func(args) or 0)


if __name__ == '__main__':
    main()
