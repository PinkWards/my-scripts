-- Animation Copy v9.3 - FIXED GROUND DETECTION
-- Only saves position when TRULY on walkable ground

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local LP = Players.LocalPlayer

-- CONFIG
local TOGGLE_KEY = Enum.KeyCode.G
local MAX_DIST = 150
local GROUND_SAVE_INTERVAL = 0.5

-- STATE
local copying = false
local target = nil
local savedGroundCF = nil
local respawning = false
local hasTarget = false

-- CACHE
local char, hum, animator, root = nil, nil, nil, nil
local targetChar, targetHum, targetAnimator, targetRoot = nil, nil, nil, nil

-- ANIMATION STORAGE
local tracks = {}

-- CONSTANTS
local V3_ZERO = Vector3.zero
local V3_DOWN = Vector3.new(0, -1, 0)

-- Reusable raycast params
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

-- ═══════════════════════════════════════════════════════════════════
-- GROUND DETECTION - FIXED
-- ═══════════════════════════════════════════════════════════════════

local lastGroundSave = 0
local stableGroundTime = 0
local STABLE_TIME_REQUIRED = 0.3  -- Must be on ground for 0.3 seconds

local function isOnSolidGround()
    if not root or not hum then return false end
    
    -- Check 1: Humanoid must say we're on ground
    if hum.FloorMaterial == Enum.Material.Air then return false end
    
    -- Check 2: Must not be jumping or falling
    local state = hum:GetState()
    if state == Enum.HumanoidStateType.Jumping then return false end
    if state == Enum.HumanoidStateType.Freefall then return false end
    if state == Enum.HumanoidStateType.Flying then return false end
    
    -- Check 3: Y velocity must be near zero (not moving up or down)
    local yVel = root.AssemblyLinearVelocity.Y
    if math.abs(yVel) > 5 then return false end
    
    -- Check 4: Raycast must hit ground very close (within 3.5 studs)
    rayParams.FilterDescendantsInstances = {char}
    local result = workspace:Raycast(root.Position, V3_DOWN * 3.5, rayParams)
    if not result then return false end
    
    -- Check 5: Ground must be walkable (not too steep)
    local groundNormal = result.Normal
    local upDot = groundNormal:Dot(Vector3.new(0, 1, 0))
    if upDot < 0.7 then return false end  -- Too steep
    
    -- Check 6: Must not be on another player
    local hitPart = result.Instance
    if hitPart then
        local model = hitPart:FindFirstAncestorOfClass("Model")
        if model and Players:GetPlayerFromCharacter(model) then
            return false  -- Standing on a player
        end
    end
    
    return true
end

local function getGroundPosition()
    if not root then return nil end
    
    rayParams.FilterDescendantsInstances = {char}
    local result = workspace:Raycast(root.Position, V3_DOWN * 10, rayParams)
    
    if result then
        local hipHeight = hum and hum.HipHeight or 2
        local groundPos = result.Position + Vector3.new(0, hipHeight + 2.5, 0)
        return CFrame.new(groundPos) * CFrame.Angles(0, math.rad(root.Orientation.Y), 0)
    end
    return nil
end

local function autoSaveGroundPosition()
    if respawning or not root or not hum then return end
    
    local now = tick()
    
    -- Check if on solid ground
    if isOnSolidGround() then
        -- Increment stable time
        stableGroundTime += RunService.Heartbeat:Wait()
        
        -- Only save if stable for required time AND interval passed
        if stableGroundTime >= STABLE_TIME_REQUIRED then
            if now - lastGroundSave >= GROUND_SAVE_INTERVAL then
                local groundCF = getGroundPosition()
                if groundCF then
                    savedGroundCF = groundCF
                    lastGroundSave = now
                end
            end
        end
    else
        -- Reset stable time when not on ground
        stableGroundTime = 0
    end
end

-- ═══════════════════════════════════════════════════════════════════
-- CACHE FUNCTIONS
-- ═══════════════════════════════════════════════════════════════════

