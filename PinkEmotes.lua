--[[ 
    Pink Emote + Animation System
    Connected to: github.com/PinkWards/emote-sniper
    💗 With Animation Support!
]]

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
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")

-- Database URLs (Using working URLs)
local EMOTE_DATABASE_URL = "https://raw.githubusercontent.com/7yd7/sniper-Emote/refs/heads/test/EmoteSniper.json"
local ANIMATION_DATABASE_URL = "https://raw.githubusercontent.com/7yd7/sniper-Emote/refs/heads/test/AnimationSniper.json"

-- State variables
local currentMode = "emote" -- "emote" or "animation"
local emoteClickConnections = {}
local isMonitoringClicks = false

-- Emote data
local emotesData = {}
local originalEmotesData = {}
local filteredEmotes = {}
local favoriteEmotes = {}
local favoriteEmotesFileName = "FavoriteEmotes.json"

-- Animation data
local animationsData = {}
local originalAnimationsData = {}
local filteredAnimations = {}
local favoriteAnimations = {}
local favoriteAnimationsFileName = "FavoriteAnimations.json"

local currentPage = 1
local itemsPerPage = 8
local totalPages = 1
local isLoading = false
local totalLoaded = 0
local favoriteEnabled = false
local isGUICreated = false

getgenv().lastPlayedAnimation = getgenv().lastPlayedAnimation or nil
getgenv().autoReloadEnabled = getgenv().autoReloadEnabled or false

-- 💗 PINK THEME COLORS
local COLORS = {
    PINK_LIGHT = Color3.fromHex("#FFEBF2"),
    PINK_MEDIUM = Color3.fromHex("#FFC8DC"),
    PINK_WHEEL = Color3.fromHex("#FFD9E8"),
    PINK_HEART = Color3.fromHex("#FF6B9D"),
    PINK_ANIM = Color3.fromHex("#C8A2C8"),
    WHITE = Color3.fromRGB(255, 255, 255),
    PLACEHOLDER = Color3.fromRGB(255, 210, 230),
}

local lastThemeUpdate = 0
local THEME_UPDATE_INTERVAL = 0.5
local frameCount = 0
local FRAME_CHECK_INTERVAL = 30

-- GUI element references
local Under, UIListLayout, _1left, _9right, _4pages, _3TextLabel, _2Routenumber
local Top, UIListLayout_2, UICorner, Search, Favorite, UICorner2
local ModeToggle, ReloadBtn

local clickCooldown = {}
local cachedEmotesWheel = nil
local lastWheelCheck = 0

local lastRadialActionTime = 0
local lastWheelVisibleTime = 0

--============ UTILITY FUNCTIONS ============--

local function Notify(data)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = data.Title or "Notification",
            Text = data.Content or "",
            Duration = data.Duration or 5
        })
    end)
end

local function getCharacterAndHumanoid()
    local char = player.Character
    if not char then return nil, nil end
    local hum = char:FindFirstChild("Humanoid")
    return char, hum
end

local function stopEmotes()
    pcall(function()
        local char, hum = getCharacterAndHumanoid()
        if hum then
            local tracks = hum:GetPlayingAnimationTracks()
            for i = 1, #tracks do
                tracks[i]:Stop()
            end
        end
    end)
end

local function getEmotesWheel()
    local currentTime = tick()
    if cachedEmotesWheel and cachedEmotesWheel.Parent and (currentTime - lastWheelCheck) < 1 then
        return cachedEmotesWheel
    end
    lastWheelCheck = currentTime
    local success, wheel = pcall(function()
        return CoreGui.RobloxGui.EmotesMenu.Children.Main.EmotesWheel
    end)
    if success and wheel then
        cachedEmotesWheel = wheel
        return wheel
    end
    cachedEmotesWheel = nil
    return nil
end

local function checkEmotesMenuExists()
    local wheel = getEmotesWheel()
    return wheel ~= nil, wheel
end

--============ FILE I/O ============--

local function saveFavorites()
    if writefile then
        pcall(function()
            writefile(favoriteEmotesFileName, HttpService:JSONEncode(favoriteEmotes))
        end)
    end
end

local function loadFavorites()
    if readfile and isfile and isfile(favoriteEmotesFileName) then
        pcall(function()
            favoriteEmotes = HttpService:JSONDecode(readfile(favoriteEmotesFileName))
        end)
    end
end

local function saveFavoritesAnimations()
    if writefile then
        pcall(function()
            writefile(favoriteAnimationsFileName, HttpService:JSONEncode(favoriteAnimations))
        end)
    end
end

local function loadFavoritesAnimations()
    if readfile and isfile and isfile(favoriteAnimationsFileName) then
        pcall(function()
            favoriteAnimations = HttpService:JSONDecode(readfile(favoriteAnimationsFileName))
        end)
    end
end

--============ HELPER FUNCTIONS ============--

local function extractAssetId(imageUrl)
    return string.match(imageUrl, "Asset&id=(%d+)")
end

local function getEmoteName(assetId)
    local success, productInfo = pcall(function()
        return MarketplaceService:GetProductInfo(tonumber(assetId))
    end)
    if success and productInfo then
        return productInfo.Name
    end
    return "Emote_" .. tostring(assetId)
end

local function isInFavorites(assetId)
    local favoriteList = currentMode == "animation" and favoriteAnimations or favoriteEmotes
    local assetStr = tostring(assetId)
    for i = 1, #favoriteList do
        if tostring(favoriteList[i].id) == assetStr then
            return true
        end
    end
    return false
end

