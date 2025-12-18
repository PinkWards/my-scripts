--[[
    Anti-Fling v14 - ZERO LAG Edition
    - Immune to ALL flings including rings
    - No workspace scanning
    - Protects YOUR character only
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer

local Enabled = false
local TeleportCooldown = false

-- Character cache
local Character, HRP, Humanoid

-- Position tracking
local SafeCFrame = nil
local LastVelocity = Vector3.zero

-- Thresholds
local MAX_VELOCITY = 80
local MAX_ANGULAR = 15

--============ SIMPLE GUI ============--

local Gui = Instance.new("ScreenGui")
Gui.Name = "AntiFling"
Gui.ResetOnSpawn = false
Gui.Parent = LocalPlayer:WaitForChild("PlayerGui")

local Button = Instance.new("TextButton")
Button.Size = UDim2.new(0, 55, 0, 22)
Button.Position = UDim2.new(0, 8, 0.5, -11)
Button.BackgroundColor3 = Color3.fromRGB(35, 35, 40)
Button.TextColor3 = Color3.fromRGB(255, 255, 255)
Button.Text = "AF"
Button.TextSize = 12
Button.Font = Enum.Font.GothamBold
Button.BorderSizePixel = 0
Button.Active = true
Button.Draggable = true
Button.Parent = Gui
Instance.new("UICorner", Button).CornerRadius = UDim.new(0, 4)

--============ CORE PROTECTION ============--

-- This is the SECRET: We make YOUR parts immune to external forces
local function ProtectCharacter(char)
    if not char then return end
    
    for _, part in pairs(char:GetDescendants()) do
        if part:IsA("BasePart") then
            -- Make parts very heavy (can't be pushed)
            part.CustomPhysicalProperties = PhysicalProperties.new(
                100,  -- High density
                0.3,  -- Low friction  
                0,    -- No elasticity (no bounce)
                1,    -- Friction weight
                0     -- Elasticity weight
            )
        end
    end
    
    -- Also protect new parts added to character
    char.DescendantAdded:Connect(function(part)
        if part:IsA("BasePart") and Enabled then
            part.CustomPhysicalProperties = PhysicalProperties.new(100, 0.3, 0, 1, 0)
        end
    end)
end

-- Make other players' parts not collide with you
local function NoclipPlayer(player)
    if player == LocalPlayer then return end
    
    local char = player.Character
    if not char then return end
    
    for _, part in pairs(char:GetDescendants()) do
        if part:IsA("BasePart") then
            part.CanCollide = false
        end
    end
end

local function NoclipAllPlayers()
    for _, player in pairs(Players:GetPlayers()) do
        NoclipPlayer(player)
    end
end

--============ CHARACTER SETUP ============--

local function Setup(char)
    Character = char
    HRP = char:WaitForChild("HumanoidRootPart", 5)
    Humanoid = char:WaitForChild("Humanoid", 5)
    
    if HRP then
        SafeCFrame = HRP.CFrame
        
        if Enabled then
            ProtectCharacter(char)
            NoclipAllPlayers()
        end
    end
end

if LocalPlayer.Character then
    Setup(LocalPlayer.Character)
end

LocalPlayer.CharacterAdded:Connect(function(char)
    task.wait(0.2)
    Setup(char)
end)

--============ PLAYER EVENTS ============--

Players.PlayerAdded:Connect(function(player)
    player.CharacterAdded:Connect(function()
        task.wait(0.3)
        if Enabled then
            NoclipPlayer(player)
        end
    end)
end)

for _, player in pairs(Players:GetPlayers()) do
    if player ~= LocalPlayer then
        player.CharacterAdded:Connect(function()
            task.wait(0.3)
            if Enabled then
                NoclipPlayer(player)
            end
        end)
    end
end

--============ TOGGLE ============--

Button.MouseButton1Click:Connect(function()
    Enabled = not Enabled
    Button.BackgroundColor3 = Enabled and Color3.fromRGB(0, 120, 60) or Color3.fromRGB(35, 35, 40)
    
    if Enabled then
        ProtectCharacter(Character)
        NoclipAllPlayers()
        if HRP then
            SafeCFrame = HRP.CFrame
        end
    end
end)

--============ TELEPORT API ============--

getgenv().AllowTeleport = function()
    TeleportCooldown = true
    task.delay(0.5, function()
        TeleportCooldown = false
        if HRP then
            SafeCFrame = HRP.CFrame
        end
    end)
end

--============ MAIN LOOP (SUPER LIGHT) ============--

local frameSkip = 0

RunService.Heartbeat:Connect(function()
    if not Enabled then return end
    if not HRP or not HRP.Parent then return end
    if TeleportCooldown then
        SafeCFrame = HRP.CFrame
        return
    end
    
    local vel = HRP.AssemblyLinearVelocity
    local ang = HRP.AssemblyAngularVelocity
    local velMag = vel.Magnitude
    local angMag = ang.Magnitude
    
    -- INSTANT spin cancel (runs every frame for responsiveness)
    if angMag > MAX_ANGULAR then
        HRP.AssemblyAngularVelocity = Vector3.zero
    end
    
    -- INSTANT velocity cancel if spinning
    if velMag > MAX_VELOCITY and angMag > 5 then
        HRP.AssemblyLinearVelocity = Vector3.new(
            math.clamp(vel.X, -60, 60),
            math.clamp(vel.Y, -100, 60),
            math.clamp(vel.Z, -60, 60)
        )
    end
    
    -- Skip heavy checks (only every 5 frames)
    frameSkip = frameSkip + 1
    if frameSkip < 5 then return end
    frameSkip = 0
    
    -- Fling detection and recovery
    local isFlung = velMag > 150 or angMag > 30 or (velMag > 100 and angMag > 15)
    
    if isFlung and SafeCFrame then
        HRP.CFrame = SafeCFrame
        HRP.AssemblyLinearVelocity = Vector3.zero
        HRP.AssemblyAngularVelocity = Vector3.zero
        return
    end
    
    -- Update safe position when stable
    if velMag < 50 and angMag < 8 then
        SafeCFrame = HRP.CFrame
        LastVelocity = vel
    end
end)

--============ RING IMMUNITY (THE SECRET!) ============--
--[[
    Instead of detecting rings, we make YOU immune to them.
    This works by:
    1. Making your parts super heavy (can't be pushed)
    2. Instantly canceling any spin (rings spin you)
    3. Instantly canceling extreme velocity
    4. Teleporting back if somehow still flung
    
    NO SCANNING NEEDED = NO LAG!
]]

print("═══════════════════════════════════════")
print("  Anti-Fling v14 - Zero Lag Edition")
print("═══════════════════════════════════════")
print("  ✓ Ring immunity (no scanning!)")
print("  ✓ Player push immunity")
print("  ✓ Teleport compatible")
print("")
print("  Use AllowTeleport() before TP")
print("═══════════════════════════════════════")
