--[[
    Anti-Fling v12 - Ultimate Protection
    Immune to ALL flings including spinning parts/rings
    Teleport compatible
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer

local Enabled = false
local CollisionGroup = "AntiFlingGroup"

local SafePosition = nil
local SafeCFrame = nil
local LastGroundedPos = nil
local LastValidVelocity = Vector3.zero
local TeleportCooldown = false

local PhysicsService = game:GetService("PhysicsService")
local groupCreated = pcall(function()
    PhysicsService:RegisterCollisionGroup(CollisionGroup)
end)

if groupCreated then
    pcall(function()
        PhysicsService:CollisionGroupSetCollidable(CollisionGroup, "Default", false)
        PhysicsService:CollisionGroupSetCollidable(CollisionGroup, CollisionGroup, false)
    end)
end

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

-- Store dangerous parts we already processed
local ProcessedParts = {}
local DangerousParts = {}

local function SetCharacterCollision(char, enabled)
    if not char then return end
    for _, part in ipairs(char:GetDescendants()) do
        if part:IsA("BasePart") then
            if enabled then
                if groupCreated then
                    pcall(function()
                        part.CollisionGroup = CollisionGroup
                    end)
                end
                part.CanCollide = false
                part.CanTouch = false
                part.Massless = true
            end
        end
    end
    char.DescendantAdded:Connect(function(part)
        if part:IsA("BasePart") and Enabled then
            if groupCreated then
                pcall(function()
                    part.CollisionGroup = CollisionGroup
                end)
            end
            part.CanCollide = false
            part.CanTouch = false
            part.Massless = true
        end
    end)
end

local function ApplyToAllPlayers()
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character then
            SetCharacterCollision(player.Character, Enabled)
        end
    end
end

local function OnCharacterAdded(player, char)
    task.wait(0.2)
    if player ~= LocalPlayer and Enabled then
        SetCharacterCollision(char, true)
    end
end

for _, player in ipairs(Players:GetPlayers()) do
    if player ~= LocalPlayer then
        player.CharacterAdded:Connect(function(char)
            OnCharacterAdded(player, char)
        end)
    end
end

Players.PlayerAdded:Connect(function(player)
    player.CharacterAdded:Connect(function(char)
        OnCharacterAdded(player, char)
    end)
end)

local HRP, Humanoid, RootJoint, Character

local function SetupCharacterProtection(char)
    if not char then return end
    
    -- Make your own parts unable to be pushed
    for _, part in ipairs(char:GetDescendants()) do
        if part:IsA("BasePart") then
            part.CustomPhysicalProperties = PhysicalProperties.new(
                100,    -- Density (heavy so hard to push)
                0,      -- Friction
                0,      -- Elasticity (no bounce)
                0,      -- FrictionWeight
                0       -- ElasticityWeight
            )
        end
    end
    
    char.DescendantAdded:Connect(function(part)
        if part:IsA("BasePart") and Enabled then
            part.CustomPhysicalProperties = PhysicalProperties.new(100, 0, 0, 0, 0)
        end
    end)
end

local function Setup(char)
    Character = char
    HRP = char:WaitForChild("HumanoidRootPart", 5)
    Humanoid = char:WaitForChild("Humanoid", 5)
    local torso = char:FindFirstChild("Torso") or char:FindFirstChild("UpperTorso")
    if torso then
        RootJoint = torso:FindFirstChild("RootJoint") or torso:FindFirstChild("Root")
    end
    if HRP then
        SafePosition = HRP.Position
        SafeCFrame = HRP.CFrame
        LastGroundedPos = HRP.Position
        
        SetupCharacterProtection(char)
        
        HRP:GetPropertyChangedSignal("CFrame"):Connect(function()
            if Enabled and HRP then
                local newPos = HRP.Position
                local vel = HRP.AssemblyLinearVelocity
                if SafePosition and (newPos - SafePosition).Magnitude > 50 and vel.Magnitude < 30 then
                    TeleportCooldown = true
                    SafePosition = newPos
                    SafeCFrame = HRP.CFrame
                    LastGroundedPos = newPos
                    task.delay(0.5, function()
                        TeleportCooldown = false
                    end)
                end
            end
        end)
    end
end

if LocalPlayer.Character then
    Setup(LocalPlayer.Character)
end

LocalPlayer.CharacterAdded:Connect(function(char)
    task.wait(0.1)
    Setup(char)
end)

Button.MouseButton1Click:Connect(function()
    Enabled = not Enabled
    Button.BackgroundColor3 = Enabled and Color3.fromRGB(0, 120, 60) or Color3.fromRGB(35, 35, 40)
    ApplyToAllPlayers()
    if Enabled and HRP then
        SafePosition = HRP.Position
        SafeCFrame = HRP.CFrame
        LastGroundedPos = HRP.Position
        SetupCharacterProtection(Character)
    end
    
    -- Clear processed parts when toggling
    ProcessedParts = {}
    DangerousParts = {}
end)

getgenv().AllowTeleport = function()
    TeleportCooldown = true
    task.delay(0.5, function()
        TeleportCooldown = false
    end)
    if HRP then
        task.delay(0.1, function()
            if HRP then
                SafePosition = HRP.Position
                SafeCFrame = HRP.CFrame
            end
        end)
    end
end

local MAX_VELOCITY = 60
local MAX_ANGULAR = 12
local MAX_DISPLACEMENT = 50
local TELEPORT_THRESHOLD = 200
local DANGEROUS_VELOCITY = 50
local DANGEROUS_ANGULAR = 30
local SCAN_RADIUS = 35
local frameCount = 0
local scanCount = 0

local function IsFlung()
    if not HRP then return false end
    local vel = HRP.AssemblyLinearVelocity
    local ang = HRP.AssemblyAngularVelocity
    if vel.Magnitude > 80 and ang.Magnitude > 15 then
        return true
    end
    if vel.Magnitude > 150 then
        return true
    end
    if ang.Magnitude > 40 then
        return true
    end
    return false
end

local function IsPartDangerous(part)
    if not part:IsA("BasePart") then return false end
    if part.Anchored then return false end
    if part:IsDescendantOf(Character) then return false end
    
    -- Check if part belongs to any player's character
    for _, player in ipairs(Players:GetPlayers()) do
        if player.Character and part:IsDescendantOf(player.Character) then
            return false -- Already handled by player noclip
        end
    end
    
    local vel = part.AssemblyLinearVelocity
    local ang = part.AssemblyAngularVelocity
    
    -- Fast moving part
    if vel.Magnitude > DANGEROUS_VELOCITY then
        return true
    end
    
    -- Spinning part (ring fling)
    if ang.Magnitude > DANGEROUS_ANGULAR then
        return true
    end
    
    -- Part with high velocity AND spinning
    if vel.Magnitude > 30 and ang.Magnitude > 15 then
        return true
    end
    
    return false
end

local function NeutralizePart(part)
    if not part or not part.Parent then return end
    if ProcessedParts[part] then return end
    
    ProcessedParts[part] = true
    DangerousParts[part] = true
    
    pcall(function()
        if groupCreated then
            part.CollisionGroup = CollisionGroup
        end
        part.CanCollide = false
        part.CanTouch = false
    end)
end

local function ScanNearbyParts()
    if not HRP or not HRP.Parent then return end
    
    local pos = HRP.Position
    local params = OverlapParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {Character}
    
    local parts = Workspace:GetPartBoundsInRadius(pos, SCAN_RADIUS, params)
    
    for _, part in ipairs(parts) do
        if not ProcessedParts[part] then
            if IsPartDangerous(part) then
                NeutralizePart(part)
            end
        end
    end
end

local function CleanupProcessedParts()
    for part, _ in pairs(ProcessedParts) do
        if not part or not part.Parent then
            ProcessedParts[part] = nil
            DangerousParts[part] = nil
        end
    end
end

RunService.Heartbeat:Connect(function(dt)
    if not Enabled then return end
    if not HRP or not HRP.Parent then return end
    if Humanoid and Humanoid.Health <= 0 then return end
    
    -- Scan for dangerous parts every 5 frames
    scanCount = scanCount + 1
    if scanCount >= 5 then
        scanCount = 0
        ScanNearbyParts()
    end
    
    -- Cleanup every 100 frames
    frameCount = frameCount + 1
    if frameCount >= 100 then
        frameCount = 0
        CleanupProcessedParts()
    end
    
    if TeleportCooldown then
        SafePosition = HRP.Position
        SafeCFrame = HRP.CFrame
        return
    end
    
    local vel = HRP.AssemblyLinearVelocity
    local ang = HRP.AssemblyAngularVelocity
    local pos = HRP.Position
    local velMag = vel.Magnitude
    local angMag = ang.Magnitude
    
    -- Instant velocity correction
    if velMag > MAX_VELOCITY then
        if angMag > 5 or velMag > 100 then
            HRP.AssemblyLinearVelocity = Vector3.new(
                math.clamp(vel.X, -MAX_VELOCITY, MAX_VELOCITY),
                math.clamp(vel.Y, -120, 80),
                math.clamp(vel.Z, -MAX_VELOCITY, MAX_VELOCITY)
            )
            LastValidVelocity = HRP.AssemblyLinearVelocity
        else
            LastValidVelocity = vel
        end
    else
        LastValidVelocity = vel
    end
    
    -- Instant angular correction
    if angMag > MAX_ANGULAR then
        HRP.AssemblyAngularVelocity = Vector3.zero
    end
    
    -- Teleport protection
    if SafePosition and (pos - SafePosition).Magnitude > TELEPORT_THRESHOLD then
        if IsFlung() then
            HRP.CFrame = SafeCFrame
            HRP.AssemblyLinearVelocity = Vector3.zero
            HRP.AssemblyAngularVelocity = Vector3.zero
            return
        else
            SafePosition = pos
            SafeCFrame = HRP.CFrame
        end
    end
    
    -- Displacement protection
    if SafePosition then
        local displacement = (pos - SafePosition).Magnitude
        local expectedDisplacement = velMag * dt * 2
        if displacement > MAX_DISPLACEMENT and displacement > expectedDisplacement + 30 then
            if IsFlung() then
                HRP.CFrame = SafeCFrame
                HRP.AssemblyLinearVelocity = LastValidVelocity * 0.3
                HRP.AssemblyAngularVelocity = Vector3.zero
                return
            else
                SafePosition = pos
                SafeCFrame = HRP.CFrame
            end
        end
    end
    
    -- Update safe position when stable
    if velMag < MAX_VELOCITY and angMag < MAX_ANGULAR then
        SafePosition = pos
        SafeCFrame = HRP.CFrame
        if Humanoid and Humanoid.FloorMaterial ~= Enum.Material.Air then
            LastGroundedPos = pos
        end
    end
end)

RunService.RenderStepped:Connect(function()
    if not Enabled then return end
    if not HRP or not HRP.Parent then return end
    if Humanoid and Humanoid.Health <= 0 then return end
    if TeleportCooldown then return end
    
    local vel = HRP.AssemblyLinearVelocity
    local ang = HRP.AssemblyAngularVelocity
    
    -- Instant spin cancel
    if ang.Magnitude > MAX_ANGULAR then
        HRP.AssemblyAngularVelocity = Vector3.zero
    end
    
    -- Instant extreme velocity cancel
    if vel.Magnitude > MAX_VELOCITY * 1.5 then
        if IsFlung() then
            HRP.AssemblyLinearVelocity = Vector3.new(
                math.clamp(vel.X, -MAX_VELOCITY, MAX_VELOCITY),
                math.clamp(vel.Y, -100, 60),
                math.clamp(vel.Z, -MAX_VELOCITY, MAX_VELOCITY)
            )
            HRP.AssemblyAngularVelocity = Vector3.zero
        end
    end
end)

-- Extra protection: Stepped runs before physics
RunService.Stepped:Connect(function()
    if not Enabled then return end
    if not HRP or not HRP.Parent then return end
    if Humanoid and Humanoid.Health <= 0 then return end
    if TeleportCooldown then return end
    
    local ang = HRP.AssemblyAngularVelocity
    if ang.Magnitude > MAX_ANGULAR * 2 then
        HRP.AssemblyAngularVelocity = Vector3.zero
    end
    
    local vel = HRP.AssemblyLinearVelocity
    if vel.Magnitude > MAX_VELOCITY * 2.5 then
        HRP.AssemblyLinearVelocity = Vector3.new(
            math.clamp(vel.X, -MAX_VELOCITY, MAX_VELOCITY),
            math.clamp(vel.Y, -100, 60),
            math.clamp(vel.Z, -MAX_VELOCITY, MAX_VELOCITY)
        )
    end
end)

print("[Anti-Fling v12] Loaded - Full protection against all flings!")
print("Tip: Teleports auto-detected. If blocked, run: AllowTeleport()")
