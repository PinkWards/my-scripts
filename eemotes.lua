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
    Title = "Visual Emote Changer V5",
    Author = "By Pnsdg Evade",
    Folder = "DaraHub",
    Size = UDim2.fromOffset(580, 490),
    Theme = "Dark",
    HidePanelBackground = false,
    Acrylic = false,
    HideSearchBar = false,
    SideBarWidth = 200
})

Window:SetIconSize(48)

Window:CreateTopbarButton("theme-switcher", "moon", function()
    WindUI:SetTheme(WindUI:GetCurrentTheme() == "Dark" and "Light" or "Dark")
end, 990)

local FeatureSection = Window:Section({ Title = "Features", Opened = true })
local Tabs = {
    EmoteChanger = FeatureSection:Tab({ Title = "EmoteChanger", Icon = "smile" }),
    EmoteList = FeatureSection:Tab({ Title = "Emote List", Icon = "list" }),
    Visuals = FeatureSection:Tab({ Title = "Visuals", Icon = "eye" })
}

-- ═══════════════════════════════════════════════════════════════
-- CONFIG SYSTEM
-- ═══════════════════════════════════════════════════════════════

local HttpService = game:GetService("HttpService")
local CONFIG_FOLDER = "DaraHub"
local CONFIG_FILE = CONFIG_FOLDER .. "/EmoteConfig.json"

local function EnsureConfigFolder()
    if not isfolder then return end
    pcall(function()
        if not isfolder(CONFIG_FOLDER) then
            makefolder(CONFIG_FOLDER)
        end
    end)
end

local function SaveConfig(ownedEmotes, replaceEmotes, replacementEnabled, cosmeticOwned, cosmeticTarget)
    local success, err = pcall(function()
        EnsureConfigFolder()
        local data = {
            Version = 3,
            Slots = {},
            ReplacementEnabled = replacementEnabled or false,
            CosmeticOwned = cosmeticOwned or "",
            CosmeticTarget = cosmeticTarget or ""
        }
        for i = 1, 6 do
            data.Slots[i] = {
                Owned = ownedEmotes[i] or "",
                Replace = replaceEmotes[i] or ""
            }
        end
        writefile(CONFIG_FILE, HttpService:JSONEncode(data))
    end)
    return success, err
end

local function LoadConfig()
    local data = {
        Slots = {},
        ReplacementEnabled = false,
        CosmeticOwned = "",
        CosmeticTarget = ""
    }
    for i = 1, 6 do
        data.Slots[i] = { Owned = "", Replace = "" }
    end
    
    pcall(function()
        if isfile and isfile(CONFIG_FILE) then
            local raw = readfile(CONFIG_FILE)
            local parsed = HttpService:JSONDecode(raw)
            if parsed and parsed.Slots then
                for i = 1, 6 do
                    if parsed.Slots[i] then
                        data.Slots[i].Owned = parsed.Slots[i].Owned or ""
                        data.Slots[i].Replace = parsed.Slots[i].Replace or ""
                    end
                end
                data.ReplacementEnabled = parsed.ReplacementEnabled or false
                data.CosmeticOwned = parsed.CosmeticOwned or ""
                data.CosmeticTarget = parsed.CosmeticTarget or ""
            end
        end
    end)
    
    return data
end

local function DeleteConfig()
    pcall(function()
        if isfile and isfile(CONFIG_FILE) then
            delfile(CONFIG_FILE)
        end
    end)
end

-- ═══════════════════════════════════════════════════════════════
-- LOAD SAVED CONFIG
-- ═══════════════════════════════════════════════════════════════

local savedConfig = LoadConfig()

-- ═══════════════════════════════════════════════════════════════
-- EMOTE CHANGER CORE
-- ═══════════════════════════════════════════════════════════════

Tabs.EmoteChanger:Section({ Title = "Emote ID Hook" })

