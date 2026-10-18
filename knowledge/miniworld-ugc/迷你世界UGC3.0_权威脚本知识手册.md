# 迷你世界 UGC 3.0 · Lua 脚本权威知识手册

> **版本**：v2026.10.18　**取代**：此前 miniworld-ugc 目录下全部零散文档
> **原则**：以**实践结果为准**。转储只用于查"有没有这个成员"，
> **签名一律以实机跑通的脚本 / 官方文档为准**。
> **证据等级**：【已测】实机或用户实测 · 【官方】官方文档 · 【转储】环境转储 · 【推测】待验证

---

# 〇、阅读前必读：三条总纲

1. **转储存在 ≠ 可用。**
   `loadstring` 在转储里是 function，用户早期实测返回 nil，10-18 探针又是 function。
   判断可用性唯一途径是 `type(x)` + 实调，不能只看清单。

2. **API 签名不照转储猜。**
   转储写 `Data.Table:InsertValue(self, varId, playerId, ...)` 变参，
   照它传多个参数 → **行号被塞进第 1 列、数据挤到第 2 列，静默错位不报错**。
   实机可用写法只有一个字符串参数（见 §8）。

3. **确定存在的模块，直接用，禁止写降级兜底。**
   `bit` / `json` / `threadpool` / `coroutine` / `os` / `math` / `string` / `table`
   均已确认存在。**为它们写"自拼/自实现"的降级路径是错的**——
   既慢，又会把真 bug 藏进兜底分支里（见 §11 列举的 4 次事故）。

---

# 一、运行环境硬事实

| 项 | 值 | 证据 |
|---|---|---|
| Lua 版本 | **5.1**（修改优化版）`_VERSION = "Lua 5.1"` | 【已测】 |
| 是否 LuaJIT | **否**，`jit = nil`、`ffi = nil` | 【已测】10-18 探针 |
| 运行位置 | **主机端**（单人=自己，联机=房主设备，云服=官方服务器） | 【官方】 |
| 状态更新 | **50 ms = 1 tick** | 【官方】 |
| 大数 | **double**，`2^53` 与 `2^53+1` 完全相同 → 大整数必须自实现 BN | 【已测】 |
| 文件 IO | **无**，`io` 空表、`package` 空表 | 【已测】 |
| 错误行为 | `error` **不抛异常**，只记日志，代码继续往下跑 | 【官方】miniExtend |

## 库成员清单（两版探测有差异，用前 `type()` 判存在）

| 库 | 用户早期文档版 | 10-18 真机探针版 | 处理 |
|---|---|---|---|
| `os` | — | **3 个**：`date` `time` **`timeMs`** | ✅ 一致，`os.clock` **不存在**，用了必崩 |
| `math` | 34 个 | 34 个 | ✅ 一致（含 `tanh` `pow` `clamp` `lerp` `mod` `ldexp` `approximately` `log10`） |
| `bit` | 12 个 | 12 个 | ✅ 一致，**含 `ror`** |
| `string` | `startswith` `endswith` `split` `dump` `IsBlank` `Contains` `Trim` | `Trim` `split` | ⚠️ **冲突，用前判存在** |
| `table` | 15 个（`clone` `equal` `merge` `move` `show` `num_pairs` `foreach` `foreachi` `maxn` `tostring` `getn`） | 8 个 | ⚠️ **冲突，用前判存在** |
| `coroutine` | 7 个（含 `isyieldable`） | 7 个 | ✅ 一致 |
| `debug` | 1 个 `traceback` | 1 个 | ✅ 一致 |
| `json` | `encode` `decode` | — | ✅ **确定存在**，官方全局函数页 |
| `threadpool` | `Work` `work` `wait` `Wait` | — | ✅ **确定存在** |

## ⛔ 禁止降级清单（用户 2026-10-18 明确指令）

以下模块**必须用原生**，不要再写自实现兜底：

```
bit         12 成员全在：arshift band bnot bor bswap bxor lshift ror rshift tobit tohex
                        bit.lshift(1,31) = -2147483648  → 有符号 32 位，取高位要 +4294967296
json        json.encode(table) -> string   /   json.decode(string) -> table
threadpool  threadpool:wait(秒)  —— 等待；官方 FAQ「如何等待1秒后继续执行」的标准答案
coroutine   7 个成员全在，含 isyieldable
os          os.timeMs() 毫秒时间戳 —— 所有按时间推进的调度一律用它
math        tanh / pow / clamp / lerp / mod / ldexp / approximately 引擎都有
```

