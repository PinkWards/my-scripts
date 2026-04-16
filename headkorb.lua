local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer

-- ══════════════════════════════════════════════
--  ASSET IDs
-- ══════════════════════════════════════════════
local HEADLESS_MESH_ID   = "rbxassetid://1095708"
local KORBLOX_MESH_ID    = "rbxassetid://101851696"
local KORBLOX_TEXTURE_ID = "rbxassetid://101851254"
local DARK_GREY          = Color3.fromRGB(64, 64, 64)
local TINY               = Vector3.new(0.001, 0.001, 0.001)

-- ══════════════════════════════════════════════
--  CONNECTION MANAGEMENT
-- ══════════════════════════════════════════════
local connections = {}
local applied     = false

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
--  UTILITY
-- ══════════════════════════════════════════════
local function forceProp(instance, prop, value, signal)
    -- Immediately set and lock a property via its changed signal
    local ok, err = pcall(function()
        instance[prop] = value
    end)
    if not ok then return end

    addConn(instance:GetPropertyChangedSignal(prop):Connect(function()
        local cur
        local s, _ = pcall(function() cur = instance[prop] end)
        if s and cur ~= value then
            instance[prop] = value
        end
    end))
end

local function destroyChildrenOfClass(parent, className)
    for _, v in ipairs(parent:GetChildren()) do
        if v:IsA(className) then v:Destroy() end
    end
end

-- ══════════════════════════════════════════════
--  HEADLESS
-- ══════════════════════════════════════════════
local function lockPartInvisible(part)
    -- Transparency
    forceProp(part, "Transparency", 1)

    -- LocalTransparencyModifier also needs to be 0 so the engine
    -- doesn't override our 1 back toward visible
    pcall(function()
        part.LocalTransparencyModifier = 0
    end)
    addConn(part:GetPropertyChangedSignal("LocalTransparencyModifier"):Connect(function()
        pcall(function()
            if part.LocalTransparencyModifier ~= 0 then
                part.LocalTransparencyModifier = 0
            end
        end)
    end))
end

local function nukeHeadAccessories(character)
    local function checkAccessory(acc)
        if not acc:IsA("Accessory") then return end
        task.wait(0.05)
        if not acc.Parent then return end

        local handle = acc:FindFirstChild("Handle")
        if not handle then return end

        -- Check attachment name instead of weld part — more reliable
        local att = handle:FindFirstChildOfClass("Attachment")
        if att and att.Name:lower():find("hat") or att and att.Name == "HatAttachment"
            or att and att.Name == "HairAttachment"
            or att and att.Name == "FaceCenterAttachment"
            or att and att.Name == "FaceFrontAttachment"
            or att and att.Name == "NeckAttachment" then
            lockPartInvisible(handle)
            return
        end

        -- Fallback: check weld target
        for _, w in ipairs(handle:GetChildren()) do
            if (w:IsA("Weld") or w:IsA("Motor6D")) then
                local other = (w.Part0 ~= handle and w.Part0) or (w.Part1 ~= handle and w.Part1)
                if other and other.Name == "Head" then
                    lockPartInvisible(handle)
                    return
                end
            end
        end
    end

    for _, v in ipairs(character:GetChildren()) do
        task.spawn(checkAccessory, v)
    end

    addConn(character.ChildAdded:Connect(function(child)
        task.spawn(checkAccessory, child)
    end))
end

local function applyHeadless(character)
    local head = character:WaitForChild("Head", 10)
    if not head then return end

    -- Remove face decal
    local function removeFace()
        local face = head:FindFirstChild("face")
        if face then face:Destroy() end
    end
    removeFace()
    addConn(head.ChildAdded:Connect(function(child)
        if child:IsA("Decal") then
            task.defer(function()
                if child and child.Parent then child:Destroy() end
            end)
        end
    end))

    -- Shrink existing mesh
    local existing = head:FindFirstChildOfClass("SpecialMesh")
    if existing then
        existing.Scale = TINY
        existing.Offset = Vector3.new(0, 0, 0)
    end

    -- Add our tiny headless mesh (prevents head from "popping" on respawn)
    if not head:FindFirstChild("HLMesh") then
        local m = Instance.new("SpecialMesh")
        m.Name      = "HLMesh"
        m.MeshType  = Enum.MeshType.FileMesh
        m.MeshId    = HEADLESS_MESH_ID
        m.Scale     = TINY
        m.Parent    = head
    end

    -- Lock head invisible
    lockPartInvisible(head)
    forceProp(head, "CanCollide", false)

    -- Hide hat/hair accessories on head
    nukeHeadAccessories(character)
end

-- ══════════════════════════════════════════════
--  KORBLOX  ——  R6
-- ══════════════════════════════════════════════
local function applyKorbloxR6(character)
    local leg = character:WaitForChild("Right Leg", 10)
    if not leg then return end
    if leg:FindFirstChild("KorbloxMesh") then return end

    -- Remove existing meshes
    destroyChildrenOfClass(leg, "SpecialMesh")
    destroyChildrenOfClass(leg, "CharacterMesh")

    -- Lock colour
    forceProp(leg, "Color", DARK_GREY)
    forceProp(leg, "BrickColor", BrickColor.new(DARK_GREY))

    -- Apply mesh
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
--  KORBLOX  ——  R15
-- ══════════════════════════════════════════════

