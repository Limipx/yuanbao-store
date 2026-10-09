-- ============================================================
-- MiniBus · 通用广播总线（组件版，可直接导入）
--
-- 一个预设广播 ID 当无数个用：
--   触发器里只需新建【一条】广播消息，把 ID 填到本组件属性 busId，
--   全地图所有组件共用这一条，靠「路由字符串」区分用途，
--   等于无数个逻辑频道。
--
-- 三类通道，同一套 API：
--   Local = 对象内事件 PushEvent            同对象组件之间
--   Room  = 房间广播   PushCustomEvent      同房间所有组件
--   Cloud = 云服广播   PushCloudServerMsg   跨房间，第三参数可定向
--
-- 发送权限不可用时自动降级为本地直连，逻辑不断。
-- ============================================================

local Script = {}

-- ===== 属性（必须留顶层，不能搬进 OnStart） =====
Script.propertys = {
    busId = {
        type = Mini.String,
        default = "",
        displayName = "广播消息ID",
        tips = "在触发器里新建一条广播消息，把它的 ID 填这里。全地图组件共用一条即可。"
    },
    autoBind = {
        type = Mini.Bool,
        default = true,
        displayName = "启动即绑定"
    },
    debug = {
        type = Mini.Bool,
        default = false,
        displayName = "调试日志"
    }
}

