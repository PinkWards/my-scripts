local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local player = Players.LocalPlayer

-- Mesh IDs
local KORBLOX_MESH_ID = "rbxassetid://101851696"
local KORBLOX_TEXTURE_ID = "rbxassetid://101851684"

-- Color options
local COLORS = {
    WHITE = Color3.fromRGB(255, 255, 255),
    BLACK = Color3.fromRGB(25, 25, 25)
}

local currentColor = COLORS.WHITE
local isWhite = true
local isApplying = false

-- Store connections for cleanup
local korbloxConnections = {}

-----------------------
-- APPLY FUNCTIONS
-----------------------

local function makeHeadless(character)
    local head = character:FindFirstChild("Head")
    if not head then return end

    head.Transparency = 1
    head.CanCollide = false

    for _, child in ipairs(head:GetChildren()) do
        if child:IsA("Decal") and child.Name == "face" then
            child:Destroy()
        end
    end
end

local function applyKorbloxLeg(character)
    if isApplying then return end
    isApplying = true
    
    local humanoid = character:FindFirstChild("Humanoid")
    if not humanoid then 
        isApplying = false
        return 
    end

    local rightLeg

    if humanoid.RigType == Enum.HumanoidRigType.R15 then
        rightLeg = character:FindFirstChild("RightUpperLeg")
        
        local lowerLeg = character:FindFirstChild("RightLowerLeg")
        local foot = character:FindFirstChild("RightFoot")
        
        if lowerLeg then lowerLeg.Transparency = 1 end
        if foot then foot.Transparency = 1 end
    else
        rightLeg = character:FindFirstChild("Right Leg")
    end

    if not rightLeg then 
        isApplying = false
        return 
    end

    -- Check if already applied
    local existingMesh = rightLeg:FindFirstChild("KorbloxMesh")
    if existingMesh then
        existingMesh.VertexColor = Vector3.new(currentColor.R, currentColor.G, currentColor.B)
        isApplying = false
        return
    end

    -- Remove other meshes
    for _, child in ipairs(rightLeg:GetChildren()) do
        if child:IsA("SpecialMesh") or child:IsA("CharacterMesh") then
            child:Destroy()
        end
    end

    local mesh = Instance.new("SpecialMesh")
    mesh.Name = "KorbloxMesh"
    mesh.MeshType = Enum.MeshType.FileMesh
    mesh.MeshId = KORBLOX_MESH_ID
    mesh.TextureId = KORBLOX_TEXTURE_ID
    mesh.Scale = Vector3.new(1, 1, 1)
    mesh.VertexColor = Vector3.new(currentColor.R, currentColor.G, currentColor.B)
    mesh.Parent = rightLeg
    
    isApplying = false
end

local function applyEffects(character)
    if not character then return end
    
    local humanoid = character:FindFirstChild("Humanoid")
    if not humanoid then return end
    
    makeHeadless(character)
    applyKorbloxLeg(character)
end

local function updateColor()
    local character = player.Character
    if not character then return end
    
    local humanoid = character:FindFirstChild("Humanoid")
    if not humanoid then return end
    
    local rightLeg
    if humanoid.RigType == Enum.HumanoidRigType.R15 then
        rightLeg = character:FindFirstChild("RightUpperLeg")
    else
        rightLeg = character:FindFirstChild("Right Leg")
    end
    
    if not rightLeg then return end
    
    local mesh = rightLeg:FindFirstChild("KorbloxMesh")
    if mesh then
        mesh.VertexColor = Vector3.new(currentColor.R, currentColor.G, currentColor.B)
    end
end

local function setupCharacter(character)
    task.wait(0.5)
    applyEffects(character)
end

-----------------------
-- CREATE GUI
-----------------------

if player.PlayerGui:FindFirstChild("KorbloxGUI") then
    player.PlayerGui:FindFirstChild("KorbloxGUI"):Destroy()
end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "KorbloxGUI"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = player.PlayerGui

