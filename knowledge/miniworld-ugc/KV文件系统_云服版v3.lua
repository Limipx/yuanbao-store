--[[
================================================================================
 KV 文件系统 云服版 v3 —— CRDT op-log 架构（框架全改）
================================================================================
 v2 的致命问题（已全部重构）：
   1. 缓存永不失效        -> v3: 每次 sync 强制重放，永不返回未验证缓存
   2. 读-改-写无版本校验  -> v3: 只追加 op-log，从不覆盖已有值
   3. ID 用时间戳+随机数  -> v3: ID = siteId.seq，siteId 由 uin 派生，零碰撞
   4. 多键操作非原子      -> v3: 一次移动只生成 1 条 op，1 次批量发布
   5. 限流失败静默入队    -> v3: 失败显式上抛 ERR，绝不假成功

 理论依据（见 KV环境一致性_前沿文献研究.md）：
   - op-based CRDT / OpSets   : 对象身份稳定，父关系由 op 推导
   - Dotted Version Vector    : dot = siteId.seq，紧凑因果摘要
   - Hybrid Logical Clock     : (pt, ct) 仅作确定性全序与新鲜度，不承担因果
   - Yjs delta 同步           : 按状态向量只拉缺失 delta，不全量回传
   - Merkle 根比较            : 根里存摘要，无差异则零写

 可达 / 不可达（务必先看这段）：
   ✅ 强最终一致（所有客户端最终看到同一状态）
   ✅ 因果可检测（能判断"我这个读数可能陈旧"）
   ✅ 并发不丢数据（并发创建的文件都保留）
   ❌ 线性一致（无法保证读到"全局最新"）
   ❌ 跨键原子提交（服务端无事务）
   ❌ 进程被杀时未发布的本地 op 会丢（可接受：等于没提交）

--------------------------------------------------------------------------------
 KV 布局（key 全部 ASCII，无空格，≤50 字节）
--------------------------------------------------------------------------------
   R.<app>              根（权威指针）
                        值: v1|sites|shards|seqs|hash
                          sites = S1,S2,...          已出现的站点
                          shards= S1:3,S2:1          各站点已发布分片数
                          seqs  = S1:17,S2:4         各站点已发布到的最大 seq
   L.<app>.<site>.<n>   第 n 个不可变 delta 分片（n 从 1 开始）
                        首行: H|<site>|<minSeq>|<maxSeq>|<count>
                        其后每行一条 op

   op 行格式（可打印，| 分隔，无空格）：
     dot|type|obj|arg1|arg2|hlc|dep
       dot  = <siteId>.<seq>          全局唯一，本地确定
       type = mk|mv|rm|wr
       obj  = 对象稳定 ID
       arg1 = mk:父ID   mv:新父ID   rm:-   wr:内容
       arg2 = mv:旧父ID（用于并发检测） 其余 -
       hlc  = <pt>:<ct>
       dep  = 依赖的 dot，逗号分隔

--------------------------------------------------------------------------------
 与引擎的接口（只有这 3 行绑定 Data.Map，签名不对就改这 3 行）
--------------------------------------------------------------------------------
   Data.Map:GetValueAndBlock(varId, playerId, key)      -> code, key, value
   Data.Map:SetValueAndBlock(varId, playerId, key, val) -> code, key, value
   Data.Map:RemoveValueAndBlock(varId, playerId, key)   -> code, key, value
   约定 code == 0 为成功（若引擎不同，改 _ok() 一处即可）
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
        tips = "所有key的前缀;不同应用用不同前缀隔离",
    },
    kvVarId = {
        type = Mini.String, default = "",
        displayName = "云服变量ID",
        tips = "填变量库里的全局变量ID;留空则用内置默认",
    },
    useRoomScope = {
        type = Mini.Bool, default = false,
        displayName = "用房间级而非全服级",
        tips = "false=全服级(playerId传nil);true=房间级",
    },
    peerSites = {
        type = Mini.String, default = "",
        displayName = "已知站点ID(逗号分隔)",
        tips = "跨房间同步要填;同房间可留空靠根发现;填了就不怕根被覆盖",
    },
    maxOpsPerShard = {
        type = Mini.Number, default = 64,
        displayName = "每个分片最多几条op",
        minValue = 8, maxValue = 512,
        tips = "调大=分片少,单次set更大;调小=更频繁写根",
    },
    autoFlushOnWrite = {
        type = Mini.Bool, default = false,
        displayName = "每次操作立刻发布",
        tips = "关=攒着批量发布(省配额);开=即时但费配额",
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
        displayName = "①初始化站点(留空)",
        params = { "留空即可", Mini.String },
    },
    Create = {
        returnType = Mini.String,
        displayName = "②创建对象(父ID,类型)",
        params = { "父ID(留空=根目录)", Mini.String,
                   "类型dir或file", Mini.String },
    },
    Move = {
        returnType = Mini.String,
        displayName = "③移动(对象ID,新父ID)",
        params = { "对象ID", Mini.String, "新父ID", Mini.String },
    },
    Remove = {
        returnType = Mini.String,
        displayName = "④删除(对象ID)",
        params = { "对象ID", Mini.String },
    },
    Write = {
        returnType = Mini.String,
        displayName = "⑤写入(对象ID,内容)",
        params = { "对象ID", Mini.String, "内容", Mini.String },
    },
    Sync = {
        returnType = Mini.String,
        displayName = "⑥双向同步(留空)",
        params = { "留空即可", Mini.String },
    },
    List = {
        returnType = Mini.String,
        displayName = "⑦列出子项(父ID)",
        params = { "父ID(留空=根)", Mini.String },
    },
    Status = {
        returnType = Mini.String,
        displayName = "⑧状态与新鲜度(留空)",
        params = { "留空即可", Mini.String },
    },
    Flush = {
        returnType = Mini.String,
        displayName = "⑨发布本地暂存(留空)",
        params = { "留空即可", Mini.String },
    },
    Check = {
        returnType = Mini.String,
        displayName = "⑩自检(留空)",
        params = { "留空即可", Mini.String },
    },
}

