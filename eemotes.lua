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
    Settings = FeatureSection:Tab({ Title = "Settings", Icon = "settings" })
}

local player = game:GetService("Players").LocalPlayer
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local PlayerGui = player:WaitForChild("PlayerGui")
local Events = ReplicatedStorage:WaitForChild("Events", 10)
local CharacterFolder = Events and Events:WaitForChild("Character", 10)
local EmoteRemote = CharacterFolder and CharacterFolder:WaitForChild("Emote", 10)
local PassCharacterInfo = CharacterFolder and CharacterFolder:WaitForChild("PassCharacterInfo", 10)

local remoteSignal = PassCharacterInfo and PassCharacterInfo.OnClientEvent
local currentTag = nil

-- 6 SLOTS
local MAX_SLOTS = 6
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
-- EMOTE WHEEL REPLACEMENT SYSTEM (NEW)
-- ═══════════════════════════════════════════════════════════════

local emoteWheelReplacementEnabled = false
local originalEmoteData = {}
local emoteDataSaved = false
local emoteWheelConnection = nil
local emoteModuleCache = {}

-- Get emote module data (icon, name, etc.)
local function GetEmoteModuleData(emoteName)
    if emoteModuleCache[emoteName] then
        return emoteModuleCache[emoteName]
    end
    
    local emotesFolder = ReplicatedStorage:FindFirstChild("Items")
    if emotesFolder then
        emotesFolder = emotesFolder:FindFirstChild("Emotes")
        if emotesFolder then
            for _, emoteModule in pairs(emotesFolder:GetChildren()) do
                if emoteModule:IsA("ModuleScript") then
                    if emoteModule.Name:lower():gsub("%s+", "") == emoteName:lower():gsub("%s+", "") then
                        local success, data = pcall(function()
                            return require(emoteModule)
                        end)
                        if success and data then
                            emoteModuleCache[emoteName] = {
                                Name = emoteModule.Name,
                                Data = data
                            }
                            return emoteModuleCache[emoteName]
                        end
                    end
                end
            end
        end
    end
    return nil
end

-- Find the emote wheel frame
local function FindEmoteWheel()
    -- Common paths for emote wheel in Evade
    local possiblePaths = {
        PlayerGui:FindFirstChild("EmoteWheel"),
        PlayerGui:FindFirstChild("Emotes"),
        PlayerGui:FindFirstChild("MainUI") and PlayerGui.MainUI:FindFirstChild("EmoteWheel"),
        PlayerGui:FindFirstChild("GameUI") and PlayerGui.GameUI:FindFirstChild("EmoteWheel"),
    }
    
    for _, path in pairs(possiblePaths) do
        if path then return path end
    end
    
    -- Deep search
    for _, gui in pairs(PlayerGui:GetDescendants()) do
        if gui:IsA("Frame") or gui:IsA("ScreenGui") then
            if gui.Name:lower():find("emote") then
                return gui
            end
        end
    end
    
    return nil
end

-- Find emote slots within the wheel
local function FindEmoteSlots(emoteWheel)
    local slots = {}
    
    if not emoteWheel then return slots end
    
    for _, child in pairs(emoteWheel:GetDescendants()) do
        -- Look for emote buttons/slots
        if child:IsA("ImageButton") or child:IsA("TextButton") or child:IsA("Frame") then
            local nameLabel = child:FindFirstChild("Name") or child:FindFirstChild("EmoteName") or child:FindFirstChild("Label")
            local iconImage = child:FindFirstChild("Icon") or child:FindFirstChild("Image") or child:FindFirstChild("EmoteIcon")
            
            if not iconImage and child:IsA("ImageButton") then
                iconImage = child
            end
            
            if nameLabel or iconImage then
                table.insert(slots, {
                    Frame = child,
                    NameLabel = nameLabel,
                    IconImage = iconImage
                })
            end
        end
    end
    
    return slots
end

