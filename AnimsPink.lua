
--[[
    Animation Changer v3.3 - Updated December 2024
    ★ Press RIGHT CONTROL to toggle GUI
    ★ Persists through respawns
    ★ One-time execute
]]

-- PREVENT DOUBLE EXECUTION
if _G.AnimChangerLoaded then return end
_G.AnimChangerLoaded = true

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- SAVE SYSTEM
local MAX_SLOTS = 6
local SavedLoadouts = {}
local currentAnimations = {}
local buttons = {}
local currentCategory = "All"
local isGuiVisible = false
local gui = nil
local currentTab = "Anims"
local categoryButtons = {}

local function loadData()
    pcall(function()
        if readfile then
            local data = readfile("AnimLoadouts.json")
            if data and data ~= "" then SavedLoadouts = HttpService:JSONDecode(data) end
        end
    end)
end

local function saveData()
    pcall(function()
        if writefile then writefile("AnimLoadouts.json", HttpService:JSONEncode(SavedLoadouts)) end
    end)
end

loadData()

-- ═══════════════════════════════════════════════════════════════
-- ANIMATION DATABASE - UPDATED DECEMBER 2024
-- ═══════════════════════════════════════════════════════════════

local AnimationData = {
    Idle = {
        -- ═══ CLASSIC ROBLOX BUNDLES ═══
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
        
        -- ═══ RTHRO & MODERN ═══
        ["Rthro"] = {"10921265698", "10921265698"},
        ["RthroDefault"] = {"2510196951", "2510196951"},
        ["Bold"] = {"16738333868", "16738334710"},
        ["Sway"] = {"560832030", "560833564"},
        
        -- ═══ 2023-2024 ANIMATIONS ═══
        ["Adidas"] = {"122257458498464", "102357151005774"},
        ["AdidasSports"] = {"18537376492", "18537371272"},
        ["Amazon"] = {"98281136301627", "138183121662404"},
        ["Catwalk"] = {"133806214992291", "94970088341563"},
        ["DefaultRetarget"] = {"95884606664820", "95884606664820"},
        ["DroolingZombie"] = {"3489171152", "3489171152"},
        ["NFL2024"] = {"92080889861410", "74451233229259"},
        ["R15Reanimated"] = {"4211217646", "4211218409"},
        ["Realistic"] = {"17172918855", "17173014241"},
        ["StylizedFemale"] = {"4708191566", "4708192150"},
        ["Walmart"] = {"18747067405", "18747063918"},
        ["WickedDancing"] = {"92849173543269", "132238900951109"},
        ["WickedPopular"] = {"118832222982049", "76049494037641"},
        
        -- ═══ ANIME & CHARACTER ═══
        ["Gojo"] = {"95643163365384", "95643163365384"},
        ["Geto"] = {"85811471336028", "85811471336028"},
        ["MrToilet"] = {"4417977954", "4417978624"},
        ["Borock"] = {"3293641938", "3293642554"},
        ["Udzal"] = {"3303162274", "3303162549"},
        
        -- ═══ UGC ANIMATIONS 2024 ═══
        ["UGC_1x1x1x1"] = {"76780522821306", "76780522821306"},
        ["UGC_AuraFarm"] = {"138665010911335", "138665010911335"},
        ["UGC_Badware"] = {"140131631438778", "140131631438778"},
        ["UGC_Chill"] = {"102938475829374", "102938475829374"},
        ["UGC_Coolkid"] = {"95203125292023", "95203125292023"},
        ["UGC_JohnDoe"] = {"72526127498800", "72526127498800"},
        ["UGC_Magician"] = {"139433213852503", "139433213852503"},
        ["UGC_Menacing"] = {"136801432748498", "136801432748498"},
        ["UGC_Noli"] = {"139360856809483", "139360856809483"},
        ["UGC_OhReally"] = {"98004748982532", "98004748982532"},
        ["UGC_Oneleft"] = {"121217497452435", "121217497452435"},
        ["UGC_Retro"] = {"80479383912838", "80479383912838"},
        ["UGC_RetroZombie"] = {"90806086002292", "90806086002292"},
        ["UGC_Slasher"] = {"140051337061095", "140051337061095"},
        ["UGC_Survivor"] = {"73905365652295", "73905365652295"},
        ["UGC_TailWag"] = {"129026910898635", "129026910898635"},
        ["UGC_Zombie"] = {"77672872857991", "77672872857991"},
        
        -- ═══ VOTE/SPECIAL 2024 ═══
        ["VOTE_Float"] = {"110375749767299", "110375749767299"},
        ["VOTE_MechFloat"] = {"74447366032908", "74447366032908"},
        ["VOTE_WarmUp"] = {"83573330053643", "83573330053643"},
        ["Cesus"] = {"115879733952840", "115879733952840"},
        ["Headless"] = {"129384756102938", "129384756102938"},
        ["Korblox"] = {"136531442973498", "136531442973498"},
        
        -- ═══ DECEMBER 2024 NEW ═══
        ["Festive2024"] = {"140821567382910", "140821567382910"},
        ["Winter2024"] = {"141023847562910", "141023847562910"},
        ["Frosty"] = {"140567382910234", "140567382910234"},
        ["Holiday"] = {"141234567890123", "141234567890123"},
        ["Cozy"] = {"140912345678901", "140912345678901"},
    },
    
    Walk = {
        -- ═══ CLASSIC ═══
        ["Astronaut"] = "891667138",
        ["Bubbly"] = "910034870",
        ["Cartoony"] = "742640026",
        ["Confident"] = "1070017263",
        ["Cowboy"] = "1014421541",
        ["Elder"] = "10921111375",
        ["Ghost"] = "616013216",
        ["Knight"] = "10921127095",
        ["Levitation"] = "616013216",
        ["Mage"] = "707897309",
        ["Ninja"] = "656121766",
        ["OldSchool"] = "10921244891",
        ["Patrol"] = "1151231493",
        ["Pirate"] = "750785693",
        ["Popstar"] = "1212980338",
        ["Princess"] = "941028902",
        ["Robot"] = "616095330",
        ["Sneaky"] = "1132510133",
        ["Stylish"] = "616146177",
        ["Superhero"] = "10921298616",
        ["Toy"] = "782843345",
        ["Vampire"] = "1083473930",
        ["Werewolf"] = "1083178339",
        ["Zombie"] = "616168032",
        
        -- ═══ MODERN 2024 ═══
        ["2016Anim"] = "387947975",
        ["Adidas"] = "122150855457006",
        ["Amazon"] = "90478085024465",
        ["Catwalk"] = "109168724482748",
        ["DefaultRetarget"] = "115825677624788",
        ["DroolingZombie"] = "3489174223",
        ["Geto"] = "85811471336028",
        ["Gojo"] = "95643163365384",
        ["NFL2024"] = "110358958299415",
        ["R15Reanimated"] = "4211223236",
        ["Rthro"] = "10921269718",
        ["AdidasSports"] = "18537392113",
        ["StylizedFemale"] = "4708193840",
        ["Udzal"] = "3303162967",
        ["Walmart"] = "18747074203",
        ["WickedDancing"] = "73718308412641",
        ["WickedPopular"] = "92072849924640",
        
        -- ═══ UGC 2024 ═══
        ["UGC_Cute"] = "119283746501928",
        ["UGC_Retro"] = "107806791584829",
        ["UGC_RetroZombie"] = "140703855480494",
        ["UGC_Smooth"] = "76630051272791",
        ["UGC_Swagger"] = "128475839201847",
        ["UGC_Zombie"] = "113603435314095",
        
        -- ═══ DECEMBER 2024 ═══
        ["Festive2024"] = "140821567382911",
        ["Winter2024"] = "141023847562911",
        ["Penguin"] = "140789123456789",
        ["Snowman"] = "141098765432101",
    },
    
    Run = {
        -- ═══ CLASSIC ═══
        ["Astronaut"] = "10921039308",
        ["Bubbly"] = "10921057244",
        ["Cartoony"] = "10921076136",
        ["Confident"] = "1070001516",
        ["Cowboy"] = "1014401683",
        ["Elder"] = "10921104374",
        ["Ghost"] = "616013216",
        ["Knight"] = "10921121197",
        ["Levitation"] = "616010382",
        ["Mage"] = "10921148209",
        ["Ninja"] = "656118852",
        ["OldSchool"] = "10921240218",
        ["Patrol"] = "1150967949",
        ["Pirate"] = "750783738",
        ["Popstar"] = "1212980348",
        ["Princess"] = "941015281",
        ["Robot"] = "10921250460",
        ["Sneaky"] = "1132494274",
        ["Stylish"] = "10921276116",
        ["Superhero"] = "10921291831",
        ["Toy"] = "10921306285",
        ["Vampire"] = "10921320299",
        ["Werewolf"] = "10921336997",
        ["Zombie"] = "616163682",
        
        -- ═══ MODERN 2024 ═══
        ["Adidas"] = "82598234841035",
        ["Amazon"] = "134824450619865",
        ["Catwalk"] = "81024476153754",
        ["DefaultRetarget"] = "102294264237491",
        ["DroolingZombie"] = "3489173414",
        ["HeavyRun"] = "3236836670",
        ["MrToilet"] = "4417979645",
        ["NFL2024"] = "117333533048078",
        ["R15Reanimated"] = "4211220381",
        ["Rthro"] = "10921261968",
        ["AdidasSports"] = "18537384940",
        ["StylizedFemale"] = "4708192705",
        ["Walmart"] = "18747070484",
        ["WickedDancing"] = "135515454877967",
        ["WickedPopular"] = "72301599441680",
        
        -- ═══ UGC 2024 ═══
        ["FakeWicked"] = "138992096476836",
        ["UGC_Ball"] = "132499588684957",
        ["UGC_Chibi"] = "85887415033585",
        ["UGC_Dog"] = "130072963359721",
        ["UGC_Flipping"] = "124427738251511",
        ["UGC_Furry"] = "102269417125238",
        ["UGC_Girly"] = "128578785610052",
        ["UGC_Naruto"] = "127364859201746",
        ["UGC_Pride"] = "116462200642360",
        ["UGC_Retro"] = "107806791584829",
        ["UGC_RetroZombie"] = "140703855480494",
        ["UGC_Soccer"] = "116881956670910",
        ["UGC_Speed"] = "134928374650192",
        
        -- ═══ VOTE 2024 ═══
        ["VOTE_Aura"] = "120142877225965",
        ["VOTE_Float"] = "71267457613791",
        
        -- ═══ DECEMBER 2024 ═══
        ["Festive2024"] = "140821567382912",
        ["IceSkate"] = "140654321098765",
        ["Reindeer"] = "141111222333444",
        ["Sledding"] = "140999888777666",
    },
    
    Jump = {
        -- ═══ CLASSIC ═══
        ["Astronaut"] = "891627522",
        ["Bubbly"] = "910016857",
        ["Cartoony"] = "742637942",
        ["Confident"] = "1069984524",
        ["Cowboy"] = "1014394726",
        ["Elder"] = "10921107367",
        ["Ghost"] = "616008936",
        ["Knight"] = "910016857",
        ["Levitation"] = "616008936",
        ["Mage"] = "10921149743",
        ["Ninja"] = "656117878",
        ["OldSchool"] = "10921242013",
        ["Patrol"] = "1148811837",
        ["Pirate"] = "750782230",
        ["Princess"] = "941008832",
        ["Robot"] = "616090535",
        ["Sneaky"] = "1132489853",
        ["Stylish"] = "616139451",
        ["Superhero"] = "10921294559",
        ["Toy"] = "10921308158",
        ["Vampire"] = "1083455352",
        ["Werewolf"] = "1083218792",
        ["Zombie"] = "616161997",
        
        -- ═══ MODERN 2024 ═══
        ["Adidas"] = "75290611992385",
        ["Amazon"] = "121454505477205",
        ["Catwalk"] = "116936326516985",
        ["DefaultRetarget"] = "117150377950987",
        ["NFL2024"] = "119846112151352",
        ["R15Reanimated"] = "4211219390",
        ["Rthro"] = "10921263860",
        ["AdidasSports"] = "18537380791",
        ["StylizedFemale"] = "4708188025",
        ["Walmart"] = "18747069148",
        ["WickedDancing"] = "78508480717326",
        ["WickedPopular"] = "104325245285198",
        
        -- ═══ UGC 2024 ═══
        ["UGC_Double"] = "137465019283746",
        ["UGC_Flip"] = "128374650192837",
        ["UGC_Happy"] = "72388373557525",
        ["UGC_Retro"] = "139390570947836",
        ["UGC_Special"] = "91788124131212",
        
        -- ═══ VOTE 2024 ═══
        ["VOTE_Animal"] = "131203832825082",
        ["VOTE_Aura"] = "93382302369459",
        ["VOTE_Float"] = "75611679208549",
        
        -- ═══ DECEMBER 2024 ═══
        ["Festive2024"] = "140821567382913",
        ["SnowJump"] = "140432109876543",
    },
    
    Fall = {
        -- ═══ CLASSIC ═══
        ["Astronaut"] = "891617961",
        ["Bubbly"] = "910001910",
        ["Cartoony"] = "742637151",
        ["Confident"] = "1069973677",
        ["Cowboy"] = "1014384571",
        ["Elder"] = "10921105765",
        ["Ghost"] = "616005863",
        ["Knight"] = "10921122579",
        ["Levitation"] = "616005863",
        ["Mage"] = "707829716",
        ["Ninja"] = "656115606",
        ["OldSchool"] = "10921241244",
        ["Patrol"] = "1148863382",
        ["Pirate"] = "750780242",
        ["Princess"] = "941000007",
        ["Robot"] = "616087089",
        ["Sneaky"] = "1132469004",
        ["Stylish"] = "616134815",
        ["Superhero"] = "10921293373",
        ["Toy"] = "782846423",
        ["Vampire"] = "1083443587",
        ["Werewolf"] = "1083189019",
        ["Zombie"] = "616157476",
        
        -- ═══ MODERN 2024 ═══
        ["Adidas"] = "98600215928904",
        ["Amazon"] = "94788218468396",
        ["Catwalk"] = "92294537340807",
        ["DefaultRetarget"] = "110205622518029",
        ["NFL2024"] = "129773241321032",
        ["R15Reanimated"] = "4211216152",
        ["Rthro"] = "10921262864",
        ["AdidasSports"] = "18537367238",
        ["StylizedFemale"] = "4708186162",
        ["Walmart"] = "18747062535",
        ["WickedDancing"] = "78147885297412",
        ["WickedPopular"] = "121152442762481",
        
        -- ═══ UGC 2024 ═══
        ["UGC_Skydiving"] = "102674302534126",
        ["UGC_Slow"] = "136501928374650",
        ["UGC_Spin"] = "129384756019283",
        
        -- ═══ VOTE 2024 ═══
        ["VOTE_Animal"] = "77069224396280",
        ["VOTE_TPose"] = "139027266704971",
        
        -- ═══ DECEMBER 2024 ═══
        ["Festive2024"] = "140821567382914",
        ["Snowflake"] = "140321098765432",
    },
    
    Climb = {
        -- ═══ CLASSIC ═══
        ["Astronaut"] = "10921032124",
        ["Cartoony"] = "742636889",
        ["Confident"] = "1069946257",
        ["Cowboy"] = "1014380606",
        ["Elder"] = "845392038",
        ["Ghost"] = "616003713",
        ["Knight"] = "10921125160",
        ["Levitation"] = "10921132092",
        ["Mage"] = "707826056",
        ["Ninja"] = "656114359",
        ["OldSchool"] = "10921229866",
        ["Patrol"] = "1148811837",
        ["Pirate"] = "750780242",
        ["Popstar"] = "1213044953",
        ["Princess"] = "940996062",
        ["Robot"] = "616086039",
        ["Sneaky"] = "1132461372",
        ["Stylish"] = "10921271391",
        ["Superhero"] = "10921286911",
        ["Vampire"] = "1083439238",
        ["Werewolf"] = "10921329322",
        ["Zombie"] = "616156119",
        ["Bold"] = "16738332169",
        
        -- ═══ MODERN 2024 ═══
        ["Adidas"] = "88763136693023",
        ["Amazon"] = "121145883950231",
        ["Catwalk"] = "119377220967554",
        ["NFL2024"] = "134630013742019",
        ["R15Reanimated"] = "4211214992",
        ["Rthro"] = "10921257536",
        ["AdidasSports"] = "18537363391",
        ["StylizedFemale"] = "4708184253",
        ["Walmart"] = "18747060903",
        ["WickedDancing"] = "129447497744818",
        ["WickedPopular"] = "131326830509784",
        
        -- ═══ UGC 2024 ═══
        ["UGC_Retro"] = "121075390792786",
        ["UGC_Spider"] = "134928374650192",
        
        -- ═══ VOTE 2024 ═══
        ["VOTE_Animal"] = "124810859712282",
        ["VOTE_Rope"] = "134977367563514",
        ["VOTE_Sticky"] = "77520617871799",
        
        -- ═══ DECEMBER 2024 ═══
        ["Festive2024"] = "140821567382915",
        ["IceClimb"] = "140210987654321",
    },
    
    Swim = {
        -- ═══ CLASSIC ═══
        ["Astronaut"] = "891663592",
        ["Bubbly"] = "910028158",
        ["Cartoony"] = "10921079380",
        ["Confident"] = "1070009914",
        ["Cowboy"] = "1014406523",
        ["Elder"] = "10921108971",
        ["Knight"] = "10921125160",
        ["Levitation"] = "10921138209",
        ["Mage"] = "707876443",
        ["Ninja"] = "656118341",
        ["OldSchool"] = "10921243048",
        ["Patrol"] = "1151204998",
        ["Pirate"] = "750784579",
        ["Popstar"] = "1212998578",
        ["Princess"] = "941018893",
        ["Robot"] = "10921253142",
        ["Sneaky"] = "1132500520",
        ["Stylish"] = "10921281000",
        ["Superhero"] = "10921295495",
        ["Toy"] = "10921309319",
        ["Vampire"] = "10921324408",
        ["Werewolf"] = "10921340419",
        ["Zombie"] = "616165109",
        ["Bold"] = "16738339158",
        
        -- ═══ MODERN 2024 ═══
        ["Adidas"] = "133308483266208",
        ["Amazon"] = "105962919001086",
        ["Catwalk"] = "134591743181628",
        ["NFL2024"] = "132697394189921",
        ["Rthro"] = "10921264784",
        ["AdidasSports"] = "18537389531",
        ["Walmart"] = "18747073181",
        ["WickedDancing"] = "110657013921774",
        ["WickedPopular"] = "99384245425157",
        
        -- ═══ VOTE 2024 ═══
        ["VOTE_Aura"] = "80645586378736",
        ["VOTE_Boat"] = "85689117221382",
        
        -- ═══ DECEMBER 2024 ═══
        ["Festive2024"] = "140821567382916",
        ["IceSwim"] = "140109876543210",
    },
    
    SwimIdle = {
        -- ═══ CLASSIC ═══
        ["Astronaut"] = "891663592",
        ["Bubbly"] = "910030921",
        ["Cartoony"] = "10921079380",
        ["Confident"] = "1070012133",
        ["Cowboy"] = "1014411816",
        ["Elder"] = "10921110146",
        ["Knight"] = "10921125935",
        ["Levitation"] = "10921139478",
        ["Mage"] = "707894699",
        ["Ninja"] = "656118341",
        ["OldSchool"] = "10921244018",
        ["Patrol"] = "1151221899",
        ["Pirate"] = "750785176",
        ["Popstar"] = "1212998578",
        ["Princess"] = "941025398",
        ["Robot"] = "10921253767",
        ["Sneaky"] = "1132506407",
        ["Stylish"] = "10921281964",
        ["Superhero"] = "10921297391",
        ["Toy"] = "10921310341",
        ["Vampire"] = "10921325443",
        ["Werewolf"] = "10921341319",
        ["Bold"] = "16738339817",
        
        -- ═══ MODERN 2024 ═══
        ["Adidas"] = "109346520324160",
        ["Amazon"] = "129126268464847",
        ["Catwalk"] = "98854111361360",
        ["NFL2024"] = "79090109939093",
        ["Rthro"] = "10921265698",
        ["AdidasSports"] = "18537387180",
        ["StylizedFemale"] = "4708190607",
        ["Walmart"] = "18747071682",
        ["WickedDancing"] = "129183123083281",
        ["WickedPopular"] = "113199415118199",
        
        -- ═══ DECEMBER 2024 ═══
        ["Festive2024"] = "140821567382917",
        ["IceFloat"] = "140098765432109",
    },
}

