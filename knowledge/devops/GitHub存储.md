# GitHub 存储要点

## 账号

- 用户名 `Limipx`（ID 206050242）
- 仓库：`yuanbao-store`（公开）、`yuanbao-phone`（私有）、
  `liming-house`、`mini-project`

## 下载必须用 jsdelivr + commit SHA

`raw.githubusercontent.com` 和 `github.com` 在沙盒 **403**。
`cdn.jsdelivr.net` 可用，但**有缓存**，`@main` 会拿到旧版。

```bash
# 用 commit SHA 绕过缓存
https://cdn.jsdelivr.net/gh/Limipx/yuanbao-store@<SHA>/skills/skills.tar.gz
```
`purge.jsdelivr.net` 在沙盒被 403，清不了缓存 → 只能走 SHA。
首次拉大文件偶尔返回 0 字节，**重试即可**（实测第 3 次成功）。

## 硬限制

- 单文件 blob **40MB**
- 密码**不能**用于 API（2021 起禁止），必须 PAT
- 上传用 Contents API，PUT 带 sha 更新

## 压缩

skills 10.04MB → 4.16MB（2.42x，tar.gz）
