local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")

local player = Players.LocalPlayer
local GROUP_NAME = "LocalPlayerGhost"
local DEFAULT_GROUP = "Default"

local ghostEnabled = true

pcall(function()
	PhysicsService:CreateCollisionGroup(GROUP_NAME)
end)

PhysicsService:CollisionGroupSetCollidable(GROUP_NAME, GROUP_NAME, false)

local function setCharacterCollision(character, enabled)
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") then
			PhysicsService:SetPartCollisionGroup(part, enabled and GROUP_NAME or DEFAULT_GROUP)
		end
	end
end

local function onCharacterAdded(character)
	character:WaitForChild("HumanoidRootPart")
	setCharacterCollision(character, ghostEnabled)
end

if player.Character then
	onCharacterAdded(player.Character)
end

player.CharacterAdded:Connect(onCharacterAdded)

local gui = Instance.new("ScreenGui")
gui.Name = "GhostToggleGui"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

local button = Instance.new("TextButton")
button.Size = UDim2.fromOffset(120, 32)
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
	if player.Character then
		setCharacterCollision(player.Character, ghostEnabled)
	end
end)
