local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

-- ============ SETTINGS ============
local FLASHBACK_KEY = Enum.KeyCode.C
local MAX_RECORD_SECONDS = 60
local RECORD_TOOLS = true
-- ============ END OF SETTINGS ============

local LocalPlayer = Players.LocalPlayer
local Character = nil
local RootPart = nil
local Humanoid = nil

local RecordedFrames = {}
local MaxFrameCount = MAX_RECORD_SECONDS * 60
local IsRewinding = false
local RewindTimer = 0
local SavedWalkSpeed = 16
local SavedJumpPower = 50

local function GetCharacter()
	Character = LocalPlayer.Character
	if not Character then
		RootPart = nil
		Humanoid = nil
		return false
	end
	RootPart = Character:FindFirstChild("HumanoidRootPart")
	Humanoid = Character:FindFirstChildOfClass("Humanoid")
	if RootPart and Humanoid then
		return true
	end
	return false
end

local function IsAlive()
	if not Character or not Character.Parent then
		return false
	end
	if not RootPart or not RootPart.Parent then
		return false
	end
	if not Humanoid or Humanoid.Health <= 0 then
		return false
	end
	return true
end

local function FreezeCharacter()
	if not Humanoid then return end
	SavedWalkSpeed = Humanoid.WalkSpeed
	SavedJumpPower = Humanoid.JumpPower
	Humanoid.WalkSpeed = 0
	Humanoid.JumpPower = 0
	Humanoid.AutoRotate = false
end

local function UnfreezeCharacter()
	if not Humanoid then return end
	Humanoid.WalkSpeed = SavedWalkSpeed
	Humanoid.JumpPower = SavedJumpPower
	Humanoid.AutoRotate = true
	Humanoid.PlatformStand = false
end

local function RecordFrame(dt)
	if not IsAlive() then
		return
	end

	if #RecordedFrames >= MaxFrameCount then
		table.remove(RecordedFrames, 1)
	end

	local data = {
		Position = RootPart.CFrame,
		Velocity = RootPart.AssemblyLinearVelocity,
		MoveState = Humanoid:GetState(),
		Standing = Humanoid.PlatformStand,
		Delta = dt,
	}

	if RECORD_TOOLS then
		data.HeldTool = Character:FindFirstChildOfClass("Tool")
	end

	RecordedFrames[#RecordedFrames + 1] = data
end

local function PlaybackFrames(dt)
	if not IsAlive() then
		return
	end

	local count = #RecordedFrames
	if count == 0 then
		return
	end

	RewindTimer = RewindTimer + dt

	while RewindTimer > 0 and #RecordedFrames > 0 do
		count = #RecordedFrames
		local frame = RecordedFrames[count]

		if not frame then break end

		RewindTimer = RewindTimer - frame.Delta
		RecordedFrames[count] = nil

		RootPart.CFrame = frame.Position
		RootPart.AssemblyLinearVelocity = -frame.Velocity * 0.3

		Humanoid:ChangeState(frame.MoveState)
		Humanoid.PlatformStand = frame.Standing

		if RECORD_TOOLS then
			local currentTool = Character:FindFirstChildOfClass("Tool")
			if frame.HeldTool and frame.HeldTool.Parent then
				if not currentTool then
					Humanoid:EquipTool(frame.HeldTool)
				end
			elseif currentTool then
				Humanoid:UnequipTools()
			end
		end
	end
end

UserInputService.InputBegan:Connect(function(input, typing)
	if typing then
		return
	end
	if input.KeyCode == FLASHBACK_KEY then
		IsRewinding = true
		RewindTimer = 0
		FreezeCharacter()
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == FLASHBACK_KEY then
		IsRewinding = false
		RewindTimer = 0
		UnfreezeCharacter()
	end
end)

RunService.Heartbeat:Connect(function(deltaTime)
	if not Character or not Character.Parent then
		GetCharacter()
		return
	end
	if not RootPart or not RootPart.Parent then
		GetCharacter()
		return
	end
	if not Humanoid or Humanoid.Health <= 0 then
		return
	end

	if IsRewinding then
		PlaybackFrames(deltaTime)
	else
		RecordFrame(deltaTime)
	end
end)

LocalPlayer.CharacterAdded:Connect(function(newCharacter)
	task.wait(0.1)

	RecordedFrames = {}
	IsRewinding = false
	RewindTimer = 0

	Character = newCharacter
	RootPart = newCharacter:WaitForChild("HumanoidRootPart", 5)
	Humanoid = newCharacter:WaitForChild("Humanoid", 5)

	if Humanoid then
		SavedWalkSpeed = Humanoid.WalkSpeed
		SavedJumpPower = Humanoid.JumpPower

		Humanoid.Died:Connect(function()
			IsRewinding = false
		end)
	end
end)

if LocalPlayer.Character then
	GetCharacter()
	if Humanoid then
		SavedWalkSpeed = Humanoid.WalkSpeed
		SavedJumpPower = Humanoid.JumpPower

		Humanoid.Died:Connect(function()
			IsRewinding = false
		end)
	end
end

print("====== FLASHBACK LOADED ======")
print("Hold [" .. FLASHBACK_KEY.Name .. "] to rewind")
print("==============================")
