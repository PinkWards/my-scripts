local Players        = game:GetService("Players")
local RunService     = game:GetService("RunService")
local PhysicsService = game:GetService("PhysicsService")
local LP             = Players.LocalPlayer

local isTeleporting = false
local conns         = {}

----------------------------------------------------------------
--  VULNERABILITY ANALYSIS & PATCHES:
--
--  V1.  MICRO-FLING: apply tiny velocity each frame
--       staying under threshold but accumulating displacement
--       FIX: track cumulative unexpected displacement over time
--
--  V2.  DELAYED FLING: attach force, wait 3+ seconds, activate
--       bypasses "from other player" check if reparented
--       FIX: destroy ANY force on character not in whitelist
--
--  V3.  INVISIBLE PART FLING: transparent spinning parts
--       ring detection misses them if Size is tiny
--       FIX: check velocity regardless of size/transparency
--
--  V4.  GROUND REMOVAL: delete floor under you, you fall into
--       void, safeCF is now mid-air or void position
--       FIX: validate safeCF Y coordinate, never save below map
--
--  V5.  SAFECF POISONING: slowly push you to edge/void,
--       safeCF updates while grounded at bad position
--       FIX: keep multiple safe positions, validate all of them
--
--  V6.  ACCESSORY FLING: put spinning mesh in accessory handle
--       bypasses character descendant checks
--       FIX: treat all accessories from other players same as parts
--
--  V7.  NETWORK OWNERSHIP EXPLOIT: take ownership of YOUR parts
--       and CFrame them directly
--       FIX: continuously verify HRP ownership is local player
--
--  V8.  RAPID RESPAWN FLING: kill you + fling during spawn
--       protection not active yet during WaitForChild
--       FIX: add pre-protection during spawn
--
--  V9.  CAMERA FLING: manipulate your camera to cause disorientation
--       not physical but annoying
--       FIX: lock camera subject to your character
--
--  V10. ANIMATION SPEED FLING: play root-motion animation at 100x speed
--       moves your root part through animation not velocity
--       FIX: monitor root part displacement independent of velocity
--
--  V11. COLLISION GROUP OVERRIDE: exploiter sets their parts back
--       to default group rapidly
--       FIX: higher frequency group enforcement on nearby players
--
--  V12. PHASE FLING: noclip inside you, re-enable collision
--       suddenly while spinning to push from inside
--       FIX: collision groups make this impossible since mutual
--
--  V13. HUMANOID PROPERTY MANIPULATION: set your WalkSpeed to 0
--       or JumpPower to 0 remotely, then push you
--       FIX: monitor humanoid property changes
--
--  V14. ATTACHMENT FLING: create attachment on your HRP, use
--       AlignPosition targeting that attachment
--       FIX: destroy foreign attachments too
--
--  V15. TERRAIN FLING: modify terrain to create launcher
--       FIX: velocity deviation catches the launch
--
--  V16. VEHICLE SEAT FLING: put you in vehicle seat then
--       spin the vehicle
--       FIX: expanded seat check covers vehicle seats
--
--  V17. MASSLESS FLING: set your parts to Massless = true
--       making you extremely light and easy to push
--       FIX: monitor and revert Massless changes
--
--  V18. MESH DEFORMATION FLING: deform your mesh to create
--       physics glitch
--       FIX: velocity deviation catches result
--
--  V19. MULTI-PLAYER COORDINATED FLING: multiple players
--       each apply small forces below individual threshold
--       FIX: cumulative displacement tracking catches total
--
--  V20. TOOL DROP FLING: drop tool with spinning handle near you
--       handle is unanchored, not in character anymore
--       FIX: ring detection catches any spinning unanchored part
----------------------------------------------------------------

