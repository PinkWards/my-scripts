local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local LP = Players.LocalPlayer
local WS = game:GetService("Workspace")

-- CONFIG
local MAX_VEL = 80
local FLING_ACCEL = 500
local EXTREME_VEL_SQ = 250000 -- 500^2

-- STATE
local root, char, safeCF = nil, nil, nil
local flings = 0
local protecting = false
local lastVel = Vector3.zero
local lastTime = 0
local V3Zero = Vector3.zero

-- FLY MOVERS (whitelist - never interfere with these)
local FLY_WHITELIST = {
    BodyVelocity = true,
    BodyGyro = true,
    BodyPosition = true,
    VectorForce = true,
    LinearVelocity = true,
    AlignPosition = true,
    AlignOrientation = true,
    BodyForce = true,
    BodyThrust = true,
}

-- FLING MOVERS (these are suspicious when added by others)
local FLING_MOVERS = {
    RocketPropulsion = true,
    BodyAngularVelocity = true,
}

-- SUPER RING DETECTION CACHE
local badParts = {}

-- ═══════════════════════════════════════════════════════════════════
-- FLY DETECTION (checks if YOU are using fly)
-- ═══════════════════════════════════════════════════════════════════

local isFlying = false
local flyCheckCounter = 0

local function updateFlyStatus()
    if not char then 
        isFlying = false
        return 
    end
    
    for _, obj in char:GetDescendants() do
        if FLY_WHITELIST[obj.ClassName] then
            isFlying = true
            return
        end
    end
    isFlying = false
end

-- ═══════════════════════════════════════════════════════════════════
-- FLING DETECTION (acceleration spike detection)
-- ═══════════════════════════════════════════════════════════════════

local function isFling(vel)
    local now = tick()
    local dt = now - lastTime
    if dt < 0.0001 then dt = 0.0001 end
    
    local velDiff = vel - lastVel
    local accel = velDiff.Magnitude / dt
    
    lastVel = vel
    lastTime = now
    
    -- Fling = sudden massive acceleration
    return accel > FLING_ACCEL and vel.Magnitude > 120
end

-- ═══════════════════════════════════════════════════════════════════
-- SUPER RING / MALICIOUS PART DETECTION
-- ═══════════════════════════════════════════════════════════════════

local function isSuperRing(part)
    if not part:IsA("BasePart") or part.Anchored then return false end
    
    -- Zero physics = super ring
    local cpp = part.CustomPhysicalProperties
    if cpp then
        if cpp.Density == 0 and cpp.Friction == 0 and cpp.Elasticity == 0 then
            return true
        end
    end
    
    -- Invisible + high speed = fling part
    if part.Transparency >= 0.9 then
        local v = part.AssemblyLinearVelocity
        if v.Magnitude > 200 then
            return true
        end
    end
    
    -- Massless + high speed
    if part.Massless then
        local v = part.AssemblyLinearVelocity
        if v.Magnitude > 300 then
            return true
        end
    end
    
    return false
end

local function neutralizePart(part)
    part.CanCollide = false
    part.CanTouch = false
    part.Massless = true
    
    -- Kill velocity
    pcall(function()
        part.AssemblyLinearVelocity = V3Zero
        part.AssemblyAngularVelocity = V3Zero
    end)
    
    -- Try destroy
    pcall(part.Destroy, part)
end

-- ═══════════════════════════════════════════════════════════════════
-- MAIN PROTECTION LOOP (ultra optimized)
-- ═══════════════════════════════════════════════════════════════════