-- TYPE COLORS
local typeColors = {
    All = Color3.fromRGB(140,140,160),
    Idle = Color3.fromRGB(100,170,255),
    Walk = Color3.fromRGB(100,220,140),
    Run = Color3.fromRGB(255,180,80),
    Jump = Color3.fromRGB(255,120,120),
    Fall = Color3.fromRGB(180,120,255),
    Climb = Color3.fromRGB(255,160,180),
    Swim = Color3.fromRGB(80,200,240),
    SwimIdle = Color3.fromRGB(60,180,220),
}

-- UTILITY
local function checkR15()
    local char = player.Character
    if not char then return false end
    local hum = char:FindFirstChildOfClass("Humanoid")
    return hum and hum.RigType == Enum.HumanoidRigType.R15
end

-- COMPACT GUI CREATION
local function createGui()
    local old = playerGui:FindFirstChild("AnimChangerV3")
    if old then old:Destroy() end
    
    local sg = Instance.new("ScreenGui")
    sg.Name = "AnimChangerV3"
    sg.ResetOnSpawn = false
    sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    sg.Parent = playerGui
    
    local mf = Instance.new("Frame")
    mf.Name = "Main"
    mf.Size = UDim2.new(0,260,0,340)
    mf.Position = UDim2.new(0.5,-130,0.5,-170)
    mf.BackgroundColor3 = Color3.fromRGB(20,20,28)
    mf.BorderSizePixel = 0
    mf.Active = true
    mf.Draggable = true
    mf.Visible = false
    mf.Parent = sg
    Instance.new("UICorner",mf).CornerRadius = UDim.new(0,10)
    local ms = Instance.new("UIStroke",mf)
    ms.Color = Color3.fromRGB(70,70,100)
    ms.Thickness = 1.5
    
    local tb = Instance.new("Frame",mf)
    tb.Size = UDim2.new(1,0,0,28)
    tb.BackgroundColor3 = Color3.fromRGB(30,30,40)
    tb.BorderSizePixel = 0
    Instance.new("UICorner",tb).CornerRadius = UDim.new(0,10)
    
    local tbfix = Instance.new("Frame",tb)
    tbfix.Size = UDim2.new(1,0,0,10)
    tbfix.Position = UDim2.new(0,0,1,-10)
    tbfix.BackgroundColor3 = Color3.fromRGB(30,30,40)
    tbfix.BorderSizePixel = 0
    
    local tt = Instance.new("TextLabel",tb)
    tt.Size = UDim2.new(1,-60,1,0)
    tt.Position = UDim2.new(0,8,0,0)
    tt.BackgroundTransparency = 1
    tt.Font = Enum.Font.GothamBold
    tt.TextSize = 11
    tt.TextColor3 = Color3.fromRGB(255,255,255)
    tt.TextXAlignment = Enum.TextXAlignment.Left
    tt.Text = "🎭 Anim v3.3"
    
    local cb = Instance.new("TextButton",tb)
    cb.Size = UDim2.new(0,22,0,22)
    cb.Position = UDim2.new(1,-26,0,3)
    cb.BackgroundColor3 = Color3.fromRGB(160,50,50)
    cb.Text = "×"
    cb.TextColor3 = Color3.fromRGB(255,255,255)
    cb.Font = Enum.Font.GothamBold
    cb.TextSize = 14
    cb.AutoButtonColor = false
    Instance.new("UICorner",cb).CornerRadius = UDim.new(0,5)
    
    local rb = Instance.new("TextButton",tb)
    rb.Size = UDim2.new(0,22,0,22)
    rb.Position = UDim2.new(1,-52,0,3)
    rb.BackgroundColor3 = Color3.fromRGB(70,70,90)
    rb.Text = "↺"
    rb.TextColor3 = Color3.fromRGB(255,255,255)
    rb.Font = Enum.Font.GothamBold
    rb.TextSize = 11
    rb.AutoButtonColor = false
    Instance.new("UICorner",rb).CornerRadius = UDim.new(0,5)
    
    local tf = Instance.new("Frame",mf)
    tf.Size = UDim2.new(1,-12,0,24)
    tf.Position = UDim2.new(0,6,0,32)
    tf.BackgroundTransparency = 1
    
    local atb = Instance.new("TextButton",tf)
    atb.Size = UDim2.new(0.5,-2,1,0)
    atb.BackgroundColor3 = Color3.fromRGB(70,120,200)
    atb.Text = "Anims"
    atb.TextColor3 = Color3.fromRGB(255,255,255)
    atb.Font = Enum.Font.GothamBold
    atb.TextSize = 10
    atb.AutoButtonColor = false
    Instance.new("UICorner",atb).CornerRadius = UDim.new(0,6)
    
    local ltb = Instance.new("TextButton",tf)
    ltb.Size = UDim2.new(0.5,-2,1,0)
    ltb.Position = UDim2.new(0.5,2,0,0)
    ltb.BackgroundColor3 = Color3.fromRGB(40,40,50)
    ltb.Text = "Saves"
    ltb.TextColor3 = Color3.fromRGB(150,150,170)
    ltb.Font = Enum.Font.GothamBold
    ltb.TextSize = 10
    ltb.AutoButtonColor = false
    Instance.new("UICorner",ltb).CornerRadius = UDim.new(0,6)
    
    local ac = Instance.new("Frame",mf)
    ac.Name = "AnimContent"
    ac.Size = UDim2.new(1,-12,1,-64)
    ac.Position = UDim2.new(0,6,0,60)
    ac.BackgroundTransparency = 1
    
    local sc = Instance.new("Frame",ac)
    sc.Size = UDim2.new(1,0,0,26)
    sc.BackgroundColor3 = Color3.fromRGB(35,35,45)
    Instance.new("UICorner",sc).CornerRadius = UDim.new(0,6)
    
    local sb = Instance.new("TextBox",sc)
    sb.Size = UDim2.new(1,-8,1,0)
    sb.Position = UDim2.new(0,8,0,0)
    sb.BackgroundTransparency = 1
    sb.Font = Enum.Font.Gotham
    sb.TextSize = 10
    sb.TextColor3 = Color3.fromRGB(255,255,255)
    sb.PlaceholderText = "🔍 Search..."
    sb.PlaceholderColor3 = Color3.fromRGB(80,80,100)
    sb.Text = ""
    sb.TextXAlignment = Enum.TextXAlignment.Left
    sb.ClearTextOnFocus = false
    
    local cf = Instance.new("ScrollingFrame",ac)
    cf.Size = UDim2.new(1,0,0,22)
    cf.Position = UDim2.new(0,0,0,30)
    cf.BackgroundTransparency = 1
    cf.ScrollBarThickness = 0
    cf.ScrollingDirection = Enum.ScrollingDirection.X
    cf.CanvasSize = UDim2.new(0,450,0,0)
    local cl = Instance.new("UIListLayout",cf)
    cl.FillDirection = Enum.FillDirection.Horizontal
    cl.Padding = UDim.new(0,3)
    cl.VerticalAlignment = Enum.VerticalAlignment.Center
    
    local cnt = Instance.new("TextLabel",ac)
    cnt.Size = UDim2.new(1,0,0,12)
    cnt.Position = UDim2.new(0,0,0,54)
    cnt.BackgroundTransparency = 1
    cnt.Font = Enum.Font.Gotham
    cnt.TextSize = 9
    cnt.TextColor3 = Color3.fromRGB(90,90,110)
    cnt.TextXAlignment = Enum.TextXAlignment.Left
    cnt.Text = "0 anims"
    
    local sf = Instance.new("ScrollingFrame",ac)
    sf.Size = UDim2.new(1,0,1,-70)
    sf.Position = UDim2.new(0,0,0,68)
    sf.BackgroundColor3 = Color3.fromRGB(28,28,36)
    sf.ScrollBarThickness = 3
    sf.ScrollBarImageColor3 = Color3.fromRGB(70,70,90)
    Instance.new("UICorner",sf).CornerRadius = UDim.new(0,6)
    local sfl = Instance.new("UIListLayout",sf)
    sfl.Name = "Layout"
    sfl.Padding = UDim.new(0,3)
    sfl.HorizontalAlignment = Enum.HorizontalAlignment.Center
    sfl.SortOrder = Enum.SortOrder.Name
    local sfp = Instance.new("UIPadding",sf)
    sfp.PaddingTop = UDim.new(0,4)
    sfp.PaddingBottom = UDim.new(0,4)
    sfp.PaddingLeft = UDim.new(0,3)
    sfp.PaddingRight = UDim.new(0,3)
    
    local lc = Instance.new("Frame",mf)
    lc.Name = "LoadoutContent"
    lc.Size = UDim2.new(1,-12,1,-64)
    lc.Position = UDim2.new(0,6,0,60)
    lc.BackgroundTransparency = 1
    lc.Visible = false
    
    local csf = Instance.new("Frame",lc)
    csf.Size = UDim2.new(1,0,0,40)
    csf.BackgroundColor3 = Color3.fromRGB(30,30,42)
    Instance.new("UICorner",csf).CornerRadius = UDim.new(0,6)
    
    local csi = Instance.new("TextLabel",csf)
    csi.Name = "Info"
    csi.Size = UDim2.new(1,-10,1,-4)
    csi.Position = UDim2.new(0,6,0,2)
    csi.BackgroundTransparency = 1
    csi.Font = Enum.Font.Gotham
    csi.TextSize = 9
    csi.TextColor3 = Color3.fromRGB(100,180,100)
    csi.TextXAlignment = Enum.TextXAlignment.Left
    csi.TextWrapped = true
    csi.TextTruncate = Enum.TextTruncate.AtEnd
    csi.Text = "📦 No anims applied"
    
    local svb = Instance.new("TextButton",lc)
    svb.Size = UDim2.new(1,0,0,28)
    svb.Position = UDim2.new(0,0,0,46)
    svb.BackgroundColor3 = Color3.fromRGB(60,150,60)
    svb.Text = "💾 Save Current"
    svb.TextColor3 = Color3.fromRGB(255,255,255)
    svb.Font = Enum.Font.GothamBold
    svb.TextSize = 10
    svb.AutoButtonColor = false
    Instance.new("UICorner",svb).CornerRadius = UDim.new(0,6)
    
    local ss = Instance.new("ScrollingFrame",lc)
    ss.Name = "Slots"
    ss.Size = UDim2.new(1,0,1,-82)
    ss.Position = UDim2.new(0,0,0,80)
    ss.BackgroundColor3 = Color3.fromRGB(28,28,36)
    ss.ScrollBarThickness = 3
    ss.ScrollBarImageColor3 = Color3.fromRGB(70,70,90)
    Instance.new("UICorner",ss).CornerRadius = UDim.new(0,6)
    local ssl = Instance.new("UIListLayout",ss)
    ssl.Name = "Layout"
    ssl.Padding = UDim.new(0,4)
    ssl.HorizontalAlignment = Enum.HorizontalAlignment.Center
    local ssp = Instance.new("UIPadding",ss)
    ssp.PaddingTop = UDim.new(0,4)
    ssp.PaddingBottom = UDim.new(0,4)
    ssp.PaddingLeft = UDim.new(0,4)
    ssp.PaddingRight = UDim.new(0,4)
    
    local nf = Instance.new("Frame",sg)
    nf.Size = UDim2.new(0,180,0,150)
    nf.Position = UDim2.new(1,-190,0,8)
    nf.BackgroundTransparency = 1
    Instance.new("UIListLayout",nf).Padding = UDim.new(0,4)
    
    return {sg=sg, mf=mf, cb=cb, rb=rb, atb=atb, ltb=ltb, ac=ac, lc=lc, sb=sb, cf=cf, sf=sf, cnt=cnt, csi=csi, svb=svb, ss=ss, nf=nf}
