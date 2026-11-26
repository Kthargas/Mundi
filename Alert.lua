local ADDON, ns = ...
local L = ns.L

-- Resource alert: a sound and a message when the minimap shows a herb, an ore or a treasure that the
-- tracking (Find Herbs, Find Minerals, Find Treasure) finds.
--
-- The game has no list of the tracking dots, but the minimap can be asked what lies under any point:
-- with its soft cursor on, Minimap:UpdateMouseoverAtPoint() moves a virtual mouse over the map, and
-- C_TooltipInfo.GetMinimapMouseover() returns the tooltip lines for that spot. A grid of such points
-- covers the whole square map, a few dozen per frame. Nothing moves and the real mouse is untouched.

local A = {}

A.SOUNDS = {
	{ key = "NONE", label = L.ALERT_SOUND_NONE },
	{ key = "RAID_WARNING", label = L.ALERT_SOUND_RAID },
	{ key = "READY_CHECK", label = L.ALERT_SOUND_READY },
	{ key = "TELL_MESSAGE", label = L.ALERT_SOUND_WHISPER },
	{ key = "MAP_PING", label = L.ALERT_SOUND_PING },
}
local SOUND_IDS = { RAID_WARNING = 8959, READY_CHECK = 8960, TELL_MESSAGE = 3081, MAP_PING = 3175 }

local STEP = 8          -- grid spacing in minimap units; a dot answers within about 11 units
local PER_FRAME = 80    -- probes per frame
-- Tracking spells whose dots are worth an alert: Find Herbs, Find Minerals, Find Treasure.
local FINDERS = { [2383] = true, [2580] = true, [2481] = true }

local function Secret(v) return ns.IsSecret(v) end

local function Clean(text)
	text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	text = text:gsub("|T.-|t", ""):gsub("|A.-|a", "")
	return strtrim(text)
end

local function Supported()
	return Minimap.UpdateMouseoverAtPoint and Minimap.SetUsingSoftCursor
		and C_TooltipInfo and C_TooltipInfo.GetMinimapMouseover and true or false
end

-- Is one of the finders on? true when the game does not say.
local function FinderOn()
	if not (C_Minimap and C_Minimap.GetNumTrackingTypes and C_Minimap.GetTrackingInfo) then return true end
	for index = 1, C_Minimap.GetNumTrackingTypes() do
		local info = C_Minimap.GetTrackingInfo(index)
		if Secret(info) then return true end
		if type(info) == "table" then
			if Secret(info.active) or Secret(info.spellID) then return true end
			if info.active and info.spellID and FINDERS[info.spellID] then return true end
		end
	end
	return false
end

local function IsMoving()
	if IsPlayerMoving then return IsPlayerMoving() end
	return (GetUnitSpeed("player") or 0) > 0
end

-- Why a scan cannot run now, or nil.
function A:Blocker()
	if not Supported() then return L.ALERT_WHY_API end
	if InCombatLockdown() then return L.ALERT_WHY_COMBAT end
	if not (Minimap:IsVisible() and Minimap:GetLeft()) then return L.ALERT_WHY_HIDDEN end
	return nil
end

---------------------------------------------------------------------------
-- Scan
---------------------------------------------------------------------------

