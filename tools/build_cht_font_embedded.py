#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
build_cht_font_embedded.py — 用 freetype 讀 WenQuanYi 的 embedded bitmap
（設計師手繪點陣字）烘出更清晰的 12×12 chinese_gb16x12.fnt。

相對 build_cht_font.py（PIL outline 二值化，筆劃細如噪點），本工具：
- 首選：讀 wqy-zenhei.ttc 的 embedded bitmap strike（12px），直接取手繪點陣，
  最銳利。
- 退路：若指定字型無 12px embedded strike，改用 freetype 對 outline 以
  FT_LOAD_TARGET_MONO render 12px（比 PIL 抗鋸齒二值化銳）。

輸出格式（同 build_cht_font.py，對齊 ScummVM charset.cpp ZH_CHN）：
- 無 header；每 glyph 12 列 × 2 bytes = 24 bytes；MSB-first（bit x → 0x80>>x）
- 依碼表 idx 寫進 idx*24；未用碼位保持 0
- 固定 8178 glyphs × 24 = 196272 bytes

用法：
  python3 build_cht_font_embedded.py -t cht_table.json -f wqy-zenhei.ttc -o out.fnt
  python3 build_cht_font_embedded.py -f wqy-zenhei.ttc --list-sizes
  python3 build_cht_font_embedded.py -t cht_table.json -f wqy-zenhei.ttc --dump 我
"""
import argparse
import json
import sys

import freetype

from cht_common import NUM_GLYPHS

GLYPH_SIZE = 12
BYTES_PER_GLYPH = 24
CELL = 12  # 12x12 目標格


def open_face(path, face_index):
    return freetype.Face(path, index=face_index)


def list_strikes(face):
    """回傳 available_sizes 的 (i, width, height) 清單。"""
    out = []
    for i in range(face.num_fixed_sizes):
        sz = face.available_sizes[i]
        out.append((i, sz.width, sz.height))
    return out


def pick_strike(face, target=12):
    """挑最接近 target 高度的 embedded bitmap strike index；沒有回 None。"""
    strikes = list_strikes(face)
    if not strikes:
        return None, strikes
    best = min(strikes, key=lambda s: abs(s[2] - target))
    return best[0], strikes


def render_bits_embedded(face, ch, strike_idx, y_off, x_off):
    """用 embedded bitmap strike 取 ch 的 12x12 0/1 點陣。"""
    face.select_size(strike_idx)
    # 載入並 render；不加 FT_LOAD_NO_BITMAP 讓 embedded bitmap 生效
    face.load_char(ch, freetype.FT_LOAD_RENDER | freetype.FT_LOAD_TARGET_MONO)
    return _blit(face.glyph, y_off, x_off)


def render_bits_mono(face, ch, px, y_off, x_off):
    """退路：對 outline 以 px 大小 MONO render。"""
    face.set_pixel_sizes(0, px)
    face.load_char(ch, freetype.FT_LOAD_RENDER | freetype.FT_LOAD_TARGET_MONO)
    return _blit(face.glyph, y_off, x_off)


def _blit(glyph, y_off, x_off):
    """把 glyph.bitmap（MONO）貼到 12x12 格，回傳 0/1 二維 list。

    baseline 對齊：cell 內 baseline 取第 (CELL-2) 列（descent≈2），
    dst_top = baseline - bitmap_top；可用 y_off 微調。
    """
    bm = glyph.bitmap
    rows, width, pitch = bm.rows, bm.width, bm.pitch
    buf = bm.buffer
    grid = [[0] * CELL for _ in range(CELL)]
    baseline = (CELL - 2)  # 第 10 列為 baseline
    dst_top = baseline - glyph.bitmap_top + y_off
    dst_left = glyph.bitmap_left + x_off
    for sy in range(rows):
        dy = dst_top + sy
        if dy < 0 or dy >= CELL:
            continue
        row_base = sy * pitch
        for sx in range(width):
            byte = buf[row_base + (sx >> 3)]
            bit = (byte >> (7 - (sx & 7))) & 1
            if not bit:
                continue
            dx = dst_left + sx
            if 0 <= dx < CELL:
                grid[dy][dx] = 1
    return grid


def bits_to_bytes(bits):
    out = bytearray()
    row_bytes = (CELL + 7) // 8  # 2
    for row in bits:
        for bi in range(row_bytes):
            b = 0
            for k in range(8):
                x = bi * 8 + k
                if x < CELL and row[x]:
                    b |= 0x80 >> k
            out.append(b)
    return bytes(out)


def dump_ascii(bits):
    return '\n'.join(''.join('#' if v else '.' for v in r) for r in bits)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('-t', '--table')
    ap.add_argument('-f', '--font', required=True)
    ap.add_argument('-o', '--output')
    ap.add_argument('--face-index', type=int, default=0)
    ap.add_argument('--y-offset', type=int, default=0)
    ap.add_argument('--x-offset', type=int, default=0)
    ap.add_argument('--mono', action='store_true',
                    help='強制走 outline MONO render（退路），不用 embedded bitmap')
    ap.add_argument('--px', type=int, default=12, help='MONO render 像素大小')
    ap.add_argument('--list-sizes', action='store_true')
    ap.add_argument('--dump', metavar='CH')
    args = ap.parse_args()

    face = open_face(args.font, args.face_index)

    if args.list_sizes:
        print('face_index=%d family=%r style=%r num_faces=%d'
              % (args.face_index, face.family_name, face.style_name, face.num_faces))
        print('num_fixed_sizes=%d' % face.num_fixed_sizes)
        for i, w, h in list_strikes(face):
            print('  strike[%d] width=%d height=%d' % (i, w, h))
        return 0

    strike_idx, strikes = pick_strike(face, 12)
    use_embedded = (not args.mono) and (strike_idx is not None)

    def render(ch):
        if use_embedded:
            return render_bits_embedded(face, ch, strike_idx, args.y_offset, args.x_offset)
        return render_bits_mono(face, ch, args.px, args.y_offset, args.x_offset)

    mode = ('embedded strike#%d %s' % (strike_idx, strikes[strike_idx][1:])
            if use_embedded else 'outline MONO %dpx' % args.px)

    if args.dump:
        sys.stderr.write('mode: %s\n' % mode)
        print(dump_ascii(render(args.dump)))
        return 0

    if not args.table or not args.output:
        ap.error('需要 -t 與 -o')

    with open(args.table, 'r', encoding='utf-8') as f:
        table = json.load(f)

    buf = bytearray(NUM_GLYPHS * BYTES_PER_GLYPH)
    count = 0
    nonempty = 0
    for ch, ent in table['chars'].items():
        idx = ent['idx']
        if not (0 <= idx < NUM_GLYPHS):
            raise SystemExit('idx 超界: %r idx=%d' % (ch, idx))
        bits = render(ch)
        gb = bits_to_bytes(bits)
        if any(gb):
            nonempty += 1
        buf[idx * BYTES_PER_GLYPH:(idx + 1) * BYTES_PER_GLYPH] = gb
        count += 1

    with open(args.output, 'wb') as f:
        f.write(buf)
    sys.stderr.write('mode: %s\n' % mode)
    print('烘焙完成: %d 字 (%d 非空) → %s (%d bytes)'
          % (count, nonempty, args.output, len(buf)))
    return 0


if __name__ == '__main__':
    sys.exit(main())
