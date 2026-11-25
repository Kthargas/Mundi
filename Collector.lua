local ADDON, ns = ...
local L = ns.L

-- Addon button collector: one button on the minimap edge opens a Blizzard-styled window holding the
-- minimap buttons of other addons (LibDBIcon buttons and other named buttons on the minimap).

local C = {}
ns:RegisterModule("collector", C)

C.ICONS = {
	{ key = "BAG", label = L.ICON_BAG, texture = "Interface\\Icons\\INV_Misc_Bag_10" },
	{ key = "GEAR", label = L.ICON_GEAR, texture = "Interface\\Icons\\INV_Misc_Gear_01" },
	{ key = "SCROLL", label = L.ICON_SCROLL, texture = "Interface\\Icons\\INV_Scroll_03" },
	{ key = "MAP", label = L.ICON_MAP, texture = "Interface\\Icons\\INV_Misc_Map_01" },
	{ key = "CHEST", label = L.ICON_CHEST, texture = "Interface\\Icons\\INV_Box_02" },
}

local CELL = 32       -- base cell size of one minimap button
local PAD = 6         -- inner padding of the window content
local LABEL_GAP = 6

local entries = {}    -- frame -> entry
local ordered = {}    -- list of entries, in the saved order (new buttons by name at the end)

local function db() return ns.db.collector end

local function Meta(frame)
	local mt = getmetatable(frame)
	return mt and mt.__index
end

local function Nop() end

---------------------------------------------------------------------------
-- Detecting buttons
---------------------------------------------------------------------------

-- Frames on the minimap that are map pins or Blizzard parts, never addon buttons.
local IGNORE_PATTERNS = {
	"^SquareMap", "^HybridMinimap", "^MinimapBackdrop", "^MinimapCompass", "^MiniMapMail",
	"^GameTimeFrame", "^TimeManager", "^AddonCompartment", "^ExpansionLandingPage", "^QueueStatus",
	"^Questie", "^HandyNotes", "^GatherMate", "^Gatherer", "^TomTom", "^Routes", "^GatherNote",
	"^CTMapMod", "^NovaWorldBuffs", "^Pin", "Pin%d*$", "Pin_", "POI", "Blip", "^Lib_GPI",
}

local function IsIgnoredName(name)
	for _, pattern in ipairs(IGNORE_PATTERNS) do
		if name:find(pattern) then return true end
	end
	-- Pools of map icons usually end in a number; real buttons rarely do unless they say "minimap".
	if name:find("%d$") and not name:lower():find("minimap") then return true end
	return false
end

local function IsBlizzardFrame(name)
	if type(issecurevariable) ~= "function" then return false end
	local secure, owner = issecurevariable(name)
	return secure and not owner
end

local function LooksLikeButton(frame)
	if not frame.IsObjectType then return false end
	if frame:IsForbidden() or frame:IsProtected() then return false end
	local name = frame:GetName()
	if not name or name:find("^LibDBIcon10_") then return false end
	-- Never take Blizzard's own frames: moving them from addon code spreads taint.
	if IsBlizzardFrame(name) then return false end
	if db().manual[name] then return true end
	if IsIgnoredName(name) then return false end
	if not frame:IsMouseEnabled() then return false end
	local isButton = frame:IsObjectType("Button")
	if not isButton and not (frame:GetScript("OnMouseUp") or frame:GetScript("OnMouseDown")) then return false end
	local w, h = frame:GetSize()
	if w < 14 or h < 14 or w > 64 or h > 64 then return false end
	local ratio = w / h
	return ratio > 0.6 and ratio < 1.6
end

local function DisplayName(name)
	local clean = name:gsub("^LibDBIcon10_", "")
	clean = clean:gsub("[_%-]?[Mm]ini[Mm]ap[_%-]?[Bb]utton", ""):gsub("[_%-]?[Mm]ini[Mm]ap$", "")
	clean = clean:gsub("[_%-]?Button$", ""):gsub("_", " ")
	if clean == "" then return name end
	return clean
end

-- Find the icon texture of a button (for the list layout and the manager window).
local SKIP_TEXTURES = {
	[136430] = true, -- Interface\Minimap\MiniMap-TrackingBorder
	[136467] = true, -- Interface\Minimap\UI-Minimap-Background
	[136477] = true, -- Interface\Minimap\UI-Minimap-ZoomButton-Highlight
}

local function FindIcon(frame)
	local name = frame:GetName()
	local icon = frame.icon or frame.Icon or (name and _G[name .. "Icon"])
	if icon and icon.GetTexture and (icon:GetTexture() or icon:GetAtlas()) then return icon end
	for _, region in ipairs({ frame:GetRegions() }) do
		if region:IsObjectType("Texture") and region:GetDrawLayer() ~= "HIGHLIGHT" then
			local tex = region:GetTexture()
			local skip = type(tex) == "number" and SKIP_TEXTURES[tex]
			if type(tex) == "string" then
				local lower = tex:lower()
				skip = lower:find("trackingborder") or lower:find("minimap%-background") or lower:find("highlight")
			end
			if (tex or region:GetAtlas()) and not skip then return region end
		end
	end
