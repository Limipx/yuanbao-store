--================================================================
-- 拼音输入法 v4 · 二维表满利用率版
--
-- 相比 v3 的改进：
--   1) 二维表从 19 张压到 15 张（每行塞满 2000 字符，每表装箱 495KB，
--      前 14 张实测 496.0~496.5KB = 99.3% 利用率，末表为余数）
--   2) 段索引写在每一行（C|段号|载荷），段可任意分散在任意表，
--      装箱不再受"段必须连续"限制，利用率才能拉满
--   3) base85 字符集排除 " \ , | 四个字符 -> CSV 零转义（省 1.17%）
--   4) 字典/符号表存原文 + 段名带字节长度，解码按长度截断，不再越界
--
-- 用法：把 csv/py4_01.csv ~ py4_15.csv 导入二维表，
--       把 15 个表 ID 逐项填进属性 tableIds（字符串数组，已预设 15 个槽位）。
--
-- v5 新增：Smart（混合输入自动判断）/ Correct（26键容错纠错）/ Type（类型诊断）
--
-- 开放函数：Smart / Query / Prefix / Abbr / Sentence / Correct / Type / Status / Warm
--================================================================

local Script = {}

Script.propertys = {
    tableIds = {
        type = Mini.Array,
        itemType = Mini.String,
        default = Mini.Array(Mini.String,
            "v7694277148953455613110817",
            "v7694277153248422909110818",
            "v7694575387187522557110907",
            "v7694575412957326333110909",
            "v7694575455906999293110911",
            "v7694575481676803069110913",
            "v7694575516036541437110915",
            "v7694575537511377917110917",
            "v7694575571871116285110919",
            "v7694575597640920061110921",
            "v7694575657770462205110923",
            "v7694575687835233277110925",
            "v7694575696425167869110927",
            "v7694575747964775421110929",
            "v7694575756554710013110931"
        ),
        displayName = "二维表ID组",
        customDisplayName = "表ID",
        tips = "15 张词库二维表的 ID，每项一行。导入 csv/py4_01..15.csv 后逐个填入"
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
        displayName = "启用模糊音",
        minValue = 0,
        maxValue = 1,
        format = "%.0f",
        tips = "1=开启。zh/z ch/c sh/s n/l in/ing en/eng 等互认"
    },
    enableTypo = {
        type = Mini.Number,
        default = 1,
        displayName = "26键打错容错",
        minValue = 0,
        maxValue = 2,
        format = "%.0f",
        tips = "0=关 1=编辑距离1(快) 2=编辑距离2(慢，覆盖漏打/多打/对调)"
    },
    keepSingle = {
        type = Mini.Number,
        default = 1,
        displayName = "单字母当拼音",
        minValue = 0,
        maxValue = 1,
        format = "%.0f",
        tips = "1=单个字母也按拼音转汉字(如 a->啊)；0=当英文原样输出"
    },
    enableFallback = {
        type = Mini.Number,
        default = 1,
        displayName = "启用降级分词",
        minValue = 0,
        maxValue = 1,
        format = "%.0f",
        tips = "1=开启。整串没命中时按音节切分拼字"
    },
}

--======================== 开放函数 ========================
Script.openFnArgs = {
    Query = {
        returnType = Mini.String,
        displayName = "拼音查字",
        params = { "拼音", Mini.String, "最多几个", Mini.Number }
    },
    Prefix = {
        returnType = Mini.String,
        displayName = "前缀联想",
        params = { "拼音前缀", Mini.String, "最多几个", Mini.Number }
    },
    Abbr = {
        returnType = Mini.String,
        displayName = "简拼查词",
        params = { "首字母串", Mini.String, "最多几个", Mini.Number }
    },
    Sentence = {
        returnType = Mini.String,
        displayName = "整句拼音",
        params = { "连续拼音", Mini.String, "每音几个", Mini.Number }
    },
    Warm = {
        returnType = Mini.String,
        displayName = "预热桶",
        params = { "桶名", Mini.String }
    },
    Smart = {
        returnType = Mini.String,
        displayName = "智能输入",
        params = { "任意输入", Mini.String, "每词几个", Mini.Number }
    },
    Correct = {
        returnType = Mini.String,
        displayName = "拼音纠错",
        params = { "打错的拼音", Mini.String }
    },
    Type = {
        returnType = Mini.String,
        displayName = "类型诊断",
        params = { "任意输入", Mini.String }
    },
    Status = {
        returnType = Mini.String,
        displayName = "状态诊断"
    },
}

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

--================ 新 base85（排除 " \ , | -> CSV 零转义）================
local R85 = {}
do
    local i, b = 0, 0x21
    while i < 85 do
        local c = string.char(b)
        if c ~= '"' and c ~= '\\' and c ~= ',' and c ~= '|' then
            R85[c] = i
            i = i + 1
        end
        b = b + 1
    end
end

