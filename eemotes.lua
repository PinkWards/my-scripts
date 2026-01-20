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

-- SET L KEY AS TOGGLE KEY FOR THE WINDOW
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
local UserInputService = game:GetService("UserInputService")
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

local currentEmoteInputs = {}
local selectEmoteInputs = {}
local EmoteChangerEmoteOption = nil
local allEmotes = {}
local emoteConnections = {}

local SAVE_FOLDER = "DaraHub"
local SAVE_FILE = SAVE_FOLDER .. "/EmoteConfig.json"

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
-- INDICATOR GUI
-- ═══════════════════════════════════════════════════════════════

local IndicatorGui = nil
local OptionButtons = {}
local indicatorVisible = true

local function UpdateIndicatorButtons()
    for i, button in pairs(OptionButtons) do
        if button and button.Parent then
            button.BackgroundColor3 = (i == emoteOption) and Color3.fromRGB(50, 180, 100) or Color3.fromRGB(45, 45, 55)
        end
    end
end

local function CreateIndicatorGUI()
    if IndicatorGui then
        IndicatorGui:Destroy()
    end
    
    IndicatorGui = Instance.new("ScreenGui")
    IndicatorGui.Name = "EmoteOptionIndicator"
    IndicatorGui.ResetOnSpawn = false
    
    pcall(function()
        IndicatorGui.Parent = game:GetService("CoreGui")
    end)
    if not IndicatorGui.Parent then
        IndicatorGui.Parent = player:WaitForChild("PlayerGui")
    end
    
    local Container = Instance.new("Frame")
    Container.Name = "Container"
    Container.Size = UDim2.new(0, 160, 0, 70)
    Container.Position = UDim2.new(0, 20, 0.85, 0)
    Container.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
    Container.BackgroundTransparency = 0.1
    Container.BorderSizePixel = 0
    Container.Active = true
    Container.Draggable = true
    Container.Parent = IndicatorGui
    
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 10)
    corner.Parent = Container
    
    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(80, 80, 90)
    stroke.Parent = Container
    
    local Title = Instance.new("TextLabel")
    Title.Size = UDim2.new(1, 0, 0, 22)
    Title.Position = UDim2.new(0, 0, 0, 5)
    Title.BackgroundTransparency = 1
    Title.Text = "🎭 Emote Option"
    Title.TextColor3 = Color3.fromRGB(200, 200, 210)
    Title.TextSize = 12
    Title.Font = Enum.Font.GothamBold
    Title.Parent = Container
    
    local ButtonsFrame = Instance.new("Frame")
    ButtonsFrame.Size = UDim2.new(1, -20, 0, 32)
    ButtonsFrame.Position = UDim2.new(0, 10, 0, 30)
    ButtonsFrame.BackgroundTransparency = 1
    ButtonsFrame.Parent = Container
    
    for i = 1, 3 do
        local Button = Instance.new("TextButton")
        Button.Name = "Option" .. i
        Button.Size = UDim2.new(0, 42, 0, 32)
        Button.Position = UDim2.new(0, (i - 1) * 47, 0, 0)
        Button.BackgroundColor3 = (i == emoteOption) and Color3.fromRGB(50, 180, 100) or Color3.fromRGB(45, 45, 55)
        Button.BorderSizePixel = 0
        Button.Text = tostring(i)
        Button.TextColor3 = Color3.new(1, 1, 1)
        Button.TextSize = 16
        Button.Font = Enum.Font.GothamBold
        Button.AutoButtonColor = false
        Button.Parent = ButtonsFrame
        
        local btnCorner = Instance.new("UICorner")
        btnCorner.CornerRadius = UDim.new(0, 8)
        btnCorner.Parent = Button
        
        OptionButtons[i] = Button
        
        Button.MouseButton1Click:Connect(function()
            emoteOption = i
            if player.Character then
                player.Character:SetAttribute("EmoteNum", i)
            end
            UpdateIndicatorButtons()
        end)
    end
    
    local Hint = Instance.new("TextLabel")
    Hint.Size = UDim2.new(1, 0, 0, 14)
    Hint.Position = UDim2.new(0, 0, 1, -16)
    Hint.BackgroundTransparency = 1
    Hint.Text = "Numpad 1-3 | L = Toggle"
    Hint.TextColor3 = Color3.fromRGB(120, 120, 130)
    Hint.TextSize = 9
    Hint.Font = Enum.Font.Gotham
    Hint.Parent = Container
