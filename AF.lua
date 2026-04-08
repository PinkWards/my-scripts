local Players        = game:GetService("Players")
local RunService     = game:GetService("RunService")
local PhysicsService = game:GetService("PhysicsService")
local LP             = Players.LocalPlayer

local V3ZERO    = Vector3.zero
local ANG_CAP   = 8  -- Stricter angular control
local HORIZ_CAP = 100  -- Tighter horizontal control
local UP_CAP    = 80
local DOWN_CAP  = 150
local SCAN_RAD  = 35  -- Larger detection radius

local trackedPlayers   = {}
local trackedCharConns = {}
local conns            = {}

-- ═══════════════════════════════════════════════
-- COLLISION GROUPS (ENHANCED)
-- ═══════════════════════════════════════════════
local cgWork = false
pcall(function()
    PhysicsService:RegisterCollisionGroup("_af_me")
    PhysicsService:RegisterCollisionGroup("_af_them")
    PhysicsService:CollisionGroupSetCollidable("_af_me", "_af_them", false)
    PhysicsService:CollisionGroupSetCollidable("_af_them", "_af_them", false)
    cgWork = true
end)

-- ═══════════════════════════════════════════════
-- DANGEROUS FORCE CLASS NAMES
-- ═══════════════════════════════════════════════
local DANGEROUS = {
    BodyVelocity = true, BodyAngularVelocity = true, BodyForce = true,
    BodyPosition = true, BodyGyro = true, BodyThrust = true, 
    RocketPropulsion = true, Torque = true, VectorForce = true, 
    LinearVelocity = true, AlignPosition = true, AlignOrientation = true, 
    AngularVelocity = true
}

-- ═══════════════════════════════════════════════
-- UTILITY (MAXIMIZED)
-- ═══════════════════════════════════════════════
local processedParts = setmetatable({}, {__mode = "k"}) -- Weak table for auto-cleanup

local function safeSet(part, props)
    for prop, val in pairs(props) do
        if part[prop] ~= val then
            part[prop] = val
        end
    end
end

local function killPart(part)
    if not part:IsA("BasePart") or processedParts[part] then return end
    processedParts[part] = true
    
    -- Batch property setting for performance
    safeSet(part, {
        CanCollide = false,
        CanTouch = false,
        CanQuery = false,
        Massless = true,
        CollisionGroup = cgWork and "_af_them" or part.CollisionGroup
    })
end

local function killPartVelocity(part)
    if part.AssemblyLinearVelocity ~= V3ZERO or part.AssemblyAngularVelocity ~= V3ZERO then
        safeSet(part, {
            AssemblyLinearVelocity = V3ZERO,
            AssemblyAngularVelocity = V3ZERO
        })
    end
end

-- ═══════════════════════════════════════════════
-- NEUTRALIZE OTHER PLAYERS (MAXIMUM POWER)
-- ═══════════════════════════════════════════════
local function trackChar(ch, plr)
    if not ch then return end

    if trackedCharConns[plr] then
        for _, c in ipairs(trackedCharConns[plr]) do
            c:Disconnect()
        end
    end

    local charConns = {}
    trackedCharConns[plr] = charConns

    -- Immediate neutralization
    local descendants = ch:GetDescendants()
    for i = 1, #descendants do
        local part = descendants[i]
        if part:IsA("BasePart") then
            killPart(part)
            killPartVelocity(part)
        end
    end

    -- Continuous enforcement on new parts
    charConns[#charConns + 1] = ch.DescendantAdded:Connect(function(p)
        if p:IsA("BasePart") then
            killPart(p)
            killPartVelocity(p)
            -- Double-tap to ensure it sticks
            task.defer(function()
                killPart(p)
                killPartVelocity(p)
            end)
        end
    end)
end

local function trackPlayer(plr)
    if plr == LP or trackedPlayers[plr] then return end
    trackedPlayers[plr] = true
    if plr.Character then trackChar(plr.Character, plr) end
    plr.CharacterAdded:Connect(function(c)
        task.wait(0.05)
        trackChar(c, plr)
    end)
end

for _, plr in ipairs(Players:GetPlayers()) do trackPlayer(plr) end
Players.PlayerAdded:Connect(trackPlayer)
Players.PlayerRemoving:Connect(function(plr)
    trackedPlayers[plr] = nil
    if trackedCharConns[plr] then
        for _, c in ipairs(trackedCharConns[plr]) do
            c:Disconnect()
        end
        trackedCharConns[plr] = nil
    end
end)

-- Aggressive periodic re-enforcement
task.spawn(function()
    while true do
        task.wait(0.2) -- Faster re-enforcement
        for plr in pairs(trackedPlayers) do
            local ch = plr.Character
            if ch then
                local descendants = ch:GetDescendants()
                for i = 1, #descendants do
                    local part = descendants[i]
                    if part:IsA("BasePart") then
                        killPart(part)
                        -- Kill velocity if they're moving fast
                        if part.AssemblyLinearVelocity.Magnitude > 50 then
                            killPartVelocity(part)
                        end
                    end
                end
            end
        end
    end
end)

