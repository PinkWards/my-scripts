if not game:IsLoaded() then game.Loaded:Wait() end

local SCRIPT_VERSION = 33

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

local State = {
    ExchangeUnlocked = false,
}

local Config = {
    FOV = 120
}

-- =====================
-- BHOP VARIABLES
-- =====================
local BhopHold = false
local bhopHoldActive = false
local autoJumpType = "Simulation"
local wallRunJumpEnabled = false
local bhopConnection = nil
local bhopLoaded = false
local characterBhopConn = nil
local Character = LocalPlayer.Character
local currentSpeed = 0
local GROUND_CHECK_DISTANCE = 3.5
local MAX_SLOPE_ANGLE = 45

local accelerationMethod = "Acceleration"
local accelerationValue = -0.5
local autoAccelerationEnabled = false
local maxAcceleration = 3
local minAcceleration = -1
local maxAutoAccelSpeed = 70

-- =====================
-- BOUNCE VARIABLES
-- =====================
local BounceSpeed = 140
local BounceHeight = 90
local BounceMultiplier = 5
local FallSpeedThreshold = 69
local LastFloorMaterial = Enum.Material.Air
local LastPosition = Vector3.new()
local edgeTrimpConnection = nil
local wasInAir = false

-- =====================
-- AIR STRAFE VARIABLES (OPTIMIZED + EMOTE FIX)
-- =====================
local movementInstances = {}
local AirExploitValue = 500
local isCurrentlyEmoting = false

-- =====================
-- SELF REVIVE VARIABLES
-- =====================
local hasRevived = false

-- =====================
-- COLA VARIABLES
-- =====================
local ColaSettings = {
    Speed = 1.4,
    Duration = 3.5,
    Active = false,
    HookInstalled = false,
    OldNamecall = nil,
}

-- =====================
-- CORE VARIABLES
-- =====================
local Humanoid, RootPart, HumanoidRootPart = nil, nil, nil
local GUI, TimerGUI = nil, nil
local TimerLabel, StatusLabel = nil, nil

local holdQ, holdSpace, holdLeftShift = false, false, false

local LastCarry = 0
local LastRayFilterUpdate = 0

local CachedGame = nil
local FullbrightEnabled = false
local SavedLighting = nil
local LastCamera = nil

local Connections = {}
local ExchangeConnections = {}

local LastGCTime = 0
local GC_INTERVAL = 120
local LastCacheCleanup = 0
local CACHE_CLEANUP_INTERVAL = 45

local VEC3_ZERO = Vector3.zero
local VEC2_ZERO = Vector2.new(0, 0)

-- =====================
-- AIR STRAFE ENGINE (ZERO LAG + EMOTE FIX)
-- =====================
local function CacheMovementInstances()
    movementInstances = {}
    pcall(function()
        for _, v in pairs(getgc(true)) do
            if type(v) == "table" and rawget(v, "defaultMovementStats") then
                table.insert(movementInstances, v)
            end
        end
    end)
end

local function ApplyAirExploit()
    if AirExploitValue <= 0 then return end
    pcall(function()
        for _, instance in ipairs(movementInstances) do
            if instance and instance.defaultMovementStats and instance.overrideMovementStats then
                for k, val in pairs(instance.defaultMovementStats) do
                    local lowerK = string.lower(k)
                    if lowerK == "airacceleration" or lowerK == "airstrafeacceleration" then
                        instance.overrideMovementStats[k] = AirExploitValue
                    end
                end
            end
        end
    end)
end

local function RevertAirStatsForSlide()
    pcall(function()
        for _, instance in ipairs(movementInstances) do
            if instance and instance.defaultMovementStats and instance.overrideMovementStats then
                for k, val in pairs(instance.defaultMovementStats) do
                    local lowerK = string.lower(k)
                    if lowerK == "airacceleration" or lowerK == "airstrafeacceleration" then
                        -- Revert to exact game defaults (1 and 182)
                        instance.overrideMovementStats[k] = val
                    end
                end
            end
        end
    end)
end

local function SetupEmoteDetector(character)
    if Connections.EmoteStateConn then Connections.EmoteStateConn:Disconnect() end
    
    -- Listen to the state change event (0 lag, only fires when you actually emote)
    Connections.EmoteStateConn = character:GetAttributeChangedSignal("State"):Connect(function()
        local currentState = character:GetAttribute("State") or ""
        local nowEmoting = string.find(currentState, "Emoting") ~= nil
        
        if nowEmoting ~= isCurrentlyEmoting then
            isCurrentlyEmoting = nowEmoting
            if isCurrentlyEmoting then
                RevertAirStatsForSlide()
            else
                ApplyAirExploit()
            end
        end
    end)