local function b85dec(s)
    local out = {}
    local n, i, len = 0, 1, #s
    while i <= len do
        local g = s:sub(i, i + 4)
        local gl = #g
        if gl < 2 then break end
        local v = 0
        for j = 1, gl do
            v = v * 85 + (R85[g:sub(j, j)] or 0)
        end
        local nb = gl - 1
        for k = 0, nb - 1 do
            local sh = 8 * (3 - k)
            n = n + 1
            out[n] = string.char(math.floor(v / pow2(sh)) % 256)
        end
        i = i + 5
    end
    return table.concat(out)
end

--================ 二维表读取 =================
-- CSV 导入后行可能单列也可能多列（行号/内容/空），取真正的载荷列。
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

--================ UTF-8 切分（0-based 数组）================
local function splitUtf8(s)
    local out = {}
    local n = 0
    local i, len = 1, #s
    while i <= len do
        local b = string.byte(s, i)
        local cl
        if b < 0x80 then cl = 1
        elseif b >= 0xF0 then cl = 4
        elseif b >= 0xE0 then cl = 3
        elseif b >= 0xC0 then cl = 2
        else cl = 1 end
        out[n] = s:sub(i, i + cl - 1)
        n = n + 1
        i = i + cl
    end
    return out, n
end

--================ 段系统 =================
local IDS = {}
local SEGPOS = {}      -- sid -> { {表序号, 行号}, ... }（按全局顺序）
local NAME2SID = nil
local NAMES = nil
local SCANNED = false
local SCAN_ERR = nil
local TOTAL_TABLES = nil
local DIC, ASC = nil, nil
local NB1, NB2 = 0, 0
local LAST_ERR = nil
local SELFREF = nil   -- OnStart 里保存 self，运行时属性值从 self 读

