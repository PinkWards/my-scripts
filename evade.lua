if not game:IsLoaded() then game.Loaded:Wait() end

local scriptSource = nil

pcall(function()
    if queue_on_teleport then
        local scriptToQueue = game:HttpGet("YOUR_SCRIPT_URL_HERE")
        queue_on_teleport(scriptToQueue)
    end
end)

local TeleportService = game:GetService("TeleportService")
local teleportConnection

pcall(function()
    teleportConnection = game:GetService("Players").LocalPlayer.OnTeleport:Connect(function(state)
        if state == Enum.TeleportState.Started then
            print("[Evade Helper] Teleporting... Script will need re-execution")
        end
    end)
end)

local AllowedPlaceIds = {
    [9872472334] = true,
    [13839327834] = true,
    [13772394567] = true,
}

local RUN_IN_ANY_GAME = true

if not RUN_IN_ANY_GAME and not AllowedPlaceIds[game.PlaceId] then 
    warn("[Evade Helper] Game not in allowed list. PlaceId:", game.PlaceId)
    return 
end

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualUser = game:GetService("VirtualUser")
local TweenService = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui", 10)
local Workspace = workspace

local State = {
    Border = false,
    AntiNextbot = false,
    AutoFarm = false,
    VoteMap = false,
    VoteMode = false,
    MapIndex = 1,
    ModeIndex = 1,
    MapSearch = "",
    GamemodeSearch = "",
    InfiniteCola = false,
    UpsideDownFix = false,
    EdgeBoost = false
}

local Config = {
    FOV = 120,
    DangerThreshold = 50,
    SafeDistance = 80
}

local BounceConfig = {
    Power = 90,
    Boost = 120,
    Cooldown = 0.15,
    AirDuration = 6,
    AirGain = 5.5,
    AirMax = 280
}

local EdgeConfig = {
    Boost = 14,
    MinSpeed = 8,
    Cooldown = 0.12,
    MinEdge = 0.3,
    LastTime = 0,
    DetectionRange = 2.5,
    RayDepth = 5
}

local ColaConfig = {
    Speed = 1.4,
    Duration = 3.5
}

-- ═══════════════════════════════════════════════════════
-- OPTIMIZED BHOP CONFIG
-- ═══════════════════════════════════════════════════════
local BhopConfig = {
    PreJumpDistance = 4.5,        -- How far ahead to predict landing
    PreJumpVelThreshold = -2,    -- Minimum downward velocity to trigger pre-jump
    GroundRayLength = 3.2,       -- Ray length for ground detection
    SpeedPreserveMultiplier = 1.02, -- Slight speed boost on each hop to counter friction
    MaxPreservedSpeed = 200,     -- Cap for preserved horizontal speed
    InstantJumpBuffer = 0.05,    -- Time window for instant re-jump after landing
    MultiRayCount = 5,           -- Number of rays for ground detection
    MultiRaySpread = 1.2,        -- Spread radius for multi-ray detection
    VelocityRestoreFrames = 3,   -- Frames to restore velocity after jump
    FrictionCompensation = 1.15, -- Multiplier to counteract ground friction
}

local Humanoid, RootPart = nil, nil
local GUI, VIPPanel, TimerGUI = nil, nil, nil
local TimerLabel, StatusLabel = nil, nil

local holdQ, holdSpace, holdX = false, false, false

local LastAntiCheck, LastCarry, LastBounce, AirEnd = 0, 0, 0, 0
local LastVoteMap, LastVoteMode = 0, 0
local SelfResCD = 0
local LastRayFilterUpdate = 0
local LastEdgeCheck = 0

local CurrentTarget, FarmStart = nil, 0
local ColaDrank = false
local NPCNames = {}
local NPCLoaded = false
local CachedBots, CachedItems = {}, {}
local Maps, Modes = {}, {}
local FullbrightEnabled = false
local SavedLighting = nil
local LastCamera = nil

local Connections = {}
local EdgeTouchConnections = {}
local CachedGame = nil
local StateChangedConn = nil

local SliderTrack, SliderFill, SliderThumb, SliderLabel
local SliderMin, SliderMax = 1.0, 1.8

local LastGroundState = false
local LastJumpTick = 0
local BHOP_COOLDOWN = 0

-- Speed preservation state
local PreHopVelocity = Vector3.zero
local HopCount = 0
local LastHopTime = 0
local VelocityRestoreCounter = 0
local StoredHorizontalSpeed = 0
local IsInBhopChain = false
local LastLandingTime = 0
local WasAirborne = false
local PendingJump = false
local FramesSinceLanding = 0

local BhopRayParams = RaycastParams.new()
BhopRayParams.FilterType = Enum.RaycastFilterType.Exclude
BhopRayParams.RespectCanCollide = true

local EdgeRayParams = RaycastParams.new()
EdgeRayParams.FilterType = Enum.RaycastFilterType.Exclude
EdgeRayParams.IgnoreWater = true
EdgeRayParams.RespectCanCollide = true

local function SafeGetPath(...)
    local args = {...}
    local current = args[1]
    for i = 2, #args do
        if not current then return nil end
        current = current:FindFirstChild(args[i])
    end
    return current
end

local function IsEvadeGame()
    local hasNPCs = ReplicatedStorage:FindFirstChild("NPCs") ~= nil
    local hasEvents = SafeGetPath(ReplicatedStorage, "Events", "Character", "Interact") ~= nil
    local hasGame = Workspace:FindFirstChild("Game") ~= nil or Workspace:FindFirstChild("SecurityPart") ~= nil
    return hasNPCs or hasEvents or hasGame
end

local function UpdateRayFilter()
    local now = tick()
    if now - LastRayFilterUpdate < 0.5 then return end
    LastRayFilterUpdate = now
    
    local filterList = {}
    
    local character = LocalPlayer.Character
    if character then
        table.insert(filterList, character)
    end
    
    for _, player in ipairs(Players:GetPlayers()) do
        if player.Character then
            table.insert(filterList, player.Character)
        end
    end
    
    local gameFolder = Workspace:FindFirstChild("Game")
    if gameFolder then
        local gamePlayers = gameFolder:FindFirstChild("Players")
        if gamePlayers then
            table.insert(filterList, gamePlayers)
        end
    end
    
    BhopRayParams.FilterDescendantsInstances = filterList
    EdgeRayParams.FilterDescendantsInstances = filterList
end

local function ForceUpdateRayFilter()
    LastRayFilterUpdate = 0
    UpdateRayFilter()
end

local function SafeCall(func, ...)
    local success, result = pcall(func, ...)
    return success and result
end

local function GetDistance(position, bots)
    local minDist = math.huge
    for _, botPos in ipairs(bots) do
        local dist = (position - botPos).Magnitude
        if dist < minDist then
            minDist = dist
        end
    end
    return minDist
end

local function GetNamesFromPath(path)
    local names = {}
    local folder = ReplicatedStorage
    for part in path:gmatch("[^%.]+") do
        folder = folder and folder:FindFirstChild(part)
    end
    if folder then
        for _, child in ipairs(folder:GetChildren()) do
            table.insert(names, child.Name)
        end
    end
    return names
end

task.spawn(function()
    Maps = GetNamesFromPath("Info.Maps")
    Modes = GetNamesFromPath("Info.Gamemodes")
end)

local function CleanupAll()
    for _, conn in pairs(Connections) do
        SafeCall(function() conn:Disconnect() end)
    end
    table.clear(Connections)
    
    for _, conn in pairs(EdgeTouchConnections) do
        SafeCall(function() conn:Disconnect() end)
    end
    table.clear(EdgeTouchConnections)
    
    if TimerGUI then SafeCall(function() TimerGUI:Destroy() end) TimerGUI = nil end
    if GUI then SafeCall(function() GUI:Destroy() end) GUI = nil end
    
    table.clear(CachedBots)
    table.clear(CachedItems)
    CachedGame = nil
end

local function LoadNPCs()
    table.clear(NPCNames)
    local folder = ReplicatedStorage:FindFirstChild("NPCs")
    if folder then
        for _, npc in ipairs(folder:GetChildren()) do
            NPCNames[npc.Name] = true
        end
        NPCLoaded = true
    else
        NPCLoaded = false
    end
end

-- ═══════════════════════════════════════════════════════
-- OPTIMIZED GROUND DETECTION - Multi-ray system
-- ═══════════════════════════════════════════════════════
local function IsOnGroundMultiRay()
    if not Humanoid or not RootPart then return false, nil end
    
    -- Fast check first
    if Humanoid.FloorMaterial ~= Enum.Material.Air then
        return true, RootPart.Position - Vector3.new(0, 3, 0)
    end
    
    local state = Humanoid:GetState()
    if state == Enum.HumanoidStateType.Running or
       state == Enum.HumanoidStateType.RunningNoPhysics or
       state == Enum.HumanoidStateType.Landed then
        return true, RootPart.Position - Vector3.new(0, 3, 0)
    end
    
    -- Multi-ray ground detection for consistency
    local pos = RootPart.Position
    local rayLen = BhopConfig.GroundRayLength
    local spread = BhopConfig.MultiRaySpread
    
    local rayOrigins = {
        pos,  -- Center
        pos + Vector3.new(spread, 0, 0),
        pos + Vector3.new(-spread, 0, 0),
        pos + Vector3.new(0, 0, spread),
        pos + Vector3.new(0, 0, -spread),
    }
    
    for _, origin in ipairs(rayOrigins) do
        local rayResult = Workspace:Raycast(origin, Vector3.new(0, -rayLen, 0), BhopRayParams)
        if rayResult and rayResult.Instance then
            local hitPart = rayResult.Instance
            local hitModel = hitPart:FindFirstAncestorOfClass("Model")
            
            if hitModel then
                local hitPlayer = Players:GetPlayerFromCharacter(hitModel)
                if hitPlayer or hitModel:FindFirstChildOfClass("Humanoid") then
                    continue
                end
            end
            
            local angle = math.deg(math.acos(math.clamp(rayResult.Normal:Dot(Vector3.yAxis), -1, 1)))
            if angle <= 45 then
                return true, rayResult.Position
            end
        end
    end
    
    return false, nil
end

local function IsOnGroundInstant()
    local grounded, _ = IsOnGroundMultiRay()
    return grounded
end

-- ═══════════════════════════════════════════════════════
-- OPTIMIZED BHOP - Speed Preservation System
-- ═══════════════════════════════════════════════════════
local function GetHorizontalSpeed()
    if not RootPart then return 0 end
    local vel = RootPart.AssemblyLinearVelocity
    return Vector3.new(vel.X, 0, vel.Z).Magnitude
end

local function GetHorizontalVelocity()
    if not RootPart then return Vector3.zero end
    local vel = RootPart.AssemblyLinearVelocity
    return Vector3.new(vel.X, 0, vel.Z)
end

local function PreserveSpeed()
    if not RootPart or not IsInBhopChain then return end
    if StoredHorizontalSpeed <= 0 then return end
    
    local currentVel = RootPart.AssemblyLinearVelocity
    local currentHorizontal = Vector3.new(currentVel.X, 0, currentVel.Z)
    local currentSpeed = currentHorizontal.Magnitude
    
    -- Only restore if we lost speed (friction ate it)
    if currentSpeed < StoredHorizontalSpeed * 0.92 and currentSpeed > 1 then
        local targetSpeed = math.min(
            StoredHorizontalSpeed * BhopConfig.SpeedPreserveMultiplier,
            BhopConfig.MaxPreservedSpeed
        )
        
        local direction
        if currentHorizontal.Magnitude > 0.5 then
            direction = currentHorizontal.Unit
        else
            -- Use camera direction as fallback
            local camera = Workspace.CurrentCamera
            if camera then
                local look = camera.CFrame.LookVector
                direction = Vector3.new(look.X, 0, look.Z)
                if direction.Magnitude > 0.1 then
                    direction = direction.Unit
                else
                    return
                end
            else
                return
            end
        end
        
        local restoredVel = direction * targetSpeed
        RootPart.AssemblyLinearVelocity = Vector3.new(restoredVel.X, currentVel.Y, restoredVel.Z)
    end
end