local function getBundledItemsForAnimation(animId)
    local idStr = tostring(animId)
    
    -- Search in original data first
    for _, anim in pairs(originalAnimationsData) do
        if tostring(anim.id) == idStr and anim.bundledItems then
            return anim.bundledItems
        end
    end
    
    -- Search in filtered data
    for _, anim in pairs(filteredAnimations) do
        if tostring(anim.id) == idStr and anim.bundledItems then
            return anim.bundledItems
        end
    end
    
    -- Search in animations data
    for _, anim in pairs(animationsData) do
        if tostring(anim.id) == idStr and anim.bundledItems then
            return anim.bundledItems
        end
    end
    
    -- Search in favorites
    for _, anim in pairs(favoriteAnimations) do
        if tostring(anim.id) == idStr and anim.bundledItems then
            return anim.bundledItems
        end
    end
    
    return nil
end

--============ FAVORITE ICON ============--

local function updateFavoriteIcon(imageLabel, assetId, isFavorite)
    local favoriteIcon = imageLabel:FindFirstChild("FavoriteHeart")
    
    if isFavorite then
        if not favoriteIcon then
            favoriteIcon = Instance.new("TextLabel")
            favoriteIcon.Name = "FavoriteHeart"
            favoriteIcon.Size = UDim2.new(0.22, 0, 0.22, 0)
            favoriteIcon.Position = UDim2.new(0.76, 0, 0.02, 0)
            favoriteIcon.BackgroundTransparency = 1
            favoriteIcon.ZIndex = imageLabel.ZIndex + 10
            favoriteIcon.Text = "💗"
            favoriteIcon.TextScaled = true
            favoriteIcon.Font = Enum.Font.SourceSans
            favoriteIcon.TextColor3 = COLORS.WHITE
            favoriteIcon.Parent = imageLabel
        else
            favoriteIcon.Visible = true
        end
    elseif favoriteIcon then
        favoriteIcon.Visible = false
    end
end

--============ THEME APPLICATION ============--

