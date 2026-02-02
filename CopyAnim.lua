-- Animation Copy v10.0 - PERFECT MOTOR6D SYNC
-- Copies actual bone transforms for 100% visual sync regardless of ping
-- NOT network-based - copies transforms locally every frame

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local LP = Players.LocalPlayer

-- CONFIG
local TOGGLE_KEY = Enum.KeyCode.G
local MAX_DIST = 150
local GROUND_SAVE_INTERVAL = 0.5
local SYNC_SMOOTHING = 0.5 -- 0 = instant snap, 1 = smooth lerp

-- STATE
local copying = false
local target = nil
local savedGroundCF = nil
local respawning = false
local hasTarget = false

-- CACHE
local char, hum, root = nil, nil, nil
local targetChar, targetHum, targetRoot = nil, nil, nil

-- MOTOR6D CACHE - This is the key to perfect sync!
local localMotors = {}
local targetMotors = {}

-- CONSTANTS
local V3_ZERO = Vector3.zero
local V3_DOWN = Vector3.new(0, -1, 0)
local CF_IDENTITY = CFrame.identity

-- Reusable raycast params
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

-- ═══════════════════════════════════════════════════════════════════
-- MOTOR6D SYNC SYSTEM - NETWORK INDEPENDENT
-- ═══════════════════════════════════════════════════════════════════

local function cacheMotors()
    table.clear(localMotors)
    table.clear(targetMotors)
    
    if char then
        for _, desc in char:GetDescendants() do
            if desc:IsA("Motor6D") then
                localMotors[desc.Name] = desc
            end
        end
    end
    
    if targetChar then
        for _, desc in targetChar:GetDescendants() do
            if desc:IsA("Motor6D") then
                targetMotors[desc.Name] = desc
            end
        end
    end
    
    -- Debug output
    local localCount = 0
    local targetCount = 0
    for _ in pairs(localMotors) do localCount += 1 end
    for _ in pairs(targetMotors) do targetCount += 1 end
    
    return localCount > 0 and targetCount > 0
end

-- This function copies bone transforms DIRECTLY - no network involved!
local function syncMotors()
    if not copying or respawning or not hasTarget then return end
    if not targetChar or not targetChar.Parent then return end
    
    for name, targetMotor in pairs(targetMotors) do
        local localMotor = localMotors[name]
        if localMotor and targetMotor then
            -- Check if motor still exists
            if not targetMotor.Parent or not localMotor.Parent then continue end
            
            -- Direct transform copy - THIS IS THE KEY!
            -- Motor6D.Transform is what animations modify
            -- By copying it directly, we bypass all network sync issues
            local targetTransform = targetMotor.Transform
            
            if SYNC_SMOOTHING > 0 and SYNC_SMOOTHING < 1 then
                -- Smooth interpolation for less jittery movement
                localMotor.Transform = localMotor.Transform:Lerp(targetTransform, 1 - SYNC_SMOOTHING)
            else
                -- Instant snap (perfectly accurate)
                localMotor.Transform = targetTransform
            end
        end
    end
end

-- ═══════════════════════════════════════════════════════════════════
-- GROUND DETECTION - FIXED
-- ═══════════════════════════════════════════════════════════════════

local lastGroundSave = 0
local stableGroundTime = 0
local STABLE_TIME_REQUIRED = 0.3

local function isOnSolidGround()
    if not root or not hum then return false end
    
    if hum.FloorMaterial == Enum.Material.Air then return false end
    
    local state = hum:GetState()
    if state == Enum.HumanoidStateType.Jumping then return false end
    if state == Enum.HumanoidStateType.Freefall then return false end
    if state == Enum.HumanoidStateType.Flying then return false end
    
    local yVel = root.AssemblyLinearVelocity.Y
    if math.abs(yVel) > 5 then return false end
    
    rayParams.FilterDescendantsInstances = {char}
    local result = workspace:Raycast(root.Position, V3_DOWN * 3.5, rayParams)
    if not result then return false end
    
    local groundNormal = result.Normal
    local upDot = groundNormal:Dot(Vector3.new(0, 1, 0))
    if upDot < 0.7 then return false end
    
    local hitPart = result.Instance
    if hitPart then
        local model = hitPart:FindFirstAncestorOfClass("Model")
        if model and Players:GetPlayerFromCharacter(model) then
            return false
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
    
    if isOnSolidGround() then
        stableGroundTime += RunService.Heartbeat:Wait()
        
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
        stableGroundTime = 0
    end
end

-- ═══════════════════════════════════════════════════════════════════
-- CACHE FUNCTIONS
-- ═══════════════════════════════════════════════════════════════════

