-- Ultra-Clean Animation Copy Script v5.3 (OPTIMIZED)
-- With Respawn Position Feature

-- Cache services once
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer

-- Settings
local CONFIG = {
    ToggleKey = Enum.KeyCode.G,
    MaxDistance = 150,
    PopupTimeout = 10,
    BlackFadeTime = 0.3,
    FadeOutTime = 0.4,
}

-- State
local isCopying = false
local targetPlayer = nil
local mainConnection = nil
local savedCFrame = nil
local isRespawning = false
local animateScriptDisabled = false

-- Animation storage (use table.create for pre-allocation hint)
local loadedAnims = {}
local playingTracks = {}
local lastSyncTime = {}

-- Cache commonly used values
local ZERO_VECTOR = Vector3.zero
local ANIMATION_PRIORITY = Enum.AnimationPriority.Action4

-- Reusable TweenInfo objects (avoid creating new ones each time)
local TWEEN_FADE_IN = TweenInfo.new(CONFIG.BlackFadeTime)
local TWEEN_FADE_OUT = TweenInfo.new(CONFIG.FadeOutTime)
local TWEEN_HOVER = TweenInfo.new(0.15)
local TWEEN_POPUP_IN = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local TWEEN_POPUP_OUT = TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.In)

-- Cache character references
local cachedChar = nil
local cachedHumanoid = nil
local cachedAnimator = nil
local cachedRoot = nil

-- ═══════════════════════════════════════════════════════════════════
-- CHARACTER CACHE
-- ═══════════════════════════════════════════════════════════════════

local function updateCharacterCache()
    local char = LocalPlayer.Character
    if not char then
        cachedChar = nil
        cachedHumanoid = nil
        cachedAnimator = nil
        cachedRoot = nil
        return false
    end
    
    if char ~= cachedChar then
        cachedChar = char
        cachedHumanoid = char:FindFirstChild("Humanoid")
        cachedRoot = char:FindFirstChild("HumanoidRootPart")
        cachedAnimator = cachedHumanoid and cachedHumanoid:FindFirstChildOfClass("Animator")
    end
    
    return cachedHumanoid ~= nil and cachedRoot ~= nil
end

-- ═══════════════════════════════════════════════════════════════════
-- MINIMAL UI (Only for respawn popup)
-- ═══════════════════════════════════════════════════════════════════

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "AnimCopyGui"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 999
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

-- Black overlay for respawn
local blackFrame = Instance.new("Frame")
blackFrame.Name = "BlackOverlay"
blackFrame.Size = UDim2.new(1, 0, 1, 0)
blackFrame.BackgroundColor3 = Color3.new(0, 0, 0)
blackFrame.BackgroundTransparency = 1
blackFrame.BorderSizePixel = 0
blackFrame.Parent = screenGui

local loadingText = Instance.new("TextLabel")
loadingText.Size = UDim2.new(1, 0, 0, 50)
loadingText.Position = UDim2.new(0, 0, 0.5, -25)
loadingText.BackgroundTransparency = 1
loadingText.TextColor3 = Color3.new(1, 1, 1)
loadingText.TextSize = 20
loadingText.Font = Enum.Font.GothamBold
loadingText.Text = ""
loadingText.TextTransparency = 1
loadingText.Parent = blackFrame

-- Popup container
local popupContainer = Instance.new("Frame")
popupContainer.Name = "PopupContainer"
popupContainer.Size = UDim2.new(1, 0, 1, 0)
popupContainer.BackgroundTransparency = 1
popupContainer.Visible = false
popupContainer.Parent = screenGui

-- Dim background
local dimBackground = Instance.new("Frame")
dimBackground.Name = "DimBackground"
dimBackground.Size = UDim2.new(1, 0, 1, 0)
dimBackground.BackgroundColor3 = Color3.new(0, 0, 0)
dimBackground.BackgroundTransparency = 0.5
dimBackground.BorderSizePixel = 0
dimBackground.Parent = popupContainer

