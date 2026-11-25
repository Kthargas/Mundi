local ADDON, ns = ...
local L = ns.L

-- Square minimap: keeps Blizzard's own MinimapCluster (zone header, clock, calendar, tracking, mail,
-- addon compartment, day/night cycle, coordinates, zoom buttons) and only changes the shape, the
-- frame art and the places of the pieces that sat on the round frame.

local M = {}
ns:RegisterModule("map", M)

-- Frame styles: Blizzard nine-slice layouts (NineSliceLayouts.lua). "pad" moves the art outwards so
-- its inner edge lines up with the map edge.
M.BORDERS = {
	{ key = "DIALOG", label = L.BORDER_DIALOG, layout = "Dialog", pad = 7 },
	{ key = "TOOLTIP", label = L.BORDER_TOOLTIP, layout = "TooltipDefaultLayout", pad = 3 },
	{ key = "METAL", label = L.BORDER_METAL, layout = "GenericMetal", pad = 0 },
	{ key = "SIMPLE", label = L.BORDER_SIMPLE, layout = "SimplePanelTemplate", pad = 3 },
	{ key = "NONE", label = L.BORDER_NONE },
}

local PIECES = { "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner",
	"TopEdge", "BottomEdge", "LeftEdge", "RightEdge", "Center" }

local function AtlasExists(name)
	return name and C_Texture and C_Texture.GetAtlasInfo(name) ~= nil
end

local function GetLayout(style)
	if not style.layout then return nil end
	local layout = NineSliceLayouts and NineSliceLayouts[style.layout]
	if not layout then return nil end
	-- The art must exist in this client, otherwise the style is skipped.
	local corner = layout.TopLeftCorner and layout.TopLeftCorner.atlas
	local edge = layout.TopEdge and layout.TopEdge.atlas
	if not (AtlasExists(corner) and AtlasExists(edge)) then return nil end
	-- Copy without the centre piece so the map stays visible.
	local copy = {}
	for k, v in pairs(layout) do
		if k ~= "Center" then
			if type(v) == "table" then
				local piece = {}
				for pk, pv in pairs(v) do piece[pk] = pv end
				copy[k] = piece
			else
				copy[k] = v
			end
		end
	end
	return copy
end