local function cacheLocal()
    local c = LP.Character
    if not c then
        char, hum, animator, root = nil, nil, nil, nil
        return false
    end
    
    char = c
    hum = c:FindFirstChildOfClass("Humanoid")
    root = c:FindFirstChild("HumanoidRootPart")
    
    if hum then
        animator = hum:FindFirstChildOfClass("Animator")
        if not animator then
            animator = Instance.new("Animator")
            animator.Parent = hum
        end
    end
    
    return hum ~= nil and root ~= nil and animator ~= nil
end

local function cacheTarget()
    if not target then
        targetChar, targetHum, targetAnimator, targetRoot = nil, nil, nil, nil
        return false
    end
    
    local tc = target.Character
    if not tc then
        targetChar, targetHum, targetAnimator, targetRoot = nil, nil, nil, nil
        return false
    end
    
    targetChar = tc
    targetHum = tc:FindFirstChildOfClass("Humanoid")
    targetRoot = tc:FindFirstChild("HumanoidRootPart")
    
    if targetHum then
        targetAnimator = targetHum:FindFirstChildOfClass("Animator")
    end
    
    return targetHum ~= nil and targetAnimator ~= nil and targetRoot ~= nil
end

-- ═══════════════════════════════════════════════════════════════════
-- ANIMATE SCRIPT CONTROL
-- ═══════════════════════════════════════════════════════════════════

local function disableAnimate()
    if not char then return end
    
    local animate = char:FindFirstChild("Animate")
    if animate and animate:IsA("LocalScript") then
        animate.Disabled = true
    end
    
    if animator then
        for _, track in animator:GetPlayingAnimationTracks() do
            track:Stop(0.1)
        end
    end
end

local function enableAnimate()
    if not char then return end
    
    local animate = char:FindFirstChild("Animate")
    if animate and animate:IsA("LocalScript") then
        animate.Disabled = false
    end
end

-- ═══════════════════════════════════════════════════════════════════
-- CLEAN ANIMATION SYNC
-- ═══════════════════════════════════════════════════════════════════

local function cleanSync()
    if not copying or respawning or not hasTarget then return end
    if not animator or not targetAnimator then return end
    
    local ok, targetTracks = pcall(targetAnimator.GetPlayingAnimationTracks, targetAnimator)
    if not ok or not targetTracks then return end
    
    local currentActive = {}
    
    for _, targetTrack in targetTracks do
        if targetTrack.IsPlaying and targetTrack.Animation then
            local animId = targetTrack.Animation.AnimationId
            if animId and animId ~= "" then
                currentActive[animId] = targetTrack
            end
        end
    end
    
    for animId, myTrack in pairs(tracks) do
        if not currentActive[animId] then
            myTrack:Stop(0.1)
            myTrack:Destroy()
            tracks[animId] = nil
        end
    end
    
    for animId, targetTrack in pairs(currentActive) do
        local myTrack = tracks[animId]
        
        if not myTrack then
            local anim = Instance.new("Animation")
            anim.AnimationId = animId
            
            local success, newTrack = pcall(animator.LoadAnimation, animator, anim)
            if success and newTrack then
                newTrack.Priority = Enum.AnimationPriority.Action4
                myTrack = newTrack
                tracks[animId] = myTrack
                myTrack:Play(0.1, targetTrack.WeightCurrent, targetTrack.Speed)
            end
            
            anim:Destroy()
        end
        
        if myTrack then
            local timeDiff = math.abs(myTrack.TimePosition - targetTrack.TimePosition)
            if timeDiff > 0.05 then
                myTrack.TimePosition = targetTrack.TimePosition
            end
            
            if myTrack.Speed ~= targetTrack.Speed then
                myTrack:AdjustSpeed(targetTrack.Speed)
            end
            
            local weightDiff = math.abs(myTrack.WeightCurrent - targetTrack.WeightCurrent)
            if weightDiff > 0.05 then
                myTrack:AdjustWeight(targetTrack.WeightCurrent, 0.1)
            end
            
            if not myTrack.IsPlaying then
                myTrack:Play(0.1, targetTrack.WeightCurrent, targetTrack.Speed)
            end
        end
    end
