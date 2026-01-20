-- EVADE HELPER V8 - TRIMP-FRIENDLY BHOP 🚀
if not game:IsLoaded() then game.Loaded:Wait() end
if game.PlaceId ~= 9872472334 then return end

-- Services
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualUser = game:GetService("VirtualUser")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui", 10)
local Workspace = workspace

-- State Management
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
    Boost = 12,
    MinSpeed = 12,
    Cooldown = 0.2,
    MinEdge = 0.4,
    LastTime = 0
}

local ColaConfig = {
    Speed = 1.4,
    Duration = 3.5
}

-- Character References
local Humanoid, RootPart = nil, nil
local GUI, VIPPanel, TimerGUI = nil, nil, nil
local TimerLabel, StatusLabel = nil, nil

-- Input States
local holdQ, holdSpace, holdX = false, false, false

-- Timing
local LastAntiCheck, LastCarry, LastBounce, AirEnd = 0, 0, 0, 0
local LastVoteMap, LastVoteMode = 0, 0
local SelfResCD = 0
local LastRayFilterUpdate = 0

-- Caches
local CurrentTarget, FarmStart = nil, 0
local ColaDrank = false
local NPCNames = {}
local NPCLoaded = false
local CachedBots, CachedItems = {}, {}
local Maps, Modes = {}, {}
local FullbrightEnabled = false
local SavedLighting = nil
local LastCamera = nil

-- Connections Storage
local Connections = {}
local EdgeTouchConnections = {}
local CachedGame = nil
local StateChangedConn = nil

-- Slider UI References
local SliderTrack, SliderFill, SliderThumb, SliderLabel
local SliderMin, SliderMax = 1.0, 1.8

-- BHOP Variables
local LastGroundState = false
local LastJumpTick = 0
local BHOP_COOLDOWN = 0

-- Raycast Parameters
local BhopRayParams = RaycastParams.new()
BhopRayParams.FilterType = Enum.RaycastFilterType.Exclude
BhopRayParams.RespectCanCollide = true

local EdgeRayParams = RaycastParams.new()
EdgeRayParams.FilterType = Enum.RaycastFilterType.Exclude
EdgeRayParams.IgnoreWater = true

-- ═══════════════════════════════════════════════════════════════
-- RAYCAST FILTER
-- ═══════════════════════════════════════════════════════════════

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

-- ═══════════════════════════════════════════════════════════════
-- UTILITY FUNCTIONS
-- ═══════════════════════════════════════════════════════════════

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
-- GROUND DETECTION - TRIMP FRIENDLY
-- ═══════════════════════════════════════════════════════════════

local function IsOnGroundInstant()
    if not Humanoid or not RootPart then return false end
    
    -- Fast checks first
    if Humanoid.FloorMaterial ~= Enum.Material.Air then
        return true
    end
    
    local state = Humanoid:GetState()
    if state == Enum.HumanoidStateType.Running or
       state == Enum.HumanoidStateType.RunningNoPhysics or
       state == Enum.HumanoidStateType.Landed then
        return true
    end
    
    -- LOWERED raycast distance for better trimp control
    local rayResult = Workspace:Raycast(RootPart.Position, Vector3.new(0, -2.5, 0), BhopRayParams)
    if rayResult and rayResult.Instance then
        local hitPart = rayResult.Instance
        local hitModel = hitPart:FindFirstAncestorOfClass("Model")
        
        if hitModel then
            local hitPlayer = Players:GetPlayerFromCharacter(hitModel)
            if hitPlayer or hitModel:FindFirstChildOfClass("Humanoid") then
                return false
            end
        end
        
        -- LOWERED angle threshold - slopes won't trigger ground detection as easily
        local angle = math.deg(math.acos(math.clamp(rayResult.Normal:Dot(Vector3.yAxis), -1, 1)))
        return angle <= 35
    end
    
    return false
end

-- ═══════════════════════════════════════════════════════════════
-- BHOP SYSTEM - TRIMP FRIENDLY
-- ═══════════════════════════════════════════════════════════════

local function SuperBhop()
    if not holdSpace or not Humanoid or not RootPart then return end
    if Humanoid.Health <= 0 then return end
    
    local character = LocalPlayer.Character
    if not character or character:GetAttribute("Downed") then return end
    
    local onGround = IsOnGroundInstant()
    local now = tick()
    
    if onGround then
        if not LastGroundState or (now - LastJumpTick) >= BHOP_COOLDOWN then
            LastJumpTick = now
            Humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
            
            task.defer(function()
                if Humanoid and Humanoid.Health > 0 and holdSpace then
                    if IsOnGroundInstant() then
                        Humanoid.Jump = true
                    end
                end
            end)
        end
    end
    
    LastGroundState = onGround
