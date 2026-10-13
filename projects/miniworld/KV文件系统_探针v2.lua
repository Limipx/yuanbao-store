-- ============================================================
-- KV 接口探针 v2（决定性版）
-- 目的：查清当前运行时到底有哪些 KV 读写函数、真实签名与返回
-- 用法：
--   1) 单独新建脚本组件导入，加载后自动打印一遍
--   2) 或整段追加到 KV文件系统_房间个人版v2 / 云服版v2 末尾再导入
--      （不会覆盖 propertys / openFunctions / openFnArgs）
--   3) 想在运行时带 varId 复测：触发器调用 Script:Probe2("v7e9xxx", 0)
-- ============================================================

local function P(s) print("[KVPROBE2] " .. tostring(s)) end

local function T(x)
  if x == nil then return "nil" end
  local t = type(x)
  if t == "string" then
    local n = #x
    local vis = x
    if n > 48 then vis = x:sub(1, 48) .. "..." end
    -- 不可打印字节打点，避免日志被截断
    vis = vis:gsub("[%c%z\128-\255]", ".")
    return "string(" .. n .. ")[" .. vis .. "]"
  elseif t == "number" then return "number(" .. tostring(x) .. ")"
  elseif t == "boolean" then return tostring(x)
  elseif t == "table" then return "table"
  elseif t == "function" then return "function"
  else return t end
end

local function resolve(path)
  local cur = _G
  for seg in path:gmatch("[^%.]+") do
    if type(cur) ~= "table" then return nil end
    cur = cur[seg]
  end
  return cur
end

