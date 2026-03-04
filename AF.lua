local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local LP         = Players.LocalPlayer

local isTeleporting = false
local conns        = {}

----------------------------------------------------------------
--  CONFIGURATION
----------------------------------------------------------------
local CFG = {
    -- velocity thresholds
    ANG_HARD    = 50,
    ANG_SOFT    = 30,
    LIN_MAX     = 180,
    VERT_MAX    = 250,
    FLING_MULT  = 2.2,

    -- teleport
    TP_DIST     = 80,

    -- proximity scanner (other players)
    THREAT_RADIUS = 25,
    THREAT_SPIN   = 30,

    -- RING / UNANCHORED PART DEFENSE
    RING_RADIUS   = 32,   -- spatial scan radius around you
    RING_SPIN     = 14,   -- angular vel that flags a part
    RING_SPEED    = 50,   -- linear  vel that flags a part
    TOUCH_CD      = 0.08, -- touched event cooldown (seconds)

    -- tick intervals (frames)
    COL_TICK    = 6,
    FORCE_TICK  = 15,
    BODY_TICK   = 8,
    PROX_TICK   = 12,
    RING_TICK   = 6,       -- spatial scan frequency
    ARMOR_TICK  = 120,

    -- physics armor
    DENSITY     = 30,
    FRICTION    = 2,
    ELASTICITY  = 0,
}

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

local heavyProps = PhysicalProperties.new(
    CFG.DENSITY, CFG.FRICTION, CFG.ELASTICITY, 1, 1
)

local function purgeForces(root)
    for _, d in ipairs(root:GetDescendants()) do
        if DANGEROUS[d.ClassName] then kill(d) end
    end
end

local function armorize(char)
    for _, p in ipairs(char:GetDescendants()) do
        if p:IsA("BasePart") then
            p.CustomPhysicalProperties = heavyProps
            p.Massless = false
        end
    end
end

-- Check if a part belongs to ANY player character
local function isCharacterPart(part)
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr.Character and part:IsDescendantOf(plr.Character) then
            return true
        end
    end
    return false
end

-- Neutralize a threatening unanchored part
local function neutralize(part)
    pcall(function()
        part.CanCollide         = false
        part.CanTouch           = false
        part.AssemblyLinearVelocity  = V3ZERO
        part.AssemblyAngularVelocity = V3ZERO
    end)
end

-- Check if a part is a ring/fling threat
local function isThreat(part)
    if not part:IsA("BasePart") then return false end
    if part.Anchored then return false end
    if part.AssemblyAngularVelocity.Magnitude > CFG.RING_SPIN then return true end
    if part.AssemblyLinearVelocity.Magnitude  > CFG.RING_SPEED then return true end
    return false
end

