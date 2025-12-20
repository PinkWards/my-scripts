-- Animation Copy v9.0 - ZERO LATENCY EDITION
-- 100% frame-perfect sync regardless of ping
-- Pure Motor6D replication (no animation timing dependency)

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

-- MOTOR6D CACHE (THE KEY TO ZERO LATENCY)
local myMotors = {}
local targetMotors = {}

-- BODY PARTS CACHE (DIRECT CFRAME SYNC)
local myParts = {}
local targetParts = {}

-- JOINT OFFSETS (for perfect relative positioning)
local jointOffsets = {}

-- ANIMATION STORAGE (backup layer)
local anims = {}
local tracks = {}
local trackIds = {}
local activeThisFrame = {}

-- CONSTANTS
local V3_ZERO = Vector3.zero
local V3_DOWN = Vector3.new(0, -1, 0)
local CF_IDENTITY = CFrame.identity
local PRIORITY = Enum.AnimationPriority.Action4

-- BODY PART NAMES TO SYNC
local SYNC_PARTS = {
    "Head",
    "UpperTorso", "LowerTorso",
    "LeftUpperArm", "LeftLowerArm", "LeftHand",
    "RightUpperArm", "RightLowerArm", "RightHand",
    "LeftUpperLeg", "LeftLowerLeg", "LeftFoot",
    "RightUpperLeg", "RightLowerLeg", "RightFoot",
    -- R6 parts
    "Torso",
    "Left Arm", "Right Arm",
    "Left Leg", "Right Leg"
}

-- ═══════════════════════════════════════════════════════════════════
-- GROUND DETECTION & AUTO-SAVE
-- ═══════════════════════════════════════════════════════════════════

local lastGroundSave = 0

local function isOnGround()
    if not root or not hum then return false end
    if hum.FloorMaterial ~= Enum.Material.Air then return true end
    
    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Exclude
    rayParams.FilterDescendantsInstances = {char}
    
    local result = workspace:Raycast(root.Position, V3_DOWN * 4, rayParams)
    return result ~= nil
end

local function getGroundPosition()
    if not root then return nil end
    
    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Exclude
    rayParams.FilterDescendantsInstances = {char}
    
    local result = workspace:Raycast(root.Position, V3_DOWN * 50, rayParams)
    
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
    if now - lastGroundSave < GROUND_SAVE_INTERVAL then return end
    
    if isOnGround() then
        local groundCF = getGroundPosition()
        if groundCF then
            savedGroundCF = groundCF
            lastGroundSave = now
        end
    end
end

-- ═══════════════════════════════════════════════════════════════════
-- CACHE BODY PARTS (for direct CFrame sync)
-- ═══════════════════════════════════════════════════════════════════

local function cacheParts(character, partsTable)
    table.clear(partsTable)
    if not character then return end
    
    for _, name in SYNC_PARTS do
        local part = character:FindFirstChild(name)
        if part and part:IsA("BasePart") then
            partsTable[name] = part
        end
    end
end

-- ═══════════════════════════════════════════════════════════════════
-- CACHE MOTOR6Ds
-- ═══════════════════════════════════════════════════════════════════

local function cacheMotors(character, motorTable)
    table.clear(motorTable)
    if not character then return end
    
    for _, desc in character:GetDescendants() do
        if desc:IsA("Motor6D") then
            motorTable[desc.Name] = desc
        end
    end
end

-- ═══════════════════════════════════════════════════════════════════
-- CALCULATE RELATIVE OFFSETS (for position-independent sync)
-- ═══════════════════════════════════════════════════════════════════

local function calculateRelativeTransform(targetPart, targetRootPart, myRootPart)
    if not targetPart or not targetRootPart or not myRootPart then 
        return nil 
    end
    
    -- Get target part's position relative to target's root
    local relativeToTargetRoot = targetRootPart.CFrame:ToObjectSpace(targetPart.CFrame)
    
    -- Apply that relative position to my root
    return myRootPart.CFrame:ToWorldSpace(relativeToTargetRoot)
end

-- ═══════════════════════════════════════════════════════════════════
-- CACHE FUNCTIONS
-- ═══════════════════════════════════════════════════════════════════

local function cacheLocal()
    local c = LP.Character
    if not c then
        char, hum, animator, root = nil, nil, nil, nil
        table.clear(myMotors)
        table.clear(myParts)
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
    
    cacheMotors(char, myMotors)
    cacheParts(char, myParts)
    
    return hum ~= nil and root ~= nil and animator ~= nil
