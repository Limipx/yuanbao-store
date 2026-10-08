# yuanbao-store（Limipx）

| 路径 | 内容 |
|---|---|
| `skills/` | 技能库，每个子文件夹一个技能。解包到 `/data/skills/` 即用 |
| `agent/` | Agent 画像：`core/PROFILE.md` 是核心能力，`domains/*.md` 是领域专长 |
| `uploads/` | 手机上传器写入的文件，`uploads/<批次ID>/` |

## 恢复命令

```bash
# 拿到技能库
curl -L -o skills.tar.gz https://raw.githubusercontent.com/Limipx/yuanbao-store/main/skills/skills.tar.gz
mkdir -p /data/skills && tar -xzf skills.tar.gz -C /data/skills --strip-components=1

# 拿到 agent 画像
curl -L -o agent.tar.gz https://raw.githubusercontent.com/Limipx/yuanbao-store/main/agent/agent.tar.gz
tar -xzf agent.tar.gz -C /data/workspace
```

## 约定
- 数据一律**压缩后**入库（tar.gz），避免零散小文件占满
- 单文件 100MB 硬限、单 blob 约 40MB，压缩 + 分片更安全