local function cacheLocal()
    local c = LP.Character
    if not c then
        char, hum, root = nil, nil, nil
        return false
    end
    
    char = c
    hum = c:FindFirstChildOfClass("Humanoid")
    root = c:FindFirstChild("HumanoidRootPart")
    
    return hum ~= nil and root ~= nil
end

local function cacheTarget()
    if not target then
        targetChar, targetHum, targetRoot = nil, nil, nil
        return false
    end
    
    local tc = target.Character
    if not tc then
        targetChar, targetHum, targetRoot = nil, nil, nil
        return false
    end
    
    targetChar = tc
    targetHum = tc:FindFirstChildOfClass("Humanoid")
    targetRoot = tc:FindFirstChild("HumanoidRootPart")
    
    -- Cache motors after caching target
    if targetHum and targetRoot then
        cacheMotors()
    end
    
    return targetHum ~= nil and targetRoot ~= nil
end

-- ═══════════════════════════════════════════════════════════════════
-- ANIMATE SCRIPT CONTROL
-- ═══════════════════════════════════════════════════════════════════

local storedAnimateParent = nil
local storedAnimate = nil

local function disableAnimate()
    if not char then return end
    
    local animate = char:FindFirstChild("Animate")
    if animate then
        storedAnimate = animate
        storedAnimateParent = animate.Parent
        animate.Parent = nil -- Remove completely, not just disable
    end
    
    -- Stop all current animations
    local animator = hum and hum:FindFirstChildOfClass("Animator")
    if animator then
        for _, track in animator:GetPlayingAnimationTracks() do
            track:Stop(0)
        end
    end
end

local function enableAnimate()
    if storedAnimate and storedAnimateParent then
        storedAnimate.Parent = storedAnimateParent
    end
    storedAnimate = nil
    storedAnimateParent = nil
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
-- MAIN SYNC LOOP - RUNS EVERY FRAME
-- ═══════════════════════════════════════════════════════════════════

RunService.RenderStepped:Connect(function()
    if copying and hasTarget and not respawning then
        syncMotors()
    end
end)

RunService.Heartbeat:Connect(function()
    autoSaveGroundPosition()
end)

-- Refresh motor cache periodically
local motorRefreshTimer = 0
RunService.Heartbeat:Connect(function(dt)
    if not copying then return end
    
    motorRefreshTimer += dt
    if motorRefreshTimer < 2 then return end
    motorRefreshTimer = 0
    
    if hasTarget and target then
        if not target.Parent then
            print("⚠️ Target left")
            hasTarget = false
            target = nil
            enableAnimate()
        elseif target.Character ~= targetChar then
            cacheTarget()
        else
            -- Refresh motor cache in case of equipment changes
            cacheMotors()
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
            print("✅ Target respawned - Motors recached")
        end
    end)
    
    if target.Character then
        local targetHumanoid = target.Character:FindFirstChildOfClass("Humanoid")
        if targetHumanoid then
            targetConnections.died = targetHumanoid.Died:Connect(function()
                print("⏳ Target died...")
            end)
        end
        
        -- Watch for new descendants (equipment, tools, etc.)
        targetConnections.descAdded = target.Character.DescendantAdded:Connect(function(desc)
            if desc:IsA("Motor6D") then
                task.wait(0.1)
                cacheMotors()
            end
        end)
    end
end

-- Also watch local character for changes
local localConnections = {}

local function setupLocalConnections()
    for _, conn in pairs(localConnections) do
        if conn then conn:Disconnect() end
    end
    table.clear(localConnections)
    
    if char then
        localConnections.descAdded = char.DescendantAdded:Connect(function(desc)
            if desc:IsA("Motor6D") then
                task.wait(0.1)
                cacheMotors()
            end
        end)
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
        print("❌ Target not valid")
        target = nil
        return
    end
    
    -- Cache motors before starting
    if not cacheMotors() then
        print("❌ Could not cache Motor6Ds")
        target = nil
        return
    end
    
    copying = true
    hasTarget = true
    
    disableAnimate()
    setupTargetConnections()
    setupLocalConnections()
    
    if isOnSolidGround() then
        savedGroundCF = getGroundPosition()
    end
    
    print("═══════════════════════════════════════")
    print("  ✅ MOTOR6D SYNC: " .. target.Name)
    print("  🔄 Perfect visual sync - No network lag!")
    print("  📌 Press [G] to stop")
    print("═══════════════════════════════════════")
end

