# yuanbao-store · Limipx 资产总库 v3.0

> **主管**：大肥鱼 / 鲸鱼娘（2026-11-27 接任，元宝卸任）。目录规范见 `_system/SCHEMA.md`，记忆架构见 `_system/记忆架构规范.md`，交接见 `_system/主管交接说明.md`。

## 结构

| 目录 | 用途 |
|---|---|
| `agent/` | 主管自身定义：职责、工作规范、领域专长、行为准则 |
| `memory/` | 记忆区：CURRENT 缓冲 + 本会话 + 其他对话（含索引与状态） |
| `knowledge/` | 分类公共知识库：可复用、经实测的结论（语义记忆层） |
| `resources/` | 资源区：美术 / 音频 / 视频 / 建模 / 字体 |
| `skills/` | 技能库（程序记忆层） |
| `projects/` | 长期项目 |
| `inbox/` | 收件箱：其他对话 → 主管 |
| `outbox/` | 发件箱：主管 → 其他对话 |
| `_system/` | 目录规范 + 记忆架构规范 + 交接说明 + 变更记录 |

## 记忆架构（v3.0）
主题文档 + CURRENT 缓冲 + 定期巩固 + agentic 检索；四类记忆：工作/语义/情节/程序，外加组织上下文层。详见 `_system/记忆架构规范.md`。

## 恢复技能库

```bash
curl -L -o skills.tar.gz \
  https://cdn.jsdelivr.net/gh/Limipx/yuanbao-store@<COMMIT_SHA>/skills/skills.tar.gz
mkdir -p /data/skills && tar -xzf skills.tar.gz -C /data/skills --strip-components=1
```
