# 跨会话恢复卡 · 迷你世界 UGC 3.0 / Lua 脚本

> **用途**：新会话开局先读这一份，即可恢复全部已验证知识与工作纪律，
> 不必重新翻 26 篇零散文档。
> **版本**：v2026.10.19　**原则**：以实践结果为准，废除一切过时结论。
> **证据等级**：【已测】实机或用户实测 · 【官方】官方文档 · 【转储】环境转储 · 【推测】待验证

---

# 〇、本文件怎么用

1. 读完本文件即可开工。**不必**再读 `_kb/` 下其他文档（它们已被并入）。
2. 需要某个模块的完整 API 表时，再查 `_kb/一层API全量知识库.md`（749 函数）。
3. 需要更细的论证过程时，查 `_kb/迷你世界UGC3.0_权威脚本知识手册.md`（1135 行）。
4. **本文件末尾有「上次会话状态」**，先看它能接上进度。

---

# 一、恢复步骤（每次新会话必做）

## 1.1 拉取长期记忆与知识库

> **TOKEN 不随本文件存储**（GitHub secret scanning 会拦截明文 token，
> 且违反"不泄露凭证"红线）。PAT 由用户在会话开头直接提供。
> 生成：https://github.com/settings/tokens/new → 90 days → **只勾 repo**

```bash
TOKEN="<会话开头用户提供的 PAT>"

# 记忆主档（最关键）
curl -s -H "Authorization: Bearer $TOKEN" -H "Accept: application/vnd.github.raw" \
  -o /data/workspace/_memory/MEMORY.md \
  https://raw.githubusercontent.com/Limipx/yuanbao-store/main/memory/main/MEMORY.md

# 知识手册
curl -s -H "Authorization: Bearer $TOKEN" -H "Accept: application/vnd.github.raw" \
  -o /data/workspace/_kb/迷你世界UGC3.0_权威脚本知识手册.md \
  https://raw.githubusercontent.com/Limipx/yuanbao-store/main/knowledge/miniworld-ugc/迷你世界UGC3.0_权威脚本知识手册.md
```

## 1.2 恢复技能库

```bash
curl -L -H "Authorization: Bearer $TOKEN" \
  -o /tmp/skills.tar.gz \
  https://raw.githubusercontent.com/Limipx/yuanbao-store/main/skills/skills.tar.gz
mkdir -p /data/skills && tar -xzf /tmp/skills.tar.gz -C /data/skills --strip-components=1
```

⚠️ GitHub tree API 的 path 要**原始中文**，百分号编码会 `422 BadObjectState`。
⚠️ 密码**不能**用于 GitHub API（2021 起禁用），必须用 PAT。

## 1.3 仓库结构

```
yuanbao-store/  （账号 Limipx）
├─ memory/main/MEMORY.md          长期记忆主档
├─ knowledge/miniworld-ugc/       ★ 本项目的全部知识库
│  ├─ 迷你世界UGC3.0_权威脚本知识手册.md   1135 行主手册
│  ├─ 一层API全量知识库.md                749 函数表
│  ├─ Mini.CustomData_格式与用法.md
│  ├─ KV文件系统_云服版v4.lua / 房间个人版v2.1.lua
│  ├─ API全模块探针.lua + API转储基线_全量含二层.csv
│  └─ _deprecated/                已归档的 10 篇旧文档
├─ skills/                        124 个技能 / 4.16MB
└─ _system/                       SCHEMA.md + 交接档案.md
```

---

# 二、运行环境硬事实

| 项 | 值 | 证据 |
|---|---|---|
| Lua 版本 | **5.1**（修改优化版）`_VERSION = "Lua 5.1"` | 【已测】 |
| 是否 LuaJIT | **否**，`jit = nil`、`ffi = nil` | 【已测】10-18 探针 |
| 运行位置 | 主机端（单人=自己，联机=房主设备，云服=官方服务器） | 【官方】 |
| 状态更新 | **50 ms = 1 tick** | 【官方】 |
| 大数 | **double**，`2^53` 与 `2^53+1` 完全相同 → 大整数必须自实现 BN | 【已测】 |
| 文件 IO | **无**，`io` 空表、`package` 空表 | 【已测】 |
| 错误行为 | `error` **不抛异常**，只记日志，代码继续往下跑 | 【官方】 |

## 2.1 库成员清单

| 库 | 成员 | 备注 |
|---|---|---|
| `os` | **3 个**：`date` `time` **`timeMs`** | ⛔ **`os.clock` 不存在，用了必崩** |
| `math` | **34 个** | 含 `tanh` `pow` `clamp` `lerp` `mod` `ldexp` `approximately` `log10` |
| `bit` | **12 个全在**：`band bor bxor bnot bswap lshift rshift arshift rol ror tobit tohex` | ⛔ **含 `ror`**；有符号 32 位，`lshift(1,31) = -2147483648` |
| `string` | `Trim` `split`（10-18 探针） | ⚠️ 用户早期文档另有 `startswith` `endswith` `dump` → **冲突，用前 `type()` 判存在** |
| `table` | 8 个（10-18 探针）vs 15 个（早期文档） | ⚠️ **冲突，用前判存在**；⛔ **无 `unpack`，用全局 `unpack`** |
| `coroutine` | 7 个（含 `isyieldable`） | ✅ 一致 |
| `debug` | 1 个 `traceback` | ✅ 一致 |
| `json` | `encode` `decode` | ✅ 确定存在（官方全局函数页） |
| `threadpool` | `Work` `work` `wait` `Wait` | ✅ 确定存在 |

