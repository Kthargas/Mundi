local ADDON, ns = ...
local L = ns.L

-- Layout editor: drag every button and display around the minimap (mail, tracking, calendar, clock,
-- zoom buttons, ...). Positions are stored relative to the map centre as a fraction of the map size,
-- so a layout keeps its shape when the map is resized. The editor uses Blizzard's Edit Mode art.

local E = {}
ns:RegisterModule("layout", E)

local function db() return ns.db.layout end

-- Map and header are placed by Blizzard's Edit Mode and the header options; in the editor they can be
-- selected for their settings but not dragged.
local ELEMENTS = {
	{ key = "map", label = "EL_MAP", fixed = true, level = 900, get = function() return Minimap end },
	{ key = "header", label = "EL_HEADER", fixed = true, level = 950, get = function() return MinimapCluster and MinimapCluster.ZoneTextButton end },
	{ key = "mail", label = "EL_MAIL", get = function() return MinimapCluster and MinimapCluster.IndicatorFrame end },
	{ key = "tracking", dock = true, label = "EL_TRACKING", get = function() return MinimapCluster and MinimapCluster.Tracking end },
	{ key = "calendar", dock = true, label = "EL_CALENDAR", get = function() return _G.GameTimeFrame end },
	{ key = "clock", label = "EL_CLOCK", get = function() return _G.TimeManagerClockButton end },
	{ key = "compartment", dock = true, label = "EL_COMPARTMENT", get = function() return _G.AddonCompartmentFrame end,
		off = function() return ns.db.map.hideCompartment end },
	{ key = "instance", label = "EL_INSTANCE", get = function() return MinimapCluster and MinimapCluster.InstanceDifficulty end },
	{ key = "zoomIn", label = "EL_ZOOM_IN", get = function() return Minimap and Minimap.ZoomIn end },
	{ key = "zoomOut", label = "EL_ZOOM_OUT", get = function() return Minimap and Minimap.ZoomOut end },
	{ key = "diel", dock = true, label = "EL_DIEL", get = function() return MinimapCluster and MinimapCluster.DielFrame end },
	{ key = "landing", label = "EL_LANDING", get = function() return _G.ExpansionLandingPageMinimapButton end },
	{ key = "event", label = "EL_EVENT", get = function() return MinimapBackdrop and MinimapBackdrop.ExternalEventURLButton end },
	{ key = "coords", label = "EL_COORDS", get = function() local c = MinimapCluster and MinimapCluster.MinimapContainer return c and c.PlayerCoords end },
	{ key = "collector", dock = true, label = "EL_COLLECTOR", get = function() return ns.collector and ns.collector.button end },
}
E.ELEMENTS = ELEMENTS

local byKey = {}
for _, el in ipairs(ELEMENTS) do byKey[el.key] = el end

---------------------------------------------------------------------------
-- Settings per element, shown in the editor dialog when the element is selected
---------------------------------------------------------------------------

local function Percent(value) return L.PERCENT:format(math.floor(value * 100 + 0.5)) end
local function Seconds(value)
	if value <= 0 then return L.OFF end
	return L.SECONDS:format(value)
end