end

-- ═══════════════════════════════════════════════════════════════════
-- STOP ALL ANIMATIONS
-- ═══════════════════════════════════════════════════════════════════

local function stopAllTracks()
    for animId, track in pairs(tracks) do
        if track then
            track:Stop(0.1)
            track:Destroy()
        end
    end
    table.clear(tracks)
    
    if animator then
        for _, track in animator:GetPlayingAnimationTracks() do
            track:Stop(0.1)
        end
    end
end

-- ═══════════════════════════════════════════════════════════════════
-- FIND NEAREST PLAYER
-- ═══════════════════════════════════════════════════════════════════

local function findNearest()
    if not root then return nil end
    
    local myPos = root.Position
    local bestPlayer, bestDist = nil, MAX_DIST
    
    for _, player in Players:GetPlayers() do
        if player ~= LP and player.Character then
            local playerRoot = player.Character:FindFirstChild("HumanoidRootPart")
            if playerRoot then
                local dist = (myPos - playerRoot.Position).Magnitude
                if dist < bestDist then
                    bestPlayer = player
                    bestDist = dist
                end
            end
        end
    end
    
    return bestPlayer
end

-- ═══════════════════════════════════════════════════════════════════
-- LOOPS
-- ═══════════════════════════════════════════════════════════════════

RunService.RenderStepped:Connect(function()
    if copying and hasTarget and not respawning then
        cleanSync()
    end
end)

RunService.Heartbeat:Connect(function()
    autoSaveGroundPosition()
end)

local cacheTimer = 0
RunService.Heartbeat:Connect(function(dt)
    if not copying then return end
    
    cacheTimer += dt
    if cacheTimer < 1 then return end
    cacheTimer = 0
    
    if hasTarget and target then
        if not target.Parent then
            print("⚠️ Target left")
            hasTarget = false
            target = nil
            stopAllTracks()
            enableAnimate()
        elseif target.Character ~= targetChar then
            cacheTarget()
        end
    end
end)

-- ═══════════════════════════════════════════════════════════════════
-- TARGET HANDLING
-- ═══════════════════════════════════════════════════════════════════

local targetConnections = {}

local function cleanupTargetConnections()
    for _, conn in pairs(targetConnections) do
        if conn then conn:Disconnect() end
    end
    table.clear(targetConnections)
end

local function setupTargetConnections()
    cleanupTargetConnections()
    
    if not target then return end
    
    targetConnections.charAdded = target.CharacterAdded:Connect(function()
        task.wait(0.5)
        cacheTarget()
        if copying and hasTarget then
            disableAnimate()
            print("✅ Target respawned")
        end
    end)
    
    if target.Character then
        local targetHumanoid = target.Character:FindFirstChildOfClass("Humanoid")
        if targetHumanoid then
            targetConnections.died = targetHumanoid.Died:Connect(function()
                print("⏳ Target died...")
                stopAllTracks()
            end)
        end
    end
end

-- ═══════════════════════════════════════════════════════════════════
-- START / STOP
-- ═══════════════════════════════════════════════════════════════════

local function start()
    if copying then return end
    
    if not cacheLocal() then
        print("❌ No character")
        return
    end
    
    local nearest = findNearest()
    if not nearest then
        print("❌ No player nearby")
        return
    end
    
    target = nearest
    
    if not cacheTarget() then
        print("❌ Target has no animator")
        target = nil
        return
    end
    
    copying = true
    hasTarget = true
    
    stopAllTracks()
    disableAnimate()
    setupTargetConnections()
    
    -- Only save if truly on ground
    if isOnSolidGround() then
        savedGroundCF = getGroundPosition()
    end
    
    print("═══════════════════════════════════════")
    print("  ✅ COPYING: " .. target.Name)
    print("  📌 Press [G] to stop")
    print("═══════════════════════════════════════")
