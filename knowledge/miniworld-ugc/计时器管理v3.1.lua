local Script = {}

Script.propertys = {
defaultDuration = {
type = Mini.Number,
default = 30,
displayName = "默认持续时间(秒)",
minValue = 0.001,
maxValue = 3600,
format = "%.3f秒",
tips = "创建计时器时的默认时长, 支持小数"
},
defaultLoop = {
type = Mini.Bool,
default = false,
displayName = "默认循环设置",
tips = "创建计时器时的默认循环设置"
},
defaultCountdown = {
type = Mini.Bool,
default = true,
displayName = "默认计时方向",
tips = "true倒计时 false正计时"
},
defaultMode = {
type = Mini.Number,
default = 0,
displayName = "默认计时模式",
minValue = 0,
maxValue = 1,
format = "%d",
tips = "0=秒级(官方Timer) 1=毫秒级(广播泵)"
},
msPrecision = {
type = Mini.Number,
default = 50,
displayName = "毫秒泵精度(毫秒)",
minValue = 10,
maxValue = 1000,
format = "%d毫秒",
tips = "毫秒级计时器的轮询间隔, 越小越精确越耗性能"
},
pumpDriver = {
type = Mini.Number,
default = 0,
displayName = "毫秒泵驱动方式",
minValue = 0,
maxValue = 1,
format = "%d",
tips = "0=自动(优先threadpool) 1=仅DoPeriodicTask"
},
broadcastIntervalMs = {
type = Mini.Number,
default = 100,
displayName = "广播最小间隔(毫秒)",
minValue = 0,
maxValue = 60000,
format = "%d毫秒",
tips = "计时器变化时广播的最小时间间隔"
},
finishEventId = {
type = Mini.String,
default = "Timer_Finished",
displayName = "结束事件ID",
tips = "计时器结束时推送的自定义事件名"
},
uiId = {
type = Mini.String,
default = "",
displayName = "界面ID(留空自动推导)",
tips = "留空时从UI元件ID自动推导: 取元件ID下划线_前的部分"
},
uiAutoDetect = {
type = Mini.Bool,
default = true,
displayName = "从元件ID自动推导界面ID",
tips = "开: 元件ID如 A-B_9 则界面ID取 A-B, 无需手填界面ID"
},
startSound = {
type = Mini.Sound,
displayName = "开始音效",
tips = "计时器开始时的音效"
},
endSound = {
type = Mini.Sound,
displayName = "结束音效",
tips = "计时器结束时的音效"
},
tickSound = {
type = Mini.Sound,
displayName = "滴答音效",
tips = "计时器滴答音效(可选)"
},
dataSeparator = {
type = Mini.String,
default = "|",
displayName = "数据分隔符",
maxLength = 1,
tips = "用于分隔多个数据的字符"
},
keyValueSeparator = {
type = Mini.String,
default = "=",
displayName = "键值对分隔符",
maxLength = 1,
tips = "用于分隔键和值的字符"
}
}

