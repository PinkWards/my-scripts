--[[
    Animation Changer v3.6 - External Database Version (OPTIMIZED)
    ★ Press RIGHT CONTROL to toggle GUI
    ★ Persists through respawns
    ★ Fetches animations from external database
]]

if _G.AnimChangerLoaded then return end
_G.AnimChangerLoaded = true

-- Cache services once
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local MAX_SLOTS = 8
local SavedLoadouts = {}
local currentAnimations = {}
local buttons = {}
local currentCategory = "All"
local isGuiVisible = false
local gui = nil
local currentTab = "Anims"
local categoryButtons = {}
local AnimationData = {}

-- Database URL
local DATABASE_URL = "https://raw.githubusercontent.com/SpeakSpanishOrVanish/Gaze-stuff/refs/heads/main/Gaze%20Anim%20Database"

-- Pre-create TweenInfo objects (reused throughout)
local TWEEN_FAST = TweenInfo.new(0.15)
local TWEEN_NORMAL = TweenInfo.new(0.2)
local TWEEN_SMOOTH = TweenInfo.new(0.25)
local TWEEN_POPUP_IN = TweenInfo.new(0.3, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
local TWEEN_POPUP_OUT = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

-- Cache colors (avoid creating new Color3 objects)
local COLORS = {
    BG_DARK = Color3.fromRGB(25, 25, 35),
    BG_MEDIUM = Color3.fromRGB(35, 35, 50),
    BG_LIGHT = Color3.fromRGB(45, 45, 62),
    BG_HOVER = Color3.fromRGB(60, 60, 82),
    ACCENT_BLUE = Color3.fromRGB(70, 130, 210),
    ACCENT_GREEN = Color3.fromRGB(60, 170, 90),
    ACCENT_GREEN_HOVER = Color3.fromRGB(80, 210, 120),
    ACCENT_RED = Color3.fromRGB(200, 60, 60),
    ACCENT_RED_HOVER = Color3.fromRGB(240, 80, 80),
    TEXT_WHITE = Color3.fromRGB(255, 255, 255),
    TEXT_GRAY = Color3.fromRGB(150, 150, 175),
    TEXT_DARK = Color3.fromRGB(120, 120, 140),
    SUCCESS = Color3.fromRGB(100, 220, 130),
    WARNING = Color3.fromRGB(255, 180, 60),
    ERROR = Color3.fromRGB(255, 100, 100),
    INFO = Color3.fromRGB(100, 180, 255),
}

local typeColors = {
    All = Color3.fromRGB(140, 140, 160),
    Idle = Color3.fromRGB(100, 170, 255),
    Walk = Color3.fromRGB(100, 220, 140),
    Run = Color3.fromRGB(255, 180, 80),
    Jump = Color3.fromRGB(255, 120, 120),
    Fall = Color3.fromRGB(180, 120, 255),
    Climb = Color3.fromRGB(255, 160, 180),
    Swim = Color3.fromRGB(80, 200, 240),
    SwimIdle = Color3.fromRGB(60, 180, 220),
}

-- Animation type order (reused in multiple places)
local ANIM_ORDER = {"Idle", "Walk", "Run", "Jump", "Fall", "Climb", "Swim", "SwimIdle"}

-- Animation folder mapping (cached)
local ANIM_MAP = {
    Idle = {"idle", {"Animation1", "Animation2"}},
    Walk = {"walk", {"WalkAnim"}},
    Run = {"run", {"RunAnim"}},
    Jump = {"jump", {"JumpAnim"}},
    Fall = {"fall", {"FallAnim"}},
    Climb = {"climb", {"ClimbAnim"}},
    Swim = {"swim", {"Swim"}},
    SwimIdle = {"swimidle", {"SwimIdle"}},
}

-- Default animation IDs
local DEFAULT_ANIMS = {
    idle = {"507766388", "507766666"},
    walk = "507777826",
    run = "507767714",
    jump = "507765000",
    fall = "507767968",
    climb = "507765644",
    swim = "507784897",
    swimidle = "507785072"
}

local function loadSaveData()
    pcall(function()
        if readfile then
            local data = readfile("AnimLoadouts.json")
            if data and data ~= "" then
                SavedLoadouts = HttpService:JSONDecode(data)
            end
        end
    end)
end

local function saveData()
    pcall(function()
        if writefile then
            writefile("AnimLoadouts.json", HttpService:JSONEncode(SavedLoadouts))
        end
    end)
end

-- Fetch animation database from GitHub
local function fetchAnimationDatabase()
    if RunService:IsStudio() then return nil end
    
    local success, result = pcall(function()
        -- Try different methods to fetch
        if syn and syn.request then
            return syn.request({Url = DATABASE_URL, Method = "GET"}).Body
        elseif http and http.request then
            return http.request({Url = DATABASE_URL, Method = "GET"}).Body
        elseif request then
            return request({Url = DATABASE_URL, Method = "GET"}).Body
        elseif http_request then
            return http_request({Url = DATABASE_URL, Method = "GET"}).Body
        elseif game.HttpGet then
            return game:HttpGet(DATABASE_URL)
        elseif HttpGet then
            return HttpGet(DATABASE_URL)
        end
        return nil
    end)
    
    return success and result or nil
end

-- Parse the database text into animation data
local function parseDatabase(rawData)
    if not rawData then return nil end
    
    local data = {}
    for i = 1, #ANIM_ORDER do
        data[ANIM_ORDER[i]] = {}
    end
    
    local currentCat = nil
    
    for line in rawData:gmatch("[^\r\n]+") do
        line = line:match("^%s*(.-)%s*$")
        
        if line ~= "" and not line:match("^%-%-") and not line:match("^#") then
            local categoryMatch = line:match("^%[(%w+)%]$")
            if categoryMatch then
                currentCat = categoryMatch
                if not data[currentCat] then
                    data[currentCat] = {}
                end
            elseif currentCat then
                local name, value = line:match("^([%w_%-]+)%s*=%s*(.+)$")
                if name and value then
                    value = value:gsub('"', ''):gsub("'", "")
                    
                    local id1, id2 = value:match("^{%s*([%d]+)%s*,%s*([%d]+)%s*}$")
                    if id1 and id2 then
                        data[currentCat][name] = {id1, id2}
                    else
                        local singleId = value:match("^([%d]+)$")
                        if singleId then
                            if currentCat == "Idle" then
                                data[currentCat][name] = {singleId, singleId}
                            else
                                data[currentCat][name] = singleId
                            end
                        end
                    end
                end
            end
        end
    end
    
    return data
end

-- Alternative: Try to load as Lua module
local function tryLoadAsLua(rawData)
    if not rawData then return nil end
    
    local success, result = pcall(function()
        local func = loadstring(rawData)
        if func then
            local data = func()
            return type(data) == "table" and data or nil
        end
        return nil
    end)
    
    return success and result or nil
end

-- Fallback database
local function getDefaultDatabase()
    return {
        Idle = {
            ["Astronaut"] = {"891621366", "891633237"},
            ["Bubbly"] = {"910004836", "910009958"},
            ["Cartoony"] = {"742637544", "742638445"},
            ["Confident"] = {"1069977950", "1069987858"},
            ["Cowboy"] = {"1014390418", "1014398616"},
            ["Elder"] = {"10921101664", "10921102574"},
            ["Ghost"] = {"616006778", "616008087"},
            ["Knight"] = {"657595757", "657568135"},
            ["Levitation"] = {"616006778", "616008087"},
            ["Mage"] = {"707742142", "707855907"},
            ["Ninja"] = {"656117400", "656118341"},
            ["OldSchool"] = {"10921230744", "10921232093"},
            ["Patrol"] = {"1149612882", "1150842221"},
            ["Pirate"] = {"750781874", "750782770"},
            ["Popstar"] = {"1212900985", "1150842221"},
            ["Princess"] = {"941003647", "941013098"},
            ["Robot"] = {"616088211", "616089559"},
            ["Sneaky"] = {"1132473842", "1132477671"},
            ["Stylish"] = {"616136790", "616138447"},
            ["Superhero"] = {"10921288909", "10921290167"},
            ["Toy"] = {"782841498", "782845736"},
            ["Vampire"] = {"1083445855", "1083450166"},
            ["Werewolf"] = {"1083195517", "1083214717"},
            ["Zombie"] = {"616158929", "616160636"},
            ["Rthro"] = {"10921265698", "10921265698"},
            ["Bold"] = {"16738333868", "16738334710"},
        },
        Walk = {
            ["Astronaut"] = "891667138", ["Bubbly"] = "910034870", ["Cartoony"] = "742640026",
            ["Confident"] = "1070017263", ["Cowboy"] = "1014421541", ["Elder"] = "10921111375",
            ["Ghost"] = "616013216", ["Knight"] = "10921127095", ["Levitation"] = "616013216",
            ["Mage"] = "707897309", ["Ninja"] = "656121766", ["OldSchool"] = "10921244891",
            ["Patrol"] = "1151231493", ["Pirate"] = "750785693", ["Popstar"] = "1212980338",
            ["Princess"] = "941028902", ["Robot"] = "616095330", ["Sneaky"] = "1132510133",
            ["Stylish"] = "616146177", ["Superhero"] = "10921298616", ["Toy"] = "782843345",
            ["Vampire"] = "1083473930", ["Werewolf"] = "1083178339", ["Zombie"] = "616168032",
        },
        Run = {
            ["Astronaut"] = "10921039308", ["Bubbly"] = "10921057244", ["Cartoony"] = "10921076136",
            ["Confident"] = "1070001516", ["Cowboy"] = "1014401683", ["Elder"] = "10921104374",
            ["Ghost"] = "616013216", ["Knight"] = "10921121197", ["Levitation"] = "616010382",
            ["Mage"] = "10921148209", ["Ninja"] = "656118852", ["OldSchool"] = "10921240218",
            ["Patrol"] = "1150967949", ["Pirate"] = "750783738", ["Popstar"] = "1212980348",
            ["Princess"] = "941015281", ["Robot"] = "10921250460", ["Sneaky"] = "1132494274",
            ["Stylish"] = "10921276116", ["Superhero"] = "10921291831", ["Toy"] = "10921306285",
            ["Vampire"] = "10921320299", ["Werewolf"] = "10921336997", ["Zombie"] = "616163682",
        },
        Jump = {
            ["Astronaut"] = "891627522", ["Bubbly"] = "910016857", ["Cartoony"] = "742637942",
            ["Confident"] = "1069984524", ["Cowboy"] = "1014394726", ["Elder"] = "10921107367",
            ["Ghost"] = "616008936", ["Knight"] = "910016857", ["Levitation"] = "616008936",
            ["Mage"] = "10921149743", ["Ninja"] = "656117878", ["OldSchool"] = "10921242013",
            ["Patrol"] = "1148811837", ["Pirate"] = "750782230", ["Princess"] = "941008832",
            ["Robot"] = "616090535", ["Sneaky"] = "1132489853", ["Stylish"] = "616139451",
            ["Superhero"] = "10921294559", ["Toy"] = "10921308158", ["Vampire"] = "1083455352",
            ["Werewolf"] = "1083218792", ["Zombie"] = "616161997",
        },
        Fall = {
            ["Astronaut"] = "891617961", ["Bubbly"] = "910001910", ["Cartoony"] = "742637151",
            ["Confident"] = "1069973677", ["Cowboy"] = "1014384571", ["Elder"] = "10921105765",
            ["Ghost"] = "616005863", ["Knight"] = "10921122579", ["Levitation"] = "616005863",
            ["Mage"] = "707829716", ["Ninja"] = "656115606", ["OldSchool"] = "10921241244",
            ["Patrol"] = "1148863382", ["Pirate"] = "750780242", ["Princess"] = "941000007",
            ["Robot"] = "616087089", ["Sneaky"] = "1132469004", ["Stylish"] = "616134815",
            ["Superhero"] = "10921293373", ["Toy"] = "782846423", ["Vampire"] = "1083443587",
            ["Werewolf"] = "1083189019", ["Zombie"] = "616157476",
        },
        Climb = {
            ["Astronaut"] = "10921032124", ["Cartoony"] = "742636889", ["Confident"] = "1069946257",
            ["Cowboy"] = "1014380606", ["Elder"] = "845392038", ["Ghost"] = "616003713",
            ["Knight"] = "10921125160", ["Levitation"] = "10921132092", ["Mage"] = "707826056",
            ["Ninja"] = "656114359", ["OldSchool"] = "10921229866", ["Pirate"] = "750780242",
            ["Princess"] = "940996062", ["Robot"] = "616086039", ["Sneaky"] = "1132461372",
            ["Stylish"] = "10921271391", ["Superhero"] = "10921286911", ["Vampire"] = "1083439238",
            ["Werewolf"] = "10921329322", ["Zombie"] = "616156119",
        },
        Swim = {
            ["Astronaut"] = "891663592", ["Bubbly"] = "910028158", ["Cartoony"] = "10921079380",
            ["Confident"] = "1070009914", ["Cowboy"] = "1014406523", ["Elder"] = "10921108971",
            ["Knight"] = "10921125160", ["Mage"] = "707876443", ["Ninja"] = "656118341",
            ["OldSchool"] = "10921243048", ["Pirate"] = "750784579", ["Princess"] = "941018893",
            ["Robot"] = "10921253142", ["Sneaky"] = "1132500520", ["Stylish"] = "10921281000",
            ["Superhero"] = "10921295495", ["Vampire"] = "10921324408", ["Zombie"] = "616165109",
        },
        SwimIdle = {
            ["Astronaut"] = "891663592", ["Bubbly"] = "910030921", ["Cartoony"] = "10921079380",
            ["Confident"] = "1070012133", ["Cowboy"] = "1014411816", ["Elder"] = "10921110146",
            ["Knight"] = "10921125935", ["Mage"] = "707894699", ["Ninja"] = "656118341",
            ["OldSchool"] = "10921244018", ["Pirate"] = "750785176", ["Princess"] = "941025398",
            ["Robot"] = "10921253767", ["Sneaky"] = "1132506407", ["Stylish"] = "10921281964",
            ["Superhero"] = "10921297391", ["Vampire"] = "10921325443",
        },
    }
end

-- Load animations from database
local function loadAnimations()
    print("🔄 Fetching animation database...")
    
    local rawData = fetchAnimationDatabase()
    
    if rawData then
        -- First try to load as Lua
        local luaData = tryLoadAsLua(rawData)
        if luaData then
            AnimationData = luaData
            print("✅ Loaded database as Lua module")
            return true
        end
        
        -- Try to parse as custom format
        local parsedData = parseDatabase(rawData)
        if parsedData then
            local count = 0
            for _, anims in pairs(parsedData) do
                for _ in pairs(anims) do count += 1 end
            end
            if count > 0 then
                AnimationData = parsedData
                print("✅ Parsed database: " .. count .. " animations")
                return true
            end
        end
        
        -- Try JSON
        local jsonSuccess, jsonData = pcall(function()
            return HttpService:JSONDecode(rawData)
        end)
        if jsonSuccess and jsonData then
            AnimationData = jsonData
            print("✅ Loaded database as JSON")
            return true
        end
    end
    
    print("⚠️ Using fallback database")
    AnimationData = getDefaultDatabase()
    return false
end

loadSaveData()

-- Cache character references
local cachedChar = nil
local cachedHumanoid = nil
local cachedAnimate = nil

local function updateCharacterCache()
    local char = player.Character
    if char ~= cachedChar then
        cachedChar = char
        cachedHumanoid = char and char:FindFirstChildOfClass("Humanoid")
        cachedAnimate = char and char:FindFirstChild("Animate")
    end
    return cachedChar, cachedHumanoid, cachedAnimate
end

local function checkR15()
    updateCharacterCache()
    return cachedHumanoid and cachedHumanoid.RigType == Enum.HumanoidRigType.R15
end

local function stopAnims()
    updateCharacterCache()
    if cachedHumanoid then
        local tracks = cachedHumanoid:GetPlayingAnimationTracks()
        for i = 1, #tracks do
            tracks[i]:Stop(0)
        end
    end
end

local function refresh()
    updateCharacterCache()
    if cachedHumanoid then
        cachedHumanoid:ChangeState(Enum.HumanoidStateType.Landed)
        task.wait(0.03)
        cachedHumanoid:ChangeState(Enum.HumanoidStateType.Running)
    end
end

local function setAnim(aType, aId)
    updateCharacterCache()
    if not cachedAnimate then return false end
    
    local ok = pcall(function()
        stopAnims()
        local m = ANIM_MAP[aType]
        if m then
            local folder = cachedAnimate:FindFirstChild(m[1])
            if folder then
                if aType == "Idle" and typeof(aId) == "table" then
                    for i, name in ipairs(m[2]) do
                        local a = folder:FindFirstChild(name)
                        if a and aId[i] then
                            a.AnimationId = "rbxassetid://" .. aId[i]
                        end
                    end
                else
                    local a = folder:FindFirstChild(m[2][1])
                    if a then
                        a.AnimationId = "rbxassetid://" .. tostring(aId)
                    end
                end
            end
        end
        refresh()
    end)
    return ok
end

local function resetAnims()
    updateCharacterCache()
    if not cachedAnimate then return false end
    
    pcall(function()
        stopAnims()
        local idle = cachedAnimate:FindFirstChild("idle")
        if idle then
            local a1 = idle:FindFirstChild("Animation1")
            local a2 = idle:FindFirstChild("Animation2")
            if a1 then a1.AnimationId = "rbxassetid://" .. DEFAULT_ANIMS.idle[1] end
            if a2 then a2.AnimationId = "rbxassetid://" .. DEFAULT_ANIMS.idle[2] end
        end
        
        local folderMap = {
            walk = "WalkAnim", run = "RunAnim", jump = "JumpAnim",
            fall = "FallAnim", climb = "ClimbAnim", swim = "Swim", swimidle = "SwimIdle"
        }
        
        for k, v in pairs(folderMap) do
            local f = cachedAnimate:FindFirstChild(k)
            if f then
                local a = f:FindFirstChild(v)
                if a then
                    a.AnimationId = "rbxassetid://" .. DEFAULT_ANIMS[k]
                end
            end
        end
        refresh()
    end)
    
    table.clear(currentAnimations)
    return true
end

local function createGui()
    local old = playerGui:FindFirstChild("AnimChangerV36")
    if old then old:Destroy() end
    
    local sg = Instance.new("ScreenGui")
    sg.Name = "AnimChangerV36"
    sg.ResetOnSpawn = false
    sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    sg.Parent = playerGui
    
    local mf = Instance.new("Frame")
    mf.Name = "Main"
    mf.Size = UDim2.new(0, 380, 0, 520)
    mf.Position = UDim2.new(0.5, -190, 0.5, -260)
    mf.BackgroundColor3 = COLORS.BG_DARK
    mf.BorderSizePixel = 0
    mf.Active = true
    mf.Draggable = true
    mf.Visible = false
    mf.Parent = sg
    Instance.new("UICorner", mf).CornerRadius = UDim.new(0, 12)
    local mfStroke = Instance.new("UIStroke", mf)
    mfStroke.Color = Color3.fromRGB(80, 80, 120)
    mfStroke.Thickness = 2

    local tb = Instance.new("Frame", mf)
    tb.Name = "TitleBar"
    tb.Size = UDim2.new(1, 0, 0, 50)
    tb.BackgroundColor3 = COLORS.BG_MEDIUM
    tb.BorderSizePixel = 0
    Instance.new("UICorner", tb).CornerRadius = UDim.new(0, 12)
    
    local tbFix = Instance.new("Frame", tb)
    tbFix.Size = UDim2.new(1, 0, 0, 15)
    tbFix.Position = UDim2.new(0, 0, 1, -15)
    tbFix.BackgroundColor3 = COLORS.BG_MEDIUM
    tbFix.BorderSizePixel = 0

    local title = Instance.new("TextLabel", tb)
    title.Size = UDim2.new(1, -100, 1, 0)
    title.Position = UDim2.new(0, 16, 0, 0)
    title.BackgroundTransparency = 1
    title.Font = Enum.Font.GothamBold
    title.TextSize = 20
    title.TextColor3 = COLORS.TEXT_WHITE
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Text = "🎭 Animation Changer"

    local closeBtn = Instance.new("TextButton", tb)
    closeBtn.Size = UDim2.new(0, 36, 0, 36)
    closeBtn.Position = UDim2.new(1, -44, 0, 7)
    closeBtn.BackgroundColor3 = COLORS.ACCENT_RED
    closeBtn.Text = "✕"
    closeBtn.TextColor3 = COLORS.TEXT_WHITE
    closeBtn.Font = Enum.Font.GothamBold
    closeBtn.TextSize = 18
    closeBtn.AutoButtonColor = false
    Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 8)

    local resetBtn = Instance.new("TextButton", tb)
    resetBtn.Size = UDim2.new(0, 36, 0, 36)
    resetBtn.Position = UDim2.new(1, -86, 0, 7)
    resetBtn.BackgroundColor3 = Color3.fromRGB(70, 70, 100)
    resetBtn.Text = "↺"
    resetBtn.TextColor3 = COLORS.TEXT_WHITE
    resetBtn.Font = Enum.Font.GothamBold
    resetBtn.TextSize = 20
    resetBtn.AutoButtonColor = false
    Instance.new("UICorner", resetBtn).CornerRadius = UDim.new(0, 8)

    local tabFrame = Instance.new("Frame", mf)
    tabFrame.Size = UDim2.new(1, -24, 0, 42)
    tabFrame.Position = UDim2.new(0, 12, 0, 56)
    tabFrame.BackgroundTransparency = 1

    local animsTab = Instance.new("TextButton", tabFrame)
    animsTab.Size = UDim2.new(0.5, -4, 1, 0)
    animsTab.BackgroundColor3 = COLORS.ACCENT_BLUE
    animsTab.Text = "🎬 Animations"
    animsTab.TextColor3 = COLORS.TEXT_WHITE
    animsTab.Font = Enum.Font.GothamBold
    animsTab.TextSize = 16
    animsTab.AutoButtonColor = false
    Instance.new("UICorner", animsTab).CornerRadius = UDim.new(0, 10)

    local savesTab = Instance.new("TextButton", tabFrame)
    savesTab.Size = UDim2.new(0.5, -4, 1, 0)
    savesTab.Position = UDim2.new(0.5, 4, 0, 0)
    savesTab.BackgroundColor3 = Color3.fromRGB(50, 50, 70)
    savesTab.Text = "💾 Saved Sets"
    savesTab.TextColor3 = COLORS.TEXT_GRAY
    savesTab.Font = Enum.Font.GothamBold
    savesTab.TextSize = 16
    savesTab.AutoButtonColor = false
    Instance.new("UICorner", savesTab).CornerRadius = UDim.new(0, 10)

    local animContent = Instance.new("Frame", mf)
    animContent.Name = "AnimContent"
    animContent.Size = UDim2.new(1, -24, 1, -112)
    animContent.Position = UDim2.new(0, 12, 0, 104)
    animContent.BackgroundTransparency = 1

    local searchFrame = Instance.new("Frame", animContent)
    searchFrame.Size = UDim2.new(1, 0, 0, 44)
    searchFrame.BackgroundColor3 = Color3.fromRGB(40, 40, 55)
    Instance.new("UICorner", searchFrame).CornerRadius = UDim.new(0, 10)

    local searchIcon = Instance.new("TextLabel", searchFrame)
    searchIcon.Size = UDim2.new(0, 40, 1, 0)
    searchIcon.BackgroundTransparency = 1
    searchIcon.Text = "🔍"
    searchIcon.TextSize = 18

    local searchBox = Instance.new("TextBox", searchFrame)
    searchBox.Size = UDim2.new(1, -50, 1, 0)
    searchBox.Position = UDim2.new(0, 44, 0, 0)
    searchBox.BackgroundTransparency = 1
    searchBox.Font = Enum.Font.GothamSemibold
    searchBox.TextSize = 16
    searchBox.TextColor3 = COLORS.TEXT_WHITE
    searchBox.PlaceholderText = "Search animations..."
    searchBox.PlaceholderColor3 = COLORS.TEXT_DARK
    searchBox.Text = ""
    searchBox.TextXAlignment = Enum.TextXAlignment.Left
    searchBox.ClearTextOnFocus = false

    local catFrame = Instance.new("ScrollingFrame", animContent)
    catFrame.Size = UDim2.new(1, 0, 0, 38)
    catFrame.Position = UDim2.new(0, 0, 0, 50)
    catFrame.BackgroundTransparency = 1
    catFrame.ScrollBarThickness = 0
    catFrame.ScrollingDirection = Enum.ScrollingDirection.X
    catFrame.CanvasSize = UDim2.new(0, 600, 0, 0)
    local catLayout = Instance.new("UIListLayout", catFrame)
    catLayout.FillDirection = Enum.FillDirection.Horizontal
    catLayout.Padding = UDim.new(0, 8)
    catLayout.VerticalAlignment = Enum.VerticalAlignment.Center

    local countLabel = Instance.new("TextLabel", animContent)
    countLabel.Size = UDim2.new(1, 0, 0, 24)
    countLabel.Position = UDim2.new(0, 0, 0, 92)
    countLabel.BackgroundTransparency = 1
    countLabel.Font = Enum.Font.GothamSemibold
    countLabel.TextSize = 14
    countLabel.TextColor3 = Color3.fromRGB(130, 130, 160)
    countLabel.TextXAlignment = Enum.TextXAlignment.Left
    countLabel.Text = "Loading..."

    local animList = Instance.new("ScrollingFrame", animContent)
    animList.Size = UDim2.new(1, 0, 1, -124)
    animList.Position = UDim2.new(0, 0, 0, 120)
    animList.BackgroundColor3 = Color3.fromRGB(32, 32, 45)
    animList.ScrollBarThickness = 6
    animList.ScrollBarImageColor3 = Color3.fromRGB(100, 100, 130)
    animList.BorderSizePixel = 0
    Instance.new("UICorner", animList).CornerRadius = UDim.new(0, 10)
    local animLayout = Instance.new("UIListLayout", animList)
    animLayout.Name = "Layout"
    animLayout.Padding = UDim.new(0, 6)
    animLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    animLayout.SortOrder = Enum.SortOrder.Name
    local animPadding = Instance.new("UIPadding", animList)
    animPadding.PaddingTop = UDim.new(0, 8)
    animPadding.PaddingBottom = UDim.new(0, 8)
    animPadding.PaddingLeft = UDim.new(0, 8)
    animPadding.PaddingRight = UDim.new(0, 8)

    local loadoutContent = Instance.new("Frame", mf)
    loadoutContent.Name = "LoadoutContent"
    loadoutContent.Size = UDim2.new(1, -24, 1, -112)
    loadoutContent.Position = UDim2.new(0, 12, 0, 104)
    loadoutContent.BackgroundTransparency = 1
    loadoutContent.Visible = false

    local currentSetFrame = Instance.new("Frame", loadoutContent)
    currentSetFrame.Size = UDim2.new(1, 0, 0, 120)
    currentSetFrame.BackgroundColor3 = Color3.fromRGB(35, 42, 60)
    Instance.new("UICorner", currentSetFrame).CornerRadius = UDim.new(0, 10)
    local csStroke = Instance.new("UIStroke", currentSetFrame)
    csStroke.Color = Color3.fromRGB(80, 140, 220)
    csStroke.Thickness = 1

    local csTitle = Instance.new("TextLabel", currentSetFrame)
    csTitle.Size = UDim2.new(1, -16, 0, 30)
    csTitle.Position = UDim2.new(0, 10, 0, 6)
    csTitle.BackgroundTransparency = 1
    csTitle.Font = Enum.Font.GothamBold
    csTitle.TextSize = 16
    csTitle.TextColor3 = COLORS.INFO
    csTitle.TextXAlignment = Enum.TextXAlignment.Left
    csTitle.Text = "📦 Current Animation Set"

    local csInfoScroll = Instance.new("ScrollingFrame", currentSetFrame)
    csInfoScroll.Size = UDim2.new(1, -16, 0, 76)
    csInfoScroll.Position = UDim2.new(0, 8, 0, 36)
    csInfoScroll.BackgroundTransparency = 1
    csInfoScroll.ScrollBarThickness = 4
    csInfoScroll.ScrollBarImageColor3 = Color3.fromRGB(90, 90, 120)
    csInfoScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    csInfoScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y

    local csInfo = Instance.new("TextLabel", csInfoScroll)
    csInfo.Name = "Info"
    csInfo.Size = UDim2.new(1, -8, 0, 0)
    csInfo.AutomaticSize = Enum.AutomaticSize.Y
    csInfo.BackgroundTransparency = 1
    csInfo.Font = Enum.Font.GothamSemibold
    csInfo.TextSize = 14
    csInfo.TextColor3 = Color3.fromRGB(180, 200, 220)
    csInfo.TextXAlignment = Enum.TextXAlignment.Left
    csInfo.TextYAlignment = Enum.TextYAlignment.Top
    csInfo.TextWrapped = true
    csInfo.Text = "No animations applied yet"

    local saveBtn = Instance.new("TextButton", loadoutContent)
    saveBtn.Size = UDim2.new(1, 0, 0, 48)
    saveBtn.Position = UDim2.new(0, 0, 0, 128)
    saveBtn.BackgroundColor3 = COLORS.ACCENT_GREEN
    saveBtn.Text = "💾 Save Current Set to Slot"
    saveBtn.TextColor3 = COLORS.TEXT_WHITE
    saveBtn.Font = Enum.Font.GothamBold
    saveBtn.TextSize = 17
    saveBtn.AutoButtonColor = false
    Instance.new("UICorner", saveBtn).CornerRadius = UDim.new(0, 10)

    local slotsHeader = Instance.new("TextLabel", loadoutContent)
    slotsHeader.Size = UDim2.new(1, 0, 0, 30)
    slotsHeader.Position = UDim2.new(0, 0, 0, 184)
    slotsHeader.BackgroundTransparency = 1
    slotsHeader.Font = Enum.Font.GothamBold
    slotsHeader.TextSize = 15
    slotsHeader.TextColor3 = Color3.fromRGB(170, 170, 195)
    slotsHeader.TextXAlignment = Enum.TextXAlignment.Left
    slotsHeader.Text = "📂 Saved Slots (Shift+Click = Delete)"

    local slotsScroll = Instance.new("ScrollingFrame", loadoutContent)
    slotsScroll.Name = "Slots"
    slotsScroll.Size = UDim2.new(1, 0, 1, -222)
    slotsScroll.Position = UDim2.new(0, 0, 0, 218)
    slotsScroll.BackgroundColor3 = Color3.fromRGB(32, 32, 45)
    slotsScroll.ScrollBarThickness = 6
    slotsScroll.ScrollBarImageColor3 = Color3.fromRGB(100, 100, 130)
    slotsScroll.BorderSizePixel = 0
    Instance.new("UICorner", slotsScroll).CornerRadius = UDim.new(0, 10)
    local slotsLayout = Instance.new("UIListLayout", slotsScroll)
    slotsLayout.Name = "Layout"
    slotsLayout.Padding = UDim.new(0, 8)
    slotsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    local slotsPadding = Instance.new("UIPadding", slotsScroll)
    slotsPadding.PaddingTop = UDim.new(0, 8)
    slotsPadding.PaddingBottom = UDim.new(0, 8)
    slotsPadding.PaddingLeft = UDim.new(0, 8)
    slotsPadding.PaddingRight = UDim.new(0, 8)

    local notifFrame = Instance.new("Frame", sg)
    notifFrame.Size = UDim2.new(0, 280, 0, 300)
    notifFrame.Position = UDim2.new(1, -290, 0, 10)
    notifFrame.BackgroundTransparency = 1
    Instance.new("UIListLayout", notifFrame).Padding = UDim.new(0, 8)

    return {
        sg = sg, mf = mf, cb = closeBtn, rb = resetBtn,
        atb = animsTab, ltb = savesTab, ac = animContent, lc = loadoutContent,
        sb = searchBox, cf = catFrame, sf = animList, cnt = countLabel,
        csi = csInfo, svb = saveBtn, ss = slotsScroll, nf = notifFrame
    }
