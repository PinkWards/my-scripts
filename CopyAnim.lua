-- Animation Copy v6.0 - PERFECT SYNC EDITION
-- Zero delay, frame-perfect synchronization

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

-- CACHE
local char, hum, animator, root = nil, nil, nil, nil
local targetChar, targetHum, targetAnimator = nil, nil, nil

-- ANIMATION STORAGE (arrays for faster iteration)
local anims = {}      -- [animId] = Animation instance
local tracks = {}     -- [animId] = AnimationTrack
local trackIds = {}   -- array of active animIds for fast iteration

-- CONSTANTS
local V3_ZERO = Vector3.zero
local PRIORITY = Enum.AnimationPriority.Action4

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
    if not target or not target.Character then
        targetChar, targetHum, targetAnimator = nil, nil, nil
        return false
    end
    targetChar = target.Character
    targetHum = targetChar:FindFirstChildOfClass("Humanoid")
    if targetHum then
        targetAnimator = targetHum:FindFirstChildOfClass("Animator")
    end
    return targetHum ~= nil and targetAnimator ~= nil
end

-- ═══════════════════════════════════════════════════════════════════
-- ANIMATE SCRIPT CONTROL
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
    
    -- Remove from trackIds array
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
-- FIND TARGET
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
-- SYNC LOOP (ULTRA OPTIMIZED - RUNS EVERY FRAME)
-- ═══════════════════════════════════════════════════════════════════

local activeThisFrame = {}
local conn = nil

local function sync()
    if not copying or respawning then return end
    if not animator or not targetAnimator then return end
    
    -- Get target tracks directly
    local ok, targetTracks = pcall(targetAnimator.GetPlayingAnimationTracks, targetAnimator)
    if not ok then return end
    
    -- Clear active set
    table.clear(activeThisFrame)
    
    -- Sync each target track
    for i = 1, #targetTracks do
        local tt = targetTracks[i]
        if tt.IsPlaying and tt.Animation then
            local id = tt.Animation.AnimationId
            if id and id ~= "" then
                activeThisFrame[id] = true
                
                local myTrack = tracks[id]
                
                -- Start track if needed
                if not myTrack then
                    myTrack = getTrack(id)
                    if myTrack then
                        myTrack:Play(0, 1, tt.Speed)
                    end
                end
                
                -- INSTANT SYNC - no thresholds, every frame
                if myTrack then
                    -- Direct sync TimePosition
                    myTrack.TimePosition = tt.TimePosition
                    
                    -- Speed sync
                    if myTrack.Speed ~= tt.Speed then
                        myTrack:AdjustSpeed(tt.Speed)
                    end
                    
                    -- Ensure full weight
                    if myTrack.WeightCurrent < 0.99 then
                        myTrack:AdjustWeight(1, 0)
                    end
                end
            end
        end
    end
    
    -- Stop tracks no longer playing on target
    for i = #trackIds, 1, -1 do
        local id = trackIds[i]
        if not activeThisFrame[id] then
            stopTrack(id)
        end
    end
end

-- ═══════════════════════════════════════════════════════════════════
-- HEARTBEAT - Target validation & finding (slower, off render thread)
-- ═══════════════════════════════════════════════════════════════════

local validateCounter = 0

RunService.Heartbeat:Connect(function()
    if not copying or respawning then return end
    
    validateCounter += 1
    if validateCounter < 3 then return end -- Every 3 frames
    validateCounter = 0
    
    -- Check target validity
    if not target or not target.Character or not target.Character:FindFirstChild("Humanoid") then
        local newTarget = findNearest()
        if newTarget and newTarget ~= target then
            stopAll()
            target = newTarget
            cacheTarget()
            disableAnimate()
            print("📌 Copying: " .. target.Name)
        elseif not newTarget then
            target = nil
            targetChar, targetHum, targetAnimator = nil, nil, nil
        end
    else
        cacheTarget()
    end
end)

-- ═══════════════════════════════════════════════════════════════════
-- START / STOP
-- ═══════════════════════════════════════════════════════════════════

local function start()
    if copying then return end
    copying = true
    
    cacheLocal()
    stopAll()
    disableAnimate()
    
    if root then savedCF = root.CFrame end
    
    target = findNearest()
    cacheTarget()
    
    print("═════════════════════════════════")
    print("✅ Animation Copy: ON")
    if target then print("📌 Copying: " .. target.Name) end
    print("═════════════════════════════════")
    
    -- Use PreRender for smoothest visual sync
    conn = RunService.PreRender:Connect(sync)
end

local function stop()
    if not copying then return end
    copying = false
    
    if conn then conn:Disconnect() conn = nil end
    
    stopAll()
    enableAnimate()
    target = nil
    targetChar, targetHum, targetAnimator = nil, nil, nil
    
    print("═════════════════════════════════")
    print("❌ Animation Copy: OFF")
    print("═════════════════════════════════")
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
-- MINIMAL GUI (Popup only)
-- ═══════════════════════════════════════════════════════════════════