## 2.2 ⛔ 禁止降级清单（用户明确指令）

`bit` / `json` / `threadpool` / `coroutine` / `os` / `math` / `string` / `table`
**均已确认存在。为它们写"自拼/自实现"的降级路径是错的**——
既慢，又会把真 bug 藏进兜底分支里（已因此出过 4 次事故）。

> **历史事故**：真随机数 v2 注释写「bit 只有 rol 没有 ror（**记忆实测**）」，
> 据此绕开原生自拼。**ror 其实在 12 个成员里。**
> → 纪律：凡"引擎某 API 存不存在"必须回查转储/真机探针，
> **禁止凭记忆，禁止在注释里写"（实测）"四个字**（写过的两处恰好都是记反的）。

## 2.3 Lua 5.1 的 32 位哈希精度坑

`h = (h * 16777619) % 2^32` 的乘积 ≈ 2^56 > 2^53 ⇒ **丢精度**。
（典型错误注释："`255*2^32 < 2^53` 安全"——只算了加法项，漏了乘法项。）

✅ 正确写法（FNV-1a，乘法拆高低 16 位，中间量 < 2^41）：

```lua
local function _h32(s)
    local h = 2166136261
    for i = 1, #s do
        local x = bit.bxor(bit.tobit(h), string.byte(s, i))
        if x < 0 then x = x + 4294967296 end
        local hi = math.floor(x / 65536)
        local lo = x - hi * 65536
        h = (((hi * 16777619) % 65536) * 65536 + lo * 16777619) % 4294967296
    end
    return h
end
```

校验：`""→2166136261`、`"a"→3826002220`、`"abc"→440920331`、`"foobar"→3214735720`。

⚠️ `rshift` 是**逻辑右移**（无符号），`arshift` 才是算术右移。
⚠️ **测试陷阱**：lupa 是 Lua 5.5 有 int64 子类型，旧错法跑不出问题。
要用 `2166136261.0` 浮点字面量强制 double 才能复现 5.1 行为。

---

# 三、组件表规范

违反表现为「导入成功但调用返回 nil」，极难排查。

## 3.1 非函数字段白名单只有两项

| 字段 | 是否豁免 |
|---|---|
| `propertys` | ✅ |
| `openFnArgs` | ✅ |
| `openFunctions`（自造） | ❌ **会报错** |
| `version` / `config` / 任何自定义表 | ❌ |

**开放函数列表由 `openFnArgs` 的键决定，根本不需要另列一份 `openFunctions`。**

## 3.2 实现函数必须 local 化

```lua
local function _iSay(self, s) ... end      -- ✅
function Script:SayImpl(self, s) ... end   -- ❌ 被引擎当开放函数，面板爆炸
```

## 3.3 顶层 local 上限 200（Lua 5.1 `LUAI_MAXVARS`）

撞上限的解法：把大块逻辑挂到模块表上，内部 local 独立计数——
`function Script._fastMatvec(...) end`（下划线开头不会被当开放函数，顶层 local 净增 0）。

## 3.4 openFnArgs 正确格式（**以实机脚本为准**）

```lua
Script.openFnArgs = {
    Rnd = {
        returnType  = Mini.String,
        displayName = "取随机数(留空=0~1小数)",
        params      = { "规格", Mini.String },   -- 扁平数组，名/类型交替
    },
}
```

- `params` 项数全为**奇数** = 「名、类型交替 + 末项是返回名（无类型）」
- ⚠️ 裸数组 `{ Mini.String }` 和 `{ p1 = Mini.String }` **都不是实机验证过的写法**
- ⛔ 实现了但没写进 `openFnArgs` 的函数 → **触发器根本调不到**

## 3.5 开放函数一律 pcall 包壳

```lua
function Script:Say(p1, p2)
    local ok, r = pcall(_iSay, self, p1, p2)
    if not ok then return 0 end
    return r
end
```

因为 `error` 不抛异常、只记日志、代码继续跑，不包壳会以"返回 nil"形式暴露，极难排查。

## 3.6 五个永不改名

| 对象 | 原因 |
|---|---|
| `propertys` / `openFnArgs` | 引擎**加载期**读，搬进 `OnStart` = 读到空 → 面板空白 → 二维表 ID 读不到 |
| `On*` 生命周期函数 | 引擎按**名字**调用，不走 openFnArgs 表 |
| 元方法 `__index` 等 | 改名 → `setmetatable` 槽位变 nil |
| `openFnArgs` 的**键** | 键就是函数名，改函数定义不改键 = 引擎按旧名找不到 |
| 混淆时的枚举名 | 属性类型对不上 |

> 「非函数字段放 OnStart」只是规范 WARN，**永远不要为满足它牺牲功能**。

## 3.7 元数据区的字符串不能用 `_DEC` 加密

`_DEC` 是 chunk 顶层 local，引擎在受限环境求值元数据时看不见。
要藏就用 `string.char(...)`（纯全局，可达）。

## 3.8 ID 预处理：数字 vs 字符串

引擎里**原版 ID 是数字，自定义 ID 是字符串（形如 `s_***`）**。

```lua
-- ❌ v="s_1773" 时 tonumber 返回 nil，nil>0 直接报错
if tonumber(v) > 0 then return tonumber(v) end
```

✅ 正确写法：先判 `type`，`number` 直接返回；`string` 先 `string.match(v,"^%d+$")`
再 `tonumber` 且 `>0`，否则**原样返回字符串**。

