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

-- "Rotate minimap" does not work with a square map: the game turns the terrain as a square, so the
-- corners stay empty. SquareMap keeps north up and switches the Blizzard setting back off.
function M:KeepNorthUp()
	if not (GetCVarBool and GetCVarBool("rotateMinimap")) then return end
	SetCVar("rotateMinimap", "0")
	if not self.rotateReported then
		self.rotateReported = true
		ns.Print(L.ROTATE_OFF)
	end
end

function M:ApplyMask()
	self:KeepNorthUp()
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

---------------------------------------------------------------------------
-- Header: one bar with a square field at each end and up to three text fields in between.
-- A field holds one function (tracking, calendar, day/night, addon compartment or the collector
-- button), shown as a bare icon that is part of the bar. Functions in no field are normal elements
-- with their own look that the layout editor places freely.
---------------------------------------------------------------------------

local HEADER_WIDTH = 152       -- Blizzard's header button
local HEADER_SLICE = 12        -- end caps of the header art that must not stretch
local ICON_INSET = 4           -- icon size = field size minus this on each side
local TEXT_PAD = 8             -- space between a field (or the bar end) and the text
local TEXT_GAP = 10            -- space between two text fields

M.DOCKABLE = { "tracking", "calendar", "diel", "compartment", "collector" }

local function DockFrame(key)
	local cluster = MinimapCluster
	if key == "tracking" then return cluster and cluster.Tracking end
	if key == "calendar" then return _G.GameTimeFrame end
	if key == "compartment" then return _G.AddonCompartmentFrame end
	if key == "diel" then return cluster and cluster.DielFrame end
	if key == "collector" then return ns.collector and ns.collector.button end
end
M.DockFrame = DockFrame

-- The function in the left or right field, or nil.
function M:GetField(side)
	local header = ns.db.header
	local key = side == "LEFT" and header.left or header.right
	if key == "NONE" or not key then return nil end
	-- One function can only be in one field; the left one wins.
	if side == "RIGHT" and key == header.left then return nil end
	return key
end

function M:IsDocked(key)
	return key ~= nil and (self:GetField("LEFT") == key or self:GetField("RIGHT") == key)
end

local function IsActive(key, frame)
	if key == "diel" then return ns.db.map.showDiel end
	if key == "collector" then return ns.db.collector.enabled end
	if key == "compartment" and ns.db.map.hideCompartment then return false end
	return frame:IsShown()
end

local function SetHeaderTexture(texture)
	if not texture then return end
	texture:ClearAllPoints()
	texture:SetAllPoints()
	if texture.SetTextureSliceMargins then
		texture:SetTextureSliceMargins(HEADER_SLICE, 0, HEADER_SLICE, 0)
		if texture.SetTextureSliceMode and Enum.UITextureSliceMode then
			texture:SetTextureSliceMode(Enum.UITextureSliceMode.Stretched)
		end
	end
end

-- Bare icons (no plate or frame), first one that exists in this client wins.
local function CalendarDay()
	local day = _G.GameTimeFrame and _G.GameTimeFrame.calendarDay
	if not day and C_DateAndTime and C_DateAndTime.GetCurrentCalendarTime then
		local now = C_DateAndTime.GetCurrentCalendarTime()
		day = now and now.monthDay
	end
	return day or tonumber(date("%d")) or 1
end

-- Bare icons for the fields, first one that exists in this client wins.
local function DayIcon()
	local day = C_DateAndTime and C_DateAndTime.IsDayTime and C_DateAndTime.IsDayTime()
	return day == false and "UI-HUD-Minimap-NightCycle" or "UI-HUD-Minimap-DayCycle"
end

local ICONS = {
	tracking = function() return { atlas = { "ui-hud-minimap-tracking-up", "common-search-magnifyingglass" }, file = "Interface\\Common\\UI-Searchbox-Icon" } end,
	calendar = function()
		local day = CalendarDay()
		return { atlas = { ("ui-hud-calendar-%d-up"):format(day) }, file = "Interface\\Calendar\\UI-Calendar-Button",
			coords = { 0, 0.390625, 0, 0.78125 }, day = day }
	end,
	-- Sun or moon without Blizzard's ring around it: the middle of the picture, cut round.
	diel = function() return { atlas = { DayIcon() }, crop = 0.18, round = true } end,
	collector = function()
		local C = ns.collector
		local texture = C and C.ICONS and C.ICONS[1] and C.ICONS[1].texture
		for _, info in ipairs(C and C.ICONS or {}) do
			if info.key == ns.db.collector.icon then texture = info.texture end
		end
		return { file = texture, coords = { 0.08, 0.92, 0.08, 0.92 }, round = true, inset = 1 }
	end,
}
M.FIELD_ATLASES = { "ui-hud-minimap-tracking-up", "common-search-magnifyingglass", "ui-hud-calendar-1-up" }

