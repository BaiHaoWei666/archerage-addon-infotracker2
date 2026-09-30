-- 用實際任務組與來源驗證 LEFT_LOADING 當下補查的顯示結果。
local function Start()
    ADDON={ImportAPI=function() end}
    API_TYPE=setmetatable({}, {__index=function() return {id=1} end})
    UIEVENT_TYPE=setmetatable({}, {__index=function(_, key) return key end})
    TADT_TODAY=1
    local events, reads = {}, {}
    local api={completed={[9000221]=true,[8623]=true,[8627]=true,[8631]=true,[8644]=true,[8645]=true},
        journal=0,assignments=0}
    UIParent={SetEventHandler=function(_, event, fn) events[event]=fn end}
    X2Locale={GetLocale=function() return 'zh_cn' end}
    X2Quest={
        IsCompleted=function(_, id)
            reads[id]=(reads[id] or 0)+1
            if api.fail==id then error('API unavailable') end
            return api.completed[id]
        end,
        GetActiveQuestListCount=function() api.journal=api.journal+1; return 2 end,
        GetActiveQuestType=function(_, index) return index==1 and 8619 or 9000225 end,
    }
    X2Achievement={GetTodayAssignmentInfo=function() api.assignments=api.assignments+1 end}
    dofile('core.lua'); dofile('locale.lua'); dofile('quest_data.lua')
    local aegis, gold
    for _, cat in ipairs(ITV2.CATEGORIES) do
        for _, item in ipairs(cat.items) do
            if item.key=='AEGIS' then aegis=item elseif item.key=='HALCY' then gold=item end
        end
    end
    ITV2.CATEGORIES={{key='daily',kind='quest',items={aegis,gold}},
        {key='weekly',kind='quest',items={{ids={8619}}}}}
    dofile('sources/common.lua'); dofile('tracking_data.lua'); dofile('sources/quest.lua')
    local data=ITV2.TrackingData
    data.Initialize(); data.RegisterEvents()
    local view={refreshes=0}
    local function ReadView()
        view.aegis=ITV2.SOURCES.quest.View(aegis,{}).text
        view.gold=ITV2.SOURCES.quest.View(gold,{}).text
    end
    ITV2.Popout={RefreshData=function(changed)
        view.refreshes=view.refreshes+1; view.changed=changed; ReadView()
    end}
    ReadView()
    for id in pairs(reads) do reads[id]=nil end
    api.journal,api.assignments=0,0
    return events,api,reads,data,view,ReadView
end

-- 燭台只有 updated、黃金沒有任務事件；不執行 OnUpdate 也必須立即得到完成結果。
local events,api,reads,data,view,readView=Start()
assert(view.aegis=='烛台 (6/7)' and view.gold=='黄金 (0/2)')
assert(events.ENTERED_WORLD==nil)
events.QUEST_CONTEXT_UPDATED(8619,'updated')
api.completed[8619],api.completed[9000225]=true,true
events.LEFT_LOADING()
assert(data.GetQuest(8619).completed and not data.GetQuest(8619).active)
assert(data.GetQuest(9000225).completed and not data.GetQuest(9000225).active)
readView()
assert(view.aegis=='烛台 (7/7)' and view.gold=='黄金 (1/2)', '當下仍顯示舊進度')
assert(reads[8619]==1 and reads[9000225]==1, '同一 ID 跨分類被重複查詢')
assert(api.journal==0 and api.assignments==0, '補查意外全量初始化')
ITV2.AdvanceTime(0)
assert(view.refreshes==1 and view.changed.daily and view.changed.weekly)

-- 完成狀態不被暫時的 false 清除；單筆錯誤、nil、非布林 true 都不誤判，也不擋住其他任務。
events,api,reads,data,view,readView=Start()
api.completed[8623]=false
api.fail=8619
api.completed[9000225]=true
api.completed[9320]=1
events.LEFT_LOADING()
assert(data.GetQuest(8623).completed and reads[8623]==nil)
assert(not data.GetQuest(8619).completed and data.GetQuest(8619).active)
assert(not data.GetQuest(9320).completed and not data.GetQuest(8620).completed)
assert(data.GetQuest(9000225).completed)
local goldReads=reads[9000225]
api.fail=nil
api.completed[8619]=true
events.LEFT_LOADING()
assert(data.GetQuest(8619).completed, '第二個事件沒有當下重新補查')
assert(reads[9000225]==goldReads, '後續事件重查已完成任務')

-- API 在事件後才改變時，時間流逝不偷偷補查；下一次事件才更新。
events,api,reads,data,view,readView=Start()
events.LEFT_LOADING()
local initialReads=reads[9000225]
api.completed[9000225]=true
ITV2.AdvanceTime(1); ITV2.AdvanceTime(1000); ITV2.AdvanceTime(5000); ITV2.AdvanceTime(60000)
assert(not data.GetQuest(9000225).completed and reads[9000225]==initialReads)
events.LEFT_LOADING()
assert(data.GetQuest(9000225).completed)
api.completed[9000225]=false
events.QUEST_CONTEXT_UPDATED(9000225,'reset')
local active=data.GetQuest(9000225).active
events.LEFT_LOADING()
assert(not data.GetQuest(9000225).completed and data.GetQuest(9000225).active==active)
print('PASS: 不需 OnUpdate 即可補記燭台／黃金、錯誤隔離、已完成不重查、無背景重試及原 reset')
