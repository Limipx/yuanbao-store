# yuanbao-store（Limipx）

长期存储仓库：**技能库 + Agent 画像 + 手机上传文件**

| 路径 | 内容 |
|---|---|
| `skills/` | 技能库，一个子文件夹 = 一个技能（`skills.tar.gz`，29 个） |
| `agent/` | Agent 画像：`core/PROFILE.md` 核心能力 + `domains/*.md` 领域专长 |
| `uploads/` | 手机上传器写入，`uploads/<批次ID>/` |

## 恢复命令（推荐 jsdelivr，国内更快更稳）

```bash
# 技能库（269 文件 / 3.1MB）
curl -L -o skills.tar.gz https://cdn.jsdelivr.net/gh/Limipx/yuanbao-store@main/skills/skills.tar.gz
mkdir -p /data/skills && tar -xzf skills.tar.gz -C /data/skills --strip-components=1

# Agent 画像
curl -L -o agent.tar.gz https://cdn.jsdelivr.net/gh/Limipx/yuanbao-store@main/agent/agent.tar.gz
tar -xzf agent.tar.gz -C /data/workspace
```

备选（若 jsdelivr 不通）：
```bash
https://raw.githubusercontent.com/Limipx/yuanbao-store/main/skills/skills.tar.gz
```

## 上传器 APK

Release 直链（任何人可下载，无需登录）：
```
https://github.com/Limipx/yuanbao-store/releases/download/v1.0/YuanbaoUploader.apk
```

## 约定

- 数据一律**压缩后**入库（tar.gz），避免零散小文件
- 单文件 100MB 硬限、单 blob 约 40MB，压缩 + 分片更安全
- 新技能回存时打成 tar.gz 传进 `skills/`

## 状态

- skills：269 文件，7.1MB → **3.1MB（2.26x）**
- agent：6 文件，7KB