local function enum(label, obj)
  if type(obj) ~= "table" then P(label .. " | 不存在") return end
  local ks = {}
  for k, v in pairs(obj) do ks[#ks + 1] = tostring(k) .. ":" .. type(v) end
  table.sort(ks)
  P(label .. " | table  共 " .. #ks .. " 项")
  for i = 1, #ks do P("   " .. ks[i]) end
end

local function call(label, obj, m, ...)
  if type(obj) ~= "table" or type(obj[m]) ~= "function" then
    P("   " .. label .. " | 函数不存在")
    return nil
  end
  local pack = { pcall(obj[m], obj, ...) }
  local ok = pack[1]
  local out = "   " .. label .. " | ok=" .. tostring(ok)
  local n = #pack
  out = out .. " 返回" .. (n - 1) .. "个"
  for i = 2, math.min(n, 7) do out = out .. " | " .. T(pack[i]) end
  P(out)
  if not ok then return nil end
  return pack[2], pack[3], pack[4]
end

-- ---------------- 1. 全局模块存在性 ----------------
local MODS = { "Data", "Data.Map", "Data.Array", "Data.Table",
  "Trigger", "Trigger.KvMap", "CloudSever", "CloudData", "CloudService",
  "KV", "Storage", "ErrorCode", "Mini", "Player", "World",
  "CustomUI", "Timer", "TriggerEvent", "Script" }

-- ---------------- 2. 属性 / varId ----------------
local function dumpProps(self)
  local sp = type(Script) == "table" and Script.propertys or nil
  if type(sp) ~= "table" then P("propertys 不可用") return {} end
  local ids = {}
  for _, p in ipairs(sp) do
    if type(p) == "table" and p.key then
      local v = (type(self) == "table") and self[p.key] or nil
      P("   prop " .. tostring(p.key) .. " | " .. T(v))
      if type(v) == "string" and v:sub(1, 1) == "v" then ids[#ids + 1] = v end
    end
  end
  return ids
end

local function run(varId, playerId)
  P("========== 探针v2开始 varId=" .. T(varId) .. " playerId=" .. T(playerId) .. " ==========")

  P("---- 1. 全局模块 ----")
  for _, n in ipairs(MODS) do
    P("   " .. n .. " | " .. T(resolve(n)))
  end

  P("---- 2. 方法清单 ----")
  enum("Data", resolve("Data"))
  enum("Data.Map", resolve("Data.Map"))
  enum("Data.Array", resolve("Data.Array"))
  enum("Data.Table", resolve("Data.Table"))
  enum("Trigger.KvMap", resolve("Trigger.KvMap"))
  enum("CloudSever", resolve("CloudSever"))

  P("---- 3. ErrorCode 常量 ----")
  enum("ErrorCode", resolve("ErrorCode"))

  P("---- 4. 属性与 varId ----")
  local ids = dumpProps(self)
  if (varId == nil or varId == "") and ids[1] then varId = ids[1] end
  P("   使用 varId = " .. T(varId))

  if not varId then
    P("!! 未拿到 varId，后续往返测试跳过。请调用 Script:Probe2('v你的表ID',0)")
    return
  end

  local DM = resolve("Data.Map")
  local KM = resolve("Trigger.KvMap")

  P("---- 5. 存在性速判（关键） ----")
  local chk = {
    { "Data.Map.GetMapValue", DM, "GetMapValue" },
    { "Data.Map.SetMapValue", DM, "SetMapValue" },
    { "Data.Map.RemoveMapValue", DM, "RemoveMapValue" },
    { "Data.Map.GetValueAndBlock", DM, "GetValueAndBlock" },
    { "Data.Map.SetValueAndBlock", DM, "SetValueAndBlock" },
    { "Data.Map.RemoveValueAndBlock", DM, "RemoveValueAndBlock" },
    { "Data.Map.GetValueAndCallBack", DM, "GetValueAndCallBack" },
    { "Data.Map.SetValueAndCallBack", DM, "SetValueAndCallBack" },
    { "Data.Map.UpdateValueAndCallback", DM, "UpdateValueAndCallback" },
    { "Data.Map.GetAllValue", DM, "GetAllValue" },
    { "Data.Map.ClearData", DM, "ClearData" },
    { "Data.Map.SetUserDataValue", DM, "SetUserDataValue" },
    { "Data.Map.GetUserDataValue", DM, "GetUserDataValue" },
    { "Trigger.KvMap.GetDataListBykey", KM, "GetDataListBykey" },
    { "Trigger.KvMap.SetDataListBykey", KM, "SetDataListBykey" },
    { "Trigger.KvMap.RemoveDataListBykey", KM, "RemoveDataListBykey" },
  }
  for _, c in ipairs(chk) do
    local o = c[2]
    local st = (type(o) == "table" and type(o[c[3]]) == "function") and "有" or "无"
    P("   " .. c[1] .. " | " .. st)
  end

  P("---- 6. 往返测试 ----")
  local K33 = "p2" .. string.rep("a", 31)          -- 33 字节
  local VBIN = "AB\0\1\255CD"                       -- 含不可打印字节
  P("   key=" .. T(K33) .. "  value=" .. T(VBIN))

  -- 6.1 Data.Map 阻塞版
  if type(DM) == "table" and type(DM.SetValueAndBlock) == "function" then
    P("  [A] Data.Map 阻塞版")
    call("SetValueAndBlock", DM, "SetValueAndBlock", varId, playerId, K33, VBIN)
    local c1, _, v1 = call("GetValueAndBlock", DM, "GetValueAndBlock", varId, playerId, K33)
    P("     往返一致 = " .. tostring(v1 == VBIN) .. "  code=" .. T(c1))
    call("RemoveValueAndBlock", DM, "RemoveValueAndBlock", varId, playerId, K33)
    local c2, _, v2 = call("GetValueAndBlock(删除后)", DM, "GetValueAndBlock", varId, playerId, K33)
    P("     删除后 code=" .. T(c2) .. " val=" .. T(v2))
  else
    P("  [A] Data.Map 阻塞版不可用")
  end

  -- 6.2 Data.Map 回调版（看回调是否同步触发）
  if type(DM) == "table" and type(DM.SetValueAndCallBack) == "function" then
    P("  [B] Data.Map 回调版")
    local got = nil
    local okb, br = pcall(DM.SetValueAndCallBack, DM, varId, playerId, K33, VBIN,
      function(...) got = { ... } end)
    P("     SetValueAndCallBack ok=" .. tostring(okb) .. " ret=" .. T(br)
      .. " 回调同步触发=" .. tostring(got ~= nil))
    if got then
      local s = "     回调返回" .. #got .. "个"
      for i = 1, math.min(#got, 5) do s = s .. " | " .. T(got[i]) end
      P(s)
    end
    local ok2 = pcall(DM.GetValueAndCallBack, DM, varId, playerId, K33,
      function(...) P("     GetValueAndCallBack 回调: " .. T((select(1, ...)))
        .. " | " .. T((select(2, ...))) .. " | " .. T((select(3, ...)))) end)
    P("     GetValueAndCallBack ok=" .. tostring(ok2))
    if type(DM.RemoveValueAndCallBack) == "function" then
      call("RemoveValueAndCallBack", DM, "RemoveValueAndCallBack", varId, playerId, K33)
    end
  else
    P("  [B] Data.Map 回调版不可用")
  end

  -- 6.3 Trigger.KvMap
  if type(KM) == "table" and type(KM.SetDataListBykey) == "function" then
    P("  [C] Trigger.KvMap")
    call("SetDataListBykey", KM, "SetDataListBykey", varId, playerId, K33, VBIN)
    local r1 = call("GetDataListBykey(itype=0)", KM, "GetDataListBykey", varId, playerId, K33, 0)
    call("GetDataListBykey(itype=1)", KM, "GetDataListBykey", varId, playerId, K33, 1)
    P("     往返一致 = " .. tostring(r1 == VBIN))
    call("RemoveDataListBykey", KM, "RemoveDataListBykey", varId, playerId, K33)
  else
    P("  [C] Trigger.KvMap 不可用")
  end

  -- 6.4 UserData（无 varId）
  if type(DM) == "table" and type(DM.SetUserDataValue) == "function" then
    P("  [D] Data.Map UserData")
    call("SetUserDataValue", DM, "SetUserDataValue", K33, VBIN)
    local u = call("GetUserDataValue", DM, "GetUserDataValue", K33)
    P("     往返一致 = " .. tostring(u == VBIN))
  else
    P("  [D] UserData 不可用")
  end

  -- 6.5 GetAllValue（看能否整表拉取，用于重建索引）
  if type(DM) == "table" and type(DM.GetAllValue) == "function" then
    P("  [E] Data.Map.GetAllValue")
    local ok, all = pcall(DM.GetAllValue, DM, varId, playerId)
    P("     ok=" .. tostring(ok) .. " ret=" .. T(all))
    if type(all) == "table" then
      local n = 0
      for _ in pairs(all) do n = n + 1 end
      P("     条目数=" .. n)
    end
  end

  -- 6.6 playerId 语义
  P("---- 7. playerId 语义 ----")
  if type(DM) == "table" and type(DM.GetValueAndBlock) == "function" then
    call("get(pid=nil)", DM, "GetValueAndBlock", varId, nil, K33)
    call("get(pid=0)", DM, "GetValueAndBlock", varId, 0, K33)
  end

  P("========== 探针v2结束 ==========")
end

-- 开放函数
Script.Probe2 = function(self, varId, playerId)
  if playerId == nil then playerId = 0 end
  local ok, err = pcall(run, varId, playerId)
  if not ok then P("探针异常: " .. tostring(err)) end
  return "ok"
end

Script.propertys = Script.propertys or {}
Script.openFunctions = Script.openFunctions or {}
Script.openFnArgs = Script.openFnArgs or {}
local hasP = false
for _, v in ipairs(Script.openFunctions) do if v == "Probe2" then hasP = true end end
if not hasP then
  Script.openFunctions[#Script.openFunctions + 1] = "Probe2"
  Script.openFnArgs[#Script.openFnArgs + 1] = { "varId", "playerId" }
end

-- 加载期自动跑一遍（拿不到属性就只打印环境部分）
pcall(run, nil, 0)
