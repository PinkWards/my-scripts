local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer

local HEADLESS_MESH_ID   = "rbxassetid://1095708"
local KORBLOX_MESH_ID    = "rbxassetid://101851696"
local KORBLOX_TEXTURE_ID = "rbxassetid://101851254"
local DARK_GREY          = Color3.fromRGB(64, 64, 64)
local TINY               = Vector3.new(0.001, 0.001, 0.001)

local connections = {}
local applied = false

local function addConn(c)
    connections[#connections + 1] = c
end

local function cleanupAll()
    for i = #connections, 1, -1 do
        local c = connections[i]
        if c and c.Connected then c:Disconnect() end
        connections[i] = nil
    end
    applied = false
end

-- ══════════════════════════════════════════════
--  HEADLESS — only hides the head part itself
--  does NOT touch any accessories or hair
-- ══════════════════════════════════════════════
local function applyHeadless(character)
    local head = character:WaitForChild("Head", 10)
    if not head then return end

    -- Remove face decal only
    local face = head:FindFirstChild("face")
    if face then face:Destroy() end

    -- Prevent face decal from coming back
    addConn(head.ChildAdded:Connect(function(child)
        if child:IsA("Decal") then
            task.defer(function()
                if child and child.Parent then child:Destroy() end
            end)
        end
    end))

    -- Shrink the existing head mesh so head shape is invisible
    local existing = head:FindFirstChildOfClass("SpecialMesh")
    if existing then
        existing.Scale = TINY
    end

    -- Add tiny headless mesh
    if not head:FindFirstChild("HLMesh") then
        local m = Instance.new("SpecialMesh")
        m.Name     = "HLMesh"
        m.MeshType = Enum.MeshType.FileMesh
        m.MeshId   = HEADLESS_MESH_ID
        m.Scale    = TINY
        m.Parent   = head
    end

    -- Make head invisible
    head.Transparency = 1
    head.CanCollide   = false

    -- Lock head transparency
    addConn(head:GetPropertyChangedSignal("Transparency"):Connect(function()
        if head.Transparency ~= 1 then
            head.Transparency = 1
        end
    end))

    -- Lock LocalTransparencyModifier
    addConn(head:GetPropertyChangedSignal("LocalTransparencyModifier"):Connect(function()
        pcall(function()
            if head.LocalTransparencyModifier ~= 0 then
                head.LocalTransparencyModifier = 0
            end
        end)
    end))
    pcall(function() head.LocalTransparencyModifier = 0 end)
end

-- ══════════════════════════════════════════════
--  KORBLOX — R6
-- ══════════════════════════════════════════════
local function applyKorbloxR6(character)
    local leg = character:WaitForChild("Right Leg", 10)
    if not leg then return end
    if leg:FindFirstChild("KorbloxMesh") then return end

    -- Remove any existing mesh on the leg
    for _, c in ipairs(leg:GetChildren()) do
        if c:IsA("SpecialMesh") then c:Destroy() end
    end

    leg.Color = DARK_GREY

    -- Lock color
    addConn(leg:GetPropertyChangedSignal("Color"):Connect(function()
        if leg.Color ~= DARK_GREY then
            leg.Color = DARK_GREY
        end
    end))

    local m = Instance.new("SpecialMesh")
    m.Name      = "KorbloxMesh"
    m.MeshType  = Enum.MeshType.FileMesh
    m.MeshId    = KORBLOX_MESH_ID
    m.TextureId = KORBLOX_TEXTURE_ID
    m.Scale     = Vector3.new(1, 1, 1)
    m.Offset    = Vector3.new(0, 0, 0)
    m.Parent    = leg
end

-- ══════════════════════════════════════════════
--  KORBLOX — R15
-- ══════════════════════════════════════════════
local function findMotorTo(character, targetPart)
    for _, d in ipairs(character:GetDescendants()) do
        if d:IsA("Motor6D") and d.Part1 == targetPart then
            return d
        end
    end
    return nil
end

local function applyKorbloxR15(character)
    if character:FindFirstChild("KorbloxLeg") then return end

    local upperLeg = character:WaitForChild("RightUpperLeg", 10)
    local lowerLeg = character:WaitForChild("RightLowerLeg", 10)
    local foot     = character:WaitForChild("RightFoot",     10)

    if not upperLeg then return end

    -- Wait for motors to load
    task.wait(0.2)

    local upperMotor = findMotorTo(character, upperLeg)

    -- Hide the real leg parts
    local function hidePart(part)
        if not part then return end
        part.Transparency = 1
        part.CanCollide   = false
        pcall(function() part.LocalTransparencyModifier = 0 end)
    end

    hidePart(upperLeg)
    hidePart(lowerLeg)
    hidePart(foot)

    -- Create the visual Korblox part
    local kPart = Instance.new("Part")
    kPart.Name         = "KorbloxLeg"
    kPart.Size         = Vector3.new(1, 1, 1)
    kPart.Anchored     = false
    kPart.CanCollide   = false
    kPart.Massless     = true
    kPart.Color        = DARK_GREY
    kPart.Transparency = 0
    kPart.Parent       = character

    local kMesh = Instance.new("SpecialMesh")
    kMesh.Name      = "KorbloxMesh"
    kMesh.MeshType  = Enum.MeshType.FileMesh
    kMesh.MeshId    = KORBLOX_MESH_ID
    kMesh.TextureId = KORBLOX_TEXTURE_ID
    kMesh.Scale     = Vector3.new(1, 1, 1)
    kMesh.Offset    = Vector3.new(0, 0, 0)
    kMesh.Parent    = kPart

    -- Weld to same joint as RightUpperLeg
    local weld = Instance.new("Motor6D")
    weld.Name = "KorbloxDrive"

    if upperMotor then
        weld.Part0  = upperMotor.Part0
        weld.Part1  = kPart
        weld.C0     = upperMotor.C0
        weld.C1     = CFrame.new(0, 0.5, 0)
        weld.Parent = upperMotor.Parent
    else
        -- Fallback
        local hrp = character:FindFirstChild("HumanoidRootPart")
        weld.Part0  = hrp or upperLeg
        weld.Part1  = kPart
        weld.C0     = CFrame.new(0.5, -1, 0)
        weld.C1     = CFrame.new(0, 0.5, 0)
        weld.Parent = weld.Part0
    end

    -- Every frame: mirror animation and keep legs hidden
    addConn(RunService.Heartbeat:Connect(function()
        if not character.Parent then return end

        if upperMotor and upperMotor.Parent then
            weld.C0        = upperMotor.C0
            weld.Transform = upperMotor.Transform
        end

        -- Keep legs invisible every frame
        if upperLeg.Parent then
            upperLeg.Transparency = 1
            pcall(function() upperLeg.LocalTransparencyModifier = 0 end)
        end
        if lowerLeg and lowerLeg.Parent then
            lowerLeg.Transparency = 1
            pcall(function() lowerLeg.LocalTransparencyModifier = 0 end)
        end
        if foot and foot.Parent then
            foot.Transparency = 1
            pcall(function() foot.LocalTransparencyModifier = 0 end)
        end
    end))
end

-- ══════════════════════════════════════════════
--  MAIN
-- ══════════════════════════════════════════════
local function applyAll(character)
    if applied then return end
    applied = true

    local humanoid = character:WaitForChild("Humanoid", 10)
    if not humanoid then applied = false; return end

    task.wait(0.1)
    if not character.Parent then applied = false; return end

    -- Headless (just the head, nothing else)
    task.spawn(applyHeadless, character)

    -- Korblox
    if humanoid.RigType == Enum.HumanoidRigType.R6 then
        task.spawn(applyKorbloxR6, character)
    else
        task.spawn(applyKorbloxR15, character)
    end

    -- Handle Head re-added edge case
    addConn(character.ChildAdded:Connect(function(child)
        if child.Name == "Head" then
            task.wait(0.05)
            task.spawn(applyHeadless, character)
        end
    end))
end

local function onCharacter(character)
    cleanupAll()
    task.spawn(applyAll, character)
end

if player.Character then
    onCharacter(player.Character)
end

player.CharacterAdded:Connect(onCharacter)
