# arrayWrapper 机理

## 为什么需要

`Mini.Array(itemType)` 返回引擎原生 userdata，它的 `__className_`
**恒为 "Array"**，无法表达元素类型。而引擎解析返回值**只认 __className_**。
所以必须造假 table 拦截查询。

## 真机实测查询序列

```
String : Array → Array → String → Array → Array
                          ↑ 第3次给元素类型
```

## getcount == 3 是硬编码

引擎侧硬编码的查询次序，Lua 只能迎合。改动即错位：

```
第1次给 → String > Array > Array > Array > Array
第2次给 → Array > String > Array > Array > Array
第3次给 → Array > Array > String > Array > Array  ← 唯一正确
第4次给 → Array > Array > Array > String > Array
```
（真机 2026-10-08 实测，用户日志确认）

## 九项耦合细节（都不能动）

新建空 table / `__index` / 计数到 3 / 前两次返 "Array" /
其余转发 userdata / setmetatable / 闭包捕获 propertytype …

## 唯一可安全改进处

原版第 3 次返回是硬编码 if-else，**只覆盖 String/Number/Bool/Item**，
其余 46 种全返回 "Unknown"。

转储证实：**每个 `Mini.X.__className_` 恒等于 "X"**，50 种无一例外。

```lua
return propertytype.__className_ or "Unknown"
```
实测：`Vec3` 从 Unknown → Vec3，`Color` 从 Unknown → Color ✅

## 位置要求

`arrayWrapper` 必须定义在 `openFnArgs` **之前**。
纯 Lua 语义：`returnType = arrayWrapper(...)` 在构造表时立即执行。
