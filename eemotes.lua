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

local emoteModelScript = nil
local originalEmoteData = {}
local emoteDataSaved = false
local emoteFrame = nil
local currentTag = nil

local MAX_SLOTS = 6
local currentEmotes = {"", "", "", "", "", ""}
local selectEmotes = {"", "", "", "", "", ""}

local currentEmoteInputs = {}
local selectEmoteInputs = {}

local Events = ReplicatedStorage:WaitForChild("Events", 10)
local CharacterFolder = Events and Events:WaitForChild("Character", 10)
local EmoteRemote = CharacterFolder and CharacterFolder:WaitForChild("Emote", 10)
local PassCharacterInfo = CharacterFolder and CharacterFolder:WaitForChild("PassCharacterInfo", 10)
local remoteSignal = PassCharacterInfo and PassCharacterInfo.OnClientEvent

local emoteNameCache = {}
local normalizedCache = {}

local emoteOption = 1
local randomOptionEnabled = true
local allEmotes = {}

local SAVE_FOLDER = "DaraHub"
local CONFIGS_FILE = SAVE_FOLDER .. "/EmoteConfigs.json"

local requiredModuleCache = {}
local emoteDisplayNameToModule = {}
local displayNameCacheBuilt = false
local cachedEmoteModelFunction = nil
local cachedCosmeticNames = nil
local levD = {}

local function safeRequire(moduleScript)
    local cached = requiredModuleCache[moduleScript]
    if cached ~= nil then
        return true, cached
    end
    local success, result = pcall(require, moduleScript)
    if success then
        requiredModuleCache[moduleScript] = result
    end
    return success, result
end

local function normalizeText(text)
    if not text then return "" end
    local cached = normalizedCache[text]
    if cached then return cached end
    cached = string.lower(text:gsub("%s+", ""))
    normalizedCache[text] = cached
    return cached
end

local function fireSelect(emoteName)
    if not currentTag then return end
    local tagNumber = tonumber(currentTag)
    if not tagNumber or tagNumber < 0 or tagNumber > 255 then return end
    if not emoteName or emoteName == "" then return end

    if randomOptionEnabled and player.Character then
        player.Character:SetAttribute("EmoteNum", math.random(1, 3))
    elseif player.Character then
        player.Character:SetAttribute("EmoteNum", emoteOption)
    end

    local bufferData = buffer.create(2)
    buffer.writeu8(bufferData, 0, tagNumber)
    buffer.writeu8(bufferData, 1, 17)

    if remoteSignal then
        firesignal(remoteSignal, bufferData, {emoteName})
    end
end

local function setupHumanoidListeners(char)
    local humanoid = char:WaitForChild("Humanoid", 5)
    if not humanoid then return end

    humanoid.AnimationPlayed:Connect(function(track)
        local animation = track.Animation
        if not animation then return end
        
        local emoteItems = ReplicatedStorage:FindFirstChild("Items")
        if not emoteItems then return end
        local emotesFolder = emoteItems:FindFirstChild("Emotes")
        if not emotesFolder then return end
        
        if not animation:IsDescendantOf(emotesFolder) then return end

        local emoteModule = animation:FindFirstAncestorWhichIsA("ModuleScript")
        if not emoteModule then return end

        local currentEmoteName = emoteModule.Name
        local normalizedPlaying = normalizeText(currentEmoteName)

        for i = 1, MAX_SLOTS do
            if currentEmotes[i] ~= "" and selectEmotes[i] ~= "" then
                if normalizeText(currentEmotes[i]) == normalizedPlaying then
                    fireSelect(selectEmotes[i])
                    break
                end
            end
        end
    end)
end

local function setupAnimationListener()
    if player.Character then
        setupHumanoidListeners(player.Character)
    end

    player.CharacterAdded:Connect(function(newChar)
        task.wait(0.5)
        setupHumanoidListeners(newChar)
    end)
end

setupAnimationListener()

