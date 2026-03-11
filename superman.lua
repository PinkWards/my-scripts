-- Services
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

-- Variables
local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
local rootPart = character:WaitForChild("HumanoidRootPart")

local flying = false
local flySpeed = 700
local TOGGLE_KEY = Enum.KeyCode.Q

local workspace = game:GetService("Workspace")
local defaultGravity = workspace.Gravity

local ctrl = {f = 0, b = 0, l = 0, r = 0}
local lastctrl = {f = 0, b = 0, l = 0, r = 0}
local keyConnections = {}

local currentAnim = nil
local lastDirection = "none"
local turnTilt = 0
local maxTilt = 45

-- Animation Functions
local function PlayAnim(id, time, speed)
    pcall(function()
        if currentAnim then
            currentAnim:Stop(0.1)
        end

        player.Character.Animate.Disabled = true
        local hum = player.Character.Humanoid
        local animtrack = hum:GetPlayingAnimationTracks()
        for _, track in pairs(animtrack) do
            track:Stop()
        end

        local Anim = Instance.new("Animation")
        Anim.AnimationId = "rbxassetid://" .. id
        local loadanim = hum:LoadAnimation(Anim)
        loadanim:Play()
        loadanim.TimePosition = time
        loadanim:AdjustSpeed(speed)

        currentAnim = loadanim

        loadanim.Stopped:Connect(function()
            player.Character.Animate.Disabled = false
            for _, track in pairs(animtrack) do
                track:Stop()
            end
        end)
    end)
end

local function StopAnim()
    player.Character.Animate.Disabled = false
    local animtrack = player.Character.Humanoid:GetPlayingAnimationTracks()
    for _, track in pairs(animtrack) do
        track:Stop()
    end
end

-- Fly Update
local function updateFly()
    if not flying then return end

    local camera = workspace.CurrentCamera
    local speed = 0

    if not rootPart:FindFirstChild("FlyGyro") then
        local bg = Instance.new("BodyGyro")
        bg.Name = "FlyGyro"
        bg.P = 9e4
        bg.maxTorque = Vector3.new(9e9, 9e9, 9e9)
        bg.CFrame = rootPart.CFrame
        bg.Parent = rootPart

        local bv = Instance.new("BodyVelocity")
        bv.Name = "FlyVelocity"
        bv.Velocity = Vector3.new(0, 0.1, 0)
        bv.MaxForce = Vector3.new(9e9, 9e9, 9e9)
        bv.Parent = rootPart
    end

    local bg = rootPart.FlyGyro
    local bv = rootPart.FlyVelocity

    if ctrl.l + ctrl.r ~= 0 or ctrl.f + ctrl.b ~= 0 then
        speed = speed + flySpeed * 0.15
        if speed > flySpeed then
            speed = flySpeed
        end
    elseif speed ~= 0 then
        speed = speed - flySpeed * 0.08
        if speed < 0 then
            speed = 0
        end
    end

    local targetTilt = 0
    if ctrl.f == 1 then
        if ctrl.l == -1 then
            targetTilt = maxTilt
            if lastDirection ~= "left" then
                lastDirection = "left"
                PlayAnim(10714177846, 4.65, 0)
            end
        elseif ctrl.r == 1 then
            targetTilt = -maxTilt
            if lastDirection ~= "right" then
                lastDirection = "right"
                PlayAnim(10714177846, 4.65, 0)
            end
        else
            lastDirection = "none"
        end
    end

    turnTilt = turnTilt + (targetTilt - turnTilt) * 0.1

    if (ctrl.l + ctrl.r) ~= 0 or (ctrl.f + ctrl.b) ~= 0 then
        bv.Velocity = ((camera.CoordinateFrame.lookVector * (ctrl.f + ctrl.b)) +
            ((camera.CoordinateFrame * CFrame.new(ctrl.l + ctrl.r, (ctrl.f + ctrl.b) * 0.2, 0).p) -
            camera.CoordinateFrame.p)) * speed
        lastctrl = {f = ctrl.f, b = ctrl.b, l = ctrl.l, r = ctrl.r}
    elseif (ctrl.l + ctrl.r) == 0 and (ctrl.f + ctrl.b) == 0 and speed ~= 0 then
        bv.Velocity = ((camera.CoordinateFrame.lookVector * (lastctrl.f + lastctrl.b)) +
            ((camera.CoordinateFrame * CFrame.new(lastctrl.l + lastctrl.r, (lastctrl.f + lastctrl.b) * 0.2, 0).p) -
            camera.CoordinateFrame.p)) * speed
    else
        bv.Velocity = Vector3.new(0, 0.1, 0)
    end

    if ctrl.f == 1 then
        bg.CFrame = camera.CoordinateFrame
            * CFrame.Angles(-math.rad(90), 0, math.rad(turnTilt))
    else
        bg.CFrame = camera.CoordinateFrame
            * CFrame.Angles(-math.rad((ctrl.f + ctrl.b) * 50 * speed / flySpeed), 0, math.rad(turnTilt))
    end
