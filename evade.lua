if not game:IsLoaded() then game.Loaded:Wait() end

local SCRIPT_VERSION = 21

-- Auto-execute removed

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

local BounceSpeed = 75 -- Default speed for the bounce modifier

local ColaSettings = {
    Speed = 1.4,
    Duration = 3.5,
    Active = false,
    HookInstalled = false,
    OldNamecall = nil,
}

local Humanoid, RootPart = nil, nil
local GUI, TimerGUI = nil, nil
local TimerLabel, StatusLabel = nil, nil

local holdQ, holdSpace, holdLeftShift = false, false, false
local keysDown = { W = false, A = false, S = false, D = false }

local LastAntiCheck, LastCarry = 0, 0
local SelfResCD = 0
local LastRayFilterUpdate = 0

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

local LastGCTime = 0
local GC_INTERVAL = 120
local LastCacheCleanup = 0
local CACHE_CLEANUP_INTERVAL = 45

local EdgeRayParams = RaycastParams.new()
EdgeRayParams.FilterType = Enum.RaycastFilterType.Exclude
EdgeRayParams.IgnoreWater = true
EdgeRayParams.RespectCanCollide = true

local VEC3_ZERO = Vector3.zero
local VEC2_ZERO = Vector2.new(0, 0)

local Theme = {
    Background = Color3.fromRGB(15, 15, 20),
    Surface = Color3.fromRGB(22, 22, 30),
    Accent = Color3.fromRGB(88, 101, 242),
    Success = Color3.fromRGB(87, 242, 135),
    Danger = Color3.fromRGB(237, 66, 69),
    TextPrimary = Color3.fromRGB(235, 235, 245),
    TextSecondary = Color3.fromRGB(148, 155, 175),
    TextMuted = Color3.fromRGB(88, 95, 115),
    Border = Color3.fromRGB(40, 40, 55),
}

-- ═══════════════════════════════════════════════════════════════
-- CORE UTILS
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
        local validCount = 0
        for i = 1, #CachedItems do
            local item = CachedItems[i]
            if item and item.object and item.object.Parent then
                validCount = validCount + 1
                if validCount ~= i then CachedItems[validCount] = item end
            end
        end
        for i = validCount + 1, #CachedItems do CachedItems[i] = nil end
        if CachedGame and not CachedGame.Parent then CachedGame = Workspace:FindFirstChild("Game") end
    end
    if now - LastGCTime >= GC_INTERVAL then
        LastGCTime = now
        pcall(function() collectgarbage("step", 50) end)
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
-- MOVEMENT (MACRO BHOP + NEW BOUNCE MODIFIER + SPEED STRAFE)
-- ═══════════════════════════════════════════════════════════════

local bounceConnection = nil
local lastWalkSpeed = nil

local function StartBounceModifier()
    if bounceConnection then return end
    lastWalkSpeed = nil
    bounceConnection = RunService.RenderStepped:Connect(function()
        if not RootPart or not Humanoid then return end
        local velocity = RootPart.AssemblyLinearVelocity
        local speed = velocity.Magnitude
        local newWalkSpeed = 0
        
        if speed > 0.1 then 
            newWalkSpeed = BounceSpeed
        else
            newWalkSpeed = 0
        end
        
        if lastWalkSpeed == nil or newWalkSpeed ~= lastWalkSpeed then
            Humanoid.WalkSpeed = newWalkSpeed
            lastWalkSpeed = newWalkSpeed
        end
    end)
end

local function StopBounceModifier()
    if bounceConnection then
        bounceConnection:Disconnect()
        bounceConnection = nil
    end
    lastWalkSpeed = nil
    if Humanoid then
        Humanoid.WalkSpeed = 16 -- Restores normal walk speed
    end
end

local function OnStateChanged(old, new)
    if new == Enum.HumanoidStateType.Landed then
        if holdLeftShift then
            Humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
        elseif holdSpace then
            Humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
        end
    end
end

