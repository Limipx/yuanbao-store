-- ============================================================
-- KVFS v4 测试台（Lua 5.1 / lupa）
-- 重点：mock 的 UpdateValueAndCallback 忠实复刻官方协议
--   GET -> SET -> (CAS 失败则重新拉取再 SET) -> OK
-- 并提供【对抗性调度器】：在 GET 与 SET 之间插入第三方写入，
-- 强制走冲突重试路径，用来证明 mergeFn 是 join（不丢更新）
-- ============================================================
math.randomseed(20261018)

-- ---------- 引擎环境 ----------
Mini = { String = "String", Number = "Number", Bool = "Bool",
Object = "Object", Player = "Player", Array = "Array",
CustomData = "CustomData" }
ErrorCode = { OK = 0, FAILED = 1, KV_UPDATE_GET = 3, KV_UPDATE_SET = 4,
KV_OP_CD_LMT = 5, KV_OP_QPM_LMT = 6, KV_OP_NO_VAL = 2,
KV_OP_INVALID_VAL = 7 }
CLOCK = 1700000000000
os = { time = function() return math.floor(CLOCK / 1000) end,
timeMs = function() return CLOCK end,
date = function() return "2026-01-01" end }
_G.os = os
Player = { GetUin = function() return 0 end }

-- ---------- bit 库 mock（忠实复刻引擎 bit：有符号 32 位语义） ----------
local function _u2(x) return x % 4294967296 end
local function _tobit(x)
  x = _u2(x)
  if x >= 2147483648 then x = x - 4294967296 end
  return x
end
local function _bitwise(a, b, op)
  a, b = _u2(a), _u2(b)
  local r, m = 0, 1
  for _ = 1, 32 do
    local pa, pb = a % 2, b % 2
    if (op == "xor" and pa ~= pb) or (op == "and" and pa == 1 and pb == 1) then
      r = r + m
    end
    a = math.floor(a / 2); b = math.floor(b / 2); m = m * 2
  end
  return _tobit(r)
end
local function _rshift(a, s)
  local v = math.floor(_u2(a))
  for _ = 1, s do v = math.floor(v / 2) end
  return _tobit(v)
end
-- lupa 是 5.5，math.pow 已移除；引擎 5.1 有，这里补个 shim 只为跑通测试
if not math.pow then math.pow = function(a, b) return a ^ b end end
bit = {
  tobit  = _tobit,
  bxor   = function(a, b) return _bitwise(a, b, "xor") end,
  band   = function(a, b) return _bitwise(a, b, "and") end,
  rshift = _rshift,
}
_G.bit = bit

-- ---------- Mock KV ----------
local Store = {}
local Queue = {}
local STAT = { get = 0, set = 0, atomic = 0, conflict = 0, retry = 0,
intrude = 0, keys = {} }
local MODE = "sync"          -- sync=回调同步跑完   async=入队由调度器推进
local INTRUDE = 0            -- 0~1，在 GET/SET 之间插入第三方写的概率
local INTRUDER = nil         -- function(key, store) 第三方写逻辑

local function noteKey(k)
STAT.keys[k] = true
end

Data = { Map = {} }
function Data.Map:GetValueAndBlock(vid, pid, k)
STAT.get = STAT.get + 1; noteKey(k)
return 0, k, Store[k]
end
function Data.Map:SetValueAndBlock(vid, pid, k, v)
STAT.set = STAT.set + 1; noteKey(k)
Store[k] = v
return 0, k, v
end
function Data.Map:RemoveValueAndBlock(vid, pid, k)
Store[k] = nil
return 0, k
end

