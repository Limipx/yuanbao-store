--====================================================================
-- 表ID探针 v3 · 确认 playerId 到底该传什么
--====================================================================
local Script = {}
Script.propertys = {
    tableIds = {
        type = Mini.Array, itemType = Mini.String,
        default = Mini.Array(Mini.String,
            "v7694277148953455613110817",
            "v7694277153248422909110818"),
        displayName = "二维表ID组", customDisplayName = "表ID"
    },
}
Script.openFnArgs = {
    Probe3 = { returnType = Mini.String, displayName = "pid扫描" },
}
local function add(L, s) L[#L + 1] = tostring(s) end

function Script:Probe3()
    local L = {}
    add(L, "=== v3 playerId 扫描 ===")
    local ids = {}
    pcall(function()
        for i = 1, #self.tableIds do
            local v = self.tableIds[i]
            if type(v) == "string" and v ~= "" then ids[#ids + 1] = v end
        end
    end)
    if #ids == 0 then return "无ID" end
    local t = ids[1]
    add(L, "tid=" .. t)

    local pids = { ["nil"] = nil, ["0"] = 0, ["1"] = 1 }
    for k, pid in pairs(pids) do
        local ok, rows = pcall(Data.Table.GetAllValue, Data.Table, t, pid)
        local n = -1
        if ok and type(rows) == "table" then
            n = 0
            for _ in pairs(rows) do n = n + 1 end
        end
        add(L, "pid=" .. k .. " ok=" .. tostring(ok) .. " type=" .. type(rows) .. " 个数=" .. n)
        if ok and type(rows) == "table" and n > 0 then
            local okr, r1 = pcall(function() return rows[1] end)
            if okr then
                if type(r1) == "table" then
                    add(L, "   row1[1]=" .. tostring(r1[1]):sub(1, 50))
                else
                    add(L, "   row1=" .. tostring(r1):sub(1, 50))
                end
            end
        end
    end

    -- GetTableColKeys 到底返回几个（验证之前那个 table 是否为空壳）
    local okc, keys = pcall(function() return Data.Table:GetTableColKeys(t) end)
    local cn = -1
    if okc and type(keys) == "table" then
        cn = 0
        for _ in pairs(keys) do cn = cn + 1 end
    end
    add(L, "GetTableColKeys 个数=" .. cn)

    add(L, "=== 结束 ===")
    return table.concat(L, "\n")
end
function Script:OnStart() print("[v3] 调 Probe3()") end
return Script