-- Popup box
local popupBox = Instance.new("Frame")
popupBox.Name = "PopupBox"
popupBox.Size = UDim2.new(0, 320, 0, 180)
popupBox.Position = UDim2.new(0.5, -160, 0.5, -90)
popupBox.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
popupBox.BorderSizePixel = 0
popupBox.Parent = popupContainer

local popupCorner = Instance.new("UICorner")
popupCorner.CornerRadius = UDim.new(0, 12)
popupCorner.Parent = popupBox

-- Popup shadow
local popupShadow = Instance.new("ImageLabel")
popupShadow.Name = "Shadow"
popupShadow.Size = UDim2.new(1, 30, 1, 30)
popupShadow.Position = UDim2.new(0, -15, 0, -15)
popupShadow.BackgroundTransparency = 1
popupShadow.Image = "rbxassetid://5554236805"
popupShadow.ImageColor3 = Color3.new(0, 0, 0)
popupShadow.ImageTransparency = 0.5
popupShadow.ScaleType = Enum.ScaleType.Slice
popupShadow.SliceCenter = Rect.new(23, 23, 277, 277)
popupShadow.ZIndex = -1
popupShadow.Parent = popupBox

-- Icon
local icon = Instance.new("TextLabel")
icon.Name = "Icon"
icon.Size = UDim2.new(0, 50, 0, 50)
icon.Position = UDim2.new(0.5, -25, 0, 15)
icon.BackgroundTransparency = 1
icon.Text = "📍"
icon.TextSize = 35
icon.Font = Enum.Font.GothamBold
icon.Parent = popupBox

-- Title
local popupTitle = Instance.new("TextLabel")
popupTitle.Name = "Title"
popupTitle.Size = UDim2.new(1, -20, 0, 25)
popupTitle.Position = UDim2.new(0, 10, 0, 65)
popupTitle.BackgroundTransparency = 1
popupTitle.TextColor3 = Color3.new(1, 1, 1)
popupTitle.TextSize = 18
popupTitle.Font = Enum.Font.GothamBold
popupTitle.Text = "Teleport Back?"
popupTitle.Parent = popupBox

-- Description
local popupDesc = Instance.new("TextLabel")
popupDesc.Name = "Description"
popupDesc.Size = UDim2.new(1, -20, 0, 20)
popupDesc.Position = UDim2.new(0, 10, 0, 90)
popupDesc.BackgroundTransparency = 1
popupDesc.TextColor3 = Color3.fromRGB(180, 180, 180)
popupDesc.TextSize = 14
popupDesc.Font = Enum.Font.Gotham
popupDesc.Text = "Return to your previous location?"
popupDesc.Parent = popupBox

-- Timer text
local timerText = Instance.new("TextLabel")
timerText.Name = "Timer"
timerText.Size = UDim2.new(1, -20, 0, 15)
timerText.Position = UDim2.new(0, 10, 0, 110)
timerText.BackgroundTransparency = 1
timerText.TextColor3 = Color3.fromRGB(120, 120, 120)
timerText.TextSize = 12
timerText.Font = Enum.Font.Gotham
timerText.Text = "Auto-closing in 10s..."
timerText.Parent = popupBox

-- Button container
local buttonContainer = Instance.new("Frame")
buttonContainer.Name = "Buttons"
buttonContainer.Size = UDim2.new(1, -20, 0, 40)
buttonContainer.Position = UDim2.new(0, 10, 1, -50)
buttonContainer.BackgroundTransparency = 1
buttonContainer.Parent = popupBox

local buttonLayout = Instance.new("UIListLayout")
buttonLayout.FillDirection = Enum.FillDirection.Horizontal
buttonLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
buttonLayout.Padding = UDim.new(0, 10)
buttonLayout.Parent = buttonContainer

