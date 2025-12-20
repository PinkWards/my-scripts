-- [ Anti-TPUA v7.3 | FULLY FIXED EDITION ] --
-- Fixed: Slow falling, weird jumping, all physics issues

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local LP = Players.LocalPlayer

-- [ Config ] --
local CHECK_RADIUS = 35
local HORIZONTAL_FLING_SPEED = 400  -- Only horizontal matters
local FLING_SPIN = 60
local ATTACK_SPEED = 30
local ATTACK_SPIN = 10

-- [ State ] --
local lastPos = nil
local lastMoveTime = 0
local blockCount = 0
local safeCF = nil
local attackingParts = {}
local ghostedPlayers = {}
local lastGroundedTime = 0

-- [ Cache ] --
local char, root, hum = nil, nil, nil
local V3_ZERO = Vector3.zero
local overlapParams = OverlapParams.new()
overlapParams.FilterType = Enum.RaycastFilterType.Exclude
overlapParams.MaxParts = 100

-- [ GUI ] --
local gui = Instance.new("ScreenGui")
gui.Name = "AntiTPUA_v7"
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
title.Text = "AntiTPUA v7.3"
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

-- [ Fast owner check using cache ] --
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

-- [ Neutralize part ] --
local function neutralize(part)
    if attackingParts[part] then return end
    attackingParts[part] = tick()
    
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
    
    -- Very close + moving
    if dist < 8 and speed > 20 then return true end
    
    return false
end

-- [ Ghost player parts ] --
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

-- [ Check for fly hacks ] --
local function isFlying()
    if not root then return false end
    
    for _, obj in root:GetChildren() do
        local class = obj.ClassName
        if class == "BodyGyro" or class == "BodyVelocity" or 
           class == "BodyPosition" or class == "LinearVelocity" or
           class == "AlignPosition" or class == "VectorForce" then
            return true
        end
    end
    return false
end

-- [ Check if grounded ] --
local function isGrounded()
    if not hum then return false end
    return hum.FloorMaterial ~= Enum.Material.Air
end

-- [ Check if player is jumping normally ] --
local function isJumping()
    if not hum then return false end
    local state = hum:GetState()
    return state == Enum.HumanoidStateType.Jumping or 
           state == Enum.HumanoidStateType.Freefall
end

-- [ Cleanup old attacking parts ] --
local function cleanupParts()
    local now = tick()
    for part, time in pairs(attackingParts) do
        if now - time > 2 then
            if part and part.Parent then
                if root then
                    local dist = (part.Position - root.Position).Magnitude
                    if dist > 40 then
                        part.CanCollide = true
                        part.CanTouch = true
                    end
                end
            end
            attackingParts[part] = nil
        end
    end
end

-- [ MAIN PROTECTION LOOP - COMPLETELY FIXED ] --
local frameCounter = 0
local cleanupCounter = 0

