if _G.EmotesGUIRunning then return end
_G.EmotesGUIRunning = true

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")
local StarterGui = game:GetService("StarterGui")
local GuiService = game:GetService("GuiService")
local ContextActionService = game:GetService("ContextActionService")

local player = Players.LocalPlayer
local EMOTE_URL = "https://raw.githubusercontent.com/PinkWards/emote-sniper/refs/heads/main/EmoteSniper.json"
local ANIM_URL  = "https://raw.githubusercontent.com/PinkWards/emote-sniper/refs/heads/main/AnimationSniper.json"

local State = {
    mode = "emote", currentPage = 1, itemsPerPage = 60,
    emotesData = {}, animsData = {}, filteredEmotes = {}, filteredAnims = {},
    favEmotes = {}, favAnims = {},
    isLoadingEmotes = false, isLoadingAnims = false,
    favSetVersion = 0, autoReapplyEnabled = false,
    favFileName = "FavoriteEmotes.json", favAnimFileName = "FavoriteAnimation.json",
    favLookupEmote = {}, favLookupAnim = {}, applyingAnim = false,
    cacheDirty = true, cachedCombined = {},
    config = { NotifyEnabled = true, AutoReapplyEnabled = false, CustomAnimSlots = {} }
}

getgenv().lastAnim = getgenv().lastAnim or nil
local ConfigPath = "PinkWards/Config.json"

local ANIM_SLOT_NAMES = {"idle","walk","run","jump","climb","fall","swim","swimidle"}
local validSlotLookup = {}
for _, n in ipairs(ANIM_SLOT_NAMES) do validSlotLookup[n:lower()] = n end