local gui = Instance.new("ScreenGui")
gui.Name = "AnimSync"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 999
gui.Parent = LP:WaitForChild("PlayerGui")

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
box.Size = UDim2.fromOffset(320, 160)
box.Position = UDim2.new(0.5,-160,0.5,-80)
box.BackgroundColor3 = Color3.fromRGB(30,30,35)
box.BorderSizePixel = 0
box.Parent = popup
Instance.new("UICorner", box).CornerRadius = UDim.new(0,12)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1,-20,0,30)
title.Position = UDim2.new(0,10,0,15)
title.BackgroundTransparency = 1
title.TextColor3 = Color3.new(1,1,1)
title.TextSize = 18
title.Font = Enum.Font.GothamBold
title.Text = "📍 Teleport Back?"
title.Parent = box

local desc = Instance.new("TextLabel")
desc.Size = UDim2.new(1,-20,0,20)
desc.Position = UDim2.new(0,10,0,50)
desc.BackgroundTransparency = 1
desc.TextColor3 = Color3.fromRGB(180,180,180)
desc.TextSize = 14
desc.Font = Enum.Font.Gotham
desc.Text = "Return to previous location?"
desc.Parent = box

local timer = Instance.new("TextLabel")
timer.Size = UDim2.new(1,-20,0,15)
timer.Position = UDim2.new(0,10,0,72)
timer.BackgroundTransparency = 1
timer.TextColor3 = Color3.fromRGB(120,120,120)
timer.TextSize = 12
timer.Font = Enum.Font.Gotham
timer.Text = "Auto-close in 10s..."
timer.Parent = box

local btnCont = Instance.new("Frame")
btnCont.Size = UDim2.new(1,-20,0,40)
btnCont.Position = UDim2.new(0,10,1,-50)
btnCont.BackgroundTransparency = 1
btnCont.Parent = box

local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Horizontal
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.Padding = UDim.new(0,10)
layout.Parent = btnCont

local yesBtn = Instance.new("TextButton")
yesBtn.Size = UDim2.fromOffset(130,40)
yesBtn.BackgroundColor3 = Color3.fromRGB(0,170,127)
yesBtn.BorderSizePixel = 0
yesBtn.TextColor3 = Color3.new(1,1,1)
yesBtn.TextSize = 15
yesBtn.Font = Enum.Font.GothamBold
yesBtn.Text = "✓ Yes"
yesBtn.Parent = btnCont
Instance.new("UICorner", yesBtn).CornerRadius = UDim.new(0,8)

local noBtn = Instance.new("TextButton")
noBtn.Size = UDim2.fromOffset(130,40)
noBtn.BackgroundColor3 = Color3.fromRGB(60,60,65)
noBtn.BorderSizePixel = 0
noBtn.TextColor3 = Color3.new(1,1,1)
noBtn.TextSize = 15
noBtn.Font = Enum.Font.GothamBold
noBtn.Text = "✕ No"
noBtn.Parent = btnCont
Instance.new("UICorner", noBtn).CornerRadius = UDim.new(0,8)

-- Popup logic
local result, active = nil, false

local function showPopup()
    result, active = nil, true
    popup.Visible = true
    
    local t = 10
    task.spawn(function()
        while active and t > 0 do
            timer.Text = "Auto-close in " .. t .. "s..."
            task.wait(1)
            t -= 1
        end
        if active then result, active = false, false end
    end)
    
    while active do task.wait(0.05) end
    popup.Visible = false
    return result
end

yesBtn.MouseButton1Click:Connect(function() result, active = true, false end)
noBtn.MouseButton1Click:Connect(function() result, active = false, false end)

-- Fade functions
local TI = TweenInfo.new(0.3)
local function fadeIn()
    loadTxt.Text = "⟳ Teleporting..."
    TweenService:Create(black, TI, {BackgroundTransparency = 0}):Play()
    TweenService:Create(loadTxt, TI, {TextTransparency = 0}):Play()
    task.wait(0.3)
end

local function fadeOut()
    TweenService:Create(black, TI, {BackgroundTransparency = 1}):Play()
    TweenService:Create(loadTxt, TI, {TextTransparency = 1}):Play()
    task.wait(0.3)
end

-- ═══════════════════════════════════════════════════════════════════
-- CHARACTER RESPAWN
-- ═══════════════════════════════════════════════════════════════════

LP.CharacterAdded:Connect(function(c)
    table.clear(tracks)
    table.clear(trackIds)
    table.clear(anims)
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
            print("📍 Staying here")
        end
        
        respawning = false
    end
    
    task.wait(0.2)
    if copying then disableAnimate() end
end)

-- ═══════════════════════════════════════════════════════════════════
-- CLEANUP
-- ═══════════════════════════════════════════════════════════════════

Players.PlayerRemoving:Connect(function(p)
    if p == target then
        stopAll()
        target = nil
        targetChar, targetHum, targetAnimator = nil, nil, nil
        print("⚠️ Target left")
    end
end)

-- ═══════════════════════════════════════════════════════════════════
-- INIT
-- ═══════════════════════════════════════════════════════════════════

print("═══════════════════════════════════")
print("  🎭 Animation Copy v6.0")
print("  PERFECT SYNC EDITION")
print("═══════════════════════════════════")
print("  Press [G] to toggle")
print("  ✓ Frame-perfect sync")
print("  ✓ Zero delay while moving")
print("  ✓ PreRender for smoothest visuals")
print("═══════════════════════════════════")
