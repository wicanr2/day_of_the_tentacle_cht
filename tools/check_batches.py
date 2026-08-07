#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""檢查翻譯批次（TSV）的格式，翻完一批就跑。

    check_batches.py translations/dott/*.tsv

檢查項目（任何一項不過就是會在遊戲裡出事的）：
  1. TAB 欄位數 —— 必須恰好一個 TAB
  2. escape 序列 \\ddd —— 譯文必須與原文完全相同（順序也是）；
     它們是控制碼與語音索引，動到就換行錯亂或語音對不上
  3. `^` 的數量 —— 顯示成省略號／停頓，少一個畫面就變樣
  4. 反引號 ` 的數量 —— 原文用它當引號
  5. 譯文不得含 0xA1–0xFD 範圍的單一 latin-1 字元 ——
     CJK 模式下會被引擎當成雙位元組首碼，整段錯位
  6. 譯文不得含半形 TAB／控制字元
"""
import glob
import re
import sys

ESC = re.compile(r'\\\d{3}')
BAD_LATIN1 = re.compile(r'[¡-ý]')


def check_file(path):
    problems = []
    n_done = n_total = 0
    for ln, line in enumerate(open(path, encoding='utf-8'), 1):
        line = line.rstrip('\n')
        if not line or line.startswith('#'):
            continue
        n_total += 1
        if line.count('\t') != 1:
            problems.append(f'{path}:{ln} TAB 數量 {line.count(chr(9))}，應為 1')
            continue
        src, dst = line.split('\t')
        if not dst.strip():
            continue
        n_done += 1

        if ESC.findall(src) != ESC.findall(dst):
            problems.append(f'{path}:{ln} escape 不一致\n'
                            f'      原文 {ESC.findall(src)}\n      譯文 {ESC.findall(dst)}')
        if src.count('^') != dst.count('^'):
            problems.append(f'{path}:{ln} `^` 數量 {src.count("^")} → {dst.count("^")}')
        if src.count('`') != dst.count('`'):
            problems.append(f'{path}:{ln} 反引號數量 {src.count("`")} → {dst.count("`")}')
        bad = BAD_LATIN1.findall(dst)
        if bad:
            problems.append(f'{path}:{ln} 譯文含會撞碼的 latin-1 字元 {bad}（間隔號要用 ・ U+30FB）')
        if any(ord(c) < 0x20 for c in dst):
            problems.append(f'{path}:{ln} 譯文含控制字元')
    return problems, n_done, n_total


def main():
    paths = []
    for pat in sys.argv[1:]:
        paths.extend(sorted(glob.glob(pat)) or [pat])
    if not paths:
        sys.exit('用法: check_batches.py <批次檔...>')

    all_problems, done, total = [], 0, 0
    for p in paths:
        pr, d, t = check_file(p)
        all_problems += pr
        done += d
        total += t

    for p in all_problems:
        print('  ✗ ' + p)
    pct = done * 100 / total if total else 0
    print(f'\n{len(paths)} 個批次：已翻 {done} / {total} 句（{pct:.1f}%），'
          f'{"格式全數通過" if not all_problems else f"{len(all_problems)} 個問題"}')
    return 1 if all_problems else 0


if __name__ == '__main__':
    sys.exit(main())
