local ADDON, ns = ...
local L = ns.L

-- Options in Blizzard's own settings window (Esc > Options > AddOns > SquareMap), built only from
-- the stock Settings controls so it looks and behaves like every other game option.

local O = { settings = {} }
ns.options = O

local function ApplyAll()
	ns:ApplyAll()
end

local function ListOptions(list)
	return function()
		local container = Settings.CreateControlTextContainer()
		for _, item in ipairs(list) do
			container:Add(item.key, item.label)
		end
		return container:GetData()
	end
end

function O:Proxy(category, section, field, varType, name, onSet)
	local variable = "SQUAREMAP_" .. section:upper() .. "_" .. field:upper()
	local default = ns.DEFAULTS[section][field]
	local setting = Settings.RegisterProxySetting(category, variable, varType, name, default,
		function() return ns.db[section][field] end,
		function(value)
			ns.db[section][field] = value
			;(onSet or ApplyAll)(value)
		end)
	self.settings[#self.settings + 1] = setting
	return setting
end

function O:Checkbox(category, section, field, name, tooltip, onSet)
	local setting = self:Proxy(category, section, field, Settings.VarType.Boolean, name, onSet)
	return Settings.CreateCheckbox(category, setting, tooltip), setting
end

function O:Slider(category, section, field, name, tooltip, minValue, maxValue, step, formatter)
	local setting = self:Proxy(category, section, field, Settings.VarType.Number, name)
	local options = Settings.CreateSliderOptions(minValue, maxValue, step)
	options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, formatter or function(value)
		return tostring(math.floor(value + 0.5))
	end)
	return Settings.CreateSlider(category, setting, options, tooltip), setting
end

function O:Dropdown(category, section, field, name, tooltip, list)
	local setting = self:Proxy(category, section, field, Settings.VarType.String, name)
	return Settings.CreateDropdown(category, setting, ListOptions(list), tooltip), setting
end

local function CVarExists(name)
	if C_CVar and C_CVar.GetCVarInfo then
		return C_CVar.GetCVarInfo(name) ~= nil
	end
	return GetCVar(name) ~= nil
end

function O:CVarCheckbox(category, cvar, variable, name, tooltip, onSet)
	if not CVarExists(cvar) then return end
	local default = GetCVarDefault and GetCVarDefault(cvar) == "1" or false
	local setting = Settings.RegisterProxySetting(category, variable, Settings.VarType.Boolean, name, default,
		function() return GetCVarBool(cvar) end,
		function(value)
			SetCVar(cvar, value and "1" or "0")
			if onSet then onSet(value) end
		end)
	return Settings.CreateCheckbox(category, setting, tooltip), setting
end

local function Header(layout, text)
	layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(text))
end

local function DependsOn(child, parent, predicate)
	if child and parent and child.SetParentInitializer then
		child:SetParentInitializer(parent, predicate)
	end
end

local function Percent(value) return L.PERCENT:format(math.floor(value * 100 + 0.5)) end
local function Seconds(value)
	if value <= 0 then return L.OFF end
	return L.SECONDS:format(value)
end

