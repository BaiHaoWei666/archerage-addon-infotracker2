-- 透過實際 main.lua 啟動，驗證載入初始化及一般事件的資料更新。
ADDON={ImportAPI=function() end}
API_TYPE=setmetatable({}, {__index=function() return {id=1} end})
UIEVENT_TYPE=setmetatable({}, {__index=function(_, key) return key end})
TADT_TODAY=1
local events,calls={}, {journal=0,quests=0,assignments=0}
local completed={[2]=true,[3]=true}
local slots={}
for slot=1,7 do slots[slot]={questType=100+slot,status=2} end
UIParent={SetEventHandler=function(_, event, fn) events[event]=fn end}
X2Quest={
    GetActiveQuestListCount=function() calls.journal=calls.journal+1; return 1 end,
    GetActiveQuestType=function() return 1 end,
    IsCompleted=function(_, id) calls.quests=calls.quests+1; return completed[id]==true end,
}
X2Achievement={GetTodayAssignmentInfo=function(_, _, slot)
    calls.assignments=calls.assignments+1; return slots[slot]
end}
dofile('core.lua')
ITV2.Text=function(key) return key end
ITV2.Chat=function() end
ITV2.CATEGORIES={
    {key='daily',kind='quest',items={{key='A',ids={1,2}}}},
    {key='weekly',kind='quest',items={{key='B',ids={3}}}},
}
dofile('sources/common.lua'); dofile('tracking_data.lua'); dofile('sources/quest.lua')
local data=ITV2.TrackingData
local refreshes,changed,showChallenge=0,nil,false
local function Refresh(categories)
    refreshes=refreshes+1; changed=categories
    if showChallenge and categories.challenge then
        for slot=1,7 do data.GetAssignment(slot) end
    end
end
local initialView
ITV2.Popout={
    Init=function() initialView=ITV2.SOURCES.quest.View(ITV2.CATEGORIES[1].items[1],{}).text end,
    GetPosition=function() return {} end,
    RefreshData=Refresh,
}
ITV2.Editor={RefreshData=Refresh}
ITV2.Settings={Load=function() end,ReportLoadedPosition=function() end}
dofile('main.lua')

-- 載入即有可用資料；後續 OnUpdate 不再初始化，ENTERED_WORLD 已移除。
assert(initialView=='A (1/2)' and calls.journal==1 and calls.quests==3 and calls.assignments==7)
assert(events.ENTERED_WORLD==nil)
ITV2.AdvanceTime(0); ITV2.AdvanceTime(60000)
assert(calls.journal==1 and calls.quests==3 and calls.assignments==7 and refreshes==0)

-- 事件當下改狀態；連續事件的畫面通知仍合併，completed 不被晚到的 updated 推翻。
events.QUEST_CONTEXT_UPDATED(1,'completed')
events.QUEST_CONTEXT_UPDATED(1,'updated')
assert(data.GetQuest(1).completed and not data.GetQuest(1).active)
assert(refreshes==0)
ITV2.AdvanceTime(0)
assert(refreshes==2 and changed.daily and not changed.weekly)
events.QUEST_CONTEXT_UPDATED(1,'reset')
assert(not data.GetQuest(1).completed and data.GetQuest(2).completed and data.GetQuest(3).completed)
events.QUEST_CONTEXT_UPDATED(1,'started')
assert(data.GetQuest(1).active)
ITV2.AdvanceTime(0)
local before=refreshes
events.QUEST_CONTEXT_UPDATED(1,'updated')
events.QUEST_CONTEXT_UPDATED(99999,'completed')
ITV2.AdvanceTime(0)
assert(refreshes==before and calls.journal==1 and calls.quests==3)

-- 挑戰隱藏時僅失效，顯示後才讀；兩視窗共用查詢結果。
slots[2].status=3
events.QUEST_CONTEXT_UPDATED(102,'completed')
ITV2.AdvanceTime(0)
assert(calls.assignments==7)
assert(data.GetAssignment(2).status==3 and calls.assignments==8)
data.GetAssignment(2)
assert(calls.assignments==8)
showChallenge=true
slots[2].status=1
events.QUEST_CONTEXT_UPDATED(102,'reset')
ITV2.AdvanceTime(0)
assert(data.GetAssignment(2).status==1 and calls.assignments==9)

-- 更換挑戰只合併一次七格重讀，新 ID 的後續事件仍能更新單格。
events.QUEST_CONTEXT_UPDATED(102,'dropped')
slots[2]={questType=202,status=2}
events.START_TODAY_ASSIGNMENT()
events.UPDATE_TODAY_ASSIGNMENT({questType=202})
ITV2.AdvanceTime(0)
assert(data.GetAssignment(2).questType==202 and calls.assignments==16)
slots[2].status=3
events.QUEST_CONTEXT_UPDATED(202,'completed')
ITV2.AdvanceTime(0)
assert(data.GetAssignment(2).status==3 and calls.assignments==17)

-- 原本的角色資訊快取仍跨視窗共用，到期才讀取。
local infoReads=0
local function ReadInfo() infoReads=infoReads+1; return false end
assert(data.ReadInfo('buff',ReadInfo)==false)
data.ReadInfo('buff',ReadInfo)
ITV2.AdvanceTime(999); data.ReadInfo('buff',ReadInfo)
assert(infoReads==1)
ITV2.AdvanceTime(1); data.ReadInfo('buff',ReadInfo)
assert(infoReads==2)
print('PASS: 實際載入單次初始化、立即任務狀態更新、畫面合併、挑戰延後讀取與共用、角色快取')
