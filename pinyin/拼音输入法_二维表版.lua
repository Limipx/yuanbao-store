--====================================================================
-- 拼音输入法 · 二维表版（迷你世界 UGC 3.0 · Lua 5.1 组件脚本）
--
-- 与旧版（数据内联在 Lua 里）的区别：
--   * 词库数据全部移出，存进 19 张二维表（每张 < 500KB）
--   * Lua 只负责：读表 -> 拼段 -> Base85 解码 -> inflate -> 变长解码 -> 查询
--   * 首次查询某拼音时才解压对应分桶，结果缓存，同拼音二次查询走缓存
--
-- 词库规模：494381 个拼音 key / 820678 条候选 / 163 个分桶
--          84233 条首字母模糊条目 / 字典汉字 13089
--
-- 二维表格式（与生成脚本严格对应，别手改）：
--   第 1 行  M|表序号|总表数|本表行数
--   之后：   H|载荷长度|crc32|段名        （段头，段名如 D / A / F / Bni）
--            C|载荷分片                    （连续若干行，可跨表；每片 2400 字符）
--
-- 容错设计（踩过的坑都写成保护了）：
--   1) 属性从组件实例 self 读，不读 Script 模板表（模板上是 nil）
--   2) 二维表行可能单列也可能多列 -> pickField 自动挑真正的载荷列
--   3) 段头带长度 + crc，缺行/串表会立刻发现，跳过而不是解出乱码
--   4) 表读不到 / 字典缺失 / 解压失败 -> 降级返回空串，绝不崩、绝不返回 nil
--   5) 输入容错：nil / 数字 / 空串 / 带声调 / 带空格 / 大小写，全部正常
--====================================================================
local Script = {}

--======================== 属性 ========================
Script.propertys = {
    tableIdsText = {
        type = Mini.String,
        default = "v7694277148953455613110817,v7694277153248422909110818,v7694575387187522557110907,v7694575412957326333110909,v7694575455906999293110911,v7694575481676803069110913,v7694575516036541437110915,v7694575537511377917110917,v7694575571871116285110919,v7694575597640920061110921,v7694575657770462205110923,v7694575687835233277110925,v7694575696425167869110927,v7694575747964775421110929,v7694575756554710013110931,v7694575816684252157110933,v7694575842454055933110935,v7694575868223859709110937,v7694575902583598077110939",
        displayName = "二维表ID组",
        tips = "19 张词库二维表的 ID，逗号分隔。已内置默认值，一般不用改"
    },
    maxResult = {
        type = Mini.Number,
        default = 20,
        displayName = "最多返回几个",
        minValue = 1,
        maxValue = 100,
        format = "%.0f个",
        tips = "候选太多时截断，默认20"
    },
    enableFuzzy = {
        type = Mini.Number,
        default = 1,
        displayName = "启用首字母模糊匹配",
        minValue = 0,
        maxValue = 1,
        format = "%.0f",
        tips = "1=开启。整串没命中时尝试首字母匹配（如 nh -> 你好）"
    },
    enableFallback = {
        type = Mini.Number,
        default = 1,
        displayName = "启用降级分词",
        minValue = 0,
        maxValue = 1,
        format = "%.0f",
        tips = "1=开启。整串没命中时按音节切分拼字（如 nihaoshijie -> 你好世界）"
    },
}

--======================== 开放函数 ========================
Script.openFnArgs = {
    Type = {
        returnType = Mini.String,
        displayName = "拼音打字",
        params = { "拼音", Mini.String }
    },
    TypeEx = {
        returnType = Mini.String,
        displayName = "拼音打字(带上限)",
        params = { "拼音", Mini.String, "最多几个", Mini.Number }
    },
    PinyinCount = {
        returnType = Mini.Number,
        displayName = "查拼音条数(调试)",
        params = { "拼音", Mini.String }
    },
    WarmUp = {
        returnType = Mini.String,
        displayName = "预热(建段索引)",
        params = {},
        tips = "提前扫描全部二维表建立段索引，之后查询更快。可留空调用"
    },
    Status = {
        returnType = Mini.String,
        displayName = "运行状态(调试)",
        params = {}
    },
}

--==================== 0. 属性读取 ====================
-- 铁律：属性值写在组件实例 self 上，读 Script.xxx 恒为 nil
-- （这个坑导致过 tableIds 崩溃、上限失效，别再犯）
local COMPONENT_SELF = nil

local function getProp(name, defv)
    local v
    if COMPONENT_SELF ~= nil then
        local ok, x = pcall(function() return COMPONENT_SELF[name] end)
        if ok and x ~= nil then v = x end
    end
    if v == nil then
        local ok2, x2 = pcall(function() return Script[name] end)
        if ok2 and x2 ~= nil then v = x2 end
    end
    return v ~= nil and v or defv
end
local function getNumProp(name, defv)
    local n = tonumber(getProp(name, defv))
    return n ~= nil and n or defv