end

local function PreJumpQueue()
    if not holdSpace or not Humanoid or not RootPart then return end
    if Humanoid.Health <= 0 then return end
    
    local state = Humanoid:GetState()
    if state == Enum.HumanoidStateType.Freefall then
        -- LOWERED raycast for less aggressive pre-jump
        local rayResult = Workspace:Raycast(RootPart.Position, Vector3.new(0, -5, 0), BhopRayParams)
        if rayResult then
            local hitPart = rayResult.Instance
            local hitModel = hitPart:FindFirstAncestorOfClass("Model")
            
            if hitModel then
                local hitPlayer = Players:GetPlayerFromCharacter(hitModel)
                if hitPlayer or hitModel:FindFirstChildOfClass("Humanoid") then
                    return
                end
            end
            
            -- Don't pre-jump on slopes/ramps - allows trimping!
            local angle = math.deg(math.acos(math.clamp(rayResult.Normal:Dot(Vector3.yAxis), -1, 1)))
            if angle > 25 then
                return
            end
            
            local dist = (RootPart.Position - rayResult.Position).Magnitude
            local vel = RootPart.AssemblyLinearVelocity.Y
            
            -- More precise: only trigger very close to ground
            if vel < -8 and dist < 2.8 then
                task.defer(function()
                    if holdSpace and Humanoid then
                        Humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
                    end
                end)
            end
        end
    end
end

-- ═══════════════════════════════════════════════════════════════
-- BOT DETECTION
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
    
    local gamePlayers = CachedGame and CachedGame:FindFirstChild("Players")
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

-- ═══════════════════════════════════════════════════════════════
-- ITEM COLLECTION
-- ═══════════════════════════════════════════════════════════════

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
    
    local effects = CachedGame and CachedGame:FindFirstChild("Effects")
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

-- ═══════════════════════════════════════════════════════════════
-- SAFE SPOT FINDER
-- ═══════════════════════════════════════════════════════════════

local function FindSafeSpot(myPos, bots)
    local safeLocations = {}
    
    if not CachedGame then
        CachedGame = Workspace:FindFirstChild("Game")
    end
    
    local mapFolder = CachedGame and CachedGame:FindFirstChild("Map")
    local partsFolder = mapFolder and mapFolder:FindFirstChild("Parts")
    local spawnsFolder = partsFolder and partsFolder:FindFirstChild("Spawns")
    
    if spawnsFolder then
        for _, spawn in ipairs(spawnsFolder:GetChildren()) do
            if spawn:IsA("BasePart") then
                table.insert(safeLocations, spawn.Position + Vector3.new(0, 5, 0))
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
            if hrp and not player.Character:GetAttribute("Downed") then
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

-- ═══════════════════════════════════════════════════════════════
-- TELEPORT
-- ═══════════════════════════════════════════════════════════════

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

-- ═══════════════════════════════════════════════════════════════
-- ANTI-NEXTBOT
-- ═══════════════════════════════════════════════════════════════

local function AntiNextbot()
    if not State.AntiNextbot then return end
    
    local now = tick()
    if now - LastAntiCheck < 0.15 then return end
    LastAntiCheck = now
    
    local character = LocalPlayer.Character
    if not character then return end
    
    local hrp = character:FindFirstChild("HumanoidRootPart")
    if not hrp or character:GetAttribute("Downed") then return end
    
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

