--[[
    ====== FLASHBACK SCRIPT (FRAME-PERFECT REWIND) ======
    Hold C to rewind time!
    ✓ Frame-perfect playback
    ✓ Proper animation recording
    ✓ Correct speed
]]

-- ============ SETTINGS ============

local FLASHBACK_KEY = Enum.KeyCode.C
local FLASHBACK_LENGTH = 60
local REVERSE_VELOCITY = true         
local RECORD_TOOLS = true             
local RESTORE_HEALTH = true           

-- Rewind speed (frames consumed per heartbeat)
-- 1.0 = exact recorded speed (1 frame per heartbeat)
-- 2.0 = 2x faster
-- 3.0 = 3x faster
local REWIND_SPEED = 2.0  -- Adjust this if too slow/fast

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
    lastinput = false, 
    canrevert = true, 
    active = false,
    frameAccumulator = 0,
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

function flashback:Advance(allowinput)
    if not HRP or not HRP.Parent then return end
    if not Humanoid or Humanoid.Health <= 0 then return end
    
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
    
    if self.wasRewinding then
        ResumeAnimations()
        self.wasRewinding = false
    end
    
    self.frameAccumulator = 0
    
    local frameData = {
        CFrame = HRP.CFrame,
        Velocity = HRP.AssemblyLinearVelocity,
        AngularVelocity = HRP.AssemblyAngularVelocity,
        State = Humanoid:GetState(),
        Health = Humanoid.Health,
    }
    
    frameData.Motors = {}
    for _, motor in pairs(GetMotor6Ds()) do
        frameData.Motors[motor] = {
            Transform = motor.Transform,
        }
    end
    
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

function flashback:Revert()
    if not HRP or not HRP.Parent then return end
    if not Humanoid or Humanoid.Health <= 0 then return end
    
    if #frames == 0 or not self.canrevert then
        self.canrevert = false
        self:Advance(false)
        return
    end
    
    self.lastinput = true
    self.wasRewinding = true
    
    StopAnimations()
    
    -- Simple frame consumption based on REWIND_SPEED
    self.frameAccumulator = self.frameAccumulator + REWIND_SPEED
    
    local lastframe = nil
    
    -- Consume frames based on accumulated speed
    while self.frameAccumulator >= 1 and #frames > 0 do
        self.frameAccumulator = self.frameAccumulator - 1
        lastframe = frames[#frames]
        frames[#frames] = nil  -- Remove consumed frame
    end
    
    -- If speed < 1, just peek at last frame without consuming
    if not lastframe and #frames > 0 then
        lastframe = frames[#frames]
    end
    
    if not lastframe then return end
    
    -- ========== APPLY FRAME ==========
    
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
    
    -- Apply Motor6D transforms (restores exact animation pose)
    if lastframe.Motors then
        for motor, data in pairs(lastframe.Motors) do
            if motor and motor.Parent then
                motor.Transform = data.Transform
            end
        end
    end
    
    -- Apply body part CFrames
    if lastframe.BodyParts then
        for part, cf in pairs(lastframe.BodyParts) do
            if part and part.Parent and part ~= HRP then
                part.CFrame = cf
            end
        end
    end
    
    Humanoid.PlatformStand = true
    
    pcall(function()
        Humanoid:ChangeState(lastframe.State)
    end)
    
    if RESTORE_HEALTH and lastframe.Health then
        Humanoid.Health = lastframe.Health
    end
    
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

-- Input handling
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode == FLASHBACK_KEY then
        flashback.active = true
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if input.KeyCode == FLASHBACK_KEY then
        flashback.active = false
        flashback.frameAccumulator = 0
        
        if Humanoid then
            Humanoid.PlatformStand = false
        end
        ResumeAnimations()
    end
end)

-- Main loop
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
        flashback:Revert()
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
    flashback.frameAccumulator = 0
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
print("Speed: " .. REWIND_SPEED .. "x")
print("======================================")
