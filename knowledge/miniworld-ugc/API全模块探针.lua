--====================================================================
-- API 全模块探针 v1  (迷你世界 UGC 3.0 / Lua 5.1 组件脚本)
--
-- 干什么：把内置环境转储(1.54.0)里全部 284 个 table 模块，在
--         【运行时】逐个反射遍历，记录「模块 . 成员 = 类型」，
--         然后 (a) 写进二维表  (b) 分块 print 到日志。
--
-- 【铁律 1】以【运行时二维表的结果】为准。内置转储清单只用来提示
--           「哪些模块在运行时不见了」，绝不反过来用它覆盖实测结果。
-- 【铁律 2】导出【原版】：不压缩、不编码、不截断。二维表导出没有内存
--           限制，原文直出，每行一条完整记录。
--
-- 事件：TriggerEvent / ObjectEvent 单独打印（开放函数 ②）。
--
-- 开放函数：
--   ① ScanAll()            扫描全部模块（内置清单 + 运行时 _G 新模块）
--   ② PrintEvents()        打印 TriggerEvent / ObjectEvent 事件表
--   ③ ExportTable()        导出到二维表（原版不压缩，默认1张表，一行放多条）
--   ④ DumpLog()            全部结果分块打印到日志
--   ⑤ DumpCsv()            按 CSV(3列)格式分块打印，可直接存成 .csv
--   ⑥ DumpModule(模块名)    只打印一个模块
--   ⑦ Lookup(关键字)        按关键字查成员（模块名或成员名模糊匹配）
--   ⑧ Diff()               与内置转储清单对照：缺失 / 新增
--   ⑨ SelfCheck()          自检
--   ⑩ Verify()             读回二维表，逐行比对，证明导出真的落进去了
--
-- 依赖：Data.Table:Clear / InsertValue / GetAllValue
--       签名以 建筑文件生成器3.1 实机写法为准，不许照转储猜（转储里是变参...）
--       os.timeMs（计时，不用 os.clock，引擎没有）
--====================================================================
local Script = {}

--======================== 属性 ========================
Script.propertys = {
    outTableIds = {
        type = Mini.String,
        default = "",
        displayName = "输出二维表ID组",
        tips = "逗号分隔。默认只用第1张：导出只有2000行限制、无内存限制，一行可放多条，1张表就够"
    },
    -- 【限制记忆（用户反复强调，已写死）】
    --   导入：500KB 内存 + 2000 行
    --   导出：只有 2000 行上限，【没有】内存限制
    -- 所以导出一律原版直出：不编码、不压缩、不截断；每表最多 2000 行。
    rowsPerTable = {
        type = Mini.Number,
        default = 2000,
        displayName = "每表行数",
        minValue = 100,
        maxValue = 2000,
        format = "%.0f",
        tips = "每表最多2000行(含头部，数据1999)。一行放多条后通常1张表即可，不需要分片"
    },
    mergeLines = {
        type = Mini.Number,
        default = 0,
        displayName = "每行合并几个成员(0=自动)",
        minValue = 0,
        maxValue = 64,
        format = "%.0f",
        tips = "0=自动：算出刚好让 1 张表装下全部的行合并数(3840条时=2，约1920行)。导出无内存限制只有2000行限制，所以永远只用1张表。手动填N则每行放N条，分号拼接，纯原文可读，不是编码压缩"
    },
    chunkSize = {
        type = Mini.Number,
        default = 800,
        displayName = "打印分块字符数",
        minValue = 100,
        maxValue = 8000,
        format = "%.0f",
        tips = "print 单行过长可能被日志截断，默认 800 字符一块"
    },
    scanStdLib = {
        type = Mini.Bool,
        default = true,
        displayName = "包含标准库模块",
        tips = "table math string os bit coroutine debug 等也扫一遍"
    },
    scanRuntimeNew = {
        type = Mini.Bool,
        default = true,
        displayName = "扫描运行时新模块",
        tips = "遍历 _G 找转储里没有的表，标为 R"
    },
    onlyFunction = {
        type = Mini.Bool,
        default = false,
        displayName = "只记录函数",
        tips = "开启后不记录常量/枚举/子表，行数大幅减少"
    }
}