-- Save original emote data
local function SaveOriginalEmoteData()
    local emoteWheel = FindEmoteWheel()
    if not emoteWheel then return false end
    
    local slots = FindEmoteSlots(emoteWheel)
    originalEmoteData = {}
    
    for i, slot in ipairs(slots) do
        originalEmoteData[i] = {
            Frame = slot.Frame,
            NameLabel = slot.NameLabel,
            IconImage = slot.IconImage,
            OriginalName = slot.NameLabel and slot.NameLabel.Text or "",
            OriginalIcon = slot.IconImage and (slot.IconImage.Image or "") or ""
        }
    end
    
    emoteDataSaved = #originalEmoteData > 0
    return emoteDataSaved
end

-- Replace emote visuals in the wheel
local function ReplaceEmoteWheelVisuals()
    if not emoteWheelReplacementEnabled then return end
    if not emoteDataSaved then
        SaveOriginalEmoteData()
    end
    
    local emoteWheel = FindEmoteWheel()
    if not emoteWheel then return end
    
    local slots = FindEmoteSlots(emoteWheel)
    
    for i, slot in ipairs(slots) do
        for j = 1, MAX_SLOTS do
            if currentEmotes[j] ~= "" and selectEmotes[j] ~= "" then
                local currentName = currentEmotes[j]:lower():gsub("%s+", "")
                local slotName = ""
                
                if slot.NameLabel then
                    slotName = slot.NameLabel.Text:lower():gsub("%s+", "")
                end
                
                if slotName == currentName or (slot.Frame.Name and slot.Frame.Name:lower():gsub("%s+", "") == currentName) then
                    -- Get replacement emote data
                    local replaceData = GetEmoteModuleData(selectEmotes[j])
                    
                    if replaceData then
                        -- Replace name
                        if slot.NameLabel then
                            slot.NameLabel.Text = replaceData.Name
                        end
                        
                        -- Replace icon
                        if slot.IconImage and replaceData.Data then
                            if replaceData.Data.Icon then
                                slot.IconImage.Image = replaceData.Data.Icon
                            elseif replaceData.Data.Image then
                                slot.IconImage.Image = replaceData.Data.Image
                            end
                        end
                    end
                    break
                end
            end
        end
    end
end

-- Restore original emote visuals
local function RestoreOriginalEmoteVisuals()
    for i, data in pairs(originalEmoteData) do
        if data.NameLabel and data.OriginalName then
            pcall(function()
                data.NameLabel.Text = data.OriginalName
            end)
        end
        if data.IconImage and data.OriginalIcon then
            pcall(function()
                data.IconImage.Image = data.OriginalIcon
            end)
        end
    end
end

-- Monitor emote wheel for changes
local function StartEmoteWheelMonitor()
    if emoteWheelConnection then
        emoteWheelConnection:Disconnect()
    end
    
    emoteWheelConnection = PlayerGui.DescendantAdded:Connect(function(descendant)
        if emoteWheelReplacementEnabled then
            task.delay(0.1, function()
                if descendant.Name:lower():find("emote") then
                    ReplaceEmoteWheelVisuals()
                end
            end)
        end
    end)
    
    -- Also check periodically
    task.spawn(function()
        while true do
            task.wait(1)
            if emoteWheelReplacementEnabled then
                ReplaceEmoteWheelVisuals()
            end
        end
    end)
end

-- ═══════════════════════════════════════════════════════════════
-- COSMETICS CHANGER VARIABLES
-- ═══════════════════════════════════════════════════════════════

local cosmetic1, cosmetic2 = "", ""
local originalCosmetic1, originalCosmetic2 = "", ""
local isSwapped = false
local cosmetic1Input, cosmetic2Input = nil, nil

-- ═══════════════════════════════════════════════════════════════
-- CONFIG SYSTEM
-- ═══════════════════════════════════════════════════════════════

local allConfigs = {}
local currentConfigName = ""
local configDropdown = nil

local function EnsureFolder()
    if not isfolder then return end
    pcall(function()
        if not isfolder(SAVE_FOLDER) then
            makefolder(SAVE_FOLDER)
        end
    end)
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
    pcall(function()
        if writefile then
            writefile(CONFIGS_FILE, HttpService:JSONEncode(data))
        end
    end)
end

