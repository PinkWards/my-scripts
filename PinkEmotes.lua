--[[ PinkWards Emote + Animation System - Clean Native Style, Optimized for 4000+ items ]]

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
	-- Performance: caches
	favLookupEmote = {},
	favLookupAnim = {},
	normalListCache = nil,
	normalListCacheVersion = -1,
	normalListCacheMode = "",
	searchDebounce = nil,
	lastSearchTerm = "",
}

getgenv().lastAnim = getgenv().lastAnim or nil

-- ============ COLORS (Native Roblox Dark Theme) ============ --
local COLORS = {
	BG_DARK = Color3.fromRGB(30, 30, 30),
	BG_MEDIUM = Color3.fromRGB(45, 45, 45),
	BG_LIGHT = Color3.fromRGB(60, 60, 60),
	BG_HOVER = Color3.fromRGB(80, 80, 80),
	TEXT_PRIMARY = Color3.fromRGB(255, 255, 255),
	TEXT_SECONDARY = Color3.fromRGB(180, 180, 180),
	TEXT_DIM = Color3.fromRGB(120, 120, 120),
	ACCENT = Color3.fromRGB(0, 162, 255),
	ACCENT_DIM = Color3.fromRGB(0, 120, 200),
	FAV_ACTIVE = Color3.fromRGB(255, 170, 50),
	FAV_DOT = Color3.fromRGB(255, 170, 50),
	GREEN_ON = Color3.fromRGB(0, 180, 80),
	RED_OFF = Color3.fromRGB(180, 50, 50),
	ANIM_MODE = Color3.fromRGB(140, 100, 200),
	BORDER = Color3.fromRGB(70, 70, 70),
}

-- ============ UI ELEMENTS ============ --
local UI = {
	Under = nil, LeftBtn = nil, RightBtn = nil,
	PagesLabel = nil, SepLabel = nil, PageNumBox = nil,
	Top = nil, Search = nil, FavBtn = nil, ModeBtn = nil,
	AutoReapplyBtn = nil,
	FavBtnLabel = nil, ModeBtnLabel = nil, AutoBtnLabel = nil,
}