local function AirStrafe()
    if not holdLeftShift or not RootPart or not Humanoid then return end
    if Humanoid.Health <= 0 then return end
    
    local state = Humanoid:GetState()
    if state ~= Enum.HumanoidStateType.Freefall and state ~= Enum.HumanoidStateType.Jumping then return end
    
    local cam = Workspace.CurrentCamera
    if not cam then return end
    
    local right = Vector3.new(cam.CFrame.RightVector.X, 0, cam.CFrame.RightVector.Z)
    if right.Magnitude < 0.01 then return end
    right = right.Unit
    
    local wishDir = Vector3.zero
    if keysDown.D then wishDir = wishDir + right end
    if keysDown.A then wishDir = wishDir - right end
    
    if wishDir.Magnitude < 0.01 then return end
    wishDir = wishDir.Unit
    
    local vel = RootPart.AssemblyLinearVelocity
    local hVel = Vector3.new(vel.X, 0, vel.Z)
    
    local gain = 1.5 
    local newHVel = hVel + (wishDir * gain)
    
    if newHVel.Magnitude > 1000 then
        newHVel = newHVel.Unit * 1000
    end
    
    RootPart.AssemblyLinearVelocity = Vector3.new(newHVel.X, vel.Y, newHVel.Z)
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

local function ForceEnableExchange()
    if getgenv().var156_upvw_arg1 then return end
    getgenv().var156_upvw_arg1 = true
    State.ExchangeUnlocked = true
    local player = Players.LocalPlayer
    local function patchExchange()
        local exchangeButton = SafeGetPath(player, "PlayerGui", "Menu", "Views", "Default", "MainMenu", "LeftCorner", "Exchange", "ImageButton")
        local exitButton = SafeGetPath(player, "PlayerGui", "Menu", "Views", "Battlepass", "Exchange", "Center", "Exit", "ImageButton")
        if exchangeButton then
            player.PlayerGui.Menu.Views.Default.MainMenu.LeftCorner.Exchange.Visible = true
            if ExchangeConnections.ExchangeClick then ExchangeConnections.ExchangeClick:Disconnect() end
            ExchangeConnections.ExchangeClick = exchangeButton.MouseButton1Click:Connect(function()
                local bp = player.PlayerGui.Menu.Views:FindFirstChild("Battlepass")
                if bp then bp.Center.Visible = false bp.Exchange.Visible = true end
            end)
        end
        if exitButton then
            if ExchangeConnections.ExitClick then ExchangeConnections.ExitClick:Disconnect() end
            ExchangeConnections.ExitClick = exitButton.MouseButton1Click:Connect(function()
                local bp = player.PlayerGui.Menu.Views:FindFirstChild("Battlepass")
                if bp then repeat task.wait() until bp.Visible == false bp.Exchange.Visible = false bp.Center.Visible = true end
            end)
        end
    end
    patchExchange()
    if ExchangeConnections.DescendantAdded then ExchangeConnections.DescendantAdded:Disconnect() end
    ExchangeConnections.DescendantAdded = player.PlayerGui.DescendantAdded:Connect(function() task.wait(0.1) patchExchange() end)
end

local EdgeConfig = { Boost = 35, MinSpeed = 3, Cooldown = 0.12, MinEdge = 0.5, LastTime = 0, DetectionRange = 2.5, RayDepth = 5 }

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

local function SetupEdgeBoost()
    for _, conn in pairs(EdgeTouchConnections) do SafeCall(function() conn:Disconnect() end) end
    table.clear(EdgeTouchConnections)
    if not State.EdgeBoost then return end
    local character = LocalPlayer.Character
    if not character then return end
    for _, part in ipairs(character:GetDescendants()) do
        if part:IsA("BasePart") then EdgeTouchConnections[#EdgeTouchConnections + 1] = part.Touched:Connect(function(hit)
            if not State.EdgeBoost or not hit or not hit.Parent then return end
            local char = LocalPlayer.Character
            if not char or not Humanoid or not RootPart then return end
            if hit:IsDescendantOf(char) then return end
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
        end) end
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