end

-- =====================
-- MOVEMENT MODULE HOOK
-- =====================
pcall(function()
    local m = require(ReplicatedStorage.Modules.Character.CharacterTable.CharacterController.Local.Movement)
    local originalGetStats = m.getStats
    m.getStats = function(s, p)
        local v = originalGetStats(s, p)
        local isBhopActive = bhopHoldActive
        v.BhopEnabled = isBhopActive
        local method = accelerationMethod or "Acceleration"
        local accel = accelerationValue or -0.2

        if isBhopActive and (method == "Ground Acceleration" or method == "Acceleration") then
            if method == "No Acceleration" then
                v.Friction = 5
            elseif method == "Ground Acceleration" then
                v.Friction = s:checkGrounded() and accel or 5
            elseif method == "Acceleration" then
                if autoAccelerationEnabled then
                    if currentSpeed > maxAutoAccelSpeed then
                        v.Friction = maxAcceleration
                    elseif currentSpeed < maxAutoAccelSpeed then
                        v.Friction = minAcceleration
                    else
                        v.Friction = accel
                    end
                else
                    v.Friction = accel
                end
            end
        else
            v.Friction = 5
        end

        return v
    end
end)

-- =====================
-- THEME
-- =====================
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

-- =====================
-- UTILITY FUNCTIONS
-- =====================
local function SafeGetPath(...)
    local args = {...}
    local current = args[1]
    for i = 2, #args do
        if not current then return nil end
        current = current:FindFirstChild(args[i])
    end
    return current
end

local function UpdateRayFilter()
    local now = tick()
    if now - LastRayFilterUpdate < 3.0 then return end
    LastRayFilterUpdate = now
end

local function ForceUpdateRayFilter()
    LastRayFilterUpdate = 0
    UpdateRayFilter()
end

local function SafeCall(func, ...)
    local success, result = pcall(func, ...)
    return success and result
end

local function PeriodicCleanup()
    local now = tick()
    if now - LastCacheCleanup >= CACHE_CLEANUP_INTERVAL then
        LastCacheCleanup = now
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
    for _, conn in pairs(ExchangeConnections) do SafeCall(function() conn:Disconnect() end) end
    table.clear(ExchangeConnections)
    if edgeTrimpConnection then SafeCall(function() edgeTrimpConnection:Disconnect() end) edgeTrimpConnection = nil end
    if bhopConnection then SafeCall(function() bhopConnection:Disconnect() end) bhopConnection = nil end
    if characterBhopConn then SafeCall(function() characterBhopConn:Disconnect() end) characterBhopConn = nil end
    getgenv().var156_upvw_arg1 = nil
    if TimerGUI then SafeCall(function() TimerGUI:Destroy() end) TimerGUI = nil end
    if GUI then SafeCall(function() GUI:Destroy() end) GUI = nil end
    CachedGame = nil
end

