local Players        = game:GetService("Players")
local RunService     = game:GetService("RunService")
local PhysicsService = game:GetService("PhysicsService")
local LP             = Players.LocalPlayer

local V3ZERO    = Vector3.zero
local ANG_CAP   = 20
local HORIZ_CAP = 150
local UP_CAP    = 120
local SCAN_RAD  = 25

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
    cgWork = true
end)

-- ═══════════════════════════════════════════════
-- DANGEROUS FORCE CLASS NAMES
-- ═══════════════════════════════════════════════
local DANGEROUS = {}
for _, cn in ipairs({
    "BodyVelocity","BodyAngularVelocity","BodyForce",
    "BodyPosition","BodyGyro","BodyThrust","RocketPropulsion",
    "Torque","VectorForce","LinearVelocity","AlignPosition",
    "AlignOrientation","AngularVelocity",
}) do DANGEROUS[cn] = true end

-- ═══════════════════════════════════════════════
-- NEUTRALIZE OTHER PLAYERS' PARTS (event-driven)
-- Set once on spawn/add, re-enforce only on property revert
-- ═══════════════════════════════════════════════
local function neutralizePart(part)
    if not part:IsA("BasePart") then return end
    pcall(function()
        part.CanCollide = false
        part.CanTouch   = false
        part.Massless   = true
        if cgWork then part.CollisionGroup = "_af_them" end
    end)
end

local function trackChar(ch, plr)
    if not ch then return end

    -- Kill old connections for this player
    if trackedCharConns[plr] then
        for _, c in ipairs(trackedCharConns[plr]) do
            pcall(function() c:Disconnect() end)
        end
    end
    local charConns = {}
    trackedCharConns[plr] = charConns

    -- Neutralize all existing parts
    for _, p in ipairs(ch:GetDescendants()) do neutralizePart(p) end

    -- Neutralize new parts immediately
    charConns[#charConns + 1] = ch.DescendantAdded:Connect(function(p)
        neutralizePart(p)
        task.defer(function() neutralizePart(p) end)
    end)

    -- Instead of per-frame iteration, listen for CanCollide changes
    -- on each BasePart to re-neutralize (handles server/other scripts reverting)
    for _, p in ipairs(ch:GetDescendants()) do
        if p:IsA("BasePart") then
            charConns[#charConns + 1] = p:GetPropertyChangedSignal("CanCollide"):Connect(function()
                pcall(function()
                    if p.CanCollide then p.CanCollide = false end
                end)
            end)
            charConns[#charConns + 1] = p:GetPropertyChangedSignal("CanTouch"):Connect(function()
                pcall(function()
                    if p.CanTouch then p.CanTouch = false end
                end)
            end)
        end
    end

    -- Also hook new descendants for property listeners
    charConns[#charConns + 1] = ch.DescendantAdded:Connect(function(p)
        if p:IsA("BasePart") then
            charConns[#charConns + 1] = p:GetPropertyChangedSignal("CanCollide"):Connect(function()
                pcall(function()
                    if p.CanCollide then p.CanCollide = false end
                end)
            end)
            charConns[#charConns + 1] = p:GetPropertyChangedSignal("CanTouch"):Connect(function()
                pcall(function()
                    if p.CanTouch then p.CanTouch = false end
                end)
            end)
        end
    end)
end

local function trackPlayer(plr)
    if plr == LP or trackedPlayers[plr] then return end
    trackedPlayers[plr] = true
    if plr.Character then trackChar(plr.Character, plr) end
    plr.CharacterAdded:Connect(function(c)
        task.wait(0.1)
        trackChar(c, plr)
    end)
end

for _, plr in ipairs(Players:GetPlayers()) do trackPlayer(plr) end
Players.PlayerAdded:Connect(trackPlayer)
Players.PlayerRemoving:Connect(function(plr)
    trackedPlayers[plr] = nil
    if trackedCharConns[plr] then
        for _, c in ipairs(trackedCharConns[plr]) do
            pcall(function() c:Disconnect() end)
        end
        trackedCharConns[plr] = nil
    end
end)

-- ═══════════════════════════════════════════════
-- THROTTLED RE-ENFORCE FOR OTHER PLAYERS
-- Runs every 0.5s instead of every frame
-- Catches anything the property signals missed
-- ═══════════════════════════════════════════════
task.spawn(function()
    while true do
        task.wait(0.5)
        for plr in pairs(trackedPlayers) do
            local ch = plr.Character
            if ch then
                for _, p in ipairs(ch:GetDescendants()) do
                    if p:IsA("BasePart") then
                        pcall(function()
                            if p.CanCollide then p.CanCollide = false end
                            if p.CanTouch then p.CanTouch = false end
                            if not p.Massless then p.Massless = true end
                            if cgWork and p.CollisionGroup ~= "_af_them" then
                                p.CollisionGroup = "_af_them"
                            end
                        end)
                    end
                end
            end
        end
    end
end)