--------------------------------------------------------------------------------
-- Raw JSON parser - keeps IDs as pure strings, never touches tonumber on them
--------------------------------------------------------------------------------
local function parseAnimsFromRaw(rawJson)
    local results = {}
    local pos = 1
    while true do
        -- find each top-level object by looking for "id": <number>
        local s, e, idStr = rawJson:find('"id"%s*:%s*(-?%d+)', pos)
        if not s then break end
        pos = e + 1

        -- item id (this one is small so tonumber is safe)
        local itemId = tonumber(idStr)
        if not itemId then break end

        -- find name
        local _, ne, itemName = rawJson:find('"name"%s*:%s*"([^"]*)"', e)
        if not itemName then break end

        -- find bundledAnimations block
        local baS = rawJson:find('"bundledAnimations"%s*:%s*{', ne)
        if not baS then pos = ne + 1; continue end

        local bOpen = rawJson:find('{', baS)
        if not bOpen then break end

        -- find matching closing brace
        local depth = 0
        local bEnd = bOpen
        for i = bOpen, #rawJson do
            local c = rawJson:sub(i,i)
            if c == '{' then depth = depth + 1
            elseif c == '}' then
                depth = depth - 1
                if depth == 0 then bEnd = i; break end
            end
        end

        local block = rawJson:sub(bOpen, bEnd)
        local bundled = {}

        -- parse each slot key and its animation ids
        -- IMPORTANT: ids are extracted as raw strings to avoid precision loss
        local sp = 1
        while true do
            local _, ke, slotKey = block:find('"([A-Za-z]+)"%s*:%s*%[', sp)
            if not ke then break end
            sp = ke + 1

            local aS = block:find('%[', ke)
            if not aS then break end
            local aE = block:find('%]', aS)
            if not aE then break end

            local slotName = validSlotLookup[slotKey:lower()]
            if slotName then
                local ids = {}
                -- grab each "id": DIGITS as a raw string
                for raw in block:sub(aS, aE):gmatch('"id"%s*:%s*(%d+)') do
                    ids[#ids+1] = raw  -- raw string, never converted to number
                end
                if #ids > 0 then bundled[slotName] = ids end
            end
            sp = aE + 1
        end

        if next(bundled) then
            results[#results+1] = { id = itemId, name = itemName, bundledItems = bundled }
        end
        pos = bEnd + 1
    end
    return results
end

--------------------------------------------------------------------------------
-- Animation application - mirrors the working FE script exactly
--------------------------------------------------------------------------------
local function getChar()   return player.Character end
local function getHum()
    local c = getChar(); return c and c:FindFirstChildOfClass("Humanoid")
end
local function getAnimate()
    local c = getChar(); return c and c:FindFirstChild("Animate")
end

local function stopAllTracks()
    local h = getHum(); if not h then return end
    pcall(function()
        for _, t in ipairs(h:GetPlayingAnimationTracks()) do t:Stop(0) end
    end)
end

local function freeze()
    local c = getChar(); if not c then return end
    local h = getHum()
    if h then pcall(function() h.PlatformStand = true end) end
    for _, p in ipairs(c:GetDescendants()) do
        if p:IsA("BasePart") and not p.Anchored then p.Anchored = true end
    end
end

local function unfreeze()
    local c = getChar(); if not c then return end
    local h = getHum()
    if h then pcall(function() h.PlatformStand = false end) end
    for _, p in ipairs(c:GetDescendants()) do
        if p:IsA("BasePart") and p.Anchored then p.Anchored = false end
    end
end

local function doRefresh(slotName)
    local h = getHum(); if not h then return end
    if slotName == "swim" or slotName == "swimidle" then
        pcall(function()
            h:ChangeState(Enum.HumanoidStateType.GettingUp)
            task.wait(0.1)
            h:ChangeState(Enum.HumanoidStateType.Swimming)
        end)
    elseif slotName == "climb" then
        pcall(function()
            h:ChangeState(Enum.HumanoidStateType.GettingUp)
            task.wait(0.1)
            h:ChangeState(Enum.HumanoidStateType.Climbing)
        end)
    else
        pcall(function() h:ChangeState(Enum.HumanoidStateType.Freefall) end)
    end
end

-- Core setter: directly patches Animation children in the Animate folder slot.
-- Uses "http://www.roblox.com/asset/?id=ID" format exactly like the working script.
-- IDs come in as raw digit strings and are never converted to numbers.
local function setSlotAnimations(slotName, ids)
    local animate = getAnimate(); if not animate then return false end
    local folder = animate:FindFirstChild(slotName)
    if not folder then return false end

    -- collect existing Animation children
    local existing = {}
    for _, ch in ipairs(folder:GetChildren()) do
        if ch:IsA("Animation") then existing[#existing+1] = ch end
    end

    if #existing == 0 then return false end

    -- Set each existing animation child
    -- If bundle has fewer IDs than slots, repeat the last ID
    -- This stops the old animation bleeding through unused slots
    local lastId = ids[#ids]
    for i, animObj in ipairs(existing) do
        local idStr = ids[i] or lastId
        -- Use the same URL format as the working FE script
        animObj.AnimationId = "http://www.roblox.com/asset/?id=" .. idStr
    end

    return true
end

-- Apply an entire bundle across all slots
local function applyBundle(bundledItems)
    freeze()
    task.wait(0.1)
    stopAllTracks()

    -- Disable Animate to force re-read, same pattern as working script
    local animate = getAnimate()
    if animate then
        pcall(function() animate.Enabled = false end)
    end
    task.wait(0.05)

    local applied = 0
    for slotName, ids in pairs(bundledItems) do
        if setSlotAnimations(slotName, ids) then
            applied = applied + 1
        end
    end

    if animate then
        pcall(function() animate.Enabled = true end)
    end
    task.wait(0.05)

    unfreeze()
    task.wait(0.1)
    doRefresh("idle")  -- generic refresh
    return applied
end

-- Apply a single slot
local function applyOneSlot(slotName, ids)
    freeze()
    task.wait(0.1)
    stopAllTracks()

    local animate = getAnimate()
    if animate then pcall(function() animate.Enabled = false end) end
    task.wait(0.05)

    local ok = setSlotAnimations(slotName, ids)

    if animate then pcall(function() animate.Enabled = true end) end
    task.wait(0.05)

    unfreeze()
    task.wait(0.1)
    doRefresh(slotName)
    return ok
end

--------------------------------------------------------------------------------
-- Config / File helpers
--------------------------------------------------------------------------------
local function ensureFolder()
    if isfolder and not isfolder("PinkWards") then
        pcall(function() makefolder("PinkWards") end)
    end
end

local function SaveConfig()
    if not writefile then return end
    ensureFolder()
    pcall(function() writefile(ConfigPath, HttpService:JSONEncode(State.config)) end)
end

local function LoadConfig()
    if isfile and isfile(ConfigPath) then
        local ok, data = pcall(function() return HttpService:JSONDecode(readfile(ConfigPath)) end)
        if ok and data then for k,v in pairs(data) do State.config[k] = v end end
    end
    State.autoReapplyEnabled = State.config.AutoReapplyEnabled or false
    if not State.config.CustomAnimSlots then State.config.CustomAnimSlots = {} end
end

local function notify(title, content, duration)
    if not State.config.NotifyEnabled then return end
    pcall(function()
        StarterGui:SetCore("SendNotification",{Title=title or "PinkWards",Text=content or "",Duration=duration or 4})
    end)
end

local function saveFile(name, data)
    if not writefile then return end
    ensureFolder()
    pcall(function() writefile("PinkWards/"..name, HttpService:JSONEncode(data)) end)
end

local function loadFile(name)
    for _, path in ipairs({"PinkWards/"..name, name}) do
        if readfile and isfile then
            local exists = false
            pcall(function() exists = isfile(path) end)
            if exists then
                local ok, res = pcall(function() return HttpService:JSONDecode(readfile(path)) end)
                if ok and res and type(res) == "table" then
                    if res.data and type(res.data)=="table" then return res.data end
                    if res.favorites and type(res.favorites)=="table" then return res.favorites end
                    return res
                end
            end
        end
    end
    return {}
end

local function saveLastAnim()
    if getgenv().lastAnim then saveFile("LastAnimation.json", getgenv().lastAnim) end
end

local function loadLastAnim()
    local data = loadFile("LastAnimation.json")
    if data and data.id then
        getgenv().lastAnim = {id=data.id, name=data.name, bundledItems=data.bundledItems}
    end
end

local function rebuildFavLookup()
    State.favLookupEmote = {}
    for _,v in ipairs(State.favEmotes) do State.favLookupEmote[tostring(v.id)] = true end
    State.favLookupAnim = {}
    for _,v in ipairs(State.favAnims) do State.favLookupAnim[tostring(v.id)] = true end
    State.favSetVersion = State.favSetVersion + 1
end

local function playEmote(name, id)
    local c = getChar(); if not c then return end
    local h = getHum()
    local desc = h and h:FindFirstChildOfClass("HumanoidDescription")
    if not h or not desc then return end
    if h.RigType ~= Enum.HumanoidRigType.R6 then
        task.spawn(function()
            pcall(function() desc:AddEmote(name, id) end)
            pcall(function() h:PlayEmoteAndGetAnimTrackById(id) end)
        end)
    else notify("R6?","You gotta be R15 dude",3) end
end

local function applyAnim(data)
    if not data then return end
    if State.applyingAnim then return end
    State.applyingAnim = true
    task.spawn(function()
        local bundled = data.bundledItems
        if not bundled or not next(bundled) then
            notify("Animation","No data for: "..tostring(data.name),3)
            State.applyingAnim = false; return
        end
        getgenv().lastAnim = {id=data.id, name=data.name, bundledItems=bundled}
        saveLastAnim()
        notify("Animation","Applying: "..tostring(data.name).."...",2)
        local applied = applyBundle(bundled)
        notify("Animation","Applied: "..tostring(data.name).." ("..applied.." slots)",3)
        State.applyingAnim = false
    end)
end

local function searchItems(term)
    term = term:lower()
    local source = State.mode=="animation" and State.animsData or State.emotesData
    if term == "" then
        if State.mode=="animation" then State.filteredAnims = State.animsData
        else State.filteredEmotes = State.emotesData end
    else
        local result = {}
        local isId = term:match("^-?%d+$")
        if isId then
            for i=1,#source do if tostring(source[i].id)==term then result[#result+1]=source[i]; break end end
        else
            for i=1,#source do if source[i].name:lower():find(term,1,true) then result[#result+1]=source[i] end end
        end
        if State.mode=="animation" then State.filteredAnims=result else State.filteredEmotes=result end
    end
    State.currentPage=1; State.cacheDirty=true
end

local function fetchEmotes()
    if State.isLoadingEmotes then return end
    State.isLoadingEmotes = true
    local ok, res = pcall(function() return HttpService:JSONDecode(game:HttpGet(EMOTE_URL)) end)
    if ok and res then
        local raw = res.data or res; local data = {}
        for i=1,#raw do
            local it = raw[i]; local id = tonumber(it.id)
            if id and id ~= 0 then data[#data+1]={id=id,name=it.name or ("Emote_"..id)} end
        end
        State.emotesData=data; State.filteredEmotes=data
    end
    State.isLoadingEmotes=false; State.cacheDirty=true
end

local function fetchAnims()
    if State.isLoadingAnims then return end
    State.isLoadingAnims = true
    -- fetch raw string and parse ourselves to preserve large IDs
    local ok, raw = pcall(function() return game:HttpGet(ANIM_URL) end)
    if ok and raw then
        local parsed = parseAnimsFromRaw(raw)
        State.animsData=parsed; State.filteredAnims=parsed
    end
    State.isLoadingAnims=false; State.cacheDirty=true
end

function toggleFav(id, name, bundledItems)
    local list = State.mode=="animation" and State.favAnims or State.favEmotes
    local found, idx = false, 0
    for i,v in ipairs(list) do if tostring(v.id)==tostring(id) then found,idx=true,i; break end end
    if found then table.remove(list,idx); notify("Favorites","Removed: "..name,3)
    else
        local e={id=id,name=name}
        if State.mode=="animation" then e.bundledItems=bundledItems end
        table.insert(list,e); notify("Favorites","Added: "..name,3)
    end
    saveFile(State.mode=="animation" and State.favAnimFileName or State.favFileName, list)
    rebuildFavLookup(); State.cacheDirty=true; refreshGrid()
end

--------------------------------------------------------------------------------
-- Custom slots
--------------------------------------------------------------------------------
local function applyAllCustomSlots()
    if not State.config.CustomAnimSlots or not next(State.config.CustomAnimSlots) then
        notify("Custom Anim","No custom slots configured",3); return end
    if State.applyingAnim then notify("Custom Anim","Already applying...",3); return end
    State.applyingAnim = true
    task.spawn(function()
        if not getChar() then State.applyingAnim=false; return end
        notify("Custom Anim","Applying all custom slots...",2)
        local merged = {}
        for slotName, info in pairs(State.config.CustomAnimSlots) do
            if type(info)=="table" and info.id then
                for _,a in ipairs(State.animsData) do
                    if tostring(a.id)==tostring(info.id) and a.bundledItems and a.bundledItems[slotName] then
                        merged[slotName] = a.bundledItems[slotName]; break
                    end
                end
            end
        end
        if next(merged) then
            local applied = applyBundle(merged)
            notify("Custom Anim","Applied ("..applied.." slots)",3)
        else notify("Custom Anim","Could not find animation data",3) end
        State.applyingAnim=false
    end)
end

local function applySlotFromBundle(slotName, bundleData)
    if not bundleData or not bundleData.bundledItems then return false end
    local ids = bundleData.bundledItems[slotName]
    if not ids or #ids==0 then return false end
    local ok = applyOneSlot(slotName, ids)
    if ok then
        State.config.CustomAnimSlots[slotName]={id=bundleData.id,name=bundleData.name}
        SaveConfig()
    end
    return ok
end

local function reapplyAll()
    if not getChar() then return end
    local hc = State.config.CustomAnimSlots and next(State.config.CustomAnimSlots)
    if hc then applyAllCustomSlots()
    elseif getgenv().lastAnim and getgenv().lastAnim.bundledItems then applyAnim(getgenv().lastAnim) end
end

--------------------------------------------------------------------------------
-- GUI
--------------------------------------------------------------------------------
local FavoriteOff = "rbxassetid://10651060677"
local FavoriteOn  = "rbxassetid://10651061109"

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name="Emotes"; ScreenGui.DisplayOrder=2
ScreenGui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling
ScreenGui.ResetOnSpawn=false; ScreenGui.Enabled=false

local hiddenUI = gethui or get_hidden_gui
if hiddenUI then ScreenGui.Parent=hiddenUI()
else pcall(function() syn.protect_gui(ScreenGui) end); ScreenGui.Parent=CoreGui end

local Corner = Instance.new("UICorner"); Corner.CornerRadius=UDim.new(0,6)

local BackFrame = Instance.new("Frame")
BackFrame.Size=UDim2.new(0.58,0,0.72,0); BackFrame.AnchorPoint=Vector2.new(0.5,0.5)
BackFrame.Position=UDim2.new(0.5,0,0.5,0); BackFrame.BackgroundTransparency=1
BackFrame.BorderSizePixel=0; BackFrame.Parent=ScreenGui

local Frame = Instance.new("ScrollingFrame")
Frame.Size=UDim2.new(1,0,0.82,0); Frame.CanvasSize=UDim2.new(0,0,0,0)
Frame.AutomaticCanvasSize=Enum.AutomaticSize.Y; Frame.ScrollingDirection=Enum.ScrollingDirection.Y
Frame.AnchorPoint=Vector2.new(0.5,0); Frame.Position=UDim2.new(0.5,0,0,0)
Frame.BackgroundTransparency=1; Frame.ScrollBarThickness=4
Frame.BorderSizePixel=0; Frame.Parent=BackFrame

local FramePadding=Instance.new("UIPadding",Frame)
FramePadding.PaddingLeft=UDim.new(0,5); FramePadding.PaddingRight=UDim.new(0,8)
FramePadding.PaddingTop=UDim.new(0,5)

local Grid=Instance.new("UIGridLayout")
Grid.CellSize=UDim2.new(0,75,0,75); Grid.CellPadding=UDim2.new(0,5,0,5)
Grid.SortOrder=Enum.SortOrder.LayoutOrder; Grid.Parent=Frame

local PageFrame=Instance.new("Frame")
PageFrame.BackgroundTransparency=1; PageFrame.Size=UDim2.new(1,0,0.07,0)
PageFrame.Position=UDim2.new(0,0,0.84,0); PageFrame.BorderSizePixel=0; PageFrame.Parent=BackFrame

local PageLeft=Instance.new("TextButton")
PageLeft.BorderSizePixel=0; PageLeft.AnchorPoint=Vector2.new(0,0.5)
PageLeft.Position=UDim2.new(0.3,0,0.5,0); PageLeft.Size=UDim2.new(0.08,0,0.85,0)
PageLeft.TextScaled=true; PageLeft.TextColor3=Color3.new(1,1,1)
PageLeft.Font=Enum.Font.GothamBold; PageLeft.BackgroundColor3=Color3.new(0,0,0)
PageLeft.BackgroundTransparency=0.3; PageLeft.Text="<"
Corner:Clone().Parent=PageLeft; PageLeft.Parent=PageFrame

local PageLabel=Instance.new("TextBox")
PageLabel.BackgroundTransparency=1; PageLabel.AnchorPoint=Vector2.new(0.5,0.5)
PageLabel.Position=UDim2.new(0.5,0,0.5,0); PageLabel.Size=UDim2.new(0.22,0,0.85,0)
PageLabel.TextScaled=true; PageLabel.Font=Enum.Font.GothamBold
PageLabel.TextColor3=Color3.new(1,1,1); PageLabel.Text="1 / 1"
PageLabel.ClearTextOnFocus=false; PageLabel.BorderSizePixel=0; PageLabel.Parent=PageFrame

local PageRight=Instance.new("TextButton")
PageRight.BorderSizePixel=0; PageRight.AnchorPoint=Vector2.new(1,0.5)
PageRight.Position=UDim2.new(0.7,0,0.5,0); PageRight.Size=UDim2.new(0.08,0,0.85,0)
PageRight.TextScaled=true; PageRight.TextColor3=Color3.new(1,1,1)
PageRight.Font=Enum.Font.GothamBold; PageRight.BackgroundColor3=Color3.new(0,0,0)
PageRight.BackgroundTransparency=0.3; PageRight.Text=">"
Corner:Clone().Parent=PageRight; PageRight.Parent=PageFrame

local EmoteName=Instance.new("TextLabel")
EmoteName.TextScaled=true; EmoteName.AnchorPoint=Vector2.new(0.5,0.5)
EmoteName.Position=UDim2.new(0.5,0,0.95,0); EmoteName.Size=UDim2.new(0.65,0,0.055,0)
EmoteName.BackgroundColor3=Color3.fromRGB(30,30,30); EmoteName.TextColor3=Color3.new(1,1,1)
EmoteName.Font=Enum.Font.GothamBold; EmoteName.BorderSizePixel=0
EmoteName.Text="Select an Emote"; EmoteName.Parent=BackFrame
Corner:Clone().Parent=EmoteName

local TopBar=Instance.new("Frame")
TopBar.BackgroundTransparency=1; TopBar.Size=UDim2.new(1,0,0.07,0)
TopBar.Position=UDim2.new(0,0,-0.09,0); TopBar.BorderSizePixel=0; TopBar.Parent=BackFrame

local function mkBtn(ax,xp,xs,txt,par)
    local b=Instance.new("TextButton")
    b.BorderSizePixel=0; b.AnchorPoint=Vector2.new(ax,0.5)
    b.Position=UDim2.new(xp,0,0.5,0); b.Size=UDim2.new(xs,0,0.9,0)
    b.TextScaled=true; b.TextColor3=Color3.new(1,1,1)
    b.Font=Enum.Font.GothamBold; b.BackgroundColor3=Color3.new(0,0,0)
    b.BackgroundTransparency=0.3; b.Text=txt
    Corner:Clone().Parent=b; b.Parent=par; return b
end

local CloseButton   = mkBtn(0,0,    0.11,"Close",TopBar)
local ModeButton    = mkBtn(0,0.43, 0.11,"EMO",  TopBar)
local AutoButton    = mkBtn(0,0.55, 0.12,"RE",   TopBar)
local CustomAnimBtn = mkBtn(0,0.68, 0.11,"CUS",  TopBar)
local SortButton    = mkBtn(1,1,    0.13,"Sort", TopBar)

local SearchBar=Instance.new("TextBox")
SearchBar.BorderSizePixel=0; SearchBar.AnchorPoint=Vector2.new(0,0.5)
SearchBar.Position=UDim2.new(0.12,0,0.5,0); SearchBar.Size=UDim2.new(0.30,0,0.9,0)
SearchBar.TextScaled=true; SearchBar.PlaceholderText="Search..."
SearchBar.Font=Enum.Font.Gotham; SearchBar.PlaceholderColor3=Color3.fromRGB(150,150,150)
SearchBar.TextColor3=Color3.new(1,1,1); SearchBar.BackgroundColor3=Color3.new(0,0,0)
SearchBar.BackgroundTransparency=0.3
Corner:Clone().Parent=SearchBar; SearchBar.Parent=TopBar

local SortFrame=Instance.new("Frame")
SortFrame.Visible=false; SortFrame.BorderSizePixel=0
SortFrame.AnchorPoint=Vector2.new(1,0); SortFrame.Position=UDim2.new(1,0,0.01,0)
SortFrame.Size=UDim2.new(0.3,0,0,0); SortFrame.AutomaticSize=Enum.AutomaticSize.Y
SortFrame.BackgroundColor3=Color3.fromRGB(20,20,20); SortFrame.BackgroundTransparency=0.1
SortFrame.ZIndex=100; Corner:Clone().Parent=SortFrame; SortFrame.Parent=BackFrame

local sll=Instance.new("UIListLayout",SortFrame); sll.Padding=UDim.new(0.02,0)
sll.HorizontalAlignment=Enum.HorizontalAlignment.Center; sll.SortOrder=Enum.SortOrder.LayoutOrder
local spad=Instance.new("UIPadding",SortFrame)
spad.PaddingTop=UDim.new(0,4); spad.PaddingBottom=UDim.new(0,4)

local CurrentSort="favfirst"
local function createsort(order,text,sort)
    local s=Instance.new("TextButton")
    s.Size=UDim2.new(0.94,0,0,28); s.BackgroundColor3=Color3.fromRGB(30,30,30)
    s.LayoutOrder=order; s.TextColor3=Color3.new(1,1,1); s.Text=text
    s.Font=Enum.Font.GothamBold; s.TextSize=13; s.BorderSizePixel=0; s.ZIndex=101
    Corner:Clone().Parent=s; s.Parent=SortFrame
    s.MouseButton1Click:Connect(function()
        SortFrame.Visible=false; CurrentSort=sort
        State.currentPage=1; State.cacheDirty=true; refreshGrid()
    end)
end
createsort(1,"Favorites First","favfirst")
createsort(2,"A - Z","az")
createsort(3,"Z - A","za")

local buttonPool={}; local btnDataMap={}
local function ensurePoolSize(count)
    while #buttonPool<count do
        local i=#buttonPool+1
        local btn=Instance.new("ImageButton")
        btn.Name="PoolBtn_"..i; btn.BackgroundColor3=Color3.fromRGB(0,0,0)
        btn.BackgroundTransparency=0.5; btn.BorderSizePixel=0; btn.Visible=false
        Instance.new("UICorner",btn).CornerRadius=UDim.new(0,6)
        local fav=Instance.new("ImageButton")
        fav.Name="favorite"; fav.Image=FavoriteOff
        fav.AnchorPoint=Vector2.new(0.5,0.5); fav.Size=UDim2.new(0.32,0,0.32,0)
        fav.Position=UDim2.new(0.88,0,0.88,0); fav.BorderSizePixel=0
        fav.BackgroundTransparency=1; fav.Parent=btn
        btn.MouseButton1Click:Connect(function()
            local item=btnDataMap[btn]
            if item then
                if State.mode=="animation" then applyAnim(item.data)
                else task.spawn(playEmote,item.data.name,item.data.id) end
                ScreenGui.Enabled=false
            end
        end)
        fav.MouseButton1Click:Connect(function()
            local item=btnDataMap[btn]
            if item then toggleFav(item.data.id,item.data.name,item.data.bundledItems) end
        end)
        btn.MouseEnter:Connect(function()
            local item=btnDataMap[btn]; if item then EmoteName.Text=item.data.name end
        end)
        btn.Parent=Frame; buttonPool[i]=btn
    end
end
ensurePoolSize(60)

local function getItemsPerPage()
    local aX,aY=Frame.AbsoluteSize.X,Frame.AbsoluteSize.Y
    if aX>0 and aY>0 then return math.max(1,math.floor((aX-8)/80)*math.floor(aY/80)) end
    return 60
end

function refreshGrid()
    State.itemsPerPage=getItemsPerPage(); ensurePoolSize(State.itemsPerPage)
    if State.cacheDirty then
        local list=State.mode=="animation" and State.filteredAnims or State.filteredEmotes
        local favs=State.mode=="animation" and State.favAnims or State.favEmotes
        local favLookup=State.mode=="animation" and State.favLookupAnim or State.favLookupEmote
        local normalList={}
        for i=1,#list do if not favLookup[tostring(list[i].id)] then normalList[#normalList+1]=list[i] end end
        if CurrentSort=="az" then
            table.sort(normalList,function(a,b) return a.name:lower()<b.name:lower() end)
            table.sort(favs,function(a,b) return a.name:lower()<b.name:lower() end)
        elseif CurrentSort=="za" then
            table.sort(normalList,function(a,b) return a.name:lower()>b.name:lower() end)
            table.sort(favs,function(a,b) return a.name:lower()>b.name:lower() end)
        end
        State.cachedCombined={}
        for _,v in ipairs(favs) do State.cachedCombined[#State.cachedCombined+1]={data=v,isFav=true} end
        for _,v in ipairs(normalList) do State.cachedCombined[#State.cachedCombined+1]={data=v,isFav=false} end
        State.cacheDirty=false
    end
    local combined=State.cachedCombined
    local totalPages=math.max(1,math.ceil(#combined/State.itemsPerPage))
    if State.currentPage>totalPages then State.currentPage=totalPages end
    if State.currentPage<1 then State.currentPage=1 end
    if not PageLabel:IsFocused() then PageLabel.Text=State.currentPage.." / "..totalPages end
    local startIdx=(State.currentPage-1)*State.itemsPerPage+1
    local endIdx=math.min(startIdx+State.itemsPerPage-1,#combined)
    for i=1,#buttonPool do
        local btn=buttonPool[i]; local itemIdx=startIdx+i-1
        if itemIdx<=endIdx and combined[itemIdx] then
            local item=combined[itemIdx]; btnDataMap[btn]=item; btn.Visible=true
            if State.mode=="animation" then
                btn.Image=item.data.id>0
                    and ("rbxthumb://type=BundleThumbnail&id="..item.data.id.."&w=420&h=420")
                    or  ("rbxthumb://type=Asset&id="..math.abs(item.data.id).."&w=150&h=150")
            else
                btn.Image="rbxthumb://type=Asset&id="..item.data.id.."&w=150&h=150"
            end
            btn:FindFirstChild("favorite").Image=item.isFav and FavoriteOn or FavoriteOff
        else btn.Visible=false; btnDataMap[btn]=nil end
    end
end

Frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
    local n=getItemsPerPage()
    if n~=State.itemsPerPage then State.itemsPerPage=n; if ScreenGui.Enabled then refreshGrid() end end
end)
PageLeft.MouseButton1Click:Connect(function()
    local t=math.max(1,math.ceil(#State.cachedCombined/State.itemsPerPage)); if t<=1 then return end
    State.currentPage=State.currentPage>1 and State.currentPage-1 or t; refreshGrid()
end)
PageRight.MouseButton1Click:Connect(function()
    local t=math.max(1,math.ceil(#State.cachedCombined/State.itemsPerPage)); if t<=1 then return end
    State.currentPage=State.currentPage<t and State.currentPage+1 or 1; refreshGrid()
end)
PageLabel.Focused:Connect(function()
    PageLabel.Text=tostring(State.currentPage)
    PageLabel.CursorPosition=1; PageLabel.SelectionStart=#PageLabel.Text+1
end)
PageLabel.FocusLost:Connect(function()
    local n=tonumber(PageLabel.Text:gsub("%s",""))
    if n then
        local t=math.max(1,math.ceil(#State.cachedCombined/State.itemsPerPage))
        State.currentPage=math.clamp(math.floor(n),1,t)
    end
    refreshGrid()
end)

--------------------------------------------------------------------------------
-- Custom Anim Editor
--------------------------------------------------------------------------------
local customFrame=nil
local function closeCustomAnimEditor()
    if customFrame then customFrame.Visible=false end; BackFrame.Visible=true
end

local function openCustomAnimEditor()
    if customFrame and customFrame.Visible then closeCustomAnimEditor(); return end
    if #State.animsData==0 then
        notify("Custom Anim","Loading animations first...",3)
        task.spawn(function() fetchAnims(); task.wait(1); openCustomAnimEditor() end); return
    end
    BackFrame.Visible=false
    if not customFrame then
        customFrame=Instance.new("Frame",ScreenGui)
        customFrame.Name="CustomAnimFrame"; customFrame.BackgroundColor3=Color3.new(0,0,0)
        customFrame.BackgroundTransparency=0.2; customFrame.BorderSizePixel=0
        customFrame.Size=UDim2.new(0.42,0,0.58,0); customFrame.AnchorPoint=Vector2.new(0.5,0.5)
        customFrame.Position=UDim2.new(0.5,0,0.5,0); customFrame.ClipsDescendants=true
        customFrame.ZIndex=50; Instance.new("UICorner",customFrame).CornerRadius=UDim.new(0,10)

        local titleBar=Instance.new("Frame",customFrame)
        titleBar.BackgroundTransparency=1; titleBar.Size=UDim2.new(1,0,0,38); titleBar.ZIndex=51

        local titleLabel=Instance.new("TextLabel",titleBar)
        titleLabel.BackgroundTransparency=1; titleLabel.Size=UDim2.new(0.8,0,1,0)
        titleLabel.Position=UDim2.fromOffset(10,0); titleLabel.Font=Enum.Font.GothamBold
        titleLabel.Text="Custom Animation Slots"; titleLabel.TextColor3=Color3.fromRGB(255,255,255)
        titleLabel.TextSize=14; titleLabel.TextXAlignment=Enum.TextXAlignment.Left; titleLabel.ZIndex=52

        local closeBtn=Instance.new("TextButton",titleBar)
        closeBtn.BackgroundTransparency=1; closeBtn.Size=UDim2.fromOffset(38,38)
        closeBtn.Position=UDim2.new(1,-38,0,0); closeBtn.Font=Enum.Font.GothamBold
        closeBtn.Text="X"; closeBtn.TextColor3=Color3.fromRGB(200,200,200)
        closeBtn.TextSize=16; closeBtn.ZIndex=52
        closeBtn.MouseButton1Click:Connect(closeCustomAnimEditor)

        local contentArea=Instance.new("Frame",customFrame)
        contentArea.BackgroundTransparency=1; contentArea.Position=UDim2.fromOffset(0,40)
        contentArea.Size=UDim2.new(1,0,1,-40); contentArea.ZIndex=51; contentArea.ClipsDescendants=true

        local slotPage=Instance.new("Frame",contentArea)
        slotPage.Name="SlotPage"; slotPage.BackgroundTransparency=1
        slotPage.Size=UDim2.fromScale(1,1); slotPage.ZIndex=52; slotPage.Visible=true

        local scrollFrame=Instance.new("ScrollingFrame",slotPage)
        scrollFrame.BackgroundTransparency=1; scrollFrame.Size=UDim2.new(1,0,1,-44)
        scrollFrame.ScrollBarThickness=4; scrollFrame.CanvasSize=UDim2.fromOffset(0,0)
        scrollFrame.AutomaticCanvasSize=Enum.AutomaticSize.Y; scrollFrame.BorderSizePixel=0
        scrollFrame.ZIndex=53
        local ll=Instance.new("UIListLayout",scrollFrame)
        ll.Padding=UDim.new(0,4); ll.SortOrder=Enum.SortOrder.LayoutOrder
        local pu=Instance.new("UIPadding",scrollFrame)
        pu.PaddingLeft=UDim.new(0,8); pu.PaddingRight=UDim.new(0,8); pu.PaddingTop=UDim.new(0,4)

        local pickerPage=Instance.new("Frame",contentArea)
        pickerPage.Name="PickerPage"; pickerPage.BackgroundTransparency=1
        pickerPage.Size=UDim2.fromScale(1,1); pickerPage.ZIndex=52; pickerPage.Visible=false

        local pickerTitle=Instance.new("TextLabel",pickerPage)
        pickerTitle.BackgroundTransparency=1; pickerTitle.Size=UDim2.new(1,-60,0,28)
        pickerTitle.Position=UDim2.fromOffset(8,2); pickerTitle.Font=Enum.Font.GothamBold
        pickerTitle.Text="Pick bundle for: idle"; pickerTitle.TextColor3=Color3.fromRGB(255,255,255)
        pickerTitle.TextSize=12; pickerTitle.TextXAlignment=Enum.TextXAlignment.Left; pickerTitle.ZIndex=53

        local pickerBack=Instance.new("TextButton",pickerPage)
        pickerBack.BackgroundColor3=Color3.new(0,0,0); pickerBack.BackgroundTransparency=0.3
        pickerBack.Size=UDim2.fromOffset(50,24); pickerBack.Position=UDim2.new(1,-58,0,4)
        pickerBack.Font=Enum.Font.GothamBold; pickerBack.Text="Back"
        pickerBack.TextColor3=Color3.fromRGB(220,220,220); pickerBack.TextSize=11
        pickerBack.BorderSizePixel=0; pickerBack.ZIndex=53
        Instance.new("UICorner",pickerBack).CornerRadius=UDim.new(0,4)
        pickerBack.MouseButton1Click:Connect(function() pickerPage.Visible=false; slotPage.Visible=true end)

        local pickerSearch=Instance.new("TextBox",pickerPage)
        pickerSearch.BackgroundColor3=Color3.new(0,0,0); pickerSearch.BackgroundTransparency=0.3
        pickerSearch.Position=UDim2.fromOffset(5,32); pickerSearch.Size=UDim2.new(1,-10,0,26)
        pickerSearch.Font=Enum.Font.Gotham; pickerSearch.PlaceholderText="Search bundles..."
        pickerSearch.PlaceholderColor3=Color3.fromRGB(100,100,100)
        pickerSearch.Text=""; pickerSearch.TextColor3=Color3.fromRGB(255,255,255)
        pickerSearch.TextSize=12; pickerSearch.ClearTextOnFocus=false
        pickerSearch.BorderSizePixel=0; pickerSearch.ZIndex=53
        Instance.new("UICorner",pickerSearch).CornerRadius=UDim.new(0,4)

        local pickerScroll=Instance.new("ScrollingFrame",pickerPage)
        pickerScroll.BackgroundTransparency=1; pickerScroll.Position=UDim2.fromOffset(0,62)
        pickerScroll.Size=UDim2.new(1,0,1,-62); pickerScroll.ScrollBarThickness=4
        pickerScroll.CanvasSize=UDim2.fromOffset(0,0); pickerScroll.AutomaticCanvasSize=Enum.AutomaticSize.Y
        pickerScroll.BorderSizePixel=0; pickerScroll.ZIndex=53
        local pll=Instance.new("UIListLayout",pickerScroll)
        pll.Padding=UDim.new(0,2); pll.SortOrder=Enum.SortOrder.LayoutOrder

        local curPickSlot=""; local pickApplying=false

        local function populatePicker(filter)
            for _,ch in pairs(pickerScroll:GetChildren()) do if ch:IsA("TextButton") then ch:Destroy() end end
            filter=(filter or ""):lower(); local matches={}
            for i=1,#State.animsData do
                if #matches>=50 then break end
                local it=State.animsData[i]
                if filter=="" or it.name:lower():find(filter,1,true) then matches[#matches+1]=it end
            end
            for _,item in ipairs(matches) do
                local b=Instance.new("TextButton")
                b.BackgroundColor3=Color3.new(0,0,0); b.BackgroundTransparency=0.4
                b.Size=UDim2.new(1,-4,0,30); b.Font=Enum.Font.Gotham
                b.Text="  "..item.name; b.TextColor3=Color3.fromRGB(220,220,220)
                b.TextSize=11; b.TextXAlignment=Enum.TextXAlignment.Left
                b.BorderSizePixel=0; b.ZIndex=54; b.AutoButtonColor=true
                Instance.new("UICorner",b).CornerRadius=UDim.new(0,4); b.Parent=pickerScroll
                b.MouseButton1Click:Connect(function()
                    if pickApplying then return end; pickApplying=true
                    task.spawn(function()
                        local ok=applySlotFromBundle(curPickSlot,item)
                        if ok then
                            pickerPage.Visible=false; slotPage.Visible=true
                            local row=scrollFrame:FindFirstChild("Row_"..curPickSlot)
                            if row then local cl=row:FindFirstChild("CurrentLabel"); if cl then cl.Text=item.name end end
                        end
                        pickApplying=false
                    end)
                end)
            end
        end

        local pickDebounce=nil
        pickerSearch:GetPropertyChangedSignal("Text"):Connect(function()
            if pickDebounce then pcall(function() task.cancel(pickDebounce) end) end
            pickDebounce=task.delay(0.35,function() populatePicker(pickerSearch.Text); pickDebounce=nil end)
        end)

        for idx,slotName in ipairs(ANIM_SLOT_NAMES) do
            local row=Instance.new("Frame",scrollFrame)
            row.Name="Row_"..slotName; row.BackgroundColor3=Color3.new(0,0,0)
            row.BackgroundTransparency=0.4; row.Size=UDim2.new(1,0,0,38)
            row.LayoutOrder=idx; row.BorderSizePixel=0; row.ZIndex=54
            Instance.new("UICorner",row).CornerRadius=UDim.new(0,6)

            local sl=Instance.new("TextLabel",row)
            sl.BackgroundTransparency=1; sl.Position=UDim2.fromOffset(8,0)
            sl.Size=UDim2.new(0.18,0,1,0); sl.Font=Enum.Font.GothamBold
            sl.Text=slotName; sl.TextColor3=Color3.fromRGB(220,220,220)
            sl.TextSize=12; sl.TextXAlignment=Enum.TextXAlignment.Left; sl.ZIndex=55

            local cl=Instance.new("TextLabel",row)
            cl.Name="CurrentLabel"; cl.BackgroundTransparency=1
            cl.Position=UDim2.new(0.20,0,0,0); cl.Size=UDim2.new(0.36,0,1,0)
            cl.Font=Enum.Font.Gotham; cl.Text="None"
            cl.TextColor3=Color3.fromRGB(150,150,150); cl.TextSize=10
            cl.TextTruncate=Enum.TextTruncate.AtEnd
            cl.TextXAlignment=Enum.TextXAlignment.Left; cl.ZIndex=55

            local rb=Instance.new("TextButton",row)
            rb.Name="RemoveBtn"; rb.BackgroundColor3=Color3.fromRGB(180,50,50)
            rb.Position=UDim2.new(0.57,0,0.1,0); rb.Size=UDim2.new(0.18,-2,0.8,0)
            rb.Font=Enum.Font.GothamBold; rb.Text="X"
            rb.TextColor3=Color3.fromRGB(255,255,255); rb.TextSize=12
            rb.BorderSizePixel=0; rb.ZIndex=55
            Instance.new("UICorner",rb).CornerRadius=UDim.new(0,4)
            rb.MouseButton1Click:Connect(function()
                if State.applyingAnim then return end
                State.config.CustomAnimSlots[slotName]=nil; SaveConfig()
                cl.Text="None"; notify("Custom Anim","Removed: "..slotName,3)
            end)

            local sb=Instance.new("TextButton",row)
            sb.BackgroundColor3=Color3.fromRGB(0,130,220)
            sb.Position=UDim2.new(0.76,0,0.1,0); sb.Size=UDim2.new(0.22,-4,0.8,0)
            sb.Font=Enum.Font.GothamBold; sb.Text="Pick"
            sb.TextColor3=Color3.fromRGB(255,255,255); sb.TextSize=11
            sb.BorderSizePixel=0; sb.ZIndex=55
            Instance.new("UICorner",sb).CornerRadius=UDim.new(0,4)
            sb.MouseButton1Click:Connect(function()
                curPickSlot=slotName; pickerTitle.Text="Pick bundle for: "..slotName
                pickerSearch.Text=""; populatePicker("")
                slotPage.Visible=false; pickerPage.Visible=true
            end)
        end

        local botBar=Instance.new("Frame",slotPage)
        botBar.BackgroundTransparency=1; botBar.BorderSizePixel=0
        botBar.Size=UDim2.new(1,0,0,36); botBar.Position=UDim2.new(0,0,1,-38); botBar.ZIndex=54
        local botL=Instance.new("UIListLayout",botBar)
        botL.FillDirection=Enum.FillDirection.Horizontal
        botL.HorizontalAlignment=Enum.HorizontalAlignment.Center
        botL.VerticalAlignment=Enum.VerticalAlignment.Center; botL.Padding=UDim.new(0,10)

        local applyAllBtn=Instance.new("TextButton",botBar)
        applyAllBtn.LayoutOrder=1; applyAllBtn.BackgroundColor3=Color3.fromRGB(40,160,60)
        applyAllBtn.Size=UDim2.new(0,130,0,28); applyAllBtn.Font=Enum.Font.GothamBold
        applyAllBtn.Text="Apply All"; applyAllBtn.TextColor3=Color3.fromRGB(255,255,255)
        applyAllBtn.TextSize=12; applyAllBtn.BorderSizePixel=0; applyAllBtn.ZIndex=55
        Instance.new("UICorner",applyAllBtn).CornerRadius=UDim.new(0,6)
        applyAllBtn.MouseButton1Click:Connect(function() task.spawn(applyAllCustomSlots) end)

        local clearAllBtn=Instance.new("TextButton",botBar)
        clearAllBtn.LayoutOrder=2; clearAllBtn.BackgroundColor3=Color3.fromRGB(180,50,50)
        clearAllBtn.Size=UDim2.new(0,130,0,28); clearAllBtn.Font=Enum.Font.GothamBold
        clearAllBtn.Text="Clear All"; clearAllBtn.TextColor3=Color3.fromRGB(255,255,255)
        clearAllBtn.TextSize=12; clearAllBtn.BorderSizePixel=0; clearAllBtn.ZIndex=55
        Instance.new("UICorner",clearAllBtn).CornerRadius=UDim.new(0,6)
        clearAllBtn.MouseButton1Click:Connect(function()
            State.config.CustomAnimSlots={}; SaveConfig()
            notify("Custom Anim","Cleared all custom slots",3)
            for _,ch in pairs(scrollFrame:GetChildren()) do
                if ch:IsA("Frame") then
                    local c2=ch:FindFirstChild("CurrentLabel"); if c2 then c2.Text="None" end
                end
            end
        end)
    end

    for _,slotName in ipairs(ANIM_SLOT_NAMES) do
        local row=customFrame:FindFirstChild("Row_"..slotName,true)
        if row then
            local cl=row:FindFirstChild("CurrentLabel")
            if cl then
                local ci=State.config.CustomAnimSlots[slotName]
                cl.Text=(type(ci)=="table" and ci.name) and ci.name or "None"
            end
        end
    end
    customFrame.Visible=true
end

--------------------------------------------------------------------------------
-- Wiring
--------------------------------------------------------------------------------
CloseButton.MouseButton1Click:Connect(function() ScreenGui.Enabled=false end)

SearchBar:GetPropertyChangedSignal("Text"):Connect(function()
    local t=SearchBar.Text
    if #t>50 then SearchBar.Text=t:sub(1,50); t=SearchBar.Text end
    searchItems(t); refreshGrid()
end)

ModeButton.MouseButton1Click:Connect(function()
    State.mode=State.mode=="emote" and "animation" or "emote"
    ModeButton.Text=State.mode=="animation" and "ANI" or "EMO"
    if State.mode=="animation" and #State.animsData==0 then task.spawn(fetchAnims) end
    SearchBar.Text=""; searchItems(""); State.cacheDirty=true; refreshGrid()
end)

AutoButton.MouseButton1Click:Connect(function()
    State.autoReapplyEnabled=not State.autoReapplyEnabled
    State.config.AutoReapplyEnabled=State.autoReapplyEnabled; SaveConfig()
    AutoButton.Text=State.autoReapplyEnabled and "RE: ON" or "RE"
    notify("Auto-Reapply",State.autoReapplyEnabled and "ON" or "OFF",3)
    if State.autoReapplyEnabled then task.spawn(reapplyAll) end
end)

CustomAnimBtn.MouseButton1Click:Connect(openCustomAnimEditor)
SortButton.MouseButton1Click:Connect(function() SortFrame.Visible=not SortFrame.Visible end)

local inputconnect
ScreenGui:GetPropertyChangedSignal("Enabled"):Connect(function()
    if ScreenGui.Enabled then
        if customFrame then customFrame.Visible=false end
        BackFrame.Visible=true; EmoteName.Text="Select an Emote"
        SortFrame.Visible=false; GuiService:SetEmotesMenuOpen(false)
        refreshGrid()
        inputconnect=UserInputService.InputBegan:Connect(function(input,processed)
            if not processed and input.UserInputType==Enum.UserInputType.MouseButton1 then
                local mp=UserInputService.GetMouseLocation and UserInputService:GetMouseLocation() or input.Position
                local fp=BackFrame.AbsolutePosition; local fs=BackFrame.AbsoluteSize
                if mp.X<fp.X or mp.X>fp.X+fs.X or mp.Y<fp.Y or mp.Y>fp.Y+fs.Y then
                    ScreenGui.Enabled=false
                end
            end
        end)
    else
        if customFrame then customFrame.Visible=false; BackFrame.Visible=true end
        if inputconnect then inputconnect:Disconnect() end
    end
end)

local menuToggleDebounce=false
ContextActionService:BindCoreActionAtPriority("Emote Menu",function(name,state)
    if state==Enum.UserInputState.Begin then
        if menuToggleDebounce then return end; menuToggleDebounce=true
        ScreenGui.Enabled=not ScreenGui.Enabled
        task.delay(0.2,function() menuToggleDebounce=false end)
    end
end,true,2001,Enum.KeyCode.Comma)

local lastReapplyTime=0
local function onCharacterAdded(char)
    local hum=char:WaitForChild("Humanoid",15); if not hum then return end
    State.applyingAnim=false
    if State.autoReapplyEnabled then
        char:WaitForChild("Animate",15); task.wait(2)
        if not char:IsDescendantOf(game) or hum.Health<=0 then return end
        local now=tick(); if now-lastReapplyTime<5 then return end; lastReapplyTime=now
        reapplyAll()
    end
    hum.Died:Connect(function() State.applyingAnim=false end)
end

task.spawn(function()
    LoadConfig(); loadLastAnim()

    local rawEF=loadFile(State.favFileName); State.favEmotes={}
    if type(rawEF)=="table" then
        for _,v in ipairs(rawEF) do
            if type(v)=="table" and v.id then
                State.favEmotes[#State.favEmotes+1]={id=v.id,name=v.name or ("Emote_"..tostring(v.id))}
            end
        end
    end

    local rawAF=loadFile(State.favAnimFileName); State.favAnims={}
    if type(rawAF)=="table" then
        for _,v in ipairs(rawAF) do
            if type(v)=="table" and v.id then
                State.favAnims[#State.favAnims+1]={id=v.id,name=v.name or ("Anim_"..tostring(v.id)),bundledItems=v.bundledItems}
            end
        end
    end

    rebuildFavLookup(); fetchEmotes(); fetchAnims()
    notify("PinkWards","Emote Sniper loaded! Press ',' to open.",4)
end)

player.CharacterAdded:Connect(onCharacterAdded)
if player.Character then task.spawn(function() onCharacterAdded(player.Character) end) end

StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Chat,true)
GuiService.EmotesMenuOpenChanged:Connect(function(isopen) if isopen then ScreenGui.Enabled=false end end)
GuiService.MenuOpened:Connect(function() ScreenGui.Enabled=false end)
