local ADDON, ns = ...
local L = ns.L

-- Resource alert: a sound and a message when the minimap shows a herb, an ore or anything else the
-- tracking finds.
--
-- The game has no API for the tracking blips on the minimap. The only thing that names them is the
-- minimap's own tooltip, and that needs the mouse over the blip. Addons cannot move the mouse, so the
-- map comes to the mouse instead: for a few frames it is made invisible and moved so that one spot after
-- the other sits under the cursor, and the tooltip of each frame is read. Afterwards everything is put
-- back. This is the same trick other alert addons use, and the reason the map blinks for a moment.
--
-- Fast mode shrinks the map while it scans. The minimap always shows the whole tracking range, whatever
-- its size, while the blips keep their size, so on a small map a few samples cover all of it. Thorough
-- mode scans the map at its real size, which takes many more frames.

local A = {}

A.SOUNDS = {
	{ key = "NONE", label = L.ALERT_SOUND_NONE },
	{ key = "RAID_WARNING", label = L.ALERT_SOUND_RAID },
	{ key = "READY_CHECK", label = L.ALERT_SOUND_READY },
	{ key = "TELL_MESSAGE", label = L.ALERT_SOUND_WHISPER },
	{ key = "MAP_PING", label = L.ALERT_SOUND_PING },
}
local SOUND_IDS = { RAID_WARNING = 8959, READY_CHECK = 8960, TELL_MESSAGE = 3081, MAP_PING = 3175 }

local FAST_SIZE, FAST_STEP = 36, 12
local FULL_STEP = 16

local function Clean(text)
	text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	text = text:gsub("|T.-|t", ""):gsub("|A.-|a", "")
	return strtrim(text)
end

local function Lower(text)
	return text:lower()
end

-- Grid of spots (offsets from the map centre) that one pass puts under the cursor, centre first.
local function Grid(size, step)
	local n = math.max(1, math.ceil(size / step))
	local points = {}
	for row = 0, n - 1 do
		for col = 0, n - 1 do
			local x = -size / 2 + step * (col + 0.5)
			local y = -size / 2 + step * (row + 0.5)
			points[#points + 1] = { x, y }
		end
	end
	table.sort(points, function(a, b) return a[1] * a[1] + a[2] * a[2] < b[1] * b[1] + b[2] * b[2] end)
	return points
end

local function MouseFocus()
	if GetMouseFoci then
		local foci = GetMouseFoci()
		return foci and foci[1]
	end
	return GetMouseFocus and GetMouseFocus()
end

local function IsMoving()
	if IsPlayerMoving then return IsPlayerMoving() end
	return (GetUnitSpeed("player") or 0) > 0
end

-- Why a pass cannot run now, or nil.
function A:Blocker()
	if InCombatLockdown() or UnitAffectingCombat("player") then return L.ALERT_WHY_COMBAT end
	if UnitIsDeadOrGhost("player") then return L.ALERT_WHY_DEAD end
	if not Minimap:IsVisible() then return L.ALERT_WHY_HIDDEN end
	if IsMouselooking and IsMouselooking() then return L.ALERT_WHY_MOUSE end
	if (SpellIsTargeting and SpellIsTargeting()) or (GetCursorInfo and GetCursorInfo()) then return L.ALERT_WHY_MOUSE end
	-- Only while the cursor rests on the 3D world: over a window, a button or a unit (tooltip) the
	-- scan would take the tooltip away from you.
	if MouseFocus() ~= WorldFrame or GameTooltip:IsShown() then return L.ALERT_WHY_MOUSE end
	return nil
end

---------------------------------------------------------------------------
-- One pass
---------------------------------------------------------------------------

function A:Place(index)
	local spot = self.points[index]
	local x, y = GetCursorPosition()
	local scale = Minimap:GetEffectiveScale()
	Minimap:ClearAllPoints()
	-- The spot at (dx, dy) from the centre lands under the cursor.
	Minimap:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale - spot[1], y / scale - spot[2])
end

