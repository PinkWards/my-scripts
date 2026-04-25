if _G.EmotesGUIRunning then return end
_G.EmotesGUIRunning = true

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")
local StarterGui = game:GetService("StarterGui")
local GuiService = game:GetService("GuiService")
local ContextActionService = game:GetService("ContextActionService")

local player = Players.LocalPlayer
local EMOTE_URL = "https://raw.githubusercontent.com/PinkWards/emote-sniper/refs/heads/main/EmoteSniper.json"
local ANIM_URL = "https://raw.githubusercontent.com/PinkWards/emote-sniper/refs/heads/main/AnimationSniper.json"

local State = {
    mode = "emote",
    currentPage = 1,
    itemsPerPage = 60,
    emotesData = {},
    animsData = {},
    filteredEmotes = {},
    filteredAnims = {},
    favEmotes = {},
    favAnims = {},
    isLoadingEmotes = false,
    isLoadingAnims = false,
    favSetVersion = 0,
    autoReapplyEnabled = false,
    favFileName = "FavoriteEmotes.json",
    favAnimFileName = "FavoriteAnimation.json",
    favLookupEmote = {},
    favLookupAnim = {},
    applyingAnim = false,
    config = {
        NotifyEnabled = true,
        AutoReapplyEnabled = false,
        CustomAnimSlots = {},
    }
}

getgenv().lastAnim = getgenv().lastAnim or nil
local ConfigPath = "PinkWards/Config.json"
local lastEmotePlay = 0

local function SaveConfig()
    if not isfolder then return end
    if not isfolder("PinkWards") then pcall(function() makefolder("PinkWards") end) end
    pcall(function() writefile(ConfigPath, HttpService:JSONEncode(State.config)) end)
end

local function LoadConfig()
    if isfile and isfile(ConfigPath) then
        local ok, data = pcall(function() return HttpService:JSONDecode(readfile(ConfigPath)) end)
        if ok and data then for k, v in pairs(data) do State.config[k] = v end end
    end
    State.autoReapplyEnabled = State.config.AutoReapplyEnabled or false
    if not State.config.CustomAnimSlots then State.config.CustomAnimSlots = {} end
end

local function notify(title, content, duration)
    if not State.config.NotifyEnabled then return end
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = title or "PinkWards",
            Text = content or "",
            Duration = duration or 4
        })
    end)
end

local function saveFile(name, data)
    if writefile then
        if not isfolder("PinkWards") then pcall(function() makefolder("PinkWards") end) end
        pcall(function() writefile("PinkWards/" .. name, HttpService:JSONEncode(data)) end)
    end
end

local function loadFile(name)
    local paths = {"PinkWards/" .. name, name}
    for _, path in ipairs(paths) do
        if readfile and isfile then
            local exists = false
            pcall(function() exists = isfile(path) end)
            if exists then
                local ok, res = pcall(function() return HttpService:JSONDecode(readfile(path)) end)
                if ok and res and type(res) == "table" then
                    if res.data and type(res.data) == "table" then return res.data end
                    if res.favorites and type(res.favorites) == "table" then return res.favorites end
                    return res
                end
            end
        end
    end
    return {}
end

local function saveLastAnim()
    if getgenv().lastAnim then saveFile("LastAnimation.json", getgenv().lastAnim) end
end

local function loadLastAnim()
    local data = loadFile("LastAnimation.json")
    if data and data.id then getgenv().lastAnim = data end
end

local function rebuildFavLookup()
    State.favLookupEmote = {}
    for _, v in ipairs(State.favEmotes) do State.favLookupEmote[tostring(v.id)] = true end
    State.favLookupAnim = {}
    for _, v in ipairs(State.favAnims) do State.favLookupAnim[tostring(v.id)] = true end
    State.favSetVersion = State.favSetVersion + 1
end

local function getBundled(id)
    for _, src in ipairs({State.filteredAnims, State.animsData, State.favAnims}) do
        for _, a in ipairs(src) do
            if tostring(a.id) == tostring(id) and a.bundledItems then return a.bundledItems end
        end
    end
    return nil
end

local function playEmote(name, id)
    if tick() - lastEmotePlay < 0.5 then return end
    lastEmotePlay = tick()
    
    local char = player.Character
    if not char then return end
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    local description = humanoid and humanoid:FindFirstChildOfClass("HumanoidDescription")
    if not humanoid or not description then return end

    if humanoid.RigType ~= Enum.HumanoidRigType.R6 then
        local succ, err = pcall(function()
            humanoid:PlayEmoteAndGetAnimTrackById(id)
        end)
        if not succ then
            pcall(function() description:AddEmote(name, id) end)
            pcall(function() humanoid:PlayEmoteAndGetAnimTrackById(id) end)
        end
    else
        notify("R6?", "You gotta be R15 dude", 3)
    end
end

local function freezeCharacter()
    local char = player.Character; if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid"); if hum then hum.PlatformStand = true end
    task.spawn(function() for _, part in ipairs(char:GetDescendants()) do if part:IsA("BasePart") and not part.Anchored then part.Anchored = true end end end)
end

local function unfreezeCharacter()
    local char = player.Character; if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid"); if hum then hum.PlatformStand = false end
    task.spawn(function() for _, part in ipairs(char:GetDescendants()) do if part:IsA("BasePart") and part.Anchored then part.Anchored = false end end end)
end

local function stopAllTracks()
    local char = player.Character; if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid"); if not hum then return end
    pcall(function() for _, track in ipairs(hum:GetPlayingAnimationTracks()) do track:Stop(0) end end)
end

local ANIM_SLOT_NAMES = {"idle", "walk", "run", "jump", "climb", "fall", "swim", "swimidle"}
local validSlotLookup = {}
for _, name in ipairs(ANIM_SLOT_NAMES) do validSlotLookup[name:lower()] = name end
local originalAnimData = nil

local function captureOriginalAnims()
    local char = player.Character; if not char then return end
    local animate = char:FindFirstChild("Animate"); if not animate then return end
    if originalAnimData then return end
    originalAnimData = {}
    for _, child in pairs(animate:GetChildren()) do
        local slotName = validSlotLookup[child.Name:lower()]
        if slotName then
            originalAnimData[slotName] = {}
            for _, anim in pairs(child:GetChildren()) do
                if anim:IsA("Animation") then
                    local weight = 1; local wObj = anim:FindFirstChild("Weight")
                    if wObj and wObj:IsA("NumberValue") then weight = wObj.Value end
                    table.insert(originalAnimData[slotName], {id = anim.AnimationId, name = anim.Name, weight = weight})
                end
            end
        end
    end
end

local function revertSlot(slotName)
    local char = player.Character; if not char then return false end
    local animate = char:FindFirstChild("Animate"); if not animate then return false end
    if not originalAnimData or not originalAnimData[slotName] then return false end
    local folder = nil
    for _, child in pairs(animate:GetChildren()) do if child.Name:lower() == slotName:lower() then folder = child; break end end
    if not folder then return false end
    local existingAnims = {}
    for _, child in pairs(folder:GetChildren()) do if child:IsA("Animation") then table.insert(existingAnims, child) end end
    local origAnims = originalAnimData[slotName]
    for i, aData in ipairs(origAnims) do
        if i <= #existingAnims then
            existingAnims[i].AnimationId = aData.id
            local wObj = existingAnims[i]:FindFirstChild("Weight")
            if wObj and wObj:IsA("NumberValue") then wObj.Value = aData.weight end
        end
    end
    for i = #origAnims + 1, #existingAnims do pcall(function() existingAnims[i]:Destroy() end) end
    return true
