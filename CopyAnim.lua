-- Animation Copy v9.3 - CLEAN (No UI clutter)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local LP = Players.LocalPlayer

-- CONFIG
local TOGGLE_KEY = Enum.KeyCode.G
local MAX_DIST = 150

-- STATE
local copying = false
local target = nil
local hasTarget = false

-- CACHE
local char, hum, animator, root = nil, nil, nil, nil
local targetChar, targetHum, targetAnimator, targetRoot = nil, nil, nil, nil

-- ANIMATION STORAGE
local tracks = {}

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
-- ANIMATION SYNC
-- ═══════════════════════════════════════════════════════════════════

local function cleanSync()
    if not copying or not hasTarget then return end
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
-- MAIN LOOP
-- ═══════════════════════════════════════════════════════════════════

RunService.RenderStepped:Connect(function()
    if copying and hasTarget then
        cleanSync()
    end
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
        end
    end)
    
    if target.Character then
        local targetHumanoid = target.Character:FindFirstChildOfClass("Humanoid")
        if targetHumanoid then
            targetConnections.died = targetHumanoid.Died:Connect(function()
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
    
    print("✅ Copying: " .. target.Name)
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
    
    print("❌ Stopped")
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
        stop()
    end
end)

-- ═══════════════════════════════════════════════════════════════════
-- CHARACTER RESPAWN
-- ═══════════════════════════════════════════════════════════════════

LP.CharacterAdded:Connect(function(newChar)
    table.clear(tracks)
    char, hum, animator, root = nil, nil, nil, nil
    
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

print("════════════════════════════════")
print("  Animation Copy - Press [G]")
print("════════════════════════════════")