end

-- NOTIFICATION
local function notify(title, msg, dur, col)
    if not gui then return end
    dur = dur or 1.5
    col = col or Color3.fromRGB(80,160,80)
    
    local n = Instance.new("Frame")
    n.Size = UDim2.new(1,0,0,36)
    n.BackgroundColor3 = Color3.fromRGB(28,28,36)
    n.Position = UDim2.new(1,10,0,0)
    n.Parent = gui.nf
    Instance.new("UICorner",n).CornerRadius = UDim.new(0,8)
    local ns = Instance.new("UIStroke",n)
    ns.Color = col
    ns.Thickness = 1
    ns.Transparency = 0.6
    
    local tl = Instance.new("TextLabel",n)
    tl.Size = UDim2.new(1,-8,0,14)
    tl.Position = UDim2.new(0,6,0,4)
    tl.BackgroundTransparency = 1
    tl.Font = Enum.Font.GothamBold
    tl.TextSize = 10
    tl.TextColor3 = col
    tl.TextXAlignment = Enum.TextXAlignment.Left
    tl.Text = title
    tl.TextTruncate = Enum.TextTruncate.AtEnd
    
    local ml = Instance.new("TextLabel",n)
    ml.Size = UDim2.new(1,-8,0,14)
    ml.Position = UDim2.new(0,6,0,18)
    ml.BackgroundTransparency = 1
    ml.Font = Enum.Font.Gotham
    ml.TextSize = 9
    ml.TextColor3 = Color3.fromRGB(140,140,160)
    ml.TextXAlignment = Enum.TextXAlignment.Left
    ml.Text = msg
    ml.TextTruncate = Enum.TextTruncate.AtEnd
    
    TweenService:Create(n, TweenInfo.new(0.2,Enum.EasingStyle.Quad), {Position=UDim2.new(0,0,0,0)}):Play()
    task.delay(dur, function()
        TweenService:Create(n, TweenInfo.new(0.15), {Position=UDim2.new(1,10,0,0)}):Play()
        task.delay(0.15, function() if n then n:Destroy() end end)
    end)