local function InstallColaHook()
    if ColaSettings.HookInstalled then return end
    local ToolAction = SafeGetPath(ReplicatedStorage, "Events", "Character", "ToolAction")
    local SpeedBoost = SafeGetPath(ReplicatedStorage, "Events", "Character", "SpeedBoost")
    if not ToolAction or not SpeedBoost then return end
    local mt = getrawmetatable(game)
    if not mt then return end
    ColaSettings.OldNamecall = mt.__namecall
    local lastBlock = 0
    setreadonly(mt, false)
    mt.__namecall = newcclosure(function(self, ...)
        local method = getnamecallmethod()
        local args = {...}
        if method == "FireServer" and self == ToolAction and args[1] == 0 and args[2] == 20 then
            if ColaSettings.Active then
                local now = tick()
                if now - lastBlock < 0.5 then return nil end
                lastBlock = now
                task.spawn(function()
                    task.wait(0.3)
                    if ColaSettings.Active then
                        firesignal(SpeedBoost.OnClientEvent, "Cola", ColaSettings.Speed, ColaSettings.Duration, Color3.fromRGB(199, 141, 93))
                    end
                end)
                return nil
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

local function ToggleInfiniteCola(state)
    if state then
        ColaSettings.Active = true
        State.InfiniteCola = true
        InstallColaHook()
    else
        State.InfiniteCola = false
        UninstallColaHook()
    end
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

-- ═══════════════════════════════════════════════════════════════
-- GUI (COMPACT + COLA SETTINGS)
-- ═══════════════════════════════════════════════════════════════

local TI_FAST = TweenInfo.new(0.12, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local TI_OPEN = TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local TI_SLOW = TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

local function Tween(obj, props, tweenInfo)
    TweenService:Create(obj, tweenInfo or TI_FAST, props):Play()
end

local function MakeDraggable(frame)
    local dragging, dragStart, startPos = false, nil, nil
    local dragArea = Instance.new("Frame") dragArea.Name = "DragArea" dragArea.Size = UDim2.new(1, 0, 0, 30) dragArea.BackgroundTransparency = 1 dragArea.ZIndex = 10 dragArea.Parent = frame
    dragArea.InputBegan:Connect(function(input) if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = true dragStart = input.Position startPos = frame.Position end end)
    dragArea.InputEnded:Connect(function(input) if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end end)
    Connections["Drag_" .. frame.Name] = UserInputService.InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            local delta = input.Position - dragStart
            frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)
end

local function CreateToggle(parent, name, text, yPos, callback)
    local btn = Instance.new("TextButton")
    btn.Name = name btn.Size = UDim2.new(1, -20, 0, 28) btn.Position = UDim2.new(0, 10, 0, yPos)
    btn.BackgroundColor3 = Color3.fromRGB(25, 25, 35) btn.Text = "" btn.AutoButtonColor = false btn.BorderSizePixel = 0 btn.Parent = parent
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
    
    local label = Instance.new("TextLabel") label.Size = UDim2.new(1, -40, 1, 0) label.Position = UDim2.new(0, 10, 0, 0)
    label.BackgroundTransparency = 1 label.Text = text label.TextColor3 = Color3.fromRGB(180, 180, 200) label.TextSize = 11
    label.Font = Enum.Font.Gotham label.TextXAlignment = Enum.TextXAlignment.Left label.Parent = btn
    
    local dot = Instance.new("Frame") dot.Size = UDim2.new(0, 8, 0, 8) dot.Position = UDim2.new(1, -18, 0.5, -4)
    dot.BackgroundColor3 = Color3.fromRGB(80, 80, 100) dot.BorderSizePixel = 0 dot.Parent = btn
    Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)
    
    btn.MouseButton1Click:Connect(function()
        local active = not btn:GetAttribute("Toggled")
        btn:SetAttribute("Toggled", active)
        if active then
            Tween(btn, {BackgroundColor3 = Color3.fromRGB(40, 40, 70)})
            Tween(dot, {BackgroundColor3 = Color3.fromRGB(88, 101, 242)})
        else
            Tween(btn, {BackgroundColor3 = Color3.fromRGB(25, 25, 35)})
            Tween(dot, {BackgroundColor3 = Color3.fromRGB(80, 80, 100)})
        end
        callback(active)
    end)
    return btn