-- ============ UTILITIES ============ --
local function notify(title, content, duration)
	pcall(function()
		StarterGui:SetCore("SendNotification", {
			Title = title or "PinkWards",
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

-- ============ FAST FAVORITE LOOKUP ============ --
local function rebuildFavLookup()
	State.favLookupEmote = {}
	for _, v in ipairs(State.favEmotes) do
		State.favLookupEmote[tostring(v.id)] = true
	end
	State.favLookupAnim = {}
	for _, v in ipairs(State.favAnims) do
		State.favLookupAnim[tostring(v.id)] = true
	end
	-- Invalidate normal list cache
	State.normalListCacheVersion = -1
end

local function isInFav(id)
	local lookup = State.mode == "animation" and State.favLookupAnim or State.favLookupEmote
	return lookup[tostring(id)] == true
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

-- ============ NORMAL LIST CACHE (avoids rebuilding every frame) ============ --
local function getNormalList()
	local list = State.mode == "animation" and State.filteredAnims or State.filteredEmotes
	local version = State.favSetVersion

	if State.normalListCache
		and State.normalListCacheVersion == version
		and State.normalListCacheMode == State.mode then
		return State.normalListCache
	end

	local result = {}
	local lookup = State.mode == "animation" and State.favLookupAnim or State.favLookupEmote

	for i = 1, #list do
		if not lookup[tostring(list[i].id)] then
			result[#result + 1] = list[i]
		end
	end

	State.normalListCache = result
	State.normalListCacheVersion = version
	State.normalListCacheMode = State.mode
	return result
end

-- ============ NATIVE THEME ============ --
local function applyNativeTheme()
	local wheel = getWheel()
	if not wheel then return end

	pcall(function()
		local back = wheel:FindFirstChild("Back")
		if back then
			local background = back:FindFirstChild("Background")
			if background then
				if background:IsA("Frame") then
					background.BackgroundColor3 = COLORS.BG_DARK
					background.BackgroundTransparency = 0.05
				end
				local overlay = background:FindFirstChild("BackgroundCircleOverlay")
				if overlay then
					overlay.BackgroundColor3 = COLORS.BG_MEDIUM
					overlay.BackgroundTransparency = 0.1
				end
				for _, child in pairs(background:GetChildren()) do
					if child:IsA("ImageLabel") then
						child.ImageColor3 = COLORS.BG_DARK
						child.ImageTransparency = 0.05
					end
				end
			end
		end
	end)

	if UI.LeftBtn then UI.LeftBtn.ImageColor3 = COLORS.TEXT_SECONDARY end
	if UI.RightBtn then UI.RightBtn.ImageColor3 = COLORS.TEXT_SECONDARY end
	if UI.PagesLabel then UI.PagesLabel.TextColor3 = COLORS.TEXT_SECONDARY end
	if UI.SepLabel then UI.SepLabel.TextColor3 = COLORS.TEXT_DIM end
	if UI.PageNumBox then UI.PageNumBox.TextColor3 = COLORS.TEXT_PRIMARY end

	if UI.Top then
		UI.Top.BackgroundColor3 = COLORS.BG_MEDIUM
		UI.Top.BackgroundTransparency = 0.1
	end

	if UI.FavBtn then
		UI.FavBtn.BackgroundColor3 = State.favEnabled and COLORS.FAV_ACTIVE or COLORS.BG_LIGHT
		UI.FavBtn.BackgroundTransparency = 0.1
	end
	if UI.FavBtnLabel then
		UI.FavBtnLabel.Text = "FAV"
		UI.FavBtnLabel.TextColor3 = State.favEnabled and COLORS.BG_DARK or COLORS.TEXT_SECONDARY
	end

	if UI.ModeBtn then
		UI.ModeBtn.BackgroundColor3 = State.mode == "animation" and COLORS.ANIM_MODE or COLORS.BG_LIGHT
		UI.ModeBtn.BackgroundTransparency = 0.1
	end
	if UI.ModeBtnLabel then
		UI.ModeBtnLabel.Text = State.mode == "animation" and "ANI" or "EMO"
		UI.ModeBtnLabel.TextColor3 = COLORS.TEXT_PRIMARY
	end

	if UI.AutoReapplyBtn then
		UI.AutoReapplyBtn.BackgroundColor3 = State.autoReapplyEnabled and COLORS.GREEN_ON or COLORS.RED_OFF
		UI.AutoReapplyBtn.BackgroundTransparency = 0.1
	end
	if UI.AutoBtnLabel then
		UI.AutoBtnLabel.Text = "RE"
		UI.AutoBtnLabel.TextColor3 = COLORS.TEXT_PRIMARY
	end
end

-- ============ PAGINATION ============ --
local function calcPages()
	local favs = State.mode == "animation" and State.favAnims or State.favEmotes
	local normalList = getNormalList()

	local pages = 0
	if #favs > 0 then pages = pages + math.ceil(#favs / State.itemsPerPage) end
	if #normalList > 0 then pages = pages + math.ceil(#normalList / State.itemsPerPage) end
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
		notify("Animation", "No animation data", 3)
		return
	end

	local char = player.Character or player.CharacterAdded:Wait()
	local hum = char:FindFirstChild("Humanoid")
	local animate = char:FindFirstChild("Animate")

	if not animate then
		notify("Animation", "Animate not found", 3)
		return
	end

	if not hum then
		notify("Animation", "Humanoid not found", 3)
		return
	end

	local bundled = data.bundledItems or getBundled(data.id)
	if not bundled then
		notify("Animation", "No assets for: " .. (data.name or data.id), 3)
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

	notify("Animation", "Applied: " .. (data.name or "Animation"), 3)
end

-- ============ EMOTE PLAYING (OPTIMIZED WITH CANCEL) ============ --
local loadedTracks = {}
local currentLoadId = 0

local function cleanupAllTracks()
	for i = #loadedTracks, 1, -1 do
		local track = loadedTracks[i]
		if track then
			pcall(function()
				track:Stop(0)
				track:Destroy()
			end)
		end
	end
	loadedTracks = {}
	State.currentEmoteTrack = nil
end

local function forceResetAnimator()
	local _, hum = getChar()
	if not hum then return end

	pcall(function()
		local animator = hum:FindFirstChild("Animator")
		if animator then
			for _, track in pairs(animator:GetPlayingAnimationTracks()) do
				track:Stop(0)
				track:Destroy()
			end
		end
	end)

	pcall(function()
		hum:ChangeState(Enum.HumanoidStateType.GettingUp)
		task.wait(0.05)
		hum:ChangeState(Enum.HumanoidStateType.Running)
	end)
end

local function stopCurrentEmote()
	currentLoadId = currentLoadId + 1

	if State.currentEmoteTrack then
		pcall(function()
			State.currentEmoteTrack:Stop(0)
			State.currentEmoteTrack:Destroy()
		end)
		State.currentEmoteTrack = nil
	end

	for i = #loadedTracks, 1, -1 do
		local track = loadedTracks[i]
		local isPlaying = false
		pcall(function() isPlaying = track.IsPlaying end)
		if not isPlaying then
			pcall(function()
				track:Stop(0)
				track:Destroy()
			end)
			table.remove(loadedTracks, i)
		end
	end
end

local function playEmote(emoteId)
	local char, hum = getChar()
	if not hum then return false end

	stopCurrentEmote()

	currentLoadId = currentLoadId + 1
	local myLoadId = currentLoadId

	if #loadedTracks >= 25 then
		cleanupAllTracks()
		forceResetAnimator()
		task.wait(0.1)
		char, hum = getChar()
		if not hum then return false end
	end

	local animator = hum:FindFirstChild("Animator")
	if not animator then return false end

	pcall(function()
		for _, track in pairs(animator:GetPlayingAnimationTracks()) do
			if track.Priority == Enum.AnimationPriority.Action then
				track:Stop(0)
			end
		end
	end)

	local anim = Instance.new("Animation")
	anim.AnimationId = "rbxassetid://" .. emoteId

	local ok, track = pcall(function()
		return animator:LoadAnimation(anim)
	end)

	pcall(function() anim:Destroy() end)

	if myLoadId ~= currentLoadId then
		if ok and track then
			pcall(function() track:Stop(0); track:Destroy() end)
		end
		return false
	end

	if not ok or not track then
		forceResetAnimator()
		return false
	end

	pcall(function()
		track.Priority = Enum.AnimationPriority.Action
		track.Looped = true
	end)

	if myLoadId ~= currentLoadId then
		pcall(function() track:Stop(0); track:Destroy() end)
		return false
	end

	local playOk = pcall(function()
		track:Play(0.1)
	end)

	if not playOk then
		pcall(function() track:Stop(0); track:Destroy() end)
		forceResetAnimator()
		return false
	end

	if myLoadId ~= currentLoadId then
		pcall(function() track:Stop(0); track:Destroy() end)
		return false
	end

	State.currentEmoteTrack = track
	table.insert(loadedTracks, track)

	track.Stopped:Connect(function()
		if State.currentEmoteTrack == track then
			State.currentEmoteTrack = nil
		end
	end)

	return true
end

-- ============ FAVORITE DOT INDICATOR ============ --
local function updateFavIcon(img, id, isFav)
	local dot = img:FindFirstChild("FavDot")
	if isFav then
		if not dot then
			dot = Instance.new("Frame")
			dot.Name = "FavDot"
			dot.Size = UDim2.new(0, 8, 0, 8)
			dot.Position = UDim2.new(0.85, 0, 0.05, 0)
			dot.BackgroundColor3 = COLORS.FAV_DOT
			dot.BackgroundTransparency = 0
			dot.BorderSizePixel = 0
			dot.ZIndex = img.ZIndex + 10
			dot.Parent = img

			local dotCorner = Instance.new("UICorner")
			dotCorner.CornerRadius = UDim.new(1, 0)
			dotCorner.Parent = dot
		end
		dot.Visible = true
	elseif dot then
		dot.Visible = false
	end
end

-- ============ DISPLAY UPDATE (OPTIMIZED) ============ --
local lastDisplayPage = -1
local lastDisplayMode = ""
local lastDisplayFavVer = -1

local function updateDisplay(force)
	-- Skip if nothing changed (unless forced)
	if not force
		and lastDisplayPage == State.currentPage
		and lastDisplayMode == State.mode
		and lastDisplayFavVer == State.favSetVersion then
		return
	end

	lastDisplayPage = State.currentPage
	lastDisplayMode = State.mode
	lastDisplayFavVer = State.favSetVersion

	local char, hum = getChar()
	if not char or not hum or not hum.HumanoidDescription then return end

	local desc = hum.HumanoidDescription
	local favs = State.mode == "animation" and State.favAnims or State.favEmotes
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
				items[#items + 1] = item
			end
		end
	else
		local normalList = getNormalList()
		local adjPage = State.currentPage - favPages
		local startIdx = (adjPage - 1) * State.itemsPerPage + 1
		local endIdx = math.min(startIdx + State.itemsPerPage - 1, #normalList)
		for i = startIdx, endIdx do
			if normalList[i] then items[#items + 1] = normalList[i] end
		end
	end

	local emoteTable = {}
	local equipped = {}
	for _, item in ipairs(items) do
		emoteTable[item.name] = {item.id}
		equipped[#equipped + 1] = item.name
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
							local dot = child:FindFirstChild("FavDot")
							if dot then dot.Visible = false end
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
							local dot = child:FindFirstChild("FavDot")
							if dot then dot.Visible = false end
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
		notify("Favorites", "Removed: " .. name, 3)
	else
		local entry = {id = id, name = name}
		if State.mode == "animation" then
			entry.bundledItems = bundled or getBundled(id)
		end
		table.insert(list, entry)
		notify("Favorites", "Added: " .. name, 3)
	end

	local fileName = State.mode == "animation" and State.favAnimFileName or State.favFileName
	saveFile(fileName, list)
	rebuildFavLookup()
	State.favSetVersion = State.favSetVersion + 1
	State.totalPages = calcPages()
	updatePageDisplay()
	updateDisplay(true)
end

-- ============ WHEEL CLICK HANDLER ============ --
local function handleSector(index)
	if tick() - State.lastAction < 0.35 then return end
	State.lastAction = tick()

	local favs = State.mode == "animation" and State.favAnims or State.favEmotes
	local favPages = #favs > 0 and math.ceil(#favs / State.itemsPerPage) or 0

	local item
	if State.currentPage <= favPages and #favs > 0 then
		local startIdx = (State.currentPage - 1) * State.itemsPerPage
		item = favs[startIdx + index]
		if item and State.mode == "animation" and not item.bundledItems then
			item.bundledItems = getBundled(item.id)
		end
	else
		local normalList = getNormalList()
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
		task.spawn(function()
			playEmote(item.id)
		end)
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

-- ============ DATA FETCHING (CHUNKED FOR PERFORMANCE) ============ --
local function fetchEmotes()
	if State.isLoading then return end
	State.isLoading = true

	local ok, result = pcall(function()
		return HttpService:JSONDecode(game:HttpGet(EMOTE_URL))
	end)

	if ok and result then
		local rawList = result.data or result
		local data = {}
		-- Pre-allocate table size hint by building in chunks
		for i = 1, #rawList do
			local item = rawList[i]
			local id = tonumber(item.id)
			if id and id > 0 then
				data[#data + 1] = {id = id, name = item.name or ("Emote_" .. id)}
			end
		end
		State.emotesData = data
		State.filteredEmotes = data
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
		local rawList = result.data or result
		local data = {}
		for i = 1, #rawList do
			local item = rawList[i]
			local id = tonumber(item.id)
			if id and id > 0 then
				data[#data + 1] = {
					id = id,
					name = item.name or ("Anim_" .. id),
					bundledItems = item.bundledItems
				}
			end
		end
		State.animsData = data
		State.filteredAnims = data
	end

	State.isLoading = false
end

-- ============ SEARCH (DEBOUNCED + OPTIMIZED) ============ --
local function searchItems(term)
	term = term:lower()

	if term == State.lastSearchTerm then return end
	State.lastSearchTerm = term

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

		-- For large datasets, limit scan with early termination for exact ID
		if isIdSearch then
			for i = 1, #source do
				if tostring(source[i].id) == term then
					result[#result + 1] = source[i]
					break -- Exact ID match, only one result
				end
			end
		else
			-- Name search - use plain find for speed (no patterns)
			for i = 1, #source do
				if source[i].name:lower():find(term, 1, true) then
					result[#result + 1] = source[i]
				end
			end
		end

		if State.mode == "animation" then
			State.filteredAnims = result
		else
			State.filteredEmotes = result
		end
	end

	-- Invalidate normal list cache
	State.normalListCacheVersion = -1

	State.currentPage = 1
	State.totalPages = calcPages()
	updatePageDisplay()
	updateDisplay(true)
end

-- ============ NAVIGATION ============ --
local function prevPage()
	State.currentPage = State.currentPage <= 1 and State.totalPages or State.currentPage - 1
	updatePageDisplay()
	updateDisplay(true)
end

local function nextPage()
	State.currentPage = State.currentPage >= State.totalPages and 1 or State.currentPage + 1
	updatePageDisplay()
	updateDisplay(true)
end

local function goToPage(num)
	State.currentPage = math.clamp(num, 1, State.totalPages)
	updatePageDisplay()
	updateDisplay(true)
end

-- ============ TOGGLES ============ --
local function toggleMode()
	State.mode = State.mode == "emote" and "animation" or "emote"

	if State.mode == "animation" and #State.animsData == 0 then
		fetchAnims()
	end

	if UI.Search then UI.Search.Text = "" end
	State.lastSearchTerm = ""

	if State.mode == "animation" then
		State.filteredAnims = State.animsData
	else
		State.filteredEmotes = State.emotesData
	end

	-- Invalidate cache
	State.normalListCacheVersion = -1

	State.currentPage = 1
	State.totalPages = calcPages()
	updatePageDisplay()
	updateDisplay(true)
	applyNativeTheme()

	notify("Mode", State.mode == "animation" and "Animation Mode" or "Emote Mode", 3)
end

local function toggleFavMode()
	State.favEnabled = not State.favEnabled
	applyNativeTheme()
	notify("Favorites", State.favEnabled and "Click items to favorite" or "Favorite mode OFF", 3)
	updateDisplay(true)
end

local function toggleAutoReapply()
	State.autoReapplyEnabled = not State.autoReapplyEnabled
	saveAutoReapplySetting()
	applyNativeTheme()

	if State.autoReapplyEnabled then
		notify("Auto-Reapply", "ON - Animations restore on respawn", 3)
	else
		notify("Auto-Reapply", "OFF - Animations won't restore on respawn", 3)
	end
end

-- ============ CHARACTER HANDLING ============ --
local function onCharacterAdded(char)
	local hum = char:WaitForChild("Humanoid")

	currentLoadId = currentLoadId + 1
	cleanupAllTracks()
	loadedTracks = {}
	State.currentEmoteTrack = nil

	if State.autoReapplyEnabled and getgenv().lastAnim and getgenv().lastAnim.id then
		task.wait(0.5)
		applyAnim(getgenv().lastAnim)
		notify("Auto-Reload", "Animation restored", 3)
	end

	hum.Died:Connect(function()
		State.favEnabled = false
		currentLoadId = currentLoadId + 1
		cleanupAllTracks()
		loadedTracks = {}
		applyNativeTheme()
	end)
end

-- ============ GUI CREATION (Native Roblox Style) ============ --
local function makeTextButton(name, parent, pos, size, text, bgColor)
	local btn = Instance.new("ImageButton")
	btn.Name = name
	btn.Parent = parent
	btn.BackgroundColor3 = bgColor or COLORS.BG_LIGHT
	btn.BackgroundTransparency = 0.1
	btn.BorderSizePixel = 0
	btn.Position = pos
	btn.Size = size
	btn.Image = ""

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = btn

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Parent = btn
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 1, 0)
	label.Font = Enum.Font.GothamBold
	label.Text = text
	label.TextColor3 = COLORS.TEXT_PRIMARY
	label.TextScaled = true
	label.ZIndex = btn.ZIndex + 1

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 2)
	padding.PaddingRight = UDim.new(0, 2)
	padding.PaddingTop = UDim.new(0, 2)
	padding.PaddingBottom = UDim.new(0, 2)
	padding.Parent = label

	return btn, label
end

function createGUI()
	local wheel = getWheel()
	if not wheel then return false end

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
	UI.LeftBtn.ImageColor3 = COLORS.TEXT_SECONDARY

	UI.PageNumBox = Instance.new("TextBox")
	UI.PageNumBox.Name = "PageNum"
	UI.PageNumBox.Parent = UI.Under
	UI.PageNumBox.LayoutOrder = 2
	UI.PageNumBox.BackgroundTransparency = 1
	UI.PageNumBox.Size = UDim2.new(0.16, 0, 0.81, 0)
	UI.PageNumBox.Font = Enum.Font.GothamBold
	UI.PageNumBox.Text = "1"
	UI.PageNumBox.TextColor3 = COLORS.TEXT_PRIMARY
	UI.PageNumBox.TextScaled = true

	UI.SepLabel = Instance.new("TextLabel")
	UI.SepLabel.Name = "Separator"
	UI.SepLabel.Parent = UI.Under
	UI.SepLabel.LayoutOrder = 3
	UI.SepLabel.BackgroundTransparency = 1
	UI.SepLabel.Size = UDim2.new(0.34, 0, 0.94, 0)
	UI.SepLabel.Font = Enum.Font.GothamBold
	UI.SepLabel.Text = "/"
	UI.SepLabel.TextColor3 = COLORS.TEXT_DIM
	UI.SepLabel.TextScaled = true

	UI.PagesLabel = Instance.new("TextLabel")
	UI.PagesLabel.Name = "TotalPages"
	UI.PagesLabel.Parent = UI.Under
	UI.PagesLabel.LayoutOrder = 4
	UI.PagesLabel.BackgroundTransparency = 1
	UI.PagesLabel.Size = UDim2.new(0.16, 0, 0.81, 0)
	UI.PagesLabel.Font = Enum.Font.GothamBold
	UI.PagesLabel.Text = "1"
	UI.PagesLabel.TextColor3 = COLORS.TEXT_SECONDARY
	UI.PagesLabel.TextScaled = true

	UI.RightBtn = Instance.new("ImageButton")
	UI.RightBtn.Name = "RightBtn"
	UI.RightBtn.Parent = UI.Under
	UI.RightBtn.LayoutOrder = 5
	UI.RightBtn.BackgroundTransparency = 1
	UI.RightBtn.Size = UDim2.new(0.17, 0, 0.94, 0)
	UI.RightBtn.Image = "rbxassetid://107938916240738"
	UI.RightBtn.ImageColor3 = COLORS.TEXT_SECONDARY

	-- Top search bar
	UI.Top = Instance.new("Frame")
	UI.Top.Name = "Top"
	UI.Top.Parent = wheel
	UI.Top.BackgroundColor3 = COLORS.BG_MEDIUM
	UI.Top.BackgroundTransparency = 0.1
	UI.Top.BorderSizePixel = 0
	UI.Top.Position = UDim2.new(0.13, 0, -0.11, 0)
	UI.Top.Size = UDim2.new(0.74, 0, 0.095, 0)

	local topCorner = Instance.new("UICorner")
	topCorner.CornerRadius = UDim.new(0, 8)
	topCorner.Parent = UI.Top

	local topStroke = Instance.new("UIStroke")
	topStroke.Color = COLORS.BORDER
	topStroke.Thickness = 1
	topStroke.Parent = UI.Top

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
	UI.Search.Font = Enum.Font.Gotham
	UI.Search.PlaceholderText = "Search by name or ID..."
	UI.Search.PlaceholderColor3 = COLORS.TEXT_DIM
	UI.Search.Text = ""
	UI.Search.TextColor3 = COLORS.TEXT_PRIMARY
	UI.Search.TextScaled = true

	-- Favorite button
	UI.FavBtn, UI.FavBtnLabel = makeTextButton(
		"Favorite", wheel,
		UDim2.new(0.019, 0, -0.108, 0),
		UDim2.new(0.0875, 0, 0.0875, 0),
		"FAV",
		COLORS.BG_LIGHT
	)

	-- Mode toggle button
	UI.ModeBtn, UI.ModeBtnLabel = makeTextButton(
		"ModeToggle", wheel,
		UDim2.new(0.889, 0, -0.108, 0),
		UDim2.new(0.0875, 0, 0.0875, 0),
		"EMO",
		COLORS.BG_LIGHT
	)

	-- Auto-Reapply button
	UI.AutoReapplyBtn, UI.AutoBtnLabel = makeTextButton(
		"AutoReapplyToggle", wheel,
		UDim2.new(0.889, 0, -0.215, 0),
		UDim2.new(0.0875, 0, 0.0875, 0),
		"RE",
		State.autoReapplyEnabled and COLORS.GREEN_ON or COLORS.RED_OFF
	)

	-- Connect events
	UI.LeftBtn.MouseButton1Click:Connect(prevPage)
	UI.RightBtn.MouseButton1Click:Connect(nextPage)

	UI.PageNumBox.FocusLost:Connect(function()
		local num = tonumber(UI.PageNumBox.Text)
		if num then goToPage(num) else UI.PageNumBox.Text = tostring(State.currentPage) end
	end)

	-- Debounced search
	local searchDebounceThread = nil
	UI.Search:GetPropertyChangedSignal("Text"):Connect(function()
		if searchDebounceThread then
			pcall(function() task.cancel(searchDebounceThread) end)
		end
		searchDebounceThread = task.delay(0.3, function()
			searchItems(UI.Search.Text)
			searchDebounceThread = nil
		end)
	end)

	UI.FavBtn.MouseButton1Click:Connect(toggleFavMode)
	UI.ModeBtn.MouseButton1Click:Connect(toggleMode)
	UI.AutoReapplyBtn.MouseButton1Click:Connect(toggleAutoReapply)

	applyNativeTheme()
	State.guiCreated = true

	return true
end

-- ============ MAIN LOOPS ============ --
local frameCount = 0
RunService.RenderStepped:Connect(function()
	frameCount = frameCount + 1
	if frameCount >= 60 then -- Check every ~1 second instead of every ~0.5s
		frameCount = 0
		if not State.guiCreated then
			local wheel = getWheel()
			if wheel and createGUI() then
				updatePageDisplay()
				updateDisplay(true)
			end
		else
			applyNativeTheme()
		end
	end
end)

-- ============ INITIALIZATION ============ --
task.spawn(function()
	while not getWheel() do task.wait(0.1) end

	if createGUI() then
		State.favEmotes = loadFile(State.favFileName)
		State.favAnims = loadFile(State.favAnimFileName)
		rebuildFavLookup()
		loadLastAnim()
		loadAutoReapplySetting()
		applyNativeTheme()

		fetchEmotes()
		fetchAnims()

		State.totalPages = calcPages()
		updatePageDisplay()
		updateDisplay(true)

		notify("PinkWards", "Loaded! Press '.' to open", 5)
	end
end)

-- Character added handler
player.CharacterAdded:Connect(onCharacterAdded)
if player.Character then
	task.spawn(function() onCharacterAdded(player.Character) end)
end

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
		task.wait(2) -- Check less frequently
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
		btn.Size = UDim2.new(0, 50, 0, 50)
		btn.Position = UDim2.new(0, 10, 0.5, -25)
		btn.BackgroundColor3 = COLORS.BG_MEDIUM
		btn.BackgroundTransparency = 0.1
		btn.Text = "E"
		btn.Font = Enum.Font.GothamBold
		btn.TextSize = 22
		btn.TextColor3 = COLORS.TEXT_PRIMARY
		btn.Parent = gui

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 8)
		corner.Parent = btn

		local stroke = Instance.new("UIStroke")
		stroke.Color = COLORS.BORDER
		stroke.Thickness = 1
		stroke.Parent = btn

		btn.MouseButton1Click:Connect(function()
			pcall(function() GuiService:SetEmotesMenuOpen(true) end)
		end)
	end)

	notify("Mobile", "Tap 'E' button to open emotes", 10)
end

print("=========================================")
print("   PinkWards Emote + Animation System")
print("   Press '.' to open")
print("   [EMO/ANI] = Toggle Mode")
print("   [FAV] = Favorite Mode")
print("   [RE] = Toggle Auto-Reapply")
print("   Settings save between sessions")
print("=========================================")
