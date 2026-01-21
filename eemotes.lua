local WindUI

do
    local ok, result = pcall(function()
        return require("./src/Init")
    end)
    
    if ok then
        WindUI = result
    else 
        WindUI = loadstring(game:HttpGet("https://github.com/Footagesus/WindUI/releases/latest/download/main.lua"))()
    end
end

WindUI.TransparencyValue = 0.2
WindUI:SetTheme("Dark")

local Window = WindUI:CreateWindow({
    Title = "Visual Emote Changer",
    Author = "By Pnsdg (Evade Overhaul)",
    Folder = "DaraHub",
    Size = UDim2.fromOffset(580, 490),
    Theme = "Dark",
    HidePanelBackground = false,
    Acrylic = false,
    HideSearchBar = false,
    SideBarWidth = 200
})

Window:SetToggleKey(Enum.KeyCode.L)
Window:SetIconSize(48)

Window:CreateTopbarButton("theme-switcher", "moon", function()
    WindUI:SetTheme(WindUI:GetCurrentTheme() == "Dark" and "Light" or "Dark")
end, 990)

local FeatureSection = Window:Section({ Title = "Features", Opened = true })
local Tabs = {
    EmoteChanger = FeatureSection:Tab({ Title = "EmoteChanger", Icon = "smile" }),
    EmoteList = FeatureSection:Tab({ Title = "Emote List", Icon = "list" }),
    Visuals = FeatureSection:Tab({ Title = "Visuals", Icon = "eye" }),
    CosmeticList = FeatureSection:Tab({ Title = "Cosmetic List", Icon = "shirt" }),
    Settings = FeatureSection:Tab({ Title = "Settings", Icon = "settings" })
}

local player = game:GetService("Players").LocalPlayer
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local Events = ReplicatedStorage:WaitForChild("Events", 10)
local CharacterFolder = Events and Events:WaitForChild("Character", 10)
local EmoteRemote = CharacterFolder and CharacterFolder:WaitForChild("Emote", 10)
local PassCharacterInfo = CharacterFolder and CharacterFolder:WaitForChild("PassCharacterInfo", 10)

local remoteSignal = PassCharacterInfo and PassCharacterInfo.OnClientEvent
local currentTag = nil
local currentEmotes = {"", "", "", "", "", ""}
local selectEmotes = {"", "", "", "", "", ""}
local emoteEnabled = {false, false, false, false, false, false}
local emoteOption = 1
local pendingSlot = nil

local randomOptionEnabled = true

local currentEmoteInputs = {}
local selectEmoteInputs = {}
local allEmotes = {}
local emoteConnections = {}

local SAVE_FOLDER = "DaraHub"
local CONFIGS_FILE = SAVE_FOLDER .. "/EmoteConfigs.json"

-- ═══════════════════════════════════════════════════════════════
-- COSMETICS CHANGER VARIABLES
-- ═══════════════════════════════════════════════════════════════

local cosmetic1, cosmetic2 = "", ""
local originalCosmetic1, originalCosmetic2 = "", ""
local isSwapped = false
local allCosmetics = {}
local cosmeticRarities = {}
local cosmeticPrices = {}

-- Rarity based on price ranges
local RARITY_INFO = {
    ["Free"] = { Order = 1, Color = "⚪", MinPrice = 0, MaxPrice = 0 },
    ["Common"] = { Order = 2, Color = "⚪", MinPrice = 1, MaxPrice = 500 },
    ["Uncommon"] = { Order = 3, Color = "🟢", MinPrice = 501, MaxPrice = 1500 },
    ["Rare"] = { Order = 4, Color = "🔵", MinPrice = 1501, MaxPrice = 5000 },
    ["Epic"] = { Order = 5, Color = "🟣", MinPrice = 5001, MaxPrice = 15000 },
    ["Legendary"] = { Order = 6, Color = "🟡", MinPrice = 15001, MaxPrice = 50000 },
    ["Mythic"] = { Order = 7, Color = "🔴", MinPrice = 50001, MaxPrice = 150000 },
    ["Divine"] = { Order = 8, Color = "💎", MinPrice = 150001, MaxPrice = 999999999 },
    ["Admin"] = { Order = 9, Color = "⭐" },
    ["Unknown"] = { Order = 99, Color = "❓" }
}

-- ═══════════════════════════════════════════════════════════════
-- COSMETICS SCANNER WITH PRICE-BASED RARITY
-- ═══════════════════════════════════════════════════════════════

local function GetCosmeticPrice(cosmeticInstance)
    local price = nil
    
    -- Method 1: Check for Price/Cost attribute
    price = cosmeticInstance:GetAttribute("Price")
    if price then return tonumber(price) end
    
    price = cosmeticInstance:GetAttribute("Cost")
    if price then return tonumber(price) end
    
    -- Method 2: Check for Price/Cost value object
    local priceValue = cosmeticInstance:FindFirstChild("Price")
    if priceValue and priceValue:IsA("ValueBase") then
        return tonumber(priceValue.Value)
    end
    
    local costValue = cosmeticInstance:FindFirstChild("Cost")
    if costValue and costValue:IsA("ValueBase") then
        return tonumber(costValue.Value)
    end
    
    -- Method 3: Try to require ModuleScript and read price
    if cosmeticInstance:IsA("ModuleScript") then
        local success, data = pcall(function()
            return require(cosmeticInstance)
        end)
        if success and type(data) == "table" then
            -- Check various common price field names
            if data.Price then return tonumber(data.Price) end
            if data.price then return tonumber(data.price) end
            if data.Cost then return tonumber(data.Cost) end
            if data.cost then return tonumber(data.cost) end
            if data.Coins then return tonumber(data.Coins) end
            if data.coins then return tonumber(data.coins) end
            if data.Money then return tonumber(data.Money) end
            if data.money then return tonumber(data.money) end
            if data.Value then return tonumber(data.Value) end
            if data.value then return tonumber(data.value) end
        end
    end
    
    -- Method 4: Check children for ModuleScript with price data
    for _, child in pairs(cosmeticInstance:GetChildren()) do
        if child:IsA("ModuleScript") then
            local success, data = pcall(function()
                return require(child)
            end)
            if success and type(data) == "table" then
                if data.Price then return tonumber(data.Price) end
                if data.price then return tonumber(data.price) end
                if data.Cost then return tonumber(data.Cost) end
                if data.cost then return tonumber(data.cost) end
            end
        end
    end
    
    return nil
end

