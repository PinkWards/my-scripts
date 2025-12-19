-- Animation Copy v8.0 - ULTIMATE SYNC EDITION
-- Copies animations + body parts ONLY (you stay where you are)
-- Zero lag, zero buggy body parts

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local LP = Players.LocalPlayer

-- CONFIG
local TOGGLE_KEY = Enum.KeyCode.G
local MAX_DIST = 150

-- STATE
local copying = false
local target = nil
local savedCF = nil
local respawning = false
local hasTarget = false

-- CACHE
local char, hum, animator, root = nil, nil, nil, nil
local targetChar, targetHum, targetAnimator, targetRoot = nil, nil, nil, nil

-- MOTOR6D CACHE
local myMotors = {}
local targetMotors = {}

-- ANIMATION STORAGE
local anims = {}
local tracks = {}
local trackIds = {}
local activeThisFrame = {}

-- CONSTANTS
local V3_ZERO = Vector3.zero
local PRIORITY = Enum.AnimationPriority.Action4

-- ═══════════════════════════════════════════════════════════════════
-- MOTOR6D CACHING (for perfect body part sync)
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
-- CACHE FUNCTIONS
-- ═══════════════════════════════════════════════════════════════════

local function cacheLocal()
    local c = LP.Character
    if not c then
        char, hum, animator, root = nil, nil, nil, nil
        table.clear(myMotors)
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
    return hum ~= nil and root ~= nil and animator ~= nil
end

local function cacheTarget()
    if not target then
        targetChar, targetHum, targetAnimator, targetRoot = nil, nil, nil, nil
        table.clear(targetMotors)
        return false
    end
    
    local tc = target.Character
    if not tc then
        targetChar, targetHum, targetAnimator, targetRoot = nil, nil, nil, nil
        table.clear(targetMotors)
        return false
    end
    
    targetChar = tc
    targetHum = tc:FindFirstChildOfClass("Humanoid")
    targetRoot = tc:FindFirstChild("HumanoidRootPart")
    
    if targetHum then
        targetAnimator = targetHum:FindFirstChildOfClass("Animator")
    end
    
    cacheMotors(targetChar, targetMotors)
    return targetHum ~= nil and targetAnimator ~= nil and targetRoot ~= nil
end

-- ═══════════════════════════════════════════════════════════════════
-- DISABLE ANIMATE SCRIPT ONLY
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
-- TRACK MANAGEMENT
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
-- ULTIMATE SYNC (ANIMATION + MOTOR6D ONLY - NO POSITION)
-- ═══════════════════════════════════════════════════════════════════

local function ultimateSync()
    if not copying or respawning or not hasTarget then return end
    if not animator or not targetAnimator then return end
    
    -- ═══════════════════════════════════════════════════════════════
    -- LAYER 1: COPY MOTOR6D TRANSFORMS (perfect body part poses)
    -- This makes arms, legs, head match exactly
    -- ═══════════════════════════════════════════════════════════════
    
    for name, targetMotor in targetMotors do
        local myMotor = myMotors[name]
        if myMotor and name ~= "RootJoint" and name ~= "Root" then
            -- Copy joint transforms (NOT position, just rotation/pose)
            myMotor.Transform = targetMotor.Transform
        end
    end
    
    -- ═══════════════════════════════════════════════════════════════
    -- LAYER 2: COPY ANIMATIONS (timing + speed + weight)
    -- ═══════════════════════════════════════════════════════════════
    
    local ok, targetTracks = pcall(targetAnimator.GetPlayingAnimationTracks, targetAnimator)
    if not ok or not targetTracks then return end
    
    table.clear(activeThisFrame)
    
    for i = 1, #targetTracks do
        local tt = targetTracks[i]
        if tt.IsPlaying and tt.Animation then
            local id = tt.Animation.AnimationId
            if id and id ~= "" then
                activeThisFrame[id] = true
                
                local myTrack = tracks[id]
                
                if not myTrack then
                    myTrack = getTrack(id)
                    if myTrack then
                        myTrack:Play(0, tt.WeightTarget, tt.Speed)
                    end
                end
                
                if myTrack then
                    -- FORCE TIME SYNC
                    myTrack.TimePosition = tt.TimePosition
                    
                    -- FORCE SPEED
                    if myTrack.Speed ~= tt.Speed then
                        myTrack:AdjustSpeed(tt.Speed)
                    end
                    
                    -- FORCE WEIGHT
                    local tw = tt.WeightCurrent
                    if math.abs(myTrack.WeightCurrent - tw) > 0.01 then
                        myTrack:AdjustWeight(tw, 0)
                    end
                    
                    -- FORCE PLAYING
                    if not myTrack.IsPlaying then
                        myTrack:Play(0, tw, tt.Speed)
                        myTrack.TimePosition = tt.TimePosition
                    end
                end
            end
        end
    end
    
    -- Stop tracks not on target
    for i = #trackIds, 1, -1 do
        local id = trackIds[i]
        if not activeThisFrame[id] then
            stopTrack(id)
        end
    end
end

-- ═══════════════════════════════════════════════════════════════════
-- MULTI-LAYER SYNC (runs multiple times per frame for 100% accuracy)
-- ═══════════════════════════════════════════════════════════════════

RunService.PreSimulation:Connect(ultimateSync)
RunService.PreRender:Connect(ultimateSync)
RunService.PreAnimation:Connect(ultimateSync)
RunService.RenderStepped:Connect(ultimateSync)

