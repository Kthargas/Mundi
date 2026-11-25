local ADDON, ns = ...

-- Level ranges on the world map:
-- * next to the zone name that Blizzard shows while the cursor is over a zone of a continent map,
-- * in the middle of every zone on the continent map.
-- Both are Mundi's own font strings on top of Blizzard's map. Blizzard's map code is never called and
-- no map pins are used, so the map stays untainted.
local V = {}
ns:RegisterModule("levels", V)

local CONTINENT, ZONE = 2, 3   -- Enum.UIMapType

local function db() return ns.db.worldmap end

---------------------------------------------------------------------------
-- Level data
---------------------------------------------------------------------------
-- Forever's client knows no level ranges (C_Map.GetMapLevels returns nothing), so Mundi carries the
-- classic ones. Looked up by zone name (English and German) and by the classic map ID.
local RANGES = {
	-- Eastern Kingdoms
	{ 1, 10, 1429, "Elwynn Forest", "Wald von Elwynn" },
	{ 1, 10, 1426, "Dun Morogh" },
	{ 1, 10, 1420, "Tirisfal Glades", "Tirisfal" },
	{ 10, 20, 1436, "Westfall" },
	{ 10, 20, 1432, "Loch Modan" },
	{ 10, 20, 1421, "Silverpine Forest", "Silberwald" },
	{ 15, 25, 1433, "Redridge Mountains", "Rotkammgebirge" },
	{ 18, 30, 1431, "Duskwood", "Dämmerwald" },
	{ 20, 30, 1424, "Hillsbrad Foothills", "Vorgebirge des Hügellands" },
	{ 20, 30, 1437, "Wetlands", "Sumpfland" },
	{ 30, 40, 1416, "Alterac Mountains", "Alteracgebirge" },
	{ 30, 40, 1417, "Arathi Highlands", "Arathihochland" },
	{ 30, 45, 1434, "Stranglethorn Vale", "Schlingendorntal" },
	{ 35, 45, 1418, "Badlands", "Ödland" },
	{ 35, 45, 1435, "Swamp of Sorrows", "Sümpfe des Elends" },
	{ 40, 50, 1425, "The Hinterlands", "Hinterland" },
	{ 43, 50, 1427, "Searing Gorge", "Sengende Schlucht" },
	{ 45, 55, 1419, "Blasted Lands", "Verwüstete Lande" },
	{ 50, 58, 1428, "Burning Steppes", "Brennende Steppe" },
	{ 51, 58, 1422, "Western Plaguelands", "Westliche Pestländer" },
	{ 53, 60, 1423, "Eastern Plaguelands", "Östliche Pestländer" },
	{ 55, 60, 1430, "Deadwind Pass", "Gebirgspass der Totenwinde" },
	-- Kalimdor
	{ 1, 10, 1411, "Durotar" },
	{ 1, 10, 1412, "Mulgore" },
	{ 1, 10, 1438, "Teldrassil" },
	{ 10, 20, 1439, "Darkshore", "Dunkelküste" },
	{ 10, 25, 1413, "The Barrens", "Brachland" },
	{ 15, 27, 1442, "Stonetalon Mountains", "Steinkrallengebirge" },
	{ 18, 30, 1440, "Ashenvale", "Eschental" },
	{ 25, 35, 1441, "Thousand Needles", "Tausend Nadeln" },
	{ 30, 40, 1443, "Desolace" },
	{ 35, 45, 1445, "Dustwallow Marsh", "Düstermarschen" },
	{ 40, 50, 1444, "Feralas" },
	{ 40, 50, 1446, "Tanaris" },
	{ 45, 55, 1447, "Azshara" },
	{ 48, 55, 1448, "Felwood", "Teufelswald" },
	{ 48, 55, 1449, "Un'Goro Crater", "Krater von Un'Goro" },
	{ 55, 60, 1451, "Silithus" },
	{ 55, 60, 1452, "Winterspring", "Winterquell" },
}

local BY_NAME, BY_ID = {}, {}
for _, r in ipairs(RANGES) do
	local range = { r[1], r[2] }
	BY_ID[r[3]] = range
	for i = 4, #r do BY_NAME[r[i]] = range end
end

-- Lowest and highest level of a zone, or nil.
function V:GetLevels(mapID, name)
	if C_Map.GetMapLevels then
		local ok, minLevel, maxLevel = pcall(C_Map.GetMapLevels, mapID)
		if ok and type(minLevel) == "number" and type(maxLevel) == "number" and minLevel > 0 and maxLevel > 0 then
			return minLevel, maxLevel
		end
	end
	if not name then
		local info = C_Map.GetMapInfo(mapID)
		name = info and info.name
	end
	local range = (name and BY_NAME[name]) or BY_ID[mapID]
	if range then return range[1], range[2] end
end