local player = game:GetService("Players").LocalPlayer
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local emoteModelScript = nil
local originalEmoteData = {}
local replacementEnabled = savedConfig.ReplacementEnabled or false
local emoteDataSaved = false
local emoteFrame = nil
local currentTag = nil

local ownedEmotes = {}
local replaceEmotes = {}
local ownedEmoteInputs = {}
local replaceEmoteInputs = {}

for i = 1, 6 do
    ownedEmotes[i] = savedConfig.Slots[i].Owned
    replaceEmotes[i] = savedConfig.Slots[i].Replace
end

local Events = ReplicatedStorage:WaitForChild("Events", 10)
local CharacterFolder = Events and Events:WaitForChild("Character", 10)
local EmoteRemote = CharacterFolder and CharacterFolder:WaitForChild("Emote", 10)
local PassCharacterInfo = CharacterFolder and CharacterFolder:WaitForChild("PassCharacterInfo", 10)
local remoteSignal = PassCharacterInfo and PassCharacterInfo.OnClientEvent

local emoteNameCache = {}
local normalizedCache = {}

local function fireSelect(emoteName)
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

local function normalizeText(text)
    if not text then return "" end
    if not normalizedCache[text] then
        normalizedCache[text] = string.lower(text:gsub("%s+", ""))
    end
    return normalizedCache[text]
end

-- ═══════════════════════════════════════════════════════════════
-- AUTO RANDOM EMOTE OPTION (1-3 automatically)
-- ═══════════════════════════════════════════════════════════════

local emoteNumCharConnection = nil

local function applyRandomEmoteNum(char)
    if not char then return end
    char:SetAttribute("EmoteNum", math.random(1, 3))
end

local function startAutoRandomEmoteNum()
    if player.Character then
        applyRandomEmoteNum(player.Character)
    end
    
    if emoteNumCharConnection then
        emoteNumCharConnection:Disconnect()
    end
    emoteNumCharConnection = player.CharacterAdded:Connect(function(char)
        task.wait(1)
        applyRandomEmoteNum(char)
    end)
    
    task.spawn(function()
        while task.wait(2) do
            local char = player.Character
            if char then
                char:SetAttribute("EmoteNum", math.random(1, 3))
            end
        end
    end)
end

startAutoRandomEmoteNum()

-- ═══════════════════════════════════════════════════════════════
-- ANIMATION LISTENER
-- ═══════════════════════════════════════════════════════════════

local function setupAnimationListener()
    local function setupHumanoidListeners(char)
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
                        
                        for i = 1, 6 do
                            if ownedEmotes[i] ~= "" and replaceEmotes[i] ~= "" then
                                local normalizedOwned = normalizeText(ownedEmotes[i])
                                local normalizedPlaying = normalizeText(currentEmoteName)
                                
                                if normalizedOwned == normalizedPlaying then
                                    fireSelect(replaceEmotes[i])
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

-- ═══════════════════════════════════════════════════════════════
-- EMOTE MODEL & WHEEL FUNCTIONS
-- ═══════════════════════════════════════════════════════════════

local function findEmoteModelScript()
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

local function findEmoteModuleByDisplayName(displayName)
    if displayName == "NONE" or not displayName then return nil end
    
    if emoteNameCache[displayName] ~= nil then
        return emoteNameCache[displayName]
    end
    
    local emotesFolder = ReplicatedStorage:FindFirstChild("Items")
    if not emotesFolder then 
        emoteNameCache[displayName] = nil
        return nil 
    end
    emotesFolder = emotesFolder:FindFirstChild("Emotes")
    if not emotesFolder then 
        emoteNameCache[displayName] = nil
        return nil 
    end
    
    local normalizedDisplayName = normalizeText(displayName)
    
    for _, emoteModule in pairs(emotesFolder:GetChildren()) do
        local success, emoteData = pcall(require, emoteModule)
        if success and emoteData then
            local emoteDisplayName = emoteData.AppearanceInfo.NameShorted or emoteData.AppearanceInfo.Name
            if normalizeText(emoteDisplayName) == normalizedDisplayName then
                emoteNameCache[displayName] = emoteModule.Name
                return emoteModule.Name
            end
        end
    end
    
    emoteNameCache[displayName] = nil
    return nil