end

local function loadAssetObjects(assetId)
    local ok, objs = pcall(function() return game:GetObjects("rbxassetid://" .. tostring(assetId)) end)
    if ok and objs and #objs > 0 then return objs end
    ok, objs = pcall(function() local model = game:GetService("InsertService"):LoadAsset(tonumber(assetId)); return {model} end)
    if ok and objs and #objs > 0 then return objs end
    return nil
end

local function extractAnimDataFromObject(obj)
    local result = {}
    local function scanContainer(parent)
        for _, child in pairs(parent:GetChildren()) do
            local lowerName = child.Name:lower(); local slotName = validSlotLookup[lowerName]
            if slotName then
                if not result[slotName] then result[slotName] = {} end
                for _, anim in pairs(child:GetChildren()) do
                    if anim:IsA("Animation") and anim.AnimationId ~= "" then
                        local weight = 1; local wObj = anim:FindFirstChild("Weight")
                        if wObj and wObj:IsA("NumberValue") then weight = wObj.Value end
                        table.insert(result[slotName], {id = anim.AnimationId, name = anim.Name, weight = weight})
                    end
                end
            else
                if not child:IsA("Animation") and #child:GetChildren() > 0 then scanContainer(child) end
            end
        end
    end
    scanContainer(obj); return result
end

local function setSlotAnimations(animate, slotName, anims)
    local folder = nil
    for _, child in pairs(animate:GetChildren()) do if child.Name:lower() == slotName:lower() then folder = child; break end end
    if not folder then return 0 end
    local existingAnims = {}
    for _, child in pairs(folder:GetChildren()) do if child:IsA("Animation") then table.insert(existingAnims, child) end end
    local applied = 0
    for i, aData in ipairs(anims) do
        if i <= #existingAnims then
            existingAnims[i].AnimationId = aData.id
            local wObj = existingAnims[i]:FindFirstChild("Weight")
            if wObj and wObj:IsA("NumberValue") then wObj.Value = aData.weight
            elseif aData.weight ~= 1 then local w = Instance.new("NumberValue"); w.Name = "Weight"; w.Value = aData.weight; w.Parent = existingAnims[i] end
        else
            local newAnim = Instance.new("Animation"); newAnim.Name = aData.name; newAnim.AnimationId = aData.id
            if aData.weight ~= 1 then local w = Instance.new("NumberValue"); w.Name = "Weight"; w.Value = aData.weight; w.Parent = newAnim end
            newAnim.Parent = folder
        end
        applied = applied + 1
    end
    return applied
end

local function applySlotWithFreeze(animate, slotName, anims)
    local char = player.Character; if not char then return 0 end
    local hum = char:FindFirstChildOfClass("Humanoid"); if not hum then return 0 end
    freezeCharacter(); wait(0.1); stopAllTracks(); local applied = setSlotAnimations(animate, slotName, anims)
    hum:ChangeState(Enum.HumanoidStateType.Freefall); wait(0.1); unfreezeCharacter(); return applied
end

local function applyAllSlotsWithFreeze(animate, allAnimData)
    local char = player.Character; if not char then return 0 end
    local hum = char:FindFirstChildOfClass("Humanoid"); if not hum then return 0 end
    freezeCharacter(); wait(0.1); stopAllTracks()
    local totalApplied = 0
    for slotName, anims in pairs(allAnimData) do totalApplied = totalApplied + setSlotAnimations(animate, slotName, anims) end
    hum:ChangeState(Enum.HumanoidStateType.Freefall); wait(0.1); unfreezeCharacter(); return totalApplied
end

local function applyAnim(data)
    if not data then return end; if State.applyingAnim then return end
    State.applyingAnim = true
    task.spawn(function()
        local char = player.Character; if not char then State.applyingAnim = false; return end
        local hum = char:FindFirstChild("Humanoid"); local animate = char:FindFirstChild("Animate")
        if not animate or not hum then State.applyingAnim = false; return end
        captureOriginalAnims(); local bundled = data.bundledItems or getBundled(data.id)
        if not bundled then State.applyingAnim = false; return end
        getgenv().lastAnim = {id = data.id, name = data.name, bundledItems = bundled}; saveLastAnim()
        notify("Animation", "Loading: " .. tostring(data.name or "Animation") .. "...", 2)
        local allAnimData = {}
        for key, assetIds in pairs(bundled) do
            for _, assetId in pairs(assetIds) do
                local objs = loadAssetObjects(assetId)
                if objs then
                    for _, obj in pairs(objs) do
                        local extracted = extractAnimDataFromObject(obj)
                        for slotName, anims in pairs(extracted) do if not allAnimData[slotName] or #allAnimData[slotName] == 0 then allAnimData[slotName] = anims end end
                        pcall(function() obj:Destroy() end)
                    end
                end
            end
        end
        local totalApplied = applyAllSlotsWithFreeze(animate, allAnimData)
        notify("Animation", "Applied: " .. tostring(data.name or "Animation") .. " (" .. totalApplied .. " slots)", 3)
        State.applyingAnim = false
    end)
end

local function applySlotFromBundle(slotName, bundleData, skipFreeze)
    if not bundleData then return false end
    local char = player.Character; if not char then return false end
    local animate = char:FindFirstChild("Animate"); local hum = char:FindFirstChild("Humanoid")
    if not animate or not hum then return false end
    captureOriginalAnims(); local bundled = bundleData.bundledItems or getBundled(bundleData.id)
    if not bundled then return false end
    local targetAnims = nil
    for key, assetIds in pairs(bundled) do
        for _, assetId in pairs(assetIds) do
            local objs = loadAssetObjects(assetId)
            if objs then
                for _, obj in pairs(objs) do
                    local extracted = extractAnimDataFromObject(obj)
                    for sn, anims in pairs(extracted) do if sn:lower() == slotName:lower() then if not targetAnims or #targetAnims == 0 then targetAnims = anims end end end
                    pcall(function() obj:Destroy() end)
                end
            end
        end
    end
    if not targetAnims or #targetAnims == 0 then return false end
    local applied = skipFreeze and setSlotAnimations(animate, slotName, targetAnims) or applySlotWithFreeze(animate, slotName, targetAnims)
    if applied > 0 then State.config.CustomAnimSlots[slotName] = {id = bundleData.id, name = bundleData.name}; SaveConfig(); return true end
    return false
end