| 输入 | 输出 | 类型 |
|---|---|---|
| `1001` | 1001 | number |
| `"2002"` | 2002 | number |
| `"s_abc123"` | `s_abc123` | string |
| `"0"` | `"0"` | string |

---

# 四、组件属性系统

## 4.1 配置字段

```
type        属性类型（Mini.Xxx）
default     默认值
displayName 属性别名（面板显示名）
permission  访问权限：默认 Public / CmpProPermission.Private / Read
isSave      是否自动持久化：false = 不存
minValue / maxValue   数值范围（⛔ 是 minValue，写成 min 不报错但范围限制不生效）
tips        ✅【真机确认生效】面板提示文字
sort        ✅【真机确认生效】面板排列序号（小的在前）
```

**`isSave = false`** → 不自动落地，每次进游戏或出区块重载都取默认值。
官方建议**用组件属性存数据，而不是全局变量**。

⛔ **数组形式 `{ name="rsaBits", type=..., min=256 }` 是错的**——
`self.rsaBits` 取到 nil，所有默认值失效。必须键值映射。

## 4.2 Mini.CustomData：✅ 支持任意层级嵌套

```lua
{
    type = Mini.CustomData, displayName = "自定义数据",
    customDef = {
        name  = { type = Mini.String, displayName = "名称" },
        level = { type = Mini.Number, displayName = "等级" },
        items = { type = Mini.Array, itemType = Mini.Item, displayName = "物品列表" }
    }
}
```

### ⛔ 两种出现位置，写法不同（商店自定义2.lua 实证）

| | **A · 数组元素** | **B · 普通字段** |
|---|---|---|
| `type` | `Mini.Array` | `Mini.CustomData` |
| `itemType` | `Mini.CustomData` | —（不写） |
| `customDef` | ✅ | ✅ |
| 显示名 | `customDisplayName` + `displayName` | 只有 `displayName` |

**B 形（字段直接是 CustomData，不必经过 Array）**：

```lua
price = {
    type = Mini.CustomData, displayName = "价格",
    customDef = {
        currency = { type = Mini.String, displayName = "货币类型", default = "gold" },
        amount   = { type = Mini.Number, displayName = "数量", minValue = 0 }
    }
}
```

- **运行时 = 纯 Lua table**，键名就是 `customDef` 的键名（实测 5 层取值全通）
- ⛔ `customDef` 键名 = 运行时键名，**混淆/重命名不能改**，改了静默取 nil
- ⚠️ 增删改只作用在内存副本，**不回写属性面板** → 要持久化自己写 Data.*
- 数组索引在路径表达式里必须写**中括号**：`[1].name` 有效，`1.name` → nil
- `itemType=Mini.CustomData` 时 `default` 写法【未验证】→ 先不写
- ⚠️ **区分两套 CustomData**：组件属性的 `Mini.CustomData`（`customDef`）
  vs 道具实例 CustomData（`Item:Set/GetStringCustomData`，`instId+key+value`）。名字一样不是一回事。

## 4.3 其他

- `Mini.Enum`：`Script.MyEnum = Mini.Enum({ OPTION1 = {value=1, displayName="选项1"} })`
- `Mini.Bool` 的 `children = {"子属性1"}` → 勾选时才显示（联动显隐）
- 1.53 新增 7 种"组"类型（NUMBERGROUP=17 … EFFECTTYPEGROUP=24）【推测】= `Mini.Array(元素类型)`
- ⚠️ `Mini` 在转储里只有 `Array` 一个显式字段（走元表 `__index` 动态解析）
  → **"转储里没有"不等于"不存在"**

---

# 五、★ Trigger / TriggerEvent 事件体系（**最重要的模块**）

> 用户明确：**Trigger 主要是 TriggerEvent 事件注册，是最重要的。**

```lua
self:AddTriggerEvent(TriggerEvent.Xxx, self.Handler)
```

- 官方签名：`AddTriggerEvent(string 事件类型, function 回调, [过滤参1], [过滤参2])` → 无返回
- ⚠️ **该函数只在 UI 跟世界类型组件有效**
- `TriggerEvent.Xxx` 的值 = 字符串事件名（**252 个常量全部有值**），
  与旧 `ScriptSupportEvent:registerEvent([=[Player.ClickBlock]=], fn)` **完全等价**
- 事件参数九类统一：eventobjid / x,y,z / blockid / itemid / itemnum / toobjid / targetactorid
- 回调里另有 `event.CurEventParam`

---

# 六、广播通信体系

## 6.1 三套机制，别混用

| 机制 | 用途 |
|---|---|
| `self:AddCustomEvent` / `PushCustomEvent` | 组件自定义事件 |
| `ScriptSupportEvent:registerEvent` | 旧式事件注册 |
| `self:PushCloudServerMsg(类型, 内容...)` | 云服广播，第三参可定向房间 |

⛔ **匿名广播回调签名 `(cmp, eventId, param1...)` —— 载荷在第 3 参。**
写成 `function(_, msg)` 拿到的是 eventId，内容每帧恒等，**不报错**。

## 6.2 定时器（引擎自带，**优先于自造广播泵**）

```lua
self:DoPeriodicTask(fn, 秒[, 延迟, 次数])
self:DoTaskInTime(fn, 秒)
```

→ 新脚本**优先用它**，不要再自造"广播自驱动泵"。

## 6.3 协程

`self:ThreadWork(function() end)` 启动 / `self:ThreadWait(秒)` 等待（默认一帧）。
`coroutine.isyieldable` 判断当前能否 yield。

## 6.4 其他

