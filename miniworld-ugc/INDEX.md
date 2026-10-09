# 迷你世界 UGC3.0 知识库

> 更新：2026-10-09（官方 Wiki + 8个组件模板 + 1.54.0 转储全面刷新）
> 状态标注：【已测】= 实测确认　【未测】= 待验证

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

1. **\*Edit 族** — 能否脚本化配置 MOD 内容（潜力最大）
2. **threadpool** — 真多线程与性能收益
3. **Class / Instance / GetInst** — 类系统语义
4. **Export / Import** — 跨 MOD 数据交换
5. **json** — 与 table 互转
6. 新增 7 种"组"属性类型的 `Mini.X` 名
7. os.timeMs 精度
8. Trigger.Component 实操

→ 全部可用 `探针_隐藏接口.lua` 一次性测完。

## 与混淆相关（务必先读）

做混淆前必读 `引擎元数据铁律.md` 五条。
违反表现：「导入成功、看得到函数名、调用返回 nil」，极难排查。