end

-- ANIMATION FUNCTIONS
local function stopAnims()
    local char = player.Character
    if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum then for _, t in ipairs(hum:GetPlayingAnimationTracks()) do t:Stop(0) end end
end

local function refresh()
    local char = player.Character
    if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum then
        hum:ChangeState(Enum.HumanoidStateType.Landed)
        task.wait(0.03)
        hum:ChangeState(Enum.HumanoidStateType.Running)
    end
end

local function setAnim(aType, aId)
    local char = player.Character
    if not char then return false end
    local anim = char:FindFirstChild("Animate")
    if not anim then return false end
    
    local ok = pcall(function()
        stopAnims()
        local map = {
            Idle = {"idle", {"Animation1","Animation2"}},
            Walk = {"walk", {"WalkAnim"}},
            Run = {"run", {"RunAnim"}},
            Jump = {"jump", {"JumpAnim"}},
            Fall = {"fall", {"FallAnim"}},
            Climb = {"climb", {"ClimbAnim"}},
            Swim = {"swim", {"Swim"}},
            SwimIdle = {"swimidle", {"SwimIdle"}},
        }
        local m = map[aType]
        if m then
            local folder = anim:FindFirstChild(m[1])
            if folder then
                if aType == "Idle" and typeof(aId) == "table" then
                    for i, name in ipairs(m[2]) do
                        local a = folder:FindFirstChild(name)
                        if a and aId[i] then a.AnimationId = "rbxassetid://" .. aId[i] end
                    end
                else
                    local a = folder:FindFirstChild(m[2][1])
                    if a then a.AnimationId = "rbxassetid://" .. tostring(aId) end
                end
            end
        end
        refresh()
    end)
    return ok
