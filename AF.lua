-- [ Anti-Fling v9.1 | No Push + No Fling | Zero Lag ] --
-- Blocks all player contact - nobody can push or fling you

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local LP = Players.LocalPlayer

-- [ Config ] --
local SCAN_RADIUS = 30
local FLING_SPEED = 120
local FLING_SPIN = 20

-- [ State ] --
local blockCount = 0
local blockedParts = {}
local processedCharacters = {}

-- [ Cache ] --
local char, root, hum
local V3_ZERO = Vector3.zero
local overlapParams = OverlapParams.new()
overlapParams.FilterType = Enum.RaycastFilterType.Exclude
overlapParams.MaxParts = 50

-- ═══════════════════════════════════════════════════════════════════
-- SIMPLE GUI
-- ═══════════════════════════════════════════════════════════════════

local gui = Instance.new("ScreenGui")
gui.Name = "AntiFling"
gui.ResetOnSpawn = false
gui.Parent = LP:WaitForChild("PlayerGui")

local box = Instance.new("Frame")
box.Size = UDim2.fromOffset(85, 38)
box.Position = UDim2.fromOffset(5, 5)
box.BackgroundColor3 = Color3.new(0, 0, 0)
box.BackgroundTransparency = 0.5
box.BorderSizePixel = 0
box.Parent = gui
Instance.new("UICorner", box).CornerRadius = UDim.new(0, 6)

local dot = Instance.new("Frame")
dot.Size = UDim2.fromOffset(8, 8)
dot.Position = UDim2.fromOffset(6, 6)
dot.BackgroundColor3 = Color3.new(0, 1, 0)
dot.BorderSizePixel = 0
dot.Parent = box
Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -20, 0, 14)
title.Position = UDim2.fromOffset(18, 3)
title.BackgroundTransparency = 1
title.Text = "Anti-Fling"
title.TextColor3 = Color3.new(1, 1, 1)
title.TextSize = 10
title.Font = Enum.Font.GothamBold
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = box

local counter = Instance.new("TextLabel")
counter.Size = UDim2.new(1, -10, 0, 12)
counter.Position = UDim2.fromOffset(6, 20)
counter.BackgroundTransparency = 1
counter.Text = "Blocked: 0"
counter.TextColor3 = Color3.new(1, 0.6, 0)
counter.TextSize = 9
counter.Font = Enum.Font.Gotham
counter.TextXAlignment = Enum.TextXAlignment.Left
counter.Parent = box

local function flash()
    dot.BackgroundColor3 = Color3.new(1, 0, 0)
    task.delay(0.08, function()
        dot.BackgroundColor3 = Color3.new(0, 1, 0)
    end)
end

-- ═══════════════════════════════════════════════════════════════════
-- GHOST OTHER PLAYERS (No Push/Bump)
-- ═══════════════════════════════════════════════════════════════════

local function ghostCharacter(character)
    if not character or processedCharacters[character] then return end
    processedCharacters[character] = true
    
    local function disablePart(part)
        if part:IsA("BasePart") then
            part.CanCollide = false
        end
    end
    
    -- Disable all current parts
    for _, part in character:GetDescendants() do
        disablePart(part)
    end
    
    -- Disable any new parts added
    character.DescendantAdded:Connect(disablePart)
end

local function setupPlayer(player)
    if player == LP then return end
    
    if player.Character then
        ghostCharacter(player.Character)
    end
    
    player.CharacterAdded:Connect(function(c)
        task.wait()
        ghostCharacter(c)
    end)
end

-- ═══════════════════════════════════════════════════════════════════
-- FLING DETECTION
-- ═══════════════════════════════════════════════════════════════════

local function isOtherPlayerPart(part)
    local ancestor = part:FindFirstAncestorOfClass("Model")
    if not ancestor then return false end
    local player = Players:GetPlayerFromCharacter(ancestor)
    return player and player ~= LP
end

local function isFlingAttack(part, myPos)
    if part.Anchored then return false end
    if not isOtherPlayerPart(part) then return false end
    
    local speed = part.AssemblyLinearVelocity.Magnitude
    local spin = part.AssemblyAngularVelocity.Magnitude
    local dist = (part.Position - myPos).Magnitude
    
    -- High speed fling
    if speed > FLING_SPEED and dist < 25 then return true end
    
    -- Spinning attack (super ring)
    if spin > FLING_SPIN and dist < 20 then return true end
    
    -- Very fast direct attack
    if speed > 180 and dist < 30 then
        local dir = (myPos - part.Position).Unit
        local velDir = part.AssemblyLinearVelocity.Unit
        if dir:Dot(velDir) > 0.4 then return true end
    end
    
    return false
end

local function blockPart(part)
    if blockedParts[part] then return end
    blockedParts[part] = tick()
    
    part.AssemblyLinearVelocity = V3_ZERO
    part.AssemblyAngularVelocity = V3_ZERO
    
    blockCount += 1
    counter.Text = "Blocked: " .. blockCount
    flash()
end

-- ═══════════════════════════════════════════════════════════════════
-- CHARACTER SETUP
-- ═══════════════════════════════════════════════════════════════════

local function setupCharacter(c)
    if not c then return end
    
    char = c
    root = c:WaitForChild("HumanoidRootPart", 5)
    hum = c:FindFirstChildOfClass("Humanoid")
    
    if not root then return end
    
    overlapParams.FilterDescendantsInstances = {char}
    
    -- Anti-ragdoll
    if hum then
        hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
        hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
    end
end

-- ═══════════════════════════════════════════════════════════════════
-- MAIN LOOP - LIGHTWEIGHT
-- ═══════════════════════════════════════════════════════════════════

local frameCount = 0
local cleanupCount = 0

RunService.Heartbeat:Connect(function()
    if not root or not root.Parent then return end
    
    frameCount += 1
    if frameCount < 8 then return end
    frameCount = 0
    
    local myPos = root.Position
    
    -- Scan for fling attacks
    local ok, parts = pcall(workspace.GetPartBoundsInRadius, workspace, myPos, SCAN_RADIUS, overlapParams)
    
    if ok and parts then
        for _, part in parts do
            if isFlingAttack(part, myPos) then
                blockPart(part)
            end
        end
    end
    
    -- Cleanup every ~100 frames
    cleanupCount += 1
    if cleanupCount >= 12 then
        cleanupCount = 0
        local now = tick()
        for part, time in pairs(blockedParts) do
            if now - time > 2 then
                blockedParts[part] = nil
            end
        end
    end
end)

-- ═══════════════════════════════════════════════════════════════════
-- INIT
-- ═══════════════════════════════════════════════════════════════════

-- Ghost all existing players
for _, player in Players:GetPlayers() do
    setupPlayer(player)
end

-- Ghost new players
Players.PlayerAdded:Connect(setupPlayer)

-- Cleanup when players leave
Players.PlayerRemoving:Connect(function(player)
    if player.Character then
        processedCharacters[player.Character] = nil
    end
end)

-- Setup local character
if LP.Character then
    setupCharacter(LP.Character)
end

LP.CharacterAdded:Connect(function(c)
    task.wait(0.1)
    setupCharacter(c)
end)

print("🛡️ Anti-Fling v9.1 | No Push + No Fling | Active")