local function GetRarityFromPrice(price)
    if price == nil then
        return "Unknown"
    end
    
    price = tonumber(price) or 0
    
    if price == 0 then
        return "Free"
    elseif price <= 500 then
        return "Common"
    elseif price <= 1500 then
        return "Uncommon"
    elseif price <= 5000 then
        return "Rare"
    elseif price <= 15000 then
        return "Epic"
    elseif price <= 50000 then
        return "Legendary"
    elseif price <= 150000 then
        return "Mythic"
    else
        return "Divine"
    end
end

local function CheckIfAdmin(cosmeticInstance)
    -- Check if it's an admin/special cosmetic
    local name = cosmeticInstance.Name:lower()
    local adminKeywords = {"admin", "dev", "developer", "mod", "moderator", "staff", "owner", "vip", "exclusive"}
    
    for _, keyword in ipairs(adminKeywords) do
        if name:find(keyword) then
            return true
        end
    end
    
    -- Check for admin attribute
    local isAdmin = cosmeticInstance:GetAttribute("Admin")
    if isAdmin then return true end
    
    local isSpecial = cosmeticInstance:GetAttribute("Special")
    if isSpecial then return true end
    
    -- Check in module data
    if cosmeticInstance:IsA("ModuleScript") then
        local success, data = pcall(function()
            return require(cosmeticInstance)
        end)
        if success and type(data) == "table" then
            if data.Admin or data.admin then return true end
            if data.Special or data.special then return true end
            if data.Developer or data.developer then return true end
            if data.Gamepass or data.gamepass then return true end
            if data.Robux or data.robux then return true end
        end
    end
    
    return false
end

local function ScanCosmetics()
    allCosmetics = {}
    cosmeticRarities = {}
    cosmeticPrices = {}
    
    local Cosmetics = ReplicatedStorage:FindFirstChild("Items")
    if Cosmetics then
        Cosmetics = Cosmetics:FindFirstChild("Cosmetics")
    end
    
    if not Cosmetics then
        warn("Could not find ReplicatedStorage.Items.Cosmetics")
        return allCosmetics
    end
    
    for _, cosmetic in pairs(Cosmetics:GetChildren()) do
        local cosmeticName = cosmetic.Name
        local price = GetCosmeticPrice(cosmetic)
        local rarity
        
        -- Check if it's admin/special first
        if CheckIfAdmin(cosmetic) then
            rarity = "Admin"
        else
            rarity = GetRarityFromPrice(price)
        end
        
        table.insert(allCosmetics, cosmeticName)
        cosmeticRarities[cosmeticName] = rarity
        cosmeticPrices[cosmeticName] = price or 0
    end
    
    -- Sort by price (highest first), then alphabetically
    table.sort(allCosmetics, function(a, b)
        local priceA = cosmeticPrices[a] or 0
        local priceB = cosmeticPrices[b] or 0
        
        -- Sort by rarity order first
        local rarityA = cosmeticRarities[a] or "Unknown"
        local rarityB = cosmeticRarities[b] or "Unknown"
        local orderA = RARITY_INFO[rarityA] and RARITY_INFO[rarityA].Order or 99
        local orderB = RARITY_INFO[rarityB] and RARITY_INFO[rarityB].Order or 99
        
        if orderA == orderB then
            -- Same rarity, sort by price (highest first)
            if priceA == priceB then
                return a:lower() < b:lower()
            end
            return priceA > priceB
        end
        return orderA < orderB
    end)
    
    return allCosmetics
end

local function GetRarityDisplay(cosmeticName)
    local rarity = cosmeticRarities[cosmeticName] or "Unknown"
    local price = cosmeticPrices[cosmeticName] or 0
    local info = RARITY_INFO[rarity] or RARITY_INFO["Unknown"]
    
    local priceStr = ""
    if price > 0 then
        -- Format price with commas
        local formatted = tostring(price)
        while true do
            formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", '%1,%2')
            if k == 0 then break end
        end
        priceStr = " - 💰" .. formatted
    elseif price == 0 and rarity ~= "Unknown" then
        priceStr = " - FREE"
    end
    
    return info.Color .. " [" .. rarity .. "]" .. priceStr
end

local function FormatPrice(price)
    if not price or price == 0 then
        return "Free"
    end
    local formatted = tostring(price)
    while true do
        formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", '%1,%2')
        if k == 0 then break end
    end
    return formatted
end

-- ═══════════════════════════════════════════════════════════════
-- EMOTE SCANNER
-- ═══════════════════════════════════════════════════════════════

local function ScanEmotes()
    allEmotes = {}
    local emotesFolder = ReplicatedStorage:FindFirstChild("Items")
    if emotesFolder then
        emotesFolder = emotesFolder:FindFirstChild("Emotes")
        if emotesFolder then
            for _, emoteModule in pairs(emotesFolder:GetChildren()) do
                if emoteModule:IsA("ModuleScript") then
                    table.insert(allEmotes, emoteModule.Name)
                end
            end
        end
    end
    table.sort(allEmotes, function(a, b)
        return a:lower() < b:lower()
    end)
    return allEmotes
end

-- ═══════════════════════════════════════════════════════════════
-- COSMETICS SCANNER WITH RARITY DETECTION
-- ═══════════════════════════════════════════════════════════════

local function GetCosmeticRarity(cosmeticInstance)
    -- Method 1: Check for Rarity attribute
    local rarityAttr = cosmeticInstance:GetAttribute("Rarity")
    if rarityAttr then
        return tostring(rarityAttr)
    end
    
    -- Method 2: Check for Rarity value object
    local rarityValue = cosmeticInstance:FindFirstChild("Rarity")
    if rarityValue and rarityValue:IsA("ValueBase") then
        return tostring(rarityValue.Value)
    end
    
    -- Method 3: Check for Type attribute (some games use this)
    local typeAttr = cosmeticInstance:GetAttribute("Type")
    if typeAttr then
        return tostring(typeAttr)
    end
    
    -- Method 4: Try to require and read from ModuleScript
    if cosmeticInstance:IsA("ModuleScript") then
        local success, data = pcall(function()
            return require(cosmeticInstance)
        end)
        if success and type(data) == "table" then
            if data.Rarity then return tostring(data.Rarity) end
            if data.rarity then return tostring(data.rarity) end
            if data.Type then return tostring(data.Type) end
            if data.type then return tostring(data.type) end
            if data.Tier then return tostring(data.Tier) end
            if data.tier then return tostring(data.tier) end
        end
    end
    
    -- Method 5: Check parent folder name for rarity hints
    local parent = cosmeticInstance.Parent
    if parent then
        local parentName = parent.Name:lower()
        for rarity, _ in pairs(RARITY_INFO) do
            if parentName:find(rarity:lower()) then
                return rarity
            end
        end
    end
    
    -- Method 6: Check cosmetic name for rarity keywords
    local name = cosmeticInstance.Name:lower()
    local rarityKeywords = {
        ["admin"] = "Admin",
        ["dev"] = "Developer",
        ["developer"] = "Developer",
        ["exclusive"] = "Exclusive",
        ["limited"] = "Limited",
        ["event"] = "Event",
        ["halloween"] = "Event",
        ["christmas"] = "Event",
        ["mythic"] = "Mythic",
        ["legendary"] = "Legendary",
        ["epic"] = "Epic",
        ["rare"] = "Rare",
        ["uncommon"] = "Uncommon",
        ["common"] = "Common",
        ["free"] = "Free"
    }
    
    for keyword, rarity in pairs(rarityKeywords) do
        if name:find(keyword) then
            return rarity
        end
    end
    
    return "Unknown"
