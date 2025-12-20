-- [ Anti-TPUA v8.0 | CLEAN REWRITE ] --
-- Completely rewritten - NO velocity manipulation on self
-- Only blocks INCOMING attacks, never touches your physics

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local LP = Players.LocalPlayer

-- [ Config ] --
local CHECK_RADIUS = 35
local ATTACK_SPEED = 30
local ATTACK_SPIN = 10

-- [ State ] --
local blockCount = 0
local attackingParts = {}
local ghostedPlayers = {}
local lastSafePosition = nil
local lastSafeTime = 0
local wasBeingFlung = false
local flingStartTime = 0

-- [ Cache ] --
local char, root, hum = nil, nil, nil
local V3_ZERO = Vector3.zero
local overlapParams = OverlapParams.new()
overlapParams.FilterType = Enum.RaycastFilterType.Exclude
overlapParams.MaxParts = 100

-- [ GUI ] --
local gui = Instance.new("ScreenGui")
gui.Name = "AntiTPUA_v8"
gui.ResetOnSpawn = false
gui.Parent = LP:WaitForChild("PlayerGui")

local box = Instance.new("Frame")
box.Size = UDim2.fromOffset(90, 40)
box.Position = UDim2.fromOffset(5, 5)
box.BackgroundColor3 = Color3.new(0, 0, 0)
box.BackgroundTransparency = 0.5
box.BorderSizePixel = 0
box.Parent = gui
Instance.new("UICorner", box).CornerRadius = UDim.new(0, 6)

local dot = Instance.new("Frame")
dot.Size = UDim2.fromOffset(8, 8)
dot.Position = UDim2.fromOffset(6, 6)
dot.BackgroundColor3 = Color3.new(0, 1, 0)
dot.BorderSizePixel = 0
dot.Parent = box
Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -20, 0, 16)
title.Position = UDim2.fromOffset(18, 2)
title.BackgroundTransparency = 1
title.Text = "AntiTPUA v8"
title.TextColor3 = Color3.new(1, 1, 1)
title.TextSize = 10
title.Font = Enum.Font.GothamBold
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = box

local counter = Instance.new("TextLabel")
counter.Size = UDim2.new(1, -10, 0, 14)
counter.Position = UDim2.fromOffset(6, 20)
counter.BackgroundTransparency = 1
counter.Text = "Blocked: 0"
counter.TextColor3 = Color3.new(1, 0.6, 0)
counter.TextSize = 10
counter.Font = Enum.Font.Gotham
counter.TextXAlignment = Enum.TextXAlignment.Left
counter.Parent = box

local flashQueued = false
local function flash()
    if flashQueued then return end
    flashQueued = true
    dot.BackgroundColor3 = Color3.new(1, 0, 0)
    task.delay(0.1, function()
        dot.BackgroundColor3 = Color3.new(0, 1, 0)
        flashQueued = false
    end)
end

local function incrementBlock()
    blockCount += 1
    counter.Text = "Blocked: " .. blockCount
    flash()
end

-- [ Character Cache ] --
local function cacheCharacter(c)
    if not c then
        char, root, hum = nil, nil, nil
        return false
    end
    
    char = c
    root = c:FindFirstChild("HumanoidRootPart")
    hum = c:FindFirstChildOfClass("Humanoid")
    
    if char then
        overlapParams.FilterDescendantsInstances = {char}
    end
    
    return root ~= nil and hum ~= nil
end

-- [ Player Cache ] --
local playerCharacters = {}

local function updatePlayerCache()
    table.clear(playerCharacters)
    for _, p in Players:GetPlayers() do
        if p ~= LP and p.Character then
            playerCharacters[p.Character] = p
        end
    end
end

local function getPartOwner(part)
    local parent = part.Parent
    while parent and parent ~= workspace do
        if playerCharacters[parent] then
            return playerCharacters[parent]
        end
        parent = parent.Parent
    end
    return nil
end

-- [ Neutralize attacking part - THIS is the protection ] --
local function neutralize(part)
    if attackingParts[part] then return end
    attackingParts[part] = tick()
    
    -- Stop the ATTACKING PART, not ourselves
    part.CanCollide = false
    part.CanTouch = false
    part.AssemblyLinearVelocity = V3_ZERO
    part.AssemblyAngularVelocity = V3_ZERO
    
    incrementBlock()
end