local function LoadAllConfigs()
    if not isfile then return false end
    
    local fileExists = false
    pcall(function()
        fileExists = isfile(CONFIGS_FILE)
    end)
    
    if not fileExists then return false end
    
    local success, result = pcall(function()
        local content = readfile(CONFIGS_FILE)
        return HttpService:JSONDecode(content)
    end)
    
    if success and result then
        if result.configs then
            allConfigs = result.configs
            currentConfigName = result.lastUsed or ""
            return true
        end
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
        randomOptionEnabled = true,
        emoteWheelReplacement = false,
        cosmetic1 = "",
        cosmetic2 = ""
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
        randomOptionEnabled = randomOptionEnabled,
        emoteWheelReplacement = emoteWheelReplacementEnabled,
        cosmetic1 = cosmetic1,
        cosmetic2 = cosmetic2
    }
    currentConfigName = name
    SaveAllConfigs()
    return true, "Saved to " .. name
end

local function LoadFromConfig(name)
    if not allConfigs[name] then return false, "Config not found" end
    
    local config = allConfigs[name]
    
    for i = 1, MAX_SLOTS do
        currentEmotes[i] = (config.currentEmotes and config.currentEmotes[i]) or ""
        selectEmotes[i] = (config.selectEmotes and config.selectEmotes[i]) or ""
    end
    emoteOption = config.emoteOption or 1
    randomOptionEnabled = config.randomOptionEnabled ~= false
    emoteWheelReplacementEnabled = config.emoteWheelReplacement or false
    cosmetic1 = config.cosmetic1 or ""
    cosmetic2 = config.cosmetic2 or ""
    
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
        randomOptionEnabled = original.randomOptionEnabled ~= false,
        emoteWheelReplacement = original.emoteWheelReplacement or false,
        cosmetic1 = original.cosmetic1 or "",
        cosmetic2 = original.cosmetic2 or ""
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

local function SwapCosmetics(silent)
    if cosmetic1 == "" or cosmetic2 == "" then 
        return false, "Please enter both cosmetics"
    end
    
    if cosmetic1 == cosmetic2 then
        return false, "Cosmetics must be different"
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
        return false, "Could not find cosmetics"
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
    
    return true, "Swapped " .. matchedCosmetic1 .. " ↔ " .. matchedCosmetic2
end

local function ResetCosmetics(silent)
    if not isSwapped then
        return false, "No cosmetics swapped"
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
        
        return true, "Reset cosmetics"
    end
    
    return false, "Could not reset"
end

-- ═══════════════════════════════════════════════════════════════
-- EMOTE OPTION FUNCTIONS
-- ═══════════════════════════════════════════════════════════════

local emoteMonitorRunning = false

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

local function StartEmoteMonitor()
    if emoteMonitorRunning then return end
    emoteMonitorRunning = true
    
    task.spawn(function()
        while emoteMonitorRunning do
            task.wait(1)
            local char = player.Character
            if char then
                local currentNum = randomOptionEnabled and math.random(1, 3) or emoteOption
                char:SetAttribute("EmoteNum", currentNum)
            end
        end
    end)
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
    
    StartEmoteMonitor()
end

-- ═══════════════════════════════════════════════════════════════
-- EMOTE VALIDATION - DETAILED FEEDBACK
-- ═══════════════════════════════════════════════════════════════

local function NormalizeEmoteName(name)
    return name:gsub("%s+", ""):lower()
end

local function IsValidEmote(name)
    if name == "" then return false, "" end
    local normalizedInput = NormalizeEmoteName(name)
    local emotesFolder = ReplicatedStorage:FindFirstChild("Items")
    
    if emotesFolder then
        emotesFolder = emotesFolder:FindFirstChild("Emotes")
        if emotesFolder then
            for _, emoteModule in pairs(emotesFolder:GetChildren()) do
                if emoteModule:IsA("ModuleScript") then
                    if NormalizeEmoteName(emoteModule.Name) == normalizedInput then
                        return true, emoteModule.Name
                    end
                end
            end
        end
    end
    return false, ""
end