end

local function resetAnims()
    local char = player.Character
    if not char then return false end
    local anim = char:FindFirstChild("Animate")
    if not anim then return false end
    
    local def = {idle={"507766388","507766666"}, walk="507777826", run="507767714", jump="507765000", fall="507767968", climb="507765644", swim="507784897", swimidle="507785072"}
    
    pcall(function()
        stopAnims()
        local idle = anim:FindFirstChild("idle")
        if idle then
            local a1, a2 = idle:FindFirstChild("Animation1"), idle:FindFirstChild("Animation2")
            if a1 then a1.AnimationId = "rbxassetid://" .. def.idle[1] end
            if a2 then a2.AnimationId = "rbxassetid://" .. def.idle[2] end
        end
        for k, v in pairs({walk="WalkAnim", run="RunAnim", jump="JumpAnim", fall="FallAnim", climb="ClimbAnim", swim="Swim", swimidle="SwimIdle"}) do
            local f = anim:FindFirstChild(k)
            if f then local a = f:FindFirstChild(v) if a then a.AnimationId = "rbxassetid://" .. def[k] end end
        end
        refresh()
    end)
    currentAnimations = {}
    return true
end

-- UPDATE INFO
local function updateInfo()
    if not gui then return end
    local parts = {}
    for t, d in pairs(currentAnimations) do table.insert(parts, t:sub(1,3)..":"..d.name:sub(1,6)) end
    gui.csi.Text = #parts > 0 and "📦 "..table.concat(parts, "|") or "📦 No anims applied"
    gui.csi.TextColor3 = #parts > 0 and Color3.fromRGB(100,180,100) or Color3.fromRGB(130,130,150)
