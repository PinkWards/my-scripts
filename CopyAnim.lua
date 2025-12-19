-- Animation Copy v7.0 - ABSOLUTE SYNC EDITION
-- No auto-target, multi-layer sync, zero ping dependency

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
local targetAnimator = nil

-- STORAGE
local anims = {}
local tracks = {}
local trackIds = {}

-- CONSTANTS
local V3_ZERO = Vector3.zero
local PRIORITY = Enum.AnimationPriority.Action4

-- ═══════════════════════════════════════════════════════════════════
-- CACHE
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
        targetAnimator = nil
        return false
    end
    
    local tc = target.Character
    if not tc then
        targetAnimator = nil
        return false
    end
    
    local th = tc:FindFirstChildOfClass("Humanoid")
    if not th then
        targetAnimator = nil
        return false
    end
    
    targetAnimator = th:FindFirstChildOfClass("Animator")
    return targetAnimator ~= nil
end

-- ═══════════════════════════════════════════════════════════════════
-- ANIMATE SCRIPT
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
-- FIND NEAREST (only called manually)
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
-- ULTRA SYNC FUNCTION (called multiple times per frame)
-- ═══════════════════════════════════════════════════════════════════

local activeThisFrame = {}

local function ultraSync()
    if not copying or respawning or not hasTarget then return end
    if not animator or not targetAnimator then return end
    
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
                        myTrack:Play(0, 1, tt.Speed)
                    end
                end
                
                if myTrack then
                    -- FORCE SYNC - absolute position match
                    myTrack.TimePosition = tt.TimePosition
                    
                    -- FORCE SPEED
                    local ts = tt.Speed
                    if myTrack.Speed ~= ts then
                        myTrack:AdjustSpeed(ts)
                    end
                    
                    -- FORCE WEIGHT
                    if myTrack.WeightCurrent < 1 then
                        myTrack:AdjustWeight(1, 0)
                    end
                    
                    -- FORCE PLAYING
                    if not myTrack.IsPlaying then
                        myTrack:Play(0, 1, ts)
                        myTrack.TimePosition = tt.TimePosition
                    end
                end
            end
        end
    end
    
    -- Stop inactive
    for i = #trackIds, 1, -1 do
        local id = trackIds[i]
        if not activeThisFrame[id] then
            stopTrack(id)
        end
    end
end

-- ═══════════════════════════════════════════════════════════════════
-- MULTI-LAYER SYNC (200% SYNC - runs on ALL render events)
-- ═══════════════════════════════════════════════════════════════════

-- Layer 1: PreRender (earliest, before physics)
RunService.PreRender:Connect(ultraSync)

-- Layer 2: PreAnimation (before animation update)
RunService.PreAnimation:Connect(ultraSync)

-- Layer 3: RenderStepped (standard render)
RunService.RenderStepped:Connect(ultraSync)

-- ═══════════════════════════════════════════════════════════════════
-- TARGET VALIDATION (check if target died/left)
-- ═══════════════════════════════════════════════════════════════════

local function validateTarget()
    if not hasTarget or not target then return end
    
    -- Check if player left
    if not target.Parent then
        print("⚠️ Target left the game")
        print("💡 Press [G] again to select new target")
        hasTarget = false
        target = nil
        targetAnimator = nil
        stopAll()
        enableAnimate()
        return
    end
    
    -- Check if character exists
    local tc = target.Character
    if not tc then
        print("⚠️ Target died/respawning - waiting...")
        targetAnimator = nil
        return
    end
    
    -- Check if humanoid exists and alive
    local th = tc:FindFirstChildOfClass("Humanoid")
    if not th then
        targetAnimator = nil
        return
    end
    
    -- Re-cache animator
    cacheTarget()
end

-- Validation runs slower (every 5 frames)
local validateCounter = 0
RunService.Heartbeat:Connect(function()
    if not copying then return end
    
    validateCounter += 1
    if validateCounter < 5 then return end
    validateCounter = 0
    
    validateTarget()
end)

-- ═══════════════════════════════════════════════════════════════════
-- TARGET DEATH DETECTION
-- ═══════════════════════════════════════════════════════════════════

local deathConnection = nil

