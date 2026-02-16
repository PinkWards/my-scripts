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

local HttpService = game:GetService("HttpService")

-- ============================================================
-- CORE EMOTE CHANGER (EXACT COPY FROM WORKING SCRIPT)
-- DO NOT MODIFY ANYTHING IN THIS SECTION
-- ============================================================

player = game:GetService("Players").LocalPlayer
ReplicatedStorage = game:GetService("ReplicatedStorage")

emoteModelScript = nil
originalEmoteData = {}
replacementEnabled = false
emoteDataSaved = false
emoteFrame = nil
currentTag = nil

currentEmotes = {}
selectEmotes = {}
currentEmoteInputs = {}
selectEmoteInputs = {}

for i = 1, 12 do
    currentEmotes[i] = ""
    selectEmotes[i] = ""
end

Events = ReplicatedStorage:WaitForChild("Events", 10)
CharacterFolder = Events and Events:WaitForChild("Character", 10)
EmoteRemote = CharacterFolder and CharacterFolder:WaitForChild("Emote", 10)
PassCharacterInfo = CharacterFolder and CharacterFolder:WaitForChild("PassCharacterInfo", 10)
remoteSignal = PassCharacterInfo and PassCharacterInfo.OnClientEvent

emoteNameCache = {}
normalizedCache = {}

function fireSelect(emoteName)
    if not currentTag then return end
    local tagNumber = tonumber(currentTag)
    if not tagNumber or tagNumber < 0 or tagNumber > 255 then return end
    if not emoteName or emoteName == "" then return end
    
    local bufferData = buffer.create(2)
    buffer.writeu8(bufferData, 0, tagNumber)
    buffer.writeu8(bufferData, 1, 17)
    
    if remoteSignal then
        firesignal(remoteSignal, bufferData, {emoteName})
    end
end

function setupAnimationListener()
    function setupHumanoidListeners(char)
        local isR15 = char:GetAttribute("R15") == true
        local humanoid
        if isR15 then
            local r15Visual = char:WaitForChild("R15Visual", 5)
            if r15Visual then
                humanoid = r15Visual:WaitForChild("Visual_Humanoid", 5)
            end
        else
            humanoid = char:WaitForChild("Humanoid", 5)
        end
        
        if humanoid then
            humanoid.AnimationPlayed:Connect(function(track)
                local animation = track.Animation
                if animation and animation:IsDescendantOf(ReplicatedStorage.Items.Emotes) then
                    local emoteModule = animation:FindFirstAncestorWhichIsA("ModuleScript")
                    if emoteModule then
                        local currentEmoteName = emoteModule.Name
                        
                        for i = 1, 12 do
                            if currentEmotes[i] ~= "" and selectEmotes[i] ~= "" then
                                local normalizedCurrent = normalizeText(currentEmotes[i])
                                local normalizedPlaying = normalizeText(currentEmoteName)
                                
                                if normalizedCurrent == normalizedPlaying then
                                    fireSelect(selectEmotes[i])
                                    break
                                end
                            end
                        end
                    end
                end
            end)
        end
    end
    
    if player.Character then
        setupHumanoidListeners(player.Character)
    end
    
    player.CharacterAdded:Connect(function(newChar)
        task.wait(0.5)
        setupHumanoidListeners(newChar)
    end)
end

setupAnimationListener()

function findEmoteModelScript()
    if emoteModelScript then return emoteModelScript end
    
    for _, script in pairs(player.PlayerScripts:GetDescendants()) do
        if script.Name == "EmoteModel" then
            emoteModelScript = script
            return script
        end
    end
    
    for _, script in pairs(ReplicatedStorage:GetDescendants()) do
        if script.Name == "EmoteModel" then
            emoteModelScript = script
            return script
        end
    end
    return nil
end

function normalizeText(text)
    if not text then return "" end
    if not normalizedCache[text] then
        normalizedCache[text] = string.lower(text:gsub("%s+", ""))
    end
    return normalizedCache[text]
end

