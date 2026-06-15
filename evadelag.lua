-- || EVADE SAFE FPS BOOSTER || --
-- STRICT RULE: Only touches the Map folder and Lighting.
-- Leaves Cache, Menu, Players, and Effects ALONE so UI and Ghosts work perfectly.

local lighting = game:GetService("Lighting")
local workspace = game:GetService("Workspace")
local players = game:GetService("Players")
local lp = players.LocalPlayer

-- OPTIMIZE LIGHTING (Safely removes GPU heavers, keeps MenuBlur and Colors)
local function optimizeLighting()
    pcall(function()
        lighting.GlobalShadows = false
        lighting.Brightness = 2
        lighting.Ambient = Color3.fromRGB(80, 80, 80)
        lighting.OutdoorAmbient = Color3.fromRGB(80, 80, 80)
        lighting.FogEnd = 1000000
        
        for _, effect in ipairs(lighting:GetChildren()) do
            -- ONLY destroy the heavy FPS killers. Leave MenuBlur, ColorCorrection, and Sky alone!
            if effect:IsA("Atmosphere") or effect:IsA("DepthOfFieldEffect") or effect:IsA("SunRaysEffect") or effect:IsA("BloomEffect") then
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
            end
        end)
    end
end

local function runOptimization()
    optimizeLighting()
    optimizeMap()
    print("[EVADE SAFE FPS] Map and Lighting optimized. UI and Ghosts untouched!")
end

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
end

spawn(safeStart)