end

-- Toggle Flight
local function toggleFlight()
    flying = not flying

    if flying then
        workspace.Gravity = 0
        humanoid.PlatformStand = true

        PlayAnim(10714347256, 4, 0)

        table.insert(keyConnections, UserInputService.InputBegan:Connect(function(input)
            if UserInputService:GetFocusedTextBox() then return end

            if input.KeyCode == Enum.KeyCode.W then
                ctrl.f = 1
                PlayAnim(10714177846, 4.65, 0)
            elseif input.KeyCode == Enum.KeyCode.S then
                ctrl.b = -1
                if ctrl.f == 0 then
                    PlayAnim(10147823318, 4.11, 0)
                end
            elseif input.KeyCode == Enum.KeyCode.A then
                ctrl.l = -1
                if ctrl.f == 1 then
                    PlayAnim(10714177846, 4.65, 0)
                end
            elseif input.KeyCode == Enum.KeyCode.D then
                ctrl.r = 1
                if ctrl.f == 1 then
                    PlayAnim(10714177846, 4.65, 0)
                end
            end
        end))

        table.insert(keyConnections, UserInputService.InputEnded:Connect(function(input)
            if input.KeyCode == Enum.KeyCode.W then
                ctrl.f = 0
                if ctrl.b == 0 then
                    PlayAnim(10714347256, 4, 0)
                else
                    PlayAnim(10147823318, 4.11, 0)
                end
            elseif input.KeyCode == Enum.KeyCode.S then
                ctrl.b = 0
                if ctrl.f == 1 then
                    PlayAnim(10714177846, 4.65, 0)
                else
                    PlayAnim(10714347256, 4, 0)
                end
            elseif input.KeyCode == Enum.KeyCode.A then
                ctrl.l = 0
                if ctrl.f == 1 then
                    PlayAnim(10714177846, 4.65, 0)
                end
            elseif input.KeyCode == Enum.KeyCode.D then
                ctrl.r = 0
                if ctrl.f == 1 then
                    PlayAnim(10714177846, 4.65, 0)
                end
            end
        end))

        RunService:BindToRenderStep("Fly", Enum.RenderPriority.Camera.Value, updateFly)
    else
        workspace.Gravity = defaultGravity
        humanoid.PlatformStand = false

        StopAnim()

        if rootPart:FindFirstChild("FlyGyro") then
            rootPart.FlyGyro:Destroy()
        end
        if rootPart:FindFirstChild("FlyVelocity") then
            rootPart.FlyVelocity:Destroy()
        end

        ctrl = {f = 0, b = 0, l = 0, r = 0}
        lastctrl = {f = 0, b = 0, l = 0, r = 0}

        for _, connection in pairs(keyConnections) do
            connection:Disconnect()
        end
        table.clear(keyConnections)

        RunService:UnbindFromRenderStep("Fly")
    end
end

-- Input Handler
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode == TOGGLE_KEY then
        toggleFlight()
    end
end)

-- Character Respawn Handler
player.CharacterAdded:Connect(function(newCharacter)
    character = newCharacter
    humanoid = character:WaitForChild("Humanoid")
    rootPart = character:WaitForChild("HumanoidRootPart")

    if flying then
        workspace.Gravity = defaultGravity
        flying = false

        StopAnim()

        ctrl = {f = 0, b = 0, l = 0, r = 0}
        lastctrl = {f = 0, b = 0, l = 0, r = 0}

        for _, connection in pairs(keyConnections) do
            connection:Disconnect()
        end
        table.clear(keyConnections)

        pcall(function()
            RunService:UnbindFromRenderStep("Fly")
        end)
    end
end)