-- =====================
-- BOUNCE SYSTEM
-- =====================
local function startBounce()
    if edgeTrimpConnection then edgeTrimpConnection:Disconnect() end
    
    if Character then
        local rootPart = Character:FindFirstChild("HumanoidRootPart")
        local humanoid = Character:FindFirstChild("Humanoid")
        if rootPart then LastPosition = rootPart.Position end
        if humanoid then LastFloorMaterial = humanoid.FloorMaterial end
    end
    
    wasInAir = false
    
    local bounceRayParams = RaycastParams.new()
    bounceRayParams.FilterType = Enum.RaycastFilterType.Blacklist
    bounceRayParams.IgnoreWater = true
    local blacklist = {Character}
    for _, player in ipairs(Players:GetPlayers()) do
        if player.Character then table.insert(blacklist, player.Character) end
    end
    bounceRayParams.FilterDescendantsInstances = blacklist
    
    edgeTrimpConnection = RunService.Heartbeat:Connect(function(dt)
        if not (Character and Humanoid and RootPart) then return end
        
        local isOnGround = false
        local ray = workspace:Raycast(RootPart.Position, Vector3.new(0, -3.5, 0), bounceRayParams)
        if ray then
            isOnGround = true
        end
        
        if isOnGround and wasInAir then
            local vel = RootPart.Velocity
            local hVel = Vector3.new(vel.X, 0, vel.Z)
            local hSpeed = hVel.Magnitude
            
            local preservedSpeed = math.max(hSpeed, BounceSpeed)
            
            if hSpeed > 1 then
                local dir = hVel.Unit
                RootPart.Velocity = Vector3.new(dir.X * preservedSpeed, BounceHeight, dir.Z * preservedSpeed)
            else
                RootPart.Velocity = Vector3.new(vel.X, BounceHeight, vel.Z)
            end
            
            Humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
            wasInAir = false
        elseif not isOnGround then
            wasInAir = true
        end
        
        local CurrentPosition = RootPart.Position
        local Velocity = (CurrentPosition - LastPosition) / dt
        LastPosition = CurrentPosition
        
        local CurrentFloorMaterial = Humanoid.FloorMaterial
        local IsFalling = Humanoid:GetState() == Enum.HumanoidStateType.Freefall or 
                          Humanoid:GetState() == Enum.HumanoidStateType.Jumping
        
        local EdgeDetected = false
        if CurrentFloorMaterial ~= LastFloorMaterial and 
           CurrentFloorMaterial == Enum.Material.Air and 
           not IsFalling then
            EdgeDetected = true
        end
        
        if EdgeDetected and Humanoid:GetState() ~= Enum.HumanoidStateType.Freefall then
            local FallVelocity = Velocity.Y
            if FallVelocity < -FallSpeedThreshold then
                local BounceVel = math.abs(FallVelocity) * BounceMultiplier
                RootPart.Velocity = Vector3.new(RootPart.Velocity.X, BounceVel, RootPart.Velocity.Z)
            end
        end
        
        LastFloorMaterial = CurrentFloorMaterial
    end)
end

local function stopBounce()
    if edgeTrimpConnection then
        edgeTrimpConnection:Disconnect()
        edgeTrimpConnection = nil
    end
end

-- =====================
-- BHOP SYSTEM
-- =====================
local function IsOnGround()
    if not Character or not RootPart or not Humanoid then return false end
    local raycastParams = RaycastParams.new()
    raycastParams.FilterType = Enum.RaycastFilterType.Blacklist
    
    local blacklist = {Character}
    for _, player in ipairs(Players:GetPlayers()) do
        if player.Character then
            table.insert(blacklist, player.Character)
        end
    end
    raycastParams.FilterDescendantsInstances = blacklist
    raycastParams.IgnoreWater = true
    
    local rayOrigin = RootPart.Position
    local rayDirection = Vector3.new(0, -GROUND_CHECK_DISTANCE, 0)
    local raycastResult = workspace:Raycast(rayOrigin, rayDirection, raycastParams)
    if not raycastResult then return false end
    local surfaceNormal = raycastResult.Normal
    local angle = math.deg(math.acos(surfaceNormal:Dot(Vector3.new(0, 1, 0))))
    return angle <= MAX_SLOPE_ANGLE
end

local function updateBhop()
    if not bhopLoaded then return end
    if not Character or not Humanoid then return end
    if RootPart then
        currentSpeed = (RootPart.Velocity * Vector3.new(1, 0, 1)).Magnitude
    end
    if bhopHoldActive then
        if IsOnGround() then
            if autoJumpType == "Realistic" then
                pcall(function()
                    LocalPlayer.PlayerScripts.Events.temporary_events.JumpReact:Fire()
                    task.wait(0.1)
                    LocalPlayer.PlayerScripts.Events.temporary_events.EndJump:Fire()
                end)
            else
                Humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
            end
        end
    end
    if wallRunJumpEnabled then
        local state = Character:GetAttribute("State")
        if state == "Wallrunning" then
            pcall(function()
                LocalPlayer.PlayerScripts.Events.temporary_events.JumpReact:Fire()
                LocalPlayer.PlayerScripts.Events.temporary_events.EndJump:Fire()
            end)
        end
    end
end

local function loadBhop()
    if bhopLoaded then return end
    bhopLoaded = true
    if bhopConnection then bhopConnection:Disconnect() end
    bhopConnection = RunService.Heartbeat:Connect(updateBhop)
end

local function unloadBhop()
    if not bhopLoaded then return end
    bhopLoaded = false
    if bhopConnection then bhopConnection:Disconnect() bhopConnection = nil end
    bhopHoldActive = false
