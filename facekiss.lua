-- Services
local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer      = Players.LocalPlayer

-- Cleanup previous execution
if getgenv()._fk_cleanup then pcall(getgenv()._fk_cleanup) end

-- Config
local FACE_OFFSET   = -0.7
local HEIGHT_OFFSET  = 1
local THRUST_DIST   = 2.0
local THRUST_FREQ   = 25
local LERP_SPEED    = 40
local TOGGLE_KEY    = Enum.KeyCode.Z

-- State
local isActive        = false
local targetHead      = nil
local targetPlayer    = nil
local thrustClock     = 0
local mainConn        = nil
local noclipConn      = nil
local conns           = {}
local savedCanCollide = {}          -- ← NEW: stores original CanCollide per part

local function track(c) conns[#conns+1] = c return c end
local function getHRP()
    local ch = LocalPlayer.Character
    return ch and ch:FindFirstChild("HumanoidRootPart")
end

local function smoothAlpha(speed, dt)
    return 1 - math.exp(-speed * dt)
end

-- ══════════════════════════════════════
-- Noclip  (FIXED)
-- ══════════════════════════════════════
local function startNoclip()
    if noclipConn then noclipConn:Disconnect() end

    -- Save original CanCollide states ONCE before we start zeroing them
    table.clear(savedCanCollide)
    local char = LocalPlayer.Character
    if char then
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") then
                savedCanCollide[part] = part.CanCollide
            end
        end
    end

    noclipConn = track(RunService.Stepped:Connect(function()
        local char = LocalPlayer.Character
        if not char then return end
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") then
                part.CanCollide = false
            end
        end
    end))
end

local function stopNoclip()
    if noclipConn then
        noclipConn:Disconnect()
        noclipConn = nil
    end

    -- Restore each part to its ORIGINAL CanCollide value
    for part, wasCollidable in pairs(savedCanCollide) do
        if part and part.Parent then
            part.CanCollide = wasCollidable
        end
    end
    table.clear(savedCanCollide)

    -- ★ BuildRigFromAttachments() REMOVED — it was creating
    --   duplicate Motor6D joints every call, corrupting physics.
end

-- ══════════════════════════════════════
-- Character Lock / Unlock
-- ══════════════════════════════════════
local function lock(char)
    if not char then return end
    local a = char:FindFirstChild("Animate")
    if a then a.Disabled = true end
    local h = char:FindFirstChildOfClass("Humanoid")
    if h then
        for _, t in ipairs(h:GetPlayingAnimationTracks()) do t:Stop(0) end
        h.PlatformStand = true
        h.AutoRotate = false
        h:ChangeState(Enum.HumanoidStateType.Physics)
    end
    for _, c in ipairs(char:GetChildren()) do
        if c:IsA("LocalScript") and c.Name:lower():find("control") then
            c.Disabled = true
        end
    end
end

local function unlock(char)
    if not char then return end
    local a = char:FindFirstChild("Animate")
    if a then a.Disabled = false end
    local h = char:FindFirstChildOfClass("Humanoid")
    if h then
        h.PlatformStand = false
        h.AutoRotate = true
        h:ChangeState(Enum.HumanoidStateType.GettingUp)
    end
    for _, c in ipairs(char:GetChildren()) do
        if c:IsA("LocalScript") and c.Name:lower():find("control") then
            c.Disabled = false
        end
    end
end

-- ══════════════════════════════════════
-- Full Deactivate
-- ══════════════════════════════════════
local function deactivate()
    if not isActive then return end
    isActive = false
    getgenv().facekissactive = false
    targetHead, targetPlayer = nil, nil

    if mainConn then mainConn:Disconnect(); mainConn = nil end
    stopNoclip()
    unlock(LocalPlayer.Character)
    print("[FaceKiss] Deactivated")
end

-- ══════════════════════════════════════
-- Target Validity Check
-- ══════════════════════════════════════
local function isTargetAlive()
    if not targetPlayer or not targetPlayer:IsDescendantOf(Players) then
        return false
    end
    if not targetPlayer.Character then
        return false
    end
    local hum = targetPlayer.Character:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then
        return false
    end
    return true
end

-- ══════════════════════════════════════
-- Targeting
-- ══════════════════════════════════════
local function findNearest()
    local hrp = getHRP()
    if not hrp then return nil, nil end
    local best, bHead, bPlr = math.huge, nil, nil
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and p.Character then
            local hum  = p.Character:FindFirstChildOfClass("Humanoid")
            local head = p.Character:FindFirstChild("Head")
            if hum and hum.Health > 0 and head then
                local d = (hrp.Position - head.Position).Magnitude
                if d < best then best, bHead, bPlr = d, head, p end
            end
        end
    end
    return bHead, bPlr
end

-- ══════════════════════════════════════
-- Main Loop  (velocity fix)
-- ══════════════════════════════════════
local function startLoop()
    thrustClock = 0
    if mainConn then mainConn:Disconnect() end

    mainConn = track(RunService.RenderStepped:Connect(function(dt)
        if not isActive then
            if mainConn then mainConn:Disconnect(); mainConn = nil end
            return
        end

        if not isTargetAlive() then
            deactivate()
            return
        end

        local hrp = getHRP()
        if not hrp then return end

        if not targetHead or not targetHead:IsDescendantOf(workspace) then
            targetHead = targetPlayer.Character:FindFirstChild("Head")
            if not targetHead then
                deactivate()
                return
            end
        end

        lock(LocalPlayer.Character)

        thrustClock = thrustClock + dt
        local t = math.sin(thrustClock * THRUST_FREQ) * 0.5 + 0.5
        local z = FACE_OFFSET - (t * THRUST_DIST)

        local goal = targetHead.CFrame
            * CFrame.new(0, HEIGHT_OFFSET, z)
            * CFrame.Angles(0, math.rad(180), 0)

        hrp.CFrame = hrp.CFrame:Lerp(goal, smoothAlpha(LERP_SPEED, dt))
        hrp.AssemblyLinearVelocity  = Vector3.zero   -- ← modern property
        hrp.AssemblyAngularVelocity = Vector3.zero   -- ← modern property
    end))
end

-- ══════════════════════════════════════
-- Toggle
-- ══════════════════════════════════════
local function toggle()
    if isActive then
        deactivate()
    else
        targetHead, targetPlayer = findNearest()
        if not targetHead then
            warn("[FaceKiss] No nearby player found!")
            return
        end

        isActive = true
        getgenv().facekissactive = true

        lock(LocalPlayer.Character)
        startNoclip()

        local hrp = getHRP()
        if hrp then
            hrp.CFrame = targetHead.CFrame
                * CFrame.new(0, HEIGHT_OFFSET, FACE_OFFSET)
                * CFrame.Angles(0, math.rad(180), 0)
        end

        startLoop()
        print("[FaceKiss] Activated — targeting: " .. targetPlayer.Name)
    end
end

-- ══════════════════════════════════════
-- Auto-stop when target leaves
-- ══════════════════════════════════════
track(Players.PlayerRemoving:Connect(function(plr)
    if isActive and targetPlayer == plr then
        deactivate()
    end
end))

-- ══════════════════════════════════════
-- Keybind
-- ══════════════════════════════════════
track(UserInputService.InputBegan:Connect(function(input, gpe)
    if not gpe and input.KeyCode == TOGGLE_KEY then toggle() end
end))

-- ══════════════════════════════════════
-- Respawn
-- ══════════════════════════════════════
track(LocalPlayer.CharacterAdded:Connect(function(newChar)
    newChar:WaitForChild("HumanoidRootPart")
    if not isActive then return end
    task.wait(0.2)
    lock(newChar)
    startNoclip()
    if isTargetAlive() then
        targetHead = targetPlayer.Character:FindFirstChild("Head")
        if targetHead then
            startLoop()
            return
        end
    end
    deactivate()
end))

-- ══════════════════════════════════════
-- Cleanup for re-execution
-- ══════════════════════════════════════
getgenv()._fk_cleanup = function()
    isActive = false
    getgenv().facekissactive = false
    for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
    table.clear(conns)
    mainConn = nil
    stopNoclip()
    unlock(LocalPlayer.Character)
end

print("[FaceKiss] Ready — press Z to toggle")
