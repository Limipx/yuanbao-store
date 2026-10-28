# -*- coding: utf-8 -*-
"""刻痕上石：记忆块 -> 稀疏(BM25) + 稠密(TFIDF 稀疏余弦) 双索引"""
import json, pickle, os, time, numpy as np, jieba
from sklearn.feature_extraction.text import TfidfVectorizer
import scipy.sparse as sp

D = os.path.dirname(os.path.abspath(__file__))
chunks = json.load(open(f'{D}/chunks.json', encoding='utf-8'))
aug = [(c['title'] + ' ' + c['title'] + ' ' + (c['path'] or '') + ' ' + c['text'])
       for c in chunks]
t0 = time.time()

tf = TfidfVectorizer(analyzer='char_wb', ngram_range=(2, 4),
                     max_features=40000, sublinear_tf=True, min_df=1)
X = tf.fit_transform(aug).tocsr()
X.data = X.data.astype('float32')
sp.save_npz(f'{D}/tfidf_X.npz', X)
pickle.dump(tf, open(f'{D}/tfidf.pkl', 'wb'), protocol=4)

STOP = set('的了是在和与及就都而或有也这个我们你他它们吧呢啊嘛哦对于关于以及并且可以'.split())
def cut(s):
    return [w for w in jieba.lcut(s) if len(w) > 1 and w not in STOP]
corpus = [cut(c['title'] + ' ' + c['title'] + ' ' + c['text']) for c in chunks]
from rank_bm25 import BM25Okapi
bm = BM25Okapi(corpus)
# 只存打分所需统计量，避免整对象过大
stat = {'docs': [{w: int(n) for w, n in d.items()} for d in bm.doc_freqs],
        'lens': list(bm.doc_len), 'avg': float(bm.avgdl), 'idf': dict(bm.idf),
        'k1': bm.k1, 'b': bm.b}
pickle.dump(stat, open(f'{D}/bm25.pkl', 'wb'), protocol=4)

for f in ['tfidf_X.npz', 'tfidf.pkl', 'bm25.pkl', 'chunks.json']:
    print(f'{f:16s} {os.path.getsize(D+"/"+f)/1024:8.1f} KB')
print(f'块数={len(chunks)} 特征={X.shape[1]} 非零={X.nnz} 耗时={time.time()-t0:.1f}s')
