--[[
    Anti-Fling v13 - Ultimate Push & Fling Immunity
    - Immune to ALL player pushing (even while AFK)
    - Immune to ring flings, super rings, spinning parts
    - Teleport compatible (Infinite Yield, etc.)
    - Hold position when AFK
]]

-- Cache services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local PhysicsService = game:GetService("PhysicsService")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer

local Enabled = false
local CollisionGroup = "AntiFlingGroup"

local SafePosition = nil
local SafeCFrame = nil
local LastGroundedPos = nil
local LastValidVelocity = Vector3.zero
local TeleportCooldown = false
local AFKMode = false
local AFKPosition = nil
local LastInputTime = tick()

-- Cache constants
local ZERO_VECTOR = Vector3.zero
local HEAVY_PHYSICS = PhysicalProperties.new(math.huge, 0, 0, 0, 0) -- Immovable
local ANCHOR_PHYSICS = PhysicalProperties.new(100000, 2, 0, 100, 0)

-- Thresholds
local MAX_VELOCITY = 60
local MAX_ANGULAR = 12
local MAX_DISPLACEMENT = 50
local TELEPORT_THRESHOLD = 200
local DANGEROUS_VELOCITY = 50
local DANGEROUS_ANGULAR = 30
local SCAN_RADIUS = 50 -- Increased for ring detection
local AFK_TIMEOUT = 5 -- Seconds before AFK mode activates
local RING_DETECTION_RADIUS = 80 -- Large radius for ring parts

-- Frame counters
local frameCount = 0
local scanCount = 0

-- Storage
local ProcessedParts = {}
local DangerousParts = {}
local NeutralizedObjects = {}
local connections = {}

-- Character references
local HRP, Humanoid, RootJoint, Character

-- Physics group setup
local groupCreated = pcall(function()
    PhysicsService:RegisterCollisionGroup(CollisionGroup)
end)

if groupCreated then
    pcall(function()
        PhysicsService:CollisionGroupSetCollidable(CollisionGroup, "Default", false)
        PhysicsService:CollisionGroupSetCollidable(CollisionGroup, CollisionGroup, false)
    end)
end

--============ GUI SETUP ============--

local Gui = Instance.new("ScreenGui")
Gui.Name = "AntiFlingV13"
Gui.ResetOnSpawn = false
Gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
Gui.Parent = LocalPlayer:WaitForChild("PlayerGui")

local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 70, 0, 50)
MainFrame.Position = UDim2.new(0, 8, 0.5, -25)
MainFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
MainFrame.BorderSizePixel = 0
MainFrame.Active = true
MainFrame.Draggable = true
MainFrame.Parent = Gui
Instance.new("UICorner", MainFrame).CornerRadius = UDim.new(0, 6)

local Button = Instance.new("TextButton")
Button.Size = UDim2.new(1, -8, 0, 20)
Button.Position = UDim2.new(0, 4, 0, 4)
Button.BackgroundColor3 = Color3.fromRGB(35, 35, 40)
Button.TextColor3 = Color3.fromRGB(255, 255, 255)
Button.Text = "AF"
Button.TextSize = 11
Button.Font = Enum.Font.GothamBold
Button.BorderSizePixel = 0
Button.Parent = MainFrame
Instance.new("UICorner", Button).CornerRadius = UDim.new(0, 4)

local AFKIndicator = Instance.new("TextLabel")
AFKIndicator.Size = UDim2.new(1, -8, 0, 16)
AFKIndicator.Position = UDim2.new(0, 4, 0, 28)
AFKIndicator.BackgroundColor3 = Color3.fromRGB(45, 45, 50)
AFKIndicator.TextColor3 = Color3.fromRGB(150, 150, 150)
AFKIndicator.Text = "AFK: OFF"
AFKIndicator.TextSize = 9
AFKIndicator.Font = Enum.Font.Gotham
AFKIndicator.BorderSizePixel = 0
AFKIndicator.Parent = MainFrame
Instance.new("UICorner", AFKIndicator).CornerRadius = UDim.new(0, 3)

