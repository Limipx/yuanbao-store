--[[
API 全模块反射探针 v4  —— 递归到二层(Data.Map / Data.Table 等)
====================================================================
铁律：
  * 以【运行时二维表实测结果】为准，转储只用于查"有没有这个成员"
  * 导出：只有 2000 行限制，【没有内存限制】-> 只用 1 张表，一行放多条(pack)
  * 导入：500KB 内存 + 2000 行
  * Data.Table 实机签名(来自建筑文件生成器3.1)：
        Data.Table:Clear(tableId, nil)
        Data.Table:InsertValue(tableId, nil, 一个字符串)      <- 只传【一个】
        Data.Table:GetAllValue(tableId, nil) -> allRows[i][1]  <- 第1行是头部
    传多个参数会把行号塞进第1列，不报错、静默错位
====================================================================
]]

local Script = {}

Script.propertys = {
    tableIdsText = {
        type = Mini.String,
        displayName = "输出二维表ID(只用1张)",
        defaultValue = "",
        tips = "导出无内存限制/仅2000行 -> 一张够; 留空则导出报ERR",
    },
    packSize = {
        type = Mini.Number,
        displayName = "每行合并几条(0=自动)",
        defaultValue = 0,
        minValue = 0,
        maxValue = 50,
        tips = "一条=模块|路径|类型|层级; 多条用;拼成一行",
    },
    maxDepth = {
        type = Mini.Number,
        displayName = "递归深度(2=探到Data.Map这层)",
        defaultValue = 2,
        minValue = 1,
        maxValue = 4,
    },
    blockBytes = {
        type = Mini.Number,
        displayName = "分块打印字节数",
        defaultValue = 400,
        minValue = 50,
        maxValue = 4000,
    },
}

Script.openFnArgs = {
    ScanAll = {
        returnType = Mini.String,
        displayName = "①扫描全部(含二层)",
        params = {},
    },
    ExportTable = {
        returnType = Mini.String,
        displayName = "②导出到二维表(1张)",
        params = {},
    },
    VerifyExport = {
        returnType = Mini.String,
        displayName = "③校验导出(读回比对)",
        params = {},
    },
    DumpBlocks = {
        returnType = Mini.String,
        displayName = "④分块打印结果",
        params = {},
    },
    ShowModule = {
        returnType = Mini.String,
        displayName = "⑤打印指定模块",
        params = { "模块名", Mini.String },
    },
    FindMember = {
        returnType = Mini.String,
        displayName = "⑥查找成员(关键字)",
        params = { "关键字", Mini.String },
    },
    DumpEvents = {
        returnType = Mini.String,
        displayName = "⑦打印TriggerEvent",
        params = {},
    },
    Summary = {
        returnType = Mini.String,
        displayName = "⑧统计摘要",
        params = {},
    },
    SelfTest = {
        returnType = Mini.String,
        displayName = "⑨运行自检",
        params = {},
    },
}