> **历史事故**：真随机数 v2 源码注释写「引擎 bit 只有 rol 没有 ror（**记忆实测**）」，
> 于是绕开原生 `ror` 自拼。`ror` 其实**就在 12 个成员里**。
> 「记忆实测」四个字就是病根——它不是实测。
> **纪律：涉及"引擎某 API 存不存在"，必须回查转储或探针，禁止凭记忆下结论，
> 更禁止在注释里写"（实测）"三个字。**

---

# 二、两套脚本上下文（别混用）

| | 触发器脚本（旧） | **组件脚本（新，UGC 3.0 推荐）** |
|---|---|---|
| 入口 | 全局函数 | `local Script = {}` … `return Script` |
| 注册事件 | `ScriptSupportEvent:registerEvent([=[Player.ClickBlock]=], fn)` | `self:AddTriggerEvent(TriggerEvent.PlayerClickBlock, self.Handler)` |
| 回调签名 | `function 名(event)` | `function Script:Handler(event)` |
| 属性 | 无 | `Script.propertys`（面板可配） |
| 开放函数 | 无 | `Script.openFnArgs`（触发器可调用） |
| 定时器 | 需自己实现 | `self:DoPeriodicTask` / `self:DoTaskInTime` |

**新项目一律用组件脚本。**

## 桥梁：`TriggerEvent.Xxx` 的值 = 字符串事件名

转储里 **252 个 TriggerEvent 常量全部有值，值就是字符串事件名**：

```
TriggerEvent.ActorCreate      = "Actor.Create"
TriggerEvent.GameHour         = "Game.Hour"
TriggerEvent.PlayerClickBlock = "Player.ClickBlock"
TriggerEvent.GameStart        = "Game.Start"
```

所以两套写法**完全等价**：

```lua
-- 旧
ScriptSupportEvent:registerEvent([=[Player.ClickBlock]=], OnClick)
-- 新
self:AddTriggerEvent(TriggerEvent.PlayerClickBlock, self.OnClick)
```

【转储】252/252 个常量均带字符串值。

## 组件脚本骨架（8 个官方模板的共同结构）

```lua
local Script = {}

-- ① 属性定义（引擎加载期读，面板显示）
Script.propertys = {
    varNum = { type = Mini.Number, default = 99, displayName = "数值" },
    varStr = { type = Mini.String, default = "你好！", displayName = "文本" },
}

-- ② 开放函数签名
Script.openFnArgs = {
    Add = {
        returnType  = Mini.Number,
        displayName = "函数别名",
        params      = { "a", Mini.Number, "b", Mini.Number },  -- 名/类型交替
    },
}

-- ③ 启动
function Script:OnStart()
    self:AddTriggerEvent(TriggerEvent.PlayerClickBlock, self.OnPlayerClickBlock)
    self.task = self:DoPeriodicTask(self.OnPeriodicTask, 3)
end

-- ④ 开放函数
function Script:Add(a, b)
    if a and b then return a + b end
end

return Script   -- 必须有，否则引擎拿不到组件表
```

## 官方 8 种组件类型

| 组件 | 挂载对象 | 典型用途 |
|---|---|---|
| 世界组件 | 世界节点 | 全局玩法逻辑、玩家点击方块 |
| 玩家组件 | 玩家 | 玩家相关 |
| 生物组件 | 生物 | 生物行为 |
| 实体组件 | 实体 | 右键交互 |
| 方块组件 | 方块 | 方块被破坏掉落 |
| 界面组件 | UI | UI 按钮、自定义事件 |
| 状态效果组件1 | 状态 | 周期加血 |
| 状态效果组件2 | 状态 | 一次性加血 |

---

# 三、组件表规范（违反表现为"导入成功但调用返回 nil"）

## 3.1 非函数字段白名单只有两项

引擎会检查组件表字段构成，除白名单外**任何非函数字段**触发：
「定义的表中不能有非函数字段，初始化数据在 OnStart 中执行」

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
function Script:SayImpl(self, s) ... end   -- ❌ 被引擎当成开放函数，面板爆炸
```

实测：20 个 `XxxImpl` 直接导致面板多出 20 个冗余项。

## 3.3 顶层 local 上限 200（Lua 5.1 `LUAI_MAXVARS`）

```lua
local a1, ..., a201   -- ❌ 编译失败
```

撞上限的解法：把大块逻辑挂到模块表上，内部 local 独立计数：

```lua
function Script._fastMatvec(...) end   -- 下划线开头不会被当开放函数，顶层 local 净增 0
```

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

⚠️ 裸数组 `{ Mini.String }` 和 `{ p1 = Mini.String }` **都不是实机验证过的写法**。
（三个实机脚本：中文转拼音 / 音节TTS v3.3 / 真随机数 v1，三者格式一致。）

## 3.5 开放函数一律 pcall 包壳

```lua
function Script:Say(p1, p2)
    local ok, r = pcall(_iSay, self, p1, p2)
    if not ok then return 0 end
    return r
