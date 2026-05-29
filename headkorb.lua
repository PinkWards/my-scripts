if _G.PerfectKorbloxHeadlessLoaded then return end
_G.PerfectKorbloxHeadlessLoaded = true

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local player = Players.LocalPlayer

local HEADLESS_MESH_ID = "rbxassetid://1095708"
local KORBLOX_MESH_ID = "rbxassetid://101851696"
local KORBLOX_TEXTURE_ID = "rbxassetid://101851254"
local DARK_GREY_COLOR = Color3.fromRGB(64, 64, 64)
local TINY_SCALE = Vector3.new(0.001, 0.001, 0.001)

-- Default Y offset tailored for R15 to perfectly cover the lower leg gap
local currentOffsetY = -0.5 

local activeConnections = {}
local heartbeatConns = {}
local applied = false

-- =============================================
--           BUTTERY SMOOTH MINI GUI
-- =============================================

local function buildGUI()
    local old = player.PlayerGui:FindFirstChild("KorbloxAdjuster")
    if old then old:Destroy() end

    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "KorbloxAdjuster"
    screenGui.ResetOnSpawn = false
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screenGui.Parent = player.PlayerGui

    local container = Instance.new("Frame")
    container.Name = "Container"
    container.Size = UDim2.new(0, 230, 0, 34)
    container.Position = UDim2.new(0, 15, 0, 15)
    container.BackgroundTransparency = 1
    container.Parent = screenGui

    -- Toggle Icon
    local toggleBtn = Instance.new("TextButton")
    toggleBtn.Name = "Toggle"
    toggleBtn.Size = UDim2.new(0, 30, 0, 30)
    toggleBtn.Position = UDim2.new(0, 0, 0, 2)
    toggleBtn.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
    toggleBtn.Text = "🦿"
    toggleBtn.TextSize = 16
    toggleBtn.BorderSizePixel = 0
    toggleBtn.AutoButtonColor = false
    toggleBtn.Parent = container

    local btnCorner = Instance.new("UICorner")
    btnCorner.CornerRadius = UDim.new(0, 8)
    btnCorner.Parent = toggleBtn

    local btnStroke = Instance.new("UIStroke")
    btnStroke.Color = Color3.fromRGB(90, 170, 255)
    btnStroke.Thickness = 1.2
    btnStroke.Parent = toggleBtn

    -- Slider Frame
    local mainFrame = Instance.new("Frame")
    mainFrame.Name = "SliderFrame"
    mainFrame.Size = UDim2.new(0, 194, 0, 30)
    mainFrame.Position = UDim2.new(0, 35, 0, 2)
    mainFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
    mainFrame.BorderSizePixel = 0
    mainFrame.Visible = false
    mainFrame.Parent = container

    local frameCorner = Instance.new("UICorner")
    frameCorner.CornerRadius = UDim.new(0, 8)
    frameCorner.Parent = mainFrame

    local frameStroke = Instance.new("UIStroke")
    frameStroke.Color = Color3.fromRGB(60, 60, 60)
    frameStroke.Thickness = 0.8
    frameStroke.Parent = mainFrame

    local label = Instance.new("TextLabel")
    label.Text = "Y"
    label.Size = UDim2.new(0, 12, 1, 0)
    label.Position = UDim2.new(0, 8, 0, 0)
    label.BackgroundTransparency = 1
    label.TextColor3 = Color3.fromRGB(200, 200, 200)
    label.TextSize = 14
    label.Font = Enum.Font.GothamBold
    label.Parent = mainFrame

    local track = Instance.new("Frame")
    track.Size = UDim2.new(1, -60, 0, 6)
    track.Position = UDim2.new(0, 26, 0.5, 0)
    track.AnchorPoint = Vector2.new(0, 0.5)
    track.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
    track.BorderSizePixel = 0
    track.Parent = mainFrame

    local tCorner = Instance.new("UICorner")
    tCorner.CornerRadius = UDim.new(0, 3)
    tCorner.Parent = track

    local fill = Instance.new("Frame")
    fill.Size = UDim2.new(0, 0, 1, 0)
    fill.BackgroundColor3 = Color3.fromRGB(90, 170, 255)
    fill.BorderSizePixel = 0
    fill.Parent = track

    local fCorner = Instance.new("UICorner")
    fCorner.CornerRadius = UDim.new(0, 3)
    fCorner.Parent = fill

    local valLabel = Instance.new("TextLabel")
    valLabel.Name = "ValLabel"
    valLabel.Text = tostring(currentOffsetY)
    valLabel.Size = UDim2.new(0, 30, 1, 0)
    valLabel.Position = UDim2.new(1, -37, 0, 0)
    valLabel.BackgroundTransparency = 1
    valLabel.TextColor3 = Color3.fromRGB(90, 170, 255)
    valLabel.TextSize = 12
    valLabel.Font = Enum.Font.GothamBold
    valLabel.Parent = mainFrame

    -- Slider Logic
    local minVal = -2.0
    local maxVal = 2.0
    local stepVal = 0.01

    local function updateSlider(value)
        value = math.clamp(value, minVal, maxVal)
        local display = math.round(value * 100) / 100
        currentOffsetY = display
        valLabel.Text = tostring(display)
        local alpha = (value - minVal) / (maxVal - minVal)
        fill.Size = UDim2.new(alpha, 0, 1, 0)
    end

    updateSlider(currentOffsetY)

    local sliding = false
    local function updateFromInput(input)
        local relX = (input.Position.X - track.AbsolutePosition.X) / track.AbsoluteSize.X
        local raw = minVal + math.clamp(relX, 0, 1) * (maxVal - minVal)
        local snapped = math.round(raw / stepVal) * stepVal
        updateSlider(snapped)
    end

    track.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            sliding = true
            updateFromInput(input)
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if sliding and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            updateFromInput(input)
        end
    end)

    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            sliding = false
        end
    end)

    -- Toggle & Drag Logic
    local isOpen = false
    local dragging = false
    local dragStart, startPos, dragDistance

    toggleBtn.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = container.Position
            dragDistance = 0
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            dragDistance = delta.Magnitude
            container.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y
            )
        end
    end)

    toggleBtn.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            if dragging then
                dragging = false
                if dragDistance < 6 then
                    isOpen = not isOpen
                    mainFrame.Visible = isOpen
                end
            end
        end
    end)
