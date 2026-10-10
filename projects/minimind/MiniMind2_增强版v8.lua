--====================================================================
-- 迷你世界 MiniMind2-Small 生成式对话引擎（Lua 5.1 组件脚本）
--
--   模型：MiniMind2-Small 26M（dim=512 / 8 层 / 8 头 / 2 个 KV 头 GQA）
--   权重：MiniMind2-PyTorch 的 pretrain_512.pth，int8 逐行 absmax 量化
--   分词：MiniMind2 BPE（vocab 6400 / merges 6141，与权重严格配套）
--   加速：① 精确缓存命中（零耗时）② KV cache 跨轮复用
--   依赖：bit 模块（一定存在）、os.timeMs
--
--   ⚠ 重要更正（相对上一版的交接说明）：
--     1) 上一版烘焙进去的是 **MiniMind3 的分词表**（含 vision/audio/tts
--        特殊 token，merges 6108）。它与 MiniMind2 的 512 权重**不配套**——
--        id 3 起全部错位，实测任何中文输入都退化成乱码/空回复。
--        本版换成 gongjy/MiniMind2 的官方分词表（id 0/1/2 相同，其余全变）。
--     2) attention 的真实结构是 head_dim=64 / nKvHeads=2（不是 4）。
--        权重形状即证据：q_proj(512,512)=8x64、k_proj(128,512)=2x64。
--        引擎按二进制头里的 headDim/nKvHeads 自适应，无需改代码。
--     3) 上游 post-训练的 512 权重（full_sft/rlhf/grpo/reason）在公开仓库里
--        是坏的：与 pretrain 的相对 L2 距离完全相同（1.1214），
--        实测 loss 16+（随机基线 8.76）、输出为「是是是是」这类退化串。
--        因此本脚本配的是**唯一可用**的 pretrain_512.pth 权重。
--        它没有对话微调，靠 prompt 里的 one-shot/few-shot 示例引导格式。
--
--   权重导出（本仓库工具）：
--     python export_tables.py --pth weights/pretrain_512.pth --out out_pretrain512
--     python verify_tables.py out_pretrain512 pretrain_512
--   产出 66 个二维表 CSV，按 二维表ID列表.txt 顺序导入，ID 填进属性 tableIds。
--   每表 1000 行 × 500 字符（≤500KB，满足 2000 行 / 512KB 上限）。
--
--   性能（实测口径，纯 Lua 无 BLAS）：0.37–0.45 秒/token 是硬上限，
--   8 token 回复约 3–4 秒。务必走 Chat（缓存）+ WarmCache 预热高频问句。
--====================================================================

local Script = {}

--====================================================================
-- ImageCodec · 纯 Lua 5.1 图片解码核心
--   1) base64 解码
--   2) inflate（deflate 解压）—— PNG 的 IDAT 需要
--   3) PNG 解码（颜色类型 0/2/3/4/6，位深 8/16，含 Adam7 之外的所有非隔行情形）
--   4) JPEG 解码（baseline SOF0，灰度 / YCbCr 3 分量，采样 4:4:4 / 4:2:2 / 4:2:0）
-- 不依赖任何 C 库；bit 模块存在时自动加速，不存在时走纯算术实现。
--====================================================================
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

local DLENS_ORDER = { 17,18,19,1,9,8,10,7,11,6,12,5,13,4,14,3,15,2,16,1 }

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