end

function C.CopyIcon(target, source)
	local icon = source and FindIcon(source)
	if not icon then
		target:SetTexture(134400) -- question mark icon
		target:SetTexCoord(0, 1, 0, 1)
		return
	end
	local atlas = icon.GetAtlas and icon:GetAtlas()
	if atlas then
		target:SetAtlas(atlas)
	else
		target:SetTexture(icon:GetTexture())
		target:SetTexCoord(icon:GetTexCoord())
	end
	target:SetDesaturated(icon:IsDesaturated())
	target:SetVertexColor(icon:GetVertexColor())
end

function C:Register(frame, label, source)
	if not frame or entries[frame] then return entries[frame] end
	local name = frame:GetName()
	local entry = {
		frame = frame,
		id = name or ("LDB:" .. tostring(label)),
		label = label or (name and DisplayName(name)) or "?",
		source = source,
	}
	entries[frame] = entry
	ordered[#ordered + 1] = entry
	C:SortEntries()
	return entry
end

-- Buttons the player arranged by dragging keep their saved place; all others follow by name.
function C:SortEntries()
	local rank = {}
	for i, id in ipairs(db().order or {}) do rank[id] = i end
	table.sort(ordered, function(a, b)
		local ra, rb = rank[a.id], rank[b.id]
		if ra and rb then return ra < rb end
		if ra or rb then return ra ~= nil end
		return a.label:lower() < b.label:lower()
	end)
end

function C:SaveOrder()
	local order = {}
	for _, entry in ipairs(ordered) do order[#order + 1] = entry.id end
	db().order = order
end

function C:ResetOrder()
	db().order = {}
	self:SortEntries()
	self:Layout()
end

function C:GetLibDBIcon()
	return LibStub and LibStub("LibDBIcon-1.0", true)
end

function C:Scan(force)
	local lib = self:GetLibDBIcon()
	if lib then
		if lib.GetButtonList then
			for _, name in ipairs(lib:GetButtonList()) do
				local button = lib.GetMinimapButton and lib:GetMinimapButton(name) or _G["LibDBIcon10_" .. name]
				if button then self:Register(button, name, "LDB") end
			end
		end
		if not self.libHooked and lib.RegisterCallback then
			self.libHooked = true
			lib.RegisterCallback(C, "LibDBIcon_IconCreated", function(_, button, name)
				C:Register(button, name, "LDB")
				ns.Debounce("collector-refresh", 0.1, function() C:Refresh() end)
			end)
		end
	end

	local parents = { Minimap, MinimapBackdrop }
	for _, parent in ipairs(parents) do
		if parent then
			for _, child in ipairs({ parent:GetChildren() }) do
				local name = child:GetName()
				if name and name:find("^LibDBIcon10_") then
					self:Register(child, (name:gsub("^LibDBIcon10_", "")), "LDB")
				elseif LooksLikeButton(child) then
					self:Register(child, DisplayName(name), "GENERIC")
				end
			end
		end
	end

	for name in pairs(db().manual) do
		local frame = _G[name]
		if type(frame) == "table" and frame.GetObjectType and not frame:IsForbidden() and not IsBlizzardFrame(name) then
			self:Register(frame, DisplayName(name), "MANUAL")
		end
	end

	self:Refresh()
end

function C:AddManual(name)
	local frame = _G[name]
	if type(frame) ~= "table" or not frame.GetObjectType or frame:IsForbidden() or IsBlizzardFrame(name) then
		ns.Print(L.NOT_FOUND:format(name))
		return
	end
	db().manual[name] = true
	db().excluded[name] = nil
	self:Register(frame, DisplayName(name), "MANUAL")
	self:Refresh()
	ns.Print(L.ADDED:format(name))
end

function C:Count()
	local n = 0
	for _, entry in ipairs(ordered) do
		if entry.collected and entry.frame:IsShown() then n = n + 1 end
	end
	return n
end

function C:GetEntries()
	return ordered
end

---------------------------------------------------------------------------
-- Taking buttons into the window and giving them back
---------------------------------------------------------------------------

local OVERRIDES = { "SetPoint", "ClearAllPoints", "SetAllPoints", "SetParent", "SetAlpha" }

function C:Grab(entry)
	if entry.collected then return end
	local b = entry.frame
	if b:IsProtected() and InCombatLockdown() then return end

	local orig = { parent = b:GetParent(), strata = b:GetFrameStrata(), level = b:GetFrameLevel(),
		scale = b:GetScale(), alpha = b:GetAlpha(), points = {}, methods = {},
		dragStart = b:GetScript("OnDragStart"), dragStop = b:GetScript("OnDragStop"),
		fixedStrata = b.HasFixedFrameStrata and b:HasFixedFrameStrata(),
		fixedLevel = b.HasFixedFrameLevel and b:HasFixedFrameLevel() }
	for i = 1, b:GetNumPoints() do
		orig.points[i] = { b:GetPoint(i) }
	end
	for _, method in ipairs(OVERRIDES) do
		orig.methods[method] = rawget(b, method) or false
	end
	entry.orig = orig

	local meta = Meta(b)
	meta.SetParent(b, self.content)
	-- The owning addon must not move the button out of the window again (LibDBIcon re-places
	-- buttons on the minimap edge whenever it refreshes).
	for _, method in ipairs(OVERRIDES) do b[method] = Nop end
	-- Dragging a button inside the window changes its place in the window.
	if b.RegisterForDrag then b:RegisterForDrag("LeftButton") end
	b:SetScript("OnDragStart", function() C:BeginDrag(entry) end)
	b:SetScript("OnDragStop", function() C:EndDrag(entry) end)
	-- LibDBIcon pins its buttons to MEDIUM strata; inside the DIALOG window they would be hidden behind it.
	if b.SetFixedFrameStrata then b:SetFixedFrameStrata(false) end
	if b.SetFixedFrameLevel then b:SetFixedFrameLevel(false) end
	b:SetFrameStrata(self.content:GetFrameStrata())
	b:SetFrameLevel(self.content:GetFrameLevel() + 5)
	meta.SetAlpha(b, 1)

	if not entry.hooked then
		-- LibDBIcon fades "show on mouseover" icons with an animation when the mouse leaves the minimap.
		if b.fadeOut and b.fadeOut.Play then
			hooksecurefunc(b.fadeOut, "Play", function(anim)
				if entry.collected then
					anim:Stop()
					Meta(b).SetAlpha(b, 1)
				end
			end)
		end
		entry.hooked = true
		local function onUsed(_, mouseButton)
			if entry.collected and db().closeOnClick and mouseButton ~= "RightButton" and not C.dragEntry
				and (not C.dragEndTime or GetTime() - C.dragEndTime > 0.1) then
				C_Timer.After(0, function() C:Hide() end)
			end
		end
		if b:IsObjectType("Button") then
			b:HookScript("OnClick", onUsed)
		else
			b:HookScript("OnMouseUp", onUsed)
		end
		b:HookScript("OnShow", function() if entry.collected then ns.Debounce("collector-layout", 0, function() C:Layout() end) end end)
		b:HookScript("OnHide", function() if entry.collected then ns.Debounce("collector-layout", 0, function() C:Layout() end) end end)
	end
	entry.collected = true
end

function C:Release(entry)
	if not entry.collected then return end
	local b = entry.frame
	if b:IsProtected() and InCombatLockdown() then return end
	if self.dragEntry == entry then self:EndDrag(entry) end
	local orig = entry.orig
	local meta = Meta(b)

	for _, method in ipairs(OVERRIDES) do
		local saved = orig.methods[method]
		b[method] = saved or nil
	end
	meta.SetParent(b, orig.parent or Minimap)
	if b.SetFixedFrameStrata then b:SetFixedFrameStrata(false) end
	if b.SetFixedFrameLevel then b:SetFixedFrameLevel(false) end
	b:SetFrameStrata(orig.strata)
	b:SetFrameLevel(orig.level)
	if orig.fixedStrata then b:SetFixedFrameStrata(true) end
	if orig.fixedLevel then b:SetFixedFrameLevel(true) end
	b:SetScale(orig.scale)
	b:SetAlpha(orig.alpha)
	b:SetScript("OnDragStart", orig.dragStart)
	b:SetScript("OnDragStop", orig.dragStop)
	meta.ClearAllPoints(b)
	for _, p in ipairs(orig.points) do
		meta.SetPoint(b, unpack(p))
	end
	entry.collected = false
	if entry.row then entry.row:Hide() end

	-- LibDBIcon knows best where its button belongs on a square minimap.
	if entry.source == "LDB" then
		local lib = self:GetLibDBIcon()
		if lib and lib.Refresh then pcall(lib.Refresh, lib, entry.label) end
	end
end

function C:ShouldCollect(entry)
	return db().enabled and not db().excluded[entry.id]
end

function C:Refresh()
	if not self.ready then return end
	if InCombatLockdown() then
		ns.RunAfterCombat("collector", function() C:Refresh() end)
	end
	for _, entry in ipairs(ordered) do
		if self:ShouldCollect(entry) then
			self:Grab(entry)
		else
			self:Release(entry)
		end
	end
	self:UpdateButton()
	self:Layout()
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------

local function CreateRow(entry)
	local row = CreateFrame("Button", nil, C.content)
	row:RegisterForClicks("AnyUp")
	local hl = row:CreateTexture(nil, "HIGHLIGHT")
	hl:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
	hl:SetBlendMode("ADD")
	hl:SetAllPoints()
	local text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	text:SetJustifyH("LEFT")
	text:SetWordWrap(false)
	row.text = text

	-- The row forwards clicks and the tooltip to the real addon button.
	row:SetScript("OnClick", function(_, mouseButton)
		local b = entry.frame
		if b:IsObjectType("Button") then
			b:Click(mouseButton)
		else
			local fn = b:GetScript("OnMouseUp")
			if fn then fn(b, mouseButton) end
		end
	end)
	row:RegisterForDrag("LeftButton")
	row:SetScript("OnDragStart", function() C:BeginDrag(entry) end)
	row:SetScript("OnDragStop", function() C:EndDrag(entry) end)
	row:SetScript("OnEnter", function()
		local fn = entry.frame:GetScript("OnEnter")
		if fn then fn(entry.frame) end
	end)
	row:SetScript("OnLeave", function()
		local fn = entry.frame:GetScript("OnLeave")
		if fn then fn(entry.frame) end
	end)
	entry.row = row
	return row
end

local function SavePosition(frame)
	local point, _, relPoint, x, y = frame:GetPoint(1)
	db().point = { point, relPoint, x, y }
end

local function MakeMovable(frame)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function(self)
		if db().anchor == "FREE" then self:StartMoving() end
	end)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		if db().anchor == "FREE" then SavePosition(self) end
	end)
