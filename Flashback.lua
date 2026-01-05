--[[
    ====== FLASHBACK SCRIPT (FRAME-PERFECT REWIND) ======
    Hold C to rewind time!
    ✓ Frame-perfect playback
    ✓ Proper animation recording
    ✓ Correct speed (1:1 with recording)
]]

-- ============ SETTINGS ============

local FLASHBACK_KEY = Enum.KeyCode.C
local FLASHBACK_LENGTH = 60          -- Seconds of recording
local REVERSE_VELOCITY = true         
local RECORD_TOOLS = true             
local RESTORE_HEALTH = true           

-- Rewind speed: 1.0 = exact same speed as recorded
local REWIND_SPEED = 1.0

-- ============ END OF SETTINGS ============

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local LP = Players.LocalPlayer
local frames = {}
local maxFrames = FLASHBACK_LENGTH * 60

-- Character references
local Character = nil
local HRP = nil
local Humanoid = nil
local Animator = nil

local flashback = {
    lastinput = false, 
    canrevert = true, 
    active = false,
    frameIndex = 0,        -- Current frame position (float for smooth speed)
    wasRewinding = false,  -- Track if we were rewinding last frame
}

-- Update character references
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

-- Get all Motor6Ds in character (these control animations)
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

-- Stop all animations
local function StopAnimations()
    if not Animator then return end
    
    for _, track in pairs(Animator:GetPlayingAnimationTracks()) do
        track:AdjustSpeed(0)  -- Pause instead of stop to keep pose
    end
end

-- Resume all animations
local function ResumeAnimations()
    if not Animator then return end
    
    for _, track in pairs(Animator:GetPlayingAnimationTracks()) do
        track:AdjustSpeed(1)
    end
end

function flashback:Advance(allowinput)
    if not HRP or not HRP.Parent then return end
    if not Humanoid or Humanoid.Health <= 0 then return end
    
    -- Remove old frames when limit reached
    if #frames >= maxFrames then
        table.remove(frames, 1)
    end
    
    if allowinput and not self.canrevert then
        self.canrevert = true
    end
    
    if self.lastinput then
        Humanoid.PlatformStand = false
        self.lastinput = false
    end
    
    -- Resume animations if we were rewinding
    if self.wasRewinding then
        ResumeAnimations()
        self.wasRewinding = false
    end
    
    -- Reset frame index to end
    self.frameIndex = 0
    
    -- Record current frame
    local frameData = {
        CFrame = HRP.CFrame,
        Velocity = HRP.AssemblyLinearVelocity,
        AngularVelocity = HRP.AssemblyAngularVelocity,
        State = Humanoid:GetState(),
        Health = Humanoid.Health,
        Timestamp = tick(),  -- Record actual time
    }
    
    -- Record Motor6D transforms (this captures the actual animation pose)
    frameData.Motors = {}
    for _, motor in pairs(GetMotor6Ds()) do
        frameData.Motors[motor] = {
            Transform = motor.Transform,
            C0 = motor.C0,
            C1 = motor.C1,
        }
    end
    
    -- Record body part CFrames as backup
    frameData.BodyParts = {}
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

