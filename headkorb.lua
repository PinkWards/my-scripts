-- Korblox Leg Script (R15 Adjuster + Mini GUI)
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local player = Players.LocalPlayer

local KORBLOX_MESH_ID = "rbxassetid://101851696"
local KORBLOX_TEXTURE_ID = "rbxassetid://101851254"
local DARK_GREY_COLOR = Color3.fromRGB(64, 64, 64)

local currentOffset = {
	Y = 0.19,
}

local activeConnections = {}
local heartbeatConns = {}
local applied = false

-- =============================================
--              MINI GUI
-- =============================================

local function buildGUI()
	local old = player.PlayerGui:FindFirstChild("KorbloxMiniGUI")
	if old then old:Destroy() end

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "KorbloxMiniGUI"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent = player.PlayerGui

	-- Toggle Icon Button (always visible)
	local toggleBtn = Instance.new("ImageButton")
	toggleBtn.Name = "ToggleBtn"
	toggleBtn.Size = UDim2.new(0, 40, 0, 40)
	toggleBtn.Position = UDim2.new(0, 12, 0.5, -20)
	toggleBtn.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	toggleBtn.BorderSizePixel = 0
	toggleBtn.Image = "rbxassetid://6031068420" -- gear/settings icon
	toggleBtn.ImageColor3 = Color3.fromRGB(255, 200, 80)
	toggleBtn.ZIndex = 10
	toggleBtn.Parent = screenGui

	local toggleCorner = Instance.new("UICorner")
	toggleCorner.CornerRadius = UDim.new(1, 0)
	toggleCorner.Parent = toggleBtn

	local toggleStroke = Instance.new("UIStroke")
	toggleStroke.Color = Color3.fromRGB(255, 200, 80)
	toggleStroke.Thickness = 1.5
	toggleStroke.Parent = toggleBtn

	-- Main panel (small, just the slider)
	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.Size = UDim2.new(0, 200, 0, 72)
	panel.Position = UDim2.new(0, 60, 0.5, -36)
	panel.BackgroundColor3 = Color3.fromRGB(22, 22, 22)
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Active = true
	panel.ZIndex = 9
	panel.Parent = screenGui

	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, 8)
	panelCorner.Parent = panel

	local panelStroke = Instance.new("UIStroke")
	panelStroke.Color = Color3.fromRGB(255, 200, 80)
	panelStroke.Thickness = 1
	panelStroke.Parent = panel

	-- Panel title
	local titleLabel = Instance.new("TextLabel")
	titleLabel.Text = "Korblox Y Offset"
	titleLabel.Size = UDim2.new(1, -10, 0, 18)
	titleLabel.Position = UDim2.new(0, 8, 0, 6)
	titleLabel.BackgroundTransparency = 1
	titleLabel.TextColor3 = Color3.fromRGB(255, 200, 80)
	titleLabel.TextSize = 11
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.ZIndex = 10
	titleLabel.Parent = panel

	-- Value box
	local valueBox = Instance.new("TextBox")
	valueBox.Size = UDim2.new(0, 48, 0, 18)
	valueBox.Position = UDim2.new(1, -56, 0, 6)
	valueBox.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
	valueBox.BorderSizePixel = 0
	valueBox.TextColor3 = Color3.fromRGB(255, 200, 80)
	valueBox.TextSize = 11
	valueBox.Font = Enum.Font.GothamBold
	valueBox.Text = tostring(currentOffset.Y)
	valueBox.ClearTextOnFocus = false
	valueBox.ZIndex = 10
	valueBox.Parent = panel

	local vbCorner = Instance.new("UICorner")
	vbCorner.CornerRadius = UDim.new(0, 4)
	vbCorner.Parent = valueBox

	-- Slider track
	local track = Instance.new("Frame")
	track.Name = "Track"
	track.Size = UDim2.new(1, -16, 0, 10)
	track.Position = UDim2.new(0, 8, 0, 34)
	track.BackgroundColor3 = Color3.fromRGB(55, 55, 55)
	track.BorderSizePixel = 0
	track.ZIndex = 10
	track.Parent = panel

	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius = UDim.new(0, 5)
	trackCorner.Parent = track

	-- Fill bar
	local fill = Instance.new("Frame")
	fill.BackgroundColor3 = Color3.fromRGB(255, 160, 0)
	fill.BorderSizePixel = 0
	fill.Size = UDim2.new(0, 0, 1, 0)
	fill.ZIndex = 11
	fill.Parent = track

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 5)
	fillCorner.Parent = fill

	-- Thumb
	local thumb = Instance.new("Frame")
	thumb.Size = UDim2.new(0, 16, 0, 16)
	thumb.AnchorPoint = Vector2.new(0.5, 0.5)
	thumb.BackgroundColor3 = Color3.fromRGB(255, 200, 80)
	thumb.BorderSizePixel = 0
	thumb.ZIndex = 12
	thumb.Parent = track

	local thumbCorner = Instance.new("UICorner")
	thumbCorner.CornerRadius = UDim.new(1, 0)
	thumbCorner.Parent = thumb

	-- Drag label hint
	local hintLabel = Instance.new("TextLabel")
	hintLabel.Text = "drag to adjust • -0.5 to 2"
	hintLabel.Size = UDim2.new(1, -10, 0, 14)
	hintLabel.Position = UDim2.new(0, 8, 0, 52)
	hintLabel.BackgroundTransparency = 1
	hintLabel.TextColor3 = Color3.fromRGB(120, 120, 120)
	hintLabel.TextSize = 9
	hintLabel.Font = Enum.Font.Gotham
	hintLabel.TextXAlignment = Enum.TextXAlignment.Left
	hintLabel.ZIndex = 10
	hintLabel.Parent = panel

	-- Dragging the panel
	local dragging, dragStart, startPos
	panel.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = input.Position
			startPos = panel.Position
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging then
			if input.UserInputType == Enum.UserInputType.MouseMovement
				or input.UserInputType == Enum.UserInputType.Touch then
				local delta = input.Position - dragStart
				panel.Position = UDim2.new(
					startPos.X.Scale,
					startPos.X.Offset + delta.X,
					startPos.Y.Scale,
					startPos.Y.Offset + delta.Y
				)
			end
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)

	-- Slider logic
	local MIN_Y, MAX_Y, STEP_Y = -0.5, 2, 0.01

	local function valueToAlpha(v)
		return math.clamp((v - MIN_Y) / (MAX_Y - MIN_Y), 0, 1)
	end

	local function alphaToValue(a)
		local raw = MIN_Y + a * (MAX_Y - MIN_Y)
		local snapped = math.round(raw / STEP_Y) * STEP_Y
		return math.clamp(snapped, MIN_Y, MAX_Y)
	end

	local function applyValue(v)
		v = math.clamp(v, MIN_Y, MAX_Y)
		local display = math.round(v * 10000) / 10000
		currentOffset.Y = display
		valueBox.Text = tostring(display)
		local alpha = valueToAlpha(v)
		fill.Size = UDim2.new(alpha, 0, 1, 0)
		thumb.Position = UDim2.new(alpha, 0, 0.5, 0)
	end

	applyValue(currentOffset.Y)

	local sliding = false

	local function updateFromInput(input)
		local abs = track.AbsolutePosition
		local sz = track.AbsoluteSize
		local relX = (input.Position.X - abs.X) / sz.X
		applyValue(alphaToValue(math.clamp(relX, 0, 1)))
	end

	track.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			sliding = true
			updateFromInput(input)
		end
	end)
	thumb.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			sliding = true
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if sliding then
			if input.UserInputType == Enum.UserInputType.MouseMovement
				or input.UserInputType == Enum.UserInputType.Touch then
				updateFromInput(input)
			end
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			sliding = false
		end
	end)

	valueBox.FocusLost:Connect(function()
		local num = tonumber(valueBox.Text)
		if num then
			applyValue(math.clamp(num, MIN_Y, MAX_Y))
		else
			valueBox.Text = tostring(currentOffset.Y)
		end
	end)

	-- Toggle open/close
	toggleBtn.MouseButton1Click:Connect(function()
		panel.Visible = not panel.Visible
	end)
