--[[
    Anti-Fling v11 - Maximum Protection + Teleport Compatible
    Immune to all fling types, allows intentional teleports
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
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

local HRP, Humanoid, RootJoint

local function Setup(char)
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
        
        -- Detect intentional teleports by hooking CFrame changes
        HRP:GetPropertyChangedSignal("CFrame"):Connect(function()
            if Enabled and HRP then
                local newPos = HRP.Position
                local vel = HRP.AssemblyLinearVelocity
                
                -- If position changed but velocity is low = intentional teleport
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
    end
end)

-- Global function to allow teleports from other scripts
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
local frameCount = 0

local function IsFlung()
    if not HRP then return false end
    local vel = HRP.AssemblyLinearVelocity
    local ang = HRP.AssemblyAngularVelocity
    -- Fling = high velocity + high angular (spinning while moving fast)
    if vel.Magnitude > 100 and ang.Magnitude > 20 then
        return true
    end
    -- Or extreme velocity alone
    if vel.Magnitude > 200 then
        return true
    end
    return false
end

RunService.Heartbeat:Connect(function(dt)
    if not Enabled then return end
    if not HRP or not HRP.Parent then return end
    if Humanoid and Humanoid.Health <= 0 then return end
    if TeleportCooldown then
        -- Update safe position during cooldown
        SafePosition = HRP.Position
        SafeCFrame = HRP.CFrame
        return
    end
    
    local vel = HRP.AssemblyLinearVelocity
    local ang = HRP.AssemblyAngularVelocity
    local pos = HRP.Position
    local velMag = vel.Magnitude
    local angMag = ang.Magnitude
    
    -- Only snap back if actually being flung (high velocity + spinning)
    if SafePosition and (pos - SafePosition).Magnitude > TELEPORT_THRESHOLD then
        if IsFlung() then
            HRP.CFrame = SafeCFrame
            HRP.AssemblyLinearVelocity = Vector3.zero
            HRP.AssemblyAngularVelocity = Vector3.zero
            return
        else
            -- Intentional teleport, update safe position
            SafePosition = pos
            SafeCFrame = HRP.CFrame
        end
    end
    
    if velMag > MAX_VELOCITY then
        -- Only clamp if also spinning (fling signature)
        if angMag > 5 or velMag > 150 then
            local clampedVel = Vector3.new(
                math.clamp(vel.X, -MAX_VELOCITY, MAX_VELOCITY),
                math.clamp(vel.Y, -120, 80),
                math.clamp(vel.Z, -MAX_VELOCITY, MAX_VELOCITY)
            )
            HRP.AssemblyLinearVelocity = clampedVel
            LastValidVelocity = clampedVel
        else
            LastValidVelocity = vel
        end
    else
        LastValidVelocity = vel
    end
    
    if angMag > MAX_ANGULAR then
        HRP.AssemblyAngularVelocity = Vector3.zero
    end
    
    if SafePosition then
        local displacement = (pos - SafePosition).Magnitude
        local expectedDisplacement = velMag * dt * 2
        if displacement > MAX_DISPLACEMENT and displacement > expectedDisplacement + 30 then
            if IsFlung() then
                HRP.CFrame = SafeCFrame
                HRP.AssemblyLinearVelocity = LastValidVelocity * 0.5
                HRP.AssemblyAngularVelocity = Vector3.zero
                return
            else
                SafePosition = pos
                SafeCFrame = HRP.CFrame
            end
        end
    end
    
    frameCount = frameCount + 1
    if frameCount >= 3 then
        frameCount = 0
        if velMag < MAX_VELOCITY and angMag < MAX_ANGULAR then
            SafePosition = pos
            SafeCFrame = HRP.CFrame
            if Humanoid and Humanoid.FloorMaterial ~= Enum.Material.Air then
                LastGroundedPos = pos
            end
        end
    end
end)

RunService.RenderStepped:Connect(function()
    if not Enabled then return end
    if not HRP or not HRP.Parent then return end
    if Humanoid and Humanoid.Health <= 0 then return end
    if TeleportCooldown then return end
    
    local ang = HRP.AssemblyAngularVelocity
    if ang.Magnitude > MAX_ANGULAR * 1.5 then
        HRP.AssemblyAngularVelocity = Vector3.zero
    end
    
    local vel = HRP.AssemblyLinearVelocity
    if vel.Magnitude > MAX_VELOCITY * 2 then
        if IsFlung() then
            HRP.AssemblyLinearVelocity = Vector3.new(
                math.clamp(vel.X, -MAX_VELOCITY, MAX_VELOCITY),
                math.clamp(vel.Y, -100, 60),
                math.clamp(vel.Z, -MAX_VELOCITY, MAX_VELOCITY)
            )
        end
    end
end)

print("[Anti-Fling v11] Loaded - Teleport compatible!")
print("Tip: Teleports are auto-detected. If issues occur, run: AllowTeleport()")
