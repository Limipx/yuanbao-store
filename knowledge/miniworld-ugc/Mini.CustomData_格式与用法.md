# Mini.CustomData 格式与用法

> 依据：**商店自定义2.lua（实机在用脚本）** + 本次 lupa 实跑验证（见文末实测输出）
> 定位：属性面板上的**结构体 / 记录类型**，用 `customDef` 描述字段，**可无限嵌套**
> 一句话：**运行时它就是普通 Lua table，键名就是 `customDef` 里写的键名**

---

## 一、它解决什么问题

`propertys` 顶层只能平铺 String / Number / Bool / Item / Picture……
要表达「分类 → 子分类 → 商品 → 价格 → 货币/数量」这种**树形配置**，就得用 CustomData。

好处：**一整个配置树只要一个属性**，策划在面板上逐层展开编辑，不用在触发器里拼一堆平行数组。

---

## 二、核心结论：两种出现位置（写法不同）

文档一同时用到了两种，这是最关键的一条：

| | **A · 作为数组元素** | **B · 作为普通字段** |
|---|---|---|
| `type` | `Mini.Array` | `Mini.CustomData` |
| `itemType` | `Mini.CustomData` | —（不写） |
| `customDef` | ✅ 必须有 | ✅ 必须有 |
| 显示名 | `customDisplayName`（单个元素在面板上的名字）<br>+ `displayName`（整个数组的名字） | `displayName` |
| 运行时 | `self.xxx[i]` 是 table | `self.xxx` 是 table |

### A · 数组元素（文档一的大类 / 小类 / 商品）

```lua
categories = {
    type = Mini.Array,
    displayName = "商品分类",
    itemType = Mini.CustomData,        -- ← 元素是自定义结构
    customDisplayName = "大类",         -- ← 面板上"添加大类"
    customDef = {
        name = { type = Mini.String, displayName = "分类名称", maxLength = 20 },
        subcategories = {
            type = Mini.Array, displayName = "子分类",
            itemType = Mini.CustomData, customDisplayName = "小类",
            customDef = { ... }
        }
    }
}
```

### B · 普通字段（文档一的 `price`，⚠️ **这是文档一独有的新证据**）

```lua
price = {
    type = Mini.CustomData,            -- ← 直接作为字段类型，不经过 Array
    displayName = "价格",
    customDef = {                       -- ← 没有 customDisplayName
        currency = { type = Mini.String, displayName = "货币类型", default = "gold" },
        amount   = { type = Mini.Number, displayName = "数量", minValue = 0 }
    }
}
```

> 之前技能库里只有「Array 里嵌 CustomData」的例子，**没有**「字段直接是 CustomData」的实证。
> 文档一补上了这条：**CustomData 里可以套 CustomData**，不必借助 Array。

---

## 三、`customDef` 内部字段的写法

**与 `propertys` 顶层字段完全同构**，支持同样的配置项：

```
type          字段类型（Mini.Xxx / Mini.Array / Mini.CustomData）
displayName   面板显示名
default       默认值
minValue / maxValue   数值范围（是 minValue，不是 min）
maxLength     字符串最大长度
```

### ⛔ 红线：键名不能改

```lua
customDef = { name = ..., subcategories = ..., price = ... }
```

这三个键名 **就是运行时的 Lua table 键名**，脚本里写 `category.name`、`product.price.amount`。

- **混淆器 / 重命名工具不能改 `customDef` 的键名**（同理 `propertys` 的键名、`openFnArgs` 的键名）
- 键名必须是合法 Lua 标识符，别用中文、别用数字开头
- 改了 → 运行时取到 nil，**不报错，静默失效**

---

## 四、嵌套：三种形态，任意深度

| 形态 | 写法 | 文档一实例 |
|---|---|---|
| ① CustomData → 字段是 `Array<CustomData>` | `type=Array` + `itemType=CustomData` | `categories` → `subcategories` → `products` |
| ② CustomData → 字段是 `CustomData` | `type=CustomData` | `products[].price` |
| ③ 混合 | 交替递归 | 见下 |

**文档一实测的嵌套链（5 层，全部取值成功）：**