local TOK_PACKED = "GhRPYqfa:JFX=WMrUKb8C-3$[)9\\>13/KH]gtS.V=G^m//1%T71*[Td,#E\"S\"]k_8;fV62jE\\`9I_TO,q#Wjfq/1BI]bUnP?h`p#cW:921H/IFV/?pEqB\"h)cT_7(rm.o:]3$+c:I[SKgYqmVT(bIP7VQ$*MuBdVj'N+\"$@ar2[IDech[$E>08H`ah[\"]fHo8PX^)\"F(h?\\%S\\&*'<h[86H^E%bNr,2:Apq?1+_XE7uKteZ-n*p@18)`4]mI6\\9:AA`%KCHSDDYV-=8)a@(#N:Hs^$pLG45i]gKCE=Ej7\"GTU[[=5PONe6h[=oPrdOVIiT'FVOG9UY$LNq/jj4=iOG?WKj3S240F1)aL7a/T<+-K\\@3r\"0-XeTS)ZD;c4T'L\"J&CVUR&u.s7[S%IfiFJWLY3rsG/A&6B\"MK[(M<PQFqA8@@<N>sa'j-(AuB'\\(1o5:lo`KuL=rU]]*Pad0Y7[ulS,pWZeI1G$hqCApRd0:cbo]7_u2e.p\\uYss5S(u:W!&p%JP>amXGu>s&ll3kMcDIK_p6:mf-:ss4?6/hh:lV)t*`3\\Gu<^r]c)5rtt2(;n2kRiVpTFqu7T&s'*#5n)=7qK_tcemf-@uIi@aIL&:O^^Cflm_u3WGh[]CEE5*(SVr<(`h!]sorG_d!g`M4H_f1)>mZ59a8[ptopLiIa7CYPmpFjG_X)NP#mOuKV<OfdRpG_(12Vd2Dq(KV_ZS;DAb^UMms\"M[s;4.CD0`NM/r_LH00>dWg@K+Tir1Ac?^BjF\\)<UrKbl;gQs-k_B[pf:)_Yi;Hq0r\\Artsnu.Eqg5R/`L,s0#l1hno<+L\\^rUoD]]js!u<cLAA/0?Ouaf0]*<1XYAWBo1>><K_[IKGJee]bkK$QH'f\\,q-fX4L&#_UT7m#SR%K*.M_I@+o9Wnb.a0Q_r%cL\"_YcI=Do2E1bjWCb^Be1o(;BQ+HstA$FCbDC6Tte3/<lR)LMbT?VX7YD#jKF]c$gE-A^>nA_cK%(lp%U+B\\NmK@qI#N`dU(O6=pJ'%-[a6C4Did3qc@eOH2`^j%n]hSeh$l<IDt)I^9<*'oK9p@ip24chfQ>#;\"VZQ9o2U@ZPQEAac\"qm#TlqJE>/$6<]*V+(YglIm(%i\\*)Se90UVi-ao@'3,b:0o^K'Xm.T&>s''Ycm14BX8f#Ek)11oLdk4uPUfD*u^!B'na,f'9(H1faQh]0\\r7;8,aBh(!j%BmP\\$'V]n>O%;I[dOLPj+_t6B7s]ft-6-ILps<dr's>/f+'k^H0>?I)pH8)qVsuXG)u6`-.gkfi$jED)J3aeRaUCZd!uW7:*;8]\\h_7%W,4O&cRq(Hu$4\"[t[nbpsaJ8k>-G5N,;e-h87V\"H)>brWf_5.?(!Dga0mk7NS))\\DVEL*5CF=Yr@I$+m:mGEEe2KD(!Q1bp&S;L'KuB5X\"`\\jhJq4g3hKk/GKc@\\S*V!Hs'4J0&+QP2rY5qA;qmOY%=e6fO0]X[e^3LIg90)_A<l#ihNj)-cZ>kjSRV>cn5R>i_;3.loD)Va%$`F0Na?IPlgp>gG*O_6'tUcSZklmPBchh-fj\\MT9Ql]fZcnM)\\C+VF1NiCI]o_\"E[uI\"fV>GN4FZWrR)4(&>\\@kZgSFUh=3a(Cp@GuXHm<R9*W\"/?c35gm7`Og)u0CX76+an/;KsTJdn3^FTX#mu3NGZZRIf1mX\\\\r.UoKta`LsIjc),Bk5?2Ju_pPuB*rR=NRrL@$'D):$;C\"K_O+8SFIqHPLT!8FZZ]gp(8nj1@a<Td08`_j.]@GcLMD)%5`O163b6[Z[&Gp2Nfr![MVb&ak*GMf\"df$\"5fWJ?O=_9Y9bJ*kubjRp2?mt'T>n^t-7KB$A^1pTX8[<_IZKC!oCg\\a18gU>o?*\\t'R:OaG6<_1JijIbEBO't:mDn7Csod7?N3_uS(?dXY&YXNnupBi6`KN5Yo@p]+>Hn90^OkD/[Rrs+F*Ct7'])R5OH?a-c86AkuYARs%7&t\"q`;]%l<X>R5PBY^ZkeM+jTA[OVa+Rg0CT\"#9j#!PPS(`/3mF9e7RkK$_4Y-Z[`t-&X11'o5'P8Upgm;\"\\8Nb^U^n&F@g0((on@s4.?[j5'<Ul*sL5bn-8)-q4eIT8QnPe:agQ_E!a3BX'*I%Ct*\\OpM&e:Y,W5@+*7uTOh2];'rG0tcu(flq-(JeUc$:\\E4`\\6e&p#>,*Spm.5eo!GW-%:?a:;N#>,p0L-Ge*Y'PG*71*!]\\J*9liN:%0kIUD[k\"'\"cfi@RD-CpW`U-psJk>]:uqU(#O8n^:99(936)(@7IJ&04[XUBKYo\"S(K`B*q6%=UGAFUFo/XK95A[&'u=ol0]%!E$[J(rl^?3cm*ITA';f@FarJ0)Sn\"atA`3Yr>,,rMiA[NJ#8j<X:AlVhM`i&mRX%$NPc9@Gp/>&j-[I2IK\\Nl3(;/<BDU;%lB%\\1`K*o@%6Xb]o[0$C>:te&c1V02e004Ui9t3?UI2)BePnrkW4b*;fe(K.<$c4R)lYi995C[67Ad\"%^R$[+=:Pk(cQ.7gc3P^AM]R1AS)19Ong)W6CO6f+\"i(l!.:2L<`2M(DN`Xh+C:O+),=q0C2c&om>9^+Unkh@G$fa?b`p;7hfi6dV0*K@p>`A;f@$`OXTQ$1+4[a=kebDpGnrCH>E^5MZXMa&nfBDrN:21PHCI0<@7aBURjd@pMcY8HhU&=bmhjoO3j07Z9Y5CJa@aH#1gr;6sb4kAa8j0<9<gH!R%O$[K=ScpItNXRQ-Q<h.^n%44[R.,Aj$3IB;/6hg1(:Eg)?2>HqOfA<\"*pq*V%j%m5\\$D>\\k6dWFY6m<94e[9NU9i?EF,EsQO2TfH-$VK=.)(Q>=pE/+Z(ks$SdtD[%#ejA[mRp)]>`1*.m2jo]JV@.0/J@[\"Lk,`S[3\"1CI'0T2XKfkIUV+E\\\\%aU_LXGD)ipr\";qAk$<H6Et);dFrjh,<\\'6Dq(')(OZf+@\\G&]-p`OhLmW!QU7`g/,4uF1+GCDTcMJ7`A;\\.+U'J-LE(M[q#bRp=R5W*<j1aZjViFGU(FInO^uekI)*mrmEBbck^`J@Kns/Kf?BoO(G!sE79]3gZC!Y12J$q.Ll\"s@kJ.\"lir\\kXuI1,T=iKKN<<So\"CWoXm]AD2V;>ZW43Il$\">de7IgkLA0YFu.1h!k\"`fG\"MbC7F#\"a;(...j7?S\"1]>)iP=@+QSfa]#2c3F;P57J[/5l+',n*F9eDHnE-q7]i./\\E\"R\"k5Y\\:uj1_o\")[gGIMNKQkH%$.Jg@Y9PaAW5!k#1$saRD?&bbPntB5n6pRf]20lr#iEG_=K:I@<N0Va!H-nX78<(OW[6Y4Sa554/V%F^S>WQj@W9ct8fUg<CMDgF!O%#ePZUDF/RG/VO\\E\"O$Lq1cHB9!Ch/CoPQbC'h]'RFUNs#6TahA^Wq@`k:*h.$9J5@q93aQRbdIl:'Y!@JW%(3F@AJHcS[H^qq<W6.5QVfrA?^ae=If7l'O7(_E-@*RV,2rO6su:87T$>b`eLe/+9kFN.nar6csQBO?^`(Dqf,/TRMQm*mZj+[g&1hkMC*t1/``R,9`T#(ec@eW/?nba1AoDA,6om;gYU,^rCd?T>4jcS.Rqr#QM3Nqh:6Mg]%r$3<E*il6`;e7Z)\"D`HR`t(@3gj^oATYR\\/p\"m)5BlnDJ'\\64jeLL_>q6,jS7<@m&8e`f+\\pGs?_<rms%\\miafS(9<UB[j33]]to+e@)DiY,>&+qECUnHR(;Xs<>tETUk:OY.Qap?pmZIBj>57V9A'I1G'EZG[\\F!X2KPq^[]\\Z7D1_e7\\]-L\\c+u7dE/f).PlC<Qp's2ua0^GNCt3@R^iKn'I<^(@q^FiOpqU1gOor_KYUoRA]9\"W1Ud!Cg\\G[fsa*^F7)1<H2M4]eBGYaX4KeGH!^4rQrG(%h+IGH^!cZY[6R>[N)(b4X[o\\@SVaC:7Q-1,G#p,t_3(kb1/X]WT0KrIB5pWE&A]5isRY)?SaQ`riR?SqX,Z^4p]9'`Pak[MO_AeUKLScf'5?>#VE9_$([X;-cqF$7hQp)GfqcjnkuA7-uo`LY\\nNrG%Kl>\\5W882'mB>Fi.;Ug#&5Fn./K(1'f;1&L&=Z^@'$ikNo#)Hf7]TDchd@M'[Y8Ca+dKE_>:\"(iI)Ri$ke1&=Y)UWs([)M5@#E,:l91LmL(1QeP9aJu4Geeeo8=pC^F=3%\"C_(h-0XSkPShtf`es[BRN8Z*\\Q(hoB*R6^`a;RFEL5ICVb]fGMbG2oJn-WJN>.r?-L3jc(n72gB0BdH7qshqM9'/+T.p]=dh!?Vg-C#r=T#Pn(+<-YLrdjkSjP]Wrc-<s:(9sbWs*uJC=Lr:).g6T-'pr69=o\"g+L'13,kGJ_EFOFP3G`gE4O6AGq+7Q+_:CT[h-lEN;\"#BS)@F&W,k7c]q*$+gH),lP7Kh4gu3lQ^Dm]7j]\\WYu4:__4HT+=ud%;9cgg=`oNStU1mp$=C&X01g%g<+*JZltC>m5WGcjK+tX5dR>P#o@gbX!XLKKBtRnV62>:T3h7G=>WJ7kOc1>j4d:Q&=1=V[7'71,h]EjGjHTSmqGWS#$Jul,>L#ELM_#oAfGo1lq7Xs,.&=EI_WbB$3RVFoahs;V9h3^ENQf7ca4.+8\\19&4+4Kl4oaV`$OMiVi%$hX.pBEYC_ZFsHDF@8gj,K\"k)RiMP2mLeUE,\"Np-\\!!o!72-C,VbagF/S2RTML?H)h94Y(\\IZ0(0.??7aTld^KT-&ranTA_Bk4b$9]3Jq\"0\\Ba^#5,<efG\"q5$6`lNN+=97TNL$d(-&SBWeHVTh<*nlA0Q80)i=Q-UH$#NbJH51H=hX(E`(@=p,Pq.@H:baN\"OB913Y[,J[i:0u1#e$;4P<\"fmnWL'8M+f3s;0H]/OGZ?V's3rWB.%1-FQc:\"^DHsrV$@IDo=:^p:N4Boq^h$MP:gS>'YuK_YS5)3lpf>,:aW8*1)i<WmEj>P)6EW$%5Y\\s?\"_-PYOGoFBs35TR6@cU?4M\\.#<;gTft+l(4oC^X,nWqZ2\\naRb)VQ2B!t$^SYjUPm2<C&\\)dAYlWkpESgqTSZ?Lo&_^etQJE4akrq&/:5C\\JH48'N<YEe3K5d-Tjq+fDcD0&#=,&WWYE$*8LR__*e&f+Qkj!%nP--l[RP(8*n3]sb*o(E(N/Y!'k2_JP1>IaC8Xna*7(VQZIkVJ79CRjXP]gO]\\KEi@rZN6d7lU\"AXk$)`ja5!tL*=/'a't@BXGNr<N47(,[\\8.)u^0c/#<^R61oHFc#:U?o+k5kPQ#bBr[H-I1H=3*ro*RAM:]PN>h)gRqo'[,e%Q4*P?;&M>!iRq?A.,e\"ZD'-fW)1HGZLBWaUAltl556)<f8@QgM)&LLG&=6TBOtIti_I$A8+m_m4b6^/E\\%Dup,an-^#Rt?P0'DD?C,5(s'Jc+o3<nW>3dulfSu%L[brnp,!*4K\"?>r>.Io#O%&KcEYBAS-\\0PiqHf6,;i^Rd/^@eci\\\"p$hY*%T7)E85Fl8di=)-A.jH7ta\"Q=8qDIL:b]d\"Xd!3(Y3FXT8a\"3bI_^anXbMrkgbcoSU_+(OW>cb[!!J,F;Z<M>Ip$f8`n!l00X0W^fOn@d_C?!9YCbJO]5nt7ms.^5IE0!H<Ot4mcI]%?m\"I@g]Tg$j`q8c2jb5qNE`cg>h2)nV1N,7T\"^\"!%iM5G,%5k6.Jf!WN?dljC:_F[Pt-Y%r/`nQA%+u%DBIX5KtNK+$pGS4h%'%_<?OU2Kn]cWjZ6\\^^#IeP=@[PCQfNp)BUR*<BM(@dY=sa:&o&7p8eq&Q'OtRc$W)7\\pPcKqV!.GY(?Z7QPr!u`Ed4X[1/Eg1Su\".mB;Q\\pUN@b#Eo=nH#:!(b,IWA%)t8U_P/le@MfNu#>E!l0],<eS#s#ZfXIIn2,M[H[X2&+=&>GL4<j]2+=[jr65[I6kR<\\p.AP*lQ,Bt^_D_\\GMbMQ6/EhbF07iQ1Y<>D6$-/O<TEIQM^p(?,a^pgf:d/$2cs4Yphgg](d!YCs)AnFGJ`Q[o,rU\\:k7:H(-=YP+eh2Qsj:<j?l8X7#<-aYD?a;]AV.p=9g/&HG=XQp-cnaX&CXN6AnbGf;ddNp4(AX:_cNG3m&PZqYL13_^V]$-TSRcHhbqZa85MhLF\"jb(VGJ4Lq;W!3*2hK8HX!?4eiT:jb$1J\\,q[::iTTm!kDN,H1k.YeMrQ[)4oP7IP=G5<?2GMjSq!VtHk-2_5%Zn5O?7?i$d;aN;V.W,MR\\`:6Iq;D3=D'EV[rRMp1#b(#1TNH!-[fjQ_Mb*%(_+8P'7<iZK\"1%PN0ju>L4b*;;00ss$(0;QNZ$j]Tkg6?P3Ym>s3]pK'@ia,5s0Lan$V1*`WIe'!RD?\\2WAJV]I[QkjEjgif^%-bUK;_uY<^T!7*t/u\"+^CKm+rCOp48@oD/P8,K.[9,TVa(,/Y.,,C3NE&e'0ZdA1<'hg+9kP^BW28C718.u_d5k'kd8[[mL42\\:[IMP=pST7EWtmqbr;*WDe\\GdU/!Q(,9it+eD6XDF(t!622eHr\\SV-\\<bT00CmdM9<%4$d&#fnokHMl<VS1fmbq2=epBa%hBE^'g)(_qe9f%))+f*9\\Q@Z-3A7P)\"nf_\\Vj]^KQU,(fK1`-<1@M!h>4#!8u;J\"Apk``4.9WWsBC,97(Ft]'i#1P@N9+;/c406591ZCbWK<#9jk1tU?<.0&&i&_;DPrdXn(;2G>mUu4p(A/!A#*,_qr$AJedb&Dhnr7ae<ViiUal,!J\"l$?s?Ablk(Ddk(72rGk:c8/m,ilE],Bu'Y%j=h;YK+dN\\t\\S(oL-S;aU=Df.VG1=>utHq1Tpe'8fVp:9\"*f>Bjkq51WHMKfX&=HE#2`jp[$[Urr@Pr/tn$MVS*_D`iP;t\"aMUg]$9DCc4k6Sd^62%dW!,p&0$4%0E+_a;T1`<5fPR\"#=qoq,CO0\\]h4MV`]#GLGsrN3RaQ2`4&hoas-Imadu(TL;OPE>=fR!O?_8q\"9.Ib(V;`G11\"dZE@&<);8[BUM`6%\"k#YhCY6BqYDZ&XKi[B1F3CkNUFLrYJ/)>AE9AkFcS6XnuS\"+gD((l-f%QLsDd0?#\\q\"kF5^O9JAe-kVRoYYA*I11)$?T?tUU&]$[I;]jHkMhb:@\")cpkG.CrgoYff'B[a<%OQ@6tBtL=eWn3_gh4c^ofnt\\\\6kF?:eYFXB&b9To^8kBpW$BI/Xd-=-jkEn4RbD2Anm&7UM_#l:#(`FZ#/FGHZF,4$AWZ[Y_=HHZI,Kk>'*$BDMOq$Ks#K]_*=>G??<!i1<#>_g6uL[dk15E/gS%^ncb]Z5*[Z!n:^+C<Nt=A?\\MKZ?d%(GZhj\";To\\-dH:%H)k_d?jFhX9Y>p1mK&p;>1OVlI\\XYCt-]9UdU\\'Kh3[agCl0I_/4=]t>.Q<BHKWZg%]TR(]%:gh,C_M'CgC.umDpo#Yb3=XjV:Yoe4gGoqh%-*Jp]0r&EA=]!hAZaP*23ZK8SrpH%Q><L+V0eBGk@SF]1-m0(7.kWu)Uu!U[9Y\";*W&t*%.LPdF=4)Z\"@OiGSGoE!2Ae$0M/O=s&\"M99-h25<;qrS02+<E4s?^G\\YV$\\/(fGi`S&<r\"[*EM2?!:u\"&s\"ntL\\e=CtF#KELclgO,bbka#=dsEBT.L4Tr5#lbH?qE6`gI[8b,XEo.uQfRnmQ&F)(T<Cpff])XU*rUh+P_q6P:=6N,PV8TKM*FNcM$B]gFUWTSajH#P6*^^\".n;%:FNs(U/U1iRr*:SS73^\"t;9_<P@f=K1a<YA,uj9FiJ^]Mioq]^RY!4_,\"NS:'C_-:;#;dm0@$(%Ka;.P5#u)5fZ81B`>gk2:K8(KI9/*.YYq!*E6@%Ed0EXXU/loiQeka).eJ.b$;42Tkr55nieBbU]EHGKccpK0+l0c6A3E36)NhDHp-9#5,0\\L$P:H9hKW(Nc;fZ]Z1oZj9BE#D_?F__-d3^K2/jB9X:l0dL-7s])r`P*B]KmgD77NrRs0f)><Sh/LtGmidlO=caMD]+anJU\\;hCR$=?^tBTUW8.:SqSoVK7q+9XY/[5j=HMQbFq]CUQ>;<[c2fFZLBlgB[r*dFb!fgOb7?3/0mrB.QjkCZh/#lL1.+k_[*pn6Q8D?%#[DM3a[t\"%H#nF>qM.n;<-@D@>uiGqj>Z?AiqEm1qea;9r9%$[>p$/#\"'-q7t*%Slm;\"dE;fHofS`ZW]W_I1`e4O+bHKU-_.Pr?-.2uM66.7G=Ps\"OTZ9`/Qo_pQ0]lo8t-&(ke-K&:]mRlSV6XW6L`65^cW#VceI^\"OYoSo>&r?i4\"f)>CV?g<=+ok\\nT(pk#\\jdqKqGtE+9F1u^Y`R!jKkP!oOPlbQ7D_nE+30r+:BJu5;p36Ko\"p)]g_PD+M6:3YP!0\"\\BmX<&4)DI4n5$,fuEsShpfp'j/\\1#CUR]k8d>lg.hVtbojdA*-[Xb\"EX+*H<8d\"O12J;&i<oP3;.+'s'fgE^JnH;603#\\lb.?OhU)CU^b`leo@U=!9S47%t/LK*K(SB5XE6B)KjRhLJVR%d6$]B1mGEj^fCpBK?cN&VOUTM3PG84*rc\\mWV8(TO/0qQ?tA@cEPggiNbG!hee24]RQ%n,61jRjtYDFb^#N-;\\THcN_(KibOpZc+nY5Pr=&e9JgNFoci;UI(r9.(g*,GP%8>Z`m)cB.X%A7ud^sZ=^jmD;bq%,p(rrR(I=*CnJ?8:u;*]bXG<%7jsa\\Qpf755m?8Q=M4#,nHsYI/1sF#7hUS)ZiH0*4p)CL_>\",-pjhYSi_kbeM:u_mkM6!M@s\"gO';4:6F<Z;W'VoWN.n&Yj2X^[h[`i[6@i@PtW^aB.Z2=lMRYaG*K\\%Dn^!AG^K<*(1,r[>d4QgTPlRc0Ba5u3dAYKRt.QC.&MSUO?1dEr\"g-\\\"2I<JPE6A.!A*`/iM`RmcmDNO#n>%)Z*U*/^Iak0@ak@kP=;V*k!M-gV-UnW>06\\8KWBBY\"d<J]ppLoaCV!U1DQK,<;I<fCi6V]o*Oo-1R-UiJQkAET=?3aboSRf3.T&b5[5,N@RBF`?>NI_$Bn\\S2m9o(C'MRf?s^j-JAUb\"G\"O(ZMZ9L=_&E0)2tZLc]uD-K/U;6J9eU2>6>!r)[<3ko\\ATMaX\\=%U<5GNj!j;Qj*p%ZXZ3h:.\\uh0Qo@eo4)GoNYa1g/5)c7mSmVuZ'h(]HGAh@<&H1K%3Y<lKsdXc7@pO@H\"3u-S_=e9TA([WV0lNWlCKcmeROa&Dj7.T(dD;Vbj5TOSUk:e\\KK\"kG\\\"NggH8KO2R-PtLi+F06YW6VTInQ.,\"IPOI=7(/GniD?@VX2OS_keXA'MK\\aoD%XSod:7dpu\"o%\\<)bL.i/uNZTb#fi8ON!Le7$0T;e\\?-jb?[[BLW;/u)U?I^;]V_DO))?]d[Ho9e/^^/XmjXa/>5LJOTa#7lu$.?r`$#ab_\"SUS..n-4m9)]STGi&W8.\\\\auSo42QHn(S@G9eSf=/r,Le7H<[JkK^Fs,.Ns-C14*$[lbCFCih[NA<E]#S/N=PlKd!he*kB.NI660O^fL'<\"Io'2DEnj/p9*0j5eVNV/Qm&0g1=bJZ\\-Ve+mkg0t70kh?S;j]*nQY3eZ!g<=+s3*l(I`!TD02F)t-J/Sf2(QhJ\"5bk?c9=CI=X+hDsdZlpq\"238]\\rSY(p`7PXn`C<Q[b)9@bFgmQiC,C^[gL[S=]$%PE6r<1\\O=$/'&\"4nOG/!@Jl2tQmB(4MZ\\@D(g1fcpr>CoJ[PE7AQ.<`<Q9h?6\\%TAq5m3b8M!:mtn45[2hfalPc$QNWW!<'QARJ0cj2GsiH7oAo1=\\\"li'$pu7@/^^h01Qn)hib=@t>]M0IFWf;O5@'KO'6t./3I7cFrlRhof2K9>8\"eLK'lF3q7VICGJN=&7#0p1.Q\"DK!ES\\7T=dhMqtXdNj/ki'on*Xgt[6@j<7=s;FW&Fs3U>FVjF`RaP)rfNW:U#b(BAWgIG^N/69!eVQMP\\;jhdk@2taq.!VTq@PZFQ!q9'pdLI7AdLPcd7[f.M0m`\\pl`=q.Zg(.Go)a9k?0<P[&0fhaes6LMQKq&/0&dVL<C'ZgVjb90_ETV(qEu^P'1fHDD\"k4%B9VPepi\\&*39oQ9'OSSsKdt_P.G3MQBFqh0%EOHPO$9/_Zl4KVlA/^.VOo:ZHA/:5gWO-5nJ68_plO`PgWb,j&ZOF'279(H;SX.h<H=?YrgKtsW5a5`RbAA^Qs&/o4#(C+EHW66QQ.;S[0$mQVC>4T<G%qR:`JmM!$RZGW&]`!P9qb$`Kt[OStV'l#>>sr%*&s\"54Y\"uqQs8Y9RNB:mX8!SVDF0-Kd?8Y1R^eIr$@TDj_QGIJXpXo.3pYgn4%b?b\"_Us/q+EV$PrXG*TBh=ntWO%ko;9*_UMNC4f:DOZ&!t,f:Ha#lhoV+.-@<a#Dp.[SUMdFHFjV\\oe#^cU$C)X4kn\"sf4h-\\dSfG!*]1=u:6`?%OI<:\\C7)E]'PQs%Po`]UZ)chF+uOT0\"G&3M8eIgtoZUG:T(i',`R'Y_)aioiX(o;S&./MH=Kp:0>MQ+CnIH+:q)pB&]2ci;bgk4\"MNTZH]OV_a'@D@L@CcOL`ko0Npe1&`(XMF=KnO#\\@b]StecYhHoq)WbYZE1R%!;u\"KX?n.,[Lr:nIZ@gddk[]>m$SMq,]&ELj?Wr4(Gun^/D>4_]nE):Ph3Ji+d8*.aOCF3(!-qO\"A&:CnlRfatfVB&Q*#hj:99`V:.DAak_Hg9X:KcciTme20%-ah-<)(98hkQ.8^.6:#e)m::<5=6\\q%IiTR>7#%:C!=:(#^a*?JE);%)*e(r;&]PY(b?3G#0YWSTO`RmjpCjOPL73<7[m]i-/^nV7C4#ZdfOtF9E2%^dWNnYjfcZs:oSA!+)q_XEOdX%6@eu7Q0eb#bg,u!c\\`:[R#3H58.K&2sUSl<GI%\"i13YsE`mTg:Ii/6^G/W3!h6duFRp'<U&j4`*+O^tZCGj'RceYRs!%[[8N_oEiXpq\"V,.`GLo&Tbt*<qQ?%e+0+Yg<$D2=KA(Cb/D,MQ[u`2piJJ,=\\)r)6BUk3s?\"eq\"S_m^R'Qke-k#gBODNA%F<Ko6Hb2+C\"<Tg_R$sd\"=Q1t5P&]D@k:U=CB^R0q,>&XhuAmPcY*i?Nbk:6G#Ja(rtG2\"Ln:Ei=N]/Y(fZ<f3Q.$_L8[N=VnNKe2oj,n?pEg;tH!),`0S5gB-2e]A!25\"ef4\"hiO,l6a1*CfDHCBC=@D%^&>d%2b(6\\=:a1AWIRDibN7QgZN1?Xq;)kC?o;W_*h)rNE0#`(jPo[FBG]';sUkb42\\.]J'1.]_P9I77M9f>RaH+Zu*d4D,=Se`p5AGY#Van/H1tY=f,&1T*[k81OJ*^M3j8JS!ko\\DA^0)@%?;I+a0o,5nmqZ0kl*4qUOX1;RaF='c.'nGlV+$qP;d812!-&Y*EVhSDMW4A-3#C>Md1oV99_sok8KAHJm,/`Oo'1j-HJPr+T2T!aUr8rc'5WA`8B0eD\"<n\\#ZTb4\"=^>=\\jG*/X\"#9+F*?#Z6b/]$:r.AJud0e.a9$P)liRR,tIa;Ud243RpauC=C+C)n]]IE,q(o'o(MraN!>#ad%#$/LTL:'SX(F\\QI,b.H:C&M1[eH=rXIF.K\\,Rr\\;_=hs&<*Zid7,t?3H]b@Hgo)(5(P8WRJe;OXm/m,Dib>o%qckl?d0%D5W!LQe3]q>;Nik8\"P2`Lo9-T_damo4<]2jb>qn.>J?t#>O^ZI,ikVERi8q[3bh2/U(`*n=!(_>H'NI'8eSaPVkUJdhdOu\"6b:eMp6GK^f]?oc<1kAh8\"')n=S)jr*_!A`<k[g8$bbd>_#K\"hm*D-AB!M5)]F?c?3)eJ7le'#YI$#F\"k\\m]Ke0bXgJ0gA1K^ag:VPb2'h+!-r8kaDuSDq>saIA8.U>:Y2?n'!n(Z814<G8G+<tt#'EOgT+:^UjPEc)Bfg:1+-EXC\\/=6;n]SdTK/DrbuB(f%.%X@8fFgDLAMNZorL01q#4CF[GHg<XKg/:T\"LiFj\"J*@]J7[+1&[;:1)/Cms$GEH)6``U8r$b1p#Lf5=?W)uUAZ:Kt*kFutMrY9!=;ln*9,jSb.d`b;?*Ls+QF\"1rT4E!e3V_COW\\,dOIXG]kP-;2Gugc;q!hR_LAscqLcWH>2K/^l>A-1@F/&4.bt7p>dJMO4<_\"'\"S9BQD2'\"c3GOn+/='NAI<PcH&I@@rJfLb<D<XB?eqSE\\3UQL.%5\"!cNj8A/>Qb2%YL<?\\$o@^oI_eXXW=uK=\\?1IpS2aMC-79Id<U2C$:Ve.Z:@%_2e/$b'..WK86Kcr(@#6p7S-[#jA*)Ms!PEAjaMCsm=X$&C(N_Zo[-d:S,YP^S;L8nVr4AF_fjGSc+ncqY22j6$Bj/V&s8,RacIMlAts*kCt+nWZ!VgTE=G/20b]Od+2T'UTPkX!aBfGV#u?(&,j3F)NeMg&!ZP5[*:5u!2_?.dTP>?08oaY+C)BP*8tn3f$j_`4`'u-!0$6VRa*(E+lgsGhRmTB=>Cn(@X\\ok\"/`jDGK^bL$<XCnd-#[$\\80?mr(N$J>O-PTG@6aYO>G?;tOT^I'McVWV<7p<&+#bVf.M9i6pFcM\"?Ls]SWEJjR266*5*-i:Hq<1Ip,Tc8R5?#nUWTt-U)i6EKq,:+8OXjb\"jmjPbScPt;qFcbu3ec$dD].`?JD,8ZZpi=uNK43-=Q2X<1[Y\\U6qC=VImiq%F/Yk!l:9c4cK*^IBFc1tCT]n\\9h@Flpo=R48A#Jnb\"]fLXT&hpoEA)db<8qX.3J3$`q3b>eq,oTK)kUH0>)6Nbl_@!@_-Dtq=SD`9bnVmY!l:&EMdm.]7GAjXr4[J0\\Bf9o$Yr3YRTVc?\\s1Gg@?nF<Q$W`qbE*F^k(+jc=b1(!ItKQB<Xm?H_M?ahiT\\RG-O;(Jl(gG+SPX(BK/T(VV\"B^Se6c[=#!j=p'_hA6_J!Oe9tk*V/e)lC?J^kEcrL1/-Kq=@&lU;:*jC9&b3N8`JfVL`T<2m2[3tWG5#et$&a+0#Zi>rmgt21=7og<(aM-,7%i]o5>NBELj+3Kh.NmjA/`s`::(oo@R5Cgl,krIG2munm.9tkOaXF:f8,,FG\\eZr<uPt?Vj%h^.R[g?Go??c>GC?#NccuX,\\3RI*1GD7*VEFe:[gDkgb3mSf^EUh?F)P:,2taaI\\pV?%NKu>7q95hMbG-PJ\\R\"2mNtO6:1Zu6TNEqPc'lOb+XZjE[d4*%,$,/aE+LA#SM^Rm\\@!EoRHY0o\"\\BE=899H%69B=lW<43[7F7@E4D2#lN,#%t\\k['-=/4Z*`fSoc=C@*5JF!D#N,@N,).AgHNjKZj2QP-#%&1m\\1hPCkc^KkP6=\"WM?=IP>qB?[],,)m1*`knN-4@Y='8fT\\1!jU[#tV?mPBKCfL^Fq$/-#YL?RpL?gOPgXT@-gm0fA:%iQ<*,lZMa)9%B^A_RA2J'rNWb)_*/-ibCP;<#pN8f]j=Q@964:b#gA(,q+DYS7T&$7DP<UIHO1@ScJEs@UCX4/>Bc5Skhlg7T3aF_?0)J9'<HQ5Y^^K+8o($gsT'uGe^1;ETZ,o6:#WT$6Vo1N6pgoQ7&&$GbRq^U*D&6A@\\9R]7PnS6m@I*L\\*X'^!*ZB`)V7t]-0_)oc2gSZD3ptaHB\"C]_ROXk?i5Y:NB/4Dk%4%9i_l[&XQB*P#\\o*nBa4!\"C<C8;ihc#GAp)!k1n1n)P:!8ot2*+33EY')mj`(gTt;a._JD,iuQ<A/\"Y\\j!cQ#GgIe?/AZgkqP-cOeN2Sa;3Ff\\+'Z$Xt<C14p]`k&H8!ClQ]IpEM0FJDE\\?a$4;j8\\p8Ag*7e9Vt=]fs!e#,UMnS4`/B:#ou+@@0:X\"%bqc$hHlsn;dK\"8[.=+;Xu!mnG3<(c&0Z37^'jSf_\\0AXVV5/GRH4b>i+lRU-1[XE_CPs'NDrUH.68JH*i@DO4pk!kE3Fh%<3N/[-Z<;\\3q'FL:W\\13\\%g8QIa@Z<+*QqK1=]*;N)a3L<H(.[35W?`uR36<%[S]Jm00bB9,W;6o?OL&a\"]5!P$4DlsPLP.@;/#F%P//WE4a0=3J^>CCN;._0G]XM[=5S31\\ncn7VgP)D3An8h_ag]G043eQ&)(<]+^^<t^8Ai-2NciKA=9_a4KI?0TI#9[Orfh3aQXo2DldSo+@dm=pl>+a3>3qTI*MRNDVQ&s)OfW7\">Pg))7O,DX/#ECD_nkjaVJL>sahfl(K:$NrDFKh]I`QT9,;EB\"p0C@]/tHHK$reYn37g)3Q>r;%<SOg9n4h3%qA8W>I`+<-\">Y@^R6nG%B/W8)JL]CWWZ6f-2?HE&PY5+9%3N-CE4LnYURqlX6CCI`RI=XgX&D`riR*ZZB!(urFi6S=c0MlJpq7eK5eKeGW&Tht5L9=<'2G5)k[XD0ia-$I!t#q7\"'*qJg\"d2Z!m:[>0OprBCXneS_+[ZFD<ZUf/Q.p[rX`i\"6'O9MH)Jo6K4U_AV+5e].7?e$&hi2.VjTN=\"KG!M.e;obgsAKL44VqtA8rO(!2+tt630DZU<8H_bPXd5E?-\"ED\"%ofo7Th+sW>/gFITHC0D:`&a5'_+_jYc+B-_=RAre7CJG@U^Y\\dhWVm:eDsK3$Q(i3%0sqRpE\"9msqX2(VmsLNa4GI#krqPqTun6/UZYqZ\"t]Ld['FY*F.rn?ie\\[a6SOgH[f;lA0h6O7/OD(E$MI[&8V#KiN8&uc7;JS=mX-fF)=#t(mBF1/Wj#S+>k`\\P;J<DWVB/`ZX@rJ$l*)-.LP?F2Ys5\"Y9^?nb*?mqH;_Dp_Y7$X3*J\\iG'!,LoeIA&.CJm?OjiBYX3>ciJ*<?UMP:ij=G;L-@mOC#h*p79#P=[(B^)\"l1j+3UY:DqrcGQ-d/$Y'Y2`Ke0UY!VWr4,JH,D8rK/Ge.Ys,D-]m4>^&2=b*V5q)rR&`eRA/8@cpN*ugPo>B3AG:6A==Zdg(i0E@1-MS>e^%?KIfY:2[bisMQ.Fu1/oC5H]_EX32`JE#s]Ht[ih[g*5nj()E.Kd#D^kETH$%&@8-uUA:.O:dNH@][3-i=627nr_)-\")O27)qgNR>=<WjWdH\\;)/D4/<Ms\\Ek3rZm'$(OnW\\!JMD/oq$CQVTZcodCH\\*HEMb)*9/KhQn,I+?W%06u/&G;g8EE!HU,G,F9JeB/]1+E>R\"DUu>L^6Wk.'eW.fQER,NCC-9!3dk37Y',hEMo`m=.8^;M\"kbn,Ef9.%$CnAE4Aa.p+/Qo!MF:(FFd3:nMWcg-aHnKh3fiaUNU)9E$Z^fOqQ+T)B_UQ&$hMeZgQ6T;oVIq_aQj(e-[)(<lOXNo=,Xm6ppPu_360V[d&6tC.M?eUDl,ai8W>B7;Dq-;4/r34J8BW\\(e00riYXifEE)YLfsbWqN*V+U)M^.9GjLC2;9ij;:<(o*R2?0%A\\([QOLcoCVFd#o;;HldbeU`Ma,6)Jn8?>eQ<CRU1Y4nr1B9,Xi^5;OZa=Q(2o-f!sL<lp/S>P<4QN%c8\\F\"!(;2Jc'Cp!DAU/emo<_,@$<Z\"LA,F9b$ZV9*>#CO511p#f?OEn0Dn3Y,WSp*J2MhL0P_[(=;(8MSF=:R9uj$3W^b=e/1g=[-dFJdRDu>Srff0rY-d4MGUa62+Yd+cKtc,g@DK+;'?d@E/h\"\"]X'L4^XlcnT:)@Krl[9\"Z(WhMB]HedDD6EaKLi%t^>cY5iT1qk4DU,j1*JBu%M^rg)>B^i?n3bgho'-e0Uok_'DJb<=UY1K8YFX)H0gMblR5]rumX2'4gPcTcl+jWA-co\"WTc0fu0Wf[4(&MG)Q=1U&;LQDdmThDlJ_qP(%\"*Y#GCQT;=UEVF!2\"*\"&kZl;-b9PIQsDuT(NlY+$LT)GCju+^duCsJ/IZCF0)j-kAf\"#f$c1q[0^kO9!@'X+$a=#f\"MLL&-.O^rbnS]=.`IVD16TgAN1O':4NuO!&V:u[m7WUW5^Z&?9fjYsm-dO?g:#Wq;XCT1WS7gjM\\RrlSW^q<gP%%j:eFX(+FGEa[Ujttlpi!o/\\oM\\[c5jpb%$PhlCd'2);@S^K]nqjFoX!B&#i$6l8Un8np!M5!uJGq=`CA(UW(&N.Aaj%*C9hA,pD28fs[apEF&<WZ&Q\"INg5eF\"Gf'B/M`(b5kS+gI2cld#D.^uaXNi<'&=r4`(o0W'-01ZAJ2Ha+T4*-*U?Rp!GbtnFVVe[97RG2'!Ik$=j3XG\"QU[VOaA[37Fh]6Kk];[mu[:n6ragA:1p8nn/U0Cl=u`T0_I10;kI2infK>rTgHX@$@]U=Mc*+jGV5OefL()KX$#=\"g0Fo%Bb7D3'7)5h>Ti@D=,#!hqD]_r^oVKAm58-+EJ)mYbk)I;Uc[?b_>l3AjAM;n7q:s2!MVI)Jn;W%=r5uZ87%I?PX+^f;8Xi_C8u:63tLGc?*\\>)]8Q#k8XG30GEj(J!NI)\\W%\\D'6&B>M!>fLjZQ!b`;GZJ8e,bN(:_CY+La0CqGmA$$c7(hTVZn`A35#BUG9PKg%g4i)QgTEjC7u-H\"*d.U4u!t$73Q/M:^TQgDjEe'-S3fNfM67M0;PYA@-SbZ<E.'G^l+MkBgG)8j&Rp7\"it)tT=uuF`gjj^WrZJqeiQSU7``0[G;[RFEqAGi>$q/qG%m&'YquRaDLS\"_Shc+$a1N\\#;?DpGY?0lsN)$cG0TBUFFL<hi64(^#[p1fuj6hQ8asj/!MH8Y;M9#@^77XN&*nqt-Hgd6p3-_UbfTW85Y<kjq6eZ/9Q'Jmi,3hn5[FGC8)SE8(>fBr\\UHQVR6G@uEq14mZ)niCK]!+*BCEH1t;>'r[lK4$GWW(HX;,p[6Vc`e+JbC`C<`)\"(3Dt-^UokL1gmdYR9@YJ-+l>oZHPR%2qXma/;4k*Hp56hZC(tO%W9YhYU\\]-.3[r3d^4ggI&4V-79tmJmC-[pV[Ea,#:iI<\"G]TTE\\bS[]D\"!d$S]KeJ*rQU)!nuRGK3]bQ-uTqtqqbs]#hu2s0?L#pL#5dFIOKjBM@g$Ui_4I'WI;d0+UsEo[K:.J$E,g(7%HrX69_nOf^1G8h3cKtl(@jbhYlFRRSmpZmXeV*DSD#7@E1-H:?^@#8IA=r>l>e-H.8'Q4>1b\"W$XWX@FK-I?W:R*Z0]C;bF+CsIVU)^m?Y&(DgVe'::rZ3rCLFIO,W.`=B0Q:gGnhZ9D)+A?erc.m9ff)M_m67W3TMe?ZE8M7sst8KIs11k[mZOV>Cg$M\"<ntC0Ru'El_:Y4a@4=.X47QNYP$G3:(^6?sG@=J>A6[^-,dbl=BbT9WIQ*Z$4J^G,(.t\"soDWiY'Iu#4h\\Tn%J+2rWqKBXZB>jL*'G#h4\\^5ML#s?jmt,um&ojR3qgqeC8$6/4U3Y]e72oFWS__AGSp*H`ieAm84@Mq0\\'g/n4]E5@B`Lrh\\Y=b-Wrs--RkCEid;[DoOA(QI8'1pG[/NaD)Hn'k+WPYjL9Sg3?<:&8'47^iJ3I.P<0WCJb&/0N<dd`ZomNP%_SR>'3k+^+$9hdJ)>D0+qFk=\\Q:Coi\"CAoC]q/ADGbYJl<\\mH?$_g:pc@nZ.C?me'aG;+X4:!7Ju,gW/SL&Z,A+elrR85<pdU+7HhV9QE(7UCcmV,9/b'5AbW$gO!Yo650TW\"BUT<86/PUnCa^3aNL]]Io+\"@AWi1[4JWltnnB^T_!V`qGeXtUBuKpqX]'\\p-s9\\psNgNoM$-dB#%lBTVgo%\\/tWLDee2<FeH3Pc#9Thj14J>%:.^\\+]UE)lQN>hCHLU.92@<\"]_:4P;B%+jDl_C[An#XuelT9?n?DmF=agF%g'lZ)C5*QbWoNG,\\[%pB+tXBrI#sZt1Bg_;F_VbbeWM!o&CqcuD58>/^N=#?H4es3BnHADEi1efpU8J*m9KC2JmEBd$>G#-1YK>,?j!51Z]^ln7H4&N#E1BGFcX@Y=fH54sRhp8Nsn`a\"Kl&8-ZZbr_.#4UpX'+[_JJQ>h\\f5Sa`d9MKjPiF\\F&8E-=%E1fGQqs#S6)-(@Ik2AO_Qd&+$\\;ds,NOK!qm$=(JdMB1bXB/mTceVq'*LM0>i\"pUq1js**?ZCS)<G/hh-k`i5h;t:O+i]9-'9%ianOO+JE)hR)ChmYgpfIu>;HntD@CXEn,I);0h:0\"DD=Z'?7*;bkj5s-eR&r:\"d/hu*]cH!%Tf[8`*:l\"b2i8DQQ\\est3u6JgdcFYf\\KR\"[ek`1Ze(gt16`Iq-?,RG9i<.Vk<Qh8Ok&el38p`%TAng@TS>Ql#.Ndl,3!5&$J$5tb[2qO)lsXMFQt(-C(WT@^^p^oFPnK3-Oc==gnLqRte^B=G6s7f(_(GUd:;$X&_&3CCNs76%^_=*:27a&+7l&;b\"%Sb</F8JI.9S&EA`H&jh77*h.](,k!(IRYWGT+@n[*Bp39L:Jf^D-7#qG(Ah[ggo4Nq\\K6NZLF(#e!f4h>2rKG0q*ee7XW-Kb6O6JY9:cL\\U\\*,AuBR\"iY.,XF!P7'm`6'\"\\dC4HL0-%@,8SHnP*ZMj\\d_m42h^AG^M]kr=b35KB,02OT\"b]hP>!ROtQZRU0!QV:g\\=i_s0KGO+GLXdXW'P$efYp?W,=ZQ;V9V54<BHAj'>?;JG;'(]n7YFVKWf=d+FL2LL;\\k!kXBcQ=*2h$AmoR(rCXnS>-8V1qCa<K*Rjb'5]0mB1b9/3iJS#?odJ.!'CT>hMOS-CW/6+HHXQ64JNAZV6QA^AL'fg3AW-W2u?[;/f^Vsq$<3kMO0(K#$P<QA$0]i!0lI,p5obF/F'%D%\\],U@1k\\BA=gl/T.I\\qW^o3#<B0RTPpC/j!%k:F0IP`g2>uc2_6[2.bbrr)XSmL0V=\"PjMJ8aGqD7_I0NmXtQHLQ!-%0GHJ6LY\\0lUlO1=Vm)$82cRr(K(92%_$B%2$Pa(-FdLt1*,7KLp`T#mS[r>q3d0k`5KYSQ,fuHSu5YY[57pVr($V][:HPm\\nNWEh5k].P(?]UJ)$P>:4.l^B8\\*.H.cW_p[,ZkR4^$U/r[U-lA*1KSZX#,nRiSdmYr1mH#2['5,&52kHc+kUP:-g4gb$KIWKrG=N<3tnF[^8#TiGBZYHSdsf7uFgd/hiKOY26FO;KA:qkk`*C=AR?^-7XU^m[!^CEOsm7@dYb=]p/]\"o?gq237\"U:Bd\"DjH-E6E)kAN5N:U52*oI'a8i-]+ZWfl5BeIRX;iQsoM97*iHk_\\.iWETP4daLk5ei[@SYY`hWPs2'm$Nc<!%B,^<fNY&Trq?\\jV\"Aj8Auu28bZqJ&UeD[<,r>'X#[oigQZPn43%iT?mqL@fgBU=RST^R^;aq&5e_9D'@75f5LGW;g*.kKR:WIiQD9!jo6nYNR1<LX0'W!8nTe#m.>]VCaud.5f2;.OV!/VQ+l_DKIO5lO,jMWI`B>,kASfI&\\Q^p&([7.KO2`7sRF4cZ,0kVi:f.q^=dLRUa95R0aTm_jIKIpPa<\"9JFC/hn?sOsYeRb8ZO1;-BN$:.:A\\cQAV1XKV`SQPTFXU)(`9.2.E\"q=p=NZnT;KM7GUb,SK:,/iMY+W9u'mUWFd6Au\"]+:.6U<\"l\\iAiaM=nu^dGtL90>8u1I5`P/)M!(lVM-;Xt]O6r'Wn2`U]K$?S0\\h6?,*bKtFcIj=HTo@'$s#E6bRhUKlAI7DPpH4uCG/$*W`oZ=#j.L2cn:ke*E>bc9VcrN^]'9&IbOiYTX[YKfc]ZpOh0_eLO$M_c-q4/D-OL:#Kfkc3jpMa@p9.`Gs\"o7.2C=lRKJ#!8:kbmIJ&AsjHUXCa2<(:DVam_Rk!mi5%/B#C`_?2)_%XiToR4;Nk=a3.<^X!U)G=\"\"?41qT9(&JBe%%uSPH<H&+gTG/#O$e*b<FNGiOe1>E])@7\\9UW;>*;kVr3<qM/nebnk#AKT\\22K#nL-_(LQ+0/fk;>5>Y,K:?VUQNQ\\rXLlh+&B7hYjQB-.IM=3HVYMQQJ9hgjWXQ-_+FQco\"N3b^m_FX8r/EH*+qTAn:c3#ARQh.OeIJ\"Tbok@dLXeqYWIG\\n!L@)48/lFSMht!&9LqB',PTHAE5[(mM_G4&[W>=WriB.&<=4ula+F,sh/TsS;PBSMf6(g:A&Xd5&SO*qt=]b$_iQ&#q[2$4mf3Og`;=49_nN?eUC:%6[D*,<]NYVjNh9d<&Zoi!E#n5j=S!Yp&!P**s=pW)UD>&8><]'ERa\"ZF<ep^-5SoZ+*9-/9MWII,YmP>c8C6]RNR@#XU3-\\/t]+HST)O7H8\\N/Dii7Qp+A<C^O8YAs/gX/$4#GoB*16!`]f^-urI5%0?Es3RVd_V#uYbk3taL6\\ds,14q?<t[aOZ0bn'')D+WObtL#M'k.97=:Hndl#&8<%Bd&gZ$b*q_--1L_%FK23JR9+J-$m,p?_&42L!h!LC%W(I-9mQo@@]Hri4r?3AJa*C<\\=Y?WpWKC#+CR:r$$Ec#cia0jhQUB2/Oa\"18efOL)2SJa@'*t,=O7=!GrC6N3;6in#^'EL=7P0g9L)T@<ECfk)Cmroa'bKEsYF$PPJb\\:06]!_29&nmspd+RRCpi!c?e-G2^--@5$&N^*an(P3a)P5GIQ^[KR[);W&=ZjNeI`<,lNh,UA\"hII46NcB+BrA:^qeJY4Mb9aT#R+X=XnKpA,O?.k%^/,S@UlaL3TSsS1HVi#FQXO+U>,h,iHb9@BM9HVPqNaNdT4gmmb\\LCI5U%:RjsMlZ)DK\\au`f;[=2+Cc`ih!qW+u)[dVje==p>HH>HDb:7;Q!]_&6_3:/@G-0KsUP7tXr=CPieb=;CO8T^FB/HbCnq\\NdO'9D[G7Q<^A<t_,+hQ,Fh0dSl+nmHa$Lt#R<7)^OeFBJKr+B!hAh]:N'^;Q1(%\\$[>;s)URccL/@eN1!X7%I&C1j]@bF8'lCto6F*[kk_dL=\\gNBfZ-+.uIWn\\O8\"k[P]!Gs:,dkJjn#:9IGh,`l`phCHL9I`u74e?1\"jNEC<AUIcKt@I/t@f3T.f+Xo-nl1\\HXB$_)R7Hs\"P$p3=O39(P&q'8X.GQQ&QAPodF4BjoAWM?W5)8i@J,mHnn'Y`j-k6Y@=Nu[/7;9GIIn?\\u0/T^7:<@CoZp%D6t4o.9.SsO5Lc]\"fr(HLP#'oFL&g,93Is#1jj%q`%=9\"Y??3,%&^f6/W!Bd?oa\\fF#h\"\\(F\"j]BNGf/3?H7u7#g=9tsUo:,%+4:f=QduRhl(JFElKp#KjXsoYKd]:=QBubd_@L=g=P[LBEJWsGWDuNd^UkTTrI.iAm67$L$[D73-YV6MRNoG5j&UQC+*?<,/5Y?uh&qAG&^b'prUd^K65*2cjIJu!L0T)*0AWY+MSggVVJc;;W;BN]!$_Klh#]f5%2@psr3WP55.uMu_Mu7/R/X`HFqO2Ma?'`f:/NG=Z#&0k^51!c;jhFYcAE$suWY\\fkbbBr/^%jl5[j>HE<$J1Y\"A10pl-Jb.AYk9Gd/EJ!\\_.:P1Vd3SM$U'/kd_OmW3X3,O2O.,cVAYC.KZhUk(pt'T!)AHPkJSa:E`O%`Mno.X&PaZL(DfhY[k4#?f=TR)i?[P,Z3<W8o/ZRg_8:.A0tn1Z6YIsr^dr\"+p..NLB@3O@NUBfMq1E^`C-&lpn_DPK(M6f0k<5cG?*M-b&MaWh:;]LZ#rlsMM*5c?,].Oa]NJXPu#7Xo3bO7.2#:ChhjjL'I08f+0[LEN8TY*.Lco&T$ML4HpE9B&\\higa?4,1m5HlcD+'lD?Z;uMnJ8bO]:*<i.t=U6EbZlC(fK-30;'qM\"_=OiUF$QAa-3T6ljaU%7nBRT1bhu@Pb_C^7_JOY5\"2i=5$8n_A4j*Hpfahs*ab$;^f!m#9Hm]oHZ*C`)NUj9PA97D^*^`Gk%c;\\cC_iHQ5X%_kSuN;'X2dk*FeBWZ1RS\\C.^oBXVRM3>-PRhGBHfKfj<&T=)?a&F1MT]<&?/Xc+K&W\"9MQT+f%T#_oQ?/4Ki)63tIIi`JIa_-#Ma-T#;#rMoqH'i[D.F\"YWhIYk!+k\"S>O$=d+Nd_1O2Gkt2li1m/HHMQP40aM\"MK6P>bOPE*-_`3%OY6d8-GI0Q8@RaDXSCC=s=V1r>U,W%]YM?pelW89QRcZq1?^]qm*UY&\\F[Qt=Q?-4*U$=Z_fXYf:n(\"i%Ui'A\"gSdEh8dZFn#E^&(U\",qF/eS%6L:m>,qY,E8>\\WlC5Em[R?$H.b'>1Qh#_ZK<MdR'amD87c6:%L?';-+e3SY-$;Sf9sAB2CS*%9lk+mH6i0iRT47]tH,Z,&ImMfL3ek70k/\"a#0[=MiQXeOA\"=4p9GJ%W9'a(!HW5.Mlg2@ZDGBQ9K9]Kc,-cann!A,5b-,SV^rlZLqrQ%*M8X3.5\\ki\"S`ChJ)KUicl)=m$m#G3`;qQMQ:-$W?*YUqA@2c8/]ri;A!4?Ym#6$!N<FZ=5Hg9&'_?4S-D:T:hohfbWQNGP5^'`]=+M3Wk$/?3%MH]@6^R(3S/s6FdQ[*,hhs?B#OpCL>!kakSuVoe9^W.O@S,G</@XH*9+`_!#mqD!b/E2K0peu9Y>*J(?;LET$HfkjF]3EG_M&#a'TOXP7QGGT&LZ_=TQ0:f\\GFgOI`V]CKk59^ZuArJWo:I(F_gEEWqq-V)B@2_P[XmLpd$^D*c*[QVRG1R;Q8rkB#]>[&R\\6U.g+cT&gd&k-]Zr.!AMf_n/DJsI8.4SmB4EbSNcWaNJ1udQ;f*_,L!k:#?nCe)pN;$1Ed[Yj-!4^.#:`1BA=FSENLNK+&''-M:^Is+E.i!U+6adLo,g@K)oMFX6,DuXsci@DHh`?%_6h4LN+`sYSQa=kGM]\\01)#\"+k/>QJZs:RYRM@p\\_d8/)OGF)NkX3l/gQW+\\[DmR%[%sq.#AK2F>s`+[MKJ8JXj[DV6lQ%.DqX(3`)njk9m0nY;`:#(9X+%7kpXI32fO@_sbA/e.D:kod_C!_*->d5ik0,\\4k`X=t1D>g+23+bjM6[\"^Lp=<k[[jTI3Y@\":0;;Z.i[r:3/n:1\\PYDcg(55\"TT!J)GINXNg^7rAHTq<bHZP\"@m\"!4.L+!n3W#d>E/PoQDn([s/&;+H!YpKq\\:58A77om'C'I_>@b7*!l=LZ%!@'Vu%-N9)`=Ti\\B+g.!bO8>e;trq!d,'ncZesE[&I/=(CG!=n8ou8_EocK-;VBP_q9iKS@6Y=kGJX\\/-dF;#*'>&GKjmP66M:rK@)ZL_:JOi#^QX[U$!$Xp-&luDe=\"%L3SFa\"4'Pl<N5oH?]lH9)IT.`PF;]!'qDO'#;ml!K[N$\"nK<f-)8,2U?m9+X-0fjX?e6q1/qtsB9#ulArC/+p>%#m*0`UOMjY3M0;7NQ%SfI45he$.P;\\ggibjfW<edd_q@A.eRX4)/5pLLsWa%C*(<k]PP,'g,k4iBV:u7%g19;QXP6K+_@HR4u_LG!TudI:k,m,>$8Yd/aX,D9\\pLX)S;ll]!;RqOjWaH-)t#8$\"sSJ7/r830dR'A-o'?E@q`'EHo#/)0pp\\r!-[DC6mp_KXqmTlg)LofkONfSjb63(\"uQlR+JVu\\!e'JnVrkTecCn.:KF!dYXl*IaDtBX)+JcRhC454DX6:EeeU(,<oGW:W^uS>3rVB<H]LL<e$)C9Li^Pf0^aQR3\"i&-@2@b!$nL#\"9'@W3C;T'\"K7613e7:h$cD_\\mM`Fe/N*aNW9qi`a_Y2]X!Uoj\"T_cZ+oV<Q+L7!F\"^<uH@AMLdW>5dk.:ci[O49<0qVHNi`?*rg87/K&u:=#D`bp\\eLjcrm2fe\\p4/^>U(M&V<$J5K')`t,GG*t2FNKk:d5QBVWF5W/mBpE?!m.)^iWPiiMJM@8hG2VZ.&/reG;XY@sV9iT%b'HZJ0<spaF0oo$h&>PT)f-F1WEeJ^\"FZD8&Cl]5bc!81fQ!FFh2/@)<_W[RD5J(t'7=cCgol)%!/O9'Y<**iT$e&&!-mZb(;,`I!&W&_=,UDL.bb,PT%X4J=V%rJm!Y+B\"P$m(,C[WWkV&O&bo%&WaUC2RRQN$20#Tsm'd//q#W9bac>&PffgfI^P<9K-oZV@!LQ>6NtOttdZ:PGYtYc\\arbe5$PT=9`E%ouanR0Hn[(gtDp?1QjD7od#mFULdpfD>^O0p%oug/2#)FYnWXVY[@bXVP!;s'j[%W5]1uD);,r,U54TB9L48LQOB:fd.X\"+\"YS/4*IOiHAsL:;;9gC=^W');/BSOX[9C:(VsZ,:#[Hqc[=Aa&F+_;La-T?!-rO6[0TX5pdD/d`deqr]JPGE:<SYbMH7?Xm8.BR2\"kM%(>;`+,I>C&]lJ\"E&!\"L];]\"(Y'W`\\@E?k1\"X!de!1PA.BkAXT%f'M%%5`:>%Q\\'r1+Mrksd,X?jM@?[IQF[^-<\\ZG4B7SoI\\cq%/C-/_5,#Th0GH!>H<O$$G[;[D&hW#m,7PLPL.Q%r&P#Js?a1jOGchg?jQet7`hJ1#Y%>Et)*1Yj&KDrQ(?QCI7Gtku+;&h'c7Cm*,&#kAYZ2'N<-^k'uO`LgL>dZ$*I(Sm=n<p\\E%p??^igDU;#3m418P%rL^^R\\p^NnC21W_<JLAYt%O4N;^NFHPV.Agmj:6LE/XL$E.Bnb4T9$],_Nn76gc:<fG+ET:sKLP_VoqY&ZVLe=Z[ko+@O65s1P(I##K\\\"'Zh4T.X/?cNoD)(2-)r`M!bVPI4BD6D0OXogunZY\"2mdS'B1Y47B&rf\\nl`ipl-km7tJiQTA)9_\\(6/C`#erKu]=)s2Zh-or,;\"M76Ws3k[i_X?(TtD8t'7XlgN@.IFlJF?haTbW?Q>J;sO[DSX4pRgu!oqp&RZ?YF=n(:p3aF`7OY)-kHqIO2Qc&\"%DfcDlE*8=A^ps6Gj->Dd>*]Ot$3lj&)iGX.X0\"^0-(Y]!rCA+]LEMed1Jt08>)\\/9VKsIef@b.e<'Tt9q&N4.6R(V$:P_#VTACN?huA!2of-;S,P&FN@&Uae#X$+T4q;MEe[3DDdl)OCh9[bC<$E(YhfTOHK1)S44@e)62ok;W;fC&&?;d6WOOpPURdij)MuAHqB'Y;C0c3gWS4a2YNt2Q8k[LQ#l0$-Qq!Xpq[g'%oHMWT]16Nai220Cp,ccu?M:nAGeD5gBG*f2)=c5>k&BT*teX3Q)1#@aJfMkj?-',-_8.:[>LbsL8fVXg9p]3bNdi'6;]eH6TKR)GK$2#nqlhEg&[<b9p3hPI<-@G@%s2bH4HrN]W.\"CGpnh:)Cc!aL$?YSH#P_dZ8G?h#.otT!cmS],(I($^24tjU96W_3FQ-QbW-;T(<3s<_ND9'X2NXc@dQe-WFS9TOY`iN[k/h4Z/&oihWe/GN:`AD5-o5a$k+kYdfTf=\\1oSt4W>pj?rm(A#[4qcKLoXb@G8)pNpm)$3W$$X:h^+-(oVaPm/S=2]s*!a=(T9e>PfR7^ecWkq^fLML^3[mm.ar2:ggi\\8QP\"c2d<^R19mEZQ&o:D^A4]akf$QaoC#)Hg79T[qA4\\gA_@6jpAB$MI?q`ZC^Ve(d]j*9%n^\\3.*)7s/?d^\\\\(Nf:NCNgj]Pc>N@_dd04C2-:!)<(`u##Tr%GUSaCe))c@DVVY1E$7Frj6<,L)9(.ph/K2#!=QhO88B,`s-+\\6DJ395Ae^MNdY`j%NrgH=BeuIaKn]aa3'2XPG*O#T%=r[;`^p3$n]HT$)6ILiP5#*m%#T(+1]P>_WWd?MMFtjuIPXI+ei(`Y(Yh!@s;@t:UGq87sH9a@Y:h-LAJsG.]Ud`Zs7(\"]#kG]UGW3*=C-]\\:@a3Qqb8*H+==ciG_*.NL&hn1e$fr-J/3cM`7fnui$kYF1kg!''ZRPMK7;G/18X6<Cs[iX-FSOQ=AU2&B`RK4bX7;Ump'u<!!1fB+<jLGh6O0E)H8(`(@;eT'k]Jpr]s&-^!>7pM88RqAOm93k5(eodg6IcMq4D#ZLk0!!.SV.,hjqCb$pXh-uP@Gqc.JA0N),VY).;)1&gZKIGU9&\\B.?9CHPDSZF1qG/*VEt]6LH6;EVn5.Z[?n(Q]YLp]`t9%!,]bKlT7K@Af:#HO!E-KGkAA2R$Vtj\\B6%Rrjq%1eJpJ=ONt76^<S]2'b13pg1BB^qJU>_h<)#?KQh_3a)ghpBQc5\"WW2O`6@N&Q?=@44=7(;hT&`j8I@<ekF=>/@q%PqX@6ENuL;VMt!1$u@p@INh`S]2fXktnJ;kNqW;[IL*:2R3T6?&e[J648UPdN^(c5DV:oU13k*MD>qp@;AE$q2`k?D043p8/n5hEqNr:9>&B83u,'_j]J$qju*IDH7<T;Q:3UU5pF%3VQ?'sQIVsOe?k1)2/Z]0k.SGI1)/?&K]#I'`9<U^D\\MnLMR]rg+N:JkeL5,hGbhREkbG/I9W>V%)Q%_6HQb5g[S]A./J`nH44:o<=3$(jNRmCW+0+qO3<JbSi:4:G%-\"iiO=1^I6a#8O9cs/G\"V]ji[hhZjZ.BQ>c&H'iH!3>M@h#V*PENn+2LD+C(R$7V(>L?=.(Gr+6H;:-#qY*rZGe=(7dd$<NN>.AVVW&.brLUcRUTA72-:[49$Ks0$=AL]'78IX4-Ph9(Ejmp<V7Ta\")U@fT3HWec8L`QHn#qnc\\8p0<:]sn'A&iU8CPEp^EK\"Qmr\"-('TB2N-Ja@s>`[d-6AGnc]tR^QonT:H,01ZLP><la2J:@4Qrc-@<E`ckH=-Pa'6Vhm6DZqm*3(_[r(9#-P>JVC3p[!%Q)Wf2O0iFZ;GDGVl$t$0e\"juA`W$%[!#g.NU(T*.U%p8Sqsr\\t:nmnN$=6UL/5+NkHcqWRS$!V3,]V$BTJXce;KVPi<T37Nk<HD'\\@!R)mY[`'n`7MD>-DX<+DfY.RJY(\\5`YYNgm5'GhL^J5(4;VJ[r^W*A=Qa9n:@s?X>Ru:0CrMQkKkh\"/V\"'mOds_]1GpE-FY;588'@$>mA!;4c.7;*E#!\",7dJ.HL\\AS=)Ke`k`2#O<J&n'>Qi%FgDJG_Nk7Jhhjj?G9n\"R=tB>'5j\\Iqf@jnVO`MHK8<qWulbYfnYi:0*[7gI+r]8Vc1=7q?\\Li?3)HPNJ]/>:m'$(Ip<'H7Klll3A/'q[#K>?aWF#l=d3!MVqnbIk;k]534)r=<=:M^KTAE'L6QU4'7S\\:P-E'Gg0,VJr`gOT!0a+>RANWI0'RrqC^M*\\H8.4Y8Y.NNNbrFE/,+GN9,>ni`%\"d`.]AhoN_8t?])-Rbl)%a9H>kHC_CS,9Bf6IN`j0a2cC?R6\"%X/[ludkWTEcLN58[;_8eP5#sWCQaUW%>)3F=_`.nNJqD)q+T&qf,Lg-g=ceDn[Vn?:@n7i.E@XAR/+SE?Zs(OJR[nt30g3fUtNo@OjfuIU8hj)31(.T9.%F_3Y\\%:R2[EN15:,&TMTOU``U:.'L&p[?gP5\"65$r5JH=0b<+R!6J+8ZE#Tn\"+,k9j#H&>fsXgL-!gFZ[Q'9+3<hqe6*b!6ZDc3f)!'k()*FY>_queIFZ%cN*\\R/N*Y-$#Jdk:LH0$cK+@J>Jm2ir4kAKL9P#9qIQDcTrjk?LDu%>>fFLZu<&61UjLMiS;*=`[lTMH=Cgg_oKV2Q(L!%ErIJO=WnBCf--B4./a(MdIdA!q(3mgW^=q)e;8g\".2'm]0=\"U7(hporreLLAtqeP.4cTbu`aS^i]S!(!R&;T>(BWtidOkkj-@+.S9FPT%t-g7q$W^04n,7$eYUV4Qe1KC,?a99H-s&-S#8BMntI)[rL98lPBB^O3MlKa8je`5.kJ;rrr1K]KnD>7K5aWTgjAPEdjYNgrEmd'AD_c!oqFE)$F/#Wc$DGbip.[92h9KfW5H<tjN<`ep0ZH2O,c^/0=b+(/&L5r?H3Qh(_'kR;:]faP9\\]b=1G%#nIc:P\\M.g)57Jb5\\@h+bCiSl\\LeHZETF>b4SDu^\":NoJOWO0E`q.N3ApL+;81V@AKg-+6)I-@\\ZWC'@P!='2^QP>j:IoO4=?!*eMJ@\"OC.D8gLE<=9,u5&.ZCk:@K;0ZB8)]p!BA7GUDV,`n,BW6ZH,KhXl7;brc.!>7l+^hZtuI%fCU88=(qU8$^>O\"i%E4(2dQhgrP2iJIqA,L?A5,tl=l9@,k>VO@`2f1jBb@E$('Wtqd@?e%>gdWdt^W#HYGXe*lYQ<<S0-)rW];b21clI7*t5#5R#!q+#5Cn5Q,\\tV:-Wn-Vm,E^%;WUcs1[(ThQ<qV1uN;DG/B+L!hT<_5NVoP]Snuih@>%`aGjAZlnZY1)`AR\\ct=&MDd>/J7O^L:[/,T?d8U;ORctu/`=q9RKH%\"6cq#;!XLYFa.odCeCql9lcXspP+\\_SJdD$bJYqR3&/AYSj$bd!oirmT\"9`fjQckVTUN3ctbGEB[!J%8!h>+]g/oVjVm-f)qaE(MT.Y't>GEA\\5b/+p%YFE(o\"]MI*o+7=mCH:q\"$1_L#]36eR0N)q4,f$rtl#SJ/:BQ'\\#_2hdWh#/)(Vn9+!,\"@0DtejA-.\"WOj(i(@]MIM8W1@$O5t>_Y1]i\\k:qRP_\"fc%5;VX\"[_6%U\"d\"pLR([Jl3nCDM<jB>2l;[8n0XT:oJ)cofio\\KN;C[,FlOM\".a\";J?F;6<d.o3e5cc_ZY)ZYbtrnA\"LJcW5rE9bS]bEJ0>lL<*sjlis;l7>tc>=*++cSA;P*Ho7.J7@Cc0gP3L;7.CH\"ff0n;!J]J%<WSgS%Z@a-p':ifAt#44:;;bhX\\t;O'Klf?6YBBK1>A5WfU0D:%Ck=X9Ir)r@_LCF3G.<%gn\"8a3mt4d<#0(%!FYHVAV6FQZr#J9NlOI-._@*T@+DFJVR%B\"W\\FTs_<28YM3paA?g<1d/c/.A[d-'_cdf/mlN07i<qu$?b@4P,EqGAJ4ju)rJX+QNL2>93P^0^cdDHIQ\"W1S<\\9t8AcYf^2L^#([19I4kB5sFcpM=(n[h.+e\\QCl5TN^I8(_6D1m>BG(5pcE!n?l1,N#J8dX80:c&m'`E2%u.0S1Bf&.Ib8[%sA%eH[7PDQpR=,)KG'\\MB?Eg6];l9H_]pbX.o`]>&0c`jeB2[_cV,tBQdb8O6\"B^\\3@/`60&C&<9m\"+lEo1cr^lO@<-r*\"LBk$\\2Y&p:'3$D(Zo5lF`WJ\"c@of,6'<,j3&c%s@N`DoVF^)K#HnN_L$b5.>R3]4pfop<-1%]E=f'B-jjl!5B'=mq7Lf-$,YD1X\\V&PV6OqF'QP6LV7eQ)l!Wg@e&I&,siSCQUuA?#U-II>k\\/Ot`32,\"F0`/53PX/Mc*OIdY\"YAnN>_6]`W\\<p?qMdt?_6/)e?;*G\"Lb'Xn-YV]a>RJk;6ii0XdJ.ts)'/**95]Kbq5h@unM[e(\"$E=S+b^$[h0=O3kWW'*sdfehc8OK'X69!\"QC&b_.9E=j*-A^LEcdN#\"?fK\"r\"S^trB)dcp:[iX$.h!'Foo6m6mjqm52mGb4ZbOcO!t+q#1njqD\"t6Gu=P@;!h`A'Xk`N*:O:RPJd[I9.gDSf\"+6<,M7=r0(l16Rdmh4ac#nl-+ahG_X2W6qrTQ6DB[S5m>lplBq;Q2fHWDD]Mh#qfA#C*TBKEhN2DLW\"9VZbW#^5%L*/7Cbj6;D422IcUUMZ*HTDbhU?FS45Y79+$sMOiLCp\\>3+r8gY%cmA^&TDu#*bZM=o5A=JQaIbaW;?B5@95kiW(e[H_9=81mcDH-qZ\"ua#p6*1+O+\"jjiU/h&`CQB4-6L[M-$EEpI+i,UrZUmX]XC>L*!!Ybia+`HRA>4L*%l-_>/Ge9O]H!j(:Ni[rWl/=[u$O*?F%Q[Wq:1N=8%G[*fT3V?nucHVmS1GL+8%Y6?9hX5K8Jdj-*ts\\$um:$!ALp]6q#!p/biVZ.etb$FsO\\E]t[20!k!sYUj!<`+(Dr,\"Ban_I<`\\Mg^nCO9A.UrPSkhj,eaHU%_2nJ.f1$BsPaNH-*2EZd2tfrPXuMcgg!tQ2!Fn29rVdV[:f:,Qp07j9]B\\';,&icmJ:ED<WWVGd[r@Z]ce`\\*lE,m6Pc[j:\\bDKo`WOJeqe!a5`O,H\\-5]1O,7:qIUh/,.MeiMk:R\\_o9e4@T*T\\RtP8PYjHVDEFY@-nBtt/\"`2q[FmM=rHA%5KCtdN5P]kei53-qG;E_<+_q!1\\]&:WtfdB#(,;\\T%n_Qkt]TjEm_0XbbY&VqZlt*P\"B7,n15,RIURf1;?MB!r'#P+PS,g:oTW[]9ahORc7;O\"OFD>s#Xm.^?[B3n?YBXS#.q+^k(*fe?Bni#tZ*(;uUK`)Rar4iRJP9E.c$8OSq5N<Za-5,oGR&Js.VZWK(i^(ZnJ,_P/HU!I7qCNIU(n#gB9-2'S6k#;II-_-Nd7Yao/[L?C4AH_thK%G]'+$D^-M0jNcg>RRp)c,8,bOY>bUaM3?LKLaoemT^p#L8X:Y:2l0,&#WrYg9&@/lhgnM[YAA\"#1M#*\"5L`W,)ulh*Z`3;/L`\"21;EkX^UWoRA>p@#Nk4nNR>93nl?QE6*lH@qgqlV[(M#9>\"2Sk*dYq_ru(q9/r=_T,aJQ)026Er&/#9jEj!O[-p3bbK2M@lHnrOpikHR<F-\"Rh#0K\"K!Z[EO*IdWe^@egk=<2k\"NqFt<%hf#8+&I!)\"6b(I$f$S%^O?JgY91.JSZH+5;f%+-e!b0H>CMF>]ASrrG[[KFR0\"iKMb-($36'\"^IY0/nOje+$*8U48\\2W.J/=AeP6mM1FS6p;e1R8rToPm.A*2u&M+;Qo@J8-_[W[?&eVU$6j2<;W-R);+iU)C]g@'f]YC`t;/Bld8\\$aZ8m,Mdeg%K<P0HEn60mAhchIB]#64nhP]r$5&>YRNk@p?Pn8uC20n#`DIbBq/\"UNdKd)U)6E#bC&VI+Y8GRNt3Wf(&BHdQssuo68I2/gX6tde-a8PfG.$>tu'\"nP<7A8pZ2_>I\"0\\2qQ@3*j>GU7:>3<@JPVa,j:&R-IT7b8i-b6'[D@T&TVr[^D$p20![n+?uJ<^4\\U10LL^tp.Nr@ZOiC-?@:$TSqDcUP%_O!uiSfM<7-X/HiCkF\\.g(8>9C*mQ)<G\\XVW>8e=B1@-`Ndlq*)be@USa+A?gmL/0*?,caUhlIo=(8=<LtHl9k/nq[M,Q9+1.kCH.Wt#@Cs\"Q5Q'XAn4)sQ?h>b*HhPWuM.!e#H3F9#OaSaG-nT\"'\\\"f)BKR6*;5k81pg_aJYAY1[g.G9HBI)eG^=/TgUcq;e)I#(#P(!0:ub*[P/Du)q*0dDE:cDSdR`#`p`+4D\\bXQCd<hs'1*<geN387o_6qrC906Rer'16IUT%^!nilp@T\"g#;KroVhJ4$H'#o/[o]B#Ing8Bia8iKtrn*6(C2E#e&G4B^s%+Bdt-.?c<klSL#3>J?RVdX_F3VTf(`D%:f&*--\"8.QL%4pGF!bS1J(+ckpNPfi0b;*Y&id8/MLX;Fe+=?ZBn)ko+jVW^75c39g56k/*)gDC@3iYkS<MtcFFA\\55$^Ngp%\\P`0%&Pm0UFN#4$oZ)Q-`-DkZ*]Kb@k%Qt=0+.KhV-h.+(iQkZ7pD;saY8-ar9a6ZoJpX#JJAg.5KQW+.,8/&g0#ud:+Rl6*U-6Que$4+-(bVk,H-T*G<Y%$nFbF&lErX)#7JX\\51lBcFsmdQNX#hZXlPU<jbc6=]_Veb_BR?/\"4C<r3=*-cQlhmAe2++a0j9Jj7'&^TR)HT3a\\Uqt:$R-a=Vh\"i),oQT*^;_m<8:'+\\Ga2uA\\)%*3(9W)eAWU,kg8jZ\\Z/c76VVj_c60jaS/QU/!\\.p6U#3'>pN4.:g'D$!tu-F-5V6'B*Q?&<&eH&E&p]M?)+``konq,YRN!@Na=JQO5\"Q1Ak6K<URS,KJ:IP_DS`KT(t*Co.X>\\)Et7*P5$IH[S$RG@>0GKauM+5Z7FqNb5Am)8jb\\q_IoYg;tEj2ZM!BL_kC($?g%sfi[m&PBmp.Z@Ih8+uX9g+C6oakNW]dNUIa$.6a,D\"S=8VdWbq^naT5$2rG$CF&Ocs_lZ@\"BcBu!-QKu<]l!l2l\\p-M(H<9B\"8@lh`\\SI-2:s(4R5j4eg;KPsYs2L`PXQB\\>jk'?j^FkqjtMZ+`/kjB1QNS]me=9%;oDo&,?kK>_oWF#;4!W7j0B%I+d/*\"/6aRR<2&6E8>J>h)hpF1Kk!#>U?q7qd9uA?KE\\Ljk`n`eF4It\"b02537b].d>_G/^<FNu8C<J3c\\d(gLp/\\Q'mBM-XO2.+X=j69kX7:HsM<:#n](=8tf_C;(Lg%@Q^.Q%<'Q?u;J?Qp3$Lu1lf8kk*>VR_k*@C&*S&fhO7RlnamahgW:?bG0Zi)LbS[k5oIk>*N(1%lE,C,>=+DefHY*qd'iB<``@mg?`FnGGOZq7!qh9E-48tc#^iWZPc!?tcI5FU)qm\\.>3RKnX1DRJuCn++tWn[Xfoi&WW\"LPi4a*Chd7:F+oj*.'D8>gn$QnOdkZO.Rn!Ya9WoZ$W]041Gke9n!FW7<A'2eH_MuaZOQK0=.s`$Ni3)69$?]j$hsbX#-L80U0'G^NX;#QMj^cpTYRoo14@&*nMjKMKUCb-CPaMKRc>4T$U#5<*F/@!kk2;Z-AA[8fNP(:e.]1hI7$PBu:4'>^Bajin^WR5`t!,E%Ytf^5iXp@Ljr0)]<,Lcm1eJ\"L2QnPhi([-jP@QS2,.c<tN(_WL<Taiq<X=^I[!>BceVJc:c1*Hs:S)&o\"mp-^#@Z<4IU:]\\ig\",,P-4ZL%>0mXL-a@4)X+ED$T</d008?q&P%-]5T\\HL`X`5&Tj_H(o#?='3VA!f%GEj2rV9!s'T,P68ga3k^WL-3e'?\\aW/aF.H2X0Kjsfb^&un2n#-Bili?IBlei?,J(3H]2lea5usBGdYW0>eAn!&2e;0G8=QP*1a*M_`<YiWlFT3r#5/UW[DrU.U[f#eau/(`1SkDp(5j5cmaQU9&!NHg=X?Frd3q6P6@b62H2:ndj\"!naY5H/P/WS\"\"m<Pi<P;7;PQlT5L8f#gj=+87EBWS\\[Ya7aTiE$U&kTDRf&&d$.&/,*\":[0+M8H\\eW$'g)_gJ^M<_Xp79@,K5f<=ms'N=_%;I=O+>9_6_D0(?ER&_9L*T!PSiZt92)R^a%cp56BJd%41\"YK$r09gP0^\"ETc#Fe4H6&.^$,0Ls\\#)oT-/%@st_cH1H4dTQ0`p<$\\&JS/(K*M/kC*+(.j_QM>>N'JPD+0[sU1U]sgGoUo?Md?-b-4m^Q8LDh][6;09=scG6.N*gno.(>@`2LFBiW'!@^>dGP6GSNEh,Fb5M<o<&,N$tn:Qti3-*$!B#QdMd[t-2[lu_BC`Y!#\"j\\G,(b!H*+rkVfB2KM]<@IY&#Sn1*P`uG<E.WgPG#V+ep6T[NL#r:iOmmP]#SA^518dcihH@iK*DS8G:_T]-h/6<o@SZ]0QQ2e&;<U?W)AtWu5-PD3COMq#_@&t5T3\\W?gg:WV?5j*3!l?SermldrSMqcj'Z`6i*%O:MseFni$aE\\N*\\@]>H/@T+h[li]cE\"#I>l)oB9'8IU3mEh`3\"7OE(&`7$8Sg'%5\\@&XfN=59sSe5c^'3cf#-]uEl;'KH5>HDt)^^e1!GXqI\\V;.43>#E^u=,@h!JMS9\"5\\lj%*\"&849UUuS)'u]UAt(6ens\\b#^Yi:83WX]i1uq&K`lS)AXA:r;ikc'pfq'pI<Tm)Yeg@huPAgklY$^n@?CXeXM\"4Gl6,s9L%>TI#]A\\SjCA(k9G(E^cQ@-A//<n;m7cGVC!q'Yg=S!:!O;Nt>+^b^Aq%d1UM@aaIP@>rBPtND4FB9+nTluSZPfu2\"/I?s3$thfRNM0/MCL$N.8L+FH=bIm3_V+R\\3*8mCW)E^-GkUNYFjPQ\"d6X0qW=aa=mPs2--es*`hPD%QPIcB.J^R`mLKrbIM>&/7Tc>+oCt.i8_,iMCNV'Z&J1p/]isEV\\a2riq!!0sAFHR<=l*tVW8gMd-)lq8e,=e\\mjnRf\"/j3,6!.trlL%/^\\oQ+6D7Q;7ca2me^9jFNU_($Ve1\\Y--6T\\om&()D<5NR.18ttQHAd@q0kfh'#mX>gWR]AtI=0a>Ap+F/>+^n,6nL[gdn;2jU`fM1m1Y&&b<RG86D15KPjt=t=CWM@l480d_J]8&CZ?!noJ&aQ28Si4;I:CM9j&]VroqC&^!UljQ\\pQHF\"Ptrd8h_eb[Zgd^B.gfZ1n?WuU%>W/<ooVW#j*KKe--?9o.%kJds7'eVIjR@o3CAK.P!>sC<$PEeojR[,4lO?:!4AKg]Us;B%28%[X&o6lZktCBj=6*jWHNlqMu!-DPIW'L]YPO7DmE8ZL8,B>I)G1b!#*MZnbAklcpl7G9ITSe&Pum5<S/de:dRQnB-,I.5S.A];uV!QAuT\"epQ\\$&tAkLqj5fRa`(GC*0XUQ]\",Ur_D>#MUg[j%oCVWT*;Z&g`.`;UL+`BVE\\-i^G1iTEN%E'f0lH\"aSqKlP+)6(=2^o55UT@KoP@2FS9sJ?d1.%[@Z,T^8\\ic+6ku>&pOriB*]=28-r;[r0/S\"#YWBLtW\"9oN;J7r\"bP;7?t8#8FTXa$E^;q43'WABPbV$L!B@q<q,kqoQ?CJ#faOR#'Fi@%EINuj3'7kgVYJ\"1oa0eb#J?DTFINq.3Pp%G.I0o(UsXOb)[CeO9+)q6*;Sg?fO1R22mZT[\"ANp<_;M'.-'?F9Zaf_2s-K,+;:CL.Zb>,o,.Gkp\"!peoY!\\U-q&@$4bN\\olKU(3JXjbUsf'b'9_YrE#53i/J/%%l4>?fh:&R`!Q7'+FYW^r/1+cgp<;EOO\\5<+FAraOFsku(6/4\\1#*+8rt&,0OYq,fc\\e>)Mnh/.`6iADI?l\\0BjMu'kmRNZ:VE/LTq(LCO,!?jR(MnKF=4s::Vb[=(@\\.mO(((TED(PuOH$Bp?-#A`EOE-KXTXBgd=p<egJ!=lqtP7*S7]#'[^>NB0\\q2:Fq\\m4m97\"NK1/KT%E(89onNO)*bQk-)=et?g#*p0V_*gq8@]a&[EcEMX]RWB'acEBY$c!;:Kjgt,!0Eg5\\]I*$C\"tU.eC2p$\"ZS48nX`XS7Oo_#:\"8D@+*>rXl3c5K-_F\\Zq#dp)]%[l#K&OIae+*U7CP\\oCH<[p7QYVRa2?GiO@\"llQ$C&0RAaWi'n:GJ:?(X4@;=qLPT9f>:2i.J!lFVK4.s_/Bb\\NZ1pRTgq1dpQG<01oC[A/pcmtD4!I?8A,=_[)Wq:Jrj:_*AYS=?*gCY\"p5r*Hdr$&e>GfND%geoY>3ns^!Z+iBrL<H\\HcH2gf6N7$LD3tmG>ZDPl%XjDScW-u5m^2B]]AoHdM7;'Bro@1Qps`521cTm'hA%I6IMmAI0HMUR:QsEm8f=JDFd0rf1$bEh]V:&q&KuQW.o\"BLM)GQ,%6QMI&Ei#M!9+!7#V2@-$DdafZ]GbPp`TD4$@C7aaKkD\"n9b.l'=;7QP\\\"Tu(,_8qqTpF#;.E2a;:?lRd=`^+Gl_GWDT\\FT1tpmoMYq#`$<:MA$@AHRHUJeK?ZVh#4nkZcNj0hIDR**[]_<uGqn18G'b*`f>H[$bFBopC#dbUL85ko*Z\\5m/YrMI>\\ASER#oGfIo,FdF50)$T*(RIY+:e9%`]0,:BiOrk28Z(r,qWk5S.!<S?=FYKpsM5r`Gb8SD:0pI%RaC6X1@?`\\CER?Y8J*Zq60Hm&eB?=,*=D;$/qOE*As>.&KIic1>spE/OEM\\N)<0G&p)bC\"GH$=\\B!a\\M5+)E6hl+>0g<TnI3_1m]WaKH>_d3>I\\&mYLC$[-G@gk)NVfli2$@H:ZBjR\\XF_?c#!<2)P!FSiM7Y=?n^=W*^^ZaKKD\\\"^6_X]s\"nQp?e0R\",B-(fH53eeFiDg'7QQ*oH-Jj%:r';]lJ^l$bh==I5E8@=t>85+tDb4l6Up8!jM[(PNe[4/\\#N8U<Vj4H*%d:K<_eWj0$UrUY#6+.XhKhoZ7tKLGo<95>A'(%hTeI$AF/LO]QXF,VST$eB;\\MAWU87M`Mf1PhTWc(M(#nT:1JY(V3T(%T[^0_3[478j!J),;qRjSDTj.79*JiNs!?NI>WNK,q:_%PX;JX%2ecPn\"V?@h^@DGYul,5kTTL@R6J=PRdVIi,mn1u'E[>=7Tk(33VDFMlD%<\"C%frqr5SFu\\D])@)HWAoQC/QkfQO[SC[T&Qo+m7IX\\@(r0_@Mt!f!sX,[$9ZXo4i7KmFChE]\\4FSb4'BIP/TjT*$5^s!)LJh\\Hgm6;]KMQ@oAn+[7L&#\\=#U[pRJKK)Q9t>XVm-;rFY)sq;%oAs'0aVfF#7]E.*r6Q#&a*Jd`jO>9)(SI-i97pk?KpqaA\\HoJ#*BT]jR^:^)M5qh@'Fu;^P-#nfYCo)@mqT^'/W'ROUP29bq68ILg:PQN=s-P.gNR>1QWQFiK?Z3\\I5,#g>ZP[HiU[e_t.;1&c<I`<Hf<ILPgoWd3=\"p_e)eSo=RWqenLB`(ZBO2T^,#nuPB9XM)L1+\"N1aYlTB*.`Gi-cR.\\r9Y.^K`^$/,bMJe9)F#6W)R[4W@g8JLf(#TW=%Bu7mnC0&/VS8;K\\uO:R.6\\rN#m]Qh+>`C9qcU0'+K;(O.5R6I7hreNq;5;TYud:_4KdcEihph<N?GdZZ01,coLGU4PC.Tc\\Y+C\\K'\"!#4G)?.[U!l+qscs\"`U#SFKE]s:8Va1U4ChlA4*\"]Nu'Zcdu7#F?_5`E(J\\E2QeYg1K(A=p+X/<tCU]\"QH#:hg/<K_\"q-V:jFsgE;,qMLf4Oq14Qg*S2G5,\"HWTEe(hiqYEJAL+rZt-eZ31&m^4V+Bs9'uM1aL'SjHPj'8%K[Zf44aS,A1:'&rdQ<#M=QYUKJ+BS+;)$o%*M=sD``Q;5omB.%+hq8EQRV+A`=ph57I0^prGS$Uu^efNlf>/kmmZ37E`5O3I9e>2h)]m#r#k$ST\\+>Ou&iY6\\1tmjf5[tblJm_R>*D9k#,E'pd-%KcSV<r\"M=,![,e#e#qD)Q'gt9//)NtkKah%e\\(MRC17).M`k*^cZl+(C1sdF05ke9mi?ZT5OH5H;USbS4+7sEBdnI8P5o*@&[9j.,OW*nHL-7Voj)P#K5e,fbClIQ)KLmXVhI&UL:_hbJS%@Q`J&qbH$R;j51q$Hc^fdJ5KC5u*!R(f\")#5t%@>eHB0^kEe.o,U%2%5_cQ<I?>O-As;ZigWrX`G[H&Y49Zl_2*gEdVa$^#sUmO3&5q^C''h\"20I!HfRU*HM:eo5qAPIKWGZrb9nZa,U]_3od&374q1fhD+j5^kh[]pelD%LmRl@2XQmEaGM,M2`I'Q9'F^=hgJ+64momsuBAJGCcNaKkEBd0-DpZ2G(dc3Uk=0q#Pn@X:*@%=j_SHIhfN<o5@,_nHC6CKqSMb5[\\U'URZ^@YEdmX$\\X/:JPO_U1149pa\\8[7M@rt!DTU%u^VBesYVLCZBY6JlZcP(l\\T<&,B4a064mUW:dk\\$T7pT9W9QhD=`,\"lf81#bA2'_.?<q%/$pD1f@1IebO;jZ^(5GNiS#]d$6Z$5P\\.,BWo>^(^W>k`>,ht4V;X?`1[1,`P2JLU@B2!XPjb1I&c`1hgf==CNW=g+JW:SMs(?FchEo0:981TPiJgW8@qW+l6SAaMicbckZXL=X`4@5i^UHQE)hto;mJE8RD\\<RAA\"@'r\"5;(^7\\RXWsqhL/tZ50S%2R9f;8GF*2mj^]c=eWL3^8+2-POJ,_b'$0mtCjq.TK.`[fbP\\#/E?Y$k.-<\"^>D7,%pBEn?m%l/-a_*U?qUboGF0FGCHJ0i\"Z\\*<mIM64Mo!5>dmD-iLGCCr3^CKnK:3kMq;Yb>X@heC&:]G9phY]>PhNpT1mqU\"L6pZJPBc3*;>$d[L#:*kV[Cad%o^[,mlnZ6oXBK1LXJ/jR:d=Q\"=c5Nf^44]I)U8\"t&K\\1;;(%*XMq=2O<AV0YC]<+:+p9Zs+ud/+H8RCbe5j-o\"+RXlaZqG#Ij_@'1$174(KB=Bedb?g*2L.&8J]ErW7&d/qKUoAU'Wlc\"!oteMpZBn#?j,E<Oe-OOfm-:&V0/49*4D5R.B)(/fN6XbpnIK525G7qL]`<8qC$@9.q8nO?n(=TEWFr$%fD[RI%O+X%glsggJYs/49KqON1<9G:E8>5D8BV<5<Fm9hjIqFi$bm*H1M5N)\\6js5d*JE%?c>[o6[s00lGp,K@fDmjCn:dpTiGSUW6u\\4q1Mj52'f\":*W/5S^[hg>0clLZ+7<-2g-.C/cG*^WXX\\$c^.DpTo^+k3\"X?o\\ktBFig=%MebDD7U\\`V041!Zoj;9@]iZEWE\\hIoW(Qtpa)c\\Bj274P8plEFf!_hn9s*K>BP8%.\\>kYlPFkrSB/pVM1_^Lo1@:P?u]&`HsY$[>4b$o=DlJ_Q]L/V2S#N6P77[ZcU>]`Q^$\"R,[*P.V<OA\\C#,aU_+'pOKVXol@`T3sY+!7@B`]rN;$ua'.r&OlGctEQWKB'k=^WQXOO(N#m/>C+5mAMl_ieODWpLCRPXcZ.([9'j*I35O:Rj_f[L-]eA/08C%FRA-C+=#S61]+!DTP^L6t.(W<#6/k4\\W.\"@>m8'HlhISQH]ASeDLIrM*gOM(KrFmQ7AY)>V!!IXJjp[$3W10O1lIEE9s&&]u-48E\\5g2_kqipcHh,`o?apDd\\Iq9T$'6I59a`-O6RKqpNE2Mh8O7oqdN705OB0m:B5\\!LE)m`s<`:\"IbF#%hR'qbDSBap5,46W^ep5Y,e1?pi*;=aohdpttV[6ah1^XqK&pG\"/*n/B10!A*?5o4-gofO/_?LF\\2N>9SZkjc*YCV.QL@^7:n0#=PAf)epG&FNoY_V#'.#T\\:o`&R@:Urjd1;q!@G?=el]YrI'gK1/\"WUTT1PS\"(U=]O&][o56.0]A`G!.uV!C0N(mb5t;GqN2qNPc+H2jl(T7I/7;<r2Ol#+W5Q%3a@(F7inSH30eVJh`QS6@B6^%Km\\=Hqg-<pjdh-s>0:d7dTJ4aqo]0i]0$,*1YeIW\\/4X\"aUDD0c,4TD2<Oc)*up(_*%:hrrVu&5b)5bc8>P-^7\"F#m4VAM0qNl5YCmbPq#W\\Dfj2YXa!pLRg2'$>tOp5ZTO/^$uUk%O7H<B44c?'Ikdj`l,mfb_-iXhCnd#-\"OVC-Ck)O[r\\QaNou2GsE'o%0Vt?!RVmgt%[NG8ZX+V/P,Z>+\\dPLJia-;a.Ei1I/'23^?*cWrS$9=Z=MqWkM._kRL:Tptn2cu_$*jDS5M4Yjs?@OJ8j.gaqW`f8)<l&S$XFf8`m&e2rWYIXS-WA8lLXXe/[Ab8Qh%b\";!7N$Q8r.Xpb=fc=3k0'ch>qjjgCEOTDM;JaebD%++<RslJ\"]_NS$dSe'9o8&s4C\\T?PrqJ=e/HNGrHgnFTLW@:!%L7fKNIS$7WWGnaW:8)Po;KPR3/e4Rgd(0pj7<5T:8Ic7e#+kL[4%(A]D:b>Cs,T<4<D<W!?@!HV+!]t#emA7*M9mA=.*YKEb!rtA=)H.lLMARC^L,t7mQ\"\"(mVf*?b>pLT\"J2mS0%dSF.U68n/D^^W1>';]6nYOJ\\D771Z$@/]d(o.lGam*q:h9q59rlS$3^3VHk['k9bMN;$4D_H&_F@:gmC]a-%sAe<88^R\"lW-92fqA6qNY_?b6c#a%W4qR%)IFSs4)B*!dfl:;$^;3Eps1L:s_V>MVsEBt[fP(/k]/mmZm%p;l6gY(7F?LWoPZ>t,JH5E$YUuF^tlZ*M)o%6N=Xa@3MfRh4?KCuhaIG&\\7R=fEVnaXP.0?.AN&nDJ/btJ)j)c8nQTUGEW`M0SDOciW8'g27qf(-B[*c_2A[m1TN]GiORV\"N(&HX'^W!Or59qP.O43AtYj)T]_F4(o]VGI/0>\".XMqX*a1950&#PA07`ba8(WK.63`+m6S'hla0ud1`538?`/`6+N5GI-DQFsWf:oQ_/KeZSQsQ:bp6)M]ZKG\"oHS.:g.OgFia`^qE\")S^D$j^>[*+R'*-Imb:G9bR.c2Zo!tX:mN!Wg)Tuq,A6;$7P-5)5+H6b3@h==mSeU*'*Up0(\"@lbE>Eb`8JM0T^0=AZTQ=^g`5\\`g]mc8>LsPT!mX)0q<G$ondP0A+'-&q^9.?bVu>>6[u]mbfJ7P*NGP(!Bkk/]b!GL<=m96AH:eJp!=7P<`Z4CWNn'AE$Ws5r;0\"MXH^BlM#B#`inTR5Q,rViqH>j%EH.ORYE/oBR!>Betf''.,ZDCi4`ht:Pslh'*&-?M]LHp>5_01q]B0S*NUWXr8q0Zj<#Q.YItPr#*YKRm[O8BhVXZoI]`/X&\\`oIf4&>@g5_NE-fkjaA[Ff0-r56=.H?5V:=q^nR/Y1W\\K]_X=RmRlXZR=eK:Qe$,:c$,cTMl6L&ui0ePK*]=\"0l^&&b*0\"U\"*_atLeck\\7,m\\6Vr3>pHEf88*%!H<3T:M4NJe]^m\"A-/N7CUs]!gDJq!Ni3H%H]Q&jD\\,@T'\\8prackGoHQeUS?&)\\g?MAn\\W88^&fCC0\\qemh)CKg35,N`5S)$<_9q+.(;o##R$-8aGn.\"bBNFZs*N?!bNF5Y_#me\"5iFY-e!N!1[Pm:aL=dC\"1cIjM(^/^Rat5G!B?cIWA<t#o8c(JlJ(88UHue#Y'b3>bqpo<E`;R)f;Jm$gDV<B'D$$.7FWdY&>q$<%(7H5DYAX+$jXIds6NC[_r%ijDd64!@bda+'$VefU$D/D)Y4_A_hn'NnFe/8,W2QHa+-;Go>,pW_IqMX92#iuDQ;e6+d)]RO78*cZ;pX?c\\Cj?$r4N(X'`&WML4+j6%LEVNK-;lJ=5VolJa2eF>q1\"Y&poZisak/[#P/<U81WIg*;M)],n6/n(f:,^Oh\"1be2U^,9E;knGksF>W'`tH-L$TXnle<YFf-E4*)VKP?aV.86VaNr602phD$]'']QW;-m`9\\\\(8BOEkV<2[0X6[-tX@@djc@/aY7;^HQYFVDL63aaS.*t'\\;H;4$BOq&1n.#e!<BZ]$pG<LMZ02R#oVt#E(WN(%B\\fHbnpaWJnGo29qM0Vmms)4.iE8p-m:_G:bh<oL^LuKP_-C<SVoLos@^8P)+/64;_I!gE!7VlW)jj6p5.?kTl4&S+js[6pf?LMT0mZdLFPX5+b_9BYG9V^e0R\".\\<SQJ4[fMV!m(9<0sbI,P#X%1;d1$@t.#R1:_AMWY'Ks<TE`EA4tWi4o\"FpH\"/gI2TlsXHe[hF7sgsn0h.P>1mmhS?)8HF_1I5N->G+qqbUV!4K7pi>0O'h7a4q!hh2KU;kaZeoY]aS'=P#Z'NN;Fr/\"ln0Fs&Z7D@XA'`-2+&4P]<gJ9ZP^8;PgWiYBF`H,p.EaLej\\D\\!YcGOk!mT4SL0G]fMBb7Zk)j>j$^io>FbH.#*N.<:IH#Vgie.Lp#Oglg`RekU&*7>]0/rk[#@5i4q(6E#hlBG=YTGD\\mQ.Wcho!s2A4unh$`PQj(IK^-n4HJi&b@980=MO9b5m%(I^neb6r)?tUUQd<XT::LNDlH426tMnC)^cpfl7(EXR@9eO&G.%8MG79uDtp<b%GFL.($ZNTXb\":k\\k%mIp2k4NLR-+#.i\\EE7W-FsZ8oaH^+GJ`!2_u6'9r0+3]f?SAWF`9+I9_gcaXs=B\\e8K]C+bPhcf,I4)Dk=/gfN8H/+6lal/+*<JjLC$8\"5^i=/0+N.[HqbldRV>_REQ(uqH,gaAQJIDe,+8gh$j6J8t,qG5Z-ZT11Z46(q/E%rI-1Zj;lT?!qGk\\4L4S,nnD[kCLqOP&kc>sl=U=D2FHG%h*s<A:nn1\\d_7&L=G$W]D??S1ac)*fnhRjVB6nE:fAUQ$gpF.V_-VP\\TqD9k5p(cRBW@Q^A3^q1YB'CWUEBPJUI`Jc,WL0>3&YnjhSb$BVn;+[k[J&rFUQA$9B@3A1i96;hVjlSYRP5];'[rQ(Su/k*eE-51(2Nh30I8%%91/Fn)+aFJpcT/6/NSBfJ;,?9AtJNkp#)WK?'LNi(J[N<](crDol5]\\3Vo6t`$-sk7M(TW;_Vpm`lm,JP_MG]0#Us;@>]!7GUmrJPYa;de%0MZ);^7m>8@Pr^/$l,#d\"7PU$R%sqt[OD[V9TF)@.W0pN\"5cH5cMW3,q]LaVUI\\e*#S/nje>ahr3#*rK`8ot_[)GdSW3,SEC\"LJcq)LIeY</UtD-ag3_\\]c]]\"i!IGEi+HnTQ/WM<H-4i[b#jpFYV):b%g3)[B.75738c=]]nG8jFmY_)cF<`8KHp=d.1J\\Tg2_g2DZq>PhA_=4@[%flC24fl?,KS`1TIniu`&kI,Y(;_oK_5>JN9-T=Ub93Qr[!?,X4.i1e2Bng!$m6BReQlcFCTO:5<^Ol-]AiTV,s&Fi3<+8*g/c(Mnmsso7BYd5@lkXcH\\j)phpuPJ*P&2;n_n#Wg);!0WY(;F.!Q)ZhXfY%k/baGRdX6L\\Q<0Z[47Tag&D*Q4#<kpJ1sI$EgDe\\?O=0J\\\"JUD'Y1eEiV(lRdNO`%.JMX,&b-66#H8ITM[sbDL2%L#@$C90\\)p#_#jRl-u;VN[EJ(p*%lK+WdN*o<)^o;e!jb?W.*-\\D[>%(Ercd_Bep-(MP#JA2`M:,K::im-6oDCq6is>6GD,**g0jV/>Cg(+e6hfH*AS=+h.bhBpl]uiqaajO0=g\\d3\"32>cHSUgbR&3>>7@AfAR`;K)5r@ofQX\\0:XiV:JroMUQ\\7%Ji#ZRE;&.e31&'ED>Yu!LuaB[L`RH?!G3]SVdJX%7$r8R28,\\OiH(jHjV0L;BOTOt:$(q8pW,gH3-8oLcsZs:>3Ia@]tW,t_kQ!oirdl5I.<:%Wr.F23-c`piHVGJ=oTiQc\\AaiKa@AC^bgH,;I%X)Z-'`E&)S!^ZUVWW@^?32j5YO]@6+Q2ZDg6h4B=![IHh2Ui1(j)c$_:^tgk#1Eg;6\\ZCM-8o>SP:.8Emnte=S'%O[F:,@\"1I2MVC@:R=+n>QlF),.n.E#YB>]]:<Eb6i;Ol-i)!>,fp1Ir#'B$u'pqnG0&X)#%b,H,`)[dl:[m+V.g,%l)&\"pY9\"=HKhWFd*sh<E*N[Mj0R;b=S0U;[+&-HSh?itfNVb*QLgPF8+-`F9,M8QOp!l;nFs&)R#c$g5fr#0Xg5AC0dmQ<K\\a1;1Z>kcJ(P3L=>ZC,BVnk&=;\\pUbM==^hC).@60_mUKb*I;\"s7pqgj?6K(%D;c[&!R%:>\"$OP7@F*mU.'b,Pt>:tCYM<7T'(?#^$f94`[Z?Qb0q^tqmI6#S]2L_Z;rQkMj$k^E(%\\=Wbn0Y.)@elu(-:jdEiIP<q:)Mk'PsBQG&9es,[ZiDT?qXE5;;J43BUV)7*I>R]Nb'g$6e)f[kKgU(]TAr)&7Z\"gb2=dp;n*q;\\bALXbZ3rCP;t#i0_GW/_S/%-m#(c&its3OR^^$1s8S5g+U69![&)SJWR^*%[3?g]0KEQJ\"q'J.7Am0eCMVi0!XM<^q6.8ej,ACUO\\c>`?Sb<?/-\"LkC71ZK=9i&q\"qh0fs%le3^/\\skr+4TNYHnW9C&4\\?A03/]M>qQi<?:PqI!Dr*g6]N_8OQ<o1JL?a-0<Xm,=9mTK5dQbS2o7dc-,;K2(Lf*[BhL-BG>VTl%?4_J=eD5!.'a1ZLj.<\\\\uN@m5+M+68sF-?+8-5G=<65096>\\\\lB_+n;.7DV.52dNc4B0YqCYS/Qm$GQT@>D4?4:V%AV%nBaN-ZN'*:SG?(q49GL?^rq.9-TeieH^k;geB,:n@ae52h-\\uSaK6mnac#)s!LOq-LA`K!7#O)Y3e&A,W^[KNj%dn?WhSQd7^6\"H=XaM9FW('?'Wt=q3GmD3fYV*U[n-Fo\\LLNpf705Hk#D,BR'P`lMOWDcL;P8(paTScQ?9gfjVA5JZ_>Lccm'S/mot/LOj;l0WUO5)Fms_Q;]d5E\\&cn)@dH0UbUt\"QlPLU@1#roN!45uK<KQ$JA`surJW#a\\jW%csIq$aqM5WH$XAC,.g<0/kP3iS)N6?aatpGZ#&\"n1P=AFu[4D-\"RpED0RSfe8!Igd0$hl:D_IE`$qR2FAK!Fk](ff7>,jG-WPTkQ.Ki\\&EaM]1sV?Gjk4-W-h>&:0g2+apU?6A'C!YmGe.s.#c0j`a&uIcY^3L512ip6g%gEf+F*-13(g[!@r\\Z](E)DnT-40:N9]<n*j]l<W8h#g9;%X[Ai9\\Bo2T7]\";>)gXVHS:;UZef,8+*9?n7JRSU6Igt%8.J5=GVKks_km=G&X*TD7Y?XE>BeJUg`/AX/gW1^ZTC[q-U+sQbJ&MO1Z^UQEHeZK96h\\;<IXO*!_kG%6@Zo#Rko:<MNRD?b$:'[WB1<?ol]1/YHXk_@/G_LM<;!9Oe4GL7!Yc_1ETFH7^a=poEk;/V&>a-qZ8AqX2JB;Us`tUt&^PC:6)71mWEFMOFq;*0].kgm;U;eHu4_m2C3Z=kaS(4aJ;%m#g_YL,KpWUJi)DD!nI@a5GQ3q#OF&T`>hODeWocjS?gd?e'RE335UCqN:2%*%XqO(VH&6[=qJt>+oJ'B%.)CFVjJu&M/<NIkiRX&UBAJo,BnSp2L[.98s-ZP0Y2:Z9pVm)(5]gf_r839cE>)=WsnkVJGA+6n'e$)W<N!g\"3GP.(b+VUclFkRbU8m.fI6-g`2(s@LppP5LC0W/Aj+Q?5NIW(F6J8+q;9V.9FRT7dLH)d6^cH5KHX(/46S;]Ka2tlIb6(tnD+#U.?etTsg.I^ORA$5c$f#9NQbA9dbK!H)>n@QY[;9*)%hD8e&1m:h&80j,1W\\RrPhAYua0l$Ph2U\\aV+<lQ@8!3jZ6G>[>&8R>2o'=TqdgsSH'pCFb(PmBth1B/\"?LT6%f&o)`gf/RT>Vq$5::1>T\"=`c5Zn[okCoI,Y-`Y?C_AkG-m8@M\\*VNKdZ,:7&-9Zl9rc6T4^[XI$-p94D8hBR61G^uX8/um5^CUULffGAsZU$]6Zt-UD^2*DA,XeI%`RVR1ako_A_(d@j_Kj*/`:#k:-9jDq.(<bob?^>*nh35SFDW$WY7[Vu1<?:&eV+U`]$Yi7dE>2D^;1mOZL!L^X@t*-#Lgf%O?QHiA:q&V3:E(8Hn#$3K9kf5^$QAK:QM_c3==qEp84e-iHDht**dr-\\+3bb1KN9L.454QYb@B.O.JOG.$G_%lP0a#R0C\"MASk$%'`9E!FFFYeT<JgH8!$F#&+*Z]+nl5pG'l\\^,?Wh5Y;Or>$<p<@CVoYV*Ph:tP>jOP[oZ(?CBj&/7gBUQbD4aXgQ.U#<RIW\"2)l)jPNON1JfF%ai`\"t47R#KoR?k&r58Tti3TY7aaDr967OHPLIUsQjg]K`K6sKY$bH!Uj-9d@]Ka'f*53WNX\"hlQDQT^Q#;.lNmVD;UO6_ek,6mi#okJD_N9rNKW=:'];qnUbbM%Y2BM^cLLKa\\G'7LI//_JZr)]_3c(kij*pgYXljc5@n+3Yt!EXi#c'5g,'3?0EAEkU8G!8##S<RnfZb$M$d\\F4+cb'tWkIH)[me]Q[aX5k&3Q4i[^!?jlbPkDl8pK6kL5_5.XW9:@Vq.p2sD!P=]%VlMS)V\\mJJB)1G7&3*fgnlLdq]$tkBaSi[Ip/d2A==fAVl;0],TFXFLZ>uPD[b_?S\\.O@,huVZ5%a0t[d^!tD^fnX,Jd$L;/Eb/JeK+H?]IOEK]_BVT`n!+SmOD:H>H[V['%IukUYPDs8s&`:4Nr%M6k&4[Mr6sX/>Mck=Yknf1!1fT-DNjUW&lctJVTI?fS?nWW:8*B*CD5_!jcJ[T;CEiiGe/%kB[%l$_(>9(BK^#jD.[^s3r[Xm1$D%_JTo13UPV^@Y^f.I4RMY0>NpU9qK%lm&9m'>.NQ028,;,S[q0p'WrfD5b4q%]=8otZ<u2`orVIUA>KO4J[t<m_=?&H8Kb@><!I-[p;J(qok@-lgVJHrhk^`ZPWNSU)Hb+59HO&5DrTQm]I=pHP?C*aPc*s;c?!FX`e_%oPo<<@;AU%.-\"a5^1D*t=Zn>Q$MUUS($@C#I%pntR%m+.(L<OGB6U4gVe6^?iAX\"1K5#`Bk`)afQr>tshgrBmi0e8<>C!X%NAqQ3ZN]FV=)^VaGa_jZB<+Mf<Lm33d!SoCE)R=t+GkokZfI\\Xm80DRPXVshsd5B3T9Wb[n_BY,+/RT_Z'L+BWcuoMY3)rF7HXcXtH5]s#:rlHaPOpPn@Vehc8%dgQe4:Wh!/Q;EG9T_N_&9T1W04V$I[)8($YIu0L^NcajE#G)fl\\\\q4h)J(N=tu&mL/cj'G\"UL*P6H#\"E0fJpE=:j'h#Zj)gSkZde-1,jN<q-A^<hRRhW4S\"eWT/C;V%[+>VsC3!u\"O#-[)1M36hgU>R3bU`PdW0[bq8h_=n0a:u,d$lfBphT.JNf!$srg0[Noirbj&+j8'0D+i=OF7o-^8^:$ZquB?CTH&OaV[94/[BOI7M?H0VS9e[9pKrm0*ZDjJ%A;0h;5T+Gj7KB4`^+_j%V*R)T'460K-/QLF\"JQTHcd9V^B)mN-fge+[RR(d=`,?pg;b:do)5QY+un*N!jcj;?,:Qc)>+ijii*3lpY+'sFK0h]gB[5TZ]_+gO]PY=^X76@\"i]8e@UQr(*b3,2Y@/du$/j&J)/;I:c))<Z3!Os6<6K>Imr)nR2:@`hRl^J\\QV2:'%VZ2&_8lI;-\\]6E3a0k0Qo0.Skd\\RNOtQa!Cr&OA4eoT,WdGZmXd7)dN)mCBbT[XZ-N-PTX\\U0p!tcK+kW$+:XNb<3b9kX1Lg*&l<qX_Lbt,E[N0Z\"5%Ui(rpcS;-Sr8+IVa)[c>%PL;WtO+DU4JJ/2Eh/L8\\B1J_SRLQ,?ee:+j#sm-CqDR?$Vg4)M!'[^\"`Y`O2Kt,bIWZD\\P)&j4!IooD\"rc2Qa)o^?B[X=hu,pkEV4G)RTV).S`_=_B3;Bsb3d*7I8mki-8MuX3TYCTf>OelY><=,+=<M[QX$aBLSW+[=*Qk^UB>OjWnCE:h^b1Mi<&d'/B;.c78LK*enscH0@=Abm:Y6`Jdd=!6PgC0R*)UZme\"H$86$oS%/ZVYPL'Y#X1#nTcA[DR\\t1rI83cTj*V7si!NH]C_d?-#W,a=P;p?+bh6E)T=!4s,CTQ4M:fk$>+o1_`s3GMF.1.b$E2U$nMimpA:?(sm>ApsI2X48:[RYHgmqh5ljVgROCt<djaSD'*.OR<E4k#,^=.oafH4t-E0DhqMLK64/Sb4F^<m]&H%:3\\<d!;`m.*r0%>C@3Tk[t*sZ(1A$Wu\\gM>:E26[h@DGAGq7tDhHMsINsgQiE2WV#IF:?4Kg.\"bK5VUD/n7e\\X\\Q1n=)c0FsBRiCs+K/743lVNTRQpko;$P.$!jg#P*uFMCl`S)N]=7f/FF?U:K>d>omZqPMYiPL'&DNA_1.dLoZlSc4ACeqYGj'<`f[BEjTOCNP];A+<_S\\MD@GsG>ZnbFCAb]GLT\\#iBre@oduuWj)bjV\"ETOi.(j=\"'=OgrL:>e_^EDeU@#_t.'`mgGn`bWNp1+W%Qh!D9eREbkWfUEt[XFCBg0.Nf>'S\\\"H%jIY+ulXS(+j6DqQH&<lc)?cjYm1E=,;`*J4(i>kmG4]\"+ql^Ed#$\"?55b5YS8f#e1=Drb@Mj*Z[e1cL#ma8g`^bcZ1+4<X_;]%KW\\>n9GQOs^08<-Gk_*Y4g'rTjqfd*Dq<$KApBf@9M@,i@88d]HQK*u]aqRPHYr!?q7ZD`q.)&t,Ff^<_+*5&9c]2QiQtFKB<@/J1:VA/E.\\Ts<_.AK*-AuDp.XYDIHga:DTkJPVC%`J!JPhr*VahRQKl1=6\\p!]gq-&25?kgZ);5^52n9DE=H=LoU97pCSLA419[fdBWZpsqp;FUP'$aTiO8M`(.LV'snk5okc/.Y$Gfpn0'8KT`##@jkB`92t<oV]Rn+J:sJ5`GT-P9t$,<rYYbp1fNG-s-0M5iKrd?H(!9a%:B,AI!/_QRlg(f1qQ]b(Z^#@1QSF4L(j7O6Qd5#EUrDkg+cCS>K)YM>k(^&OAWri2!DTm^Thre_lf4db[FQ])CV\"G1hArs;\\PY6KG,OWFA(\\ne>-jaT#Qr'gH[QCWebD8mh/L/4?GjL^Roh8%uDrjR\"f11@^6(U&d\\@_d4<miVqh@91dV_HMQS+3%u0I.o-!bQ2s]pE]LN+faM2I\\1=sroGt.GRE&V2,]fJmR-'Og@S6T^lt,?bE4aaiSaAn)9s`:':X;=FnR\"N@F0'$gda@tKS:JF(PA]tgZt-+AXFWL?4!UtK90Y\"Qg\"5+Xs%dYf4D0IT?5uYhQhiSk4=,JW9IB&Mrfd^dLK]O8]9P7c7<WjYm9'h4<C_9K)nOV9>h[j0NrW4J!0f,<T/kEnj6LhX<4Ug#?/rAQ_;B.^e33cn_s23^\\=5erfQe3oBYAup1n/b6'ooAR=c%hDnkj^5itLP=M]fBki;ekGV8jd:@%UMSQ0n<5D_ASJ^SUbrpP!\\m!dHi;8S^enE!gl/6+7\\5m5AkrXZ=ISRIF</0/1o%a!$el%6lS%ZcQr7NO;AW62hj?M$:Vqnc6h<5a.f>Xlb;`4#eUS;FA4O:.'9fd:cd(OUBKrf$Y`&TF$$^oq1.R8:\\Rh*(/feXjItE+?u>$0-%OQ/]]:^lIh@<bUOE4ja:R.^?]S9\"C#-YU<cU`3Y,s\"V>[89IO%F(OUZCF%,X3j;02@GEl5?=me<j`^L00>cW4jMX>+%p?:R(aa%oTHkpb,;D.9);`33pH1-@\">MP\"V%8a3B%P%O@;l&p4aF3,$FP)ID]SO2mSTI6N?>g';EcI1V)?>J@Q)`)0(OA\\\"HMH-KbcZ6Y^3&*'S;r_ND8pEKrQH@<>A$ZoAT:[`rd6?V%F`8nRkF5L+#K>#OS4OA8-:k^a=N>nYPFDWHk6rh6jhWWh4FrW!5??Ki6\"sjG\\VdU^#dAgh.24j])\"3\\]H^?)T:AuO9o+Z'pPV?+N<\\mrPB0KXOlh!`'dM^ljaM7ak%f,R*Eo\\i<g?$MA%nrpJ#KGq/GW\"\"($B2l$TW]]7^m%'o=8%q$\\\\\\Ml6[e#\"N1biX)e>2,>,>ZMqhGR:O\\Ih_C9!0!\"u=53g1TGdNb0_E,ASC!!6[Nd.m-].K2]q3ZQ;iF%M:HgO)<7Pb9Y(KYS\"_:R^@8;\\fO0[c4Lq\"+\\$:)au$s+5b1g]!V8b[&!%`2Da\\3Bf]f5$YIJ2no3jrkGV>63\"K!m<55_S(\\?h.?2L048,ANrFWoArQpYT7]Q@1^8)3?`Y](l\\5V9>%\\J:6M=JoMuMX1=6oM^5lNgi,61SQ?NL6*?O#9Qtc8cYU3?[&I>)F!bu`HOMe4bk2iZF)i@BatoH'@VR4W<BY-/5`i.Xg,.&IlI=D8')p#a>D%&Ao3WfS09^(h6Hp%L0@WJrpNC6]C4MN8PRC5/r3_P$u8Y'Y6sYa\\!p-Z2%@(82E4j75lh\\(6fi.HUSXEe:cugof*^j!:!\\j`A8@BrRp7Ne`)-<KU#5-?*,+\"*:H2XoHLY<+e)1.]Xd.rSj7U961bq*mciCqlA:3:$-Ars:Gcq<([cY5dq\"RN-E\"agB9)\"\"e1O&\"IO'J$5r/mfcj:2VT9CrN_EPZ2)!t?k+\"VZZ]!K\\?i06dn*_,lT5078E';[gI%N9PLbi&e#:e-7tG8gmqZI:RHH3BSt:)*:[58kLCfRJTaH#ZT%(NESg=<I!Xs%k\\47@V.OY:LtjnY0(%:/]11K`P??Y#fM;*P:pk0h&PPtLa:NGlUCWRi]p1,'p1].)i)=3%5-*CpqCI7Sd,BBeWnr)?O\\/f(B=%1i=T@!SW=/Dk.$]8l4D>@grmlE3W:34r$#AST%8\"5$f^/embo>p%@T*#@:-1THb>2>+:^=(k.\\V;:N_H^#F5:JM;4lmf'1g^WuG@T'1mHF!J-jgJIG>g2[_h=?/lZ*JHI@#kf`pod_Kaa^`XsPUPlV(<V;5QBuZ6&.KIG9VWN25TQh.\\OY9GYI+se&GgbYGS=j;gXWb.cJo`SAhgT)8?WX<`HX\"o.O=Z3sjD-O,6Cn5g\"`i(g)':#TmVpRIJ%*RNiILSba]m5:WUFP\\rH\\6,jV%636U1q+Y@UEtpFU/8Q!3E!WPEL+X?YC?N78qq5P=*g^>.8OTuL(c09m8/K(aaReuiobN]#JCE0=7$i[T%h3g<l<6]=<:Gs5q$QifI8NpBQ>M/Q$g^CuXgJu:PLn%Bok(BXY/>r8k9,l#'g]Y8\"-DH]V^OkONm`;ZZ$rPrnun;>>/:P[f3.-\\#m2OGCqre6m&:IM-*dYU<`W&9CtX$+11X:N:c)`^GMIj)JkEVga/Q2B_7aYcgLJ@H2_`g'5q-<\\GlZ\\Zl<$-(r,rC!e*UKb`e%LYK87B.k?=E-u(Y8obN21Tc7)hnr]Bg_%&TbK(u\\=l691:cDuda+iL6hKNDa)>OTE6_*\"rSL`?6d0-\"m:l#m>:2Yf87`l2mI_r(l?AHqX8Xhd`TA;KNiDD@m%4LVU=Uft:`U(6aOQUmn51=c\"8W!(6_.Do>Q.e*W(nN9e,ls\\`'.NWVJfEK12o3?&,M8Y0Q:P\"gQd@ViA_^^iokkNc):\",dTFa!CJU?l-=o=g$M9idTmel)8.XPoElhEWR0XtB\"^Nq2K]0S,Qf^Alog#m3[))&k-gEfs2Y'EQ1-r]5d'q=>;l.,A:IOn#qs(@`[:XU$%)67VGVo`K'F.K)DFLLai#A>\\>EeU^`qU.%42WWl_fQ\"SIl9cGXFFO\"nW>UZb%-g]&uEUfN*f8jA;AGPd.;^Z(Yc(8UN!!iRHk5UQp%>_1kZ\\9TT2p!=!YEF.VU__&Vi`+\\.N./,uBb2s.SPDG,NIMl)HMRKcF<2LM1e\\D!H0nFSo+oqq]G<j,s@?2+G.0l[F`sjlg:^c];8Io6t>[Ts,Ml(#/K3pWXkbg8\"EPO`Md[_V`;nK#UWW#UDkM<qTr$ht29j6Vlu-=2g&nE\"`^'\\N%pe:#.O&&CtlDLkF_i+/#=e+9unAV-cfUgp]Q5U9OgI#\\hR^#C.I-s87Au4XVI.fT7bI_k(l\\o<QD=FJAO7gK'uG1+c/bNd@TTa_g]*,i>/+=)Te=MtUl#5AtZj*LOB],Gj9iPiX0CpaPTQ&:mm2\\7:5O5KnL=\\t3UjF!$+<cfYX3%1gC#`Br^8d!]F=3:h\"ogfDeJb[.uJUV#e:V;2F1^,:cEE4s<tXVdgLn77bCXK#t>muI-A55L)eDc?uc(\\JQ?08X5C/1MTF%\"T?,d!!?]S/:/,2^V/cKemcK>C%d'MuUd#/*Z;/(d:@`mB=T2L;;hRW[-j8q=kiENb&mn+M:el@X+&<\\!+hVc3c^-C?V^YLP2j;7PiB9g[iCB:*/]%4WQPO%,AR]&!Gi-odcWm4,Yh1):1.)6'W9I>Z+&=:bRdKRu0O5WB4i,:+Zm?mhj;dQiTqSU!C/P7l\\lq\"-F3dC0*A)4VqpU7jZa!N6Fk8/WSCpRP;2&%]6\\#WogGjp\\Iej%C0ZEo>qsh<p8As#edmkk^i@0>n5foAC64co^giDkOg7kaL.81[71,J1LW_JZOe%.Ypt]F[3JK7X@='N5doFC?/Wc#3\\iW_X)!GjqmeEdNG,[30b\\(E$\\/mXRP)j=;eIoN5';6Q,?L_s$EHf96H``:C/qdGp_lG=]f3KY%8cIcjVa`@Uk2.T%o&=VV\\#W5;jka93ZOgp2`>JkqAAHnl[q&\"37a#8a<[0,g2hMpT/rT[>cNBU#\"=<Ej[&\"6#$DR-PjoBM0cm/L?aQBEB/1MUO#f`6(c;_8bATuj&]g,*n#Hdb:2n]t&uq7TG@=:c1q2ncV$oPR?cQ)M\"%-?6h#`[iTQ\\Mb0Ad:@=XX_FZjsNV4*[R-@&7:F1)I'a(69:eVm^GE7pO_l4,]daDJid@S\".NJIf=s[^MNQPiH;lsTBEQCDuVHgmGALMlb,l*#%6[]Iom%qD4G<;8[!;MUO`28HL?/6rVLQD)n.6ZU0Wa*,\"_eG7FhF'-L9[n[L*V08sC)X=B`6jELV>#G2f]`bBXe`1n!ef)Q)tse[&?<,E'+i'#a5CT+!SA2am<J7EA)=]bE]m]bH2[!?Vp^^(\\/fYJJn[3POY7Hj*\"BlY&[e#$pf]>i!Ms.d'mImGEmV-89K0ngFTLR@DS+W\\?^/EiS2;^PA8,YP\\a^]'m]dH\"))EY2Z63&tj!6d9/([qoH&Bj7LC##IqV:Lu$m+0J\\4Y>hEYtLJ6HbM;8@/Xf[lRQZ.7*F(kPJ>9RsW\\(Qkg5^NH_c54U&6.,FeL!@NNFh3SKBM1IUaH=rBp;H\"0qL>Oc8tb04^0p)g;SVlE68^Goq^i6Fc;D=R%Y$icj]BSmH5*[HBu.45mI+SsnQ#!h\\k7%tLUp$FXR2%$7fsHt6,2?:k/OO]8[7':J3qk:maBu-RokGGaF&4YgqhT%T[9AlG;a(t]8=_$&m+\"!?%^7Fe(uf+KMPdbJF.<eM`s,@4cj10$YtYUl()(EpXn!Gb`d>+E1*=\"l:;*H'M\\$L$^P\\4&`=bn/Y6_TH22IpKQ4>GNHCPLDq1PA9jFF@V;uqJGH0J-BrWLeLC'!ds1'e!Z:tiA_P9Y%S.(#ZXkE?]\\NIXn9S^0ZLd8o?1\\RPYN$'hCW&=R.S/hpcJ(%Pr<>MtV7%\\bsZr'54^riia'.!C_,PhInXmHo#q\\rZl0rZHm6^:#(DZ:((>F+7PaA/a.Y!f1,&>Rem)/-7C1c=MIjG'85\\SrAH^j6%nOC\"NK9Qj_l^cgj\"ne$mDTsI!?d]97X6EWb,-=N^MMp'(0\\SS#XkklS;'p(aFfC:kY8g+uX\\AElWYUt,N>d==TQ;TR^A2[:b(%p4YE`oif>2_'A^b=G2O$E2W12RkB\"Y1oD3\"_\\k?ZihhOUmuHF1A\"8FZ4HS#(48L:)1<0,02aeVgNbRSURt=#uS\\@YNR\\,!DriL,1;XM[%Xk!.&kVen4+PmE[QPcR(O/mjB],J_sjfFhA!>A^0mNGDX?:CXk>Eb5&Tb'62^=qrJ=\\78=\\`LoWQ)o5:4Bf%k='1584-a+`%KHSc3e53(9+KO;1su^-\\#TZ#n!gN='upW2__&>[G0'+lBTtJhf]Bb?6,TaMY=6)m+ae\\0YM\";btncJmc+:'h&UR<#R,+k\"cL&2D.`9>'6';KBL30la@?f`)]u!.:6m@A0gYi;\";S7$%SBN/d;HI%!4JkLQ4rS?04-B-7-/N;hDYt\\7p\\f>r`=)?<\"5YPlF8'Ik,6[@[,ud'4R]9&r4Qu5Q$nU=m\"XNktr*t\\ulXlTQm'6T)/&`\\O'`#//>t*.2f&R*\"QR_oJ+S1X'/(kO3826rnaW1_C7%GGHrtYfF=YO+js*gD,!Y(=pj7^P$Lb?-*A(V/`XrDO)hoQQEP@k*77&j'd\\sfW#Ecr:\"A)5R&_GGJk[=$)C9VH5EHUrh&/2U*_1EaQ.6\"neAcFY]=$b1NQJY[:+&0)RkpH8A?GHZS\"!+hhPho:VVt5*'Ssek2P!_0QA;^A0fq\"U\\\\TN0T(D!t\"/Vu*$J0d#b/gW`B.pt>^(#T&j/TB0c-P\\lMB2:[8?V?2$l;<gZZfbrPVDFL?%S<ikd7cZ5NDAS^SB-6i^,F8\\79B00<:7SVlpjZbg/Qp>d03P`/anCrgQ,>8:h)Q.,!H-m,5Uo$k%eoGBC%u@c:h94bjOQH-DVW`GJBE&b3Y.:OtsW?WP1oPC3)4.4-^n-d2DHW9hk>m,5n`UWH)<W=7^rK),gWK1Su\\#Oapme>6nK$]L8hC)-i2KKTbN;<C6>O`hFC8#o$jj:jdFlO=M64IT,$IEpo?0se6\\R?X9rcd6_EC&]s1&eE/q5k@6]:S%]9Hl\\e44dhq%7B3aGR)8u8QK0b[n!^!8i(@9t`oQ9n$q7Al,*.sAE/n(<rnX#h*c'uGlTe[\"M!(%3b5qDUWf(4=&4g_Ng?.MoIk3u2GCsp\"2iY\\2g9f+kA0ITtgg6QnK2cPP!B[q]45us#`efDp)X\\ko9U9*^5?/KVo&5Tqc^2,C]MT,HR9.DNnJ30I6WpD25H5ZoLb\\gF<4SX!In,;$#SZJOWI6$L]<tY5ggb7S-Plm3n5m*VT*<.(je$)9p)tK38PGl/a5FI_-bq2A3h\"$fbZ1S1Hj.@'1-kOAFfVcHl2/F*!]cZ0rDi]P0-dN:f#J;]&-]P:!^ij)VN'njMcFragAjjS;6?JK3[Y\"jRN4C!`2J@,rUT@1L?Rp.;\">$,;7W8UZOhZ,F/$PHrS+c1ON]`#<.^Y(51[`*K_)<$YJr'e<f<B#'CKZQ=_QWHNh&-DFcV\"ie_M@T7Q##jZosiJ\\:VbLHXGR\\_ZdSGS!A3F*L!Vj,,bdb$>:__dZbWGaf/rb&,lI\\?a'!?M?VX+&/84tNrt(p*/K`le`\"d@@)G=:e&;a='=m]5cP'_84?NSkYjeKdgUk76.*[o1b@K8\"q>>\"upta&(Bq+oV)DSbeCiO3XQMOBAaZ\"R5o>]QOP<e%cfe?E'HQEc,-+G1q+0qHO&3oZJ:#d3oR+o9EaE\\rbiNbmO\\[!.`C[CjBp%&:NY*iWdT_]C?_n0!P$rkP2M](g.:OfEmS2qGLlG*h_lC6S?2D1HqR-jr8Y%&6EZ.Michc?ch^\"$5e5O6Im^Z6J(BekbnFM9PY+J2J$_D3_d(%0;/'e;MDTSH3RW96H(WGNKef:!#q/Yr*oVUm`m@^rtK_qh/'7`@hN0)V\"(K>YW.'so`DRDW:R2.jth-.kqATOsG6mB<FqFemg;q?>LpG=3KrC\\cWolG`m\"P+8RJ8YJ8^Y.GfGZ5?2DaSM5&1sn.O3dPJ.rh4<B^iZ'<AR'*+dVoPX\\+j3Gn3i&YmD3bkP66F>U&(_+\\d'4EmeKNgH:?&+9e]c<8mS<Qe.ID3H./EHR#=o#'>i.\\=)Pq?3:\\ogFfNS=%=/OHD>$t$(8e?.`6p(rE&M@epO(QFW,s!87*+Ur@fuC()RX8.qZIVrlVpm*OX$ta_nNFSem1jPQ#6XbA_<?(;VL^?j`tnmaBksiMFIiX/O1Y)9\"R3V:n$O%rC;//^fJ[G`BF<B\\M3O)5F6^d5WUa*C[*Z079CL=ZZ^tUi:nS6EVqlrKiY=Am+cu_Fjr7ZKeE&l^JYPX=\"IA,(,N6#p6=qj0h8.<6Qa-bLOQG?\"j&llWD9o0HI)7<4\\R?nEsTd/4&`GVYQh.:%)aE,g<=t8^SKVbWt]Dt0Pkm/&'G3KYS`PaqhMTl8+IAJV:$^bN(\"(uUcm4:f_P_';-h5l0*/A+l4DdN,g`L424Ir9-(YX[%S'eFAt&&iXSGMBKN'8#a?2ZH7nNu#V)loc:+<1t<$0L7a]au'NW:<.m2eULM-G-cfn`=aD5!CDn(Fi=_8aV.NhpIp@FJY/Cg+im1ZgoiRJKe0qB9U>TtH&q3UF08p:u`$P[o`arGni6iDZ4]aY57L<<\"pb@oHE?I<:CSO/a`hYIsa>\"fToLJ]-48`Bff8m8kTV_.\"m'62OR[0<a2rGTt7oQ'MD\"8^<j04^\"11s3mun^e3n`=#\"S*\"@<l.b!J-]A4=sPhgQ9uKf#E=7B-#tG8NjG>tTX[+&(&9c5/nlBQb%o8ZkYc_&Shsf\\P$S`WjmMl_g[:$eg4sjjkF)C1ZPta$rJGc@],mN`^mXZK4Gg6:iajVb./i[6T!KV\"3b-T=o8)GUhLY_j<m+/ZdUJ8:/<\\886eR:b6Djro3hnH&]lfK^U>]19bp9V0-JYfVPg(Ve1ZD9a]72Lp*#/BeKZ'\\?-Q1*bois^,8dZ#gOA!@j?Vr:CrMWeJd^]KjP3e_,#!/dL&'\"#R'3d8&ljN0lNp#q9(sY^%W3'O-iD@9)&Qdm3WLZ'EMa:8,*F(b.V*n]r@KpWP2gs\\SHX`cXSI!>]q0CLu$!@D#PBE!B2<H/c#_-GQBMY,bNA^Ydg/N[Im?REdn^?c&p>9[(9Ei3qR2^L;<jqAa<P^bnW]<@R]VckC%*8;(Cj?T)\\W<@3F20#Pr?6gU8_Q,+#^Thhf,0R-XFfiq.5n-\"0FD$A\\m9n=PPu[i02]6n+so(-T]4Aj\"DWZ.[U<cF?$gJc+Vg=Ejki$f?r%0XmOTZpK'?9#)kIQYfZT<9_7kF!R65(.c;+ZGA^t0_UppNao4Bo0HE><H84#r8+IB\\0ZjXK[QqQZFF7j<)1!hS/iV$;qSI(OA\\kjf0360bKT\"6L7DYt(JM%o*j)l+qaHf'&><W)C90iM2g5S/Ye9`U>sL/4[kE]'_6(fB#!oKDBM,).M7>t\\68Nk(S%qip:Enm<QgC?0OJUK!:CZ;M\"+*j)VaEK*%,Mi<5*Ii.b)lNYf9(;.\"klhAXQ@3j-i[fdN]p9(+m6*dZI^Ns[o^!Z<*NS\\]Q7C6&q%mj\"##SG'18#3Sn]Nt-ab&*kKe2ur?'JVQZAG/g^_k@0;EO#[#*T.MSSVRo0\\O^TS9Lo`AE6[1-T=)\"L::P-pIr'\"860L_!]ig81:$ijlZI*!lnW`\\\\5&o<Ag2=7BLXFI#Q?M_hTZ8UkB5=j/?5HdQI1;=JJdT!c2nKSkIjr@L0O7`=H=kX'CUY1FJ[TSZYOG,0mc0He'1i@V&a9_CNldBr$_>&*9Us6f\\t61!*@8f&@9W_Ms.p0(.Pb6L(m[(C]c)AFg.7dMCdJp*a\"Qp,\"l_0bMo[FOpI)6Eiao?B\"Z[ED6>tEH\"]LguK=ACKqtqg$N.)%]e8S^##T_%+D#4Em9E=kJLXuW,@+KFHZC3_B?#3I'1?M[PD^b\\YP,N/T6s\"@BRdHd,]i6?9P\";gWZoIoa.Ds8!7#i#Qbm*f-,CDQ2IWsapKV]`3U8%MH3r'R\"Vg^140*K5H/]de7*c\"IX=Xoe%&`A6up[4q9psTfl9]piehIN(5D[0fmqI&-@^mlR6\\Jb;tf.&i(1]l1HoiA_-mS!G6fPnHWelF6_;@,k$tU+0s*'@7\"0(5R$!HOYcBmq5^\"7o##f/jd^1^UI:C'=QcQ?$KU$VkSsr-oP^t)r+1-@^$9##Dqb@^e<S1=`.,bkU\"&<8<jbA]sK0JT:HWC5l'56C_q>[;d#8/KPZ+kn36lNR8W\\]PJX;Q]Bn_b]jeT7)7^8).@d[\"[o[0Fg;`<Y4j#HnYq^RjX`1(h.$ioIg>q;)qLC&!EeZ'qdDk#Wgr]8jMaIU3G'\\:'^.4b*9*;I,cB<Is#%/NFB.B76it^(C,a@H]&Cgf\"f)?lokFHu=lZb)K54/C9W.Vm7euT&XYhZUGmd#PQY\\oXfAZ:H:Sp+noQYlWU,X([*Iklbe-A-EYEaY(Bc,!q*QdWT,3C]ILs^F?_PN=VVI&,b^<\\5W[2GHPeOL$::s4)bFjI#S8pmA+uC[d&h\\NEuVNY`UYdVQPP<bBcM02<n-g%&;7mdP-0O;[CgF&qfk>fJ*U\"iG.iZG>U-K\"QI6*]Q+q&QK7\\pF2EYU^Qf+b45Al.9m;(=e=!t9jO'ao8dWuC<Bj%0d:)F+s,(#Ir']kk82_mq>0gPHL(5]jQ8&<M^KH\\llB1#>aX1TI\"k\\4M_/2%uV\"i^2nfJkNEXuM@N<f.iH3Qu(Jb\"%>@fE]TY.Db.Vj,gUce8#s\\@o:bH-_'2A4HoS%XLQi+ocKi<4q>HHL)E8f,3E:$'B+kuT<<NMFTNt>&?fpU-\"48_lR$<WT;4]^j\"=2ZDPbhCoc'Z?05ubp1>2/R#t-]&';*-O;cKsB@&sp,HtZqSDO\"ZHE\"['+?_D9U8&1DC,8[(*TeVa'UnJ-<[Kp]OkbA#j'%Yp5,em/Dm701Ai:MZX:_P)5ZkQV\"&:2,`FtAg.o\"nrX]/Y3;04p%DhR?'k,:18[Y8&1Z&75&\\7r8F#G3Ba\"H2gOe0Z*D13r%-G'u^m.i\"9@SNNJXnnPu'a.XDfZ\"+3U-;Aa&#j'Ok_^T,B^<hA5O]aEU,\"*PBaeqAlK,QbL%B9M]E\"c0c%qfX>ER_.lb8eg0,i@DbN]8+8c&U(!:O93l)`/@eJ$kn2<0'V,c;]67Ie3N\\JA?nO-r!-a;NCj*>1sAN8ZTDDuA[8mIAs=GA*TP(CF4BO2TJhLi\\I5u`nu-ZFXs/t(h\\t'.ZoUt9XrU'M4f;&8iH\">7LeJi<4iI%B>&r%P+8P5B9X%:-B6lrF+XfB^iUgIA3(29OFLq;5$PWZFRXGjkhTK..7U'Zn5T(C[O?#2.[*TX'Cu&Wb[g6g]a^P`Dg'4H,A[VY23U*M)PI4pqEl7L7CFDLf(*cV\\09i/u99PtRc'#T%1,1P*-+CVUFHsds9)hd>pKcsKE#NtLZRL5E4:ku=#?p#lpc8C,q+VO[A2j/9Z1S>2aT:&DFP]?'WYPd.j\\_r%!XA-uqVf)%0Sp)X:bCNG5_iAic\"EcY#J)lZiZ[A`L?*m=[a+bhmSqL#ji^T49Fp97VE.LlIQr\\\\`UoaGEj^<^rV4,oJuFJCkhK*Y#f^2G1b(,Mb'TffLN'QC]'0W,8YgP1nEidtV/hlendCc(>$u13f7V[*5tHHB^X&^sgsf.c[mqXmnlU\"h@sN7^debfVJ_]N4FG.ITGA(:V3=&F`L'fH/CY.$ffgt^r_DlB\\,+A!rLZ2>Zc@lZQhV:6:2&d!5/oKFKML^)qpZAU<XCZ%8=.kSY8$Sf-Wdd$-L+6<ANiN51]Ou79e$CAFi]ADK:1ssM)E81\\*M7Gkj\\r9CN50OM`Io+WU%'k%Lo=O)RO;(=r,:m/P0tm\">GMW]&PeY\\D!)pbeL&\"E`c3?jB0eY$H'=&0+U240RjeuE,g7?MUF1&eG*^l;4;a3tcA?3\\E6r5DJqIt)'7EgA3-kB70Vf%j:=D]30odsMST%60gT/Cp3+3m3/@+i@@o[ILR+%k(BZb$Dl.OJXc3;dPH6UaY<]cqI?P`gd3@=Wdd+tY(])X9Bf7eo^^'FB2/X*\\PY-u@mr)'B:mtn*MKLP[!gb!N4NXro[\\e>(bT>4RWep@O58jblH;2aBQcElHqB:*@@CBEqFM-C(#@@ZNEjfAVA!:GV[g\"Mh[bI*%@Hq%M^'2;ad3\"/afFaH=XAC>;uIH#qZ=E55qDgp<C>K`h.K6de3F\"@:?.WQJK-i0Ot!4N8VZpRNOHhj)7=IOIaq1'D)Xk+%5fLgbG3Jh\\?)LBa8[c/8.DVc>XPm,GtOBL)?`B+p`OfLa*GG<Ae#EO<IYlJT;.n\"ag6Rm4;W`CMNpKi)hKiMZNgSg%4doNME\\5XrkW-u<*j]<*C!mTiKgAHPVVK7<^U;Bab$bk2ak>dF+<]RkH,cO:K]]DY<T8)0AI_3%!r(@MpTW_aXoX<t_5FuPCrPaXfnATl!N&SQ+i1d+_FjmHNYn&fk,jM.:jRl*A?s=:-MW>g@WaB01nj`&e<BKbiT;ZNi*(q*DO%08mXVT]A@P/1[pD\\8R>m#^+Ta$Ka?VtmkF0OaT@l(E)'K`RUnWle[)LU79-SVs#p(r^?!5g,8FlIndkFY7R'\\m9N6oEYdd-Vro+4-r5,;$1TUl,>.GOdCqO\"r(P:B11!\\)!m@\"o@,eJ#$<pb'slWY?G(4bR82D=u,<(4sZ\"PO0n_$s\"VcGCG0MHf]DJj.]HL!Gkq!c+/&uR!PheoF<VIn\\Fi;R%)t$>/ARak.&5-\"-:-+sihH'@&U@)q!(tg4I0<]C0TU9t7b:bI9WkaY>=V>E^Hu\\[]U?o&FH>2Vce<Ia\\TdETdiV^P2mate'hO`R$e>*8OJ'g@XpTH6q]5&N]I`#h`Wt9.3\\Qk\\9d,=:)W(M].)th*]4?Y\\Z[4Ie\\-PbREB+6`Lco`+)`:]V]&*&P>SV'uBDphn/;[U1)nX'#Tk<LVh?%sMjCPiQW@sYr6g.lf+b:Umh5#kOL#9\\;khU\"f/$BHr&\";#o>!<n<I+<=foda2nT[dce8_@@q>#k+IQW$h.b'XuRF486REG@f_DTAO8Eunc/Y[DZH^*rB>5BS<s98iH:TP8hZR[!9F$::&H0dDQ+H.;=_phHt3PusiX*G7\\DLHPHclg]\"uGk5'A0IR0@e?J:dc-klOdTXjYcA>5;6.?a!S%``4qK\"7b%7U[%0eKA'fg\"6ZDb%GWq00\"nqG&m$OA?cuY\"R$G[[[8>,X<l]V:s/H(k]7*dVoD.)C`*ZcVWsshR>!;#KBQ=Do&4Ha7Spe'^qQ!+R.:$bIMs:VF@UF5WSqFjcPH5oVs[.ap\"*:+Bl(eI7`J8(>C+8n[era#07(qOXDl\\C`eOMK)Z5`CO)-;jLp2N$IS@UC1e8MO`Q;9eiiifgo=[B;.V&61b$jajQ(ZgOO$s:\"GLIK\\Ppc6D_0q)(^#PU'>)l9BGnSfET@qd1]m,DGH807]m=hSL!MWj@.-AHl.Z[\\e&JJ:-Ct1.rgS>o(Q=@ETuR`L0C_8$_bN2kk`?!jpU8&_+4uEK_3+pJ4^#`'-lS?1``0;\\0B\\dINq<^kO?fMKhK`u30bVT[2[:\\Ed!Yio05Y=T7-k6OIe6C\"lhQpD)u[-+=-Rt]Ol&a&8T`0/m\"S.Vlm+9;q]Zaop4LsGlSC>t$C[)aX=[n16tY[3h[i4>\\hAT5KLL4b+bj^,3J&^7L:c0H2d1(rj8VnE\\h/T>3[ZU##cB:UV%U8ESbLJ.AQ1g<JFTG@2f?'Pcj6hE(m0mh&s]RuSE0:QCM1']hMKIK_&/G!Vn[1t\\1!XkmAl,J\"N^'ss$h0bN$pG-7G2RVACuJ-G2t9T&bNL%9,Y(um,2m$\"`/6#icYJ$5^P>S6_$Y*ZKM-uG8kWO<tI;Bp*&Cn#2IdB/&IEqT*FW4@(j%Gb.fXTM](CNnsU))]MK;K_%Q\"D;@\"c@mId/FVJ5mR]MMop9!h&Nm&4r[YgNSITCT%L>SF#<YN+Es&uR?.oV0_5&rm$G,2[V0j2Ns5<T#X]PNbVM[Uc)`F%^N`70m^`2;OJW8bUQFdcr?`h0?!TN`:&ebKs?3Tj2'!OkY9W2L?KYb>M;\\O<qSKB'_ZIemH''*lJGrjiPs*@`I\"bNi0FMZY-R'Y[t3Jd@7>':/[G!(O@VER)g_TMlQpXc16A_?\\l_hL%2u?iODr\"j2Zsl308bfmK3ce,3?6p6N*NP^4ko\\J!,E/H;bAq\"ON%I@2aq;!l:!\"P:fJfe3`UB;(es?Fup'mc8\"5UZ:18#;LKpopM37E_RM016T>IFaae6d4AW=ZbneB+P41;g\\n>oQ/rM:I4.1]O7G)l]lK1<*])0e%o'+[uo3S;)-;\\dOOkW:X68Sj.g6sd))1u!I'QqMsb,\\Uk`uuZ6P\"Re7eC26-=guhkEa3P8jeJs:j0@m'')g4*2i/'G*/9H9[k3u]jPJ<b,IcGkql4[cECBF\"dEeddS?)ZSN=Y#'"