-- Main Frame
local MainFrame = Instance.new("Frame")
MainFrame.Name = "MainFrame"
MainFrame.Size = UDim2.new(0, 140, 0, 100)
MainFrame.Position = UDim2.new(0, 20, 0.5, -50)
MainFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
MainFrame.BorderSizePixel = 0
MainFrame.Active = true
MainFrame.Draggable = true
MainFrame.Parent = ScreenGui

local MainCorner = Instance.new("UICorner")
MainCorner.CornerRadius = UDim.new(0, 8)
MainCorner.Parent = MainFrame

-- Title Bar
local TitleBar = Instance.new("Frame")
TitleBar.Name = "TitleBar"
TitleBar.Size = UDim2.new(1, 0, 0, 28)
TitleBar.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
TitleBar.BorderSizePixel = 0
TitleBar.Parent = MainFrame

local TitleCorner = Instance.new("UICorner")
TitleCorner.CornerRadius = UDim.new(0, 8)
TitleCorner.Parent = TitleBar

local TitleFix = Instance.new("Frame")
TitleFix.Size = UDim2.new(1, 0, 0, 8)
TitleFix.Position = UDim2.new(0, 0, 1, -8)
TitleFix.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
TitleFix.BorderSizePixel = 0
TitleFix.Parent = TitleBar

local TitleText = Instance.new("TextLabel")
TitleText.Size = UDim2.new(1, -35, 1, 0)
TitleText.Position = UDim2.new(0, 10, 0, 0)
TitleText.BackgroundTransparency = 1
TitleText.Text = "Korblox"
TitleText.TextColor3 = Color3.fromRGB(255, 255, 255)
TitleText.TextSize = 13
TitleText.Font = Enum.Font.GothamBold
TitleText.TextXAlignment = Enum.TextXAlignment.Left
TitleText.Parent = TitleBar

-- Minimize Button
local MinimizeBtn = Instance.new("TextButton")
MinimizeBtn.Size = UDim2.new(0, 22, 0, 22)
MinimizeBtn.Position = UDim2.new(1, -25, 0, 3)
MinimizeBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
MinimizeBtn.BorderSizePixel = 0
MinimizeBtn.Text = "-"
MinimizeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
MinimizeBtn.TextSize = 16
MinimizeBtn.Font = Enum.Font.GothamBold
MinimizeBtn.Parent = TitleBar

local MinCorner = Instance.new("UICorner")
MinCorner.CornerRadius = UDim.new(0, 6)
MinCorner.Parent = MinimizeBtn

-- Content Frame
local ContentFrame = Instance.new("Frame")
ContentFrame.Name = "ContentFrame"
ContentFrame.Size = UDim2.new(1, -16, 0, 55)
ContentFrame.Position = UDim2.new(0, 8, 0, 35)
ContentFrame.BackgroundTransparency = 1
ContentFrame.Parent = MainFrame

-- White Button
local WhiteBtn = Instance.new("TextButton")
WhiteBtn.Name = "WhiteBtn"
WhiteBtn.Size = UDim2.new(0.48, 0, 0, 45)
WhiteBtn.Position = UDim2.new(0, 0, 0, 0)
WhiteBtn.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
WhiteBtn.BorderSizePixel = 0
WhiteBtn.Text = ""
WhiteBtn.Parent = ContentFrame

local WhiteCorner = Instance.new("UICorner")
WhiteCorner.CornerRadius = UDim.new(0, 6)
WhiteCorner.Parent = WhiteBtn

local WhiteLabel = Instance.new("TextLabel")
WhiteLabel.Size = UDim2.new(1, 0, 1, 0)
WhiteLabel.BackgroundTransparency = 1
WhiteLabel.Text = "White"
WhiteLabel.TextColor3 = Color3.fromRGB(0, 0, 0)
WhiteLabel.TextSize = 12
WhiteLabel.Font = Enum.Font.GothamBold
WhiteLabel.Parent = WhiteBtn

local WhiteStroke = Instance.new("UIStroke")
WhiteStroke.Thickness = 2
WhiteStroke.Color = Color3.fromRGB(0, 200, 0)
WhiteStroke.Parent = WhiteBtn

