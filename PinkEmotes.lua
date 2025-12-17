--[[ 
    Pink Emote System
    Connected to: github.com/PinkWards/emote-sniper
    💗 Final Clean Version - Light & Smooth!
]]

if _G.EmotesGUIRunning then
    return
end
_G.EmotesGUIRunning = true

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")
local StarterGui = game:GetService("StarterGui")

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")

-- 💗 YOUR DATABASE 💗
local DATABASE_URL = "https://raw.githubusercontent.com/PinkWards/emote-sniper/main/EmoteSniper.json"

local emoteClickConnections = {}
local isMonitoringClicks = false

local emotesData = {}
local originalEmotesData = {}
local filteredEmotes = {}
local favoriteEmotes = {}
local favoriteFileName = "FavoriteEmotes.json"
local emoteSearchTerm = ""

local currentPage = 1
local itemsPerPage = 8
local totalPages = 1
local isLoading = false
local totalEmotesLoaded = 0
local favoriteEnabled = false
local isGUICreated = false

-- 💗 PINK THEME COLORS (LIGHTER!) 💗
local PINK_LIGHT = Color3.fromHex("#FFEBF2")      -- Very light pink
local PINK_MEDIUM = Color3.fromHex("#FFC8DC")     -- Light medium pink
local PINK_WHEEL = Color3.fromHex("#FFD9E8")      -- Light wheel background
local PINK_HEART = Color3.fromHex("#FF6B9D")      -- Heart pink
local WHITE = Color3.fromRGB(255, 255, 255)

-- 💗 LAG FIX: Throttle updates
local lastThemeUpdate = 0
local THEME_UPDATE_INTERVAL = 0.5  -- Only update theme every 0.5 seconds

local Under, UIListLayout, _1left, _9right, _4pages, _3TextLabel, _2Routenumber, Top,
    UIListLayout_2, UICorner, Search, Favorite, UICorner2

local function Notify(data)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = data.Title or "Notification",
            Text = data.Content or "",
            Duration = data.Duration or 5
        })
    end)
end

local function stopEmotes()
    pcall(function()
        for _, track in ipairs(humanoid:GetPlayingAnimationTracks()) do
            track:Stop()
        end
    end)
end

local function getCharacterAndHumanoid()
    local char = player.Character
    if not char then return nil, nil end
    local hum = char:FindFirstChild("Humanoid")
    if not hum then return nil, nil end
    return char, hum
end

local function checkEmotesMenuExists()
    local success, emotesWheel = pcall(function()
        return CoreGui.RobloxGui.EmotesMenu.Children.Main.EmotesWheel
    end)
    if success and emotesWheel then
        return true, emotesWheel
    end
    return false, nil
end

local function saveFavorites()
    if writefile then
        pcall(function()
            writefile(favoriteFileName, HttpService:JSONEncode(favoriteEmotes))
        end)
    end
end

local function loadFavorites()
    if readfile and isfile and isfile(favoriteFileName) then
        pcall(function()
            favoriteEmotes = HttpService:JSONDecode(readfile(favoriteFileName))
        end)
    end
end

local function extractAssetId(imageUrl)
    return string.match(imageUrl, "Asset&id=(%d+)")
end

local function getEmoteName(assetId)
    local success, productInfo = pcall(function()
        return game:GetService("MarketplaceService"):GetProductInfo(tonumber(assetId))
    end)
    if success and productInfo then
        return productInfo.Name
    end
    return "Emote_" .. tostring(assetId)
end

local function isInFavorites(assetId)
    for _, favorite in pairs(favoriteEmotes) do
        if tostring(favorite.id) == tostring(assetId) then
            return true
        end
    end
    return false
end

-- 💗 SMALL HEART
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
            favoriteIcon.TextColor3 = WHITE
            favoriteIcon.Parent = imageLabel
        else
            favoriteIcon.Visible = true
        end
    else
        if favoriteIcon then
            favoriteIcon.Visible = false
        end
    end
end