-- Colour like Blizzard's quest difficulty: red/orange when the zone is above you, yellow while you are in
-- its range, green and grey when you have outgrown it.
local function LevelColor(minLevel, maxLevel)
	local level = UnitLevel("player") or 1
	local color
	if level >= minLevel and level <= maxLevel then
		color = QuestDifficultyColors and QuestDifficultyColors.standard
	elseif GetQuestDifficultyColor then
		color = GetQuestDifficultyColor(level < minLevel and minLevel or maxLevel)
	end
	color = color or NORMAL_FONT_COLOR
	return color.r, color.g, color.b
end

local function RangeText(minLevel, maxLevel)
	if minLevel == maxLevel then return tostring(minLevel) end
	return ("%d-%d"):format(minLevel, maxLevel)
end

---------------------------------------------------------------------------
-- Next to the zone name under the cursor
---------------------------------------------------------------------------
-- Blizzard's area label (the zone name over the continent map) lives on its data provider.
local function FindAreaLabel()
	for provider in pairs(WorldMapFrame.dataProviders or {}) do
		local label = type(provider) == "table" and provider.Label
		if type(label) == "table" and type(label.Name) == "table" and label.Name.GetText then
			return label
		end
	end
end

local function Plain(text)
	return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

function V:CreateHover()
	local label = FindAreaLabel()
	if not label then return end
	-- A child of the label: it fades and hides together with Blizzard's name.
	local f = CreateFrame("Frame", nil, label)
	f:SetSize(1, 1)
	f:SetFrameLevel(label:GetFrameLevel() + 2)
	local text = f:CreateFontString(nil, "OVERLAY")
	text:SetPoint("LEFT", label.Name, "RIGHT", 6, 0)
	f.text = text
	f.label = label
	f:Hide()
	self.hover = f
end

function V:UpdateHover()
	local f = self.hover
	if not f then return end
	local map = WorldMapFrame
	local mapID = map:GetMapID()
	local info = mapID and C_Map.GetMapInfo(mapID)
	local name = f.label.Name
	local show = false
	if db().levelHover and info and info.mapType == CONTINENT and name:IsVisible()
		and map.ScrollContainer:IsMouseOver() then
		local x, y = map.ScrollContainer:GetNormalizedCursorPosition()
		local hovered = x and C_Map.GetMapInfoAtPosition(mapID, x, y)
		local shown = name:GetText()
		-- Only for the zone Blizzard is naming right now, and not when the client adds its own range.
		if hovered and hovered.mapID ~= mapID and shown and not shown:find("%(%d+%-%d+%)")
			and Plain(shown):find(hovered.name, 1, true) then
			local minLevel, maxLevel = self:GetLevels(hovered.mapID, hovered.name)
			if minLevel then
				local font, size, flags = name:GetFont()
				if font then f.text:SetFont(font, size, flags) end
				f.text:SetShadowColor(name:GetShadowColor())
				f.text:SetShadowOffset(name:GetShadowOffset())
				f.text:SetText("(" .. RangeText(minLevel, maxLevel) .. ")")
				f.text:SetTextColor(LevelColor(minLevel, maxLevel))
				show = true
			end
		end
	end
	f:SetShown(show)
end

---------------------------------------------------------------------------
-- In the middle of every zone on the continent map
---------------------------------------------------------------------------
-- A spot inside the zone: of a grid of points over the zone's rectangle, the one that really lies in the
-- zone and is closest to the middle of all such points (the middle of the rectangle can be in the sea).
local spots = {}