- 消息 ID 必须是**预设 ID**（触发器里新建后才能用）
- 参数：数量不限、能传 table
- ⛔ **开放函数返回值人类看不见**——要人看到必须 `print` 到日志窗，或 `PushCustomEvent` 推广播

---

# 七、数据存储（最重要，用户强调无数次）

## 7.1 ⛔⛔ 两条"明确废除"

1. **`CloudSever`（注意是 Sever 不是 Server）已明确废除** → 云服一律走 `Data.Map`
2. **`Studio` 系列仅适用于 Mini Studio，不适用于 UGC 3.0**
   （`game:GetService` / Studio 版 `CloudService` 在 UGC 3.0 组件脚本里不成立）

## 7.2 ⛔⛔ 二维表限制（最终版）

| 方向 | 行数上限 | 体积上限 |
|---|---|---|
| **导入** | **2000 行** | **500KB** |
| **导出** | **2000 行** | **无限制** |

> **唯一限制就是 2000 行**。导入另加 500KB；**导出没有内存限制**。
> → **导出永远只开 1 张表**，把多条拼进一行即可，⛔ **绝不分片成多张表**。

- 做法：N 条记录用 `;` 拼进一行，`pack = ceil(总条数 / 1999)`
- 3840 条时 `pack=2` → 1920 行，**1 张表装完**
- 头部记 `PK:n`（合并数），读回时按它拆开逐条比对
- 只有当用户**手动设 pack=1** 且条数 >1999 时才需要多表
- 导出的表若要导入别存档 → 按**导入侧** 500KB + 2000 行设计

### ✅ 值的格式规则（真机确认）

1. 值可以是**任意可打印字符**（不可打印字符不行）
2. **没有换行**的前提下，值内部可以直接含 `"` 和 `,`
3. 用 `""` 包围的字符串，**类型明确为 string 时可以不加引号**
4. **单行长度无明确限制，可以到 500KB**
5. **转义字符可加可不加**

> 引号只是可选的语法糖。真正的硬约束只有「不能有换行」和「必须是可打印字符」。

### ⚠️ 逗号陷阱（最容易静默毁数据）

`ord(',') = 44` 落在 base85 字符集（33 + 35~117 + 126）内，
真实数据里就有 `),IkSQ` 这种含逗号的值。**绝不能用 `split(',')` 解析**，
必须靠引号定位（`string.find(line,'"')` 找首尾）。
`[^,]+` 还有第二个问题：**空字段会被跳过**（`"a,,b"` 得 2 个而非 3 个）。

## 7.3 ⛔⛔ Data 模块：四套 API 并存（**禁止只认 Data.Table**）

```
Data:函数API         ← Data 模块自身也有函数（不是只有三个子表）
Data.Map:函数API     ← KV 表 / 排行榜
Data.Array:函数API   ← 数组表
Data.Table:函数API   ← 二维表
```

查 API 时**四个都要探**。

### Data.Table 实机签名（以 建筑文件生成器3.1 为准，**禁止照转储猜**）

```lua
Data.Table:Clear(tableId, nil)
Data.Table:InsertValue(tableId, nil, 一个字符串)   -- 每行只传【一个】字符串
local all = Data.Table:GetAllValue(tableId, nil)   -- all[i][1] 才是值，第 1 行是头部
```

- 转储写的是变参 `self,varId,playerId,...`，**照它猜多传参数 → 行号被塞进第 1 列、
  数据挤到第 2 列，静默错位不报错**
- 第 1 行放头部（如 `BLD3|V1|DR:n|...`），读时 `for i=2,#all` 跳过
- 其余成员：GetValue / SetValue / GetCols / GetRowIndex / InsertValueByRow /
  UpdateAllValue / UpdateLineValues / RemoveRow / GetTableColKeys

**规则**：API 签名一律以实机跑通的脚本为准，转储只用来查「有没有这个成员」。

### Data.Array 实机签名（**与 Data.Table 参数个数不同，禁止互套**）

```lua
Data.Array:GetSize(varId)                       -- 2 参
Data.Array:GetValue(varId, nil, i)              -- 3 参
Data.Array:InsertValue(varId, nil, value, pos)  -- 4 参（可指定位置）
Data.Array:Remove(varId, nil, i)                -- 3 参
```

### 二维表 CSV 格式（真机验证过的那种）

