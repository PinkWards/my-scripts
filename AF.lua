local Players        = game:GetService("Players")
local RunService     = game:GetService("RunService")
local PhysicsService = game:GetService("PhysicsService")
local LP             = Players.LocalPlayer

local V3ZERO    = Vector3.zero
local ANG_CAP   = 15
local HORIZ_CAP = 130
local UP_CAP    = 300   -- raised from 100 so balloon doesnt get cut
local DOWN_CAP  = 180
local SCAN_RAD  = 30

local SCAN_INTERVAL  = 0.1
local REENFORCE_RATE = 1.0
local MAX_VELOCITY_DELTA = 80
local MAX_ABSOLUTE_SPEED = 130

-- ═══════════════════════════════════════════════
-- TP WHITELIST SYSTEM
-- Call allowNextTP() before any teleport
-- It opens a 2 second window where position
-- anchor is disabled so the TP goes through
-- ═══════════════════════════════════════════════
local tpAllowed     = false
local tpAllowedUntil = 0

local function allowNextTP(duration)
    duration = duration or 2  -- seconds to keep anchor off
    tpAllowed = true
    tpAllowedUntil = os.clock() + duration
end

-- expose it globally so you can call it from console
-- or from other scripts before teleporting
getgenv().allowNextTP = allowNextTP

-- ═══════════════════════════════════════════════
-- also expose a global to temporarily raise UP_CAP
-- call boostUp() when balloon activates
-- ═══════════════════════════════════════════════
local upCapOverride = nil
local upCapUntil    = 0

local function boostUp(newCap, duration)
    newCap   = newCap   or 600
    duration = duration or 5
    upCapOverride = newCap
    upCapUntil    = os.clock() + duration
end

getgenv().boostUp = boostUp

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
-- UTILITY
-- ═══════════════════════════════════════════════
local function safeSet(part, prop, val)
    pcall(function() part[prop] = val end)
end

local function killPart(part)
    if not part:IsA("BasePart") then return end
    safeSet(part, "CanCollide", false)
    safeSet(part, "CanTouch",   false)
    safeSet(part, "Massless",   true)
    if cgWork then safeSet(part, "CollisionGroup", "_af_them") end
end

local function killPartVelocity(part)
    safeSet(part, "AssemblyLinearVelocity",  V3ZERO)
    safeSet(part, "AssemblyAngularVelocity", V3ZERO)
end

