local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer

-- Asset IDs
local HEADLESS_MESH_ID   = "rbxassetid://1095708"
local KORBLOX_MESH_ID    = "rbxassetid://101851696"
local KORBLOX_TEXTURE_ID = "rbxassetid://101851254"
local DARK_GREY          = Color3.fromRGB(64, 64, 64)
local TINY               = Vector3.new(0.001, 0.001, 0.001)

-- Connection tracking
local activeConnections  = {}
local heartbeatConns     = {}
local applied            = false

local function track(conn)
    activeConnections[#activeConnections + 1] = conn
end

local function trackHB(conn)
    heartbeatConns[#heartbeatConns + 1] = conn
end

local function cleanupAll()
    for i = #activeConnections, 1, -1 do
        local c = activeConnections[i]
        if c and c.Connected then c:Disconnect() end
        activeConnections[i] = nil
    end
    for i = #heartbeatConns, 1, -1 do
        local c = heartbeatConns[i]
        if c and c.Connected then c:Disconnect() end
        heartbeatConns[i] = nil
    end
    applied = false
end

-- ══════════════════════════════════════════════
--  HEADLESS
--  Only hides the Head part and its face decal
--  Does NOT touch accessories or hair
-- ══════════════════════════════════════════════
local function applyHeadless(character)
    local head = character:WaitForChild("Head", 10)
    if not head then return end
    if head:FindFirstChild("HeadlessMesh") then return end

    -- Remove face decal
    local face = head:FindFirstChild("face")
    if face then face:Destroy() end

    -- Prevent face decal coming back
    track(head.ChildAdded:Connect(function(child)
        if child:IsA("Decal") then
            task.defer(function()
                if child and child.Parent then
                    child:Destroy()
                end
            end)
        end
    end))

    -- Shrink the default head mesh so the head shape disappears
    local existing = head:FindFirstChildOfClass("SpecialMesh")
    if existing then
        existing.Scale = TINY
    end

    -- Add the official headless mesh at tiny scale
    local hlMesh = Instance.new("SpecialMesh")
    hlMesh.Name     = "HeadlessMesh"
    hlMesh.MeshType = Enum.MeshType.FileMesh
    hlMesh.MeshId   = HEADLESS_MESH_ID
    hlMesh.Scale    = TINY
    hlMesh.Parent   = head

    -- Make head invisible
    head.Transparency = 1
    head.CanCollide   = false

    -- Lock transparency so engine cannot restore it
    track(head:GetPropertyChangedSignal("Transparency"):Connect(function()
        if head.Transparency ~= 1 then
            head.Transparency = 1
        end
    end))

    -- Lock LocalTransparencyModifier so engine cannot override it
    track(head:GetPropertyChangedSignal("LocalTransparencyModifier"):Connect(function()
        pcall(function()
            if head.LocalTransparencyModifier ~= 0 then
                head.LocalTransparencyModifier = 0
            end
        end)
    end))
    pcall(function() head.LocalTransparencyModifier = 0 end)
end

-- ══════════════════════════════════════════════
--  KORBLOX R6
--
--  R6 has one single "Right Leg" part.
--  We just replace its mesh directly.
--  Animations move the part automatically so
--  no extra motors or heartbeat needed.
-- ══════════════════════════════════════════════
local function applyKorbloxR6(character)
    local rightLeg = character:WaitForChild("Right Leg", 10)
    if not rightLeg then return end
    if rightLeg:FindFirstChild("KorbloxMesh") then return end

    -- Remove any existing mesh on the leg
    for _, child in ipairs(rightLeg:GetChildren()) do
        if child:IsA("SpecialMesh") or child:IsA("CharacterMesh") then
            child:Destroy()
        end
    end

    -- Set the leg color to dark grey to match Korblox texture
    rightLeg.Color = DARK_GREY

    -- Lock the color so body color changes don't override it
    track(rightLeg:GetPropertyChangedSignal("Color"):Connect(function()
        if rightLeg.Color ~= DARK_GREY then
            rightLeg.Color = DARK_GREY
        end
    end))

    -- Apply Korblox mesh directly onto the Right Leg part
    local m = Instance.new("SpecialMesh")
    m.Name      = "KorbloxMesh"
    m.MeshType  = Enum.MeshType.FileMesh
    m.MeshId    = KORBLOX_MESH_ID
    m.TextureId = KORBLOX_TEXTURE_ID
    m.Scale     = Vector3.new(1, 1, 1)
    m.Offset    = Vector3.new(0, 0, 0)
    m.Parent    = rightLeg
end

-- ══════════════════════════════════════════════
--  KORBLOX R15
--
--  R15 splits the leg into 3 parts:
--    RightUpperLeg (thigh)
--    RightLowerLeg (shin)
--    RightFoot     (foot)
--
--  The Korblox mesh covers the entire leg as
--  one piece so we cannot just slap it on one
--  part. Instead:
--
--  1. Hide all 3 real leg parts
--  2. Find the Motor6D that drives RightUpperLeg
--     (usually sits inside LowerTorso, called
--      "RightHip")
--  3. Create a new blank Part with the Korblox mesh
--  4. Create a new Motor6D that connects our part
--     to the SAME parent joint as the real leg
--  5. Every Heartbeat copy BOTH C0 and Transform
--     from the real motor so animations apply
--     correctly to our visual part
-- ══════════════════════════════════════════════
local function applyKorbloxR15(character)
    -- Wait for all three leg parts to exist
    local rightUpperLeg = character:WaitForChild("RightUpperLeg", 10)
    local rightLowerLeg = character:WaitForChild("RightLowerLeg", 10)
    local rightFoot     = character:WaitForChild("RightFoot",     10)

    if not rightUpperLeg then return end
    if character:FindFirstChild("KorbloxLeg") then return end

    -- Small wait so all Motor6D joints are fully built
    task.wait(0.15)

    -- Find the Motor6D whose Part1 is RightUpperLeg
    -- This motor is what the animation system writes to
    -- It is almost always inside LowerTorso as "RightHip"
    local upperMotor = nil
    local lowerTorso = character:FindFirstChild("LowerTorso")
    if lowerTorso then
        for _, v in ipairs(lowerTorso:GetChildren()) do
            if v:IsA("Motor6D") and v.Part1 == rightUpperLeg then
                upperMotor = v
                break
            end
        end
    end

    -- Fallback: search whole character if not found in LowerTorso
    if not upperMotor then
        for _, v in ipairs(character:GetDescendants()) do
            if v:IsA("Motor6D") and v.Part1 == rightUpperLeg then
                upperMotor = v
                break
            end
        end
    end

    -- ── Hide the 3 real leg parts ───────────────────────────────────
    local function hidePart(part)
        if not part then return end
        part.Transparency = 1
        part.CanCollide   = false
        -- Also zero out LocalTransparencyModifier or the engine
        -- can fight us and make the part semi-visible
        pcall(function() part.LocalTransparencyModifier = 0 end)
    end

    hidePart(rightUpperLeg)
    hidePart(rightLowerLeg)
    hidePart(rightFoot)

    -- ── Create the visual Korblox part ─────────────────────────────
    local kPart = Instance.new("Part")
    kPart.Name         = "KorbloxLeg"
    kPart.Size         = Vector3.new(1, 1, 1)
    kPart.Anchored     = false
    kPart.CanCollide   = false
    kPart.Massless     = true   -- does not affect physics weight
    kPart.CastShadow   = true
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

    -- ── Create Motor6D to drive our Korblox part ───────────────────
    local driveMotor = Instance.new("Motor6D")
    driveMotor.Name = "KorbloxDrive"

    if upperMotor then
        --  Attach to the SAME parent and Part0 as the real leg motor
        --  so our part sits at exactly the same joint origin
        --
        --  Structure it creates:
        --    LowerTorso
        --    ├── Motor6D "RightHip"     → RightUpperLeg (hidden)
        --    └── Motor6D "KorbloxDrive" → KorbloxLeg    (visible)
        --
        driveMotor.Part0  = upperMotor.Part0   -- LowerTorso
        driveMotor.Part1  = kPart
        driveMotor.C0     = upperMotor.C0      -- match exact joint position
        driveMotor.C1     = upperMotor.C1      -- match exact part-relative offset
        driveMotor.Parent = upperMotor.Parent  -- also LowerTorso

        -- Every frame mirror both C0 and Transform from the real motor
        -- C0        = the joint's rest/bind position (can change with body scale)
        -- Transform = what the animation system writes each frame (the pose)
        -- Without Transform the leg will not animate at all
        trackHB(RunService.Heartbeat:Connect(function()
            if not character.Parent then return end
            if not upperMotor.Parent then return end
            if not driveMotor.Parent then return end

            driveMotor.C0        = upperMotor.C0
            driveMotor.Transform = upperMotor.Transform

            -- Re-lock leg visibility every frame
            -- The server or animation system can restore transparency
            if rightUpperLeg.Parent then
                rightUpperLeg.Transparency = 1
                pcall(function() rightUpperLeg.LocalTransparencyModifier = 0 end)
            end
            if rightLowerLeg and rightLowerLeg.Parent then
                rightLowerLeg.Transparency = 1
                pcall(function() rightLowerLeg.LocalTransparencyModifier = 0 end)
            end
            if rightFoot and rightFoot.Parent then
                rightFoot.Transparency = 1
                pcall(function() rightFoot.LocalTransparencyModifier = 0 end)
            end
        end))
    else
        -- Fallback if no motor found: weld directly to RightUpperLeg
        -- Leg will still be hidden but animation may not perfectly follow
        driveMotor.Part0  = rightUpperLeg
        driveMotor.Part1  = kPart
        driveMotor.C0     = CFrame.new(0, 0, 0)
        driveMotor.C1     = CFrame.new(0, 0, 0)
        driveMotor.Parent = rightUpperLeg

        trackHB(RunService.Heartbeat:Connect(function()
            if not character.Parent then return end
            if rightUpperLeg.Parent then
                rightUpperLeg.Transparency = 1
                pcall(function() rightUpperLeg.LocalTransparencyModifier = 0 end)
            end
            if rightLowerLeg and rightLowerLeg.Parent then
                rightLowerLeg.Transparency = 1
                pcall(function() rightLowerLeg.LocalTransparencyModifier = 0 end)
            end
            if rightFoot and rightFoot.Parent then
                rightFoot.Transparency = 1
                pcall(function() rightFoot.LocalTransparencyModifier = 0 end)
            end
        end))
    end
end

-- ══════════════════════════════════════════════
--  MAIN APPLY
-- ══════════════════════════════════════════════
local function applyAll(character)
    if applied then return end
    applied = true

    local humanoid = character:WaitForChild("Humanoid", 10)
    if not humanoid then
        applied = false
        return
    end

    -- Wait for character to fully load into workspace
    if not character.Parent then
        character.AncestryChanged:Wait()
    end

    if not character.Parent then
        applied = false
        return
    end

    -- Apply headless first (works same for R6 and R15)
    task.spawn(applyHeadless, character)

    -- Apply Korblox based on rig type
    if humanoid.RigType == Enum.HumanoidRigType.R6 then
        task.spawn(applyKorbloxR6, character)
    elseif humanoid.RigType == Enum.HumanoidRigType.R15 then
        task.spawn(applyKorbloxR15, character)
    end

    -- Edge case: Head gets re-added mid session
    track(character.ChildAdded:Connect(function(child)
        if child.Name == "Head" then
            task.wait(0.05)
            task.spawn(applyHeadless, character)
        end
    end))
end

-- ══════════════════════════════════════════════
--  CHARACTER LIFECYCLE
-- ══════════════════════════════════════════════
local function onCharacter(character)
    cleanupAll()
    task.spawn(applyAll, character)
end

if player.Character then
    onCharacter(player.Character)
end

player.CharacterAdded:Connect(onCharacter)