RunService.RenderStepped:Connect(function()
    if not root then return end
    
    local vel = root.AssemblyLinearVelocity
    local velSq = vel.X*vel.X + vel.Y*vel.Y + vel.Z*vel.Z
    
    -- Update fly status every 10 frames
    flyCheckCounter += 1
    if flyCheckCounter >= 10 then
        flyCheckCounter = 0
        updateFlyStatus()
    end
    
    -- FLYING MODE: Allow high speed, only block extreme flings
    if isFlying then
        if velSq > EXTREME_VEL_SQ and isFling(vel) then
            root.AssemblyLinearVelocity = lastVel * 0.5
            root.AssemblyAngularVelocity = V3Zero
            flings += 1
            protecting = true
        else
            protecting = false
            if velSq < 625 then -- 25^2
                safeCF = root.CFrame
            end
        end
        return
    end
    
    -- NORMAL MODE: Full protection
    
    -- EXTREME VELOCITY: Instant freeze + teleport
    if velSq > 160000 then -- 400^2
        root.AssemblyLinearVelocity = V3Zero
        root.AssemblyAngularVelocity = V3Zero
        if safeCF then
            root.CFrame = safeCF
        end
        flings += 1
        protecting = true
        return
    end
    
    -- HIGH VELOCITY: Check if fling
    if velSq > 14400 then -- 120^2
        if isFling(vel) then
            root.AssemblyLinearVelocity = V3Zero
            root.AssemblyAngularVelocity = V3Zero
            if safeCF and velSq > 40000 then
                root.CFrame = safeCF
            end
            flings += 1
            protecting = true
            return
        end
    end
    
    -- MEDIUM VELOCITY: Clamp
    if velSq > 6400 then -- 80^2
        root.AssemblyLinearVelocity = vel.Unit * MAX_VEL
        protecting = false
        return
    end
    
    -- NORMAL: Save safe position
    protecting = false
    if velSq < 400 then -- 20^2
        safeCF = root.CFrame
    end
end)

-- ═══════════════════════════════════════════════════════════════════
-- ANGULAR VELOCITY PROTECTION (prevents spin flings)
-- ═══════════════════════════════════════════════════════════════════

RunService.Heartbeat:Connect(function()
    if not root or isFlying then return end
    
    local angVel = root.AssemblyAngularVelocity
    local angMag = angVel.Magnitude
    
    if angMag > 50 then
        root.AssemblyAngularVelocity = angVel.Unit * 20
    end
end)

-- ═══════════════════════════════════════════════════════════════════
-- CHARACTER SETUP
-- ═══════════════════════════════════════════════════════════════════

local function onChar(c)
    char = c
    root = c:WaitForChild("HumanoidRootPart", 5)
    if root then
        safeCF = root.CFrame
        lastVel = Vector3.zero
        lastTime = tick()
    end
    
    -- Remove suspicious movers added to character
    c.DescendantAdded:Connect(function(obj)
        if FLING_MOVERS[obj.ClassName] then
            task.defer(function()
                if obj.Parent then
                    pcall(obj.Destroy, obj)
                end
            end)
        end
    end)
end

LP.CharacterAdded:Connect(onChar)
if LP.Character then task.spawn(onChar, LP.Character) end

-- ═══════════════════════════════════════════════════════════════════
-- OTHER PLAYERS: FULL NOCLIP + VELOCITY NEUTRALIZE
-- ═══════════════════════════════════════════════════════════════════

local function protectFromPlayer(player)
    if player == LP then return end
    
    local function handleChar(c)
        if not c then return end
        task.wait(0.1)
        
        -- Disable all collision
        for _, part in c:GetDescendants() do
            if part:IsA("BasePart") then
                part.CanCollide = false
                part.CanTouch = false
            end
        end
        
        -- Monitor new parts
        c.DescendantAdded:Connect(function(part)
            if part:IsA("BasePart") then
                part.CanCollide = false
                part.CanTouch = false
            end
        end)
    end
    
    if player.Character then handleChar(player.Character) end
    player.CharacterAdded:Connect(handleChar)
end

for _, p in Players:GetPlayers() do
    task.spawn(protectFromPlayer, p)
end
Players.PlayerAdded:Connect(protectFromPlayer)

-- ═══════════════════════════════════════════════════════════════════
-- WORKSPACE PROTECTION: Destroy/Neutralize Fling Parts
-- ═══════════════════════════════════════════════════════════════════

WS.DescendantAdded:Connect(function(obj)
    -- Check BaseParts
    if obj:IsA("BasePart") then
        task.defer(function()
            if not obj.Parent then return end
            if isSuperRing(obj) then
                neutralizePart(obj)
                flings += 1
            end
        end)
        return
    end
    
    -- Check constraints that could fling
    if obj:IsA("Constraint") then
        task.defer(function()
            if not obj.Parent then return end
            
            -- Check if constraint targets local player
            local att0 = obj:FindFirstChild("Attachment0") or obj.Attachment0
            local att1 = obj:FindFirstChild("Attachment1") or obj.Attachment1
            
            if char then
                local targetsMe = false
                if att0 and att0:IsDescendantOf(char) then targetsMe = true end
                if att1 and att1:IsDescendantOf(char) then targetsMe = true end
                
                if targetsMe then
                    pcall(obj.Destroy, obj)
                end
            end
        end)
    end
end)