--------------------------------------------------------------------
-- 内置模块清单(来自转储 282 个顶层模块)
--------------------------------------------------------------------
local MODS = {
  "ABSOLUTECAMPTYPE", "Ability", "AbsoluteCampType", "Action", "ActionType", "Actor", "ActorBodyEffect",
  "Aggro", "AliveState", "AnimMode", "Area", "AreaCloneType", "AreaFillType", "AreaSimilarity", "AutoSprinklerBlock",
  "AvtPart", "BACKPACK_TYPE", "Backpack", "BackpackBeginIndex", "BackpackComponent", "BackpackType", "BeaconClampType",
  "BeaconMapType", "BeginType", "Biome", "BiomeType", "Block", "BlockAttr", "BlockEdit", "BlockId", "BlockLimits",
  "BlockStateEdit", "BlockStateType", "BlockStatus", "Blueprint", "Bool", "BoxRefresh", "BtreeRangeType",
  "Buff", "CREATUREATTR", "CameraEditState", "CameraModel", "CameraRotate", "Chat", "CheckList", "Chest",
  "ClientPositive", "CloudSever", "CmpProPermission", "CmpUIPermission", "Collider", "Color", "ColorGrandient",
  "CommonBlockPlace", "ComponentType", "ComponentUIPermissions", "ComponentUIStyle", "CraftingEdit", "CreatureAttr",
  "CreatureMotion", "Cropblock", "CustomData", "CustomModType", "CustomMsg", "CustomUI", "Data", "DeviceType",
  "DoExplodeStatus", "DoHarmStatus", "Door", "DropItem", "DropMode", "Easing", "Effect", "ElementAttr",
  "ElementType", "Entity", "EntityType", "Enum", "EquipEdit", "EquipSlotType", "ErrorCode", "EventDate",
  "ExplodeDmgType", "FaceDir", "FaceType", "Feed", "Fight", "FoodEdit", "FurnaceEdit", "FurnaceType", "GRAPHICS",
  "GSoundType", "Game", "GameActorType", "GameEffect", "GameObject", "GameRule", "GameSetting", "GamemakerRule",
  "GenerateBlock", "GoBackType", "Graphics", "GraphicsType", "GridAttr", "GroupView", "GroupWeatherType",
  "Grow", "GunAction", "GunActionBan", "GunAttr", "GunDamageType", "GunEdit", "GunFireType", "GunSpreadType",
  "GunState", "HURTTYPE", "HorizontalOffset", "HumanBodyAnchorId", "HurtType", "ITEMATTR", "InnerPopUpview",
  "Item", "ItemAbility", "ItemAttr", "ItemEdit", "ItemEffectType", "KeyCode", "LaunchProjectileStatus",
  "LayingEggType", "LightingFurniture", "LineAnimation", "LinearTransformation", "Listen", "Log", "LogLevel",
  "LuaPanda", "MODATTRIB_TYPE", "MapMarkType", "MapShopOrder", "MatchMode", "Material", "Mini", "MiniCurrency",
  "MiniMapMarkType", "MiniShopData", "MiniShopDetail", "MiniShopPage", "MiniShopWarehouse", "MiniViewSecondTab",
  "Mob", "MobType", "Mod", "ModAttribType", "Model", "ModelAction", "Monster", "MonsterEdit", "MoveType",
  "NPCShop", "Number", "ObjType", "Object", "ObjectEvent", "ObjectLib", "ObsBluePrintStatus", "OfficeUtils",
  "OldGunEdit", "PLAYERATTR", "PackEdit", "PathPoint", "Physics", "PickupActionType", "Picture", "PixelUnits",
  "Player", "PlayerAttr", "PlayerBodyUIHight", "PlayerController", "PlayerMotion", "PlayerNameType", "PlayerRelations",
  "PlayerType", "Prefab", "ProgressImg", "ProgressVal", "Projectile", "ProjectileEdit", "RandomAddStatus",
  "RayDetectType", "RecoverStatus", "RelativeCampType", "RelativeType", "Reproduction", "Ride", "Roadblock",
  "Role", "RoleAttr", "RoleMotion", "RolePickupType", "Rotation", "Scale", "SkeletonPoint", "SkyBox", "SkyBoxFilter",
  "SkyboxAttr", "SkyboxAttrNoTime", "SkyboxColor", "SkyboxFilter", "SkyboxFilterSwitch", "SkyboxMap", "SkyboxParticle",
  "SkyboxSwitch", "SkyboxTime", "SortType", "Sound", "Status", "StatusEdit", "StorageType", "String", "SurviveComponent",
  "Tag", "Tame", "Task", "TaskAnimType", "TaskChainType", "TaskDialogType", "TaskEvent", "TaskPassType",
  "TaskType", "TaskUIType", "Team", "TeamAttr", "TeamResults", "TerrainType", "ThrowItem", "Timer", "ToolEdit",
  "TouchState", "Trigger", "TriggerEvent", "TurnFaceDir", "UIAttr", "UIProjectSet", "UIScollDir", "UiElement",
  "UiState", "UseEdit", "VDistanceRange", "VIEWPORTTYPE", "VarType", "Vec2", "Vec3", "VerticalOffset",
  "ViedoPlayMode", "ViewPortType", "Villager", "WeatherGroup", "WeatherType", "WorkStage", "WorkeStage",
  "World", "WorldContainer", "WorldRuleBaseSetting", "WorldRuleCloudSetting", "WorldRuleFightSetting",
  "WorldRuleHUDUI", "WorldRuleRebirth", "WorldRuleSceneUI", "WorldRuleSound", "WorldRuleStartMode", "WorldType",
  "__info", "bit", "coroutine", "debug", "json", "math", "os", "string", "table", "threadpool",
}

--------------------------------------------------------------------
-- 工具
--------------------------------------------------------------------
local function _split(s, sep)
    local r, n = {}, 0
    if not s or s == "" then return r end
    sep = sep or ","
    local pat = "[^" .. sep .. "]+"
    for w in string.gmatch(s, pat) do
        n = n + 1
        local v = string.gsub(w, "^%s+", "")
        v = string.gsub(v, "%s+$", "")
        r[n] = v
    end
    return r
end

local function _trim(s)
    if not s then return "" end
    s = string.gsub(s, "^%s+", "")
    s = string.gsub(s, "%s+$", "")
    return s
