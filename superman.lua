-- Services
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

-- Variables
local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
local mouse = player:GetMouse()

local flying = false
local flySpeed = 700
local TOGGLE_KEY = Enum.KeyCode.Q

local workspace = game:GetService("Workspace")
local defaultGravity = workspace.Gravity

local ctrl = {f = 0, b = 0, l = 0, r = 0}
local lastctrl = {f = 0, b = 0, l = 0, r = 0}
local KeyDownFunction = nil
local KeyUpFunction = nil

local currentAnim = nil

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
    if currentAnim then
        currentAnim:Stop(0.1)
        currentAnim = nil
    end
    player.Character.Animate.Disabled = false
    local animtrack = player.Character.Humanoid:GetPlayingAnimationTracks()
    for _, track in pairs(animtrack) do
        track:Stop()
    end
end

-- Get the correct torso part (R15 or R6)
local function GetTorso()
    local char = player.Character
    if not char then return nil end
    return char:FindFirstChild("UpperTorso") or char:FindFirstChild("HumanoidRootPart")
end

-- Toggle Flight
local function toggleFlight()
    flying = not flying

    if flying then
        workspace.Gravity = 0
        local torso = GetTorso()
        if not torso then
            flying = false
            return
        end

        local speed = 0

        local bg = Instance.new("BodyGyro", torso)
        bg.P = 9e4
        bg.maxTorque = Vector3.new(9e9, 9e9, 9e9)
        bg.cframe = torso.CFrame

        local bv = Instance.new("BodyVelocity", torso)
        bv.velocity = Vector3.new(0, 0.1, 0)
        bv.maxForce = Vector3.new(9e9, 9e9, 9e9)

        PlayAnim(10714347256, 4, 0)

        KeyDownFunction = mouse.KeyDown:Connect(function(key)
            if key:lower() == "w" then
                ctrl.f = 1
                PlayAnim(10714177846, 4.65, 0)
            elseif key:lower() == "s" then
                ctrl.b = -1
                PlayAnim(10147823318, 4.11, 0)
            elseif key:lower() == "a" then
                ctrl.l = -1
                PlayAnim(10147823318, 3.55, 0)
            elseif key:lower() == "d" then
                ctrl.r = 1
                PlayAnim(10147823318, 4.81, 0)
            end
        end)

        KeyUpFunction = mouse.KeyUp:Connect(function(key)
            if key:lower() == "w" then
                ctrl.f = 0
                PlayAnim(10714347256, 4, 0)
            elseif key:lower() == "s" then
                ctrl.b = 0
                PlayAnim(10714347256, 4, 0)
            elseif key:lower() == "a" then
                ctrl.l = 0
                PlayAnim(10714347256, 4, 0)
            elseif key:lower() == "d" then
                ctrl.r = 0
                PlayAnim(10714347256, 4, 0)
            end
        end)

        -- Fly loop
        coroutine.wrap(function()
            repeat task.wait()
                player.Character.Humanoid.PlatformStand = true

                if ctrl.l + ctrl.r ~= 0 or ctrl.f + ctrl.b ~= 0 then
                    speed = speed + flySpeed * 0.10
                    if speed > flySpeed then
                        speed = flySpeed
                    end
                elseif not (ctrl.l + ctrl.r ~= 0 or ctrl.f + ctrl.b ~= 0) and speed ~= 0 then
                    speed = speed - flySpeed * 0.10
                    if speed < 0 then
                        speed = 0
                    end
                end

                if (ctrl.l + ctrl.r) ~= 0 or (ctrl.f + ctrl.b) ~= 0 then
                    bv.velocity = ((game.Workspace.CurrentCamera.CoordinateFrame.lookVector * (ctrl.f + ctrl.b)) +
                        ((game.Workspace.CurrentCamera.CoordinateFrame * CFrame.new(ctrl.l + ctrl.r, (ctrl.f + ctrl.b) * 0.2, 0).p) -
                        game.Workspace.CurrentCamera.CoordinateFrame.p)) * speed
                    lastctrl = {f = ctrl.f, b = ctrl.b, l = ctrl.l, r = ctrl.r}
                elseif (ctrl.l + ctrl.r) == 0 and (ctrl.f + ctrl.b) == 0 and speed ~= 0 then
                    bv.velocity = ((game.Workspace.CurrentCamera.CoordinateFrame.lookVector * (lastctrl.f + lastctrl.b)) +
                        ((game.Workspace.CurrentCamera.CoordinateFrame * CFrame.new(lastctrl.l + lastctrl.r, (lastctrl.f + lastctrl.b) * 0.2, 0).p) -
                        game.Workspace.CurrentCamera.CoordinateFrame.p)) * speed
                else
                    bv.velocity = Vector3.new(0, 0.1, 0)
                end

                bg.cframe = game.Workspace.CurrentCamera.CoordinateFrame *
                    CFrame.Angles(-math.rad((ctrl.f + ctrl.b) * 50 * speed / flySpeed), 0, 0)
            until not flying

            ctrl = {f = 0, b = 0, l = 0, r = 0}
            lastctrl = {f = 0, b = 0, l = 0, r = 0}
            speed = 0
            bg:Destroy()
            bv:Destroy()
            player.Character.Humanoid.PlatformStand = false
            workspace.Gravity = defaultGravity
        end)()
    else
        flying = false
        StopAnim()

        if KeyDownFunction then
            KeyDownFunction:Disconnect()
            KeyDownFunction = nil
        end
        if KeyUpFunction then
            KeyUpFunction:Disconnect()
            KeyUpFunction = nil
        end
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

    if flying then
        flying = false
        workspace.Gravity = defaultGravity

        StopAnim()

        if KeyDownFunction then
            KeyDownFunction:Disconnect()
            KeyDownFunction = nil
        end
        if KeyUpFunction then
            KeyUpFunction:Disconnect()
            KeyUpFunction = nil
        end

        ctrl = {f = 0, b = 0, l = 0, r = 0}
        lastctrl = {f = 0, b = 0, l = 0, r = 0}
    end
end)