local function ValidateAndApplyEmotes()
    local sameEmoteSlots = {}
    local missingEmoteSlots = {}
    local invalidEmoteSlots = {}
    local successfulSlots = {}
    
    for i = 1, MAX_SLOTS do
        if currentEmotes[i] ~= "" and selectEmotes[i] ~= "" then
            local currentValid, currentActual = IsValidEmote(currentEmotes[i])
            local selectValid, selectActual = IsValidEmote(selectEmotes[i])
            
            if not currentValid and not selectValid then
                table.insert(invalidEmoteSlots, {
                    slot = i,
                    currentInvalid = true,
                    currentName = currentEmotes[i],
                    selectInvalid = true,
                    selectName = selectEmotes[i]
                })
                emoteEnabled[i] = false
            elseif not currentValid then
                table.insert(invalidEmoteSlots, {
                    slot = i,
                    currentInvalid = true,
                    currentName = currentEmotes[i],
                    selectInvalid = false,
                    selectName = selectEmotes[i]
                })
                emoteEnabled[i] = false
            elseif not selectValid then
                table.insert(invalidEmoteSlots, {
                    slot = i,
                    currentInvalid = false,
                    currentName = currentEmotes[i],
                    selectInvalid = true,
                    selectName = selectEmotes[i]
                })
                emoteEnabled[i] = false
            elseif currentActual:lower() == selectActual:lower() then
                table.insert(sameEmoteSlots, i)
                emoteEnabled[i] = false
            else
                table.insert(successfulSlots, {
                    slot = i,
                    current = currentActual,
                    select = selectActual
                })
                emoteEnabled[i] = true
            end
        elseif currentEmotes[i] ~= "" or selectEmotes[i] ~= "" then
            table.insert(missingEmoteSlots, i)
            emoteEnabled[i] = false
        else
            emoteEnabled[i] = false
        end
    end
    
    -- Build detailed message
    local message = ""
    
    if #successfulSlots > 0 then
        message = message .. "<font color='#00FF00'>✓ Applied:</font>\n"
        for _, data in ipairs(successfulSlots) do
            message = message .. "<font color='#00FF00'>  Slot " .. data.slot .. ": " .. data.current .. " → " .. data.select .. "</font>\n"
        end
    end
    
    if #sameEmoteSlots > 0 then
        message = message .. "<font color='#FF6B6B'>✗ Same name:</font>\n"
        for _, slot in ipairs(sameEmoteSlots) do
            message = message .. "<font color='#FF6B6B'>  Slot " .. slot .. "</font>\n"
        end
    end
    
    if #invalidEmoteSlots > 0 then
        message = message .. "<font color='#FF4444'>✗ Invalid:</font>\n"
        for _, data in ipairs(invalidEmoteSlots) do
            if data.currentInvalid and data.selectInvalid then
                message = message .. "<font color='#FF4444'>  Slot " .. data.slot .. " - Both</font>\n"
            elseif data.currentInvalid then
                message = message .. "<font color='#FF4444'>  Slot " .. data.slot .. " - \"" .. data.currentName .. "\"</font>\n"
            else
                message = message .. "<font color='#FF4444'>  Slot " .. data.slot .. " - \"" .. data.selectName .. "\"</font>\n"
            end
        end
    end
    
    if #missingEmoteSlots > 0 then
        message = message .. "<font color='#FFAA00'>⚠ Missing pair:</font>\n"
        for _, slot in ipairs(missingEmoteSlots) do
            message = message .. "<font color='#FFAA00'>  Slot " .. slot .. "</font>\n"
        end
    end
    
    if message == "" then
        message = "No emotes configured"
    end
    
    -- Apply emote wheel visuals if enabled
    if emoteWheelReplacementEnabled then
        ReplaceEmoteWheelVisuals()
    end
    
    return #successfulSlots, message
end

-- ═══════════════════════════════════════════════════════════════
-- EMOTE CHANGER LOGIC (FIRESIGNAL METHOD)
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

local function ApplyEmotes(silent)
    local count, message = ValidateAndApplyEmotes()
    return count, message
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
            for i = 1, MAX_SLOTS do
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
-- UPDATE UI FUNCTION
-- ═══════════════════════════════════════════════════════════════

local shuffleToggle, manualDropdown, emoteWheelToggle

