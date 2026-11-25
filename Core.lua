local ADDON, ns = ...
local L = ns.L

_G.SquareMap = ns
ns.version = C_AddOns and C_AddOns.GetAddOnMetadata(ADDON, "Version") or "1.0.0"
ns.modules = {}
ns.reported = {}

-- Built-in game texture used as a square mask (no custom textures are shipped).
ns.SQUARE_MASK = "Interface\\Buttons\\WHITE8X8"

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
		showDiel = true,
		showInstance = true,
		compass = true,
		headerFade = false,
		combatAlpha = 1,
		rightClick = "TRACKING",
		middleClick = "COLLECTOR",
	},
	worldmap = {
		caves = false,
		width = nil,
		coords = true,
	},
	collector = {
		enabled = true,
		icon = "BAG",
		angle = 225,
		showCount = true,
		style = "PANEL",
		layout = "GRID",
		columns = 5,
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
	layout = {
		snap = true,
		positions = {},
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
	print("|cffffd100SquareMap:|r", ...)
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

function ns:ResetSettings()
	-- Put moved elements back first; their saved spots are about to go.
	if ns.layout and ns.db and ns.db.layout then ns.layout:ResetAll() end
	wipe(SquareMapDB)
	CopyDefaults(ns.DEFAULTS, SquareMapDB)
	ns.db = SquareMapDB
	ns:ApplyAll()
	if ns.options and ns.options.Refresh then ns.options:Refresh() end
end

-- Diagnostics: remember the last SquareMap calls, so a blocked action can be traced back to them.
local trace = {}
function ns.Trace(label)
	local now = GetTime()
	local last = trace[#trace]
	if last and last.label == label then
		last.count, last.time = last.count + 1, now
		return
	end
	trace[#trace + 1] = { label = label, count = 1, time = now }
	if #trace > 8 then table.remove(trace, 1) end
end

local function Instrument(name, tbl)
	if type(tbl) ~= "table" then return end
	for key, fn in pairs(tbl) do
		if type(fn) == "function" then
			local label = name .. ":" .. tostring(key)
			tbl[key] = function(...)
				ns.Trace(label)
				return fn(...)
			end
		end
	end
end

function ns.PrintTrace()
	local now = GetTime()
	for i = #trace, math.max(1, #trace - 5), -1 do
		local t = trace[i]
		ns.Print(L.TRACE_LINE:format(t.label, t.count, now - t.time))
	end
end

local events = CreateFrame("Frame")
ns.events = events
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
-- Diagnostics: name the blocked function in chat so taint reports can be tracked down.
events:RegisterEvent("ADDON_ACTION_BLOCKED")
events:RegisterEvent("ADDON_ACTION_FORBIDDEN")
events:SetScript("OnEvent", function(self, event, arg1, arg2)
	if event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
		if arg1 == ADDON then
			-- Once per blocked function and session; a tainted map can block the same call many times.
			local key = event .. tostring(arg2)
			if ns.reported[key] then return end
			ns.reported[key] = true
			ns.Print(L.BLOCKED:format(event, tostring(arg2), InCombatLockdown() and L.YES or L.NO) .. " v" .. tostring(ns.version))
			ns.PrintTrace()
			if ns.worldmap and ns.worldmap.tainted then ns.Print(L.WM_TAINTED) end
		end
		return
	end
	if event == "ADDON_LOADED" and arg1 == ADDON then
		for _, mod in ipairs(ns.modules) do Instrument(mod.name, mod) end
		Instrument("options", ns.options)
		SquareMapDB = SquareMapDB or {}
		CopyDefaults(ns.DEFAULTS, SquareMapDB)
		ns.db = SquareMapDB
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
		if not ns.db.worldmap.cavesOptIn then
			ns.db.worldmap.caves = false
			ns.db.worldmap.cavesOptIn = true
		end
		if ns.options and ns.options.Register then
			local ok, err = pcall(ns.options.Register, ns.options)
			if not ok then geterrorhandler()(err) end
		end
	elseif event == "PLAYER_LOGIN" then
		for _, mod in ipairs(ns.modules) do
			if mod.Init then
				local ok, err = pcall(mod.Init, mod)
				if not ok then geterrorhandler()(err) end
			end
		end
		ns:ApplyAll()
	elseif event == "PLAYER_REGEN_ENABLED" then
		for key, fn in pairs(afterCombat) do
			afterCombat[key] = nil
			local ok, err = pcall(fn)
			if not ok then geterrorhandler()(err) end
		end
	end
end)

-- Slash commands
SLASH_SQUAREMAP1 = "/squaremap"
SLASH_SQUAREMAP2 = "/sqm"
SlashCmdList.SQUAREMAP = function(msg)
	msg = strtrim(msg or "")
	local cmd, rest = msg:match("^(%S*)%s*(.-)$")
	cmd = (cmd or ""):lower()
	if cmd == "" or cmd == "options" or cmd == "config" then
		ns.OpenOptions()
	elseif cmd == "buttons" or cmd == "b" then
		if ns.collector then ns.collector:Toggle() end
	elseif cmd == "manage" then
		if ns.collector then ns.collector:ShowManager() end
	elseif cmd == "scan" then
		if ns.collector then ns.collector:Scan(true) end
		ns.Print(L.COLLECTED:format(ns.collector and ns.collector:Count() or 0))
	elseif cmd == "add" and rest ~= "" then
		if ns.collector then ns.collector:AddManual(rest) end
	elseif cmd == "layout" or cmd == "edit" then
		if ns.layout then ns.layout:Toggle() end
	elseif cmd == "atlas" then
		if ns.map then ns.map:PrintAtlasReport() end
	elseif cmd == "reset" then
		ns:ResetSettings()
	else
		ns.Print(L.HELP)
	end
end

function ns.OpenOptions()
	if ns.options and ns.options.Open then
		ns.options:Open()
	end
end

-- Key bindings (Bindings.xml)
function SquareMap_ToggleCollector()
	if ns.collector then ns.collector:Toggle() end
end

function SquareMap_OpenOptions()
	ns.OpenOptions()
end

-- Addon compartment entry (## AddonCompartmentFunc in the TOC)
function SquareMap_OnAddonCompartmentClick(addonName, mouseButton)
	if mouseButton == "RightButton" then
		if ns.collector then ns.collector:Toggle() end
	else
		ns.OpenOptions()
	end
end

function SquareMap_OnAddonCompartmentEnter(addonName, menuButton)
	GameTooltip:SetOwner(menuButton, "ANCHOR_LEFT")
	GameTooltip_SetTitle(GameTooltip, L.TITLE)
	GameTooltip:AddLine(L.CMP_LEFT, 1, 1, 1)
	GameTooltip:AddLine(L.CMP_RIGHT, 1, 1, 1)
	GameTooltip:Show()
end

function SquareMap_OnAddonCompartmentLeave()
	GameTooltip:Hide()
end