local function SetIcon(texture, spec)
	texture:SetTexCoord(0, 1, 0, 1)
	for _, atlas in ipairs(spec.atlas or {}) do
		local info = AtlasExists(atlas) and C_Texture.GetAtlasInfo(atlas)
		if info then
			if spec.crop and info.file and info.leftTexCoord then
				-- Part of the atlas only: from its file with the coordinates moved inwards.
				local l, r, t, b = info.leftTexCoord, info.rightTexCoord, info.topTexCoord, info.bottomTexCoord
				local cx, cy = (r - l) * spec.crop, (b - t) * spec.crop
				texture:SetTexture(info.file)
				texture:SetTexCoord(l + cx, r - cx, t + cy, b - cy)
			else
				texture:SetAtlas(atlas)
			end
			return true
		end
	end
	texture:SetTexture(spec.file)
	if spec.coords then texture:SetTexCoord(unpack(spec.coords)) end
	return false
end

-- What a function's own frame draws; hidden while it sits in a field (the frame stays for the clicks).
local function OwnArt(key, frame)
	if key == "tracking" then
		local button = frame.Button
		return { frame.Background, button and button.StateTexture, button and button.AddTexture }
	end
	if key == "calendar" or key == "compartment" then return { frame.StateTexture, frame.AddTexture } end
	if key == "collector" then return { frame.border, frame.background, frame.icon, frame.count } end
	if key == "diel" then return { frame } end
	return {}
end

local function HideArt(key, frame)
	for _, texture in pairs(OwnArt(key, frame)) do
		if texture then texture:SetAlpha(0) end
	end
end

local function ShowArt(key, frame)
	for _, texture in pairs(OwnArt(key, frame)) do
		if texture then texture:SetAlpha(1) end
	end
end

-- Blizzard puts the button art back on every hover and click; the field glows while the mouse is over
-- the function's frame.
function M:HookFieldArt()
	if self.fieldArtHooked then return end
	self.fieldArtHooked = true
	local cluster = MinimapCluster
	local function hook(key, frame, mouse)
		if not frame then return end
		if frame.OnButtonStateChanged then
			hooksecurefunc(frame, "OnButtonStateChanged", function()
				if M:IsDocked(key) then HideArt(key, DockFrame(key)) end
			end)
		end
		frame:HookScript("OnEnter", function() M:SetFieldGlow(key, true) end)
		frame:HookScript("OnLeave", function() M:SetFieldGlow(key, false) end)
	end
	hook("tracking", cluster and cluster.Tracking and cluster.Tracking.Button)
	hook("calendar", _G.GameTimeFrame)
	hook("compartment", _G.AddonCompartmentFrame)
	hook("collector", ns.collector and ns.collector.button)
end

function M:SetFieldGlow(key, on)
	for side, field in pairs(self.fields or {}) do
		if field.glow then field.glow:SetShown(on and self:GetField(side) == key) end
	end
end

-- One square field at the end of the header bar: just the icon, no frame of its own.

function M:GetFieldFrame(zone, side)
	self.fields = self.fields or {}
	local field = self.fields[side]
	if field then return field end
	field = CreateFrame("Frame", nil, zone)
	local icon = field:CreateTexture(nil, "ARTWORK")
	icon:SetPoint("CENTER")
	field.icon = icon
	local glow = field:CreateTexture(nil, "OVERLAY")
	glow:SetAllPoints(icon)
	glow:SetBlendMode("ADD")
	glow:SetAlpha(0.35)
	glow:Hide()
	field.glow = glow
	local mask = field:CreateMaskTexture()
	mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	mask:SetAllPoints(icon)
	field.mask = mask
	local day = field:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	day:SetPoint("CENTER", icon, "CENTER", 0, -1)
	field.day = day
	self.fields[side] = field
	return field
end