local function UpdateAllUI()
    for i = 1, MAX_SLOTS do
        pcall(function()
            if currentEmoteInputs[i] then currentEmoteInputs[i]:Set(currentEmotes[i]) end
            if selectEmoteInputs[i] then selectEmoteInputs[i]:Set(selectEmotes[i]) end
        end)
    end
    pcall(function()
        if cosmetic1Input then cosmetic1Input:Set(cosmetic1) end
        if cosmetic2Input then cosmetic2Input:Set(cosmetic2) end
    end)
    pcall(function()
        if shuffleToggle then shuffleToggle:Set(randomOptionEnabled) end
        if manualDropdown then manualDropdown:Set(tostring(emoteOption)) end
        if emoteWheelToggle then emoteWheelToggle:Set(emoteWheelReplacementEnabled) end
    end)
end

local function ApplyEverything(silent)
    local emoteCount, emoteMessage = ApplyEmotes(silent)
    local cosmeticSuccess = false
    local cosmeticMsg = ""
    
    if cosmetic1 ~= "" and cosmetic2 ~= "" and not isSwapped then
        cosmeticSuccess, cosmeticMsg = SwapCosmetics(silent)
    end
    
    SetEmoteOption(emoteOption)
    
    if not silent then
        local msg = emoteMessage
        if cosmeticSuccess then
            msg = msg .. "\n\n<font color='#00FFFF'>Cosmetics: " .. cosmeticMsg .. "</font>"
        end
        WindUI:Notify({
            Title = "Applied!",
            Content = msg,
            Duration = 5
        })
    end
    
    return emoteCount, cosmeticSuccess
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

shuffleToggle = Tabs.EmoteChanger:Toggle({
    Title = "Shuffle Animation",
    Desc = "Randomly picks Option 1, 2, or 3 each time",
    Value = randomOptionEnabled,
    Callback = function(v)
        randomOptionEnabled = v
    end
})

manualDropdown = Tabs.EmoteChanger:Dropdown({
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

-- NEW: EMOTE WHEEL REPLACEMENT TOGGLE
Tabs.EmoteChanger:Section({ Title = "Visual Options", TextSize = 16 })

emoteWheelToggle = Tabs.EmoteChanger:Toggle({
    Title = "Replace Emote Wheel Icons",
    Desc = "Changes the icons/names in your emote wheel visually",
    Value = emoteWheelReplacementEnabled,
    Callback = function(v)
        emoteWheelReplacementEnabled = v
        if v then
            SaveOriginalEmoteData()
            ReplaceEmoteWheelVisuals()
            WindUI:Notify({
                Title = "Emote Wheel",
                Content = "Icon replacement enabled!",
                Duration = 2
            })
        else
            RestoreOriginalEmoteVisuals()
            WindUI:Notify({
                Title = "Emote Wheel",
                Content = "Icons restored to original",
                Duration = 2
            })
        end
    end
})

Tabs.EmoteChanger:Divider()
Tabs.EmoteChanger:Section({ Title = "Emote Slots (6)", TextSize = 16 })

for i = 1, MAX_SLOTS do
    Tabs.EmoteChanger:Paragraph({ Title = "Slot " .. i, Desc = "" })
    
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
    Title = "Apply Emotes",
    Icon = "check",
    Callback = function()
        local count, message = ApplyEmotes()
        WindUI:Notify({
            Title = "Emote Changer",
            Content = message,
            Duration = 5
        })
    end
})

Tabs.EmoteChanger:Button({
    Title = "Reset All Emotes",
    Icon = "trash-2",
    Callback = function()
        for i = 1, MAX_SLOTS do
            currentEmotes[i] = ""
            selectEmotes[i] = ""
            emoteEnabled[i] = false
            pcall(function()
                if currentEmoteInputs[i] then currentEmoteInputs[i]:Set("") end
                if selectEmoteInputs[i] then selectEmoteInputs[i]:Set("") end
            end)
        end
        
        -- Restore wheel visuals
        if emoteWheelReplacementEnabled then
            RestoreOriginalEmoteVisuals()
        end
        
        WindUI:Notify({ Title = "Reset", Content = "All emotes cleared!", Duration = 2 })
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
    Desc = "Your Cosmetic = what you own | Target = what you want to look like"
})
Tabs.Visuals:Divider()

