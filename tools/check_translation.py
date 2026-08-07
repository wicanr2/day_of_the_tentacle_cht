#!/usr/bin/env python3
# 翻譯批次校驗：比對英文原文檔與繁中譯文檔的結構一致性
# 用法: python3 check_translation.py <原文chunk> <譯文chunk>
# 檢查: 行數一致、註解行一致、TAG 序列一致、每行 \ddd escape 多重集一致、OBNA padding 存在
import re
import sys

TAG_RE = re.compile(r'^\[(\d{3}:[A-Z]+#\d+)\]')
ESC_RE = re.compile(r'\\(\d{3})')


def read_lines(path, encoding):
    with open(path, 'rb') as f:
        data = f.read()
    text = data.decode(encoding)
    lines = re.split(r'\r\n|\n', text)
    while lines and lines[-1] == '':
        lines.pop()
    return lines


def main():
    if len(sys.argv) != 3:
        print('用法: check_translation.py <原文> <譯文>')
        return 2
    en = read_lines(sys.argv[1], 'latin-1')
    cht = read_lines(sys.argv[2], 'utf-8')
    errors = []

    if len(en) != len(cht):
        errors.append(f'行數不一致: 原文 {len(en)} vs 譯文 {len(cht)}')
        # 行數不同時後續逐行比對無意義，直接結束
        report(errors)
        return 1

    tag_mismatch = esc_mismatch = comment_mismatch = pad_missing = 0
    for i, (e, c) in enumerate(zip(en, cht), 1):
        if e.startswith(';;'):
            if e != c:
                comment_mismatch += 1
                errors.append(f'L{i}: 註解行被更動')
            continue
        et = TAG_RE.match(e)
        ct = TAG_RE.match(c)
        if bool(et) != bool(ct) or (et and et.group(1) != ct.group(1)):
            tag_mismatch += 1
            errors.append(f'L{i}: TAG 不一致: {et.group(1) if et else e[:30]!r} vs {ct.group(1) if ct else c[:30]!r}')
            continue
        e_esc = sorted(ESC_RE.findall(e))
        c_esc = sorted(ESC_RE.findall(c))
        if e_esc != c_esc:
            esc_mismatch += 1
            errors.append(f'L{i}: escape 不一致: 原文{e_esc} vs 譯文{c_esc}')
        if '@' in e and '@' not in c:
            pad_missing += 1
            errors.append(f'L{i}: 原文有 @ padding 但譯文遺失')

    report(errors)
    if errors:
        print(f'FAIL: tag={tag_mismatch} esc={esc_mismatch} comment={comment_mismatch} pad={pad_missing}')
        return 1
    print(f'OK: {len(en)} 行結構一致')
    return 0


def report(errors):
    for msg in errors[:50]:
        print(' ', msg)
    if len(errors) > 50:
        print(f'  ...另 {len(errors) - 50} 條未列出')


if __name__ == '__main__':
    sys.exit(main())
