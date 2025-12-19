local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local LP = Players.LocalPlayer
local WS = game:GetService("Workspace")

-- CONFIG
local MAX_VEL = 55
local FLING_VEL = 150

-- STATE (minimal)
local root, safeCF, flings, protecting = nil, nil, 0, false
local V3Zero = Vector3.zero

-- DANGEROUS CLASSES (hash)
local BAD = {
	BodyVelocity=1,BodyAngularVelocity=1,BodyForce=1,BodyThrust=1,
	BodyPosition=1,BodyGyro=1,VectorForce=1,LinearVelocity=1,
	AngularVelocity=1,AlignPosition=1,AlignOrientation=1,LineForce=1
}

-- MAIN LOOP (ultra minimal)
RunService.RenderStepped:Connect(function()
	if not root then return end
	
	local lv = root.AssemblyLinearVelocity
	local m = lv.X*lv.X + lv.Y*lv.Y + lv.Z*lv.Z -- faster than .Magnitude
	
	if m > 90000 then -- 300^2 extreme
		root.AssemblyLinearVelocity = V3Zero
		root.AssemblyAngularVelocity = V3Zero
		if safeCF then root.CFrame = safeCF end
		flings += 1
		protecting = true
	elseif m > 22500 then -- 150^2 high
		root.AssemblyLinearVelocity = V3Zero
		root.AssemblyAngularVelocity = V3Zero
		flings += 1
		protecting = true
	elseif m > 3025 then -- 55^2 clamp
		root.AssemblyLinearVelocity = lv.Unit * MAX_VEL
		protecting = false
	else
		if m < 400 then safeCF = root.CFrame end -- save when slow
		protecting = false
	end
end)

-- CHARACTER SETUP
local function onChar(c)
	root = c:WaitForChild("HumanoidRootPart", 5)
	if root then safeCF = root.CFrame end
	
	c.DescendantAdded:Connect(function(o)
		if BAD[o.ClassName] then
			task.defer(o.Destroy, o)
		end
	end)
end

LP.CharacterAdded:Connect(onChar)
if LP.Character then task.spawn(onChar, LP.Character) end

-- OTHER PLAYERS (event-only, no loop)
local function noCollide(c)
	if not c then return end
	for _,p in c:GetChildren() do
		if p:IsA("BasePart") then p.CanCollide = false end
	end
	c.DescendantAdded:Connect(function(p)
		if p:IsA("BasePart") then p.CanCollide = false end
	end)
end

local function onPlayer(p)
	if p == LP then return end
	if p.Character then noCollide(p.Character) end
	p.CharacterAdded:Connect(noCollide)
end

for _,p in Players:GetPlayers() do task.spawn(onPlayer, p) end
Players.PlayerAdded:Connect(onPlayer)

-- SUSPICIOUS PARTS (simple check)
WS.DescendantAdded:Connect(function(o)
	if not o:IsA("BasePart") then return end
	
	task.defer(function()
		if not o.Parent then return end
		
		local cpp = o.CustomPhysicalProperties
		if cpp and cpp.Density == 0 and cpp.Friction == 0 then
			o.CanCollide = false
			pcall(o.Destroy, o)
			return
		end
		
		local v = o.AssemblyLinearVelocity
		if v.X*v.X + v.Y*v.Y + v.Z*v.Z > 160000 then -- 400^2
			o.CanCollide = false
			pcall(o.Destroy, o)
		end
	end)
end)

-- TINY GUI
local gui = Instance.new("ScreenGui")
gui.ResetOnSpawn = false
gui.Parent = LP:WaitForChild("PlayerGui")

local lbl = Instance.new("TextLabel")
lbl.Size = UDim2.fromOffset(100, 24)
lbl.Position = UDim2.new(0, 10, 0.5, -12)
lbl.BackgroundColor3 = Color3.new(0.1, 0.1, 0.1)
lbl.TextColor3 = Color3.new(0.5, 1, 0.5)
lbl.Font = Enum.Font.GothamBold
lbl.TextSize = 11
lbl.Text = "🛡️ 0"
lbl.Parent = gui
Instance.new("UICorner", lbl).CornerRadius = UDim.new(0, 4)

-- GUI UPDATE (1Hz)
task.spawn(function()
	while task.wait(1) do
		lbl.Text = protecting and "⚠️ "..flings or "🛡️ "..flings
		lbl.TextColor3 = protecting and Color3.new(1,0.4,0.4) or Color3.new(0.5,1,0.5)
	end
end)