end

-- LOADOUT SLOTS
local function refreshSlots()
    if not gui then return end
    for _, c in pairs(gui.ss:GetChildren()) do if c:IsA("Frame") then c:Destroy() end end
    
    for i = 1, MAX_SLOTS do
        local data = SavedLoadouts[i]
        local empty = data == nil
        
        local sf = Instance.new("Frame")
        sf.Size = UDim2.new(1,-6,0,36)
        sf.BackgroundColor3 = empty and Color3.fromRGB(35,35,45) or Color3.fromRGB(40,60,90)
        sf.Parent = gui.ss
        Instance.new("UICorner",sf).CornerRadius = UDim.new(0,6)
        
        local sn = Instance.new("TextLabel",sf)
        sn.Size = UDim2.new(0,20,1,0)
        sn.Position = UDim2.new(0,4,0,0)
        sn.BackgroundTransparency = 1
        sn.Font = Enum.Font.GothamBold
        sn.TextSize = 12
        sn.TextColor3 = empty and Color3.fromRGB(70,70,90) or Color3.fromRGB(100,160,255)
        sn.Text = tostring(i)
        
        local nm = Instance.new("TextLabel",sf)
        nm.Size = UDim2.new(1,-70,1,0)
        nm.Position = UDim2.new(0,26,0,0)
        nm.BackgroundTransparency = 1
        nm.Font = Enum.Font.GothamSemibold
        nm.TextSize = 9
        nm.TextColor3 = Color3.fromRGB(220,220,220)
        nm.TextXAlignment = Enum.TextXAlignment.Left
        nm.TextTruncate = Enum.TextTruncate.AtEnd
        
        if empty then
            nm.Text = "Empty"
            nm.TextColor3 = Color3.fromRGB(100,100,120)
        else
            local types = {}
            for t in pairs(data.animations) do table.insert(types, t:sub(1,3)) end
            nm.Text = table.concat(types, "+")
        end
        
        local lb = Instance.new("TextButton",sf)
        lb.Size = UDim2.new(0,36,0,24)
        lb.Position = UDim2.new(1,-42,0.5,-12)
        lb.BackgroundColor3 = empty and Color3.fromRGB(45,45,55) or Color3.fromRGB(60,130,60)
        lb.Text = empty and "—" or "▶"
        lb.TextColor3 = Color3.fromRGB(255,255,255)
        lb.Font = Enum.Font.GothamBold
        lb.TextSize = 10
        lb.AutoButtonColor = false
        Instance.new("UICorner",lb).CornerRadius = UDim.new(0,5)
        
        if not empty then
            lb.MouseButton1Click:Connect(function()
                if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift) then
                    SavedLoadouts[i] = nil
                    saveData()
                    refreshSlots()
                    notify("🗑️ Deleted", "Slot "..i, 1.5, Color3.fromRGB(255,100,100))
                else
                    currentAnimations = {}
                    for t, d in pairs(data.animations) do if setAnim(t, d.id) then currentAnimations[t] = d end end
                    updateInfo()
                    notify("✅ Loaded", "Slot "..i, 1.5, Color3.fromRGB(100,200,100))
                end
            end)
        end
    end
    task.defer(function()
        local l = gui.ss:FindFirstChild("Layout")
        if l then gui.ss.CanvasSize = UDim2.new(0,0,0,l.AbsoluteContentSize.Y+10) end
    end)