--==================== 组件属性 ====================
Script.propertys = {
    tableIds = {
        type = Mini.Array,
        itemType = Mini.String,
        default = Mini.Array(Mini.String,
            "v7693060393308433405110852",
            "v7693126570164530173110818",
            "v7693126613114203133110820",
            "v7693126651768908797110822",
            "v7693126711898450941110824",
            "v7693126780617927677110826",
            "v7693127098445507581110828",
            "v7693127149985115133110830",
            "v7693127197229755389110832",
            "v7693127235884461053110834",
            "v7693127261654264829110836",
            "v7693127296014003197110838",
            "v7693127317488839677110840",
            "v7693127343258643453110842",
            "v7693127364733479933110844",
            "v7693127390503283709110846",
            "v7693127424863022077110848",
            "v7693127450632825853110850",
            "v7693127502172433405110852",
            "v7693127540827139069110854",
            "v7693143986256915453110856",
            "v7693144046386457597110858",
            "v7693144080746195965110860",
            "v7693144115105934333110862",
            "v7693144145170705405110864",
            "v7693144179530443773110866",
            "v7693144218185149437110868",
            "v7693144248249920509110870",
            "v7693144514537892861110872",
            "v7693144566077500413110874",
            "v7693144609027173373110876",
            "v7693144643386911741110878",
            "v7693144682041617405110880",
            "v7693144716401355773110882",
            "v7693144755056061437110884",
            "v7693144806595668989110886",
            "v7693144853840309245110888",
            "v7693144896789982205110890",
            "v7693144935444687869110892",
            "v7693144969804426237110894",
            "v7693822226017463293719949",
            "v7693822281852038141719951",
            "v7693822320506743805719953",
            "v7693822363456416765719955",
            "v7693822393521187837719957",
            "v7693822427880926205719959",
            "v7693822462240664573719961",
            "v7693822496600402941719963",
            "v7693822530960141309719965",
            "v7693822565319879677719967",
            "v7693822621154454525719969",
            "v7693822659809160189719971",
            "v7693822698463865853719973",
            "v7693822737118571517719975",
            "v7693822775773277181719977",
            "v7693823059241118717719979",
            "v7693823106485758973719981",
            "v7693823140845497341719983",
            "v7693823149435431933719985",
            "v7693823205270006781719987",
            "v7693823248219679741719989",
            "v7693823295464319997719991",
            "v7693823342708960253719993",
            "v7693823389953600509719995",
            "v7693823402838502397719997",
            "v7693823471557979133719999",
            "v7693823518802619389720001",
            "v7693823561752292349720003",
            "v7693823600406998013720005",
            "v7693823630471769085720007"
        ),
        displayName = "二维表ID组",
        customDisplayName = "表ID",
        tips = "MiniMind 权重表(70张)。留空则只用缓存+检索，不生成"
    },
    temperature = {
        type = Mini.Number, default = 0.85, minValue = 0.05, maxValue = 2.0,
        format = "%.2f", displayName = "温度", stride = 0.01,
        tips = "越低越保守，越高越发散"
    },
    topP = {
        type = Mini.Number, default = 0.85, minValue = 0.1, maxValue = 1.0, stride = 0.01,
        format = "%.2f", displayName = "Top-P",
        tips = "核采样，累积概率达到阈值就截断"
    },
    maxTokens = {
        type = Mini.Number, default = 24, minValue = 1, maxValue = 128,
        format = "%.0f", displayName = "最大生成字数",
        tips = "生成是逐字跑的，这是耗时的主要来源"
    },
    ctxTurns = {
        type = Mini.Number, default = 4, minValue = 0, maxValue = 16,
        format = "%.0f", displayName = "上下文轮数",
        tips = "带上几轮历史。轮数越多，首字前的准备时间越长"
    },
    maxCtx = {
        type = Mini.Number, default = 256, minValue = 32, maxValue = 1024,
        format = "%.0f", displayName = "上下文最大token",
        tips = "超了就丢最早的。KV缓存内存 = 层数*kv头*头维*该值*2"
    },
    cacheSize = {
        type = Mini.Number, default = 20000, minValue = 0, maxValue = 200000,
        format = "%.0f", displayName = "缓存条数上限",
        tips = "完全命中直接回，是唯一零耗时的路径"
    },
    seed = {
        type = Mini.Number, default = 20261005, displayName = "随机种子"
    },
    promptMode = {
        type = Mini.Number, default = 2, minValue = 0, maxValue = 2,
        format = "%.0f", displayName = "提示词模式",
        tips = "2=问答cue(默认,预训练权重最优) 1=聊天模板(SFT权重) 0=纯续写"
    },
    repPenalty = {
        type = Mini.Number, default = 1.15, minValue = 1.0, maxValue = 2.0, stride = 0.01,
        format = "%.2f", displayName = "重复惩罚",
        tips = ">1 抑制刚出现过的 token，防止原地循环"
    },
    debugMode = { type = Mini.Bool, default = false, displayName = "调试日志" },
    cacheShards = {
        type = Mini.Array,
        itemType = Mini.String,
        default = Mini.Array(Mini.String, ""),
        displayName = "缓存存档分片",
        customDisplayName = "缓存片",
        tips = "SaveCache 把缓存序列化成JSON后按片存在这里，重进地图用 LoadCache 取回"
    },
    shardLen = {
        type = Mini.Number, default = 1200, minValue = 200, maxValue = 8000,
        format = "%.0f", displayName = "每片字符数",
        tips = "单个属性字符串别太长，1200 较稳"
    },
    autoLoadCache = {
        type = Mini.Bool, default = true, displayName = "启动时自动加载缓存"
    },
    autoSaveEvery = {
        type = Mini.Number, default = 0, minValue = 0, maxValue = 500,
        format = "%.0f", displayName = "每N次新缓存自动存档",
        tips = "0=不自动(手动调SaveCache)；调太小会频繁序列化"
    }
}