local function ExecuteJump()
    if not Humanoid or Humanoid.Health <= 0 then return end
    
    -- Store pre-jump velocity for preservation
    local currentHSpeed = GetHorizontalSpeed()
    if currentHSpeed > StoredHorizontalSpeed * 0.8 then
        StoredHorizontalSpeed = currentHSpeed
        PreHopVelocity = RootPart.AssemblyLinearVelocity
    end
    
    -- Apply friction compensation before jumping
    if IsInBhopChain and StoredHorizontalSpeed > 5 then
        local currentVel = RootPart.AssemblyLinearVelocity
        local horizontal = Vector3.new(currentVel.X, 0, currentVel.Z)
        
        if horizontal.Magnitude > 0.5 then
            local boostedSpeed = math.min(
                StoredHorizontalSpeed * BhopConfig.FrictionCompensation,
                BhopConfig.MaxPreservedSpeed
            )
            local boostedVel = horizontal.Unit * boostedSpeed
            RootPart.AssemblyLinearVelocity = Vector3.new(boostedVel.X, currentVel.Y, boostedVel.Z)
        end
    end
    
    -- Execute the jump
    Humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
    VelocityRestoreCounter = BhopConfig.VelocityRestoreFrames
    
    -- Post-jump velocity restoration
    task.defer(function()
        if not RootPart or not Humanoid then return end
        if Humanoid.Health <= 0 then return end
        
        local postVel = RootPart.AssemblyLinearVelocity
        local postHorizontal = Vector3.new(postVel.X, 0, postVel.Z)
        local postSpeed = postHorizontal.Magnitude
        
        -- If jump ate our speed, restore it
        if IsInBhopChain and StoredHorizontalSpeed > 5 and postSpeed < StoredHorizontalSpeed * 0.85 then
            local targetSpeed = math.min(StoredHorizontalSpeed, BhopConfig.MaxPreservedSpeed)
            
            if postHorizontal.Magnitude > 0.5 then
                local restored = postHorizontal.Unit * targetSpeed
                RootPart.AssemblyLinearVelocity = Vector3.new(restored.X, postVel.Y, restored.Z)
            elseif PreHopVelocity.Magnitude > 0.5 then
                local preH = Vector3.new(PreHopVelocity.X, 0, PreHopVelocity.Z)
                if preH.Magnitude > 0.5 then
                    local restored = preH.Unit * targetSpeed
                    RootPart.AssemblyLinearVelocity = Vector3.new(restored.X, postVel.Y, restored.Z)
                end
            end
        end
    end)
    
    local now = tick()
    LastJumpTick = now
    HopCount = HopCount + 1
    LastHopTime = now
    IsInBhopChain = true
end

local function SuperBhop()
    if not holdSpace or not Humanoid or not RootPart then return end
    if Humanoid.Health <= 0 then return end
    
    local character = LocalPlayer.Character
    if not character then return end
    
    local isDowned = SafeCall(function() return character:GetAttribute("Downed") end)
    if isDowned then return end
    
    local onGround, groundPos = IsOnGroundMultiRay()
    local now = tick()
    
    -- Track airborne state for chain detection
    if not onGround then
        WasAirborne = true
    end
    
    -- Reset bhop chain if too much time passed
    if now - LastHopTime > 1.0 then
        IsInBhopChain = false
        HopCount = 0
        StoredHorizontalSpeed = 0
    end
    
    if onGround then
        FramesSinceLanding = FramesSinceLanding + 1
        
        -- Store speed on first ground contact
        if WasAirborne or not LastGroundState then
            WasAirborne = false
            LastLandingTime = now
            FramesSinceLanding = 0
            
            local currentSpeed = GetHorizontalSpeed()
            if currentSpeed > StoredHorizontalSpeed * 0.7 then
                StoredHorizontalSpeed = currentSpeed
            end
        end
        
        -- Jump immediately - zero delay
        if not LastGroundState or (now - LastJumpTick) >= BHOP_COOLDOWN then
            ExecuteJump()
            
            -- Double-tap insurance
            task.defer(function()
                if Humanoid and Humanoid.Health > 0 and holdSpace then
                    if IsOnGroundInstant() then
                        ExecuteJump()
                    end
                end
            end)
        end
        
        -- Preserve speed while on ground (anti-friction)
        PreserveSpeed()
    else
        FramesSinceLanding = 0
        
        -- Velocity restore frames while airborne after jump
        if VelocityRestoreCounter > 0 then
            VelocityRestoreCounter = VelocityRestoreCounter - 1
            PreserveSpeed()
        end
    end
    
    LastGroundState = onGround
end

-- ═══════════════════════════════════════════════════════
-- OPTIMIZED PRE-JUMP QUEUE - Predictive landing
-- ═══════════════════════════════════════════════════════
local function PreJumpQueue()
    if not holdSpace or not Humanoid or not RootPart then return end
    if Humanoid.Health <= 0 then return end
    
    local state = Humanoid:GetState()
    if state == Enum.HumanoidStateType.Freefall then
        local pos = RootPart.Position
        local vel = RootPart.AssemblyLinearVelocity
        
        -- Store speed before landing
        local hSpeed = Vector3.new(vel.X, 0, vel.Z).Magnitude
        if hSpeed > StoredHorizontalSpeed * 0.8 then
            StoredHorizontalSpeed = hSpeed
            PreHopVelocity = vel
        end
        
        -- Multi-ray predictive landing detection
        local predictedPositions = {
            pos,
            pos + Vector3.new(vel.X, 0, vel.Z).Unit * 1.5,  -- Slightly ahead
        }
        
        for _, checkPos in ipairs(predictedPositions) do
            local rayResult = Workspace:Raycast(checkPos, Vector3.new(0, -BhopConfig.PreJumpDistance, 0), BhopRayParams)
            if rayResult then
                local hitPart = rayResult.Instance
                local hitModel = hitPart:FindFirstAncestorOfClass("Model")
                
                if hitModel then
                    local hitPlayer = Players:GetPlayerFromCharacter(hitModel)
                    if hitPlayer or hitModel:FindFirstChildOfClass("Humanoid") then
                        continue
                    end
                end
                
                local angle = math.deg(math.acos(math.clamp(rayResult.Normal:Dot(Vector3.yAxis), -1, 1)))
                if angle > 35 then
                    continue
                end
                
                local dist = (pos - rayResult.Position).Magnitude
                
                -- More aggressive pre-jump - trigger earlier and with less velocity requirement
                if vel.Y < BhopConfig.PreJumpVelThreshold and dist < BhopConfig.PreJumpDistance then
                    -- Calculate time to impact for better prediction
                    local timeToImpact = dist / math.max(math.abs(vel.Y), 1)
                    
                    if timeToImpact < 0.15 or dist < 2.5 then
                        PendingJump = true
                        IsInBhopChain = true
                        
                        task.defer(function()
                            if holdSpace and Humanoid and Humanoid.Health > 0 then
                                -- Pre-apply friction compensation
                                if StoredHorizontalSpeed > 5 then
                                    local currentVel = RootPart.AssemblyLinearVelocity
                                    local horizontal = Vector3.new(currentVel.X, 0, currentVel.Z)
                                    if horizontal.Magnitude > 0.5 then
                                        local boosted = horizontal.Unit * math.min(StoredHorizontalSpeed * BhopConfig.FrictionCompensation, BhopConfig.MaxPreservedSpeed)
                                        RootPart.AssemblyLinearVelocity = Vector3.new(boosted.X, currentVel.Y, boosted.Z)
                                    end
                                end
                                
                                Humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
                                LastJumpTick = tick()
                                HopCount = HopCount + 1
                                LastHopTime = tick()
                                VelocityRestoreCounter = BhopConfig.VelocityRestoreFrames
                            end
                        end)
                        return -- Found a valid landing spot, exit
                    end
                end
            end
        end
    end
end

-- ═══════════════════════════════════════════════════════
-- CONTINUOUS SPEED PRESERVATION (runs every frame during bhop)
-- ═══════════════════════════════════════════════════════
local function ContinuousSpeedPreservation()
    if not holdSpace or not RootPart or not Humanoid then return end
    if Humanoid.Health <= 0 then return end
    if not IsInBhopChain or StoredHorizontalSpeed <= 3 then return end
    
    local vel = RootPart.AssemblyLinearVelocity
    local horizontal = Vector3.new(vel.X, 0, vel.Z)
    local currentSpeed = horizontal.Magnitude
    
    -- Only during ground contact moments (where friction kills speed)
    local onGround = IsOnGroundInstant()
    if not onGround then return end
    
    -- If speed dropped significantly, restore it
    local speedRatio = currentSpeed / StoredHorizontalSpeed
    if speedRatio < 0.88 and currentSpeed > 1 then
        local targetSpeed = math.min(
            StoredHorizontalSpeed * BhopConfig.SpeedPreserveMultiplier,
            BhopConfig.MaxPreservedSpeed
        )
        
        local direction
        if horizontal.Magnitude > 0.5 then
            direction = horizontal.Unit
        else
            local preH = Vector3.new(PreHopVelocity.X, 0, PreHopVelocity.Z)
            if preH.Magnitude > 0.5 then
                direction = preH.Unit
            else
                return
            end
        end
        
        local restored = direction * targetSpeed
        RootPart.AssemblyLinearVelocity = Vector3.new(restored.X, vel.Y, restored.Z)
    end
    
    -- Update stored speed if we're going faster (e.g., downhill)
    if currentSpeed > StoredHorizontalSpeed then
        StoredHorizontalSpeed = currentSpeed
    end
end

local LastBotCheck = 0

local function GetBots()
    local now = tick()
    if now - LastBotCheck < 0.1 then
        return CachedBots
    end
    LastBotCheck = now
    
    if not NPCLoaded then LoadNPCs() end
    table.clear(CachedBots)
    
    if not CachedGame then
        CachedGame = Workspace:FindFirstChild("Game")
    end
    
    if not CachedGame then return CachedBots end
    
    local gamePlayers = CachedGame:FindFirstChild("Players")
    if gamePlayers then
        for _, model in ipairs(gamePlayers:GetChildren()) do
            if model:IsA("Model") and NPCNames[model.Name] then
                local hrp = model:FindFirstChild("HumanoidRootPart")
                if hrp then
                    table.insert(CachedBots, hrp.Position)
                end
            end
        end
    end
    
    return CachedBots
end

local LastItemCheck = 0

local function GetItems()
    local now = tick()
    if now - LastItemCheck < 0.1 then
        return CachedItems
    end
    LastItemCheck = now
    
    table.clear(CachedItems)
    
    if not CachedGame then
        CachedGame = Workspace:FindFirstChild("Game")
    end
    
    if not CachedGame then return CachedItems end
    
    local effects = CachedGame:FindFirstChild("Effects")
    if not effects then return CachedItems end
    
    for _, containerName in ipairs({"Tickets", "Collectables"}) do
        local container = effects:FindFirstChild(containerName)
        if container then
            for _, item in ipairs(container:GetChildren()) do
                if item and item.Parent then
                    local part
                    if item:IsA("Model") then
                        part = item:FindFirstChild("HumanoidRootPart") or item.PrimaryPart or item:FindFirstChildWhichIsA("BasePart")
                    elseif item:IsA("BasePart") then
                        part = item
                    end
                    
                    if part and part.Parent then
                        table.insert(CachedItems, {object = item, position = part.Position})
                    end
                end
            end
        end
    end
    
    return CachedItems
end

local function FindSafeSpot(myPos, bots)
    local safeLocations = {}
    
    if not CachedGame then
        CachedGame = Workspace:FindFirstChild("Game")
    end
    
    if CachedGame then
        local mapFolder = CachedGame:FindFirstChild("Map")
        local partsFolder = mapFolder and mapFolder:FindFirstChild("Parts")
        local spawnsFolder = partsFolder and partsFolder:FindFirstChild("Spawns")
        
        if spawnsFolder then
            for _, spawn in ipairs(spawnsFolder:GetChildren()) do
                if spawn:IsA("BasePart") then
                    table.insert(safeLocations, spawn.Position + Vector3.new(0, 5, 0))
                end
            end
        end
    end
    
    local securityPart = Workspace:FindFirstChild("SecurityPart")
    if securityPart then
        table.insert(safeLocations, securityPart.Position + Vector3.new(0, 5, 0))
    end
    
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character then
            local hrp = player.Character:FindFirstChild("HumanoidRootPart")
            local isDowned = SafeCall(function() return player.Character:GetAttribute("Downed") end)
            if hrp and not isDowned then
                table.insert(safeLocations, hrp.Position + Vector3.new(0, 3, 0))
            end
        end
    end
    
    local bestLocation, bestDistance = nil, 0
    for _, location in ipairs(safeLocations) do
        local minDist = GetDistance(location, bots)
        if minDist > bestDistance and minDist >= Config.SafeDistance then
            bestDistance = minDist
            bestLocation = location
        end
    end
    
    if not bestLocation and securityPart then
        bestLocation = securityPart.Position + Vector3.new(0, 5, 0)
    end
    
    return bestLocation