function findEmoteModuleByDisplayName(displayName)
    if displayName == "NONE" or not displayName then return nil end
    
    if emoteNameCache[displayName] ~= nil then
        return emoteNameCache[displayName]
    end
    
    emotesFolder = ReplicatedStorage:FindFirstChild("Items")
    if not emotesFolder then 
        emoteNameCache[displayName] = nil
        return nil 
    end
    emotesFolder = emotesFolder:FindFirstChild("Emotes")
    if not emotesFolder then 
        emoteNameCache[displayName] = nil
        return nil 
    end
    
    normalizedDisplayName = normalizeText(displayName)
    
    for _, emoteModule in pairs(emotesFolder:GetChildren()) do
        success, emoteData = pcall(require, emoteModule)
        if success and emoteData then
            emoteDisplayName = emoteData.AppearanceInfo.NameShorted or emoteData.AppearanceInfo.Name
            if normalizeText(emoteDisplayName) == normalizedDisplayName then
                emoteNameCache[displayName] = emoteModule.Name
                return emoteModule.Name
            end
        end
    end
    
    emoteNameCache[displayName] = nil
    return nil
end

function getEmoteFrame()
    playerGui = player.PlayerGui
    shared = playerGui and playerGui:FindFirstChild("Shared")
    hud = shared and shared:FindFirstChild("HUD")
    interactors = hud and hud:FindFirstChild("Interactors")
    popups = interactors and interactors:FindFirstChild("Popups")
    return popups and popups:FindFirstChild("Emote")
end

function cleanUpLastEmoteFrame()
    if emoteFrame then
        emoteFrame = nil
    end
end

function restoreOriginalEmotes()
    if not emoteModelScript then
        findEmoteModelScript()
    end
    if not emoteModelScript or not emoteFrame then return end
    
    emoteModelFunction = require(emoteModelScript)
    emoteWheel = emoteFrame:FindFirstChild("Wheel")
    emoteWheel2 = emoteFrame:FindFirstChild("Wheel2")
    
    if not emoteWheel then return end
    
    function processSlot(emoteSlot, key)
        if not emoteSlot then return end
        textLabel = emoteSlot:FindFirstChild("TextLabel")
        viewportFrame = emoteSlot:FindFirstChild("ViewportFrame")
        
        if textLabel and viewportFrame then
            original = originalEmoteData[key]
            if original then
                if viewportFrame:FindFirstChild("WorldModel") then
                    viewportFrame.WorldModel:Destroy()
                end
                
                if original.displayText ~= "NONE" and original.emoteName then
                    emoteModule = ReplicatedStorage.Items.Emotes:FindFirstChild(original.emoteName)
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

function replaceEmotesFrame()
    if not replacementEnabled or not emoteDataSaved or not emoteFrame then return false end
    if not emoteModelScript then findEmoteModelScript() end
    if not emoteModelScript then return false end
    
    emoteModelFunction = require(emoteModelScript)
    emoteWheel = emoteFrame:FindFirstChild("Wheel")
    emoteWheel2 = emoteFrame:FindFirstChild("Wheel2")
    
    if not emoteWheel then return false end
    
    anyPairsConfigured = false
    
    function processEmoteSlot(emoteSlot, wheelName, i)
        if not emoteSlot then return end
        textLabel = emoteSlot:FindFirstChild("TextLabel")
        if not textLabel then return end
        
        currentText = textLabel.Text
        normalizedCurrent = normalizeText(currentText)
        
        for j = 1, 12 do
            searchEmote = currentEmotes[j]
            replaceEmote = selectEmotes[j]
            
            if searchEmote ~= "" and replaceEmote ~= "" then
                anyPairsConfigured = true
                if normalizedCurrent == normalizeText(searchEmote) then
                    viewportFrame = emoteSlot.ViewportFrame
                    if viewportFrame then
                        replacementModule = ReplicatedStorage.Items.Emotes:FindFirstChild(replaceEmote)
                        if replacementModule then
                            key = wheelName.."_Emote"..i
                            if not originalEmoteData[key] then
                                originalEmoteData[key] = {
                                    displayText = currentText,
                                    emoteName = findEmoteModuleByDisplayName(currentText) or currentText
                                }
                            end
                            
                            if viewportFrame:FindFirstChild("WorldModel") then
                                viewportFrame.WorldModel:Destroy()
                            end
                            
                            targetEmoteModule = require(replacementModule)
                            targetDisplayName = targetEmoteModule.AppearanceInfo.NameShorted or targetEmoteModule.AppearanceInfo.Name
                            
                            emoteModelFunction(viewportFrame, replaceEmote)
                            textLabel.Text = targetDisplayName
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
    
    return anyPairsConfigured
end

function saveOriginalEmoteData(frame)
    if not frame then return end
    originalEmoteData = {}
    emoteWheel = frame:FindFirstChild("Wheel")
    emoteWheel2 = frame:FindFirstChild("Wheel2")
    
    if not emoteWheel then return end
    
    function saveSlot(emoteSlot, key)
        if not emoteSlot then return end
        textLabel = emoteSlot:FindFirstChild("TextLabel")
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

