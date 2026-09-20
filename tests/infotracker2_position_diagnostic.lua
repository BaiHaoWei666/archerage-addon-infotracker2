-- 缺少座標時保留原始存檔；正常位置不輸出，重複呼叫不洗版。
local function Check(saved, expected, reason, truncated, beforeReport)
    local messages = {}
    ADDON = {LoadData = function() return saved end}
    ITV2 = {
        Text = function(key) return key end,
        Chat = function(message) messages[#messages + 1] = message end,
        GetUiScale = function() return 1 end,
    }
    dofile('quest_data.lua')
    dofile('items.lua')
    dofile('settings.lua')
    ITV2.Settings.Load()
    if beforeReport then beforeReport(saved) end
    local initialized = false
    ITV2.Popout = {Init = function() initialized = true end}
    -- 沿用正式初始化順序，但不重讀存檔，以驗證快照不受後續操作影響。
    local load = ITV2.Settings.Load
    ITV2.Settings.Load = function() end
    dofile('main.lua')
    ITV2.Settings.Load = load
    assert(initialized and messages[#messages] == 'LOADED', '診斷阻斷初始化')
    table.remove(messages)
    local count = #messages
    ITV2.Settings.ReportPositionFallback()
    assert(#messages == count, '診斷重複輸出')
    if expected then
        assert(count >= 2, '缺少位置時未輸出')
        assert(messages[1] == reason, '未區分正常首次使用與異常座標')
        assert((messages[count] == 'POSITION_DATA_TRUNCATED') == (truncated == true), '截短狀態錯誤')
        assert(count <= 28, '診斷訊息過多')
        local parts = {}
        for i = 2, truncated and count - 1 or count do
            assert(#messages[i] < 220, '聊天分段過長')
            assert(not messages[i]:find('[%z\1-\31]'), '聊天訊息包含控制字元')
            parts[#parts + 1] = messages[i]:gsub('^%[ITV2 position %d+/%d+%] ', '')
        end
        assert(table.concat(parts):find(expected, 1, true), '原始資料未保留')
    else
        assert(count == 0, '有效位置不應輸出')
    end
    return ITV2.Settings
end
Check(nil, 'itv2_settings=nil', 'POSITION_DATA_MISSING')
Check('invalid', 'itv2_settings="invalid"', 'POSITION_DATA_INVALID')
Check({}, 'itv2_settings={}', 'POSITION_NOT_SAVED')
Check({popout={}}, '["popout"]={}', 'POSITION_NOT_SAVED')
Check({popout=false}, '["popout"]=false', 'POSITION_DATA_INVALID')
Check({popout={x='bad', y=42, anchor='header'}}, '["x"]="bad"', 'POSITION_DATA_INVALID')
Check({popout={x=42, anchor='header'}, note=string.rep('存档', 100)}, string.rep('存档', 100), 'POSITION_DATA_INVALID')
Check({popout={x='120', y='240', anchor='header'}}, nil)
Check({popout={x=0, y=-42, anchor='header'}}, nil)
local legacy = Check({popout={x=120, y=240}}, nil)
assert(legacy.popoutPosY == 214, '舊版位置遷移不相容')
for _, value in ipairs({math.huge, -math.huge, 0/0}) do
    local settings = Check({popout={x=value, y=42, anchor='header'}}, '["popout"]=', 'POSITION_DATA_INVALID')
    assert(settings.popoutPosX == nil, '非有限座標未排除')
end
Check({popout={x='old', y=42}}, '["x"]="old"', 'POSITION_DATA_INVALID', false, function(saved)
    saved.popout.x = 'changed'
end)
Check({note='line\nbreak\t\0'}, 'line\\010break\\009\\000', 'POSITION_NOT_SAVED')
Check({note=string.rep('存档', 3000), popout={x='bad'}}, 'itv2_settings={["popout"]=', 'POSITION_DATA_INVALID', true)
local cycle = {}; cycle.self = cycle
Check(cycle, '<cycle>', 'POSITION_NOT_SAVED')
local deep = {}; local child = deep
for i=1,20 do child.nested={}; child=child.nested end
Check(deep, '<depth-limit>', 'POSITION_NOT_SAVED', true)
local wide = {}; for i=1,1000 do wide[i]=i end
Check(wide, 'itv2_settings={', 'POSITION_NOT_SAVED', true)
Check({note=string.rep(string.char(128), 5000)}, 'itv2_settings={', 'POSITION_NOT_SAVED', true)
local settings = Check({popout={x=12,y=34,anchor='header'}}, nil)
ADDON.LoadData = function() return nil end
settings.Load()
assert(settings.popoutPosX == nil and settings.popoutPosY == nil, '重新載入沿用過期座標')
print('PASS: 正式位置診斷、原始快照、輸出上限、異常資料防護、初始化與座標相容性')
