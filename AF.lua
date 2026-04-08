local Players        = game:GetService("Players")
local RunService     = game:GetService("RunService")
local PhysicsService = game:GetService("PhysicsService")
local LP             = Players.LocalPlayer

local V3ZERO    = Vector3.zero
local ANG_CAP   = 15
local HORIZ_CAP = 130
local UP_CAP    = 100
local DOWN_CAP  = 180
local SCAN_RAD  = 30

local trackedPlayers   = {}
local trackedCharConns = {}
local conns            = {}

-- ═══════════════════════════════════════════════
-- COLLISION GROUPS
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
local DANGEROUS = {}
for _, cn in ipairs({
    "BodyVelocity", "BodyAngularVelocity", "BodyForce",
    "BodyPosition", "BodyGyro", "BodyThrust", "RocketPropulsion",
    "Torque", "VectorForce", "LinearVelocity", "AlignPosition",
    "AlignOrientation", "AngularVelocity",
}) do DANGEROUS[cn] = true end

-- ═══════════════════════════════════════════════
-- UTILITY (OPTIMIZED)
-- ═══════════════════════════════════════════════
local function safeSet(part, prop, val)
    if part[prop] ~= val then -- Only set if different
        part[prop] = val
    end
end

local processedParts = {} -- Cache to avoid re-processing
local function killPart(part)
    if not part:IsA("BasePart") or processedParts[part] then return end
    processedParts[part] = true
    
    safeSet(part, "CanCollide", false)
    safeSet(part, "CanTouch", false)
    safeSet(part, "Massless", true)
    if cgWork then safeSet(part, "CollisionGroup", "_af_them") end
end

local function killPartVelocity(part)
    safeSet(part, "AssemblyLinearVelocity", V3ZERO)
    safeSet(part, "AssemblyAngularVelocity", V3ZERO)
end

-- ═══════════════════════════════════════════════
-- NEUTRALIZE OTHER PLAYERS (OPTIMIZED)
-- ═══════════════════════════════════════════════
local function hookPartProperties(part, connTable)
    if not part:IsA("BasePart") then return end

    local function enforce()
        safeSet(part, "CanCollide", false)
        safeSet(part, "CanTouch", false)
    end

    -- Only hook if cgWork is enabled
    if cgWork then
        connTable[#connTable + 1] = part:GetPropertyChangedSignal("CollisionGroup"):Connect(function()
            if part.CollisionGroup ~= "_af_them" then
                part.CollisionGroup = "_af_them"
            end
        end)
    end
end