end

local function notify(titleText, msg, dur, col)
    if not gui then return end
    dur = dur or 2
    col = col or COLORS.SUCCESS
    
    local n = Instance.new("Frame")
    n.Size = UDim2.new(1, 0, 0, 64)
    n.BackgroundColor3 = COLORS.BG_MEDIUM
    n.Position = UDim2.new(1, 20, 0, 0)
    n.Parent = gui.nf
    Instance.new("UICorner", n).CornerRadius = UDim.new(0, 12)
    local ns = Instance.new("UIStroke", n)
    ns.Color = col
    ns.Thickness = 2
    
    local accent = Instance.new("Frame", n)
    accent.Size = UDim2.new(0, 5, 1, -14)
    accent.Position = UDim2.new(0, 7, 0, 7)
    accent.BackgroundColor3 = col
    Instance.new("UICorner", accent).CornerRadius = UDim.new(0, 3)
    
    local tl = Instance.new("TextLabel", n)
    tl.Size = UDim2.new(1, -24, 0, 26)
    tl.Position = UDim2.new(0, 20, 0, 8)
    tl.BackgroundTransparency = 1
    tl.Font = Enum.Font.GothamBold
    tl.TextSize = 16
    tl.TextColor3 = col
    tl.TextXAlignment = Enum.TextXAlignment.Left
    tl.Text = titleText
    
    local ml = Instance.new("TextLabel", n)
    ml.Size = UDim2.new(1, -24, 0, 22)
    ml.Position = UDim2.new(0, 20, 0, 34)
    ml.BackgroundTransparency = 1
    ml.Font = Enum.Font.GothamSemibold
    ml.TextSize = 14
    ml.TextColor3 = Color3.fromRGB(180, 180, 200)
    ml.TextXAlignment = Enum.TextXAlignment.Left
    ml.Text = msg
    
    TweenService:Create(n, TWEEN_POPUP_IN, {Position = UDim2.new(0, 0, 0, 0)}):Play()
    
    task.delay(dur, function()
        TweenService:Create(n, TWEEN_SMOOTH, {Position = UDim2.new(1, 20, 0, 0)}):Play()
        task.delay(0.25, function()
            if n and n.Parent then n:Destroy() end
        end)
    end)
