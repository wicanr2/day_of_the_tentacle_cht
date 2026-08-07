#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""產生小樣譯文：只翻指令列與開場幾句，其餘保留原文。

用途是先驗證「碼空間 → 字型 → 回填 → 顯示」整條路徑，
在投入全量翻譯之前確認中文真的畫得出來、不撞碼、不截字。

輸入：dumps/dott_raw.txt（無 TAG，回填用）、dumps/dott_ctx.txt（有 TAG，定位用）
輸出：dumps/dott_sample_zh.txt（UTF-8，供 cht_codec encode-file）
"""
import re
import sys

RAW = sys.argv[1] if len(sys.argv) > 1 else 'dumps/dott_raw.txt'
CTX = sys.argv[2] if len(sys.argv) > 2 else 'dumps/dott_ctx.txt'
OUT = sys.argv[3] if len(sys.argv) > 3 else 'dumps/dott_sample_zh.txt'

# 指令列與介系詞。key 是原文 body（去掉語音前綴後的完整內容）
VERBS = {
    'Walk to': '走到',
    'Give': '給予',
    'Open': '打開',
    'Close': '關上',
    'Pick up': '拿起',
    'L\xb0k at': '查看',      # 原文用 0xB0 當 "oo" 合字
    'Talk to': '交談',
    'Use': '使用',
    'Push': '推',
    'Pu\xb8': '拉',           # 原文用 0xB8 當 "ll" 合字
    'in': '放進',
    'with': '用',
    'on': '在',
    'to': '給',
}

# 開場動畫的幾句（用原文全文比對，避免誤傷）
LINES = {
    "I don't think you should drink that^": '我看你最好別喝那個……',
    'It looks bad for you.': '看起來對身體不太好。',
    'It makes me feel GREAT!\\255\\003Smarter!  More aggressive!':
        '我覺得棒透了！\\255\\003更聰明！更有侵略性！',
    'I feel like I could^': '我覺得我可以……',
    '^like^\\255\\003^I^\\255\\003^could^': '……好像……\\255\\003……我……\\255\\003……可以……',
    'TAKE ON \\255\\003THE WORLD!!!': '征服\\255\\003全世界！！！',
    "Look, Hoagie, it's a hamster!": '你看，霍基，是隻倉鼠！',
    'Just what I need for dissection lab tomorrow!': '正好給我明天解剖課用！',
    'Hands off that hamster!': '別碰那隻倉鼠！',
}

VOICE = re.compile(r'^(?:\\255\\010(?:\\\d{3}){2})+')


def main():
    raw = open(RAW, 'rb').read().split(b'\r\n')
    ctx = open(CTX, 'rb').read().split(b'\r\n')
    if len(raw) != len(ctx):
        sys.exit(f'行數不一致：raw {len(raw)} vs ctx {len(ctx)}')

    out = []
    n_verb = n_line = 0
    for r in raw:
        s = r.decode('latin-1')
        m = VOICE.match(s)
        prefix, body = (m.group(0), s[m.end():]) if m else ('', s)

        if body in VERBS:
            out.append(prefix + VERBS[body])
            n_verb += 1
        elif body in LINES:
            out.append(prefix + LINES[body])
            n_line += 1
        else:
            out.append(s)

    open(OUT, 'w', encoding='utf-8', newline='').write('\r\n'.join(out))
    print(f'指令列替換 {n_verb} 行、對白替換 {n_line} 行，共輸出 {len(out)} 行 → {OUT}')


if __name__ == '__main__':
    main()