local function trackChar(ch, plr)
    if not ch then return end

    if trackedCharConns[plr] then
        for _, c in ipairs(trackedCharConns[plr]) do
            c:Disconnect()
        end
    end

    local charConns = {}
    trackedCharConns[plr] = charConns

    -- Batch process descendants
    local descendants = ch:GetDescendants()
    for i = 1, #descendants do
        killPart(descendants[i])
        hookPartProperties(descendants[i], charConns)
    end

    charConns[#charConns + 1] = ch.DescendantAdded:Connect(function(p)
        killPart(p)
        hookPartProperties(p, charConns)
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

-- Periodic re-enforce (OPTIMIZED - increased interval)
task.spawn(function()
    while true do
        task.wait(0.5) -- Increased from 0.3
        for plr in pairs(trackedPlayers) do
            local ch = plr.Character
            if ch then
                local descendants = ch:GetDescendants()
                for i = 1, #descendants do
                    killPart(descendants[i])
                end
            end
        end
    end
end)

-- ═══════════════════════════════════════════════
-- CHARACTER PROTECTION (OPTIMIZED)
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
    processedParts = {} -- Reset cache

    local hrp = char:WaitForChild("HumanoidRootPart", 5)
    local hum = char:WaitForChild("Humanoid", 5)
    if not hrp or not hum then return end

    local overlapParams = OverlapParams.new()
    overlapParams.FilterType = Enum.RaycastFilterType.Exclude
    overlapParams.FilterDescendantsInstances = {char}

    -- ═══════════════════════════════════
    -- OUR COLLISION GROUP
    -- ═══════════════════════════════════
    local function fortify(p)
        if not p:IsA("BasePart") then return end
        if cgWork then safeSet(p, "CollisionGroup", "_af_me") end
    end

    local descendants = char:GetDescendants()
    for i = 1, #descendants do fortify(descendants[i]) end
    
    reg(char.DescendantAdded:Connect(function(p)
        fortify(p)
    end))

    local function hookOwnPart(p)
        if not p:IsA("BasePart") or not cgWork then return end
        reg(p:GetPropertyChangedSignal("CollisionGroup"):Connect(function()
            if p.CollisionGroup ~= "_af_me" then
                p.CollisionGroup = "_af_me"
            end
        end))
    end

    for i = 1, #descendants do hookOwnPart(descendants[i]) end
    reg(char.DescendantAdded:Connect(hookOwnPart))

    -- ═══════════════════════════════════
    -- VELOCITY CLAMPING (OPTIMIZED)
    -- Reduced to ONE event instead of three
    -- ═══════════════════════════════════
    local function clampVelocity()
        if not char.Parent or not hrp.Parent then return end

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

    -- Use ONLY Heartbeat (most efficient for physics)
    reg(RunService.Heartbeat:Connect(clampVelocity))

    -- ═══════════════════════════════════
    -- NEARBY PART SCAN (OPTIMIZED)
    -- Throttled to reduce frequency
    -- ═══════════════════════════════════
    local lastScan = 0
    local SCAN_INTERVAL = 0.1 -- Scan every 0.1 seconds instead of every frame
    
    reg(RunService.Heartbeat:Connect(function()
        if not char.Parent or not hrp.Parent then return end
        
        local now = tick()
        if now - lastScan < SCAN_INTERVAL then return end
        lastScan = now

        local ok, nearby = pcall(function()
            return workspace:GetPartBoundsInRadius(
                hrp.Position, SCAN_RAD, overlapParams
            )
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
                    killPart(part)
                    local av = part.AssemblyAngularVelocity.Magnitude
                    local lv = part.AssemblyLinearVelocity.Magnitude
                    if av > 10 or lv > 200 then
                        killPartVelocity(part)
                    end
                else
                    local av = part.AssemblyAngularVelocity.Magnitude
                    local lv = part.AssemblyLinearVelocity.Magnitude
                    if av > 5 or lv > 20 then
                        killPart(part)
                        killPartVelocity(part)
                    end
                end
            end
        end
    end))

    -- ═══════════════════════════════════
    -- FORCE / WELD GUARD (OPTIMIZED)
    -- Removed redundant task.defer and task.delay
    -- ═══════════════════════════════════
    reg(char.DescendantAdded:Connect(function(obj)
        if DANGEROUS[obj.ClassName] then
            task.defer(function()
                if not obj.Parent then return end
                for _, prop in ipairs({"Attachment0", "Attachment1", "Part0", "Part1"}) do
                    local ok2, val = pcall(function() return obj[prop] end)
                    if ok2 and val and typeof(val) == "Instance"
                    and not val:IsDescendantOf(char) then
                        obj:Destroy()
                        return
                    end
                end
            end)
            return
        end

        if obj:IsA("JointInstance")
        or obj:IsA("WeldConstraint")
        or obj:IsA("Constraint") then
            task.defer(function()
                if not obj.Parent then return end
                local p0, p1
                if obj:IsA("Constraint") then
                    p0 = obj.Attachment0 and obj.Attachment0.Parent
                    p1 = obj.Attachment1 and obj.Attachment1.Parent
                else
                    p0, p1 = obj.Part0, obj.Part1
                end
                if p0 and p1
                and (p0:IsDescendantOf(char) ~= p1:IsDescendantOf(char)) then
                    obj:Destroy()
                end
            end)
        end
    end))

    -- ═══════════════════════════════════
    -- SEAT GUARD
    -- ═══════════════════════════════════
    reg(hum:GetPropertyChangedSignal("SeatPart"):Connect(function()
        local seat = hum.SeatPart
        if not seat then return end
        for plr in pairs(trackedPlayers) do
            if plr.Character and seat:IsDescendantOf(plr.Character) then
                hum.Sit = false
                return
            end
        end
        if not seat.Anchored and not seat:IsDescendantOf(char) then
            if seat.AssemblyAngularVelocity.Magnitude > 8
            or seat.AssemblyLinearVelocity.Magnitude > 40 then
                hum.Sit = false
            end
        end
    end))

    -- ═══════════════════════════════════
    -- TOUCH GUARD (OPTIMIZED)
    -- Added cooldown to prevent spam
    -- ═══════════════════════════════════
    local touchCooldowns = {}
    local TOUCH_COOLDOWN = 0.1
    
    local function hookTouch(bp)
        if not bp:IsA("BasePart") then return end
        reg(bp.Touched:Connect(function(hit)
            if not hit or not hit.Parent then return end
            if hit:IsDescendantOf(char) or hit.Anchored then return end
            
            if touchCooldowns[hit] and tick() - touchCooldowns[hit] < TOUCH_COOLDOWN then
                return
            end
            touchCooldowns[hit] = tick()

            local av = hit.AssemblyAngularVelocity.Magnitude
            local lv = hit.AssemblyLinearVelocity.Magnitude
            if av > 5 or lv > 20 then
                killPart(hit)
                killPartVelocity(hit)
                task.defer(clampVelocity)
            end
        end))
    end

    for i = 1, #descendants do hookTouch(descendants[i]) end
    reg(char.DescendantAdded:Connect(hookTouch))

    -- ═══════════════════════════════════
    -- PLATFORMSTAND GUARD
    -- ═══════════════════════════════════
    reg(hum:GetPropertyChangedSignal("PlatformStand"):Connect(function()
        if hum.PlatformStand then
            task.defer(function()
                if hum.Parent then
                    hum.PlatformStand = false
                end
            end)
        end
    end))
end

protect(LP.Character)
LP.CharacterAdded:Connect(function(c)
    task.wait(0.15)
    protect(c)
end)
