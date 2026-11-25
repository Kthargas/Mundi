local ADDON, ns = ...
local L = ns.L

-- Extras on top of the Blizzard minimap: who pinged, instance info, north marker while rotating,
-- auto zoom out, fading header, combat opacity and mouse button actions.

local E = {}
ns:RegisterModule("extras", E)

local function OverlayLevel()
	local border = ns.map and ns.map.border
	return (border and border:GetFrameLevel() or Minimap:GetFrameLevel()) + 4
end

---------------------------------------------------------------------------
-- Instance info (Forever has no Blizzard difficulty banner on the minimap)
---------------------------------------------------------------------------

function E:CreateInstanceInfo()
	local f = CreateFrame("Frame", nil, Minimap)
	f:SetSize(60, 28)
	f:SetPoint("TOPLEFT", Minimap, "TOPLEFT", 6, -5)
	f:EnableMouse(true)
	local size = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	size:SetPoint("TOPLEFT")
	local diff = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	diff:SetPoint("TOPLEFT", size, "BOTTOMLEFT", 0, -1)
	f.size, f.diff = size, diff
	f:SetScript("OnEnter", function(self)
		local name, instanceType, _, difficultyName, maxPlayers = GetInstanceInfo()
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
		GameTooltip_SetTitle(GameTooltip, name)
		if difficultyName and difficultyName ~= "" then GameTooltip:AddLine(difficultyName, 1, 1, 1) end
		if maxPlayers and maxPlayers > 0 then
			GameTooltip:AddLine(L.MAX_PLAYERS:format(maxPlayers), 1, 1, 1)
		end
		GameTooltip:Show()
	end)
	f:SetScript("OnLeave", GameTooltip_Hide)
	f:Hide()
	self.instance = f
end

function E:UpdateInstanceInfo()
	local f = self.instance
	if not f then return end
	local inInstance, kind = IsInInstance()
	if not ns.db.map.showInstance or not inInstance or (kind ~= "party" and kind ~= "raid") then
		f:Hide()
		return
	end
	local _, _, difficultyID, difficultyName, maxPlayers = GetInstanceInfo()
	f.size:SetText(maxPlayers and maxPlayers > 0 and tostring(maxPlayers) or "")
	local short = difficultyName or ""
	local isHeroic = false
	if difficultyID and GetDifficultyInfo then
		local _, _, heroic, _, displayHeroic = GetDifficultyInfo(difficultyID)
		isHeroic = heroic or displayHeroic
	end
	if isHeroic then
		short = L.DIFF_HEROIC
		f.size:SetTextColor(1, 0.5, 0.25)
	else
		f.size:SetTextColor(NORMAL_FONT_COLOR:GetRGB())
	end
	f.diff:SetText(short)
	f:SetFrameLevel(OverlayLevel())
	f:Show()
end

---------------------------------------------------------------------------
-- North marker while the minimap rotates
---------------------------------------------------------------------------

function E:CreateCompass()
	local f = CreateFrame("Frame", nil, Minimap)
	f:SetSize(16, 16)
	local text = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	text:SetPoint("CENTER")
	text:SetText(COMPASS_NORTH or "N")
	f:Hide()
	local elapsed = 0
	f:SetScript("OnUpdate", function(self, dt)
		elapsed = elapsed + dt
		if elapsed < 0.02 then return end
		elapsed = 0
		local facing = GetPlayerFacing and GetPlayerFacing()
		if not facing or ns.IsSecret(facing) then
			text:Hide()
			return
		end
		text:Show()
		-- facing: 0 = north, counter-clockwise. On a rotating map the player looks up,
		-- so north sits at "facing" radians clockwise from the top.
		local x, y = math.sin(facing), math.cos(facing)
		local half = Minimap:GetWidth() / 2 - 9
		local m = math.max(math.abs(x), math.abs(y))
		self:ClearAllPoints()
		self:SetPoint("CENTER", Minimap, "CENTER", x / m * half, y / m * half)
	end)
	self.compass = f
end

function E:UpdateCompass()
	local show = ns.db.map.compass and GetCVarBool("rotateMinimap")
	self.compass:SetFrameLevel(OverlayLevel())
	self.compass:SetShown(show)
end

---------------------------------------------------------------------------
-- Auto zoom out
---------------------------------------------------------------------------

function E:OnZoomChanged()
	if self.zoomTimer then
		self.zoomTimer:Cancel()
		self.zoomTimer = nil
	end
	local delay = ns.db.map.autoZoom or 0
	if delay <= 0 or Minimap:GetZoom() == 0 then return end
	self.zoomTimer = C_Timer.NewTimer(delay, function()
		self.zoomTimer = nil
		if Minimap:GetZoom() > 0 then
			Minimap:SetZoom(0)
			if Minimap.ZoomOut then Minimap.ZoomOut:Disable() end
			if Minimap.ZoomIn then Minimap.ZoomIn:Enable() end
		end
	end)
end

---------------------------------------------------------------------------
-- Header fade and combat opacity
---------------------------------------------------------------------------

local function HeaderFrames()
	local cluster = MinimapCluster
	return {
		cluster.ZoneTextButton,
		cluster.Tracking,
		-- A clock that is not one of the header's text fields stays invisible.
		(not ns.map or ns.map.clockUsed ~= false) and _G.TimeManagerClockButton or false,
		_G.GameTimeFrame,
		_G.AddonCompartmentFrame,
		cluster.InstanceDifficulty,
	}