--[[
    Real Korblox in R15 works as a MeshPart accessory welded to
    RightUpperLeg. We replicate that by:
      1. Hiding RightUpperLeg + RightLowerLeg + RightFoot
      2. Creating a visual Part with the Korblox mesh
      3. Welding it to HumanoidRootPart and mirroring the
         RightUpperLeg Motor6D transform every frame so it
         animates correctly.
]]

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

    local hrp          = character:WaitForChild("HumanoidRootPart", 10)
    local upperLeg     = character:WaitForChild("RightUpperLeg",    10)
    local lowerLeg     = character:WaitForChild("RightLowerLeg",    10)
    local foot         = character:WaitForChild("RightFoot",        10)

    if not hrp or not upperLeg then return end

    -- ── Hide original R15 right-leg parts ──────────────────────────
    local function hidePart(part)
        if not part then return end
        lockPartInvisible(part)
        forceProp(part, "CanCollide", false)
        -- Remove meshes / decals so they don't bleed through
        for _, c in ipairs(part:GetChildren()) do
            if c:IsA("SpecialMesh") or c:IsA("Decal") or c:IsA("SurfaceAppearance") then
                c:Destroy()
            end
        end
        -- Prevent new ones being added
        addConn(part.ChildAdded:Connect(function(child)
            if child:IsA("SpecialMesh") or child:IsA("Decal") or child:IsA("SurfaceAppearance") then
                task.defer(function() if child.Parent then child:Destroy() end end)
            end
        end))
    end

    hidePart(upperLeg)
    hidePart(lowerLeg)
    hidePart(foot)

    -- ── Find the motor that drives RightUpperLeg ────────────────────
    -- Wait a moment for the rig to fully load motors
    task.wait(0.1)
    local upperMotor = findMotorTo(character, upperLeg)

    -- ── Create visual Korblox part ──────────────────────────────────
    local kPart = Instance.new("Part")
    kPart.Name           = "KorbloxLeg"
    kPart.Size           = Vector3.new(1, 1, 1)
    kPart.Anchored       = false
    kPart.CanCollide     = false
    kPart.Massless       = true
    kPart.CastShadow     = true
    kPart.Color          = DARK_GREY
    kPart.Transparency   = 0
    kPart.Parent         = character

    local kMesh = Instance.new("SpecialMesh")
    kMesh.Name      = "KorbloxMesh"
    kMesh.MeshType  = Enum.MeshType.FileMesh
    kMesh.MeshId    = KORBLOX_MESH_ID
    kMesh.TextureId = KORBLOX_TEXTURE_ID
    -- Scale tuned to match real Korblox proportions in R15
    kMesh.Scale     = Vector3.new(1, 1, 1)
    kMesh.Offset    = Vector3.new(0, 0, 0)
    kMesh.Parent    = kPart

    -- ── Weld Korblox part to the same joint RightUpperLeg uses ─────
    local weld = Instance.new("Motor6D")
    weld.Name = "KorbloxDrive"

    if upperMotor then
        -- Mirror the exact same joint
        weld.Part0  = upperMotor.Part0   -- e.g. LowerTorso
        weld.Part1  = kPart
        weld.C0     = upperMotor.C0
        weld.C1     = CFrame.new(0, 0.5, 0)  -- shift so mesh sits correctly
        weld.Parent = upperMotor.Parent
    else
        -- Fallback: weld to HRP directly
        weld.Part0  = hrp
        weld.Part1  = kPart
        weld.C0     = CFrame.new(0.5, -1, 0)
        weld.C1     = CFrame.new(0, 0.5, 0)
        weld.Parent = hrp
    end

    -- ── Every frame: mirror animation transform + re-hide legs ──────
    addConn(RunService.Heartbeat:Connect(function()
        if not character.Parent then return end

        -- Mirror transform so animations apply to the visual leg
        if upperMotor and upperMotor.Parent then
            weld.C0        = upperMotor.C0
            weld.Transform = upperMotor.Transform
        end

        -- Keep legs invisible (animation system & server replication
        -- can restore transparency each frame)
        if upperLeg.Parent then
            if upperLeg.Transparency        ~= 1 then upperLeg.Transparency        = 1 end
            if upperLeg.LocalTransparencyModifier ~= 0 then upperLeg.LocalTransparencyModifier = 0 end
        end
        if lowerLeg and lowerLeg.Parent then
            if lowerLeg.Transparency        ~= 1 then lowerLeg.Transparency        = 1 end
            if lowerLeg.LocalTransparencyModifier ~= 0 then lowerLeg.LocalTransparencyModifier = 0 end
        end
        if foot and foot.Parent then
            if foot.Transparency            ~= 1 then foot.Transparency            = 1 end
            if foot.LocalTransparencyModifier ~= 0 then foot.LocalTransparencyModifier = 0 end
        end
    end))
end

-- ══════════════════════════════════════════════
--  MAIN APPLY
-- ══════════════════════════════════════════════
local function applyAll(character)
    if applied then return end
    applied = true

    local humanoid = character:WaitForChild("Humanoid", 10)
    if not humanoid then applied = false; return end

    -- Wait for character to be fully parented
    if not character.Parent then
        character.AncestryChanged:Wait()
    end

    -- Small yield so all parts and motors exist
    task.wait(0.15)

    if not character.Parent then applied = false; return end

    -- Headless (works for both R6 and R15)
    task.spawn(applyHeadless, character)

    -- Korblox based on rig type
    if humanoid.RigType == Enum.HumanoidRigType.R6 then
        task.spawn(applyKorbloxR6, character)
    else
        task.spawn(applyKorbloxR15, character)
    end

    -- If Head re-appears (rare edge case)
    addConn(character.ChildAdded:Connect(function(child)
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