end

function C:CreateWindows()
	-- Window style: Blizzard's ButtonFrameTemplate without portrait.
	local panel = CreateFrame("Frame", "SquareMapCollectorPanel", UIParent, "ButtonFrameTemplate")
	if ButtonFrameTemplate_HideAttic then ButtonFrameTemplate_HideAttic(panel) end
	if ButtonFrameTemplate_HideButtonBar then ButtonFrameTemplate_HideButtonBar(panel) end
	ButtonFrameTemplate_HidePortrait(panel)
	panel:SetTitle(L.WINDOW_TITLE)
	panel:SetFrameStrata("DIALOG")
	panel:SetToplevel(true)
	panel:SetClampedToScreen(true)
	panel:Hide()
	MakeMovable(panel)

	local gear = CreateFrame("Button", nil, panel)
	gear:SetSize(16, 16)
	if panel.CloseButton then
		gear:SetPoint("RIGHT", panel.CloseButton, "LEFT", -2, 0)
	else
		gear:SetPoint("TOPRIGHT", -28, -4)
	end
	gear:SetNormalTexture("Interface\\Buttons\\UI-OptionsButton")
	gear:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
	gear:SetScript("OnClick", function() C:ShowManager() end)
	gear:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip_SetTitle(GameTooltip, L.MANAGE_TITLE)
		GameTooltip:Show()
	end)
	gear:SetScript("OnLeave", GameTooltip_Hide)
	panel.Gear = gear

	-- Compact style: a tooltip border.
	local compact = CreateFrame("Frame", "SquareMapCollectorCompact", UIParent, "TooltipBackdropTemplate")
	compact:SetFrameStrata("DIALOG")
	compact:SetToplevel(true)
	compact:SetClampedToScreen(true)
	compact:Hide()
	MakeMovable(compact)

	tinsert(UISpecialFrames, "SquareMapCollectorPanel")
	tinsert(UISpecialFrames, "SquareMapCollectorCompact")

	local content = CreateFrame("Frame", "SquareMapCollectorContent", panel)
	content:SetSize(1, 1)
	self.content = content
	self.panel, self.compact = panel, compact

	local empty = content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	empty:SetPoint("TOPLEFT", PAD, -PAD)
	empty:SetText(L.EMPTY)
	self.emptyText = empty

	-- Auto close when the mouse stays away
	local idle = 0
	local function OnUpdate(frame, elapsed)
		local delay = db().autoHide or 0
		if delay <= 0 then return end
		if C.dragEntry or frame:IsMouseOver() or (C.button and C.button:IsMouseOver()) then
			idle = 0
			return
		end
		idle = idle + elapsed
		if idle >= delay then
			idle = 0
			frame:Hide()
		end
	end
	for _, frame in ipairs({ panel, compact }) do
		frame:SetScript("OnUpdate", OnUpdate)
		frame:HookScript("OnShow", function()
			idle = 0
			PlaySound(SOUNDKIT.IG_MAINMENU_OPEN)
		end)
		frame:HookScript("OnHide", function()
			PlaySound(SOUNDKIT.IG_MAINMENU_CLOSE)
			if C.button then C.button:UpdateState() end
		end)
	end
