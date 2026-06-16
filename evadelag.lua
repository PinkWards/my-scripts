-- || EVADE FPS BOOSTER v4 - TAILORED TO YOUR SCAN || --
-- Targets: Map.Lighting, Map.InvisParts, Camera particles, Cache cleanup

local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local lp = Players.LocalPlayer

local trackedOldMap = nil

-- ============================================
-- 1. WORKSPACE.LIGHTING (Safe effects)
-- ============================================
local function optimizeWorkspaceLighting()
    pcall(function()
        Lighting.GlobalShadows = false
        Lighting.Brightness = 2
        Lighting.Ambient = Color3.fromRGB(80, 80, 80)
        Lighting.OutdoorAmbient = Color3.fromRGB(80, 80, 80)
        Lighting.FogEnd = 1000000
        Lighting.FogStart = 0
        Lighting.EnvironmentDiffuseScale = 0
        Lighting.EnvironmentSpecularScale = 0
        -- DO NOT change Technology (breaks cursor)
        
        for _, effect in ipairs(Lighting:GetChildren()) do
            pcall(function()
                -- SKIP MenuBlur (causes issues) and Sky
                if effect.Name == "MenuBlur" then return end
                if effect:IsA("Sky") then return end
                
                if effect:IsA("Atmosphere")
                or effect:IsA("DepthOfFieldEffect")
                or effect:IsA("SunRaysEffect")
                or effect:IsA("BloomEffect")
                or effect:IsA("BlurEffect") then
                    effect:Destroy()
                elseif effect:IsA("ColorCorrectionEffect") then
                    effect.Brightness = 0
                    effect.Contrast = 0
                    effect.Saturation = 0
                    effect.TintColor = Color3.fromRGB(255, 255, 255)
                end
            end)
        end
    end)
end

