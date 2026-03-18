--[[ 💗 PinkWards Emote + Animation System - Updated & Optimized ]]

if _G.EmotesGUIRunning then return end
_G.EmotesGUIRunning = true

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")
local StarterGui = game:GetService("StarterGui")
local MarketplaceService = game:GetService("MarketplaceService")
local GuiService = game:GetService("GuiService")

local player = Players.LocalPlayer
local EMOTE_URL = "https://raw.githubusercontent.com/PinkWards/emote-sniper/refs/heads/main/EmoteSniper.json"
local ANIM_URL = "https://raw.githubusercontent.com/PinkWards/emote-sniper/refs/heads/main/AnimationSniper.json"

-- ============ STATE ============ --
local State = {
	mode = "emote",
	currentPage = 1,
	itemsPerPage = 8,
	totalPages = 1,
	emotesData = {},
	animsData = {},
	filteredEmotes = {},
	filteredAnims = {},
	favEmotes = {},
	favAnims = {},
	favEnabled = false,
	isLoading = false,
	currentEmoteTrack = nil,
	lastWheelVisible = 0,
	lastAction = 0,
	favSetVersion = 0,
	guiCreated = false,
	wheelCache = nil,
	lastWheelCheck = 0,
	autoReapplyEnabled = true,
	favFileName = "FavoriteEmotes.json",
	favAnimFileName = "FavoriteAnimations.json",
}

getgenv().lastAnim = getgenv().lastAnim or nil

-- ============ COLORS (Pink Theme) ============ --
local COLORS = {
	PINK_LIGHT = Color3.fromHex("#FFEBF2"),
	PINK_MEDIUM = Color3.fromHex("#FFC8DC"),
	PINK_WHEEL = Color3.fromHex("#FFD9E8"),
	PINK_HEART = Color3.fromHex("#FF6B9D"),
	PINK_ANIM = Color3.fromHex("#C8A2C8"),
	WHITE = Color3.fromRGB(255, 255, 255),
	PLACEHOLDER = Color3.fromRGB(255, 210, 230),
	GREEN_ON = Color3.fromRGB(100, 220, 130),
	RED_OFF = Color3.fromRGB(220, 100, 100),
}

-- ============ UI ELEMENTS ============ --
local UI = {
	Under = nil, LeftBtn = nil, RightBtn = nil,
	PagesLabel = nil, SepLabel = nil, PageNumBox = nil,
	Top = nil, Search = nil, FavBtn = nil, ModeBtn = nil,
	AutoReapplyBtn = nil,
}

-- ============ UTILITIES ============ --
local function notify(title, content, duration)
	pcall(function()
		StarterGui:SetCore("SendNotification", {
			Title = title or "💗 PinkWards",
			Text = content or "",
			Duration = duration or 4
		})
	end)
end

local function getChar()
	local c = player.Character
	return c, c and c:FindFirstChild("Humanoid")
end

local function getWheel()
	local t = tick()
	if State.wheelCache and State.wheelCache.Parent and t - State.lastWheelCheck < 1 then
		return State.wheelCache
	end
	State.lastWheelCheck = t
	local ok, w = pcall(function()
		return CoreGui.RobloxGui.EmotesMenu.Children.Main.EmotesWheel
	end)
	State.wheelCache = ok and w or nil
	return State.wheelCache
end

local function saveFile(name, data)
	if writefile then
		pcall(function() writefile(name, HttpService:JSONEncode(data)) end)
	end
end

local function loadFile(name)
	if readfile and isfile and isfile(name) then
		local ok, res = pcall(function()
			return HttpService:JSONDecode(readfile(name))
		end)
		return ok and res or {}
	end
	return {}
end

local function saveLastAnim()
	if getgenv().lastAnim then
		saveFile("LastAnimation.json", getgenv().lastAnim)
	end
end

local function loadLastAnim()
	local data = loadFile("LastAnimation.json")
	if data and data.id then
		getgenv().lastAnim = data
	end
end

local function saveAutoReapplySetting()
	saveFile("AutoReapplySetting.json", {enabled = State.autoReapplyEnabled})
end

local function loadAutoReapplySetting()
	local data = loadFile("AutoReapplySetting.json")
	if data and data.enabled ~= nil then
		State.autoReapplyEnabled = data.enabled
	end
end

local function extractId(url)
	return string.match(url, "Asset&id=(%d+)")
end

local function getEmoteName(id)
	local ok, info = pcall(function()
		return MarketplaceService:GetProductInfo(tonumber(id))
	end)
	return ok and info and info.Name or "Emote_" .. id
end

local function isInFav(id)
	local list = State.mode == "animation" and State.favAnims or State.favEmotes
	for _, v in ipairs(list) do
		if tostring(v.id) == tostring(id) then return true end
	end
	return false
