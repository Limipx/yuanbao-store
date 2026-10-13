--[[
================================================================================
 全服去中心化文件夹系统  (Server-Wide Decentralized FS)   v1.0
--------------------------------------------------------------------------------
 存储层 : 房间字符串数组 Data.Array(playerId = nil)   —— 追加式日志，跨重启保留
 通信层 : 云服全服广播 PushCloudServerMsg/AddCloudSeverEvent —— 单一逻辑通道
 共识层 : Lamport 时钟 + (clock,rid,seq) 确定性全序     —— 无 Leader / 无投票
 完整性 : 每房间哈希链 + 全局 Merkle 根
 同步层 : 版本向量(VV) + Merkle 根比对 + 反熵补发
 容灾   : 全量复制(每个房间都是全节点) —— 抗房间随时关闭
--------------------------------------------------------------------------------
 不使用 KV 表。table 只负责：内存态 / 待发队列 / 去重集合 / 版本向量。
================================================================================
 开放函数:
   Init()                      初始化(必须最先调用或由 OnStart 自动调用)
   Tick()                      出块+心跳(需接定时器,或手动周期调用)
   OnCloudEvent(...)           云服广播入口(接到预设消息ID的回调上)
   Mkdir(path)                 建目录
   Write(path, content)        写文件(自动分片)
   Read(path)                  读文件
   List(path)                  列子项(逗号分隔)
   Delete(path)                删除子树
   Move(a,b) / Copy(a,b)       移动 / 复制
   Find(pattern)               通配查找(* 单段, ** 多段)
   Stat(path)                  取属性
   Digest()                    版本向量 + Merkle 根
   Status()                    运行状态
   Sync()                      立即广播一次心跳(请求补齐)
   Compact()                   写快照 + 逻辑剪枝
   Verify()                    校验全部哈希链
   NetProbe()                  探测广播接口是否可用
================================================================================
]]

local Script = {}

--------------------------------------------------------------------------------
-- 0. 位运算适配(优先 bit / bit32,否则纯算术回退)
--------------------------------------------------------------------------------
local BIT = (function()
    local b = bit or bit32
    if b and b.band and b.bor and b.bxor and b.bnot and b.lshift and b.rshift then
        return { band = b.band, bor = b.bor, bxor = b.bxor, bnot = b.bnot,
                 lshift = b.lshift, rshift = b.rshift, native = true }
    end
    local M = 4294967296
    local function bd(a, c)
        a = a % M; c = c % M
        local r, p = 0, 1
        for _ = 0, 31 do
            if a % 2 >= 1 and c % 2 >= 1 then r = r + p end
            a = math.floor(a / 2); c = math.floor(c / 2); p = p * 2
        end
        return r
    end
    local function br(a, c)
        a = a % M; c = c % M
        local r, p = 0, 1
        for _ = 0, 31 do
            if a % 2 >= 1 or c % 2 >= 1 then r = r + p end
            a = math.floor(a / 2); c = math.floor(c / 2); p = p * 2
        end
        return r
    end
    local function bx(a, c)
        a = a % M; c = c % M
        local r, p = 0, 1
        for _ = 0, 31 do
            if (a % 2 >= 1) ~= (c % 2 >= 1) then r = r + p end
            a = math.floor(a / 2); c = math.floor(c / 2); p = p * 2
        end
        return r
    end
    local function fold(fn)
        return function(a, b, ...)
            local r = fn(a, b)
            local n = select("#", ...)
            for i = 1, n do r = fn(r, (select(i, ...))) end
            return r
        end
    end
    return {
        band = fold(bd), bor = fold(br), bxor = fold(bx),
        bnot = function(a) return (M - 1) - (a % M) end,
        lshift = function(a, n) return ((a % M) * (2 ^ n)) % M end,
        rshift = function(a, n) return math.floor((a % M) / (2 ^ n)) end,
        native = false,
    }
end)()

--------------------------------------------------------------------------------
-- 1. MD5(含常量预计算)—— 用于哈希链 / Merkle / 内容寻址
--------------------------------------------------------------------------------
local MD5K, MD5S = {}, {}
do
    for i = 0, 63 do MD5K[i] = math.floor(math.abs(math.sin(i + 1)) * 4294967296) % 4294967296 end
    local s = { 7,12,17,22, 7,12,17,22, 7,12,17,22, 7,12,17,22,
                5, 9,14,20, 5, 9,14,20, 5, 9,14,20, 5, 9,14,20,
                4,11,16,23, 4,11,16,23, 4,11,16,23, 4,11,16,23,
                6,10,15,21, 6,10,15,21, 6,10,15,21, 6,10,15,21 }
    for i = 1, 64 do MD5S[i] = s[i] end
end