cosmetic1Input = Tabs.Visuals:Input({
    Title = "Your Cosmetic (Owned)",
    Placeholder = "Enter cosmetic name",
    Value = cosmetic1,
    Callback = function(v) 
        cosmetic1 = v
    end
})

cosmetic2Input = Tabs.Visuals:Input({
    Title = "Target Cosmetic (Want)",
    Placeholder = "Enter cosmetic name",
    Value = cosmetic2,
    Callback = function(v) 
        cosmetic2 = v
    end
})

Tabs.Visuals:Divider()

Tabs.Visuals:Button({
    Title = "Apply Cosmetic Swap",
    Icon = "check",
    Callback = function()
        if isSwapped then
            ResetCosmetics(true)
        end
        local success, msg = SwapCosmetics()
        WindUI:Notify({
            Title = "Cosmetics",
            Content = msg,
            Duration = 2
        })
        UpdateSwapStatus()
    end
})

Tabs.Visuals:Button({
    Title = "Reset Cosmetics",
    Icon = "rotate-ccw",
    Callback = function()
        local success, msg = ResetCosmetics()
        WindUI:Notify({
            Title = "Cosmetics",
            Content = msg,
            Duration = 2
        })
        UpdateSwapStatus()
    end
})

Tabs.Visuals:Divider()

local swapStatusParagraph = Tabs.Visuals:Paragraph({
    Title = "Status",
    Desc = "No cosmetics swapped"
})

function UpdateSwapStatus()
    pcall(function()
        if isSwapped then
            swapStatusParagraph:SetDesc("✓ Swapped: " .. cosmetic1 .. " ↔ " .. cosmetic2)
        else
            swapStatusParagraph:SetDesc("No cosmetics swapped")
        end
    end)
end

-- ═══════════════════════════════════════════════════════════════
-- SETTINGS TAB - CONFIG SYSTEM
-- ═══════════════════════════════════════════════════════════════

Tabs.Settings:Section({ Title = "Config Profiles", TextSize = 20 })
Tabs.Settings:Paragraph({
    Title = "Manage Configs",
    Desc = "Saves emotes + cosmetics + wheel settings"
})
Tabs.Settings:Divider()

local currentConfigDisplay = Tabs.Settings:Paragraph({
    Title = "Current Config",
    Desc = "None selected"
})

local function UpdateConfigDisplay()
    pcall(function()
        currentConfigDisplay:SetDesc(currentConfigName ~= "" and ("► " .. currentConfigName) or "None selected")
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
            if isSwapped then
                ResetCosmetics(true)
            end
            if emoteWheelReplacementEnabled then
                RestoreOriginalEmoteVisuals()
            end
            
            local success, msg = LoadFromConfig(selected)
            if success then
                UpdateAllUI()
                ApplyEverything(true)
                UpdateConfigDisplay()
                UpdateSwapStatus()
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
    Placeholder = "Enter name (Main, Alt1, etc.)",
    Value = "",
    Callback = function(v)
        newConfigName = v
    end
})

Tabs.Settings:Button({
    Title = "Create Config",
    Icon = "plus",
    Callback = function()
        if newConfigName == "" then
            WindUI:Notify({ Title = "Error", Content = "Enter a name!", Duration = 2 })
            return
        end
        local success, msg = CreateConfig(newConfigName)
        if success then
            RefreshConfigDropdown()
            UpdateConfigDisplay()
            UpdateConfigList()
        end
        WindUI:Notify({ Title = success and "Config" or "Error", Content = msg, Duration = 2 })
    end
})

Tabs.Settings:Divider()
Tabs.Settings:Section({ Title = "Quick Actions", TextSize = 16 })

Tabs.Settings:Button({
    Title = "Save Current Config",
    Icon = "save",
    Callback = function()
        if currentConfigName == "" then
            WindUI:Notify({ Title = "Error", Content = "Select or create a config!", Duration = 2 })
            return
        end
        local success, msg = SaveToConfig(currentConfigName)
        WindUI:Notify({ Title = "Config", Content = msg, Duration = 2 })
    end
})