end

local function _join(t, sep)
    local r, n = {}, 0
    for i = 1, #t do
        n = n + 1
        r[n] = tostring(t[i])
    end
    return table.concat(r, sep or ",")
end

-- 不用 math.ceil(沙盒实测返回nil): 纯加法算块数
local function _blocks(total, size)
    if size <= 0 then size = 400 end
    local n = 0
    local acc = 0
    while acc < total do
        n = n + 1
        acc = acc + size
    end
    if n == 0 then n = 1 end
    return n
end

local function _printBlocks(tag, lines)
    local size = Script.blockBytes or 400
    if size < 50 then size = 50 end
    local all = _join(lines, "\n")
    local nbk = _blocks(string.len(all), size)
    local pos = 1
    for b = 1, nbk do
        local part = string.sub(all, pos, pos + size - 1)
        pos = pos + size
        print("[块" .. b .. "/" .. nbk .. "] " .. tag .. "\n" .. part)
    end
    return nbk
end

--------------------------------------------------------------------
-- 记录与递归
--------------------------------------------------------------------
local _recs = {}
local _seen = {}
local _stat = { modOK = 0, modMiss = 0, rec = 0, t1 = 0, t2 = 0, t3 = 0 }

local function _add(path, ty, depth)
    local n = #_recs + 1
    _recs[n] = { path = path, ty = ty, d = depth }
    _stat.rec = n
    if depth == 1 then
        _stat.t1 = _stat.t1 + 1
    elseif depth == 2 then
        _stat.t2 = _stat.t2 + 1
    else
        _stat.t3 = _stat.t3 + 1
    end
end

-- 递归遍历一张表; depth=1 表示这是模块的直接成员
local function _walk(tbl, path, depth, maxd)
    if type(tbl) ~= "table" then return end
    if depth > maxd then return end
    local key = "@" .. tostring(tbl)
    if _seen[key] then return end
    _seen[key] = 1

    local cnt = 0
    local okf, errf = pcall(function()
        for k, v in pairs(tbl) do
            cnt = cnt + 1
            local full = path .. "." .. tostring(k)
            local ty = type(v)
            if ty == "table" then
                _add(full, "table", depth)
                if depth < maxd then
                    _walk(v, full, depth + 1, maxd)
                end
            else
                _add(full, ty, depth)
            end
        end
    end)
    if not okf then
        _add(path .. ".(遍历失败:" .. tostring(errf) .. ")", "?", depth)
        return
    end
    if cnt == 0 then
        _add(path .. ".(空表)", "empty", depth)
    end
end