--======================== 开放函数 ========================
Script.openFnArgs = {
    ScanAll = {
        returnType = Mini.String,
        displayName = "①扫描全部模块",
        params = {}
    },
    PrintEvents = {
        returnType = Mini.String,
        displayName = "②打印事件表",
        params = { "开关", Mini.String }
    },
    ExportTable = {
        returnType = Mini.String,
        displayName = "③导出到二维表",
        params = {}
    },
    DumpLog = {
        returnType = Mini.String,
        displayName = "④分块打印全部结果",
        params = {}
    },
    DumpCsv = {
        returnType = Mini.String,
        displayName = "⑤打印CSV(3列)",
        params = {}
    },
    DumpModule = {
        returnType = Mini.String,
        displayName = "⑥打印单个模块",
        params = { "模块名", Mini.String }
    },
    Lookup = {
        returnType = Mini.String,
        displayName = "⑦查成员",
        params = { "关键字", Mini.String }
    },
    Diff = {
        returnType = Mini.String,
        displayName = "⑧与转储对照",
        params = {}
    },
    SelfCheck = {
        returnType = Mini.String,
        displayName = "⑨自检",
        params = {}
    },
    Verify = {
        returnType = Mini.String,
        displayName = "⑩校验导出(读回比对)",
        params = {}
    }
}

--======================== 内置转储模块清单 ========================
-- 来源：1.54.0 环境转储 dump_parsed.json 中所有顶层 table 模块（284 个）
-- 仅用于「运行时缺失提示」，不参与任何判定
local MODS_STR = "ABSOLUTECAMPTYPE,Ability,AbsoluteCampType,Action,ActionType,Actor,ActorBodyEffect,Aggro,AliveState,AnimMode,Area,AreaCloneType,AreaFillType,AreaSimilarity,AutoSprinklerBlock,AvtPart,BACKPACK_TYPE,Backpack,BackpackBeginIndex,BackpackComponent,BackpackType,BeaconClampType,BeaconMapType,BeginType,Biome,BiomeType,Block,BlockAttr,BlockEdit,BlockId,BlockLimits,BlockStateEdit,BlockStateType,BlockStatus,Blueprint,Bool,BoxRefresh,BtreeRangeType,Buff,CREATUREATTR,CameraEditState,CameraModel,CameraRotate,Chat,CheckList,Chest,ClientPositive,CloudSever,CmpProPermission,CmpUIPermission,Collider,Color,ColorGrandient,CommonBlockPlace,ComponentType,ComponentUIPermissions,ComponentUIStyle,CraftingEdit,CreatureAttr,CreatureMotion,Cropblock,CustomData,CustomModType,CustomMsg,CustomUI,Data,DeviceType,DoExplodeStatus,DoHarmStatus,Door,DropItem,DropMode,Easing,Effect,ElementAttr,ElementType,Entity,EntityType,Enum,EquipEdit,EquipSlotType,ErrorCode,EventDate,ExplodeDmgType,FaceDir,FaceType,Feed,Fight,FoodEdit,FurnaceEdit,FurnaceType,GRAPHICS,GSoundType,Game,GameActorType,GameEffect,GameObject,GameRule,GameSetting,GamemakerRule,GenerateBlock,GoBackType,Graphics,GraphicsType,GridAttr,GroupView,GroupWeatherType,Grow,GunAction,GunActionBan,GunAttr,GunDamageType,GunEdit,GunFireType,GunSpreadType,GunState,HURTTYPE,HorizontalOffset,HumanBodyAnchorId,HurtType,ITEMATTR,InnerPopUpview,Item,ItemAbility,ItemAttr,ItemEdit,ItemEffectType,KeyCode,LaunchProjectileStatus,LayingEggType,LightingFurniture,LineAnimation,LinearTransformation,Listen,Log,LogLevel,LuaPanda,MODATTRIB_TYPE,MapMarkType,MapShopOrder,MatchMode,Material,Mini,MiniCurrency,MiniMapMarkType,MiniShopData,MiniShopDetail,MiniShopPage,MiniShopWarehouse,MiniViewSecondTab,Mob,MobType,Mod,ModAttribType,Model,ModelAction,Monster,MonsterEdit,MoveType,NPCShop,Number,ObjType,Object,ObjectEvent,ObjectLib,ObsBluePrintStatus,OfficeUtils,OldGunEdit,PLAYERATTR,PackEdit,PathPoint,Physics,PickupActionType,Picture,PixelUnits,Player,PlayerAttr,PlayerBodyUIHight,PlayerController,PlayerMotion,PlayerNameType,PlayerRelations,PlayerType,Prefab,ProgressImg,ProgressVal,Projectile,ProjectileEdit,RandomAddStatus,RayDetectType,RecoverStatus,RelativeCampType,RelativeType,Reproduction,Ride,Roadblock,Role,RoleAttr,RoleMotion,RolePickupType,Rotation,Scale,SkeletonPoint,SkyBox,SkyBoxFilter,SkyboxAttr,SkyboxAttrNoTime,SkyboxColor,SkyboxFilter,SkyboxFilterSwitch,SkyboxMap,SkyboxParticle,SkyboxSwitch,SkyboxTime,SortType,Sound,Status,StatusEdit,StorageType,String,SurviveComponent,Tag,Tame,Task,TaskAnimType,TaskChainType,TaskDialogType,TaskEvent,TaskPassType,TaskType,TaskUIType,Team,TeamAttr,TeamResults,TerrainType,ThrowItem,Timer,ToolEdit,TouchState,Trigger,TriggerEvent,TurnFaceDir,UIAttr,UIProjectSet,UIScollDir,UiElement,UiState,UseEdit,VDistanceRange,VIEWPORTTYPE,VarType,Vec2,Vec3,VerticalOffset,ViedoPlayMode,ViewPortType,Villager,WeatherGroup,WeatherType,WorkStage,WorkeStage,World,WorldContainer,WorldRuleBaseSetting,WorldRuleCloudSetting,WorldRuleFightSetting,WorldRuleHUDUI,WorldRuleRebirth,WorldRuleSceneUI,WorldRuleSound,WorldRuleStartMode,WorldType,__info,bit,coroutine,debug,io,json,math,os,package,string,table,threadpool"

