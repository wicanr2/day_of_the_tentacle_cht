# -*- coding: utf-8 -*-
"""
cht_common.py — 妙探闖通關（Sam & Max）中文化：碼空間共用定義

本模組集中定義自訂雙位元組碼空間的硬規則，供
collect_charset.py / cht_codec.py / build_cht_font.py 共用，
避免三處各自維護而漂移。

碼空間規則（對齊 ScummVM charset.cpp ZH_CHN 路徑）：
- 每個中文字元編成 2 個位元組 (lead, trail)，檔案順序為 [lead][trail]
- 引擎索引公式：idx = (lead - 0xA1) * 94 + (trail - 0xA1)
- 字型檔 chinese_gb16x12.fnt 固定 8178 glyphs（每 glyph 24 bytes），
  故 idx 必須 ≤ 8177，亦即 lead ≤ 0xF7
- lead/trail 皆須落在 0xA1–0xFD（避開 0xFE/0xFF 控制碼前導）

scummtr `-c`（Windows-1252）匯入時會把若干高位元組 remap 成別的遊戲位元組
（text.cpp CT_V3_WIN1252 → _finalCharset），共 27 個位元組不可用作
lead/trail，否則寫進遊戲的位元組會與碼表不符（撞碼）。
"""

# scummtr `-c` 模式會 remap 的高位元組（不可用作 lead/trail）
FORBIDDEN_BYTES = frozenset([
    0xA9,
    0xC4, 0xC6, 0xC7, 0xC9,
    0xD6, 0xDC,
    0xDF,
    0xE0, 0xE1, 0xE2, 0xE4, 0xE6, 0xE7, 0xE8, 0xE9, 0xEA, 0xEB, 0xEC, 0xEE, 0xEF,
    0xF2, 0xF4, 0xF6, 0xF9, 0xFB, 0xFC,
])

LEAD_MIN, LEAD_MAX = 0xA1, 0xF7    # lead 上限由 idx < 8178 推出
TRAIL_MIN, TRAIL_MAX = 0xA1, 0xFD

NUM_GLYPHS = 8178                  # 字型檔 glyph 總數（引擎 numChar）
FONT_FILE_SIZE = NUM_GLYPHS * 24   # 196,272 bytes

# 依 idx 順序可用的 (lead, trail) 清單：idx 小的排前面，指派碼位時依序取用
ALLOWED_LEADS = [b for b in range(LEAD_MIN, LEAD_MAX + 1) if b not in FORBIDDEN_BYTES]
ALLOWED_TRAILS = [b for b in range(TRAIL_MIN, TRAIL_MAX + 1) if b not in FORBIDDEN_BYTES]
CODE_POINTS = [(lead, trail) for lead in ALLOWED_LEADS for trail in ALLOWED_TRAILS]
MAX_CHARS = len(CODE_POINTS)       # 63 * 66 = 4158


def bytes_to_idx(lead, trail):
    """(lead, trail) → 引擎字型索引（對齊 ZH_CHN 公式）"""
    return (lead - 0xA1) * 94 + (trail - 0xA1)


def read_mixed_text(path):
    """
    讀取「UTF-8 為主、可能混入少數 latin-1 高位元組」的文字檔。

    scummtr 匯出檔內含少數 raw latin-1 位元組（如 0xE9/0xEB），
    直接 decode('utf-8') 會失敗。這裡逐段嘗試 UTF-8 解碼，
    失敗的單一位元組以 latin-1 字元保留（U+0080–U+00FF），
    讓後續編碼器能原樣放回該位元組。
    回傳 Python str（CRLF 保留為 \r\n 字元，不做換行轉換）。
    """
    data = open(path, 'rb').read()
    out = []
    i = 0
    n = len(data)
    while i < n:
        b = data[i]
        if b < 0x80:
            out.append(chr(b))
            i += 1
        else:
            # 嘗試 UTF-8 多位元組序列（2–4 bytes）
            decoded = None
            for length in (2, 3, 4):
                if i + length <= n:
                    try:
                        decoded = data[i:i + length].decode('utf-8')
                    except UnicodeDecodeError:
                        continue
                    break
            if decoded is not None:
                out.append(decoded)
                i += length
            else:
                # 無效 UTF-8：視為 raw latin-1 位元組原樣保留
                out.append(chr(b))
                i += 1
    return ''.join(out)


def is_cjk_char(ch):
    """判定是否為需要編入碼表的 CJK／全形字元"""
    cp = ord(ch)
    return (
        0x4E00 <= cp <= 0x9FFF or      # CJK Unified Ideographs
        0x3400 <= cp <= 0x4DBF or      # Extension A
        0x3000 <= cp <= 0x303F or      # CJK 標點（。「」『』、…等）
        0xFF00 <= cp <= 0xFFEF or      # 全形英數與標點
        cp == 0x30FB or                # ・ 片假名中點：人名間隔號（字形居中，優於 U+00B7）
        0x00A0 <= cp <= 0x00FF or      # latin-1 補充：外語殘留字（Flambé 的 é、原文 ëëë 等）
        cp in (0x2014, 0x2026)         # —（破折號）、…（刪節號，部分字型放在 U+2026）
    )