function readTagFromFolder(folder)
    if not folder then return nil end
    attributeValue = folder:GetAttribute("Tag")
    if attributeValue ~= nil then return attributeValue end
    tagValue = folder:FindFirstChild("Tag")
    if tagValue and tagValue:IsA("ValueBase") then return tagValue.Value end
    return nil
end

local respawnInProgress = false
local lastRespawnTime = 0
local reapplyThread = nil

function cleanupOnRespawn()
    currentTag = nil
    emoteFrame = nil
    
    if reapplyThread then
        task.cancel(reapplyThread)
        reapplyThread = nil
    end
end

function handleSingleRespawn()
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
            if workspace:FindFirstChild("Game") and workspace.Game:FindFirstChild("Players") then
                local playerFolder = workspace.Game.Players:FindFirstChild(player.Name)
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
            task.wait(0.1)
        end
        
        respawnInProgress = false
    end)
    
    if replacementEnabled and emoteDataSaved then
        if reapplyThread then
            task.cancel(reapplyThread)
            reapplyThread = nil
        end
        
        reapplyThread = task.delay(1.5, function()
            if not replacementEnabled or not emoteDataSaved then return end
            
            for attempts = 1, 30 do
                emoteFrame = getEmoteFrame()
                if emoteFrame then
                    saveOriginalEmoteData(emoteFrame)
                    restoreOriginalEmotes()
                    replaceEmotesFrame()
                    break
                end
                task.wait(0.1)
            end
        end)
    end
end

-- ============================================================
-- END OF CORE EMOTE CHANGER (DO NOT MODIFY ABOVE)
-- ============================================================

-- === EXTRA VARIABLES ===

local allEmotes = {}
local SAVE_FOLDER = "DaraHub"
local CONFIGS_FILE = SAVE_FOLDER .. "/EmoteConfigs.json"
local cachedCosmeticNames = nil
local levD = {}
local cosmetic1, cosmetic2 = "", ""
local isSwapped = false
local cosmetic1Input, cosmetic2Input = nil, nil
local allConfigs = {}
local currentConfigName = ""
local configDropdown = nil

-- === COSMETICS ===