end

local function getEmoteFrame()
    local playerGui = player.PlayerGui
    local shared = playerGui and playerGui:FindFirstChild("Shared")
    local hud = shared and shared:FindFirstChild("HUD")
    local interactors = hud and hud:FindFirstChild("Interactors")
    local popups = interactors and interactors:FindFirstChild("Popups")
    return popups and popups:FindFirstChild("Emote")
end

local function cleanUpLastEmoteFrame()
    emoteFrame = nil
end

local function restoreOriginalEmotes()
    if not emoteModelScript then
        findEmoteModelScript()
    end
    if not emoteModelScript or not emoteFrame then return end
    
    local emoteModelFunction = require(emoteModelScript)
    local emoteWheel = emoteFrame:FindFirstChild("Wheel")
    local emoteWheel2 = emoteFrame:FindFirstChild("Wheel2")
    
    if not emoteWheel then return end
    
    local function processSlot(emoteSlot, key)
        if not emoteSlot then return end
        local textLabel = emoteSlot:FindFirstChild("TextLabel")
        local viewportFrame = emoteSlot:FindFirstChild("ViewportFrame")
        
        if textLabel and viewportFrame then
            local original = originalEmoteData[key]
            if original then
                if viewportFrame:FindFirstChild("WorldModel") then
                    viewportFrame.WorldModel:Destroy()
                end
                
                if original.displayText ~= "NONE" and original.emoteName then
                    local emoteModule = ReplicatedStorage.Items.Emotes:FindFirstChild(original.emoteName)
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
    if not replacementEnabled or not emoteDataSaved or not emoteFrame then return false end
    if not emoteModelScript then findEmoteModelScript() end
    if not emoteModelScript then return false end
    
    local emoteModelFunction = require(emoteModelScript)
    local emoteWheel = emoteFrame:FindFirstChild("Wheel")
    local emoteWheel2 = emoteFrame:FindFirstChild("Wheel2")
    
    if not emoteWheel then return false end
    
    local anyPairsConfigured = false
    
    local function processEmoteSlot(emoteSlot, wheelName, i)
        if not emoteSlot then return end
        local textLabel = emoteSlot:FindFirstChild("TextLabel")
        if not textLabel then return end
        
        local currentText = textLabel.Text
        local normalizedCurrent = normalizeText(currentText)
        
        for j = 1, 6 do
            local searchEmote = ownedEmotes[j]
            local replaceEmote = replaceEmotes[j]
            
            if searchEmote ~= "" and replaceEmote ~= "" then
                anyPairsConfigured = true
                if normalizedCurrent == normalizeText(searchEmote) then
                    local viewportFrame = emoteSlot.ViewportFrame
                    if viewportFrame then
                        local replacementModule = ReplicatedStorage.Items.Emotes:FindFirstChild(replaceEmote)
                        if replacementModule then
                            local key = wheelName.."_Emote"..i
                            if not originalEmoteData[key] then
                                originalEmoteData[key] = {
                                    displayText = currentText,
                                    emoteName = findEmoteModuleByDisplayName(currentText) or currentText
                                }
                            end
                            
                            if viewportFrame:FindFirstChild("WorldModel") then
                                viewportFrame.WorldModel:Destroy()
                            end
                            
                            local targetEmoteModule = require(replacementModule)
                            local targetDisplayName = targetEmoteModule.AppearanceInfo.NameShorted or targetEmoteModule.AppearanceInfo.Name
                            
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

-- ═══════════════════════════════════════════════════════════════
-- RESPAWN HANDLING
-- ═══════════════════════════════════════════════════════════════

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
        task.cancel(reapplyThread)
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

-- ═══════════════════════════════════════════════════════════════
-- COSMETICS SYSTEM
-- ═══════════════════════════════════════════════════════════════