function M:UpdateFieldIcon(field, key, size)
	local spec = ICONS[key] and ICONS[key]()
	local icon = field.icon
	if field.masked then
		icon:RemoveMaskTexture(field.mask)
		field.glow:RemoveMaskTexture(field.mask)
		field.masked = nil
	end
	if not spec then
		icon:Hide()
		field.day:Hide()
		return
	end
	local isAtlas = SetIcon(icon, spec)
	SetIcon(field.glow, spec)
	local iconSize = size - (ICON_INSET + (spec.inset or 0)) * 2
	icon:SetSize(iconSize, iconSize)
	if spec.round then
		icon:AddMaskTexture(field.mask)
		field.glow:AddMaskTexture(field.mask)
		field.masked = true
	end
	icon:Show()
	-- The plain calendar texture has no day number; Blizzard's calendar atlases do.
	field.day:SetShown(spec.day ~= nil and not isAtlas)
	field.day:SetText(spec.day or "")
end

-- The collector button is the addon's own: in a field it moves into the header (it belongs to the map
-- otherwise), so it is on top of the header for the mouse.
local function SetCollectorParent(frame, parent)
	if frame:GetParent() ~= parent then frame:SetParent(parent) end
end

function M:PlaceField(zone, side, size)
	local field = self:GetFieldFrame(zone, side)
	field:ClearAllPoints()
	field:SetSize(size, size)
	field:SetFrameLevel(zone:GetFrameLevel() + 1)
	if side == "LEFT" then
		field:SetPoint("LEFT", zone, "LEFT", 0, 0)
	else
		field:SetPoint("RIGHT", zone, "RIGHT", 0, 0)
	end
	local key = self:GetField(side)
	local frame = key and DockFrame(key)
	local used = frame and IsActive(key, frame) and not (InCombatLockdown() and frame:IsProtected())
	field:SetShown(used and true or false)
	if not used then return 0 end

	self:UpdateFieldIcon(field, key, size)
	HideArt(key, frame)
	if key ~= "diel" then
		-- The function's own frame stays on the field, invisible, for clicks and tooltip.
		if key == "collector" then
			SetCollectorParent(frame, field)
			local h = frame:GetHeight()
			if h and h > 0 then frame:SetScale(size / h) end
		end
		frame:ClearAllPoints()
		frame:SetPoint("CENTER", field, "CENTER", 0, 0)
		frame:SetFrameLevel(field:GetFrameLevel() + 3)
	end
	return size
end

-- Functions that left a field get their own look back; without a spot from the layout editor they
-- sit next to the header, the way Blizzard's layout has them.
function M:PlaceFree(zone)
	local layout = ns.layout and ns.db.layout and ns.layout
	self.wasDocked = self.wasDocked or {}
	for _, key in ipairs(self.DOCKABLE) do
		local frame = DockFrame(key)
		local docked = self:IsDocked(key)
		if frame and not docked and self.wasDocked[key] then
			ShowArt(key, frame)
			if key == "collector" then
				SetCollectorParent(frame, Minimap)
				frame:SetScale(1)
				frame:SetAlpha(1)
				if ns.collector.UpdateButton then ns.collector:UpdateButton() end
			end
		end
		self.wasDocked[key] = docked
	end
	local function Free(key)
		local frame = DockFrame(key)
		if not frame or self:IsDocked(key) or (layout and layout:IsMoved(key)) then return nil end
		if InCombatLockdown() and frame:IsProtected() then return nil end
		return frame
	end
	local tracking = Free("tracking")
	if tracking then
		tracking:ClearAllPoints()
		tracking:SetPoint("RIGHT", zone, "LEFT", -2, 0)
	end
	local calendar = Free("calendar")
	if calendar then
		calendar:ClearAllPoints()
		calendar:SetPoint("LEFT", zone, "RIGHT", 2, 0)
	end
	local compartment = Free("compartment")
	if compartment then
		compartment:ClearAllPoints()
		if calendar and calendar:IsShown() then
			compartment:SetPoint("LEFT", calendar, "RIGHT", 0, 0)
		else
			compartment:SetPoint("LEFT", zone, "RIGHT", 2, 0)
		end
	end
end

---------------------------------------------------------------------------
-- Text fields: zone name, clock and other values
---------------------------------------------------------------------------

local function Clock(wantAMPM)
	if GetCVarBool and GetCVarBool("timeMgrUseMilitaryTime") then return false end
	return wantAMPM
end

local function Colored(value, good, bad, text)
	local r, g = 1, 1
	if value <= good then r, g = 0.3, 1 elseif value >= bad then r, g = 1, 0.3 else r, g = 1, 0.82 end
	return ("|cff%02x%02x%02x%s|r"):format(math.floor(r * 255), math.floor(g * 255), 76, text)
