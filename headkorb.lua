local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer

local HEADLESS_MESH_ID = "rbxassetid://1095708"
local KORBLOX_MESH_ID = "rbxassetid://101851696"
local KORBLOX_TEXTURE_ID = "rbxassetid://101851254"
local DARK_GREY_COLOR = Color3.fromRGB(64, 64, 64)
local TINY_SCALE = Vector3.new(0.001, 0.001, 0.001)

-- The exact scale the real Korblox leg uses on a default R15 avatar
-- These are the base values that get multiplied by your body scales
local KORBLOX_BASE_SCALE = Vector3.new(1, 1, 1)

-- Fixed Y placement: matches the exact real Korblox leg position
-- relative to LowerTorso bottom edge, same as the catalog item
local KORBLOX_FIXED_Y = -0.55

local activeConnections = {}
local heartbeatConns = {}
local applied = false

local function getScaleProp(humanoid, propName)
    local success, val = pcall(function()
        return humanoid[propName]
    end)
    if success then
        local num = tonumber(val)
        if num then
            return math.max(num, 0.5)
        end
        if typeof(val) == "Instance" and val:IsA("NumberValue") then
            return math.max(val.Value, 0.5)
        end
    end
    return 1.0
end

-- Returns the mesh scale based on your actual body scales
local function getKorbloxScale(humanoid)
    local wScale = getScaleProp(humanoid, "BodyWidthScale")
    local hScale = getScaleProp(humanoid, "BodyHeightScale")
    local dScale = getScaleProp(humanoid, "BodyDepthScale")
    return Vector3.new(
        KORBLOX_BASE_SCALE.X * wScale,
        KORBLOX_BASE_SCALE.Y * hScale,
        KORBLOX_BASE_SCALE.Z * dScale
    )
end

-- Returns the fixed Y offset anchored to the LowerTorso bottom
-- so it always sits exactly where the real Korblox leg sits
local function getKorbloxOffset(character, humanoid)
    local rigType = humanoid.RigType

    if rigType == Enum.HumanoidRigType.R15 then
        local lowerTorso = character:FindFirstChild("LowerTorso")
        local upperLeg   = character:FindFirstChild("RightUpperLeg")
        local lowerLeg   = character:FindFirstChild("RightLowerLeg")
        local foot       = character:FindFirstChild("RightFoot")

        if not upperLeg then
            return Vector3.new(0, KORBLOX_FIXED_Y, 0)
        end

        -- Total leg height so we can center the mesh on the leg column
        local totalLegHeight = upperLeg.Size.Y
        if lowerLeg and lowerLeg.Parent then
            totalLegHeight = totalLegHeight + lowerLeg.Size.Y
        end
        if foot and foot.Parent then
            totalLegHeight = totalLegHeight + foot.Size.Y
        end

        -- Center offset: moves mesh origin to center of full leg column
        local centerOffset = (upperLeg.Size.Y / 2) - (totalLegHeight / 2)

        -- LowerTorso bottom edge reference
        local lowerTorsoHalf = lowerTorso and (lowerTorso.Size.Y / 2) or 0.25
        local hScale = getScaleProp(humanoid, "BodyHeightScale")

        -- Final Y: center the mesh on the leg, then anchor it
        -- exactly to where the real Korblox sits under LowerTorso
        local finalY = centerOffset + (lowerTorsoHalf * hScale * KORBLOX_FIXED_Y)
        return Vector3.new(0, finalY, 0)

    elseif rigType == Enum.HumanoidRigType.R6 then
        local torso    = character:FindFirstChild("Torso")
        local rightLeg = character:FindFirstChild("Right Leg")

        if not torso or not rightLeg then
            return Vector3.new(0, 0.19, 0)
        end

        local hScale = getScaleProp(humanoid, "BodyHeightScale")
        local legHalf   = rightLeg.Size.Y / 2
        local torsoHalf = torso.Size.Y / 2
        local finalY = (torsoHalf + legHalf) * hScale
        return Vector3.new(0, finalY, 0)
    end

    return Vector3.new(0, KORBLOX_FIXED_Y, 0)
