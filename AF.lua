local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local LP         = Players.LocalPlayer

local conns  = {}
local V3ZERO = Vector3.zero

local ringParts = setmetatable({}, {__mode = "k"})

local SPIN_KILL = 50
local RING_ANG  = 20
local RING_LIN  = 50
local TOUCH_ANG = 12

local DANGEROUS = {}
for _, cn in ipairs({
    "BodyVelocity","BodyAngularVelocity","BodyForce","BodyPosition",
    "BodyGyro","BodyThrust","RocketPropulsion",
    "Torque","VectorForce","LinearVelocity","AlignPosition",
    "AlignOrientation","AngularVelocity",
}) do DANGEROUS[cn] = true end

local function clearConns()
    for i = #conns, 1, -1 do
        pcall(function() conns[i]:Disconnect() end)
        conns[i] = nil
    end
end
local function reg(c) conns[#conns + 1] = c return c end

local function isCharPart(part)
    local model = part:FindFirstAncestorWhichIsA("Model")
    return model and model:FindFirstChildOfClass("Humanoid") ~= nil
end

local function markRing(part)
    if not part or not part.Parent then return end
    if not part:IsA("BasePart") or part.Anchored then return end
    if isCharPart(part) then return end

    local av = part.AssemblyAngularVelocity.Magnitude
    local lv = part.AssemblyLinearVelocity.Magnitude

    if (av > RING_ANG and lv > RING_LIN) or av > RING_ANG * 3 then
        ringParts[part] = true
        pcall(function()
            local par = part.Parent
            if par and par ~= workspace and par ~= game then
                for _, sib in ipairs(par:GetChildren()) do
                    if sib:IsA("BasePart") and not sib.Anchored then
                        ringParts[sib] = true
                    end
                end
            end
        end)
    end
end

local function protect(char)
    if not char then return end
    clearConns()
    ringParts = setmetatable({}, {__mode = "k"})

    local hrp = char:WaitForChild("HumanoidRootPart", 5)
    local hum = char:WaitForChild("Humanoid", 5)
    if not hrp or not hum then return end

    -- ═══════════════════════════════════════
    -- ANTI-RAGDOLL (only ragdoll blocked)
    -- trip, falling, platformstand all untouched
    -- ═══════════════════════════════════════
    pcall(function()
        hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
    end)
    reg(hum.StateChanged:Connect(function(_, s)
        if s == Enum.HumanoidStateType.Ragdoll then
            hum:ChangeState(Enum.HumanoidStateType.GettingUp)
        end
    end))

    -- ═══════════════════════════════════════
    -- FORCE / WELD GUARD (event-driven only)
    -- ═══════════════════════════════════════
    reg(char.DescendantAdded:Connect(function(obj)
        if DANGEROUS[obj.ClassName] then
            task.defer(function()
                pcall(function()
                    if not obj.Parent then return end
                    for _, plr in ipairs(Players:GetPlayers()) do
                        if plr ~= LP and plr.Character then
                            if obj:IsDescendantOf(plr.Character) then
                                obj:Destroy()
                                return
                            end
                            for _, prop in ipairs({"Attachment0","Attachment1","Part0","Part1"}) do
                                local ok, val = pcall(function() return obj[prop] end)
                                if ok and val and typeof(val) == "Instance"
                                and val:IsDescendantOf(plr.Character) then
                                    obj:Destroy()
                                    return
                                end
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
                    if not obj.Parent then return end
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

    -- ═══════════════════════════════════════
    -- SEAT FLING BLOCK
    -- ═══════════════════════════════════════
    reg(hum:GetPropertyChangedSignal("SeatPart"):Connect(function()
        local seat = hum.SeatPart
        if not seat then return end
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LP and plr.Character
            and seat:IsDescendantOf(plr.Character) then
                hum.Sit = false
                return
            end
        end
        if not seat.Anchored then
            if seat.AssemblyAngularVelocity.Magnitude > 10
            or seat.AssemblyLinearVelocity.Magnitude > 50 then
                hum.Sit = false
            end
        end
    end))

    -- ═══════════════════════════════════════
    -- RING INTERCEPTOR (event-driven)
    -- ═══════════════════════════════════════
    reg(workspace.DescendantAdded:Connect(function(obj)
        if not obj:IsA("BasePart") or obj.Anchored then return end
        if obj:IsDescendantOf(char) then return end
        if isCharPart(obj) then return end

        local function check()
            pcall(function()
                if obj.Parent then markRing(obj) end
            end)
        end
        task.defer(check)
        task.delay(0.2, check)
        task.delay(0.5, check)
    end))

    -- ═══════════════════════════════════════
    -- CONTACT SHIELD
    -- if spinning part touches us, cache it
    -- lower threshold since its already on us
    -- ═══════════════════════════════════════
    local touchCD = {}

    local function hookTouch(bp)
        if not bp:IsA("BasePart") then return end
        reg(bp.Touched:Connect(function(hit)
            if touchCD[bp] then return end
            if not hit or not hit.Parent then return end
            if hit:IsDescendantOf(char) or hit.Anchored then return end
            if isCharPart(hit) then return end

            if hit.AssemblyAngularVelocity.Magnitude > TOUCH_ANG then
                touchCD[bp] = true
                task.delay(0.1, function() touchCD[bp] = nil end)

                ringParts[hit] = true
                pcall(function()
                    local par = hit.Parent
                    if par and par ~= workspace then
                        for _, sib in ipairs(par:GetChildren()) do
                            if sib:IsA("BasePart") and not sib.Anchored then
                                ringParts[sib] = true
                            end
                        end
                    end
                end)

                hrp.AssemblyAngularVelocity = V3ZERO
            end
        end))
    end

    for _, p in ipairs(char:GetDescendants()) do hookTouch(p) end
    reg(char.DescendantAdded:Connect(hookTouch))

    -- ═══════════════════════════════════════
    -- INITIAL SCAN (runs once in background)
    -- catches ring parts already in workspace
    -- ═══════════════════════════════════════
    task.spawn(function()
        for _, obj in ipairs(workspace:GetDescendants()) do
            if obj:IsA("BasePart") and not obj.Anchored
            and not obj:IsDescendantOf(char)
            and not isCharPart(obj) then
                markRing(obj)
            end
        end
    end)

    -- ═══════════════════════════════════════
    -- STEPPED — PRE-PHYSICS
    --
    -- this is the ENTIRE anti-fling engine
    -- runs BEFORE physics calculates collisions
    -- CanCollide = false set here is used by
    -- the physics engine for that step
    -- network owner cannot override in time
    -- because Stepped and physics run on same thread
    --
    -- timeline each frame:
    --   1. network updates arrive (CanCollide reset to true)
    --   2. Stepped fires
    --   3. we set CanCollide = false
    --   4. physics simulation runs (sees our false)
    --   5. no collision calculated
    --   6. no force transferred
    --   7. you dont move
    --
    -- thats it. pure immunity. no teleporting.
    -- no velocity clamping. no position tracking.
    -- ═══════════════════════════════════════
    reg(RunService.Stepped:Connect(function()
        if not char.Parent or not hrp.Parent then return end

        -- kill extreme spin (only thing touched on you)
        if hrp.AssemblyAngularVelocity.Magnitude > SPIN_KILL then
            hrp.AssemblyAngularVelocity = V3ZERO
        end

        local myPos = hrp.Position

        -- player no-collide (only nearby, < 60 studs)
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LP and plr.Character then
                local pH = plr.Character:FindFirstChild("HumanoidRootPart")
                if pH and (pH.Position - myPos).Magnitude < 60 then
                    for _, p in ipairs(plr.Character:GetChildren()) do
                        if p:IsA("BasePart") then
                            p.CanCollide = false
                        elseif p:IsA("Accessory") or p:IsA("Tool") then
                            local h = p:FindFirstChildWhichIsA("BasePart")
                            if h then h.CanCollide = false end
                        end
                    end
                end
            end
        end

        -- ring no-collide
        for part in pairs(ringParts) do
            if part.Parent then
                part.CanCollide = false
                part.CanTouch   = false
            end
        end
    end))
end

protect(LP.Character)
LP.CharacterAdded:Connect(function(c)
    task.wait(0.2)
    protect(c)
end)
