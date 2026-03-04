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

    RING_RADIUS    = 32,
    RING_SPIN      = 14,
    RING_SPEED     = 50,
    TOUCH_CD       = 0.08,

    THREAT_RADIUS  = 25,
    THREAT_SPIN    = 30,
    THREAT_SPEED   = 150,

    COL_TICK       = 6,
    FORCE_TICK     = 15,
    PROX_TICK      = 12,
    RING_TICK      = 6,
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

local function purgeForces(root)
    for _, d in ipairs(root:GetDescendants()) do
        if DANGEROUS[d.ClassName] then
            -- only destroy if it came from another player
            local owner = d:FindFirstAncestorWhichIsA("Model")
            if owner then
                for _, plr in ipairs(Players:GetPlayers()) do
                    if plr ~= LP and plr.Character == owner then
                        kill(d)
                        break
                    end
                end
            end
        end
    end
end

local function isFromOtherPlayer(obj)
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LP and plr.Character
        and obj:IsDescendantOf(plr.Character) then
            return true
        end
    end
    return false
end

local function isCharacterPart(part)
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr.Character and part:IsDescendantOf(plr.Character) then
            return true
        end
    end
    return false
end

local function neutralize(part)
    pcall(function()
        part.CanCollide              = false
        part.CanTouch                = false
        part.AssemblyLinearVelocity  = V3ZERO
        part.AssemblyAngularVelocity = V3ZERO
    end)
end

local function isThreat(part)
    if not part:IsA("BasePart") or part.Anchored then return false end
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

    local ringParams = OverlapParams.new()
    ringParams.FilterType = Enum.RaycastFilterType.Exclude
    ringParams.FilterDescendantsInstances = {char}

    -- ═══════════════════════════════════════════
    -- LAYER 1 · ANTI-RAGDOLL
    -- only blocks ragdoll caused by other players
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
    -- LAYER 2 · PLATFORM-STAND GUARD (trip-friendly)
    -- only blocks if suspicious velocity present
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
    -- LAYER 3 · COLLISION SHIELD (other players only)
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
    -- only destroys things from other players
    -- game-made forces are left alone
    -- ═══════════════════════════════════════════
    reg(char.DescendantAdded:Connect(function(obj)
        if DANGEROUS[obj.ClassName] then
            task.defer(function()
                pcall(function()
                    -- check if this force connects to another player
                    local parent = obj.Parent
                    if not parent then return end

                    -- if the force object itself references another player
                    if isFromOtherPlayer(obj) then
                        obj:Destroy()
                        return
                    end

                    -- check if any attachment/part links to another player
                    for _, prop in ipairs({"Attachment0","Attachment1","Part0","Part1"}) do
                        local ok, val = pcall(function() return obj[prop] end)
                        if ok and val and typeof(val) == "Instance" then
                            if isFromOtherPlayer(val) then
                                obj:Destroy()
                                return
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
                    if isFromOtherPlayer(foreign) then
                        obj:Destroy()
                    end
                end)
            end)
        end
    end))

    -- ═══════════════════════════════════════════
    -- LAYER 5 · SEAT-FLING BLOCK
    -- only blocks seats owned by other players
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
    -- LAYER 6 · RING INTERCEPTOR
    -- ═══════════════════════════════════════════
    reg(workspace.DescendantAdded:Connect(function(obj)
        if not obj:IsA("BasePart") or obj.Anchored then return end
        if obj:IsDescendantOf(char) then return end
        task.defer(function()
            pcall(function()
                if obj.Parent and isThreat(obj) and not isCharacterPart(obj) then
                    neutralize(obj)
                end
            end)
        end)
        task.delay(0.15, function()
            pcall(function()
                if obj.Parent and isThreat(obj) and not isCharacterPart(obj) then
                    neutralize(obj)
                end
            end)
        end)
    end))

    -- ═══════════════════════════════════════════
    -- LAYER 7 · CONTACT SHIELD
    -- ═══════════════════════════════════════════
    local touchCD = {}

    local function hookTouch(part)
        if not part:IsA("BasePart") then return end
        reg(part.Touched:Connect(function(hit)
            if touchCD[part] then return end
            if not hit or hit.Anchored then return end
            if hit:IsDescendantOf(char) then return end
            if hit.AssemblyAngularVelocity.Magnitude < CFG.RING_SPIN
            and hit.AssemblyLinearVelocity.Magnitude < CFG.RING_SPEED then
                return
            end
            -- only react to non-game parts
            if isCharacterPart(hit) or not isThreat(hit) then return end
            touchCD[part] = true
            task.delay(CFG.TOUCH_CD, function() touchCD[part] = nil end)
            neutralize(hit)
        end))
    end

    for _, p in ipairs(char:GetDescendants()) do hookTouch(p) end
    reg(char.DescendantAdded:Connect(hookTouch))

    -- ═══════════════════════════════════════════
    -- HEARTBEAT — LIGHTWEIGHT MONITORING
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

        -- safe position (grounded)
        if hum.FloorMaterial ~= Enum.Material.Air then
            safeCF = hrp.CFrame
        end

        -- RING RADAR
        if frame % CFG.RING_TICK == 0 then
            local ok, nearby = pcall(function()
                return workspace:GetPartBoundsInRadius(
                    pos, CFG.RING_RADIUS, ringParams
                )
            end)
            if ok and nearby then
                for _, part in ipairs(nearby) do
                    if not part.Anchored
                    and not part:IsDescendantOf(char)
                    and isThreat(part) then
                        neutralize(part)
                    end
                end
            end
        end

        -- PROXIMITY SCANNER (spinning players)
        if frame % CFG.PROX_TICK == 0 then
            for _, plr in ipairs(Players:GetPlayers()) do
                if plr ~= LP and plr.Character then
                    local pH = plr.Character:FindFirstChild("HumanoidRootPart")
                    if pH and (pH.Position - pos).Magnitude < CFG.THREAT_RADIUS then
                        if pH.AssemblyAngularVelocity.Magnitude > CFG.THREAT_SPIN
                        or pH.AssemblyLinearVelocity.Magnitude > CFG.THREAT_SPEED then
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

        -- FORCE SWEEP (only foreign)
        if frame % CFG.FORCE_TICK == 0 then
            for _, d in ipairs(char:GetDescendants()) do
                if DANGEROUS[d.ClassName] then
                    pcall(function()
                        for _, prop in ipairs({"Attachment0","Attachment1","Part0","Part1"}) do
                            local ok2, val = pcall(function() return d[prop] end)
                            if ok2 and val and typeof(val) == "Instance" then
                                if isFromOtherPlayer(val) then
                                    kill(d)
                                    return
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
