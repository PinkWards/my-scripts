local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local ghostEnabled = true

-- ====================
-- Ghost / CanCollide
-- ====================
local function setGhost(character, enabled)
	for _, v in ipairs(character:GetDescendants()) do
		if v:IsA("BasePart") then
			v.CanCollide = not enabled
		end
	end
end

local function onCharacterAdded(character)
	character:WaitForChild("HumanoidRootPart")
	setGhost(character, ghostEnabled)
end

if player.Character then
	onCharacterAdded(player.Character)
end

player.CharacterAdded:Connect(onCharacterAdded)

-- ====================
-- Velocity Clamp
-- ====================
local MAX_LIN = 80      -- max linear velocity
local MAX_ANG = 45      -- max angular velocity

RunService.Heartbeat:Connect(function()
	if not ghostEnabled then return end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if root then
		local lv = root.AssemblyLinearVelocity
		local av = root.AssemblyAngularVelocity

		if lv.Magnitude > MAX_LIN then
			root.AssemblyLinearVelocity = lv.Unit * MAX_LIN
		end
		if av.Magnitude > MAX_ANG then
			root.AssemblyAngularVelocity = av.Unit * MAX_ANG
		end
	end
end)

-- ====================
-- GUI Toggle
-- ====================
local gui = Instance.new("ScreenGui")
gui.Name = "GhostToggleGui"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

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
	if player.Character then
		setGhost(player.Character, ghostEnabled)
	end
end)
