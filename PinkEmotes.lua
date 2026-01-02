--[[ 💗 PinkWards Emote + Animation System - Optimized ]]

if _G.EmotesGUIRunning then return end
_G.EmotesGUIRunning = true

local Players, HttpService, RunService, UserInputService = game:GetService("Players"), game:GetService("HttpService"), game:GetService("RunService"), game:GetService("UserInputService")
local CoreGui, StarterGui, MarketplaceService, GuiService = game:GetService("CoreGui"), game:GetService("StarterGui"), game:GetService("MarketplaceService"), game:GetService("GuiService")

local player = Players.LocalPlayer
local EMOTE_URL = "https://raw.githubusercontent.com/7yd7/sniper-Emote/refs/heads/test/EmoteSniper.json"
local ANIM_URL = "https://raw.githubusercontent.com/7yd7/sniper-Emote/refs/heads/test/AnimationSniper.json"

local mode, page, perPage, totalPages = "emote", 1, 8, 1
local emotesData, animsData, origEmotes, origAnims = {}, {}, {}, {}
local favEmotes, favAnims = {}, {}
local isLoading, favEnabled, guiCreated = false, false, false
local wheelCache, lastWheelCheck, lastWheelVisible, lastAction = nil, 0, 0, 0

getgenv().lastAnim = getgenv().lastAnim or nil

local C = {
    MED = Color3.fromHex("#FFC8DC"), WHEEL = Color3.fromHex("#FFD9E8"),
    HEART = Color3.fromHex("#FF6B9D"), ANIM = Color3.fromHex("#C8A2C8"),
    WHITE = Color3.new(1,1,1), PLACE = Color3.fromRGB(255,210,230)
}

local Under, Left, Right, Pages, Sep, PageNum, Top, Search, FavBtn, ModeBtn

local function notify(t,c,d) pcall(function() StarterGui:SetCore("SendNotification",{Title=t,Text=c,Duration=d or 4}) end) end
local function getChar() local c=player.Character return c,c and c:FindFirstChild("Humanoid") end

local function getWheel()
    local t=tick()
    if wheelCache and wheelCache.Parent and t-lastWheelCheck<1 then return wheelCache end
    lastWheelCheck=t
    local ok,w=pcall(function() return CoreGui.RobloxGui.EmotesMenu.Children.Main.EmotesWheel end)
    wheelCache=ok and w or nil
    return wheelCache
end

local function saveFile(n,d) if writefile then pcall(function() writefile(n,HttpService:JSONEncode(d)) end) end end
local function loadFile(n) if readfile and isfile and isfile(n) then local ok,r=pcall(function() return HttpService:JSONDecode(readfile(n)) end) return ok and r or {} end return {} end
local function saveLastAnim() if getgenv().lastAnim then saveFile("LastAnimation.json",getgenv().lastAnim) end end
local function loadLastAnim() getgenv().lastAnim=loadFile("LastAnimation.json") if getgenv().lastAnim and not getgenv().lastAnim.id then getgenv().lastAnim=nil end end

local function extractId(url) return string.match(url,"Asset&id=(%d+)") end
local function getEmoteName(id) local ok,info=pcall(function() return MarketplaceService:GetProductInfo(tonumber(id)) end) return ok and info and info.Name or "Emote_"..id end

local function isInFav(id)
    local list=mode=="animation" and favAnims or favEmotes
    for _,v in ipairs(list) do if tostring(v.id)==tostring(id) then return true end end
    return false
end

local function getBundled(id)
    for _,src in ipairs({origAnims,animsData,favAnims}) do
        for _,a in ipairs(src) do if tostring(a.id)==tostring(id) and a.bundledItems then return a.bundledItems end end
    end
end

