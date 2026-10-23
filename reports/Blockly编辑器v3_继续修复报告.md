# Blockly 编辑器 v3 · 继续修复到无问题

产出：`迷你世界3.0脚本Blockly编辑器_v3.html` + `_v3.txt`
**md5 `7231fd61501f83e6037a47faf184fdb1`（两份同一内容）**

---

## 一、先纠正：上一轮"244 处不匹配"是我算错了

上一轮把 **事件积木的 params_desc 也算成"输入标签"**，实际它们走 `msg0/msg1` 自定义消息，`params_desc` 在那里是**事件传参文档**（如 `eventobjid`、`x`、`y`、`z`），根本不参与 UI 标签。

正确判据：排除 `is_event` / `mutator`，再排除 `body` / `condition`，剩下的才比数量。

| 口径 | 上一轮报 | 真实 |
|---|---|---|
| 不匹配 | 244 | **80**（且都是"完全没标签"） |
| 事件积木那 241 条 | 报错 | **不是问题** |

`while_block` / `repeat_block` 只有 condition+body，无需标签 → 实际需要处理的是 **80 个**。

---

## 二、本轮修的 5 个真 bug

### ★ 1. 同一占位符出现两次 → Blockly 生成两个同名输入（9 个积木）

`print_var` 模板是 `print("{{name}}=", {{name}})`，`phs` 不去重 → `args0` 生成两个 `field_input` 都叫 `name` → 字段名冲突。

受影响 9 个：`print_var`、`world_spawncreature`、`gameobject_createprefab`、`gameobject_createprefabinst`、`block_destroyblock`、`block_placeblock`、`block_replaceblock`、`backpack_getitemnum`、`actor_trymovetopos`。

修法：定义处与生成器处各加一句去重。
`{{x}} == nil and true or {{x}}` 这类"默认 true"惯用法去重后语义不变（split/join 本来就替全部）。

### ★ 2. 体检把已登记函数全误报成"未登记"

正则写死 `^\s{4}` 匹配顶层键，但生成器输出的是 **2 空格**，于是 `keys` 恒为空 → 每个函数都报"已定义但未登记"。**干净代码也必然报警**。

改为收集 (缩进, 键)，取最小缩进作为顶层。

### ★ 3. 体检多行规则逐行匹配，永远命中不了

`Script.propertys = {` 和下一行的 `{ name = ...` 跨行，逐行正则匹配不到。新增 `LINT_BLOCK_RULES` 走整段匹配。

### ★ 4. 体检 `math.log10` 是误报（我上一轮加错的）

引擎 math 有 **34 成员，含 log10**（你真机探针实证）。已删除该规则。

### ★ 5. 80 个基础积木无 params_desc → UI 输入框没标签

Lua原生（return/赋值/变量/取字段）、print输出、其他操作、流程控制、数值操作、数学库、字符串库、表操作库。已全部补齐中文标签。
注：B 常量是无引号键 `{type:"x",...}`，补丁分两种格式处理。

---

## 三、新增 3 条体检规则

| 规则 | 说明 |
|---|---|
| propertys 数组形式 | `self.xxx` 取 nil、所有 default 失效 |
| openFnArgs params 只有类型没名字 | 实机要名/类型交替扁平数组 |
| 属性区 `min/max` | 应为 `minValue/maxValue`，限定在 propertys 块内判定以免误报普通变量 |

---

## 四、验证

```
积木总数        1133 · 重复 type 0
标签不匹配      【去重建模后】非事件积木 0（while/repeat 无普通参数，无需标签）
占位符合法性    非法占位符(含非\w) 0
Lua 模板        743 个参与编译，失败 1 —— break_stmt（裸 break 只能在循环内，编译单句必然报，非缺陷）
JS 语法         9/9 script 块通过
HTML 结构       </html> 闭合
体检·干净代码   null（零误报）
体检·脏代码     报出 os.clock / // / bit32 / table.unpack / CloudSever / Studio
                / require / io / unpack遇nil / 属性数组形式 / min= / params无名
                / 未登记函数
```

⚠️ 一处环境说明：沙盒 lupa 只提供 **Lua 5.4**，没有 5.1。故编译验证跑在 5.4，另外单独做 5.1 不兼容语法扫描（`//`、`goto`、`bit32`、`table.unpack` 等 0 命中）。

---

## 五、结论

结构性缺陷清零。上一轮剩的"244 处"经重新判定，241 处本就不是问题、80 处已补齐、9 处去重修复、体检 3 处逻辑错误已修。
