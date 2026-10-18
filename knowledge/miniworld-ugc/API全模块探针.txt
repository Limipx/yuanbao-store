--[[
API 全模块反射探针 v4  ——  递归到二层 (Data.Map / Data.Table / BlockEdit.* ...)
====================================================================
导出内容两条线：
  L1  模块:函数          Game.ShowMsgBox
  L2  模块.成员:函数      Data.Map.GetMapValue / Data.Table:InsertValue
另记录 L0=模块本体、LS=二层子表本体(Data.Map / Data.Table)

铁律(来自实机, 别再犯):
  * 以【运行时二维表实测结果】为准, 转储只用于查"有没有这个成员"
  * 导出：只有 2000 行限制, 【没有内存限制】 -> 只用 1 张表, 一行放多条(pack)
  * 导入：500KB 内存 + 2000 行
  * Data.Table 实机签名(来自建筑文件生成器3.1)：
        Data.Table:Clear(tableId, nil)
        Data.Table:InsertValue(tableId, nil, 一个字符串)      <- 只传【一个】
        Data.Table:GetAllValue(tableId, nil) -> allRows[i][1]  <- 第1行是头部
    多传参数会把行号塞进第1列, 不报错、静默错位
  * 每行拼接常量【行尾必须有 ..】否则两段并成一个, gmatch 少拆(静默丢数据)
====================================================================
记录格式:  路径|类型|层级|来源
  层级  L0=模块  L1=一层成员  L2=二层成员  LS=二层子表本体
  来源  D=转储里有  R=运行时新增(转储没记)
]]

local Script = {}

local DUMP_MODS =
    "ABSOLUTECAMPTYPE Ability AbsoluteCampType Action ActionType Actor ActorBodyEffect Aggro AliveState AnimMode Area AreaCloneType AreaFillType AreaSimilarity AutoSprinklerBlock " ..
    "AvtPart BACKPACK_TYPE Backpack BackpackBeginIndex BackpackComponent BackpackType BeaconClampType BeaconMapType BeginType Biome BiomeType Block BlockAttr BlockEdit BlockId " ..
    "BlockLimits BlockStateEdit BlockStateType BlockStatus Blueprint Bool BoxRefresh BtreeRangeType Buff CREATUREATTR CameraEditState CameraModel CameraRotate Chat CheckList Chest " ..
    "ClientPositive CloudSever CmpProPermission CmpUIPermission Collider Color ColorGrandient CommonBlockPlace ComponentType ComponentUIPermissions ComponentUIStyle CraftingEdit " ..
    "CreatureAttr CreatureMotion Cropblock CustomData CustomModType CustomMsg CustomUI Data DeviceType DoExplodeStatus DoHarmStatus Door DropItem DropMode Easing Effect ElementAttr " ..
    "ElementType Entity EntityType Enum EquipEdit EquipSlotType ErrorCode EventDate ExplodeDmgType FaceDir FaceType Feed Fight FoodEdit FurnaceEdit FurnaceType GRAPHICS GSoundType Game " ..
    "GameActorType GameEffect GameObject GameRule GameSetting GamemakerRule GenerateBlock GoBackType Graphics GraphicsType GridAttr GroupView GroupWeatherType Grow GunAction " ..
    "GunActionBan GunAttr GunDamageType GunEdit GunFireType GunSpreadType GunState HURTTYPE HorizontalOffset HumanBodyAnchorId HurtType ITEMATTR InnerPopUpview Item ItemAbility ItemAttr " ..
    "ItemEdit ItemEffectType KeyCode LaunchProjectileStatus LayingEggType LightingFurniture LineAnimation LinearTransformation Listen Log LogLevel LuaPanda MODATTRIB_TYPE MapMarkType " ..
    "MapShopOrder MatchMode Material Mini MiniCurrency MiniMapMarkType MiniShopData MiniShopDetail MiniShopPage MiniShopWarehouse MiniViewSecondTab Mob MobType Mod ModAttribType Model " ..
    "ModelAction Monster MonsterEdit MoveType NPCShop Number ObjType Object ObjectEvent ObjectLib ObsBluePrintStatus OfficeUtils OldGunEdit PLAYERATTR PackEdit PathPoint Physics " ..
    "PickupActionType Picture PixelUnits Player PlayerAttr PlayerBodyUIHight PlayerController PlayerMotion PlayerNameType PlayerRelations PlayerType Prefab ProgressImg ProgressVal " ..
    "Projectile ProjectileEdit RandomAddStatus RayDetectType RecoverStatus RelativeCampType RelativeType Reproduction Ride Roadblock Role RoleAttr RoleMotion RolePickupType Rotation " ..
    "Scale SkeletonPoint SkyBox SkyBoxFilter SkyboxAttr SkyboxAttrNoTime SkyboxColor SkyboxFilter SkyboxFilterSwitch SkyboxMap SkyboxParticle SkyboxSwitch SkyboxTime SortType Sound " ..
    "Status StatusEdit StorageType String SurviveComponent Tag Tame Task TaskAnimType TaskChainType TaskDialogType TaskEvent TaskPassType TaskType TaskUIType Team TeamAttr TeamResults " ..
    "TerrainType ThrowItem Timer ToolEdit TouchState Trigger TriggerEvent TurnFaceDir UIAttr UIProjectSet UIScollDir UiElement UiState UseEdit VDistanceRange VIEWPORTTYPE VarType Vec2 " ..
    "Vec3 VerticalOffset ViedoPlayMode ViewPortType Villager WeatherGroup WeatherType WorkStage WorkeStage World WorldContainer WorldRuleBaseSetting WorldRuleCloudSetting " ..
    "WorldRuleFightSetting WorldRuleHUDUI WorldRuleRebirth WorldRuleSceneUI WorldRuleSound WorldRuleStartMode WorldType _G __info bit coroutine debug io json math os package string " ..
    "table threadpool "

