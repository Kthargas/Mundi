local ADDON, ns = ...
local L = ns.L

_G.Mundi = ns
ns.version = C_AddOns and C_AddOns.GetAddOnMetadata(ADDON, "Version") or "1.0.0"
ns.modules = {}

-- Built-in game texture used as a square mask. The only own file is the logo.
ns.SQUARE_MASK = "Interface\\Buttons\\WHITE8X8"
ns.ICON = "Interface\\AddOns\\" .. ADDON .. "\\Textures\\Icon"

ns.DEFAULTS = {
	map = {
		size = 198,
		border = "DIALOG",
		borderScale = 0.8,
		borderOffset = 0,
		zoomButtons = "HOVER",
		autoZoom = 0,
		coordsPos = "BELOW",
		headerPos = "ABOVE",
		headerGap = 1,
		headerFull = true,
		hideCompartment = false,
		showDiel = true,
		showInstance = true,
		headerFade = false,
		combatAlpha = 1,
		rightClick = "TRACKING",
		middleClick = "COLLECTOR",
	},
	worldmap = {
		caves = false,
		width = nil,
		coords = true,
		levelHover = true,
		levelMap = true,
	},
	collector = {
		enabled = true,
		icon = "LOGO",
		angle = 225,
		showCount = true,
		style = "PANEL",
		scale = 1,
		spacing = 4,
		anchor = "BUTTON",
		closeOnClick = true,
		autoHide = 0,
		point = nil,
		excluded = {},
		order = {},
		manual = {},
	},
	-- Header: a function in the square field at each end, and three text fields in between.
	header = {
		background = true,
		left = "tracking",
		right = "calendar",
		infoLeft = "ZONE",
		infoCenter = "NONE",
		infoRight = "CLOCK",
	},
	layout = {
		snap = true,
		positions = {},
		scales = {},
		layers = {},
		hidden = {},
	},
}

local function CopyDefaults(src, dst)
	for k, v in pairs(src) do
		if type(v) == "table" then
			if type(dst[k]) ~= "table" then dst[k] = {} end
			CopyDefaults(v, dst[k])
		elseif dst[k] == nil then
			dst[k] = v
		end
	end
	return dst
end

function ns.Print(...)
	print("|cffffd100" .. L.TITLE .. ":|r", ...)
end