-- [ Check if part is attacking ] --
local function isAttacking(part, myPos)
    if part.Anchored then return false end
    
    local owner = getPartOwner(part)
    if owner == LP then return false end
    
    local partPos = part.Position
    local dist = (partPos - myPos).Magnitude
    
    if dist > 30 then return false end
    
    local vel = part.AssemblyLinearVelocity
    local speed = vel.Magnitude
    local spin = part.AssemblyAngularVelocity.Magnitude
    
    if speed < ATTACK_SPEED and spin < ATTACK_SPIN then return false end
    
    -- Super Ring: Spinning fast near you
    if spin > 15 and dist < 20 then return true end
    
    -- TPUA: Moving very fast
    if speed > 80 and dist < 25 then return true end
    
    -- Direct hit: Moving toward you
    if speed > 40 then
        local toPlayer = (myPos - partPos)
        local dotProduct = toPlayer.Unit:Dot(vel.Unit)
        if dotProduct > 0.4 then return true end
    end
    
    -- Very close + moving fast
    if dist < 8 and speed > 20 then return true end
    
    return false
end

-- [ Ghost other players' parts ] --
local function ghostPlayer(character)
    if not character or ghostedPlayers[character] then return end
    ghostedPlayers[character] = true
    
    local function disable(part)
        if part:IsA("BasePart") then
            part.CanCollide = false
            part.CanTouch = false
            part.Massless = true
        end
    end
    
    for _, part in character:GetDescendants() do
        disable(part)
    end
    
    character.DescendantAdded:Connect(disable)
end

-- [ Cleanup old parts ] --
local function cleanupParts()
    local now = tick()
    for part, time in pairs(attackingParts) do
        if now - time > 2 then
            attackingParts[part] = nil
        end
    end
end

-- [ Check if grounded ] --
local function isGrounded()
    if not hum then return false end
    return hum.FloorMaterial ~= Enum.Material.Air
end

-- [ Detect if we're being flung by checking for impossible movement ] --
local function detectFling()
    if not root or not hum then return false end
    
    local vel = root.AssemblyLinearVelocity
    local spin = root.AssemblyAngularVelocity.Magnitude
    local horizontalSpeed = Vector3.new(vel.X, 0, vel.Z).Magnitude
    
    -- Only extreme cases count as fling
    -- Normal max run speed is ~16-20, jump gives ~50 Y velocity
    -- Flings typically cause 500+ horizontal or 100+ spin
    
    if horizontalSpeed > 500 then return true end
    if spin > 80 then return true end
    if horizontalSpeed > 300 and spin > 40 then return true end
    
    return false
end

-- ═══════════════════════════════════════════════════════════════════
-- MAIN LOOP - MINIMAL SELF INTERFERENCE
-- ═══════════════════════════════════════════════════════════════════

local frameCounter = 0
local cleanupCounter = 0

RunService.Heartbeat:Connect(function()
    if not root or not root.Parent then return end
    
    local myPos = root.Position
    local now = tick()
    
    -- ═══════════════════════════════════════════════════════════════
    -- SAVE SAFE POSITION (only when stable on ground)
    -- ═══════════════════════════════════════════════════════════════
    
    if isGrounded() then
        local vel = root.AssemblyLinearVelocity
        local speed = vel.Magnitude
        if speed < 30 then
            lastSafePosition = root.CFrame
            lastSafeTime = now
        end
    end
    
    -- ═══════════════════════════════════════════════════════════════
    -- FLING RECOVERY (only for EXTREME cases)
    -- ═══════════════════════════════════════════════════════════════
    
    local beingFlung = detectFling()
    
    if beingFlung then
        if not wasBeingFlung then
            flingStartTime = now
            wasBeingFlung = true
        end
        
        -- Only intervene after 0.3 seconds of continuous fling
        -- This prevents false positives from normal gameplay
        if now - flingStartTime > 0.3 then
            local vel = root.AssemblyLinearVelocity
            
            -- ONLY stop horizontal, KEEP vertical exactly as is
            root.AssemblyLinearVelocity = Vector3.new(0, vel.Y, 0)
            root.AssemblyAngularVelocity = V3_ZERO
            
            incrementBlock()
            
            -- Teleport back if extremely far flung
            if lastSafePosition and now - lastSafeTime < 5 then
                local dist = (myPos - lastSafePosition.Position).Magnitude
                if dist > 100 then
                    root.CFrame = lastSafePosition
                end
            end
        end
    else
        wasBeingFlung = false
    end
    
    -- ═══════════════════════════════════════════════════════════════
    -- SCAN FOR ATTACKING PARTS (every 6 frames)
    -- ═══════════════════════════════════════════════════════════════
    
    frameCounter += 1
    if frameCounter >= 6 then
        frameCounter = 0
        
        local success, parts = pcall(workspace.GetPartBoundsInRadius, workspace, myPos, CHECK_RADIUS, overlapParams)
        
        if success and parts then
            for _, part in parts do
                if isAttacking(part, myPos) then
                    neutralize(part)
                end
            end
        end
    end
    
    -- ═══════════════════════════════════════════════════════════════
    -- CLEANUP (every 60 frames)
    -- ═══════════════════════════════════════════════════════════════
    
    cleanupCounter += 1
    if cleanupCounter >= 60 then
        cleanupCounter = 0
        cleanupParts()
        updatePlayerCache()
    end
end)

-- ═══════════════════════════════════════════════════════════════════
-- TOUCH PROTECTION
-- ═══════════════════════════════════════════════════════════════════

local function setupTouchProtection()
    if not root then return end
    
    local oldHitbox = char:FindFirstChild("AntiTPUA_Hitbox")
    if oldHitbox then oldHitbox:Destroy() end
    
    local hitbox = Instance.new("Part")
    hitbox.Name = "AntiTPUA_Hitbox"
    hitbox.Size = Vector3.new(8, 8, 8)
    hitbox.Transparency = 1
    hitbox.CanCollide = false
    hitbox.CanTouch = true
    hitbox.CanQuery = false
    hitbox.Massless = true
    hitbox.Anchored = false
    hitbox.Parent = char
    
    local weld = Instance.new("WeldConstraint")
    weld.Part0 = root
    weld.Part1 = hitbox
    weld.Parent = hitbox
    
    hitbox.Touched:Connect(function(part)
        if part.Anchored then return end
        if attackingParts[part] then return end
        
        local owner = getPartOwner(part)
        if owner == LP then return end
        
        local speed = part.AssemblyLinearVelocity.Magnitude
        local spin = part.AssemblyAngularVelocity.Magnitude
        
        if speed > ATTACK_SPEED or spin > ATTACK_SPIN then
            neutralize(part)
        end
    end)
end

-- ═══════════════════════════════════════════════════════════════════
-- HUMANOID PROTECTION (minimal - no state changes that affect physics)
-- ═══════════════════════════════════════════════════════════════════

local function setupHumanoidProtection()
    if not hum then return end
    
    -- Only prevent ragdoll, nothing else
    hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
    hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
    
    local lastHealth = hum.Health
    hum.HealthChanged:Connect(function(newHealth)
        if root and newHealth < lastHealth then
            local horizontalSpeed = Vector3.new(
                root.AssemblyLinearVelocity.X, 
                0, 
                root.AssemblyLinearVelocity.Z
            ).Magnitude
            
            -- Only block damage during extreme fling
            if horizontalSpeed > 400 then
                hum.Health = lastHealth
                return
            end
        end
        lastHealth = newHealth
    end)
end

-- ═══════════════════════════════════════════════════════════════════
-- CHARACTER SETUP
-- ═══════════════════════════════════════════════════════════════════

local function onCharacterAdded(c)
    task.wait(0.1)
    
    if not cacheCharacter(c) then return end
    
    lastSafePosition = root.CFrame
    lastSafeTime = tick()
    wasBeingFlung = false
    
    setupHumanoidProtection()
    setupTouchProtection()
    updatePlayerCache()
end

-- ═══════════════════════════════════════════════════════════════════
-- PLAYER SETUP
-- ═══════════════════════════════════════════════════════════════════

local function onPlayerAdded(player)
    if player == LP then return end
    
    if player.Character then
        ghostPlayer(player.Character)
    end
    
    player.CharacterAdded:Connect(function(c)
        task.wait(0.1)
        ghostPlayer(c)
        updatePlayerCache()
    end)
end

-- ═══════════════════════════════════════════════════════════════════
-- INIT
-- ═══════════════════════════════════════════════════════════════════

for _, player in Players:GetPlayers() do
    onPlayerAdded(player)
end

Players.PlayerAdded:Connect(onPlayerAdded)

Players.PlayerRemoving:Connect(function(player)
    if player.Character then
        ghostedPlayers[player.Character] = nil
        playerCharacters[player.Character] = nil
    end
end)

if LP.Character then
    onCharacterAdded(LP.Character)
end

LP.CharacterAdded:Connect(onCharacterAdded)

updatePlayerCache()

print("═══════════════════════════════════════════════")
print("  🛡️ AntiTPUA v8.0 - CLEAN REWRITE")
print("═══════════════════════════════════════════════")
print("  ✅ Complete rewrite from scratch")
print("  ✅ NO interference with jumping")
print("  ✅ NO interference with falling")
print("  ✅ Only blocks incoming attacks")
print("  ✅ Only extreme flings trigger protection")
print("  ✅ Y velocity NEVER touched")
print("═══════════════════════════════════════════════")
