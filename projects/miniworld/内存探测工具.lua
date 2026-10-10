--[[
================================================================
 Lua table 内存上限探测工具 v2.0
 用途：实测迷你世界 Lua 环境 table 能装多少内存
 主管（元宝）签发 · 2026-10-10
================================================================

 ⚠️⚠️ 安全警告（务必先读）⚠️⚠️

 本工具会真实分配内存，有闪退风险。
 引擎 C++ 层的 OOM 无法被 Lua 的 pcall 捕获，会直接闪退。

 第一次使用请务必：
   maxMB  = 50
   blockKB= 64
 确认能跑通后，再逐步提高上限。

----------------------------------------------------------------
 聊天输出（v2.0 新增）
----------------------------------------------------------------
 每一步都会往聊天框发系统消息，方便崩溃前观察进度。

 关键设计：【先发后分配】
   每批真正分配内存之前，先发出一条 "[将] P2 批12 ..."。
   万一本批直接闪退（引擎层 OOM，pcall 抓不到），
   聊天框里最后一条就是崩溃点，能定位到具体批号和当时内存。

 目标 ID 默认 0（广播给所有人）。改成某个玩家的 uin 可只发给他。

 官方签名：Chat.SendSystemMsg(self, content, playerID)
 引擎里大小写可能不一致，所以做了多候选自适应，
 第一次成功就记住。调 ChatInfo() 能看到实际命中的是哪个。

----------------------------------------------------------------
 六个阶段
----------------------------------------------------------------
 1  数字数组     单表塞 number，看元素上限
 2  字符串池     定长块存 table  ← 最贴近权重存储方案
 3  嵌套表       多字段 table 数组
 4  单串上限     单个 string 能创建多大
 5  哈希键       string key 的元素上限
 6  深度嵌套     嵌套深度 / 栈深度

----------------------------------------------------------------
 设计要点
----------------------------------------------------------------
 核心是 Step()：每次只分配一小批（默认约 1MB）就返回。
 反复调用逼近上限，崩之前的值已经被记录下来。
 不要在一个函数里一路分配到底 —— 那样崩了什么也拿不到。

 三重安全：
   ① 硬上限：实测内存超过 maxMB 立即停
   ② 单批看门狗：单次增长超 50MB 立刻中止
   ③ OOM 捕获：pcall 捕获 "not enough memory"

----------------------------------------------------------------
 开放函数
----------------------------------------------------------------
 Probe        极简连通性测试（含聊天自检），先跑这个
 Step         分配一批 ← 核心，反复调用
 Run          自动跑完（有步数上限，仍可能卡）
 Status       当前配置与安全提示（含聊天状态）
 Result(i)    取第 i 段报告
 ResultCount  报告段数
 ListPhases   阶段清单
 Free         立即释放全部内存
 ChatInfo     聊天通道自检：列出 Chat 下所有可用函数
 Say(文本)    手动发一条，验证通道
================================================================
]]

local Script = {}

-- =============================================================
-- 常量（顶层 local）
-- =============================================================
local DEFAULT_MAX_MB   = 200
local DEFAULT_STEP_KB  = 1024
local DEFAULT_BLOCK_KB = 64
local WD_LIMIT_MB      = 50      -- 单批看门狗
local REPORT_MAX       = 3500    -- 单段报告最大字符
local PROBE_MAX_MB     = 2       -- Probe 阶段上限
local CHAT_MAXLEN      = 180     -- 单条聊天最大字符（聊天框限制）

-- =============================================================
-- 运行时状态（顶层 local，在 OnStart 中初始化）
-- =============================================================
local SELFREF  = nil
local RAWSELF  = nil     -- 组件表原样快照（属性读取回退用）
local INITED   = false

local POOL     = nil     -- 当前阶段的主容器
local NPOOL    = 0       -- 元素个数
local PHASE    = 0       -- 当前阶段 0=未开始
local PDONE    = false   -- 当前阶段是否结束
local LASTERR  = ""
local REPORT   = nil
local NREPORT  = 0
local BIGSTR   = nil     -- 阶段4 单串
local DEEPT    = nil     -- 阶段6 深嵌套
local DEPTHN   = 0
local STARTMB  = 0
local PEAKMB   = 0
local CURMB    = 0
local HARDSTOP = false
local FINISHED = {}      -- 已完成阶段，防止重复收尾
local CALIBRATED = false -- 计数器是否已校准（首步自动做一次）