end

-- =============================================
--         CHEF'S KISS CORE LOGIC
-- =============================================

local function getScaleProp(humanoid, propName)
    local success, val = pcall(function()
        return humanoid[propName]
    end)
    if success then
        local num = tonumber(val)
        if num then return math.max(num, 0.5) end
        if typeof(val) == "Instance" and val:IsA("NumberValue") then
            return math.max(val.Value, 0.5)
        end
    end
    return 1.0
end

local function cleanupConnections()
    for i = #activeConnections, 1, -1 do
        if activeConnections[i] and activeConnections[i].Connected then activeConnections[i]:Disconnect() end
        activeConnections[i] = nil
    end
    for i = #heartbeatConns, 1, -1 do
        if heartbeatConns[i] and heartbeatConns[i].Connected then heartbeatConns[i]:Disconnect() end
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

-- Intelligent check to see if an accessory belongs to the head
local function isHeadAccessory(acc)
    local handle = acc:FindFirstChild("Handle")
    if not handle then return false end
    for _, att in pairs(handle:GetDescendants()) do
        if att:IsA("Attachment") then
            if att.Name == "HatAttachment" or att.Name == "HairAttachment" or att.Name == "FaceFrontAttachment" or att.Name == "FaceCenterAttachment" then
                return true
            end
        end
    end
    return false
end

local function applyHeadless(head)
    if not head or head:FindFirstChild("PerfectHeadlessTag") then return end
    local tag = Instance.new("BoolValue")
    tag.Name = "PerfectHeadlessTag"
    tag.Parent = head

    head.Transparency = 1

    -- Destroy face and shrink existing meshes (handles UGC heads perfectly)
    for _, child in pairs(head:GetChildren()) do
        if child:IsA("Decal") then
            child:Destroy()
        elseif child:IsA("SpecialMesh") then
            child.Scale = TINY_SCALE
        end
    end

    -- Apply invisible collision-less mesh
    local mesh = head:FindFirstChildOfClass("SpecialMesh") or Instance.new("SpecialMesh")
    mesh.Name = "HeadlessMesh"
    mesh.MeshType = Enum.MeshType.FileMesh
    mesh.MeshId = HEADLESS_MESH_ID
    mesh.Scale = TINY_SCALE
    mesh.Parent = head

    -- Keep head invisible permanently
    track(head:GetPropertyChangedSignal("Transparency"):Connect(function()
        if head.Transparency ~= 1 then head.Transparency = 1 end
    end))

    -- Hide head accessories perfectly
    local function checkAcc(c)
        if c:IsA("Accessory") and isHeadAccessory(c) then
            local handle = c:FindFirstChild("Handle")
            if handle then handle.Transparency = 1 end
        end
    end

    local character = head.Parent
    if character then
        for _, c in pairs(character:GetChildren()) do checkAcc(c) end
        track(character.ChildAdded:Connect(function(c)
            task.defer(function() checkAcc(c) end)
        end))
    end
end

