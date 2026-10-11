# 流式生成的卡顿来源：prefill 而非 decode

## 现象
流式输出仍"卡几秒才出第一个字"，之后才逐字吐。

## 根因（按贡献排序）
1. **prefill**：prompt 全部 token 的前向传播，一次性跑完才进入逐 token 循环。
   O(prompt 长度)，历史越长越慢；是首字前卡顿的主因。
2. **loadModel**：首次调用读二维表 + base85 解码 26MB + parseModel，几秒级，
   全部压在第一次提问上。
3. decode：O(生成 token 数)，不是主因。

## 修法
- 把 `_genContext` 拆成 `_genPlan`（编码+KV准备，不跑 forward）+ prefill 循环，
  prefill 搬进协程按 `prefillChunk` 个 token 让出一次。
- `Warmup()` + `autoWarm`：进地图时预加载模型并空跑一次，把几秒挪走。
- `ctxTurns` 限制历史轮数（该属性此前定义了却没被代码使用，轮数硬编 8）。
- prefill 期间推送 `thinkText`，给玩家"在干活"的信号。

## 实测（模拟 40 token prompt / 24 token 输出 / 30ms per token）
| 方案 | 最大连续阻塞 | 总耗时 |
|---|---|---|
| prefill 不分帧 | 1236ms | 3172ms |
| 每 4 token 让出 | 124ms | 3692ms |
| 每 2 token 让出 | 64ms | 4212ms |

卡顿降到 10%，代价是总耗时 +15%（ThreadWait 0.05s 的让出开销）。