local DUMP_SUBS =
    "Aggro.CampRelation Aggro.SearchRangeType AutoSprinklerBlock.State BackpackComponent.InteractMode BlockEdit.BlockFlowType BlockEdit.BuiltInType BlockEdit.ColliderBoxType " ..
    "BlockEdit.ColliderModeSelect BlockEdit.ColliderShape BlockEdit.ColliderState BlockEdit.ColliderType BlockEdit.CoverNeighborType BlockEdit.DrawType BlockEdit.GravityEffectType " ..
    "BlockEdit.InteractSwitch BlockEdit.InteractType BlockEdit.LodType BlockEdit.MineToolType BlockEdit.PhyCollideType BlockEdit.PlaceDirType BlockEdit.PushFlagType BlockEdit.ToolLevel " ..
    "BlockStateEdit.CustomColliderState BlockStateEdit.SubMeshDataType BoxRefresh.RefreshNumType BoxRefresh.RefreshType Chest.MaxGridCountType Collider.ColliderType " ..
    "Collider.NoPhyscColliderShap Collider.PhysicColliderShape CommonBlockPlace.PlaceTypeGroup CraftingEdit.RequirementToolsEnum CraftingEdit.SubTypeEnum CraftingEdit.TypeEnum " ..
    "Cropblock.AbundantType Cropblock.CropState Cropblock.CropType Cropblock.HarvestType Cropblock.WetAffectType Data.Array Data.Map Data.Table DoExplodeStatus.DestroyBlock " ..
    "DoExplodeStatus.ExplodeRangeType DoExplodeStatus.HarmType DoHarmStatus.AttackType DoHarmStatus.HarmInherit DoHarmStatus.HarmType Door.ControlModeType EquipEdit.AnchorType " ..
    "EquipEdit.PartModelType EquipEdit.slotType Feed.BubbleType Feed.FeedReactType Feed.RewardItemType Fight.AnimationName Fight.AttackMode Fight.ColliderShape Fight.NoPhyscColliderShap " ..
    "Fight.Team FoodEdit.BarbecueType FoodEdit.FoodTIngredientsType FoodEdit.Time FurnaceEdit.FurnaceType GenerateBlock.GenerateNumType GenerateBlock.RandomType Grow.BubbleType " ..
    "GunEdit.AutoFireType GunEdit.DamageType GunEdit.FireType GunEdit.GunHandSlot GunEdit.GunType GunEdit.PointLooksType GunEdit.ReloadType GunEdit.SightLooksType GunEdit.SightMode " ..
    "GunEdit.SightType GunEdit.SpreadSet GunEdit.SpreadType GunEdit.TrajectoryType GunEdit.TweenFuncName ItemEdit.DropItemEnum ItemEdit.ProductType ItemEdit.QualityLevel " ..
    "ItemEdit.UseType LaunchProjectileStatus.LaunchDir LaunchProjectileStatus.LaunchDirType LaunchProjectileStatus.LaunchType LayingEggType.__info LightingFurniture.ControlMode " ..
    "Mini.Array Mini.EventType Model.AvatarAnchorType Model.GunAnchorType Model.PartType MonsterEdit.Type NPCShop.CostType NPCShop.DialogScene NPCShop.GoodsQuality NPCShop.PayType " ..
    "NPCShop.RefreshType NPCShop.ShopType NPCShop.TagMatchMode OldGunEdit.BulletType OldGunEdit.FireType OldGunEdit.GunType PackEdit.PackType Physics.ColliderShape Physics.LayerType " ..
    "Physics.PhysicsType PlayerController.CrosshairType PlayerController.Mode PlayerController.MoveLimit PlayerController.RoteLimit PlayerController.ViewMove PlayerController.ViewType " ..
    "PlayerController.ZoomMode Projectile.HitProcess Projectile.HitType Projectile.HurtType Projectile.TrailType ProjectileEdit.AccumulatorType ProjectileEdit.AttackType " ..
    "ProjectileEdit.DamageType ProjectileEdit.PhysicsMaterialType ProjectileEdit.TriggerCondition RandomAddStatus.triggerTimeEnumType RecoverStatus.AttrType RecoverStatus.ModifyType " ..
    "Reproduction.ReproductionType Ride.RideMobType Ride.RidingConditionType Ride.RidingHpType Ride.RidingItemPermissionType Roadblock.ColliderType Sound.playModeType Sound.startType " ..
    "StatusEdit.priority StatusEdit.triggerTimeEnumType StatusEdit.type SurviveComponent.AddAttrType Tame.TameMobType Tame.TameType ToolEdit.ToolType Trigger.Actor Trigger.Area " ..
    "Trigger.ArrayTmp Trigger.Backpack Trigger.Block Trigger.Buff Trigger.Component Trigger.CustomUI Trigger.GameObject Trigger.Graphics Trigger.Item Trigger.KvMap Trigger.Math " ..
    "Trigger.Monster Trigger.Player Trigger.World UIProjectSet.bgColorEnum UIProjectSet.systemLevelEnum UseEdit.ChargeType UseEdit.CostType UseEdit.RangeType UseEdit.SkillType " ..
    "UseEdit.TargetTeam Villager.AvatarAnchorType Villager.GunAnchorType Villager.PartType Villager.ProfessionType WorldRuleBaseSetting.WeatherType WorldRuleCloudSetting.GameModeType " ..
    "WorldRuleFightSetting.attackModeType WorldRuleFightSetting.defenseFormulaType WorldRuleHUDUI.MapIconClickType WorldRuleHUDUI.MapPlayerIconType WorldRuleHUDUI.MapPlayerShowType " ..
    "WorldRuleRebirth.deathDropModeType WorldRuleRebirth.rebirthCostModeType WorldRuleRebirth.rebirthModeType WorldRuleSceneUI.displayNameType WorldRuleSound.backgroundMusicType " ..
    "WorldRuleSound.ratioPec WorldRuleStartMode.displayNameType WorldRuleStartMode.levelModeTypeEnum WorldRuleStartMode.playerLimitTypeEnum __info.Oviparous __info.Viviparous "

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
        maxValue = 60,
        tips = "0=自动算成刚好1张表装下; 多条用;拼成一行",
    },
    maxDepth = {
        type = Mini.Number,
        displayName = "递归深度(2=探到Data.Map这层)",
        defaultValue = 2,
        minValue = 1,
        maxValue = 3,
        tips = "2足够: 覆盖 模块.成员:函数",
    },
    scanScope = {
        type = Mini.Number,
        displayName = "扫描范围(0=表+函数,1=全部,2=仅函数)",
        defaultValue = 0,
        minValue = 0,
        maxValue = 2,
        tips = "0=表与函数(默认); 1=连枚举常量一起导; 2=只导函数(最精简)",
    },
    memberCap = {
        type = Mini.Number,
        displayName = "每个表最多取多少成员",
        defaultValue = 500,
        minValue = 50,
        maxValue = 2000,
        tips = "防止超大表把扫描卡死",
    },
    blockBytes = {
        type = Mini.Number,
        displayName = "分块打印字节数",
        defaultValue = 500,
        minValue = 50,
        maxValue = 4000,
        tips = "结果只能靠print看, 无io",
    },
    printMax = {
        type = Mini.Number,
        displayName = "最多打印多少条",
        defaultValue = 400,
        minValue = 20,
        maxValue = 5000,
        tips = "防刷屏; 导出不受此限",
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
        displayName = "⑤打印指定模块(含二层)",
        params = { "模块名", Mini.String },
    },
    FindMember = {
        returnType = Mini.String,
        displayName = "⑥查找成员(关键字)",
        params = { "关键字", Mini.String },
    },
    DumpEvents = {
        returnType = Mini.String,
        displayName = "⑦打印事件表",
        params = {},
    },
    DiffDump = {
        returnType = Mini.String,
        displayName = "⑧与转储对照(缺/新增)",
        params = {},
    },
    EnvInfo = {
        returnType = Mini.String,
        displayName = "⑨环境自检",
        params = {},
    },
}

