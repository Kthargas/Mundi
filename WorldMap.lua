local ADDON, ns = ...
local L = ns.L

-- World map additions, all on top of Blizzard's own map:
-- * cave maps: when zoomed in, the cave and building maps of the zone are drawn into the zone map,
-- * a resize grip that changes the size of the windowed map (the map itself, not the UI scale),
-- * player and cursor coordinates under the map.

local W = {}
ns:RegisterModule("worldmap", W)

local DEFAULT_WIDTH, DEFAULT_HEIGHT = 702, 534  -- Blizzard's windowed map (without the quest log)
local MIN_WIDTH = 420

local function db() return ns.db.worldmap end

local function Spacer()
	return TITLE_CANVAS_SPACER_FRAME_HEIGHT or 67
end

---------------------------------------------------------------------------
-- Cave and building maps drawn into the zone map
---------------------------------------------------------------------------

local SUB_TYPES = { 5, 4 } -- Enum.UIMapType.Micro, Enum.UIMapType.Dungeon

local function SubMaps(mapID)
	local list = {}
	local seen = {}
	for _, mapType in ipairs(SUB_TYPES) do
		for _, child in ipairs(C_Map.GetMapChildrenInfo(mapID, mapType, true) or {}) do
			if not seen[child.mapID] then
				seen[child.mapID] = true
				local left, right, top, bottom = C_Map.GetMapRectOnMap(child.mapID, mapID)
				-- Only maps that sit inside the zone and cover a small part of it.
				if left and right > left and bottom > top and (right - left) < 0.6 and (bottom - top) < 0.6 then
					list[#list + 1] = { mapID = child.mapID, left = left, right = right, top = top, bottom = bottom }
				end
			end
		end
	end
	return list
end

function W:CreateCaves()
	local sc = WorldMapFrame.ScrollContainer
	local f = CreateFrame("Frame", nil, sc.Child)
	f:SetPoint("TOPLEFT")
	f:SetFrameLevel(sc.Child:GetFrameLevel() + 2)
	f.tiles = {}
	self.caves = f
end

function W:ReleaseCaves()
	for _, tex in ipairs(self.caves.tiles) do tex:Hide() end
	self.caves.used = 0
end

function W:AcquireTile()
	local f = self.caves
	f.used = f.used + 1
	local tex = f.tiles[f.used]
	if not tex then
		tex = f:CreateTexture(nil, "ARTWORK")
		f.tiles[f.used] = tex
	end
	return tex
end

-- Draws the first art layer of a sub map into its rectangle on the zone map, tile by tile.
function W:DrawSubMap(sub, canvasW, canvasH)
	local layers = C_Map.GetMapArtLayers(sub.mapID)
	local layer = layers and layers[1]
	local textures = layer and C_Map.GetMapArtLayerTextures(sub.mapID, 1)
	if not (layer and textures and layer.layerWidth > 0 and layer.layerHeight > 0) then return end
	local cols = math.ceil(layer.layerWidth / layer.tileWidth)
	local rows = math.ceil(layer.layerHeight / layer.tileHeight)
	local scaleX = (sub.right - sub.left) * canvasW / layer.layerWidth
	local scaleY = (sub.bottom - sub.top) * canvasH / layer.layerHeight
	for row = 1, rows do
		for col = 1, cols do
			local file = textures[(row - 1) * cols + col]
			if file then
				local px, py = (col - 1) * layer.tileWidth, (row - 1) * layer.tileHeight
				local w = math.min(layer.tileWidth, layer.layerWidth - px)
				local h = math.min(layer.tileHeight, layer.layerHeight - py)
				local tex = self:AcquireTile()
				tex:SetTexture(file, nil, nil, "TRILINEAR")
				tex:SetTexCoord(0, w / layer.tileWidth, 0, h / layer.tileHeight)
				tex:ClearAllPoints()
				tex:SetPoint("TOPLEFT", self.caves, "TOPLEFT", sub.left * canvasW + px * scaleX, -(sub.top * canvasH + py * scaleY))
				tex:SetSize(w * scaleX, h * scaleY)
				tex:Show()
			end
		end
	end
end

function W:RefreshCaves()
	local f = self.caves
	if not f then return end
	self:ReleaseCaves()
	self.caveScale = nil
	local map = WorldMapFrame
	local mapID = map:GetMapID()
	local info = mapID and C_Map.GetMapInfo(mapID)
	if not (db().caves and info and info.mapType == 3) then -- Enum.UIMapType.Zone
		f:Hide()
		return
	end
	local canvasW, canvasH = map.ScrollContainer.Child:GetSize()
	f:SetSize(canvasW, canvasH)
	for _, sub in ipairs(SubMaps(mapID)) do
		self:DrawSubMap(sub, canvasW, canvasH)
	end
	f:SetShown(f.used > 0)
	self:UpdateCaveAlpha()
end

-- The caves fade in while zooming in: hidden at the widest zoom, fully shown from halfway on.
function W:UpdateCaveAlpha()
	local f = self.caves
	if not (f and f:IsShown()) then return end
	local sc = WorldMapFrame.ScrollContainer
	if not (sc.HasZoomLevels and sc:HasZoomLevels()) then return end
	local scale = sc:GetCanvasScale()
	if scale == self.caveScale then return end
	self.caveScale = scale
	local minScale, maxScale = sc:GetScaleForMinZoom(), sc:GetScaleForMaxZoom()
	local t = maxScale > minScale and (scale - minScale) / (maxScale - minScale) or 1
	f:SetAlpha(math.max(0, math.min(1, (t - 0.1) / 0.4)) * db().caveAlpha)
end

---------------------------------------------------------------------------
-- Resizing the windowed map
---------------------------------------------------------------------------

function W:ApplySize()
	local map = WorldMapFrame
	if not map or (map.IsMaximized and map:IsMaximized()) then return end
	local width = db().width
	if not width then return end
	local spacer = Spacer()
	local height = spacer + width * (DEFAULT_HEIGHT - spacer) / DEFAULT_WIDTH
	local questLog = (map.QuestLog and map.QuestLog:IsShown()) and (map.questLogWidth or 0) or 0
	map:SetSize(width + questLog, height)
	map:OnFrameSizeChanged()
	self:RefreshCaves()
end

function W:CreateGrip()
	local map = WorldMapFrame
	-- The border frame lies over the whole map in HIGH strata and catches the mouse; the grip has to sit
	-- above it, or only a corner pixel outside the frame reacts.
	local border = map.BorderFrame or map
	local grip = CreateFrame("Button", nil, border)
	grip:SetSize(20, 20)
	grip:SetPoint("BOTTOMRIGHT", map, "BOTTOMRIGHT", -3, 3)
	grip:SetFrameStrata(border:GetFrameStrata())
	grip:SetFrameLevel(border:GetFrameLevel() + 700)
	grip:SetHitRectInsets(-6, -6, -6, -6)
	grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
	grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
	grip:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip_SetTitle(GameTooltip, L.WM_RESIZE)
		GameTooltip:AddLine(L.WM_RESIZE_TT, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	grip:SetScript("OnLeave", GameTooltip_Hide)

	grip:SetScript("OnMouseDown", function(self, button)
		if button == "RightButton" then
			db().width = nil
			if map.Minimize and not (map.IsMaximized and map:IsMaximized()) then
				map:SetSize(DEFAULT_WIDTH + ((map.QuestLog and map.QuestLog:IsShown()) and (map.questLogWidth or 0) or 0), DEFAULT_HEIGHT)
				map:OnFrameSizeChanged()
				W:RefreshCaves()
			end
			return
		end
		if button ~= "LeftButton" then return end
		local scale = map:GetEffectiveScale()
		local startX = GetCursorPosition() / scale
		local startWidth = db().width or DEFAULT_WIDTH
		local maxWidth = UIParent:GetWidth() - 40
		self:SetScript("OnUpdate", function()
			local x = GetCursorPosition() / scale
			local width = math.floor(math.max(MIN_WIDTH, math.min(maxWidth, startWidth + x - startX)) + 0.5)
			if width ~= db().width then
				db().width = width
				W:ApplySize()
			end
		end)
	end)
	grip:SetScript("OnMouseUp", function(self)
		self:SetScript("OnUpdate", nil)
	end)
	self.grip = grip
end

function W:UpdateGrip()
	local map = WorldMapFrame
	if self.grip then
		self.grip:SetShown(not (map.IsMaximized and map:IsMaximized()))
	end
end

---------------------------------------------------------------------------
-- Coordinates under the map
---------------------------------------------------------------------------

local function Format(x, y)
	if not x or ns.IsSecret(x) or ns.IsSecret(y) or (x == 0 and y == 0) then return "--" end
	return ("%.1f, %.1f"):format(x * 100, y * 100)
end

function W:CreateCoords()
	local sc = WorldMapFrame.ScrollContainer
	local f = CreateFrame("Frame", nil, sc)
	f:SetPoint("BOTTOMLEFT", sc, "BOTTOMLEFT", 0, 0)
	f:SetPoint("BOTTOMRIGHT", sc, "BOTTOMRIGHT", 0, 0)
	f:SetHeight(20)
	f:SetFrameLevel(sc:GetFrameLevel() + 100)
	local bg = f:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0, 0, 0, 0.45)
	local text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	text:SetPoint("CENTER")
	f.text = text

	local elapsed = 0
	f:SetScript("OnUpdate", function(_, dt)
		elapsed = elapsed + dt
		if elapsed < 0.1 then return end
		elapsed = 0
		W:UpdateCoords()
	end)
	self.coords = f
end

function W:UpdateCoords()
	local f, map = self.coords, WorldMapFrame
	if not (f and map:IsShown()) then return end
	local mapID = map:GetMapID()
	local px, py
	if mapID then
		local pos = C_Map.GetPlayerMapPosition(mapID, "player")
		if pos and not ns.IsSecret(pos) then px, py = pos:GetXY() end
	end
	local cursor = "--"
	if map.ScrollContainer:IsMouseOver() then
		cursor = Format(map.ScrollContainer:GetNormalizedCursorPosition())
	end
	f.text:SetText(L.WM_COORDS_LINE:format(Format(px, py), cursor))
end

---------------------------------------------------------------------------

function W:Setup()
	local map = WorldMapFrame
	if self.hooked or not (map and map.ScrollContainer and map.ScrollContainer.Child) then return end
	self.hooked = true

	self:CreateCaves()
	self:CreateGrip()
	self:CreateCoords()

	if map.OnMapChanged then
		hooksecurefunc(map, "OnMapChanged", function() W:RefreshCaves() end)
	end
	map.ScrollContainer:HookScript("OnUpdate", function() W:UpdateCaveAlpha() end)
	-- Blizzard sets the window size when the map opens, minimizes or toggles the quest log; ours wins afterwards.
	for _, method in ipairs({ "Minimize", "SetQuestLogPanelShown" }) do
		if map[method] then hooksecurefunc(map, method, function() W:ApplySize() W:UpdateGrip() end) end
	end
	if map.Maximize then hooksecurefunc(map, "Maximize", function() W:UpdateGrip() W:RefreshCaves() end) end
	map:HookScript("OnShow", function()
		W:UpdateGrip()
		W:ApplySize()
		W:RefreshCaves()
	end)
	self:Apply()
end

function W:Init()
	if WorldMapFrame then
		self:Setup()
	else
		local f = CreateFrame("Frame")
		f:RegisterEvent("ADDON_LOADED")
		f:SetScript("OnEvent", function(frame, _, name)
			if name == "Blizzard_WorldMap" then
				frame:UnregisterEvent("ADDON_LOADED")
				W:Setup()
			end
		end)
	end
	self.ready = true
end

function W:Apply()
	if not self.hooked then return end
	if self.coords then self.coords:SetShown(db().coords) end
	if WorldMapFrame:IsShown() then
		self:ApplySize()
		self:RefreshCaves()
	end
end