end

local function getBundled(id)
	for _, src in ipairs({State.filteredAnims, State.animsData, State.favAnims}) do
		for _, a in ipairs(src) do
			if tostring(a.id) == tostring(id) and a.bundledItems then
				return a.bundledItems
			end
		end
	end
	return nil
end

-- ============ PINK THEME ============ --
local function applyPinkTheme()
	local wheel = getWheel()
	if not wheel then return end

	pcall(function()
		local back = wheel:FindFirstChild("Back")
		if back then
			local background = back:FindFirstChild("Background")
			if background then
				if background:IsA("Frame") then
					background.BackgroundColor3 = COLORS.PINK_WHEEL
					background.BackgroundTransparency = 0.05
				end
				local overlay = background:FindFirstChild("BackgroundCircleOverlay")
				if overlay then
					overlay.BackgroundColor3 = COLORS.PINK_LIGHT
					overlay.BackgroundTransparency = 0.1
				end
				for _, child in pairs(background:GetChildren()) do
					if child:IsA("ImageLabel") then
						child.ImageColor3 = COLORS.PINK_LIGHT
						child.ImageTransparency = 0.05
					end
				end
			end
		end
	end)

	if UI.LeftBtn then UI.LeftBtn.ImageColor3 = COLORS.PINK_MEDIUM end
	if UI.RightBtn then UI.RightBtn.ImageColor3 = COLORS.PINK_MEDIUM end
	if UI.PagesLabel then UI.PagesLabel.TextColor3 = COLORS.WHITE end
	if UI.SepLabel then UI.SepLabel.TextColor3 = COLORS.WHITE end
	if UI.PageNumBox then UI.PageNumBox.TextColor3 = COLORS.WHITE end
	if UI.Top then
		UI.Top.BackgroundColor3 = COLORS.PINK_MEDIUM
		UI.Top.BackgroundTransparency = 0.15
	end
	if UI.FavBtn then
		UI.FavBtn.BackgroundColor3 = State.favEnabled and COLORS.PINK_HEART or COLORS.PINK_MEDIUM
		UI.FavBtn.BackgroundTransparency = 0.15
	end
	if UI.ModeBtn then
		UI.ModeBtn.BackgroundColor3 = State.mode == "animation" and COLORS.PINK_ANIM or COLORS.PINK_MEDIUM
		UI.ModeBtn.BackgroundTransparency = 0.15
	end
	if UI.AutoReapplyBtn then
		UI.AutoReapplyBtn.BackgroundColor3 = State.autoReapplyEnabled and COLORS.GREEN_ON or COLORS.RED_OFF
		UI.AutoReapplyBtn.BackgroundTransparency = 0.15
	end
end

-- ============ PAGINATION ============ --
local function calcPages()
	local favs = State.mode == "animation" and State.favAnims or State.favEmotes
	local list = State.mode == "animation" and State.filteredAnims or State.filteredEmotes
	local normalCount = 0

	for _, v in ipairs(list) do
		if not isInFav(v.id) then normalCount = normalCount + 1 end
	end

	local pages = 0
	if #favs > 0 then pages = pages + math.ceil(#favs / State.itemsPerPage) end
	if normalCount > 0 then pages = pages + math.ceil(normalCount / State.itemsPerPage) end
	return math.max(pages, 1)
end

local function updatePageDisplay()
	if UI.PagesLabel and UI.PageNumBox then
		UI.PagesLabel.Text = tostring(State.totalPages)
		UI.PageNumBox.Text = tostring(State.currentPage)
	end
end

