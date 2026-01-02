--[[ 💗 PinkWards Emote + Animation System - Fixed & Optimized ]]

if _G.EmotesGUIRunning then return end
_G.EmotesGUIRunning = true

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")
local StarterGui = game:GetService("StarterGui")
local MarketplaceService = game:GetService("MarketplaceService")
local GuiService = game:GetService("GuiService")

local player = Players.LocalPlayer
local EMOTE_URL = "https://raw.githubusercontent.com/7yd7/sniper-Emote/refs/heads/test/EmoteSniper.json"
local ANIM_URL = "https://raw.githubusercontent.com/7yd7/sniper-Emote/refs/heads/test/AnimationSniper.json"

local mode = "emote"
local currentPage, itemsPerPage, totalPages = 1, 8, 1
local emotesData, animsData, filteredEmotes, filteredAnims = {}, {}, {}, {}
local favEmotes, favAnims = {}, {}
local isLoading, favEnabled, guiCreated = false, false, false
local wheelCache, lastWheelCheck, lastWheelVisible, lastAction = nil, 0, 0, 0

getgenv().lastAnim = getgenv().lastAnim or nil

local COLORS = {
    PINK_LIGHT = Color3.fromHex("#FFEBF2"),
    PINK_MEDIUM = Color3.fromHex("#FFC8DC"),
    PINK_WHEEL = Color3.fromHex("#FFD9E8"),
    PINK_HEART = Color3.fromHex("#FF6B9D"),
    PINK_ANIM = Color3.fromHex("#C8A2C8"),
    WHITE = Color3.fromRGB(255, 255, 255),
    PLACEHOLDER = Color3.fromRGB(255, 210, 230),
}

-- GUI References
local Under, LeftBtn, RightBtn, PagesLabel, SepLabel, PageNumBox
local Top, Search, FavBtn, ModeBtn

--============ UTILITIES ============--

local function notify(title, content, duration)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = title or "Notification",
            Text = content or "",
            Duration = duration or 4
        })
    end)
end

local function getChar()
    local c = player.Character
    return c, c and c:FindFirstChild("Humanoid")
end

local function getWheel()
    local t = tick()
    if wheelCache and wheelCache.Parent and t - lastWheelCheck < 1 then
        return wheelCache
    end
    lastWheelCheck = t
    local ok, w = pcall(function()
        return CoreGui.RobloxGui.EmotesMenu.Children.Main.EmotesWheel
    end)
    wheelCache = ok and w or nil
    return wheelCache
end

local function saveFile(name, data)
    if writefile then
        pcall(function()
            writefile(name, HttpService:JSONEncode(data))
        end)
    end
end

local function loadFile(name)
    if readfile and isfile and isfile(name) then
        local ok, result = pcall(function()
            return HttpService:JSONDecode(readfile(name))
        end)
        return ok and result or {}
    end
    return {}
end

local function saveLastAnim()
    if getgenv().lastAnim then
        saveFile("LastAnimation.json", getgenv().lastAnim)
    end
end

local function loadLastAnim()
    local data = loadFile("LastAnimation.json")
    if data and data.id then
        getgenv().lastAnim = data
    end
end

local function extractId(url)
    return string.match(url, "Asset&id=(%d+)")
end

local function getEmoteName(id)
    local ok, info = pcall(function()
        return MarketplaceService:GetProductInfo(tonumber(id))
    end)
    return ok and info and info.Name or "Emote_" .. id
end

local function isInFav(id)
    local list = mode == "animation" and favAnims or favEmotes
    for _, v in ipairs(list) do
        if tostring(v.id) == tostring(id) then
            return true
        end
    end
    return false
end

local function getBundled(id)
    for _, src in ipairs({filteredAnims, animsData, favAnims}) do
        for _, a in ipairs(src) do
            if tostring(a.id) == tostring(id) and a.bundledItems then
                return a.bundledItems
            end
        end
    end
    return nil
end

--============ PINK THEME ============--

