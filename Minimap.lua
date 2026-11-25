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
	else
		coords:SetPoint("TOP", Minimap, "BOTTOM", 0, -(math.ceil(self:GetBorderExtent()) + 3))
	end
	coords:SetFrameLevel((self.border and self.border:GetFrameLevel() or Minimap:GetFrameLevel()) + 4)
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

function M:Apply()
	if not self.ready then return end
	if InCombatLockdown() and (Minimap:IsProtected() or MinimapCluster:IsProtected()) then
		ns.RunAfterCombat("map", function() self:Apply() end)
		return
	end
	self:ApplyMask()
	self:ApplyBorder()
	self:ApplySize()
	self:ApplyZoomButtons()
	self:ApplyCoords()
	self:ApplyDiel()
	self:ApplyBackdropButtons()
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
	for _, method in ipairs({ "UpdateMinimapConfig", "SetHeaderUnderneath", "SetEditModeScale", "ApplyExternalEventURLButtonAnchor" }) do
		if cluster[method] then hooksecurefunc(cluster, method, reapply) end
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
