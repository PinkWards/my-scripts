-- [ Anti-TPUA v7 | Reactive Protection ] --
-- Parts are normal UNTIL they attack you

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer

-- [ State ] --
local LastPosition = nil
local LastMoveTime = 0
local BlockCount = 0
local SafeCFrame = nil
local AttackingParts = {} -- Parts currently attacking

-- [ GUI ] --
local Gui = Instance.new("ScreenGui")
Gui.Name = "AntiTPUA_v7"
Gui.ResetOnSpawn = false
Gui.Parent = LocalPlayer:WaitForChild("PlayerGui")

local Box = Instance.new("Frame")
Box.Size = UDim2.new(0, 90, 0, 40)
Box.Position = UDim2.new(0, 5, 0, 5)
Box.BackgroundColor3 = Color3.new(0, 0, 0)
Box.BackgroundTransparency = 0.5
Box.BorderSizePixel = 0
Box.Parent = Gui

Instance.new("UICorner", Box).CornerRadius = UDim.new(0, 6)

local Dot = Instance.new("Frame")
Dot.Size = UDim2.new(0, 8, 0, 8)
Dot.Position = UDim2.new(0, 6, 0, 6)
Dot.BackgroundColor3 = Color3.new(0, 1, 0)
Dot.BorderSizePixel = 0
Dot.Parent = Box

Instance.new("UICorner", Dot).CornerRadius = UDim.new(1, 0)

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, -20, 0, 16)
Title.Position = UDim2.new(0, 18, 0, 2)
Title.BackgroundTransparency = 1
Title.Text = "AntiTPUA v7"
Title.TextColor3 = Color3.new(1, 1, 1)
Title.TextSize = 10
Title.Font = Enum.Font.GothamBold
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Parent = Box

local Counter = Instance.new("TextLabel")
Counter.Size = UDim2.new(1, -10, 0, 14)
Counter.Position = UDim2.new(0, 6, 0, 20)
Counter.BackgroundTransparency = 1
Counter.Text = "Blocked: 0"
Counter.TextColor3 = Color3.new(1, 0.6, 0)
Counter.TextSize = 10
Counter.Font = Enum.Font.Gotham
Counter.TextXAlignment = Enum.TextXAlignment.Left
Counter.Parent = Box

local function Flash()
    Dot.BackgroundColor3 = Color3.new(1, 0, 0)
    task.delay(0.1, function()
        Dot.BackgroundColor3 = Color3.new(0, 1, 0)
    end)
end

-- [ Check if part belongs to any player ] --
local function IsCharacterPart(part)
    for _, player in pairs(Players:GetPlayers()) do
        if player.Character and part:IsDescendantOf(player.Character) then
            return true, player
        end
    end
    return false, nil
end

-- [ Detect if part is ATTACKING you ] --
local function IsAttacking(part, myPos, myVel)
    if part.Anchored then return false end
    
    local isChar, owner = IsCharacterPart(part)
    if isChar and owner == LocalPlayer then return false end
    
    local partPos = part.Position
    local partVel = part.AssemblyLinearVelocity
    local partSpin = part.AssemblyAngularVelocity.Magnitude
    local speed = partVel.Magnitude
    local distance = (partPos - myPos).Magnitude
    
    -- Too far = not a threat
    if distance > 30 then return false end
    
    -- Not moving = not attacking
    if speed < 30 and partSpin < 10 then return false end
    
    -- ATTACK SIGNATURES:
    
    -- 1. Super Ring: Spinning fast near you
    if partSpin > 15 and distance < 20 then
        return true
    end
    
    -- 2. TPUA: Moving very fast near you
    if speed > 80 and distance < 25 then
        return true
    end
    
    -- 3. Direct hit: Moving toward you fast
    if speed > 40 then
        local toPlayer = (myPos - partPos).Unit
        local moveDir = partVel.Unit
        local dot = toPlayer:Dot(moveDir)
        
        -- Moving toward you
        if dot > 0.4 then
            return true
        end
    end
    
    -- 4. Very close + any movement = probably attack
    if distance < 8 and speed > 20 then
        return true
    end
    
    return false
