-- || EVADE ULTIMATE SAFE FPS BOOSTER || --
-- STRICT RULE: Only touches the Map folder and Lighting.
-- Uses a safe background loop instead of global scanners so your character NEVER disappears.

local lighting = game:GetService("Lighting")
local workspace = game:GetService("Workspace")
local players = game:GetService("Players")
local lp = players.LocalPlayer

-- 1. UNCAP FPS
pcall(function()
    setfpscap(0) -- 0 = Uncapped. Change to 144 or 240 if you want a specific limit.
end)

-- OPTIMIZE LIGHTING (Safely removes GPU heavers, removes Blur, keeps MenuBlur and Colors)
local function optimizeLighting()
    pcall(function()
        lighting.GlobalShadows = false
        lighting.Brightness = 2
        lighting.Ambient = Color3.fromRGB(80, 80, 80)
        lighting.OutdoorAmbient = Color3.fromRGB(80, 80, 80)
        lighting.FogEnd = 1000000
        
        -- Far render distance trick without forcing QualityLevel (which breaks ghosts)
        lighting.EnvironmentDiffuseScale = 0
        lighting.EnvironmentSpecularScale = 0
        
        for _, effect in ipairs(lighting:GetChildren()) do
            -- ONLY destroy the heavy FPS killers. Leave MenuBlur, ColorCorrection, and Sky alone!
            if effect:IsA("Atmosphere") or effect:IsA("DepthOfFieldEffect") or effect:IsA("SunRaysEffect") or effect:IsA("BloomEffect") then
                effect:Destroy()
            -- Remove BLUR, but keep "MenuBlur" safe so your menu works!
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
                
            -- Turn off map shadows (Huge GPU saver)
            elseif obj:IsA("BasePart") then
                obj.CastShadow = false
                
            -- Lower poly on map props (Massive FPS boost)
            elseif obj:IsA("MeshPart") then
                obj.RenderFidelity = Enum.RenderFidelity.Performance
                obj.LevelOfDetail = Enum.MeshDetailLevel.Low
            end
        end)
    end
end

local function runOptimization()
    optimizeLighting()
    optimizeMap()
end

-- || SAFE BACKGROUND LOOP || --
-- Runs every 15 seconds. Because it ONLY uses the safe optimizeMap() function,
-- your character/ghost/cache/menu will NEVER be touched, but new maps get auto-cleaned!
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
    print("[EVADE SAFE FPS] Max FPS loaded! Auto-cleaning new maps safely.")
end

spawn(safeStart)