local function ZoneSpot(continentID, zoneID)
	local key = continentID .. ":" .. zoneID
	if spots[key] ~= nil then return spots[key] or nil end
	local left, right, top, bottom = C_Map.GetMapRectOnMap(zoneID, continentID)
	local spot = false
	if left and right > left and bottom > top then
		local hits, sx, sy = {}, 0, 0
		local N = 12
		for i = 0, N - 1 do
			for j = 0, N - 1 do
				local x = left + (right - left) * (i + 0.5) / N
				local y = top + (bottom - top) * (j + 0.5) / N
				local at = C_Map.GetMapInfoAtPosition(continentID, x, y)
				if at and at.mapID == zoneID then
					hits[#hits + 1] = { x, y }
					sx, sy = sx + x, sy + y
				end
			end
		end
		if #hits > 0 then
			local cx, cy = sx / #hits, sy / #hits
			local best, bestDist
			for _, p in ipairs(hits) do
				local d = (p[1] - cx) ^ 2 + (p[2] - cy) ^ 2
				if not bestDist or d < bestDist then best, bestDist = p, d end
			end
			spot = best
		else
			spot = { (left + right) / 2, (top + bottom) / 2 }
		end
	end
	spots[key] = spot
	return spot or nil
end

function V:CreateMapLabels()
	local canvas = WorldMapFrame.ScrollContainer.Child
	local holder = CreateFrame("Frame", nil, canvas)
	holder:SetAllPoints(canvas)
	holder:SetFrameLevel(canvas:GetFrameLevel() + 1500)
	-- Just above the explored-area art, below Blizzard's map pins (quests, flight points, ...).
	local manager = WorldMapFrame.GetPinFrameLevelsManager and WorldMapFrame:GetPinFrameLevelsManager()
	if manager and manager.GetValidFrameLevel then
		local ok, level = pcall(manager.GetValidFrameLevel, manager, "PIN_FRAME_LEVEL_MAP_EXPLORATION")
		if ok and type(level) == "number" then holder:SetFrameLevel(level + 1) end
	end
	holder.labels = {}
	holder:SetScript("OnUpdate", function()
		-- Keep the text the same size on screen at every zoom.
		local scale = WorldMapFrame.ScrollContainer:GetCanvasScale()
		if scale and scale ~= holder.scale then V:PlaceMapLabels() end
	end)
	holder:Hide()
	self.holder = holder
end

local function Label(i)
	local holder = V.holder
	local f = holder.labels[i]
	if not f then
		f = CreateFrame("Frame", nil, holder)
		f:SetSize(1, 1)
		local text = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
		local font, size = text:GetFont()
		if font then text:SetFont(font, size, "OUTLINE") end
		text:SetPoint("CENTER")
		f.text = text
		holder.labels[i] = f
	end
	return f
end

function V:PlaceMapLabels()
	local holder = self.holder
	local canvasScale = WorldMapFrame.ScrollContainer:GetCanvasScale() or 1
	holder.scale = canvasScale
	local width, height = holder:GetSize()
	local s = 1 / math.max(canvasScale, 0.01)
	for i = 1, holder.count or 0 do
		local f = holder.labels[i]
		f:SetScale(s)
		f:ClearAllPoints()
		f:SetPoint("CENTER", holder, "TOPLEFT", f.x * width / s, -f.y * height / s)
	end
end

function V:UpdateMapLabels()
	local holder = self.holder
	if not holder then return end
	local mapID = WorldMapFrame:GetMapID()
	local info = mapID and C_Map.GetMapInfo(mapID)
	if not (db().levelMap and info and info.mapType == CONTINENT) then
		holder:Hide()
		return
	end
	local count = 0
	for _, child in ipairs(C_Map.GetMapChildrenInfo(mapID, ZONE) or {}) do
		local minLevel, maxLevel = self:GetLevels(child.mapID, child.name)
		local spot = minLevel and ZoneSpot(mapID, child.mapID)
		if spot then
			count = count + 1
			local f = Label(count)
			f.x, f.y = spot[1], spot[2]
			f.text:SetText(RangeText(minLevel, maxLevel))
			f.text:SetTextColor(LevelColor(minLevel, maxLevel))
			f:Show()
		end
	end
	for i = count + 1, #holder.labels do holder.labels[i]:Hide() end
	holder.count = count
	holder:SetShown(count > 0)
	self:PlaceMapLabels()
end

---------------------------------------------------------------------------
function V:Setup()
	local map = WorldMapFrame
	if self.hooked or not (map and map.ScrollContainer and map.ScrollContainer.Child) then return end
	self.hooked = true
	self:CreateHover()
	self:CreateMapLabels()
	local driver = CreateFrame("Frame", nil, map)
	local elapsed = 0
	driver:SetScript("OnUpdate", function(_, dt)
		elapsed = elapsed + dt
		if elapsed < 0.05 then return end
		elapsed = 0
		V:UpdateHover()
	end)
	if map.OnMapChanged then
		hooksecurefunc(map, "OnMapChanged", function() V:UpdateMapLabels() end)
	end
	map:HookScript("OnShow", function() V:UpdateMapLabels() end)
	map.ScrollContainer.Child:HookScript("OnSizeChanged", function()
		if V.holder:IsShown() then V:PlaceMapLabels() end
	end)
	self:Apply()
end

function V:Init()
	if WorldMapFrame then
		self:Setup()
	else
		local f = CreateFrame("Frame")
		f:RegisterEvent("ADDON_LOADED")
		f:SetScript("OnEvent", function(frame, _, name)
			if name == "Blizzard_WorldMap" then
				frame:UnregisterEvent("ADDON_LOADED")
				V:Setup()
			end
		end)
	end
	-- Colours follow your level.
	local f = CreateFrame("Frame")
	f:RegisterEvent("PLAYER_LEVEL_UP")
	f:SetScript("OnEvent", function() C_Timer.After(0.5, function() V:Apply() end) end)
end

function V:Apply()
	if not self.hooked then return end
	if WorldMapFrame:IsShown() then self:UpdateMapLabels() else self.holder:Hide() end
	if not db().levelHover and self.hover then self.hover:Hide() end
end