-- ═══════════════════════════════════════════════
-- NEUTRALIZE OTHER PLAYERS
-- ═══════════════════════════════════════════════
local function hookPartProperties(part, connTable)
    if not part:IsA("BasePart") then return end

    local function enforce()
        safeSet(part, "CanCollide", false)
        safeSet(part, "CanTouch",   false)
    end

    connTable[#connTable + 1] = part:GetPropertyChangedSignal("CanCollide"):Connect(enforce)
    connTable[#connTable + 1] = part:GetPropertyChangedSignal("CanTouch"):Connect(enforce)

    if cgWork then
        connTable[#connTable + 1] = part:GetPropertyChangedSignal("CollisionGroup"):Connect(function()
            pcall(function()
                if part.CollisionGroup ~= "_af_them" then
                    part.CollisionGroup = "_af_them"
                end
            end)
        end)
    end
end

local function trackChar(ch, plr)
    if not ch then return end

    if trackedCharConns[plr] then
        for _, c in ipairs(trackedCharConns[plr]) do
            pcall(function() c:Disconnect() end)
        end
    end

    local charConns = {}
    trackedCharConns[plr] = charConns

    for _, p in ipairs(ch:GetDescendants()) do
        killPart(p)
        hookPartProperties(p, charConns)
    end

    charConns[#charConns + 1] = ch.DescendantAdded:Connect(function(p)
        killPart(p)
        task.defer(function()
            if p.Parent then killPart(p) end
        end)
        hookPartProperties(p, charConns)
    end)

    local hrpOther = ch:FindFirstChild("HumanoidRootPart")
    if hrpOther and hrpOther:IsA("BasePart") then
        local lastPos        = hrpOther.Position
        local TWEEN_LIMIT    = 60

        charConns[#charConns + 1] = RunService.Heartbeat:Connect(function(dt)
            if not hrpOther.Parent then return end
            local cur   = hrpOther.Position
            local speed = (cur - lastPos).Magnitude / math.max(dt, 0.001)
            if speed > TWEEN_LIMIT then
                killPartVelocity(hrpOther)
            end
            lastPos = cur
        end)
    end

    charConns[#charConns + 1] = ch.ChildAdded:Connect(function(child)
        if child.Name == "HumanoidRootPart" and child:IsA("BasePart") then
            local hrp2    = child
            local lastPos2 = hrp2.Position
            local TWEEN_LIMIT = 60
            charConns[#charConns + 1] = RunService.Heartbeat:Connect(function(dt)
                if not hrp2.Parent then return end
                local cur   = hrp2.Position
                local speed = (cur - lastPos2).Magnitude / math.max(dt, 0.001)
                if speed > TWEEN_LIMIT then killPartVelocity(hrp2) end
                lastPos2 = cur
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
            pcall(function() c:Disconnect() end)
        end
        trackedCharConns[plr] = nil
    end
end)

task.spawn(function()
    while true do
        task.wait(REENFORCE_RATE)
        for plr in pairs(trackedPlayers) do
            local ch = plr.Character
            if ch then
                for _, p in ipairs(ch:GetDescendants()) do
                    killPart(p)
                end
            end
        end
    end
end)

-- ═══════════════════════════════════════════════
-- CHARACTER PROTECTION
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
    local hum = char:WaitForChild("Humanoid",         5)
    if not hrp or not hum then return end

    local overlapParams = OverlapParams.new()
    overlapParams.FilterType = Enum.RaycastFilterType.Exclude
    overlapParams.FilterDescendantsInstances = {char}

    -- ─── collision group ────────────────────────
    local function fortify(p)
        if not p:IsA("BasePart") then return end
        if cgWork then safeSet(p, "CollisionGroup", "_af_me") end
    end

    local function hookOwnPart(p)
        if not p:IsA("BasePart") or not cgWork then return end
        reg(p:GetPropertyChangedSignal("CollisionGroup"):Connect(function()
            pcall(function()
                if p.CollisionGroup ~= "_af_me" then
                    p.CollisionGroup = "_af_me"
                end
            end)
        end))
    end

    for _, p in ipairs(char:GetDescendants()) do
        fortify(p)
        hookOwnPart(p)
    end

    reg(char.DescendantAdded:Connect(function(p)
        fortify(p)
        hookOwnPart(p)
        task.defer(function()
            if p.Parent then fortify(p) end
        end)
    end))

    -- ─── velocity clamp + spike detection ───────
    local lastVelocity = V3ZERO

    local function clampVelocity()
        if not char.Parent or not hrp.Parent then return end

        if hrp.AssemblyAngularVelocity.Magnitude > ANG_CAP then
            hrp.AssemblyAngularVelocity = V3ZERO
        end

        local vel   = hrp.AssemblyLinearVelocity
        local delta = (vel - lastVelocity).Magnitude

        if delta > MAX_VELOCITY_DELTA then
            hrp.AssemblyLinearVelocity = V3ZERO
            lastVelocity = V3ZERO
            return
        end

        local vx, vy, vz = vel.X, vel.Y, vel.Z
        local hMag = math.sqrt(vx*vx + vz*vz)
        local dirty = false

        if hMag > HORIZ_CAP then
            local s = HORIZ_CAP / hMag
            vx, vz = vx*s, vz*s
            dirty = true
        end

        -- ── use override cap if balloon boosted ──
        local effectiveUpCap = UP_CAP
        if upCapOverride and os.clock() < upCapUntil then
            effectiveUpCap = upCapOverride
        else
            upCapOverride = nil
        end

        if vy > effectiveUpCap then
            vy    = effectiveUpCap
            dirty = true
        elseif vy < -DOWN_CAP then
            vy    = -DOWN_CAP
            dirty = true
        end

        if dirty then
            hrp.AssemblyLinearVelocity = Vector3.new(vx, vy, vz)
            lastVelocity = Vector3.new(vx, vy, vz)
        else
            lastVelocity = vel
        end
    end

    reg(RunService.Heartbeat:Connect(clampVelocity))

    -- ─── nearby scan (throttled) ─────────────────
    local lastScan = 0
    reg(RunService.Heartbeat:Connect(function(dt)
        if not char.Parent or not hrp.Parent then return end
        lastScan += dt
        if lastScan < SCAN_INTERVAL then return end
        lastScan = 0

        local ok, nearby = pcall(function()
            return workspace:GetPartBoundsInRadius(hrp.Position, SCAN_RAD, overlapParams)
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
                    killPart(part)
                    pcall(function()
                        if part.AssemblyAngularVelocity.Magnitude > 10
                        or part.AssemblyLinearVelocity.Magnitude  > 200 then
                            killPartVelocity(part)
                        end
                    end)
                else
                    pcall(function()
                        local av = part.AssemblyAngularVelocity.Magnitude
                        local lv = part.AssemblyLinearVelocity.Magnitude
                        if av > 5 or lv > 20 then
                            killPart(part)
                            killPartVelocity(part)
                        end
                    end)
                end
            end
        end
    end))

    -- ─── force / weld guard ──────────────────────
    reg(char.DescendantAdded:Connect(function(obj)
        if DANGEROUS[obj.ClassName] then
            local function checkExternal()
                pcall(function()
                    if not obj.Parent then return end
                    for _, prop in ipairs({"Attachment0","Attachment1","Part0","Part1"}) do
                        local ok2, val = pcall(function() return obj[prop] end)
                        if ok2 and val and typeof(val) == "Instance"
                        and not val:IsDescendantOf(char) then
                            obj:Destroy()
                            return
                        end
                    end
                end)
            end
            checkExternal()
            task.defer(checkExternal)
            return
        end

        if obj:IsA("JointInstance") or obj:IsA("WeldConstraint") or obj:IsA("Constraint") then
            local function checkJoint()
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
            end
            checkJoint()
            task.defer(checkJoint)
        end
    end))

    -- ─── seat guard ──────────────────────────────
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
            or seat.AssemblyLinearVelocity.Magnitude  > 40 then
                hum.Sit = false
            end
        end
    end))

    -- ─── touch guard ─────────────────────────────
    local touchCooldowns = {}

    local function hookTouch(bp)
        if not bp:IsA("BasePart") then return end
        reg(bp.Touched:Connect(function(hit)
            if not hit or not hit.Parent then return end
            if hit:IsDescendantOf(char) or hit.Anchored then return end

            local now = os.clock()
            if touchCooldowns[hit] and now - touchCooldowns[hit] < 0.2 then return end
            touchCooldowns[hit] = now

            pcall(function()
                local av = hit.AssemblyAngularVelocity.Magnitude
                local lv = hit.AssemblyLinearVelocity.Magnitude
                if av > 5 or lv > 20 then
                    killPart(hit)
                    killPartVelocity(hit)
                end
            end)

            task.defer(clampVelocity)
        end))
    end

    for _, p in ipairs(char:GetDescendants()) do hookTouch(p) end
    reg(char.DescendantAdded:Connect(hookTouch))

    task.spawn(function()
        while char.Parent do
            task.wait(5)
            touchCooldowns = {}
        end
    end)

    -- ─── platformstand guard ─────────────────────
    reg(hum:GetPropertyChangedSignal("PlatformStand"):Connect(function()
        if hum.PlatformStand then
            task.defer(function()
                if hum.Parent then hum.PlatformStand = false end
            end)
        end
    end))

    -- ─── position anchor (TP aware) ──────────────
    local lastMyPos = hrp.Position

    -- studs/sec — generous enough for balloon
    -- but still catches fling attacks
    local MY_POS_SPEED_LIMIT = 250

    reg(RunService.Heartbeat:Connect(function(dt)
        if not char.Parent or not hrp.Parent then return end

        -- ── if TP window is open, skip anchor entirely
        -- and update lastMyPos so we dont snap back after
        if tpAllowed then
            if os.clock() > tpAllowedUntil then
                tpAllowed = false
            end
            lastMyPos = hrp.Position  -- accept new position
            return
        end

        local curPos = hrp.Position
        local speed  = (curPos - lastMyPos).Magnitude / math.max(dt, 0.001)

        if speed > MY_POS_SPEED_LIMIT then
            hrp.CFrame = CFrame.new(lastMyPos) * (hrp.CFrame - hrp.CFrame.Position)
            hrp.AssemblyLinearVelocity  = V3ZERO
            hrp.AssemblyAngularVelocity = V3ZERO
        else
            lastMyPos = curPos
        end
    end))
end

protect(LP.Character)
LP.CharacterAdded:Connect(function(c)
    task.wait(0.15)
    protect(c)
end)

print("Anti-fling loaded")
print("Before teleporting run: allowNextTP()")
print("If balloon gets cut run: boostUp()")