local LISTS = {
	border = function()
		local list = {}
		local available = ns.map and ns.map.GetAvailableBorders and ns.map:GetAvailableBorders() or (ns.map and ns.map.BORDERS) or {}
		for _, style in ipairs(available) do list[#list + 1] = { key = style.key, label = style.label } end
		return list
	end,
	actions = function() return ns.extras and ns.extras.ACTIONS or {} end,
	headerPos = function() return { { key = "ABOVE", label = L.HEADER_ABOVE }, { key = "BELOW", label = L.HEADER_BELOW } } end,
	zoom = function()
		return { { key = "HOVER", label = L.ZOOM_HOVER }, { key = "ALWAYS", label = L.ZOOM_ALWAYS }, { key = "NEVER", label = L.ZOOM_NEVER } }
	end,
	coordsPos = function()
		return { { key = "BELOW", label = L.COORDS_BELOW }, { key = "INSIDE", label = L.COORDS_INSIDE }, { key = "TOP", label = L.COORDS_TOP } }
	end,
	icon = function()
		local list = {}
		for _, info in ipairs(ns.collector and ns.collector.ICONS or {}) do
			list[#list + 1] = { key = info.key, label = ("|T%s:16:16:0:0:64:64:5:59:5:59|t %s"):format(info.texture, info.label) }
		end
		return list
	end,
	style = function() return { { key = "PANEL", label = L.STYLE_PANEL }, { key = "COMPACT", label = L.STYLE_COMPACT } } end,
	layout = function() return { { key = "GRID", label = L.LAYOUT_GRID }, { key = "LIST", label = L.LAYOUT_LIST } } end,
	anchor = function() return { { key = "BUTTON", label = L.ANCHOR_BUTTON }, { key = "FREE", label = L.ANCHOR_FREE } } end,
	place = function()
		return { { key = "NONE", label = L.SLOT_FREE }, { key = "LEFT", label = L.SLOT_LEFT }, { key = "RIGHT", label = L.SLOT_RIGHT } }
	end,
	field = function()
		local list = { { key = "NONE", label = L.FIELD_EMPTY } }
		for _, key in ipairs(ns.map and ns.map.DOCKABLE or {}) do
			list[#list + 1] = { key = key, label = L["EL_" .. key:upper()] }
		end
		return list
	end,
	info = function()
		local list = {}
		for _, info in ipairs(ns.map and ns.map.INFO or {}) do list[#list + 1] = { key = info.key, label = info.label } end
		return list
	end,
}

local function Check(section, field, label) return { kind = "check", section = section, field = field, label = label } end
local function Slider(section, field, label, minValue, maxValue, step, format)
	return { kind = "slider", section = section, field = field, label = label, min = minValue, max = maxValue, step = step, format = format }
end
local function Choice(section, field, label, list) return { kind = "dropdown", section = section, field = field, label = label, list = LISTS[list] } end
local function CVar(cvar, label) return { kind = "cvar", cvar = cvar, label = label } end
-- Square field at either end of the header: which function sits there.
local function Field(side, label)
	local field = side == "LEFT" and "left" or "right"
	return { kind = "dropdown", section = "header", field = field, label = label, list = LISTS.field,
		set = function(value) E:SetField(side, value) end }
end
-- For a function that is not in the header: put it into a field.
local function Place(key)
	return { kind = "dropdown", label = "HEADER_SLOT", list = LISTS.place,
		get = function()
			if ns.db.header.left == key then return "LEFT" end
			if ns.db.header.right == key then return "RIGHT" end
			return "NONE"
		end,
		set = function(side)
			if side ~= "NONE" then E:SetField(side, key) end
		end }
end

local SETTINGS = {
	map = {
		Slider("map", "size", "SIZE", 140, 400, 2),
		Choice("map", "border", "BORDER", "border"),
		Slider("map", "borderScale", "BORDER_SCALE", 0.4, 1.6, 0.05, Percent),
		Slider("map", "borderOffset", "BORDER_OFFSET", -10, 20, 1),
		CVar("rotateMinimap", "ROTATE"),
		Slider("map", "autoZoom", "AUTOZOOM", 0, 60, 1, Seconds),
		Slider("map", "combatAlpha", "COMBAT_ALPHA", 0.1, 1, 0.05, Percent),
		Check("map", "compass", "COMPASS"),
		Choice("map", "rightClick", "RIGHT_CLICK", "actions"),
		Choice("map", "middleClick", "MIDDLE_CLICK", "actions"),
	},
	header = {
		Choice("map", "headerPos", "HEADER_POS", "headerPos"),
		Slider("map", "headerGap", "HEADER_GAP", -10, 20, 1),
		Check("map", "headerFull", "HEADER_FULL"),
		Check("map", "headerFade", "HEADER_FADE"),
		Check("header", "background", "HEADER_BG"),
		Field("LEFT", "FIELD_LEFT"),
		Field("RIGHT", "FIELD_RIGHT"),
		Choice("header", "infoLeft", "INFO_LEFT", "info"),
		Choice("header", "infoCenter", "INFO_CENTER", "info"),
		Choice("header", "infoRight", "INFO_RIGHT", "info"),
		Check("map", "hideCompartment", "HIDE_COMPARTMENT"),
	},
	tracking = { Place("tracking") },
	calendar = { Place("calendar") },
	coords = {
		CVar("minimapShowPlayerCoords", "COORDS"),
		Choice("map", "coordsPos", "COORDS_POS", "coordsPos"),
	},
	zoomIn = { Choice("map", "zoomButtons", "ZOOM_BUTTONS", "zoom") },
	zoomOut = { Choice("map", "zoomButtons", "ZOOM_BUTTONS", "zoom") },
	diel = { Check("map", "showDiel", "SHOW_DIEL"), Place("diel") },
	instance = { Check("map", "showInstance", "SHOW_INSTANCE") },
	compartment = { Check("map", "hideCompartment", "HIDE_COMPARTMENT"), Place("compartment") },
	collector = {
		Check("collector", "enabled", "COLLECTOR_ENABLE"),
		Place("collector"),
		Choice("collector", "icon", "COLLECTOR_ICON", "icon"),
		Check("collector", "showCount", "SHOW_COUNT"),
		Choice("collector", "style", "WINDOW_STYLE", "style"),
		Choice("collector", "layout", "LAYOUT", "layout"),
		Slider("collector", "columns", "COLUMNS", 1, 12, 1),
		Slider("collector", "scale", "BUTTON_SCALE", 0.6, 1.6, 0.05, Percent),
		Slider("collector", "spacing", "SPACING", 0, 16, 1),
		Choice("collector", "anchor", "WINDOW_ANCHOR", "anchor"),
		Check("collector", "closeOnClick", "CLOSE_ON_CLICK"),
		Slider("collector", "autoHide", "AUTO_HIDE", 0, 10, 1, Seconds),
	},
}
E.SETTINGS = SETTINGS

local function GetSetting(spec)
	if spec.get then return spec.get() end
	if spec.kind == "cvar" then return GetCVarBool(spec.cvar) end
	return ns.db[spec.section][spec.field]
end

function E:SetSetting(spec, value)
	if spec.set then
		spec.set(value)
	elseif spec.kind == "cvar" then
		SetCVar(spec.cvar, value and "1" or "0")
	else
		ns.db[spec.section][spec.field] = value
	end
	ns:ApplyAll()
	if ns.options and ns.options.Refresh then ns.options:Refresh() end
	if self.active then self:UpdateDialog() end
end

-- The anchors a frame had before SquareMap first moved it, to put it back on reset.
local original = {}

local function SavePoints(key, frame)
	if original[key] then return end
	local points = {}
	for i = 1, frame:GetNumPoints() do
		points[i] = { frame:GetPoint(i) }
	end
	original[key] = points
end

local function CanMove(frame)
	return frame and not (InCombatLockdown() and frame:IsProtected())
end

function E:IsMoved(key)
	return db().positions[key] ~= nil
end

-- Puts one element at its saved position. Returns true when it has one.
function E:Place(key)
	local pos = db().positions[key]
	local el = byKey[key]
	if el and el.fixed then return false end
	-- In a header slot the map module places it.
	if el and el.dock and ns.map and ns.map:IsDocked(key) then return true end
	local frame = el and el.get()
	if not (pos and CanMove(frame)) then return pos ~= nil end
	SavePoints(key, frame)
	local mes, fes = Minimap:GetEffectiveScale(), frame:GetEffectiveScale()
	if not fes or fes <= 0 then fes = mes end
	local dx, dy = pos.x * Minimap:GetWidth(), pos.y * Minimap:GetHeight()
	frame:ClearAllPoints()
	frame:SetPoint("CENTER", Minimap, "CENTER", dx * mes / fes, dy * mes / fes)
	return true
end

-- Size and layer. Blizzard sets the scale and frame level of some elements itself (day/night is
-- counter-scaled, zoom buttons get a level above the border); when it does, that becomes the new base.
local base = { scale = {}, level = {} }
local applied = { scale = {}, level = {} }

local function Track(kind, key, current)
	if base[kind][key] == nil or (applied[kind][key] and math.abs(current - applied[kind][key]) > 0.001) then
		base[kind][key] = current
	end
	return base[kind][key]
end

local MIN_SCALE, MAX_SCALE = 0.5, 2
local MIN_LAYER, MAX_LAYER = -10, 10

function E:GetScale(key) return db().scales[key] or 1 end
function E:GetLayer(key) return db().layers[key] or 0 end

function E:ApplyStyle(key)
	local el = byKey[key]
	local frame = el and el.get()
	if el and el.fixed then return end
	if not CanMove(frame) then return end
	local scale, layer = db().scales[key], db().layers[key]
	if scale or base.scale[key] then
		local target = Track("scale", key, frame:GetScale()) * (scale or 1)
		frame:SetScale(target)
		applied.scale[key] = target
		if not scale then base.scale[key], applied.scale[key] = nil, nil end
	end
	if layer or base.level[key] then
		local target = math.max(0, Track("level", key, frame:GetFrameLevel()) + (layer or 0))
		frame:SetFrameLevel(target)
		applied.level[key] = target
		if not layer then base.level[key], applied.level[key] = nil, nil end
	end
end

function E:SetScale(key, value)
	value = math.max(MIN_SCALE, math.min(MAX_SCALE, math.floor(value * 20 + 0.5) / 20))
	db().scales[key] = math.abs(value - 1) > 0.001 and value or nil
	self:ApplyStyle(key)
	self:Place(key)
	self:Refresh(key)
end

function E:SetLayer(key, value)
	value = math.max(MIN_LAYER, math.min(MAX_LAYER, math.floor(value + 0.5)))
	db().layers[key] = value ~= 0 and value or nil
	self:ApplyStyle(key)
	if self.active then self:UpdateDialog() end
end

-- Called by the map module after it has placed everything in its default spot.
function E:ApplyPositions()
	for _, el in ipairs(ELEMENTS) do
		self:ApplyStyle(el.key)
		if db().positions[el.key] then self:Place(el.key) end
	end
	if self.active then self:UpdateOverlays() end
end

function E:Clear(key)
	db().positions[key] = nil
	local el = byKey[key]
	local frame = el and el.get()
	local points = original[key]
	if points and CanMove(frame) then
		frame:ClearAllPoints()
		for _, p in ipairs(points) do frame:SetPoint(unpack(p)) end
	end
	original[key] = nil
	self:Refresh(key)
end

-- Puts a function into the left or right header field ("NONE" empties it). In a field it is part of
-- the header: its spot, size and layer from the editor are dropped.
function E:SetField(side, key)
	local header = ns.db.header
	local own, other = side == "LEFT" and "left" or "right", side == "LEFT" and "right" or "left"
	header[own] = key
	if key ~= "NONE" then
		if header[other] == key then header[other] = "NONE" end
		db().positions[key], db().scales[key], db().layers[key] = nil, nil, nil
		original[key] = nil
	end
end

-- Position, size and layer back to Blizzard's.
function E:ResetElement(key)
	local el = byKey[key]
	if el and el.fixed then
		-- Map and header cannot move; right click puts their settings back instead.
		for _, spec in ipairs(SETTINGS[key] or {}) do
			if spec.section then ns.db[spec.section][spec.field] = ns.DEFAULTS[spec.section][spec.field] end
		end
		if key == "header" then
			-- The default functions go back into their fields.
			self:SetField("LEFT", ns.db.header.left)
			self:SetField("RIGHT", ns.db.header.right)
		end
		ns:ApplyAll()
		if ns.options and ns.options.Refresh then ns.options:Refresh() end
		if self.active then self:UpdateOverlays() self:UpdateDialog() end
		return
	end
	db().scales[key], db().layers[key] = nil, nil
	self:ApplyStyle(key)
	self:Clear(key)
end

function E:ResetAll()
	for _, el in ipairs(ELEMENTS) do
		local key = el.key
		if not el.fixed and (db().positions[key] or db().scales[key] or db().layers[key]) then
			self:ResetElement(key)
		end
	end
end

-- Let the other modules put their elements back (header width, collector button, ...).
function E:Refresh(key)
	if ns.map and ns.map.Reapply then ns.map:Reapply() end
	if key == "collector" and ns.collector and ns.collector.UpdateButton then ns.collector:UpdateButton() end
	if self.active then self:UpdateOverlays() self:UpdateDialog() end
end

-- Offset of the element's centre from the map centre, in map units.
local function CenterOffset(frame)
	local fx, fy = frame:GetCenter()
	local mx, my = Minimap:GetCenter()
	if not (fx and mx) then return 0, 0 end
	local fes, mes = frame:GetEffectiveScale(), Minimap:GetEffectiveScale()
	return (fx * fes - mx * mes) / mes, (fy * fes - my * mes) / mes
end

local SNAP_GRID = 4
local SNAP_LINE = 6

local function Snap(value, halfSize)
	if not db().snap then return math.floor(value + 0.5) end
	-- Centre line and map edges pull the element in, otherwise a 4 px grid.
	for _, line in ipairs({ 0, -halfSize, halfSize }) do
		if math.abs(value - line) <= SNAP_LINE then return line end
	end
	return math.floor(value / SNAP_GRID + 0.5) * SNAP_GRID
end

---------------------------------------------------------------------------
-- Editor
---------------------------------------------------------------------------

-- Same nine-slice layout Blizzard's Edit Mode uses for its selection boxes.
local SELECTION_LAYOUT = {
	["TopRightCorner"] = { atlas = "%s-NineSlice-Corner", mirrorLayout = true, x = 8, y = 8 },
	["TopLeftCorner"] = { atlas = "%s-NineSlice-Corner", mirrorLayout = true, x = -8, y = 8 },
	["BottomLeftCorner"] = { atlas = "%s-NineSlice-Corner", mirrorLayout = true, x = -8, y = -8 },
	["BottomRightCorner"] = { atlas = "%s-NineSlice-Corner", mirrorLayout = true, x = 8, y = -8 },
	["TopEdge"] = { atlas = "_%s-NineSlice-EdgeTop" },
	["BottomEdge"] = { atlas = "_%s-NineSlice-EdgeBottom" },
	["LeftEdge"] = { atlas = "!%s-NineSlice-EdgeLeft" },
	["RightEdge"] = { atlas = "!%s-NineSlice-EdgeRight" },
	["Center"] = { atlas = "%s-NineSlice-Center", x = -8, y = 8, x1 = 8, y1 = -8 },
}
local HIGHLIGHT_KIT, SELECTED_KIT = "editmode-actionbar-highlight", "editmode-actionbar-selected"
local MIN_BOX = 20

local function SetKit(box, kit)
	if box.kit == kit then return end
	box.kit = kit
	if NineSliceUtil and NineSliceUtil.ApplyLayout then
		NineSliceUtil.ApplyLayout(box, SELECTION_LAYOUT, kit)
	end
end

local function ShowTooltip(box)
	GameTooltip:SetOwner(box, "ANCHOR_RIGHT")
	GameTooltip_SetTitle(GameTooltip, L[box.element.label])
	local frame = box.element.get()
	if frame and not frame:IsShown() then
		GameTooltip:AddLine(L.LAYOUT_HIDDEN, 0.8, 0.8, 0.8, true)
	end
	GameTooltip:AddLine(L.LAYOUT_TT_SELECT, 1, 1, 1, true)
	if box.element.fixed then
		GameTooltip:AddLine(L.LAYOUT_TT_FIXED, 0.8, 0.8, 0.8, true)
		GameTooltip:AddLine(L.LAYOUT_TT_RESET_SETTINGS, 1, 1, 1, true)
	else
		GameTooltip:AddLine(L.LAYOUT_TT_DRAG, 1, 1, 1, true)
		GameTooltip:AddLine(L.LAYOUT_TT_WHEEL, 1, 1, 1, true)
		GameTooltip:AddLine(L.LAYOUT_TT_LAYER, 1, 1, 1, true)
		GameTooltip:AddLine(L.LAYOUT_TT_RESET, 1, 1, 1, true)
	end
	GameTooltip:Show()
end

function E:CreateBox(el)
	local box = CreateFrame("Frame", nil, UIParent)
	box:SetFrameStrata("HIGH")
	box:SetFrameLevel(el.level or 1000)
	box:EnableMouse(true)
	box.element = el
	SetKit(box, HIGHLIGHT_KIT)

	local label = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	label:SetPoint("CENTER")
	label:SetText(L[el.label])
	label:Hide()
	box.label = label

	box:SetScript("OnEnter", ShowTooltip)
	box:SetScript("OnLeave", GameTooltip_Hide)
	box:SetScript("OnMouseDown", function(self, button)
		if button == "RightButton" then
			E:ResetElement(el.key)
			E:Select(self)
			ShowTooltip(self)
			return
		end
		if button ~= "LeftButton" then return end
		E:StartDrag(self)
	end)
	box:SetScript("OnMouseUp", function(self, button)
		if button == "LeftButton" then E:StopDrag(self) end
	end)
	-- Mouse wheel: size; with Shift: layer.
	box:EnableMouseWheel(true)
	box:SetScript("OnMouseWheel", function(self, delta)
		E:Select(self)
		if el.fixed then return end
		if IsShiftKeyDown() then
			E:SetLayer(el.key, E:GetLayer(el.key) + delta)
		else
			E:SetScale(el.key, E:GetScale(el.key) + delta * 0.05)
		end
	end)
	return box
end

local DRAG_START = 4

function E:StartDrag(box)
	local el = box.element
	local frame = el.get()
	self:Select(box)
	if el.fixed or not CanMove(frame) then return end
	GameTooltip:Hide()
	local startX, startY = CenterOffset(frame)
	local scale = Minimap:GetEffectiveScale()
	local cx, cy = GetCursorPosition()
	local halfW, halfH = Minimap:GetWidth() / 2, Minimap:GetHeight() / 2
	box.moved = nil
	box:SetScript("OnUpdate", function()
		local x, y = GetCursorPosition()
		-- A click selects; only a real drag moves (and takes a button out of the header).
		if not box.moved then
			if math.abs(x - cx) + math.abs(y - cy) < DRAG_START then return end
			box.moved = true
		end
		local dx = startX + (x - cx) / scale
		local dy = startY + (y - cy) / scale
		-- Keep elements on or near the map.
		dx = math.max(-halfW - 80, math.min(halfW + 80, Snap(dx, halfW)))
		dy = math.max(-halfH - 80, math.min(halfH + 80, Snap(dy, halfH)))
		db().positions[el.key] = { x = dx / Minimap:GetWidth(), y = dy / Minimap:GetHeight() }
		E:Place(el.key)
	end)
end

function E:StopDrag(box)
	if not box:GetScript("OnUpdate") then return end
	box:SetScript("OnUpdate", nil)
	box.moved = nil
	self:Refresh(box.element.key)
end

function E:Select(box)
	for _, other in pairs(self.boxes or {}) do
		SetKit(other, other == box and SELECTED_KIT or HIGHLIGHT_KIT)
	end
	self.selected = box
	self:UpdateDialog()
end

function E:UpdateOverlays()
	local uiScale = UIParent:GetEffectiveScale()
	for _, el in ipairs(ELEMENTS) do
		local box = self.boxes[el.key]
		local frame = el.get()
		if frame and el.off and el.off() then frame = nil end
		-- In a header field it is part of the header (select the header for it).
		if frame and el.dock and ns.map and ns.map:IsDocked(el.key) then frame = nil end
		if frame then
			box = box or self:CreateBox(el)
			self.boxes[el.key] = box
			local fes = frame:GetEffectiveScale() / uiScale
			local w = math.max(MIN_BOX, (frame:GetWidth() or 0) * fes)
			local h = math.max(MIN_BOX, (frame:GetHeight() or 0) * fes)
			box:ClearAllPoints()
			if frame:GetCenter() then
				box:SetPoint("CENTER", frame, "CENTER")
			else
				box:SetPoint("CENTER", Minimap, "CENTER")
			end
			box:SetSize(w, h)
			-- Hidden elements (no mail right now, no instance, ...) still get a box to place them.
			box.label:SetShown(not frame:IsShown() and not el.fixed)
			box:SetAlpha(frame:IsShown() and 1 or 0.7)
			box:Show()
		elseif box then
			box:Hide()
		end
	end
end

local function CreateSlider(parent, minValue, maxValue, steps, format, onChange)
	local slider = CreateFrame("Frame", nil, parent, "MinimalSliderWithSteppersTemplate")
	slider:SetSize(190, 20)
	local labels = MinimalSliderWithSteppersMixin and MinimalSliderWithSteppersMixin.Label
	local formatters = labels and CreateMinimalSliderFormatter and { [labels.Right] = CreateMinimalSliderFormatter(labels.Right, format) }
	function slider:SetSQMValue(value)
		self.updating = true
		self:Init(value, minValue, maxValue, steps, formatters)
		self.updating = nil
	end
	slider:SetSQMValue(minValue)
	slider:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, value)
		if not slider.updating then onChange(value) end
	end, slider)
	return slider
end

local ROW = 32
local LABEL_X, CONTROL_X = 22, -26
local PANEL_TOP = -128

local function Row(parent, text, y)
	local label = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	label:SetPoint("TOPLEFT", LABEL_X, y - 4)
	label:SetWidth(140)
	label:SetJustifyH("LEFT")
	label:SetText(text)
	return label
end

local function CreateCheck(parent, onClick)
	local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	check:SetSize(26, 26)
	check:SetScript("OnClick", function(self) onClick(self:GetChecked() and true or false) end)
	return check
end

local function CreateDropdown(parent, list, get, set)
	local dropdown = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
	dropdown:SetWidth(190)
	if dropdown.SetupMenu then
		dropdown:SetupMenu(function(_, root)
			for _, item in ipairs(list()) do
				root:CreateRadio(item.label, function() return get() == item.key end, function() set(item.key) end, item.key)
			end
		end)
	end
	return dropdown
end

-- One panel per element: size and layer (movable elements), then the element's own settings.
function E:CreatePanel(el)
	local panel = CreateFrame("Frame", nil, self.dialog)
	panel:SetPoint("TOPLEFT", self.dialog, "TOPLEFT", 0, PANEL_TOP)
	panel:SetPoint("RIGHT", self.dialog, "RIGHT")
	panel.refresh = {}
	panel.widgets = {}
	local y = 0
	local key = el.key

	local function Add(label, widget, refresh, inset)
		Row(panel, label, y)
		widget:SetPoint("TOPRIGHT", panel, "TOPRIGHT", CONTROL_X - (inset or 0), y)
		panel.refresh[#panel.refresh + 1] = refresh
		y = y - ROW
	end

	if not el.fixed then
		local scale = CreateSlider(panel, MIN_SCALE * 100, MAX_SCALE * 100, 30, function(value) return ("%d%%"):format(value) end,
			function(value) E:SetScale(key, value / 100) end)
		Add(L.LAYOUT_SCALE, scale, function() scale:SetSQMValue(E:GetScale(key) * 100) end, 14)
		local layer = CreateSlider(panel, MIN_LAYER, MAX_LAYER, MAX_LAYER - MIN_LAYER, function(value) return ("%+d"):format(value) end,
			function(value) E:SetLayer(key, value) end)
		Add(L.LAYOUT_LAYER, layer, function() layer:SetSQMValue(E:GetLayer(key)) end, 14)
		panel.scale, panel.layer = scale, layer
	end

	for _, spec in ipairs(SETTINGS[key] or {}) do
		local widget, refresh, inset
		local function set(value) E:SetSetting(spec, value) end
		if spec.kind == "check" or spec.kind == "cvar" then
			widget = CreateCheck(panel, set)
			refresh = function() widget:SetChecked(GetSetting(spec) and true or false) end
			inset = -2
		elseif spec.kind == "slider" then
			local steps = math.max(1, math.floor((spec.max - spec.min) / spec.step + 0.5))
			widget = CreateSlider(panel, spec.min, spec.max, steps, spec.format or function(value)
				return tostring(math.floor(value + 0.5))
			end, set)
			refresh = function() widget:SetSQMValue(GetSetting(spec) or spec.min) end
			inset = 14
		else
			widget = CreateDropdown(panel, spec.list, function() return GetSetting(spec) end, set)
			refresh = function() if widget.GenerateMenu then widget:GenerateMenu() end end
		end
		widget.spec = spec
		panel.widgets[#panel.widgets + 1] = widget
		Add(L[spec.label] or spec.label, widget, refresh, inset)
	end
	panel.height = -y
	panel:SetHeight(math.max(1, -y))
	return panel
end

function E:CreateDialog()
	local f = CreateFrame("Frame", "SquareMapLayoutDialog", UIParent)
	f:SetSize(380, 300)
	f:SetFrameStrata("DIALOG")
	f:SetFrameLevel(200)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:SetClampedToScreen(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:SetPoint("TOPRIGHT", MinimapCluster, "TOPLEFT", -20, 0)
	local border = CreateFrame("Frame", nil, f, "DialogBorderTemplate")
	border:SetAllPoints()

	local title = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
	title:SetPoint("TOP", 0, -18)
	title:SetText(L.LAYOUT_TITLE)

	local hint = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	hint:SetPoint("TOPLEFT", 20, -44)
	hint:SetPoint("TOPRIGHT", -20, -44)
	hint:SetJustifyH("LEFT")
	hint:SetText(L.LAYOUT_HINT)

	-- The selected element's name; its panel follows below.
	local selected = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightMedium")
	selected:SetPoint("TOPLEFT", 22, -104)
	selected:SetPoint("TOPRIGHT", -22, -104)
	selected:SetJustifyH("LEFT")
	f.selected = selected

	local snap = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
	snap:SetSize(26, 26)
	local snapText = snap.Text or snap:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	snapText:ClearAllPoints()
	snapText:SetPoint("LEFT", snap, "RIGHT", 2, 1)
	snapText:SetFontObject("GameFontHighlight")
	snapText:SetText(L.LAYOUT_SNAP)
	snap:SetScript("OnShow", function(self) self:SetChecked(db().snap) end)
	snap:SetScript("OnClick", function(self) db().snap = self:GetChecked() and true or false end)
	f.snap = snap

	local resetOne = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	resetOne:SetSize(336, 22)
	resetOne:SetText(L.LAYOUT_RESET_ONE)
	resetOne:SetScript("OnClick", function() if E.selected then E:ResetElement(E.selected.element.key) end end)
	f.resetOne = resetOne

	local reset = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	reset:SetSize(160, 22)
	reset:SetPoint("BOTTOMLEFT", 22, 20)
	reset:SetText(L.LAYOUT_RESET)
	reset:SetScript("OnClick", function() E:ResetAll() end)

	local done = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	done:SetSize(160, 22)
	done:SetPoint("BOTTOMRIGHT", -22, 20)
	done:SetText(L.LAYOUT_DONE)
	done:SetScript("OnClick", function() E:Stop() end)

	-- New frames start shown: hide first, then hook OnHide. The other way round, this Hide ran Stop
	-- on the editor that was just starting, so the first open of a session did nothing.
	f:Hide()
	f:SetScript("OnHide", function() if E.active then E:Stop() end end)
	tinsert(UISpecialFrames, "SquareMapLayoutDialog")
	self.dialog = f
	self.panels = {}
	return f
end

function E:UpdateDialog()
	local f = self.dialog
	if not f then return end
	local box = self.selected
	-- An element that just went into a header field has no box any more: show the header instead.
	local header = self.boxes and self.boxes.header
	if box and not box:IsShown() and header and header:IsShown() and box ~= header then
		self:Select(header)
		return
	end
	local el = box and box.element
	f.selected:SetText(el and L[el.label] or L.LAYOUT_NONE)

	local panel
	for key, other in pairs(self.panels) do
		if not el or key ~= el.key then other:Hide() end
	end
	if el then
		panel = self.panels[el.key] or self:CreatePanel(el)
		self.panels[el.key] = panel
		panel:Show()
		for _, refresh in ipairs(panel.refresh) do refresh() end
	end

	-- Snap and reset sit under the panel; the dialog grows with it.
	local y = PANEL_TOP - (panel and panel.height or 0) - 6
	f.snap:ClearAllPoints()
	f.snap:SetPoint("TOPLEFT", f, "TOPLEFT", 16, y)
	f.resetOne:ClearAllPoints()
	f.resetOne:SetPoint("TOP", f, "TOP", 0, y - 34)
	f.resetOne:SetText(el and el.fixed and L.LAYOUT_RESET_SETTINGS or L.LAYOUT_RESET_ONE)
	if f.resetOne.SetEnabled then f.resetOne:SetEnabled(el ~= nil) end
	f:SetHeight(-(y - 34) + 22 + 56)
end

function E:Start()
	if self.active then return end
	if InCombatLockdown() then
		UIErrorsFrame:AddMessage(ERR_NOT_IN_COMBAT or L.NOT_IN_COMBAT, 1, 0.1, 0.1)
		return
	end
	local dialog = self.dialog or self:CreateDialog()
	self.active = true
	self.boxes = self.boxes or {}
	self:UpdateOverlays()
	dialog:Show()
	self:UpdateDialog()
	self.events = self.events or CreateFrame("Frame")
	self.events:RegisterEvent("PLAYER_REGEN_DISABLED")
	self.events:SetScript("OnEvent", function() E:Stop() end)
end

function E:Stop()
	if not self.active then return end
	self.active = nil
	for _, box in pairs(self.boxes) do
		box:SetScript("OnUpdate", nil)
		box:Hide()
	end
	self.selected = nil
	if self.events then self.events:UnregisterEvent("PLAYER_REGEN_DISABLED") end
	if self.dialog and self.dialog:IsShown() then self.dialog:Hide() end
	GameTooltip:Hide()
end

function E:Toggle()
	if self.active then self:Stop() else self:Start() end
end

function E:Init()
	self.ready = true
end

function E:Apply()
	self:ApplyPositions()
end
