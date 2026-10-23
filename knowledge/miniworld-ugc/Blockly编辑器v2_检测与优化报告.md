# 迷你世界3.0 Blockly 编辑器 · 逐个检测与优化报告（v1 → v2）

源文件：`迷你世界3.0脚本Blockly编辑器.html`（1,036,341 字节 / 5087 行）
产出：`迷你世界3.0脚本Blockly编辑器_优化版.html` + `_v2.txt`（1,062,609 字节 / 5159 行）
**md5 `4de2339e91b854ea158064e5cf7935d1`（两份同一内容）**

---

## 一、检测方法

不是"看一眼"，是把积木库真的解析出来逐条过：

- 用 Node 20 把 `B / G / L / DATA_MAP` 四个常量**真实解析成对象**（不是正则扫）
- 遍历全部 **1133 个积木**、**998 个 Lua 模板**
- 每条做：占位符解析、params 对齐、模块归属统计、Lua 5.1 编译
- 逐个比对记忆库里的硬事实与已废除清单

---

## 二、逐项检测结果

| # | 检测项 | 结果 |
|---|---|---|
| 1 | `os.clock` | ✅ 0 处（没踩"用了必崩"的坑） |
| 2 | `bit32` / `goto` / `table.unpack` | ✅ 均 0 处 |
| 3 | `CloudSever` | ⚠️ **2 个积木存在**（已废除）→ 已标注 |
| 4 | `Studio` / `GetService` | ✅ 0 处 |
| 5 | `bit` 模块 | ❌ **完全缺失**（记忆铁律：必须用、禁止降级）→ 补 12 个 |
| 6 | `os.timeMs` / `os.time` / `os.date` | ❌ **完全缺失** → 补 3 个 |
| 7 | `coroutine`（7 成员） | ❌ **完全缺失** → 补 7 个 |
| 8 | `threadpool:wait` | ❌ **缺失**（官方"等待1秒"标准答案）→ 补 |
| 9 | `UpdateValueAndCallback` | ❌ **缺失**（KV 并发正确性的支点）→ 已升级 |
| 10 | `math` 扩展（34 成员） | ⚠️ 只有 20 个 → 补 17 个（tanh/clamp/lerp/mod/ldexp…） |
| 11 | `string` 扩展 | ⚠️ 缺 split/Trim/startswith/endswith → 补 6 个 |
| 12 | `table` 扩展 + 全局 `unpack` | ⚠️ 缺 clone/equal/unpack → 补 9 个 |
| 13 | 全局基础函数（pcall/select/setmetatable…） | ❌ 缺失 → 补 14 个 |
| 14 | `openFnArgs` 生成格式 | ❌ **真 bug**：params 只有类型没名字 → 已修 |
| 15 | `Data.Table:InsertValue` | ❌ **真 bug**：用了变参 `{{...}}` → 已修为单值 |
| 16 | `{{x\|y\|z}}` 写法 | ❌ **真 bug**：8 个 World 积木，源码无处理逻辑 → 已修 |
| 17 | `arrayWrapper` 其余类型 | ⚠️ 返回 "Unknown" → 改为 `propertytype.__className_` |
| 18 | `World:GetAllPlayers({{alive}})` | ⚠️ 真机确认无参 → 已改正 |
| 19 | Lua 5.1 合规检查 | ❌ 无 → 新增导出前自动体检 |
| 20 | 开放函数登记表一致性检查 | ❌ 无 → 新增 |

---

## 三、修的 4 个真 bug（都会静默出错）

### ★ 1. `openFnArgs` 的 params 缺参数名

修复前生成：
```lua
params = {
        Mini.String
    }
```

记忆库里的实机正确格式是**扁平数组、名/类型交替**：
```lua
params = { "规格", Mini.String }
```

修复后：
```lua
params = {
        "原文", Mini.String,
        "密钥位数", arrayWrapper(Mini.Number)
    }
```
→ 给 `openfn_func` 加了参数名输入框（mutator + 持久化 + 生成器三处同步改）。

### ★ 2. `Data.Table:InsertValue` 变参

修复前：`Data.Table:InsertValue({{varId}}, {{playerId}}, {{...}})`

记忆铁律：实机**每行只传一个字符串**，多传会把行号塞进第 1 列、数据挤到第 2 列，**不报错、静默错位**。
已改为 `InsertValue({{varId}}, {{playerId}}, {{value}})`，desc 里写全 2000 行 / 500KB / 一行放多条。

### ★ 3. 8 个 World 积木的 `{{x|y|z}}`（最隐蔽）

```
World:SetSpawnPoint({{x|y|z}})
```
源码的占位符正则是 `/\{\{(\w+)\}\}/g`，`\w+` **匹配不到 `|`**，于是：
- UI 上**不生成输入插槽**（用户没法填）
- 生成代码**原样输出** `World:SetSpawnPoint({{x|y|z}})` → **导入即崩**