end

local function checkBhopState()
    if bhopHoldActive then
        loadBhop()
    else
        unloadBhop()
    end
end

local function setupJumpButton()
    pcall(function()
        local touchGui = LocalPlayer:WaitForChild("PlayerGui", 5):WaitForChild("TouchGui", 5)
        if not touchGui then return end
        local touchControlFrame = touchGui:WaitForChild("TouchControlFrame", 5)
        if not touchControlFrame then return end
        local jumpButton = touchControlFrame:WaitForChild("JumpButton", 5)
        if not jumpButton then return end
        jumpButton.MouseButton1Down:Connect(function()
            if BhopHold then
                bhopHoldActive = true
                checkBhopState()
            end
        end)
        jumpButton.MouseButton1Up:Connect(function()
            bhopHoldActive = false
            checkBhopState()
        end)
    end)
end

-- =====================
-- SELF REVIVE SYSTEM
-- =====================
local function manualRevive()
    local character = LocalPlayer.Character
    if not character then return end
    local isDowned = character:GetAttribute("Downed")
    if not isDowned then return end
    if not hasRevived then
        hasRevived = true
        pcall(function()
            ReplicatedStorage.Events.Player.ChangePlayerMode:FireServer(true)
        end)
        task.delay(10, function()
            hasRevived = false
        end)
    end
end

-- =====================
-- STATE CHANGED
-- =====================
local function OnStateChanged(old, new)
    if holdLeftShift and (new == Enum.HumanoidStateType.Landed or new == Enum.HumanoidStateType.Running) then
        if RootPart and Humanoid then
            local vel = RootPart.Velocity
            local hVel = Vector3.new(vel.X, 0, vel.Z)
            local hSpeed = hVel.Magnitude
            local preservedSpeed = math.max(hSpeed, BounceSpeed)
            
            if hSpeed > 1 then
                local dir = hVel.Unit
                RootPart.Velocity = Vector3.new(dir.X * preservedSpeed, BounceHeight, dir.Z * preservedSpeed)
            else
                RootPart.Velocity = Vector3.new(vel.X, BounceHeight, vel.Z)
            end
            Humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
        end
    end
end

-- =====================
-- CARRY
-- =====================
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

-- =====================
-- REVIVE OTHERS
-- =====================
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

-- =====================
-- EXCHANGE
-- =====================
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

-- =====================
-- CAMERA FOV
-- =====================
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

-- =====================
-- COLA HOOK
-- =====================
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
        InstallColaHook()
    else
        UninstallColaHook()
    end
end

-- =====================
-- FULLBRIGHT
-- =====================
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

