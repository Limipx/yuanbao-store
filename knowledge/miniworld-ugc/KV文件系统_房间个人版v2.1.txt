-- ============================================================
-- KVFS  :  迷你世界 KV 表上的完整文件系统
--   房间/个人版  v2.1
--
-- ============================================================
-- v2.1 修复清单（全部实测）
--   ★1 缓存永不过期      -> 两级缓存都加 TTL(属性 cacheMs, 默认 1500ms, 0=不缓存)
--                            并新增 DropCache 同时清 KV 层与节点层
--   ★2 单字节内容读崩溃  -> HF.decomp 哈夫曼树退化为单叶节点时不再走 node.l/node.r
--                            另加 node==nil 防御，损坏数据不再崩溃
--   ★3 Hash/SimFind 错位 -> N() 不再写死 FSGET(vid,nil)，改为传入 playerId
--                            同时新增 PIDOF：0/空串/nil 一律归一为 nil，
--                            避免同一个空间建出两份实例两套缓存
--   ★4 同名并发产生孤儿  -> 创建前绕过缓存再查一次(freshKids)，窗口收窄到
--                            「检查->写入」这一瞬间；残留竞态见说明 §6.4
--   ★5 ID 熵偏低         -> nextId 混入实例 salt，且生成后查一次是否已占用，
--                            占用就换下一个(最多 8 次)，杜绝静默覆盖
--   ★6 大文件哈希 1.3s   -> 新增属性 hashMode=1 走采样指纹，实测快约 5.7 倍
--                            默认 0(全量)，保证 Dedup/Same 语义不变
--   ★7 属性范围不生效    -> min/max 改名 minValue/maxValue
--   ★8 返回类型标错      -> 14 个实际返回 JSON 串的函数 returnType 改 Mini.String
--   ★9 SetScope 空操作   -> 真正实现：设置该变量「玩家留空」时的默认玩家
--   ★10 新建项看不见      -> resolve 未命中时丢弃整片缓存重查一次，
--                            别人新建的目录/文件立刻可见，不必等 TTL
-- ============================================================
--
-- 硬约束适配：key <= 50 字节 / 仅 94 个可打印 ASCII（无空格）
--             value <= 2,000,000 字节 / 支持比特流（不可打印字节）
--
-- 数据结构（研究结论落地）：
--   * ID 寻址树 + 父边引用：移动/重命名只改被移动节点的 parent 与父目录
--     的一条 name->id 边，代价 O(深度)，与子树大小无关
--   * 目录子节点默认内联；超过 180 项自动转 c<id>_<page> 分页，避免重写巨型 blob
--   * 大文件按 1048576 字节分片（2MB 上限留一倍余量）
--   * 可选 path->id 索引分片 i<hh>，热点路径 1 次 KV 读命中
--   * 混合加密：内容用对称密钥（加密后 MAC），对称密钥用 RSA 公钥封装
--     —— RSA 明文长度受模数限制，绝不能直接加密 2MB 内容
-- ============================================================
-- ============================================================
-- KVFS-CORE  :  受限 KV 存储上的完整文件系统（纯逻辑核心）
-- 约束：key <= 50 字节、仅 94 个可打印 ASCII；value <= 2,000,000 字节、支持比特流
-- 本文件不含任何引擎 API，通过注入的 kv 适配器访问存储：
--   kv.get(varId, playerId, key) -> value|nil
--   kv.set(varId, playerId, key, value) -> true|false
--   kv.del(varId, playerId, key) -> true|false
-- ============================================================
local M = {}

-- ---------------- 配置 ----------------
local CFG = {
  SHARD      = 1048576,   -- 分片大小 1MB（2MB 上限留一倍余量）
  MAXV       = 1900000,   -- 单值安全上限
  INLINE     = 180,       -- 目录内联子节点上限，超出转分页
  PAGE       = 400,       -- 每页子节点数
  COMP_MIN   = 384,       -- 小于此不压缩
  COMP_MAX   = 600000,    -- 大于此不压缩（Lua 性能）
  IDLEN      = 12,
  HASH_MAX   = 262144,
  LBLK       = 65536,   -- Merkle 逻辑块（与物理分片解耦，跨表一致）
  SIM_MAX    = 262144,  -- 超过此大小 SimHash 改为采样
  SAMP       = 65536,   -- ★v2.1 采样指纹每段字节数
  SAMP_MIN   = 262144,  -- ★v2.1 超过此大小才允许采样
  IDTRY      = 8,       -- ★v2.1 ID 冲突重试次数
}
M.CFG = CFG