local function findEmoteModelScript()
    if emoteModelScript then return emoteModelScript end
    for _, script in ipairs(player.PlayerScripts:GetDescendants()) do
        if script.Name == "EmoteModel" then
            emoteModelScript = script
            return script
        end
    end
    for _, script in ipairs(ReplicatedStorage:GetDescendants()) do
        if script.Name == "EmoteModel" and script:IsA("ModuleScript") then
            emoteModelScript = script
            return script
        end
    end
    return nil
end

local function getEmoteModelFunction()
    if cachedEmoteModelFunction then return cachedEmoteModelFunction end
    if not emoteModelScript then findEmoteModelScript() end
    if not emoteModelScript then return nil end
    local success, result = safeRequire(emoteModelScript)
    if success then
        cachedEmoteModelFunction = result
        return result
    end
    return nil
end

local function BuildEmoteDisplayNameCache()
    if displayNameCacheBuilt then return end
    local emotesFolder = ReplicatedStorage:FindFirstChild("Items")
    if not emotesFolder then return end
    emotesFolder = emotesFolder:FindFirstChild("Emotes")
    if not emotesFolder then return end
    for _, emoteModule in ipairs(emotesFolder:GetChildren()) do
        if emoteModule:IsA("ModuleScript") then
            local success, emoteData = safeRequire(emoteModule)
            if success and emoteData and emoteData.AppearanceInfo then
                local displayName = emoteData.AppearanceInfo.NameShorted or emoteData.AppearanceInfo.Name
                if displayName then
                    emoteDisplayNameToModule[normalizeText(displayName)] = emoteModule.Name
                end
            end
        end
    end
    displayNameCacheBuilt = true
end

local function findEmoteModuleByDisplayName(displayName)
    if displayName == "NONE" or not displayName then return nil end
    local cached = emoteNameCache[displayName]
    if cached ~= nil then return cached end
    if not displayNameCacheBuilt then BuildEmoteDisplayNameCache() end
    local result = emoteDisplayNameToModule[normalizeText(displayName)]
    emoteNameCache[displayName] = result
    return result
end

local function getEmoteFrame()
    local playerGui = player.PlayerGui
    if not playerGui then return nil end
    local shared = playerGui:FindFirstChild("Shared")
    if not shared then return nil end
    local hud = shared:FindFirstChild("HUD")
    if not hud then return nil end
    local interactors = hud:FindFirstChild("Interactors")
    if not interactors then return nil end
    local popups = interactors:FindFirstChild("Popups")
    if not popups then return nil end
    return popups:FindFirstChild("Emote")
end

local function cleanUpLastEmoteFrame()
    emoteFrame = nil
    emoteDataSaved = false
end

local function saveOriginalEmoteData(frame)
    if not frame then return end
    originalEmoteData = {}
    local emoteWheel = frame:FindFirstChild("Wheel")
    local emoteWheel2 = frame:FindFirstChild("Wheel2")
    if not emoteWheel then return end
    local function saveSlot(emoteSlot, key)
        if not emoteSlot then return end
        local textLabel = emoteSlot:FindFirstChild("TextLabel")
        if textLabel then
            originalEmoteData[key] = {
                displayText = textLabel.Text,
                emoteName = findEmoteModuleByDisplayName(textLabel.Text) or textLabel.Text
            }
        end
    end
    for i = 1, 6 do
        saveSlot(emoteWheel:FindFirstChild("Emote"..i), "Wheel_Emote"..i)
    end
    if emoteWheel2 then
        for i = 1, 6 do
            saveSlot(emoteWheel2:FindFirstChild("Emote"..i), "Wheel2_Emote"..i)
        end
    end
    emoteDataSaved = true
end