-- 聊天输出状态
local CHATFN   = nil     -- 命中的发送函数 {obj=, name=, argc=}
local CHATNAME = ""      -- 命中的函数名，Status/ChatInfo 可见
local CHATSENT = 0       -- 成功发送条数
local CHATFAIL = 0       -- 失败条数
local CHATLAST = ""      -- 最后一条发出的文本
local NSTEP    = 0       -- 当前阶段已跑批数（用于 throttle）

-- 阶段名
local PNAME = {
    [0] = "未开始",
    [1] = "数字数组",
    [2] = "字符串池",
    [3] = "嵌套表",
    [4] = "单串上限",
    [5] = "哈希键",
    [6] = "深度嵌套",
}

-- =============================================================
-- 工具函数
-- =============================================================

-- =============================================================
-- 聊天输出层
--
-- 官方签名（Wiki + API 反射导出）：
--   Chat.SendChat      = self, content, playerID
--   Chat.SendSystemMsg = self, content, playerID
--
-- 两个坑：
--  ① 是点号调用并显式带 self，不是冒号。
--     冒号 Chat:sendSystemMsg(x) 展开成 Chat.sendSystemMsg(Chat, x)，
--     函数名大小写必须与实际完全一致。
--  ② 引擎里到底是大写 SendSystemMsg 还是小写 sendSystemMsg，
--     版本之间不一致。所以做成多候选，第一次成功就记住，
--     后续直接用，不再逐个试。
--
-- 崩溃前观察的关键：
--   每条 "将分配" 都在真正分配内存【之前】发出。
--   万一崩了，聊天框里最后一条就是崩之前的进度。
-- =============================================================

-- 前向声明：sendChat 在 getNum / calcMB 真正定义之前就会调用它们。
-- 不在这里声明，函数体里取到的就是全局 nil，整个聊天输出全废。
local getNum    -- 读组件属性（定义在后面）
local calcMB    -- 内存计算（定义在后面）

-- 候选函数名（按优先级）
local CHAT_NAMES = {
    "SendSystemMsg", "sendSystemMsg",
    "SendChat",      "sendChat",
    "sendSystemMsgToPlayer", "SendSystemMsgToPlayer",
}

local function chatObj()
    -- 三种取法都试：_G 可能不是真全局表（沙箱隔离），
    -- 也可能 Chat 直接挂在环境链上
    local ok, C = pcall(rawget, _G, "Chat")
    if ok and type(C) == "table" then return C end
    if type(rawget(_G, "Chat")) == "table" then return rawget(_G, "Chat") end
    if type(Chat) == "table" then return Chat end
    return nil
end

-- 尝试一次调用：先带 pid，失败则不带
local function tryCall(obj, name, text, pid)
    local f = obj[name]
    -- 注意：不能只认 "function"。引擎里的 C 函数、以及部分
    -- 宿主注入的回调，type() 可能报 "userdata"，但照样能调。
    local tf = type(f)
    if tf ~= "function" and tf ~= "userdata" then return false, 0 end
    local ok = pcall(f, obj, text, pid)
    if ok then return true, 3 end
    local ok2 = pcall(f, obj, text)
    if ok2 then return true, 2 end
    return false, 0
end

-- 发送一条聊天消息。返回是否成功
local function sendChat(text)
    if type(text) ~= "string" then text = tostring(text) end
    if text == "" then return false end
    if #text > CHAT_MAXLEN then
        text = text:sub(1, CHAT_MAXLEN - 3) .. "..."
    end
    local pid = getNum("chatPlayerId", 0)

    -- 已命中过 → 直接用
    if CHATFN then
        local okc = pcall(CHATFN.fn, CHATFN.obj, text, pid)
        if okc then
            CHATSENT = CHATSENT + 1
            CHATLAST = text
            return true
        end
        -- 命中过的也可能失效（重载/版本变化），清空重探
        CHATFN = nil
        CHATNAME = ""
    end

    local obj = chatObj()
    if not obj then
        CHATFAIL = CHATFAIL + 1
        return false
    end
    for i = 1, #CHAT_NAMES do
        local nm = CHAT_NAMES[i]
        local okc, argc = tryCall(obj, nm, text, pid)
        if okc then
            CHATFN = { obj = obj, fn = obj[nm], name = nm, argc = argc }
            CHATNAME = "Chat." .. nm .. "(argc=" .. argc .. ")"
            CHATSENT = CHATSENT + 1
            CHATLAST = text
            return true
        end
    end
    CHATFAIL = CHATFAIL + 1
    return false