local function applyTheme()
    local w=getWheel() if not w then return end
    pcall(function() local b=w:FindFirstChild("Back") if b then local bg=b:FindFirstChild("Background") if bg and bg:IsA("Frame") then bg.BackgroundColor3,bg.BackgroundTransparency=C.WHEEL,0.05 end end end)
    if Left then Left.ImageColor3=C.MED end
    if Right then Right.ImageColor3=C.MED end
    if Pages then Pages.TextColor3=C.WHITE end
    if Sep then Sep.TextColor3=C.WHITE end
    if PageNum then PageNum.TextColor3=C.WHITE end
    if Top then Top.BackgroundColor3=C.MED end
    if FavBtn then FavBtn.BackgroundColor3=favEnabled and C.HEART or C.MED end
    if ModeBtn then ModeBtn.BackgroundColor3=mode=="animation" and C.ANIM or C.MED end
end

local function calcPages()
    local favs=mode=="animation" and favAnims or favEmotes
    local list=mode=="animation" and origAnims or origEmotes
    local normal=0
    for _,v in ipairs(list) do if not isInFav(v.id) then normal=normal+1 end end
    local p=0
    if #favs>0 then p=p+math.ceil(#favs/perPage) end
    if normal>0 then p=p+math.ceil(normal/perPage) end
    return math.max(p,1)
end

local function updatePageDisplay() if Pages and PageNum then Pages.Text,PageNum.Text=tostring(totalPages),tostring(page) end end

