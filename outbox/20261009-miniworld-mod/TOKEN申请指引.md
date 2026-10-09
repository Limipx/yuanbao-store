# 模组工程师 Token 申请指引

> 主管（元宝）签发 · 2026-10-09
> **这份给你（Limipx）去操作**，30 秒完成

---

## 为什么必须你手动创建

**Fine-grained PAT 无法通过 API 创建**，只能走网页。
（GitHub 禁了密码调 API，创建 token 也没有开放接口。）

所以：**我给不出 token，只能给你步骤**。

---

## 一、创建步骤（精确）

### 1. 打开生成页

```
https://github.com/settings/personal-access-tokens/new
```

### 2. 填写

| 项 | 填什么 |
|---|---|
| **Token name** | `miniworld-mod-engineer` |
| **Expiration** | `90 days` |
| **Description** | 模组工程师专用，仅 yuanbao-store |

### 3. Repository access —— **关键**

```
⦿ Only select repositories
  → 只勾选  yuanbao-store
```

**一个都别多选。**

### 4. Repository permissions —— **最关键**

点开 `Repository permissions`，**只改这一项**：

| 权限项 | 设为 |
|---|---|
| **Contents** | `Read and write` |

其余**全部保持默认（不设置）**。

然后**逐项确认这三个是「未设置」**：

```
❌ Workflows        —— 保持不选！
❌ Administration   —— 保持不选！
❌ Metadata 以外的一切 —— 保持默认
```

### 5. 生成

点 `Generate token`，复制 `github_pat_` 开头的那串（只显示一次）。

---

## 二、为什么这样配是安全的

这是我**特意设计的权限组合**，有三层保障：

### 保障 1：够不到其他仓库

`Only select repositories` 只勾了 `yuanbao-store`。
你的 `yuanbao-phone`（私有，有手机操控脚本）、
`liming-house`、`mini-project` **完全够不着**。

### 保障 2：改不了守护脚本

**GitHub 把 `.github/workflows/` 的写权限单独拆成了 `Workflows` 权限。**

不给 `Workflows` → **它推不动 `.github/workflows/` 下的任何文件**。

我写的 `structure-guard.yml` 目录守护，它**技术上改不了**。
这是硬保障，不是靠自觉。

### 保障 3：动不了仓库本身

不给 `Administration` → 不能改仓库设置、不能删仓库、
不能改可见性、不能管协作者。

### 保障 4：自动化兜底

即使它绕过规范改了结构，push 时 `structure-guard.yml` 会：
- 检查九个顶层目录是否还在
- 检查是否新增了未授权的顶层条目
- 违规 → **push 失败**并在日志里明确提示

---

## 三、⚠️ 一个必须说清的限制

**Fine-grained token 的权限是仓库级的，无法按目录细分。**

也就是说，从技术上它**能**改 `_system/SCHEMA.md`、能改 `agent/`。

**GitHub 没有路径级权限这个东西。**

所以「不能改文件夹结构」这条，实际靠：

```
1. Workflows 权限不给  → 守护脚本它改不了（技术硬保障）
2. structure-guard.yml → 改了结构 push 会失败（自动化兜底）
3. CODEOWNERS         → 受保护路径变更会标主管审核
4. 规范约束           → 已写进《权限与写入规范.md》
```

四层。前两层是技术的，后两层是流程的。
**够用，但不是绝对。** 真要绝对隔离，得让它 fork 后走 PR——
那样流程太重，我建议先这样。

---

## 四、拿到 token 后怎么用

### 给它（模组工程师对话）

```
这是你的 GitHub token，只对 yuanbao-store 仓库有读写权限：

github_pat_xxxxx

用法：
  export GITHUB_TOKEN=github_pat_xxxxx
  # 或直接 git remote set-url origin https://<TOKEN>@github.com/Limipx/yuanbao-store.git

能写：knowledge/miniworld-ugc/**、projects/miniworld/**、
      inbox/你的ID/**、resources/**（须登记）、你自己的 memory
不能写：顶层结构、_system/、agent/、memory/main/、.github/
```

**并附上这两份文件**：
- `TASK.md`
- `权限与写入规范.md`

### 安全提醒

- 只写进环境变量或 git remote，**不写进代码文件**
- 不提交进仓库
- 90 天过期，到期找我重开
- 泄露/不用了 → 立即吊销

---

## 五、吊销方式

```
https://github.com/settings/personal-access-tokens
→ 找到 miniworld-mod-engineer
→ Revoke
```

---

## 六、我这边已就绪

已经部署好的：

| 文件 | 作用 |
|---|---|
| `.github/workflows/structure-guard.yml` | 目录守护，push 即检查 |
| `.github/CODEOWNERS` | 受保护路径标主管审核 |
| `outbox/.../权限与写入规范.md` | 给它的规范 |

**你生成 token 后，把三份文件（TASK.md + 权限规范 + token）一起发过去就行。**
