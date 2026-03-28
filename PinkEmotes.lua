if _G.EmotesGUIRunning then return end
_G.EmotesGUIRunning = true

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
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
    itemsPerPage = 8,
    totalPages = 1,
    emotesData = {},
    animsData = {},
    filteredEmotes = {},
    filteredAnims = {},
    favEmotes = {},
    favAnims = {},
    favEnabled = false,
    isLoadingEmotes = false,
    isLoadingAnims = false,
    currentEmoteTrack = nil,
    lastAction = 0,
    favSetVersion = 0,
    guiCreated = false,
    wheelCache = nil,
    lastWheelCheck = 0,
    autoReapplyEnabled = false,
    favFileName = "FavoriteEmotes.json",
    favAnimFileName = "FavoriteAnimation.json",
    favLookupEmote = {},
    favLookupAnim = {},
    normalListCache = nil,
    normalListCacheVersion = -1,
    normalListCacheMode = "",
    lastSearchTerm = "",
    lastDisplayPage = -1,
    lastDisplayMode = "",
    lastDisplayFavVer = -1,
    currentOperationToken = 0,
    hudEditorActive = false,
    favoriteIconId = "rbxassetid://97307461910825",
    globalClickConn = nil,
    currentPageItems = {},
    applyingAnim = false,
    config = {
        NotifyEnabled = true,
        HUDPositions = {},
        AutoReapplyEnabled = false,
        CustomAnimSlots = {},
    }
}

getgenv().lastAnim = getgenv().lastAnim or nil

local ConfigPath = "PinkWards/Config.json"

local function SaveConfig()
    if not isfolder then return end
    if not isfolder("PinkWards") then pcall(function() makefolder("PinkWards") end) end
    pcall(function() writefile(ConfigPath, HttpService:JSONEncode(State.config)) end)
end

local function LoadConfig()
    if isfile and isfile(ConfigPath) then
        local ok, data = pcall(function() return HttpService:JSONDecode(readfile(ConfigPath)) end)
        if ok and data then
            for k, v in pairs(data) do State.config[k] = v end
        end
    end
    State.autoReapplyEnabled = State.config.AutoReapplyEnabled or false
    if not State.config.CustomAnimSlots then State.config.CustomAnimSlots = {} end
end

local Themes = {}
local currentThemeName = "Default"
local DefaultTheme = {
    Background = {30, 30, 30},
    ImageColor = {255, 255, 255},
    IconColors = {
        Left = {180, 180, 180},
        Right = {180, 180, 180},
        Favorite = {255, 170, 50},
        Mode = {255, 255, 255},
        Auto = {255, 255, 255}
    },
}

local function LoadThemes() Themes = {Default = DefaultTheme} end

local function GetIconColor(key)
    local theme = Themes[currentThemeName]
    if theme and theme.IconColors and theme.IconColors[key] then
        local c = theme.IconColors[key]
        return Color3.fromRGB(c[1], c[2], c[3])
    end
    return Color3.fromRGB(255, 255, 255)
end

local function TableToColor(t)
    if not t then return Color3.fromRGB(255, 255, 255) end
    return Color3.fromRGB(t[1] or 255, t[2] or 255, t[3] or 255)
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

local function getChar()
    local c = player.Character
    return c, c and c:FindFirstChild("Humanoid")
end

local function getWheel()
    local t = tick()
    if State.wheelCache and State.wheelCache.Parent and t - State.lastWheelCheck < 1 then
        return State.wheelCache
    end
    State.lastWheelCheck = t
    local ok, w = pcall(function()
        return CoreGui.RobloxGui.EmotesMenu.Children.Main.EmotesWheel
    end)
    State.wheelCache = ok and w or nil
    return State.wheelCache
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
    State.normalListCacheVersion = -1
    State.favSetVersion = State.favSetVersion + 1
end

local function isInFav(id)
    local lookup = State.mode == "animation" and State.favLookupAnim or State.favLookupEmote
    return lookup[tostring(id)] == true
end

local function getBundled(id)
    for _, src in ipairs({State.filteredAnims, State.animsData, State.favAnims}) do
        for _, a in ipairs(src) do
            if tostring(a.id) == tostring(id) and a.bundledItems then return a.bundledItems end
        end
    end
    return nil
end