local function applyAllCustomSlots()
    if not State.config.CustomAnimSlots or not next(State.config.CustomAnimSlots) then notify("Custom Anim", "No custom slots configured", 3); return end
    if State.applyingAnim then notify("Custom Anim", "Already applying, please wait...", 3); return end
    State.applyingAnim = true
    task.spawn(function()
        local char = player.Character; if not char then State.applyingAnim = false; return end
        local animate = char:FindFirstChild("Animate"); local hum = char:FindFirstChild("Humanoid")
        if not animate or not hum then State.applyingAnim = false; return end
        captureOriginalAnims(); notify("Custom Anim", "Applying all custom slots...", 2); local allAnimData = {}
        for slotName, info in pairs(State.config.CustomAnimSlots) do
            if type(info) == "table" and info.id then
                local bundled = getBundled(info.id)
                if not bundled then for _, a in ipairs(State.animsData) do if tostring(a.id) == tostring(info.id) and a.bundledItems then bundled = a.bundledItems; break end end end
                if bundled then
                    for key, assetIds in pairs(bundled) do
                        for _, assetId in pairs(assetIds) do
                            local objs = loadAssetObjects(assetId)
                            if objs then
                                for _, obj in pairs(objs) do
                                    local extracted = extractAnimDataFromObject(obj)
                                    for sn, anims in pairs(extracted) do if sn:lower() == slotName:lower() then if not allAnimData[sn] or #allAnimData[sn] == 0 then allAnimData[sn] = anims end end end
                                    pcall(function() obj:Destroy() end)
                                end
                            end
                        end
                    end
                end
            end
        end
        local totalApplied = applyAllSlotsWithFreeze(animate, allAnimData); local slotCount = 0; for _ in pairs(State.config.CustomAnimSlots) do slotCount = slotCount + 1 end
        notify("Custom Anim", "Applied " .. slotCount .. " slots (" .. totalApplied .. " anims)", 3); State.applyingAnim = false
    end)
end

local function reapplyCustomSlots()
    if not State.config.CustomAnimSlots or not next(State.config.CustomAnimSlots) then return end
    local char = player.Character; if not char then return end
    local animate = char:FindFirstChild("Animate"); local hum = char:FindFirstChild("Humanoid"); if not animate or not hum then return end
    originalAnimData = nil; captureOriginalAnims(); local allAnimData = {}
    for slotName, info in pairs(State.config.CustomAnimSlots) do
        if type(info) == "table" and info.id then
            local bundled = getBundled(info.id)
            if not bundled then for _, a in ipairs(State.animsData) do if tostring(a.id) == tostring(info.id) and a.bundledItems then bundled = a.bundledItems; break end end end
            if bundled then
                for key, assetIds in pairs(bundled) do
                    for _, assetId in pairs(assetIds) do
                        local objs = loadAssetObjects(assetId)
                        if objs then
                            for _, obj in pairs(objs) do
                                local extracted = extractAnimDataFromObject(obj)
                                for sn, anims in pairs(extracted) do if sn:lower() == slotName:lower() then if not allAnimData[sn] or #allAnimData[sn] == 0 then allAnimData[sn] = anims end end end
                                pcall(function() obj:Destroy() end)
                            end
                        end
                    end
                end
            end
        end
    end
    if next(allAnimData) then applyAllSlotsWithFreeze(animate, allAnimData) end
end

local function revertSlotWithFreeze(slotName)
    local char = player.Character; if not char then return false end; local hum = char:FindFirstChildOfClass("Humanoid"); if not hum then return false end
    freezeCharacter(); wait(0.1); stopAllTracks(); local reverted = revertSlot(slotName); hum:ChangeState(Enum.HumanoidStateType.Freefall); wait(0.1); unfreezeCharacter(); return reverted
end

local function revertAllSlotsWithFreeze()
    local char = player.Character; if not char then return false end; local hum = char:FindFirstChildOfClass("Humanoid"); if not hum then return false end
    freezeCharacter(); wait(0.1); stopAllTracks(); local anyReverted = false
    for _, slotName in ipairs(ANIM_SLOT_NAMES) do if revertSlot(slotName) then anyReverted = true end end
    hum:ChangeState(Enum.HumanoidStateType.Freefall); wait(0.1); unfreezeCharacter(); return anyReverted
end

function toggleFav(id, name, bundled)
    local list = State.mode == "animation" and State.favAnims or State.favEmotes
    local found, idx = false, 0
    for i, v in ipairs(list) do if tostring(v.id) == tostring(id) then found, idx = true, i; break end end
    if found then table.remove(list, idx); notify("Favorites", "Removed: " .. name, 3)
    else
        local entry = {id = id, name = name}
        if State.mode == "animation" then entry.bundledItems = bundled or getBundled(id) end
        table.insert(list, entry); notify("Favorites", "Added: " .. name, 3)
    end
    saveFile(State.mode == "animation" and State.favAnimFileName or State.favFileName, list)
    rebuildFavLookup()
end

local function searchItems(term)
    term = term:lower()
    local source = State.mode == "animation" and State.animsData or State.emotesData
    if term == "" then
        if State.mode == "animation" then State.filteredAnims = State.animsData else State.filteredEmotes = State.emotesData end
    else
        local result = {}; local isIdSearch = term:match("^%d+$")
        if isIdSearch then for i = 1, #source do if tostring(source[i].id) == term then result[#result + 1] = source[i]; break end end
        else for i = 1, #source do if source[i].name:lower():find(term, 1, true) then result[#result + 1] = source[i] end end end
        if State.mode == "animation" then State.filteredAnims = result else State.filteredEmotes = result end
    end
    State.currentPage = 1
end

local function fetchEmotes()
    if State.isLoadingEmotes then return end; State.isLoadingEmotes = true
    local ok, result = pcall(function() return HttpService:JSONDecode(game:HttpGet(EMOTE_URL)) end)
    if ok and result then
        local rawList = result.data or result; local data = {}
        for i = 1, #rawList do local item = rawList[i]; local id = tonumber(item.id); if id and id > 0 then data[#data + 1] = {id = id, name = item.name or ("Emote_" .. id)} end end
        State.emotesData = data; State.filteredEmotes = data
    end; State.isLoadingEmotes = false
end

local function fetchAnims()
    if State.isLoadingAnims then return end; State.isLoadingAnims = true
    local ok, result = pcall(function() return HttpService:JSONDecode(game:HttpGet(ANIM_URL)) end)
    if ok and result then
        local rawList = result.data or result; local data = {}
        for i = 1, #rawList do local item = rawList[i]; local id = tonumber(item.id); if id and id > 0 then data[#data + 1] = {id = id, name = item.name or ("Anim_" .. id), bundledItems = item.bundledItems} end end
        State.animsData = data; State.filteredAnims = data
    end; State.isLoadingAnims = false
end

-- ============ NEW GUI SETUP ============ --
local FavoriteOff = "rbxassetid://10651060677"
local FavoriteOn = "rbxassetid://10651061109"

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "Emotes"; ScreenGui.DisplayOrder = 2; ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling; ScreenGui.ResetOnSpawn = false; ScreenGui.Enabled = false

local hiddenUI = gethui or get_hidden_gui
if hiddenUI then ScreenGui.Parent = hiddenUI()
else pcall(function() syn.protect_gui(ScreenGui) end); ScreenGui.Parent = CoreGui end

local BackFrame = Instance.new("Frame")
BackFrame.Size = UDim2.new(0.55, 0, 0.7, 0)
BackFrame.AnchorPoint = Vector2.new(0.5, 0.5)
BackFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
BackFrame.BackgroundTransparency = 1
BackFrame.BorderSizePixel = 0
BackFrame.Parent = ScreenGui