local function _scan(maxd)
    _recs = {}
    _seen = {}
    _stat = { modOK = 0, modMiss = 0, rec = 0, t1 = 0, t2 = 0, t3 = 0 }
    local missing = {}
    for i = 1, #MODS do
        local name = MODS[i]
        local ok, obj = pcall(function() return _G[name] end)
        if ok and obj ~= nil then
            _stat.modOK = _stat.modOK + 1
            _add(name, type(obj), 1)
            if type(obj) == "table" then
                _walk(obj, name, 2, maxd)
            end
        else
            _stat.modMiss = _stat.modMiss + 1
            missing[#missing + 1] = name
        end
    end
    return missing
end

local function _line(r)
    local mod, rest
    local p = string.find(r.path, ".", 1, true)
    if p then
        mod = string.sub(r.path, 1, p - 1)
        rest = string.sub(r.path, p + 1)
    else
        mod = r.path
        rest = "(自身)"
    end
    return mod .. "|" .. rest .. "|" .. r.ty .. "|L" .. tostring(r.d)
end

--------------------------------------------------------------------
-- 二维表
--------------------------------------------------------------------
local function _ids()
    local ok, v = pcall(function() return Script.tableIdsText end)
    if not ok then v = nil end
    if type(v) == "string" and v ~= "" then
        return _split(v, ",")
    end
    return {}
end

local function _autoPack(n)
    if n <= 0 then return 1 end
    local pk = 1
    while pk * 1999 < n do
        pk = pk + 1
    end
    return pk
end

--------------------------------------------------------------------
function Script:OnStart()
    print("[API探针v4] 已载入, 递归深度=" .. tostring(Script.maxDepth))
    print("[API探针v4] 顺序: ①扫描全部 -> ②导出(只1张) -> ③校验")
end

function Script:ScanAll()
    local maxd = Script.maxDepth or 2
    if maxd < 1 then maxd = 1 end
    local missing = _scan(maxd)
    local out = {}
    out[#out + 1] = "============== 扫描结果(含二层) =============="
    out[#out + 1] = "模块 存在" .. tostring(_stat.modOK) .. " / 缺失" .. tostring(_stat.modMiss)
    out[#out + 1] = "记录总数 " .. tostring(_stat.rec)
    out[#out + 1] = "  L1=" .. tostring(_stat.t1) .. "  L2=" .. tostring(_stat.t2) .. "  L3+=" .. tostring(_stat.t3)
    if #missing > 0 then
        out[#out + 1] = "缺失: " .. _join(missing, ",")
    end
    out[#out + 1] = "=============================================="
    local s = _join(out, "\n")
    print(s)
    return "OK " .. tostring(_stat.rec) .. "条(L2=" .. tostring(_stat.t2) .. ")"
end

function Script:ExportTable()
    if #_recs == 0 then return "ERR: 还没扫描, 请先点①" end
    local ids = _ids()
    if #ids < 1 then
        return "ERR: 请在属性「输出二维表ID」填表ID(只用1张)"
    end
    local n = #_recs
    local pk = Script.packSize or 0
    if pk <= 0 then pk = _autoPack(n) end
    local body = {}
    local rn = 0
    local i = 1
    while i <= n do
        local buf = {}
        local c = 0
        while c < pk and i <= n do
            c = c + 1
            buf[c] = _line(_recs[i])
            i = i + 1
        end
        rn = rn + 1
        body[rn] = _join(buf, ";")
    end
    if rn > 1999 then
        return "ERR: 需要" .. tostring(rn) .. "行超2000 -> 把合并数调到 " .. tostring(_autoPack(n))
    end
    local tid = ids[1]
    local ok, err = pcall(function()
        Data.Table:Clear(tid, nil)
        Data.Table:InsertValue(tid, nil,
            "APIR|V4|REC:" .. tostring(n) .. "|PK:" .. tostring(pk) .. "|DEP:" .. tostring(Script.maxDepth or 2))
        for r = 1, rn do
            Data.Table:InsertValue(tid, nil, body[r])
        end
    end)
    if not ok then return "ERR: 写入失败 " .. tostring(err) end
    print("[导出] " .. tostring(rn) .. "行 x 每行" .. tostring(pk) .. "条 -> 1张表 id=" .. tostring(tid))
    return "OK " .. tostring(rn) .. "行; 点③校验"
end

function Script:VerifyExport()
    local ids = _ids()
    if #ids < 1 then return "ERR: 未填表ID" end
    local tid = ids[1]
    local ok, rows = pcall(function() return Data.Table:GetAllValue(tid, nil) end)
    if not ok then return "ERR: 读回失败 " .. tostring(rows) end
    if type(rows) ~= "table" or #rows == 0 then
        return "★校验无效: 读回0行(表空或未写入), 不能算通过"
    end
    local pk = 1
    local h = rows[1]
    local hv = ""
    if type(h) == "table" then hv = tostring(h[1]) else hv = tostring(h) end
    local p = string.find(hv, "PK:", 1, true)
    if p then pk = tonumber(string.sub(hv, p + 3)) or 1 end
    local got, bad, firstBad = 0, 0, ""
    for i = 2, #rows do
        local r = rows[i]
        local v = ""
        if type(r) == "table" then v = tostring(r[1]) else v = tostring(r) end
        local parts = _split(v, ";")
        for j = 1, #parts do
            got = got + 1
            local want = nil
            if got <= #_recs then want = _line(_recs[got]) end
            if want and parts[j] ~= want then
                bad = bad + 1
                if firstBad == "" then
                    firstBad = "行" .. tostring(i) .. "第" .. tostring(j) .. "条 期望[" .. want .. "] 实得[" .. parts[j] .. "]"
                end
            end
        end
    end
    local out = {}
    out[#out + 1] = "头部: " .. hv
    out[#out + 1] = "读回" .. tostring(#rows - 1) .. "行, 展开" .. tostring(got) .. "条, 内存记录" .. tostring(#_recs) .. "条"
    if got == 0 then
        return "★校验无效: 展开0条 -> 第1列不是数据(检查InsertValue是否只传1个字符串)"
    end
    if bad == 0 and got == #_recs then
        out[#out + 1] = "★★校验通过 " .. tostring(got) .. "条逐条一致"
    else
        out[#out + 1] = "★校验失败 不一致" .. tostring(bad) .. "处; 首个: " .. firstBad
    end
    local s = _join(out, "\n")
    print(s)
    return s
end

function Script:DumpBlocks()
    if #_recs == 0 then return "ERR: 先点①扫描" end
    local lines = {}
    for i = 1, #_recs do lines[i] = _line(_recs[i]) end
    local nb = _printBlocks("全量(含二层)", lines)
    return "OK " .. tostring(#lines) .. "条分" .. tostring(nb) .. "块"
end

function Script:ShowModule(name)
    name = _trim(name)
    if name == "" then return "ERR: 填模块名, 如 Data" end
    local lines, c = {}, 0
    for i = 1, #_recs do
        local p = string.find(_recs[i].path, ".", 1, true)
        local mod = _recs[i].path
        if p then mod = string.sub(_recs[i].path, 1, p - 1) end
        if mod == name then
            c = c + 1
            lines[c] = _line(_recs[i])
        end
    end
    if c == 0 then return "模块[" .. name .. "] 无记录" end
    _printBlocks("模块 " .. name, lines)
    return "OK " .. tostring(c) .. "条"
end

function Script:FindMember(kw)
    kw = _trim(kw)
    if kw == "" then return "ERR: 填关键字" end
    local lines, c = {}, 0
    for i = 1, #_recs do
        if string.find(_recs[i].path, kw, 1, true) then
            c = c + 1
            lines[c] = _line(_recs[i])
        end
    end
    if c == 0 then return "无匹配: " .. kw end
    _printBlocks("匹配 " .. kw, lines)
    return "OK " .. tostring(c) .. "条"
end

function Script:DumpEvents()
    local ok, t = pcall(function() return TriggerEvent end)
    if not ok or type(t) ~= "table" then return "ERR: TriggerEvent 不可访问" end
    local keys, c = {}, 0
    for k, v in pairs(t) do
        c = c + 1
        keys[c] = tostring(k) .. " = " .. tostring(v)
    end
    if c == 0 then return "TriggerEvent 是空表" end
    table.sort(keys)
    _printBlocks("TriggerEvent(" .. tostring(c) .. ")", keys)
    return "OK " .. tostring(c) .. "个事件常量"
end

function Script:Summary()
    if #_recs == 0 then return "ERR: 先点①扫描" end
    local cnt, order = {}, {}
    for i = 1, #_recs do
        local p = string.find(_recs[i].path, ".", 1, true)
        local mod = _recs[i].path
        if p then mod = string.sub(_recs[i].path, 1, p - 1) end
        if not cnt[mod] then
            cnt[mod] = 0
            order[#order + 1] = mod
        end
        cnt[mod] = cnt[mod] + 1
    end
    table.sort(order, function(a, b) return cnt[a] > cnt[b] end)
    local out = {}
    out[#out + 1] = "============== 摘要 =============="
    out[#out + 1] = "模块 存在" .. tostring(_stat.modOK) .. " 缺失" .. tostring(_stat.modMiss)
    out[#out + 1] = "记录 " .. tostring(_stat.rec) .. " (L1=" .. _stat.t1 .. " L2=" .. _stat.t2 .. " L3+=" .. _stat.t3 .. ")"
    local lim = 15
    if #order < lim then lim = #order end
    for i = 1, lim do
        out[#out + 1] = "  " .. order[i] .. " : " .. tostring(cnt[order[i]]) .. "条"
    end
    out[#out + 1] = "=================================="
    local s = _join(out, "\n")
    print(s)
    return s
end

function Script:SelfTest()
    local pass, fail = 0, 0
    local out = {}
    local function ck(cond, name)
        if cond then pass = pass + 1; out[#out + 1] = "[PASS] " .. name
        else fail = fail + 1; out[#out + 1] = "[FAIL] " .. name end
    end
    ck(type(_G) == "table", "_G 是 table")
    ck(#MODS > 200, "内置模块清单 " .. tostring(#MODS) .. " 个")
    ck(type(os.timeMs) == "function", "os.timeMs 可调用")
    ck(os.clock == nil, "os.clock 不存在(符合预期)")
    local dok = pcall(function() return type(Data) end)
    ck(dok and type(Data) == "table", "模块 Data 存在")
    local dtk = pcall(function() return type(Data.Table) end)
    ck(dtk, "Data.Table 可访问")
    local dmk = pcall(function() return type(Data.Map) end)
    ck(dmk, "Data.Map 可访问")
    _scan(Script.maxDepth or 2)
    ck(_stat.rec > 1000, "扫描产出 " .. tostring(_stat.rec) .. " 条")
    ck(_stat.t2 > 0, "二层记录 " .. tostring(_stat.t2) .. " 条(>0=探到了)")
    print("============== 自检 ==============")
    print(_join(out, "\n"))
    print("通过 " .. tostring(pass) .. " / 失败 " .. tostring(fail))
    print("==================================")
    return "自检 " .. tostring(pass) .. "通过 / " .. tostring(fail) .. "失败"
end

return Script