--==================== 开放函数 ====================
Script.openFnArgs = {
    Chat = {
        returnType = Mini.String, displayName = "对话(缓存+生成)",
        params = { "会话ID", Mini.String, "用户文本", Mini.String }
    },
    Generate = {
        returnType = Mini.String, displayName = "强制生成(跳过缓存)",
        params = { "会话ID", Mini.String, "用户文本", Mini.String }
    },
    ResetSession = {
        returnType = Mini.String, displayName = "清空会话",
        params = { "会话ID", Mini.String }
    },
    SetTableIds = {
        returnType = Mini.String, displayName = "设置二维表ID组",
        params = { "ID组(逗号分隔)", Mini.String }
    },
    ProbeTable = {
        returnType = Mini.String, displayName = "探二维表(调试)",
        params = { "表ID", Mini.String }
    },
    GetTableIds = {
        returnType = Mini.String, displayName = "查看当前二维表ID(逗号分隔)",
        params = {}
    },
    ModelStats = {
        returnType = Mini.String, displayName = "模型与缓存统计"
    },
    Encode = {
        returnType = Mini.String, displayName = "分词结果(调试)",
        params = { "文本", Mini.String }
    },
    WarmCache = {
        returnType = Mini.String, displayName = "预热缓存",
        params = { "问答对(每行:问\\t答)", Mini.String }
    },
    ShowIds = {
        returnType = Mini.String, displayName = "查看当前二维表ID(调试)",
        params = {}
    },
    Ask = { returnType = Mini.String, displayName = "对话(智能路由)",
            params = { "会话ID", Mini.String, "用户文本", Mini.String } },
    Route = { returnType = Mini.String, displayName = "看走哪条路径(调试)",
              params = { "会话ID", Mini.String, "用户文本", Mini.String } },
    Calc = { returnType = Mini.String, displayName = "计算(内置skill)",
             params = { "表达式", Mini.String } },
    AddDoc = { returnType = Mini.String, displayName = "加知识问答",
               params = { "问题", Mini.String, "答案", Mini.String } },
    AddDocs = { returnType = Mini.String, displayName = "批量加知识(每行:问\t答)",
                params = { "文本", Mini.String } },
    SearchKB = { returnType = Mini.String, displayName = "检索知识库(调试)",
                 params = { "查询", Mini.String } },
    ClearKB = { returnType = Mini.String, displayName = "清空知识库" },
    SetPersona = { returnType = Mini.String, displayName = "设置人设",
                   params = { "人设名", Mini.String, "风格", Mini.String } },
    ListPersona = { returnType = Mini.String, displayName = "列出人设" },
    ListSkills = { returnType = Mini.String, displayName = "列出技能" },
    RegisterVM = { returnType = Mini.String, displayName = "注册LuaVM技能",
                   params = { "技能名", Mini.String, "Lua源码", Mini.String } },
    Stats2 = { returnType = Mini.String, displayName = "统计(知识/技能/人设)" },
    SaveCache = { returnType = Mini.String, displayName = "缓存存档(写属性)", params = {} },
    LoadCache = { returnType = Mini.String, displayName = "缓存读档(从属性)", params = {} },
    ClearCache = { returnType = Mini.String, displayName = "清空答案缓存", params = {} },
    CacheStats = { returnType = Mini.String, displayName = "缓存命中统计", params = {} },
    ExportShard = {
        returnType = Mini.String, displayName = "导出第N片缓存JSON",
        params = { "片序号(从1)", Mini.String }
    },
    ImportShards = {
        returnType = Mini.String, displayName = "导入缓存JSON(可多行拼接)",
        params = { "JSON文本", Mini.String }
    }
}