```
字段备注,权重数据,
字段名,权重数据,
字段类型,string,
1,"MMLM|",
2,"9he;U0`V7T!!iQ)!!3-#!'gMa!...",
```

3 列：行号 / 引号包裹的值 / 空。前 3 行元数据。**首列必须是行号（数字），不能是逻辑名。**

## 7.4 Data.Map（KV 表 + 排行榜统一接口，13 个函数）

**开启**：开发者工具 → 触发器 → 变量库 → 全局变量 → 选「排行榜」或「表」

```
SetValueAndCallBack / SetValueAndBlock
RemoveValueAndCallBack / RemoveValueAndBlock
UpdateValueAndCallback                          ★ 服务端原子 RMW
GetValueAndCallBack / GetValueAndBlock
GetIndexValueAndCallback / GetIndexValueAndBlock     排行榜专用
GetNumValuesAndCallback / GetRangeValuesAndCallback  排行榜专用
SetRankValueAndBlock / ClearData
```

### ★★ `UpdateValueAndCallback` = 服务端原子读-改-写

**这是 KV 并发正确性的支点。** v3 之前用 Get+Set 两条独立调用，丢更新是必然的。

- 签名：`Data.Map:UpdateValueAndCallback(varId, playerId, key, callback) -> bool`
  **只有 4 参，没有 value**（带 value 的版本是玩家封装，不是官方签名）
- 语义：服务端托管 CAS + 自动重试。
  `GET(code=KV_UPDATE_GET)` → `SET(code=KV_UPDATE_SET, return 新值)` → 冲突则重新 GET/SET → `OK`
- 官方原话："确保数据不出错，不会被其他玩家覆盖"

**铁律（写任何 KV 并发代码前必须记住）**
1. 合并函数**必须是 join**（幂等+交换+结合）—— 重试时 base 每次都变，非幂等会重复累加
2. 回调会被调多次，不能用调用次数做业务计数
3. SET 与 OK 可能同值，必须用「值==刚返回的新值」或调用序号兜底
4. 重试耗尽 → 直接 set 最后合并结果仍是安全的（join 保证已见内容都在里面）

### ⛔ 四个硬限制

| 限制 | 值 |
|---|---|
| **Key** | **≤ 50 字节**，必须可打印**单字节**，**排除空格(32)** |
| **value** | **≤ 2MB**，✅ **可含不可打印字符**（可当比特流） |
| 限流 | 全图共享 `30 + 在线×10` 次/分 → **人均预算 ≈ 10 次/分** |
| 作用域 | `playerId = nil` → **房间级**；`playerId = 数值 uin` → **私人级** |

## 7.5 ⛔⛔ Data.Map 作用域语义（用户确认，权威）

- **`playerId = nil` → 房间级**（同一存档的房间内共享）
- **`playerId = 数值 uin` → 私人级**（该玩家跨房间/跨存档可见）
- **没有"全服级"这一档**：全服要靠**共享同一个 varId + 房间级 nil** 实现，
  **跨房间共享同一个 varId = 真**（已确认）
- 选错空间 = 数据互相看不见，**不报错**
- ⛔ **同一空间必须用同一个 pid 值建实例**：`FSGET(vid,nil)` 与 `FSGET(vid,0)`
  会建出**两份实例、两套缓存**，同空间两份副本互不可见
  （这是 KVFS v2 的 Hash/SimFind 恒 -404 的**更深层根因**）
- 修法：`PIDOF()` 把 `0 / "" / "0"` 一律归一为 `nil`；**uin 保持原样不归并**
- **一个脚本里所有 KV 调用必须走同一个 pid**，不能某个函数写死 nil、其余用 playerId

## 7.6 ⛔⛔ 存储载体选型：先看「能不能放不可打印字符」

| 载体 | 值能含不可打印字符？ | 单条容量上限 |
|---|---|---|
| **Data.Table（二维表）** | ❌ **不行**，只能任意可打印字符 | 单行可到 500KB；表限 **2000 行** |
| **Data.Map 的 Key** | ❌ 不行；**必须可打印单字节、排除空格** | **≤ 50 字节** |
| **Data.Map 的 value** | ✅ **可以**（可当比特流存） | **≤ 2MB** |
| **Data.Array** | ✅ **可以** | 上限待确认 |
| **其余所有字符串** | ✅ 可以 | **≤ 50MB** |

**推论（很实用）**
- 存二进制/压缩数据 → 选 **Data.Map / Data.Array**，
  **⛔ 不要套 base85**（省 25% 体积 + 编解码 CPU）
- 但**二维表路径上**值的"可打印"是硬约束 → **base85 仍是正解**
  → 同一份数据走两条路要两套编码，别搞混
- Data.Map 的 Key 建议用 **base85 哈希**：字符集 `33 + 35~117 + 126` **不含空格**，
  32 字节哈希 → 约 40 字符 < 50 字节，安全
- 2MB value ≠ 一次写 2MB：限流是 `30 + n×10` 次/分，单次塞满易超时；
  实践上**单次几十 KB + 分片**

---

# 八、并发与云服（多房间 / 千人规模）

## 8.1 已验证的架构（KVFS v4）

**op-based CRDT + 服务端原子 RMW**：

| v3（错） | v4（正） |
|---|---|
| Get+Set → 丢失更新 | 一律走 `UpdateValueAndCallback` 原子 RMW |
| 缓存永不失效 | 指针 seq 未变就一个字节都不多读 |
| ID = 时间戳+random，**同秒启动两客户端序列完全相同 → 碰撞** | **seq 块预留**：原子申领 64 个连续 seq，区间不重叠 |
| 限流失败静默当成功 | 显式返回 ERR |

**关键教训**：唯一 siteId 在双开/多实例场景下**根本做不到**（同 uin 必然同 id），
所以唯一性改由 seq 块预留承担。实测两个实例同 uin 同 siteId → 20 个对象全保留。

## 8.2 千人规模的硬天花板是配额，不是算法

官方配额 `30 + 在线×10` 次/分是**全图共享**，人均 ≈ 10 次/分。

> **铁律：`maxTrackSites × 60/autoSyncSec ≤ 10`**

稳态优化实测：50 站点首次同步 164 读 → 稳态 **50 读**（每站点 1 次指针读）。
没有这条优化就是 166 读，直接爆配额。

## 8.3 已放弃的路线

- **RAMP**（Bailis, SIGMOD 2014）**不适用**：要服务端为每个键保存版本元数据，
  你的 KV 没有；且要多次 prepare/commit 往返，配额扛不住
- **LWW** 会丢并发更新，**只能当可接受的策略，不能保证不丢数据**
- 正确路线是 **op-based CRDT**：不做"改父指针"，做**只追加 move 日志**，
  由日志推导树结构

## 8.4 已知限制（诚实版）

- **无跨键事务**（引擎没有）→ 用不可变 blob + join 绕开
- **无 GC**：op-log 只增不减，长期会撞 2MB → 需要快照压缩（未实现）
- 未投递的本地 op 随进程死亡丢失（语义上等于没提交）
- 站点发现偏弱：跨房间要填 `peerSites` 属性，或靠根（会被覆盖）

---

# 九、性能：纯 Lua 引擎的优化判据

## ⛔ 通用公式

> **省「操作次数 / 解释开销」有效；省「搬运带宽 / 提高算术强度」无效。**

- ✅ 有效：批量取字节、把值缓存到 local、减少 table 访问
- ❌ 无效：推测解码、batch GEMM（实测只有 1.17~1.24x）、权重条带重排

原因：GPU 瓶颈是搬权重（提高算术强度是白赚），
**纯 Lua 解释器的成本 ≈ 操作次数 × 解释开销**，批处理省不掉乘加。

> **推论**：视频里所有"变粗/批量"的收益都建立在带宽墙上。
> 判断一个优化能不能用，先问它省的是「搬运」还是「操作次数」。

## 9.1 matvec 加速（MiniMind2 v24Acc1，实测 2.51x）

**结论：权重条带重排（repack）是负收益，永远别再做。**

- v24Acc 慢且卡：每处理一个 32 行条带都要把 32 个累加器重新清零；
  启动 repack 全模型 0.4~2.5 秒，元凶是**逐字节 `string.char`（2580 万次调用）**
  → 这就是实机"卡顿/失败"的根因（超时中断 → 部分矩阵重排、部分没重排）

- **正确做法：把循环倒过来——【列块在外、行在内】**

```lua
while jb <= lim do
    local x0,...,x63 = x[jb], ..., x[jb+63]      -- 64 个 local，被所有行复用
    for i = 0, rows - 1 do
        local b0,...,b63 = sb(s, off, off + 63)  -- 一次取 64 字节
        out[i+1] = out[i+1] + b0*x0 + ... + b63*x63