end

M.INFO = {
	{ key = "ZONE", label = L.INFO_ZONE },
	{ key = "CLOCK", label = L.INFO_CLOCK },
	{ key = "LOCALTIME", label = L.INFO_LOCALTIME, get = function()
		if GameTime_GetLocalTime then return GameTime_GetLocalTime(Clock(true)) end
		return date("%H:%M")
	end },
	{ key = "SERVERTIME", label = L.INFO_SERVERTIME, get = function()
		if GameTime_GetGameTime then return GameTime_GetGameTime(Clock(true)) end
		local h, m = GetGameTime()
		return ("%02d:%02d"):format(h, m)
	end },
	{ key = "MONEY", label = L.INFO_MONEY, get = function()
		local money = GetMoney()
		-- Gold only once there is some; copper and silver are noise in a header.
		if money >= 10000 then money = money - money % 10000 end
		if GetMoneyString then return GetMoneyString(money, true) end
		return tostring(math.floor(money / 10000)) .. "g"
	end },
	{ key = "PING", label = L.INFO_PING, get = function()
		local _, _, home, world = GetNetStats()
		local ms = math.max(home or 0, world or 0)
		return Colored(ms, 100, 250, L.INFO_MS:format(ms))
	end },
	{ key = "FPS", label = L.INFO_FPS, get = function()
		local fps = math.floor(GetFramerate() + 0.5)
		return Colored(-fps, -60, -25, L.INFO_FPS_VALUE:format(fps))
	end },
	{ key = "COORDS", label = L.INFO_COORDS, get = function()
		local map = C_Map.GetBestMapForUnit("player")
		local pos = map and C_Map.GetPlayerMapPosition(map, "player")
		if not pos then return "--" end
		local x, y = pos:GetXY()
		return ("%.1f, %.1f"):format(x * 100, y * 100)
	end },
	{ key = "DURABILITY", label = L.INFO_DURABILITY, get = function()
		local lowest
		for slot = 1, 18 do
			local cur, max = GetInventoryItemDurability(slot)
			if cur and max and max > 0 then lowest = math.min(lowest or 1, cur / max) end
		end
		if not lowest then return "--" end
		local pct = math.floor(lowest * 100 + 0.5)
		return Colored(-pct, -50, -20, L.INFO_DURABILITY_VALUE:format(pct))
	end },
	{ key = "BAGS", label = L.INFO_BAGS, get = function()
		local free = 0
		local bags = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
		for bag = 0, bags do
			local n = C_Container and C_Container.GetContainerNumFreeSlots(bag)
			free = free + (n or 0)
		end
		return Colored(-free, -10, -3, L.INFO_BAGS_VALUE:format(free))
	end },
	{ key = "NONE", label = L.INFO_NONE },
}
local INFO = {}
for _, info in ipairs(M.INFO) do INFO[info.key] = info end

local POSITIONS = { "LEFT", "CENTER", "RIGHT" }
local FIELD_OF = { LEFT = "infoLeft", CENTER = "infoCenter", RIGHT = "infoRight" }

function M:GetInfo(pos)
	local key = ns.db.header[FIELD_OF[pos]]
	return INFO[key] and key or "NONE"
end