end

function C:GetWindow()
	return db().style == "COMPACT" and self.compact or self.panel
end

-- Space taken by the window chrome around the content.
function C:GetChrome(window)
	if window == self.panel then
		local inset = self.panel.Inset
		if inset and inset.GetPointByName then
			local p1, _, _, x1, y1 = inset:GetPointByName("TOPLEFT")
			local p2, _, _, x2, y2 = inset:GetPointByName("BOTTOMRIGHT")
			if p1 and p2 then
				return x1 + PAD, -y1 + PAD, -x2 + PAD, y2 + PAD
			end
		end
		return 10, 28, 10, 10
	end
	return 8, 8, 8, 8
end

-- The panel's nine-slice art needs room for its corner pieces; below that the side edges poke out above
-- and below the frame. Measure the corners instead of guessing, the art differs between clients.
function C:GetMinSize(window)
	if window ~= self.panel then return 0, 0 end
	local nine = window.NineSlice
	local tl, tr = nine and nine.TopLeftCorner, nine and nine.TopRightCorner
	local bl, br = nine and nine.BottomLeftCorner, nine and nine.BottomRightCorner
	local minW, minH = 150, 110
	if not (tl and tr and bl and br) then return minW, minH end
	local top, bottom, left, right = window:GetTop(), window:GetBottom(), window:GetLeft(), window:GetRight()
	local h, w
	if top and bottom and tl:GetBottom() and bl:GetTop() then
		h = math.max(top - tl:GetBottom() + bl:GetTop() - bottom, top - tr:GetBottom() + br:GetTop() - bottom)
		w = math.max(tl:GetRight() - left + right - tr:GetLeft(), bl:GetRight() - left + right - br:GetLeft())
	else
		h = math.max(tl:GetHeight() + bl:GetHeight(), tr:GetHeight() + br:GetHeight())
		w = math.max(tl:GetWidth() + tr:GetWidth(), bl:GetWidth() + br:GetWidth())
	end
	return math.max(minW, math.ceil(w) + 2), math.max(minH, math.ceil(h) + 2)