-- Modules: { Init = fn, Apply = fn }. Init runs once at login, Apply whenever settings change.
function ns:RegisterModule(name, mod)
	self.modules[#self.modules + 1] = mod
	self[name] = mod
	mod.name = name
end

function ns:ApplyAll()
	for _, mod in ipairs(self.modules) do
		if mod.Apply then
			local ok, err = pcall(mod.Apply, mod)
			if not ok then geterrorhandler()(err) end
		end
	end
end

-- Some work must wait until combat is over (moving protected frames, for example).
local afterCombat = {}
function ns.RunAfterCombat(key, fn)
	if not InCombatLockdown() then
		fn()
		return true
	end
	afterCombat[key] = fn
	return false
end

-- Small throttle so many events in a row only cause one update.
function ns.Debounce(key, delay, fn)
	ns._debounce = ns._debounce or {}
	if ns._debounce[key] then return end
	ns._debounce[key] = true
	C_Timer.After(delay, function()
		ns._debounce[key] = nil
		fn()
	end)
end

function ns.IsSecret(v)
	return type(issecretvalue) == "function" and issecretvalue(v)
end

-- Profiles
ns.SHARED = "Default"

function ns.CharKey()
	-- GetRealmName is ready at load time (UnitFullName may not be yet), so keys stay the same every session.
	return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
end

-- Switch this character between the shared settings and its own copy of them. Needs a reload.
function ns.SetOwnProfile(own)
	if (ns.char.own and true or false) == own then return end
	ns.char.own = own or nil
	local key = ns.CharKey()
	if own and type(ns.root.profiles[key]) ~= "table" then
		ns.root.profiles[key] = CopyTable(ns.root.profiles[ns.SHARED])
	end
	StaticPopup_Show("MUNDI_RELOAD_PROFILE")
end

StaticPopupDialogs["MUNDI_RELOAD_PROFILE"] = {
	text = L.RELOAD_PROFILE,
	button1 = L.WM_RELOAD_NOW,
	button2 = L.WM_RELOAD_LATER,
	OnAccept = function() ReloadUI() end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

-- Gold of every character, for the tooltip of the gold field.
function ns.SaveGold()
	if not ns.root then return end
	local _, class = UnitClass("player")
	ns.root.gold[ns.CharKey()] = { money = GetMoney(), class = class }
end

function ns:ResetSettings()
	-- Put moved elements back first; their saved spots are about to go.
	if ns.layout and ns.db and ns.db.layout then ns.layout:ResetAll() end
	wipe(ns.db)
	CopyDefaults(ns.DEFAULTS, ns.db)
	ns:ApplyAll()
	if ns.options and ns.options.Refresh then ns.options:Refresh() end
end

local events = CreateFrame("Frame")
ns.events = events
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("PLAYER_MONEY")
events:SetScript("OnEvent", function(self, event, arg1)
	if event == "ADDON_LOADED" and arg1 == ADDON then
		-- 2.0.0: SquareMap is now Mundi. Settings saved under the old name are taken over once
		-- (WTF\...\SavedVariables\SquareMap.lua renamed to Mundi.lua keeps them).
		if not MundiDB and type(SquareMapDB) == "table" then
			MundiDB = SquareMapDB
			ns.migrated = true
		end
		SquareMapDB = nil
		MundiDB = MundiDB or {}
		local root = MundiDB
		-- Settings live in profiles: one shared by all characters, and one per character that wants its own.
		if type(root.profiles) ~= "table" then
			local old = {}
			for k, v in pairs(root) do old[k] = v; root[k] = nil end
			root.profiles = { [ns.SHARED] = old }
		end
		root.chars = root.chars or {}
		root.gold = root.gold or {}
		root.profiles[ns.SHARED] = root.profiles[ns.SHARED] or {}
		local charKey = ns.CharKey()
		local char = root.chars[charKey] or {}
		root.chars[charKey] = char
		local name = char.own and charKey or ns.SHARED
		if type(root.profiles[name]) ~= "table" then root.profiles[name] = CopyTable(root.profiles[ns.SHARED]) end
		ns.root, ns.char = root, char
		ns.db = CopyDefaults(ns.DEFAULTS, root.profiles[name])
		-- 1.0.6: the click actions are back (the blocked popup came from the ping listener). Versions
		-- 1.0.1 to 1.0.5 had reset right click to the ping; give it the tracking menu again once.
		if not ns.db.map.clicksRestored then
			if ns.db.map.rightClick == "PING" then ns.db.map.rightClick = "TRACKING" end
			ns.db.map.clicksRestored = true
		end
		-- 1.3.1: switching to cave maps uses Blizzard's SetMapID from addon code, which taints the map
		-- (map pin sharing got blocked). It is opt-in now; turn it off once for existing settings.
		-- 1.4.1: opening the world map from addon code tainted it (blocked map pins in combat).
		for _, field in ipairs({ "rightClick", "middleClick" }) do
			if ns.db.map[field] == "WORLDMAP" then ns.db.map[field] = "NONE" end
		end
		-- 1.8.0: the header has fixed fields for tracking and calendar. They go back into the header once,
		-- also when 1.7.0 left them where the layout editor had put them.
		if not ns.db.header.fields then
			local header, layout = ns.db.header, ns.db.layout
			header.dock, header.order, header.buttonBg, header.migrated = nil, nil, nil, nil
			for _, key in ipairs({ "tracking", "calendar" }) do
				layout.positions[key], layout.scales[key], layout.layers[key] = nil, nil, nil
			end
			header.fields = true
		end
		-- 1.8.3: the collector window is always a list; the grid settings are gone.
		-- 1.9.0: the north marker is gone (the square map always keeps north up).
		ns.db.collector.layout, ns.db.collector.columns, ns.db.map.compass = nil, nil, nil
		if not ns.db.worldmap.cavesOptIn then
			ns.db.worldmap.caves = false
			ns.db.worldmap.cavesOptIn = true
		end
		-- 1.1.0 had a resource alert; Blizzard closed the minimap to addons, so it is gone again.
		ns.db.alert = nil
		if ns.options and ns.options.Register then
			local ok, err = pcall(ns.options.Register, ns.options)
			if not ok then geterrorhandler()(err) end
		end
	elseif event == "PLAYER_MONEY" then
		ns.SaveGold()
	elseif event == "PLAYER_LOGIN" then
		ns.sessionMoney = GetMoney()
		ns.SaveGold()
		for _, mod in ipairs(ns.modules) do
			if mod.Init then
				local ok, err = pcall(mod.Init, mod)
				if not ok then geterrorhandler()(err) end
			end
		end
		ns:ApplyAll()
		-- The old SquareMap folder would run a second minimap next to this one: switch it off.
		if C_AddOns and C_AddOns.GetAddOnInfo and C_AddOns.GetAddOnInfo("SquareMap") then
			if C_AddOns.IsAddOnLoaded("SquareMap") then
				C_AddOns.DisableAddOn("SquareMap")
				ns.Print(L.OLD_ADDON)
			end
		end
		if ns.migrated then ns.Print(L.MIGRATED) end
	elseif event == "PLAYER_REGEN_ENABLED" then
		for key, fn in pairs(afterCombat) do
			afterCombat[key] = nil
			local ok, err = pcall(fn)
			if not ok then geterrorhandler()(err) end
		end
	end
end)

-- Slash commands (same layout as Fray: no argument opens the options, "help" lists the rest)
local COMMANDS = {
	{ "", L.CMD_OPTIONS },
	{ "buttons", L.CMD_BUTTONS },
	{ "manage", L.CMD_MANAGE },
	{ "layout", L.CMD_LAYOUT },
	{ "scan", L.CMD_SCAN },
	{ "add <Frame>", L.CMD_ADD },
	{ "reset", L.CMD_RESET },
}

local function Help()
	ns.Print(L.HELP_TITLE)
	for _, c in ipairs(COMMANDS) do
		print(("  |cffffd100/mundi%s|r - %s"):format(c[1] ~= "" and " " .. c[1] or "", c[2]))
	end
end

SLASH_MUNDI1 = "/mundi"
SlashCmdList.MUNDI = function(msg)
	local cmd, rest = strtrim(msg or ""):match("^(%S*)%s*(.-)$")
	cmd = (cmd or ""):lower()
	if cmd == "" or cmd == "options" or cmd == "config" then
		ns.OpenOptions()
	elseif cmd == "buttons" or cmd == "b" then
		if ns.collector then ns.collector:Toggle() end
	elseif cmd == "manage" then
		if ns.collector then ns.collector:ShowManager() end
	elseif cmd == "layout" or cmd == "edit" then
		if ns.layout then ns.layout:Toggle() end
	elseif cmd == "scan" then
		if ns.collector then ns.collector:Scan() end
		ns.Print(L.COLLECTED:format(ns.collector and ns.collector:Count() or 0))
	elseif cmd == "add" and rest ~= "" then
		if ns.collector then ns.collector:AddManual(rest) end
	elseif cmd == "reset" then
		StaticPopup_Show("MUNDI_RESET")
	else
		Help()
	end
end

function ns.OpenOptions()
	if ns.options and ns.options.Open then
		ns.options:Open()
	end
end

-- Key bindings (Bindings.xml)
function Mundi_ToggleCollector()
	if ns.collector then ns.collector:Toggle() end
end

function Mundi_OpenOptions()
	ns.OpenOptions()
end

-- Addon compartment entry (## AddonCompartmentFunc in the TOC)
function Mundi_OnAddonCompartmentClick(addonName, mouseButton)
	if mouseButton == "RightButton" then
		if ns.collector then ns.collector:Toggle() end
	else
		ns.OpenOptions()
	end
end

function Mundi_OnAddonCompartmentEnter(addonName, menuButton)
	GameTooltip:SetOwner(menuButton, "ANCHOR_LEFT")
	GameTooltip_SetTitle(GameTooltip, L.TITLE)
	GameTooltip:AddLine(L.CMP_LEFT, 1, 1, 1)
	GameTooltip:AddLine(L.CMP_RIGHT, 1, 1, 1)
	GameTooltip:Show()
end

function Mundi_OnAddonCompartmentLeave()
	GameTooltip:Hide()
end