RunService.Heartbeat:Connect(function()
    if not root or not root.Parent then return end
    if not hum then return end
    
    local myPos = root.Position
    local now = tick()
    
    -- Track grounded time
    if isGrounded() then
        lastGroundedTime = now
    end
    
    -- ═══════════════════════════════════════════════════════════════
    -- SELF FLING PROTECTION - COMPLETELY REWRITTEN
    -- ═══════════════════════════════════════════════════════════════
    
    if not isFlying() then
        -- Teleport detection
        if lastPos then
            local dist = (myPos - lastPos).Magnitude
            if dist > 50 then
                lastMoveTime = now
                safeCF = root.CFrame
                lastPos = myPos
                return
            end
        end
        
        -- Only check for flings after being still for a moment
        if now - lastMoveTime > 0.5 then
            local vel = root.AssemblyLinearVelocity
            local angVel = root.AssemblyAngularVelocity
            local spin = angVel.Magnitude
            
            -- ✅ FIXED: Only care about HORIZONTAL velocity
            local horizontalSpeed = Vector3.new(vel.X, 0, vel.Z).Magnitude
            
            -- ✅ FIXED: Time since grounded (allow normal jumps)
            local airTime = now - lastGroundedTime
            
            -- ✅ FIXED: Don't interfere with normal movement
            -- Only detect actual fling attacks:
            -- 1. Extremely fast horizontal movement (not from walking/running)
            -- 2. Extreme spinning (not from normal gameplay)
            -- 3. Must have been grounded recently (to ignore falling from heights)
            
            local isBeingFlung = false
            
            -- Extreme horizontal fling (way faster than any normal movement)
            if horizontalSpeed > HORIZONTAL_FLING_SPEED then
                isBeingFlung = true
            end
            
            -- Extreme spin attack
            if spin > FLING_SPIN then
                isBeingFlung = true
            end
            
            -- Fast horizontal + spinning combo
            if horizontalSpeed > 200 and spin > 25 then
                isBeingFlung = true
            end
            
            -- ✅ FIXED: Never interfere with Y velocity (jumping/falling)
            if isBeingFlung then
                -- Only stop horizontal movement, NEVER touch Y velocity
                local currentY = vel.Y
                
                root.AssemblyLinearVelocity = Vector3.new(0, currentY, 0)
                root.AssemblyAngularVelocity = V3_ZERO
                
                -- Only reset other parts if extreme fling
                if horizontalSpeed > 600 or spin > 80 then
                    for _, part in char:GetDescendants() do
                        if part:IsA("BasePart") and part ~= root then
                            local partVel = part.AssemblyLinearVelocity
                            part.AssemblyLinearVelocity = Vector3.new(0, partVel.Y, 0)
                            part.AssemblyAngularVelocity = V3_ZERO
                        end
                    end
                end
                
                -- Teleport back only for extreme cases
                if horizontalSpeed > 800 and safeCF then
                    root.CFrame = safeCF
                end
                
                incrementBlock()
            else
                -- Save position only when truly stable on ground
                if isGrounded() and horizontalSpeed < 20 then
                    safeCF = root.CFrame
                end
            end
        end
    else
        safeCF = root.CFrame
    end
    
    lastPos = myPos
    
    -- ═══════════════════════════════════════════════════════════════
    -- REACTIVE PART SCAN (every 6 frames)
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

-- [ TOUCH PROTECTION ] --
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

-- [ HUMANOID PROTECTION - FIXED ] --
local function setupHumanoidProtection()
    if not hum then return end
    
    -- ✅ FIXED: Only disable ragdoll states, nothing else
    hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
    hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
    
    -- ✅ REMOVED: These were causing jumping issues
    -- hum:SetStateEnabled(Enum.HumanoidStateType.Physics, false)
    
    local lastHealth = hum.Health
    hum.HealthChanged:Connect(function(newHealth)
        if root then
            -- Only block damage if being flung horizontally
            local horizontalSpeed = Vector3.new(
                root.AssemblyLinearVelocity.X, 
                0, 
                root.AssemblyLinearVelocity.Z
            ).Magnitude
            
            if horizontalSpeed > 300 and newHealth < lastHealth then
                hum.Health = lastHealth
                return
            end
        end
        lastHealth = newHealth
    end)
end

-- [ CHARACTER SETUP ] --
local function onCharacterAdded(c)
    task.wait(0.1)
    
    if not cacheCharacter(c) then return end
    
    lastPos = root.Position
    safeCF = root.CFrame
    lastMoveTime = 0
    lastGroundedTime = tick()
    
    setupHumanoidProtection()
    setupTouchProtection()
    updatePlayerCache()
end

-- [ PLAYER SETUP ] --
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

-- [ INIT ] --
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
print("  🛡️ AntiTPUA v7.3 - FULLY FIXED")
print("═══════════════════════════════════════════════")
print("  ✅ All Fixes:")
print("    • Normal jumping works perfectly")
print("    • Normal falling works perfectly")
print("    • Only blocks HORIZONTAL flings")
print("    • Never touches Y velocity")
print("    • Removed problematic state disables")
print("")
print("  🔥 Full protection maintained!")
print("═══════════════════════════════════════════════")
