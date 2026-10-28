# -*- coding: utf-8 -*-
"""刻痕：把记忆文档切成可检索的块"""
import os, re, json, hashlib

SOURCES = []
def add(path, tag):
    if os.path.exists(path):
        SOURCES.append((path, tag))

MEM = '/data/workspace/_memory'
KB  = '/data/workspace/_kb'
add(f'{MEM}/MEMORY.md', 'MEMORY')
for f in ['交接档案.md','SCHEMA.md','INDEX.md','CHANGELOG清理.md','技能库恢复.md']:
    add(f'{MEM}/{f}', 'MEMORY')
for f in sorted(os.listdir(KB)) if os.path.isdir(KB) else []:
    if f.endswith('.md') and not f.startswith('.'):
        add(f'{KB}/{f}', 'KB')
for f in ['/data/workspace/跨会话恢复_迷你UGC3.0.md',
          '/data/workspace/生物基因性状系统_设计说明.md',
          '/data/workspace/迷你UGC3.0_引擎环境实测手册.md']:
    add(f, 'DOC')

HEAD = re.compile(r'^(#{1,6})\s+(.*)$')
MAXLEN = 1400
MINLEN = 60

def split_long(text, limit=MAXLEN):
    """过长块按空行/句末二次切"""
    if len(text) <= limit:
        return [text]
    parts, cur = [], ''
    for para in text.split('\n'):
        if cur and len(cur) + len(para) + 1 > limit:
            parts.append(cur)
            cur = ''
        cur = (cur + '\n' + para).strip() if cur else para
    if cur:
        parts.append(cur)
    out = []
    for p in parts:
        while len(p) > limit * 1.5:
            cut = p.rfind('\n', 0, limit)
            if cut < limit * 0.4:
                cut = limit
            out.append(p[:cut]); p = p[cut:]
        if p.strip():
            out.append(p)
    return [x.strip() for x in out if x.strip()]

def chunk_file(path, tag):
    raw = open(path, encoding='utf-8', errors='replace').read()
    lines = raw.split('\n')
    blocks = []
    stack = {i: '' for i in range(1, 7)}
    cur_title, cur_level, cur_lines, start_ln = None, 0, [], 0
    def flush():
        nonlocal cur_lines, cur_title, cur_level
        if cur_title is None or not cur_lines:
            cur_lines = []
            return
        body = '\n'.join(cur_lines).strip()
        path_titles = [stack[i] for i in range(1, 7) if stack[i]]
        for seg in split_long(body):
            if len(seg) < MINLEN and not re.search(r'[⛔★]|铁律|实测|签名|上限|禁止', seg):
                pass
            blocks.append({
                'src': os.path.basename(path),
                'tag': tag,
                'title': cur_title,
                'level': cur_level,
                'path': ' > '.join(path_titles),
                'line': start_ln,
                'text': seg,
            })
        cur_lines = []
    for i, ln in enumerate(lines):
        m = HEAD.match(ln)
        if m:
            flush()
            lvl = len(m.group(1)); t = m.group(2).strip()
            cur_title, cur_level, start_ln = t, lvl, i + 1
            stack[lvl] = t
            for j in range(lvl + 1, 7):
                stack[j] = ''
        else:
            if cur_title is None:
                cur_title, cur_level, start_ln = '(前言)', 0, i + 1
            cur_lines.append(ln)
    flush()
    return blocks

def main():
    all_blocks = []
    seen = set()
    for path, tag in SOURCES:
        try:
            bs = chunk_file(path, tag)
        except Exception as e:
            print('SKIP', path, e); continue
        for b in bs:
            h = hashlib.md5((b['src'] + b['title'] + b['text']).encode('utf-8')).hexdigest()[:12]
            if h in seen:
                continue
            seen.add(h)
            b['id'] = h
            all_blocks.append(b)
    # 合并过短块到相邻同文件块
    merged = []
    for b in all_blocks:
        if (merged and len(b['text']) < MINLEN and b['src'] == merged[-1]['src']
                and len(merged[-1]['text']) + len(b['text']) < MAXLEN):
            merged[-1]['text'] += '\n' + b['text']
        else:
            merged.append(b)
    json.dump(merged, open('chunks.json', 'w', encoding='utf-8'),
              ensure_ascii=False, indent=1)
    print('文件数:', len(SOURCES), '块数:', len(merged))
    tot = sum(len(b['text']) for b in merged)
    print('总字符:', tot, '均长:', tot // max(1, len(merged)))
    from collections import Counter
    print('来源分布:', Counter(b['src'] for b in merged).most_common(8))
    print('长块(>2000):', sum(1 for b in merged if len(b['text']) > 2000))

if __name__ == '__main__':
    main()
