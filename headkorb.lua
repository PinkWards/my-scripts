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

-- Safe shield function to get body scales without crashing
local function getScaleProp(humanoid, propName)
    local success, val = pcall(function()
        return humanoid[propName]
    end)
    if success then
        local num = tonumber(val)
        if num then
            return math.max(num, 0.5)
        end
        -- Fallback if the game uses an old NumberValue instead of a property
        if typeof(val) == "Instance" and val:IsA("NumberValue") then
            return math.max(val.Value, 0.5)
        end
    end
    -- If it returns a table, nil, or breaks, just use default 1.0 scale
    return 1.0
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
    if not head or head:FindFirstChild("HeadlessApplied") then return end

    -- Add a flag so we don't apply twice
    local flag = Instance.new("BoolValue")
    flag.Name = "HeadlessApplied"
    flag.Parent = head

    head.Transparency = 1
    removeFace(head)

    -- Destroy existing mesh to prevent double-mesh visual bugs
    local existingMesh = head:FindFirstChildOfClass("SpecialMesh")
    if existingMesh then
        existingMesh:Destroy()
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
                            -- Fixed: Check both Part0 and Part1 properly
                            local isHeadAccessory = (weld.Part0 and weld.Part0.Name == "Head") or (weld.Part1 and weld.Part1.Name == "Head")
                            if isHeadAccessory then
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
                        local isHeadAccessory = (weld.Part0 and weld.Part0.Name == "Head") or (weld.Part1 and weld.Part1.Name == "Head")
                        if isHeadAccessory then
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
    if not rightLeg then return end
    
    local korbloxMesh = rightLeg:FindFirstChild("KorbloxMesh")
    if not korbloxMesh then
        for _, child in ipairs(rightLeg:GetChildren()) do
            if child:IsA("SpecialMesh") or child:IsA("CharacterMesh") then
                child:Destroy()
            end
        end

        rightLeg.Color = DARK_GREY_COLOR

        korbloxMesh = Instance.new("SpecialMesh")
        korbloxMesh.Name = "KorbloxMesh"
        korbloxMesh.MeshType = Enum.MeshType.FileMesh
        korbloxMesh.MeshId = KORBLOX_MESH_ID
        korbloxMesh.TextureId = KORBLOX_TEXTURE_ID
        korbloxMesh.Parent = rightLeg
    end

    track(rightLeg:GetPropertyChangedSignal("Color"):Connect(function()
        if rightLeg.Color ~= DARK_GREY_COLOR then
            rightLeg.Color = DARK_GREY_COLOR
        end
    end))

    -- Added dynamic scaling for R6
    trackHeartbeat(RunService.Heartbeat:Connect(function()
        if not rightLeg or not rightLeg.Parent then return end
        if not korbloxMesh or not korbloxMesh.Parent then return end
        
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        if not humanoid then return end
        
        local wScale = getScaleProp(humanoid, "BodyWidthScale")
        local dScale = getScaleProp(humanoid, "BodyDepthScale")
        local hScale = getScaleProp(humanoid, "BodyHeightScale")
        
        korbloxMesh.Scale = Vector3.new(wScale, hScale, dScale)
    end))
end

