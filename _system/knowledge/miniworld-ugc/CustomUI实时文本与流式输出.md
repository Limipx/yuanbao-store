# CustomUI 实时文本 / 流式输出

## CustomUI:SetText（实测命中 4 参形式）
```lua
CustomUI:SetText(playerId, 界面ID, 元件ID, 文本)
```
- playerId = 0 不代表广播，要遍历 `Player:GetAllPlayers()` 逐个发
- 引擎版本间签名不一致，脚本里做自适应：依次试
  `SetText(pid,ui,el,txt)` / `SetText(pid,el,txt)` / `SetText(el,txt)`，首次成功记住

## 元件ID 内含界面ID（用户纠正）
```
元件ID   7695242090665913341-110874_1
界面ID   7695242090665913341-110874
```
派生：去掉末尾 `_数字` → `elementId:match("^(.+)_%d+$")`
**不要再让用户单独填界面ID。**

## 逐 token 流式（参考计时器管理2代.lua 的广播原理）
- 主线程只派发；生成放协程，每 token 后 `self:ThreadWait(秒)` 让出主线程
- **ThreadWait 单位是秒**，0.05 = 50ms
- ThreadWait 不能包 pcall：Lua 5.1 不允许跨 C 边界 yield
- 引擎不支持协程挂起时自动退化为同步跑完，不会坏
- 每个 token 解码后要查 UTF-8 完整性，末尾是半个汉字就先不推

## ⚠️ 顶层 local 上限 200（Lua 硬限制）
整份脚本是主 chunk，**顶层 local 变量 + local function 合计不能超过 200**。
MiniMind2 v12 曾达到 202 → 真机加载直接失败。
解法：常量表并入已有表（如 `Inflater.LBASE`）、删除重复声明、运行态变量并入状态表。
写大脚本时要定期统计：
```bash
python3 -c "统计 ^local 行数与每行变量数"
```

## 前向声明（又栽了一次）
`_ensureEnhance` 定义在流式模块之后 → StreamAsk 运行时取全局 nil。
**规则**：函数体里用到后面才定义的 local，必须在使用点之前 `local xxx` 声明，
且定义处写成 `xxx = function()`（不能再写 `local function xxx`）。