local cachedCosmeticNames = nil
local levD = {}
local cosmeticOwned = savedConfig.CosmeticOwned or ""
local cosmeticTarget = savedConfig.CosmeticTarget or ""
local isCosmeticSwapped = false
local cosmeticOwnedInput = nil
local cosmeticTargetInput = nil

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
        local si = s:sub(i, i)
        local row = levD[i]
        local prevRow = levD[i - 1]
        for j = 1, n do
            local cost = (si == t:sub(j, j)) and 0 or 1
            local del = prevRow[j] + 1
            local ins = row[j - 1] + 1
            local sub = prevRow[j - 1] + cost
            if del < ins then
                row[j] = del < sub and del or sub
            else
                row[j] = ins < sub and ins or sub
            end
        end
    end
    return levD[m][n]
end

local function cosmeticSimilarity(s, t)
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
        local score = cosmeticSimilarity(name, cName)
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
    if cosmeticOwned == "" or cosmeticTarget == "" then return false, "Please enter both cosmetics" end
    if cosmeticOwned == cosmeticTarget then return false, "Cosmetics must be different" end
    local Cosmetics = GetCosmeticsFolder()
    if not Cosmetics then return false, "Cosmetics folder not found" end
    local m1 = findSimilarCosmetic(cosmeticOwned)
    local m2 = findSimilarCosmetic(cosmeticTarget)
    local a = Cosmetics:FindFirstChild(m1)
    local b = Cosmetics:FindFirstChild(m2)
    if not a or not b then return false, "Could not find cosmetics: " .. m1 .. " / " .. m2 end
    
    local tempRoot = Instance.new("Folder", Cosmetics)
    tempRoot.Name = "__temp_swap"
    local tempA = Instance.new("Folder", tempRoot)
    local tempB = Instance.new("Folder", tempRoot)
    for _, c in ipairs(a:GetChildren()) do c.Parent = tempA end
    for _, c in ipairs(b:GetChildren()) do c.Parent = tempB end
    for _, c in ipairs(tempA:GetChildren()) do c.Parent = b end
    for _, c in ipairs(tempB:GetChildren()) do c.Parent = a end
    tempRoot:Destroy()
    
    cosmeticOwned = m1
    cosmeticTarget = m2
    isCosmeticSwapped = true
    return true, "Swapped: " .. m1 .. " ↔ " .. m2
end

local function ResetCosmetics(silent)
    if not isCosmeticSwapped then return false, "No cosmetics swapped" end
    local Cosmetics = GetCosmeticsFolder()
    if not Cosmetics then return false, "Cosmetics folder not found" end
    local a = Cosmetics:FindFirstChild(cosmeticOwned)
    local b = Cosmetics:FindFirstChild(cosmeticTarget)
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
        isCosmeticSwapped = false
        return true, "Cosmetics restored to original"
    end
    return false, "Could not find cosmetics to reset"
end

-- ═══════════════════════════════════════════════════════════════
-- EMOTE SCANNER
-- ═══════════════════════════════════════════════════════════════

local allEmotes = {}

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

-- ═══════════════════════════════════════════════════════════════
-- UI HELPER
-- ═══════════════════════════════════════════════════════════════

local function UpdateAllUI()
    for i = 1, 6 do
        pcall(function()
            if ownedEmoteInputs[i] and ownedEmoteInputs[i].Set then ownedEmoteInputs[i]:Set(ownedEmotes[i]) end
            if replaceEmoteInputs[i] and replaceEmoteInputs[i].Set then replaceEmoteInputs[i]:Set(replaceEmotes[i]) end
        end)
    end
    pcall(function()
        if cosmeticOwnedInput and cosmeticOwnedInput.Set then cosmeticOwnedInput:Set(cosmeticOwned) end
        if cosmeticTargetInput and cosmeticTargetInput.Set then cosmeticTargetInput:Set(cosmeticTarget) end
    end)
end

-- ═══════════════════════════════════════════════════════════════
-- EMOTE CHANGER TAB UI
-- ═══════════════════════════════════════════════════════════════

