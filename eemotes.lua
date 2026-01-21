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
-- COSMETICS CHANGER VARIABLES (SIMPLIFIED)
-- ═══════════════════════════════════════════════════════════════

local cosmetic1, cosmetic2 = "", ""
local originalCosmetic1, originalCosmetic2 = "", ""
local isSwapped = false
local allCosmetics = {}

-- ═══════════════════════════════════════════════════════════════
-- MULTI-CONFIG SYSTEM (FIXED)
-- ═══════════════════════════════════════════════════════════════

local allConfigs = {}
local currentConfigName = ""
local configDropdown = nil

local function EnsureFolder()
    if not isfolder then return end
    if not isfolder(SAVE_FOLDER) then
        pcall(function()
            makefolder(SAVE_FOLDER)
        end)
    end
end

local function GetConfigNames()
    local names = {}
    for name, _ in pairs(allConfigs) do
        table.insert(names, name)
    end
    table.sort(names, function(a, b)
        return a:lower() < b:lower()
    end)
    return names
end

local function SaveAllConfigs()
    EnsureFolder()
    local data = {
        configs = allConfigs,
        lastUsed = currentConfigName
    }
    local success = pcall(function()
        if writefile then
            writefile(CONFIGS_FILE, HttpService:JSONEncode(data))
        end
    end)
    return success
end

