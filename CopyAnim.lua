-- Animation Copy v11 - CLEAN & SIMPLE
-- Just copies nearest player's animations perfectly

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local LP = Players.LocalPlayer

-- CONFIG
local TOGGLE_KEY = Enum.KeyCode.G
local MAX_DIST = 150

-- STATE
local copying = false
local target = nil
local targetChar = nil
local myChar, myHum, myRoot = nil, nil, nil
local storedAnimate = nil

-- ═══════════════════════════════════════════════════════════════════
-- FIND NEAREST PLAYER
-- ═══════════════════════════════════════════════════════════════════

local function findNearest()
    if not myRoot then return nil end
    
    local myPos = myRoot.Position
    local best, bestDist = nil, MAX_DIST
    
    for _, player in Players:GetPlayers() do
        if player ~= LP then
            local char = player.Character
            if char then
                local root = char:FindFirstChild("HumanoidRootPart")
                if root then
                    local dist = (myPos - root.Position).Magnitude
                    if dist < bestDist then
                        best = player
                        bestDist = dist
                    end
                end
            end
        end
    end
    
    return best
end

-- ═══════════════════════════════════════════════════════════════════
-- ANIMATE SCRIPT CONTROL
-- ═══════════════════════════════════════════════════════════════════

local function disableAnimate()
    if not myChar then return end
    
    -- Remove Animate script completely
    local animate = myChar:FindFirstChild("Animate")
    if animate then
        storedAnimate = animate
        animate.Parent = nil
    end
    
    -- Stop all playing animations
    if myHum then
        local animator = myHum:FindFirstChildOfClass("Animator")
        if animator then
            for _, track in animator:GetPlayingAnimationTracks() do
                track:Stop(0)
            end
        end
    end
end

local function enableAnimate()
    if storedAnimate and myChar then
        storedAnimate.Parent = myChar
    end
    storedAnimate = nil
end

-- ═══════════════════════════════════════════════════════════════════
-- MOTOR6D SYNC - PERFECT COPY EVERY FRAME
-- ═══════════════════════════════════════════════════════════════════

local function syncMotors()
    if not myChar or not myChar.Parent then return end
    if not targetChar or not targetChar.Parent then return end
    
    -- Get all motors from target
    for _, part in targetChar:GetDescendants() do
        if part:IsA("Motor6D") then
            -- Find matching motor in my character
            local myMotor = myChar:FindFirstChild(part.Name, true)
            if myMotor and myMotor:IsA("Motor6D") then
                myMotor.Transform = part.Transform
            end
        end
    end
end

-- ═══════════════════════════════════════════════════════════════════
-- START / STOP
-- ═══════════════════════════════════════════════════════════════════

local function start()
    if copying then return end
    
    -- Get my character
    myChar = LP.Character
    if not myChar then
        warn("No character!")
        return
    end
    
    myHum = myChar:FindFirstChildOfClass("Humanoid")
    myRoot = myChar:FindFirstChild("HumanoidRootPart")
    
    if not myHum or not myRoot then
        warn("Character not ready!")
        return
    end
    
    -- Find nearest player
    local nearest = findNearest()
    if not nearest then
        warn("No player nearby!")
        return
    end
    
    if not nearest.Character then
        warn("Target has no character!")
        return
    end
    
    target = nearest
    targetChar = target.Character
    
    copying = true
    disableAnimate()
    
    print("✅ Copying: " .. target.Name)
end

local function stop()
    if not copying then return end
    
    copying = false
    
    -- Reset all motor transforms to default
    if myChar then
        for _, part in myChar:GetDescendants() do
            if part:IsA("Motor6D") then
                part.Transform = CFrame.identity
            end
        end
    end
    
    enableAnimate()
    
    target = nil
    targetChar = nil
    
    print("❌ Stopped")
end

-- ═══════════════════════════════════════════════════════════════════
-- MAIN LOOP - SYNCS EVERY FRAME
-- ═══════════════════════════════════════════════════════════════════

RunService.RenderStepped:Connect(function()
    if not copying then return end
    
    -- Check if target still valid
    if not target or not target.Parent then
        stop()
        return
    end
    
    -- Update target character reference
    if target.Character ~= targetChar then
        targetChar = target.Character
    end
    
    if not targetChar then return end
    
    -- Sync!
    syncMotors()
end)

-- ═══════════════════════════════════════════════════════════════════
-- INPUT
-- ═══════════════════════════════════════════════════════════════════

UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.KeyCode == TOGGLE_KEY then
        if copying then
            stop()
        else
            start()
        end
    end
end)

-- ═══════════════════════════════════════════════════════════════════
-- HANDLE PLAYER LEAVING
-- ═══════════════════════════════════════════════════════════════════

Players.PlayerRemoving:Connect(function(player)
    if player == target then
        stop()
    end
end)

-- ═══════════════════════════════════════════════════════════════════
-- HANDLE RESPAWN
-- ═══════════════════════════════════════════════════════════════════

LP.CharacterAdded:Connect(function(newChar)
    myChar = newChar
    myHum = newChar:WaitForChild("Humanoid", 10)
    myRoot = newChar:WaitForChild("HumanoidRootPart", 10)
    
    task.wait(0.3)
    
    if copying and target then
        targetChar = target.Character
        disableAnimate()
    end
end)

-- ═══════════════════════════════════════════════════════════════════
-- SIMPLE GUI - JUST SHOWS STATUS
-- ═══════════════════════════════════════════════════════════════════

local gui = Instance.new("ScreenGui")
gui.Name = "AnimCopy"
gui.ResetOnSpawn = false
gui.Parent = LP:WaitForChild("PlayerGui")

local label = Instance.new("TextLabel")
label.Size = UDim2.fromOffset(160, 24)
label.Position = UDim2.fromOffset(10, 10)
label.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
label.BackgroundTransparency = 0.5
label.TextColor3 = Color3.fromRGB(255, 255, 255)
label.Font = Enum.Font.GothamBold
label.TextSize = 11
label.Text = "[G] Copy Anim"
label.Parent = gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 4)
corner.Parent = label

-- Update GUI
task.spawn(function()
    while true do
        task.wait(0.1)
        if copying and target then
            label.Text = "Copying: " .. target.Name
            label.BackgroundColor3 = Color3.fromRGB(0, 100, 50)
        else
            label.Text = "[G] Copy Anim"
            label.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
        end
    end
end)

-- ═══════════════════════════════════════════════════════════════════
-- INIT
-- ═══════════════════════════════════════════════════════════════════

if LP.Character then
    myChar = LP.Character
    myHum = myChar:FindFirstChildOfClass("Humanoid")
    myRoot = myChar:FindFirstChild("HumanoidRootPart")
end

print("═══════════════════════════════")
print("  Animation Copy - Press [G]")
print("═══════════════════════════════")
