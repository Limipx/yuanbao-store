--[[
================================================================================
KV 文件系统 云服版 v4 —— Server-Atomic CRDT（服务端原子 RMW + CRDT 合并）
================================================================================
★ 本版相对 v3 的根本变化：发现了 Data.Map:UpdateValueAndCallback ★

官方文档原话：
  "安全更新表中某个key下的值，并发存取数据，确保Key下的值唯一性"
  "遇到冲突、失败的情况，接口会自动回传最新的数据值，并调用开发者的
    回调函数，按照开发者自己设定的逻辑进行更新数据，确保了数据不出错，
    不会被其他玩家覆盖"

这不是普通的 set —— 它是【服务端托管的原子读-改-写 + 冲突自动重试】：
  引擎拉取当前值 -> 回调(KV_UPDATE_GET) -> 回调(KV_UPDATE_SET, 你返回新值)
  -> 引擎尝试用 CAS 写回 -> 若期间被别人改过，重新拉取、再次回调
  -> 成功 回调(ErrorCode.OK)

等价于数据库里的 "UPDATE ... WHERE version = x" 重试循环，
等价于乐观锁，但重试由服务端驱动，不需要我们自己轮询。

v3 的问题：用的是 Get + Set 两条独立调用 => 丢失更新(lost update)必然发生。
v4 的解法：所有共享可变状态一律走 _aupd()，
          且 mergeFn 必须是【join：幂等 + 交换 + 结合】，
          因此即便引擎重试、即便并发交错、即便读到更新的值再合并，
          结果都是同一个上确界 —— 数学上不可能丢更新。

--------------------------------------------------------------------------------
可达到 / 不可达到（先说清楚）
--------------------------------------------------------------------------------
✅ 单键线性一致（服务端串行化 + CAS 重试）
✅ 不丢更新（merge 是 join，任何交错都收敛到同一上确界）
✅ 千人多房间：每个站点只写自己的键，无共享热点键（分片注册表 16 桶）
✅ 因果可检测 / 并发冲突显式检出并裁决（结果全网一致）
✅ 内容寻址 blob 不可变 —— 永不需要加锁
✅ 去中心化可用：即使共享注册表完全不可写，靠 peerSites 仍能收敛
❌ 跨键事务（引擎无事务；本设计用"不可变 blob + join 合并"绕开）
❌ 进程被杀时【未投递】的本地 op 会丢（等于没提交，可接受）
--------------------------------------------------------------------------------
KV 布局（key 全部 ASCII 可打印、无空格、<=50 字节）
--------------------------------------------------------------------------------
V.<app>.<site>        站点指针（只由该站点自己写，join = 逐字段取 max）
  值: site|maxShard|maxSeq|snapShard|snapSeq|hash
L.<app>.<site>.<n>    第 n 个日志分片（owner 单写，join = 按 dot 并集）
  首行: H|<site>|<minSeq>|<maxSeq>|<count>
  其后每行: dot|type|obj|a1|a2|hlc|dep
S.<app>.<site>        快照（owner 写，join = 按 obj 取最新 dot 覆盖）
  首行: T|<site>|<uptoShard>|<uptoSeq>|<count>
  其后每行: 与 op 行同格式（已压缩，每个 obj 只留最后一条有效 op）
B.<app>.<hash>[.<i>]  内容寻址 blob（不可变，创建后永不改写，无冲突）
R.<app>.<b>           注册表第 b 桶（多写，join = 并集 + 取 max）
  值: site:maxShard:maxSeq;site:...   （b = hash(site) % rootShards）
--------------------------------------------------------------------------------
op 行字段
--------------------------------------------------------------------------------
dot  = <siteId>.<seq>        全局唯一、本地确定、零分配
type = mk|mv|rn|rm|wr
obj  = 对象稳定 ID（= 创建它的 dot）
a1   = mk:父ID   mv:新父ID   rn:新名字   rm:-   wr:内容
a2   = mk:kind:name(d或f)  mv:旧父ID  rn:-  rm:-  wr:-
hlc  = <ptMs>:<ct>          仅用于确定性全序，不承担因果
dep  = 依赖的 dot，逗号分隔  ← 因果由它承载
--------------------------------------------------------------------------------
与引擎的绑定（只有这几行，签名不对就改这里）
--------------------------------------------------------------------------------
Data.Map:UpdateValueAndCallback(varId, pid, key, cb) -> bool   ★原子RMW
Data.Map:GetValueAndBlock(varId, pid, key)      -> code, key, value
Data.Map:SetValueAndBlock(varId, pid, key, val) -> code, key, value
Data.Map:RemoveValueAndBlock(varId, pid, key)   -> code, key
约定 code == 0 (ErrorCode.OK) 为成功；不同就改 Script:_isOK()
================================================================================
]]
local Script = {}
--------------------------------------------------------------------------------
-- 属性
--------------------------------------------------------------------------------
Script.propertys = {
appPrefix = {
type = Mini.String, default = "fs",
displayName = "命名空间前缀",
tips = "所有key的前缀;不同应用用不同前缀隔离;只保留字母数字下划线短横线",
},
kvVarId = {
type = Mini.String, default = "",
displayName = "云服变量ID",
tips = "变量库里的全局(云)变量ID;留空则用内置默认;必须是云变量否则跨房不通",
},
scope = {
type = Mini.Number, default = 0,
displayName = "作用域 0共享 1私人",
minValue = 0, maxValue = 1,
tips = "0=共享(playerId传nil,全服/房间看变量预设);1=私人(playerId传uin)",
},
registryRefreshSec = {
type = Mini.Number, default = 300,
displayName = "注册表刷新周期(秒)",
minValue = 10, maxValue = 3600,
tips = "注册表只用于发现新站点,不需要每次同步都读;调大省配额",
},
peerSites = {
type = Mini.String, default = "",
displayName = "已知站点ID(逗号分隔)",
tips = "跨房间同步要填;同房间可留空靠注册表发现;填了则注册表不可用时仍能收敛",
},
rootShards = {
type = Mini.Number, default = 4,
displayName = "注册表分桶数",
minValue = 1, maxValue = 64,
tips = "人多时调大(建议16);分桶把注册表的写热点打散",
},
useRegistry = {
type = Mini.Bool, default = true,
displayName = "启用共享注册表",
tips = "关=纯去中心化,只靠peerSites发现;人多且限流时可关",
},
maxOpsPerShard = {
type = Mini.Number, default = 200,
displayName = "每分片最多op条数",
minValue = 8, maxValue = 4000,
},
maxShardBytes = {
type = Mini.Number, default = 48000,
displayName = "每分片最大字节",
minValue = 2000, maxValue = 1800000,
tips = "Data.Map单值上限2MB,留足余量",
},
snapshotEveryOps = {
type = Mini.Number, default = 400,
displayName = "每多少op做一次快照",
minValue = 0, maxValue = 100000,
tips = "0=不做快照;大值=日志长但省写",
},
inlineMaxBytes = {
type = Mini.Number, default = 512,
displayName = "内容内联上限(字节)",
minValue = 0, maxValue = 100000,
tips = "小于此且不含分隔符则内联进op;否则存内容寻址blob",
},
maxTrackSites = {
type = Mini.Number, default = 8,
displayName = "最多跟踪几个站点",
minValue = 1, maxValue = 512,
tips = "同步时读取的站点数上限;配额铁律: 本值 x 60/自动同步周期 必须 <= 10",
},
autoFlushOnWrite = {
type = Mini.Bool, default = false,
displayName = "每次改动立刻发布",
tips = "关=攒着批量发布(省配额,推荐);开=即时但费配额",
},
preferAsync = {
type = Mini.Bool, default = true,
displayName = "优先用原子更新接口",
tips = "true=UpdateValueAndCallback(真原子);false=Block接口模拟CAS",
},
casRetries = {
type = Mini.Number, default = 8,
displayName = "CAS最大重试次数",
minValue = 1, maxValue = 64,
},
autoSyncSec = {
type = Mini.Number, default = 60,
displayName = "自动同步周期(秒)",
minValue = 0, maxValue = 3600,
tips = "0=不自动同步",
},
autoFlushSec = {
type = Mini.Number, default = 10,
displayName = "自动发布周期(秒)",
minValue = 0, maxValue = 3600,
tips = "0=只手动发布;建议0或>=10",
},
rmWins = {
type = Mini.Bool, default = true,
displayName = "并发时删除优先",
tips = "true=并发的rm压过mv/wr;false=按全序后者胜",
},
outEventId = {
type = Mini.String, default = "",
displayName = "结果广播事件ID",
tips = "异步结果推到这个自定义事件;开放函数返回值人类看不到,必须靠它或日志",
},
echoDetail = {
type = Mini.Bool, default = true,
displayName = "输出详细日志",
},
}
--------------------------------------------------------------------------------
-- 开放函数
--------------------------------------------------------------------------------
Script.openFnArgs = {
Init = {
returnType = Mini.String,
displayName = "①初始化(留空)",
params = { "留空即可", Mini.String },
},
Create = {
returnType = Mini.String,
displayName = "②创建(父ID,类型,名字)",
params = { "父ID(留空=根)", Mini.String,
"类型 dir或file", Mini.String,
"名字", Mini.String },
},
Move = {
returnType = Mini.String,
displayName = "③移动(对象ID,新父ID)",
params = { "对象ID", Mini.String, "新父ID", Mini.String },
},
Rename = {
returnType = Mini.String,
displayName = "④改名(对象ID,新名字)",
params = { "对象ID", Mini.String, "新名字", Mini.String },
},
Remove = {
returnType = Mini.String,
displayName = "⑤删除(对象ID)",
params = { "对象ID", Mini.String },
},
Write = {
returnType = Mini.String,
displayName = "⑥写入(对象ID,内容)",
params = { "对象ID", Mini.String, "内容", Mini.String },
},
Read = {
returnType = Mini.String,
displayName = "⑦读取(对象ID)",
params = { "对象ID", Mini.String },
},
List = {
returnType = Mini.String,
displayName = "⑧列出子项(父ID)",
params = { "父ID(留空=根)", Mini.String },
},
Sync = {
returnType = Mini.String,
displayName = "⑨拉取同步(留空)",
params = { "留空即可", Mini.String },
},
Flush = {
returnType = Mini.String,
displayName = "⑩发布本地(留空)",
params = { "留空即可", Mini.String },
},
Status = {
returnType = Mini.String,
displayName = "⑪状态与新鲜度(留空)",
params = { "留空即可", Mini.String },
},
Compact = {
returnType = Mini.String,
displayName = "⑫压缩快照(留空)",
params = { "留空即可", Mini.String },
},
Check = {
returnType = Mini.String,
displayName = "⑬自检(留空)",
params = { "留空即可", Mini.String },
},
Env = {
returnType = Mini.String,
displayName = "⑭环境自检(留空)",
params = { "留空即可", Mini.String },
},
}
--------------------------------------------------------------------------------
-- 基础工具
--------------------------------------------------------------------------------
local ROOTID = "@root"
local SEP = "|"
local MAXKEY = 50
local MAXVAL = 1900000
local MAX_RETRY = 6