-- =====================
-- TWEEN HELPERS
-- =====================
local TI_FAST = TweenInfo.new(0.12, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local TI_OPEN = TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local TI_SLOW = TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

local function Tween(obj, props, tweenInfo)
    TweenService:Create(obj, tweenInfo or TI_FAST, props):Play()
end

-- =====================
-- GUI HELPERS
-- =====================
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

local function CreateInput(parent, text, yPos, default, callback)
    local lbl = Instance.new("TextLabel", parent)
    lbl.Size = UDim2.new(0, 100, 0, 20) lbl.Position = UDim2.new(0, 10, 0, yPos)
    lbl.BackgroundTransparency = 1 lbl.Text = text lbl.TextColor3 = Color3.fromRGB(140, 140, 160)
    lbl.TextSize = 9 lbl.Font = Enum.Font.Gotham lbl.TextXAlignment = Enum.TextXAlignment.Left
    local inp = Instance.new("TextBox", parent)
    inp.Size = UDim2.new(0, 45, 0, 20) inp.Position = UDim2.new(1, -55, 0, yPos)
    inp.BackgroundColor3 = Color3.fromRGB(25, 25, 35) inp.Text = tostring(default)
    inp.TextColor3 = Color3.fromRGB(180, 180, 200) inp.TextSize = 9 inp.Font = Enum.Font.Gotham inp.BorderSizePixel = 0
    inp.ClearTextOnFocus = false
    Instance.new("UICorner", inp).CornerRadius = UDim.new(0, 4)
    inp.FocusLost:Connect(function() callback(inp.Text) end)
    return inp
end

local function CreateSection(parent, text, yPos)
    local sep = Instance.new("Frame", parent)
    sep.Size = UDim2.new(1, -20, 0, 1) sep.Position = UDim2.new(0, 10, 0, yPos)
    sep.BackgroundColor3 = Color3.fromRGB(40, 40, 60) sep.BorderSizePixel = 0
    local lbl = Instance.new("TextLabel", parent)
    lbl.Size = UDim2.new(0, 150, 0, 14) lbl.Position = UDim2.new(0, 10, 0, yPos + 4)
    lbl.BackgroundTransparency = 1 lbl.Text = text lbl.TextColor3 = Color3.fromRGB(88, 101, 242)
    lbl.TextSize = 9 lbl.Font = Enum.Font.GothamBold lbl.TextXAlignment = Enum.TextXAlignment.Left
    return yPos + 22
end

local function CreateButtonGroup(parent, yPos, options, default, callback)
    local btns = {}
    local bx = 10
    for _, opt in ipairs(options) do
        local b = Instance.new("TextButton", parent)
        b.Size = UDim2.new(0, 75, 0, 20) b.Position = UDim2.new(0, bx, 0, yPos)
        b.BackgroundColor3 = (opt == default) and Color3.fromRGB(40, 40, 70) or Color3.fromRGB(25, 25, 35)
        b.Text = opt b.TextColor3 = (opt == default) and Color3.fromRGB(88, 101, 242) or Color3.fromRGB(150, 150, 170)
        b.TextSize = 9 b.Font = Enum.Font.Gotham b.BorderSizePixel = 0 b.AutoButtonColor = false
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 4)
        b.MouseButton1Click:Connect(function()
            callback(opt)
            for _, bb in ipairs(btns) do
                bb.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
                bb.TextColor3 = Color3.fromRGB(150, 150, 170)
            end
            b.BackgroundColor3 = Color3.fromRGB(40, 40, 70)
            b.TextColor3 = Color3.fromRGB(88, 101, 242)
        end)
        btns[#btns + 1] = b
        bx = bx + 79
    end
    return btns
end

-- =====================
-- MAIN GUI
-- =====================
local GUI_HEIGHT = 380

local function CreateMainGUI()
    if GUI then SafeCall(function() GUI:Destroy() end) end
    GUI = Instance.new("ScreenGui") GUI.Name = "EvadeHelper" GUI.ResetOnSpawn = false GUI.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    SafeCall(function() GUI.Parent = game:GetService("CoreGui") end)
    if not GUI.Parent then GUI.Parent = PlayerGui end
    
    local main = Instance.new("Frame") main.Name = "Main" main.Size = UDim2.new(0, 180, 0, 0) main.Position = UDim2.new(0, 20, 0, 50)
    main.BackgroundColor3 = Color3.fromRGB(15, 15, 22) main.BackgroundTransparency = 0.1 main.BorderSizePixel = 0 main.ClipsDescendants = true main.Parent = GUI
    Instance.new("UICorner", main).CornerRadius = UDim.new(0, 10)
    Instance.new("UIStroke", main).Color = Color3.fromRGB(40, 40, 60)
    
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
    content.BackgroundTransparency = 1 content.ScrollBarThickness = 0 content.BorderSizePixel = 0 content.CanvasSize = UDim2.new(0, 0, 0, 1200) content.Parent = main
    
    local y = 8
    
    -- GENERAL
    y = CreateSection(content, "GENERAL", y)
    CreateToggle(content, "Bright", "Fullbright", y, function(s) if not s then ToggleFullbright() else ToggleFullbright() end end) y = y + 32
    CreateToggle(content, "Exchange", "Exchange", y, function(s) ForceEnableExchange() end) y = y + 36

    -- REVIVE
    y = CreateSection(content, "SELF REVIVE [R]", y)
    y = y + 28

    -- BHOP
    y = CreateSection(content, "BHOP", y)
    CreateToggle(content, "BhopHold", "Bhop Hold (Space)", y, function(s) BhopHold = s if not s then bhopHoldActive = false checkBhopState() end end) y = y + 32
    CreateToggle(content, "WallRun", "WallRun Jump", y, function(s) wallRunJumpEnabled = s end) y = y + 28
    CreateButtonGroup(content, y, {"Simulation", "Realistic"}, autoJumpType, function(v) autoJumpType = v end) y = y + 28
    CreateButtonGroup(content, y, {"No Accel", "Ground", "Accel"}, "Accel", function(v)
        if v == "No Accel" then accelerationMethod = "No Acceleration"
        elseif v == "Ground" then accelerationMethod = "Ground Acceleration"
        else accelerationMethod = "Acceleration" end
    end) y = y + 28
    CreateInput(content, "Friction", y, accelerationValue, function(v) local n = tonumber(v) if n then accelerationValue = n end end) y = y + 26
    CreateToggle(content, "AutoAccel", "Auto Acceleration", y, function(s) autoAccelerationEnabled = s end) y = y + 32

    -- BOUNCE
    y = CreateSection(content, "BOUNCE [Hold LShift]", y)
    CreateInput(content, "Height", y, BounceHeight, function(v) BounceHeight = tonumber(v) or 90 end) y = y + 32

    -- AIR STRAFE
    y = CreateSection(content, "AIR STRAFE (OP)", y)
    CreateInput(content, "Exploit Pwr", y, AirExploitValue, function(v) local n = tonumber(v) if n and n > 0 then AirExploitValue = n if not isCurrentlyEmoting then ApplyAirExploit() end end end) y = y + 32

    -- COLA
    y = CreateSection(content, "CUSTOM COLA", y)
    CreateToggle(content, "InfCola", "Custom Cola", y, function(s) ToggleInfiniteCola(s) end) y = y + 28
    local presetX = 10
    for _, p in ipairs({{n="1.4x",s=1.4},{n="1.8x",s=1.8},{n="2.5x",s=2.5},{n="3.0x",s=3.0}}) do
        local b = Instance.new("TextButton", content)
        b.Size = UDim2.new(0, 35, 0, 20) b.Position = UDim2.new(0, presetX, 0, y)
        b.BackgroundColor3 = Color3.fromRGB(25,25,35) b.Text = p.n b.TextColor3 = Color3.fromRGB(150,150,170)
        b.TextSize = 9 b.Font = Enum.Font.Gotham b.BorderSizePixel = 0 b.AutoButtonColor = false
        Instance.new("UICorner", b).CornerRadius = UDim.new(0,4)
        b.MouseButton1Click:Connect(function() ColaSettings.Speed = p.s end)
        presetX = presetX + 39
    end
    y = y + 26
    CreateInput(content, "Duration", y, ColaSettings.Duration, function(v) local n = tonumber(v) if n and n > 0 then ColaSettings.Duration = n end end) y = y + 32

    -- FOV
    y = CreateSection(content, "FOV", y)
    local fovX = 10
    for _, f in ipairs({{n="70",v=70},{n="90",v=90},{n="120",v=120}}) do
        local b = Instance.new("TextButton", content)
        b.Size = UDim2.new(0, 45, 0, 20) b.Position = UDim2.new(0, fovX, 0, y)
        b.BackgroundColor3 = Color3.fromRGB(25,25,35) b.Text = f.n b.TextColor3 = Color3.fromRGB(150,150,170)
        b.TextSize = 9 b.Font = Enum.Font.Gotham b.BorderSizePixel = 0 b.AutoButtonColor = false
        Instance.new("UICorner", b).CornerRadius = UDim.new(0,4)
        b.MouseButton1Click:Connect(function() Config.FOV = f.v SetFOV() end)
        fovX = fovX + 49
    end
    y = y + 30
    
    content.CanvasSize = UDim2.new(0, 0, 0, y)
    main.Size = UDim2.new(0, 180, 0, 0) main.Visible = true
    Tween(main, {Size = UDim2.new(0, 180, 0, GUI_HEIGHT)}, TI_OPEN)
end

-- =====================
-- TIMER GUI
-- =====================
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

-- =====================
-- INPUT HANDLING
-- =====================
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    local key = input.KeyCode
    if key == Enum.KeyCode.Space then
        holdSpace = true
        if BhopHold then
            bhopHoldActive = true
            checkBhopState()
        end
    elseif key == Enum.KeyCode.E then Revive()
    elseif key == Enum.KeyCode.R then manualRevive()
    elseif key == Enum.KeyCode.Q then holdQ = true
    elseif key == Enum.KeyCode.P then ToggleFullbright()
    elseif key == Enum.KeyCode.LeftShift then
        holdLeftShift = true
        startBounce()
    elseif key == Enum.KeyCode.RightShift then
        if GUI and GUI:FindFirstChild("Main") then
            local m = GUI.Main
            if m.Visible then Tween(m, {Size = UDim2.new(0, 180, 0, 0)}, TI_SLOW) task.delay(0.3, function() m.Visible = false end)
            else m.Visible = true m.Size = UDim2.new(0, 180, 0, 0) Tween(m, {Size = UDim2.new(0, 180, 0, GUI_HEIGHT)}, TI_OPEN) end
        end
    end
end)