-- Colors
local COLOR_ENABLED = Color3.fromRGB(0, 120, 60)
local COLOR_DISABLED = Color3.fromRGB(35, 35, 40)
local COLOR_AFK_ON = Color3.fromRGB(255, 180, 0)
local COLOR_AFK_OFF = Color3.fromRGB(150, 150, 150)

--============ CORE FUNCTIONS ============--

local function ClampVelocity(vel, maxH, minV, maxV)
    return Vector3.new(
        math.clamp(vel.X, -maxH, maxH),
        math.clamp(vel.Y, minV, maxV),
        math.clamp(vel.Z, -maxH, maxH)
    )
end

-- Detect if part is a ring/super ring component
local function IsRingPart(part)
    if not part:IsA("BasePart") then return false end
    
    local name = part.Name:lower()
    local parentName = part.Parent and part.Parent.Name:lower() or ""
    
    -- Check common ring naming patterns
    local ringKeywords = {"ring", "fling", "spin", "rotate", "kill", "death", "trap"}
    for _, keyword in ipairs(ringKeywords) do
        if name:find(keyword) or parentName:find(keyword) then
            return true
        end
    end
    
    -- Check for ring behavior: high angular velocity + moving
    local ang = part.AssemblyAngularVelocity
    local vel = part.AssemblyLinearVelocity
    
    -- Super ring detection: very high spin + orbital movement
    if ang.Magnitude > 20 then
        return true
    end
    
    -- Ring parts typically have high velocity AND angular velocity
    if vel.Magnitude > 40 and ang.Magnitude > 10 then
        return true
    end
    
    -- Check if part has BodyMovers (common in ring scripts)
    for _, child in ipairs(part:GetChildren()) do
        if child:IsA("BodyAngularVelocity") or 
           child:IsA("BodyVelocity") or
           child:IsA("BodyPosition") or
           child:IsA("BodyGyro") or
           child:IsA("AlignPosition") or
           child:IsA("AlignOrientation") or
           child:IsA("LinearVelocity") or
           child:IsA("AngularVelocity") then
            local bodyVel = child:IsA("BodyAngularVelocity") and child.AngularVelocity.Magnitude or 0
            if bodyVel > 10 then
                return true
            end
        end
    end
    
    return false
end

local function IsPartDangerous(part)
    if not part:IsA("BasePart") then return false end
    if part.Anchored then return false end
    if Character and part:IsDescendantOf(Character) then return false end
    
    -- Check if part belongs to any player's character
    for _, player in ipairs(Players:GetPlayers()) do
        if player.Character and part:IsDescendantOf(player.Character) then
            return false -- Handled separately
        end
    end
    
    -- Ring detection (priority)
    if IsRingPart(part) then
        return true
    end
    
    local vel = part.AssemblyLinearVelocity
    local ang = part.AssemblyAngularVelocity
    local velMag = vel.Magnitude
    local angMag = ang.Magnitude
    
    -- Fast moving part
    if velMag > DANGEROUS_VELOCITY then
        return true
    end
    
    -- Spinning part
    if angMag > DANGEROUS_ANGULAR then
        return true
    end
    
    -- Combined threat
    if velMag > 30 and angMag > 15 then
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
        -- Apply collision group
        if groupCreated then
            part.CollisionGroup = CollisionGroup
        end
        
        -- Disable all collision/touch
        part.CanCollide = false
        part.CanTouch = false
        
        -- Disable BodyMovers on dangerous parts
        for _, child in ipairs(part:GetChildren()) do
            if child:IsA("BodyMover") or 
               child:IsA("BodyAngularVelocity") or
               child:IsA("BodyVelocity") then
                pcall(function()
                    child.MaxForce = ZERO_VECTOR
                    child.MaxTorque = ZERO_VECTOR
                end)
            end
            if child:IsA("Constraint") then
                pcall(function()
                    child.Enabled = false
                end)
            end
        end
    end)
end