----------------------------------------------------------------
--  MAIN PROTECTION
----------------------------------------------------------------
local function protect(char)
    if not char then return end
    clearConns()

    local hrp = char:WaitForChild("HumanoidRootPart", 5)
    local hum = char:WaitForChild("Humanoid", 5)
    if not hrp or not hum then return end

    local safeCF  = hrp.CFrame
    local lastPos = hrp.Position
    local frame   = 0

    -- overlap params for spatial query (reused every scan)
    local ringParams = OverlapParams.new()
    ringParams.FilterType = Enum.RaycastFilterType.Exclude
    ringParams.FilterDescendantsInstances = {char}

    -- ═══════════════════════════════════════════
    -- LAYER 1 · PHYSICS ARMOR
    -- ═══════════════════════════════════════════
    armorize(char)

    -- ═══════════════════════════════════════════
    -- LAYER 2 · STATE LOCKDOWN
    -- ═══════════════════════════════════════════
    pcall(function()
        hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
        hum:SetStateEnabled(Enum.HumanoidStateType.Physics, false)
    end)
    reg(hum.StateChanged:Connect(function(_, s)
        if s == Enum.HumanoidStateType.Ragdoll
        or s == Enum.HumanoidStateType.Physics then
            hum:ChangeState(Enum.HumanoidStateType.GettingUp)
        end
    end))

    -- ═══════════════════════════════════════════
    -- LAYER 3 · PLATFORM-STAND GUARD
    -- ═══════════════════════════════════════════
    reg(hum:GetPropertyChangedSignal("PlatformStand"):Connect(function()
        if hum.PlatformStand then hum.PlatformStand = false end
    end))

    -- ═══════════════════════════════════════════
    -- LAYER 4 · COLLISION SHIELD (player characters)
    -- ═══════════════════════════════════════════
    local function ncPart(p)
        if p:IsA("BasePart") then p.CanCollide = false end
    end
    local function ncChar(c)
        if not c then return end
        for _, p in ipairs(c:GetDescendants()) do ncPart(p) end
        reg(c.DescendantAdded:Connect(ncPart))
    end
    local function watchPlr(plr)
        if plr == LP then return end
        if plr.Character then ncChar(plr.Character) end
        reg(plr.CharacterAdded:Connect(function(c)
            task.wait(0.1) ncChar(c)
        end))
    end
    for _, p in ipairs(Players:GetPlayers()) do watchPlr(p) end
    reg(Players.PlayerAdded:Connect(watchPlr))

    -- ═══════════════════════════════════════════
    -- LAYER 5 · FORCE ANNIHILATOR + WELD GUARD
    -- ═══════════════════════════════════════════
    purgeForces(char)

    reg(char.DescendantAdded:Connect(function(obj)
        if obj:IsA("BasePart") then
            task.defer(function()
                pcall(function()
                    obj.CustomPhysicalProperties = heavyProps
                    obj.Massless = false
                end)
            end)
        end

        if DANGEROUS[obj.ClassName] then
            task.defer(function() kill(obj) end)
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
                    for _, plr in ipairs(Players:GetPlayers()) do
                        if plr ~= LP and plr.Character
                        and foreign:IsDescendantOf(plr.Character) then
                            obj:Destroy()
                            return
                        end
                    end
                end)
            end)
        end
    end))

    -- ═══════════════════════════════════════════
    -- LAYER 6 · SEAT-FLING BLOCK
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
    -- LAYER 7 · PRE-PHYSICS INTERCEPT (Stepped)
    -- ═══════════════════════════════════════════
    reg(RunService.Stepped:Connect(function()
        if not char.Parent or not hrp.Parent or isTeleporting then return end
        if hrp.AssemblyAngularVelocity.Magnitude > CFG.ANG_HARD then
            hrp.AssemblyAngularVelocity = V3ZERO
        end
        local lv = hrp.AssemblyLinearVelocity
        if math.sqrt(lv.X * lv.X + lv.Z * lv.Z) > CFG.LIN_MAX * CFG.FLING_MULT
        or math.abs(lv.Y) > CFG.VERT_MAX * CFG.FLING_MULT then
            hrp.AssemblyLinearVelocity = V3ZERO
        end
    end))

    -- ═══════════════════════════════════════════
    -- LAYER 11b · RING INTERCEPTOR
    -- catches ring parts the INSTANT they spawn
    -- anywhere in workspace, any depth
    -- ═══════════════════════════════════════════
    reg(workspace.DescendantAdded:Connect(function(obj)
        if not obj:IsA("BasePart") or obj.Anchored then return end
        if obj:IsDescendantOf(char) then return end

        -- check immediately + again after brief delay
        -- (some ring scripts set velocity a frame after spawn)
        task.defer(function()
            pcall(function()
                if not obj.Parent then return end
                if isThreat(obj) and not isCharacterPart(obj) then
                    neutralize(obj)
                end
            end)
        end)
        task.delay(0.15, function()
            pcall(function()
                if not obj.Parent then return end
                if isThreat(obj) and not isCharacterPart(obj) then
                    neutralize(obj)
                end
            end)
        end)
    end))

    -- ═══════════════════════════════════════════
    -- LAYER 11c · CONTACT SHIELD (Touched)
    -- last resort — if a ring part reaches you
    -- debounced per body-part to prevent lag
    -- ═══════════════════════════════════════════
    local touchCD = {}

    local function hookTouch(part)
        if not part:IsA("BasePart") then return end
        reg(part.Touched:Connect(function(hit)
            if touchCD[part] then return end
            if not hit or hit.Anchored then return end
            if hit:IsDescendantOf(char) then return end

            -- is the thing that touched us dangerous?
            local av = hit.AssemblyAngularVelocity.Magnitude
            local lv = hit.AssemblyLinearVelocity.Magnitude
            if av < CFG.RING_SPIN and lv < CFG.RING_SPEED then return end

            touchCD[part] = true
            task.delay(CFG.TOUCH_CD, function() touchCD[part] = nil end)

            -- neutralize the threat
            neutralize(hit)

            -- protect ourselves immediately
            pcall(function()
                hrp.AssemblyLinearVelocity  = V3ZERO
                hrp.AssemblyAngularVelocity = V3ZERO
            end)
        end))
    end

    for _, p in ipairs(char:GetDescendants()) do hookTouch(p) end
    reg(char.DescendantAdded:Connect(hookTouch))

    -- ═══════════════════════════════════════════
    -- LAYERS 8-12 · HEARTBEAT FORTRESS
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

        local av = hrp.AssemblyAngularVelocity
        local lv = hrp.AssemblyLinearVelocity
        local am = av.Magnitude
        local flung = false

        -- LAYER 8a · SPIN FLING
        if am > CFG.ANG_HARD then
            hrp.AssemblyAngularVelocity = V3ZERO
            hrp.AssemblyLinearVelocity  = V3ZERO
            hrp.CFrame = safeCF
            flung = true
        elseif am > CFG.ANG_SOFT then
            hrp.AssemblyAngularVelocity = av.Unit * CFG.ANG_SOFT
        end

        -- LAYER 8b · LINEAR FLING
        if not flung then
            local hSpd = math.sqrt(lv.X * lv.X + lv.Z * lv.Z)
            local vSpd = math.abs(lv.Y)
            if hSpd > CFG.LIN_MAX * CFG.FLING_MULT
            or vSpd > CFG.VERT_MAX * CFG.FLING_MULT then
                hrp.AssemblyLinearVelocity  = V3ZERO
                hrp.AssemblyAngularVelocity = V3ZERO
                hrp.CFrame = safeCF
                flung = true
            elseif hSpd > CFG.LIN_MAX or vSpd > CFG.VERT_MAX then
                hrp.AssemblyLinearVelocity = Vector3.new(
                    math.clamp(lv.X, -CFG.LIN_MAX,  CFG.LIN_MAX),
                    math.clamp(lv.Y, -CFG.VERT_MAX, CFG.VERT_MAX),
                    math.clamp(lv.Z, -CFG.LIN_MAX,  CFG.LIN_MAX)
                )
            end
        end

        -- LAYER 9 · BODY-PARTS PATROL
        if frame % CFG.BODY_TICK == 0 then
            for _, part in ipairs(char:GetChildren()) do
                if part:IsA("BasePart") and part ~= hrp then
                    if part.AssemblyAngularVelocity.Magnitude > CFG.ANG_HARD then
                        part.AssemblyAngularVelocity = V3ZERO
                    end
                    if part.AssemblyLinearVelocity.Magnitude > CFG.LIN_MAX * CFG.FLING_MULT then
                        part.AssemblyLinearVelocity = V3ZERO
                    end
                end
            end
        end

        -- LAYER 10 · PROXIMITY THREAT SCANNER (players)
        if frame % CFG.PROX_TICK == 0 then
            for _, plr in ipairs(Players:GetPlayers()) do
                if plr ~= LP and plr.Character then
                    local pH = plr.Character:FindFirstChild("HumanoidRootPart")
                    if pH and (pH.Position - pos).Magnitude < CFG.THREAT_RADIUS then
                        if pH.AssemblyAngularVelocity.Magnitude > CFG.THREAT_SPIN
                        or pH.AssemblyLinearVelocity.Magnitude  > CFG.LIN_MAX then
                            for _, p in ipairs(plr.Character:GetDescendants()) do
                                if p:IsA("BasePart") then
                                    p.CanCollide = false
                                    p.CanTouch   = false
                                end
                            end
                        end
                    end
                end
            end
        end

        -- ═══════════════════════════════════════
        -- LAYER 11a · RING RADAR (spatial query)
        -- finds ALL unanchored threats near you
        -- regardless of workspace hierarchy depth
        -- ═══════════════════════════════════════
        if frame % CFG.RING_TICK == 0 then
            local ok, nearby = pcall(function()
                return workspace:GetPartBoundsInRadius(pos, CFG.RING_RADIUS, ringParams)
            end)
            if ok and nearby then
                for _, part in ipairs(nearby) do
                    if not part.Anchored
                    and not part:IsDescendantOf(char) then
                        local av2 = part.AssemblyAngularVelocity.Magnitude
                        local lv2 = part.AssemblyLinearVelocity.Magnitude
                        if av2 > CFG.RING_SPIN or lv2 > CFG.RING_SPEED then
                            neutralize(part)
                        end
                    end
                end
            end
        end

        -- LAYER 12 · SAFE POSITION UPDATE
        if not flung and hum.FloorMaterial ~= Enum.Material.Air then
            safeCF = hrp.CFrame
        end

        -- periodic maintenance
        if frame % CFG.COL_TICK == 0 then
            for _, plr in ipairs(Players:GetPlayers()) do
                if plr ~= LP and plr.Character then
                    for _, p in ipairs(plr.Character:GetDescendants()) do
                        if p:IsA("BasePart") then p.CanCollide = false end
                    end
                end
            end
        end
        if frame % CFG.FORCE_TICK == 0 then purgeForces(char) end
        if frame % CFG.ARMOR_TICK == 0 then armorize(char) end
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
