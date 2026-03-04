local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

-- ============ SETTINGS ============
local FLASHBACK_KEY = Enum.KeyCode.C
local MAX_RECORD_SECONDS = 60
local RECORD_TOOLS = true
local REWIND_SPEED = 1.5
-- ============ END OF SETTINGS ============

local LocalPlayer = Players.LocalPlayer
local Character = nil
local RootPart = nil
local Humanoid = nil

local Frames = {}
local MaxFrames = MAX_RECORD_SECONDS * 60
local Rewinding = false
local HoldingKey = false
local RewindTimer = 0

local SavedWalkSpeed = 16
local SavedJumpPower = 50
local SavedAutoRotate = true

local function RefreshCharacter()
	Character = LocalPlayer.Character
	if not Character then
		RootPart = nil
		Humanoid = nil
		return false
	end
	RootPart = Character:FindFirstChild("HumanoidRootPart")
	Humanoid = Character:FindFirstChildOfClass("Humanoid")
	return RootPart ~= nil and Humanoid ~= nil
end

local function IsAlive()
	if not Character or not Character.Parent then return false end
	if not RootPart or not RootPart.Parent then return false end
	if not Humanoid or Humanoid.Health <= 0 then return false end
	return true
end

local function StopRewind()
	if not Rewinding then return end
	Rewinding = false
	RewindTimer = 0

	if not IsAlive() then return end

	RootPart.Anchored = false
	RootPart.AssemblyLinearVelocity = Vector3.zero
	RootPart.AssemblyAngularVelocity = Vector3.zero

	Humanoid.WalkSpeed = SavedWalkSpeed
	Humanoid.JumpPower = SavedJumpPower
	Humanoid.AutoRotate = SavedAutoRotate
	Humanoid.PlatformStand = false
end

local function StartRewind()
	if not IsAlive() then return end
	if Rewinding then return end
	if #Frames == 0 then return end

	Rewinding = true
	RewindTimer = 0

	SavedWalkSpeed = Humanoid.WalkSpeed
	SavedJumpPower = Humanoid.JumpPower
	SavedAutoRotate = Humanoid.AutoRotate

	RootPart.Anchored = true
	Humanoid.WalkSpeed = 0
	Humanoid.JumpPower = 0
	Humanoid.AutoRotate = false
end

local function Record(dt)
	if not IsAlive() then return end

	if #Frames >= MaxFrames then
		table.remove(Frames, 1)
	end

	local entry = {
		CF = RootPart.CFrame,
		DT = dt,
	}

	if RECORD_TOOLS then
		entry.Tool = Character:FindFirstChildOfClass("Tool")
	end

	Frames[#Frames + 1] = entry
end

local function Rewind(dt)
	if not IsAlive() then
		StopRewind()
		return
	end

	if #Frames == 0 then
		StopRewind()
		return
	end

	RewindTimer = RewindTimer + (dt * REWIND_SPEED)

	while RewindTimer > 0 and #Frames > 0 do
		local index = #Frames
		local frame = Frames[index]
		if not frame then break end

		RewindTimer = RewindTimer - frame.DT
		Frames[index] = nil

		RootPart.CFrame = frame.CF

		if RECORD_TOOLS then
			local currentTool = Character:FindFirstChildOfClass("Tool")
			if frame.Tool and frame.Tool.Parent then
				if not currentTool then
					Humanoid:EquipTool(frame.Tool)
				end
			elseif currentTool then
				Humanoid:UnequipTools()
			end
		end
	end

	if #Frames == 0 then
		StopRewind()
	end
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == FLASHBACK_KEY then
		HoldingKey = true
		StartRewind()
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == FLASHBACK_KEY then
		HoldingKey = false
		StopRewind()
	end
end)

RunService.Heartbeat:Connect(function(dt)
	if not Character or not Character.Parent then
		if Rewinding then StopRewind() end
		RefreshCharacter()
		return
	end
	if not RootPart or not RootPart.Parent then
		if Rewinding then StopRewind() end
		RefreshCharacter()
		return
	end
	if not Humanoid or Humanoid.Health <= 0 then
		if Rewinding then StopRewind() end
		return
	end

	if Rewinding then
		Rewind(dt)
	else
		Record(dt)
	end
end)

LocalPlayer.CharacterAdded:Connect(function(char)
	task.wait(0.1)

	Rewinding = false
	HoldingKey = false
	RewindTimer = 0
	Frames = {}

	Character = char
	RootPart = char:WaitForChild("HumanoidRootPart", 5)
	Humanoid = char:WaitForChild("Humanoid", 5)

	if Humanoid then
		SavedWalkSpeed = Humanoid.WalkSpeed
		SavedJumpPower = Humanoid.JumpPower
		SavedAutoRotate = Humanoid.AutoRotate

		Humanoid.Died:Connect(function()
			StopRewind()
		end)
	end
end)

if LocalPlayer.Character then
	RefreshCharacter()
	if Humanoid then
		SavedWalkSpeed = Humanoid.WalkSpeed
		SavedJumpPower = Humanoid.JumpPower
		SavedAutoRotate = Humanoid.AutoRotate

		Humanoid.Died:Connect(function()
			StopRewind()
		end)
	end
end

print("====== FLASHBACK LOADED ======")
print("Hold [" .. FLASHBACK_KEY.Name .. "] to rewind")
print("Rewind speed: " .. REWIND_SPEED .. "x")
print("==============================")