local function NeutralizeRingCompletely(part)
    if not part or not part.Parent then return end
    if NeutralizedObjects[part] then return end
    
    NeutralizedObjects[part] = true
    
    pcall(function()
        -- Disable the part completely
        part.CanCollide = false
        part.CanTouch = false
        part.Massless = true
        
        if groupCreated then
            part.CollisionGroup = CollisionGroup
        end
        
        -- Kill all physics on the part
        part.AssemblyLinearVelocity = ZERO_VECTOR
        part.AssemblyAngularVelocity = ZERO_VECTOR
        
        -- Disable all BodyMovers and Constraints
        for _, child in ipairs(part:GetDescendants()) do
            if child:IsA("BodyAngularVelocity") then
                child.AngularVelocity = ZERO_VECTOR
                child.MaxTorque = ZERO_VECTOR
            elseif child:IsA("BodyVelocity") then
                child.Velocity = ZERO_VECTOR
                child.MaxForce = ZERO_VECTOR
            elseif child:IsA("BodyPosition") then
                child.MaxForce = ZERO_VECTOR
            elseif child:IsA("BodyGyro") then
                child.MaxTorque = ZERO_VECTOR
            elseif child:IsA("BodyForce") then
                child.Force = ZERO_VECTOR
            elseif child:IsA("BodyThrust") then
                child.Force = ZERO_VECTOR
            elseif child:IsA("LinearVelocity") then
                child.MaxForce = 0
                child.VectorVelocity = ZERO_VECTOR
            elseif child:IsA("AngularVelocity") then
                child.MaxTorque = 0
                child.AngularVelocity = ZERO_VECTOR
            elseif child:IsA("AlignPosition") then
                child.MaxForce = 0
            elseif child:IsA("AlignOrientation") then
                child.MaxTorque = 0
            elseif child:IsA("Constraint") then
                child.Enabled = false
            end
        end
    end)
end

-- Pre-create scan params
local scanParams = OverlapParams.new()
scanParams.FilterType = Enum.RaycastFilterType.Exclude

local function ScanNearbyParts()
    if not HRP or not HRP.Parent then return end
    
    -- Extended radius scan for rings
    local parts = Workspace:GetPartBoundsInRadius(HRP.Position, RING_DETECTION_RADIUS, scanParams)
    
    for i = 1, #parts do
        local part = parts[i]
        if part:IsA("BasePart") and not ProcessedParts[part] then
            -- Priority: Ring detection
            if IsRingPart(part) then
                NeutralizeRingCompletely(part)
                ProcessedParts[part] = true
            elseif IsPartDangerous(part) then
                NeutralizePart(part)
            end
        end
    end
end