end

local function ScanCosmetics()
    allCosmetics = {}
    cosmeticRarities = {}
    
    local cosmeticsFolder = ReplicatedStorage:FindFirstChild("Items")
    if cosmeticsFolder then
        cosmeticsFolder = cosmeticsFolder:FindFirstChild("Cosmetics")
        if cosmeticsFolder then
            for _, cosmetic in pairs(cosmeticsFolder:GetChildren()) do
                local cosmeticName = cosmetic.Name
                local rarity = GetCosmeticRarity(cosmetic)
                
                table.insert(allCosmetics, cosmeticName)
                cosmeticRarities[cosmeticName] = rarity
            end
        end
    end
    
    -- Sort by rarity first, then alphabetically
    table.sort(allCosmetics, function(a, b)
        local rarityA = cosmeticRarities[a] or "Unknown"
        local rarityB = cosmeticRarities[b] or "Unknown"
        local orderA = RARITY_INFO[rarityA] and RARITY_INFO[rarityA].Order or 99
        local orderB = RARITY_INFO[rarityB] and RARITY_INFO[rarityB].Order or 99
        
        if orderA == orderB then
            return a:lower() < b:lower()
        end
        return orderA < orderB
    end)
    
    return allCosmetics
end

local function GetRarityDisplay(cosmeticName)
    local rarity = cosmeticRarities[cosmeticName] or "Unknown"
    local info = RARITY_INFO[rarity] or RARITY_INFO["Unknown"]
    return info.Color .. " [" .. rarity .. "]"
end

-- ═══════════════════════════════════════════════════════════════
-- COSMETICS CHANGER FUNCTIONS
-- ═══════════════════════════════════════════════════════════════

local function normalize(str) 
    return str:gsub("%s+", ""):lower() 
end 

local function levenshtein(s, t) 
    local m, n = #s, #t 
    local d = {} 
    for i = 0, m do d[i] = {[0] = i} end 
    for j = 0, n do d[0][j] = j end 
    
    for i = 1, m do 
        for j = 1, n do 
            local cost = (s:sub(i,i) == t:sub(j,j)) and 0 or 1 
            d[i][j] = math.min( 
                d[i-1][j] + 1, 
                d[i][j-1] + 1, 
                d[i-1][j-1] + cost 
            ) 
        end 
    end 
    return d[m][n] 
end 

