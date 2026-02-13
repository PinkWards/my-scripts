local Players = game:GetService("Players")

local player = Players.LocalPlayer
local HEADLESS_MESH_ID = "rbxassetid://1095708"
local KORBLOX_MESH_ID = "rbxassetid://101851696"
local KORBLOX_TEXTURE_ID = "rbxassetid://101851254"
local DARK_GREY_COLOR = Color3.fromRGB(64, 64, 64)
local TINY_SCALE = Vector3.new(0.001, 0.001, 0.001)
local UNIT_SCALE = Vector3.one
local KORBLOX_WELD_OFFSET = CFrame.new(0, -0.8, 0)

-- OPT: store connections so we can clean them up on respawn (prevents memory leak)
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

    local mesh = Instance.new("SpecialMesh")
    mesh.Name = "HeadlessMesh"
    mesh.MeshType = Enum.MeshType.FileMesh
    mesh.MeshId = HEADLESS_MESH_ID
    mesh.Scale = TINY_SCALE
    mesh.Parent = head

    -- OPT: tracked connections (cleaned up on respawn)
    track(head:GetPropertyChangedSignal("Transparency"):Connect(function()
        if head.Transparency ~= 1 then
            head.Transparency = 1
        end
    end))

    track(head.ChildAdded:Connect(function(child)
        if child.Name == "face" and child:IsA("Decal") then
            child:Destroy()
        end
    end))
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

    -- OPT: tracked connection
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
    korbloxMesh.Scale = UNIT_SCALE
    korbloxMesh.Parent = rightLeg
end

local function applyKorbloxR15(character)
    local rightUpperLeg = character:FindFirstChild("RightUpperLeg")
    if not rightUpperLeg or character:FindFirstChild("KorbloxLeg") then return end

    rightUpperLeg.Transparency = 1
    local rightLowerLeg = character:FindFirstChild("RightLowerLeg")
    local rightFoot = character:FindFirstChild("RightFoot")
    if rightLowerLeg then rightLowerLeg.Transparency = 1 end
    if rightFoot then rightFoot.Transparency = 1 end

    local korbloxLeg = Instance.new("Part")
    korbloxLeg.Name = "KorbloxLeg"
    korbloxLeg.Size = Vector3.new(1, 2, 1)
    korbloxLeg.Anchored = false
    korbloxLeg.CanCollide = false
    korbloxLeg.Color = DARK_GREY_COLOR

    local mesh = Instance.new("SpecialMesh")
    mesh.MeshType = Enum.MeshType.FileMesh
    mesh.MeshId = KORBLOX_MESH_ID
    mesh.TextureId = KORBLOX_TEXTURE_ID
    mesh.Scale = UNIT_SCALE
    mesh.Parent = korbloxLeg

    local weld = Instance.new("Weld")
    weld.Part0 = rightUpperLeg
    weld.Part1 = korbloxLeg
    weld.C0 = KORBLOX_WELD_OFFSET
    weld.Parent = korbloxLeg

    -- OPT: parent last (single replication event instead of multiple property changes while parented)
    korbloxLeg.Parent = character
end

local function applyCharacter(character)
    if applied then return end
    applied = true

    -- OPT: removed task.wait(0.2) — WaitForChild("Head") in CharacterAdded already ensures loading
    -- If called from initial check, head exists already

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

-- Initial application
if player.Character then
    applyCharacter(player.Character)
end

-- Respawn handling
player.CharacterAdded:Connect(function(character)
    -- OPT: clean up old connections to prevent memory leak
    cleanupConnections()
    character:WaitForChild("Head")
    applyCharacter(character)
end)