-- Cache button colors
local YES_COLOR_NORMAL = Color3.fromRGB(0, 170, 127)
local YES_COLOR_HOVER = Color3.fromRGB(0, 200, 150)
local NO_COLOR_NORMAL = Color3.fromRGB(60, 60, 65)
local NO_COLOR_HOVER = Color3.fromRGB(80, 80, 85)

-- Yes button
local yesButton = Instance.new("TextButton")
yesButton.Name = "YesButton"
yesButton.Size = UDim2.new(0, 130, 0, 40)
yesButton.BackgroundColor3 = YES_COLOR_NORMAL
yesButton.BorderSizePixel = 0
yesButton.TextColor3 = Color3.new(1, 1, 1)
yesButton.TextSize = 15
yesButton.Font = Enum.Font.GothamBold
yesButton.Text = "✓  Yes, Teleport"
yesButton.AutoButtonColor = true
yesButton.Parent = buttonContainer

Instance.new("UICorner", yesButton).CornerRadius = UDim.new(0, 8)

-- No button
local noButton = Instance.new("TextButton")
noButton.Name = "NoButton"
noButton.Size = UDim2.new(0, 130, 0, 40)
noButton.BackgroundColor3 = NO_COLOR_NORMAL
noButton.BorderSizePixel = 0
noButton.TextColor3 = Color3.new(1, 1, 1)
noButton.TextSize = 15
noButton.Font = Enum.Font.GothamBold
noButton.Text = "✕  No, Stay"
noButton.AutoButtonColor = true
noButton.Parent = buttonContainer

Instance.new("UICorner", noButton).CornerRadius = UDim.new(0, 8)

screenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")

-- ═══════════════════════════════════════════════════════════════════
-- POPUP FUNCTIONS
-- ═══════════════════════════════════════════════════════════════════

local popupResult = nil
local popupActive = false

-- Cache popup positions
local POPUP_POS_CENTER = UDim2.new(0.5, -160, 0.5, -90)
local POPUP_POS_BELOW = UDim2.new(0.5, -160, 0.6, -90)

local function showPopup()
    popupResult = nil
    popupActive = true
    
    popupBox.Position = POPUP_POS_BELOW
    popupContainer.Visible = true
    
    TweenService:Create(popupBox, TWEEN_POPUP_IN, {Position = POPUP_POS_CENTER}):Play()
    
    local timeLeft = CONFIG.PopupTimeout
    
    task.spawn(function()
        while popupActive and timeLeft > 0 do
            timerText.Text = "Auto-closing in " .. timeLeft .. "s..."
            task.wait(1)
            timeLeft -= 1
        end
        
        if popupActive then
            popupResult = false
            popupActive = false
        end
    end)
    
    while popupActive do
        task.wait(0.1)
    end
    
    TweenService:Create(popupBox, TWEEN_POPUP_OUT, {Position = POPUP_POS_BELOW}):Play()
    task.wait(0.2)
    popupContainer.Visible = false
    
    return popupResult
end

local function closePopup(result)
    popupResult = result
    popupActive = false
end

-- Button hover effects (optimized with cached tweens)
yesButton.MouseEnter:Connect(function()
    TweenService:Create(yesButton, TWEEN_HOVER, {BackgroundColor3 = YES_COLOR_HOVER}):Play()
end)

yesButton.MouseLeave:Connect(function()
    TweenService:Create(yesButton, TWEEN_HOVER, {BackgroundColor3 = YES_COLOR_NORMAL}):Play()
end)

noButton.MouseEnter:Connect(function()
    TweenService:Create(noButton, TWEEN_HOVER, {BackgroundColor3 = NO_COLOR_HOVER}):Play()
end)

noButton.MouseLeave:Connect(function()
    TweenService:Create(noButton, TWEEN_HOVER, {BackgroundColor3 = NO_COLOR_NORMAL}):Play()
end)

yesButton.MouseButton1Click:Connect(function()
    closePopup(true)
end)

noButton.MouseButton1Click:Connect(function()
    closePopup(false)
end)

