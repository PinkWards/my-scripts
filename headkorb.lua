local StarterGui = game:GetService("StarterGui")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

-- // Constants
local KORBLOX_MESH_ID = "rbxassetid://101851696"
local KORBLOX_TEXTURE_ID = "rbxassetid://101851254"
local DARK_GREY_COLOR = Color3.fromRGB(64, 64, 64)
local MIN_VAL, MAX_VAL, STEP = -2, 2, 0.05
local CONFIG_FILE = "KorbloxLegConfig.txt"

-- // Config (persists during session)
local Config = {
    LegYOffset = 0,
}

-- // Load saved config from file
pcall(function()
    local savedData = readfile(CONFIG_FILE)
    if savedData then
        local savedNum = tonumber(savedData)
        if savedNum then
            Config.LegYOffset = math.clamp(savedNum, MIN_VAL, MAX_VAL)
        end
    end
end)

-- // Notification
local function notify(title, text, icon)
    StarterGui:SetCore("SendNotification", {
        Title = title,
        Text = text,
        Icon = icon or "",
        Duration = 5
    })
end

local player = Players.LocalPlayer or Players:GetPropertyChangedSignal("LocalPlayer"):Wait()

-- // References for the heartbeat loop
local korbloxWeld = nil
local isR15 = true
local currentYOffset = 0 -- Used for smooth lerping in R15

-- // Helper to safely get scale
local function getScaleProp(humanoid, propName)
    local success, val = pcall(function() return humanoid[propName] end)
    if success then
        local num = tonumber(val)
        if num then return math.max(num, 0.5) end
        if typeof(val) == "Instance" and val:IsA("NumberValue") then return math.max(val.Value, 0.5) end
    end
    return 1.0
end

-- // ============ GUI (Created First) ============
local sg = Instance.new("ScreenGui")
sg.Name = "KorbloxLegGui"
sg.ResetOnSpawn = false
sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
sg.Parent = game:GetService("CoreGui")

local frm = Instance.new("Frame")
frm.Size = UDim2.new(0, 175, 0, 34)
frm.Position = UDim2.new(1, -185, 0, 10)
frm.BackgroundColor3 = Color3.fromRGB(12, 12, 12)
frm.BackgroundTransparency = 0.15
frm.BorderSizePixel = 0
frm.Active = true
frm.Draggable = true
frm.Visible = false -- Hidden by default until R15 is confirmed
frm.Parent = sg

Instance.new("UICorner", frm).CornerRadius = UDim.new(0, 6)
local frmStroke = Instance.new("UIStroke")
frmStroke.Color = Color3.fromRGB(50, 50, 50)
frmStroke.Thickness = 0.5
frmStroke.Parent = frm

local yLbl = Instance.new("TextLabel")
yLbl.Size = UDim2.new(0, 12, 1, 0)
yLbl.Position = UDim2.new(0, 5, 0, 0)
yLbl.BackgroundTransparency = 1
yLbl.Text = "Y"
yLbl.TextColor3 = Color3.fromRGB(150, 150, 150)
yLbl.TextSize = 10
yLbl.Font = Enum.Font.GothamBold
yLbl.Parent = frm

local txB = Instance.new("TextBox")
txB.Size = UDim2.new(0, 32, 0, 20)
txB.Position = UDim2.new(0, 19, 0.5, -10)
txB.BackgroundColor3 = Color3.fromRGB(28, 28, 28)
txB.BackgroundTransparency = 0.35
txB.TextColor3 = Color3.fromRGB(255, 255, 255)
txB.TextSize = 9
txB.Font = Enum.Font.Gotham
txB.Text = "0.00"
txB.BorderSizePixel = 0
txB.ClearTextOnFocus = false
txB.Parent = frm
Instance.new("UICorner", txB).CornerRadius = UDim.new(0, 3)

local slBg = Instance.new("Frame")
slBg.Size = UDim2.new(0, 84, 0, 6)
slBg.Position = UDim2.new(0, 55, 0.5, -3)
slBg.BackgroundColor3 = Color3.fromRGB(38, 38, 38)
slBg.BorderSizePixel = 0
slBg.Parent = frm
Instance.new("UICorner", slBg).CornerRadius = UDim.new(0, 3)

