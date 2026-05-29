if _G.HK_HeadlessKorbloxLoaded then return end
_G.HK_HeadlessKorbloxLoaded = true

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local player = Players.LocalPlayer

local HEADLESS_MESH_ID = "rbxassetid://1095708"
local KORBLOX_MESH_ID = "rbxassetid://101851696"
local KORBLOX_TEXTURE_ID = "rbxassetid://101851254"
local DARK_GREY_COLOR = Color3.fromRGB(64, 64, 64)
local TINY_SCALE = Vector3.new(0.001, 0.001, 0.001)

-- Only Y offset is adjustable, strictly for R15
local currentOffsetY = -0.1

local activeConnections = {}
local heartbeatConns = {}
local applied = false

-- =============================================
--              MINI GUI BUILDER
-- =============================================

local function buildGUI()
    local old = player.PlayerGui:FindFirstChild("HK_Adjuster")
    if old then old:Destroy() end

    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "HK_Adjuster"
    screenGui.ResetOnSpawn = false
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screenGui.Parent = player.PlayerGui

    -- Fixed Container (Cannot be dragged)
    local container = Instance.new("Frame")
    container.Name = "Container"
    container.Size = UDim2.new(0, 235, 0, 34)
    container.Position = UDim2.new(0, 15, 0, 15) -- Fixed position
    container.BackgroundTransparency = 1
    container.Parent = screenGui

    -- Toggle Icon Button ("HK")
    local toggleBtn = Instance.new("TextButton")
    toggleBtn.Name = "Toggle"
    toggleBtn.Size = UDim2.new(0, 30, 0, 30)
    toggleBtn.Position = UDim2.new(0, 0, 0, 2)
    toggleBtn.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
    toggleBtn.Text = "HK"
    toggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    toggleBtn.Font = Enum.Font.GothamBold
    toggleBtn.TextSize = 12
    toggleBtn.BorderSizePixel = 0
    toggleBtn.AutoButtonColor = false
    toggleBtn.Parent = container

    local btnCorner = Instance.new("UICorner")
    btnCorner.CornerRadius = UDim.new(0, 8)
    btnCorner.Parent = toggleBtn

    local btnStroke = Instance.new("UIStroke")
    btnStroke.Color = Color3.fromRGB(200, 200, 200)
    btnStroke.Thickness = 1.2
    btnStroke.Parent = toggleBtn

    -- Slider Frame
    local mainFrame = Instance.new("Frame")
    mainFrame.Name = "SliderFrame"
    mainFrame.Size = UDim2.new(0, 198, 0, 30)
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
    fill.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    fill.BorderSizePixel = 0
    fill.Parent = track

    local fCorner = Instance.new("UICorner")
    fCorner.CornerRadius = UDim.new(0, 3)
    fCorner.Parent = fill

    local valLabel = Instance.new("TextLabel")
    valLabel.Name = "ValLabel"
    valLabel.Text = tostring(currentOffsetY)
    valLabel.Size = UDim2.new(0, 32, 1, 0)
    valLabel.Position = UDim2.new(1, -38, 0, 0)
    valLabel.BackgroundTransparency = 1
    valLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
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

    -- Toggle Logic (Just clicks, no dragging possible)
    toggleBtn.MouseButton1Click:Connect(function()
        mainFrame.Visible = not mainFrame.Visible
    end)
end

-- =============================================
--           CORE KORBLOX & HEADLESS LOGIC
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
    if not head or head:FindFirstChild("HK_HeadlessTag") then return end
    local tag = Instance.new("BoolValue")
    tag.Name = "HK_HeadlessTag"
    tag.Parent = head

    head.Transparency = 1

    for _, child in pairs(head:GetChildren()) do
        if child:IsA("Decal") then
            child:Destroy()
        elseif child:IsA("SpecialMesh") then
            child.Scale = TINY_SCALE
        end
    end

    local mesh = head:FindFirstChildOfClass("SpecialMesh") or Instance.new("SpecialMesh")
    mesh.Name = "HeadlessMesh"
    mesh.MeshType = Enum.MeshType.FileMesh
    mesh.MeshId = HEADLESS_MESH_ID
    mesh.Scale = TINY_SCALE
    mesh.Parent = head

    track(head:GetPropertyChangedSignal("Transparency"):Connect(function()
        if head.Transparency ~= 1 then head.Transparency = 1 end
    end))

    local character = head.Parent
    if character then
        local function checkAcc(c)
            if c:IsA("Accessory") and isHeadAccessory(c) then
                local handle = c:FindFirstChild("Handle")
                if handle then handle.Transparency = 1 end
            end
        end

        for _, c in pairs(character:GetChildren()) do checkAcc(c) end
        track(character.ChildAdded:Connect(function(c)
            task.defer(function() checkAcc(c) end)
        end))
    end
end

local function applyKorbloxR6(character)
    local rightLeg = character:FindFirstChild("Right Leg")
    if not rightLeg or rightLeg:FindFirstChild("HK_KorbloxTag") then return end
    
    local tag = Instance.new("BoolValue")
    tag.Name = "HK_KorbloxTag"
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
    korbloxMesh.Offset = Vector3.new(0, 0, 0) -- Untouched R6 native look
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

    if not rightUpperLeg or not humanoid or rightUpperLeg:FindFirstChild("HK_KorbloxTag") then return end
    
    local tag = Instance.new("BoolValue")
    tag.Name = "HK_KorbloxTag"
    tag.Parent = rightUpperLeg

    -- Hide actual leg parts
    for _, p in pairs({rightUpperLeg, rightLowerLeg, rightFoot}) do
        if p then
            p.Transparency = 1
            p.CanCollide = false
            for _, c in pairs(p:GetChildren()) do
                if c:IsA("SpecialMesh") or c:IsA("Decal") then c:Destroy() end
            end
        end
    end

    -- Create the stable fake Korblox leg part
    local korbloxLeg = Instance.new("Part")
    korbloxLeg.Name = "KorbloxLeg"
    korbloxLeg.Size = Vector3.new(1, 1, 1)
    korbloxLeg.Anchored = false
    korbloxLeg.CanCollide = false
    korbloxLeg.Massless = true
    korbloxLeg.Color = DARK_GREY_COLOR
    korbloxLeg.Transparency = 0
    korbloxLeg.Parent = character

    local mesh = Instance.new("SpecialMesh")
    mesh.Name = "KorbloxMesh"
    mesh.MeshType = Enum.MeshType.FileMesh
    mesh.MeshId = KORBLOX_MESH_ID
    mesh.TextureId = KORBLOX_TEXTURE_ID
    mesh.Parent = korbloxLeg

    -- Align perfectly to the upper leg before welding
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

        -- Force hide real legs
        if rightUpperLeg.Transparency ~= 1 then rightUpperLeg.Transparency = 1 end
        if rightLowerLeg and rightLowerLeg.Parent and rightLowerLeg.Transparency ~= 1 then rightLowerLeg.Transparency = 1 end
        if rightFoot and rightFoot.Parent and rightFoot.Transparency ~= 1 then rightFoot.Transparency = 1 end

        local curW = getScaleProp(humanoid, "BodyWidthScale")
        local curH = getScaleProp(humanoid, "BodyHeightScale")
        local curD = getScaleProp(humanoid, "BodyDepthScale")
        mesh.Scale = Vector3.new(curW, curH, curD)

        -- Live update Y offset based on slider (R15 only)
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
