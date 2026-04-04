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

-- ★ FIX 1: O(1) lookup cache instead of nested player loops
local partToPlayer = {}

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
        -- ★ FIX 1: register in cache
        if p:IsA("BasePart") then partToPlayer[p] = plr end
        hookPartProperties(p, charConns)
    end

    charConns[#charConns + 1] = ch.DescendantAdded:Connect(function(p)
        killPart(p)
        if p:IsA("BasePart") then partToPlayer[p] = plr end
        task.defer(function() killPart(p) end)
        task.delay(0.1, function() killPart(p) end)
        hookPartProperties(p, charConns)
    end)

    -- ★ FIX 1: clean cache when parts leave
    charConns[#charConns + 1] = ch.DescendantRemoving:Connect(function(p)
        if p:IsA("BasePart") then partToPlayer[p] = nil end
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
    -- ★ FIX 1: clean cache
    if plr.Character then
        for _, p in ipairs(plr.Character:GetDescendants()) do
            if p:IsA("BasePart") then partToPlayer[p] = nil end
        end
    end
    if trackedCharConns[plr] then
        for _, c in ipairs(trackedCharConns[plr]) do
            pcall(function() c:Disconnect() end)
        end
        trackedCharConns[plr] = nil
    end
end)

-- ★ FIX 2: re-enforce less often (was 0.3s, now 1s — still safe)
task.spawn(function()
    while true do
        task.wait(1)
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

    for _, p in ipairs(char:GetDescendants()) do fortify(p) end
    reg(char.DescendantAdded:Connect(function(p)
        fortify(p)
        task.defer(function() fortify(p) end)
    end))

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

    for _, p in ipairs(char:GetDescendants()) do hookOwnPart(p) end
    reg(char.DescendantAdded:Connect(function(p) hookOwnPart(p) end))

    -- ═══════════════════════════════════
    -- VELOCITY CLAMPING
    -- ★ FIX 3: 2 events instead of 3 (Stepped was redundant)
    -- ═══════════════════════════════════
    local function clampVelocity()
        if not char.Parent or not hrp.Parent then return end

        if hrp.AssemblyAngularVelocity.Magnitude > ANG_CAP then
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

    reg(RunService.RenderStepped:Connect(clampVelocity))
    reg(RunService.Heartbeat:Connect(clampVelocity))

    -- ═══════════════════════════════════
    -- NEARBY PART SCAN
    -- ★ FIX 4: runs every 3rd frame + O(1) player lookup
    -- ★ FIX 5: higher thresholds for world debris so normal
    --          disaster physics don't trigger constant writes
    -- ═══════════════════════════════════
    local scanTick = 0
    reg(RunService.Heartbeat:Connect(function()
        if not char.Parent or not hrp.Parent then return end

        scanTick += 1
        if scanTick < 3 then return end  -- ★ every 3rd frame
        scanTick = 0

        local ok, nearby = pcall(function()
            return workspace:GetPartBoundsInRadius(
                hrp.Position, SCAN_RAD, overlapParams
            )
        end)

        if not ok or not nearby then return end

        for _, part in ipairs(nearby) do
            if not part.Anchored and not part:IsDescendantOf(char) then

                -- ★ FIX 1: O(1) lookup replaces nested loop
                if partToPlayer[part] then
                    -- PLAYER PART — full neutralize
                    killPart(part)
                    pcall(function()
                        if part.AssemblyAngularVelocity.Magnitude > 10
                        or part.AssemblyLinearVelocity.Magnitude > 200 then
                            killPartVelocity(part)
                        end
                    end)
                else
                    -- WORLD DEBRIS
                    -- ★ FIX 5: raised thresholds (was 5/20)
                    -- normal disaster debris won't trigger this
                    -- only weaponized/fling-speed parts get caught
                    pcall(function()
                        local av = part.AssemblyAngularVelocity.Magnitude
                        local lv = part.AssemblyLinearVelocity.Magnitude
                        if av > 25 or lv > 100 then
                            killPart(part)
                            killPartVelocity(part)
                        end
                    end)
                end
            end
        end
    end))

    -- ═══════════════════════════════════
    -- FORCE / WELD GUARD (unchanged — not a lag source)
    -- ═══════════════════════════════════
    reg(char.DescendantAdded:Connect(function(obj)
        if DANGEROUS[obj.ClassName] then
            local function checkExternal()
                pcall(function()
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
            end

            checkExternal()
            task.defer(checkExternal)
            task.delay(0.1, checkExternal)
            return
        end

        if obj:IsA("JointInstance")
        or obj:IsA("WeldConstraint")
        or obj:IsA("Constraint") then
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
            task.delay(0.1, checkJoint)
        end
    end))

    -- ═══════════════════════════════════
    -- SEAT GUARD (uses O(1) cache now)
    -- ═══════════════════════════════════
    reg(hum:GetPropertyChangedSignal("SeatPart"):Connect(function()
        local seat = hum.SeatPart
        if not seat then return end
        -- ★ FIX 1: O(1) check
        if partToPlayer[seat] then
            hum.Sit = false
            return
        end
        if not seat.Anchored and not seat:IsDescendantOf(char) then
            if seat.AssemblyAngularVelocity.Magnitude > 8
            or seat.AssemblyLinearVelocity.Magnitude > 40 then
                hum.Sit = false
            end
        end
    end))

    -- ═══════════════════════════════════
    -- TOUCH GUARD
    -- ★ FIX 6: debounce per part so hundreds of
    --          debris touches don't all fire separately
    -- ═══════════════════════════════════
    local touchCD = {}

    local function hookTouch(bp)
        if not bp:IsA("BasePart") then return end
        reg(bp.Touched:Connect(function(hit)
            if not hit or not hit.Parent then return end
            if hit:IsDescendantOf(char) or hit.Anchored then return end

            -- ★ skip if this part was already handled recently
            if touchCD[hit] then return end
            touchCD[hit] = true
            task.delay(0.15, function() touchCD[hit] = nil end)

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

    -- ═══════════════════════════════════
    -- PLATFORMSTAND GUARD (unchanged)
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