end

local function stop()
    if not copying then return end
    
    copying = false
    hasTarget = false
    
    cleanupTargetConnections()
    stopAllTracks()
    enableAnimate()
    
    target = nil
    targetChar = nil
    targetHum = nil
    targetAnimator = nil
    targetRoot = nil
    
    print("═══════════════════════════════════════")
    print("  ❌ STOPPED")
    print("═══════════════════════════════════════")
end

-- ═══════════════════════════════════════════════════════════════════
-- INPUT
-- ═══════════════════════════════════════════════════════════════════

UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.KeyCode == TOGGLE_KEY then
        if copying then stop() else start() end
    end
end)

-- ═══════════════════════════════════════════════════════════════════
-- PLAYER LEFT
-- ═══════════════════════════════════════════════════════════════════

Players.PlayerRemoving:Connect(function(player)
    if player == target then
        print("⚠️ Target left")
        stop()
    end
end)

-- ═══════════════════════════════════════════════════════════════════
-- GUI
-- ═══════════════════════════════════════════════════════════════════

local gui = Instance.new("ScreenGui")
gui.Name = "AnimCopy"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 999
gui.Parent = LP:WaitForChild("PlayerGui")

local status = Instance.new("TextLabel")
status.Size = UDim2.fromOffset(180, 28)
status.Position = UDim2.fromOffset(10, 10)
status.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
status.BackgroundTransparency = 0.3
status.TextColor3 = Color3.fromRGB(255, 255, 255)
status.Font = Enum.Font.GothamBold
status.TextSize = 12
status.Text = ""
status.Visible = false
status.Parent = gui
Instance.new("UICorner", status).CornerRadius = UDim.new(0, 6)

local statusStroke = Instance.new("UIStroke")
statusStroke.Color = Color3.fromRGB(60, 60, 70)
statusStroke.Thickness = 1
statusStroke.Parent = status

local groundLabel = Instance.new("TextLabel")
groundLabel.Size = UDim2.fromOffset(180, 20)
groundLabel.Position = UDim2.fromOffset(10, 42)
groundLabel.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
groundLabel.BackgroundTransparency = 0.5
groundLabel.TextColor3 = Color3.fromRGB(150, 200, 255)
groundLabel.Font = Enum.Font.Gotham
groundLabel.TextSize = 10
groundLabel.Text = ""
groundLabel.Visible = false
groundLabel.Parent = gui
Instance.new("UICorner", groundLabel).CornerRadius = UDim.new(0, 4)

-- Ground status indicator
local groundStatus = Instance.new("TextLabel")
groundStatus.Size = UDim2.fromOffset(180, 16)
groundStatus.Position = UDim2.fromOffset(10, 64)
groundStatus.BackgroundTransparency = 1
groundStatus.TextColor3 = Color3.fromRGB(100, 255, 100)
groundStatus.Font = Enum.Font.Gotham
groundStatus.TextSize = 9
groundStatus.Text = ""
groundStatus.Visible = false
groundStatus.Parent = gui

local popup = Instance.new("Frame")
popup.Size = UDim2.new(1, 0, 1, 0)
popup.BackgroundTransparency = 1
popup.Visible = false
popup.Parent = gui

local popupDim = Instance.new("Frame")
popupDim.Size = UDim2.new(1, 0, 1, 0)
popupDim.BackgroundColor3 = Color3.new(0, 0, 0)
popupDim.BackgroundTransparency = 0.5
popupDim.BorderSizePixel = 0
popupDim.Parent = popup

local popupBox = Instance.new("Frame")
popupBox.Size = UDim2.fromOffset(280, 140)
popupBox.Position = UDim2.new(0.5, -140, 0.5, -70)
popupBox.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
popupBox.BorderSizePixel = 0
popupBox.Parent = popup
Instance.new("UICorner", popupBox).CornerRadius = UDim.new(0, 10)