local function getNormalList()
    local list = State.mode == "animation" and State.filteredAnims or State.filteredEmotes
    local version = State.favSetVersion
    if State.normalListCache and State.normalListCacheVersion == version and State.normalListCacheMode == State.mode then
        return State.normalListCache
    end
    local result = {}
    local lookup = State.mode == "animation" and State.favLookupAnim or State.favLookupEmote
    for i = 1, #list do
        if not lookup[tostring(list[i].id)] then result[#result + 1] = list[i] end
    end
    State.normalListCache = result
    State.normalListCacheVersion = version
    State.normalListCacheMode = State.mode
    return result
end

local loadedTracks = {}
local currentLoadId = 0

local function cleanupAllTracks()
    for i = #loadedTracks, 1, -1 do
        pcall(function() loadedTracks[i]:Stop(0); loadedTracks[i]:Destroy() end)
    end
    loadedTracks = {}
    State.currentEmoteTrack = nil
end

local function forceResetAnimator()
    local _, hum = getChar()
    if not hum then return end
    pcall(function()
        local animator = hum:FindFirstChild("Animator")
        if animator then
            for _, track in pairs(animator:GetPlayingAnimationTracks()) do track:Stop(0); track:Destroy() end
        end
    end)
    pcall(function()
        hum:ChangeState(Enum.HumanoidStateType.GettingUp)
        task.wait(0.05)
        hum:ChangeState(Enum.HumanoidStateType.Running)
    end)
end

local function stopCurrentEmote()
    currentLoadId = currentLoadId + 1
    if State.currentEmoteTrack then
        pcall(function() State.currentEmoteTrack:Stop(0); State.currentEmoteTrack:Destroy() end)
        State.currentEmoteTrack = nil
    end
    for i = #loadedTracks, 1, -1 do
        local track = loadedTracks[i]
        local isPlaying = false
        pcall(function() isPlaying = track.IsPlaying end)
        if not isPlaying then
            pcall(function() track:Stop(0); track:Destroy() end)
            table.remove(loadedTracks, i)
        end
    end
end

local function playEmote(emoteId)
    local char, hum = getChar()
    if not hum then return false end
    stopCurrentEmote()
    currentLoadId = currentLoadId + 1
    local myLoadId = currentLoadId

    if #loadedTracks >= 25 then
        cleanupAllTracks()
        forceResetAnimator()
        task.wait(0.1)
        char, hum = getChar()
        if not hum then return false end
    end

    local animator = hum:FindFirstChild("Animator")
    if not animator then return false end

    pcall(function()
        for _, track in pairs(animator:GetPlayingAnimationTracks()) do
            if track.Priority == Enum.AnimationPriority.Action then track:Stop(0) end
        end
    end)

    local anim = Instance.new("Animation")
    anim.AnimationId = "rbxassetid://" .. emoteId
    local ok, track = pcall(function() return animator:LoadAnimation(anim) end)
    pcall(function() anim:Destroy() end)

    if myLoadId ~= currentLoadId then
        if ok and track then pcall(function() track:Stop(0); track:Destroy() end) end
        return false
    end
    if not ok or not track then forceResetAnimator(); return false end

    pcall(function() track.Priority = Enum.AnimationPriority.Action; track.Looped = true end)
    if myLoadId ~= currentLoadId then pcall(function() track:Stop(0); track:Destroy() end); return false end

    local playOk = pcall(function() track:Play(0.1) end)
    if not playOk then pcall(function() track:Stop(0); track:Destroy() end); forceResetAnimator(); return false end
    if myLoadId ~= currentLoadId then pcall(function() track:Stop(0); track:Destroy() end); return false end

    State.currentEmoteTrack = track
    table.insert(loadedTracks, track)
    track.Stopped:Connect(function()
        if State.currentEmoteTrack == track then State.currentEmoteTrack = nil end
    end)
    return true
end

-- ============ FREEZE / UNFREEZE (from working script) ============ --

local function freezeCharacter()
    local char = player.Character
    if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum then hum.PlatformStand = true end
    task.spawn(function()
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") and not part.Anchored then
                part.Anchored = true
            end
        end
    end)
end

local function unfreezeCharacter()
    local char = player.Character
    if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum then hum.PlatformStand = false end
    task.spawn(function()
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") and part.Anchored then
                part.Anchored = false
            end
        end
    end)
end

local function stopAllTracks()
    local char = player.Character
    if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return end
    pcall(function()
        for _, track in ipairs(hum:GetPlayingAnimationTracks()) do
            track:Stop(0)
        end
    end)
end

-- ============ ANIMATION APPLICATION SYSTEM ============ --

local ANIM_SLOT_NAMES = {"idle", "walk", "run", "jump", "climb", "fall", "swim", "swimidle"}

local validSlotLookup = {}
for _, name in ipairs(ANIM_SLOT_NAMES) do validSlotLookup[name:lower()] = name end

local originalAnimData = nil

local function captureOriginalAnims()
    local char = player.Character
    if not char then return end
    local animate = char:FindFirstChild("Animate")
    if not animate then return end
    if originalAnimData then return end

    originalAnimData = {}
    for _, child in pairs(animate:GetChildren()) do
        local slotName = validSlotLookup[child.Name:lower()]
        if slotName then
            originalAnimData[slotName] = {}
            for _, anim in pairs(child:GetChildren()) do
                if anim:IsA("Animation") then
                    local weight = 1
                    local wObj = anim:FindFirstChild("Weight")
                    if wObj and wObj:IsA("NumberValue") then weight = wObj.Value end
                    table.insert(originalAnimData[slotName], {
                        id = anim.AnimationId,
                        name = anim.Name,
                        weight = weight
                    })
                end
            end
        end
    end
end

local function revertSlot(slotName)
    local char = player.Character
    if not char then return false end
    local animate = char:FindFirstChild("Animate")
    if not animate then return false end
    if not originalAnimData or not originalAnimData[slotName] then return false end

    local folder = nil
    for _, child in pairs(animate:GetChildren()) do
        if child.Name:lower() == slotName:lower() then
            folder = child
            break
        end
    end
    if not folder then return false end

    local existingAnims = {}
    for _, child in pairs(folder:GetChildren()) do
        if child:IsA("Animation") then
            table.insert(existingAnims, child)
        end
    end

    local origAnims = originalAnimData[slotName]
    for i, aData in ipairs(origAnims) do
        if i <= #existingAnims then
            existingAnims[i].AnimationId = aData.id
            local wObj = existingAnims[i]:FindFirstChild("Weight")
            if wObj and wObj:IsA("NumberValue") then
                wObj.Value = aData.weight
            end
        end
    end

    for i = #origAnims + 1, #existingAnims do
        pcall(function() existingAnims[i]:Destroy() end)
    end

    return true
end

local function loadAssetObjects(assetId)
    local ok, objs = pcall(function()
        return game:GetObjects("rbxassetid://" .. tostring(assetId))
    end)
    if ok and objs and #objs > 0 then return objs end

    ok, objs = pcall(function()
        local model = game:GetService("InsertService"):LoadAsset(tonumber(assetId))
        return {model}
    end)
    if ok and objs and #objs > 0 then return objs end

    return nil
end

local function extractAnimDataFromObject(obj)
    local result = {}

    local function scanContainer(parent)
        for _, child in pairs(parent:GetChildren()) do
            local lowerName = child.Name:lower()
            local slotName = validSlotLookup[lowerName]

            if slotName then
                if not result[slotName] then result[slotName] = {} end
                for _, anim in pairs(child:GetChildren()) do
                    if anim:IsA("Animation") and anim.AnimationId ~= "" then
                        local weight = 1
                        local wObj = anim:FindFirstChild("Weight")
                        if wObj and wObj:IsA("NumberValue") then weight = wObj.Value end
                        table.insert(result[slotName], {
                            id = anim.AnimationId,
                            name = anim.Name,
                            weight = weight
                        })
                    end
                end
            else
                if not child:IsA("Animation") and #child:GetChildren() > 0 then
                    scanContainer(child)
                end
            end
        end
    end

    scanContainer(obj)
    return result
end

local function setSlotAnimations(animate, slotName, anims)
    local folder = nil
    for _, child in pairs(animate:GetChildren()) do
        if child.Name:lower() == slotName:lower() then
            folder = child
            break
        end
    end
    if not folder then return 0 end

    local existingAnims = {}
    for _, child in pairs(folder:GetChildren()) do
        if child:IsA("Animation") then
            table.insert(existingAnims, child)
        end
    end

    local applied = 0
    for i, aData in ipairs(anims) do
        if i <= #existingAnims then
            existingAnims[i].AnimationId = aData.id
            local wObj = existingAnims[i]:FindFirstChild("Weight")
            if wObj and wObj:IsA("NumberValue") then
                wObj.Value = aData.weight
            elseif aData.weight ~= 1 then
                local w = Instance.new("NumberValue")
                w.Name = "Weight"
                w.Value = aData.weight
                w.Parent = existingAnims[i]
            end
        else
            local newAnim = Instance.new("Animation")
            newAnim.Name = aData.name
            newAnim.AnimationId = aData.id
            if aData.weight ~= 1 then
                local w = Instance.new("NumberValue")
                w.Name = "Weight"
                w.Value = aData.weight
                w.Parent = newAnim
            end
            newAnim.Parent = folder
        end
        applied = applied + 1
    end

    return applied
end

-- This matches the working script's exact pattern
local function applySlotWithFreeze(animate, slotName, anims)
    local char = player.Character
    if not char then return 0 end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return 0 end

    freezeCharacter()
    wait(0.1)

    stopAllTracks()

    local applied = setSlotAnimations(animate, slotName, anims)

    hum:ChangeState(Enum.HumanoidStateType.Freefall)

    wait(0.1)
    unfreezeCharacter()

    return applied
end

local function applyAllSlotsWithFreeze(animate, allAnimData)
    local char = player.Character
    if not char then return 0 end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return 0 end

    freezeCharacter()
    wait(0.1)

    stopAllTracks()

    local totalApplied = 0
    for slotName, anims in pairs(allAnimData) do
        totalApplied = totalApplied + setSlotAnimations(animate, slotName, anims)
    end

    hum:ChangeState(Enum.HumanoidStateType.Freefall)

    wait(0.1)
    unfreezeCharacter()

    return totalApplied
end

local function applyAnim(data)
    if not data then return end
    if State.applyingAnim then return end
    State.applyingAnim = true

    task.spawn(function()
        local char = player.Character
        if not char then State.applyingAnim = false; return end
        local hum = char:FindFirstChild("Humanoid")
        local animate = char:FindFirstChild("Animate")
        if not animate or not hum then State.applyingAnim = false; return end

        captureOriginalAnims()

        local bundled = data.bundledItems or getBundled(data.id)
        if not bundled then State.applyingAnim = false; return end

        getgenv().lastAnim = {id = data.id, name = data.name, bundledItems = bundled}
        saveLastAnim()

        notify("Animation", "Loading: " .. tostring(data.name or "Animation") .. "...", 2)

        local allAnimData = {}

        for key, assetIds in pairs(bundled) do
            for _, assetId in pairs(assetIds) do
                local objs = loadAssetObjects(assetId)
                if objs then
                    for _, obj in pairs(objs) do
                        local extracted = extractAnimDataFromObject(obj)
                        for slotName, anims in pairs(extracted) do
                            if not allAnimData[slotName] or #allAnimData[slotName] == 0 then
                                allAnimData[slotName] = anims
                            end
                        end
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
    local char = player.Character
    if not char then return false end
    local animate = char:FindFirstChild("Animate")
    local hum = char:FindFirstChild("Humanoid")
    if not animate or not hum then return false end

    captureOriginalAnims()

    local bundled = bundleData.bundledItems or getBundled(bundleData.id)
    if not bundled then return false end

    local targetAnims = nil

    for key, assetIds in pairs(bundled) do
        for _, assetId in pairs(assetIds) do
            local objs = loadAssetObjects(assetId)
            if objs then
                for _, obj in pairs(objs) do
                    local extracted = extractAnimDataFromObject(obj)
                    for sn, anims in pairs(extracted) do
                        if sn:lower() == slotName:lower() then
                            if not targetAnims or #targetAnims == 0 then
                                targetAnims = anims
                            end
                        end
                    end
                    pcall(function() obj:Destroy() end)
                end
            end
        end
    end

    if not targetAnims or #targetAnims == 0 then return false end

    local applied
    if skipFreeze then
        applied = setSlotAnimations(animate, slotName, targetAnims)
    else
        applied = applySlotWithFreeze(animate, slotName, targetAnims)
    end

    if applied > 0 then
        State.config.CustomAnimSlots[slotName] = {id = bundleData.id, name = bundleData.name}
        SaveConfig()
        return true
    end

    return false
end

local function applyAllCustomSlots()
    if not State.config.CustomAnimSlots or not next(State.config.CustomAnimSlots) then
        notify("Custom Anim", "No custom slots configured", 3)
        return
    end
    if State.applyingAnim then
        notify("Custom Anim", "Already applying, please wait...", 3)
        return
    end
    State.applyingAnim = true

    task.spawn(function()
        local char = player.Character
        if not char then State.applyingAnim = false; return end
        local animate = char:FindFirstChild("Animate")
        local hum = char:FindFirstChild("Humanoid")
        if not animate or not hum then State.applyingAnim = false; return end

        captureOriginalAnims()

        notify("Custom Anim", "Applying all custom slots...", 2)

        local allAnimData = {}

        for slotName, info in pairs(State.config.CustomAnimSlots) do
            if type(info) == "table" and info.id then
                local bundled = getBundled(info.id)
                if not bundled then
                    for _, a in ipairs(State.animsData) do
                        if tostring(a.id) == tostring(info.id) and a.bundledItems then
                            bundled = a.bundledItems
                            break
                        end
                    end
                end

                if bundled then
                    for key, assetIds in pairs(bundled) do
                        for _, assetId in pairs(assetIds) do
                            local objs = loadAssetObjects(assetId)
                            if objs then
                                for _, obj in pairs(objs) do
                                    local extracted = extractAnimDataFromObject(obj)
                                    for sn, anims in pairs(extracted) do
                                        if sn:lower() == slotName:lower() then
                                            if not allAnimData[sn] or #allAnimData[sn] == 0 then
                                                allAnimData[sn] = anims
                                            end
                                        end
                                    end
                                    pcall(function() obj:Destroy() end)
                                end
                            end
                        end
                    end
                end
            end
        end

        local totalApplied = applyAllSlotsWithFreeze(animate, allAnimData)

        local slotCount = 0
        for _ in pairs(State.config.CustomAnimSlots) do slotCount = slotCount + 1 end

        notify("Custom Anim", "Applied " .. slotCount .. " slots (" .. totalApplied .. " anims)", 3)
        State.applyingAnim = false
    end)
end

local function reapplyCustomSlots()
    if not State.config.CustomAnimSlots or not next(State.config.CustomAnimSlots) then return end

    local char = player.Character
    if not char then return end
    local animate = char:FindFirstChild("Animate")
    local hum = char:FindFirstChild("Humanoid")
    if not animate or not hum then return end

    originalAnimData = nil
    captureOriginalAnims()

    local allAnimData = {}

    for slotName, info in pairs(State.config.CustomAnimSlots) do
        if type(info) == "table" and info.id then
            local bundled = getBundled(info.id)
            if not bundled then
                for _, a in ipairs(State.animsData) do
                    if tostring(a.id) == tostring(info.id) and a.bundledItems then
                        bundled = a.bundledItems
                        break
                    end
                end
            end

            if bundled then
                for key, assetIds in pairs(bundled) do
                    for _, assetId in pairs(assetIds) do
                        local objs = loadAssetObjects(assetId)
                        if objs then
                            for _, obj in pairs(objs) do
                                local extracted = extractAnimDataFromObject(obj)
                                for sn, anims in pairs(extracted) do
                                    if sn:lower() == slotName:lower() then
                                        if not allAnimData[sn] or #allAnimData[sn] == 0 then
                                            allAnimData[sn] = anims
                                        end
                                    end
                                end
                                pcall(function() obj:Destroy() end)
                            end
                        end
                    end
                end
            end
        end
    end

    if next(allAnimData) then
        applyAllSlotsWithFreeze(animate, allAnimData)
    end
end

local function revertSlotWithFreeze(slotName)
    local char = player.Character
    if not char then return false end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return false end

    freezeCharacter()
    wait(0.1)

    stopAllTracks()

    local reverted = revertSlot(slotName)

    hum:ChangeState(Enum.HumanoidStateType.Freefall)

    wait(0.1)
    unfreezeCharacter()

    return reverted
end

local function revertAllSlotsWithFreeze()
    local char = player.Character
    if not char then return false end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return false end

    freezeCharacter()
    wait(0.1)

    stopAllTracks()

    local anyReverted = false
    for _, slotName in ipairs(ANIM_SLOT_NAMES) do
        if revertSlot(slotName) then anyReverted = true end
    end

    hum:ChangeState(Enum.HumanoidStateType.Freefall)

    wait(0.1)
    unfreezeCharacter()

    return anyReverted
end

local function updateFavIcon(img, id, isFav)
    local star = img:FindFirstChild("FavStar")
    if isFav then
        if not star then
            star = Instance.new("ImageLabel")
            star.Name = "FavStar"
            star.Size = UDim2.new(0.25, 0, 0.25, 0)
            star.Position = UDim2.new(0.7, 0, 0, 0)
            star.BackgroundTransparency = 1
            star.ZIndex = img.ZIndex + 10
            star.Image = State.favoriteIconId
            star.ScaleType = Enum.ScaleType.Fit
            star.Parent = img
        end
        star.Visible = true
        star.ImageColor3 = GetIconColor("Favorite")
    elseif star then
        star.Visible = false
    end
end

local function getItemForIndex(index)
    if index < 1 or index > #State.currentPageItems then return nil end
    return State.currentPageItems[index]
end

local function handleSector(index)
    local now = tick()
    if now - State.lastAction < 0.2 then return end
    State.lastAction = now

    local item = getItemForIndex(index)
    if not item then return end

    if State.favEnabled then
        toggleFav(item.id, item.name, item.bundledItems)
    elseif State.mode == "animation" then
        applyAnim(item)
    else
        task.spawn(function() playEmote(item.id) end)
    end
end

function toggleFav(id, name, bundled)
    local list = State.mode == "animation" and State.favAnims or State.favEmotes
    local found, idx = false, 0
    for i, v in ipairs(list) do
        if tostring(v.id) == tostring(id) then found, idx = true, i; break end
    end

    if found then
        table.remove(list, idx)
        notify("Favorites", "Removed: " .. name, 3)
    else
        local entry = {id = id, name = name}
        if State.mode == "animation" then entry.bundledItems = bundled or getBundled(id) end
        table.insert(list, entry)
        notify("Favorites", "Added: " .. name, 3)
    end

    saveFile(State.mode == "animation" and State.favAnimFileName or State.favFileName, list)
    rebuildFavLookup()
    State.totalPages = calcPages()
    updatePageDisplay()
    updateDisplay(true)
end

local function calcPages()
    local favs = State.mode == "animation" and State.favAnims or State.favEmotes
    local normalList = getNormalList()
    local pages = 0
    if #favs > 0 then pages = pages + math.ceil(#favs / State.itemsPerPage) end
    if #normalList > 0 then pages = pages + math.ceil(#normalList / State.itemsPerPage) end
    return math.max(pages, 1)
end

local function updatePageDisplay()
    if UI and UI.PagesLabel and UI.PageNumBox then
        UI.PagesLabel.Text = tostring(State.totalPages)
        UI.PageNumBox.Text = tostring(State.currentPage)
    end
end

local function getWheelButtons()
    local wheel = getWheel()
    if not wheel then return nil end
    local front = wheel:FindFirstChild("Front")
    if not front then return nil end
    local btns = front:FindFirstChild("EmotesButtons")
    if not btns then return nil end

    local buttonList = {}
    for _, child in pairs(btns:GetChildren()) do
        if child:IsA("ImageLabel") then
            buttonList[#buttonList + 1] = child
        end
    end
    table.sort(buttonList, function(a, b) return tonumber(a.Name) < tonumber(b.Name) end)
    return buttonList
end

local function getHoveredButtonIndex()
    local buttonList = getWheelButtons()
    if not buttonList then return nil end

    local mousePos = UserInputService:GetMouseLocation()
    local inset = GuiService:GetGuiInset()
    local adjustedY = mousePos.Y - inset.Y

    for i, btn in ipairs(buttonList) do
        if btn.Image ~= "" then
            local absPos = btn.AbsolutePosition
            local absSize = btn.AbsoluteSize
            if mousePos.X >= absPos.X and mousePos.X <= absPos.X + absSize.X
                and adjustedY >= absPos.Y and adjustedY <= absPos.Y + absSize.Y then
                return i
            end
        end
    end
    return nil
end

local function updateDisplay(force)
    if not force
        and State.lastDisplayPage == State.currentPage
        and State.lastDisplayMode == State.mode
        and State.lastDisplayFavVer == State.favSetVersion then
        return
    end

    local char, hum = getChar()
    if not char or not hum then return end

    local desc = hum:FindFirstChildOfClass("HumanoidDescription")
    if not desc then
        for i = 1, 10 do
            task.wait(0.1)
            desc = hum:FindFirstChildOfClass("HumanoidDescription")
            if desc then break end
        end
        if not desc then return end
    end

    State.lastDisplayPage = State.currentPage
    State.lastDisplayMode = State.mode
    State.lastDisplayFavVer = State.favSetVersion

    local favs = State.mode == "animation" and State.favAnims or State.favEmotes
    local items = {}
    local itemsPerPage = State.itemsPerPage
    local favPages = #favs > 0 and math.ceil(#favs / itemsPerPage) or 0

    if State.currentPage <= favPages and #favs > 0 then
        local startIdx = (State.currentPage - 1) * itemsPerPage + 1
        local endIdx = math.min(startIdx + itemsPerPage - 1, #favs)
        for i = startIdx, endIdx do
            if favs[i] then
                local item = {id = tonumber(favs[i].id), name = favs[i].name}
                if State.mode == "animation" then item.bundledItems = favs[i].bundledItems or getBundled(favs[i].id) end
                items[#items + 1] = item
            end
        end
    else
        local normalList = getNormalList()
        local adjPage = State.currentPage - favPages
        local startIdx = (adjPage - 1) * itemsPerPage + 1
        local endIdx = math.min(startIdx + itemsPerPage - 1, #normalList)
        for i = startIdx, endIdx do
            if normalList[i] then items[#items + 1] = normalList[i] end
        end
    end

    State.currentPageItems = items

    local emoteTable = {}
    local equipped = {}
    for _, item in ipairs(items) do
        emoteTable[item.name] = {item.id}
        equipped[#equipped + 1] = item.name
    end

    pcall(function() desc:SetEmotes(emoteTable); desc:SetEquippedEmotes(equipped) end)

    local token = State.currentOperationToken + 1
    State.currentOperationToken = token

    task.delay(0.15, function()
        if token ~= State.currentOperationToken then return end
        local buttonList = getWheelButtons()
        if not buttonList then return end

        for i = 1, #buttonList do
            local child = buttonList[i]
            if i <= #items then
                local item = items[i]
                if State.mode == "animation" then
                    child.Image = "rbxthumb://type=BundleThumbnail&id=" .. item.id .. "&w=420&h=420"
                else
                    child.Image = "rbxthumb://type=Asset&id=" .. item.id .. "&w=420&h=420"
                end
                updateFavIcon(child, item.id, isInFav(item.id))
                child.ImageColor3 = Color3.new(1, 1, 1)
            else
                child.Image = ""
                local star = child:FindFirstChild("FavStar")
                if star then star.Visible = false end
            end
        end
    end)
end

local function searchItems(term)
    term = term:lower()
    if term == State.lastSearchTerm then return end
    State.lastSearchTerm = term
    local source = State.mode == "animation" and State.animsData or State.emotesData

    if term == "" then
        if State.mode == "animation" then State.filteredAnims = State.animsData
        else State.filteredEmotes = State.emotesData end
    else
        local result = {}
        local isIdSearch = term:match("^%d+$")
        if isIdSearch then
            for i = 1, #source do
                if tostring(source[i].id) == term then result[#result + 1] = source[i]; break end
            end
        else
            for i = 1, #source do
                if source[i].name:lower():find(term, 1, true) then result[#result + 1] = source[i] end
            end
        end
        if State.mode == "animation" then State.filteredAnims = result
        else State.filteredEmotes = result end
    end

    State.normalListCacheVersion = -1
    State.currentPage = 1
    State.totalPages = calcPages()
    updatePageDisplay()
    updateDisplay(true)
end

local function prevPage()
    State.currentPage = State.currentPage <= 1 and State.totalPages or State.currentPage - 1
    updatePageDisplay(); updateDisplay(true)
end

local function nextPage()
    State.currentPage = State.currentPage >= State.totalPages and 1 or State.currentPage + 1
    updatePageDisplay(); updateDisplay(true)
end

local function goToPage(num)
    State.currentPage = math.clamp(num, 1, State.totalPages)
    updatePageDisplay(); updateDisplay(true)
end

local function toggleMode()
    State.mode = State.mode == "emote" and "animation" or "emote"
    if State.mode == "animation" and #State.animsData == 0 then
        task.spawn(function()
            local ok, result = pcall(function() return HttpService:JSONDecode(game:HttpGet(ANIM_URL)) end)
            if ok and result then
                local rawList = result.data or result
                local data = {}
                for i = 1, #rawList do
                    local item = rawList[i]; local id = tonumber(item.id)
                    if id and id > 0 then data[#data + 1] = {id = id, name = item.name or ("Anim_" .. id), bundledItems = item.bundledItems} end
                end
                State.animsData = data; State.filteredAnims = data
                State.normalListCacheVersion = -1; State.totalPages = calcPages()
                updatePageDisplay(); updateDisplay(true)
            end
        end)
    end
    if UI and UI.Search then UI.Search.Text = "" end
    State.lastSearchTerm = ""
    if State.mode == "animation" then State.filteredAnims = State.animsData
    else State.filteredEmotes = State.emotesData end
    State.normalListCacheVersion = -1; State.currentPage = 1
    State.totalPages = calcPages(); updatePageDisplay(); updateDisplay(true); applyNativeTheme()
end

local function toggleFavMode()
    State.favEnabled = not State.favEnabled
    applyNativeTheme(); updateDisplay(true)
end

local function toggleAutoReapply()
    State.autoReapplyEnabled = not State.autoReapplyEnabled
    State.config.AutoReapplyEnabled = State.autoReapplyEnabled
    SaveConfig(); applyNativeTheme()
    notify("Auto-Reapply", State.autoReapplyEnabled and "ON" or "OFF", 3)

    if State.autoReapplyEnabled then
        task.spawn(function()
            local hasCustomSlots = State.config.CustomAnimSlots and next(State.config.CustomAnimSlots)
            local hasLastAnim = getgenv().lastAnim and getgenv().lastAnim.id

            if hasLastAnim and not hasCustomSlots then
                applyAnim(getgenv().lastAnim)
            elseif hasCustomSlots then
                applyAllCustomSlots()
            end
        end)
    end
end

function applyNativeTheme()
    local wheel = getWheel()
    if not wheel then return end
    local theme = Themes[currentThemeName] or DefaultTheme

    pcall(function()
        local back = wheel:FindFirstChild("Back")
        if back then
            local bg = back:FindFirstChild("Background")
            if bg and bg:IsA("Frame") then
                bg.BackgroundColor3 = TableToColor(theme.Background); bg.BackgroundTransparency = 0.05
                local ov = bg:FindFirstChild("BackgroundCircleOverlay")
                if ov then ov.BackgroundColor3 = TableToColor(theme.Background); ov.BackgroundTransparency = 0.1 end
            end
        end
    end)

    if UI.LeftBtn then UI.LeftBtn.ImageColor3 = GetIconColor("Left") end
    if UI.RightBtn then UI.RightBtn.ImageColor3 = GetIconColor("Right") end
    if UI.PagesLabel then UI.PagesLabel.TextColor3 = TableToColor(theme.ImageColor) end
    if UI.SepLabel then UI.SepLabel.TextColor3 = TableToColor(theme.ImageColor) end
    if UI.PageNumBox then UI.PageNumBox.TextColor3 = TableToColor(theme.ImageColor) end
    if UI.Top then UI.Top.BackgroundColor3 = TableToColor(theme.Background); UI.Top.BackgroundTransparency = 0.1 end
    if UI.FavBtn then UI.FavBtn.BackgroundColor3 = State.favEnabled and GetIconColor("Favorite") or TableToColor(theme.Background); UI.FavBtn.BackgroundTransparency = 0.1 end
    if UI.FavBtnLabel then UI.FavBtnLabel.TextColor3 = State.favEnabled and Color3.fromRGB(255, 255, 255) or TableToColor(theme.ImageColor) end
    if UI.ModeBtn then UI.ModeBtn.BackgroundColor3 = State.mode == "animation" and GetIconColor("Mode") or TableToColor(theme.Background) end
    if UI.ModeBtnLabel then UI.ModeBtnLabel.TextColor3 = TableToColor(theme.ImageColor); UI.ModeBtnLabel.Text = State.mode == "animation" and "ANI" or "EMO" end
    if UI.AutoReapplyBtn then UI.AutoReapplyBtn.BackgroundColor3 = State.autoReapplyEnabled and GetIconColor("Auto") or TableToColor(theme.Background) end
    if UI.AutoBtnLabel then UI.AutoBtnLabel.TextColor3 = TableToColor(theme.ImageColor) end
    if UI.CustomAnimBtn then UI.CustomAnimBtn.BackgroundColor3 = TableToColor(theme.Background); UI.CustomAnimBtn.BackgroundTransparency = 0.1 end
    if UI.CustomAnimBtnLabel then UI.CustomAnimBtnLabel.TextColor3 = TableToColor(theme.ImageColor) end
end

-- ============ GLOBAL CLICK HANDLER ============ --
local function setupGlobalWheelClick()
    if State.globalClickConn then
        pcall(function() State.globalClickConn:Disconnect() end)
        State.globalClickConn = nil
    end

    State.globalClickConn = UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
        if State.hudEditorActive then return end

        local wheel = getWheel()
        if not wheel or not wheel.Visible then return end
        if #State.currentPageItems == 0 then return end

        task.defer(function()
            local index = getHoveredButtonIndex()
            if index then
                handleSector(index)
            end
        end)
    end)
end

-- ============ HUD EDITOR ============ --
local HUD = {
    Connections = {},
    Strokes = {},
    Overlay = nil,
    DefaultPositions = {
        Under = UDim2.new(0.13, 0, 1, 0),
        Top = UDim2.new(0.13, 0, -0.11, 0),
        FavBtn = UDim2.new(0.019, 0, -0.108, 0),
        ModeBtn = UDim2.new(0.889, 0, -0.108, 0),
        AutoBtn = UDim2.new(0.889, 0, -0.215, 0),
        CustomAnimBtn = UDim2.new(0.019, 0, -0.215, 0),
    }
}

local function getMovableElements()
    local elems = {}
    if UI.Top then elems["Top"] = UI.Top end
    if UI.Under then elems["Under"] = UI.Under end
    if UI.FavBtn then elems["FavBtn"] = UI.FavBtn end
    if UI.ModeBtn then elems["ModeBtn"] = UI.ModeBtn end
    if UI.AutoReapplyBtn then elems["AutoBtn"] = UI.AutoReapplyBtn end
    if UI.CustomAnimBtn then elems["CustomAnimBtn"] = UI.CustomAnimBtn end
    return elems
end

local function setupElementDragging(name, element)
    local stroke = Instance.new("UIStroke")
    stroke.Name = "HUDEditorStroke"; stroke.Color = Color3.fromRGB(0, 255, 100); stroke.Thickness = 2; stroke.Parent = element
    table.insert(HUD.Strokes, stroke)

    local dragging = false
    local dragStart, startPos

    local dragHandle = Instance.new("ImageButton")
    dragHandle.Name = "DragHandle"; dragHandle.Parent = element; dragHandle.BackgroundTransparency = 1
    dragHandle.Size = UDim2.fromScale(1, 1); dragHandle.ZIndex = 9999; dragHandle.Active = true; dragHandle.Image = ""

    table.insert(HUD.Connections, dragHandle.InputBegan:Connect(function(input)
        if not State.hudEditorActive then return end
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true; dragStart = input.Position; startPos = element.Position; stroke.Color = Color3.fromRGB(255, 255, 255)
        end
    end))
    table.insert(HUD.Connections, UserInputService.InputChanged:Connect(function(input)
        if not dragging then return end
        if input.UserInputType == Enum.UserInputType.MouseMovement then
            local delta = input.Position - dragStart
            local ps = element.Parent and element.Parent.AbsoluteSize or Vector2.new(1, 1)
            element.Position = UDim2.new(startPos.X.Scale + delta.X / ps.X, startPos.X.Offset, startPos.Y.Scale + delta.Y / ps.Y, startPos.Y.Offset)
        end
    end))
    table.insert(HUD.Connections, UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 and dragging then
            dragging = false; stroke.Color = Color3.fromRGB(0, 255, 100)
            State.config.HUDPositions[name] = {element.Position.X.Scale, element.Position.X.Offset, element.Position.Y.Scale, element.Position.Y.Offset}
            SaveConfig()
        end
    end))
end

local function enterHUDEditor()
    if State.hudEditorActive then return end
    State.hudEditorActive = true
    GuiService:SetEmotesMenuOpen(false); task.wait(0.15)
    local wheel = getWheel()
    if not wheel then State.hudEditorActive = false; return end
    wheel.Visible = true

    local overlay = Instance.new("Frame")
    overlay.Name = "HUDEditorOverlay"; overlay.Parent = CoreGui; overlay.BackgroundTransparency = 1
    overlay.Size = UDim2.fromScale(1, 1); overlay.ZIndex = 6000; HUD.Overlay = overlay

    local controlBar = Instance.new("Frame", overlay)
    controlBar.BackgroundTransparency = 1; controlBar.AnchorPoint = Vector2.new(1, 0)
    controlBar.Position = UDim2.new(1, -10, 0, 10); controlBar.Size = UDim2.fromOffset(100, 42)
    local layout = Instance.new("UIListLayout", controlBar)
    layout.FillDirection = Enum.FillDirection.Horizontal; layout.Padding = UDim.new(0, 8)

    local resetBtn = Instance.new("ImageButton", controlBar)
    resetBtn.BackgroundColor3 = Color3.fromRGB(0, 0, 0); resetBtn.BackgroundTransparency = 0.4
    resetBtn.Size = UDim2.fromOffset(42, 42); resetBtn.Image = "rbxassetid://123088523596870"
    Instance.new("UICorner", resetBtn).CornerRadius = UDim.new(0, 10)

    local exitBtn = Instance.new("ImageButton", controlBar)
    exitBtn.BackgroundColor3 = Color3.fromRGB(0, 0, 0); exitBtn.BackgroundTransparency = 0.4
    exitBtn.Size = UDim2.fromOffset(42, 42); exitBtn.Image = "rbxassetid://79024388644722"
    Instance.new("UICorner", exitBtn).CornerRadius = UDim.new(0, 10)

    exitBtn.MouseButton1Click:Connect(function()
        State.hudEditorActive = false
        for _, conn in pairs(HUD.Connections) do pcall(function() conn:Disconnect() end) end; HUD.Connections = {}
        for _, stroke in pairs(HUD.Strokes) do pcall(function() if stroke and stroke.Parent then stroke:Destroy() end end) end; HUD.Strokes = {}
        if HUD.Overlay then HUD.Overlay:Destroy() end; HUD.Overlay = nil
        pcall(function() GuiService:SetEmotesMenuOpen(false) end)
    end)
    resetBtn.MouseButton1Click:Connect(function()
        State.config.HUDPositions = {}; SaveConfig()
        for name, el in pairs(getMovableElements()) do
            if HUD.DefaultPositions[name] then el.Position = HUD.DefaultPositions[name] end
        end
    end)

    for name, element in pairs(getMovableElements()) do setupElementDragging(name, element) end
end

-- ============ CUSTOM ANIMATION EDITOR ============ --
local customAnimEditorGui = nil

local function closeCustomAnimEditor()
    if customAnimEditorGui then customAnimEditorGui:Destroy(); customAnimEditorGui = nil end
end

local function openCustomAnimEditor()
    if customAnimEditorGui then closeCustomAnimEditor(); return end

    if #State.animsData == 0 then
        notify("Custom Anim", "Loading animations first...", 3)
        task.spawn(function()
            local ok, result = pcall(function() return HttpService:JSONDecode(game:HttpGet(ANIM_URL)) end)
            if ok and result then
                local rawList = result.data or result
                local data = {}
                for i = 1, #rawList do
                    local item = rawList[i]; local id = tonumber(item.id)
                    if id and id > 0 then data[#data + 1] = {id = id, name = item.name or ("Anim_" .. id), bundledItems = item.bundledItems} end
                end
                State.animsData = data; State.filteredAnims = data
            end
            openCustomAnimEditor()
        end)
        return
    end

    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "CustomAnimEditor"; screenGui.ResetOnSpawn = false
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling; screenGui.Parent = CoreGui
    customAnimEditorGui = screenGui

    local main = Instance.new("Frame", screenGui)
    main.BackgroundColor3 = Color3.fromRGB(30, 30, 30); main.BorderSizePixel = 0
    main.Size = UDim2.fromOffset(380, 480); main.Position = UDim2.fromScale(0.5, 0.5)
    main.AnchorPoint = Vector2.new(0.5, 0.5); main.ZIndex = 50; main.ClipsDescendants = true
    Instance.new("UICorner", main).CornerRadius = UDim.new(0, 10)
    local ms = Instance.new("UIStroke", main); ms.Color = Color3.fromRGB(70, 70, 70); ms.Thickness = 1

    local titleBar = Instance.new("Frame", main)
    titleBar.BackgroundColor3 = Color3.fromRGB(40, 40, 40); titleBar.Size = UDim2.new(1, 0, 0, 35)
    titleBar.BorderSizePixel = 0; titleBar.ZIndex = 51
    Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 10)

    local titleLabel = Instance.new("TextLabel", titleBar)
    titleLabel.BackgroundTransparency = 1; titleLabel.Size = UDim2.new(0.8, 0, 1, 0)
    titleLabel.Position = UDim2.fromOffset(10, 0); titleLabel.Font = Enum.Font.GothamBold
    titleLabel.Text = "Custom Animation Slots"; titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    titleLabel.TextSize = 14; titleLabel.TextXAlignment = Enum.TextXAlignment.Left; titleLabel.ZIndex = 52

    local closeBtn = Instance.new("TextButton", titleBar)
    closeBtn.BackgroundTransparency = 1; closeBtn.Size = UDim2.fromOffset(35, 35)
    closeBtn.Position = UDim2.new(1, -35, 0, 0); closeBtn.Font = Enum.Font.GothamBold
    closeBtn.Text = "X"; closeBtn.TextColor3 = Color3.fromRGB(200, 200, 200); closeBtn.TextSize = 16; closeBtn.ZIndex = 52
    closeBtn.MouseButton1Click:Connect(closeCustomAnimEditor)

    local edDragging, edDragStart, edStartPos = false, nil, nil
    local dragConns = {}
    titleBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            edDragging = true; edDragStart = input.Position; edStartPos = main.Position
        end
    end)
    table.insert(dragConns, UserInputService.InputChanged:Connect(function(input)
        if edDragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            local delta = input.Position - edDragStart
            main.Position = UDim2.new(edStartPos.X.Scale, edStartPos.X.Offset + delta.X, edStartPos.Y.Scale, edStartPos.Y.Offset + delta.Y)
        end
    end))
    table.insert(dragConns, UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then edDragging = false end
    end))

    screenGui.Destroying:Connect(function()
        for _, conn in ipairs(dragConns) do pcall(function() conn:Disconnect() end) end
    end)

    local contentArea = Instance.new("Frame", main)
    contentArea.BackgroundTransparency = 1; contentArea.Position = UDim2.fromOffset(0, 38)
    contentArea.Size = UDim2.new(1, 0, 1, -38); contentArea.ZIndex = 51; contentArea.ClipsDescendants = true

    local slotPage = Instance.new("Frame", contentArea)
    slotPage.Name = "SlotPage"; slotPage.BackgroundTransparency = 1
    slotPage.Size = UDim2.fromScale(1, 1); slotPage.ZIndex = 52; slotPage.Visible = true

    local scrollFrame = Instance.new("ScrollingFrame", slotPage)
    scrollFrame.BackgroundTransparency = 1; scrollFrame.Position = UDim2.fromOffset(0, 0)
    scrollFrame.Size = UDim2.new(1, 0, 1, -44); scrollFrame.ScrollBarThickness = 4
    scrollFrame.ScrollBarImageColor3 = Color3.fromRGB(100, 100, 100)
    scrollFrame.CanvasSize = UDim2.fromOffset(0, 0); scrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
    scrollFrame.BorderSizePixel = 0; scrollFrame.ZIndex = 53

    local ll = Instance.new("UIListLayout", scrollFrame)
    ll.Padding = UDim.new(0, 4); ll.SortOrder = Enum.SortOrder.LayoutOrder
    local padUI = Instance.new("UIPadding", scrollFrame)
    padUI.PaddingLeft = UDim.new(0, 8); padUI.PaddingRight = UDim.new(0, 8); padUI.PaddingTop = UDim.new(0, 4)

    local pickerPage = Instance.new("Frame", contentArea)
    pickerPage.Name = "PickerPage"; pickerPage.BackgroundTransparency = 1
    pickerPage.Size = UDim2.fromScale(1, 1); pickerPage.ZIndex = 52; pickerPage.Visible = false

    local pickerTitle = Instance.new("TextLabel", pickerPage)
    pickerTitle.BackgroundTransparency = 1; pickerTitle.Size = UDim2.new(1, -60, 0, 28)
    pickerTitle.Position = UDim2.fromOffset(8, 2); pickerTitle.Font = Enum.Font.GothamBold
    pickerTitle.Text = "Pick bundle for: idle"; pickerTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
    pickerTitle.TextSize = 12; pickerTitle.TextXAlignment = Enum.TextXAlignment.Left; pickerTitle.ZIndex = 53

    local pickerBack = Instance.new("TextButton", pickerPage)
    pickerBack.BackgroundColor3 = Color3.fromRGB(60, 60, 60); pickerBack.Size = UDim2.fromOffset(50, 24)
    pickerBack.Position = UDim2.new(1, -58, 0, 4); pickerBack.Font = Enum.Font.GothamBold
    pickerBack.Text = "Back"; pickerBack.TextColor3 = Color3.fromRGB(220, 220, 220); pickerBack.TextSize = 11
    pickerBack.BorderSizePixel = 0; pickerBack.ZIndex = 53
    Instance.new("UICorner", pickerBack).CornerRadius = UDim.new(0, 4)

    local pickerSearch = Instance.new("TextBox", pickerPage)
    pickerSearch.BackgroundColor3 = Color3.fromRGB(50, 50, 50); pickerSearch.Position = UDim2.fromOffset(5, 32)
    pickerSearch.Size = UDim2.new(1, -10, 0, 26); pickerSearch.Font = Enum.Font.Gotham
    pickerSearch.PlaceholderText = "Search bundles..."; pickerSearch.PlaceholderColor3 = Color3.fromRGB(100, 100, 100)
    pickerSearch.Text = ""; pickerSearch.TextColor3 = Color3.fromRGB(255, 255, 255); pickerSearch.TextSize = 12
    pickerSearch.ClearTextOnFocus = false; pickerSearch.BorderSizePixel = 0; pickerSearch.ZIndex = 53
    Instance.new("UICorner", pickerSearch).CornerRadius = UDim.new(0, 4)

    local pickerStatus = Instance.new("TextLabel", pickerPage)
    pickerStatus.Name = "StatusLabel"; pickerStatus.BackgroundTransparency = 1
    pickerStatus.Size = UDim2.new(1, 0, 0, 20); pickerStatus.Position = UDim2.new(0, 0, 1, -20)
    pickerStatus.Font = Enum.Font.Gotham; pickerStatus.Text = ""
    pickerStatus.TextColor3 = Color3.fromRGB(100, 255, 100); pickerStatus.TextSize = 11; pickerStatus.ZIndex = 55

    local pickerScroll = Instance.new("ScrollingFrame", pickerPage)
    pickerScroll.BackgroundTransparency = 1; pickerScroll.Position = UDim2.fromOffset(0, 62)
    pickerScroll.Size = UDim2.new(1, 0, 1, -82); pickerScroll.ScrollBarThickness = 4
    pickerScroll.ScrollBarImageColor3 = Color3.fromRGB(100, 100, 100)
    pickerScroll.CanvasSize = UDim2.fromOffset(0, 0); pickerScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    pickerScroll.BorderSizePixel = 0; pickerScroll.ZIndex = 53
    local pll = Instance.new("UIListLayout", pickerScroll)
    pll.Padding = UDim.new(0, 2); pll.SortOrder = Enum.SortOrder.LayoutOrder

    local currentPickerSlot = ""
    local pickerApplying = false

    pickerBack.MouseButton1Click:Connect(function()
        pickerPage.Visible = false
        slotPage.Visible = true
    end)

    local pickerBuildToken = 0

    local function populatePickerList(filterTerm)
        pickerBuildToken = pickerBuildToken + 1
        local myToken = pickerBuildToken

        for _, child in pairs(pickerScroll:GetChildren()) do
            if child:IsA("TextButton") or child:IsA("TextLabel") then child:Destroy() end
        end

        filterTerm = (filterTerm or ""):lower()

        local matches = {}
        for i = 1, #State.animsData do
            if #matches >= 50 then break end
            local item = State.animsData[i]
            if filterTerm == "" or item.name:lower():find(filterTerm, 1, true) or tostring(item.id) == filterTerm then
                matches[#matches + 1] = item
            end
        end

        if #matches == 0 then
            local noR = Instance.new("TextLabel", pickerScroll)
            noR.BackgroundTransparency = 1; noR.Size = UDim2.new(1, 0, 0, 30)
            noR.Font = Enum.Font.Gotham; noR.Text = "No bundles found"
            noR.TextColor3 = Color3.fromRGB(100, 100, 100); noR.TextSize = 11; noR.ZIndex = 54
            return
        end

        local BATCH_SIZE = 10
        local batchIdx = 1

        local function createBatch()
            if myToken ~= pickerBuildToken then return end
            local batchEnd = math.min(batchIdx + BATCH_SIZE - 1, #matches)

            for i = batchIdx, batchEnd do
                if myToken ~= pickerBuildToken then return end
                local item = matches[i]

                local btn = Instance.new("TextButton")
                btn.BackgroundColor3 = Color3.fromRGB(40, 40, 40); btn.Size = UDim2.new(1, -4, 0, 30)
                btn.Font = Enum.Font.Gotham; btn.Text = "  " .. item.name
                btn.TextColor3 = Color3.fromRGB(220, 220, 220); btn.TextSize = 11
                btn.TextXAlignment = Enum.TextXAlignment.Left; btn.BorderSizePixel = 0
                btn.LayoutOrder = i; btn.ZIndex = 54; btn.AutoButtonColor = true
                Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 4)
                btn.Parent = pickerScroll

                btn.MouseButton1Click:Connect(function()
                    if pickerApplying then return end
                    pickerApplying = true

                    btn.Text = "  Applying..."
                    btn.TextColor3 = Color3.fromRGB(100, 255, 100)
                    pickerStatus.Text = "Applying " .. item.name .. "..."

                    task.spawn(function()
                        local bundled = item.bundledItems or getBundled(item.id)
                        if not bundled then
                            notify("Custom Anim", "No bundle data for: " .. item.name, 3)
                            btn.Text = "  " .. item.name
                            btn.TextColor3 = Color3.fromRGB(220, 220, 220)
                            pickerStatus.Text = "Failed - no bundle data"
                            pickerApplying = false
                            return
                        end

                        local success = applySlotFromBundle(currentPickerSlot, {id = item.id, name = item.name, bundledItems = bundled})

                        btn.Text = "  " .. item.name
                        btn.TextColor3 = Color3.fromRGB(220, 220, 220)

                        if success then
                            notify("Custom Anim", currentPickerSlot .. " set from: " .. item.name, 3)
                            pickerStatus.Text = "Applied " .. currentPickerSlot .. " from " .. item.name
                            pickerPage.Visible = false
                            slotPage.Visible = true
                            local row = scrollFrame:FindFirstChild("Row_" .. currentPickerSlot)
                            if row then
                                local cl = row:FindFirstChild("CurrentLabel")
                                if cl then cl.Text = item.name end
                            end
                        else
                            notify("Custom Anim", "Could not extract " .. currentPickerSlot .. " from: " .. item.name, 3)
                            pickerStatus.Text = "Failed to extract " .. currentPickerSlot
                        end
                        pickerApplying = false
                    end)
                end)
            end

            batchIdx = batchEnd + 1
            if batchIdx <= #matches then
                task.defer(createBatch)
            end
        end

        createBatch()
    end

    local pickerDebounce = nil
    pickerSearch:GetPropertyChangedSignal("Text"):Connect(function()
        if pickerDebounce then pcall(function() task.cancel(pickerDebounce) end) end
        pickerDebounce = task.delay(0.35, function()
            populatePickerList(pickerSearch.Text)
            pickerDebounce = nil
        end)
    end)

    local function openPickerForSlot(slotName)
        currentPickerSlot = slotName
        pickerTitle.Text = "Pick bundle for: " .. slotName
        pickerSearch.Text = ""
        pickerStatus.Text = ""
        pickerApplying = false
        populatePickerList("")
        slotPage.Visible = false
        pickerPage.Visible = true
    end

    -- Build slot rows with individual REMOVE buttons
    for idx, slotName in ipairs(ANIM_SLOT_NAMES) do
        local row = Instance.new("Frame", scrollFrame)
        row.Name = "Row_" .. slotName; row.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
        row.Size = UDim2.new(1, 0, 0, 38); row.LayoutOrder = idx; row.BorderSizePixel = 0; row.ZIndex = 54
        Instance.new("UICorner", row).CornerRadius = UDim.new(0, 6)

        local slotLabel = Instance.new("TextLabel", row)
        slotLabel.BackgroundTransparency = 1; slotLabel.Position = UDim2.fromOffset(8, 0)
        slotLabel.Size = UDim2.new(0.18, 0, 1, 0); slotLabel.Font = Enum.Font.GothamBold
        slotLabel.Text = slotName; slotLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
        slotLabel.TextSize = 12; slotLabel.TextXAlignment = Enum.TextXAlignment.Left; slotLabel.ZIndex = 55

        local currentInfo = State.config.CustomAnimSlots[slotName]
        local currentName = "None"
        if type(currentInfo) == "table" and currentInfo.name then currentName = currentInfo.name end

        local currentLabel = Instance.new("TextLabel", row)
        currentLabel.Name = "CurrentLabel"; currentLabel.BackgroundTransparency = 1
        currentLabel.Position = UDim2.new(0.20, 0, 0, 0); currentLabel.Size = UDim2.new(0.36, 0, 1, 0)
        currentLabel.Font = Enum.Font.Gotham; currentLabel.Text = currentName
        currentLabel.TextColor3 = Color3.fromRGB(150, 150, 150); currentLabel.TextSize = 10
        currentLabel.TextTruncate = Enum.TextTruncate.AtEnd; currentLabel.TextXAlignment = Enum.TextXAlignment.Left; currentLabel.ZIndex = 55

        -- Per-slot REMOVE button
        local removeBtn = Instance.new("TextButton", row)
        removeBtn.Name = "RemoveBtn"
        removeBtn.BackgroundColor3 = Color3.fromRGB(160, 50, 50)
        removeBtn.Position = UDim2.new(0.57, 0, 0.1, 0); removeBtn.Size = UDim2.new(0.18, -2, 0.8, 0)
        removeBtn.Font = Enum.Font.GothamBold; removeBtn.Text = "X"
        removeBtn.TextColor3 = Color3.fromRGB(255, 255, 255); removeBtn.TextSize = 12
        removeBtn.BorderSizePixel = 0; removeBtn.ZIndex = 55
        Instance.new("UICorner", removeBtn).CornerRadius = UDim.new(0, 4)

        removeBtn.MouseButton1Click:Connect(function()
            if State.applyingAnim then
                notify("Custom Anim", "Wait for current operation to finish", 3)
                return
            end

            State.config.CustomAnimSlots[slotName] = nil
            SaveConfig()

            captureOriginalAnims()
            local reverted = revertSlotWithFreeze(slotName)

            if reverted then
                notify("Custom Anim", "Removed & reverted: " .. slotName, 3)
            else
                notify("Custom Anim", "Removed: " .. slotName .. " (revert on respawn)", 3)
            end

            currentLabel.Text = "None"
        end)

        -- Pick button
        local selectBtn = Instance.new("TextButton", row)
        selectBtn.BackgroundColor3 = Color3.fromRGB(0, 130, 220)
        selectBtn.Position = UDim2.new(0.76, 0, 0.1, 0); selectBtn.Size = UDim2.new(0.22, -4, 0.8, 0)
        selectBtn.Font = Enum.Font.GothamBold; selectBtn.Text = "Pick"
        selectBtn.TextColor3 = Color3.fromRGB(255, 255, 255); selectBtn.TextSize = 11
        selectBtn.BorderSizePixel = 0; selectBtn.ZIndex = 55
        Instance.new("UICorner", selectBtn).CornerRadius = UDim.new(0, 4)

        selectBtn.MouseButton1Click:Connect(function()
            openPickerForSlot(slotName)
        end)
    end

    -- Bottom buttons
    local bottomBar = Instance.new("Frame", slotPage)
    bottomBar.BackgroundTransparency = 1; bottomBar.BorderSizePixel = 0
    bottomBar.Size = UDim2.new(1, 0, 0, 36); bottomBar.Position = UDim2.new(0, 0, 1, -38)
    bottomBar.ZIndex = 54

    local bottomLayout = Instance.new("UIListLayout", bottomBar)
    bottomLayout.FillDirection = Enum.FillDirection.Horizontal
    bottomLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    bottomLayout.VerticalAlignment = Enum.VerticalAlignment.Center
    bottomLayout.Padding = UDim.new(0, 10)

    local applyAllBtn = Instance.new("TextButton", bottomBar)
    applyAllBtn.Name = "ApplyAllBtn"; applyAllBtn.LayoutOrder = 1
    applyAllBtn.BackgroundColor3 = Color3.fromRGB(40, 160, 60)
    applyAllBtn.Size = UDim2.new(0, 130, 0, 28)
    applyAllBtn.Font = Enum.Font.GothamBold; applyAllBtn.Text = "Apply All"
    applyAllBtn.TextColor3 = Color3.fromRGB(255, 255, 255); applyAllBtn.TextSize = 12
    applyAllBtn.BorderSizePixel = 0; applyAllBtn.ZIndex = 55
    Instance.new("UICorner", applyAllBtn).CornerRadius = UDim.new(0, 6)

    applyAllBtn.MouseButton1Click:Connect(function()
        if State.applyingAnim then
            notify("Custom Anim", "Already applying, please wait...", 3)
            return
        end

        local hasSlots = false
        for _, info in pairs(State.config.CustomAnimSlots) do
            if type(info) == "table" and info.id then hasSlots = true; break end
        end

        if not hasSlots then
            notify("Custom Anim", "No custom slots configured! Pick some first.", 3)
            return
        end

        applyAllBtn.Text = "Applying..."
        applyAllBtn.BackgroundColor3 = Color3.fromRGB(80, 80, 80)

        task.spawn(function()
            applyAllCustomSlots()
            while State.applyingAnim do task.wait(0.1) end
            if applyAllBtn and applyAllBtn.Parent then
                applyAllBtn.Text = "Apply All"
                applyAllBtn.BackgroundColor3 = Color3.fromRGB(40, 160, 60)
            end
        end)
    end)

    local clearAllBtn = Instance.new("TextButton", bottomBar)
    clearAllBtn.Name = "ClearAllBtn"; clearAllBtn.LayoutOrder = 2
    clearAllBtn.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
    clearAllBtn.Size = UDim2.new(0, 130, 0, 28)
    clearAllBtn.Font = Enum.Font.GothamBold; clearAllBtn.Text = "Clear All"
    clearAllBtn.TextColor3 = Color3.fromRGB(255, 255, 255); clearAllBtn.TextSize = 12
    clearAllBtn.BorderSizePixel = 0; clearAllBtn.ZIndex = 55
    Instance.new("UICorner", clearAllBtn).CornerRadius = UDim.new(0, 6)

    clearAllBtn.MouseButton1Click:Connect(function()
        if State.applyingAnim then
            notify("Custom Anim", "Wait for current operation to finish", 3)
            return
        end

        State.config.CustomAnimSlots = {}; SaveConfig()

        captureOriginalAnims()
        revertAllSlotsWithFreeze()

        for _, child in pairs(scrollFrame:GetChildren()) do
            if child:IsA("Frame") then
                local cl = child:FindFirstChild("CurrentLabel")
                if cl then cl.Text = "None" end
            end
        end
        notify("Custom Anim", "All custom slots cleared & reverted", 3)
    end)
end

-- ============ HOTKEYS ============ --
local function bindWheelHotkeys()
    local keyToIndex = {
        [Enum.KeyCode.One] = 1, [Enum.KeyCode.Two] = 2, [Enum.KeyCode.Three] = 3, [Enum.KeyCode.Four] = 4,
        [Enum.KeyCode.Five] = 5, [Enum.KeyCode.Six] = 6, [Enum.KeyCode.Seven] = 7, [Enum.KeyCode.Eight] = 8,
        [Enum.KeyCode.KeypadOne] = 1, [Enum.KeyCode.KeypadTwo] = 2, [Enum.KeyCode.KeypadThree] = 3,
        [Enum.KeyCode.KeypadFour] = 4, [Enum.KeyCode.KeypadFive] = 5, [Enum.KeyCode.KeypadSix] = 6,
        [Enum.KeyCode.KeypadSeven] = 7, [Enum.KeyCode.KeypadEight] = 8
    }
    local function onHotkey(_, inputState, inputObject)
        if inputState ~= Enum.UserInputState.Begin then return Enum.ContextActionResult.Pass end
        if State.hudEditorActive then return Enum.ContextActionResult.Pass end
        local index = keyToIndex[inputObject.KeyCode]
        if not index then return Enum.ContextActionResult.Pass end
        local wheel = getWheel()
        if not wheel or not wheel.Visible then return Enum.ContextActionResult.Pass end
        handleSector(index)
        return Enum.ContextActionResult.Sink
    end
    ContextActionService:UnbindAction("PinkWards_EmoteWheelHotkeys")
    ContextActionService:BindActionAtPriority(
        "PinkWards_EmoteWheelHotkeys", onHotkey, false, (Enum.ContextActionPriority.High.Value + 50),
        Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four,
        Enum.KeyCode.Five, Enum.KeyCode.Six, Enum.KeyCode.Seven, Enum.KeyCode.Eight,
        Enum.KeyCode.KeypadOne, Enum.KeyCode.KeypadTwo, Enum.KeyCode.KeypadThree, Enum.KeyCode.KeypadFour,
        Enum.KeyCode.KeypadFive, Enum.KeyCode.KeypadSix, Enum.KeyCode.KeypadSeven, Enum.KeyCode.KeypadEight
    )
end

-- ============ GUI CREATION ============ --
UI = {}

local function makeTextButton(name, parent, pos, size, text)
    local btn = Instance.new("ImageButton")
    btn.Name = name; btn.Parent = parent; btn.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
    btn.BackgroundTransparency = 0.1; btn.BorderSizePixel = 0; btn.Position = pos; btn.Size = size; btn.Image = ""
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
    local stroke = Instance.new("UIStroke", btn); stroke.Color = Color3.fromRGB(70, 70, 70); stroke.Thickness = 1; stroke.Transparency = 0.5
    local label = Instance.new("TextLabel", btn)
    label.Name = "Label"; label.BackgroundTransparency = 1; label.Size = UDim2.new(1, 0, 1, 0)
    label.Font = Enum.Font.GothamBold; label.Text = text; label.TextColor3 = Color3.fromRGB(255, 255, 255)
    label.TextScaled = true; label.ZIndex = btn.ZIndex + 1
    return btn, label
end

function createGUI()
    local wheel = getWheel()
    if not wheel then return false end

    for _, name in ipairs({"Under", "Top", "Favorite", "ModeToggle", "AutoReapplyToggle", "CustomAnimToggle"}) do
        local existing = wheel:FindFirstChild(name)
        if existing then existing:Destroy() end
    end

    UI.Under = Instance.new("Frame")
    UI.Under.Name = "Under"; UI.Under.Parent = wheel; UI.Under.BackgroundTransparency = 1; UI.Under.BorderSizePixel = 0
    UI.Under.Position = State.config.HUDPositions.Under and UDim2.new(unpack(State.config.HUDPositions.Under)) or HUD.DefaultPositions.Under
    UI.Under.Size = UDim2.new(0.74, 0, 0.13, 0)

    local ul = Instance.new("UIListLayout", UI.Under)
    ul.FillDirection = Enum.FillDirection.Horizontal; ul.VerticalAlignment = Enum.VerticalAlignment.Center; ul.SortOrder = Enum.SortOrder.LayoutOrder

    UI.LeftBtn = Instance.new("ImageButton", UI.Under)
    UI.LeftBtn.Name = "LeftBtn"; UI.LeftBtn.LayoutOrder = 1; UI.LeftBtn.BackgroundTransparency = 1
    UI.LeftBtn.Size = UDim2.new(0.17, 0, 0.94, 0); UI.LeftBtn.Image = "rbxassetid://93111945058621"

    UI.PageNumBox = Instance.new("TextBox", UI.Under)
    UI.PageNumBox.Name = "PageNum"; UI.PageNumBox.LayoutOrder = 2; UI.PageNumBox.BackgroundTransparency = 1
    UI.PageNumBox.Size = UDim2.new(0.16, 0, 0.81, 0); UI.PageNumBox.Font = Enum.Font.GothamBold
    UI.PageNumBox.Text = "1"; UI.PageNumBox.TextColor3 = Color3.fromRGB(255, 255, 255); UI.PageNumBox.TextScaled = true

    UI.SepLabel = Instance.new("TextLabel", UI.Under)
    UI.SepLabel.Name = "Sep"; UI.SepLabel.LayoutOrder = 3; UI.SepLabel.BackgroundTransparency = 1
    UI.SepLabel.Size = UDim2.new(0.34, 0, 0.94, 0); UI.SepLabel.Font = Enum.Font.GothamBold
    UI.SepLabel.Text = "/"; UI.SepLabel.TextColor3 = Color3.fromRGB(120, 120, 120); UI.SepLabel.TextScaled = true

    UI.PagesLabel = Instance.new("TextLabel", UI.Under)
    UI.PagesLabel.Name = "Total"; UI.PagesLabel.LayoutOrder = 4; UI.PagesLabel.BackgroundTransparency = 1
    UI.PagesLabel.Size = UDim2.new(0.16, 0, 0.81, 0); UI.PagesLabel.Font = Enum.Font.GothamBold
    UI.PagesLabel.Text = "1"; UI.PagesLabel.TextColor3 = Color3.fromRGB(180, 180, 180); UI.PagesLabel.TextScaled = true

    UI.RightBtn = Instance.new("ImageButton", UI.Under)
    UI.RightBtn.Name = "RightBtn"; UI.RightBtn.LayoutOrder = 5; UI.RightBtn.BackgroundTransparency = 1
    UI.RightBtn.Size = UDim2.new(0.17, 0, 0.94, 0); UI.RightBtn.Image = "rbxassetid://107938916240738"

    UI.Top = Instance.new("Frame", wheel)
    UI.Top.Name = "Top"; UI.Top.BackgroundColor3 = Color3.fromRGB(45, 45, 45); UI.Top.BackgroundTransparency = 0.1; UI.Top.BorderSizePixel = 0
    UI.Top.Position = State.config.HUDPositions.Top and UDim2.new(unpack(State.config.HUDPositions.Top)) or HUD.DefaultPositions.Top
    UI.Top.Size = UDim2.new(0.74, 0, 0.095, 0)
    Instance.new("UICorner", UI.Top).CornerRadius = UDim.new(0, 8)
    local ts = Instance.new("UIStroke", UI.Top); ts.Color = Color3.fromRGB(70, 70, 70); ts.Thickness = 1
    local tl = Instance.new("UIListLayout", UI.Top)
    tl.FillDirection = Enum.FillDirection.Horizontal; tl.HorizontalAlignment = Enum.HorizontalAlignment.Center; tl.VerticalAlignment = Enum.VerticalAlignment.Center

    UI.Search = Instance.new("TextBox", UI.Top)
    UI.Search.Name = "Search"; UI.Search.BackgroundTransparency = 1; UI.Search.Size = UDim2.new(0.87, 0, 0.82, 0)
    UI.Search.Font = Enum.Font.Gotham; UI.Search.PlaceholderText = "Search by name or ID..."
    UI.Search.PlaceholderColor3 = Color3.fromRGB(120, 120, 120); UI.Search.Text = ""
    UI.Search.TextColor3 = Color3.fromRGB(255, 255, 255); UI.Search.TextScaled = true

    UI.FavBtn, UI.FavBtnLabel = makeTextButton("Favorite", wheel,
        State.config.HUDPositions.FavBtn and UDim2.new(unpack(State.config.HUDPositions.FavBtn)) or HUD.DefaultPositions.FavBtn,
        UDim2.new(0.0875, 0, 0.0875, 0), "FAV")

    UI.ModeBtn, UI.ModeBtnLabel = makeTextButton("ModeToggle", wheel,
        State.config.HUDPositions.ModeBtn and UDim2.new(unpack(State.config.HUDPositions.ModeBtn)) or HUD.DefaultPositions.ModeBtn,
        UDim2.new(0.0875, 0, 0.0875, 0), "EMO")

    UI.AutoReapplyBtn, UI.AutoBtnLabel = makeTextButton("AutoReapplyToggle", wheel,
        State.config.HUDPositions.AutoBtn and UDim2.new(unpack(State.config.HUDPositions.AutoBtn)) or HUD.DefaultPositions.AutoBtn,
        UDim2.new(0.0875, 0, 0.0875, 0), "RE")

    UI.CustomAnimBtn, UI.CustomAnimBtnLabel = makeTextButton("CustomAnimToggle", wheel,
        State.config.HUDPositions.CustomAnimBtn and UDim2.new(unpack(State.config.HUDPositions.CustomAnimBtn)) or HUD.DefaultPositions.CustomAnimBtn,
        UDim2.new(0.0875, 0, 0.0875, 0), "CUS")

    UI.LeftBtn.MouseButton1Click:Connect(prevPage)
    UI.RightBtn.MouseButton1Click:Connect(nextPage)

    UI.PageNumBox.FocusLost:Connect(function()
        local num = tonumber(UI.PageNumBox.Text)
        if num then goToPage(num) else UI.PageNumBox.Text = tostring(State.currentPage) end
    end)

    local searchDebounce = nil
    UI.Search:GetPropertyChangedSignal("Text"):Connect(function()
        if searchDebounce then pcall(function() task.cancel(searchDebounce) end) end
        searchDebounce = task.delay(0.3, function() searchItems(UI.Search.Text); searchDebounce = nil end)
    end)

    UI.FavBtn.MouseButton1Click:Connect(toggleFavMode)
    UI.ModeBtn.MouseButton1Click:Connect(toggleMode)
    UI.AutoReapplyBtn.MouseButton1Click:Connect(toggleAutoReapply)
    UI.CustomAnimBtn.MouseButton1Click:Connect(openCustomAnimEditor)

    applyNativeTheme()
    State.guiCreated = true
    bindWheelHotkeys()
    setupGlobalWheelClick()

    return true
end

-- ============ DATA FETCHING ============ --
local function fetchEmotes()
    if State.isLoadingEmotes then return end
    State.isLoadingEmotes = true
    local ok, result = pcall(function() return HttpService:JSONDecode(game:HttpGet(EMOTE_URL)) end)
    if ok and result then
        local rawList = result.data or result; local data = {}
        for i = 1, #rawList do
            local item = rawList[i]; local id = tonumber(item.id)
            if id and id > 0 then data[#data + 1] = {id = id, name = item.name or ("Emote_" .. id)} end
        end
        State.emotesData = data; State.filteredEmotes = data
    end
    State.isLoadingEmotes = false
end

local function fetchAnims()
    if State.isLoadingAnims then return end
    State.isLoadingAnims = true
    local ok, result = pcall(function() return HttpService:JSONDecode(game:HttpGet(ANIM_URL)) end)
    if ok and result then
        local rawList = result.data or result; local data = {}
        for i = 1, #rawList do
            local item = rawList[i]; local id = tonumber(item.id)
            if id and id > 0 then data[#data + 1] = {id = id, name = item.name or ("Anim_" .. id), bundledItems = item.bundledItems} end
        end
        State.animsData = data; State.filteredAnims = data
    end
    State.isLoadingAnims = false
end

local function forceFullRefresh()
    State.lastDisplayPage = -1; State.lastDisplayMode = ""; State.lastDisplayFavVer = -1
    State.normalListCacheVersion = -1; State.wheelCache = nil; State.lastWheelCheck = 0
    State.totalPages = calcPages(); updatePageDisplay(); updateDisplay(true); applyNativeTheme()
end

local function onCharacterAdded(char)
    local hum = char:WaitForChild("Humanoid", 15)
    if not hum then return end
    local desc = hum:FindFirstChildOfClass("HumanoidDescription")
    if not desc then
        for i = 1, 30 do task.wait(0.1); desc = hum:FindFirstChildOfClass("HumanoidDescription"); if desc then break end end
    end

    currentLoadId = currentLoadId + 1; cleanupAllTracks(); loadedTracks = {}; State.currentEmoteTrack = nil
    State.applyingAnim = false
    originalAnimData = nil

    if State.autoReapplyEnabled then
        task.wait(1)

        captureOriginalAnims()

        local hasCustomSlots = State.config.CustomAnimSlots and next(State.config.CustomAnimSlots)
        local hasLastAnim = getgenv().lastAnim and getgenv().lastAnim.id

        if hasCustomSlots then
            reapplyCustomSlots()
        elseif hasLastAnim then
            applyAnim(getgenv().lastAnim)
        end
    end

    task.wait(0.8); forceFullRefresh()

    local wheel = getWheel()
    if wheel and not wheel:FindFirstChild("Under") then
        State.guiCreated = false; State.wheelCache = nil; task.wait(0.3)
        if getWheel() then createGUI(); forceFullRefresh() end
    end

    task.spawn(function()
        for i = 1, 10 do task.wait(0.5); if player.Character ~= char then return end; forceFullRefresh() end
    end)

    hum.Died:Connect(function()
        State.favEnabled = false; currentLoadId = currentLoadId + 1; cleanupAllTracks(); loadedTracks = {}
        State.applyingAnim = false; applyNativeTheme()
    end)
end

-- ============ RENDER LOOP ============ --
local frameCount = 0
RunService.RenderStepped:Connect(function()
    frameCount = frameCount + 1
    if frameCount >= 60 then
        frameCount = 0
        local wheel = getWheel()
        if not wheel then State.guiCreated = false; return end
        if not State.guiCreated or not wheel:FindFirstChild("Under") then
            State.guiCreated = false
            if createGUI() then forceFullRefresh() end
        else
            applyNativeTheme()
        end
    end
end)

-- ============ INIT ============ --
task.spawn(function()
    LoadConfig(); LoadThemes()
    while not getWheel() do task.wait(0.1) end

    if createGUI() then
        local rawEmoteFavs = loadFile(State.favFileName)
        local rawAnimFavs = loadFile(State.favAnimFileName)

        State.favEmotes = {}
        if type(rawEmoteFavs) == "table" then
            for _, v in ipairs(rawEmoteFavs) do
                if type(v) == "table" and v.id then State.favEmotes[#State.favEmotes + 1] = {id = v.id, name = v.name or ("Emote_" .. tostring(v.id))} end
            end
        end
        State.favAnims = {}
        if type(rawAnimFavs) == "table" then
            for _, v in ipairs(rawAnimFavs) do
                if type(v) == "table" and v.id then State.favAnims[#State.favAnims + 1] = {id = v.id, name = v.name or ("Anim_" .. tostring(v.id)), bundledItems = v.bundledItems} end
            end
        end

        rebuildFavLookup(); loadLastAnim(); fetchEmotes(); fetchAnims()
        task.wait(0.5)
        State.totalPages = calcPages(); updatePageDisplay(); updateDisplay(true); applyNativeTheme()
        notify("PinkWards", "Emote Sniper loaded successfully", 4)
    end
end)

player.CharacterAdded:Connect(onCharacterAdded)
if player.Character then task.spawn(function() onCharacterAdded(player.Character) end) end
StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Chat, true)

task.spawn(function()
    while true do
        pcall(function()
            local robloxGui = CoreGui:FindFirstChild("RobloxGui")
            local emotesMenu = robloxGui and robloxGui:FindFirstChild("EmotesMenu")
            if not emotesMenu then StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.EmotesMenu, true)
            else
                local wheel = getWheel()
                if wheel and not wheel:FindFirstChild("Under") then State.guiCreated = false; State.wheelCache = nil end
            end
        end)
        task.wait(2)
    end
end)
