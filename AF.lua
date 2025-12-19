local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer
local Workspace = game:GetService("Workspace")

-- ==================== CONFIG ====================
local MAX_LIN = 55
local MAX_ANG = 30
local FLING_THRESHOLD = 150
local EXTREME_THRESHOLD = 300

-- ==================== STATE (cached) ====================
local ghostEnabled = true
local lastSafeCFrame = nil
local flingCount = 0
local cachedRoot = nil
local cachedChar = nil
local isProtecting = false

-- ==================== DANGEROUS CLASSES (fast lookup) ====================
local DANGEROUS = {
	BodyVelocity = true, BodyAngularVelocity = true, BodyForce = true,
	BodyThrust = true, BodyPosition = true, BodyGyro = true,
	RocketPropulsion = true, VectorForce = true, LineForce = true,
	Torque = true, LinearVelocity = true, AngularVelocity = true,
	AlignPosition = true, AlignOrientation = true
}

-- ==================== CORE FUNCTIONS ====================
local function updateCache()
	cachedChar = LocalPlayer.Character
	cachedRoot = cachedChar and cachedChar:FindFirstChild("HumanoidRootPart")
end

local function setGhost(char, enabled)
	if not char then return end
	for _, p in ipairs(char:GetDescendants()) do
		if p:IsA("BasePart") then
			p.CanCollide = not enabled
		end
	end
end

local function disablePlayerCollision(player)
	if player == LocalPlayer then return end
	local char = player.Character
	if not char then return end
	for _, p in ipairs(char:GetDescendants()) do
		if p:IsA("BasePart") then
			p.CanCollide = false
			p.CanTouch = false
		end
	end
end

-- ==================== MAIN PROTECTION (single loop) ====================
local frameCount = 0
local lastCleanup = 0

RunService.RenderStepped:Connect(function()
	if not cachedRoot then
		updateCache()
		return
	end
	
	-- Velocity protection (every frame - critical)
	local lv = cachedRoot.AssemblyLinearVelocity
	local av = cachedRoot.AssemblyAngularVelocity
	local linMag = lv.Magnitude
	local angMag = av.Magnitude
	
	-- Extreme fling - instant freeze + teleport
	if linMag > EXTREME_THRESHOLD then
		cachedRoot.AssemblyLinearVelocity = Vector3.zero
		cachedRoot.AssemblyAngularVelocity = Vector3.zero
		if lastSafeCFrame then
			cachedRoot.CFrame = lastSafeCFrame
		end
		flingCount += 1
		isProtecting = true
	-- High velocity - clamp hard
	elseif linMag > FLING_THRESHOLD then
		cachedRoot.AssemblyLinearVelocity = lv.Unit * (MAX_LIN * 0.5)
		cachedRoot.AssemblyAngularVelocity = Vector3.zero
		flingCount += 1
		isProtecting = true
	-- Normal clamp
	else
		if linMag > MAX_LIN then
			cachedRoot.AssemblyLinearVelocity = lv.Unit * MAX_LIN
		end
		if angMag > MAX_ANG then
			cachedRoot.AssemblyAngularVelocity = av.Unit * MAX_ANG
		end
		
		-- Save safe position when stable
		if linMag < 20 then
			lastSafeCFrame = cachedRoot.CFrame
		end
		isProtecting = false
	end
	
	-- Throttled tasks (every 6 frames = ~10Hz)
	frameCount += 1
	if frameCount >= 6 then
		frameCount = 0
		
		-- Ghost enforcement
		if ghostEnabled and cachedChar then
			for _, p in ipairs(cachedChar:GetChildren()) do
				if p:IsA("BasePart") and p.CanCollide then
					p.CanCollide = false
				end
			end
		end
	end
end)

-- ==================== LIGHTWEIGHT PART DETECTION ====================
local function isBadPart(part)
	if not part:IsA("BasePart") or part.Anchored then return false end
	
	local cpp = part.CustomPhysicalProperties
	if cpp and cpp.Density == 0 and cpp.Friction == 0 then
		return true
	end
	
	if part.AssemblyLinearVelocity.Magnitude > 500 then
		return true
	end
	
	return false
end

-- ==================== EVENT-BASED DETECTION (no polling) ====================
Workspace.DescendantAdded:Connect(function(obj)
	-- Quick class check first (fastest)
	local className = obj.ClassName
	
	-- Dangerous movers on player
	if DANGEROUS[className] then
		task.defer(function()
			if obj.Parent and cachedChar and obj:IsDescendantOf(cachedChar) then
				obj:Destroy()
			end
		end)
		return
	end
	
	-- Suspicious parts
	if className == "Part" or className == "MeshPart" or className == "UnionOperation" then
		task.defer(function()
			if obj.Parent and isBadPart(obj) then
				obj:Destroy()
			end
		end)
	end
end)