-- ═══════════════════════════════════════════════════════════════
-- AUTO FARM
-- ═══════════════════════════════════════════════════════════════

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
    
    if character:GetAttribute("Downed") then
        SafeCall(function()
            ReplicatedStorage.Events.Player.ChangePlayerMode:FireServer(true)
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

-- ═══════════════════════════════════════════════════════════════
-- UPSIDE DOWN FIX
-- ═══════════════════════════════════════════════════════════════

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

-- ═══════════════════════════════════════════════════════════════
-- BOUNCE (X KEY)
-- ═══════════════════════════════════════════════════════════════

local function Bounce()
    if not holdX or not Humanoid or Humanoid.Health <= 0 then return end
    
    local character = LocalPlayer.Character
    if not character or character:GetAttribute("Downed") then return end
    
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

-- ═══════════════════════════════════════════════════════════════
-- AIR STRAFE
-- ═══════════════════════════════════════════════════════════════

local function AirStrafe()
    if tick() > AirEnd then return end
    
    local character = LocalPlayer.Character
    if not character then return end
    
    local root = character:FindFirstChild("HumanoidRootPart")
    if not root or character:GetAttribute("Downed") then return end
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

-- ═══════════════════════════════════════════════════════════════
-- EDGE BOOST
-- ═══════════════════════════════════════════════════════════════

local function EdgeBoostHandler(hit)
    if not State.EdgeBoost then return end
    if not hit or not hit.Parent then return end
    
    local character = LocalPlayer.Character
    if not character or not Humanoid then return end
    if hit:IsDescendantOf(character) then return end
    
    local hitModel = hit:FindFirstAncestorOfClass("Model")
    if hitModel then
        local hitPlayer = Players:GetPlayerFromCharacter(hitModel)
        if hitPlayer or hitModel:FindFirstChildOfClass("Humanoid") then
            return
        end
    end
    
    if not hit.CanCollide or hit.Transparency > 0.9 or hit.Size.Magnitude < 1 then return end
    
    local now = tick()
    if now - EdgeConfig.LastTime < EdgeConfig.Cooldown then return end
    
    local root = character:FindFirstChild("HumanoidRootPart")
    if not root then return end
    
    local vel = root.AssemblyLinearVelocity
    local horizontalSpeed = Vector3.new(vel.X, 0, vel.Z).Magnitude
    
    if horizontalSpeed < EdgeConfig.MinSpeed then return end
    
    local partTop = hit.Position.Y + (hit.Size.Y / 2)
    local playerBottom = root.Position.Y - Humanoid.HipHeight
    
    if playerBottom <= partTop then return end
    
    local foundEdge = false
    local directions = {
        Vector3.new(2, 0, 0), Vector3.new(-2, 0, 0),
        Vector3.new(0, 0, 2), Vector3.new(0, 0, -2)
    }
    
    for _, dir in ipairs(directions) do
        local origin = Vector3.new(hit.Position.X + dir.X, partTop + 2, hit.Position.Z + dir.Z)
        local ray = Workspace:Raycast(origin, Vector3.new(0, -5, 0), EdgeRayParams)
        
        if not ray or math.abs(partTop - ray.Position.Y) >= EdgeConfig.MinEdge then
            foundEdge = true
            break
        end
    end
    
    if foundEdge then
        root.AssemblyLinearVelocity = Vector3.new(vel.X, vel.Y + EdgeConfig.Boost, vel.Z)
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
            local conn = part.Touched:Connect(EdgeBoostHandler)
            table.insert(EdgeTouchConnections, conn)
        end
    end
end

-- ═══════════════════════════════════════════════════════════════
-- CARRY & REVIVE
-- ═══════════════════════════════════════════════════════════════

local function DoCarry()
    if not holdQ then return end
    
    local now = tick()
    if now - LastCarry < 0.4 then return end
    LastCarry = now
    
    local character = LocalPlayer.Character
    if not character then return end
    
    local hrp = character:FindFirstChild("HumanoidRootPart")
    if not hrp or character:GetAttribute("Downed") then return end
    
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character then
            local otherHrp = player.Character:FindFirstChild("HumanoidRootPart")
            local otherChar = player.Character
            
            if otherHrp and (hrp.Position - otherHrp.Position).Magnitude <= 8 then
                local isDowned = otherChar:GetAttribute("Downed")
                local otherHum = otherChar:FindFirstChild("Humanoid")
                local isPhysics = otherHum and otherHum:GetState() == Enum.HumanoidStateType.Physics
                
                if isDowned or isPhysics then
                    SafeCall(function()
                        ReplicatedStorage.Events.Character.Interact:FireServer("Carry", nil, player.Name)
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
            
            if otherHrp and otherChar:GetAttribute("Downed") then
                if (hrp.Position - otherHrp.Position).Magnitude <= 15 then
                    SafeCall(function()
                        ReplicatedStorage.Events.Character.Interact:FireServer("Revive", true, player.Name)
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
    if not character or not character:GetAttribute("Downed") then return end
    
    SelfResCD = now
    SafeCall(function()
        ReplicatedStorage.Events.Player.ChangePlayerMode:FireServer(true)
    end)
end

-- ═══════════════════════════════════════════════════════════════
-- TOGGLES
-- ═══════════════════════════════════════════════════════════════

local function ToggleBorder()
    State.Border = not State.Border
    
    if not CachedGame then
        CachedGame = Workspace:FindFirstChild("Game")
    end
    
    local mapFolder = CachedGame and CachedGame:FindFirstChild("Map")
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

-- ═══════════════════════════════════════════════════════════════
-- COLA FIX & INFINITE
-- ═══════════════════════════════════════════════════════════════

local function FixCola()
    SafeCall(function()
        local eventPath = LocalPlayer.PlayerScripts.Events.temporary_events.UseKeybind
        local mt = getrawmetatable(eventPath)
        local oldNamecall = mt.__namecall
        
        setreadonly(mt, false)
        mt.__namecall = newcclosure(function(self, ...)
            local method = getnamecallmethod()
            local args = {...}
            
            if method == "Fire" and self == eventPath and args[1] and args[1].Key == "Cola" then
                ReplicatedStorage.Events.Character.ToolAction:FireServer(0, 19)
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
    
    if enabled then
        local toolActionEvent = ReplicatedStorage.Events.Character.ToolAction
        local speedBoostEvent = ReplicatedStorage.Events.Character.SpeedBoost
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
            local toolActionEvent = ReplicatedStorage.Events.Character.ToolAction
            local mt = getrawmetatable(toolActionEvent)
            
            setreadonly(mt, false)
            mt.__namecall = ColaOldNamecall
            setreadonly(mt, true)
        end
    end
end

-- ═══════════════════════════════════════════════════════════════
-- VIP VOTING
-- ═══════════════════════════════════════════════════════════════

local function GetVoteEvent()
    return SafeCall(function() return ReplicatedStorage.Events.Player.Vote end)
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
        ReplicatedStorage.Events.CustomServers.Admin:FireServer(command, value)
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
-- GUI BUILDERS
-- ═══════════════════════════════════════════════════════════════

local function CreateButton(parent, name, text, x, y, w, h, callback)
    local button = Instance.new("TextButton")
    button.Name = name
    button.Size = UDim2.new(0, w, 0, h)
    button.Position = UDim2.new(0, x, 0, y)
    button.BackgroundColor3 = Color3.fromRGB(40, 40, 45)
    button.Text = text
    button.TextColor3 = Color3.new(1, 1, 1)
    button.TextSize = 11
    button.Font = Enum.Font.GothamMedium
    button.AutoButtonColor = false
    button.Parent = parent
    Instance.new("UICorner", button).CornerRadius = UDim.new(0, 5)
    button.MouseButton1Click:Connect(callback)
    return button
end

local function CreateLabel(parent, text, x, y, w, size, color)
    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(0, w, 0, 16)
    label.Position = UDim2.new(0, x, 0, y)
    label.BackgroundTransparency = 1
    label.Text = text
    label.TextColor3 = color or Color3.fromRGB(160, 160, 165)
    label.TextSize = size or 11
    label.Font = Enum.Font.Gotham
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = parent
    return label
end

local function CreateInput(parent, name, placeholder, x, y, w, callback)
    local input = Instance.new("TextBox")
    input.Name = name
    input.Size = UDim2.new(0, w, 0, 24)
    input.Position = UDim2.new(0, x, 0, y)
    input.BackgroundColor3 = Color3.fromRGB(35, 35, 40)
    input.Text = ""
    input.PlaceholderText = placeholder
    input.TextColor3 = Color3.new(1, 1, 1)
    input.PlaceholderColor3 = Color3.fromRGB(90, 90, 95)
    input.TextSize = 11
    input.Font = Enum.Font.Gotham
    input.ClearTextOnFocus = false
    input.Parent = parent
    Instance.new("UICorner", input).CornerRadius = UDim.new(0, 5)
    if callback then input.FocusLost:Connect(function() callback(input.Text) end) end
    return input
end

local function MakeDraggable(frame)
    local dragging, dragStart, startPos = false, nil, nil
    local dragArea = Instance.new("Frame")
    dragArea.Name = "DragArea"
    dragArea.Size = UDim2.new(1, 0, 0, 30)
    dragArea.Position = UDim2.new(0, 0, 0, 0)
    dragArea.BackgroundTransparency = 1
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

local function SetButtonActive(button, active)
    button:SetAttribute("Active", active)
    button.BackgroundColor3 = active and Color3.fromRGB(50, 180, 100) or Color3.fromRGB(40, 40, 45)
end

local function UpdateGUI()
    if not GUI then return end
    local main = GUI:FindFirstChild("Main")
    if not main then return end
    
    local function Update(name, active)
        local button = main:FindFirstChild(name)
        if button then SetButtonActive(button, active) end
    end
    
    Update("FOV90", Config.FOV == 90)
    Update("FOV120", Config.FOV == 120)
    Update("Bright", FullbrightEnabled)
    Update("Border", State.Border)
    Update("Anti", State.AntiNextbot)
    Update("Farm", State.AutoFarm)
    Update("InfCola", State.InfiniteCola)
    Update("UpFix", State.UpsideDownFix)
    Update("EdgeBoost", State.EdgeBoost)
    Update("ColaLow", ColaConfig.Speed == 1.4)
    Update("ColaMed", ColaConfig.Speed == 1.6)
    Update("ColaHigh", ColaConfig.Speed == 1.8)
end

local function UpdateSliderUI(value)
    if not SliderTrack then return end
    local pos = math.clamp((value - SliderMin) / (SliderMax - SliderMin), 0, 1)
    SliderFill.Size = UDim2.new(pos, 0, 1, 0)
    SliderThumb.Position = UDim2.new(pos, -6, 0.5, -6)
    SliderLabel.Text = string.format("Speed (%.1fx) • Default: 1.4x", value)
end

local function CreateVIPPanel()
    if VIPPanel then VIPPanel.Visible = not VIPPanel.Visible return end
    
    VIPPanel = Instance.new("Frame")
    VIPPanel.Name = "VIP"
    VIPPanel.Size = UDim2.new(0, 260, 0, 155)
    VIPPanel.Position = UDim2.new(0, 195, 0, 12)
    VIPPanel.BackgroundColor3 = Color3.fromRGB(25, 25, 28)
    VIPPanel.Parent = GUI
    Instance.new("UICorner", VIPPanel).CornerRadius = UDim.new(0, 8)
    Instance.new("UIStroke", VIPPanel).Color = Color3.fromRGB(70, 70, 80)
    
    CreateLabel(VIPPanel, "VIP Server", 10, 8, 100, 12, Color3.fromRGB(200, 200, 205))
    CreateButton(VIPPanel, "X", "X", 232, 6, 22, 22, function() VIPPanel.Visible = false end)
    
    local y = 36
    CreateLabel(VIPPanel, "Map Vote", 10, y, 60, 10)
    local autoVoteBtn = CreateButton(VIPPanel, "AV", "OFF", 75, y - 2, 36, 22, function() end)
    autoVoteBtn.MouseButton1Click:Connect(function()
        if State.VoteMap then StopMapVoting() else StartMapVoting() end
        autoVoteBtn.Text = State.VoteMap and "ON" or "OFF"
        SetButtonActive(autoVoteBtn, State.VoteMap)
    end)
    
    for i = 1, 4 do
        local btn = CreateButton(VIPPanel, "Mp" .. i, tostring(i), 108 + (i - 1) * 30, y - 2, 26, 22, function()
            State.MapIndex = i
            for j = 1, 4 do local b = VIPPanel:FindFirstChild("Mp" .. j) if b then SetButtonActive(b, j == i) end end
        end)
        if i == 1 then SetButtonActive(btn, true) end
    end
    
    y = y + 30
    CreateLabel(VIPPanel, "Mode Vote", 10, y, 60, 10)
    local autoModeBtn = CreateButton(VIPPanel, "AM", "OFF", 75, y - 2, 36, 22, function() end)
    autoModeBtn.MouseButton1Click:Connect(function()
        if State.VoteMode then StopModeVoting() else StartModeVoting() end
        autoModeBtn.Text = State.VoteMode and "ON" or "OFF"
        SetButtonActive(autoModeBtn, State.VoteMode)
    end)
    
    for i = 1, 4 do
        local btn = CreateButton(VIPPanel, "Md" .. i, tostring(i), 108 + (i - 1) * 30, y - 2, 26, 22, function()
            State.ModeIndex = i
            for j = 1, 4 do local b = VIPPanel:FindFirstChild("Md" .. j) if b then SetButtonActive(b, j == i) end end
        end)
        if i == 1 then SetButtonActive(btn, true) end
    end
    
    y = y + 32
    CreateInput(VIPPanel, "MapIn", "Map...", 10, y, 115, function(text) State.MapSearch = text end)
    CreateButton(VIPPanel, "AddM", "+", 130, y + 1, 26, 22, function() local map = FindInList(State.MapSearch, Maps) if map then FireAdmin("AddMap", map) end end)
    CreateButton(VIPPanel, "RemM", "-", 160, y + 1, 26, 22, function() local map = FindInList(State.MapSearch, Maps) if map then FireAdmin("RemoveMap", map) end end)
    
    y = y + 30
    CreateInput(VIPPanel, "ModeIn", "Mode...", 10, y, 115, function(text) State.GamemodeSearch = text end)
    CreateButton(VIPPanel, "SetM", "Set", 130, y + 1, 55, 22, function() local mode = FindInList(State.GamemodeSearch, Modes) if mode then FireAdmin("Gamemode", mode) end end)
    
    MakeDraggable(VIPPanel)
end

local function CreateMainGUI()
    if GUI then SafeCall(function() GUI:Destroy() end) end
    
    GUI = Instance.new("ScreenGui")
    GUI.Name = "EvadeHelper"
    GUI.ResetOnSpawn = false
    SafeCall(function() GUI.Parent = game:GetService("CoreGui") end)
    if not GUI.Parent then GUI.Parent = PlayerGui end
    
    local main = Instance.new("Frame")
    main.Name = "Main"
    main.Size = UDim2.new(0, 180, 0, 280)
    main.Position = UDim2.new(0, 12, 0, 12)
    main.BackgroundColor3 = Color3.fromRGB(22, 22, 25)
    main.Parent = GUI
    Instance.new("UICorner", main).CornerRadius = UDim.new(0, 8)
    Instance.new("UIStroke", main).Color = Color3.fromRGB(50, 180, 100)
    
    CreateLabel(main, "EVADE HELPER V8", 10, 8, 120, 12, Color3.fromRGB(50, 180, 100))
    CreateButton(main, "VIP", "VIP", 130, 6, 28, 20, CreateVIPPanel)
    CreateButton(main, "X", "X", 160, 6, 18, 20, function() main.Visible = false end)
    
    local y = 30
    CreateLabel(main, "FOV", 10, y + 2, 30, 10)
    CreateButton(main, "FOV90", "90", 42, y - 2, 32, 22, function() Config.FOV = 90 SetFOV() UpdateGUI() end)
    CreateButton(main, "FOV120", "120", 78, y - 2, 36, 22, function() Config.FOV = 120 SetFOV() UpdateGUI() end)
    CreateButton(main, "Bright", "Light", 118, y - 2, 52, 22, function() ToggleFullbright() UpdateGUI() end)
    
    y = y + 28
    CreateButton(main, "Border", "Border", 10, y, 50, 22, function() ToggleBorder() UpdateGUI() end)
    CreateButton(main, "Anti", "Anti", 64, y, 40, 22, function() State.AntiNextbot = not State.AntiNextbot if State.AntiNextbot then LoadNPCs() end UpdateGUI() end)
    CreateButton(main, "Farm", "Farm", 108, y, 62, 22, function() State.AutoFarm = not State.AutoFarm if not State.AutoFarm then CurrentTarget = nil end UpdateGUI() end)
    
    y = y + 28
    CreateLabel(main, "Cola", 10, y + 2, 35, 10)
    CreateButton(main, "Fix", "Fix", 45, y - 2, 40, 22, FixCola)
    CreateButton(main, "InfCola", "Infinite", 89, y - 2, 80, 22, function() State.InfiniteCola = not State.InfiniteCola ToggleInfiniteCola(State.InfiniteCola) UpdateGUI() end)
    
    y = y + 28
    CreateLabel(main, "Speed Preset", 10, y + 2, 70, 9)
    CreateButton(main, "ColaLow", "Low", 85, y, 28, 22, function() ColaConfig.Speed = 1.4 UpdateSliderUI(1.4) UpdateGUI() end)
    CreateButton(main, "ColaMed", "Med", 117, y, 28, 22, function() ColaConfig.Speed = 1.6 UpdateSliderUI(1.6) UpdateGUI() end)
    CreateButton(main, "ColaHigh", "Max", 149, y, 21, 22, function() ColaConfig.Speed = 1.8 UpdateSliderUI(1.8) UpdateGUI() end)
    
    y = y + 28
    local holder = Instance.new("Frame")
    holder.Name = "SliderHolder"
    holder.Size = UDim2.new(0, 160, 0, 36)
    holder.Position = UDim2.new(0, 10, 0, y)
    holder.BackgroundTransparency = 1
    holder.Parent = main
    
    SliderLabel = Instance.new("TextLabel")
    SliderLabel.Size = UDim2.new(1, 0, 0, 14)
    SliderLabel.BackgroundTransparency = 1
    SliderLabel.Text = string.format("Speed (%.1fx) • Default: 1.4x", ColaConfig.Speed)
    SliderLabel.TextColor3 = Color3.fromRGB(160, 160, 165)
    SliderLabel.TextSize = 9
    SliderLabel.Font = Enum.Font.Gotham
    SliderLabel.TextXAlignment = Enum.TextXAlignment.Left
    SliderLabel.Parent = holder
    
    SliderTrack = Instance.new("Frame")
    SliderTrack.Size = UDim2.new(1, 0, 0, 4)
    SliderTrack.Position = UDim2.new(0, 0, 0, 18)
    SliderTrack.BackgroundColor3 = Color3.fromRGB(35, 35, 40)
    SliderTrack.Parent = holder
    Instance.new("UICorner", SliderTrack).CornerRadius = UDim.new(0, 2)
    
    local initialPos = (ColaConfig.Speed - SliderMin) / (SliderMax - SliderMin)
    SliderFill = Instance.new("Frame")
    SliderFill.Size = UDim2.new(initialPos, 0, 1, 0)
    SliderFill.BackgroundColor3 = Color3.fromRGB(50, 180, 100)
    SliderFill.Parent = SliderTrack
    Instance.new("UICorner", SliderFill).CornerRadius = UDim.new(0, 2)
    
    SliderThumb = Instance.new("Frame")
    SliderThumb.Size = UDim2.new(0, 10, 0, 10)
    SliderThumb.Position = UDim2.new(initialPos, -5, 0.5, -5)
    SliderThumb.BackgroundColor3 = Color3.fromRGB(50, 180, 100)
    SliderThumb.Parent = SliderTrack
    Instance.new("UICorner", SliderThumb).CornerRadius = UDim.new(1, 0)
    
    local sliderDragging = false
    local function UpdateSliderFromMouse(mousePos)
        if not SliderTrack then return end
        local pos = math.clamp((mousePos.X - SliderTrack.AbsolutePosition.X) / SliderTrack.AbsoluteSize.X, 0, 1)
        local val = math.round((SliderMin + pos * (SliderMax - SliderMin)) * 10) / 10
        val = math.clamp(val, SliderMin, SliderMax)
        ColaConfig.Speed = val
        SliderFill.Size = UDim2.new(pos, 0, 1, 0)
        SliderThumb.Position = UDim2.new(pos, -5, 0.5, -5)
        SliderLabel.Text = string.format("Speed (%.1fx) • Default: 1.4x", val)
        UpdateGUI()
    end
    
    SliderThumb.InputBegan:Connect(function(input) if input.UserInputType == Enum.UserInputType.MouseButton1 then sliderDragging = true end end)
    UserInputService.InputEnded:Connect(function(input) if input.UserInputType == Enum.UserInputType.MouseButton1 then sliderDragging = false end end)
    UserInputService.InputChanged:Connect(function(input) if sliderDragging and input.UserInputType == Enum.UserInputType.MouseMovement then UpdateSliderFromMouse(input.Position) end end)
    SliderTrack.InputBegan:Connect(function(input) if input.UserInputType == Enum.UserInputType.MouseButton1 then UpdateSliderFromMouse(input.Position) end end)
    
    y = y + 40
    CreateLabel(main, "Cola Duration", 10, y + 2, 75, 10)
    local colaDurInput = CreateInput(main, "ColaDur", tostring(ColaConfig.Duration), 90, y, 50, function(text) local num = tonumber(text) if num and num > 0 then ColaConfig.Duration = num end end)
    colaDurInput.Text = tostring(ColaConfig.Duration)
    CreateLabel(main, "s", 143, y + 2, 20, 10)
    
    y = y + 28
    CreateButton(main, "EdgeBoost", "Edge Boost", 10, y, 82, 22, function() State.EdgeBoost = not State.EdgeBoost SetupEdgeBoost() UpdateGUI() end)
    CreateButton(main, "UpFix", "Upside Fix", 96, y, 74, 22, function() State.UpsideDownFix = not State.UpsideDownFix ToggleUpsideDownFix(State.UpsideDownFix) UpdateGUI() end)
    
    MakeDraggable(main)
    UpdateGUI()
end

-- ═══════════════════════════════════════════════════════════════
-- TIMER GUI
-- ═══════════════════════════════════════════════════════════════

local function CreateTimerGUI()
    if TimerGUI then SafeCall(function() TimerGUI:Destroy() end) end
    TimerGUI = Instance.new("ScreenGui")
    TimerGUI.Name = "EvadeTimer"
    TimerGUI.ResetOnSpawn = false
    TimerGUI.Parent = PlayerGui
    
    local container = Instance.new("Frame", TimerGUI)
    container.Name = "Timer"
    container.AnchorPoint = Vector2.new(0.5, 0)
    container.Position = UDim2.new(0.5, 0, 0.02, 0)
    container.Size = UDim2.new(0, 100, 0, 45)
    container.BackgroundTransparency = 0.2
    container.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
    Instance.new("UICorner", container).CornerRadius = UDim.new(0, 8)
    local stroke = Instance.new("UIStroke", container)
    stroke.Color = Color3.fromRGB(60, 60, 65)
    stroke.Thickness = 1.5
    
    StatusLabel = Instance.new("TextLabel", container)
    StatusLabel.Position = UDim2.new(0.5, 0, 0.25, 0)
    StatusLabel.AnchorPoint = Vector2.new(0.5, 0.5)
    StatusLabel.Size = UDim2.new(1, 0, 0.4, 0)
    StatusLabel.BackgroundTransparency = 1
    StatusLabel.Font = Enum.Font.GothamBold
    StatusLabel.Text = "WAIT"
    StatusLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
    StatusLabel.TextSize = 12
    
    TimerLabel = Instance.new("TextLabel", container)
    TimerLabel.Position = UDim2.new(0.5, 0, 0.65, 0)
    TimerLabel.AnchorPoint = Vector2.new(0.5, 0.5)
    TimerLabel.Size = UDim2.new(1, 0, 0.5, 0)
    TimerLabel.BackgroundTransparency = 1
    TimerLabel.Font = Enum.Font.GothamBlack
    TimerLabel.Text = "0:00"
    TimerLabel.TextColor3 = Color3.new(1, 1, 1)
    TimerLabel.TextSize = 18
end

local function UpdateTimer()
    if not CachedGame then CachedGame = Workspace:FindFirstChild("Game") end
    local stats = CachedGame and CachedGame:FindFirstChild("Stats")
    if not stats then
        if TimerLabel then TimerLabel.Text = "0:00" end
        if StatusLabel then StatusLabel.Text = "WAIT" end
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
            TimerLabel.TextColor3 = (roundStarted and timer and timer <= 15) and Color3.fromRGB(255, 80, 80) or Color3.new(1, 1, 1)
        end
        if StatusLabel then
            StatusLabel.Text = roundStarted and "RUNNING" or "WAITING"
            StatusLabel.TextColor3 = roundStarted and Color3.fromRGB(100, 255, 100) or Color3.fromRGB(200, 200, 200)
        end
    end)
end

-- ═══════════════════════════════════════════════════════════════
-- INPUT HANDLING
-- ═══════════════════════════════════════════════════════════════

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    local key = input.KeyCode
    if key == Enum.KeyCode.Space then holdSpace = true LastGroundState = false
    elseif key == Enum.KeyCode.X then holdX = true
    elseif key == Enum.KeyCode.E then Revive()
    elseif key == Enum.KeyCode.R then SelfResurrect()
    elseif key == Enum.KeyCode.Q then holdQ = true
    elseif key == Enum.KeyCode.P then ToggleFullbright() UpdateGUI()
    elseif key == Enum.KeyCode.RightShift then
        if GUI and GUI:FindFirstChild("Main") then
            GUI.Main.Visible = not GUI.Main.Visible
            if VIPPanel then VIPPanel.Visible = false end
        end
    end
end)

UserInputService.InputEnded:Connect(function(input)
    local key = input.KeyCode
    if key == Enum.KeyCode.Space then holdSpace = false LastGroundState = false
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
    table.clear(CachedBots)
    table.clear(CachedItems)
    
    if Humanoid then
        StateChangedConn = Humanoid.StateChanged:Connect(function(old, new)
            if holdSpace and new == Enum.HumanoidStateType.Landed then
                task.defer(function()
                    if holdSpace and Humanoid and Humanoid.Health > 0 then
                        Humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
                    end
                end)
            end
        end)
    end
end

-- ═══════════════════════════════════════════════════════════════
-- PLAYER TRACKING
-- ═══════════════════════════════════════════════════════════════

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
    
    Connections.MainLoop = RunService.RenderStepped:Connect(function()
        local now = tick()
        SuperBhop()
        PreJumpQueue()
        Bounce()
        AirStrafe()
        DoCarry()
        
        if now - lastUpdate >= 0.1 then
            lastUpdate = now
            UpdateRayFilter()
            AntiNextbot()
            AutoFarm()
        end
    end)
end

-- ═══════════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════════

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

print("═══════════════════════════════════════════")
print("✅ EVADE HELPER V8 - TRIMP FRIENDLY!")
print("═══════════════════════════════════════════")
print("✅ Bhop: Responsive + Trimp-friendly")
print("✅ Lower raycast = Better ramp/slope control")
print("✅ No pre-jump on slopes = Clean trimps")
print("═══════════════════════════════════════════")
print("⌨️ CONTROLS:")
print("   Space = Bhop (trimp-friendly)")
print("   X = Bounce + Air Strafe")
print("   Q = Carry | E = Revive | R = Self-res")
print("   P = Fullbright | RightShift = Toggle GUI")
print("═══════════════════════════════════════════")