end

local function ToggleIndicator()
    indicatorVisible = not indicatorVisible
    if IndicatorGui then
        IndicatorGui.Enabled = indicatorVisible
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
    
    UpdateIndicatorButtons()
    
    pcall(function()
        if EmoteChangerEmoteOption and EmoteChangerEmoteOption.Set then
            EmoteChangerEmoteOption:Set(tostring(num))
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
end

-- ═══════════════════════════════════════════════════════════════
-- CONFIG FUNCTIONS
-- ═══════════════════════════════════════════════════════════════

local function EnsureFolder()
    if not isfolder(SAVE_FOLDER) then
        makefolder(SAVE_FOLDER)
    end
end

local function SaveConfig()
    EnsureFolder()
    local config = {
        currentEmotes = currentEmotes,
        selectEmotes = selectEmotes,
        emoteOption = emoteOption
    }
    local success = pcall(function()
        writefile(SAVE_FILE, HttpService:JSONEncode(config))
    end)
    return success
end

local function LoadConfig()
    if not isfile(SAVE_FILE) then
        return false
    end
    
    local success, result = pcall(function()
        return HttpService:JSONDecode(readfile(SAVE_FILE))
    end)
    
    if success and result then
        for i = 1, 6 do
            currentEmotes[i] = (result.currentEmotes and result.currentEmotes[i]) or ""
            selectEmotes[i] = (result.selectEmotes and result.selectEmotes[i]) or ""
        end
        emoteOption = result.emoteOption or 1
        return true
    end
    return false
end

local function DeleteConfig()
    if isfile(SAVE_FILE) then
        delfile(SAVE_FILE)
        return true
    end
    return false
end

-- ═══════════════════════════════════════════════════════════════
-- KEYBINDS
-- ═══════════════════════════════════════════════════════════════

UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    
    if input.KeyCode == Enum.KeyCode.KeypadOne then
        SetEmoteOption(1)
    elseif input.KeyCode == Enum.KeyCode.KeypadTwo then
        SetEmoteOption(2)
    elseif input.KeyCode == Enum.KeyCode.KeypadThree then
        SetEmoteOption(3)
    elseif input.KeyCode == Enum.KeyCode.L then
        -- Toggle the indicator when L is pressed (Window toggle is handled by WindUI)
        ToggleIndicator()
    end
end)

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
    Desc = "Current = emote you own | Select = animation to play\nNumpad 1-3 = switch option | L = toggle GUI"
})
Tabs.EmoteChanger:Divider()

for i = 1, 6 do
    currentEmoteInputs[i] = Tabs.EmoteChanger:Input({
        Title = "Current Emote " .. i,
        Placeholder = "Enter emote name",
        Value = currentEmotes[i],
        Callback = function(v)
            currentEmotes[i] = v:gsub("%s+", "")
        end
    })
end

Tabs.EmoteChanger:Divider()

for i = 1, 6 do
    selectEmoteInputs[i] = Tabs.EmoteChanger:Input({
        Title = "Select Emote " .. i,
        Placeholder = "Enter emote name",
        Value = selectEmotes[i],
        Callback = function(v)
            selectEmotes[i] = v:gsub("%s+", "")
        end
    })
end

Tabs.EmoteChanger:Divider()
Tabs.EmoteChanger:Section({ Title = "Animation Option", TextSize = 16 })

EmoteChangerEmoteOption = Tabs.EmoteChanger:Input({
    Title = "Emote Option (1-3)",
    Placeholder = "1",
    Value = tostring(emoteOption),
    Callback = function(v)
        SetEmoteOption(tonumber(v) or 1)
    end
})

