--[[
    ====== FLASHBACK SCRIPT ======
    Hold C to rewind time!
    
    TWEAKABLE SETTINGS BELOW:
]]

-- ============ SETTINGS (TWEAK THESE!) ============

local FLASHBACK_KEY = Enum.KeyCode.G -- Change this to any key you want (e.g., Enum.KeyCode.R, Enum.KeyCode.F, etc.)

local FLASHBACK_LENGTH = 60 -- How many seconds of history to store (higher = more memory usage)

local FLASHBACK_SPEED = 1 -- How many frames to skip when rewinding
                          -- 0 = no skip (slowest rewind, very smooth)
                          -- 1 = skip 1 frame (normal speed)
                          -- 2 = skip 2 frames (faster rewind)
                          -- 3+ = even faster rewind

local SMOOTHNESS = 0.3 -- How smooth the flashback looks (0.1 to 1)
                       -- Lower = smoother but less accurate
                       -- Higher = more accurate but can be choppy
                       -- Recommended: 0.2 - 0.5

local REVERSE_VELOCITY = true -- Set to false if you don't want reversed momentum after flashback

local VELOCITY_MULTIPLIER = 1 -- How strong the reversed velocity is (0 = no velocity, 1 = normal, 2 = double, etc.)

local RECORD_TOOLS = true -- Set to false if you don't want to record tool equip/unequip

local USE_INTERPOLATION = true -- Set to true for smoother movement (recommended)

local INTERPOLATION_SPEED = 0.5 -- How fast interpolation is (0.1 = very smooth, 1 = instant)
                                 -- Only works if USE_INTERPOLATION is true

-- ============ END OF SETTINGS ============

local frames = {}
local LP = game:GetService("Players").LocalPlayer
local RS = game:GetService("RunService")
local UIS = game:GetService("UserInputService")

local function getchar()
    return LP.Character or LP.CharacterAdded:Wait()
end

local function gethrp(c)
    return c:FindFirstChild("HumanoidRootPart") 
        or c.RootPart 
        or c.PrimaryPart 
        or c:FindFirstChild("Torso") 
        or c:FindFirstChild("UpperTorso") 
        or c:FindFirstChildWhichIsA("BasePart")
end

local flashback = {
    lastinput = false, 
    canrevert = true, 
    active = false,
    targetCFrame = nil -- Used for interpolation
}

function flashback:Advance(char, hrp, hum, allowinput)
    local maxFrames = FLASHBACK_LENGTH * 60
    
    -- Remove old frames if we have too many
    while #frames > maxFrames do
        table.remove(frames, 1)
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
    
    -- Only record tool if setting is enabled
    if RECORD_TOOLS then
        frameData.Tool = char:FindFirstChildOfClass("Tool")
    end
    
    table.insert(frames, frameData)
end

function flashback:Revert(char, hrp, hum)
    local num = #frames
    
    if num == 0 or not self.canrevert then
        self.canrevert = false
        self:Advance(char, hrp, hum)
        return
    end
    
    -- Skip frames based on FLASHBACK_SPEED
    for i = 1, FLASHBACK_SPEED do
        if num > 1 then
            table.remove(frames, num)
            num = num - 1
        end
    end
    
    self.lastinput = true
    local lastframe = frames[num]
    
    if not lastframe then return end
    
    table.remove(frames, num)
    
    -- Apply position (with or without interpolation)
    if USE_INTERPOLATION then
        hrp.CFrame = hrp.CFrame:Lerp(lastframe.CFrame, INTERPOLATION_SPEED)
    else
        hrp.CFrame = lastframe.CFrame
    end
    
    -- Apply velocity
    if REVERSE_VELOCITY then
        hrp.Velocity = -lastframe.Velocity * VELOCITY_MULTIPLIER
    else
        hrp.Velocity = Vector3.new(0, 0, 0)
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
        else
            hum:UnequipTools()
        end
    end
end

-- Key input handling
UIS.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode == FLASHBACK_KEY then
        flashback.active = true
    end
end)

UIS.InputEnded:Connect(function(input, gameProcessed)
    if input.KeyCode == FLASHBACK_KEY then
        flashback.active = false
    end
end)

-- Main loop
RS.Heartbeat:Connect(function(deltaTime)
    local char = getchar()
    local hrp = gethrp(char)
    local hum = char:FindFirstChildWhichIsA("Humanoid")
    
    if not hrp or not hum then return end
    
    if flashback.active then
        flashback:Revert(char, hrp, hum)
    else
        flashback:Advance(char, hrp, hum, true)
    end
end)

-- Reset frames when character respawns
LP.CharacterAdded:Connect(function()
    frames = {}
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
