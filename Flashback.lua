--[[
    ====== FLASHBACK SCRIPT (BACKWARD REPLAY) ======
    Hold C to run backwards in time!
    ✓ Same speed as you moved
    ✓ Animations play in reverse
    ✓ Looks like rewinding a video
]]

-- ============ SETTINGS ============

local FLASHBACK_KEY = Enum.KeyCode.C
local FLASHBACK_LENGTH = 60
local RECORD_TOOLS = true             
local RESTORE_HEALTH = true           

-- ============ END OF SETTINGS ============

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local LP = Players.LocalPlayer
local frames = {}
local maxFrames = FLASHBACK_LENGTH * 60

local Character = nil
local HRP = nil
local Humanoid = nil
local Animator = nil

local flashback = {
    active = false,
    canrevert = true,
    wasRewinding = false,
}

local function UpdateCharacter()
    Character = LP.Character
    if not Character then
        HRP = nil
        Humanoid = nil
        Animator = nil
        return false
    end
    
    HRP = Character:FindFirstChild("HumanoidRootPart")
    Humanoid = Character:FindFirstChildOfClass("Humanoid")
    
    if Humanoid then
        Animator = Humanoid:FindFirstChildOfClass("Animator")
    end
    
    return HRP ~= nil and Humanoid ~= nil
end

local function GetMotor6Ds()
    local motors = {}
    if not Character then return motors end
    
    for _, desc in pairs(Character:GetDescendants()) do
        if desc:IsA("Motor6D") then
            table.insert(motors, desc)
        end
    end
    return motors
end

local function StopAnimations()
    if not Animator then return end
    for _, track in pairs(Animator:GetPlayingAnimationTracks()) do
        track:AdjustSpeed(0)
    end
end

local function ResumeAnimations()
    if not Animator then return end
    for _, track in pairs(Animator:GetPlayingAnimationTracks()) do
        track:AdjustSpeed(1)
    end
end

function flashback:Record()
    if not HRP or not HRP.Parent then return end
    if not Humanoid or Humanoid.Health <= 0 then return end
    
    -- Remove oldest frame if full
    if #frames >= maxFrames then
        table.remove(frames, 1)
    end
    
    if not self.canrevert then
        self.canrevert = true
    end
    
    -- Resume animations after rewind
    if self.wasRewinding then
        Humanoid.PlatformStand = false
        ResumeAnimations()
        self.wasRewinding = false
    end
    
    -- Record frame
    local frameData = {
        CFrame = HRP.CFrame,
        Velocity = HRP.AssemblyLinearVelocity,
        AngularVelocity = HRP.AssemblyAngularVelocity,
        State = Humanoid:GetState(),
        Health = Humanoid.Health,
        Motors = {},
        BodyParts = {},
    }
    
    -- Record Motor6D transforms (animation pose)
    for _, motor in pairs(GetMotor6Ds()) do
        frameData.Motors[motor] = motor.Transform
    end
    
    -- Record body parts
    for _, part in pairs(Character:GetDescendants()) do
        if part:IsA("BasePart") then
            frameData.BodyParts[part] = part.CFrame
        end
    end
    
    if RECORD_TOOLS then
        frameData.Tool = Character:FindFirstChildOfClass("Tool")
    end
    
    frames[#frames + 1] = frameData
end

function flashback:Playback()
    if not HRP or not HRP.Parent then return end
    if not Humanoid or Humanoid.Health <= 0 then return end
    
    -- No frames left
    if #frames == 0 then
        self.canrevert = false
        return
    end
    
    if not self.canrevert then
        return
    end
    
    self.wasRewinding = true
    
    -- Stop animator from overriding our pose
    StopAnimations()
    
    -- Get last frame and remove it (1 frame per heartbeat = same speed)
    local frame = frames[#frames]
    frames[#frames] = nil
    
    if not frame then return end
    
    -- ========== APPLY FRAME EXACTLY ==========
    
    -- Position
    HRP.CFrame = frame.CFrame
    
    -- Reverse velocity (so you move backwards)
    HRP.AssemblyLinearVelocity = -frame.Velocity
    HRP.AssemblyAngularVelocity = -(frame.AngularVelocity or Vector3.zero)
    
    -- Apply Motor6D transforms (exact animation pose)
    for motor, transform in pairs(frame.Motors) do
        if motor and motor.Parent then
            motor.Transform = transform
        end
    end
    
    -- Apply body part positions
    for part, cf in pairs(frame.BodyParts) do
        if part and part.Parent and part ~= HRP then
            part.CFrame = cf
        end
    end
    
    -- Prevent physics interference
    Humanoid.PlatformStand = true
    
    -- State
    pcall(function()
        Humanoid:ChangeState(frame.State)
    end)
    
    -- Health
    if RESTORE_HEALTH and frame.Health then
        Humanoid.Health = frame.Health
    end
    
    -- Tools
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

-- Input
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode == FLASHBACK_KEY then
        flashback.active = true
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if input.KeyCode == FLASHBACK_KEY then
        flashback.active = false
        
        if Humanoid then
            Humanoid.PlatformStand = false
        end
        ResumeAnimations()
    end
end)

-- Main loop (Heartbeat runs ~60 times per second, same as recording)
RunService.Heartbeat:Connect(function()
    if not Character or not Character.Parent then
        UpdateCharacter()
        return
    end
    
    if not HRP or not HRP.Parent then
        UpdateCharacter()
        return
    end
    
    if not Humanoid or Humanoid.Health <= 0 then
        return
    end
    
    if flashback.active then
        flashback:Playback()  -- Play 1 frame backward
    else
        flashback:Record()    -- Record 1 frame
    end
end)

-- Reset on respawn
LP.CharacterAdded:Connect(function(char)
    task.wait(0.1)
    
    frames = {}
    flashback.canrevert = true
    flashback.active = false
    flashback.wasRewinding = false
    
    Character = char
    HRP = char:WaitForChild("HumanoidRootPart", 5)
    Humanoid = char:WaitForChild("Humanoid", 5)
    
    if Humanoid then
        Animator = Humanoid:FindFirstChildOfClass("Animator")
        Humanoid.Died:Connect(function()
            flashback.active = false
            flashback.canrevert = false
        end)
    end
    
    print("[Flashback] Ready! Hold " .. FLASHBACK_KEY.Name .. " to run backwards")
end)

-- Initial setup
if LP.Character then
    UpdateCharacter()
    if Humanoid then
        Humanoid.Died:Connect(function()
            flashback.active = false
            flashback.canrevert = false
        end)
    end
end

print("====== BACKWARD REPLAY LOADED ======")
print("Hold [" .. FLASHBACK_KEY.Name .. "] to run backwards!")
print("=====================================")
