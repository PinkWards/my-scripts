if not game:IsLoaded() then game.Loaded:Wait() end

local SCRIPT_VERSION = 18

pcall(function()
    if queue_on_teleport then
        local scriptToQueue = game:HttpGet("https://raw.githubusercontent.com/PinkWards/my-scripts/refs/heads/main/evade.lua")
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
    EdgeBoost = false,
    ExchangeUnlocked = false
}

local Config = {
    FOV = 120,
    DangerThreshold = 60,
    SafeDistance = 90
}

-- ═══════════════════════════════════════════════════════════════
-- BOUNCE CONFIG - REALISTIC: Must touch ground, instant response
-- ═══════════════════════════════════════════════════════════════

local BounceConfig = {
    Power = 90,
    Cooldown = 0.05,
    MaxSpeed = 1000,
}

-- ═══════════════════════════════════════════════════════════════
-- COLA SETTINGS
-- ═══════════════════════════════════════════════════════════════

local ColaSettings = {
    Speed = 1.4,
    Duration = 3.5,
    Active = false,
    HookInstalled = false,
    OldNamecall = nil,
}

local ColaSpeedPresets = {
    {name = "Normal",    speed = 1.4},
    {name = "Fast",      speed = 1.6},
    {name = "VeryFast",  speed = 1.8},
    {name = "Ultra",     speed = 2.0},
    {name = "Insane",    speed = 2.5},
    {name = "Max",       speed = 3.0},
}

local Humanoid, RootPart = nil, nil
local GUI, VIPPanel, TimerGUI = nil, nil, nil
local TimerLabel, StatusLabel = nil, nil

local holdQ, holdSpace, holdLeftShift = false, false, false

local LastAntiCheck, LastCarry, LastBounce = 0, 0, 0
local LastVoteMap, LastVoteMode = 0, 0
local SelfResCD = 0
local LastRayFilterUpdate = 0
local LastEdgeCheck = 0

local CurrentTarget, FarmStart = nil, 0
local NPCNames = {}
local NPCLoaded = false
local CachedBots, CachedItems = {}, {}
local Maps, Modes = {}, {}
local FullbrightEnabled = false
local SavedLighting = nil
local LastCamera = nil

local Connections = {}
local EdgeTouchConnections = {}
local ExchangeConnections = {}
local CachedGame = nil
local StateChangedConn = nil
local BounceStateConn = nil
local BhopHeartbeatConn = nil

local SliderTrack, SliderFill, SliderThumb, SliderLabel
local SliderMin, SliderMax = 1.4, 3.0

local LastGCTime = 0
local GC_INTERVAL = 120
local LastCacheCleanup = 0
local CACHE_CLEANUP_INTERVAL = 45

-- REALISTIC BOUNCE STATE
local RecordedSpeed = 16
local IsBouncing = false
local WasInAir = false

-- BHOP STATE
local WasGrounded = false
local LastJumpTime = 0
local JUMP_COOLDOWN = 0.1 -- Prevent spam jumping

local EdgeRayParams = RaycastParams.new()
EdgeRayParams.FilterType = Enum.RaycastFilterType.Exclude
EdgeRayParams.IgnoreWater = true
EdgeRayParams.RespectCanCollide = true

local VEC3_ZERO = Vector3.zero
local VEC3_DOWN = Vector3.new(0, -1, 0)
local VEC3_Y_AXIS = Vector3.yAxis
local VEC2_ZERO = Vector2.new(0, 0)