-- 💗 APPLY LIGHT PINK TO WHEEL (Optimized - less loops!)
local function applyPinkThemeToWheel()
    pcall(function()
        local emotesWheel = CoreGui.RobloxGui.EmotesMenu.Children.Main.EmotesWheel
        
        -- Back layer
        local back = emotesWheel:FindFirstChild("Back")
        if back then
            local background = back:FindFirstChild("Background")
            if background then
                if background:IsA("Frame") then
                    background.BackgroundColor3 = PINK_WHEEL
                    background.BackgroundTransparency = 0.05  -- More visible, lighter
                end
                
                local overlay = background:FindFirstChild("BackgroundCircleOverlay")
                if overlay then
                    overlay.BackgroundColor3 = PINK_LIGHT
                    overlay.BackgroundTransparency = 0.1
                end
                
                -- Only style direct children (faster!)
                for _, child in pairs(background:GetChildren()) do
                    if child:IsA("ImageLabel") then
                        child.ImageColor3 = PINK_LIGHT
                        child.ImageTransparency = 0.05
                    end
                end
            end
        end
        
        -- Center - lighter colors
        local center = emotesWheel:FindFirstChild("Center")
        if center then
            for _, child in pairs(center:GetChildren()) do
                if child:IsA("Frame") then
                    child.BackgroundColor3 = PINK_MEDIUM
                    child.BackgroundTransparency = 0.2
                elseif child:IsA("ImageLabel") then
                    child.ImageColor3 = PINK_MEDIUM
                end
            end
        end
    end)
end

-- 💗 MAKE EMOTE ICONS LIGHTER (Optimized!)
local function lightenEmoteIcons()
    pcall(function()
        local emotesButtons = CoreGui.RobloxGui.EmotesMenu.Children.Main.EmotesWheel.Front.EmotesButtons
        
        for _, child in pairs(emotesButtons:GetChildren()) do
            if child:IsA("ImageLabel") then
                -- Make emote icons brighter/lighter
                child.ImageColor3 = Color3.fromRGB(255, 255, 255)  -- Full brightness
                child.ImageTransparency = 0  -- Fully visible
                child.BackgroundTransparency = 1  -- No background box
                
                -- Remove any added elements (faster cleanup)
                local stroke = child:FindFirstChild("PinkStroke")
                if stroke then stroke:Destroy() end
                
                local corner = child:FindFirstChild("PinkCorner") 
                if corner then corner:Destroy() end
                
                local bg = child:FindFirstChild("PinkBackground")
                if bg then bg:Destroy() end
            end
        end
    end)
end

-- 💗 OPTIMIZED: Update favorites only (not full theme)
local function updateAllFavoriteIcons()
    pcall(function()
        local frontFrame = CoreGui.RobloxGui.EmotesMenu.Children.Main.EmotesWheel.Front.EmotesButtons
        
        for _, child in pairs(frontFrame:GetChildren()) do
            if child:IsA("ImageLabel") and child.Image ~= "" then
                -- Make icon lighter
                child.ImageColor3 = WHITE
                child.ImageTransparency = 0
                child.BackgroundTransparency = 1
                
                local assetId = extractAssetId(child.Image)
                if assetId then
                    updateFavoriteIcon(child, assetId, isInFavorites(assetId))
                end
            end
        end
    end)
end

-- 💗 LAG FIX: Throttled color updates
local function updateGUIColors()
    local currentTime = tick()
    
    -- Only update theme every 0.5 seconds to reduce lag
    if currentTime - lastThemeUpdate < THEME_UPDATE_INTERVAL then
        return
    end
    lastThemeUpdate = currentTime
    
    applyPinkThemeToWheel()
    lightenEmoteIcons()
    
    -- Update UI elements
    if _1left then _1left.ImageColor3 = PINK_MEDIUM end
    if _9right then _9right.ImageColor3 = PINK_MEDIUM end
    if _4pages then _4pages.TextColor3 = WHITE end
    if _3TextLabel then _3TextLabel.TextColor3 = WHITE end
    if _2Routenumber then _2Routenumber.TextColor3 = WHITE end
    if Top then Top.BackgroundColor3 = PINK_MEDIUM; Top.BackgroundTransparency = 0.15 end
    if Favorite then 
        if not favoriteEnabled then
            Favorite.BackgroundColor3 = PINK_MEDIUM
            Favorite.BackgroundTransparency = 0.15
        end
    end
end

