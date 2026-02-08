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
            print("[Evade Helper] Teleporting...")
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

-- ═══════════════════════════════════════════════════════════════
-- STATE & CONFIG
-- ═══════════════════════════════════════════════════════════════

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

-- ═══════════════════════════════════════════════════════════════
-- BHOP CONFIG (OPTIMIZED)
-- ═══════════════════════════════════════════════════════════════

local BhopConfig = {
    PreJumpDistance = 4.5,
    PreJumpVelThreshold = -2,
    GroundRayLength = 3.2,
    SlopeMaxAngle = 45,
    SpeedPreserveEnabled = true,
    MinPreserveSpeed = 5,
    LandingBoostFactor = 1.02,
    JumpQueueWindow = 0.08,
    ConsecutiveJumpBonus = 0.005,
    MaxConsecutiveBonus = 0.05,
    GroundCheckMultiRay = true,
    MultiRaySpread = 1.2,
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

-- BHOP state variables (optimized)
local LastGroundState = false
local LastJumpTick = 0
local BHOP_COOLDOWN = 0
local PreLandingQueued = false
local LastHorizontalSpeed = 0
local SavedHorizontalVelocity = Vector3.zero
local ConsecutiveJumps = 0
local LastLandingTick = 0
local WasInAir = false
local JumpQueued = false
local LastGroundCheckResult = false
local LastGroundCheckTick = 0
local GroundCheckCacheTime = 0.005

local BhopRayParams = RaycastParams.new()
BhopRayParams.FilterType = Enum.RaycastFilterType.Exclude
BhopRayParams.RespectCanCollide = true

local EdgeRayParams = RaycastParams.new()
EdgeRayParams.FilterType = Enum.RaycastFilterType.Exclude
EdgeRayParams.IgnoreWater = true
EdgeRayParams.RespectCanCollide = true

-- ═══════════════════════════════════════════════════════════════
-- THEME / COLORS
-- ═══════════════════════════════════════════════════════════════

local Theme = {
    Background = Color3.fromRGB(15, 15, 20),
    Surface = Color3.fromRGB(22, 22, 30),
    SurfaceLight = Color3.fromRGB(30, 30, 40),
    Card = Color3.fromRGB(25, 25, 35),
    Accent = Color3.fromRGB(88, 101, 242),
    AccentHover = Color3.fromRGB(108, 121, 255),
    AccentGlow = Color3.fromRGB(88, 101, 242),
    Success = Color3.fromRGB(87, 242, 135),
    Warning = Color3.fromRGB(254, 231, 92),
    Danger = Color3.fromRGB(237, 66, 69),
    TextPrimary = Color3.fromRGB(235, 235, 245),
    TextSecondary = Color3.fromRGB(148, 155, 175),
    TextMuted = Color3.fromRGB(88, 95, 115),
    Border = Color3.fromRGB(40, 40, 55),
    BorderAccent = Color3.fromRGB(88, 101, 242),
    ButtonOff = Color3.fromRGB(35, 35, 48),
    ButtonOn = Color3.fromRGB(88, 101, 242),
    ButtonHover = Color3.fromRGB(42, 42, 58),
    SliderBg = Color3.fromRGB(35, 35, 48),
    SliderFill = Color3.fromRGB(88, 101, 242),
    Shadow = Color3.fromRGB(0, 0, 0),
}

local FONT_TITLE = Enum.Font.GothamBlack
local FONT_HEADING = Enum.Font.GothamBold
local FONT_BODY = Enum.Font.GothamMedium
local FONT_SMALL = Enum.Font.Gotham

-- ═══════════════════════════════════════════════════════════════
-- UTILITY FUNCTIONS
-- ═══════════════════════════════════════════════════════════════

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

-- ═══════════════════════════════════════════════════════════════
-- OPTIMIZED BHOP SYSTEM
-- ═══════════════════════════════════════════════════════════════

local function ValidateRayHit(rayResult)
    if not rayResult or not rayResult.Instance then return false end
    
    local hitPart = rayResult.Instance
    local hitModel = hitPart:FindFirstAncestorOfClass("Model")
    
    if hitModel then
        local hitPlayer = Players:GetPlayerFromCharacter(hitModel)
        if hitPlayer or hitModel:FindFirstChildOfClass("Humanoid") then
            return false
        end
    end
    
    local angle = math.deg(math.acos(math.clamp(rayResult.Normal:Dot(Vector3.yAxis), -1, 1)))
    return angle <= BhopConfig.SlopeMaxAngle
end

local function IsOnGroundInstant()
    if not Humanoid or not RootPart then return false end
    
    local now = tick()
    if now - LastGroundCheckTick < GroundCheckCacheTime then
        return LastGroundCheckResult
    end
    LastGroundCheckTick = now
    
    -- Fast check: FloorMaterial
    if Humanoid.FloorMaterial ~= Enum.Material.Air then
        LastGroundCheckResult = true
        return true
    end
    
    -- Fast check: Humanoid state
    local state = Humanoid:GetState()
    if state == Enum.HumanoidStateType.Running or
       state == Enum.HumanoidStateType.RunningNoPhysics or
       state == Enum.HumanoidStateType.Landed then
        LastGroundCheckResult = true
        return true
    end
    
    -- Primary center ray
    local pos = RootPart.Position
    local rayResult = Workspace:Raycast(pos, Vector3.new(0, -BhopConfig.GroundRayLength, 0), BhopRayParams)
    if rayResult and ValidateRayHit(rayResult) then
        LastGroundCheckResult = true
        return true
    end
    
    -- Multi-ray ground detection for consistency on edges/slopes
    if BhopConfig.GroundCheckMultiRay then
        local spread = BhopConfig.MultiRaySpread
        local offsets = {
            Vector3.new(spread, 0, 0),
            Vector3.new(-spread, 0, 0),
            Vector3.new(0, 0, spread),
            Vector3.new(0, 0, -spread),
            Vector3.new(spread * 0.7, 0, spread * 0.7),
            Vector3.new(-spread * 0.7, 0, spread * 0.7),
            Vector3.new(spread * 0.7, 0, -spread * 0.7),
            Vector3.new(-spread * 0.7, 0, -spread * 0.7),
        }
        
        for _, offset in ipairs(offsets) do
            local sideRay = Workspace:Raycast(pos + offset, Vector3.new(0, -BhopConfig.GroundRayLength, 0), BhopRayParams)
            if sideRay and ValidateRayHit(sideRay) then
                LastGroundCheckResult = true
                return true
            end
        end
    end
    
    LastGroundCheckResult = false
    return false
end

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
    if not BhopConfig.SpeedPreserveEnabled then return end
    if not RootPart then return end
    
    local currentHSpeed = GetHorizontalSpeed()
    local currentVel = RootPart.AssemblyLinearVelocity
    local horizontalVel = Vector3.new(currentVel.X, 0, currentVel.Z)
    
    -- Only preserve if we had meaningful speed and are losing it
    if LastHorizontalSpeed > BhopConfig.MinPreserveSpeed and currentHSpeed < LastHorizontalSpeed * 0.85 then
        local preserveSpeed = LastHorizontalSpeed * BhopConfig.LandingBoostFactor
        
        -- Apply consecutive jump bonus
        local bonus = math.min(ConsecutiveJumps * BhopConfig.ConsecutiveJumpBonus, BhopConfig.MaxConsecutiveBonus)
        preserveSpeed = preserveSpeed * (1 + bonus)
        
        if horizontalVel.Magnitude > 0.1 then
            local dir = horizontalVel.Unit
            RootPart.AssemblyLinearVelocity = Vector3.new(
                dir.X * preserveSpeed,
                currentVel.Y,
                dir.Z * preserveSpeed
            )
        elseif SavedHorizontalVelocity.Magnitude > 0.1 then
            local dir = SavedHorizontalVelocity.Unit
            RootPart.AssemblyLinearVelocity = Vector3.new(
                dir.X * preserveSpeed,
                currentVel.Y,
                dir.Z * preserveSpeed
            )
        end
    end
end

local function ExecuteJump()
    if not Humanoid or Humanoid.Health <= 0 then return end
    
    -- Save speed before jump
    LastHorizontalSpeed = GetHorizontalSpeed()
    SavedHorizontalVelocity = GetHorizontalVelocity()
    
    -- Execute jump
    Humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
    
    -- Preserve speed immediately after state change
    task.defer(function()
        if Humanoid and RootPart and Humanoid.Health > 0 then
            PreserveSpeed()
        end
    end)
    
    -- Double-check preservation after a tiny delay
    task.delay(0.01, function()
        if Humanoid and RootPart and Humanoid.Health > 0 and holdSpace then
            PreserveSpeed()
        end
    end)
    
    ConsecutiveJumps = ConsecutiveJumps + 1
    LastJumpTick = tick()
    JumpQueued = false
    PreLandingQueued = false
end

local function SuperBhop()
    if not holdSpace or not Humanoid or not RootPart then return end
    if Humanoid.Health <= 0 then return end
    
    local character = LocalPlayer.Character
    if not character then return end
    
    local isDowned = SafeCall(function() return character:GetAttribute("Downed") end)
    if isDowned then return end
    
    local onGround = IsOnGroundInstant()
    local now = tick()
    local currentSpeed = GetHorizontalSpeed()
    
    -- Track speed continuously while in air
    if not onGround then
        if currentSpeed > BhopConfig.MinPreserveSpeed then
            LastHorizontalSpeed = math.max(LastHorizontalSpeed, currentSpeed)
            SavedHorizontalVelocity = GetHorizontalVelocity()
        end
        WasInAir = true
    end
    
    -- Landing detection - execute queued jump immediately
    if onGround and WasInAir then
        WasInAir = false
        LastLandingTick = now
        
        if holdSpace then
            ExecuteJump()
            return
        end
    end
    
    -- Ground jump with speed preservation
    if onGround then
        if not LastGroundState or (now - LastJumpTick) >= BHOP_COOLDOWN then
            -- Save current speed before any jump
            if currentSpeed > BhopConfig.MinPreserveSpeed then
                LastHorizontalSpeed = currentSpeed
                SavedHorizontalVelocity = GetHorizontalVelocity()
            end
            
            ExecuteJump()
            
            -- Backup jump attempt
            task.defer(function()
                if Humanoid and Humanoid.Health > 0 and holdSpace then
                    if IsOnGroundInstant() then
                        ExecuteJump()
                    end
                end
            end)
        end
    else
        -- Reset consecutive jumps if we've been in air too long without jumping
        if now - LastJumpTick > 1.5 then
            ConsecutiveJumps = 0
        end
    end
    
    LastGroundState = onGround
end

local function PreJumpQueue()
    if not holdSpace or not Humanoid or not RootPart then return end
    if Humanoid.Health <= 0 then return end
    
    local state = Humanoid:GetState()
    if state == Enum.HumanoidStateType.Freefall then
        local pos = RootPart.Position
        local vel = RootPart.AssemblyLinearVelocity
        
        -- Predictive ground detection - cast ray further based on velocity
        local predictiveLength = BhopConfig.PreJumpDistance
        if vel.Y < -20 then
            predictiveLength = predictiveLength * 1.5
        end
        
        -- Center ray
        local rayResult = Workspace:Raycast(pos, Vector3.new(0, -predictiveLength, 0), BhopRayParams)
        
        -- If center misses, try offset rays for edge catching
        if not rayResult then
            local spread = BhopConfig.MultiRaySpread * 0.8
            local horizontalVel = Vector3.new(vel.X, 0, vel.Z)
            if horizontalVel.Magnitude > 1 then
                local moveDir = horizontalVel.Unit
                rayResult = Workspace:Raycast(pos + moveDir * spread, Vector3.new(0, -predictiveLength, 0), BhopRayParams)
            end
        end
        
        if rayResult and ValidateRayHit(rayResult) then
            local dist = (pos - rayResult.Position).Magnitude
            
            -- Dynamic pre-jump threshold based on fall speed
            local threshold = 3.5
            if vel.Y < BhopConfig.PreJumpVelThreshold then
                threshold = math.clamp(3.5 + math.abs(vel.Y) * 0.04, 3.5, 6.0)
            end
            
            if dist < threshold then
                -- Save speed before pre-landing jump
                local currentSpeed = GetHorizontalSpeed()
                if currentSpeed > BhopConfig.MinPreserveSpeed then
                    LastHorizontalSpeed = math.max(LastHorizontalSpeed, currentSpeed)
                    SavedHorizontalVelocity = GetHorizontalVelocity()
                end
                
                PreLandingQueued = true
                
                task.defer(function()
                    if holdSpace and Humanoid and Humanoid.Health > 0 then
                        ExecuteJump()
                    end
                end)
            end
        end
    end
end

-- Speed preservation on humanoid state changes
local function OnHumanoidStateChanged(old, new)
    if not holdSpace then
        if new == Enum.HumanoidStateType.Landed or new == Enum.HumanoidStateType.Running then
            ConsecutiveJumps = 0
        end
        return
    end
    
    if new == Enum.HumanoidStateType.Landed then
        -- Instant jump on landing
        task.defer(function()
            if holdSpace and Humanoid and Humanoid.Health > 0 then
                ExecuteJump()
            end
        end)
    elseif new == Enum.HumanoidStateType.Running then
        -- Backup: if we somehow enter running state while holding space
        task.defer(function()
            if holdSpace and Humanoid and Humanoid.Health > 0 then
                local speed = GetHorizontalSpeed()
                if speed > BhopConfig.MinPreserveSpeed then
                    LastHorizontalSpeed = speed
                    SavedHorizontalVelocity = GetHorizontalVelocity()
                end
                ExecuteJump()
            end
        end)
    elseif new == Enum.HumanoidStateType.Jumping then
        -- Preserve speed right when jump initiates
        task.defer(function()
            if RootPart and Humanoid and Humanoid.Health > 0 then
                PreserveSpeed()
            end
        end)
    end
end

-- ═══════════════════════════════════════════════════════════════
-- GAME LOGIC (unchanged functionality)
-- ═══════════════════════════════════════════════════════════════

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
        warn("[Evade Helper] Cola events not found")
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

-- ═══════════════════════════════════════════════════════════════
-- MODERN GUI SYSTEM
-- ═══════════════════════════════════════════════════════════════

local function Tween(obj, props, duration, style, direction)
    local tweenInfo = TweenInfo.new(
        duration or 0.2,
        style or Enum.EasingStyle.Quint,
        direction or Enum.EasingDirection.Out
    )
    local tween = TweenService:Create(obj, tweenInfo, props)
    tween:Play()
    return tween
end

local function AddShadow(parent, offset, transparency)
    local shadow = Instance.new("ImageLabel")
    shadow.Name = "Shadow"
    shadow.AnchorPoint = Vector2.new(0.5, 0.5)
    shadow.BackgroundTransparency = 1
    shadow.Position = UDim2.new(0.5, 0, 0.5, offset or 4)
    shadow.Size = UDim2.new(1, 30, 1, 30)
    shadow.Image = "rbxassetid://6014261993"
    shadow.ImageColor3 = Color3.fromRGB(0, 0, 0)
    shadow.ImageTransparency = transparency or 0.5
    shadow.ScaleType = Enum.ScaleType.Slice
    shadow.SliceCenter = Rect.new(49, 49, 450, 450)
    shadow.ZIndex = -1
    shadow.Parent = parent
    return shadow
end

local function CreateModernButton(parent, name, text, icon, pos, size, callback)
    local btn = Instance.new("TextButton")
    btn.Name = name
    btn.Size = size or UDim2.new(1, -16, 0, 36)
    btn.Position = pos or UDim2.new(0, 8, 0, 0)
    btn.BackgroundColor3 = Theme.ButtonOff
    btn.Text = ""
    btn.AutoButtonColor = false
    btn.BorderSizePixel = 0
    btn.Parent = parent
    
    local corner = Instance.new("UICorner", btn)
    corner.CornerRadius = UDim.new(0, 8)
    
    local stroke = Instance.new("UIStroke", btn)
    stroke.Color = Theme.Border
    stroke.Thickness = 1
    stroke.Transparency = 0.5
    
    -- Icon/indicator dot
    local indicator = Instance.new("Frame")
    indicator.Name = "Indicator"
    indicator.Size = UDim2.new(0, 6, 0, 6)
    indicator.Position = UDim2.new(0, 12, 0.5, -3)
    indicator.BackgroundColor3 = Theme.TextMuted
    indicator.Parent = btn
    Instance.new("UICorner", indicator).CornerRadius = UDim.new(1, 0)
    
    local label = Instance.new("TextLabel")
    label.Name = "Label"
    label.Size = UDim2.new(1, -40, 1, 0)
    label.Position = UDim2.new(0, 26, 0, 0)
    label.BackgroundTransparency = 1
    label.Text = text
    label.TextColor3 = Theme.TextSecondary
    label.TextSize = 12
    label.Font = FONT_BODY
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = btn
    
    local statusText = Instance.new("TextLabel")
    statusText.Name = "Status"
    statusText.Size = UDim2.new(0, 30, 1, 0)
    statusText.Position = UDim2.new(1, -38, 0, 0)
    statusText.BackgroundTransparency = 1
    statusText.Text = "OFF"
    statusText.TextColor3 = Theme.TextMuted
    statusText.TextSize = 10
    statusText.Font = FONT_SMALL
    statusText.Parent = btn
    
    -- Hover effects
    btn.MouseEnter:Connect(function()
        if not btn:GetAttribute("Active") then
            Tween(btn, {BackgroundColor3 = Theme.ButtonHover}, 0.15)
        end
        Tween(stroke, {Color = Theme.AccentGlow, Transparency = 0.3}, 0.15)
    end)
    
    btn.MouseLeave:Connect(function()
        if not btn:GetAttribute("Active") then
            Tween(btn, {BackgroundColor3 = Theme.ButtonOff}, 0.15)
        end
        Tween(stroke, {Color = btn:GetAttribute("Active") and Theme.AccentGlow or Theme.Border, Transparency = 0.5}, 0.15)
    end)
    
    btn.MouseButton1Click:Connect(function()
        if callback then callback() end
    end)
    
    return btn
end

local function CreateSmallButton(parent, name, text, pos, size, callback)
    local btn = Instance.new("TextButton")
    btn.Name = name
    btn.Size = size or UDim2.new(0, 50, 0, 28)
    btn.Position = pos or UDim2.new(0, 0, 0, 0)
    btn.BackgroundColor3 = Theme.ButtonOff
    btn.Text = text
    btn.TextColor3 = Theme.TextSecondary
    btn.TextSize = 11
    btn.Font = FONT_BODY
    btn.AutoButtonColor = false
    btn.BorderSizePixel = 0
    btn.Parent = parent
    
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
    
    btn.MouseEnter:Connect(function()
        if not btn:GetAttribute("Active") then
            Tween(btn, {BackgroundColor3 = Theme.ButtonHover}, 0.12)
        end
    end)
    
    btn.MouseLeave:Connect(function()
        if not btn:GetAttribute("Active") then
            Tween(btn, {BackgroundColor3 = Theme.ButtonOff}, 0.12)
        end
    end)
    
    btn.MouseButton1Click:Connect(function()
        if callback then callback() end
    end)
    
    return btn
end

local function CreateSectionLabel(parent, text, pos)
    local container = Instance.new("Frame")
    container.Size = UDim2.new(1, -16, 0, 20)
    container.Position = pos
    container.BackgroundTransparency = 1
    container.Parent = parent
    
    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, 0, 1, 0)
    label.BackgroundTransparency = 1
    label.Text = "  " .. text:upper():gsub(".", "%1 "):sub(1, -2) .. "  "
    label.TextColor3 = Theme.TextMuted
    label.TextSize = 9
    label.Font = FONT_HEADING
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = container
    
    local line = Instance.new("Frame")
    line.Size = UDim2.new(1, -#text * 10 - 8, 0, 1)
    line.Position = UDim2.new(0, #text * 10 + 8, 0.5, 0)
    line.BackgroundColor3 = Theme.Border
    line.BackgroundTransparency = 0.5
    line.BorderSizePixel = 0
    line.Parent = container
    
    return container
end

local function CreateModernInput(parent, name, placeholder, pos, size, callback)
    local container = Instance.new("Frame")
    container.Name = name .. "Container"
    container.Size = size or UDim2.new(1, -16, 0, 32)
    container.Position = pos
    container.BackgroundColor3 = Theme.SurfaceLight
    container.BorderSizePixel = 0
    container.Parent = parent
    Instance.new("UICorner", container).CornerRadius = UDim.new(0, 6)
    
    local stroke = Instance.new("UIStroke", container)
    stroke.Color = Theme.Border
    stroke.Thickness = 1
    stroke.Transparency = 0.5
    
    local input = Instance.new("TextBox")
    input.Name = name
    input.Size = UDim2.new(1, -16, 1, 0)
    input.Position = UDim2.new(0, 8, 0, 0)
    input.BackgroundTransparency = 1
    input.Text = ""
    input.PlaceholderText = placeholder
    input.TextColor3 = Theme.TextPrimary
    input.PlaceholderColor3 = Theme.TextMuted
    input.TextSize = 11
    input.Font = FONT_SMALL
    input.ClearTextOnFocus = false
    input.Parent = container
    
    input.Focused:Connect(function()
        Tween(stroke, {Color = Theme.Accent, Transparency = 0}, 0.15)
    end)
    
    input.FocusLost:Connect(function()
        Tween(stroke, {Color = Theme.Border, Transparency = 0.5}, 0.15)
        if callback then callback(input.Text) end
    end)
    
    return input
end

local function SetModernButtonActive(button, active)
    button:SetAttribute("Active", active)
    
    local indicator = button:FindFirstChild("Indicator")
    local label = button:FindFirstChild("Label")
    local status = button:FindFirstChild("Status")
    
    if active then
        Tween(button, {BackgroundColor3 = Color3.fromRGB(88, 101, 242)}, 0.2) -- Theme.ButtonOn
        if indicator then Tween(indicator, {BackgroundColor3 = Theme.Success}, 0.2) end
        if label then Tween(label, {TextColor3 = Theme.TextPrimary}, 0.2) end
        if status then status.Text = "ON" Tween(status, {TextColor3 = Theme.Success}, 0.2) end
    else
        Tween(button, {BackgroundColor3 = Theme.ButtonOff}, 0.2)
        if indicator then Tween(indicator, {BackgroundColor3 = Theme.TextMuted}, 0.2) end
        if label then Tween(label, {TextColor3 = Theme.TextSecondary}, 0.2) end
        if status then status.Text = "OFF" Tween(status, {TextColor3 = Theme.TextMuted}, 0.2) end
    end
end

local function SetSmallButtonActive(button, active)
    button:SetAttribute("Active", active)
    
    if active then
        Tween(button, {BackgroundColor3 = Theme.ButtonOn, TextColor3 = Theme.TextPrimary}, 0.15)
    else
        Tween(button, {BackgroundColor3 = Theme.ButtonOff, TextColor3 = Theme.TextSecondary}, 0.15)
    end
end

local function MakeDraggable(frame)
    local dragging, dragStart, startPos = false, nil, nil
    local dragArea = Instance.new("Frame")
    dragArea.Name = "DragArea"
    dragArea.Size = UDim2.new(1, 0, 0, 40)
    dragArea.Position = UDim2.new(0, 0, 0, 0)
    dragArea.BackgroundTransparency = 1
    dragArea.ZIndex = 10
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

local function UpdateGUI()
    if not GUI then return end
    local main = GUI:FindFirstChild("Main")
    if not main then return end
    
    local content = main:FindFirstChild("Content")
    if not content then return end
    
    local function UpdateModern(name, active)
        local button = content:FindFirstChild(name)
        if button and button:IsA("TextButton") then
            SetModernButtonActive(button, active)
        end
    end
    
    local function UpdateSmall(name, active)
        local button = content:FindFirstChild(name)
        if button and button:IsA("TextButton") then
            SetSmallButtonActive(button, active)
        end
    end
    
    UpdateSmall("FOV90", Config.FOV == 90)
    UpdateSmall("FOV120", Config.FOV == 120)
    UpdateModern("Bright", FullbrightEnabled)
    UpdateModern("Border", State.Border)
    UpdateModern("Anti", State.AntiNextbot)
    UpdateModern("Farm", State.AutoFarm)
    UpdateModern("InfCola", State.InfiniteCola)
    UpdateModern("UpFix", State.UpsideDownFix)
    UpdateModern("EdgeBoost", State.EdgeBoost)
    UpdateSmall("ColaLow", ColaConfig.Speed == 1.4)
    UpdateSmall("ColaMed", ColaConfig.Speed == 1.6)
    UpdateSmall("ColaHigh", ColaConfig.Speed == 1.8)
end

local function UpdateSliderUI(value)
    if not SliderTrack then return end
    local pos = math.clamp((value - SliderMin) / (SliderMax - SliderMin), 0, 1)
    Tween(SliderFill, {Size = UDim2.new(pos, 0, 1, 0)}, 0.1)
    Tween(SliderThumb, {Position = UDim2.new(pos, -7, 0.5, -7)}, 0.1)
    SliderLabel.Text = string.format("Cola Speed: %.1fx", value)
end

local function CreateVIPPanel()
    if VIPPanel then VIPPanel.Visible = not VIPPanel.Visible return end
    
    VIPPanel = Instance.new("Frame")
    VIPPanel.Name = "VIP"
    VIPPanel.Size = UDim2.new(0, 280, 0, 200)
    VIPPanel.Position = UDim2.new(0, 310, 0, 50)
    VIPPanel.BackgroundColor3 = Theme.Background
    VIPPanel.BorderSizePixel = 0
    VIPPanel.Parent = GUI
    Instance.new("UICorner", VIPPanel).CornerRadius = UDim.new(0, 12)
    local vipStroke = Instance.new("UIStroke", VIPPanel)
    vipStroke.Color = Theme.Border
    vipStroke.Thickness = 1
    AddShadow(VIPPanel)
    
    -- Title bar
    local titleBar = Instance.new("Frame")
    titleBar.Size = UDim2.new(1, 0, 0, 36)
    titleBar.BackgroundColor3 = Theme.Surface
    titleBar.BorderSizePixel = 0
    titleBar.Parent = VIPPanel
    Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 12)
    
    -- Fix bottom corners of title bar
    local titleFix = Instance.new("Frame")
    titleFix.Size = UDim2.new(1, 0, 0, 12)
    titleFix.Position = UDim2.new(0, 0, 1, -12)
    titleFix.BackgroundColor3 = Theme.Surface
    titleFix.BorderSizePixel = 0
    titleFix.Parent = titleBar
    
    local vipTitle = Instance.new("TextLabel")
    vipTitle.Size = UDim2.new(1, -40, 1, 0)
    vipTitle.Position = UDim2.new(0, 14, 0, 0)
    vipTitle.BackgroundTransparency = 1
    vipTitle.Text = "⚡ VIP SERVER"
    vipTitle.TextColor3 = Theme.Accent
    vipTitle.TextSize = 12
    vipTitle.Font = FONT_HEADING
    vipTitle.TextXAlignment = Enum.TextXAlignment.Left
    vipTitle.Parent = titleBar
    
    local closeBtn = CreateSmallButton(titleBar, "X", "✕", UDim2.new(1, -32, 0, 4), UDim2.new(0, 28, 0, 28), function()
        VIPPanel.Visible = false
    end)
    closeBtn.TextSize = 14
    
    local y = 44
    
    -- Map Vote
    local mapLabel = Instance.new("TextLabel")
    mapLabel.Size = UDim2.new(0, 70, 0, 20)
    mapLabel.Position = UDim2.new(0, 12, 0, y)
    mapLabel.BackgroundTransparency = 1
    mapLabel.Text = "Map Vote"
    mapLabel.TextColor3 = Theme.TextSecondary
    mapLabel.TextSize = 11
    mapLabel.Font = FONT_BODY
    mapLabel.TextXAlignment = Enum.TextXAlignment.Left
    mapLabel.Parent = VIPPanel
    
    local autoVoteBtn = CreateSmallButton(VIPPanel, "AV", "AUTO", UDim2.new(0, 85, 0, y - 2), UDim2.new(0, 42, 0, 24), function() end)
    autoVoteBtn.TextSize = 9
    autoVoteBtn.MouseButton1Click:Connect(function()
        if State.VoteMap then StopMapVoting() else StartMapVoting() end
        SetSmallButtonActive(autoVoteBtn, State.VoteMap)
    end)
    
    for i = 1, 4 do
        local btn = CreateSmallButton(VIPPanel, "Mp" .. i, tostring(i), UDim2.new(0, 130 + (i - 1) * 32, 0, y - 2), UDim2.new(0, 28, 0, 24), function()
            State.MapIndex = i
            for j = 1, 4 do local b = VIPPanel:FindFirstChild("Mp" .. j) if b then SetSmallButtonActive(b, j == i) end end
        end)
        btn.TextSize = 10
        if i == 1 then SetSmallButtonActive(btn, true) end
    end
    
    y = y + 32
    
    -- Mode Vote
    local modeLabel = Instance.new("TextLabel")
    modeLabel.Size = UDim2.new(0, 70, 0, 20)
    modeLabel.Position = UDim2.new(0, 12, 0, y)
    modeLabel.BackgroundTransparency = 1
    modeLabel.Text = "Mode Vote"
    modeLabel.TextColor3 = Theme.TextSecondary
    modeLabel.TextSize = 11
    modeLabel.Font = FONT_BODY
    modeLabel.TextXAlignment = Enum.TextXAlignment.Left
    modeLabel.Parent = VIPPanel
    
    local autoModeBtn = CreateSmallButton(VIPPanel, "AM", "AUTO", UDim2.new(0, 85, 0, y - 2), UDim2.new(0, 42, 0, 24), function() end)
    autoModeBtn.TextSize = 9
    autoModeBtn.MouseButton1Click:Connect(function()
        if State.VoteMode then StopModeVoting() else StartModeVoting() end
        SetSmallButtonActive(autoModeBtn, State.VoteMode)
    end)
    
    for i = 1, 4 do
        local btn = CreateSmallButton(VIPPanel, "Md" .. i, tostring(i), UDim2.new(0, 130 + (i - 1) * 32, 0, y - 2), UDim2.new(0, 28, 0, 24), function()
            State.ModeIndex = i
            for j = 1, 4 do local b = VIPPanel:FindFirstChild("Md" .. j) if b then SetSmallButtonActive(b, j == i) end end
        end)
        btn.TextSize = 10
        if i == 1 then SetSmallButtonActive(btn, true) end
    end
    
    y = y + 36
    
    -- Map search
    local mapInput = CreateModernInput(VIPPanel, "MapIn", "Search map...", UDim2.new(0, 12, 0, y), UDim2.new(0, 160, 0, 28), function(text) State.MapSearch = text end)
    local addMapBtn = CreateSmallButton(VIPPanel, "AddM", "+", UDim2.new(0, 178, 0, y), UDim2.new(0, 28, 0, 28), function()
        local map = FindInList(State.MapSearch, Maps) if map then FireAdmin("AddMap", map) end
    end)
    addMapBtn.TextSize = 14
    local remMapBtn = CreateSmallButton(VIPPanel, "RemM", "−", UDim2.new(0, 210, 0, y), UDim2.new(0, 28, 0, 28), function()
        local map = FindInList(State.MapSearch, Maps) if map then FireAdmin("RemoveMap", map) end
    end)
    remMapBtn.TextSize = 14
    
    y = y + 36
    
    -- Mode search
    local modeInput = CreateModernInput(VIPPanel, "ModeIn", "Search mode...", UDim2.new(0, 12, 0, y), UDim2.new(0, 160, 0, 28), function(text) State.GamemodeSearch = text end)
    local setModeBtn = CreateSmallButton(VIPPanel, "SetM", "SET", UDim2.new(0, 178, 0, y), UDim2.new(0, 60, 0, 28), function()
        local mode = FindInList(State.GamemodeSearch, Modes) if mode then FireAdmin("Gamemode", mode) end
    end)
    setModeBtn.TextSize = 9
    
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
    
    local main = Instance.new("Frame")
    main.Name = "Main"
    main.Size = UDim2.new(0, 280, 0, 0) -- Start collapsed for animation
    main.Position = UDim2.new(0, 20, 0, 50)
    main.BackgroundColor3 = Theme.Background
    main.BorderSizePixel = 0
    main.ClipsDescendants = true
    main.Parent = GUI
    Instance.new("UICorner", main).CornerRadius = UDim.new(0, 12)
    
    local mainStroke = Instance.new("UIStroke", main)
    mainStroke.Color = Theme.Border
    mainStroke.Thickness = 1
    
    AddShadow(main)
    
    -- Title bar
    local titleBar = Instance.new("Frame")
    titleBar.Name = "TitleBar"
    titleBar.Size = UDim2.new(1, 0, 0, 44)
    titleBar.BackgroundColor3 = Theme.Surface
    titleBar.BorderSizePixel = 0
    titleBar.Parent = main
    Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 12)
    
    local titleFix = Instance.new("Frame")
    titleFix.Size = UDim2.new(1, 0, 0, 12)
    titleFix.Position = UDim2.new(0, 0, 1, -12)
    titleFix.BackgroundColor3 = Theme.Surface
    titleFix.BorderSizePixel = 0
    titleFix.Parent = titleBar
    
    -- Accent line under title
    local accentLine = Instance.new("Frame")
    accentLine.Size = UDim2.new(1, 0, 0, 2)
    accentLine.Position = UDim2.new(0, 0, 1, -2)
    accentLine.BackgroundColor3 = Theme.Accent
    accentLine.BorderSizePixel = 0
    accentLine.Parent = titleBar
    
    local gradient = Instance.new("UIGradient", accentLine)
    gradient.Color = ColorSequence.new{
        ColorSequenceKeypoint.new(0, Theme.Accent),
        ColorSequenceKeypoint.new(0.5, Color3.fromRGB(155, 89, 182)),
        ColorSequenceKeypoint.new(1, Theme.Danger),
    }
    
    local titleText = IsEvadeGame() and "EVADE HELPER" or "HELPER (Universal)"
    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -100, 1, 0)
    title.Position = UDim2.new(0, 14, 0, 0)
    title.BackgroundTransparency = 1
    title.Text = "🎮  " .. titleText
    title.TextColor3 = Theme.TextPrimary
    title.TextSize = 13
    title.Font = FONT_TITLE
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = titleBar
    
    local versionLabel = Instance.new("TextLabel")
    versionLabel.Size = UDim2.new(0, 30, 0, 16)
    versionLabel.Position = UDim2.new(0, 14 + #titleText * 7 + 30, 0, 14)
    versionLabel.BackgroundColor3 = Theme.Accent
    versionLabel.Text = "V9"
    versionLabel.TextColor3 = Theme.TextPrimary
    versionLabel.TextSize = 9
    versionLabel.Font = FONT_HEADING
    versionLabel.Parent = titleBar
    Instance.new("UICorner", versionLabel).CornerRadius = UDim.new(0, 4)
    
    -- VIP Button
    local vipBtn = CreateSmallButton(titleBar, "VIP", "⚡ VIP", UDim2.new(1, -78, 0, 8), UDim2.new(0, 44, 0, 28), CreateVIPPanel)
    vipBtn.TextSize = 10
    vipBtn.BackgroundColor3 = Color3.fromRGB(45, 40, 60)
    
    -- Close button
    local closeBtn = CreateSmallButton(titleBar, "X", "✕", UDim2.new(1, -32, 0, 8), UDim2.new(0, 28, 0, 28), function()
        Tween(main, {Size = UDim2.new(0, 280, 0, 0)}, 0.3)
        task.delay(0.3, function() main.Visible = false end)
    end)
    closeBtn.TextSize = 14
    closeBtn.BackgroundColor3 = Color3.fromRGB(60, 30, 30)
    closeBtn.TextColor3 = Theme.Danger
    
    -- Content area
    local content = Instance.new("ScrollingFrame")
    content.Name = "Content"
    content.Size = UDim2.new(1, 0, 1, -46)
    content.Position = UDim2.new(0, 0, 0, 46)
    content.BackgroundTransparency = 1
    content.ScrollBarThickness = 3
    content.ScrollBarImageColor3 = Theme.Accent
    content.BorderSizePixel = 0
    content.CanvasSize = UDim2.new(0, 0, 0, 520)
    content.Parent = main
    
    local y = 8
    
    -- ═══ VISUAL SECTION ═══
    CreateSectionLabel(content, "Visual", UDim2.new(0, 8, 0, y))
    y = y + 24
    
    -- FOV Row
    local fovContainer = Instance.new("Frame")
    fovContainer.Size = UDim2.new(1, -16, 0, 32)
    fovContainer.Position = UDim2.new(0, 8, 0, y)
    fovContainer.BackgroundTransparency = 1
    fovContainer.Parent = content
    
    local fovLabel = Instance.new("TextLabel")
    fovLabel.Size = UDim2.new(0, 35, 1, 0)
    fovLabel.BackgroundTransparency = 1
    fovLabel.Text = "FOV"
    fovLabel.TextColor3 = Theme.TextSecondary
    fovLabel.TextSize = 11
    fovLabel.Font = FONT_BODY
    fovLabel.TextXAlignment = Enum.TextXAlignment.Left
    fovLabel.Parent = fovContainer
    
    local fov90 = CreateSmallButton(content, "FOV90", "90°", UDim2.new(0, 50, 0, y + 2), UDim2.new(0, 45, 0, 28), function()
        Config.FOV = 90 SetFOV() UpdateGUI()
    end)
    
    local fov120 = CreateSmallButton(content, "FOV120", "120°", UDim2.new(0, 100, 0, y + 2), UDim2.new(0, 50, 0, 28), function()
        Config.FOV = 120 SetFOV() UpdateGUI()
    end)
    
    y = y + 38
    
    local brightBtn = CreateModernButton(content, "Bright", "Fullbright", nil, UDim2.new(0, 8, 0, y), UDim2.new(1, -16, 0, 36), function()
        ToggleFullbright() UpdateGUI()
    end)
    
    y = y + 42
    
    -- ═══ GAMEPLAY SECTION ═══
    CreateSectionLabel(content, "Gameplay", UDim2.new(0, 8, 0, y))
    y = y + 24
    
    local borderBtn = CreateModernButton(content, "Border", "Remove Borders", nil, UDim2.new(0, 8, 0, y), UDim2.new(1, -16, 0, 36), function()
        ToggleBorder() UpdateGUI()
    end)
    y = y + 40
    
    local antiBtn = CreateModernButton(content, "Anti", "Anti-Nextbot", nil, UDim2.new(0, 8, 0, y), UDim2.new(1, -16, 0, 36), function()
        State.AntiNextbot = not State.AntiNextbot
        if State.AntiNextbot then LoadNPCs() end
        UpdateGUI()
    end)
    y = y + 40
    
    local farmBtn = CreateModernButton(content, "Farm", "Auto Farm", nil, UDim2.new(0, 8, 0, y), UDim2.new(1, -16, 0, 36), function()
        State.AutoFarm = not State.AutoFarm
        if not State.AutoFarm then CurrentTarget = nil end
        UpdateGUI()
    end)
    y = y + 40
    
    local edgeBtn = CreateModernButton(content, "EdgeBoost", "Edge Boost", nil, UDim2.new(0, 8, 0, y), UDim2.new(1, -16, 0, 36), function()
        State.EdgeBoost = not State.EdgeBoost
        SetupEdgeBoost()
        UpdateGUI()
    end)
    y = y + 40
    
    local upFixBtn = CreateModernButton(content, "UpFix", "Upside Down Fix", nil, UDim2.new(0, 8, 0, y), UDim2.new(1, -16, 0, 36), function()
        State.UpsideDownFix = not State.UpsideDownFix
        ToggleUpsideDownFix(State.UpsideDownFix)
        UpdateGUI()
    end)
    y = y + 46
    
    -- ═══ COLA SECTION ═══
    CreateSectionLabel(content, "Cola", UDim2.new(0, 8, 0, y))
    y = y + 24
    
    -- Cola buttons row
    local fixBtn = CreateSmallButton(content, "Fix", "🔧 Fix", UDim2.new(0, 8, 0, y), UDim2.new(0, 70, 0, 30), FixCola)
    fixBtn.TextSize = 10
    
    local infColaBtn = CreateModernButton(content, "InfCola", "Infinite Cola", nil, UDim2.new(0, 84, 0, y - 3), UDim2.new(0, 188, 0, 36), function()
        State.InfiniteCola = not State.InfiniteCola
        ToggleInfiniteCola(State.InfiniteCola)
        UpdateGUI()
    end)
    y = y + 40
    
    -- Speed presets
    local presetLabel = Instance.new("TextLabel")
    presetLabel.Size = UDim2.new(0, 50, 0, 20)
    presetLabel.Position = UDim2.new(0, 8, 0, y + 4)
    presetLabel.BackgroundTransparency = 1
    presetLabel.Text = "Speed"
    presetLabel.TextColor3 = Theme.TextMuted
    presetLabel.TextSize = 10
    presetLabel.Font = FONT_SMALL
    presetLabel.TextXAlignment = Enum.TextXAlignment.Left
    presetLabel.Parent = content
    
    local colaLow = CreateSmallButton(content, "ColaLow", "1.4x", UDim2.new(0, 60, 0, y + 2), UDim2.new(0, 48, 0, 26), function()
        ColaConfig.Speed = 1.4 UpdateSliderUI(1.4) UpdateGUI()
    end)
    colaLow.TextSize = 10
    
    local colaMed = CreateSmallButton(content, "ColaMed", "1.6x", UDim2.new(0, 112, 0, y + 2), UDim2.new(0, 48, 0, 26), function()
        ColaConfig.Speed = 1.6 UpdateSliderUI(1.6) UpdateGUI()
    end)
    colaMed.TextSize = 10
    
    local colaHigh = CreateSmallButton(content, "ColaHigh", "1.8x", UDim2.new(0, 164, 0, y + 2), UDim2.new(0, 48, 0, 26), function()
        ColaConfig.Speed = 1.8 UpdateSliderUI(1.8) UpdateGUI()
    end)
    colaHigh.TextSize = 10
    
    y = y + 34
    
    -- Modern slider
    local sliderHolder = Instance.new("Frame")
    sliderHolder.Name = "SliderHolder"
    sliderHolder.Size = UDim2.new(1, -16, 0, 42)
    sliderHolder.Position = UDim2.new(0, 8, 0, y)
    sliderHolder.BackgroundTransparency = 1
    sliderHolder.Parent = content
    
    SliderLabel = Instance.new("TextLabel")
    SliderLabel.Size = UDim2.new(1, 0, 0, 16)
    SliderLabel.BackgroundTransparency = 1
    SliderLabel.Text = string.format("Cola Speed: %.1fx", ColaConfig.Speed)
    SliderLabel.TextColor3 = Theme.TextSecondary
    SliderLabel.TextSize = 10
    SliderLabel.Font = FONT_SMALL
    SliderLabel.TextXAlignment = Enum.TextXAlignment.Left
    SliderLabel.Parent = sliderHolder
    
    SliderTrack = Instance.new("Frame")
    SliderTrack.Size = UDim2.new(1, 0, 0, 6)
    SliderTrack.Position = UDim2.new(0, 0, 0, 22)
    SliderTrack.BackgroundColor3 = Theme.SliderBg
    SliderTrack.BorderSizePixel = 0
    SliderTrack.Parent = sliderHolder
    Instance.new("UICorner", SliderTrack).CornerRadius = UDim.new(0, 3)
    
    local initialPos = (ColaConfig.Speed - SliderMin) / (SliderMax - SliderMin)
    SliderFill = Instance.new("Frame")
    SliderFill.Size = UDim2.new(initialPos, 0, 1, 0)
    SliderFill.BackgroundColor3 = Theme.SliderFill
    SliderFill.BorderSizePixel = 0
    SliderFill.Parent = SliderTrack
    Instance.new("UICorner", SliderFill).CornerRadius = UDim.new(0, 3)
    
    -- Slider glow
    local sliderGlow = Instance.new("UIGradient", SliderFill)
    sliderGlow.Color = ColorSequence.new{
        ColorSequenceKeypoint.new(0, Color3.fromRGB(88, 101, 242)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(155, 89, 182)),
    }
    
    SliderThumb = Instance.new("Frame")
    SliderThumb.Size = UDim2.new(0, 14, 0, 14)
    SliderThumb.Position = UDim2.new(initialPos, -7, 0.5, -7)
    SliderThumb.BackgroundColor3 = Color3.new(1, 1, 1)
    SliderThumb.BorderSizePixel = 0
    SliderThumb.Parent = SliderTrack
    Instance.new("UICorner", SliderThumb).CornerRadius = UDim.new(1, 0)
    
    local thumbStroke = Instance.new("UIStroke", SliderThumb)
    thumbStroke.Color = Theme.Accent
    thumbStroke.Thickness = 2
    
    local sliderDragging = false
    local function UpdateSliderFromMouse(mousePos)
        if not SliderTrack then return end
        local pos = math.clamp((mousePos.X - SliderTrack.AbsolutePosition.X) / SliderTrack.AbsoluteSize.X, 0, 1)
        local val = math.round((SliderMin + pos * (SliderMax - SliderMin)) * 10) / 10
        val = math.clamp(val, SliderMin, SliderMax)
        ColaConfig.Speed = val
        Tween(SliderFill, {Size = UDim2.new(pos, 0, 1, 0)}, 0.05)
        Tween(SliderThumb, {Position = UDim2.new(pos, -7, 0.5, -7)}, 0.05)
        SliderLabel.Text = string.format("Cola Speed: %.1fx", val)
        UpdateGUI()
    end
    
    SliderThumb.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            sliderDragging = true
            Tween(SliderThumb, {Size = UDim2.new(0, 18, 0, 18), Position = UDim2.new(SliderThumb.Position.X.Scale, -9, 0.5, -9)}, 0.1)
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            sliderDragging = false
            local currentPos = (ColaConfig.Speed - SliderMin) / (SliderMax - SliderMin)
            Tween(SliderThumb, {Size = UDim2.new(0, 14, 0, 14), Position = UDim2.new(currentPos, -7, 0.5, -7)}, 0.1)
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if sliderDragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            UpdateSliderFromMouse(input.Position)
        end
    end)
    SliderTrack.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            UpdateSliderFromMouse(input.Position)
        end
    end)
    
    y = y + 36
    
    -- Duration input
    local durLabel = Instance.new("TextLabel")
    durLabel.Size = UDim2.new(0, 80, 0, 20)
    durLabel.Position = UDim2.new(0, 8, 0, y + 6)
    durLabel.BackgroundTransparency = 1
    durLabel.Text = "Duration (sec)"
    durLabel.TextColor3 = Theme.TextMuted
    durLabel.TextSize = 10
    durLabel.Font = FONT_SMALL
    durLabel.TextXAlignment = Enum.TextXAlignment.Left
    durLabel.Parent = content
    
    local colaDurInput = CreateModernInput(content, "ColaDur", tostring(ColaConfig.Duration), UDim2.new(0, 100, 0, y + 2), UDim2.new(0, 70, 0, 28), function(text)
        local num = tonumber(text)
        if num and num > 0 then ColaConfig.Duration = num end
    end)
    
    -- Update canvas size
    content.CanvasSize = UDim2.new(0, 0, 0, y + 50)
    
    MakeDraggable(main)
    
    -- Open animation
    main.Size = UDim2.new(0, 280, 0, 0)
    main.Visible = true
    Tween(main, {Size = UDim2.new(0, 280, 0, 480)}, 0.4, Enum.EasingStyle.Back)
    
    UpdateGUI()
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
    container.BackgroundColor3 = Theme.Background
    container.BorderSizePixel = 0
    Instance.new("UICorner", container).CornerRadius = UDim.new(0, 10)
    
    local timerStroke = Instance.new("UIStroke", container)
    timerStroke.Color = Theme.Border
    timerStroke.Thickness = 1
    
    AddShadow(container, 3, 0.6)
    
    -- Accent top line
    local topLine = Instance.new("Frame")
    topLine.Size = UDim2.new(0.6, 0, 0, 2)
    topLine.Position = UDim2.new(0.2, 0, 0, 0)
    topLine.BackgroundColor3 = Theme.Accent
    topLine.BorderSizePixel = 0
    topLine.Parent = container
    Instance.new("UICorner", topLine).CornerRadius = UDim.new(0, 1)
    
    StatusLabel = Instance.new("TextLabel", container)
    StatusLabel.Position = UDim2.new(0.5, 0, 0, 8)
    StatusLabel.AnchorPoint = Vector2.new(0.5, 0)
    StatusLabel.Size = UDim2.new(1, 0, 0, 14)
    StatusLabel.BackgroundTransparency = 1
    StatusLabel.Font = FONT_HEADING
    StatusLabel.Text = "WAITING"
    StatusLabel.TextColor3 = Theme.TextMuted
    StatusLabel.TextSize = 9
    
    TimerLabel = Instance.new("TextLabel", container)
    TimerLabel.Position = UDim2.new(0.5, 0, 0, 22)
    TimerLabel.AnchorPoint = Vector2.new(0.5, 0)
    TimerLabel.Size = UDim2.new(1, 0, 0, 26)
    TimerLabel.BackgroundTransparency = 1
    TimerLabel.Font = FONT_TITLE
    TimerLabel.Text = "0:00"
    TimerLabel.TextColor3 = Theme.TextPrimary
    TimerLabel.TextSize = 22
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
            TimerLabel.TextColor3 = (roundStarted and timer and timer <= 15) and Theme.Danger or Theme.TextPrimary
        end
        if StatusLabel then
            StatusLabel.Text = roundStarted and "⚡ RUNNING" or "⏳ WAITING"
            StatusLabel.TextColor3 = roundStarted and Theme.Success or Theme.TextMuted
        end
    end)