```
categories (Array<CD>)
  └─ [i].name                                  String
  └─ [i].subcategories (Array<CD>)
       └─ [j].name                             String
       └─ [j].products (Array<CD>)
            └─ [k].item                        Mini.Item
            └─ [k].price (CustomData)          ← 非数组的 CustomData
                 └─ .currency                  String
                 └─ .amount                    Number
            └─ [k].icon                        Mini.Picture
```

---

## 五、运行时形态：就是纯 Lua table（实测）

```lua
function Script:OnStart()
    local c = self.categories[1]
    print(c.name)                                  -- 武器
    print(c.subcategories[1].name)                 -- 剑
    print(c.subcategories[1].products[1].price.currency)  -- gold
    print(c.subcategories[1].products[1].price.amount)    -- 100
    print(c.subcategories[1].products[1].icon)     -- 0_10001
end
```

实测输出（lupa 加载文档一原脚本）：

```
categories[1].name = 武器
[1].subcategories[1].name = 剑
[1].sub[1].products[1].price.currency = gold
[1].sub[1].products[1].price.amount = 100
[1].sub[1].products[1].icon = 0_10001
```

可用操作：`#arr`、`arr[i]`、`ipairs` / `pairs`、`table.insert` / `table.remove`、直接赋值——**全是普通 table 操作**。

### ⚠️ 但它只是内存副本

```
[4] SetPathValue '[1].name' = 防具  => 设置成功
[5] 改后读回   '[1].name'           => 防具
[6] 属性原表   self.categories[1].name = 武器   ← 没跟着变
```

文档一 `OnStart` 里 `shopData = self:_convertCategoriesToJSON(self.categories)` 是**拷了一份**，
之后所有增删改都作用在 `shopData` 上，**不会回写属性面板**。

要持久化得自己存：`Data.Map` / `Data.Array` / `Data.Table`（见手册 §8）。

---

## 六、customDef 里可用的字段类型

| 类型 | 文档一实证 | 备注 |
|---|---|---|
| `Mini.String` | ✅ `name` / `currency` | `maxLength` 写法见过，**是否生效未验证** |
| `Mini.Number` | ✅ `amount` | `minValue` 写法见过 |
| `Mini.Item` | ✅ `item` | 资源选择器 |
| `Mini.Picture` | ✅ `icon` | `default = "0_10001"` |
| `Mini.Array` | ✅ `subcategories` / `products` | 递归入口 |
| `Mini.CustomData` | ✅ `price` | 递归入口（非数组） |
| `Mini.Bool` / `Mini.Vec3` / `Mini.Enum` | 【未验证】 | 按同构推断可用 |

---

## 七、`default` 的两种写法（⚠️ 现存冲突）

```lua
-- 文档一：字面量表
currencies = { type = Mini.Array, itemType = Mini.String,
               default = { "gold", "diamond", "honor" } }

-- 技能库 13 章（道具搜索3.lua 等）：构造器
searchRangeGroup = { type = Mini.Array, itemType = Mini.String,
                     default = Mini.Array(Mini.String, "0-2000", "9995-17019") }
```

**两种都见过，元素为基础类型时都可用**。
⚠️ **`itemType = Mini.CustomData` 时 `default` 怎么写，未验证**——文档一的 `categories` 就没写 default。
建议：自定义结构**先不写 default**，需要初始值时在 `OnStart` 里补。

---

## 八、配套：`Data.Array` 实机签名（文档一实证，新证据）

文档一里实际在用的调用：

```lua
Data.Array:GetSize(self.currencies)                        -- 2 参
Data.Array:GetValue(self.currencies, nil, i)               -- 3 参
Data.Array:InsertValue(self.currencies, nil, value, size+1) -- 4 参（可指定位置）
Data.Array:Remove(self.currencies, nil, i)                 -- 3 参
```

⚠️ **和 `Data.Table:InsertValue(tableId, nil, "一个字符串")`（3 参）参数个数不一样**，
不要互相套用——之前就因为拿转储的变参签名瞎猜而错位（第 1 列变成行号）。
**API 参数以实机跑通的脚本为准，转储只用来查"有没有这个成员"。**

