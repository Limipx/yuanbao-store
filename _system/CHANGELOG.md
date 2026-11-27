# 变更记录

## v2.0（2026-10-09）—— 主管制 + 专业目录结构

元宝升级为主管，统领一切事务、监督其他对话、兼任网页/应用开发。

**新增顶层**：
- `agent/` ← 原 `agent/`，扩充为 core/domains/directives
- `memory/` ← 新增，含 main + sessions（其他对话记忆区）
- `knowledge/` ← 新增，分类公共知识库
- `resources/` ← 新增，美术/音频/视频/建模/字体
- `projects/` ← 新增
- `inbox/` `outbox/` ← 新增，跨对话收发
- `_system/` ← 新增，规范与变更

**保留**：
- `skills/` ← 技能库（124 个 / 4.16MB）

**新增文件**：
- `_system/SCHEMA.md`（目录规范，唯一权威）
- `agent/core/ROLE.md`（主管职责）
- `agent/core/WORKFLOW.md`（工作规范）
- `agent/directives/实测优先.md`

## v1.0（2026-10-08）—— 初版

- skills/（29 个自定义技能）
- agent/core/PROFILE.md、agent/domains/*

## v3.0（2026-11-27）—— 主管交接 + 记忆架构升级

- 元宝卸任，大肥鱼/鲸鱼娘接任主管（见 _system/主管交接说明.md），CODEOWNERS/ROLE/README 已标注。
- 新增 _system/记忆架构规范.md v3.0：Infini Memory 主题文档法 + CoALA 四类记忆 + CURRENT 缓冲巩固 + agentic 检索。
- 新增 memory/CURRENT.md 写入缓冲区。
- 保留元宝全部历史资产，增量维护不覆盖。