end

local function updateInfo()
    if not gui then return end
    
    local lines = {}
    for i = 1, #ANIM_ORDER do
        local aType = ANIM_ORDER[i]
        local data = currentAnimations[aType]
        if data then
            lines[#lines + 1] = "• " .. aType .. ": " .. data.name
        end
    end
    
    if #lines > 0 then
        gui.csi.Text = table.concat(lines, "\n")
        gui.csi.TextColor3 = Color3.fromRGB(150, 230, 160)
    else
        gui.csi.Text = "No animations applied yet\nGo to Animations tab to apply some!"
        gui.csi.TextColor3 = COLORS.TEXT_GRAY
    end
end

local function refreshSlots()
    if not gui then return end
    
    -- Clear existing slots
    local children = gui.ss:GetChildren()
    for i = 1, #children do
        if children[i]:IsA("Frame") then
            children[i]:Destroy()
        end
    end
    
    for i = 1, MAX_SLOTS do
        local data = SavedLoadouts[i]
        local empty = data == nil
        local slotHeight = empty and 65 or 100
        
        local sf = Instance.new("Frame")
        sf.Name = "Slot" .. i
        sf.Size = UDim2.new(1, -10, 0, slotHeight)
        sf.BackgroundColor3 = empty and Color3.fromRGB(42, 42, 58) or Color3.fromRGB(42, 58, 90)
        sf.Parent = gui.ss
        Instance.new("UICorner", sf).CornerRadius = UDim.new(0, 10)
        
        if not empty then
            local stroke = Instance.new("UIStroke", sf)
            stroke.Color = Color3.fromRGB(80, 150, 220)
            stroke.Thickness = 1
        end
        
        local badge = Instance.new("Frame", sf)
        badge.Size = UDim2.new(0, 44, 0, 44)
        badge.Position = UDim2.new(0, 10, 0, 10)
        badge.BackgroundColor3 = empty and Color3.fromRGB(58, 58, 78) or Color3.fromRGB(70, 150, 230)
        Instance.new("UICorner", badge).CornerRadius = UDim.new(0, 10)
        
        local sn = Instance.new("TextLabel", badge)
        sn.Size = UDim2.new(1, 0, 1, 0)
        sn.BackgroundTransparency = 1
        sn.Font = Enum.Font.GothamBold
        sn.TextSize = 22
        sn.TextColor3 = COLORS.TEXT_WHITE
        sn.Text = tostring(i)
        
        if empty then
            local emptyLabel = Instance.new("TextLabel", sf)
            emptyLabel.Size = UDim2.new(1, -130, 1, 0)
            emptyLabel.Position = UDim2.new(0, 64, 0, 0)
            emptyLabel.BackgroundTransparency = 1
            emptyLabel.Font = Enum.Font.GothamSemibold
            emptyLabel.TextSize = 17
            emptyLabel.TextColor3 = Color3.fromRGB(120, 120, 145)
            emptyLabel.TextXAlignment = Enum.TextXAlignment.Left
            emptyLabel.Text = "Empty Slot"
        else
            local titleLabel = Instance.new("TextLabel", sf)
            titleLabel.Size = UDim2.new(1, -140, 0, 26)
            titleLabel.Position = UDim2.new(0, 64, 0, 8)
            titleLabel.BackgroundTransparency = 1
            titleLabel.Font = Enum.Font.GothamBold
            titleLabel.TextSize = 16
            titleLabel.TextColor3 = COLORS.TEXT_WHITE
            titleLabel.TextXAlignment = Enum.TextXAlignment.Left
            titleLabel.Text = "Saved Set #" .. i
            
            local details = {}
            local animCount = 0
            
            for j = 1, #ANIM_ORDER do
                local aType = ANIM_ORDER[j]
                local aData = data.animations[aType]
                if aData then
                    animCount += 1
                    details[#details + 1] = aType .. ": " .. aData.name
                end
            end
            
            local countBadge = Instance.new("TextLabel", sf)
            countBadge.Size = UDim2.new(0, 32, 0, 20)
            countBadge.Position = UDim2.new(0, 64, 0, 36)
            countBadge.BackgroundColor3 = Color3.fromRGB(60, 140, 80)
            countBadge.Font = Enum.Font.GothamBold
            countBadge.TextSize = 12
            countBadge.TextColor3 = COLORS.TEXT_WHITE
            countBadge.Text = tostring(animCount)
            Instance.new("UICorner", countBadge).CornerRadius = UDim.new(0, 5)
            
            local detailsLabel = Instance.new("TextLabel", sf)
            detailsLabel.Size = UDim2.new(1, -140, 0, 50)
            detailsLabel.Position = UDim2.new(0, 100, 0, 32)
            detailsLabel.BackgroundTransparency = 1
            detailsLabel.Font = Enum.Font.Gotham
            detailsLabel.TextSize = 12
            detailsLabel.TextColor3 = Color3.fromRGB(175, 195, 225)
            detailsLabel.TextXAlignment = Enum.TextXAlignment.Left
            detailsLabel.TextYAlignment = Enum.TextYAlignment.Top
            detailsLabel.TextWrapped = true
            detailsLabel.Text = table.concat(details, " • ")
            
            local lb = Instance.new("TextButton", sf)
            lb.Size = UDim2.new(0, 58, 0, 44)
            lb.Position = UDim2.new(1, -68, 0.5, -22)
            lb.BackgroundColor3 = Color3.fromRGB(60, 160, 100)
            lb.Text = "▶"
            lb.TextColor3 = COLORS.TEXT_WHITE
            lb.Font = Enum.Font.GothamBold
            lb.TextSize = 24
            lb.AutoButtonColor = false
            Instance.new("UICorner", lb).CornerRadius = UDim.new(0, 10)
            
            lb.MouseEnter:Connect(function()
                TweenService:Create(lb, TWEEN_FAST, {BackgroundColor3 = Color3.fromRGB(80, 210, 130)}):Play()
            end)
            lb.MouseLeave:Connect(function()
                TweenService:Create(lb, TWEEN_FAST, {BackgroundColor3 = Color3.fromRGB(60, 160, 100)}):Play()
            end)
            
            local slotIndex = i -- Capture for closure
            lb.MouseButton1Click:Connect(function()
                if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift) then
                    SavedLoadouts[slotIndex] = nil
                    saveData()
                    refreshSlots()
                    notify("🗑️ Deleted", "Slot " .. slotIndex .. " cleared", 2, COLORS.ERROR)
                else
                    table.clear(currentAnimations)
                    local loadedCount = 0
                    for t, d in pairs(data.animations) do
                        if setAnim(t, d.id) then
                            currentAnimations[t] = d
                            loadedCount += 1
                        end
                    end
                    updateInfo()
                    notify("✅ Loaded!", loadedCount .. " animations from Slot " .. slotIndex, 2.5, COLORS.SUCCESS)
                end
            end)
        end
    end
    
    task.defer(function()
        local l = gui.ss:FindFirstChild("Layout")
        if l then
            gui.ss.CanvasSize = UDim2.new(0, 0, 0, l.AbsoluteContentSize.Y + 20)
        end
    end)
end

local function createAnimBtn(name, aType, aId)
    if not gui then return end
    
    local typeColor = typeColors[aType] or Color3.fromRGB(150, 150, 150)
    
    local b = Instance.new("TextButton")
    b.Name = name .. "_" .. aType
    b.Size = UDim2.new(1, -10, 0, 48)
    b.BackgroundColor3 = COLORS.BG_LIGHT
    b.Text = ""
    b.AutoButtonColor = false
    b.Parent = gui.sf
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 10)
    
    local accent = Instance.new("Frame", b)
    accent.Size = UDim2.new(0, 5, 1, -14)
    accent.Position = UDim2.new(0, 7, 0, 7)
    accent.BackgroundColor3 = typeColor
    Instance.new("UICorner", accent).CornerRadius = UDim.new(0, 3)
    
    local nl = Instance.new("TextLabel", b)
    nl.Size = UDim2.new(1, -95, 1, 0)
    nl.Position = UDim2.new(0, 20, 0, 0)
    nl.BackgroundTransparency = 1
    nl.Font = Enum.Font.GothamSemibold
    nl.TextSize = 16
    nl.TextColor3 = COLORS.TEXT_WHITE
    nl.TextXAlignment = Enum.TextXAlignment.Left
    nl.Text = name
    nl.TextTruncate = Enum.TextTruncate.AtEnd
    
    local tb = Instance.new("Frame", b)
    tb.Size = UDim2.new(0, 65, 0, 28)
    tb.Position = UDim2.new(1, -75, 0.5, -14)
    tb.BackgroundColor3 = typeColor
    tb.BackgroundTransparency = 0.6
    Instance.new("UICorner", tb).CornerRadius = UDim.new(0, 8)
    Instance.new("UIStroke", tb).Color = typeColor
    
    local tbText = Instance.new("TextLabel", tb)
    tbText.Size = UDim2.new(1, 0, 1, 0)
    tbText.BackgroundTransparency = 1
    tbText.Font = Enum.Font.GothamBold
    tbText.TextSize = 12
    tbText.TextColor3 = typeColor
    tbText.Text = aType:sub(1, 5)
    
    b.MouseEnter:Connect(function()
        TweenService:Create(b, TWEEN_FAST, {BackgroundColor3 = COLORS.BG_HOVER}):Play()
    end)
    b.MouseLeave:Connect(function()
        TweenService:Create(b, TWEEN_FAST, {BackgroundColor3 = COLORS.BG_LIGHT}):Play()
    end)
    
    b.MouseButton1Click:Connect(function()
        if setAnim(aType, aId) then
            currentAnimations[aType] = {name = name, id = aId}
            updateInfo()
            b.BackgroundColor3 = Color3.fromRGB(60, 160, 80)
            task.delay(0.2, function()
                TweenService:Create(b, TWEEN_NORMAL, {BackgroundColor3 = COLORS.BG_LIGHT}):Play()
            end)
            notify("✓ Applied", name .. " → " .. aType, 1.8, COLORS.SUCCESS)
        else
            b.BackgroundColor3 = Color3.fromRGB(160, 60, 60)
            task.delay(0.2, function()
                TweenService:Create(b, TWEEN_NORMAL, {BackgroundColor3 = COLORS.BG_LIGHT}):Play()
            end)
            notify("✗ Failed", "Could not apply", 1.8, COLORS.ERROR)
        end
    end)
    
    buttons[#buttons + 1] = b
end

local function createCatBtn(cat, sel)
    if not gui then return end
    local displayName = cat == "SwimI" and "SwimIdle" or cat
    local catColor = typeColors[displayName] or Color3.fromRGB(150, 150, 150)
    
    local b = Instance.new("TextButton")
    b.Name = displayName
    b.Size = UDim2.new(0, 72, 0, 32)
    b.BackgroundColor3 = sel and catColor or Color3.fromRGB(50, 50, 68)
    b.BackgroundTransparency = sel and 0.2 or 0
    b.Font = Enum.Font.GothamBold
    b.TextSize = 13
    b.TextColor3 = sel and COLORS.TEXT_WHITE or COLORS.TEXT_GRAY
    b.Text = cat == "SwimI" and "SwimI" or cat
    b.AutoButtonColor = false
    b.Parent = gui.cf
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)
    
    if sel then
        local stroke = Instance.new("UIStroke", b)
        stroke.Name = "SelectStroke"
        stroke.Color = catColor
        stroke.Thickness = 2
    end
    
    return b