function O:Register()
	if not (Settings and Settings.RegisterVerticalLayoutCategory) then return end

	local category, layout = Settings.RegisterVerticalLayoutCategory(L.TITLE)
	self.category = category

	-- Minimap
	Header(layout, L.SECTION_MAP)
	self:Slider(category, "map", "size", L.SIZE, L.SIZE_TT, 140, 400, 2)

	local borders = {}
	local available = ns.map and ns.map.GetAvailableBorders and ns.map:GetAvailableBorders() or ns.map.BORDERS
	for _, style in ipairs(available) do borders[#borders + 1] = { key = style.key, label = style.label } end
	local borderInit = self:Dropdown(category, "map", "border", L.BORDER, L.BORDER_TT, borders)
	local function HasArt() return ns.db.map.border ~= "NONE" end
	DependsOn(self:Slider(category, "map", "borderScale", L.BORDER_SCALE, L.BORDER_SCALE_TT, 0.4, 1.6, 0.05, Percent), borderInit, HasArt)
	DependsOn(self:Slider(category, "map", "borderOffset", L.BORDER_OFFSET, L.BORDER_OFFSET_TT, -10, 20, 1), borderInit, HasArt)

	self:Dropdown(category, "map", "headerPos", L.HEADER_POS, L.HEADER_POS_TT, {
		{ key = "ABOVE", label = L.HEADER_ABOVE },
		{ key = "BELOW", label = L.HEADER_BELOW },
	})
	self:Slider(category, "map", "headerGap", L.HEADER_GAP, L.HEADER_GAP_TT, -10, 20, 1)
	self:Checkbox(category, "map", "headerFull", L.HEADER_FULL, L.HEADER_FULL_TT)

	self:CVarCheckbox(category, "rotateMinimap", "SQUAREMAP_CVAR_ROTATE", L.ROTATE, L.ROTATE_TT)
	self:Dropdown(category, "map", "zoomButtons", L.ZOOM_BUTTONS, L.ZOOM_BUTTONS_TT, {
		{ key = "HOVER", label = L.ZOOM_HOVER },
		{ key = "ALWAYS", label = L.ZOOM_ALWAYS },
		{ key = "NEVER", label = L.ZOOM_NEVER },
	})
	self:Slider(category, "map", "autoZoom", L.AUTOZOOM, L.AUTOZOOM_TT, 0, 60, 1, Seconds)

	local coordsInit = self:CVarCheckbox(category, "minimapShowPlayerCoords", "SQUAREMAP_CVAR_COORDS", L.COORDS, L.COORDS_TT)
	local coordsPos = self:Dropdown(category, "map", "coordsPos", L.COORDS_POS, nil, {
		{ key = "BELOW", label = L.COORDS_BELOW },
		{ key = "INSIDE", label = L.COORDS_INSIDE },
		{ key = "TOP", label = L.COORDS_TOP },
	})
	DependsOn(coordsPos, coordsInit, function() return GetCVarBool("minimapShowPlayerCoords") end)

	self:Checkbox(category, "map", "showDiel", L.SHOW_DIEL, L.SHOW_DIEL_TT)
	self:Checkbox(category, "map", "showInstance", L.SHOW_INSTANCE, L.SHOW_INSTANCE_TT)
	self:Checkbox(category, "map", "compass", L.COMPASS, L.COMPASS_TT)
	self:Checkbox(category, "map", "headerFade", L.HEADER_FADE, L.HEADER_FADE_TT)
	self:Slider(category, "map", "combatAlpha", L.COMBAT_ALPHA, L.COMBAT_ALPHA_TT, 0.1, 1, 0.05, Percent)

	Header(layout, L.SECTION_WORLDMAP)
	self:Checkbox(category, "worldmap", "caves", L.WM_CAVES, L.WM_CAVES_TT)
	self:Checkbox(category, "worldmap", "coords", L.WM_COORDS, L.WM_COORDS_TT)

	Header(layout, L.SECTION_CLICKS)
	local actions = ns.extras and ns.extras.ACTIONS or {}
	self:Dropdown(category, "map", "rightClick", L.RIGHT_CLICK, nil, actions)
	self:Dropdown(category, "map", "middleClick", L.MIDDLE_CLICK, nil, actions)

	-- Addon buttons
	Header(layout, L.SECTION_COLLECTOR)
	local enableInit = self:Checkbox(category, "collector", "enabled", L.COLLECTOR_ENABLE, L.COLLECTOR_ENABLE_TT)
	local function Enabled() return ns.db.collector.enabled end
	local function Dep(init) DependsOn(init, enableInit, Enabled) return init end

	local icons = {}
	for _, info in ipairs(ns.collector and ns.collector.ICONS or {}) do
		icons[#icons + 1] = { key = info.key, label = ("|T%s:16:16:0:0:64:64:5:59:5:59|t %s"):format(info.texture, info.label) }
	end
	Dep(self:Dropdown(category, "collector", "icon", L.COLLECTOR_ICON, nil, icons))
	Dep(self:Checkbox(category, "collector", "showCount", L.SHOW_COUNT, L.SHOW_COUNT_TT))
	Dep(self:Dropdown(category, "collector", "style", L.WINDOW_STYLE, nil, {
		{ key = "PANEL", label = L.STYLE_PANEL },
		{ key = "COMPACT", label = L.STYLE_COMPACT },
	}))
	local layoutInit = Dep(self:Dropdown(category, "collector", "layout", L.LAYOUT, nil, {
		{ key = "GRID", label = L.LAYOUT_GRID },
		{ key = "LIST", label = L.LAYOUT_LIST },
	}))
	local columns = self:Slider(category, "collector", "columns", L.COLUMNS, nil, 1, 12, 1)
	DependsOn(columns, layoutInit, function() return Enabled() and ns.db.collector.layout ~= "LIST" end)
	Dep(self:Slider(category, "collector", "scale", L.BUTTON_SCALE, nil, 0.6, 1.6, 0.05, Percent))
	Dep(self:Slider(category, "collector", "spacing", L.SPACING, nil, 0, 16, 1))
	Dep(self:Dropdown(category, "collector", "anchor", L.WINDOW_ANCHOR, nil, {
		{ key = "BUTTON", label = L.ANCHOR_BUTTON },
		{ key = "FREE", label = L.ANCHOR_FREE },
	}))
	Dep(self:Checkbox(category, "collector", "closeOnClick", L.CLOSE_ON_CLICK, L.CLOSE_ON_CLICK_TT))
	Dep(self:Slider(category, "collector", "autoHide", L.AUTO_HIDE, L.AUTO_HIDE_TT, 0, 10, 1, Seconds))

	if CreateSettingsButtonInitializer then
		layout:AddInitializer(CreateSettingsButtonInitializer(L.MANAGE, L.MANAGE_BTN, function()
			if ns.collector then ns.collector:ShowManager() end
		end, L.MANAGE_TT, true))
		layout:AddInitializer(CreateSettingsButtonInitializer(L.SORT_RESET, L.SORT_RESET_BTN, function()
			if ns.collector then ns.collector:ResetOrder() end
		end, L.SORT_RESET_TT, true))

		Header(layout, L.SECTION_INFO)
		layout:AddInitializer(CreateSettingsButtonInitializer(L.RESET_ALL, L.RESET_ALL_BTN, function()
			StaticPopup_Show("SQUAREMAP_RESET")
		end, nil, true))
	end

	Settings.RegisterAddOnCategory(category)
end

function O:Refresh()
	for _, setting in ipairs(self.settings) do
		if setting.NotifyUpdate then setting:NotifyUpdate() end
	end
end

function O:Open()
	if self.category and Settings.OpenToCategory then
		Settings.OpenToCategory(self.category:GetID())
	end
end

StaticPopupDialogs["SQUAREMAP_RESET"] = {
	text = L.RESET_CONFIRM,
	button1 = YES,
	button2 = NO,
	OnAccept = function() ns:ResetSettings() end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}