-- ═══════════════════════════════════════════════════════════════════
-- MOTOR RECACHE (keep motors updated)
-- ═══════════════════════════════════════════════════════════════════

local cacheCounter = 0
RunService.Heartbeat:Connect(function()
    if not copying then return end
    
    cacheCounter += 1
    if cacheCounter < 30 then return end
    cacheCounter = 0
    
    if char then cacheMotors(char, myMotors) end
    if targetChar then cacheMotors(targetChar, targetMotors) end
    
    -- Validate target
    if hasTarget and target then
        if not target.Parent then
            print("⚠️ Target left the game")
            print("💡 Press [G] to stop, then [G] for new target")
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
    
    if root then savedCF = root.CFrame end
    
    print("═══════════════════════════════════════")
    print("  ✅ ANIMATION COPY: ON")
    print("  📌 Copying: " .. target.Name)
    print("═══════════════════════════════════════")
    print("  ⚡ SYNC ACTIVE:")
    print("    ✓ Animation sync")
    print("    ✓ Motor6D sync (body parts)")
    print("    ✓ You stay in YOUR position")
    print("    ✓ You can move freely")
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
    
    print("═══════════════════════════════════════")
    print("  ❌ ANIMATION COPY: OFF")
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
        print("═══════════════════════════════════════")
        print("  ⚠️ Target left the game!")
        print("  💡 Press [G] to stop, then [G] for new target")
        print("═══════════════════════════════════════")
        
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
gui.Name = "AnimCopy"
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
box.Size = UDim2.fromOffset(300,140)
box.Position = UDim2.new(0.5,-150,0.5,-70)
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
title.Text = "📍 Teleport Back?"
title.Parent = box

local timerLbl = Instance.new("TextLabel")
timerLbl.Size = UDim2.new(1,0,0,20)
timerLbl.Position = UDim2.new(0,0,0,40)
timerLbl.BackgroundTransparency = 1
timerLbl.TextColor3 = Color3.fromRGB(150,150,150)
timerLbl.TextSize = 12
timerLbl.Font = Enum.Font.Gotham
timerLbl.Text = "10s..."
timerLbl.Parent = box

local btnFrame = Instance.new("Frame")
btnFrame.Size = UDim2.new(1,-20,0,40)
btnFrame.Position = UDim2.new(0,10,1,-50)
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

-- Status indicator
local status = Instance.new("TextLabel")
status.Size = UDim2.fromOffset(160,24)
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

-- Popup logic
local popupResult, popupActive = nil, false

local function showPopup()
    popupResult, popupActive = nil, true
    popup.Visible = true
    
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

local TI = TweenInfo.new(0.25)
local function fadeIn()
    loadTxt.Text = "⟳ Teleporting..."
    TweenService:Create(black, TI, {BackgroundTransparency = 0}):Play()
    TweenService:Create(loadTxt, TI, {TextTransparency = 0}):Play()
    task.wait(0.25)
end

local function fadeOut()
    TweenService:Create(black, TI, {BackgroundTransparency = 1}):Play()
    TweenService:Create(loadTxt, TI, {TextTransparency = 1}):Play()
    task.wait(0.25)
end

-- Status update
task.spawn(function()
    while true do
        task.wait(0.15)
        
        if copying then
            status.Visible = true
            
            if not hasTarget or not target then
                status.Text = "⚠️ No Target [G]"
                status.TextColor3 = Color3.fromRGB(255,80,80)
            elseif not targetAnimator then
                status.Text = "⏳ Waiting..."
                status.TextColor3 = Color3.fromRGB(255,180,80)
            else
                status.Text = "⚡ Copying: " .. target.Name
                status.TextColor3 = Color3.fromRGB(80,255,120)
            end
        else
            status.Visible = false
        end
    end
end)

-- ═══════════════════════════════════════════════════════════════════
-- CHARACTER RESPAWN
-- ═══════════════════════════════════════════════════════════════════

LP.CharacterAdded:Connect(function(c)
    table.clear(tracks)
    table.clear(trackIds)
    table.clear(anims)
    table.clear(myMotors)
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
    
    if savedCF then
        respawning = true
        task.wait(0.5)
        
        if showPopup() then
            fadeIn()
            task.wait(0.1)
            r.CFrame = savedCF
            r.AssemblyLinearVelocity = V3_ZERO
            r.AssemblyAngularVelocity = V3_ZERO
            task.wait(0.1)
            fadeOut()
            print("📍 Teleported back")
        else
            savedCF = r.CFrame
            print("📍 Staying at spawn")
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

print("═══════════════════════════════════════════════")
print("  🎭 Animation Copy v8.0")
print("  PERFECT SYNC EDITION")
print("═══════════════════════════════════════════════")
print("  Press [G] to toggle")
print("")
print("  ✅ WHAT IT COPIES:")
print("    • All animations (walk, run, jump, etc)")
print("    • Body part positions (arms, legs, head)")
print("    • Animation timing (frame-perfect)")
print("")
print("  ✅ WHAT IT DOESN'T COPY:")
print("    • Your position (you stay where you are)")
print("    • You can walk around freely")
print("    • You can go anywhere you want")
print("")
print("  🔧 No buggy body parts")
print("  🚀 No lag")
print("  🎯 No auto-target switch")
print("═══════════════════════════════════════════════")
