--[[
    ====== FLASHBACK SCRIPT (OPTIMIZED) ======
    Hold C to rewind time!
    
    TWEAKABLE SETTINGS BELOW:
]]

-- ============ SETTINGS (TWEAK THESE!) ============

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

-- Cache services once (instead of calling GetService repeatedly)
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local LP = Players.LocalPlayer
local frames = {}
local maxFrames = FLASHBACK_LENGTH * 60

-- Cache character parts to avoid repeated FindFirstChild calls
local cachedChar = nil
local cachedHRP = nil
local cachedHum = nil

local function updateCache()
    local char = LP.Character
    if not char then 
        return nil, nil, nil 
    end
    
    -- Only update cache if character changed
    if char ~= cachedChar then
        cachedChar = char
        cachedHRP = char:FindFirstChild("HumanoidRootPart") 
            or char:FindFirstChild("Torso") 
            or char:FindFirstChild("UpperTorso") 
            or char:FindFirstChildWhichIsA("BasePart")
        cachedHum = char:FindFirstChildWhichIsA("Humanoid")
    end
    
    return cachedChar, cachedHRP, cachedHum
end

local flashback = {
    lastinput = false, 
    canrevert = true, 
    active = false,
}

function flashback:Advance(char, hrp, hum, allowinput)
    -- More efficient frame removal (remove from end instead of beginning)
    local frameCount = #frames
    if frameCount >= maxFrames then
        -- Remove oldest frames in batch if too many
        local toRemove = frameCount - maxFrames + 1
        for i = 1, toRemove do
            table.remove(frames, 1)
        end
    end
    
    if allowinput and not self.canrevert then
        self.canrevert = true
    end
    
    if self.lastinput then
        hum.PlatformStand = false
        self.lastinput = false
    end
    
    -- Record current frame
    local frameData = {
        CFrame = hrp.CFrame,
        Velocity = hrp.Velocity,
        State = hum:GetState(),
        PlatformStand = hum.PlatformStand,
    }
    
    if RECORD_TOOLS then
        frameData.Tool = char:FindFirstChildOfClass("Tool")
    end
    
    frames[#frames + 1] = frameData -- Slightly faster than table.insert
end

function flashback:Revert(char, hrp, hum)
    local num = #frames
    
    if num == 0 or not self.canrevert then
        self.canrevert = false
        self:Advance(char, hrp, hum, false)
        return
    end
    
    -- Skip frames based on FLASHBACK_SPEED
    local framesToRemove = math.min(FLASHBACK_SPEED, num - 1)
    for i = 1, framesToRemove do
        frames[num] = nil
        num = num - 1
    end
    
    self.lastinput = true
    local lastframe = frames[num]
    
    if not lastframe then return end
    
    frames[num] = nil -- Faster than table.remove for last element
    
    -- Apply position
    if USE_INTERPOLATION then
        hrp.CFrame = hrp.CFrame:Lerp(lastframe.CFrame, INTERPOLATION_SPEED)
    else
        hrp.CFrame = lastframe.CFrame
    end
    
    -- Apply velocity
    if REVERSE_VELOCITY then
        hrp.Velocity = -lastframe.Velocity * VELOCITY_MULTIPLIER
    else
        hrp.Velocity = Vector3.zero -- Cached zero vector
    end
    
    -- Apply state
    hum:ChangeState(lastframe.State)
    hum.PlatformStand = lastframe.PlatformStand
    
    -- Handle tools
    if RECORD_TOOLS then
        local currenttool = char:FindFirstChildOfClass("Tool")
        if lastframe.Tool then
            if not currenttool then
                hum:EquipTool(lastframe.Tool)
            end
        elseif currenttool then
            hum:UnequipTools()
        end
    end
end

-- Key input handling
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
    local char, hrp, hum = updateCache()
    
    if not hrp or not hum then return end
    
    if flashback.active then
        flashback:Revert(char, hrp, hum)
    else
        flashback:Advance(char, hrp, hum, true)
    end
end)

-- Reset when character respawns
LP.CharacterAdded:Connect(function()
    frames = {}
    cachedChar = nil
    cachedHRP = nil
    cachedHum = nil
    flashback.canrevert = true
    flashback.active = false
end)

print("====== FLASHBACK SCRIPT LOADED ======")
print("Hold [" .. FLASHBACK_KEY.Name .. "] to rewind time!")
print("Current settings:")
print("  - Flashback length: " .. FLASHBACK_LENGTH .. " seconds")
print("  - Flashback speed: " .. FLASHBACK_SPEED)
print("  - Smoothness: " .. SMOOTHNESS)
print("  - Interpolation: " .. tostring(USE_INTERPOLATION))
print("======================================")