end
```

因为引擎里 `error` **不抛异常、只记日志、代码继续跑**，
不包壳的错误会以"返回 nil"的形式暴露给调用方，极难排查。

## 3.6 五个永不改名

| 对象 | 原因 |
|---|---|
| `propertys` / `openFnArgs` / `openFunctions` | 引擎**加载期**读，挪进 `OnStart` = 读到空 → 面板空白 → 二维表 ID 读不到 |
| `On*` 生命周期函数 | 引擎按**名字**调用，不走 openFnArgs 表 |
| 元方法 `__index` 等 | 改名 → `setmetatable` 的 `__index` 槽位变 nil |
| `openFnArgs` 的**键** | 键就是函数名，改函数定义不改键 = 引擎按旧名找不到 |
| 混淆时的枚举名 | 属性类型对不上 |

## 3.7 元数据区的字符串不能用 `_DEC` 加密

`_DEC` 是 chunk 顶层 local，引擎在**受限环境**求值元数据时看不见。
要藏就用 `string.char(...)`（纯全局，可达）。

## 3.8 ID 预处理：数字 vs 字符串

引擎里**原版 ID 是数字，自定义 ID 是字符串（形如 `s_***`）**。

```lua
if tonumber(v) > 0 then return tonumber(v) end   -- ❌ v="s_1773" 时 tonumber 返回 nil，nil>0 直接报错
```

正确写法：

```lua
local function _pytoyp(v)
    if v == nil then return nil end
    if type(v) == "number" then return v end
    if type(v) == "string" then
        if string.match(v, "^%d+$") then
            local n = tonumber(v)
            if n ~= nil and n > 0 then return n end
        end
        return v                       -- s_*** 原样返回
    end
    local ok, n = pcall(tonumber, v)
    if ok and n ~= nil and n > 0 then return n end
    return v
end
```

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
minValue / maxValue   数值范围（注意是 minValue，不是 min）
```

**`isSave` 很重要**：`false` → 不自动落地，每次进游戏或出区块重载都取默认值。
默认自动落地保存。官方建议**用组件属性存数据，而不是全局变量**。

⚠️ `tips` / `sort` 官网没提，用户手册里有，**待真机验证**。

## 4.2 属性类型：官网 13 种 vs 手册 50+ 种

官网只公开 13 种。手册里有但官网查不到的（**标【未验证】**）：

```
Mini.Vec2 / Rotation / Scale / Entity / Object / Player / Mob / Role
Mini.UiElement / UiState / Tag / Area / BiomeType / PathPoint
Mini.Action / LineAnimation / ModelAction / SkyBox / SkyBoxFilter / Material
Mini.CheckList / GroupView / CustomMsg / Prefab / Blueprint
Mini.DropItem / ThrowItem / SkeletonPoint
Mini.CreatureType (=MobType) / Mini.Creature (=Mob)
```

⚠️ `Mini` 在转储里**只有 `Array` 一个显式字段**——因为走元表 `__index` 动态解析，
转储抓不到。**"转储里没有"不等于"不存在"。**

## 4.3 1.53 新增：7 种"组"类型

```
NUMBERGROUP=17  STRINGGROUP=18  BOOLEANGROUP=19  BLOCKTYPEGROUP=20
ITEMTYPEGROUP=21  CREATURETYPEGROUP=22  TIMERGROUP=23  EFFECTTYPEGROUP=24
```

【推测】组类型很可能就是 `Mini.Array(元素类型)` 的实现（`itemType` + `maxNum`）。

## 4.4 Mini.CustomData：嵌套结构

```lua
{
    type = Mini.CustomData,
    displayName = "自定义数据",
    customDef = {
        name  = { type = Mini.String, displayName = "名称" },
        level = { type = Mini.Number, displayName = "等级" },
        items = { type = Mini.Array, itemType = Mini.Item, displayName = "物品列表" }
    }
}
```

⚠️ **区分两套 CustomData**：组件属性的 `Mini.CustomData`（`customDef`）vs
道具实例 CustomData（`Item:Set/GetStringCustomData` 等，`instId + key + value`）。名字一样，不是一回事。

## 4.5 Mini.Enum：下拉选项