end

-- ═══════════════════════════════════════════════════════════════
-- INPUT HANDLING
-- ═══════════════════════════════════════════════════════════════

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    local key = input.KeyCode
    if key == Enum.KeyCode.Space then
        holdSpace = true
        LastGroundState = false
        WasInAir = false
        JumpQueued = true
        -- Capture current speed immediately when space is pressed
        if RootPart then
            local speed = GetHorizontalSpeed()
            if speed > BhopConfig.MinPreserveSpeed then
                LastHorizontalSpeed = speed
                SavedHorizontalVelocity = GetHorizontalVelocity()
            end
        end
    elseif key == Enum.KeyCode.X then holdX = true
    elseif key == Enum.KeyCode.E then Revive()
    elseif key == Enum.KeyCode.R then SelfResurrect()
    elseif key == Enum.KeyCode.Q then holdQ = true
    elseif key == Enum.KeyCode.P then ToggleFullbright() UpdateGUI()
    elseif key == Enum.KeyCode.RightShift then
        if GUI and GUI:FindFirstChild("Main") then
            local mainFrame = GUI.Main
            if mainFrame.Visible then
                Tween(mainFrame, {Size = UDim2.new(0, 280, 0, 0)}, 0.3)
                task.delay(0.3, function() mainFrame.Visible = false end)
            else
                mainFrame.Visible = true
                mainFrame.Size = UDim2.new(0, 280, 0, 0)
                Tween(mainFrame, {Size = UDim2.new(0, 280, 0, 480)}, 0.4, Enum.EasingStyle.Back)
            end
            if VIPPanel then VIPPanel.Visible = false end
        end
    end
