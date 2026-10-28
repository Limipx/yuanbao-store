# -*- coding: utf-8 -*-
"""三生石 · 记忆 RAG 检索
  召回 python3 三生石.py 召回 "查询" [-k 8] [--tag MEMORY] [--full] [--json]
  状态 python3 三生石.py 状态
  刻石 python3 三生石.py 刻 "内容" --title "标题" [--src 来源]
"""
import json, pickle, os, sys, argparse, time, hashlib
import numpy as np, jieba, scipy.sparse as sp

D = os.path.dirname(os.path.abspath(__file__))
jieba.setLogLevel(60)
STOP = set('的了是在和与及就都而或有也这个我们你他它们吧呢啊嘛哦对于关于以及并且可以'.split())
CUT = lambda s: [w for w in jieba.lcut(s) if len(w) > 1 and w not in STOP]
RRF_K = 60

def load():
    chunks = json.load(open(f'{D}/chunks.json', encoding='utf-8'))
    tf = pickle.load(open(f'{D}/tfidf.pkl', 'rb'))
    X = sp.load_npz(f'{D}/tfidf_X.npz')
    bm = pickle.load(open(f'{D}/bm25.pkl', 'rb'))
    return chunks, tf, X, bm

def bm25_scores(bm, qterms):
    n = len(bm['docs'])
    s = np.zeros(n, dtype='float64')
    idf, k1, b, avg = bm['idf'], bm['k1'], bm['b'], bm['avg']
    for t in set(qterms):
        iv = idf.get(t)
        if iv is None:
            continue
        for i in range(n):
            f = bm['docs'][i].get(t, 0)
            if not f:
                continue
            denom = f + k1 * (1 - b + b * bm['lens'][i] / avg)
            s[i] += iv * f * (k1 + 1) / denom
    return s

def rank_desc(scores):
    """返回 文档->排名(0起) 的 dict，只保留有分的前 300"""
    idx = np.argsort(-scores)
    out = {}
    r = 0
    for i in idx:
        if scores[i] <= 0:
            break
        out[int(i)] = r
        r += 1
        if r >= 300:
            break
    return out

def recall(q, k=8, tag=None, full=False):
    chunks, tf, X, bm = load()
    # 稠密：TFIDF 稀疏余弦
    qv = tf.transform([q])
    dense = np.asarray((X @ qv.T).todense()).ravel()
    # 稀疏：BM25
    sparse = bm25_scores(bm, CUT(q))
    rd, rs = rank_desc(dense), rank_desc(sparse)
    rrf = {}
    for d, r in rd.items():
        rrf[d] = rrf.get(d, 0) + 1.0 / (RRF_K + r)
    for d, r in rs.items():
        rrf[d] = rrf.get(d, 0) + 1.0 / (RRF_K + r)
    # 标题/路径命中加成
    ql = q.lower()
    for i, c in enumerate(chunks):
        if i in rrf:
            t = (c['title'] + ' ' + (c['path'] or '')).lower()
            hit = sum(1 for ch in set(ql) if len(ch.strip()) and ch in t)
            if c['title'].lower() in ql or ql in c['title'].lower():
                rrf[i] += 0.02
            rrf[i] += min(hit, 6) * 0.0015
    order = sorted(rrf.items(), key=lambda x: -x[1])
    res = []
    for i, sc in order:
        c = chunks[i]
        if tag and c['tag'] != tag:
            continue
        res.append({'id': c['id'], 'score': round(sc, 4), 'src': c['src'],
                    'tag': c['tag'], 'title': c['title'], 'path': c['path'],
                    'line': c['line'],
                    'text': c['text'] if full else c['text'][:600]})
        if len(res) >= k:
            break
    return res

def cmd_status():
    chunks, tf, X, bm = load()
    from collections import Counter
    tot = sum(len(c['text']) for c in chunks)
    print(f'块数 {len(chunks)}  总字符 {tot}  均长 {tot//len(chunks)}')
    print('标签分布', dict(Counter(c['tag'] for c in chunks)))
    print('来源 TOP', Counter(c['src'] for c in chunks).most_common(6))
    for f in ['chunks.json', 'tfidf_X.npz', 'tfidf.pkl', 'bm25.pkl']:
        print(f'  {f:14s} {os.path.getsize(D+"/"+f)/1024:8.1f} KB')
    inc = f'{D}/新刻石.md'
    print('待整理新刻:', os.path.getsize(inc) // 1024 if os.path.exists(inc) else 0, 'KB')

def cmd_carve(text, title, src='NEW'):
    p = f'{D}/新刻石.md'
    with open(p, 'a', encoding='utf-8') as f:
        f.write(f'\n## {title}\n<!-- src={src} t={time.strftime("%Y-%m-%d %H:%M")} -->\n{text}\n')
    print('已刻入', p, '（运行 重建 后并入检索）')

def cmd_rebuild():
    os.system(f'cd {D} && python3 chunk.py && python3 index.py 2>&1 | grep -v jieba')
    print('重建完成')

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('cmd', choices=['召回', '状态', '刻', '重建', '开场', 'search'])
    ap.add_argument('q', nargs='?', default='')
    ap.add_argument('-k', type=int, default=8)
    ap.add_argument('--tag', default=None)
    ap.add_argument('--full', action='store_true')
    ap.add_argument('--json', action='store_true')
    ap.add_argument('--title', default='未命名')
    ap.add_argument('--src', default='NEW')
    a = ap.parse_args()
    if a.cmd in ('状态',):
        cmd_status(); return
    if a.cmd == '开场':
        core = open(f'{D}/核心层.md', encoding='utf-8').read()
        print('=' * 20 + ' 核心层（常驻，不可跳过） ' + '=' * 20)
        print(core)
        if a.q:
            print('\n' + '=' * 20 + f' 招魂：{a.q} ' + '=' * 20)
            for i, r in enumerate(recall(a.q, k=a.k, tag=a.tag), 1):
                print(f"[{i}] {r['score']:.4f} {r['src']} · {r['title']}")
                print(r['text'][:900])
                print('-' * 50)
        return
    if a.cmd == '刻':
        cmd_carve(a.q, a.title, a.src); return
    if a.cmd == '重建':
        cmd_rebuild(); return
    t0 = time.time()
    res = recall(a.q, k=a.k, tag=a.tag, full=a.full)
    if a.json:
        print(json.dumps(res, ensure_ascii=False, indent=1)); return
    print(f'【招魂】"{a.q}"  命中 {len(res)} 条  耗时 {time.time()-t0:.2f}s\n' + '=' * 60)
    for i, r in enumerate(res, 1):
        print(f"[{i}] {r['score']:.4f}  {r['src']} · {r['title']}  (L{r['line']})")
        if r['path'] and r['path'] != r['title']:
            print(f"    路径: {r['path'][:80]}")
        print('    ' + r['text'].replace('\n', '\n    ')[:1500])
        print('-' * 60)

if __name__ == '__main__':
    main()