end

function E:CreateFader()
	local f = CreateFrame("Frame")
	local alpha, elapsed = 1, 0
	f:SetScript("OnUpdate", function(_, dt)
		elapsed = elapsed + dt
		if elapsed < 0.05 then return end
		local step = elapsed * 4
		elapsed = 0
		local over = MinimapCluster:IsMouseOver() or Minimap:IsMouseOver()
			or (ns.collector and ns.collector:IsWindowMouseOver())
		local target = over and 1 or 0
		if alpha == target then return end
		if alpha < target then
			alpha = math.min(target, alpha + step)
		else
			alpha = math.max(target, alpha - step)
		end
		for _, frame in ipairs(HeaderFrames()) do
			if frame then frame:SetAlpha(alpha) end
		end
	end)
	f.Reset = function()
		alpha = 1
		for _, frame in ipairs(HeaderFrames()) do
			if frame then frame:SetAlpha(1) end
		end
	end
	f:Hide()
	self.fader = f
end

function E:UpdateFader()
	if ns.db.map.headerFade then
		self.fader:Show()
	else
		self.fader:Hide()
		self.fader.Reset()
	end
end

function E:UpdateCombatAlpha(inCombat)
	if inCombat == nil then inCombat = InCombatLockdown() or UnitAffectingCombat("player") end
	MinimapCluster:SetAlpha(inCombat and ns.db.map.combatAlpha or 1)
end

---------------------------------------------------------------------------
-- Mouse buttons on the map
---------------------------------------------------------------------------

E.ACTIONS = {
	{ key = "PING", label = L.ACTION_PING },
	{ key = "TRACKING", label = L.ACTION_TRACKING },
	{ key = "CALENDAR", label = L.ACTION_CALENDAR },
	{ key = "COLLECTOR", label = L.ACTION_COLLECTOR },
	{ key = "OPTIONS", label = L.ACTION_OPTIONS },
	{ key = "LAYOUT", label = L.ACTION_LAYOUT },
	{ key = "NONE", label = L.ACTION_NONE },
}

function E:RunAction(action)
	if action == "TRACKING" then
		-- The tracking ("search") menu of the header button, the same menu a click on that button opens.
		local tracking = MinimapCluster.Tracking and MinimapCluster.Tracking.Button
		if tracking and tracking.OpenMenu then
			if tracking.IsMenuOpen and tracking:IsMenuOpen() then
				tracking:CloseMenu()
			else
				tracking:OpenMenu()
			end
			return true
		end
	elseif action == "CALENDAR" then
		if ToggleCalendar then
			ToggleCalendar()
			return true
		end
	elseif action == "OPTIONS" then
		ns.OpenOptions()
		return true
	elseif action == "LAYOUT" then
		if ns.layout then
			ns.layout:Toggle()
			return true
		end
	elseif action == "COLLECTOR" then
		if ns.collector then
			ns.collector:Toggle()
			return true
		end
	elseif action == "NONE" then
		return true
	end
	return false
end

function E:HookClicks()
	-- Only hook, never replace Blizzard's handler: a replaced script would run the ping from addon code.
	-- Blizzard pings on every mouse button; the chosen action runs in addition.
	ns.Trace("extras:Minimap:HookScript(OnMouseUp)")
	Minimap:HookScript("OnMouseUp", function(_, button)
		local action
		if button == "RightButton" then
			action = ns.db.map.rightClick
		elseif button == "MiddleButton" then
			action = ns.db.map.middleClick
		end
		if action and action ~= "PING" then
			E:RunAction(action)
		end
	end)
end

---------------------------------------------------------------------------

function E:Init()
	self:CreateInstanceInfo()
	self:CreateCompass()
	self:CreateFader()
	self:HookClicks()

	local f = CreateFrame("Frame")
	f:RegisterEvent("MINIMAP_UPDATE_ZOOM")
	f:RegisterEvent("PLAYER_ENTERING_WORLD")
	f:RegisterEvent("ZONE_CHANGED_NEW_AREA")
	f:RegisterEvent("PLAYER_DIFFICULTY_CHANGED")
	f:RegisterEvent("PLAYER_REGEN_DISABLED")
	f:RegisterEvent("PLAYER_REGEN_ENABLED")
	f:SetScript("OnEvent", function(_, event, ...)
		if event == "MINIMAP_UPDATE_ZOOM" then
			E:OnZoomChanged()
		elseif event == "PLAYER_REGEN_DISABLED" then
			E:UpdateCombatAlpha(true)
		elseif event == "PLAYER_REGEN_ENABLED" then
			E:UpdateCombatAlpha(false)
		else
			E:UpdateInstanceInfo()
		end
	end)

	-- No MINIMAP_PING listener: in this client the ping callback is reserved for Blizzard code, and
	-- registering it from an addon is a forbidden action (the "blocked from an action" popup).

	if CVarCallbackRegistry and CVarCallbackRegistry.RegisterCallback then
		CVarCallbackRegistry:RegisterCallback("rotateMinimap", function() E:UpdateCompass() end, E)
	end
	EventRegistry:RegisterCallback("SquareMap.LayoutChanged", function()
		E:UpdateCompass()
		E:UpdateInstanceInfo()
	end, E)
	self.ready = true
end

function E:Apply()
	if not self.ready then return end
	self:UpdateInstanceInfo()
	self:UpdateCompass()
	self:UpdateFader()
	self:UpdateCombatAlpha()
	self:OnZoomChanged()
end