end

local function Teleport(pos)
    local character = LocalPlayer.Character
    if not character then return end
    
    local hrp = character:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    
    local rayParams = RaycastParams.new()
    rayParams.FilterDescendantsInstances = {character}
    rayParams.FilterType = Enum.RaycastFilterType.Exclude
    
    local ray = Workspace:Raycast(pos, Vector3.new(0, -50, 0), rayParams)
    local finalPos = ray and (ray.Position + Vector3.new(0, 5, 0)) or pos
    
    hrp.CFrame = CFrame.new(finalPos)
    
    task.defer(function()
        if hrp and hrp.Parent then
            hrp.AssemblyLinearVelocity = Vector3.zero
            hrp.AssemblyAngularVelocity = Vector3.zero
        end
    end)
end

local function AntiNextbot()
    if not State.AntiNextbot then return end
    
    local now = tick()
    if now - LastAntiCheck < 0.15 then return end
    LastAntiCheck = now
    
    local character = LocalPlayer.Character
    if not character then return end
    
    local hrp = character:FindFirstChild("HumanoidRootPart")
    local isDowned = SafeCall(function() return character:GetAttribute("Downed") end)
    if not hrp or isDowned then return end
    
    local bots = GetBots()
    if #bots == 0 then return end
    
    local myPos = hrp.Position
    local closestDist = GetDistance(myPos, bots)
    
    if closestDist <= Config.DangerThreshold then
        local safeSpot = FindSafeSpot(myPos, bots)
        if safeSpot then
            Teleport(safeSpot)
        end
    end
end

local LastFarmTick = 0

local function AutoFarm()
    if not State.AutoFarm then return end
    
    local now = tick()
    if now - LastFarmTick < 0.05 then return end
    LastFarmTick = now
    
    local character = LocalPlayer.Character
    if not character then return end
    
    local hrp = character:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    
    local isDowned = SafeCall(function() return character:GetAttribute("Downed") end)
    if isDowned then
        SafeCall(function()
            local event = SafeGetPath(ReplicatedStorage, "Events", "Player", "ChangePlayerMode")
            if event then event:FireServer(true) end
        end)
        local securityPart = Workspace:FindFirstChild("SecurityPart")
        if securityPart then
            Teleport(securityPart.Position)
        end
        CurrentTarget = nil
        return
    end
    
    local items = GetItems()
    
    if #items == 0 then
        local securityPart = Workspace:FindFirstChild("SecurityPart")
        if securityPart then
            Teleport(securityPart.Position)
        end
        CurrentTarget = nil
        return
    end
    
    if CurrentTarget then
        if not CurrentTarget.object or not CurrentTarget.object.Parent then
            CurrentTarget = nil
            FarmStart = 0
        else
            local freshPos = nil
            local obj = CurrentTarget.object
            local part
            
            if obj:IsA("Model") then
                part = obj:FindFirstChild("HumanoidRootPart") or obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart")
            elseif obj:IsA("BasePart") then
                part = obj
            end
            
            if part and part.Parent then
                freshPos = part.Position
            end
            
            if freshPos then
                Teleport(freshPos)
                CurrentTarget.position = freshPos
            end
            
            if tick() - FarmStart >= 0.25 then
                CurrentTarget = nil
                FarmStart = 0
            end
            return
        end
    end
    
    local myPos = hrp.Position
    local nearestItem, nearestDist = nil, math.huge
    
    for _, item in ipairs(items) do
        if item.object and item.object.Parent then
            local dist = (myPos - item.position).Magnitude
            if dist < nearestDist then
                nearestDist = dist
                nearestItem = item
            end
        end
    end
    
    if nearestItem then
        CurrentTarget = nearestItem
        FarmStart = tick()
        Teleport(nearestItem.position)
    end
end

local function ToggleUpsideDownFix(enabled)
    State.UpsideDownFix = enabled
    
    if Connections.UpsideDown then
        Connections.UpsideDown:Disconnect()
        Connections.UpsideDown = nil
    end
    
    if enabled then
        Connections.UpsideDown = RunService.RenderStepped:Connect(function()
            local camera = Workspace.CurrentCamera
            if not camera then return end
            
            local cf = camera.CFrame
            local rx, ry, rz = cf:ToEulerAnglesXYZ()
            
            if math.abs(rz) > math.rad(90) then
                camera.CFrame = CFrame.new(cf.Position) * CFrame.Angles(rx, ry, 0)
            end
        end)
    end
end

local function Bounce()
    if not holdX or not Humanoid or Humanoid.Health <= 0 then return end
    
    local character = LocalPlayer.Character
    if not character then return end
    
    local isDowned = SafeCall(function() return character:GetAttribute("Downed") end)
    if isDowned then return end
    
    local root = character:FindFirstChild("HumanoidRootPart")
    if not root then return end
    
    local now = tick()
    if now - LastBounce < BounceConfig.Cooldown then return end
    if not IsOnGroundInstant() then return end
    
    LastBounce = now
    
    local camera = Workspace.CurrentCamera
    if not camera then return end
    
    local look = camera.CFrame.LookVector
    local forward = Vector3.new(look.X, 0, look.Z)
    forward = forward.Magnitude > 0.1 and forward.Unit or Vector3.new(0, 0, -1)
    
    root.AssemblyLinearVelocity = Vector3.new(
        forward.X * BounceConfig.Boost,
        BounceConfig.Power,
        forward.Z * BounceConfig.Boost
    )
    
    AirEnd = now + BounceConfig.AirDuration
end

local function AirStrafe()
    if tick() > AirEnd then return end
    
    local character = LocalPlayer.Character
    if not character then return end
    
    local root = character:FindFirstChild("HumanoidRootPart")
    local isDowned = SafeCall(function() return character:GetAttribute("Downed") end)
    if not root or isDowned then return end
    if IsOnGroundInstant() then return end
    
    local moveLeft = UserInputService:IsKeyDown(Enum.KeyCode.A)
    local moveRight = UserInputService:IsKeyDown(Enum.KeyCode.D)
    local moveForward = UserInputService:IsKeyDown(Enum.KeyCode.W)
    
    if not moveLeft and not moveRight and not moveForward then return end
    
    local vel = root.AssemblyLinearVelocity
    local horizontalVel = Vector3.new(vel.X, 0, vel.Z)
    
    local camera = Workspace.CurrentCamera
    if not camera then return end
    
    local strafeDir = Vector3.zero
    if moveLeft then strafeDir = strafeDir - camera.CFrame.RightVector end
    if moveRight then strafeDir = strafeDir + camera.CFrame.RightVector end
    if moveForward then strafeDir = strafeDir + camera.CFrame.LookVector end
    
    strafeDir = Vector3.new(strafeDir.X, 0, strafeDir.Z)
    
    if strafeDir.Magnitude > 0.1 then
        strafeDir = strafeDir.Unit
        local newVel = horizontalVel + strafeDir * BounceConfig.AirGain
        
        if newVel.Magnitude > BounceConfig.AirMax then
            newVel = newVel.Unit * BounceConfig.AirMax
        end
        
        root.AssemblyLinearVelocity = Vector3.new(newVel.X, vel.Y, newVel.Z)
    end
end

local function DetectEdge(position, direction)
    local centerRay = Workspace:Raycast(position, Vector3.new(0, -EdgeConfig.RayDepth, 0), EdgeRayParams)
    if not centerRay then return false, nil end
    
    local checkPos = position + direction * EdgeConfig.DetectionRange
    local edgeRay = Workspace:Raycast(checkPos, Vector3.new(0, -EdgeConfig.RayDepth - 2, 0), EdgeRayParams)
    
    if not edgeRay then
        return true, centerRay.Position.Y
    end
    
    local heightDiff = centerRay.Position.Y - edgeRay.Position.Y
    if heightDiff >= EdgeConfig.MinEdge then
        return true, centerRay.Position.Y
    end
    
    return false, nil
end

local function ReactiveEdgeBoost()
    if not State.EdgeBoost then return end
    if not Humanoid or not RootPart then return end
    if Humanoid.Health <= 0 then return end
    
    local character = LocalPlayer.Character
    if not character then return end
    
    local isDowned = SafeCall(function() return character:GetAttribute("Downed") end)
    if isDowned then return end
    
    local now = tick()
    if now - EdgeConfig.LastTime < EdgeConfig.Cooldown then return end
    
    local vel = RootPart.AssemblyLinearVelocity
    local horizontalVel = Vector3.new(vel.X, 0, vel.Z)
    local horizontalSpeed = horizontalVel.Magnitude
    
    if horizontalSpeed < EdgeConfig.MinSpeed then return end
    
    local playerPos = RootPart.Position
    local moveDir = horizontalVel.Unit
    
    local checkDirections = {
        moveDir,
        (moveDir + RootPart.CFrame.RightVector * 0.5).Unit,
        (moveDir - RootPart.CFrame.RightVector * 0.5).Unit,
        RootPart.CFrame.LookVector,
        -RootPart.CFrame.LookVector,
        RootPart.CFrame.RightVector,
        -RootPart.CFrame.RightVector
    }
    
    for _, dir in ipairs(checkDirections) do
        local isEdge, groundY = DetectEdge(playerPos, dir)
        
        if isEdge and groundY then
            local playerFeetY = playerPos.Y - (Humanoid.HipHeight + 0.5)
            local heightAboveGround = playerFeetY - groundY
            
            if heightAboveGround < 1.5 and heightAboveGround > -0.5 then
                local boostAmount = EdgeConfig.Boost
                
                if vel.Y < 0 then
                    boostAmount = boostAmount * 1.2
                end
                
                RootPart.AssemblyLinearVelocity = Vector3.new(vel.X, math.max(vel.Y, 0) + boostAmount, vel.Z)
                EdgeConfig.LastTime = now
                return
            end
        end
    end
end

local function EdgeBoostTouchHandler(hit)
    if not State.EdgeBoost then return end
    if not hit or not hit.Parent then return end
    
    local character = LocalPlayer.Character
    if not character or not Humanoid or not RootPart then return end
    if hit:IsDescendantOf(character) then return end
    
    local hitModel = hit:FindFirstAncestorOfClass("Model")
    if hitModel then
        local hitPlayer = Players:GetPlayerFromCharacter(hitModel)
        if hitPlayer or hitModel:FindFirstChildOfClass("Humanoid") then
            return
        end
    end
    
    if not hit.CanCollide or hit.Transparency > 0.9 or hit.Size.Magnitude < 0.5 then return end
    
    local now = tick()
    if now - EdgeConfig.LastTime < EdgeConfig.Cooldown then return end
    
    local vel = RootPart.AssemblyLinearVelocity
    local horizontalSpeed = Vector3.new(vel.X, 0, vel.Z).Magnitude
    
    if horizontalSpeed < EdgeConfig.MinSpeed * 0.5 then return end
    
    local partTop = hit.Position.Y + (hit.Size.Y / 2)
    
    local isNearEdge = false
    local hitPos = hit.Position
    local directions = {
        Vector3.new(hit.Size.X/2 + 0.5, 0, 0),
        Vector3.new(-hit.Size.X/2 - 0.5, 0, 0),
        Vector3.new(0, 0, hit.Size.Z/2 + 0.5),
        Vector3.new(0, 0, -hit.Size.Z/2 - 0.5)
    }
    
    for _, offset in ipairs(directions) do
        local checkPos = Vector3.new(hitPos.X + offset.X, partTop + 1, hitPos.Z + offset.Z)
        local ray = Workspace:Raycast(checkPos, Vector3.new(0, -3, 0), EdgeRayParams)
        
        if not ray or math.abs(partTop - ray.Position.Y) >= EdgeConfig.MinEdge then
            local distToEdge = (RootPart.Position - Vector3.new(hitPos.X + offset.X, RootPart.Position.Y, hitPos.Z + offset.Z)).Magnitude
            if distToEdge < EdgeConfig.DetectionRange + 1 then
                isNearEdge = true
                break
            end
        end
    end
    
    if isNearEdge then
        local boostAmount = EdgeConfig.Boost * 0.8
        RootPart.AssemblyLinearVelocity = Vector3.new(vel.X, math.max(vel.Y, 0) + boostAmount, vel.Z)
        EdgeConfig.LastTime = now
    end