-- ═══════════════════════════════════════════════
-- PER-CHARACTER PROTECTION
-- ═══════════════════════════════════════════════
local function clearConns()
    for i = #conns, 1, -1 do
        pcall(function() conns[i]:Disconnect() end)
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
    -- ASSIGN OUR COLLISION GROUP (event-driven)
    -- ═══════════════════════════════════
    local function fortify(p)
        if not p:IsA("BasePart") then return end
        pcall(function()
            if cgWork then p.CollisionGroup = "_af_me" end
        end)
    end

    for _, p in ipairs(char:GetDescendants()) do fortify(p) end
    reg(char.DescendantAdded:Connect(function(p)
        fortify(p)
        task.defer(function() fortify(p) end)
    end))

    -- Re-enforce our collision group on property change instead of every frame
    local function hookOwnPart(p)
        if not p:IsA("BasePart") then return end
        if cgWork then
            reg(p:GetPropertyChangedSignal("CollisionGroup"):Connect(function()
                pcall(function()
                    if p.CollisionGroup ~= "_af_me" then
                        p.CollisionGroup = "_af_me"
                    end
                end)
            end))
        end
    end

    for _, p in ipairs(char:GetDescendants()) do hookOwnPart(p) end
    reg(char.DescendantAdded:Connect(function(p) hookOwnPart(p) end))

    -- ═══════════════════════════════════
    -- VELOCITY CLAMPING
    -- Only on Stepped (once per physics step is sufficient)
    -- ═══════════════════════════════════
    local function clamp()
        if not char.Parent or not hrp.Parent then return end

        local ang = hrp.AssemblyAngularVelocity
        local vel = hrp.AssemblyLinearVelocity
        local angMag = ang.Magnitude

        -- Kill excessive spin
        if angMag > ANG_CAP then
            hrp.AssemblyAngularVelocity = V3ZERO

            -- Clamp linear velocity only when spin detected (fling signature)
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
            end

            if dirty then
                hrp.AssemblyLinearVelocity = Vector3.new(vx, vy, vz)
            end
        end
    end

    -- Single Stepped connection for clamping (pre-physics)
    reg(RunService.Stepped:Connect(clamp))

    -- ═══════════════════════════════════
    -- NEARBY PART SCAN (throttled)
    -- Runs every 3 frames instead of every frame
    -- ═══════════════════════════════════
    local scanCounter = 0
    reg(RunService.Heartbeat:Connect(function()
        scanCounter = scanCounter + 1
        if scanCounter < 3 then return end
        scanCounter = 0

        if not char.Parent or not hrp.Parent then return end

        local ok, nearby = pcall(function()
            return workspace:GetPartBoundsInRadius(
                hrp.Position, SCAN_RAD, overlapParams
            )
        end)

        if not ok or not nearby then return end

        for _, part in ipairs(nearby) do
            if not part.Anchored and not part:IsDescendantOf(char) then
                local isPlayer = false
                for plr in pairs(trackedPlayers) do
                    if plr.Character and part:IsDescendantOf(plr.Character) then
                        isPlayer = true
                        break
                    end
                end

                if isPlayer then
                    pcall(function()
                        if part.CanCollide then part.CanCollide = false end
                        if part.CanTouch then part.CanTouch = false end
                        if cgWork and part.CollisionGroup ~= "_af_them" then
                            part.CollisionGroup = "_af_them"
                        end
                    end)
                else
                    local av = part.AssemblyAngularVelocity.Magnitude
                    local lv = part.AssemblyLinearVelocity.Magnitude
                    if av > 8 or lv > 30 then
                        pcall(function()
                            part.CanCollide = false
                            part.CanTouch   = false
                            part.Massless   = true
                            part.AssemblyLinearVelocity  = V3ZERO
                            part.AssemblyAngularVelocity = V3ZERO
                            if cgWork then part.CollisionGroup = "_af_them" end
                        end)
                    end
                end
            end
        end
    end))

    -- ═══════════════════════════════════
    -- FORCE / WELD GUARD (unchanged — event-driven, no perf issue)
    -- ═══════════════════════════════════
    reg(char.DescendantAdded:Connect(function(obj)
        if DANGEROUS[obj.ClassName] then
            task.defer(function()
                pcall(function()
                    if not obj.Parent then return end
                    for _, prop in ipairs({
                        "Attachment0","Attachment1","Part0","Part1"
                    }) do
                        local ok2, val = pcall(function() return obj[prop] end)
                        if ok2 and val and typeof(val) == "Instance"
                        and not val:IsDescendantOf(char) then
                            obj:Destroy()
                            return
                        end
                    end
                end)
            end)
            return
        end

        if obj:IsA("JointInstance")
        or obj:IsA("WeldConstraint")
        or obj:IsA("Constraint") then
            task.defer(function()
                pcall(function()
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
            end)
        end
    end))

    -- ═══════════════════════════════════
    -- SEAT GUARD (unchanged — event-driven)
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
            if seat.AssemblyAngularVelocity.Magnitude > 10
            or seat.AssemblyLinearVelocity.Magnitude > 50 then
                hum.Sit = false
            end
        end
    end))

    -- ═══════════════════════════════════
    -- TOUCH GUARD (unchanged — event-driven)
    -- ═══════════════════════════════════
    local touchCD = {}
    local function hookTouch(bp)
        if not bp:IsA("BasePart") then return end
        reg(bp.Touched:Connect(function(hit)
            if touchCD[bp] then return end
            if not hit or not hit.Parent then return end
            if hit:IsDescendantOf(char) or hit.Anchored then return end

            local av = hit.AssemblyAngularVelocity.Magnitude
            local lv = hit.AssemblyLinearVelocity.Magnitude
            if av > 8 or lv > 25 then
                touchCD[bp] = true
                task.delay(0.05, function() touchCD[bp] = nil end)
                pcall(function()
                    hit.CanCollide = false
                    hit.CanTouch   = false
                    hit.Massless   = true
                    hit.AssemblyLinearVelocity  = V3ZERO
                    hit.AssemblyAngularVelocity = V3ZERO
                    if cgWork then hit.CollisionGroup = "_af_them" end
                end)
            end
        end))
    end

    for _, p in ipairs(char:GetDescendants()) do hookTouch(p) end
    reg(char.DescendantAdded:Connect(hookTouch))
end

protect(LP.Character)
LP.CharacterAdded:Connect(function(c)
    task.wait(0.2)
    protect(c)
end)