Tabs.EmoteChanger:Section({ Title = "Your Owned Emotes", TextSize = 16 })
Tabs.EmoteChanger:Section({ Title = "Enter the emote name you currently have equipped", TextSize = 10 })

for i = 1, 6 do
    ownedEmoteInputs[i] = Tabs.EmoteChanger:Input({
        Title = "Slot " .. i .. " - Owned Emote",
        Placeholder = "Enter emote you own",
        Value = ownedEmotes[i],
        Callback = function(v)
            ownedEmotes[i] = v:gsub("%s+", "")
        end
    })
end

Tabs.EmoteChanger:Divider()

Tabs.EmoteChanger:Section({ Title = "Replace With", TextSize = 16 })
Tabs.EmoteChanger:Section({ Title = "Enter the emote name you want to visually replace it with", TextSize = 10 })

for i = 1, 6 do
    replaceEmoteInputs[i] = Tabs.EmoteChanger:Input({
        Title = "Slot " .. i .. " - Replace With",
        Placeholder = "Enter emote to show instead",
        Value = replaceEmotes[i],
        Callback = function(v)
            replaceEmotes[i] = v:gsub("%s+", "")
        end
    })
end

-- ═══════════════════════════════════════════════════════════════
-- CONTROLS
-- ═══════════════════════════════════════════════════════════════

Tabs.EmoteChanger:Divider()
Tabs.EmoteChanger:Section({ Title = "Controls", TextSize = 16 })