local function applyKorbloxR15(character)
    local rightUpperLeg = character:FindFirstChild("RightUpperLeg")
    local rightLowerLeg = character:FindFirstChild("RightLowerLeg")
    local rightFoot     = character:FindFirstChild("RightFoot")
    local humanoid      = character:FindFirstChildOfClass("Humanoid")
    local hrp           = character:FindFirstChild("HumanoidRootPart")

    if not rightUpperLeg or not humanoid or not hrp then return end
    if character:FindFirstChild("KorbloxLeg") then return end

    local function hidePart(part)
        if not part then return end
        part.Transparency = 1
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
    korbloxLeg.Anchored     = true -- Prevents physics flinging/disappearing completely
    korbloxLeg.CanCollide   = false
    korbloxLeg.Massless     = true
    korbloxLeg.CastShadow   = true
    korbloxLeg.Color        = DARK_GREY_COLOR
    korbloxLeg.Transparency = 0

    local mesh = Instance.new("SpecialMesh")
    mesh.Name      = "KorbloxMesh"
    mesh.MeshType  = Enum.MeshType.FileMesh
    mesh.MeshId    = KORBLOX_MESH_ID
    mesh.TextureId = KORBLOX_TEXTURE_ID
    mesh.Parent    = korbloxLeg

    -- Calculate initial position to prevent flashing at the world origin (0,0,0)
    local initialLegHeight = rightUpperLeg.Size.Y + (rightLowerLeg and rightLowerLeg.Size.Y or 0) + (rightFoot and rightFoot.Size.Y or 0)
    if initialLegHeight < 0.1 then initialLegHeight = 2.6 end
    
    local wScale = getScaleProp(humanoid, "BodyWidthScale")
    local dScale = getScaleProp(humanoid, "BodyDepthScale")
    mesh.Scale = Vector3.new(wScale, initialLegHeight / 2.0, dScale)
    
    local topPos = (rightUpperLeg.CFrame * CFrame.new(0, rightUpperLeg.Size.Y / 2, 0)).Position
    local flatCFrame = CFrame.new(topPos) * hrp.CFrame.Rotation
    korbloxLeg.CFrame = flatCFrame * CFrame.new(0, -initialLegHeight / 2, 0)

    korbloxLeg.Parent = character

    trackHeartbeat(RunService.Heartbeat:Connect(function()
        if not character or not character.Parent then return end
        -- Re-fetch parts if they were recreated by an animation/game script
        if not rightUpperLeg or not rightUpperLeg.Parent then 
            rightUpperLeg = character:FindFirstChild("RightUpperLeg")
            rightLowerLeg = character:FindFirstChild("RightLowerLeg")
            rightFoot = character:FindFirstChild("RightFoot")
            hrp = character:FindFirstChild("HumanoidRootPart")
        end
        if not rightUpperLeg or not hrp then return end
        if not mesh or not mesh.Parent then return end
        if not humanoid or not humanoid.Parent then return end
        
        -- Force real legs to stay hidden
        if rightUpperLeg.Transparency ~= 1 then rightUpperLeg.Transparency = 1 end
        if rightLowerLeg and rightLowerLeg.Transparency ~= 1 then rightLowerLeg.Transparency = 1 end
        if rightFoot and rightFoot.Transparency ~= 1 then rightFoot.Transparency = 1 end
        
        local currentLegHeight = rightUpperLeg.Size.Y
        if rightLowerLeg then currentLegHeight = currentLegHeight + rightLowerLeg.Size.Y end
        if rightFoot then currentLegHeight = currentLegHeight + rightFoot.Size.Y end
        
        if currentLegHeight > 0.1 then
            local curW = getScaleProp(humanoid, "BodyWidthScale")
            local curD = getScaleProp(humanoid, "BodyDepthScale")
            mesh.Scale = Vector3.new(curW, currentLegHeight / 2.0, curD)
            
            -- Accurately track the hip joint and point straight down (stiff like real Korblox)
            local topPos = (rightUpperLeg.CFrame * CFrame.new(0, rightUpperLeg.Size.Y / 2, 0)).Position
            local flatCFrame = CFrame.new(topPos) * hrp.CFrame.Rotation
            korbloxLeg.CFrame = flatCFrame * CFrame.new(0, -currentLegHeight / 2, 0)
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
        -- Re-apply Korblox if the game/animation resets your leg parts dynamically
        elseif child.Name == "RightUpperLeg" or child.Name == "Right Leg" then
            task.wait(0.1)
            local hum = character:FindFirstChildOfClass("Humanoid")
            if hum then
                if hum.RigType == Enum.HumanoidRigType.R15 then
                    applyKorbloxR15(character)
                elseif hum.RigType == Enum.HumanoidRigType.R6 then
                    applyKorbloxR6(character)
                end
            end
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
    cleanupConnections()
    task.spawn(function()
        applyCharacter(character)
    end)
end)
