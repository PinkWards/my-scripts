local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer
local Workspace = game:GetService("Workspace")

-- Constants
local MAX_LIN = 80      -- max linear velocity
local MAX_ANG = 45      -- max angular velocity
local SUSPICIOUS_RADIUS = 100 -- radius to check for suspicious parts
local MAX_PARTS = 100   -- max number of parts allowed to be controlled

-- Variables
local ghostEnabled = true  -- Start with ghost mode enabled
local suspiciousParts = {}

-- ====================
-- Ghost / CanCollide
-- ====================
local function setGhost(character, enabled)
    for _, part in ipairs(character:GetDescendants()) do
        if part:IsA("BasePart") then
            part.CanCollide = not enabled
        end
    end
end

local function onCharacterAdded(character)
    character:WaitForChild("HumanoidRootPart")
    setGhost(character, ghostEnabled)
end

if LocalPlayer.Character then
    onCharacterAdded(LocalPlayer.Character)
end

LocalPlayer.CharacterAdded:Connect(onCharacterAdded)

-- ====================
-- Velocity Clamp
-- ====================
local function clampVelocity(root)
    local lv = root.AssemblyLinearVelocity
    local av = root.AssemblyAngularVelocity

    if lv.Magnitude > MAX_LIN then
        root.AssemblyLinearVelocity = lv.Unit * MAX_LIN
    end
    if av.Magnitude > MAX_ANG then
        root.AssemblyAngularVelocity = av.Unit * MAX_ANG
    end
end

RunService.RenderStepped:Connect(function()
    if not LocalPlayer.Character then return end
    local root = LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if root then
        clampVelocity(root)
    end
end)

-- ====================
-- Detect and Remove Malicious Parts
-- ====================
local function isSuspiciousPart(part)
    if part:IsA("BasePart") and not part.Anchored and part:IsDescendantOf(Workspace) then
        if part.CustomPhysicalProperties.Density == 0 and part.CustomPhysicalProperties.Friction == 0 and part.CustomPhysicalProperties.Elasticity == 0 and part.CustomPhysicalProperties.FrictionWeight == 0 and part.CustomPhysicalProperties.ElasticityWeight == 0 then
            return true
        end
    end
    return false
end

local function checkForSuspiciousParts()
    local count = 0
    for _, part in ipairs(Workspace:GetDescendants()) do
        if isSuspiciousPart(part) then
            if not table.find(suspiciousParts, part) then
                table.insert(suspiciousParts, part)
                count = count + 1
                if count > MAX_PARTS then
                    warn("Detected excessive suspicious parts. Removing them.")
                    for _, suspiciousPart in ipairs(suspiciousParts) do
                        suspiciousPart:Destroy()
                    end
                    suspiciousParts = {}
                    break
                end
            end
        end
    end
end

RunService.Stepped:Connect(function()
    if #suspiciousParts < MAX_PARTS then
        checkForSuspiciousParts()
    end
end)

-- ====================
-- GUI Toggle
-- ====================
local gui = Instance.new("ScreenGui")
gui.Name = "GhostToggleGui"
gui.ResetOnSpawn = false
gui.Parent = LocalPlayer:WaitForChild("PlayerGui")

local button = Instance.new("TextButton")
button.Size = UDim2.fromOffset(140, 32)
button.Position = UDim2.new(0, 12, 0.5, -16)
button.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
button.TextColor3 = Color3.fromRGB(255, 255, 255)
button.TextScaled = true
button.BorderSizePixel = 0
button.Parent = gui

local function updateButton()
    button.Text = ghostEnabled and "Ghost: ON" or "Ghost: OFF"
end

updateButton()

button.MouseButton1Click:Connect(function()
    ghostEnabled = not ghostEnabled
    updateButton()
    if LocalPlayer.Character then
        setGhost(LocalPlayer.Character, ghostEnabled)
    end
end)

-- ====================
-- Monitor and Log Suspicious Activity
-- ====================
local function logSuspiciousActivity(message)
    print("[Anti-SuperRings] " .. message)
    -- Optionally, send logs to a server or another service for further analysis
end

RunService.Stepped:Connect(function()
    if #suspiciousParts > MAX_PARTS then
        logSuspiciousActivity("Excessive suspicious parts detected and removed.")
    end
end)

-- ====================
-- Additional Checks
-- ====================
local function onPartAdded(part)
    if isSuspiciousPart(part) then
        part:Destroy()
        logSuspiciousActivity("Destroyed suspicious part: " .. part:GetFullName())
    end
end

Workspace.DescendantAdded:Connect(onPartAdded)

local function onPartRemoved(part)
    local index = table.find(suspiciousParts, part)
    if index then
        table.remove(suspiciousParts, index)
    end
end

Workspace.DescendantRemoving:Connect(onPartRemoved)

-- ====================
-- Prevent SimulationRadius Abuse
-- ====================
local function onPropertyChange(property)
    if property == "SimulationRadius" then
        local currentRadius = gethiddenproperty(LocalPlayer, "SimulationRadius")
        if currentRadius > 1000 then
            sethiddenproperty(LocalPlayer, "SimulationRadius", 1000)
            logSuspiciousActivity("Abused SimulationRadius detected and corrected.")
        end
    end
end

LocalPlayer:GetPropertyChangedSignal("SimulationRadius"):Connect(onPropertyChange)

-- ====================
-- Notify Player
-- ====================
game.StarterGui:SetCore("SendNotification", {
    Title = "Anti-SuperRings",
    Text = "Active and protecting you from super rings.",
    Icon = "rbxasset://textures/ui/GuiImagePlaceholder.png",
    Duration = 5
})

-- ====================
-- Disable Collisions with Other Players
-- ====================
local function disablePlayerCollisions()
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character then
            local character = player.Character
            for _, part in ipairs(character:GetDescendants()) do
                if part:IsA("BasePart") then
                    part.CanCollide = false
                end
            end
        end
    end
end

disablePlayerCollisions()

Players.PlayerAdded:Connect(function(player)
    player.CharacterAdded:Connect(function(character)
        for _, part in ipairs(character:GetDescendants()) do
            if part:IsA("BasePart") then
                part.CanCollide = false
            end
        end
    end)
end)

Players.PlayerRemoving:Connect(function(player)
    if player.Character then
        for _, part in ipairs(player.Character:GetDescendants()) do
            if part:IsA("BasePart") then
                part.CanCollide = true
            end
        end
    end
end)