end

local function CreateMainGUI()
    if GUI then SafeCall(function() GUI:Destroy() end) end
    GUI = Instance.new("ScreenGui") GUI.Name = "EvadeHelper" GUI.ResetOnSpawn = false GUI.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    SafeCall(function() GUI.Parent = game:GetService("CoreGui") end)
    if not GUI.Parent then GUI.Parent = PlayerGui end
    
    local main = Instance.new("Frame") main.Name = "Main" main.Size = UDim2.new(0, 180, 0, 0) main.Position = UDim2.new(0, 20, 0, 50)
    main.BackgroundColor3 = Color3.fromRGB(15, 15, 22) main.BackgroundTransparency = 0.1 main.BorderSizePixel = 0 main.ClipsDescendants = true main.Parent = GUI
    Instance.new("UICorner", main).CornerRadius = UDim.new(0, 10)
    local stroke = Instance.new("UIStroke", main) stroke.Color = Color3.fromRGB(40, 40, 60) stroke.Thickness = 1
    
    local title = Instance.new("TextLabel") title.Size = UDim2.new(1, 0, 0, 30) title.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
    title.Text = "  EVADE // V" .. SCRIPT_VERSION title.TextColor3 = Color3.fromRGB(88, 101, 242) title.TextSize = 11 title.Font = Enum.Font.GothamBold
    title.TextXAlignment = Enum.TextXAlignment.Left title.BorderSizePixel = 0 title.Parent = main
    Instance.new("UICorner", title).CornerRadius = UDim.new(0, 10)
    local fix = Instance.new("Frame", title) fix.Size = UDim2.new(1,0,0,10) fix.Position = UDim2.new(0,0,1,-10) fix.BackgroundColor3 = title.BackgroundColor3 fix.BorderSizePixel = 0
    
    local closeBtn = Instance.new("TextButton", title) closeBtn.Size = UDim2.new(0, 30, 0, 30) closeBtn.Position = UDim2.new(1, -30, 0, 0)
    closeBtn.BackgroundTransparency = 1 closeBtn.Text = "X" closeBtn.TextColor3 = Color3.fromRGB(200,200,220) closeBtn.TextSize = 12 closeBtn.Font = Enum.Font.GothamBold closeBtn.BorderSizePixel = 0
    closeBtn.MouseButton1Click:Connect(function()
        Tween(main, {Size = UDim2.new(0, 180, 0, 0)}, TI_SLOW) task.delay(0.3, function() main.Visible = false end)
    end)
    
    local content = Instance.new("ScrollingFrame") content.Size = UDim2.new(1, 0, 1, -30) content.Position = UDim2.new(0, 0, 0, 30)
    content.BackgroundTransparency = 1 content.ScrollBarThickness = 0 content.BorderSizePixel = 0 content.CanvasSize = UDim2.new(0, 0, 0, 350) content.Parent = main
    
    local y = 8
    CreateToggle(content, "Bright", "Fullbright", y, function(s) if not s then ToggleFullbright() else ToggleFullbright() end end) y = y + 32
    CreateToggle(content, "Border", "No Borders", y, function(s) ToggleBorder() end) y = y + 32
    CreateToggle(content, "Anti", "Anti-Nextbot", y, function(s) State.AntiNextbot = s if s then LoadNPCs() end end) y = y + 32
    CreateToggle(content, "Farm", "Auto Farm", y, function(s) State.AutoFarm = s if not s then CurrentTarget = nil end end) y = y + 32
    CreateToggle(content, "EdgeBoost", "Edge Boost", y, function(s) State.EdgeBoost = s SetupEdgeBoost() end) y = y + 32
    CreateToggle(content, "UpFix", "Upside Fix", y, function(s) State.UpsideDownFix = s ToggleUpsideDownFix(s) end) y = y + 32
    CreateToggle(content, "InfCola", "Custom Cola", y, function(s) ToggleInfiniteCola(s) end) y = y + 32
    CreateToggle(content, "Exchange", "Exchange", y, function(s) ForceEnableExchange() end) y = y + 36
    
    -- Cola Speed Presets
    local presetY = y
    local presetX = 10
    local presets = {
        {name = "1.4x", speed = 1.4}, {name = "1.8x", speed = 1.8}, {name = "2.5x", speed = 2.5}, {name = "3.0x", speed = 3.0}
    }
    for _, p in ipairs(presets) do
        local b = Instance.new("TextButton", content)
        b.Size = UDim2.new(0, 35, 0, 20) b.Position = UDim2.new(0, presetX, 0, presetY)
        b.BackgroundColor3 = Color3.fromRGB(25,25,35) b.Text = p.name b.TextColor3 = Color3.fromRGB(150,150,170)
        b.TextSize = 9 b.Font = Enum.Font.Gotham b.BorderSizePixel = 0 b.AutoButtonColor = false
        Instance.new("UICorner", b).CornerRadius = UDim.new(0,4)
        b.MouseButton1Click:Connect(function() ColaSettings.Speed = p.speed end)
        presetX = presetX + 39
    end
    y = y + 26
    
    -- Cola Duration Input
    local durInput = Instance.new("TextBox", content)
    durInput.Size = UDim2.new(0, 40, 0, 20) durInput.Position = UDim2.new(0, 10, 0, y)
    durInput.BackgroundColor3 = Color3.fromRGB(25,25,35) durInput.Text = tostring(ColaSettings.Duration)
    durInput.TextColor3 = Color3.fromRGB(180,180,200) durInput.PlaceholderText = "Sec"
    durInput.TextSize = 9 durInput.Font = Enum.Font.Gotham durInput.BorderSizePixel = 0
    Instance.new("UICorner", durInput).CornerRadius = UDim.new(0,4)
    durInput.FocusLost:Connect(function() local n = tonumber(durInput.Text) if n and n > 0 then ColaSettings.Duration = n end end)

    local durLabel = Instance.new("TextLabel", content)
    durLabel.Size = UDim2.new(0, 80, 0, 20) durLabel.Position = UDim2.new(0, 55, 0, y)
    durLabel.BackgroundTransparency = 1 durLabel.Text = "Cola Duration" durLabel.TextColor3 = Color3.fromRGB(100,100,120)
    durLabel.TextSize = 9 durLabel.Font = Enum.Font.Gotham durLabel.TextXAlignment = Enum.TextXAlignment.Left
    y = y + 30
    
    -- FOV Buttons
    local fovLabel = Instance.new("TextLabel", content) fovLabel.Size = UDim2.new(0, 40, 0, 20) fovLabel.Position = UDim2.new(0, 10, 0, y)
    fovLabel.BackgroundTransparency = 1 fovLabel.Text = "FOV:" fovLabel.TextColor3 = Color3.fromRGB(150,150,170) fovLabel.TextSize = 10 fovLabel.Font = Enum.Font.Gotham
    
    local function CreateFovBtn(name, text, xPos, val)
        local b = Instance.new("TextButton", content) b.Name = name b.Size = UDim2.new(0, 40, 0, 20) b.Position = UDim2.new(0, xPos, 0, y)
        b.BackgroundColor3 = Color3.fromRGB(25,25,35) b.Text = text b.TextColor3 = Color3.fromRGB(150,150,170) b.TextSize = 10 b.Font = Enum.Font.Gotham b.BorderSizePixel = 0 b.AutoButtonColor = false
        Instance.new("UICorner", b).CornerRadius = UDim.new(0,4)
        b.MouseButton1Click:Connect(function() Config.FOV = val SetFOV() end)
    end
    CreateFovBtn("F90", "90", 55, 90)
    CreateFovBtn("F120", "120", 100, 120)
    
    content.CanvasSize = UDim2.new(0, 0, 0, y + 50)
    MakeDraggable(main)
    main.Size = UDim2.new(0, 180, 0, 0) main.Visible = true
    Tween(main, {Size = UDim2.new(0, 180, 0, 310)}, TI_OPEN)