local Corner = Instance.new("UICorner")

local Frame = Instance.new("ScrollingFrame")
Frame.Size = UDim2.new(1, 0, 0.85, 0)
Frame.CanvasSize = UDim2.new(0, 0, 0, 0)
Frame.AutomaticCanvasSize = Enum.AutomaticSize.Y
Frame.ScrollingDirection = Enum.ScrollingDirection.Y
Frame.AnchorPoint = Vector2.new(0.5, 0)
Frame.Position = UDim2.new(0.5, 0, 0, 0)
Frame.BackgroundTransparency = 1
Frame.ScrollBarThickness = 4
Frame.BorderSizePixel = 0
Frame.Parent = BackFrame

local FramePadding = Instance.new("UIPadding", Frame)
FramePadding.PaddingLeft = UDim.new(0, 5)
FramePadding.PaddingRight = UDim.new(0, 8)
FramePadding.PaddingTop = UDim.new(0, 5)

local Grid = Instance.new("UIGridLayout")
Grid.CellSize = UDim2.new(0, 65, 0, 65)
Grid.CellPadding = UDim2.new(0, 5, 0, 5)
Grid.SortOrder = Enum.SortOrder.LayoutOrder
Grid.Parent = Frame

local PageFrame = Instance.new("Frame")
PageFrame.BackgroundTransparency = 1
PageFrame.Size = UDim2.new(1, 0, 0.06, 0)
PageFrame.Position = UDim2.new(0, 0, 0.87, 0)
PageFrame.BorderSizePixel = 0
PageFrame.Parent = BackFrame

local PageLeft = Instance.new("TextButton")
PageLeft.BorderSizePixel = 0; PageLeft.AnchorPoint = Vector2.new(0, 0.5); PageLeft.Position = UDim2.new(0.3, 0, 0.5, 0)
PageLeft.Size = UDim2.new(0.1, 0, 0.9, 0); PageLeft.TextScaled = true; PageLeft.TextColor3 = Color3.new(1, 1, 1)
PageLeft.BackgroundColor3 = Color3.new(0, 0, 0); PageLeft.BackgroundTransparency = 0.3; PageLeft.Text = "<"
Corner:Clone().Parent = PageLeft; PageLeft.Parent = PageFrame

local PageLabel = Instance.new("TextLabel")
PageLabel.BackgroundTransparency = 1; PageLabel.AnchorPoint = Vector2.new(0.5, 0.5); PageLabel.Position = UDim2.new(0.5, 0, 0.5, 0)
PageLabel.Size = UDim2.new(0.2, 0, 1, 0); PageLabel.TextScaled = true; PageLabel.TextColor3 = Color3.new(1, 1, 1)
PageLabel.Text = "1 / 1"; PageLabel.Parent = PageFrame

local PageRight = Instance.new("TextButton")
PageRight.BorderSizePixel = 0; PageRight.AnchorPoint = Vector2.new(1, 0.5); PageRight.Position = UDim2.new(0.7, 0, 0.5, 0)
PageRight.Size = UDim2.new(0.1, 0, 0.9, 0); PageRight.TextScaled = true; PageRight.TextColor3 = Color3.new(1, 1, 1)
PageRight.BackgroundColor3 = Color3.new(0, 0, 0); PageRight.BackgroundTransparency = 0.3; PageRight.Text = ">"
Corner:Clone().Parent = PageRight; PageRight.Parent = PageFrame

local EmoteName = Instance.new("TextLabel")
EmoteName.TextScaled = true
EmoteName.AnchorPoint = Vector2.new(0.5, 0.5)
EmoteName.Position = UDim2.new(0.5, 0, 0.96, 0)
EmoteName.Size = UDim2.new(0.6, 0, 0.06, 0)
EmoteName.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
EmoteName.TextColor3 = Color3.new(1, 1, 1)
EmoteName.BorderSizePixel = 0
EmoteName.Text = "Select an Emote"
EmoteName.Parent = BackFrame
Corner:Clone().Parent = EmoteName

local TopBar = Instance.new("Frame")
TopBar.BackgroundTransparency = 1; TopBar.Size = UDim2.new(1, 0, 0.06, 0)
TopBar.Position = UDim2.new(0, 0, -0.08, 0)
TopBar.BorderSizePixel = 0; TopBar.Parent = BackFrame

local CloseButton = Instance.new("TextButton")
CloseButton.BorderSizePixel = 0; CloseButton.AnchorPoint = Vector2.new(0, 0.5); CloseButton.Position = UDim2.new(0, 0, 0.5, 0)
CloseButton.Size = UDim2.new(0.12, 0, 0.9, 0); CloseButton.TextScaled = true; CloseButton.TextColor3 = Color3.new(1, 1, 1)
CloseButton.BackgroundColor3 = Color3.new(0, 0, 0); CloseButton.BackgroundTransparency = 0.3; CloseButton.Text = "Close"
Corner:Clone().Parent = CloseButton; CloseButton.Parent = TopBar

local SearchBar = Instance.new("TextBox")
SearchBar.BorderSizePixel = 0; SearchBar.AnchorPoint = Vector2.new(0, 0.5); SearchBar.Position = UDim2.new(0.14, 0, 0.5, 0)
SearchBar.Size = UDim2.new(0.36, 0, 0.9, 0); SearchBar.TextScaled = true; SearchBar.PlaceholderText = "Search"
SearchBar.TextColor3 = Color3.new(1, 1, 1); SearchBar.BackgroundColor3 = Color3.new(0, 0, 0); SearchBar.BackgroundTransparency = 0.3
Corner:Clone().Parent = SearchBar; SearchBar.Parent = TopBar

local ModeButton = Instance.new("TextButton")
ModeButton.BorderSizePixel = 0; ModeButton.AnchorPoint = Vector2.new(0, 0.5); ModeButton.Position = UDim2.new(0.52, 0, 0.5, 0)
ModeButton.Size = UDim2.new(0.1, 0, 0.9, 0); ModeButton.TextScaled = true; ModeButton.TextColor3 = Color3.new(1, 1, 1)
ModeButton.BackgroundColor3 = Color3.new(0, 0, 0); ModeButton.BackgroundTransparency = 0.3; ModeButton.Text = "EMO"
Corner:Clone().Parent = ModeButton; ModeButton.Parent = TopBar

local AutoButton = Instance.new("TextButton")
AutoButton.BorderSizePixel = 0; AutoButton.AnchorPoint = Vector2.new(0, 0.5); AutoButton.Position = UDim2.new(0.64, 0, 0.5, 0)
AutoButton.Size = UDim2.new(0.1, 0, 0.9, 0); AutoButton.TextScaled = true; AutoButton.TextColor3 = Color3.new(1, 1, 1)
AutoButton.BackgroundColor3 = Color3.new(0, 0, 0); AutoButton.BackgroundTransparency = 0.3; AutoButton.Text = "RE"
Corner:Clone().Parent = AutoButton; AutoButton.Parent = TopBar