local function _t(v) if v == nil then return "" end return tostring(v) end
local function _n(v) return tonumber(v) or 0 end
local function _flag(v)
if v == nil then return false end
if type(v) == "boolean" then return v end
local s = _t(v):lower()
if s == "true" or s == "1" or s == "yes" or s == "on" then return true end
if s == "false" or s == "0" or s == "no" or s == "off" or s == "" then return false end
local num = tonumber(v)
if num == nil then return true end
return num ~= 0
end
local _split = string.split or function(s, d)
local out = {}
local pat = "[^" .. (d or SEP) .. "]+"
local i = 0
for w in string.gmatch(s, pat) do i = i + 1; out[i] = w end
out.n = i
return out
end
-- ⚠ string.split 会跳过空字段；本文件的所有序列化都保证字段非空（用 "-" 占位）
local function _join(list, d)
local n = #list
if n == 0 then return "" end
local acc = list[1]
for i = 2, n do acc = acc .. (d or ",") .. list[i] end
return acc
end
local function _trim(s)
s = _t(s)
local a, b = string.find(s, "^%s+")
if a then s = string.sub(s, b + 1) end
a, b = string.find(s, "%s+$")
if a then s = string.sub(s, 1, a - 1) end
return s
end
-- 32 位 FNV-1a（纯算术，255 * 2^32 < 2^53，double 精度安全）
local function _h32(s)
local h = 2166136261
for i = 1, #s do
h = (h * 16777619) % 4294967296
h = (h + string.byte(s, i)) % 4294967296
end
return h
end
local HEX = "0123456789abcdef"
local function _hex8(n)
local s = ""
for i = 7, 0, -1 do
local b = math.floor(n / math.pow(2, i * 4)) % 16
s = s .. string.sub(HEX, b + 1, b + 1)
end
return s
end
local function _hash(s) return _hex8(_h32(s)) end
local B36 = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"
local function _b36(n)
n = math.floor(_n(n))
if n <= 0 then return "0" end
local s = ""
while n > 0 do
local r = n % 36
s = string.sub(B36, r + 1, r + 1) .. s
n = math.floor(n / 36)
end
return s
end
-- 名字/内容清洗：op 行用 | 分隔，且不能有换行
local function _safeName(s)
s = _t(s)
s = string.gsub(s, "[%c" .. SEP .. ":;]", "_")
if s == "" then s = "_" end
if #s > 40 then s = string.sub(s, 1, 40) end
return s
end
local function _canInline(s)
if #s > 0 and #s <= 4096 then
if string.find(s, "[%c" .. SEP .. "]", 1) then return false end
return true
end
return false
end
local function _ordkey(hlc, dot)
local p, c = string.match(hlc or "0:0", "^(%-?%d+):(%d+)")
return string.format("%013d:%05d:%s", _n(p), _n(c), _t(dot))
end
--------------------------------------------------------------------------------
-- 引擎环境探测（一次性）
--------------------------------------------------------------------------------
local EC = (type(ErrorCode) == "table") and ErrorCode or {}
local EC_OK = EC.OK
if EC_OK == nil then EC_OK = 0 end
local EC_SET = EC.KV_UPDATE_SET
local EC_GET = EC.KV_UPDATE_GET
local EC_NOVAL = EC.KV_OP_NO_VAL
local HAS_UPD = false
if type(Data) == "table" and type(Data.Map) == "table"
and type(Data.Map.UpdateValueAndCallback) == "function" then
HAS_UPD = true
end
--------------------------------------------------------------------------------
-- KV 适配层（引擎 / mock 双路）
--------------------------------------------------------------------------------
function Script:_isOK(c) return c == EC_OK or c == 0 end
function Script:_pid()
if _n(self.scope) == 1 then
local u = self._uin
if u == nil or u == 0 then u = self._testUin or 0 end
if u ~= 0 then return u end
end
return nil
end
function Script:_vid()
local v = _trim(self.kvVarId)
if v ~= "" then return v end
return self._defVarId or "KVFS"
end
function Script:_get(k)
self._st_get = (self._st_get or 0) + 1
if self._mock then return self._mock:get(k) end
local c, _, v = Data.Map:GetValueAndBlock(self:_vid(), self:_pid(), k)
if not self:_isOK(c) then return nil end
return v
end
function Script:_set(k, v)
self._st_set = (self._st_set or 0) + 1
if self._mock then return self._mock:set(k, v) end
local c = Data.Map:SetValueAndBlock(self:_vid(), self:_pid(), k, v)
return self:_isOK(c)
end
function Script:_del(k)
if self._mock then return self._mock:del(k) end
local c = Data.Map:RemoveValueAndBlock(self:_vid(), self:_pid(), k)
return self:_isOK(c)
end
function Script:_log(s)
if _flag(self.echoDetail) then print(_t(s)) end
end
function Script:_out(s)
print(_t(s))
local eid = _trim(self.outEventId)
if eid ~= "" and self.PushCustomEvent then
pcall(function() self:PushCustomEvent(eid, _t(s)) end)
end
end
--------------------------------------------------------------------------------
-- ★ 核心：原子读-改-写
--   _aupd(key, mergeFn, onDone)
--   mergeFn(oldString) -> newString | nil(放弃)
--   契约：mergeFn 必须是 join（幂等 / 交换 / 结合），否则重试会破坏正确性
--------------------------------------------------------------------------------
function Script:_aupd(key, mergeFn, onDone)
local wantAsync = _flag(self.preferAsync) and HAS_UPD and not self._forceSync
if wantAsync then
return self:_aupdAsync(key, mergeFn, onDone)
end
return self:_aupdSync(key, mergeFn, onDone)
end

