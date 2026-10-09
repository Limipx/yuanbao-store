# 目录结构规范 v2.0

> 本文件是**唯一权威定义**。任何对话新增内容前先读这里。
> 不符合规范的写入，主管有权整理或拒绝。

## 顶层

```
yuanbao-store/
├─ agent/        主管（元宝）自身定义 —— 我是谁、怎么干活
├─ memory/       记忆区 —— 本会话 + 其他所有对话
├─ knowledge/    分类公共知识库 —— 沉淀的可复用知识
├─ resources/    资源区 —— 美术/音频/视频/建模/字体
├─ skills/       技能库
├─ projects/     项目区 —— 长期工程
├─ inbox/        收件箱 —— 其他对话投递给主管
├─ outbox/       发件箱 —— 主管下发给其他对话
└─ _system/      系统规范与变更记录
```

## 各区细则

### agent/ —— 主管自身
```
core/PROFILE.md     核心画像：能力边界、工作风格
core/ROLE.md        主管职责：统领、监督、协调、验收
core/WORKFLOW.md    工作规范：开工前/中/后做什么
domains/*.md        领域专长（一个文件一个领域）
directives/*.md     行为准则（硬性约束）
```

### memory/ —— 记忆区
```
main/MEMORY.md          主管本会话记忆
sessions/<id>/META.md   会话元信息（主题/起止/状态/负责人）
sessions/<id>/MEMORY.md 该会话记忆
sessions/<id>/SUMMARY.md 会话结束时的一句话总结（监督用）
INDEX.md                所有会话索引 + 状态总览
```

**命名**：`<id>` 用 `YYYYMMDD-<主题拼音>`，例 `20261009-miniworld-mod`

**状态值**：`进行中` / `已完成` / `阻塞` / `已归档`

### knowledge/ —— 公共知识库
按主题分目录，每个目录下必须有 `INDEX.md`。
已有：`miniworld-ugc` `lua` `ai-ml` `crypto` `web-dev` `app-dev`
新增主题照此办理。

**收录标准**：可复用、经过实测、非一次性。

### resources/ —— 资源区
```
INDEX.md        总索引（**所有资源必须登记**，含校验和）
art/            贴图、UI、图标、原画
audio/          音效、BGM、语音
video/          视频素材、录屏
models/         3D 模型（glb/obj/fbx/blend）
fonts/          字体
_incoming/      待分类暂存（主管定期整理）
```

**登记格式**（INDEX.md 内一行一条）：
```
| 文件名 | 类型 | 尺寸/时长 | 校验和sha1前8 | 用途 | 来源 | 入库时间 |
```

**大文件**：单文件 > 5MB 用 tar.gz 压缩；> 40MB 必须分片（GitHub blob 上限）。

### inbox/ —— 收件箱（其他对话 → 主管）
```
inbox/<from-session-id>/<文件>
```
其他对话的产物、记忆快照、问题上报都投这里。
**主管定期检查并处理，处理完移到 knowledge/ 或归档。**

### outbox/ —— 发件箱（主管 → 其他对话）
```
outbox/<to-session-id>/<文件>
```
主管下发的任务书、规范、共享资料放这里。

### projects/ —— 项目区
长期工程，每个项目一个目录，必须含 `PROJECT.md`（目标/进度/负责人）。

## 通用规则

1. **压缩**：任何 > 1MB 的文件优先 tar.gz
2. **单文件上限**：40MB（GitHub blob 硬限制）
3. **中文**：文件名用中文可读，路径避免空格
4. **索引**：每个分类目录必须有 INDEX.md
5. **不删历史**：用 `archive/` 而非删除
6. **变更**：改动结构先更新本文件 + CHANGELOG.md

## 主管（元宝）专用读写区

- **读**：全库可读
- **写**：全库可写，但 `memory/main/` 和 `agent/` 只有主管改
- **其他对话**：可写 `inbox/` 和自己的 `memory/sessions/<id>/`，其余需主管批准