-- ═══════════════════════════════════════════════════════════════════
-- FADE FUNCTIONS
-- ═══════════════════════════════════════════════════════════════════

local function fadeToBlack()
    loadingText.Text = "⟳ Teleporting..."
    TweenService:Create(blackFrame, TWEEN_FADE_IN, {BackgroundTransparency = 0}):Play()
    TweenService:Create(loadingText, TWEEN_FADE_IN, {TextTransparency = 0}):Play()
    task.wait(CONFIG.BlackFadeTime)
end

local function fadeFromBlack()
    TweenService:Create(blackFrame, TWEEN_FADE_OUT, {BackgroundTransparency = 1}):Play()
    TweenService:Create(loadingText, TWEEN_FADE_OUT, {TextTransparency = 1}):Play()
    task.wait(CONFIG.FadeOutTime)
    loadingText.Text = ""
end

-- ═══════════════════════════════════════════════════════════════════
-- ANIMATION COPY FUNCTIONS
-- ═══════════════════════════════════════════════════════════════════

local function disableAnimateScript()
    if not cachedChar then return end
    
    local animate = cachedChar:FindFirstChild("Animate")
    if animate then
        animate.Disabled = true
        animateScriptDisabled = true
    end
    
    if cachedAnimator then
        local tracks = cachedAnimator:GetPlayingAnimationTracks()
        for i = 1, #tracks do
            pcall(function()
                tracks[i]:Stop(0)
            end)
        end
    end
end

local function enableAnimateScript()
    if not cachedChar then return end
    
    local animate = cachedChar:FindFirstChild("Animate")
    if animate then
        animate.Disabled = false
    end
    
    animateScriptDisabled = false
end

local function getNearestPlayer()
    if not cachedRoot then return nil end
    
    local myPos = cachedRoot.Position
    local nearest = nil
    local nearestDist = CONFIG.MaxDistance
    
    local players = Players:GetPlayers()
    for i = 1, #players do
        local player = players[i]
        if player ~= LocalPlayer and player.Character then
            local root = player.Character:FindFirstChild("HumanoidRootPart")
            if root then
                local dist = (myPos - root.Position).Magnitude
                if dist < nearestDist then
                    nearestDist = dist
                    nearest = player
                end
            end
        end
    end
    
    return nearest
end

local function completeCleanup()
    -- Stop and destroy playing tracks
    for animId, track in pairs(playingTracks) do
        pcall(function()
            track:Stop(0)
            track:Destroy()
        end)
    end
    table.clear(playingTracks)
    table.clear(lastSyncTime)
    
    -- Destroy loaded animations
    for animId, anim in pairs(loadedAnims) do
        pcall(function()
            anim:Destroy()
        end)
    end
    table.clear(loadedAnims)
    
    -- Stop all animator tracks
    if cachedAnimator then
        local tracks = cachedAnimator:GetPlayingAnimationTracks()
        for i = 1, #tracks do
            pcall(function()
                tracks[i]:Stop(0)
            end)
        end
    end
    
    task.wait(0.1)
end

local function getOrCreateAnimator()
    if cachedAnimator then return cachedAnimator end
    
    if not cachedHumanoid then return nil end
    
    cachedAnimator = cachedHumanoid:FindFirstChildOfClass("Animator")
    if not cachedAnimator then
        cachedAnimator = Instance.new("Animator")
        cachedAnimator.Parent = cachedHumanoid
    end
    
    return cachedAnimator
end