end

local function SetupEdgeBoost()
    for _, conn in pairs(EdgeTouchConnections) do
        SafeCall(function() conn:Disconnect() end)
    end
    table.clear(EdgeTouchConnections)
    
    if not State.EdgeBoost then return end
    
    local character = LocalPlayer.Character
    if not character then return end
    
    for _, part in ipairs(character:GetDescendants()) do
        if part:IsA("BasePart") then
            local conn = part.Touched:Connect(EdgeBoostTouchHandler)
            table.insert(EdgeTouchConnections, conn)
        end
    end
end

local function DoCarry()
    if not holdQ then return end
    
    local now = tick()
    if now - LastCarry < 0.4 then return end
    LastCarry = now
    
    local character = LocalPlayer.Character
    if not character then return end
    
    local hrp = character:FindFirstChild("HumanoidRootPart")
    local isDowned = SafeCall(function() return character:GetAttribute("Downed") end)
    if not hrp or isDowned then return end
    
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character then
            local otherHrp = player.Character:FindFirstChild("HumanoidRootPart")
            local otherChar = player.Character
            
            if otherHrp and (hrp.Position - otherHrp.Position).Magnitude <= 8 then
                local otherDowned = SafeCall(function() return otherChar:GetAttribute("Downed") end)
                local otherHum = otherChar:FindFirstChild("Humanoid")
                local isPhysics = otherHum and otherHum:GetState() == Enum.HumanoidStateType.Physics
                
                if otherDowned or isPhysics then
                    SafeCall(function()
                        local event = SafeGetPath(ReplicatedStorage, "Events", "Character", "Interact")
                        if event then event:FireServer("Carry", nil, player.Name) end
                    end)
                    return
                end
            end
        end
    end
end

local function Revive()
    local character = LocalPlayer.Character
    if not character then return end
    
    local hrp = character:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character then
            local otherChar = player.Character
            local otherHrp = otherChar:FindFirstChild("HumanoidRootPart")
            
            local otherDowned = SafeCall(function() return otherChar:GetAttribute("Downed") end)
            if otherHrp and otherDowned then
                if (hrp.Position - otherHrp.Position).Magnitude <= 15 then
                    SafeCall(function()
                        local event = SafeGetPath(ReplicatedStorage, "Events", "Character", "Interact")
                        if event then event:FireServer("Revive", true, player.Name) end
                    end)
                end
            end
        end
    end
end

local function SelfResurrect()
    local now = tick()
    if now - SelfResCD < 3 then return end
    
    local character = LocalPlayer.Character
    local isDowned = SafeCall(function() return character and character:GetAttribute("Downed") end)
    if not isDowned then return end
    
    SelfResCD = now
    SafeCall(function()
        local event = SafeGetPath(ReplicatedStorage, "Events", "Player", "ChangePlayerMode")
        if event then event:FireServer(true) end
    end)
end

local function ToggleBorder()
    State.Border = not State.Border
    
    if not CachedGame then
        CachedGame = Workspace:FindFirstChild("Game")
    end
    
    if not CachedGame then return end
    
    local mapFolder = CachedGame:FindFirstChild("Map")
    local invisParts = mapFolder and mapFolder:FindFirstChild("InvisParts")
    
    if invisParts then
        for _, obj in ipairs(invisParts:GetDescendants()) do
            if obj:IsA("BasePart") then
                obj.CanCollide = not State.Border
            end
        end
    end
end

local function SetFOV()
    local camera = Workspace.CurrentCamera
    if camera and camera.FieldOfView ~= Config.FOV then
        camera.FieldOfView = Config.FOV
    end
end

local function SetupCameraFOV()
    local camera = Workspace.CurrentCamera
    if camera then
        LastCamera = camera
        SetFOV()
        
        if Connections.CameraFOV then
            Connections.CameraFOV:Disconnect()
        end
        
        Connections.CameraFOV = camera:GetPropertyChangedSignal("FieldOfView"):Connect(function()
            if camera.FieldOfView ~= Config.FOV then
                camera.FieldOfView = Config.FOV
            end
        end)
    end
end

Connections.CameraChange = Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
    local camera = Workspace.CurrentCamera
    if camera and camera ~= LastCamera then
        SetupCameraFOV()
    end
end)

local function ToggleFullbright()
    FullbrightEnabled = not FullbrightEnabled
    
    if FullbrightEnabled then
        SavedLighting = {
            Lighting.Brightness,
            Lighting.Ambient,
            Lighting.OutdoorAmbient,
            Lighting.ClockTime,
            Lighting.FogEnd
        }
        
        Lighting.Brightness = 1.2
        Lighting.Ambient = Color3.fromRGB(90, 90, 90)
        Lighting.OutdoorAmbient = Color3.fromRGB(90, 90, 90)
        Lighting.ClockTime = 14
        Lighting.FogEnd = 5000
    elseif SavedLighting then
        Lighting.Brightness = SavedLighting[1]
        Lighting.Ambient = SavedLighting[2]
        Lighting.OutdoorAmbient = SavedLighting[3]
        Lighting.ClockTime = SavedLighting[4]
        Lighting.FogEnd = SavedLighting[5]
    end
end

local function FixCola()
    SafeCall(function()
        local eventPath = SafeGetPath(LocalPlayer, "PlayerScripts", "Events", "temporary_events", "UseKeybind")
        if not eventPath then return end
        
        local mt = getrawmetatable(eventPath)
        local oldNamecall = mt.__namecall
        
        setreadonly(mt, false)
        mt.__namecall = newcclosure(function(self, ...)
            local method = getnamecallmethod()
            local args = {...}
            
            if method == "Fire" and self == eventPath and args[1] and args[1].Key == "Cola" then
                local toolAction = SafeGetPath(ReplicatedStorage, "Events", "Character", "ToolAction")
                if toolAction then toolAction:FireServer(0, 19) end
                return task.wait()
            end
            
            return oldNamecall(self, ...)
        end)
        setreadonly(mt, true)
    end)
end

local ColaOldNamecall = nil

local function ToggleInfiniteCola(enabled)
    State.InfiniteCola = enabled
    
    local toolActionEvent = SafeGetPath(ReplicatedStorage, "Events", "Character", "ToolAction")
    local speedBoostEvent = SafeGetPath(ReplicatedStorage, "Events", "Character", "SpeedBoost")
    
    if not toolActionEvent or not speedBoostEvent then 
        warn("[Evade Helper] Cola events not found - feature disabled")
        return 
    end
    
    if enabled then
        local mt = getrawmetatable(toolActionEvent)
        
        ColaOldNamecall = ColaOldNamecall or mt.__namecall
        local rateLimit = 0
        
        setreadonly(mt, false)
        mt.__namecall = newcclosure(function(self, ...)
            local method = getnamecallmethod()
            local args = {...}
            
            if method == "FireServer" and self == toolActionEvent and args[2] == 19 then
                local currentTime = tick()
                if currentTime - rateLimit >= 0.1 then
                    rateLimit = currentTime
                    ColaDrank = true
                    
                    task.delay(2.14, function()
                        if State.InfiniteCola then
                            firesignal(speedBoostEvent.OnClientEvent, "Cola", ColaConfig.Speed, ColaConfig.Duration, Color3.fromRGB(199, 141, 93))
                        end
                    end)
                    return nil
                end
            end
            
            return ColaOldNamecall(self, ...)
        end)
        setreadonly(mt, true)
    else
        ColaDrank = false
        
        if ColaOldNamecall then
            local mt = getrawmetatable(toolActionEvent)
            
            setreadonly(mt, false)
            mt.__namecall = ColaOldNamecall
            setreadonly(mt, true)
        end
    end
end

local function GetVoteEvent()
    return SafeGetPath(ReplicatedStorage, "Events", "Player", "Vote")
end

local function FindInList(name, list)
    if not name or name == "" then return nil end
    for _, item in ipairs(list) do
        if item:lower() == name:lower() then
            return item
        end
    end
    return nil
end

local function FireAdmin(command, value)
    SafeCall(function()
        local event = SafeGetPath(ReplicatedStorage, "Events", "CustomServers", "Admin")
        if event then event:FireServer(command, value) end
    end)
end

local function VoteMapLoop()
    if not State.VoteMap then return end
    local event = GetVoteEvent()
    if event then SafeCall(function() event:FireServer(State.MapIndex, false) end) end
    task.delay(1, VoteMapLoop)
end

local function VoteModeLoop()
    if not State.VoteMode then return end
    local event = GetVoteEvent()
    if event then SafeCall(function() event:FireServer(State.ModeIndex, true) end) end
    task.delay(1, VoteModeLoop)
end

local function StartMapVoting()
    if State.VoteMap then return end
    State.VoteMap = true
    VoteMapLoop()
end

local function StopMapVoting()
    State.VoteMap = false
end

local function StartModeVoting()
    if State.VoteMode then return end
    State.VoteMode = true
    VoteModeLoop()
end

local function StopModeVoting()
    State.VoteMode = false
end

-- ═══════════════════════════════════════════════════════
-- COMPLETELY REDESIGNED GUI - Modern glassmorphism style
-- ═══════════════════════════════════════════════════════

local COLORS = {
    Background = Color3.fromRGB(15, 15, 20),
    Surface = Color3.fromRGB(22, 22, 30),
    SurfaceHover = Color3.fromRGB(30, 30, 40),
    Card = Color3.fromRGB(28, 28, 38),
    Primary = Color3.fromRGB(88, 101, 242),    -- Discord-like blue/purple
    PrimaryDark = Color3.fromRGB(71, 82, 196),
    Success = Color3.fromRGB(87, 242, 135),
    Danger = Color3.fromRGB(237, 66, 69),
    Warning = Color3.fromRGB(254, 231, 92),
    Text = Color3.fromRGB(220, 221, 222),
    TextMuted = Color3.fromRGB(114, 118, 125),
    TextDim = Color3.fromRGB(72, 75, 81),
    Border = Color3.fromRGB(40, 40, 55),
    ActiveGlow = Color3.fromRGB(88, 101, 242),
    Accent = Color3.fromRGB(235, 69, 158),     -- Pink accent
    AccentAlt = Color3.fromRGB(69, 203, 235),   -- Cyan accent
}

local function Tween(obj, props, duration, style, direction)
    local tweenInfo = TweenInfo.new(
        duration or 0.2,
        style or Enum.EasingStyle.Quart,
        direction or Enum.EasingDirection.Out
    )
    TweenService:Create(obj, tweenInfo, props):Play()
end

local function AddShadow(parent, depth)
    depth = depth or 4
    local shadow = Instance.new("ImageLabel")
    shadow.Name = "Shadow"
    shadow.BackgroundTransparency = 1
    shadow.Image = "rbxassetid://6014261993"
    shadow.ImageColor3 = Color3.fromRGB(0, 0, 0)
    shadow.ImageTransparency = 0.6
    shadow.ScaleType = Enum.ScaleType.Slice
    shadow.SliceCenter = Rect.new(49, 49, 450, 450)
    shadow.Size = UDim2.new(1, depth * 6, 1, depth * 6)
    shadow.Position = UDim2.new(0, -depth * 3, 0, -depth * 3)
    shadow.ZIndex = parent.ZIndex - 1
    shadow.Parent = parent
    return shadow
end

