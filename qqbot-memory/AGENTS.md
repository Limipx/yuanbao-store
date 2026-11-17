# 这个仓库的阅读协议（给 Agent 看）

这是 QQ 机器人的长期记忆仓库。**先看 `INDEX.md` 决定看哪，不要全扫。**

## 目录与含义

| 路径 | 是什么 | 能不能改 |
|---|---|---|
| `events/YYYY/MM/DD.jsonl` | **唯一真相**，一行一个事件，append-only | 只追加，永不改、永不删 |
| `facts.json` | 从事件流投影出来的当前事实 | 自动生成，手改会被覆盖 |
| `conflicts.json` | 冲突队列，只暴露不裁决 | 自动生成 |
| `graph/nodes.jsonl` `graph/edges.jsonl` | 实体图投影 | 自动生成，可重建 |
| `brief.md` | 常注入核心（≤1500 tokens） | 自动生成 |
| `people/*.md` `groups/*.md` `topics/*.md` | 人可读小传 | **人可以直接改** |
| `stickers/index.json` | 表情包索引（不存二进制） | 自动生成 |
| `schedules.json` | 定时任务台账 | 自动生成 |
| `meta/manifest.json` | schemaVersion / 统计 / 最后 flush | 自动生成 |

## 三条规矩

1. **要纠正事实就写新事件**（`kind=correction`，`supersedes` 指向旧事件 id），不要删旧行 —— 要保留 provenance。
2. **owner 的条目 pinned**：不衰减、不被一次反例覆盖；与自动观察冲突时写进 `conflicts.json` 等人裁决。
3. **凭据永不入库**：token / appSecret / access_token 一旦出现就是事故。

## 重建

`rebuild = 从 events 全量重放`，结果必须与增量投影逐字节一致。