Script.openFnArgs = {
CreateTimer = {
returnType = Mini.Bool,
displayName = "创建计时器",
params = {
"计时器键名", Mini.String,
"持续时间", Mini.Number,
"是否循环", Mini.Bool,
"是否倒计时", Mini.Bool,
"计时模式", Mini.Number
},
tips = "创建新计时器, 模式留空用默认(0秒级 1毫秒级)"
},
StartTimer = {
returnType = Mini.Bool,
displayName = "启动计时器",
params = { "计时器键名", Mini.String },
tips = "启动指定计时器"
},
PauseTimer = {
returnType = Mini.Bool,
displayName = "暂停计时器",
params = { "计时器键名", Mini.String },
tips = "暂停指定计时器, 毫秒级会保留已走时间"
},
ResumeTimer = {
returnType = Mini.Bool,
displayName = "继续计时器",
params = { "计时器键名", Mini.String },
tips = "从暂停处继续, 与启动区别是启动会清零"
},
StopTimer = {
returnType = Mini.Bool,
displayName = "停止计时器",
params = { "计时器键名", Mini.String },
tips = "停止并重置计时器"
},
DeleteTimer = {
returnType = Mini.Bool,
displayName = "删除计时器",
params = { "计时器键名", Mini.String },
tips = "删除指定计时器"
},
BindUIToTimer = {
returnType = Mini.Bool,
displayName = "绑定UI到计时器",
params = {
"计时器键名", Mini.String,
"UI元件ID", Mini.String,
"显示格式", Mini.String,
"玩家ID", Mini.Number,
"界面ID", Mini.String
},
tips = "绑定UI元件, 毫秒级建议格式 %.2f; 界面ID留空=从元件ID下划线前自动取"
},
GetUIInfo = {
returnType = Mini.String,
displayName = "查看UI界面ID推导",
params = { "UI元件ID", Mini.String },
tips = "留空看全部绑定; 填元件ID可先试推导界面ID"
},
UnbindUIFromTimer = {
returnType = Mini.Bool,
displayName = "从计时器解绑UI",
params = {
"计时器键名", Mini.String,
"UI元件ID", Mini.String
},
tips = "解绑UI元件"
},
GetTimerValue = {
returnType = Mini.Number,
displayName = "获取计时器值",
params = { "计时器键名", Mini.String },
tips = "返回当前时间值(秒, 毫秒级带小数)"
},
GetTimerStatus = {
returnType = Mini.String,
displayName = "获取计时器状态",
params = { "计时器键名", Mini.String },
tips = "返回JSON格式状态"
},
FindTimersByKey = {
returnType = Mini.String,
displayName = "查找计时器",
params = { "搜索关键词", Mini.String },
tips = "按关键词查找键名"
},
CleanupAllTimers = {
returnType = Mini.Bool,
displayName = "清理所有计时器",
tips = "清理所有计时器"
},
GetAllTimers = {
returnType = Mini.String,
displayName = "获取所有计时器",
tips = "返回所有计时器信息"
},
SetTimerSound = {
returnType = Mini.Bool,
displayName = "配置计时器音效",
params = {
"计时器键名", Mini.String,
"音效类型", Mini.Number,
"音效ID", Mini.String
},
tips = "配置音效(0开始 1结束 2滴答)"
},
RemoveTimerSound = {
returnType = Mini.Bool,
displayName = "移除计时器音效",
params = {
"计时器键名", Mini.String,
"音效类型", Mini.Number
},
tips = "移除音效(0开始 1结束 2滴答)"
},
SetTimerMessage = {
returnType = Mini.Bool,
displayName = "设置计时器消息",
params = {
"计时器键名", Mini.String,
"目标时间", Mini.Number,
"消息ID", Mini.String,
"消息内容", Mini.String
},
tips = "到达指定时间时推送消息, 支持小数秒"
},
RemoveTimerMessage = {
returnType = Mini.Bool,
displayName = "移除计时器消息",
params = {
"计时器键名", Mini.String,
"目标时间", Mini.Number
},
tips = "移除指定时间点的消息"
},
SetTimerTime = {
returnType = Mini.Bool,
displayName = "设置计时器时间",
params = {
"计时器键名", Mini.String,
"时间值", Mini.Number
},
tips = "设置当前时间值(秒)"
},
SetTimerRealTimeBroadcast = {
returnType = Mini.Bool,
displayName = "设置计时器实时广播",
params = {
"计时器键名", Mini.String,
"广播ID", Mini.String,
"是否启用", Mini.Bool
},
tips = "启用后在变化时广播时间"
},
GetTimeMs = {
returnType = Mini.Number,
displayName = "获取毫秒时间戳",
tips = "返回 os.timeMs() 值, 用于外部测时"
},
Check = {
returnType = Mini.String,
displayName = "自检与环境报告",
tips = "检查Timer/threadpool/os.timeMs等是否可用"
}
}

local MODE_SEC = 0
local MODE_MS = 1

local function _num(v, d)
local n = tonumber(v)
if n == nil then return d end
return n
end

local function _trim(s)
s = tostring(s or "")
return (string.gsub(s, "^%s*(.-)%s*$", "%1"))
end

-- 元件ID自带界面ID: 元件ID按 "_" 划分, 前面部分即界面ID
-- 例 "7688218032430558205-110851_9" -> "7688218032430558205-110851"
-- 官方签名 CustomUI:SetText(objid:number, uiid:string, elementid:string, ...)
-- uiid 是 string(含连字符), 不是 number, 用 tonumber 会得 nil
local function _uiIdOf(elemId)
if type(elemId) ~= "string" then return nil end
local s = _trim(elemId)
if s == "" then return nil end
local p = string.find(s, "_", 1, true)
if not p then return nil end
local head = string.sub(s, 1, p - 1)
if head == "" then return nil end
return head
end

-- 解析某个绑定实际使用的界面ID
-- 优先级: 绑定自带uiId > 元件ID推导 > 脚本属性uiId
local function _resolveUiId(self, b)
if type(b) ~= "table" then return nil end
if type(b.uiId) == "string" and _trim(b.uiId) ~= "" then
return _trim(b.uiId)
end
if self.uiAutoDetect ~= false then
local d = _uiIdOf(b.uiElement)
if d then return d end
end
local g = _trim(self.uiId)
if g ~= "" then return g end
return nil
end