local function similarity(s, t) 
    local nS, nT = normalize(s), normalize(t) 
    local dist = levenshtein(nS, nT) 
    return 1 - dist / math.max(#nS, #nT) 
end 

local function findSimilarCosmetic(name) 
    local Cosmetics = ReplicatedStorage:FindFirstChild("Items")
    if Cosmetics then
        Cosmetics = Cosmetics:FindFirstChild("Cosmetics")
    end
    if not Cosmetics then return name end
    
    local bestMatch = name 
    local bestScore = 0.5 
    for _, c in ipairs(Cosmetics:GetChildren()) do 
        local score = similarity(name, c.Name) 
        if score > bestScore then 
            bestScore = score 
            bestMatch = c.Name 
        end 
    end 
    return bestMatch 
end 

local function SwapCosmetics()
    if cosmetic1 == "" or cosmetic2 == "" or cosmetic1 == cosmetic2 then 
        return false, "Please select two different cosmetics"
    end
    
    local Cosmetics = ReplicatedStorage:FindFirstChild("Items")
    if Cosmetics then
        Cosmetics = Cosmetics:FindFirstChild("Cosmetics")
    end
    if not Cosmetics then 
        return false, "Cosmetics folder not found"
    end
    
    local matchedCosmetic1 = findSimilarCosmetic(cosmetic1) 
    local matchedCosmetic2 = findSimilarCosmetic(cosmetic2) 
    
    local a = Cosmetics:FindFirstChild(matchedCosmetic1) 
    local b = Cosmetics:FindFirstChild(matchedCosmetic2) 
    if not a or not b then 
        return false, "Could not find one or both cosmetics"
    end 
    
    if not isSwapped then
        originalCosmetic1 = matchedCosmetic1
        originalCosmetic2 = matchedCosmetic2
    end
    
    local tempRoot = Instance.new("Folder", Cosmetics) 
    tempRoot.Name = "__temp_swap_" .. tostring(tick()):gsub("%.", "_") 
    
    local tempA = Instance.new("Folder", tempRoot) 
    local tempB = Instance.new("Folder", tempRoot) 
    
    for _, c in ipairs(a:GetChildren()) do c.Parent = tempA end 
    for _, c in ipairs(b:GetChildren()) do c.Parent = tempB end 
    
    for _, c in ipairs(tempA:GetChildren()) do c.Parent = b end 
    for _, c in ipairs(tempB:GetChildren()) do c.Parent = a end 
    
    tempRoot:Destroy()
    
    cosmetic1 = matchedCosmetic1
    cosmetic2 = matchedCosmetic2
    isSwapped = true
    
    return true, "Successfully swapped " .. matchedCosmetic1 .. " with " .. matchedCosmetic2
end

local function ResetCosmetics()
    if not isSwapped then
        return false, "No cosmetics have been swapped yet"
    end
    
    if originalCosmetic1 == "" or originalCosmetic2 == "" then
        return false, "Original cosmetic names not found"
    end
    
    local Cosmetics = ReplicatedStorage:FindFirstChild("Items")
    if Cosmetics then
        Cosmetics = Cosmetics:FindFirstChild("Cosmetics")
    end
    if not Cosmetics then 
        return false, "Cosmetics folder not found"
    end
    
    local a = Cosmetics:FindFirstChild(cosmetic1) 
    local b = Cosmetics:FindFirstChild(cosmetic2) 
    
    if a and b then
        local tempRoot = Instance.new("Folder", Cosmetics) 
        tempRoot.Name = "__temp_reset_" .. tostring(tick()):gsub("%.", "_") 
        
        local tempA = Instance.new("Folder", tempRoot) 
        local tempB = Instance.new("Folder", tempRoot) 
        
        for _, c in ipairs(a:GetChildren()) do c.Parent = tempA end 
        for _, c in ipairs(b:GetChildren()) do c.Parent = tempB end 
        
        for _, c in ipairs(tempA:GetChildren()) do c.Parent = b end 
        for _, c in ipairs(tempB:GetChildren()) do c.Parent = a end 
        
        tempRoot:Destroy()
        
        isSwapped = false
        
        return true, "Successfully reset cosmetics to original state"
    else
        return false, "Could not find swapped cosmetics to reset"
    end
end

-- ═══════════════════════════════════════════════════════════════
-- EMOTE OPTION FUNCTIONS
-- ═══════════════════════════════════════════════════════════════

local function SetEmoteOption(num)
    if num < 1 then num = 1 end
    if num > 3 then num = 3 end
    emoteOption = num
    
    if player.Character then
        player.Character:SetAttribute("EmoteNum", num)
    end
end

local function SetRandomOption()
    local randomNum = math.random(1, 3)
    if player.Character then
        player.Character:SetAttribute("EmoteNum", randomNum)
    end
    return randomNum
end

local function SetupEmoteConnections()
    for _, conn in pairs(emoteConnections) do
        pcall(function() conn:Disconnect() end)
    end
    emoteConnections = {}
    
    if player.Character then
        player.Character:SetAttribute("EmoteNum", emoteOption)
    end
    
    emoteConnections.char = player.CharacterAdded:Connect(function(char)
        task.wait(0.5)
        char:SetAttribute("EmoteNum", emoteOption)
    end)
    
    emoteConnections.game = workspace.ChildAdded:Connect(function(child)
        if child.Name == "Game" then
            task.wait(1)
            if player.Character then
                player.Character:SetAttribute("EmoteNum", emoteOption)
            end
        end
    end)
end

-- ═══════════════════════════════════════════════════════════════
-- EMOTE CHANGER LOGIC
-- ═══════════════════════════════════════════════════════════════

local function ReadTagFromFolder(f)
    if not f then return nil end
    local a = f:GetAttribute("Tag")
    if a ~= nil then return a end
    local o = f:FindFirstChild("Tag")
    if o and o:IsA("ValueBase") then return o.Value end
    return nil
end

local function OnRespawn()
    currentTag = nil
    pendingSlot = nil
    
    task.spawn(function()
        for _ = 1, 20 do
            local gameFolder = workspace:FindFirstChild("Game")
            if gameFolder then
                local playersFolder = gameFolder:FindFirstChild("Players")
                if playersFolder then
                    local pf = playersFolder:FindFirstChild(player.Name)
                    if pf then
                        local tag = ReadTagFromFolder(pf)
                        if tag then
                            local num = tonumber(tag)
                            if num and num >= 0 and num <= 255 then
                                currentTag = tag
                                break
                            end
                        end
                    end
                end
            end
            task.wait(0.5)
        end
    end)
end

local function FireSelect(slot)
    if not currentTag then return end
    if not remoteSignal then return end
    
    local b = tonumber(currentTag)
    if not b or b < 0 or b > 255 then return end
    if not selectEmotes[slot] or selectEmotes[slot] == "" then return end
    
    if randomOptionEnabled then
        SetRandomOption()
    end
    
    local buf = buffer.create(2)
    buffer.writeu8(buf, 0, b)
    buffer.writeu8(buf, 1, 17)
    
    firesignal(remoteSignal, buf, {selectEmotes[slot]})
end

local function IsValidEmote(name)
    if name == "" then return false end
    local lower = name:lower():gsub("%s+", "")
    local folder = ReplicatedStorage:FindFirstChild("Items")
    if folder then
        folder = folder:FindFirstChild("Emotes")
        if folder then
            for _, m in pairs(folder:GetChildren()) do
                if m:IsA("ModuleScript") and m.Name:lower():gsub("%s+", "") == lower then
                    return true
                end
            end
        end
    end
    return false
end

local function ApplyEmotes()
    local count = 0
    for i = 1, 6 do
        if currentEmotes[i] ~= "" and selectEmotes[i] ~= "" then
            local cv = IsValidEmote(currentEmotes[i])
            local sv = IsValidEmote(selectEmotes[i])
            emoteEnabled[i] = cv and sv and currentEmotes[i]:lower() ~= selectEmotes[i]:lower()
            if emoteEnabled[i] then count = count + 1 end
        else
            emoteEnabled[i] = false
        end
    end
    return count
end

-- Setup remotes
if PassCharacterInfo and EmoteRemote then
    PassCharacterInfo.OnClientEvent:Connect(function()
        if pendingSlot then
            local slot = pendingSlot
            pendingSlot = nil
            task.wait(0.1)
            FireSelect(slot)
        end
    end)
    
    local oldNamecall
    oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
        local method = getnamecallmethod()
        local args = {...}
        
        if method == "FireServer" and self == EmoteRemote and type(args[1]) == "string" then
            for i = 1, 6 do
                if emoteEnabled[i] and currentEmotes[i] ~= "" and args[1] == currentEmotes[i] then
                    pendingSlot = i
                    task.spawn(function()
                        task.wait(0.15)
                        if pendingSlot == i then
                            pendingSlot = nil
                            FireSelect(i)
                        end
                    end)
                    return nil
                end
            end
        end
        
        return oldNamecall(self, ...)
    end)
    
    if player.Character then
        task.spawn(OnRespawn)
    end
    
    player.CharacterAdded:Connect(function()
        task.wait(1)
        OnRespawn()
    end)
    
    local gameFolder = workspace:FindFirstChild("Game")
    if gameFolder then
        local playersFolder = gameFolder:FindFirstChild("Players")
        if playersFolder then
            playersFolder.ChildAdded:Connect(function(child)
                if child.Name == player.Name then
                    task.wait(0.5)
                    OnRespawn()
                end
            end)
        end
    end
end

-- ═══════════════════════════════════════════════════════════════
-- EMOTE CHANGER TAB
-- ═══════════════════════════════════════════════════════════════

Tabs.EmoteChanger:Section({ Title = "Emote Changer", TextSize = 20 })
Tabs.EmoteChanger:Paragraph({
    Title = "How to use",
    Desc = "Current = emote you own | Select = animation to play"
})
Tabs.EmoteChanger:Divider()

Tabs.EmoteChanger:Section({ Title = "Animation Options", TextSize = 16 })

local shuffleToggle = Tabs.EmoteChanger:Toggle({
    Title = "Shuffle Animation (Like Zombie Stride)",
    Desc = "Randomly picks Option 1, 2, or 3 each time you emote",
    Value = randomOptionEnabled,
    Callback = function(v)
        randomOptionEnabled = v
    end
})

