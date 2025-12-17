-- Ultra-Clean Animation Copy Script v5.3 (No GUI)
-- Perfect Sync Edition

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer

-- Settings
local CONFIG = {
    ToggleKey = Enum.KeyCode.H,
    MaxDistance = 150,
}

-- State
local isCopying = false
local targetPlayer = nil
local mainConnection = nil

-- Animation storage
local loadedAnims = {}
local playingTracks = {}
local lastSyncTime = {}

-- Store original animate script
local animateScriptDisabled = false

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
-- MAIN UPDATE LOOP
-- ═══════════════════════════════════════════════════════════════════

local function update()
    if not isCopying then return end
    
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
    
    targetPlayer = getNearestPlayer()
    
    print("═══════════════════════════════════")
    print("✅ Animation Copy: ON")
    if targetPlayer then
        print("📌 Copying: " .. targetPlayer.Name)
    else
        print("🔍 Waiting for nearby player...")
    end
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
-- CHARACTER RESPAWN HANDLING
-- ═══════════════════════════════════════════════════════════════════

LocalPlayer.CharacterAdded:Connect(function(char)
    playingTracks = {}
    loadedAnims = {}
    lastSyncTime = {}
    animateScriptDisabled = false
    
    local hum = char:WaitForChild("Humanoid", 10)
    if not hum then return end
    
    task.wait(0.3)
    
    if isCopying then
        disableAnimateScript()
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
print("    ✓ 100% frame-perfect sync")
print("    ✓ No twisted arms/legs")
print("    ✓ Auto-targets nearest player")
print("═══════════════════════════════════════════")