--------------------------------------------------------------------
-- 基础工具
--------------------------------------------------------------------
local _recs = {}          -- 结果: 每条 "路径|类型|层级|来源"
local _n = 0
local _stat = {}
local _setMods = {}       -- 转储模块名集合
local _setSubs = {}       -- 转储二层子表路径集合

local function _kind(v)
    local t = type(v)
    if t == "table" or t == "function" or t == "string" or t == "number"
       or t == "boolean" or t == "userdata" or t == "thread" then
        return t
    end
    return "other"
end

local function _words(s)
    local n = 0
    for _ in string.gmatch(s, "%S+") do n = n + 1 end
    return n
end

local function _fill(set, s)
    local n = 0
    for w in string.gmatch(s, "%S+") do set[w] = true n = n + 1 end
    return n
end

local function _keyname(k)
    if type(k) == "string" then return k end
    local ok, r = pcall(tostring, k)
    if ok and type(r) == "string" then return r end
    return "?"
end

-- 安全取成员列表: 返回数组 {{k,v}...}
local function _members(t, cap)
    local out, cnt = {}, 0
    local ok = pcall(function()
        for k, v in pairs(t) do
            cnt = cnt + 1
            if cnt > cap then break end
            out[cnt] = { k, v }
        end
    end)
    return out, ok, cnt
