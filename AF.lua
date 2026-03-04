local Players        = game:GetService("Players")
local RunService     = game:GetService("RunService")
local PhysicsService = game:GetService("PhysicsService")
local LP             = Players.LocalPlayer

local isTeleporting = false
local conns         = {}

----------------------------------------------------------------
--  CONFIGURATION
----------------------------------------------------------------
local CFG = {
    TP_DIST        = 80,
    RING_RADIUS    = 35,
    THREAT_RADIUS  = 25,
    COL_TICK       = 5,
    FORCE_TICK     = 20,
    BFD_TICK       = 3,
    RING_TICK      = 5,
    SHIELD_TICK    = 6,
    NEAR_COL_TICK  = 2,
    NEAR_COL_DIST  = 15,
    MAX_SCAN       = 40,
    -- only angular velocity this high = definitely fling
    -- normal gameplay NEVER produces this
    SPIN_KILL      = 50,
}

local RING_ANGULAR_MIN = 30
local RING_LINEAR_MIN  = 80

----------------------------------------------------------------
--  DANGEROUS CLASSES
----------------------------------------------------------------
local DANGEROUS = {}
for _, cn in ipairs({
    "BodyVelocity","BodyAngularVelocity","BodyForce","BodyPosition",
    "BodyGyro","BodyThrust","RocketPropulsion",
    "Torque","VectorForce","LinearVelocity","AlignPosition",
    "AlignOrientation","AngularVelocity",
}) do DANGEROUS[cn] = true end

----------------------------------------------------------------
--  HELPERS
----------------------------------------------------------------
local V3ZERO = Vector3.zero

local function clearConns()
    for i = #conns, 1, -1 do
        pcall(function() conns[i]:Disconnect() end)
        conns[i] = nil
    end