-- ===== MB_BEGIN =====
local MiniBus = (function()
    if _G.__MiniBus then return _G.__MiniBus end

    local MB = {}

    -- 唯一的预设广播 ID：改成你在触发器里新建的那个广播消息的 ID
    MB.BUS_ID = _G.__MiniBusBusId or "m177358728257565"

    MB.handlers = {}     -- route -> {fn, ...}
    MB.nodes    = {}     -- 绑定的组件 self 列表
    MB.seq      = 0
    MB.seen     = {}     -- 已处理的 msgId，防多组件重复分发
    MB.seenN    = 0
    MB.debug    = false

    local function log(...)
        if MB.debug then print("[MiniBus]", ...) end
    end

    -- ---------- 序列化（不依赖 json，纯 ASCII 安全） ----------
    -- 格式：N(nil) T(true) F(false) I<len>:<int> D<len>:<num>
    --       S<len>:<str> { k v k v ... } }
    local MAX_DEPTH = 24

    local function ser(v, out, depth)
        depth = depth or 0
        if depth > MAX_DEPTH then out[#out + 1] = "N"; return end
        local t = type(v)
        if t == "nil" then
            out[#out + 1] = "N"
        elseif t == "boolean" then
            out[#out + 1] = v and "T" or "F"
        elseif t == "number" then
            if v ~= v or v == math.huge or v == -math.huge then
                out[#out + 1] = "N"
            else
                local s
                if v == math.floor(v) and v >= -2147483648 and v <= 2147483647 then
                    s = string.format("%.0f", v); out[#out + 1] = "I"
                else
                    s = string.format("%.17g", v); out[#out + 1] = "D"
                end
                out[#out + 1] = tostring(#s) .. ":" .. s
            end
        elseif t == "string" then
            out[#out + 1] = "S" .. tostring(#v) .. ":" .. v
        elseif t == "table" then
            out[#out + 1] = "{"
            for k, val in pairs(v) do
                ser(k, out, depth + 1)
                ser(val, out, depth + 1)
            end
            out[#out + 1] = "}"
        else
            out[#out + 1] = "N"   -- function / userdata / thread → nil
        end
    end

    function MB.serialize(v)
        local out = {}
        ser(v, out, 0)
        return table.concat(out)
    end

    function MB.deserialize(s)
        if type(s) ~= "string" or s == "" then return nil end
        local pos, n = 1, #s
        local function rd(k)
            local r = s:sub(pos, pos + k - 1); pos = pos + k; return r
        end
        local function readPrefixed()
            local i = s:find(":", pos, true)
            if not i then return nil end
            local len = tonumber(s:sub(pos, i - 1))
            pos = i + 1
            if not len then return nil end
            local body = s:sub(pos, pos + len - 1)
            pos = pos + len
            return body
        end
        local parse
        parse = function(depth)
            if depth > MAX_DEPTH then return nil end
            local c = rd(1)
            if c == "N" then return nil
            elseif c == "T" then return true
            elseif c == "F" then return false
            elseif c == "I" then return tonumber(readPrefixed()) or 0
            elseif c == "D" then return tonumber(readPrefixed()) or 0
            elseif c == "S" then return readPrefixed() or ""
            elseif c == "{" then
                local t = {}
                while pos <= n do
                    if s:sub(pos, pos) == "}" then rd(1); break end
                    local k = parse(depth + 1)
                    if pos > n then break end
                    local v = parse(depth + 1)
                    if k ~= nil then t[k] = v end
                end
                return t
            end
            return nil
        end
        local ok, res = pcall(parse, 0)
        return ok and res or nil
    end

    -- ---------- 信封 ----------
    -- 只占【一个】广播参数：云服广播的第三个参数要留给定向房间 ID
    local function pack(route, data)
        MB.seq = MB.seq + 1
        local mid = tostring((os and os.timeMs and os.timeMs() or 0)) .. "_" .. tostring(MB.seq)
        return route .. "\1" .. mid .. "\1" .. MB.serialize(data)
    end

    local function unpack(env)
        if type(env) ~= "string" then return nil end
        local p1 = env:find("\1", 1, true)
        if not p1 then return nil end
        local p2 = env:find("\1", p1 + 1, true)
        if not p2 then return nil end
        return env:sub(1, p1 - 1), env:sub(p1 + 1, p2 - 1), env:sub(p2 + 1)
    end

    -- ---------- 去重 ----------
    local function already(mid)
        if not mid or mid == "" then return false end
        if MB.seen[mid] then return true end
        MB.seen[mid] = true
        MB.seenN = MB.seenN + 1
        if MB.seenN > 2000 then MB.seen = {}; MB.seenN = 0 end
        return false
    end

    -- ---------- 分发 ----------
    function MB:dispatch(env, from)
        local route, mid, body = unpack(env)
        if not route then return end
        if already(mid) then return end
        local data = MB.deserialize(body)
        local list = self.handlers[route]
        if not list then
            -- 支持前缀通配：订阅 "背包.*" 可收到 "背包.同步"
            local head = route:match("^(.-)%.[^.]+$")
            if head then list = self.handlers[head .. ".*"] end
        end
        if not list then log("无订阅", route); return end
        for i = 1, #list do
            local ok, err = pcall(list[i], data, from, route)
            if not ok then log("handler 出错", route, tostring(err)) end
        end
    end

    -- ---------- 通道能力探测 ----------
    local function canPush(self, fn)
        return self and type(self[fn]) == "function"
    end

    -- ---------- 对外 API ----------

    -- 绑定组件。OnStart 里调一次。
    -- 会自动注册：对象内事件 + 房间广播 + 云服广播 三路监听
    function MB:Bind(self)
        if not self then return self end
        self.__mbBus = true
        self.handlers = self.handlers   -- 保持 handlers 在 MB 上（共享）
        MB.nodes[#MB.nodes + 1] = self

        local function onEnv(cmp, eventId, p1, p2, p3)
            -- AddCustomEvent 回调签名：(cmp, eventId, param1, param2, param3)
            -- 不同版本参数位置不一，逐个尝试找出信封
            local env = nil
            for _, v in ipairs({p1, p2, p3}) do
                if type(v) == "string" and v:find("\1", 1, true) then
                    env = v
                    break
                end
            end
            if env then MB:dispatch(env, "custom") end
        end

        -- 房间广播监听（一个 ID 复用）
        if canPush(self, "AddCustomEvent") then
            pcall(function()
                self:AddCustomEvent(MB.BUS_ID, function(cmp, eventId, a, b, c)
                    local env = a
                    if type(env) ~= "string" or not env:find("\1", 1, true) then
                        env = (type(b) == "string" and b:find("\1", 1, true)) and b or nil
                    end
                    if env then MB:dispatch(env, "custom") end
                end)
            end)
        end

        -- 云服广播监听
        if canPush(self, "AddCloudSeverEvent") then
            pcall(function()
                self:AddCloudSeverEvent(MB.BUS_ID, function(cmp, eventId, a, b, c)
                    local env = a
                    if type(env) ~= "string" or not env:find("\1", 1, true) then
                        env = (type(b) == "string" and b:find("\1", 1, true)) and b or nil
                    end
                    if env then MB:dispatch(env, "cloud") end
                end)
            end)
        end

        -- 对象内事件监听（同对象组件间，最轻量、不需要广播权限）
        if canPush(self, "AddEvent") then
            pcall(function()
                self:AddEvent("MiniBus", function(cmp, a, b, c)
                    local env = a
                    if type(env) ~= "string" or not env:find("\1", 1, true) then env = b end
                    if type(env) == "string" and env:find("\1", 1, true) then
                        MB:dispatch(env, "local")
                    end
                end)
            end)
        end
        return self
    end

    -- 订阅。route 支持 "背包.同步" 精确，或 "背包.*" 前缀通配
    function MB:On(route, fn)
        if type(route) ~= "string" or type(fn) ~= "function" then return end
        self.handlers[route] = self.handlers[route] or {}
        local list = self.handlers[route]
        list[#list + 1] = fn
    end

    function MB:Off(route, fn)
        local list = self.handlers[route]
        if not list then return end
        if not fn then self.handlers[route] = nil; return end
        for i = #list, 1, -1 do
            if list[i] == fn then table.remove(list, i) end
        end
    end

    -- 发送：自动选通道
    --   scope = "local"  对象内（PushEvent，同对象组件间，不需要广播权限）
    --         = "room"   房间广播（PushCustomEvent，需要一个预设广播 ID）
    --         = "cloud"  云服广播（PushCloudServerMsg，可跨房间）
    --         = "auto"   默认：local → room 依次尝试，都不行则回落 _G 直连
    function MB:EmitEx(route, data, scope, roomId)
        local env = pack(route, data)
        local self = MB.nodes[1]
        local sent = false

        if scope == "local" or scope == "auto" then
            if self and canPush(self, "PushEvent") then
                local ok = pcall(function() self:PushEvent("MiniBus", env) end)
                if ok then sent = true; log("local→", route) end
            end
            if not sent and scope == "local" then
                -- 回落 _G 直连：同一 Lua VM 内组件共享 _G，一定能送达
                MB:dispatch(env, "local")
                return true
            end
        end

        if (scope == "room" or (scope == "auto" and not sent)) then
            if self and canPush(self, "PushCustomEvent") then
                local ok = pcall(function() self:PushCustomEvent(MB.BUS_ID, env) end)
                if ok then sent = true; log("room→", route) end
            end
            if not sent and scope == "room" then
                MB:dispatch(env, "room")   -- 无权限时降级为本地，保证逻辑不断
                return true
            end
        end

        if scope == "cloud" then
            if self and canPush(self, "PushCloudServerMsg") then
                -- 第三个参数传房间 ID = 只向那个房间发；不传 = 全云服
                if roomId then
                    pcall(function() self:PushCloudServerMsg(MB.BUS_ID, env, roomId) end)
                else
                    pcall(function() self:PushCloudServerMsg(MB.BUS_ID, env) end)
                end
                log("cloud→", route, roomId or "全部")
                return true
            end
            MB:dispatch(env, "cloud")
            return true
        end

        if not sent and scope == "auto" then
            MB:dispatch(env, "auto")
            return true
        end
        return sent
    end

    -- 常用简写
    function MB:Emit(route, data)  return MB:EmitEx(route, data, "auto") end
    function MB:Local(route, data) return MB:EmitEx(route, data, "local") end
    function MB:Room(route, data)  return MB:EmitEx(route, data, "room") end
    function MB:Cloud(route, data, roomId) return MB:EmitEx(route, data, "cloud", roomId) end

    -- 请求-响应（在同一 VM 内可用；跨房需配合回调 route）
    function MB:Unbind(cmp)
        if not cmp then return end
        for i = #self.nodes, 1, -1 do
            if self.nodes[i] == cmp then table.remove(self.nodes, i) end
        end
    end

    -- 对外编解码：开放函数只能传字符串时用这对转换
    function MB:Encode(t)
        return MB.serialize(t)
    end

    function MB:Decode(s)
        if s == nil or s == "" then return nil end
        local ok, v = pcall(MB.deserialize, s)
        if ok then return v end
        return s
    end

    function MB:Request(route, data, timeoutTick)
        local res, got = nil, false
        local reply = route .. ".reply"
        MB:On(reply, function(d) res, got = d, true end)
        MB:Emit(route, data)
        return res, got
    end

    function MB:Stats()
        local n = 0
        for _ in pairs(self.handlers) do n = n + 1 end
        return {routes = n, nodes = #self.nodes, seen = self.seenN}
    end

    _G.__MiniBus = MB
    return MB
end)()


-- ===== 生命周期（不能改名） =====
function Script:OnStart()
    if self.busId and self.busId ~= "" then
        MiniBus.BUS_ID = self.busId
    end
    if self.autoBind then
        MiniBus:Bind(self)
    end
    MiniBus:On("demo.ping", function(data, from)
        if self.debug then print("[MiniBus] 收到 ping", tostring(data)) end
        MiniBus:Emit("demo.pong", { echo = data })
    end)
    if self.debug then print("[MiniBus] 已启动 busId=", MiniBus.BUS_ID) end
end

function Script:OnDestroy()
    MiniBus:Unbind(self)
end

-- ===== 开放函数（键名必须与函数名一致） =====
Script.openFunctions = {
    BusEmit = true, BusOn = true, BusLocal = true,
    BusRoom = true, BusCloud = true, BusStats = true
}

Script.openFnArgs = {
    BusEmit = {
        returnType = Mini.String,
        params = { "路由", Mini.String, "数据", Mini.String },
        displayName = "发送(自动选通道)"
    },
    BusOn = {
        returnType = Mini.String,
        params = { "路由", Mini.String },
        displayName = "订阅路由"
    },
    BusLocal = {
        returnType = Mini.String,
        params = { "路由", Mini.String, "数据", Mini.String },
        displayName = "发送(对象内)"
    },
    BusRoom = {
        returnType = Mini.String,
        params = { "路由", Mini.String, "数据", Mini.String },
        displayName = "发送(房间广播)"
    },
    BusCloud = {
        returnType = Mini.String,
        params = { "路由", Mini.String, "数据", Mini.String, "定向房间", Mini.String },
        displayName = "发送(云服广播)"
    },
    BusStats = {
        returnType = Mini.String,
        params = {},
        displayName = "运行状态"
    }
}

function Script:BusEmit(route, dataStr)
    return MiniBus:Emit(route, MiniBus:Decode(dataStr)) and "已发送" or "发送失败"
end
function Script:BusLocal(route, dataStr)
    return MiniBus:Local(route, MiniBus:Decode(dataStr)) and "已发送(对象内)" or "失败"
end
function Script:BusRoom(route, dataStr)
    return MiniBus:Room(route, MiniBus:Decode(dataStr)) and "已发送(房间)" or "失败"
end
function Script:BusCloud(route, dataStr, roomId)
    return MiniBus:Cloud(route, MiniBus:Decode(dataStr), roomId) and "已发送(云服)" or "失败"
end
function Script:BusOn(route)
    MiniBus:On(route, function(data, from)
        print("[MiniBus]", tostring(route), tostring(data))
    end)
    return "已订阅 " .. tostring(route)
end
function Script:BusStats()
    local s = MiniBus:Stats()
    return string.format("路由%d 组件%d 已处理%d", s.routes, s.nodes, s.seen)
end

return Script