end

-- =============================================
--           CORE LOGIC
-- =============================================

local function getScaleProp(humanoid, propName)
	local success, val = pcall(function() return humanoid[propName] end)
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

local function track(conn)
	activeConnections[#activeConnections + 1] = conn
	return conn
end

local function trackHeartbeat(conn)
	heartbeatConns[#heartbeatConns + 1] = conn
	return conn
end

-- =============================================
--  R6: Korblox on Right Leg (no Y adjustment)
-- =============================================

local function applyKorbloxR6(character)
	local rightLeg = character:FindFirstChild("Right Leg")
	if not rightLeg or rightLeg:FindFirstChild("KorbloxMesh") then return end

	for _, child in ipairs(rightLeg:GetChildren()) do
		if child:IsA("SpecialMesh") or child:IsA("CharacterMesh") then
			child:Destroy()
		end
	end

	rightLeg.Color = DARK_GREY_COLOR

	track(rightLeg:GetPropertyChangedSignal("Color"):Connect(function()
		if rightLeg.Color ~= DARK_GREY_COLOR then
			rightLeg.Color = DARK_GREY_COLOR
		end
	end))

	local korbloxMesh = Instance.new("SpecialMesh")
	korbloxMesh.Name = "KorbloxMesh"
	korbloxMesh.MeshType = Enum.MeshType.FileMesh
	korbloxMesh.MeshId = KORBLOX_MESH_ID
	korbloxMesh.TextureId = KORBLOX_TEXTURE_ID
	-- R6: fixed offset, no GUI adjustment
	korbloxMesh.Offset = Vector3.new(0, 0.19, 0)
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
		-- R6 keeps fixed offset, no GUI control
		korbloxMesh.Offset = Vector3.new(0, 0.19, 0)
	end))
