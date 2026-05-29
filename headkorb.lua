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