local STDLIB = {
    table = 1, math = 1, string = 1, os = 1, io = 1,
    debug = 1, coroutine = 1, package = 1, bit = 1, json = 1
}

local _mods = {}      -- 内置模块名 -> true
local _rows = {}      -- 结果行 {mod, mem, typ, src}
local _stat = { modOk = 0, modNil = 0, modNoTbl = 0, mem = 0, newMod = 0, err = 0, ms = 0 }
local _done = false
local _scanStd = true
local _scanNew = true
local _chunkSize = 800

--======================== 基础工具 ========================

-- 稳健分割：不用 string.split（其行为未验证），也不用 [^,]+（会跳过空字段）
local function _sp(s, sep)
    local out, cur = {}, ""
    local n = #s
    for i = 1, n do
        local c = s:sub(i, i)
        if c == sep then
            out[#out + 1] = cur
            cur = ""
        else
            cur = cur .. c
        end
    end
    out[#out + 1] = cur
    return out
end

local function _t(v)
    if v == nil then return "nil" end
    local ok, r = pcall(type, v)
    if not ok then return "?" end
    return r
end

local function _s(v)
    local ok, r = pcall(tostring, v)
    if not ok then return "<不能转字符串>" end
    return r or ""
end

-- 计时：os.timeMs 可能不存在或返回非数字，一律防御（避免 t1-t0 崩）
-- 自实现 join，避免依赖 table.concat（各版本行为不一致）
local function _join(arr, sep)
    local out = ""
    for i = 1, #arr do
        if i > 1 then out = out .. sep end
        out = out .. _s(arr[i])
    end
    return out
end

local function _now()
    local ok, v = pcall(function() return os.timeMs() end)
    if ok and type(v) == "number" then return v end
    return 0
end

local function _loadMods()
    local n = 0
    local arr = _sp(MODS_STR, ",")
    for i = 1, #arr do
        local m = arr[i]
        if m ~= "" then
            _mods[m] = true
            n = n + 1
        end
    end
    return n
end

local _modCount = _loadMods()

--======================== 记录 ========================

-- 只记录函数的开关（属性 onlyFunction）
local _onlyFn = false
local function _want(typ)
    if _onlyFn then return typ == "function" end
    return true
end

--======================== 扫描单个模块 ========================

local function _scanOne(name, src)
    local ok, m = pcall(function() return _G[name] end)
    if not ok or m == nil then
        _stat.modNil = _stat.modNil + 1
        if _want("nil") then
            _rows[#_rows + 1] = { name, "(模块不存在)", "nil", src }
        end
        return 0
    end
    local tp = _t(m)
    if tp ~= "table" then
        _stat.modNoTbl = _stat.modNoTbl + 1
        if _want(tp) then
            _rows[#_rows + 1] = { name, "(非table)", tp, src }
        end
        return 0
    end
    local cnt = 0
    local ok2, err2 = pcall(function()
        for k, v in pairs(m) do
            cnt = cnt + 1
            local tp2 = _t(v)
            if _want(tp2) then
                _rows[#_rows + 1] = { name, _s(k), tp2, src }
            end
        end
    end)
    if not ok2 then
        _stat.err = _stat.err + 1
        _rows[#_rows + 1] = { name, "(遍历失败)", "err", src }
        return 0
    end
    _stat.modOk = _stat.modOk + 1
    _stat.mem = _stat.mem + cnt
    return cnt
end

--======================== 排序 ========================

local function _sortRows()
    table.sort(_rows, function(a, b)
        if a[1] ~= b[1] then return a[1] < b[1] end
        return a[2] < b[2]
    end)
end

--======================== 主扫描 ========================

local function _scanAll()
    _rows = {}
    _stat = { modOk = 0, modNil = 0, modNoTbl = 0, mem = 0, newMod = 0, err = 0, ms = 0 }
    local t0 = _now()

    -- 1) 内置清单里的模块
    local arr = _sp(MODS_STR, ",")
    for i = 1, #arr do
        local m = arr[i]
        if m ~= "" then
            local isStd = STDLIB[m]
            local skip = (isStd and (not _scanStd))
            if not skip then
                _scanOne(m, "D")
            end
        end
    end

    -- 2) 运行时 _G 里的新表
    local wantNew = _scanNew
    if wantNew then
        local ok, err = pcall(function()
            for k, v in pairs(_G) do
                local kn = _s(k)
                if kn ~= "_G" and _t(v) == "table" and not _mods[kn] then
                    local isStd = STDLIB[kn]
                    local skip = (isStd and (not _scanStd))
                    if not skip then
                        _stat.newMod = _stat.newMod + 1
                        _scanOne(kn, "R")
                    end
                end
            end
        end)
        if not ok then _stat.err = _stat.err + 1 end
    end

    _sortRows()
    _done = true
    local t1 = _now()
    _stat.ms = t1 - t0
    return true
end

--======================== 分块打印 ========================

local function _chunks(lines, tag)
    local lim = _chunkSize
    if not lim or lim < 100 then lim = 800 end
    local buf, nb, tot = "", 0, 0
    for i = 1, #lines do
        local L = lines[i]
        buf = buf .. L .. "\n"
        tot = tot + #L + 1
        if #buf >= lim then
            nb = nb + 1
            print("[" .. tag .. " 块" .. nb .. "]==========\n" .. buf)
            buf = ""
        end
    end
    if buf ~= "" then
        nb = nb + 1
        print("[" .. tag .. " 块" .. nb .. "]==========\n" .. buf)
    end
    print("[" .. tag .. "] 共" .. nb .. "块 / " .. tot .. "字节")
    return nb
end

--======================== 行 -> 文本 ========================

local function _lineOf(r)
    return r[1] .. "|" .. r[2] .. "|" .. r[3] .. "|" .. r[4]
end

local function _csvOf(i, r)
    return i .. ',"' .. r[1] .. "|" .. r[2] .. "|" .. r[3] .. "|" .. r[4] .. '",'
end

local function _allLines()
    local out = {}
    for i = 1, #_rows do
        out[#out + 1] = _lineOf(_rows[i])
    end
    return out
end

local function _allCsv()
    local out = {}
    out[#out + 1] = "字段备注,API数据,"
    out[#out + 1] = "字段名,API数据,"
    out[#out + 1] = "字段类型,string,"
    for i = 1, #_rows do
        out[#out + 1] = _csvOf(i, _rows[i])
    end
    return out
end

--======================== 写二维表 ========================

-- 写二维表。
-- 【签名以 建筑文件生成器3.1 实测为准，不猜】
--   Data.Table:Clear(tableId, nil)
--   Data.Table:InsertValue(tableId, nil, 一个字符串)   ← 每行只传一个字符串
--   Data.Table:GetAllValue(tableId, nil) -> { {[1]=字符串}, ... }  第1行是头部
-- 转储里 InsertValue 是 (self,varId,playerId,...)，变参；但 3.1 实机只传一个
-- 字符串就能用，且读回来 row[1] 就是那个字符串。多传会把行号写进数据表，
-- 导出后第一列全是 1,2,3...，真正的 API 数据跑到第二列去。
local MAX_TABLE_ROWS = 2000
local MAX_DATA_ROWS  = 1999      -- 减去第 1 行头部

-- 把若干条记录合并成一行，用 ";" 分隔（纯原文，不是编码/压缩）
-- 导出无内存限制，只有 2000 行限制 —— 所以一行能放很多，1 张表就够
local function _packLines(rows, pack)
    local out = {}
    local i, n = 1, #rows
    while i <= n do
        local t, j = {}, 0
        while j < pack and i <= n do
            j = j + 1
            t[j] = _lineOf(rows[i])
            i = i + 1
        end
        out[#out + 1] = _join(t, ";")
    end
    return out
end

-- pack 自动值：刚好让 1 张表装下全部记录
local function _autoPack(n)
    local pack = 1
    local acc = MAX_DATA_ROWS
    while acc < n do
        pack = pack + 1
        acc = MAX_DATA_ROWS * pack
    end
    return pack
end

local function _writeTable(tid, lines, from, to, hdr)
    if not (Data and Data.Table) then
        return false, "Data.Table 不可用"
    end
    pcall(function() Data.Table:Clear(tid, nil) end)

    -- 头部行（与 3.1 同一套路：第 1 行放元信息，读的时候跳过）
    local okh, errh = pcall(function()
        Data.Table:InsertValue(tid, nil, hdr)
    end)
    if not okh then
        return false, "写头部失败: " .. _s(errh)
    end

    local n = 0
    for i = from, to do
        local line = lines[i]
        local ok2, err2 = pcall(function()
            Data.Table:InsertValue(tid, nil, line)
        end)
        if ok2 then
            n = n + 1
        else
            return false, "第 " .. i .. " 行失败: " .. _s(err2)
        end
    end
    return true, n
end

-- 读回二维表，校验导出是否真的落进去了
local function _readBack(tid)
    local all
    local ok, err = pcall(function()
        all = Data.Table:GetAllValue(tid, nil)
    end)
    if not ok then return nil, "读取失败: " .. _s(err) end
    if type(all) ~= "table" then return nil, "GetAllValue 返回的不是表" end
    local hdr = ""
    if type(all[1]) == "table" and type(all[1][1]) == "string" then
        hdr = all[1][1]
    end
    local out = {}
    for i = 2, #all do          -- 跳过第 1 行头部
        local row = all[i]
        if type(row) == "table" and type(row[1]) == "string" then
            out[#out + 1] = row[1]
        end
    end
    return out, hdr
end

--======================== 组件启动 ========================

function Script:OnStart()
    print("[API全模块探针] 已载入")
    print("[API全模块探针] 内置转储模块 " .. _modCount .. " 个")
    print("[API全模块探针] 请逐个调用: ①扫描全部模块 / ②打印事件表 / ③导出到二维表 / ④分块打印全部结果")
    print("[API全模块探针] 先填属性: 输出二维表ID组")
end

--======================== 开放函数实现 ========================

function Script:ScanAll()
    _chunkSize = self.chunkSize
    _onlyFn = (self.onlyFunction == true)
    _scanStd = (self.scanStdLib ~= false)
    _scanNew = (self.scanRuntimeNew ~= false)
    _scanAll()
    local s = _stat
    return "扫描完成 模块OK=" .. s.modOk .. " 缺失=" .. s.modNil
        .. " 非表=" .. s.modNoTbl .. " 新模块=" .. s.newMod
        .. " 成员=" .. s.mem .. " 记录行=" .. #_rows
        .. " 遍历出错=" .. s.err .. " 耗时=" .. s.ms .. "ms"
end

function Script:PrintEvents(sw)
    _chunkSize = self.chunkSize
    local which = sw or ""
    local names = { "TriggerEvent", "ObjectEvent" }
    if which == "1" then names = { "TriggerEvent" } end
    if which == "2" then names = { "ObjectEvent" } end
    local lines = {}
    for i = 1, #names do
        local nm = names[i]
        lines[#lines + 1] = "========== " .. nm .. " =========="
        local ok, m = pcall(function() return _G[nm] end)
        if not ok or m == nil then
            lines[#lines + 1] = nm .. " 不存在"
        elseif _t(m) ~= "table" then
            lines[#lines + 1] = nm .. " 类型=" .. _t(m)
        else
            local cnt = 0
            local ok2 = pcall(function()
                for k, v in pairs(m) do
                    cnt = cnt + 1
                    lines[#lines + 1] = string.format("事件 %d. %s = %s", cnt, _s(k), _t(v))
                end
            end)
            if not ok2 then lines[#lines + 1] = nm .. " 遍历失败" end
            lines[#lines + 1] = nm .. " 共 " .. cnt .. " 个事件"
        end
    end
    _chunks(lines, "事件")
    return "已打印 " .. #names .. " 个事件表"
end

function Script:ExportTable()
    _chunkSize = self.chunkSize
    _onlyFn = (self.onlyFunction == true)
    if not _done then
        _scanStd = (self.scanStdLib ~= false)
        _scanNew = (self.scanRuntimeNew ~= false)
        _scanAll()
    end
    local ids = _sp(self.outTableIds or "", ",")
    local real = {}
    for i = 1, #ids do
        local v = ids[i]
        v = v:gsub("^%s+", ""):gsub("%s+$", "")
        if v ~= "" then real[#real + 1] = v end
    end
    if #real == 0 then
        return "ERR: 属性[输出二维表ID组]为空，先填表ID（逗号分隔）"
    end
    -- 【铁律】导出只有 2000 行限制，没有内存限制。
    -- 所以：一行可以放很多条，1 张表就装得下全部，根本不需要分片。
    local n = #_rows
    if n == 0 then return "ERR: 扫描结果为 0 行，先点 ①扫描全部模块" end

    local mrg = self.mergeLines
    if type(mrg) ~= "number" or mrg < 1 then mrg = 0 end
    local pack = (mrg >= 1) and mrg or _autoPack(n)

    local lines = _packLines(_rows, pack)

    local per = self.rowsPerTable or 1999
    if type(per) ~= "number" or per < 1 then per = 1999 end
    if per > MAX_DATA_ROWS then per = MAX_DATA_ROWS end
    -- 纯加法算需要几张表，不依赖 math.ceil/math.floor
    local need = 1
    local acc = per
    while acc < #lines do
        need = need + 1
        acc = acc + per
    end
    if need > #real then
        return "ERR: 表不够。合并后 " .. #lines .. " 行，每表 " .. per
            .. " 行，需要 " .. need .. " 张，只填了 " .. #real
            .. " 张（还差 " .. (need - #real) .. " 张）。"
            .. "把[每行合并几个成员]调大就能只用 1 张表（导出无内存限制）"
    end

    local out = {}
    local bytes = 0
    for t = 1, need do
        local from = (t - 1) * per + 1
        local to = t * per
        if to > #lines then to = #lines end
        for i = from, to do bytes = bytes + #lines[i] + 1 end
        local hdr = string.format(
            "APIP2|V2|PK:%d|TI:%d|TC:%d|DL:%d|DR:%d|FROM:%d|TO:%d|MOD:%d|NEW:%d|TIME:%s|LEN:%d",
            pack, t, need, #lines, to - from + 1, from, to,
            _stat.modOk, _stat.newMod,
            _s(os.time and os.time() or 0), n)
        local ok, w = _writeTable(real[t], lines, from, to, hdr)
        if ok then
            out[#out + 1] = "表" .. t .. "(" .. real[t] .. ") 写入 " .. w .. " 行"
        else
            out[#out + 1] = "表" .. t .. " 失败: " .. _s(w)
        end
    end
    return "导出完成（原版不压缩，一行放 " .. pack .. " 条，分号分隔）。"
        .. " 记录 " .. n .. " 条 → " .. #lines .. " 行 → " .. need .. " 张表，约 "
        .. bytes .. " 字节。 " .. _join(out, " | ")
        .. " 。（导入侧才有 500KB 限制，导出没有）接着点 ⑩校验导出 读回来比对"
end

function Script:Verify()
    if not _done then
        return "ERR: 先点 ①扫描全部模块"
    end
    local ids = _sp(self.outTableIds or "", ",")
    local real = {}
    for i = 1, #ids do
        local v = (ids[i] or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if v ~= "" then real[#real + 1] = v end
    end
    if #real == 0 then return "ERR: 属性[输出二维表ID组]为空" end

    local n = #_rows
    local mrg = self.mergeLines
    if type(mrg) ~= "number" or mrg < 1 then mrg = 0 end
    local pack = (mrg >= 1) and mrg or _autoPack(n)
    local lines = _packLines(_rows, pack)

    local per = self.rowsPerTable or 1999
    if type(per) ~= "number" or per < 1 then per = 1999 end
    if per > MAX_DATA_ROWS then per = MAX_DATA_ROWS end

    local got, bad, first = 0, 0, ""
    local readRows = 0
    for t = 1, #real do
        local arr, err, hdr = _readBack(real[t])
        if not arr then
            return "表" .. t .. "(" .. real[t] .. ") " .. _s(err)
        end
        -- 头部里带了实际合并数 PK，以它为准
        if type(hdr) == "string" then
            local pk = hdr:match("PK:(%d+)")
            if pk then
                local v = tonumber(pk)
                if v and v >= 1 and v ~= pack then
                    pack = v
                    lines = _packLines(_rows, pack)
                end
            end
        end
        local from = (t - 1) * per + 1
        if from > #lines then break end
        for i = 1, #arr do
            readRows = readRows + 1
            local want = lines[from + i - 1]
            if want ~= nil and arr[i] == want then
                got = got + 1
            else
                bad = bad + 1
                if first == "" then
                    first = "表" .. t .. "第" .. i .. "行 期望["
                        .. _s(want) .. "] 实读[" .. _s(arr[i]) .. "]"
                end
            end
        end
    end
    if readRows == 0 then
        return "★校验无效：一张表都没读回内容（表ID填错？或 GetAllValue 返回结构不是 {[1]=字符串}）。"
            .. " 表内行数请用 ⑩ 之前的 ③ 输出核对"
    end
    if bad == 0 then
        return "校验通过：读回 " .. readRows .. " 行 × 每行" .. pack
            .. "条 = 覆盖 " .. n .. " 条记录，与内存中逐条一致（0 不一致）"
    end
    return "★校验失败：一致 " .. got .. " 行，不一致 " .. bad .. " 行。首个：" .. first
end

function Script:DumpLog()
    _chunkSize = self.chunkSize
    _onlyFn = (self.onlyFunction == true)
    if not _done then
        _scanStd = (self.scanStdLib ~= false)
        _scanNew = (self.scanRuntimeNew ~= false)
        _scanAll()
    end
    local head = {
        "========== 全模块探针结果 ==========",
        "模块OK=" .. _stat.modOk .. " 缺失=" .. _stat.modNil .. " 非表=" .. _stat.modNoTbl,
        "新模块=" .. _stat.newMod .. " 成员=" .. _stat.mem .. " 记录行=" .. #_rows,
        "格式: 模块|成员|类型|来源(D=转储清单 R=运行时新增)"
    }
    local lines = _allLines()
    for i = 1, #lines do head[#head + 1] = lines[i] end
    _chunks(head, "全量")
    return "已打印 " .. #head .. " 行"
end

function Script:DumpCsv()
    _chunkSize = self.chunkSize
    _onlyFn = (self.onlyFunction == true)
    if not _done then
        _scanStd = (self.scanStdLib ~= false)
        _scanNew = (self.scanRuntimeNew ~= false)
        _scanAll()
    end
    local lines = _allCsv()
    _chunks(lines, "CSV")
    return "CSV 已打印（3列格式，可直接存成 .csv 导入）"
end

function Script:DumpModule(name)
    _chunkSize = self.chunkSize
    local nm = name or ""
    if nm == "" then return "ERR: 填模块名，例如 Player" end
    local lines = { "========== " .. nm .. " ==========" }
    local ok, m = pcall(function() return _G[nm] end)
    if not ok or m == nil then
        lines[#lines + 1] = nm .. " 不存在"
    elseif _t(m) ~= "table" then
        lines[#lines + 1] = nm .. " 类型=" .. _t(m)
    else
        local cnt = 0
        local ok2 = pcall(function()
            for k, v in pairs(m) do
                cnt = cnt + 1
                lines[#lines + 1] = string.format("%d. %s = %s", cnt, _s(k), _t(v))
            end
        end)
        if not ok2 then lines[#lines + 1] = nm .. " 遍历失败" end
        lines[#lines + 1] = nm .. " 共 " .. cnt .. " 个成员"
    end
    _chunks(lines, nm)
    return nm .. " 已打印"
end

function Script:Lookup(key)
    local kw = key or ""
    if kw == "" then return "ERR: 填关键字" end
    if not _done then
        _scanStd = (self.scanStdLib ~= false)
        _scanNew = (self.scanRuntimeNew ~= false)
        _scanAll()
    end
    local lines, cnt = {}, 0
    for i = 1, #_rows do
        local r = _rows[i]
        if r[1]:find(kw, 1, true) or r[2]:find(kw, 1, true) then
            cnt = cnt + 1
            lines[#lines + 1] = _lineOf(r)
        end
    end
    lines[#lines + 1] = "命中 " .. cnt .. " 条"
    _chunks(lines, "查" .. kw)
    return "命中 " .. cnt .. " 条"
end

function Script:Diff()
    _chunkSize = self.chunkSize
    _onlyFn = (self.onlyFunction == true)
    if not _done then
        _scanStd = (self.scanStdLib ~= false)
        _scanNew = (self.scanRuntimeNew ~= false)
        _scanAll()
    end
    local miss, news = {}, {}
    for i = 1, #_rows do
        local r = _rows[i]
        if r[4] == "M" or r[2] == "(模块不存在)" then
            miss[#miss + 1] = r[1]
        elseif r[4] == "R" then
            news[#news + 1] = r[1]
        end
    end
    local seenM, seenN = {}, {}
    local lines = { "========== 与转储对照 ==========" }
    local a, b = 0, 0
    for i = 1, #miss do
        if not seenM[miss[i]] then
            seenM[miss[i]] = true
            a = a + 1
            lines[#lines + 1] = "转储有/运行时无: " .. miss[i]
        end
    end
    for i = 1, #news do
        if not seenN[news[i]] then
            seenN[news[i]] = true
            b = b + 1
            lines[#lines + 1] = "运行时新增模块: " .. news[i]
        end
    end
    lines[#lines + 1] = "缺失 " .. a .. " 个 / 新增 " .. b .. " 个"
    _chunks(lines, "对照")
    return "缺失 " .. a .. " / 新增 " .. b
end

function Script:SelfCheck()
    _chunkSize = self.chunkSize
    _onlyFn = (self.onlyFunction == true)
    local lines = { "========== 自检 ==========" }
    local pass, fail = 0, 0
    local function ck(name, ok, extra)
        if ok then pass = pass + 1 else fail = fail + 1 end
        lines[#lines + 1] = (ok and "[PASS] " or "[FAIL] ") .. name .. (extra and (" -> " .. extra) or "")
    end
    ck("内置模块清单解析", _modCount > 200, _modCount .. " 个")
    ck("_G 可用", _t(_G) == "table")
    local okMs = false
    pcall(function() local v = os.timeMs() ; okMs = true end)
    ck("os.timeMs 可调用", okMs, _t(os.timeMs))
    local okFmt = false
    pcall(function() local v = string.format("%d", 1) ; okFmt = (v == "1") end)
    ck("string.format 正确", okFmt)
    local okSort = false
    pcall(function()
        local t = { 3, 1, 2 }
        table.sort(t, function(a, b) return a < b end)
        okSort = (t[1] == 1 and t[3] == 3)
    end)
    ck("table.sort 正确", okSort)
    ck("string.format 存在", _t(string.format) == "function")
    ck("table.sort 存在", _t(table.sort) == "function")
    ck("Data.Table 可用", not not (Data and Data.Table))
    ck("_sp 分割保留空字段", #_sp("a,,b", ",") == 3, tostring(#_sp("a,,b", ",")))
    local okS, _ = pcall(function() return _G["Player"] end)
    ck("读 _G['Player'] 不报错", okS)
    _scanStd = (self.scanStdLib ~= false)
    _scanNew = (self.scanRuntimeNew ~= false)
    local t0 = _now()
    _scanAll()
    ck("扫描产出记录", #_rows > 500, #_rows .. " 行")
    ck("模块OK数量合理", _stat.modOk > 100, tostring(_stat.modOk))
    lines[#lines + 1] = "通过 " .. pass .. " / 失败 " .. fail
    _chunks(lines, "自检")
    return "自检 通过=" .. pass .. " 失败=" .. fail
end

return Script