local manualDropdown = Tabs.EmoteChanger:Dropdown({
    Title = "Manual Animation Option",
    Desc = "Only works when Shuffle is OFF",
    Multi = false,
    AllowNone = false,
    Value = tostring(emoteOption),
    Values = {"1", "2", "3"},
    Callback = function(v)
        SetEmoteOption(tonumber(v) or 1)
    end
})

Tabs.EmoteChanger:Divider()
Tabs.EmoteChanger:Section({ Title = "Emote Slots", TextSize = 16 })

for i = 1, 6 do
    Tabs.EmoteChanger:Paragraph({
        Title = "Slot " .. i,
        Desc = ""
    })
    
    currentEmoteInputs[i] = Tabs.EmoteChanger:Input({
        Title = "Current Emote " .. i,
        Placeholder = "Emote you own",
        Value = currentEmotes[i],
        Callback = function(v)
            currentEmotes[i] = v:gsub("%s+", "")
        end
    })
    
    selectEmoteInputs[i] = Tabs.EmoteChanger:Input({
        Title = "Select Emote " .. i,
        Placeholder = "Animation to play",
        Value = selectEmotes[i],
        Callback = function(v)
            selectEmotes[i] = v:gsub("%s+", "")
        end
    })
end

Tabs.EmoteChanger:Divider()

Tabs.EmoteChanger:Button({
    Title = "Apply Emote Mappings",
    Icon = "check",
    Callback = function()
        local count = ApplyEmotes()
        WindUI:Notify({
            Title = "Emote Changer",
            Content = "Applied " .. count .. " emote(s)!",
            Duration = 2
        })
    end
})

Tabs.EmoteChanger:Button({
    Title = "Reset All",
    Icon = "trash-2",
    Callback = function()
        for i = 1, 6 do
            currentEmotes[i] = ""
            selectEmotes[i] = ""
            emoteEnabled[i] = false
            pcall(function()
                if currentEmoteInputs[i] then currentEmoteInputs[i]:Set("") end
                if selectEmoteInputs[i] then selectEmoteInputs[i]:Set("") end
            end)
        end
        WindUI:Notify({ Title = "Reset", Content = "Cleared!", Duration = 1 })
    end
})

-- ═══════════════════════════════════════════════════════════════
-- EMOTE LIST TAB
-- ═══════════════════════════════════════════════════════════════

Tabs.EmoteList:Section({ Title = "Emote List", TextSize = 20 })
Tabs.EmoteList:Paragraph({
    Title = "All Available Emotes",
    Desc = "Click any emote to copy its name"
})
Tabs.EmoteList:Divider()

Tabs.EmoteList:Button({
    Title = "Refresh Emote List",
    Icon = "refresh-cw",
    Callback = function()
        ScanEmotes()
        WindUI:Notify({
            Title = "Emotes",
            Content = "Found " .. #allEmotes .. " emotes!",
            Duration = 2
        })
    end
})

Tabs.EmoteList:Divider()

task.spawn(function()
    task.wait(1)
    ScanEmotes()
    
    Tabs.EmoteList:Paragraph({
        Title = "Found " .. #allEmotes .. " emotes",
        Desc = "Click to copy"
    })
    
    Tabs.EmoteList:Divider()
    
    for i, emoteName in ipairs(allEmotes) do
        Tabs.EmoteList:Button({
            Title = emoteName,
            Icon = "copy",
            Callback = function()
                if setclipboard then
                    setclipboard(emoteName)
                    WindUI:Notify({
                        Title = "Copied!",
                        Content = emoteName,
                        Duration = 1
                    })
                end
            end
        })
        
        if i % 25 == 0 then
            task.wait()
        end
    end
end)

-- ═══════════════════════════════════════════════════════════════
-- VISUALS TAB - COSMETICS CHANGER
-- ═══════════════════════════════════════════════════════════════

Tabs.Visuals:Section({ Title = "Cosmetics Changer", TextSize = 20 })
Tabs.Visuals:Paragraph({
    Title = "How to use",
    Desc = "Swap cosmetic appearances (visual only, client-side)"
})
Tabs.Visuals:Divider()

-- Cosmetic dropdowns
local cosmeticNames = {}
task.spawn(function()
    task.wait(0.5)
    ScanCosmetics()
    cosmeticNames = allCosmetics
end)

local cosmetic1Dropdown = nil
local cosmetic2Dropdown = nil

Tabs.Visuals:Section({ Title = "Select Cosmetics", TextSize = 16 })

Tabs.Visuals:Input({
    Title = "Current Cosmetic (Your Owned)",
    Placeholder = "Enter cosmetic name or use list below",
    Callback = function(v) 
        cosmetic1 = v
        if not isSwapped then
            originalCosmetic1 = v
        end
    end
})

Tabs.Visuals:Input({
    Title = "Target Cosmetic (Want to look like)",
    Placeholder = "Enter cosmetic name or use list below",
    Callback = function(v) 
        cosmetic2 = v
        if not isSwapped then
            originalCosmetic2 = v
        end
    end
})

Tabs.Visuals:Divider()

Tabs.Visuals:Button({
    Title = "Apply Cosmetics Swap",
    Icon = "check",
    Callback = function()
        local success, msg = SwapCosmetics()
        WindUI:Notify({
            Title = "Cosmetics Changer",
            Content = msg,
            Duration = 3
        })
    end
})

Tabs.Visuals:Button({
    Title = "Reset Cosmetics",
    Desc = "Restore cosmetics to their original state",
    Icon = "rotate-ccw",
    Callback = function()
        local success, msg = ResetCosmetics()
        WindUI:Notify({
            Title = "Cosmetics Changer",
            Content = msg,
            Duration = 3
        })
    end
})

Tabs.Visuals:Divider()

Tabs.Visuals:Paragraph({
    Title = "Status",
    Desc = "Use the Cosmetic List tab to browse and select cosmetics with rarity tags"
})

-- ═══════════════════════════════════════════════════════════════
-- COSMETIC LIST TAB
-- ═══════════════════════════════════════════════════════════════

Tabs.CosmeticList:Section({ Title = "Cosmetic List", TextSize = 20 })
Tabs.CosmeticList:Paragraph({
    Title = "All Available Cosmetics",
    Desc = "Click any cosmetic to copy its name. Sorted by rarity/price."
})
Tabs.CosmeticList:Divider()