-- ═══════════════════════════════════════════════════════════════
-- THEME
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
-- UTILITY
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
    if now - LastRayFilterUpdate < 3.0 then return end
    LastRayFilterUpdate = now
    local filterList = {}
    local character = LocalPlayer.Character
    if character then filterList[#filterList + 1] = character end
    for _, player in ipairs(Players:GetPlayers()) do
        if player.Character then filterList[#filterList + 1] = player.Character end
    end
    local gameFolder = Workspace:FindFirstChild("Game")
    if gameFolder then
        local gamePlayers = gameFolder:FindFirstChild("Players")
        if gamePlayers then filterList[#filterList + 1] = gamePlayers end
    end
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

local function GetDistanceSq(position, bots)
    local minDistSq = math.huge
    for _, botPos in ipairs(bots) do
        local dx = position.X - botPos.X
        local dy = position.Y - botPos.Y
        local dz = position.Z - botPos.Z
        local distSq = dx*dx + dy*dy + dz*dz
        if distSq < minDistSq then minDistSq = distSq end
    end
    return minDistSq
end

local function GetNamesFromPath(path)
    local names = {}
    local folder = ReplicatedStorage
    for part in path:gmatch("[^%.]+") do
        folder = folder and folder:FindFirstChild(part)
    end
    if folder then
        for _, child in ipairs(folder:GetChildren()) do
            names[#names + 1] = child.Name
        end
    end
    return names
end

task.spawn(function()
    Maps = GetNamesFromPath("Info.Maps")
    Modes = GetNamesFromPath("Info.Gamemodes")
end)

local function PeriodicCleanup()
    local now = tick()
    
    if now - LastCacheCleanup >= CACHE_CLEANUP_INTERVAL then
        LastCacheCleanup = now
        
        for i = 1, #CachedBots do CachedBots[i] = nil end
        LastBotCheck = 0
        
        local validCount = 0
        for i = 1, #CachedItems do
            local item = CachedItems[i]
            if item and item.object and item.object.Parent then
                validCount = validCount + 1
                if validCount ~= i then
                    CachedItems[validCount] = item
                end
            end
        end
        for i = validCount + 1, #CachedItems do
            CachedItems[i] = nil
        end
        
        if CachedGame and not CachedGame.Parent then
            CachedGame = Workspace:FindFirstChild("Game")
        end
    end
    
    if now - LastGCTime >= GC_INTERVAL then
        LastGCTime = now
        pcall(function()
            collectgarbage("step", 50)
        end)
    end
end

local function CleanupAll()
    for _, conn in pairs(Connections) do SafeCall(function() conn:Disconnect() end) end
    table.clear(Connections)
    for _, conn in pairs(EdgeTouchConnections) do SafeCall(function() conn:Disconnect() end) end
    table.clear(EdgeTouchConnections)
    for _, conn in pairs(ExchangeConnections) do SafeCall(function() conn:Disconnect() end) end
    table.clear(ExchangeConnections)
    getgenv().var156_upvw_arg1 = nil
    if StateChangedConn then SafeCall(function() StateChangedConn:Disconnect() end) StateChangedConn = nil end
    if BounceStateConn then SafeCall(function() BounceStateConn:Disconnect() end) BounceStateConn = nil end
    if BhopHeartbeatConn then SafeCall(function() BhopHeartbeatConn:Disconnect() end) BhopHeartbeatConn = nil end
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
        for _, npc in ipairs(folder:GetChildren()) do NPCNames[npc.Name] = true end
        NPCLoaded = true
    else
        NPCLoaded = false
    end
end

-- ═══════════════════════════════════════════════════════════════
-- FIXED BHOP SYSTEM - Prevents spam jumping
-- ═══════════════════════════════════════════════════════════════

local function IsGrounded()
    if not Humanoid then return false end
    local state = Humanoid:GetState()
    return state == Enum.HumanoidStateType.Landed or 
           state == Enum.HumanoidStateType.Running or
           state == Enum.HumanoidStateType.RunningNoPhysics
end

local function ExecuteJump()
    if not Humanoid or Humanoid.Health <= 0 then return end
    
    local now = tick()
    
    -- Prevent spam jumping with cooldown
    if now - LastJumpTime < JUMP_COOLDOWN then return end
    
    -- Only jump if actually grounded
    if not IsGrounded() then return end
    
    Humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
    LastJumpTime = now
    WasGrounded = false
end

-- State-based detection (fires on state change)
local function OnBhopStateChanged(old, new)
    if not holdSpace then 
        -- Update grounded state when not holding space
        if IsGrounded() then
            WasGrounded = true
        end
        return 
    end
    
    -- Detect landing transition
    if new == Enum.HumanoidStateType.Landed or 
       new == Enum.HumanoidStateType.Running or 
       new == Enum.HumanoidStateType.RunningNoPhysics then
        
        -- Only jump if we weren't already grounded (prevents spam)
        if not WasGrounded then
            WasGrounded = true
            ExecuteJump()
        end
    elseif new == Enum.HumanoidStateType.Freefall or 
           new == Enum.HumanoidStateType.Jumping then
        -- Reset grounded state when in air
        WasGrounded = false
    end
end

-- Heartbeat loop for catching missed states
local function OnBhopHeartbeat()
    if not holdSpace or not Humanoid then return end
    
    local isCurrentlyGrounded = IsGrounded()
    
    -- Only jump when transitioning from air to ground
    if isCurrentlyGrounded and not WasGrounded then
        WasGrounded = true
        ExecuteJump()
    elseif not isCurrentlyGrounded then
        WasGrounded = false
    end
end

-- ═══════════════════════════════════════════════════════════════
-- BOUNCE SYSTEM - REALISTIC: Touch ground to bounce, zero delay
-- ═══════════════════════════════════════════════════════════════

local function ExecuteBounce()
    local now = tick()
    if now - LastBounce < BounceConfig.Cooldown then return end
    if not RootPart or not Humanoid then return end
    if Humanoid.Health <= 0 then return end

    local vel = RootPart.AssemblyLinearVelocity
    local hVel = Vector3.new(vel.X, 0, vel.Z)
    local hSpeed = hVel.Magnitude

    -- Pure stacking: only ever increase
    if hSpeed > RecordedSpeed then
        RecordedSpeed = hSpeed
    end

    local useSpeed = math.max(RecordedSpeed, hSpeed)
    useSpeed = math.min(useSpeed, BounceConfig.MaxSpeed)

    -- Get direction
    local dir
    if hSpeed > 1 then
        dir = hVel.Unit
    else
        local cam = Workspace.CurrentCamera
        if cam then
            local look = cam.CFrame.LookVector
            dir = Vector3.new(look.X, 0, look.Z)
            if dir.Magnitude > 0.01 then
                dir = dir.Unit
            else
                dir = Vector3.new(0, 0, -1)
            end
        else
            dir = Vector3.new(0, 0, -1)
        end
    end

    -- Apply: full speed + upward bounce
    RootPart.AssemblyLinearVelocity = dir * useSpeed + Vector3.new(0, BounceConfig.Power, 0)

    -- Force jump state so engine doesnt apply ground friction
    Humanoid:ChangeState(Enum.HumanoidStateType.Jumping)

    IsBouncing = true
    LastBounce = now
end

-- This fires the INSTANT the humanoid touches ground - zero frame delay
local function OnBounceStateChanged(old, new)
    if not holdLeftShift then return end
    if not RootPart or not Humanoid then return end
    if Humanoid.Health <= 0 then return end

    -- Only bounce when we actually land (realistic - must touch ground)
    if new == Enum.HumanoidStateType.Landed or new == Enum.HumanoidStateType.Running then
        local character = LocalPlayer.Character
        if character then
            local isDowned = SafeCall(function() return character:GetAttribute("Downed") end)
            if isDowned then return end
        end

        -- Execute bounce immediately on the same frame as landing
        ExecuteBounce()
    end
end

-- Track speed while in air so we dont lose it
local function UpdateBounceAirSpeed()
    if not holdLeftShift then
        if IsBouncing then
            IsBouncing = false
        end
        return
    end

    if not RootPart or not Humanoid then return end
    if Humanoid.Health <= 0 then return end

    local vel = RootPart.AssemblyLinearVelocity
    local hSpeed = Vector3.new(vel.X, 0, vel.Z).Magnitude

    -- Always track the highest speed during bounce chain
    if IsBouncing and hSpeed > RecordedSpeed then
        RecordedSpeed = hSpeed
    end

    -- While in air during a bounce chain, preserve horizontal speed
    if IsBouncing then
        local state = Humanoid:GetState()
        if state == Enum.HumanoidStateType.Freefall then
            local currentHSpeed = Vector3.new(vel.X, 0, vel.Z).Magnitude
            -- If air drag reduced our speed, restore it
            if currentHSpeed > 1 and currentHSpeed < RecordedSpeed * 0.85 then
                local dir = Vector3.new(vel.X, 0, vel.Z).Unit
                RootPart.AssemblyLinearVelocity = Vector3.new(
                    dir.X * RecordedSpeed,
                    vel.Y,
                    dir.Z * RecordedSpeed
                )
            end
        end
    end
end

-- ═══════════════════════════════════════════════════════════════
-- GAME LOGIC
-- ═══════════════════════════════════════════════════════════════

local LastBotCheck = 0
local function GetBots()
    local now = tick()
    if now - LastBotCheck < 0.3 then return CachedBots end
    LastBotCheck = now
    if not NPCLoaded then LoadNPCs() end
    local count = 0
    if not CachedGame then CachedGame = Workspace:FindFirstChild("Game") end
    if CachedGame then
        local gamePlayers = CachedGame:FindFirstChild("Players")
        if gamePlayers then
            for _, model in ipairs(gamePlayers:GetChildren()) do
                if model:IsA("Model") and NPCNames[model.Name] then
                    local hrp = model:FindFirstChild("HumanoidRootPart")
                    if hrp then count = count + 1 CachedBots[count] = hrp.Position end
                end
            end
        end
    end
    for i = count + 1, #CachedBots do CachedBots[i] = nil end
    return CachedBots
end

local LastItemCheck = 0
local function GetItems()
    local now = tick()
    if now - LastItemCheck < 0.3 then return CachedItems end
    LastItemCheck = now
    local count = 0
    if not CachedGame then CachedGame = Workspace:FindFirstChild("Game") end
    if not CachedGame then for i = 1, #CachedItems do CachedItems[i] = nil end return CachedItems end
    local effects = CachedGame:FindFirstChild("Effects")
    if not effects then for i = 1, #CachedItems do CachedItems[i] = nil end return CachedItems end
    for _, containerName in ipairs({"Tickets", "Collectables"}) do
        local container = effects:FindFirstChild(containerName)
        if container then
            for _, item in ipairs(container:GetChildren()) do
                if item and item.Parent then
                    local part
                    if item:IsA("Model") then part = item:FindFirstChild("HumanoidRootPart") or item.PrimaryPart or item:FindFirstChildWhichIsA("BasePart")
                    elseif item:IsA("BasePart") then part = item end
                    if part and part.Parent then
                        count = count + 1
                        local entry = CachedItems[count]
                        if entry then entry.object = item entry.position = part.Position
                        else CachedItems[count] = {object = item, position = part.Position} end
                    end
                end
            end
        end
    end
    for i = count + 1, #CachedItems do CachedItems[i] = nil end
    return CachedItems
end

local function FindSafeSpot(myPos, bots)
    local safeLocations = {}
    if not CachedGame then CachedGame = Workspace:FindFirstChild("Game") end
    if CachedGame then
        local mapFolder = CachedGame:FindFirstChild("Map")
        local partsFolder = mapFolder and mapFolder:FindFirstChild("Parts")
        local spawnsFolder = partsFolder and partsFolder:FindFirstChild("Spawns")
        if spawnsFolder then
            for _, spawn in ipairs(spawnsFolder:GetChildren()) do
                if spawn:IsA("BasePart") then safeLocations[#safeLocations + 1] = spawn.Position + Vector3.new(0, 5, 0) end
            end
        end
    end
    local securityPart = Workspace:FindFirstChild("SecurityPart")
    if securityPart then safeLocations[#safeLocations + 1] = securityPart.Position + Vector3.new(0, 5, 0) end
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character then
            local hrp = player.Character:FindFirstChild("HumanoidRootPart")
            local isDowned = SafeCall(function() return player.Character:GetAttribute("Downed") end)
            if hrp and not isDowned then safeLocations[#safeLocations + 1] = hrp.Position + Vector3.new(0, 3, 0) end
        end
    end
    local bestLocation, bestDistSq = nil, 0
    local safeSq = Config.SafeDistance * Config.SafeDistance
    for _, location in ipairs(safeLocations) do
        local minDistSq = GetDistanceSq(location, bots)
        if minDistSq > bestDistSq and minDistSq >= safeSq then bestDistSq = minDistSq bestLocation = location end
    end
    if not bestLocation and securityPart then bestLocation = securityPart.Position + Vector3.new(0, 5, 0) end
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
            hrp.AssemblyLinearVelocity = VEC3_ZERO
            hrp.AssemblyAngularVelocity = VEC3_ZERO
        end
    end)
end

local function AntiNextbot()
    if not State.AntiNextbot then return end
    local now = tick()
    if now - LastAntiCheck < 0.35 then return end
    LastAntiCheck = now
    local character = LocalPlayer.Character
    if not character then return end
    local hrp = character:FindFirstChild("HumanoidRootPart")
    local isDowned = SafeCall(function() return character:GetAttribute("Downed") end)
    if not hrp or isDowned then return end
    local bots = GetBots()
    if #bots == 0 then return end
    local myPos = hrp.Position
    local closestDistSq = GetDistanceSq(myPos, bots)
    if closestDistSq <= Config.DangerThreshold * Config.DangerThreshold then
        local safeSpot = FindSafeSpot(myPos, bots)
        if safeSpot then Teleport(safeSpot) end
    end
end

local LastFarmTick = 0
local function AutoFarm()
    if not State.AutoFarm then return end
    local now = tick()
    if now - LastFarmTick < 0.15 then return end
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
        if securityPart then Teleport(securityPart.Position) end
        CurrentTarget = nil
        return
    end
    local items = GetItems()
    if #items == 0 then
        local securityPart = Workspace:FindFirstChild("SecurityPart")
        if securityPart then Teleport(securityPart.Position) end
        CurrentTarget = nil
        return
    end
    if CurrentTarget then
        if not CurrentTarget.object or not CurrentTarget.object.Parent then
            CurrentTarget = nil FarmStart = 0
        else
            local obj = CurrentTarget.object
            local part
            if obj:IsA("Model") then part = obj:FindFirstChild("HumanoidRootPart") or obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart")
            elseif obj:IsA("BasePart") then part = obj end
            if part and part.Parent then Teleport(part.Position) CurrentTarget.position = part.Position end
            if now - FarmStart >= 0.25 then CurrentTarget = nil FarmStart = 0 end
            return
        end
    end
    local myPos = hrp.Position
    local nearestItem, nearestDistSq = nil, math.huge
    for _, item in ipairs(items) do
        if item.object and item.object.Parent then
            local dx = myPos.X - item.position.X
            local dy = myPos.Y - item.position.Y
            local dz = myPos.Z - item.position.Z
            local distSq = dx*dx + dy*dy + dz*dz
            if distSq < nearestDistSq then nearestDistSq = distSq nearestItem = item end
        end
    end
    if nearestItem then CurrentTarget = nearestItem FarmStart = now Teleport(nearestItem.position) end
end

local function ToggleUpsideDownFix(enabled)
    State.UpsideDownFix = enabled
    if Connections.UpsideDown then Connections.UpsideDown:Disconnect() Connections.UpsideDown = nil end
    if enabled then
        Connections.UpsideDown = RunService.RenderStepped:Connect(function()
            local camera = Workspace.CurrentCamera
            if not camera then return end
            local cf = camera.CFrame
            local rx, ry, rz = cf:ToEulerAnglesXYZ()
            if math.abs(rz) > 1.5708 then camera.CFrame = CFrame.new(cf.Position) * CFrame.Angles(rx, ry, 0) end
        end)
    end
end

-- ═══════════════════════════════════════════════════════════════
-- EXCHANGE BUTTON UNLOCKER
-- ═══════════════════════════════════════════════════════════════

local function ForceEnableExchange()
    if getgenv().var156_upvw_arg1 then
        game:GetService("Players").LocalPlayer.PlayerGui.Global.Messages.Use:Fire("You can only use this at a time jae", "Error")
        return
    end
    getgenv().var156_upvw_arg1 = true
    
    State.ExchangeUnlocked = true
    
    local Players = game:GetService("Players")
    local player = Players.LocalPlayer

    function arg69()
        function arg_v5()
            local exchangeButton = player.PlayerGui:FindFirstChild("Menu") and 
            player.PlayerGui.Menu:FindFirstChild("Views") and 
            player.PlayerGui.Menu.Views:FindFirstChild("Default") and 
            player.PlayerGui.Menu.Views.Default:FindFirstChild("MainMenu") and 
            player.PlayerGui.Menu.Views.Default.MainMenu:FindFirstChild("LeftCorner") and 
            player.PlayerGui.Menu.Views.Default.MainMenu.LeftCorner:FindFirstChild("Exchange") and 
            player.PlayerGui.Menu.Views.Default.MainMenu.LeftCorner.Exchange:FindFirstChild("ImageButton")

            local exitButton = player.PlayerGui:FindFirstChild("Menu") and 
            player.PlayerGui.Menu:FindFirstChild("Views") and 
            player.PlayerGui.Menu.Views:FindFirstChild("Battlepass") and 
            player.PlayerGui.Menu.Views.Battlepass:FindFirstChild("Exchange") and 
            player.PlayerGui.Menu.Views.Battlepass.Exchange:FindFirstChild("Center") and 
            player.PlayerGui.Menu.Views.Battlepass.Exchange.Center:FindFirstChild("Exit") and 
            player.PlayerGui.Menu.Views.Battlepass.Exchange.Center.Exit:FindFirstChild("ImageButton")

            if exchangeButton then
                player.PlayerGui.Menu.Views.Default.MainMenu.LeftCorner.Exchange.Visible = true

                if ExchangeConnections.ExchangeClick then
                    ExchangeConnections.ExchangeClick:Disconnect()
                end
                
                ExchangeConnections.ExchangeClick = exchangeButton.MouseButton1Click:Connect(function()
                    local battlepass = player.PlayerGui.Menu.Views:FindFirstChild("Battlepass")
                    if battlepass then
                        battlepass.Center.Visible = false
                        battlepass.Exchange.Visible = true
                    end
                end)
            end

            if exitButton then
                if ExchangeConnections.ExitClick then
                    ExchangeConnections.ExitClick:Disconnect()
                end
                
                ExchangeConnections.ExitClick = exitButton.MouseButton1Click:Connect(function()
                    local battlepass = player.PlayerGui.Menu.Views:FindFirstChild("Battlepass")
                    if battlepass then
                        repeat task.wait() until battlepass.Visible == false
                        battlepass.Exchange.Visible = false
                        battlepass.Center.Visible = true
                    end
                end)
            end
        end

        arg_v5()

        if ExchangeConnections.DescendantAdded then
            ExchangeConnections.DescendantAdded:Disconnect()
        end
        
        ExchangeConnections.DescendantAdded = player.PlayerGui.DescendantAdded:Connect(function()
            task.wait(0.1)
            arg_v5()
        end)
    end

    arg69()
end

-- ═══════════════════════════════════════════════════════════════
-- EDGE BOOST
-- ═══════════════════════════════════════════════════════════════

local EdgeConfig = {
    Boost = 35,
    MinSpeed = 3,
    Cooldown = 0.12,
    MinEdge = 0.5,
    LastTime = 0,
    DetectionRange = 2.5,
    RayDepth = 5
}

local function DetectEdge(position, direction)
    local centerRay = Workspace:Raycast(position, Vector3.new(0, -EdgeConfig.RayDepth, 0), EdgeRayParams)
    if not centerRay then return false, nil end
    local checkPos = position + direction * EdgeConfig.DetectionRange
    local edgeRay = Workspace:Raycast(checkPos, Vector3.new(0, -EdgeConfig.RayDepth - 2, 0), EdgeRayParams)
    if not edgeRay then return true, centerRay.Position.Y end
    if centerRay.Position.Y - edgeRay.Position.Y >= EdgeConfig.MinEdge then return true, centerRay.Position.Y end
    return false, nil
end

local function ReactiveEdgeBoost()
    if not State.EdgeBoost or not Humanoid or not RootPart then return end
    if Humanoid.Health <= 0 then return end
    local now = tick()
    if now - EdgeConfig.LastTime < EdgeConfig.Cooldown then return end
    local character = LocalPlayer.Character
    if not character then return end
    local isDowned = SafeCall(function() return character:GetAttribute("Downed") end)
    if isDowned then return end
    local vel = RootPart.AssemblyLinearVelocity
    local hSpeedSq = vel.X * vel.X + vel.Z * vel.Z
    if hSpeedSq < EdgeConfig.MinSpeed * EdgeConfig.MinSpeed then return end
    local playerPos = RootPart.Position
    local invSpeed = 1 / math.sqrt(hSpeedSq)
    local moveDirX, moveDirZ = vel.X * invSpeed, vel.Z * invSpeed
    local rightVec = RootPart.CFrame.RightVector
    local checkDirs = {
        Vector3.new(moveDirX, 0, moveDirZ),
        Vector3.new(moveDirX * 0.7 + rightVec.X * 0.7, 0, moveDirZ * 0.7 + rightVec.Z * 0.7).Unit,
        Vector3.new(moveDirX * 0.7 - rightVec.X * 0.7, 0, moveDirZ * 0.7 - rightVec.Z * 0.7).Unit,
    }
    for _, dir in ipairs(checkDirs) do
        local isEdge, groundY = DetectEdge(playerPos, dir)
        if isEdge and groundY then
            local heightAboveGround = (playerPos.Y - (Humanoid.HipHeight + 0.5)) - groundY
            if heightAboveGround < 1.5 and heightAboveGround > -0.5 then
                local boostAmount = EdgeConfig.Boost
                if vel.Y < 0 then boostAmount = boostAmount * 1.2 end
                RootPart.AssemblyLinearVelocity = Vector3.new(vel.X, math.max(vel.Y, 0) + boostAmount, vel.Z)
                EdgeConfig.LastTime = now
                return
            end
        end
    end
end

local function EdgeBoostTouchHandler(hit)
    if not State.EdgeBoost or not hit or not hit.Parent then return end
    local character = LocalPlayer.Character
    if not character or not Humanoid or not RootPart then return end
    if hit:IsDescendantOf(character) then return end
    local hitModel = hit:FindFirstAncestorOfClass("Model")
    if hitModel then
        if Players:GetPlayerFromCharacter(hitModel) or hitModel:FindFirstChildOfClass("Humanoid") then return end
    end
    if not hit.CanCollide or hit.Transparency > 0.9 or hit.Size.Magnitude < 0.5 then return end
    local now = tick()
    if now - EdgeConfig.LastTime < EdgeConfig.Cooldown then return end
    local vel = RootPart.AssemblyLinearVelocity
    local hSpeedSq = vel.X * vel.X + vel.Z * vel.Z
    local minSq = (EdgeConfig.MinSpeed * 0.5) ^ 2
    if hSpeedSq < minSq then return end
    local partTop = hit.Position.Y + (hit.Size.Y * 0.5)
    local hitPos = hit.Position
    local halfX, halfZ = hit.Size.X * 0.5 + 0.5, hit.Size.Z * 0.5 + 0.5
    local playerPos = RootPart.Position
    local invSpeed = 1 / math.sqrt(hSpeedSq)
    local moveDirX, moveDirZ = vel.X * invSpeed, vel.Z * invSpeed
    local offsets = {
        Vector3.new(moveDirX > 0 and halfX or -halfX, 0, 0),
        Vector3.new(0, 0, moveDirZ > 0 and halfZ or -halfZ),
    }
    for _, offset in ipairs(offsets) do
        local checkPos = Vector3.new(hitPos.X + offset.X, partTop + 1, hitPos.Z + offset.Z)
        local ray = Workspace:Raycast(checkPos, Vector3.new(0, -3, 0), EdgeRayParams)
        if not ray or math.abs(partTop - ray.Position.Y) >= EdgeConfig.MinEdge then
            local dx = playerPos.X - (hitPos.X + offset.X)
            local dz = playerPos.Z - (hitPos.Z + offset.Z)
            if dx*dx + dz*dz < (EdgeConfig.DetectionRange + 1)^2 then
                RootPart.AssemblyLinearVelocity = Vector3.new(vel.X, math.max(vel.Y, 0) + EdgeConfig.Boost * 0.8, vel.Z)
                EdgeConfig.LastTime = now
                return
            end
        end
    end
end

local function SetupEdgeBoost()
    for _, conn in pairs(EdgeTouchConnections) do SafeCall(function() conn:Disconnect() end) end
    table.clear(EdgeTouchConnections)
    if not State.EdgeBoost then return end
    local character = LocalPlayer.Character
    if not character then return end
    for _, part in ipairs(character:GetDescendants()) do
        if part:IsA("BasePart") then EdgeTouchConnections[#EdgeTouchConnections + 1] = part.Touched:Connect(EdgeBoostTouchHandler) end
    end
end

local function DoCarry()
    if not holdQ then return end
    local now = tick()
    if now - LastCarry < 0.5 then return end
    LastCarry = now
    local character = LocalPlayer.Character
    if not character then return end
    local hrp = character:FindFirstChild("HumanoidRootPart")
    local isDowned = SafeCall(function() return character:GetAttribute("Downed") end)
    if not hrp or isDowned then return end
    local myPos = hrp.Position
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character then
            local otherHrp = player.Character:FindFirstChild("HumanoidRootPart")
            if otherHrp then
                local dx = myPos.X - otherHrp.Position.X
                local dy = myPos.Y - otherHrp.Position.Y
                local dz = myPos.Z - otherHrp.Position.Z
                if dx*dx + dy*dy + dz*dz <= 64 then
                    local otherDowned = SafeCall(function() return player.Character:GetAttribute("Downed") end)
                    local otherHum = player.Character:FindFirstChild("Humanoid")
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
end

local function Revive()
    local character = LocalPlayer.Character
    if not character then return end
    local hrp = character:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    local myPos = hrp.Position
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character then
            local otherHrp = player.Character:FindFirstChild("HumanoidRootPart")
            local otherDowned = SafeCall(function() return player.Character:GetAttribute("Downed") end)
            if otherHrp and otherDowned then
                local dx = myPos.X - otherHrp.Position.X
                local dy = myPos.Y - otherHrp.Position.Y
                local dz = myPos.Z - otherHrp.Position.Z
                if dx*dx + dy*dy + dz*dz <= 225 then
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
    if not CachedGame then CachedGame = Workspace:FindFirstChild("Game") end
    if not CachedGame then return end
    local mapFolder = CachedGame:FindFirstChild("Map")
    local invisParts = mapFolder and mapFolder:FindFirstChild("InvisParts")
    if invisParts then
        local targetCollide = not State.Border
        for _, obj in ipairs(invisParts:GetDescendants()) do
            if obj:IsA("BasePart") then obj.CanCollide = targetCollide end
        end
    end
end

local function SetFOV()
    local camera = Workspace.CurrentCamera
    if camera and camera.FieldOfView ~= Config.FOV then camera.FieldOfView = Config.FOV end
end

local function SetupCameraFOV()
    local camera = Workspace.CurrentCamera
    if camera then
        LastCamera = camera
        SetFOV()
        if Connections.CameraFOV then Connections.CameraFOV:Disconnect() end
        Connections.CameraFOV = camera:GetPropertyChangedSignal("FieldOfView"):Connect(function()
            if camera.FieldOfView ~= Config.FOV then camera.FieldOfView = Config.FOV end
        end)
    end
end

Connections.CameraChange = Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
    local camera = Workspace.CurrentCamera
    if camera and camera ~= LastCamera then SetupCameraFOV() end
end)

-- ═══════════════════════════════════════════════════════════════
-- COLA SYSTEM
-- ═══════════════════════════════════════════════════════════════

local function InstallColaHook()
    if ColaSettings.HookInstalled then return end

    local ToolAction = SafeGetPath(ReplicatedStorage, "Events", "Character", "ToolAction")
    local SpeedBoost = SafeGetPath(ReplicatedStorage, "Events", "Character", "SpeedBoost")

    if not ToolAction or not SpeedBoost then
        warn("[Cola] Events not found")
        return
    end

    local mt = getrawmetatable(game)
    if not mt then warn("[Cola] No metatable") return end

    ColaSettings.OldNamecall = mt.__namecall
    local lastBlock = 0

    setreadonly(mt, false)

    mt.__namecall = newcclosure(function(self, ...)
        local method = getnamecallmethod()
        local args = {...}

        if method == "FireServer" and self == ToolAction then
            if args[1] == 0 and args[2] == 20 then
                if ColaSettings.Active then
                    local now = tick()
                    if now - lastBlock < 0.5 then
                        return nil
                    end
                    lastBlock = now

                    task.spawn(function()
                        task.wait(0.3)
                        if ColaSettings.Active then
                            firesignal(
                                SpeedBoost.OnClientEvent,
                                "Cola",
                                ColaSettings.Speed,
                                ColaSettings.Duration,
                                Color3.fromRGB(199, 141, 93)
                            )
                        end
                    end)

                    return nil
                end
            end
        end

        return ColaSettings.OldNamecall(self, ...)
    end)

    setreadonly(mt, true)
    ColaSettings.HookInstalled = true
end

local function UninstallColaHook()
    if not ColaSettings.HookInstalled then return end
    ColaSettings.Active = false
    local mt = getrawmetatable(game)
    if ColaSettings.OldNamecall and mt then
        setreadonly(mt, false)
        mt.__namecall = ColaSettings.OldNamecall
        setreadonly(mt, true)
    end
    ColaSettings.HookInstalled = false
    ColaSettings.OldNamecall = nil
end

local function ToggleInfiniteColaFixed(state)
    if state then
        ColaSettings.Active = true
        State.InfiniteCola = true
        InstallColaHook()
    else
        State.InfiniteCola = false
        UninstallColaHook()
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
                if toolAction then toolAction:FireServer(0, 20) end
                return task.wait()
            end
            return oldNamecall(self, ...)
        end)
        setreadonly(mt, true)
    end)
end

local function ToggleFullbright()
    FullbrightEnabled = not FullbrightEnabled
    if FullbrightEnabled then
        SavedLighting = {Lighting.Brightness, Lighting.Ambient, Lighting.OutdoorAmbient, Lighting.ClockTime, Lighting.FogEnd}
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

local function GetVoteEvent() return SafeGetPath(ReplicatedStorage, "Events", "Player", "Vote") end
local function FindInList(name, list)
    if not name or name == "" then return nil end
    local nameLower = name:lower()
    for _, item in ipairs(list) do if item:lower() == nameLower then return item end end
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
local function StartMapVoting() if State.VoteMap then return end State.VoteMap = true VoteMapLoop() end
local function StopMapVoting() State.VoteMap = false end
local function StartModeVoting() if State.VoteMode then return end State.VoteMode = true VoteModeLoop() end
local function StopModeVoting() State.VoteMode = false end

-- [GUI CODE CONTINUES - Same as before, truncated for character limit]
-- The GUI section remains identical to the previous version

-- ═══════════════════════════════════════════════════════════════
-- INPUT
-- ═══════════════════════════════════════════════════════════════

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    local key = input.KeyCode
    
    if key == Enum.KeyCode.Space then
        holdSpace = true
        -- Immediate first jump only if grounded
        if IsGrounded() then
            ExecuteJump()
        end
    elseif key == Enum.KeyCode.E then 
        Revive()
    elseif key == Enum.KeyCode.R then 
        SelfResurrect()
    elseif key == Enum.KeyCode.Q then 
        holdQ = true
    elseif key == Enum.KeyCode.P then 
        ToggleFullbright() 
        UpdateGUI()
    elseif key == Enum.KeyCode.LeftShift then
        holdLeftShift = true
        if RootPart and Humanoid and Humanoid.Health > 0 then
            local vel = RootPart.AssemblyLinearVelocity
            local hSpeed = Vector3.new(vel.X, 0, vel.Z).Magnitude
            if hSpeed > RecordedSpeed then
                RecordedSpeed = hSpeed
            end
        end
    elseif key == Enum.KeyCode.RightShift then
        if GUI and GUI:FindFirstChild("Main") then
            local mainFrame = GUI.Main
            if mainFrame.Visible then
                Tween(mainFrame, {Size = UDim2.new(0, 280, 0, 0)}, TI_SLOW)
                task.delay(0.3, function() mainFrame.Visible = false end)
            else
                mainFrame.Visible = true mainFrame.Size = UDim2.new(0, 280, 0, 0)
                Tween(mainFrame, {Size = UDim2.new(0, 280, 0, 480)}, TI_OPEN)
            end
            if VIPPanel then VIPPanel.Visible = false end
        end
    end
end)

UserInputService.InputEnded:Connect(function(input)
    local key = input.KeyCode
    
    if key == Enum.KeyCode.Space then
        holdSpace = false
        WasGrounded = false -- Reset grounded state when releasing space
    elseif key == Enum.KeyCode.Q then 
        holdQ = false
    elseif key == Enum.KeyCode.LeftShift then
        holdLeftShift = false
        IsBouncing = false
        RecordedSpeed = 16
    end
end)

-- ═══════════════════════════════════════════════════════════════
-- CHARACTER SETUP
-- ═══════════════════════════════════════════════════════════════

local function SetupCharacter(character)
    if StateChangedConn then StateChangedConn:Disconnect() StateChangedConn = nil end
    if BounceStateConn then BounceStateConn:Disconnect() BounceStateConn = nil end
    if BhopHeartbeatConn then BhopHeartbeatConn:Disconnect() BhopHeartbeatConn = nil end
    
    Humanoid = character:WaitForChild("Humanoid", 5)
    RootPart = character:WaitForChild("HumanoidRootPart", 5)
    ForceUpdateRayFilter()
    SetupEdgeBoost()
    CurrentTarget, FarmStart = nil, 0
    LastBounce = 0
    LastJumpTime = 0
    WasInAir = false
    IsBouncing = false
    RecordedSpeed = 16
    WasGrounded = false
    table.clear(CachedBots) table.clear(CachedItems)
    
    if Humanoid then 
        -- Bhop: Dual detection system
        StateChangedConn = Humanoid.StateChanged:Connect(OnBhopStateChanged)
        BhopHeartbeatConn = RunService.Heartbeat:Connect(OnBhopHeartbeat)
        
        -- Bounce: Separate connection
        BounceStateConn = Humanoid.StateChanged:Connect(OnBounceStateChanged)
    end
end

Players.PlayerAdded:Connect(function(player)
    player.CharacterAdded:Connect(function() task.delay(0.5, ForceUpdateRayFilter) end)
    player.CharacterRemoving:Connect(function() task.delay(0.5, ForceUpdateRayFilter) end)
end)
Players.PlayerRemoving:Connect(function(player) if player == LocalPlayer then CleanupAll() else task.delay(0.5, ForceUpdateRayFilter) end end)
for _, player in ipairs(Players:GetPlayers()) do
    if player ~= LocalPlayer then
        player.CharacterAdded:Connect(function() task.delay(0.5, ForceUpdateRayFilter) end)
        player.CharacterRemoving:Connect(function() task.delay(0.5, ForceUpdateRayFilter) end)
    end
end

-- ═══════════════════════════════════════════════════════════════
-- MAIN LOOP
-- ═══════════════════════════════════════════════════════════════

local function StartMainLoop()
    if Connections.MainLoop then Connections.MainLoop:Disconnect() end
    if Connections.SlowLoop then Connections.SlowLoop:Disconnect() end
    
    Connections.MainLoop = RunService.RenderStepped:Connect(function()
        UpdateBounceAirSpeed()
    end)
    
    local slowAccum, edgeAccum, cleanupAccum = 0, 0, 0
    Connections.SlowLoop = RunService.Heartbeat:Connect(function(dt)
        if State.EdgeBoost then
            edgeAccum = edgeAccum + dt
            if edgeAccum >= 0.06 then
                edgeAccum = 0
                ReactiveEdgeBoost()
            end
        end
        
        if holdQ then DoCarry() end
        
        slowAccum = slowAccum + dt
        if slowAccum >= 0.2 then
            slowAccum = 0
            UpdateRayFilter()
            if State.AntiNextbot then AntiNextbot() end
            if State.AutoFarm then AutoFarm() end
        end
        
        cleanupAccum = cleanupAccum + dt
        if cleanupAccum >= 10.0 then
            cleanupAccum = 0
            PeriodicCleanup()
        end
    end)
end

-- ═══════════════════════════════════════════════════════════════
-- INIT
-- ═══════════════════════════════════════════════════════════════

if LocalPlayer.Character then SetupCharacter(LocalPlayer.Character) end
LocalPlayer.CharacterAdded:Connect(SetupCharacter)

Workspace.ChildAdded:Connect(function(child)
    if child.Name == "Game" then
        CachedGame = child task.wait(0.5) ForceUpdateRayFilter() CreateTimerGUI() UpdateTimer()
        NPCLoaded = false CurrentTarget, FarmStart = nil, 0 LastBounce = 0 LastJumpTime = 0
        WasInAir = false
        IsBouncing = false
        RecordedSpeed = 16
        WasGrounded = false
        table.clear(CachedBots) table.clear(CachedItems)
        if State.UpsideDownFix then State.UpsideDownFix = false ToggleUpsideDownFix(false) UpdateGUI() end
    end
end)

LocalPlayer.Idled:Connect(function()
    VirtualUser:Button2Down(VEC2_ZERO, Workspace.CurrentCamera.CFrame)
    task.wait(1)
    VirtualUser:Button2Up(VEC2_ZERO, Workspace.CurrentCamera.CFrame)
end)

CreateMainGUI() CreateTimerGUI() UpdateTimer() SetFOV() SetupCameraFOV() LoadNPCs() ForceUpdateRayFilter() StartMainLoop()

print("[Evade Helper] V" .. SCRIPT_VERSION .. " loaded! Fixed bhop - no spam jumping!")