-- 从字符串数组属性读取 ID（逐项过滤空串与过短项）
local function collectIds(arr)
    local t = {}
    if not arr then return t end
    local ok, n = pcall(function() return #arr end)
    if not ok or not n then return t end
    for i = 1, n do
        local v = arr[i]
        if type(v) == "string" and #v > 3 then t[#t + 1] = v end
    end
    return t
end

-- 扫描所有表，建立 SEGPOS（每行自带段号：C|<sid>|<载荷分片>）
local function scanAll()
    if SCANNED then return true end
    if #IDS == 0 then
        SCAN_ERR = "属性 tableIds 为空：请先导入二维表并把 15 个 ID 逐项填入"
        return false
    end
    SEGPOS = {}
    for ti = 1, #IDS do
        local rows = readTable(IDS[ti])
        if not rows then
            SCAN_ERR = SCAN_ERR or ("表 " .. ti .. " 读取失败")
        else
            for ri = 1, #rows do
                local f = pickField(rows[ri])
                if type(f) == "string" and f:sub(1, 2) == "C|" then
                    local p2 = f:find("|", 3)
                    if p2 then
                        local sid = tonumber(f:sub(3, p2 - 1))
                        if sid then
                            local a = SEGPOS[sid]
                            if not a then a = {}; SEGPOS[sid] = a end
                            a[#a + 1] = { ti, ri }
                        end
                    end
                end
            end
        end
    end
    SCANNED = true
    return true
end

local loadSegRaw

-- 段名表：MANIFEST 是 sid=0，其余段名按 sid 顺序排列
local function loadNames()
    if NAMES then return true end
    if not scanAll() then return false end
    local m = loadSegRaw(0)
    if not m then LAST_ERR = "MANIFEST 读取失败"; return false end
    NAMES = {}
    local i = 1
    for w in m:gmatch("[^,]+") do
        NAMES[i] = w
        i = i + 1
    end
    NAME2SID = {}
    for k = 1, #NAMES do NAME2SID[NAMES[k]] = k end
    NAME2SID["@MANIFEST"] = 0
    return true
end

-- 读取段（原始字节，未 vdecode）
local ROWSCACHE = {}
loadSegRaw = function(sid)
    if not scanAll() then return nil end
    local pos = SEGPOS[sid]
    if not pos then return nil end
    local parts = {}
    local np = 0
    for i = 1, #pos do
        local ti, ri = pos[i][1], pos[i][2]
        local rs = ROWSCACHE[ti]
        if rs == nil then rs = readTable(IDS[ti]); ROWSCACHE[ti] = rs end
        if rs then
            local f = pickField(rs[ri])
            if type(f) == "string" and f:sub(1, 2) == "C|" then
                local p2 = f:find("|", 3)
                if p2 and tonumber(f:sub(3, p2 - 1)) == sid then
                    np = np + 1
                    parts[np] = f:sub(p2 + 1)
                end
            end
        end
    end
    if np == 0 then return nil end
    local raw = b85dec(table.concat(parts))
    local ok, out = pcall(function() return Inflater.inflate(raw, 3) end)
    if not ok or not out then LAST_ERR = "段 " .. tostring(sid) .. " 解压失败"; return nil end
    return out
end

-- 字典按需加载
local function ensureDict()
    if DIC then return true end
    if not loadNames() then return false end
    -- 找 @D<len> 与 @A<len>
    local dn, an = nil, nil
    for i = 1, #NAMES do
        local nm = NAMES[i]
        if nm:sub(1, 2) == "@D" then dn = nm
        elseif nm:sub(1, 2) == "@A" then an = nm end
    end
    if not dn or not an then LAST_ERR = "字典段缺失"; return false end
    local db = loadSegRaw(NAME2SID[dn])
    local ab = loadSegRaw(NAME2SID[an])
    if not db or not ab then LAST_ERR = "字典段读取失败"; return false end
    local dlen = tonumber(dn:sub(3)) or #db
    local alen = tonumber(an:sub(3)) or #ab
    if #db > dlen then db = db:sub(1, dlen) end
    if #ab > alen then ab = ab:sub(1, alen) end
    DIC = splitUtf8(db)
    ASC = {}
    local na = 0
    for i = 1, #ab do na = na + 1; ASC[na] = ab:sub(i, i) end
    NB1 = na
    NB2 = na + 128
    return true
end

local function vdecode(b)
    if not ensureDict() then return nil end
    local out = {}
    local n = 0
    local i, len = 1, #b
    while i <= len do
        local x = string.byte(b, i)
        if x < NB1 then
            n = n + 1; out[n] = ASC[x + 1]; i = i + 1
        elseif x < NB2 then
            n = n + 1; out[n] = DIC[x - NB1]; i = i + 1
        else
            if i + 1 > len then break end
            local y = string.byte(b, i + 1)
            n = n + 1; out[n] = DIC[128 + (x - NB2) * 256 + y]; i = i + 2
        end
    end
    return table.concat(out)
end

-- 按段名取已解码文本（K/F 走 vdecode，其余只 inflate）
local SEGCACHE = {}
local SEGCACHE_N = 0
local function segText(name)
    local v = SEGCACHE[name]
    if v ~= nil then return v end
    if not loadNames() then return nil end
    local sid = NAME2SID[name]
    if not sid then return nil end
    local raw = loadSegRaw(sid)
    if not raw then return nil end
    local t = raw
    local c2 = name:sub(2, 2)
    if c2 == "K" or c2 == "F" then t = vdecode(raw) end
    if SEGCACHE_N >= 40 then SEGCACHE = {}; SEGCACHE_N = 0 end
    SEGCACHE[name] = t
    SEGCACHE_N = SEGCACHE_N + 1
    return t
end

--================ 工具 =================
local function split(s, sep)
    local t = {}
    local i = 1
    while true do
        local p = s:find(sep, i, true)
        if not p then t[#t + 1] = s:sub(i); break end
        t[#t + 1] = s:sub(i, p - 1)
        i = p + #sep
    end
    return t
end

-- 运行时属性值由引擎注入到 self 上，读 SELFREF[name]（self 在 OnStart 保存）
local function propNum(name, dft)
    local v = SELFREF and SELFREF[name]
    if v == nil then
        local p = Script.propertys and Script.propertys[name]
        if p then v = p.default end
    end
    v = tonumber(v)
    if v == nil then return dft end
    return v
end

local BUCKET_BLOCKS = {}

local function bucketHeads(bucket)
    local h = BUCKET_BLOCKS[bucket]
    if h then return h end
    local t = segText("@I" .. bucket)
    if not t then return nil end
    h = split(t, "|")
    BUCKET_BLOCKS[bucket] = h
    return h
end

-- 块内查找：块内容是 key=value，用 \1 分隔
local function lookupBlock(bucket, blk, py)
    local t = segText("@K" .. bucket .. "#" .. blk)
    if not t then return nil end
    for e in t:gmatch("[^\1]+") do
        local eq = e:find("=", 1, true)
        if eq and e:sub(1, eq - 1) == py then
            return e:sub(eq + 1)
        end
    end
    return nil
end

-- 二分定位块（返回最后一个 块首key <= py 的块号，0-based）
local function findBlock(heads, py)
    local lo, hi = 0, #heads - 1
    local best = 0
    while lo <= hi do
        local mid = math.floor((lo + hi) / 2)
        if heads[mid + 1] <= py then best = mid; lo = mid + 1
        else hi = mid - 1 end
    end
    return best
end

--================ 模糊音 =================
local FUZZY = {
    { "zh", "z" }, { "ch", "c" }, { "sh", "s" },
    { "ing", "in" }, { "eng", "en" }, { "ang", "an" },
    { "n", "l" }, { "r", "l" }, { "f", "h" },
}
local function fuzzyVariants(py)
    local out, seen = {}, {}
    seen[py] = true
    for _, r in ipairs(FUZZY) do
        local a, b = r[1], r[2]
        if py:find(a, 1, true) then
            local v = py:gsub(a, b)
            if not seen[v] then seen[v] = true; out[#out + 1] = v end
        end
        if py:find(b, 1, true) then
            local v = py:gsub(b, a)
            if not seen[v] then seen[v] = true; out[#out + 1] = v end
        end
    end
    return out
end

--================ 音节表（整句切分用）=================
local SYLSET = nil
local function ensureSyl()
    if SYLSET then return true end
    local t = segText("@S")
    if not t then return false end
    SYLSET = {}
    for w in t:gmatch("[^,%s]+") do SYLSET[w] = true end
    return true
end

local function cutSyl(s)
    if not SYLSET then return nil end
    local n = #s
    local f, pv = {}, {}
    f[0] = true
    for i = 1, n do
        for L = 6, 1, -1 do
            if i - L >= 0 and f[i - L] then
                local sub = s:sub(i - L + 1, i)
                if SYLSET[sub] then f[i] = true; pv[i] = L; break end
            end
        end
    end
    if not f[n] then return nil end
    local out = {}
    local i = n
    while i > 0 do
        local L = pv[i]
        out[#out + 1] = s:sub(i - L + 1, i)
        i = i - L
    end
    local r = {}
    for k = #out, 1, -1 do r[#r + 1] = out[k] end
    return r
end

--================ 核心查询 =================
local function takeN(cands, n)
    if not cands then return "" end
    local t = split(cands, ",")
    local m = #t
    if m > n then m = n end
    local o = {}
    for i = 1, m do o[i] = t[i] end
    return table.concat(o, ",")
end

local function queryExact(py)
    if not py or py == "" then return nil end
    local bucket = py:sub(1, 2)
    local heads = bucketHeads(bucket)
    if not heads then return nil end
    local blk = findBlock(heads, py)
    local v = lookupBlock(bucket, blk, py)
    if v then return v end
    if blk + 1 <= #heads - 1 then
        v = lookupBlock(bucket, blk + 1, py)
        if v then return v end
    end
    if blk - 1 >= 0 then
        v = lookupBlock(bucket, blk - 1, py)
        if v then return v end
    end
    return nil
end

--================ 开放函数 =================
function Script:Query(pinyin, n)
    n = tonumber(n) or 1
    local py = tostring(pinyin or ""):lower():gsub("[^a-z]", "")
    if py == "" then return "" end
    local v = queryExact(py)
    if not v and propNum("enableFuzzy", 1) == 1 then
        for _, fv in ipairs(fuzzyVariants(py)) do
            v = queryExact(fv)
            if v then break end
        end
    end
    return takeN(v, n)
end

function Script:Prefix(pinyin, n)
    n = tonumber(n) or propNum("maxResult", 20)
    local py = tostring(pinyin or ""):lower():gsub("[^a-z]", "")
    if py == "" then return "" end
    local bucket = py:sub(1, 2)
    local heads = bucketHeads(bucket)
    if not heads then return "" end
    local res = {}
    local cnt = 0
    for b = 0, #heads - 1 do
        local t = segText("@K" .. bucket .. "#" .. b)
        if t then
            for e in t:gmatch("[^\1]+") do
                local eq = e:find("=", 1, true)
                if eq then
                    local k = e:sub(1, eq - 1)
                    if k:sub(1, #py) == py then
                        cnt = cnt + 1
                        res[cnt] = e:sub(eq + 1)
                        if cnt >= 20 then break end
                    end
                end
            end
        end
        if cnt >= 20 then break end
    end
    return takeN(table.concat(res, ","), n)
end

function Script:Abbr(str, n)
    n = tonumber(n) or propNum("maxResult", 20)
    local s = tostring(str or ""):lower():gsub("[^a-z]", "")
    if s == "" then return "" end
    local seg = segText("@F" .. s:sub(1, 1))
    if not seg then return "" end
    for e in seg:gmatch("[^\1]+") do
        local eq = e:find("=", 1, true)
        if eq and e:sub(1, eq - 1) == s then
            return takeN(e:sub(eq + 1), n)
        end
    end
    return ""
end

-- 贪心最长匹配：从最长音节串开始试，命中即成词
local function greedyCut(s, maxlen)
    local i = 1
    local out = {}
    local n = #s
    while i <= n do
        local hit = nil
        local L = math.min(maxlen, n - i + 1)
        while L >= 1 do
            local sub = s:sub(i, i + L - 1)
            local v = queryExact(sub)
            if v then hit = { sub, v }; break end
            L = L - 1
        end
        if not hit then return nil end
        out[#out + 1] = hit
        i = i + #hit[1]
    end
    return out
end

function Script:Sentence(str, n)
    n = tonumber(n) or 1
    local s = tostring(str or ""):lower():gsub("[^a-z]", "")
    if s == "" then return "" end
    -- 先试贪心最长成词
    local parts = greedyCut(s, 12)
    if parts then
        local o = {}
        for i = 1, #parts do
            local t = split(parts[i][2], ",")
            o[i] = t[1] or ""
        end
        return table.concat(o, "")
    end
    -- 兜底：按音节 DP 切分，逐音取首字
    if not ensureSyl() then return "音节表未加载" end
    local sy = cutSyl(s)
    if not sy then return "无法切分" end
    local o = {}
    for i = 1, #sy do
        local v = queryExact(sy[i])
        if v then
            local t = split(v, ",")
            o[i] = t[1] or ""
        else
            o[i] = "?"
        end
    end
    return table.concat(o, "")
end

function Script:Warm(bucket)
    local b = tostring(bucket or ""):lower():gsub("[^a-z]", "")
    if b == "" then return "桶名为空" end
    local heads = bucketHeads(b)
    if not heads then return "桶 " .. b .. " 无索引" end
    local c = 0
    for i = 0, #heads - 1 do
        if segText("@K" .. b .. "#" .. i) then c = c + 1 end
    end
    return "已预热 " .. c .. " 块"
end

function Script:Status()
    local ok = scanAll()
    if not ok then return "ERR " .. tostring(SCAN_ERR) end
    local lines = {}
    lines[#lines + 1] = "表数=" .. #IDS
    if not loadNames() then
        return table.concat(lines, " | ") .. " | MANIFEST失败"
    end
    lines[#lines + 1] = "段数=" .. #NAMES
    local npos = 0
    for _ in pairs(SEGPOS) do npos = npos + 1 end
    lines[#lines + 1] = "已扫到段号=" .. npos
    if ensureDict() then
        lines[#lines + 1] = "字典ok"
    else
        lines[#lines + 1] = "字典未加载:" .. tostring(LAST_ERR)
    end
    local q = queryExact("ni")
    lines[#lines + 1] = "ni=" .. tostring(q and split(q, ",")[1] or "nil")
    return table.concat(lines, " | ")
end

function Script:OnStart()
    SELFREF = self
    IDS = collectIds(self.tableIds)
    local ok = scanAll()
    if not ok then
        print("[拼音v4] " .. tostring(SCAN_ERR))
        return
    end
    local c = 0
    for _ in pairs(SEGPOS) do c = c + 1 end
    print("[拼音v4] 表=" .. #IDS .. " 已扫段号=" .. c)
    if loadNames() then
        print("[拼音v4] 段名=" .. #NAMES)
    else
        print("[拼音v4] MANIFEST 读取失败: " .. tostring(LAST_ERR))
    end
end


--================ 26键容错（v5 新增）=================
-- QWERTY 物理邻键：手机 26 键最常见的误触来源
local NEIGHBOR = {
    q="wa", w="qes", e="wrd", r="etf", t="ryg", y="tuh", u="yij", i="uok",
    o="ipl", p="ol", a="qsz", s="awdz", d="sefx", f="drcg", g="fthv",
    h="gyjb", j="hukn", k="ijlm", l="kop", z="ax", x="zsc", c="xdv",
    v="cfb", b="vng", n="bmh", m="njk",
}
-- 插入操作只试这些字母（全试会爆炸，且真实误触集中在这几个）
local INSERT_SET = "aeiounzzhg"

-- 编辑距离（带上限剪枝，超过 limit 直接返回 limit+1）
local function editDist(a, b, limit)
    local la, lb = #a, #b
    if la > lb then a, b, la, lb = b, a, lb, la end
    if lb - la > limit then return limit + 1 end
    local prev = {}
    for j = 0, lb do prev[j] = j end
    for i = 1, la do
        local cur = { [0] = i }
        local ai = a:sub(i, i)
        local best = cur[0]
        for j = 1, lb do
            local cost = (ai == b:sub(j, j)) and 0 or 1
            local v = prev[j - 1] + cost
            if prev[j] + 1 < v then v = prev[j] + 1 end
            if cur[j - 1] + 1 < v then v = cur[j - 1] + 1 end
            cur[j] = v
            if v < best then best = v end
        end
        if best > limit then return limit + 1 end
        prev = cur
    end
    return prev[lb]
end

-- 单音节纠错：返回 SYLSET 内、编辑距离 <=1 的候选（不含自身）
local SYLFIX = setmetatable({}, { __mode = "k" })
-- 高频拼音（纠错同分时优先，避免 xihuan/pengyou/zhongguo 被同距离候选抢走）
local HIFREQ = {
    nihao=1, zhongguo=1, pengyou=1, xihuan=1, mingtian=1, woxihuan=1, xiexie=1,
    wo=1, ni=1, ta=1, women=1, nimen=1, tamen=1, zhege=1, nage=1, shenme=1,
    zenme=1, weishenme=1, keyi=1, bukeyi=1, yao=1, buyao=1, you=1,
    meiyou=1, shi=1, bushi=1, hao=1, buhao=1, lai=1, qu=1, kan=1, ting=1,
    shuo=1, zuo=1, chi=1, he=1, wan=1, xuexi=1, gongzuo=1, shijian=1,
    difang=1, dongxi=1, wenti=1, zhidao=1, buzhidao=1, xianzai=1, yijing=1,
    haiyou=1, danshi=1, yinwei=1, suoyi=1, ruguo=1, jiu=1, zai=1,
    jintian=1, zuotian=1, xiawu=1, shangwu=1, wanshang=1, dajia=1,
    laoshi=1, xuesheng=1, dianhua=1, diannao=1, shouji=1, wangluo=1,
    xinxi=1, shuju=1, kaishi=1, jieshu=1, chenggong=1, shibai=1, jiejue=1,
    zhunbei=1, jihua=1, xiwang=1, ganxie=1, duibuqi=1, qing=1, bangzhu=1,
    yidian=1, yixia=1, zheyang=1, zennmeyang=1, xing=1, buxing=1,
    zhongwen=1, yingwen=1, fanyi=1, yisi=1, lijie=1, mingbai=1,
    youxi=1, ditu=1, jiaose=1, zhuangbei=1, jineng=1, shuxing=1,
    dengji=1, jingyan=1, jinbi=1, daoju=1, beibao=1, renwu=1, guaiwu=1,
    fangkuai=1, jianzhu=1, shengcheng=1, qingchu=1, shanchu=1,
    xiugai=1, tianjia=1, chaxun=1,
woshi=1, ruhe=1, jiushi=1, zaijian=1, nihaoya=1, meiwenti=1, meiguanxi=1, wancheng=1, }

-- 邻键加权纠错代价：替换邻键 1，删/插 3，替换非邻键 4
local function typoCost(a, b, maxd)
    if a == b then return 0 end
    local la, lb = #a, #b
    if math.abs(la - lb) > (maxd or 99) then return 99 end
    local prev = {}
    for j = 0, lb do prev[j] = (j == 0) and 0 or (prev[j - 1] + 3) end
    for i = 1, la do
        local cur = {}
        cur[0] = prev[0] + 3
        local ca = a:sub(i, i)
        for j = 1, lb do
            local cb = b:sub(j, j)
            local rep = (ca == cb) and 0
                     or ((NEIGHBOR[ca] or ""):find(cb, 1, true) and 1 or 4)
            local v = prev[j - 1] + rep
            local de = prev[j] + 3
            local ins = cur[j - 1] + 3
            if de < v then v = de end
            if ins < v then v = ins end
            cur[j] = v
        end
        prev = cur
        if maxd then
            local mn = 99
            for j = 0, lb do if prev[j] < mn then mn = prev[j] end end
            if mn > maxd then return 99 end
        end
    end
    return prev[lb]
end

local function sylFix(syl)
    if not ensureSyl() then return nil end
    local c = SYLFIX[syl]
    if c then return c end
    local out, seen = {}, { [syl] = true }
    local function add(x)
        if x and x ~= "" and not seen[x] and SYLSET[x] then
            seen[x] = true; out[#out + 1] = x
        end
    end
    local n = #syl
    -- ① 替换（邻键）
    for i = 1, n do
        local ch = syl:sub(i, i)
        local nb = NEIGHBOR[ch]
        if nb then
            for k = 1, #nb do
                add(syl:sub(1, i - 1) .. nb:sub(k, k) .. syl:sub(i + 1))
            end
        end
    end
    -- ② 漏字母：删掉一位
    for i = 1, n do add(syl:sub(1, i - 1) .. syl:sub(i + 1)) end
    -- ③ 多打字母：插入一位
    for i = 0, n do
        for k = 1, #INSERT_SET do
            add(syl:sub(1, i) .. INSERT_SET:sub(k, k) .. syl:sub(i + 1))
        end
    end
    -- ④ 手快对调：相邻两位互换
    for i = 1, n - 1 do
        add(syl:sub(1, i - 1) .. syl:sub(i + 1, i + 1) .. syl:sub(i, i) .. syl:sub(i + 2))
    end
    c = out
    SYLFIX[syl] = c
    return c
end

-- 整串纠错：先切音节，逐音节取候选重组，再逐个试查
local function seqFix(py, limit)
    if not ensureSyl() then return nil end
    local cuts = cutSyl(py)
    if not cuts then return nil end
    local perSyl = {}
    local total = 1
    for i, sc in ipairs(cuts) do
        local cand = sylFix(sc) or {}
        local lst = { sc }
        for j = 1, #cand do
            if #lst >= 8 then break end
            lst[#lst + 1] = cand[j]
        end
        perSyl[i] = lst
        total = total * #lst
        if total > limit then break end
    end
    if total > limit then
        -- 组合爆炸：只纠错第一个音节（最常见的打错位置）
        perSyl = { perSyl[1] }
        total = #perSyl[1]
    end
    local idx = {}
    for i = 1, #perSyl do idx[i] = 1 end
    local tried = 0
    while tried < limit do
        local parts = {}
        for i = 1, #perSyl do parts[i] = perSyl[i][idx[i]] end
        local cand = table.concat(parts)
        if cand ~= py then
            tried = tried + 1
            local v = queryExact(cand)
            if v then return v, cand end
        end
        -- 进位
        local c = #perSyl
        while c >= 1 do
            idx[c] = idx[c] + 1
            if idx[c] <= #perSyl[c] then break end
            idx[c] = 1; c = c - 1
        end
        if c < 1 then break end
    end
    return nil
end

-- 英文保护：拼音串里不可能出现的辅音连缀（zh/ch/sh/ng 不能列，拼音里有）
local EN_MARK = {
    "th", "ck", "ph", "gh", "wh", "ll", "rr", "mm", "gg", "ff",
    "bb", "dd", "pp", "tt", "zz", "vv", "ww", "qq", "kk", "jj",
}
local function looksEnglish(w)
    -- 能以合法音节开头 => 一定是拼音，不是英文（zh/ng 这类连缀会误判）
    for _, L in ipairs({6, 5, 4, 3, 2}) do
        if #w >= L and SYLSET[w:sub(1, L)] then return false end
    end
    for _, m in ipairs(EN_MARK) do
        if w:find(m, 1, true) then return true end
    end
    return false
end

-- 兜底：同一 bucket 内扫所有 key，按编辑距离取最近的
local function bucketNearest(py, maxd)
    local bk = py:sub(1, 2)
    local heads = bucketHeads(bk)
    if not heads then return nil end
    local c = findBlock(heads, py)
    local best, bestSc, scanned = nil, 1e18, 0
    local ok = ensureSyl()
    for off = 0, 8 do
        for _, b in ipairs({ c - off, c + off }) do
            if b >= 0 and b < #heads then
                local t = segText("@K" .. bk .. "#" .. b)
                if t then
                    for e in t:gmatch("[^\1]+") do
                        local eq = e:find("=", 1, true)
                        if eq then
                            local kk = e:sub(1, eq - 1)
                            if math.abs(#kk - #py) <= maxd then
                                local d = typoCost(kk, py, maxd)
                                if d <= maxd then
                                    local ns = 0
                                    if ok then local cu = cutSyl(kk); if cu then ns = #cu end end
                                    local sc = d * 1000 - ((HIFREQ[kk]) and 100000 or 0) - ns * 10 - #kk * 0.01
                                    if sc < bestSc then
                                        bestSc = sc; best = { v = e:sub(eq + 1), k = kk }
                                    end
                                end
                            end
                            scanned = scanned + 1
                        end
                    end
                end
            end
        end
        if scanned > 60000 then break end
    end
    if best then return best.v, best.k end
    return nil
end

-- 分层降级查询：精确 → 模糊音 → 音节纠错 → 整串编辑距离
local TYPOCACHE = setmetatable({}, { __mode = "k" })
local function smartQuery(py)
    if not py or py == "" then return nil, nil end
    local ck = TYPOCACHE[py]
    if ck ~= nil then return ck[1], ck[2] end
    local v, fixed = queryExact(py), nil
    if not v and propNum("enableFuzzy", 1) == 1 then
        for _, fv in ipairs(fuzzyVariants(py)) do
            v = queryExact(fv)
            if v then fixed = fv; break end
        end
    end
    local typo = propNum("enableTypo", 1)
    if not v and typo >= 1 then
        v, fixed = seqFix(py, 32)
        local v2, f2 = bucketNearest(py, 4)
        if not v2 and typo >= 2 then v2, f2 = bucketNearest(py, 6) end
        if v2 then
            if (not v) or (HIFREQ[f2] and not HIFREQ[fixed or ""]) then v, fixed = v2, f2 end
        end
    end
    TYPOCACHE[py] = { v, fixed }
    return v, fixed
end

-- 按音节逐段查（整句兜底：woxihuan → 我 喜 欢）
local function perSylQuery(py, n)
    if not ensureSyl() then return nil end
    local cuts = cutSyl(py)
    if not cuts then return nil end
    local out = {}
    for _, sc in ipairs(cuts) do
        local v = smartQuery(sc)
        if not v then return nil end
        out[#out + 1] = split(v, ",")[1]
    end
    return table.concat(out)
end

--================ 类型识别 =================
-- 返回 token 列表：{ {kind=..., raw=..., out=...}, ... }
local function tokenize(s)
    local chars, cnt = splitUtf8(s or "")
    local i, tokens = 0, {}
    while i < cnt do
        local c = chars[i]
        local b = c:byte()
        if b >= 128 then
            tokens[#tokens + 1] = { kind = "cjk", raw = c }
            i = i + 1
        elseif (b >= 65 and b <= 90) or (b >= 97 and b <= 122) then
            local j = i
            while j < cnt do
                local bb = chars[j]:byte()
                if (bb >= 65 and bb <= 90) or (bb >= 97 and bb <= 122) then j = j + 1 else break end
            end
            tokens[#tokens + 1] = { kind = "word", raw = table.concat(chars, "", i, j - 1):lower() }
            i = j
        elseif b >= 48 and b <= 57 then
            local j = i
            while j < cnt do
                local bb = chars[j]:byte()
                if bb >= 48 and bb <= 57 then j = j + 1 else break end
            end
            tokens[#tokens + 1] = { kind = "num", raw = table.concat(chars, "", i, j - 1) }
            i = j
        else
            tokens[#tokens + 1] = { kind = "sym", raw = c }
            i = i + 1
        end
    end
    return tokens
end

-- 单个 word token 的判定：返回 out 文本 + 诊断标签
local function resolveWord(w, n, pick)
    if #w == 0 then return nil, "none" end
    if #w == 1 and propNum("keepSingle", 1) == 0 then return nil, "en" end
    -- ① 精确 / 模糊音：命中即拼音，无争议
    local v, fixed = queryExact(w), nil
    if not v and propNum("enableFuzzy", 1) == 1 then
        for _, fv in ipairs(fuzzyVariants(w)) do
            v = queryExact(fv)
            if v then fixed = fv; break end
        end
    end
    if v then
        local t = split(v, ",")
        if pick then
            local x = t[pick]
            if x then return x, (fixed and ("py+fix:" .. fixed) or "py") end
        end
        return takeN(v, n), (fixed and ("py+fuzzy:" .. fixed) or "py")
    end
    local cuts = (ensureSyl() and cutSyl(w)) or nil
    -- ② 能切成 >=2 个合法音节：一定是拼音（英文几乎不可能）
    if cuts and #cuts >= 2 then
        local r = perSylQuery(w, n)
        if r then
            if pick then return split(r, ",")[1], "py+syl" end
            return r, "py+syl"
        end
    end
    -- ③ 英文保护：带拼音不可能有的辅音连缀（hello 的 ll）
    if looksEnglish(w) then return nil, "en" end
    -- ④ 短串且切不出音节：容错太容易误判，判英文
    if #w <= 3 and not cuts then return nil, "en" end
    -- ⑤ 26 键容错：音节级纠错 → 整串编辑距离
    local typo = propNum("enableTypo", 1)
    if typo >= 1 then
        v, fixed = seqFix(w, 32)
        local v2, f2 = bucketNearest(w, 4)
        if not v2 and typo >= 2 then v2, f2 = bucketNearest(w, 6) end
        if v2 then
            if (not v) or (HIFREQ[f2] and not HIFREQ[fixed or ""]) then v, fixed = v2, f2 end
        end
    end
    if v then
        local t = split(v, ",")
        if pick then
            local x = t[pick]
            if x then return x, ("py+typo:" .. tostring(fixed)) end
        end
        return takeN(v, n), ("py+typo:" .. tostring(fixed))
    end
    return nil, "en"
end

-- token 序列后处理：word 后紧跟单个数字 1-9 → 当作候选序号消费掉
local function mergePick(tokens)
    local out, i = {}, 1
    while i <= #tokens do
        local t = tokens[i]
        local nx = tokens[i + 1]
        if t.kind == "word" and nx and nx.kind == "num"
           and #nx.raw == 1 and nx.raw >= "1" and nx.raw <= "9" then
            t.pick = tonumber(nx.raw)
            out[#out + 1] = t
            i = i + 2
        else
            out[#out + 1] = t
            i = i + 1
        end
    end
    return out
end

--================ 开放函数：Smart / Correct / Type =================
function Script:Smart(input, n)
    n = tonumber(n) or 1
    if n < 1 then n = 1 end
    local s = tostring(input or "")
    if s == "" then return "" end
    local tk = mergePick(tokenize(s))
    local buf = {}
    for _, t in ipairs(tk) do
        if t.kind ~= "word" then
            buf[#buf + 1] = t.raw
        else
            local out = resolveWord(t.raw, n, t.pick)
            buf[#buf + 1] = out or t.raw
        end
    end
    return table.concat(buf)
end

function Script:Correct(pinyin)
    local py = tostring(pinyin or ""):lower():gsub("[^a-z]", "")
    if py == "" then return "" end
    if queryExact(py) then return py .. "  (无需纠正)" end
    local v, fixed = smartQuery(py)
    if v and fixed then
        return py .. " -> " .. fixed .. "  =>  " .. takeN(v, propNum("maxResult", 20))
    end
    return py .. "  (无法纠正)"
end

function Script:Type(input)
    local s = tostring(input or "")
    if s == "" then return "" end
    local tk = mergePick(tokenize(s))
    local buf = {}
    for _, t in ipairs(tk) do
        if t.kind ~= "word" then
            buf[#buf + 1] = t.kind .. "(" .. t.raw .. ")"
        else
            local out, tag = resolveWord(t.raw, 3, t.pick)
            buf[#buf + 1] = t.raw .. "=" .. tag
            if out then buf[#buf] = buf[#buf] .. ":" .. out end
        end
    end
    return table.concat(buf, " | ")
end


function Script:OnDestroy()
    SELFREF = nil
    IDS = {}
    SEGCACHE = {}
    ROWSCACHE = {}
end

return Script