-- Rarity Legend
Tabs.CosmeticList:Section({ Title = "Rarity Legend (By Price)", TextSize = 14 })
Tabs.CosmeticList:Paragraph({
    Title = "Price Ranges",
    Desc = "⚪ Free: 0 | ⚪ Common: 1-500 | 🟢 Uncommon: 501-1,500\n🔵 Rare: 1,501-5,000 | 🟣 Epic: 5,001-15,000\n🟡 Legendary: 15,001-50,000 | 🔴 Mythic: 50,001-150,000\n💎 Divine: 150,001+ | ⭐ Admin/Special"
})
Tabs.CosmeticList:Divider()

-- Filter by rarity
local selectedRarityFilter = "All"
local rarityFilterDropdown = Tabs.CosmeticList:Dropdown({
    Title = "Filter by Rarity",
    Multi = false,
    AllowNone = false,
    Value = "All",
    Values = {"All", "Free", "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Divine", "Admin", "Unknown"},
    Callback = function(v)
        selectedRarityFilter = v
        WindUI:Notify({
            Title = "Filter",
            Content = "Filter set to: " .. v,
            Duration = 2
        })
    end
})

-- Sort options
local sortByPrice = true
Tabs.CosmeticList:Toggle({
    Title = "Sort by Price (Highest First)",
    Desc = "When OFF, sorts alphabetically within each rarity",
    Value = true,
    Callback = function(v)
        sortByPrice = v
    end
})

Tabs.CosmeticList:Divider()

local cosmeticCountParagraph = Tabs.CosmeticList:Paragraph({
    Title = "Cosmetics",
    Desc = "Press 'Scan Cosmetics' to load..."
})

Tabs.CosmeticList:Button({
    Title = "Scan Cosmetics",
    Icon = "search",
    Callback = function()
        WindUI:Notify({
            Title = "Scanning...",
            Content = "Please wait...",
            Duration = 1
        })
        
        task.spawn(function()
            ScanCosmetics()
            
            -- Count by rarity
            local rarityCount = {}
            local totalValue = 0
            for _, cosmeticName in ipairs(allCosmetics) do
                local rarity = cosmeticRarities[cosmeticName] or "Unknown"
                rarityCount[rarity] = (rarityCount[rarity] or 0) + 1
                totalValue = totalValue + (cosmeticPrices[cosmeticName] or 0)
            end
            
            local summary = "Found " .. #allCosmetics .. " cosmetics!\nTotal Value: 💰" .. FormatPrice(totalValue) .. "\n\n"
            
            local rarityOrder = {"Free", "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Divine", "Admin", "Unknown"}
            for _, rarity in ipairs(rarityOrder) do
                local count = rarityCount[rarity]
                if count then
                    local info = RARITY_INFO[rarity] or RARITY_INFO["Unknown"]
                    summary = summary .. info.Color .. " " .. rarity .. ": " .. count .. "\n"
                end
            end
            
            pcall(function()
                cosmeticCountParagraph:SetDesc(summary)
            end)
            
            WindUI:Notify({
                Title = "Cosmetics Scanned!",
                Content = "Found " .. #allCosmetics .. " cosmetics",
                Duration = 3
            })
        end)
    end
})

Tabs.CosmeticList:Button({
    Title = "Copy All Cosmetic Names",
    Icon = "clipboard",
    Callback = function()
        if #allCosmetics == 0 then
            WindUI:Notify({
                Title = "Error",
                Content = "Scan cosmetics first!",
                Duration = 2
            })
            return
        end
        
        local text = "=== COSMETICS LIST ===\n\n"
        
        local rarityOrder = {"Divine", "Mythic", "Legendary", "Epic", "Rare", "Uncommon", "Common", "Free", "Admin", "Unknown"}
        for _, rarity in ipairs(rarityOrder) do
            local cosmeticsInRarity = {}
            for _, name in ipairs(allCosmetics) do
                if cosmeticRarities[name] == rarity then
                    table.insert(cosmeticsInRarity, name)
                end
            end
            
            if #cosmeticsInRarity > 0 then
                local info = RARITY_INFO[rarity] or RARITY_INFO["Unknown"]
                text = text .. "\n" .. info.Color .. " " .. rarity:upper() .. " (" .. #cosmeticsInRarity .. "):\n"
                for _, name in ipairs(cosmeticsInRarity) do
                    local price = cosmeticPrices[name] or 0
                    text = text .. "  • " .. name .. " - " .. FormatPrice(price) .. "\n"
                end
            end
        end
        
        if setclipboard then
            setclipboard(text)
            WindUI:Notify({
                Title = "Copied!",
                Content = "All cosmetic names copied to clipboard!",
                Duration = 2
            })
        end
    end
})

Tabs.CosmeticList:Divider()

-- Search
local searchQuery = ""
Tabs.CosmeticList:Input({
    Title = "Search Cosmetics",
    Placeholder = "Type to search...",
    Callback = function(v)
        searchQuery = v:lower()
    end
})