local popupTitle = Instance.new("TextLabel")
popupTitle.Size = UDim2.new(1, 0, 0, 30)
popupTitle.Position = UDim2.fromOffset(0, 15)
popupTitle.BackgroundTransparency = 1
popupTitle.TextColor3 = Color3.new(1, 1, 1)
popupTitle.Font = Enum.Font.GothamBold
popupTitle.TextSize = 14
popupTitle.Text = "📍 Teleport back?"
popupTitle.Parent = popupBox

local popupPos = Instance.new("TextLabel")
popupPos.Size = UDim2.new(1, 0, 0, 20)
popupPos.Position = UDim2.fromOffset(0, 45)
popupPos.BackgroundTransparency = 1
popupPos.TextColor3 = Color3.fromRGB(150, 200, 255)
popupPos.Font = Enum.Font.Gotham
popupPos.TextSize = 11
popupPos.Text = ""
popupPos.Parent = popupBox

local popupTimer = Instance.new("TextLabel")
popupTimer.Size = UDim2.new(1, 0, 0, 20)
popupTimer.Position = UDim2.fromOffset(0, 65)
popupTimer.BackgroundTransparency = 1
popupTimer.TextColor3 = Color3.fromRGB(150, 150, 150)
popupTimer.Font = Enum.Font.Gotham
popupTimer.TextSize = 10
popupTimer.Text = ""
popupTimer.Parent = popupBox

local btnYes = Instance.new("TextButton")
btnYes.Size = UDim2.fromOffset(100, 32)
btnYes.Position = UDim2.new(0.5, -110, 1, -45)
btnYes.BackgroundColor3 = Color3.fromRGB(0, 150, 100)
btnYes.BorderSizePixel = 0
btnYes.TextColor3 = Color3.new(1, 1, 1)
btnYes.Font = Enum.Font.GothamBold
btnYes.TextSize = 12
btnYes.Text = "✓ Yes"
btnYes.Parent = popupBox
Instance.new("UICorner", btnYes).CornerRadius = UDim.new(0, 6)

local btnNo = Instance.new("TextButton")
btnNo.Size = UDim2.fromOffset(100, 32)
btnNo.Position = UDim2.new(0.5, 10, 1, -45)
btnNo.BackgroundColor3 = Color3.fromRGB(60, 60, 65)
btnNo.BorderSizePixel = 0
btnNo.TextColor3 = Color3.new(1, 1, 1)
btnNo.Font = Enum.Font.GothamBold
btnNo.TextSize = 12
btnNo.Text = "✕ No"
btnNo.Parent = popupBox
Instance.new("UICorner", btnNo).CornerRadius = UDim.new(0, 6)

local fadeScreen = Instance.new("Frame")
fadeScreen.Size = UDim2.new(1, 0, 1, 0)
fadeScreen.BackgroundColor3 = Color3.new(0, 0, 0)
fadeScreen.BackgroundTransparency = 1
fadeScreen.BorderSizePixel = 0
fadeScreen.Parent = gui

local popupResult = nil
local popupActive = false

local function showTeleportPopup()
    if not savedGroundCF then return false end
    
    popupResult = nil
    popupActive = true
    popup.Visible = true
    
    local pos = savedGroundCF.Position
    popupPos.Text = string.format("Position: %.0f, %.0f, %.0f", pos.X, pos.Y, pos.Z)
    
    local countdown = 10
    task.spawn(function()
        while popupActive and countdown > 0 do
            popupTimer.Text = countdown .. "s..."
            task.wait(1)
            countdown -= 1
        end
        if popupActive then
            popupResult = false
            popupActive = false
        end
    end)
    
    while popupActive do task.wait() end
    popup.Visible = false
    
    return popupResult == true
end