local slFill = Instance.new("Frame")
slFill.BackgroundColor3 = Color3.fromRGB(0, 140, 255)
slFill.BorderSizePixel = 0
slFill.Parent = slBg
Instance.new("UICorner", slFill).CornerRadius = UDim.new(0, 3)

local slKnob = Instance.new("Frame")
slKnob.Size = UDim2.new(0, 8, 0, 12)
slKnob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
slKnob.BorderSizePixel = 0
slKnob.Parent = slBg
Instance.new("UICorner", slKnob).CornerRadius = UDim.new(1, 0)

local slHit = Instance.new("TextButton")
slHit.Size = UDim2.new(1, 0, 0, 22)
slHit.Position = UDim2.new(0, 0, 0.5, -11)
slHit.BackgroundTransparency = 1
slHit.Text = ""
slHit.Parent = slBg

local upVis = Instance.new("TextLabel")
upVis.Size = UDim2.new(0, 14, 0, 12)
upVis.Position = UDim2.new(0, 145, 0, 3)
upVis.BackgroundColor3 = Color3.fromRGB(38, 38, 38)
upVis.BackgroundTransparency = 0.3
upVis.Text = "▲"
upVis.TextColor3 = Color3.fromRGB(180, 180, 180)
upVis.TextSize = 7
upVis.Font = Enum.Font.Gotham
upVis.BorderSizePixel = 0
upVis.Parent = frm
Instance.new("UICorner", upVis).CornerRadius = UDim.new(0, 3)

local upBtn = Instance.new("TextButton")
upBtn.Size = UDim2.new(0, 24, 0, 16)
upBtn.Position = UDim2.new(0, 140, 0, 1)
upBtn.BackgroundTransparency = 1
upBtn.Text = ""
upBtn.Parent = frm

local dnVis = Instance.new("TextLabel")
dnVis.Size = UDim2.new(0, 14, 0, 12)
dnVis.Position = UDim2.new(0, 145, 0, 19)
dnVis.BackgroundColor3 = Color3.fromRGB(38, 38, 38)
dnVis.BackgroundTransparency = 0.3
dnVis.Text = "▼"
dnVis.TextColor3 = Color3.fromRGB(180, 180, 180)
dnVis.TextSize = 7
dnVis.Font = Enum.Font.Gotham
dnVis.BorderSizePixel = 0
dnVis.Parent = frm
Instance.new("UICorner", dnVis).CornerRadius = UDim.new(0, 3)

local dnBtn = Instance.new("TextButton")
dnBtn.Size = UDim2.new(0, 24, 0, 16)
dnBtn.Position = UDim2.new(0, 140, 0, 17)
dnBtn.BackgroundTransparency = 1
dnBtn.Text = ""
dnBtn.Parent = frm

-- // ============ LOGIC ============
local SL_W, KN_W = 84, 8

local function updateVisuals()
    local norm = math.clamp((Config.LegYOffset - MIN_VAL) / (MAX_VAL - MIN_VAL), 0, 1)
    slKnob.Position = UDim2.new(0, norm * (SL_W - KN_W), 0.5, -6)
    if norm >= 0.5 then
        slFill.Position = UDim2.new(0, 0.5 * SL_W, 0, 0)
        slFill.Size = UDim2.new(0, (norm - 0.5) * SL_W, 1, 0)
    else
        slFill.Position = UDim2.new(0, norm * SL_W, 0, 0)
        slFill.Size = UDim2.new(0, (0.5 - norm) * SL_W, 1, 0)
    end
    txB.Text = string.format("%.2f", Config.LegYOffset)
end

local function setValue(val)
    local n = tonumber(val)
    if not n then return end
    Config.LegYOffset = math.clamp(math.round(n * 100) / 100, MIN_VAL, MAX_VAL)
    updateVisuals()
    
    pcall(function()
        writefile(CONFIG_FILE, tostring(Config.LegYOffset))
    end)
end

local dragging = false

