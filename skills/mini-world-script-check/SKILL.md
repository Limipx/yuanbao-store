---
name: mini-world-script-check
description: |
  迷你世界 UGC 3.0 组件脚本的**交付前检查**技能。写完、改完、混淆完任何一个 .lua 组件脚本后，
  在交给用户之前必须加载本技能跑一遍检查，确认无误再交付。
  覆盖五类高频致命错误：① 结构缺失（没有 local Script / return Script）② 登记表违规
  （Script 表内有非函数字段、openFunctions 与 openFnArgs 互相赋值）③ 属性读取错误
  （读 Script.propertys[x].default 而非 self[x]）④ 二维表读取错误（playerId 传非 0 数字）
  ⑤ 元数据铁律（propertys 被搬进 OnStart、On* 改名、元方法改名、登记表键与函数名不同步）。
  触发词：检查脚本、检查一下、跑一遍检查、交付前检查、脚本又出问题、读不出来、返回 nil、
  属性面板空白、触发器看不到、二维表读不到。
  只要用户说"这个脚本不对/读不出来/又错了"，先加载本技能检查，不要凭空猜原因。
version: "1.0"
---

# 迷你世界组件脚本 · 交付前检查

## 铁律：先查再猜

> **遇到"脚本跑不通"，第一反应永远是「grep 用户已有的、能跑通的脚本」，不是在自己的代码里找原因。**

用户沙盒的 `/data/inputs/` 下通常放着此前验证过的脚本（如 `迷你MiniMind对话_修复.lua`、
`建筑文件生成器3.1.lua`、`拼音输入法_二维表版.lua`）。**这些是权威参考**。

错误路径（已犯过四次）：怪数组 → 猜 ID 前导 0 → 探针自己写漏 → 仍不对。
正确路径（一次命中）：`grep "GetAllValue" /data/inputs/*.lua` → 抄现成写法。

## 使用流程

```
1. python3 scripts/check.py <脚本.lua>      自动检查，输出问题清单
2. 逐条修
3. 重跑 check.py 直到 0 错误
4. 语法复核：python3 -c "from luaparser import ast; ast.parse(open(f).read())"
5. 才交付
```

## 检查项（自动）

| # | 级别 | 检查内容 |
|---|---|---|
| 1 | ❌ | 有 `local Script = {}` |
| 2 | ❌ | 末尾有 `return Script` |
| 3 | ❌ | 无 `openFunctions = openFnArgs` 互赋值 |
| 4 | ❌ | 运行时不读 `Script.propertys[x].default` / `.value` |
| 5 | ❌ | 二维表 `GetAllValue` 的 playerId 是 nil 或 0 |
| 6 | ❌ | `propertys` / `openFnArgs` 在顶层（缩进 0） |
| 7 | ❌ | `arrayWrapper` 定义在 openFnArgs 之前 |
| 8 | ⚠️ | 开放函数有惰性初始化（不依赖 OnStart 一定成功） |
| 9 | ⚠️ | `On*` 生命周期函数未被重命名 |
| 10 | ⚠️ | 登记表键与函数定义名一一对应 |

## 检查项（人工，脚本查不出）

**登记表内不能有非函数字段**
```
Script 表内只允许：propertys / openFnArgs / openFunctions（元数据）
                  + 开放函数（function）
其余数据（缓存表、配置、状态变量）一律顶层 local，在 OnStart 里赋值。
```

**数组属性读写**
```lua
-- 定义
xxx = { type = Mini.Array, itemType = Mini.String,
        default = Mini.Array(Mini.String, "a", "b"),
        displayName = "...", customDisplayName = "..." }
-- 读取：运行时从 self 读，1-based
local n = #self.xxx        -- userdata 支持 # 和 ipairs
for i = 1, n do local v = self.xxx[i] end
```
`Mini.Array` 的 default 只用于**定义**；`arrayWrapper` 只用于**开放函数返回数组**，
属性 default 不需要包装，两者别混。

**惰性初始化**（必写）
```lua
local function ensureInit(self)
    if SELFREF == nil and self ~= nil then SELFREF = self end
    if #IDS > 0 then return end
    IDS = collectIds(getProp("tableIds"))
end
-- 每个开放函数第一行调 ensureInit(self)
```

**属性读取**（唯一正确写法）
```lua
local function getProp(name)
    if SELFREF ~= nil then
        local ok, x = pcall(function() return SELFREF[name] end)
        if ok and x ~= nil then return x end
    end
    local ok2, x2 = pcall(function() return Script[name] end)
    if ok2 and x2 ~= nil then return x2 end
    return nil
end
```
❌ 绝不读 `Script.propertys[name].default`（定义期占位，面板改了不生效）

## 二维表读取（本次踩坑核心）

```lua
-- playerId 语义
nil / 0  →  全局房间变量（二维表存这儿）
非0数字  →  私人个人变量（uin）

local function readTable(tid)
    local ok, rows = pcall(Data.Table.GetAllValue, Data.Table, tid, nil)
    if ok and type(rows) == "table" and #rows > 0 then return rows end
    local ok2, rows2 = pcall(Data.Table.GetAllValue, Data.Table, tid, 0)
    if ok2 and type(rows2) == "table" and #rows2 > 0 then return rows2 end
    if ok and type(rows) == "table" then return rows end
    return nil
end
```
传 `1` 等于查 uin=1 的私人变量 → 永远 nil。

## 调试：探针法

排查不出来的问题，写**极简探针组件**（50–150 行）单独测一件事，让用户跑并回传输出。
比猜快得多。探针要点：
- 每个待测量**硬编码单独一行 pcall**，不要放表里循环（`pairs{nil=...}` 会漏掉 nil 键）
- 打印 `type()` + 个数 + 首行内容
- 交叉验证：同数据用多个接口查（GetAllValue / GetRows / GetTableColKeys）

## 交付前自检（对用户）

不说"改好了"除非：① check.py 通过 ② 语法解析通过 ③ 该文件真的被读写过。
**"我说改了但实际没落到文件"已犯过一次**——改完用 grep 复核一次再回复。