function flashback:Revert(deltaTime)
    if not HRP or not HRP.Parent then return end
    if not Humanoid or Humanoid.Health <= 0 then return end
    
    local numFrames = #frames
    
    if numFrames == 0 or not self.canrevert then
        self.canrevert = false
        self:Advance(false)
        return
    end
    
    self.lastinput = true
    self.wasRewinding = true
    
    -- Stop animations so we can control the pose manually
    StopAnimations()
    
    -- Initialize frame index if starting rewind
    if self.frameIndex == 0 then
        self.frameIndex = numFrames
    end
    
    -- Move backwards through frames based on speed and delta time
    -- deltaTime normalized to 60 FPS (0.0167 seconds per frame)
    local frameStep = REWIND_SPEED * (deltaTime / 0.0167)
    self.frameIndex = self.frameIndex - frameStep
    
    -- Clamp to valid range
    if self.frameIndex < 1 then
        self.frameIndex = 1
        -- Remove consumed frames
        local framesToRemove = numFrames - 1
        for i = 1, framesToRemove do
            table.remove(frames, 1)
        end
        self.frameIndex = 1
    end
    
    -- Get the frame to display (integer index)
    local targetIndex = math.floor(self.frameIndex)
    targetIndex = math.clamp(targetIndex, 1, numFrames)
    
    local lastframe = frames[targetIndex]
    if not lastframe then return end
    
    -- Remove frames we've passed
    while #frames > math.ceil(self.frameIndex) + 1 do
        frames[#frames] = nil
    end
    
    -- ========== APPLY FRAME (EXACT) ==========
    
    -- Set exact position
    HRP.CFrame = lastframe.CFrame
    
    -- Set velocity
    if REVERSE_VELOCITY then
        HRP.AssemblyLinearVelocity = -lastframe.Velocity
        HRP.AssemblyAngularVelocity = -(lastframe.AngularVelocity or Vector3.zero)
    else
        HRP.AssemblyLinearVelocity = Vector3.zero
        HRP.AssemblyAngularVelocity = Vector3.zero
    end
    
    -- Apply Motor6D transforms (this restores the exact animation pose!)
    if lastframe.Motors then
        for motor, data in pairs(lastframe.Motors) do
            if motor and motor.Parent then
                motor.Transform = data.Transform
            end
        end
    end
    
    -- Apply body part CFrames as backup
    if lastframe.BodyParts then
        for part, cf in pairs(lastframe.BodyParts) do
            if part and part.Parent and part ~= HRP then
                -- Only apply if not controlled by Motor6D
                local hasMotor = false
                for _, child in pairs(part:GetChildren()) do
                    if child:IsA("Motor6D") then
                        hasMotor = true
                        break
                    end
                end
                if not hasMotor then
                    part.CFrame = cf
                end
            end
        end
    end
    
    -- Prevent physics from fighting us
    Humanoid.PlatformStand = true
    
    -- Apply humanoid state
    pcall(function()
        Humanoid:ChangeState(lastframe.State)
    end)
    
    -- Restore health
    if RESTORE_HEALTH and lastframe.Health then
        Humanoid.Health = lastframe.Health
    end
    
    -- Handle tools
    if RECORD_TOOLS then
        local currenttool = Character:FindFirstChildOfClass("Tool")
        if lastframe.Tool and lastframe.Tool.Parent then
            if not currenttool then
                Humanoid:EquipTool(lastframe.Tool)
            end
        elseif currenttool then
            Humanoid:UnequipTools()
        end
    end
end

-- Key input
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode == FLASHBACK_KEY then
        flashback.active = true
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if input.KeyCode == FLASHBACK_KEY then
        flashback.active = false
        flashback.frameIndex = 0
        
        -- Re-enable normal movement
        if Humanoid then
            Humanoid.PlatformStand = false
        end
        ResumeAnimations()
    end
end)

-- Main loop with delta time
RunService.Heartbeat:Connect(function(deltaTime)
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
        flashback:Revert(deltaTime)
    else
        flashback:Advance(true)
    end
end)

-- Reset on respawn
LP.CharacterAdded:Connect(function(char)
    task.wait(0.1)
    
    frames = {}
    flashback.canrevert = true
    flashback.active = false
    flashback.lastinput = false
    flashback.frameIndex = 0
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
    
    print("[Flashback] Ready! Hold " .. FLASHBACK_KEY.Name .. " to rewind")
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

print("====== FLASHBACK SCRIPT LOADED ======")
print("Hold [" .. FLASHBACK_KEY.Name .. "] to rewind time!")
print("Speed: " .. REWIND_SPEED .. "x (1.0 = same speed)")
print("======================================")