-- Text area between the square fields, filled once the bar width is known.
function M:LayoutInfo()
	local zone = MinimapCluster and MinimapCluster.ZoneTextButton
	local area = self.infoArea
	if not (zone and area) then return end
	self.infoText = self.infoText or {}
	local layout = ns.layout and ns.db.layout and ns.layout
	local zoneText, clock = _G.MinimapZoneText, _G.TimeManagerClockButton
	local clockFree = clock and not (layout and layout:IsMoved("clock"))
	local used = { ZONE = false, CLOCK = false }
	local widths, regions = {}, {}
	local count = 0
	for _, pos in ipairs(POSITIONS) do
		local key = self:GetInfo(pos)
		local region, width
		if key == "ZONE" and zoneText and not used.ZONE then
			region, used.ZONE = zoneText, true
		elseif key == "CLOCK" and clockFree and not used.CLOCK then
			region, used.CLOCK = clock, true
			width = clock:IsShown() and clock:GetWidth() * clock:GetEffectiveScale() / zone:GetEffectiveScale() or 0
		elseif INFO[key] and INFO[key].get then
			local text = self.infoText[pos]
			if not text then
				text = zone:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
				text:SetWordWrap(false)
				self.infoText[pos] = text
			end
			local ok, value = pcall(INFO[key].get)
			text:SetText(ok and value or "")
			text:Show()
			region, width = text, text:GetStringWidth() + 2
		end
		if self.infoText[pos] and region ~= self.infoText[pos] then self.infoText[pos]:Hide() end
		regions[pos], widths[pos] = region, width
		if region then count = count + 1 end
	end

	-- The zone name takes what the others leave; the others keep their own width.
	local total = area.width
	local fixed = 0
	for _, pos in ipairs(POSITIONS) do
		if regions[pos] and regions[pos] ~= zoneText then fixed = fixed + (widths[pos] or 0) end
	end
	local zoneWidth = math.max(30, total - fixed - TEXT_GAP * math.max(0, count - 1))
	if regions.CENTER and regions.CENTER ~= zoneText then
		-- A centred value: the side fields get half the room each.
		zoneWidth = math.min(zoneWidth, math.max(30, total / 2 - (widths.CENTER or 0) / 2 - TEXT_GAP))
	end

	local justify = { LEFT = "LEFT", CENTER = "CENTER", RIGHT = "RIGHT" }
	for _, pos in ipairs(POSITIONS) do
		local region = regions[pos]
		if region then
			local ratio = zone:GetEffectiveScale() / region:GetEffectiveScale()
			region:ClearAllPoints()
			if pos == "LEFT" then
				region:SetPoint("LEFT", zone, "LEFT", (area.left) * ratio, -1 * ratio)
			elseif pos == "RIGHT" then
				region:SetPoint("RIGHT", zone, "RIGHT", -(area.right) * ratio, -1 * ratio)
			else
				region:SetPoint("CENTER", zone, "LEFT", (area.left + total / 2) * ratio, -1 * ratio)
			end
			if region.SetJustifyH then region:SetJustifyH(justify[pos]) end
			if region == zoneText then
				zoneText:SetWidth(zoneWidth)
			elseif region ~= clock then
				region:SetWidth(widths[pos])
			end
		end
	end
	-- Zone name and clock not picked: kept out of sight (Blizzard keeps updating them).
	if zoneText then zoneText:SetAlpha(used.ZONE and 1 or 0) end
	if clockFree then
		clock:SetAlpha(used.CLOCK and 1 or 0)
		clock:EnableMouse(used.CLOCK)
	end
	self.clockUsed = used.CLOCK or not clockFree
end

-- Values change all the time: refreshed every second while any is shown.
function M:UpdateInfoTicker()
	local needed = false
	for _, pos in ipairs(POSITIONS) do
		if INFO[self:GetInfo(pos)].get then needed = true end
	end
	if not self.infoTicker then
		local f = CreateFrame("Frame")
		local elapsed = 0
		f:SetScript("OnUpdate", function(_, dt)
			elapsed = elapsed + dt
			if elapsed < 1 then return end
			elapsed = 0
			M:LayoutInfo()
		end)
		f:SetScript("OnEvent", function() M:LayoutInfo() end)
		self.infoTicker = f
	end
	self.infoTicker:SetShown(needed)
	if needed then
		self.infoTicker:RegisterEvent("PLAYER_MONEY")
		self.infoTicker:RegisterEvent("BAG_UPDATE_DELAYED")
		self.infoTicker:RegisterEvent("UPDATE_INVENTORY_DURABILITY")
	else
		self.infoTicker:UnregisterAllEvents()
	end
end

-- Bar width, the two fields and the text fields. Returns the bar width in header units.
function M:ApplyHeaderSlots(zone, extent, scale)
	local db = ns.db.map
	local zoneScale = zone:GetScale() or 1
	local size = zone:GetHeight()
	self:HookFieldArt()
	local width
	if db.headerFull then
		width = math.max(HEADER_WIDTH, (db.size + extent * 2) * scale / zoneScale)
	else
		local left = self:GetField("LEFT") and size or 0
		local right = self:GetField("RIGHT") and size or 0
		width = HEADER_WIDTH + left + right
	end
	zone:SetWidth(width)
	local left = self:PlaceField(zone, "LEFT", size)
	local right = self:PlaceField(zone, "RIGHT", size)
	self:PlaceFree(zone)

	SetHeaderTexture(zone.StateTexture)
	SetHeaderTexture(zone.AddTexture)
	if zone.StateTexture then zone.StateTexture:SetShown(ns.db.header.background) end

	self.infoArea = { left = left + TEXT_PAD, right = right + TEXT_PAD, width = math.max(40, width - left - right - TEXT_PAD * 2) }
	self:LayoutInfo()
	self:UpdateInfoTicker()
	return width