function A:Grid()
	local width, height = Minimap:GetWidth(), Minimap:GetHeight()
	if self.gridW == width and self.gridH == height then return self.grid end
	local grid = {}
	for x = STEP / 2, width, STEP do
		for y = STEP / 2, height, STEP do
			grid[#grid + 1] = { x, y }
		end
	end
	self.grid, self.gridW, self.gridH = grid, width, height
	return grid
end

function A:StartScan(debug)
	self.scan = { points = self:Grid(), next = 1, hits = {}, order = {}, debug = debug }
end

function A:Record(text, x, y)
	local scan = self.scan
	for line in text:gmatch("[^\n]+") do
		local name = Clean(line)
		if name ~= "" then
			local hit = scan.hits[name]
			if not hit then
				hit = { x = 0, y = 0, n = 0 }
				scan.hits[name] = hit
				scan.order[#scan.order + 1] = name
			end
			hit.x, hit.y, hit.n = hit.x + x, hit.y + y, hit.n + 1
		end
	end
end

function A:Probe(left, bottom, scale, x, y)
	Minimap:UpdateMouseoverAtPoint((left + x) * scale, (bottom + y) * scale)
	local data = C_TooltipInfo.GetMinimapMouseover()
	if not data or Secret(data) then return end
	local lines = data.lines
	if not lines or Secret(lines) then return end
	for _, line in ipairs(lines) do
		local text = line.leftText
		if type(text) == "string" and not Secret(text) then self:Record(text, x, y) end
	end
end

-- Probes the next chunk of the grid; the soft cursor is on only while probing.
function A:ScanSome()
	local scan = self.scan
	local left, bottom = Minimap:GetLeft(), Minimap:GetBottom()
	if not (left and bottom and Minimap:IsVisible()) or InCombatLockdown() then
		self.scan = nil
		return
	end
	local scale = Minimap:GetEffectiveScale()
	local points = scan.points
	local last = math.min(scan.next + PER_FRAME - 1, #points)
	Minimap:SetUsingSoftCursor(true)
	local ok, err = pcall(function()
		for i = scan.next, last do
			self:Probe(left, bottom, scale, points[i][1], points[i][2])
		end
	end)
	Minimap:SetUsingSoftCursor(false)
	if not ok then
		self.scan = nil
		error(err, 0)
	end
	scan.next = last + 1
	if scan.next > #points then
		self.scan = nil
		self:Finish(scan)
	end
end

---------------------------------------------------------------------------
-- Results
---------------------------------------------------------------------------

local DIRECTIONS = { "E", "NE", "N", "NW", "W", "SW", "S", "SE" }

local function Direction(hit)
	local half = math.min(Minimap:GetWidth(), Minimap:GetHeight()) / 2
	local x = hit.x / hit.n - Minimap:GetWidth() / 2
	local y = hit.y / hit.n - Minimap:GetHeight() / 2
	if x * x + y * y < (half / 4) ^ 2 then return L.ALERT_DIR_NEAR end
	local angle = math.deg(math.atan2(y, x)) % 360
	return L["ALERT_DIR_" .. DIRECTIONS[math.floor((angle + 22.5) / 45) % 8 + 1]]
end

local function GroupNames()
	local names = {}
	local function Add(unit)
		local name = UnitName(unit)
		if name and not Secret(name) then names[name] = true end
	end
	Add("player")
	Add("pet")
	local prefix, count = "party", 4
	if IsInRaid and IsInRaid() then prefix, count = "raid", 40 end
	for i = 1, count do
		Add(prefix .. i)
		Add(prefix .. "pet" .. i)
	end
	return names
end

-- Why a name is not reported, or nil.
function A:Skip(name, group)
	if group[name] then return L.ALERT_TEST_GROUP end
	-- Quest progress ("Peacebloom 3/8", "Copper: 2") is no node.
	if name:find("[%d:/]") then return L.ALERT_TEST_QUEST end
	local db = ns.db.alert
	local lower = name:lower()
	for _, entry in ipairs(db.ignore) do
		if lower:find(entry:lower(), 1, true) then return L.ALERT_TEST_FILTERED end
	end
	if db.filter == "LIST" then
		for _, entry in ipairs(db.names) do
			if lower:find(entry:lower(), 1, true) then return nil end
		end
		return L.ALERT_TEST_FILTERED
	end
	return nil
end

function A:Finish(scan)
	local db = ns.db.alert
	local now = GetTime()
	local group = GroupNames()
	if scan.debug then
		ns.Print(L.ALERT_TEST_DONE:format(#scan.points, #scan.order))
		if not FinderOn() then ns.Print(L.ALERT_WHY_FINDER) end
		for _, name in ipairs(scan.order) do
			local why = self:Skip(name, group)
			print(("  |cffffd100%s|r (%s)%s"):format(name, Direction(scan.hits[name]), why and " - " .. why or ""))
		end
	end
	local hits = {}
	for _, name in ipairs(scan.order) do
		if not self:Skip(name, group) then
			local last = self.seen[name]
			if not last or now - last > db.repeatAfter then
				hits[#hits + 1] = ("%s (%s)"):format(name, Direction(scan.hits[name]))
			end
			self.seen[name] = now
		end
	end
	if #hits > 0 and (db.enabled or scan.debug) then self:Announce(hits) end
end

function A:Announce(hits)
	local db = ns.db.alert
	local text = L.ALERT_FOUND:format(table.concat(hits, ", "))
	local sound = SOUND_IDS[db.sound]
	if sound then PlaySound(sound, "Master") end
	if db.screen then
		if RaidNotice_AddMessage and RaidWarningFrame then
			RaidNotice_AddMessage(RaidWarningFrame, text, ChatTypeInfo and ChatTypeInfo.RAID_WARNING or { r = 1, g = 0.82, b = 0 })
		else
			UIErrorsFrame:AddMessage(text, 1, 0.82, 0)
		end
	end
	if db.chat then ns.Print(text) end
end

---------------------------------------------------------------------------
-- Timer and commands
---------------------------------------------------------------------------

function A:Init()
	self.seen = {}
	-- 1.1.0 test builds moved the map under the cursor and had these settings.
	ns.db.alert.mode, ns.db.alert.frames = nil, nil
	local f = CreateFrame("Frame")
	local elapsed = 0
	f:SetScript("OnUpdate", function(_, dt)
		if self.scan then
			local ok, err = pcall(self.ScanSome, self)
			if not ok then geterrorhandler()(err) end
			return
		end
		local db = ns.db.alert
		if not db.enabled then return end
		elapsed = elapsed + dt
		if elapsed < db.interval then return end
		elapsed = 0
		if db.onlyMoving and not IsMoving() then return end
		if self:Blocker() or not FinderOn() then return end
		self:StartScan(false)
	end)
	self.frame = f
end

function A:Apply()
	if not ns.db.alert.enabled and self.scan and not self.scan.debug then self.scan = nil end
end

-- One scan with a report in the chat, whether the alert is on or not.
function A:Test()
	local why = self:Blocker()
	if why then
		ns.Print(L.ALERT_TEST_BLOCKED:format(why))
		return
	end
	self:StartScan(true)
end

-- Diagnosis for "/mundi alert debug": three seconds after the command, with the real mouse resting on a
-- dot, prints what the minimap answers for the real mouse and for virtual probes at the same spot.
local function Lines(data)
	if data == nil then return "nil" end
	if Secret(data) then return "secret" end
	local lines = data.lines
	if not lines then return "no lines" end
	if Secret(lines) then return "secret lines" end
	local out = {}
	for _, line in ipairs(lines) do
		local text = line.leftText
		out[#out + 1] = Secret(text) and "secret" or tostring(text):gsub("\n", " / ")
	end
	return #out > 0 and table.concat(out, " | ") or "0 lines"
end

function A:Debug()
	ns.Print(L.ALERT_DEBUG_START)
	C_Timer.After(3, function()
		local p = function(...) print("  |cffffd100Mundi|r", ...) end
		p("API:", tostring(Minimap.UpdateMouseoverAtPoint ~= nil), tostring(Minimap.SetUsingSoftCursor ~= nil),
			tostring(C_TooltipInfo and C_TooltipInfo.GetMinimapMouseover ~= nil), "finder:", tostring(FinderOn()))
		local left, bottom = Minimap:GetLeft(), Minimap:GetBottom()
		local scale = Minimap:GetEffectiveScale()
		p(("map left %.1f bottom %.1f size %.1f x %.1f scale %.3f ui %.3f"):format(left or -1, bottom or -1,
			Minimap:GetWidth(), Minimap:GetHeight(), scale, UIParent:GetEffectiveScale()))
		local cx, cy = GetCursorPosition()
		local lx, ly = cx / scale - (left or 0), cy / scale - (bottom or 0)
		p(("cursor %.1f, %.1f -> map %.1f, %.1f  over map: %s"):format(cx, cy, lx, ly, tostring(Minimap:IsMouseOver())))
		p("real mouse:", Lines(C_TooltipInfo.GetMinimapMouseover()))
		local shown = GameTooltip:IsShown() and _G.GameTooltipTextLeft1 and _G.GameTooltipTextLeft1:GetText()
		p("GameTooltip:", shown and not Secret(shown) and tostring(shown):gsub("\n", " / ") or "-")
		if not Minimap.UpdateMouseoverAtPoint then return end
		local function Try(label, x, y, soft)
			if soft then Minimap:SetUsingSoftCursor(true) end
			local ok, err = pcall(Minimap.UpdateMouseoverAtPoint, Minimap, x, y)
			local now = ok and Lines(C_TooltipInfo.GetMinimapMouseover()) or ("error " .. tostring(err))
			if soft then Minimap:SetUsingSoftCursor(false) end
			p(label, now)
		end
		Try("probe soft (cursor):", cx, cy, true)
		Try("probe hard (cursor):", cx, cy, false)
		Try("probe soft (ui units):", cx / UIParent:GetEffectiveScale(), cy / UIParent:GetEffectiveScale(), true)
		Try("probe soft (map local):", lx, ly, true)
		-- Some answers only arrive a frame later.
		Minimap:SetUsingSoftCursor(true)
		Minimap:UpdateMouseoverAtPoint(cx, cy)
		C_Timer.After(0, function()
			p("probe soft, next frame:", Lines(C_TooltipInfo.GetMinimapMouseover()))
			Minimap:SetUsingSoftCursor(false)
		end)
	end)
end

local function FindEntry(list, name)
	local lower = name:lower()
	for i, entry in ipairs(list) do
		if entry:lower() == lower then return i end
	end
end

function A:Command(rest)
	local db = ns.db.alert
	local sub, arg = strtrim(rest or ""):match("^(%S*)%s*(.-)$")
	sub = (sub or ""):lower()
	arg = strtrim(arg or "")
	local list = (sub == "ignore" or sub == "unignore") and db.ignore or db.names
	if sub == "" or sub == "on" or sub == "off" then
		if sub == "" then db.enabled = not db.enabled else db.enabled = sub == "on" end
		ns.Print(db.enabled and L.ALERT_ON or L.ALERT_OFF)
		ns:ApplyAll()
		if ns.options and ns.options.Refresh then ns.options:Refresh() end
	elseif (sub == "add" or sub == "ignore") and arg ~= "" then
		if not FindEntry(list, arg) then list[#list + 1] = arg end
		ns.Print((sub == "add" and L.ALERT_ADDED or L.ALERT_IGNORED):format(arg))
		if sub == "add" and db.filter ~= "LIST" then ns.Print(L.ALERT_LIST_HINT) end
	elseif (sub == "remove" or sub == "unignore") and arg ~= "" then
		local i = FindEntry(list, arg)
		if i then table.remove(list, i) end
		ns.Print((i and L.ALERT_REMOVED or L.ALERT_NOT_FOUND):format(arg))
	elseif sub == "list" then
		ns.Print(L.ALERT_LIST:format(#db.names > 0 and table.concat(db.names, ", ") or L.ALERT_EMPTY))
		ns.Print(L.ALERT_IGNORE_LIST:format(#db.ignore > 0 and table.concat(db.ignore, ", ") or L.ALERT_EMPTY))
	elseif sub == "test" then
		self:Test()
	elseif sub == "debug" then
		self:Debug()
	else
		ns.Print(L.ALERT_HELP_TITLE)
		for _, c in ipairs({
			{ "", L.ALERT_CMD_TOGGLE },
			{ " add <Name>", L.ALERT_CMD_ADD },
			{ " remove <Name>", L.ALERT_CMD_REMOVE },
			{ " ignore <Name>", L.ALERT_CMD_IGNORE },
			{ " unignore <Name>", L.ALERT_CMD_UNIGNORE },
			{ " list", L.ALERT_CMD_LIST },
			{ " test", L.ALERT_CMD_TEST },
			{ " debug", L.ALERT_CMD_DEBUG },
		}) do
			print(("  |cffffd100/mundi alert%s|r - %s"):format(c[1], c[2]))
		end
	end
end

ns:RegisterModule("alert", A)