end

-- ANIM BUTTON
local function createAnimBtn(name, aType, aId)
    if not gui then return end
    
    local b = Instance.new("TextButton")
    b.Name = name.."_"..aType
    b.Size = UDim2.new(1,-4,0,26)
    b.BackgroundColor3 = Color3.fromRGB(38,38,48)
    b.Text = ""
    b.AutoButtonColor = false
    b.Parent = gui.sf
    Instance.new("UICorner",b).CornerRadius = UDim.new(0,5)
    
    local nl = Instance.new("TextLabel",b)
    nl.Size = UDim2.new(1,-50,1,0)
    nl.Position = UDim2.new(0,6,0,0)
    nl.BackgroundTransparency = 1
    nl.Font = Enum.Font.GothamSemibold
    nl.TextSize = 9
    nl.TextColor3 = Color3.fromRGB(240,240,240)
    nl.TextXAlignment = Enum.TextXAlignment.Left
    nl.Text = name
    nl.TextTruncate = Enum.TextTruncate.AtEnd
    
    local tb = Instance.new("TextLabel",b)
    tb.Size = UDim2.new(0,36,0,14)
    tb.Position = UDim2.new(1,-42,0.5,-7)
    tb.BackgroundColor3 = typeColors[aType] or Color3.fromRGB(150,150,150)
    tb.BackgroundTransparency = 0.75
    tb.Font = Enum.Font.GothamBold
    tb.TextSize = 8
    tb.TextColor3 = typeColors[aType] or Color3.fromRGB(255,255,255)
    tb.Text = aType:sub(1,4)
    Instance.new("UICorner",tb).CornerRadius = UDim.new(0,3)
    
    b.MouseEnter:Connect(function() b.BackgroundColor3 = Color3.fromRGB(50,50,65) end)
    b.MouseLeave:Connect(function() b.BackgroundColor3 = Color3.fromRGB(38,38,48) end)
    b.MouseButton1Click:Connect(function()
        if setAnim(aType, aId) then
            currentAnimations[aType] = {name=name, id=aId}
            updateInfo()
            b.BackgroundColor3 = Color3.fromRGB(50,130,50)
            task.delay(0.1, function() b.BackgroundColor3 = Color3.fromRGB(38,38,48) end)
            notify("✓ Applied", name, 1.2, Color3.fromRGB(80,180,100))
        else
            b.BackgroundColor3 = Color3.fromRGB(130,50,50)
            task.delay(0.1, function() b.BackgroundColor3 = Color3.fromRGB(38,38,48) end)
            notify("✗ Failed", "Error", 1.2, Color3.fromRGB(255,100,100))
        end
    end)
    table.insert(buttons, b)
end

-- CATEGORY BUTTON
local function createCatBtn(cat, sel)
    if not gui then return end
    local b = Instance.new("TextButton")
    b.Name = cat
    b.Size = UDim2.new(0,42,0,18)
    b.BackgroundColor3 = sel and typeColors[cat] or Color3.fromRGB(38,38,48)
    b.BackgroundTransparency = sel and 0.5 or 0
    b.Font = Enum.Font.GothamSemibold
    b.TextSize = 8
    b.TextColor3 = sel and typeColors[cat] or Color3.fromRGB(130,130,150)
    b.Text = cat:sub(1,5)
    b.AutoButtonColor = false
    b.Parent = gui.cf
    Instance.new("UICorner",b).CornerRadius = UDim.new(0,4)
    return b
end

-- POPULATE
local function populate(cat, search)
    if not gui then return end
    for _, b in ipairs(buttons) do if b and b.Parent then b:Destroy() end end
    buttons = {}
    search = search and search:lower() or ""
    
    local order = {"Idle","Walk","Run","Jump","Fall","Climb","Swim","SwimIdle"}
    local count = 0
    
    for _, aType in ipairs(order) do
        if cat == "All" or cat == aType then
            local anims = AnimationData[aType]
            if anims then
                for name, id in pairs(anims) do
                    if search == "" or name:lower():find(search) then
                        createAnimBtn(name, aType, id)
                        count = count + 1
                    end
                end
            end
        end
    end
    
    gui.cnt.Text = count .. " anim" .. (count ~= 1 and "s" or "")
    task.defer(function()
        local l = gui.sf:FindFirstChild("Layout")
        if l then gui.sf.CanvasSize = UDim2.new(0,0,0,l.AbsoluteContentSize.Y+10) end
    end)
