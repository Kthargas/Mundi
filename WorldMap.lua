local ADDON, ns = ...
local L = ns.L

-- World map: seamless zoom (wheel past the closest zoom opens the zone, cave or dungeon map under the cursor,
-- wheel past the widest zoom goes up a level), a scale for the windowed map and coordinates.
-- Blizzard's own map is kept; everything is added with hooks.

local W = {}
ns:RegisterModule("worldmap", W)

local EPSILON = 0.001

local function db() return ns.db.worldmap end

-- The smallest child map whose area on the current map contains the point (zones, caves, dungeons).
local function ChildMapAt(mapID, x, y)
	local best, bestArea
	local children = C_Map.GetMapChildrenInfo and C_Map.GetMapChildrenInfo(mapID)
	for _, child in ipairs(children or {}) do
		local left, right, top, bottom = C_Map.GetMapRectOnMap(child.mapID, mapID)
		if left and right > left and bottom > top and x >= left and x <= right and y >= top and y <= bottom then
			local area = (right - left) * (bottom - top)
			if area < 1 - EPSILON and (not bestArea or area < bestArea) then
				best, bestArea = child.mapID, area
			end
		end
	end
	if best then return best end
	local info = C_Map.GetMapInfoAtPosition and C_Map.GetMapInfoAtPosition(mapID, x, y)
	if info and info.mapID ~= mapID then return info.mapID end
end

function W:Descend()
	local map = WorldMapFrame
	local mapID = map:GetMapID()
	local x, y = map.ScrollContainer:GetNormalizedCursorPosition()
	local child = mapID and x and ChildMapAt(mapID, x, y)
	if child then
		map:SetMapID(child)
		return true
	end
end

function W:Ascend()
	local map = WorldMapFrame
	local info = map:GetMapID() and C_Map.GetMapInfo(map:GetMapID())
	if info and info.parentMapID and info.parentMapID > 0 then
		map:SetMapID(info.parentMapID)
		return true
	end
end

-- Runs after Blizzard's own wheel handling. One extra wheel step at the zoom limit changes the map, so a
-- fast scroll does not jump through several maps at once.
function W:OnWheel(delta)
	if not db().seamlessZoom then return end
	local sc = WorldMapFrame.ScrollContainer
	if not (sc.GetScaleForMaxZoom and sc.HasZoomLevels and sc:HasZoomLevels()) then return end
	local target = sc.targetScale or sc:GetCanvasScale()
	if delta > 0 then
		local atMax = target >= sc:GetScaleForMaxZoom() - EPSILON
		if self.edge == "MAX" and atMax then
			self.edge = nil
			self:Descend()
			return
		end
		self.edge = atMax and "MAX" or nil
	else
		local atMin = target <= sc:GetScaleForMinZoom() + EPSILON
		if self.edge == "MIN" and atMin then
			self.edge = nil
			self:Ascend()
			return
		end
		self.edge = atMin and "MIN" or nil
	end
end

function W:ApplyScale()
	local map = WorldMapFrame
	if not map then return end
	if InCombatLockdown() and map:IsProtected() then
		ns.RunAfterCombat("worldmap-scale", function() W:ApplyScale() end)
		return
	end
	local maximized = map.IsMaximized and map:IsMaximized()
	map:SetScale(maximized and 1 or db().scale)
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
	if self.hooked or not (map and map.ScrollContainer) then return end
	self.hooked = true

	map.ScrollContainer:HookScript("OnMouseWheel", function(_, delta) W:OnWheel(delta) end)
	if map.OnMapChanged then
		hooksecurefunc(map, "OnMapChanged", function() W.edge = nil end)
	end
	map:HookScript("OnShow", function()
		W.edge = nil
		W:ApplyScale()
	end)
	for _, method in ipairs({ "Minimize", "Maximize" }) do
		if map[method] then hooksecurefunc(map, method, function() W:ApplyScale() end) end
	end
	self:CreateCoords()
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
	self:ApplyScale()
	if self.coords then self.coords:SetShown(db().coords) end
end