-- ═══════════════════════════════════════════════════════════════════
-- PROXIMITY FLING PART SCANNER (catches nearby threats)
-- ═══════════════════════════════════════════════════════════════════

local scanCounter = 0
RunService.Stepped:Connect(function()
    if not root then return end
    
    scanCounter += 1
    if scanCounter < 15 then return end -- Every 15 frames
    scanCounter = 0
    
    local myPos = root.Position
    
    -- Check workspace children only (faster)
    for _, obj in WS:GetChildren() do
        if obj:IsA("BasePart") and not obj.Anchored then
            local dist = (obj.Position - myPos).Magnitude
            if dist < 50 then
                local vel = obj.AssemblyLinearVelocity.Magnitude
                if vel > 300 and isSuperRing(obj) then
                    neutralizePart(obj)
                end
            end
        end
    end
end)

-- ═══════════════════════════════════════════════════════════════════
-- EMERGENCY FREEZE (backup protection)
-- ═══════════════════════════════════════════════════════════════════

local lastPos = nil
local stuckCounter = 0

RunService.PreRender:Connect(function()
    if not root or isFlying then return end
    
    local pos = root.Position
    local vel = root.AssemblyLinearVelocity
    
    -- Detect being flung into void
    if pos.Y < -200 then
        if safeCF then
            root.CFrame = safeCF
            root.AssemblyLinearVelocity = V3Zero
            root.AssemblyAngularVelocity = V3Zero
            flings += 1
        end
        return
    end
    
    -- Detect rapid position change (teleport fling)
    if lastPos then
        local posDiff = (pos - lastPos).Magnitude
        if posDiff > 100 and vel.Magnitude > 200 then
            if safeCF then
                root.CFrame = safeCF
                root.AssemblyLinearVelocity = V3Zero
                root.AssemblyAngularVelocity = V3Zero
                flings += 1
            end
        end
    end
    
    lastPos = pos
end)

-- ═══════════════════════════════════════════════════════════════════
-- TINY GUI (status only)
-- ═══════════════════════════════════════════════════════════════════

local gui = Instance.new("ScreenGui")
gui.Name = "AntiFlingUltimate"
gui.ResetOnSpawn = false
gui.Parent = LP:WaitForChild("PlayerGui")

local lbl = Instance.new("TextLabel")
lbl.Size = UDim2.fromOffset(100, 22)
lbl.Position = UDim2.new(0, 8, 0.5, -11)
lbl.BackgroundColor3 = Color3.fromRGB(15, 25, 15)
lbl.BackgroundTransparency = 0.1
lbl.TextColor3 = Color3.fromRGB(100, 255, 100)
lbl.Font = Enum.Font.GothamBold
lbl.TextSize = 11
lbl.Text = "🛡️ 0"
lbl.Parent = gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 4)
corner.Parent = lbl

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(50, 100, 50)
stroke.Thickness = 1
stroke.Parent = lbl

-- Update GUI (slow - 2Hz)
task.spawn(function()
    while task.wait(0.5) do
        if isFlying then
            lbl.Text = "✈️ " .. flings
            lbl.TextColor3 = Color3.fromRGB(100, 180, 255)
            lbl.BackgroundColor3 = Color3.fromRGB(15, 25, 40)
            stroke.Color = Color3.fromRGB(50, 80, 120)
        elseif protecting then
            lbl.Text = "⚠️ " .. flings
            lbl.TextColor3 = Color3.fromRGB(255, 100, 100)
            lbl.BackgroundColor3 = Color3.fromRGB(40, 15, 15)
            stroke.Color = Color3.fromRGB(120, 50, 50)
        else
            lbl.Text = "🛡️ " .. flings
            lbl.TextColor3 = Color3.fromRGB(100, 255, 100)
            lbl.BackgroundColor3 = Color3.fromRGB(15, 25, 15)
            stroke.Color = Color3.fromRGB(50, 100, 50)
        end
    end
end)

-- ═══════════════════════════════════════════════════════════════════

print("═══════════════════════════════════════")
print("  🛡️ ULTIMATE ANTI-FLING v9.0")
print("═══════════════════════════════════════")
print("  ✓ Always ON (no toggle needed)")
print("  ✓ Fly/TP compatible")
print("  ✓ Super ring immune")
print("  ✓ Constraint fling immune")
print("  ✓ Spin fling immune")
print("  ✓ Void fling protection")
print("  ✓ Zero lag optimized")
print("═══════════════════════════════════════")
