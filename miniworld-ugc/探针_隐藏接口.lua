--[[
隐藏接口探针 · 迷你世界组件（可直接导入）
主管签发 2026-10-09

目的：实测环境转储里发现但官方未文档化的接口是否可用
导入后 OnStart 自动跑完并 print，也可触发器逐个调用

重点验证（按价值排序）：
  ① *Edit 族（脚本配置 MOD 内容）
  ② threadpool（真多线程）
  ③ Class/Instance/GetInst（类系统）
  ④ Export/Import（跨 MOD）
  ⑤ json.encode/decode
  ⑥ os.timeMs
  ⑦ Trigger.Component.CallComponentFunction
  ⑧ 新增 7 种"组"属性类型的 Mini 名
  ⑨ loadstring 等 stub 复核
  ⑩ 非标准原生库扩展
]]

local Script = {}

Script.propertys = {}

Script.openFnArgs = {
    ProbeEdit    = { returnType = Mini.String, displayName = "①*Edit族探测" },
    ProbeThread  = { returnType = Mini.String, displayName = "②threadpool" },
    ProbeClass   = { returnType = Mini.String, displayName = "③类系统" },
    ProbeModIO   = { returnType = Mini.String, displayName = "④跨MOD" },
    ProbeJson    = { returnType = Mini.String, displayName = "⑤json" },
    ProbeOs      = { returnType = Mini.String, displayName = "⑥os.timeMs" },
    ProbeCmpFn   = { returnType = Mini.String, displayName = "⑦组件调用" },
    ProbeGroup   = { returnType = Mini.String, displayName = "⑧组类型" },
    ProbeStub    = { returnType = Mini.String, displayName = "⑨stub复核" },
    ProbeNative  = { returnType = Mini.String, displayName = "⑩原生扩展" },
    ProbeAll     = { returnType = Mini.String, displayName = "全部跑一遍" },
}