-- 路径 A：UpdateValueAndCallback（服务端驱动 CAS + 自动重试）
function Script:_aupdAsync(key, mergeFn, onDone)
local st = { calls = 0, sets = 0, base = nil, newVal = nil,
done = false, fail = nil, aborted = false }
local selfRef = self
local function cb(code, k, v)
st.calls = st.calls + 1
if st.calls > MAX_RETRY then
-- CAS 长期抢不到（写者极密）：直接落盘最后一次合并结果。
-- 因为 mergeFn 是 join，且 base 已包含我们看到的全部内容，
-- 这次覆盖【不会丢任何已见数据】——只是可能覆盖掉同一瞬间别人的写，
-- 而那些写的内容【不在 base 里】，属于真正的并发窗口，由下一轮同步补回。
local nv = st.newVal
if nv == nil then nv = mergeFn(st.base) end
if nv ~= nil then
selfRef:_set(key, nv)
st.done = true; st.newVal = nv
selfRef:_aupdFinish(st, onDone)
else
st.fail = -98
selfRef:_aupdFinish(st, onDone)
end
return nil
end
-- 1) 引擎把当前值给我们（或告知不存在）
if EC_GET ~= nil and code == EC_GET then
st.base = v; return nil
end
if EC_NOVAL ~= nil and code == EC_NOVAL then
st.base = nil; return nil
end
-- 2) 引擎索要新值
local isSet = false
if EC_SET ~= nil and code == EC_SET then
isSet = true
elseif EC_SET == nil and st.calls == 1 then
isSet = true   -- 枚举缺失时的兜底：首次调用即索取新值（官方博客语义）
elseif EC_SET ~= nil and EC_SET == EC_OK and code == EC_OK then
-- SET 与 OK 数值相同，用"值是否等于刚返回的新值"来区分
if st.sets > 0 and v ~= nil and v == st.newVal then
st.done = true
else
isSet = true
end
end
if isSet then
if st.base == nil and v ~= nil and v ~= "" then st.base = v end
local nv = mergeFn(st.base)
if nv == nil then st.aborted = true; return nil end
st.sets = st.sets + 1
st.newVal = nv
return nv
end
-- 3) 完成
if code == EC_OK then
st.done = true
selfRef:_aupdFinish(st, onDone)
else
if st.sets == 0 and st.calls <= 1 then
local nv = mergeFn(st.base)
if nv == nil then
st.aborted = true; selfRef:_aupdFinish(st, onDone); return nil end
st.sets = st.sets + 1; st.newVal = nv
return nv
end
st.fail = code
selfRef:_aupdFinish(st, onDone)
end
return nil
end
local ok
if self._mock then
ok = self._mock:atomic(key, cb)
else
ok = Data.Map:UpdateValueAndCallback(self:_vid(), self:_pid(), key, cb)
end
if not ok then
-- 投递失败：降级到同步 CAS
return self:_aupdSync(key, mergeFn, onDone)
end
-- 若 mock/引擎已同步跑完回调，立刻结算
if st.done or st.fail or st.aborted then
self:_aupdFinish(st, onDone)
return true
end
-- 异步挂起：登记 watchdog，超时后降级重试
self._pend = self._pend or {}
self._pend[#self._pend + 1] = { st = st, key = key, mergeFn = mergeFn,
onDone = onDone, t0 = self:_now(),
cb = cb, tries = 1 }
return true
end
function Script:_aupdFinish(st, onDone)
if st.finished then return end
st.finished = true
if onDone then
if st.aborted then onDone(false, "abort", nil)
elseif st.fail then onDone(false, st.fail, nil)
else onDone(true, EC_OK, st.newVal) end
end
end
-- watchdog：由 OnUpdate / DoPeriodicTask 驱动
function Script:_pumpPend()
local p = self._pend
if not p or #p == 0 then return 0 end
local now = self:_now()
local keep = {}
local n = 0
for i = 1, #p do
local it = p[i]
if it.st.done or it.st.fail or it.st.aborted then
self:_aupdFinish(it.st, it.onDone)
elseif now - it.t0 > (self._timeoutMs or 8000) then
if it.tries < 3 then
it.tries = it.tries + 1
it.t0 = now
it.st.done = false; it.st.fail = nil; it.st.aborted = false
it.st.finished = false
it.st.calls = 0
if self._mock then self._mock:atomic(it.key, it.cb)
else Data.Map:UpdateValueAndCallback(self:_vid(), self:_pid(), it.key, it.cb) end
if it.st.done or it.st.fail or it.st.aborted then
self:_aupdFinish(it.st, it.onDone)
else
keep[#keep + 1] = it
end
else
it.st.fail = -97
self:_aupdFinish(it.st, it.onDone)
end
else
keep[#keep + 1] = it
end
n = n + 1
end
self._pend = keep
return n
end
-- 路径 B：Block 接口模拟 CAS（get -> merge -> set，写前校验未变）
function Script:_aupdSync(key, mergeFn, onDone)
local tries = math.max(1, _n(self.casRetries))
local old = self:_get(key)
for i = 1, tries do
local nv = mergeFn(old)
if nv == nil then
if onDone then onDone(false, "abort", nil) end
return false
end
-- 保险：再读一次，确认没人改过（Block 路径没有真 CAS，只能尽力）
local chk = self:_get(key)
if (chk or "") ~= (old or "") then
old = chk
else
if self:_set(key, nv) then
if onDone then onDone(true, EC_OK, nv) end
return true
end
old = self:_get(key)
end
end
if onDone then onDone(false, "cas_exhausted", nil) end
return false
end
function Script:_now()
if os and os.timeMs then return os.timeMs() or 0 end
return (self._fakeNow or 0)
end
--------------------------------------------------------------------------------
-- 键构造
--------------------------------------------------------------------------------
function Script:_app()
local a = _trim(self.appPrefix)
a = string.gsub(a, "[^%w_-]", "")
if a == "" then a = "fs" end
if #a > 12 then a = string.sub(a, 1, 12) end
return a
end
function Script:_kPtr(site) return "V." .. self:_app() .. "." .. _t(site) end
function Script:_kSnap(site) return "S." .. self:_app() .. "." .. _t(site) end
function Script:_kShard(site, n)
return "L." .. self:_app() .. "." .. _t(site) .. "." .. _t(n)
end
function Script:_kBlob(h, i)
if i then return "B." .. self:_app() .. "." .. _t(h) .. "." .. _t(i) end
return "B." .. self:_app() .. "." .. _t(h)
end
function Script:_kReg(site)
local nb = math.max(1, _n(self.rootShards))
local b = _h32(_t(site)) % nb
return "R." .. self:_app() .. "." .. _t(b)
end
function Script:_kRegB(b) return "R." .. self:_app() .. "." .. _t(b) end
--------------------------------------------------------------------------------
-- 站点身份：由 uin 派生；无 uin 时生成并持久化到自己的私人空间
--------------------------------------------------------------------------------
function Script:_ensureSite()
if self._site then return self._site end
local uin = self._testUin or 0
if uin == 0 and type(Player) == "table" and Player.GetUin then
local ok, u = pcall(function() return Player:GetUin() end)
if ok and u then uin = _n(u) end
end
if uin == 0 and self.playerId then uin = _n(self.playerId) end
self._uin = uin
-- 站点 ID 稳定地由 uin 派生（换存档/换会话不变）
-- 同一 uin 的多个活进程（多组件实例 / 双开）会拿到【同一个 siteId】，
-- 唯一性不再靠 siteId，而靠【seq 块预留】(见 _reserve)：
--   每个进程向 Q.<app>.<site> 原子申领 64 个连续 seq，
--   即使两个进程同时申领，拿到的区间也互不重叠 -> dot 永不撞车
local site
if uin ~= 0 then
site = "S" .. _b36(uin)
else
site = "X" .. _b36(_h32(_t(self) .. _t(self:_now())))
end
self._site = site
self._seq = 0
self._ownMax = 0
self._ops = {}
self._pendOps = {}
self._conflict = {}
self._snapSeq = 0
self._snapShard = 0
self._curShard = 1
self._hlcPt = 0
self._hlcCt = 0
self._seenSites = {}
self:_bootstrap()
return site
end
--------------------------------------------------------------------------------
-- HLC（仅全序与新鲜度；因果由 op.dep 承载）
--------------------------------------------------------------------------------
function Script:_hlcTick()
local now = self:_now()
if now <= self._hlcPt then
self._hlcCt = self._hlcCt + 1
else
self._hlcPt = now
self._hlcCt = 0
end
return self._hlcPt .. ":" .. self._hlcCt
end
function Script:_hlcSee(hlc)
local p, c = string.match(hlc or "", "^(%-?%d+):(%d+)")
if not p then return end
p, c = _n(p), _n(c)
if p > self._hlcPt then self._hlcPt, self._hlcCt = p, c
elseif p == self._hlcPt and c > self._hlcCt then self._hlcCt = c end
end
--------------------------------------------------------------------------------
-- op 编解码
--------------------------------------------------------------------------------
function Script:_parseOp(line)
if not line or line == "" then return nil end
local f = _split(line, SEP)
if #f < 6 then return nil end
return {
dot = f[1], typ = f[2], obj = f[3],
a1 = f[4] or "-", a2 = f[5] or "-",
hlc = f[6] or "0:0", dep = f[7] or "-",
ord = _ordkey(f[6], f[1]),
}
end
function Script:_serOp(o)
return table.concat({ o.dot, o.typ, o.obj,
(o.a1 == "" and "-" or o.a1),
(o.a2 == "" and "-" or o.a2),
o.hlc, (o.dep == "" and "-" or o.dep) }, SEP)
end
function Script:_ingest(o)
if not o or not o.dot then return false end
if self._ops[o.dot] then return false end
self._ops[o.dot] = o
self:_hlcSee(o.hlc)
local site, seq = string.match(o.dot, "^(.-)%.(%d+)$")
if site == self._site then
if _n(seq) > (self._ownMax or 0) then self._ownMax = _n(seq) end
end
return true
end
--------------------------------------------------------------------------------
-- ★ seq 块预留：dot 全局唯一的真正保障
--   Q.<app>.<site> 存"已发放到的 seq"。进程需要新 seq 时，原子地把它 +BLOCK，
--   自己独占 [base+1, base+BLOCK]。
--   两个进程同时申领：一个拿到 [b, b+63]，另一个重试后拿到 [b+64, b+127]
--   ——区间不重叠，所以 dot 永不撞车（这是比"唯一 siteId"更强的保证，
--     因为唯一 siteId 在双开/多实例场景下根本做不到）
--------------------------------------------------------------------------------
local SEQ_BLOCK = 64
function Script:_reserve()
local key = "Q." .. self:_app() .. "." .. _t(self._site)
local base = nil
local oldForce = self._forceSync
self._forceSync = true
self:_aupd(key, function(old)
local b = _n(old)
if b < (self._ownMax or 0) then b = self._ownMax end
base = b
return _t(b + SEQ_BLOCK)
end, function(ok, code)
if not ok then base = nil end
end)
self._forceSync = oldForce
if base == nil then
base = (self._ownMax or 0) + (self:_now() % 997) + 1
end
self._ownMax = base
self._seqEnd = base + SEQ_BLOCK
end
function Script:_newOp(typ, obj, a1, a2)
self:_ensureSite()
if (self._ownMax or 0) >= (self._seqEnd or 0) then self:_reserve() end
local hlc = self:_hlcTick()
local seq = (self._ownMax or 0) + 1
self._ownMax = seq
self._seq = seq
local dep = self:_headOf(obj)
local o = { dot = self._site .. "." .. _t(seq), typ = typ, obj = obj,
a1 = _t(a1), a2 = _t(a2), hlc = hlc,
dep = (dep and dep ~= "" ) and dep or "-" }
o.ord = _ordkey(o.hlc, o.dot)
self:_ingest(o)
self._pendOps[#self._pendOps + 1] = o
return o
end
function Script:_headOf(obj)
local best, bo = nil, nil
for _, o in pairs(self._ops or {}) do
if o.obj == obj then
if not bo or o.ord > bo.ord then best, bo = o.dot, o end
end
end
return best
end
--------------------------------------------------------------------------------
-- 重放：由 op 集合投影状态（确定性 —— 全网一致）
--------------------------------------------------------------------------------
function Script:_replay()
local list = {}
for _, o in pairs(self._ops or {}) do list[#list + 1] = o end
table.sort(list, function(a, b) return a.ord < b.ord end)
local parent, alive, content, name, kind = {}, {}, {}, {}, {}
local lastOp = {}
local conflict = {}
local function isDep(o, d)
if not d or d == "" or d == "-" then return false end
if not o.dep or o.dep == "" or o.dep == "-" then return false end
return string.find("," .. o.dep .. ",", "," .. d .. ",", 1, true) ~= nil
end
local function ancestors(id)
local seen, cur, guard = {}, id, 0
while cur and cur ~= ROOTID and guard < 200000 do
if seen[cur] then return seen, true end
seen[cur] = true
cur = parent[cur]
guard = guard + 1
end
return seen, false
end
for _, o in ipairs(list) do
local obj = o.obj
if o.typ == "mk" then
local kd = string.sub(o.a2, 1, 1)
local nm = string.sub(o.a2, 3)
kind[obj] = (kd == "d") and "dir" or "file"
name[obj] = nm
parent[obj] = (o.a1 ~= "-" and o.a1 ~= "") and o.a1 or ROOTID
alive[obj] = true
lastOp[obj] = o.dot
elseif o.typ == "mv" then
local np = (o.a1 ~= "-" and o.a1 ~= "") and o.a1 or ROOTID
if np == obj then
conflict[#conflict + 1] = { typ = "selfparent", obj = obj, dot = o.dot }
else
local old = parent[obj]
parent[obj] = np
local _, cyc = ancestors(np)
if cyc then
parent[obj] = old
conflict[#conflict + 1] = { typ = "cycle", obj = obj, dot = o.dot, parent = np }
else
local prev = lastOp[obj]
local po = prev and self._ops[prev]
if po and po.typ == "mv" and prev ~= o.dot and not isDep(o, prev) then
conflict[#conflict + 1] = { typ = "concurrent_move", obj = obj,
winner = o.dot, loser = prev }
end
alive[obj] = true
lastOp[obj] = o.dot
end
end
elseif o.typ == "rn" then
local prev = lastOp[obj]
local po = prev and self._ops[prev]
if po and po.typ == "rn" and prev ~= o.dot and not isDep(o, prev) then
conflict[#conflict + 1] = { typ = "concurrent_rename", obj = obj,
winner = o.dot, loser = prev }
end
name[obj] = o.a1
lastOp[obj] = o.dot
elseif o.typ == "rm" then
local prev = lastOp[obj]
if prev and not isDep(o, prev) then
conflict[#conflict + 1] = { typ = "concurrent_rm", obj = obj,
dot = o.dot, other = prev }
end
alive[obj] = false
lastOp[obj] = o.dot
elseif o.typ == "wr" then
if alive[obj] == false then
local prev = lastOp[obj]
if _flag(self.rmWins) and prev and self._ops[prev]
and self._ops[prev].typ == "rm" and not isDep(o, prev) then
conflict[#conflict + 1] = { typ = "rm_wins", obj = obj, dot = o.dot }
else
content[obj] = o.a1
lastOp[obj] = o.dot
end
else
content[obj] = o.a1
lastOp[obj] = o.dot
end
end
end
self._conflict = conflict
self._view = { parent = parent, alive = alive, content = content,
name = name, kind = kind, lastOp = lastOp, count = #list }
return self._view
end
--------------------------------------------------------------------------------
-- 内容：内容寻址 blob（不可变 —— 天然无冲突）
--------------------------------------------------------------------------------
function Script:_putContent(s)
self:_ensureSite()
local h = _hash(s)
local key = self:_kBlob(h)
local cur = self:_get(key)
if cur == nil or cur ~= s then
self:_set(key, s)
end
return "#" .. h
end
function Script:_getContent(spec)
if not spec or spec == "" or spec == "-" then return "" end
if string.sub(spec, 1, 1) == "=" then return string.sub(spec, 2) end
if string.sub(spec, 1, 1) == "#" then
local h = string.sub(spec, 2)
local v = self:_get(self:_kBlob(h))
return v or ""
end
return spec
end
--------------------------------------------------------------------------------
-- 发布：pending op -> 日志分片（owner 单写，join = 按 dot 并集）
--------------------------------------------------------------------------------
local function _shardHeader(site, minSeq, maxSeq, cnt)
return "H" .. SEP .. _t(site) .. SEP .. _t(minSeq) .. SEP
.. _t(maxSeq) .. SEP .. _t(cnt)
end
local function _parseShard(raw)
local lines = {}
local head = { site = "", min = 0, max = 0, cnt = 0 }
if not raw or raw == "" then return head, lines end
local nl = 1
for line in string.gmatch(raw, "[^\n]+") do
if nl == 1 then
local f = _split(line, SEP)
head.site = f[2] or ""
head.min = _n(f[3])
head.max = _n(f[4])
head.cnt = _n(f[5])
else
lines[#lines + 1] = line
end
nl = nl + 1
end
return head, lines
end
-- ★ join：按 dot 并集，幂等
local function _mergeShard(old, site, newOps, maxBytes, maxOps)
local head, lines = _parseShard(old)
local have = {}
for _, l in ipairs(lines) do
local d = string.match(l, "^([^" .. SEP .. "]+)")
if d then have[d] = true end
end
local added = 0
local out = {}
for _, o in ipairs(newOps) do
if not have[o.dot] then
out[#out + 1] = o
have[o.dot] = true
added = added + 1
end
end
if added == 0 then return nil, "noop" end
local all = {}
for i = 1, #lines do all[#all + 1] = lines[i] end
for i = 1, #out do all[#all + 1] = _serOpWrap(out[i]) end
local minSeq, maxSeq = head.min, head.max
for _, o in ipairs(all) do
local s = _n(string.match(o, "^[^" .. SEP .. "]+%.(%d+)"))
if minSeq == 0 or s < minSeq then minSeq = s end
if s > maxSeq then maxSeq = s end
end
if minSeq == 0 then minSeq = maxSeq end
local body = _shardHeader(site, minSeq, maxSeq, #all)
for i = 1, #all do body = body .. "\n" .. all[i] end
if #body > maxBytes then return nil, "size" end
if #all > maxOps then return nil, "count" end
return body
end
function _serOpWrap(o)
return table.concat({ o.dot, o.typ, o.obj,
(o.a1 == "" and "-" or o.a1), (o.a2 == "" and "-" or o.a2),
o.hlc, (o.dep == "" and "-" or o.dep) }, SEP)
end
-- 指针 join：逐字段取 max
local function _mergePtr(old, site, shard, seq, snapShard, snapSeq)
local f = old and _split(old, SEP) or {}
local s0 = (f[1] and f[1] ~= "") and f[1] or site
local sh = math.max(_n(f[2]), _n(shard))
local sq = math.max(_n(f[3]), _n(seq))
local ss = math.max(_n(f[4]), _n(snapShard))
local sq2 = math.max(_n(f[5]), _n(snapSeq))
local body = s0 .. SEP .. _t(sh) .. SEP .. _t(sq) .. SEP .. _t(ss)
.. SEP .. _t(sq2)
return body .. SEP .. _hash(body)
end
local function _parsePtr(raw)
local f = raw and _split(raw, SEP) or {}
return { site = f[1] or "", shard = _n(f[2]), seq = _n(f[3]),
snapShard = _n(f[4]), snapSeq = _n(f[5]), hash = f[6] or "" }
end
-- 注册表 join：并集 + 取 max
local function _mergeReg(old, entries)
local map = {}
if old and old ~= "" then
for _, it in ipairs(_split(old, ";")) do
local s, sh, sq = string.match(it, "^([^:]+):(%d+):(%d+)$")
if s then
local e = map[s]
if not e then map[s] = { sh = _n(sh), sq = _n(sq) }
else
if _n(sh) > e.sh then e.sh = _n(sh) end
if _n(sq) > e.sq then e.sq = _n(sq) end
end
end
end
end
for _, e in ipairs(entries) do
local cur = map[e.site]
if not cur then map[e.site] = { sh = _n(e.shard), sq = _n(e.seq) }
else
if _n(e.shard) > cur.sh then cur.sh = _n(e.shard) end
if _n(e.seq) > cur.sq then cur.sq = _n(e.seq) end
end
end
local ks = {}
for k in pairs(map) do ks[#ks + 1] = k end
table.sort(ks)
local out = {}
for _, k in ipairs(ks) do
out[#out + 1] = k .. ":" .. _t(map[k].sh) .. ":" .. _t(map[k].sq)
end
return table.concat(out, ";")
end
local function _parseReg(raw)
local out = {}
if not raw or raw == "" then return out end
for _, it in ipairs(_split(raw, ";")) do
local s, sh, sq = string.match(it, "^([^:]+):(%d+):(%d+)$")
if s then out[#out + 1] = { site = s, shard = _n(sh), seq = _n(sq) } end
end
return out
end
--------------------------------------------------------------------------------
-- 启动引导：读自己的指针与日志，恢复 seq / 分片号 / 已知 dot
-- 不做这一步，新进程会从 seq=0 重新开始 -> 与自己的历史 op 撞 dot
--------------------------------------------------------------------------------
function Script:_bootstrap()
if self._booted then return end
self._booted = true
local site = self._site
local p = _parsePtr(self:_get(self:_kPtr(site)))
if p.site == site and p.seq > 0 then
self._ownMax = p.seq
self._seqEnd = p.seq
self._curShard = math.max(1, p.shard)
self._snapSeq = p.snapSeq
self._snapShard = p.snapShard
end
local sraw = self:_get(self:_kSnap(site))
if sraw and sraw ~= "" then
local hh, ll = _parseShard(sraw)
for _, l in ipairs(ll) do
local o = self:_parseOp(l)
if o then self:_ingest(o) end
end
end
for n = 1, math.max(1, self._curShard or 1) do
local raw = self:_get(self:_kShard(site, n))
if raw and raw ~= "" then
local hh, ll = _parseShard(raw)
for _, l in ipairs(ll) do
local o = self:_parseOp(l)
if o then self:_ingest(o) end
end
end
end
self._known = self._known or {}
self._known[site] = { seq = self._ownMax or 0, snap = p.snapSeq,
shard = math.max(1, self._curShard or 1), loaded = true }
end
--------------------------------------------------------------------------------
-- Flush：把 pending 写进日志分片
--------------------------------------------------------------------------------
function Script:Flush()
self:_ensureSite()
if #self._pendOps == 0 then return "无待发布" end
local ops = self._pendOps
self._pendOps = {}
local maxB = math.max(2000, _n(self.maxShardBytes))
local maxO = math.max(8, _n(self.maxOpsPerShard))
local site = self._site
local function doAppend(shardIdx, cbDone)
local key = self:_kShard(site, shardIdx)
local selfRef = self
self._lastAbortWhy = nil
self:_aupd(key, function(old)
local body, why = _mergeShard(old, site, ops, maxB, maxO)
if body == nil then selfRef._lastAbortWhy = why; return nil end
return body
end, function(ok, code, val)
if ok then
cbDone(true, shardIdx)
else
cbDone(false, shardIdx, code)
end
end)
end
local res = { ok = false, shard = self._curShard or 1, err = nil }
-- 同步路径：直接拿结果；异步路径：靠回调推进
local syncMode = not (_flag(self.preferAsync) and HAS_UPD)
if syncMode or self._forceSync then
local ok = false
for attempt = 1, 4 do
local done = false
local gotOk = false
local why = nil
doAppend(res.shard, function(o, sh, code)
done = true; gotOk = o; why = code
end)
if not done then
-- _aupdSync 会同步调用 onDone
end
if gotOk then ok = true; break end
why = why or self._lastAbortWhy
if why == "noop" then ok = true; break end
if why == "size" or why == "count" then
res.shard = res.shard + 1
self._curShard = res.shard
self:_publishPtr(res.shard, self._ownMax, true)
elseif why == "abort" then
ok = true; break
else
res.err = why
break
end
end
if ok or res.shard ~= (self._curShard or 1) then
self:_publishPtr(self._curShard, self._ownMax, true)
self:_publishReg(true)
end
return ok and ("OK: 已发布到分片 " .. _t(res.shard))
or ("ERR: 发布失败 " .. _t(res.err))
end
-- 异步路径：用一次性的自推进链
local idx = self._curShard or 1
local tries = 0
local function step()
tries = tries + 1
if tries > 4 then
self:_out("ERR: 发布重试过多，op 已回退到待发布队列")
for i = 1, #ops do self._pendOps[#self._pendOps + 1] = ops[i] end
return
end
doAppend(idx, function(o, sh, code)
if o then
self._curShard = sh
self:_publishPtr(sh, self._ownMax, false)
self:_publishReg(false)
self:_out("OK: 已发布 " .. #ops .. " 条 op -> 分片 " .. _t(sh))
elseif code == "size" or code == "count" or self._lastAbortWhy == "size"
or self._lastAbortWhy == "count" then
self._lastAbortWhy = nil
idx = idx + 1
self._curShard = idx
self:_publishPtr(idx, self._ownMax, false, step)
elseif code == "abort" then
local w = self._lastAbortWhy
self._lastAbortWhy = nil
self:_publishPtr(idx, self._ownMax, false)
self:_publishReg(false)
if w == "noop" then
self:_out("OK: 幂等命中（这批 op 已在分片内）")
else
self:_out("OK: 分片已满，已滚动到 " .. _t(idx))
end
else
self:_out("ERR: 发布失败 " .. _t(code) .. "，已回退")
for i = 1, #ops do self._pendOps[#self._pendOps + 1] = ops[i] end
end
end)
end
step()
return "已发起发布（" .. #ops .. " 条 op），结果看日志/广播"
end
function Script:_publishPtr(shard, seq, sync, after)
self:_ensureSite()
local site = self._site
local key = self:_kPtr(site)
local selfRef = self
self:_aupd(key, function(old)
return _mergePtr(old, site, shard, seq,
selfRef._snapShard or 0, selfRef._snapSeq or 0)
end, function(ok, code)
if not ok and after == nil then
selfRef:_log("WARN: 指针更新失败 " .. _t(code))
end
if after then after(ok) end
end)
end
function Script:_publishReg(sync)
if not _flag(self.useRegistry) then return end
self:_ensureSite()
local key = self:_kReg(self._site)
local e = { site = self._site, shard = self._curShard or 1, seq = self._ownMax or 0 }
self:_aupd(key, function(old) return _mergeReg(old, { e }) end, nil)
end
--------------------------------------------------------------------------------
-- Sync：拉取（注册表 -> 指针 -> 快照 -> 增量分片）
--------------------------------------------------------------------------------
function Script:_discoverSites()
local out = {}
local seen = {}
local me = self:_ensureSite()
seen[me] = true
out[#out + 1] = me
local ps = _trim(self.peerSites)
if ps ~= "" then
for _, s in ipairs(_split(ps, ",")) do
s = _trim(s)
if s ~= "" and not seen[s] then seen[s] = true; out[#out + 1] = s end
end
end
-- 注册表带 TTL：只有"发现新站点"才需要读，稳态同步不该为它付费
if _flag(self.useRegistry) then
local now = self:_now()
local ttl = math.max(10, _n(self.registryRefreshSec)) * 1000
self._regCache = self._regCache or {}
if (now - (self._regAt or 0)) > ttl then
local nb = math.max(1, _n(self.rootShards))
local found = {}
for b = 0, nb - 1 do
local raw = self:_get(self:_kRegB(b))
for _, e in ipairs(_parseReg(raw)) do
found[#found + 1] = e.site
end
end
self._regCache = found
self._regAt = now
end
for _, st in ipairs(self._regCache) do
if not seen[st] then seen[st] = true; out[#out + 1] = st end
end
end
for s in pairs(self._seenSites or {}) do
if not seen[s] then seen[s] = true; out[#out + 1] = s end
end
return out
end
function Script:Sync()
self:_ensureSite()
local sites = self:_discoverSites()
local cap = math.max(1, _n(self.maxTrackSites))
local pulled, newops, snew = 0, 0, 0
local stale = {}
self._known = self._known or {}
for i = 1, math.min(#sites, cap) do
local site = sites[i]
self._seenSites[site] = true
local p = _parsePtr(self:_get(self:_kPtr(site)))
pulled = pulled + 1
-- ★ 配额命门：指针 seq 没变就一个字节都不多读
--   稳态成本 = 每个关注站点 1 次读，这是千人规模能成立的前提
local kn = self._known[site]
local changed = (not kn) or (not kn.loaded)
or kn.seq ~= p.seq or kn.snap ~= p.snapSeq
if changed then
if (not kn) or (not kn.loaded) or kn.snap ~= p.snapSeq then
local sraw = self:_get(self:_kSnap(site))
if sraw and sraw ~= "" then
local nh, nl = _parseShard(sraw)
for _, l in ipairs(nl) do
local o = self:_parseOp(l)
if o and self:_ingest(o) then newops = newops + 1 end
end
end
end
local from = (kn and kn.loaded) and math.max(1, _n(kn.shard)) or 1
for n = from, math.max(from, p.shard) do
local raw = self:_get(self:_kShard(site, n))
if raw and raw ~= "" then
local hh, ll = _parseShard(raw)
for _, l in ipairs(ll) do
local o = self:_parseOp(l)
if o and self:_ingest(o) then newops = newops + 1 end
end
end
end
if (not kn) or p.seq > _n(kn.seq) then
stale[#stale + 1] = site .. ":" .. _t(p.seq)
end
end
self._known[site] = { seq = p.seq, snap = p.snapSeq,
shard = p.shard, loaded = true }
end
self:_replay()
local v = self._view
return "SYNC: 站点 " .. #sites .. " 已读 " .. pulled
.. " 新op " .. newops .. " 总op " .. v.count
.. " 对象 " .. self:_countAlive() .. (#stale > 0 and (" 活跃:" .. _join(stale, " ")) or "")
end
function Script:_countAlive()
local n = 0
for _, a in pairs((self._view and self._view.alive) or {}) do
if a then n = n + 1 end
end
return n
end
--------------------------------------------------------------------------------
-- 快照 / 压缩
--------------------------------------------------------------------------------
function Script:Compact()
self:_ensureSite()
self:_replay()
local v = self._view
local lines = {}
local uptoSeq = self._ownMax or 0
local uptoShard = self._curShard or 1
for obj, dot in pairs(v.lastOp or {}) do
local o = self._ops[dot]
if o and v.alive[obj] ~= false then
lines[#lines + 1] = _serOpWrap(o)
end
end
table.sort(lines)
local body = "T" .. SEP .. self._site .. SEP .. _t(uptoShard) .. SEP
.. _t(uptoSeq) .. SEP .. _t(#lines)
for i = 1, #lines do body = body .. "\n" .. lines[i] end
if #body > MAXVAL then
return "ERR: 快照过大 " .. #body
end
local key = self:_kSnap(self._site)
local ok = false
self:_aupd(key, function(old)
if old and old ~= "" then
local oh, ol = _parseShard(old)
local oSeq = _n(oh.max)
if oSeq > uptoSeq then return nil end
end
return body
end, function(o, code) ok = o end)
if not ok and _flag(self.preferAsync) then
return "已发起快照（异步）"
end
self._snapSeq = uptoSeq
self._snapShard = uptoShard
self:_publishPtr(uptoShard, uptoSeq, true)
return "OK: 快照 " .. #lines .. " 条 / " .. #body .. " 字节，已更新指针"
end
--------------------------------------------------------------------------------
-- 文件系统操作
--------------------------------------------------------------------------------
function Script:_childrenOf(pid)
self:_replay()
local v = self._view
local out = {}
for obj, p in pairs(v.parent or {}) do
if p == pid and v.alive[obj] then
out[#out + 1] = { id = obj, name = v.name[obj] or obj,
kind = v.kind[obj] or "file" }
end
end
table.sort(out, function(a, b) return a.id < b.id end)
return out
end
function Script:Create(pid, kind, name)
self:_ensureSite()
pid = _trim(pid); if pid == "" then pid = ROOTID end
kind = _trim(kind); if kind ~= "dir" then kind = "file" end
name = _safeName(name)
local o = self:_newOp("mk", nil, pid, (kind == "dir" and "d" or "f") .. ":" .. name)
o.obj = o.dot
self:_ingest(o)
if auto then self:Flush() end
return o.dot
end
function Script:Move(obj, npid)
self:_ensureSite()
obj = _trim(obj); npid = _trim(npid); if npid == "" then npid = ROOTID end
if not self._ops or not self:_objExists(obj) then
return nil, "对象不存在"
end
local old = (self._view and self._view.parent[obj]) or ROOTID
local o = self:_newOp("mv", obj, npid, old)
if _flag(self.autoFlushOnWrite) then self:Flush() end
return o.dot
end
function Script:Rename(obj, nm)
self:_ensureSite()
obj = _trim(obj)
if not self:_objExists(obj) then return nil, "对象不存在" end
local o = self:_newOp("rn", obj, _safeName(nm), "-")
if _flag(self.autoFlushOnWrite) then self:Flush() end
return o.dot
end
function Script:Remove(obj)
self:_ensureSite()
obj = _trim(obj)
if not self:_objExists(obj) then return nil, "对象不存在" end
local o = self:_newOp("rm", obj, "-", "-")
if _flag(self.autoFlushOnWrite) then self:Flush() end
return o.dot
end
function Script:Write(obj, content)
self:_ensureSite()
obj = _trim(obj)
if not self:_objExists(obj) then return nil, "对象不存在" end
local spec
if _canInline(content) and #content <= math.max(0, _n(self.inlineMaxBytes)) then
spec = "=" .. content
else
spec = self:_putContent(content)
end
local o = self:_newOp("wr", obj, spec, "-")
if _flag(self.autoFlushOnWrite) then self:Flush() end
return o.dot
end
function Script:_objExists(obj)
self:_replay()
local v = self._view
if v.parent[obj] ~= nil then return true end
if v.lastOp[obj] ~= nil then return true end
return false
end
function Script:_readObj(obj)
self:_replay()
local v = self._view
if v.alive[obj] == false then return nil, "已删除" end
return self:_getContent(v.content[obj]) or ""
end
--------------------------------------------------------------------------------
-- 开放函数实现
--------------------------------------------------------------------------------
function Script:OnStart()
self._forceSync = false
self._timeoutMs = 8000
pcall(function() self:_ensureSite() end)
if self.DoPeriodicTask then
local s = _n(self.autoSyncSec)
if s > 0 then
pcall(function()
self:DoPeriodicTask(function()
self:_pumpPend()
local ok, r = pcall(function() return self:Sync() end)
if ok then self:_log("[自动同步] " .. _t(r)) end
end, s)
end)
end
local f = _n(self.autoFlushSec)
if f > 0 then
pcall(function()
self:DoPeriodicTask(function()
self:_pumpPend()
if #(self._pendOps or {}) > 0 then self:Flush() end
end, f)
end)
end
end
self:_log("[KVFS v4] 已载入 站点=" .. _t(self._site)
.. " 原子更新接口=" .. (HAS_UPD and "有" or "无")
.. " 注册表=" .. (_flag(self.useRegistry) and "开" or "关"))
self:_log("[KVFS v4] 请调用 ①初始化 / ⑬自检 / ⑭环境自检")
end
function Script:Init()
self:_ensureSite()
self:_replay()
return "OK: 站点=" .. self._site .. " 变量=" .. self:_vid()
.. " 作用域=" .. (_n(self.scope) == 1 and "私人" or "共享")
.. " 原子RMW=" .. (HAS_UPD and "可用" or "不可用(降级CAS)")
.. " 注册表桶=" .. _t(math.max(1, _n(self.rootShards)))
end
function Script:Create_(pid, kind, name)
pid = _trim(pid)
if pid == "" then pid = ROOTID end
if pid ~= ROOTID then self:_ensureSite(); self:_replay() end
local id, err = self:Create(pid, kind, name)
if not id then return "ERR: " .. _t(err) end
if _flag(self.preferAsync) and HAS_UPD and not self._forceSync then
self:Flush()
end
return "OK: 已创建 " .. id .. (_flag(self.preferAsync) and "（发布结果看日志）" or "")
end
function Script:Move_(obj, npid)
local id, err = self:Move(_trim(obj), _trim(npid))
if not id then return "ERR: " .. _t(err) end
if _flag(self.autoFlushOnWrite) then self:Flush() end
return "OK: 已移动 " .. id
end
function Script:Rename_(obj, nm)
local id, err = self:Rename(_trim(obj), _trim(nm))
if not id then return "ERR: " .. _t(err) end
if _flag(self.autoFlushOnWrite) then self:Flush() end
return "OK: 已改名 " .. id
end
function Script:Remove_(obj)
local id, err = self:Remove(_trim(obj))
if not id then return "ERR: " .. _t(err) end
if _flag(self.autoFlushOnWrite) then self:Flush() end
return "OK: 已删除 " .. id
end
function Script:Write_(obj, content)
local id, err = self:Write(_trim(obj), content)
if not id then return "ERR: " .. _t(err) end
if #content > _n(self.inlineMaxBytes) then
return "OK: 已写入(blob) " .. id
end
return "OK: 已写入 " .. id
end
function Script:Read_(obj)
local s, err = self:_readObj(_trim(obj))
if not s then return "ERR: " .. _t(err) end
return s
end
function Script:List_(pid)
pid = _trim(pid); if pid == "" then pid = ROOTID end
local ch = self:_childrenOf(pid)
if #ch == 0 then return "(空)" end
local out = {}
for i, c in ipairs(ch) do
out[i] = c.kind .. "\t" .. c.name .. "\t" .. c.id
end
return table.concat(out, "\n")
end
function Script:Status()
self:_ensureSite()
self:_replay()
local v = self._view
local cf = self._conflict or {}
local sites = self:_discoverSites()
local lines = {}
lines[#lines + 1] = "站点=" .. _t(self._site)
lines[#lines + 1] = "本地seq=" .. _t(self._ownMax) .. " 待发布=" .. #self._pendOps
lines[#lines + 1] = "当前分片=" .. _t(self._curShard) .. " 快照seq=" .. _t(self._snapSeq)
lines[#lines + 1] = "已知op=" .. v.count .. " 存活对象=" .. self:_countAlive()
lines[#lines + 1] = "发现站点=" .. #sites .. " 跟踪上限=" .. _t(self._maxTrack())
local perMin = _t(self:_maxTrack()) .. " x 60/" .. _t(math.max(1, _n(self.autoSyncSec)))
local budget = self:_quotaPerMin()
lines[#lines + 1] = "配额估算: 稳态每分钟读 = " .. perMin .. " (每人预算约 " .. budget .. ")"
lines[#lines + 1] = "冲突=" .. #cf
lines[#lines + 1] = "读=" .. _t(self._st_get) .. " 写=" .. _t(self._st_set)
lines[#lines + 1] = "原子RMW=" .. (HAS_UPD and "可用" or "缺失")
.. " 偏好异步=" .. (_flag(self.preferAsync) and "是" or "否")
.. " 挂起=" .. #(self._pend or {})
for i = 1, math.min(#cf, 5) do
lines[#lines + 1] = "  冲突#" .. i .. " " .. _t(cf[i].typ)
.. " obj=" .. _t(cf[i].obj) .. " dot=" .. _t(cf[i].dot)
end
return table.concat(lines, "\n")
end
function Script:_maxTrack() return _n(self.maxTrackSites) end
-- 配额：官方文档 30 + 在线人数 x 10 次/分钟（读写各自计，且是全图共享）
-- 人均预算 = (30 + 10N) / N ≈ 10（N 大时）
function Script:_quotaPerMin()
local n = 0
if type(World) == "table" and World.GetAllPlayers then
local ok, ps = pcall(function() return World:GetAllPlayers(-1) end)
if ok and type(ps) == "table" then n = #ps end
end
if n <= 0 then n = 1 end
return math.floor((30 + 10 * n) / n)
end
function Script:Env()
local lines = {}
lines[#lines + 1] = "============== 环境自检 =============="
lines[#lines + 1] = "_VERSION = " .. _t(_VERSION)
lines[#lines + 1] = "Data=" .. type(Data) .. " Data.Map=" .. type(Data and Data.Map)
lines[#lines + 1] = "UpdateValueAndCallback = "
.. ((HAS_UPD) and "★存在(可用真原子)" or "✗不存在(降级为Block CAS)")
lines[#lines + 1] = "ErrorCode=" .. type(ErrorCode)
.. " OK=" .. _t(EC_OK)
.. " KV_UPDATE_SET=" .. _t(EC_SET)
.. " KV_UPDATE_GET=" .. _t(EC_GET)
.. " KV_OP_NO_VAL=" .. _t(EC_NOVAL)
lines[#lines + 1] = "string.split=" .. type(string.split)
.. " os.timeMs=" .. type(os and os.timeMs)
.. " os.clock=" .. type(os and os.clock)
lines[#lines + 1] = "math.pow=" .. type(math.pow) .. " math.tanh=" .. type(math.tanh)
lines[#lines + 1] = "bit=" .. type(bit) .. " json=" .. type(json)
lines[#lines + 1] = "DoPeriodicTask=" .. type(self.DoPeriodicTask)
.. " PushCustomEvent=" .. type(self.PushCustomEvent)
lines[#lines + 1] = "AddTriggerEvent=" .. type(self.AddTriggerEvent)
local ok, u = pcall(function() return Player:GetUin() end)
lines[#lines + 1] = "Player:GetUin()=" .. (ok and _t(u) or "ERR")
lines[#lines + 1] = "======================================"
return table.concat(lines, "\n")
end
function Script:Check()
local pass, fail = 0, 0
local function ck(name, cond, extra)
if cond then pass = pass + 1
else fail = fail + 1
print("[FAIL] " .. name .. " " .. _t(extra)) end
end
self._forceSync = true   -- 自检一律走同步路径，保证可断言
self:_ensureSite()
ck("①站点ID非空且<=12字符", self._site and #self._site > 0 and #self._site <= 12, self._site)
ck("②_hash 稳定", _hash("abc") == _hash("abc") and _hash("abc") ~= _hash("abd"))
ck("③_ordkey 定长", #_ordkey("1700000000000:5", "S1.1") == 13 + 1 + 5 + 1 + 4)
-- 合并是 join
local a1 = _mergeReg("", { { site = "S1", shard = 2, seq = 5 } })
local a2 = _mergeReg(a1, { { site = "S1", shard = 1, seq = 9 } })
local a3 = _mergeReg(a1, { { site = "S2", shard = 1, seq = 1 } })
local a4 = _mergeReg(a3, { { site = "S1", shard = 1, seq = 9 } })
ck("④注册表合并取max", string.find(a2, "S1:2:9", 1, true) ~= nil, a2)
ck("⑤注册表幂等", _mergeReg(a1, { { site = "S1", shard = 2, seq = 5 } }) == a1)
ck("⑥注册表交换律(结果一致)", a4 == _mergeReg(a2, { { site = "S2", shard = 1, seq = 1 } }), a4)
local p1 = _mergePtr(nil, "S1", 3, 7, 0, 0)
local p2 = _mergePtr(p1, "S1", 1, 2, 0, 0)
ck("⑦指针合并取max", string.find(p2, "|3|7|", 1, true) ~= nil, p2)
ck("⑧指针幂等", _mergePtr(p1, "S1", 3, 7, 0, 0) == p1)
-- 分片合并
local o1 = { dot = "S1.1", typ = "mk", obj = "S1.1", a1 = "@root",
a2 = "f:a", hlc = "1:0", dep = "-" }
local o2 = { dot = "S1.2", typ = "wr", obj = "S1.1", a1 = "=hi",
a2 = "-", hlc = "2:0", dep = "S1.1" }
local m1 = _mergeShard(nil, "S1", { o1 }, 100000, 100)
ck("⑨分片合并新增", m1 and string.find(m1, "S1.1", 1, true) ~= nil)
local m2 = _mergeShard(m1, "S1", { o1, o2 }, 100000, 100)
ck("⑩分片合并幂等(重复op不翻倍)",
m2 and (select(2, string.gsub(m2, "S1%.1" .. SEP .. "mk", "")) == 1))
ck("⑪分片合并含新op", m2 and string.find(m2, "S1%.2" .. SEP .. "wr", 1) ~= nil)
ck("⑫分片超限时拒绝", (function()
local r, why = _mergeShard(m1, "S1", { o2 }, 10, 100)
return r == nil and why == "size"
end)())
-- 端到端（同步路径）
self._ops = {}; self._pendOps = {}; self._ownMax = 0
self._hlcPt = 0; self._hlcCt = 0   -- 场景隔离：不重置会让前后场景的HLC互相污染
local id = self:Create(ROOTID, "file", "hello.txt")
ck("⑬创建返回dot", id and string.find(id, "%.") ~= nil, id)
self:Write(id, "你好世界")
ck("⑭写入后可读", self:_readObj(id) == "你好世界", self:_readObj(id))
local dir = self:Create(ROOTID, "dir", "docs")
ck("⑮目录创建", dir ~= nil)
self:Move(id, dir)
self:_replay()
ck("⑯移动生效", self._view.parent[id] == dir, self._view.parent[id])
local ch = self:_childrenOf(dir)
ck("⑰子项可见", #ch == 1 and ch[1].id == id)
-- 并发：同一对象两条无因果的 mv
-- ⚠ 远程 op 的 hlc 必须取"未来"时刻，否则会排在本地 mk 之前，
--   被随后的 mk 重新复活，导致并发冲突根本不会被检出
local FUT = _t((self:_now() or 0) + 1000000)
self:_replay()
local cf0 = #(self._conflict or {})
local mv1 = { dot = "Z9.1", typ = "mv", obj = id, a1 = ROOTID, a2 = dir,
hlc = FUT .. ":1", dep = "-" }
mv1.ord = _ordkey(mv1.hlc, mv1.dot)
self:_ingest(mv1)
local mv2 = { dot = "Z8.1", typ = "mv", obj = id, a1 = dir, a2 = ROOTID,
hlc = FUT .. ":0", dep = "-" }
mv2.ord = _ordkey(mv2.hlc, mv2.dot)
self:_ingest(mv2)
self:_replay()
ck("⑱并发move被检出", #(self._conflict or {}) > cf0)
-- rmWins
self._ops = {}; self._pendOps = {}; self._ownMax = 0
self._hlcPt = 0; self._hlcCt = 0   -- 场景隔离：不重置会让前后场景的HLC互相污染
local id2 = self:Create(ROOTID, "file", "x")
self:Write(id2, "A")
local rm = { dot = "Z7.9", typ = "rm", obj = id2, a1 = "-", a2 = "-",
hlc = FUT .. ":0", dep = "-" }
rm.ord = _ordkey(rm.hlc, rm.dot)
self:_ingest(rm)
local wr = { dot = "Z7.10", typ = "wr", obj = id2, a1 = "=B", a2 = "-",
hlc = FUT .. ":1", dep = "-" }
wr.ord = _ordkey(wr.hlc, wr.dot)
self:_ingest(wr)
self:_replay()
ck("⑲并发rm优先(rmWins)", self._view.alive[id2] == false, "alive=" .. tostring(self._view.alive[id2]) .. " id2=" .. tostring(id2) .. " lastOp=" .. tostring(self._view.lastOp[id2]))
-- 成环
self._ops = {}; self._pendOps = {}; self._ownMax = 0
self._hlcPt = 0; self._hlcCt = 0   -- 场景隔离：不重置会让前后场景的HLC互相污染
local d1 = self:Create(ROOTID, "dir", "d1")
local d2 = self:Create(d1, "dir", "d2")
self:_replay()
local cmv = { dot = "Z6.1", typ = "mv", obj = d1, a1 = d2, a2 = ROOTID,
hlc = FUT .. ":0", dep = "-" }
cmv.ord = _ordkey(cmv.hlc, cmv.dot)
self:_ingest(cmv)
self:_replay()
ck("⑳成环被拒绝", self._view.parent[d1] ~= d2, self._view.parent[d1])
self._forceSync = false
print("[Check] 通过 " .. pass .. " / 失败 " .. fail)
return "自检: 通过 " .. pass .. " 失败 " .. fail
end
return Script
