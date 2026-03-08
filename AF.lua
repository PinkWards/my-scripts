local Players        = game:GetService("Players")
local RunService     = game:GetService("RunService")
local PhysicsService = game:GetService("PhysicsService")
local LP             = Players.LocalPlayer

local V3ZERO    = Vector3.zero
local ANG_CAP   = 20
local HORIZ_CAP = 150
local UP_CAP    = 120
local SCAN_RAD  = 25

local trackedPlayers = {}
local conns          = {}

-- ═══════════════════════════════════════════════
-- LAYER 1: COLLISION GROUPS (engine level block)
-- ═══════════════════════════════════════════════
local cgWork = false
pcall(function()
    PhysicsService:RegisterCollisionGroup("_af_me")
    PhysicsService:RegisterCollisionGroup("_af_them")
    PhysicsService:CollisionGroupSetCollidable("_af_me", "_af_them", false)
    cgWork = true
end)

-- ═══════════════════════════════════════════════
-- LAYER 2: NEUTRALIZE OTHER PLAYERS' PARTS
-- CanCollide false + CanTouch false
-- Massless = true
-- Collision group assignment
-- NO density changes
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

local function trackChar(ch)
    if not ch then return end
    for _, p in ipairs(ch:GetDescendants()) do neutralizePart(p) end
    ch.DescendantAdded:Connect(function(p)
        neutralizePart(p)
        task.defer(function() neutralizePart(p) end)
    end)
end

local function trackPlayer(plr)
    if plr == LP or trackedPlayers[plr] then return end
    trackedPlayers[plr] = true
    if plr.Character then trackChar(plr.Character) end
    plr.CharacterAdded:Connect(function(c)
        task.wait(0.1)
        trackChar(c)
    end)
end

for _, plr in ipairs(Players:GetPlayers()) do trackPlayer(plr) end
Players.PlayerAdded:Connect(trackPlayer)
Players.PlayerRemoving:Connect(function(plr) trackedPlayers[plr] = nil end)

-- re-enforce EVERY frame on Stepped + Heartbeat
local function enforceOthers()
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

RunService.Stepped:Connect(enforceOthers)
RunService.Heartbeat:Connect(enforceOthers)

-- ═══════════════════════════════════════════════
-- DANGEROUS FORCES
-- ═══════════════════════════════════════════════
local DANGEROUS = {}
for _, cn in ipairs({
    "BodyVelocity","BodyAngularVelocity","BodyForce",
    "BodyPosition","BodyGyro","BodyThrust","RocketPropulsion",
    "Torque","VectorForce","LinearVelocity","AlignPosition",
    "AlignOrientation","AngularVelocity",
}) do DANGEROUS[cn] = true end

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
    -- LAYER 3: ASSIGN OUR COLLISION GROUP
    -- No density/mass changes — just collision group
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

    -- re-enforce our collision group every frame
    reg(RunService.Heartbeat:Connect(function()
        if not char.Parent then return end
        for _, p in ipairs(char:GetDescendants()) do
            if p:IsA("BasePart") then
                pcall(function()
                    if cgWork and p.CollisionGroup ~= "_af_me" then
                        p.CollisionGroup = "_af_me"
                    end
                end)
            end
        end
    end))

    -- ═══════════════════════════════════
    -- LAYER 4: VELOCITY CLAMPING
    -- Replaces the density approach entirely
    -- Aggressively clamps velocity every frame
    -- on all 3 frame events
    -- ═══════════════════════════════════

    -- Store last known good velocity for restoration
    local lastGoodVel = V3ZERO
    local lastGoodTime = 0

    local function clamp()
        if not char.Parent or not hrp.Parent then return end

        local ang = hrp.AssemblyAngularVelocity
        local vel = hrp.AssemblyLinearVelocity
        local angMag = ang.Magnitude
        local dirty = false

        -- always kill excessive spin
        if angMag > ANG_CAP then
            hrp.AssemblyAngularVelocity = V3ZERO
            dirty = true
        end

        -- clamp linear velocity if we're also spinning
        -- flings ALWAYS spin you, TP tools don't
        if angMag > ANG_CAP then
            local vx, vy, vz = vel.X, vel.Y, vel.Z
            local hMag = math.sqrt(vx * vx + vz * vz)

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

        -- Track last good velocity (when not being flung)
        if angMag <= ANG_CAP then
            lastGoodVel = hrp.AssemblyLinearVelocity
            lastGoodTime = tick()
        end
    end

    -- BindToRenderStep at FIRST priority
    local bindName = "_af_" .. tostring(math.random(999999))
    RunService:BindToRenderStep(bindName, Enum.RenderPriority.First.Value, clamp)
    reg({Disconnect = function()
        pcall(function() RunService:UnbindFromRenderStep(bindName) end)
    end})

    reg(RunService.Stepped:Connect(clamp))
    reg(RunService.Heartbeat:Connect(clamp))

    -- ═══════════════════════════════════
    -- LAYER 5: NEARBY PART SCAN
    -- freeze + neutralize any fast/spinning
    -- unanchored part near us
    -- NO density changes — just velocity zero + collision
    -- ═══════════════════════════════════
    local function scanNearby()
        if not char.Parent or not hrp.Parent then return end

        local ok, nearby = pcall(function()
            return workspace:GetPartBoundsInRadius(
                hrp.Position, SCAN_RAD, overlapParams
            )
        end)

        if ok and nearby then
            for _, part in ipairs(nearby) do
                if not part.Anchored and not part:IsDescendantOf(char) then
                    local isPlayer = false
                    for plr in pairs(trackedPlayers) do
                        if plr.Character
                        and part:IsDescendantOf(plr.Character) then
                            isPlayer = true
                            break
                        end
                    end

                    if isPlayer then
                        pcall(function()
                            part.CanCollide = false
                            part.CanTouch   = false
                            if cgWork then
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
                                if cgWork then
                                    part.CollisionGroup = "_af_them"
                                end
                            end)
                        end
                    end
                end
            end
        end
    end

    reg(RunService.Stepped:Connect(scanNearby))
    reg(RunService.Heartbeat:Connect(scanNearby))

    -- ═══════════════════════════════════
    -- FORCE / WELD GUARD
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
            if seat.AssemblyAngularVelocity.Magnitude > 10
            or seat.AssemblyLinearVelocity.Magnitude > 50 then
                hum.Sit = false
            end
        end
    end))

    -- ═══════════════════════════════════
    -- TOUCH GUARD
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
