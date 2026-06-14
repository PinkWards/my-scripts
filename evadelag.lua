-- || EVADE BALANCED SMOOTH FPS BOOSTER || --
-- STRICT RULE: Only touches the Map folder and Lighting.
-- Spoofed to Level 3 for perfect mid-range render distance without the far-distance lag.

local lighting = game:GetService("Lighting")
local workspace = game:GetService("Workspace")
local players = game:GetService("Players")
local lp = players.LocalPlayer

-- 1. LOCK FPS TO 60 (Crucial for i5/HD 620 steady frame pacing)
pcall(function()
    setfpscap(60) 
end)

-- OPTIMIZE LIGHTING & SPOOF RENDER DISTANCE
local function optimizeLighting()
    pcall(function()
        -- THE SPOOF: Level 3 is the perfect "Mid-Range" 
        -- Not too near (Level 1), not too far/laggy (Level 5). Just right!
        settings().Rendering.QualityLevel = Enum.QualityLevel.Level03
        
        lighting.GlobalShadows = false
        lighting.Brightness = 2
        lighting.Ambient = Color3.fromRGB(80, 80, 80)
        lighting.OutdoorAmbient = Color3.fromRGB(80, 80, 80)
        lighting.FogEnd = 1000000
        
        -- Kill realistic light bouncing (Massive iGPU saver)
        lighting.EnvironmentDiffuseScale = 0
        lighting.EnvironmentSpecularScale = 0
        
        for _, effect in ipairs(lighting:GetChildren()) do
            -- ONLY destroy the heavy FPS killers. Leave MenuBlur, ColorCorrection, and Sky alone!
            if effect:IsA("Atmosphere") or effect:IsA("DepthOfFieldEffect") or effect:IsA("SunRaysEffect") or effect:IsA("BloomEffect") then
                effect:Destroy()
            elseif effect:IsA("BlurEffect") and effect.Name ~= "MenuBlur" then
                effect:Destroy()
            end
        end
    end)
end

-- OPTIMIZE MAP ONLY (This is the only safe place to delete particles)
local function optimizeMap()
    local gameFolder = workspace:FindFirstChild("Game")
    if not gameFolder then return end
    
    -- ONLY look inside the Map folder!
    local mapFolder = gameFolder:FindFirstChild("Map")
    if not mapFolder then return end
    
    for _, obj in ipairs(mapFolder:GetDescendants()) do
        pcall(function()
            -- Destroy map particles (smoke, fog, blood on the floor)
            if obj:IsA("ParticleEmitter") or obj:IsA("Smoke") or obj:IsA("Fire") or obj:IsA("Trail") then
                obj:Destroy()
                
            -- Optimize Map Parts for Integrated Graphics
            elseif obj:IsA("BasePart") then
                obj.CastShadow = false
                obj.Reflectance = 0 -- Removes shiny reflections (Massive HD 620 lag source)
                
            -- Lower poly on map props
            elseif obj:IsA("MeshPart") then
                obj.RenderFidelity = Enum.RenderFidelity.Performance
                obj.LevelOfDetail = Enum.MeshDetailLevel.Low
            end
        end)
    end
    
    -- TERRAIN WATER FIX (Kills water reflections and waves that destroy iGPUs)
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
-- This loop ONLY touches Lighting settings and QualityLevel.
-- It does NOT touch workspace objects, so your ghost will NEVER disappear.
-- It ensures Evade doesn't reset your render distance back to 1 bar or turn shadows back on.
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
        -- When a new map loads for the next round, re-optimize the map
        mapFolder.ChildAdded:Connect(function()
            task.wait(3) -- Wait for map to load in
            optimizeMap()
        end)
    end
end

-- || SAFE START (Prevents Lobby Freeze) || --
local function safeStart()
    -- Wait until you actually spawn in
    while not lp.Character do
        task.wait(1)
    end
    task.wait(5) -- Give the game 5 seconds to fully load
    runOptimization()
    print("[EVADE BALANCED FPS] Mid-Range Render + Ultra Smoothness Active!")
end

spawn(safeStart)
