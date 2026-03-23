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
local ContextActionService = game:GetService("ContextActionService")
local ContentProvider = game:GetService("ContentProvider")

local player = Players.LocalPlayer
local EMOTE_URL = "https://raw.githubusercontent.com/PinkWards/emote-sniper/refs/heads/main/EmoteSniper.json"
local ANIM_URL = "https://raw.githubusercontent.com/PinkWards/emote-sniper/refs/heads/main/AnimationSniper.json"

-- ============ STATE ============ --
local State = {
    mode = "emote",
    currentPage = 1,
    itemsPerPage = 8,
    totalPages = 1,
    emotesData = {},
    animsData = {},
    filteredEmotes = {},
    filteredAnims = {},
    favEmotes = {},
    favAnims = {},
    favEnabled = false,
    isLoading = false,
    currentEmoteTrack = nil,
    lastWheelVisible = 0,
    lastAction = 0,
    favSetVersion = 0,
    guiCreated = false,
    wheelCache = nil,
    lastWheelCheck = 0,
    autoReapplyEnabled = true,
    favFileName = "FavoriteEmotes.json",
    favAnimFileName = "FavoriteAnimations.json",
    favLookupEmote = {},
    favLookupAnim = {},
    normalListCache = nil,
    normalListCacheVersion = -1,
    normalListCacheMode = "",
    searchDebounce = nil,
    lastSearchTerm = "",
    needsDisplayRefresh = false,
    lastDisplayPage = -1,
    lastDisplayMode = "",
    lastDisplayFavVer = -1,
    
    randomEnabled = true,
    randomMode = "All",
    currentOperationToken = 0,
    imageUpdateToken = 0,
    hudEditorActive = false,
    targetImages = {},
    favoriteIconId = "rbxassetid://97307461910825",
    notFavoriteIconId = "rbxassetid://124025954365505",
    config = {
        NotifyEnabled = true,
        SearchVisible = true,
        FavVisible = true,
        ModeVisible = true,
        NavVisible = true,
        HUDPositions = {},
        SelectedTheme = "Default",
        RandomEnabled = true,
        RandomMode = "All",
        EmotePage = 1,
        AnimationPage = 1,
    }
}

getgenv().lastAnim = getgenv().lastAnim or nil

-- ============ CONFIG SYSTEM ============ --
local ConfigPath = "PinkWards/Config.json"

local function SaveConfig()
    if not isfolder then return end
    if not isfolder("PinkWards") then 
        pcall(function() makefolder("PinkWards") end)
    end
    pcall(function()
        writefile(ConfigPath, HttpService:JSONEncode(State.config))
    end)
end

local function LoadConfig()
    if isfile and isfile(ConfigPath) then
        local ok, data = pcall(function()
            return HttpService:JSONDecode(readfile(ConfigPath))
        end)
        if ok and data then
            for k, v in pairs(data) do
                State.config[k] = v
            end
        end
    end
    State.randomEnabled = State.config.RandomEnabled
    State.randomMode = State.config.RandomMode
end

-- ============ THEME SYSTEM ============ --
local Themes = {}
local ThemeConfigPath = "PinkWards/Themes.json"
local currentThemeName = "Default"

local DefaultTheme = {
    Background = {30, 30, 30},
    Accent = {0, 162, 255},
    ImageColor = {255, 255, 255},
    IconColors = {
        Left = {180, 180, 180},
        Right = {180, 180, 180},
        Favorite = {255, 170, 50},
        NotFavorite = {120, 120, 120},
        Mode = {255, 255, 255},
        Auto = {255, 255, 255}
    },
    Icons = {
        Left = "93111945058621",
        Right = "107938916240738",
        Favorite = "97307461910825",
        NotFavorite = "124025954365505",
        Mode = "13285615740",
        Auto = "127493377027615"
    }
}

local function SaveThemes()
    if not isfolder then return end
    if not isfolder("PinkWards") then 
        pcall(function() makefolder("PinkWards") end)
    end
    local toSave = { Themes = {}, Selected = currentThemeName }
    for name, data in pairs(Themes) do
        if name ~= "Default" then
            toSave.Themes[name] = data
        end
    end
    pcall(function()
        writefile(ThemeConfigPath, HttpService:JSONEncode(toSave))
    end)
end

local function LoadThemes()
    Themes = { Default = DefaultTheme }
    if isfile and isfile(ThemeConfigPath) then
        local ok, data = pcall(function()
            return HttpService:JSONDecode(readfile(ThemeConfigPath))
        end)
        if ok and data then
            for name, theme in pairs(data.Themes or {}) do
                Themes[name] = theme
            end
            if data.Selected and Themes[data.Selected] then
                currentThemeName = data.Selected
            end
        end
    end
end

local function GetIconColor(key)
    local theme = Themes[currentThemeName]
    if theme and theme.IconColors and theme.IconColors[key] then
        local c = theme.IconColors[key]
        return Color3.fromRGB(c[1], c[2], c[3])
    end
    return Color3.fromRGB(255, 255, 255)
end

local function TableToColor(t)
    if not t then return Color3.fromRGB(255, 255, 255) end
    return Color3.fromRGB(t[1] or 255, t[2] or 255, t[3] or 255)
end

local function ColorToTable(c)
    return {math.round(c.R * 255), math.round(c.G * 255), math.round(c.B * 255)}
end

-- ============ UTILITIES ============ --
local function notify(title, content, duration)
    if not State.config.NotifyEnabled then return end
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = title or "PinkWards",
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
    if State.wheelCache and State.wheelCache.Parent and t - State.lastWheelCheck < 1 then
        return State.wheelCache
    end
    State.lastWheelCheck = t
    local ok, w = pcall(function()
        return CoreGui.RobloxGui.EmotesMenu.Children.Main.EmotesWheel
    end)
    State.wheelCache = ok and w or nil
    return State.wheelCache
end

local function saveFile(name, data)
    if writefile then
        if not isfolder("PinkWards") then 
            pcall(function() makefolder("PinkWards") end)
        end
        pcall(function() writefile("PinkWards/" .. name, HttpService:JSONEncode(data)) end)
    end
end

local function loadFile(name)
    if readfile and isfile and isfile("PinkWards/" .. name) then
        local ok, res = pcall(function()
            return HttpService:JSONDecode(readfile("PinkWards/" .. name))
        end)
        return ok and res or {}
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

-- ============ FAST FAVORITE LOOKUP ============ --
local function rebuildFavLookup()
    State.favLookupEmote = {}
    for _, v in ipairs(State.favEmotes) do
        State.favLookupEmote[tostring(v.id)] = true
    end
    State.favLookupAnim = {}
    for _, v in ipairs(State.favAnims) do
        State.favLookupAnim[tostring(v.id)] = true
    end
    State.normalListCacheVersion = -1
    State.favSetVersion = State.favSetVersion + 1
end

local function isInFav(id)
    local lookup = State.mode == "animation" and State.favLookupAnim or State.favLookupEmote
    return lookup[tostring(id)] == true
end

local function getBundled(id)
    for _, src in ipairs({State.filteredAnims, State.animsData, State.favAnims}) do
        for _, a in ipairs(src) do
            if tostring(a.id) == tostring(id) and a.bundledItems then
                return a.bundledItems
            end
        end
    end
    return nil
end

