local ADDON, ns = ...
local L = ns.L

-- Layout editor: drag every button and display around the minimap (mail, tracking, calendar, clock,
-- zoom buttons, ...). Positions are stored relative to the map centre as a fraction of the map size,
-- so a layout keeps its shape when the map is resized. The editor uses Blizzard's Edit Mode art.

local E = {}
ns:RegisterModule("layout", E)

local function db() return ns.db.layout end

local ELEMENTS = {
	{ key = "mail", label = "EL_MAIL", get = function() return MinimapCluster and MinimapCluster.IndicatorFrame end },
	{ key = "tracking", label = "EL_TRACKING", get = function() return MinimapCluster and MinimapCluster.Tracking end },
	{ key = "calendar", label = "EL_CALENDAR", get = function() return _G.GameTimeFrame end },
	{ key = "clock", label = "EL_CLOCK", get = function() return _G.TimeManagerClockButton end },
	{ key = "compartment", label = "EL_COMPARTMENT", get = function() return _G.AddonCompartmentFrame end,
		off = function() return ns.db.map.hideCompartment end },
	{ key = "instance", label = "EL_INSTANCE", get = function() return MinimapCluster and MinimapCluster.InstanceDifficulty end },
	{ key = "zoomIn", label = "EL_ZOOM_IN", get = function() return Minimap and Minimap.ZoomIn end },
	{ key = "zoomOut", label = "EL_ZOOM_OUT", get = function() return Minimap and Minimap.ZoomOut end },
	{ key = "diel", label = "EL_DIEL", get = function() return MinimapCluster and MinimapCluster.DielFrame end },
	{ key = "landing", label = "EL_LANDING", get = function() return _G.ExpansionLandingPageMinimapButton end },
	{ key = "event", label = "EL_EVENT", get = function() return MinimapBackdrop and MinimapBackdrop.ExternalEventURLButton end },
	{ key = "coords", label = "EL_COORDS", get = function() local c = MinimapCluster and MinimapCluster.MinimapContainer return c and c.PlayerCoords end },
	{ key = "collector", label = "EL_COLLECTOR", get = function() return ns.collector and ns.collector.button end },
}
E.ELEMENTS = ELEMENTS

local byKey = {}
for _, el in ipairs(ELEMENTS) do byKey[el.key] = el end

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

-- Position, size and layer back to Blizzard's.
function E:ResetElement(key)
	db().scales[key], db().layers[key] = nil, nil
	self:ApplyStyle(key)
	self:Clear(key)
end

function E:ResetAll()
	for _, el in ipairs(ELEMENTS) do
		local key = el.key
		if db().positions[key] or db().scales[key] or db().layers[key] then self:ResetElement(key) end
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
	GameTooltip:AddLine(L.LAYOUT_TT_DRAG, 1, 1, 1, true)
	GameTooltip:AddLine(L.LAYOUT_TT_WHEEL, 1, 1, 1, true)
	GameTooltip:AddLine(L.LAYOUT_TT_LAYER, 1, 1, 1, true)
	GameTooltip:AddLine(L.LAYOUT_TT_RESET, 1, 1, 1, true)
	GameTooltip:Show()
end

function E:CreateBox(el)
	local box = CreateFrame("Frame", nil, UIParent)
	box:SetFrameStrata("HIGH")
	box:SetFrameLevel(1000)
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
		if IsShiftKeyDown() then
			E:SetLayer(el.key, E:GetLayer(el.key) + delta)
		else
			E:SetScale(el.key, E:GetScale(el.key) + delta * 0.05)
		end
	end)
	return box
end

function E:StartDrag(box)
	local frame = box.element.get()
	if not CanMove(frame) then return end
	self:Select(box)
	GameTooltip:Hide()
	local startX, startY = CenterOffset(frame)
	local scale = Minimap:GetEffectiveScale()
	local cx, cy = GetCursorPosition()
	local halfW, halfH = Minimap:GetWidth() / 2, Minimap:GetHeight() / 2
	box:SetScript("OnUpdate", function()
		local x, y = GetCursorPosition()
		local dx = startX + (x - cx) / scale
		local dy = startY + (y - cy) / scale
		-- Keep elements on or near the map.
		dx = math.max(-halfW - 80, math.min(halfW + 80, Snap(dx, halfW)))
		dy = math.max(-halfH - 80, math.min(halfH + 80, Snap(dy, halfH)))
		db().positions[box.element.key] = { x = dx / Minimap:GetWidth(), y = dy / Minimap:GetHeight() }
		E:Place(box.element.key)
	end)