Tabs.CosmeticList:Button({
    Title = "Show Filtered Results",
    Icon = "filter",
    Callback = function()
        if #allCosmetics == 0 then
            WindUI:Notify({
                Title = "Error",
                Content = "Scan cosmetics first!",
                Duration = 2
            })
            return
        end
        
        local filtered = {}
        for _, name in ipairs(allCosmetics) do
            local rarity = cosmeticRarities[name] or "Unknown"
            local matchesRarity = (selectedRarityFilter == "All") or (rarity == selectedRarityFilter)
            local matchesSearch = (searchQuery == "") or (name:lower():find(searchQuery, 1, true))
            
            if matchesRarity and matchesSearch then
                table.insert(filtered, name)
            end
        end
        
        if #filtered == 0 then
            WindUI:Notify({
                Title = "No Results",
                Content = "No cosmetics match your filter",
                Duration = 2
            })
            return
        end
        
        local resultText = "Found " .. #filtered .. " matching cosmetics:\n\n"
        for i, name in ipairs(filtered) do
            if i <= 20 then
                resultText = resultText .. GetRarityDisplay(name) .. " " .. name .. "\n"
            end
        end
        if #filtered > 20 then
            resultText = resultText .. "\n... and " .. (#filtered - 20) .. " more"
        end
        
        WindUI:Notify({
            Title = "Search Results",
            Content = resultText,
            Duration = 8
        })
    end
})

Tabs.CosmeticList:Divider()
Tabs.CosmeticList:Section({ Title = "Cosmetic Browser", TextSize = 16 })

-- This will be populated when scanning
local cosmeticButtonsCreated = false

Tabs.CosmeticList:Button({
    Title = "Load Cosmetic List (May Lag)",
    Desc = "Creates clickable buttons for each cosmetic",
    Icon = "list",
    Callback = function()
        if #allCosmetics == 0 then
            WindUI:Notify({
                Title = "Error",
                Content = "Scan cosmetics first!",
                Duration = 2
            })
            return
        end
        
        if cosmeticButtonsCreated then
            WindUI:Notify({
                Title = "Already Loaded",
                Content = "Cosmetic list already created!",
                Duration = 2
            })
            return
        end
        
        WindUI:Notify({
            Title = "Loading...",
            Content = "Creating " .. #allCosmetics .. " buttons...",
            Duration = 2
        })
        
        task.spawn(function()
            local rarityOrder = {"Divine", "Mythic", "Legendary", "Epic", "Rare", "Uncommon", "Common", "Free", "Admin", "Unknown"}
            
            for _, rarity in ipairs(rarityOrder) do
                local cosmeticsInRarity = {}
                for _, name in ipairs(allCosmetics) do
                    if cosmeticRarities[name] == rarity then
                        table.insert(cosmeticsInRarity, name)
                    end
                end
                
                if #cosmeticsInRarity > 0 then
                    local info = RARITY_INFO[rarity] or RARITY_INFO["Unknown"]
                    
                    Tabs.CosmeticList:Section({ 
                        Title = info.Color .. " " .. rarity .. " (" .. #cosmeticsInRarity .. ")", 
                        TextSize = 14 
                    })
                    
                    -- Sort by price within rarity
                    table.sort(cosmeticsInRarity, function(a, b)
                        local priceA = cosmeticPrices[a] or 0
                        local priceB = cosmeticPrices[b] or 0
                        if priceA == priceB then
                            return a:lower() < b:lower()
                        end
                        return priceA > priceB
                    end)
                    
                    for i, cosmeticName in ipairs(cosmeticsInRarity) do
                        local price = cosmeticPrices[cosmeticName] or 0
                        local priceText = price > 0 and ("💰 " .. FormatPrice(price)) or "FREE"
                        
                        Tabs.CosmeticList:Button({
                            Title = cosmeticName,
                            Desc = info.Color .. " " .. rarity .. " | " .. priceText,
                            Icon = "copy",
                            Callback = function()
                                if setclipboard then
                                    setclipboard(cosmeticName)
                                    WindUI:Notify({
                                        Title = "Copied!",
                                        Content = cosmeticName .. "\n" .. priceText,
                                        Duration = 1.5
                                    })
                                end
                            end
                        })
                        
                        if i % 15 == 0 then
                            task.wait()
                        end
                    end
                    
                    task.wait()
                end
            end
            
            cosmeticButtonsCreated = true
            
            WindUI:Notify({
                Title = "Complete!",
                Content = "All cosmetics loaded!",
                Duration = 2
            })
        end)
    end
})

-- ═══════════════════════════════════════════════════════════════
-- SETTINGS TAB - MULTI CONFIG SYSTEM
-- ═══════════════════════════════════════════════════════════════

Tabs.Settings:Section({ Title = "Config Profiles", TextSize = 20 })
Tabs.Settings:Paragraph({
    Title = "Manage Multiple Configs",
    Desc = "Create configs for different accounts (Main, Alt, etc.)"
})
Tabs.Settings:Divider()

-- Current config display
local currentConfigDisplay = Tabs.Settings:Paragraph({
    Title = "Current Config",
    Desc = "None selected"
})

local function UpdateConfigDisplay()
    pcall(function()
        currentConfigDisplay:SetDesc(currentConfigName ~= "" and currentConfigName or "None selected")
    end)
end

-- Config selector dropdown
Tabs.Settings:Section({ Title = "Select Config", TextSize = 16 })

local function RefreshConfigDropdown()
    local names = GetConfigNames()
    if #names == 0 then
        names = {"No configs yet"}
    end
    if configDropdown then
        pcall(function()
            configDropdown:Refresh(names, true)
            if currentConfigName ~= "" and allConfigs[currentConfigName] then
                configDropdown:Set(currentConfigName)
            end
        end)
    end
end

configDropdown = Tabs.Settings:Dropdown({
    Title = "Choose Config",
    Desc = "Select a config to load",
    Multi = false,
    AllowNone = true,
    Value = "",
    Values = {"No configs yet"},
    Callback = function(selected)
        if selected and selected ~= "No configs yet" and allConfigs[selected] then
            local success, msg = LoadFromConfig(selected)
            if success then
                -- Update UI with loaded values
                for i = 1, 6 do
                    pcall(function()
                        if currentEmoteInputs[i] then currentEmoteInputs[i]:Set(currentEmotes[i]) end
                        if selectEmoteInputs[i] then selectEmoteInputs[i]:Set(selectEmotes[i]) end
                    end)
                end
                SetEmoteOption(emoteOption)
                pcall(function()
                    shuffleToggle:Set(randomOptionEnabled)
                    manualDropdown:Set(tostring(emoteOption))
                end)
                ApplyEmotes()
                UpdateConfigDisplay()
                WindUI:Notify({ Title = "Config", Content = msg, Duration = 2 })
            end
        end
    end
})

Tabs.Settings:Divider()

-- Create new config
Tabs.Settings:Section({ Title = "Create New Config", TextSize = 16 })

local newConfigName = ""
Tabs.Settings:Input({
    Title = "New Config Name",
    Placeholder = "Enter name (e.g., Main, Alt1, Alt2)",
    Value = "",
    Callback = function(v)
        newConfigName = v
    end
})

Tabs.Settings:Button({
    Title = "Create New Config",
    Icon = "plus",
    Callback = function()
        if newConfigName == "" then
            WindUI:Notify({ Title = "Error", Content = "Enter a config name!", Duration = 2 })
            return
        end
        local success, msg = CreateConfig(newConfigName)
        if success then
            RefreshConfigDropdown()
            UpdateConfigDisplay()
            WindUI:Notify({ Title = "Config", Content = msg, Duration = 2 })
        else
            WindUI:Notify({ Title = "Error", Content = msg, Duration = 2 })
        end
    end
})

Tabs.Settings:Divider()

-- Save/Load/Delete current config
Tabs.Settings:Section({ Title = "Current Config Actions", TextSize = 16 })

Tabs.Settings:Button({
    Title = "Save to Current Config",
    Icon = "save",
    Callback = function()
        if currentConfigName == "" then
            WindUI:Notify({ Title = "Error", Content = "Select or create a config first!", Duration = 2 })
            return
        end
        local success, msg = SaveToConfig(currentConfigName)
        WindUI:Notify({ Title = "Config", Content = success and msg or "Failed to save!", Duration = 2 })
    end
})

Tabs.Settings:Button({
    Title = "Reload Current Config",
    Icon = "refresh-cw",
    Callback = function()
        if currentConfigName == "" then
            WindUI:Notify({ Title = "Error", Content = "No config selected!", Duration = 2 })
            return
        end
        local success, msg = LoadFromConfig(currentConfigName)
        if success then
            for i = 1, 6 do
                pcall(function()
                    if currentEmoteInputs[i] then currentEmoteInputs[i]:Set(currentEmotes[i]) end
                    if selectEmoteInputs[i] then selectEmoteInputs[i]:Set(selectEmotes[i]) end
                end)
            end
            SetEmoteOption(emoteOption)
            pcall(function()
                shuffleToggle:Set(randomOptionEnabled)
                manualDropdown:Set(tostring(emoteOption))
            end)
            ApplyEmotes()
            WindUI:Notify({ Title = "Config", Content = msg, Duration = 2 })
        end
    end
})

Tabs.Settings:Divider()

-- Rename config
Tabs.Settings:Section({ Title = "Rename Config", TextSize = 16 })

local renameInput = ""
Tabs.Settings:Input({
    Title = "New Name",
    Placeholder = "Enter new name for current config",
    Value = "",
    Callback = function(v)
        renameInput = v
    end
})

Tabs.Settings:Button({
    Title = "Rename Current Config",
    Icon = "edit",
    Callback = function()
        if currentConfigName == "" then
            WindUI:Notify({ Title = "Error", Content = "No config selected!", Duration = 2 })
            return
        end
        if renameInput == "" then
            WindUI:Notify({ Title = "Error", Content = "Enter a new name!", Duration = 2 })
            return
        end
        local success, msg = RenameConfig(currentConfigName, renameInput)
        if success then
            RefreshConfigDropdown()
            UpdateConfigDisplay()
            WindUI:Notify({ Title = "Config", Content = msg, Duration = 2 })
        else
            WindUI:Notify({ Title = "Error", Content = msg, Duration = 2 })
        end
    end
})

Tabs.Settings:Divider()

-- Duplicate config
Tabs.Settings:Section({ Title = "Duplicate Config", TextSize = 16 })

local duplicateName = ""
Tabs.Settings:Input({
    Title = "Duplicate Name",
    Placeholder = "Name for the copy",
    Value = "",
    Callback = function(v)
        duplicateName = v
    end
})

Tabs.Settings:Button({
    Title = "Duplicate Current Config",
    Icon = "copy",
    Callback = function()
        if currentConfigName == "" then
            WindUI:Notify({ Title = "Error", Content = "No config selected!", Duration = 2 })
            return
        end
        if duplicateName == "" then
            WindUI:Notify({ Title = "Error", Content = "Enter a name for the copy!", Duration = 2 })
            return
        end
        local success, msg = DuplicateConfig(currentConfigName, duplicateName)
        if success then
            RefreshConfigDropdown()
            WindUI:Notify({ Title = "Config", Content = msg, Duration = 2 })
        else
            WindUI:Notify({ Title = "Error", Content = msg, Duration = 2 })
        end
    end
})

Tabs.Settings:Divider()

-- Delete config
Tabs.Settings:Section({ Title = "Delete Config", TextSize = 16 })

Tabs.Settings:Button({
    Title = "Delete Current Config",
    Icon = "trash",
    Callback = function()
        if currentConfigName == "" then
            WindUI:Notify({ Title = "Error", Content = "No config selected!", Duration = 2 })
            return
        end
        local configToDelete = currentConfigName
        local success, msg = DeleteConfig(configToDelete)
        if success then
            RefreshConfigDropdown()
            UpdateConfigDisplay()
            WindUI:Notify({ Title = "Config", Content = msg, Duration = 2 })
        else
            WindUI:Notify({ Title = "Error", Content = msg, Duration = 2 })
        end
    end
})

Tabs.Settings:Button({
    Title = "Delete ALL Configs",
    Icon = "alert-triangle",
    Callback = function()
        allConfigs = {}
        currentConfigName = ""
        SaveAllConfigs()
        RefreshConfigDropdown()
        UpdateConfigDisplay()
        WindUI:Notify({ Title = "Config", Content = "All configs deleted!", Duration = 2 })
    end
})

Tabs.Settings:Divider()

-- Config list display
Tabs.Settings:Section({ Title = "All Saved Configs", TextSize = 16 })

local configListParagraph = Tabs.Settings:Paragraph({
    Title = "Configs",
    Desc = "Loading..."
})

local function UpdateConfigList()
    local names = GetConfigNames()
    local listText = ""
    if #names == 0 then
        listText = "No configs saved yet"
    else
        for i, name in ipairs(names) do
            if name == currentConfigName then
                listText = listText .. "► " .. name .. " (active)\n"
            else
                listText = listText .. "• " .. name .. "\n"
            end
        end
    end
    pcall(function()
        configListParagraph:SetDesc(listText)
    end)
end

Tabs.Settings:Button({
    Title = "Refresh Config List",
    Icon = "refresh-cw",
    Callback = function()
        RefreshConfigDropdown()
        UpdateConfigList()
        UpdateConfigDisplay()
        WindUI:Notify({ Title = "Refreshed", Content = "Config list updated!", Duration = 1 })
    end
})

Tabs.Settings:Divider()

Tabs.Settings:Paragraph({
    Title = "Info",
    Desc = "Press L to toggle the UI\nConfigs are saved to: " .. CONFIGS_FILE
})

-- ═══════════════════════════════════════════════════════════════
-- INITIALIZE
-- ═══════════════════════════════════════════════════════════════

SetupEmoteConnections()

task.spawn(function()
    task.wait(1)
    
    -- Load configs
    LoadAllConfigs()
    RefreshConfigDropdown()
    UpdateConfigList()
    UpdateConfigDisplay()
    
    -- Auto-load last used config
    if currentConfigName ~= "" and allConfigs[currentConfigName] then
        local success = LoadFromConfig(currentConfigName)
        if success then
            for i = 1, 6 do
                pcall(function()
                    if currentEmoteInputs[i] then currentEmoteInputs[i]:Set(currentEmotes[i]) end
                    if selectEmoteInputs[i] then selectEmoteInputs[i]:Set(selectEmotes[i]) end
                end)
            end
            SetEmoteOption(emoteOption)
            pcall(function()
                shuffleToggle:Set(randomOptionEnabled)
                manualDropdown:Set(tostring(emoteOption))
                configDropdown:Set(currentConfigName)
            end)
            task.wait(0.5)
            ApplyEmotes()
            UpdateConfigDisplay()
            WindUI:Notify({
                Title = "Emote Changer",
                Content = "Loaded config: " .. currentConfigName,
                Duration = 2
            })
        end
    else
        WindUI:Notify({
            Title = "Emote Changer",
            Content = "Create a config in Settings tab!",
            Duration = 3
        })
    end
end)

print("Visual Emote Changer Loaded!")
print("Press L to toggle UI")