-- ============ NORMAL LIST CACHE ============ --
local function getNormalList()
    local list = State.mode == "animation" and State.filteredAnims or State.filteredEmotes
    local version = State.favSetVersion

    if State.normalListCache
        and State.normalListCacheVersion == version
        and State.normalListCacheMode == State.mode then
        return State.normalListCache
    end

    local result = {}
    local lookup = State.mode == "animation" and State.favLookupAnim or State.favLookupEmote

    for i = 1, #list do
        if not lookup[tostring(list[i].id)] then
            result[#result + 1] = list[i]
        end
    end

    State.normalListCache = result
    State.normalListCacheVersion = version
    State.normalListCacheMode = State.mode
    return result
end

-- ============ RANDOM SLOT ============ --
local function shouldRandomSlotBeShown()
    if not State.randomEnabled then return false end
    if State.searchDebounce and State.lastSearchTerm ~= "" then return false end
    return true
end

local function getRandomSourceList()
    if not State.randomEnabled then return {} end
    if State.randomMode == "Favorites" then
        return State.mode == "animation" and State.favAnims or State.favEmotes
    end
    return State.mode == "animation" and State.filteredAnims or State.filteredEmotes
end

local function pickRandomItem()
    local list = getRandomSourceList()
    if #list == 0 then return nil end
    return list[math.random(1, #list)]
end

-- ============ ANIMATION SYSTEM ============ --
local loadedTracks = {}
local currentLoadId = 0

local function cleanupAllTracks()
    for i = #loadedTracks, 1, -1 do
        local track = loadedTracks[i]
        if track then
            pcall(function()
                track:Stop(0)
                track:Destroy()
            end)
        end
    end
    loadedTracks = {}
    State.currentEmoteTrack = nil
end

local function forceResetAnimator()
    local _, hum = getChar()
    if not hum then return end

    pcall(function()
        local animator = hum:FindFirstChild("Animator")
        if animator then
            for _, track in pairs(animator:GetPlayingAnimationTracks()) do
                track:Stop(0)
                track:Destroy()
            end
        end
    end)

    pcall(function()
        hum:ChangeState(Enum.HumanoidStateType.GettingUp)
        task.wait(0.05)
        hum:ChangeState(Enum.HumanoidStateType.Running)
    end)
end

local function stopCurrentEmote()
    currentLoadId = currentLoadId + 1

    if State.currentEmoteTrack then
        pcall(function()
            State.currentEmoteTrack:Stop(0)
            State.currentEmoteTrack:Destroy()
        end)
        State.currentEmoteTrack = nil
    end

    for i = #loadedTracks, 1, -1 do
        local track = loadedTracks[i]
        local isPlaying = false
        pcall(function() isPlaying = track.IsPlaying end)
        if not isPlaying then
            pcall(function()
                track:Stop(0)
                track:Destroy()
            end)
            table.remove(loadedTracks, i)
        end
    end
end

local function playEmote(emoteId)
    local char, hum = getChar()
    if not hum then return false end

    stopCurrentEmote()

    currentLoadId = currentLoadId + 1
    local myLoadId = currentLoadId

    if #loadedTracks >= 25 then
        cleanupAllTracks()
        forceResetAnimator()
        task.wait(0.1)
        char, hum = getChar()
        if not hum then return false end
    end

    local animator = hum:FindFirstChild("Animator")
    if not animator then return false end

    pcall(function()
        for _, track in pairs(animator:GetPlayingAnimationTracks()) do
            if track.Priority == Enum.AnimationPriority.Action then
                track:Stop(0)
            end
        end
    end)

    local anim = Instance.new("Animation")
    anim.AnimationId = "rbxassetid://" .. emoteId

    local ok, track = pcall(function()
        return animator:LoadAnimation(anim)
    end)

    pcall(function() anim:Destroy() end)

    if myLoadId ~= currentLoadId then
        if ok and track then
            pcall(function() track:Stop(0); track:Destroy() end)
        end
        return false
    end

    if not ok or not track then
        forceResetAnimator()
        return false
    end

    pcall(function()
        track.Priority = Enum.AnimationPriority.Action
        track.Looped = true
    end)

    if myLoadId ~= currentLoadId then
        pcall(function() track:Stop(0); track:Destroy() end)
        return false
    end

    local playOk = pcall(function()
        track:Play(0.1)
    end)

    if not playOk then
        pcall(function() track:Stop(0); track:Destroy() end)
        forceResetAnimator()
        return false
    end

    if myLoadId ~= currentLoadId then
        pcall(function() track:Stop(0); track:Destroy() end)
        return false
    end

    State.currentEmoteTrack = track
    table.insert(loadedTracks, track)

    track.Stopped:Connect(function()
        if State.currentEmoteTrack == track then
            State.currentEmoteTrack = nil
        end
    end)

    return true
end

local function applyAnim(data)
    if not data then
        notify("Animation", "No animation data", 3)
        return
    end

    local char = player.Character or player.CharacterAdded:Wait()
    local hum = char:FindFirstChild("Humanoid")
    local animate = char:FindFirstChild("Animate")

    if not animate then
        notify("Animation", "Animate not found", 3)
        return
    end

    if not hum then
        notify("Animation", "Humanoid not found", 3)
        return
    end

    local bundled = data.bundledItems or getBundled(data.id)
    if not bundled then
        notify("Animation", "No assets for: " .. (data.name or data.id), 3)
        return
    end

    getgenv().lastAnim = {id = data.id, name = data.name, bundledItems = bundled}
    saveLastAnim()

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

    notify("Animation", "Applied: " .. (data.name or "Animation"), 3)
end

-- ============ FAVORITE STAR OVERLAY ============ --
local function updateFavIcon(img, id, isFav)
    local star = img:FindFirstChild("FavStar")
    if isFav then
        if not star then
            star = Instance.new("ImageLabel")
            star.Name = "FavStar"
            star.Size = UDim2.new(0.25, 0, 0.25, 0)
            star.Position = UDim2.new(0.7, 0, 0, 0)
            star.BackgroundTransparency = 1
            star.ZIndex = img.ZIndex + 10
            star.Image = State.favoriteIconId
            star.ScaleType = Enum.ScaleType.Fit
            star.Parent = img
        end
        star.Visible = true
        star.ImageColor3 = GetIconColor("Favorite")
    elseif star then
        star.Visible = false
    end
end

-- ============ DISPLAY UPDATE (OPTIMIZED WITH RANDOM SLOT) ============ --
local function updateDisplay(force)
    if not force
        and State.lastDisplayPage == State.currentPage
        and State.lastDisplayMode == State.mode
        and State.lastDisplayFavVer == State.favSetVersion then
        return
    end

    local char, hum = getChar()
    if not char or not hum then return end

    local desc = hum:FindFirstChildOfClass("HumanoidDescription")
    if not desc then
        for i = 1, 10 do
            task.wait(0.1)
            desc = hum:FindFirstChildOfClass("HumanoidDescription")
            if desc then break end
        end
        if not desc then return end
    end

    State.lastDisplayPage = State.currentPage
    State.lastDisplayMode = State.mode
    State.lastDisplayFavVer = State.favSetVersion

    local favs = State.mode == "animation" and State.favAnims or State.favEmotes
    local items = {}
    local randomSlotActive = shouldRandomSlotBeShown()
    
    local itemsPerPage = randomSlotActive and (State.itemsPerPage - 1) or State.itemsPerPage
    local favPages = #favs > 0 and math.ceil(#favs / itemsPerPage) or 0
    local inFavPages = State.currentPage <= favPages

    if inFavPages and #favs > 0 then
        local startIdx = (State.currentPage - 1) * itemsPerPage + 1
        local endIdx = math.min(startIdx + itemsPerPage - 1, #favs)
        for i = startIdx, endIdx do
            if favs[i] then
                local item = {id = tonumber(favs[i].id), name = favs[i].name}
                if State.mode == "animation" then
                    item.bundledItems = favs[i].bundledItems or getBundled(favs[i].id)
                end
                items[#items + 1] = item
            end
        end
    else
        local normalList = getNormalList()
        local adjPage = State.currentPage - favPages
        local startIdx = (adjPage - 1) * itemsPerPage + 1
        local endIdx = math.min(startIdx + itemsPerPage - 1, #normalList)
        for i = startIdx, endIdx do
            if normalList[i] then items[#items + 1] = normalList[i] end
        end
    end

    local emoteTable = {}
    local equipped = {}
    
    if randomSlotActive then
        emoteTable["🎲 Random"] = {0}
        equipped[#equipped + 1] = "🎲 Random"
    end
    
    for _, item in ipairs(items) do
        emoteTable[item.name] = {item.id}
        equipped[#equipped + 1] = item.name
    end

    pcall(function()
        desc:SetEmotes(emoteTable)
        desc:SetEquippedEmotes(equipped)
    end)

    local token = State.currentOperationToken + 1
    State.currentOperationToken = token
    
    task.delay(0.15, function()
        if token ~= State.currentOperationToken then return end
        
        local wheel = getWheel()
        if not wheel then return end

        pcall(function()
            local front = wheel:FindFirstChild("Front")
            if not front then return end
            local btns = front:FindFirstChild("EmotesButtons")
            if not btns then return end

            local slotIndex = 1
            local buttonList = {}
            for _, child in pairs(btns:GetChildren()) do
                if child:IsA("ImageLabel") then
                    buttonList[#buttonList + 1] = child
                end
            end
            
            table.sort(buttonList, function(a, b)
                return tonumber(a.Name) < tonumber(b.Name)
            end)

            if randomSlotActive then
                local randomSlot = buttonList[1]
                if randomSlot then
                    randomSlot.Image = "rbxassetid://109283577128136"
                    randomSlot.ImageColor3 = Color3.fromRGB(188, 188, 188)
                    local star = randomSlot:FindFirstChild("FavStar")
                    if star then star.Visible = false end
                end
                slotIndex = 2
            end

            for i = slotIndex, #buttonList do
                local child = buttonList[i]
                local itemIdx = i - (randomSlotActive and 1 or 0)
                if itemIdx <= #items then
                    local item = items[itemIdx]
                    if State.mode == "animation" then
                        child.Image = "rbxthumb://type=BundleThumbnail&id=" .. item.id .. "&w=420&h=420"
                        local idVal = child:FindFirstChild("AnimID")
                        if not idVal then
                            idVal = Instance.new("IntValue")
                            idVal.Name = "AnimID"
                            idVal.Parent = child
                        end
                        idVal.Value = item.id
                    else
                        child.Image = "rbxthumb://type=Asset&id=" .. item.id .. "&w=420&h=420"
                    end
                    updateFavIcon(child, item.id, isInFav(item.id))
                    child.Active = not State.favEnabled
                    child.ImageColor3 = Color3.new(1, 1, 1)
                else
                    child.Image = ""
                    local idVal = child:FindFirstChild("AnimID")
                    if idVal then idVal:Destroy() end
                    local star = child:FindFirstChild("FavStar")
                    if star then star.Visible = false end
                end
            end
        end)
    end)
end

-- ============ PAGINATION ============ --
local function calcPages()
    local favs = State.mode == "animation" and State.favAnims or State.favEmotes
    local normalList = getNormalList()
    local randomSlotActive = shouldRandomSlotBeShown()
    local itemsPerPage = randomSlotActive and (State.itemsPerPage - 1) or State.itemsPerPage

    local pages = 0
    if #favs > 0 then pages = pages + math.ceil(#favs / itemsPerPage) end
    if #normalList > 0 then pages = pages + math.ceil(#normalList / itemsPerPage) end
    return math.max(pages, 1)
end

local function updatePageDisplay()
    if UI.PagesLabel and UI.PageNumBox then
        UI.PagesLabel.Text = tostring(State.totalPages)
        UI.PageNumBox.Text = tostring(State.currentPage)
    end
end

-- ============ WHEEL CLICK HANDLER WITH RANDOM SUPPORT ============ --
local function handleSector(index)
    if tick() - State.lastAction < 0.35 then return end
    State.lastAction = tick()

    local randomSlotActive = shouldRandomSlotBeShown()
    
    if randomSlotActive and index == 1 then
        local randomItem = pickRandomItem()
        if not randomItem then
            notify("Random", "No items available", 3)
            return
        end
        
        if State.favEnabled then
            if State.mode == "animation" then
                toggleFav(randomItem.id, randomItem.name, randomItem.bundledItems)
            else
                toggleFav(randomItem.id, randomItem.name, nil)
            end
        else
            if State.mode == "animation" then
                applyAnim(randomItem)
            else
                task.spawn(function()
                    playEmote(randomItem.id)
                end)
            end
        end
        return
    end

    local adjustedIndex = randomSlotActive and index - 1 or index
    if adjustedIndex < 1 then return end

    local favs = State.mode == "animation" and State.favAnims or State.favEmotes
    local itemsPerPage = randomSlotActive and (State.itemsPerPage - 1) or State.itemsPerPage
    local favPages = #favs > 0 and math.ceil(#favs / itemsPerPage) or 0

    local item
    if State.currentPage <= favPages and #favs > 0 then
        local startIdx = (State.currentPage - 1) * itemsPerPage
        item = favs[startIdx + adjustedIndex]
        if item and State.mode == "animation" and not item.bundledItems then
            item.bundledItems = getBundled(item.id)
        end
    else
        local normalList = getNormalList()
        local adjPage = State.currentPage - favPages
        local startIdx = (adjPage - 1) * itemsPerPage
        item = normalList[startIdx + adjustedIndex]
    end

    if not item then return end

    if State.favEnabled then
        toggleFav(item.id, item.name, item.bundledItems)
    elseif State.mode == "animation" then
        applyAnim(item)
    else
        task.spawn(function()
            playEmote(item.id)
        end)
    end
end

-- ============ NUMBER KEY HOTKEYS ============ --
local function bindWheelHotkeys()
    if not ContextActionService then return end

    local keyToIndex = {
        [Enum.KeyCode.One] = 1, [Enum.KeyCode.Two] = 2, [Enum.KeyCode.Three] = 3, [Enum.KeyCode.Four] = 4,
        [Enum.KeyCode.Five] = 5, [Enum.KeyCode.Six] = 6, [Enum.KeyCode.Seven] = 7, [Enum.KeyCode.Eight] = 8,
        [Enum.KeyCode.KeypadOne] = 1, [Enum.KeyCode.KeypadTwo] = 2, [Enum.KeyCode.KeypadThree] = 3, 
        [Enum.KeyCode.KeypadFour] = 4, [Enum.KeyCode.KeypadFive] = 5, [Enum.KeyCode.KeypadSix] = 6,
        [Enum.KeyCode.KeypadSeven] = 7, [Enum.KeyCode.KeypadEight] = 8
    }

    local function onHotkey(actionName, inputState, inputObject)
        if inputState ~= Enum.UserInputState.Begin then return Enum.ContextActionResult.Pass end
        if State.hudEditorActive then return Enum.ContextActionResult.Pass end
        
        local index = keyToIndex[inputObject.KeyCode]
        if not index then return Enum.ContextActionResult.Pass end
        
        local wheel = getWheel()
        if not wheel or (not wheel.Visible and tick() - State.lastWheelVisible > 0.15) then 
            return Enum.ContextActionResult.Pass 
        end
        
        handleSector(index)
        return Enum.ContextActionResult.Sink
    end

    ContextActionService:UnbindAction("PinkWards_EmoteWheelHotkeys")
    ContextActionService:BindActionAtPriority(
        "PinkWards_EmoteWheelHotkeys",
        onHotkey,
        false,
        (Enum.ContextActionPriority.High.Value + 50),
        Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four,
        Enum.KeyCode.Five, Enum.KeyCode.Six, Enum.KeyCode.Seven, Enum.KeyCode.Eight,
        Enum.KeyCode.KeypadOne, Enum.KeyCode.KeypadTwo, Enum.KeyCode.KeypadThree, Enum.KeyCode.KeypadFour,
        Enum.KeyCode.KeypadFive, Enum.KeyCode.KeypadSix, Enum.KeyCode.KeypadSeven, Enum.KeyCode.KeypadEight
    )
end

-- ============ FAVORITES ============ --
local function toggleFav(id, name, bundled)
    local list = State.mode == "animation" and State.favAnims or State.favEmotes
    local found, idx = false, 0

    for i, v in ipairs(list) do
        if tostring(v.id) == tostring(id) then
            found, idx = true, i
            break
        end
    end

    if found then
        table.remove(list, idx)
        notify("Favorites", "Removed: " .. name, 3)
    else
        local entry = {id = id, name = name}
        if State.mode == "animation" then
            entry.bundledItems = bundled or getBundled(id)
        end
        table.insert(list, entry)
        notify("Favorites", "Added: " .. name, 3)
    end

    local fileName = State.mode == "animation" and State.favAnimFileName or State.favFileName
    saveFile(fileName, list)
    rebuildFavLookup()
    State.totalPages = calcPages()
    updatePageDisplay()
    updateDisplay(true)
end

-- ============ SEARCH (DEBOUNCED) ============ --
local function searchItems(term)
    term = term:lower()

    if term == State.lastSearchTerm then return end
    State.lastSearchTerm = term

    local source = State.mode == "animation" and State.animsData or State.emotesData

    if term == "" then
        if State.mode == "animation" then
            State.filteredAnims = State.animsData
        else
            State.filteredEmotes = State.emotesData
        end
    else
        local result = {}
        local isIdSearch = term:match("^%d+$")

        if isIdSearch then
            for i = 1, #source do
                if tostring(source[i].id) == term then
                    result[#result + 1] = source[i]
                    break
                end
            end
        else
            for i = 1, #source do
                if source[i].name:lower():find(term, 1, true) then
                    result[#result + 1] = source[i]
                end
            end
        end

        if State.mode == "animation" then
            State.filteredAnims = result
        else
            State.filteredEmotes = result
        end
    end

    State.normalListCacheVersion = -1

    State.currentPage = 1
    State.totalPages = calcPages()
    updatePageDisplay()
    updateDisplay(true)
end

-- ============ NAVIGATION ============ --
local function prevPage()
    State.currentPage = State.currentPage <= 1 and State.totalPages or State.currentPage - 1
    updatePageDisplay()
    updateDisplay(true)
end

local function nextPage()
    State.currentPage = State.currentPage >= State.totalPages and 1 or State.currentPage + 1
    updatePageDisplay()
    updateDisplay(true)
end

local function goToPage(num)
    State.currentPage = math.clamp(num, 1, State.totalPages)
    updatePageDisplay()
    updateDisplay(true)
end

-- ============ TOGGLES ============ --
local function toggleMode()
    State.mode = State.mode == "emote" and "animation" or "emote"
    
    if State.mode == "animation" and #State.animsData == 0 then
        task.spawn(function()
            local ok, result = pcall(function()
                return HttpService:JSONDecode(game:HttpGet(ANIM_URL))
            end)
            if ok and result then
                local rawList = result.data or result
                local data = {}
                for i = 1, #rawList do
                    local item = rawList[i]
                    local id = tonumber(item.id)
                    if id and id > 0 then
                        data[#data + 1] = {
                            id = id,
                            name = item.name or ("Anim_" .. id),
                            bundledItems = item.bundledItems
                        }
                    end
                end
                State.animsData = data
                State.filteredAnims = data
            end
        end)
    end

    if UI.Search then UI.Search.Text = "" end
    State.lastSearchTerm = ""

    if State.mode == "animation" then
        State.filteredAnims = State.animsData
    else
        State.filteredEmotes = State.emotesData
    end

    State.normalListCacheVersion = -1

    State.currentPage = State.mode == "animation" and (State.config.AnimationPage or 1) or (State.config.EmotePage or 1)
    State.totalPages = calcPages()
    updatePageDisplay()
    updateDisplay(true)
    applyNativeTheme()

    notify("Mode", State.mode == "animation" and "Animation Mode" or "Emote Mode", 3)
end

local function toggleFavMode()
    State.favEnabled = not State.favEnabled
    applyNativeTheme()
    notify("Favorites", State.favEnabled and "Click items to favorite" or "Favorite mode OFF", 3)
    updateDisplay(true)
end

local function toggleRandomMode()
    State.randomEnabled = not State.randomEnabled
    State.config.RandomEnabled = State.randomEnabled
    SaveConfig()
    State.totalPages = calcPages()
    updatePageDisplay()
    updateDisplay(true)
    notify("Random Slot", State.randomEnabled and "Random slot ON" or "Random slot OFF", 3)
end

local function toggleAutoReapply()
    State.autoReapplyEnabled = not State.autoReapplyEnabled
    saveFile("AutoReapplySetting.json", {enabled = State.autoReapplyEnabled})
    applyNativeTheme()
    notify("Auto-Reapply", State.autoReapplyEnabled and "ON - Animations restore on respawn" or "OFF", 3)
end

-- ============ THEME APPLICATION ============ --
local function applyNativeTheme()
    local wheel = getWheel()
    if not wheel then return end

    local theme = Themes[currentThemeName] or DefaultTheme
    
    pcall(function()
        local back = wheel:FindFirstChild("Back")
        if back then
            local background = back:FindFirstChild("Background")
            if background then
                if background:IsA("Frame") then
                    background.BackgroundColor3 = TableToColor(theme.Background)
                    background.BackgroundTransparency = 0.05
                end
                local overlay = background:FindFirstChild("BackgroundCircleOverlay")
                if overlay then
                    overlay.BackgroundColor3 = TableToColor(theme.Background)
                    overlay.BackgroundTransparency = 0.1
                end
            end
        end
    end)

    if UI.LeftBtn then UI.LeftBtn.ImageColor3 = GetIconColor("Left") end
    if UI.RightBtn then UI.RightBtn.ImageColor3 = GetIconColor("Right") end
    if UI.PagesLabel then UI.PagesLabel.TextColor3 = TableToColor(theme.ImageColor) end
    if UI.SepLabel then UI.SepLabel.TextColor3 = TableToColor(theme.ImageColor) end
    if UI.PageNumBox then UI.PageNumBox.TextColor3 = TableToColor(theme.ImageColor) end

    if UI.Top then
        UI.Top.BackgroundColor3 = TableToColor(theme.Background)
        UI.Top.BackgroundTransparency = 0.1
    end

    if UI.FavBtn then
        UI.FavBtn.BackgroundColor3 = State.favEnabled and GetIconColor("Favorite") or TableToColor(theme.Background)
        UI.FavBtn.BackgroundTransparency = 0.1
    end
    if UI.FavBtnLabel then
        UI.FavBtnLabel.TextColor3 = State.favEnabled and Color3.fromRGB(255, 255, 255) or TableToColor(theme.ImageColor)
    end

    if UI.ModeBtn then
        UI.ModeBtn.BackgroundColor3 = State.mode == "animation" and GetIconColor("Mode") or TableToColor(theme.Background)
    end
    if UI.ModeBtnLabel then
        UI.ModeBtnLabel.TextColor3 = TableToColor(theme.ImageColor)
    end

    if UI.RandomBtn then
        UI.RandomBtn.BackgroundColor3 = State.randomEnabled and GetIconColor("Favorite") or TableToColor(theme.Background)
    end
    if UI.RandomBtnLabel then
        UI.RandomBtnLabel.TextColor3 = TableToColor(theme.ImageColor)
    end

    if UI.AutoReapplyBtn then
        UI.AutoReapplyBtn.BackgroundColor3 = State.autoReapplyEnabled and GetIconColor("Auto") or TableToColor(theme.Background)
    end
    if UI.AutoBtnLabel then
        UI.AutoBtnLabel.TextColor3 = TableToColor(theme.ImageColor)
    end
end

-- ============ HUD EDITOR ============ --
local HUD = {
    Connections = {},
    Strokes = {},
    Overlay = nil,
    DefaultPositions = {
        Under = UDim2.new(0.13, 0, 1, 0),
        Top = UDim2.new(0.13, 0, -0.11, 0),
        FavBtn = UDim2.new(0.019, 0, -0.108, 0),
        ModeBtn = UDim2.new(0.889, 0, -0.108, 0),
        RandomBtn = UDim2.new(0.889, 0, -0.215, 0),
        AutoBtn = UDim2.new(0.889, 0, -0.322, 0),
    }
}

local function getMovableElements()
    local elems = {}
    if UI.Top then elems["Top"] = UI.Top end
    if UI.Under then elems["Under"] = UI.Under end
    if UI.FavBtn then elems["FavBtn"] = UI.FavBtn end
    if UI.ModeBtn then elems["ModeBtn"] = UI.ModeBtn end
    if UI.RandomBtn then elems["RandomBtn"] = UI.RandomBtn end
    if UI.AutoReapplyBtn then elems["AutoBtn"] = UI.AutoReapplyBtn end
    return elems
end

local function calculateSnap(element, newPos, currentName, allMovable)
    local SNAP_THRESHOLD = 8
    local parent = element.Parent
    if not parent then return newPos, nil, nil end
    local ps = parent.AbsoluteSize
    local pp = parent.AbsolutePosition
    local absX = pp.X + newPos.X.Scale * ps.X + newPos.X.Offset
    local absY = pp.Y + newPos.Y.Scale * ps.Y + newPos.Y.Offset
    local absW = element.AbsoluteSize.X
    local absH = element.AbsoluteSize.Y
    local sX, sY = absX, absY
    local didX, didY = false, false
    local guideX, guideY
    
    for oName, oEl in pairs(allMovable) do
        if oName ~= currentName then
            local oX = oEl.AbsolutePosition.X
            local oY = oEl.AbsolutePosition.Y
            local oW = oEl.AbsoluteSize.X
            local oH = oEl.AbsoluteSize.Y
            if not didX then
                if math.abs(absX - oX) < SNAP_THRESHOLD then sX = oX; didX = true; guideX = oX end
                if math.abs(absX - (oX + oW)) < SNAP_THRESHOLD then sX = oX + oW; didX = true; guideX = oX + oW end
                if math.abs((absX + absW) - oX) < SNAP_THRESHOLD then sX = oX - absW; didX = true; guideX = oX end
                if math.abs((absX + absW) - (oX + oW)) < SNAP_THRESHOLD then sX = oX + oW - absW; didX = true; guideX = oX + oW end
            end
            if not didY then
                if math.abs(absY - oY) < SNAP_THRESHOLD then sY = oY; didY = true; guideY = oY end
                if math.abs(absY - (oY + oH)) < SNAP_THRESHOLD then sY = oY + oH; didY = true; guideY = oY + oH end
                if math.abs((absY + absH) - oY) < SNAP_THRESHOLD then sY = oY - absH; didY = true; guideY = oY end
                if math.abs((absY + absH) - (oY + oH)) < SNAP_THRESHOLD then sY = oY + oH - absH; didY = true; guideY = oY + oH end
            end
        end
    end
    
    local fsx = (sX - pp.X) / ps.X
    local fsy = (sY - pp.Y) / ps.Y
    return UDim2.new(fsx, newPos.X.Offset, fsy, newPos.Y.Offset), guideX, guideY
end

local function setupElementDragging(name, element, allMovable, snapGuideV, snapGuideH)
    local stroke = Instance.new("UIStroke")
    stroke.Name = "HUDEditorStroke"
    stroke.Color = Color3.fromRGB(0, 255, 100)
    stroke.Thickness = 2
    stroke.Parent = element
    table.insert(HUD.Strokes, stroke)

    local dragging = false
    local dragStart, startPos
    
    local dragHandle = Instance.new("ImageButton")
    dragHandle.Name = "DragHandle"
    dragHandle.Parent = element
    dragHandle.BackgroundTransparency = 1
    dragHandle.Size = UDim2.fromScale(1, 1)
    dragHandle.ZIndex = 9999
    dragHandle.Active = true
    dragHandle.Image = ""

    table.insert(HUD.Connections, dragHandle.InputBegan:Connect(function(input)
        if not State.hudEditorActive then return end
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            dragStart = input.Position
            startPos = element.Position
            stroke.Color = Color3.fromRGB(255, 255, 255)
        end
    end))

    table.insert(HUD.Connections, UserInputService.InputChanged:Connect(function(input)
        if not dragging then return end
        if input.UserInputType == Enum.UserInputType.MouseMovement then
            local delta = input.Position - dragStart
            local ps = element.Parent and element.Parent.AbsoluteSize or Vector2.new(1, 1)
            local rawPos = UDim2.new(
                startPos.X.Scale + delta.X / ps.X, startPos.X.Offset,
                startPos.Y.Scale + delta.Y / ps.Y, startPos.Y.Offset
            )
            local snapped, gx, gy = calculateSnap(element, rawPos, name, allMovable)
            element.Position = snapped
            if snapGuideV then snapGuideV.Visible = (gx ~= nil); if gx then snapGuideV.Position = UDim2.fromOffset(gx, 0) end end
            if snapGuideH then snapGuideH.Visible = (gy ~= nil); if gy then snapGuideH.Position = UDim2.fromOffset(0, gy) end end
        end
    end))

    table.insert(HUD.Connections, UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            if dragging then
                dragging = false
                stroke.Color = Color3.fromRGB(0, 255, 100)
                if snapGuideV then snapGuideV.Visible = false end
                if snapGuideH then snapGuideH.Visible = false end
                State.config.HUDPositions[name] = {
                    element.Position.X.Scale, element.Position.X.Offset,
                    element.Position.Y.Scale, element.Position.Y.Offset
                }
                SaveConfig()
            end
        end
    end))
end

local function enterHUDEditor()
    if State.hudEditorActive then return end
    State.hudEditorActive = true

    GuiService:SetEmotesMenuOpen(false)
    task.wait(0.15)

    local wheel = getWheel()
    if not wheel then State.hudEditorActive = false; return end
    wheel.Visible = true

    local overlay = Instance.new("Frame")
    overlay.Name = "HUDEditorOverlay"
    overlay.Parent = CoreGui
    overlay.BackgroundTransparency = 1
    overlay.Size = UDim2.fromScale(1, 1)
    overlay.ZIndex = 6000
    HUD.Overlay = overlay

    local controlBar = Instance.new("Frame")
    controlBar.Parent = overlay
    controlBar.BackgroundTransparency = 1
    controlBar.AnchorPoint = Vector2.new(1, 0)
    controlBar.Position = UDim2.new(1, -10, 0, 10)
    controlBar.Size = UDim2.fromOffset(100, 42)
    
    local layout = Instance.new("UIListLayout")
    layout.FillDirection = Enum.FillDirection.Horizontal
    layout.Padding = UDim.new(0, 8)
    layout.Parent = controlBar

    local resetBtn = Instance.new("ImageButton")
    resetBtn.Parent = controlBar
    resetBtn.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    resetBtn.BackgroundTransparency = 0.4
    resetBtn.Size = UDim2.fromOffset(42, 42)
    resetBtn.Image = "rbxassetid://123088523596870"
    Instance.new("UICorner", resetBtn).CornerRadius = UDim.new(0, 10)

    local exitBtn = Instance.new("ImageButton")
    exitBtn.Parent = controlBar
    exitBtn.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    exitBtn.BackgroundTransparency = 0.4
    exitBtn.Size = UDim2.fromOffset(42, 42)
    exitBtn.Image = "rbxassetid://79024388644722"
    Instance.new("UICorner", exitBtn).CornerRadius = UDim.new(0, 10)

    exitBtn.MouseButton1Click:Connect(function()
        State.hudEditorActive = false
        for _, conn in pairs(HUD.Connections) do
            pcall(function() conn:Disconnect() end)
        end
        HUD.Connections = {}
        for _, stroke in pairs(HUD.Strokes) do
            pcall(function() if stroke and stroke.Parent then stroke:Destroy() end end)
        end
        HUD.Strokes = {}
        if HUD.Overlay then HUD.Overlay:Destroy() end
        HUD.Overlay = nil
        pcall(function() GuiService:SetEmotesMenuOpen(false) end)
    end)

    resetBtn.MouseButton1Click:Connect(function()
        State.config.HUDPositions = {}
        SaveConfig()
        for name, el in pairs(getMovableElements()) do
            if HUD.DefaultPositions[name] then
                el.Position = HUD.DefaultPositions[name]
            end
        end
        notify("HUD Editor", "Positions reset to default", 3)
    end)

    local allMovable = getMovableElements()
    local snapGuideH = Instance.new("Frame")
    snapGuideH.Name = "SnapGuide"
    snapGuideH.BackgroundColor3 = Color3.fromRGB(0, 170, 255)
    snapGuideH.Size = UDim2.new(1, 0, 0, 1)
    snapGuideH.ZIndex = 6002
    snapGuideH.Visible = false
    snapGuideH.Parent = overlay

    local snapGuideV = Instance.new("Frame")
    snapGuideV.Name = "SnapGuide"
    snapGuideV.BackgroundColor3 = Color3.fromRGB(0, 170, 255)
    snapGuideV.Size = UDim2.new(0, 1, 1, 0)
    snapGuideV.ZIndex = 6002
    snapGuideV.Visible = false
    snapGuideV.Parent = overlay

    for name, element in pairs(allMovable) do
        setupElementDragging(name, element, allMovable, snapGuideV, snapGuideH)
    end

    notify("HUD Editor", "Drag elements to reposition, click X to exit", 5)
end

-- ============ BACKUP SYSTEM ============ --
local function exportSettings()
    local exportData = {
        Type = "All",
        Version = 1,
        Themes = Themes,
        Config = State.config,
        Favorites = {
            Emotes = State.favEmotes,
            Animations = State.favAnims
        }
    }
    local json = HttpService:JSONEncode(exportData)
    setclipboard(json)
    notify("Export", "Settings copied to clipboard!", 3)
end

local function importSettings()
    local popup = Instance.new("Frame")
    popup.Size = UDim2.fromOffset(350, 250)
    popup.Position = UDim2.fromScale(0.5, 0.5)
    popup.AnchorPoint = Vector2.new(0.5, 0.5)
    popup.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    popup.Parent = CoreGui
    
    Instance.new("UICorner", popup).CornerRadius = UDim.new(0, 12)
    
    local title = Instance.new("TextLabel", popup)
    title.Size = UDim2.new(1, 0, 0, 35)
    title.BackgroundTransparency = 1
    title.Text = "Import Settings"
    title.TextColor3 = Color3.new(1, 1, 1)
    title.Font = Enum.Font.GothamBold
    title.TextSize = 14
    
    local input = Instance.new("TextBox", popup)
    input.Position = UDim2.new(0.05, 0, 0.15, 0)
    input.Size = UDim2.new(0.9, 0, 0.5, 0)
    input.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
    input.TextColor3 = Color3.new(1, 1, 1)
    input.PlaceholderText = "Paste JSON here..."
    input.MultiLine = true
    input.TextWrapped = true
    Instance.new("UICorner", input).CornerRadius = UDim.new(0, 8)
    
    local importBtn = Instance.new("TextButton", popup)
    importBtn.Position = UDim2.new(0.05, 0, 0.75, 0)
    importBtn.Size = UDim2.new(0.4, 0, 0.12, 0)
    importBtn.BackgroundColor3 = Color3.fromRGB(0, 162, 255)
    importBtn.Text = "Import"
    importBtn.TextColor3 = Color3.new(1, 1, 1)
    Instance.new("UICorner", importBtn).CornerRadius = UDim.new(0, 8)
    
    local cancelBtn = Instance.new("TextButton", popup)
    cancelBtn.Position = UDim2.new(0.55, 0, 0.75, 0)
    cancelBtn.Size = UDim2.new(0.4, 0, 0.12, 0)
    cancelBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
    cancelBtn.Text = "Cancel"
    cancelBtn.TextColor3 = Color3.new(1, 1, 1)
    Instance.new("UICorner", cancelBtn).CornerRadius = UDim.new(0, 8)
    
    importBtn.MouseButton1Click:Connect(function()
        local ok, data = pcall(function()
            return HttpService:JSONDecode(input.Text)
        end)
        if ok and data then
            if data.Themes then
                for name, theme in pairs(data.Themes) do
                    if name ~= "Default" then
                        Themes[name] = theme
                    end
                end
                SaveThemes()
            end
            if data.Config then
                for k, v in pairs(data.Config) do
                    State.config[k] = v
                end
                SaveConfig()
                State.randomEnabled = State.config.RandomEnabled
                State.randomMode = State.config.RandomMode
            end
            if data.Favorites then
                if data.Favorites.Emotes then
                    State.favEmotes = data.Favorites.Emotes
                    saveFile(State.favFileName, State.favEmotes)
                end
                if data.Favorites.Animations then
                    State.favAnims = data.Favorites.Animations
                    saveFile(State.favAnimFileName, State.favAnims)
                end
                rebuildFavLookup()
            end
            State.totalPages = calcPages()
            updatePageDisplay()
            updateDisplay(true)
            applyNativeTheme()
            notify("Import", "Settings imported successfully!", 3)
        else
            notify("Import", "Invalid JSON format!", 3)
        end
        popup:Destroy()
    end)
    
    cancelBtn.MouseButton1Click:Connect(function()
        popup:Destroy()
    end)
end

-- ============ GUI CREATION ============ --
UI = {}

local function makeTextButton(name, parent, pos, size, text, bgColor)
    local btn = Instance.new("ImageButton")
    btn.Name = name
    btn.Parent = parent
    btn.BackgroundColor3 = bgColor or Color3.fromRGB(45, 45, 45)
    btn.BackgroundTransparency = 0.1
    btn.BorderSizePixel = 0
    btn.Position = pos
    btn.Size = size
    btn.Image = ""

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 6)
    corner.Parent = btn

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(70, 70, 70)
    stroke.Thickness = 1
    stroke.Transparency = 0.5
    stroke.Parent = btn

    local label = Instance.new("TextLabel")
    label.Name = "Label"
    label.Parent = btn
    label.BackgroundTransparency = 1
    label.Size = UDim2.new(1, 0, 1, 0)
    label.Font = Enum.Font.GothamBold
    label.Text = text
    label.TextColor3 = Color3.fromRGB(255, 255, 255)
    label.TextScaled = true
    label.ZIndex = btn.ZIndex + 1

    return btn, label
end

function createGUI()
    local wheel = getWheel()
    if not wheel then return false end

    for _, name in ipairs({"Under", "Top", "Favorite", "ModeToggle", "RandomToggle", "AutoReapplyToggle"}) do
        local existing = wheel:FindFirstChild(name)
        if existing then existing:Destroy() end
    end

    -- Bottom navigation bar
    UI.Under = Instance.new("Frame")
    UI.Under.Name = "Under"
    UI.Under.Parent = wheel
    UI.Under.BackgroundTransparency = 1
    UI.Under.BorderSizePixel = 0
    UI.Under.Position = State.config.HUDPositions.Under and UDim2.new(unpack(State.config.HUDPositions.Under)) or HUD.DefaultPositions.Under
    UI.Under.Size = UDim2.new(0.74, 0, 0.13, 0)

    local underLayout = Instance.new("UIListLayout")
    underLayout.Parent = UI.Under
    underLayout.FillDirection = Enum.FillDirection.Horizontal
    underLayout.VerticalAlignment = Enum.VerticalAlignment.Center
    underLayout.SortOrder = Enum.SortOrder.LayoutOrder

    UI.LeftBtn = Instance.new("ImageButton")
    UI.LeftBtn.Name = "LeftBtn"
    UI.LeftBtn.Parent = UI.Under
    UI.LeftBtn.LayoutOrder = 1
    UI.LeftBtn.BackgroundTransparency = 1
    UI.LeftBtn.Size = UDim2.new(0.17, 0, 0.94, 0)
    UI.LeftBtn.Image = "rbxassetid://93111945058621"
    UI.LeftBtn.ImageColor3 = Color3.fromRGB(180, 180, 180)

    UI.PageNumBox = Instance.new("TextBox")
    UI.PageNumBox.Name = "PageNum"
    UI.PageNumBox.Parent = UI.Under
    UI.PageNumBox.LayoutOrder = 2
    UI.PageNumBox.BackgroundTransparency = 1
    UI.PageNumBox.Size = UDim2.new(0.16, 0, 0.81, 0)
    UI.PageNumBox.Font = Enum.Font.GothamBold
    UI.PageNumBox.Text = "1"
    UI.PageNumBox.TextColor3 = Color3.fromRGB(255, 255, 255)
    UI.PageNumBox.TextScaled = true

    UI.SepLabel = Instance.new("TextLabel")
    UI.SepLabel.Name = "Separator"
    UI.SepLabel.Parent = UI.Under
    UI.SepLabel.LayoutOrder = 3
    UI.SepLabel.BackgroundTransparency = 1
    UI.SepLabel.Size = UDim2.new(0.34, 0, 0.94, 0)
    UI.SepLabel.Font = Enum.Font.GothamBold
    UI.SepLabel.Text = "/"
    UI.SepLabel.TextColor3 = Color3.fromRGB(120, 120, 120)
    UI.SepLabel.TextScaled = true

    UI.PagesLabel = Instance.new("TextLabel")
    UI.PagesLabel.Name = "TotalPages"
    UI.PagesLabel.Parent = UI.Under
    UI.PagesLabel.LayoutOrder = 4
    UI.PagesLabel.BackgroundTransparency = 1
    UI.PagesLabel.Size = UDim2.new(0.16, 0, 0.81, 0)
    UI.PagesLabel.Font = Enum.Font.GothamBold
    UI.PagesLabel.Text = "1"
    UI.PagesLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
    UI.PagesLabel.TextScaled = true

    UI.RightBtn = Instance.new("ImageButton")
    UI.RightBtn.Name = "RightBtn"
    UI.RightBtn.Parent = UI.Under
    UI.RightBtn.LayoutOrder = 5
    UI.RightBtn.BackgroundTransparency = 1
    UI.RightBtn.Size = UDim2.new(0.17, 0, 0.94, 0)
    UI.RightBtn.Image = "rbxassetid://107938916240738"
    UI.RightBtn.ImageColor3 = Color3.fromRGB(180, 180, 180)

    -- Top search bar
    UI.Top = Instance.new("Frame")
    UI.Top.Name = "Top"
    UI.Top.Parent = wheel
    UI.Top.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
    UI.Top.BackgroundTransparency = 0.1
    UI.Top.BorderSizePixel = 0
    UI.Top.Position = State.config.HUDPositions.Top and UDim2.new(unpack(State.config.HUDPositions.Top)) or HUD.DefaultPositions.Top
    UI.Top.Size = UDim2.new(0.74, 0, 0.095, 0)

    local topCorner = Instance.new("UICorner")
    topCorner.CornerRadius = UDim.new(0, 8)
    topCorner.Parent = UI.Top

    local topStroke = Instance.new("UIStroke")
    topStroke.Color = Color3.fromRGB(70, 70, 70)
    topStroke.Thickness = 1
    topStroke.Parent = UI.Top

    local topLayout = Instance.new("UIListLayout")
    topLayout.Parent = UI.Top
    topLayout.FillDirection = Enum.FillDirection.Horizontal
    topLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    topLayout.VerticalAlignment = Enum.VerticalAlignment.Center

    UI.Search = Instance.new("TextBox")
    UI.Search.Name = "Search"
    UI.Search.Parent = UI.Top
    UI.Search.BackgroundTransparency = 1
    UI.Search.Size = UDim2.new(0.87, 0, 0.82, 0)
    UI.Search.Font = Enum.Font.Gotham
    UI.Search.PlaceholderText = "Search by name or ID..."
    UI.Search.PlaceholderColor3 = Color3.fromRGB(120, 120, 120)
    UI.Search.Text = ""
    UI.Search.TextColor3 = Color3.fromRGB(255, 255, 255)
    UI.Search.TextScaled = true

    -- Buttons
    UI.FavBtn, UI.FavBtnLabel = makeTextButton(
        "Favorite", wheel,
        State.config.HUDPositions.FavBtn and UDim2.new(unpack(State.config.HUDPositions.FavBtn)) or HUD.DefaultPositions.FavBtn,
        UDim2.new(0.0875, 0, 0.0875, 0),
        "FAV"
    )

    UI.ModeBtn, UI.ModeBtnLabel = makeTextButton(
        "ModeToggle", wheel,
        State.config.HUDPositions.ModeBtn and UDim2.new(unpack(State.config.HUDPositions.ModeBtn)) or HUD.DefaultPositions.ModeBtn,
        UDim2.new(0.0875, 0, 0.0875, 0),
        "EMO"
    )

    UI.RandomBtn, UI.RandomBtnLabel = makeTextButton(
        "RandomToggle", wheel,
        State.config.HUDPositions.RandomBtn and UDim2.new(unpack(State.config.HUDPositions.RandomBtn)) or HUD.DefaultPositions.RandomBtn,
        UDim2.new(0.0875, 0, 0.0875, 0),
        "RND"
    )

    UI.AutoReapplyBtn, UI.AutoBtnLabel = makeTextButton(
        "AutoReapplyToggle", wheel,
        State.config.HUDPositions.AutoBtn and UDim2.new(unpack(State.config.HUDPositions.AutoBtn)) or HUD.DefaultPositions.AutoBtn,
        UDim2.new(0.0875, 0, 0.0875, 0),
        "RE"
    )

    -- Connect events
    UI.LeftBtn.MouseButton1Click:Connect(prevPage)
    UI.RightBtn.MouseButton1Click:Connect(nextPage)

    UI.PageNumBox.FocusLost:Connect(function()
        local num = tonumber(UI.PageNumBox.Text)
        if num then goToPage(num) else UI.PageNumBox.Text = tostring(State.currentPage) end
    end)

    local searchDebounceThread = nil
    UI.Search:GetPropertyChangedSignal("Text"):Connect(function()
        if searchDebounceThread then
            pcall(function() task.cancel(searchDebounceThread) end)
        end
        searchDebounceThread = task.delay(0.3, function()
            searchItems(UI.Search.Text)
            searchDebounceThread = nil
        end)
    end)

    UI.FavBtn.MouseButton1Click:Connect(toggleFavMode)
    UI.ModeBtn.MouseButton1Click:Connect(toggleMode)
    UI.RandomBtn.MouseButton1Click:Connect(toggleRandomMode)
    UI.AutoReapplyBtn.MouseButton1Click:Connect(toggleAutoReapply)

    applyNativeTheme()
    State.guiCreated = true
    
    bindWheelHotkeys()
    
    return true
end

-- ============ DATA FETCHING ============ --
local function fetchEmotes()
    if State.isLoading then return end
    State.isLoading = true

    local ok, result = pcall(function()
        return HttpService:JSONDecode(game:HttpGet(EMOTE_URL))
    end)

    if ok and result then
        local rawList = result.data or result
        local data = {}
        for i = 1, #rawList do
            local item = rawList[i]
            local id = tonumber(item.id)
            if id and id > 0 then
                data[#data + 1] = {id = id, name = item.name or ("Emote_" .. id)}
            end
        end
        State.emotesData = data
        State.filteredEmotes = data
    end

    State.isLoading = false
end

local function fetchAnims()
    if State.isLoading then return end
    State.isLoading = true

    local ok, result = pcall(function()
        return HttpService:JSONDecode(game:HttpGet(ANIM_URL))
    end)

    if ok and result then
        local rawList = result.data or result
        local data = {}
        for i = 1, #rawList do
            local item = rawList[i]
            local id = tonumber(item.id)
            if id and id > 0 then
                data[#data + 1] = {
                    id = id,
                    name = item.name or ("Anim_" .. id),
                    bundledItems = item.bundledItems
                }
            end
        end
        State.animsData = data
        State.filteredAnims = data
    end

    State.isLoading = false
end

-- ============ CHARACTER HANDLING ============ --
local function forceFullRefresh()
    State.lastDisplayPage = -1
    State.lastDisplayMode = ""
    State.lastDisplayFavVer = -1
    State.normalListCacheVersion = -1
    State.wheelCache = nil
    State.lastWheelCheck = 0

    State.totalPages = calcPages()
    updatePageDisplay()
    updateDisplay(true)
    applyNativeTheme()
end

local function onCharacterAdded(char)
    local hum = char:WaitForChild("Humanoid", 15)
    if not hum then return end

    local desc = hum:FindFirstChildOfClass("HumanoidDescription")
    if not desc then
        for i = 1, 30 do
            task.wait(0.1)
            desc = hum:FindFirstChildOfClass("HumanoidDescription")
            if desc then break end
        end
    end

    currentLoadId = currentLoadId + 1
    cleanupAllTracks()
    loadedTracks = {}
    State.currentEmoteTrack = nil

    if State.autoReapplyEnabled and getgenv().lastAnim and getgenv().lastAnim.id then
        task.wait(0.5)
        applyAnim(getgenv().lastAnim)
        notify("Auto-Reload", "Animation restored", 3)
    end

    task.wait(0.8)
    forceFullRefresh()

    local wheel = getWheel()
    if wheel and not wheel:FindFirstChild("Under") then
        State.guiCreated = false
        State.wheelCache = nil
        task.wait(0.3)
        if getWheel() then
            createGUI()
            forceFullRefresh()
        end
    end

    task.spawn(function()
        for i = 1, 10 do
            task.wait(0.5)
            if player.Character ~= char then return end
            forceFullRefresh()
        end
    end)

    hum.Died:Connect(function()
        State.favEnabled = false
        currentLoadId = currentLoadId + 1
        cleanupAllTracks()
        loadedTracks = {}
        applyNativeTheme()
    end)
end

-- ============ MAIN RENDER LOOP ============ --
local frameCount = 0
RunService.RenderStepped:Connect(function()
    frameCount = frameCount + 1
    if frameCount >= 60 then
        frameCount = 0

        local wheel = getWheel()
        if not wheel then
            State.guiCreated = false
            return
        end

        if not State.guiCreated or not wheel:FindFirstChild("Under") then
            State.guiCreated = false
            if createGUI() then
                forceFullRefresh()
            end
        else
            applyNativeTheme()
        end

        if State.needsDisplayRefresh then
            State.needsDisplayRefresh = false
            forceFullRefresh()
        end
    end
end)

-- ============ INITIALIZATION ============ --
task.spawn(function()
    LoadConfig()
    LoadThemes()
    
    while not getWheel() do task.wait(0.1) end

    if createGUI() then
        State.favEmotes = loadFile(State.favFileName)
        State.favAnims = loadFile(State.favAnimFileName)
        rebuildFavLookup()
        loadLastAnim()
        
        fetchEmotes()
        fetchAnims()

        State.totalPages = calcPages()
        updatePageDisplay()
        updateDisplay(true)

        notify("PinkWards", "Loaded! Press '.' to open | RND = Random Slot", 5)
    end
end)

-- Character handler
player.CharacterAdded:Connect(onCharacterAdded)
if player.Character then
    task.spawn(function() onCharacterAdded(player.Character) end)
end

-- Keep emotes menu enabled
StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Chat, true)

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
                    State.guiCreated = false
                    State.wheelCache = nil
                end
            end
        end)
        task.wait(2)
    end
end)