Tabs.EmoteChanger:Button({ Title = "Option 1", Icon = "hash", Callback = function() SetEmoteOption(1) end })
Tabs.EmoteChanger:Button({ Title = "Option 2", Icon = "hash", Callback = function() SetEmoteOption(2) end })
Tabs.EmoteChanger:Button({ Title = "Option 3", Icon = "hash", Callback = function() SetEmoteOption(3) end })

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

Tabs.EmoteList:Section({ Title = "📋 Emote List", TextSize = 20 })
Tabs.EmoteList:Paragraph({
    Title = "All Available Emotes",
    Desc = "Click any emote to copy its name to clipboard"
})
Tabs.EmoteList:Divider()

Tabs.EmoteList:Button({
    Title = "🔄 Refresh Emote List",
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

-- Load emotes
task.spawn(function()
    task.wait(1)
    ScanEmotes()
    
    Tabs.EmoteList:Paragraph({
        Title = "📊 Found " .. #allEmotes .. " emotes",
        Desc = "Click to copy name"
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
-- SETTINGS TAB
-- ═══════════════════════════════════════════════════════════════

Tabs.Settings:Section({ Title = "Configuration", TextSize = 20 })
Tabs.Settings:Divider()

Tabs.Settings:Button({
    Title = "Save Config",
    Icon = "save",
    Callback = function()
        local success = SaveConfig()
        WindUI:Notify({
            Title = "Config",
            Content = success and "Saved!" or "Failed!",
            Duration = 1
        })
    end
})

Tabs.Settings:Button({
    Title = "Load Config",
    Icon = "download",
    Callback = function()
        local success = LoadConfig()
        if success then
            for i = 1, 6 do
                pcall(function()
                    if currentEmoteInputs[i] then currentEmoteInputs[i]:Set(currentEmotes[i]) end
                    if selectEmoteInputs[i] then selectEmoteInputs[i]:Set(selectEmotes[i]) end
                end)
            end
            SetEmoteOption(emoteOption)
            ApplyEmotes()
            WindUI:Notify({ Title = "Config", Content = "Loaded!", Duration = 1 })
        else
            WindUI:Notify({ Title = "Config", Content = "Not found!", Duration = 1 })
        end
    end
})

Tabs.Settings:Button({
    Title = "Delete Config",
    Icon = "trash",
    Callback = function()
        local success = DeleteConfig()
        WindUI:Notify({
            Title = "Config",
            Content = success and "Deleted!" or "Not found!",
            Duration = 1
        })
    end
})

Tabs.Settings:Divider()

Tabs.Settings:Paragraph({
    Title = "Keybinds",
    Desc = "L = Toggle GUI\nNumpad 1 = Option 1\nNumpad 2 = Option 2\nNumpad 3 = Option 3"
})

-- You can also change the toggle key here if you want
Tabs.Settings:Keybind({
    Title = "Toggle GUI Key",
    Value = "L",
    Callback = function(key)
        Window:SetToggleKey(Enum.KeyCode[key])
    end
})

-- ═══════════════════════════════════════════════════════════════
-- INITIALIZE
-- ═══════════════════════════════════════════════════════════════

CreateIndicatorGUI()
SetupEmoteConnections()

task.spawn(function()
    task.wait(1)
    if LoadConfig() then
        for i = 1, 6 do
            pcall(function()
                if currentEmoteInputs[i] then currentEmoteInputs[i]:Set(currentEmotes[i]) end
                if selectEmoteInputs[i] then selectEmoteInputs[i]:Set(selectEmotes[i]) end
            end)
        end
        SetEmoteOption(emoteOption)
        task.wait(0.5)
        ApplyEmotes()
        WindUI:Notify({
            Title = "Emote Changer",
            Content = "Config auto-loaded!",
            Duration = 2
        })
    end
end)

print("✅ Visual Emote Changer Loaded!")
print("   L = Toggle GUI")
print("   Numpad 1-3 = Switch animation option")