end

-- =============================================
--  R15: Korblox on Right Leg (Y GUI-controlled)
-- =============================================

local function applyKorbloxR15(character)
	local rightUpperLeg = character:FindFirstChild("RightUpperLeg")
	local rightLowerLeg = character:FindFirstChild("RightLowerLeg")
	local rightFoot = character:FindFirstChild("RightFoot")
	local humanoid = character:FindFirstChildOfClass("Humanoid")

	if not rightUpperLeg or not humanoid then return end
	if character:FindFirstChild("KorbloxLeg") then return end

	local function hidePart(part)
		if not part then return end
		part.Transparency = 1
		part.CanCollide = false
		for _, child in ipairs(part:GetChildren()) do
			if child:IsA("SpecialMesh") or child:IsA("Decal") then
				child:Destroy()
			end
		end
	end

	hidePart(rightUpperLeg)
	hidePart(rightLowerLeg)
	hidePart(rightFoot)

	-- Invisible anchor part welded to RightUpperLeg
	local korbloxLeg = Instance.new("Part")
	korbloxLeg.Name = "KorbloxLeg"
	korbloxLeg.Size = Vector3.new(1, 1, 1)
	korbloxLeg.Anchored = false
	korbloxLeg.CanCollide = false
	korbloxLeg.Massless = true
	korbloxLeg.CastShadow = true
	korbloxLeg.Color = DARK_GREY_COLOR
	korbloxLeg.Transparency = 0
	korbloxLeg.Parent = character

	local mesh = Instance.new("SpecialMesh")
	mesh.Name = "KorbloxMesh"
	mesh.MeshType = Enum.MeshType.FileMesh
	mesh.MeshId = KORBLOX_MESH_ID
	mesh.TextureId = KORBLOX_TEXTURE_ID

	local wScale = getScaleProp(humanoid, "BodyWidthScale")
	local hScale = getScaleProp(humanoid, "BodyHeightScale")
	local dScale = getScaleProp(humanoid, "BodyDepthScale")
	mesh.Scale = Vector3.new(wScale, hScale, dScale)
	mesh.Parent = korbloxLeg

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

		-- Keep legs hidden
		if rightUpperLeg.Transparency ~= 1 then rightUpperLeg.Transparency = 1 end
		if rightLowerLeg and rightLowerLeg.Parent and rightLowerLeg.Transparency ~= 1 then
			rightLowerLeg.Transparency = 1
		end
		if rightFoot and rightFoot.Parent and rightFoot.Transparency ~= 1 then
			rightFoot.Transparency = 1
		end

		-- Compute total leg height
		local legHeight = rightUpperLeg.Size.Y
		if rightLowerLeg and rightLowerLeg.Parent then
			legHeight = legHeight + rightLowerLeg.Size.Y
		end
		if rightFoot and rightFoot.Parent then
			legHeight = legHeight + rightFoot.Size.Y
		end

		if legHeight > 0.1 then
			local curW = getScaleProp(humanoid, "BodyWidthScale")
			local curH = getScaleProp(humanoid, "BodyHeightScale")
			local curD = getScaleProp(humanoid, "BodyDepthScale")
			mesh.Scale = Vector3.new(curW, curH, curD)

			-- Base centering + GUI Y offset only
			local baseY = (rightUpperLeg.Size.Y / 2) - (legHeight / 2)
			mesh.Offset = Vector3.new(0, baseY + currentOffset.Y, 0)
		end
	end))
end

-- =============================================
--              INIT
-- =============================================

local function waitForRig(character)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid then return end
	if humanoid.RigType == Enum.HumanoidRigType.R15 then
		character:WaitForChild("RightUpperLeg", 10)
		character:WaitForChild("RightLowerLeg", 10)
		character:WaitForChild("RightFoot", 10)
		character:WaitForChild("HumanoidRootPart", 10)
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

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		if humanoid.RigType == Enum.HumanoidRigType.R6 then
			applyKorbloxR6(character)
		elseif humanoid.RigType == Enum.HumanoidRigType.R15 then
			applyKorbloxR15(character)
		end
	end
end

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