local function cosmeticNormalize(str)
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
    local nS, nT = cosmeticNormalize(s), cosmeticNormalize(t)
    local maxLen = math.max(#nS, #nT)
    if maxLen == 0 then return 1 end
    return 1 - levenshtein(nS, nT) / maxLen
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
    if cosmetic1 == "" or cosmetic2 == "" then return false, "Please enter both cosmetics" end
    if cosmetic1 == cosmetic2 then return false, "Cosmetics must be different" end
    local Cosmetics = GetCosmeticsFolder()
    if not Cosmetics then return false, "Cosmetics folder not found" end
    local m1 = findSimilarCosmetic(cosmetic1)
    local m2 = findSimilarCosmetic(cosmetic2)
    local a = Cosmetics:FindFirstChild(m1)
    local b = Cosmetics:FindFirstChild(m2)
    if not a or not b then return false, "Could not find cosmetics" end
    local tempRoot = Instance.new("Folder", Cosmetics)
    tempRoot.Name = "__temp_swap"
    local tempA = Instance.new("Folder", tempRoot)
    local tempB = Instance.new("Folder", tempRoot)
    for _, c in ipairs(a:GetChildren()) do c.Parent = tempA end
    for _, c in ipairs(b:GetChildren()) do c.Parent = tempB end
    for _, c in ipairs(tempA:GetChildren()) do c.Parent = b end
    for _, c in ipairs(tempB:GetChildren()) do c.Parent = a end
    tempRoot:Destroy()
    cosmetic1 = m1
    cosmetic2 = m2
    isSwapped = true
    return true, "Swapped " .. m1 .. " and " .. m2
end

local function ResetCosmetics(silent)
    if not isSwapped then return false, "No cosmetics swapped" end
    local Cosmetics = GetCosmeticsFolder()
    if not Cosmetics then return false, "Cosmetics folder not found" end
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

-- === CONFIG SYSTEM ===

local function EnsureFolder()
    if not isfolder then return end
    pcall(function()
        if not isfolder(SAVE_FOLDER) then makefolder(SAVE_FOLDER) end
    end)
end

local function GetConfigNames()
    local names = {}
    for name, _ in pairs(allConfigs) do names[#names + 1] = name end
    table.sort(names, function(a, b) return a:lower() < b:lower() end)
    return names
end

local saveQueued = false
local function SaveAllConfigs()
    if saveQueued then return end
    saveQueued = true
    task.defer(function()
        saveQueued = false
        EnsureFolder()
        pcall(function()
            if writefile then
                writefile(CONFIGS_FILE, HttpService:JSONEncode({ configs = allConfigs, lastUsed = currentConfigName }))
            end
        end)
    end)
end

local function LoadAllConfigs()
    if not isfile then return false end
    local fileExists = false
    pcall(function() fileExists = isfile(CONFIGS_FILE) end)
    if not fileExists then return false end
    local success, result = pcall(function()
        return HttpService:JSONDecode(readfile(CONFIGS_FILE))
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
    local ce, se = {}, {}
    for i = 1, 12 do ce[i] = ""; se[i] = "" end
    allConfigs[name] = { currentEmotes = ce, selectEmotes = se, cosmetic1 = "", cosmetic2 = "" }
    currentConfigName = name
    SaveAllConfigs()
    return true, "Config created: " .. name
end

local function SaveToConfig(name)
    if name == "" then return false, "No config selected" end
    local ce, se = {}, {}
    for i = 1, 12 do ce[i] = currentEmotes[i]; se[i] = selectEmotes[i] end
    allConfigs[name] = { currentEmotes = ce, selectEmotes = se, cosmetic1 = cosmetic1, cosmetic2 = cosmetic2 }
    currentConfigName = name
    SaveAllConfigs()
    return true, "Saved to " .. name
end

local function LoadFromConfig(name)
    if not allConfigs[name] then return false, "Config not found" end
    local config = allConfigs[name]
    for i = 1, 12 do
        currentEmotes[i] = (config.currentEmotes and config.currentEmotes[i]) or ""
        selectEmotes[i] = (config.selectEmotes and config.selectEmotes[i]) or ""
    end
    cosmetic1 = config.cosmetic1 or ""
    cosmetic2 = config.cosmetic2 or ""
    currentConfigName = name
    SaveAllConfigs()
    return true, "Loaded " .. name
end

local function RenameConfig(oldName, newName)
    if oldName == "" or newName == "" then return false, "Name cannot be empty" end
    if not allConfigs[oldName] then return false, "Config not found" end
    if allConfigs[newName] then return false, "Name already exists" end
    allConfigs[newName] = allConfigs[oldName]
    allConfigs[oldName] = nil
    if currentConfigName == oldName then currentConfigName = newName end
    SaveAllConfigs()
    return true, "Renamed to " .. newName
end

local function DeleteConfig(name)
    if name == "" or not allConfigs[name] then return false, "Config not found" end
    allConfigs[name] = nil
    if currentConfigName == name then currentConfigName = "" end
    SaveAllConfigs()
    return true, "Deleted " .. name
end

local function DuplicateConfig(name, newName)
    if name == "" or newName == "" then return false, "Name cannot be empty" end
    if not allConfigs[name] then return false, "Config not found" end
    if allConfigs[newName] then return false, "Name already exists" end
    local o = allConfigs[name]
    local ce, se = {}, {}
    for i = 1, 12 do
        ce[i] = (o.currentEmotes and o.currentEmotes[i]) or ""
        se[i] = (o.selectEmotes and o.selectEmotes[i]) or ""
    end
    allConfigs[newName] = { currentEmotes = ce, selectEmotes = se, cosmetic1 = o.cosmetic1 or "", cosmetic2 = o.cosmetic2 or "" }
    SaveAllConfigs()
    return true, "Duplicated as " .. newName
end

-- === EMOTE SCANNER ===

local function ScanEmotes()
    allEmotes = {}
    local ef = ReplicatedStorage:FindFirstChild("Items")
    if ef then
        ef = ef:FindFirstChild("Emotes")
        if ef then
            for _, em in ipairs(ef:GetChildren()) do
                if em:IsA("ModuleScript") then
                    allEmotes[#allEmotes + 1] = em.Name
                end
            end
        end
    end
    table.sort(allEmotes, function(a, b) return a:lower() < b:lower() end)
    return allEmotes
end

-- === UI HELPER ===

local function UpdateAllUI()
    for i = 1, 12 do
        pcall(function()
            if currentEmoteInputs[i] and currentEmoteInputs[i].Set then currentEmoteInputs[i]:Set(currentEmotes[i]) end
            if selectEmoteInputs[i] and selectEmoteInputs[i].Set then selectEmoteInputs[i]:Set(selectEmotes[i]) end
        end)
    end
    pcall(function()
        if cosmetic1Input then cosmetic1Input:Set(cosmetic1) end
        if cosmetic2Input then cosmetic2Input:Set(cosmetic2) end
    end)
end

-- ============================================================
-- EMOTE CHANGER TAB
-- ============================================================

Tabs.EmoteChanger:Section({ Title = "Emote Changer", TextSize = 20 })
Tabs.EmoteChanger:Paragraph({
    Title = "How to use",
    Desc = "Current = emote you own | Select = visual replacement\nOthers see your real emote, you see the replacement"
})
Tabs.EmoteChanger:Divider()

Tabs.EmoteChanger:Section({ Title = "Animation Options", TextSize = 16 })

EmoteChangerEmoteOption = Tabs.EmoteChanger:Input({
    Title = "Emote Possible option",
    Desc = "Higher Value may Broke emote animation recommend Use 1-3 (0 or 'Random' for random)",
    Placeholder = "0",
    Value = "0",
    Callback = function(v)
        currentNum = v:lower() == "random" or tonumber(v) == 0 and "Random" or tonumber(v) or 0
        
        function setupCharacter(char)
            if char == player.Character then
                char:SetAttribute("EmoteNum", currentNum == "Random" and math.random(1, 3) or currentNum)
            end
        end
        
        function monitorCharacter()
            while true do
                task.wait(1)
                char = player.Character
                if char and char:GetAttribute("EmoteNum") ~= currentNum then
                    char:SetAttribute("EmoteNum", currentNum == "Random" and math.random(1, 3) or currentNum)
                end
            end
        end
        
        if player.Character then setupCharacter(player.Character) end
        player.CharacterAdded:Connect(function(char) task.wait(1); setupCharacter(char) end)
        spawn(monitorCharacter)
    end
})

Tabs.EmoteChanger:Divider()
Tabs.EmoteChanger:Section({ Title = "Current Emotes", TextSize = 16 })

for i = 1, 12 do
    currentEmoteInputs[i] = Tabs.EmoteChanger:Input({
        Title = "Current Emote " .. i,
        Placeholder = "Enter current emote name",
        Value = currentEmotes[i],
        Callback = function(v) currentEmotes[i] = v:gsub("%s+", "") end
    })
end

Tabs.EmoteChanger:Divider()
Tabs.EmoteChanger:Section({ Title = "Select Emotes", TextSize = 16 })

for i = 1, 12 do
    selectEmoteInputs[i] = Tabs.EmoteChanger:Input({
        Title = "Select Emote " .. i,
        Placeholder = "Enter select emote name",
        Value = selectEmotes[i],
        Callback = function(v) selectEmotes[i] = v:gsub("%s+", "") end
    })
end

Tabs.EmoteChanger:Divider()

ApplyButton = Tabs.EmoteChanger:Toggle({
    Title = "Enable replace emote wheel",
    Type = "Checkbox",
    Value = replacementEnabled,
    Callback = function(state)
        replacementEnabled = state
        ApplyButton.Color = replacementEnabled and Color3.fromHex("#305dff") or Color3.fromHex("#555555")
        
        if emoteFrame and emoteDataSaved then
            restoreOriginalEmotes()
        end
        
        if replacementEnabled and emoteFrame and emoteDataSaved then
            replaceEmotesFrame()
        end
    end
})

ApplyButton.Color = replacementEnabled and Color3.fromHex("#305dff") or Color3.fromHex("#555555")

EmoteChangerEmoteApply = Tabs.EmoteChanger:Button({
    Title = "Apply Emote Mappings",
    Icon = "refresh-cw",
    Callback = function()
        hasAnyEmote = false
        for i = 1, 12 do
            if currentEmotes[i] ~= "" or selectEmotes[i] ~= "" then
                hasAnyEmote = true
                break
            end
        end
        
        if not hasAnyEmote then
            WindUI:Notify({ Title = "Emote Changer", Content = "Please enter your emote", Duration = 3 })
            return
        end
        
        function normalizeEmoteName(name)
            return name:gsub("%s+", ""):lower()
        end
        
        function isValidEmote(emoteName)
            if emoteName == "" then return false, "" end
            normalizedInput = normalizeEmoteName(emoteName)
            emotesFolder = ReplicatedStorage:FindFirstChild("Items")
            if emotesFolder then
                emotesFolder = emotesFolder:FindFirstChild("Emotes")
                if emotesFolder then
                    for _, emoteModule in ipairs(emotesFolder:GetChildren()) do
                        if emoteModule:IsA("ModuleScript") then
                            if normalizeEmoteName(emoteModule.Name) == normalizedInput then
                                return true, emoteModule.Name
                            end
                        end
                    end
                end
            end
            return false, ""
        end
        
        sameEmoteSlots = {}
        missingEmoteSlots = {}
        invalidEmoteSlots = {}
        successfulSlots = {}
        
        for i = 1, 12 do
            if currentEmotes[i] ~= "" and selectEmotes[i] ~= "" then
                currentValid, currentActual = isValidEmote(currentEmotes[i])
                selectValid, selectActual = isValidEmote(selectEmotes[i])
                
                if not currentValid and not selectValid then
                    table.insert(invalidEmoteSlots, { slot = i, currentInvalid = true, currentName = currentEmotes[i], selectInvalid = true, selectName = selectEmotes[i] })
                elseif not currentValid then
                    table.insert(invalidEmoteSlots, { slot = i, currentInvalid = true, currentName = currentEmotes[i], selectInvalid = false, selectName = selectEmotes[i] })
                elseif not selectValid then
                    table.insert(invalidEmoteSlots, { slot = i, currentInvalid = false, currentName = currentEmotes[i], selectInvalid = true, selectName = selectEmotes[i] })
                elseif currentActual:lower() == selectActual:lower() then
                    table.insert(sameEmoteSlots, i)
                else
                    table.insert(successfulSlots, { slot = i, current = currentActual, select = selectActual })
                end
            elseif currentEmotes[i] ~= "" or selectEmotes[i] ~= "" then
                table.insert(missingEmoteSlots, i)
            end
        end
        
        message = ""
        if #successfulSlots > 0 then
            message = message .. "<font color='#00FF00'><stroke color='#000000' width='0.0001'>✓ Successfully applied emote on:</stroke></font>\n"
            for _, data in ipairs(successfulSlots) do
                message = message .. "<font color='#00FF00'><stroke color='#000000' width='0.0001'>Slot " .. data.slot .. " Emote: " .. data.current .. " → " .. data.select .. "</stroke></font>\n"
            end
            message = message .. "\n"
        end
        if #sameEmoteSlots > 0 then
            message = message .. "<font color='#ff0000'><stroke color='#FFFFFF' width='0.0001'>🆇 Failed to apply emote on:</stroke></font>\n"
            for _, slot in ipairs(sameEmoteSlots) do
                message = message .. "<font color='#ff0000'><stroke color='#FFFFFF' width='0.0001'>Slot " .. slot .. " - Cannot change emote with the same name</stroke></font>\n"
            end
            message = message .. "\n"
        end
        if #invalidEmoteSlots > 0 then
            message = message .. "<font color='#ff0000'><stroke color='#FFFFFF' width='0.0001'>🆇 Failed to apply emote on:</stroke></font>\n"
            for _, data in ipairs(invalidEmoteSlots) do
                message = message .. "<font color='#ff0000'><stroke color='#FFFFFF' width='0.0001'>Slot " .. data.slot .. " - "
                if data.currentInvalid and data.selectInvalid then
                    message = message .. "Invalid current emote: \"" .. data.currentName .. "\", Invalid select emote: \"" .. data.selectName .. "\"</stroke></font>\n"
                elseif data.currentInvalid then
                    message = message .. "Invalid current emote: \"" .. data.currentName .. "\", Select emote: \"" .. data.selectName .. "\"</stroke></font>\n"
                else
                    message = message .. "Current emote: \"" .. data.currentName .. "\", Invalid select emote: \"" .. data.selectName .. "\"</stroke></font>\n"
                end
            end
            message = message .. "\n"
        end
        if #missingEmoteSlots > 0 then
            message = message .. "<font color='#ff0000'><stroke color='#FFFFFF' width='0.0001'>🆇 Failed to apply emote on:</stroke></font>\n"
            for _, slot in ipairs(missingEmoteSlots) do
                if currentEmotes[slot] == "" then
                    message = message .. "<font color='#ff0000'><stroke color='#FFFFFF' width='0.0001'>Slot " .. slot .. " - Current emote slot is missing text</stroke></font>\n"
                else
                    message = message .. "<font color='#ff0000'><stroke color='#FFFFFF' width='0.0001'>Slot " .. slot .. " - Select emote slot is missing text</stroke></font>\n"
                end
            end
        end
        
        emoteNameCache = {}
        normalizedCache = {}
        WindUI:Notify({ Title = "Emote Changer", Content = message, Duration = 8 })
        
        cleanUpLastEmoteFrame()
        emoteFrame = getEmoteFrame()
        if not emoteFrame then
            WindUI:Notify({ Title = "Emote Changer", Content = "Emote wheel not found.", Duration = 5 })
            return
        end
        
        saveOriginalEmoteData(emoteFrame)
        restoreOriginalEmotes()
        if replacementEnabled then
            replaceEmotesFrame()
        end
    end
})

EmoteChangerEmoteReset = Tabs.EmoteChanger:Button({
    Title = "Reset All Emotes",
    Icon = "trash-2",
    Callback = function()
        if emoteFrame then
            restoreOriginalEmotes()
        end
        for i = 1, 12 do
            currentEmotes[i] = ""
            selectEmotes[i] = ""
            if currentEmoteInputs[i] and currentEmoteInputs[i].Set then currentEmoteInputs[i]:Set("") end
            if selectEmoteInputs[i] and selectEmoteInputs[i].Set then selectEmoteInputs[i]:Set("") end
        end
        if EmoteChangerEmoteOption and EmoteChangerEmoteOption.Set then EmoteChangerEmoteOption:Set("") end
        emoteNameCache = {}
        normalizedCache = {}
        cleanUpLastEmoteFrame()
        WindUI:Notify({ Title = "Emote Changer", Content = "All emotes have been reset!" })
    end
})

-- ============================================================
-- EMOTE LIST TAB
-- ============================================================

Tabs.EmoteList:Section({ Title = "Emote List", TextSize = 20 })
Tabs.EmoteList:Paragraph({ Title = "All Available Emotes", Desc = "Click any emote to copy its name" })
Tabs.EmoteList:Divider()

Tabs.EmoteList:Button({
    Title = "Refresh Emote List",
    Icon = "refresh-cw",
    Callback = function()
        ScanEmotes()
        WindUI:Notify({ Title = "Emotes", Content = "Found " .. #allEmotes .. " emotes!", Duration = 2 })
    end
})

Tabs.EmoteList:Divider()

task.spawn(function()
    task.wait(1)
    ScanEmotes()
    Tabs.EmoteList:Paragraph({ Title = "Found " .. #allEmotes .. " emotes", Desc = "Click to copy" })
    Tabs.EmoteList:Divider()
    for i, emoteName in ipairs(allEmotes) do
        Tabs.EmoteList:Button({
            Title = emoteName,
            Icon = "copy",
            Callback = function()
                if setclipboard then
                    setclipboard(emoteName)
                    WindUI:Notify({ Title = "Copied!", Content = emoteName, Duration = 1 })
                end
            end
        })
        if i % 40 == 0 then task.wait() end
    end
end)

-- ============================================================
-- VISUALS TAB
-- ============================================================

Tabs.Visuals:Section({ Title = "Cosmetics Changer", TextSize = 20 })
Tabs.Visuals:Paragraph({ Title = "How to use", Desc = "Your Cosmetic = what you own | Target = what you want" })
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
    Title = "Apply Cosmetic Swap", Icon = "check",
    Callback = function()
        if isSwapped then ResetCosmetics(true) end
        local success, msg = SwapCosmetics()
        WindUI:Notify({ Title = "Cosmetics", Content = msg, Duration = 2 })
        UpdateSwapStatus()
    end
})

Tabs.Visuals:Button({
    Title = "Reset Cosmetics", Icon = "rotate-ccw",
    Callback = function()
        local success, msg = ResetCosmetics()
        WindUI:Notify({ Title = "Cosmetics", Content = msg, Duration = 2 })
        UpdateSwapStatus()
    end
})

Tabs.Visuals:Divider()

local swapStatusParagraph = Tabs.Visuals:Paragraph({ Title = "Status", Desc = "No cosmetics swapped" })

function UpdateSwapStatus()
    pcall(function()
        if isSwapped then
            swapStatusParagraph:SetDesc("Swapped: " .. cosmetic1 .. " and " .. cosmetic2)
        else
            swapStatusParagraph:SetDesc("No cosmetics swapped")
        end
    end)
end

-- ============================================================
-- SETTINGS TAB
-- ============================================================

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
    Multi = false, AllowNone = true, Value = "", Values = {"No configs yet"},
    Callback = function(selected)
        if selected and selected ~= "No configs yet" and allConfigs[selected] then
            if isSwapped then ResetCosmetics(true) end
            if emoteFrame then restoreOriginalEmotes() end
            local success, msg = LoadFromConfig(selected)
            if success then
                UpdateAllUI()
                UpdateConfigDisplay()
                UpdateSwapStatus()
                if cosmetic1 ~= "" and cosmetic2 ~= "" and not isSwapped then
                    SwapCosmetics(true)
                    UpdateSwapStatus()
                end
                cleanUpLastEmoteFrame()
                emoteFrame = getEmoteFrame()
                if emoteFrame then
                    saveOriginalEmoteData(emoteFrame)
                    restoreOriginalEmotes()
                    if replacementEnabled then replaceEmotesFrame() end
                end
                WindUI:Notify({ Title = "Config", Content = msg, Duration = 2 })
            end
        end
    end
})

Tabs.Settings:Divider()
Tabs.Settings:Section({ Title = "Create New Config", TextSize = 16 })

local newConfigName = ""
Tabs.Settings:Input({ Title = "New Config Name", Placeholder = "Enter name", Value = "", Callback = function(v) newConfigName = v end })

Tabs.Settings:Button({
    Title = "Create Config", Icon = "plus",
    Callback = function()
        if newConfigName == "" then WindUI:Notify({ Title = "Error", Content = "Enter a name!", Duration = 2 }) return end
        local success, msg = CreateConfig(newConfigName)
        if success then RefreshConfigDropdown() UpdateConfigDisplay() UpdateConfigList() end
        WindUI:Notify({ Title = success and "Config" or "Error", Content = msg, Duration = 2 })
    end
})

Tabs.Settings:Divider()
Tabs.Settings:Section({ Title = "Quick Actions", TextSize = 16 })

Tabs.Settings:Button({
    Title = "Save Current Config", Icon = "save",
    Callback = function()
        if currentConfigName == "" then WindUI:Notify({ Title = "Error", Content = "Select or create a config!", Duration = 2 }) return end
        local success, msg = SaveToConfig(currentConfigName)
        WindUI:Notify({ Title = "Config", Content = msg, Duration = 2 })
    end
})

Tabs.Settings:Divider()
Tabs.Settings:Section({ Title = "Manage Config", TextSize = 16 })

local renameInput = ""
Tabs.Settings:Input({ Title = "New Name (for rename)", Placeholder = "Enter new name", Value = "", Callback = function(v) renameInput = v end })

Tabs.Settings:Button({
    Title = "Rename Config", Icon = "edit",
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
    Title = "Duplicate Config", Icon = "copy",
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
    Title = "Delete Current Config", Icon = "trash",
    Callback = function()
        if currentConfigName == "" then WindUI:Notify({ Title = "Error", Content = "No config selected!", Duration = 2 }) return end
        local success, msg = DeleteConfig(currentConfigName)
        if success then RefreshConfigDropdown() UpdateConfigDisplay() UpdateConfigList() end
        WindUI:Notify({ Title = success and "Config" or "Error", Content = msg, Duration = 2 })
    end
})

Tabs.Settings:Button({
    Title = "Delete ALL Configs", Icon = "alert-triangle",
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

-- ============================================================
-- INITIALIZE
-- ============================================================

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
    local loaded = LoadAllConfigs()
    RefreshConfigDropdown()
    UpdateConfigList()
    UpdateConfigDisplay()
    if currentConfigName ~= "" and allConfigs[currentConfigName] then
        local success = LoadFromConfig(currentConfigName)
        if success then
            UpdateAllUI()
            task.wait(0.5)
            if cosmetic1 ~= "" and cosmetic2 ~= "" and not isSwapped then
                SwapCosmetics(true)
                UpdateSwapStatus()
            end
            cleanUpLastEmoteFrame()
            emoteFrame = getEmoteFrame()
            if emoteFrame then
                saveOriginalEmoteData(emoteFrame)
                restoreOriginalEmotes()
                if replacementEnabled then replaceEmotesFrame() end
            end
            WindUI:Notify({ Title = "Auto-Applied!", Content = "Config: " .. currentConfigName, Duration = 3 })
        end
    else
        WindUI:Notify({ Title = "Emote Changer", Content = "Create a config in Settings!", Duration = 3 })
    end
end)

print("Visual Emote Changer Loaded")
print("Press L to toggle UI")