local function restoreOriginalEmotes()
    local emoteModelFunction = getEmoteModelFunction()
    if not emoteModelFunction or not emoteFrame then return end
    local emoteWheel = emoteFrame:FindFirstChild("Wheel")
    local emoteWheel2 = emoteFrame:FindFirstChild("Wheel2")
    if not emoteWheel then return end
    local emotesFolder = ReplicatedStorage:FindFirstChild("Items")
    emotesFolder = emotesFolder and emotesFolder:FindFirstChild("Emotes")
    local function processSlot(emoteSlot, key)
        if not emoteSlot then return end
        local textLabel = emoteSlot:FindFirstChild("TextLabel")
        local viewportFrame = emoteSlot:FindFirstChild("ViewportFrame")
        if textLabel and viewportFrame then
            local original = originalEmoteData[key]
            if original then
                local wm = viewportFrame:FindFirstChild("WorldModel")
                if wm then wm:Destroy() end
                if original.displayText ~= "NONE" and original.emoteName and emotesFolder then
                    local emoteModule = emotesFolder:FindFirstChild(original.emoteName)
                    if emoteModule then
                        emoteModelFunction(viewportFrame, original.emoteName)
                    end
                    textLabel.Text = original.displayText
                else
                    textLabel.Text = "NONE"
                end
            end
        end
    end
    for i = 1, 6 do
        processSlot(emoteWheel:FindFirstChild("Emote"..i), "Wheel_Emote"..i)
    end
    if emoteWheel2 then
        for i = 1, 6 do
            processSlot(emoteWheel2:FindFirstChild("Emote"..i), "Wheel2_Emote"..i)
        end
    end
end

local function replaceEmotesFrame()
    if not emoteDataSaved or not emoteFrame then return false end
    local emoteModelFunction = getEmoteModelFunction()
    if not emoteModelFunction then return false end
    local emoteWheel = emoteFrame:FindFirstChild("Wheel")
    local emoteWheel2 = emoteFrame:FindFirstChild("Wheel2")
    if not emoteWheel then return false end
    local emotesFolder = ReplicatedStorage:FindFirstChild("Items")
    emotesFolder = emotesFolder and emotesFolder:FindFirstChild("Emotes")
    if not emotesFolder then return false end
    local anyReplaced = false
    local function processEmoteSlot(emoteSlot, wheelName, slotIndex)
        if not emoteSlot then return end
        local textLabel = emoteSlot:FindFirstChild("TextLabel")
        if not textLabel then return end
        local normalizedCurrent = normalizeText(textLabel.Text)
        for j = 1, MAX_SLOTS do
            if currentEmotes[j] ~= "" and selectEmotes[j] ~= "" then
                if normalizedCurrent == normalizeText(currentEmotes[j]) then
                    local replaceEmote = selectEmotes[j]
                    local viewportFrame = emoteSlot:FindFirstChild("ViewportFrame")
                    if viewportFrame then
                        local replacementModule = emotesFolder:FindFirstChild(replaceEmote)
                        if replacementModule then
                            local key = wheelName.."_Emote"..slotIndex
                            if not originalEmoteData[key] then
                                originalEmoteData[key] = {
                                    displayText = textLabel.Text,
                                    emoteName = findEmoteModuleByDisplayName(textLabel.Text) or textLabel.Text
                                }
                            end
                            local wm = viewportFrame:FindFirstChild("WorldModel")
                            if wm then wm:Destroy() end
                            local success, targetEmoteModule = safeRequire(replacementModule)
                            if success and targetEmoteModule and targetEmoteModule.AppearanceInfo then
                                local targetDisplayName = targetEmoteModule.AppearanceInfo.NameShorted or targetEmoteModule.AppearanceInfo.Name
                                emoteModelFunction(viewportFrame, replaceEmote)
                                textLabel.Text = targetDisplayName
                                anyReplaced = true
                            end
                        end
                    end
                    break
                end
            end
        end
    end
    for i = 1, 6 do
        processEmoteSlot(emoteWheel:FindFirstChild("Emote"..i), "Wheel", i)
    end
    if emoteWheel2 then
        for i = 1, 6 do
            processEmoteSlot(emoteWheel2:FindFirstChild("Emote"..i), "Wheel2", i)
        end
    end
    return anyReplaced
end