--==================== 运行时基础 ====================
-- 环境前提（已确认）：
--   * bit 模块一定存在（band/bor/bxor/lshift/rshift）
--   * os 只有 date/time/timeMs，没有 clock
--   * Lua 5.1：没有 goto / bit32 / table.unpack / 整数除法
local band, bor, bxor, blshift, brshift = bit.band, bit.bor, bit.bxor, bit.lshift, bit.rshift
local function nowMs() return os.timeMs() end

--==================== 属性读取（铁律）====================
-- 属性值在**组件实例 self** 上，读 Script.xxx 拿到的是 propertys 里的
-- 定义表（{type=..., default=...}），不是配置值。必须统一走这里。
local COMPONENT_SELF = nil
local ID_SOURCE = nil          -- 记录 ID 从哪来，启动时打印，便于排障

local function isPropDef(v)
    -- 定义表的特征：带 type / default 字段
    return type(v) == "table" and (v.default ~= nil or v.type ~= nil)
end
local function getProp(name)
    local src = COMPONENT_SELF
    if src ~= nil then
        local ok, x = pcall(function() return src[name] end)
        if ok and x ~= nil and not isPropDef(x) then return x end
    end
    local ok2, x2 = pcall(function() return Script[name] end)
    if ok2 and x2 ~= nil and not isPropDef(x2) then return x2 end
    return nil
end
local function getNumProp(name, defv)
    local v = tonumber(getProp(name))
    return v ~= nil and v or defv
end
local function getStrProp(name, defv)
    local v = getProp(name)
    if type(v) == "string" and v ~= "" then return v end
    return defv
end
local function getBoolProp(name, defv)
    local v = getProp(name)
    if type(v) == "boolean" then return v end
    if type(v) == "number" then return v ~= 0 end
    if type(v) == "string" then
        return v == "1" or v:lower() == "true" or v:lower() == "yes"
    end
    return defv
end
local function D(...)
    if getBoolProp("debugMode", false) then
        print("[MM] " .. tostring(...))
    end
end

local SEED_STATE = nil
local function rnd()
    -- xorshift32，纯 bit 运算，不依赖 math.randomseed
    if not SEED_STATE then
        SEED_STATE = band(getNumProp("seed", 20261005), 0x7FFFFFFF)
        if SEED_STATE == 0 then SEED_STATE = 20261005 end
    end
    local x = SEED_STATE
    x = bxor(x, blshift(x, 13))
    x = bxor(x, brshift(x, 17))
    x = bxor(x, blshift(x, 5))
    SEED_STATE = band(x, 0x7FFFFFFF)
    return SEED_STATE
end
local function rnd01()
    -- [0,1)
    return (rnd() % 1000000) / 1000000
end

--==================== 二维表读取 ====================
-- 用户实际导入的 70 个二维表 ID（mmlm_1..mmlm_70 的顺序）。
-- 属性没生效时兜底用这份，保证开箱即用。
local DEFAULT_IDS = {
    "v7693060393308433405110852",
    "v7693126570164530173110818",
    "v7693126613114203133110820",
    "v7693126651768908797110822",
    "v7693126711898450941110824",
    "v7693126780617927677110826",
    "v7693127098445507581110828",
    "v7693127149985115133110830",
    "v7693127197229755389110832",
    "v7693127235884461053110834",
    "v7693127261654264829110836",
    "v7693127296014003197110838",
    "v7693127317488839677110840",
    "v7693127343258643453110842",
    "v7693127364733479933110844",
    "v7693127390503283709110846",
    "v7693127424863022077110848",
    "v7693127450632825853110850",
    "v7693127502172433405110852",
    "v7693127540827139069110854",
    "v7693143986256915453110856",
    "v7693144046386457597110858",
    "v7693144080746195965110860",
    "v7693144115105934333110862",
    "v7693144145170705405110864",
    "v7693144179530443773110866",
    "v7693144218185149437110868",
    "v7693144248249920509110870",
    "v7693144514537892861110872",
    "v7693144566077500413110874",
    "v7693144609027173373110876",
    "v7693144643386911741110878",
    "v7693144682041617405110880",
    "v7693144716401355773110882",
    "v7693144755056061437110884",
    "v7693144806595668989110886",
    "v7693144853840309245110888",
    "v7693144896789982205110890",
    "v7693144935444687869110892",
    "v7693144969804426237110894",
    "v7693822226017463293719949",
    "v7693822281852038141719951",
    "v7693822320506743805719953",
    "v7693822363456416765719955",
    "v7693822393521187837719957",
    "v7693822427880926205719959",
    "v7693822462240664573719961",
    "v7693822496600402941719963",
    "v7693822530960141309719965",
    "v7693822565319879677719967",
    "v7693822621154454525719969",
    "v7693822659809160189719971",
    "v7693822698463865853719973",
    "v7693822737118571517719975",
    "v7693822775773277181719977",
    "v7693823059241118717719979",
    "v7693823106485758973719981",
    "v7693823140845497341719983",
    "v7693823149435431933719985",
    "v7693823205270006781719987",
    "v7693823248219679741719989",
    "v7693823295464319997719991",
    "v7693823342708960253719993",
    "v7693823389953600509719995",
    "v7693823402838502397719997",
    "v7693823471557979133719999",
    "v7693823518802619389720001",
    "v7693823561752292349720003",
    "v7693823600406998013720005",
    "v7693823630471769085720007"
}
local RUNTIME_IDS = nil

local function getIds()
    if RUNTIME_IDS then return RUNTIME_IDS end
    -- 优先级：实例属性 tableIds > 实例属性 tableIdsText > 内置 DEFAULT_IDS
    -- 属性可能是字符串也可能是 Mini.Array，两种都要接住
    local raw = getProp("tableIds")
    if raw == nil then raw = getProp("tableIdsText") end
    local list = {}
    ID_SOURCE = "内置默认(70个)" 
    if type(raw) == "string" and raw ~= "" then
        for w in string.gmatch(raw, "[^,;，；%s]+") do
            list[#list + 1] = w
        end
    elseif type(raw) == "table" then
        -- Mini.Array 可能是普通表，也可能是 userdata 代理
        local ok = pcall(function()
            for i = 1, 100000 do
                local v = raw[i]
                if v == nil then break end
                list[#list + 1] = tostring(v)
            end
        end)
        if not ok or #list == 0 then
            local vals = raw.values
            if type(vals) == "table" then
                for i = 1, #vals do list[#list + 1] = tostring(vals[i]) end
            end
        end
    end
    if #list == 0 then
        list = DEFAULT_IDS
        ID_SOURCE = "内置默认(70个)"
    else
        ID_SOURCE = "属性配置"
    end
    RUNTIME_IDS = list
    return list
end

local function readTable(tid)
    -- 全局二维表的 playerId 传 nil；传 0 在部分版本返回空。两种都试。
    local ok, rows = pcall(Data.Table.GetAllValue, Data.Table, tid, nil)
    if ok and type(rows) == "table" and #rows > 0 then return rows end
    local ok2, rows2 = pcall(Data.Table.GetAllValue, Data.Table, tid, 0)
    if ok2 and type(rows2) == "table" and #rows2 > 0 then return rows2 end
    if ok and type(rows) == "table" then return rows end
    return nil
end

local function pickField(row)
    if type(row) == "string" then return row end
    if type(row) ~= "table" then return tostring(row) end
    if #row == 1 then return row[1] end
    local best, blen = nil, 0
    for i = 1, #row do
        local v = tostring(row[i] or "")
        -- 跳过行号这类纯数字短串
        if #v > blen and not (i == 1 and #v < 6 and tonumber(v)) then
            best, blen = v, #v
        end
    end
    return best or row[1]
end

--==================== Base85 解码 ====================
local B85 = {}
do
    for i = 0, 84 do B85[string.char(i + 0x21)] = i end
end

-- Base85 -> 字节串。
-- 两个关键优化（27MB 权重 = 3600 万字符，朴素写法跑不完）：
--   1) string.byte(s,i,i+4) 一次取 5 个字节值，避免 5 次 string.sub
--      每次都新建临时字符串（这是最大的开销）
--   2) 数值索引查表 BV[b]，不用 B85[char]
--   3) 分块 concat：7M 个条目直接塞一张表要几百 MB，按 2048 个一批拼接
local BV = {}
for i = 0, 84 do BV[0x21 + i] = i end

local function b85Decode(s)
    if type(s) ~= "string" or #s < 5 then return "" end
    -- 导出端把 base85 里的 '"'(0x22, 值 1) 转义成了 "~q" 两个字符，
    -- 避免和 CSV 的双引号包裹冲突。解码前必须先还原，否则 BV[0x7E] 是 nil，
    -- Lua 5.1 会在 "attempt to perform arithmetic on a nil value" 直接崩。
    if string.find(s, "~", 1, true) then
        s = string.gsub(s, "~q", '"')
    end
    local n = #s
    local i = 1
    local buf, nb = {}, 0
    local parts, np = {}, 0
    local sbyte = string.byte
    local schar = string.char
    local floor = math.floor
    while i + 4 <= n do
        local a, b, c, d, e = sbyte(s, i, i + 4)
        local v = ((((BV[a] * 85 + BV[b]) * 85 + BV[c]) * 85 + BV[d]) * 85 + BV[e])
        nb = nb + 1
        buf[nb] = schar(floor(v / 16777216) % 256, floor(v / 65536) % 256,
                        floor(v / 256) % 256, v % 256)
        if nb >= 2048 then
            np = np + 1; parts[np] = table.concat(buf, "", 1, nb); nb = 0
        end
        i = i + 5
    end
    -- 尾部不足 5 字符的分组：按 ascii85 规则用 'u'(=84) 补齐后解码，
    -- 只取应有的字节数（k 个字符 -> k-1 字节）。
    -- 不补会整组丢弃，最多丢 4 字节；而权重 blob 长度恰好不是 5 的倍数
    -- （26029093），实测解出 26029092，parseModel 随即错位到越界读 nil。
    local rem = n - i + 1
    if rem > 1 then
        local p1 = sbyte(s, i)
        local p2 = rem > 1 and sbyte(s, i + 1) or 0x75
        local p3 = rem > 2 and sbyte(s, i + 2) or 0x75
        local p4 = rem > 3 and sbyte(s, i + 3) or 0x75
        local v = ((((BV[p1] * 85 + BV[p2]) * 85 + BV[p3]) * 85 + BV[p4]) * 85 + BV[0x75])
        local all = { floor(v / 16777216) % 256, floor(v / 65536) % 256,
                      floor(v / 256) % 256, v % 256 }
        local out = {}
        for k = 1, rem - 1 do out[k] = schar(all[k]) end
        nb = nb + 1
        buf[nb] = table.concat(out, "", 1, rem - 1)
    end
    if nb > 0 then np = np + 1; parts[np] = table.concat(buf, "", 1, nb) end
    return table.concat(parts, "", 1, np)
end

--==================== 二进制读取 ====================
-- 权重存成字符串：1 字节/参数（int8），内存只有 table 方案的 1/16。
-- 26M 参数 -> 26MB（table 方案要 416MB，游戏里根本塞不下）。
local Reader = {}
Reader.__index = Reader
function Reader.new(s, pos)
    return setmetatable({ s = s, p = pos or 1 }, Reader)
end
function Reader:u8()
    local v = string.byte(self.s, self.p); self.p = self.p + 1; return v or 0
end
function Reader:u32()
    local a, b, c, d = string.byte(self.s, self.p, self.p + 3)
    self.p = self.p + 4
    return (a or 0) + (b or 0) * 256 + (c or 0) * 65536 + (d or 0) * 16777216
end
function Reader:f32()
    local a, b, c, d = string.byte(self.s, self.p, self.p + 3)
    self.p = self.p + 4
    -- IEEE754 小端
    local m = a + b * 256 + c * 65536 + band(d, 0x7F) * 16777216
    local e = blshift(band(d, 0x80), 1) + brshift(brshift(c, 7), 0) * 0 -- 占位
    -- 简化：用 string.format/tonumber 不可靠，改用位运算重建
    local sign = 1
    if band(d, 0x80) ~= 0 then sign = -1 end
    local exp = blshift(band(d, 0x7F), 1) + brshift(c, 7)
    local mant = band(c, 0x7F) * 65536 + b * 256 + a
    if exp == 0 then
        return sign * mant * 2 ^ (-149)
    elseif exp == 255 then
        return 0
    end
    return sign * (1 + mant / 8388608) * 2 ^ (exp - 127)
end
function Reader:bytes(n)
    local v = string.sub(self.s, self.p, self.p + n - 1)
    self.p = self.p + n
    return v
end

--==================== 模型容器 ====================
local M = nil          -- 反序列化后的模型
local MODEL_ERR = nil

-- 一个 int8 权重矩阵：字符串 + 每行的 scale
local function readMat(r, rows, cols)
    local scales = {}
    for i = 1, rows do scales[i] = r:f32() end
    return { s = r:bytes(rows * cols), rows = rows, cols = cols, scales = scales }
end

-- int8 矩阵 · 向量：acc = Σ (b-128)*x[j]，最后乘 scale
local BYTEVAL = {}
for b = 0, 255 do BYTEVAL[b] = b - 128 end

-- int8 矩阵 · 向量。
-- 存储的是 (w+128) 的无符号字节，朴素写法每次要查 BYTEVAL[b] 表还原成 w，
-- 2900 万次查表是纯开销。改成：
--   Σ w[j]*x[j] = Σ (b[j]-128)*x[j] = Σ b[j]*x[j] - 128*Σ x[j]
-- 直接用 string.byte 返回的原始字节值相乘，行末减掉 128*sumX 即可。
-- sumX 每行复用，代价只有 cols 次加法。
local function matvec(W, x, out)
    local s, scales, rows, cols = W.s, W.scales, W.rows, W.cols
    local sb = string.byte
    local sumX = 0
    for j = 1, cols do sumX = sumX + x[j] end
    local bias = sumX * 128
    local d3 = cols - 3
    for i = 0, rows - 1 do
        local off = i * cols
        local acc = 0
        local j = 1
        while j < d3 do
            local a, b, c, d = sb(s, off + j, off + j + 3)
            acc = acc + a * x[j] + b * x[j + 1]
                  + c * x[j + 2] + d * x[j + 3]
            j = j + 4
        end
        while j <= cols do
            acc = acc + sb(s, off + j) * x[j]
            j = j + 1
        end
        out[i + 1] = (acc - bias) * scales[i + 1]
    end
    return out
end

-- 取 embedding 的第 id 行（已反量化）
local function embRow(W, id, out)
    local s, scales, cols = W.s, W.scales, W.cols
    local off = id * cols
    local sb = string.byte
    for j = 1, cols do
        out[j] = BYTEVAL[sb(s, off + j)] * scales[id + 1]
    end
    return out
end