end

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

    local character = head.Parent
    if character then
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
    korbloxMesh.Parent = rightLeg

    trackHeartbeat(RunService.Heartbeat:Connect(function()
        if not rightLeg or not rightLeg.Parent then return end
        if not korbloxMesh or not korbloxMesh.Parent then return end

        local humanoid = character:FindFirstChildOfClass("Humanoid")
        if not humanoid then return end

        -- Scale mesh to match body proportions
        korbloxMesh.Scale = getKorbloxScale(humanoid)
        -- Fixed placement anchored to torso
        korbloxMesh.Offset = getKorbloxOffset(character, humanoid)
    end))
end

local function applyKorbloxR15(character)
    local rightUpperLeg = character:FindFirstChild("RightUpperLeg")
    local rightLowerLeg = character:FindFirstChild("RightLowerLeg")
    local rightFoot     = character:FindFirstChild("RightFoot")
    local humanoid      = character:FindFirstChildOfClass("Humanoid")

    if not rightUpperLeg or not humanoid then return end
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
    -- Set initial scale from body scales right away
    mesh.Scale     = getKorbloxScale(humanoid)
    mesh.Parent    = korbloxLeg

    korbloxLeg.CFrame = rightUpperLeg.CFrame

    local weld = Instance.new("WeldConstraint")
    weld.Part0 = rightUpperLeg
    weld.Part1 = korbloxLeg
    weld.Parent = korbloxLeg

    trackHeartbeat(RunService.Heartbeat:Connect(function()
        if not character or not character.Parent then return end
        if not rightUpperLeg or not rightUpperLeg.Parent then return end
        if not mesh or not mesh.Parent then return end
        if not humanoid or not humanoid.Parent then return end

        if rightUpperLeg.Transparency ~= 1 then
            rightUpperLeg.Transparency = 1
        end
        if rightLowerLeg and rightLowerLeg.Parent and rightLowerLeg.Transparency ~= 1 then
            rightLowerLeg.Transparency = 1
        end
        if rightFoot and rightFoot.Parent and rightFoot.Transparency ~= 1 then
            rightFoot.Transparency = 1
        end

        local currentLegHeight = rightUpperLeg.Size.Y
        if rightLowerLeg and rightLowerLeg.Parent then
            currentLegHeight = currentLegHeight + rightLowerLeg.Size.Y
        end
        if rightFoot and rightFoot.Parent then
            currentLegHeight = currentLegHeight + rightFoot.Size.Y
        end

        if currentLegHeight > 0.1 then
            -- Scale dynamically with body proportions every frame
            mesh.Scale = getKorbloxScale(humanoid)
            -- Fixed placement anchored to LowerTorso every frame
            mesh.Offset = getKorbloxOffset(character, humanoid)
        end
    end))
end

local function waitForRig(character)
    local humanoid = character:WaitForChild("Humanoid", 10)
    if not humanoid then return end

    if humanoid.RigType == Enum.HumanoidRigType.R15 then
        character:WaitForChild("LowerTorso",       10)
        character:WaitForChild("RightUpperLeg",    10)
        character:WaitForChild("RightLowerLeg",    10)
        character:WaitForChild("RightFoot",        10)
        character:WaitForChild("HumanoidRootPart", 10)
    else
        character:WaitForChild("Right Leg", 10)
    end
end

local function applyCharacter(character)
    if applied then return end
    applied = true

    waitForRig(character)

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

    track(character.ChildAdded:Connect(function(child)
        if child.Name == "Head" then
            task.wait(0.1)
            applyHeadless(child)
        end
    end))
end

if player.Character then
    task.spawn(function()
        applyCharacter(player.Character)
    end)
end

player.CharacterAdded:Connect(function(character)
    cleanupConnections()
    task.spawn(function()
        applyCharacter(character)
    end)
end)