local function CreateModernButton(parent, text, icon, position, size, callback, toggleState)
    local container = Instance.new("Frame")
    container.Name = text:gsub("%s+", "")
    container.Size = size or UDim2.new(1, -16, 0, 36)
    container.Position = position or UDim2.new(0, 8, 0, 0)
    container.BackgroundColor3 = COLORS.Surface
    container.BorderSizePixel = 0
    container.Parent = parent
    
    local corner = Instance.new("UICorner", container)
    corner.CornerRadius = UDim.new(0, 8)
    
    local stroke = Instance.new("UIStroke", container)
    stroke.Color = COLORS.Border
    stroke.Thickness = 1
    stroke.Transparency = 0.5
    
    local button = Instance.new("TextButton")
    button.Name = "Btn"
    button.Size = UDim2.new(1, 0, 1, 0)
    button.BackgroundTransparency = 1
    button.Text = ""
    button.AutoButtonColor = false
    button.Parent = container
    
    -- Icon
    if icon then
        local iconLabel = Instance.new("TextLabel")
        iconLabel.Name = "Icon"
        iconLabel.Size = UDim2.new(0, 20, 0, 20)
        iconLabel.Position = UDim2.new(0, 10, 0.5, -10)
        iconLabel.BackgroundTransparency = 1
        iconLabel.Text = icon
        iconLabel.TextColor3 = COLORS.TextMuted
        iconLabel.TextSize = 14
        iconLabel.Font = Enum.Font.GothamBold
        iconLabel.Parent = container
    end
    
    local label = Instance.new("TextLabel")
    label.Name = "Label"
    label.Size = UDim2.new(1, icon and -70 or -20, 1, 0)
    label.Position = UDim2.new(0, icon and 34 or 10, 0, 0)
    label.BackgroundTransparency = 1
    label.Text = text
    label.TextColor3 = COLORS.Text
    label.TextSize = 12
    label.Font = Enum.Font.GothamMedium
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = container
    
    -- Toggle indicator
    local indicator = Instance.new("Frame")
    indicator.Name = "Indicator"
    indicator.Size = UDim2.new(0, 36, 0, 18)
    indicator.Position = UDim2.new(1, -46, 0.5, -9)
    indicator.BackgroundColor3 = COLORS.TextDim
    indicator.Parent = container
    Instance.new("UICorner", indicator).CornerRadius = UDim.new(1, 0)
    
    local dot = Instance.new("Frame")
    dot.Name = "Dot"
    dot.Size = UDim2.new(0, 14, 0, 14)
    dot.Position = UDim2.new(0, 2, 0.5, -7)
    dot.BackgroundColor3 = Color3.new(1, 1, 1)
    dot.Parent = indicator
    Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)
    
    local isActive = false
    
    local function SetActive(active)
        isActive = active
        Tween(indicator, {BackgroundColor3 = active and COLORS.Primary or COLORS.TextDim}, 0.25)
        Tween(dot, {Position = active and UDim2.new(1, -16, 0.5, -7) or UDim2.new(0, 2, 0.5, -7)}, 0.25)
        Tween(stroke, {Color = active and COLORS.Primary or COLORS.Border}, 0.25)
        
        if icon then
            local iconLabel = container:FindFirstChild("Icon")
            if iconLabel then
                Tween(iconLabel, {TextColor3 = active and COLORS.Primary or COLORS.TextMuted}, 0.25)
            end
        end
    end
    
    container:SetAttribute("SetActive", "")
    container.SetActive = SetActive
    
    -- Hover effects
    button.MouseEnter:Connect(function()
        Tween(container, {BackgroundColor3 = COLORS.SurfaceHover}, 0.15)
    end)
    button.MouseLeave:Connect(function()
        Tween(container, {BackgroundColor3 = COLORS.Surface}, 0.15)
    end)
    
    button.MouseButton1Click:Connect(function()
        if callback then callback() end
        -- Quick press animation
        Tween(container, {BackgroundColor3 = COLORS.Primary}, 0.05)
        task.delay(0.1, function()
            Tween(container, {BackgroundColor3 = COLORS.Surface}, 0.15)
        end)
    end)
    
    return container, SetActive
end

local function CreateModernSmallButton(parent, text, position, size, callback, color)
    local button = Instance.new("TextButton")
    button.Name = text:gsub("%s+", "")
    button.Size = size or UDim2.new(0, 60, 0, 28)
    button.Position = position or UDim2.new(0, 0, 0, 0)
    button.BackgroundColor3 = color or COLORS.Surface
    button.Text = text
    button.TextColor3 = COLORS.Text
    button.TextSize = 11
    button.Font = Enum.Font.GothamMedium
    button.AutoButtonColor = false
    button.BorderSizePixel = 0
    button.Parent = parent
    
    Instance.new("UICorner", button).CornerRadius = UDim.new(0, 6)
    
    local stroke = Instance.new("UIStroke", button)
    stroke.Color = COLORS.Border
    stroke.Thickness = 1
    stroke.Transparency = 0.5
    
    button.MouseEnter:Connect(function()
        Tween(button, {BackgroundColor3 = COLORS.SurfaceHover}, 0.15)
    end)
    button.MouseLeave:Connect(function()
        Tween(button, {BackgroundColor3 = color or COLORS.Surface}, 0.15)
    end)
    
    if callback then button.MouseButton1Click:Connect(callback) end
    
    return button
end

local function CreateSectionHeader(parent, text, y)
    local header = Instance.new("TextLabel")
    header.Size = UDim2.new(1, -16, 0, 20)
    header.Position = UDim2.new(0, 8, 0, y)
    header.BackgroundTransparency = 1
    header.Text = text
    header.TextColor3 = COLORS.TextMuted
    header.TextSize = 10
    header.Font = Enum.Font.GothamBold
    header.TextXAlignment = Enum.TextXAlignment.Left
    header.Parent = parent
    
    -- Subtle line under header
    local line = Instance.new("Frame")
    line.Size = UDim2.new(1, -16, 0, 1)
    line.Position = UDim2.new(0, 8, 0, y + 18)
    line.BackgroundColor3 = COLORS.Border
    line.BackgroundTransparency = 0.5
    line.BorderSizePixel = 0
    line.Parent = parent
    
    return header
end

local function CreateModernInput(parent, placeholder, position, size, callback)
    local input = Instance.new("TextBox")
    input.Size = size or UDim2.new(0, 120, 0, 28)
    input.Position = position or UDim2.new(0, 0, 0, 0)
    input.BackgroundColor3 = COLORS.Surface
    input.Text = ""
    input.PlaceholderText = placeholder
    input.TextColor3 = COLORS.Text
    input.PlaceholderColor3 = COLORS.TextDim
    input.TextSize = 11
    input.Font = Enum.Font.Gotham
    input.ClearTextOnFocus = false
    input.BorderSizePixel = 0
    input.Parent = parent
    
    Instance.new("UICorner", input).CornerRadius = UDim.new(0, 6)
    
    local stroke = Instance.new("UIStroke", input)
    stroke.Color = COLORS.Border
    stroke.Thickness = 1
    
    input.Focused:Connect(function()
        Tween(stroke, {Color = COLORS.Primary}, 0.2)
    end)
    input.FocusLost:Connect(function()
        Tween(stroke, {Color = COLORS.Border}, 0.2)
        if callback then callback(input.Text) end
    end)
    
    return input
end

local function MakeDraggable(frame)
    local dragging, dragStart, startPos = false, nil, nil
    local dragArea = Instance.new("Frame")
    dragArea.Name = "DragArea"
    dragArea.Size = UDim2.new(1, 0, 0, 40)
    dragArea.Position = UDim2.new(0, 0, 0, 0)
    dragArea.BackgroundTransparency = 1
    dragArea.ZIndex = frame.ZIndex + 10
    dragArea.Parent = frame
    
    dragArea.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            dragStart = input.Position
            startPos = frame.Position
        end
    end)
    dragArea.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            local delta = input.Position - dragStart
            frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)
end

-- Store toggle functions for UpdateGUI
local ToggleFunctions = {}

local function UpdateGUI()
    -- Toggle functions are called directly by their respective buttons now
end

local function UpdateSliderUI(value)
    if not SliderTrack then return end
    local pos = math.clamp((value - SliderMin) / (SliderMax - SliderMin), 0, 1)
    SliderFill.Size = UDim2.new(pos, 0, 1, 0)
    SliderThumb.Position = UDim2.new(pos, -7, 0.5, -7)
    if SliderLabel then
        SliderLabel.Text = string.format("%.1fx", value)
    end
end

local function CreateVIPPanel()
    if VIPPanel then VIPPanel.Visible = not VIPPanel.Visible return end
    
    VIPPanel = Instance.new("Frame")
    VIPPanel.Name = "VIP"
    VIPPanel.Size = UDim2.new(0, 280, 0, 200)
    VIPPanel.Position = UDim2.new(0, 310, 0, 60)
    VIPPanel.BackgroundColor3 = COLORS.Background
    VIPPanel.BorderSizePixel = 0
    VIPPanel.Parent = GUI
    Instance.new("UICorner", VIPPanel).CornerRadius = UDim.new(0, 12)
    
    local vipStroke = Instance.new("UIStroke", VIPPanel)
    vipStroke.Color = COLORS.Border
    vipStroke.Thickness = 1
    
    AddShadow(VIPPanel, 5)
    
    -- Title bar
    local titleBar = Instance.new("Frame")
    titleBar.Size = UDim2.new(1, 0, 0, 36)
    titleBar.BackgroundColor3 = COLORS.Surface
    titleBar.BorderSizePixel = 0
    titleBar.Parent = VIPPanel
    Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 12)
    
    -- Fix bottom corners of title bar
    local titleFix = Instance.new("Frame")
    titleFix.Size = UDim2.new(1, 0, 0, 12)
    titleFix.Position = UDim2.new(0, 0, 1, -12)
    titleFix.BackgroundColor3 = COLORS.Surface
    titleFix.BorderSizePixel = 0
    titleFix.Parent = titleBar
    
    local vipTitle = Instance.new("TextLabel")
    vipTitle.Size = UDim2.new(1, -40, 1, 0)
    vipTitle.Position = UDim2.new(0, 12, 0, 0)
    vipTitle.BackgroundTransparency = 1
    vipTitle.Text = "⚡ VIP SERVER"
    vipTitle.TextColor3 = COLORS.Warning
    vipTitle.TextSize = 12
    vipTitle.Font = Enum.Font.GothamBold
    vipTitle.TextXAlignment = Enum.TextXAlignment.Left
    vipTitle.Parent = titleBar
    
    local closeBtn = Instance.new("TextButton")
    closeBtn.Size = UDim2.new(0, 28, 0, 28)
    closeBtn.Position = UDim2.new(1, -34, 0.5, -14)
    closeBtn.BackgroundColor3 = COLORS.Danger
    closeBtn.BackgroundTransparency = 0.8
    closeBtn.Text = "✕"
    closeBtn.TextColor3 = COLORS.Danger
    closeBtn.TextSize = 12
    closeBtn.Font = Enum.Font.GothamBold
    closeBtn.AutoButtonColor = false
    closeBtn.BorderSizePixel = 0
    closeBtn.Parent = titleBar
    Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 6)
    closeBtn.MouseButton1Click:Connect(function() VIPPanel.Visible = false end)
    
    local y = 44
    
    -- Map Vote Section
    CreateSectionHeader(VIPPanel, "MAP VOTING", y)
    y = y + 24
    
    local mapRow = Instance.new("Frame")
    mapRow.Size = UDim2.new(1, -16, 0, 30)
    mapRow.Position = UDim2.new(0, 8, 0, y)
    mapRow.BackgroundTransparency = 1
    mapRow.Parent = VIPPanel
    
    local autoVoteBtn = CreateModernSmallButton(mapRow, "AUTO", UDim2.new(0, 0, 0, 0), UDim2.new(0, 50, 0, 28), nil, COLORS.Surface)
    autoVoteBtn.MouseButton1Click:Connect(function()
        if State.VoteMap then StopMapVoting() else StartMapVoting() end
        autoVoteBtn.Text = State.VoteMap and "ON" or "AUTO"
        autoVoteBtn.BackgroundColor3 = State.VoteMap and COLORS.Primary or COLORS.Surface
    end)
    
    for i = 1, 4 do
        local btn = CreateModernSmallButton(mapRow, tostring(i), UDim2.new(0, 54 + (i-1) * 34, 0, 0), UDim2.new(0, 30, 0, 28), function()
            State.MapIndex = i
            for j = 1, 4 do 
                local b = mapRow:FindFirstChild(tostring(j)) 
                if b then b.BackgroundColor3 = j == i and COLORS.Primary or COLORS.Surface end 
            end
        end)
        if i == 1 then btn.BackgroundColor3 = COLORS.Primary end
    end
    
    y = y + 36
    
    -- Mode Vote Section
    CreateSectionHeader(VIPPanel, "MODE VOTING", y)
    y = y + 24
    
    local modeRow = Instance.new("Frame")
    modeRow.Size = UDim2.new(1, -16, 0, 30)
    modeRow.Position = UDim2.new(0, 8, 0, y)
    modeRow.BackgroundTransparency = 1
    modeRow.Parent = VIPPanel
    
    local autoModeBtn = CreateModernSmallButton(modeRow, "AUTO", UDim2.new(0, 0, 0, 0), UDim2.new(0, 50, 0, 28), nil, COLORS.Surface)
    autoModeBtn.MouseButton1Click:Connect(function()
        if State.VoteMode then StopModeVoting() else StartModeVoting() end
        autoModeBtn.Text = State.VoteMode and "ON" or "AUTO"
        autoModeBtn.BackgroundColor3 = State.VoteMode and COLORS.Primary or COLORS.Surface
    end)
    
    for i = 1, 4 do
        local btn = CreateModernSmallButton(modeRow, tostring(i), UDim2.new(0, 54 + (i-1) * 34, 0, 0), UDim2.new(0, 30, 0, 28), function()
            State.ModeIndex = i
            for j = 1, 4 do 
                local b = modeRow:FindFirstChild(tostring(j)) 
                if b then b.BackgroundColor3 = j == i and COLORS.Primary or COLORS.Surface end 
            end
        end)
        if i == 1 then btn.BackgroundColor3 = COLORS.Primary end
    end
    
    y = y + 38
    
    -- Admin controls
    local adminRow = Instance.new("Frame")
    adminRow.Size = UDim2.new(1, -16, 0, 28)
    adminRow.Position = UDim2.new(0, 8, 0, y)
    adminRow.BackgroundTransparency = 1
    adminRow.Parent = VIPPanel
    
    local mapInput = CreateModernInput(adminRow, "Map name...", UDim2.new(0, 0, 0, 0), UDim2.new(0, 130, 0, 28), function(text) State.MapSearch = text end)
    CreateModernSmallButton(adminRow, "+", UDim2.new(0, 134, 0, 0), UDim2.new(0, 28, 0, 28), function() local map = FindInList(State.MapSearch, Maps) if map then FireAdmin("AddMap", map) end end, COLORS.Success)
    CreateModernSmallButton(adminRow, "−", UDim2.new(0, 166, 0, 0), UDim2.new(0, 28, 0, 28), function() local map = FindInList(State.MapSearch, Maps) if map then FireAdmin("RemoveMap", map) end end, COLORS.Danger)
    
    y = y + 34
    
    local modeAdminRow = Instance.new("Frame")
    modeAdminRow.Size = UDim2.new(1, -16, 0, 28)
    modeAdminRow.Position = UDim2.new(0, 8, 0, y)
    modeAdminRow.BackgroundTransparency = 1
    modeAdminRow.Parent = VIPPanel
    
    local modeInput = CreateModernInput(modeAdminRow, "Mode name...", UDim2.new(0, 0, 0, 0), UDim2.new(0, 130, 0, 28), function(text) State.GamemodeSearch = text end)
    CreateModernSmallButton(modeAdminRow, "SET", UDim2.new(0, 134, 0, 0), UDim2.new(0, 60, 0, 28), function() local mode = FindInList(State.GamemodeSearch, Modes) if mode then FireAdmin("Gamemode", mode) end end, COLORS.Primary)
    
    MakeDraggable(VIPPanel)