local ApplyButton = Tabs.EmoteChanger:Toggle({
    Title = "Enable Visual Emote Replacement",
    Desc = "Shows replacement emotes on your emote wheel",
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

Tabs.EmoteChanger:Button({
    Title = "Apply Emote Mappings",
    Icon = "refresh-cw",
    Desc = "Validate and apply your emote pairs",
    Callback = function()
        local hasAnyEmote = false
        for i = 1, 6 do
            if ownedEmotes[i] ~= "" or replaceEmotes[i] ~= "" then
                hasAnyEmote = true
                break
            end
        end
        
        if not hasAnyEmote then
            WindUI:Notify({
                Title = "Emote Changer",
                Content = "Please enter at least one emote pair.",
                Duration = 3
            })
            return
        end
        
        local function normalizeEmoteName(name)
            return name:gsub("%s+", ""):lower()
        end
        
        local function isValidEmote(emoteName)
            if emoteName == "" then return false, "" end
            local normalizedInput = normalizeEmoteName(emoteName)
            local emotesFolder = ReplicatedStorage:FindFirstChild("Items")
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
        
        local sameEmoteSlots = {}
        local missingEmoteSlots = {}
        local invalidEmoteSlots = {}
        local successfulSlots = {}
        
        for i = 1, 6 do
            if ownedEmotes[i] ~= "" and replaceEmotes[i] ~= "" then
                local ownedValid, ownedActual = isValidEmote(ownedEmotes[i])
                local replaceValid, replaceActual = isValidEmote(replaceEmotes[i])
                
                if not ownedValid and not replaceValid then
                    table.insert(invalidEmoteSlots, {
                        slot = i, ownedInvalid = true, ownedName = ownedEmotes[i],
                        replaceInvalid = true, replaceName = replaceEmotes[i]
                    })
                elseif not ownedValid then
                    table.insert(invalidEmoteSlots, {
                        slot = i, ownedInvalid = true, ownedName = ownedEmotes[i],
                        replaceInvalid = false, replaceName = replaceEmotes[i]
                    })
                elseif not replaceValid then
                    table.insert(invalidEmoteSlots, {
                        slot = i, ownedInvalid = false, ownedName = ownedEmotes[i],
                        replaceInvalid = true, replaceName = replaceEmotes[i]
                    })
                elseif ownedActual:lower() == replaceActual:lower() then
                    table.insert(sameEmoteSlots, i)
                else
                    table.insert(successfulSlots, {
                        slot = i, owned = ownedActual, replace = replaceActual
                    })
                end
            elseif ownedEmotes[i] ~= "" or replaceEmotes[i] ~= "" then
                table.insert(missingEmoteSlots, i)
            end
        end
        
        local message = ""
        
        if #successfulSlots > 0 then
            message = message .. "<font color='#00FF00'><stroke color='#000000' width='0.0001'>✓ Applied:</stroke></font>\n"
            for _, data in ipairs(successfulSlots) do
                message = message .. "<font color='#00FF00'><stroke color='#000000' width='0.0001'>  Slot " .. data.slot .. ": " .. data.owned .. " → " .. data.replace .. "</stroke></font>\n"
            end
        end
        
        if #sameEmoteSlots > 0 then
            message = message .. "<font color='#ff0000'><stroke color='#FFFFFF' width='0.0001'>✗ Same emote:</stroke></font>\n"
            for _, slot in ipairs(sameEmoteSlots) do
                message = message .. "<font color='#ff0000'><stroke color='#FFFFFF' width='0.0001'>  Slot " .. slot .. " - Can't replace with same emote</stroke></font>\n"
            end
        end
        
        if #invalidEmoteSlots > 0 then
            message = message .. "<font color='#ff0000'><stroke color='#FFFFFF' width='0.0001'>✗ Invalid:</stroke></font>\n"
            for _, data in ipairs(invalidEmoteSlots) do
                message = message .. "<font color='#ff0000'><stroke color='#FFFFFF' width='0.0001'>  Slot " .. data.slot .. " - "
                if data.ownedInvalid and data.replaceInvalid then
                    message = message .. "Both invalid"
                elseif data.ownedInvalid then
                    message = message .. "Owned: \"" .. data.ownedName .. "\" not found"
                else
                    message = message .. "Replace: \"" .. data.replaceName .. "\" not found"
                end
                message = message .. "</stroke></font>\n"
            end
        end
        
        if #missingEmoteSlots > 0 then
            message = message .. "<font color='#ff0000'><stroke color='#FFFFFF' width='0.0001'>✗ Incomplete pair:</stroke></font>\n"
            for _, slot in ipairs(missingEmoteSlots) do
                local which = ownedEmotes[slot] == "" and "Owned emote" or "Replace emote"
                message = message .. "<font color='#ff0000'><stroke color='#FFFFFF' width='0.0001'>  Slot " .. slot .. " - " .. which .. " is empty</stroke></font>\n"
            end
        end
        
        emoteNameCache = {}
        normalizedCache = {}
        
        WindUI:Notify({ Title = "Emote Changer", Content = message, Duration = 8 })
        
        cleanUpLastEmoteFrame()
        emoteFrame = getEmoteFrame()
        if not emoteFrame then
            WindUI:Notify({ Title = "Emote Changer", Content = "Emote wheel not found. Open it first!", Duration = 5 })
            return
        end
        
        saveOriginalEmoteData(emoteFrame)
        restoreOriginalEmotes()
        
        if replacementEnabled then
            replaceEmotesFrame()
        end
    end
})

-- ═══════════════════════════════════════════════════════════════
-- CONFIG BUTTONS
-- ═══════════════════════════════════════════════════════════════

Tabs.EmoteChanger:Divider()
Tabs.EmoteChanger:Section({ Title = "Config", TextSize = 16 })

Tabs.EmoteChanger:Button({
    Title = "Save Config",
    Icon = "save",
    Desc = "Save emote slots + cosmetics to file",
    Callback = function()
        local success, err = SaveConfig(ownedEmotes, replaceEmotes, replacementEnabled, cosmeticOwned, cosmeticTarget)
        if success then
            WindUI:Notify({ Title = "Config", Content = "Config saved! (emotes + cosmetics)", Icon = "check-circle", Duration = 3 })
        else
            WindUI:Notify({ Title = "Config", Content = "Failed to save: " .. tostring(err), Icon = "x-circle", Duration = 3 })
        end
    end
})

Tabs.EmoteChanger:Button({
    Title = "Load Config",
    Icon = "download",
    Desc = "Load emote slots + cosmetics from file",
    Callback = function()
        local data = LoadConfig()
        
        local hasData = false
        for i = 1, 6 do
            if data.Slots[i].Owned ~= "" or data.Slots[i].Replace ~= "" then
                hasData = true
                break
            end
        end
        if data.CosmeticOwned ~= "" or data.CosmeticTarget ~= "" then
            hasData = true
        end
        
        if not hasData then
            WindUI:Notify({ Title = "Config", Content = "No saved config found or config is empty.", Icon = "info", Duration = 3 })
            return
        end
        
        -- Restore emotes if active
        if emoteFrame and emoteDataSaved then
            restoreOriginalEmotes()
        end
        
        -- Reset cosmetics if swapped
        if isCosmeticSwapped then
            ResetCosmetics(true)
        end
        
        -- Load emote slots
        for i = 1, 6 do
            ownedEmotes[i] = data.Slots[i].Owned
            replaceEmotes[i] = data.Slots[i].Replace
        end
        
        -- Load cosmetics
        cosmeticOwned = data.CosmeticOwned or ""
        cosmeticTarget = data.CosmeticTarget or ""
        
        UpdateAllUI()
        
        -- Auto-apply cosmetics if both are set
        if cosmeticOwned ~= "" and cosmeticTarget ~= "" then
            local success, msg = SwapCosmetics(true)
            if success then
                UpdateSwapStatus()
            end
        end
        
        WindUI:Notify({ Title = "Config", Content = "Config loaded! Click 'Apply Emote Mappings' to activate emotes.", Icon = "check-circle", Duration = 4 })
    end
})

Tabs.EmoteChanger:Button({
    Title = "Delete Config",
    Icon = "trash",
    Desc = "Delete saved config file",
    Callback = function()
        DeleteConfig()
        WindUI:Notify({ Title = "Config", Content = "Config file deleted.", Icon = "check-circle", Duration = 3 })
    end
})

-- ═══════════════════════════════════════════════════════════════
-- RESET ALL
-- ═══════════════════════════════════════════════════════════════

Tabs.EmoteChanger:Divider()

Tabs.EmoteChanger:Button({
    Title = "Reset All Emotes",
    Icon = "trash-2",
    Desc = "Clear all 6 slots and restore originals",
    Callback = function()
        if emoteFrame then
            restoreOriginalEmotes()
        end
        
        for i = 1, 6 do
            ownedEmotes[i] = ""
            replaceEmotes[i] = ""
            
            if ownedEmoteInputs[i] and ownedEmoteInputs[i].Set then
                ownedEmoteInputs[i]:Set("")
            end
            if replaceEmoteInputs[i] and replaceEmoteInputs[i].Set then
                replaceEmoteInputs[i]:Set("")
            end
        end
        
        emoteNameCache = {}
        normalizedCache = {}
        cleanUpLastEmoteFrame()
        
        WindUI:Notify({ Title = "Emote Changer", Content = "All 6 emote slots have been reset!", Duration = 3 })
    end
})

-- ═══════════════════════════════════════════════════════════════
-- EMOTE LIST TAB
-- ═══════════════════════════════════════════════════════════════

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

-- ═══════════════════════════════════════════════════════════════
-- VISUALS TAB (COSMETICS)
-- ═══════════════════════════════════════════════════════════════

Tabs.Visuals:Section({ Title = "Cosmetics Changer", TextSize = 20 })
Tabs.Visuals:Paragraph({
    Title = "How to use",
    Desc = "Your Cosmetic = what you own and have equipped\nTarget Cosmetic = what you want it to visually look like\nThis swaps the cosmetic data so you see the target instead"
})
Tabs.Visuals:Divider()

cosmeticOwnedInput = Tabs.Visuals:Input({
    Title = "Your Cosmetic (Owned)",
    Placeholder = "Enter cosmetic name you own",
    Value = cosmeticOwned,
    Callback = function(v) cosmeticOwned = v end
})

cosmeticTargetInput = Tabs.Visuals:Input({
    Title = "Target Cosmetic (Want)",
    Placeholder = "Enter cosmetic name you want",
    Value = cosmeticTarget,
    Callback = function(v) cosmeticTarget = v end
})

Tabs.Visuals:Divider()

Tabs.Visuals:Button({
    Title = "Apply Cosmetic Swap",
    Icon = "check",
    Desc = "Swap your owned cosmetic with the target",
    Callback = function()
        if isCosmeticSwapped then
            ResetCosmetics(true)
        end
        local success, msg = SwapCosmetics()
        WindUI:Notify({ Title = "Cosmetics", Content = msg, Duration = 3 })
        UpdateSwapStatus()
    end
})

Tabs.Visuals:Button({
    Title = "Reset Cosmetics",
    Icon = "rotate-ccw",
    Desc = "Restore cosmetics to original",
    Callback = function()
        local success, msg = ResetCosmetics()
        WindUI:Notify({ Title = "Cosmetics", Content = msg, Duration = 3 })
        UpdateSwapStatus()
    end
})

Tabs.Visuals:Divider()

Tabs.Visuals:Section({ Title = "Cosmetic List", TextSize = 16 })

Tabs.Visuals:Button({
    Title = "Show All Cosmetics",
    Icon = "list",
    Desc = "List all available cosmetic names (copies on click)",
    Callback = function()
        local names = GetCosmeticNames()
        if #names == 0 then
            WindUI:Notify({ Title = "Cosmetics", Content = "No cosmetics found!", Duration = 2 })
            return
        end
        
        -- Clear cache to rescan
        cachedCosmeticNames = nil
        names = GetCosmeticNames()
        table.sort(names, function(a, b) return a:lower() < b:lower() end)
        
        local listStr = table.concat(names, "\n")
        if setclipboard then
            setclipboard(listStr)
            WindUI:Notify({
                Title = "Cosmetics",
                Content = "Copied " .. #names .. " cosmetic names to clipboard!",
                Duration = 3
            })
        else
            WindUI:Notify({
                Title = "Cosmetics",
                Content = "Found " .. #names .. " cosmetics (clipboard not available)",
                Duration = 3
            })
        end
    end
})

Tabs.Visuals:Divider()

local swapStatusParagraph = Tabs.Visuals:Paragraph({ Title = "Swap Status", Desc = "No cosmetics swapped" })

function UpdateSwapStatus()
    pcall(function()
        if isCosmeticSwapped then
            swapStatusParagraph:SetDesc("Active: " .. cosmeticOwned .. " ↔ " .. cosmeticTarget)
        else
            swapStatusParagraph:SetDesc("No cosmetics swapped")
        end
    end)
end

Tabs.Visuals:Divider()
Tabs.Visuals:Paragraph({
    Title = "Note",
    Desc = "Cosmetic swap is visual only (client-side).\nOther players see your real cosmetic.\nCosmetics are saved with your config."
})

-- ═══════════════════════════════════════════════════════════════
-- RESPAWN CONNECTIONS
-- ═══════════════════════════════════════════════════════════════

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

-- ═══════════════════════════════════════════════════════════════
-- INITIALIZE
-- ═══════════════════════════════════════════════════════════════

findEmoteModelScript()

-- Auto-apply cosmetics from saved config on load
task.spawn(function()
    task.wait(1.5)
    if cosmeticOwned ~= "" and cosmeticTarget ~= "" and not isCosmeticSwapped then
        local success, msg = SwapCosmetics(true)
        if success then
            UpdateSwapStatus()
            WindUI:Notify({ Title = "Auto-Applied", Content = "Cosmetics: " .. msg, Duration = 3 })
        end
    end
end)

print("Visual Emote Changer V5 Loaded")
print("Emotes: 6 slots | Cosmetics: Visuals tab | Config: saves both")