end

local function cacheTarget()
    if not target then
        targetChar, targetHum, targetAnimator, targetRoot = nil, nil, nil, nil
        table.clear(targetMotors)
        table.clear(targetParts)
        return false
    end
    
    local tc = target.Character
    if not tc then
        targetChar, targetHum, targetAnimator, targetRoot = nil, nil, nil, nil
        table.clear(targetMotors)
        table.clear(targetParts)
        return false
    end
    
    targetChar = tc
    targetHum = tc:FindFirstChildOfClass("Humanoid")
    targetRoot = tc:FindFirstChild("HumanoidRootPart")
    
    if targetHum then
        targetAnimator = targetHum:FindFirstChildOfClass("Animator")
    end
    
    cacheMotors(targetChar, targetMotors)
    cacheParts(targetChar, targetParts)
    
    return targetHum ~= nil and targetRoot ~= nil
end

-- ═══════════════════════════════════════════════════════════════════
-- DISABLE/ENABLE ANIMATE
-- ═══════════════════════════════════════════════════════════════════

local function disableAnimate()
    if not char then return end
    
    local a = char:FindFirstChild("Animate")
    if a then a.Disabled = true end
    
    if animator then
        for _, t in animator:GetPlayingAnimationTracks() do
            t:Stop(0)
        end
    end
end

local function enableAnimate()
    if not char then return end
    
    local a = char:FindFirstChild("Animate")
    if a then a.Disabled = false end
end

-- ═══════════════════════════════════════════════════════════════════
-- TRACK MANAGEMENT (backup animation layer)
-- ═══════════════════════════════════════════════════════════════════