local function copyAnimation(animId, targetTrack)
    local animator = getOrCreateAnimator()
    if not animator then return end
    
    -- Create animation if not exists
    if not loadedAnims[animId] then
        local anim = Instance.new("Animation")
        anim.AnimationId = animId
        loadedAnims[animId] = anim
    end
    
    -- Load and play track if not exists
    if not playingTracks[animId] then
        local success = pcall(function()
            local track = animator:LoadAnimation(loadedAnims[animId])
            track.Priority = ANIMATION_PRIORITY
            track:Play(0, 1, targetTrack.Speed)
            track.TimePosition = targetTrack.TimePosition
            playingTracks[animId] = track
            lastSyncTime[animId] = tick()
        end)
        
        if not success then return end
    end
    
    local myTrack = playingTracks[animId]
    if not myTrack then return end
    
    -- Sync track properties
    pcall(function()
        local targetSpeed = targetTrack.Speed
        if math.abs(myTrack.Speed - targetSpeed) > 0.001 then
            myTrack:AdjustSpeed(targetSpeed)
        end
        
        if myTrack.WeightCurrent < 0.999 then
            myTrack:AdjustWeight(1, 0)
        end
        
        if targetTrack.Length > 0 then
            local targetTime = targetTrack.TimePosition
            local timeDiff = math.abs(myTrack.TimePosition - targetTime)
            local now = tick()
            local lastSync = lastSyncTime[animId] or 0
            
            if timeDiff > 0.016 or (now - lastSync) > 0.5 then
                myTrack.TimePosition = targetTime
                lastSyncTime[animId] = now
            end
        end
    end)
end

-- ═══════════════════════════════════════════════════════════════════
-- POSITION SAVE FUNCTION
-- ═══════════════════════════════════════════════════════════════════

local function saveCurrentPosition()
    if cachedRoot then
        savedCFrame = cachedRoot.CFrame
        return true
    end
    return false
end

-- ═══════════════════════════════════════════════════════════════════
-- MAIN UPDATE LOOP (OPTIMIZED)
-- ═══════════════════════════════════════════════════════════════════

-- Reusable table for active animations (avoid creating new table each frame)
local activeAnims = {}
local toRemove = {}

local function update()
    if not isCopying or isRespawning then return end
    
    if not updateCharacterCache() then return end
    
    if not animateScriptDisabled then
        disableAnimateScript()
    end
    
    -- Find new target if needed
    if not targetPlayer or not targetPlayer.Character then
        local newTarget = getNearestPlayer()
        if newTarget and newTarget ~= targetPlayer then
            completeCleanup()
            disableAnimateScript()
            targetPlayer = newTarget
            print("📌 Now copying: " .. targetPlayer.Name)
        end
    end
    
    -- Validate target
    if targetPlayer then
        local targetChar = targetPlayer.Character
        if not targetChar or not targetChar:FindFirstChild("Humanoid") then
            completeCleanup()
            targetPlayer = nil
            return
        end
    end
    
    if not targetPlayer then return end
    
    local targetHum = targetPlayer.Character:FindFirstChild("Humanoid")
    if not targetHum then return end
    
    local targetAnimator = targetHum:FindFirstChildOfClass("Animator")
    if not targetAnimator then return end
    
    local success, targetTracks = pcall(function()
        return targetAnimator:GetPlayingAnimationTracks()
    end)
    
    if not success or not targetTracks then return end
    
    -- Clear and reuse activeAnims table
    table.clear(activeAnims)
    
    -- Copy active animations
    for i = 1, #targetTracks do
        local track = targetTracks[i]
        if track.IsPlaying and track.Animation then
            local animId = track.Animation.AnimationId
            if animId and animId ~= "" then
                activeAnims[animId] = true
                copyAnimation(animId, track)
            end
        end
    end
    
    -- Find tracks to remove (reuse table)
    table.clear(toRemove)
    for animId, track in pairs(playingTracks) do
        if not activeAnims[animId] then
            toRemove[#toRemove + 1] = animId
        end
    end
    
    -- Remove inactive tracks
    for i = 1, #toRemove do
        local animId = toRemove[i]
        pcall(function()
            playingTracks[animId]:Stop(0)
            playingTracks[animId]:Destroy()
        end)
        playingTracks[animId] = nil
        lastSyncTime[animId] = nil
    end
end

-- ═══════════════════════════════════════════════════════════════════
-- TOGGLE FUNCTIONS
-- ═══════════════════════════════════════════════════════════════════

local function startCopying()
    if isCopying then return end
    isCopying = true
    
    updateCharacterCache()
    completeCleanup()
    disableAnimateScript()
    saveCurrentPosition()
    
    targetPlayer = getNearestPlayer()
    
    print("═══════════════════════════════════")
    print("✅ Animation Copy: ON")
    if targetPlayer then
        print("📌 Copying: " .. targetPlayer.Name)
    else
        print("🔍 Waiting for nearby player...")
    end
    print("📍 Position saved for respawn")
    print("═══════════════════════════════════")
    
    mainConnection = RunService.RenderStepped:Connect(update)
end

local function stopCopying()
    if not isCopying then return end
    isCopying = false
    
    if mainConnection then
        mainConnection:Disconnect()
        mainConnection = nil
    end
    
    completeCleanup()
    enableAnimateScript()
    
    targetPlayer = nil
    
    print("═══════════════════════════════════")
    print("❌ Animation Copy: OFF")
    print("═══════════════════════════════════")
end

local function toggle()
    if isCopying then
        stopCopying()
    else
        startCopying()
    end
end

-- ═══════════════════════════════════════════════════════════════════
-- INPUT HANDLING
-- ═══════════════════════════════════════════════════════════════════

UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    
    if input.KeyCode == CONFIG.ToggleKey then
        toggle()
    end
end)