local function getSliderVal(input)
    local relX = input.Position.X - slBg.AbsolutePosition.X
    local norm = math.clamp(relX / slBg.AbsoluteSize.X, 0, 1)
    return MIN_VAL + norm * (MAX_VAL - MIN_VAL)
end

slHit.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        setValue(getSliderVal(input))
    end
end)

slHit.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = false
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        setValue(getSliderVal(input))
    end
end)

txB.FocusLost:Connect(function()
    local val = tonumber(txB.Text)
    if val then
        setValue(val)
    else
        txB.Text = string.format("%.2f", Config.LegYOffset)
    end
end)

txB.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = false
    end
end)

local function setupArrow(btn, vis, delta)
    local holding = false
    btn.MouseButton1Down:Connect(function()
        setValue(Config.LegYOffset + delta)
        vis.BackgroundColor3 = Color3.fromRGB(65, 65, 65)
        holding = true
        task.spawn(function()
            task.wait(0.35)
            while holding do
                setValue(Config.LegYOffset + delta)
                task.wait(0.035) -- Faster, smoother continuous adjustment
            end
        end)
    end)
    btn.MouseButton1Up:Connect(function()
        holding = false
        vis.BackgroundColor3 = Color3.fromRGB(38, 38, 38)
    end)
    btn.MouseLeave:Connect(function()
        holding = false
        vis.BackgroundColor3 = Color3.fromRGB(38, 38, 38)
    end)
end

setupArrow(upBtn, upVis, STEP)
setupArrow(dnBtn, dnVis, -STEP)
updateVisuals()

-- // Headless
local function applyHeadless(char)
    local head = char:FindFirstChild("Head")
    if not head then return end
    head.Transparency = 1
    pcall(function() head.CastShadow = false end)
    
    for _, v in ipairs(head:GetChildren()) do
        if v:IsA("Decal") or v:IsA("Texture") or v:IsA("SurfaceAppearance") then
            v:Destroy()
        elseif v:IsA("SpecialMesh") then
            v.Scale = Vector3.new(0.001, 0.001, 0.001)
        end
    end
    
    for _, acc in ipairs(char:GetChildren()) do
        if acc:IsA("Accessory") then
            local handle = acc:FindFirstChild("Handle")
            if handle then
                for _, att in ipairs(handle:GetDescendants()) do
                    if att:IsA("Attachment") and (att.Name == "HatAttachment" or att.Name == "HairAttachment" or att.Name == "FaceFrontAttachment" or att.Name == "FaceCenterAttachment") then
                        handle.Transparency = 1
                    end
                end
            end
        end
    end
end

-- // Korblox Setup (Runs once per spawn)
local function setupKorblox(char)
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return end

    -- Clean up old parts from previous deaths just in case
    local oldLeg = char:FindFirstChild("KorbloxLeg")
    if oldLeg then oldLeg:Destroy() end

    korbloxWeld = nil

    if hum.RigType == Enum.HumanoidRigType.R15 then
        isR15 = true
        frm.Visible = true -- Show adjuster GUI for R15
        
        local ru = char:FindFirstChild("RightUpperLeg")
        local rl = char:FindFirstChild("RightLowerLeg")
        local rf = char:FindFirstChild("RightFoot")

        if ru and rl and rf then
            ru.Transparency = 1
            rl.Transparency = 1
            rf.Transparency = 1

            for _, p in pairs({ru, rl, rf}) do
                for _, c in pairs(p:GetChildren()) do
                    if c:IsA("SpecialMesh") or c:IsA("Decal") then c:Destroy() end
                end
            end

            local korbloxLeg = Instance.new("Part")
            korbloxLeg.Name = "KorbloxLeg"
            korbloxLeg.Size = Vector3.new(1, 1, 1)
            korbloxLeg.Anchored = false
            korbloxLeg.CanCollide = false
            korbloxLeg.Massless = true
            korbloxLeg.Color = DARK_GREY_COLOR
            korbloxLeg.Transparency = 0
            korbloxLeg.CFrame = ru.CFrame
            korbloxLeg.Parent = char

            local mesh = Instance.new("SpecialMesh")
            mesh.MeshType = Enum.MeshType.FileMesh
            mesh.MeshId = KORBLOX_MESH_ID
            mesh.TextureId = KORBLOX_TEXTURE_ID
            mesh.Parent = korbloxLeg

            local weld = Instance.new("Weld")
            weld.Part0 = ru
            weld.Part1 = korbloxLeg
            weld.C0 = CFrame.new()
            weld.C1 = CFrame.new()
            weld.Parent = korbloxLeg

            korbloxWeld = weld
            currentYOffset = Config.LegYOffset 
        end
    else
        isR15 = false
        frm.Visible = false -- Force hide adjuster GUI for R6
        
        local rightLeg = char:FindFirstChild("Right Leg")
        if rightLeg then
            -- Remove existing right leg character meshes completely
            for _, v in ipairs(char:GetChildren()) do
                if v:IsA("CharacterMesh") and v.BodyPart == Enum.BodyPart.RightLeg then
                    v:Destroy()
                end
            end
            
            -- Remove any stray SpecialMesh inside the leg
            for _, c in ipairs(rightLeg:GetChildren()) do
                if c:IsA("SpecialMesh") then c:Destroy() end
            end

            rightLeg.Color = DARK_GREY_COLOR
            rightLeg.Transparency = 0

            -- Using the official Roblox CharacterMesh native to R6 packages
            -- This ensures 100% exact positioning, scale, and behavior with no floating
            local cMesh = Instance.new("CharacterMesh")
            cMesh.Name = "KorbloxR6Leg"
            cMesh.BodyPart = Enum.BodyPart.RightLeg
            cMesh.MeshId = 101851696
            cMesh.OverlayTextureId = 101851254
            cMesh.Parent = char
        end
    end