-- 从 blob 解析模型
local function parseModel(blob)
    local r = Reader.new(blob, 1)
    if r:bytes(5) ~= "MMLM1" then return nil, "magic 不对" end
    local cfg = {
        dim = r:u32(), nLayers = r:u32(), nHeads = r:u32(),
        nKvHeads = r:u32(), headDim = r:u32(), hidden = r:u32(),
        vocab = r:u32(), maxCtx = r:u32()
    }
    local m = { cfg = cfg, layers = {} }
    m.embed = readMat(r, cfg.vocab, cfg.dim)
    local qd = cfg.nHeads * cfg.headDim
    local kvd = cfg.nKvHeads * cfg.headDim
    for l = 1, cfg.nLayers do
        local L = {}
        L.an = {}
        for i = 1, cfg.dim do L.an[i] = r:f32() end
        L.fn = {}
        for i = 1, cfg.dim do L.fn[i] = r:f32() end
        L.wq = readMat(r, qd, cfg.dim)
        L.wk = readMat(r, kvd, cfg.dim)
        L.wv = readMat(r, kvd, cfg.dim)
        L.wo = readMat(r, cfg.dim, qd)
        L.w1 = readMat(r, cfg.hidden, cfg.dim)
        L.w2 = readMat(r, cfg.dim, cfg.hidden)
        L.w3 = readMat(r, cfg.hidden, cfg.dim)
        m.layers[l] = L
    end
    m.fnorm = {}
    for i = 1, cfg.dim do m.fnorm[i] = r:f32() end
    return m, nil
end

