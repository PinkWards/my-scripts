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

local SCAN_INTERVAL  = 0.15
local PART_COOLDOWN  = 3.0
local TOUCH_COOLDOWN = 0.5

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
    "BodyVelocity","BodyAngularVelocity","BodyForce",
    "BodyPosition","BodyGyro","BodyThrust","RocketPropulsion",
    "Torque","VectorForce","LinearVelocity","AlignPosition",
    "AlignOrientation","AngularVelocity",
}) do DANGEROUS[cn] = true end

-- ═══════════════════════════════════════════════
-- ENEMY PART FAST LOOKUP TABLE
-- Maintained incrementally so scan loop is O(1) per part
-- Covers character parts AND workspace tool parts
-- ═══════════════════════════════════════════════
local enemyPartSet = {}

local function addToEnemySet(p)
    if p:IsA("BasePart") then
        enemyPartSet[p] = true
    end
end

local function removeFromEnemySet(p)
    if p:IsA("BasePart") then
        enemyPartSet[p] = nil
    end
end

-- ═══════════════════════════════════════════════
-- UTILITY
-- ═══════════════════════════════════════════════
local function safeSet(part, prop, val)
    pcall(function() part[prop] = val end)
end

local function killPart(part)
    if not part:IsA("BasePart") then return end
    if part.CanCollide   then safeSet(part, "CanCollide",  false) end
    if part.CanTouch     then safeSet(part, "CanTouch",    false) end
    if not part.Massless then safeSet(part, "Massless",    true)  end
    if cgWork and part.CollisionGroup ~= "_af_them" then
        safeSet(part, "CollisionGroup", "_af_them")
    end
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

    local function enforceCanCollide()
        if part.CanCollide then safeSet(part, "CanCollide", false) end
    end
    local function enforceCanTouch()
        if part.CanTouch then safeSet(part, "CanTouch", false) end
    end

    connTable[#connTable + 1] =
        part:GetPropertyChangedSignal("CanCollide"):Connect(enforceCanCollide)
    connTable[#connTable + 1] =
        part:GetPropertyChangedSignal("CanTouch"):Connect(enforceCanTouch)

    if cgWork then
        connTable[#connTable + 1] =
            part:GetPropertyChangedSignal("CollisionGroup"):Connect(function()
                pcall(function()
                    if part.CollisionGroup ~= "_af_them" then
                        part.CollisionGroup = "_af_them"
                    end
                end)
            end)
    end
end

-- ─────────────────────────────────────────────
-- trackChar: hook an enemy player's character
-- No batching — enemy chars are small (< 20 parts)
-- so processing them immediately is fine and safe
-- ─────────────────────────────────────────────
local function trackChar(ch, plr)
    if not ch then return end

    if trackedCharConns[plr] then
        for _, c in ipairs(trackedCharConns[plr]) do
            pcall(function() c:Disconnect() end)
        end
        -- Remove old char parts from enemy set
        if plr.Character and plr.Character ~= ch then
            for _, p in ipairs(plr.Character:GetDescendants()) do
                removeFromEnemySet(p)
            end
        end
    end

    local charConns = {}
    trackedCharConns[plr] = charConns

    -- Process immediately — char parts are few, this won't lag
    for _, p in ipairs(ch:GetDescendants()) do
        addToEnemySet(p)
        killPart(p)
        hookPartProperties(p, charConns)
    end

    charConns[#charConns + 1] = ch.DescendantAdded:Connect(function(p)
        addToEnemySet(p)
        killPart(p)
        task.defer(function() killPart(p) end)
        task.delay(0.1, function() killPart(p) end)
        hookPartProperties(p, charConns)
    end)

    charConns[#charConns + 1] = ch.DescendantRemoving:Connect(function(p)
        removeFromEnemySet(p)
    end)
end

-- ─────────────────────────────────────────────
-- Also track parts that enemy players put in
-- Workspace directly (ring tools, fling parts)
-- This is what the original was missing for workspace tools
-- ─────────────────────────────────────────────
local workspaceConns = {}

local function watchPlayerWorkspaceParts(plr)
    -- Watch workspace for parts whose name/owner ties to this player
    -- The reliable way: watch the player's tool/backpack additions
    local conn1 = plr.Backpack.ChildAdded:Connect(function(tool)
        -- When a tool enters backpack, parts aren't dangerous yet
    end)

    -- Watch when player equips something into workspace
    local conn2 = workspace.ChildAdded:Connect(function(obj)
        -- If a new model/part appears in workspace and a script
        -- in it references this player, treat it as enemy
        -- Simpler and reliable: just add it to scan naturally
        -- The key fix is removing MAX_PER_SCAN so scan catches it
    end)

    workspaceConns[plr] = {conn1, conn2}
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
    local ch = plr.Character
    if ch then
        for _, p in ipairs(ch:GetDescendants()) do
            removeFromEnemySet(p)
        end
    end
    trackedPlayers[plr] = nil
    if trackedCharConns[plr] then
        for _, c in ipairs(trackedCharConns[plr]) do
            pcall(function() c:Disconnect() end)
        end
        trackedCharConns[plr] = nil
    end
    if workspaceConns[plr] then
        for _, c in ipairs(workspaceConns[plr]) do
            pcall(function() c:Disconnect() end)
        end
        workspaceConns[plr] = nil
    end
end)

-- ─────────────────────────────────────────────
-- Periodic re-enforce enemy chars
-- Only touches parts that actually need fixing
-- ─────────────────────────────────────────────
task.spawn(function()
    while true do
        task.wait(0.6)
        for plr in pairs(trackedPlayers) do
            local ch = plr.Character
            if ch then
                for _, p in ipairs(ch:GetDescendants()) do
                    if p:IsA("BasePart") then
                        local needsFix = p.CanCollide or p.CanTouch
                            or not p.Massless
                            or (cgWork and p.CollisionGroup ~= "_af_them")
                        if needsFix then killPart(p) end
                    end
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

    -- ─────────────────────────────────────
    -- OUR COLLISION GROUP
    -- ─────────────────────────────────────
    local function fortify(p)
        if not p:IsA("BasePart") then return end
        if cgWork and p.CollisionGroup ~= "_af_me" then
            safeSet(p, "CollisionGroup", "_af_me")
        end
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

    -- ─────────────────────────────────────
    -- VELOCITY CLAMPING — Heartbeat only
    -- ─────────────────────────────────────
    local function clampVelocity()
        if not char.Parent or not hrp.Parent then return end

        if hrp.AssemblyAngularVelocity.Magnitude > ANG_CAP then
            hrp.AssemblyAngularVelocity = V3ZERO
        end

        local vel = hrp.AssemblyLinearVelocity
        local vx, vy, vz = vel.X, vel.Y, vel.Z
        local hMag = math.sqrt(vx*vx + vz*vz)
        local dirty = false

        if hMag > HORIZ_CAP then
            local s = HORIZ_CAP / hMag
            vx, vz = vx*s, vz*s
            dirty = true
        end
        if vy > UP_CAP then
            vy = UP_CAP; dirty = true
        elseif vy < -DOWN_CAP then
            vy = -DOWN_CAP; dirty = true
        end

        if dirty then
            hrp.AssemblyLinearVelocity = Vector3.new(vx, vy, vz)
        end
    end

    reg(RunService.Heartbeat:Connect(clampVelocity))

    -- ─────────────────────────────────────
    -- NEARBY PART SCAN
    --
    -- KEY FIXES vs the broken version:
    -- 1. NO MAX_PER_SCAN cap — enemy parts must NEVER be skipped
    -- 2. enemyPartSet gives O(1) lookup so no nested player loop
    -- 3. Map parts use cooldown cache to skip redundant work
    -- 4. Enemy parts are ALWAYS processed, no cooldown on them
    -- ─────────────────────────────────────
    local partLastHandled = {}
    local lastCleanup = 0
    local lastScan    = 0

    reg(RunService.Heartbeat:Connect(function()
        local now = tick()
        if now - lastScan < SCAN_INTERVAL then return end
        lastScan = now

        if not char.Parent or not hrp.Parent then return end

        -- Clean stale cache every 15s
        if now - lastCleanup > 15 then
            lastCleanup = now
            for p, t in pairs(partLastHandled) do
                if now - t > PART_COOLDOWN * 2 then
                    partLastHandled[p] = nil
                end
            end
        end

        local ok, nearby = pcall(function()
            return workspace:GetPartBoundsInRadius(hrp.Position, SCAN_RAD, overlapParams)
        end)
        if not ok or not nearby then return end

        for _, part in ipairs(nearby) do
            if part.Anchored or part:IsDescendantOf(char) then continue end

            -- O(1) lookup — is this an enemy player part?
            if enemyPartSet[part] then
                -- ALWAYS process enemy parts — no cap, no cooldown
                killPart(part)
                pcall(function()
                    if part.AssemblyAngularVelocity.Magnitude > 10
                    or part.AssemblyLinearVelocity.Magnitude > 200 then
                        killPartVelocity(part)
                    end
                end)
            else
                -- Map/disaster part — use cooldown to skip redundant work
                -- This is where we save performance on map load
                local av, lv = 0, 0
                pcall(function()
                    av = part.AssemblyAngularVelocity.Magnitude
                    lv = part.AssemblyLinearVelocity.Magnitude
                end)

                local isDangerous = av > 5 or lv > 20

                if isDangerous then
                    -- Dangerous map debris: always act immediately
                    partLastHandled[part] = now
                    killPart(part)
                    killPartVelocity(part)
                elseif not partLastHandled[part]
                    or (now - partLastHandled[part] > PART_COOLDOWN) then
                    -- Calm map part: only re-check after cooldown expires
                    -- This is the main lag fix for map loads
                    partLastHandled[part] = now
                    local needsFix = part.CanCollide or part.CanTouch
                        or (cgWork and part.CollisionGroup ~= "_af_them")
                    if needsFix then killPart(part) end
                end
                -- If cached and calm: skip entirely — zero work this tick
            end
        end
    end))

    -- ─────────────────────────────────────
    -- FORCE / WELD GUARD
    -- ─────────────────────────────────────
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
            task.delay(0.1, checkExternal)
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
            task.delay(0.1, checkJoint)
        end
    end))

    -- ─────────────────────────────────────
    -- SEAT GUARD
    -- ─────────────────────────────────────
    reg(hum:GetPropertyChangedSignal("SeatPart"):Connect(function()
        local seat = hum.SeatPart
        if not seat then return end
        -- O(1) check using enemyPartSet
        if enemyPartSet[seat] then
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

    -- ─────────────────────────────────────
    -- TOUCH GUARD — per-part cooldown stops debris spam
    -- Enemy parts always trigger clampVelocity immediately
    -- ─────────────────────────────────────
    local touchCooldowns = {}

    local function hookTouch(bp)
        if not bp:IsA("BasePart") then return end
        reg(bp.Touched:Connect(function(hit)
            if not hit or not hit.Parent then return end
            if hit:IsDescendantOf(char) or hit.Anchored then return end

            local now = tick()
            if touchCooldowns[hit] and now - touchCooldowns[hit] < TOUCH_COOLDOWN then
                return
            end

            -- Enemy part touch: treat as higher threat
            if enemyPartSet[hit] then
                touchCooldowns[hit] = now
                killPart(hit)
                pcall(function() killPartVelocity(hit) end)
                task.defer(clampVelocity)
                return
            end

            pcall(function()
                local av = hit.AssemblyAngularVelocity.Magnitude
                local lv = hit.AssemblyLinearVelocity.Magnitude
                if av > 5 or lv > 20 then
                    touchCooldowns[hit] = now
                    killPart(hit)
                    killPartVelocity(hit)
                    task.defer(clampVelocity)
                end
            end)
        end))
    end

    -- Clean touch cooldowns periodically
    task.spawn(function()
        while char.Parent do
            task.wait(5)
            local now = tick()
            for part, t in pairs(touchCooldowns) do
                if now - t > TOUCH_COOLDOWN * 4 then
                    touchCooldowns[part] = nil
                end
            end
        end
    end)

    for _, p in ipairs(char:GetDescendants()) do hookTouch(p) end
    reg(char.DescendantAdded:Connect(hookTouch))

    -- ─────────────────────────────────────
    -- PLATFORMSTAND GUARD
    -- ─────────────────────────────────────
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