end

function E:StopDrag(box)
	if not box:GetScript("OnUpdate") then return end
	box:SetScript("OnUpdate", nil)
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
			box.label:SetShown(not frame:IsShown())
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

local function Row(parent, text, y)
	local label = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	label:SetPoint("TOPLEFT", 22, y)
	label:SetText(text)
	return label
end

function E:CreateDialog()
	local f = CreateFrame("Frame", "SquareMapLayoutDialog", UIParent)
	f:SetSize(340, 286)
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

	-- The selected element: its name, size and layer.
	local selected = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	selected:SetPoint("TOPLEFT", 22, -100)
	selected:SetPoint("TOPRIGHT", -22, -100)
	selected:SetJustifyH("LEFT")
	f.selected = selected

	Row(f, L.LAYOUT_SCALE, -128)
	f.scale = CreateSlider(f, MIN_SCALE * 100, MAX_SCALE * 100, 30, function(value) return ("%d%%"):format(value) end,
		function(value) if E.selected then E:SetScale(E.selected.element.key, value / 100) end end)
	f.scale:SetPoint("TOPRIGHT", -40, -124)

	Row(f, L.LAYOUT_LAYER, -158)
	f.layer = CreateSlider(f, MIN_LAYER, MAX_LAYER, MAX_LAYER - MIN_LAYER, function(value) return ("%+d"):format(value) end,
		function(value) if E.selected then E:SetLayer(E.selected.element.key, value) end end)
	f.layer:SetPoint("TOPRIGHT", -40, -154)

	local snap = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
	snap:SetSize(26, 26)
	snap:SetPoint("TOPLEFT", 16, -190)
	local snapText = snap.Text or snap:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	snapText:ClearAllPoints()
	snapText:SetPoint("LEFT", snap, "RIGHT", 2, 1)
	snapText:SetFontObject("GameFontHighlight")
	snapText:SetText(L.LAYOUT_SNAP)
	snap:SetScript("OnShow", function(self) self:SetChecked(db().snap) end)
	snap:SetScript("OnClick", function(self) db().snap = self:GetChecked() and true or false end)

	local resetOne = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	resetOne:SetSize(296, 22)
	resetOne:SetPoint("TOP", 0, -222)
	resetOne:SetText(L.LAYOUT_RESET_ONE)
	resetOne:SetScript("OnClick", function() if E.selected then E:ResetElement(E.selected.element.key) end end)
	f.resetOne = resetOne

	local reset = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	reset:SetSize(140, 22)
	reset:SetPoint("BOTTOMLEFT", 22, 20)
	reset:SetText(L.LAYOUT_RESET)
	reset:SetScript("OnClick", function() E:ResetAll() end)

	local done = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	done:SetSize(140, 22)
	done:SetPoint("BOTTOMRIGHT", -22, 20)
	done:SetText(L.LAYOUT_DONE)
	done:SetScript("OnClick", function() E:Stop() end)

	f:SetScript("OnHide", function() if E.active then E:Stop() end end)
	tinsert(UISpecialFrames, "SquareMapLayoutDialog")
	f:Hide()
	self.dialog = f
	return f
end

function E:UpdateDialog()
	local f = self.dialog
	if not f then return end
	local box = self.selected
	local key = box and box.element.key
	f.selected:SetText(box and L[box.element.label] or L.LAYOUT_NONE)
	f.scale:SetSQMValue(key and self:GetScale(key) * 100 or 100)
	f.layer:SetSQMValue(key and self:GetLayer(key) or 0)
	for _, widget in ipairs({ f.scale, f.layer, f.resetOne }) do
		if widget.SetEnabled then widget:SetEnabled(key ~= nil) end
	end
end

function E:Start()
	if self.active then return end
	if InCombatLockdown() then
		UIErrorsFrame:AddMessage(ERR_NOT_IN_COMBAT or L.NOT_IN_COMBAT, 1, 0.1, 0.1)
		return
	end
	self.active = true
	self.boxes = self.boxes or {}
	self:UpdateOverlays()
	;(self.dialog or self:CreateDialog()):Show()
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