-- ============================================================
-- 一、SHA-256（纯 Lua 5.1 + bit）
-- ============================================================
local SHA = {}
do
  local bit = bit or require("bit")
  local band, bor, bxor, bnot = bit.band, bit.bor, bit.bxor, bit.bnot
  local lshift, rshift, rol, ror = bit.lshift, bit.rshift, bit.rol, bit.ror
  local tobit = bit.tobit
  local function u32(v) v = tobit(v) return v < 0 and v + 0x100000000 or v end
  local function add32(a, b) return u32(tobit(a) + tobit(b)) end
  local function shr32(v, n) return u32(rshift(tobit(v), n)) end
  local function ror32(v, n) return u32(ror(tobit(v), n)) end
  local function Ch(x, y, z) return bxor(band(x, y), band(bnot(x), z)) end
  local function Maj(x, y, z) return bxor(bxor(band(x, y), band(x, z)), band(y, z)) end
  local function S0(x) return bxor(bxor(ror32(x, 2), ror32(x, 13)), ror32(x, 22)) end
  local function S1(x) return bxor(bxor(ror32(x, 6), ror32(x, 11)), ror32(x, 25)) end
  local function s0(x) return bxor(bxor(ror32(x, 7), ror32(x, 18)), shr32(x, 3)) end
  local function s1(x) return bxor(bxor(ror32(x, 17), ror32(x, 19)), shr32(x, 10)) end
  local K = {
    0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
    0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
    0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
    0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
    0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
    0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
    0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
    0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2 }
  local HEX = "0123456789abcdef"
  function SHA.hex(msg)
    msg = msg or ""
    local len = #msg * 8
    local m = msg .. string.char(0x80)
    while ((#m * 8) % 512) ~= 448 do m = m .. string.char(0) end
    local hi = math.floor(len / 0x100000000)
    local lo = len % 0x100000000
    for i = 3, 0, -1 do m = m .. string.char(band(rshift(hi, i * 8), 0xFF)) end
    for i = 3, 0, -1 do m = m .. string.char(band(rshift(lo, i * 8), 0xFF)) end
    local w = {}
    for i = 1, #m, 4 do
      local v = 0
      for j = 0, 3 do v = bor(lshift(v, 8), string.byte(m, i + j) or 0) end
      w[#w + 1] = v
    end
    local H = { 0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,
                0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19 }
    for cs = 1, #w, 16 do
      local W = {}
      for t = 0, 15 do W[t] = w[cs + t] end
      for t = 16, 63 do
        W[t] = add32(add32(s1(W[t-2]), W[t-7]), add32(s0(W[t-15]), W[t-16]))
      end
      local a,b,c,d,e,f,g,h = H[1],H[2],H[3],H[4],H[5],H[6],H[7],H[8]
      for t = 0, 63 do
        local T1 = add32(add32(add32(h, S1(e)), Ch(e,f,g)), add32(K[t+1], W[t]))
        local T2 = add32(S0(a), Maj(a,b,c))
        h,g,f,e,d,c,b,a = g,f,e,add32(d,T1),c,b,a,add32(T1,T2)
      end
      H[1]=add32(H[1],a) H[2]=add32(H[2],b) H[3]=add32(H[3],c) H[4]=add32(H[4],d)
      H[5]=add32(H[5],e) H[6]=add32(H[6],f) H[7]=add32(H[7],g) H[8]=add32(H[8],h)
    end
    local out = {}
    for i = 1, 8 do
      local v = H[i]
      for j = 3, 0, -1 do
        local by = band(rshift(v, j * 8), 0xFF)
        out[#out+1] = HEX:sub(math.floor(by/16)+1, math.floor(by/16)+1)
        out[#out+1] = HEX:sub(by%16+1, by%16+1)
      end
    end
    return table.concat(out)
  end
  function SHA.bytes(msg)
    local h = SHA.hex(msg)
    local t = {}
    for i = 1, #h, 2 do t[#t+1] = string.char(tonumber(h:sub(i, i+1), 16)) end
    return table.concat(t)
  end
end
M.SHA = SHA

-- ============================================================
-- 一·二、内容指纹：MD5(128bit 判相同) + SimHash(32bit 判相似)
--   为什么用 MD5 而不是 SHA256：KV key 限 50 字节，
--   SHA256 的 hex 是 64 字符 -> "i"+64 = 65 字节，直接超限；
--   MD5 的 hex 是 32 字符 -> 33 字节，可安全用作索引 key。
-- ============================================================
local FP = {}
do
  -- MD5(128bit) + SimHash(32bit) —— 内容指纹与相似度
  -- 设计要点：
  --   MD5 hex 32 字符 -> KV key 最长 33 字节（< 50 限制）
  --   SHA256 hex 64 字符 -> key 65 字节，**超限**，故内容指纹一律用 MD5
  local bit = bit
  local band, bor, bxor, bnot = bit.band, bit.bor, bit.bxor, bit.bnot
  local lshift, rshift, rol = bit.lshift, bit.rshift, bit.rol
  local tobit = bit.tobit

  local function u32(v) v = tobit(v) return v < 0 and v + 0x100000000 or v end
  local function add32(a, b) return u32(tobit(a) + tobit(b)) end
  local function rotl(v, n) local r = rol(tobit(v), n) return r < 0 and r + 0x100000000 or r end

  -- ============================================================
  -- MD5
  -- ============================================================
  local MD5 = {}
  do
    local K = {}
    local HEX = "0123456789abcdef"

    local function F32(x, y, z) return bor(band(x, y), band(bnot(x), z)) end
    local function G32(x, y, z) return bor(band(x, z), band(y, bnot(z))) end
    local function H32(x, y, z) return bxor(bxor(x, y), z) end
    local function I32(x, y, z) return bxor(y, bor(x, bnot(z))) end

    -- 单块压缩：X[1..16] 为小端 32 位字
    local function block(H, X)
      local A, B, C, Dd = H[1], H[2], H[3], H[4]
      -- 轮 1
      A = add32(rotl(add32(add32(add32(A, F32(B, C, Dd)), X[1]), 0xd76aa478), 7), B)
      Dd = add32(rotl(add32(add32(add32(Dd, F32(A, B, C)), X[2]), 0xe8c7b756), 12), A)
      C = add32(rotl(add32(add32(add32(C, F32(Dd, A, B)), X[3]), 0x242070db), 17), Dd)
      B = add32(rotl(add32(add32(add32(B, F32(C, Dd, A)), X[4]), 0xc1bdceee), 22), C)
      A = add32(rotl(add32(add32(add32(A, F32(B, C, Dd)), X[5]), 0xf57c0faf), 7), B)
      Dd = add32(rotl(add32(add32(add32(Dd, F32(A, B, C)), X[6]), 0x4787c62a), 12), A)
      C = add32(rotl(add32(add32(add32(C, F32(Dd, A, B)), X[7]), 0xa8304613), 17), Dd)
      B = add32(rotl(add32(add32(add32(B, F32(C, Dd, A)), X[8]), 0xfd469501), 22), C)
      A = add32(rotl(add32(add32(add32(A, F32(B, C, Dd)), X[9]), 0x698098d8), 7), B)
      Dd = add32(rotl(add32(add32(add32(Dd, F32(A, B, C)), X[10]), 0x8b44f7af), 12), A)
      C = add32(rotl(add32(add32(add32(C, F32(Dd, A, B)), X[11]), 0xffff5bb1), 17), Dd)
      B = add32(rotl(add32(add32(add32(B, F32(C, Dd, A)), X[12]), 0x895cd7be), 22), C)
      A = add32(rotl(add32(add32(add32(A, F32(B, C, Dd)), X[13]), 0x6b901122), 7), B)
      Dd = add32(rotl(add32(add32(add32(Dd, F32(A, B, C)), X[14]), 0xfd987193), 12), A)
      C = add32(rotl(add32(add32(add32(C, F32(Dd, A, B)), X[15]), 0xa679438e), 17), Dd)
      B = add32(rotl(add32(add32(add32(B, F32(C, Dd, A)), X[16]), 0x49b40821), 22), C)

      -- 轮 2
      A = add32(rotl(add32(add32(add32(A, G32(B, C, Dd)), X[2]), 0xf61e2562), 5), B)
      Dd = add32(rotl(add32(add32(add32(Dd, G32(A, B, C)), X[7]), 0xc040b340), 9), A)
      C = add32(rotl(add32(add32(add32(C, G32(Dd, A, B)), X[12]), 0x265e5a51), 14), Dd)
      B = add32(rotl(add32(add32(add32(B, G32(C, Dd, A)), X[1]), 0xe9b6c7aa), 20), C)
      A = add32(rotl(add32(add32(add32(A, G32(B, C, Dd)), X[6]), 0xd62f105d), 5), B)
      Dd = add32(rotl(add32(add32(add32(Dd, G32(A, B, C)), X[11]), 0x02441453), 9), A)
      C = add32(rotl(add32(add32(add32(C, G32(Dd, A, B)), X[16]), 0xd8a1e681), 14), Dd)
      B = add32(rotl(add32(add32(add32(B, G32(C, Dd, A)), X[5]), 0xe7d3fbc8), 20), C)
      A = add32(rotl(add32(add32(add32(A, G32(B, C, Dd)), X[10]), 0x21e1cde6), 5), B)
      Dd = add32(rotl(add32(add32(add32(Dd, G32(A, B, C)), X[15]), 0xc33707d6), 9), A)
      C = add32(rotl(add32(add32(add32(C, G32(Dd, A, B)), X[4]), 0xf4d50d87), 14), Dd)
      B = add32(rotl(add32(add32(add32(B, G32(C, Dd, A)), X[9]), 0x455a14ed), 20), C)
      A = add32(rotl(add32(add32(add32(A, G32(B, C, Dd)), X[14]), 0xa9e3e905), 5), B)
      Dd = add32(rotl(add32(add32(add32(Dd, G32(A, B, C)), X[3]), 0xfcefa3f8), 9), A)
      C = add32(rotl(add32(add32(add32(C, G32(Dd, A, B)), X[8]), 0x676f02d9), 14), Dd)
      B = add32(rotl(add32(add32(add32(B, G32(C, Dd, A)), X[13]), 0x8d2a4c8a), 20), C)

      -- 轮 3
      A = add32(rotl(add32(add32(add32(A, H32(B, C, Dd)), X[6]), 0xfffa3942), 4), B)
      Dd = add32(rotl(add32(add32(add32(Dd, H32(A, B, C)), X[9]), 0x8771f681), 11), A)
      C = add32(rotl(add32(add32(add32(C, H32(Dd, A, B)), X[12]), 0x6d9d6122), 16), Dd)
      B = add32(rotl(add32(add32(add32(B, H32(C, Dd, A)), X[15]), 0xfde5380c), 23), C)
      A = add32(rotl(add32(add32(add32(A, H32(B, C, Dd)), X[2]), 0xa4beea44), 4), B)
      Dd = add32(rotl(add32(add32(add32(Dd, H32(A, B, C)), X[5]), 0x4bdecfa9), 11), A)
      C = add32(rotl(add32(add32(add32(C, H32(Dd, A, B)), X[8]), 0xf6bb4b60), 16), Dd)
      B = add32(rotl(add32(add32(add32(B, H32(C, Dd, A)), X[11]), 0xbebfbc70), 23), C)
      A = add32(rotl(add32(add32(add32(A, H32(B, C, Dd)), X[14]), 0x289b7ec6), 4), B)
      Dd = add32(rotl(add32(add32(add32(Dd, H32(A, B, C)), X[1]), 0xeaa127fa), 11), A)
      C = add32(rotl(add32(add32(add32(C, H32(Dd, A, B)), X[4]), 0xd4ef3085), 16), Dd)
      B = add32(rotl(add32(add32(add32(B, H32(C, Dd, A)), X[7]), 0x04881d05), 23), C)
      A = add32(rotl(add32(add32(add32(A, H32(B, C, Dd)), X[10]), 0xd9d4d039), 4), B)
      Dd = add32(rotl(add32(add32(add32(Dd, H32(A, B, C)), X[13]), 0xe6db99e5), 11), A)
      C = add32(rotl(add32(add32(add32(C, H32(Dd, A, B)), X[16]), 0x1fa27cf8), 16), Dd)
      B = add32(rotl(add32(add32(add32(B, H32(C, Dd, A)), X[3]), 0xc4ac5665), 23), C)

      -- 轮 4
      A = add32(rotl(add32(add32(add32(A, I32(B, C, Dd)), X[1]), 0xf4292244), 6), B)
      Dd = add32(rotl(add32(add32(add32(Dd, I32(A, B, C)), X[8]), 0x432aff97), 10), A)
      C = add32(rotl(add32(add32(add32(C, I32(Dd, A, B)), X[15]), 0xab9423a7), 15), Dd)
      B = add32(rotl(add32(add32(add32(B, I32(C, Dd, A)), X[6]), 0xfc93a039), 21), C)
      A = add32(rotl(add32(add32(add32(A, I32(B, C, Dd)), X[13]), 0x655b59c3), 6), B)
      Dd = add32(rotl(add32(add32(add32(Dd, I32(A, B, C)), X[4]), 0x8f0ccc92), 10), A)
      C = add32(rotl(add32(add32(add32(C, I32(Dd, A, B)), X[11]), 0xffeff47d), 15), Dd)
      B = add32(rotl(add32(add32(add32(B, I32(C, Dd, A)), X[2]), 0x85845dd1), 21), C)
      A = add32(rotl(add32(add32(add32(A, I32(B, C, Dd)), X[9]), 0x6fa87e4f), 6), B)
      Dd = add32(rotl(add32(add32(add32(Dd, I32(A, B, C)), X[16]), 0xfe2ce6e0), 10), A)
      C = add32(rotl(add32(add32(add32(C, I32(Dd, A, B)), X[7]), 0xa3014314), 15), Dd)
      B = add32(rotl(add32(add32(add32(B, I32(C, Dd, A)), X[14]), 0x4e0811a1), 21), C)
      A = add32(rotl(add32(add32(add32(A, I32(B, C, Dd)), X[5]), 0xf7537e82), 6), B)
      Dd = add32(rotl(add32(add32(add32(Dd, I32(A, B, C)), X[12]), 0xbd3af235), 10), A)
      C = add32(rotl(add32(add32(add32(C, I32(Dd, A, B)), X[3]), 0x2ad7d2bb), 15), Dd)
      B = add32(rotl(add32(add32(add32(B, I32(C, Dd, A)), X[10]), 0xeb86d391), 21), C)

      H[1] = add32(H[1], A) H[2] = add32(H[2], B) H[3] = add32(H[3], C) H[4] = add32(H[4], Dd)
    end

    local Xb = {}
    for i = 1, 16 do Xb[i] = 0 end

    function MD5.hex(msg)
      msg = msg or ""
      local H = { 0x67452301, 0xefcdab89, 0x98badcfe, 0x10325476 }
      local len = #msg
      local pos = 1
      while pos + 63 <= len do
        for i = 0, 15 do
          local o = pos + i * 4
          local b0, b1, b2, b3 = string.byte(msg, o, o + 3)
          Xb[i + 1] = bor(bor(b0, lshift(b1, 8)), bor(lshift(b2, 16), lshift(b3, 24)))
        end
        block(H, Xb)
        pos = pos + 64
      end
      -- 尾部 + 填充（小长度，直接建表）
      local tail = {}
      local tn = 0
      for i = pos, len do tn = tn + 1 tail[tn] = string.byte(msg, i) end
      tn = tn + 1 tail[tn] = 0x80
      while (tn % 64) ~= 56 do tn = tn + 1 tail[tn] = 0 end
      local bits = len * 8
      local lo = bits % 0x100000000
      local hi = math.floor(bits / 0x100000000)
      for i = 0, 3 do tn = tn + 1 tail[tn] = band(rshift(lo, i * 8), 0xFF) end
      for i = 0, 3 do tn = tn + 1 tail[tn] = band(rshift(hi, i * 8), 0xFF) end
      for p = 1, tn, 64 do
        for i = 0, 15 do
          local o = p + i * 4
          local b0, b1, b2, b3 = tail[o] or 0, tail[o+1] or 0, tail[o+2] or 0, tail[o+3] or 0
          Xb[i + 1] = bor(bor(b0, lshift(b1, 8)), bor(lshift(b2, 16), lshift(b3, 24)))
        end
        block(H, Xb)
      end
      local out = {}
      local n = 0
      for i = 1, 4 do
        local v = H[i]
        for j = 0, 3 do
          local by = band(rshift(v, j * 8), 0xFF)
          n = n + 1 out[n] = HEX:sub(math.floor(by/16)+1, math.floor(by/16)+1)
          n = n + 1 out[n] = HEX:sub(by%16+1, by%16+1)
        end
      end
      return table.concat(out)
    end
  end

  -- ============================================================
  -- SimHash 32 位
  -- ============================================================
  local SIM = {}
  do
    local function toU32(v) v = tobit(v) return v < 0 and v + 0x100000000 or v end
    local function add32s(a, b) return toU32(tobit(a) + tobit(b)) end
    local function lsh(v, n) return toU32(lshift(tobit(v), n)) end
    local function rsh(v, n) return toU32(rshift(tobit(v), n)) end

    -- 单字节 -> 32 位伪随机（黄金比例 + 混合）
    local function byteHash(bv)
      local h = toU32(bv * 0x9E3779B9)
      h = bxor(h, rsh(h, 16))
      h = add32s(h, lsh(h, 8))
      h = bxor(h, rsh(h, 4))
      return toU32(h)
    end
    SIM.byteHash = byteHash

    -- 文本 -> 32 位指纹（字节频数加权）
    function SIM.hash(text)
      if type(text) ~= "string" or #text == 0 then return 0 end
      local freq = {}
      for i = 1, #text do
        local b = string.byte(text, i)
        freq[b] = (freq[b] or 0) + 1
      end
      return SIM.fromWeights(freq)
    end

    -- 由「特征 -> 权重」表生成指纹（文件夹合并也走这里）
    function SIM.fromWeights(freq)
      local v = {}
      for i = 0, 31 do v[i] = 0 end
      for bv, w in pairs(freq) do
        local h = byteHash(bv)
        for i = 0, 31 do
          if band(h, lshift(1, i)) ~= 0 then v[i] = v[i] + w else v[i] = v[i] - w end
        end
      end
      local fp = 0
      for i = 0, 31 do if v[i] > 0 then fp = bor(fp, lshift(1, i)) end end
      return fp < 0 and fp + 0x100000000 or fp
    end

    -- 位向量累加（文件夹合并用，权重可指定）
    function SIM.merge(entries)
      -- entries: { {sim=number, w=number}, ... }
      local v = {}
      for i = 0, 31 do v[i] = 0 end
      for _, e in ipairs(entries) do
        local s = e.sim or 0
        local w = e.w or 1
        for i = 0, 31 do
          if band(s, lshift(1, i)) ~= 0 then v[i] = v[i] + w else v[i] = v[i] - w end
        end
      end
      local fp = 0
      for i = 0, 31 do if v[i] > 0 then fp = bor(fp, lshift(1, i)) end end
      return fp < 0 and fp + 0x100000000 or fp
    end

    local function popcount32(x)
      x = tobit(x)
      x = band(x, 0x55555555) + band(rshift(x, 1), 0x55555555)
      x = band(x, 0x33333333) + band(rshift(x, 2), 0x33333333)
      x = band(x, 0x0F0F0F0F) + band(rshift(x, 4), 0x0F0F0F0F)
      x = band(x, 0x00FF00FF) + band(rshift(x, 8), 0x00FF00FF)
      x = band(x, 0x0000FFFF) + band(rshift(x, 16), 0x0000FFFF)
      return (x < 0) and x + 0x100000000 or x
    end
    SIM.popcount = popcount32
    function SIM.hamming(a, b) return popcount32(bxor(tobit(a), tobit(b))) end
    function SIM.similarity(a, b) return 1 - SIM.hamming(a, b) / 32 end

    local HEX8 = "0123456789abcdef"
    function SIM.hex(fp)
      local out = {}
      for j = 3, 0, -1 do
        local by = band(rshift(tobit(fp), j * 8), 0xFF)
        out[#out+1] = HEX8:sub(math.floor(by/16)+1, math.floor(by/16)+1)
        out[#out+1] = HEX8:sub(by%16+1, by%16+1)
      end
      return table.concat(out)
    end
  end

  FP.MD5 = MD5
    FP.SIM = SIM
    function FP.hex(fp) return SIM.hex(fp) end

  -- 大文件：按固定逻辑块做两级 Merkle（确定性 + 可增量 + 任意大小）
  FP.sample = false   -- ★v2.1 采样开关(属性 hashMode=1 时置 true)
  function FP.md5Of(data)
    if type(data) ~= "string" then return nil end
    -- ★v2.1 采样：只哈希 头/中/尾 各 SAMP 字节，再拼上总长度
    --   实测 1MB：全量 1.29s -> 采样 0.225s（快 5.7 倍）
    --   代价：未采样区间的改动检测不到，Dedup/Same 会漏判 -> 默认关闭
    if FP.sample and #data > CFG.SAMP_MIN then
      local n, m = CFG.SAMP, math.floor(#data / 2)
      return MD5.hex(data:sub(1, n) .. data:sub(m, m + n - 1)
                     .. data:sub(-n) .. ":" .. tostring(#data))
    end
    if #data <= CFG.LBLK then return MD5.hex(data) end
    local buf, p = {}, 1
    while p <= #data do
      buf[#buf+1] = MD5.hex(data:sub(p, p + CFG.LBLK - 1))
      p = p + CFG.LBLK
    end
    return MD5.hex(table.concat(buf))
  end
  -- 超大文件：头/中/尾各采样 32KB，避免全量扫描
  function FP.simOf(data)
    if type(data) ~= "string" or #data == 0 then return 0 end
    if #data <= CFG.SIM_MAX then return SIM.hash(data) end
    local h = data:sub(1, 32768)
    local m = math.floor(#data / 2)
    return SIM.hash(h .. data:sub(m, m + 32767) .. data:sub(-32768))
  end
end
M.FP = FP


-- ============================================================
-- 二、哈夫曼压缩（输出比特流，支持不可打印字节）
-- ============================================================
local HF = {}
do
  local BW = {}
  BW.__index = BW
  function BW.new() return setmetatable({ b = {}, buf = 0, n = 0 }, BW) end
  function BW:bit(v)
    self.buf = self.buf * 2 + (v and 1 or 0)
    self.n = self.n + 1
    if self.n == 8 then self.b[#self.b+1] = string.char(self.buf) self.buf = 0 self.n = 0 end
  end
  function BW:int(v, bits)
    for i = bits - 1, 0, -1 do self:bit(math.floor(v / (2^i)) % 2 == 1) end
  end
  function BW:byte(v) self:int(v, 8) end
  function BW:str(s) for i = 1, #s do self:bit(s:sub(i,i) == "1") end end
  function BW:out()
    if self.n > 0 then
      while self.n < 8 do self.buf = self.buf * 2 self.n = self.n + 1 end
      self.b[#self.b+1] = string.char(self.buf)
    end
    return table.concat(self.b)
  end
  local BR = {}
  BR.__index = BR
  function BR.new(d) return setmetatable({ d = d, p = 1, bp = 0, cur = (#d > 0) and d:byte(1) or 0 }, BR) end
  function BR:bit()
    if self.bp == 0 then
      if self.p > #self.d then return nil end
      self.cur = self.d:byte(self.p) self.p = self.p + 1 self.bp = 8
    end
    self.bp = self.bp - 1
    return math.floor(self.cur / (2^self.bp)) % 2
  end
  function BR:int(bits)
    local v = 0
    for _ = 1, bits do
      local b = self:bit()
      if b == nil then return nil end
      v = v * 2 + b
    end
    return v
  end

  local function freq(s)
    local f = {}
    for i = 1, #s do local b = s:byte(i) f[b] = (f[b] or 0) + 1 end
    return f
  end
  local function build(f)
    local ns = {}
    for b = 0, 255 do if f[b] then ns[#ns+1] = { f = f[b], b = b } end end
    if #ns == 0 then return nil end
    if #ns == 1 then return ns[1] end
    table.sort(ns, function(a, b) return a.f < b.f end)
    while #ns > 1 do
      local l = table.remove(ns, 1)
      local r = table.remove(ns, 1)
      local p = { f = l.f + r.f, l = l, r = r }
      local i = 1
      while i <= #ns and ns[i].f < p.f do i = i + 1 end
      table.insert(ns, i, p)
    end
    return ns[1]
  end
  local function codes(n, pre, c)
    if n.l == nil and n.r == nil then c[n.b] = (pre ~= "" and pre or "0") return end
    codes(n.l, pre .. "0", c)
    codes(n.r, pre .. "1", c)
  end
  local function ser(n, w)
    if n.b then w:bit(true) w:byte(n.b)
    else w:bit(false) ser(n.l, w) ser(n.r, w) end
  end
  local function deser(r)
    local l = r:bit()
    if l == nil then return nil end
    if l == 1 then local b = r:int(8) if b == nil then return nil end return { b = b } end
    local a = deser(r) local b = deser(r)
    if not a or not b then return nil end
    return { l = a, r = b }
  end

  function HF.comp(s)
    if type(s) ~= "string" or #s == 0 then return "" end
    if #s == 1 then
      local w = BW.new() w:int(1, 8) w:byte(s:byte(1)) return w:out()
    end
    local f = freq(s)
    local t = build(f)
    local c = {}
    codes(t, "", c)
    local parts = {}
    for i = 1, #s do parts[#parts+1] = c[s:byte(i)] end
    local bs = table.concat(parts)
    local w = BW.new()
    w:int(0, 8)        -- 0 = 哈夫曼
    w:int(#s, 32)      -- 原始长度
    w:int(#bs, 32)     -- 比特数
    ser(t, w)
    w:byte(255)        -- 树结束标记
    w:str(bs)
    return w:out()
  end
  function HF.decomp(d)
    if type(d) ~= "string" or #d == 0 then return "" end
    local r = BR.new(d)
    local ty = r:int(8)
    if ty == nil then return "" end
    if ty == 1 then local b = r:int(8) return b and string.char(b) or "" end
    if ty ~= 0 then return "" end
    local n = r:int(32)
    local bl = r:int(32)
    if not n or not bl or n == 0 then return "" end
    local t = deser(r)
    if not t then return "" end
    if r:int(8) ~= 255 then return "" end
    local out = {}
    -- ★v2.1 修正：内容里只有一种字节时，哈夫曼树退化成【单个叶节点】
    --   旧版仍按 node.l / node.r 往下走 -> node 变 nil -> 索引 node.b 直接崩溃
    --   实测触发条件：长度 >= COMP_MIN(384) 且只含 1 种字节
    if t.b then
      local one = string.char(t.b)
      local g2 = 0
      while g2 < bl do
        local b = r:bit()
        if b == nil then break end
        g2 = g2 + 1
        out[#out+1] = one
      end
      return table.concat(out)
    end
    local node = t
    local got = 0
    while got < bl do
      local b = r:bit()
      if b == nil then break end
      got = got + 1
      node = (b == 0) and node.l or node.r
      if not node then break end          -- ★v2.1 防御：数据损坏时不再崩溃
      if node.b then out[#out+1] = string.char(node.b) node = t end
    end
    return table.concat(out)
  end
end
M.HF = HF

-- ============================================================
-- 三、对称加密：加密后 MAC（Encrypt-then-MAC）
--   KS  = SHA256(ek .. ctr) 逐块；tag = SHA256(mk .. ct)
--   先验证 tag 再解密 —— 无认证的 XOR 流会被 bit-flipping 篡改
-- ============================================================
local CR = {}
do
  local function ksBlock(ek, ctr)
    return SHA.bytes(ek .. ":" .. tostring(ctr))
  end
  function CR.enc(pt, ek, mk)
    local out = {}
    local ctr = 0
    for i = 1, #pt, 32 do
      local chunk = pt:sub(i, i + 31)
      local k = ksBlock(ek, ctr)
      local t = {}
      for j = 1, #chunk do
        t[j] = string.char(bit.bxor(chunk:byte(j), k:byte(j)))
      end
      out[#out+1] = table.concat(t)
      ctr = ctr + 1
    end
    local ct = table.concat(out)
    return ct, SHA.hex(mk .. "|" .. ct)
  end
  function CR.dec(ct, ek, mk, tag)
    if SHA.hex(mk .. "|" .. ct) ~= tag then return nil, "MAC校验失败:内容已被篡改" end
    local out = {}
    local ctr = 0
    for i = 1, #ct, 32 do
      local chunk = ct:sub(i, i + 31)
      local k = ksBlock(ek, ctr)
      local t = {}
      for j = 1, #chunk do
        t[j] = string.char(bit.bxor(chunk:byte(j), k:byte(j)))
      end
      out[#out+1] = table.concat(t)
      ctr = ctr + 1
    end
    return table.concat(out)
  end
  -- 由口令派生双密钥
  function CR.derive(pass, salt)
    local a = SHA.bytes(pass .. "|E|" .. salt)
    local b = SHA.bytes(pass .. "|M|" .. salt)
    return a, b, salt
  end
end
M.CR = CR

local function bin2hex(b)
  local t = {}
  for i = 1, #b do t[i] = string.format("%02x", b:byte(i)) end
  return table.concat(t)
end
local function hex2bin(h)
  local t = {}
  for i = 1, #h, 2 do t[#t+1] = string.char(tonumber(h:sub(i, i+1), 16) or 0) end
  return table.concat(t)
end
M.bin2hex, M.hex2bin = bin2hex, hex2bin

-- ============================================================
-- 四、Base94（key 安全编码：把任意二进制安全地塞进 50 字节 key）
--   94 个符号 = ASCII 33..126，不含空格
-- ============================================================
local B94 = {}
do
  local CH = {}
  for i = 33, 126 do CH[#CH+1] = string.char(i) end
  local MAP = {}
  for i, c in ipairs(CH) do MAP[c] = i - 1 end
  function B94.enc(str)
    -- 按大数处理
    local n = {}
    for i = 1, #str do
      local carry = str:byte(i)
      for j = 1, #n do
        local v = n[j] * 256 + carry
        n[j] = v % 94
        carry = math.floor(v / 94)
      end
      while carry > 0 do n[#n+1] = carry % 94 carry = math.floor(carry / 94) end
    end
    if #n == 0 then return "" end
    local t = {}
    for i = 1, #n do t[i] = CH[n[i] + 1] end
    return table.concat(t)
  end
  function B94.dec(s)
    local n = {}
    for i = 1, #s do
      local v = MAP[s:sub(i, i)]
      if not v then return nil end
      local carry = v
      for j = 1, #n do
        local x = n[j] + carry * 94
        n[j] = x % 256
        carry = math.floor(x / 256)
      end
      while carry > 0 do n[#n+1] = carry % 256 carry = math.floor(carry / 256) end
    end
    local t = {}
    for i = 1, #n do t[i] = string.char(n[i]) end
    return table.concat(t)
  end
end
M.B94 = B94

-- ============================================================
-- 五、极简 RSA（仅用于封装/解封 32 字节文件密钥 DEK）
--   RSA 明文长度受模数限制，绝不能直接加密 2MB 内容 —— 必须混合加密
-- ============================================================
local RSA = {}
do
  local bit = bit
  local W = 65536
  local BN = {}
  function BN.trim(a) while #a > 0 and a[#a] == 0 do a[#a] = nil end return a end
  function BN.cmp(a, b)
    if #a ~= #b then return (#a < #b) and -1 or 1 end
    for i = #a, 1, -1 do if a[i] ~= b[i] then return (a[i] < b[i]) and -1 or 1 end end
    return 0
  end
  function BN.add(a, b)
    local r = {} local c = 0
    for i = 1, math.max(#a, #b) do
      local t = (a[i] or 0) + (b[i] or 0) + c
      if t >= W then r[i] = t - W c = 1 else r[i] = t c = 0 end
    end
    if c == 1 then r[#r+1] = 1 end
    return r
  end
  function BN.sub(a, b)
    local r = {} local bo = 0
    for i = 1, #a do
      local t = (a[i] or 0) - (b[i] or 0) - bo
      if t < 0 then t = t + W bo = 1 else bo = 0 end
      r[i] = t
    end
    return BN.trim(r)
  end
  function BN.mul(a, b)
    local r = {}
    for i = 1, #a do
      if a[i] ~= 0 then
        local c = 0
        for j = 1, #b do
          local k = i + j - 1
          local t = (r[k] or 0) + a[i] * b[j] + c
          r[k] = t % W c = math.floor(t / W)
        end
        local k = i + #b
        while c > 0 do local t = (r[k] or 0) + c r[k] = t % W c = math.floor(t / W) k = k + 1 end
      end
    end
    return BN.trim(r)
  end
  function BN.divSmall(a, m)
    local q = {} local rem = 0
    for i = #a, 1, -1 do
      local cur = rem * W + a[i]
      q[i] = math.floor(cur / m) rem = cur - q[i] * m
    end
    return BN.trim(q), rem
  end
  function BN.fromHex(s)
    s = string.lower(s or ""):gsub("[^0-9a-f]", "")
    local p = #s % 4
    if p > 0 then s = string.rep("0", 4 - p) .. s end
    local r = {} local n = #s / 4
    for i = 1, n do r[n - i + 1] = tonumber(s:sub((i-1)*4+1, i*4), 16) or 0 end
    return BN.trim(r)
  end
  function BN.toHex(a)
    if #a == 0 then return "0" end
    local t = {}
    for i = #a, 1, -1 do t[#t+1] = string.format("%04x", a[i]) end
    local s = table.concat(t):gsub("^0+", "")
    return (s == "") and "0" or s
  end
  -- 蒙哥马利
  local MONT = {}
  function MONT.np(n)
    local n0 = n[1] or 0
    for i = 1, W - 1, 2 do if (n0 * i) % W == W - 1 then return i end end
    return 1
  end
  function MONT.setup(n)
    local k = math.max(#n, 1)
    local np = MONT.np(n)
    local function modShift(a, m)
      local r = {}
      for i = #a, 1, -1 do
        local ai = a[i]
        for b = 15, 0, -1 do
          r = BN.add(r, r)
          if bit.band(ai, bit.lshift(1, b)) ~= 0 then r = BN.add(r, { 1 }) end
          if BN.cmp(r, m) >= 0 then r = BN.sub(r, m) end
        end
      end
      return r
    end
    local function shl(a, k)
      local r = {}
      for i = 1, k do r[i] = 0 end
      for i = 1, #a do r[i + k] = a[i] end
      return r
    end
    local R = modShift(shl({ 1 }, k), n)
    local R2 = modShift(shl({ 1 }, 2 * k), n)
    return { n = n, k = k, np = np, R = R, R2 = R2 }
  end
  function MONT.mul(m, A, B)
    local n, k, np = m.n, m.k, m.np
    local t = {}
    for i = 1, k + 2 do t[i] = 0 end
    for i = 1, k do
      local ai = A[i] or 0
      local C = 0
      for j = 1, k do
        local tt = t[j] + ai * (B[j] or 0) + C
        t[j] = tt % W C = math.floor(tt / W)
      end
      local tt = t[k+1] + C
      t[k+1] = tt % W t[k+2] = math.floor(tt / W)
      local mm = (t[1] * np) % W
      local tt0 = t[1] + mm * (n[1] or 0)
      local C2 = math.floor(tt0 / W)
      for j = 2, k do
        local tt2 = t[j] + mm * (n[j] or 0) + C2
        t[j-1] = tt2 % W C2 = math.floor(tt2 / W)
      end
      local tt3 = t[k+1] + C2
      t[k] = tt3 % W t[k+1] = t[k+2] + math.floor(tt3 / W)
    end
    local r = {}
    for j = 1, k do r[j] = t[j] end
    if t[k+1] and t[k+1] ~= 0 then r[k+1] = t[k+1] end
    r = BN.trim(r)
    while BN.cmp(r, n) >= 0 do r = BN.sub(r, n) end
    return r
  end
  function MONT.pow(m, base, exp)
    local x = MONT.mul(m, base, m.R2)
    local res = m.R
    local bl = 0
    if #exp > 0 then
      local t = exp[#exp]
      bl = (#exp - 1) * 16
      while t > 0 do bl = bl + 1 t = math.floor(t / 2) end
    end
    for i = bl - 1, 0, -1 do
      res = MONT.mul(m, res, res)
      local limb = math.floor(i / 16) + 1
      if limb <= #exp and bit.band(bit.rshift(exp[limb], i % 16), 1) == 1 then
        res = MONT.mul(m, res, x)
      end
    end
    return MONT.mul(m, res, { 1 })
  end
  RSA._BN = BN
  RSA._MONT = MONT
  -- 公钥加密小数据（< 模数字节数-11）
  function RSA.enc(data, eHex, nHex)
    local n = BN.fromHex(nHex)
    local k = math.ceil((#n * 16) / 8)
    if #data > k - 11 then return nil, "数据过长" end
    local ps = {}
    for i = 1, k - #data - 3 do ps[i] = string.char(math.random(1, 255)) end
    local em = string.char(0, 2) .. table.concat(ps) .. string.char(0) .. data
    local m = MONT.setup(n)
    local x = {}
    for i = 1, #em do x = BN.add(BN.mul(x, { 256 }), { em:byte(i) }) end
    local c = MONT.pow(m, x, BN.fromHex(eHex))
    local out = {}
    local t = c
    for i = k, 1, -1 do
      local q, r = BN.divSmall(t, 256)
      out[i] = string.char(r) t = q
    end
    return table.concat(out)
  end
end
M.RSA = RSA

-- ============================================================
-- 六、文件系统核心
-- ============================================================
local function hexs(n)
  local t = {}
  for i = 1, n do t[i] = string.format("%x", math.random(0, 15)) end
  return table.concat(t)
end

local FS = {}
FS.__index = FS

function M.new(kv, varId, playerId, opts)
  opts = opts or {}
  local o = setmetatable({}, FS)
  o.kv   = kv
  o.vid  = varId
  o.pid  = playerId
  o.cache = {}        -- id -> node
  o.ct    = {}        -- ★v2.1 id -> 缓存写入时刻(ms)
  o.cms   = tonumber(opts.cacheMs) or 1500   -- ★v2.1 节点缓存有效期
  o.dirty = {}
  o.seq   = 0
  o.opts  = opts
  o.keys  = {}       -- 运行时密钥，绝不落盘
  o.shard = opts.shard or CFG.SHARD
  o.safe  = opts.safe      -- true=分片内容做 Base94 编码（兼容不支持二进制的后端）
  o.index  = (opts.index ~= false)     -- 内容寻址索引(MD5 -> 首个节点)
  o.simIdx = (opts.simIdx ~= false)    -- SimHash 鸽巢分桶索引(相似检索加速)
  return o
end

-- ★v2.1 毫秒时钟：引擎有 os.timeMs 就用它，否则退到秒级
local function NOWMS()
  if type(os) == "table" and type(os.timeMs) == "function" then
    local v = os.timeMs()
    if type(v) == "number" then return v end
  end
  return (os.time() or 0) * 1000
end
M.NOWMS = NOWMS

-- ★v2.1 清空本实例的全部缓存（节点层）
function FS:drop()
  self.cache = {}
  self.ct = {}
  if self.kv and self.kv.dropc then self.kv.dropc(self.vid, self.pid) end
  return true
end

-- ---- 键构造（全部 <= 50 字节，仅可打印 ASCII）----
-- 根锚点只存根 id；根对象本身仍是普通节点，避免两份副本不同步
function FS:kRoot()    return "r" end
function FS:kNode(id)  return "n" .. id end
function FS:kKid(id,p) return "c" .. id .. "_" .. string.format("%04x", p or 0) end
function FS:kData(id,s)return "d" .. id .. "_" .. string.format("%06x", s or 0) end
function FS:kIdx(h)    return "i" .. h end
function FS:kWal(s)    return "w" .. string.format("%08x", s) end
function FS:kKey(kid)  return "k" .. kid end
function FS:kLock(id)  return "l" .. id end

-- ---- 基础读写 ----
function FS:get(k) return self.kv.get(self.vid, self.pid, k) end
function FS:set(k, v)
  if v ~= nil and #v > CFG.MAXV then return false, "值超出上限:" .. #v end
  return self.kv.set(self.vid, self.pid, k, v)
end
function FS:del(k) return self.kv.del(self.vid, self.pid, k) end

local function jenc(t) return json.encode(t) end
local function jdec(s)
  if not s or s == "" then return nil end
  local ok, r = pcall(json.decode, s)
  if ok then return r end
  return nil
end

-- ---- 序列号 ----
function FS:nextId()
  -- ★v2.1：
  --   1) 混入本实例 salt，双开/多客户端不再拿到同一串随机序列
  --   2) 生成后立刻查一次该 id 是否已占用，占用就换下一个（最多 IDTRY 次）
  --      —— 旧版可能生成出已被别人占用的 ID，静默覆盖对方节点
  if not self.salt then self.salt = math.random(0, 0xffff) end
  local try = 0
  while try < CFG.IDTRY do
    try = try + 1
    self.seq = self.seq + 1
    local id = string.format("%04x%04x%04x",
      math.floor(os.time() % 0x10000),
      (math.random(0, 0xffff) + self.salt) % 0x10000,
      (self.seq * 7919 + self.salt) % 0x10000)
    if not self:get(self:kNode(id)) then return id end
  end
  -- 兜底：极端情况下再拼一层随机
  return string.format("%04x%04x%04x",
    math.floor(os.time() % 0x10000),
    math.random(0, 0xffff),
    math.random(0, 0xffff))
end

-- ---- 根 ----
function FS:init()
  local rid = self:get(self:kRoot())
  if rid and rid ~= "" and self:get(self:kNode(rid)) then
    return self:node(rid)
  end
  local root = {
    id = "000000000000", typ = "d", name = "", parent = nil,
    owner = 0, mode = 511, ct = os.time(), mt = os.time(), ver = 1,
    kids = {}, nk = 0, pages = 0, size = 0,
  }
  self:set(self:kNode(root.id), jenc(root))
  self:set(self:kRoot(), root.id)
  self.cache[root.id] = root
  return root
end
function FS:root()
  local rid = self:get(self:kRoot())
  if rid and rid ~= "" then
    local n = self:node(rid)
    if n then return n end
  end
  return self:init()
end

-- ---- 节点 ----
function FS:node(id)
  if not id then return nil end
  local c = self.cache[id]
  if c ~= nil then
    -- ★v2.1 TTL：cms<=0 表示不缓存；超期就丢弃重读
    if self.cms <= 0 then return c end
    if (NOWMS() - (self.ct[id] or 0)) < self.cms then return c end
    self.cache[id] = nil
  end
  local n = jdec(self:get(self:kNode(id)) or "")
  if n then self.cache[id] = n self.ct[id] = NOWMS() end
  return n
end
-- ★v2.1 绕过本地缓存直读存储（创建前的最后一道同名检查用）
function FS:getFresh(k)
  if self.kv.fresh then return self.kv.fresh(self.vid, self.pid, k) end
  return self:get(k)
end
function FS:put(n)
  n.ver = (n.ver or 0) + 1
  n.mt = os.time()
  self.cache[n.id] = n
  self.ct[n.id] = NOWMS()
  self.dirty[n.id] = true
  return self:set(self:kNode(n.id), jenc(n))
end
function FS:flush()
  local n = 0
  for id, n_ in pairs(self.dirty) do
    if self.cache[id] then self:set(self:kNode(id), jenc(self.cache[id])) end
    self.dirty[id] = nil n = n + 1
  end
  return n
end

-- ---- 子节点读取（内联 / 分页）----
function FS:kids(id)
  local n = self:node(id)
  if not n then return {} end
  if n.pages and n.pages > 0 then
    local out = {}
    for p = 0, n.pages - 1 do
      local t = jdec(self:get(self:kKid(id, p)) or "")
      if t then for k, v in pairs(t) do out[k] = v end end
    end
    return out
  end
  return n.kids or {}
end
-- ★v2.1 绕过缓存重新读一次子节点表
function FS:freshKids(id)
  self.cache[id] = nil
  local n = jdec(self:getFresh(self:kNode(id)) or "")
  if not n then return nil end
  self.cache[id] = n self.ct[id] = NOWMS()
  if n.pages and n.pages > 0 then
    local out = {}
    for p = 0, n.pages - 1 do
      local t = jdec(self:getFresh(self:kKid(id, p)) or "")
      if t then for k, v in pairs(t) do out[k] = v end end
    end
    return out
  end
  return n.kids or {}
end
function FS:putKids(id, kids)
  local n = self:node(id)
  if not n then return false end
  local cnt = 0
  for _ in pairs(kids) do cnt = cnt + 1 end
  -- 回收旧页
  if n.pages and n.pages > 0 then
    for p = 0, n.pages - 1 do self:del(self:kKid(id, p)) end
  end
  if cnt <= CFG.INLINE then
    n.kids = kids n.pages = 0
  else
    -- 分页：按名称排序后切块
    local names = {}
    for k in pairs(kids) do names[#names+1] = k end
    table.sort(names)
    local p, cur, c = 0, {}, 0
    for _, nm in ipairs(names) do
      cur[nm] = kids[nm] c = c + 1
      if c >= CFG.PAGE then
        self:set(self:kKid(id, p), jenc(cur)) p = p + 1 cur = {} c = 0
      end
    end
    if c > 0 then self:set(self:kKid(id, p), jenc(cur)) p = p + 1 end
    n.kids = {} n.pages = p
  end
  n.nk = cnt
  return self:put(n)
end

-- ---- 路径 ----
local function splitPath(p)
  local t = {}
  for s in tostring(p or ""):gmatch("[^/]+") do t[#t+1] = s end
  return t
end
local function joinPath(base, rel)
  local t = {}
  for _, s in ipairs(splitPath(base)) do t[#t+1] = s end
  for _, s in ipairs(splitPath(rel)) do
    if s == "." then
    elseif s == ".." then t[#t] = nil
    else t[#t+1] = s end
  end
  return "/" .. table.concat(t, "/")
end
M.splitPath = splitPath
M.joinPath = joinPath

-- 解析路径 -> 节点（绝对以 / 开头，否则相对 cwd）
function FS:resolve(path, cwdId, _retry)
  path = tostring(path or "/")
  local startId
  if path:sub(1, 1) == "/" then
    startId = self:root().id
  else
    startId = cwdId or self:root().id
  end
  local parts = splitPath(path)
  if #parts == 0 then return self:node(startId) end
  local cur = startId
  for _, seg in ipairs(parts) do
    if seg == "." then
      -- skip
    elseif seg == ".." then
      local p = self:node(cur)
      cur = (p and p.parent) or cur
    else
      local k = self:kids(cur)
      local nid = k[seg]
      if not nid then
        -- ★v2.1 未命中时把缓存整片丢掉再查一次：
        --   别人【新建】的目录/文件能立刻看到，而不是等 TTL 过期
        --   只在真的找不到时才付出这次代价
        if self.cms > 0 and not _retry then
          self:drop()
          return self:resolve(path, cwdId, true)
        end
        return nil
      end
      cur = nid
    end
  end
  return self:node(cur)
end

-- 节点 -> 绝对路径
function FS:abspath(id)
  local parts = {}
  local cur = id
  local guard = 0
  while cur and guard < 256 do
    guard = guard + 1
    local n = self:node(cur)
    if not n then break end
    if n.parent == nil then break end
    if n.name and n.name ~= "" then parts[#parts+1] = n.name end
    cur = n.parent
  end
  local s = ""
  for i = #parts, 1, -1 do s = s .. "/" .. parts[i] end
  return (s == "") and "/" or s
end

-- ---- 权限 ----
-- mode: unix 风格，低 9 位 rwxrwxrwx；owner=0 视为 root，恒通过
function FS:can(n, who, need)
  if not n then return false end
  who = who or self.actor or self.pid or 0
  if who == 0 then return true end
  if who == 0 then return true end
  local m = n.mode or 493
  need = need or "r"
  local shift
  if n.owner == who then shift = 6
  else shift = 0 end
  local bitv = (need == "r") and 4 or ((need == "w") and 2 or 1)
  return bit.band(bit.rshift(m, shift), bitv) ~= 0
end
function FS:chmod(id, mode, who)
  who = who or self.actor or 0
  local n = self:node(id)
  if not n then return false, "节点不存在" end
  if not (who == 0 or n.owner == who) then return false, "无权限" end
  n.mode = math.floor(mode) % 512
  return self:put(n)
end
function FS:chown(id, owner, who)
  who = who or self.actor or 0
  local n = self:node(id)
  if not n then return false, "节点不存在" end
  if who ~= 0 then return false, "只有 root 可变更属主" end
  n.owner = owner
  return self:put(n)
end

-- ---- 创建 ----
function FS:mkdir(path, who)
  local parentPath, name = path:match("^(.*)/([^/]+)$")
  if not name then name = path:match("^([^/]+)$") parentPath = "" end
  local p
  if parentPath == "" or parentPath == nil then
    p = self:root()
  else
    p = self:resolve(parentPath, self.cwd)
  end
  if not p or p.typ ~= "d" then return nil, "父目录不存在" end
  if not self:can(p, who, "w") then return nil, "父目录不可写" end
  -- ★v2.1：先读一次缓存版本做快速判断，再绕过缓存复查一次
  --   两个客户端并发创建同名项时，这一步能把窗口收窄到「检查->写入」一瞬
  local k = self:kids(p.id)
  if k[name] then return nil, "已存在同名项" end
  local kf = self:freshKids(p.id) or k
  if kf[name] then return nil, "已存在同名项(并发)" end
  k = kf
  local n = {
    id = self:nextId(), typ = "d", name = name, parent = p.id,
    owner = who or self.pid or 0, mode = 493,
    ct = os.time(), mt = os.time(), ver = 0,
    kids = {}, nk = 0, pages = 0, size = 0,
  }
  n.md5 = FP.MD5.hex("")
  n.sim = 0
  n.hm  = "merkle"
  self:put(n)
  k[name] = n.id
  self:putKids(p.id, k)
  self:idxAdd(self:abspath(n.id), n.id)
  self:refreshUp(n.id)
  self:fpIndex(n)
  return n
end

-- 写内容（分片 + 可选压缩 + 可选加密）
function FS:_store(id, data, n)
  -- 清旧分片
  if n.shards then
    for s = 0, n.shards - 1 do self:del(self:kData(id, s)) end
  end
  local body = data
  local comp = "none"
  if #data >= CFG.COMP_MIN and #data <= CFG.COMP_MAX then
    local c = HF.comp(data)
    if #c < #data then body = c comp = "huff" end
  end
  local enc = "none"
  local tag = nil
  local K = self.keys[id]
  if K and K.ek and K.mk then
    local ct, tg = CR.enc(body, K.ek, K.mk)
    body, tag, enc = ct, tg, "sym"
  end
  if self.safe then body = B94.enc(body) end
  local shards = math.max(1, math.ceil(#body / self.shard))
  for s = 0, shards - 1 do
    local chunk = body:sub(s * self.shard + 1, (s + 1) * self.shard)
    local ok, e = self:set(self:kData(id, s), chunk)
    if not ok then return false, e end
  end
  n.shards = shards
  n.csize = #body
  n.size  = #data
  n.comp  = comp
  n.enc   = enc
  n.tag   = tag
  n.md5 = FP.md5Of(data)
  n.sim = FP.simOf(data)
  n.hm  = (#data > CFG.LBLK) and "merkle" or "full"
  return true
end

function FS:_load(n)
  if not n or n.typ ~= "f" then return nil, "不是文件" end
  if not n.shards or n.shards == 0 then return "" end
  local parts = {}
  for s = 0, n.shards - 1 do
    local c = self:get(self:kData(n.id, s))
    if c == nil then return nil, "分片缺失:" .. s end
    parts[#parts+1] = c
  end
  local body = table.concat(parts)
  if self.safe then body = B94.dec(body) or "" end
  if n.enc == "sym" then
    local K = self.keys[n.id]
    if not (K and K.ek and K.mk) then return nil, "未解锁:请先 SetKey 或 Unlock" end
    local pt, e = CR.dec(body, K.ek, K.mk, n.tag)
    if not pt then return nil, e end
    body = pt
  elseif n.enc == "hybrid" then
    return nil, "混合加密需先用私钥解封 DEK"
  end
  if n.comp == "huff" then body = HF.decomp(body) end
  return body
end

function FS:mkfile(path, content, who)
  local parentPath, name = path:match("^(.*)/([^/]+)$")
  if not name then name = path:match("^([^/]+)$") parentPath = "" end
  local p
  if parentPath == "" or parentPath == nil then p = self:root()
  else p = self:resolve(parentPath, self.cwd) end
  if not p or p.typ ~= "d" then return nil, "父目录不存在" end
  if not self:can(p, who, "w") then return nil, "父目录不可写" end
  -- ★v2.1：先读一次缓存版本做快速判断，再绕过缓存复查一次
  --   两个客户端并发创建同名项时，这一步能把窗口收窄到「检查->写入」一瞬
  local k = self:kids(p.id)
  if k[name] then return nil, "已存在同名项" end
  local kf = self:freshKids(p.id) or k
  if kf[name] then return nil, "已存在同名项(并发)" end
  k = kf
  content = content or ""
  local n = {
    id = self:nextId(), typ = "f", name = name, parent = p.id,
    owner = who or self.pid or 0, mode = 420,
    ct = os.time(), mt = os.time(), ver = 0,
    size = #content, shards = 0,
  }
  local ok, e = self:_store(n.id, content, n)
  if not ok then return nil, e end
  self:put(n)
  k[name] = n.id
  self:putKids(p.id, k)
  self:idxAdd(self:abspath(n.id), n.id)
  self:refreshUp(n.id)
  self:fpIndex(n)
  return n
end

function FS:write(id, content, who)
  local n = self:node(id)
  if not n or n.typ ~= "f" then return false, "不是文件" end
  if not self:can(n, who, "w") then return false, "无写权限" end
  if n.md5 then self:fpUnindex(n) end
  local ok, e = self:_store(id, content, n)
  if not ok then return false, e end
  n.size = #content
  local r = self:put(n)
  self:fpIndex(n)
  self:refreshUp(n.parent)
  return r
end

function FS:read(id, who)
  local n = self:node(id)
  if not n then return nil, "节点不存在" end
  if n.typ == "d" then return nil, "是目录" end
  if not self:can(n, who, "r") then return nil, "无读权限" end
  return self:_load(n)
end

-- ---- 列举（支持分页）----
function FS:list(id, who, off, lim)
  local n = self:node(id)
  if not n or n.typ ~= "d" then return nil, "不是目录" end
  if not self:can(n, who, "r") then return nil, "无读权限" end
  local k = self:kids(id)
  local names = {}
  for nm in pairs(k) do names[#names+1] = nm end
  table.sort(names)
  off = off or 0
  lim = lim or 1000
  local out = {}
  for i = off + 1, math.min(#names, off + lim) do
    local cid = k[names[i]]
    local c = self:node(cid)
    out[#out+1] = {
      name = names[i], id = cid,
      typ = c and c.typ or "?",
      size = c and c.size or 0,
      mode = c and c.mode or 0,
      owner = c and c.owner or 0,
      mt = c and c.mt or 0,
      enc = c and c.enc or "none",
    }
  end
  return out, #names
end

-- ---- 重命名 / 移动 ----
function FS:rename(id, newName, who)
  local n = self:node(id)
  if not n or not n.parent then return false, "不能重命名根" end
  local p = self:node(n.parent)
  if not self:can(p, who, "w") then return false, "无权限" end
  local k = self:kids(p.id)
  if k[newName] then return false, "目标名已存在" end
  k[n.name] = nil
  k[newName] = id
  n.name = newName
  self:put(n)
  self:putKids(p.id, k)
  self:refreshUp(p.id)
  return true
end

-- 移动：只改父边 + 自身 parent，后代不变 —— O(深度)，与子树大小无关
function FS:move(id, newParentId, who)
  local n = self:node(id)
  if not n or not n.parent then return false, "不能移动根" end
  local np = self:node(newParentId)
  if not np or np.typ ~= "d" then return false, "目标目录不存在" end
  -- 环检测：newParent 不能是 id 的后代
  local cur = newParentId
  local guard = 0
  while cur and guard < 512 do
    guard = guard + 1
    if cur == id then return false, "不能移动到自身子树内" end
    local c = self:node(cur)
    cur = c and c.parent
  end
  local op = self:node(n.parent)
  if not self:can(op, who, "w") or not self:can(np, who, "w") then
    return false, "无权限"
  end
  local ok = self:kids(np.id)
  if ok[n.name] then return false, "目标目录已存在同名项" end
  local fk = self:kids(op.id)
  fk[n.name] = nil
  self:putKids(op.id, fk)
  ok[n.name] = id
  n.parent = newParentId
  self:put(n)
  self:putKids(np.id, ok)
  self:refreshUp(op.id)
  self:refreshUp(np.id)
  return true
end


-- ============================================================
-- 指纹：Merkle 向上传播 / 索引 / 查询
-- ============================================================
-- 重算目录指纹并沿父链向上传播（O(深度 × 子项数)）
function FS:refreshUp(id)
  local guard, cur = 0, id
  while cur and guard < 512 do
    guard = guard + 1
    local n = self:node(cur)
    if not n then break end
    if n.typ == "d" then
      local k = self:kids(cur)
      local names, items, buf = {}, {}, {}
      for nm in pairs(k) do names[#names+1] = nm end
      table.sort(names)
      for _, nm in ipairs(names) do
        local c = self:node(k[nm])
        if c then
          buf[#buf+1] = nm .. "\0" .. (c.typ or "f") .. "\0" .. (c.md5 or "")
          local w = 1
          if c.typ ~= "d" then w = 1 + math.floor((c.size or 0) / 4096) end
          items[#items+1] = { sim = c.sim or 0, w = w }
        end
      end
      n.md5 = FP.MD5.hex(table.concat(buf, "\1"))
      n.sim = (#items > 0) and FP.SIM.merge(items) or 0
      n.hm  = "merkle"
      self:put(n)
    end
    cur = n.parent
  end
end

-- 分桶 key：32 位切 4 段 × 8 位
function FS:kSim(seg, v) return "s" .. seg .. v end

function FS:fpIndex(n)
  if not n then return end
  if self.index and n.typ == "f" and n.md5 then
    if not self:get(self:kIdx(n.md5)) then self:set(self:kIdx(n.md5), n.id) end
  end
  if not (self.simIdx and n.sim) then return end
  local hx = FP.SIM.hex(n.sim)
  for seg = 0, 3 do
    local v = hx:sub(seg * 2 + 1, seg * 2 + 2)
    local key = self:kSim(seg, v)
    local t = jdec(self:get(key) or "")
    if type(t) ~= "table" then t = {} end
    local have = false
    for _, x in ipairs(t) do if x == n.id then have = true break end end
    if not have then t[#t+1] = n.id self:set(key, jenc(t)) end
  end
end

function FS:fpUnindex(n)
  if not n then return end
  if self.simIdx and n.sim then
    local hx = FP.SIM.hex(n.sim)
    for seg = 0, 3 do
      local key = self:kSim(seg, hx:sub(seg * 2 + 1, seg * 2 + 2))
      local t = jdec(self:get(key) or "")
      if type(t) == "table" then
        local o = {}
        for _, x in ipairs(t) do if x ~= n.id then o[#o+1] = x end end
        if #o > 0 then self:set(key, jenc(o)) else self:del(key) end
      end
    end
  end
end

-- 相同判断（MD5）
function FS:same(idA, idB)
  local a, b = self:node(idA), self:node(idB)
  if not a or not b then return nil, "节点不存在" end
  if not (a.md5 and b.md5) then return nil, "缺少指纹" end
  return (a.md5 == b.md5) and 1 or 0
end

-- 相似度（SimHash 汉明距离）
function FS:sim(idA, idB)
  local a, b = self:node(idA), self:node(idB)
  if not a or not b then return nil, "节点不存在" end
  return FP.SIM.similarity(a.sim or 0, b.sim or 0)
end

-- 相似检索：鸽巢原理（汉明距离 ≤3 时，4 段中必有一段完全相同）
function FS:simFind(id, thr, limit, who)
  local n = self:node(id)
  if not n then return nil, "节点不存在" end
  thr = tonumber(thr) or 3
  limit = tonumber(limit) or 50
  local target = n.sim or 0
  local hx = FP.SIM.hex(target)
  local cand, seen = {}, {}
  if self.simIdx then
    for seg = 0, 3 do
      local t = jdec(self:get(self:kSim(seg, hx:sub(seg*2+1, seg*2+2))) or "")
      if type(t) == "table" then
        for _, x in ipairs(t) do if not seen[x] then seen[x] = 1 cand[#cand+1] = x end end
      end
    end
  end
  if #cand == 0 then cand = self:_allIds(nil, 20000) end
  local out = {}
  for _, cid in ipairs(cand) do
    if cid ~= n.id then
      local c = self:node(cid)
      if c and self:can(c, who, "r") then
        local d = FP.SIM.hamming(target, c.sim or 0)
        if d <= thr then
          out[#out+1] = { path = self:abspath(cid), id = cid, typ = c.typ,
                          dist = d, sim = 1 - d / 32, size = c.size or 0 }
        end
      end
    end
  end
  table.sort(out, function(a, b) return a.dist < b.dist end)
  local r = {}
  for i = 1, math.min(#out, limit) do r[i] = out[i] end
  return r
end

-- 全量 id 列表（分桶索引不可用时的退化路径）
function FS:_allIds(startId, limit)
  local out, stack = {}, { startId or self:root().id }
  local guard = 0
  while #stack > 0 and #out < limit and guard < 200000 do
    guard = guard + 1
    local cur = table.remove(stack)
    local n = self:node(cur)
    if n then
      out[#out+1] = cur
      if n.typ == "d" then
        local k = self:kids(cur)
        for _, v in pairs(k) do stack[#stack+1] = v end
      end
    end
  end
  return out
end

-- 重复扫描：按 md5 分组
function FS:dedupScan(startId, limit)
  local groups, order, seen = {}, {}, {}
  local ids = self:_allIds(startId, tonumber(limit) or 20000)
  local waste = 0
  for _, cid in ipairs(ids) do
    local c = self:node(cid)
    if c and c.typ == "f" and c.md5 then
      local g = groups[c.md5]
      if not g then g = { md5 = c.md5, size = c.size or 0, items = {} } groups[c.md5] = g order[#order+1] = g end
      g.items[#g.items+1] = { path = self:abspath(cid), id = cid }
      if #g.items > 1 then waste = waste + (c.size or 0) end
    end
  end
  local out = {}
  for _, g in ipairs(order) do if #g.items > 1 then out[#out+1] = g end end
  table.sort(out, function(a, b) return #b.items * (b.size or 0) > #a.items * (a.size or 0) end)
  return out, waste, #ids
end

-- 重建全部分桶索引
function FS:reindex()
  local ids = self:_allIds(nil, 200000)
  local cleared, n = {}, 0
  for seg = 0, 3 do
    for i = 0, 255 do
      local v = string.format("%02x", i)
      self:del(self:kSim(seg, v))
    end
  end
  for _, cid in ipairs(ids) do
    local c = self:node(cid)
    if c then self:fpIndex(c) n = n + 1 end
  end
  return n
end

-- ---- 删除（递归）----
function FS:remove(id, who)
  local n = self:node(id)
  if not n then return false, "节点不存在" end
  if not n.parent then return false, "不能删除根" end
  local p = self:node(n.parent)
  if not self:can(p, who, "w") then return false, "无权限" end
  local function rec(cid)
    local c = self:node(cid)
    if not c then return end
    if c.typ == "d" then
      local k = self:kids(cid)
      for _, v in pairs(k) do rec(v) end
      if c.pages and c.pages > 0 then
        for pp = 0, c.pages - 1 do self:del(self:kKid(cid, pp)) end
      end
    else
      for s = 0, (c.shards or 0) - 1 do self:del(self:kData(cid, s)) end
    end
    self:idxDel(self:abspath(cid))
    self:fpUnindex(c)
    self:del(self:kNode(cid))
    self.cache[cid] = nil
  end
  rec(id)
  local k = self:kids(p.id)
  k[n.name] = nil
  self:putKids(p.id, k)
  self:refreshUp(p.id)
  return true
end

-- ---- 复制 ----
function FS:copy(id, newParentId, newName, who)
  local n = self:node(id)
  if not n then return false, "源不存在" end
  local np = self:node(newParentId)
  if not np or np.typ ~= "d" then return false, "目标目录不存在" end
  if not self:can(np, who, "w") then return false, "无权限" end
  local k = self:kids(newParentId)
  local nm = newName or n.name
  if k[nm] then return false, "目标已存在同名项" end
  local function rec(src, par, name)
    local s = self:node(src)
    if not s then return nil end
    local dst = {
      id = self:nextId(), typ = s.typ, name = name, parent = par,
      owner = s.owner, mode = s.mode, ct = os.time(), mt = os.time(), ver = 0,
    }
    if s.typ == "f" then
      local data, e = self:_load(s)
      if not data then return nil, e end
      if self.keys[src] then self.keys[dst.id] = self.keys[src] end
      dst.salt = s.salt
      local ok, e2 = self:_store(dst.id, data, dst)
      if not ok then return nil, e2 end
    else
      dst.kids = {} dst.nk = 0 dst.pages = 0 dst.size = 0
    end
    self:put(dst)
    if s.typ == "d" then
      local kk = self:kids(src)
      local nk = {}
      for cn, cv in pairs(kk) do
        local c = rec(cv, dst.id, cn)
        if c then nk[cn] = c.id end
      end
      self:putKids(dst.id, nk)
    end
    return dst
  end
  local d = rec(id, newParentId, nm)
  if not d then return false, "复制失败" end
  k = self:kids(newParentId)
  k[nm] = d.id
  self:putKids(newParentId, k)
  self:fpIndex(d)
  self:refreshUp(newParentId)
  return true, d.id
end

-- ---- 路径索引（可选加速，缺失时自动回退树遍历）----
function FS:idxAdd(path, id)
  if not self.opts.index then return end
  local h = SHA.hex(path):sub(1, 2)
  local k = self:kIdx(h)
  local t = jdec(self:get(k) or "") or {}
  t[path] = id
  if #jenc(t) > CFG.MAXV then return end
  self:set(k, jenc(t))
end
function FS:idxDel(path)
  if not self.opts.index then return end
  local h = SHA.hex(path):sub(1, 2)
  local k = self:kIdx(h)
  local t = jdec(self:get(k) or "")
  if t and t[path] then t[path] = nil self:set(k, jenc(t)) end
end
function FS:idxGet(path)
  if not self.opts.index then return nil end
  local h = SHA.hex(path):sub(1, 2)
  local t = jdec(self:get(self:kIdx(h)) or "")
  return t and t[path]
end

-- ---- 通配符匹配 ----
local function wild(pat, s)
  pat = pat:gsub("([%.%+%-%^%$%(%)%%%[%]])", "%%%1")
  pat = pat:gsub("%*", ".*"):gsub("%?", ".")
  return s:match("^" .. pat .. "$") ~= nil
end
M.wild = wild

-- ---- 搜索：支持绝对/相对路径、glob、递归 ----
-- pattern 例: "/a/*/c*.txt"  或  "*.lua"（相对 startId 递归）
function FS:find(pattern, startId, who, limit)
  limit = limit or 200
  local res = {}
  local pats = splitPath(pattern or "*")
  local absolute = tostring(pattern):sub(1, 1) == "/"
  local function walk(dirId, depth, prefix)
    if depth > #pats then return end
    if #res >= limit then return end
    local n = self:node(dirId)
    if not n or not self:can(n, who, "r") then return end
    local pat = pats[depth]
    if pat == "**" then
      local k = self:kids(dirId)
      for nm, cid in pairs(k) do
        local c = self:node(cid)
        if c then
          if c.typ == "d" then walk(cid, depth, prefix .. nm .. "/")
          else res[#res+1] = { path = prefix .. nm, id = cid, node = c } end
        end
      end
      if depth < #pats then
        for nm, cid in pairs(k) do
          local c = self:node(cid)
          if c and c.typ == "d" then walk(cid, depth + 1, prefix .. nm .. "/") end
        end
      end
      return
    end
    local k = self:kids(dirId)
    if depth == #pats and not pat:find("[%*%?]") then
      local cid = k[pat]
      if cid then
        local c = self:node(cid)
        res[#res+1] = { path = prefix .. pat, id = cid, node = c }
      end
      return
    end
    local names = {}
    for nm in pairs(k) do names[#names+1] = nm end
    table.sort(names)
    for _, nm in ipairs(names) do
      if wild(pat, nm) then
        local cid = k[nm]
        if depth == #pats then
          local c = self:node(cid)
          res[#res+1] = { path = prefix .. nm, id = cid, node = c }
        else
          local c = self:node(cid)
          if c and c.typ == "d" then walk(cid, depth + 1, prefix .. nm .. "/") end
        end
      end
    end
  end
  -- 单段模式（如 "*.lua"）默认递归，语义等同 find . -name
  if (not absolute) and #pats == 1 and pats[1] ~= "**" then
    pats = { "**", pats[1] }
  end
  local start = absolute and self:root().id or (startId or self:root().id)
  -- 相对且非递归：从 startId 逐层
  if not absolute and not startId then start = self.cwd or self:root().id end
  walk(start, 1, absolute and "/" or "")
  return res
end

-- ---- 内容搜索（grep）----
function FS:grep(pattern, startId, who, limit)
  limit = limit or 20
  local hits = {}
  local all = self:find("**", startId, who, 5000)
  for _, e in ipairs(all) do
    if #hits >= limit then break end
    if e.node and e.node.typ == "f" and self:can(e.node, who, "r") then
      local data = self:_load(e.node)
      if data and data:find(pattern, 1, true) then
        local pos = data:find(pattern, 1, true)
        hits[#hits+1] = { path = e.path, id = e.id, at = pos,
                          line = data:sub(math.max(1, pos - 20), pos + 40) }
      end
    end
  end
  return hits
end

-- ---- 打包 / 解包（目录 -> 单文件；跨表迁移同一格式）----
-- 包格式：KVPK1\n 然后每条 [4B len][path]\n[4B len][meta json][8B len][content]
function FS:pack(id, opt)
  opt = opt or {}
  local root = self:node(id)
  if not root then return nil, "节点不存在" end
  local parts = {}
  local function rec(nid, rel)
    local n = self:node(nid)
    if not n then return end
    local meta = {
      t = n.typ, m = n.mode, o = n.owner, c = n.ct, u = n.mt,
      e = n.enc, k = n.comp, h = n.hash,
    }
    local data = ""
    if n.typ == "f" then data = self:_load(n) or "" end
    parts[#parts+1] = string.format("%08x", #rel) .. rel
    local mj = jenc(meta)
    parts[#parts+1] = string.format("%08x", #mj) .. mj
    parts[#parts+1] = string.format("%016x", #data) .. data
    if n.typ == "d" then
      local k = self:kids(nid)
      local names = {}
      for nm in pairs(k) do names[#names+1] = nm end
      table.sort(names)
      for _, nm in ipairs(names) do rec(k[nm], rel == "" and nm or (rel .. "/" .. nm)) end
    end
  end
  rec(id, opt.name or root.name or "")
  local raw = table.concat(parts)
  -- 只压载荷，不压 magic 头：否则解包时会少剥一层
  if opt.comp ~= false and #raw >= CFG.COMP_MIN then
    local c = HF.comp(raw)
    if #c < #raw then return "KVPZ1\n" .. c, #raw, #c end
  end
  return "KVPK1\n" .. raw, #raw, #raw
end

-- 解包到指定父目录
function FS:unpack(data, parentId, opt)
  opt = opt or {}
  local magic = data:sub(1, 6)
  if magic == "KVPZ1\n" then data = HF.decomp(data:sub(7)) elseif magic == "KVPK1\n" then data = data:sub(7)
  else return nil, "不是合法的包" end
  local p = 1
  local created, failed = 0, 0
  local idmap = {}
  local function rd(n)
    local s = data:sub(p, p + n - 1) p = p + n return s
  end
  while p <= #data do
    local l1 = tonumber(rd(8), 16) if not l1 then break end
    local rel = rd(l1)
    local l2 = tonumber(rd(8), 16) if not l2 then break end
    local mj = rd(l2)
    local l3 = tonumber(rd(16), 16) if not l3 then break end
    local content = rd(l3)
    local meta = jdec(mj) or {}
    -- 逐级创建
    local curPar = parentId
    local segs = splitPath(rel)
    for i = 1, #segs - 1 do
      local kk = self:kids(curPar)
      local cid = kk[segs[i]]
      if not cid then
        local nn = { id = self:nextId(), typ = "d", name = segs[i], parent = curPar,
                     owner = meta.o or 0, mode = meta.m or 493, ct = meta.c or os.time(),
                     mt = os.time(), ver = 0, kids = {}, nk = 0, pages = 0, size = 0 }
        self:put(nn)
        kk[segs[i]] = nn.id
        self:putKids(curPar, kk)
        curPar = nn.id
      else
        curPar = cid
      end
    end
    local kk = self:kids(curPar)
    local nm = segs[#segs] or rel
    if opt.overwrite and kk[nm] then self:remove(kk[nm], 0) kk = self:kids(curPar) end
    if kk[nm] then failed = failed + 1
    else
      local n = { id = self:nextId(), typ = meta.t or "f", name = nm, parent = curPar,
                  owner = meta.o or 0, mode = meta.m or 420, ct = meta.c or os.time(),
                  mt = os.time(), ver = 0 }
      if n.typ == "f" then
        local ok, e = self:_store(n.id, content, n)
        if not ok then failed = failed + 1 end
      else
        n.kids = {} n.nk = 0 n.pages = 0 n.size = 0
      end
      self:put(n)
      kk[nm] = n.id
      self:putKids(curPar, kk)
      created = created + 1
    end
  end
  return created, failed
end

-- ---- 跨表迁移（上传/下载）----
function FS:export(id, dstFs, dstParentId, opt)
  opt = opt or {}
  local data, raw, packed = self:pack(id, opt)
  if not data then return nil, "打包失败" end
  return dstFs:unpack(data, dstParentId or dstFs:root().id, opt), raw, packed
end

-- ---- 加密：对称 ----
function FS:setKey(id, pass, who)
  who = who or self.actor or 0
  local n = self:node(id)
  if not n then return false, "节点不存在" end
  if not (who == 0 or n.owner == who) then return false, "无权限" end
  local salt = n.salt or hexs(8)
  local dek = SHA.bytes(tostring(pass) .. "|" .. salt)
  local ek  = SHA.bytes(dek .. "|E")
  local mk  = SHA.bytes(dek .. "|M")
  local old = self.keys[id]
  self.keys[id] = nil
  local plain
  if n.typ == "f" then plain = self:_load(n) end
  self.keys[id] = { ek = ek, mk = mk, dek = dek }
  n.salt = salt
  if n.typ == "f" then
    if plain == nil then self.keys[id] = old return false, "无法读取原文" end
    n.enc = "sym"
    local ok, e = self:_store(id, plain, n)
    if not ok then self.keys[id] = old return false, e end
  else
    n.enc = "none"
  end
  return self:put(n)
end

-- 用口令解锁（同一会话内再次访问已加密文件）
function FS:unlock(id, pass, who)
  local n = self:node(id)
  if not n or not n.salt then return false, "该节点未设置加密" end
  local dek = SHA.bytes(tostring(pass) .. "|" .. n.salt)
  self.keys[id] = { ek = SHA.bytes(dek .. "|E"), mk = SHA.bytes(dek .. "|M"), dek = dek }
  -- 试解密一片验证口令
  local d, e = self:_load(n)
  if d == nil then self.keys[id] = nil return false, tostring(e) end
  return true
end

-- 混合加密：DEK 由 RSA 公钥封装
function FS:wrapKey(id, eHex, nHex, keyId, who)
  local n = self:node(id)
  if not n then return false, "节点不存在" end
  local K = self.keys[id]
  if not (K and K.dek) then return false, "请先 SetKey/Unlock 载入密钥" end
  local ct = RSA.enc(K.dek, eHex, nHex)   -- 32 字节，RSA-512 即可容纳
  if not ct then return false, "RSA 封装失败" end
  n.wrap = n.wrap or {}
  n.wrap[keyId or "default"] = bin2hex(ct)   -- 二进制密文以 hex 落盘，避免破坏 JSON
  -- 不改写 n.enc：属主仍可用口令读，wrap 只是给接收者多一条解密路径
  return self:put(n)
end

-- ---- 统计 ----
function FS:stat(id)
  local n = self:node(id)
  if not n then return nil end
  return {
    id = n.id, typ = n.typ, name = n.name, path = self:abspath(n.id),
    size = n.size or 0, csize = n.csize or 0, shards = n.shards or 0,
    comp = n.comp or "none", enc = n.enc or "none",
    md5 = n.md5, sim = n.sim and FP.SIM.hex(n.sim) or nil, simd = n.sim, hm = n.hm,
    mode = n.mode, owner = n.owner, ct = n.ct, mt = n.mt, ver = n.ver,
    nk = n.nk or 0, pages = n.pages or 0,
  }
end

-- ---- 配额 ----
function FS:usage(who)
  local total, files = 0, 0
  local function rec(id)
    local n = self:node(id)
    if not n then return end
    if n.typ == "f" then
      if who == nil or n.owner == who then total = total + (n.size or 0) files = files + 1 end
    else
      local k = self:kids(id)
      for _, v in pairs(k) do rec(v) end
    end
  end
  rec(self:root().id)
  return total, files
end

-- ====================================================================
local Script = {}
local INDEX_ON = 1
local SAFE_ON = 0
local HASH_MODE = 0       -- ★v2.1 0=全量指纹 1=采样指纹
Script.propertys = {
  indexOn = { type = Mini.Number, default = 1, displayName = "路径索引(1开/0关)", minValue = 0, maxValue = 1 },
  shardSize = { type = Mini.Number, default = 1048576, displayName = "分片大小(字节)", minValue = 65536, maxValue = 1900000 },
  safeMode = { type = Mini.Number, default = 0, displayName = "分片Base94编码(1开)", minValue = 0, maxValue = 1 },
  useCache = { type = Mini.Number, default = 1, displayName = "读缓存(1开/0关)", minValue = 0, maxValue = 1,
               tips = "多人共享同一变量时建议 0; 或保留 1 并把 cacheMs 调小" },
  cacheMs = { type = Mini.Number, default = 1500, displayName = "缓存有效期(毫秒)", minValue = 0, maxValue = 60000,
              tips = "0=完全不缓存(每次直读, 最准最慢); 1500=别人的改动最多晚 1.5 秒被看到" },
  hashMode = { type = Mini.Number, default = 0, displayName = "指纹采样(0全量/1采样)", minValue = 0, maxValue = 1,
               tips = "1=只哈希头中尾各 64KB, 大文件快约 5.7 倍; 代价是 Dedup/Same 可能漏判未采样区" },
}
Script.openFnArgs = {
  Init = { returnType = Mini.String, displayName = "初始化文件系统", params = { "变量ID", Mini.String, "玩家", Mini.Number, "广播消息ID", Mini.String } },
  Mkdir = { returnType = Mini.String, displayName = "创建目录", params = { "变量ID", Mini.String, "玩家", Mini.Number, "路径", Mini.String, "广播消息ID", Mini.String } },
  MkFile = { returnType = Mini.String, displayName = "创建文件", params = { "变量ID", Mini.String, "玩家", Mini.Number, "路径", Mini.String, "内容", Mini.String, "广播消息ID", Mini.String } },
  Read = { returnType = Mini.String, displayName = "读取文件", params = { "变量ID", Mini.String, "玩家", Mini.Number, "路径", Mini.String, "广播消息ID", Mini.String } },
  Write = { returnType = Mini.String, displayName = "写入文件", params = { "变量ID", Mini.String, "玩家", Mini.Number, "路径", Mini.String, "内容", Mini.String, "广播消息ID", Mini.String } },
  List = { returnType = Mini.String, displayName = "列举目录", params = { "变量ID", Mini.String, "玩家", Mini.Number, "路径", Mini.String, "偏移", Mini.Number, "条数", Mini.Number, "广播消息ID", Mini.String } },
  Stat = { returnType = Mini.String, displayName = "查看属性", params = { "变量ID", Mini.String, "玩家", Mini.Number, "路径", Mini.String, "广播消息ID", Mini.String } },
  Remove = { returnType = Mini.String, displayName = "递归删除", params = { "变量ID", Mini.String, "玩家", Mini.Number, "路径", Mini.String, "广播消息ID", Mini.String } },
  Rename = { returnType = Mini.String, displayName = "重命名", params = { "变量ID", Mini.String, "玩家", Mini.Number, "路径", Mini.String, "新名", Mini.String, "广播消息ID", Mini.String } },
  Move = { returnType = Mini.String, displayName = "移动", params = { "变量ID", Mini.String, "玩家", Mini.Number, "路径", Mini.String, "目标父目录", Mini.String, "广播消息ID", Mini.String } },
  Copy = { returnType = Mini.String, displayName = "复制", params = { "变量ID", Mini.String, "玩家", Mini.Number, "路径", Mini.String, "目标父目录", Mini.String, "新名", Mini.String, "广播消息ID", Mini.String } },
  Find = { returnType = Mini.String, displayName = "路径/通配符搜索", params = { "变量ID", Mini.String, "玩家", Mini.Number, "模式", Mini.String, "起始路径", Mini.String, "上限", Mini.Number, "广播消息ID", Mini.String } },
  Grep = { returnType = Mini.String, displayName = "内容搜索", params = { "变量ID", Mini.String, "玩家", Mini.Number, "关键字", Mini.String, "起始路径", Mini.String, "上限", Mini.Number, "广播消息ID", Mini.String } },
  Pack = { returnType = Mini.String, displayName = "打包目录成单文件", params = { "变量ID", Mini.String, "玩家", Mini.Number, "路径", Mini.String, "压缩(1/0)", Mini.Number, "广播消息ID", Mini.String } },
  Unpack = { returnType = Mini.String, displayName = "解包到目录", params = { "变量ID", Mini.String, "玩家", Mini.Number, "包数据", Mini.String, "目标路径", Mini.String, "覆盖(1/0)", Mini.Number, "广播消息ID", Mini.String } },
  Upload = { returnType = Mini.String, displayName = "跨表上传/下载", params = { "源变量ID", Mini.String, "源玩家", Mini.Number, "源路径", Mini.String, "目标变量ID", Mini.String, "目标玩家", Mini.Number, "目标路径", Mini.String, "广播消息ID", Mini.String } },
  Chmod = { returnType = Mini.String, displayName = "改权限", params = { "变量ID", Mini.String, "玩家", Mini.Number, "路径", Mini.String, "模式", Mini.Number, "广播消息ID", Mini.String } },
  Chown = { returnType = Mini.String, displayName = "改属主", params = { "变量ID", Mini.String, "玩家", Mini.Number, "路径", Mini.String, "属主", Mini.Number, "广播消息ID", Mini.String } },
  SetKey = { returnType = Mini.String, displayName = "对称加密", params = { "变量ID", Mini.String, "玩家", Mini.Number, "路径", Mini.String, "口令", Mini.String, "广播消息ID", Mini.String } },
  WrapKey = { returnType = Mini.String, displayName = "RSA封装文件密钥", params = { "变量ID", Mini.String, "玩家", Mini.Number, "路径", Mini.String, "公钥e(hex)", Mini.String, "模数n(hex)", Mini.String, "密钥ID", Mini.String, "广播消息ID", Mini.String } },
  Usage = { returnType = Mini.String, displayName = "配额统计", params = { "变量ID", Mini.String, "玩家", Mini.Number, "按属主", Mini.Number, "广播消息ID", Mini.String } },
  DropCache = { returnType = Mini.String, displayName = "释放缓存", params = { "变量ID", Mini.String, "玩家", Mini.Number, "广播消息ID", Mini.String } },
  Info = { returnType = Mini.String, displayName = "运行状态", params = { "变量ID", Mini.String, "玩家", Mini.Number, "广播消息ID", Mini.String } },
  Flush = { returnType = Mini.String, displayName = "刷写队列", params = { "变量ID", Mini.String, "玩家", Mini.Number, "最多条数", Mini.Number, "广播消息ID", Mini.String } },
  Hash = { returnType = Mini.String, displayName = "取指纹(MD5+SimHash)", params = { "变量ID", Mini.String, "玩家", Mini.Number, "路径", Mini.String, "广播消息ID", Mini.String } },
  Same = { returnType = Mini.String, displayName = "判断内容是否相同", params = { "变量ID", Mini.String, "玩家", Mini.Number, "路径A", Mini.String, "路径B", Mini.String, "广播消息ID", Mini.String } },
  Sim = { returnType = Mini.String, displayName = "计算相似度", params = { "变量ID", Mini.String, "玩家", Mini.Number, "路径A", Mini.String, "路径B", Mini.String, "广播消息ID", Mini.String } },
  SimFind = { returnType = Mini.String, displayName = "相似文件/目录检索", params = { "变量ID", Mini.String, "玩家", Mini.Number, "路径", Mini.String, "汉明阈值", Mini.Number, "上限", Mini.Number, "广播消息ID", Mini.String } },
  Dedup = { returnType = Mini.String, displayName = "重复文件扫描", params = { "变量ID", Mini.String, "玩家", Mini.Number, "起始路径", Mini.String, "上限", Mini.Number, "广播消息ID", Mini.String } },
  Reindex = { returnType = Mini.String, displayName = "重建相似索引", params = { "变量ID", Mini.String, "玩家", Mini.Number, "广播消息ID", Mini.String } },
  SetScope = { returnType = Mini.String, displayName = "设置作用域", params = { "变量ID", Mini.String, "玩家", Mini.Number, "room/personal", Mini.String, "广播消息ID", Mini.String } },
  SetCache = { returnType = Mini.String, displayName = "读缓存开关", params = { "变量ID", Mini.String, "玩家", Mini.Number, "开关", Mini.Number, "广播消息ID", Mini.String } },
  SetActor = { returnType = Mini.String, displayName = "设置操作者", params = { "变量ID", Mini.String, "玩家", Mini.Number, "操作者", Mini.Number, "广播消息ID", Mini.String } },
  Check = { returnType = Mini.String, displayName = "★自检(导入后先跑)", params = { "变量ID", Mini.String, "玩家", Mini.Number, "广播消息ID", Mini.String } },
  Unlock = { returnType = Mini.String, displayName = "口令解锁", params = { "变量ID", Mini.String, "玩家", Mini.Number, "路径", Mini.String, "口令", Mini.String, "广播消息ID", Mini.String } },
}

-- ============================================================
-- 适配层公共部分
-- ============================================================
local function jok(t) return json.encode(t) end
local function toNum(v, d) v = tonumber(v) if v == nil then return d end return v end
local function toStr(v, d) if v == nil then return d end return tostring(v) end
local function tostr(v) if v == nil then return "nil" end return tostring(v) end
local NIL = setmetatable({}, { __index = function() return NIL end })  -- 缓存 nil 哨兵

local POOL = {}          -- varId|pid -> fs 实例
local function keyOf(vid, pid) return tostring(vid) .. "|" .. tostring(pid) end

-- ★v2.1 作用域归一：0 / "" / nil 一律视为【房间级】= nil
--   旧版 FSGET(vid,0) 与 FSGET(vid,nil) 会建出【两份实例、两套缓存】，
--   同一个空间两份副本互不可见 —— 这也是 Hash/SimFind 找不到东西的根因之一
local function PIDOF(v)
  if v == nil then return nil end
  local str = tostring(v)
  if str == "" or str == "0" then return nil end
  if tonumber(v) == 0 then return nil end
  return v
end

-- ★v2.1 SetScope 真正生效：记录「玩家留空」时该变量默认用谁
local SCOPE_DEF = {}
local function DEFPLAYER(varId, playerId)
  if playerId == nil or tostring(playerId) == "" or tonumber(playerId) == 0 then
    local d = SCOPE_DEF[tostring(varId)]
    if d then return d end
  end
  return playerId
end

-- ============================================================
-- 【房间 / 个人适配层】直接读写，无限流，同步返回
--   playerId = nil  -> 房间级（全局）
--   playerId = uin  -> 该玩家的个人空间（同表按 playerId 隔离）
-- ============================================================
local LC = {}
LC.state = {}
local function lst(vid, pid)
  local kk = keyOf(vid, pid)
  local s = LC.state[kk]
  if not s then s = { cache = {}, ct = {}, nread = 0, nwrite = 0 } LC.state[kk] = s end
  return s
end
local LOCAL_CACHE = true
local CACHE_MS = 1500        -- ★v2.1 KV 层缓存有效期(毫秒)，由属性 cacheMs 决定；0=不缓存
-- 统一 KV 适配器：优先 Data.Map 阻塞接口，缺失时回退 Trigger.KvMap
-- （实测：Data.Map.GetMapValue/SetMapValue/RemoveMapValue 在当前运行时并不存在，
--   正确写法是 GetValueAndBlock(varId, playerId, key) / SetValueAndBlock(...)
--   / RemoveValueAndBlock(...)，返回 code[,key,value]，code==0 为成功）
local KVAPI = nil
local function kvApi()
  if KVAPI then return KVAPI end
  local dm = (type(Data) == "table") and Data.Map or nil
  if type(dm) == "table" and type(dm.GetValueAndBlock) == "function" then
    KVAPI = {
      name = "Data.Map.Block",
      get = function(v, p, k)
        local code, _, val = dm.GetValueAndBlock(dm, v, p, k)
        if code ~= nil and code ~= 0 then return nil end
        return val
      end,
      set = function(v, p, k, val)
        local code = dm.SetValueAndBlock(dm, v, p, k, val)
        return (code == nil) or (code == 0)
      end,
      del = function(v, p, k)
        if type(dm.RemoveValueAndBlock) ~= "function" then
          return dm.SetValueAndBlock(dm, v, p, k, "") ~= false
        end
        local code = dm.RemoveValueAndBlock(dm, v, p, k)
        return (code == nil) or (code == 0)
      end,
    }
  elseif type(Trigger) == "table" and type(Trigger.KvMap) == "table"
      and type(Trigger.KvMap.SetDataListBykey) == "function" then
    local KM = Trigger.KvMap
    KVAPI = {
      name = "Trigger.KvMap",
      get = function(v, p, k)
        local ok, r = pcall(KM.GetDataListBykey, KM, v, p, k, 0)
        if not ok then return nil end
        return r
      end,
      set = function(v, p, k, val)
        local ok, r = pcall(KM.SetDataListBykey, KM, v, p, k, val)
        return (not ok) or (r ~= false)
      end,
      del = function(v, p, k)
        local ok = pcall(KM.RemoveDataListBykey, KM, v, p, k)
        return ok
      end,
    }
  else
    KVAPI = { name = "NONE",
      get = function() return nil end,
      set = function() return false end,
      del = function() return false end }
  end
  return KVAPI
end

local function localKV(vid, pid)
  local A = kvApi()
  return {
    get = function(v, p, k)
      local s = lst(v, p)
      s.nread = s.nread + 1
      if LOCAL_CACHE and CACHE_MS > 0 then
        local c = s.cache[k]
        -- ★v2.1 TTL：超期就作废重读，别人的改动最多晚 CACHE_MS 毫秒被看到
        if c ~= nil and (NOWMS() - (s.ct[k] or 0)) < CACHE_MS then
          return (c == NIL) and nil or c
        end
      end
      local val = A.get(v, p, k)
      if LOCAL_CACHE and CACHE_MS > 0 then
        s.cache[k] = (val == nil or val == "") and NIL or val
        s.ct[k] = NOWMS()
      end
      return val
    end,
    set = function(v, p, k, val)
      local s = lst(v, p)
      s.nwrite = s.nwrite + 1
      if LOCAL_CACHE and CACHE_MS > 0 then
        s.cache[k] = (val == nil) and NIL or val
        s.ct[k] = NOWMS()
      end
      return A.set(v, p, k, val)
    end,
    del = function(v, p, k)
      local s = lst(v, p)
      s.nwrite = s.nwrite + 1
      if LOCAL_CACHE and CACHE_MS > 0 then s.cache[k] = NIL s.ct[k] = NOWMS() end
      return A.del(v, p, k)
    end,
    -- ★v2.1 整片丢弃（resolve 未命中时用）
    dropc = function(v, p, k)
      local s = lst(v, p)
      s.cache = {} s.ct = {}
    end,
    -- ★v2.1 绕过缓存直读，并把读到的最新值回填进缓存
    fresh = function(v, p, k)
      local s = lst(v, p)
      s.nread = s.nread + 1
      local val = A.get(v, p, k)
      if LOCAL_CACHE and CACHE_MS > 0 then
        s.cache[k] = (val == nil or val == "") and NIL or val
        s.ct[k] = NOWMS()
      end
      return val
    end,
  }
end

local function FSGET(vid, pid)
  pid = PIDOF(pid)                 -- ★v2.1 归一
  local kk = keyOf(vid, pid)
  local f = POOL[kk]
  if not f then
    f = M.new(localKV(vid, pid), vid, pid,
      { index = (INDEX_ON == 1), safe = (SAFE_ON == 1), cacheMs = CACHE_MS })
    f:init()
    POOL[kk] = f
    local st = lst(vid, pid) st.fs = f
  end
  if FP then FP.sample = (HASH_MODE == 1) end   -- ★v2.1 采样指纹开关
  return f
end

-- ★v2.1：不再写死 nil，按调用方传入的玩家取实例
local function N(vid, pid, p, who)
  local f = FSGET(vid, pid)
  local n
  if type(p) == "table" and p.id then n = p
  else n = f:resolve(tostring(p or "/"), f:root().id) end
  return f, n
end
local function need(n, what)
  if not n then return jok({ code = -404, msg = (what or "路径") .. "不存在" }) end
  return nil
end
-- 广播：填了「广播消息ID」就把结果推到该事件（实时/延迟返回通道）
-- 不填或填 0/空串 -> 走函数返回值（确定性返回）
local function EMIT(self_, evtId, payload)
  if evtId == nil then return false end
  local s = tostring(evtId)
  if s == "" or s == "0" then return false end
  local txt = (type(payload) == "string") and payload or tostring(payload)
  pcall(function()
    if self_ and self_.PushCustomEvent then self_:PushCustomEvent(s, txt) end
  end)
  return true
end

local function okN(f, n, extra)
  local s = f:stat(n.id)
  s.code = 0
  if extra then for k, v in pairs(extra) do s[k] = v end end
  return jok(s)
end

-- ====================================================================
-- 开放函数实现
-- ====================================================================
function Script:_I_Init(varId, playerId)
  local f = FSGET(varId, DEFPLAYER(varId, playerId))
  return jok({ code = 0, root = f:root().id, msg = "初始化完成" })
end
function Script:Init(varId, playerId, evtId)
  local _r = self:_I_Init(varId, playerId)
  if evtId ~= nil and tostring(evtId) ~= "" and tostring(evtId) ~= "0" then
    EMIT(self, evtId, _r)
    return jok({ code = 0, async = 1, evt = tostring(evtId), msg = "完整结果已广播" })
  end
  return _r
end

function Script:_I_Mkdir(varId, playerId, path)
  local f = FSGET(varId, DEFPLAYER(varId, playerId))
  local n, e = f:mkdir(path, playerId)
  if not n then return jok({ code = -1, msg = tostring(e) }) end
  return okN(f, n)
end
function Script:Mkdir(varId, playerId, path, evtId)
  local _r = self:_I_Mkdir(varId, playerId, path)
  if evtId ~= nil and tostring(evtId) ~= "" and tostring(evtId) ~= "0" then
    EMIT(self, evtId, _r)
    return jok({ code = 0, async = 1, evt = tostring(evtId), msg = "完整结果已广播" })
  end
  return _r
end

function Script:_I_MkFile(varId, playerId, path, content)
  local f = FSGET(varId, DEFPLAYER(varId, playerId))
  local n, e = f:mkfile(path, toStr(content, ""), playerId)
  if not n then return jok({ code = -1, msg = tostr(e) }) end
  return okN(f, n)
end
function Script:MkFile(varId, playerId, path, content, evtId)
  local _r = self:_I_MkFile(varId, playerId, path, content)
  if evtId ~= nil and tostring(evtId) ~= "" and tostring(evtId) ~= "0" then
    EMIT(self, evtId, _r)
    return jok({ code = 0, async = 1, evt = tostring(evtId), msg = "完整结果已广播" })
  end
  return _r
end

function Script:_I_Read(varId, playerId, path)
  local f = FSGET(varId, DEFPLAYER(varId, playerId))
  local n = f:resolve(tostring(path or "/"), f:root().id)
  if not n then return jok({ code = -404, msg = "路径不存在" }) end
  local d, e = f:read(n.id, playerId)
  if d == nil then return jok({ code = -2, msg = tostr(e) }) end
  return d
end
function Script:Read(varId, playerId, path, evtId)
  local _r = self:_I_Read(varId, playerId, path)
  EMIT(self, evtId, _r)
  return _r
end

function Script:_I_Write(varId, playerId, path, content)
  local f = FSGET(varId, DEFPLAYER(varId, playerId))
  local n = f:resolve(tostring(path or "/"), f:root().id)
  if not n then return jok({ code = -404, msg = "路径不存在" }) end
  local ok, e = f:write(n.id, toStr(content, ""), playerId)
  if not ok then return jok({ code = -3, msg = tostr(e) }) end
  return okN(f, n)
end
function Script:Write(varId, playerId, path, content, evtId)
  local _r = self:_I_Write(varId, playerId, path, content)
  if evtId ~= nil and tostring(evtId) ~= "" and tostring(evtId) ~= "0" then
    EMIT(self, evtId, _r)
    return jok({ code = 0, async = 1, evt = tostring(evtId), msg = "完整结果已广播" })
  end
  return _r
end

function Script:_I_List(varId, playerId, path, offset, limit)
  local f = FSGET(varId, DEFPLAYER(varId, playerId))
  local n = f:resolve(tostring(path or "/"), f:root().id)
  if not n then return jok({ code = -404, msg = "路径不存在" }) end
  local items, total = f:list(n.id, playerId, toNum(offset, 0), toNum(limit, 200))
  if not items then return jok({ code = -3, msg = tostr(total) }) end
  return jok({ code = 0, total = total, count = #items, items = items })
end
function Script:List(varId, playerId, path, offset, limit, evtId)
  local _r = self:_I_List(varId, playerId, path, offset, limit)
  EMIT(self, evtId, _r)
  return _r
end

function Script:_I_Stat(varId, playerId, path)
  local f = FSGET(varId, DEFPLAYER(varId, playerId))
  local n = f:resolve(tostring(path or "/"), f:root().id)
  if not n then return jok({ code = -404, msg = "路径不存在" }) end
  return okN(f, n)
end
function Script:Stat(varId, playerId, path, evtId)
  local _r = self:_I_Stat(varId, playerId, path)
  EMIT(self, evtId, _r)
  return _r
end

function Script:_I_Remove(varId, playerId, path)
  local f = FSGET(varId, DEFPLAYER(varId, playerId))
  local n = f:resolve(tostring(path or "/"), f:root().id)
  if not n then return jok({ code = -404, msg = "路径不存在" }) end
  local ok, e = f:remove(n.id, playerId)
  if not ok then return jok({ code = -4, msg = tostr(e) }) end
  return jok({ code = 0, msg = "已删除" })
end
function Script:Remove(varId, playerId, path, evtId)
  local _r = self:_I_Remove(varId, playerId, path)
  if evtId ~= nil and tostring(evtId) ~= "" and tostring(evtId) ~= "0" then
    EMIT(self, evtId, _r)
    return jok({ code = 0, async = 1, evt = tostring(evtId), msg = "完整结果已广播" })
  end
  return _r
end

function Script:_I_Rename(varId, playerId, path, newName)
  local f = FSGET(varId, DEFPLAYER(varId, playerId))
  local n = f:resolve(tostring(path or "/"), f:root().id)
  if not n then return jok({ code = -404, msg = "路径不存在" }) end
  local ok, e = f:rename(n.id, toStr(newName, n.name), playerId)
  if not ok then return jok({ code = -5, msg = tostr(e) }) end
  return okN(f, n)
end
function Script:Rename(varId, playerId, path, newName, evtId)
  local _r = self:_I_Rename(varId, playerId, path, newName)
  if evtId ~= nil and tostring(evtId) ~= "" and tostring(evtId) ~= "0" then
    EMIT(self, evtId, _r)
    return jok({ code = 0, async = 1, evt = tostring(evtId), msg = "完整结果已广播" })
  end
  return _r
end

function Script:_I_Move(varId, playerId, path, newParentPath)
  local f = FSGET(varId, DEFPLAYER(varId, playerId))
  local n = f:resolve(tostring(path or "/"), f:root().id)
  local p = f:resolve(tostring(newParentPath or "/"), f:root().id)
  if not n or not p then return jok({ code = -404, msg = "路径不存在" }) end
  local ok, e = f:move(n.id, p.id, playerId)
  if not ok then return jok({ code = -6, msg = tostr(e) }) end
  return okN(f, n)
end
function Script:Move(varId, playerId, path, newParentPath, evtId)
  local _r = self:_I_Move(varId, playerId, path, newParentPath)
  if evtId ~= nil and tostring(evtId) ~= "" and tostring(evtId) ~= "0" then
    EMIT(self, evtId, _r)
    return jok({ code = 0, async = 1, evt = tostring(evtId), msg = "完整结果已广播" })
  end
  return _r
end

function Script:_I_Copy(varId, playerId, path, newParentPath, newName)
  local f = FSGET(varId, DEFPLAYER(varId, playerId))
  local n = f:resolve(tostring(path or "/"), f:root().id)
  local p = f:resolve(tostring(newParentPath or "/"), f:root().id)
  if not n or not p then return jok({ code = -404, msg = "路径不存在" }) end
  local ok, e = f:copy(n.id, p.id, newName, playerId)
  if not ok then return jok({ code = -7, msg = tostr(e) }) end
  return jok({ code = 0, id = e, msg = "已复制" })
end
function Script:Copy(varId, playerId, path, newParentPath, newName, evtId)
  local _r = self:_I_Copy(varId, playerId, path, newParentPath, newName)
  if evtId ~= nil and tostring(evtId) ~= "" and tostring(evtId) ~= "0" then
    EMIT(self, evtId, _r)
    return jok({ code = 0, async = 1, evt = tostring(evtId), msg = "完整结果已广播" })
  end
  return _r
end

function Script:_I_Find(varId, playerId, pattern, startPath, limit)
  local f = FSGET(varId, DEFPLAYER(varId, playerId))
  local sp = nil
  if startPath and startPath ~= "" then local s = f:resolve(tostring(startPath), f:root().id) sp = s and s.id end
  local r = f:find(tostring(pattern or "**"), sp, playerId, toNum(limit, 200))
  local out = {}
  for i, e in ipairs(r) do out[i] = { path = e.path, id = e.id, typ = e.node and e.node.typ, size = e.node and e.node.size } end
  return jok({ code = 0, count = #out, items = out })
end
function Script:Find(varId, playerId, pattern, startPath, limit, evtId)
  local _r = self:_I_Find(varId, playerId, pattern, startPath, limit)
  EMIT(self, evtId, _r)
  return _r
end

function Script:_I_Grep(varId, playerId, pattern, startPath, limit)
  local f = FSGET(varId, DEFPLAYER(varId, playerId))
  local sp = nil
  if startPath and startPath ~= "" then local s = f:resolve(tostring(startPath), f:root().id) sp = s and s.id end
  local r = f:grep(tostring(pattern or ""), sp, playerId, toNum(limit, 20))
  return jok({ code = 0, count = #r, items = r })
end
function Script:Grep(varId, playerId, pattern, startPath, limit, evtId)
  local _r = self:_I_Grep(varId, playerId, pattern, startPath, limit)
  EMIT(self, evtId, _r)
  return _r
end

function Script:_I_Pack(varId, playerId, path, compress)
  local f = FSGET(varId, DEFPLAYER(varId, playerId))
  local n = f:resolve(tostring(path or "/"), f:root().id)
  if not n then return jok({ code = -404, msg = "路径不存在" }) end
  local pk, raw, packed = f:pack(n.id, { comp = (compress ~= 0), name = n.name })
  if not pk then return jok({ code = -8, msg = "打包失败" }) end
  return pk
end
function Script:Pack(varId, playerId, path, compress, evtId)
  local _r = self:_I_Pack(varId, playerId, path, compress)
  if evtId ~= nil and tostring(evtId) ~= "" and tostring(evtId) ~= "0" then
    EMIT(self, evtId, _r)
    return jok({ code = 0, async = 1, evt = tostring(evtId), msg = "完整结果已广播" })
  end
  return _r
end

function Script:_I_Unpack(varId, playerId, pkg, destPath, overwrite)
  local f = FSGET(varId, DEFPLAYER(varId, playerId))
  local p = f:resolve(tostring(destPath or "/"), f:root().id)
  if not p then return jok({ code = -404, msg = "目标路径不存在" }) end
  local c, fl = f:unpack(tostring(pkg or ""), p.id, { overwrite = (overwrite == 1) })
  return jok({ code = 0, created = c or 0, failed = fl or 0 })
end
function Script:Unpack(varId, playerId, pkg, destPath, overwrite, evtId)
  local _r = self:_I_Unpack(varId, playerId, pkg, destPath, overwrite)
  if evtId ~= nil and tostring(evtId) ~= "" and tostring(evtId) ~= "0" then
    EMIT(self, evtId, _r)
    return jok({ code = 0, async = 1, evt = tostring(evtId), msg = "完整结果已广播" })
  end
  return _r
end

function Script:_I_Upload(srcVarId, srcPlayerId, srcPath, dstVarId, dstPlayerId, dstPath)
  local a = FSGET(srcVarId, DEFPLAYER(srcVarId, srcPlayerId))
  local b = FSGET(dstVarId, DEFPLAYER(dstVarId, dstPlayerId))
  local n = a:resolve(tostring(srcPath or "/"), a:root().id)
  if not n then return jok({ code = -404, msg = "源路径不存在" }) end
  local p = b:resolve(tostring(dstPath or "/"), b:root().id)
  if not p then return jok({ code = -404, msg = "目标路径不存在" }) end
  local r = a:export(n.id, b, p.id, {})
  return jok({ code = 0, created = r or 0, msg = "跨表迁移完成" })
end
function Script:Upload(srcVarId, srcPlayerId, srcPath, dstVarId, dstPlayerId, dstPath, evtId)
  local _r = self:_I_Upload(srcVarId, srcPlayerId, srcPath, dstVarId, dstPlayerId, dstPath)
  if evtId ~= nil and tostring(evtId) ~= "" and tostring(evtId) ~= "0" then
    EMIT(self, evtId, _r)
    return jok({ code = 0, async = 1, evt = tostring(evtId), msg = "完整结果已广播" })
  end
  return _r
end

function Script:_I_Chmod(varId, playerId, path, mode)
  local f = FSGET(varId, DEFPLAYER(varId, playerId))
  local n = f:resolve(tostring(path or "/"), f:root().id)
  if not n then return jok({ code = -404, msg = "路径不存在" }) end
  local ok, e = f:chmod(n.id, toNum(mode, 420), playerId)
  if not ok then return jok({ code = -9, msg = tostr(e) }) end
  return okN(f, n)
end
function Script:Chmod(varId, playerId, path, mode, evtId)
  local _r = self:_I_Chmod(varId, playerId, path, mode)
  if evtId ~= nil and tostring(evtId) ~= "" and tostring(evtId) ~= "0" then
    EMIT(self, evtId, _r)
    return jok({ code = 0, async = 1, evt = tostring(evtId), msg = "完整结果已广播" })
  end
  return _r
end

function Script:_I_Chown(varId, playerId, path, owner)
  local f = FSGET(varId, DEFPLAYER(varId, playerId))
  local n = f:resolve(tostring(path or "/"), f:root().id)
  if not n then return jok({ code = -404, msg = "路径不存在" }) end
  local ok, e = f:chown(n.id, toNum(owner, 0), playerId)
  if not ok then return jok({ code = -10, msg = tostr(e) }) end
  return okN(f, n)
end
function Script:Chown(varId, playerId, path, owner, evtId)
  local _r = self:_I_Chown(varId, playerId, path, owner)
  if evtId ~= nil and tostring(evtId) ~= "" and tostring(evtId) ~= "0" then
    EMIT(self, evtId, _r)
    return jok({ code = 0, async = 1, evt = tostring(evtId), msg = "完整结果已广播" })
  end
  return _r
end

function Script:_I_SetKey(varId, playerId, path, pass)
  local f = FSGET(varId, DEFPLAYER(varId, playerId))
  local n = f:resolve(tostring(path or "/"), f:root().id)
  if not n then return jok({ code = -404, msg = "路径不存在" }) end
  local ok, e = f:setKey(n.id, toStr(pass, ""), playerId)
  if not ok then return jok({ code = -11, msg = tostr(e) }) end
  return jok({ code = 0, enc = "sym", msg = "已启用对称加密(加密后MAC)" })
end
function Script:SetKey(varId, playerId, path, pass, evtId)
  local _r = self:_I_SetKey(varId, playerId, path, pass)
  if evtId ~= nil and tostring(evtId) ~= "" and tostring(evtId) ~= "0" then
    EMIT(self, evtId, _r)
    return jok({ code = 0, async = 1, evt = tostring(evtId), msg = "完整结果已广播" })
  end
  return _r
end

function Script:_I_WrapKey(varId, playerId, path, pubE, pubN, keyId)
  local f = FSGET(varId, DEFPLAYER(varId, playerId))
  local n = f:resolve(tostring(path or "/"), f:root().id)
  if not n then return jok({ code = -404, msg = "路径不存在" }) end
  local ok, e = f:wrapKey(n.id, toStr(pubE, "10001"), toStr(pubN, ""), toStr(keyId, "default"), playerId)
  if not ok then return jok({ code = -12, msg = tostr(e) }) end
  return jok({ code = 0, enc = "hybrid", msg = "DEK 已用 RSA 公钥封装" })
end
function Script:WrapKey(varId, playerId, path, pubE, pubN, keyId, evtId)
  local _r = self:_I_WrapKey(varId, playerId, path, pubE, pubN, keyId)
  if evtId ~= nil and tostring(evtId) ~= "" and tostring(evtId) ~= "0" then
    EMIT(self, evtId, _r)
    return jok({ code = 0, async = 1, evt = tostring(evtId), msg = "完整结果已广播" })
  end
  return _r
end

function Script:_I_Usage(varId, playerId, owner)
  local f = FSGET(varId, DEFPLAYER(varId, playerId))
  local tot, nf = f:usage(owner)
  return jok({ code = 0, bytes = tot, files = nf })
end
function Script:Usage(varId, playerId, owner, evtId)
  local _r = self:_I_Usage(varId, playerId, owner)
  EMIT(self, evtId, _r)
  return _r
end

function Script:_I_Unlock(varId, playerId, path, pass)
  local f = FSGET(varId, DEFPLAYER(varId, playerId))
  local n = f:resolve(tostring(path or "/"), f:root().id)
  if not n then return jok({ code = -404, msg = "路径不存在" }) end
  local ok, e = f:unlock(n.id, toStr(pass, ""), playerId)
  if not ok then return jok({ code = -13, msg = tostr(e) }) end
  return jok({ code = 0, msg = "已解锁" })
end
function Script:Unlock(varId, playerId, path, pass, evtId)
  local _r = self:_I_Unlock(varId, playerId, path, pass)
  if evtId ~= nil and tostring(evtId) ~= "" and tostring(evtId) ~= "0" then
    EMIT(self, evtId, _r)
    return jok({ code = 0, async = 1, evt = tostring(evtId), msg = "完整结果已广播" })
  end
  return _r
end

function Script:_I_SetActor(varId, playerId, who)
  local f = FSGET(varId, DEFPLAYER(varId, playerId))
  f.actor = toNum(who, 0)
  return jok({ code = 0, actor = f.actor, msg = "操作者已设定(0=root)" })
end
function Script:SetActor(varId, playerId, who, evtId)
  local _r = self:_I_SetActor(varId, playerId, who)
  if evtId ~= nil and tostring(evtId) ~= "" and tostring(evtId) ~= "0" then
    EMIT(self, evtId, _r)
    return jok({ code = 0, async = 1, evt = tostring(evtId), msg = "完整结果已广播" })
  end
  return _r
end

function Script:_I_DropCache(varId, playerId)
  local pid = PIDOF(playerId)
  local kk = keyOf(varId, pid)
  local f = POOL[kk]
  if f then f:drop() end
  POOL[kk] = nil
  local s = LC.state[kk]
  -- ★v2.1 两级缓存都要清，旧版只清了 KV 层，节点层仍可能返回旧对象
  if s then s.cache = {} s.ct = {} end
  return jok({ code = 0, msg = "缓存已释放(节点层+KV层)" })
end
function Script:DropCache(varId, playerId, evtId)
  local _r = self:_I_DropCache(varId, playerId)
  if evtId ~= nil and tostring(evtId) ~= "" and tostring(evtId) ~= "0" then
    EMIT(self, evtId, _r)
    return jok({ code = 0, async = 1, evt = tostring(evtId), msg = "完整结果已广播" })
  end
  return _r
end

function Script:_I_Info(varId, playerId)
  local pid = PIDOF(playerId)
  local s = LC.state[keyOf(varId, pid)]
  local f = POOL[keyOf(varId, pid)]
  local st = kvApi()
  return jok({ code = 0, read = s and s.nread or 0, write = s and s.nwrite or 0,
    root = f and f:root().id, kv = st and st.name or "?",
    cacheMs = CACHE_MS, hashMode = HASH_MODE,
    scope = SCOPE_DEF[tostring(varId)] or 0 })
end
function Script:Info(varId, playerId, evtId)
  local _r = self:_I_Info(varId, playerId)
  EMIT(self, evtId, _r)
  return _r
end

function Script:_I_Hash(varId, playerId, path)
  local f, n = N(varId, playerId, path)
  local e = need(n, "路径") if e then return e end
  local s = f:stat(n.id)
  s.code = 0
  return jok(s)
end
function Script:Hash(varId, playerId, path, evtId)
  local _r = self:_I_Hash(varId, playerId, path)
  EMIT(self, evtId, _r)
  return _r
end

function Script:_I_Same(varId, playerId, pathA, pathB)
  local f = FSGET(varId, DEFPLAYER(varId, playerId))
  local a = f:resolve(tostring(pathA or "/"), f:root().id)
  local b = f:resolve(tostring(pathB or "/"), f:root().id)
  if not a or not b then return jok({ code = -404, msg = "路径不存在" }) end
  local r, er = f:same(a.id, b.id)
  if r == nil then return jok({ code = -1, msg = tostr(er) }) end
  return jok({ code = 0, same = r, md5A = a.md5, md5B = b.md5,
    pathA = pathA, pathB = pathB, msg = (r == 1) and "内容完全相同" or "内容不同" })
end
function Script:Same(varId, playerId, pathA, pathB, evtId)
  local _r = self:_I_Same(varId, playerId, pathA, pathB)
  EMIT(self, evtId, _r)
  return _r
end

function Script:_I_Sim(varId, playerId, pathA, pathB)
  local f = FSGET(varId, DEFPLAYER(varId, playerId))
  local a = f:resolve(tostring(pathA or "/"), f:root().id)
  local b = f:resolve(tostring(pathB or "/"), f:root().id)
  if not a or not b then return jok({ code = -404, msg = "路径不存在" }) end
  local sm = f:sim(a.id, b.id)
  return jok({ code = 0, sim = sm, dist = FP.SIM.hamming(a.sim or 0, b.sim or 0),
    simA = FP.SIM.hex(a.sim or 0), simB = FP.SIM.hex(b.sim or 0),
    same = (a.md5 and b.md5 and a.md5 == b.md5) and 1 or 0 })
end
function Script:Sim(varId, playerId, pathA, pathB, evtId)
  local _r = self:_I_Sim(varId, playerId, pathA, pathB)
  EMIT(self, evtId, _r)
  return _r
end

function Script:_I_SimFind(varId, playerId, path, thr, limit)
  local f, n = N(varId, playerId, path)
  local e = need(n, "路径") if e then return e end
  local r = f:simFind(n.id, toNum(thr, 3), toNum(limit, 50), playerId)
  return jok({ code = 0, count = #r, thr = toNum(thr, 3), items = r })
end
function Script:SimFind(varId, playerId, path, thr, limit, evtId)
  local _r = self:_I_SimFind(varId, playerId, path, thr, limit)
  EMIT(self, evtId, _r)
  return _r
end

function Script:_I_Dedup(varId, playerId, path, limit)
  local f = FSGET(varId, DEFPLAYER(varId, playerId))
  local sp = nil
  if path and path ~= "" then local s2 = f:resolve(tostring(path), f:root().id) sp = s2 and s2.id end
  local g, waste, total = f:dedupScan(sp, toNum(limit, 20000))
  local out = {}
  for i, x in ipairs(g) do out[i] = { md5 = x.md5, size = x.size, n = #x.items, items = x.items } end
  return jok({ code = 0, groups = #out, scanned = total, wasteBytes = waste, items = out })
end
function Script:Dedup(varId, playerId, path, limit, evtId)
  local _r = self:_I_Dedup(varId, playerId, path, limit)
  EMIT(self, evtId, _r)
  return _r
end

function Script:_I_Reindex(varId, playerId)
  local f = FSGET(varId, DEFPLAYER(varId, playerId))
  local n = f:reindex()
  return jok({ code = 0, indexed = n, msg = "分桶索引已重建" })
end
function Script:Reindex(varId, playerId, evtId)
  local _r = self:_I_Reindex(varId, playerId)
  if evtId ~= nil and tostring(evtId) ~= "" and tostring(evtId) ~= "0" then
    EMIT(self, evtId, _r)
    return jok({ code = 0, async = 1, evt = tostring(evtId), msg = "完整结果已广播" })
  end
  return _r
end


-- ---- 房间/个人专有 ----
function Script:_I_SetScope(varId, playerId, scope)
  -- ★v2.1 真正实现（旧版赋值后无人读取，等于空操作）
  --   room          -> 「玩家」留空时用房间级
  --   personal:<uin>-> 「玩家」留空时用该 uin 的个人空间
  local sc = tostr(scope or "room")
  local kk = tostring(varId)
  if sc == "room" then
    SCOPE_DEF[kk] = nil
    return jok({ code = 0, scope = "room", msg = "默认作用域=房间级(玩家留空时)" })
  end
  if sc == "personal" then
    SCOPE_DEF[kk] = nil
    return jok({ code = -1, msg = "请填 personal:<uin>，例如 personal:1001" })
  end
  local uin = tonumber(sc:match("^personal:(.+)$") or "")
  if not uin or uin == 0 then
    return jok({ code = -1, msg = "未知作用域:" .. sc .. " (只认 room / personal:<uin>)" })
  end
  SCOPE_DEF[kk] = uin
  return jok({ code = 0, scope = "personal", uin = uin,
    msg = "默认玩家=" .. tostring(uin) .. "(玩家留空时生效)" })
end
function Script:SetScope(varId, playerId, scope, evtId)
  local _r = self:_I_SetScope(varId, playerId, scope)
  if evtId ~= nil and tostring(evtId) ~= "" and tostring(evtId) ~= "0" then
    EMIT(self, evtId, _r)
    return jok({ code = 0, async = 1, evt = tostring(evtId), msg = "完整结果已广播" })
  end
  return _r
end
function Script:Flush(varId, playerId, maxOps)
  local f = POOL[keyOf(varId, playerId)]
  if not f then return jok({ code = 0, flushed = 0 }) end
  local n = f:flush()
  return jok({ code = 0, flushed = n })
end
function Script:SetCache(varId, playerId, on)
  LOCAL_CACHE = (toNum(on, 1) == 1)
  if not LOCAL_CACHE then local s = LC.state[keyOf(varId, playerId)] if s then s.cache = {} end end
  return jok({ code = 0, cache = LOCAL_CACHE })
end

function Script:OnStart()
  if type(bit) ~= "table" then print("[KVFS] 缺少 bit 模块") return end
  if type(json) ~= "table" then print("[KVFS] 缺少 json 模块") return end
  if self.shardSize then M.CFG.SHARD = math.floor(self.shardSize) end
  if self.indexOn ~= nil then INDEX_ON = self.indexOn end
  if self.safeMode ~= nil then SAFE_ON = self.safeMode end
  if self.useCache ~= nil then LOCAL_CACHE = (self.useCache == 1) end
  -- ★v2.1
  if self.cacheMs ~= nil then
    CACHE_MS = math.floor(tonumber(self.cacheMs) or 1500)
    if CACHE_MS < 0 then CACHE_MS = 0 end
  end
  if self.hashMode ~= nil then HASH_MODE = (tonumber(self.hashMode) == 1) and 1 or 0 end
  print("[KVFS v2.1] 就绪 cacheMs=" .. tostring(CACHE_MS) .. " hashMode=" .. tostring(HASH_MODE))
end

-- ★v2.1 自检：真机导入后先跑这个
function Script:_I_Check()
  local out, np, nf = {}, 0, 0
  local function t(name, cond, extra)
    if cond then np = np + 1 else nf = nf + 1 end
    out[#out+1] = (cond and "PASS " or "FAIL ") .. name .. (extra and (" | " .. tostring(extra)) or "")
  end
  t("bit 模块存在", type(bit) == "table")
  t("bit.ror 存在", type(bit) == "table" and type(bit.ror) == "function")
  t("json 模块存在", type(json) == "table")
  t("os.timeMs 存在", type(os) == "table" and type(os.timeMs) == "function")
  t("Data.Map 存在", type(Data) == "table" and type(Data.Map) == "table")
  local st = kvApi()
  t("KV 适配器可用", st.name ~= "NONE", st.name)
  t("Data.Map.GetValueAndBlock", type(Data) == "table" and Data.Map
    and type(Data.Map.GetValueAndBlock) == "function")
  -- 哈夫曼单叶节点（v2.0 会崩）
  local okc, e = pcall(function()
    local one = string.rep("A", 1000)
    local c = M.HF.comp(one)
    local d = M.HF.decomp(c)
    assert(d == one, "往返不一致 len=" .. tostring(#d))
  end)
  t("单字节内容哈夫曼往返", okc, e)
  -- 普通内容往返
  local ok2, e2 = pcall(function()
    local txt = ("abcdefghij" .. string.rep("中文测试", 30))
    local c = M.HF.comp(txt)
    assert(M.HF.decomp(c) == txt)
  end)
  t("普通内容哈夫曼往返", ok2, e2)
  -- 损坏数据不崩
  local ok3, e3 = pcall(function() M.HF.decomp(string.rep("", 40)) end)
  t("损坏数据不崩溃", ok3, e3)
  -- 端到端
  local ok4, e4 = pcall(function()
    local f = FSGET("__chk__", nil)
    f:mkdir("/t")
    local n = f:mkfile("/t/a.txt", "hello 你好")
    assert(n, "创建失败")
    local got = f:read(n.id, 0)
    assert(got == "hello 你好", "读取不一致: " .. tostring(got))
  end)
  t("端到端 建目录/写文件/读回", ok4, e4)
  -- 并发同名复查：第二次创建必须失败
  local ok5, e5 = pcall(function()
    local f = FSGET("__chk__", nil)
    local r = f:mkfile("/t/a.txt", "again")
    assert(r == nil, "同名未拦住")
  end)
  t("同名创建被拦住", ok5, e5)
  -- 作用域归一
  t("PIDOF 归一(0->nil)", PIDOF(0) == nil and PIDOF("0") == nil and PIDOF("") == nil)
  t("PIDOF 保留 uin", PIDOF(1001) == 1001)
  return jok({ code = 0, pass = np, fail = nf, items = out,
    msg = (nf == 0) and ("全部通过 " .. np .. "/" .. np) or (tostring(nf) .. " 项失败, 详见 items") })
end
function Script:Check(varId, playerId, evtId)
  local _r = self:_I_Check()
  if evtId ~= nil and tostring(evtId) ~= "" and tostring(evtId) ~= "0" then
    EMIT(self, evtId, _r)
    return jok({ code = 0, async = 1, evt = tostring(evtId), msg = "完整结果已广播" })
  end
  return _r
end
return Script