end

local function CreateMainGUI()
    if GUI then SafeCall(function() GUI:Destroy() end) end
    
    GUI = Instance.new("ScreenGui")
    GUI.Name = "EvadeHelper"
    GUI.ResetOnSpawn = false
    GUI.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    SafeCall(function() GUI.Parent = game:GetService("CoreGui") end)
    if not GUI.Parent then GUI.Parent = PlayerGui end
    
    -- Main container
    local main = Instance.new("Frame")
    main.Name = "Main"
    main.Size = UDim2.new(0, 280, 0, 480)
    main.Position = UDim2.new(0, 20, 0, 60)
    main.BackgroundColor3 = COLORS.Background
    main.BorderSizePixel = 0
    main.Parent = GUI
    
    Instance.new("UICorner", main).CornerRadius = UDim.new(0, 12)
    
    local mainStroke = Instance.new("UIStroke", main)
    mainStroke.Color = COLORS.Border
    mainStroke.Thickness = 1
    
    AddShadow(main, 6)
    
    -- ═══ Title Bar ═══
    local titleBar = Instance.new("Frame")
    titleBar.Name = "TitleBar"
    titleBar.Size = UDim2.new(1, 0, 0, 40)
    titleBar.BackgroundColor3 = COLORS.Surface
    titleBar.BorderSizePixel = 0
    titleBar.Parent = main
    Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 12)
    
    local titleFix = Instance.new("Frame")
    titleFix.Size = UDim2.new(1, 0, 0, 12)
    titleFix.Position = UDim2.new(0, 0, 1, -12)
    titleFix.BackgroundColor3 = COLORS.Surface
    titleFix.BorderSizePixel = 0
    titleFix.Parent = titleBar
    
    -- Accent gradient on title
    local titleGradient = Instance.new("UIGradient", titleBar)
    titleGradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(30, 30, 42)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(22, 22, 30))
    })
    titleGradient.Rotation = 90
    
    local titleIcon = Instance.new("TextLabel")
    titleIcon.Size = UDim2.new(0, 24, 0, 24)
    titleIcon.Position = UDim2.new(0, 10, 0.5, -12)
    titleIcon.BackgroundTransparency = 1
    titleIcon.Text = "⚡"
    titleIcon.TextSize = 16
    titleIcon.Parent = titleBar
    
    local titleText = Instance.new("TextLabel")
    titleText.Size = UDim2.new(0, 160, 1, 0)
    titleText.Position = UDim2.new(0, 34, 0, 0)
    titleText.BackgroundTransparency = 1
    titleText.Text = IsEvadeGame() and "EVADE HELPER" or "HELPER"
    titleText.TextColor3 = COLORS.Text
    titleText.TextSize = 14
    titleText.Font = Enum.Font.GothamBlack
    titleText.TextXAlignment = Enum.TextXAlignment.Left
    titleText.Parent = titleBar
    
    local versionLabel = Instance.new("TextLabel")
    versionLabel.Size = UDim2.new(0, 30, 0, 16)
    versionLabel.Position = UDim2.new(0, titleText.Position.X.Offset + (IsEvadeGame() and 108 or 60), 0.5, -8)
    versionLabel.BackgroundColor3 = COLORS.Primary
    versionLabel.Text = "V9"
    versionLabel.TextColor3 = Color3.new(1, 1, 1)
    versionLabel.TextSize = 9
    versionLabel.Font = Enum.Font.GothamBold
    versionLabel.Parent = titleBar
    Instance.new("UICorner", versionLabel).CornerRadius = UDim.new(0, 4)
    
    -- Title buttons
    local vipBtn = CreateModernSmallButton(titleBar, "VIP", UDim2.new(1, -74, 0.5, -12), UDim2.new(0, 36, 0, 24), CreateVIPPanel, COLORS.Warning)
    vipBtn.TextColor3 = COLORS.Background
    vipBtn.TextSize = 9
    vipBtn.Font = Enum.Font.GothamBold
    
    local minimizeBtn = Instance.new("TextButton")
    minimizeBtn.Size = UDim2.new(0, 28, 0, 24)
    minimizeBtn.Position = UDim2.new(1, -34, 0.5, -12)
    minimizeBtn.BackgroundColor3 = COLORS.Danger
    minimizeBtn.BackgroundTransparency = 0.7
    minimizeBtn.Text = "—"
    minimizeBtn.TextColor3 = COLORS.Danger
    minimizeBtn.TextSize = 14
    minimizeBtn.Font = Enum.Font.GothamBold
    minimizeBtn.AutoButtonColor = false
    minimizeBtn.BorderSizePixel = 0
    minimizeBtn.Parent = titleBar
    Instance.new("UICorner", minimizeBtn).CornerRadius = UDim.new(0, 6)
    minimizeBtn.MouseButton1Click:Connect(function() main.Visible = false end)
    
    -- ═══ Scroll Frame for content ═══
    local scroll = Instance.new("ScrollingFrame")
    scroll.Name = "Content"
    scroll.Size = UDim2.new(1, 0, 1, -44)
    scroll.Position = UDim2.new(0, 0, 0, 44)
    scroll.BackgroundTransparency = 1
    scroll.ScrollBarThickness = 3
    scroll.ScrollBarImageColor3 = COLORS.Primary
    scroll.ScrollBarImageTransparency = 0.5
    scroll.CanvasSize = UDim2.new(0, 0, 0, 540)
    scroll.BorderSizePixel = 0
    scroll.Parent = main
    
    local y = 8
    
    -- ═══ DISPLAY SECTION ═══
    CreateSectionHeader(scroll, "🖥  DISPLAY", y)
    y = y + 26
    
    -- FOV Row
    local fovRow = Instance.new("Frame")
    fovRow.Size = UDim2.new(1, -16, 0, 32)
    fovRow.Position = UDim2.new(0, 8, 0, y)
    fovRow.BackgroundTransparency = 1
    fovRow.Parent = scroll
    
    local fovLabel = Instance.new("TextLabel")
    fovLabel.Size = UDim2.new(0, 35, 1, 0)
    fovLabel.BackgroundTransparency = 1
    fovLabel.Text = "FOV"
    fovLabel.TextColor3 = COLORS.TextMuted
    fovLabel.TextSize = 11
    fovLabel.Font = Enum.Font.GothamMedium
    fovLabel.TextXAlignment = Enum.TextXAlignment.Left
    fovLabel.Parent = fovRow
    
    local fov90Btn = CreateModernSmallButton(fovRow, "90°", UDim2.new(0, 40, 0, 2), UDim2.new(0, 45, 0, 28), function()
        Config.FOV = 90 
        SetFOV()
        fov90Btn.BackgroundColor3 = COLORS.Primary
        fovRow:FindFirstChild("120°").BackgroundColor3 = COLORS.Surface
    end)
    
    local fov120Btn = CreateModernSmallButton(fovRow, "120°", UDim2.new(0, 89, 0, 2), UDim2.new(0, 45, 0, 28), function()
        Config.FOV = 120 
        SetFOV()
        fov120Btn.BackgroundColor3 = COLORS.Primary
        fovRow:FindFirstChild("90°").BackgroundColor3 = COLORS.Surface
    end)
    fov120Btn.BackgroundColor3 = COLORS.Primary
    
    local brightBtn = CreateModernSmallButton(fovRow, "💡 Light", UDim2.new(0, 140, 0, 2), UDim2.new(0, 65, 0, 28), function()
        ToggleFullbright()
        brightBtn.BackgroundColor3 = FullbrightEnabled and COLORS.Primary or COLORS.Surface
    end)
    
    y = y + 40
    
    -- ═══ GAMEPLAY SECTION ═══
    CreateSectionHeader(scroll, "🎮  GAMEPLAY", y)
    y = y + 26
    
    local _, borderToggle = CreateModernButton(scroll, "No Border", "🚧", UDim2.new(0, 8, 0, y), UDim2.new(1, -16, 0, 36), function()
        ToggleBorder()
        borderToggle(State.Border)
    end)
    ToggleFunctions.Border = borderToggle
    y = y + 42
    
    local _, antiToggle = CreateModernButton(scroll, "Anti Nextbot", "🛡", UDim2.new(0, 8, 0, y), UDim2.new(1, -16, 0, 36), function()
        State.AntiNextbot = not State.AntiNextbot
        if State.AntiNextbot then LoadNPCs() end
        antiToggle(State.AntiNextbot)
    end)
    ToggleFunctions.Anti = antiToggle
    y = y + 42
    
    local _, farmToggle = CreateModernButton(scroll, "Auto Farm", "🎯", UDim2.new(0, 8, 0, y), UDim2.new(1, -16, 0, 36), function()
        State.AutoFarm = not State.AutoFarm
        if not State.AutoFarm then CurrentTarget = nil end
        farmToggle(State.AutoFarm)
    end)
    ToggleFunctions.Farm = farmToggle
    y = y + 42
    
    local _, edgeToggle = CreateModernButton(scroll, "Edge Boost", "📐", UDim2.new(0, 8, 0, y), UDim2.new(1, -16, 0, 36), function()
        State.EdgeBoost = not State.EdgeBoost
        SetupEdgeBoost()
        edgeToggle(State.EdgeBoost)
    end)
    ToggleFunctions.Edge = edgeToggle
    y = y + 42
    
    local _, upfixToggle = CreateModernButton(scroll, "Upside Down Fix", "🔄", UDim2.new(0, 8, 0, y), UDim2.new(1, -16, 0, 36), function()
        State.UpsideDownFix = not State.UpsideDownFix
        ToggleUpsideDownFix(State.UpsideDownFix)
        upfixToggle(State.UpsideDownFix)
    end)
    ToggleFunctions.UpFix = upfixToggle
    y = y + 48
    
    -- ═══ COLA SECTION ═══
    CreateSectionHeader(scroll, "🥤  COLA", y)
    y = y + 26
    
    local colaRow = Instance.new("Frame")
    colaRow.Size = UDim2.new(1, -16, 0, 32)
    colaRow.Position = UDim2.new(0, 8, 0, y)
    colaRow.BackgroundTransparency = 1
    colaRow.Parent = scroll
    
    local fixColaBtn = CreateModernSmallButton(colaRow, "🔧 Fix", UDim2.new(0, 0, 0, 2), UDim2.new(0, 60, 0, 28), FixCola, COLORS.Warning)
    fixColaBtn.TextColor3 = COLORS.Background
    
    local infColaBtn = CreateModernSmallButton(colaRow, "∞ Infinite", UDim2.new(0, 64, 0, 2), UDim2.new(0, 80, 0, 28), function()
        State.InfiniteCola = not State.InfiniteCola
        ToggleInfiniteCola(State.InfiniteCola)
        infColaBtn.BackgroundColor3 = State.InfiniteCola and COLORS.Primary or COLORS.Surface
    end)
    
    y = y + 40
    
    -- Speed Slider
    local sliderContainer = Instance.new("Frame")
    sliderContainer.Size = UDim2.new(1, -16, 0, 44)
    sliderContainer.Position = UDim2.new(0, 8, 0, y)
    sliderContainer.BackgroundColor3 = COLORS.Surface
    sliderContainer.BorderSizePixel = 0
    sliderContainer.Parent = scroll
    Instance.new("UICorner", sliderContainer).CornerRadius = UDim.new(0, 8)
    Instance.new("UIStroke", sliderContainer).Color = COLORS.Border
    
    local speedTitle = Instance.new("TextLabel")
    speedTitle.Size = UDim2.new(0, 100, 0, 16)
    speedTitle.Position = UDim2.new(0, 10, 0, 4)
    speedTitle.BackgroundTransparency = 1
    speedTitle.Text = "Speed Multiplier"
    speedTitle.TextColor3 = COLORS.TextMuted
    speedTitle.TextSize = 9
    speedTitle.Font = Enum.Font.GothamMedium
    speedTitle.TextXAlignment = Enum.TextXAlignment.Left
    speedTitle.Parent = sliderContainer
    
    SliderLabel = Instance.new("TextLabel")
    SliderLabel.Size = UDim2.new(0, 40, 0, 16)
    SliderLabel.Position = UDim2.new(1, -48, 0, 4)
    SliderLabel.BackgroundTransparency = 1
    SliderLabel.Text = string.format("%.1fx", ColaConfig.Speed)
    SliderLabel.TextColor3 = COLORS.Primary
    SliderLabel.TextSize = 11
    SliderLabel.Font = Enum.Font.GothamBold
    SliderLabel.TextXAlignment = Enum.TextXAlignment.Right
    SliderLabel.Parent = sliderContainer
    
    SliderTrack = Instance.new("Frame")
    SliderTrack.Size = UDim2.new(1, -20, 0, 6)
    SliderTrack.Position = UDim2.new(0, 10, 0, 28)
    SliderTrack.BackgroundColor3 = COLORS.TextDim
    SliderTrack.BorderSizePixel = 0
    SliderTrack.Parent = sliderContainer
    Instance.new("UICorner", SliderTrack).CornerRadius = UDim.new(1, 0)
    
    local initialPos = (ColaConfig.Speed - SliderMin) / (SliderMax - SliderMin)
    
    SliderFill = Instance.new("Frame")
    SliderFill.Size = UDim2.new(initialPos, 0, 1, 0)
    SliderFill.BackgroundColor3 = COLORS.Primary
    SliderFill.BorderSizePixel = 0
    SliderFill.Parent = SliderTrack
    Instance.new("UICorner", SliderFill).CornerRadius = UDim.new(1, 0)
    
    -- Gradient on fill
    local fillGradient = Instance.new("UIGradient", SliderFill)
    fillGradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, COLORS.Primary),
        ColorSequenceKeypoint.new(1, COLORS.Accent)
    })
    
    SliderThumb = Instance.new("Frame")
    SliderThumb.Size = UDim2.new(0, 14, 0, 14)
    SliderThumb.Position = UDim2.new(initialPos, -7, 0.5, -7)
    SliderThumb.BackgroundColor3 = Color3.new(1, 1, 1)
    SliderThumb.BorderSizePixel = 0
    SliderThumb.ZIndex = 5
    SliderThumb.Parent = SliderTrack
    Instance.new("UICorner", SliderThumb).CornerRadius = UDim.new(1, 0)
    
    -- Thumb glow
    local thumbGlow = Instance.new("UIStroke", SliderThumb)
    thumbGlow.Color = COLORS.Primary
    thumbGlow.Thickness = 2
    thumbGlow.Transparency = 0.3
    
    local sliderDragging = false
    local function UpdateSliderFromMouse(mousePos)
        if not SliderTrack then return end
        local pos = math.clamp((mousePos.X - SliderTrack.AbsolutePosition.X) / SliderTrack.AbsoluteSize.X, 0, 1)
        local val = math.round((SliderMin + pos * (SliderMax - SliderMin)) * 10) / 10
        val = math.clamp(val, SliderMin, SliderMax)
        ColaConfig.Speed = val
        UpdateSliderUI(val)
    end
    
    -- Make thumb draggable
    local thumbButton = Instance.new("TextButton")
    thumbButton.Size = UDim2.new(1, 8, 1, 8)
    thumbButton.Position = UDim2.new(0, -4, 0, -4)
    thumbButton.BackgroundTransparency = 1
    thumbButton.Text = ""
    thumbButton.ZIndex = 6
    thumbButton.Parent = SliderThumb
    
    thumbButton.InputBegan:Connect(function(input) if input.UserInputType == Enum.UserInputType.MouseButton1 then sliderDragging = true end end)
    UserInputService.InputEnded:Connect(function(input) if input.UserInputType == Enum.UserInputType.MouseButton1 then sliderDragging = false end end)
    UserInputService.InputChanged:Connect(function(input) if sliderDragging and input.UserInputType == Enum.UserInputType.MouseMovement then UpdateSliderFromMouse(input.Position) end end)
    
    -- Click track to set
    local trackButton = Instance.new("TextButton")
    trackButton.Size = UDim2.new(1, 0, 1, 10)
    trackButton.Position = UDim2.new(0, 0, 0, -5)
    trackButton.BackgroundTransparency = 1
    trackButton.Text = ""
    trackButton.ZIndex = 4
    trackButton.Parent = SliderTrack
    trackButton.MouseButton1Click:Connect(function()
        local mouse = UserInputService:GetMouseLocation()
        UpdateSliderFromMouse(Vector3.new(mouse.X, mouse.Y, 0))
    end)
    
    y = y + 52
    
    -- Duration input
    local durRow = Instance.new("Frame")
    durRow.Size = UDim2.new(1, -16, 0, 28)
    durRow.Position = UDim2.new(0, 8, 0, y)
    durRow.BackgroundTransparency = 1
    durRow.Parent = scroll
    
    local durLabel = Instance.new("TextLabel")
    durLabel.Size = UDim2.new(0, 80, 1, 0)
    durLabel.BackgroundTransparency = 1
    durLabel.Text = "Duration (s)"
    durLabel.TextColor3 = COLORS.TextMuted
    durLabel.TextSize = 10
    durLabel.Font = Enum.Font.GothamMedium
    durLabel.TextXAlignment = Enum.TextXAlignment.Left
    durLabel.Parent = durRow
    
    local durInput = CreateModernInput(durRow, "3.5", UDim2.new(0, 90, 0, 0), UDim2.new(0, 60, 0, 28), function(text) 
        local num = tonumber(text) 
        if num and num > 0 then ColaConfig.Duration = num end 
    end)
    durInput.Text = tostring(ColaConfig.Duration)
    
    -- Preset buttons
    local presetLabel = Instance.new("TextLabel")
    presetLabel.Size = UDim2.new(0, 50, 1, 0)
    presetLabel.Position = UDim2.new(0, 158, 0, 0)
    presetLabel.BackgroundTransparency = 1
    presetLabel.Text = "Preset:"
    presetLabel.TextColor3 = COLORS.TextDim
    presetLabel.TextSize = 9
    presetLabel.Font = Enum.Font.Gotham
    presetLabel.TextXAlignment = Enum.TextXAlignment.Left
    presetLabel.Parent = durRow
    
    CreateModernSmallButton(durRow, "1.4", UDim2.new(0, 200, 0, 0), UDim2.new(0, 28, 0, 28), function() ColaConfig.Speed = 1.4 UpdateSliderUI(1.4) end)
    CreateModernSmallButton(durRow, "1.6", UDim2.new(0, 232, 0, 0), UDim2.new(0, 28, 0, 28), function() ColaConfig.Speed = 1.6 UpdateSliderUI(1.6) end)
    
    y = y + 40
    
    -- ═══ KEYBINDS INFO ═══
    CreateSectionHeader(scroll, "⌨  KEYBINDS", y)
    y = y + 24
    
    local keybinds = {
        {"SPACE", "Bunny Hop (hold)"},
        {"X", "Bounce (hold)"},
        {"Q", "Carry (hold)"},
        {"E", "Revive"},
        {"R", "Self Resurrect"},
        {"P", "Toggle Fullbright"},
        {"R.SHIFT", "Toggle GUI"},
    }
    
    for _, kb in ipairs(keybinds) do
        local kbRow = Instance.new("Frame")
        kbRow.Size = UDim2.new(1, -16, 0, 20)
        kbRow.Position = UDim2.new(0, 8, 0, y)
        kbRow.BackgroundTransparency = 1
        kbRow.Parent = scroll
        
        local keyBadge = Instance.new("TextLabel")
        keyBadge.Size = UDim2.new(0, 55, 0, 18)
        keyBadge.BackgroundColor3 = COLORS.Surface
        keyBadge.Text = kb[1]
        keyBadge.TextColor3 = COLORS.AccentAlt
        keyBadge.TextSize = 8
        keyBadge.Font = Enum.Font.GothamBold
        keyBadge.Parent = kbRow
        Instance.new("UICorner", keyBadge).CornerRadius = UDim.new(0, 4)
        
        local keyDesc = Instance.new("TextLabel")
        keyDesc.Size = UDim2.new(1, -65, 0, 18)
        keyDesc.Position = UDim2.new(0, 60, 0, 0)
        keyDesc.BackgroundTransparency = 1
        keyDesc.Text = kb[2]
        keyDesc.TextColor3 = COLORS.TextDim
        keyDesc.TextSize = 10
        keyDesc.Font = Enum.Font.Gotham
        keyDesc.TextXAlignment = Enum.TextXAlignment.Left
        keyDesc.Parent = kbRow
        
        y = y + 22
    end
    
    y = y + 8
    scroll.CanvasSize = UDim2.new(0, 0, 0, y)
    
    MakeDraggable(main)