local function md5(str)
    str = tostring(str or "")
    local band, bor, bxor, bnot, lshift, rshift =
        BIT.band, BIT.bor, BIT.bxor, BIT.bnot, BIT.lshift, BIT.rshift
    local M = 4294967296
    local function rol(x, n) n = n % 32; return bor(lshift(x, n), rshift(x, 32 - n)) % M end
    local len = #str
    local pad = (55 - (len % 64)) % 64
    local bytes = { str:byte(1, len) }
    bytes[len + 1] = 0x80
    for i = len + 2, len + 1 + pad do bytes[i] = 0 end
    local bl = (len * 8) % M
    for i = 0, 7 do bytes[len + 2 + pad + i] = band(rshift(bl, i * 8), 0xFF) end
    local A, B1, C, D = 0x67452301, 0xefcdab89, 0x98badcfe, 0x10325476
    local nchunks = (len + 1 + pad + 8) / 64
    for ch = 0, nchunks - 1 do
        local base = ch * 64
        local m0 = {}
        for j = 0, 15 do
            local o = base + j * 4
            -- 注意: 只用两参数 bor —— 部分引擎的 bit 库不是可变参数
            m0[j] = bor(bor(bor(bytes[o + 1] or 0, lshift(bytes[o + 2] or 0, 8)),
                            lshift(bytes[o + 3] or 0, 16)), lshift(bytes[o + 4] or 0, 24))
        end
        local a, b, c, d = A, B1, C, D
        for i = 0, 63 do
            local f, k
            if i < 16 then
                f = bor(band(b, c), band(bnot(b), d)); k = i
            elseif i < 32 then
                f = bor(band(b, d), band(bnot(d), c)); k = (5 * i + 1) % 16
            elseif i < 48 then
                f = bxor(bxor(b, c), d); k = (3 * i + 5) % 16
            else
                f = bxor(c, bor(b, bnot(d))); k = (7 * i) % 16
            end
            local tmp = (a + f + m0[k] + MD5K[i]) % M
            a, d, c, b = d, c, b, (b + rol(tmp, MD5S[i + 1])) % M
        end
        A = (A + a) % M; B1 = (B1 + b) % M; C = (C + c) % M; D = (D + d) % M
    end
    local out = {}
    for _, x in ipairs({ A, B1, C, D }) do
        for i = 0, 3 do out[#out + 1] = string.format("%02x", band(rshift(x, i * 8), 0xFF)) end
    end
    return table.concat(out)
end

--------------------------------------------------------------------------------
-- 2. 基础工具: 转义 / 切分 / hex / Merkle
--------------------------------------------------------------------------------
local function esc(s)
    s = tostring(s or "")
    local out = {}
    for i = 1, #s do
        local c = s:sub(i, i)
        if c == "\\" then out[#out + 1] = "\\\\"
        elseif c == "|" then out[#out + 1] = "\\p"
        elseif c == "\n" then out[#out + 1] = "\\n"
        elseif c == "\r" then out[#out + 1] = "\\r"
        else out[#out + 1] = c end
    end
    return table.concat(out)
end

local function unesc(s)
    local out, i, n = {}, 1, #s
    while i <= n do
        local c = s:sub(i, i)
        if c == "\\" then
            local nx = s:sub(i + 1, i + 1)
            if nx == "p" then out[#out + 1] = "|"; i = i + 2
            elseif nx == "n" then out[#out + 1] = "\n"; i = i + 2
            elseif nx == "r" then out[#out + 1] = "\r"; i = i + 2
            elseif nx == "\\" then out[#out + 1] = "\\"; i = i + 2
            else out[#out + 1] = c; i = i + 1 end
        else out[#out + 1] = c; i = i + 1 end
    end
    return table.concat(out)
end

local function split(s, sep)
    local r, start = {}, 1
    while true do
        local a, b = string.find(s, sep, start, true)
        if not a then r[#r + 1] = string.sub(s, start); break end
        r[#r + 1] = string.sub(s, start, a - 1)
        start = b + 1
    end
    return r
end

local function tohex(s)
    local out = {}
    for i = 1, #s do out[i] = string.format("%02x", s:byte(i)) end
    return table.concat(out)
end

local function fromhex(h)
    local out = {}
    for i = 1, #h - 1, 2 do out[#out + 1] = string.char(tonumber(h:sub(i, i + 1), 16) or 0) end
    return table.concat(out)
end

local function merkleRoot(list)
    if #list == 0 then return string.rep("0", 32) end
    local lvl = list
    while #lvl > 1 do
        local nxt = {}
        for i = 1, #lvl, 2 do
            if lvl[i + 1] then nxt[#nxt + 1] = md5(lvl[i] .. lvl[i + 1])
            else nxt[#nxt + 1] = lvl[i] end
        end
        lvl = nxt
    end
    return lvl[1]
end

--------------------------------------------------------------------------------
-- 3. 组件属性
--------------------------------------------------------------------------------
Script.propertys = {
    arrId = { type = Mini.String, default = "FSLog", displayName = "房间数组ID",
              tips = "房间作用域字符串数组(playerId=nil),存操作日志" },
    msgId = { type = Mini.String, default = "", displayName = "云服广播消息ID",
              tips = "触发器里预设的广播消息ID,形如 m177358728257565" },
    roomId = { type = Mini.String, default = "", displayName = "定向房间ID(留空=全服)",
              tips = "留空则广播给该地图所有云服房间" },
    blockSec = { type = Mini.Number, default = 10, displayName = "出块间隔(秒)",
              tips = "待发条目打包周期,建议 >= 广播延迟" },
    blockMax = { type = Mini.Number, default = 12, displayName = "每块最大条目" },
    blockChars = { type = Mini.Number, default = 3500, displayName = "每块最大字符",
              tips = "防止单条广播超长" },
    shardBytes = { type = Mini.Number, default = 512, displayName = "分片字节",
              tips = "超过则自动分片(hex后翻倍)" },
    helloSec = { type = Mini.Number, default = 60, displayName = "心跳周期(秒)",
              tips = "广播版本向量请求补齐" },
    autoInit = { type = Mini.Bool, default = true, displayName = "OnStart自动初始化" },
    autoTimer = { type = Mini.Bool, default = true, displayName = "自动建定时器" },
}

Script.openFnArgs = {
    Init          = { returnType = Mini.Bool,   displayName = "初始化",
                      params = {} },
    Tick          = { returnType = Mini.String, displayName = "出块+心跳",
                      params = {} },
    OnCloudEvent  = { returnType = Mini.String, displayName = "云服广播入口",
                      params = { "任意参数", Mini.String } },
    Mkdir         = { returnType = Mini.String, displayName = "建目录",
                      params = { "路径", Mini.String } },
    Write         = { returnType = Mini.String, displayName = "写文件",
                      params = { "路径", Mini.String, "内容", Mini.String } },
    Read          = { returnType = Mini.String, displayName = "读文件",
                      params = { "路径", Mini.String } },
    List          = { returnType = Mini.String, displayName = "列子项",
                      params = { "路径", Mini.String } },
    Delete        = { returnType = Mini.String, displayName = "删除子树",
                      params = { "路径", Mini.String } },
    Move          = { returnType = Mini.String, displayName = "移动",
                      params = { "源", Mini.String, "目标", Mini.String } },
    Copy          = { returnType = Mini.String, displayName = "复制",
                      params = { "源", Mini.String, "目标", Mini.String } },
    Find          = { returnType = Mini.String, displayName = "通配查找",
                      params = { "模式", Mini.String } },
    Stat          = { returnType = Mini.String, displayName = "取属性",
                      params = { "路径", Mini.String } },
    Digest        = { returnType = Mini.String, displayName = "版本向量+Merkle根",
                      params = {} },
    Status        = { returnType = Mini.String, displayName = "运行状态",
                      params = {} },
    Sync          = { returnType = Mini.String, displayName = "请求补齐",
                      params = {} },
    Compact       = { returnType = Mini.String, displayName = "快照+剪枝",
                      params = {} },
    Verify        = { returnType = Mini.String, displayName = "校验哈希链",
                      params = {} },
    NetProbe      = { returnType = Mini.String, displayName = "探测广播接口",
                      params = {} },
}

--------------------------------------------------------------------------------
-- 4. 运行时状态(table 承担: 内存态 / 待发 / 去重 / 版本向量)
--------------------------------------------------------------------------------
local S = {
    rid = nil, clock = 0, seq = 0,
    log = {}, byKey = {}, vv = {}, cw = {}, lastHash = {},
    tree = nil, kids = nil, dirty = true,
    out = {}, ready = false,
    lastBlock = 0, lastHello = 0,
    netOk = nil, snapAt = 0,
    stats = { recv = 0, sent = 0, dup = 0, bad = 0, blk = 0 },
}

local MAGIC = "DCCFS"          -- 信封路由前缀: 一个广播当无数个用
local SEP = "\1"

--------------------------------------------------------------------------------
-- 5. 房间数组 IO (playerId = nil)
--------------------------------------------------------------------------------
local function A()
    return Data.Array
end

local function arrSize(id)
    local ok, n = pcall(A().GetSize, A(), id, nil)
    if not ok or n == nil then return 0 end
    return n
end

local function arrGet(id, i)
    local ok, v = pcall(A().GetValue, A(), id, nil, i)
    if not ok then return nil end
    return v
end

local function arrAdd(id, v)
    local ok = pcall(A().InsertValue, A(), id, nil, v)
    return ok
end

local function arrSet(id, i, v)
    local ok = pcall(A().SetValue, A(), id, nil, v, i)
    return ok
end

--------------------------------------------------------------------------------
-- 6. 房间ID: 单独一条数组,只属于本房间,不同步
--------------------------------------------------------------------------------
local function ridArrId(arrId) return tostring(arrId) .. "_rid" end

local function ensureRid(arrId)
    if S.rid then return S.rid end
    local ra = ridArrId(arrId)
    local v = arrGet(ra, 1)
    if v and v ~= "" then S.rid = v; return S.rid end
    local addr = tonumber(tostring({}):match("0x(%x+)"), 16) or 7
    local seed = ((os.time() or 0) * 1000003 + math.floor((os.clock() or 0) * 1000000)
                  + addr) % 2147483647
    math.randomseed(seed)
    for _ = 1, 3 do math.random(0, 65535) end
    local s = ""
    for i = 1, 5 do s = s .. string.format("%04x", math.random(0, 65535)) end
    S.rid = "r" .. s:sub(1, 20)
    pcall(A().InsertValue, A(), ra, nil, S.rid)
    if arrSize(ra) > 1 then
        -- 已有旧值(异常),以第1条为准
        local first = arrGet(ra, 1)
        if first and first ~= "" then S.rid = first end
    end
    return S.rid
end

--------------------------------------------------------------------------------
-- 7. 日志条目: 编解码 / 哈希链
--------------------------------------------------------------------------------
local GENESIS = string.rep("0", 32)

local function entryBody(e)
    return table.concat({ tostring(e.seq), tostring(e.clock), esc(e.rid), e.prev,
                          esc(e.op), esc(e.path), esc(e.val), esc(e.arg) }, "|")
end

local function entryStr(e)
    return table.concat({ tostring(e.seq), tostring(e.clock), esc(e.rid), e.prev, e.hash,
                          esc(e.op), esc(e.path), esc(e.val), esc(e.arg) }, "|")
end

local function parseEntry(s)
    if type(s) ~= "string" or s == "" then return nil end
    local f = split(s, "|")
    if #f < 9 then return nil end
    local seq, clock = tonumber(f[1]), tonumber(f[2])
    if not seq or not clock then return nil end
    return { seq = seq, clock = clock, rid = unesc(f[3]), prev = f[4], hash = f[5],
             op = unesc(f[6]), path = unesc(f[7]), val = unesc(f[8]), arg = unesc(f[9]) }
end

local function verifyEntry(e)
    if not e or type(e.hash) ~= "string" or #e.hash ~= 32 then return false end
    return md5(entryBody(e)) == e.hash
end

--------------------------------------------------------------------------------
-- 8. 载入本地日志 -> 排序 -> 建索引
--------------------------------------------------------------------------------
local function reindex()
    table.sort(S.log, function(a, b)
        if a.clock ~= b.clock then return a.clock < b.clock end
        if a.rid ~= b.rid then return a.rid < b.rid end
        return a.seq < b.seq
    end)
    S.byKey = {}; S.vv = {}; S.cw = {}; S.lastHash = {}
    -- 已按 (clock,rid,seq) 排好序: 同一 rid 内 seq 递增, 直接顺序覆盖即可
    local have = {}
    for _, e in ipairs(S.log) do
        S.byKey[e.rid .. ":" .. e.seq] = true
        if not S.vv[e.rid] or e.seq > S.vv[e.rid] then S.vv[e.rid] = e.seq end
        S.lastHash[e.rid] = e.hash
        local t = have[e.rid]
        if not t then t = {}; have[e.rid] = t end
        t[e.seq] = true
    end
    -- 连续水位(cumulative watermark): 只认 1..c 全部到齐的最高 c
    -- 用"最大 seq"会因乱序投递产生空洞, 导致中间条目永远补不回来
    for rid, set in pairs(have) do
        local c = 0
        while set[c + 1] do c = c + 1 end
        S.cw[rid] = c
    end
    S.dirty = true
end

local function loadLog(arrId)
    S.log = {}
    local n = arrSize(arrId)
    local i = 1
    while i <= n do
        local v = arrGet(arrId, i)
        if v ~= nil then
            local e = parseEntry(v)
            if e then S.log[#S.log + 1] = e end
        end
        i = i + 1
    end
    reindex()
    local mc = 0
    for _, e in ipairs(S.log) do if e.clock > mc then mc = e.clock end end
    S.clock = mc
    local ms = S.vv[S.rid] or 0
    S.seq = ms
end

--------------------------------------------------------------------------------
-- 9. 状态机: 排序后重放 -> 目录树(table 内存态)
--------------------------------------------------------------------------------
local function normPath(p)
    p = tostring(p or "")
    if p == "" then p = "/" end
    p = p:gsub("\\", "/")
    p = p:gsub("/+", "/")
    if p:sub(1, 1) ~= "/" then p = "/" .. p end
    if #p > 1 and p:sub(-1) == "/" then p = p:sub(1, -2) end
    return p
end

local function parentOf(p)
    local i = p:match(".*()/")
    if not i or i <= 1 then return "/" end
    return p:sub(1, i - 1)
end

local function nameOf(p)
    if p == "/" then return "" end
    local i = p:match(".*()/")
    return p:sub((i or 0) + 1)
end

local function isUnder(p, anc)
    if anc == "/" then return p ~= "/" end
    return p == anc or p:sub(1, #anc + 1) == anc .. "/"
end

-- 解析 [] / [n] / [-1]
local function resolveAppend(path, kids)
    local base = path:sub(1, -3)           -- 去掉 []
    local mx = 0
    local pre = base .. "["
    for k in pairs(kids or {}) do
        if k:sub(1, #pre) == pre then
            local n = tonumber(k:match("%[(%-?%d+)%]$"))
            if n and n > mx then mx = n end
        end
    end
    return base .. "[" .. (mx + 1) .. "]"
end

local function resolveNegOne(path, kids)
    local base = path:sub(1, #path - 4)
    local mx = 0
    local pre = base .. "["
    for k in pairs(kids or {}) do
        if k:sub(1, #pre) == pre then
            local n = tonumber(k:match("%[(%-?%d+)%]$"))
            if n and n > mx then mx = n end
        end
    end
    if mx == 0 then return base .. "[1]" end
    return base .. "[" .. mx .. "]"
end

local function buildTree()
    local tree = {}
    local snapBase = 0
    -- 找最后一个快照
    for i, e in ipairs(S.log) do
        if e.op == "SNP" then snapBase = i end
    end
    for i = snapBase > 0 and snapBase or 1, #S.log do
        local e = S.log[i]
        local op, p, val, arg = e.op, e.path, e.val, e.arg
        if op == "SNP" then
            for line in tostring(val):gmatch("[^\n]+") do
                local a, b = line:match("^([^\t]*)\t(.*)$")
                if a and a ~= "" then
                    local t, h = b:match("^(.):(.*)$")
                    tree[a] = { t = t or "f", v = (t == "f") and (h or "") or nil,
                                s = nil, n = "", clk = e.clock, rid = e.rid }
                end
            end
        elseif op == "D" then
            tree[p] = { t = "d", v = nil, s = nil, n = "", clk = e.clock, rid = e.rid }
        elseif op == "F" then
            tree[p] = { t = "f", v = val, s = tree[p] and tree[p].s or nil,
                        n = arg, clk = e.clock, rid = e.rid }
            if not (arg and arg:sub(1, 2) == "c:") then tree[p].s = nil end
        elseif op == "S" then
            local node = tree[p]
            if not node then node = { t = "f", v = "", s = {}, n = "", clk = e.clock, rid = e.rid }; tree[p] = node end
            node.s = node.s or {}
            node.s[tonumber(arg) or 0] = val
            node.clk = e.clock
        elseif op == "X" then
            for k in pairs(tree) do
                if k == p or isUnder(k, p) then tree[k] = nil end
            end
        elseif op == "M" then
            local src, dst = p, normPath(arg)
            local keys = {}
            for k in pairs(tree) do
                if k == src then keys[#keys + 1] = { k, dst }
                elseif isUnder(k, src) then keys[#keys + 1] = { k, dst .. k:sub(#src + 1) } end
            end
            for _, kv in ipairs(keys) do
                tree[kv[2]] = tree[kv[1]]
                tree[kv[1]] = nil
            end
        elseif op == "P" then
            if tree[p] then tree[p].mode = arg end
        end
    end
    -- 建子项索引
    local kids = {}
    for k in pairs(tree) do
        if k ~= "/" then
            local par = parentOf(k)
            kids[par] = kids[par] or {}
            kids[par][nameOf(k)] = true
        end
    end
    S.tree, S.kids, S.dirty = tree, kids, false
    S.snapAt = snapBase
    return tree
end

local function T()
    if S.dirty or not S.tree then buildTree() end
    return S.tree
end

--------------------------------------------------------------------------------
-- 10. 出块 / 发条
--------------------------------------------------------------------------------
local function enqueue(e)
    S.out[#S.out + 1] = entryStr(e)
end

local function emit(arrId, op, path, val, arg, clkOverride)
    local clk = clkOverride
    if not clk then
        S.clock = S.clock + 1
        clk = S.clock
    elseif clk > S.clock then
        S.clock = clk
    end
    S.seq = S.seq + 1
    local prev = S.lastHash[S.rid] or GENESIS
    local e = { seq = S.seq, clock = clk, rid = S.rid, prev = prev,
                hash = "", op = op, path = path, val = val or "", arg = arg or "" }
    e.hash = md5(entryBody(e))
    S.log[#S.log + 1] = e
    S.byKey[e.rid .. ":" .. e.seq] = true
    S.vv[S.rid] = e.seq
    if (S.cw[S.rid] or 0) == e.seq - 1 then S.cw[S.rid] = e.seq end
    S.lastHash[S.rid] = e.hash
    S.dirty = true
    arrAdd(arrId, entryStr(e))
    enqueue(e)
    return e
end

--------------------------------------------------------------------------------
-- 11. 网络: 云服全服广播(一个广播当无数个用: 信封路由)
--------------------------------------------------------------------------------
local function envelope(kind, body)
    return MAGIC .. SEP .. kind .. SEP .. body
end

local function sendRaw(self, payload)
    local msgId = self.msgId
    if not msgId or msgId == "" then return false, "未配置云服广播消息ID" end
    local room = self.roomId
    local ok, err
    if room and room ~= "" then
        ok, err = pcall(function() return self:PushCloudServerMsg(msgId, payload, room) end)
    else
        ok, err = pcall(function() return self:PushCloudServerMsg(msgId, payload) end)
    end
    if not ok then return false, tostring(err) end
    return true, nil
end

local function broadcast(self, kind, body)
    local ok, err = sendRaw(self, envelope(kind, body))
    if ok then S.stats.sent = S.stats.sent + 1; S.netOk = true
    else S.netOk = false end
    return ok, err
end

-- 待发条目打包出块
local function flushBlock(self)
    if #S.out == 0 then return 0 end
    local maxN = tonumber(self.blockMax) or 12
    local maxC = tonumber(self.blockChars) or 3500
    local batch, used = {}, 0
    while #S.out > 0 and #batch < maxN do
        local e = S.out[1]
        local escE = esc(e)
        if #batch > 0 and used + #escE + 1 > maxC then break end
        if #escE > maxC and #batch > 0 then break end
        table.remove(S.out, 1)
        batch[#batch + 1] = escE
        used = used + #escE + 1
    end
    if #batch == 0 then return 0 end
    local ok = broadcast(self, "BLK", table.concat(batch, "|"))
    if ok then S.stats.blk = S.stats.blk + 1 else
        for i = #batch, 1, -1 do table.insert(S.out, 1, unesc(batch[i])) end
    end
    return #batch
end

--------------------------------------------------------------------------------
-- 12. 版本向量 / 摘要
--------------------------------------------------------------------------------
-- 广播出去的是"连续水位", 不是"最大seq" —— 只有水位才表达"还缺什么"
local function vvStr()
    local ks = {}
    for k in pairs(S.cw) do ks[#ks + 1] = k end
    table.sort(ks)
    local parts = {}
    for _, k in ipairs(ks) do parts[#parts + 1] = k .. ":" .. tostring(S.cw[k]) end
    return table.concat(parts, ",")
end

local function parseVV(s)
    local t = {}
    if not s or s == "" then return t end
    for kv in tostring(s):gmatch("[^,]+") do
        local k, v = kv:match("^([^:]+):(%-?%d+)$")
        if k then t[k] = tonumber(v) end
    end
    return t
end

local function stateRoot()
    local hs = {}
    for _, e in ipairs(S.log) do hs[#hs + 1] = e.hash end
    return merkleRoot(hs)
end

--------------------------------------------------------------------------------
-- 13. 收包处理
--------------------------------------------------------------------------------
local function applyEntries(arrId, strs)
    local added = 0
    for _, raw in ipairs(strs) do
        local e = parseEntry(raw)
        if not e then S.stats.bad = S.stats.bad + 1
        else
            local key = e.rid .. ":" .. e.seq
            if S.byKey[key] then
                S.stats.dup = S.stats.dup + 1
            elseif not verifyEntry(e) then
                S.stats.bad = S.stats.bad + 1
            else
                S.log[#S.log + 1] = e
                S.byKey[key] = true
                if not S.vv[e.rid] or e.seq > S.vv[e.rid] then S.vv[e.rid] = e.seq end
                if e.clock > S.clock then S.clock = e.clock end
                arrAdd(arrId, entryStr(e))
                added = added + 1
            end
        end
    end
    if added > 0 then
        S.stats.recv = S.stats.recv + 1
        reindex()
    end
    return added
end

local function onBLK(self, arrId, body)
    local parts = split(body, "|")
    local strs = {}
    for i = 1, #parts do
        local s = unesc(parts[i])
        if s ~= "" then strs[#strs + 1] = s end
    end
    return applyEntries(arrId, strs)
end


--------------------------------------------------------------------------------
-- 12. 版本向量 / 摘要
--------------------------------------------------------------------------------
-- 广播出去的是"连续水位", 不是"最大seq" —— 只有水位才表达"还缺什么"
local function vvStr()
    local ks = {}
    for k in pairs(S.cw) do ks[#ks + 1] = k end
    table.sort(ks)
    local parts = {}
    for _, k in ipairs(ks) do parts[#parts + 1] = k .. ":" .. tostring(S.cw[k]) end
    return table.concat(parts, ",")
end

local function parseVV(s)
    local t = {}
    if not s or s == "" then return t end
    for kv in tostring(s):gmatch("[^,]+") do
        local k, v = kv:match("^([^:]+):(%-?%d+)$")
        if k then t[k] = tonumber(v) end
    end
    return t
end

local function stateRoot()
    local hs = {}
    for _, e in ipairs(S.log) do hs[#hs + 1] = e.hash end
    return merkleRoot(hs)
end

--------------------------------------------------------------------------------
-- 13. 收包处理
--------------------------------------------------------------------------------
local function applyEntries(arrId, strs)
    local added = 0
    for _, raw in ipairs(strs) do
        local e = parseEntry(raw)
        if not e then S.stats.bad = S.stats.bad + 1
        else
            local key = e.rid .. ":" .. e.seq
            if S.byKey[key] then
                S.stats.dup = S.stats.dup + 1
            elseif not verifyEntry(e) then
                S.stats.bad = S.stats.bad + 1
            else
                S.log[#S.log + 1] = e
                S.byKey[key] = true
                if not S.vv[e.rid] or e.seq > S.vv[e.rid] then S.vv[e.rid] = e.seq end
                if e.clock > S.clock then S.clock = e.clock end
                arrAdd(arrId, entryStr(e))
                added = added + 1
            end
        end
    end
    if added > 0 then
        S.stats.recv = S.stats.recv + 1
        reindex()
    end
    return added
end

local function onBLK(self, arrId, body)
    local parts = split(body, "|")
    local strs = {}
    for i = 1, #parts do
        local s = unesc(parts[i])
        if s ~= "" then strs[#strs + 1] = s end
    end
    return applyEntries(arrId, strs)
end

-- 收到别人心跳: 把"他水位以上"的条目补发过去
local function onHLO(self, arrId, body)
    local a, b = body:match("^([^;]*);(.*)$")
    local their = parseVV(a or "")
    local myRoot = b or ""
    local missing = {}
    for _, e in ipairs(S.log) do
        local have = their[e.rid] or 0
        if e.seq > have then missing[#missing + 1] = e end
    end
    if #missing == 0 then return 0 end
    if stateRoot() == myRoot then return 0 end
    -- 抑风暴退避: 对方已有数据时 15% 概率本轮不答(它还会再喊, 不影响最终收敛)
    local theirHas = false
    for _, v in pairs(their) do if v > 0 then theirHas = true; break end end
    if theirHas and math.random(1, 100) <= 15 then return 0 end

    -- 关键: 按 (rid,seq) 排序取前缀 = 一定落在"水位窗口"内, 保证单调推进。
    -- 若改成随机切片, 水位会永远停在 0(拿不到 seq=1), 收敛直接死锁。
    table.sort(missing, function(x, y)
        if x.rid ~= y.rid then return x.rid < y.rid end
        return x.seq < y.seq
    end)
    local maxN = tonumber(self.blockMax) or 12
    local maxC = tonumber(self.blockChars) or 3500
    local n = #missing
    local idxs = {}
    local take = math.min(maxN, n)
    for i = 1, take do idxs[#idxs + 1] = i end
    -- 放大: 再抓一个按自身 rid 散列定位的对齐块, 多个房间大概率抓到不同块
    if n > take then
        local blocks = math.floor((n - take) / maxN) + 1
        local h = 0
        for i = 1, #S.rid do h = (h * 31 + S.rid:byte(i)) % 1000003 end
        local b0 = take + (h % blocks) * maxN
        for i = b0, math.min(b0 + maxN - 1, n) do idxs[#idxs + 1] = i end
    end

    local batch, used = {}, 0
    for _, idx in ipairs(idxs) do
        local ee = esc(entryStr(missing[idx]))
        if #batch > 0 and used + #ee + 1 > maxC then break end
        batch[#batch + 1] = ee; used = used + #ee + 1
    end
    if #batch == 0 then return 0 end
    broadcast(self, "BLK", table.concat(batch, "|"))
    return #batch
end
function Script:OnCloudEvent(...)
    local arrId = self.arrId or "FSLog"
    if not S.ready then Script.Init(self) end
    local n = select("#", ...)
    local payload = nil
    for i = 1, n do
        local v = select(i, ...)
        if type(v) == "string" and v:sub(1, #MAGIC) == MAGIC then payload = v; break end
    end
    if not payload then return "IGNORE" end
    local parts = split(payload, SEP)
    if #parts < 3 or parts[1] ~= MAGIC then return "BADENV" end
    local kind, body = parts[2], parts[3]
    if kind == "BLK" then
        local c = onBLK(self, arrId, body)
        return "BLK+" .. tostring(c)
    elseif kind == "HLO" then
        local c = onHLO(self, arrId, body)
        return "HLO+" .. tostring(c)
    end
    return "UNKNOWN"
end

--------------------------------------------------------------------------------
-- 14. 心跳 / 出块(定时器驱动)
--------------------------------------------------------------------------------
function Script:Tick()
    local arrId = self.arrId or "FSLog"
    if not S.ready then Script.Init(self) end
    local now = os.time() or 0
    local bs = tonumber(self.blockSec) or 10
    local hs = tonumber(self.helloSec) or 60
    local sent = flushBlock(self)
    if hs > 0 and (now - S.lastHello) >= hs then
        S.lastHello = now
        broadcast(self, "HLO", vvStr() .. ";" .. stateRoot())
    end
    return string.format("sent=%d out=%d log=%d", sent, #S.out, #S.log)
end

--------------------------------------------------------------------------------
-- 15. 初始化
--------------------------------------------------------------------------------
function Script:Init()
    local arrId = self.arrId or "FSLog"
    if S.ready then return true end
    if not Data or not Data.Array then return false end
    ensureRid(arrId)
    pcall(A().InsertValue, A(), arrId, nil, "")   -- 确保数组存在
    pcall(A().RemoveByValue, A(), arrId, nil, "")
    loadLog(arrId)
    S.ready = true
    if not S.hooked and self.msgId and self.msgId ~= "" and self.AddCloudSeverEvent then
        pcall(function()
            self:AddCloudSeverEvent(self.msgId, function(_, ...)
                return Script.OnCloudEvent(self, ...)
            end)
        end)
        S.hooked = true
    end
    if self.autoTimer and Timer and Timer.CreateTimer then
        pcall(function()
            Timer:CreateTimer(self, (tonumber(self.blockSec) or 10) * 1000,
                              function() Script.Tick(self) end)
        end)
    end
    return true
end

--------------------------------------------------------------------------------
-- 16. 文件系统操作
--------------------------------------------------------------------------------
function Script:Mkdir(path)
    local arrId = self.arrId or "FSLog"
    if not S.ready then Script.Init(self) end
    path = normPath(path)
    emit(arrId, "D", path, "", "")
    return "OK " .. path
end

function Script:Write(path, content)
    local arrId = self.arrId or "FSLog"
    if not S.ready then Script.Init(self) end
    local p = tostring(path or "")
    local append = false
    if p:sub(-2) == "[]" then append = true end
    if append then
        if S.dirty then buildTree() end
        p = resolveAppend(normPath(p), S.tree)
    elseif p:sub(-4) == "[-1]" then
        if S.dirty then buildTree() end
        p = resolveNegOne(normPath(p), S.tree)
    end
    path = normPath(p)
    content = tostring(content or "")
    local sb = tonumber(self.shardBytes) or 512
    local hex = tohex(content)
    -- 去重: 内容相同则跳过
    local cur = T()[path]
    if cur and cur.t == "f" and cur.n and cur.n:sub(1, 2) ~= "c:" and cur.v == hex then
        return "SKIP " .. path
    end
    if #content <= sb then
        emit(arrId, "F", path, hex, "")
    else
        S.clock = S.clock + 1
        local clk = S.clock
        local n, i = 0, 1
        while i <= #content do
            n = n + 1
            emit(arrId, "S", path, tohex(content:sub(i, i + sb - 1)), tostring(n), clk)
            i = i + sb
        end
        emit(arrId, "F", path, "", "c:" .. n, clk)
    end
    return string.format("OK %s (%dB)", path, #content)
end

local function nodeContent(node)
    if not node then return nil end
    if node.n and node.n:sub(1, 2) == "c:" then
        local sh = node.s or {}
        local out = {}
        for i = 1, 1 / 0 do
            if not sh[i] then break end
            out[#out + 1] = fromhex(sh[i])
        end
        return table.concat(out)
    end
    return fromhex(node.v or "")
end

function Script:Read(path)
    if not S.ready then Script.Init(self) end
    path = normPath(path)
    local node = T()[path]
    if not node then return "" end
    return nodeContent(node) or ""
end

function Script:List(path)
    if not S.ready then Script.Init(self) end
    if S.dirty or not S.kids then buildTree() end
    path = normPath(path)
    local k = S.kids[path] or {}
    local names = {}
    for n in pairs(k) do names[#names + 1] = n end
    table.sort(names)
    return table.concat(names, ",")
end

function Script:Delete(path)
    local arrId = self.arrId or "FSLog"
    if not S.ready then Script.Init(self) end
    path = normPath(path)
    if path == "/" then return "ERR 不能删根" end
    emit(arrId, "X", path, "", "")
    return "OK " .. path
end

function Script:Move(src, dst)
    local arrId = self.arrId or "FSLog"
    if not S.ready then Script.Init(self) end
    src = normPath(src); dst = normPath(dst)
    emit(arrId, "M", src, "", dst)
    return "OK " .. src .. " -> " .. dst
end

function Script:Copy(src, dst)
    if not S.ready then Script.Init(self) end
    src = normPath(src); dst = normPath(dst)
    local tree = T()
    local n = tree[src]
    if not n then return "ERR 源不存在" end
    if n.t == "d" then
        Script.Mkdir(self, dst)
        local kids = S.kids[src] or {}
        for name in pairs(kids) do Script.Copy(self, src .. "/" .. name, dst .. "/" .. name) end
        return "OK dir " .. src
    end
    return Script.Write(self, dst, nodeContent(n) or "")
end

-- 段内通配: * 匹配任意字符(非 /)
local function segMatch(pat, s)
    local p = "^" .. tostring(pat):gsub("[%^%$%(%)%%%.%[%]%+%-%?]", "%%%1"):gsub("%*", ".*") .. "$"
    return string.find(s, p) ~= nil
end

-- * 单段, ** 多段
local function matchPath(pat, p)
    local ps = split(pat, "/")
    local ss = split(p, "/")
    local i, j = 1, 1
    while i <= #ps do
        local seg = ps[i]
        if seg == "**" then
            if i == #ps then return true end
            local rest = {}
            for k = i + 1, #ps do rest[#rest + 1] = ps[k] end
            for k = j, #ss do
                local sub = {}
                for m = k, #ss do sub[#sub + 1] = ss[m] end
                if matchPath(table.concat(rest, "/"), table.concat(sub, "/")) then return true end
            end
            return false
        end
        if j > #ss then return false end
        if not segMatch(seg, ss[j]) then return false end
        i = i + 1; j = j + 1
    end
    return j > #ss
end

function Script:Find(pattern)
    if not S.ready then Script.Init(self) end
    if S.dirty then buildTree() end
    local pat = normPath(tostring(pattern or ""))
    local out = {}
    for k in pairs(S.tree) do
        if k ~= "/" and matchPath(pat, k) then out[#out + 1] = k end
    end
    table.sort(out)
    return table.concat(out, "\n")
end

function Script:Stat(path)
    if not S.ready then Script.Init(self) end
    if S.dirty then buildTree() end
    path = normPath(path)
    local n = S.tree[path]
    if not n then return "ERR 不存在" end
    local c = nodeContent(n) or ""
    return string.format("path=%s type=%s size=%d clk=%d owner=%s", path, n.t or "?", #c,
                         n.clk or 0, tostring(n.rid or "?"))
end

--------------------------------------------------------------------------------
-- 17. 运维
--------------------------------------------------------------------------------
function Script:Digest()
    if not S.ready then Script.Init(self) end
    return string.format("rid=%s cw=%s max=%s root=%s log=%d", tostring(S.rid), vvStr(),
                         tostring(S.vv[S.rid] or 0), stateRoot(), #S.log)
end

function Script:Status()
    if not S.ready then Script.Init(self) end
    return string.format("rid=%s ready=%s log=%d out=%d clock=%d seq=%d net=%s recv=%d sent=%d dup=%d bad=%d blk=%d",
        tostring(S.rid), tostring(S.ready), #S.log, #S.out, S.clock, S.seq,
        tostring(S.netOk), S.stats.recv, S.stats.sent, S.stats.dup, S.stats.bad, S.stats.blk)
end

function Script:Sync()
    if not S.ready then Script.Init(self) end
    local ok, err = broadcast(self, "HLO", vvStr() .. ";" .. stateRoot())
    return ok and ("OK " .. vvStr()) or ("FAIL " .. tostring(err))
end

function Script:Compact()
    local arrId = self.arrId or "FSLog"
    if not S.ready then Script.Init(self) end
    if S.dirty then buildTree() end
    local lines = {}
    local keys = {}
    for k in pairs(S.tree) do keys[#keys + 1] = k end
    table.sort(keys)
    for _, k in ipairs(keys) do
        local n = S.tree[k]
        if n.t == "d" then lines[#lines + 1] = k .. "\td:"
        else lines[#lines + 1] = k .. "\tf:" .. tostring(n.v or "") end
    end
    emit(arrId, "SNP", "/", table.concat(lines, "\n"), "")
    return string.format("OK snapshot=%d entries log=%d", #lines, #S.log)
end

function Script:Verify()
    if not S.ready then Script.Init(self) end
    local bad, chains = 0, 0
    local byRid = {}
    for _, e in ipairs(S.log) do
        if not verifyEntry(e) then bad = bad + 1 end
        local prev = byRid[e.rid]
        if prev then
            if e.seq == prev.seq + 1 then
                chains = chains + 1
                if e.prev ~= prev.hash then bad = bad + 1 end
            end
        end
        if not byRid[e.rid] or e.seq > byRid[e.rid].seq then byRid[e.rid] = e end
    end
    return string.format("log=%d bad=%d chain_ok=%d root=%s", #S.log, bad, chains, stateRoot())
end

-- 调试/自检钩子(非开放函数,引擎不注册)
_DCFS_DBG = { md5 = md5, S = S, merkleRoot = merkleRoot, esc = esc, unesc = unesc }

function Script:NetProbe()
    if not S.ready then Script.Init(self) end
    local ok, err = sendRaw(self, envelope("HLO", "probe;0"))
    return string.format("PushCloudServerMsg=%s msgId=%s room=%s err=%s bit=%s",
        tostring(ok), tostring(self.msgId), tostring(self.roomId), tostring(err),
        BIT.native and "native" or "fallback")
end

--------------------------------------------------------------------------------
-- 18. 引擎入口
--------------------------------------------------------------------------------
function Script:OnStart()
    if self.autoInit == false then return end
    Script.Init(self)
    Script.Sync(self)          -- 进图先喊一嗓子, 让老房间把存量推过来
end