local function readTagFromFolder(folder)
    if not folder then return nil end
    local attributeValue = folder:GetAttribute("Tag")
    if attributeValue ~= nil then return attributeValue end
    local tagValue = folder:FindFirstChild("Tag")
    if tagValue and tagValue:IsA("ValueBase") then return tagValue.Value end
    return nil
end

local respawnInProgress = false
local lastRespawnTime = 0
local reapplyThread = nil

local function cleanupOnRespawn()
    currentTag = nil
    emoteFrame = nil
    if reapplyThread then
        pcall(function() task.cancel(reapplyThread) end)
        reapplyThread = nil
    end
end

local function handleSingleRespawn()
    local now = tick()
    if respawnInProgress and (now - lastRespawnTime) < 2 then
        return
    end
    respawnInProgress = true
    lastRespawnTime = now
    cleanupOnRespawn()
    task.spawn(function()
        local startTime = tick()
        while tick() - startTime < 10 do
            local game_folder = workspace:FindFirstChild("Game")
            if game_folder then
                local players_folder = game_folder:FindFirstChild("Players")
                if players_folder then
                    local playerFolder = players_folder:FindFirstChild(player.Name)
                    if playerFolder then
                        currentTag = readTagFromFolder(playerFolder)
                        if currentTag then
                            local tagNumber = tonumber(currentTag)
                            if tagNumber and tagNumber >= 0 and tagNumber <= 255 then
                                break
                            end
                        end
                    end
                end
            end
            task.wait(0.1)
        end
        respawnInProgress = false
    end)
    if reapplyThread then
        pcall(function() task.cancel(reapplyThread) end)
        reapplyThread = nil
    end
    reapplyThread = task.delay(1.5, function()
        for attempts = 1, 30 do
            emoteFrame = getEmoteFrame()
            if emoteFrame then
                saveOriginalEmoteData(emoteFrame)
                replaceEmotesFrame()
                break
            end
            task.wait(0.1)
        end
    end)
end

-- Cosmetics

local cosmetic1, cosmetic2 = "", ""
local isSwapped = false
local cosmetic1Input, cosmetic2Input = nil, nil

local function normalize(str) 
    return str:gsub("%s+", ""):lower() 
end 

local function levenshtein(s, t) 
    local m, n = #s, #t 
    for i = 0, m do 
        if not levD[i] then levD[i] = {} end
        levD[i][0] = i 
    end 
    for j = 0, n do levD[0][j] = j end 
    for i = 1, m do 
        local si = s:sub(i,i)
        local row = levD[i]
        local prevRow = levD[i-1]
        for j = 1, n do 
            local cost = (si == t:sub(j,j)) and 0 or 1 
            local del = prevRow[j] + 1
            local ins = row[j-1] + 1
            local sub = prevRow[j-1] + cost
            if del < ins then
                row[j] = del < sub and del or sub
            else
                row[j] = ins < sub and ins or sub
            end
        end 
    end 
    return levD[m][n] 
end 