end)

UserInputService.InputEnded:Connect(function(input)
    local key = input.KeyCode
    if key == Enum.KeyCode.Space then
        holdSpace = false
        LastGroundState = false
        ConsecutiveJumps = 0
        WasInAir = false
        PreLandingQueued = false
        JumpQueued = false
    elseif key == Enum.KeyCode.Q then holdQ = false
    elseif key == Enum.KeyCode.X then holdX = false AirEnd = 0
    end
end)

-- ═══════════════════════════════════════════════════════════════
-- CHARACTER SETUP
-- ═══════════════════════════════════════════════════════════════

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
    ConsecutiveJumps = 0
    LastHorizontalSpeed = 0
    SavedHorizontalVelocity = Vector3.zero
    WasInAir = false
    PreLandingQueued = false
    JumpQueued = false
    LastGroundCheckTick = 0
    table.clear(CachedBots)
    table.clear(CachedItems)
    
    if Humanoid then
        StateChangedConn = Humanoid.StateChanged:Connect(OnHumanoidStateChanged)
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

-- ═══════════════════════════════════════════════════════════════
-- MAIN LOOP
-- ═══════════════════════════════════════════════════════════════

local function StartMainLoop()
    if Connections.MainLoop then Connections.MainLoop:Disconnect() end
    local lastUpdate = 0
    local lastEdgeUpdate = 0
    
    Connections.MainLoop = RunService.RenderStepped:Connect(function()
        local now = tick()
        SuperBhop()
        PreJumpQueue()
        Bounce()
        AirStrafe()
        DoCarry()
        
        if State.EdgeBoost and now - lastEdgeUpdate >= 0.016 then
            lastEdgeUpdate = now
            ReactiveEdgeBoost()
        end
        
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
        ConsecutiveJumps = 0
        LastHorizontalSpeed = 0
        SavedHorizontalVelocity = Vector3.zero
        ColaDrank = false
        WasInAir = false
        PreLandingQueued = false
        table.clear(CachedBots)
        table.clear(CachedItems)
        if State.UpsideDownFix then State.UpsideDownFix = false ToggleUpsideDownFix(false) UpdateGUI() end
    end
end)

LocalPlayer.Idled:Connect(function()
    VirtualUser:Button2Down(Vector2.new(0, 0), Workspace.CurrentCamera.CFrame)
    task.wait(1)
    VirtualUser:Button2Up(Vector2.new(0, 0), Workspace.CurrentCamera.CFrame)
end)

CreateMainGUI()
CreateTimerGUI()
UpdateTimer()
SetFOV()
SetupCameraFOV()
LoadNPCs()
ForceUpdateRayFilter()
StartMainLoop()