local CustomAnimBtn = Instance.new("TextButton")
CustomAnimBtn.BorderSizePixel = 0; CustomAnimBtn.AnchorPoint = Vector2.new(0, 0.5); CustomAnimBtn.Position = UDim2.new(0.76, 0, 0.5, 0)
CustomAnimBtn.Size = UDim2.new(0.1, 0, 0.9, 0); CustomAnimBtn.TextScaled = true; CustomAnimBtn.TextColor3 = Color3.new(1, 1, 1)
CustomAnimBtn.BackgroundColor3 = Color3.new(0, 0, 0); CustomAnimBtn.BackgroundTransparency = 0.3; CustomAnimBtn.Text = "CUS"
Corner:Clone().Parent = CustomAnimBtn; CustomAnimBtn.Parent = TopBar

local SortButton = Instance.new("TextButton")
SortButton.BorderSizePixel = 0; SortButton.AnchorPoint = Vector2.new(1, 0.5); SortButton.Position = UDim2.new(1, 0, 0.5, 0)
SortButton.Size = UDim2.new(0.12, 0, 0.9, 0); SortButton.TextScaled = true; SortButton.TextColor3 = Color3.new(1, 1, 1)
SortButton.BackgroundColor3 = Color3.new(0, 0, 0); SortButton.BackgroundTransparency = 0.3; SortButton.Text = "Sort"
Corner:Clone().Parent = SortButton; SortButton.Parent = TopBar

local SortFrame = Instance.new("Frame")
SortFrame.Visible = false; SortFrame.BorderSizePixel = 0; SortFrame.Position = UDim2.new(1, 5, -0.125, 0)
SortFrame.Size = UDim2.new(0.4, 0, 0, 0); SortFrame.AutomaticSize = Enum.AutomaticSize.Y; SortFrame.BackgroundTransparency = 1
Corner:Clone().Parent = SortFrame; SortFrame.Parent = BackFrame

local SortList = Instance.new("UIListLayout")
SortList.Padding = UDim.new(0.02, 0); SortList.HorizontalAlignment = Enum.HorizontalAlignment.Center
SortList.VerticalAlignment = Enum.VerticalAlignment.Top; SortList.SortOrder = Enum.SortOrder.LayoutOrder; SortList.Parent = SortFrame

local CurrentSort = "favfirst"
local function createsort(order, text, sort)
    local CreatedSort = Instance.new("TextButton"); CreatedSort.SizeConstraint = Enum.SizeConstraint.RelativeXX
    CreatedSort.Size = UDim2.new(1, 0, 0.3, 0); CreatedSort.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    CreatedSort.LayoutOrder = order; CreatedSort.TextColor3 = Color3.new(1, 1, 1); CreatedSort.Text = text
    CreatedSort.TextScaled = true; CreatedSort.BorderSizePixel = 0; Corner:Clone().Parent = CreatedSort; CreatedSort.Parent = SortFrame
    CreatedSort.MouseButton1Click:Connect(function() SortFrame.Visible = false; CurrentSort = sort; State.currentPage = 1; refreshGrid() end)
end

createsort(1, "Favorites First", "favfirst"); createsort(2, "A - Z", "az"); createsort(3, "Z - A", "za")

-- ============ GRID LOGIC ============ --
local function getTotalPages()
    local list = State.mode == "animation" and State.filteredAnims or State.filteredEmotes
    local favs = State.mode == "animation" and State.favAnims or State.favEmotes
    local totalItems = #list + #favs
    return math.max(1, math.ceil(totalItems / State.itemsPerPage))
end

