-- 實際資料層與來源：初始化全讀、事件合併、單一 reset、隱藏頁延後讀取。
ADDON = { ImportAPI = function() end }
API_TYPE = setmetatable({}, {__index=function() return {id=1} end})
UIEVENT_TYPE = setmetatable({}, {__index=function(_, key) return key end})
TADT_TODAY = 1
local handlers, calls = {}, {journal=0, complete=0, assignment=0}
UIParent = { SetEventHandler=function(_, name, fn) handlers[name]=fn end }
dofile('core.lua')
ITV2.Text = function(key) return key end
ITV2.CATEGORIES = {
    {key='daily',kind='quest',items={{key='A',ids={1,2}}}},
    {key='weekly',kind='quest',items={{key='B',ids={3}}}},
}
local completed = {[2]=true,[3]=true}
X2Quest = {
    GetActiveQuestListCount=function() calls.journal=calls.journal+1; return 1 end,
    GetActiveQuestType=function() return 1 end,
    IsCompleted=function(_, id) calls.complete=calls.complete+1; return completed[id] or false end,
    GetQuestContextMainTitle=function(_, id) return 'Quest '..id end,
}
local slots={}
for i=1,7 do slots[i]={questType=100+i,status=2} end
X2Achievement = {GetTodayAssignmentInfo=function(_, _, slot)
    calls.assignment=calls.assignment+1; return slots[slot]
end}
dofile('sources/common.lua')
dofile('tracking_data.lua')
dofile('sources/quest.lua')
local Data=ITV2.TrackingData
Data.Initialize()
Data.RegisterEvents()
assert(calls.journal==1 and calls.complete==3 and calls.assignment==7)
assert(handlers.CLEAR_COMPLETED_QUEST_INFO==nil and handlers.UPDATE_COMPLETED_QUEST_INFO==nil)
local updates, visibleChallenge = 0, false
local lastChanged
ITV2.Editor={RefreshData=function(changed)
    updates=updates+1; lastChanged=changed
    if visibleChallenge and changed.challenge then
        for slot=1,7 do Data.GetAssignment(slot) end
    end
end}
ITV2.Popout={RefreshData=function(changed)
    if visibleChallenge and changed.challenge then
        for slot=1,7 do Data.GetAssignment(slot) end
    end
end}
local quest=ITV2.SOURCES.quest
local item=ITV2.CATEGORIES[1].items[1]
for i=1,100 do quest.View(item,{}); quest.Children(item,{}) end
ITV2.AdvanceTime(60000)
assert(calls.complete==3 and calls.journal==1 and updates==0, '閒置或顯示仍輪詢')
handlers.QUEST_CONTEXT_UPDATED(99999,'started')
ITV2.AdvanceTime(1)
assert(updates==0, '無關任務觸發刷新')
handlers.QUEST_CONTEXT_UPDATED(1,'dropped')
handlers.QUEST_CONTEXT_UPDATED(1,'started')
handlers.QUEST_CONTEXT_UPDATED(1,'updated')
ITV2.AdvanceTime(1)
assert(updates==1 and lastChanged.daily and not lastChanged.weekly)
assert(Data.GetQuest(1).active and not Data.GetQuest(1).completed)
handlers.QUEST_CONTEXT_UPDATED(1,'updated')
ITV2.AdvanceTime(1)
assert(updates==1, '進行中 updated 無顯示變更仍刷新')
handlers.QUEST_CONTEXT_UPDATED(1,'completed')
handlers.QUEST_CONTEXT_UPDATED(1,'reset')
ITV2.AdvanceTime(1)
assert(not Data.GetQuest(1).completed and not Data.GetQuest(1).active)
assert(Data.GetQuest(2).completed and Data.GetQuest(3).completed, 'reset 誤清除其他任務')
assert(calls.complete==3 and calls.journal==1 and calls.assignment==7, 'reset 觸發全讀')

-- 隱藏時事件不讀取；切入後只讀失效格，第二個視窗共用结果。
slots[2].status=3
handlers.QUEST_CONTEXT_UPDATED(102,'completed')
ITV2.AdvanceTime(1)
assert(calls.assignment==7)
assert(Data.GetAssignment(2).status==3 and calls.assignment==8)
Data.GetAssignment(2)
assert(calls.assignment==8)
visibleChallenge=true
slots[2].status=1
handlers.QUEST_CONTEXT_UPDATED(102,'reset')
ITV2.AdvanceTime(1)
assert(calls.assignment==9 and Data.GetAssignment(2).status==1, '挑戰 reset 未限單格')
handlers.QUEST_CONTEXT_UPDATED(99999,'reset')
ITV2.AdvanceTime(1)
assert(calls.assignment==9)

-- 更換舊任務、開始新挑戰合併七格讀取，包含新 ID 的後續對應。
handlers.QUEST_CONTEXT_UPDATED(102,'dropped')
slots[2]={questType=202,status=2}
handlers.QUEST_CONTEXT_UPDATED(202,'started')
handlers.START_TODAY_ASSIGNMENT('副本')
handlers.UPDATE_TODAY_ASSIGNMENT({questType=202})
local before=updates
ITV2.AdvanceTime(1)
assert(calls.assignment==16 and updates==before+1 and Data.GetAssignment(2).questType==202)
slots[2].status=3
handlers.QUEST_CONTEXT_UPDATED(202,'completed')
ITV2.AdvanceTime(1)
assert(calls.assignment==17 and Data.GetAssignment(2).status==3)

-- 角色資訊跨視窗共用一秒快取；資料到期後才重新讀取。
local infoCalls=0
local function ReadInfo() infoCalls=infoCalls+1; return false end
assert(Data.ReadInfo('buff',ReadInfo)==false)
Data.ReadInfo('buff',ReadInfo)
ITV2.AdvanceTime(999)
Data.ReadInfo('buff',ReadInfo)
assert(infoCalls==1)
ITV2.AdvanceTime(1)
Data.ReadInfo('buff',ReadInfo)
assert(infoCalls==2)

handlers.ENTERED_WORLD()
handlers.ENTERED_WORLD()
ITV2.AdvanceTime(1)
assert(calls.journal==2 and calls.complete==6 and calls.assignment==24, '進場未合併同步')
print('PASS: 初始化全讀、閒置零任務 API、無關事件過濾、事件合併、單 ID reset、挑戰更換／隱藏／共用、角色快取與進場同步')