end
local function reg(c) conns[#conns + 1] = c return c end
local function kill(o) pcall(function() o:Destroy() end) end

local function isFromOtherPlayer(obj)
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LP and plr.Character
        and obj:IsDescendantOf(plr.Character) then
            return true
        end
    end
    return false
end

local function isInAnyCharacter(part)
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr.Character and part:IsDescendantOf(plr.Character) then
            return true
        end
    end
    return false
end

----------------------------------------------------------------
-- RING DETECTION
----------------------------------------------------------------
local knownRingParts = setmetatable({}, {__mode = "k"})

local function isRingPart(part)
    if knownRingParts[part] then return true end
    if not part:IsA("BasePart") then return false end
    if part.Anchored then return false end
    if isInAnyCharacter(part) then return false end

    local av = part.AssemblyAngularVelocity.Magnitude
    local lv = part.AssemblyLinearVelocity.Magnitude

    if av > RING_ANGULAR_MIN and lv > RING_LINEAR_MIN then
        knownRingParts[part] = true
        return true
    end
    if av > RING_ANGULAR_MIN * 3 then
        knownRingParts[part] = true
        return true
    end

    local parent = part.Parent
    if parent and parent ~= workspace and parent ~= game then
        local siblings = parent:GetChildren()
        if #siblings >= 3 then
            local spinCount = 0
            local limit = math.min(#siblings, 8)
            for i = 1, limit do
                local sib = siblings[i]
                if sib:IsA("BasePart") and not sib.Anchored
                and sib.AssemblyAngularVelocity.Magnitude > RING_ANGULAR_MIN * 0.5 then
                    spinCount += 1
                end
            end
            if spinCount >= 3 then
                for _, sib in ipairs(siblings) do
                    if sib:IsA("BasePart") then
                        knownRingParts[sib] = true
                    end
                end
                return true
            end
        end
    end
    return false
end

----------------------------------------------------------------
-- COLLISION GROUPS
----------------------------------------------------------------
local MY_GROUP     = "AntiFling_Me"
local PLAYER_GROUP = "AntiFling_Players"
local RING_GROUP   = "AntiFling_Rings"

pcall(function() PhysicsService:RegisterCollisionGroup(MY_GROUP) end)
pcall(function() PhysicsService:RegisterCollisionGroup(PLAYER_GROUP) end)
pcall(function() PhysicsService:RegisterCollisionGroup(RING_GROUP) end)
pcall(function()
    PhysicsService:CollisionGroupSetCollidable(MY_GROUP, PLAYER_GROUP, false)
    PhysicsService:CollisionGroupSetCollidable(MY_GROUP, RING_GROUP, false)
end)

local function assignGroup(part, group)
    pcall(function() part.CollisionGroup = group end)
end

----------------------------------------------------------------
-- BFD DETECTION
----------------------------------------------------------------
local playerTracker = {}

local function initTracker(plr)
    if plr == LP then return end
    playerTracker[plr] = {
        lastLook  = nil,
        flipCount = 0,
        lastReset = tick(),
        flagged   = false,
    }
end

local function cleanTracker(plr)
    playerTracker[plr] = nil
end

local function updateBFD(plr, pHRP)
    local t = playerTracker[plr]
    if not t or not pHRP then return false end

    local look = pHRP.CFrame.LookVector
    local now  = tick()

    if now - t.lastReset > 1 then
        t.flagged   = t.flipCount > 15
        t.flipCount = 0
        t.lastReset = now
    end

    if t.lastLook then
        if look:Dot(t.lastLook) < -0.5 then
            t.flipCount += 1
        end
    end
    t.lastLook = look
    return t.flagged
end

----------------------------------------------------------------
-- PLAYER GROUP ASSIGNMENT
----------------------------------------------------------------
local function groupPlayerChar(plrChar)
    if not plrChar then return end
    for _, p in ipairs(plrChar:GetDescendants()) do
        if p:IsA("BasePart") then assignGroup(p, PLAYER_GROUP) end
    end
end

local function watchPlayerGroups(plr)
    if plr == LP then return end
    if plr.Character then
        groupPlayerChar(plr.Character)
        reg(plr.Character.DescendantAdded:Connect(function(p)
            if p:IsA("BasePart") then assignGroup(p, PLAYER_GROUP) end
        end))
    end
    reg(plr.CharacterAdded:Connect(function(c)
        task.wait(0.1)
        groupPlayerChar(c)
        reg(c.DescendantAdded:Connect(function(p)
            if p:IsA("BasePart") then assignGroup(p, PLAYER_GROUP) end
        end))
    end))
end

----------------------------------------------------------------
--  MAIN PROTECTION
----------------------------------------------------------------
local function protect(char)
    if not char then return end
    clearConns()
    knownRingParts = setmetatable({}, {__mode = "k"})
    playerTracker  = {}

    local hrp = char:WaitForChild("HumanoidRootPart", 5)
    local hum = char:WaitForChild("Humanoid", 5)
    if not hrp or not hum then return end

    -- immediately shield all parts
    for _, p in ipairs(char:GetDescendants()) do
        if p:IsA("BasePart") then assignGroup(p, MY_GROUP) end
    end

    local lastPos = hrp.Position
    local frame   = 0

    local ringParams = OverlapParams.new()
    ringParams.FilterType = Enum.RaycastFilterType.Exclude
    ringParams.FilterDescendantsInstances = {char}

    for _, plr in ipairs(Players:GetPlayers()) do
        initTracker(plr)
        watchPlayerGroups(plr)
    end
    reg(Players.PlayerAdded:Connect(function(plr)
        initTracker(plr)
        watchPlayerGroups(plr)
    end))
    reg(Players.PlayerRemoving:Connect(cleanTracker))

    local function shieldPart(p)
        if p:IsA("BasePart") then assignGroup(p, MY_GROUP) end
    end
    reg(char.DescendantAdded:Connect(shieldPart))

    local function handleRing(part)
        assignGroup(part, RING_GROUP)
        pcall(function()
            part.CanCollide              = false
            part.CanTouch                = false
            part.AssemblyLinearVelocity  = V3ZERO
            part.AssemblyAngularVelocity = V3ZERO
        end)
    end

    local function nukeRingFamily(part)
        handleRing(part)
        pcall(function()
            local parent = part.Parent
            if parent and parent ~= workspace and parent ~= game then
                for _, sib in ipairs(parent:GetChildren()) do
                    if sib:IsA("BasePart") and not sib.Anchored then
                        knownRingParts[sib] = true
                        handleRing(sib)
                    end
                end
            end
        end)
    end

    local function purgeChar()
        for _, d in ipairs(char:GetDescendants()) do
            if DANGEROUS[d.ClassName] then
                pcall(function()
                    if isFromOtherPlayer(d) then kill(d) return end
                    for _, prop in ipairs({"Attachment0","Attachment1","Part0","Part1"}) do
                        local ok, val = pcall(function() return d[prop] end)
                        if ok and val and typeof(val) == "Instance"
                        and isFromOtherPlayer(val) then
                            kill(d) return
                        end
                    end
                end)
            end
        end
    end
    purgeChar()

    -- ═══════════════════════════════════════════
    -- ANTI-RAGDOLL (only this state blocked)
    -- everything else (FallingDown, PlatformStand,
    -- Physics, Freefall) left completely alone
    -- ═══════════════════════════════════════════
    pcall(function()
        hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
    end)
    reg(hum.StateChanged:Connect(function(_, s)
        if s == Enum.HumanoidStateType.Ragdoll then
            hum:ChangeState(Enum.HumanoidStateType.GettingUp)
        end
    end))

    -- ═══════════════════════════════════════════
    -- NO PLATFORMSTAND GUARD
    -- trip works 100% because we never touch it
    -- collision groups protect you even while tripped
    -- ═══════════════════════════════════════════

    -- ═══════════════════════════════════════════
    -- FOREIGN FORCE / WELD GUARD
    -- ═══════════════════════════════════════════
    reg(char.DescendantAdded:Connect(function(obj)
        if obj:IsA("BasePart") then
            assignGroup(obj, MY_GROUP)
            return
        end

        if DANGEROUS[obj.ClassName] then
            task.defer(function()
                pcall(function()
                    if isFromOtherPlayer(obj) then obj:Destroy() return end
                    for _, prop in ipairs({"Attachment0","Attachment1","Part0","Part1"}) do
                        local ok, val = pcall(function() return obj[prop] end)
                        if ok and val and typeof(val) == "Instance"
                        and isFromOtherPlayer(val) then
                            obj:Destroy() return
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
                    local p0, p1
                    if obj:IsA("Constraint") then
                        local a0, a1 = obj.Attachment0, obj.Attachment1
                        p0 = a0 and a0.Parent
                        p1 = a1 and a1.Parent
                    else
                        p0, p1 = obj.Part0, obj.Part1
                    end
                    if not p0 or not p1 then return end
                    local o0 = p0:IsDescendantOf(char)
                    local o1 = p1:IsDescendantOf(char)
                    if o0 == o1 then return end
                    local foreign = o0 and p1 or p0
                    if isFromOtherPlayer(foreign) then obj:Destroy() end
                end)
            end)
        end
    end))

    -- ═══════════════════════════════════════════
    -- SEAT-FLING BLOCK
    -- ═══════════════════════════════════════════
    reg(hum:GetPropertyChangedSignal("SeatPart"):Connect(function()
        local seat = hum.SeatPart
        if not seat then return end
        local isForeign = false
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LP and plr.Character
            and seat:IsDescendantOf(plr.Character) then
                isForeign = true
                break
            end
        end
        if not isForeign and not seat.Anchored then
            if seat.AssemblyAngularVelocity.Magnitude > 10
            or seat.AssemblyLinearVelocity.Magnitude > 50 then
                isForeign = true
            end
        end
        if isForeign then
            hum.Sit = false
        end
    end))

    -- ═══════════════════════════════════════════
    -- RING INTERCEPTOR
    -- ═══════════════════════════════════════════
    reg(workspace.DescendantAdded:Connect(function(obj)
        if not obj:IsA("BasePart") then return end
        if obj.Anchored then return end
        if obj:IsDescendantOf(char) then return end

        local function check()
            pcall(function()
                if obj.Parent and isRingPart(obj) then
                    nukeRingFamily(obj)
                end
            end)
        end
        task.defer(check)
        task.delay(0.15, check)
        task.delay(0.4, check)
    end))

    -- ═══════════════════════════════════════════
    -- CONTACT SHIELD
    -- if a ring part somehow touches you,
    -- neutralize it and zero ONLY your angular
    -- velocity (no teleport, no position change)
    -- ═══════════════════════════════════════════
    local touchCD = {}

    local function hookTouch(bodyPart)
        if not bodyPart:IsA("BasePart") then return end
        reg(bodyPart.Touched:Connect(function(hit)
            if touchCD[bodyPart] then return end
            if not hit or not hit.Parent then return end
            if hit:IsDescendantOf(char) then return end
            if hit.Anchored then return end
            if not isRingPart(hit) then return end

            touchCD[bodyPart] = true
            task.delay(0.05, function() touchCD[bodyPart] = nil end)

            nukeRingFamily(hit)

            -- only zero spinning, never teleport
            pcall(function()
                hrp.AssemblyAngularVelocity = V3ZERO
            end)
        end))
    end

    for _, p in ipairs(char:GetDescendants()) do hookTouch(p) end
    reg(char.DescendantAdded:Connect(function(p)
        shieldPart(p)
        hookTouch(p)
    end))

    -- ═══════════════════════════════════════════
    -- HEARTBEAT
    -- no velocity clamping
    -- no position tracking
    -- no snap-back
    -- no teleporting
    -- just maintain collision groups and
    -- kill spinning (angular velocity only)
    -- ═══════════════════════════════════════════
    reg(RunService.Heartbeat:Connect(function()
        if not char.Parent or not hrp.Parent then return end
        frame += 1
        local pos = hrp.Position

        -- teleport whitelist
        if lastPos and (pos - lastPos).Magnitude > CFG.TP_DIST then
            isTeleporting = true
            task.delay(0.6, function() isTeleporting = false end)
        end
        lastPos = pos
        if isTeleporting then return end

        -- ONLY thing we touch on your character:
        -- kill spinning. thats it.
        -- normal gameplay never hits 50 angular velocity
        -- you can fall, jump, trip, boost, fly — untouched
        local angMag = hrp.AssemblyAngularVelocity.Magnitude
        if angMag > CFG.SPIN_KILL then
            hrp.AssemblyAngularVelocity = V3ZERO
        end

        -- shield enforcement
        if frame % CFG.SHIELD_TICK == 0 then
            for _, p in ipairs(char:GetDescendants()) do
                if p:IsA("BasePart") then
                    assignGroup(p, MY_GROUP)
                end
            end
        end

        -- player group enforcement
        if frame % CFG.COL_TICK == 0 then
            for _, plr in ipairs(Players:GetPlayers()) do
                if plr ~= LP and plr.Character then
                    for _, p in ipairs(plr.Character:GetDescendants()) do
                        if p:IsA("BasePart") then
                            assignGroup(p, PLAYER_GROUP)
                        end
                    end
                end
            end
        end

        -- nearby player aggressive enforcement
        if frame % CFG.NEAR_COL_TICK == 0 then
            for _, plr in ipairs(Players:GetPlayers()) do
                if plr ~= LP and plr.Character then
                    local pH = plr.Character:FindFirstChild("HumanoidRootPart")
                    if pH and (pH.Position - pos).Magnitude < CFG.NEAR_COL_DIST then
                        for _, p in ipairs(plr.Character:GetDescendants()) do
                            if p:IsA("BasePart") then
                                assignGroup(p, PLAYER_GROUP)
                                p.CanCollide = false
                                p.CanTouch   = false
                            end
                        end
                    end
                end
            end
        end

        -- BFD detection — extra isolate flippers
        if frame % CFG.BFD_TICK == 0 then
            for _, plr in ipairs(Players:GetPlayers()) do
                if plr ~= LP and plr.Character then
                    local pH = plr.Character:FindFirstChild("HumanoidRootPart")
                    if pH then
                        local isBFD = updateBFD(plr, pH)
                        if isBFD and (pH.Position - pos).Magnitude < CFG.THREAT_RADIUS then
                            for _, p in ipairs(plr.Character:GetDescendants()) do
                                if p:IsA("BasePart") then
                                    assignGroup(p, PLAYER_GROUP)
                                    p.CanCollide = false
                                    p.CanTouch   = false
                                end
                            end
                        end
                    end
                end
            end
        end

        -- ring radar
        if frame % CFG.RING_TICK == 0 then
            local ok, nearby = pcall(function()
                return workspace:GetPartBoundsInRadius(
                    pos, CFG.RING_RADIUS, ringParams
                )
            end)
            if ok and nearby then
                local scanned = 0
                for _, part in ipairs(nearby) do
                    if scanned >= CFG.MAX_SCAN then break end
                    if knownRingParts[part] then
                        handleRing(part)
                    elseif not part.Anchored
                    and not isInAnyCharacter(part) then
                        scanned += 1
                        if isRingPart(part) then
                            nukeRingFamily(part)
                        end
                    end
                end
            end
        end

        -- force sweep
        if frame % CFG.FORCE_TICK == 0 then purgeChar() end
    end))
end

----------------------------------------------------------------
-- BOOTSTRAP
----------------------------------------------------------------
protect(LP.Character)
LP.CharacterAdded:Connect(function(c)
    pcall(function()
        for _, p in ipairs(c:GetDescendants()) do
            if p:IsA("BasePart") then assignGroup(p, MY_GROUP) end
        end
    end)
    task.wait(0.2)
    protect(c)
end)

getgenv().WhitelistTP = function()
    isTeleporting = true
    task.delay(1, function() isTeleporting = false end)
end