local function similarity(s, t) 
    local nS, nT = normalize(s), normalize(t) 
    local maxLen = math.max(#nS, #nT)
    if maxLen == 0 then return 1 end
    local dist = levenshtein(nS, nT) 
    return 1 - dist / maxLen
end 

local function GetCosmeticNames()
    if cachedCosmeticNames then return cachedCosmeticNames end
    cachedCosmeticNames = {}
    local Cosmetics = ReplicatedStorage:FindFirstChild("Items")
    if Cosmetics then Cosmetics = Cosmetics:FindFirstChild("Cosmetics") end
    if Cosmetics then
        for _, c in ipairs(Cosmetics:GetChildren()) do
            cachedCosmeticNames[#cachedCosmeticNames + 1] = c.Name
        end
    end
    return cachedCosmeticNames
end

local function findSimilarCosmetic(name) 
    local names = GetCosmeticNames()
    local bestMatch = name 
    local bestScore = 0.5 
    for _, cName in ipairs(names) do 
        local score = similarity(name, cName) 
        if score > bestScore then 
            bestScore = score 
            bestMatch = cName
        end 
    end 
    return bestMatch 
end 

local function GetCosmeticsFolder()
    local items = ReplicatedStorage:FindFirstChild("Items")
    return items and items:FindFirstChild("Cosmetics")
end

local function SwapCosmetics(silent)
    if cosmetic1 == "" or cosmetic2 == "" then 
        return false, "Please enter both cosmetics"
    end
    if cosmetic1 == cosmetic2 then
        return false, "Cosmetics must be different"
    end
    local Cosmetics = GetCosmeticsFolder()
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
    local tempRoot = Instance.new("Folder", Cosmetics) 
    tempRoot.Name = "__temp_swap" 
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
    return true, "Swapped " .. matchedCosmetic1 .. " and " .. matchedCosmetic2
end

local function ResetCosmetics(silent)
    if not isSwapped then
        return false, "No cosmetics swapped"
    end
    local Cosmetics = GetCosmeticsFolder()
    if not Cosmetics then 
        return false, "Cosmetics folder not found"
    end
    local a = Cosmetics:FindFirstChild(cosmetic1) 
    local b = Cosmetics:FindFirstChild(cosmetic2) 
    if a and b then
        local tempRoot = Instance.new("Folder", Cosmetics) 
        tempRoot.Name = "__temp_reset" 
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

-- Config system

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
        names[#names + 1] = name
    end
    table.sort(names, function(a, b)
        return a:lower() < b:lower()
    end)
    return names
end

local saveQueued = false
local function SaveAllConfigs()
    if saveQueued then return end
    saveQueued = true
    task.defer(function()
        saveQueued = false
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
    if success and result and result.configs then
        allConfigs = result.configs
        currentConfigName = result.lastUsed or ""
        return true
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
        cosmetic1 = original.cosmetic1 or "",
        cosmetic2 = original.cosmetic2 or ""
    }
    SaveAllConfigs()
    return true, "Duplicated as " .. newName
end

-- Emote scanner

local function ScanEmotes()
    allEmotes = {}
    local emotesFolder = ReplicatedStorage:FindFirstChild("Items")
    if emotesFolder then
        emotesFolder = emotesFolder:FindFirstChild("Emotes")
        if emotesFolder then
            for _, emoteModule in ipairs(emotesFolder:GetChildren()) do
                if emoteModule:IsA("ModuleScript") then
                    allEmotes[#allEmotes + 1] = emoteModule.Name
                end
            end
        end
    end
    table.sort(allEmotes, function(a, b)
        return a:lower() < b:lower()
    end)
    if not displayNameCacheBuilt then
        BuildEmoteDisplayNameCache()
    end
    return allEmotes
end

-- Validation

local emoteNameSet = nil
local emoteNameMap = nil

local function BuildEmoteNameSet()
    emoteNameSet = {}
    emoteNameMap = {}
    local emotesFolder = ReplicatedStorage:FindFirstChild("Items")
    if emotesFolder then
        emotesFolder = emotesFolder:FindFirstChild("Emotes")
        if emotesFolder then
            for _, emoteModule in ipairs(emotesFolder:GetChildren()) do
                if emoteModule:IsA("ModuleScript") then
                    local norm = normalizeText(emoteModule.Name)
                    emoteNameSet[norm] = true
                    emoteNameMap[norm] = emoteModule.Name
                end
            end
        end
    end
end

local function isValidEmote(emoteName)
    if emoteName == "" then return false, "" end
    if not emoteNameSet then BuildEmoteNameSet() end
    local normalized = normalizeText(emoteName)
    if emoteNameSet[normalized] then
        return true, emoteNameMap[normalized]
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
            local currentValid, currentActual = isValidEmote(currentEmotes[i])
            local selectValid, selectActual = isValidEmote(selectEmotes[i])
            if not currentValid and not selectValid then
                invalidEmoteSlots[#invalidEmoteSlots + 1] = {
                    slot = i, currentInvalid = true, currentName = currentEmotes[i],
                    selectInvalid = true, selectName = selectEmotes[i]
                }
            elseif not currentValid then
                invalidEmoteSlots[#invalidEmoteSlots + 1] = {
                    slot = i, currentInvalid = true, currentName = currentEmotes[i],
                    selectInvalid = false, selectName = selectEmotes[i]
                }
            elseif not selectValid then
                invalidEmoteSlots[#invalidEmoteSlots + 1] = {
                    slot = i, currentInvalid = false, currentName = currentEmotes[i],
                    selectInvalid = true, selectName = selectEmotes[i]
                }
            elseif currentActual:lower() == selectActual:lower() then
                sameEmoteSlots[#sameEmoteSlots + 1] = i
            else
                currentEmotes[i] = currentActual
                selectEmotes[i] = selectActual
                successfulSlots[#successfulSlots + 1] = {
                    slot = i, current = currentActual, select = selectActual
                }
            end
        elseif currentEmotes[i] ~= "" or selectEmotes[i] ~= "" then
            missingEmoteSlots[#missingEmoteSlots + 1] = i
        end
    end
    local parts = {}
    if #successfulSlots > 0 then
        parts[#parts + 1] = "<font color='#00FF00'>Applied:</font>"
        for _, data in ipairs(successfulSlots) do
            parts[#parts + 1] = "<font color='#00FF00'>  Slot " .. data.slot .. ": " .. data.current .. " > " .. data.select .. "</font>"
        end
    end
    if #sameEmoteSlots > 0 then
        parts[#parts + 1] = "<font color='#FF6B6B'>Same name:</font>"
        for _, slot in ipairs(sameEmoteSlots) do
            parts[#parts + 1] = "<font color='#FF6B6B'>  Slot " .. slot .. "</font>"
        end
    end
    if #invalidEmoteSlots > 0 then
        parts[#parts + 1] = "<font color='#FF4444'>Invalid:</font>"
        for _, data in ipairs(invalidEmoteSlots) do
            if data.currentInvalid and data.selectInvalid then
                parts[#parts + 1] = "<font color='#FF4444'>  Slot " .. data.slot .. " - Both</font>"
            elseif data.currentInvalid then
                parts[#parts + 1] = "<font color='#FF4444'>  Slot " .. data.slot .. " - \"" .. data.currentName .. "\"</font>"
            else
                parts[#parts + 1] = "<font color='#FF4444'>  Slot " .. data.slot .. " - \"" .. data.selectName .. "\"</font>"
            end
        end
    end
    if #missingEmoteSlots > 0 then
        parts[#parts + 1] = "<font color='#FFAA00'>Missing pair:</font>"
        for _, slot in ipairs(missingEmoteSlots) do
            parts[#parts + 1] = "<font color='#FFAA00'>  Slot " .. slot .. "</font>"
        end
    end
    local message = #parts > 0 and table.concat(parts, "\n") or "No emotes configured"
    cleanUpLastEmoteFrame()
    emoteFrame = getEmoteFrame()
    if emoteFrame then
        saveOriginalEmoteData(emoteFrame)
        restoreOriginalEmotes()
        replaceEmotesFrame()
    end
    return #successfulSlots, message
end

-- UI functions

local shuffleToggle, manualDropdown

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
    end)
end

local function ApplyEmotes(silent)
    return ValidateAndApplyEmotes()
end

local function ApplyEverything(silent)
    local emoteCount, emoteMessage = ApplyEmotes(silent)
    local cosmeticSuccess = false
    local cosmeticMsg = ""
    if cosmetic1 ~= "" and cosmetic2 ~= "" and not isSwapped then
        cosmeticSuccess, cosmeticMsg = SwapCosmetics(silent)
    end
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

-- UI Tabs

Tabs.EmoteChanger:Section({ Title = "Emote Changer", TextSize = 20 })
Tabs.EmoteChanger:Paragraph({
    Title = "How to use",
    Desc = "Current = emote you own | Select = visual replacement\nOthers see your real emote, you see the replacement"
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
        emoteOption = tonumber(v) or 1
        if player.Character then
            player.Character:SetAttribute("EmoteNum", emoteOption)
        end
    end
})

Tabs.EmoteChanger:Divider()
Tabs.EmoteChanger:Section({ Title = "Emote Slots", TextSize = 16 })

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
        Placeholder = "Visual replacement",
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
        if emoteFrame then
            restoreOriginalEmotes()
        end
        for i = 1, MAX_SLOTS do
            currentEmotes[i] = ""
            selectEmotes[i] = ""
            pcall(function()
                if currentEmoteInputs[i] then currentEmoteInputs[i]:Set("") end
                if selectEmoteInputs[i] then selectEmoteInputs[i]:Set("") end
            end)
        end
        emoteNameCache = {}
        normalizedCache = {}
        cleanUpLastEmoteFrame()
        WindUI:Notify({ Title = "Reset", Content = "All emotes cleared!", Duration = 2 })
    end
})

-- Emote List Tab

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
        if i % 40 == 0 then
            task.wait()
        end
    end
end)

-- Visuals Tab

Tabs.Visuals:Section({ Title = "Cosmetics Changer", TextSize = 20 })
Tabs.Visuals:Paragraph({
    Title = "How to use",
    Desc = "Your Cosmetic = what you own | Target = what you want"
})
Tabs.Visuals:Divider()

cosmetic1Input = Tabs.Visuals:Input({
    Title = "Your Cosmetic (Owned)",
    Placeholder = "Enter cosmetic name",
    Value = cosmetic1,
    Callback = function(v) cosmetic1 = v end
})

cosmetic2Input = Tabs.Visuals:Input({
    Title = "Target Cosmetic (Want)",
    Placeholder = "Enter cosmetic name",
    Value = cosmetic2,
    Callback = function(v) cosmetic2 = v end
})

Tabs.Visuals:Divider()

Tabs.Visuals:Button({
    Title = "Apply Cosmetic Swap",
    Icon = "check",
    Callback = function()
        if isSwapped then ResetCosmetics(true) end
        local success, msg = SwapCosmetics()
        WindUI:Notify({ Title = "Cosmetics", Content = msg, Duration = 2 })
        UpdateSwapStatus()
    end
})

Tabs.Visuals:Button({
    Title = "Reset Cosmetics",
    Icon = "rotate-ccw",
    Callback = function()
        local success, msg = ResetCosmetics()
        WindUI:Notify({ Title = "Cosmetics", Content = msg, Duration = 2 })
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
            swapStatusParagraph:SetDesc("Swapped: " .. cosmetic1 .. " and " .. cosmetic2)
        else
            swapStatusParagraph:SetDesc("No cosmetics swapped")
        end
    end)
end

-- Settings Tab

Tabs.Settings:Section({ Title = "Config Profiles", TextSize = 20 })
Tabs.Settings:Paragraph({ Title = "Manage Configs", Desc = "Saves emotes + cosmetics" })
Tabs.Settings:Divider()

local currentConfigDisplay = Tabs.Settings:Paragraph({ Title = "Current Config", Desc = "None selected" })

local function UpdateConfigDisplay()
    pcall(function()
        currentConfigDisplay:SetDesc(currentConfigName ~= "" and currentConfigName or "None selected")
    end)
end

Tabs.Settings:Section({ Title = "Select Config", TextSize = 16 })

local function RefreshConfigDropdown()
    local names = GetConfigNames()
    if #names == 0 then names = {"No configs yet"} end
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
            if isSwapped then ResetCosmetics(true) end
            if emoteFrame then restoreOriginalEmotes() end
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
    Placeholder = "Enter name",
    Value = "",
    Callback = function(v) newConfigName = v end
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
    Icon = "play",
    Callback = function()
        ApplyEverything(false)
        UpdateSwapStatus()
    end
})

Tabs.Settings:Divider()
Tabs.Settings:Section({ Title = "Manage Config", TextSize = 16 })

local renameInput = ""
Tabs.Settings:Input({ Title = "New Name (for rename)", Placeholder = "Enter new name", Value = "", Callback = function(v) renameInput = v end })

Tabs.Settings:Button({
    Title = "Rename Config",
    Icon = "edit",
    Callback = function()
        if currentConfigName == "" then WindUI:Notify({ Title = "Error", Content = "No config selected!", Duration = 2 }) return end
        local success, msg = RenameConfig(currentConfigName, renameInput)
        if success then RefreshConfigDropdown() UpdateConfigDisplay() UpdateConfigList() end
        WindUI:Notify({ Title = success and "Config" or "Error", Content = msg, Duration = 2 })
    end
})

local duplicateName = ""
Tabs.Settings:Input({ Title = "Duplicate Name", Placeholder = "Name for copy", Value = "", Callback = function(v) duplicateName = v end })

Tabs.Settings:Button({
    Title = "Duplicate Config",
    Icon = "copy",
    Callback = function()
        if currentConfigName == "" then WindUI:Notify({ Title = "Error", Content = "No config selected!", Duration = 2 }) return end
        local success, msg = DuplicateConfig(currentConfigName, duplicateName)
        if success then RefreshConfigDropdown() UpdateConfigList() end
        WindUI:Notify({ Title = success and "Config" or "Error", Content = msg, Duration = 2 })
    end
})

Tabs.Settings:Divider()
Tabs.Settings:Section({ Title = "Delete", TextSize = 16 })

Tabs.Settings:Button({
    Title = "Delete Current Config",
    Icon = "trash",
    Callback = function()
        if currentConfigName == "" then WindUI:Notify({ Title = "Error", Content = "No config selected!", Duration = 2 }) return end
        local success, msg = DeleteConfig(currentConfigName)
        if success then RefreshConfigDropdown() UpdateConfigDisplay() UpdateConfigList() end
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

local configListParagraph = Tabs.Settings:Paragraph({ Title = "Configs", Desc = "Loading..." })

function UpdateConfigList()
    local names = GetConfigNames()
    if #names == 0 then
        pcall(function() configListParagraph:SetDesc("No configs saved") end)
        return
    end
    local parts = {}
    for _, name in ipairs(names) do
        if name == currentConfigName then
            parts[#parts + 1] = "> " .. name .. " (active)"
        else
            parts[#parts + 1] = "  " .. name
        end
    end
    pcall(function() configListParagraph:SetDesc(table.concat(parts, "\n")) end)
end

Tabs.Settings:Button({ Title = "Refresh List", Icon = "refresh-cw", Callback = function() RefreshConfigDropdown() UpdateConfigList() UpdateConfigDisplay() end })

Tabs.Settings:Divider()
Tabs.Settings:Paragraph({ Title = "Info", Desc = "Press L to toggle UI\nVisual only - you see replacement, others see your real emote" })

-- Initialize

findEmoteModelScript()

if player.Character then
    task.spawn(handleSingleRespawn)
end

player.CharacterAdded:Connect(function()
    task.wait(1)
    handleSingleRespawn()
end)

if workspace:FindFirstChild("Game") and workspace.Game:FindFirstChild("Players") then
    workspace.Game.Players.ChildAdded:Connect(function(child)
        if child.Name == player.Name then
            task.wait(0.5)
            handleSingleRespawn()
        end
    end)
    workspace.Game.Players.ChildRemoved:Connect(function(child)
        if child.Name == player.Name then
            currentTag = nil
            cleanUpLastEmoteFrame()
        end
    end)
end

task.spawn(function()
    task.wait(1)
    BuildEmoteDisplayNameCache()
    BuildEmoteNameSet()
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
            local msg = "Config: " .. currentConfigName .. "\nEmotes: " .. emoteCount .. " applied"
            if cosmeticSuccess then msg = msg .. "\nCosmetics: Swapped!" end
            WindUI:Notify({ Title = "Auto-Applied!", Content = msg, Duration = 3 })
        end
    else
        WindUI:Notify({ Title = "Emote Changer", Content = "Create a config in Settings!", Duration = 3 })
    end
end)

print("Visual Emote Changer Loaded")
print("Press L to toggle UI")
