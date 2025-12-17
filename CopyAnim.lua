-- Ultra-Clean Animation Copy Script v5.3 (Perfect Sync)
-- With Respawn Position Feature

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer

-- Settings
local CONFIG = {
    ToggleKey = Enum.KeyCode.H,
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

-- Animation storage
local loadedAnims = {}
local playingTracks = {}
local lastSyncTime = {}

-- Store original animate script
local animateScriptDisabled = false

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

-- Yes button
local yesButton = Instance.new("TextButton")
yesButton.Name = "YesButton"
yesButton.Size = UDim2.new(0, 130, 0, 40)
yesButton.BackgroundColor3 = Color3.fromRGB(0, 170, 127)
yesButton.BorderSizePixel = 0
yesButton.TextColor3 = Color3.new(1, 1, 1)
yesButton.TextSize = 15
yesButton.Font = Enum.Font.GothamBold
yesButton.Text = "✓  Yes, Teleport"
yesButton.AutoButtonColor = true
yesButton.Parent = buttonContainer

local yesCorner = Instance.new("UICorner")
yesCorner.CornerRadius = UDim.new(0, 8)
yesCorner.Parent = yesButton

-- No button
local noButton = Instance.new("TextButton")
noButton.Name = "NoButton"
noButton.Size = UDim2.new(0, 130, 0, 40)
noButton.BackgroundColor3 = Color3.fromRGB(60, 60, 65)
noButton.BorderSizePixel = 0
noButton.TextColor3 = Color3.new(1, 1, 1)
noButton.TextSize = 15
noButton.Font = Enum.Font.GothamBold
noButton.Text = "✕  No, Stay"
noButton.AutoButtonColor = true
noButton.Parent = buttonContainer

local noCorner = Instance.new("UICorner")
noCorner.CornerRadius = UDim.new(0, 8)
noCorner.Parent = noButton

screenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")

-- ═══════════════════════════════════════════════════════════════════
-- POPUP FUNCTIONS
-- ═══════════════════════════════════════════════════════════════════

local popupResult = nil
local popupActive = false

local function showPopup()
    popupResult = nil
    popupActive = true
    
    popupBox.Position = UDim2.new(0.5, -160, 0.5, -90)
    popupBox.Size = UDim2.new(0, 320, 0, 180)
    popupContainer.Visible = true
    
    popupBox.Position = UDim2.new(0.5, -160, 0.6, -90)
    popupBox:TweenPosition(
        UDim2.new(0.5, -160, 0.5, -90),
        Enum.EasingDirection.Out,
        Enum.EasingStyle.Back,
        0.3,
        true
    )
    
    local timeLeft = CONFIG.PopupTimeout
    
    task.spawn(function()
        while popupActive and timeLeft > 0 do
            timerText.Text = "Auto-closing in " .. timeLeft .. "s..."
            task.wait(1)
            timeLeft = timeLeft - 1
        end
        
        if popupActive then
            popupResult = false
            popupActive = false
        end
    end)
    
    while popupActive do
        task.wait(0.1)
    end
    
    popupBox:TweenPosition(
        UDim2.new(0.5, -160, 0.6, -90),
        Enum.EasingDirection.In,
        Enum.EasingStyle.Back,
        0.2,
        true
    )
    task.wait(0.2)
    popupContainer.Visible = false
    
    return popupResult
end

local function closePopup(result)
    popupResult = result
    popupActive = false
end

-- Button hover effects
local function addHoverEffect(button, normalColor, hoverColor)
    button.MouseEnter:Connect(function()
        TweenService:Create(button, TweenInfo.new(0.15), {BackgroundColor3 = hoverColor}):Play()
    end)
    
    button.MouseLeave:Connect(function()
        TweenService:Create(button, TweenInfo.new(0.15), {BackgroundColor3 = normalColor}):Play()
    end)
end

addHoverEffect(yesButton, Color3.fromRGB(0, 170, 127), Color3.fromRGB(0, 200, 150))
addHoverEffect(noButton, Color3.fromRGB(60, 60, 65), Color3.fromRGB(80, 80, 85))

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
    TweenService:Create(blackFrame, TweenInfo.new(CONFIG.BlackFadeTime), {BackgroundTransparency = 0}):Play()
    TweenService:Create(loadingText, TweenInfo.new(CONFIG.BlackFadeTime), {TextTransparency = 0}):Play()
    task.wait(CONFIG.BlackFadeTime)
end

local function fadeFromBlack()
    TweenService:Create(blackFrame, TweenInfo.new(CONFIG.FadeOutTime), {BackgroundTransparency = 1}):Play()
    TweenService:Create(loadingText, TweenInfo.new(CONFIG.FadeOutTime), {TextTransparency = 1}):Play()
    task.wait(CONFIG.FadeOutTime)
    loadingText.Text = ""
end

-- ═══════════════════════════════════════════════════════════════════
-- ANIMATION COPY FUNCTIONS
-- ═══════════════════════════════════════════════════════════════════

local function disableAnimateScript()
    local char = LocalPlayer.Character
    if not char then return end
    
    local animate = char:FindFirstChild("Animate")
    if animate then
        animate.Disabled = true
        animateScriptDisabled = true
    end
    
    local humanoid = char:FindFirstChild("Humanoid")
    if humanoid then
        local animator = humanoid:FindFirstChildOfClass("Animator")
        if animator then
            for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
                pcall(function()
                    track:Stop(0)
                end)
            end
        end
    end
end

local function enableAnimateScript()
    local char = LocalPlayer.Character
    if not char then return end
    
    local animate = char:FindFirstChild("Animate")
    if animate then
        animate.Disabled = false
    end
    
    animateScriptDisabled = false
end

local function getNearestPlayer()
    local myChar = LocalPlayer.Character
    if not myChar then return nil end
    
    local myRoot = myChar:FindFirstChild("HumanoidRootPart")
    if not myRoot then return nil end
    
    local nearest = nil
    local nearestDist = CONFIG.MaxDistance
    
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character then
            local root = player.Character:FindFirstChild("HumanoidRootPart")
            if root then
                local dist = (myRoot.Position - root.Position).Magnitude
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
    for animId, track in pairs(playingTracks) do
        pcall(function()
            track:Stop(0)
            track:Destroy()
        end)
    end
    playingTracks = {}
    lastSyncTime = {}
    
    for animId, anim in pairs(loadedAnims) do
        pcall(function()
            anim:Destroy()
        end)
    end
    loadedAnims = {}
    
    local char = LocalPlayer.Character
    if char then
        local humanoid = char:FindFirstChild("Humanoid")
        if humanoid then
            local animator = humanoid:FindFirstChildOfClass("Animator")
            if animator then
                for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
                    pcall(function()
                        track:Stop(0)
                    end)
                end
            end
        end
    end
    
    task.wait(0.1)
end

local function getAnimator()
    local char = LocalPlayer.Character
    if not char then return nil end
    
    local humanoid = char:FindFirstChild("Humanoid")
    if not humanoid then return nil end
    
    local animator = humanoid:FindFirstChildOfClass("Animator")
    if not animator then
        animator = Instance.new("Animator")
        animator.Parent = humanoid
    end
    
    return animator
end

local function copyAnimation(animId, targetTrack)
    local animator = getAnimator()
    if not animator then return end
    
    if not loadedAnims[animId] then
        local anim = Instance.new("Animation")
        anim.AnimationId = animId
        loadedAnims[animId] = anim
    end
    
    if not playingTracks[animId] then
        local success = pcall(function()
            local track = animator:LoadAnimation(loadedAnims[animId])
            track.Priority = Enum.AnimationPriority.Action4
            track:Play(0, 1, targetTrack.Speed)
            track.TimePosition = targetTrack.TimePosition
            playingTracks[animId] = track
            lastSyncTime[animId] = tick()
        end)
        
        if not success then return end
    end
    
    local myTrack = playingTracks[animId]
    if not myTrack then return end
    
    pcall(function()
        if math.abs(myTrack.Speed - targetTrack.Speed) > 0.001 then
            myTrack:AdjustSpeed(targetTrack.Speed)
        end
        
        if myTrack.WeightCurrent < 0.999 then
            myTrack:AdjustWeight(1, 0)
        end
        
        if targetTrack.Length > 0 then
            local timeDiff = math.abs(myTrack.TimePosition - targetTrack.TimePosition)
            local now = tick()
            local lastSync = lastSyncTime[animId] or 0
            
            if timeDiff > 0.016 or (now - lastSync) > 0.5 then
                myTrack.TimePosition = targetTrack.TimePosition
                lastSyncTime[animId] = now
            end
        end
    end)
end

-- ═══════════════════════════════════════════════════════════════════
-- POSITION SAVE FUNCTION
-- ═══════════════════════════════════════════════════════════════════

local function saveCurrentPosition()
    local char = LocalPlayer.Character
    if char then
        local root = char:FindFirstChild("HumanoidRootPart")
        if root then
            savedCFrame = root.CFrame
            return true
        end
    end
    return false
end

-- ═══════════════════════════════════════════════════════════════════
-- MAIN UPDATE LOOP
-- ═══════════════════════════════════════════════════════════════════

local function update()
    if not isCopying or isRespawning then return end
    
    local char = LocalPlayer.Character
    if not char then return end
    
    if not animateScriptDisabled then
        disableAnimateScript()
    end
    
    if not targetPlayer or not targetPlayer.Character then
        local newTarget = getNearestPlayer()
        if newTarget and newTarget ~= targetPlayer then
            completeCleanup()
            disableAnimateScript()
            targetPlayer = newTarget
            print("📌 Now copying: " .. targetPlayer.Name)
        end
    end
    
    if targetPlayer and (not targetPlayer.Character or not targetPlayer.Character:FindFirstChild("Humanoid")) then
        completeCleanup()
        targetPlayer = nil
        return
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
    
    local activeAnims = {}
    
    for _, track in ipairs(targetTracks) do
        if track.IsPlaying and track.Animation then
            local animId = track.Animation.AnimationId
            if animId and animId ~= "" then
                activeAnims[animId] = true
                copyAnimation(animId, track)
            end
        end
    end
    
    local toRemove = {}
    for animId, track in pairs(playingTracks) do
        if not activeAnims[animId] then
            table.insert(toRemove, animId)
        end
    end
    
    for _, animId in ipairs(toRemove) do
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
    playingTracks = {}
    loadedAnims = {}
    lastSyncTime = {}
    animateScriptDisabled = false
    
    local hum = char:WaitForChild("Humanoid", 10)
    local root = char:WaitForChild("HumanoidRootPart", 10)
    
    if not hum or not root then return end
    
    if savedCFrame then
        isRespawning = true
        
        task.wait(0.5)
        
        local wantsTeleport = showPopup()
        
        if wantsTeleport then
            fadeToBlack()
            
            task.wait(0.2)
            
            pcall(function()
                root.CFrame = savedCFrame
                root.Velocity = Vector3.zero
                root.RotVelocity = Vector3.zero
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
print("    🎭 Animation Copy v5.3 (Perfect Sync)")
print("═══════════════════════════════════════════")
print("    Press [H] to toggle")
print("")
print("    Features:")
print("    ✓ 100% frame-perfect sync")
print("    ✓ No twisted arms/legs")
print("    ✓ Auto-targets nearest player")
print("    ✓ Respawn position confirmation")
print("═══════════════════════════════════════════")