end

function C:Layout()
	if not self.content then return end
	local cfg = db()
	local window = self:GetWindow()
	local content = self.content
	if content:GetParent() ~= window then
		content:SetParent(window)
	end
	content:SetFrameStrata(window:GetFrameStrata())
	content:SetFrameLevel(window:GetFrameLevel() + 5)

	local scale = cfg.scale
	local cell = CELL * scale
	local spacing = cfg.spacing
	local list = cfg.layout == "LIST"
	local columns = list and 1 or math.max(1, cfg.columns)

	local visible = {}
	for _, entry in ipairs(ordered) do
		if entry.collected then
			if entry.frame:IsShown() then
				visible[#visible + 1] = entry
			elseif entry.row then
				entry.row:Hide()
			end
		end
	end

	-- In list mode each row gets the width of the longest name.
	local labelWidth = 0
	if list then
		for _, entry in ipairs(visible) do
			local row = entry.row or CreateRow(entry)
			row.text:SetText(entry.label)
			labelWidth = math.max(labelWidth, row.text:GetUnboundedStringWidth())
		end
		labelWidth = math.min(math.max(labelWidth, 80), 220)
	end
	local cellW = list and (cell + LABEL_GAP + labelWidth + 4) or cell

	for index, entry in ipairs(visible) do
		local b = entry.frame
		local meta = Meta(b)
		local i = index - 1
		local col = i % columns
		local rowIndex = math.floor(i / columns)
		local x = col * (cellW + spacing)
		local y = rowIndex * (cell + spacing)

		meta.SetParent(b, content)
		b:SetFrameStrata(content:GetFrameStrata())
		b:SetFrameLevel(content:GetFrameLevel() + (entry == self.dragEntry and 20 or 5))
		b:SetScale(scale)
		meta.SetAlpha(b, entry == self.dragEntry and 0.6 or 1)
		if entry ~= self.dragEntry then
			meta.ClearAllPoints(b)
			meta.SetPoint(b, "CENTER", content, "TOPLEFT", (x + cell / 2) / scale, -(y + cell / 2) / scale)
		end

		if list then
			local row = entry.row
			row:SetParent(content)
			row:SetFrameLevel(content:GetFrameLevel() + 1)
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", content, "TOPLEFT", x, -y)
			row:SetSize(cellW, cell)
			row.text:ClearAllPoints()
			row.text:SetPoint("LEFT", row, "LEFT", cell + LABEL_GAP, 0)
			row.text:SetWidth(labelWidth)
			row:Show()
		elseif entry.row then
			entry.row:Hide()
		end
	end

	self.metrics = { visible = visible, columns = columns, cellW = cellW, cell = cell, spacing = spacing, scale = scale }

	local count = #visible
	local rows = math.max(1, math.ceil(count / columns))
	local usedColumns = math.max(1, math.min(columns, count))
	local w = usedColumns * cellW + (usedColumns - 1) * spacing
	local h = rows * cell + (rows - 1) * spacing
	self.emptyText:SetShown(count == 0)
	if count == 0 then
		w = math.max(w, self.emptyText:GetUnboundedStringWidth())
		h = math.max(h, 14)
	end

	local left, top, right, bottom = self:GetChrome(window)
	local minWidth, minHeight = self:GetMinSize(window)
	local width = math.max(minWidth, w + left + right)
	local height = math.max(minHeight, h + top + bottom)
	window:SetSize(width, height)
	content:ClearAllPoints()
	content:SetPoint("TOPLEFT", window, "TOPLEFT", left + (width - left - right - w) / 2, -(top + (height - top - bottom - h) / 2))
	content:SetSize(w, h)

	self:UpdateButton()
end

---------------------------------------------------------------------------
-- Rearranging buttons by drag and drop
---------------------------------------------------------------------------

-- Index of the cell under the cursor, counted like the visible buttons.
function C:CursorSlot()
	local m, content = self.metrics, self.content
	local left, top = content:GetLeft(), content:GetTop()
	if not (m and left and top) or #m.visible == 0 then return nil end
	local s = content:GetEffectiveScale()
	local cx, cy = GetCursorPosition()
	local x, y = cx / s - left, top - cy / s
	local col = math.min(m.columns - 1, math.max(0, math.floor(x / (m.cellW + m.spacing))))
	local row = math.max(0, math.floor(y / (m.cell + m.spacing)))
	return math.min(#m.visible, row * m.columns + col + 1), x, y
end

function C:MoveEntry(entry, slot)
	local visible = self.metrics.visible
	local target = visible[slot]
	if not target or target == entry then return false end
	local fromSlot
	for i, e in ipairs(visible) do if e == entry then fromSlot = i break end end
	for i, e in ipairs(ordered) do if e == entry then table.remove(ordered, i) break end end
	for i, e in ipairs(ordered) do
		if e == target then
			-- Moving forward puts the button behind the target, moving back puts it in front.
			table.insert(ordered, (fromSlot and slot > fromSlot) and i + 1 or i, entry)
			return true
		end
	end
	ordered[#ordered + 1] = entry
	return true
end

function C:BeginDrag(entry)
	if not entry.collected or self.dragEntry or InCombatLockdown() and entry.frame:IsProtected() then return end
	self.dragEntry = entry
	local b, meta = entry.frame, Meta(entry.frame)
	if GameTooltip:IsOwned(b) then GameTooltip:Hide() end
	self.dragger = self.dragger or CreateFrame("Frame")
	self.dragger:SetScript("OnUpdate", function()
		local slot, x, y = C:CursorSlot()
		if not slot then return end
		local scale = C.metrics.scale
		meta.ClearAllPoints(b)
		meta.SetPoint(b, "CENTER", C.content, "TOPLEFT", x / scale, -y / scale)
		if C:MoveEntry(entry, slot) then C:Layout() end
	end)
	self:Layout()
end

function C:EndDrag(entry)
	if self.dragEntry ~= entry then return end
	self.dragger:SetScript("OnUpdate", nil)
	self.dragEntry = nil
	self.dragEndTime = GetTime()
	self:SaveOrder()
	self:Layout()
end

function C:PositionWindow(window)
	window:ClearAllPoints()
	local cfg = db()
	if cfg.anchor == "FREE" and cfg.point then
		local p = cfg.point
		window:SetPoint(p[1], UIParent, p[2], p[3], p[4])
		return
	end
	local anchor = (self.button and self.button:IsShown()) and self.button or Minimap
	local x, y = anchor:GetCenter()
	local sx, sy = UIParent:GetCenter()
	if not x then
		window:SetPoint("CENTER")
		return
	end
	local scaleRatio = anchor:GetEffectiveScale() / UIParent:GetEffectiveScale()
	x, y = x * scaleRatio, y * scaleRatio
	local v = y > sy and "TOP" or "BOTTOM"
	local h = x > sx and "RIGHT" or "LEFT"
	local otherH = h == "RIGHT" and "LEFT" or "RIGHT"
	local gap = h == "RIGHT" and -4 or 4
	if anchor == Minimap then
		window:SetPoint(v .. h, anchor, v .. otherH, gap * 3, 0)
	else
		window:SetPoint(v .. h, anchor, v .. otherH, gap, 0)
	end
end

function C:Show()
	if not self.ready then return end
	local other = self:GetWindow() == self.panel and self.compact or self.panel
	other:Hide()
	self:Scan()
	local window = self:GetWindow()
	self:Layout()
	self:PositionWindow(window)
	window:Show()
	if self.button then self.button:UpdateState() end
end

function C:Hide()
	if self.panel then self.panel:Hide() end
	if self.compact then self.compact:Hide() end
end

function C:IsShown()
	return (self.panel and self.panel:IsShown()) or (self.compact and self.compact:IsShown())
end

function C:IsWindowMouseOver()
	return self:IsShown() and ((self.panel:IsShown() and self.panel:IsMouseOver()) or (self.compact:IsShown() and self.compact:IsMouseOver()))
end

function C:Toggle()
	if self:IsShown() then self:Hide() else self:Show() end
end

---------------------------------------------------------------------------
-- The collector button on the minimap edge (classic minimap button look)
---------------------------------------------------------------------------

local function PlaceButton(button)
	-- A spot chosen in the layout editor wins over the position on the map edge.
	if ns.layout and ns.db.layout and ns.layout:Place("collector") then return end
	local angle = math.rad(db().angle or 225)
	local x, y = math.cos(angle), math.sin(angle)
	local w = Minimap:GetWidth() / 2 + 5
	local h = Minimap:GetHeight() / 2 + 5
	-- Square edge, same maths LibDBIcon uses for square minimaps.
	local diagW = math.sqrt(2 * w * w) - 10
	local diagH = math.sqrt(2 * h * h) - 10
	x = math.max(-w, math.min(x * diagW, w))
	y = math.max(-h, math.min(y * diagH, h))
	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

function C:CreateButton()
	local b = CreateFrame("Button", "SquareMapCollectorButton", Minimap)
	b:SetSize(31, 31)
	b:SetFrameStrata("MEDIUM")
	b:SetFrameLevel(8)
	b:RegisterForClicks("AnyUp")
	b:RegisterForDrag("LeftButton")
	b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

	local overlay = b:CreateTexture(nil, "OVERLAY")
	overlay:SetSize(50, 50)
	overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	overlay:SetPoint("TOPLEFT")
	b.border = overlay

	local background = b:CreateTexture(nil, "BACKGROUND")
	background:SetSize(24, 24)
	background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	background:SetPoint("CENTER")
	b.background = background

	local icon = b:CreateTexture(nil, "ARTWORK")
	icon:SetSize(18, 18)
	icon:SetPoint("CENTER")
	local mask = b:CreateMaskTexture()
	mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	mask:SetAllPoints(icon)
	icon:AddMaskTexture(mask)
	b.icon = icon

	local count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
	count:SetPoint("BOTTOMRIGHT", -3, 4)
	b.count = count

	b:SetScript("OnMouseDown", function(self)
		self.icon:SetPoint("CENTER", 1, -1)
	end)
	b:SetScript("OnMouseUp", function(self)
		self.icon:SetPoint("CENTER", 0, 0)
	end)
	b:SetScript("OnClick", function(self, mouseButton)
		if mouseButton == "RightButton" then
			if IsShiftKeyDown() then
				C:ShowManager()
			else
				ns.OpenOptions()
			end
		else
			C:Toggle()
		end
		GameTooltip:Hide()
	end)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip_SetTitle(GameTooltip, L.SECTION_COLLECTOR)
		GameTooltip:AddLine(L.COLLECTED:format(C:Count()), NORMAL_FONT_COLOR:GetRGB())
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine(L.TT_LEFT, 0.8, 0.8, 0.8)
		GameTooltip:AddLine(L.TT_RIGHT, 0.8, 0.8, 0.8)
		GameTooltip:AddLine(L.TT_SHIFT, 0.8, 0.8, 0.8)
		GameTooltip:AddLine(L.TT_DRAG, 0.8, 0.8, 0.8)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", GameTooltip_Hide)
	b:SetScript("OnDragStart", function(self)
		self:LockHighlight()
		-- In a header field the button is part of the header and does not move.
		if ns.map and ns.map:IsDocked("collector") then return end
		-- Dragging the button along the map edge replaces a spot from the layout editor.
		if ns.db.layout then ns.db.layout.positions.collector = nil end
		self:SetScript("OnUpdate", function()
			local mx, my = Minimap:GetCenter()
			local scale = Minimap:GetEffectiveScale()
			local cx, cy = GetCursorPosition()
			db().angle = math.deg(math.atan2(cy / scale - my, cx / scale - mx)) % 360
			PlaceButton(self)
			if C:IsShown() and db().anchor ~= "FREE" then C:PositionWindow(C:GetWindow()) end
		end)
		GameTooltip:Hide()
	end)
	b:SetScript("OnDragStop", function(self)
		self:SetScript("OnUpdate", nil)
		self:UnlockHighlight()
	end)

	function b:UpdateState()
		if C:IsShown() then self:LockHighlight() else self:UnlockHighlight() end
	end

	self.button = b
end

function C:UpdateButton()
	local b = self.button
	if not b then return end
	local cfg = db()
	b:SetShown(cfg.enabled)
	local iconInfo = self.ICONS[1]
	for _, info in ipairs(self.ICONS) do
		if info.key == cfg.icon then iconInfo = info end
	end
	b.icon:SetTexture(iconInfo.texture)
	b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	local n = self:Count()
	b.count:SetText(n > 0 and n or "")
	b.count:SetShown(cfg.showCount)
	PlaceButton(b)
	b:UpdateState()
end

---------------------------------------------------------------------------
-- Manager window: choose which buttons are collected
---------------------------------------------------------------------------

function C:CreateManager()
	local f = CreateFrame("Frame", "SquareMapManager", UIParent, "ButtonFrameTemplate")
	if ButtonFrameTemplate_HideAttic then ButtonFrameTemplate_HideAttic(f) end
	ButtonFrameTemplate_HidePortrait(f)
	f:SetTitle(L.MANAGE_TITLE)
	f:SetSize(320, 420)
	f:SetPoint("CENTER")
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:Hide()
	tinsert(UISpecialFrames, "SquareMapManager")

	local hint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	hint:SetPoint("TOPLEFT", f.Inset, "TOPLEFT", 8, -8)
	hint:SetPoint("TOPRIGHT", f.Inset, "TOPRIGHT", -8, -8)
	hint:SetJustifyH("LEFT")
	hint:SetText(L.MANAGE_HINT)

	local empty = f:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	empty:SetPoint("CENTER", f.Inset)
	empty:SetText(L.MANAGE_EMPTY)
	f.empty = empty

	local scrollBox = CreateFrame("Frame", nil, f, "WowScrollBoxList")
	scrollBox:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", -4, -8)
	scrollBox:SetPoint("BOTTOMRIGHT", f.Inset, "BOTTOMRIGHT", -20, 6)
	local scrollBar = CreateFrame("EventFrame", nil, f, "MinimalScrollBar")
	scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 6, 0)
	scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 6, 0)

	local view = CreateScrollBoxListLinearView()
	view:SetElementExtent(30)
	view:SetElementInitializer("Button", function(row, entry)
		if not row.check then
			row:SetHeight(30)
			local hl = row:CreateTexture(nil, "HIGHLIGHT")
			hl:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
			hl:SetBlendMode("ADD")
			hl:SetAllPoints()
			local check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
			check:SetSize(26, 26)
			check:SetPoint("LEFT", 2, 0)
			row.check = check
			local icon = row:CreateTexture(nil, "ARTWORK")
			icon:SetSize(20, 20)
			icon:SetPoint("LEFT", check, "RIGHT", 4, 0)
			row.icon = icon
			local text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
			text:SetPoint("LEFT", icon, "RIGHT", 8, 0)
			text:SetPoint("RIGHT", -4, 0)
			text:SetJustifyH("LEFT")
			text:SetWordWrap(false)
			row.text = text
			local function toggle()
				local e = row.entry
				db().excluded[e.id] = (not row.check:GetChecked()) or nil
				PlaySound(row.check:GetChecked() and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
				C:Refresh()
			end
			check:SetScript("OnClick", toggle)
			row:SetScript("OnClick", function()
				row.check:SetChecked(not row.check:GetChecked())
				toggle()
			end)
		end
		row.entry = entry
		row.check:SetChecked(not db().excluded[entry.id])
		C.CopyIcon(row.icon, entry.frame)
		local label = entry.label
		if entry.frame:GetName() and entry.source ~= "LDB" then
			label = label .. " |cff808080(" .. entry.frame:GetName() .. ")|r"
		end
		row.text:SetText(label)
	end)
	ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)
	f.scrollBox = scrollBox

	local rescan = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	rescan:SetSize(120, 22)
	rescan:SetPoint("BOTTOMRIGHT", -6, 4)
	rescan:SetText(L.RESCAN)
	rescan:SetScript("OnClick", function()
		C:Scan(true)
		C:UpdateManager()
	end)
	if ButtonFrameTemplate_ShowButtonBar then ButtonFrameTemplate_ShowButtonBar(f) end

	f:SetScript("OnShow", function()
		PlaySound(SOUNDKIT.IG_MAINMENU_OPEN)
		C:UpdateManager()
	end)
	f:SetScript("OnHide", function() PlaySound(SOUNDKIT.IG_MAINMENU_CLOSE) end)
	self.manager = f
end

function C:UpdateManager()
	local f = self.manager
	if not f then return end
	local list = {}
	for _, entry in ipairs(ordered) do list[#list + 1] = entry end
	f.scrollBox:SetDataProvider(CreateDataProvider(list), ScrollBoxConstants and ScrollBoxConstants.RetainScrollPosition)
	f.empty:SetShown(#list == 0)
end

function C:ShowManager()
	if not self.manager then self:CreateManager() end
	self:Scan()
	if self.manager:IsShown() then
		self:UpdateManager()
	else
		self.manager:Show()
	end
end

---------------------------------------------------------------------------

function C:Init()
	self:CreateWindows()
	self:CreateButton()
	self.ready = true

	EventRegistry:RegisterCallback("SquareMap.LayoutChanged", function()
		if self.button then PlaceButton(self.button) end
		for _, entry in ipairs(ordered) do
			if not entry.collected and entry.source == "LDB" then
				local lib = self:GetLibDBIcon()
				if lib and lib.Refresh then pcall(lib.Refresh, lib, entry.label) end
			end
		end
	end, self)

	-- Addons create their buttons at different times; look again a few times after login.
	local f = CreateFrame("Frame")
	f:RegisterEvent("PLAYER_ENTERING_WORLD")
	f:RegisterEvent("ADDON_LOADED")
	f:SetScript("OnEvent", function()
		ns.Debounce("collector-scan", 1, function() C:Scan() end)
	end)
	for _, delay in ipairs({ 1, 3, 8, 20 }) do
		C_Timer.After(delay, function() C:Scan() end)
	end
end

function C:Apply()
	if not self.ready then return end
	self:Refresh()
	if self:IsShown() then
		local window = self:GetWindow()
		local other = window == self.panel and self.compact or self.panel
		if other:IsShown() then
			other:Hide()
			window:Show()
		end
		self:Layout()
		self:PositionWindow(window)
	end
end