```lua
Script.MyEnum = Mini.Enum({
    OPTION1 = { value = 1, displayName = "选项1" },
    OPTION2 = { value = 2, displayName = "选项2" }
})
{ type = Script.MyEnum, default = Script.MyEnum.OPTION1, displayName = "枚举选项" }
```

## 4.6 Mini.Bool 的 children：联动显隐

```lua
{ type = Mini.Bool, default = true, displayName = "启用功能",
  children = { "子属性1", "子属性2" } }   -- 勾选时才显示
```

---

# 五、★ Trigger / TriggerEvent 事件体系（**最重要的模块**）

> 用户 2026-10-18 明确：**Trigger 主要是 TriggerEvent 事件注册，是最重要的。**

## 5.1 注册方式

```lua
-- 组件脚本（推荐）
self:AddTriggerEvent(TriggerEvent.Xxx, self.Handler)
self:AddTriggerEvent(TriggerEvent.UIButtonClick, self.OnBtnClick, "元件id")  -- 第三参=过滤
self:AddTriggerEvent(TriggerEvent.PlayerInputKeyDown, self.OnKeyW, KeyCode.W)

-- 触发器脚本（旧）
ScriptSupportEvent:registerEvent([=[Player.ClickBlock]=], function(event) ... end)
```

### `AddTriggerEvent` 官方签名

```
参数：string   事件类型
      function 回调函数
      number|string 过滤参数1（可不传）
      number|string 过滤参数2（可不传）
返回：无
作用：添加触发事件（⚠️ 该函数只在 UI 跟世界类型组件有效）
```

⚠️ **只在 UI 组件和世界组件有效**——这是硬限制，挂在别的组件上不生效。

## 5.2 事件参数（九类，参数形式统一）

| 类 | 例 | 参数 |
|---|---|---|
| 世界 | 背包物品变化 | blockid, itemid, itemnum, x, y, z |
| 游戏逻辑 | 世界小时变化 | hour |
| 玩家 | 玩家死亡 | eventobjid, shortix, x, y, z |
| 生物 | 生物死亡 | eventobjid, toobjid, actorid |
| 方块 | 被创建 | blockid, x, y, z |
| 道具 | 掉落物被创建 | eventobjid, itemid, defaultvalue, x, y, z |
| 特效 | 特效被创建 | effectid, x, y, z |
| UI | 界面被打开 | eventobjid, CustomUI |
| 其他 | 购买会员 | eventobjid |

**玩家点击方块**（模板注释明确）：`event.eventobjid  event.blockid  event.x  event.y  event.z`
另有 `event.CurEventParam`（触发器的当前事件参数）。

## 5.3 常用事件常量（官方事件系统页摘抄）

**游戏**
```
TriggerEvent.GameStart              游戏创建（无传参）
TriggerEvent.GameHour               游戏时间（传参 hour）
TriggerEvent.GroupWeatherChanged    地形组天气改变
TriggerEvent.MinitimerChange        计时器改变（timerid / timername / timertime）
TriggerEvent.CraftEnd               配方合成完毕（eventobjid,targetactorid,itemid,itemnum）
TriggerEvent.FurnaceBegin/End       熔炼开始/结束（x,y,z）
TriggerEvent.TimelineStart/Stop     剧情动画开始/结束（customdata,defaultvalue,second,...）
```

**玩家**
```
TriggerEvent.PlayerRevive               玩家复活（eventobjid,x,y,z）
TriggerEvent.PlayerMoveOneBlockSize     玩家移动（eventobjid,x,y,z）
TriggerEvent.PlayerSelectShortcut       玩家选中快捷栏（eventobjid,x,y,z,itemid,shortix,itemnum）
TriggerEvent.PlayerInvateFriend         玩家邀请好友（eventobjid,x,y,z,toobjid）
TriggerEvent.PlayerInputKeyClick        任意玩家点击按键（eventobjid,x,y,z）
TriggerEvent.PlayerAddItem              玩家获得道具（eventobjid,x,y,z,itemid,itemnum）
TriggerEvent.PlayerClickBlock           玩家点击方块
```

**方块**
```
TriggerEvent.BlockAdd                   方块被创建（x,y,z,blockid）
TriggerEvent.BlockDigBegin              方块被挖掘（x,y,z,blockid,eventobjid,targetactorid）
TriggerEvent.BlockDestroyBy             方块被破坏
TriggerEvent.BlockTrigger               方块被触发
TriggerEvent.BluePrintBuildBegin        放置蓝图（areaid）
```