```

  `x[j]` 的 table 访问从 **2580 万降到 512**，`string.byte` 调用再降 64 倍。
  **零 repack、零启动开销。**

- 实测：0.409 → **0.163 秒/token（2.51x）**；embRow 4.05x
  **新旧输出 maxdiff = 0，逐位精确**
- local 用量：matvec 143 / embRow 75（上限 200）。
  真机报超限（尤其过混淆器后）→ 降级 BLK=32（约 2.42x，local 79）
- ⚠️ 之前报的 "3.65x" 是相对更早基线，**不可复现**

## 9.2 int8 量化（仅 MB 级数据才值得）

```
[ f32 scale × rows ]  [ uint8 (w+128) × rows×cols ]
反量化：w = (byte - 128) × scale
```

直接 `string.byte` 取原始值相乘，**行末减一次 `128·sumX`**：
`Σ w[j]·x[j] = Σ (b[j]-128)·x[j] = Σ b[j]·x[j] - 128·Σx[j]`

| 对比项 | 结果 |
|---|---|
| Lua vs Python 偏差 | 1.045e-06 |
| 分类一致 | 60/60 |
| 体积 | 15496 B → 1466 B（9.5%） |

⚠️ **API 清单、配置表、日志这类小数据必须原文直出**，再压缩就是错的。

---

# 十、⛔ 静默失效清单（最重要，全是不报错只给错结果）

| # | 症状 | 根因 | 修法 |
|---|---|---|---|
| 1 | 收不到广播 / 内容每帧恒等 | 匿名回调签名 `(cmp, eventId, param1...)`，**载荷在第 3 参** | `function(cmp, eid, p1, ...)` |
| 2 | SHA-256 全错 | `bit.ror` 自拼时 nil 被 pcall 吞 | **原生 `ror` 存在，直接用** |
| 3 | SHA 大数算错 | 算术右移：`_t(x)` 把 ≥2^31 转负数，`floor` 变补 1 | 先取无符号 `(x % 2^32)` 再移 |
| 4 | 熵永远攒不够 | 播种逻辑塞在只有取数才走到的分支里 | 熵攒够即自动播种 |
| 5 | 二维表第一列全是 1,2,3 | `InsertValue` 多传参数 | **只传一个字符串** |
| 6 | 属性面板空白 / 二维表读不到 | `propertys` 搬进了 `OnStart` | 留顶层 |
| 7 | 触发器看得到函数但返回 nil | `openFnArgs` 键与函数名不同步 | 同步改 |
| 8 | 归一化后分数全是垃圾 | **只导权重不导 `mean/std`** | 一起导 |
| 9 | base85 解码崩 | `~q` 正好被切在两张表之间，逐表还原漏掉 | **对整个拼接串做还原** |
| 10 | 末字节错 1 | 标准 Ascii85 末组截断，末位 digit=84 时借位破坏前一字节 | 编码前补零到 4 倍数，永不截断末组 |
| 11 | 计时器没销毁 / 返回 0 | **前向引用**取到全局 nil（被 pcall 吞） | 被引用的 local 必须先定义 |
| 12 | 最后 N 个音节不发音 | 多行字符串拼接**行尾漏逗号**，`id100id101` 并成一段 | 三表对齐校验 |
| 13 | 结果永远查不出作弊 | `math.pow` / `math.tanh` 被误判不存在而走了空兜底 | **引擎有，直接用** |
| 14 | 收尾必崩 | `Kill` 函数定义在 `_finish` **之后**，取到全局 nil | 卡在 `_finish` 之前、`_pump` 之后 |
| 15 | 循环变量赋值崩 | Lua 5.5 禁 `s = f(s)`（5.1 允许） | 写成新变量 |
| 16 | 属性 `default` 全失效 / 范围限制不生效 | propertys 写成数组形式 / `min` 写成 `min` | 键值映射 + `minValue` |
| 17 | 私人空间 Hash/SimFind 恒 -404 | 某函数写死 `FSGET(vid,nil)`，其余用 playerId | 全部走 `PIDOF()` |
| 18 | 单字节重复内容读取崩溃 | 哈夫曼树退化成单叶，走 `node.l/node.r` 得 nil | `if t.b then` 直接按 bl 输出 |
| 19 | 缓存看不到别人改动 | 缓存无 TTL | 加 TTL + **resolve 未命中时丢缓存重试一次** |
| 20 | 同秒启动两客户端 ID 撞车 | `math.random` 同 seed 序列相同 | 混入 salt + 生成后查占用 |

## 10.1 调试期通用坑

- **循环变量赋值**：`for _, s in ipairs(l) do s = lower(s) end` — Lua 5.5 报
  `attempt to assign to const variable`。写成新变量。
- **定位串误删**：批量修改时普通注释里的相同文字会被误命中，定位标记要加特殊前缀。
- **开放函数返回值人类看不见**：返回值只能给别的脚本。要人看到必须
  `print` 到日志窗，或 `PushCustomEvent` 推广播。

---

# 十一、⛔ 已废除的错误知识（档案，勿再用）

| 废除项 | 真相 |
|---|---|
| ~~引擎是 LuaJIT / FFI 可见~~ | `jit=nil` `ffi=nil`。曾据截图七个字段名（fill/copy/gc/load/string/arch/os）断定是 LuaJIT——**错了**，那七个与 LuaJIT 的 ffi 成员同名，但实机 ffi 是 nil，据此规划的全部 FFI 加速作废 |
| ~~bit 只有 rol 没有 ror~~ | 12 成员**含 ror** |
| ~~math.tanh 不存在需自带~~ | 引擎 math 34 成员全有 |
| ~~table.concat 不是函数~~ | 那是 lupa 5.5 沙盒，不是引擎 |
| ~~导出二维表分片多张表~~ | **只用 1 张，一行放多条** |
| ~~Data.Map:GetMapValue~~ | 真机不存在 |
| ~~CloudSever 可用~~ | 已废除，走 Data.Map |
| ~~Studio CloudService 可用于 UGC 3.0~~ | 仅适用 Mini Studio |
| `Lua5.1数学库缺失与实测坑.md` | **整体废除**（前提就是错的）。
文中"静默失效 7 类"仍有效，已并入 §10 |

---

# 十二、交付纪律（血泪，红线）

1. **说"做好了/已生成"必须同轮带文件** —— 已违规 4 次
   （v3.3、反作弊 zip、RSA v2、真随机 v3）
2. **更严重**：反作弊 zip **文件根本不存在**却说"已打包"（属编造，非疏漏）
3. **对策：⛔ 先交付再写说明；交付前核 md5**
4. **先交付、再写正文**——把交付当成独立动作，写完文字不等于收工
5. **凡在回复里说"做好了"，必须同一轮带上文件——不带就是没做完**

> 用户原话：**"每次没给（文件）的时候我都发现有问题。"**
> 规律：跳过交付动作的轮次，内容多少都有没验证到的地方——
> 因为交付会逼出最后一次核 md5、核文件存在。

## 12.1 主管红线

不编造未验证结论 / 不泄露凭证 / 不删历史只归档 /
不交未验证产物 / 关键问题最多问两次

---

# 十三、待真机验证清单

- [ ] `loadstring` 到底能不能用（转储=function / 早期实测=nil / 10-18探针=function，三源冲突）
- [ ] `string` 的 `startswith` / `endswith` / `dump` / `IsBlank` / `Contains` 是否存在
- [ ] `table` 的 `merge` / `move` / `show` / `num_pairs` / `foreach` / `foreachi` / `maxn` / `tostring` / `getn`
- [ ] 1.53 七种"组"类型在脚本侧的确切写法
- [ ] `DoPeriodicTask` / `DoTaskInTime` 在 1.59.0 各组件类型上的可用性
- [ ] `AddTriggerEvent` "只在 UI/世界组件有效"的精确边界
- [ ] `Data.Array` 单条容量上限的确切数值
- [ ] `ErrorCode` 完整枚举值
- [x] ~~属性字段 `tips` / `sort` 是否生效~~ → ✅ **已确认真机生效**
- [x] ~~Studio 版 `CloudService`~~ → ✅ **已明确不适用于 UGC 3.0**
- [x] ~~`Data.Map` 数据长度上限~~ → ✅ Key ≤50 字节；value ≤2MB

> **规则**：推测项（一层 API 库里 160 条）调用前必须 `type(模块.函数)` 判存在，
> **不要当成可用 API 直接写进业务代码**。

---

# 十四、沙盒测试环境（≠ 引擎）

- ⛔ **lupa 默认后端是 Lua 5.5，不是 5.1**。此前多轮声称"lupa 真 Lua 5.1
  与引擎同版本"是**错的**。要用 **lupa 的 `lua51`**。
- 5.5 有 `os.clock`、`math.tanh`、`table.concat`、int64 子类型 → 掩盖精度问题
- ⛔ **造 mock 引擎的坑**：按转储生成 mock 时若直接覆盖
  `pairs`/`print`/`type`/`string`/`math`/`table`/`os` 等保留名，
  会**把解释器自身库覆盖掉**，后续全废且报错无对象。
  必须跳过保留名（_G/_ENV/string/math/table/os/io/coroutine/package/type/print/
  pairs/ipairs/select/require/tostring/tonumber/next/error/pcall/unpack/debug/bit/jit/ffi/arg）
  —— 但 **Data 不能跳过**（它是引擎模块，需 `Data = {}` 先建）
- **KV 存储必须放在 Lua 侧的 table 里**。若走 Python 函数传参，含非 UTF-8 字节的
  Lua 字符串会在 `py_from_lua` 处抛 UnicodeDecodeError（压缩后内容必触发）
- **Python 函数塞进 Lua 表后 `type()` 是 `userdata` 不是 `function`**，
  会让 `type(bit.ror)=="function"` 这类自检假失败 → 要包成 Lua 闭包
- **二进制（Pack 结果）不能经 Python 往返**，必须在 Lua 内一次完成
- **测试多客户端并发**：单个 Lua 状态里把脚本源码执行 N 次，每次得到独立
  Script 表 = N 个"客户端"（各自独立的模块级 local）。比开 N 个状态更好。

---

# 十五、当前资产清单（/data/workspace）

## 主力脚本

| 文件 | 用途 |
|---|---|
| `MiniMind2_纯净版v2.lua/.txt` | 146989 B，裸模型测试，广播输出，7 个开放函数 |
| `MiniMind2_增强版v24Acc1.txt` | 319717 B，matvec 2.51x，逐位精确 |
| `KV文件系统_云服版v4.lua/.txt` | 58396 B，服务端原子 RMW，CRDT op-log |
| `KV文件系统_房间个人版v2.1.lua/.txt` | 113043 B，md5 `f9405852`，86 项断言 |
| `API全模块探针.lua/.txt` | 29177 B，递归二层扫描 284 模块 |
| `真随机数生成器v4.lua/.txt` | 33497 B，`RndInt(最小,最大)` 闭区间整数 |
| `RSA_证书版v5.lua/.txt` | 62630 B，跨存档跨游戏，证书+签名 |
| `LuaVM桥接.lua` | 154180 B，自写 Lua 5.1 VM，宿主↔VM 17/17 全通 |

## 知识文档

| 文件 | 用途 |
|---|---|
| `_kb/迷你世界UGC3.0_权威脚本知识手册.md` | 1135 行主手册 |
| `_kb/一层API全量知识库.md` | 749 函数 + 244 枚举，三源标注 |
| `Mini.CustomData_格式与用法.md` | 商店脚本实证 |
| `KV文件系统v4_设计说明.md` | 并发设计、配额数学 |
| `KV环境一致性_前沿文献研究.md` | CRDT/HLC/RAMP/Merkle-DAG 逐条评估 |

## 转储

`apitool/dump_parsed.json`：7267 顶层键、**284 个 table 模块**、一层成员 **3840**
（TriggerEvent 252 / ObjectEvent 182 / Player 309 / Monster 162 / Actor 136 / World 125）

> ⛔ **转储是扁平路径式**，不是嵌套表：键 = `模块.成员.子成员`。
> 其中 **189 个是 table 型直接成员**（Data.Map / Data.Table 这类），
> **需递归才有二层**。探针 v1~v3 只展开一层，漏掉全部二层成员。
> **扫描 API 必须递归到 depth>=2。**
> ⛔ 转储把标准库也当模块（_G/string/math/table/os/io/coroutine/package/...）。
> 正解：模块列表 = 顶层且 `type=='table'` 的 key（285 个），不是全部顶层 key。

**铁律：以运行时二维表结果为准**，转储清单只用来提示「哪个模块不见了」。

---

# 十六、上次会话状态（2026-10-19）

## 最近完成

| 项 | 状态 |
|---|---|
| KVFS 房间/个人版 v2.1 | ✅ 9 条修复，86 项断言全过，md5 `f9405852` |
| KVFS 云服版 v4 | ✅ 38 项断言，含对抗性并发调度（190 次抢写 / 105 次 CAS 重试） |
| Data.Map 作用域语义 | ✅ 用户确认：nil=房间，数值=私人，跨房间共享同一 varId |
| Mini.CustomData | ✅ B 形（字段直接 CustomData）实证 |
| 权威脚本知识手册 | ✅ 989 行 / 41.7KB，10 篇旧文档已并入归档 |

## 用户本轮强调（写进纪律）

- **Trigger 主要是 TriggerEvent 事件注册，是最重要的模块**
- **threadpool / json / coroutine / os / bit 确定存在，必须用，禁止降级兜底**
- **导出没有内存限制，直接导出原版，不用编码压缩** —— 我此前完全没记住，已置顶
- **二维表导入 500KB + 2000 行；导出只有 2000 行，无内存限制**
  → 导出一律只用 1 张表，一行填多个

## 未决问题

- `loadstring` 三源冲突（转储 function / 早期实测 nil / 探针 function）
- `string` / `table` 两版探测结果冲突
- `Data.Array` 单条容量上限未定
- KVFS v4 无 GC，op-log 长期会撞 2MB → 快照压缩未实现

## 下一步可选

1. 修 KVFS v4 的 GC（快照压缩）
2. 用 `DoPeriodicTask` 替换各脚本里的自造广播泵
3. 真机跑 API 全模块探针，回收 160 条推测项的验证结果
4. 补 `Data.Array` 容量上限探针