end

-- Header above or below the square map.
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

	local compartment = _G.AddonCompartmentFrame
	if compartment then self:ApplyCompartment(compartment) end
	self:ApplyHeaderSlots(zone, extent, scale)

	container:ClearAllPoints()
	zone:ClearAllPoints()
	if db.headerPos == "BELOW" then
		container:SetPoint("TOP", cluster, "TOP", 0, (margin - extent))
		zone:SetPoint("TOP", Minimap, "BOTTOM", 0, -edge)
	else
		container:SetPoint("TOP", cluster, "TOP", 0, -(zoneHeight + gap) / scale + (margin - extent))
		zone:SetPoint("BOTTOM", Minimap, "TOP", 0, edge)
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
			local tracking = cluster.Tracking
			local left = (tracking and tracking:IsShown() and not self:IsDocked("tracking")
				and not (ns.layout and ns.layout:IsMoved("tracking"))) and tracking or zone
			indicator:SetPoint("RIGHT", left, "LEFT", -2, 0)
		end
	end
end

-- Blizzard's addon compartment lists addons that registered for it; the collector button shows the
-- actual minimap buttons. Both at once is twice the same list, so the compartment can be hidden.
function M:ApplyCompartment(compartment)
	if not self.compartmentHooked then
		self.compartmentHooked = true
		compartment:HookScript("OnShow", function(frame)
			if ns.db.map.hideCompartment then frame:Hide() end
		end)
	end
	if ns.db.map.hideCompartment then
		compartment:Hide()
	elseif self.compartmentHidden then
		-- Same rule as Blizzard's own: shown when addons have registered entries.
		local entries = compartment.registeredAddons
		compartment:SetShown(entries == nil or #entries > 0)
	end
	self.compartmentHidden = ns.db.map.hideCompartment
end

-- Blizzard shows and hides some header buttons itself (tracking at login, the compartment when an
-- addon registers, the clock); the bar is laid out again once that has happened.
function M:WatchHeaderButtons()
	local pending
	local function relayout()
		if pending then return end
		pending = true
		C_Timer.After(0, function()
			pending = nil
			M:Reapply()
		end)
	end
	for _, key in ipairs({ "tracking", "calendar", "compartment" }) do
		local frame = DockFrame(key)
		if frame then
			frame:HookScript("OnShow", relayout)
			frame:HookScript("OnHide", relayout)
		end
	end
	self.relayout = relayout
	-- Day turns to night, a new calendar day: the field icons follow.
	local watcher = CreateFrame("Frame")
	local elapsed, lastDay = 0, nil
	watcher:RegisterEvent("DIEL_CYCLE_CHANGED")
	watcher:SetScript("OnEvent", relayout)
	watcher:SetScript("OnUpdate", function(_, dt)
		elapsed = elapsed + dt
		if elapsed < 30 then return end
		elapsed = 0
		local day = CalendarDay()
		if lastDay and day ~= lastDay then relayout() end
		lastDay = day
	end)
end

function M:ApplyDiel()
	local diel = MinimapCluster and MinimapCluster.DielFrame
	if not diel then return end
	diel:SetShown(ns.db.map.showDiel)
	-- In a header field the field shows the sun or moon; Blizzard's frame (with its ring) stays hidden.
	if self:IsDocked("diel") then return end
	diel:SetAlpha(1)
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
	local width = math.max(mapOuter, (zone:GetWidth() + 4) * zoneScale)
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
	self:ApplyDiel()
	self:ApplyHeader()
	self:ApplyZoomButtons()
	self:ApplyCoords()
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
			SetHeaderTexture(self.StateTexture)
			SetHeaderTexture(self.AddTexture)
		end)
	end
	if CVarCallbackRegistry and CVarCallbackRegistry.RegisterCallback then
		CVarCallbackRegistry:RegisterCallback("rotateMinimap", function()
			C_Timer.After(0, function() M:KeepNorthUp() end)
		end, M)
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
			elseif name == "Blizzard_TimeManager" then
				-- The clock anchors itself to the header end when it loads; move it out of the right slot.
				M:Reapply()
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
	self:WatchHeaderButtons()
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
	"ui-hud-minimap-tracking-up", "common-search-magnifyingglass", "ui-hud-calendar-1-up",
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