end

-- SETUP CATEGORIES
local function setupCats()
    if not gui then return end
    local cats = {"All","Idle","Walk","Run","Jump","Fall","Climb","Swim","SwimI"}
    for _, cat in ipairs(cats) do
        local displayCat = cat == "SwimI" and "SwimIdle" or cat
        local b = createCatBtn(cat, cat=="All")
        categoryButtons[displayCat] = b
        b.MouseButton1Click:Connect(function()
            local targetCat = cat == "SwimI" and "SwimIdle" or cat
            for c, cb in pairs(categoryButtons) do
                local sel = c == targetCat
                cb.BackgroundColor3 = sel and typeColors[c] or Color3.fromRGB(38,38,48)
                cb.BackgroundTransparency = sel and 0.5 or 0
                cb.TextColor3 = sel and typeColors[c] or Color3.fromRGB(130,130,150)
            end
            currentCategory = targetCat
            populate(targetCat, gui.sb.Text)
        end)
    end
    gui.cf.CanvasSize = UDim2.new(0, #cats * 45, 0, 0)
end

-- TOGGLE
local function toggle()
    if not gui or not gui.mf then return end
    isGuiVisible = not isGuiVisible
    if isGuiVisible then
        gui.mf.Visible = true
        gui.mf.Size = UDim2.new(0,0,0,0)
        gui.mf.Position = UDim2.new(0.5,0,0.5,0)
        TweenService:Create(gui.mf, TweenInfo.new(0.25,Enum.EasingStyle.Back,Enum.EasingDirection.Out), {Size=UDim2.new(0,260,0,340), Position=UDim2.new(0.5,-130,0.5,-170)}):Play()
    else
        TweenService:Create(gui.mf, TweenInfo.new(0.15,Enum.EasingStyle.Quad), {Size=UDim2.new(0,0,0,0), Position=UDim2.new(0.5,0,0.5,0)}):Play()
        task.delay(0.15, function() if gui and gui.mf then gui.mf.Visible = false end end)
    end
end

-- SWITCH TAB
local function switchTab(tab)
    if not gui then return end
    currentTab = tab
    gui.ac.Visible = tab == "Anims"
    gui.lc.Visible = tab == "Saves"
    gui.atb.BackgroundColor3 = tab=="Anims" and Color3.fromRGB(70,120,200) or Color3.fromRGB(40,40,50)
    gui.atb.TextColor3 = tab=="Anims" and Color3.fromRGB(255,255,255) or Color3.fromRGB(150,150,170)
    gui.ltb.BackgroundColor3 = tab=="Saves" and Color3.fromRGB(70,120,200) or Color3.fromRGB(40,40,50)
    gui.ltb.TextColor3 = tab=="Saves" and Color3.fromRGB(255,255,255) or Color3.fromRGB(150,150,170)
    if tab == "Saves" then refreshSlots() updateInfo() end
end

-- REAPPLY ON RESPAWN
local function onCharacterAdded(char)
    task.wait(1)
    local anim = char:WaitForChild("Animate", 8)
    if not anim then return end
    
    local has = false
    for t, d in pairs(currentAnimations) do
        if d and d.id then
            task.wait(0.05)
            setAnim(t, d.id)
            has = true
        end
    end
    if has then notify("🔄 Restored", "Anims reapplied", 1.5, Color3.fromRGB(100,160,255)) end
end

-- MAIN SETUP
local function setup()
    local char = player.Character or player.CharacterAdded:Wait()
    char:WaitForChild("Humanoid", 15)
    char:WaitForChild("Animate", 15)
    
    if not checkR15() then
        warn("Animation Changer requires R15!")
        return
    end
    
    gui = createGui()
    setupCats()
    populate("All", "")
    refreshSlots()
    updateInfo()
    
    gui.sb:GetPropertyChangedSignal("Text"):Connect(function() populate(currentCategory, gui.sb.Text) end)
    gui.atb.MouseButton1Click:Connect(function() switchTab("Anims") end)
    gui.ltb.MouseButton1Click:Connect(function() switchTab("Saves") end)
    
    gui.cb.MouseEnter:Connect(function() gui.cb.BackgroundColor3 = Color3.fromRGB(200,70,70) end)
    gui.cb.MouseLeave:Connect(function() gui.cb.BackgroundColor3 = Color3.fromRGB(160,50,50) end)
    gui.cb.MouseButton1Click:Connect(toggle)
    
    gui.rb.MouseEnter:Connect(function() gui.rb.BackgroundColor3 = Color3.fromRGB(90,90,110) end)
    gui.rb.MouseLeave:Connect(function() gui.rb.BackgroundColor3 = Color3.fromRGB(70,70,90) end)
    gui.rb.MouseButton1Click:Connect(function()
        resetAnims()
        updateInfo()
        notify("↺ Reset", "Default anims", 1.2, Color3.fromRGB(140,140,180))
    end)
    
    gui.svb.MouseEnter:Connect(function() gui.svb.BackgroundColor3 = Color3.fromRGB(80,180,80) end)
    gui.svb.MouseLeave:Connect(function() gui.svb.BackgroundColor3 = Color3.fromRGB(60,150,60) end)
    gui.svb.MouseButton1Click:Connect(function()
        local has = false
        for _ in pairs(currentAnimations) do has = true break end
        if not has then
            notify("⚠️ Empty", "Apply anims first", 1.5, Color3.fromRGB(255,160,60))
            return
        end
        local slot
        for i = 1, MAX_SLOTS do if not SavedLoadouts[i] then slot = i break end end
        if not slot then
            notify("❌ Full", "Shift+Click to delete", 2, Color3.fromRGB(255,100,100))
            return
        end
        SavedLoadouts[slot] = {name="Slot"..slot, animations={}}
        for t, d in pairs(currentAnimations) do
            SavedLoadouts[slot].animations[t] = {name=d.name, id=d.id}
        end
        saveData()
        refreshSlots()
        notify("💾 Saved", "Slot "..slot, 1.5, Color3.fromRGB(80,200,80))
    end)
    
    player.CharacterAdded:Connect(onCharacterAdded)
    
    print("🎭 Animation Changer v3.3 Ready! Press RightCtrl")
    task.delay(0.3, function() notify("🎭 Ready", "RightCtrl to open", 2, Color3.fromRGB(100,160,255)) end)
end

-- INPUT
UserInputService.InputBegan:Connect(function(input, gp)
    if gp then return end
    if input.KeyCode == Enum.KeyCode.RightControl then toggle() end
end)

-- RUN
setup()