local function LoadAllConfigs()
    if not isfile then return false end
    
    local fileExists = false
    pcall(function()
        fileExists = isfile(CONFIGS_FILE)
    end)
    
    if not fileExists then
        print("[Config] No config file found at: " .. CONFIGS_FILE)
        return false
    end
    
    local success, result = pcall(function()
        local content = readfile(CONFIGS_FILE)
        print("[Config] File content loaded, parsing...")
        return HttpService:JSONDecode(content)
    end)
    
    if success and result then
        if result.configs then
            allConfigs = result.configs
            currentConfigName = result.lastUsed or ""
            print("[Config] Loaded " .. #GetConfigNames() .. " configs!")
            print("[Config] Last used: " .. (currentConfigName ~= "" and currentConfigName or "none"))
            return true
        elseif type(result) == "table" then
            -- Old format compatibility - direct config table
            allConfigs = result
            currentConfigName = ""
            print("[Config] Loaded configs (old format)")
            return true
        end
    else
        warn("[Config] Failed to parse config file: " .. tostring(result))
    end
    
    return false
end

local function CreateConfig(name)
    if name == "" then return false, "Name cannot be empty" end
    if allConfigs[name] then return false, "Config already exists" end
    
    allConfigs[name] = {
        currentEmotes = {"", "", "", "", "", ""},
        selectEmotes = {"", "", "", "", "", ""},
        emoteOption = 1,
        randomOptionEnabled = true
    }
    currentConfigName = name
    SaveAllConfigs()
    return true, "Config created: " .. name
end

local function SaveToConfig(name)
    if name == "" then return false, "No config selected" end
    
    allConfigs[name] = {
        currentEmotes = table.clone(currentEmotes),
        selectEmotes = table.clone(selectEmotes),
        emoteOption = emoteOption,
        randomOptionEnabled = randomOptionEnabled
    }
    currentConfigName = name
    SaveAllConfigs()
    return true, "Saved to " .. name
end

local function LoadFromConfig(name)
    if not allConfigs[name] then 
        print("[Config] Config not found: " .. name)
        return false, "Config not found" 
    end
    
    local config = allConfigs[name]
    print("[Config] Loading config: " .. name)
    
    for i = 1, 6 do
        currentEmotes[i] = (config.currentEmotes and config.currentEmotes[i]) or ""
        selectEmotes[i] = (config.selectEmotes and config.selectEmotes[i]) or ""
    end
    emoteOption = config.emoteOption or 1
    if config.randomOptionEnabled ~= nil then
        randomOptionEnabled = config.randomOptionEnabled
    end
    currentConfigName = name
    SaveAllConfigs()
    return true, "Loaded " .. name
end

local function RenameConfig(oldName, newName)
    if oldName == "" then return false, "No config selected" end
    if newName == "" then return false, "New name cannot be empty" end
    if not allConfigs[oldName] then return false, "Config not found" end
    if allConfigs[newName] then return false, "Name already exists" end
    
    allConfigs[newName] = allConfigs[oldName]
    allConfigs[oldName] = nil
    if currentConfigName == oldName then
        currentConfigName = newName
    end
    SaveAllConfigs()
    return true, "Renamed to " .. newName
end

local function DeleteConfig(name)
    if name == "" then return false, "No config selected" end
    if not allConfigs[name] then return false, "Config not found" end
    
    allConfigs[name] = nil
    if currentConfigName == name then
        currentConfigName = ""
    end
    SaveAllConfigs()
    return true, "Deleted " .. name
end

local function DuplicateConfig(name, newName)
    if name == "" then return false, "No config selected" end
    if newName == "" then return false, "New name cannot be empty" end
    if not allConfigs[name] then return false, "Config not found" end
    if allConfigs[newName] then return false, "Name already exists" end
    
    local original = allConfigs[name]
    allConfigs[newName] = {
        currentEmotes = table.clone(original.currentEmotes or {"", "", "", "", "", ""}),
        selectEmotes = table.clone(original.selectEmotes or {"", "", "", "", "", ""}),
        emoteOption = original.emoteOption or 1,
        randomOptionEnabled = original.randomOptionEnabled ~= false
    }
    SaveAllConfigs()
    return true, "Duplicated as " .. newName
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
-- COSMETICS SCANNER (SIMPLIFIED - NO RARITY)
-- ═══════════════════════════════════════════════════════════════

local function ScanCosmetics()
    allCosmetics = {}
    
    local Cosmetics = ReplicatedStorage:FindFirstChild("Items")
    if Cosmetics then
        Cosmetics = Cosmetics:FindFirstChild("Cosmetics")
    end
    
    if not Cosmetics then
        warn("Could not find ReplicatedStorage.Items.Cosmetics")
        return allCosmetics
    end
    
    for _, cosmetic in pairs(Cosmetics:GetChildren()) do
        table.insert(allCosmetics, cosmetic.Name)
    end
    
    table.sort(allCosmetics, function(a, b)
        return a:lower() < b:lower()
    end)
    
    return allCosmetics
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
    
    return true, "Swapped " .. matchedCosmetic1 .. " with " .. matchedCosmetic2
end

local function ResetCosmetics()
    if not isSwapped then
        return false, "No cosmetics have been swapped"
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
        
        return true, "Reset cosmetics to original"
    else
        return false, "Could not find swapped cosmetics"
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

Tabs.Visuals:Input({
    Title = "Current Cosmetic (Your Owned)",
    Placeholder = "Enter cosmetic name",
    Callback = function(v) 
        cosmetic1 = v
        if not isSwapped then
            originalCosmetic1 = v
        end
    end
})

Tabs.Visuals:Input({
    Title = "Target Cosmetic (Want to look like)",
    Placeholder = "Enter cosmetic name",
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

-- ═══════════════════════════════════════════════════════════════
-- COSMETIC LIST TAB (SIMPLIFIED - LIKE EMOTE LIST)
-- ═══════════════════════════════════════════════════════════════

Tabs.CosmeticList:Section({ Title = "Cosmetic List", TextSize = 20 })
Tabs.CosmeticList:Paragraph({
    Title = "All Available Cosmetics",
    Desc = "Click any cosmetic to copy its name"
})
Tabs.CosmeticList:Divider()

Tabs.CosmeticList:Button({
    Title = "Refresh Cosmetic List",
    Icon = "refresh-cw",
    Callback = function()
        ScanCosmetics()
        WindUI:Notify({
            Title = "Cosmetics",
            Content = "Found " .. #allCosmetics .. " cosmetics!",
            Duration = 2
        })
    end
})

Tabs.CosmeticList:Divider()

task.spawn(function()
    task.wait(1.5)
    ScanCosmetics()
    
    Tabs.CosmeticList:Paragraph({
        Title = "Found " .. #allCosmetics .. " cosmetics",
        Desc = "Click to copy"
    })
    
    Tabs.CosmeticList:Divider()
    
    for i, cosmeticName in ipairs(allCosmetics) do
        Tabs.CosmeticList:Button({
            Title = cosmeticName,
            Icon = "copy",
            Callback = function()
                if setclipboard then
                    setclipboard(cosmeticName)
                    WindUI:Notify({
                        Title = "Copied!",
                        Content = cosmeticName,
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
-- SETTINGS TAB - CONFIG SYSTEM (FIXED)
-- ═══════════════════════════════════════════════════════════════

Tabs.Settings:Section({ Title = "Config Profiles", TextSize = 20 })
Tabs.Settings:Paragraph({
    Title = "Manage Multiple Configs",
    Desc = "Create configs for different accounts"
})
Tabs.Settings:Divider()

local currentConfigDisplay = Tabs.Settings:Paragraph({
    Title = "Current Config",
    Desc = "None selected"
})

local function UpdateConfigDisplay()
    pcall(function()
        currentConfigDisplay:SetDesc(currentConfigName ~= "" and currentConfigName or "None selected")
    end)
end

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
Tabs.Settings:Section({ Title = "Create New Config", TextSize = 16 })

local newConfigName = ""
Tabs.Settings:Input({
    Title = "New Config Name",
    Placeholder = "Enter name (e.g., Main, Alt1)",
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
        end
        WindUI:Notify({ Title = success and "Config" or "Error", Content = msg, Duration = 2 })
    end
})

Tabs.Settings:Divider()
Tabs.Settings:Section({ Title = "Config Actions", TextSize = 16 })

Tabs.Settings:Button({
    Title = "Save to Current Config",
    Icon = "save",
    Callback = function()
        if currentConfigName == "" then
            WindUI:Notify({ Title = "Error", Content = "Select or create a config first!", Duration = 2 })
            return
        end
        local success, msg = SaveToConfig(currentConfigName)
        WindUI:Notify({ Title = "Config", Content = msg, Duration = 2 })
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
        end
        WindUI:Notify({ Title = "Config", Content = msg, Duration = 2 })
    end
})

Tabs.Settings:Divider()
Tabs.Settings:Section({ Title = "Rename Config", TextSize = 16 })

local renameInput = ""
Tabs.Settings:Input({
    Title = "New Name",
    Placeholder = "Enter new name",
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
        local success, msg = RenameConfig(currentConfigName, renameInput)
        if success then
            RefreshConfigDropdown()
            UpdateConfigDisplay()
        end
        WindUI:Notify({ Title = success and "Config" or "Error", Content = msg, Duration = 2 })
    end
})

Tabs.Settings:Divider()
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
        local success, msg = DuplicateConfig(currentConfigName, duplicateName)
        if success then
            RefreshConfigDropdown()
        end
        WindUI:Notify({ Title = success and "Config" or "Error", Content = msg, Duration = 2 })
    end
})

Tabs.Settings:Divider()
Tabs.Settings:Section({ Title = "Delete Config", TextSize = 16 })

Tabs.Settings:Button({
    Title = "Delete Current Config",
    Icon = "trash",
    Callback = function()
        if currentConfigName == "" then
            WindUI:Notify({ Title = "Error", Content = "No config selected!", Duration = 2 })
            return
        end
        local success, msg = DeleteConfig(currentConfigName)
        if success then
            RefreshConfigDropdown()
            UpdateConfigDisplay()
        end
        WindUI:Notify({ Title = success and "Config" or "Error", Content = msg, Duration = 2 })
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
        for _, name in ipairs(names) do
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
    Desc = "Press L to toggle the UI\nConfigs saved to: " .. CONFIGS_FILE
})

-- ═══════════════════════════════════════════════════════════════
-- INITIALIZE
-- ═══════════════════════════════════════════════════════════════

SetupEmoteConnections()

task.spawn(function()
    task.wait(1)
    
    -- Load configs
    print("[Init] Loading configs...")
    local loaded = LoadAllConfigs()
    print("[Init] Configs loaded: " .. tostring(loaded))
    print("[Init] Config count: " .. #GetConfigNames())
    print("[Init] Current config: " .. (currentConfigName ~= "" and currentConfigName or "none"))
    
    RefreshConfigDropdown()
    UpdateConfigList()
    UpdateConfigDisplay()
    
    -- Auto-load last used config
    if currentConfigName ~= "" and allConfigs[currentConfigName] then
        print("[Init] Auto-loading config: " .. currentConfigName)
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