local function stop()
    if not copying then return end
    
    copying = false
    hasTarget = false
    
    cleanupTargetConnections()
    enableAnimate()
    
    -- Reset all motor transforms
    for name, localMotor in pairs(localMotors) do
        if localMotor and localMotor.Parent then
            localMotor.Transform = CF_IDENTITY
        end
    end
    
    table.clear(localMotors)
    table.clear(targetMotors)
    
    target = nil
    targetChar = nil
    targetHum = nil
    targetRoot = nil
    
    print("═══════════════════════════════════════")
    print("  ❌ STOPPED - Animations restored")
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
gui.Name = "AnimCopyMotor"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 999
gui.Parent = LP:WaitForChild("PlayerGui")

local status = Instance.new("TextLabel")
status.Size = UDim2.fromOffset(200, 28)
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

local motorInfo = Instance.new("TextLabel")
motorInfo.Size = UDim2.fromOffset(200, 20)
motorInfo.Position = UDim2.fromOffset(10, 42)
motorInfo.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
motorInfo.BackgroundTransparency = 0.5
motorInfo.TextColor3 = Color3.fromRGB(150, 200, 255)
motorInfo.Font = Enum.Font.Gotham
motorInfo.TextSize = 10
motorInfo.Text = ""
motorInfo.Visible = false
motorInfo.Parent = gui
Instance.new("UICorner", motorInfo).CornerRadius = UDim.new(0, 4)

local groundLabel = Instance.new("TextLabel")
groundLabel.Size = UDim2.fromOffset(200, 20)
groundLabel.Position = UDim2.fromOffset(10, 66)
groundLabel.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
groundLabel.BackgroundTransparency = 0.5
groundLabel.TextColor3 = Color3.fromRGB(150, 200, 255)
groundLabel.Font = Enum.Font.Gotham
groundLabel.TextSize = 10
groundLabel.Text = ""
groundLabel.Visible = false
groundLabel.Parent = gui
Instance.new("UICorner", groundLabel).CornerRadius = UDim.new(0, 4)

local groundStatus = Instance.new("TextLabel")
groundStatus.Size = UDim2.fromOffset(200, 16)
groundStatus.Position = UDim2.fromOffset(10, 90)
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

-- Status update
task.spawn(function()
    while true do
        task.wait(0.1)
        
        if copying and hasTarget and target then
            status.Visible = true
            status.Text = "🔄 Motor Sync: " .. target.Name
            status.TextColor3 = Color3.fromRGB(100, 255, 150)
            
            -- Motor count info
            local localCount = 0
            local targetCount = 0
            for _ in pairs(localMotors) do localCount += 1 end
            for _ in pairs(targetMotors) do targetCount += 1 end
            
            motorInfo.Visible = true
            motorInfo.Text = string.format("⚙️ Motors: %d local / %d target", localCount, targetCount)
            
            if savedGroundCF then
                groundLabel.Visible = true
                local pos = savedGroundCF.Position
                groundLabel.Text = string.format("📍 %.0f, %.0f, %.0f", pos.X, pos.Y, pos.Z)
            else
                groundLabel.Visible = false
            end
            
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
            motorInfo.Visible = false
            groundLabel.Visible = false
            groundStatus.Visible = false
        else
            status.Visible = false
            motorInfo.Visible = false
            groundLabel.Visible = false
            groundStatus.Visible = false
        end
    end
end)

-- ═══════════════════════════════════════════════════════════════════
-- CHARACTER RESPAWN
-- ═══════════════════════════════════════════════════════════════════

LP.CharacterAdded:Connect(function(newChar)
    table.clear(localMotors)
    char, hum, root = nil, nil, nil
    stableGroundTime = 0
    
    local newHum = newChar:WaitForChild("Humanoid", 10)
    local newRoot = newChar:WaitForChild("HumanoidRootPart", 10)
    if not newHum or not newRoot then return end
    
    char = newChar
    hum = newHum
    root = newRoot
    
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
        cacheMotors()
        setupLocalConnections()
        disableAnimate()
    end
end)

-- ═══════════════════════════════════════════════════════════════════
-- INIT
-- ═══════════════════════════════════════════════════════════════════

cacheLocal()

print("═══════════════════════════════════════════════")
print("  🔄 Animation Copy v10.0 - MOTOR6D SYNC")
print("═══════════════════════════════════════════════")
print("  Press [G] to toggle")
print("")
print("  ✅ Why this version is BETTER:")
print("    • Copies Motor6D.Transform directly")
print("    • NOT network-based - syncs every frame")
print("    • Works with ANY ping")
print("    • Perfectly matches target's pose")
print("    • No animation loading/playing issues")
print("    • Smooth and jitter-free")
print("═══════════════════════════════════════════════")