end
local function getIds()
    local t = {}
    local txt = getProp("tableIdsText", "")
    if type(txt) == "string" and txt ~= "" then
        for p in txt:gmatch("[^,%s;，、\n\r]+") do
            local x = (p:gsub("^%s+", "")):gsub("%s+$", "")
            if x ~= "" then t[#t + 1] = x end
        end
    end
    return t
end

--==================== 1. bit / Base85 / Inflate ====================
local bit = bit
local band, bor, bxor, bnot = bit.band, bit.bor, bit.bxor, bit.bnot
local blshift, brshift = bit.lshift, bit.rshift
local Inflater = {}

--================ 0. bit 操作（迷你 bit 模块，一定存在）=================
local band    = bit.band
local bor     = bit.bor
local bxor    = bit.bxor
local bnot    = bit.bnot
local blshift = bit.lshift
local brshift = bit.rshift

local function pow2(n) return 2 ^ n end

local BitReader = {}
BitReader.__index = BitReader

function BitReader:new(data, startPos)
    local o = { data = data, pos = startPos or 1, buf = 0, cnt = 0 }
    setmetatable(o, self)
    return o
end

-- 读取 n 位（n <= 24），位序 LSB first（deflate 用）
function BitReader:readBits(n)
    while self.cnt < n do
        local b = string.byte(self.data, self.pos)
        if b == nil then return nil end
        self.pos = self.pos + 1
        self.buf = self.buf + b * pow2(self.cnt)
        self.cnt = self.cnt + 8
    end
    local q = pow2(n)
    local v = self.buf % q
    self.buf = (self.buf - v) / q
    self.cnt = self.cnt - n
    return v
end

-- 读取 1 位，返回 nil / 0 / 1
function BitReader:readBit()
    if self.cnt == 0 then
        local b = string.byte(self.data, self.pos)
        if b == nil then return nil end
        self.pos = self.pos + 1
        self.buf = b
        self.cnt = 8
    end
    local v = self.buf % 2
    self.buf = (self.buf - v) / 2
    self.cnt = self.cnt - 1
    return v
end

-- 丢弃到字节边界
function BitReader:alignByte()
    local drop = self.cnt % 8
    if drop > 0 then
        local q = pow2(drop)
        local v = self.buf % q
        self.buf = (self.buf - v) / q
        self.cnt = self.cnt - drop
    end
end

-- 高位在前的位读取器（JPEG 用：MSB first）
local MSBReader = {}
MSBReader.__index = MSBReader

function MSBReader:new(data, pos)
    local o = { data = data, pos = pos or 1, buf = 0, cnt = 0 }
    setmetatable(o, self)
    return o
end

-- JPEG 的字节填充：0xFF 后跟 0x00 表示字面量 0xFF
function MSBReader:_nextByte()
    local b = string.byte(self.data, self.pos)
    if b == nil then return nil end
    self.pos = self.pos + 1
    if b == 0xFF then
        local n = string.byte(self.data, self.pos)
        if n == 0x00 then
            self.pos = self.pos + 1
        elseif n == nil then
            return nil
        else
            -- 真正的标记：回退，交由上层处理
            self.pos = self.pos - 1
            return nil
        end
    end
    return b
end

function MSBReader:readBit()
    if self.cnt == 0 then
        local b = self:_nextByte()
        if b == nil then return nil end
        self.buf = b
        self.cnt = 8
    end
    self.cnt = self.cnt - 1
    local v = math.floor(self.buf / pow2(self.cnt))
    self.buf = self.buf % pow2(self.cnt)
    return v
end

function MSBReader:readBits(n)
    local v = 0
    for _ = 1, n do
        local b = self:readBit()
        if b == nil then return nil end
        v = v * 2 + b
    end
    return v
end

function MSBReader:alignByte()
    self.buf = 0
    self.cnt = 0
end

--================ 3. Canonical Huffman 解码 =================
-- counts[len] = 该码长的符号数；symbols 按 (码长, 符号值) 排序
-- 返回 { counts, symbols, minCode, maxCode, firstSymbolIndex }
local function buildHuffman(lengths)
    local counts = {}
    for i = 0, 16 do counts[i] = 0 end
    for i = 1, #lengths do
        local l = lengths[i] or 0
        counts[l] = counts[l] + 1
    end
    counts[0] = 0

    local minCode, firstIdx = {}, {}
    local code, idx = 0, 0
    for len = 1, 16 do
        code = code * 2
        -- firstIdx[len] 必须是 sum(counts[0..len-1])：先记录再累加，
        -- 不能在同一轮里既加 counts[len-1] 又加 counts[len]，否则下一轮会重复计一次
        firstIdx[len] = idx
        minCode[len] = code
        idx = idx + counts[len]
        code = code + counts[len]
    end

    local symbols = {}
    for sym = 0, #lengths - 1 do
        local l = lengths[sym + 1] or 0
        if l > 0 then
            -- 先取当前槽位再自增：firstIdx 初始即该码长的首个槽位（0-based）
            symbols[firstIdx[l]] = sym
            firstIdx[l] = firstIdx[l] + 1
        end
    end

    return { counts = counts, symbols = symbols, minCode = minCode, firstIdxSaved = firstIdx }
end

-- 用 LSB-first 读取器解码（inflate）
local function huffDecodeLSB(br, h)
    local code, first, index = 0, 0, 0
    for len = 1, 16 do
        local b = br:readBit()
        if b == nil then return nil end
        code = code * 2 + b          -- 先读到的位是码字的高位
        local count = h.counts[len]
        if code - first < count then
            return h.symbols[index + (code - first)]
        end
        index = index + count
        first = (first + count) * 2
        -- 注意：不能再 code = code * 2。位已在 code = code*2 + b 时左移过，
        -- 再左移一次会让每轮的位权翻倍，码字永远匹配不上。
    end
    return nil
end

-- 用 MSB-first 读取器解码（JPEG）
local function huffDecodeMSB(br, h)
    local code, first, index = 0, 0, 0
    for len = 1, 16 do
        local b = br:readBit()
        if b == nil then return nil end
        code = code * 2 + b
        local count = h.counts[len]
        if code - first < count then
            return h.symbols[index + (code - first)]
        end
        index = index + count
        first = (first + count) * 2
        -- 注意：不能再 code = code * 2。位已在 code = code*2 + b 时左移过，
        -- 再左移一次会让每轮的位权翻倍，码字永远匹配不上。
    end
    return nil
end

--================ 4. inflate（deflate 解压）=================
local LBASE = { 3,4,5,6,7,8,9,10,11,13,15,17,19,23,27,31,35,43,51,59,67,83,99,115,131,163,195,227,258 }
local LEXT  = { 0,0,0,0,0,0,0,0,1,1,1,1,2,2,2,2,3,3,3,3,4,4,4,4,5,5,5,5,0 }
local DBASE = { 1,2,3,4,5,7,9,13,17,25,33,49,65,97,129,193,257,385,513,769,1025,1537,2049,3073,4097,6145,8193,12289,16385,24577 }
local DEXT  = { 0,0,0,0,1,1,2,2,3,3,4,4,5,5,6,6,7,7,8,8,9,9,10,10,11,11,12,12,13,13 }

local FIXED_LIT, FIXED_DIST
local function initFixed()
    if FIXED_LIT then return end
    local l = {}
    for i = 1, 144 do l[i] = 8 end
    for i = 145, 256 do l[i] = 9 end
    for i = 257, 280 do l[i] = 7 end
    for i = 281, 288 do l[i] = 8 end
    FIXED_LIT = buildHuffman(l)
    local d = {}
    for i = 1, 30 do d[i] = 5 end
    FIXED_DIST = buildHuffman(d)
end

-- 解压 deflate 数据流；返回字符串
local CLEN_ORDER = {16,17,18,0,8,7,9,6,10,5,11,4,12,3,13,2,14,1,15}

-- 读取动态霍夫曼树的码长并构建字面量树/距离树
-- 返回 true, litTree, distTree 或 false, errmsg
local function readDynamicTrees(br)
    local hlit = br:readBits(5)
    local hdist = br:readBits(5)
    local hclen = br:readBits(4)
    if hlit == nil or hdist == nil or hclen == nil then
        return false, "动态树头读取失败"
    end
    hlit = hlit + 257
    hdist = hdist + 1
    hclen = hclen + 4

    local clen = {}
    for i = 1, 19 do clen[i] = 0 end
    for i = 1, hclen do
        local v = br:readBits(3)
        if v == nil then return false, "码长读取失败" end
        clen[CLEN_ORDER[i] + 1] = v
    end
    local clTree = buildHuffman(clen)
    if not clTree then return false, "码长树构建失败" end

    local lengths = {}
    local index = 0
    while index < hlit + hdist do
        local sym = huffDecodeLSB(br, clTree)
        if sym == nil then return false, "码长符号解码失败" end
        local symlen, rep
        if sym < 16 then
            symlen = sym
            rep = 1
        elseif sym == 16 then
            if index < 1 then return false, "码长重复 16 缺少前驱" end
            symlen = lengths[index] or 0
            rep = 3 + (br:readBits(2) or 0)
        elseif sym == 17 then
            symlen = 0
            rep = 3 + (br:readBits(3) or 0)
        else
            symlen = 0
            rep = 11 + (br:readBits(7) or 0)
        end
        for _ = 1, rep do
            if index >= hlit + hdist then return false, "码长数据溢出" end
            index = index + 1
            lengths[index] = symlen
        end
    end

    local litL, distL = {}, {}
    for i = 1, hlit do litL[i] = lengths[i] or 0 end
    for i = 1, hdist do distL[i] = lengths[hlit + i] or 0 end
    local lt = buildHuffman(litL)
    local dt = buildHuffman(distL)
    if not lt then return false, "字面量树构建失败" end
    if not dt then return false, "距离树构建失败" end
    return true, lt, dt
end


function Inflater.inflate(data, startPos)
    initFixed()
    local br = BitReader:new(data, startPos or 1)

    -- 滑动窗口输出缓冲：buf 保留最近 KEEP 字节供 dist 回溯，
    -- 超出的部分 flush 进 chunks，避免大图一次性占用巨量内存。
    local WINDOW, KEEP = 131072, 65536
    local chunks, nChunks = {}, 0
    local buf = ""
    local flushed = 0

    local function push(s)
        if s == "" then return end
        buf = buf .. s
        if #buf > WINDOW then
            local drop = #buf - KEEP
            nChunks = nChunks + 1
            chunks[nChunks] = string.sub(buf, 1, drop)
            buf = string.sub(buf, drop + 1)
            flushed = flushed + drop
        end
    end

    -- 取全局位置 gpos 起最多 len 字节（只从当前窗口内取）
    local function copyRange(gpos, len)
        local p = gpos - flushed
        if p < 1 then return "" end
        if p > #buf then return "" end
        return string.sub(buf, p, p + len - 1)
    end

    local last = 0
    while last == 0 do
        local b = br:readBit()
        if b == nil then break end
        last = b
        local btype = br:readBits(2)
        if btype == nil then break end

        if btype == 0 then
            -- 未压缩块
            br:alignByte()
            local len = string.byte(data, br.pos)
            local len2 = string.byte(data, br.pos + 1)
            if len == nil or len2 == nil then break end
            len = len + len2 * 256
            br.pos = br.pos + 4
            if br.pos + len - 1 > #data then break end
            push(string.sub(data, br.pos, br.pos + len - 1))
            br.pos = br.pos + len

        elseif btype == 1 or btype == 2 then
            local litTree, distTree
            if btype == 1 then
                litTree, distTree = FIXED_LIT, FIXED_DIST
            else
                local ok, l, d = readDynamicTrees(br)
                if not ok then return nil, l end
                litTree, distTree = l, d
            end

            while true do
                local sym = huffDecodeLSB(br, litTree)
                if sym == nil then return nil, "字面量解码失败" end
                if sym < 256 then
                    push(string.char(sym))
                elseif sym == 256 then
                    break
                else
                    local li = sym - 257 + 1
                    if li < 1 or li > 29 then return nil, "非法长度码 " .. tostring(sym) end
                    local length = LBASE[li] + (br:readBits(LEXT[li]) or 0)
                    local dsym = huffDecodeLSB(br, distTree)
                    if dsym == nil then return nil, "距离解码失败" end
                    if dsym > 29 then return nil, "非法距离码 " .. tostring(dsym) end
                    local dist = DBASE[dsym + 1] + (br:readBits(DEXT[dsym + 1]) or 0)
                    if dist < 1 then return nil, "非法距离 0" end

                    local total = flushed + #buf
                    local src = total - dist + 1
                    if src < 1 then return nil, "距离超出已输出数据" end
                    -- 先从历史窗口取能取到的部分
                    local avail = total - src + 1
                    local take = (length < avail) and length or avail
                    local res = copyRange(src, take)
                    if #res < take then
                        res = res .. string.rep("\0", take - #res)
                    end
                    -- 重叠部分（dist < length）由自身循环补齐
                    while #res < length do
                        local need = length - #res
                        res = res .. string.sub(res, 1, need)
                    end
                    push(res)
                end
            end
        else
            return nil, "非法的 deflate 块类型 3"
        end
    end

    nChunks = nChunks + 1
    chunks[nChunks] = buf
    return table.concat(chunks, "", 1, nChunks)
end

--==================== 压缩数据段 ====================

local function b85dec(s)
    if type(s) ~= "string" or #s == 0 then return "" end
    local out, i, n = {}, 1, #s
    while i <= n do
        local v, k = 0, 0
        while k < 5 do
            local c = string.byte(s, i + k) or 0x21
            local d = c - 0x21
            if d < 0 then d = 0 elseif d > 84 then d = 84 end
            v = v * 85 + d
            k = k + 1
        end
        i = i + 5
        out[#out + 1] = string.char(
            math.floor(v / 16777216) % 256, math.floor(v / 65536) % 256,
            math.floor(v / 256) % 256, v % 256)
    end
    return table.concat(out)
end


--==================== 2. 二维表读取与容错 ====================
local IDS = {}
local TABLE_ROWS = {}      -- 每张表的行数
local INDEX = nil          -- 段名 -> {ti, ri, len, crc}
local SCANNED = false
local SCAN_ERR = nil
local BIDX = {}            -- 桶名 -> 块首 key 数组

-- 二维表行可能单列也可能多列（CSV 导入后常见 3 列：行号/内容/空）。
-- 取真正的载荷：不是纯数字短串（行号），且取最长的那个字段。
local function pickField(row)
    if type(row) == "string" then return row end
    if type(row) ~= "table" then return nil end
    if #row == 1 then return row[1] end
    local best, blen = nil, -1
    for i = 1, #row do
        local v = row[i]
        if type(v) == "string" then
            local isNum = (#v <= 6) and (tonumber(v) ~= nil)
            if (not isNum) and #v > blen then best, blen = v, #v end
        end
    end
    return best or row[1]
end

local function readTable(tid)
    if not (Data and Data.Table and Data.Table.GetAllValue) then return nil end
    local ok, rows = pcall(function() return Data.Table:GetAllValue(tid, 1) end)
    if not ok or type(rows) ~= "table" then return nil end
    return rows
end

-- FNV-1a 校验和（与生成脚本 _crc 同算法）。
-- 注意：h * 16777619 最大到 7.2e16，已超过 double 的 2^53 精确范围，
-- 直接 band(...,0xFFFFFFFF) 会丢低位精度导致校验永远不符。
-- 所以把乘法拆成高 16 位 / 低 16 位两段，每步都控制在 2^53 以内，保证精确。
local function u32(x) return x < 0 and (x + 4294967296) or x end
local function crc32(s)
    local h = 2166136261
    local P, M = 16777619, 4294967296
    for i = 1, #s do
        h = u32(bxor(h, string.byte(s, i)))
        local a0 = h % 65536
        local a1 = math.floor(h / 65536)
        -- a0*P 与 a1*P 都 <= 1.1e12，安全；(a1*P)%65536*65536 只取低 16 位贡献
        h = (a0 * P + ((a1 * P) % 65536) * 65536) % M
    end
    return h
end

-- 扫描全部二维表，建立「段名 -> 位置」索引。
-- 逐表读取、处理完即丢弃，峰值只占一张表（约 475KB），不爆内存。
-- 最近一次段加载失败的原因（给 Status 诊断用）
local LAST_ERR = nil
-- 词库总表数（从 M|表序号|总表数|本表行数 解析），用于判断数据是否传完整
local TOTAL_TABLES = nil

local function scanAll()
    if SCANNED then return true end
    INDEX = {}
    TABLE_ROWS = {}
    local ntab = 0
    for ti = 1, #IDS do
        local rows = readTable(IDS[ti])
        if rows then
            ntab = ntab + 1
            TABLE_ROWS[ti] = #rows
            for ri = 1, #rows do
                local f = pickField(rows[ri])
                if type(f) == "string" and f:sub(1, 2) == "M|" then
                    -- M|表序号|总表数|本表行数 —— 拿到总表数才知道数据传全了没有
                    local q1 = f:find("|", 3, true)
                    local q2 = q1 and f:find("|", q1 + 1, true)
                    if q2 then
                        local tot = tonumber(f:sub(q1 + 1, q2 - 1))
                        if tot and tot > 0 then TOTAL_TABLES = tot end
                    end
                elseif type(f) == "string" and f:sub(1, 2) == "H|" then
                    -- H|len|crc|tag —— 只有 3 个竖线。
                    -- 踩过的坑：原写法多找了一层 p3（第 4 个竖线），
                    -- 而格式里根本没有第 4 个，p3 恒为 nil，
                    -- 结果全部表扫描成功、段索引却是 0 条、所有查询返回空串。
                    -- 表现是"扫描正常但字典死活载不进来"，极难从现象反推。
                    local p1 = f:find("|", 3, true)
                    local p2 = p1 and f:find("|", p1 + 1, true)
                    if p2 then
                        local ln = tonumber(f:sub(3, p1 - 1))
                        local cc = tonumber(f:sub(p1 + 1, p2 - 1))
                        local tag = f:sub(p2 + 1)
                        if ln and tag ~= "" then
                            INDEX[tag] = { ti = ti, ri = ri, len = ln, crc = cc or 0 }
                        end
                    end
                end
            end
            rows = nil
            if math.fmod(ti, 4) == 0 then collectgarbage("step") end
        else
            TABLE_ROWS[ti] = 0
        end
    end
    SCANNED = true
    if ntab == 0 then
        SCAN_ERR = "一张二维表都没读到，检查表 ID 是否正确（属性 tableIdsText）"
        return false
    end
    return true
end

local CHUNK = 2400   -- 与生成脚本一致

-- 按段名取出完整载荷。段分片连续存放，可跨表；跨表时下一张表从第 2 行继续
-- （第 1 行是 M| 清单行）。
local function loadPayload(tag)
    if not scanAll() then return nil end
    local h = INDEX[tag]
    if not h then return nil end
    local need = math.ceil(h.len / CHUNK)
    if need < 1 then need = 1 end
    local ti, ri = h.ti, h.ri
    local parts, np = {}, 0
    local cacheTi, cacheRows = -1, nil
    for _ = 1, need do
        -- 推进到下一条数据行
        ri = ri + 1
        if ri > (TABLE_ROWS[ti] or 0) then ti, ri = ti + 1, 2 end
        if ti > #IDS then break end
        if cacheTi ~= ti then
            cacheRows = readTable(IDS[ti])
            cacheTi = ti
        end
        if not cacheRows then break end
        local f = pickField(cacheRows[ri])
        if type(f) ~= "string" or f:sub(1, 2) ~= "C|" then
            -- 表头容错：CSV 导入时可能把「字段备注/字段名/字段类型」三行也带进二维表，
            -- 使 M| 清单行不在第 1 行，换表后 ri=2 会落在表头行上，整段被判为截断。
            -- 向后最多探测 10 行找真正的 C| 分片；找不到就放弃本段（CRC 会兜底，不会解出乱码）。
            local limit = math.min(TABLE_ROWS[ti] or 0, ri + 10)
            local k = ri
            while k <= limit do
                local pf = pickField(cacheRows[k])
                if type(pf) == "string" and pf:sub(1, 2) == "C|" then
                    f = pf
                    ri = k
                    break
                end
                k = k + 1
            end
        end
        if type(f) ~= "string" or f:sub(1, 2) ~= "C|" then
            -- 不是预期的分片行，说明串表或段被截断，放弃这一段
            LAST_ERR = "段 " .. tostring(tag) .. " 分片不完整(" .. np .. "/" .. need .. ")"
            break
        end
        np = np + 1
        parts[np] = f:sub(3)
    end
    cacheRows = nil
    local payload = table.concat(parts, "", 1, np)
    if #payload ~= h.len then return nil end
    if crc32(payload) ~= h.crc then return nil end
    return payload
end

--==================== 3. 字典与变长解码 ====================
local DIC = nil       -- 汉字数组（按索引 0 起）
local ASC = nil       -- ASCII 符号串
local NA, NHI, NB1, NB2 = 0, 128, 0, 0
local DIC_ERR = nil

local function splitUtf8(s)
    local out, n = {}, 0
    for c in string.gmatch(s, "[\1-\127\194-\244][\128-\191]*") do
        out[n] = c; n = n + 1
    end
    return out, n
end

local function loadDict()
    if DIC then return true end
    local pd = loadPayload("D")
    local pa = loadPayload("A")
    if not pa then
        DIC_ERR = (DIC_ERR or "") .. "符号表(A)缺失; "
    else
        -- A 段载荷： "字节数|base85"
        local bar = pa:find("|", 1, true)
        if bar then
            local ln = tonumber(pa:sub(1, bar - 1))
            local raw = b85dec(pa:sub(bar + 1))
            if ln and #raw >= ln then ASC = raw:sub(1, ln) end
        end
    end
    if not pd then
        DIC_ERR = (DIC_ERR or "") .. "字典(D)缺失; "
        return false
    end
    local bar = pd:find("|", 1, true)
    if not bar then DIC_ERR = "字典(D)格式错"; return false end
    local ln = tonumber(pd:sub(1, bar - 1))
    local raw = b85dec(pd:sub(bar + 1))
    if not ln or #raw < ln then DIC_ERR = "字典(D)长度不足"; return false end
    DIC, NHI = splitUtf8(raw:sub(1, ln))
    NA = #(ASC or "")
    NB1 = NA
    NB2 = NA + 128
    return true
end

-- 变长编码 -> 原文
local function vdecode(bs)
    if not DIC then return "" end
    local out, i, n, sb = {}, 1, #bs, string.byte
    local hs = ASC or ""
    while i <= n do
        local x = sb(bs, i)
        if x < NB1 then
            out[#out + 1] = hs:sub(x + 1, x + 1); i = i + 1
        elseif x < NB2 then
            out[#out + 1] = DIC[x - NB1] or ""; i = i + 1
        else
            out[#out + 1] = DIC[128 + (x - NB2) * 256 + (sb(bs, i + 1) or 0)] or ""
            i = i + 2
        end
    end
    return table.concat(out)
end

local function decodeSection(payload)
    local ok, raw = pcall(function() return Inflater.inflate(b85dec(payload), 3) end)
    if not ok or type(raw) ~= "string" or raw == "" then return nil end
    local ok2, txt = pcall(vdecode, raw)
    if not ok2 then return nil end
    return txt
end

--==================== 4. 分桶加载与查询 ====================
local function bucketKey(py)
    if #py >= 2 then return py:sub(1, 2) end
    return py:sub(1, 1)
end

-- 块索引：桶名 -> { 块首key 数组 }（极小，几十~几百字节）
local BIDX = {}
local function loadBucketIndex(bk)
    if BIDX[bk] then return BIDX[bk] end
    local payload = loadPayload("I" .. bk)
    if not payload then return nil end
    local ok, raw = pcall(function() return Inflater.inflate(b85dec(payload), 3) end)
    if not ok or type(raw) ~= "string" or raw == "" then return nil end
    local heads = {}
    for w in raw:gmatch("[^|]+") do heads[#heads + 1] = w end
    BIDX[bk] = heads
    return heads
end

-- 解析一个块成 key -> 候选串 的映射
local function parseMap(txt)
    local m = {}
    for entry in txt:gmatch("[^\1]+") do
        local eq = entry:find("=", 1, true)
        if eq and eq > 1 then m[entry:sub(1, eq - 1)] = entry:sub(eq + 1) end
    end
    return m
end

local CHUNK_CACHE = {}
local CHUNK_ORDER = {}
local CHUNK_MAX = 64

local function loadChunk(tag)
    local m = CHUNK_CACHE[tag]
    if m then return m end
    if not loadDict() then return nil end
    local payload = loadPayload(tag)
    if not payload then return nil end
    local txt = decodeSection(payload)
    if not txt then return nil end
    m = parseMap(txt)
    CHUNK_CACHE[tag] = m
    CHUNK_ORDER[#CHUNK_ORDER + 1] = tag
    while #CHUNK_ORDER > CHUNK_MAX do
        CHUNK_CACHE[table.remove(CHUNK_ORDER, 1)] = nil
    end
    return m
end

-- 按 key 定位到块：块首 key 有序，线性扫够快（每桶最多几十块）
local function chunkOf(heads, key)
    local n = #heads
    if n == 0 then return nil end
    local lo, hi = 1, n
    while lo < hi do
        local mid = math.floor((lo + hi + 1) / 2)
        if heads[mid] <= key then lo = mid else hi = mid - 1 end
    end
    return lo - 1      -- 0-based 块号
end

-- 精确查某个拼音：先读块索引定位，再只解压那一个块
local function exactLookup(py)
    local bk = bucketKey(py)
    local heads = loadBucketIndex(bk)
    if not heads and #bk > 1 then
        bk = py:sub(1, 1)
        heads = loadBucketIndex(bk)
    end
    if not heads then return nil end
    local ci = chunkOf(heads, py)
    if not ci or ci < 0 then return nil end
    local m = loadChunk("K" .. bk .. "#" .. tostring(ci))
    if not m then return nil end
    return m[py]
end

--==================== 首字母模糊表（按首字母分块）====================
local FUZZYC = {}
local function loadFuzzyFor(c)
    if FUZZYC[c] then return FUZZYC[c] end
    if not loadDict() then return nil end
    local payload = loadPayload("G" .. c)
    if not payload then return nil end
    local txt = decodeSection(payload)
    if not txt then return nil end
    local m = parseMap(txt)
    FUZZYC[c] = m
    return m
end

--==================== 5. 拼音归一化 ====================
local TONE = {
    ["\228\184\128"]="a",["\228\184\129"]="a",["\228\184\130"]="a",["\228\184\131"]="a",
    ["\197\141"]="e",["\233\166\137"]="e",["\233\166\138"]="e",["\233\166\139"]="e",
    ["\238\188\128"]="i",["\237\184\128"]="i",["\239\191\133"]="i",["\236\128\130"]="i",
    ["\229\147\140"]="o",["\229\147\141"]="o",["\231\187\143"]="o",["\232\184\128"]="o",
    ["\229\145\152"]="u",["\229\145\153"]="u",["\231\148\168"]="u",["\232\182\128"]="u",
    ["\231\147\145"]="v",["\252\143\133"]="v",["\252\143\134"]="v",["\252\143\135"]="v",
    ["\252\143\136"]="v",["\252\191\190"]="v",
}
local function normPinyin(s)
    if type(s) ~= "string" then s = tostring(s or "") end
    s = s:lower()
    -- 去声调字母（UTF-8 三字节）
    for k, v in pairs(TONE) do s = s:gsub(k, v) end
    -- ü/Ü 必须先映射成 v 再剥离：ü 是 UTF-8 双字节，
    -- 直接 [^a-z] 剥离会把两个字节都删掉（lüe -> le，查出来全是"了乐勒"）
    s = s:gsub("\195\188", "v"):gsub("\195\156", "v")
    s = s:gsub("[%s'%-_%.,]", "")
    -- 只保留 a-z。中文/数字/符号输入会被剥成空串，由调用方做容错处理
    s = s:gsub("[^a-z]", "")
    return s
end

--==================== 6. 音节表（用于降级切分）====================
local SYL = "a,ai,an,ang,ao,ba,bai,ban,bang,bao,bei,ben,beng,bi,bian,biao,bie,bin,bing,bo,bu,ca,cai,can,cang,cao,ce,cen,ceng,cha,chai,chan,chang,chao,che,chen,cheng,chi,chong,chou,chu,chua,chuai,chuan,chuang,chui,chun,chuo,ci,cong,cou,cu,cuan,cui,cun,cuo,da,dai,dan,dang,dao,de,dei,den,deng,di,dia,dian,diao,die,ding,diu,dong,dou,du,duan,dui,dun,duo,e,ei,en,er,fa,fan,fang,fei,fen,feng,fo,fou,fu,ga,gai,gan,gang,gao,ge,gei,gen,geng,gong,gou,gu,gua,guai,guan,guang,gui,gun,guo,ha,hai,han,hang,hao,he,hei,hen,heng,hong,hou,hu,hua,huai,huan,huang,hui,hun,huo,ji,jia,jian,jiang,jiao,jie,jin,jing,jiong,jiu,ju,juan,jue,jun,ka,kai,kan,kang,kao,ke,kei,ken,keng,kong,kou,ku,kua,kuai,kuan,kuang,kui,kun,kuo,la,lai,lan,lang,lao,le,lei,leng,li,lia,lian,liang,liao,lie,lin,ling,liu,lo,long,lou,lu,luan,lue,lun,luo,lv,lve,ma,mai,man,mang,mao,me,mei,men,meng,mi,mian,miao,mie,min,ming,miu,mo,mou,mu,na,nai,nan,nang,nao,ne,nei,nen,neng,ni,nian,niang,niao,nie,nin,ning,niu,nong,nou,nu,nuan,nue,nuo,nv,nve,o,ou,pa,pai,pan,pang,pao,pei,pen,peng,pi,pian,piao,pie,pin,ping,po,pou,pu,qi,qia,qian,qiang,qiao,qie,qin,qing,qiong,qiu,qu,quan,que,qun,ran,rang,rao,re,ren,reng,ri,rong,rou,ru,ruan,rui,run,ruo,sa,sai,san,sang,sao,se,sen,seng,sha,shai,shan,shang,shao,she,shei,shen,sheng,shi,shou,shu,shua,shuai,shuan,shuang,shui,shun,shuo,si,song,sou,su,suan,sui,sun,suo,ta,tai,tan,tang,tao,te,tei,teng,ti,tian,tiao,tie,ting,tong,tou,tu,tuan,tui,tun,tuo,wa,wai,wan,wang,wei,wen,weng,wo,wu,xi,xia,xian,xiang,xiao,xie,xin,xing,xiong,xiu,xu,xuan,xue,xun,ya,yan,yang,yao,ye,yi,yin,ying,yo,yong,you,yu,yuan,yue,yun,za,zai,zan,zang,zao,ze,zei,zen,zeng,zha,zhai,zhan,zhang,zhao,zhe,zhei,zhen,zheng,zhi,zhong,zhou,zhu,zhua,zhuai,zhuan,zhuang,zhui,zhun,zhuo,zi,zong,zou,zu,zuan,zui,zun,zuo"
local SYLLABLES = {}
do
    for w in string.gmatch(SYL, "[^,]+") do SYLLABLES[#SYLLABLES + 1] = w end
    table.sort(SYLLABLES, function(a, b) return #a > #b end)
end

-- 最长匹配切分：返回音节数组，切不动返回 nil
local function splitSyllables(py)
    local out, i, n = {}, 1, #py
    while i <= n do
        local hit = nil
        for k = 1, #SYLLABLES do
            local s = SYLLABLES[k]
            if i + #s - 1 <= n and py:sub(i, i + #s - 1) == s then hit = s; break end
        end
        if not hit then return nil end
        out[#out + 1] = hit
        i = i + #hit
    end
    return out
end

--==================== 7. 查询主逻辑 ====================
-- 截断到最多 n 个候选
local function cutCands(val, n)
    if type(val) ~= "string" or val == "" then return "" end
    if n <= 0 then return "" end
    local cnt = 0
    local pos = 0
    for i = 1, #val do
        if val:sub(i, i) == "," then
            cnt = cnt + 1
            if cnt >= n then return val:sub(1, i - 1) end
        end
    end
    return val
end

-- 降级：按音节切分，逐音节取首个候选字拼接
local function fallbackLookup(py)
    local syls = splitSyllables(py)
    if not syls or #syls < 2 then return nil end
    local out = {}
    for i = 1, #syls do
        local v = exactLookup(syls[i])
        if not v or v == "" then return nil end
        local first = v:match("^[^,]+")
        if not first or first == "" then return nil end
        out[#out + 1] = first
    end
    return table.concat(out)
end

-- 首字母模糊
local function fuzzyLookup(py)
    if getNumProp("enableFuzzy", 1) < 1 then return nil end
    local c = py:sub(1, 1)
    local f = loadFuzzyFor(c)
    if not f then return nil end
    return f[py]
end

-- 输入里是否含中文（用于区分"打的是汉字"和"打的是拼音"）
local function hasHan(s)
    if type(s) ~= "string" then return false end
    return s:find("[\228-\233][\128-\191][\128-\191]") ~= nil
end
local function rawText(py)
    if type(py) == "string" then return py end
    if py == nil then return "" end
    local ok, t = pcall(tostring, py)
    return ok and t or ""
end

-- 上轮遗留的两处容错在这统一收口：
--   * 输入是纯汉字/数字/符号 -> 明确提示，不再返回空串
--     （触发器拿空串等于拿到 nil，玩家看到的是"什么都没发生"）
--   * 拼音合法但词库没命中 -> 返回空串，由调用方决定兜底
local function doType(py, limit)
    local raw = rawText(py)
    local s = normPinyin(py)
    if s == "" then
        if raw == "" then return "" end
        if hasHan(raw) then return "（请输入拼音，如 nihao）" end
        return "（请输入拼音字母，如 nihao）"
    end
    local n = math.floor(limit or getNumProp("maxResult", 20))
    if n < 1 then n = 1 end

    -- 1) 精确
    local v = exactLookup(s)
    if v and v ~= "" then return cutCands(v, n) end

    -- 2) 降级分词（含 v->u / lve->lue 等常见变体回退）
    if getNumProp("enableFallback", 1) >= 1 then
        local fb = fallbackLookup(s)
        if fb and fb ~= "" then return fb end
    end

    -- 3) 首字母模糊
    local fz = fuzzyLookup(s)
    if fz and fz ~= "" then return cutCands(fz, n) end

    -- 4) v/ü 变体：nv<->nu、lv<->lu、nve<->nue、lve<->lue 互查
    local alt = s
    if alt:find("v") then
        alt = alt:gsub("nv", "nu"):gsub("lv", "lu"):gsub("nve", "nue"):gsub("lve", "lue")
    else
        alt = alt:gsub("nu", "nv"):gsub("lu", "lv"):gsub("nue", "nve"):gsub("lue", "lve")
    end
    if alt ~= s then
        local v2 = exactLookup(alt)
        if v2 and v2 ~= "" then return cutCands(v2, n) end
    end

    return ""
end

--==================== 8. 生命周期 ====================
function Script:OnStart()
    COMPONENT_SELF = self
    IDS = getIds()
    return true
end

function Script:OnDestroy()
    CHUNK_CACHE = {}
    CHUNK_ORDER = {}
    BIDX = {}
    FUZZYC = {}
    INDEX = nil
    SCANNED = false
    return true
end

function Script:Type(pinyin)
    if COMPONENT_SELF == nil then COMPONENT_SELF = self end
    if #IDS == 0 then IDS = getIds() end
    local ok, r = pcall(doType, pinyin, nil)
    if not ok then return "（查询出错：" .. tostring(r) .. "）" end
    if type(r) ~= "string" or r == "" then return "（没找到候选）" end
    return r
end

function Script:TypeEx(pinyin, limit)
    if COMPONENT_SELF == nil then COMPONENT_SELF = self end
    if #IDS == 0 then IDS = getIds() end
    local ok, r = pcall(doType, pinyin, limit)
    if not ok then return "（查询出错：" .. tostring(r) .. "）" end
    if type(r) ~= "string" or r == "" then return "（没找到候选）" end
    return r
end

function Script:PinyinCount(pinyin)
    if COMPONENT_SELF == nil then COMPONENT_SELF = self end
    if #IDS == 0 then IDS = getIds() end
    local ok, r = pcall(function()
        local s = normPinyin(pinyin)
        if s == "" then return 0 end
        local v = exactLookup(s)
        if not v or v == "" then return 0 end
        local c = 1
        for _ in v:gmatch(",") do c = c + 1 end
        return c
    end)
    if not ok then return 0 end
    return tonumber(r) or 0
end

function Script:WarmUp()
    if COMPONENT_SELF == nil then COMPONENT_SELF = self end
    if #IDS == 0 then IDS = getIds() end
    local t0 = os.timeMs()
    local ok = scanAll()
    local t1 = os.timeMs()
    if not ok then return "预热失败：" .. tostring(SCAN_ERR) end
    local n = 0
    for _ in pairs(INDEX or {}) do n = n + 1 end
    return string.format("预热完成：%d 张表 / %d 个段 / %d ms", #IDS, n, t1 - t0)
end

function Script:Status()
    if COMPONENT_SELF == nil then COMPONENT_SELF = self end
    if #IDS == 0 then IDS = getIds() end
    local ok = scanAll()
    local nread, nseg = 0, 0
    for ti = 1, #IDS do if (TABLE_ROWS[ti] or 0) > 0 then nread = nread + 1 end end
    if INDEX then for _ in pairs(INDEX) do nseg = nseg + 1 end end
    local t = { "二维表 " .. #IDS .. " 张(读到 " .. nread .. " 张)" }
    if TOTAL_TABLES then
        if nread < TOTAL_TABLES then
            t[#t + 1] = "!! 数据未传完 " .. nread .. "/" .. TOTAL_TABLES
                .. "，超出部分的拼音查不到（数据缺失，非脚本故障）"
        else
            t[#t + 1] = "数据完整 " .. nread .. "/" .. TOTAL_TABLES
        end
    end
    t[#t + 1] = "段索引: " .. nseg .. " 段" .. (ok and "" or "(未建立)")
    if SCAN_ERR then t[#t + 1] = "扫描错误: " .. SCAN_ERR end
    t[#t + 1] = "字典: " .. (DIC and ("已载入 " .. NHI .. " 字") or "未载入")
    if DIC_ERR then t[#t + 1] = "字典错误: " .. DIC_ERR end
    t[#t + 1] = "块缓存: " .. #CHUNK_ORDER .. "/" .. CHUNK_MAX
    local fn = 0
    for _ in pairs(FUZZYC) do fn = fn + 1 end
    t[#t + 1] = "模糊表: 已载入 " .. fn .. " 个首字母段"
    if LAST_ERR then t[#t + 1] = "最近加载失败: " .. LAST_ERR end
    return table.concat(t, "\n")
end


-- 调试导出（仅测试环境用；正式版无害）
_G.__DBG = {
    scanAll = scanAll, readTable = readTable, pickField = pickField,
    crc32 = crc32, loadPayload = loadPayload, loadDict = loadDict,
    loadBucketIndex = loadBucketIndex, chunkOf = chunkOf, loadChunk = loadChunk,
    exactLookup = exactLookup, normPinyin = normPinyin, INDEX = function() return INDEX end,
    DIC = function() return DIC, NHI, ASC end,
}
return Script