**特效 / 界面**
```
TriggerEvent.ParticlePosOnCreate        特效创建在任意位置（eventobjid,x,y,z,effectid）
TriggerEvent.ParticleItemOnCreate       特效创建在掉落物
TriggerEvent.UIButtonClick              界面元件被点击（eventobjid,uielement,x,y,z）
TriggerEvent.UILostFocus                界面输入字符串（eventobjid,content,uielement）
```

**对象（碰撞与区域）**
```
TriggerEvent.PlayerCollideToPlayer      玩家撞玩家（eventobjid,targetactorid,x,y,z,toobjid）
TriggerEvent.PlayerAreaIn               玩家进入区域（eventobjid,targetactorid,x,y,z）
```

> 完整 252 条以真机探针导出的二维表为准（见 §8.4 探针）。

## 5.4 个体事件：ObjectEvent（对象自身）

```lua
self:AddEvent(ObjectEvent.Xxx, self.Handler)     -- 转储里 182 个常量
```

---

# 六、组件实例方法（`self:` 系列，引擎注入，转储抓不到）

> 转储只抓 `_G` 全局环境，**抓不到实例方法**。以下来自 8 个官方模板 + 官方 Wiki。

## 6.1 事件监听 / 发送

```lua
self:AddTriggerEvent(TriggerEvent.Xxx, self.Handler)      -- 触发器事件
self:AddEvent(ObjectEvent.Xxx, self.Handler)              -- 个体事件（对象自身）
self:AddCustomEvent("广播ID", self.OnCustomEvent)          -- 监听自定义广播
self:PushEvent("id", 1, 2, 3)                             -- 实例内部事件（仅本实例）
self:PushCustomEvent("广播ID", 1, 2, 3)                    -- 自定义广播（异步，跨实例）
self:PushCloudServerMsg("类型", 内容...)                    -- 云服广播（异步）
```

### 官方签名

| 函数 | 参数 | 返回 | 作用 |
|---|---|---|---|
| `AddTriggerEvent` | string 事件类型, function 回调, [过滤参1], [过滤参2] | 无 | 添加触发事件（**仅 UI/世界组件有效**） |
| `AddCustomEvent` | string 消息id, function 回调 | 无 | 监听自定义消息(广播) |
| `PushCustomEvent` | string 消息id, 多个基本数据类型 消息内容 | 无 | 发送自定义消息(**异步**) |
| `PushCloudServerMsg` | string 自定义事件类型, 多个基本数据类型 事件内容 | 无 | 发送云服广播消息(**异步**) |

### 广播回调签名

```lua
function Script:OnCustomEvent(event, arg1, arg2)
    print(event.eventType, arg1, arg2)
end
```

⚠️ **匿名回调的实际签名是 `(cmp, eventId, param1...)`——载荷在第 3 个参数。**
写成 `function(_, msg)` 拿到的是 eventId（每帧恒等），**不报错但逻辑全废**。

## 6.2 定时器（引擎自带，**优先于自造广播泵**）

```lua
self:DoTaskInTime(function() print("延时执行") end, 5)      -- N 秒后执行 1 次
self.task = self:DoPeriodicTask(self.OnPeriodicTask, 3)     -- 每 3 秒
local t = self:DoPeriodicTask(fn, 3, 5, 10)                 -- 5秒后开始，每3秒，共10次
self.task:Pause()   self.task:Resume()   self.task:Cancel()
```

> 历史：TTS v3.3 / 真随机数 v2 用「广播自驱动泵」是因为当时没确认到这套 API。
> **现已确认存在，新脚本一律优先用 `DoPeriodicTask`。**

## 6.3 协程（引擎注入 + 原生）

```lua
self:ThreadWork(function() print("线程启动") end)   -- 启动新协程
self:ThreadWait(1)                                  -- 等待 1 秒（默认一帧）
threadpool:wait(1)                                  -- 官方 FAQ 的标准答案
```

⚠️ `ThreadWait` 官方描述为"启动新协程"，需在协程上下文内调用。
**协程是可用的**——长任务分片多了这条路，不必全靠广播泵。

## 6.4 组件/对象操作

```lua
self:GetComponent("HP")     -- 取本对象其他组件，返回组件实例
self:GetGameObjectId()      -- 世界组件/实体组件用
self:GetId()                -- 对象 id
self.varNum                 -- 属性直接读写
```

## 6.5 官方模板片段

```lua
-- 方块被破坏 → 生成掉落物
function Script:OnBlockRemove(event)
    GameObject:CreatePrefab(ObjType.DropItem, self.dropItem,
        event.x, event.y, event.z, self.dropItemNum)
end

-- 点方块 → 创建嘟嘟鸟并设血量
local objs = GameObject:CreatePrefab(ObjType.Mob, 3400, event.x, event.y+1, event.z)
if objs and objs[1] then
    local hpCmp = objs[1]:GetComponent("HP")
    if hpCmp then hpCmp.hp = 120 end
    Actor:SetAttr(objs[1]:GetId(), RoleAttr.CurHp, 120)
end
```