end

local function _push(path, kind, lv, src)
    _n = _n + 1
    _recs[_n] = path .. "|" .. kind .. "|" .. lv .. "|" .. src
end

local function _say(s)
    print(s)
end

-- 分块打印
local BLOCK = {}
local function _emit(s)
    BLOCK[#BLOCK + 1] = s
end
local function _flush(blockBytes)
    local buf, total = "", 0
    local idx = 0
    for i = 1, #BLOCK do
        local one = BLOCK[i] .. "\n"
        if #buf + #one > blockBytes then
            idx = idx + 1
            print("[块" .. idx .. "] " .. buf)
            total = total + #buf
            buf = one
        else
            buf = buf .. one
        end
    end
    if #buf > 0 then
        idx = idx + 1
        print("[块" .. idx .. "] " .. buf)
        total = total + #buf
    end
    print("=== 共" .. idx .. "块 / " .. total .. "字节 ===")
    BLOCK = {}
    return idx, total
end

--------------------------------------------------------------------
-- ① 扫描
--------------------------------------------------------------------
function Script:ScanAll()
    _recs = {}
    _n = 0
    _stat = { modOk = 0, modMiss = 0, l0 = 0, l1 = 0, l2 = 0,
              ls = 0, newMod = 0, newMem = 0, subMiss = 0 }

    if not _setMods.__loaded then
        _stat.dumpMods = _fill(_setMods, DUMP_MODS)
        _stat.dumpSubs = _fill(_setSubs, DUMP_SUBS)
        _setMods.__loaded = true
    end

    local depth  = self.maxDepth or 2
    if depth < 1 then depth = 1 end
    local scope  = self.scanScope or 0
    local cap    = self.memberCap or 500
    if cap < 50 then cap = 50 end

    local function want(kind)
        if scope == 1 then return true end
        if scope == 2 then return kind == "function" end
        return kind == "table" or kind == "function"
    end

    -- 收集模块名: 转储 ∪ 运行时 _G 里的 table
    local names, seen = {}, {}
    for w in string.gmatch(DUMP_MODS, "%S+") do
        if not seen[w] then seen[w] = true names[#names + 1] = w end
    end
    local SKIP = { _G = true, package = true, _ENV = true, arg = true,
                   Script = true, utf8 = true }
    local okG = pcall(function()
        for k, v in pairs(_G) do
            if type(v) == "table" and not SKIP[_keyname(k)] then
                local nm = _keyname(k)
                if not seen[nm] then
                    seen[nm] = true
                    names[#names + 1] = nm
                    _stat.newMod = _stat.newMod + 1
                end
            end
        end
    end)
    _stat.rtPairs = tostring(okG)

    local seenTab = {}
    local t0 = os.timeMs and os.timeMs() or 0

    for i = 1, #names do
        local mname = names[i]
        local ok, m = pcall(function() return _G[mname] end)
        local t = (ok and type(m) == "table") and m or nil
        if not t then
            if _setMods[mname] then
                _stat.modMiss = _stat.modMiss + 1
                _push(mname, "nil", "L0", "X")
            end
        else
            _stat.modOk = _stat.modOk + 1
            local src = _setMods[mname] and "D" or "R"
            _push(mname, "table", "L0", src)
            _stat.l0 = _stat.l0 + 1

            local list = _members(t, cap)
            for j = 1, #list do
                local k2, v2 = list[j][1], list[j][2]
                local kn = _keyname(k2)
                local kd = _kind(v2)
                local path2 = mname .. "." .. kn
                if want(kd) then
                    _push(path2, kd, "L1", src and "D" or "R")
                    _stat.l1 = _stat.l1 + 1
                end
                -- 二层
                if depth >= 2 and kd == "table" then
                    local addr = tostring(v2)
                    if not seenTab[addr] then
                        seenTab[addr] = true
                        if _setSubs[path2] then
                            _push(path2, "table", "LS", "D")
                            _stat.ls = _stat.ls + 1
                        end
                        local l2 = _members(v2, cap)
                        for q = 1, #l2 do
                            local k3, v3 = l2[q][1], l2[q][2]
                            local kd3 = _kind(v3)
                            if want(kd3) then
                                local p3 = path2 .. "." .. _keyname(k3)
                                _push(p3, kd3, "L2", _setSubs[path2] and "D" or "R")
                                _stat.l2 = _stat.l2 + 1
                            end
                        end
                    end
                end
            end
        end
    end

    local ms = (os.timeMs and os.timeMs() or 0) - t0
    _say("[扫描] 模块在=" .. _stat.modOk .. " 缺失=" .. _stat.modMiss
         .. " 新增=" .. _stat.newMod)
    _say("[扫描] L1=" .. _stat.l1 .. " L2=" .. _stat.l2 .. " 子表=" .. _stat.ls)
    _say("[扫描] 总记录=" .. _n .. " 耗时=" .. ms .. "ms _G遍历=" .. _stat.rtPairs)
    return "总记录 " .. _n .. " 条 (L1=" .. _stat.l1 .. " L2=" .. _stat.l2 .. ")"
end

--------------------------------------------------------------------
-- ② 导出 (只用 1 张表, 一行放多条)
--------------------------------------------------------------------
local function _firstId(s)
    if not s or s == "" then return nil end
    for w in string.gmatch(s, "[^,;%s]+") do return w end
    return nil
end

local function _packOf(n, want)
    if want and want > 0 then return want end
    local p = 1
    while math.ceil(n / p) > 1999 do p = p + 1 end
    return p
end

local function _lineOf(from, pack)
    local buf = nil
    local last = from + pack - 1
    if last > _n then last = _n end
    for i = from, last do
        buf = buf and (buf .. ";" .. _recs[i]) or _recs[i]
    end
    return buf
end

function Script:ExportTable()
    if _n == 0 then return "ERR: 请先点①扫描" end
    local id = _firstId(self.tableIdsText)
    if not id then return "ERR: 未填输出二维表ID(属性tableIdsText)" end

    local pack = _packOf(_n, self.packSize)
    local rows = math.ceil(_n / pack)
    if rows > 1999 then
        return "ERR: 需要" .. rows .. "行但表上限1999 -> 把'每行合并几条'调到>="
               .. _packOf(_n, 0) .. " (当前pack=" .. pack .. ")"
    end

    local head = "APIP2|V1|PK:" .. pack .. "|TC:" .. _n
                 .. "|MOD:" .. (_stat.modOk or 0)
                 .. "|L1:" .. (_stat.l1 or 0)
                 .. "|L2:" .. (_stat.l2 or 0)
                 .. "|LS:" .. (_stat.ls or 0)
                 .. "|LEN:" .. rows

    local ok, err = pcall(function()
        Data.Table:Clear(id, nil)
        Data.Table:InsertValue(id, nil, head)
    end)
    if not ok then return "ERR: 写头部失败 " .. tostring(err) end

    local wrote = 0
    for r = 1, rows do
        local from = (r - 1) * pack + 1
        local ok2, err2 = pcall(function()
            Data.Table:InsertValue(id, nil, _lineOf(from, pack))
        end)
        if not ok2 then
            return "ERR: 写第" .. r .. "行失败 " .. tostring(err2)
        end
        wrote = wrote + 1
    end
    _stat.exported = { id = id, pack = pack, rows = rows }
    return "OK: " .. _n .. "条 -> pack=" .. pack .. " -> " .. rows
           .. "行(含头部" .. (rows + 1) .. ") 表=" .. tostring(id)
end

--------------------------------------------------------------------
-- ③ 校验导出
--------------------------------------------------------------------
function Script:VerifyExport()
    local id = _firstId(self.tableIdsText)
    if not id then return "ERR: 未填输出二维表ID" end
    local all = nil
    local ok, err = pcall(function() return Data.Table:GetAllValue(id, nil) end)
    if not ok then return "ERR: GetAllValue失败 " .. tostring(err) end
    all = err
    if type(all) ~= "table" or #all == 0 then
        return "★校验无效: 读回空(表ID错?没导出?) type=" .. type(all)
    end

    local head = all[1] and all[1][1] or nil
    if type(head) ~= "string" or string.sub(head, 1, 6) ~= "APIP2|" then
        return "★校验无效: 第1行不是APIP2头部 -> " .. tostring(head)
    end
    local pk = tonumber(string.match(head, "PK:(%d+)")) or 1
    local tc = tonumber(string.match(head, "TC:(%d+)")) or 0

    local got, bad = 0, 0
    local firstBad = nil
    for i = 2, #all do
        local row = all[i] and all[i][1] or nil
        if type(row) ~= "string" then
            bad = bad + 1
        else
            local pos = 1
            for w in string.gmatch(row, "[^;]+") do
                got = got + 1
                local want = _recs[got]
                if want ~= w then
                    bad = bad + 1
                    if not firstBad then
                        firstBad = "第" .. i .. "行第" .. pos .. "条: 读回["
                                   .. tostring(w) .. "] 期望[" .. tostring(want) .. "]"
                    end
                end
                pos = pos + 1
            end
        end
    end
    if got == 0 then
        return "★校验无效: 读回" .. (#all - 1) .. "行但0条内容(拆包失败?)"
    end
    if bad > 0 then
        return "★校验失败: 读回" .. got .. "条, 不一致" .. bad
               .. " 首个=" .. tostring(firstBad)
    end
    if tc > 0 and got ~= tc then
        return "★数量不符: 头部TC=" .. tc .. " 实读" .. got
    end
    return "PASS: 读回" .. (#all - 1) .. "行 x pack" .. pk .. " = " .. got
           .. "条, 逐条一致(0不一致)"
end

--------------------------------------------------------------------
-- ④ 分块打印
--------------------------------------------------------------------
function Script:DumpBlocks()
    if _n == 0 then return "ERR: 请先点①扫描" end
    local lim = self.printMax or 400
    if lim > _n then lim = _n end
    _emit("===== 扫描结果 前" .. lim .. " / 共" .. _n .. " =====")
    for i = 1, lim do _emit(i .. " " .. _recs[i]) end
    local a, b = _flush(self.blockBytes or 500)
    return "已打印 " .. lim .. " 条 / " .. a .. "块 / " .. b .. "字节"
end

--------------------------------------------------------------------
-- ⑤ 指定模块  ⑥ 查找  ⑦ 事件  ⑧ 对照  ⑨ 自检
--------------------------------------------------------------------
function Script:ShowModule(name)
    if _n == 0 then return "ERR: 请先点①扫描" end
    if not name or name == "" then return "ERR: 填模块名, 如 Data" end
    local hit = 0
    _emit("===== 模块 " .. name .. " =====")
    for i = 1, _n do
        local r = _recs[i]
        local p = string.match(r, "^([^|]+)")
        if p == name or string.sub(p, 1, #name + 1) == name .. "." then
            _emit(r); hit = hit + 1
        end
    end
    _flush(self.blockBytes or 500)
    return "命中 " .. hit .. " 条"
end

function Script:FindMember(key)
    if _n == 0 then return "ERR: 请先点①扫描" end
    if not key or key == "" then return "ERR: 填关键字, 如 Map" end
    local hit, lim = 0, self.printMax or 400
    _emit("===== 含 " .. key .. " =====")
    for i = 1, _n do
        if string.find(_recs[i], key, 1, true) then
            if hit < lim then _emit(_recs[i]) end
            hit = hit + 1
        end
    end
    _flush(self.blockBytes or 500)
    return "命中 " .. hit .. " 条"
end

function Script:DumpEvents()
    _emit("===== 事件表 =====")
    local cnt = 0
    local list = { "TriggerEvent", "ObjectEvent", "ActorEvent", "PlayerEvent",
                   "BlockEvent", "ItemEvent", "UIEvent", "MonsterEvent" }
    for i = 1, #list do
        local nm = list[i]
        local t = nil
        pcall(function() t = _G[nm] end)
        if type(t) ~= "table" then
            _emit("-- " .. nm .. " 不存在")
        else
            local ms = _members(t, 2000)
            _emit("-- " .. nm .. " (" .. #ms .. ")")
            for j = 1, #ms do
                _emit("   " .. nm .. "." .. _keyname(ms[j][1])
                      .. " = " .. _kind(ms[j][2]))
                cnt = cnt + 1
            end
        end
    end
    _flush(self.blockBytes or 500)
    return "事件成员 " .. cnt .. " 个"
end

function Script:DiffDump()
    if _n == 0 then return "ERR: 请先点①扫描" end
    if not _setMods.__loaded then
        _fill(_setMods, DUMP_MODS); _fill(_setSubs, DUMP_SUBS)
        _setMods.__loaded = true
    end
    local miss, newm = {}, {}
    for i = 1, _n do
        local r = _recs[i]
        local lv = string.match(r, "|(%w+)|%w+$")
        if lv == "L0" then
            local p = string.match(r, "^([^|]+)")
            local src = string.match(r, "|(%w+)$")
            if src == "X" then miss[#miss + 1] = p
            elseif src == "R" then newm[#newm + 1] = p end
        end
    end
    _emit("===== 与转储对照 =====")
    _emit("[转储] 模块" .. _words(DUMP_MODS) .. " 二层子表" .. _words(DUMP_SUBS))
    _emit("[实机缺失] " .. #miss)
    for i = 1, #miss do if i <= 60 then _emit("  - " .. miss[i]) end end
    _emit("[运行时新增] " .. #newm)
    for i = 1, #newm do if i <= 60 then _emit("  + " .. newm[i]) end end
    _flush(self.blockBytes or 500)
    return "缺失 " .. #miss .. " / 新增 " .. #newm
end

function Script:EnvInfo()
    local pass, fail = 0, 0
    local function chk(cond, msg)
        if cond then pass = pass + 1 _emit("PASS " .. msg)
        else fail = fail + 1 _emit("FAIL " .. msg) end
    end
    if not _setMods.__loaded then
        _fill(_setMods, DUMP_MODS); _fill(_setSubs, DUMP_SUBS)
        _setMods.__loaded = true
    end
    _emit("===== ⑨ 自检 =====")
    chk(_VERSION == "Lua 5.1" or _VERSION ~= nil, "_VERSION=" .. tostring(_VERSION))
    chk(type(Script.propertys) == "table", "propertys 是表")
    chk(type(Script.openFnArgs) == "table", "openFnArgs 是表")
    local nf = 0
    for k, v in pairs(Script) do
        if type(v) == "table" and k ~= "propertys" and k ~= "openFnArgs" then
            nf = nf + 1
        end
    end
    chk(nf == 0, "非函数字段仅 propertys/openFnArgs (多出" .. nf .. ")")
    chk(_words(DUMP_MODS) > 250, "内置模块名 " .. _words(DUMP_MODS) .. " (>300)")
    chk(_words(DUMP_SUBS) > 100, "内置二层子表 " .. _words(DUMP_SUBS) .. " (>100)")
    chk(type(os.timeMs) == "function", "os.timeMs 可调用")
    if type(os.clock) == "function" then
        _emit("NOTE os.clock 存在(沙盒5.5); 真机5.1无此函数, 用了必崩")
    else
        _emit("PASS os.clock 不存在(与真机5.1一致)")
    end
    chk(type(print) == "function", "print 可用")
    chk(type(pairs) == "function", "pairs 可用")
    chk(_G ~= nil, "_G 可读")
    -- 二层是否真探到
    if _n == 0 then
        _emit("SKIP 二层检查(还没点①扫描)")
    else
        local has2, hasLS = 0, 0
        for i = 1, _n do
            if string.find(_recs[i], "|L2|", 1, true) then has2 = has2 + 1 end
            if string.find(_recs[i], "|LS|", 1, true) then hasLS = hasLS + 1 end
        end
        chk(has2 > 0, "探到二层成员 " .. has2 .. " 条")
        chk(hasLS > 0, "探到二层子表 " .. hasLS .. " 个")
        chk(_n == #_recs, "记录数连续 n=" .. _n .. " #=" .. #_recs)
        chk(_packOf(_n, 0) >= 1, "自动pack=" .. _packOf(_n, 0)
            .. " -> " .. math.ceil(_n / _packOf(_n, 0)) .. "行(<=1999)")
    end
    _emit("---- " .. pass .. " 通过 / " .. fail .. " 失败 ----")
    _flush(self.blockBytes or 500)
    return pass .. " 通过 / " .. fail .. " 失败"
end

--------------------------------------------------------------------
return Script
