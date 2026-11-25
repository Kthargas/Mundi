local ADDON, ns = ...
local L = ns.L

-- World map additions, all on top of Blizzard's own map:
-- * cave maps: zooming in over a cave opens Blizzard's cave map, zooming out goes back to the zone,
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
-- Cave and building maps
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

-- The cave under the cursor on a zone map, if any.
local function CaveAt(mapID, x, y)
	local best, bestArea
	for _, sub in ipairs(SubMaps(mapID)) do
		if x >= sub.left and x <= sub.right and y >= sub.top and y <= sub.bottom then
			local area = (sub.right - sub.left) * (sub.bottom - sub.top)
			if not bestArea or area < bestArea then best, bestArea = sub.mapID, area end
		end
	end
	return best
end

local function IsCaveType(info)
	return info and (info.mapType == 5 or info.mapType == 4)
end

-- Runs after Blizzard's own wheel handling. At the closest zoom over a cave, one more step in opens
-- Blizzard's cave map; on a cave map at the widest zoom, one more step out goes back to the zone.
-- The extra step keeps a fast scroll from switching maps by accident.
function W:OnWheel(delta)
	if not db().caves then return end
	local map = WorldMapFrame
	local sc = map.ScrollContainer
	if not (sc.HasZoomLevels and sc:HasZoomLevels()) then return end
	local mapID = map:GetMapID()
	local info = mapID and C_Map.GetMapInfo(mapID)
	if not info then return end
	local target = sc.targetScale or sc:GetCanvasScale()

	if delta > 0 and info.mapType == 3 then
		local atMax = target >= sc:GetScaleForMaxZoom() - 0.001
		local x, y = sc:GetNormalizedCursorPosition()
		local cave = atMax and x and CaveAt(mapID, x, y)
		if cave and self.edge == "IN" then
			self.edge = nil
			self.tainted = true
			map:SetMapID(cave)
			return
		end
		self.edge = cave and "IN" or nil
	elseif delta < 0 and IsCaveType(info) and info.parentMapID and info.parentMapID > 0 then
		local atMin = target <= sc:GetScaleForMinZoom() + 0.001
		if atMin and self.edge == "OUT" then
			self.edge = nil
			self.tainted = true
			map:SetMapID(info.parentMapID)
			return
		end
		self.edge = atMin and "OUT" or nil
	else
		self.edge = nil
	end
end

---------------------------------------------------------------------------
-- Resizing the windowed map
---------------------------------------------------------------------------

-- Taint: Blizzard's map code must never run from addon code, or pins it creates meanwhile (the shared
-- map pin, for example) carry the taint and their protected actions (copying the pin to the clipboard)
-- get blocked. So the window size is changed with the plain frame size call right after Blizzard sets
-- its own size; Blizzard then refits the map canvas itself, in secure code.

local function TargetSize(extra)
	local width = db().width
	if not width then return end
	local spacer = Spacer()
	return width + (extra or 0), spacer + width * (DEFAULT_HEIGHT - spacer) / DEFAULT_WIDTH
end

local function QuestLogExtra(map)
	return (map.QuestLog and map.QuestLog:IsShown()) and (map.questLogWidth or 0) or 0
end

-- Called after Blizzard's SetSize/SetWidth on the map, and directly while the map is hidden.
function W:ResizeFrame(extra)
	local map = WorldMapFrame
	if self.sizing or not map or (map.IsMaximized and map:IsMaximized()) then return end
	local width, height = TargetSize(extra or QuestLogExtra(map))
	if not width then return end
	self.sizing = true
	map:SetSize(width, height)
	self.sizing = nil
end

-- Only for an explicit drag of the grip: the canvas has to follow the frame live, and Blizzard does not
-- refit it on its own. The map is refitted again in secure code the next time it opens.
function W:ApplySize()
	self.tainted = true
	local map = WorldMapFrame
	if not map or (map.IsMaximized and map:IsMaximized()) then return end
	local width, height = TargetSize(QuestLogExtra(map))
	if not width then
		width, height = DEFAULT_WIDTH + QuestLogExtra(map), DEFAULT_HEIGHT
	end
	self.sizing = true
	map:SetSize(width, height)
	self.sizing = nil
	if map:IsShown() and map.OnFrameSizeChanged then map:OnFrameSizeChanged() end
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
		if InCombatLockdown() then
			UIErrorsFrame:AddMessage(ERR_NOT_IN_COMBAT or L.NOT_IN_COMBAT, 1, 0.1, 0.1)
			return
		end
		if button == "RightButton" then
			if not db().width then return end
			db().width = nil
			W:ApplySize()
			W:AskReload()
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
				W.resized = true
				W:ApplySize()
			end
		end)
	end)
	grip:SetScript("OnMouseUp", function(self)
		if not self:GetScript("OnUpdate") then return end
		self:SetScript("OnUpdate", nil)
		if W.resized then W:AskReload() end
	end)
	self.grip = grip
end

-- The live refit while dragging runs Blizzard's map code from addon code, which taints the map until
-- the UI is reloaded. After a reload the saved size is applied the clean way.
function W:AskReload()
	self.resized = nil
	StaticPopup_Show("SQUAREMAP_WM_RELOAD")
end

StaticPopupDialogs["SQUAREMAP_WM_RELOAD"] = {
	text = L.WM_RELOAD,
	button1 = L.WM_RELOAD_NOW,
	button2 = L.WM_RELOAD_LATER,
	OnAccept = function() ReloadUI() end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

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

	self:CreateGrip()
	self:CreateCoords()

	map.ScrollContainer:HookScript("OnMouseWheel", function(_, delta) W:OnWheel(delta) end)
	if map.OnMapChanged then
		hooksecurefunc(map, "OnMapChanged", function() W.edge = nil end)
	end
	-- Blizzard sets the window size when it minimizes the map (SetSize) or toggles the quest log
	-- (SetWidth), and refits the canvas right after. Our size goes in between, so that refit uses it.
	hooksecurefunc(map, "SetSize", function() W:ResizeFrame() end)
	hooksecurefunc(map, "SetWidth", function(_, width)
		local extra = map.minimizedWidth and width and math.max(0, width - map.minimizedWidth) or nil
		W:ResizeFrame(extra)
	end)
	for _, method in ipairs({ "Minimize", "Maximize" }) do
		if map[method] then hooksecurefunc(map, method, function() W:UpdateGrip() end) end
	end
	map:HookScript("OnShow", function()
		W.edge = nil
		W:UpdateGrip()
	end)
	-- Blizzard does not resize the map on every open, so set the saved size once while it is still hidden.
	if not map:IsShown() then self:ResizeFrame() end
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
end