Tabs.Settings:Button({
    Title = "Apply Everything",
    Desc = "Apply all emotes + cosmetics",
    Icon = "play",
    Callback = function()
        ApplyEverything(false)
        UpdateSwapStatus()
    end
})

Tabs.Settings:Divider()
Tabs.Settings:Section({ Title = "Manage Config", TextSize = 16 })

local renameInput = ""
Tabs.Settings:Input({
    Title = "New Name (for rename)",
    Placeholder = "Enter new name",
    Value = "",
    Callback = function(v)
        renameInput = v
    end
})

Tabs.Settings:Button({
    Title = "Rename Config",
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
            UpdateConfigList()
        end
        WindUI:Notify({ Title = success and "Config" or "Error", Content = msg, Duration = 2 })
    end
})

local duplicateName = ""
Tabs.Settings:Input({
    Title = "Duplicate Name",
    Placeholder = "Name for copy",
    Value = "",
    Callback = function(v)
        duplicateName = v
    end
})

Tabs.Settings:Button({
    Title = "Duplicate Config",
    Icon = "copy",
    Callback = function()
        if currentConfigName == "" then
            WindUI:Notify({ Title = "Error", Content = "No config selected!", Duration = 2 })
            return
        end
        local success, msg = DuplicateConfig(currentConfigName, duplicateName)
        if success then
            RefreshConfigDropdown()
            UpdateConfigList()
        end
        WindUI:Notify({ Title = success and "Config" or "Error", Content = msg, Duration = 2 })
    end
})

Tabs.Settings:Divider()
Tabs.Settings:Section({ Title = "Delete", TextSize = 16 })

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
            UpdateConfigList()
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
        UpdateConfigList()
        WindUI:Notify({ Title = "Config", Content = "All configs deleted!", Duration = 2 })
    end
})

Tabs.Settings:Divider()
Tabs.Settings:Section({ Title = "Saved Configs", TextSize = 16 })

local configListParagraph = Tabs.Settings:Paragraph({
    Title = "Configs",
    Desc = "Loading..."
})

function UpdateConfigList()
    local names = GetConfigNames()
    local listText = ""
    if #names == 0 then
        listText = "No configs saved"
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
    Title = "Refresh List",
    Icon = "refresh-cw",
    Callback = function()
        RefreshConfigDropdown()
        UpdateConfigList()
        UpdateConfigDisplay()
    end
})

Tabs.Settings:Divider()
Tabs.Settings:Paragraph({
    Title = "Info",
    Desc = "Press L to toggle UI\n+ Emote wheel icon replacement!"
})

-- ═══════════════════════════════════════════════════════════════
-- INITIALIZE
-- ═══════════════════════════════════════════════════════════════

SetupEmoteConnections()
StartEmoteWheelMonitor()

task.spawn(function()
    task.wait(1)
    
    local loaded = LoadAllConfigs()
    RefreshConfigDropdown()
    UpdateConfigList()
    UpdateConfigDisplay()
    
    if currentConfigName ~= "" and allConfigs[currentConfigName] then
        local success = LoadFromConfig(currentConfigName)
        if success then
            UpdateAllUI()
            
            task.wait(0.5)
            
            local emoteCount, cosmeticSuccess = ApplyEverything(true)
            UpdateSwapStatus()
            
            local msg = "Config: " .. currentConfigName .. "\n"
            msg = msg .. "Emotes: " .. emoteCount .. " applied"
            if cosmeticSuccess then
                msg = msg .. "\nCosmetics: Swapped!"
            end
            if emoteWheelReplacementEnabled then
                msg = msg .. "\nWheel: Icons replaced!"
            end
            
            WindUI:Notify({
                Title = "Auto-Applied!",
                Content = msg,
                Duration = 3
            })
        end
    else
        WindUI:Notify({
            Title = "Emote Changer",
            Content = "Create a config in Settings!",
            Duration = 3
        })
    end
end)

print("Visual Emote Changer Loaded!")
print("+ Emote Wheel Icon Replacement")
print("Press L to toggle UI")
