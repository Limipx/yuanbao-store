# 单文件 HTML 工具范式

用户偏好：**一个 .html 双击就能用**，纯前端、不上传数据。

## 结构模板

```html
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>工具名</title>
<style>
/* 移动端优先：max-width、touch 友好、深色 */
</style>
</head>
<body>
<!-- 输入区 → 配置区 → 结果区 三段式 -->
<script>
/* 纯 JS，无依赖，无网络请求 */
</script>
</body>
</html>
```

## 必须遵守

1. **纯前端**，不上传任何数据（用户明确要求）
2. **移动端适配**（用户是手机）
3. 深色主题 + 紧凑布局
4. 结果区提供「复制」和「下载」
5. 开关默认状态 = 安全状态，**危险选项默认关并置灰**

## 已交付的工具

- 混淆工具（Lua 混淆 + 密钥激活）
- 解析工具（反查签名/变体/校验状态）
- 配钥工具（生成 salt/iters/verify/enc）
- 拼音输入法工具

## 踩过的坑

**界面和代码打架**：HTML 复选框写 `checked`，
但 JS 里注释写"默认 false，搬走会导致属性丢失"。
结果混淆后 propertys 被搬进 OnStart → 属性面板空白。
→ **危险选项必须在代码层锁死，不能只靠界面默认值**