local function applyPinkThemeToWheel()
    local emotesWheel = getEmotesWheel()
    if not emotesWheel then return end
    
    pcall(function()
        local back = emotesWheel:FindFirstChild("Back")
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
end

local function updateAnimationImages(currentPageAnims)
    local emotesWheel = getEmotesWheel()
    if not emotesWheel then return end
    
    pcall(function()
        local front = emotesWheel:FindFirstChild("Front")
        if not front then return end
        local frontFrame = front:FindFirstChild("EmotesButtons")
        if not frontFrame then return end
        
        local buttonIndex = 1
        for _, child in pairs(frontFrame:GetChildren()) do
            if child:IsA("ImageLabel") then
                if buttonIndex <= #currentPageAnims then
                    local animData = currentPageAnims[buttonIndex]
                    child.Image = "rbxthumb://type=BundleThumbnail&id=" .. animData.id .. "&w=420&h=420"
                    
                    local idValue = child:FindFirstChild("AnimationID") or Instance.new("IntValue")
                    idValue.Name = "AnimationID"
                    idValue.Value = animData.id
                    idValue.Parent = child
                    
                    child.Active = not favoriteEnabled
                    buttonIndex = buttonIndex + 1
                else
                    child.Image = ""
                    local idValue = child:FindFirstChild("AnimationID")
                    if idValue then idValue:Destroy() end
                end
            end
        end
        frontFrame.Active = not favoriteEnabled
    end)
end

local function updateAllFavoriteIcons()
    local emotesWheel = getEmotesWheel()
    if not emotesWheel then return end
    
    pcall(function()
        local front = emotesWheel:FindFirstChild("Front")
        if not front then return end
        local frontFrame = front:FindFirstChild("EmotesButtons")
        if not frontFrame then return end
        
        for _, child in pairs(frontFrame:GetChildren()) do
            if child:IsA("ImageLabel") and child.Image ~= "" then
                local assetId
                if currentMode == "animation" then
                    local idVal = child:FindFirstChild("AnimationID")
                    if idVal then assetId = idVal.Value end
                else
                    assetId = extractAssetId(child.Image)
                end
                
                if assetId then
                    updateFavoriteIcon(child, assetId, isInFavorites(assetId))
                end
                child.Active = not favoriteEnabled
            end
        end
        frontFrame.Active = not favoriteEnabled
    end)
end

local function updateGUIColors()
    local currentTime = tick()
    if currentTime - lastThemeUpdate < THEME_UPDATE_INTERVAL then return end
    lastThemeUpdate = currentTime
    
    applyPinkThemeToWheel()
    
    if _1left then _1left.ImageColor3 = COLORS.PINK_MEDIUM end
    if _9right then _9right.ImageColor3 = COLORS.PINK_MEDIUM end
    if _4pages then _4pages.TextColor3 = COLORS.WHITE end
    if _3TextLabel then _3TextLabel.TextColor3 = COLORS.WHITE end
    if _2Routenumber then _2Routenumber.TextColor3 = COLORS.WHITE end
    if Top then
        Top.BackgroundColor3 = COLORS.PINK_MEDIUM
        Top.BackgroundTransparency = 0.15
    end
    if Favorite and not favoriteEnabled then
        Favorite.BackgroundColor3 = COLORS.PINK_MEDIUM
        Favorite.BackgroundTransparency = 0.15
    end
    if ModeToggle then
        ModeToggle.BackgroundColor3 = currentMode == "animation" and COLORS.PINK_ANIM or COLORS.PINK_MEDIUM
        ModeToggle.BackgroundTransparency = 0.15
    end
    if ReloadBtn then
        ReloadBtn.BackgroundColor3 = getgenv().autoReloadEnabled and COLORS.PINK_HEART or COLORS.PINK_MEDIUM
        ReloadBtn.BackgroundTransparency = 0.15
        ReloadBtn.Visible = currentMode == "animation"
    end
end

--============ PAGINATION ============--

local function calculateTotalPages()
    if currentMode == "animation" then
        local favs = _G.filteredFavoritesAnimationsForDisplay or favoriteAnimations
        local hasFavorites = #favs > 0
        local normalCount = 0
        for i = 1, #filteredAnimations do
            if not isInFavorites(filteredAnimations[i].id) then
                normalCount = normalCount + 1
            end
        end
        local pages = 0
        if hasFavorites then pages = pages + math.ceil(#favs / itemsPerPage) end
        if normalCount > 0 then pages = pages + math.ceil(normalCount / itemsPerPage) end
        return math.max(pages, 1)
    else
        local favs = _G.filteredFavoritesForDisplay or favoriteEmotes
        local hasFavorites = #favs > 0
        local normalCount = 0
        for i = 1, #filteredEmotes do
            if not isInFavorites(filteredEmotes[i].id) then
                normalCount = normalCount + 1
            end
        end
        local pages = 0
        if hasFavorites then pages = pages + math.ceil(#favs / itemsPerPage) end
        if normalCount > 0 then pages = pages + math.ceil(normalCount / itemsPerPage) end
        return math.max(pages, 1)
    end
end

local function updatePageDisplay()
    if _4pages and _2Routenumber then
        _4pages.Text = tostring(totalPages)
        _2Routenumber.Text = tostring(currentPage)
    end
end

--============ APPLY ANIMATION (FIXED) ============--

local function applyAnimation(data)
    if not data then
        Notify({Title = '💗 Animation', Content = '❌ No animation data', Duration = 3})
        return
    end
    
    local char = player.Character or player.CharacterAdded:Wait()
    local hum = char:FindFirstChild("Humanoid")
    local animate = char:FindFirstChild("Animate")
    
    if not animate then
        Notify({Title = '💗 Animation', Content = '❌ Animate not found', Duration = 3})
        return
    end
    
    if not hum then
        Notify({Title = '💗 Animation', Content = '❌ Humanoid not found', Duration = 3})
        return
    end
    
    -- Get bundledItems - try multiple sources
    local bundledItems = data.bundledItems
    
    if not bundledItems then
        bundledItems = getBundledItemsForAnimation(data.id)
    end
    
    if not bundledItems then
        Notify({Title = '💗 Animation', Content = '❌ No assets for: ' .. (data.name or tostring(data.id)), Duration = 3})
        return
    end
    
    -- Save for auto-reload
    getgenv().lastPlayedAnimation = {
        id = data.id,
        name = data.name,
        bundledItems = bundledItems
    }
    
    -- Stop current animations
    for _, track in pairs(hum:GetPlayingAnimationTracks()) do
        track:Stop()
    end
    
    local appliedCount = 0
    
    for key, assetIds in pairs(bundledItems) do
        for _, assetId in pairs(assetIds) do
            spawn(function()
                local success, objects = pcall(function()
                    return game:GetObjects("rbxassetid://" .. assetId)
                end)
                
                if success and objects and #objects > 0 then
                    local function searchForAnimations(parent, parentPath)
                        for _, child in pairs(parent:GetChildren()) do
                            if child:IsA("Animation") then
                                local animationPath = parentPath .. "." .. child.Name
                                local pathParts = animationPath:split(".")
                                
                                if #pathParts >= 2 then
                                    local animateCategory = pathParts[#pathParts - 1]
                                    local animationName = pathParts[#pathParts]
                                    
                                    local categoryFolder = animate:FindFirstChild(animateCategory)
                                    if categoryFolder then
                                        local animSlot = categoryFolder:FindFirstChild(animationName)
                                        if animSlot then
                                            animSlot.AnimationId = child.AnimationId
                                            appliedCount = appliedCount + 1
                                            
                                            task.wait(0.1)
                                            local animation = Instance.new("Animation")
                                            animation.AnimationId = child.AnimationId
                                            
                                            local animator = hum:FindFirstChild("Animator")
                                            if animator then
                                                local animTrack = animator:LoadAnimation(animation)
                                                animTrack.Priority = Enum.AnimationPriority.Action
                                                animTrack:Play()
                                                
                                                task.wait(0.1)
                                                animTrack:Stop()
                                            end
                                        end
                                    end
                                end
                            elseif #child:GetChildren() > 0 then
                                searchForAnimations(child, parentPath .. "." .. child.Name)
                            end
                        end
                    end
                    
                    for _, obj in pairs(objects) do
                        searchForAnimations(obj, obj.Name)
                        obj.Parent = workspace
                        task.delay(1, function()
                            if obj and obj.Parent then obj:Destroy() end
                        end)
                    end
                end
            end)
        end
    end
    
    Notify({Title = '💗 Animation', Content = '✅ Applied: ' .. (data.name or "Animation"), Duration = 3})
end

--============ UPDATE DISPLAY ============--

local function updateAnimations()
    local char, hum = getCharacterAndHumanoid()
    if not char or not hum or not hum.HumanoidDescription then return end
    
    local desc = hum.HumanoidDescription
    local currentPageAnims = {}
    local animTable = {}
    local equippedAnims = {}
    
    local favs = _G.filteredFavoritesAnimationsForDisplay or favoriteAnimations
    local hasFavorites = #favs > 0
    local favPagesCount = hasFavorites and math.ceil(#favs / itemsPerPage) or 0
    local isInFavoritesPages = currentPage <= favPagesCount
    
    if isInFavoritesPages and hasFavorites then
        local startIndex = (currentPage - 1) * itemsPerPage + 1
        local endIndex = math.min(startIndex + itemsPerPage - 1, #favs)
        for i = startIndex, endIndex do
            if favs[i] then
                local bundled = favs[i].bundledItems or getBundledItemsForAnimation(favs[i].id)
                table.insert(currentPageAnims, {
                    id = tonumber(favs[i].id), 
                    name = favs[i].name, 
                    bundledItems = bundled
                })
            end
        end
    else
        local normalAnims = {}
        for i = 1, #filteredAnimations do
            if not isInFavorites(filteredAnimations[i].id) then
                table.insert(normalAnims, filteredAnimations[i])
            end
        end
        local adjustedPage = currentPage - favPagesCount
        local startIndex = (adjustedPage - 1) * itemsPerPage + 1
        local endIndex = math.min(startIndex + itemsPerPage - 1, #normalAnims)
        for i = startIndex, endIndex do
            if normalAnims[i] then
                table.insert(currentPageAnims, normalAnims[i])
            end
        end
    end
    
    for _, anim in pairs(currentPageAnims) do
        animTable[anim.name] = {anim.id}
        table.insert(equippedAnims, anim.name)
    end
    
    desc:SetEmotes(animTable)
    desc:SetEquippedEmotes(equippedAnims)
    
    task.wait(0.1)
    updateAnimationImages(currentPageAnims)
    task.delay(0.2, function()
        if favoriteEnabled then updateAllFavoriteIcons() end
    end)
end

local function updateEmotes()
    if currentMode == "animation" then
        updateAnimations()
        return
    end
    
    local char, hum = getCharacterAndHumanoid()
    if not char or not hum or not hum.HumanoidDescription then return end
    
    local desc = hum.HumanoidDescription
    local currentPageEmotes = {}
    local emoteTable = {}
    local equippedEmotes = {}
    
    local favs = _G.filteredFavoritesForDisplay or favoriteEmotes
    local hasFavorites = #favs > 0
    local favPagesCount = hasFavorites and math.ceil(#favs / itemsPerPage) or 0
    local isInFavoritesPages = currentPage <= favPagesCount
    
    if isInFavoritesPages and hasFavorites then
        local startIndex = (currentPage - 1) * itemsPerPage + 1
        local endIndex = math.min(startIndex + itemsPerPage - 1, #favs)
        for i = startIndex, endIndex do
            if favs[i] then
                table.insert(currentPageEmotes, {id = tonumber(favs[i].id), name = favs[i].name})
            end
        end
    else
        local normalEmotes = {}
        for i = 1, #filteredEmotes do
            if not isInFavorites(filteredEmotes[i].id) then
                table.insert(normalEmotes, filteredEmotes[i])
            end
        end
        local adjustedPage = currentPage - favPagesCount
        local startIndex = (adjustedPage - 1) * itemsPerPage + 1
        local endIndex = math.min(startIndex + itemsPerPage - 1, #normalEmotes)
        for i = startIndex, endIndex do
            if normalEmotes[i] then
                table.insert(currentPageEmotes, normalEmotes[i])
            end
        end
    end
    
    for _, emote in pairs(currentPageEmotes) do
        emoteTable[emote.name] = {emote.id}
        table.insert(equippedEmotes, emote.name)
    end
    
    desc:SetEmotes(emoteTable)
    desc:SetEquippedEmotes(equippedEmotes)
    
    task.delay(0.15, updateAllFavoriteIcons)
end

--============ FAVORITES ============--

local function toggleFavorite(id, name, bundledItems)
    local favoriteList = currentMode == "animation" and favoriteAnimations or favoriteEmotes
    local found = false
    local index = 0
    local idStr = tostring(id)
    
    for i = 1, #favoriteList do
        if tostring(favoriteList[i].id) == idStr then
            found = true
            index = i
            break
        end
    end
    
    if found then
        table.remove(favoriteList, index)
        Notify({Title = '💗 Favorites', Content = 'Removed "' .. name .. '"', Duration = 3})
    else
        if currentMode == "animation" then
            local items = bundledItems or getBundledItemsForAnimation(id)
            table.insert(favoriteList, {id = id, name = name .. " 💗", bundledItems = items})
        else
            table.insert(favoriteList, {id = id, name = name .. " 💗"})
        end
        Notify({Title = '💗 Favorites', Content = 'Added "' .. name .. '"', Duration = 3})
    end
    
    if currentMode == "animation" then
        saveFavoritesAnimations()
    else
        saveFavorites()
    end
    
    totalPages = calculateTotalPages()
    updatePageDisplay()
    updateEmotes()
end

--============ CLICK DETECTION FOR ANIMATIONS ============--

local function handleSectorAction(index)
    local currentTime = tick()
    if currentTime - lastRadialActionTime < 0.25 then return end
    lastRadialActionTime = currentTime
    
    task.wait(0.05)
    
    local favs, filteredList
    if currentMode == "animation" then
        favs = _G.filteredFavoritesAnimationsForDisplay or favoriteAnimations
        filteredList = filteredAnimations
    else
        favs = _G.filteredFavoritesForDisplay or favoriteEmotes
        filteredList = filteredEmotes
    end
    
    local hasFavorites = #favs > 0
    local favPagesCount = hasFavorites and math.ceil(#favs / itemsPerPage) or 0
    local isInFavoritesPages = currentPage <= favPagesCount
    
    local function getItemAtIndex(idx)
        if isInFavoritesPages and hasFavorites then
            local startIndex = (currentPage - 1) * itemsPerPage + 1
            local item = favs[startIndex + idx - 1]
            if item and currentMode == "animation" and not item.bundledItems then
                item.bundledItems = getBundledItemsForAnimation(item.id)
            end
            return item
        else
            local normalList = {}
            for _, item in pairs(filteredList) do
                if not isInFavorites(item.id) then
                    table.insert(normalList, item)
                end
            end
            local adjustedPage = currentPage - favPagesCount
            local startIndex = (adjustedPage - 1) * itemsPerPage + 1
            return normalList[startIndex + idx - 1]
        end
    end
    
    local itemData = getItemAtIndex(index)
    if not itemData then return end
    
    if favoriteEnabled then
        toggleFavorite(itemData.id, itemData.name, itemData.bundledItems)
    else
        if currentMode == "animation" then
            applyAnimation(itemData)
        end
    end
end

-- Input detection for animation wheel clicks
UserInputService.InputBegan:Connect(function(input)
    if currentMode ~= "animation" and not favoriteEnabled then return end
    if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
    
    local exists, wheel = checkEmotesMenuExists()
    if not (exists and (wheel.Visible or tick() - lastWheelVisibleTime < 0.15)) then return end
    
    local pos = Vector2.new(input.Position.X, input.Position.Y)
    local aPos, aSize = wheel.AbsolutePosition, wheel.AbsoluteSize
    
    if pos.X < aPos.X or pos.X > aPos.X + aSize.X or pos.Y < aPos.Y or pos.Y > aPos.Y + aSize.Y then return end
    
    local center = aPos + aSize / 2
    local dx, dy = pos.X - center.X, pos.Y - center.Y
    local distance = math.sqrt(dx * dx + dy * dy)
    
    if distance < aSize.X * 0.1 then return end
    
    local angle = math.deg(math.atan2(dy, dx))
    local correctedAngle = (angle + 90 + 22.5) % 360
    local sectorIndex = math.floor(correctedAngle / 45) + 1
    
    handleSectorAction(sectorIndex)
end)

-- Track wheel visibility
RunService.Heartbeat:Connect(function()
    local ok, m = pcall(function() return CoreGui.RobloxGui.EmotesMenu.Children end)
    if ok and m then
        pcall(function()
            if m.Main.EmotesWheel.Visible then
                lastWheelVisibleTime = tick()
            end
        end)
    end
end)

--============ EMOTE CLICK DETECTION ============--

local function setupEmoteClickDetection()
    if isMonitoringClicks then return end
    
    local function monitorEmotes()
        while favoriteEnabled and currentMode == "emote" do
            pcall(function()
                local emotesWheel = getEmotesWheel()
                if not emotesWheel then return end
                
                local front = emotesWheel:FindFirstChild("Front")
                if not front then return end
                local frontFrame = front:FindFirstChild("EmotesButtons")
                if not frontFrame then return end
                
                for i = 1, #emoteClickConnections do
                    local conn = emoteClickConnections[i]
                    if conn then conn:Disconnect() end
                end
                emoteClickConnections = {}
                
                for _, child in pairs(frontFrame:GetChildren()) do
                    if child:IsA("ImageLabel") and child.Image ~= "" then
                        local clickDetector = child:FindFirstChild("ClickDetector")
                        if not clickDetector then
                            clickDetector = Instance.new("TextButton")
                            clickDetector.Name = "ClickDetector"
                            clickDetector.Size = UDim2.new(1, 0, 1, 0)
                            clickDetector.BackgroundTransparency = 1
                            clickDetector.Text = ""
                            clickDetector.ZIndex = child.ZIndex + 1
                            clickDetector.Parent = child
                        end
                        
                        local assetId = extractAssetId(child.Image)
                        if assetId then
                            updateFavoriteIcon(child, assetId, isInFavorites(assetId))
                            
                            local connection = clickDetector.MouseButton1Click:Connect(function()
                                if favoriteEnabled and assetId then
                                    toggleFavorite(assetId, getEmoteName(assetId), nil)
                                end
                            end)
                            table.insert(emoteClickConnections, connection)
                        end
                    end
                end
            end)
            task.wait(0.15)
        end
        
        for i = 1, #emoteClickConnections do
            local conn = emoteClickConnections[i]
            if conn then conn:Disconnect() end
        end
        emoteClickConnections = {}
        isMonitoringClicks = false
    end
    
    if favoriteEnabled then
        isMonitoringClicks = true
        task.spawn(monitorEmotes)
    end
end

local function stopEmoteClickDetection()
    isMonitoringClicks = false
    for i = 1, #emoteClickConnections do
        local conn = emoteClickConnections[i]
        if conn then conn:Disconnect() end
    end
    emoteClickConnections = {}
end

local function toggleFavoriteMode()
    favoriteEnabled = not favoriteEnabled
    
    if favoriteEnabled then
        if Favorite then
            Favorite.BackgroundColor3 = COLORS.PINK_HEART
            Favorite.BackgroundTransparency = 0.1
        end
        Notify({Title = '💗 Favorites', Content = "Click to add hearts!", Duration = 5})
        if currentMode == "emote" then
            setupEmoteClickDetection()
        end
        updateAllFavoriteIcons()
    else
        if Favorite then
            Favorite.BackgroundColor3 = COLORS.PINK_MEDIUM
            Favorite.BackgroundTransparency = 0.15
        end
        Notify({Title = '💗 Favorites', Content = 'Favorite mode OFF', Duration = 3})
        stopEmoteClickDetection()
        updateAllFavoriteIcons()
    end
end

--============ DATA FETCHING ============--

local function fetchAllEmotes()
    if isLoading then return end
    isLoading = true
    emotesData = {}
    totalLoaded = 0
    
    local success, result = pcall(function()
        local jsonContent = game:HttpGet(EMOTE_DATABASE_URL)
        if jsonContent and jsonContent ~= "" then
            return HttpService:JSONDecode(jsonContent)
        end
        return nil
    end)
    
    if success and result then
        local emotesList = result.data or result
        for i = 1, #emotesList do
            local item = emotesList[i]
            local emoteId = tonumber(item.id)
            if emoteId and emoteId > 0 then
                table.insert(emotesData, {id = emoteId, name = item.name or ("Emote_" .. item.id)})
                totalLoaded = totalLoaded + 1
            end
        end
    end
    
    originalEmotesData = emotesData
    filteredEmotes = emotesData
    isLoading = false
end

local function fetchAllAnimations()
    if isLoading then return end
    isLoading = true
    animationsData = {}
    
    local success, result = pcall(function()
        local jsonContent = game:HttpGet(ANIMATION_DATABASE_URL)
        if jsonContent and jsonContent ~= "" then
            return HttpService:JSONDecode(jsonContent)
        end
        return nil
    end)
    
    if success and result then
        local animList = result.data or result
        for i = 1, #animList do
            local item = animList[i]
            local animId = tonumber(item.id)
            if animId and animId > 0 then
                table.insert(animationsData, {
                    id = animId,
                    name = item.name or ("Animation_" .. item.id),
                    bundledItems = item.bundledItems
                })
            end
        end
    end
    
    originalAnimationsData = animationsData
    filteredAnimations = animationsData
    isLoading = false
end

--============ SEARCH ============--

local function searchEmotes(searchTerm)
    if isLoading then return end
    searchTerm = searchTerm:lower()
    
    if currentMode == "animation" then
        if searchTerm == "" then
            filteredAnimations = originalAnimationsData
            _G.filteredFavoritesAnimationsForDisplay = nil
        else
            local isIdSearch = searchTerm:match("^%d+$")
            local newFilteredList = {}
            
            for i = 1, #originalAnimationsData do
                local anim = originalAnimationsData[i]
                if (isIdSearch and tostring(anim.id) == searchTerm) or (not isIdSearch and anim.name:lower():find(searchTerm)) then
                    table.insert(newFilteredList, anim)
                end
            end
            filteredAnimations = newFilteredList
            
            if not isIdSearch then
                _G.filteredFavoritesAnimationsForDisplay = {}
                for i = 1, #favoriteAnimations do
                    if favoriteAnimations[i].name:lower():find(searchTerm) then
                        table.insert(_G.filteredFavoritesAnimationsForDisplay, favoriteAnimations[i])
                    end
                end
            end
        end
    else
        if searchTerm == "" then
            filteredEmotes = originalEmotesData
            _G.filteredFavoritesForDisplay = nil
        else
            local isIdSearch = searchTerm:match("^%d%d%d%d%d+$")
            local newFilteredList = {}
            
            if isIdSearch then
                for i = 1, #originalEmotesData do
                    local emote = originalEmotesData[i]
                    if tostring(emote.id) == searchTerm then
                        table.insert(newFilteredList, emote)
                    end
                end
                if #newFilteredList == 0 then
                    local emoteId = tonumber(searchTerm)
                    if emoteId then
                        local newEmote = {id = emoteId, name = getEmoteName(emoteId)}
                        table.insert(originalEmotesData, newEmote)
                        table.insert(newFilteredList, newEmote)
                    end
                end
            else
                for i = 1, #originalEmotesData do
                    local emote = originalEmotesData[i]
                    if emote.name:lower():find(searchTerm) then
                        table.insert(newFilteredList, emote)
                    end
                end
            end
            filteredEmotes = newFilteredList
            
            if not isIdSearch then
                _G.filteredFavoritesForDisplay = {}
                for i = 1, #favoriteEmotes do
                    if favoriteEmotes[i].name:lower():find(searchTerm) then
                        table.insert(_G.filteredFavoritesForDisplay, favoriteEmotes[i])
                    end
                end
            end
        end
    end
    
    totalPages = calculateTotalPages()
    currentPage = 1
    updatePageDisplay()
    updateEmotes()
end

--============ NAVIGATION ============--

local function goToPage(pageNumber)
    currentPage = math.clamp(pageNumber, 1, totalPages)
    updatePageDisplay()
    updateEmotes()
end

local function previousPage()
    currentPage = currentPage <= 1 and totalPages or currentPage - 1
    updatePageDisplay()
    updateEmotes()
end

local function nextPage()
    currentPage = currentPage >= totalPages and 1 or currentPage + 1
    updatePageDisplay()
    updateEmotes()
end

--============ MODE TOGGLE ============--

local function toggleMode()
    stopEmoteClickDetection()
    
    if currentMode == "emote" then
        currentMode = "animation"
        if #animationsData == 0 then
            fetchAllAnimations()
        end
        Notify({Title = '💗 Mode', Content = '🎬 Animation Mode', Duration = 3})
    else
        currentMode = "emote"
        Notify({Title = '💗 Mode', Content = '💃 Emote Mode', Duration = 3})
    end
    
    if Search then Search.Text = "" end
    _G.filteredFavoritesForDisplay = nil
    _G.filteredFavoritesAnimationsForDisplay = nil
    
    if currentMode == "animation" then
        filteredAnimations = originalAnimationsData
    else
        filteredEmotes = originalEmotesData
    end
    
    currentPage = 1
    totalPages = calculateTotalPages()
    updatePageDisplay()
    updateEmotes()
    updateGUIColors()
    
    if favoriteEnabled and currentMode == "emote" then
        setupEmoteClickDetection()
    end
end

local function toggleAutoReload()
    getgenv().autoReloadEnabled = not getgenv().autoReloadEnabled
    if getgenv().autoReloadEnabled then
        Notify({Title = '💗 Auto-Reload', Content = '🔄 ON - Animations persist on respawn!', Duration = 5})
    else
        Notify({Title = '💗 Auto-Reload', Content = '🔄 OFF', Duration = 3})
    end
    updateGUIColors()
end

--============ BUTTON HELPERS ============--

local function safeButtonClick(buttonName, callback)
    local currentTime = tick()
    if not clickCooldown[buttonName] or (currentTime - clickCooldown[buttonName]) > 0.15 then
        clickCooldown[buttonName] = currentTime
        callback()
    end
end

local function connectEvents()
    if _1left then _1left.MouseButton1Click:Connect(previousPage) end
    if _9right then _9right.MouseButton1Click:Connect(nextPage) end
    
    if _2Routenumber then
        _2Routenumber.FocusLost:Connect(function()
            local pageNum = tonumber(_2Routenumber.Text)
            if pageNum then
                goToPage(pageNum)
            else
                _2Routenumber.Text = tostring(currentPage)
            end
        end)
    end
    
    if Search then
        Search:GetPropertyChangedSignal("Text"):Connect(function()
            searchEmotes(Search.Text)
        end)
    end
    
    if Favorite then
        Favorite.MouseButton1Click:Connect(function()
            safeButtonClick("Favorite", toggleFavoriteMode)
        end)
    end
    
    if ModeToggle then
        ModeToggle.MouseButton1Click:Connect(function()
            safeButtonClick("ModeToggle", toggleMode)
        end)
    end
    
    if ReloadBtn then
        ReloadBtn.MouseButton1Click:Connect(function()
            safeButtonClick("ReloadBtn", toggleAutoReload)
        end)
    end
end

--============ GUI CREATION ============--

local function createGUIElements()
    local exists, emotesWheel = checkEmotesMenuExists()
    if not exists then return false end
    
    local elementsToClean = {"Under", "Top", "Favorite", "ModeToggle", "ReloadBtn"}
    for i = 1, #elementsToClean do
        local element = emotesWheel:FindFirstChild(elementsToClean[i])
        if element then element:Destroy() end
    end
    
    -- Bottom navigation
    Under = Instance.new("Frame")
    Under.Name = "Under"
    Under.Parent = emotesWheel
    Under.BackgroundTransparency = 1
    Under.BorderSizePixel = 0
    Under.Position = UDim2.new(0.13, 0, 1, 0)
    Under.Size = UDim2.new(0.74, 0, 0.13, 0)
    
    UIListLayout = Instance.new("UIListLayout")
    UIListLayout.Parent = Under
    UIListLayout.FillDirection = Enum.FillDirection.Horizontal
    UIListLayout.VerticalAlignment = Enum.VerticalAlignment.Center
    
    _1left = Instance.new("ImageButton")
    _1left.Name = "1left"
    _1left.Parent = Under
    _1left.BackgroundTransparency = 1
    _1left.Size = UDim2.new(0.17, 0, 0.94, 0)
    _1left.Image = "rbxassetid://93111945058621"
    _1left.ImageColor3 = COLORS.PINK_MEDIUM
    
    _9right = Instance.new("ImageButton")
    _9right.Name = "9right"
    _9right.Parent = Under
    _9right.BackgroundTransparency = 1
    _9right.Size = UDim2.new(0.17, 0, 0.94, 0)
    _9right.Image = "rbxassetid://107938916240738"
    _9right.ImageColor3 = COLORS.PINK_MEDIUM
    
    _4pages = Instance.new("TextLabel")
    _4pages.Name = "4pages"
    _4pages.Parent = Under
    _4pages.BackgroundTransparency = 1
    _4pages.Size = UDim2.new(0.16, 0, 0.81, 0)
    _4pages.Font = Enum.Font.GothamBold
    _4pages.Text = "1"
    _4pages.TextColor3 = COLORS.WHITE
    _4pages.TextScaled = true
    
    _3TextLabel = Instance.new("TextLabel")
    _3TextLabel.Name = "3TextLabel"
    _3TextLabel.Parent = Under
    _3TextLabel.BackgroundTransparency = 1
    _3TextLabel.Size = UDim2.new(0.34, 0, 0.94, 0)
    _3TextLabel.Font = Enum.Font.GothamBold
    _3TextLabel.Text = " --- "
    _3TextLabel.TextColor3 = COLORS.WHITE
    _3TextLabel.TextScaled = true
    
    _2Routenumber = Instance.new("TextBox")
    _2Routenumber.Name = "2Route-number"
    _2Routenumber.Parent = Under
    _2Routenumber.BackgroundTransparency = 1
    _2Routenumber.Size = UDim2.new(0.16, 0, 0.81, 0)
    _2Routenumber.Font = Enum.Font.GothamBold
    _2Routenumber.Text = "1"
    _2Routenumber.TextColor3 = COLORS.WHITE
    _2Routenumber.TextScaled = true
    
    -- Top search bar
    Top = Instance.new("Frame")
    Top.Name = "Top"
    Top.Parent = emotesWheel
    Top.BackgroundColor3 = COLORS.PINK_MEDIUM
    Top.BackgroundTransparency = 0.15
    Top.BorderSizePixel = 0
    Top.Position = UDim2.new(0.13, 0, -0.11, 0)
    Top.Size = UDim2.new(0.74, 0, 0.095, 0)
    
    UICorner = Instance.new("UICorner")
    UICorner.CornerRadius = UDim.new(0, 20)
    UICorner.Parent = Top
    
    UIListLayout_2 = Instance.new("UIListLayout")
    UIListLayout_2.Parent = Top
    UIListLayout_2.FillDirection = Enum.FillDirection.Horizontal
    UIListLayout_2.HorizontalAlignment = Enum.HorizontalAlignment.Center
    UIListLayout_2.VerticalAlignment = Enum.VerticalAlignment.Center
    
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
    
    -- Heart Button (Favorite)
    Favorite = Instance.new("ImageButton")
    Favorite.Name = "Favorite"
    Favorite.Parent = emotesWheel
    Favorite.BackgroundColor3 = COLORS.PINK_MEDIUM
    Favorite.BackgroundTransparency = 0.15
    Favorite.BorderSizePixel = 0
    Favorite.Position = UDim2.new(0.019, 0, -0.108, 0)
    Favorite.Size = UDim2.new(0.0875, 0, 0.0875, 0)
    Favorite.Image = ""
    
    local heartText = Instance.new("TextLabel")
    heartText.Parent = Favorite
    heartText.BackgroundTransparency = 1
    heartText.Size = UDim2.new(1, 0, 1, 0)
    heartText.Font = Enum.Font.SourceSans
    heartText.Text = "💗"
    heartText.TextScaled = true
    heartText.ZIndex = Favorite.ZIndex + 1
    
    Instance.new("UICorner", Favorite).CornerRadius = UDim.new(0, 10)
    
    -- Mode Toggle Button (Emote/Animation)
    ModeToggle = Instance.new("ImageButton")
    ModeToggle.Name = "ModeToggle"
    ModeToggle.Parent = emotesWheel
    ModeToggle.BackgroundColor3 = COLORS.PINK_MEDIUM
    ModeToggle.BackgroundTransparency = 0.15
    ModeToggle.BorderSizePixel = 0
    ModeToggle.Position = UDim2.new(0.889, 0, -0.108, 0)
    ModeToggle.Size = UDim2.new(0.0875, 0, 0.0875, 0)
    ModeToggle.Image = ""
    
    local modeText = Instance.new("TextLabel")
    modeText.Parent = ModeToggle
    modeText.BackgroundTransparency = 1
    modeText.Size = UDim2.new(1, 0, 1, 0)
    modeText.Font = Enum.Font.SourceSans
    modeText.Text = "🎬"
    modeText.TextScaled = true
    modeText.ZIndex = ModeToggle.ZIndex + 1
    
    Instance.new("UICorner", ModeToggle).CornerRadius = UDim.new(0, 10)
    
    -- Auto-Reload Button (only visible in animation mode)
    ReloadBtn = Instance.new("ImageButton")
    ReloadBtn.Name = "ReloadBtn"
    ReloadBtn.Parent = emotesWheel
    ReloadBtn.BackgroundColor3 = COLORS.PINK_MEDIUM
    ReloadBtn.BackgroundTransparency = 0.15
    ReloadBtn.BorderSizePixel = 0
    ReloadBtn.Position = UDim2.new(0.889, 0, 1.02, 0)
    ReloadBtn.Size = UDim2.new(0.0875, 0, 0.0875, 0)
    ReloadBtn.Image = ""
    ReloadBtn.Visible = false
    
    local reloadText = Instance.new("TextLabel")
    reloadText.Parent = ReloadBtn
    reloadText.BackgroundTransparency = 1
    reloadText.Size = UDim2.new(1, 0, 1, 0)
    reloadText.Font = Enum.Font.SourceSans
    reloadText.Text = "🔄"
    reloadText.TextScaled = true
    reloadText.ZIndex = ReloadBtn.ZIndex + 1
    
    Instance.new("UICorner", ReloadBtn).CornerRadius = UDim.new(0, 10)
    
    applyPinkThemeToWheel()
    connectEvents()
    isGUICreated = true
    
    return true
end

local function checkAndRecreateGUI()
    local emotesWheel = getEmotesWheel()
    if not emotesWheel then
        isGUICreated = false
        return
    end
    
    if not emotesWheel:FindFirstChild("Under") or not emotesWheel:FindFirstChild("Top") or not emotesWheel:FindFirstChild("Favorite") then
        isGUICreated = false
        if createGUIElements() then
            updatePageDisplay()
            updateEmotes()
        end
    end
end

--============ CHARACTER HANDLING ============--

local function onCharacterAdded(char)
    local hum = char:WaitForChild("Humanoid")
    
    -- Auto-reload animation
    if getgenv().autoReloadEnabled and getgenv().lastPlayedAnimation then
        task.wait(0.5)
        applyAnimation(getgenv().lastPlayedAnimation)
        Notify({Title = '💗 Auto-Reload', Content = '🔄 Animation reapplied!', Duration = 3})
    end
    
    hum.Died:Connect(function()
        favoriteEnabled = false
        stopEmotes()
    end)
end

if player.Character then
    onCharacterAdded(player.Character)
end

player.CharacterAdded:Connect(function(char)
    character = char
    humanoid = char:WaitForChild("Humanoid")
    favoriteEnabled = false
    cachedEmotesWheel = nil
    
    onCharacterAdded(char)
    
    task.wait(0.3)
    task.spawn(function()
        while not checkEmotesMenuExists() do
            task.wait(0.1)
        end
        task.wait(0.3)
        stopEmotes()
        if createGUIElements() then
            updatePageDisplay()
            updateEmotes()
        end
    end)
end)

--============ MAIN LOOPS ============--

RunService.RenderStepped:Connect(function()
    frameCount = frameCount + 1
    if frameCount >= FRAME_CHECK_INTERVAL then
        frameCount = 0
        if not isGUICreated then
            checkAndRecreateGUI()
        else
            updateGUIColors()
        end
    end
end)

-- Initial setup
task.spawn(function()
    while not checkEmotesMenuExists() do
        task.wait(0.1)
    end
    if createGUIElements() then
        loadFavorites()
        loadFavoritesAnimations()
        fetchAllEmotes()
        fetchAllAnimations()
        totalPages = calculateTotalPages()
        updatePageDisplay()
        updateEmotes()
        Notify({Title = '💗 PinkWards', Content = 'Loaded! Press "." to open', Duration = 5})
    end
end)

StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Chat, true)

task.spawn(function()
    while true do
        pcall(function()
            local emotesMenu = CoreGui:FindFirstChild("RobloxGui")
            emotesMenu = emotesMenu and emotesMenu:FindFirstChild("EmotesMenu")
            if not emotesMenu then
                StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.EmotesMenu, true)
            else
                local emotesWheel = getEmotesWheel()
                if emotesWheel and not emotesWheel:FindFirstChild("Under") then
                    createGUIElements()
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
        local openButton = Instance.new("ScreenGui")
        openButton.Name = "EmoteOpenButton"
        openButton.ResetOnSpawn = false
        
        if syn and syn.protect_gui then
            syn.protect_gui(openButton)
            openButton.Parent = CoreGui
        elseif gethui then
            openButton.Parent = gethui()
        else
            openButton.Parent = CoreGui
        end
        
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(0, 55, 0, 55)
        btn.Position = UDim2.new(0, 10, 0.5, -27)
        btn.BackgroundColor3 = COLORS.PINK_MEDIUM
        btn.BackgroundTransparency = 0.15
        btn.Text = "💗"
        btn.TextSize = 28
        btn.TextColor3 = COLORS.WHITE
        btn.Parent = openButton
        
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 12)
        
        btn.MouseButton1Click:Connect(function()
            pcall(function()
                GuiService:SetEmotesMenuOpen(true)
            end)
        end)
    end)
    Notify({Title = '💗 Mobile', Content = 'Tap the heart to open!', Duration = 10})
end

if UserInputService.KeyboardEnabled then
    Notify({Title = '💗 PinkWards', Content = 'Press "." to open | 🎬 for animations!', Duration = 10})
end

print("=========================================")
print("   💗 PinkWards Emote + Animation System")
print("   Press '.' to open")
print("   🎬 = Toggle Animation Mode")
print("   💗 = Favorite Mode")
print("   🔄 = Auto-Reload (Animation Mode)")
print("=========================================")