end

-- // Heartbeat Loop (Applies offset, scale, and forces transparency every frame)
RunService.Heartbeat:Connect(function(deltaTime)
    local char = player.Character
    if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return end

    -- Keep head invisible
    local head = char:FindFirstChild("Head")
    if head and head.Transparency ~= 1 then head.Transparency = 1 end

    if isR15 then
        local ru = char:FindFirstChild("RightUpperLeg")
        local rl = char:FindFirstChild("RightLowerLeg")
        local rf = char:FindFirstChild("RightFoot")
        if ru and ru.Transparency ~= 1 then ru.Transparency = 1 end
        if rl and rl.Transparency ~= 1 then rl.Transparency = 1 end
        if rf and rf.Transparency ~= 1 then rf.Transparency = 1 end

        if korbloxWeld and korbloxWeld.Parent then
            -- Smoothly lerp towards the target config offset for smooth adjuster feeling
            currentYOffset = currentYOffset + (Config.LegYOffset - currentYOffset) * math.min(1, 15 * deltaTime)
            
            -- Apply Y Offset
            korbloxWeld.C0 = CFrame.new(0, currentYOffset, 0)
            
            -- Apply Scale
            local mesh = korbloxWeld.Parent:FindFirstChildOfClass("SpecialMesh")
            if mesh and hum then
                local w = getScaleProp(hum, "BodyWidthScale")
                local h = getScaleProp(hum, "BodyHeightScale")
                local d = getScaleProp(hum, "BodyDepthScale")
                mesh.Scale = Vector3.new(w, h, d)
            end
        end
    else
        -- R6 logic: The CharacterMesh handles everything automatically. 
        -- We only ensure the leg color and transparency remain correct.
        local rightLeg = char:FindFirstChild("Right Leg")
        if rightLeg then
            if rightLeg.Color ~= DARK_GREY_COLOR then rightLeg.Color = DARK_GREY_COLOR end
            if rightLeg.Transparency ~= 0 then rightLeg.Transparency = 0 end
        end
    end
end)

-- // Character Loading
player.CharacterAdded:Connect(function(char)
    korbloxWeld = nil
    char:WaitForChild("HumanoidRootPart", 10)
    task.wait(1.5) -- Wait for rig to fully load
    setupKorblox(char)
end)

if player.Character then
    task.spawn(function()
        setupKorblox(player.Character)
    end)
end

notify("Korblox + Headless", "Active! GUI adjusts R15 only. R6 uses native Korblox.", "rbxassetid://101851696")