function A:Read(index)
	if not GameTooltip:IsShown() then return end
	local spot = self.points[index]
	for n = 1, GameTooltip:NumLines() do
		local fs = _G["GameTooltipTextLeft" .. n]
		local text = fs and fs:GetText()
		if type(text) == "string" and not ns.IsSecret(text) then
			for line in (text:gsub("|n", "\n") .. "\n"):gmatch("(.-)\n") do
				local name = Clean(line)
				if name ~= "" and not self.found[name] then
					self.found[name] = spot
					self.order[#self.order + 1] = name
				end
			end
		end
	end
	if self.debug then
		local owner = GameTooltip:GetOwner()
		self.debugOwner = owner and (owner:GetName() or tostring(owner)) or "-"
	end
end

function A:StartPass(debug)
	local db = ns.db.alert
	self.saved = { points = {}, width = Minimap:GetWidth(), height = Minimap:GetHeight(), alpha = Minimap:GetAlpha(), tipAlpha = GameTooltip:GetAlpha() }
	for i = 1, Minimap:GetNumPoints() do
		self.saved.points[i] = { Minimap:GetPoint(i) }
	end
	if db.mode == "FULL" then
		self.size = math.min(self.saved.width, self.saved.height)
		self.points = Grid(self.size, FULL_STEP)
	else
		self.size = FAST_SIZE
		self.points = Grid(FAST_SIZE, FAST_STEP)
		Minimap:SetSize(FAST_SIZE, FAST_SIZE)
	end
	self.found, self.order = {}, {}
	self.debug = debug
	self.index, self.wait = 1, math.max(1, db.frames or 1)
	self.scanning = true
	ns.alertScanning = true
	Minimap:SetAlpha(0)
	GameTooltip:SetAlpha(0)
	self:Place(1)
end

-- Put the map back exactly as it was. Safe to call at any time.
function A:Restore()
	local saved = self.saved
	self.scanning = false
	ns.alertScanning = false
	if not saved then return end
	self.saved = nil
	Minimap:SetSize(saved.width, saved.height)
	Minimap:ClearAllPoints()
	for _, p in ipairs(saved.points) do
		Minimap:SetPoint(p[1], p[2], p[3], p[4], p[5])
	end
	Minimap:SetAlpha(saved.alpha)
	GameTooltip:Hide()
	GameTooltip:SetAlpha(saved.tipAlpha)
end

-- Runs every frame while a pass is going on: read the tooltip of the last spot, move to the next one.
function A:Step()
	self.wait = self.wait - 1
	if self.wait > 0 then return end
	self:Read(self.index)
	self.index = self.index + 1
	if self.index > #self.points then
		self:Restore()
		self:Finish()
		return
	end
	self.wait = math.max(1, ns.db.alert.frames or 1)
	self:Place(self.index)
end

---------------------------------------------------------------------------
-- Results
---------------------------------------------------------------------------

local DIRECTIONS = { "E", "NE", "N", "NW", "W", "SW", "S", "SE" }

function A:Direction(spot)
	local x, y = spot[1], spot[2]
	if x * x + y * y < (self.size / 6) ^ 2 then return L.ALERT_DIR_NEAR end
	local angle = math.deg(math.atan2(y, x)) % 360
	local index = math.floor((angle + 22.5) / 45) % 8 + 1
	return L["ALERT_DIR_" .. DIRECTIONS[index]]
end

local function GroupNames()
	local names = {}
	local me = UnitName("player")
	if me then names[me] = true end
	local prefix, count = "party", 4
	if IsInRaid and IsInRaid() then prefix, count = "raid", 40 end
	for i = 1, count do
		local name = UnitName(prefix .. i)
		if name then names[name] = true end
		local pet = UnitName(prefix .. "pet" .. i)
		if pet then names[pet] = true end
	end
	local pet = UnitName("pet")
	if pet then names[pet] = true end
	return names
end

function A:Matches(name)
	local db = ns.db.alert
	local lower = Lower(name)
	for _, entry in ipairs(db.ignore) do
		if lower:find(Lower(entry), 1, true) then return false end
	end
	if db.filter == "LIST" then
		for _, entry in ipairs(db.names) do
			if lower:find(Lower(entry), 1, true) then return true end
		end
		return false
	end
	return true
end

function A:Finish()
	local db = ns.db.alert
	local now = GetTime()
	local group = GroupNames()
	if self.debug then
		ns.Print(L.ALERT_TEST_DONE:format(#self.points, #self.order, self.debugOwner or "-"))
		for _, name in ipairs(self.order) do
			local note = group[name] and L.ALERT_TEST_GROUP or (self:Matches(name) and "" or L.ALERT_TEST_FILTERED)
			print(("  |cffffd100%s|r (%s)%s"):format(name, self:Direction(self.found[name]), note))
		end
		self.debug, self.debugOwner = nil, nil
	end
	local hits = {}
	for _, name in ipairs(self.order) do
		if not group[name] and self:Matches(name) then
			local last = self.seen[name]
			if not last or now - last > db.repeatAfter then
				hits[#hits + 1] = ("%s (%s)"):format(name, self:Direction(self.found[name]))
			end
			self.seen[name] = now
		end
	end
	if #hits > 0 then self:Announce(hits) end
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
	local f = CreateFrame("Frame")
	local elapsed = 0
	f:SetScript("OnUpdate", function(_, dt)
		if self.scanning then
			local ok, err = pcall(self.Step, self)
			if not ok then
				self:Restore()
				geterrorhandler()(err)
			end
			return
		end
		local db = ns.db.alert
		if not db.enabled and not self.testPending then return end
		elapsed = elapsed + dt
		if elapsed < (self.testPending and 0 or db.interval) then return end
		if not self.testPending and db.onlyMoving and not IsMoving() then return end
		elapsed = 0
		local why = self:Blocker()
		if why then
			if self.testPending and GetTime() > self.testPending then
				self.testPending = nil
				ns.Print(L.ALERT_TEST_BLOCKED:format(why))
			end
			return
		end
		local debug = self.testPending ~= nil
		self.testPending = nil
		local ok, err = pcall(self.StartPass, self, debug)
		if not ok then
			self:Restore()
			geterrorhandler()(err)
		end
	end)
	f:RegisterEvent("PLAYER_REGEN_DISABLED")
	f:SetScript("OnEvent", function() if self.scanning then self:Restore() end end)
	self.frame = f
end

function A:Apply()
	if self.scanning and not ns.db.alert.enabled then self:Restore() end
end

-- One pass with a report in the chat, whether the alert is on or not.
function A:Test()
	self.testPending = GetTime() + 5
	ns.Print(L.ALERT_TEST_START)
end

local function FindEntry(list, name)
	local lower = Lower(name)
	for i, entry in ipairs(list) do
		if Lower(entry) == lower then return i end
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
	elseif sub == "frames" and tonumber(arg) then
		db.frames = math.max(1, math.min(5, math.floor(tonumber(arg))))
		ns.Print(L.ALERT_FRAMES:format(db.frames))
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
		}) do
			print(("  |cffffd100/mundi alert%s|r - %s"):format(c[1], c[2]))
		end
	end
end

ns:RegisterModule("alert", A)
