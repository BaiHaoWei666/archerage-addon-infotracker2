-- 重播縮放座標契約：AddAnchor 接受顯示座標，GetOffset 回傳除以 UI 倍率的座標。
-- 110% 實機診斷：存檔 (1270.36,606.765) 直接錨定後讀回 (1154.88,551.605)。
local widgets, calls = {}, {}
local uiScale = 1
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
            return function(self,_,_,x,y)
                Count('header.AddAnchor')
                self.x=x/uiScale;self.y=y/uiScale
            end
        end
        if key=='GetOffset' then return function(self) return self.x,self.y end end
        if key=='GetEffectiveOffset' then
            return function(self)
                return self.x*uiScale,self.y*uiScale
            end
        end
        if key=='StartMoving' then
            return function(self) Count(key) end
        end
        if key=='EnableDrag' then
            return function(self,enabled) Count(key);self.dragEnabled=enabled end
        end
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

for _,scale in ipairs({1.1,1.2,1,1.25,1.5}) do
    for _,savedCoordSpace in ipairs({'anchor','ui','effective','legacy'}) do
        for _,hasLayoutHelper in ipairs({false,true}) do
            widgets,calls={},{}
            uiScale=scale
            local saved={popout={x=1270.36,y=606.765,anchor='header',
                coordSpace=savedCoordSpace~='legacy' and savedCoordSpace or nil}}
            local initialX,initialY=saved.popout.x,saved.popout.y
            if savedCoordSpace=='effective' or savedCoordSpace=='legacy' then
                initialX,initialY=initialX/scale,initialY/scale
            end
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
            local body=widgets.itv2PopoutWindow
            local function Frame(dt) body.handlers.OnUpdate(body,dt) end
            local function CheckPosition(x,y)
                assert(math.abs(header.x-x)<0.01 and math.abs(header.y-y)<0.01,
                    string.format('scale=%s expected=(%s,%s) actual=(%s,%s)',scale,x,y,header.x,header.y))
            end
            CheckPosition(initialX,initialY)
            assert(#messages==1 and messages[1]=='LOADED','正確還原仍觸發診斷')
            assert(header.dragEnabled==true,'標題列未啟用拖曳')
            local enables=calls.EnableDrag
            for i=1,60 do Frame(16) end
            assert(calls.EnableDrag==enables,'閒置時仍重設拖曳能力')
            header.handlers.OnMouseDown()
            header.handlers.OnMouseUp()
            assert(widgets.itv2PopPageMenu.visible,'一般點擊未開啟分類選單')
            header.handlers.OnMouseDown()
            header.handlers.OnMouseUp()
            assert(not widgets.itv2PopPageMenu.visible,'一般點擊未關閉分類選單')
            local nearEdge={3840/scale-230,2160/scale-297}
            for _,drop in ipairs({{1500.25,850.75},nearEdge,{0,0}}) do
                header.handlers.OnMouseDown()
                assert(header.dragEnabled==true,'左鍵按下未啟用原生拖曳')
                local anchors=calls['header.AddAnchor']
                header.handlers.OnDragStart()
                assert(header.itv2Moving==true,'左鍵拖曳未啟動移動')
                header.x,header.y=drop[1],drop[2]
                Frame(75)
                assert(header.dragEnabled==true,'拖曳途中關閉原生拖曳')
                header.handlers.OnDragStop()
                header.handlers.OnMouseUp()
                assert(not widgets.itv2PopPageMenu.visible,'拖曳放開後誤開啟分類選單')
                CheckPosition(drop[1],drop[2])
                assert(calls['header.AddAnchor']==anchors,'放開拖曳後重新設定錨點')
                assert(saved.popout.x==drop[1] and saved.popout.y==drop[2],'拖曳存檔座標不一致')
                assert(saved.popout.coordSpace=='ui','存檔未標示 UI 座標系')
                local actualX,actualY=ITV2.Popout.GetPosition()
                assert(actualX==drop[1] and actualY==drop[2],'位置讀回與存檔座標系不同')
                for i=1,3 do
                    dofile('main.lua')
                    CheckPosition(drop[1],drop[2])
                end
            end
            assert(#messages==10,'連續重載產生位置診斷')
        end
    end
end
print('PASS: 100%／110%／120%／125%／150% 縮放座標、舊存檔、Shift 拖曳及連續重載')
