--[[
    ====== FLASHBACK SCRIPT (FIXED) ======
    Hold C to rewind time!
    ✓ Fixed: Now works after death
]]

-- ============ SETTINGS ============

local FLASHBACK_KEY = Enum.KeyCode.C
local FLASHBACK_LENGTH = 60
local FLASHBACK_SPEED = 1
local SMOOTHNESS = 0.3
local REVERSE_VELOCITY = true
local VELOCITY_MULTIPLIER = 1
local RECORD_TOOLS = true
local USE_INTERPOLATION = true
local INTERPOLATION_SPEED = 0.5

-- ============ END OF SETTINGS ============

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local LP = Players.LocalPlayer
local frames = {}
local maxFrames = FLASHBACK_LENGTH * 60

-- Character references (will be updated on respawn)
local Character = nil
local HRP = nil
local Humanoid = nil

local flashback = {
    lastinput = false, 
    canrevert = true, 
    active = false,
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
    -- Check if character is valid
    if not HRP or not HRP.Parent then return end
    if not Humanoid or Humanoid.Health <= 0 then return end
    
    -- Remove old frames
    local frameCount = #frames
    if frameCount >= maxFrames then
        table.remove(frames, 1)
    end
    
    if allowinput and not self.canrevert then
        self.canrevert = true
    end
    
    if self.lastinput then
        Humanoid.PlatformStand = false
        self.lastinput = false
    end
    
    -- Record current frame
    local frameData = {
        CFrame = HRP.CFrame,
        Velocity = HRP.AssemblyLinearVelocity,
        State = Humanoid:GetState(),
        PlatformStand = Humanoid.PlatformStand,
    }
    
    if RECORD_TOOLS then
        frameData.Tool = Character:FindFirstChildOfClass("Tool")
    end
    
    frames[#frames + 1] = frameData
end

function flashback:Revert()
    -- Check if character is valid
    if not HRP or not HRP.Parent then return end
    if not Humanoid or Humanoid.Health <= 0 then return end
    
    local num = #frames
    
    if num == 0 or not self.canrevert then
        self.canrevert = false
        self:Advance(false)
        return
    end
    
    -- Skip frames based on speed
    local framesToRemove = math.min(FLASHBACK_SPEED, num - 1)
    for i = 1, framesToRemove do
        frames[num] = nil
        num = num - 1
    end
    
    self.lastinput = true
    local lastframe = frames[num]
    
    if not lastframe then return end
    
    frames[num] = nil
    
    -- Apply position
    if USE_INTERPOLATION then
        HRP.CFrame = HRP.CFrame:Lerp(lastframe.CFrame, INTERPOLATION_SPEED)
    else
        HRP.CFrame = lastframe.CFrame
    end
    
    -- Apply velocity
    if REVERSE_VELOCITY then
        HRP.AssemblyLinearVelocity = -lastframe.Velocity * VELOCITY_MULTIPLIER
    else
        HRP.AssemblyLinearVelocity = Vector3.zero
    end
    
    -- Apply state
    Humanoid:ChangeState(lastframe.State)
    Humanoid.PlatformStand = lastframe.PlatformStand
    
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
    -- Always try to update character references
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

-- THIS IS THE FIX! Reset everything properly on respawn
LP.CharacterAdded:Connect(function(char)
    -- Wait for character to fully load
    task.wait(0.1)
    
    -- Clear old frames (they're from dead character!)
    frames = {}
    
    -- Reset flashback state
    flashback.canrevert = true
    flashback.active = false
    flashback.lastinput = false
    
    -- Update references to NEW character
    Character = char
    HRP = char:WaitForChild("HumanoidRootPart", 5)
    Humanoid = char:WaitForChild("Humanoid", 5)
    
    -- Handle death during flashback
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
print("======================================")
