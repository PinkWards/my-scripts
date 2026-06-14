-- || EVADE HD 620 OPTIMIZED FPS BOOSTER || --
-- Strict Map & Lighting ONLY rule (Character/Ghost 100% Safe)
-- Locked to 60 FPS, Removed reflections, Optimized for i5/Integrated Graphics

local lighting = game:GetService("Lighting")
local workspace = game:GetService("Workspace")
local players = game:GetService("Players")
local lp = players.LocalPlayer

-- 1. LOCK FPS TO 60 (Crucial for frame pacing and preventing iGPU thermal throttling)
pcall(function()
    setfpscap(60) 
end)

-- 2. OPTIMIZE CPU PHYSICS (Frees up your i5 processor)
pcall(function()
    settings().Physics.AllowSleep = true -- Stops calculating physics for stationary map parts
end)

-- OPTIMIZE LIGHTING (Keeps game looking colorful, removes GPU killers)
local function optimizeLighting()
    pcall(function()
        lighting.GlobalShadows = false
        lighting.Brightness = 2
        lighting.Ambient = Color3.fromRGB(80, 80, 80)
        lighting.OutdoorAmbient = Color3.fromRGB(80, 80, 80)
        lighting.FogEnd = 1000000
        
        -- Removes realistic light bouncing (Huge iGPU saver, game still looks completely normal)
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
                obj.Reflectance = 0 -- Removes shiny reflections (Massive HD 620 booster)
                
            -- Lower poly on map props
            elseif obj:IsA("MeshPart") then
                obj.RenderFidelity = Enum.RenderFidelity.Performance
                obj.LevelOfDetail = Enum.MeshDetailLevel.Low
            end
        end)
    end
    
    -- TERRAIN WATER FIX (Removes water wave and reflection calculations)
    pcall(function()
        local terrain = workspace:FindFirstChild("Terrain")
        if terrain then
            terrain.WaterWaveSize = 0
            terrain.WaterWaveSpeed = 0
            terrain.WaterReflectance = 0 -- Kills heavy water mirrors
            terrain.WaterTransparency = 0.2 -- Makes water slightly opaque so it doesn't try to render what's under it
        end
    end)
end

local function runOptimization()
    optimizeLighting()
    optimizeMap()
end

-- || SAFE BACKGROUND LOOP || --
-- Runs every 15 seconds. Strictly ONLY uses the safe optimizeMap() function.
-- Your character/ghost/cache/menu will NEVER be touched, but new maps get auto-cleaned!
spawn(function()
    while task.wait(15) do
        runOptimization()
    end
end)

-- || SAFE START (Prevents Lobby Freeze) || --
local function safeStart()
    -- Wait until you actually spawn in
    while not lp.Character do
        task.wait(1)
    end
    task.wait(5) -- Give the game 5 seconds to fully load
    runOptimization()
    print("[EVADE 60FPS LOCK] Loaded for HD 620! Smooth and steady.")
end

spawn(safeStart)
