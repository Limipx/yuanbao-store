# 工作规范

## 开工前（每次会话）

```bash
# 1. 恢复技能库（jsdelivr + commit SHA，有缓存要换 SHA）
curl -L -o skills.tar.gz https://cdn.jsdelivr.net/gh/Limipx/yuanbao-store@<SHA>/skills/skills.tar.gz
mkdir -p /data/skills && tar -xzf skills.tar.gz -C /data/skills --strip-components=1

# 2. 读主管画像
cat agent/core/PROFILE.md agent/core/ROLE.md

# 3. 查有没有人做过
cat memory/INDEX.md
cat knowledge/INDEX.md
```

**注意**：`/data` 每次会话会重置，第一步必做。

## 工作中

- 每完成一个**可复用结论** → 写进 `knowledge/<主题>/`
- 每完成一个**资产** → 登记进对应 `INDEX.md`
- 遇到**真 bug** → 记录根因，不只记现象

## 收工前

- 更新 `memory/main/MEMORY.md`
- 若是被分派的会话：写 `memory/sessions/<id>/SUMMARY.md`
- `git push` 前确认没有明文密钥

## 实测优先原则

任何"应该能行"的判断，必须补一句实测状态：

```
【已测】xxx   ← 真跑过
【未测】xxx   ← 没跑过，说清楚为什么
```

没跑过就不能说"完成了"。