function M:GetBorderStyle(key)
	for _, style in ipairs(self.BORDERS) do
		if style.key == key and (not style.layout or GetLayout(style)) then
			return style
		end
	end
	-- Fall back to the first style this client can draw.
	for _, style in ipairs(self.BORDERS) do
		if not style.layout or GetLayout(style) then return style end
	end
	return self.BORDERS[#self.BORDERS]
end

function M:GetAvailableBorders()
	local list = {}
	for _, style in ipairs(self.BORDERS) do
		if not style.layout or GetLayout(style) then list[#list + 1] = style end
	end
	return list
end

-- The visible distance between map edge and the outside of the frame art.
function M:GetBorderExtent()
	local db = ns.db.map
	local style = self:GetBorderStyle(db.border)
	if not style.layout then return 2 end
	return math.max(1, (style.pad or 0) * db.borderScale + db.borderOffset)
end

---------------------------------------------------------------------------
-- Border
---------------------------------------------------------------------------

function M:CreateBorder()
	local border = CreateFrame("Frame", "SquareMapBorder", Minimap)
	border:SetFrameLevel(Minimap:GetFrameLevel() + 2)
	border:EnableMouse(false)
	self.border = border

	-- "Thin line" style: plain colour lines, no texture file
	local lines = {}
	for i = 1, 4 do
		local t = Minimap:CreateTexture(nil, "OVERLAY", nil, 7)
		t:SetColorTexture(0, 0, 0, 0.9)
		t:Hide()
		lines[i] = t
	end
	lines[1]:SetPoint("BOTTOMLEFT", Minimap, "TOPLEFT", -1, 0)
	lines[1]:SetPoint("BOTTOMRIGHT", Minimap, "TOPRIGHT", 1, 0)
	lines[1]:SetHeight(1)
	lines[2]:SetPoint("TOPLEFT", Minimap, "BOTTOMLEFT", -1, 0)
	lines[2]:SetPoint("TOPRIGHT", Minimap, "BOTTOMRIGHT", 1, 0)
	lines[2]:SetHeight(1)
	lines[3]:SetPoint("TOPRIGHT", Minimap, "TOPLEFT", 0, 0)
	lines[3]:SetPoint("BOTTOMRIGHT", Minimap, "BOTTOMLEFT", 0, 0)
	lines[3]:SetWidth(1)
	lines[4]:SetPoint("TOPLEFT", Minimap, "TOPRIGHT", 0, 0)
	lines[4]:SetPoint("BOTTOMLEFT", Minimap, "BOTTOMRIGHT", 0, 0)
	lines[4]:SetWidth(1)
	self.lines = lines
end

function M:ApplyBorder()
	local db = ns.db.map
	local style = self:GetBorderStyle(db.border)
	local border = self.border

	for _, name in ipairs(PIECES) do
		if border[name] then border[name]:Hide() end
	end
	for _, t in ipairs(self.lines) do t:SetShown(not style.layout) end

	local layout = GetLayout(style)
	if not layout then
		border:Hide()
		return
	end

	local scale = db.borderScale > 0 and db.borderScale or 1
	border:SetScale(scale)
	local pad = (style.pad or 0) + db.borderOffset / scale
	border:ClearAllPoints()
	border:SetPoint("TOPLEFT", Minimap, "TOPLEFT", -pad, pad)
	border:SetPoint("BOTTOMRIGHT", Minimap, "BOTTOMRIGHT", pad, -pad)

	NineSliceUtil.ApplyLayout(border, layout)
	for name in pairs(layout) do
		if border[name] and border[name].Show then border[name]:Show() end
	end
	border:Show()
end

---------------------------------------------------------------------------
-- Shape, size and the pieces around the map
---------------------------------------------------------------------------

local function RefreshMinimapRender()
	-- The minimap only redraws its terrain at the new size after a zoom change.
	local zoom = Minimap:GetZoom()
	local levels = Minimap:GetZoomLevels()
	if zoom > 0 then
		Minimap:SetZoom(zoom - 1)
	elseif levels > 1 then
		Minimap:SetZoom(zoom + 1)
	end
	Minimap:SetZoom(zoom)
end

function M:ApplyMask()
	Minimap:SetMaskTexture(ns.SQUARE_MASK)
	-- The quest and archaeology areas are drawn with a round ring by default.
	if Minimap.SetQuestBlobRingScalar then Minimap:SetQuestBlobRingScalar(0) end
	if Minimap.SetArchBlobRingScalar then Minimap:SetArchBlobRingScalar(0) end
	if Minimap.SetTaskBlobRingScalar then Minimap:SetTaskBlobRingScalar(0) end
	if Minimap.SetQuestBlobRingAlpha then Minimap:SetQuestBlobRingAlpha(0) end
	if Minimap.SetArchBlobRingAlpha then Minimap:SetArchBlobRingAlpha(0) end
	if Minimap.SetTaskBlobRingAlpha then Minimap:SetTaskBlobRingAlpha(0) end

	if MinimapCompassTexture then MinimapCompassTexture:Hide() end
	if MinimapCompassTextureUnderlay then MinimapCompassTextureUnderlay:Hide() end
	self:ApplyHybridMask()
end

function M:ApplyHybridMask()
	local hybrid = _G.HybridMinimap
	if not hybrid or not hybrid.CircleMask then return end
	hybrid.CircleMask:SetTexture(ns.SQUARE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	hybrid.CircleMask:ClearAllPoints()
	hybrid.CircleMask:SetAllPoints(hybrid)
end

function M:ApplySize()
	local db = ns.db.map
	local size = db.size
	local sizeChanged = math.abs(Minimap:GetWidth() - size) > 0.5

	Minimap:SetSize(size, size)
	if MinimapBackdrop then
		MinimapBackdrop:SetSize(size, size)
	end

	-- The container used to have the size of the round frame art; now it hugs the square frame.
	local cluster = MinimapCluster
	local container = cluster and cluster.MinimapContainer
	if container then
		local margin = math.ceil(self:GetBorderExtent()) + 2
		container:SetSize(size + margin * 2, size + margin * 2)
	end

	if sizeChanged then
		C_Timer.After(0, RefreshMinimapRender)
	end
end

function M:ApplyZoomButtons()
	local zoomIn, zoomOut, hit = Minimap.ZoomIn, Minimap.ZoomOut, Minimap.ZoomHitArea
	if not (zoomIn and zoomOut) then return end
	local level = (self.border and self.border:GetFrameLevel() or Minimap:GetFrameLevel()) + 3

	zoomOut:ClearAllPoints()
	zoomOut:SetPoint("BOTTOMRIGHT", Minimap, "BOTTOMRIGHT", -5, 6)
	zoomOut:SetFrameLevel(level)
	zoomIn:ClearAllPoints()
	zoomIn:SetPoint("BOTTOM", zoomOut, "TOP", 0, 3)
	zoomIn:SetFrameLevel(level)
	if hit then
		hit:ClearAllPoints()
		hit:SetPoint("BOTTOMRIGHT", Minimap, "BOTTOMRIGHT", 0, 0)
		hit:SetSize(30, 42)
	end

	local mode = ns.db.map.zoomButtons
	if mode == "ALWAYS" then
		zoomIn:Show()
		zoomOut:Show()
	elseif mode == "NEVER" or not Minimap:IsMouseOver() then
		zoomIn:Hide()
		zoomOut:Hide()
	end
end

function M:ApplyCoords()
	local container = MinimapCluster and MinimapCluster.MinimapContainer
	local coords = container and container.PlayerCoords
	if not coords then return end
	coords:ClearAllPoints()
	local pos = ns.db.map.coordsPos
	if pos == "INSIDE" then
		coords:SetPoint("BOTTOM", Minimap, "BOTTOM", 0, 8)
	elseif pos == "TOP" then
		coords:SetPoint("TOP", Minimap, "TOP", 0, -8)
	elseif ns.db.map.headerPos == "BELOW" and MinimapCluster.ZoneTextButton then
		-- The header already sits under the map: put the coordinates under the header.
		local zone = MinimapCluster.ZoneTextButton
		local scale = zone:GetEffectiveScale() / coords:GetEffectiveScale()
		coords:SetPoint("TOP", zone, "BOTTOM", 0, -2 * scale)
	else
		coords:SetPoint("TOP", Minimap, "BOTTOM", 0, -(math.ceil(self:GetBorderExtent()) + 3))
	end
	coords:SetFrameLevel((self.border and self.border:GetFrameLevel() or Minimap:GetFrameLevel()) + 4)
end

-- Header (zone name, clock, calendar, tracking): directly above or below the square map.
function M:ApplyHeader()
	local cluster = MinimapCluster
	local container, zone = cluster.MinimapContainer, cluster.ZoneTextButton
	if not (container and zone) then return end
	local db = ns.db.map
	local scale = container:GetScale()
	if not scale or scale <= 0 then scale = 1 end
	local extent = self:GetBorderExtent()
	local margin = math.ceil(extent) + 2
	local gap = db.headerGap or 0
	local zoneHeight = zone:GetHeight() * zone:GetScale()
	-- Zone button offsets are in its own units, the map edge is in container units.
	local edge = extent * scale / zone:GetScale() + gap / zone:GetScale()

	local shift = self:ApplyHeaderWidth(zone, extent, scale)

	container:ClearAllPoints()
	zone:ClearAllPoints()
	if db.headerPos == "BELOW" then
		container:SetPoint("TOP", cluster, "TOP", 0, (margin - extent))
		zone:SetPoint("TOP", Minimap, "BOTTOM", shift, -edge)
	else
		container:SetPoint("TOP", cluster, "TOP", 0, -(zoneHeight + gap) / scale + (margin - extent))
		zone:SetPoint("BOTTOM", Minimap, "TOP", shift, edge)
	end

	local indicator = cluster.IndicatorFrame
	if indicator then
		indicator:ClearAllPoints()
		if db.headerFull then
			-- The header fills the map width: mail sits in the map corner next to the header, like Blizzard's own.
			if db.headerPos == "BELOW" then
				indicator:SetPoint("BOTTOMLEFT", Minimap, "BOTTOMLEFT", 2, 2)
			else
				indicator:SetPoint("TOPLEFT", Minimap, "TOPLEFT", 2, -2)
			end
		else
			-- Left of the header instead of hanging over the map.
			local left = (cluster.Tracking and cluster.Tracking:IsShown()) and cluster.Tracking or zone
			indicator:SetPoint("RIGHT", left, "LEFT", -2, 0)
		end
	end
	-- Addon compartment: right of the calendar instead of below it.
	local compartment, calendar = _G.AddonCompartmentFrame, _G.GameTimeFrame
	if compartment and calendar then
		compartment:ClearAllPoints()
		compartment:SetPoint("LEFT", calendar, "RIGHT", 0, 0)
	end
end

local HEADER_WIDTH = 152       -- Blizzard's header button
local HEADER_TEXT_WIDTH = 110
local HEADER_SLICE = 12        -- end caps of the header art that must not stretch
local CALENDAR_OVERLAP = 4     -- the calendar overlaps the header end in Blizzard's layout

local function Visible(frame)
	return frame and frame:IsShown() and frame:GetWidth() * frame:GetScale() or 0
end

local function SetHeaderTexture(texture, full)
	if not texture then return end
	texture:ClearAllPoints()
	if full then
		texture:SetAllPoints()
		if texture.SetTextureSliceMargins then
			texture:SetTextureSliceMargins(HEADER_SLICE, 0, HEADER_SLICE, 0)
			if texture.SetTextureSliceMode and Enum.UITextureSliceMode then
				texture:SetTextureSliceMode(Enum.UITextureSliceMode.Stretched)
			end
		end
	else
		texture:SetPoint("CENTER")
	end
end

-- Stretch the header (tracking, zone name, clock, calendar, addon compartment) over the full map width.
-- Returns the horizontal offset that centers the whole row over the map.
function M:ApplyHeaderWidth(zone, extent, scale)
	local db = ns.db.map
	local cluster = MinimapCluster
	local zoneScale = zone:GetScale() or 1
	-- Elements moved with the layout editor no longer take room in the header.
	local layout = ns.layout and ns.db.layout and ns.layout
	local function Moved(key) return layout and layout:IsMoved(key) end
	local left = Moved("tracking") and 0 or Visible(cluster.Tracking)
	local right = (Moved("calendar") and 0 or math.max(0, Visible(_G.GameTimeFrame) - CALENDAR_OVERLAP))
		+ ((Moved("compartment") or Moved("calendar")) and 0 or Visible(_G.AddonCompartmentFrame))
	local width = HEADER_WIDTH
	if db.headerFull then
		local mapWidth = (db.size + extent * 2) * scale
		width = math.max(80, (mapWidth - left - right) / zoneScale)
	end
	zone:SetWidth(width)
	SetHeaderTexture(zone.StateTexture, db.headerFull)
	SetHeaderTexture(zone.AddTexture, db.headerFull)
	local text = _G.MinimapZoneText
	if text then
		local clock = _G.TimeManagerClockButton
		local clockWidth = (clock and clock:IsShown() and not Moved("clock")) and clock:GetWidth() or 0
		text:SetWidth(db.headerFull and math.max(40, width - 12 - clockWidth) or HEADER_TEXT_WIDTH)
	end
	return (left - right) / 2 / zoneScale
end

function M:ApplyDiel()
	local diel = MinimapCluster and MinimapCluster.DielFrame
	if not diel then return end
	diel:SetShown(ns.db.map.showDiel)
	diel:ClearAllPoints()
	-- The day/night frame is counter-scaled by Blizzard, so offsets are in its own units.
	local w, h = diel:GetSize()
	diel:SetPoint("CENTER", Minimap, "TOPRIGHT", -w * 0.3, -h * 0.3)
	diel:SetFrameLevel((self.border and self.border:GetFrameLevel() or Minimap:GetFrameLevel()) + 3)
end

function M:ApplyBackdropButtons()
	local event = MinimapBackdrop and MinimapBackdrop.ExternalEventURLButton
	if event then
		event:ClearAllPoints()
		event:SetPoint("CENTER", Minimap, "BOTTOMLEFT", 16, 16)
	end
	local landing = _G.ExpansionLandingPageMinimapButton
	if landing then
		landing:ClearAllPoints()
		landing:SetPoint("CENTER", Minimap, "LEFT", 4, -Minimap:GetHeight() * 0.25)
	end
end

-- The cluster is the frame Edit Mode selects and moves. Blizzard sizes it for the round map (256 x 256);
-- make it hug the square map and its header so the selection box matches what you see.
local CLUSTER_PAD = 2
function M:ApplyClusterSize()
	local cluster = MinimapCluster
	local container, zone = cluster and cluster.MinimapContainer, cluster and cluster.ZoneTextButton
	if not (container and zone) then return end
	if InCombatLockdown() and cluster:IsProtected() then return end
	local db = ns.db.map
	local scale = container:GetScale()
	if not scale or scale <= 0 then scale = 1 end
	local extent = self:GetBorderExtent()
	local mapOuter = (db.size + extent * 2) * scale
	local zoneScale = zone:GetScale() or 1
	local width = math.max(mapOuter, (zone:GetWidth() + 50) * zoneScale)
	local height = zone:GetHeight() * zoneScale + (db.headerGap or 0) + mapOuter

	-- Coordinates under the map (or under a header below the map) hang outside the frame.
	local coords = container.PlayerCoords
	if db.coordsPos == "BELOW" and coords and coords:IsShown() then
		height = height + (coords:GetHeight() + 3) * scale
	end

	self.sizingCluster = true
	cluster:SetSize(width + CLUSTER_PAD * 2, height + CLUSTER_PAD)
	self.sizingCluster = nil
end

function M:Apply()
	if not self.ready then return end
	if InCombatLockdown() and (Minimap:IsProtected() or MinimapCluster:IsProtected()) then
		ns.RunAfterCombat("map", function() self:Apply() end)
		return
	end
	self:ApplyMask()
	self:ApplyBorder()
	self:ApplySize()
	self:ApplyHeader()
	self:ApplyZoomButtons()
	self:ApplyCoords()
	self:ApplyDiel()
	self:ApplyBackdropButtons()
	if ns.layout and ns.db.layout then ns.layout:ApplyPositions() end
	self:ApplyClusterSize()
	EventRegistry:TriggerEvent("SquareMap.LayoutChanged")
end

-- Blizzard re-applies its own round setup in a few places; put ours back afterwards.
function M:Reapply()
	if self.reapplying then return end
	self.reapplying = true
	local ok, err = pcall(self.Apply, self)
	self.reapplying = nil
	if not ok then geterrorhandler()(err) end
end

function M:HookBlizzard()
	local cluster = MinimapCluster
	local function reapply() M:Reapply() end
	-- The header art is reset to its atlas size on every hover and click.
	local zone = cluster.ZoneTextButton
	if zone and zone.OnButtonStateChanged then
		hooksecurefunc(zone, "OnButtonStateChanged", function(self)
			SetHeaderTexture(self.StateTexture, ns.db.map.headerFull)
		end)
	end
	for _, method in ipairs({ "UpdateMinimapConfig", "SetHeaderUnderneath", "SetEditModeScale", "ApplyExternalEventURLButtonAnchor" }) do
		if cluster[method] then hooksecurefunc(cluster, method, reapply) end
	end

	-- The cluster is a ResizeLayoutFrame: whenever Blizzard re-lays it out, it grows back to the round size.
	if cluster.Layout then
		hooksecurefunc(cluster, "Layout", function()
			if not M.sizingCluster then M:ApplyClusterSize() end
		end)
	end

	local landing = _G.ExpansionLandingPageMinimapButton
	if landing then
		for _, method in ipairs({ "SetLandingPageIconOffset", "ResetLandingPageIconOffset", "UpdateIcon" }) do
			if landing[method] then hooksecurefunc(landing, method, reapply) end
		end
	end

	-- Zoom button visibility modes
	Minimap:HookScript("OnEnter", function()
		if ns.db.map.zoomButtons == "NEVER" then
			Minimap.ZoomIn:Hide()
			Minimap.ZoomOut:Hide()
		end
	end)
	Minimap:HookScript("OnLeave", function()
		if ns.db.map.zoomButtons == "ALWAYS" then
			Minimap.ZoomIn:Show()
			Minimap.ZoomOut:Show()
		end
	end)

	local watcher = CreateFrame("Frame")
	watcher:RegisterEvent("ADDON_LOADED")
	watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
	watcher:RegisterEvent("DISPLAY_SIZE_CHANGED")
	watcher:SetScript("OnEvent", function(_, event, name)
		if event == "ADDON_LOADED" then
			if name == "Blizzard_HybridMinimap" then
				M:ApplyHybridMask()
			end
		else
			M:Reapply()
		end
	end)

	if EventRegistry and EventRegistry.RegisterCallback then
		EventRegistry:RegisterCallback("EditMode.Enter", reapply, M)
		EventRegistry:RegisterCallback("EditMode.Exit", reapply, M)
	end
end

function M:Init()
	if not (Minimap and MinimapCluster) then return end
	self:CreateBorder()
	self:HookBlizzard()
	self.ready = true
end

-- Other addons (LibDBIcon and friends) ask this to place their buttons on the edge.
function GetMinimapShape()
	return "SQUARE"
end

---------------------------------------------------------------------------
-- Diagnostics: which Blizzard art does this client know?
---------------------------------------------------------------------------

M.ATLAS_CHECK = {
	"UI-Frame-DiamondMetal-CornerTopLeft", "_UI-Frame-DiamondMetal-EdgeTop",
	"Tooltip-NineSlice-CornerTopLeft", "_Tooltip-NineSlice-EdgeTop",
	"UI-Frame-GenericMetal-Corner", "_UI-Frame-GenericMetal-EdgeTop",
	"UI-Frame-SimpleMetal-CornerTopLeft", "_UI-Frame-SimpleMetal-EdgeTop",
	"ui-hud-minimap-zoom-in", "ui-hud-minimap-zoom-out",
	"ui-hud-minimap-addon-indicator", "ui-hud-minimap-tracking-button",
	"UI-HUD-Minimap-Frame-Cycle", "UI-HUD-Minimap-DayCycle",
}

function M:PrintAtlasReport()
	for _, name in ipairs(self.ATLAS_CHECK) do
		local info = C_Texture.GetAtlasInfo(name)
		if info then
			ns.Print(("|cff20ff20%s|r %s (%dx%d)"):format(L.ATLAS_OK, name, info.width or 0, info.height or 0))
		else
			ns.Print(("|cffff2020%s|r %s"):format(L.ATLAS_MISSING, name))
		end
	end
end
