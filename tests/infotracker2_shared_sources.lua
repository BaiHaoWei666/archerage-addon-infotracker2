-- 真實來源與共用排程：跨視窗去重、隱藏停止、失敗恢復、收入事件與跨日。
ADDON = { ImportAPI=function() end }
API_TYPE = setmetatable({}, {__index=function() return {id=1} end})
UIEVENT_TYPE = setmetatable({}, {__index=function(_, key) return key end})
TADT_TODAY, TADT_EXPEDITION = 1, 2
local handlers, day, saves = {}, 1, 0
UIParent = {
    SetEventHandler=function(_, key, fn) handlers[key]=fn end,
    GetServerTimeTable=function() return {year=2026,month=9,day=day} end,
}
ADDON.LoadData=function() end
ADDON.ClearData=function() end
ADDON.SaveData=function() saves=saves+1 end
dofile('core.lua')
ITV2.Text=function(key) return key end
ITV2.Chat=function() end
ITV2.CATEGORIES={}
local calls={list=0,detail=0,assignment=0,buff=0}
local slots={}
for i=1,7 do slots[i]={status=1,questType=100+i} end
X2Quest={GetActiveQuestListCount=function() return 0 end}
X2Achievement={GetTodayAssignmentInfo=function(_, kind, slot)
    calls.assignment=calls.assignment+1
    return slots[slot]
end}
local entered, missing, fail = 0, false, false
X2BattleField={
    GetInstanceListByKind=function() calls.list=calls.list+1; return {{type=1},{type=2}} end,
    GetInstanceName=function(_, id) return 'Dungeon '..id end,
    GetDetailInstanceInfo=function()
        calls.detail=calls.detail+1
        if fail then error('temporary API failure') end
        if missing then return nil end
        return {enterCount=entered,maxEnterCount=3}
    end,
}
X2Unit={UnitName=function() return 'test' end, UnitBuffCount=function() calls.buff=calls.buff+1; return 0 end}
dofile('sources/common.lua')
dofile('tracking_data.lua')
dofile('sources/dungeon.lua')
dofile('sources/info.lua')
dofile('sources/income.lua')
local Data=ITV2.TrackingData
Data.Initialize()
Data.RegisterEvents()
local items={DG_1={key='DG_1',index=1},DG_2={key='DG_2',index=2},
    INFO_DAILY={key='INFO_DAILY'},INFO_BLESSING={key='INFO_BLESSING'},INC_GOLD={key='INC_GOLD',field='gold'}}
local function View(category, key) return ITV2.SOURCES[category].View(items[key], {}) end
local displays={}
for _, name in ipairs({'Editor','Popout'}) do
    local display={category='dungeon',keys={'DG_1','DG_2'},updates=0}
    displays[name]=display
    ITV2[name]={
        GetDataDemand=function() return display.category,display.keys end,
        RefreshData=function(changed)
            if display.category and changed[display.category] then
                display.updates=display.updates+1
                for _, key in ipairs(display.keys) do View(display.category,key) end
            end
        end,
    }
end
local function Flush(ms) ITV2.AdvanceTime(ms); ITV2.AdvanceTime(0) end
local function SetPage(category, keys)
    for _, display in pairs(displays) do display.category,display.keys=category,keys end
end
View('dungeon','DG_1'); View('dungeon','DG_2')
View('dungeon','DG_1'); View('dungeon','DG_2')
Flush(0)
assert(calls.list==1 and calls.detail==2,'兩視窗未共用副本清單與詳細資料')
local updates=displays.Editor.updates
Flush(5000)
assert(calls.list==2 and calls.detail==4,'同輪副本查詢重複')
assert(displays.Editor.updates==updates,'副本無變化仍刷新')
entered=1
Flush(5000)
assert(calls.detail==6 and displays.Editor.updates==updates+1 and displays.Popout.updates==updates+1)
assert(View('dungeon','DG_1').text=='Dungeon 1 [1/3]')
SetPage(nil,{})
Flush(60000)
assert(calls.detail==6,'隱藏頁面仍輪詢')
SetPage('dungeon',{'DG_1'})
View('dungeon','DG_1'); Flush(0)
assert(calls.detail==7,'重新開啟未補查過期資料')
Flush(5000)
assert(calls.detail==8,'未追蹤副本仍輪詢')
missing=true
Flush(5000)
assert(View('dungeon','DG_1').status=='neutral')
local before=calls.detail
View('dungeon','DG_1')
assert(calls.detail==before,'缺資料沒有共用快取')
missing=false; fail=true
Flush(5000)
fail=false
Flush(1000)
assert(View('dungeon','DG_1').text=='Dungeon 1 [1/3]','API 失敗後未恢復')

-- 角色每日狀態與挑戰使用同一份七格資料；事件僅重讀失效格。
SetPage('info',{'INFO_DAILY','INFO_BLESSING'})
View('info','INFO_DAILY'); View('info','INFO_BLESSING'); Flush(0)
assert(calls.assignment==7 and calls.buff==1)
Flush(1000)
assert(calls.assignment==7 and calls.buff==2,'角色每日狀態重複查詢挑戰 API')
slots[3].status=2
handlers.UPDATE_TODAY_ASSIGNMENT({questType=103})
Flush(0)
assert(calls.assignment==8 and View('info','INFO_DAILY').status=='complete')
assert(Data.GetAssignment(3).status==2 and calls.assignment==8)

-- 收入資料只累計一次，事件下一幀通知兩視窗；跨日無入帳也會歸零。
SetPage('income',{'INC_GOLD'})
View('income','INC_GOLD'); Flush(0)
updates=displays.Editor.updates
before=saves
Flush(1000)
assert(displays.Editor.updates==updates and saves==before,'閒置收入刷新或重複存檔')
handlers.PLAYER_MONEY(20000); handlers.PLAYER_MONEY(10000)
Flush(0)
assert(displays.Editor.updates==updates+1 and View('income','INC_GOLD').text=='INC_GOLD 3.00GOLD_UNIT')
assert(saves==before+2,'收入未即時保存')
day=2
Flush(1000)
assert(displays.Editor.updates==updates+2 and saves==before+3)
assert(View('income','INC_GOLD').text=='INC_GOLD LESS_THAN_1G')
ITV2.SOURCES.income.Reset(); Flush(0)
assert(displays.Editor.updates==updates+3,'手動重置未通知')
SetPage(nil,{})
before=saves
day=3
Flush(60000)
assert(saves==before,'隱藏收入仍輪詢跨日')
View('income','INC_GOLD')
assert(saves==before+1,'重新顯示未檢查跨日')

-- 防止引擎原地修改 table，並確保 false / nil 快取不重查。
local value={count=1}
local reads=0
local function Read() reads=reads+1; return value end
assert(Data.ReadPolled('custom','value',Read,1000).count==1)
value.count=2
assert(Data.ReadPolled('custom','value',Read,1000).count==1)
Flush(1000)
assert(Data.ReadPolled('custom','value',Read,1000).count==2 and reads==2)
value=nil
Flush(1000)
assert(Data.ReadPolled('custom','value',Read,1000)==nil)
Data.ReadPolled('custom','value',Read,1000)
assert(reads==3)
print('PASS: 副本／資訊跨視窗共用、隱藏停止、按需查詢、變更通知、失敗恢復、收入事件與跨日')