UserInputService.InputEnded:Connect(function(input)
    local key = input.KeyCode
    if key == Enum.KeyCode.Space then
        holdSpace = false
        if bhopHoldActive then
            bhopHoldActive = false
            checkBhopState()
        end
    elseif key == Enum.KeyCode.Q then holdQ = false
    elseif key == Enum.KeyCode.LeftShift then 
        holdLeftShift = false
        stopBounce()
    end
end)

-- =====================
-- CHARACTER SETUP
-- =====================
local function SetupCharacter(character)
    if Connections.StateChangedConn then Connections.StateChangedConn:Disconnect() Connections.StateChangedConn = nil end
    
    Character = character
    Humanoid = character:WaitForChild("Humanoid", 5)
    RootPart = character:WaitForChild("HumanoidRootPart", 5)
    HumanoidRootPart = RootPart
    
    ForceUpdateRayFilter()
    hasRevived = false
    
    if Humanoid then 
        Connections.StateChangedConn = Humanoid.StateChanged:Connect(OnStateChanged)
    end
    
    SetupEmoteDetector(character)
    
    setupJumpButton()
    
    if bhopHoldActive then
        task.delay(0.5, function() checkBhopState() end)
    end
end

Players.PlayerAdded:Connect(function(player)
    player.CharacterAdded:Connect(function() task.delay(0.5, ForceUpdateRayFilter) end)
    player.CharacterRemoving:Connect(function() task.delay(0.5, ForceUpdateRayFilter) end)
end)
Players.PlayerRemoving:Connect(function(player) 
    if player == LocalPlayer then CleanupAll()
    else task.delay(0.5, ForceUpdateRayFilter) end 
end)
for _, player in ipairs(Players:GetPlayers()) do
    if player ~= LocalPlayer then
        player.CharacterAdded:Connect(function() task.delay(0.5, ForceUpdateRayFilter) end)
        player.CharacterRemoving:Connect(function() task.delay(0.5, ForceUpdateRayFilter) end)
    end