btnYes.MouseButton1Click:Connect(function()
    popupResult = true
    popupActive = false
end)

btnNo.MouseButton1Click:Connect(function()
    popupResult = false
    popupActive = false
end)

local function teleportToSaved()
    if not root or not savedGroundCF then return end
    
    TweenService:Create(fadeScreen, TweenInfo.new(0.15), {BackgroundTransparency = 0}):Play()
    task.wait(0.15)
    
    root.CFrame = savedGroundCF
    root.AssemblyLinearVelocity = V3_ZERO
    root.AssemblyAngularVelocity = V3_ZERO
    
    task.wait(0.05)
    TweenService:Create(fadeScreen, TweenInfo.new(0.15), {BackgroundTransparency = 1}):Play()
end

-- Status update with ground indicator
task.spawn(function()
    while true do
        task.wait(0.1)
        
        if copying and hasTarget and target then
            status.Visible = true
            status.Text = "⚡ Copying: " .. target.Name
            status.TextColor3 = Color3.fromRGB(100, 255, 150)
            
            if savedGroundCF then
                groundLabel.Visible = true
                local pos = savedGroundCF.Position
                groundLabel.Text = string.format("📍 %.0f, %.0f, %.0f", pos.X, pos.Y, pos.Z)
            else
                groundLabel.Visible = false
            end
            
            -- Show ground status
            groundStatus.Visible = true
            if isOnSolidGround() then
                groundStatus.Text = "🟢 On solid ground"
                groundStatus.TextColor3 = Color3.fromRGB(100, 255, 100)
            else
                groundStatus.Text = "🔴 In air (not saving)"
                groundStatus.TextColor3 = Color3.fromRGB(255, 100, 100)
            end
        elseif copying then
            status.Visible = true
            status.Text = "⏳ Waiting..."
            status.TextColor3 = Color3.fromRGB(255, 200, 100)
            groundLabel.Visible = false
            groundStatus.Visible = false
        else
            status.Visible = false
            groundLabel.Visible = false
            groundStatus.Visible = false
        end
    end
end)

-- ═══════════════════════════════════════════════════════════════════
-- CHARACTER RESPAWN
-- ═══════════════════════════════════════════════════════════════════

LP.CharacterAdded:Connect(function(newChar)
    table.clear(tracks)
    char, hum, animator, root = nil, nil, nil, nil
    stableGroundTime = 0
    
    local newHum = newChar:WaitForChild("Humanoid", 10)
    local newRoot = newChar:WaitForChild("HumanoidRootPart", 10)
    if not newHum or not newRoot then return end
    
    char = newChar
    hum = newHum
    root = newRoot
    
    animator = newHum:FindFirstChildOfClass("Animator")
    if not animator then
        animator = Instance.new("Animator")
        animator.Parent = newHum
    end
    
    if savedGroundCF then
        respawning = true
        task.wait(0.3)
        
        if showTeleportPopup() then
            teleportToSaved()
            print("📍 Teleported!")
        else
            task.wait(0.5)
            if isOnSolidGround() then
                savedGroundCF = getGroundPosition()
            end
        end
        
        respawning = false
    end
    
    task.wait(0.2)
    if copying and hasTarget then
        cacheTarget()
        disableAnimate()
    end
end)

-- ═══════════════════════════════════════════════════════════════════
-- INIT
-- ═══════════════════════════════════════════════════════════════════

cacheLocal()

print("═══════════════════════════════════════════════")
print("  🎭 Animation Copy v9.3 - FIXED GROUND")
print("═══════════════════════════════════════════════")
print("  Press [G] to toggle")
print("")
print("  ✅ Only saves when TRULY on ground:")
print("    • FloorMaterial not Air")
print("    • Not jumping/falling")
print("    • Y velocity near zero")
print("    • Raycast hits close ground")
print("    • Ground not too steep")
print("    • Not standing on players")
print("    • Stable for 0.3 seconds")
print("═══════════════════════════════════════════════")