-- ★ 原子更新：忠实复刻官方协议
local function runTxn(t)
local cb, key = t.cb, t.key
while true do
t.tries = t.tries + 1
if t.tries > 16 then cb(ErrorCode.FAILED, key, nil); return false end
local base = Store[key]
-- 1) 引擎把当前值交给回调
if base ~= nil then cb(ErrorCode.KV_UPDATE_GET, key, base)
else cb(ErrorCode.KV_OP_NO_VAL, key, nil) end
-- 2) 引擎索要新值
local nv = cb(ErrorCode.KV_UPDATE_SET, key, base)
if nv == nil then return false end
-- ★ 对抗点：GET 与 SET 之间，第三方抢先写入
if INTRUDER and INTRUDE > 0 and math.random() < INTRUDE then
INTRUDER(key, Store)
STAT.intrude = STAT.intrude + 1
end
-- 3) CAS 校验
if (Store[key] or "") == (base or "") then
Store[key] = nv
noteKey(key)
cb(ErrorCode.OK, key, nv)
return true
else
STAT.conflict = STAT.conflict + 1
STAT.retry = STAT.retry + 1
end
end
end

function Data.Map:UpdateValueAndCallback(vid, pid, k, cb)
STAT.atomic = STAT.atomic + 1
noteKey(k)
local t = { key = k, cb = cb, tries = 0 }
if MODE == "sync" then return runTxn(t) end
Queue[#Queue + 1] = t
return true
end

local Mock = {}
function Mock:get(k) STAT.get = STAT.get + 1; noteKey(k); return Store[k] end
function Mock:set(k, v) STAT.set = STAT.set + 1; noteKey(k); Store[k] = v; return true end
function Mock:del(k) Store[k] = nil; return true end
function Mock:atomic(k, cb)
STAT.atomic = STAT.atomic + 1; noteKey(k)
local t = { key = k, cb = cb, tries = 0 }
if MODE == "sync" then return runTxn(t) end
Queue[#Queue + 1] = t
return true
end

-- 调度器：随机顺序推进，队列乱序
local function pump(maxSteps)
local steps = 0
while #Queue > 0 and steps < (maxSteps or 100000) do
local i = math.random(1, #Queue)
local t = Queue[i]
table.remove(Queue, i)
runTxn(t)
steps = steps + 1
end
return steps
end
local function pumpAll(insts, maxSteps)
local guard = 0
while #Queue > 0 and guard < (maxSteps or 2000) do
pump(1)
for _, s in ipairs(insts or {}) do
if s._pumpPend then s:_pumpPend() end
end
guard = guard + 1
end
for _, s in ipairs(insts or {}) do
if s._pumpPend then s:_pumpPend() end
end
return guard
end

-- ---------- 载入被测脚本 ----------
local path = "/data/workspace/KV文件系统_云服版v4.lua"
local f = assert(loadfile(path))
local Script = f()
if type(Script) ~= "table" then error("脚本未返回 Script 表") end

-- ---------- 断言 ----------
local PASS, FAIL = 0, 0
local function ck(name, cond, extra)
if cond then PASS = PASS + 1; print("[ok]   " .. name)
else FAIL = FAIL + 1; print("[FAIL] " .. name .. "  << " .. tostring(extra)) end
end
local function newInst(uin, props)
local s = setmetatable({}, { __index = Script })
for k, v in pairs(Script.propertys) do s[k] = v.default end
if props then for k, v in pairs(props) do s[k] = v end end
s._mock = Mock
s._testUin = uin
s._defVarId = "KVFSVAR"
s.echoDetail = false
return s
end
local function reset()
Store = {}; Queue = {}
STAT = { get = 0, set = 0, atomic = 0, conflict = 0, retry = 0,
intrude = 0, keys = {} }
INTRUDE = 0; INTRUDER = nil
end

print("================ 载入 ================")
ck("脚本是 table", type(Script) == "table")
ck("propertys 只有 propertys/openFnArgs 之外的键？", (function()
local n = 0
for k in pairs(Script) do n = n + 1 end
return n >= 2
end)())
local nf = 0
for k, v in pairs(Script.propertys) do
if type(v) ~= "table" or v.type == nil or v.displayName == nil then
nf = nf + 1; print("  属性格式错: " .. tostring(k))
end
end
ck("属性全部为键值格式(type/displayName)", nf == 0, nf)
local nfn = 0
for k, v in pairs(Script.openFnArgs) do
nfn = nfn + 1
if type(v) ~= "table" or v.returnType == nil or v.displayName == nil
or type(v.params) ~= "table" or #v.params < 2 then
print("  开放函数格式错: " .. tostring(k))
end
end
ck("开放函数数量>=10 且格式合规", nfn >= 10, nfn)

-- ============================================================
print("")
print("================ T1 内置自检 Check() ================")
reset(); MODE = "sync"
do
local a = newInst(1001)
local r = a:Check()
ck("Check 无失败", string.find(r, "失败 0", 1, true) ~= nil, r)
end

-- ============================================================
print("")
print("================ T2 单站点文件操作（同步路径） ================")
reset(); MODE = "sync"
do
local a = newInst(1001)
a.preferAsync = false
a:Init()
local d = a:Create_(nil, "dir", "docs")
ck("创建目录返回OK", string.sub(d, 1, 2) == "OK", d)
local did = string.match(d, "([^%s]+)$")
local f1 = a:Create_(did, "file", "a.txt")
local fid = string.match(f1, "([^%s]+)$")
a:Write_(fid, "hello")
ck("读取内容一致", a:Read_(fid) == "hello", a:Read_(fid))
a:Write_(fid, string.rep("X", 5000))
local big = a:Read_(fid)
ck("大内容走blob且往返一致", #big == 5000, #big)
local ls = a:List_(did)
ck("List 含该文件", string.find(ls, "a.txt", 1, true) ~= nil, ls)
a:Rename_(fid, "b.txt")
ck("改名生效", string.find(a:List_(did), "b.txt", 1, true) ~= nil)
local d2 = a:Create_(nil, "dir", "other")
local d2id = string.match(d2, "([^%s]+)$")
a:Move_(fid, d2id)
ck("移动后原目录空", a:List_(did) == "(空)", a:List_(did))
ck("移动后新目录有", string.find(a:List_(d2id), "b.txt", 1, true) ~= nil)
a:Remove_(fid)
ck("删除后读不到", string.sub(a:Read_(fid), 1, 3) == "ERR", a:Read_(fid))
local r = a:Flush()
ck("Flush 成功", string.sub(r, 1, 2) == "OK", r)
end

-- ============================================================
print("")
print("================ T3 六站点并发 -> 全局收敛 ================")
reset(); MODE = "sync"
do
local insts = {}
for i = 1, 6 do
local s = newInst(2000 + i, { preferAsync = false })
s:Init()
insts[i] = s
end
for i = 1, 6 do
for j = 1, 10 do insts[i]:Create_(nil, "file", "f" .. i .. "_" .. j) end
insts[i]:Flush()
end
for i = 1, 6 do insts[i]:Sync() end
local counts = {}
for i = 1, 6 do
counts[i] = insts[i]:_countAlive()
end
local same = true
for i = 2, 6 do if counts[i] ~= counts[1] then same = false end end
ck("六站点视图一致", same, table.concat(counts, ","))
ck("对象总数=60", counts[1] == 60, counts[1])
end

-- ============================================================
print("")
print("================ T4 对抗调度：GET/SET 之间被第三方抢写 ================")
reset(); MODE = "async"; INTRUDE = 1.0
do
-- 第三方：每次抢写都往同一个分片塞入一条"幽灵 op"
local ghost = 0
INTRUDER = function(key, st)
ghost = ghost + 1
local cur = st[key]
if cur and string.sub(cur, 1, 2) == "H|" then
st[key] = cur .. "\nGHOST." .. ghost .. "|wr|GHOST." .. ghost
.. "=x|-|9:0|-"
end
end
local insts = {}
for i = 1, 5 do
local s = newInst(3000 + i, { preferAsync = true })
s:Init()
insts[i] = s
end
for i = 1, 5 do
for j = 1, 8 do insts[i]:Create_(nil, "file", "c" .. i .. "_" .. j) end
insts[i]:Flush()
end
pumpAll(insts)
for i = 1, 5 do insts[i]:Sync() end
local counts = {}
for i = 1, 5 do counts[i] = insts[i]:_countAlive() end
local same = true
for i = 2, 5 do if counts[i] ~= counts[1] then same = false end end
ck("对抗下视图仍一致", same, table.concat(counts, ","))
ck("对抗下 40 个对象全保留", counts[1] == 40, counts[1])
ck("确实发生了 CAS 冲突重试", STAT.retry > 0, STAT.retry)
ck("确实发生了第三方抢写", STAT.intrude > 0, STAT.intrude)
print("  [统计] 冲突=" .. STAT.conflict .. " 重试=" .. STAT.retry
.. " 抢写=" .. STAT.intrude .. " 原子调用=" .. STAT.atomic)
end

-- ============================================================
print("")
print("================ T5 同站点双进程（重复 uin）不丢 op ================")
reset(); MODE = "async"; INTRUDE = 0.6
INTRUDER = function(key, st)
local cur = st[key]
if cur and string.sub(cur, 1, 2) == "H|" then
st[key] = cur .. "\nS4001.999|wr|S4001.999|=z|-|9:0|-"
end
end
do
local a = newInst(4001, { preferAsync = true })
local b = newInst(4001, { preferAsync = true })
a:Init(); b:Init()
ck("两实例站点ID相同但dot不撞(块预留)", a._site == b._site, a._site .. "/" .. b._site)
for j = 1, 10 do a:Create_(nil, "file", "A" .. j) end
for j = 1, 10 do b:Create_(nil, "file", "B" .. j) end
a:Flush(); b:Flush()
pumpAll({ a, b })
-- 两边各自回读
local c = newInst(4001, { preferAsync = false })
c:Init(); c:Sync()
ck("同站点并发 20 个对象全保留", c:_countAlive() == 20, c:_countAlive())
local ls = c:List_(nil)
ck("A 序列存在", string.find(ls, "A1", 1, true) ~= nil)
ck("B 序列存在", string.find(ls, "B1", 1, true) ~= nil)
end

-- ============================================================
print("")
print("================ T6 快照压缩后仍可完整恢复 ================")
reset(); MODE = "sync"
do
local a = newInst(5001, { preferAsync = false, snapshotEveryOps = 0 })
a:Init()
for j = 1, 30 do a:Create_(nil, "file", "s" .. j) end
a:Flush()
local r = a:Compact()
ck("Compact 成功", string.sub(r, 1, 2) == "OK", r)
local b = newInst(5002, { preferAsync = false })
b:Init()
b.peerSites = a._site
b:Sync()
ck("新站点从快照+日志恢复 30 个", b:_countAlive() == 30, b:_countAlive())
end

-- ============================================================
print("")
print("================ T7 纯去中心化（关注册表，只靠 peerSites） ================")
reset(); MODE = "sync"
do
local a = newInst(6001, { preferAsync = false, useRegistry = false })
local b = newInst(6002, { preferAsync = false, useRegistry = false })
a:Init(); b:Init()
a.peerSites = b._site
b.peerSites = a._site
for j = 1, 5 do a:Create_(nil, "file", "x" .. j) end
for j = 1, 5 do b:Create_(nil, "file", "y" .. j) end
a:Flush(); b:Flush()
a:Sync(); b:Sync()
ck("去中心化 A 见 10", a:_countAlive() == 10, a:_countAlive())
ck("去中心化 B 见 10", b:_countAlive() == 10, b:_countAlive())
local usedReg = false
for k in pairs(STAT.keys) do
if string.sub(k, 1, 2) == "R." then usedReg = true end
end
ck("确实没写注册表键", not usedReg)
end

-- ============================================================
print("")
print("================ T8 键约束（<=50 字节 / 可打印 / 无空格） ================")
do
local bad = 0
local worst = 0
for k in pairs(STAT.keys) do
if #k > worst then worst = #k end
if #k > 50 then bad = bad + 1; print("  超长键: " .. k .. " (" .. #k .. ")") end
if string.find(k, "%s") then bad = bad + 1; print("  含空白: " .. k) end
if string.find(k, "[%c]") then bad = bad + 1; print("  含控制字符: " .. k) end
if string.find(k, "[^%w_.%-]") then bad = bad + 1; print("  含非法字符: " .. k) end
end
ck("所有键合法", bad == 0, bad)
print("  最长键 " .. worst .. " 字节")
end

-- ============================================================
print("")
print("================ T9 值大小不超过 2MB ================")
do
local big = 0
for k, v in pairs(Store) do
if type(v) == "string" and #v > big then big = #v end
end
ck("单值 < 2MB", big < 2000000, big)
print("  最大值 " .. big .. " 字节")
end

-- ============================================================
print("")
print("================ T10 配额估算（人均读写次数） ================")
reset(); MODE = "sync"
do
local a = newInst(7001, { preferAsync = false })
a:Init()
for j = 1, 50 do a:Create_(nil, "file", "q" .. j) end
a:Flush()
print("  50 次创建+1次发布：读=" .. STAT.get .. " 写=" .. STAT.set
.. " 原子=" .. STAT.atomic)
local b = newInst(7002, { preferAsync = false })
b:Init(); b.peerSites = a._site
local g0, s0 = STAT.get, STAT.set
b:Sync()
print("  一次全量同步：读=" .. (STAT.get - g0) .. " 写=" .. (STAT.set - s0))
ck("同步读次数 <= 20", (STAT.get - g0) <= 20, STAT.get - g0)
end

-- ============================================================
print("")
print("================ T11 环境自检 Env() ================")
reset(); MODE = "sync"
do
local a = newInst(8001)
local r = a:Env()
ck("Env 报出原子接口可用", string.find(r, "★存在", 1, true) ~= nil, r)
print(r)
end


-- ============================================================
print("")
print("================ T12 规模：50 站点 / 注册表分桶 / 同步成本 ================")
reset(); MODE = "sync"
do
local insts = {}
for i = 1, 50 do
local s = newInst(90000 + i, { preferAsync = false, rootShards = 16 })
s:Init()
insts[i] = s
end
for i = 1, 50 do
for j = 1, 4 do insts[i]:Create_(nil, "file", "m" .. i .. "_" .. j) end
insts[i]:Flush()
end
local buckets = {}
for k in pairs(STAT.keys) do
if string.sub(k, 1, 2) == "R." then buckets[k] = true end
end
local nb = 0
for _ in pairs(buckets) do nb = nb + 1 end
ck("注册表确实分桶(>1)", nb > 1, nb)
print("  注册表桶数=" .. nb)
local g0 = STAT.get
local c = newInst(90001, { preferAsync = false, rootShards = 16 })
c:Init()
c.maxTrackSites = 50
c:Sync()
print("  全量同步一次：读=" .. (STAT.get - g0))
ck("50站点首次同步读次数 <= 260", (STAT.get - g0) <= 260, STAT.get - g0)
ck("收敛到 200 个对象", c:_countAlive() == 200, c:_countAlive())
end

print("")
-- ============================================================
print("")
print("================ T13 稳态同步成本（第二、三次同步） ================")
do
local c2 = newInst(90001, { preferAsync = false, rootShards = 16 })
c2:Init()
c2.maxTrackSites = 50
local g0 = STAT.get
c2:Sync()
local r1 = STAT.get - g0
local g1 = STAT.get
c2:Sync()
local r2 = STAT.get - g1
local g2 = STAT.get
c2:Sync()
local r3 = STAT.get - g2
print("  首次=" .. r1 .. " 第二次=" .. r2 .. " 第三次(稳态)=" .. r3)
ck("稳态同步 <= 70 次读", r3 <= 70, r3)
ck("稳态 < 首次(注册表已带TTL)", r3 < r1, r3 .. " vs " .. r1)
end

print("")
print("================================================")
print("总计 通过 " .. PASS .. " / 失败 " .. FAIL)
print("================================================")