end

-- 对外输出：受 logChat 开关控制
--
-- kind: "info" 普通 / "pre" 分配前（必发，用于崩溃定位）
local function log(s, kind)
    if getNum("logChat", 1) ~= 1 then return end
    sendChat(tostring(s))
end

-- 分配前预告：崩溃定位用，不受 throttle 限制
local function logPre(s)
    if getNum("logChat", 1) ~= 1 then return end
    if getNum("chatPre", 1) == 1 then
        sendChat("[将] " .. tostring(s))
    end
end

-- 当前 Lua 内存占用（MB）
--
-- 重要：collectgarbage("count") 并非所有环境都可信。
-- 实测发现某些 Lua 运行时里，真实分配了 6.25MB，
-- 但 collectgarbage("count") 只报 0.03MB —— 计数严重失真。
-- 一旦失真，硬上限和看门狗会全部失效，工具就有闪退风险。
--
-- 所以加一道自检校准（见 calibrate()）：
-- 分配已知大小的内存，看计数器的增量对不对。
-- 对不上就置 MEMTRUST=false，全部改用自算值。
local MEMTRUST = true

local function memMB()
    if not MEMTRUST then return calcMB() end
    local ok, kb = pcall(collectgarbage, "count")
    if ok and type(kb) == "number" and kb > 0 then
        return kb / 1024
    end
    MEMTRUST = false
    return calcMB()
end

-- 校准：分配约 2MB 已知数据，看计数器增量
local function calibrate()
    collectgarbage("collect")
    local a = memMB()
    local tmp = {}
    local knowMB = 2
    local blocks = math.floor(knowMB * 1024 / 64)
    local okpc = pcall(function()
        for i = 1, blocks do
            tmp[i] = string.rep(string.char(65 + (i % 26)), 65536)
        end
    end)
    if not okpc then
        MEMTRUST = false
        return false, "分配失败"
    end
    local b = memMB()
    tmp = nil
    collectgarbage("collect")
    local delta = b - a
    -- 期望增量约 knowMB；低于一半判定失真
    if delta < knowMB * 0.5 then
        MEMTRUST = false
        return false, string.format(
            "分配 %.2fMB 但计数器只涨 %.3fMB", knowMB, delta)
    end
    MEMTRUST = true
    return true, string.format("分配 %.2fMB 计数器涨 %.2fMB", knowMB, delta)
end