---

# 七、广播通信体系

## 7.1 三套机制，别混用

| 机制 | 发送 | 监听 | 可达范围 |
|---|---|---|---|
| **对象内事件** | `self:PushEvent(id, ...)` | `self:AddEvent(id, fn)` | **只有同一对象上**的组件 |
| **房间广播** | `self:PushCustomEvent(id, ...)` | `self:AddCustomEvent(id, fn)` | 同房间**所有**组件 + 触发器 |
| **云服广播** | `self:PushCloudServerMsg(id, ...)` | `self:AddCloudSeverEvent(id, fn)` | 该地图**所有云服房间** |

⚠️ 用错了表现为"发出去没任何反应"。

## 7.2 消息 ID 必须是预设 ID

**广播消息 ID 必须是在触发器里新建的那条广播消息的 ID**（形如 `m177358728257565`）。
自己编字符串发出去没人收。

好处：用触发器的广播 ID，**触发器那边也能收到**——一条广播同时打通
「组件 ↔ 组件」和「组件 ↔ 触发器」。

## 7.3 参数：数量不限、能传 table

官方写"多个基本数据类型"，用户实测补充：**数量不限、可以直接传 table**（引擎传值副本）。
⚠️ **不能广播 `_G`**（发送权限不足），这与"能不能传 table"是两回事。

## 7.4 云服广播第三参 = 定向房间

```lua
self:PushCloudServerMsg(id, p1)              -- 发给所有云服房间
self:PushCloudServerMsg(id, p1, "room_888")  -- 只发给 room_888
```

## 7.5 一个广播当无数个用（官方先例）

广播 ID 要预设、数量有限。解法：**只建一条广播，用「路由字符串」区分用途**。

```lua
self:PushCustomEvent(broadcastId, identify, funcName, ...)
```

官方 KV 表组件就是这么干的。

---

# 八、数据存储：Data 三子表 + 二维表铁律

转储：`Data` 含 `Array` / `Map` / `Table` 三个子表 + 4 个函数。
**云服旧模块 `CloudSever`（注意是 Sever 不是 Server）已作废，走 `Data.Map`。**

## 8.1 ⛔⛔ 二维表限制（用户强调无数次）

| 方向 | 限制 |
|---|---|
| **导入** | **500KB 内存 + 2000 行** |
| **导出** | **只有 2000 行，没有内存限制** |

**结论：导出一律只用 1 张表 —— 一行里放多条就行，绝不是分多张表。**

- 做法：N 条记录用 `;` 拼进一行，`pack = ceil(总条数 / 1999)`
- 3840 条时 `pack=2` → 1920 行，**1 张表装完**
- 头部记 `PK:n`（合并数），读回时按它拆开逐条比对
- 一行能放很长（真机 `mmlm_1.csv` 是 945 行 × 500 字符，且那是导入侧）
- **只有当用户手动设 pack=1 且条数 >1999 时才需要多表**

> **历史错误**：探针 v1/v2 按行数分片成 3~4 张表，还报"表不够还差几张"——用户明明说过导出没内存限制。

## 8.2 ⛔ Data.Table 实机签名（以 建筑文件生成器3.1 为准，**禁止照转储猜**）

```lua
Data.Table:Clear(tableId, nil)
Data.Table:InsertValue(tableId, nil, 一个字符串)   -- 每行只传【一个】字符串
local all = Data.Table:GetAllValue(tableId, nil)   -- all[i][1] 才是值，第 1 行是头部
```

- 传了第 4、5 个参数（行号、空串）→ **行号变成第 1 列的值，真正数据跑到第 2 列**，
  导出 CSV 第一列全是 1,2,3...，**静默错位不报错**
- 第 1 行放头部（如 `BLD3|V1|DR:n|...`），读时 `for i=2,#all` 跳过
- 每张表硬上限 **2000 行**（含头部 → 数据最多 1999）

其余成员：GetValue / SetValue / GetCols / GetRowIndex / InsertValueByRow /
UpdateAllValue / UpdateLineValues / RemoveRow / GetTableColKeys。

## 8.3 二维表 CSV 格式（真机验证过的那种）

