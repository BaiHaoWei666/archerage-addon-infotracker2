-- 副本次數與建立戰隊
ADDON:ImportAPI(API_TYPE.BATTLE_FIELD.id)
ADDON:ImportAPI(API_TYPE.SQUAD.id)

local T = ITV2.Text
local Chat = ITV2.Chat
local Util = ITV2.SourceUtil

local DUNGEON_KIND_ID = 4
local SQUAD_COOLDOWN_MS = 5000
local CANNOT_SOLO = { [24] = true, [43] = true, [52] = true, [53] = true, [66] = true, [80] = true }

local squadCooldownUntil = 0

-- 建隊與確認視窗使用即時資料；顯示次數才使用共用快取。
local function GetDungeonList()
    return X2BattleField:GetInstanceListByKind(DUNGEON_KIND_ID) or {}
end

local function ReadDungeon(item)
    return ITV2.TrackingData.ReadPolled("dungeon", item.key, function()
        local list = ITV2.TrackingData.ReadPolled("dungeon", "list", function()
            return X2BattleField:GetInstanceListByKind(DUNGEON_KIND_ID) or {}
        end, 5000)
        local instance = list[item.index]
        if not instance then return nil end
        local info = X2BattleField:GetDetailInstanceInfo(instance.type)
        return {
            name = X2BattleField:GetInstanceName(instance.type) or "?",
            entered = info and info.enterCount or 0,
            max = info and info.maxEnterCount,
        }
    end, 5000)
end

local function CreateSquad(instance, inviteParty)
    local name = X2BattleField:GetInstanceName(instance.type) or "?"

    local remaining = squadCooldownUntil - ITV2.NowMs()
    if remaining > 0 then
        Chat(string.format(T("COOLDOWN_WAIT"), math.ceil(remaining / 1000)))
        return
    end

    local info = X2BattleField:GetDetailInstanceInfo(instance.type)
    if info == nil then
        Chat(string.format(T("CANNOT_GET_INFO"), name))
        return
    end
    if info.enterCount ~= nil and info.maxEnterCount ~= nil and info.enterCount >= info.maxEnterCount then
        Chat(string.format(T("NO_REMAIN_COUNT"), name))
        return
    end

    inviteParty = inviteParty == true
    if inviteParty then
        Chat(T("SQUAD_INVITE_LOG"))
    end

    local minGS = info.gearScore or 0
    local minLV = info.levelMin or 55

    -- 能單人就先快速匹配，失敗再建非公開戰隊
    if info.singleApplyAvailable == true and not CANNOT_SOLO[instance.type] then
        Chat(string.format(T("QUICK_ENTER"), name))
        if X2Squad:CreateSquad(instance.type, SOT_DIRECT_MATCHING, "", inviteParty, minLV, minGS) then
            squadCooldownUntil = ITV2.NowMs() + SQUAD_COOLDOWN_MS
            Chat(string.format(T("CREATE_SUCCESS_QUICK"), name, tostring(instance.type)))
            return
        end
        Chat(string.format(T("CREATE_FAILED_QUICK"), name, tostring(instance.type)))
    else
        Chat(string.format(T("CREATING_TEAM"), name))
    end

    if X2Squad:CreateSquad(instance.type, SOT_PRIVATE, "", inviteParty, minLV, minGS) then
        squadCooldownUntil = ITV2.NowMs() + SQUAD_COOLDOWN_MS
        Chat(string.format(T("CREATE_SUCCESS_PRIVATE"), name))
    else
        Chat(string.format(T("CREATE_FAILED_PRIVATE"), name))
    end
end

ITV2.SOURCES.dungeon = {
    View = function(item)
        local data = ReadDungeon(item)
        if data == nil then
            return { text = string.format(T("DUNGEON_FALLBACK"), item.index), status = "neutral" }
        end
        if data.max == nil then
            return { text = data.name, status = "neutral" }
        end
        return {
            text = string.format("%s [%d/%d]", data.name, data.entered, data.max),
            status = Util.ProgressStatus(data.entered, data.max),
        }
    end,

    -- 詢問窗顯示用的副本名稱
    GetName = function(item)
        local instance = GetDungeonList()[item.index]
        local name = instance and X2BattleField:GetInstanceName(instance.type)
        return name or string.format(T("DUNGEON_FALLBACK"), item.index)
    end,

    -- options.inviteParty：建立戰隊時邀請隊伍成員
    Activate = function(item, options)
        local instance = GetDungeonList()[item.index]
        if instance == nil or instance.type == nil then
            Chat(T("INVALID_INSTANCE"))
            return
        end
        CreateSquad(instance, options ~= nil and options.inviteParty)
    end,

}
