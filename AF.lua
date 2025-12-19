local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local LP = Players.LocalPlayer
local WS = game:GetService("Workspace")

-- CONFIG
local MAX_VEL = 55
local FLY_MAX_VEL = 400
local FLING_ACCEL = 600
local TOGGLE_KEY = Enum.KeyCode.F8

-- STATE
local root, char, safeCF, flings, protecting = nil, nil, nil, 0, false
local enabled = true
local isFlying = false
local lastVel = Vector3.zero
local lastTime = 0
local V3Zero = Vector3.zero

-- FLY MOVERS (don't destroy these - fly scripts need them)
local FLY_MOVERS = {
    BodyVelocity = true,
    BodyGyro = true,
    BodyPosition = true,
    VectorForce = true,
    LinearVelocity = true,
    AlignPosition = true,
    AlignOrientation = true,
}

-- ═══════════════════════════════════════════════════════════════════
-- FLY DETECTION
-- ═══════════════════════════════════════════════════════════════════

local function checkFlying()
    if not char then return false end
    
    -- Check if any fly body movers exist on character
    for _, obj in char:GetDescendants() do
        if FLY_MOVERS[obj.ClassName] then
            return true
        end
    end
    return false
end

-- ═══════════════════════════════════════════════════════════════════
-- FLING DETECTION (acceleration-based, not velocity-based)
-- ═══════════════════════════════════════════════════════════════════

local function isFlingAcceleration(vel)
    local now = tick()
    local dt = now - lastTime
    if dt < 0.001 then dt = 0.001 end
    
    local accel = (vel - lastVel).Magnitude / dt
    
    lastVel = vel
    lastTime = now
    
    -- High acceleration + high velocity = fling
    -- Flying has smooth acceleration
    return accel > FLING_ACCEL and vel.Magnitude > 150
end

-- ═══════════════════════════════════════════════════════════════════
-- MAIN LOOP
-- ═══════════════════════════════════════════════════════════════════

RunService.RenderStepped:Connect(function()
    if not enabled or not root then return end
    
    local lv = root.AssemblyLinearVelocity
    local m = lv.X*lv.X + lv.Y*lv.Y + lv.Z*lv.Z
    
    -- Update fly status
    isFlying = checkFlying()
    
    -- If flying, allow high velocity
    if isFlying then
        -- Only block extreme fling acceleration while flying
        if isFlingAcceleration(lv) then
            root.AssemblyLinearVelocity = lastVel
            flings += 1
            protecting = true
        else
            protecting = false
        end
        
        -- Save position when moving slow
        if m < 400 then
            safeCF = root.CFrame
        end
        return
    end
    
    -- Normal anti-fling (not flying)
    if m > 90000 then -- 300^2 extreme
        root.AssemblyLinearVelocity = V3Zero
        root.AssemblyAngularVelocity = V3Zero
        if safeCF then root.CFrame = safeCF end
        flings += 1
        protecting = true
    elseif m > 22500 then -- 150^2 high
        -- Check if it's a fling or just fast movement
        if isFlingAcceleration(lv) then
            root.AssemblyLinearVelocity = V3Zero
            root.AssemblyAngularVelocity = V3Zero
            flings += 1
            protecting = true
        else
            protecting = false
        end
    elseif m > 3025 then -- 55^2 clamp
        root.AssemblyLinearVelocity = lv.Unit * MAX_VEL
        protecting = false
    else
        if m < 400 then safeCF = root.CFrame end
        protecting = false
    end
end)

-- ═══════════════════════════════════════════════════════════════════
-- CHARACTER SETUP (NO body mover destruction)
-- ═══════════════════════════════════════════════════════════════════

local function onChar(c)
    char = c
    root = c:WaitForChild("HumanoidRootPart", 5)
    if root then
        safeCF = root.CFrame
        lastVel = Vector3.zero
        lastTime = tick()
    end
    
    -- DON'T destroy body movers anymore - fly scripts need them!
end

LP.CharacterAdded:Connect(onChar)
if LP.Character then task.spawn(onChar, LP.Character) end

-- ═══════════════════════════════════════════════════════════════════
-- OTHER PLAYERS NOCLIP
-- ═══════════════════════════════════════════════════════════════════

local function noCollide(c)
    if not c then return end
    for _, p in c:GetChildren() do
        if p:IsA("BasePart") then p.CanCollide = false end
    end
    c.DescendantAdded:Connect(function(p)
        if p:IsA("BasePart") then p.CanCollide = false end
    end)
end

local function onPlayer(p)
    if p == LP then return end
    if p.Character then noCollide(p.Character) end
    p.CharacterAdded:Connect(noCollide)
end

for _, p in Players:GetPlayers() do task.spawn(onPlayer, p) end
Players.PlayerAdded:Connect(onPlayer)

-- ═══════════════════════════════════════════════════════════════════
-- SUSPICIOUS PARTS
-- ═══════════════════════════════════════════════════════════════════

WS.DescendantAdded:Connect(function(o)
    if not o:IsA("BasePart") then return end
    
    task.defer(function()
        if not o.Parent then return end
        
        local cpp = o.CustomPhysicalProperties
        if cpp and cpp.Density == 0 and cpp.Friction == 0 then
            o.CanCollide = false
            pcall(o.Destroy, o)
            return
        end
        
        local v = o.AssemblyLinearVelocity
        if v.X*v.X + v.Y*v.Y + v.Z*v.Z > 160000 then
            o.CanCollide = false
            pcall(o.Destroy, o)
        end
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
-- TOGGLE KEY
-- ═══════════════════════════════════════════════════════════════════

UserInputService.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if input.KeyCode == TOGGLE_KEY then
        enabled = not enabled
    end
end)

-- ═══════════════════════════════════════════════════════════════════
-- GUI
-- ═══════════════════════════════════════════════════════════════════

local gui = Instance.new("ScreenGui")
gui.ResetOnSpawn = false
gui.Parent = LP:WaitForChild("PlayerGui")

local lbl = Instance.new("TextLabel")
lbl.Size = UDim2.fromOffset(110, 24)
lbl.Position = UDim2.new(0, 10, 0.5, -12)
lbl.BackgroundColor3 = Color3.new(0.1, 0.1, 0.1)
lbl.TextColor3 = Color3.new(0.5, 1, 0.5)
lbl.Font = Enum.Font.GothamBold
lbl.TextSize = 11
lbl.Text = "🛡️ 0"
lbl.Parent = gui
Instance.new("UICorner", lbl).CornerRadius = UDim.new(0, 4)

task.spawn(function()
    while task.wait(0.3) do
        if not enabled then
            lbl.Text = "❌ OFF [F8]"
            lbl.TextColor3 = Color3.new(0.5, 0.5, 0.5)
            lbl.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
        elseif isFlying then
            lbl.Text = "✈️ " .. flings
            lbl.TextColor3 = Color3.new(0.4, 0.7, 1)
            lbl.BackgroundColor3 = Color3.fromRGB(15, 25, 40)
        elseif protecting then
            lbl.Text = "⚠️ " .. flings
            lbl.TextColor3 = Color3.new(1, 0.4, 0.4)
            lbl.BackgroundColor3 = Color3.fromRGB(40, 15, 15)
        else
            lbl.Text = "🛡️ " .. flings
            lbl.TextColor3 = Color3.new(0.5, 1, 0.5)
            lbl.BackgroundColor3 = Color3.fromRGB(15, 30, 15)
        end
    end
end)

print("🛡️ Anti-Fling loaded | [F8] toggle | Fly compatible")