```
字段备注,权重数据,
字段名,权重数据,
字段类型,string,
1,"MMLM|",
2,"9he;U0`V7T!!iQ)!!3-#!'gMa!...",
```

- **3 列**：行号 / 引号包裹的值 / 空
- **前 3 行**元数据
- 首列必须是行号（数字），**不能是逻辑名**

### ⚠️ 逗号陷阱（最容易静默毁数据）

`ord(',') = 44` 落在 base85 字符集（33 + 35~117 + 126）内，
真实数据里就有 `),IkSQ` 这种含逗号的值。

**绝不能用 `split(',')` 解析**，必须靠引号定位：

```lua
local a = string.find(line, '"')
local b = string.find(line, '"', a + 1)
local val = string.sub(line, a + 1, b - 1)
```

`[^,]+` 还有第二个问题：**空字段会被跳过**（`"a,,b"` 得 2 个而非 3 个）。

## 8.4 Data.Map（KV 表 + 排行榜统一接口，13 个函数）

**开启**：开发者工具 → 触发器 → 变量库 → 全局变量 → 选「排行榜」或「表」

```
SetValueAndCallBack / SetValueAndBlock
RemoveValueAndCallBack / RemoveValueAndBlock
UpdateValueAndCallback
GetValueAndCallBack / GetValueAndBlock
GetIndexValueAndCallback / GetIndexValueAndBlock     排行榜专用
GetNumValuesAndCallback / GetRangeValuesAndCallback  排行榜专用
SetRankValueAndBlock / ClearData
```

**入参**：`varId`(string) `playerId`(number|nil 全局传 nil) `key`(string) `value`(string|number|boolean) `callback`(function)
**返回**：`code`(ErrorCode) `key` `value` [排行榜额外：`index` `ascending` `extendinfo`]

### ⛔ 三个硬限制

1. **不支持自定义 table** —— 必须自己序列化（`json.encode`）
2. **请求频率限流**（按在线人数动态分配）

| 类型 | 每分钟上限 |
|---|---|
| 设置 / 获取 | `30 + numPlayers × 10` |
| **排行榜** | **`5 + numPlayers × 2`（最严格，约 KV 的 1/5）** |

3. 数据长度限制（每条有大小上限）

### 示例

```lua
local v = json.encode({score = 200, name = Actor:GetNickName(uin)})
local code, key, val = Data.Map:SetValueAndBlock(GlobalKV, nil, "Key2", v)
if code == ErrorCode.OK then print("写入成功") end