local function calculateTotalPages()
    local favoritesToUse = _G.filteredFavoritesForDisplay or favoriteEmotes
    local hasFavorites = #favoritesToUse > 0
    local normalEmotesCount = 0

    for _, emote in pairs(filteredEmotes) do
        if not isInFavorites(emote.id) then
            normalEmotesCount = normalEmotesCount + 1
        end
    end

    local pages = 0
    if hasFavorites then
        pages = pages + math.ceil(#favoritesToUse / itemsPerPage)
    end
    if normalEmotesCount > 0 then
        pages = pages + math.ceil(normalEmotesCount / itemsPerPage)
    end

    return math.max(pages, 1)
end

local function updateEmotes()
    local char, hum = getCharacterAndHumanoid()
    if not char or not hum then return end

    local humanoidDescription = hum.HumanoidDescription
    if not humanoidDescription then return end

    local currentPageEmotes = {}
    local emoteTable = {}
    local equippedEmotes = {}

    local favoritesToUse = _G.filteredFavoritesForDisplay or favoriteEmotes
    local hasFavorites = #favoritesToUse > 0
    local favoritePagesCount = hasFavorites and math.ceil(#favoritesToUse / itemsPerPage) or 0
    local isInFavoritesPages = currentPage <= favoritePagesCount

    if isInFavoritesPages and hasFavorites then
        local startIndex = (currentPage - 1) * itemsPerPage + 1
        local endIndex = math.min(startIndex + itemsPerPage - 1, #favoritesToUse)

        for i = startIndex, endIndex do
            if favoritesToUse[i] then
                table.insert(currentPageEmotes, {
                    id = tonumber(favoritesToUse[i].id),
                    name = favoritesToUse[i].name
                })
            end
        end
    else
        local normalEmotes = {}
        for _, emote in pairs(filteredEmotes) do
            if not isInFavorites(emote.id) then
                table.insert(normalEmotes, emote)
            end
        end

        local adjustedPage = currentPage - favoritePagesCount
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

    humanoidDescription:SetEmotes(emoteTable)
    humanoidDescription:SetEquippedEmotes(equippedEmotes)
    
    -- Delayed update for smoother experience
    task.delay(0.15, updateAllFavoriteIcons)
end

local function updatePageDisplay()
    if _4pages and _2Routenumber then
        _4pages.Text = tostring(totalPages)
        _2Routenumber.Text = tostring(currentPage)
    end
end

local function toggleFavorite(emoteId, emoteName)
    local found = false
    local index = 0

    for i, fav in pairs(favoriteEmotes) do
        if tostring(fav.id) == tostring(emoteId) then
            found = true
            index = i
            break
        end
    end

    if found then
        table.remove(favoriteEmotes, index)
        Notify({Title = '💗 Favorites', Content = 'Removed "' .. emoteName .. '"', Duration = 3})
    else
        table.insert(favoriteEmotes, {id = emoteId, name = emoteName .. " 💗"})
        Notify({Title = '💗 Favorites', Content = 'Added "' .. emoteName .. '"', Duration = 3})
    end

    saveFavorites()
    totalPages = calculateTotalPages()
    updatePageDisplay()
    updateEmotes()
end

local function setupEmoteClickDetection()
    if isMonitoringClicks then return end
   
    local function monitorEmotes()
        while favoriteEnabled do
            pcall(function()
                local frontFrame = CoreGui.RobloxGui.EmotesMenu.Children.Main.EmotesWheel.Front.EmotesButtons
                
                -- Disconnect old connections
                for _, connection in pairs(emoteClickConnections) do
                    if connection then connection:Disconnect() end
                end
                emoteClickConnections = {}
               
                for _, child in pairs(frontFrame:GetChildren()) do
                    if child:IsA("ImageLabel") and child.Image ~= "" then
                        local clickDetector = child:FindFirstChild("ClickDetector")
                        if not clickDetector then
                            clickDetector = Instance.new("TextButton")
                            clickDetector.Name = "ClickDetector"
                            clickDetector.Size = UDim2.new(1, 0, 1, 0)
                            clickDetector.Position = UDim2.new(0, 0, 0, 0)
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
                                    toggleFavorite(assetId, getEmoteName(assetId))
                                end
                            end)
                            table.insert(emoteClickConnections, connection)
                        end
                    end
                end
            end)
           
            task.wait(0.15)  -- Slightly faster response
        end
       
        for _, connection in pairs(emoteClickConnections) do
            if connection then connection:Disconnect() end
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
    
    for _, connection in pairs(emoteClickConnections) do
        if connection then connection:Disconnect() end
    end
    emoteClickConnections = {}
    
    pcall(function()
        local frontFrame = CoreGui.RobloxGui.EmotesMenu.Children.Main.EmotesWheel.Front.EmotesButtons
        for _, child in pairs(frontFrame:GetChildren()) do
            if child:IsA("ImageLabel") then
                local clickDetector = child:FindFirstChild("ClickDetector")
                if clickDetector then clickDetector:Destroy() end
            end
        end
    end)
end

local function fetchAllEmotes()
    if isLoading then return end
    isLoading = true
    emotesData = {}
    totalEmotesLoaded = 0

    Notify({Title = '💗 Pink Emotes', Content = 'Loading emotes...', Duration = 3})

    local success, result = pcall(function()
        local jsonContent = game:HttpGet(DATABASE_URL)
        if jsonContent and jsonContent ~= "" then
            return HttpService:JSONDecode(jsonContent)
        end
        return nil
    end)

    if success and result then
        local emotesList = result.data or result
        
        for _, item in pairs(emotesList) do
            local emoteData = {
                id = tonumber(item.id),
                name = item.name or ("Emote_" .. (item.id or "Unknown"))
            }
            if emoteData.id and emoteData.id > 0 then
                table.insert(emotesData, emoteData)
                totalEmotesLoaded = totalEmotesLoaded + 1
            end
        end
        
        Notify({Title = '💗 Pink Emotes', Content = "Loaded " .. totalEmotesLoaded .. " emotes!", Duration = 5})
    else
        emotesData = {
            {id = 3360686498, name = "Stadium"},
            {id = 3360692915, name = "Tilt"},
            {id = 3576968026, name = "Shrug"},
            {id = 3360689775, name = "Salute"}
        }
        totalEmotesLoaded = #emotesData
    end

    originalEmotesData = emotesData
    filteredEmotes = emotesData
    totalPages = calculateTotalPages()
    currentPage = 1
    updatePageDisplay()
    updateEmotes()
    isLoading = false
end

local function searchEmotes(searchTerm)
    if isLoading then return end

    searchTerm = searchTerm:lower()

    if searchTerm == "" then
        filteredEmotes = originalEmotesData
        _G.filteredFavoritesForDisplay = nil
    else
        local isIdSearch = searchTerm:match("^%d%d%d%d%d+$")
        local newFilteredList = {}
        
        if isIdSearch then
            for _, emote in pairs(originalEmotesData) do
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
            for _, emote in pairs(originalEmotesData) do
                if emote.name:lower():find(searchTerm) then
                    table.insert(newFilteredList, emote)
                end
            end
        end
        
        filteredEmotes = newFilteredList

        if not isIdSearch then
            _G.filteredFavoritesForDisplay = {}
            for _, favorite in pairs(favoriteEmotes) do
                if favorite.name:lower():find(searchTerm) then
                    table.insert(_G.filteredFavoritesForDisplay, favorite)
                end
            end
        end
    end

    totalPages = calculateTotalPages()
    currentPage = 1
    updatePageDisplay()
    updateEmotes()
end

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

local function onCharacterAdded(char)
    local hum = char:WaitForChild("Humanoid")
    hum.Died:Connect(function()
        favoriteEnabled = false
        stopEmotes()
    end)
end

local function toggleFavoriteMode()
    favoriteEnabled = not favoriteEnabled

    if favoriteEnabled then
        if Favorite then
            Favorite.BackgroundColor3 = PINK_HEART
            Favorite.BackgroundTransparency = 0.1
        end
        Notify({Title = '💗 Favorites', Content = "Click emotes to add hearts!", Duration = 5})
        setupEmoteClickDetection()
    else
        if Favorite then
            Favorite.BackgroundColor3 = PINK_MEDIUM
            Favorite.BackgroundTransparency = 0.15
        end
        Notify({Title = '💗 Favorites', Content = 'Favorite mode OFF', Duration = 3})
        stopEmoteClickDetection()
    end
end

local clickCooldown = {}

local function safeButtonClick(buttonName, callback)
    local currentTime = tick()
    if not clickCooldown[buttonName] or (currentTime - clickCooldown[buttonName]) > 0.15 then
        clickCooldown[buttonName] = currentTime
        callback()
    end
end

function connectEvents()
    if _1left then _1left.MouseButton1Click:Connect(previousPage) end
    if _9right then _9right.MouseButton1Click:Connect(nextPage) end
    
    if _2Routenumber then
        _2Routenumber.FocusLost:Connect(function()
            local pageNum = tonumber(_2Routenumber.Text)
            if pageNum then goToPage(pageNum) else _2Routenumber.Text = tostring(currentPage) end
        end)
    end
    
    if Search then
        Search.Changed:Connect(function(property)
            if property == "Text" then searchEmotes(Search.Text) end
        end)
    end
    
    if Favorite then
        Favorite.MouseButton1Click:Connect(function()
            safeButtonClick("Favorite", toggleFavoriteMode)
        end)
    end
end

local function createGUIElements()
    local exists, emotesWheel = checkEmotesMenuExists()
    if not exists then return false end

    -- Clean up old elements
    for _, name in pairs({"Under", "Top", "EmoteWalkButton", "Favorite", "SpeedEmote", "SpeedBox", "Changepage", "Reload"}) do
        local element = emotesWheel:FindFirstChild(name)
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
    _1left.ImageColor3 = PINK_MEDIUM

    _9right = Instance.new("ImageButton")
    _9right.Name = "9right"
    _9right.Parent = Under
    _9right.BackgroundTransparency = 1
    _9right.Size = UDim2.new(0.17, 0, 0.94, 0)
    _9right.Image = "rbxassetid://107938916240738"
    _9right.ImageColor3 = PINK_MEDIUM

    _4pages = Instance.new("TextLabel")
    _4pages.Name = "4pages"
    _4pages.Parent = Under
    _4pages.BackgroundTransparency = 1
    _4pages.Size = UDim2.new(0.16, 0, 0.81, 0)
    _4pages.Font = Enum.Font.GothamBold
    _4pages.Text = "1"
    _4pages.TextColor3 = WHITE
    _4pages.TextScaled = true

    _3TextLabel = Instance.new("TextLabel")
    _3TextLabel.Name = "3TextLabel"
    _3TextLabel.Parent = Under
    _3TextLabel.BackgroundTransparency = 1
    _3TextLabel.Size = UDim2.new(0.34, 0, 0.94, 0)
    _3TextLabel.Font = Enum.Font.GothamBold
    _3TextLabel.Text = " --- "
    _3TextLabel.TextColor3 = WHITE
    _3TextLabel.TextScaled = true

    _2Routenumber = Instance.new("TextBox")
    _2Routenumber.Name = "2Route-number"
    _2Routenumber.Parent = Under
    _2Routenumber.BackgroundTransparency = 1
    _2Routenumber.Size = UDim2.new(0.16, 0, 0.81, 0)
    _2Routenumber.Font = Enum.Font.GothamBold
    _2Routenumber.Text = "1"
    _2Routenumber.TextColor3 = WHITE
    _2Routenumber.TextScaled = true

    -- Top search bar (lighter!)
    Top = Instance.new("Frame")
    Top.Name = "Top"
    Top.Parent = emotesWheel
    Top.BackgroundColor3 = PINK_MEDIUM
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
    Search.PlaceholderColor3 = Color3.fromRGB(255, 210, 230)
    Search.Text = ""
    Search.TextColor3 = WHITE
    Search.TextScaled = true

    -- 💗 Heart Button (lighter!)
    Favorite = Instance.new("ImageButton")
    Favorite.Name = "Favorite"
    Favorite.Parent = emotesWheel
    Favorite.BackgroundColor3 = PINK_MEDIUM
    Favorite.BackgroundTransparency = 0.15
    Favorite.BorderSizePixel = 0
    Favorite.Position = UDim2.new(0.019, 0, -0.108, 0)
    Favorite.Size = UDim2.new(0.0875, 0, 0.0875, 0)
    Favorite.Image = ""

    local heartText = Instance.new("TextLabel")
    heartText.Name = "HeartText"
    heartText.Parent = Favorite
    heartText.BackgroundTransparency = 1
    heartText.Size = UDim2.new(1, 0, 1, 0)
    heartText.Font = Enum.Font.SourceSans
    heartText.Text = "💗"
    heartText.TextColor3 = WHITE
    heartText.TextScaled = true
    heartText.ZIndex = Favorite.ZIndex + 1

    UICorner2 = Instance.new("UICorner")
    UICorner2.CornerRadius = UDim.new(0, 10)
    UICorner2.Parent = Favorite

    -- Apply theme once
    applyPinkThemeToWheel()
    lightenEmoteIcons()

    connectEvents()
    isGUICreated = true
    
    return true
end

local function checkAndRecreateGUI()
    local exists, emotesWheel = checkEmotesMenuExists()
    if not exists then
        isGUICreated = false
        return
    end

    if not emotesWheel:FindFirstChild("Under") or not emotesWheel:FindFirstChild("Top") or
        not emotesWheel:FindFirstChild("Favorite") then
        isGUICreated = false
        if createGUIElements() then
            updatePageDisplay()
            updateEmotes()
        end
    end
end

-- Character handling
if player.Character then onCharacterAdded(player.Character) end

player.CharacterAdded:Connect(function(char)
    onCharacterAdded(char)
    character = char
    humanoid = char:WaitForChild("Humanoid")
    favoriteEnabled = false
    
    task.wait(0.3)
    task.spawn(function()
        while not checkEmotesMenuExists() do task.wait(0.1) end
        task.wait(0.3)
        stopEmotes()
        if createGUIElements() and #emotesData > 0 then
            updatePageDisplay()
            updateEmotes()
        end
    end)
end)

-- 💗 LAG FIX: Use RenderStepped with throttle instead of Heartbeat
local frameCount = 0
RunService.RenderStepped:Connect(function()
    frameCount = frameCount + 1
    
    -- Only check every 30 frames (~0.5 seconds at 60fps)
    if frameCount >= 30 then
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
    while not checkEmotesMenuExists() do task.wait(0.1) end
    if createGUIElements() then
        loadFavorites()
        fetchAllEmotes()
    end
end)

StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Chat, true)

-- 💗 LAG FIX: Slower background loop
task.spawn(function()
    while true do
        pcall(function()
            local emotesMenu = CoreGui:FindFirstChild("RobloxGui") and CoreGui.RobloxGui:FindFirstChild("EmotesMenu")
            
            if not emotesMenu then
                StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.EmotesMenu, true)
            else
                local exists = emotesMenu:FindFirstChild("Children") and 
                               emotesMenu.Children:FindFirstChild("Main") and
                               emotesMenu.Children.Main:FindFirstChild("EmotesWheel")

                if exists then
                    local emotesWheel = emotesMenu.Children.Main.EmotesWheel
                    if not emotesWheel:FindFirstChild("Under") or not emotesWheel:FindFirstChild("Top") then
                        createGUIElements()
                        updatePageDisplay()
                        loadFavorites()
                    end
                end
            end
        end)
        task.wait(1)  -- Check every 1 second instead of 0.3
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
        btn.BackgroundColor3 = PINK_MEDIUM
        btn.BackgroundTransparency = 0.15
        btn.Text = "💗"
        btn.TextSize = 28
        btn.TextColor3 = WHITE
        btn.Parent = openButton
        
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 12)
        
        btn.MouseButton1Click:Connect(function()
            pcall(function() game:GetService("GuiService"):SetEmotesMenuOpen(true) end)
        end)
    end)
    
    Notify({Title = '💗 Mobile', Content = 'Tap the heart to open emotes!', Duration = 10})
end

if UserInputService.KeyboardEnabled then
    Notify({Title = '💗 PinkWards Emotes', Content = 'Press "." to open | 💗 for favorites!', Duration = 10})
end

print("=========================================")
print("   💗 PinkWards Pink Emote System!")
print("   Light & Smooth Edition")
print("   Press '.' to open")
print("=========================================")