-- ============================================
-- 2. MAP.LIGHTING (THE CULPRIT - cleans map's own lighting)
-- ============================================
local function optimizeMapLighting(mapFolder)
    local mapLighting = mapFolder and mapFolder:FindFirstChild("Lighting")
    if not mapLighting then return end
    
    pcall(function()
        for _, effect in ipairs(mapLighting:GetChildren()) do
            pcall(function()
                if effect:IsA("Atmosphere")
                or effect:IsA("DepthOfFieldEffect")
                or effect:IsA("SunRaysEffect")
                or effect:IsA("BloomEffect")
                or effect:IsA("BlurEffect") then
                    effect:Destroy()
                elseif effect:IsA("ColorCorrectionEffect") then
                    effect.Brightness = 0
                    effect.Contrast = 0
                    effect.Saturation = 0
                    effect.TintColor = Color3.fromRGB(255, 255, 255)
                end
            end)
        end
    end)
end

-- ============================================
-- 3. CLEAN MAP CONTENT (with character/UI protection)
-- ============================================
local function cleanMapContent(mapFolder)
    if not mapFolder then return end
    
    local stats = {particles = 0, lights = 0, shadows = 0, decals = 0}
    
    for _, obj in ipairs(mapFolder:GetDescendants()) do
        pcall(function()
            -- SKIP anything that looks like a character
            if obj:IsA("Humanoid") or obj:IsA("Accessory") then return end
            if obj:IsA("Shirt") or obj:IsA("Pants") or obj:IsA("ShirtGraphic") then return end
            if obj:IsA("BodyColors") or obj:IsA("CharacterMesh") then return end
            if obj:IsA("Motor6D") or obj:IsA("Weld") or obj:IsA("WeldConstraint") then return end
            if obj:IsA("LocalScript") or obj:IsA("Script") or obj:IsA("ModuleScript") then return end
            
            -- Check parent chain for character/Humanoid
            local parent = obj.Parent
            while parent and parent ~= mapFolder do
                if parent:IsA("Model") and parent:FindFirstChildOfClass("Humanoid") then
                    return
                end
                parent = parent.Parent
            end
            
            -- CLEAN PARTICLES (53 in your scan)
            if obj:IsA("ParticleEmitter")
            or obj:IsA("Smoke")
            or obj:IsA("Fire")
            or obj:IsA("Trail")
            or obj:IsA("Beam") then
                obj:Destroy()
                stats.particles = stats.particles + 1
                
            -- DISABLE MAP LIGHTS (49 in your scan)
            elseif obj:IsA("PointLight")
            or obj:IsA("SpotLight")
            or obj:IsA("SurfaceLight") then
                obj.Enabled = false
                obj.Shadows = false
                stats.lights = stats.lights + 1
                
            -- SHADOWS OFF (huge GPU saver on 2543 BaseParts + 881 MeshParts)
            elseif obj:IsA("BasePart") then
                obj.CastShadow = false
                stats.shadows = stats.shadows + 1
                if obj:IsA("MeshPart") then
                    obj.RenderFidelity = Enum.RenderFidelity.Performance
                end
            end
        end)
    end
    
    print(string.format("[EVADE FPS] Map cleaned: %d particles, %d lights off, %d shadows off",
        stats.particles, stats.lights, stats.shadows))
end

-- ============================================
-- 4. CLEAN CAMERA PARTICLES (Fog, Rain, Snow, Thunderstorm)
-- ============================================
local function cleanCameraParticles()
    pcall(function()
        local camera = Workspace.CurrentCamera
        if not camera then return end
        
        for _, part in ipairs(camera:GetChildren()) do
            if part:IsA("Part") then
                for _, child in ipairs(part:GetChildren()) do
                    pcall(function()
                        if child:IsA("ParticleEmitter")
                        or child:IsA("Smoke")
                        or child:IsA("Fire") then
                            child:Destroy()
                        end
                    end)
                end
            end
        end
    end)
end

-- ============================================
-- 5. CLEAN INVISPARTS (110+ invisible map parts - usually safe to keep)
-- ============================================
local function optimizeInvisParts(mapFolder)
    local invisParts = mapFolder and mapFolder:FindFirstChild("InvisParts")
    if not invisParts then return end
    
    pcall(function()
        for _, part in ipairs(invisParts:GetChildren()) do
            if part:IsA("BasePart") then
                part.CastShadow = false
            end
        end
    end)
end

-- ============================================
-- 6. MAP CHANGE HANDLER (The main loop)
-- ============================================
local function handleMapChange(mapFolder)
    -- Wait for map to load
    task.wait(4)
    
    -- 1. Optimize the map's own lighting (THIS FIXES THE BLACK SCREEN BUG)
    optimizeMapLighting(mapFolder)
    
    -- 2. Clean map content
    cleanMapContent(mapFolder)
    
    -- 3. Optimize invis parts
    optimizeInvisParts(mapFolder)
    
    -- 4. Clean camera particles
    cleanCameraParticles()
    
    -- 5. Force Lua garbage collection
    collectgarbage("collect")
    collectgarbage("collect")
    
    print("[EVADE FPS] Map fully optimized! Round ready.")
end

-- ============================================
-- 7. WATCH FOR MAP CHANGES
-- ============================================
local function setupWatcher()
    local gameFolder = Workspace:FindFirstChild("Game")
    if not gameFolder then
        gameFolder = Workspace:WaitForChild("Game", 30)
    end
    if not gameFolder then
        warn("[EVADE FPS] Game folder not found!")
        return
    end
    
    -- Handle current map
    local currentMap = gameFolder:FindFirstChild("Map")
    if currentMap then
        task.spawn(handleMapChange, currentMap)
    end
    
    -- Watch for new map additions
    gameFolder.ChildAdded:Connect(function(child)
        if child.Name == "Map" then
            print("[EVADE FPS] New map detected, optimizing...")
            task.spawn(handleMapChange, child)
        end
    end)
end

-- ============================================
-- 8. PERIODIC CLEANUP (every 60s)
-- ============================================
task.spawn(function()
    while true do
        task.wait(60)
        pcall(function()
            collectgarbage("collect")
            collectgarbage("collect")
            -- Clean any new camera particles
            cleanCameraParticles()
        end)
    end
end)

-- ============================================
-- 9. SAFE START
-- ============================================
local function safeStart()
    while not lp do task.wait(1) end
    while not lp.Character do task.wait(1) end
    task.wait(7) -- Extra time for Evade to fully load
    
    optimizeWorkspaceLighting()
    setupWatcher()
    
    print("[EVADE FPS] ✅ Booster active! No more cursor/character bugs.")
end

task.spawn(safeStart)