local LOG = {}
local function P(tag, fmt, ...)
    local ok, msg = pcall(string.format, fmt, ...)
    local line = "[" .. tag .. "] " .. (ok and msg or tostring(fmt))
    print(line); LOG[#LOG + 1] = line
end

-- 安全调用：返回结果字符串，永不抛错
local function T(name, fn)
    local ok, res = pcall(fn)
    if not ok then return name .. "=ERR(" .. tostring(res):sub(1, 60) .. ")" end
    if res == nil then return name .. "=nil" end
    return name .. "=" .. tostring(res):sub(1, 80)
end

-- 探测一个模块：类型 + 成员数 + 前几个成员名
local function probeModule(m)
    local t = _G[m]
    if t == nil then return "不存在" end
    if type(t) ~= "table" then return type(t) .. ":" .. tostring(t):sub(1, 30) end
    local n, names = 0, {}
    for k, v in pairs(t) do
        n = n + 1
        if #names < 4 then names[#names + 1] = tostring(k) end
    end
    return "table[" .. n .. "]{" .. table.concat(names, ",") .. "}"
end

-- ① *Edit 编辑期模块族
function Script:ProbeEdit()
    local mods = {
        "CraftingEdit", "BlockEdit", "GunEdit", "ProjectileEdit", "ItemEdit",
        "EquipEdit", "UseEdit", "OldGunEdit", "FoodEdit", "StatusEdit",
        "BlockStateEdit", "ToolEdit", "MonsterEdit", "FurnaceEdit", "PackEdit",
    }
    P("①Edit", "=== *Edit 编辑期模块族 ===")
    for _, m in ipairs(mods) do P("①Edit", "  %-16s %s", m, probeModule(m)) end
    return "见日志"
end

-- ② threadpool 多线程
function Script:ProbeThread()
    P("②Thread", "threadpool = %s", probeModule("threadpool"))
    local tp = rawget(_G, "threadpool")
    if type(tp) ~= "table" then return "threadpool 不可用" end
    P("②Thread", T("Work", function() return type(tp.Work) end))
    P("②Thread", T("work", function() return type(tp.work) end))
    P("②Thread", T("wait", function() return type(tp.wait) end))
    P("②Thread", T("Wait", function() return type(tp.Wait) end))
    -- 谨慎试跑一个空任务，超时/崩溃都能被 pcall 兜住
    P("②Thread", T("Work(empty)", function()
        if type(tp.Work) == "function" then tp.Work(function() end) end
        return "ok"
    end))
    return "见日志"
end

-- ③ 类系统
function Script:ProbeClass()
    P("③Class", T("Class", function() return type(Class) end))
    P("③Class", T("Instance", function() return type(Instance) end))
    P("③Class", T("GetInst", function() return type(GetInst) end))
    P("③Class", T("Class('ProbeCls')", function()
        if type(Class) ~= "function" then return "Class 不可用" end
        local c = Class("ProbeCls")
        return type(c) .. ":" .. tostring(c):sub(1, 40)
    end))
    P("③Class", T("GetWorld", function() return type(GetWorld) end))
    P("③Class", T("GetWorld()", function()
        if type(GetWorld) ~= "function" then return "不可用" end
        return type(GetWorld())
    end))
    return "见日志"
end

-- ④ 跨 MOD
function Script:ProbeModIO()
    P("④ModIO", T("GetModId", function() return type(GetModId) end))
    P("④ModIO", T("GetModId()", function()
        if type(GetModId) ~= "function" then return "不可用" end
        return GetModId()
    end))
    P("④ModIO", T("Export", function() return type(Export) end))
    P("④ModIO", T("Import", function() return type(Import) end))
    P("④ModIO", T("Export('probe',{1,2})", function()
        if type(Export) ~= "function" then return "不可用" end
        Export("__probe_key", { 1, 2, 3 })
        return "调用未抛错"
    end))
    P("④ModIO", T("Import('__probe_key')", function()
        if type(Import) ~= "function" then return "不可用" end
        return Import("__probe_key")
    end))
    return "见日志"
end

-- ⑤ json
function Script:ProbeJson()
    P("⑤Json", "json = %s", probeModule("json"))
    local js = rawget(_G, "json")
    if type(js) ~= "table" then return "json 不可用" end
    P("⑤Json", T("encode({a=1})", function() return js.encode({ a = 1, b = "x" }) end))
    P("⑤Json", T("decode('{\"a\":1}')", function()
        local r = js.decode('{"a":1}')
        return type(r) .. (type(r) == "table" and (" a=" .. tostring(r.a)) or "")
    end))
    return "见日志"
end

-- ⑥ os
function Script:ProbeOs()
    P("⑥Os", "os = %s", probeModule("os"))
    P("⑥Os", T("os.time", function() return os.time() end))
    P("⑥Os", T("os.timeMs", function() return os.timeMs and os.timeMs() or "nil" end))
    P("⑥Os", "timeMs 与 time*1000 差 = %s", T("diff", function()
        if not os.timeMs then return "无 timeMs" end
        return os.timeMs() - os.time() * 1000
    end))
    P("⑥Os", T("getServerTime", function()
        if type(getServerTime) ~= "function" then return "不可用" end
        return getServerTime()
    end))
    return "见日志"
end

-- ⑦ Trigger.Component
function Script:ProbeCmpFn()
    local C = rawget(_G, "Trigger") and Trigger.Component
    if type(C) ~= "table" then return "Trigger.Component 不可用" end
    local n = 0
    for k, v in pairs(C) do
        n = n + 1
        P("⑦Cmp", "  %-30s %s", tostring(k), type(v))
    end
    P("⑦Cmp", "共 %d 项", n)
    return "见日志"
end

-- ⑧ 新增"组"属性类型
function Script:ProbeGroup()
    -- 1.53 新增 7 种：数值组/字符串组/生物类型组/道具类型组
    --                音效组/方块类型组/布尔值组
    local names = {
        "Mini.NumberArray", "Mini.StringArray", "Mini.BoolArray",
        "Mini.NumberGroup", "Mini.StringGroup", "Mini.BoolGroup",
        "Mini.ActorArray", "Mini.ItemArray", "Mini.SoundArray",
        "Mini.BlockArray", "Mini.Vec3Array", "Mini.ColorArray",
        "Mini.Numbers", "Mini.Strings", "Mini.Bools", "Mini.Items",
        "Mini.Actors", "Mini.Sounds", "Mini.Blocks",
    }
    P("⑧Group", "=== 探测组类型的 Mini 名 ===")
    for _, nm in ipairs(names) do
        local ok, v = pcall(load("return " .. nm))
        -- loadstring 可能不可用，改用逐段取
        if not ok then
            local t = _G["Mini"]
            ok = false
            if type(t) == "table" then
                local key = nm:match("Mini%.(.+)$")
                v = t[key]
                ok = v ~= nil
            end
        end
        if ok and v ~= nil then
            P("⑧Group", "  ✓ %-20s className=%s", nm,
                tostring(type(v) == "table" and v.__className_ or v))
        end
    end
    -- 顺便列出 Mini 表实际有哪些显式字段
    local M = rawget(_G, "Mini")
    if type(M) == "table" then
        local keys = {}
        for k, _ in pairs(M) do keys[#keys + 1] = tostring(k) end
        table.sort(keys)
        P("⑧Group", "Mini 显式字段(%d): %s", #keys, table.concat(keys, ","):sub(1, 300))
    end
    return "见日志"
end

-- ⑨ stub 复核
function Script:ProbeStub()
    P("⑨Stub", T("loadstring", function() return loadstring end))
    P("⑨Stub", T("loadstring('return 1+1')", function()
        if type(loadstring) ~= "function" then return "不是函数" end
        return loadstring("return 1+1")
    end))
    P("⑨Stub", T("load", function() return load end))
    P("⑨Stub", T("require", function() return require end))
    P("⑨Stub", T("dofile", function() return dofile end))
    P("⑨Stub", T("io", function() return type(io) .. " 成员数=" ..
        (type(io) == "table" and select(2, (function()
            local n = 0; for _ in pairs(io) do n = n + 1 end; return n, n
        end)()) or 0) end))
    P("⑨Stub", T("package", function() return type(package) end))
    P("⑨Stub", T("debug", function() return probeModule("debug") end))
    return "见日志"
end

-- ⑩ 非标准原生扩展
function Script:ProbeNative()
    local checks = {
        { "math.pow", function() return math.pow end },
        { "math.ldexp", function() return math.ldexp end },
        { "math.mod", function() return math.mod end },
        { "math.clamp", function() return math.clamp end },
        { "math.lerp", function() return math.lerp end },
        { "math.log10", function() return math.log10 end },
        { "string.split", function() return string.split end },
        { "string.trim", function() return string.trim or string.Trim end },
        { "string.startswith", function() return string.startswith end },
        { "string.Contains", function() return string.Contains end },
        { "table.clone", function() return table.clone end },
        { "table.getn", function() return table.getn end },
        { "table.tostring", function() return table.tostring end },
        { "table.num_pairs", function() return table.num_pairs end },
        { "bit.bxor", function() return bit and bit.bxor end },
        { "bit32", function() return bit32 end },
        { "coroutine.isyieldable", function() return coroutine.isyieldable end },
        { "copy_table", function() return copy_table end },
        { "lerp(全局)", function() return lerp end },
        { "printError", function() return printError end },
    }
    for _, c in ipairs(checks) do
        P("⑩Native", T(c[1], c[2]))
    end
    -- 实跑几个
    P("⑩Native", T("string.split('a,b,c',',')", function()
        if not string.split then return "无 split" end
        local r = string.split("a,b,c", ",")
        return "#" .. (type(r) == "table" and #r or "?") .. " " .. tostring(r and r[2])
    end))
    P("⑩Native", T("table.clone({1,2})", function()
        if not table.clone then return "无 clone" end
        local r = table.clone({ 1, 2 })
        return tostring(r and r[1])
    end))
    P("⑩Native", T("math.clamp(5,0,3)", function()
        if not math.clamp then return "无 clamp" end
        return math.clamp(5, 0, 3)
    end))
    return "见日志"
end

-- 全部
function Script:ProbeAll()
    LOG = {}
    self:ProbeEdit()
    self:ProbeThread()
    self:ProbeClass()
    self:ProbeModIO()
    self:ProbeJson()
    self:ProbeOs()
    self:ProbeCmpFn()
    self:ProbeGroup()
    self:ProbeStub()
    self:ProbeNative()
    return "全部完成，共 " .. #LOG .. " 行，见日志"
end

function Script:OnStart()
    print("[探针] ===== 隐藏接口探测启动 =====")
    print("[探针] _VERSION = " .. tostring(_VERSION))
    local r = self:ProbeAll()
    print("[探针] " .. tostring(r))
    print("[探针] ===== 探测结束 =====")
end

return Script
