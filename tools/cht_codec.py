#!/usr/bin/env python3
# -*- coding: utf-8 -*-
r"""
cht_codec.py — 字串 ↔ 自訂雙位元組碼空間編解碼

用法：
    python3 cht_codec.py encode-file -t cht_table.json 輸入.txt 輸出.txt
    python3 cht_codec.py decode-file -t cht_table.json 輸入.txt 輸出.txt

設計要點：
- encode-file：讀 UTF-8 譯文（容許混入 latin-1 高位元組，見
  cht_common.read_mixed_text），輸出給 scummtr `-if` 用的位元組檔
  （latin-1 語意，CRLF 原樣保留）
    - ASCII（< 0x80）原樣輸出
    - CJK 字元依 cht_table.json 查 (lead, trail) 輸出 2 bytes
    - 其餘 U+0080–U+00FF 字元（匯出檔遺留的 latin-1）原樣輸出 1 byte
    - scummtr 的 escape 序列（\255\010 等）在文字檔中本就是 ASCII
      字元，自然原樣通過，不需特別處理
- decode-file：反向操作，把 encode-file 的產出還原成 UTF-8 文字。
  只認 raw 位元組對，不展開 \ddd escape——重新匯出的檔案裡
  語音 offset 等位元組也是以 \ddd 表示，胡亂展開會誤配對；
  scummtr round-trip 驗證請改用「雙方展開 escape 後比位元組」的方式。
- 碼表 lead/trail 已避開 scummtr `-c` 會 remap 的 27 個位元組
  （見 cht_common.FORBIDDEN_BYTES）；匯出檔遺留的 raw 高位元組
  必屬該集合，故不會與 CJK 位元組對誤配。
"""
import argparse
import json
import sys

from cht_common import read_mixed_text


def load_table(path):
    """讀碼表，回傳 (char→(lead,trail), (lead,trail)→char) 兩個映射"""
    with open(path, 'r', encoding='utf-8') as f:
        table = json.load(f)
    enc = {}
    dec = {}
    for ch, ent in table['chars'].items():
        lead, trail = ent['lead'], ent['trail']
        enc[ch] = (lead, trail)
        dec[(lead, trail)] = ch
    return enc, dec


def encode_text(text, enc, path='<input>'):
    """str → bytes；遇碼表缺字立即報錯並指出行號"""
    out = bytearray()
    line_no = 1
    for ch in text:
        cp = ord(ch)
        if ch == '\n':
            line_no += 1
        if cp < 0x80:
            out.append(cp)
        elif ch in enc:
            lead, trail = enc[ch]
            out.append(lead)
            out.append(trail)
        elif cp <= 0xFF:
            # 匯出檔遺留的 latin-1 高位元組，原樣通過
            out.append(cp)
        else:
            raise SystemExit(
                '錯誤：%s 第 %d 行字元 %r (U+%04X) 不在碼表中，'
                '請先重跑 collect_charset.py' % (path, line_no, ch, cp))
    return bytes(out)


def decode_text(data, dec):
    """bytes → str；raw 位元組對查表還原，其餘以 latin-1 原樣保留"""
    out = []
    i = 0
    n = len(data)
    while i < n:
        b = data[i]
        if 0xA1 <= b <= 0xFD and i + 1 < n and 0xA1 <= data[i + 1] <= 0xFD:
            ch = dec.get((b, data[i + 1]))
            if ch is not None:
                out.append(ch)
                i += 2
                continue
        out.append(chr(b))
        i += 1
    return ''.join(out)


def main():
    ap = argparse.ArgumentParser(description='自訂雙位元組碼空間編解碼')
    ap.add_argument('mode', choices=['encode-file', 'decode-file'])
    ap.add_argument('-t', '--table', required=True, help='cht_table.json 路徑')
    ap.add_argument('input', help='輸入檔')
    ap.add_argument('output', help='輸出檔')
    args = ap.parse_args()

    enc, dec = load_table(args.table)

    if args.mode == 'encode-file':
        text = read_mixed_text(args.input)
        data = encode_text(text, enc, args.input)
        with open(args.output, 'wb') as f:
            f.write(data)
        print('編碼完成：%s → %s（%d bytes）' % (args.input, args.output, len(data)))
    else:
        with open(args.input, 'rb') as f:
            data = f.read()
        text = decode_text(data, dec)
        with open(args.output, 'w', encoding='utf-8', newline='') as f:
            f.write(text)
        print('解碼完成：%s → %s（%d 字元）' % (args.input, args.output, len(text)))


if __name__ == '__main__':
    sys.exit(main())