----------------------------------------------------------------
--  CONFIGURATION
----------------------------------------------------------------
local CFG = {
    TP_DIST       = 80,
    RING_RADIUS   = 35,
    THREAT_RADIUS = 25,
    COL_TICK      = 5,
    FORCE_TICK    = 12,
    BFD_TICK      = 3,
    RING_TICK     = 5,
    SHIELD_TICK   = 4,
    MAX_SCAN      = 40,
    
    VEL_MULT      = 2.5,
    VEL_MIN       = 80,
    VERT_MULT     = 2.0,
    VERT_MIN      = 80,
    ANG_MAX       = 50,
    FLING_FRAMES  = 2,
    
    -- V1: micro-fling cumulative tracking
    DRIFT_WINDOW    = 1.0,
    DRIFT_MAX       = 20,
    
    -- V4/V5: safe position validation
    MIN_SAFE_Y      = -50,
    SAFE_HISTORY    = 5,
    
    -- V11: nearby player group enforcement boost
    NEAR_COL_DIST   = 15,
    NEAR_COL_TICK   = 2,
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

-- V14: suspicious attachment/object classes
local SUSPICIOUS = {}
for cn, _ in pairs(DANGEROUS) do SUSPICIOUS[cn] = true end
SUSPICIOUS["Attachment"] = true
SUSPICIOUS["AlignPosition"] = true
SUSPICIOUS["AlignOrientation"] = true

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

    -- V3: check regardless of size/transparency
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
-- V4/V5: SAFE POSITION MANAGER
-- keeps history of safe positions and validates them
----------------------------------------------------------------
local SafeManager = {}
SafeManager.__index = SafeManager

function SafeManager.new(initialCF)
    local self = setmetatable({}, SafeManager)
    self.history = {}
    self.maxHistory = CFG.SAFE_HISTORY
    self:push(initialCF)
    return self
end

function SafeManager:push(cf)
    -- V4: never save positions below minimum Y
    if cf.Position.Y < CFG.MIN_SAFE_Y then return end
    
    table.insert(self.history, 1, cf)
    if #self.history > self.maxHistory then
        table.remove(self.history)
    end
end

function SafeManager:get()
    -- return most recent valid position
    for _, cf in ipairs(self.history) do
        if cf.Position.Y >= CFG.MIN_SAFE_Y then
            return cf
        end
    end
    -- absolute fallback: spawn location
    local spawnCF = CFrame.new(0, 50, 0)
    pcall(function()
        local spawns = workspace:FindFirstChildWhichIsA("SpawnLocation", true)
        if spawns then
            spawnCF = spawns.CFrame + Vector3.new(0, 5, 0)
        end
    end)
    return spawnCF
end

function SafeManager:validate(currentY)
    -- V5: if current position is way below all safe positions
    -- something pulled us down
    local best = self:get()
    if currentY < best.Position.Y - 100 then
        return false
    end
    return true
end

----------------------------------------------------------------
-- V1: DRIFT TRACKER
-- tracks cumulative unexpected displacement over time window
----------------------------------------------------------------
local DriftTracker = {}
DriftTracker.__index = DriftTracker

function DriftTracker.new()
    local self = setmetatable({}, DriftTracker)
    self.samples = {}
    self.window = CFG.DRIFT_WINDOW
    return self
end

function DriftTracker:add(amount)
    table.insert(self.samples, {time = tick(), amount = amount})
end

function DriftTracker:getTotal()
    local now = tick()
    local total = 0
    local keep = {}
    for _, s in ipairs(self.samples) do
        if now - s.time < self.window then
            total += s.amount
            keep[#keep + 1] = s
        end
    end
    self.samples = keep
    return total
end

----------------------------------------------------------------
-- V2: FORCE WHITELIST
-- records all force objects that exist when character spawns
-- anything new that wasnt there at spawn = suspicious
----------------------------------------------------------------
local function buildForceWhitelist(char)
    local whitelist = setmetatable({}, {__mode = "k"})
    for _, d in ipairs(char:GetDescendants()) do
        if DANGEROUS[d.ClassName] then
            whitelist[d] = true
        end
    end
    return whitelist
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

    -- V8: immediately set collision group before anything else
    for _, p in ipairs(char:GetDescendants()) do
        if p:IsA("BasePart") then assignGroup(p, MY_GROUP) end
    end

    local safeMan      = SafeManager.new(hrp.CFrame)
    local drift        = DriftTracker.new()
    local forceWL      = buildForceWhitelist(char)
    local lastPos      = hrp.Position
    local frame        = 0
    local recentThreat = false
    local isTripping   = false
    local flingCounter = 0
    local lastMoveDir  = V3ZERO

    -- V13: store original humanoid properties
    local origWS = hum.WalkSpeed
    local origJP = hum.JumpPower
    local origJH = hum.JumpHeight
    local origMSA = hum.MaxSlopeAngle

    local ringParams = OverlapParams.new()
    ringParams.FilterType = Enum.RaycastFilterType.Exclude
    ringParams.FilterDescendantsInstances = {char}

    -- init player tracking
    for _, plr in ipairs(Players:GetPlayers()) do
        initTracker(plr)
        watchPlayerGroups(plr)
    end
    reg(Players.PlayerAdded:Connect(function(plr)
        initTracker(plr)
        watchPlayerGroups(plr)
    end))
    reg(Players.PlayerRemoving:Connect(cleanTracker))

    -- shield our parts
    local function shieldPart(p)
        if p:IsA("BasePart") then assignGroup(p, MY_GROUP) end
    end
    reg(char.DescendantAdded:Connect(shieldPart))

    local function flagThreat()
        recentThreat = true
        task.delay(3, function() recentThreat = false end)
    end

    local function snapBack()
        local safe = safeMan:get()
        pcall(function()
            hrp.AssemblyLinearVelocity  = V3ZERO
            hrp.AssemblyAngularVelocity = V3ZERO
            hrp.CFrame = safe
        end)
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

    -- V2: enhanced force purge using whitelist
    local function purgeChar()
        for _, d in ipairs(char:GetDescendants()) do
            if DANGEROUS[d.ClassName] and not forceWL[d] then
                -- not whitelisted = wasn't here at spawn
                -- check if game might have added it legitimately
                -- game forces usually have specific parents (scripts etc)
                -- player forces are usually direct children of body parts
                local parent = d.Parent
                if parent and parent:IsA("BasePart")
                and parent:IsDescendantOf(char) then
                    -- force on our body part, not whitelisted = suspicious
                    kill(d)
                end
            end
        end
    end

    -- ═══════════════════════════════════════════
    -- STATE LOCKDOWN
    -- ═══════════════════════════════════════════
    pcall(function()
        hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
        hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
    end)
    reg(hum.StateChanged:Connect(function(_, s)
        if s == Enum.HumanoidStateType.Ragdoll
        or s == Enum.HumanoidStateType.FallingDown then
            hum:ChangeState(Enum.HumanoidStateType.GettingUp)
        end
    end))

    -- ═══════════════════════════════════════════
    -- PLATFORM-STAND GUARD (trip-friendly)
    -- ═══════════════════════════════════════════
    reg(hum:GetPropertyChangedSignal("PlatformStand"):Connect(function()
        if hum.PlatformStand then
            if recentThreat then
                hum.PlatformStand = false
                snapBack()
            else
                isTripping = true
                task.delay(5, function() isTripping = false end)
            end
        end
    end))

    -- ═══════════════════════════════════════════
    -- V13: HUMANOID PROPERTY MONITOR
    -- revert if someone changes our walkspeed/jump to 0
    -- but allow game-driven changes by updating baseline
    -- ═══════════════════════════════════════════
    local propLock = false
    
    local function monitorProp(propName, getOrig)
        reg(hum:GetPropertyChangedSignal(propName):Connect(function()
            if propLock then return end
            local val = hum[propName]
            local orig = getOrig()
            -- someone set it to 0 or negative = suspicious
            if val <= 0 and orig > 0 and recentThreat then
                propLock = true
                hum[propName] = orig
                propLock = false
            else
                -- game changed it legitimately, update baseline
                if propName == "WalkSpeed" then origWS = val
                elseif propName == "JumpPower" then origJP = val
                elseif propName == "JumpHeight" then origJH = val
                end
            end
        end))
    end
    
    monitorProp("WalkSpeed",  function() return origWS end)
    monitorProp("JumpPower",  function() return origJP end)
    monitorProp("JumpHeight", function() return origJH end)

    -- ═══════════════════════════════════════════
    -- V17: MASSLESS MONITOR
    -- ═══════════════════════════════════════════
    local function checkMassless()
        for _, p in ipairs(char:GetDescendants()) do
            if p:IsA("BasePart") and p.Massless then
                p.Massless = false
            end
        end
    end

    -- ═══════════════════════════════════════════
    -- FOREIGN FORCE / WELD / ATTACHMENT GUARD
    -- V2: uses whitelist
    -- V14: also catches foreign attachments
    -- ═══════════════════════════════════════════
    reg(char.DescendantAdded:Connect(function(obj)
        -- new body part = shield it
        if obj:IsA("BasePart") then
            assignGroup(obj, MY_GROUP)
            -- V17: prevent massless
            if obj.Massless then obj.Massless = false end
            return
        end

        -- force objects
        if DANGEROUS[obj.ClassName] then
            task.defer(function()
                pcall(function()
                    if forceWL[obj] then return end
                    -- if from other player = instant kill
                    if isFromOtherPlayer(obj) then obj:Destroy() return end
                    -- check references
                    for _, prop in ipairs({"Attachment0","Attachment1","Part0","Part1"}) do
                        local ok, val = pcall(function() return obj[prop] end)
                        if ok and val and typeof(val) == "Instance" then
                            if isFromOtherPlayer(val) then
                                obj:Destroy() return
                            end
                            -- V14: if attachment parent is from other player
                            if val:IsA("Attachment") and val.Parent then
                                if isFromOtherPlayer(val.Parent) then
                                    obj:Destroy() return
                                end
                            end
                        end
                    end
                    -- V2: not whitelisted + on our body part = suspicious
                    local parent = obj.Parent
                    if parent and parent:IsA("BasePart")
                    and parent:IsDescendantOf(char) then
                        -- give game 0.5s to claim it
                        task.delay(0.5, function()
                            pcall(function()
                                if obj.Parent and not forceWL[obj] then
                                    -- still here, still not whitelisted
                                    -- last check: does it have suspicious velocity target?
                                    obj:Destroy()
                                end
                            end)
                        end)
                    end
                end)
            end)
            return
        end

        -- V14: foreign attachments
        if obj:IsA("Attachment") then
            task.defer(function()
                pcall(function()
                    -- check if any constraint references this attachment
                    -- from outside our character
                    task.delay(0.2, function()
                        pcall(function()
                            if not obj.Parent then return end
                            -- look for constraints using this attachment
                            for _, d in ipairs(workspace:GetDescendants()) do
                                if d:IsA("Constraint") then
                                    local a0, a1 = d.Attachment0, d.Attachment1
                                    if (a0 == obj or a1 == obj) then
                                        local other = a0 == obj and a1 or a0
                                        if other and other.Parent
                                        and not other.Parent:IsDescendantOf(char) then
                                            obj:Destroy()
                                            d:Destroy()
                                            return
                                        end
                                    end
                                end
                            end
                        end)
                    end)
                end)
            end)
        end

        -- welds / constraints
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
                    if isFromOtherPlayer(foreign) then
                        obj:Destroy()
                    elseif not isInAnyCharacter(foreign)
                    and not foreign.Anchored then
                        -- connected to random unanchored part = suspicious
                        obj:Destroy()
                    end
                end)
            end)
        end
    end))

    -- ═══════════════════════════════════════════
    -- SEAT-FLING BLOCK (V16: includes vehicle seats)
    -- ═══════════════════════════════════════════
    reg(hum:GetPropertyChangedSignal("SeatPart"):Connect(function()
        local seat = hum.SeatPart
        if not seat then return end
        -- check if seat belongs to another player
        local isForeign = false
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LP and plr.Character
            and seat:IsDescendantOf(plr.Character) then
                isForeign = true
                break
            end
        end
        -- also check if seat is unanchored + spinning (fling seat)
        if not isForeign and not seat.Anchored then
            if seat.AssemblyAngularVelocity.Magnitude > 10
            or seat.AssemblyLinearVelocity.Magnitude > 50 then
                isForeign = true
            end
        end
        if isForeign then
            hum.Sit = false
            task.defer(function()
                if hrp.Parent then snapBack() end
            end)
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
    -- CONTACT SHIELD
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
            snapBack()
        end))
    end

    for _, p in ipairs(char:GetDescendants()) do hookTouch(p) end
    reg(char.DescendantAdded:Connect(function(p)
        shieldPart(p)
        hookTouch(p)
    end))

    -- ═══════════════════════════════════════════
    -- V9: CAMERA GUARD
    -- ═══════════════════════════════════════════
    local camera = workspace.CurrentCamera
    reg(RunService.RenderStepped:Connect(function()
        if camera.CameraSubject ~= hum then
            pcall(function() camera.CameraSubject = hum end)
        end
    end))

    -- ═══════════════════════════════════════════
    -- HEARTBEAT
    -- ═══════════════════════════════════════════
    reg(RunService.Heartbeat:Connect(function()
        if not char.Parent or not hrp.Parent then return end
        frame += 1
        local pos = hrp.Position
        local now = tick()

        -- teleport whitelist
        if lastPos and (pos - lastPos).Magnitude > CFG.TP_DIST then
            isTeleporting = true
            task.delay(0.6, function() isTeleporting = false end)
        end
        lastPos = pos
        if isTeleporting then
            safeMan:push(hrp.CFrame)
            flingCounter = 0
            return
        end

        -- ═══════════════════════════════════════
        -- VELOCITY DEVIATION DETECTION
        -- ═══════════════════════════════════════
        local ws = hum.WalkSpeed
        local jp = hum.JumpPower
        if jp == 0 then jp = hum.JumpHeight * 3 end

        local curLV  = hrp.AssemblyLinearVelocity
        local curAV  = hrp.AssemblyAngularVelocity
        local hVel   = math.sqrt(curLV.X * curLV.X + curLV.Z * curLV.Z)
        local vVel   = math.abs(curLV.Y)
        local angMag = curAV.Magnitude

        local maxH = math.max(ws * CFG.VEL_MULT, CFG.VEL_MIN)
        local maxV = math.max(jp * CFG.VERT_MULT, CFG.VERT_MIN)

        local state      = hum:GetState()
        local isSitting  = hum.Sit
        local isClimbing = state == Enum.HumanoidStateType.Climbing
        local isSwimming = state == Enum.HumanoidStateType.Swimming
        local isFalling  = state == Enum.HumanoidStateType.Freefall
        local isSeated   = state == Enum.HumanoidStateType.Seated
        local moveDir    = hum.MoveDirection

        local exempt = isTripping or isSitting or isSeated
            or isClimbing or isSwimming

        local flingDetected = false

        if not exempt then
            if angMag > CFG.ANG_MAX then
                flingDetected = true
            end

            if hVel > maxH then
                flingDetected = true
            end

            if isFalling then
                if vVel > math.max(maxV * 2, 200) then
                    flingDetected = true
                end
            else
                if vVel > maxV then
                    flingDetected = true
                end
            end
        end

        -- V1: MICRO-FLING CUMULATIVE TRACKING
        -- track unexpected displacement each frame
        if not exempt and not flingDetected then
            local expectedDir = moveDir * ws
            local actualHoriz = Vector3.new(curLV.X, 0, curLV.Z)
            local deviation = (actualHoriz - expectedDir).Magnitude

            -- only count deviation beyond walkspeed tolerance
            if deviation > ws * 1.5 then
                drift:add(deviation / 60) -- per frame to studs
            end

            if drift:getTotal() > CFG.DRIFT_MAX then
                flingDetected = true
                drift.samples = {}
            end
        end

        -- V10: DISPLACEMENT CHECK (animation fling)
        -- detect root part moving without velocity
        if not exempt and not flingDetected then
            local moved = (pos - (lastPos or pos)).Magnitude
            local expectedMove = ws / 60 * 2 -- generous per-frame allowance
            if moved > math.max(expectedMove * 5, 3) and hVel < ws * 0.5 then
                -- moved a lot but velocity is low = CFrame/animation manipulation
                flingDetected = true
            end
        end

        -- frame counter
        if flingDetected then
            flingCounter += 1
        else
            flingCounter = math.max(0, flingCounter - 1)
        end

        if flingCounter >= CFG.FLING_FRAMES then
            flagThreat()
            snapBack()
            flingCounter = 0
        end

        -- V4/V5: safe position management
        if flingCounter == 0
        and hum.FloorMaterial ~= Enum.Material.Air
        and not recentThreat
        and pos.Y >= CFG.MIN_SAFE_Y then
            safeMan:push(hrp.CFrame)
        end

        -- V4: validate we havent fallen below map
        if not safeMan:validate(pos.Y) and not isFalling then
            snapBack()
        end

        -- V7: network ownership check
        if frame % 10 == 0 then
            pcall(function()
                if hrp:GetNetworkOwner() ~= LP then
                    hrp:SetNetworkOwner(LP)
                end
            end)
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

        -- V11: nearby player AGGRESSIVE group enforcement
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

        -- force sweep + massless check
        if frame % CFG.FORCE_TICK == 0 then
            purgeChar()
            checkMassless()
        end

        lastMoveDir = moveDir
    end))
end

----------------------------------------------------------------
-- BOOTSTRAP
-- V8: pre-protection during spawn
----------------------------------------------------------------
protect(LP.Character)
LP.CharacterAdded:Connect(function(c)
    -- V8: immediately shield before full protection loads
    pcall(function()
        for _, p in ipairs(c:GetDescendants()) do
            if p:IsA("BasePart") then
                assignGroup(p, MY_GROUP)
            end
        end
    end)
    task.wait(0.2)
    protect(c)
end)

getgenv().WhitelistTP = function()
    isTeleporting = true
    task.delay(1, function() isTeleporting = false end)
end
