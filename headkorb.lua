local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer

local HEADLESS_MESH_ID = "rbxassetid://1095708"
local KORBLOX_MESH_ID = "rbxassetid://101851696"
local KORBLOX_TEXTURE_ID = "rbxassetid://101851254"
local DARK_GREY_COLOR = Color3.fromRGB(64, 64, 64)
local TINY_SCALE = Vector3.new(0.001, 0.001, 0.001)

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

-- Detects the correct Y lift by reading the torso size and leg sizes live
local function calculateKorbloxYLift(character, humanoid)
    local rigType = humanoid.RigType

    if rigType == Enum.HumanoidRigType.R6 then
        -- R6: torso sits above the right leg, measure both
        local torso    = character:FindFirstChild("Torso")
        local rightLeg = character:FindFirstChild("Right Leg")

        if not torso or not rightLeg then
            return 0.19 -- fallback
        end

        local torsoHalfHeight = torso.Size.Y / 2
        local legHalfHeight   = rightLeg.Size.Y / 2

        -- The leg part origin is at its center.
        -- We want the mesh bottom to align with torso bottom.
        -- Lift = half torso + half leg (places mesh top near torso bottom)
        -- Then we push up slightly so it sits flush under the torso.
        local lift = torsoHalfHeight + legHalfHeight

        -- Scale it by the humanoid height scale so it stretches with the body
        local hScale = getScaleProp(humanoid, "BodyHeightScale")
        return lift * hScale

    elseif rigType == Enum.HumanoidRigType.R15 then
        -- R15: measure the upper leg + lower leg + foot combined height
        local upperLeg = character:FindFirstChild("RightUpperLeg")
        local lowerLeg = character:FindFirstChild("RightLowerLeg")
        local foot     = character:FindFirstChild("RightFoot")
        local rootPart = character:FindFirstChild("HumanoidRootPart")

        if not upperLeg then
            return 0.55 -- fallback
        end

        local totalLegHeight = upperLeg.Size.Y
        if lowerLeg and lowerLeg.Parent then
            totalLegHeight = totalLegHeight + lowerLeg.Size.Y
        end
        if foot and foot.Parent then
            totalLegHeight = totalLegHeight + foot.Size.Y
        end

        -- Center the mesh across the full leg span
        local baseCenter = (upperLeg.Size.Y / 2) - (totalLegHeight / 2)

        -- Measure root part to get the body scale reference
        local rootHeight = rootPart and rootPart.Size.Y or 2
        local hScale     = getScaleProp(humanoid, "BodyHeightScale")

        -- Push up so the mesh top sits flush under the torso/root
        local lift = baseCenter + (rootHeight * 0.1 * hScale)
        return lift
    end

    return 0.55 -- universal fallback
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

    -- Live loop: recalculates Y lift every frame based on actual torso size
    trackHeartbeat(RunService.Heartbeat:Connect(function()
        if not rightLeg or not rightLeg.Parent then return end
        if not korbloxMesh or not korbloxMesh.Parent then return end

        local humanoid = character:FindFirstChildOfClass("Humanoid")
        if not humanoid then return end

        local wScale = getScaleProp(humanoid, "BodyWidthScale")
        local hScale = getScaleProp(humanoid, "BodyHeightScale")
        local dScale = getScaleProp(humanoid, "BodyDepthScale")
        korbloxMesh.Scale = Vector3.new(wScale, hScale, dScale)

        -- Recalculate lift dynamically from actual torso size
        local yLift = calculateKorbloxYLift(character, humanoid)
        korbloxMesh.Offset = Vector3.new(0, yLift, 0)
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

    local wScale = getScaleProp(humanoid, "BodyWidthScale")
    local hScale = getScaleProp(humanoid, "BodyHeightScale")
    local dScale = getScaleProp(humanoid, "BodyDepthScale")
    mesh.Scale     = Vector3.new(wScale, hScale, dScale)
    mesh.Parent    = korbloxLeg

    korbloxLeg.CFrame = rightUpperLeg.CFrame

    local weld = Instance.new("WeldConstraint")
    weld.Part0 = rightUpperLeg
    weld.Part1 = korbloxLeg
    weld.Parent = korbloxLeg

    -- Live loop: recalculates Y lift every frame based on actual leg + torso size
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
            local curW = getScaleProp(humanoid, "BodyWidthScale")
            local curH = getScaleProp(humanoid, "BodyHeightScale")
            local curD = getScaleProp(humanoid, "BodyDepthScale")
            mesh.Scale = Vector3.new(curW, curH, curD)

            -- Dynamically calculated from actual torso + leg sizes every frame
            local yLift = calculateKorbloxYLift(character, humanoid)
            mesh.Offset = Vector3.new(0, yLift, 0)
        end
    end))
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