local function SetCharacterCollision(char, enabled)
    if not char then return end
    
    local descendants = char:GetDescendants()
    for i = 1, #descendants do
        local part = descendants[i]
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
    
    local conn = char.DescendantAdded:Connect(function(part)
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
    connections[#connections + 1] = conn
end

local function ApplyToAllPlayers()
    local players = Players:GetPlayers()
    for i = 1, #players do
        local player = players[i]
        if player ~= LocalPlayer and player.Character then
            SetCharacterCollision(player.Character, Enabled)
        end
    end
end

local function SetupCharacterProtection(char)
    if not char then return end
    
    local descendants = char:GetDescendants()
    for i = 1, #descendants do
        local part = descendants[i]
        if part:IsA("BasePart") then
            part.CustomPhysicalProperties = HEAVY_PHYSICS
        end
    end
    
    local conn = char.DescendantAdded:Connect(function(part)
        if part:IsA("BasePart") and Enabled then
            part.CustomPhysicalProperties = HEAVY_PHYSICS
        end
    end)
    connections[#connections + 1] = conn
end

--============ AFK PROTECTION ============--

local function UpdateAFKStatus()
    if not Enabled then return end
    
    local timeSinceInput = tick() - LastInputTime
    local wasAFK = AFKMode
    
    AFKMode = timeSinceInput > AFK_TIMEOUT
    
    if AFKMode ~= wasAFK then
        if AFKMode then
            -- Just went AFK - save position
            if HRP then
                AFKPosition = HRP.CFrame
            end
            AFKIndicator.Text = "AFK: ON"
            AFKIndicator.TextColor3 = COLOR_AFK_ON
        else
            -- No longer AFK
            AFKPosition = nil
            AFKIndicator.Text = "AFK: OFF"
            AFKIndicator.TextColor3 = COLOR_AFK_OFF
        end
    end
end

local function LockAFKPosition()
    if not AFKMode or not AFKPosition or not HRP then return end
    if TeleportCooldown then return end
    
    -- Keep player locked in place
    local currentPos = HRP.Position
    local afkPos = AFKPosition.Position
    local displacement = (currentPos - afkPos).Magnitude
    
    -- If moved more than tiny amount, snap back
    if displacement > 0.5 then
        HRP.CFrame = AFKPosition
        HRP.AssemblyLinearVelocity = ZERO_VECTOR
        HRP.AssemblyAngularVelocity = ZERO_VECTOR
    end
end

-- Track user input for AFK detection
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    LastInputTime = tick()
end)

UserInputService.InputEnded:Connect(function(input)
    LastInputTime = tick()
end)

--============ CHARACTER SETUP ============--

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
        scanParams.FilterDescendantsInstances = {char}
        
        -- Teleport detection
        local conn = HRP:GetPropertyChangedSignal("CFrame"):Connect(function()
            if Enabled and HRP then
                local newPos = HRP.Position
                local vel = HRP.AssemblyLinearVelocity
                
                -- Large instant movement with low velocity = teleport
                if SafePosition and (newPos - SafePosition).Magnitude > 50 and vel.Magnitude < 30 then
                    TeleportCooldown = true
                    SafePosition = newPos
                    SafeCFrame = HRP.CFrame
                    LastGroundedPos = newPos
                    
                    -- Update AFK position if teleported
                    if AFKMode then
                        AFKPosition = HRP.CFrame
                    end
                    
                    task.delay(0.5, function()
                        TeleportCooldown = false
                    end)
                end
            end
        end)
        connections[#connections + 1] = conn
    end
end

if LocalPlayer.Character then
    Setup(LocalPlayer.Character)
end

LocalPlayer.CharacterAdded:Connect(function(char)
    task.wait(0.1)
    Setup(char)
end)

--============ PLAYER EVENTS ============--

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

--============ BUTTON ============--

Button.MouseButton1Click:Connect(function()
    Enabled = not Enabled
    Button.BackgroundColor3 = Enabled and COLOR_ENABLED or COLOR_DISABLED
    ApplyToAllPlayers()
    
    if Enabled and HRP then
        SafePosition = HRP.Position
        SafeCFrame = HRP.CFrame
        LastGroundedPos = HRP.Position
        SetupCharacterProtection(Character)
    end
    
    if not Enabled then
        AFKMode = false
        AFKPosition = nil
        AFKIndicator.Text = "AFK: OFF"
        AFKIndicator.TextColor3 = COLOR_AFK_OFF
    end
    
    table.clear(ProcessedParts)
    table.clear(DangerousParts)
    table.clear(NeutralizedObjects)
end)

--============ TELEPORT API ============--

getgenv().AllowTeleport = function()
    TeleportCooldown = true
    
    -- Also reset AFK position after teleport
    task.delay(0.5, function()
        TeleportCooldown = false
        if HRP then
            SafePosition = HRP.Position
            SafeCFrame = HRP.CFrame
            if AFKMode then
                AFKPosition = HRP.CFrame
            end
        end
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

-- Hook for Infinite Yield and other teleport scripts
getgenv().AFKTeleport = function(targetCFrame)
    TeleportCooldown = true
    
    if HRP then
        HRP.CFrame = targetCFrame
        SafePosition = targetCFrame.Position
        SafeCFrame = targetCFrame
        
        if AFKMode then
            AFKPosition = targetCFrame
        end
    end
    
    task.delay(0.5, function()
        TeleportCooldown = false
    end)
end

--============ FLING DETECTION ============--

local function IsFlung()
    if not HRP then return false end
    
    local vel = HRP.AssemblyLinearVelocity
    local ang = HRP.AssemblyAngularVelocity
    local velMag = vel.Magnitude
    local angMag = ang.Magnitude
    
    return (velMag > 80 and angMag > 15) or velMag > 150 or angMag > 40
end

local function CleanupProcessedParts()
    for part in pairs(ProcessedParts) do
        if not part or not part.Parent then
            ProcessedParts[part] = nil
            DangerousParts[part] = nil
        end
    end
    for part in pairs(NeutralizedObjects) do
        if not part or not part.Parent then
            NeutralizedObjects[part] = nil
        end
    end
end

--============ MAIN LOOPS ============--

RunService.Heartbeat:Connect(function(dt)
    if not Enabled then return end
    if not HRP or not HRP.Parent then return end
    if Humanoid and Humanoid.Health <= 0 then return end
    
    -- Update AFK status
    UpdateAFKStatus()
    
    -- Scan every 3 frames (more frequent for ring detection)
    scanCount = scanCount + 1
    if scanCount >= 3 then
        scanCount = 0
        ScanNearbyParts()
    end
    
    -- Cleanup every 100 frames
    frameCount = frameCount + 1
    if frameCount >= 100 then
        frameCount = 0
        CleanupProcessedParts()
    end
    
    -- AFK position lock
    if AFKMode then
        LockAFKPosition()
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
            HRP.AssemblyLinearVelocity = ClampVelocity(vel, MAX_VELOCITY, -120, 80)
            LastValidVelocity = HRP.AssemblyLinearVelocity
        else
            LastValidVelocity = vel
        end
    else
        LastValidVelocity = vel
    end
    
    -- Instant angular correction
    if angMag > MAX_ANGULAR then
        HRP.AssemblyAngularVelocity = ZERO_VECTOR
    end
    
    -- Teleport protection
    if SafePosition then
        local displacement = (pos - SafePosition).Magnitude
        
        if displacement > TELEPORT_THRESHOLD then
            if IsFlung() then
                HRP.CFrame = SafeCFrame
                HRP.AssemblyLinearVelocity = ZERO_VECTOR
                HRP.AssemblyAngularVelocity = ZERO_VECTOR
                return
            else
                SafePosition = pos
                SafeCFrame = HRP.CFrame
            end
        end
        
        -- Displacement protection
        local expectedDisplacement = velMag * dt * 2
        if displacement > MAX_DISPLACEMENT and displacement > expectedDisplacement + 30 then
            if IsFlung() then
                HRP.CFrame = SafeCFrame
                HRP.AssemblyLinearVelocity = LastValidVelocity * 0.3
                HRP.AssemblyAngularVelocity = ZERO_VECTOR
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
    if not Enabled or not HRP or not HRP.Parent then return end
    if Humanoid and Humanoid.Health <= 0 then return end
    if TeleportCooldown then return end
    
    local vel = HRP.AssemblyLinearVelocity
    local ang = HRP.AssemblyAngularVelocity
    local angMag = ang.Magnitude
    local velMag = vel.Magnitude
    
    -- Instant spin cancel
    if angMag > MAX_ANGULAR then
        HRP.AssemblyAngularVelocity = ZERO_VECTOR
    end
    
    -- Instant extreme velocity cancel
    if velMag > MAX_VELOCITY * 1.5 and IsFlung() then
        HRP.AssemblyLinearVelocity = ClampVelocity(vel, MAX_VELOCITY, -100, 60)
        HRP.AssemblyAngularVelocity = ZERO_VECTOR
    end
end)

RunService.Stepped:Connect(function()
    if not Enabled or not HRP or not HRP.Parent then return end
    if Humanoid and Humanoid.Health <= 0 then return end
    if TeleportCooldown then return end
    
    local ang = HRP.AssemblyAngularVelocity
    if ang.Magnitude > MAX_ANGULAR * 2 then
        HRP.AssemblyAngularVelocity = ZERO_VECTOR
    end
    
    local vel = HRP.AssemblyLinearVelocity
    if vel.Magnitude > MAX_VELOCITY * 2.5 then
        HRP.AssemblyLinearVelocity = ClampVelocity(vel, MAX_VELOCITY, -100, 60)
    end
end)

--============ STARTUP ============--

print("═══════════════════════════════════════════")
print("  Anti-Fling v13 - Ultimate Protection")
print("═══════════════════════════════════════════")
print("✓ Push immunity (even while AFK)")
print("✓ Ring/Super Ring immunity")
print("✓ Spinning part immunity")
print("✓ Teleport compatible")
print("")
print("Commands:")
print("  AllowTeleport() - Call before teleporting")
print("  AFKTeleport(CFrame) - Teleport while AFK")
print("")
print("AFK Mode activates after " .. AFK_TIMEOUT .. " seconds of no input")
print("═══════════════════════════════════════════")