-- 自算占用（MB）
-- 注意：必须赋值给前面那个 local，不能写 function calcMB()
-- 否则会创建全局函数，local 仍是 nil，memMB 调用时报错。
calcMB = function()
    local n = NPOOL
    local per
    if PHASE == 1 then
        per = 32
    elseif PHASE == 2 then
        per = (SELFREF and SELFREF.blockKB or DEFAULT_BLOCK_KB) * 1024 + 64
    elseif PHASE == 3 then
        per = 256
    elseif PHASE == 4 then
        return (BIGSTR and #BIGSTR or 0) / 1048576
    elseif PHASE == 5 then
        per = 96
    else
        per = 128
    end
    return n * per / 1048576
end

-- 属性读取：走 OnStart/首次调用时保存的组件表。
-- 绝不读 Script.propertys[x].default —— 那是定义期占位值，
-- 面板上改了也不会变。
-- 注意：这里必须用赋值形式，不能写 "local function getNum"。
-- 前面已做过前向声明，再写 local 会创建新变量遮蔽它，
-- 导致上面 sendChat 里拿到的永远是 nil。
getNum = function(name, dft)
    local v = nil
    if SELFREF then
        v = SELFREF[name]
    end
    if v == nil and RAWSELF then
        v = RAWSELF[name]
    end
    if type(v) == "number" then return v end
    if type(v) == "string" then
        local n = tonumber(v)
        if n then return n end
    end
    return dft
end

local function addReport(s)
    if not REPORT then REPORT = {} end
    NREPORT = NREPORT + 1
    REPORT[NREPORT] = tostring(s)
end

-- 分段取报告（避免单次返回过长）
local function getReport(i)
    if not REPORT then return "(无报告)" end
    if type(i) ~= "number" then i = NREPORT end
    if i < 1 then i = 1 end
    if i > NREPORT then i = NREPORT end
    local out = REPORT[i]
    if not out then return "(无)" end
    if #out <= REPORT_MAX then return out end
    -- 超长则截取尾部（尾部是临界值，最重要）
    return "...(前略)\n" .. out:sub(#out - REPORT_MAX + 20)
end

-- =============================================================
-- 阶段控制
-- =============================================================

local function beginPhase(p)
    PHASE  = p
    PDONE  = false
    NPOOL  = 0
    NSTEP  = 0
    POOL   = {}
    BIGSTR = nil
    DEEPT  = nil
    DEPTHN = 0
    LASTERR = ""
    collectgarbage("collect")
    STARTMB = memMB()
    addReport(string.format("--- 阶段 %d %s 开始  基线=%.2fMB ---",
        p, PNAME[p] or "?", STARTMB))
    log(string.format("== 阶段%d %s 开始 基线=%.2fMB 上限=%dMB ==",
        p, PNAME[p] or "?", STARTMB, getNum("maxMB", DEFAULT_MAX_MB)))
end

local function finishPhase(reason)
    PDONE = true
    FINISHED[PHASE] = true
    CURMB = memMB()
    if CURMB > PEAKMB then PEAKMB = CURMB end
    addReport(string.format(
        "[%s] 阶段%d %s 结束\n  元素=%d  自算=%.2fMB  实测=%.2fMB  净增=%.2fMB  峰值=%.2fMB%s",
        PNAME[PHASE] or "?", PHASE, reason or "", NPOOL,
        calcMB(), CURMB, CURMB - STARTMB, PEAKMB,
        (LASTERR ~= "" and ("\n  错误=" .. LASTERR) or "")))
    log(string.format("P%d 结束 元素=%d 实测=%.2fMB %s",
        PHASE, NPOOL, CURMB, reason or ""))
end

-- 安全上限检查
local function overLimit()
    if HARDSTOP then return true end
    local mx = getNum("maxMB", DEFAULT_MAX_MB)
    if memMB() >= mx then
        finishPhase("到达硬上限 " .. mx .. "MB")
        return true
    end
    return false
end

-- 看门狗：单次增长过大立即停
local function watchdog(before)
    local after = memMB()
    if after - before > WD_LIMIT_MB then
        HARDSTOP = true
        finishPhase("看门狗触发 单批增长 " ..
            string.format("%.1fMB", after - before))
        return true
    end
    return false
end

-- =============================================================
-- 各阶段单批分配
-- =============================================================

-- 阶段1：数字数组
local function step1()
    local before = memMB()
    local n = 0
    local target = getNum("stepKB", DEFAULT_STEP_KB) * 1024 / 32
    for i = 1, target do
        local ok = pcall(function()
            NPOOL = NPOOL + 1
            POOL[NPOOL] = NPOOL * 1.5
        end)
        if not ok then
            LASTERR = "写入失败"
            return true
        end
        n = n + 1
    end
    if watchdog(before) then return true end
    return overLimit()
end

-- 阶段2：字符串池（最关键）
local function step2()
    local before = memMB()
    local blk = getNum("blockKB", DEFAULT_BLOCK_KB)
    local blkChars = blk * 1024
    local cnt = math.floor(getNum("stepKB", DEFAULT_STEP_KB) / blk)
    if cnt < 1 then cnt = 1 end

    -- 先验证单块能创建
    local probe
    local okr = pcall(function() probe = string.rep("A", blkChars) end)
    if not okr or not probe then
        LASTERR = "string.rep(" .. blkChars .. ") 失败，blockKB 太大"
        return true
    end
    probe = nil

    -- 关键：每块必须是内容不同的新字符串。
    -- Lua 字符串按引用共享，插同一个 string 一百次只占一百个指针槽，
    -- 内存根本不会涨 —— 必须每块都重新生成。
    for i = 1, cnt do
        local ok = pcall(function()
            NPOOL = NPOOL + 1
            local c = string.char(65 + (NPOOL % 26))
            POOL[NPOOL] = string.rep(c, blkChars)
        end)
        if not ok then
            LASTERR = "写入失败"
            return true
        end
    end
    if watchdog(before) then return true end
    return overLimit()
end

-- 阶段3：嵌套表
local function step3()
    local before = memMB()
    local target = getNum("stepKB", DEFAULT_STEP_KB) * 1024 / 256
    for i = 1, target do
        local ok = pcall(function()
            NPOOL = NPOOL + 1
            POOL[NPOOL] = {
                id = NPOOL,
                name = "item_" .. NPOOL,
                val = NPOOL * 0.25,
                sub = { 1, 2, 3, "x", "y" },
            }
        end)
        if not ok then
            LASTERR = "写入失败"
            return true
        end
    end
    if watchdog(before) then return true end
    return overLimit()
end

-- 阶段4：单个字符串上限（倍增）
local function step4()
    local before = memMB()
    local cur = BIGSTR and #BIGSTR or 0
    if cur == 0 then cur = 65536 end
    local nxt = cur * 2
    -- 上限保护：单次不超过 16MB
    if nxt - cur > 16 * 1048576 then nxt = cur + 16 * 1048576 end

    local s
    local ok = pcall(function() s = string.rep("B", nxt) end)
    if not ok or not s then
        LASTERR = "string.rep(" .. nxt .. ") 失败"
        finishPhase("单串创建失败")
        return true
    end
    BIGSTR = s
    NPOOL = nxt
    addReport(string.format("  单串 %.2fMB 创建成功  实测=%.2fMB",
        nxt / 1048576, memMB()))
    if watchdog(before) then return true end

    if nxt >= 256 * 1048576 then
        finishPhase("已达 256MB 停止")
        return true
    end
    return overLimit()
end

-- 阶段5：哈希键
local function step5()
    local before = memMB()
    local target = getNum("stepKB", DEFAULT_STEP_KB) * 1024 / 96
    for i = 1, target do
        local ok = pcall(function()
            NPOOL = NPOOL + 1
            POOL["key_" .. NPOOL] = NPOOL
        end)
        if not ok then
            LASTERR = "写入失败"
            return true
        end
    end
    if watchdog(before) then return true end
    return overLimit()
end

-- 阶段6：深度嵌套
local function step6()
    local before = memMB()
    local target = 200
    for i = 1, target do
        local ok = pcall(function()
            DEEPT = { child = DEEPT }
            DEPTHN = DEPTHN + 1
        end)
        if not ok then
            LASTERR = "嵌套失败"
            finishPhase("深度=" .. DEPTHN)
            return true
        end
        NPOOL = DEPTHN
    end
    addReport(string.format("  深度=%d  实测=%.2fMB", DEPTHN, memMB()))
    if watchdog(before) then return true end
    if DEPTHN >= 20000 then
        finishPhase("深度达 20000 停止")
        return true
    end
    return overLimit()
end

local STEPFN = {
    [1] = step1, [2] = step2, [3] = step3,
    [4] = step4, [5] = step5, [6] = step6,
}

-- =============================================================
-- 核心：单步
-- =============================================================

local function doStep()
    if HARDSTOP then
        return "已硬停止，请调 Free() 后重设 maxMB"
    end
    -- 首步先校准计数器：失真的话硬上限会失效，有闪退风险
    if not CALIBRATED then
        CALIBRATED = true
        local cok, cmsg = calibrate()
        addReport(string.format("[校准] ok=%s %s\n  → 采用%s估算",
            tostring(cok), tostring(cmsg),
            MEMTRUST and "collectgarbage实测" or "自算值"))
    end

    -- 阶段未开始或已结束 → 进入下一个
    if PHASE == 0 or PDONE then
        -- 已收尾过的阶段不要重复收尾
        if PDONE and FINISHED[PHASE] then
            local w = getNum("phase", 0)
            if w > 0 then
                return string.format(
                    "阶段%d 已完成，用 Result(i) 查看。改 phase 属性可测其他阶段",
                    PHASE)
            end
        end
        local want = getNum("phase", 0)
        local nxt = PHASE + 1
        if want > 0 then
            if PHASE == 0 then
                nxt = want
            else
                finishPhase("单阶段模式结束")
                return string.format("阶段%d 完成，见 Result(%d)", PHASE, NREPORT)
            end
        end
        if nxt > 6 then
            return string.format(
                "全部阶段完成。峰值=%.2fMB 报告段数=%d 用 Result(i) 查看",
                PEAKMB, NREPORT)
        end
        beginPhase(nxt)
        return string.format("进入 阶段%d %s  基线=%.2fMB",
            nxt, PNAME[nxt] or "?", STARTMB)
    end

    local fn = STEPFN[PHASE]
    if not fn then
        PDONE = true
        return "未知阶段"
    end

    -- 关键：在真正分配之前先把预告发出去。
    -- 这样一旦本批直接崩（引擎层 OOM，pcall 抓不到），
    -- 聊天框最后一条就是崩溃点，能定位到具体批号和当时的内存。
    NSTEP = NSTEP + 1
    logPre(string.format("P%d 批%d 元素%d 当前%.1fMB 上限%dMB",
        PHASE, NSTEP, NPOOL, memMB(), getNum("maxMB", DEFAULT_MAX_MB)))

    local before = memMB()
    local ok, stop = pcall(fn)
    if not ok then
        LASTERR = tostring(stop)
        -- 捕获 OOM
        if tostring(stop):find("not enough memory")
            or tostring(stop):find("memory") then
            finishPhase("OOM 捕获")
            return string.format("⚠ OOM@P%d %s\n崩溃前: 元素=%d 自算=%.2fMB",
                PHASE, tostring(stop), NPOOL, calcMB())
        end
        finishPhase("异常")
        return "异常: " .. tostring(stop)
    end

    local now = memMB()
    if now > PEAKMB then PEAKMB = now end

    if stop then
        if not PDONE then finishPhase("触发停止") end
        return string.format("P%d 停止 元素=%d 实测=%.2fMB",
            PHASE, NPOOL, now)
    end

    return string.format("P%d 元素=%d 自算=%.2fMB 实测=%.2fMB 峰值=%.2fMB 本批+%.2fMB",
        PHASE, NPOOL, calcMB(), now, PEAKMB, now - before)
end

-- =============================================================
-- 惰性初始化（不依赖 OnStart）
-- =============================================================

local function ensureInit(self)
    if self then
        SELFREF = self
        -- 原样快照一份组件表，避免后续走 pcall 索引
        if not RAWSELF then
            local snap = {}
            local ok = pcall(function()
                for k, v in pairs(self) do snap[k] = v end
            end)
            if ok then RAWSELF = snap end
        end
    end
    if not REPORT then
        REPORT = {}
        NREPORT = 0
    end
    if not POOL then POOL = {} end
    INITED = true
end

-- =============================================================
-- 组件属性
-- =============================================================

Script.propertys = {
    maxMB = {
        type = Mini.Number,
        default = 200,
        displayName = "安全上限MB",
        tips = "实测内存达此值立即停止。首次请设50",
    },
    stepKB = {
        type = Mini.Number,
        default = 1024,
        displayName = "每批KB",
        tips = "每次Step分配的目标大小",
    },
    blockKB = {
        type = Mini.Number,
        default = 64,
        displayName = "单块KB",
        tips = "阶段2每块字符串大小。首次请设64",
    },
    phase = {
        type = Mini.Number,
        default = 0,
        displayName = "只跑阶段",
        tips = "0=全部 1~6=只跑指定阶段",
    },
    logChat = {
        type = Mini.Number,
        default = 1,
        displayName = "输出聊天",
        tips = "1=输出 0=静默",
    },
    chatPlayerId = {
        type = Mini.Number,
        default = 0,
        displayName = "发送目标ID",
        tips = "0=广播给所有人；非0=只发给该玩家",
    },
    chatPre = {
        type = Mini.Number,
        default = 1,
        displayName = "分配前预告",
        tips = "1=每批分配前先发一条，崩了能定位。0=不发",
    },
    autoRun = {
        type = Mini.Number,
        default = 0,
        displayName = "自动开跑",
        tips = "强烈建议保持0，手动Step",
    },
}

-- =============================================================
-- 开放函数登记表（只写 openFnArgs，不做互相赋值）
-- =============================================================

Script.openFnArgs = {
    Probe = true,
    Step = true,
    Run = true,
    Status = true,
    Result = true,
    ResultCount = true,
    ListPhases = true,
    Free = true,
    ChatInfo = true,
    Say = true,
}

-- =============================================================
-- 开放函数实现
-- =============================================================

-- 极简连通性测试：只测 2MB
function Script:Probe()
    ensureInit(self)
    log("[Probe] 开始，只测 2MB")
    local out = {}
    out[#out + 1] = "=== 连通性探测 ==="

    -- 先验证聊天通道：后面全靠它观察崩溃点
    local cok = sendChat("[内存探测] 通道自检")
    out[#out + 1] = string.format("0 聊天通道 ok=%s 通道=%s pid=%d",
        tostring(cok), (CHATNAME ~= "" and CHATNAME or "未命中"),
        getNum("chatPlayerId", 0))
    if not cok then
        out[#out + 1] = "  ⚠ 收不到就看 ChatInfo() 里的『可用函数』"
    end

    local ok1, kb1 = pcall(collectgarbage, "count")
    out[#out + 1] = string.format("1 collectgarbage ok=%s 当前=%.2fMB",
        tostring(ok1), (type(kb1) == "number" and kb1 / 1024 or 0))

    local t = {}
    local ok2, err2 = pcall(function()
        for i = 1, 32 do t[i] = string.rep("A", 65536) end
    end)
    out[#out + 1] = string.format("2 分配32块x64KB ok=%s 个数=%d 实测=%.2fMB",
        tostring(ok2), ok2 and #t or 0, memMB())

    -- 内存计数器校准：这一项最关键
    local cok, cmsg = calibrate()
    out[#out + 1] = string.format("3 计数器校准 ok=%s %s",
        tostring(cok), tostring(cmsg))
    out[#out + 1] = string.format("  → 采用%s估算",
        MEMTRUST and "collectgarbage实测" or "自算值")
    if not cok then
        out[#out + 1] = "  ⚠ 实测失真，已自动切换自算值"
        out[#out + 1] = "  ⚠ 这是安全 fallback，不是故障"
    end

    local ok3, err3 = pcall(function()
        local s = string.rep("C", 1024 * 1024)
        return #s
    end)
    out[#out + 1] = string.format("4 单串1MB ok=%s", tostring(ok3))

    local ok4, err4 = pcall(function()
        local d = {}
        local c = d
        for i = 1, 500 do c = { child = c } end
        return true
    end)
    out[#out + 1] = string.format("4 深嵌套500 ok=%s", tostring(ok4))

    t = nil
    collectgarbage("collect")
    out[#out + 1] = string.format("5 释放后=%.2fMB", memMB())
    out[#out + 1] = "=== 探测结束 ==="

    local s = table.concat(out, "\n")
    log("[Probe] 完成 详见返回")
    return s
end

-- 核心：分配一批
function Script:Step()
    ensureInit(self)
    local r = doStep()
    log(r)
    return r
end

-- 自动跑完（有步数上限）
function Script:Run()
    ensureInit(self)
    local maxstep = getNum("maxStep", 400)
    local lines = {}
    for i = 1, maxstep do
        local r = doStep()
        if i <= 5 or i % 20 == 0 then
            lines[#lines + 1] = string.format("[%d] %s", i, r)
        end
        if HARDSTOP then
            lines[#lines + 1] = "硬停止"
            break
        end
        if r:find("全部阶段完成") then break end
        if getNum("phase", 0) > 0 and r:find("完成") then break end
    end
    lines[#lines + 1] = string.format("峰值=%.2fMB 报告段数=%d",
        PEAKMB, NREPORT)
    local s = table.concat(lines, "\n")
    log(string.format("[Run] 结束 峰值=%.1fMB 报告%d段", PEAKMB, NREPORT))
    return s
end

-- 当前状态
function Script:Status()
    ensureInit(self)
    local mx = getNum("maxMB", DEFAULT_MAX_MB)
    local st = getNum("stepKB", DEFAULT_STEP_KB)
    local bk = getNum("blockKB", DEFAULT_BLOCK_KB)
    local ph = getNum("phase", 0)
    local warn = ""
    if mx > 100 then
        warn = "\n⚠ maxMB=" .. mx .. " 偏高，首次建议50"
    end
    return string.format(
        "=== 内存探测工具 v2.0 ===\n" ..
        "maxMB=%d  stepKB=%d  blockKB=%d  phase=%d(%s)\n" ..
        "当前阶段=%s  元素=%d  实测=%.2fMB  峰值=%.2fMB\n" ..
        "硬停止=%s  报告段数=%d  计量=%s\n" ..
        "聊天=%s  通道=%s  已发=%d 失败=%d 目标ID=%d%s\n" ..
        "提示：先 Probe() → 再设 maxMB=50 → 反复 Step()",
        mx, st, bk, ph, (ph == 0 and "全部" or (PNAME[ph] or "?")),
        (PNAME[PHASE] or "未开始"), NPOOL, memMB(), PEAKMB,
        tostring(HARDSTOP), NREPORT,
        (MEMTRUST and "实测" or "自算"),
        (getNum("logChat", 1) == 1 and "开" or "关"),
        (CHATNAME ~= "" and CHATNAME or "未命中"),
        CHATSENT, CHATFAIL, getNum("chatPlayerId", 0), warn)
end

-- 取报告
function Script:Result(i)
    ensureInit(self)
    return getReport(i)
end

-- 报告段数
function Script:ResultCount()
    ensureInit(self)
    return string.format("报告段数=%d  峰值=%.2fMB", NREPORT, PEAKMB)
end

-- 聊天通道自检
-- 说明：pcall 成功只代表函数存在且没抛异常，
-- 不代表消息真的显示出来了。收不到就对照下面的候选表排查。
function Script:ChatInfo()
    ensureInit(self)
    local out = {}
    out[#out + 1] = "=== 聊天通道 ==="
    local obj = chatObj()
    out[#out + 1] = "Chat模块=" .. (obj and "存在" or "不存在")
    if obj then
        local found = {}
        local okp = pcall(function()
            for k, v in pairs(obj) do
                if type(v) == "function" then
                    found[#found + 1] = tostring(k)
                end
            end
        end)
        if okp and #found > 0 then
            table.sort(found)
            out[#out + 1] = "可用函数: " .. table.concat(found, " ")
        end
    end
    out[#out + 1] = "已命中=" .. (CHATNAME ~= "" and CHATNAME or "(未命中)")
    out[#out + 1] = string.format("发送成功=%d 失败=%d 目标ID=%d",
        CHATSENT, CHATFAIL, getNum("chatPlayerId", 0))
    out[#out + 1] = "最后一条=" .. (CHATLAST ~= "" and CHATLAST or "(无)")
    out[#out + 1] = "---"
    out[#out + 1] = "若收不到消息：调 Say(测试) 手动验证；"
    out[#out + 1] = "仍无则把上面『可用函数』发我，我改用其中的名字。"
    return table.concat(out, "\n")
end

-- 手动发一条消息（验证聊天通道用）
function Script:Say(text)
    ensureInit(self)
    if text == nil or text == "" then text = "测试：聊天通道正常" end
    local ok = sendChat(tostring(text))
    return string.format("发送%s  通道=%s  pid=%d",
        ok and "成功" or "失败",
        (CHATNAME ~= "" and CHATNAME or "未命中"),
        getNum("chatPlayerId", 0))
end

-- 阶段清单
function Script:ListPhases()
    return table.concat({
        "1 数字数组   单表塞number",
        "2 字符串池   定长块存table ← 最贴近权重存储",
        "3 嵌套表     多字段table数组",
        "4 单串上限   单个string能多大",
        "5 哈希键     string key元素上限",
        "6 深度嵌套   嵌套深度/栈",
        "phase=0 全部  phase=1~6 只跑指定阶段",
    }, "\n")
end

-- 释放
function Script:Free()
    POOL = nil
    BIGSTR = nil
    DEEPT = nil
    NPOOL = 0
    PHASE = 0
    PDONE = false
    HARDSTOP = false
    DEPTHN = 0
    FINISHED = {}
    collectgarbage("collect")
    collectgarbage("collect")
    local s = string.format("已释放  当前=%.2fMB  峰值保留=%.2fMB", memMB(), PEAKMB)
    log(s)
    return s
end

-- =============================================================
-- 生命周期（保持原名，引擎按名字调用）
-- =============================================================

function Script:OnStart()
    SELFREF = self
    ensureInit(self)
    PEAKMB = 0
    HARDSTOP = false
    addReport("组件启动 " .. os.date("%Y-%m-%d %H:%M:%S"))
    log("[内存探测] 就绪。先调 Probe()")

    if getNum("autoRun", 0) == 1 then
        log("[内存探测] autoRun=1 自动开跑")
        -- 仅跑少量步，避免卡死
        for i = 1, 10 do
            doStep()
            if HARDSTOP then break end
        end
    end
end

function Script:OnDestroy()
    POOL = nil
    BIGSTR = nil
    DEEPT = nil
    collectgarbage("collect")
end

return Script
