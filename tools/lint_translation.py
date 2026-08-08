#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""譯文的一致性檢查（校對第二輪用）。

    lint_translation.py translations/dott/*.tsv

`check_batches.py` 管的是「會讓遊戲出事」的格式；這支管的是「不會出事但讀起來
不對」的東西：

  1. 譯名一致 —— 原文出現 Bernard 而譯文沒有「伯納」，就是漏改或用了別的譯法
  2. 半形標點 —— 中文句子裡混進 , . ! ? : ; " 之類
  3. 物件名過長 —— OBNA 要跟指令組成一行句子，太長會被截
  4. 疑似未翻 —— 譯文與原文完全相同，且原文含 ASCII 字母

每一條都可能有正當的例外（英文專有名詞、刻意保留的原文），所以輸出是**待覆核清單**
而不是錯誤；數量少到可以一條條看完才有意義。
"""
import argparse
import glob
import os
import re
import sys

# 原文關鍵字 → 譯文必須出現的字串之一
NAME_MAP = {
    'Bernard': ['伯納'],
    'Laverne': ['拉玟'],
    'Hoagie': ['霍基'],
    'Dr. Fred': ['佛瑞德'],
    'Doctor Fred': ['佛瑞德'],
    'Edna': ['愛德娜'],
    'Weird Ed': ['怪異愛德'],
    'Purple Tentacle': ['紫色觸手'],
    'Green Tentacle': ['綠色觸手'],
    'Chron-O-John': ['時光廁'],
    'Chron-o-John': ['時光廁'],
    'Washington': ['華盛頓'],
    'Jefferson': ['傑佛遜'],
    'Hancock': ['漢考克'],
    'Franklin': ['富蘭克林'],
    'Betsy Ross': ['貝琪'],
    'Harold': ['哈洛'],
    'Dwayne': ['杜韋恩'],
    'Ozzie': ['奧茲'],
    'Oozo': ['烏佐'],
    'Chuck the Plant': ['查克盆栽'],
}

# 中文之間夾的半形標點（英文詞組內的標點不算）
HALFWIDTH = re.compile(r'[一-鿿][,.!?;:]|[,.!?;:][一-鿿]')
CJK = re.compile(r'[一-鿿]')
HAS_LATIN = re.compile(r'[A-Za-z]{2,}')
ESC = re.compile(r'\\\d{3}')
# 區塊標記：v6 是 [001:OBNA#0042]，v1/v2 是 [001:ONv1#0042]（含小寫），
# 只吃 [A-Z]+ 會整份對照表載成空的，然後安靜退回啟發式判斷。
CTX = re.compile(r'^\[(\d+):([A-Za-z0-9]+)#(\d+)\]')
VOICE = re.compile(r'^(?:\\255\\010(?:\\\d{3}){2})+')


def load_block_types(path):
    """讀 scummtr -h 的 dump，建「原文 → 區塊類型集合」對照。

    區塊類型決定該行在畫面上的角色：OBNA 是物件名（要跟指令組成句子列，得短），
    VERB/SCRP/LSCR 是對白與腳本訊息（長一點無妨）。沒有這份對照就只能靠
    「看起來像不像物件名」猜，30 條裡有 26 條是誤判。
    """
    table = {}
    if not path or not os.path.exists(path):
        return table
    for line in open(path, 'rb').read().decode('latin-1').split('\r\n'):
        if line.startswith(';;'):
            continue
        m = CTX.match(line)
        if not m:
            continue
        body = line[m.end():]
        body = VOICE.sub('', body)
        table.setdefault(body, set()).add(m.group(2))
    return table


def visible_len(s):
    """去掉控制碼後的中文字數（全形算 1，半形算 0.5）"""
    s = ESC.sub('', s).replace('^', '').replace('@', '')
    return sum(1 if ord(c) > 0x2000 else 0.5 for c in s)


def lint(paths, max_obna=8, blocks=None):
    issues = {'譯名': [], '半形標點': [], '物件名過長': [], '疑似未翻': []}
    for p in paths:
        for ln, line in enumerate(open(p, encoding='utf-8'), 1):
            line = line.rstrip('\n')
            if not line or line.startswith('#') or '\t' not in line:
                continue
            src, dst = line.split('\t', 1)
            if not dst.strip():
                continue
            where = f'{p}:{ln}'

            for key, expect in NAME_MAP.items():
                if key in src and not any(e in dst for e in expect):
                    issues['譯名'].append(f'{where} {key} → 譯文沒有 {"/".join(expect)}\n'
                                          f'      {src[:70]}\n      {dst[:70]}')

            if HALFWIDTH.search(dst):
                issues['半形標點'].append(f'{where} {dst[:70]}')

            # 物件名要跟指令組成一行句子列，太長會被截。哪些行是 OBNA 由
            # scummtr -h 的區塊類型決定（--ctx），沒給 ctx 就退回啟發式判斷。
            if blocks:
                # OBNA = SCUMM v6 的物件名；ONv1 = v1/v2 的物件名
                is_obna = bool({'OBNA', 'ONv1'} & blocks.get(src, set()))
            else:
                is_obna = (len(src) <= 30 and not ESC.search(src)
                           and not src.rstrip('@').endswith(('.', '!', '?')))
            if is_obna and CJK.search(dst) and visible_len(dst) > max_obna:
                issues['物件名過長'].append(f'{where} {visible_len(dst):.0f} 字　{src[:40]} → {dst[:40]}')

            if src == dst and HAS_LATIN.search(src):
                issues['疑似未翻'].append(f'{where} {src[:70]}')
    return issues


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('files', nargs='+')
    ap.add_argument('--max-obna', type=int, default=8)
    ap.add_argument('--ctx', help='scummtr -h 產的 dump，用來判斷哪些行是 OBNA')
    args = ap.parse_args()

    paths = []
    for pat in args.files:
        paths.extend(sorted(glob.glob(pat)) or [pat])

    issues = lint(paths, args.max_obna, load_block_types(args.ctx))
    total = 0
    for kind, items in issues.items():
        if not items:
            continue
        total += len(items)
        print(f'\n=== {kind}（{len(items)}）===')
        for it in items:
            print('  • ' + it)
    print(f'\n{len(paths)} 個批次，待覆核 {total} 條'
          if total else f'\n{len(paths)} 個批次，四項檢查全過')
    return 0


if __name__ == '__main__':
    sys.exit(main())