---

## 九、`openFnArgs` 格式再确认（文档一实证）

```lua
SetPathValue = {
    returnType = Mini.String,
    displayName = "设置路径值",
    params = { "路径", Mini.String, "值", Mini.String,
               "值类型", Mini.String, "分隔符", Mini.String,
               "返回操作结果" }        -- ← 最后一项是返回名，无类型
}
```

实测 7 个声明的 `params` 项数：**1 / 5 / 5 / 5 / 7 / 9 / 9，全是奇数**——
「**名、类型交替 + 末项是返回名**」这条格式再次被证实。

### ⛔ 实现了但没声明 = 触发器调不到

```
已实现但未在 openFnArgs 声明: AddCurrency, RemoveCurrency, _convertCategoriesToJSON, _createContainer
```

文档一的 `AddCurrency` / `RemoveCurrency` 写了实现，但 `openFnArgs` 里没有 → **面板上看不见、调用不了**。
（下划线开头的是内部函数，不声明是对的。）

---

## 十、文档一自身的坑（实测，改脚本前先看）

| # | 问题 | 实测证据 |
|---|---|---|
| ① | **`shopData` 顶层是数组，但插入/移除用 `shopData.categories`** → 恒 nil | `ArrayInsertProduct` 调用即崩：<br>`attempt to get length of a nil value (field 'categories')` |
| ② | 数组索引必须用**中括号** | `'1.subcategories.1.name'` → **null**<br>`'[1].subcategories[1].name'` → **剑** |
| ③ | `shopData` 是内存副本，不回写属性 | 改了 `[1].name` 后 `self.categories[1].name` 仍是原值 |
| ④ | 分隔符不一致：默认 `"."`，但插入/移除传 `"/"` | `parsePath(catPath, "/")` 与 `GetPathValue(p, ".")` 口径不同 |
| ⑤ | `AddCurrency` / `RemoveCurrency` 未声明 | 触发器调不到 |
| ⑥ | `ArrayRemoveProduct` 走不到真正逻辑 | 恒返回「错误: 分类不存在」 |

**① 的修法**（二选一）：
- 让 `_convertCategoriesToJSON` 返回 `{ categories = jsonData }`，保持"有 categories 键"；
- 或把插入/移除改成直接操作数组：`shopData[catIndex].subcategories[subIndex].products`。

---

## 十一、待验证清单

- [ ] `itemType = Mini.CustomData` 时 `default` 的写法
- [ ] `maxLength` 是否真的限制字符串长度（`tips` / `sort` 已确认生效，`maxLength` 未确认）
- [ ] `customDef` 里用 `Mini.Enum` / `Mini.Vec3` / `Mini.Bool` + `children`
- [ ] 嵌套深度上限（已实证 ≥5 层，理论上不限）
- [ ] 自定义结构能否经 `Data.Table` / `Data.Map` 持久化往返（JSON ↔ 二维表）

---

## 附：本次实测原始输出

```
===== ①OnStart =====
初始商店数据: [{"name":"武器","subcategories":[{"name":"剑","products":[{"price":{"currency":"gold","amount":100},"item":"sword1","icon":"0_10001"}]}]}]
OnStart ok=true
===== ②运行时取值 =====
categories[1].name = 武器 / [1].subcategories[1].name = 剑 / ...price.currency = gold / ...price.amount = 100 / ...icon = 0_10001
===== ③路径口径 =====
'1.subcategories.1.name' => null        '[1].subcategories[1].name' => 剑
'[1].subcategories[1].products[1].price.amount' => 100
===== ④顶层形态 =====
GetShopData 首字符 = [   （数组，无 categories 键）
===== ⑤ArrayInsertProduct =====
ok=false  错误=[string "..."]:469: attempt to get length of a nil value (field 'categories')
===== ⑥ArrayRemoveProduct =====
ok=true   返回=错误: 分类不存在
===== ⑦未声明函数 =====
AddCurrency, RemoveCurrency（触发器调不到）
===== ⑧params =====
1 / 5 / 5 / 5 / 7 / 9 / 9 项，末项均为返回名
```