end

local function CreateTimerGUI()
    if TimerGUI then SafeCall(function() TimerGUI:Destroy() end) end
    TimerGUI = Instance.new("ScreenGui") TimerGUI.Name = "EvadeTimer" TimerGUI.ResetOnSpawn = false TimerGUI.Parent = PlayerGui
    local container = Instance.new("Frame", TimerGUI) container.Name = "Timer" container.AnchorPoint = Vector2.new(1, 1)
    container.Position = UDim2.new(1, -5, 1, -5) container.Size = UDim2.new(0, 80, 0, 35) container.BackgroundTransparency = 1 container.BorderSizePixel = 0
    StatusLabel = Instance.new("TextLabel", container) StatusLabel.Position = UDim2.new(0.5, 0, 0, 0) StatusLabel.AnchorPoint = Vector2.new(0.5, 0)
    StatusLabel.Size = UDim2.new(1, 0, 0, 10) StatusLabel.BackgroundTransparency = 1 StatusLabel.Font = Enum.Font.GothamBold
    StatusLabel.Text = "WAITING" StatusLabel.TextColor3 = Color3.fromRGB(0, 0, 0) StatusLabel.TextSize = 8
    StatusLabel.TextStrokeTransparency = 0.8 StatusLabel.TextStrokeColor3 = Color3.fromRGB(255, 255, 255)
    TimerLabel = Instance.new("TextLabel", container) TimerLabel.Position = UDim2.new(0.5, 0, 0, 10) TimerLabel.AnchorPoint = Vector2.new(0.5, 0)
    TimerLabel.Size = UDim2.new(1, 0, 0, 25) TimerLabel.BackgroundTransparency = 1 TimerLabel.Font = Enum.Font.Code
    TimerLabel.Text = "0:00" TimerLabel.TextColor3 = Color3.fromRGB(0, 0, 0) TimerLabel.TextSize = 24
    TimerLabel.TextStrokeTransparency = 0.8 TimerLabel.TextStrokeColor3 = Color3.fromRGB(255, 255, 255)
