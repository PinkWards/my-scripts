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
-- MULTI-CONFIG SYSTEM
-- ═══════════════════════════════════════════════════════════════

local allConfigs = {}
local currentConfigName = ""
local configDropdown = nil
local configButtons = {}

local function EnsureFolder()
    if not isfolder(SAVE_FOLDER) then
        makefolder(SAVE_FOLDER)
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
        writefile(CONFIGS_FILE, HttpService:JSONEncode(data))
    end)
    return success
end

local function LoadAllConfigs()
    if not isfile(CONFIGS_FILE) then
        return false
    end
    
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
    
    allConfigs[name] = {
        currentEmotes = {"", "", "", "", "", ""},
        selectEmotes = {"", "", "", "", "", ""},
        emoteOption = 1,
        randomOptionEnabled = true
    }
    currentConfigName = name
    SaveAllConfigs()
    return true, "Config created"
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
    if not allConfigs[name] then return false, "Config not found" end
    
    local config = allConfigs[name]
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
        currentEmotes = table.clone(original.currentEmotes),
        selectEmotes = table.clone(original.selectEmotes),
        emoteOption = original.emoteOption,
        randomOptionEnabled = original.randomOptionEnabled
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