end

local function populate(cat, search)
    if not gui then return end
    
    -- Clear existing buttons
    for i = 1, #buttons do
        if buttons[i] and buttons[i].Parent then
            buttons[i]:Destroy()
        end
    end
    table.clear(buttons)
    
    search = search and search:lower() or ""
    local count = 0
    
    for i = 1, #ANIM_ORDER do
        local aType = ANIM_ORDER[i]
        if cat == "All" or cat == aType then
            local anims = AnimationData[aType]
            if anims then
                for name, id in pairs(anims) do
                    if search == "" or name:lower():find(search, 1, true) then
                        createAnimBtn(name, aType, id)
                        count += 1
                    end
                end
            end
        end
    end
    
    gui.cnt.Text = count .. " animation" .. (count ~= 1 and "s" or "") .. " found"
    
    task.defer(function()
        local l = gui.sf:FindFirstChild("Layout")
        if l then
            gui.sf.CanvasSize = UDim2.new(0, 0, 0, l.AbsoluteContentSize.Y + 20)
        end
    end)
end

local function setupCats()
    if not gui then return end
    local cats = {"All", "Idle", "Walk", "Run", "Jump", "Fall", "Climb", "Swim", "SwimI"}
    
    for i = 1, #cats do
        local cat = cats[i]
        local displayCat = cat == "SwimI" and "SwimIdle" or cat
        local b = createCatBtn(cat, cat == "All")
        categoryButtons[displayCat] = b
        
        b.MouseButton1Click:Connect(function()
            local targetCat = cat == "SwimI" and "SwimIdle" or cat
            
            for c, cb in pairs(categoryButtons) do
                local sel = c == targetCat
                local catColor = typeColors[c] or Color3.fromRGB(150, 150, 150)
                
                local oldStroke = cb:FindFirstChild("SelectStroke")
                if oldStroke then oldStroke:Destroy() end
                
                if sel then
                    cb.BackgroundColor3 = catColor
                    cb.BackgroundTransparency = 0.2
                    cb.TextColor3 = COLORS.TEXT_WHITE
                    local stroke = Instance.new("UIStroke", cb)
                    stroke.Name = "SelectStroke"
                    stroke.Color = catColor
                    stroke.Thickness = 2
                else
                    cb.BackgroundColor3 = Color3.fromRGB(50, 50, 68)
                    cb.BackgroundTransparency = 0
                    cb.TextColor3 = COLORS.TEXT_GRAY
                end
            end
            
            currentCategory = targetCat
            populate(targetCat, gui.sb.Text)
        end)
    end
    
    gui.cf.CanvasSize = UDim2.new(0, #cats * 80, 0, 0)
end

-- Cache toggle positions
local TOGGLE_OPEN_SIZE = UDim2.new(0, 380, 0, 520)
local TOGGLE_OPEN_POS = UDim2.new(0.5, -190, 0.5, -260)
local TOGGLE_CLOSED_SIZE = UDim2.new(0, 0, 0, 0)
local TOGGLE_CLOSED_POS = UDim2.new(0.5, 0, 0.5, 0)

local function toggle()
    if not gui or not gui.mf then return end
    isGuiVisible = not isGuiVisible
    
    if isGuiVisible then
        gui.mf.Visible = true
        gui.mf.Size = TOGGLE_CLOSED_SIZE
        gui.mf.Position = TOGGLE_CLOSED_POS
        gui.mf.BackgroundTransparency = 1
        
        TweenService:Create(gui.mf, TWEEN_POPUP_OUT, {
            Size = TOGGLE_OPEN_SIZE,
            Position = TOGGLE_OPEN_POS,
            BackgroundTransparency = 0
        }):Play()
    else
        TweenService:Create(gui.mf, TweenInfo.new(0.2, Enum.EasingStyle.Quart), {
            Size = TOGGLE_CLOSED_SIZE,
            Position = TOGGLE_CLOSED_POS,
            BackgroundTransparency = 1
        }):Play()
        
        task.delay(0.2, function()
            if gui and gui.mf then
                gui.mf.Visible = false
            end
        end)
    end
end

local function switchTab(tab)
    if not gui then return end
    currentTab = tab
    gui.ac.Visible = tab == "Anims"
    gui.lc.Visible = tab == "Saves"
    
    if tab == "Anims" then
        gui.atb.BackgroundColor3 = COLORS.ACCENT_BLUE
        gui.atb.TextColor3 = COLORS.TEXT_WHITE
        gui.ltb.BackgroundColor3 = Color3.fromRGB(50, 50, 70)
        gui.ltb.TextColor3 = COLORS.TEXT_GRAY
    else
        gui.atb.BackgroundColor3 = Color3.fromRGB(50, 50, 70)
        gui.atb.TextColor3 = COLORS.TEXT_GRAY
        gui.ltb.BackgroundColor3 = COLORS.ACCENT_BLUE
        gui.ltb.TextColor3 = COLORS.TEXT_WHITE
        refreshSlots()
        updateInfo()
    end
end

local function onCharacterAdded(char)
    -- Reset cache
    cachedChar = nil
    cachedHumanoid = nil
    cachedAnimate = nil
    
    task.wait(1.5)
    
    local anim = char:WaitForChild("Animate", 10)
    if not anim then return end
    
    local hasAnims = false
    local count = 0
    
    for t, d in pairs(currentAnimations) do
        if d and d.id then
            task.wait(0.05)
            if setAnim(t, d.id) then
                count += 1
            end
            hasAnims = true
        end
    end
    
    if hasAnims then
        notify("🔄 Restored", count .. " animations reapplied", 2, COLORS.INFO)
    end
end

local function setup()
    local char = player.Character or player.CharacterAdded:Wait()
    char:WaitForChild("Humanoid", 15)
    char:WaitForChild("Animate", 15)
    
    if not checkR15() then
        warn("Animation Changer requires R15!")
        return
    end
    
    local dbLoaded = loadAnimations()
    
    gui = createGui()
    setupCats()
    populate("All", "")
    refreshSlots()
    updateInfo()
    
    -- Connect events
    gui.sb:GetPropertyChangedSignal("Text"):Connect(function()
        populate(currentCategory, gui.sb.Text)
    end)
    
    gui.atb.MouseButton1Click:Connect(function() switchTab("Anims") end)
    gui.ltb.MouseButton1Click:Connect(function() switchTab("Saves") end)
    
    gui.cb.MouseEnter:Connect(function()
        gui.cb.BackgroundColor3 = COLORS.ACCENT_RED_HOVER
    end)
    gui.cb.MouseLeave:Connect(function()
        gui.cb.BackgroundColor3 = COLORS.ACCENT_RED
    end)
    gui.cb.MouseButton1Click:Connect(toggle)
    
    gui.rb.MouseEnter:Connect(function()
        gui.rb.BackgroundColor3 = Color3.fromRGB(90, 90, 130)
    end)
    gui.rb.MouseLeave:Connect(function()
        gui.rb.BackgroundColor3 = Color3.fromRGB(70, 70, 100)
    end)
    gui.rb.MouseButton1Click:Connect(function()
        resetAnims()
        updateInfo()
        notify("↺ Reset", "All animations restored to default", 2, Color3.fromRGB(160, 160, 200))
    end)
    
    gui.svb.MouseEnter:Connect(function()
        gui.svb.BackgroundColor3 = COLORS.ACCENT_GREEN_HOVER
    end)
    gui.svb.MouseLeave:Connect(function()
        gui.svb.BackgroundColor3 = COLORS.ACCENT_GREEN
    end)
    gui.svb.MouseButton1Click:Connect(function()
        local hasAnims = next(currentAnimations) ~= nil
        if not hasAnims then
            notify("⚠️ Empty", "Apply animations first!", 2, COLORS.WARNING)
            return
        end
        
        local slot
        for i = 1, MAX_SLOTS do
            if not SavedLoadouts[i] then
                slot = i
                break
            end
        end
        
        if not slot then
            notify("❌ Full", "All slots used! Shift+Click to delete", 2.5, COLORS.ERROR)
            return
        end
        
        SavedLoadouts[slot] = {name = "Slot" .. slot, animations = {}}
        for t, d in pairs(currentAnimations) do
            SavedLoadouts[slot].animations[t] = {name = d.name, id = d.id}
        end
        saveData()
        refreshSlots()
        
        local animCount = 0
        for _ in pairs(currentAnimations) do animCount += 1 end
        notify("💾 Saved!", animCount .. " animations to Slot " .. slot, 2, COLORS.SUCCESS)
    end)
    
    player.CharacterAdded:Connect(onCharacterAdded)
    
    -- Count total animations
    local totalAnims = 0
    for _, anims in pairs(AnimationData) do
        for _ in pairs(anims) do totalAnims += 1 end
    end
    
    print("═══════════════════════════════════════════════════")
    print("🎭 Animation Changer v3.6 Loaded! (OPTIMIZED)")
    print("📊 Total Animations: " .. totalAnims)
    print("🌐 Database: " .. (dbLoaded and "External" or "Fallback"))
    print("⌨️ Press RIGHT CONTROL to toggle")
    print("═══════════════════════════════════════════════════")
    
    task.delay(0.5, function()
        local dbStatus = dbLoaded and "External DB" or "Fallback DB"
        notify("🎭 Ready!", totalAnims .. " anims • " .. dbStatus .. " • RCtrl", 3, COLORS.INFO)
    end)
end

UserInputService.InputBegan:Connect(function(input, gp)
    if gp then return end
    if input.KeyCode == Enum.KeyCode.RightControl then
        toggle()
    end
end)

setup()