-- ============ ANIMATION SYSTEM ============ --
local function applyAnim(data)
	if not data then
		notify("💗 Animation", "❌ No animation data", 3)
		return
	end

	local char = player.Character or player.CharacterAdded:Wait()
	local hum = char:FindFirstChild("Humanoid")
	local animate = char:FindFirstChild("Animate")

	if not animate then
		notify("💗 Animation", "❌ Animate not found", 3)
		return
	end

	if not hum then
		notify("💗 Animation", "❌ Humanoid not found", 3)
		return
	end

	local bundled = data.bundledItems or getBundled(data.id)
	if not bundled then
		notify("💗 Animation", "❌ No assets for: " .. (data.name or data.id), 3)
		return
	end

	getgenv().lastAnim = {id = data.id, name = data.name, bundledItems = bundled}
	saveLastAnim()

	for _, track in pairs(hum:GetPlayingAnimationTracks()) do
		track:Stop()
	end

	for _, assetIds in pairs(bundled) do
		for _, assetId in pairs(assetIds) do
			spawn(function()
				local ok, objs = pcall(function()
					return game:GetObjects("rbxassetid://" .. assetId)
				end)

				if ok and objs and #objs > 0 then
					local function searchAnims(parent, path)
						for _, child in pairs(parent:GetChildren()) do
							if child:IsA("Animation") then
								local parts = (path .. "." .. child.Name):split(".")
								if #parts >= 2 then
									local cat = parts[#parts - 1]
									local name = parts[#parts]
									local folder = animate:FindFirstChild(cat)
									if folder then
										local slot = folder:FindFirstChild(name)
										if slot then
											slot.AnimationId = child.AnimationId
											task.wait(0.1)
											local anim = Instance.new("Animation")
											anim.AnimationId = child.AnimationId
											local animator = hum:FindFirstChild("Animator")
											if animator then
												local t = animator:LoadAnimation(anim)
												t.Priority = Enum.AnimationPriority.Action
												t:Play()
												task.wait(0.1)
												t:Stop()
											end
										end
									end
								end
							elseif #child:GetChildren() > 0 then
								searchAnims(child, path .. "." .. child.Name)
							end
						end
					end

					for _, obj in pairs(objs) do
						searchAnims(obj, obj.Name)
						obj.Parent = workspace
						task.delay(1, function()
							if obj and obj.Parent then obj:Destroy() end
						end)
					end
				end
			end)
		end
	end

	notify("💗 Animation", "✅ Applied: " .. (data.name or "Animation"), 3)
end

-- ============ EMOTE PLAYING (FREEZE FIX) ============ --
local loadedTracks = {} -- Track all loaded animations to prevent buildup

local function cleanupAllTracks()
	for i = #loadedTracks, 1, -1 do
		local track = loadedTracks[i]
		if track then
			pcall(function()
				if track.IsPlaying then
					track:Stop()
				end
				track:Destroy()
			end)
		end
		table.remove(loadedTracks, i)
	end
	State.currentEmoteTrack = nil
end

local function stopCurrentEmote()
	if State.currentEmoteTrack then
		pcall(function()
			State.currentEmoteTrack:Stop()
			State.currentEmoteTrack:Destroy()
		end)
		State.currentEmoteTrack = nil
	end
end

local function playEmote(emoteId)
	local _, hum = getChar()
	if not hum then return false end

	stopCurrentEmote()

	-- If too many tracks loaded, clean ALL to prevent Animator freeze
	if #loadedTracks >= 50 then
		cleanupAllTracks()

		-- Stop all playing tracks on the animator too
		pcall(function()
			local animator = hum:FindFirstChild("Animator")
			if animator then
				for _, track in pairs(animator:GetPlayingAnimationTracks()) do
					track:Stop()
					track:Destroy()
				end
			end
		end)

		task.wait(0.1) -- Let animator recover
	end

	local anim = Instance.new("Animation")
	anim.AnimationId = "rbxassetid://" .. emoteId

	local success, track = pcall(function()
		local animator = hum:FindFirstChild("Animator")
		if not animator then return nil end
		return animator:LoadAnimation(anim)
	end)

	-- Clean up the Animation instance immediately
	anim:Destroy()

	if success and track then
		track.Priority = Enum.AnimationPriority.Action
		track.Looped = true
		track:Play()
		State.currentEmoteTrack = track
		table.insert(loadedTracks, track)
		return true
	end

	return false
end

-- ============ FAVORITE ICON ============ --
local function updateFavIcon(img, id, isFav)
	local icon = img:FindFirstChild("FavHeart")
	if isFav then
		if not icon then
			icon = Instance.new("TextLabel")
			icon.Name = "FavHeart"
			icon.Size = UDim2.new(0.22, 0, 0.22, 0)
			icon.Position = UDim2.new(0.76, 0, 0.02, 0)
			icon.BackgroundTransparency = 1
			icon.ZIndex = img.ZIndex + 10
			icon.Text = "💗"
			icon.TextScaled = true
			icon.Font = Enum.Font.SourceSans
			icon.Parent = img
		end
		icon.Visible = true
	elseif icon then
		icon.Visible = false
	end
end

-- ============ DISPLAY UPDATE ============ --
local function updateDisplay()
	local char, hum = getChar()
	if not char or not hum or not hum.HumanoidDescription then return end

	local desc = hum.HumanoidDescription
	local favs = State.mode == "animation" and State.favAnims or State.favEmotes
	local list = State.mode == "animation" and State.filteredAnims or State.filteredEmotes
	local items = {}

	local favPages = #favs > 0 and math.ceil(#favs / State.itemsPerPage) or 0
	local inFavPages = State.currentPage <= favPages

	if inFavPages and #favs > 0 then
		local startIdx = (State.currentPage - 1) * State.itemsPerPage + 1
		local endIdx = math.min(startIdx + State.itemsPerPage - 1, #favs)
		for i = startIdx, endIdx do
			if favs[i] then
				local item = {id = tonumber(favs[i].id), name = favs[i].name}
				if State.mode == "animation" then
					item.bundledItems = favs[i].bundledItems or getBundled(favs[i].id)
				end
				table.insert(items, item)
			end
		end
	else
		local normalList = {}
		for _, v in ipairs(list) do
			if not isInFav(v.id) then table.insert(normalList, v) end
		end
		local adjPage = State.currentPage - favPages
		local startIdx = (adjPage - 1) * State.itemsPerPage + 1
		local endIdx = math.min(startIdx + State.itemsPerPage - 1, #normalList)
		for i = startIdx, endIdx do
			if normalList[i] then table.insert(items, normalList[i]) end
		end
	end

	local emoteTable = {}
	local equipped = {}
	for _, item in ipairs(items) do
		emoteTable[item.name] = {item.id}
		table.insert(equipped, item.name)
	end

	desc:SetEmotes(emoteTable)
	desc:SetEquippedEmotes(equipped)

	task.delay(0.1, function()
		local wheel = getWheel()
		if not wheel then return end

		pcall(function()
			local front = wheel:FindFirstChild("Front")
			if not front then return end
			local btns = front:FindFirstChild("EmotesButtons")
			if not btns then return end

			if State.mode == "animation" then
				local idx = 1
				for _, child in pairs(btns:GetChildren()) do
					if child:IsA("ImageLabel") then
						if idx <= #items then
							child.Image = "rbxthumb://type=BundleThumbnail&id=" .. items[idx].id .. "&w=420&h=420"

							local idVal = child:FindFirstChild("AnimID")
							if not idVal then
								idVal = Instance.new("IntValue")
								idVal.Name = "AnimID"
								idVal.Parent = child
							end
							idVal.Value = items[idx].id

							updateFavIcon(child, items[idx].id, isInFav(items[idx].id))
							child.Active = not State.favEnabled
							idx = idx + 1
						else
							child.Image = ""
							local idVal = child:FindFirstChild("AnimID")
							if idVal then idVal:Destroy() end
						end
					end
				end
			else
				local idx = 1
				for _, child in pairs(btns:GetChildren()) do
					if child:IsA("ImageLabel") then
						if idx <= #items then
							child.Image = "rbxthumb://type=Asset&id=" .. items[idx].id .. "&w=420&h=420"
							updateFavIcon(child, items[idx].id, isInFav(items[idx].id))
							child.Active = not State.favEnabled
							idx = idx + 1
						else
							child.Image = ""
						end
					end
				end
			end
		end)
	end)
end

-- ============ FAVORITES ============ --
local function toggleFav(id, name, bundled)
	local list = State.mode == "animation" and State.favAnims or State.favEmotes
	local found, idx = false, 0

	for i, v in ipairs(list) do
		if tostring(v.id) == tostring(id) then
			found, idx = true, i
			break
		end
	end

	if found then
		table.remove(list, idx)
		notify("💗 Favorites", "Removed: " .. name, 3)
	else
		local entry = {id = id, name = name .. " 💗"}
		if State.mode == "animation" then
			entry.bundledItems = bundled or getBundled(id)
		end
		table.insert(list, entry)
		notify("💗 Favorites", "Added: " .. name, 3)
	end

	local fileName = State.mode == "animation" and State.favAnimFileName or State.favFileName
	saveFile(fileName, list)
	State.favSetVersion = State.favSetVersion + 1
	State.totalPages = calcPages()
	updatePageDisplay()
	updateDisplay()
end

-- ============ WHEEL CLICK HANDLER ============ --
local function handleSector(index)
	if tick() - State.lastAction < 0.25 then return end
	State.lastAction = tick()
	task.wait(0.05)

	local favs = State.mode == "animation" and State.favAnims or State.favEmotes
	local list = State.mode == "animation" and State.filteredAnims or State.filteredEmotes
	local favPages = #favs > 0 and math.ceil(#favs / State.itemsPerPage) or 0

	local item
	if State.currentPage <= favPages and #favs > 0 then
		local startIdx = (State.currentPage - 1) * State.itemsPerPage
		item = favs[startIdx + index]
		if item and State.mode == "animation" and not item.bundledItems then
			item.bundledItems = getBundled(item.id)
		end
	else
		local normalList = {}
		for _, v in ipairs(list) do
			if not isInFav(v.id) then table.insert(normalList, v) end
		end
		local adjPage = State.currentPage - favPages
		local startIdx = (adjPage - 1) * State.itemsPerPage
		item = normalList[startIdx + index]
	end

	if not item then return end

	if State.favEnabled then
		toggleFav(item.id, item.name, item.bundledItems)
	elseif State.mode == "animation" then
		applyAnim(item)
	else
		playEmote(item.id)
	end
end

-- ============ INPUT HANDLING ============ --
UserInputService.InputBegan:Connect(function(input)
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 and
		input.UserInputType ~= Enum.UserInputType.Touch then return end

	local wheel = getWheel()
	if not wheel or (not wheel.Visible and tick() - State.lastWheelVisible > 0.15) then return end

	local pos = Vector2.new(input.Position.X, input.Position.Y)
	local aPos = wheel.AbsolutePosition
	local aSize = wheel.AbsoluteSize

	if pos.X < aPos.X or pos.X > aPos.X + aSize.X or
		pos.Y < aPos.Y or pos.Y > aPos.Y + aSize.Y then return end

	local center = aPos + aSize / 2
	local dx = pos.X - center.X
	local dy = pos.Y - center.Y
	local distance = math.sqrt(dx * dx + dy * dy)

	if distance < aSize.X * 0.1 then return end

	local angle = math.deg(math.atan2(dy, dx))
	local correctedAngle = (angle + 90 + 22.5) % 360
	local sectorIndex = math.floor(correctedAngle / 45) + 1

	handleSector(sectorIndex)
end)

RunService.Heartbeat:Connect(function()
	pcall(function()
		local wheel = getWheel()
		if wheel and wheel.Visible then
			State.lastWheelVisible = tick()
		end
	end)
end)

-- ============ DATA FETCHING ============ --
local function fetchEmotes()
	if State.isLoading then return end
	State.isLoading = true

	local ok, result = pcall(function()
		return HttpService:JSONDecode(game:HttpGet(EMOTE_URL))
	end)

	if ok and result then
		State.emotesData = {}
		local list = result.data or result
		for _, item in ipairs(list) do
			local id = tonumber(item.id)
			if id and id > 0 then
				table.insert(State.emotesData, {id = id, name = item.name or ("Emote_" .. id)})
			end
		end
		State.filteredEmotes = State.emotesData
	end

	State.isLoading = false
end

local function fetchAnims()
	if State.isLoading then return end
	State.isLoading = true

	local ok, result = pcall(function()
		return HttpService:JSONDecode(game:HttpGet(ANIM_URL))
	end)

	if ok and result then
		State.animsData = {}
		local list = result.data or result
		for _, item in ipairs(list) do
			local id = tonumber(item.id)
			if id and id > 0 then
				table.insert(State.animsData, {
					id = id,
					name = item.name or ("Anim_" .. id),
					bundledItems = item.bundledItems
				})
			end
		end
		State.filteredAnims = State.animsData
	end

	State.isLoading = false
end

-- ============ SEARCH ============ --
local function searchItems(term)
	term = term:lower()
	local source = State.mode == "animation" and State.animsData or State.emotesData

	if term == "" then
		if State.mode == "animation" then
			State.filteredAnims = State.animsData
		else
			State.filteredEmotes = State.emotesData
		end
	else
		local result = {}
		local isIdSearch = term:match("^%d+$")

		for _, v in ipairs(source) do
			if (isIdSearch and tostring(v.id) == term) or (not isIdSearch and v.name:lower():find(term)) then
				table.insert(result, v)
			end
		end

		if State.mode == "animation" then
			State.filteredAnims = result
		else
			State.filteredEmotes = result
		end
	end

	State.currentPage = 1
	State.totalPages = calcPages()
	updatePageDisplay()
	updateDisplay()
end

-- ============ NAVIGATION ============ --
local function prevPage()
	State.currentPage = State.currentPage <= 1 and State.totalPages or State.currentPage - 1
	updatePageDisplay()
	updateDisplay()
end

local function nextPage()
	State.currentPage = State.currentPage >= State.totalPages and 1 or State.currentPage + 1
	updatePageDisplay()
	updateDisplay()
end

local function goToPage(num)
	State.currentPage = math.clamp(num, 1, State.totalPages)
	updatePageDisplay()
	updateDisplay()
end

-- ============ TOGGLES ============ --
local function toggleMode()
	State.mode = State.mode == "emote" and "animation" or "emote"

	if State.mode == "animation" and #State.animsData == 0 then
		fetchAnims()
	end

	if UI.Search then UI.Search.Text = "" end

	if State.mode == "animation" then
		State.filteredAnims = State.animsData
	else
		State.filteredEmotes = State.emotesData
	end

	State.currentPage = 1
	State.totalPages = calcPages()
	updatePageDisplay()
	updateDisplay()
	applyPinkTheme()

	notify("💗 Mode", State.mode == "animation" and "🎬 Animation Mode" or "💃 Emote Mode", 3)
end

local function toggleFavMode()
	State.favEnabled = not State.favEnabled
	applyPinkTheme()
	notify("💗 Favorites", State.favEnabled and "Click to add hearts!" or "Favorite mode OFF", 3)
	updateDisplay()
end

local function toggleAutoReapply()
	State.autoReapplyEnabled = not State.autoReapplyEnabled
	saveAutoReapplySetting()
	applyPinkTheme()

	if State.autoReapplyEnabled then
		notify("💗 Auto-Reapply", "🔄 ON - Animations restore on respawn", 3)
	else
		notify("💗 Auto-Reapply", "⏹️ OFF - Animations won't restore on respawn", 3)
	end
end

-- ============ CHARACTER HANDLING ============ --
local function onCharacterAdded(char)
	local hum = char:WaitForChild("Humanoid")

	-- Reset all track data on new character
	cleanupAllTracks()
	loadedTracks = {}
	State.currentEmoteTrack = nil

	-- Auto-reapply animation on respawn
	if State.autoReapplyEnabled and getgenv().lastAnim and getgenv().lastAnim.id then
		task.wait(0.5)
		applyAnim(getgenv().lastAnim)
		notify("💗 Auto-Reload", "🔄 Animation restored!", 3)
	elseif not State.autoReapplyEnabled and getgenv().lastAnim and getgenv().lastAnim.id then
		notify("💗 Auto-Reload", "⏹️ Skipped (Auto-Reapply OFF)", 3)
	end

	hum.Died:Connect(function()
		State.favEnabled = false
		cleanupAllTracks()
		applyPinkTheme()
	end)
end

-- ============ GUI CREATION (Pink Theme) ============ --
function createGUI()
	local wheel = getWheel()
	if not wheel then return false end

	-- Clean up old UI
	for _, name in ipairs({"Under", "Top", "Favorite", "ModeToggle", "AutoReapplyToggle"}) do
		local existing = wheel:FindFirstChild(name)
		if existing then existing:Destroy() end
	end

	-- Bottom navigation bar
	UI.Under = Instance.new("Frame")
	UI.Under.Name = "Under"
	UI.Under.Parent = wheel
	UI.Under.BackgroundTransparency = 1
	UI.Under.BorderSizePixel = 0
	UI.Under.Position = UDim2.new(0.13, 0, 1, 0)
	UI.Under.Size = UDim2.new(0.74, 0, 0.13, 0)

	local underLayout = Instance.new("UIListLayout")
	underLayout.Parent = UI.Under
	underLayout.FillDirection = Enum.FillDirection.Horizontal
	underLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	underLayout.SortOrder = Enum.SortOrder.LayoutOrder

	UI.LeftBtn = Instance.new("ImageButton")
	UI.LeftBtn.Name = "LeftBtn"
	UI.LeftBtn.Parent = UI.Under
	UI.LeftBtn.LayoutOrder = 1
	UI.LeftBtn.BackgroundTransparency = 1
	UI.LeftBtn.Size = UDim2.new(0.17, 0, 0.94, 0)
	UI.LeftBtn.Image = "rbxassetid://93111945058621"
	UI.LeftBtn.ImageColor3 = COLORS.PINK_MEDIUM

	UI.PageNumBox = Instance.new("TextBox")
	UI.PageNumBox.Name = "PageNum"
	UI.PageNumBox.Parent = UI.Under
	UI.PageNumBox.LayoutOrder = 2
	UI.PageNumBox.BackgroundTransparency = 1
	UI.PageNumBox.Size = UDim2.new(0.16, 0, 0.81, 0)
	UI.PageNumBox.Font = Enum.Font.GothamBold
	UI.PageNumBox.Text = "1"
	UI.PageNumBox.TextColor3 = COLORS.WHITE
	UI.PageNumBox.TextScaled = true

	UI.SepLabel = Instance.new("TextLabel")
	UI.SepLabel.Name = "Separator"
	UI.SepLabel.Parent = UI.Under
	UI.SepLabel.LayoutOrder = 3
	UI.SepLabel.BackgroundTransparency = 1
	UI.SepLabel.Size = UDim2.new(0.34, 0, 0.94, 0)
	UI.SepLabel.Font = Enum.Font.GothamBold
	UI.SepLabel.Text = " --- "
	UI.SepLabel.TextColor3 = COLORS.WHITE
	UI.SepLabel.TextScaled = true

	UI.PagesLabel = Instance.new("TextLabel")
	UI.PagesLabel.Name = "TotalPages"
	UI.PagesLabel.Parent = UI.Under
	UI.PagesLabel.LayoutOrder = 4
	UI.PagesLabel.BackgroundTransparency = 1
	UI.PagesLabel.Size = UDim2.new(0.16, 0, 0.81, 0)
	UI.PagesLabel.Font = Enum.Font.GothamBold
	UI.PagesLabel.Text = "1"
	UI.PagesLabel.TextColor3 = COLORS.WHITE
	UI.PagesLabel.TextScaled = true

	UI.RightBtn = Instance.new("ImageButton")
	UI.RightBtn.Name = "RightBtn"
	UI.RightBtn.Parent = UI.Under
	UI.RightBtn.LayoutOrder = 5
	UI.RightBtn.BackgroundTransparency = 1
	UI.RightBtn.Size = UDim2.new(0.17, 0, 0.94, 0)
	UI.RightBtn.Image = "rbxassetid://107938916240738"
	UI.RightBtn.ImageColor3 = COLORS.PINK_MEDIUM

	-- Top search bar
	UI.Top = Instance.new("Frame")
	UI.Top.Name = "Top"
	UI.Top.Parent = wheel
	UI.Top.BackgroundColor3 = COLORS.PINK_MEDIUM
	UI.Top.BackgroundTransparency = 0.15
	UI.Top.BorderSizePixel = 0
	UI.Top.Position = UDim2.new(0.13, 0, -0.11, 0)
	UI.Top.Size = UDim2.new(0.74, 0, 0.095, 0)

	local topCorner = Instance.new("UICorner")
	topCorner.CornerRadius = UDim.new(0, 20)
	topCorner.Parent = UI.Top

	local topLayout = Instance.new("UIListLayout")
	topLayout.Parent = UI.Top
	topLayout.FillDirection = Enum.FillDirection.Horizontal
	topLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	topLayout.VerticalAlignment = Enum.VerticalAlignment.Center

	UI.Search = Instance.new("TextBox")
	UI.Search.Name = "Search"
	UI.Search.Parent = UI.Top
	UI.Search.BackgroundTransparency = 1
	UI.Search.Size = UDim2.new(0.87, 0, 0.82, 0)
	UI.Search.Font = Enum.Font.GothamBold
	UI.Search.PlaceholderText = "Search/ID"
	UI.Search.PlaceholderColor3 = COLORS.PLACEHOLDER
	UI.Search.Text = ""
	UI.Search.TextColor3 = COLORS.WHITE
	UI.Search.TextScaled = true

	-- Favorite button (left side)
	UI.FavBtn = Instance.new("ImageButton")
	UI.FavBtn.Name = "Favorite"
	UI.FavBtn.Parent = wheel
	UI.FavBtn.BackgroundColor3 = COLORS.PINK_MEDIUM
	UI.FavBtn.BackgroundTransparency = 0.15
	UI.FavBtn.BorderSizePixel = 0
	UI.FavBtn.Position = UDim2.new(0.019, 0, -0.108, 0)
	UI.FavBtn.Size = UDim2.new(0.0875, 0, 0.0875, 0)
	UI.FavBtn.Image = ""

	local favCorner = Instance.new("UICorner")
	favCorner.CornerRadius = UDim.new(0, 10)
	favCorner.Parent = UI.FavBtn

	local favText = Instance.new("TextLabel")
	favText.Parent = UI.FavBtn
	favText.BackgroundTransparency = 1
	favText.Size = UDim2.new(1, 0, 1, 0)
	favText.Font = Enum.Font.SourceSans
	favText.Text = "💗"
	favText.TextScaled = true
	favText.ZIndex = UI.FavBtn.ZIndex + 1

	-- Mode toggle button (right side)
	UI.ModeBtn = Instance.new("ImageButton")
	UI.ModeBtn.Name = "ModeToggle"
	UI.ModeBtn.Parent = wheel
	UI.ModeBtn.BackgroundColor3 = COLORS.PINK_MEDIUM
	UI.ModeBtn.BackgroundTransparency = 0.15
	UI.ModeBtn.BorderSizePixel = 0
	UI.ModeBtn.Position = UDim2.new(0.889, 0, -0.108, 0)
	UI.ModeBtn.Size = UDim2.new(0.0875, 0, 0.0875, 0)
	UI.ModeBtn.Image = ""

	local modeCorner = Instance.new("UICorner")
	modeCorner.CornerRadius = UDim.new(0, 10)
	modeCorner.Parent = UI.ModeBtn

	local modeText = Instance.new("TextLabel")
	modeText.Parent = UI.ModeBtn
	modeText.BackgroundTransparency = 1
	modeText.Size = UDim2.new(1, 0, 1, 0)
	modeText.Font = Enum.Font.SourceSans
	modeText.Text = "🎬"
	modeText.TextScaled = true
	modeText.ZIndex = UI.ModeBtn.ZIndex + 1

	-- Auto-Reapply button (above mode button)
	UI.AutoReapplyBtn = Instance.new("ImageButton")
	UI.AutoReapplyBtn.Name = "AutoReapplyToggle"
	UI.AutoReapplyBtn.Parent = wheel
	UI.AutoReapplyBtn.BackgroundColor3 = State.autoReapplyEnabled and COLORS.GREEN_ON or COLORS.RED_OFF
	UI.AutoReapplyBtn.BackgroundTransparency = 0.15
	UI.AutoReapplyBtn.BorderSizePixel = 0
	UI.AutoReapplyBtn.Position = UDim2.new(0.889, 0, -0.215, 0)
	UI.AutoReapplyBtn.Size = UDim2.new(0.0875, 0, 0.0875, 0)
	UI.AutoReapplyBtn.Image = ""

	local autoCorner = Instance.new("UICorner")
	autoCorner.CornerRadius = UDim.new(0, 10)
	autoCorner.Parent = UI.AutoReapplyBtn

	local autoText = Instance.new("TextLabel")
	autoText.Parent = UI.AutoReapplyBtn
	autoText.BackgroundTransparency = 1
	autoText.Size = UDim2.new(1, 0, 1, 0)
	autoText.Font = Enum.Font.SourceSans
	autoText.Text = "🔄"
	autoText.TextScaled = true
	autoText.ZIndex = UI.AutoReapplyBtn.ZIndex + 1

	-- Connect events
	UI.LeftBtn.MouseButton1Click:Connect(prevPage)
	UI.RightBtn.MouseButton1Click:Connect(nextPage)

	UI.PageNumBox.FocusLost:Connect(function()
		local num = tonumber(UI.PageNumBox.Text)
		if num then goToPage(num) else UI.PageNumBox.Text = tostring(State.currentPage) end
	end)

	UI.Search:GetPropertyChangedSignal("Text"):Connect(function()
		searchItems(UI.Search.Text)
	end)

	UI.FavBtn.MouseButton1Click:Connect(toggleFavMode)
	UI.ModeBtn.MouseButton1Click:Connect(toggleMode)
	UI.AutoReapplyBtn.MouseButton1Click:Connect(toggleAutoReapply)

	applyPinkTheme()
	State.guiCreated = true

	return true
end

-- ============ MAIN LOOPS ============ --
local frameCount = 0
RunService.RenderStepped:Connect(function()
	frameCount = frameCount + 1
	if frameCount >= 30 then
		frameCount = 0
		if not State.guiCreated then
			local wheel = getWheel()
			if wheel and createGUI() then
				updatePageDisplay()
				updateDisplay()
			end
		else
			applyPinkTheme()
		end
	end
end)

-- ============ INITIALIZATION ============ --
task.spawn(function()
	while not getWheel() do task.wait(0.1) end

	if createGUI() then
		State.favEmotes = loadFile(State.favFileName)
		State.favAnims = loadFile(State.favAnimFileName)
		loadLastAnim()
		loadAutoReapplySetting()
		applyPinkTheme()

		fetchEmotes()
		fetchAnims()

		State.totalPages = calcPages()
		updatePageDisplay()
		updateDisplay()

		notify("💗 PinkWards", "Loaded! Press '.' to open", 5)
	end
end)

-- Keep emotes menu enabled
StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Chat, true)

task.spawn(function()
	while true do
		pcall(function()
			local robloxGui = CoreGui:FindFirstChild("RobloxGui")
			local emotesMenu = robloxGui and robloxGui:FindFirstChild("EmotesMenu")

			if not emotesMenu then
				StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.EmotesMenu, true)
			else
				local wheel = getWheel()
				if wheel and not wheel:FindFirstChild("Under") then
					createGUI()
					updatePageDisplay()
				end
			end
		end)
		task.wait(1)
	end
end)

-- ============ MOBILE SUPPORT ============ --
if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
	pcall(function()
		local gui = Instance.new("ScreenGui")
		gui.Name = "EmoteOpenBtn"
		gui.ResetOnSpawn = false

		if syn and syn.protect_gui then
			syn.protect_gui(gui)
			gui.Parent = CoreGui
		elseif gethui then
			gui.Parent = gethui()
		else
			gui.Parent = CoreGui
		end

		local btn = Instance.new("TextButton")
		btn.Size = UDim2.new(0, 55, 0, 55)
		btn.Position = UDim2.new(0, 10, 0.5, -27)
		btn.BackgroundColor3 = COLORS.PINK_MEDIUM
		btn.BackgroundTransparency = 0.15
		btn.Text = "💗"
		btn.TextSize = 28
		btn.TextColor3 = COLORS.WHITE
		btn.Parent = gui

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 12)
		corner.Parent = btn

		btn.MouseButton1Click:Connect(function()
			pcall(function() GuiService:SetEmotesMenuOpen(true) end)
		end)
	end)

	notify("💗 Mobile", "Tap the heart to open!", 10)
end

print("=========================================")
print("   💗 PinkWards Emote + Animation System")
print("   Press '.' to open")
print("   🎬 = Toggle Animation Mode")
print("   💗 = Favorite Mode")
print("   🔄 = Toggle Auto-Reapply on Death")
print("   ✅ Settings save between sessions!")
print("=========================================")