local function getTrack(animId)
    if tracks[animId] then return tracks[animId] end
    
    if not anims[animId] then
        local a = Instance.new("Animation")
        a.AnimationId = animId
        anims[animId] = a
    end
    
    local ok, t = pcall(animator.LoadAnimation, animator, anims[animId])
    if ok and t then
        t.Priority = PRIORITY
        tracks[animId] = t
        trackIds[#trackIds + 1] = animId
        return t
    end
    return nil
end

local function stopTrack(animId)
    local t = tracks[animId]
    if t then
        t:Stop(0)
        t:Destroy()
    end
    tracks[animId] = nil
    
    for i = #trackIds, 1, -1 do
        if trackIds[i] == animId then
            trackIds[i] = trackIds[#trackIds]
            trackIds[#trackIds] = nil
            break
        end
    end
end

local function stopAll()
    for i = #trackIds, 1, -1 do
        local id = trackIds[i]
        if tracks[id] then
            tracks[id]:Stop(0)
            tracks[id]:Destroy()
        end
        tracks[id] = nil
        trackIds[i] = nil
    end
    
    for id, a in anims do
        a:Destroy()
    end
    table.clear(anims)
    
    if animator then
        for _, t in animator:GetPlayingAnimationTracks() do
            t:Stop(0)
        end
    end
end

-- ═══════════════════════════════════════════════════════════════════
-- FIND NEAREST
-- ═══════════════════════════════════════════════════════════════════

local function findNearest()
    if not root then return nil end
    local pos = root.Position
    local best, bestDist = nil, MAX_DIST
    
    for _, p in Players:GetPlayers() do
        if p ~= LP and p.Character then
            local r = p.Character:FindFirstChild("HumanoidRootPart")
            if r then
                local d = (pos - r.Position).Magnitude
                if d < bestDist then
                    best, bestDist = p, d
                end
            end
        end
    end
    return best
end

-- ═══════════════════════════════════════════════════════════════════
-- ⚡ ZERO LATENCY SYNC - THE MAGIC ⚡
-- Uses Motor6D.Transform which is CLIENT-SIDE (no network delay)
-- This reads the CURRENT VISUAL STATE, not network state
-- ═══════════════════════════════════════════════════════════════════

local function zeroLatencySync()
    if not copying or respawning or not hasTarget then return end
    if not root or not targetRoot then return end
    
    -- ═══════════════════════════════════════════════════════════════
    -- LAYER 1: MOTOR6D TRANSFORM COPY (INSTANT - NO PING)
    -- Motor6D.Transform is the LOCAL animation transform
    -- This is what you SEE on screen, not what server knows
    -- ═══════════════════════════════════════════════════════════════
    
    for name, targetMotor in targetMotors do
        local myMotor = myMotors[name]
        if myMotor then
            -- Skip root joints (we don't want position sync)
            if name ~= "RootJoint" and name ~= "Root" then
                -- DIRECT TRANSFORM COPY - This is frame-perfect
                -- Transform is the animated offset from C0/C1
                myMotor.Transform = targetMotor.Transform
            end
        end
    end
    
    -- ═══════════════════════════════════════════════════════════════
    -- LAYER 2: C0 OFFSET SYNC (for scale/proportion differences)
    -- Only needed if characters have different sizes
    -- ═══════════════════════════════════════════════════════════════
    
    --[[
    for name, targetMotor in targetMotors do
        local myMotor = myMotors[name]
        if myMotor and name ~= "RootJoint" and name ~= "Root" then
            -- Match the joint configuration
            myMotor.C0 = targetMotor.C0
            myMotor.C1 = targetMotor.C1
        end
    end
    ]]
end

-- ═══════════════════════════════════════════════════════════════════
-- ANIMATION BACKUP LAYER (helps with animation events/sounds)
-- ═══════════════════════════════════════════════════════════════════

local function animationBackup()
    if not copying or respawning or not hasTarget then return end
    if not animator or not targetAnimator then return end
    
    local ok, targetTracks = pcall(targetAnimator.GetPlayingAnimationTracks, targetAnimator)
    if not ok or not targetTracks then return end
    
    table.clear(activeThisFrame)
    
    for _, tt in targetTracks do
        if tt.IsPlaying and tt.Animation then
            local id = tt.Animation.AnimationId
            if id and id ~= "" then
                activeThisFrame[id] = true
                
                local myTrack = tracks[id]
                if not myTrack then
                    myTrack = getTrack(id)
                    if myTrack then
                        myTrack:Play(0, 0.001, tt.Speed) -- Near-zero weight
                        myTrack.TimePosition = tt.TimePosition
                    end
                end
                
                if myTrack then
                    -- Keep time synced for animation events
                    myTrack.TimePosition = tt.TimePosition
                    myTrack:AdjustSpeed(tt.Speed)
                    
                    -- Very low weight so Motor6D takes priority
                    myTrack:AdjustWeight(0.001, 0)
                end
            end
        end
    end
    
    for i = #trackIds, 1, -1 do
        local id = trackIds[i]
        if not activeThisFrame[id] then
            stopTrack(id)
        end
    end
end

-- ═══════════════════════════════════════════════════════════════════
-- SINGLE OPTIMIZED SYNC LOOP (PreRender = best for visuals)
-- ═══════════════════════════════════════════════════════════════════

RunService.PreRender:Connect(function()
    if not copying or respawning or not hasTarget then return end
    
    -- Primary sync (Motor6D - zero latency)
    zeroLatencySync()
end)

-- Animation backup runs less frequently
local animBackupCounter = 0
RunService.Heartbeat:Connect(function()
    autoSaveGroundPosition()
    
    if not copying then return end
    
    animBackupCounter += 1
    if animBackupCounter >= 3 then -- Every 3 frames
        animBackupCounter = 0
        animationBackup()
    end
end)

-- ═══════════════════════════════════════════════════════════════════
-- MOTOR RECACHE
-- ═══════════════════════════════════════════════════════════════════

local cacheCounter = 0
RunService.Stepped:Connect(function()
    if not copying then return end
    
    cacheCounter += 1
    if cacheCounter < 60 then return end -- Every ~1 second
    cacheCounter = 0
    
    if char then 
        cacheMotors(char, myMotors)
        cacheParts(char, myParts)
    end
    if targetChar then 
        cacheMotors(targetChar, targetMotors)
        cacheParts(targetChar, targetParts)
    end
    
    if hasTarget and target then
        if not target.Parent then
            print("⚠️ Target left the game")
            hasTarget = false
            target = nil
            stopAll()
            enableAnimate()
        elseif target.Character then
            cacheTarget()
        end
    end
end)

-- ═══════════════════════════════════════════════════════════════════
-- TARGET DEATH HANDLING
-- ═══════════════════════════════════════════════════════════════════

local deathConn, charConn = nil, nil

local function connectTarget()
    if deathConn then deathConn:Disconnect() end
    if charConn then charConn:Disconnect() end
    
    if not target then return end
    
    charConn = target.CharacterAdded:Connect(function(newChar)
        task.wait(0.3)
        cacheTarget()
        if copying and hasTarget then
            disableAnimate()
            print("✅ Target respawned - syncing resumed")
        end
    end)
    
    if target.Character then
        local h = target.Character:FindFirstChildOfClass("Humanoid")
        if h then
            deathConn = h.Died:Connect(function()
                print("⏳ Target died - waiting for respawn...")
                stopAll()
            end)
        end
    end
end

-- ═══════════════════════════════════════════════════════════════════
-- START / STOP
-- ═══════════════════════════════════════════════════════════════════

local function start()
    if copying then return end
    
    cacheLocal()
    if not root then
        print("❌ No character found")
        return
    end
    
    local nearest = findNearest()
    if not nearest then
        print("❌ No player nearby to copy")
        return
    end
    
    copying = true
    hasTarget = true
    target = nearest
    
    stopAll()
    cacheTarget()
    disableAnimate()
    connectTarget()
    
    if isOnGround() then
        local groundCF = getGroundPosition()
        if groundCF then savedGroundCF = groundCF end
    end
    
    print("═══════════════════════════════════════")
    print("  ✅ ZERO LATENCY SYNC: ON")
    print("  📌 Copying: " .. target.Name)
    print("═══════════════════════════════════════")
    print("  ⚡ SYNC METHOD:")
    print("    ✓ Motor6D.Transform (CLIENT-SIDE)")
    print("    ✓ No network delay")
    print("    ✓ No ping dependency")
    print("    ✓ Frame-perfect accuracy")
    print("═══════════════════════════════════════")
end

local function stop()
    if not copying then return end
    copying = false
    hasTarget = false
    
    if deathConn then deathConn:Disconnect() deathConn = nil end
    if charConn then charConn:Disconnect() charConn = nil end
    
    stopAll()
    enableAnimate()
    
    target = nil
    targetChar, targetHum, targetAnimator, targetRoot = nil, nil, nil, nil
    table.clear(targetMotors)
    table.clear(targetParts)
    
    print("═══════════════════════════════════════")
    print("  ❌ ZERO LATENCY SYNC: OFF")
    print("═══════════════════════════════════════")
end

local function toggle()
    if copying then stop() else start() end
end

-- ═══════════════════════════════════════════════════════════════════
-- INPUT
-- ═══════════════════════════════════════════════════════════════════

UserInputService.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if input.KeyCode == TOGGLE_KEY then toggle() end
end)

-- ═══════════════════════════════════════════════════════════════════
-- PLAYER LEFT
-- ═══════════════════════════════════════════════════════════════════

Players.PlayerRemoving:Connect(function(p)
    if p == target then
        print("⚠️ Target left the game!")
        hasTarget = false
        target = nil
        stopAll()
        enableAnimate()
    end
end)

-- ═══════════════════════════════════════════════════════════════════
-- GUI
-- ═══════════════════════════════════════════════════════════════════

local gui = Instance.new("ScreenGui")
gui.Name = "AnimCopyZero"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 999
gui.Parent = LP:WaitForChild("PlayerGui")

-- Fade overlay
local black = Instance.new("Frame")
black.Size = UDim2.new(1,0,1,0)
black.BackgroundColor3 = Color3.new(0,0,0)
black.BackgroundTransparency = 1
black.BorderSizePixel = 0
black.Parent = gui

local loadTxt = Instance.new("TextLabel")
loadTxt.Size = UDim2.new(1,0,0,50)
loadTxt.Position = UDim2.new(0,0,0.5,-25)
loadTxt.BackgroundTransparency = 1
loadTxt.TextColor3 = Color3.new(1,1,1)
loadTxt.TextSize = 20
loadTxt.Font = Enum.Font.GothamBold
loadTxt.Text = ""
loadTxt.TextTransparency = 1
loadTxt.Parent = black

-- Popup
local popup = Instance.new("Frame")
popup.Size = UDim2.new(1,0,1,0)
popup.BackgroundTransparency = 1
popup.Visible = false
popup.Parent = gui

local dim = Instance.new("Frame")
dim.Size = UDim2.new(1,0,1,0)
dim.BackgroundColor3 = Color3.new(0,0,0)
dim.BackgroundTransparency = 0.5
dim.BorderSizePixel = 0
dim.Parent = popup

local box = Instance.new("Frame")
box.Size = UDim2.fromOffset(320,160)
box.Position = UDim2.new(0.5,-160,0.5,-80)
box.BackgroundColor3 = Color3.fromRGB(25,25,30)
box.BorderSizePixel = 0
box.Parent = popup
Instance.new("UICorner", box).CornerRadius = UDim.new(0,10)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1,0,0,30)
title.Position = UDim2.new(0,0,0,10)
title.BackgroundTransparency = 1
title.TextColor3 = Color3.new(1,1,1)
title.TextSize = 16
title.Font = Enum.Font.GothamBold
title.Text = "📍 Teleport to Last Position?"
title.Parent = box

local posLbl = Instance.new("TextLabel")
posLbl.Size = UDim2.new(1,0,0,20)
posLbl.Position = UDim2.new(0,0,0,38)
posLbl.BackgroundTransparency = 1
posLbl.TextColor3 = Color3.fromRGB(100,200,255)
posLbl.TextSize = 11
posLbl.Font = Enum.Font.Gotham
posLbl.Text = ""
posLbl.Parent = box

local timerLbl = Instance.new("TextLabel")
timerLbl.Size = UDim2.new(1,0,0,20)
timerLbl.Position = UDim2.new(0,0,0,58)
timerLbl.BackgroundTransparency = 1
timerLbl.TextColor3 = Color3.fromRGB(150,150,150)
timerLbl.TextSize = 12
timerLbl.Font = Enum.Font.Gotham
timerLbl.Text = "10s..."
timerLbl.Parent = box

local btnFrame = Instance.new("Frame")
btnFrame.Size = UDim2.new(1,-20,0,40)
btnFrame.Position = UDim2.new(0,10,1,-55)
btnFrame.BackgroundTransparency = 1
btnFrame.Parent = box

local btnLayout = Instance.new("UIListLayout")
btnLayout.FillDirection = Enum.FillDirection.Horizontal
btnLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
btnLayout.Padding = UDim.new(0,10)
btnLayout.Parent = btnFrame

local yesBtn = Instance.new("TextButton")
yesBtn.Size = UDim2.fromOffset(120,36)
yesBtn.BackgroundColor3 = Color3.fromRGB(0,150,110)
yesBtn.BorderSizePixel = 0
yesBtn.TextColor3 = Color3.new(1,1,1)
yesBtn.TextSize = 14
yesBtn.Font = Enum.Font.GothamBold
yesBtn.Text = "✓ Yes"
yesBtn.Parent = btnFrame
Instance.new("UICorner", yesBtn).CornerRadius = UDim.new(0,6)

local noBtn = Instance.new("TextButton")
noBtn.Size = UDim2.fromOffset(120,36)
noBtn.BackgroundColor3 = Color3.fromRGB(50,50,55)
noBtn.BorderSizePixel = 0
noBtn.TextColor3 = Color3.new(1,1,1)
noBtn.TextSize = 14
noBtn.Font = Enum.Font.GothamBold
noBtn.Text = "✕ No"
noBtn.Parent = btnFrame
Instance.new("UICorner", noBtn).CornerRadius = UDim.new(0,6)

-- Status
local status = Instance.new("TextLabel")
status.Size = UDim2.fromOffset(200,32)
status.Position = UDim2.new(0,10,0,10)
status.BackgroundColor3 = Color3.fromRGB(20,20,25)
status.BackgroundTransparency = 0.2
status.TextColor3 = Color3.fromRGB(100,255,100)
status.Font = Enum.Font.GothamBold
status.TextSize = 11
status.Text = ""
status.Visible = false
status.Parent = gui
Instance.new("UICorner", status).CornerRadius = UDim.new(0,4)
Instance.new("UIStroke", status).Color = Color3.fromRGB(60,60,60)

local groundStatus = Instance.new("TextLabel")
groundStatus.Size = UDim2.fromOffset(200,20)
groundStatus.Position = UDim2.new(0,10,0,46)
groundStatus.BackgroundColor3 = Color3.fromRGB(20,20,25)
groundStatus.BackgroundTransparency = 0.3
groundStatus.TextColor3 = Color3.fromRGB(100,180,255)
groundStatus.Font = Enum.Font.Gotham
groundStatus.TextSize = 9
groundStatus.Text = ""
groundStatus.Visible = false
groundStatus.Parent = gui
Instance.new("UICorner", groundStatus).CornerRadius = UDim.new(0,4)

-- Popup logic
local popupResult, popupActive = nil, false

local function showPopup()
    popupResult, popupActive = nil, true
    popup.Visible = true
    
    if savedGroundCF then
        local pos = savedGroundCF.Position
        posLbl.Text = string.format("(%.0f, %.0f, %.0f)", pos.X, pos.Y, pos.Z)
    else
        posLbl.Text = "No saved position"
    end
    
    local t = 10
    task.spawn(function()
        while popupActive and t > 0 do
            timerLbl.Text = t .. "s..."
            task.wait(1)
            t -= 1
        end
        if popupActive then popupResult, popupActive = false, false end
    end)
    
    while popupActive do task.wait(0.05) end
    popup.Visible = false
    return popupResult
end

yesBtn.MouseButton1Click:Connect(function() popupResult, popupActive = true, false end)
noBtn.MouseButton1Click:Connect(function() popupResult, popupActive = false, false end)

local TI = TweenInfo.new(0.15)
local function fadeIn()
    loadTxt.Text = "⟳ Teleporting..."
    TweenService:Create(black, TI, {BackgroundTransparency = 0}):Play()
    TweenService:Create(loadTxt, TI, {TextTransparency = 0}):Play()
    task.wait(0.15)
end

local function fadeOut()
    TweenService:Create(black, TI, {BackgroundTransparency = 1}):Play()
    TweenService:Create(loadTxt, TI, {TextTransparency = 1}):Play()
    task.wait(0.15)
end

-- Status update
task.spawn(function()
    while true do
        task.wait(0.1)
        
        if copying then
            status.Visible = true
            groundStatus.Visible = true
            
            if not hasTarget or not target then
                status.Text = "⚠️ No Target [G]"
                status.TextColor3 = Color3.fromRGB(255,80,80)
            elseif not targetRoot then
                status.Text = "⏳ Waiting..."
                status.TextColor3 = Color3.fromRGB(255,180,80)
            else
                status.Text = "⚡ ZERO LAG: " .. target.Name
                status.TextColor3 = Color3.fromRGB(80,255,120)
            end
            
            if savedGroundCF then
                local pos = savedGroundCF.Position
                groundStatus.Text = string.format("📍 (%.0f, %.0f, %.0f)", pos.X, pos.Y, pos.Z)
            end
        else
            status.Visible = false
            groundStatus.Visible = false
        end
    end
end)

-- Fast teleport
local function fastTeleport(targetCF)
    if not root then return false end
    fadeIn()
    root.Anchored = true
    task.wait(0.05)
    root.CFrame = targetCF
    root.AssemblyLinearVelocity = V3_ZERO
    root.AssemblyAngularVelocity = V3_ZERO
    task.wait(0.05)
    root.Anchored = false
    fadeOut()
    return true
end

-- ═══════════════════════════════════════════════════════════════════
-- CHARACTER RESPAWN
-- ═══════════════════════════════════════════════════════════════════

LP.CharacterAdded:Connect(function(c)
    table.clear(tracks)
    table.clear(trackIds)
    table.clear(anims)
    table.clear(myMotors)
    table.clear(myParts)
    char, hum, animator, root = nil, nil, nil, nil
    
    local h = c:WaitForChild("Humanoid", 10)
    local r = c:WaitForChild("HumanoidRootPart", 10)
    if not h or not r then return end
    
    char, hum, root = c, h, r
    animator = h:FindFirstChildOfClass("Animator")
    if not animator then
        animator = Instance.new("Animator")
        animator.Parent = h
    end
    
    cacheMotors(char, myMotors)
    cacheParts(char, myParts)
    
    if savedGroundCF then
        respawning = true
        task.wait(0.3)
        
        if showPopup() then
            fastTeleport(savedGroundCF)
            print("📍 Teleported!")
        else
            if isOnGround() then
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
print("  ⚡ Animation Copy v9.0")
print("  ZERO LATENCY EDITION")
print("═══════════════════════════════════════════════")
print("  Press [G] to toggle")
print("")
print("  🔥 WHY ZERO LATENCY:")
print("    Motor6D.Transform is CLIENT-SIDE")
print("    It shows what YOU SEE on screen")
print("    Not what the server knows")
print("    = No ping, no delay, no desync")
print("")
print("  ✅ FEATURES:")
print("    • Frame-perfect body sync")
print("    • Works with any ping")
print("    • Auto ground position save")
print("    • Respawn teleport option")
print("═══════════════════════════════════════════════")
