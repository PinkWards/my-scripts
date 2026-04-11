local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer

local HEADLESS_MESH_ID = "rbxassetid://1095708"
local KORBLOX_MESH_ID = "rbxassetid://101851696"
local KORBLOX_TEXTURE_ID = "rbxassetid://101851254"
local DARK_GREY_COLOR = Color3.fromRGB(64, 64, 64)
local TINY_SCALE = Vector3.new(0.001, 0.001, 0.001)

local activeConnections = {}
local heartbeatConns = {} -- table instead of single var to avoid overwrite
local applied = false

local function cleanupConnections()
    for i = #activeConnections, 1, -1 do
        local conn = activeConnections[i]
        if conn and conn.Connected then
            conn:Disconnect()
        end
        activeConnections[i] = nil
    end
    for i = #heartbeatConns, 1, -1 do
        local conn = heartbeatConns[i]
        if conn and conn.Connected then
            conn:Disconnect()
        end
        heartbeatConns[i] = nil
    end
    applied = false
end

local function track(conn)
    activeConnections[#activeConnections + 1] = conn
    return conn
end

local function trackHeartbeat(conn)
    heartbeatConns[#heartbeatConns + 1] = conn
    return conn
end

local function removeFace(head)
    local face = head:FindFirstChild("face")
    if face then face:Destroy() end
end

local function applyHeadless(head)
    if not head or head:FindFirstChild("HeadlessMesh") then return end

    head.Transparency = 1
    head.CanCollide = false
    removeFace(head)

    local existingMesh = head:FindFirstChildOfClass("SpecialMesh")
    if existingMesh then
        existingMesh.Scale = TINY_SCALE
    end

    local mesh = Instance.new("SpecialMesh")
    mesh.Name = "HeadlessMesh"
    mesh.MeshType = Enum.MeshType.FileMesh
    mesh.MeshId = HEADLESS_MESH_ID
    mesh.Scale = TINY_SCALE
    mesh.Parent = head

    -- Keep head invisible persistently
    track(head:GetPropertyChangedSignal("Transparency"):Connect(function()
        if head.Transparency ~= 1 then
            head.Transparency = 1
        end
    end))

    -- Remove any decals added to head
    track(head.ChildAdded:Connect(function(child)
        if child:IsA("Decal") then
            task.defer(function()
                if child and child.Parent then
                    child:Destroy()
                end
            end)
        end
    end))

    local character = head.Parent
    if character then
        -- Hide head accessories
        task.spawn(function()
            task.wait(0.3)
            if not character or not character.Parent then return end
            for _, v in pairs(character:GetChildren()) do
                if v:IsA("Accessory") then
                    local handle = v:FindFirstChild("Handle")
                    if handle then
                        local weld = handle:FindFirstChildOfClass("Weld")
                            or handle:FindFirstChildOfClass("Motor6D")
                        if weld then
                            local attachTo = weld.Part0 or weld.Part1
                            if attachTo and attachTo.Name == "Head" then
                                handle.Transparency = 1
                            end
                        end
                    end
                end
            end
        end)

        -- Also catch accessories added AFTER apply (hats loading in late)
        track(character.ChildAdded:Connect(function(child)
            if child:IsA("Accessory") then
                task.wait(0.1)
                local handle = child:FindFirstChild("Handle")
                if handle then
                    local weld = handle:FindFirstChildOfClass("Weld")
                        or handle:FindFirstChildOfClass("Motor6D")
                    if weld then
                        local attachTo = weld.Part0 or weld.Part1
                        if attachTo and attachTo.Name == "Head" then
                            handle.Transparency = 1
                        end
                    end
                end
            end
        end))
    end
end

local function applyKorbloxR6(character)
    local rightLeg = character:FindFirstChild("Right Leg")
    if not rightLeg or rightLeg:FindFirstChild("KorbloxMesh") then return end

    for _, child in ipairs(rightLeg:GetChildren()) do
        if child:IsA("SpecialMesh") or child:IsA("CharacterMesh") then
            child:Destroy()
        end
    end

    rightLeg.Color = DARK_GREY_COLOR

    track(rightLeg:GetPropertyChangedSignal("Color"):Connect(function()
        if rightLeg.Color ~= DARK_GREY_COLOR then
            rightLeg.Color = DARK_GREY_COLOR
        end
    end))

    local korbloxMesh = Instance.new("SpecialMesh")
    korbloxMesh.Name = "KorbloxMesh"
    korbloxMesh.MeshType = Enum.MeshType.FileMesh
    korbloxMesh.MeshId = KORBLOX_MESH_ID
    korbloxMesh.TextureId = KORBLOX_TEXTURE_ID
    korbloxMesh.Scale = Vector3.new(1, 1, 1)
    korbloxMesh.Parent = rightLeg
end

local function applyKorbloxR15(character)
    local rightUpperLeg = character:FindFirstChild("RightUpperLeg")
    local rightLowerLeg = character:FindFirstChild("RightLowerLeg")
    local rightFoot     = character:FindFirstChild("RightFoot")

    if not rightUpperLeg then return end
    if character:FindFirstChild("KorbloxLeg") then return end

    local function hidePart(part)
        if not part then return end
        part.Transparency = 1
        part.CanCollide   = false
        for _, child in ipairs(part:GetChildren()) do
            if child:IsA("SpecialMesh") or child:IsA("Decal") then
                child:Destroy()
            end
        end
    end

    hidePart(rightUpperLeg)
    hidePart(rightLowerLeg)
    hidePart(rightFoot)

    local upperLegMotor = nil
    for _, part in ipairs(character:GetDescendants()) do
        if part:IsA("Motor6D") and part.Part1 == rightUpperLeg then
            upperLegMotor = part
            break
        end
    end

    local korbloxLeg = Instance.new("Part")
    korbloxLeg.Name         = "KorbloxLeg"
    korbloxLeg.Size         = Vector3.new(1, 1, 1)
    korbloxLeg.Anchored     = false
    korbloxLeg.CanCollide   = false
    korbloxLeg.Massless     = true
    korbloxLeg.CastShadow   = true
    korbloxLeg.Color        = DARK_GREY_COLOR
    korbloxLeg.Transparency = 0
    korbloxLeg.Parent       = character

    local mesh = Instance.new("SpecialMesh")
    mesh.Name      = "KorbloxMesh"
    mesh.MeshType  = Enum.MeshType.FileMesh
    mesh.MeshId    = KORBLOX_MESH_ID
    mesh.TextureId = KORBLOX_TEXTURE_ID
    mesh.Scale     = Vector3.new(1, 1, 1)
    mesh.Parent    = korbloxLeg

    local driveMotor = Instance.new("Motor6D")
    driveMotor.Name = "KorbloxDrive"

    if upperLegMotor then
        driveMotor.Part0  = upperLegMotor.Part0
        driveMotor.Part1  = korbloxLeg
        driveMotor.C0     = upperLegMotor.C0
        driveMotor.C1     = CFrame.new(0, 0.5, 0)
        driveMotor.Parent = upperLegMotor.Parent

        -- Mirror animation + keep legs hidden
        trackHeartbeat(RunService.Heartbeat:Connect(function()
            if not character or not character.Parent then return end
            if not upperLegMotor or not upperLegMotor.Parent then return end
            if not driveMotor or not driveMotor.Parent then return end

            driveMotor.C0 = upperLegMotor.C0

            if rightUpperLeg and rightUpperLeg.Transparency ~= 1 then
                rightUpperLeg.Transparency = 1
            end
            if rightLowerLeg and rightLowerLeg.Transparency ~= 1 then
                rightLowerLeg.Transparency = 1
            end
            if rightFoot and rightFoot.Transparency ~= 1 then
                rightFoot.Transparency = 1
            end
        end))
    else
        driveMotor.Part0  = rightUpperLeg
        driveMotor.Part1  = korbloxLeg
        driveMotor.C0     = CFrame.new(0, 0, 0)
        driveMotor.C1     = CFrame.new(0, 0.5, 0)
        driveMotor.Parent = rightUpperLeg

        trackHeartbeat(RunService.Heartbeat:Connect(function()
            if not character or not character.Parent then return end
            if rightUpperLeg and rightUpperLeg.Transparency ~= 1 then
                rightUpperLeg.Transparency = 1
            end
            if rightLowerLeg and rightLowerLeg.Transparency ~= 1 then
                rightLowerLeg.Transparency = 1
            end
            if rightFoot and rightFoot.Transparency ~= 1 then
                rightFoot.Transparency = 1
            end
        end))
    end
end

local function waitForRig(character)
    local humanoid = character:WaitForChild("Humanoid", 10)
    if not humanoid then return end

    if humanoid.RigType == Enum.HumanoidRigType.R15 then
        character:WaitForChild("RightUpperLeg",    10)
        character:WaitForChild("RightLowerLeg",    10)
        character:WaitForChild("RightFoot",        10)
        character:WaitForChild("HumanoidRootPart", 10)
    else
        character:WaitForChild("Right Leg", 10)
    end
end

local function applyCharacter(character)
    -- Guard: don't apply twice to same character
    if applied then return end
    applied = true

    waitForRig(character)

    -- Extra safety: make sure character is still alive/in workspace
    if not character or not character.Parent then
        applied = false
        return
    end

    local head = character:FindFirstChild("Head")
    if head then
        applyHeadless(head)
    end

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if humanoid then
        if humanoid.RigType == Enum.HumanoidRigType.R6 then
            applyKorbloxR6(character)
        elseif humanoid.RigType == Enum.HumanoidRigType.R15 then
            applyKorbloxR15(character)
        end
    end

    -- Reapply headless if character reloads parts mid-session
    track(character.ChildAdded:Connect(function(child)
        if child.Name == "Head" then
            task.wait(0.1)
            applyHeadless(child)
        end
    end))
end

-- Initial load
if player.Character then
    task.spawn(function()
        applyCharacter(player.Character)
    end)
end

-- Every respawn
player.CharacterAdded:Connect(function(character)
    cleanupConnections() -- resets applied = false
    task.spawn(function()
        applyCharacter(character)
    end)
end)
