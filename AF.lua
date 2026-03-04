local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local LP         = Players.LocalPlayer

local isTeleporting = false
local conns        = {}

----------------------------------------------------------------
--  CONFIGURATION
----------------------------------------------------------------
local CFG = {
    TP_DIST        = 80,
    RING_RADIUS    = 45,
    RING_SPIN      = 5,
    RING_SPEED     = 20,
    THREAT_RADIUS  = 30,
    THREAT_SPIN    = 15,
    THREAT_SPEED   = 80,
    COL_TICK       = 5,
    FORCE_TICK     = 15,
    PROX_TICK      = 10,
    RING_TICK      = 3,
    SHIELD_TICK    = 2,
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
local V3ZERO   = Vector3.zero
local HUGE_CF  = CFrame.new(0, 10000, 0)

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
-- COLLISION GROUP SETUP
-- This is the nuclear option against ring parts.
-- Your character gets its own collision group that
-- CANNOT collide with unanchored non-character parts.
----------------------------------------------------------------
local PhysicsService = game:GetService("PhysicsService")

local MY_GROUP   = "AntiFling_Me"
local RING_GROUP = "AntiFling_Rings"

local function setupCollisionGroups()
    pcall(function() PhysicsService:RegisterCollisionGroup(MY_GROUP) end)
    pcall(function() PhysicsService:RegisterCollisionGroup(RING_GROUP) end)
    pcall(function()
        PhysicsService:CollisionGroupSetCollidable(MY_GROUP, RING_GROUP, false)
    end)
end

setupCollisionGroups()

local function assignGroup(part, group)
    pcall(function() part.CollisionGroup = group end)
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

    local safeCF      = hrp.CFrame
    local lastPos     = hrp.Position
    local frame       = 0
    local recentThreat = false

    local ringParams = OverlapParams.new()
    ringParams.FilterType = Enum.RaycastFilterType.Exclude
    ringParams.FilterDescendantsInstances = {char}

    -- assign all our parts to our collision group
    local function shieldPart(p)
        if p:IsA("BasePart") then
            assignGroup(p, MY_GROUP)
        end
    end
    for _, p in ipairs(char:GetDescendants()) do shieldPart(p) end
    reg(char.DescendantAdded:Connect(shieldPart))

    local function flagThreat()
        recentThreat = true
        task.delay(3, function() recentThreat = false end)
    end

    -- try to neutralize (may be overridden by network owner)
    local function tryNeutralize(part)
        pcall(function()
            assignGroup(part, RING_GROUP)
            part.CanCollide              = false
            part.CanTouch                = false
            part.AssemblyLinearVelocity  = V3ZERO
            part.AssemblyAngularVelocity = V3ZERO
        end)
    end

    local function isThreat(part)
        if not part:IsA("BasePart") or part.Anchored then return false end
        if isInAnyCharacter(part) then return false end
        local av = part.AssemblyAngularVelocity.Magnitude
        local lv = part.AssemblyLinearVelocity.Magnitude
        return av > CFG.RING_SPIN or lv > CFG.RING_SPEED
    end

    local function nukeFamily(part)
        pcall(function()
            local parent = part.Parent
            if parent and parent ~= workspace then
                for _, sib in ipairs(parent:GetChildren()) do
                    if sib:IsA("BasePart") and not sib.Anchored then
                        tryNeutralize(sib)
                    end
                end
            end
        end)
        tryNeutralize(part)
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
    -- LAYER 3 · PLAYER COLLISION SHIELD
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
    -- LAYER 4 · FOREIGN FORCE / WELD GUARD
    -- ═══════════════════════════════════════════
    reg(char.DescendantAdded:Connect(function(obj)
        if DANGEROUS[obj.ClassName] then
            task.defer(function()
                pcall(function()
                    if isFromOtherPlayer(obj) then obj:Destroy() return end
                    for _, prop in ipairs({"Attachment0","Attachment1","Part0","Part1"}) do
                        local ok, val = pcall(function() return obj[prop] end)
                        if ok and val and typeof(val) == "Instance" then
                            if isFromOtherPlayer(val) then
                                obj:Destroy() return
                            end
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
    -- LAYER 5 · SEAT-FLING BLOCK
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
    -- LAYER 6 · RING INTERCEPTOR (spawn catch)
    -- ═══════════════════════════════════════════
    reg(workspace.DescendantAdded:Connect(function(obj)
        if not obj:IsA("BasePart") then return end
        if obj:IsDescendantOf(char) then return end

        -- immediately assign to ring group if unanchored
        if not obj.Anchored and not isInAnyCharacter(obj) then
            assignGroup(obj, RING_GROUP)
        end

        task.defer(function()
            pcall(function()
                if obj.Parent and isThreat(obj) then
                    flagThreat()
                    nukeFamily(obj)
                end
            end)
        end)
        task.delay(0.1, function()
            pcall(function()
                if obj.Parent and isThreat(obj) then
                    flagThreat()
                    nukeFamily(obj)
                end
            end)
        end)
        task.delay(0.3, function()
            pcall(function()
                if obj.Parent and isThreat(obj) then
                    flagThreat()
                    nukeFamily(obj)
                end
            end)
        end)
    end))

    -- ═══════════════════════════════════════════
    -- LAYER 7 · CONTACT SHIELD (Touched)
    -- ═══════════════════════════════════════════
    local touchCD = {}

    local function hookTouch(bodyPart)
        if not bodyPart:IsA("BasePart") then return end
        reg(bodyPart.Touched:Connect(function(hit)
            if touchCD[bodyPart] then return end
            if not hit or not hit.Parent then return end
            if hit:IsDescendantOf(char) then return end
            if hit.Anchored then return end
            if isInAnyCharacter(hit) then return end

            local av = hit.AssemblyAngularVelocity.Magnitude
            local lv = hit.AssemblyLinearVelocity.Magnitude
            if av < 3 and lv < 15 then return end

            touchCD[bodyPart] = true
            task.delay(0.05, function() touchCD[bodyPart] = nil end)

            flagThreat()
            nukeFamily(hit)

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

        if lastPos and (pos - lastPos).Magnitude > CFG.TP_DIST then
            isTeleporting = true
            task.delay(0.6, function() isTeleporting = false end)
        end
        lastPos = pos
        if isTeleporting then safeCF = hrp.CFrame return end

        if hum.FloorMaterial ~= Enum.Material.Air then
            safeCF = hrp.CFrame
        end

        -- CONTINUOUS COLLISION GROUP ENFORCEMENT
        -- even if network owner resets properties,
        -- your parts stay in your group
        if frame % CFG.SHIELD_TICK == 0 then
            for _, p in ipairs(char:GetDescendants()) do
                if p:IsA("BasePart") then
                    assignGroup(p, MY_GROUP)
                end
            end
        end

        -- RING RADAR + COLLISION GROUP ASSIGNMENT
        if frame % CFG.RING_TICK == 0 then
            local ok, nearby = pcall(function()
                return workspace:GetPartBoundsInRadius(
                    pos, CFG.RING_RADIUS, ringParams
                )
            end)
            if ok and nearby then
                for _, part in ipairs(nearby) do
                    if not part.Anchored
                    and not isInAnyCharacter(part) then
                        -- always assign to ring group
                        assignGroup(part, RING_GROUP)

                        if isThreat(part) then
                            flagThreat()
                            nukeFamily(part)
                        end
                    end
                end
            end
        end

        -- POST-FLING RECOVERY
        if recentThreat then
            local av = hrp.AssemblyAngularVelocity
            local lv = hrp.AssemblyLinearVelocity
            if av.Magnitude > 20 then
                hrp.AssemblyAngularVelocity = V3ZERO
            end
            if lv.Magnitude > 200 then
                hrp.AssemblyLinearVelocity  = V3ZERO
                hrp.AssemblyAngularVelocity = V3ZERO
                hrp.CFrame = safeCF
            end
        end

        -- PROXIMITY SCANNER
        if frame % CFG.PROX_TICK == 0 then
            for _, plr in ipairs(Players:GetPlayers()) do
                if plr ~= LP and plr.Character then
                    local pH = plr.Character:FindFirstChild("HumanoidRootPart")
                    if pH and (pH.Position - pos).Magnitude < CFG.THREAT_RADIUS then
                        if pH.AssemblyAngularVelocity.Magnitude > CFG.THREAT_SPIN
                        or pH.AssemblyLinearVelocity.Magnitude > CFG.THREAT_SPEED then
                            flagThreat()
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

        -- COLLISION REFRESH
        if frame % CFG.COL_TICK == 0 then
            for _, plr in ipairs(Players:GetPlayers()) do
                if plr ~= LP and plr.Character then
                    for _, p in ipairs(plr.Character:GetDescendants()) do
                        if p:IsA("BasePart") then p.CanCollide = false end
                    end
                end
            end
        end

        -- FORCE SWEEP
        if frame % CFG.FORCE_TICK == 0 then
            for _, d in ipairs(char:GetDescendants()) do
                if DANGEROUS[d.ClassName] then
                    pcall(function()
                        for _, prop in ipairs({"Attachment0","Attachment1","Part0","Part1"}) do
                            local ok2, val = pcall(function() return d[prop] end)
                            if ok2 and val and typeof(val) == "Instance" then
                                if isFromOtherPlayer(val) then
                                    kill(d) return
                                end
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
