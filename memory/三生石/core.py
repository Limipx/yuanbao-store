# -*- coding: utf-8 -*-
"""从 MEMORY.md 抽出「永远不能忘」的核心层（孟婆汤解药）"""
import re, os
src = open('/data/workspace/_memory/MEMORY.md', encoding='utf-8').read()
lines = src.split('\n')
KEEP = re.compile(r'(⛔|★★|★|红线|铁律|纪律|废除|禁止|必须|绝不|血泪|踩过|实证|真机确认|不可用|已废)')
out, buf, keep = [], [], False
cur_level = 0
for ln in lines:
    m = re.match(r'^(#{1,6})\s+(.*)$', ln)
    if m:
        lvl, title = len(m.group(1)), m.group(2)
        if keep:
            out.extend(buf)
        buf = []
        keep = bool(KEEP.search(title)) and lvl <= 3
        cur_level = lvl
    if keep:
        buf.append(ln)
if keep:
    out.extend(buf)
txt = '\n'.join(out).strip()
# 去掉长代码块，保留结论
txt = re.sub(r'```[\s\S]{600,}?```', '```（略）```', txt)
open('核心层.md', 'w', encoding='utf-8').write(txt)
print('核心层 字节:', len(txt.encode('utf-8')), ' 行数:', txt.count('\n')+1)
print('占原 MEMORY 比例: %.1f%%' % (len(txt.encode()) / len(src.encode()) * 100))