-- ==================== CHARACTER HANDLING ====================
local function onCharacterAdded(char)
	cachedChar = char
	local root = char:WaitForChild("HumanoidRootPart", 5)
	if not root then return end
	
	cachedRoot = root
	lastSafeCFrame = root.CFrame
	setGhost(char, ghostEnabled)
	
	-- Remove existing dangerous objects
	for _, obj in ipairs(char:GetDescendants()) do
		if DANGEROUS[obj.ClassName] then
			obj:Destroy()
		end
	end
	
	-- Fast listener for new parts
	char.DescendantAdded:Connect(function(obj)
		if DANGEROUS[obj.ClassName] then
			task.defer(obj.Destroy, obj)
		elseif obj:IsA("BasePart") and ghostEnabled then
			obj.CanCollide = false
		end
	end)
end

if LocalPlayer.Character then
	task.spawn(onCharacterAdded, LocalPlayer.Character)
end
LocalPlayer.CharacterAdded:Connect(onCharacterAdded)

-- ==================== PLAYER COLLISION (event-based) ====================
local function setupPlayer(player)
	if player == LocalPlayer then return end
	
	local function handleChar(char)
		task.wait()
		disablePlayerCollision(player)
		char.DescendantAdded:Connect(function(p)
			if p:IsA("BasePart") then
				p.CanCollide = false
				p.CanTouch = false
			end
		end)
	end
	
	if player.Character then handleChar(player.Character) end
	player.CharacterAdded:Connect(handleChar)
end

for _, p in ipairs(Players:GetPlayers()) do
	task.spawn(setupPlayer, p)
end
Players.PlayerAdded:Connect(setupPlayer)

-- ==================== SIMULATION RADIUS (throttled) ====================
if typeof(sethiddenproperty) == "function" then
	task.spawn(function()
		while task.wait(1) do
			pcall(sethiddenproperty, LocalPlayer, "SimulationRadius", 0)
		end
	end)
end

-- ==================== MINIMAL GUI ====================
local gui = Instance.new("ScreenGui")
gui.Name = "AntiFling"
gui.ResetOnSpawn = false
gui.Parent = LocalPlayer:WaitForChild("PlayerGui")

local frame = Instance.new("Frame")
frame.Size = UDim2.fromOffset(145, 70)
frame.Position = UDim2.new(0, 10, 0.5, -35)
frame.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
frame.BorderSizePixel = 0
frame.Parent = gui

local corner = Instance.new("UICorner", frame)
corner.CornerRadius = UDim.new(0, 6)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, 0, 0, 20)
title.BackgroundTransparency = 1
title.Text = "🛡️ ANTI-FLING"
title.TextColor3 = Color3.fromRGB(100, 200, 255)
title.Font = Enum.Font.GothamBold
title.TextSize = 12
title.Parent = frame

local btn = Instance.new("TextButton")
btn.Size = UDim2.new(0.9, 0, 0, 22)
btn.Position = UDim2.new(0.05, 0, 0, 22)
btn.BackgroundColor3 = Color3.fromRGB(40, 120, 40)
btn.Font = Enum.Font.GothamSemibold
btn.TextSize = 11
btn.TextColor3 = Color3.new(1, 1, 1)
btn.Text = "Ghost: ON"
btn.BorderSizePixel = 0
btn.Parent = frame

Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 4)

local status = Instance.new("TextLabel")
status.Size = UDim2.new(1, 0, 0, 16)
status.Position = UDim2.new(0, 0, 0, 48)
status.BackgroundTransparency = 1
status.Font = Enum.Font.Gotham
status.TextSize = 10
status.TextColor3 = Color3.fromRGB(120, 255, 120)
status.Text = "Blocked: 0"
status.Parent = frame

btn.MouseButton1Click:Connect(function()
	ghostEnabled = not ghostEnabled
	btn.Text = ghostEnabled and "Ghost: ON" or "Ghost: OFF"
	btn.BackgroundColor3 = ghostEnabled and Color3.fromRGB(40, 120, 40) or Color3.fromRGB(120, 40, 40)
	setGhost(cachedChar, ghostEnabled)
end)

-- Status update (very slow - 2Hz)
task.spawn(function()
	while task.wait(0.5) do
		status.Text = "Blocked: " .. flingCount
		status.TextColor3 = isProtecting and Color3.fromRGB(255, 100, 100) or Color3.fromRGB(120, 255, 120)
	end
end)

-- ==================== DONE ====================
pcall(function()
	game.StarterGui:SetCore("SendNotification", {
		Title = "Anti-Fling",
		Text = "Zero-lag protection active!",
		Duration = 3
	})
end)