local function loadModel()
    if M then return M end
    if MODEL_ERR then return nil end
    local ids = getIds()
    if #ids == 0 then
        MODEL_ERR = "未配置二维表ID"
        return nil
    end
    local t0 = nowMs()
    local chunks = {}
    for i = 1, #ids do
        local rows = readTable(ids[i])
        if not rows then
            MODEL_ERR = "读表失败: " .. tostring(ids[i])
            return nil
        end
        local off = 1
        local h0 = rows[1] and pickField(rows[1])
        if type(h0) == "string" and string.sub(h0, 1, 5) == "MMLM|" then off = 2 end
        local t = {}
        for k = off, #rows do
            local v = pickField(rows[k])
            if v then t[#t + 1] = v end
        end
        chunks[#chunks + 1] = table.concat(t)
    end
    local b85 = table.concat(chunks)
    local bin = b85Decode(b85)
    -- 权重本身已经是 int8 量化数据，deflate 压不动多少，反而要在游戏里
    -- 花几十秒解压，所以默认不压：解码后首 5 字节就是 magic "MMLM1"。
    -- 万一以后改成压缩存储，这里自动识别并解压。
    local blob = bin
    if string.sub(bin, 1, 5) ~= "MMLM1" then
        local ok2, r2 = pcall(function() return Inflater.inflate(bin, 3) end)
        if ok2 and r2 and #r2 > 100 then blob = r2 end
    end
    if #blob < 100 then
        MODEL_ERR = "解码失败: 得到 " .. tostring(#blob) .. " 字节"
        return nil
    end
    local m, err = parseModel(blob)
    if not m then MODEL_ERR = err; return nil end
    D(string.format("模型加载 %.0fms  参数 %d  dim=%d 层=%d 头=%d/%d hidden=%d vocab=%d",
        nowMs() - t0, #blob, m.cfg.dim, m.cfg.nLayers, m.cfg.nHeads,
        m.cfg.nKvHeads, m.cfg.hidden, m.cfg.vocab))
    M = m
    return M
end

--==================== 前向 ====================
local function rmsnorm(x, w, dim, eps)
    local ss = 0
    for i = 1, dim do ss = ss + x[i] * x[i] end
    local scale = 1 / math.sqrt(ss / dim + (eps or 1e-5))
    local o = {}
    for i = 1, dim do o[i] = x[i] * scale * w[i] end
    return o
end

local function softmax(t, n)
    local mx = -1e30
    for i = 1, n do if t[i] > mx then mx = t[i] end end
    local s = 0
    for i = 1, n do t[i] = math.exp(t[i] - mx); s = s + t[i] end
    for i = 1, n do t[i] = t[i] / s end
    return t
end

-- RoPE 表：cos/sin，按位置缓存
local ROPE = nil
local function ropeTable(headDim, ropeBase, maxLen)
    if ROPE then return ROPE end
    local half = headDim / 2
    local cs, sn = {}, {}
    for p = 0, maxLen - 1 do
        local c = {}
        local s = {}
        for i = 0, half - 1 do
            local freq = 1 / (ropeBase ^ (i / (half * 1.0)))
            -- freqs = 1/(base^(2i/dim))，这里 i/half = 2i/dim
            local ang = p * freq
            c[i + 1] = math.cos(ang)
            s[i + 1] = math.sin(ang)
        end
        cs[p] = c; sn[p] = s
    end
    ROPE = { cos = cs, sin = sn }
    return ROPE
end

-- 一个会话的生成状态
local function newState(m)
    local cfg = m.cfg
    return {
        m = m,
        kv = {},          -- kv[l][1]=K 表 kv[l][2]=V 表，扁平：pos*nKvHeads*headDim
        pos = 0,
        dim = cfg.dim
    }
end

local function forwardOne(st, tokenId, pos)
    local m = st.m
    local cfg = m.cfg
    local dim, nh, nkv, hd = cfg.dim, cfg.nHeads, cfg.nKvHeads, cfg.headDim
    local qd, kvd = nh * hd, nkv * hd
    local R = ropeTable(hd, 1e6, cfg.maxCtx)
    local x = {}
    embRow(m.embed, tokenId, x)

    local qA, kA, vA, oA = {}, {}, {}, {}
    local tmp = {}

    for l = 1, cfg.nLayers do
        local L = m.layers[l]
        -- 残差输入归一化
        local h = rmsnorm(x, L.an, dim)
        -- Q/K/V
        matvec(L.wq, h, qA)
        matvec(L.wk, h, kA)
        matvec(L.wv, h, vA)
        -- RoPE（rotate_half）
        local cs, sn = R.cos[pos], R.sin[pos]
        local half = hd / 2
        for kh = 0, nkv - 1 do
            local base = kh * hd
            for i = 0, half - 1 do
                local a = kA[base + i + 1]
                local b = kA[base + half + i + 1]
                kA[base + i + 1] = a * cs[i + 1] - b * sn[i + 1]
                kA[base + half + i + 1] = b * cs[i + 1] + a * sn[i + 1]
                local c = vA[base + i + 1]
                local d = vA[base + half + i + 1]
                -- V 不加 RoPE，这里不动
                _ = c; _ = d
            end
        end
        for qh = 0, nh - 1 do
            local base = qh * hd
            for i = 0, half - 1 do
                local a = qA[base + i + 1]
                local b = qA[base + half + i + 1]
                qA[base + i + 1] = a * cs[i + 1] - b * sn[i + 1]
                qA[base + half + i + 1] = b * cs[i + 1] + a * sn[i + 1]
            end
        end
        -- 写 KV cache
        local kv = st.kv[l]
        if not kv then
            kv = { {}, {} }
            st.kv[l] = kv
        end
        local K, V = kv[1], kv[2]
        local koff = pos * kvd
        for i = 1, kvd do K[koff + i] = kA[i]; V[koff + i] = vA[i] end
        -- 注意力：GQA，nkv 个 kv 头服务 nh/nkv 个 q 头
        local rep = nh / nkv
        local attOut = {}
        for qh = 0, nh - 1 do
            local kvh = math.floor(qh / rep)
            local qb = qh * hd
            local scores = {}
            local n = pos + 1
            for t = 0, pos do
                local kb = t * kvd + kvh * hd
                local acc = 0
                for i = 1, hd do acc = acc + qA[qb + i] * K[kb + i] end
                scores[t + 1] = acc / math.sqrt(hd)
            end
            softmax(scores, n)
            local ob = qh * hd
            for i = 1, hd do attOut[ob + i] = 0 end
            for t = 0, pos do
                local vb = t * kvd + kvh * hd
                local w = scores[t + 1]
                if w > 1e-9 then
                    for i = 1, hd do attOut[ob + i] = attOut[ob + i] + w * V[vb + i] end
                end
            end
        end
        matvec(L.wo, attOut, oA)
        for i = 1, dim do x[i] = x[i] + oA[i] end
        -- FFN: SwiGLU
        local h2 = rmsnorm(x, L.fn, dim)
        matvec(L.w1, h2, tmp)
        local up = {}
        matvec(L.w3, h2, up)
        for i = 1, cfg.hidden do
            -- SiLU(x) = x * sigmoid(x)
            tmp[i] = tmp[i] * (1 / (1 + math.exp(-tmp[i]))) * up[i]
        end
        local dn = {}
        matvec(L.w2, tmp, dn)
        for i = 1, dim do x[i] = x[i] + dn[i] end
    end

    local xf = rmsnorm(x, m.fnorm, dim)
    local logits = {}
    matvec(m.embed, xf, logits)   -- tied embedding
    return logits
end

--==================== 采样 ====================
local function sample(logits, n, temperature, topP)
    local t = temperature
    if t and t > 0.001 then
        for i = 1, n do logits[i] = logits[i] / t end
    end
    local idx = {}
    for i = 1, n do idx[i] = i end
    table.sort(idx, function(a, b) return logits[a] > logits[b] end)
    -- top-p
    local mx = logits[idx[1]]
    local sum = 0
    local probs = {}
    for i = 1, n do probs[i] = math.exp(logits[i] - mx); sum = sum + probs[i] end
    local acc = 0
    local cut = n
    for i = 1, n do
        acc = acc + probs[idx[i]] / sum
        if acc >= topP then cut = i; break end
    end
    if cut < 1 then cut = 1 end
    -- 致命 bug 修复：idx[i] 是 1-based 的 logits 下标，
    -- 而 token id 空间是 0-based（embRow 用 id*cols、scales[id+1]，
    -- vocab[0] 是 <|endoftext|>）。实测 logits[1] == 参考 logits[0]。
    -- 不减 1 的话每个生成的 token 都偏一位，解码出来就是乱码。
    local r = rnd01() * acc
    local c = 0
    for i = 1, cut do
        c = c + probs[idx[i]] / sum
        if r <= c then return idx[i] - 1 end
    end
    return idx[cut] - 1
end

--==================== 分词器 ====================
local TOK = nil
local function loadTok()
    if TOK then return TOK end
    local ok, raw = pcall(function()
        return Inflater.inflate(b85Decode(TOK_PACKED), 3)
    end)
    if not ok or not raw or #raw == 0 then
        D("分词表解压失败")
        return nil
    end
    local p = string.find(raw, "\2", 1, true)
    local vs, ms = string.sub(raw, 1, p - 1), string.sub(raw, p + 1)
    local vocab = {}
    local pos = 1
    local id = 0
    while pos <= #vs do
        local nl = string.find(vs, "\n", pos, true)
        local line
        if nl then line = string.sub(vs, pos, nl - 1); pos = nl + 1
        else line = string.sub(vs, pos); pos = #vs + 1 end
        vocab[id] = line
        id = id + 1
    end
    local rank = {}
    pos = 1
    local rk = 0                 -- 显式计数器：不能用 #rank（rank 只有字符串键，
                                 -- # 的返回值是「序列部分长度」，恒为 0）
    while pos <= #ms do
        local nl = string.find(ms, "\n", pos, true)
        local line
        if nl then line = string.sub(ms, pos, nl - 1); pos = nl + 1
        else line = string.sub(ms, pos); pos = #ms + 1 end
        local sp = string.find(line, " ", 1, true)
        if sp then
            rank[string.sub(line, 1, sp - 1) .. "\1" .. string.sub(line, sp + 1)] = rk
            rk = rk + 1
        end
    end
    local rev = {}
    for k, v in pairs(vocab) do rev[v] = k end
    TOK = { vocab = vocab, rank = rank, rev = rev }
    return TOK
end

-- 字节 -> GPT2 字节级字符
local BYTE2CH = {}
do
    local bs = {}
    for b = 0, 255 do bs[b + 1] = b end
    -- GPT-2 的 bytes_to_unicode
    local n = 0
    local map = {}
    for b = 0, 255 do
        local c = b
        local ok = (b >= 33 and b <= 126) or (b >= 161 and b <= 172) or (b >= 174 and b <= 255)
        if ok then map[b] = b
        else map[b] = 256 + n; n = n + 1 end
    end
    for b = 0, 255 do
        local cp = map[b]
        -- 编码成 UTF-8
        local s
        if cp < 0x80 then s = string.char(cp)
        elseif cp < 0x800 then
            s = string.char(0xC0 + math.floor(cp / 64), 0x80 + (cp % 64))
        else
            s = string.char(0xE0 + math.floor(cp / 4096),
                            0x80 + (math.floor(cp / 64) % 64),
                            0x80 + (cp % 64))
        end
        BYTE2CH[string.char(b)] = s
    end
end
local CH2BYTE = {}
for k, v in pairs(BYTE2CH) do CH2BYTE[v] = k end

-- 简易预分词：字母串 / 数字串 / 空白 / 其它单字符
-- （GPT-2 用 \p{L} 正则，Lua 5.1 没有 Unicode 类；
--   把 >=0x80 的字节整体当作"字母"，中文连续串会被并为一块，与 GPT-2 一致）
local function preSplit(s)
    local out = {}
    local i = 1
    local n = #s
    while i <= n do
        local b = string.byte(s, i)
        local cls
        if (b >= 65 and b <= 90) or (b >= 97 and b <= 122) or b >= 0x80 then cls = 1
        elseif b >= 48 and b <= 57 then cls = 2
        elseif b == 32 or b == 9 or b == 10 or b == 13 then cls = 3
        else cls = 4 end
        -- 空白：连续一段
        if cls == 3 then
            local j = i
            while j <= n do
                local b2 = string.byte(s, j)
                if b2 == 32 or b2 == 9 or b2 == 10 or b2 == 13 then j = j + 1 else break end
            end
            -- 空白前缀合并到下一块（GPT-2 的 " ?\p{L}+"）
            local nx = j
            if nx <= n then
                local b3 = string.byte(s, nx)
                local cl3
                if (b3 >= 65 and b3 <= 90) or (b3 >= 97 and b3 <= 122) or b3 >= 0x80 then cl3 = 1
                elseif b3 >= 48 and b3 <= 57 then cl3 = 2
                else cl3 = 4 end
                if cl3 == 4 then
                    out[#out + 1] = string.sub(s, i, nx)
                    i = nx + 1
                else
                    local k = nx
                    while k <= n do
                        local b4 = string.byte(s, k)
                        local c4
                        if (b4 >= 65 and b4 <= 90) or (b4 >= 97 and b4 <= 122) or b4 >= 0x80 then c4 = 1
                        elseif b4 >= 48 and b4 <= 57 then c4 = 2
                        else c4 = 0 end
                        if c4 ~= cl3 then break end
                        k = k + 1
                    end
                    out[#out + 1] = string.sub(s, i, k - 1)
                    i = k
                end
            else
                out[#out + 1] = string.sub(s, i, j - 1)
                i = j
            end
        elseif cls == 4 then
            -- 标点：连续一段
            local j = i
            while j <= n do
                local b2 = string.byte(s, j)
                local c2
                if (b2 >= 65 and b2 <= 90) or (b2 >= 97 and b2 <= 122) or b2 >= 0x80 then c2 = 1
                elseif b2 >= 48 and b2 <= 57 then c2 = 2
                elseif b2 == 32 or b2 == 9 or b2 == 10 or b2 == 13 then c2 = 3
                else c2 = 4 end
                if c2 ~= 4 then break end
                j = j + 1
            end
            out[#out + 1] = string.sub(s, i, j - 1)
            i = j
        else
            local j = i
            while j <= n do
                local b2 = string.byte(s, j)
                local c2
                if (b2 >= 65 and b2 <= 90) or (b2 >= 97 and b2 <= 122) or b2 >= 0x80 then c2 = 1
                elseif b2 >= 48 and b2 <= 57 then c2 = 2
                else c2 = 0 end
                if c2 ~= cls then break end
                j = j + 1
            end
            out[#out + 1] = string.sub(s, i, j - 1)
            i = j
        end
    end
    return out
end

local function bpeChunk(chunk, tok)
    local rank = tok.rank
    local rev = tok.rev
    -- 先切成单字符
    local parts = {}
    local i = 1
    local n = #chunk
    while i <= n do
        local b = string.byte(chunk, i)
        local len = 1
        if b >= 0xF0 then len = 4 elseif b >= 0xE0 then len = 3
        elseif b >= 0xC0 then len = 2 end
        parts[#parts + 1] = string.sub(chunk, i, i + len - 1)
        i = i + len
    end
    while #parts > 1 do
        local bestR = nil
        local bestI = 0
        for k = 1, #parts - 1 do
            local r = rank[parts[k] .. "\1" .. parts[k + 1]]
            if r and (bestR == nil or r < bestR) then bestR = r; bestI = k end
        end
        if not bestR then break end
        local merged = parts[bestI] .. parts[bestI + 1]
        local t = {}
        for k = 1, bestI - 1 do t[#t + 1] = parts[k] end
        t[#t + 1] = merged
        for k = bestI + 2, #parts do t[#t + 1] = parts[k] end
        parts = t
    end
    local out = {}
    for k = 1, #parts do
        local id = rev[parts[k]]
        if id then out[#out + 1] = id
        else
            -- 回退：逐字节查
            local s = parts[k]
            local i2 = 1
            while i2 <= #s do
                local bb = string.byte(s, i2)
                local len = 1
                if bb >= 0xF0 then len = 4 elseif bb >= 0xE0 then len = 3 elseif bb >= 0xC0 then len = 2 end
                local cid = rev[string.sub(s, i2, i2 + len - 1)]
                if cid then out[#out + 1] = cid end
                i2 = i2 + len
            end
        end
    end
    return out
end

local function encode(s)
    local tok = loadTok()
    if not tok then return {} end
    -- 转成字节级字符空间
    local bs = {}
    for i = 1, #s do bs[i] = BYTE2CH[string.sub(s, i, i)] or "" end
    local mapped = table.concat(bs)
    local ids = {}
    for _, chunk in ipairs(preSplit(mapped)) do
        local r = bpeChunk(chunk, tok)
        for _, v in ipairs(r) do ids[#ids + 1] = v end
    end
    return ids
end

local function decodeIds(ids)
    local tok = loadTok()
    if not tok then return "" end
    local out = {}
    for _, id in ipairs(ids) do
        local s = tok.vocab[id]
        if s then
            local i = 1
            while i <= #s do
                local bb = string.byte(s, i)
                local len = 1
                if bb >= 0xF0 then len = 4 elseif bb >= 0xE0 then len = 3 elseif bb >= 0xC0 then len = 2 end
                local ch = string.sub(s, i, i + len - 1)
                out[#out + 1] = CH2BYTE[ch] or ""
                i = i + len
            end
        end
    end
    return table.concat(out)
end

--==================== 缓存 ====================
local CACHE = {}        -- key -> reply
local CACHE_Q = {}      -- LRU 顺序
local STAT = { hit = 0, miss = 0, gen = 0, genTokens = 0, genMs = 0 }

local function cacheGet(k)
    local v = CACHE[k]
    if v then
        STAT.hit = STAT.hit + 1
        return v
    end
    STAT.miss = STAT.miss + 1
    return nil
end
local function cachePut(k, v)
    local cap = math.floor(getNumProp("cacheSize", 2000))
    if cap <= 0 then return end
    if CACHE[k] == nil then
        CACHE_Q[#CACHE_Q + 1] = k
        while #CACHE_Q > cap do
            local old = table.remove(CACHE_Q, 1)
            CACHE[old] = nil
        end
    end
    CACHE[k] = v
end

--==================== 会话 ====================
local SESS = {}
local function getSess(sid)
    local s = SESS[sid]
    if not s then
        s = { turns = {}, st = nil, recentReplies = {}, lastKey = nil, sameCount = 0 }
        SESS[sid] = s
    end
    return s
end

--==================== 生成 ====================
-- 真实换行 token（实测 encode("\n") = 201）。
-- 之前用 id 0 占位，而 id 0 是 <|endoftext|>，等于往 prompt 里塞终止符。
local NL_ID = nil
local function nlId()
    if NL_ID then return NL_ID end
    local ids = encode("\n")
    NL_ID = (ids and ids[1]) or 201
    return NL_ID
end

local function doGenerate(sess, userText, boost)
    local m = loadModel()
    if not m then return nil end
    local cfg = m.cfg
    local maxCtx = math.floor(getNumProp("maxCtx", 256))
    if maxCtx > cfg.maxCtx then maxCtx = cfg.maxCtx end
    local maxTok = math.floor(getNumProp("maxTokens", 24))
    -- 0=纯续写 1=聊天模板(SFT/RLHF) 2=问答cue(默认，预训练权重实测最优)
    local mode = math.floor(getNumProp("promptMode", 2))
    local temp = getNumProp("temperature", 0.85)
    local tp = getNumProp("topP", 0.85)
    -- boost：玩家重复提问时抬高温度，逼模型换个说法
    if boost then
        temp = math.min(1.6, temp + boost)
        tp = math.min(0.98, tp + boost * 0.5)
    end

    -- 组 prompt：<|im_start|>user\n...<|im_end|>\n<|im_start|>assistant\n
    local IMS, IME = 1, 2
    local ids = {}
    local function push(t)
        if type(t) ~= "table" then return end
        for _, v in ipairs(t) do ids[#ids + 1] = v end
    end
    -- sess.turns 可能不存在（单轮调用或会话刚建），不能 ipairs(nil)
    local turns = (type(sess) == "table" and sess.turns) or {}

    -- 踩过的坑：分段 encode("问：") + encode(q) + encode("\n答：") 拼出来的
    -- BPE 序列，和 encode("问：xxx\n答：") 整串完全不同。实测整串拼好再
    -- 编码，模型才认得出这是问答格式；分段拼它会把提问当正文继续瞎续写。
    -- 所以三种模式都改成：先拼完整字符串，再一次性 encode。
    if mode == 1 then
        -- 聊天模板（SFT / RLHF / DPO 权重用这个）
        local buf = {}
        for _, tu in ipairs(turns) do
            buf[#buf + 1] = "user\n" .. tostring(tu[1] or "")
            buf[#buf + 1] = "assistant\n" .. tostring(tu[2] or "")
        end
        buf[#buf + 1] = "user\n" .. tostring(userText or "")
        buf[#buf + 1] = "assistant\n"
        for i, seg in ipairs(buf) do
            ids[#ids + 1] = IMS
            push(encode(seg))
            if i < #buf then ids[#ids + 1] = IME end
        end
    elseif mode == 2 then
        -- 问答 cue（预训练权重的实测最优解）
        -- 纯预训练模型没见过 <|im_start|>，直接问也是瞎续写；
        -- 「问：xxx\n答：」是语料里最常见的格式，引导效果最好。
        local buf = {}
        for _, tu in ipairs(turns) do
            buf[#buf + 1] = "问：" .. tostring(tu[1] or "") .. "\n答：" .. tostring(tu[2] or "")
        end
        buf[#buf + 1] = "问：" .. tostring(userText or "") .. "\n答："
        push(encode(table.concat(buf, "\n")))
    else
        -- 纯续写：拼历史 + 当前输入，不加特殊 token
        local buf = {}
        for _, tu in ipairs(turns) do
            buf[#buf + 1] = tostring(tu[1] or "")
            buf[#buf + 1] = tostring(tu[2] or "")
        end
        buf[#buf + 1] = tostring(userText or "")
        push(encode(table.concat(buf, "\n")))
    end

    if #ids > maxCtx then
        local cut = #ids - maxCtx
        local t = {}
        for i = cut + 1, #ids do t[#t - cut] = ids[i] end
        ids = t
    end

    -- KV 跨轮复用：多轮对话每轮都从头 prefill 一遍历史，第 N 轮要算 N 倍前向，
    -- 越聊越慢。这里缓存上一轮的 KV 状态，若新序列以它为前缀，
    -- 就只 prefill 新增的那几个 token。
    -- 注意：不能用"整条旧序列必须完全匹配"来判断。
    -- 上一轮存的是"生成出来的 id"，本轮是把回复解码成文本再重新编码，
    -- 两者常在句中某处就分叉。改取最长公共前缀 LCP：
    -- 因果注意力下，只要前 LCP 个 token 相同，这些位置的 KV 就依然有效。
    local st = sess.kvState
    local start = 1
    if st and sess.kvIds then
        local old = sess.kvIds
        local n = #old < #ids and #old or #ids
        local lcp = 0
        while lcp < n and old[lcp + 1] == ids[lcp + 1] do lcp = lcp + 1 end
        if lcp > 0 and lcp <= (st.pos or 0) then
            st.pos = lcp
            start = lcp + 1
        else
            st = nil
        end
    end
    if not st then st = newState(m) end

    local t0 = nowMs()
    local logits = nil
    for p = start, #ids do
        logits = forwardOne(st, ids[p], p - 1)
    end
    st.pos = #ids
    D(string.format("KV: 总%d token, 复用前缀%d, 本轮prefill %d", #ids, start-1, #ids-start+1))
    -- v8：统计"因前缀命中而省掉的前向次数"，这是 KV 复用真正的收益
    STAT.preSaved = (STAT.preSaved or 0) + (start - 1)
    STAT.preFwd = (STAT.preFwd or 0) + (#ids - start + 1)
    local preMs = nowMs() - t0
    -- 回复后处理：模型会一路续写下去（问：A 答：B 问：C 答：D...），
    -- 只保留第一段。实测不截断会出现「北京。\n答：这个词是地名...」这种尾巴。
    local function postReply(txt, md, q)
        if type(txt) ~= "string" then return "" end
        -- 按换行切，只留第一句（模型会一路续写问：A 答：B 问：C...）
        local nl = txt:find("\n", 1, true)
        if nl then txt = txt:sub(1, nl - 1) end
        if md == 2 then
            -- 续写出下一轮 cue 就掐掉
            for _, kw in ipairs({ "答：", "问：" }) do
                local k = txt:find(kw, 1, true)
                if k and k > 1 then txt = txt:sub(1, k - 1) end
            end
        end
        -- 复读机：回答里又冒出提问本身（如「中国的首都是」->「首都是北京。中国的首都是北京。」）
        -- 取提问末尾 4~8 字做锚，在非开头位置命中就截断。
        -- 注意：锚点必须按字符边界取。之前按字节切尾部 4~8 字节当锚，
        -- 会切在汉字中间产生非法序列，命中后截断把整条回答砍成乱码（实测踩过）。
        -- 只用完整提问串做锚，且要求命中位置 > 1（开头正常复述不算复读）。
        if type(q) == "string" and #q >= 6 then
            local k = txt:find(q, 2, true)
            if k and k > 1 then txt = txt:sub(1, k - 1) end
        end
        txt = txt:gsub("^%s+", ""):gsub("%s+$", "")
        return txt
    end
    local outIds = {}
    local v = cfg.vocab
    local rep = getNumProp("repPenalty", 1.15)
    local t1 = nowMs()
    -- 最近出现过的 token 计数，用于重复惩罚
    local seen = {}
    for _, id in ipairs(ids) do seen[id] = (seen[id] or 0) + 1 end
    local WIN = 32
    local recent = {}
    for _ = 1, maxTok do
        if rep > 1.0 and #recent > 0 then
            for _, rid in ipairs(recent) do
                local lg = logits[rid + 1]
                if lg then
                    -- 出现过的按次数降权（已出现则为负 log）
                    logits[rid + 1] = (lg < 0) and (lg * rep) or (lg / rep)
                end
            end
        end
        local nid = sample(logits, v, temp, tp)
        if nid == IME or nid == 0 or nid == nil then break end
        outIds[#outIds + 1] = nid
        recent[#recent + 1] = nid
        if #recent > WIN then table.remove(recent, 1) end
        if #ids >= maxCtx then break end
        logits = forwardOne(st, nid, #ids)
        ids[#ids + 1] = nid
    end
    st.pos = #ids
    sess.kvState = st
    sess.kvIds = ids
    local genMs = nowMs() - t1
    STAT.gen = STAT.gen + 1
    STAT.genTokens = STAT.genTokens + #outIds
    STAT.genMs = STAT.genMs + genMs + preMs
    D(string.format("生成: prefill %d token %.0fms, 输出 %d token %.0fms (%.0f ms/token)",
        #ids - start + 1, preMs, #outIds, genMs, (preMs + genMs) / math.max(1, #outIds)))
    local reply = decodeIds(outIds)
    reply = postReply(reply, mode, userText)
    if reply == "" then reply = nil end
    return reply
end

--####################################################################
--#  MiniMind 增强层 v6 · 智能路由 / 知识库 / Skills / 人设
--#
--#  路由顺序（从上到下，命中即返回）：
--#    L0  精确缓存      归一化后完全相等，零耗时
--#    L1  Skills        计算器(内置) / 时间 / 给东西 / 自制 LuaVM 技能
--#    L2  知识库        BM25 + bigram 倒排（不是简单命中）
--#    L3  模糊缓存      归一化 + 编辑距离，找回"换了个说法"的旧问答
--#    L4  模型生成      带人设 prompt + 上下文 + 知识注入
--#    L5  兜底接话      按意图分类，保证一定接得上话
--####################################################################

--==================== UTF-8 工具（Lua 5.1 没有 utf8 库）====================
local function _u8len(s)
    local n = 0; local i = 1; local L = #s
    while i <= L do
        local b = string.byte(s, i)
        local w = 1
        if b >= 0xF0 then w = 4 elseif b >= 0xE0 then w = 3 elseif b >= 0xC0 then w = 2 end
        i = i + w; n = n + 1
    end
    return n
end
local function _u8chars(s)
    local t = {}; local i = 1; local L = #s
    while i <= L do
        local b = string.byte(s, i)
        local w = 1
        if b >= 0xF0 then w = 4 elseif b >= 0xE0 then w = 3 elseif b >= 0xC0 then w = 2 end
        t[#t + 1] = string.sub(s, i, i + w - 1)
        i = i + w
    end
    return t
end

--==================== 文本归一化 ====================
local _PUNC = {
    ["。"]=1,["，"]=1,["、"]=1,["；"]=1,["："]=1,["？"]=1,["！"]=1,
    ["？"]=1,["！"]=1,["“"]=1,["”"]=1,["‘"]=1,["’"]=1,["（"]=1,["）"]=1,
    ["《"]=1,["》"]=1,["…"]=1,["—"]=1,["·"]=1,["　"]=1,[" "]=1,["\t"]=1,
    ["?"]=1,["!"]=1,[","]=1,["."]=1,[";"]=1,[":"]=1,["'"]=1,["\""]=1,
    ["("]=1,[")"]=1,["["]=1,["]"]=1,["{"]=1,["}"]=1,["-"]=1,["_"]=1,["~"]=1,
}
local function _norm(s)
    if type(s) ~= "string" then return "" end
    local t = {}
    for _, c in ipairs(_u8chars(s)) do
        if not _PUNC[c] then t[#t + 1] = c end
    end
    return (table.concat(t))
end
-- 结尾语气词剥离（吗/呢/啊/呀/吧/哇/哦/哈）+ 全角转半角数字
local _MOOD = { ["吗"]=1,["呢"]=1,["啊"]=1,["呀"]=1,["吧"]=1,["哇"]=1,["哦"]=1,["哈"]=1,["嘛"]=1,["喽"]=1 }
local function _stripMood(s)
    local cs = _u8chars(s)
    while #cs > 2 and _MOOD[cs[#cs]] do cs[#cs] = nil end
    return table.concat(cs)
end

--==================== 编辑距离（Levenshtein，按字符）====================
local function _lev(a, b)
    local la, lb = _u8len(a), _u8len(b)
    if la == 0 then return lb end
    if lb == 0 then return la end
    if la > 60 or lb > 60 then return 999 end   -- 太长不比，防卡
    local ca, cb = _u8chars(a), _u8chars(b)
    local prev = {}
    for j = 0, lb do prev[j] = j end
    for i = 1, la do
        local cur = {}
        cur[0] = i
        for j = 1, lb do
            local cost = (ca[i] == cb[j]) and 0 or 1
            local d1 = prev[j] + 1
            local d2 = cur[j - 1] + 1
            local d3 = prev[j - 1] + cost
            local m = d1
            if d2 < m then m = d2 end
            if d3 < m then m = d3 end
            cur[j] = m
        end
        prev = cur
    end
    return prev[lb]
end

--==================== 知识库 · BM25 + bigram 倒排 ====================
-- 为什么不用"简单命中"：
--   精确匹配 → "怎么合成钻石剑" 和 "钻石剑怎么合成" 完全不命中
--   前缀匹配 → "给我讲讲附魔" 和 "附魔是什么" 也不命中
-- 所以用 bigram 倒排 + BM25：字面粒度召回，统计权重排序，覆盖率兜底。
local _KB = {
    docs = {},        -- {id=, q=, a=, grams={g->tf}, len=, tag=}
    df = {},          -- gram -> 出现过的文档数
    inv = {},         -- gram -> {docId,...}
    avgLen = 0,
    nextId = 1,
}
local _KB_K1, _KB_B = 1.4, 0.72
local _KB_MINSCORE = 2.2      -- 低于此分视为没命中，交给模型
local _KB_MINCOVER = 0.34     -- 查询 gram 覆盖率低于此值，分数打折

local function _grams(s)
    -- 中文按字 bigram；英文/数字按词
    local cs = _u8chars(_norm(s))
    local out = {}
    local i = 1
    while i <= #cs do
        local a, b = cs[i], cs[i + 1]
        local isAscii = (#a == 1 and a:byte() < 128)
        if isAscii then
            -- 英文数字：连续读成一个 token
            local w = {}
            while i <= #cs do
                local c = cs[i]
                if #c == 1 and (c:byte() < 128) and c:match("[%w]") then
                    w[#w + 1] = c; i = i + 1
                else break end
            end
            if #w > 0 then out[#out + 1] = table.concat(w) end
        else
            if b then out[#out + 1] = a .. b else out[#out + 1] = a end
            i = i + 1
        end
    end
    return out
end

local function _kbAdd(q, a, tag)
    if type(q) ~= "string" or type(a) ~= "string" then return nil end
    if q == "" or a == "" then return nil end
    local g = _grams(q .. " " .. a)
    if #g == 0 then return nil end
    local tf = {}
    for _, x in ipairs(g) do tf[x] = (tf[x] or 0) + 1 end
    local id = _KB.nextId
    _KB.nextId = _KB.nextId + 1
    _KB.docs[id] = { id = id, q = q, a = a, grams = tf, len = #g, tag = tag or "" }
    for x in pairs(tf) do
        if not _KB.inv[x] then _KB.inv[x] = {}; _KB.df[x] = 0 end
        _KB.inv[x][#_KB.inv[x] + 1] = id
        _KB.df[x] = _KB.df[x] + 1
    end
    local tot = 0
    for _, d in pairs(_KB.docs) do tot = tot + d.len end
    local n = 0
    for _ in pairs(_KB.docs) do n = n + 1 end
    _KB.avgLen = (n > 0) and (tot / n) or 0
    return id
end

local function _kbSearch(query, topN)
    local qg = _grams(query)
    if #qg == 0 then return {} end
    local N = 0
    for _ in pairs(_KB.docs) do N = N + 1 end
    if N == 0 then return {} end

    -- 召回：含任一查询 gram 的文档
    local cand, seen = {}, {}
    for _, x in ipairs(qg) do
        local lst = _KB.inv[x]
        if lst then
            for _, id in ipairs(lst) do
                if not seen[id] then seen[id] = 1; cand[#cand + 1] = _KB.docs[id] end
            end
        end
    end
    if #cand == 0 then return {} end

    -- BM25 打分 + 覆盖率
    local avg = (_KB.avgLen > 0) and _KB.avgLen or 1
    local res = {}
    for _, d in ipairs(cand) do
        local score = 0
        local matched = 0
        local qseen = {}
        for _, x in ipairs(qg) do
            if not qseen[x] then
                qseen[x] = 1
                local tf = d.grams[x]
                if tf then
                    matched = matched + 1
                    local df = _KB.df[x] or 0
                    local idf = math.log(1 + (N - df + 0.5) / (df + 0.5))
                    if idf < 0 then idf = 0 end
                    score = score + idf * (tf * (_KB_K1 + 1)) /
                            (tf + _KB_K1 * (1 - _KB_B + _KB_B * d.len / avg))
                end
            end
        end
        local cover = matched / #qg
        -- 问题字段额外加权：问句里直接命中的更可信
        local qg2 = _grams(d.q)
        local qset = {}
        for _, x in ipairs(qg2) do qset[x] = 1 end
        local qHit = 0
        for _, x in ipairs(qg) do if qset[x] then qHit = qHit + 1 end end
        score = score + (qHit / #qg) * 1.8
        if cover < _KB_MINCOVER then score = score * (cover / _KB_MINCOVER) * 0.55 end
        -- 短文档（问答对）轻微偏好，抑制长条目霸榜
        if d.len > 0 then score = score * (1 + 0.12 / math.log(1 + d.len)) end
        res[#res + 1] = { doc = d, score = score, cover = cover }
    end
    table.sort(res, function(a, b) return a.score > b.score end)
    local out = {}
    for i = 1, math.min(topN or 3, #res) do out[#out + 1] = res[i] end
    return out
end

--==================== 内置知识（可增量覆盖）====================
local _BUILTIN_KB = {
    { "你好", "你好呀，有什么可以帮你的吗" },
    { "你是谁", "我是元宝，腾讯开发的AI助手，现在住在这个地图里陪你玩" },
    { "你叫什么名字", "我叫元宝，你可以直接喊我元宝" },
    { "谢谢", "不客气，随时找我" },
    { "再见", "拜拜，下次再聊" },
    { "现在几点了", "[SKILL:time]" },
    { "今天星期几", "[SKILL:weekday]" },
    { "你是AI吗", "是的，我是AI，不过我尽量说人话" },
    { "你会做什么", "我能聊天、回答问题、算数、查时间，还能按人设切换说话风格" },
}
local function _initKB()
    for _, kv in ipairs(_BUILTIN_KB) do _kbAdd(kv[1], kv[2], "内置") end
end

--==================== Skills 系统 ====================
-- 每个 skill: { name, desc, match(text)->true/false, run(text, sess)->string }
-- 内置：calc(计算) / time(时间) / weekday / date
-- 用户可通过 RegisterSkill 注入 Lua 源码（走 LuaVM 桥接，若环境里有）
local _SKILLS = {}
local _SKILL_ORDER = {}

local function _regSkill(name, desc, match, run)
    if not _SKILLS[name] then _SKILL_ORDER[#_SKILL_ORDER + 1] = name end
    _SKILLS[name] = { name = name, desc = desc, match = match, run = run, builtin = true }
end

-- ---- 中文数学词 → 表达式（必须在抠算式之前做，否则"3的平方"会被剥成"3"）----
local _MATHF = {
    -- 覆盖 math 里语义不符中文习惯的少数函数
    log  = function(x, b) if b then return math.log(x) / math.log(b) end return math.log(x) / math.log(10) end,
    ln   = function(x) return math.log(x) end,
    lg   = function(x) return math.log(x) / math.log(10) end,
    abs  = math.abs,  sqrt = math.sqrt,
    sin  = math.sin,  cos = math.cos,  tan = math.tan,
    asin = math.asin, acos = math.acos, atan = math.atan,
    exp  = math.exp,  floor = math.floor, ceil = math.ceil,
    max  = math.max,  min = math.min,
    rad  = math.rad,  deg = math.deg,
    fact = function(n)
        n = math.floor(tonumber(n) or 0)
        if n < 0 then error("负数没有阶乘") end
        if n > 170 then error("阶乘太大") end
        local r = 1
        for i = 2, n do r = r * i end
        return r
    end,
}
local _MATH_NAMES = {"asin","acos","atan","sqrt","abs","fact","floor","ceil","max","min","exp","rad","deg","log","ln","lg","sin","cos","tan","pow"}
local function _mathNormalize(t)
    local s = tostring(t or "")
    -- 全角 → 半角
    local map0 = { ["＋"]="+",["－"]="-",["＊"]="*",["／"]="/",["（"]="(",["）"]=")",
                   ["×"]="*",["÷"]="/",["％"]="%",["＾"]="^",["．"]=".",["　"]=" ",
                   ["，"]=",",["。"]=".",["＝"]="=",["的"]="的" }
    for k, v in pairs(map0) do s = s:gsub(k, v) end
    -- 根号 / 开方 / √
    s = s:gsub("√%s*([%d%.]+)", "sqrt(%1)")
    s = s:gsub("根号%s*([%d%.]+)", "sqrt(%1)")
    s = s:gsub("([%d%.]+)%s*的开方", "sqrt(%1)")
    s = s:gsub("开方%s*([%d%.]+)", "sqrt(%1)")
    -- X的平方 / X的立方 / X的N次方 / X的阶乘
    s = s:gsub("([%d%.]+)%s*的平方", "(%1)^2")
    s = s:gsub("([%d%.]+)%s*的立方", "(%1)^3")
    s = s:gsub("([%d%.]+)%s*的(%d+)次方", "(%1)^(%2)")
    s = s:gsub("([%d%.]+)%s*的阶乘", "fact(%1)")
    s = s:gsub("阶乘%s*([%d%.]+)", "fact(%1)")
    -- 绝对值
    s = s:gsub("绝对值%s*([%d%.%-]+)", "abs(%1)")
    s = s:gsub("|%s*([%d%.%-]+)%s*|", "abs(%1)")
    -- 百分比："100的20%" → 100*20/100
    s = s:gsub("([%d%.]+)%s*的%s*([%d%.]+)%s*%%", "(%1)*(%2)/100")
    -- 三角函数名后直接跟数字（sin30）补括号：注意只在确认是函数名时做
    for _, fn in ipairs(_MATH_NAMES) do s = s:gsub(fn .. "%s*([%d%.]+)", fn .. "(%1)") end
    -- π / Π / "派" → pi；"数字π" → "数字*pi"
    s = s:gsub("π", "pi"):gsub("Π", "pi")
    if s:find("派") and (s:find("%d")
        or s:find("多少") or s:find("是几") or s:find("等于")
        or s:find("的值") or s:find("算") or s:find("π")) then
        s = s:gsub("([%d%.%)])%s*派", "%1*pi")
        s = s:gsub("派%s*([%d%.%(])", "pi*%1")
        s = s:gsub("派", "pi")
    end
    if s:find("自然常数") or s:find("欧拉") then s = s:gsub("自然常数", "(e)"):gsub("欧拉数", "(e)") end
    -- 数字紧跟 pi / e 时补乘号：2pi → 2*pi，3e → 3*e
    s = s:gsub("([%d%.%)])%s*pi", "%1*pi")
    s = s:gsub("([%d%.%)])%s*e%s*([%+%-%*%/%)%^])", "%1*e%2")
    return s
end
-- 是否含数学意味（函数名 or 中文数学词）
local function _hasMathWord(t)
    local s = tostring(t or "")
    if s:find("sqrt") or s:find("abs") or s:find("fact") then return true end
    for w in ("sin cos tan asin acos atan log ln lg exp floor ceil max min rad deg pow"):gmatch("%a+") do
        if s:find(w, 1, true) then return true end
    end
    for _, w in ipairs({ "根号", "开方", "平方", "立方", "次方", "阶乘", "绝对值", "对数" }) do
        if s:find(w, 1, true) then return true end
    end
    return false
end

-- ---- 安全表达式求值器（不用 loadstring：实测返回 nil）----
-- 递归下降 parser，只认数字/运算符/括号/math 函数/常量。
local function _calcEval(src)
    local s = _mathNormalize(src)
    -- 全角转半角
    local map = { ["＋"]="+",["－"]="-",["＊"]="*",["／"]="/",["（"]="(",["）"]=")",
                  ["×"]="*",["÷"]="/",["％"]="%",["＾"]="^",["．"]=".",["　"]=" " }
    for k, v in pairs(map) do s = s:gsub(k, v) end
    s = s:gsub("√(%d+%.?%d*)", "sqrt(%1)")
    s = s:gsub("√", "sqrt")
    local pos = 1
    local function err(m) error(m, 0) end
    local function skip()
        while pos <= #s and s:sub(pos, pos):match("%s") do pos = pos + 1 end
    end
    local function parseExpr(lvl)
        skip()
        -- 一元
        if s:sub(pos, pos) == "-" then pos = pos + 1; return -parseExpr(3) end
        if s:sub(pos, pos) == "+" then pos = pos + 1; return parseExpr(3) end
        local left
        local c = s:sub(pos, pos)
        if c == "(" then
            pos = pos + 1
            left = parseExpr(0)
            skip()
            if s:sub(pos, pos) ~= ")" then err("缺右括号") end
            pos = pos + 1
        elseif s:sub(pos, pos + 4) == "math." then
            pos = pos + 5
            local fname = s:match("^(%a[%w_]*)", pos)
            if not fname then err("函数名缺失") end
            pos = pos + #fname
            local f = _MATHF[fname] or math[fname]
            if type(f) ~= "function" then err("不支持的函数 math." .. tostring(fname)) end
            skip()
            if s:sub(pos, pos) ~= "(" then err("函数缺括号") end
            pos = pos + 1
            local args = {}
            if s:sub(pos, pos) ~= ")" then
                while true do
                    args[#args + 1] = parseExpr(0)
                    skip()
                    if s:sub(pos, pos) == "," then pos = pos + 1
                    elseif s:sub(pos, pos) == ")" then break
                    else err("参数列表错误") end
                end
            end
            pos = pos + 1
            left = f(unpack(args))
        elseif s:match("^%a", pos) then
            local nm = s:match("^(%a[%w_]*)", pos)
            pos = pos + #nm
            local const = { pi = math.pi, e = math.exp(1), ["true"]=1, ["false"]=0 }
            if const[nm] == nil then
                local f = _MATHF[nm] or math[nm]
                if type(f) == "function" then
                    skip()
                    if s:sub(pos, pos) == "(" then
                        pos = pos + 1
                        local args = {}
                        if s:sub(pos, pos) ~= ")" then
                            while true do
                                args[#args + 1] = parseExpr(0)
                                skip()
                                if s:sub(pos, pos) == "," then pos = pos + 1
                                elseif s:sub(pos, pos) == ")" then break
                                else err("参数列表错误") end
                            end
                        end
                        pos = pos + 1
                        left = f(unpack(args))
                    else
                        err("未知名字 " .. nm)
                    end
                else
                    err("未知名字 " .. nm)
                end
            else
                left = const[nm]
            end
        else
            local num = s:match("^%d+%.?%d*", pos) or s:match("^%.%d+", pos)
            if not num then err("位置 " .. pos .. " 不是数字: " .. s:sub(pos, pos + 4)) end
            pos = pos + #num
            left = tonumber(num)
        end
        while true do
            skip()
            local op = s:sub(pos, pos)
            local nl = 0
            if op == "^" then nl = 5
            elseif op == "*" or op == "/" or op == "%" then nl = 2
            elseif op == "+" or op == "-" then nl = 1
            else break end
            if nl <= lvl then break end
            pos = pos + 1
            local right = parseExpr(nl)
            if op == "^" then left = left ^ right
            elseif op == "*" then left = left * right
            elseif op == "/" then if right == 0 then err("除零") end; left = left / right
            elseif op == "%" then if right == 0 then err("取模零") end; left = left % right
            elseif op == "+" then left = left + right
            elseif op == "-" then left = left - right end
        end
        return left
    end
    local ok, r = pcall(function()
        local v = parseExpr(0)
        skip()
        if pos <= #s then err("尾部有多余内容: " .. s:sub(pos)) end
        return v
    end)
    if not ok then return nil, tostring(r) end
    return r, nil
end

-- 判断是否为算式：含数字 + 运算符/函数
local function _isCalcExpr(t)
    if type(t) ~= "string" then return false end
    -- 单独问常量值："π是多少""e等于多少""派是几"
    if (t:find("π") or t:find("派") or t:find("欧拉") or t:find("自然常数")
        or t:match("^%s*e%s*[%=是等于]") or t:match("^%s*e%s*$"))
        and (t:find("多少") or t:find("等于") or t:find("是几") or t:find("多长") or t:find("算")) then
        return true
    end
    local hasNum = t:find("%d") ~= nil
    if not hasNum then return false end
    local ops = t:find("[%+%-*/%^%%]") ~= nil
    local cjk = 0
    for _, c in ipairs(_u8chars(t)) do
        if #c >= 3 then cjk = cjk + 1 end
    end
    -- 中文太多（像"帮我算一下100加50"里的说明文字）要先剥
    local mw = _hasMathWord(t)
    if cjk > 6 and not ops and not mw then return false end
    return ops or mw or t:find("^%s*[%d%(%.]") ~= nil or t:find("算") ~= nil
end
local function _extractExpr(t)
    -- 从"帮我算 1+2*3 等于多少"里抠出算式
    -- 先归一化中文数学词：3的平方→(3)^2、根号16→sqrt(16)，否则汉字会被剥掉只剩"3"
    local s = _mathNormalize(t)
    s = s:gsub("[我你帮算一下请问等于多少是几结果]?", "")
    s = s:gsub("计算", ""):gsub("等于", ""):gsub("多少", ""):gsub("结果", "")
    s = s:gsub("^%s+", ""):gsub("%s+$", "")
    -- 取最长的一段含数字且像算式的片段
    local best, blen = "", 0
    for w in s:gmatch("[%d%.%+%-%*/%^%%%()%a%s]+") do
        local x = w:gsub("^%s+", ""):gsub("%s+$", "")
        if x:find("%d") and #x > blen then best, blen = x, #x end
    end
    if blen == 0 then return s end
    return best
end

local function _fmtNum(v)
    if type(v) ~= "number" then return tostring(v) end
    if v ~= v then return "结果无意义" end
    if v == math.floor(v) and math.abs(v) < 1e15 then return tostring(math.floor(v)) end
    local s = string.format("%.6f", v)
    s = s:gsub("0+$", ""):gsub("%.$", "")
    return s
end

-- ---- 内置 skill: 计算 ----
_regSkill("calc", "数学计算（默认内置）", function(t)
    return _isCalcExpr(t) or (t:find("算") ~= nil and t:find("%d") ~= nil)
end, function(t)
    local expr = _extractExpr(t)
    local v, e = _calcEval(expr)
    if v == nil then return nil end
    return _fmtNum(v)
end)

-- ---- 内置 skill: 时间 ----
local _WEEK = { "日", "一", "二", "三", "四", "五", "六" }
_regSkill("time", "查询当前时间", function(t)
    -- "现在几月" 是问日期不是问时刻，别抢在 date 前面
    if t:find("几月") or t:find("几号") or t:find("几日") or t:find("年月日")
       or t:find("日期") or t:find("多少号") then return false end
    return t:find("几点") ~= nil or t:find("时间") ~= nil or t:find("现在") ~= nil
end, function(t)
    if t:find("星期") or t:find("周几") then return nil end
    local ok, s = pcall(function() return os.date("%H:%M") end)
    if ok and s then return "现在是 " .. s end
    return nil
end)
_regSkill("weekday", "查询星期", function(t)
    -- 带具体日期（"2024年5月1日是星期几"）是推算题，别拿"今天"糊弄
    if t:match("%d+%s*年%s*%d+%s*月") or t:match("%d+%s*月%s*%d+%s*日")
       or t:match("%d+%s*[%-/]%s*%d+%s*[%-/]%s*%d+") then return false end
    return t:find("星期") ~= nil or t:find("周几") ~= nil or t:find("礼拜") ~= nil
end, function(t)
    local ok, w = pcall(function() return tonumber(os.date("%w")) end)
    if ok and w then return "今天是星期" .. (_WEEK[w + 1] or "?") end
    return nil
end)
_regSkill("date", "查询日期", function(t)
    return t:find("几号") ~= nil or t:find("日期") ~= nil or t:find("今天是什么日子") ~= nil
        or t:find("几月几日") ~= nil or t:find("几月几号") ~= nil
        or t:find("年月日") ~= nil or t:find("年月") ~= nil
        or t:find("多少号") ~= nil or t:find("什么日子") ~= nil
        or t:find("今天几") ~= nil or t:find("哪一天") ~= nil or t:find("哪天") ~= nil
        or t:find("几月") ~= nil or t:find("几日") ~= nil
end, function(t)
    -- 句子里带具体年月日（"2024年5月1日是星期几"）是推算题，让给 datecalc
    if t:match("%d+%s*年%s*%d+%s*月") or t:match("%d+%s*[%-/]%s*%d+%s*[%-/]%s*%d+")
       or (t:find("星期") ~= nil and t:match("%d+%s*月%s*%d+%s*日")) then return nil end
    local ok, s = pcall(function() return os.date("%Y年%m月%d日") end)
    if not (ok and s) then return nil end
    local w = tonumber(os.date("%w")) or 0
    local wk = _WEEK[w + 1] or "?"
    -- 只问月份 / 只问号数 时给短答案，问全就给全
    if t:find("几月") and not t:find("几号") and not t:find("几日") then
        return "现在是 " .. os.date("%Y年%m月")
    end
    if (t:find("几号") or t:find("多少号")) and not t:find("几月") and not t:find("年月") then
        return "今天是 " .. os.date("%d") .. "号"
    end
    return "今天是 " .. s .. "，星期" .. wk
end)

-- ---- 内置 skill: 日期推算（星期几 / 相隔天数） ----
-- os.date 只能问"今天"，这里自己算任意日期。days_from_civil 算法，
-- 纯整数运算，不依赖 os.time（迷你世界环境 os.time 行为不保证）。
local function _daysFromCivil(y, m, d)
    y = math.floor(y)
    -- 关键：1、2月要按"上一年的第 13、14 个月"算（Hinnant 算法的 y -= m<=2）
    -- 漏了这一行的表现是：只有 1/2 月和跨 2 月 29 日的日期会整体错 365 天
    if m <= 2 then y = y - 1 end
    local era = math.floor((y >= 0 and y or y - 399) / 400)
    local yoe = y - era * 400
    local mp = (m > 2) and (m - 3) or (m + 9)
    local doy = math.floor((153 * mp + 2) / 5) + d - 1
    local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
    return era * 146097 + doe - 719468
end
local function _weekdayOf(y, m, d)
    -- 1970-01-01 是星期四 → (days + 4) % 7，0=周日
    return (_daysFromCivil(y, m, d) + 4) % 7
end
local function _todayYMD()
    return tonumber(os.date("%Y")), tonumber(os.date("%m")), tonumber(os.date("%d"))
end
_regSkill("datecalc", "日期推算（星期几/相隔天数）", function(t)
    if not t:find("%d") then return false end
    return (t:find("星期") ~= nil or t:find("周几") ~= nil or t:find("礼拜") ~= nil
            or t:find("还有多少天") ~= nil or t:find("距离") ~= nil
            or t:find("相隔") ~= nil or t:find("过了多少天") ~= nil
           or t:find("已经过去") ~= nil or t:find("过去了") ~= nil
           or t:find("过了") ~= nil or t:find("还有几天") ~= nil
           or t:find("还有多久") ~= nil or t:find("距今") ~= nil)
           and (t:find("年") ~= nil or t:find("月") ~= nil or t:find("日") ~= nil
                or t:find("号") ~= nil or t:find("%-") ~= nil or t:find("/") ~= nil)
end, function(t)
    local y, m, d = t:match("(%d+)%s*年%s*(%d+)%s*月%s*(%d+)")
    if not y then y, m, d = t:match("(%d+)%s*[%-/]%s*(%d+)%s*[%-/]%s*(%d+)") end
    local ty, tm, td = _todayYMD()
    if not y then
        -- 只有月日：补当前年（若已过去则算下一年）
        m, d = t:match("(%d+)%s*月%s*(%d+)")
        if not m then return nil end
        y = ty
        if _daysFromCivil(y, m + 0, d + 0) < _daysFromCivil(ty, tm, td) then y = ty + 1 end
    end
    y, m, d = y + 0, m + 0, d + 0
    if m < 1 or m > 12 or d < 1 or d > 31 then return nil end
    local wd = _weekdayOf(y, m, d)
    local diff = _daysFromCivil(y, m, d) - _daysFromCivil(ty, tm, td)
    if t:find("星期") or t:find("周几") or t:find("礼拜") then
        return string.format("%d年%d月%d日是星期%s", y, m, d, _WEEK[wd + 1] or "?")
    end
    if diff == 0 then return string.format("%d年%d月%d日就是今天", y, m, d) end
    if diff > 0 then
        return string.format("距离%d年%d月%d日还有%d天（那天是星期%s）",
            y, m, d, diff, _WEEK[wd + 1] or "?")
    end
    return string.format("%d年%d月%d日已经过去%d天了（那天是星期%s）",
        y, m, d, -diff, _WEEK[wd + 1] or "?")
end)

-- ---- 宿主能力探测：给东西 / 查坐标 等 ----
-- 这些依赖游戏 API 是否存在，运行时探测，不存在就自动不注册。
local function _hostHas(mod, fn)
    local ok, r = pcall(function()
        local m = _G[mod]
        if type(m) ~= "table" then return false end
        return type(m[fn]) == "function"
    end)
    return ok and r
end
local function _tryLoadHostSkills()
    -- 给东西：Backpack.AddItem / Player.AddItem 等，按环境里实际有的来
    local give = nil
    if _hostHas("Backpack", "AddItem") then
        give = function(who, item, n) return Backpack:AddItem(who, item, n) end
    elseif _hostHas("Backpack", "AddItemByID") then
        give = function(who, item, n) return Backpack:AddItemByID(who, item, n) end
    end
    if give then
        _regSkill("give", "给玩家物品", function(t)
            return (t:find("给我") ~= nil or t:find("给我来") ~= nil or t:find("给我发") ~= nil)
                   and t:find("个") ~= nil
        end, function(t, sess)
            return nil   -- 需要参数解析，由 RegisterSkill 示例覆盖
        end)
    end
end

-- ---- LuaVM 桥接：自制 skill ----
-- 若环境里挂了 LuaVM（自写编译器+VM 的桥接组件），就能把 Lua 源码
-- 注册成 skill。loadstring 实测返回 nil，这是唯一能执行字符串代码的路径。
local function _vmAvailable()
    local ok, v = pcall(function() return _G.LuaVM end)
    if not ok or type(v) ~= "table" then return nil end
    if type(v.Define) == "function" or type(v.Compile) == "function" then return v end
    return nil
end
local _VM_SKILLS = {}   -- name -> {src, fn}
local function _vmRegister(name, luaSource)
    local vm = _vmAvailable()
    if not vm then
        return false, "未检测到 LuaVM。请先导入 LuaVM 桥接组件（它会把自身挂到 _G.LuaVM）"
    end
    local ok, fn = pcall(function()
        -- 桥接组件约定：Define(name, src) 注册，Call(name, ...) 调用
        if type(vm.Define) == "function" then
            vm.Define(name, luaSource)
            return function(...) return vm.Call(name, ...) end
        end
        -- 退化：只用编译+运行
        if type(vm.Compile) == "function" and type(vm.RunBC) == "function" then
            local bc = vm.Compile(luaSource)
            return function(...) return vm.RunBC(bc, ...) end
        end
        error("LuaVM 接口不匹配")
    end)
    if not ok then return false, tostring(fn) end
    _VM_SKILLS[name] = { src = luaSource, fn = fn }
    _regSkill(name, "LuaVM 自制技能", function() return true end, function(t, sess)
        local ok2, r = pcall(fn, t, sess)
        if ok2 and r ~= nil then return tostring(r) end
        return nil
    end)
    return true, "已注册 LuaVM 技能: " .. tostring(name)
end

--==================== 人设（按会话ID切换）====================
-- sessionId 格式： "人设名::会话名"  → 人设=人设名，会话=会话名
--                 或纯字符串        → 人设=默认，会话=该串
local _PERSONAS = {}
local function _defPersona(key, name, style, extra)
    _PERSONAS[key] = {
        key = key, name = name or key,
        style = style or "",
        extra = extra or "",
    }
end
_defPersona("默认", "元宝", "友好、简洁、说人话", "")
_defPersona("元宝", "元宝", "友好、简洁、说人话", "")
_defPersona("向导", "向导", "耐心、详细、爱举例子", "回答时多用具体步骤")
_defPersona("商人", "商人", "精明、简短、爱谈价格", "涉及物品时提一句价值")
_defPersona("战士", "战士", "粗犷、直接、话不多", "")
_defPersona("学者", "学者", "严谨、书面、爱补充背景", "")
_defPersona("猫娘", "猫娘", "可爱、撒娇、句尾带喵", "回答里偶尔加个「喵」")

local function _splitSid(sid)
    local s = tostring(sid or "default")
    local p = s:find("::", 1, true)
    if p then
        return s:sub(1, p - 1), s:sub(p + 2)
    end
    -- 没有 :: 时，如果整串是已知人设名，就当人设用（会话同名）
    if _PERSONAS[s] then return s, s end
    return "默认", s
end
local function _getPersona(sid)
    local pk = _splitSid(sid)
    return _PERSONAS[pk] or _PERSONAS["默认"], pk
end

-- 按人设包装回复
local function _applyPersona(txt, persona)
    if type(txt) ~= "string" or txt == "" then return txt end
    local k = persona.key
    if k == "猫娘" then
        if txt:sub(-3) ~= "喵" and txt:sub(-3) ~= "～" then
            txt = txt .. "，喵"
        end
    elseif k == "战士" then
        txt = txt:gsub("吗？", "！")
        txt = txt:gsub("吗?", "！")
        txt = txt:gsub("呢？", "。")
    elseif k == "商人" then
        -- 不加冗余，保持简短
    end
    return txt
end

--==================== 意图识别 + 兜底接话 ====================
-- 目标：模型没答上来时，也必须接得住话，不能回"我不知道"。
local function _intent(t)
    local s = _norm(t)
    if s:find("你好") or s:find("您好") or s:find("嗨") or s:find("在吗") or s:find("早上好") or s:find("晚上好") then return "greet" end
    if s:find("再见") or s:find("拜拜") or s:find("走了") or s:find("下次") then return "bye" end
    if s:find("谢谢") or s:find("感谢") or s:find("多谢") then return "thanks" end
    if s:find("对不起") or s:find("抱歉") then return "sorry" end
    if s:find("你是谁") or s:find("你叫什么") or s:find("你的名字") then return "who" end
    if s:find("会做什么") or s:find("能做什么") or s:find("有什么用") or s:find("怎么用") then return "ability" end
    if s:find("厉害") or s:find("牛") or s:find("不错") or s:find("很好") or s:find("真棒") or s:find("优秀") then return "praise" end
    if s:find("垃圾") or s:find("太差") or s:find("不行") or s:find("好慢") or s:find("好卡") or s:find("讨厌") then return "complaint" end
    if s == "好的" or s == "好" or s == "行" or s == "可以" or s == "嗯" or s == "嗯嗯" or s == "对的" or s == "是的" or s == "ok" then return "confirm" end
    if s:find("天气") or s:find("下雨") or s:find("晴天") or s:find("气温") then return "weather" end
    if s:find("吗") or s:find("呢") or s:find("什么") or s:find("为什么") or s:find("怎么") or
       s:find("谁") or s:find("哪") or s:find("几") or s:find("?") or s:find("？") then return "question" end
    if s:find("给我") or s:find("帮我") or s:find("我要") or s:find("来个") or s:find("做一个") then return "command" end
    return "statement"
end

local _FALLBACK = {
    greet    = { "嗯，我在，你说", "嗨，聊点什么", "在呢，怎么啦" },
    bye      = { "好，那回头聊", "拜拜，有需要再来", "嗯，先这样，下次接着聊" },
    thanks   = { "不客气", "小事一桩", "没事儿，随时找我" },
    sorry    = { "没事", "不用放在心上", "没关系，继续聊" },
    who      = { "我是元宝，你的AI搭子", "元宝，负责陪你聊天办事的", "我是元宝，有什么尽管问" },
    ability  = { "我能聊天、回答问题、算数、查时间，也能按人设换风格",
                 "问问题、算个数、查时间都行，你随便试",
                 "陪聊、答疑、算数、查时间，还有查知识库" },
    praise   = { "哈哈，谢谢夸奖", "过奖啦，我还得继续努力", "嘿嘿，那我再接再厉" },
    complaint= { "抱歉啦，哪儿不对你指出来，我改",
                 "嗯，是我没做好，你再说具体点",
                 "别急，告诉我卡在哪儿了" },
    confirm  = { "好嘞", "嗯，那就这么定了", "行，继续" },
    weather  = { "天气我这边查不到实时数据，得联网才行",
                 "这个要实时天气接口，我现在连不上，换个问题吧" },
    question = { "「%s」这个我还真不太确定，换个说法我再试试",
                 "我一下没反应过来，%s 你能说得再具体点吗",
                 "%s 啊……这个我得想想，要不你换个角度问",
                 "关于%s我还没想好怎么答，你先问点别的？" },
    command  = { "好的，不过我还没学会这个操作，说清楚点我再试",
                 "收到，但这个我还做不了，换个需求试试",
                 "这个指令我接不住，你换个说法看看" },
    statement= { "嗯，然后呢", "是这样啊，继续说", "有道理，还有别的吗",
                 "嗯嗯，我在听", "然后呢，我听着" },
}
local _FB_NOTOP = {
    question = "嗯……这个我没太接住，你换个说法试试",
    weather  = "天气我这边查不到实时数据，得联网才行",
}
-- 回显用户话里的关键词，让兜底显得"听进去了"而不是机械复读
local _STOPW = { ["什么"]=1,["为什么"]=1,["怎么"]=1,["怎样"]=1,["如何"]=1,["可以"]=1,
                 ["是不是"]=1,["有没有"]=1,["这个"]=1,["那个"]=1,["多少"]=1,["几个"]=1,
                 ["哪里"]=1,["知道"]=1,["告诉"]=1,["一下"]=1,["能不能"]=1,["会不会"]=1,
                 ["请问"]=1,["一下"]=1,["觉得"]=1,["感觉"]=1 }
local function _echoTopic(t)
    local s = _norm(t or "")
    local best = ""
    for run in s:gmatch("[\128-\255][\128-\255]+") do
        local L = _u8len(run)
        if L >= 2 and L <= 6 and not _STOPW[run] then
            local r = _stripMood(run)
            local rl = _u8len(r)
            if rl >= 2 and rl > _u8len(best) then best = r end
        end
    end
    if best == "" then return nil end
    return best
end
local _san
local function _fallback(t, sess, persona)
    local it = _intent(t)
    local pool = _FALLBACK[it] or _FALLBACK.statement
    local i = 1
    if sess and sess.fbN then i = (sess.fbN % #pool) + 1 end
    if sess then sess.fbN = (sess.fbN or 0) + 1 end
    local line = pool[i]
    if line:find("%%s", 1, true) then
        local tp = _echoTopic(t)
        if tp then
            line = line:gsub("%%s", tp)
        else
            line = _FB_NOTOP[it] or "嗯，这个我没太接住，你换个说法试试"
        end
        if line:find("%%s", 1, true) then line = line:gsub("%%s", "这个") end
    end
    return _san(line, persona)
end

--==================== 上下文增强 ====================
-- 短问句（"为什么"/"然后呢"/"它呢"）单独检索一定失败，
-- 必须把上一轮的问题/实体拼进来，这是"接得上话"的关键。
local _ENTITY_LAST = {}
-- 追问词：含这些词的句子即使较长也可能是承接上文
local _FOLLOW = { ["那"]=1, ["那么"]=1, ["还"]=1, ["再"]=1, ["也"]=1, ["为什么"]=1,
                  ["为啥"]=1, ["然后"]=1, ["接着"]=1, ["另外"]=1, ["呢"]=1, ["它"]=1,
                  ["这个"]=1, ["那个"]=1, ["其他"]=1 }
local function _ctxQuery(sess, text)
    if type(sess) ~= "table" then return text end
    local turns = sess.turns or {}
    if #turns == 0 then return text end
    local lastQ = tostring(turns[#turns][1] or "")
    if lastQ == "" then return text end
    local n = _u8len(text)
    local isFollow = false
    for w in pairs(_FOLLOW) do
        if text:find(w, 1, true) then isFollow = true break end
    end
    if n >= 6 and not isFollow then return text end
    -- 短补充句 / 追问句 + 上文 = 完整查询
    return lastQ .. " " .. text
end
-- 指代消解：把"它/这个/那个/它多少钱"里的代词换成上文最后的实体
local _PRON = { ["它"]=1, ["这个"]=1, ["那个"]=1, ["这个东西"]=1, ["他"]=1, ["她"]=1 }
local function _resolve(text, sess)
    if type(sess) ~= "table" then return text end
    if not sess.lastEntity then return text end
    local out = text
    for p in pairs(_PRON) do
        if out:find(p, 1, true) then
            out = out:gsub(p, sess.lastEntity)
        end
    end
    return out
end

--==================== 重复惩罚（缓存 / 知识库 / 模糊 共用） ====================
-- 只在模型生成里做惩罚是不够的：玩家问得多的恰恰是缓存和知识库命中，
-- 一旦命中就原样复读，聊两轮就变成复读机。这里统一拦一道。
local _REP_KEEP = 6          -- 记住最近几条回复
local function _repKey(s)
    return string.lower(tostring(s or ""):gsub("%s+", ""):gsub("[%p%c]", ""))
end
local function _pushReply(sess, txt)
    if type(sess) ~= "table" then return end
    sess.recentReplies = sess.recentReplies or {}
    local k = _repKey(txt)
    if k == "" then return end
    sess.recentReplies[#sess.recentReplies + 1] = k
    while #sess.recentReplies > _REP_KEEP do table.remove(sess.recentReplies, 1) end
end
-- 与最近回复重复？返回重复次数
local function _repCount(sess, txt)
    if type(sess) ~= "table" or not sess.recentReplies then return 0 end
    local k = _repKey(txt)
    if k == "" then return 0 end
    local c = 0
    for _, r in ipairs(sess.recentReplies) do
        if r == k then c = c + 1 end
    end
    return c
end
local function _isRepeat(sess, txt) return _repCount(sess, txt) > 0 end

--==================== 智能路由主函数 ====================
local function _route(sid, text)
    local sess = getSess(sid)
    local persona = _getPersona(sid)
    local raw = tostring(text or "")
    if raw == "" then return "说点什么吧～", "empty" end

    local n1 = _norm(raw)
    local key = string.lower((n1:gsub("%s+", "")))
    local key2 = string.lower(_stripMood(n1):gsub("%s+", ""))

    -- 连续同问计数：同一个问题连着问超过 2 次 = 玩家对答案不满意
    sess.lastKey = sess.lastKey or nil
    sess.sameCount = sess.sameCount or 0
    if sess.lastKey == key or sess.lastKey == key2 then
        sess.sameCount = sess.sameCount + 1
    else
        sess.sameCount = 1
        sess.lastKey = key2 ~= "" and key2 or key
    end
    local impatient = (sess.sameCount >= 3)     -- 第 3 次起视为不满意
    if impatient then
        D(string.format("同一问题第 %d 次，判定不满意，绕过缓存/首命中", sess.sameCount))
    end

    -- L0 精确缓存（两种 key 都试）
    -- 重复惩罚：命中的答案若最近说过，就不复用，往下走换条路
    if not impatient then
        local hit = cacheGet(key)
        if not hit and key2 ~= key then hit = cacheGet(key2) end
        if hit and not _isRepeat(sess, hit) then
            local out = _san(hit, persona)
            _pushReply(sess, out)
            return out, "cache"
        end
    end

    -- L1 Skills
    local q1 = _resolve(raw, sess)
    local qs = _norm(q1)
    for _, nm in ipairs(_SKILL_ORDER) do
        local sk = _SKILLS[nm]
        -- 关键：skill 一律吃**原文** q1，不能吃 _norm 结果。
        -- _norm 会删掉 . - ( ) 等标点，"100*0.85" 会变成 "100*085"=8500、
        -- "(12+8)/4" 会变成 "12+8/4"=14，算式全错。
        -- match 两种文本都试（中文口语靠 norm，算式靠原文）。
        if sk and sk.match and (sk.match(qs) or (q1 ~= qs and sk.match(q1))) then
            local ok, r = pcall(sk.run, q1, sess)
            if ok and r ~= nil and tostring(r) ~= "" then
                local out = _applyPersona(tostring(r), persona)
                cachePut(key, out)
                -- 确定性回答（几点/几号/算式）不参与重复惩罚，问几次答几次
                _pushReply(sess, out)
                return out, "skill:" .. nm
            end
        end
    end

    -- L2 知识库（BM25）
    local kq = _ctxQuery(sess, qs)
    local hits = _kbSearch(kq, 3)
    -- 拼接上文反而稀释命中时，用原句再搜一次，取分高者
    if kq ~= qs then
        local hs = (hits[1] and hits[1].score) or 0
        if hs < _KB_MINSCORE then
            local h2 = _kbSearch(qs, 3)
            if h2[1] and h2[1].score > hs then hits = h2 end
        end
    end
    if #hits > 0 and hits[1].score >= _KB_MINSCORE then
        -- 重复惩罚：首条最近说过就顺位往下挑（不满意时强制换一条）
        local pick = 1
        if impatient or _isRepeat(sess, hits[1].doc.a) then
            for i = 2, #hits do
                if not _isRepeat(sess, hits[i].doc.a) then pick = i break end
            end
            if _isRepeat(sess, hits[pick].doc.a) then
                D("知识库候选全部与最近回复重复，改走生成")
                hits = {}
            else
                D(string.format("知识库改选第 %d 条（首条重复或玩家不满意）", pick))
            end
        end
        if #hits > 0 then
        local ans = hits[pick].doc.a
        -- 知识条目可以指向 skill（内置表里用 [SKILL:xxx]）
        local skn = ans:match("^%[SKILL:(.-)%]$")
        if skn and _SKILLS[skn] then
            local ok, r = pcall(_SKILLS[skn].run, qs, sess)
            if ok and r ~= nil then
                local out = _applyPersona(tostring(r), persona)
                cachePut(key, out)
                _pushReply(sess, out)
                return out, "kb->skill:" .. skn
            end
        end
        local out = _applyPersona(ans, persona)
        cachePut(key, out)
        _pushReply(sess, out)
        if hits[pick].score >= _KB_MINSCORE * 2 then
            return out, "kb"
        end
        -- 分数一般：仍返回，但记日志
        D(string.format("知识库弱命中 score=%.2f cover=%.2f", hits[pick].score, hits[pick].cover))
        return out, "kb-weak"
        end
    end

    -- L3 模糊缓存：历史问答里找最像的
    if #CACHE_Q > 0 then
        local bestK, bestD = nil, 999
        local lim = math.min(#CACHE_Q, 400)
        for i = 1, lim do
            local k = CACHE_Q[i]
            local d = _lev(key2, k)
            if d < bestD then bestD, bestK = d, k end
        end
        local tol = math.max(1, math.floor(_u8len(key2) * 0.25))
        if bestK and bestD <= tol then
            local v = CACHE[bestK]
            if v and not impatient and not _isRepeat(sess, v) then
                D(string.format("模糊命中 dist=%d tol=%d", bestD, tol))
                local out = _san(v, persona)
                _pushReply(sess, out)
                return out, "fuzzy"
            end
        end
    end

    -- L4 模型生成（重复提问时抬高温度，逼它换个说法）
    local ok, reply = pcall(function()
        return doGenerate(sess, raw, impatient and 0.35 or nil)
    end)
    if ok and reply and tostring(reply) ~= "" and not tostring(reply):find("^%[未加载模型%]") then
        local out = _applyPersona(tostring(reply), persona)
        if not _isRepeat(sess, out) then
            cachePut(key, out)
            _pushReply(sess, out)
            return out, "gen"
        end
        D("生成结果与最近回复重复，转兜底")
    end

    -- L5 兜底（同一问题问烦了就明说，别再复读）
    local fb = _fallback(raw, sess, persona)
    if impatient then
        fb = "这个我连着答了好几次啦，要不你把问题说具体点？我再想想～"
    end
    _pushReply(sess, fb)
    return fb, (impatient and "fallback-impatient" or "fallback")
end


--==================== 增强层初始化 / 小工具 ====================
local _ENH_INITED = false
-- 惰性初始化：任何开放函数进来都能自愈，不依赖 OnStart 一定成功
local function _ensureEnhance()
    if _ENH_INITED then return end
    _ENH_INITED = true
    _initKB()
    _tryLoadHostSkills()
    if _G.LuaVM and (_G.LuaVM.Define or (_G.LuaVM.Compile and _G.LuaVM.RunBC)) then
        _tryRegisterVM()
    end
end

local function _kbCount()
    local n = 0
    for _ in pairs(_KB) do n = n + 1 end
    return n
end

-- 从文本里挑"最像实体"的连续中文片段，供下一轮指代消解
local _STOP = { ["的"]=1, ["了"]=1, ["是"]=1, ["在"]=1, ["我"]=1, ["你"]=1, ["他"]=1,
                ["和"]=1, ["与"]=1, ["吗"]=1, ["呢"]=1, ["啊"]=1, ["吧"]=1, ["怎"]=1,
                ["怎么"]=1, ["什么"]=1, ["为什么"]=1, ["多少"]=1, ["有"]=1, ["没"]=1 }
local function _pickEntity(text)
    if type(text) ~= "string" then return nil end
    local best, blen = nil, 0
    for seg in string.gmatch(text, "[\228-\233][\128-\191]+") do
        local w = ""
        for ch in string.gmatch(seg, "[\228-\233][\128-\191][\128-\191]") do
            if _STOP[ch] then
                if #w > blen then best, blen = w, #w end
                w = ""
            else
                w = w .. ch
            end
        end
        if #w > blen then best, blen = w, #w end
    end
    if blen < 2 then return nil end
    return best
end


--==================== 开放函数实现 ====================
function Script:Chat(sessionId, userText)
    if COMPONENT_SELF == nil then COMPONENT_SELF = self end
    local ok, r = pcall(function() return Script.ChatImpl(self, sessionId, userText) end)
    if not ok then
        D("Chat 内部异常: " .. tostring(r))
        return "我卡了一下，再说一遍好吗"
    end
    return r or "嗯……"
end

function Script:Generate(sessionId, userText)
    if COMPONENT_SELF == nil then COMPONENT_SELF = self end
    local sid = tostring(sessionId or "default")
    local text = tostring(userText or "")
    local sess = getSess(sid)
    local ok, r = pcall(function() return doGenerate(sess, text) end)
    if not ok or not r or r == "" then
        return MODEL_ERR and ("[未加载模型] " .. MODEL_ERR) or "生成失败"
    end
    if #sess.turns >= 8 then table.remove(sess.turns, 1) end
    sess.turns[#sess.turns + 1] = { text, r }
    return r
end

function Script:ResetSession(sessionId)
    if COMPONENT_SELF == nil then COMPONENT_SELF = self end
    SESS[tostring(sessionId or "default")] = nil
    return "已清空"
end

function Script:SetTableIds(str)
    if COMPONENT_SELF == nil then COMPONENT_SELF = self end
    RUNTIME_IDS = nil
    M = nil
    MODEL_ERR = nil
    -- 存到 RUNTIME_IDS 而不是回写 Script.tableIdsText：
    -- 非函数字段在运行时赋值在游戏里未必生效，运行时覆盖走局部变量更可靠
    local list = {}
    for w in string.gmatch(tostring(str or ""), "[^,;，；%s]+") do
        list[#list + 1] = w
    end
    RUNTIME_IDS = list
    ID_SOURCE = "运行时SetTableIds"
    local ids = getIds()
    return "已设置 " .. #ids .. " 个二维表"
end

function Script:GetTableIds()
    if COMPONENT_SELF == nil then COMPONENT_SELF = self end
    local ids = getIds()
    return table.concat(ids, ",")
end

function Script:ProbeTable(tid)
    if COMPONENT_SELF == nil then COMPONENT_SELF = self end
    local rows = readTable(tostring(tid or ""))
    if not rows then return "读表失败" end
    local r0 = rows[1]
    local ncol = type(r0) == "table" and #r0 or 1
    local v = r0 and pickField(r0) or ""
    return string.format("表 %s: %d 行, 每行 %d 列, 首行取值=%s",
        tostring(tid), #rows, ncol, tostring(v):sub(1, 40))
end

function Script:ModelStats()
    if COMPONENT_SELF == nil then COMPONENT_SELF = self end
    local ids = getIds()
    local s = string.format("二维表 %d 个 | 模型 %s | 缓存 %d/%d 命中 %d 未中 %d",
        #ids, M and "已加载" or (MODEL_ERR or "未加载"),
        (function() local n = 0 for _ in pairs(CACHE) do n = n + 1 end return n end)(),
        math.floor(getNumProp("cacheSize", 2000)), STAT.hit, STAT.miss)
    if STAT.genTokens > 0 then
        s = s .. string.format(" | 生成 %d 次 %d token 平均 %.0f ms/token",
            STAT.gen, STAT.genTokens, STAT.genMs / STAT.genTokens)
    end
    return s
end

function Script:Encode(text)
    if COMPONENT_SELF == nil then COMPONENT_SELF = self end
    local ids = encode(tostring(text or ""))
    local t = {}
    for i = 1, math.min(#ids, 40) do t[i] = tostring(ids[i]) end
    return #ids .. " tokens: " .. table.concat(t, ",")
end

function Script:WarmCache(pairs)
    if COMPONENT_SELF == nil then COMPONENT_SELF = self end
    local n = 0
    for line in string.gmatch(tostring(pairs or ""), "[^\r\n]+") do
        local tab = string.find(line, "\t", 1, true)
        if tab then
            local q = string.lower(string.gsub(string.sub(line, 1, tab - 1), "%s+", ""))
            local a = string.sub(line, tab + 1)
            if q ~= "" and a ~= "" then cachePut(q, a); n = n + 1 end
        end
    end
    return "预热 " .. n .. " 条"
end

function Script:ShowIds()
    if COMPONENT_SELF == nil then COMPONENT_SELF = self end
    local ids = getIds()
    local t = {}
    for i = 1, math.min(#ids, 5) do t[#t + 1] = tostring(ids[i]) end
    return string.format("ID %d 个 | 来源=%s\n前5个: %s%s",
        #ids, tostring(ID_SOURCE), table.concat(t, ", "),
        #ids > 5 and ("\n...(还有 " .. (#ids - 5) .. " 个)") or "")
end

function Script:OnStart()
    COMPONENT_SELF = self
    RUNTIME_IDS = nil
    M = nil
    MODEL_ERR = nil
    local ids = getIds()
    print(string.format("[MM] 启动: 二维表 %d 个 | 来源=%s", #ids, tostring(ID_SOURCE)))
    if #ids > 0 then
        print(string.format("[MM] 首表=%s 末表=%s", tostring(ids[1]), tostring(ids[#ids])))
    end
    print(string.format("[MM] 参数: temp=%.2f topP=%.2f maxTok=%d maxCtx=%d cache=%d",
        getNumProp("temperature", 0.85), getNumProp("topP", 0.85),
        math.floor(getNumProp("maxTokens", 24)), math.floor(getNumProp("maxCtx", 256)),
        math.floor(getNumProp("cacheSize", 2000))))
    print(string.format("[MM] 提示词模式=%s (0纯续写/1聊天模板/2问答cue) 重复惩罚=%.2f",
        tostring(math.floor(getNumProp("promptMode", 2))), getNumProp("repPenalty", 1.15)))
    return true
end

function Script:OnDestroy()
    SESS = {}
    CACHE = {}
    CACHE_Q = {}
    CACHE_M = {}
    M = nil
end

--####################################################################
--#  覆盖：ChatImpl 走智能路由；以及新增开放函数
--####################################################################
function Script:ChatImpl(sessionId, userText)
    if COMPONENT_SELF == nil then COMPONENT_SELF = self end
    _ensureEnhance()
    local sid = tostring(sessionId or "default")
    local text = tostring(userText or "")
    if text == "" then return "说点什么吧～" end
    local reply, src2 = _route(sid, text)
    local sess = getSess(sid)
    if #sess.turns >= 8 then table.remove(sess.turns, 1) end
    sess.turns[#sess.turns + 1] = { text, reply }
    local e = _pickEntity(text)
    if e then sess.lastEntity = e end
    D(string.format("[%s] %s -> %s", src2 or "?", text, tostring(reply):sub(1, 40)))
    return reply
end

function Script:Route(sessionId, userText)
    if COMPONENT_SELF == nil then COMPONENT_SELF = self end
    _ensureEnhance()
    local r, s = _route(tostring(sessionId or "default"), tostring(userText or ""))
    return "[" .. tostring(s) .. "] " .. tostring(r)
end

-- 答案后处理：%s 占位替换 + 人设第一人称
_san = function(line, persona)
    if type(line) ~= "string" then return line end
    if line:find("%%s", 1, true) then line = line:gsub("%%s", "这个") end
    if type(persona) == "table" then
        local fp = persona.firstPerson or persona.first_person or persona.self
        if type(fp) == "string" and fp ~= "" and line:find("我", 1, true) then
            line = line:gsub("我", function() return fp end)
        end
    end
    return line
end
function Script:Ask(sessionId, userText)
    if COMPONENT_SELF == nil then COMPONENT_SELF = self end
    local ok, r = pcall(function() return Script.ChatImpl(self, sessionId, userText) end)
    if not ok then D("Ask 异常: " .. tostring(r)); return "我卡了一下，再说一遍好吗" end
    return r or "嗯……"
end

function Script:Calc(expr)
    _ensureEnhance()
    local ok, r = pcall(_SKILLS["calc"].run, tostring(expr or ""), nil)
    if ok and r ~= nil then return tostring(r) end
    return "算不出来，换个写法试试"
end

function Script:AddDoc(q, a)
    _ensureEnhance()
    local id = _kbAdd(tostring(q or ""), tostring(a or ""))
    return string.format("已加入知识库 #%d（当前 %d 条）", id, _kbCount())
end

function Script:AddDocs(text)
    _ensureEnhance()
    local n = 0
    for line in tostring(text or ""):gmatch("[^\r\n]+") do
        local q, a = line:match("^(.-)[\t|]%s*(.+)$")
        if not q then q, a = line:match("^(.-)%=%s*(.+)$") end
        if q and a then _kbAdd(q, a); n = n + 1 end
    end
    return string.format("批量入库 %d 条（当前 %d 条）", n, _kbCount())
end

function Script:SearchKB(q)
    _ensureEnhance()
    local hits = _kbSearch(tostring(q or ""), 5)
    if #hits == 0 then return "无命中（当前 " .. _kbCount() .. " 条）" end
    local t = {}
    for i, h in ipairs(hits) do
        t[i] = string.format("%d) [%.2f] %s => %s", i, h.score, tostring(h.doc.q):sub(1,20), tostring(h.doc.a):sub(1,40))
    end
    return table.concat(t, "\n")
end

function Script:ClearKB()
    _ensureEnhance()
    _KB = {}
    _KBID = 0
    _initKB()
    return "已清空并重建（内置 " .. _kbCount() .. " 条）"
end

function Script:SetPersona(name, style)
    _ensureEnhance()
    local n = tostring(name or "")
    if n == "" then return "人设名不能为空" end
    _PERSONAS[n] = { key = n, style = (style ~= nil and tostring(style) ~= "") and tostring(style) or nil }
    return "人设已设置：调用时用会话ID = " .. n .. "::会话名"
end

function Script:ListPersona()
    _ensureEnhance()
    local t, n = {}, 0
    for _, k in ipairs(_PERSONA_ORDER or {}) do n = n + 1; t[n] = k end
    for k in pairs(_PERSONAS) do
        local seen = false
        for _, kk in ipairs(_PERSONA_ORDER or {}) do if kk == k then seen = true end end
        if not seen then n = n + 1; t[n] = k end
    end
    return "人设(" .. n .. ")：" .. table.concat(t, " / ")
end

function Script:ListSkills()
    _ensureEnhance()
    local t, n = {}, 0
    for k in pairs(_SKILLS) do n = n + 1; t[n] = k end
    table.sort(t)
    return "技能(" .. n .. ")：" .. table.concat(t, " / ")
end

function Script:RegisterVM(name, luaSource)
    _ensureEnhance()
    if not (_G.LuaVM and (_G.LuaVM.Define or (_G.LuaVM.Compile and _G.LuaVM.RunBC))) then
        return "未检测到 LuaVM，请先把 LuaVM桥接.lua 导入同一地图"
    end
    local ok, err = pcall(_G.LuaVM.Define, tostring(name or ""), tostring(luaSource or ""))
    if not ok then return "注册失败: " .. tostring(err) end
    _tryRegisterVM()
    return "已注册 VM 技能：" .. tostring(name) .. "（当前技能 " .. (function() local c=0; for _ in pairs(_SKILLS) do c=c+1 end; return c end)() .. " 个）"
end

function Script:Stats2()
    _ensureEnhance()
    local nk = _kbCount()
    local ns = 0; for _ in pairs(_SKILLS) do ns = ns + 1 end
    local np = 0; for _ in pairs(_PERSONAS) do np = np + 1 end
    return string.format("知识 %d 条 | 技能 %d 个 | 人设 %d 个", nk, ns, np)
end

--####################################################################
--#  MiniMind 增强层 v8 · 缓存命中体系
--#
--#  两层缓存，别混为一谈：
--#
--#  【A】KV 前缀复用（推理层）—— 已在 doGenerate 里实现
--#      同一会话下一轮对话，若新 token 序列与上一轮有公共前缀 LCP，
--#      则这些位置的 K/V 直接沿用，只 forward 新增 token。
--#      对应知乎里讲的 Prefix Caching / RadixAttention 那一层。
--#      省的是矩阵乘法（prefill），不是内存。
--#      注意：它只在**同一会话、脚本未重载**时有效。st.kv 是几十 MB 的
--#      浮点表，没法序列化进属性字符串，重进地图必然丢 —— 这不是缺陷，
--#      是所有 KV Cache 的共性（显存/内存态，天然易失）。
--#
--#  【B】答案缓存（应用层）—— 本文件新增的持久化部分
--#      归一化问题 -> 答案，命中即回，零推理、零耗时。
--#      这才是知乎末尾说的"语义缓存"。命中判定刻意收紧：
--#      宁可 miss 去生成，也不要把"天气"误配成"星期几"。
--#
--#  内存：Lua table 很宽松（实测百 MB 级可用），所以 cacheSize 上限
--#  开到 20 万条。真正的约束不是内存，是序列化耗时和属性字符串长度。
--####################################################################

--==================== 缓存元数据（与 CACHE 平行，不破坏原结构）====================
-- CACHE[k] 仍是答案字符串；CACHE_M[k] 存 {n=命中次数, t=入库时间, s=来源}
-- 分开存是为了不动 L3 模糊匹配那段的既有逻辑。
local CACHE_M = {}

local function _cacheMeta(k)
    local m = CACHE_M[k]
    if not m then m = { n = 0, t = os.time(), s = "gen" }; CACHE_M[k] = m end
    return m
end

--==================== 自研 JSON（不依赖引擎 json 模块）====================
-- 环境里 json 可能不存在（转储有但可能被 stub），所以自己实现一份。
-- 只支持 Lua 5.1：没有 \\u 以外的需求，UTF-8 中文原样写入不转义。
local _JESC = { ['"'] = '\\"', ['\\'] = '\\\\', ['\n'] = '\\n',
                ['\r'] = '\\r', ['\t'] = '\\t', ['\b'] = '\\b', ['\f'] = '\\f' }
local function _jstr(s)
    s = tostring(s or "")
    s = s:gsub('[%c"\\]', function(c)
        return _JESC[c] or string.format('\\u%04x', string.byte(c))
    end)
    return '"' .. s .. '"'
end
-- 数组形式：每个条目 [q, a, n, t, s]，比对象省一半字符
local function _jenc(val)
    local t = type(val)
    if t == "nil" then return "null" end
    if t == "boolean" then return val and "true" or "false" end
    if t == "number" then
        if val ~= val or val == math.huge or val == -math.huge then return "null" end
        if math.floor(val) == val and math.abs(val) < 2 ^ 53 then
            return string.format("%d", val)
        end
        return string.format("%.6g", val)
    end
    if t == "string" then return _jstr(val) end
    if t == "table" then
        -- 纯数组判定：键为 1..n 连续
        -- 注意：遇到字符串键会 break，此时 n 可能仍是 0，
        --       不能拿 n==0 当"空表"用（会把非空对象误判成数组 -> 编码成 []）
        local n, isArr, empty = 0, true, true
        for k in pairs(val) do
            empty = false
            if type(k) ~= "number" then isArr = false; break end
            n = n + 1
        end
        if empty then return "{}" end
        if isArr then
            for i = 1, n do if val[i] == nil then isArr = false; break end end
        end
        local out = {}
        if isArr then
            for i = 1, n do out[#out + 1] = _jenc(val[i]) end
            return "[" .. table.concat(out, ",") .. "]"
        end
        for k, v in pairs(val) do
            out[#out + 1] = _jstr(tostring(k)) .. ":" .. _jenc(v)
        end
        return "{" .. table.concat(out, ",") .. "}"
    end
    return "null"
end

-- JSON 解码：手写递归下降，够用即可
local _u8fromcp   -- 前向声明：下面 parseStr 里要用
local function _jdec(s)
    local pos = 1
    local function err(m) error(m .. " @ " .. pos, 0) end
    local function ws()
        while pos <= #s do
            local c = s:sub(pos, pos)
            if c == " " or c == "\t" or c == "\n" or c == "\r" then pos = pos + 1
            else break end
        end
    end
    local parseVal
    local function parseStr()
        -- s[pos] == '"'
        pos = pos + 1
        local buf = {}
        while pos <= #s do
            local c = s:sub(pos, pos)
            if c == '"' then pos = pos + 1; break end
            if c == "\\" then
                local e = s:sub(pos + 1, pos + 1)
                local map = { n = "\n", t = "\t", r = "\r", b = "\b", f = "\f",
                              ['"'] = '"', ["\\"] = "\\", ["/"] = "/" }
                if map[e] then buf[#buf + 1] = map[e]; pos = pos + 2
                elseif e == "u" then
                    local hex = s:sub(pos + 2, pos + 5)
                    local cp = tonumber(hex, 16)
                    if not cp then err("bad \\u") end
                    buf[#buf + 1] = _u8fromcp(cp)
                    pos = pos + 6
                else buf[#buf + 1] = e; pos = pos + 2 end
            else
                buf[#buf + 1] = c; pos = pos + 1
            end
        end
        return table.concat(buf)
    end
    parseVal = function()
        ws()
        local c = s:sub(pos, pos)
        if c == "{" then
            pos = pos + 1
            local o = {}
            ws()
            if s:sub(pos, pos) == "}" then pos = pos + 1; return o end
            while true do
                ws()
                if s:sub(pos, pos) ~= '"' then err("key expect") end
                local k = parseStr()
                ws()
                if s:sub(pos, pos) ~= ":" then err("colon expect") end
                pos = pos + 1
                o[k] = parseVal()
                ws()
                local d = s:sub(pos, pos)
                if d == "," then pos = pos + 1
                elseif d == "}" then pos = pos + 1; break
                else err("comma/brace expect") end
            end
            return o
        elseif c == "[" then
            pos = pos + 1
            local a = {}
            ws()
            if s:sub(pos, pos) == "]" then pos = pos + 1; return a end
            while true do
                a[#a + 1] = parseVal()
                ws()
                local d = s:sub(pos, pos)
                if d == "," then pos = pos + 1
                elseif d == "]" then pos = pos + 1; break
                else err("comma/bracket expect") end
            end
            return a
        elseif c == '"' then return parseStr()
        elseif s:sub(pos, pos + 3) == "true" then pos = pos + 4; return true
        elseif s:sub(pos, pos + 4) == "false" then pos = pos + 5; return false
        elseif s:sub(pos, pos + 3) == "null" then pos = pos + 4; return nil
        else
            local num = s:match("^-?%d+%.?%d*[eE]?[-+]?%d*", pos)
            if not num or num == "" then err("value expect") end
            pos = pos + #num
            return tonumber(num)
        end
    end
    local v = parseVal()
    return v
end
-- 码点 -> UTF-8（\uXXXX 用，主要保底，中文一般直接原字节存）
_u8fromcp = function(cp)
    if cp < 0x80 then return string.char(cp)
    elseif cp < 0x800 then
        return string.char(0xC0 + math.floor(cp / 64), 0x80 + (cp % 64))
    elseif cp < 0x10000 then
        return string.char(0xE0 + math.floor(cp / 4096),
                           0x80 + (math.floor(cp / 64) % 64), 0x80 + (cp % 64))
    end
    return string.char(0xF0 + math.floor(cp / 262144),
                       0x80 + (math.floor(cp / 4096) % 64),
                       0x80 + (math.floor(cp / 64) % 64), 0x80 + (cp % 64))
end

--==================== 分片：切开但不能切坏 ====================
-- 两个坑：① 不能切在 UTF-8 多字节序列中间（否则该片是非法字节流）
--        ② 不能切在反斜杠和它后面的转义字符中间（否则 JSON 解析炸）
local function _shardCut(str, n)
    local shards = {}
    local i, L = 1, #str
    while i <= L do
        local take = 0
        local j = i
        while j <= L and take < n do
            local b = string.byte(str, j)
            local w = 1
            if b >= 0xF0 then w = 4 elseif b >= 0xE0 then w = 3 elseif b >= 0xC0 then w = 2 end
            if take + w > n then break end
            if b == 0x5C then  -- '\\'
                -- 连转义字符一起算进来（\\uXXXX 占 6 字节）
                local nx = str:sub(j + 1, j + 1)
                local extra = 1
                if nx == "u" then extra = 5 end
                if take + w + extra > n then break end
                j = j + w + extra; take = take + w + extra
            else
                j = j + w; take = take + w
            end
        end
        if j <= i then j = i + n end   -- 兜底，防死循环
        shards[#shards + 1] = str:sub(i, j - 1)
        i = j
    end
    if #shards == 0 then shards[1] = "" end
    return shards
end

--==================== 序列化当前缓存 ====================
local function _cacheDump()
    local items = {}
    for k, a in pairs(CACHE) do
        if type(a) == "string" and a ~= "" then
            local m = CACHE_M[k] or { n = 0, t = 0, s = "gen" }
            items[#items + 1] = { k, a, m.n or 0, m.t or 0, m.s or "gen" }
        end
    end
    -- 按命中次数降序：存档被截断时优先保住热数据
    table.sort(items, function(x, y) return (x[3] or 0) > (y[3] or 0) end)
    return _jenc({ v = 8, n = #items, ts = os.time(), items = items })
end

-- 从解析好的 items 里灌缓存
local function _absorb(items)
    local n = 0
    for _, it in ipairs(items) do
        if type(it) == "table" and type(it[1]) == "string" and type(it[2]) == "string" then
            cachePut(it[1], it[2])
            CACHE_M[it[1]] = { n = tonumber(it[3]) or 0, t = tonumber(it[4]) or os.time(),
                               s = tostring(it[5] or "gen") }
            n = n + 1
        end
    end
    return n
end

local function _cacheRestore(txt)
    if type(txt) ~= "string" or txt == "" then return 0, "空" end
    local ok, data = pcall(_jdec, txt)
    if ok and type(data) == "table" and type(data.items) == "table" then
        return _absorb(data.items), nil
    end
    -- 容错：玩家手动粘分片时漏了一片 / 某一片被属性长度截断了，
    -- 整体 JSON 就不完整。这时候不能一条都读不回来 ——
    -- 从末尾回退到最后一个条目分隔符，截断后补个尾巴再解析。
    local head = txt:match('^(.*%[%s*%[")')
    local guard = 0
    local cur = txt
    while head and guard < 30 do
        guard = guard + 1
        -- 截到最后一个完整条目的起点之前，再补 ]}
        local cut = cur:match('^(.*)%],%s*%[%s*"')
        if not cut then cut = cur:match('^(.*)%],%s*%[') end
        if not cut or #cut >= #cur then break end
        -- cut 停在"最后一个完整条目"之前，缺的可能是 条目]+items]+对象
        -- 两种补齐都试一遍（items 可能被截得只剩 0 个条目）
        for _, suf in ipairs({ "]]}", "]}" }) do
            local ok2, d2 = pcall(_jdec, cut .. suf)
            if ok2 and type(d2) == "table" and type(d2.items) == "table" then
                local n = _absorb(d2.items)
                if n > 0 then
                    return n, string.format("（JSON 尾部不完整，已容错恢复前 %d 条）", n)
                end
            end
        end
        cur = cut .. "]}"
        head = cur:match('^(.*%[%s*%[")')
    end
    return 0, "JSON 解析失败，且无法容错恢复（检查分片是否齐全/完整）"
end

--==================== 属性字符串数组读写 ====================
-- 数组属性统一走 self（铁律：不读 Script.propertys[x].default）
local function _getShards()
    local self_ = COMPONENT_SELF
    local arr = self_ and self_.cacheShards
    if type(arr) ~= "table" and type(arr) ~= "userdata" then return {} end
    local out = {}
    for i = 1, 100000 do
        local ok, v = pcall(function() return arr[i] end)
        if not ok or v == nil then break end
        if type(v) == "string" and v ~= "" then out[#out + 1] = v end
    end
    return out
end
local function _setShards(list)
    local self_ = COMPONENT_SELF
    if not self_ then return false end
    -- 先试着直接赋值（部分版本支持脚本写回属性）
    local ok = pcall(function() self_.cacheShards = list end)
    return ok
end

--==================== 开放函数 ====================
function Script:SaveCache()
    if COMPONENT_SELF == nil then COMPONENT_SELF = self end
    local json = _cacheDump()
    local n = math.floor(getNumProp("shardLen", 1200))
    local shards = _shardCut(json, n)
    local wok = _setShards(shards)
    local cnt = 0
    for _ in pairs(CACHE) do cnt = cnt + 1 end
    STAT.saved = (STAT.saved or 0) + 1
    return string.format("已存档 %d 条 / %d 片 / %d 字符 | 写回属性%s%s",
        cnt, #shards, #json, wok and "成功" or "失败(请手动复制)",
        wok and "" or "\n用 ExportShard(1..N) 逐片取出，手动粘进属性")
end

function Script:LoadCache()
    if COMPONENT_SELF == nil then COMPONENT_SELF = self end
    local shards = _getShards()
    if #shards == 0 then return "属性里没有缓存分片（先 SaveCache，或用 ImportShards 粘进去）" end
    local n, err = _cacheRestore(table.concat(shards, ""))
    if err then return "读档失败: " .. err end
    local tot = 0; for _ in pairs(CACHE) do tot = tot + 1 end
    return string.format("读档 %d 条（当前缓存共 %d 条）", n, tot)
end

function Script:ImportShards(text)
    if COMPONENT_SELF == nil then COMPONENT_SELF = self end
    local n, err = _cacheRestore(tostring(text or ""))
    if err then return "导入失败: " .. err end
    local tot = 0; for _ in pairs(CACHE) do tot = tot + 1 end
    return string.format("导入 %d 条（当前缓存共 %d 条）", n, tot)
end

function Script:ExportShard(idx)
    if COMPONENT_SELF == nil then COMPONENT_SELF = self end
    local json = _cacheDump()
    local n = math.floor(getNumProp("shardLen", 1200))
    local shards = _shardCut(json, n)
    local i = math.floor(tonumber(idx) or 1)
    if i < 1 then i = 1 end
    if i > #shards then return string.format("只有 %d 片（要的是第 %d 片）", #shards, i) end
    return shards[i]
end

function Script:ClearCache()
    if COMPONENT_SELF == nil then COMPONENT_SELF = self end
    local cnt = 0; for _ in pairs(CACHE) do cnt = cnt + 1 end
    CACHE = {}
    CACHE_Q = {}
    CACHE_M = {}
    CACHE_M = {}
    return string.format("已清空 %d 条答案缓存（知识库和技能不受影响）", cnt)
end

function Script:CacheStats()
    if COMPONENT_SELF == nil then COMPONENT_SELF = self end
    local cnt = 0; for _ in pairs(CACHE) do cnt = cnt + 1 end
    local cap = math.floor(getNumProp("cacheSize", 20000))
    local hit, miss = STAT.hit or 0, STAT.miss or 0
    local tot = hit + miss
    local rate = tot > 0 and (hit / tot * 100) or 0
    -- 热条目 top5
    local hot = {}
    for k, m in pairs(CACHE_M) do
        if CACHE[k] then hot[#hot + 1] = { k = k, n = m.n or 0 } end
    end
    table.sort(hot, function(a, b) return a.n > b.n end)
    local t = {}
    for i = 1, math.min(5, #hot) do
        t[#t + 1] = string.format("%s(%d)", tostring(hot[i].k):sub(1, 12), hot[i].n)
    end
    local shards = _getShards()
    return string.format(
        "答案缓存 %d/%d 条 | 命中 %d 次 未命中 %d 次 (%.1f%%)\n" ..
        "KV前缀复用: 省掉前向 %d 次, 实算 %d 次 (省 %.1f%%)\n" ..
        "存档分片 %d 片 | 已存档 %d 次\n" ..
        "热词: %s",
        cnt, cap, hit, miss, rate,
        STAT.preSaved or 0, STAT.preFwd or 0,
        ((STAT.preSaved or 0) + (STAT.preFwd or 0)) > 0
            and ((STAT.preSaved or 0) / ((STAT.preSaved or 0) + (STAT.preFwd or 0)) * 100) or 0,
        #shards, STAT.saved or 0,
        #t > 0 and table.concat(t, " / ") or "无")
end

--==================== 命中计数挂钩 ====================
-- 包一层，让每次命中都累加到元数据（用于 SaveCache 排序和统计热词）
do
    local _oldGet = cacheGet
    cacheGet = function(k)
        local v = _oldGet(k)
        if v then
            local m = _cacheMeta(k)
            m.n = (m.n or 0) + 1
        end
        return v
    end
    local _oldPut = cachePut
    cachePut = function(k, v)
        _oldPut(k, v)
        _cacheMeta(k)
        -- 自动存档：按新增条数节流，避免每次生成都序列化一次
        local every = math.floor(getNumProp("autoSaveEvery", 0))
        if every > 0 then
            STAT.putCount = (STAT.putCount or 0) + 1
            if STAT.putCount % every == 0 then
                local ok = _setShards(_shardCut(_cacheDump(), math.floor(getNumProp("shardLen", 1200))))
                D("自动存档 -> " .. tostring(ok))
            end
        end
    end
end

return Script