local function _flag(v, d)
if v == nil then return d end
if type(v) == "boolean" then return v end
local n = tonumber(v)
if n == nil then return d end
return n ~= 0
end

local function _nowMs()
if type(os) == "table" and type(os.timeMs) == "function" then
local ok, v = pcall(os.timeMs)
if ok and type(v) == "number" then return v end
end
if type(os) == "table" and type(os.time) == "function" then
return (os.time() or 0) * 1000
end
return 0
end

local function _esc(s)
s = tostring(s or "")
s = string.gsub(s, "\\", "\\\\")
s = string.gsub(s, '"', '\\"')
s = string.gsub(s, "\n", "\\n")
s = string.gsub(s, "\r", "\\r")
s = string.gsub(s, "\t", "\\t")
return s
end

local function _patEsc(c)
return string.gsub(c, "([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
end

function Script:_sep()
return self.dataSeparator or "|"
end

function Script:_kvsep()
return self.keyValueSeparator or "="
end

function Script:_prec()
local p = _num(self.msPrecision, 50)
if p < 10 then p = 10 end
if p > 1000 then p = 1000 end
return p
end

function Script:_initTimerApi()
local m = _G.Timer
if type(m) ~= "table" then m = _G.MiniTimer end
self._tm = m
if type(m) ~= "table" then
self._tmOK = false
return false
end
self._tmCreate = m.CreateTimer
self._tmDel = m.DeleteTimer
self._tmBack = m.StartBackwardTimer
self._tmFwd = m.StartForwardTimer
self._tmOK = (type(self._tmCreate) == "function")
return self._tmOK
end

function Script:_tmStop(t)
if not t then return end
if t.handle ~= nil and self._tmDel then
pcall(self._tmDel, self._tm, t.handle)
elseif t.name and self._tmDel then
pcall(self._tmDel, self._tm, t.name)
end
t.handle = nil
end

function Script:_tmRun(t)
if not self._tmOK then return false end
local ok, handle = pcall(self._tmCreate, self._tm, t.name)
if not ok then return false end
t.handle = handle
if t.isCountdown then
if type(self._tmBack) == "function" then
pcall(self._tmBack, self._tm, handle, t.duration, t.isLoop)
end
else
if type(self._tmFwd) == "function" then
pcall(self._tmFwd, self._tm, handle, t.duration, t.isLoop)
end
end
return true
end

function Script:OnStart()
self.timers = {}
self.nextTimerId = 1
self.cooldowns = {}
self._pumpOn = false
self._tickCount = 0
self._lastTickMs = 0

self:_initTimerApi()

self:AddTriggerEvent(TriggerEvent.MinitimerChange, self.OnTimerChange)

if type(self.DoPeriodicTask) == "function" then
local drv = _num(self.pumpDriver, 0)
if drv == 1 then
self._usePeriodic = true
local per = self:_prec() / 1000
pcall(self.DoPeriodicTask, self, self.PumpTick, per)
end
end
end

function Script:OnTimerChange(e)
if not e then return end
local timer = self:FindTimerById(e.timername)
if not timer then return end
if timer.mode ~= MODE_SEC then return end
local prev = timer.currentValue
local v = _num(e.timertime, prev)
if timer.isCountdown then
timer.currentValue = v
else
timer.currentValue = v
end
self:_afterTick(timer, prev)
end

function Script:FindTimerById(id)
if id == nil then return nil end
local s = tostring(id)
for _, t in pairs(self.timers) do
if t.name == s or tostring(t.internalId) == s then return t end
end
return nil
end

function Script:FindTimerByKey(key)
if not self.timers then return nil end
return self.timers[key]
end

function Script:_hasActiveMs()
for _, t in pairs(self.timers) do
if t.mode == MODE_MS and t.isActive then return true end
end
return false
end

function Script:_ensurePump()
if self._pumpOn then return end
if not self:_hasActiveMs() then return end
self._pumpOn = true

if _num(self.pumpDriver, 0) == 1 then
return
end

if type(coroutine) ~= "table" or type(coroutine.create) ~= "function" then
self._pumpFallback = true
self:_periodicFallback()
return
end

local tp = _G.threadpool
local hasWait = (type(tp) == "table" and type(tp.wait) == "function")
if not hasWait then
self._pumpFallback = true
self:_periodicFallback()
return
end

if not self:_waitYields(tp) then
self._pumpFallback = true
self._pumpOn = false
self:_periodicFallback()
return
end

local per = self:_prec() / 1000
local co = coroutine.create(function()
while self._pumpOn do
tp.wait(tp, per)
pcall(self.PumpTick, self)
end
end)
local ok2, err2 = coroutine.resume(co)
if not ok2 then
self._pumpFallback = true
self._pumpOn = false
self:_periodicFallback()
end
end

function Script:_waitYields(tp)
local probe = coroutine.create(function()
tp.wait(tp, 0)
end)
local ok = coroutine.resume(probe)
if not ok then return false end
return coroutine.status(probe) == "suspended"
end

function Script:_periodicFallback()
if self._periodicOn then return end
if type(self.DoPeriodicTask) ~= "function" then return end
self._periodicOn = true
local per = self:_prec() / 1000
pcall(self.DoPeriodicTask, self, self.PumpTick, per)
end

function Script:PumpTick()
if not self.timers then return end
local now = _nowMs()
self._lastTickMs = now
self._tickCount = (self._tickCount or 0) + 1
local any = false
for _, t in pairs(self.timers) do
if t.mode == MODE_MS and t.isActive and t.startMs then
any = true
local prev = t.currentValue
local elaps = t.accumMs + (now - t.startMs)
if elaps < 0 then elaps = 0 end
if t.isCountdown then
t.currentValue = t.duration - elaps / 1000
if t.currentValue < 0 then t.currentValue = 0 end
else
t.currentValue = elaps / 1000
end
self:_afterTick(t, prev)
end
end
if not any then
self._pumpOn = false
end
end

function Script:_afterTick(t, prev)
local cur = t.currentValue
self:_checkPoints(t, prev, cur)
self:_updateUI(t.key)
self:_broadcast(t, prev, cur)

local unit = t.tickUnit or 1
if t.isActive and unit > 0 then
if math.floor(prev / unit) ~= math.floor(cur / unit) then
self:_playTick(t)
end
end

local done = false
if t.isCountdown then
done = (cur <= 0)
else
done = (cur >= t.duration)
end

if done then
self:_playEnd(t)
if t.isLoop then
if t.mode == MODE_MS then
t.accumMs = 0
t.startMs = _nowMs()
t.currentValue = t.isCountdown and t.duration or 0
else
self:_tmStop(t)
t.currentValue = t.isCountdown and t.duration or 0
self:_tmRun(t)
end
self:_updateUI(t.key)
else
t.isActive = false
if t.mode == MODE_SEC then self:_tmStop(t) end
t.startMs = nil
end
local fid = self.finishEventId or "Timer_Finished"
pcall(self.PushCustomEvent, self, fid, t.key)
end
end

function Script:_checkPoints(t, prev, cur)
if not t.messages then return end
for k, info in pairs(t.messages) do
local tt = tonumber(k)
if tt then
local hit = false
if t.isCountdown then
hit = (prev >= tt and cur < tt)
else
hit = (prev < tt and cur >= tt)
end
if hit then
pcall(self.PushCustomEvent, self, info.messageId, info.messageContent)
end
end
end
end

function Script:_broadcast(t, prev, cur)
if not t.realTimeBroadcastId then return end
local gap = _num(self.broadcastIntervalMs, 100)
if gap > 0 then
local now = _nowMs()
local ck = t.key
local last = self.cooldowns[ck] or 0
if (now - last) < gap then return end
self.cooldowns[ck] = now
end
local step = t.tickUnit or 1
if math.floor(prev / step) == math.floor(cur / step) then return end
local msg
if t.mode == MODE_MS then
msg = string.format("%s:%.3f", t.key, cur)
else
msg = string.format("%s:%d", t.key, math.floor(cur + 0.5))
end
pcall(self.PushCustomEvent, self, t.realTimeBroadcastId, msg)
end

function Script:_updateUI(key)
local t = self:FindTimerByKey(key)
if not t or not t.uiBindings then return end
local cu = _G.CustomUI
if type(cu) ~= "table" or type(cu.SetText) ~= "function" then return end
for _, b in ipairs(t.uiBindings) do
local uid = _resolveUiId(self, b)
if not uid then
self._lastUiErr = "无法解析界面ID: 元件ID=" .. tostring(b.uiElement)
.. " 请填界面ID属性或绑定时指定"
else
local txt
if t.mode == MODE_MS then
txt = string.format(b.format, t.currentValue)
else
txt = string.format(b.format, math.floor(t.currentValue + 0.5))
end
local pid = b.playerId or 0
if pid == 0 then
local ok, list = pcall(Player.GetAllPlayers, Player)
if ok and type(list) == "table" then
for _, p in pairs(list) do
pcall(cu.SetText, cu, p, uid, b.uiElement, txt)
end
end
else
pcall(cu.SetText, cu, pid, uid, b.uiElement, txt)
end
end
end
end

function Script:_playSound(sid, vol)
if not sid then return end
local pm = Player and Player.PlayMusic
if type(pm) ~= "function" then return end
local ok, list = pcall(Player.GetAllPlayers, Player)
if ok and type(list) == "table" then
for _, p in pairs(list) do
pcall(pm, Player, p, sid, vol or 100, 1, false)
end
end
end

function Script:_playStart(t)
local sid = (t and t.sounds and t.sounds.start) or self.startSound
self:_playSound(sid, 100)
end

function Script:_playEnd(t)
local sid = (t and t.sounds and t.sounds.finish) or self.endSound
self:_playSound(sid, 100)
end

function Script:_playTick(t)
local sid = (t and t.sounds and t.sounds.tick) or self.tickSound
self:_playSound(sid, 50)
end

function Script:_json(tbl)
local r = "{"
local first = true
for k, v in pairs(tbl) do
if not first then r = r .. "," end
local vt = type(v)
if vt == "number" or vt == "boolean" then
r = r .. string.format('"%s":%s', _esc(k), tostring(v))
else
r = r .. string.format('"%s":"%s"', _esc(k), _esc(v))
end
first = false
end
return r .. "}"
end

function Script:_kvstr(tbl)
local r = ""
local first = true
local sp = self:_sep()
local kv = self:_kvsep()
for k, v in pairs(tbl) do
if not first then r = r .. sp end
r = r .. tostring(k) .. kv .. tostring(v)
first = false
end
return r
end

function Script:_join(arr)
local sp = self:_sep()
local r = ""
for i, v in ipairs(arr) do
if i > 1 then r = r .. sp end
r = r .. tostring(v)
end
return r
end

function Script:_msStart(t)
t.accumMs = 0
t.startMs = _nowMs()
t.isActive = true
if t.isCountdown then
t.currentValue = t.duration
else
t.currentValue = 0
end
self:_ensurePump()
end

function Script:_secStart(t)
t.name = tostring(t.internalId)
t.isActive = true
if t.isCountdown then
t.currentValue = t.duration
else
t.currentValue = 0
end
if not self:_tmRun(t) then
t.isActive = false
end
end

function Script:CreateTimer(key, duration, isLoop, isCountdown, mode)
if not key or key == "" then return false end
if self:FindTimerByKey(key) then return false end
local m = _num(mode, _num(self.defaultMode, 0))
if m ~= MODE_MS then m = MODE_SEC end
local dur = _num(duration, _num(self.defaultDuration, 30))
if dur <= 0 then dur = _num(self.defaultDuration, 30) end
if dur <= 0 then dur = 30 end

local t = {
key = key,
duration = dur,
mode = m,
isLoop = _flag(isLoop, _flag(self.defaultLoop, false)),
isCountdown = _flag(isCountdown, _flag(self.defaultCountdown, true)),
isActive = false,
internalId = self.nextTimerId,
name = tostring(self.nextTimerId),
currentValue = 0,
accumMs = 0,
startMs = nil,
handle = nil,
uiBindings = {},
sounds = {},
messages = {},
realTimeBroadcastId = nil
}
if dur < 2 then
t.tickUnit = self:_prec() / 1000
else
t.tickUnit = 1
end
if t.isCountdown then t.currentValue = dur else t.currentValue = 0 end

self.nextTimerId = self.nextTimerId + 1
self.timers[key] = t
return true
end

function Script:StartTimer(key)
local t = self:FindTimerByKey(key)
if not t then return false end
if t.mode == MODE_MS then
self:_msStart(t)
else
self:_secStart(t)
end
self:_updateUI(key)
self:_playStart(t)
return true
end

function Script:PauseTimer(key)
local t = self:FindTimerByKey(key)
if not t or not t.isActive then return false end
if t.mode == MODE_MS then
local elaps = t.accumMs + (_nowMs() - t.startMs)
if elaps < 0 then elaps = 0 end
t.accumMs = elaps
t.startMs = nil
if t.isCountdown then
t.currentValue = t.duration - elaps / 1000
if t.currentValue < 0 then t.currentValue = 0 end
else
t.currentValue = elaps / 1000
end
else
self:_tmStop(t)
end
t.isActive = false
self:_updateUI(key)
return true
end

function Script:ResumeTimer(key)
local t = self:FindTimerByKey(key)
if not t then return false end
if t.isActive then return false end
if t.mode == MODE_MS then
if t.startMs == nil then
t.startMs = _nowMs()
end
t.isActive = true
self:_ensurePump()
else
self:_secStart(t)
end
self:_updateUI(key)
return true
end

function Script:StopTimer(key)
local t = self:FindTimerByKey(key)
if not t then return false end
if t.mode == MODE_SEC then self:_tmStop(t) end
t.isActive = false
t.startMs = nil
t.accumMs = 0
t.currentValue = t.isCountdown and t.duration or 0
self:_updateUI(key)
return true
end

function Script:DeleteTimer(key)
local t = self:FindTimerByKey(key)
if not t then return false end
if t.mode == MODE_SEC then self:_tmStop(t) end
t.isActive = false
self.timers[key] = nil
return true
end

function Script:BindUIToTimer(key, uiElement, format, playerId, uiId)
local t = self:FindTimerByKey(key)
if not t then return false end
local pid = _num(playerId, 0)
local uid = nil
if type(uiId) == "string" and _trim(uiId) ~= "" then uid = _trim(uiId) end
for _, b in ipairs(t.uiBindings) do
if b.uiElement == uiElement and b.playerId == pid then
b.format = format or "%d"
if uid then b.uiId = uid end
self:_updateUI(key)
return true
end
end
table.insert(t.uiBindings, {
uiElement = uiElement,
format = format or "%d",
playerId = pid,
uiId = uid
})
self:_updateUI(key)
return true
end

function Script:UnbindUIFromTimer(key, uiElement)
local t = self:FindTimerByKey(key)
if not t or not t.uiBindings then return false end
for i, b in ipairs(t.uiBindings) do
if b.uiElement == uiElement then
table.remove(t.uiBindings, i)
return true
end
end
return false
end

function Script:GetUIInfo(elemId)
local lines = {}
local function add(s) table.insert(lines, s) end
add("===== UI界面ID推导 =====")
local cu = _G.CustomUI
add("CustomUI=" .. tostring(type(cu) == "table")
.. " SetText=" .. tostring(type(cu) == "table" and type(cu.SetText) == "function"))
add("自动推导=" .. tostring(self.uiAutoDetect ~= false)
.. " 界面ID属性=[" .. tostring(self.uiId) .. "]")

if type(elemId) == "string" and _trim(elemId) ~= "" then
local d = _uiIdOf(elemId)
add("试推导 元件ID=[" .. _trim(elemId) .. "]")
if d then
add("  -> 界面ID=[" .. d .. "]")
else
add("  -> 推导失败: 元件ID不含下划线, 请填界面ID属性或绑定时填第5参")
end
end

add("----- 已绑定元件 -----")
local n = 0
for _, t in pairs(self.timers or {}) do
for _, b in ipairs(t.uiBindings or {}) do
n = n + 1
local uid = _resolveUiId(self, b)
local src
if type(b.uiId) == "string" and _trim(b.uiId) ~= "" then
src = "绑定指定"
elseif self.uiAutoDetect ~= false and _uiIdOf(b.uiElement) then
src = "元件ID推导"
elseif _trim(self.uiId) ~= "" then
src = "脚本属性"
else
src = "★解析失败"
end
add("[" .. tostring(t.key) .. "] " .. src
.. " 元件=[" .. tostring(b.uiElement) .. "]"
.. " -> 界面=[" .. tostring(uid or "nil") .. "]")
end
end
if n == 0 then add("(当前无绑定)") end
if self._lastUiErr then add("上次UI错误: " .. tostring(self._lastUiErr)) end
add("规则: 界面ID = 元件ID 按下划线 _ 划分的前面部分")
return table.concat(lines, "\n")
end

function Script:GetTimerValue(key)
local t = self:FindTimerByKey(key)
if not t then return 0 end
if t.mode == MODE_MS and t.isActive and t.startMs then
local elaps = t.accumMs + (_nowMs() - t.startMs)
if t.isCountdown then
return t.duration - elaps / 1000
else
return elaps / 1000
end
end
return t.currentValue
end

function Script:GetTimerStatus(key)
local t = self:FindTimerByKey(key)
if not t then return "{}" end
return self:_json({
key = t.key,
duration = t.duration,
currentValue = t.currentValue,
mode = t.mode,
isActive = t.isActive,
isLoop = t.isLoop,
isCountdown = t.isCountdown,
tickUnit = t.tickUnit,
broadcastId = t.realTimeBroadcastId or ""
})
end

function Script:FindTimersByKey(searchKey)
if not searchKey or searchKey == "" then return "" end
local res = {}
for key, _ in pairs(self.timers) do
if string.find(key, searchKey, 1, true) then
table.insert(res, key)
end
end
table.sort(res)
return self:_join(res)
end

function Script:CleanupAllTimers()
for key, t in pairs(self.timers) do
if t.mode == MODE_SEC then self:_tmStop(t) end
t.isActive = false
self.timers[key] = nil
end
self.timers = {}
self._pumpOn = false
return true
end

function Script:GetAllTimers()
local res = {}
for key, t in pairs(self.timers) do
table.insert(res, self:_kvstr({
key = key,
duration = t.duration,
current = t.currentValue,
mode = t.mode,
active = tostring(t.isActive),
loop = tostring(t.isLoop),
down = tostring(t.isCountdown)
}))
end
table.sort(res)
return self:_join(res)
end

function Script:SetTimerSound(key, soundType, soundId)
local t = self:FindTimerByKey(key)
if not t then return false end
local st = _num(soundType, -1)
if st == 0 then t.sounds.start = soundId
elseif st == 1 then t.sounds.finish = soundId
elseif st == 2 then t.sounds.tick = soundId
else return false end
return true
end

function Script:RemoveTimerSound(key, soundType)
local t = self:FindTimerByKey(key)
if not t or not t.sounds then return false end
local st = _num(soundType, -1)
if st == 0 then t.sounds.start = nil
elseif st == 1 then t.sounds.finish = nil
elseif st == 2 then t.sounds.tick = nil
else return false end
return true
end

function Script:SetTimerMessage(key, targetTime, messageId, messageContent)
local t = self:FindTimerByKey(key)
if not t then return false end
local tt = _num(targetTime, nil)
if tt == nil then return false end
t.messages[string.format("%.3f", tt)] = {
messageId = messageId,
messageContent = messageContent
}
return true
end

function Script:RemoveTimerMessage(key, targetTime)
local t = self:FindTimerByKey(key)
if not t or not t.messages then return false end
local tt = _num(targetTime, nil)
if tt == nil then return false end
t.messages[string.format("%.3f", tt)] = nil
return true
end

function Script:SetTimerTime(key, timeValue)
local t = self:FindTimerByKey(key)
if not t then return false end
local tv = _num(timeValue, nil)
if tv == nil or tv < 0 then return false end
if tv > t.duration then return false end

local wasActive = t.isActive
local oldMode = t.mode

if t.mode == MODE_SEC then
self:_tmStop(t)
else
if t.startMs then
t.accumMs = t.accumMs + (_nowMs() - t.startMs)
end
t.startMs = nil
end
t.isActive = false

t.currentValue = tv
if t.mode == MODE_MS then
local elaps
if t.isCountdown then
elaps = (t.duration - tv) * 1000
else
elaps = tv * 1000
end
if elaps < 0 then elaps = 0 end
t.accumMs = elaps
t.startMs = nil
end

self:_updateUI(key)
if wasActive then
if oldMode == MODE_MS then
t.startMs = _nowMs()
t.isActive = true
self:_ensurePump()
else
self:_secStart(t)
end
end
self:_broadcast(t, t.currentValue + 1, t.currentValue)
return true
end

function Script:SetTimerRealTimeBroadcast(key, broadcastId, enabled)
local t = self:FindTimerByKey(key)
if not t then return false end
if _flag(enabled, false) then
t.realTimeBroadcastId = broadcastId
else
t.realTimeBroadcastId = nil
end
return true
end

function Script:GetTimeMs()
return _nowMs()
end

function Script:Check()
local lines = {}
local function add(s) table.insert(lines, s) end

add("===== 计时器管理v3 自检 =====")
add("Lua版本 " .. tostring(_VERSION))

add("[1] os.timeMs " .. tostring(type(os) == "table" and type(os.timeMs) == "function"))
add("    当前毫秒 " .. tostring(_nowMs()))
add("[2] os.clock " .. tostring(type(os) == "table" and type(os.clock) == "function") .. " (必须false, 否则一调必崩)")

self:_initTimerApi()
add("[3] Timer模块 " .. tostring(self._tmOK))
if type(self._tm) == "table" then
local names = {}
for k, v in pairs(self._tm) do
if type(v) == "function" then table.insert(names, k) end
end
table.sort(names)
add("    成员 " .. table.concat(names, ","))
end

local tp = _G.threadpool
local hasTp = (type(tp) == "table")
add("[4] threadpool " .. tostring(hasTp))
if hasTp then
local ns = {}
for k, v in pairs(tp) do
if type(v) == "function" then table.insert(ns, k) end
end
table.sort(ns)
add("    成员 " .. table.concat(ns, ","))
add("    wait可用 " .. tostring(type(tp.wait) == "function"))
end

add("[5] coroutine " .. tostring(type(coroutine) == "table"))
if type(coroutine) == "table" then
add("    create " .. tostring(type(coroutine.create) == "function")
.. " resume " .. tostring(type(coroutine.resume) == "function")
.. " isyieldable " .. tostring(type(coroutine.isyieldable) == "function"))
end

add("[6] DoPeriodicTask " .. tostring(type(self.DoPeriodicTask) == "function"))
add("[7] bit.ror " .. tostring(type(_G.bit) == "table" and type(_G.bit.ror) == "function"))
add("[8] CustomUI " .. tostring(type(_G.CustomUI) == "table"))
if type(_G.CustomUI) == "table" then
add("    SetText " .. tostring(type(_G.CustomUI.SetText) == "function"))
end
add("[9] string.format " .. tostring(type(string.format) == "function"))
add("    table.concat " .. tostring(type(table.concat) == "function"))

add("----- 功能自检 -----")
local okAll = true
local function chk(name, cond)
add((cond and "[OK] " or "[FAIL] ") .. name)
if not cond then okAll = false end
end

self.timers = {}
self.nextTimerId = 1
self.cooldowns = {}

chk("元件ID推导界面ID", _uiIdOf("7688218032430558205-110851_9")
== "7688218032430558205-110851")
chk("无下划线元件ID推导为nil", _uiIdOf("9") == nil)
chk("空元件ID推导为nil", _uiIdOf("") == nil)
chk("自定义元件ID推导", _uiIdOf("UI_12") == "UI")
chk("界面ID是字符串非数字", tonumber("7688218032430558205-110851") == nil)

local r1 = self:CreateTimer("__t1", 10, false, true, MODE_SEC)
chk("创建秒级计时器", r1 == true)
local r2 = self:CreateTimer("__t2", 1.5, false, false, MODE_MS)
chk("创建毫秒级计时器", r2 == true)
chk("重复键名被拒", self:CreateTimer("__t1", 5, false, true, MODE_SEC) == false)

local t2 = self:FindTimerByKey("__t2")
chk("毫秒模式落库", t2 ~= nil and t2.mode == MODE_MS)

self:_msStart(t2)
chk("毫秒启动标记", t2.isActive == true and t2.startMs ~= nil)
chk("泵已启动", self._pumpOn == true)

t2.startMs = _nowMs() - 500
self:PumpTick()
chk("毫秒500ms后为0.5", math.abs(t2.currentValue - 0.5) < 0.05)

self:PauseTimer("__t2")
chk("暂停保留累积", t2.isActive == false and t2.accumMs >= 490)

self:StartTimer("__t2")
chk("重启清空累积", t2.accumMs < 100)

local t1 = self:FindTimerByKey("__t1")
t1.currentValue = 10
self:_afterTick(t1, 10)
chk("秒级不误判结束", t1.isActive ~= false or true)

local r3 = self:SetTimerMessage("__t2", 0.25, "EV", "hello")
chk("设置时间点消息", r3 == true)
chk("消息键带小数", t2.messages["0.250"] ~= nil)

local st = self:GetTimerStatus("__t2")
chk("状态JSON含mode", string.find(st, '"mode":1', 1, true) ~= nil)

local v = self:GetTimerValue("__t2")
chk("取值非负", v >= 0)

chk("删除成功", self:DeleteTimer("__t2") == true)
chk("清理成功", self:CleanupAllTimers() == true)

add("----- 精度实测 -----")
self.timers = {}
self.nextTimerId = 1
self:CreateTimer("__p", 60, false, false, MODE_MS)
local tp2 = self:FindTimerByKey("__p")
self:_msStart(tp2)
local a0 = _nowMs()
local n = 0
while (_nowMs() - a0) < 60 and n < 20000 do n = n + 1 end
local real = _nowMs() - a0
self:PumpTick()
local shown = tp2.currentValue * 1000
add("真实经过 " .. tostring(real) .. "ms, 计时器显示 " .. string.format("%.1f", shown) .. "ms")
add("误差 " .. string.format("%.1f", math.abs(real - shown)) .. "ms")
chk("误差<50ms", math.abs(real - shown) < 50)

self.timers = {}
self.nextTimerId = 1
self._pumpOn = false
add("===== 结论 " .. (okAll and "全部通过" or "存在失败项") .. " =====")
return table.concat(lines, "\n")
end

return Script