function refreshGrid()
    for _, child in pairs(Frame:GetChildren()) do
        if child:IsA("ImageButton") or child:IsA("TextButton") or (child:IsA("Frame") and child.Name == "filler") then child:Destroy() end
    end

    local list = State.mode == "animation" and State.filteredAnims or State.filteredEmotes
    local favs = State.mode == "animation" and State.favAnims or State.favEmotes
    local favLookup = State.mode == "animation" and State.favLookupAnim or State.favLookupEmote
    local normalList = {}
    for i = 1, #list do if not favLookup[tostring(list[i].id)] then normalList[#normalList + 1] = list[i] end end

    if CurrentSort == "az" then
        table.sort(normalList, function(a, b) return a.name:lower() < b.name:lower() end)
        table.sort(favs, function(a, b) return a.name:lower() < b.name:lower() end)
    elseif CurrentSort == "za" then
        table.sort(normalList, function(a, b) return a.name:lower() > b.name:lower() end)
        table.sort(favs, function(a, b) return a.name:lower() > b.name:lower() end)
    end

    local combined = {}
    for _, v in ipairs(favs) do combined[#combined+1] = {data=v, isFav=true} end
    for _, v in ipairs(normalList) do combined[#combined+1] = {data=v, isFav=false} end

    local totalPages = getTotalPages()
    if State.currentPage > totalPages then State.currentPage = totalPages end
    if State.currentPage < 1 then State.currentPage = 1 end
    PageLabel.Text = State.currentPage .. " / " .. totalPages

    local startIdx = (State.currentPage - 1) * State.itemsPerPage + 1
    local endIdx = math.min(startIdx + State.itemsPerPage - 1, #combined)

    for i = startIdx, endIdx do
        local item = combined[i]
        if item then
            local btn = Instance.new("ImageButton")
            btn.Name = tostring(item.data.id); btn:SetAttribute("name", item.data.name)
            btn.BackgroundColor3 = Color3.fromRGB(0, 0, 0); btn.BackgroundTransparency = 0.5; btn.BorderSizePixel = 0
            btn.LayoutOrder = i; Instance.new("UICorner", btn)

            if State.mode == "animation" then btn.Image = "rbxthumb://type=BundleThumbnail&id=" .. item.data.id .. "&w=420&h=420"
            else btn.Image = "rbxthumb://type=Asset&id=" .. item.data.id .. "&w=150&h=150" end

            local Favorite = Instance.new("ImageButton"); Favorite.Name = "favorite"; Favorite.Image = item.isFav and FavoriteOn or FavoriteOff
            Favorite.AnchorPoint = Vector2.new(0.5, 0.5); Favorite.Size = UDim2.new(0.3, 0, 0.3, 0); Favorite.Position = UDim2.new(0.9, 0, 0.9, 0)
            Favorite.BorderSizePixel = 0; Favorite.BackgroundTransparency = 1; Favorite.Parent = btn

            Favorite.MouseButton1Click:Connect(function()
                toggleFav(item.data.id, item.data.name, item.data.bundledItems); refreshGrid()
            end)

            btn.MouseButton1Click:Connect(function()
                if State.mode == "animation" then applyAnim(item.data) else task.spawn(playEmote, item.data.name, item.data.id) end
                ScreenGui.Enabled = false
            end)

            btn.MouseEnter:Connect(function() EmoteName.Text = item.data.name end)
            btn.Parent = Frame
        end
    end

    for i = 1, 8 do
        local filler = Instance.new("Frame"); filler.Name = "filler"; filler.BackgroundTransparency = 1; filler.LayoutOrder = 2147483647
        filler.Parent = Frame
    end
end

PageLeft.MouseButton1Click:Connect(function()
    local totalPages = getTotalPages()
    if totalPages <= 1 then return end
    if State.currentPage > 1 then State.currentPage = State.currentPage - 1 else State.currentPage = totalPages end
    refreshGrid()
end)

PageRight.MouseButton1Click:Connect(function()
    local totalPages = getTotalPages()
    if totalPages <= 1 then return end
    if State.currentPage < totalPages then State.currentPage = State.currentPage + 1 else State.currentPage = 1 end
    refreshGrid()
end)

-- ============ CUSTOM ANIMATION EDITOR (MATCHING TRANSPARENT GUI) ============ --
local customFrame = nil
local function closeCustomAnimEditor()
    if customFrame then customFrame.Visible = false end
    BackFrame.Visible = true
end

local function openCustomAnimEditor()
    if customFrame and customFrame.Visible then closeCustomAnimEditor(); return end
    if #State.animsData == 0 then notify("Custom Anim", "Loading animations first...", 3); task.spawn(function() fetchAnims(); openCustomAnimEditor() end); return end

    BackFrame.Visible = false
    
    if not customFrame then
        customFrame = Instance.new("Frame", ScreenGui)
        customFrame.Name = "CustomAnimFrame"
        customFrame.BackgroundColor3 = Color3.new(0, 0, 0); customFrame.BackgroundTransparency = 0.2; customFrame.BorderSizePixel = 0
        customFrame.Size = UDim2.new(0.4, 0, 0.55, 0); customFrame.AnchorPoint = Vector2.new(0.5, 0.5); customFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
        customFrame.ClipsDescendants = true; customFrame.ZIndex = 50
        Instance.new("UICorner", customFrame).CornerRadius = UDim.new(0, 10)

        local titleBar = Instance.new("Frame", customFrame); titleBar.BackgroundTransparency = 1; titleBar.Size = UDim2.new(1, 0, 0, 35); titleBar.ZIndex = 51
        local titleLabel = Instance.new("TextLabel", titleBar); titleLabel.BackgroundTransparency = 1; titleLabel.Size = UDim2.new(0.8, 0, 1, 0); titleLabel.Position = UDim2.fromOffset(10, 0); titleLabel.Font = Enum.Font.GothamBold; titleLabel.Text = "Custom Animation Slots"; titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255); titleLabel.TextSize = 14; titleLabel.TextXAlignment = Enum.TextXAlignment.Left; titleLabel.ZIndex = 52
        local closeBtn = Instance.new("TextButton", titleBar); closeBtn.BackgroundTransparency = 1; closeBtn.Size = UDim2.fromOffset(35, 35); closeBtn.Position = UDim2.new(1, -35, 0, 0); closeBtn.Font = Enum.Font.GothamBold; closeBtn.Text = "X"; closeBtn.TextColor3 = Color3.fromRGB(200, 200, 200); closeBtn.TextSize = 16; closeBtn.ZIndex = 52; closeBtn.MouseButton1Click:Connect(closeCustomAnimEditor)

        local contentArea = Instance.new("Frame", customFrame); contentArea.BackgroundTransparency = 1; contentArea.Position = UDim2.fromOffset(0, 38); contentArea.Size = UDim2.new(1, 0, 1, -38); contentArea.ZIndex = 51; contentArea.ClipsDescendants = true
        local slotPage = Instance.new("Frame", contentArea); slotPage.Name = "SlotPage"; slotPage.BackgroundTransparency = 1; slotPage.Size = UDim2.fromScale(1, 1); slotPage.ZIndex = 52; slotPage.Visible = true
        local scrollFrame = Instance.new("ScrollingFrame", slotPage); scrollFrame.BackgroundTransparency = 1; scrollFrame.Position = UDim2.fromOffset(0, 0); scrollFrame.Size = UDim2.new(1, 0, 1, -44); scrollFrame.ScrollBarThickness = 4; scrollFrame.ScrollBarImageColor3 = Color3.fromRGB(100, 100, 100); scrollFrame.CanvasSize = UDim2.fromOffset(0, 0); scrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y; scrollFrame.BorderSizePixel = 0; scrollFrame.ZIndex = 53
        local ll = Instance.new("UIListLayout", scrollFrame); ll.Padding = UDim.new(0, 4); ll.SortOrder = Enum.SortOrder.LayoutOrder
        local padUI = Instance.new("UIPadding", scrollFrame); padUI.PaddingLeft = UDim.new(0, 8); padUI.PaddingRight = UDim.new(0, 8); padUI.PaddingTop = UDim.new(0, 4)

        local pickerPage = Instance.new("Frame", contentArea); pickerPage.Name = "PickerPage"; pickerPage.BackgroundTransparency = 1; pickerPage.Size = UDim2.fromScale(1, 1); pickerPage.ZIndex = 52; pickerPage.Visible = false
        local pickerTitle = Instance.new("TextLabel", pickerPage); pickerTitle.BackgroundTransparency = 1; pickerTitle.Size = UDim2.new(1, -60, 0, 28); pickerTitle.Position = UDim2.fromOffset(8, 2); pickerTitle.Font = Enum.Font.GothamBold; pickerTitle.Text = "Pick bundle for: idle"; pickerTitle.TextColor3 = Color3.fromRGB(255, 255, 255); pickerTitle.TextSize = 12; pickerTitle.TextXAlignment = Enum.TextXAlignment.Left; pickerTitle.ZIndex = 53
        local pickerBack = Instance.new("TextButton", pickerPage); pickerBack.BackgroundColor3 = Color3.new(0, 0, 0); pickerBack.BackgroundTransparency = 0.3; pickerBack.Size = UDim2.fromOffset(50, 24); pickerBack.Position = UDim2.new(1, -58, 0, 4); pickerBack.Font = Enum.Font.GothamBold; pickerBack.Text = "Back"; pickerBack.TextColor3 = Color3.fromRGB(220, 220, 220); pickerBack.TextSize = 11; pickerBack.BorderSizePixel = 0; pickerBack.ZIndex = 53; Instance.new("UICorner", pickerBack).CornerRadius = UDim.new(0, 4)
        local pickerSearch = Instance.new("TextBox", pickerPage); pickerSearch.BackgroundColor3 = Color3.new(0, 0, 0); pickerSearch.BackgroundTransparency = 0.3; pickerSearch.Position = UDim2.fromOffset(5, 32); pickerSearch.Size = UDim2.new(1, -10, 0, 26); pickerSearch.Font = Enum.Font.Gotham; pickerSearch.PlaceholderText = "Search bundles..."; pickerSearch.PlaceholderColor3 = Color3.fromRGB(100, 100, 100); pickerSearch.Text = ""; pickerSearch.TextColor3 = Color3.fromRGB(255, 255, 255); pickerSearch.TextSize = 12; pickerSearch.ClearTextOnFocus = false; pickerSearch.BorderSizePixel = 0; pickerSearch.ZIndex = 53; Instance.new("UICorner", pickerSearch).CornerRadius = UDim.new(0, 4)
        local pickerScroll = Instance.new("ScrollingFrame", pickerPage); pickerScroll.BackgroundTransparency = 1; pickerScroll.Position = UDim2.fromOffset(0, 62); pickerScroll.Size = UDim2.new(1, 0, 1, -62); pickerScroll.ScrollBarThickness = 4; pickerScroll.ScrollBarImageColor3 = Color3.fromRGB(100, 100, 100); pickerScroll.CanvasSize = UDim2.fromOffset(0, 0); pickerScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y; pickerScroll.BorderSizePixel = 0; pickerScroll.ZIndex = 53
        local pll = Instance.new("UIListLayout", pickerScroll); pll.Padding = UDim.new(0, 2); pll.SortOrder = Enum.SortOrder.LayoutOrder

        local currentPickerSlot = ""; local pickerApplying = false
        pickerBack.MouseButton1Click:Connect(function() pickerPage.Visible = false; slotPage.Visible = true end)

        local function populatePickerList(filterTerm)
            for _, child in pairs(pickerScroll:GetChildren()) do if child:IsA("TextButton") or child:IsA("TextLabel") then child:Destroy() end end
            filterTerm = (filterTerm or ""):lower()
            local matches = {}
            for i = 1, #State.animsData do
                if #matches >= 50 then break end
                local item = State.animsData[i]
                if filterTerm == "" or item.name:lower():find(filterTerm, 1, true) or tostring(item.id) == filterTerm then matches[#matches + 1] = item end
            end
            for _, item in ipairs(matches) do
                local btn = Instance.new("TextButton"); btn.BackgroundColor3 = Color3.new(0, 0, 0); btn.BackgroundTransparency = 0.4; btn.Size = UDim2.new(1, -4, 0, 30); btn.Font = Enum.Font.Gotham; btn.Text = "  " .. item.name; btn.TextColor3 = Color3.fromRGB(220, 220, 220); btn.TextSize = 11; btn.TextXAlignment = Enum.TextXAlignment.Left; btn.BorderSizePixel = 0; btn.ZIndex = 54; btn.AutoButtonColor = true; Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 4); btn.Parent = pickerScroll
                btn.MouseButton1Click:Connect(function()
                    if pickerApplying then return end; pickerApplying = true
                    task.spawn(function()
                        local bundled = item.bundledItems or getBundled(item.id); if not bundled then pickerApplying = false; return end
                        local success = applySlotFromBundle(currentPickerSlot, {id = item.id, name = item.name, bundledItems = bundled})
                        if success then pickerPage.Visible = false; slotPage.Visible = true; local row = scrollFrame:FindFirstChild("Row_" .. currentPickerSlot); if row then local cl = row:FindFirstChild("CurrentLabel"); if cl then cl.Text = item.name end end end
                        pickerApplying = false
                    end)
                end)
            end
        end

        local pickerDebounce = nil
        pickerSearch:GetPropertyChangedSignal("Text"):Connect(function()
            if pickerDebounce then pcall(function() task.cancel(pickerDebounce) end) end
            pickerDebounce = task.delay(0.35, function() populatePickerList(pickerSearch.Text); pickerDebounce = nil end)
        end)

        for idx, slotName in ipairs(ANIM_SLOT_NAMES) do
            local row = Instance.new("Frame", scrollFrame); row.Name = "Row_" .. slotName; row.BackgroundColor3 = Color3.new(0, 0, 0); row.BackgroundTransparency = 0.4; row.Size = UDim2.new(1, 0, 0, 38); row.LayoutOrder = idx; row.BorderSizePixel = 0; row.ZIndex = 54; Instance.new("UICorner", row).CornerRadius = UDim.new(0, 6)
            local slotLabel = Instance.new("TextLabel", row); slotLabel.BackgroundTransparency = 1; slotLabel.Position = UDim2.fromOffset(8, 0); slotLabel.Size = UDim2.new(0.18, 0, 1, 0); slotLabel.Font = Enum.Font.GothamBold; slotLabel.Text = slotName; slotLabel.TextColor3 = Color3.fromRGB(220, 220, 220); slotLabel.TextSize = 12; slotLabel.TextXAlignment = Enum.TextXAlignment.Left; slotLabel.ZIndex = 55
            local currentLabel = Instance.new("TextLabel", row); currentLabel.Name = "CurrentLabel"; currentLabel.BackgroundTransparency = 1; currentLabel.Position = UDim2.new(0.20, 0, 0, 0); currentLabel.Size = UDim2.new(0.36, 0, 1, 0); currentLabel.Font = Enum.Font.Gotham; currentLabel.Text = "None"; currentLabel.TextColor3 = Color3.fromRGB(150, 150, 150); currentLabel.TextSize = 10; currentLabel.TextTruncate = Enum.TextTruncate.AtEnd; currentLabel.TextXAlignment = Enum.TextXAlignment.Left; currentLabel.ZIndex = 55
            local removeBtn = Instance.new("TextButton", row); removeBtn.Name = "RemoveBtn"; removeBtn.BackgroundColor3 = Color3.fromRGB(180, 50, 50); removeBtn.Position = UDim2.new(0.57, 0, 0.1, 0); removeBtn.Size = UDim2.new(0.18, -2, 0.8, 0); removeBtn.Font = Enum.Font.GothamBold; removeBtn.Text = "X"; removeBtn.TextColor3 = Color3.fromRGB(255, 255, 255); removeBtn.TextSize = 12; removeBtn.BorderSizePixel = 0; removeBtn.ZIndex = 55; Instance.new("UICorner", removeBtn).CornerRadius = UDim.new(0, 4)
            removeBtn.MouseButton1Click:Connect(function()
                if State.applyingAnim then return end; State.config.CustomAnimSlots[slotName] = nil; SaveConfig(); captureOriginalAnims(); revertSlotWithFreeze(slotName); currentLabel.Text = "None"
            end)
            local selectBtn = Instance.new("TextButton", row); selectBtn.BackgroundColor3 = Color3.fromRGB(0, 130, 220); selectBtn.Position = UDim2.new(0.76, 0, 0.1, 0); selectBtn.Size = UDim2.new(0.22, -4, 0.8, 0); selectBtn.Font = Enum.Font.GothamBold; selectBtn.Text = "Pick"; selectBtn.TextColor3 = Color3.fromRGB(255, 255, 255); selectBtn.TextSize = 11; selectBtn.BorderSizePixel = 0; selectBtn.ZIndex = 55; Instance.new("UICorner", selectBtn).CornerRadius = UDim.new(0, 4)
            selectBtn.MouseButton1Click:Connect(function()
                currentPickerSlot = slotName; pickerTitle.Text = "Pick bundle for: " .. slotName; pickerSearch.Text = ""; populatePickerList(""); slotPage.Visible = false; pickerPage.Visible = true
            end)
        end

        local bottomBar = Instance.new("Frame", slotPage); bottomBar.BackgroundTransparency = 1; bottomBar.BorderSizePixel = 0; bottomBar.Size = UDim2.new(1, 0, 0, 36); bottomBar.Position = UDim2.new(0, 0, 1, -38); bottomBar.ZIndex = 54
        local bottomLayout = Instance.new("UIListLayout", bottomBar); bottomLayout.FillDirection = Enum.FillDirection.Horizontal; bottomLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center; bottomLayout.VerticalAlignment = Enum.VerticalAlignment.Center; bottomLayout.Padding = UDim.new(0, 10)
        local applyAllBtn = Instance.new("TextButton", bottomBar); applyAllBtn.LayoutOrder = 1; applyAllBtn.BackgroundColor3 = Color3.fromRGB(40, 160, 60); applyAllBtn.Size = UDim2.new(0, 130, 0, 28); applyAllBtn.Font = Enum.Font.GothamBold; applyAllBtn.Text = "Apply All"; applyAllBtn.TextColor3 = Color3.fromRGB(255, 255, 255); applyAllBtn.TextSize = 12; applyAllBtn.BorderSizePixel = 0; applyAllBtn.ZIndex = 55; Instance.new("UICorner", applyAllBtn).CornerRadius = UDim.new(0, 6)
        applyAllBtn.MouseButton1Click:Connect(function() task.spawn(applyAllCustomSlots) end)
        local clearAllBtn = Instance.new("TextButton", bottomBar); clearAllBtn.LayoutOrder = 2; clearAllBtn.BackgroundColor3 = Color3.fromRGB(180, 50, 50); clearAllBtn.Size = UDim2.new(0, 130, 0, 28); clearAllBtn.Font = Enum.Font.GothamBold; clearAllBtn.Text = "Clear All"; clearAllBtn.TextColor3 = Color3.fromRGB(255, 255, 255); clearAllBtn.TextSize = 12; clearAllBtn.BorderSizePixel = 0; clearAllBtn.ZIndex = 55; Instance.new("UICorner", clearAllBtn).CornerRadius = UDim.new(0, 6)
        clearAllBtn.MouseButton1Click:Connect(function()
            State.config.CustomAnimSlots = {}; SaveConfig(); captureOriginalAnims(); revertAllSlotsWithFreeze()
            for _, child in pairs(scrollFrame:GetChildren()) do if child:IsA("Frame") then local cl = child:FindFirstChild("CurrentLabel"); if cl then cl.Text = "None" end end end
        end)
    end

    -- Update dynamic labels
    for _, slotName in ipairs(ANIM_SLOT_NAMES) do
        local row = customFrame:FindFirstChild("Row_" .. slotName, true)
        if row then
            local cl = row:FindFirstChild("CurrentLabel")
            if cl then
                local currentInfo = State.config.CustomAnimSlots[slotName]
                cl.Text = (type(currentInfo) == "table" and currentInfo.name) and currentInfo.name or "None"
            end
        end
    end

    customFrame.Visible = true
end

-- ============ GUI EVENTS ============ --
CloseButton.MouseButton1Click:Connect(function() ScreenGui.Enabled = false end)

SearchBar:GetPropertyChangedSignal("Text"):Connect(function()
    local text = SearchBar.Text
    if text ~= text:sub(1, 50) then SearchBar.Text = text:sub(1, 50); text = SearchBar.Text end
    searchItems(text); refreshGrid()
end)

ModeButton.MouseButton1Click:Connect(function()
    State.mode = State.mode == "emote" and "animation" or "emote"
    ModeButton.Text = State.mode == "animation" and "ANI" or "EMO"
    if State.mode == "animation" and #State.animsData == 0 then task.spawn(fetchAnims) end
    SearchBar.Text = ""; searchItems(""); refreshGrid()
end)

AutoButton.MouseButton1Click:Connect(function()
    State.autoReapplyEnabled = not State.autoReapplyEnabled; State.config.AutoReapplyEnabled = State.autoReapplyEnabled; SaveConfig()
    AutoButton.Text = State.autoReapplyEnabled and "RE: ON" or "RE"; notify("Auto-Reapply", State.autoReapplyEnabled and "ON" or "OFF", 3)
    if State.autoReapplyEnabled then
        task.spawn(function()
            local hasCustomSlots = State.config.CustomAnimSlots and next(State.config.CustomAnimSlots)
            if getgenv().lastAnim and not hasCustomSlots then applyAnim(getgenv().lastAnim)
            elseif hasCustomSlots then applyAllCustomSlots() end
        end)
    end
end)

CustomAnimBtn.MouseButton1Click:Connect(openCustomAnimEditor)
SortButton.MouseButton1Click:Connect(function() SortFrame.Visible = not SortFrame.Visible end)

local inputconnect
ScreenGui:GetPropertyChangedSignal("Enabled"):Connect(function()
    if ScreenGui.Enabled then
        if customFrame then customFrame.Visible = false end
        BackFrame.Visible = true
        EmoteName.Text = "Select an Emote"
        SortFrame.Visible = false; GuiService:SetEmotesMenuOpen(false); refreshGrid()
        inputconnect = UserInputService.InputBegan:Connect(function(input, processed)
            if not processed and input.UserInputType == Enum.UserInputType.MouseButton1 then ScreenGui.Enabled = false end
        end)
    else
        if customFrame then customFrame.Visible = false; BackFrame.Visible = true end
        if inputconnect then inputconnect:Disconnect() end
    end
end)

local menuToggleDebounce = false
ContextActionService:BindCoreActionAtPriority("Emote Menu", function(name, state)
    if state == Enum.UserInputState.Begin then
        if menuToggleDebounce then return end
        menuToggleDebounce = true
        ScreenGui.Enabled = not ScreenGui.Enabled
        task.delay(0.2, function() menuToggleDebounce = false end)
    end
end, true, 2001, Enum.KeyCode.Comma)

-- ============ CHARACTER & DATA LOGIC ============ --
local function onCharacterAdded(char)
    local hum = char:WaitForChild("Humanoid", 15); if not hum then return end
    State.applyingAnim = false; originalAnimData = nil
    if State.autoReapplyEnabled then
        task.wait(1); captureOriginalAnims()
        local hasCustomSlots = State.config.CustomAnimSlots and next(State.config.CustomAnimSlots)
        if hasCustomSlots then reapplyCustomSlots()
        elseif getgenv().lastAnim and getgenv().lastAnim.id then applyAnim(getgenv().lastAnim) end
    end
    hum.Died:Connect(function() State.applyingAnim = false end)
end

task.spawn(function()
    LoadConfig(); loadLastAnim()
    local rawEmoteFavs = loadFile(State.favFileName); State.favEmotes = {}
    if type(rawEmoteFavs) == "table" then for _, v in ipairs(rawEmoteFavs) do if type(v) == "table" and v.id then State.favEmotes[#State.favEmotes + 1] = {id = v.id, name = v.name or ("Emote_" .. tostring(v.id))} end end end
    local rawAnimFavs = loadFile(State.favAnimFileName); State.favAnims = {}
    if type(rawAnimFavs) == "table" then for _, v in ipairs(rawAnimFavs) do if type(v) == "table" and v.id then State.favAnims[#State.favAnims + 1] = {id = v.id, name = v.name or ("Anim_" .. tostring(v.id)), bundledItems = v.bundledItems} end end end
    rebuildFavLookup(); fetchEmotes(); fetchAnims(); notify("PinkWards", "Emote Sniper loaded successfully. Press ',' to open.", 4)
end)

player.CharacterAdded:Connect(onCharacterAdded)
if player.Character then task.spawn(function() onCharacterAdded(player.Character) end) end
StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Chat, true)
GuiService.EmotesMenuOpenChanged:Connect(function(isopen) if isopen then ScreenGui.Enabled = false end end)
GuiService.MenuOpened:Connect(function() ScreenGui.Enabled = false end)