local function connectTargetDeath()
    if deathConnection then
        deathConnection:Disconnect()
        deathConnection = nil
    end
    
    if not target then return end
    
    local function onCharacter(newChar)
        if not newChar then return end
        
        local newHum = newChar:WaitForChild("Humanoid", 5)
        if not newHum then return end
        
        -- Wait for animator
        task.wait(0.2)
        cacheTarget()
        
        if copying and hasTarget then
            disableAnimate()
            print("✅ Target respawned - syncing resumed")
        end
    end
    
    if target.Character then
        local h = target.Character:FindFirstChildOfClass("Humanoid")
        if h then
            h.Died:Connect(function()
                print("⚠️ Target died - waiting for respawn...")
                stopAll()
            end)
        end
    end
    
    deathConnection = target.CharacterAdded:Connect(onCharacter)
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
    disableAnimate()
    cacheTarget()
    connectTargetDeath()
    
    if root then savedCF = root.CFrame end
    
    print("═════════════════════════════════════")
    print("✅ Animation Copy: ON")
    print("📌 Copying: " .. target.Name)
    print("═════════════════════════════════════")
    print("⚡ 200% SYNC ACTIVE")
    print("  • PreRender sync")
    print("  • PreAnimation sync")
    print("  • RenderStepped sync")
    print("═════════════════════════════════════")
end

local function stop()
    if not copying then return end
    copying = false
    hasTarget = false
    
    if deathConnection then
        deathConnection:Disconnect()
        deathConnection = nil
    end
    
    stopAll()
    enableAnimate()
    target = nil
    targetAnimator = nil
    
    print("═════════════════════════════════════")
    print("❌ Animation Copy: OFF")
    print("═════════════════════════════════════")
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
-- PLAYER REMOVING (target left game)
-- ═══════════════════════════════════════════════════════════════════

Players.PlayerRemoving:Connect(function(p)
    if p == target then
        print("═════════════════════════════════════")
        print("⚠️ Target left the game!")
        print("💡 Press [G] to stop, then [G] for new target")
        print("═════════════════════════════════════")
        
        hasTarget = false
        target = nil
        targetAnimator = nil
        stopAll()
        enableAnimate()
        -- Keep copying = true so user knows to press G to reset
    end
end)

-- ═══════════════════════════════════════════════════════════════════
-- GUI (Minimal popup only)
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
    if copying and hasTarget then
        disableAnimate()
        cacheTarget()
    end
end)

-- ═══════════════════════════════════════════════════════════════════
-- STATUS INDICATOR (tiny, shows sync status)
-- ═══════════════════════════════════════════════════════════════════

local status = Instance.new("TextLabel")
status.Size = UDim2.fromOffset(120, 20)
status.Position = UDim2.new(0, 10, 0, 10)
status.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
status.BackgroundTransparency = 0.3
status.TextColor3 = Color3.fromRGB(100, 255, 100)
status.Font = Enum.Font.GothamBold
status.TextSize = 11
status.Text = ""
status.Visible = false
status.Parent = gui
Instance.new("UICorner", status).CornerRadius = UDim.new(0, 4)

task.spawn(function()
    while true do
        task.wait(0.25)
        
        if copying then
            status.Visible = true
            
            if not hasTarget or not target then
                status.Text = "⚠️ No Target"
                status.TextColor3 = Color3.fromRGB(255, 100, 100)
            elseif not targetAnimator then
                status.Text = "⏳ Waiting..."
                status.TextColor3 = Color3.fromRGB(255, 200, 100)
            else
                status.Text = "⚡ SYNCED"
                status.TextColor3 = Color3.fromRGB(100, 255, 100)
            end
        else
            status.Visible = false
        end
    end
end)

-- ═══════════════════════════════════════════════════════════════════
-- INIT
-- ═══════════════════════════════════════════════════════════════════

print("═══════════════════════════════════════════")
print("  🎭 Animation Copy v7.0")
print("  ABSOLUTE SYNC EDITION")
print("═══════════════════════════════════════════")
print("  Press [G] to toggle")
print("")
print("  ⚡ 200% SYNC:")
print("    • PreRender")
print("    • PreAnimation")
print("    • RenderStepped")
print("")
print("  ✓ NO auto-target on death/leave")
print("  ✓ Waits for target respawn")
print("  ✓ Zero ping dependency")
print("═══════════════════════════════════════════")