end

local function CreateTimerGUI()
    if TimerGUI then SafeCall(function() TimerGUI:Destroy() end) end
    TimerGUI = Instance.new("ScreenGui")
    TimerGUI.Name = "EvadeTimer"
    TimerGUI.ResetOnSpawn = false
    TimerGUI.Parent = PlayerGui
    
    local container = Instance.new("Frame", TimerGUI)
    container.Name = "Timer"
    container.AnchorPoint = Vector2.new(0.5, 0)
    container.Position = UDim2.new(0.5, 0, 0.015, 0)
    container.Size = UDim2.new(0, 120, 0, 52)
    container.BackgroundColor3 = COLORS.Background
    container.BorderSizePixel = 0
    Instance.new("UICorner", container).CornerRadius = UDim.new(0, 10)
    
    local timerStroke = Instance.new("UIStroke", container)
    timerStroke.Color = COLORS.Border
    timerStroke.Thickness = 1
    
    AddShadow(container, 3)
    
    -- Accent bar at top
    local accentBar = Instance.new("Frame")
    accentBar.Size = UDim2.new(1, -20, 0, 2)
    accentBar.Position = UDim2.new(0, 10, 0, 6)
    accentBar.BackgroundColor3 = COLORS.Primary
    accentBar.BorderSizePixel = 0
    accentBar.Parent = container
    Instance.new("UICorner", accentBar).CornerRadius = UDim.new(1, 0)
    
    local accentGrad = Instance.new("UIGradient", accentBar)
    accentGrad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, COLORS.Primary),
        ColorSequenceKeypoint.new(1, COLORS.Accent)
    })
    
    StatusLabel = Instance.new("TextLabel", container)
    StatusLabel.Position = UDim2.new(0.5, 0, 0, 12)
    StatusLabel.AnchorPoint = Vector2.new(0.5, 0)
    StatusLabel.Size = UDim2.new(1, 0, 0, 14)
    StatusLabel.BackgroundTransparency = 1
    StatusLabel.Font = Enum.Font.GothamBold
    StatusLabel.Text = "WAITING"
    StatusLabel.TextColor3 = COLORS.TextMuted
    StatusLabel.TextSize = 9
    
    TimerLabel = Instance.new("TextLabel", container)
    TimerLabel.Position = UDim2.new(0.5, 0, 0, 26)
    TimerLabel.AnchorPoint = Vector2.new(0.5, 0)
    TimerLabel.Size = UDim2.new(1, 0, 0, 22)
    TimerLabel.BackgroundTransparency = 1
    TimerLabel.Font = Enum.Font.GothamBlack
    TimerLabel.Text = "0:00"
    TimerLabel.TextColor3 = Color3.new(1, 1, 1)
    TimerLabel.TextSize = 20
