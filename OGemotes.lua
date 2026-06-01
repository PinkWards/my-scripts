if _G.EmotesGUIRunning then return end
_G.EmotesGUIRunning = true

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")
local StarterGui = game:GetService("StarterGui")
local GuiService = game:GetService("GuiService")
local ContextActionService = game:GetService("ContextActionService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local EMOTE_URL = "https://raw.githubusercontent.com/PinkWards/emote-sniper/refs/heads/main/EmoteSniper.json"
local ANIM_URL = "https://raw.githubusercontent.com/PinkWards/emote-sniper/refs/heads/main/AnimationSniper.json"

local State = {
    mode = "emote", currentPage = 1, itemsPerPage = 60,
    emotesData = {}, animsData = {}, filteredEmotes = {}, filteredAnims = {},
    favEmotes = {}, favAnims = {}, isLoadingEmotes = false, isLoadingAnims = false,
    favSetVersion = 0, autoReapplyEnabled = false,
    favFileName = "FavoriteEmotes.json", favAnimFileName = "FavoriteAnimation.json",
    favLookupEmote = {}, favLookupAnim = {}, applyingAnim = false,
    cacheDirty = true, cachedCombined = {},
    config = { NotifyEnabled = true, AutoReapplyEnabled = false, CustomAnimSlots = {} }
}

getgenv().lastAnim = getgenv().lastAnim or nil
local ConfigPath = "PinkWards/Config.json"

local ANIM_SLOT_NAMES = {"idle", "walk", "run", "jump", "climb", "fall", "swim", "swimidle"}
local validSlotLookup = {}
for _, name in ipairs(ANIM_SLOT_NAMES) do validSlotLookup[name:lower()] = name end

--------------------------------------------------------------------------------
-- Large ID safe JSON parser
-- Roblox anim IDs exceed 2^53 so we parse as strings from raw JSON
--------------------------------------------------------------------------------
local function extractBundledFromRaw(rawJson, startPos)
    local baStart = rawJson:find('"bundledAnimations"%s*:%s*{', startPos)
    if not baStart then return nil, startPos end
    local braceOpen = rawJson:find('{', baStart)
    if not braceOpen then return nil, startPos end
    local depth, baEnd = 0, braceOpen
    for i = braceOpen, #rawJson do
        local ch = rawJson:sub(i,i)
        if ch == '{' then depth += 1
        elseif ch == '}' then
            depth -= 1
            if depth == 0 then baEnd = i; break end
        end
    end
    local block = rawJson:sub(braceOpen, baEnd)
    local bundled = {}
    local slotPos = 1
    while true do
        local keyStart, keyEnd, slotKey = block:find('"([A-Za-z]+)"%s*:%s*%[', slotPos)
        if not keyStart then break end
        slotPos = keyEnd + 1
        local arrStart = block:find('%[', keyEnd)
        if not arrStart then break end
        local arrEnd = block:find('%]', arrStart)
        if not arrEnd then break end
        local arrBlock = block:sub(arrStart, arrEnd)
        local slotName = validSlotLookup[slotKey:lower()]
        if slotName then
            local ids = {}
            for idStr in arrBlock:gmatch('"id"%s*:%s*(%d+)') do
                ids[#ids+1] = idStr
            end
            if #ids > 0 then bundled[slotName] = ids end
        end
        slotPos = arrEnd + 1
    end
    return next(bundled) and bundled or nil, baEnd + 1
end

local function parseAnimsFromRaw(rawJson)
    local results = {}
    local pos = 1
    while true do
        local idStart, idEnd, idStr = rawJson:find('"id"%s*:%s*(-?%d+)', pos)
        if not idStart then break end
        pos = idEnd + 1
        local itemId = tonumber(idStr)
        if not itemId then break end
        local _, nameEnd, itemName = rawJson:find('"name"%s*:%s*"([^"]*)"', idEnd)
        if not itemName then break end
        local bundled, newPos = extractBundledFromRaw(rawJson, nameEnd)
        pos = newPos
        if bundled then
            results[#results+1] = {id = itemId, name = itemName, bundledItems = bundled}
        end
    end
    return results
end

--------------------------------------------------------------------------------
-- FE Animation System (same method as the working script)
-- Directly sets AnimationId on the known named children inside Animate folders
--------------------------------------------------------------------------------

local lastAnimations = {}

local function getChar()
    return player.Character
end

local function getAnimate()
    local char = getChar()
    return char and char:FindFirstChild("Animate")
end

local function getHum()
    local char = getChar()
    return char and char:FindFirstChildOfClass("Humanoid")
end

local function stopAllTracks()
    local hum = getHum()
    if not hum then return end
    pcall(function()
        for _, track in ipairs(hum:GetPlayingAnimationTracks()) do
            track:Stop(0)
        end
    end)
end

local function freeze()
    local char = getChar(); if not char then return end
    local hum = getHum(); if not hum then return end
    pcall(function() hum.PlatformStand = true end)
    for _, part in ipairs(char:GetDescendants()) do
        if part:IsA("BasePart") and not part.Anchored then
            part.Anchored = true
        end
    end
end

local function unfreeze()
    local char = getChar(); if not char then return end
    local hum = getHum(); if not hum then return end
    pcall(function() hum.PlatformStand = false end)
    for _, part in ipairs(char:GetDescendants()) do
        if part:IsA("BasePart") and part.Anchored then
            part.Anchored = false
        end
    end
end

local function refresh()
    local hum = getHum(); if not hum then return end
    pcall(function()
        hum:ChangeState(Enum.HumanoidStateType.Freefall)
    end)
end

local function refreshSwim()
    local hum = getHum(); if not hum then return end
    pcall(function()
        hum:ChangeState(Enum.HumanoidStateType.GettingUp)
        task.wait(0.1)
        hum:ChangeState(Enum.HumanoidStateType.Swimming)
    end)
end

local function refreshClimb()
    local hum = getHum(); if not hum then return end
    pcall(function()
        hum:ChangeState(Enum.HumanoidStateType.GettingUp)
        task.wait(0.1)
        hum:ChangeState(Enum.HumanoidStateType.Climbing)
    end)
end

-- This is the core setter - directly patches the named Animation children
-- exactly like the working FE script does
local function setSlotDirect(slotName, ids)
    local animate = getAnimate(); if not animate then return false end
    local folder = animate:FindFirstChild(slotName)
    if not folder then return false end

    stopAllTracks()

    -- Get all Animation children in order
    local animChildren = {}
    for _, child in ipairs(folder:GetChildren()) do
        if child:IsA("Animation") then
            animChildren[#animChildren+1] = child
        end
    end

    -- Set each animation child to the corresponding id
    -- If there are more children than ids, fill remaining with last id
    -- (prevents the old animation bleeding through)
    local lastId = ids[#ids]
    for i, animChild in ipairs(animChildren) do
        local idStr = ids[i] or lastId
        animChild.AnimationId = "http://www.roblox.com/asset/?id=" .. tostring(idStr)
    end

    -- If there are more ids than children, create new Animation instances
    for i = #animChildren + 1, #ids do
        local newAnim = Instance.new("Animation")
        newAnim.Name = "Animation" .. i
        newAnim.AnimationId = "http://www.roblox.com/asset/?id=" .. tostring(ids[i])
        newAnim.Parent = folder
    end

    return true
end

-- Apply a full bundle (all slots at once)
local function applyBundle(bundledItems)
    local animate = getAnimate(); if not animate then return 0 end
    freeze()
    task.wait(0.1)

    local applied = 0
    for slotName, ids in pairs(bundledItems) do
        if setSlotDirect(slotName, ids) then
            applied += 1
        end
    end

    task.wait(0.1)
    unfreeze()
    task.wait(0.05)
    refresh()
    return applied
end

-- Apply a single slot from a bundle
local function applySlot(slotName, ids)
    local animate = getAnimate(); if not animate then return false end
    freeze()
    task.wait(0.1)

    local ok = setSlotDirect(slotName, ids)

    task.wait(0.1)
    unfreeze()
    task.wait(0.05)

    if slotName == "swim" or slotName == "swimidle" then
        refreshSwim()
    elseif slotName == "climb" then
        refreshClimb()
    else
        refresh()
    end
    return ok
end

local function saveLastAnim()
    if getgenv().lastAnim then
        if writefile then
            if not isfolder("PinkWards") then pcall(function() makefolder("PinkWards") end) end
            pcall(function() writefile("PinkWards/LastAnimation.json", HttpService:JSONEncode(getgenv().lastAnim)) end)
        end
    end
end

local function applyAnim(data)
    if not data then return end
    if State.applyingAnim then return end
    State.applyingAnim = true
    task.spawn(function()
        local bundled = data.bundledItems
        if not bundled or not next(bundled) then
            notify("Animation", "No animation data for: " .. tostring(data.name), 3)
            State.applyingAnim = false; return
        end

        getgenv().lastAnim = {id = data.id, name = data.name, bundledItems = bundled}
        saveLastAnim()

        notify("Animation", "Applying: " .. tostring(data.name) .. "...", 2)
        local applied = applyBundle(bundled)
        notify("Animation", "Applied: " .. tostring(data.name) .. " (" .. applied .. " slots)", 3)
        State.applyingAnim = false
    end)
end

--------------------------------------------------------------------------------
-- Config / File helpers
--------------------------------------------------------------------------------
local function SaveConfig()
    if not isfolder then return end
    if not isfolder("PinkWards") then pcall(function() makefolder("PinkWards") end) end
    pcall(function() writefile(ConfigPath, HttpService:JSONEncode(State.config)) end)
end

local function LoadConfig()
    if isfile and isfile(ConfigPath) then
        local ok, data = pcall(function() return HttpService:JSONDecode(readfile(ConfigPath)) end)
        if ok and data then for k, v in pairs(data) do State.config[k] = v end end
    end
    State.autoReapplyEnabled = State.config.AutoReapplyEnabled or false
    if not State.config.CustomAnimSlots then State.config.CustomAnimSlots = {} end
end

function notify(title, content, duration)
    if not State.config.NotifyEnabled then return end
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = title or "PinkWards", Text = content or "", Duration = duration or 4
        })
    end)
end

local function saveFile(name, data)
    if writefile then
        if not isfolder("PinkWards") then pcall(function() makefolder("PinkWards") end) end
        pcall(function() writefile("PinkWards/" .. name, HttpService:JSONEncode(data)) end)
    end
end

local function loadFile(name)
    for _, path in ipairs({"PinkWards/" .. name, name}) do
        if readfile and isfile then
            local exists = false
            pcall(function() exists = isfile(path) end)
            if exists then
                local ok, res = pcall(function() return HttpService:JSONDecode(readfile(path)) end)
                if ok and res and type(res) == "table" then
                    if res.data and type(res.data) == "table" then return res.data end
                    if res.favorites and type(res.favorites) == "table" then return res.favorites end
                    return res
                end
            end
        end
    end
    return {}
end

local function loadLastAnim()
    local data = loadFile("LastAnimation.json")
    if data and data.id then
        getgenv().lastAnim = {id = data.id, name = data.name, bundledItems = data.bundledItems}
    end
end

local function rebuildFavLookup()
    State.favLookupEmote = {}
    for _, v in ipairs(State.favEmotes) do State.favLookupEmote[tostring(v.id)] = true end
    State.favLookupAnim = {}
    for _, v in ipairs(State.favAnims) do State.favLookupAnim[tostring(v.id)] = true end
    State.favSetVersion += 1
end

local function playEmote(name, id)
    local char = getChar(); if not char then return end
    local humanoid = getHum()
    local description = humanoid and humanoid:FindFirstChildOfClass("HumanoidDescription")
    if not humanoid or not description then return end
    if humanoid.RigType ~= Enum.HumanoidRigType.R6 then
        task.spawn(function()
            pcall(function() description:AddEmote(name, id) end)
            pcall(function() humanoid:PlayEmoteAndGetAnimTrackById(id) end)
        end)
    else notify("R6?", "You gotta be R15 dude", 3) end
end

local function searchItems(term)
    term = term:lower()
    local source = State.mode == "animation" and State.animsData or State.emotesData
    if term == "" then
        if State.mode == "animation" then State.filteredAnims = State.animsData
        else State.filteredEmotes = State.emotesData end
    else
        local result = {}
        local isIdSearch = term:match("^-?%d+$")
        if isIdSearch then
            for i = 1, #source do
                if tostring(source[i].id) == term then result[#result+1] = source[i]; break end
            end
        else
            for i = 1, #source do
                if source[i].name:lower():find(term, 1, true) then result[#result+1] = source[i] end
            end
        end
        if State.mode == "animation" then State.filteredAnims = result
        else State.filteredEmotes = result end
    end
    State.currentPage = 1; State.cacheDirty = true
end

local function fetchEmotes()
    if State.isLoadingEmotes then return end
    State.isLoadingEmotes = true
    local ok, result = pcall(function() return HttpService:JSONDecode(game:HttpGet(EMOTE_URL)) end)
    if ok and result then
        local rawList = result.data or result; local data = {}
        for i = 1, #rawList do
            local item = rawList[i]; local id = tonumber(item.id)
            if id and id ~= 0 then data[#data+1] = {id = id, name = item.name or ("Emote_"..id)} end
        end
        State.emotesData = data; State.filteredEmotes = data
    end
    State.isLoadingEmotes = false; State.cacheDirty = true
end

local function fetchAnims()
    if State.isLoadingAnims then return end
    State.isLoadingAnims = true
    local ok, rawJson = pcall(function() return game:HttpGet(ANIM_URL) end)
    if ok and rawJson then
        local parsed = parseAnimsFromRaw(rawJson)
        State.animsData = parsed; State.filteredAnims = parsed
    end
    State.isLoadingAnims = false; State.cacheDirty = true
end

function toggleFav(id, name, bundledItems)
    local list = State.mode == "animation" and State.favAnims or State.favEmotes
    local found, idx = false, 0
    for i, v in ipairs(list) do
        if tostring(v.id) == tostring(id) then found, idx = true, i; break end
    end
    if found then
        table.remove(list, idx); notify("Favorites", "Removed: " .. name, 3)
    else
        local entry = {id = id, name = name}
        if State.mode == "animation" then entry.bundledItems = bundledItems end
        table.insert(list, entry); notify("Favorites", "Added: " .. name, 3)
    end
    saveFile(State.mode == "animation" and State.favAnimFileName or State.favFileName, list)
    rebuildFavLookup(); State.cacheDirty = true; refreshGrid()
end

--------------------------------------------------------------------------------
-- Custom slot system
--------------------------------------------------------------------------------
local function applyAllCustomSlots()
    if not State.config.CustomAnimSlots or not next(State.config.CustomAnimSlots) then
        notify("Custom Anim", "No custom slots configured", 3); return
    end
    if State.applyingAnim then notify("Custom Anim", "Already applying...", 3); return end
    State.applyingAnim = true
    task.spawn(function()
        if not getChar() then State.applyingAnim = false; return end
        notify("Custom Anim", "Applying all custom slots...", 2)
        local mergedBundled = {}
        for slotName, info in pairs(State.config.CustomAnimSlots) do
            if type(info) == "table" and info.id then
                for _, a in ipairs(State.animsData) do
                    if tostring(a.id) == tostring(info.id) and a.bundledItems then
                        if a.bundledItems[slotName] then
                            mergedBundled[slotName] = a.bundledItems[slotName]
                        end
                        break
                    end
                end
            end
        end
        if next(mergedBundled) then
            local applied = applyBundle(mergedBundled)
            notify("Custom Anim", "Applied custom slots (" .. applied .. " slots)", 3)
        else
            notify("Custom Anim", "Could not find animation data", 3)
        end
        State.applyingAnim = false
    end)
end

local function applySlotFromBundle(slotName, bundleData)
    if not bundleData or not bundleData.bundledItems then return false end
    local slotIds = bundleData.bundledItems[slotName]
    if not slotIds or #slotIds == 0 then return false end
    local ok = applySlot(slotName, slotIds)
    if ok then
        State.config.CustomAnimSlots[slotName] = {id = bundleData.id, name = bundleData.name}
        SaveConfig()
    end
    return ok
end

local function reapplyAll()
    if not getChar() then return end
    local hc = State.config.CustomAnimSlots and next(State.config.CustomAnimSlots)
    if hc then applyAllCustomSlots()
    elseif getgenv().lastAnim and getgenv().lastAnim.bundledItems then
        applyAnim(getgenv().lastAnim)
    end
end

--------------------------------------------------------------------------------
-- GUI
--------------------------------------------------------------------------------
local FavoriteOff = "rbxassetid://10651060677"
local FavoriteOn  = "rbxassetid://10651061109"

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "Emotes"; ScreenGui.DisplayOrder = 2
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.ResetOnSpawn = false; ScreenGui.Enabled = false

local hiddenUI = gethui or get_hidden_gui
if hiddenUI then ScreenGui.Parent = hiddenUI()
else pcall(function() syn.protect_gui(ScreenGui) end); ScreenGui.Parent = CoreGui end

local Corner = Instance.new("UICorner"); Corner.CornerRadius = UDim.new(0,6)

local BackFrame = Instance.new("Frame")
BackFrame.Size = UDim2.new(0.58,0,0.72,0); BackFrame.AnchorPoint = Vector2.new(0.5,0.5)
BackFrame.Position = UDim2.new(0.5,0,0.5,0); BackFrame.BackgroundTransparency = 1
BackFrame.BorderSizePixel = 0; BackFrame.Parent = ScreenGui

local Frame = Instance.new("ScrollingFrame")
Frame.Size = UDim2.new(1,0,0.82,0); Frame.CanvasSize = UDim2.new(0,0,0,0)
Frame.AutomaticCanvasSize = Enum.AutomaticSize.Y; Frame.ScrollingDirection = Enum.ScrollingDirection.Y
Frame.AnchorPoint = Vector2.new(0.5,0); Frame.Position = UDim2.new(0.5,0,0,0)
Frame.BackgroundTransparency = 1; Frame.ScrollBarThickness = 4
Frame.BorderSizePixel = 0; Frame.Parent = BackFrame

local FramePadding = Instance.new("UIPadding", Frame)
FramePadding.PaddingLeft = UDim.new(0,5); FramePadding.PaddingRight = UDim.new(0,8)
FramePadding.PaddingTop = UDim.new(0,5)

local Grid = Instance.new("UIGridLayout")
Grid.CellSize = UDim2.new(0,75,0,75); Grid.CellPadding = UDim2.new(0,5,0,5)
Grid.SortOrder = Enum.SortOrder.LayoutOrder; Grid.Parent = Frame

local PageFrame = Instance.new("Frame")
PageFrame.BackgroundTransparency = 1; PageFrame.Size = UDim2.new(1,0,0.07,0)
PageFrame.Position = UDim2.new(0,0,0.84,0); PageFrame.BorderSizePixel = 0
PageFrame.Parent = BackFrame

local PageLeft = Instance.new("TextButton")
PageLeft.BorderSizePixel = 0; PageLeft.AnchorPoint = Vector2.new(0,0.5)
PageLeft.Position = UDim2.new(0.3,0,0.5,0); PageLeft.Size = UDim2.new(0.08,0,0.85,0)
PageLeft.TextScaled = true; PageLeft.TextColor3 = Color3.new(1,1,1)
PageLeft.Font = Enum.Font.GothamBold; PageLeft.BackgroundColor3 = Color3.new(0,0,0)
PageLeft.BackgroundTransparency = 0.3; PageLeft.Text = "<"
Corner:Clone().Parent = PageLeft; PageLeft.Parent = PageFrame

local PageLabel = Instance.new("TextBox")
PageLabel.BackgroundTransparency = 1; PageLabel.AnchorPoint = Vector2.new(0.5,0.5)
PageLabel.Position = UDim2.new(0.5,0,0.5,0); PageLabel.Size = UDim2.new(0.22,0,0.85,0)
PageLabel.TextScaled = true; PageLabel.Font = Enum.Font.GothamBold
PageLabel.TextColor3 = Color3.new(1,1,1); PageLabel.Text = "1 / 1"
PageLabel.ClearTextOnFocus = false; PageLabel.BorderSizePixel = 0
PageLabel.Parent = PageFrame

local PageRight = Instance.new("TextButton")
PageRight.BorderSizePixel = 0; PageRight.AnchorPoint = Vector2.new(1,0.5)
PageRight.Position = UDim2.new(0.7,0,0.5,0); PageRight.Size = UDim2.new(0.08,0,0.85,0)
PageRight.TextScaled = true; PageRight.TextColor3 = Color3.new(1,1,1)
PageRight.Font = Enum.Font.GothamBold; PageRight.BackgroundColor3 = Color3.new(0,0,0)
PageRight.BackgroundTransparency = 0.3; PageRight.Text = ">"
Corner:Clone().Parent = PageRight; PageRight.Parent = PageFrame

local EmoteName = Instance.new("TextLabel")
EmoteName.TextScaled = true; EmoteName.AnchorPoint = Vector2.new(0.5,0.5)
EmoteName.Position = UDim2.new(0.5,0,0.95,0); EmoteName.Size = UDim2.new(0.65,0,0.055,0)
EmoteName.BackgroundColor3 = Color3.fromRGB(30,30,30); EmoteName.TextColor3 = Color3.new(1,1,1)
EmoteName.Font = Enum.Font.GothamBold; EmoteName.BorderSizePixel = 0
EmoteName.Text = "Select an Emote"; EmoteName.Parent = BackFrame
Corner:Clone().Parent = EmoteName

local TopBar = Instance.new("Frame")
TopBar.BackgroundTransparency = 1; TopBar.Size = UDim2.new(1,0,0.07,0)
TopBar.Position = UDim2.new(0,0,-0.09,0); TopBar.BorderSizePixel = 0
TopBar.Parent = BackFrame

local function makeBtn(anchorX, xPos, xSize, text, parent)
    local b = Instance.new("TextButton")
    b.BorderSizePixel = 0; b.AnchorPoint = Vector2.new(anchorX, 0.5)
    b.Position = UDim2.new(xPos,0,0.5,0); b.Size = UDim2.new(xSize,0,0.9,0)
    b.TextScaled = true; b.TextColor3 = Color3.new(1,1,1)
    b.Font = Enum.Font.GothamBold; b.BackgroundColor3 = Color3.new(0,0,0)
    b.BackgroundTransparency = 0.3; b.Text = text
    Corner:Clone().Parent = b; b.Parent = parent
    return b
end

local CloseButton   = makeBtn(0, 0,    0.11, "Close", TopBar)
local ModeButton    = makeBtn(0, 0.43, 0.11, "EMO",   TopBar)
local AutoButton    = makeBtn(0, 0.55, 0.12, "RE",    TopBar)
local CustomAnimBtn = makeBtn(0, 0.68, 0.11, "CUS",   TopBar)
local SortButton    = makeBtn(1, 1,    0.13, "Sort",  TopBar)

local SearchBar = Instance.new("TextBox")
SearchBar.BorderSizePixel = 0; SearchBar.AnchorPoint = Vector2.new(0,0.5)
SearchBar.Position = UDim2.new(0.12,0,0.5,0); SearchBar.Size = UDim2.new(0.30,0,0.9,0)
SearchBar.TextScaled = true; SearchBar.PlaceholderText = "Search..."
SearchBar.Font = Enum.Font.Gotham; SearchBar.PlaceholderColor3 = Color3.fromRGB(150,150,150)
SearchBar.TextColor3 = Color3.new(1,1,1); SearchBar.BackgroundColor3 = Color3.new(0,0,0)
SearchBar.BackgroundTransparency = 0.3
Corner:Clone().Parent = SearchBar; SearchBar.Parent = TopBar

local SortFrame = Instance.new("Frame")
SortFrame.Visible = false; SortFrame.BorderSizePixel = 0
SortFrame.AnchorPoint = Vector2.new(1,0); SortFrame.Position = UDim2.new(1,0,0.01,0)
SortFrame.Size = UDim2.new(0.3,0,0,0); SortFrame.AutomaticSize = Enum.AutomaticSize.Y
SortFrame.BackgroundColor3 = Color3.fromRGB(20,20,20); SortFrame.BackgroundTransparency = 0.1
SortFrame.ZIndex = 100; Corner:Clone().Parent = SortFrame; SortFrame.Parent = BackFrame

Instance.new("UIListLayout", SortFrame).Padding = UDim.new(0.02,0)
local sp = Instance.new("UIPadding", SortFrame)
sp.PaddingTop = UDim.new(0,4); sp.PaddingBottom = UDim.new(0,4)

local CurrentSort = "favfirst"
local function createsort(order, text, sort)
    local s = Instance.new("TextButton")
    s.Size = UDim2.new(0.94,0,0,28); s.BackgroundColor3 = Color3.fromRGB(30,30,30)
    s.LayoutOrder = order; s.TextColor3 = Color3.new(1,1,1); s.Text = text
    s.Font = Enum.Font.GothamBold; s.TextSize = 13; s.BorderSizePixel = 0; s.ZIndex = 101
    Corner:Clone().Parent = s; s.Parent = SortFrame
    s.MouseButton1Click:Connect(function()
        SortFrame.Visible = false; CurrentSort = sort
        State.currentPage = 1; State.cacheDirty = true; refreshGrid()
    end)
end
createsort(1,"Favorites First","favfirst")
createsort(2,"A - Z","az")
createsort(3,"Z - A","za")

local buttonPool = {}; local btnDataMap = {}
local function ensurePoolSize(count)
    while #buttonPool < count do
        local i = #buttonPool + 1
        local btn = Instance.new("ImageButton")
        btn.Name = "PoolBtn_"..i; btn.BackgroundColor3 = Color3.fromRGB(0,0,0)
        btn.BackgroundTransparency = 0.5; btn.BorderSizePixel = 0; btn.Visible = false
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0,6)
        local fav = Instance.new("ImageButton")
        fav.Name = "favorite"; fav.Image = FavoriteOff
        fav.AnchorPoint = Vector2.new(0.5,0.5); fav.Size = UDim2.new(0.32,0,0.32,0)
        fav.Position = UDim2.new(0.88,0,0.88,0); fav.BorderSizePixel = 0
        fav.BackgroundTransparency = 1; fav.Parent = btn
        btn.MouseButton1Click:Connect(function()
            local item = btnDataMap[btn]
            if item then
                if State.mode == "animation" then applyAnim(item.data)
                else task.spawn(playEmote, item.data.name, item.data.id) end
                ScreenGui.Enabled = false
            end
        end)
        fav.MouseButton1Click:Connect(function()
            local item = btnDataMap[btn]
            if item then toggleFav(item.data.id, item.data.name, item.data.bundledItems) end
        end)
        btn.MouseEnter:Connect(function()
            local item = btnDataMap[btn]
            if item then EmoteName.Text = item.data.name end
        end)
        btn.Parent = Frame; buttonPool[i] = btn
    end
end
ensurePoolSize(60)

local function getItemsPerPage()
    local aX, aY = Frame.AbsoluteSize.X, Frame.AbsoluteSize.Y
    if aX > 0 and aY > 0 then return math.max(1, math.floor((aX-8)/80)*math.floor(aY/80)) end
    return 60
end

function refreshGrid()
    State.itemsPerPage = getItemsPerPage(); ensurePoolSize(State.itemsPerPage)
    if State.cacheDirty then
        local list = State.mode=="animation" and State.filteredAnims or State.filteredEmotes
        local favs = State.mode=="animation" and State.favAnims or State.favEmotes
        local favLookup = State.mode=="animation" and State.favLookupAnim or State.favLookupEmote
        local normalList = {}
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
                    or ("rbxthumb://type=Asset&id="..math.abs(item.data.id).."&w=150&h=150")
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
-- Custom Anim Editor GUI
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
        local padUI=Instance.new("UIPadding",scrollFrame)
        padUI.PaddingLeft=UDim.new(0,8); padUI.PaddingRight=UDim.new(0,8); padUI.PaddingTop=UDim.new(0,4)

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

        local currentPickerSlot=""; local pickerApplying=false
        pickerBack.MouseButton1Click:Connect(function() pickerPage.Visible=false; slotPage.Visible=true end)

        local function populatePickerList(filterTerm)
            for _,child in pairs(pickerScroll:GetChildren()) do if child:IsA("TextButton") then child:Destroy() end end
            filterTerm=(filterTerm or ""):lower(); local matches={}
            for i=1,#State.animsData do
                if #matches>=50 then break end
                local item=State.animsData[i]
                if filterTerm=="" or item.name:lower():find(filterTerm,1,true) then matches[#matches+1]=item end
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
                    if pickerApplying then return end; pickerApplying=true
                    task.spawn(function()
                        local success=applySlotFromBundle(currentPickerSlot,item)
                        if success then
                            pickerPage.Visible=false; slotPage.Visible=true
                            local row=scrollFrame:FindFirstChild("Row_"..currentPickerSlot)
                            if row then local cl=row:FindFirstChild("CurrentLabel"); if cl then cl.Text=item.name end end
                        end
                        pickerApplying=false
                    end)
                end)
            end
        end

        local pickerDebounce=nil
        pickerSearch:GetPropertyChangedSignal("Text"):Connect(function()
            if pickerDebounce then pcall(function() task.cancel(pickerDebounce) end) end
            pickerDebounce=task.delay(0.35,function() populatePickerList(pickerSearch.Text); pickerDebounce=nil end)
        end)

        for idx,slotName in ipairs(ANIM_SLOT_NAMES) do
            local row=Instance.new("Frame",scrollFrame)
            row.Name="Row_"..slotName; row.BackgroundColor3=Color3.new(0,0,0)
            row.BackgroundTransparency=0.4; row.Size=UDim2.new(1,0,0,38)
            row.LayoutOrder=idx; row.BorderSizePixel=0; row.ZIndex=54
            Instance.new("UICorner",row).CornerRadius=UDim.new(0,6)

            local slotLabel=Instance.new("TextLabel",row)
            slotLabel.BackgroundTransparency=1; slotLabel.Position=UDim2.fromOffset(8,0)
            slotLabel.Size=UDim2.new(0.18,0,1,0); slotLabel.Font=Enum.Font.GothamBold
            slotLabel.Text=slotName; slotLabel.TextColor3=Color3.fromRGB(220,220,220)
            slotLabel.TextSize=12; slotLabel.TextXAlignment=Enum.TextXAlignment.Left; slotLabel.ZIndex=55

            local currentLabel=Instance.new("TextLabel",row)
            currentLabel.Name="CurrentLabel"; currentLabel.BackgroundTransparency=1
            currentLabel.Position=UDim2.new(0.20,0,0,0); currentLabel.Size=UDim2.new(0.36,0,1,0)
            currentLabel.Font=Enum.Font.Gotham; currentLabel.Text="None"
            currentLabel.TextColor3=Color3.fromRGB(150,150,150); currentLabel.TextSize=10
            currentLabel.TextTruncate=Enum.TextTruncate.AtEnd
            currentLabel.TextXAlignment=Enum.TextXAlignment.Left; currentLabel.ZIndex=55

            local removeBtn=Instance.new("TextButton",row)
            removeBtn.Name="RemoveBtn"; removeBtn.BackgroundColor3=Color3.fromRGB(180,50,50)
            removeBtn.Position=UDim2.new(0.57,0,0.1,0); removeBtn.Size=UDim2.new(0.18,-2,0.8,0)
            removeBtn.Font=Enum.Font.GothamBold; removeBtn.Text="X"
            removeBtn.TextColor3=Color3.fromRGB(255,255,255); removeBtn.TextSize=12
            removeBtn.BorderSizePixel=0; removeBtn.ZIndex=55
            Instance.new("UICorner",removeBtn).CornerRadius=UDim.new(0,4)
            removeBtn.MouseButton1Click:Connect(function()
                if State.applyingAnim then return end
                State.config.CustomAnimSlots[slotName]=nil; SaveConfig()
                currentLabel.Text="None"
                notify("Custom Anim","Removed slot: "..slotName,3)
            end)

            local selectBtn=Instance.new("TextButton",row)
            selectBtn.BackgroundColor3=Color3.fromRGB(0,130,220)
            selectBtn.Position=UDim2.new(0.76,0,0.1,0); selectBtn.Size=UDim2.new(0.22,-4,0.8,0)
            selectBtn.Font=Enum.Font.GothamBold; selectBtn.Text="Pick"
            selectBtn.TextColor3=Color3.fromRGB(255,255,255); selectBtn.TextSize=11
            selectBtn.BorderSizePixel=0; selectBtn.ZIndex=55
            Instance.new("UICorner",selectBtn).CornerRadius=UDim.new(0,4)
            selectBtn.MouseButton1Click:Connect(function()
                currentPickerSlot=slotName; pickerTitle.Text="Pick bundle for: "..slotName
                pickerSearch.Text=""; populatePickerList("")
                slotPage.Visible=false; pickerPage.Visible=true
            end)
        end

        local bottomBar=Instance.new("Frame",slotPage)
        bottomBar.BackgroundTransparency=1; bottomBar.BorderSizePixel=0
        bottomBar.Size=UDim2.new(1,0,0,36); bottomBar.Position=UDim2.new(0,0,1,-38); bottomBar.ZIndex=54
        local botLayout=Instance.new("UIListLayout",bottomBar)
        botLayout.FillDirection=Enum.FillDirection.Horizontal
        botLayout.HorizontalAlignment=Enum.HorizontalAlignment.Center
        botLayout.VerticalAlignment=Enum.VerticalAlignment.Center
        botLayout.Padding=UDim.new(0,10)

        local applyAllBtn=Instance.new("TextButton",bottomBar)
        applyAllBtn.LayoutOrder=1; applyAllBtn.BackgroundColor3=Color3.fromRGB(40,160,60)
        applyAllBtn.Size=UDim2.new(0,130,0,28); applyAllBtn.Font=Enum.Font.GothamBold
        applyAllBtn.Text="Apply All"; applyAllBtn.TextColor3=Color3.fromRGB(255,255,255)
        applyAllBtn.TextSize=12; applyAllBtn.BorderSizePixel=0; applyAllBtn.ZIndex=55
        Instance.new("UICorner",applyAllBtn).CornerRadius=UDim.new(0,6)
        applyAllBtn.MouseButton1Click:Connect(function() task.spawn(applyAllCustomSlots) end)

        local clearAllBtn=Instance.new("TextButton",bottomBar)
        clearAllBtn.LayoutOrder=2; clearAllBtn.BackgroundColor3=Color3.fromRGB(180,50,50)
        clearAllBtn.Size=UDim2.new(0,130,0,28); clearAllBtn.Font=Enum.Font.GothamBold
        clearAllBtn.Text="Clear All"; clearAllBtn.TextColor3=Color3.fromRGB(255,255,255)
        clearAllBtn.TextSize=12; clearAllBtn.BorderSizePixel=0; clearAllBtn.ZIndex=55
        Instance.new("UICorner",clearAllBtn).CornerRadius=UDim.new(0,6)
        clearAllBtn.MouseButton1Click:Connect(function()
            State.config.CustomAnimSlots={}; SaveConfig()
            notify("Custom Anim","Cleared all custom slots",3)
            for _,child in pairs(scrollFrame:GetChildren()) do
                if child:IsA("Frame") then
                    local cl=child:FindFirstChild("CurrentLabel"); if cl then cl.Text="None" end
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
-- Button wiring
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
        char:WaitForChild("Animate",15)
        task.wait(2)
        if not char:IsDescendantOf(game) or hum.Health<=0 then return end
        local now=tick(); if now-lastReapplyTime<5 then return end; lastReapplyTime=now
        reapplyAll()
    end
    hum.Died:Connect(function() State.applyingAnim=false end)
end

--------------------------------------------------------------------------------
-- Init
--------------------------------------------------------------------------------
task.spawn(function()
    LoadConfig(); loadLastAnim()

    local rawEmoteFavs=loadFile(State.favFileName); State.favEmotes={}
    if type(rawEmoteFavs)=="table" then
        for _,v in ipairs(rawEmoteFavs) do
            if type(v)=="table" and v.id then
                State.favEmotes[#State.favEmotes+1]={id=v.id,name=v.name or ("Emote_"..tostring(v.id))}
            end
        end
    end

    local rawAnimFavs=loadFile(State.favAnimFileName); State.favAnims={}
    if type(rawAnimFavs)=="table" then
        for _,v in ipairs(rawAnimFavs) do
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
