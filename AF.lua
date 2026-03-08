local Players      = game:GetService("Players")
local RunService   = game:GetService("RunService")
local LP           = Players.LocalPlayer

local conns        = {}
local V3ZERO       = Vector3.zero
local SPIN_THRESH  = 40
local SCAN_RADIUS  = 20
local FLICKER_DIST = 8

local otherPlayerPos = {}
local trackedPlayers = {}

local function clearConns()
    for i = #conns, 1, -1 do
        pcall(function() conns[i]:Disconnect() end)
        conns[i] = nil
    end
end
local function reg(c) conns[#conns + 1] = c return c end

local function disableCollision(part)
    if part:IsA("BasePart") then
        pcall(function()
            part.CanCollide = false
            part.CanTouch = false
        end)
    end
end

local function trackCharacter(character)
    if not character then return end
    for _, p in ipairs(character:GetDescendants()) do
        disableCollision(p)
    end
    character.DescendantAdded:Connect(function(p)
        task.defer(function() disableCollision(p) end)
    end)
end

local function trackPlayer(plr)
    if plr == LP then return end
    if trackedPlayers[plr] then return end
    trackedPlayers[plr] = true
    if plr.Character then trackCharacter(plr.Character) end
    plr.CharacterAdded:Connect(function(c)
        task.wait(0.1)
        trackCharacter(c)
    end)
end

for _, plr in ipairs(Players:GetPlayers()) do trackPlayer(plr) end
Players.PlayerAdded:Connect(trackPlayer)

-- continuous enforce on RenderStepped (catches network-owned re-enables)
RunService.RenderStepped:Connect(function()
    for plr in pairs(trackedPlayers) do
        local character = plr.Character
        if character then
            for _, p in ipairs(character:GetDescendants()) do
                if p:IsA("BasePart") and p.CanCollide then
                    p.CanCollide = false
                end
            end
        end
    end
end)

local DANGEROUS = {}
for _, cn in ipairs({
    "BodyVelocity","BodyAngularVelocity","BodyForce",
    "BodyPosition","BodyGyro","BodyThrust","RocketPropulsion",
    "Torque","VectorForce","LinearVelocity","AlignPosition",
    "AlignOrientation","AngularVelocity",
}) do DANGEROUS[cn] = true end

local function protect(char)
    if not char then return end
    clearConns()
    otherPlayerPos = {}

    local hrp = char:WaitForChild("HumanoidRootPart", 5)
    local hum = char:WaitForChild("Humanoid", 5)
    if not hrp or not hum then return end

    local overlapParams = OverlapParams.new()
    overlapParams.FilterType = Enum.RaycastFilterType.Exclude
    overlapParams.FilterDescendantsInstances = {char}

    -- ═══════════════════════════════════
    -- FORCE / WELD GUARD
    -- ═══════════════════════════════════
    reg(char.DescendantAdded:Connect(function(obj)
        if DANGEROUS[obj.ClassName] then
            task.defer(function()
                pcall(function()
                    if not obj.Parent then return end
                    for _, prop in ipairs({"Attachment0","Attachment1","Part0","Part1"}) do
                        local ok2, val = pcall(function() return obj[prop] end)
                        if ok2 and val and typeof(val) == "Instance" then
                            if not val:IsDescendantOf(char) then
                                obj:Destroy()
                                return
                            end
                        end
                    end
                end)
            end)
            return
        end

        if obj:IsA("JointInstance") or obj:IsA("WeldConstraint") or obj:IsA("Constraint") then
            task.defer(function()
                pcall(function()
                    if not obj.Parent then return end
                    local p0, p1
                    if obj:IsA("Constraint") then
                        local a0 = obj.Attachment0
                        local a1 = obj.Attachment1
                        p0 = a0 and a0.Parent
                        p1 = a1 and a1.Parent
                    else
                        p0 = obj.Part0
                        p1 = obj.Part1
                    end
                    if not p0 or not p1 then return end
                    local o0 = p0:IsDescendantOf(char)
                    local o1 = p1:IsDescendantOf(char)
                    if o0 ~= o1 then
                        obj:Destroy()
                    end
                end)
            end)
        end
    end))

    -- ═══════════════════════════════════
    -- SEAT FLING BLOCK
    -- ═══════════════════════════════════
    reg(hum:GetPropertyChangedSignal("SeatPart"):Connect(function()
        local seat = hum.SeatPart
        if not seat then return end
        if not seat:IsDescendantOf(char) then
            for _, plr in ipairs(Players:GetPlayers()) do
                if plr ~= LP and plr.Character and seat:IsDescendantOf(plr.Character) then
                    hum.Sit = false
                    return
                end
            end
            if not seat.Anchored then
                if seat.AssemblyAngularVelocity.Magnitude > 10 or seat.AssemblyLinearVelocity.Magnitude > 50 then
                    hum.Sit = false
                end
            end
        end
    end))

    -- ═══════════════════════════════════
    -- HEARTBEAT — SPIN = FLING, KILL IT
    -- only touches velocity when spinning
    -- so TP tools work fine (no spin)
    -- ═══════════════════════════════════
    reg(RunService.Heartbeat:Connect(function()
        if not char.Parent or not hrp.Parent then return end

        local angMag = hrp.AssemblyAngularVelocity.Magnitude

        if angMag > SPIN_THRESH then
            hrp.AssemblyAngularVelocity = V3ZERO
            local curVel = hrp.AssemblyLinearVelocity
            hrp.AssemblyLinearVelocity = Vector3.new(0, curVel.Y, 0)
        end
    end))

    -- ═══════════════════════════════════
    -- STEPPED — PRE-PHYSICS
    -- ═══════════════════════════════════
    reg(RunService.Stepped:Connect(function()
        if not char.Parent or not hrp.Parent then return end

        -- pre-physics spin kill
        if hrp.AssemblyAngularVelocity.Magnitude > SPIN_THRESH then
            hrp.AssemblyAngularVelocity = V3ZERO
            local curVel = hrp.AssemblyLinearVelocity
            hrp.AssemblyLinearVelocity = Vector3.new(0, curVel.Y, 0)
        end

        -- enforce no-collide + flicker detection on Stepped too
        for plr in pairs(trackedPlayers) do
            if plr.Character then
                local otherChar = plr.Character
                local otherHRP = otherChar:FindFirstChild("HumanoidRootPart")

                if otherHRP then
                    local prevPos = otherPlayerPos[plr]
                    local curOtherPos = otherHRP.Position

                    if prevPos then
                        local delta = (curOtherPos - prevPos).Magnitude
                        if delta > FLICKER_DIST then
                            for _, p in ipairs(otherChar:GetDescendants()) do
                                if p:IsA("BasePart") then
                                    pcall(function()
                                        p.CanCollide = false
                                        p.CanTouch = false
                                    end)
                                end
                            end
                        end
                    end
                    otherPlayerPos[plr] = curOtherPos
                end

                for _, p in ipairs(otherChar:GetDescendants()) do
                    if p:IsA("BasePart") and p.CanCollide then
                        pcall(function() p.CanCollide = false end)
                    end
                end
            end
        end

        -- freeze spinning/fast non-character parts nearby
        local ok, nearby = pcall(function()
            return workspace:GetPartBoundsInRadius(hrp.Position, SCAN_RADIUS, overlapParams)
        end)

        if ok and nearby then
            for _, part in ipairs(nearby) do
                if not part.Anchored and not part:IsDescendantOf(char) then
                    local isPlayerPart = false
                    for plr in pairs(trackedPlayers) do
                        if plr.Character and part:IsDescendantOf(plr.Character) then
                            isPlayerPart = true
                            break
                        end
                    end

                    if isPlayerPart then
                        pcall(function()
                            part.CanCollide = false
                            part.CanTouch = false
                        end)
                    else
                        local av = part.AssemblyAngularVelocity.Magnitude
                        local lv = part.AssemblyLinearVelocity.Magnitude
                        if av > 5 or lv > 25 then
                            pcall(function()
                                part.CanCollide = false
                                part.CanTouch = false
                                part.AssemblyLinearVelocity = V3ZERO
                                part.AssemblyAngularVelocity = V3ZERO
                            end)
                        end
                    end
                end
            end
        end
    end))

    -- ═══════════════════════════════════
    -- RENDERSTEPPED — final spin kill
    -- ═══════════════════════════════════
    reg(RunService.RenderStepped:Connect(function()
        if not char.Parent or not hrp.Parent then return end
        if hrp.AssemblyAngularVelocity.Magnitude > SPIN_THRESH then
            hrp.AssemblyAngularVelocity = V3ZERO
            local curVel = hrp.AssemblyLinearVelocity
            hrp.AssemblyLinearVelocity = Vector3.new(0, curVel.Y, 0)
        end
    end))

    -- ═══════════════════════════════════
    -- TOUCHED fallback
    -- ═══════════════════════════════════
    local touchCD = {}
    local function hookTouch(bp)
        if not bp:IsA("BasePart") then return end
        reg(bp.Touched:Connect(function(hit)
            if touchCD[bp] then return end
            if not hit or not hit.Parent then return end
            if hit:IsDescendantOf(char) or hit.Anchored then return end

            local av = hit.AssemblyAngularVelocity.Magnitude
            local lv = hit.AssemblyLinearVelocity.Magnitude
            if av > 5 or lv > 20 then
                touchCD[bp] = true
                task.delay(0.05, function() touchCD[bp] = nil end)
                pcall(function()
                    hit.CanCollide = false
                    hit.CanTouch = false
                    hit.AssemblyLinearVelocity = V3ZERO
                    hit.AssemblyAngularVelocity = V3ZERO
                end)
                hrp.AssemblyAngularVelocity = V3ZERO
            end
        end))
    end

    for _, p in ipairs(char:GetDescendants()) do hookTouch(p) end
    reg(char.DescendantAdded:Connect(hookTouch))
end

protect(LP.Character)
LP.CharacterAdded:Connect(function(c)
    task.wait(0.2)
    protect(c)
end)
