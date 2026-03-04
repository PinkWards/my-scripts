local FLASHBACK_KEY = Enum.KeyCode.C
local FLASHBACK_LENGTH = 60
local FLASHBACK_SPEED = 0.8
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

local Character = nil
local HRP = nil
local Humanoid = nil

local flashback = {
    lastinput = false, 
    canrevert = true, 
    active = false,
}

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
    if not HRP or not HRP.Parent then return end
    if not Humanoid or Humanoid.Health <= 0 then return end
    
    local num = #frames
    
    if num == 0 or not self.canrevert then
        self.canrevert = false
        self:Advance(false)
        return
    end
    
    local framesToRemove = math.min(FLASHBACK_SPEED, num - 1)
    for i = 1, framesToRemove do
        frames[num] = nil
        num = num - 1
    end
    
    self.lastinput = true
    local lastframe = frames[num]
    
    if not lastframe then return end
    
    frames[num] = nil
    
    if USE_INTERPOLATION then
        HRP.CFrame = HRP.CFrame:Lerp(lastframe.CFrame, INTERPOLATION_SPEED)
    else
        HRP.CFrame = lastframe.CFrame
    end
    
    if REVERSE_VELOCITY then
        HRP.AssemblyLinearVelocity = -lastframe.Velocity * VELOCITY_MULTIPLIER
    else
        HRP.AssemblyLinearVelocity = Vector3.zero
    end
    
    Humanoid:ChangeState(lastframe.State)
    Humanoid.PlatformStand = lastframe.PlatformStand
    
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

LP.CharacterAdded:Connect(function(char)
    task.wait(0.1)
    
    frames = {}
    
    flashback.canrevert = true
    flashback.active = false
    flashback.lastinput = false
    
    Character = char
    HRP = char:WaitForChild("HumanoidRootPart", 5)
    Humanoid = char:WaitForChild("Humanoid", 5)
    
    if Humanoid then
        Humanoid.Died:Connect(function()
            flashback.active = false
            flashback.canrevert = false
        end)
    end
end)

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
