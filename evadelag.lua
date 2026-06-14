-- || EVADE ULTIMATE ANTI-LAG || --
-- FIXES ROUND-BY-ROUND LAG: Anchors map debris so your CPU doesn't drown in physics.
-- Strictly ONLY touches the Map folder. Ghost/Character 100% Safe.

local lighting = game:GetService("Lighting")
local workspace = game:GetService("Workspace")
local players = game:GetService("Players")
local lp = players.LocalPlayer

-- 1. LOCK FPS TO 60
pcall(function()
    setfpscap(60) 
end)

-- OPTIMIZE LIGHTING (Level 1 Graphics + Bright Light = Far See Distance + Zero GPU Lag)
local function optimizeLighting()
    pcall(function()
        -- Force Level 1 Graphics for maximum iGPU performance
        settings().Rendering.QualityLevel = Enum.QualityLevel.Level01
        
        lighting.GlobalShadows = false
        -- Make it bright so you can see far even on Level 1 graphics!
        lighting.Brightness = 3
        lighting.Ambient = Color3.fromRGB(150, 150, 150)
        lighting.OutdoorAmbient = Color3.fromRGB(150, 150, 150)
        lighting.FogEnd = 1000000
        
        lighting.EnvironmentDiffuseScale = 0
        lighting.EnvironmentSpecularScale = 0
        
        for _, effect in ipairs(lighting:GetChildren()) do
            if effect:IsA("Atmosphere") or effect:IsA("DepthOfFieldEffect") or effect:IsA("SunRaysEffect") or effect:IsA("BloomEffect") then
                effect:Destroy()
            elseif effect:IsA("BlurEffect") and effect.Name ~= "MenuBlur" then
                effect:Destroy()
            end
        end
    end)
end

-- OPTIMIZE MAP ONLY (This is the only safe place to touch)
local function optimizeMap()
    local gameFolder = workspace:FindFirstChild("Game")
    if not gameFolder then return end
    
    local mapFolder = gameFolder:FindFirstChild("Map")
    if not mapFolder then return end
    
    for _, obj in ipairs(mapFolder:GetDescendants()) do
        pcall(function()
            -- Destroy particles and lights (Huge iGPU saver)
            if obj:IsA("ParticleEmitter") or obj:IsA("Smoke") or obj:IsA("Fire") or obj:IsA("Trail") or obj:IsA("PointLight") or obj:IsA("SpotLight") then
                obj:Destroy()
                
            -- Optimize Map Parts
            elseif obj:IsA("BasePart") then
                obj.CastShadow = false
                obj.Reflectance = 0
                
                -- THE ULTIMATE FIX: Anchor unanchored map parts!
                -- This stops physics calculations which cause lag to build up every round.
                -- Because we are ONLY in the Map folder, your character will NEVER be anchored.
                if not obj.Anchored then
                    obj.Anchored = true
                end
                
            -- Lower poly on map props
            elseif obj:IsA("MeshPart") then
                obj.RenderFidelity = Enum.RenderFidelity.Performance
                obj.LevelOfDetail = Enum.MeshDetailLevel.Low
                if not obj.Anchored then
                    obj.Anchored = true
                end
            end
        end)
    end
    
    -- Terrain Water Fix
    pcall(function()
        local terrain = workspace:FindFirstChild("Terrain")
        if terrain then
            terrain.WaterWaveSize = 0
            terrain.WaterWaveSpeed = 0
            terrain.WaterReflectance = 0
            terrain.WaterTransparency = 0.2
        end
    end)
end

local function runOptimization()
    optimizeLighting()
    optimizeMap()
end

-- || LIGHTING ENFORCER LOOP || --
spawn(function()
    while task.wait(5) do
        optimizeLighting()
    end
end)

-- || MAP CHANGE DETECTION || --
local gameFolder = workspace:WaitForChild("Game", 30)
if gameFolder then
    local mapFolder = gameFolder:FindFirstChild("Map") or gameFolder:WaitForChild("Map", 20)
    if mapFolder then
        mapFolder.ChildAdded:Connect(function()
            task.wait(3) 
            optimizeMap()
        end)
    end
end

-- || SAFE START || --
local function safeStart()
    while not lp.Character do
        task.wait(1)
    end
    task.wait(5)
    runOptimization()
    print("[EVADE ULTIMATE ANTI-LAG] Physics frozen, Graphics optimized!")
end

spawn(safeStart)