已把 8 个全部展开为 `{{x}}, {{y}}, {{z}}` 并同步 params_desc：
`spawnprojectilebydir / getbiometype / getbiomegroup / findecosystem / getraylength / getrayblock / calcdirectionbyyawdirection / setspawnpoint`

### ★ 4. 体检函数自己写错（我引入的）

`out.push(...).concat(...)` —— `push` 返回**数字**不是数组，被 `try/catch` 包住后**整个体检静默失效**。已修。

---

## 四、新增 69 个积木（全部是记忆库"确定存在、必须用、禁止降级"的）

| 子分类 | 数量 | 代表 |
|---|---|---|
| bit 位运算库 | 12 | band/bor/bxor/bnot/lshift/rshift/arshift/rol/**ror**/tobit/tohex/bswap |
| 系统时间库 | 3 | **os.timeMs()** / os.time / os.date |
| 协程与线程池 | 8 | create/resume/yield/status/wrap/running/isyieldable + **threadpool:wait** |
| 数学库扩展 | 17 | tanh/sinh/cosh/asin/acos/atan/atan2/fmod/mod/modf/**clamp**/**lerp**/ldexp/frexp/approximately/pow/huge |
| 字符串库扩展 | 6 | **split**/gmatch/Trim/startswith/endswith/dump |
| 表操作库扩展 | 9 | **clone**/**equal**/merge/move/show/num_pairs/getn/maxn + **全局 unpack** |
| 全局函数库 | 14 | **pcall**/xpcall/error/assert/select/setmetatable/getmetatable/rawget/rawset/next/ipairs/pairs/tostring/tonumber |

每个 desc 都写进了记忆库里对应的坑，例如 bit 的：
> ⛔引擎 bit 模块确定存在，12 成员全在（**含 ror**），必须用禁止自拼降级。有符号32位：lshift(1,31)=-2147483648。⚠️引擎是 Lua 5.1 数字为 double，2^53 是硬边界

---

## 五、新增 4 个"速查注释"积木

拖进画布就生成一段说明注释，不产生逻辑：

1. **★存储载体选型表** — 谁能放不可打印字符、各自容量上限
2. **★二维表与 KV 作用域** — 导入 500KB+2000行 / 导出只有 2000 行 / `playerId` nil=房间级 uin=私人级
3. **★引擎环境硬事实** — Lua 5.1 非 LuaJIT / bit 12 成员含 ror / os 无 clock / 2^53 边界
4. **★组件表规范** — 元数据不能搬进 OnStart / 非函数字段只有 2 个 / minValue 不是 min

---

## 六、新增：导出前自动体检

点「生成代码」时自动跑，结果以注释形式插在代码头部：

```
-- ⛔ Lua5.1 / 引擎合规问题:
  [第20行] os.clock 在引擎不存在,一调必崩 → 改用 os.timeMs()
  [第21行] Lua 5.1 没有 // 整除运算符
  [第22行] 引擎没有 bit32 → 用引擎 bit 模块(12成员,含 ror)
  [第23行] Lua5.1 的 table 库没有 unpack → 必须用【全局】unpack
  [第24行] ⛔CloudSever 已被官方废除 → 云服一律走 Data.Map
  [第25行] ⛔unpack 遇 nil 空洞会截断参数!后面的参数全部丢失
-- ⚠️ 属性区中文标点:
  [第5行] 属性区 displayName 含中文标点 → 官方要求禁用,请换英文标点
-- ⚠️ 开放函数登记表:
  openFnArgs 登记了 "Ghost" 但没有 function Script:Ghost(...) → 触发器看得到却调不动
```

14 条规则，全是记忆库里踩过的坑。

---

## 七、验证记录

```
JS 语法            new Function() 通过
HTML 结构          </html> 闭合 · script 9/9
积木总数           1133 · 重复 type 0
Lua 模板           998 个，983 个可编译（其余 15 个是 MUTATOR）
新增 69 个         全部进入 DATA_MAP，0 遗漏
占位符/参数描述     新增部分 0 不匹配
Lua 5.1 编译       arrayWrapper 新版 / openFnArgs 新版 / 全部新积木模板  全通过
体检函数           脏代码报 8 条 · 干净代码返回 null
```

---

## 八、已知未处理（非功能性）

- 244 个老积木的 `params_desc` 数量与占位符数不完全一致 —— 只影响 UI 上参数标签的显示，不影响生成代码正确性（源码取不到就用空标签）。
- 两版探测冲突的 API（`string.startswith/endswith/dump`、`table.merge/move/show`）已在新积木 desc 里标注「用前先 `type()` 判存在」，未替用户拍板。
