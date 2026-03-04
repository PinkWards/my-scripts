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
    TP_DIST       = 80,
    RING_RADIUS   = 35,
    THREAT_RADIUS = 20,
    COL_TICK      = 5,
    FORCE_TICK    = 20,
    PROX_TICK     = 8,
    RING_TICK     = 5,
    SHIELD_TICK   = 6,
    BFD_TICK      = 3,
    MAX_SCAN      = 40,
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
-- 3 groups:
--   ME     = your character
--   PLAYER = all other player characters
--   RING   = confirmed ring parts
--
-- ME cannot collide with PLAYER (no pushing/bumping)
-- ME cannot collide with RING   (no ring fling)
-- PLAYER can still collide with game world normally
-- RING can still collide with game world normally
-- YOU can still collide with game world normally
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
-- ASSIGN PLAYER PARTS TO PLAYER GROUP
-- this is what makes you pass through ALL players
-- engine-level, cannot be overridden by their client
----------------------------------------------------------------
local function groupPlayerChar(plrChar)
    if not plrChar then return end
    for _, p in ipairs(plrChar:GetDescendants()) do
        if p:IsA("BasePart") then
            assignGroup(p, PLAYER_GROUP)
        end
    end
end

local function watchPlayerGroups(plr)
    if plr == LP then return end
    if plr.Character then groupPlayerChar(plr.Character) end
    reg(plr.CharacterAdded:Connect(function(c)
        task.wait(0.1)
        groupPlayerChar(c)
        -- catch new parts added to their character
        reg(c.DescendantAdded:Connect(function(p)
            if p:IsA("BasePart") then
                assignGroup(p, PLAYER_GROUP)
            end
        end))
    end))
    -- also watch existing character for new parts
    if plr.Character then
        reg(plr.Character.DescendantAdded:Connect(function(p)
            if p:IsA("BasePart") then
                assignGroup(p, PLAYER_GROUP)
            end
        end))
    end
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

    local safeCF       = hrp.CFrame
    local lastPos      = hrp.Position
    local frame        = 0
    local recentThreat = false

    local ringParams = OverlapParams.new()
    ringParams.FilterType = Enum.RaycastFilterType.Exclude
    ringParams.FilterDescendantsInstances = {char}

    -- init trackers
    for _, plr in ipairs(Players:GetPlayers()) do initTracker(plr) end
    reg(Players.PlayerAdded:Connect(function(plr)
        initTracker(plr)
        watchPlayerGroups(plr)
    end))
    reg(Players.PlayerRemoving:Connect(cleanTracker))

    -- assign YOUR parts to your group
    local function shieldPart(p)
        if p:IsA("BasePart") then assignGroup(p, MY_GROUP) end
    end
    for _, p in ipairs(char:GetDescendants()) do shieldPart(p) end
    reg(char.DescendantAdded:Connect(shieldPart))

    -- assign ALL other players to player group
    for _, plr in ipairs(Players:GetPlayers()) do
        watchPlayerGroups(plr)
    end

    local function flagThreat()
        recentThreat = true
        task.delay(3, function() recentThreat = false end)
    end

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

    -- ═══════════════════════════════════════════
    -- LAYER 1 · ANTI-RAGDOLL
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
    -- LAYER 2 · PLATFORM-STAND GUARD (trip ok)
    -- ═══════════════════════════════════════════
    reg(hum:GetPropertyChangedSignal("PlatformStand"):Connect(function()
        if hum.PlatformStand then
            local lv = hrp.AssemblyLinearVelocity.Magnitude
            local av = hrp.AssemblyAngularVelocity.Magnitude
            if lv > 100 or av > 30 then
                hum.PlatformStand = false
                hrp.AssemblyLinearVelocity  = V3ZERO
                hrp.AssemblyAngularVelocity = V3ZERO
            end
        end
    end))

    -- ═══════════════════════════════════════════
    -- LAYER 3 · FOREIGN FORCE / WELD GUARD
    -- ═══════════════════════════════════════════
    reg(char.DescendantAdded:Connect(function(obj)
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
    -- LAYER 4 · SEAT-FLING BLOCK
    -- ═══════════════════════════════════════════
    reg(hum:GetPropertyChangedSignal("SeatPart"):Connect(function()
        local seat = hum.SeatPart
        if not seat then return end
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LP and plr.Character
            and seat:IsDescendantOf(plr.Character) then
                hum.Sit = false
                task.defer(function()
                    if hrp.Parent then
                        hrp.CFrame = safeCF
                        hrp.AssemblyLinearVelocity  = V3ZERO
                        hrp.AssemblyAngularVelocity = V3ZERO
                    end
                end)
                break
            end
        end
    end))

    -- ═══════════════════════════════════════════
    -- LAYER 5 · RING INTERCEPTOR
    -- ═══════════════════════════════════════════
    reg(workspace.DescendantAdded:Connect(function(obj)
        if not obj:IsA("BasePart") then return end
        if obj.Anchored then return end
        if obj:IsDescendantOf(char) then return end

        local function check()
            pcall(function()
                if obj.Parent and isRingPart(obj) then
                    flagThreat()
                    nukeRingFamily(obj)
                end
            end)
        end
        task.defer(check)
        task.delay(0.15, check)
        task.delay(0.4, check)
    end))

    -- ═══════════════════════════════════════════
    -- LAYER 6 · CONTACT SHIELD
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

            flagThreat()
            nukeRingFamily(hit)

            pcall(function()
                hrp.AssemblyLinearVelocity  = V3ZERO
                hrp.AssemblyAngularVelocity = V3ZERO
                hrp.CFrame = safeCF
            end)
        end))
    end

    for _, p in ipairs(char:GetDescendants()) do hookTouch(p) end
    reg(char.DescendantAdded:Connect(hookTouch))

    -- ═══════════════════════════════════════════
    -- HEARTBEAT
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
        if isTeleporting then safeCF = hrp.CFrame return end

        -- safe position
        if hum.FloorMaterial ~= Enum.Material.Air then
            safeCF = hrp.CFrame
        end

        -- your parts stay in your group
        if frame % CFG.SHIELD_TICK == 0 then
            for _, p in ipairs(char:GetDescendants()) do
                if p:IsA("BasePart") then
                    assignGroup(p, MY_GROUP)
                end
            end
        end

        -- keep all player parts in player group
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

        -- BFD detection
        if frame % CFG.BFD_TICK == 0 then
            for _, plr in ipairs(Players:GetPlayers()) do
                if plr ~= LP and plr.Character then
                    local pH = plr.Character:FindFirstChild("HumanoidRootPart")
                    if pH then
                        local isBFD = updateBFD(plr, pH)
                        if isBFD and (pH.Position - pos).Magnitude < CFG.THREAT_RADIUS then
                            flagThreat()
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
                            flagThreat()
                            nukeRingFamily(part)
                        end
                    end
                end
            end
        end

        -- post-fling recovery
        if recentThreat then
            local av = hrp.AssemblyAngularVelocity
            local lv = hrp.AssemblyLinearVelocity
            if av.Magnitude > 25 then
                hrp.AssemblyAngularVelocity = V3ZERO
            end
            if lv.Magnitude > 250 then
                hrp.AssemblyLinearVelocity  = V3ZERO
                hrp.AssemblyAngularVelocity = V3ZERO
                hrp.CFrame = safeCF
            end
        end

        -- force sweep
        if frame % CFG.FORCE_TICK == 0 then
            for _, d in ipairs(char:GetDescendants()) do
                if DANGEROUS[d.ClassName] then
                    pcall(function()
                        for _, prop in ipairs({"Attachment0","Attachment1","Part0","Part1"}) do
                            local ok2, val = pcall(function() return d[prop] end)
                            if ok2 and val and typeof(val) == "Instance"
                            and isFromOtherPlayer(val) then
                                kill(d) return
                            end
                        end
                    end)
                end
            end
        end
    end))
end

----------------------------------------------------------------
-- BOOTSTRAP
----------------------------------------------------------------
protect(LP.Character)
LP.CharacterAdded:Connect(function(c)
    task.wait(0.2)
    protect(c)
end)

getgenv().WhitelistTP = function()
    isTeleporting = true
    task.delay(1, function() isTeleporting = false end)
end
