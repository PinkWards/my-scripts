--[[
    ====== FLASHBACK SCRIPT (FRAME-PERFECT REWIND) ======
    Hold C to rewind time!
    ✓ Frame-perfect playback - exactly what you did
    ✓ Same speed as recorded (1:1)
    ✓ No smoothing/interpolation - pure replay
]]

-- ============ SETTINGS ============

local FLASHBACK_KEY = Enum.KeyCode.C
local FLASHBACK_LENGTH = 60          -- Seconds of recording
local REVERSE_VELOCITY = true         -- Reverse movement direction
local RECORD_TOOLS = true             -- Record equipped tools
local RESTORE_HEALTH = true           -- Restore health during rewind

-- Rewind speed: 1.0 = exact same speed as recorded
-- 0.5 = half speed (slow-mo rewind)
-- 2.0 = double speed (fast rewind)
local REWIND_SPEED = 1.0

-- Playback mode:
-- "EXACT" = Frame-perfect, no smoothing (like rewinding a video)
-- "SMOOTH" = Interpolated, smoother but less accurate
local PLAYBACK_MODE = "EXACT"

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

local flashback = {
    lastinput = false, 
    canrevert = true, 
    active = false,
    frameAccumulator = 0,
}

-- Update character references
local function UpdateCharacter()
    Character = LP.Character
    if not Character then
        HRP = nil
        Humanoid = nil
        return false
    end
    
    HRP = Character:FindFirstChild("HumanoidRootPart")
    Humanoid = Character:FindFirstChildOfClass("Humanoid")
    
    return HRP ~= nil and Humanoid ~= nil
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
    
    -- Reset accumulator when not rewinding
    self.frameAccumulator = 0
    
    -- Record current frame with ALL necessary data
    local frameData = {
        CFrame = HRP.CFrame,
        Velocity = HRP.AssemblyLinearVelocity,
        AngularVelocity = HRP.AssemblyAngularVelocity,
        State = Humanoid:GetState(),
        PlatformStand = Humanoid.PlatformStand,
        Health = Humanoid.Health,
        MaxHealth = Humanoid.MaxHealth,
        MoveDirection = Humanoid.MoveDirection,
        WalkSpeed = Humanoid.WalkSpeed,
        JumpPower = Humanoid.JumpPower,
    }
    
    -- Record all body part CFrames for perfect replay
    frameData.BodyParts = {}
    for _, part in pairs(Character:GetDescendants()) do
        if part:IsA("BasePart") and part ~= HRP then
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
    
    local num = #frames
    
    if num == 0 or not self.canrevert then
        self.canrevert = false
        self:Advance(false)
        return
    end
    
    self.lastinput = true
    
    -- Accumulate based on rewind speed
    self.frameAccumulator = self.frameAccumulator + REWIND_SPEED
    
    local lastframe = nil
    
    -- Consume frames based on accumulator
    while self.frameAccumulator >= 1 and #frames > 0 do
        self.frameAccumulator = self.frameAccumulator - 1
        lastframe = frames[#frames]
        frames[#frames] = nil  -- Remove the frame (consume it)
    end
    
    -- For fractional speeds less than 1, peek at frame without consuming
    if not lastframe and #frames > 0 then
        lastframe = frames[#frames]
    end
    
    if not lastframe then return end
    
    -- ========== APPLY FRAME ==========
    
    if PLAYBACK_MODE == "EXACT" then
        -- FRAME-PERFECT: Set exact position, no interpolation
        HRP.CFrame = lastframe.CFrame
        
        -- Set exact velocity (reversed if enabled)
        if REVERSE_VELOCITY then
            HRP.AssemblyLinearVelocity = -lastframe.Velocity
            HRP.AssemblyAngularVelocity = -lastframe.AngularVelocity
        else
            HRP.AssemblyLinearVelocity = Vector3.zero
            HRP.AssemblyAngularVelocity = Vector3.zero
        end
        
        -- Restore all body part positions for perfect visual replay
        if lastframe.BodyParts then
            for part, cf in pairs(lastframe.BodyParts) do
                if part and part.Parent then
                    part.CFrame = cf
                end
            end
        end
        
    else -- SMOOTH mode
        -- Interpolated movement
        local lerpSpeed = 0.5
        HRP.CFrame = HRP.CFrame:Lerp(lastframe.CFrame, lerpSpeed)
        
        if REVERSE_VELOCITY then
            local targetVel = -lastframe.Velocity * 0.5
            HRP.AssemblyLinearVelocity = HRP.AssemblyLinearVelocity:Lerp(targetVel, 0.3)
        else
            HRP.AssemblyLinearVelocity = HRP.AssemblyLinearVelocity:Lerp(Vector3.zero, 0.3)
        end
    end
    
    -- Apply humanoid state
    Humanoid:ChangeState(lastframe.State)
    Humanoid.PlatformStand = true  -- Prevent character from fighting the rewind
    
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
        -- Re-enable normal movement when done rewinding
        if Humanoid then
            Humanoid.PlatformStand = false
        end
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
    
    Character = char
    HRP = char:WaitForChild("HumanoidRootPart", 5)
    Humanoid = char:WaitForChild("Humanoid", 5)
    
    if Humanoid then
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
print("Mode: " .. PLAYBACK_MODE)
print("Speed: " .. REWIND_SPEED .. "x")
print("======================================")