local function applyAnim(data)
    if not data then return notify("💗 Animation","❌ No data",3) end
    local char=player.Character or player.CharacterAdded:Wait()
    local hum,animate=char:FindFirstChild("Humanoid"),char:FindFirstChild("Animate")
    if not animate or not hum then return notify("💗 Animation","❌ Missing components",3) end
    
    local bundled=data.bundledItems or getBundled(data.id)
    if not bundled then return notify("💗 Animation","❌ No assets for: "..(data.name or data.id),3) end
    
    -- AUTO-SAVE for respawn
    getgenv().lastAnim={id=data.id,name=data.name,bundledItems=bundled}
    saveLastAnim()
    
    for _,track in pairs(hum:GetPlayingAnimationTracks()) do track:Stop() end
    
    for _,assetIds in pairs(bundled) do
        for _,assetId in pairs(assetIds) do
            spawn(function()
                local ok,objs=pcall(function() return game:GetObjects("rbxassetid://"..assetId) end)
                if ok and objs and #objs>0 then
                    local function search(parent,path)
                        for _,child in pairs(parent:GetChildren()) do
                            if child:IsA("Animation") then
                                local parts=(path.."."..child.Name):split(".")
                                if #parts>=2 then
                                    local cat,name=parts[#parts-1],parts[#parts]
                                    local folder=animate:FindFirstChild(cat)
                                    if folder then
                                        local slot=folder:FindFirstChild(name)
                                        if slot then
                                            slot.AnimationId=child.AnimationId
                                            task.wait(0.1)
                                            local anim=Instance.new("Animation")
                                            anim.AnimationId=child.AnimationId
                                            local animator=hum:FindFirstChild("Animator")
                                            if animator then
                                                local t=animator:LoadAnimation(anim)
                                                t.Priority=Enum.AnimationPriority.Action
                                                t:Play() task.wait(0.1) t:Stop()
                                            end
                                        end
                                    end
                                end
                            elseif #child:GetChildren()>0 then search(child,path.."."..child.Name) end
                        end
                    end
                    for _,obj in pairs(objs) do
                        search(obj,obj.Name)
                        obj.Parent=workspace
                        task.delay(1,function() if obj and obj.Parent then obj:Destroy() end end)
                    end
                end
            end)
        end
    end
    notify("💗 Animation","✅ Applied: "..(data.name or "Animation"),3)
end

local function updateFavIcon(img,id,isFav)
    local icon=img:FindFirstChild("FavHeart")
    if isFav then
        if not icon then
            icon=Instance.new("TextLabel")
            icon.Name,icon.Size,icon.Position="FavHeart",UDim2.new(0.22,0,0.22,0),UDim2.new(0.76,0,0.02,0)
            icon.BackgroundTransparency,icon.ZIndex=1,img.ZIndex+10
            icon.Text,icon.TextScaled,icon.Font="💗",true,Enum.Font.SourceSans
            icon.Parent=img
        end
        icon.Visible=true
    elseif icon then icon.Visible=false end
end

local function updateDisplay()
    local char,hum=getChar()
    if not char or not hum or not hum.HumanoidDescription then return end
    
    local desc=hum.HumanoidDescription
    local favs=mode=="animation" and favAnims or favEmotes
    local list=mode=="animation" and origAnims or origEmotes
    local items={}
    
    local favPages=#favs>0 and math.ceil(#favs/perPage) or 0
    local inFavPages=page<=favPages
    
    if inFavPages and #favs>0 then
        local start=(page-1)*perPage+1
        for i=start,math.min(start+perPage-1,#favs) do
            if favs[i] then
                local item={id=tonumber(favs[i].id),name=favs[i].name}
                if mode=="animation" then item.bundledItems=favs[i].bundledItems or getBundled(favs[i].id) end
                table.insert(items,item)
            end
        end
    else
        local normal={}
        for _,v in ipairs(list) do if not isInFav(v.id) then table.insert(normal,v) end end
        local adj=page-favPages
        local start=(adj-1)*perPage+1
        for i=start,math.min(start+perPage-1,#normal) do if normal[i] then table.insert(items,normal[i]) end end
    end
    
    local emoteTable,equipped={},{}
    for _,item in ipairs(items) do emoteTable[item.name]={item.id} table.insert(equipped,item.name) end
    desc:SetEmotes(emoteTable) desc:SetEquippedEmotes(equipped)
    
    task.delay(0.1,function()
        local w=getWheel() if not w then return end
        pcall(function()
            local front=w:FindFirstChild("Front")
            if front then
                local btns=front:FindFirstChild("EmotesButtons")
                if btns then
                    if mode=="animation" then
                        local idx=1
                        for _,child in pairs(btns:GetChildren()) do
                            if child:IsA("ImageLabel") then
                                if idx<=#items then
                                    child.Image="rbxthumb://type=BundleThumbnail&id="..items[idx].id.."&w=420&h=420"
                                    local idVal=child:FindFirstChild("AnimID") or Instance.new("IntValue")
                                    idVal.Name,idVal.Value,idVal.Parent="AnimID",items[idx].id,child
                                    updateFavIcon(child,items[idx].id,isInFav(items[idx].id))
                                    idx=idx+1
                                else
                                    child.Image=""
                                    local idVal=child:FindFirstChild("AnimID") if idVal then idVal:Destroy() end
                                end
                            end
                        end
                    else
                        for _,child in pairs(btns:GetChildren()) do
                            if child:IsA("ImageLabel") and child.Image~="" then
                                local id=extractId(child.Image)
                                if id then updateFavIcon(child,id,isInFav(id)) end
                            end
                        end
                    end
                end
            end
        end)
    end)
end

local function toggleFav(id,name,bundled)
    local list=mode=="animation" and favAnims or favEmotes
    local found,idx=false,0
    for i,v in ipairs(list) do if tostring(v.id)==tostring(id) then found,idx=true,i break end end
    
    if found then table.remove(list,idx) notify("💗 Favorites","Removed: "..name,3)
    else
        local entry={id=id,name=name.." 💗"}
        if mode=="animation" then entry.bundledItems=bundled or getBundled(id) end
        table.insert(list,entry)
        notify("💗 Favorites","Added: "..name,3)
    end
    
    saveFile(mode=="animation" and "FavoriteAnimations.json" or "FavoriteEmotes.json",list)
    totalPages=calcPages() updatePageDisplay() updateDisplay()
end

local function handleSector(index)
    if tick()-lastAction<0.25 then return end
    lastAction=tick() task.wait(0.05)
    
    local favs=mode=="animation" and favAnims or favEmotes
    local list=mode=="animation" and origAnims or origEmotes
    local favPages=#favs>0 and math.ceil(#favs/perPage) or 0
    
    local item
    if page<=favPages and #favs>0 then
        item=favs[(page-1)*perPage+index]
        if item and mode=="animation" and not item.bundledItems then item.bundledItems=getBundled(item.id) end
    else
        local normal={}
        for _,v in ipairs(list) do if not isInFav(v.id) then table.insert(normal,v) end end
        item=normal[(page-favPages-1)*perPage+index]
    end
    
    if not item then return end
    if favEnabled then toggleFav(item.id,item.name,item.bundledItems)
    elseif mode=="animation" then applyAnim(item) end
end

UserInputService.InputBegan:Connect(function(input)
    if mode~="animation" and not favEnabled then return end
    if input.UserInputType~=Enum.UserInputType.MouseButton1 and input.UserInputType~=Enum.UserInputType.Touch then return end
    
    local w=getWheel()
    if not w or (not w.Visible and tick()-lastWheelVisible>0.15) then return end
    
    local pos=Vector2.new(input.Position.X,input.Position.Y)
    local aPos,aSize=w.AbsolutePosition,w.AbsoluteSize
    if pos.X<aPos.X or pos.X>aPos.X+aSize.X or pos.Y<aPos.Y or pos.Y>aPos.Y+aSize.Y then return end
    
    local center=aPos+aSize/2
    local dx,dy=pos.X-center.X,pos.Y-center.Y
    if math.sqrt(dx*dx+dy*dy)<aSize.X*0.1 then return end
    
    local angle=(math.deg(math.atan2(dy,dx))+90+22.5)%360
    handleSector(math.floor(angle/45)+1)
end)

RunService.Heartbeat:Connect(function() pcall(function() local w=getWheel() if w and w.Visible then lastWheelVisible=tick() end end) end)

local function fetchEmotes()
    if isLoading then return end isLoading=true
    local ok,r=pcall(function() return HttpService:JSONDecode(game:HttpGet(EMOTE_URL)) end)
    if ok and r then for _,item in ipairs(r.data or r) do local id=tonumber(item.id) if id and id>0 then table.insert(emotesData,{id=id,name=item.name or "Emote_"..id}) end end end
    origEmotes=emotesData isLoading=false
end

local function fetchAnims()
    if isLoading then return end isLoading=true
    local ok,r=pcall(function() return HttpService:JSONDecode(game:HttpGet(ANIM_URL)) end)
    if ok and r then for _,item in ipairs(r.data or r) do local id=tonumber(item.id) if id and id>0 then table.insert(animsData,{id=id,name=item.name or "Anim_"..id,bundledItems=item.bundledItems}) end end end
    origAnims=animsData isLoading=false
end

local function search(term)
    term=term:lower()
    local source=mode=="animation" and animsData or emotesData
    if term=="" then if mode=="animation" then origAnims=animsData else origEmotes=emotesData end
    else
        local result={}
        local isId=term:match("^%d+$")
        for _,v in ipairs(source) do if (isId and tostring(v.id)==term) or (not isId and v.name:lower():find(term)) then table.insert(result,v) end end
        if mode=="animation" then origAnims=result else origEmotes=result end
    end
    page,totalPages=1,calcPages() updatePageDisplay() updateDisplay()
end

local function prevPage() page=page<=1 and totalPages or page-1 updatePageDisplay() updateDisplay() end
local function nextPage() page=page>=totalPages and 1 or page+1 updatePageDisplay() updateDisplay() end
local function goPage(n) page=math.clamp(n,1,totalPages) updatePageDisplay() updateDisplay() end

local function toggleMode()
    mode=mode=="emote" and "animation" or "emote"
    if mode=="animation" and #animsData==0 then fetchAnims() end
    if Search then Search.Text="" end
    if mode=="animation" then origAnims=animsData else origEmotes=emotesData end
    page,totalPages=1,calcPages() updatePageDisplay() updateDisplay() applyTheme()
    notify("💗 Mode",mode=="animation" and "🎬 Animation" or "💃 Emote",3)
end

local function toggleFavMode() favEnabled=not favEnabled applyTheme() notify("💗 Favorites",favEnabled and "Click to add hearts!" or "OFF",3) end

local function createGUI()
    local w=getWheel() if not w then return false end
    for _,name in ipairs({"Under","Top","Favorite","ModeToggle"}) do local e=w:FindFirstChild(name) if e then e:Destroy() end end
    
    Under=Instance.new("Frame") Under.Name,Under.Parent,Under.BackgroundTransparency="Under",w,1
    Under.Position,Under.Size=UDim2.new(0.13,0,1,0),UDim2.new(0.74,0,0.13,0)
    local layout=Instance.new("UIListLayout") layout.Parent,layout.FillDirection,layout.VerticalAlignment=Under,Enum.FillDirection.Horizontal,Enum.VerticalAlignment.Center
    
    Left=Instance.new("ImageButton") Left.Name,Left.Parent,Left.BackgroundTransparency="Left",Under,1
    Left.Size,Left.Image,Left.ImageColor3=UDim2.new(0.17,0,0.94,0),"rbxassetid://93111945058621",C.MED
    
    Right=Instance.new("ImageButton") Right.Name,Right.Parent,Right.BackgroundTransparency="Right",Under,1
    Right.Size,Right.Image,Right.ImageColor3=UDim2.new(0.17,0,0.94,0),"rbxassetid://107938916240738",C.MED
    
    Pages=Instance.new("TextLabel") Pages.Name,Pages.Parent,Pages.BackgroundTransparency="Pages",Under,1
    Pages.Size,Pages.Font,Pages.Text,Pages.TextColor3,Pages.TextScaled=UDim2.new(0.16,0,0.81,0),Enum.Font.GothamBold,"1",C.WHITE,true
    
    Sep=Instance.new("TextLabel") Sep.Name,Sep.Parent,Sep.BackgroundTransparency="Sep",Under,1
    Sep.Size,Sep.Font,Sep.Text,Sep.TextColor3,Sep.TextScaled=UDim2.new(0.34,0,0.94,0),Enum.Font.GothamBold," --- ",C.WHITE,true
    
    PageNum=Instance.new("TextBox") PageNum.Name,PageNum.Parent,PageNum.BackgroundTransparency="PageNum",Under,1
    PageNum.Size,PageNum.Font,PageNum.Text,PageNum.TextColor3,PageNum.TextScaled=UDim2.new(0.16,0,0.81,0),Enum.Font.GothamBold,"1",C.WHITE,true
    
    Top=Instance.new("Frame") Top.Name,Top.Parent="Top",w
    Top.BackgroundColor3,Top.BackgroundTransparency,Top.Position,Top.Size=C.MED,0.15,UDim2.new(0.13,0,-0.11,0),UDim2.new(0.74,0,0.095,0)
    Instance.new("UICorner",Top).CornerRadius=UDim.new(0,20)
    local tLayout=Instance.new("UIListLayout") tLayout.Parent,tLayout.FillDirection,tLayout.HorizontalAlignment,tLayout.VerticalAlignment=Top,Enum.FillDirection.Horizontal,Enum.HorizontalAlignment.Center,Enum.VerticalAlignment.Center
    
    Search=Instance.new("TextBox") Search.Name,Search.Parent,Search.BackgroundTransparency="Search",Top,1
    Search.Size,Search.Font,Search.PlaceholderText,Search.PlaceholderColor3=UDim2.new(0.87,0,0.82,0),Enum.Font.GothamBold,"Search/ID",C.PLACE
    Search.Text,Search.TextColor3,Search.TextScaled="",C.WHITE,true
    
    FavBtn=Instance.new("ImageButton") FavBtn.Name,FavBtn.Parent="Favorite",w
    FavBtn.BackgroundColor3,FavBtn.BackgroundTransparency,FavBtn.Position,FavBtn.Size=C.MED,0.15,UDim2.new(0.019,0,-0.108,0),UDim2.new(0.0875,0,0.0875,0)
    Instance.new("UICorner",FavBtn).CornerRadius=UDim.new(0,10)
    local favTxt=Instance.new("TextLabel") favTxt.Parent,favTxt.BackgroundTransparency,favTxt.Size,favTxt.Text,favTxt.TextScaled=FavBtn,1,UDim2.new(1,0,1,0),"💗",true
    
    ModeBtn=Instance.new("ImageButton") ModeBtn.Name,ModeBtn.Parent="ModeToggle",w
    ModeBtn.BackgroundColor3,ModeBtn.BackgroundTransparency,ModeBtn.Position,ModeBtn.Size=C.MED,0.15,UDim2.new(0.889,0,-0.108,0),UDim2.new(0.0875,0,0.0875,0)
    Instance.new("UICorner",ModeBtn).CornerRadius=UDim.new(0,10)
    local modeTxt=Instance.new("TextLabel") modeTxt.Parent,modeTxt.BackgroundTransparency,modeTxt.Size,modeTxt.Text,modeTxt.TextScaled=ModeBtn,1,UDim2.new(1,0,1,0),"🎬",true
    
    Left.MouseButton1Click:Connect(prevPage) Right.MouseButton1Click:Connect(nextPage)
    PageNum.FocusLost:Connect(function() goPage(tonumber(PageNum.Text) or page) end)
    Search:GetPropertyChangedSignal("Text"):Connect(function() search(Search.Text) end)
    FavBtn.MouseButton1Click:Connect(toggleFavMode) ModeBtn.MouseButton1Click:Connect(toggleMode)
    
    applyTheme() guiCreated=true return true
end

local function onChar(char)
    local hum=char:WaitForChild("Humanoid")
    -- AUTO-RELOAD on respawn
    if getgenv().lastAnim and getgenv().lastAnim.id then
        task.wait(0.5)
        applyAnim(getgenv().lastAnim)
        notify("💗 Auto-Reload","🔄 Animation restored!",3)
    end
    hum.Died:Connect(function() favEnabled=false end)
end

if player.Character then onChar(player.Character) end

player.CharacterAdded:Connect(function(char)
    favEnabled,wheelCache=false,nil
    onChar(char)
    task.spawn(function()
        task.wait(0.3)
        while not getWheel() do task.wait(0.1) end
        task.wait(0.3)
        if createGUI() then updatePageDisplay() updateDisplay() end
    end)
end)

local frameCount=0
RunService.RenderStepped:Connect(function()
    frameCount=frameCount+1
    if frameCount>=30 then frameCount=0 if not guiCreated then if getWheel() and createGUI() then updatePageDisplay() updateDisplay() end else applyTheme() end end
end)

task.spawn(function()
    while not getWheel() do task.wait(0.1) end
    if createGUI() then
        favEmotes,favAnims=loadFile("FavoriteEmotes.json"),loadFile("FavoriteAnimations.json")
        loadLastAnim()
        fetchEmotes() fetchAnims()
        totalPages=calcPages() updatePageDisplay() updateDisplay()
        notify("💗 PinkWards","Loaded! Press '.' to open",5)
    end
end)

StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Chat,true)

task.spawn(function() while true do pcall(function() if not CoreGui:FindFirstChild("RobloxGui") or not CoreGui.RobloxGui:FindFirstChild("EmotesMenu") then StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.EmotesMenu,true) elseif getWheel() and not getWheel():FindFirstChild("Under") then createGUI() updatePageDisplay() end end) task.wait(1) end end)

if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
    pcall(function()
        local gui=Instance.new("ScreenGui") gui.Name,gui.ResetOnSpawn="EmoteBtn",false
        if syn and syn.protect_gui then syn.protect_gui(gui) gui.Parent=CoreGui elseif gethui then gui.Parent=gethui() else gui.Parent=CoreGui end
        local btn=Instance.new("TextButton") btn.Size,btn.Position=UDim2.new(0,55,0,55),UDim2.new(0,10,0.5,-27)
        btn.BackgroundColor3,btn.BackgroundTransparency,btn.Text,btn.TextSize,btn.TextColor3=C.MED,0.15,"💗",28,C.WHITE
        btn.Parent=gui Instance.new("UICorner",btn).CornerRadius=UDim.new(0,12)
        btn.MouseButton1Click:Connect(function() pcall(function() GuiService:SetEmotesMenuOpen(true) end) end)
    end)
end

print("💗 PinkWards | Auto-Save Enabled | Press '.' to open")
