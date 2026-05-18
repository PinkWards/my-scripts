local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer

local HEADLESS_MESH_ID = "rbxassetid://1095708"
local KORBLOX_MESH_ID = "rbxassetid://101851696"
local KORBLOX_TEXTURE_ID = "rbxassetid://101851254"
local DARK_GREY_COLOR = Color3.fromRGB(64, 64, 64)
local TINY_SCALE = Vector3.new(0.001, 0.001, 0.001)

-- [!] ADJUST THIS NUMBER TO LIFT THE KORBLOX LEG UP OR DOWN [!]
-- Changed from 0.2 to 0.1. 0.2 clipped into the torso, 0.0 floated. 0.1 is the sweet spot!
local KORBLOX_Y_LIFT = 0.18

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
    
    -- Apply the lift offset to the mesh directly for R6
    korbloxMesh.Offset = Vector3.new(0, KORBLOX_Y_LIFT, 0)
    
    korbloxMesh.Parent = rightLeg

    -- Dynamically scale R6 Korblox to match avatar scales
    trackHeartbeat(RunService.Heartbeat:Connect(function()
        if not rightLeg or not rightLeg.Parent or not korbloxMesh or not korbloxMesh.Parent then return end
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        if humanoid then
            local wScale = getScaleProp(humanoid, "BodyWidthScale")
            local hScale = getScaleProp(humanoid, "BodyHeightScale")
            local dScale = getScaleProp(humanoid, "BodyDepthScale")
            korbloxMesh.Scale = Vector3.new(wScale, hScale, dScale)
            -- Ensure lift persists dynamically
            korbloxMesh.Offset = Vector3.new(0, KORBLOX_Y_LIFT, 0)
        end
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
    
    -- Use the avatar's actual scale properties
    local wScale = getScaleProp(humanoid, "BodyWidthScale")
    local hScale = getScaleProp(humanoid, "BodyHeightScale")
    local dScale = getScaleProp(humanoid, "BodyDepthScale")
    
    mesh.Scale     = Vector3.new(wScale, hScale, dScale)
    mesh.Parent    = korbloxLeg

    -- Position the Korblox exactly on the leg before welding
    korbloxLeg.CFrame = rightUpperLeg.CFrame

    -- Weld it directly to the real (invisible) RightUpperLeg! 
    local weld = Instance.new("WeldConstraint")
    weld.Part0 = rightUpperLeg
    weld.Part1 = korbloxLeg
    weld.Parent = korbloxLeg

    -- Keep real leg parts hidden persistently & dynamically update scale
    trackHeartbeat(RunService.Heartbeat:Connect(function()
        if not character or not character.Parent then return end
        if not rightUpperLeg or not rightUpperLeg.Parent then return end
        if not mesh or not mesh.Parent then return end
        if not humanoid or not humanoid.Parent then return end
        
        if rightUpperLeg and rightUpperLeg.Transparency ~= 1 then
            rightUpperLeg.Transparency = 1
        end
        if rightLowerLeg and rightLowerLeg.Parent and rightLowerLeg.Transparency ~= 1 then
            rightLowerLeg.Transparency = 1
        end
        if rightFoot and rightFoot.Parent and rightFoot.Transparency ~= 1 then
            rightFoot.Transparency = 1
        end
        
        -- Dynamically calculate current leg height
        local currentLegHeight = rightUpperLeg.Size.Y
        if rightLowerLeg and rightLowerLeg.Parent then currentLegHeight = currentLegHeight + rightLowerLeg.Size.Y end
        if rightFoot and rightFoot.Parent then currentLegHeight = currentLegHeight + rightFoot.Size.Y end
        
        if currentLegHeight > 0.1 then
            -- Dynamically update with exact avatar scales
            local curW = getScaleProp(humanoid, "BodyWidthScale")
            local curH = getScaleProp(humanoid, "BodyHeightScale")
            local curD = getScaleProp(humanoid, "BodyDepthScale")
            mesh.Scale = Vector3.new(curW, curH, curD)
            
            -- Apply the perfect center + lift combination to fix floating/clipping
            local yOffset = (rightUpperLeg.Size.Y / 2) - (currentLegHeight / 2) + KORBLOX_Y_LIFT
            mesh.Offset = Vector3.new(0, yOffset, 0)
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