end

local function UpdateTimer()
    if not CachedGame then CachedGame = Workspace:FindFirstChild("Game") end
    local stats = CachedGame and CachedGame:FindFirstChild("Stats")
    if not stats then
        if TimerLabel then TimerLabel.Text = "0:00" end
        if StatusLabel then StatusLabel.Text = "WAITING" end
        return
    end
    
    if Connections.Timer then Connections.Timer:Disconnect() end
    Connections.Timer = stats:GetAttributeChangedSignal("Timer"):Connect(function()
        local timer = stats:GetAttribute("Timer")
        local roundStarted = stats:GetAttribute("RoundStarted")
        if TimerLabel then
            local minutes = math.floor((timer or 0) / 60)
            local seconds = (timer or 0) % 60
            TimerLabel.Text = string.format("%d:%02d", minutes, seconds)
            TimerLabel.TextColor3 = (roundStarted and timer and timer <= 15) and COLORS.Danger or Color3.new(1, 1, 1)
        end
        if StatusLabel then
            StatusLabel.Text = roundStarted and "🔴 RUNNING" or "⏳ WAITING"
            StatusLabel.TextColor3 = roundStarted and COLORS.Success or COLORS.TextMuted
        end
    end)
end

-- ═══════════════════════════════════════════════════════
-- SPEED INDICATOR HUD (shows current bhop speed)
-- ═══════════════════════════════════════════════════════
local SpeedHUD = nil
local SpeedLabel = nil

local function CreateSpeedHUD()
    if SpeedHUD then return end
    
    SpeedHUD = Instance.new("ScreenGui")
    SpeedHUD.Name = "SpeedHUD"
    SpeedHUD.ResetOnSpawn = false
    SafeCall(function() SpeedHUD.Parent = game:GetService("CoreGui") end)
    if not SpeedHUD.Parent then SpeedHUD.Parent = PlayerGui end
    
    local container = Instance.new("Frame", SpeedHUD)
    container.AnchorPoint = Vector2.new(0.5, 1)
    container.Position = UDim2.new(0.5, 0, 1, -20)
    container.Size = UDim2.new(0, 80, 0, 28)
    container.BackgroundColor3 = COLORS.Background
    container.BackgroundTransparency = 0.3
    container.BorderSizePixel = 0
    Instance.new("UICorner", container).CornerRadius = UDim.new(0, 8)
    
    SpeedLabel = Instance.new("TextLabel", container)
    SpeedLabel.Size = UDim2.new(1, 0, 1, 0)
    SpeedLabel.BackgroundTransparency = 1
    SpeedLabel.Text = "0 sp/s"
    SpeedLabel.TextColor3 = COLORS.AccentAlt
    SpeedLabel.TextSize = 12
    SpeedLabel.Font = Enum.Font.GothamBold
end

local LastSpeedUpdate = 0
local function UpdateSpeedHUD()
    if not SpeedLabel or not RootPart then return end
    local now = tick()
    if now - LastSpeedUpdate < 0.1 then return end
    LastSpeedUpdate = now
    
    local speed = math.floor(GetHorizontalSpeed())
    SpeedLabel.Text = speed .. " sp/s"
    
    if speed > 50 then
        SpeedLabel.TextColor3 = COLORS.Success
    elseif speed > 25 then
        SpeedLabel.TextColor3 = COLORS.AccentAlt
    else
        SpeedLabel.TextColor3 = COLORS.TextMuted
    end
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    local key = input.KeyCode
    if key == Enum.KeyCode.Space then 
        holdSpace = true 
        LastGroundState = false
        -- Start bhop chain tracking
        if not IsInBhopChain then
            StoredHorizontalSpeed = GetHorizontalSpeed()
            PreHopVelocity = RootPart and RootPart.AssemblyLinearVelocity or Vector3.zero
        end
    elseif key == Enum.KeyCode.X then holdX = true
    elseif key == Enum.KeyCode.E then Revive()
    elseif key == Enum.KeyCode.R then SelfResurrect()
    elseif key == Enum.KeyCode.Q then holdQ = true
    elseif key == Enum.KeyCode.P then ToggleFullbright()
    elseif key == Enum.KeyCode.RightShift then
        if GUI and GUI:FindFirstChild("Main") then
            GUI.Main.Visible = not GUI.Main.Visible
            if VIPPanel then VIPPanel.Visible = false end
        end
    end
end)

UserInputService.InputEnded:Connect(function(input)
    local key = input.KeyCode
    if key == Enum.KeyCode.Space then 
        holdSpace = false 
        LastGroundState = false
        -- Don't immediately reset bhop chain - allow brief window
        task.delay(0.3, function()
            if not holdSpace then
                IsInBhopChain = false
                HopCount = 0
            end
        end)
    elseif key == Enum.KeyCode.Q then holdQ = false
    elseif key == Enum.KeyCode.X then holdX = false AirEnd = 0
    end
end)

local function SetupCharacter(character)
    if StateChangedConn then StateChangedConn:Disconnect() StateChangedConn = nil end
    Humanoid = character:WaitForChild("Humanoid", 5)
    RootPart = character:WaitForChild("HumanoidRootPart", 5)
    ForceUpdateRayFilter()
    SetupEdgeBoost()
    CurrentTarget, FarmStart = nil, 0
    LastBounce, AirEnd = 0, 0
    LastJumpTick = 0
    LastGroundState = false
    IsInBhopChain = false
    HopCount = 0
    StoredHorizontalSpeed = 0
    VelocityRestoreCounter = 0
    PendingJump = false
    WasAirborne = false
    table.clear(CachedBots)
    table.clear(CachedItems)
    
    if Humanoid then
        -- Optimized state change handler for bhop
        StateChangedConn = Humanoid.StateChanged:Connect(function(old, new)
            if holdSpace then
                if new == Enum.HumanoidStateType.Landed then
                    -- Instant re-jump on landing
                    LastLandingTime = tick()
                    
                    -- Store velocity before ground friction can eat it
                    if RootPart then
                        local currentSpeed = GetHorizontalSpeed()
                        if currentSpeed > StoredHorizontalSpeed * 0.7 then
                            StoredHorizontalSpeed = currentSpeed
                        end
                        PreHopVelocity = RootPart.AssemblyLinearVelocity
                    end
                    
                    task.defer(function()
                        if holdSpace and Humanoid and Humanoid.Health > 0 then
                            ExecuteJump()
                        end
                    end)
                elseif new == Enum.HumanoidStateType.Running then
                    -- Also catch Running state for extra consistency
                    if WasAirborne then
                        task.defer(function()
                            if holdSpace and Humanoid and Humanoid.Health > 0 then
                                ExecuteJump()
                            end
                        end)
                    end
                elseif new == Enum.HumanoidStateType.Freefall then
                    WasAirborne = true
                end
            end
        end)
    end
end

Players.PlayerAdded:Connect(function(player)
    player.CharacterAdded:Connect(function() task.delay(0.1, ForceUpdateRayFilter) end)
    player.CharacterRemoving:Connect(function() task.delay(0.1, ForceUpdateRayFilter) end)
end)

Players.PlayerRemoving:Connect(function(player)
    if player == LocalPlayer then CleanupAll() else task.delay(0.1, ForceUpdateRayFilter) end
end)

for _, player in ipairs(Players:GetPlayers()) do
    if player ~= LocalPlayer then
        player.CharacterAdded:Connect(function() task.delay(0.1, ForceUpdateRayFilter) end)
        player.CharacterRemoving:Connect(function() task.delay(0.1, ForceUpdateRayFilter) end)
    end
end

local function StartMainLoop()
    if Connections.MainLoop then Connections.MainLoop:Disconnect() end
    local lastUpdate = 0
    local lastEdgeUpdate = 0
    
    Connections.MainLoop = RunService.RenderStepped:Connect(function()
        local now = tick()
        
        -- Bhop system (every frame for maximum consistency)
        SuperBhop()
        PreJumpQueue()
        ContinuousSpeedPreservation()
        
        -- Other movement
        Bounce()
        AirStrafe()
        DoCarry()
        
        -- Speed HUD
        UpdateSpeedHUD()
        
        -- Edge boost (60fps)
        if State.EdgeBoost and now - lastEdgeUpdate >= 0.016 then
            lastEdgeUpdate = now
            ReactiveEdgeBoost()
        end
        
        -- Slower updates (10fps)
        if now - lastUpdate >= 0.1 then
            lastUpdate = now
            UpdateRayFilter()
            AntiNextbot()
            AutoFarm()
        end
    end)
end

if LocalPlayer.Character then SetupCharacter(LocalPlayer.Character) end
LocalPlayer.CharacterAdded:Connect(SetupCharacter)

Workspace.ChildAdded:Connect(function(child)
    if child.Name == "Game" then
        CachedGame = child
        task.wait(0.5)
        ForceUpdateRayFilter()
        CreateTimerGUI()
        UpdateTimer()
        NPCLoaded = false
        CurrentTarget, FarmStart = nil, 0
        LastBounce, AirEnd = 0, 0
        LastJumpTick = 0
        LastGroundState = false
        ColaDrank = false
        IsInBhopChain = false
        HopCount = 0
        StoredHorizontalSpeed = 0
        table.clear(CachedBots)
        table.clear(CachedItems)
        if State.UpsideDownFix then State.UpsideDownFix = false ToggleUpsideDownFix(false) end
    end
end)

LocalPlayer.Idled:Connect(function()
    VirtualUser:Button2Down(Vector2.new(0, 0), Workspace.CurrentCamera.CFrame)
    task.wait(1)
    VirtualUser:Button2Up(Vector2.new(0, 0), Workspace.CurrentCamera.CFrame)
end)

CreateMainGUI()
CreateTimerGUI()
CreateSpeedHUD()
UpdateTimer()
SetFOV()
SetupCameraFOV()
LoadNPCs()
ForceUpdateRayFilter()
StartMainLoop()