-- ═══════════════════════════════════════════════
-- CHARACTER PROTECTION (ULTRA MODE)
-- ═══════════════════════════════════════════════
local function clearConns()
    for i = #conns, 1, -1 do
        conns[i]:Disconnect()
        conns[i] = nil
    end
end
local function reg(c) conns[#conns + 1] = c return c end

local function protect(char)
    if not char then return end
    clearConns()
    processedParts = setmetatable({}, {__mode = "k"})

    local hrp = char:WaitForChild("HumanoidRootPart", 5)
    local hum = char:WaitForChild("Humanoid", 5)
    if not hrp or not hum then return end

    local overlapParams = OverlapParams.new()
    overlapParams.FilterType = Enum.RaycastFilterType.Exclude
    overlapParams.FilterDescendantsInstances = {char}

    -- ═══════════════════════════════════
    -- OUR COLLISION GROUP (ENFORCED)
    -- ═══════════════════════════════════
    local function fortify(p)
        if not p:IsA("BasePart") then return end
        if cgWork then 
            safeSet(p, {
                CollisionGroup = "_af_me",
                CanCollide = true,  -- Keep our parts solid to each other
                Massless = false
            })
        end
    end

    local descendants = char:GetDescendants()
    for i = 1, #descendants do 
        fortify(descendants[i]) 
    end
    
    reg(char.DescendantAdded:Connect(fortify))

    -- Lock collision group aggressively
    if cgWork then
        for i = 1, #descendants do
            local p = descendants[i]
            if p:IsA("BasePart") then
                reg(p:GetPropertyChangedSignal("CollisionGroup"):Connect(function()
                    if p.CollisionGroup ~= "_af_me" then
                        p.CollisionGroup = "_af_me"
                    end
                end))
                
                -- Prevent collision disabling
                reg(p:GetPropertyChangedSignal("CanCollide"):Connect(function()
                    if p.Name ~= "HumanoidRootPart" and not p.CanCollide then
                        p.CanCollide = true
                    end
                end))
            end
        end
        
        reg(char.DescendantAdded:Connect(function(p)
            if p:IsA("BasePart") then
                reg(p:GetPropertyChangedSignal("CollisionGroup"):Connect(function()
                    if p.CollisionGroup ~= "_af_me" then
                        p.CollisionGroup = "_af_me"
                    end
                end))
            end
        end))
    end

    -- ═══════════════════════════════════
    -- VELOCITY CLAMPING (ULTRA STRICT)
    -- ═══════════════════════════════════
    local lastVelCheck = 0
    
    local function clampVelocity()
        if not char.Parent or not hrp.Parent then return end

        -- Always neutralize angular velocity immediately
        local angVel = hrp.AssemblyAngularVelocity
        if angVel.Magnitude > ANG_CAP then
            hrp.AssemblyAngularVelocity = V3ZERO
        end

        local vel = hrp.AssemblyLinearVelocity
        local vx, vy, vz = vel.X, vel.Y, vel.Z
        local hMag = math.sqrt(vx * vx + vz * vz)
        local dirty = false

        if hMag > HORIZ_CAP then
            local s = HORIZ_CAP / hMag
            vx, vz = vx * s, vz * s
            dirty = true
        end

        if vy > UP_CAP then
            vy = UP_CAP
            dirty = true
        elseif vy < -DOWN_CAP then
            vy = -DOWN_CAP
            dirty = true
        end

        if dirty then
            hrp.AssemblyLinearVelocity = Vector3.new(vx, vy, vz)
        end
    end

    -- Double enforcement for maximum protection
    reg(RunService.Heartbeat:Connect(clampVelocity))
    reg(RunService.Stepped:Connect(clampVelocity))

    -- ═══════════════════════════════════
    -- NEARBY PART SCAN (MAXIMUM AGGRESSION)
    -- ═══════════════════════════════════
    local lastScan = 0
    local SCAN_INTERVAL = 0.05 -- Faster scanning
    
    reg(RunService.Heartbeat:Connect(function()
        if not char.Parent or not hrp.Parent then return end
        
        local now = tick()
        if now - lastScan < SCAN_INTERVAL then return end
        lastScan = now

        local ok, nearby = pcall(function()
            return workspace:GetPartBoundsInRadius(hrp.Position, SCAN_RAD, overlapParams)
        end)

        if not ok or not nearby then return end

        for i = 1, #nearby do
            local part = nearby[i]
            if not part.Anchored and not part:IsDescendantOf(char) then
                local isPlayer = false
                for plr in pairs(trackedPlayers) do
                    if plr.Character and part:IsDescendantOf(plr.Character) then
                        isPlayer = true
                        break
                    end
                end

                if isPlayer then
                    -- Aggressive player part neutralization
                    killPart(part)
                    killPartVelocity(part)
                else
                    -- Workspace parts - only kill if dangerous
                    local av = part.AssemblyAngularVelocity.Magnitude
                    local lv = part.AssemblyLinearVelocity.Magnitude
                    if av > 3 or lv > 15 then
                        killPart(part)
                        killPartVelocity(part)
                    end
                end
            end
        end
    end))

    -- ═══════════════════════════════════
    -- FORCE / WELD GUARD (INSTANT DESTROY)
    -- ═══════════════════════════════════
    reg(char.DescendantAdded:Connect(function(obj)
        if DANGEROUS[obj.ClassName] then
            obj:Destroy()
            return
        end

        if obj:IsA("JointInstance") or obj:IsA("WeldConstraint") or obj:IsA("Constraint") then
            task.defer(function()
                if not obj.Parent then return end
                local p0, p1
                if obj:IsA("Constraint") then
                    p0 = obj.Attachment0 and obj.Attachment0.Parent
                    p1 = obj.Attachment1 and obj.Attachment1.Parent
                else
                    p0, p1 = obj.Part0, obj.Part1
                end
                if p0 and p1 and (p0:IsDescendantOf(char) ~= p1:IsDescendantOf(char)) then
                    obj:Destroy()
                end
            end)
        end
    end))

    -- ═══════════════════════════════════
    -- SEAT GUARD (INSTANT REJECT)
    -- ═══════════════════════════════════
    reg(hum:GetPropertyChangedSignal("SeatPart"):Connect(function()
        local seat = hum.SeatPart
        if not seat then return end
        
        -- Reject any seat from other players
        for plr in pairs(trackedPlayers) do
            if plr.Character and seat:IsDescendantOf(plr.Character) then
                hum.Sit = false
                return
            end
        end
        
        -- Reject dangerous moving seats
        if not seat.Anchored and not seat:IsDescendantOf(char) then
            if seat.AssemblyAngularVelocity.Magnitude > 5 or seat.AssemblyLinearVelocity.Magnitude > 30 then
                hum.Sit = false
            end
        end
    end))

    -- ═══════════════════════════════════
    -- TOUCH GUARD (AGGRESSIVE)
    -- ═══════════════════════════════════
    local touchCooldowns = setmetatable({}, {__mode = "k"})
    local TOUCH_COOLDOWN = 0.05
    
    local function hookTouch(bp)
        if not bp:IsA("BasePart") then return end
        reg(bp.Touched:Connect(function(hit)
            if not hit or not hit.Parent then return end
            if hit:IsDescendantOf(char) or hit.Anchored then return end
            
            local now = tick()
            if touchCooldowns[hit] and now - touchCooldowns[hit] < TOUCH_COOLDOWN then
                return
            end
            touchCooldowns[hit] = now

            -- Check if it's a player part
            local isPlayerPart = false
            for plr in pairs(trackedPlayers) do
                if plr.Character and hit:IsDescendantOf(plr.Character) then
                    isPlayerPart = true
                    break
                end
            end

            if isPlayerPart then
                -- Instantly neutralize player parts on touch
                killPart(hit)
                killPartVelocity(hit)
                task.defer(clampVelocity)
            else
                -- Only neutralize workspace parts if dangerous
                local av = hit.AssemblyAngularVelocity.Magnitude
                local lv = hit.AssemblyLinearVelocity.Magnitude
                if av > 3 or lv > 15 then
                    killPart(hit)
                    killPartVelocity(hit)
                    task.defer(clampVelocity)
                end
            end
        end))
    end

    for i = 1, #descendants do hookTouch(descendants[i]) end
    reg(char.DescendantAdded:Connect(hookTouch))

    -- ═══════════════════════════════════
    -- PLATFORMSTAND GUARD (INSTANT BLOCK)
    -- ═══════════════════════════════════
    reg(hum:GetPropertyChangedSignal("PlatformStand"):Connect(function()
        if hum.PlatformStand then
            hum.PlatformStand = false
        end
    end))
    
    -- Additional state guards
    reg(hum:GetPropertyChangedSignal("Sit"):Connect(function()
        if hum.Sit and not hum.SeatPart then
            hum.Sit = false
        end
    end))

    -- ═══════════════════════════════════
    -- NETWORK OWNERSHIP PROTECTION
    -- ═══════════════════════════════════
    pcall(function()
        hrp:SetNetworkOwner(LP)
    end)
end

protect(LP.Character)
LP.CharacterAdded:Connect(function(c)
    task.wait(0.15)
    protect(c)
end)
