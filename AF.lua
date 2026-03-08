local Players      = game:GetService("Players")
local RunService   = game:GetService("RunService")
local UIS          = game:GetService("UserInputService")
local LP           = Players.LocalPlayer

local conns        = {}
local V3ZERO       = Vector3.zero
local HUGE_VEL     = 80        -- velocity magnitude that is "impossible" from normal gameplay
local HUGE_ANG     = 35        -- angular velocity that is "impossible"
local SNAP_DIST    = 12        -- if we moved this far in one frame without jumping/falling, snap back
local MAX_LEGIT_Y  = 60        -- max Y velocity from normal jump+fall in natural disaster
local SCAN_RADIUS  = 20
local FLICKER_DIST = 8         -- if another player moves this far in 1 frame = flicker TP

-- track other players' positions to detect flicker TP
local otherPlayerPos = {}

local function clearConns()
    for i = #conns, 1, -1 do
        pcall(function() conns[i]:Disconnect() end)
        conns[i] = nil
    end
end
local function reg(c) conns[#conns + 1] = c return c end

-- ════════════════════════════════════════════
-- FORCE ALL OTHER PLAYER PARTS NON-COLLIDABLE
-- ════════════════════════════════════════════
local function disableCollisionOnPart(part)
    if not part:IsA("BasePart") then return end
    pcall(function()
        part.CanCollide = false
        part.CanTouch = false
    end)
end

local function lockPlayerChar(plrChar)
    if not plrChar then return end
    for _, p in ipairs(plrChar:GetDescendants()) do
        disableCollisionOnPart(p)
    end
    reg(plrChar.DescendantAdded:Connect(function(p)
        task.defer(function()
            disableCollisionOnPart(p)
        end)
    end))
end

-- ════════════════════════════════════════════
-- DANGEROUS FORCE OBJECTS
-- ════════════════════════════════════════════
local DANGEROUS = {}
for _, cn in ipairs({
    "BodyVelocity","BodyAngularVelocity","BodyForce",
    "BodyPosition","BodyGyro","BodyThrust","RocketPropulsion",
    "Torque","VectorForce","LinearVelocity","AlignPosition",
    "AlignOrientation","AngularVelocity",
}) do DANGEROUS[cn] = true end

-- ════════════════════════════════════════════
-- MAIN PROTECT
-- ════════════════════════════════════════════
local function protect(char)
    if not char then return end
    clearConns()
    otherPlayerPos = {}

    local hrp = char:WaitForChild("HumanoidRootPart", 5)
    local hum = char:WaitForChild("Humanoid", 5)
    if not hrp or not hum then return end

    -- state for snapback
    local lastPos       = hrp.Position
    local lastVel       = V3ZERO
    local isJumping     = false
    local isFalling     = false
    local groundedTick  = tick()

    -- overlap params excluding our character
    local overlapParams = OverlapParams.new()
    overlapParams.FilterType = Enum.RaycastFilterType.Exclude
    overlapParams.FilterDescendantsInstances = {char}

    -- ═══════════════════════════════════
    -- LOCK OTHER PLAYERS (event-driven + continuous)
    -- ═══════════════════════════════════
    local function watchPlayer(plr)
        if plr == LP then return end
        if plr.Character then lockPlayerChar(plr.Character) end
        reg(plr.CharacterAdded:Connect(function(c)
            task.wait(0.1)
            lockPlayerChar(c)
        end))
    end
    for _, plr in ipairs(Players:GetPlayers()) do watchPlayer(plr) end
    reg(Players.PlayerAdded:Connect(watchPlayer))

    -- ═══════════════════════════════════
    -- FORCE / WELD GUARD on our character
    -- ═══════════════════════════════════
    reg(char.DescendantAdded:Connect(function(obj)
        if DANGEROUS[obj.ClassName] then
            task.defer(function()
                pcall(function()
                    if not obj.Parent then return end
                    -- if this force object references anything outside our char, destroy
                    for _, prop in ipairs({"Attachment0","Attachment1","Part0","Part1"}) do
                        local ok2, val = pcall(function() return obj[prop] end)
                        if ok2 and val and typeof(val) == "Instance" then
                            if not val:IsDescendantOf(char) then
                                obj:Destroy()
                                return
                            end
                        end
                    end
                    -- if it's parented in our char but we didn't expect it — 
                    -- check if any other player char is involved
                    for _, plr in ipairs(Players:GetPlayers()) do
                        if plr ~= LP and plr.Character then
                            if obj:IsDescendantOf(plr.Character) then
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
            -- if seat belongs to another player or is spinning
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
    -- JUMP TRACKING (so we don't block natural jumps)
    -- ═══════════════════════════════════
    reg(hum.StateChanged:Connect(function(_, newState)
        if newState == Enum.HumanoidStateType.Jumping then
            isJumping = true
            isFalling = false
        elseif newState == Enum.HumanoidStateType.Freefall then
            isFalling = true
        elseif newState == Enum.HumanoidStateType.Landed
            or newState == Enum.HumanoidStateType.Running then
            isJumping = false
            isFalling = false
            groundedTick = tick()
        end
    end))

    -- ═══════════════════════════════════
    -- HEARTBEAT — POST-PHYSICS SNAPBACK
    --
    -- This is the KEY anti-flicker-fling:
    -- After physics resolves, if our velocity
    -- spiked impossibly, we reset it and
    -- teleport back to our last safe position.
    -- ═══════════════════════════════════
    reg(RunService.Heartbeat:Connect(function(dt)
        if not char.Parent or not hrp.Parent then return end

        local curPos = hrp.Position
        local curVel = hrp.AssemblyLinearVelocity
        local curAng = hrp.AssemblyAngularVelocity

        local velMag = curVel.Magnitude
        local angMag = curAng.Magnitude
        local posDelta = (curPos - lastPos).Magnitude

        -- determine if current motion is "legit"
        local legitimateMotion = false

        -- walking speed is typically ≤ 20 studs/s, 
        -- jump velocity ~ 50, falling can be ~ 100+
        -- disasters (tornado, etc.) can move you too
        -- we allow generous thresholds

        local yVel = math.abs(curVel.Y)
        local horizVel = Vector3.new(curVel.X, 0, curVel.Z).Magnitude

        -- if we're jumping or falling, vertical velocity is expected
        if isJumping or isFalling or hum.FloorMaterial == Enum.Material.Air then
            legitimateMotion = true
        end

        -- walking/running
        if horizVel < 30 and yVel < MAX_LEGIT_Y then
            legitimateMotion = true
        end

        -- FLING DETECTION: impossibly high velocity + angular velocity
        local flung = false

        if velMag > HUGE_VEL and angMag > HUGE_ANG then
            flung = true
        end

        -- rapid position change without corresponding movement state
        if posDelta > SNAP_DIST and dt > 0 then
            local impliedSpeed = posDelta / dt
            if impliedSpeed > 300 and not isFalling and not isJumping then
                flung = true
            end
        end

        -- massive angular velocity alone (spinning fling)
        if angMag > 80 then
            flung = true
        end

        -- massive horizontal velocity that isn't from disasters
        -- (disasters typically push < 100 studs/s horizontal)
        if horizVel > 200 and angMag > 20 then
            flung = true
        end

        if flung then
            -- SNAP BACK
            hrp.AssemblyLinearVelocity = V3ZERO
            hrp.AssemblyAngularVelocity = V3ZERO
            hrp.CFrame = CFrame.new(lastPos) * (hrp.CFrame - hrp.CFrame.Position)
            hrp.AssemblyLinearVelocity = V3ZERO
            hrp.AssemblyAngularVelocity = V3ZERO
        else
            -- update safe position
            -- only update if we're in a reasonable state
            if velMag < 150 and angMag < 30 then
                lastPos = curPos
            end
        end

        lastVel = curVel
    end))

    -- ═══════════════════════════════════
    -- STEPPED — PRE-PHYSICS
    --
    -- 1. Kill spin every frame
    -- 2. Re-enforce collision disable on ALL other player parts
    -- 3. Detect flicker-TP players and aggressively disable them
    -- 4. Freeze fast unanchored non-character parts nearby
    -- ═══════════════════════════════════
    reg(RunService.Stepped:Connect(function()
        if not char.Parent or not hrp.Parent then return end

        -- KILL OUR SPIN (always, pre-physics)
        if hrp.AssemblyAngularVelocity.Magnitude > HUGE_ANG then
            hrp.AssemblyAngularVelocity = V3ZERO
        end

        -- RE-ENFORCE collision disable on other players EVERY FRAME
        -- This is critical: the flicker-fling exploiter may
        -- re-enable CanCollide on their parts via network ownership
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LP and plr.Character then
                local otherChar = plr.Character
                local otherHRP = otherChar:FindFirstChild("HumanoidRootPart")

                -- FLICKER DETECTION: track position changes
                if otherHRP then
                    local prevPos = otherPlayerPos[plr]
                    local curOtherPos = otherHRP.Position

                    if prevPos then
                        local delta = (curOtherPos - prevPos).Magnitude
                        if delta > FLICKER_DIST then
                            -- this player is flicker-teleporting
                            -- aggressively disable ALL their parts
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

                -- always enforce no-collide on other players
                for _, p in ipairs(otherChar:GetDescendants()) do
                    if p:IsA("BasePart") then
                        pcall(function()
                            if p.CanCollide then
                                p.CanCollide = false
                            end
                        end)
                    end
                end
            end
        end

        -- FREEZE fast-moving unanchored non-character parts near us
        local ok, nearby = pcall(function()
            return workspace:GetPartBoundsInRadius(hrp.Position, SCAN_RADIUS, overlapParams)
        end)

        if ok and nearby then
            for _, part in ipairs(nearby) do
                if not part.Anchored and not part:IsDescendantOf(char) then
                    -- check if this belongs to ANY player character
                    local isPlayerPart = false
                    for _, plr in ipairs(Players:GetPlayers()) do
                        if plr ~= LP and plr.Character and part:IsDescendantOf(plr.Character) then
                            isPlayerPart = true
                            break
                        end
                    end

                    if isPlayerPart then
                        -- already handled above, but double-enforce
                        pcall(function()
                            part.CanCollide = false
                            part.CanTouch = false
                        end)
                    else
                        -- non-character part (potential fling tool ring/part)
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
    -- RENDERSTEPPED — ADDITIONAL SPIN KILL
    -- runs at render priority, catches anything
    -- that slipped through Stepped
    -- ═══════════════════════════════════
    reg(RunService.RenderStepped:Connect(function()
        if not char.Parent or not hrp.Parent then return end
        if hrp.AssemblyAngularVelocity.Magnitude > HUGE_ANG then
            hrp.AssemblyAngularVelocity = V3ZERO
        end
    end))

    -- ═══════════════════════════════════
    -- TOUCHED fallback — if somehow a part
    -- contacts us with force
    -- ═══════════════════════════════════
    local touchCD = {}
    local function hookTouch(bp)
        if not bp:IsA("BasePart") then return end
        reg(bp.Touched:Connect(function(hit)
            if touchCD[bp] then return end
            if not hit or not hit.Parent then return end
            if hit:IsDescendantOf(char) or hit.Anchored then return end

            -- any non-character part touching us with speed
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
