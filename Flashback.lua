--[[
    ====== FLASHBACK SCRIPT (SMOOTH REWIND) ======
    Hold C to rewind time!
    ✓ Fixed: Now works after death
    ✓ Health restoration enabled
    ✓ FIXED: Smooth, adjustable rewind speed
]]

-- ============ SETTINGS ============

local FLASHBACK_KEY = Enum.KeyCode.C
local FLASHBACK_LENGTH = 60
local SMOOTHNESS = 0.3
local REVERSE_VELOCITY = true
local VELOCITY_MULTIPLIER = 0.5
local RECORD_TOOLS = true
local RESTORE_HEALTH = true

-- NEW: Rewind speed control
-- 0.5 = half speed (slower rewind)
-- 1.0 = normal speed (same as recorded)
-- 2.0 = double speed (fast rewind)
local REWIND_SPEED = 1.5  -- <-- Adjust this! Lower = slower rewind

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
    frameAccumulator = 0,  -- NEW: For smooth timing
    targetFrame = nil,     -- NEW: Current target frame
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
    
    -- Remove old frames
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
    self.targetFrame = nil
    
    -- Record current frame
    local frameData = {
        CFrame = HRP.CFrame,
        Velocity = HRP.AssemblyLinearVelocity,
        State = Humanoid:GetState(),
        PlatformStand = Humanoid.PlatformStand,
        Health = Humanoid.Health,
        MaxHealth = Humanoid.MaxHealth
    }
    
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
    
    -- Accumulate time for smooth speed control
    self.frameAccumulator = self.frameAccumulator + REWIND_SPEED
    
    -- Only consume frames when accumulator is >= 1
    while self.frameAccumulator >= 1 and #frames > 0 do
        self.frameAccumulator = self.frameAccumulator - 1
        self.targetFrame = frames[#frames]
        frames[#frames] = nil
    end
    
    -- If no target yet, get the last frame (but don't remove it)
    if not self.targetFrame then
        self.targetFrame = frames[#frames]
    end
    
    if not self.targetFrame then return end
    
    local lastframe = self.targetFrame
    
    -- Smooth interpolation to target position
    -- Lower SMOOTHNESS = smoother but slower response
    local lerpSpeed = math.clamp(SMOOTHNESS * (REWIND_SPEED + 0.5), 0.1, 1)
    HRP.CFrame = HRP.CFrame:Lerp(lastframe.CFrame, lerpSpeed)
    
    -- Apply velocity (reduced for smoother feel)
    if REVERSE_VELOCITY then
        local targetVel = -lastframe.Velocity * VELOCITY_MULTIPLIER * REWIND_SPEED
        HRP.AssemblyLinearVelocity = HRP.AssemblyLinearVelocity:Lerp(targetVel, 0.3)
    else
        HRP.AssemblyLinearVelocity = HRP.AssemblyLinearVelocity:Lerp(Vector3.zero, 0.3)
    end
    
    -- Apply state
    Humanoid:ChangeState(lastframe.State)
    Humanoid.PlatformStand = lastframe.PlatformStand
    
    -- Restore health
    if RESTORE_HEALTH and lastframe.Health then
        if lastframe.Health > Humanoid.Health then
            Humanoid.Health = lastframe.Health
        end
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
    flashback.targetFrame = nil
    
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
print("Rewind Speed: " .. REWIND_SPEED .. "x")
print("======================================")
