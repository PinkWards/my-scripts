--[[
    Ultimate Anti-Fling v7 - UNPUSHABLE + Trip Works
    No one can push, bump, or fling you
    Your commands work normally
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local LP = Players.LocalPlayer

local isTeleporting = false
local lastPos = nil
local frameCount = 0

local function protect(char)
    if not char then return end
    
    local hrp = char:WaitForChild("HumanoidRootPart", 5)
    local hum = char:WaitForChild("Humanoid", 5)
    if not hrp or not hum then return end
    
    local lastSafeCF = hrp.CFrame
    lastPos = hrp.Position
    
    -- Only disable Ragdoll, NOT FallingDown (so trip works)
    pcall(function()
        hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
    end)
    
    hum.StateChanged:Connect(function(_, new)
        -- Only block Ragdoll, allow FallingDown
        if new == Enum.HumanoidStateType.Ragdoll then
            hum:ChangeState(Enum.HumanoidStateType.GettingUp)
        end
    end)
    
    -- DISABLE COLLISION WITH ALL OTHER PLAYERS
    local function noCollidePlayer(plr)
        if plr == LP then return end
        
        local function disableCollision(pChar)
            if not pChar then return end
            
            for _, part in pairs(pChar:GetChildren()) do
                if part:IsA("BasePart") then
                    part.CanCollide = false
                end
            end
            
            pChar.ChildAdded:Connect(function(child)
                if child:IsA("BasePart") then
                    child.CanCollide = false
                end
            end)
        end
        
        disableCollision(plr.Character)
        plr.CharacterAdded:Connect(disableCollision)
    end
    
    for _, plr in pairs(Players:GetPlayers()) do
        noCollidePlayer(plr)
    end
    
    Players.PlayerAdded:Connect(noCollidePlayer)
    
    local conn
    conn = RunService.Heartbeat:Connect(function()
        if not char.Parent or not hrp.Parent then
            conn:Disconnect()
            return
        end
        
        frameCount += 1
        
        -- Detect teleport
        local dist = (hrp.Position - lastPos).Magnitude
        if dist > 50 then
            isTeleporting = true
            task.delay(0.5, function() isTeleporting = false end)
        end
        lastPos = hrp.Position
        
        if isTeleporting then
            lastSafeCF = hrp.CFrame
            return
        end
        
        local angVel = hrp.AssemblyAngularVelocity.Magnitude
        
        -- Spin fling detection
        if angVel > 60 then
            hrp.AssemblyLinearVelocity = Vector3.zero
            hrp.AssemblyAngularVelocity = Vector3.zero
            hrp.CFrame = lastSafeCF
        elseif angVel > 40 then
            hrp.AssemblyAngularVelocity = Vector3.zero
        end
        
        -- Update safe pos when grounded
        if hum.FloorMaterial ~= Enum.Material.Air then
            lastSafeCF = hrp.CFrame
        end
        
        -- EVERY 5 FRAMES: Force no collision
        if frameCount % 5 == 0 then
            for _, plr in pairs(Players:GetPlayers()) do
                if plr ~= LP and plr.Character then
                    for _, part in pairs(plr.Character:GetChildren()) do
                        if part:IsA("BasePart") then
                            part.CanCollide = false
                        end
                    end
                end
            end
        end
        
        -- EVERY 15 FRAMES: Remove force objects
        if frameCount % 15 == 0 then
            for _, obj in pairs(char:GetChildren()) do
                if obj:IsA("BasePart") then
                    for _, child in pairs(obj:GetChildren()) do
                        local cn = child.ClassName
                        if cn == "Torque" or cn == "AlignPosition" or cn == "BodyAngularVelocity" then
                            child:Destroy()
                        end
                    end
                end
            end
        end
        
        -- EVERY 30 FRAMES: Ring parts check
        if frameCount % 30 == 0 then
            for _, obj in pairs(workspace:GetChildren()) do
                if obj:IsA("Folder") then
                    for _, part in pairs(obj:GetChildren()) do
                        if part:IsA("BasePart") and not part.Anchored then
                            if part.AssemblyLinearVelocity.Magnitude > 100 then
                                part.CanCollide = false
                            end
                        end
                    end
                end
            end
        end
    end)
    
    -- Block new force objects
    char.DescendantAdded:Connect(function(obj)
        local cn = obj.ClassName
        if cn == "Torque" or cn == "AlignPosition" or cn == "BodyAngularVelocity" then
            task.defer(function() pcall(function() obj:Destroy() end) end)
        end
    end)
end

protect(LP.Character)

LP.CharacterAdded:Connect(function(char)
    task.wait(0.2)
    lastPos = nil
    frameCount = 0
    protect(char)
end)

getgenv().WhitelistTP = function()
    isTeleporting = true
    task.delay(1, function() isTeleporting = false end)
end

print([[
[Anti-Fling v7] UNPUSHABLE Active!

✓ No one can push/bump/fling you
✓ Trip command works!
✓ Works in Natural Disaster Survival
✓ Allows teleports & speed
✓ Persists through respawns
]])