end

local function UpdateTimer()
    if not CachedGame then CachedGame = Workspace:FindFirstChild("Game") end
    local stats = CachedGame and CachedGame:FindFirstChild("Stats")
    if not stats then if TimerLabel then TimerLabel.Text = "0:00" end if StatusLabel then StatusLabel.Text = "WAITING" end return end
    if Connections.Timer then Connections.Timer:Disconnect() end
    Connections.Timer = stats:GetAttributeChangedSignal("Timer"):Connect(function()
        local timer = stats:GetAttribute("Timer") local roundStarted = stats:GetAttribute("RoundStarted")
        if TimerLabel then local m = math.floor((timer or 0) / 60) local s = (timer or 0) % 60 TimerLabel.Text = string.format("%d:%02d", m, s)
            TimerLabel.TextColor3 = (roundStarted and timer and timer <= 15) and Theme.Danger or Theme.TextPrimary end
        if StatusLabel then StatusLabel.Text = roundStarted and "RUNNING" or "WAITING" StatusLabel.TextColor3 = roundStarted and Theme.Success or Theme.TextMuted end
    end)
end

-- ═══════════════════════════════════════════════════════════════
-- INPUT
-- ═══════════════════════════════════════════════════════════════

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    local key = input.KeyCode
    if key == Enum.KeyCode.Space then holdSpace = true
    elseif key == Enum.KeyCode.E then Revive()
    elseif key == Enum.KeyCode.R then SelfResurrect()
    elseif key == Enum.KeyCode.Q then holdQ = true
    elseif key == Enum.KeyCode.P then ToggleFullbright()
    elseif key == Enum.KeyCode.LeftShift then
        holdLeftShift = true
        StartBounceModifier()
    elseif key == Enum.KeyCode.RightShift then
        if GUI and GUI:FindFirstChild("Main") then
            local m = GUI.Main
            if m.Visible then Tween(m, {Size = UDim2.new(0, 180, 0, 0)}, TI_SLOW) task.delay(0.3, function() m.Visible = false end)
            else m.Visible = true m.Size = UDim2.new(0, 180, 0, 0) Tween(m, {Size = UDim2.new(0, 180, 0, 310)}, TI_OPEN) end
        end
    end
    if key == Enum.KeyCode.W then keysDown.W = true end
    if key == Enum.KeyCode.A then keysDown.A = true end
    if key == Enum.KeyCode.S then keysDown.S = true end
    if key == Enum.KeyCode.D then keysDown.D = true end
