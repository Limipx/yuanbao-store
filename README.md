# yuanbao-store · Limipx 资产总库 v2.0

> 元宝（主管）统领。目录规范见 `_system/SCHEMA.md`。

## 结构

| 目录 | 用途 |
|---|---|
| `agent/` | 主管自身定义：职责、工作规范、领域专长、行为准则 |
| `memory/` | 记忆区：本会话 + 其他所有对话（含索引与状态） |
| `knowledge/` | 分类公共知识库：可复用、经实测的结论 |
| `resources/` | 资源区：美术 / 音频 / 视频 / 建模 / 字体 |
| `skills/` | 技能库（124 个 / 4.16MB） |
| `projects/` | 长期项目 |
| `inbox/` | 收件箱：其他对话 → 主管 |
| `outbox/` | 发件箱：主管 → 其他对话 |
| `_system/` | 目录规范 + 变更记录 |

## 恢复技能库

```bash
curl -L -o skills.tar.gz \
  https://cdn.jsdelivr.net/gh/Limipx/yuanbao-store@<COMMIT_SHA>/skills/skills.tar.gz
mkdir -p /data/skills && tar -xzf skills.tar.gz -C /data/skills --strip-components=1
```

⚠️ 必须用 **commit SHA**，不能用 `@main`（jsdelivr 有缓存）。

## 其他对话开工前

1. 恢复技能库
2. 读 `agent/core/ROLE.md` + `_system/SCHEMA.md`
3. 读 `memory/INDEX.md` 查有没有人做过
4. 读 `agent/directives/实测优先.md`

## 主管（元宝）

- **职责**：统领、监督、记忆、规范
- **亲自做**：网页开发、应用开发
- **专用读写**：`memory/main/`、`agent/`（仅主管可改）
- 其他对话写 `inbox/` 和自己的 `memory/sessions/<id>/`
