-- 共用資料層：任務靠事件更新，挑戰依失效格子讀取，角色資訊共用輪詢快取。
local Data = {}
ITV2.TrackingData = Data
local quests, questCategories = {}, {}
local assignments, dirtySlots = {}, {}
local allAssignmentsDirty = true
local infoCache = {}
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
    local now = ITV2.NowMs()
    local cached = infoCache[key]
    if cached and now - cached.time < 1000 then return cached.value end
    local value = read()
    infoCache[key] = { time = now, value = value }
    return value
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
    infoCache = {}
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
    end
end

function Data.AssignmentEvent(value)
    local slot = type(value) == "table" and FindSlot(tonumber(value.questType)) or nil
    if slot then dirtySlots[slot] = true else allAssignmentsDirty = true end
    Notify("challenge")
end

function Data.RegisterEvents()
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
                if cat.kind == "quest" or cat.kind == "assignment" then Notify(cat.key) end
            end
        end)
    end)
end