end

-- [ Neutralize attacking part ] --
local function NeutralizePart(part)
    if AttackingParts[part] then return end
    AttackingParts[part] = true
    
    -- Make it pass through you
    part.CanCollide = false
    part.CanTouch = false
    part.AssemblyLinearVelocity = Vector3.zero
    part.AssemblyAngularVelocity = Vector3.zero
    
    BlockCount = BlockCount + 1
    Counter.Text = "Blocked: " .. BlockCount
    Flash()
    
    -- Restore after 2 seconds (so map works again)
    task.delay(2, function()
        if part and part.Parent then
            AttackingParts[part] = nil
            -- Only restore if not still dangerous
            local character = LocalPlayer.Character
            if character then
                local root = character:FindFirstChild("HumanoidRootPart")
                if root then
                    local dist = (part.Position - root.Position).Magnitude
                    if dist > 40 then
                        part.CanCollide = true
                        part.CanTouch = true
                    end
                end
            end
        end
    end)
end

-- [ Ghost other players ] --
local function GhostPlayer(character)
    if not character then return end
    
    local function Disable(part)
        if part:IsA("BasePart") then
            part.CanCollide = false
            part.CanTouch = false
            part.Massless = true
            
            part:GetPropertyChangedSignal("CanCollide"):Connect(function()
                part.CanCollide = false
            end)
        end
    end
    
    for _, part in pairs(character:GetDescendants()) do
        Disable(part)
    end
    
    character.DescendantAdded:Connect(Disable)
end

-- [ Detect flying/teleporting ] --
local function IsFlying(character)
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if not root then return false end
    
    for _, obj in pairs(root:GetChildren()) do
        if obj:IsA("BodyGyro") or obj:IsA("BodyVelocity") or 
           obj:IsA("BodyPosition") or obj:IsA("LinearVelocity") then
            return true
        end
    end
    return false
end

-- [ Protect self from fling velocity ] --
local function ProtectSelf(character)
    if not character then return end
    
    local humanoid = character:WaitForChild("Humanoid", 5)
    local rootPart = character:WaitForChild("HumanoidRootPart", 5)
    
    if not rootPart then return end
    
    LastPosition = rootPart.Position
    SafeCFrame = rootPart.CFrame
    
    -- Disable ragdoll
    if humanoid then
        humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
        humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
        humanoid:SetStateEnabled(Enum.HumanoidStateType.Physics, false)
        
        -- Prevent health damage from fling
        local lastHealth = humanoid.Health
        humanoid.HealthChanged:Connect(function(newHealth)
            -- If health dropped suddenly and we're being flung
            local vel = rootPart.AssemblyLinearVelocity.Magnitude
            if vel > 200 and newHealth < lastHealth then
                humanoid.Health = lastHealth -- Restore health
            else
                lastHealth = newHealth
            end
        end)
    end
    
    -- Main loop
    local conn
    conn = RunService.Heartbeat:Connect(function()
        if not rootPart or not rootPart.Parent then
            conn:Disconnect()
            return
        end
        
        local myPos = rootPart.Position
        local myVel = rootPart.AssemblyLinearVelocity
        
        -- Skip if flying
        if IsFlying(character) then
            SafeCFrame = rootPart.CFrame
            LastPosition = myPos
            return
        end
        
        -- Teleport detection
        if LastPosition then
            local dist = (myPos - LastPosition).Magnitude
            if dist > 50 then
                LastMoveTime = tick()
                SafeCFrame = rootPart.CFrame
                LastPosition = myPos
                return
            end
        end
        
        if tick() - LastMoveTime < 0.5 then
            LastPosition = myPos
            return
        end
        
        -- Self fling protection
        local vel = rootPart.AssemblyLinearVelocity
        local angVel = rootPart.AssemblyAngularVelocity
        local speed = vel.Magnitude
        local spin = angVel.Magnitude
        
        local isFling = speed > 400 or 
                        spin > 60 or 
                        (speed > 150 and spin > 20) or
                        math.abs(vel.Y) > 200
        
        if isFling then
            rootPart.AssemblyLinearVelocity = Vector3.zero
            rootPart.AssemblyAngularVelocity = Vector3.zero
            
            for _, part in pairs(character:GetDescendants()) do
                if part:IsA("BasePart") then
                    part.AssemblyLinearVelocity = Vector3.zero
                    part.AssemblyAngularVelocity = Vector3.zero
                end
            end
            
            if speed > 800 then
                rootPart.CFrame = SafeCFrame
            end
            
            BlockCount = BlockCount + 1
            Counter.Text = "Blocked: " .. BlockCount
            Flash()
        else
            if speed < 50 then
                SafeCFrame = rootPart.CFrame
            end
        end
        
        LastPosition = myPos
    end)
