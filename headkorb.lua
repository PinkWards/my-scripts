local Players = game:GetService("Players")
local player = Players.LocalPlayer

local HEADLESS_MESH_ID = "rbxassetid://1095708"
local KORBLOX_MESH_ID = "rbxassetid://101851696"
local KORBLOX_TEXTURE_ID = "rbxassetid://101851254"
local DARK_GREY_COLOR = Color3.fromRGB(64, 64, 64)
local TINY_SCALE = Vector3.new(0.001, 0.001, 0.001)

local activeConnections = {}
local applied = false

local function cleanupConnections()
    for i = #activeConnections, 1, -1 do
        local conn = activeConnections[i]
        if conn and conn.Connected then
            conn:Disconnect()
        end
        activeConnections[i] = nil
    end
    applied = false
end

local function track(conn)
    activeConnections[#activeConnections + 1] = conn
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

    -- Hide any existing mesh
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

    track(head:GetPropertyChangedSignal("Transparency"):Connect(function()
        if head.Transparency ~= 1 then
            head.Transparency = 1
        end
    end))

    track(head.ChildAdded:Connect(function(child)
        if child:IsA("Decal") then
            task.defer(function()
                if child and child.Parent then
                    child:Destroy()
                end
            end)
        end
    end))

    -- Hide all accessories near head
    local character = head.Parent
    if character then
        task.spawn(function()
            task.wait(0.3)
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
    end
end

local function applyKorbloxR6(character)
    local rightLeg = character:FindFirstChild("Right Leg")
    if not rightLeg or rightLeg:FindFirstChild("KorbloxMesh") then return end

    -- Remove existing meshes
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
    local rightFoot = character:FindFirstChild("RightFoot")

    if not rightUpperLeg or character:FindFirstChild("KorbloxLeg") then return end

    -- Make original parts invisible but keep collision
    rightUpperLeg.Transparency = 1
    if rightLowerLeg then rightLowerLeg.Transparency = 1 end
    if rightFoot then rightFoot.Transparency = 1 end

    -- Keep them invisible permanently
    track(rightUpperLeg:GetPropertyChangedSignal("Transparency"):Connect(function()
        if rightUpperLeg.Transparency ~= 1 then
            rightUpperLeg.Transparency = 1
        end
    end))
    if rightLowerLeg then
        track(rightLowerLeg:GetPropertyChangedSignal("Transparency"):Connect(function()
            if rightLowerLeg.Transparency ~= 1 then
                rightLowerLeg.Transparency = 1
            end
        end))
    end
    if rightFoot then
        track(rightFoot:GetPropertyChangedSignal("Transparency"):Connect(function()
            if rightFoot.Transparency ~= 1 then
                rightFoot.Transparency = 1
            end
        end))
    end

    -- Get the humanoid root to base size scaling
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local legScale = 1
    if humanoid then
        legScale = humanoid.HipHeight / 2.5 -- adjust scale based on character size
    end

    -- Create the Korblox visual part welded to RightUpperLeg
    local korbloxLeg = Instance.new("Part")
    korbloxLeg.Name = "KorbloxLeg"
    korbloxLeg.Size = Vector3.new(1, 1, 1)
    korbloxLeg.Anchored = false
    korbloxLeg.CanCollide = false
    korbloxLeg.CastShadow = false
    korbloxLeg.Massless = true
    korbloxLeg.Color = DARK_GREY_COLOR
    korbloxLeg.Transparency = 0

    local mesh = Instance.new("SpecialMesh")
    mesh.MeshType = Enum.MeshType.FileMesh
    mesh.MeshId = KORBLOX_MESH_ID
    mesh.TextureId = KORBLOX_TEXTURE_ID
    mesh.Scale = Vector3.new(legScale, legScale, legScale)
    mesh.Offset = Vector3.new(0, 0, 0)
    mesh.Parent = korbloxLeg

    -- Weld to upper leg
    local weld = Instance.new("Motor6D")
    weld.Name = "KorbloxWeld"
    weld.Part0 = rightUpperLeg
    weld.Part1 = korbloxLeg
    -- Adjust offset so it lines up correctly with R15 leg position
    weld.C0 = CFrame.new(0, -0.5, 0)
    weld.C1 = CFrame.new(0, 0.5, 0)
    weld.Parent = rightUpperLeg

    korbloxLeg.Parent = character
end

local function waitForRig(character)
    -- Wait until humanoid rig type is known
    local humanoid = character:WaitForChild("Humanoid", 5)
    if not humanoid then return end

    -- For R15 wait for leg parts
    if humanoid.RigType == Enum.HumanoidRigType.R15 then
        character:WaitForChild("RightUpperLeg", 5)
        character:WaitForChild("RightLowerLeg", 5)
        character:WaitForChild("RightFoot", 5)
    else
        character:WaitForChild("Right Leg", 5)
    end
end

local function applyCharacter(character)
    if applied then return end
    applied = true

    waitForRig(character)

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
end

-- Initial apply
if player.Character then
    task.spawn(function()
        applyCharacter(player.Character)
    end)
end

-- Respawn
player.CharacterAdded:Connect(function(character)
    cleanupConnections()
    task.spawn(function()
        applyCharacter(character)
    end)
end)