end)

UserInputService.InputEnded:Connect(function(input)
    local key = input.KeyCode
    if key == Enum.KeyCode.Space then holdSpace = false
    elseif key == Enum.KeyCode.Q then holdQ = false
    elseif key == Enum.KeyCode.LeftShift then 
        holdLeftShift = false 
        StopBounceModifier()
    end
    if key == Enum.KeyCode.W then keysDown.W = false end
    if key == Enum.KeyCode.A then keysDown.A = false end
    if key == Enum.KeyCode.S then keysDown.S = false end
    if key == Enum.KeyCode.D then keysDown.D = false end
end)

-- ═══════════════════════════════════════════════════════════════
-- CHARACTER SETUP & LOOPS
-- ═══════════════════════════════════════════════════════════════

local function SetupCharacter(character)
    if Connections.StateChangedConn then Connections.StateChangedConn:Disconnect() Connections.StateChangedConn = nil end
    
    Humanoid = character:WaitForChild("Humanoid", 5)
    RootPart = character:WaitForChild("HumanoidRootPart", 5)
    ForceUpdateRayFilter()
    SetupEdgeBoost()
    CurrentTarget, FarmStart = nil, 0
    
    if Humanoid then 
        Connections.StateChangedConn = Humanoid.StateChanged:Connect(OnStateChanged)
    end
    
    -- If already holding shift when character spawns, restart modifier
    if holdLeftShift then
        StartBounceModifier()
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

local function StartMainLoop()
    if Connections.MainLoop then Connections.MainLoop:Disconnect() end
    if Connections.SlowLoop then Connections.SlowLoop:Disconnect() end
    
    Connections.MainLoop = RunService.RenderStepped:Connect(function()
        AirStrafe()
    end)
    
    local slowAccum, edgeAccum, cleanupAccum = 0, 0, 0
    Connections.SlowLoop = RunService.Heartbeat:Connect(function(dt)
        if State.EdgeBoost then
            edgeAccum = edgeAccum + dt
            if edgeAccum >= 0.06 then edgeAccum = 0 ReactiveEdgeBoost() end
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
        if cleanupAccum >= 10.0 then cleanupAccum = 0 PeriodicCleanup() end
    end)
end

if LocalPlayer.Character then SetupCharacter(LocalPlayer.Character) end
LocalPlayer.CharacterAdded:Connect(SetupCharacter)

Workspace.ChildAdded:Connect(function(child)
    if child.Name == "Game" then
        CachedGame = child task.wait(0.5) ForceUpdateRayFilter() CreateTimerGUI() UpdateTimer()
        NPCLoaded = false CurrentTarget, FarmStart = nil, 0
        table.clear(CachedBots) table.clear(CachedItems)
        if State.UpsideDownFix then State.UpsideDownFix = false ToggleUpsideDownFix(false) end
    end
end)

LocalPlayer.Idled:Connect(function()
    VirtualUser:Button2Down(VEC2_ZERO, Workspace.CurrentCamera.CFrame)
    task.wait(1)
    VirtualUser:Button2Up(VEC2_ZERO, Workspace.CurrentCamera.CFrame)
end)

CreateMainGUI() CreateTimerGUI() UpdateTimer() SetFOV() SetupCameraFOV() LoadNPCs() ForceUpdateRayFilter() StartMainLoop()

print("[Evade Helper] V" .. SCRIPT_VERSION .. " loaded! Macro Bhop + WalkSpeed Bounce + Air Strafe + Compact GUI!")