local c2, k2, v2 = Data.Map:GetValueAndBlock(GlobalRank, nil, "Key2")
if c2 == ErrorCode.OK then v2 = json.decode(v2) or v2
elseif c2 == ErrorCode.KV_OP_NO_VAL then print("数据不存在") end
```

⚠️ `Data.Map:GetMapValue` **真机不存在**（沙盒早期脚本用过，已证伪）。

---

# 九、全局函数（官方全局函数页）

```
json.decode(string) -> table     json.encode(table) -> string
GetWorld()                       获取当前世界对象
print(...) / printError(...)     打印信息 / 打印错误信息（黄色高亮）
Class(className, super, isSingle) / Instance(className) / GetInst(className)   类系统
```

隐藏全局函数（转储）：
```
GetModId() / Export(name, data) / Import(name, importModId)   ← 跨 MOD
GetS(id, ...) / getServerTime() / lerp() / copy_table()
SetDebugInfo() / Serialize() / UnSerialize()
```

---

# 十、性能：纯 Lua 引擎的优化判据

## ⛔ 通用公式

> **省「操作次数 / 解释开销」有效；省「搬运带宽 / 提高算术强度」无效。**

- ✅ 有效：批量取字节、把值缓存到 local、减少 table 访问
- ❌ 无效：推测解码、batch GEMM（实测只有 1.17~1.24x）、权重条带重排

原因：GPU 的瓶颈是搬权重（提高算术强度是白赚），
**纯 Lua 解释器的成本 ≈ 操作次数 × 解释开销**，批处理省不掉乘加。

## matvec 加速（MiniMind2 v24Acc1，实测 2.51x）

**结论：权重条带重排（repack）是负收益，永远别再做。**

- v24Acc 慢且卡：每处理一个 32 行条带都要把 32 个累加器重新清零（rows×cols/4）；
  启动 repack 全模型 0.4~2.5 秒，元凶是**逐字节 `string.char`（2580 万次调用）**——
  这是实机"卡顿/失败"的根因（超时中断 → 部分矩阵重排、部分没重排）

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

## int8 量化（仅 MB 级数据才值得）

```
[ f32 scale × rows ]  [ uint8 (w+128) × rows×cols ]
反量化：w = (byte - 128) × scale
```

直接 `string.byte` 取原始值相乘，**行末减一次 `128·sumX`**：

```
Σ w[j]·x[j] = Σ (b[j]-128)·x[j] = Σ b[j]·x[j] - 128·Σx[j]
```

| 对比项 | 结果 |
|---|---|
| Lua vs Python 偏差 | 1.045e-06 |
| 分类一致 | 60/60 |
| 体积 | 15496 B → 1466 B（9.5%） |

⚠️ **API 清单、配置表、日志这类小数据必须原文直出**，再压缩就是错的。

---

# 十一、⛔ 静默失效清单（最重要，全是不报错只给错结果）

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

## 调试期通用坑

- **循环变量赋值**：`for _, s in ipairs(l) do s = lower(s) end` — Lua 5.5 报
  `attempt to assign to const variable`。写成新变量。
- **定位串误删**：批量修改时普通注释里的相同文字会被误命中，定位标记要加特殊前缀。
- **开放函数返回值人类看不见**：返回值只能给别的脚本。要人看到必须
  `print` 到日志窗，或 `PushCustomEvent` 推广播。

---

# 十二、⛔ 已废除的错误知识（档案，勿再用）

| 废除项 | 真相 |
|---|---|
| ~~引擎是 LuaJIT，FFI 可见~~ | `jit=nil` `ffi=nil`，**标准 Lua 5.1**。据 `fill/copy/gc/load/string/arch/os` 七个字段推断是 LuaJIT，错了——那些与 LuaJIT 的 ffi 成员同名，但实机 ffi 是 nil |
| ~~`bit` 只有 `rol` 没有 `ror`~~ | **12 成员含 `ror`** |
| ~~`math.tanh` 不存在需自带~~ | **引擎 math 34 成员含 tanh/pow/clamp/lerp/mod/ldexp** |
| ~~`table.concat` 不是函数需自实现~~ | 那是 **lupa 5.5 沙盒**的问题，不是引擎。引擎 table 有 `concat` |
| ~~导出二维表要分片到多张表~~ | **只用 1 张表，一行放多条** |
| ~~`Data.Map:GetMapValue`~~ | **真机不存在** |
| ~~`CloudSever` 可用~~ | 官方标记废弃，走 `Data.Map` |
| ~~`io`/`package` 有内容~~ | 都是空表 |
| ~~`os.clock` 可用~~ | **不存在，用了必崩**，一律 `os.timeMs()` |

## ⚠️ 沙盒测试环境 ≠ 引擎（别把环境问题当成脚本 bug）

**lupa 是 Lua 5.5，不是 5.1**：

- `math.ceil(x)` 返回 nil
- `table.concat` 不是函数
- 整数是 64 位：用原生 `& | ~ << >>` 拼 bit mock 会导致 SHA 全错（不截断 32 位）
- 有 `os.clock`、`math.tanh`；引擎 5.1 没有

**造 mock 引擎时不要覆盖标准库名**（`pairs`/`print`/`type`），否则自检全误报。
必须跳过保留名：`_G _ENV string math table os io coroutine package type print
pairs ipairs select require tostring tonumber next error pcall unpack debug bit jit ffi arg`
（**`Data` 不能跳过**，它是引擎模块）

---

# 十三、待真机验证清单

- [ ] `loadstring` 到底能不能用（转储=function / 早期实测=nil / 10-18探针=function，三源冲突）
- [ ] `string` 的 `startswith` / `endswith` / `dump` / `IsBlank` / `Contains` 是否存在
- [ ] `table` 的 `merge` / `move` / `show` / `num_pairs` / `foreach` / `foreachi` / `maxn` / `tostring` / `getn`
- [ ] 属性字段 `tips` / `sort` 是否生效
- [ ] 1.53 七种"组"类型在脚本侧的确切写法
- [ ] `DoPeriodicTask` / `DoTaskInTime` 在 1.59.0 各组件类型上的可用性
- [ ] `AddTriggerEvent` "只在 UI/世界组件有效"的精确边界
- [ ] Studio 版 `CloudService`（`game:GetService`）能否用于组件脚本
- [ ] `ErrorCode` 完整枚举值
- [ ] `Data.Map` 数据长度上限的具体数值

---

# 十四、交付纪律（血泪）

1. **说"做好了/已生成"必须同轮带文件** —— 已违规 4 次（v3.3、反作弊 zip、RSA v2、真随机 v3）
2. **更严重**：反作弊 zip **文件根本不存在**却说"已打包"（属编造，非疏漏）
3. **对策：先交付再写说明；交付前核 md5**
4. **先交付、再写正文**——把交付当成独立动作，写完文字不等于收工
