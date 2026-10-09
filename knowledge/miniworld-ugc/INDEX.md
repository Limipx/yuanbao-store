# 迷你世界 UGC3.0 知识库

> 更新：2026-10-09（第二轮：云服体系重写 + Lua 环境差异 + 1.59.0 调研）
> 状态标注：【已测】= 实测确认　【未测】= 待验证
> **目标版本 1.59.0（筑梦华章，2026-09-22）｜API 转储数据仍为 1.54.0**

## 文件清单

| 文件 | 内容 | 状态 |
|---|---|---|
| **两套脚本上下文.md** | ★ 触发器脚本 vs 组件脚本，两套写法与桥梁 | 【已测】 |
| **环境全景_1.54.0.md** | ★ 355 顶层符号、*Edit 族、隐藏接口、原生库扩展 | 【已测】 |
| 引擎元数据铁律.md | ◀ 混淆必读，违反=返回 nil | 【已测】 |
| arrayWrapper.md | 数组返回值机理，getcount==3 | 【已测】 |
| **MiniBus组件.lua** | 通用广播总线组件，可直接导入 | 【已测】9/9 沙盒 |
| 环境能力.md | loadstring 不可用等 | 【已测】 |
| **广播通信体系.md** | ★ 三套广播机制、预设ID、MiniBus 一个ID当无数个用 | 【已测】9/9 框架，真机未测 |
| **组件属性补全.md** | isSave/permission、1.53 组类型、CustomData、官网 vs 手册差异 | 部分【未测】 |
| **探针_隐藏接口.lua** | 可导入的隐藏接口探针，10 组 | 【未测】真机 |
| **云服与数据存储.md** | ★ CloudSever 已作废 → Map 13 函数 / CloudService 体系 / 限流表 | 【已测】文档 |
| **Lua环境差异.md** | ★ `_G` 是空表走元表、`error` 不抛异常、io/package 删除 | 【已测】文档 |
| **1.59.0版本与转储调研.md** | 版本事实、转储全网调研（无 1.59 转储）、获取路径 | 【已测】调研 |

## 第二轮更新要点（2026-10-09 晚）

### 1. CloudSever 已作废（★ 重大）

官方 `cloudsever.html` 顶部原文：**「（此处已废弃）」**，14 个函数全废。  
现行方案：**云服 KV 表 + 云服排行榜**。

- 组件脚本走 `Data.Map:*` 共 **13 个函数**（KV 与排行榜统一接口）
- Studio 节点式走 `game:GetService("CloudService")` + `CloudKVStore`
- **必须云服环境**，单机/联机关房间即丢

### 2. 云服限流（务必记住）

| 类型 | 每分钟上限 |
|---|---|
| 设置类 | `30 + numPlayers × 10` |
| 获取类 | `30 + numPlayers × 10` |
| **排行榜** | **`5 + numPlayers × 2`（最严格）** |

排行榜配额约为 KV 的 **1/5**，绝不能进高频逻辑。

### 3. Lua 环境是被改过的（★ 根因级）

```
_G        实际是空表，读写全走元表  → pairs(_G) 拿不到东西
io/package 全部删除
os         仅剩 os.date / os.time
debug      1.23.0 起只剩 traceback
dofile/loadfile  空函数，什么都不做
loadstring 不执行，弹提示让用 LoadLuaScript
error      不抛异常！只记日志，代码继续往下跑  ★★
print      输出到日志文件，格式与标准不同
```

**`error` 不抛异常**这条影响很大：混淆脚本的防篡改校验若靠 `error` 中断，**实际不会中断**。

### 4. 转储存在 ≠ 可用（已确立为原则）

`loadstring` 三方印证：转储里**存在** / 真机返回 **nil** / 文档说被 stub。  
→ 判断能力必须**实测**，不能只看清单。

### 5. 全网无 1.59.0 环境转储

三个开源项目全部停更，**根因是 1.23.0 起 debug 被阉割**，正规脚本手段拿不到 genv：

| 项目 | 状态 |
|---|---|
| MiniWorldGenv | 最后提交 2023-01-02 |
| MiniExtend | EOL 2023-01-27 |
| MiniExtend 文档站 | 内容基于旧版 |

**获取路径：自己在 1.59.0 真机跑 API反射导出器.lua。**

## 本次更新要点（2026-10-09）

### 1. 两套脚本上下文（★ 最重要）

官方**有两套并行写法**，此前只知道旧的那套：

```
触发器脚本（旧）  ScriptSupportEvent:registerEvent([=[Player.ClickBlock]=], fn)
组件脚本（新）    self:AddTriggerEvent(TriggerEvent.PlayerClickBlock, self.fn)
```

**桥梁**：`TriggerEvent.Xxx` 的值就是字符串事件名
（`ActorCreate="Actor.Create"`，252/252 全部有值）。两套等价。

**新项目一律用组件脚本。**

### 2. 环境转储大幅扩容

```
旧认知：2122 函数
新认知：7267 条目 / 2122 函数 / 355 顶层符号
        其中 *Edit 族 15 个、Trigger 子模块 20 个 —— 官方全部未文档化
```

### 3. 隐藏接口（官方未提）

```
threadpool (Work/work/wait/Wait)   ★ 真多线程
json.encode / json.decode          ★ JSON
Class / Instance / GetInst         ★ 类系统
Export / Import / GetModId         ★ 跨 MOD 数据交换
Trigger.Component.*  17 个         ★ 组件属性读写/函数调用
os.timeMs                          毫秒时间戳
string.split / table.clone / math.clamp ... 非标准扩展
```

### 4. Mini 模块认知修正

转储里 `Mini` **只有 Array 一个显式字段**，没有 String/Number/Item。
但用户实测 `Mini.String.__className_=="String"`（50 种）。
→ **Mini 走元表 `__index` 动态解析，转储抓不到。转储 ≠ 完整环境。**

### 5. 1.53.0 官方新增（转储确认）

```
Actor/Player/Monster: HasTags GetTags AddTags RemoveTags ClearTags
新组件：标签组件、手持特效组件
新属性类型（7 种"组"）：数值组/字符串组/生物类型组/道具类型组/
                      音效组/方块类型组/布尔值组
```

### 6. 运行时模型（官网）

脚本在**主机端**运行，游戏状态每 **50ms** 更新一次 = 1 tick。
→ 热路径代码性能敏感。

## 待验证（优先级）

1. **在 1.59.0 真机跑 API反射导出器** — 产出新转储（最高优先，卡住一切）
2. **`Data.Map` 13 函数**在组件脚本中的确切调用形式
3. **`LoadLuaScript`** 是否可用（loadstring 的官方替代）
4. **Studio 版 CloudService** 是否可用于 1.59.0 组件脚本
5. **`error` 不抛异常**对既有混淆防篡改方案的实际影响
6. **\*Edit 族** — 能否脚本化配置 MOD 内容（潜力最大）
7. **threadpool** — 真多线程与性能收益
8. **Class / Instance / GetInst** — 类系统语义
9. **Export / Import** — 跨 MOD 数据交换
10. **json** — 与 table 互转
11. 新增 7 种"组"属性类型的 `Mini.X` 名
12. os.timeMs 精度
13. Trigger.Component 实操

→ 6–13 可用 `探针_隐藏接口.lua` 一次性测完。

## 与混淆相关（务必先读）

做混淆前必读 `引擎元数据铁律.md` 五条。
违反表现：「导入成功、看得到函数名、调用返回 nil」，极难排查。