-- ═══════════════════════════════════════════════════════════════════
-- CHARACTER RESPAWN WITH CONFIRMATION
-- ═══════════════════════════════════════════════════════════════════

LocalPlayer.CharacterAdded:Connect(function(char)
    -- Clear caches
    table.clear(playingTracks)
    table.clear(loadedAnims)
    table.clear(lastSyncTime)
    animateScriptDisabled = false
    
    -- Reset character cache
    cachedChar = nil
    cachedHumanoid = nil
    cachedAnimator = nil
    cachedRoot = nil
    
    local hum = char:WaitForChild("Humanoid", 10)
    local root = char:WaitForChild("HumanoidRootPart", 10)
    
    if not hum or not root then return end
    
    -- Update cache
    cachedChar = char
    cachedHumanoid = hum
    cachedRoot = root
    cachedAnimator = hum:FindFirstChildOfClass("Animator")
    
    if savedCFrame then
        isRespawning = true
        
        task.wait(0.5)
        
        local wantsTeleport = showPopup()
        
        if wantsTeleport then
            fadeToBlack()
            task.wait(0.2)
            
            pcall(function()
                root.CFrame = savedCFrame
                root.AssemblyLinearVelocity = ZERO_VECTOR
                root.AssemblyAngularVelocity = ZERO_VECTOR
            end)
            
            task.wait(0.2)
            
            if isCopying then
                disableAnimateScript()
            end
            
            fadeFromBlack()
            print("📍 Teleported to saved location")
        else
            savedCFrame = root.CFrame
            
            if isCopying then
                disableAnimateScript()
            end
            
            print("📍 Staying at spawn point (position updated)")
        end
        
        isRespawning = false
    else
        task.wait(0.3)
        if isCopying then
            disableAnimateScript()
        end
    end
end)

-- ═══════════════════════════════════════════════════════════════════
-- CLEANUP
-- ═══════════════════════════════════════════════════════════════════

Players.PlayerRemoving:Connect(function(player)
    if player == targetPlayer then
        completeCleanup()
        targetPlayer = nil
        print("⚠️ Target left the game")
    end
end)

-- ═══════════════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════════════

print("═══════════════════════════════════════════")
print("    🎭 Animation Copy v5.3 (OPTIMIZED)")
print("═══════════════════════════════════════════")
print("    Press [G] to toggle")
print("")
print("    Features:")
print("    ✓ 100% frame-perfect sync")
print("    ✓ No twisted arms/legs")
print("    ✓ Auto-targets nearest player")
print("    ✓ Respawn position confirmation")
print("    ✓ Optimized performance")
print("═══════════════════════════════════════════")
