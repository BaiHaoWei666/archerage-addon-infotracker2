-- 共用資料層：集中管理事件、快取與必要輪詢；視窗只宣告需求並接收變更。
local Data = {}
ITV2.TrackingData = Data
local quests, questCategories = {}, {}
local assignments, dirtySlots = {}, {}
local allAssignmentsDirty = true
local polled = {}
local pending = {}
local scheduled = false

local function Notify(category)
    pending[category] = true
    if scheduled then return end
    scheduled = true
    ITV2.Schedule("tracking-data", 0, function()
        scheduled = false
        local changed = pending
        pending = {}
        if ITV2.Editor then ITV2.Editor.RefreshData(changed) end
        if ITV2.Popout then ITV2.Popout.RefreshData(changed) end
    end)
end

local function Copy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for key, field in pairs(value) do out[key] = Copy(field) end
    return out
end

local function Equal(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for key, value in pairs(a) do if not Equal(value, b[key]) then return false end end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end

local function ReadEntry(entry)
    local value = Copy(entry.read())
    local changed = not entry.loaded or not Equal(entry.value, value)
    entry.value, entry.loaded, entry.time = value, true, ITV2.NowMs()
    return changed
end

-- nil 與 false 也快取；複製快照避免遊戲重用 table 造成變更漏判。
function Data.ReadPolled(category, key, read, interval)
    polled[category] = polled[category] or {}
    local entry = polled[category][key]
    if not entry then
        entry = { read = read, interval = interval }
        polled[category][key] = entry
    end
    if not entry.loaded or ITV2.NowMs() - entry.time >= entry.interval then
        local wasLoaded = entry.loaded
        local changed = ReadEntry(entry)
        -- 初次顯示已在刷新；失效來源也已有通知，避免通知回圈多刷一幀。
        if wasLoaded and changed then Notify(category) end
    end
    return entry.value
end

function Data.Invalidate(category, key)
    for entryKey, entry in pairs(polled[category] or {}) do
        if key == nil or key == entryKey then entry.loaded = false end
    end
    Notify(category)
end

-- 每個視窗回傳目前分類與需要的項目；合併後每個來源最多讀一次。
function Data.Poll()
    local wanted = {}
    for _, name in ipairs({ "Editor", "Popout" }) do
        local window = ITV2[name]
        if window and window.GetDataDemand then
            local category, keys = window.GetDataDemand()
            if category then
                wanted[category] = wanted[category] or {}
                for _, key in ipairs(keys) do wanted[category][key] = true end
            end
        end
    end
    for category, keys in pairs(wanted) do
        for key, entry in pairs(polled[category] or {}) do
            if (keys[key] or (key == "*" and next(keys)))
                and (not entry.loaded or ITV2.NowMs() - entry.time >= entry.interval) then
                -- 個別 API 失敗不阻斷其他來源，也不停止下次重試。
                local ok, changed = pcall(ReadEntry, entry)
                if ok and changed then Notify(category) end
            end
        end
    end
end

local function ReadSlot(slot)
    local value = X2Achievement:GetTodayAssignmentInfo(TADT_TODAY, slot)
    -- 保留獨立快照，避免引擎重用同一個 table 後悄悄改變快取。
    local copy = false
    if type(value) == "table" then
        copy = {}
        for key, field in pairs(value) do copy[key] = field end
    end
    assignments[slot] = copy
    dirtySlots[slot] = nil
end

local function ReadAllAssignments()
    for slot = 1, 7 do ReadSlot(slot) end
    allAssignmentsDirty = false
end

function Data.GetAssignment(slot)
    if allAssignmentsDirty then
        ReadAllAssignments()
    elseif dirtySlots[slot] or assignments[slot] == nil then
        ReadSlot(slot)
    end
    return assignments[slot] or nil
end

local function FindSlot(id)
    for slot, value in pairs(assignments) do
        if value and value.questType == id then return slot end
    end
end

function Data.GetQuest(id)
    return quests[id]
end

function Data.ReadInfo(key, read)
    return Data.ReadPolled("info", key, read, 1000)
end

function Data.Initialize()
    local nextQuests, nextCategories = {}, {}
    local journal = ITV2.SourceUtil.GetJournalIndexMap({})
    for _, cat in ipairs(ITV2.CATEGORIES) do
        if cat.kind == "quest" then
            for _, item in ipairs(cat.items) do
                for _, id in ipairs(item.ids) do
                    nextCategories[id] = nextCategories[id] or {}
                    nextCategories[id][cat.key] = true
                    if nextQuests[id] == nil then
                        local complete = X2Quest:IsCompleted(id) == true
                        nextQuests[id] = { completed = complete, active = not complete and journal[id] ~= nil }
                    end
                end
            end
        end
    end
    ReadAllAssignments()
    quests, questCategories = nextQuests, nextCategories
    for _, entries in pairs(polled) do
        for _, entry in pairs(entries) do entry.loaded = false end
    end
end

function Data.QuestEvent(id, action)
    id = tonumber(id)
    if id == nil then return end
    local state = quests[id]
    if state then
        local complete, active = state.completed, state.active
        if action == "completed" then
            complete, active = true, false
        elseif action == "started" then
            complete, active = false, true
        elseif action == "updated" then
            -- 進度事件不推翻已交付狀態；reset / started 才會清除完成。
            if not complete then active = true end
        elseif action == "dropped" then
            complete, active = false, false
        elseif action == "reset" then
            -- 僅清除此 ID 的完成狀態，保留仍在日誌中的接取狀態。
            complete = false
        end
        if state.completed ~= complete or state.active ~= active then
            state.completed, state.active = complete, active
            for category in pairs(questCategories[id]) do Notify(category) end
        end
    end
    local slot = FindSlot(id)
    if slot then
        if action == "dropped" then
            -- 舊格被移除後可能重排，與後續更換通知合併重建對應。
            allAssignmentsDirty = true
        else
            dirtySlots[slot] = true
        end
        Notify("challenge")
        Data.Invalidate("info", "INFO_DAILY")
    end
end

function Data.AssignmentEvent(value)
    local slot = type(value) == "table" and FindSlot(tonumber(value.questType)) or nil
    if slot then dirtySlots[slot] = true else allAssignmentsDirty = true end
    Notify("challenge")
    Data.Invalidate("info", "INFO_DAILY")
end

function Data.RegisterEvents()
    local function PollNext()
        Data.Poll()
        ITV2.Schedule("tracking-poll", 1000, PollNext)
    end
    ITV2.Schedule("tracking-poll", 1000, PollNext)
    UIParent:SetEventHandler(UIEVENT_TYPE.QUEST_CONTEXT_UPDATED, Data.QuestEvent)
    UIParent:SetEventHandler(UIEVENT_TYPE.UPDATE_TODAY_ASSIGNMENT, Data.AssignmentEvent)
    UIParent:SetEventHandler(UIEVENT_TYPE.START_TODAY_ASSIGNMENT, function()
        Data.AssignmentEvent()
    end)
    UIParent:SetEventHandler(UIEVENT_TYPE.ENTERED_WORLD, function()
        -- 進場同步一次，不對場景中每個任務通知各自全讀。
        ITV2.Schedule("tracking-world", 0, function()
            Data.Initialize()
            for _, cat in ipairs(ITV2.CATEGORIES) do
                Notify(cat.key)
            end
        end)
    end)
end