local function applyPinkTheme()
    local wheel = getWheel()
    if not wheel then return end
    
    -- Apply pink to wheel background
    pcall(function()
        local back = wheel:FindFirstChild("Back")
        if back then
            local background = back:FindFirstChild("Background")
            if background then
                if background:IsA("Frame") then
                    background.BackgroundColor3 = COLORS.PINK_WHEEL
                    background.BackgroundTransparency = 0.05
                end
                local overlay = background:FindFirstChild("BackgroundCircleOverlay")
                if overlay then
                    overlay.BackgroundColor3 = COLORS.PINK_LIGHT
                    overlay.BackgroundTransparency = 0.1
                end
                for _, child in pairs(background:GetChildren()) do
                    if child:IsA("ImageLabel") then
                        child.ImageColor3 = COLORS.PINK_LIGHT
                        child.ImageTransparency = 0.05
                    end
                end
            end
        end
    end)
    
    -- Update GUI elements colors
    if LeftBtn then LeftBtn.ImageColor3 = COLORS.PINK_MEDIUM end
    if RightBtn then RightBtn.ImageColor3 = COLORS.PINK_MEDIUM end
    if PagesLabel then PagesLabel.TextColor3 = COLORS.WHITE end
    if SepLabel then SepLabel.TextColor3 = COLORS.WHITE end
    if PageNumBox then PageNumBox.TextColor3 = COLORS.WHITE end
    if Top then
        Top.BackgroundColor3 = COLORS.PINK_MEDIUM
        Top.BackgroundTransparency = 0.15
    end
    if FavBtn then
        FavBtn.BackgroundColor3 = favEnabled and COLORS.PINK_HEART or COLORS.PINK_MEDIUM
        FavBtn.BackgroundTransparency = 0.15
    end
    if ModeBtn then
        ModeBtn.BackgroundColor3 = mode == "animation" and COLORS.PINK_ANIM or COLORS.PINK_MEDIUM
        ModeBtn.BackgroundTransparency = 0.15
    end
end

--============ PAGINATION ============--