local function applyKorbloxR6(character)
    local rightLeg = character:FindFirstChild("Right Leg")
    if not rightLeg or rightLeg:FindFirstChild("PerfectKorbloxTag") then return end
    
    local tag = Instance.new("BoolValue")
    tag.Name = "PerfectKorbloxTag"
    tag.Parent = rightLeg

    for _, child in ipairs(rightLeg:GetChildren()) do
        if child:IsA("SpecialMesh") or child:IsA("CharacterMesh") then
            child:Destroy()
        end
    end

    rightLeg.Color = DARK_GREY_COLOR

    track(rightLeg:GetPropertyChangedSignal("Color"):Connect(function()
        if rightLeg.Color ~= DARK_GREY_COLOR then rightLeg.Color = DARK_GREY_COLOR end
    end))

    local korbloxMesh = Instance.new("SpecialMesh")
    korbloxMesh.Name = "KorbloxMesh"
    korbloxMesh.MeshType = Enum.MeshType.FileMesh
    korbloxMesh.MeshId = KORBLOX_MESH_ID
    korbloxMesh.TextureId = KORBLOX_TEXTURE_ID
    korbloxMesh.Offset = Vector3.new(0, 0, 0) -- Native, untouched R6 offset
    korbloxMesh.Parent = rightLeg

    trackHeartbeat(RunService.Heartbeat:Connect(function()
        if not rightLeg or not rightLeg.Parent then return end
        if not korbloxMesh or not korbloxMesh.Parent then return end
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        if humanoid then
            local wScale = getScaleProp(humanoid, "BodyWidthScale")
            local hScale = getScaleProp(humanoid, "BodyHeightScale")
            local dScale = getScaleProp(humanoid, "BodyDepthScale")
            korbloxMesh.Scale = Vector3.new(wScale, hScale, dScale)
        end
    end))
end

local function applyKorbloxR15(character)
    local rightUpperLeg = character:FindFirstChild("RightUpperLeg")
    local rightLowerLeg = character:FindFirstChild("RightLowerLeg")
    local rightFoot     = character:FindFirstChild("RightFoot")
    local humanoid      = character:FindFirstChildOfClass("Humanoid")

    if not rightUpperLeg or not humanoid or rightUpperLeg:FindFirstChild("PerfectKorbloxTag") then return end
    
    local tag = Instance.new("BoolValue")
    tag.Name = "PerfectKorbloxTag"
    tag.Parent = rightUpperLeg

    -- Hide lower leg and foot completely, disable collisions to prevent physics glitches
    for _, p in pairs({rightLowerLeg, rightFoot}) do
        if p then
            p.Transparency = 1
            p.CanCollide = false
            for _, c in pairs(p:GetChildren()) do
                if c:IsA("SpecialMesh") or c:IsA("Decal") then c:Destroy() end
            end
        end
    end

    -- Clean upper leg for our mesh
    for _, c in pairs(rightUpperLeg:GetChildren()) do
        if c:IsA("SpecialMesh") or c:IsA("CharacterMesh") then c:Destroy() end
    end

    rightUpperLeg.Color = DARK_GREY_COLOR

    local mesh = Instance.new("SpecialMesh")
    mesh.Name = "KorbloxMesh"
    mesh.MeshType = Enum.MeshType.FileMesh
    mesh.MeshId = KORBLOX_MESH_ID
    mesh.TextureId = KORBLOX_TEXTURE_ID
    mesh.Parent = rightUpperLeg

    -- By attaching to the actual rig part, animations are 100% flawless and jitter-free
    trackHeartbeat(RunService.Heartbeat:Connect(function()
        if not character or not character.Parent then return end
        if not rightUpperLeg or not rightUpperLeg.Parent then return end
        if not mesh or not mesh.Parent then return end
        if not humanoid or not humanoid.Parent then return end

        -- Force hide lower parts in case of avatar update glitches
        if rightLowerLeg and rightLowerLeg.Parent and rightLowerLeg.Transparency ~= 1 then rightLowerLeg.Transparency = 1 end
        if rightFoot and rightFoot.Parent and rightFoot.Transparency ~= 1 then rightFoot.Transparency = 1 end
        if rightUpperLeg.Color ~= DARK_GREY_COLOR then rightUpperLeg.Color = DARK_GREY_COLOR end

        local curW = getScaleProp(humanoid, "BodyWidthScale")
        local curH = getScaleProp(humanoid, "BodyHeightScale")
        local curD = getScaleProp(humanoid, "BodyDepthScale")
        mesh.Scale = Vector3.new(curW, curH, curD)

        -- Live update Y offset based on slider
        mesh.Offset = Vector3.new(0, currentOffsetY, 0)
    end))
end

local function waitForRig(character)
    local humanoid = character:WaitForChild("Humanoid", 10)
    if not humanoid then return end
    if humanoid.RigType == Enum.HumanoidRigType.R15 then
        character:WaitForChild("RightUpperLeg", 10)
        character:WaitForChild("RightLowerLeg", 10)
        character:WaitForChild("RightFoot", 10)
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
    if head then applyHeadless(head) end

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
            task.defer(function() applyHeadless(child) end)
        end
    end))
end

-- =============================================
--              INITIALIZATION
-- =============================================

buildGUI()

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
