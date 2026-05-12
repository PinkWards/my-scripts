local Players        = game:GetService("Players")
local RunService     = game:GetService("RunService")
local PhysicsService = game:GetService("PhysicsService")
local LP             = Players.LocalPlayer

local V3ZERO    = Vector3.zero
local ANG_CAP   = 12
local HORIZ_CAP = 110
local UP_CAP    = 90
local DOWN_CAP  = 160
local SCAN_RAD  = 35
local EMERGENCY_VEL = 300

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
    PhysicsService:CollisionGroupSetCollidable("_af_me", "_af_me", true)
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
-- UTILITY
-- ═══════════════════════════════════════════════
local function safeSet(part, prop, val)
    pcall(function() part[prop] = val end)
end

local function killPart(part)
    if not part:IsA("BasePart") then return end
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
-- NEUTRALIZE OTHER PLAYERS
-- ═══════════════════════════════════════════════
local function hookPartProperties(part, connTable)
    if not part:IsA("BasePart") then return end

    local function enforce()
        safeSet(part, "CanCollide", false)
        safeSet(part, "CanTouch", false)
    end

    connTable[#connTable + 1] = part:GetPropertyChangedSignal("CanCollide"):Connect(enforce)
    connTable[#connTable + 1] = part:GetPropertyChangedSignal("CanTouch"):Connect(enforce)

    if cgWork then
        connTable[#connTable + 1] = part:GetPropertyChangedSignal("CollisionGroup"):Connect(function()
            if part.CollisionGroup ~= "_af_them" then
                safeSet(part, "CollisionGroup", "_af_them")
            end
        end)
    end
end

local function trackChar(ch, plr)
    if not ch then return end

    if trackedCharConns[plr] then
        for _, c in ipairs(trackedCharConns[plr]) do
            if c then pcall(c.Disconnect, c) end
        end
    end

    local charConns = {}
    trackedCharConns[plr] = charConns

    for _, p in ipairs(ch:GetDescendants()) do
        killPart(p)
        hookPartProperties(p, charConns)
    end

    charConns[#charConns + 1] = ch.DescendantAdded:Connect(function(p)
        task.defer(function()
            killPart(p)
            hookPartProperties(p, charConns)
        end)
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
            if c then pcall(c.Disconnect, c) end
        end
        trackedCharConns[plr] = nil
    end
end)

-- ═══════════════════════════════════════════════
-- CHARACTER PROTECTION
-- ═══════════════════════════════════════════════
local function clearConns()
    for i = #conns, 1, -1 do
        if conns[i] then pcall(conns[i].Disconnect, conns[i]) end
        conns[i] = nil
    end
end
local function reg(c) conns[#conns + 1] = c return c end

local function protect(char)
    if not char then return end
    clearConns()

    local hrp = char:WaitForChild("HumanoidRootPart", 5)
    local hum = char:WaitForChild("Humanoid", 5)
    if not hrp or not hum then return end

    local overlapParams = OverlapParams.new()
    overlapParams.FilterType = Enum.RaycastFilterType.Exclude
    overlapParams.FilterDescendantsInstances = {char}

    -- ═══════════════════════════════════
    -- OUR COLLISION GROUP + CANCOLLIDE FORTIFY
    -- ═══════════════════════════════════
    local function fortify(p)
        if not p:IsA("BasePart") then return end
        if cgWork then safeSet(p, "CollisionGroup", "_af_me") end
        safeSet(p, "CanCollide", false)
    end

    for _, p in ipairs(char:GetDescendants()) do fortify(p) end
    reg(char.DescendantAdded:Connect(function(p)
        task.defer(function() fortify(p) end)
    end))

    local function hookOwnPart(p)
        if not p:IsA("BasePart") then return end
        if cgWork then
            reg(p:GetPropertyChangedSignal("CollisionGroup"):Connect(function()
                if p.CollisionGroup ~= "_af_me" then
                    safeSet(p, "CollisionGroup", "_af_me")
                end
            end))
        end
        reg(p:GetPropertyChangedSignal("CanCollide"):Connect(function()
            if p.CanCollide then
                safeSet(p, "CanCollide", false)
            end
        end))
    end

    for _, p in ipairs(char:GetDescendants()) do hookOwnPart(p) end
    reg(char.DescendantAdded:Connect(function(p) task.defer(function() hookOwnPart(p) end) end))

    -- ═══════════════════════════════════
    -- VELOCITY CLAMPING (STEPPED — before physics)
    -- ═══════════════════════════════════
    local function clampAllCharVelocity()
        if not char.Parent or not hrp.Parent then return end

        -- Clamp HRP angular
        if hrp.AssemblyAngularVelocity.Magnitude > ANG_CAP then
            safeSet(hrp, "AssemblyAngularVelocity", V3ZERO)
        end

        -- Clamp HRP linear
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
            safeSet(hrp, "AssemblyLinearVelocity", Vector3.new(vx, vy, vz))
        end

        -- Clamp ALL our parts' angular velocity (prevents internal fling)
        for _, p in ipairs(char:GetDescendants()) do
            if p:IsA("BasePart") and p ~= hrp then
                if p.AssemblyAngularVelocity.Magnitude > ANG_CAP then
                    safeSet(p, "AssemblyAngularVelocity", V3ZERO)
                end
            end
        end
    end

    reg(RunService.Stepped:Connect(clampAllCharVelocity))

    -- ═══════════════════════════════════
    -- VELOCITY CLAMPING (HEARTBEAT — after physics, catches fling forces)
    -- ═══════════════════════════════════
    reg(RunService.Heartbeat:Connect(function()
        if not char.Parent or not hrp.Parent then return end

        local vel = hrp.AssemblyLinearVelocity
        local angVel = hrp.AssemblyAngularVelocity

        -- Emergency: if something broke through, zero everything
        if vel.Magnitude > EMERGENCY_VEL or angVel.Magnitude > ANG_CAP * 2 then
            safeSet(hrp, "AssemblyLinearVelocity", V3ZERO)
            safeSet(hrp, "AssemblyAngularVelocity", V3ZERO)
            -- Also zero all other parts
            for _, p in ipairs(char:GetDescendants()) do
                if p:IsA("BasePart") then
                    safeSet(p, "AssemblyLinearVelocity", V3ZERO)
                    safeSet(p, "AssemblyAngularVelocity", V3ZERO)
                end
            end
            return
        end

        -- Normal clamp after physics
        local vx, vy, vz = vel.X, vel.Y, vel.Z
        local hMag = math.sqrt(vx * vx + vz * vz)
        local dirty = false

        if hMag > HORIZ_CAP then
            local s = HORIZ_CAP / hMag
            vx, vz = vx * s, vz * s
            dirty = true
        end
        if vy > UP_CAP then vy = UP_CAP dirty = true
        elseif vy < -DOWN_CAP then vy = -DOWN_CAP dirty = true end

        if dirty then
            safeSet(hrp, "AssemblyLinearVelocity", Vector3.new(vx, vy, vz))
        end

        if angVel.Magnitude > ANG_CAP then
            safeSet(hrp, "AssemblyAngularVelocity", V3ZERO)
        end
    end))

    -- ═══════════════════════════════════
    -- NEARBY PART SCAN (more aggressive)
    -- ═══════════════════════════════════
    reg(RunService.Stepped:Connect(function()
        if not char.Parent or not hrp.Parent then return end

        local ok, nearby = pcall(workspace.GetPartBoundsInRadius, workspace, hrp.Position, SCAN_RAD, overlapParams)
        if not ok or not nearby then return end

        for i = 1, #nearby do
            local part = nearby[i]
            if not part.Anchored and part.Parent then
                if not part:IsDescendantOf(char) then
                    pcall(function()
                        local isPlayer = (cgWork and part.CollisionGroup == "_af_them")

                        if isPlayer then
                            -- Much lower threshold for spinning players
                            local angMag = part.AssemblyAngularVelocity.Magnitude
                            local linMag = part.AssemblyLinearVelocity.Magnitude
                            if angMag > 3 or linMag > 80 then
                                killPart(part)
                                killPartVelocity(part)
                                -- Also kill the entire assembly root
                                local root = part.AssemblyRootPart
                                if root and root ~= part then
                                    killPartVelocity(root)
                                end
                            end
                            -- Backup: force CanCollide off regardless
                            if part.CanCollide then
                                safeSet(part, "CanCollide", false)
                            end
                        else
                            if part.AssemblyAngularVelocity.Magnitude > 3 or part.AssemblyLinearVelocity.Magnitude > 15 then
                                killPart(part)
                                killPartVelocity(part)
                            end
                        end
                    end)
                end
            end
        end
    end))

    -- ═══════════════════════════════════
    -- FORCE / WELD GUARD
    -- ═══════════════════════════════════
    reg(char.DescendantAdded:Connect(function(obj)
        if DANGEROUS[obj.ClassName] then
            local function checkExternal()
                if not obj.Parent then return end
                for _, prop in ipairs({"Attachment0", "Attachment1", "Part0", "Part1"}) do
                    local ok2, val = pcall(function() return obj[prop] end)
                    if ok2 and val and typeof(val) == "Instance"
                    and not val:IsDescendantOf(char) then
                        obj:Destroy()
                        return
                    end
                end
            end

            task.defer(checkExternal)
            task.delay(0.1, checkExternal)
            return
        end

        if obj:IsA("JointInstance")
        or obj:IsA("WeldConstraint")
        or obj:IsA("Constraint") then
            local function checkJoint()
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
            end

            task.defer(checkJoint)
            task.delay(0.1, checkJoint)
        end
    end))

    -- ═══════════════════════════════════
    -- SEAT GUARD
    -- ═══════════════════════════════════
    reg(hum:GetPropertyChangedSignal("SeatPart"):Connect(function()
        local seat = hum.SeatPart
        if not seat then return end
        if seat.Anchored or seat:IsDescendantOf(char) then return end

        pcall(function()
            local isPlayer = (cgWork and seat.CollisionGroup == "_af_them")
            if isPlayer or seat.AssemblyAngularVelocity.Magnitude > 5 or seat.AssemblyLinearVelocity.Magnitude > 30 then
                hum.Sit = false
            end
        end)
    end))

    -- ═══════════════════════════════════
    -- TOUCH GUARD (more aggressive)
    -- ═══════════════════════════════════
    local function hookTouch(bp)
        if not bp:IsA("BasePart") then return end
        reg(bp.Touched:Connect(function(hit)
            if not hit or not hit.Parent or hit.Anchored or hit:IsDescendantOf(char) then return end

            pcall(function()
                local angMag = hit.AssemblyAngularVelocity.Magnitude
                local linMag = hit.AssemblyLinearVelocity.Magnitude

                if angMag > 3 or linMag > 15 then
                    killPart(hit)
                    killPartVelocity(hit)
                    -- Kill the whole assembly
                    local root = hit.AssemblyRootPart
                    if root and root ~= hit then
                        killPartVelocity(root)
                    end
                end

                -- Backup CanCollide enforcement
                if hit.CanCollide then
                    safeSet(hit, "CanCollide", false)
                end
            end)
        end))
    end

    for _, p in ipairs(char:GetDescendants()) do hookTouch(p) end
    reg(char.DescendantAdded:Connect(function(p) hookTouch(p) end))

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

    -- ═══════════════════════════════════
    -- SIT GUARD (prevent forced sit)
    -- ═══════════════════════════════════
    reg(hum:GetPropertyChangedSignal("Sit"):Connect(function()
        if hum.Sit and not hum.SeatPart then
            task.defer(function()
                if hum.Parent then
                    hum.Sit = false
                end
            end)
        end
    end))

    -- ═══════════════════════════════════
    -- STATE GUARD (prevent ragdoll/falling states that enable flinging)
    -- ═══════════════════════════════════
    reg(hum.StateChanged:Connect(function(_, newState)
        if newState == Enum.HumanoidStateType.FallingDown
        or newState == Enum.HumanoidStateType.Ragdoll then
            task.defer(function()
                if hum.Parent then
                    hum:ChangeState(Enum.HumanoidStateType.GettingUp)
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