end

-- =====================
-- MAIN LOOP
-- =====================
local function StartMainLoop()
    if Connections.MainLoop then Connections.MainLoop:Disconnect() end
    if Connections.SlowLoop then Connections.SlowLoop:Disconnect() end
    
    Connections.MainLoop = RunService.RenderStepped:Connect(function()
    end)
    
    local cleanupAccum, airExploitAccum = 0, 0
    Connections.SlowLoop = RunService.Heartbeat:Connect(function(dt)
        if not RootPart or not Humanoid then return end
        
        if holdQ then DoCarry() end
        
        -- Refresh cache every 3 seconds to keep OP Air Strafe alive
        airExploitAccum = airExploitAccum + dt
        if airExploitAccum >= 3.0 then
            airExploitAccum = 0
            CacheMovementInstances()
            if not isCurrentlyEmoting then
                ApplyAirExploit()
            end
        end
        
        cleanupAccum = cleanupAccum + dt
        if cleanupAccum >= 10.0 then 
            cleanupAccum = 0 
            PeriodicCleanup() 
            UpdateRayFilter() 
        end
    end)
end

if LocalPlayer.Character then SetupCharacter(LocalPlayer.Character) end
characterBhopConn = LocalPlayer.CharacterAdded:Connect(SetupCharacter)

Workspace.ChildAdded:Connect(function(child)
    if child.Name == "Game" then
        CachedGame = child task.wait(0.5) ForceUpdateRayFilter() CreateTimerGUI() UpdateTimer()
        hasRevived = false
    end
end)

LocalPlayer.Idled:Connect(function()
    VirtualUser:Button2Down(VEC2_ZERO, Workspace.CurrentCamera.CFrame)
    task.wait(1)
    VirtualUser:Button2Up(VEC2_ZERO, Workspace.CurrentCamera.CFrame)
end)

CreateMainGUI() CreateTimerGUI() UpdateTimer() SetFOV() SetupCameraFOV() ForceUpdateRayFilter() StartMainLoop()
CacheMovementInstances()
ApplyAirExploit()

print("[Evade Helper] V" .. SCRIPT_VERSION .. " loaded! OP Air + Emote Backslide fixed.")