local function calcPages()
    local favs = mode == "animation" and favAnims or favEmotes
    local list = mode == "animation" and filteredAnims or filteredEmotes
    local normalCount = 0
    
    for _, v in ipairs(list) do
        if not isInFav(v.id) then
            normalCount = normalCount + 1
        end
    end
    
    local pages = 0
    if #favs > 0 then
        pages = pages + math.ceil(#favs / itemsPerPage)
    end
    if normalCount > 0 then
        pages = pages + math.ceil(normalCount / itemsPerPage)
    end
    
    return math.max(pages, 1)
end

local function updatePageDisplay()
    if PagesLabel and PageNumBox then
        PagesLabel.Text = tostring(totalPages)
        PageNumBox.Text = tostring(currentPage)
    end
end

--============ ANIMATION SYSTEM ============--

local function applyAnim(data)
    if not data then
        notify("💗 Animation", "❌ No animation data", 3)
        return
    end
    
    local char = player.Character or player.CharacterAdded:Wait()
    local hum = char:FindFirstChild("Humanoid")
    local animate = char:FindFirstChild("Animate")
    
    if not animate then
        notify("💗 Animation", "❌ Animate not found", 3)
        return
    end
    
    if not hum then
        notify("💗 Animation", "❌ Humanoid not found", 3)
        return
    end
    
    local bundled = data.bundledItems or getBundled(data.id)
    if not bundled then
        notify("💗 Animation", "❌ No assets for: " .. (data.name or data.id), 3)
        return
    end
    
    -- AUTO-SAVE for respawn
    getgenv().lastAnim = {id = data.id, name = data.name, bundledItems = bundled}
    saveLastAnim()
    
    -- Stop current animations
    for _, track in pairs(hum:GetPlayingAnimationTracks()) do
        track:Stop()
    end
    
    for _, assetIds in pairs(bundled) do
        for _, assetId in pairs(assetIds) do
            spawn(function()
                local ok, objs = pcall(function()
                    return game:GetObjects("rbxassetid://" .. assetId)
                end)
                
                if ok and objs and #objs > 0 then
                    local function searchAnims(parent, path)
                        for _, child in pairs(parent:GetChildren()) do
                            if child:IsA("Animation") then
                                local parts = (path .. "." .. child.Name):split(".")
                                if #parts >= 2 then
                                    local cat = parts[#parts - 1]
                                    local name = parts[#parts]
                                    local folder = animate:FindFirstChild(cat)
                                    if folder then
                                        local slot = folder:FindFirstChild(name)
                                        if slot then
                                            slot.AnimationId = child.AnimationId
                                            task.wait(0.1)
                                            local anim = Instance.new("Animation")
                                            anim.AnimationId = child.AnimationId
                                            local animator = hum:FindFirstChild("Animator")
                                            if animator then
                                                local t = animator:LoadAnimation(anim)
                                                t.Priority = Enum.AnimationPriority.Action
                                                t:Play()
                                                task.wait(0.1)
                                                t:Stop()
                                            end
                                        end
                                    end
                                end
                            elseif #child:GetChildren() > 0 then
                                searchAnims(child, path .. "." .. child.Name)
                            end
                        end
                    end
                    
                    for _, obj in pairs(objs) do
                        searchAnims(obj, obj.Name)
                        obj.Parent = workspace
                        task.delay(1, function()
                            if obj and obj.Parent then obj:Destroy() end
                        end)
                    end
                end
            end)
        end
    end
    
    notify("💗 Animation", "✅ Applied: " .. (data.name or "Animation"), 3)
end

--============ FAVORITE ICON ============--

local function updateFavIcon(img, id, isFav)
    local icon = img:FindFirstChild("FavHeart")
    if isFav then
        if not icon then
            icon = Instance.new("TextLabel")
            icon.Name = "FavHeart"
            icon.Size = UDim2.new(0.22, 0, 0.22, 0)
            icon.Position = UDim2.new(0.76, 0, 0.02, 0)
            icon.BackgroundTransparency = 1
            icon.ZIndex = img.ZIndex + 10
            icon.Text = "💗"
            icon.TextScaled = true
            icon.Font = Enum.Font.SourceSans
            icon.Parent = img
        end
        icon.Visible = true
    elseif icon then
        icon.Visible = false
    end
end

--============ DISPLAY UPDATE ============--

local function updateDisplay()
    local char, hum = getChar()
    if not char or not hum or not hum.HumanoidDescription then return end
    
    local desc = hum.HumanoidDescription
    local favs = mode == "animation" and favAnims or favEmotes
    local list = mode == "animation" and filteredAnims or filteredEmotes
    local items = {}
    
    local favPages = #favs > 0 and math.ceil(#favs / itemsPerPage) or 0
    local inFavPages = currentPage <= favPages
    
    if inFavPages and #favs > 0 then
        local startIdx = (currentPage - 1) * itemsPerPage + 1
        local endIdx = math.min(startIdx + itemsPerPage - 1, #favs)
        for i = startIdx, endIdx do
            if favs[i] then
                local item = {id = tonumber(favs[i].id), name = favs[i].name}
                if mode == "animation" then
                    item.bundledItems = favs[i].bundledItems or getBundled(favs[i].id)
                end
                table.insert(items, item)
            end
        end
    else
        local normalList = {}
        for _, v in ipairs(list) do
            if not isInFav(v.id) then
                table.insert(normalList, v)
            end
        end
        local adjPage = currentPage - favPages
        local startIdx = (adjPage - 1) * itemsPerPage + 1
        local endIdx = math.min(startIdx + itemsPerPage - 1, #normalList)
        for i = startIdx, endIdx do
            if normalList[i] then
                table.insert(items, normalList[i])
            end
        end
    end
    
    local emoteTable = {}
    local equipped = {}
    for _, item in ipairs(items) do
        emoteTable[item.name] = {item.id}
        table.insert(equipped, item.name)
    end
    
    desc:SetEmotes(emoteTable)
    desc:SetEquippedEmotes(equipped)
    
    -- Update wheel images
    task.delay(0.1, function()
        local wheel = getWheel()
        if not wheel then return end
        
        pcall(function()
            local front = wheel:FindFirstChild("Front")
            if not front then return end
            local btns = front:FindFirstChild("EmotesButtons")
            if not btns then return end
            
            if mode == "animation" then
                local idx = 1
                for _, child in pairs(btns:GetChildren()) do
                    if child:IsA("ImageLabel") then
                        if idx <= #items then
                            child.Image = "rbxthumb://type=BundleThumbnail&id=" .. items[idx].id .. "&w=420&h=420"
                            
                            local idVal = child:FindFirstChild("AnimID")
                            if not idVal then
                                idVal = Instance.new("IntValue")
                                idVal.Name = "AnimID"
                                idVal.Parent = child
                            end
                            idVal.Value = items[idx].id
                            
                            updateFavIcon(child, items[idx].id, isInFav(items[idx].id))
                            child.Active = not favEnabled
                            idx = idx + 1
                        else
                            child.Image = ""
                            local idVal = child:FindFirstChild("AnimID")
                            if idVal then idVal:Destroy() end
                        end
                    end
                end
            else
                for _, child in pairs(btns:GetChildren()) do
                    if child:IsA("ImageLabel") and child.Image ~= "" then
                        local id = extractId(child.Image)
                        if id then
                            updateFavIcon(child, id, isInFav(id))
                        end
                        child.Active = not favEnabled
                    end
                end
            end
        end)
    end)
end

--============ FAVORITES ============--

local function toggleFav(id, name, bundled)
    local list = mode == "animation" and favAnims or favEmotes
    local found, idx = false, 0
    
    for i, v in ipairs(list) do
        if tostring(v.id) == tostring(id) then
            found, idx = true, i
            break
        end
    end
    
    if found then
        table.remove(list, idx)
        notify("💗 Favorites", "Removed: " .. name, 3)
    else
        local entry = {id = id, name = name .. " 💗"}
        if mode == "animation" then
            entry.bundledItems = bundled or getBundled(id)
        end
        table.insert(list, entry)
        notify("💗 Favorites", "Added: " .. name, 3)
    end
    
    local fileName = mode == "animation" and "FavoriteAnimations.json" or "FavoriteEmotes.json"
    saveFile(fileName, list)
    
    totalPages = calcPages()
    updatePageDisplay()
    updateDisplay()
end

--============ WHEEL CLICK HANDLER ============--

local function handleSector(index)
    if tick() - lastAction < 0.25 then return end
    lastAction = tick()
    task.wait(0.05)
    
    local favs = mode == "animation" and favAnims or favEmotes
    local list = mode == "animation" and filteredAnims or filteredEmotes
    local favPages = #favs > 0 and math.ceil(#favs / itemsPerPage) or 0
    
    local item
    if currentPage <= favPages and #favs > 0 then
        local startIdx = (currentPage - 1) * itemsPerPage
        item = favs[startIdx + index]
        if item and mode == "animation" and not item.bundledItems then
            item.bundledItems = getBundled(item.id)
        end
    else
        local normalList = {}
        for _, v in ipairs(list) do
            if not isInFav(v.id) then
                table.insert(normalList, v)
            end
        end
        local adjPage = currentPage - favPages
        local startIdx = (adjPage - 1) * itemsPerPage
        item = normalList[startIdx + index]
    end
    
    if not item then return end
    
    if favEnabled then
        toggleFav(item.id, item.name, item.bundledItems)
    elseif mode == "animation" then
        applyAnim(item)
    end
end

-- Input detection
UserInputService.InputBegan:Connect(function(input)
    if mode ~= "animation" and not favEnabled then return end
    if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
    
    local wheel = getWheel()
    if not wheel or (not wheel.Visible and tick() - lastWheelVisible > 0.15) then return end
    
    local pos = Vector2.new(input.Position.X, input.Position.Y)
    local aPos = wheel.AbsolutePosition
    local aSize = wheel.AbsoluteSize
    
    if pos.X < aPos.X or pos.X > aPos.X + aSize.X or pos.Y < aPos.Y or pos.Y > aPos.Y + aSize.Y then return end
    
    local center = aPos + aSize / 2
    local dx = pos.X - center.X
    local dy = pos.Y - center.Y
    local distance = math.sqrt(dx * dx + dy * dy)
    
    if distance < aSize.X * 0.1 then return end
    
    local angle = math.deg(math.atan2(dy, dx))
    local correctedAngle = (angle + 90 + 22.5) % 360
    local sectorIndex = math.floor(correctedAngle / 45) + 1
    
    handleSector(sectorIndex)
end)

-- Track wheel visibility
RunService.Heartbeat:Connect(function()
    pcall(function()
        local wheel = getWheel()
        if wheel and wheel.Visible then
            lastWheelVisible = tick()
        end
    end)
end)

--============ DATA FETCHING ============--

local function fetchEmotes()
    if isLoading then return end
    isLoading = true
    
    local ok, result = pcall(function()
        local json = game:HttpGet(EMOTE_URL)
        return HttpService:JSONDecode(json)
    end)
    
    if ok and result then
        emotesData = {}
        local list = result.data or result
        for _, item in ipairs(list) do
            local id = tonumber(item.id)
            if id and id > 0 then
                table.insert(emotesData, {id = id, name = item.name or ("Emote_" .. id)})
            end
        end
        filteredEmotes = emotesData
    end
    
    isLoading = false
end

local function fetchAnims()
    if isLoading then return end
    isLoading = true
    
    local ok, result = pcall(function()
        local json = game:HttpGet(ANIM_URL)
        return HttpService:JSONDecode(json)
    end)
    
    if ok and result then
        animsData = {}
        local list = result.data or result
        for _, item in ipairs(list) do
            local id = tonumber(item.id)
            if id and id > 0 then
                table.insert(animsData, {
                    id = id,
                    name = item.name or ("Anim_" .. id),
                    bundledItems = item.bundledItems
                })
            end
        end
        filteredAnims = animsData
    end
    
    isLoading = false
end

--============ SEARCH ============--

local function searchItems(term)
    term = term:lower()
    local source = mode == "animation" and animsData or emotesData
    
    if term == "" then
        if mode == "animation" then
            filteredAnims = animsData
        else
            filteredEmotes = emotesData
        end
    else
        local result = {}
        local isIdSearch = term:match("^%d+$")
        
        for _, v in ipairs(source) do
            if (isIdSearch and tostring(v.id) == term) or (not isIdSearch and v.name:lower():find(term)) then
                table.insert(result, v)
            end
        end
        
        if mode == "animation" then
            filteredAnims = result
        else
            filteredEmotes = result
        end
    end
    
    currentPage = 1
    totalPages = calcPages()
    updatePageDisplay()
    updateDisplay()
end

--============ NAVIGATION ============--

local function prevPage()
    currentPage = currentPage <= 1 and totalPages or currentPage - 1
    updatePageDisplay()
    updateDisplay()
end

local function nextPage()
    currentPage = currentPage >= totalPages and 1 or currentPage + 1
    updatePageDisplay()
    updateDisplay()
end

local function goToPage(num)
    currentPage = math.clamp(num, 1, totalPages)
    updatePageDisplay()
    updateDisplay()
end

--============ MODE & FAV TOGGLE ============--

local function toggleMode()
    mode = mode == "emote" and "animation" or "emote"
    
    if mode == "animation" and #animsData == 0 then
        fetchAnims()
    end
    
    if Search then Search.Text = "" end
    
    if mode == "animation" then
        filteredAnims = animsData
    else
        filteredEmotes = emotesData
    end
    
    currentPage = 1
    totalPages = calcPages()
    updatePageDisplay()
    updateDisplay()
    applyPinkTheme()
    
    notify("💗 Mode", mode == "animation" and "🎬 Animation Mode" or "💃 Emote Mode", 3)
end

local function toggleFavMode()
    favEnabled = not favEnabled
    applyPinkTheme()
    notify("💗 Favorites", favEnabled and "Click to add hearts!" or "Favorite mode OFF", 3)
    updateDisplay()
end

--============ GUI CREATION ============--

local function createGUI()
    local wheel = getWheel()
    if not wheel then return false end
    
    -- Clean old elements
    for _, name in ipairs({"Under", "Top", "Favorite", "ModeToggle"}) do
        local existing = wheel:FindFirstChild(name)
        if existing then existing:Destroy() end
    end
    
    -- Bottom navigation bar
    Under = Instance.new("Frame")
    Under.Name = "Under"
    Under.Parent = wheel
    Under.BackgroundTransparency = 1
    Under.BorderSizePixel = 0
    Under.Position = UDim2.new(0.13, 0, 1, 0)
    Under.Size = UDim2.new(0.74, 0, 0.13, 0)
    
    local underLayout = Instance.new("UIListLayout")
    underLayout.Parent = Under
    underLayout.FillDirection = Enum.FillDirection.Horizontal
    underLayout.VerticalAlignment = Enum.VerticalAlignment.Center
    underLayout.SortOrder = Enum.SortOrder.LayoutOrder
    
    -- Left arrow
    LeftBtn = Instance.new("ImageButton")
    LeftBtn.Name = "LeftBtn"
    LeftBtn.Parent = Under
    LeftBtn.LayoutOrder = 1
    LeftBtn.BackgroundTransparency = 1
    LeftBtn.Size = UDim2.new(0.17, 0, 0.94, 0)
    LeftBtn.Image = "rbxassetid://93111945058621"
    LeftBtn.ImageColor3 = COLORS.PINK_MEDIUM
    
    -- Page number input
    PageNumBox = Instance.new("TextBox")
    PageNumBox.Name = "PageNum"
    PageNumBox.Parent = Under
    PageNumBox.LayoutOrder = 2
    PageNumBox.BackgroundTransparency = 1
    PageNumBox.Size = UDim2.new(0.16, 0, 0.81, 0)
    PageNumBox.Font = Enum.Font.GothamBold
    PageNumBox.Text = "1"
    PageNumBox.TextColor3 = COLORS.WHITE
    PageNumBox.TextScaled = true
    
    -- Separator
    SepLabel = Instance.new("TextLabel")
    SepLabel.Name = "Separator"
    SepLabel.Parent = Under
    SepLabel.LayoutOrder = 3
    SepLabel.BackgroundTransparency = 1
    SepLabel.Size = UDim2.new(0.34, 0, 0.94, 0)
    SepLabel.Font = Enum.Font.GothamBold
    SepLabel.Text = " --- "
    SepLabel.TextColor3 = COLORS.WHITE
    SepLabel.TextScaled = true
    
    -- Total pages
    PagesLabel = Instance.new("TextLabel")
    PagesLabel.Name = "TotalPages"
    PagesLabel.Parent = Under
    PagesLabel.LayoutOrder = 4
    PagesLabel.BackgroundTransparency = 1
    PagesLabel.Size = UDim2.new(0.16, 0, 0.81, 0)
    PagesLabel.Font = Enum.Font.GothamBold
    PagesLabel.Text = "1"
    PagesLabel.TextColor3 = COLORS.WHITE
    PagesLabel.TextScaled = true
    
    -- Right arrow
    RightBtn = Instance.new("ImageButton")
    RightBtn.Name = "RightBtn"
    RightBtn.Parent = Under
    RightBtn.LayoutOrder = 5
    RightBtn.BackgroundTransparency = 1
    RightBtn.Size = UDim2.new(0.17, 0, 0.94, 0)
    RightBtn.Image = "rbxassetid://107938916240738"
    RightBtn.ImageColor3 = COLORS.PINK_MEDIUM
    
    -- Top search bar
    Top = Instance.new("Frame")
    Top.Name = "Top"
    Top.Parent = wheel
    Top.BackgroundColor3 = COLORS.PINK_MEDIUM
    Top.BackgroundTransparency = 0.15
    Top.BorderSizePixel = 0
    Top.Position = UDim2.new(0.13, 0, -0.11, 0)
    Top.Size = UDim2.new(0.74, 0, 0.095, 0)
    
    local topCorner = Instance.new("UICorner")
    topCorner.CornerRadius = UDim.new(0, 20)
    topCorner.Parent = Top
    
    local topLayout = Instance.new("UIListLayout")
    topLayout.Parent = Top
    topLayout.FillDirection = Enum.FillDirection.Horizontal
    topLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    topLayout.VerticalAlignment = Enum.VerticalAlignment.Center
    
    Search = Instance.new("TextBox")
    Search.Name = "Search"
    Search.Parent = Top
    Search.BackgroundTransparency = 1
    Search.Size = UDim2.new(0.87, 0, 0.82, 0)
    Search.Font = Enum.Font.GothamBold
    Search.PlaceholderText = "Search/ID"
    Search.PlaceholderColor3 = COLORS.PLACEHOLDER
    Search.Text = ""
    Search.TextColor3 = COLORS.WHITE
    Search.TextScaled = true
    
    -- Favorite button
    FavBtn = Instance.new("ImageButton")
    FavBtn.Name = "Favorite"
    FavBtn.Parent = wheel
    FavBtn.BackgroundColor3 = COLORS.PINK_MEDIUM
    FavBtn.BackgroundTransparency = 0.15
    FavBtn.BorderSizePixel = 0
    FavBtn.Position = UDim2.new(0.019, 0, -0.108, 0)
    FavBtn.Size = UDim2.new(0.0875, 0, 0.0875, 0)
    FavBtn.Image = ""
    
    local favCorner = Instance.new("UICorner")
    favCorner.CornerRadius = UDim.new(0, 10)
    favCorner.Parent = FavBtn
    
    local favText = Instance.new("TextLabel")
    favText.Parent = FavBtn
    favText.BackgroundTransparency = 1
    favText.Size = UDim2.new(1, 0, 1, 0)
    favText.Font = Enum.Font.SourceSans
    favText.Text = "💗"
    favText.TextScaled = true
    favText.ZIndex = FavBtn.ZIndex + 1
    
    -- Mode toggle button
    ModeBtn = Instance.new("ImageButton")
    ModeBtn.Name = "ModeToggle"
    ModeBtn.Parent = wheel
    ModeBtn.BackgroundColor3 = COLORS.PINK_MEDIUM
    ModeBtn.BackgroundTransparency = 0.15
    ModeBtn.BorderSizePixel = 0
    ModeBtn.Position = UDim2.new(0.889, 0, -0.108, 0)
    ModeBtn.Size = UDim2.new(0.0875, 0, 0.0875, 0)
    ModeBtn.Image = ""
    
    local modeCorner = Instance.new("UICorner")
    modeCorner.CornerRadius = UDim.new(0, 10)
    modeCorner.Parent = ModeBtn
    
    local modeText = Instance.new("TextLabel")
    modeText.Parent = ModeBtn
    modeText.BackgroundTransparency = 1
    modeText.Size = UDim2.new(1, 0, 1, 0)
    modeText.Font = Enum.Font.SourceSans
    modeText.Text = "🎬"
    modeText.TextScaled = true
    modeText.ZIndex = ModeBtn.ZIndex + 1
    
    -- Connect events
    LeftBtn.MouseButton1Click:Connect(prevPage)
    RightBtn.MouseButton1Click:Connect(nextPage)
    
    PageNumBox.FocusLost:Connect(function()
        local num = tonumber(PageNumBox.Text)
        if num then
            goToPage(num)
        else
            PageNumBox.Text = tostring(currentPage)
        end
    end)
    
    Search:GetPropertyChangedSignal("Text"):Connect(function()
        searchItems(Search.Text)
    end)
    
    FavBtn.MouseButton1Click:Connect(toggleFavMode)
    ModeBtn.MouseButton1Click:Connect(toggleMode)
    
    applyPinkTheme()
    guiCreated = true
    
    return true
end

--============ CHARACTER HANDLING ============--

local function onCharacterAdded(char)
    local hum = char:WaitForChild("Humanoid")
    
    -- AUTO-RELOAD animation on respawn
    if getgenv().lastAnim and getgenv().lastAnim.id then
        task.wait(0.5)
        applyAnim(getgenv().lastAnim)
        notify("💗 Auto-Reload", "🔄 Animation restored!", 3)
    end
    
    hum.Died:Connect(function()
        favEnabled = false
    end)
end

if player.Character then
    onCharacterAdded(player.Character)
end

player.CharacterAdded:Connect(function(char)
    favEnabled = false
    wheelCache = nil
    
    onCharacterAdded(char)
    
    task.spawn(function()
        task.wait(0.3)
        while not getWheel() do
            task.wait(0.1)
        end
        task.wait(0.3)
        if createGUI() then
            updatePageDisplay()
            updateDisplay()
        end
    end)
end)

--============ MAIN LOOPS ============--

local frameCount = 0
RunService.RenderStepped:Connect(function()
    frameCount = frameCount + 1
    if frameCount >= 30 then
        frameCount = 0
        if not guiCreated then
            local wheel = getWheel()
            if wheel and createGUI() then
                updatePageDisplay()
                updateDisplay()
            end
        else
            applyPinkTheme()
        end
    end
end)

-- Initial setup
task.spawn(function()
    while not getWheel() do
        task.wait(0.1)
    end
    
    if createGUI() then
        favEmotes = loadFile("FavoriteEmotes.json")
        favAnims = loadFile("FavoriteAnimations.json")
        loadLastAnim()
        
        fetchEmotes()
        fetchAnims()
        
        totalPages = calcPages()
        updatePageDisplay()
        updateDisplay()
        
        notify("💗 PinkWards", "Loaded! Press '.' to open", 5)
    end
end)

StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Chat, true)

-- Keep emotes menu alive
task.spawn(function()
    while true do
        pcall(function()
            local robloxGui = CoreGui:FindFirstChild("RobloxGui")
            local emotesMenu = robloxGui and robloxGui:FindFirstChild("EmotesMenu")
            
            if not emotesMenu then
                StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.EmotesMenu, true)
            else
                local wheel = getWheel()
                if wheel and not wheel:FindFirstChild("Under") then
                    createGUI()
                    updatePageDisplay()
                end
            end
        end)
        task.wait(1)
    end
end)

-- Mobile button
if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
    pcall(function()
        local gui = Instance.new("ScreenGui")
        gui.Name = "EmoteOpenBtn"
        gui.ResetOnSpawn = false
        
        if syn and syn.protect_gui then
            syn.protect_gui(gui)
            gui.Parent = CoreGui
        elseif gethui then
            gui.Parent = gethui()
        else
            gui.Parent = CoreGui
        end
        
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(0, 55, 0, 55)
        btn.Position = UDim2.new(0, 10, 0.5, -27)
        btn.BackgroundColor3 = COLORS.PINK_MEDIUM
        btn.BackgroundTransparency = 0.15
        btn.Text = "💗"
        btn.TextSize = 28
        btn.TextColor3 = COLORS.WHITE
        btn.Parent = gui
        
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 12)
        corner.Parent = btn
        
        btn.MouseButton1Click:Connect(function()
            pcall(function()
                GuiService:SetEmotesMenuOpen(true)
            end)
        end)
    end)
    
    notify("💗 Mobile", "Tap the heart to open!", 10)
end

print("=========================================")
print("   💗 PinkWards Emote + Animation System")
print("   Press '.' to open")
print("   🎬 = Toggle Animation Mode")
print("   💗 = Favorite Mode")
print("   ✅ Auto-saves animations on respawn!")
print("=========================================")
