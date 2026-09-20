-- 依 150% 實機診斷重播座標契約：AddAnchor 的位移可由 GetEffectiveOffset 原值讀回。
local widgets, calls = {}, {}
local function Count(key) calls[key]=(calls[key] or 0)+1 end
local function Widget(name)
    local w={handlers={},visible=true}
    w.style=setmetatable({}, {__index=function(_,method)
        return function(self,value)
            Count('style.'..method)
            if method=='SetShadow' then self.shadow=value end
            if method=='SetFontSize' then self.fontSize=value end
        end
    end})
    setmetatable(w,{__index=function(_,key)
        if string.sub(key,1,4)=='itv2' then return nil end
        if (key=='CreateChildWidget' or key=='CreateChildWidgetByType') then return function(_,_,id) return Widget(id) end end
        if key=='AddAnchor' and name=='itv2PopoutHeader' then
            return function(self,_,_,x,y) self.x=x;self.y=y end
        end
        if key=='GetEffectiveOffset' then return function(self) return self.x,self.y end end
        if key=='CreateDrawable' or key=='CreateColorDrawable' then return function() return Widget() end end
        if key=='SetHandler' then return function(self,event,fn) self.handlers[event]=fn end end
        if key=='Show' then return function(self,value) self.visible=value;Count(key) end end
        if key=='IsVisible' then return function(self) return self.visible end end
        if key=='IsMouseOver' then return function(self) Count(key);return self.over==true end end
        if key=='SetText' then return function(self,text) self.text=text;Count(key) end end
        if key=='SetChecked' then return function(self,value) self.checked=value;Count(key) end end
        return function() Count(key) end
    end})
    if name then widgets[name]=w end
    return w
end

for _,scale in ipairs({1,1.25,1.5}) do
    for _,hasLayoutHelper in ipairs({false,true}) do
        local saved={popout={x=1622.63,y=916.255,anchor='header',coordSpace='effective'}}
        local messages={}
        ADDON={ImportAPI=function()end,ImportObject=function()end,
            LoadData=function()return saved end,ClearData=function()end,
            SaveData=function(_,_,value)saved=value end}
        API_TYPE=setmetatable({}, {__index=function()return {id=1}end})
        OBJECT_TYPE={};ALIGN_CENTER=0;ALIGN_LEFT=1
        CreateEmptyWindow=Widget
        UIParent={GetFontColor=function()return {1,1,1,1}end,GetUIScale=function()return scale end}
        F_LAYOUT=hasLayoutHelper and {CalcDontApplyUIScale=function(value)return value/scale end} or nil
        X2Chat={DispatchChatMessage=function(_,_,message)messages[#messages+1]=message end}
        X2Input={IsShiftKeyDown=function()return true end}
        dofile('core.lua')
        ITV2.Text=function(key)return key end
        dofile('quest_data.lua')
        ITV2.SOURCES={}
        for _,cat in ipairs(ITV2.CATEGORIES)do
            ITV2.SOURCES[cat.kind]={View=function(item)return {text=item.key,status='neutral'}end}
        end
        dofile('items.lua');dofile('settings.lua');dofile('windows/widgets.lua');dofile('windows/popout.lua')
        ITV2.TrackingData={Initialize=function()end,RegisterEvents=function()end}
        dofile('main.lua')
        local header=widgets.itv2PopoutHeader
        local function CheckPosition(x,y)
            assert(math.abs(header.x-x)<0.01 and math.abs(header.y-y)<0.01,
                string.format('scale=%s expected=(%s,%s) actual=(%s,%s)',scale,x,y,header.x,header.y))
        end
        CheckPosition(1622.63,916.255)
        assert(#messages==1 and messages[1]=='LOADED','正確還原仍觸發診斷')
        header.handlers.OnDragStart()
        header.x,header.y=1500,850
        header.handlers.OnDragStop()
        CheckPosition(1500,850)
        assert(saved.popout.x==1500 and saved.popout.y==850,'拖曳存檔座標不一致')
        for i=1,3 do
            dofile('main.lua')
            CheckPosition(1500,850)
        end
        assert(#messages==4,'連續重載產生位置診斷')
    end
end
print('PASS: 100%／125%／150% 位置還原、拖曳存檔及連續重載不累積縮放')