end

-- [ MAIN: Reactive part protection ] --
local function StartReactiveProtection()
    local lastCheck = 0
    
    RunService.Heartbeat:Connect(function()
        if tick() - lastCheck < 0.1 then return end
        lastCheck = tick()
        
        local character = LocalPlayer.Character
        if not character then return end
        
        local root = character:FindFirstChild("HumanoidRootPart")
        if not root then return end
        
        local myPos = root.Position
        local myVel = root.AssemblyLinearVelocity
        
        -- Only check nearby area
        local region = Region3.new(
            myPos - Vector3.new(35, 35, 35),
            myPos + Vector3.new(35, 35, 35)
        )
        
        local success, parts = pcall(function()
            return workspace:FindPartsInRegion3(region, character, 200)
        end)
        
        if not success then return end
        
        for _, part in pairs(parts) do
            if IsAttacking(part, myPos, myVel) then
                NeutralizePart(part)
            end
        end
    end)
end

-- [ Touch detection - instant reaction ] --
local function StartTouchProtection()
    local character = LocalPlayer.Character
    if not character then return end
    
    local root = character:WaitForChild("HumanoidRootPart", 5)
    if not root then return end
    
    -- Create invisible hitbox around player
    local hitbox = Instance.new("Part")
    hitbox.Name = "AntiTPUA_Hitbox"
    hitbox.Size = Vector3.new(8, 8, 8)
    hitbox.Transparency = 1
    hitbox.CanCollide = false
    hitbox.CanTouch = true
    hitbox.CanQuery = false
    hitbox.Massless = true
    hitbox.Anchored = false
    hitbox.Parent = character
    
    -- Weld to root
    local weld = Instance.new("WeldConstraint")
    weld.Part0 = root
    weld.Part1 = hitbox
    weld.Parent = hitbox
    
    -- Detect touches
    hitbox.Touched:Connect(function(part)
        if part.Anchored then return end
        
        local isChar, owner = IsCharacterPart(part)
        if isChar and owner == LocalPlayer then return end
        
        local vel = part.AssemblyLinearVelocity.Magnitude
        local spin = part.AssemblyAngularVelocity.Magnitude
        
        -- Fast moving part touched us = attack!
        if vel > 30 or spin > 10 then
            NeutralizePart(part)
        end
    end)
end

-- [ Init ] --

-- Ghost players
for _, player in pairs(Players:GetPlayers()) do
    if player ~= LocalPlayer then
        if player.Character then GhostPlayer(player.Character) end
        player.CharacterAdded:Connect(GhostPlayer)
    end
end

Players.PlayerAdded:Connect(function(player)
    player.CharacterAdded:Connect(GhostPlayer)
end)

-- Self protection
if LocalPlayer.Character then
    ProtectSelf(LocalPlayer.Character)
    StartTouchProtection()
end

LocalPlayer.CharacterAdded:Connect(function(char)
    ProtectSelf(char)
    task.wait(0.5)
    StartTouchProtection()
end)

-- Start reactive protection
StartReactiveProtection()

print("[AntiTPUA v7] Reactive protection active!")
print("[AntiTPUA v7] Map parts normal - only blocks when attacked!")