-- Black Button
local BlackBtn = Instance.new("TextButton")
BlackBtn.Name = "BlackBtn"
BlackBtn.Size = UDim2.new(0.48, 0, 0, 45)
BlackBtn.Position = UDim2.new(0.52, 0, 0, 0)
BlackBtn.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
BlackBtn.BorderSizePixel = 0
BlackBtn.Text = ""
BlackBtn.Parent = ContentFrame

local BlackCorner = Instance.new("UICorner")
BlackCorner.CornerRadius = UDim.new(0, 6)
BlackCorner.Parent = BlackBtn

local BlackLabel = Instance.new("TextLabel")
BlackLabel.Size = UDim2.new(1, 0, 1, 0)
BlackLabel.BackgroundTransparency = 1
BlackLabel.Text = "Black"
BlackLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
BlackLabel.TextSize = 12
BlackLabel.Font = Enum.Font.GothamBold
BlackLabel.Parent = BlackBtn

local BlackStroke = Instance.new("UIStroke")
BlackStroke.Thickness = 0
BlackStroke.Color = Color3.fromRGB(0, 200, 0)
BlackStroke.Parent = BlackBtn

-----------------------
-- GUI FUNCTIONS
-----------------------

local function updateSelection()
    if isWhite then
        WhiteStroke.Thickness = 2
        BlackStroke.Thickness = 0
    else
        WhiteStroke.Thickness = 0
        BlackStroke.Thickness = 2
    end
end

WhiteBtn.MouseButton1Click:Connect(function()
    isWhite = true
    currentColor = COLORS.WHITE
    updateSelection()
    updateColor()
end)

BlackBtn.MouseButton1Click:Connect(function()
    isWhite = false
    currentColor = COLORS.BLACK
    updateSelection()
    updateColor()
end)

-- Minimize Toggle
local isMinimized = false
local originalSize = MainFrame.Size

MinimizeBtn.MouseButton1Click:Connect(function()
    isMinimized = not isMinimized
    
    if isMinimized then
        TweenService:Create(MainFrame, TweenInfo.new(0.2), {
            Size = UDim2.new(0, 140, 0, 28)
        }):Play()
        ContentFrame.Visible = false
        MinimizeBtn.Text = "+"
    else
        TweenService:Create(MainFrame, TweenInfo.new(0.2), {
            Size = originalSize
        }):Play()
        task.wait(0.2)
        ContentFrame.Visible = true
        MinimizeBtn.Text = "-"
    end
end)

-----------------------
-- CHARACTER EVENTS
-----------------------

korbloxConnections.characterAdded = player.CharacterAdded:Connect(function(character)
    setupCharacter(character)
end)

-- Evade round detection
task.spawn(function()
    local gameFolder = workspace:WaitForChild("Game", 10)
    if not gameFolder then return end
    
    local playersFolder = gameFolder:WaitForChild("Players", 10)
    if not playersFolder then return end
    
    korbloxConnections.roundDetect = playersFolder.ChildAdded:Connect(function(child)
        if child.Name == player.Name then
            task.wait(0.5)
            if player.Character then
                applyEffects(player.Character)
            end
        end
    end)
end)

-- Watch for Game folder recreation (map change)
korbloxConnections.gameWatch = workspace.ChildAdded:Connect(function(child)
    if child.Name == "Game" then
        task.spawn(function()
            local playersFolder = child:WaitForChild("Players", 10)
            if not playersFolder then return end
            
            -- Disconnect old connection
            if korbloxConnections.roundDetect then
                korbloxConnections.roundDetect:Disconnect()
            end
            
            korbloxConnections.roundDetect = playersFolder.ChildAdded:Connect(function(playerChild)
                if playerChild.Name == player.Name then
                    task.wait(0.5)
                    if player.Character then
                        applyEffects(player.Character)
                    end
                end
            end)
        end)
    end
end)

-- Apply now
if player.Character then
    setupCharacter(player.Character)
end