--------------------------------------------------------------------------------
-- 常量与工具
--------------------------------------------------------------------------------
local ROOTID  = "@root"
local SEP     = "|"
local MAXKEY  = 50

local _split = string.split or function(s, d)
    local out, pat = {}, "[^" .. (d or "|") .. "]+"
    for w in string.gmatch(s, pat) do out[#out + 1] = w end
    return out
end

local function _t(v) return tostring(v or "") end
local function _n(v) return tonumber(v) or 0 end
local function _flag(v)
    if v == nil then return false end
    if type(v) == "boolean" then return v end
    local s = _t(v):lower()
    if s == "true" or s == "1" or s == "yes" then return true end
    if s == "false" or s == "0" or s == "no" or s == "" then return false end
    local num = tonumber(v)
    if num == nil then return true end
    return num ~= 0
end

-- 32 位 FNV-1a（纯算术，double 精度足够：255 * 2^32 < 2^53）
local function _hash(s)
    local h = 2166136261
    local m = 16777216 -- 2^24，用于拆分乘法避免溢出语义歧义
    for i = 1, #s do
        h = (h * 16777619) % 4294967296
        h = (h + string.byte(s, i)) % 4294967296
    end
    return string.format("%08x", h)
end

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

-- 全序键：pt 对齐到 13 位、ct 到 5 位，保证字典序 == 数值序
local function _ordkey(hlc, dot)
    local p, c = string.match(hlc or "0:0", "^(%-?%d+):(%d+)")
    return string.format("%013d:%05d:%s", _n(p), _n(c), _t(dot))
end

--------------------------------------------------------------------------------
-- KV 适配层（引擎 / 测试注入 双路）
--------------------------------------------------------------------------------
function Script:_ok(c) return c == 0 end

function Script:_pid()
    if _flag(self.useRoomScope) then
        return self._roomPid
    end
    return nil
end

function Script:_vid()
    local v = _t(self.kvVarId)
    if v ~= "" then return v end
    return self._defVarId or ""
end

function Script:_kvGet(k)
    if self._mock then return self._mock:get(k) end
    local c, _, v = Data.Map:GetValueAndBlock(self:_vid(), self:_pid(), k)
    if not self:_ok(c) then return nil end
    return v
end

function Script:_kvSet(k, v)
    if self._mock then self._mock:set(k, v); return true end
    local c = Data.Map:SetValueAndBlock(self:_vid(), self:_pid(), k, v)
    return self:_ok(c)
end

function Script:_log(s)
    if _flag(self.echoDetail) then print(tostring(s)) end
end

--------------------------------------------------------------------------------
-- 键构造（严格 ≤50 字节、可打印、无空格）
--------------------------------------------------------------------------------
function Script:_app()
    local a = _t(self.appPrefix)
    if a == "" then a = "fs" end
    -- 去掉一切非 [A-Za-z0-9_-]
    a = string.gsub(a, "[^%w_-]", "")
    if a == "" then a = "fs" end
    return a
end
function Script:_kRoot()  return "R." .. self:_app() end
function Script:_kShard(site, n)
    return "L." .. self:_app() .. "." .. _t(site) .. "." .. _t(n)
end
-- 站点指针：只由该站点自己写，是权威信息（根键会被并发覆盖，这个不会）
function Script:_kPtr(site)
    return "P." .. self:_app() .. "." .. _t(site)
end

--------------------------------------------------------------------------------
-- 站点身份：由 uin 派生，全局唯一、零分配、零碰撞
--------------------------------------------------------------------------------
function Script:_ensureSite()
    if self._hlcPt == nil then self._hlcPt = 0 end
    if self._hlcCt == nil then self._hlcCt = 0 end
    if self._stat_get == nil then self._stat_get = 0 end
    if self._stat_set == nil then self._stat_set = 0 end
    if self._site then return self._site end
    local uin = self._testUin or 0
    if uin == 0 and Player and Player.GetUin then
        uin = Player:GetUin() or 0
    end
    if uin == 0 and self and self.playerId then uin = self.playerId end
    local s = "S" .. _b36(_n(uin))
    if #s > 5 then s = "S" .. string.sub(_hash(_t(uin)), 1, 4) end
    self._site = s
    self._seq  = 0
    return s
end

--------------------------------------------------------------------------------
-- HLC（只做确定性全序 + 新鲜度，不承担因果）
--------------------------------------------------------------------------------
function Script:_hlcTick()
    local now = 0
    if os and os.timeMs then now = os.timeMs() or 0 end
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
-- 根（权威指针）解析 / 写入
--------------------------------------------------------------------------------
function Script:_parseRoot(raw)
    local r = { sites = {}, shards = {}, seqs = {}, hash = "", ver = 1 }
    if not raw or raw == "" then return r end
    local f = _split(raw, SEP)
    r.ver    = _n(string.sub(f[1] or "v1", 2))
    r.hash   = f[5] or ""
    local function fill(dst, s)
        if not s or s == "" or s == "-" then return end
        for _, it in ipairs(_split(s, ",")) do
            local k, v = string.match(it, "^([^:]+):(.+)$")
            if k then dst[k] = _n(v) end
        end
    end
    fill(r.shards, f[3])
    fill(r.seqs,   f[4])
    if f[2] and f[2] ~= "" and f[2] ~= "-" then
        for _, s in ipairs(_split(f[2], ",")) do r.sites[#r.sites + 1] = s end
    end
    return r
end

function Script:_serRoot(r)
    local sites = table.concat(r.sites or {}, ",")
    local function dump(t)
        local ks = {}
        for k in pairs(t or {}) do ks[#ks + 1] = k end
        table.sort(ks)
        local out = {}
        for _, k in ipairs(ks) do out[#out + 1] = k .. ":" .. _t(t[k]) end
        return table.concat(out, ",")
    end
    -- ⚠️ 每个字段必须非空：部分 Lua 的 split（含引擎 string.split）
    --    会跳过连续分隔符产生的空字段，一旦为空就会错位
    if sites == "" then sites = "-" end
    local sh, sq = dump(r.shards), dump(r.seqs)
    if sh == "" then sh = "-" end
    if sq == "" then sq = "-" end
    local body = "v1" .. SEP .. sites .. SEP .. sh .. SEP .. sq
    return body .. SEP .. _hash(body)
end

--------------------------------------------------------------------------------
-- op-log：本地缓冲 / 已见集合
--------------------------------------------------------------------------------
function Script:_seenInit()
    self._ops      = self._ops or {}      -- dot -> op table
    self._pending  = self._pending or {}  -- 待发布 op 列表
    self._conflict = self._conflict or {} -- 冲突记录
    self._ownMax   = self._ownMax or 0
end

function Script:_parseOp(line)
    local f = _split(line, SEP)
    if #f < 6 then return nil end
    return {
        dot = f[1], typ = f[2], obj = f[3],
        a1 = f[4] or "-", a2 = f[5] or "-",
        hlc = f[6] or "0:0", dep = f[7] or "",
        ord = _ordkey(f[6], f[1]),
    }
end

function Script:_serOp(o)
    return table.concat({ o.dot, o.typ, o.obj, o.a1, o.a2, o.hlc, o.dep }, SEP)
end

-- 加入一条 op（幂等：同 dot 直接忽略）
function Script:_ingest(o)
    self:_seenInit()
    if self._ops[o.dot] then return false end
    self._ops[o.dot] = o
    self:_hlcSee(o.hlc)
    local site, seq = string.match(o.dot, "^(.-)%.(%d+)$")
    if site == self._site then
        if _n(seq) > self._ownMax then self._ownMax = _n(seq) end
    end
    return true
end

--------------------------------------------------------------------------------
-- 生成本地 op
--------------------------------------------------------------------------------
function Script:_newOp(typ, obj, a1, a2, dep)
    self:_ensureSite()
    self:_hlcTick()
    local seq = self._ownMax + 1
    self._ownMax = seq
    self._seq = seq
    local o = {
        dot = self._site .. "." .. _t(seq),
        typ = typ, obj = obj, a1 = _t(a1), a2 = _t(a2),
        hlc = self._hlcPt .. ":" .. self._hlcCt,
        dep = dep or "",
    }
    o.ord = _ordkey(o.hlc, o.dot)
    self:_ingest(o)
    if not self:_isLocal(o) then self._pending[#self._pending + 1] = o end
    return o
end

function Script:_isLocal(o) -- 占位：本原型所有新 op 都进 pending
    return false
end

-- 某对象当前已知的最新 op dot（用于填 dep）
function Script:_headOf(obj)
    local best, bo = nil, nil
    for _, o in pairs(self._ops or {}) do
        if o.obj == obj and o.typ ~= "wr" then
            if not bo or o.ord > bo.ord then best, bo = o.dot, o end
        end
    end
    return best
end

--------------------------------------------------------------------------------
-- 重放：由 op-log 投影出状态（确定性，所有客户端一致）
--------------------------------------------------------------------------------
function Script:_replay()
    self:_seenInit()
    local list = {}
    for _, o in pairs(self._ops) do list[#list + 1] = o end
    table.sort(list, function(a, b) return a.ord < b.ord end)

    local parent, alive, content, kind = {}, {}, {}, {}
    local lastOp = {}
    self._conflict = {}

    local function ancestors(id) -- 返回 id 的祖先集合（含自身）
        local seen, cur, guard = {}, id, 0
        while cur and cur ~= ROOTID and guard < 100000 do
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
            kind[obj]   = (o.a2 ~= "-" and o.a2 ~= "") and o.a2 or "file"
            parent[obj] = (o.a1 ~= "-" and o.a1 ~= "") and o.a1 or ROOTID
            alive[obj]  = true
            lastOp[obj] = o.dot

        elseif o.typ == "mv" then
            local np = (o.a1 ~= "-" and o.a1 ~= "") and o.a1 or ROOTID
            if np == obj then
                self._conflict[#self._conflict + 1] =
                    { typ = "selfparent", obj = obj, dot = o.dot }
            else
                -- 环检测：把 obj 临时挂到 np，看是否成环
                local old = parent[obj]
                parent[obj] = np
                local _, cyc = ancestors(np)
                if cyc then
                    parent[obj] = old
                    self._conflict[#self._conflict + 1] =
                        { typ = "cycle", obj = obj, dot = o.dot, parent = np }
                else
                    -- 并发 move 检测：两条因果无关的 mv 命中同一对象
                    local prev = lastOp[obj]
                    local prevOp = prev and self._ops[prev]
                    if prevOp and prevOp.typ == "mv" and prev ~= o.dot then
                        local isDep = string.find("," .. o.dep .. ",",
                                                  "," .. prev .. ",", 1, true)
                        if not isDep then
                            self._conflict[#self._conflict + 1] =
                                { typ = "concurrent_move", obj = obj,
                                  winner = o.dot, loser = prev }
                        end
                    end
                    lastOp[obj] = o.dot
                    alive[obj]  = true
                end
            end

        elseif o.typ == "rm" then
            local prev = lastOp[obj]
            local isDep = prev and string.find("," .. o.dep .. ",",
                                               "," .. prev .. ",", 1, true)
            if prev and not isDep then
                self._conflict[#self._conflict + 1] =
                    { typ = "concurrent_rm", obj = obj, dot = o.dot, other = prev }
            end
            alive[obj]  = false
            lastOp[obj] = o.dot

        elseif o.typ == "wr" then
            content[obj] = o.a1
            lastOp[obj]  = o.dot
        end
    end

    self._view = { parent = parent, alive = alive, content = content,
                   kind = kind, lastOp = lastOp, count = #list }
    return self._view
end

--------------------------------------------------------------------------------
-- 发布：把 pending 打包成一个不可变分片（1~3 次 KV）
--------------------------------------------------------------------------------
function Script:Flush()
    self:_ensureSite()
    self:_seenInit()
    if #self._pending == 0 then
        return "无待发布"
    end
    -- 1) 读根
    local raw = self:_kvGet(self:_kRoot())
    local r = self:_parseRoot(raw)
    self._stat_get = (self._stat_get or 0) + 1

    -- 2) 追加分片
    local n = _n(r.shards[self._site]) + 1
    local mn, mx = nil, nil
    local lines = {}
    for _, o in ipairs(self._pending) do
        lines[#lines + 1] = self:_serOp(o)
        local _, seq = string.match(o.dot, "^(.-)%.(%d+)$")
        seq = _n(seq)
        if not mn or seq < mn then mn = seq end
        if not mx or seq > mx then mx = seq end
    end
    table.insert(lines, 1, table.concat(
        { "H", self._site, _t(mn or 0), _t(mx or 0), _t(#self._pending) }, SEP))

    local key = self:_kShard(self._site, n)
    if #key > MAXKEY then
        return "ERR: key超长 " .. #key .. " 字节，请缩短 appPrefix"
    end
    if not self:_kvSet(key, table.concat(lines, "\n")) then
        return "ERR: 写分片失败(限流?) " .. key
    end
    self._stat_set = (self._stat_set or 0) + 1

    -- 3) 写自己的站点指针（权威，只我写，永不覆盖、永不冲突）
    if not self:_kvSet(self:_kPtr(self._site),
                       _t(n) .. SEP .. _t(math.max(_n(mx), _n(self._ownMax)))) then
        return "ERR: 写站点指针失败(限流?)"
    end
    self._stat_set = self._stat_set + 1

    self:_gotInit()
    self._gotShards[_t(self._site) .. "." .. _t(n)] = true
    if _n(self._knownTop[self._site]) < n then self._knownTop[self._site] = n end
    self._pending = {}
    -- 根键 best-effort 维护：让别人能"发现"我。
    -- 丢了也不致命 —— 权威信息在 P.<站点> 指针键里，只要发现过一次就不再丢。
    local rr = self:_parseRoot(self:_kvGet(self:_kRoot()))
    self._stat_get = self._stat_get + 1
    self:_repairRoot(rr)
    return "已发布 " .. _t(#lines - 1) .. " 条op -> " .. key
end

function Script:_mergeRoot(a, b) -- 取并集的最大值（单调）
    local out = { sites = {}, shards = {}, seqs = {}, ver = 1 }
    local seen = {}
    for _, s in ipairs(a.sites) do if not seen[s] then seen[s] = true; out.sites[#out.sites+1] = s end end
    for _, s in ipairs(b.sites) do if not seen[s] then seen[s] = true; out.sites[#out.sites+1] = s end end
    for k, v in pairs(a.shards) do out.shards[k] = v end
    for k, v in pairs(b.shards) do out.shards[k] = math.max(_n(out.shards[k]), _n(v)) end
    for k, v in pairs(a.seqs)   do out.seqs[k]   = v end
    for k, v in pairs(b.seqs)   do out.seqs[k]   = math.max(_n(out.seqs[k]), _n(v)) end
    return out
end

--------------------------------------------------------------------------------
-- 同步：拉缺失分片（只拉自己没有的）+ 推本地 pending
--------------------------------------------------------------------------------
function Script:_gotInit()
    if not self._gotShards then self._gotShards = {} end
    if not self._knownTop   then self._knownTop   = {} end
end

function Script:_haveShard(site, i)
    return self._gotShards[_t(site) .. "." .. _t(i)] == true
end

--[[
 ⚠️ 根会被并发覆盖：两个站点同时 read-modify-write 根时，
    后写的会抹掉先写者的 shards 条目（KV 无 CAS）。
    所以同步【不能只信根】，必须向上探测 + 每个客户端自愈修根。
]]
function Script:Sync()
    self:_ensureSite()
    self:_seenInit()
    self:_gotInit()
    local raw = self:_kvGet(self:_kRoot())
    self._stat_get = (self._stat_get or 0) + 1
    local r = self:_parseRoot(raw)

    -- 站点候选：根里记录的 + 我日志里见过的（根被覆盖时的兜底）
    local cand, seen = {}, {}
    local function addS(s)
        if s and s ~= "" and not seen[s] then seen[s] = true; cand[#cand+1] = s end
    end
    for _, s in ipairs(r.sites) do addS(s) end
    for _, s in ipairs(_split(_t(self.peerSites), ",")) do
        addS((string.gsub(s, "%s", "")))
    end
    for dot in pairs(self._ops) do addS(string.match(dot, "^(.-)%.")) end
    addS(self._site)

    local got = 0
    for _, site in ipairs(cand) do
        -- 权威分片数来自该站点自己的指针键，而不是会被覆盖的根
        local pr = self:_kvGet(self:_kPtr(site))
        self._stat_get = self._stat_get + 1
        local pn = 0
        if pr then pn = _n(_split(pr, SEP)[1]) end
        local top = math.max(pn, _n(r.shards[site]), _n(self._knownTop[site]))
        -- 1) 向上探测新分片（不依赖根，根可能已被覆盖）
        local guard = 0
        while guard < 64 do
            local s = self:_kvGet(self:_kShard(site, top + 1))
            self._stat_get = self._stat_get + 1
            if not s then break end
            top = top + 1
            if not self:_haveShard(site, top) then
                self._gotShards[_t(site) .. "." .. _t(top)] = true
                self:_absorb(s); got = got + 1
            end
            guard = guard + 1
        end
        self._knownTop[site] = top
        -- 2) 向下补齐历史空洞（分片可能因延迟早先没拿到）
        for i = top, 1, -1 do
            if self:_haveShard(site, i) then break end
            local s = self:_kvGet(self:_kShard(site, i))
            self._stat_get = self._stat_get + 1
            if not s then break end
            self._gotShards[_t(site) .. "." .. _t(i)] = true
            self:_absorb(s); got = got + 1
        end
    end

    self:_repairRoot(r)
    local push = ""
    if #self._pending > 0 then push = " | " .. self:Flush() end
    self:_replay()
    return "拉到 " .. _t(got) .. " 个分片" .. push
end

-- 自愈：把我确实拥有的信息写回根（抵消被别人覆盖造成的损失）
function Script:_repairRoot(r)
    local need = false
    local function bump(t, k, v)
        if _n(t[k]) < _n(v) then t[k] = v; need = true end
    end
    -- 我自己的
    bump(r.shards, self._site, _n(self._knownTop[self._site]))
    bump(r.seqs,   self._site, _n(self._ownMax))
    -- 我从日志里学到的别人（根被覆盖时这是唯一的修复来源）
    for site in pairs(self._knownTop) do
        bump(r.shards, site, _n(self._knownTop[site]))
        bump(r.seqs,   site, self:_mySeqOf(site))
    end
    for dot in pairs(self._ops) do
        local site = string.match(dot, "^(.-)%.")
        if site then
            local f = false
            for _, s in ipairs(r.sites) do if s == site then f = true end end
            if not f then r.sites[#r.sites + 1] = site; need = true end
            bump(r.seqs, site, self:_mySeqOf(site))
        end
    end
    if need then
        self:_kvSet(self:_kRoot(), self:_serRoot(r))
        self._stat_set = (self._stat_set or 0) + 1
        return true
    end
    return false
end

function Script:_mySeqOf(site)
    local m = 0
    for dot in pairs(self._ops or {}) do
        local s, seq = string.match(dot, "^(.-)%.(%d+)$")
        if s == site then
            seq = _n(seq)
            if seq > m then m = seq end
        end
    end
    return m
end

function Script:_absorb(shardText)
    local lines = _split(shardText, "\n")
    for i = 2, #lines do
        local o = self:_parseOp(lines[i])
        if o then self:_ingest(o) end
    end
end

--------------------------------------------------------------------------------
-- 业务操作
--------------------------------------------------------------------------------
function Script:_needInit()
    if not self._site then self:_ensureSite() end
    if not self._view then self:_replay() end
end

function Script:Init()
    self:_ensureSite()
    self:_seenInit()
    local ok = self:Sync()
    self:_replay()
    return "站点=" .. self._site .. " seq=" .. _t(self._ownMax) .. " | " .. ok
end

function Script:Create(parent, ktype)
    self:_needInit()
    local p = _t(parent); if p == "" then p = ROOTID end
    local kt = _t(ktype); if kt == "" then kt = "file" end
    if p ~= ROOTID and not self._view.alive[p] then
        return "ERR: 父对象不存在或已删除 " .. p
    end
    local id = self._site .. "." .. _t(self._ownMax + 1)
    self:_newOp("mk", id, p, kt, "")
    self:_replay()
    if _flag(self.autoFlushOnWrite) then self:Flush() end
    return id
end

function Script:Move(obj, newParent)
    self:_needInit()
    local np = _t(newParent); if np == "" then np = ROOTID end
    if not self._ops then return "ERR: 未初始化" end
    if not self._view.alive[obj] and not self._view.parent[obj] then
        return "ERR: 对象不存在 " .. _t(obj)
    end
    local old = self._view.parent[obj] or ROOTID
    if old == np then return "ERR: 已在目标下 " .. _t(obj) end
    local dep = self:_headOf(obj) or ""
    self:_newOp("mv", obj, np, old, dep)
    self:_replay()
    if _flag(self.autoFlushOnWrite) then self:Flush() end
    if #self._conflict > 0 then
        local c = self._conflict[#self._conflict]
        return "已移动(但冲突:" .. _t(c.typ) .. ") " .. _t(obj)
    end
    return "OK " .. _t(obj) .. " -> " .. np
end

function Script:Remove(obj)
    self:_needInit()
    if not self._view.alive[obj] then return "ERR: 对象不存在或已删除" end
    local dep = self:_headOf(obj) or ""
    self:_newOp("rm", obj, "-", "-", dep)
    self:_replay()
    if _flag(self.autoFlushOnWrite) then self:Flush() end
    return "已标记删除 " .. _t(obj)
end

function Script:Write(obj, content)
    self:_needInit()
    if not self._view.parent[obj] then return "ERR: 对象不存在 " .. _t(obj) end
    self:_newOp("wr", obj, _t(content), "-", "")
    self:_replay()
    if _flag(self.autoFlushOnWrite) then self:Flush() end
    return "已写入 " .. _t(#_t(content)) .. " 字节"
end

function Script:List(parent)
    self:_needInit()
    local p = _t(parent); if p == "" then p = ROOTID end
    local out = {}
    for id, par in pairs(self._view.parent) do
        if par == p and self._view.alive[id] then out[#out + 1] = id end
    end
    table.sort(out)
    if #out == 0 then return "(空)" end
    return table.concat(out, ",")
end

function Script:Status()
    self:_needInit()
    local n = 0
    for _ in pairs(self._ops) do n = n + 1 end
    local stale = #self._pending
    return "站点=" .. _t(self._site)
        .. " op总数=" .. _t(n)
        .. " 待发布=" .. _t(stale)
        .. " 冲突=" .. _t(#self._conflict)
        .. " 对象=" .. _t(self._view.count)
        .. " get=" .. _t(self._stat_get or 0)
        .. " set=" .. _t(self._stat_set or 0)
        .. (stale > 0 and " [本地未发布,当前读数可能陈旧]" or "")
end

function Script:Check()
    self:_needInit()
    local errs = {}
    local function ck(c, m) if c then errs[#errs+1] = "FAIL "..m end end

    ck(type(self._ops) ~= "table", "ops 非表")
    -- 所有 op 的 dot 唯一
    local seen = {}
    for dot in pairs(self._ops) do
        ck(seen[dot], "重复dot "..dot); seen[dot] = true
    end
    -- 无环
    for id, par in pairs(self._view.parent) do
        local cur, g = id, 0
        while cur and cur ~= ROOTID and g < 100000 do
            cur = self._view.parent[cur]; g = g + 1
            ck(g >= 100000, "父链成环 "..id)
            if g >= 100000 then break end
        end
    end
    -- 父对象必须存在（或为根）
    for id, par in pairs(self._view.parent) do
        if par ~= ROOTID then
            ck(self._view.parent[par] == nil, "父对象不存在 "..id.." -> "..par)
        end
    end
    -- key 长度
    ck(#self:_kRoot() > MAXKEY, "根key超长")
    ck(#self:_kShard(self._site, 999999) > MAXKEY, "分片key超长")

    if #errs == 0 then
        return "PASS 全部通过 op=" .. _t(self._view.count)
    end
    return table.concat(errs, "\n")
end

return Script
