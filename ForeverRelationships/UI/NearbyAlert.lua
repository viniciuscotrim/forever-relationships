-- Nearby alert: a pop-up when someone you have history with comes into view
-- (nameplates reach farthest; mouseover and target count too). Movable: drag it
-- anywhere, the position is saved. On by default (nearby.alert); rivals you fought
-- have their own switch (nearby.alertRivals). One alert per player per
-- nearby.alertCooldownMinutes. Never in instances, never for your own group.
local _, FR = ...
local UI = FR.UI
local L = FR.L

local Alert = { last = {} }
UI.NearbyAlert = Alert

local WIDTH, HEIGHT = 330, 86

local function Clock() return GetTime and GetTime() or 0 end

local function InInstance()
  local _, instanceType = GetInstanceInfo()
  return instanceType == "party" or instanceType == "raid" or instanceType == "pvp" or instanceType == "arena"
end

local function SavePosition(f)
  local point, _, relPoint, x, y = f:GetPoint()
  FR.db.ui = FR.db.ui or {}
  if point then FR.db.ui.alertPos = { point, relPoint, math.floor(x or 0), math.floor(y or 0) } end
end

local function RestorePosition(f)
  f:ClearAllPoints()
  local p = FR.db.ui and FR.db.ui.alertPos
  if type(p) == "table" and p[1] then f:SetPoint(p[1], UIParent, p[2], p[3], p[4])
  else f:SetPoint("TOP", UIParent, "TOP", 0, -180) end
end

function Alert:Build()
  if self.frame then return self.frame end
  local f = CreateFrame("Frame", "ForeverRelationshipsNearbyAlert", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  f:SetSize(WIDTH, HEIGHT)
  f:SetFrameStrata("DIALOG")
  if f.SetBackdrop then
    f:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = true, tileSize = 16, edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
    if f.SetBackdropBorderColor then f:SetBackdropBorderColor(0.91, 0.73, 0.29) end
  end
  f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton"); f:SetClampedToScreen(true)
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); SavePosition(self) end)
  f.title = UI.Label(f, "", "GameFontNormal"); f.title:SetPoint("TOPLEFT", 12, -10)
  f.name = UI.Label(f, "", "GameFontHighlightLarge"); f.name:SetPoint("TOPLEFT", 12, -28); f.name:SetWidth(WIDTH - 24)
  f.line = UI.Label(f, "", "GameFontHighlightSmall"); f.line:SetPoint("TOPLEFT", 12, -50); f.line:SetWidth(WIDTH - 24); f.line:SetWordWrap(true)
  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 0, 0)
  close:SetScript("OnClick", function() f:Hide() end)
  f.open = UI.Button(f, L["Open"], 70, 18, function()
    if f.guid then UI:OpenPlayer(f.guid) end
    f:Hide()
  end)
  f.open:SetPoint("BOTTOMRIGHT", -10, 8)
  UI.Tooltip(f, L["Forever Relationships"], { L["Drag to move. The position is saved."], L["Turn it off in Privacy › Settings (nearby.alert)."] })
  f:Hide()
  RestorePosition(f)
  self.frame = f
  return f
end

-- What we know about guid, or nil if there is no history worth an alert.
function Alert:Describe(guid)
  local p = FR.db.players[guid]
  if p then
    local r = FR.Rel:Compute(guid)
    if r.sessions > 0 or r.trades > 0 then
      local bits = { L["%s together"]:format(FR.FormatDuration(r.seconds)) }
      if r.dungeons + r.raids > 0 then bits[#bits + 1] = FR.Plural(r.dungeons + r.raids, "%d completion", "%d completions") end
      if r.last then bits[#bits + 1] = L["last %s"]:format(FR.FormatAgo(r.last)) end
      return { kind = "friend", name = p.name, class = p.class, level = p.level, line = table.concat(bits, " · ") }
    end
  end
  local rv = FR.Rivals and FR.Rivals:Get(guid)
  if rv and rv.battles > 0 and FR.Params:Get("nearby.alertRivals") then
    return { kind = "rival", name = rv.name, class = rv.class, level = rv.level, line = FR.Rivals:Summary(rv) }
  end
  return nil
end

function Alert:Show(guid, info)
  local f = self:Build()
  f.guid = guid
  f.title:SetText(info.kind == "rival" and ("|cffff5555" .. L["Rival nearby"] .. "|r") or (UI.GOLD .. L["Someone you know is nearby"] .. "|r"))
  f.name:SetText(UI.ClassColored(info.name or "?", info.class) .. (info.level and (" " .. UI.MUTED .. info.level .. "|r") or ""))
  f.line:SetText(info.line or "")
  f.open:SetShown(guid ~= nil)
  f:Show()
  if FR.Params:Get("nearby.alertSound") and PlaySound then
    pcall(PlaySound, SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959, "Master")
  end
  self.token = (self.token or 0) + 1
  local token = self.token
  local secs = FR.Params:Get("nearby.alertSeconds")
  if secs > 0 and C_Timer then C_Timer.After(secs, function() if self.token == token and not f:IsMouseOver() then f:Hide() end end) end
end

function Alert:Check(unit)
  if not FR.db or not FR.Params:Get("nearby.alert") or InInstance() then return end
  if not FR.SafeCall(UnitIsPlayer, unit) then return end
  local guid = FR.Clean(UnitGUID(unit))
  if not guid or guid == FR.playerGUID or FR.Sessions:InGroupWith(guid) then return end
  local now = Clock()
  local last = self.last[guid]
  if last and now - last < FR.Params:Get("nearby.alertCooldownMinutes") * 60 then return end
  local info = self:Describe(guid)
  if not info then return end
  self.last[guid] = now
  self:Show(guid, info)
end

-- A sample alert to place the pop-up (/fr alert).
function Alert:Test()
  self:Show(nil, { kind = "friend", name = UnitName and FR.Clean((UnitName("player"))) or "You", class = select(2, UnitClass("player")),
    line = L["Drag to move. The position is saved."] })
end

function Alert:ResetPosition()
  if FR.db.ui then FR.db.ui.alertPos = nil end
  if self.frame then RestorePosition(self.frame) end
end

-- Nameplates are the farthest the game lets an addon see other players. This sets
-- the client's own maximum nameplate distance (the game clamps it to what it allows).
function Alert:MaxRange()
  if FR.InCombat() or not (SetCVar and GetCVar) then return nil end
  pcall(SetCVar, "nameplateMaxDistance", 100)
  return tonumber(GetCVar("nameplateMaxDistance"))
end

FR:On("NAME_PLATE_UNIT_ADDED", function(_, unit) Alert:Check(unit) end)
FR:On("UPDATE_MOUSEOVER_UNIT", function() Alert:Check("mouseover") end)
FR:On("PLAYER_TARGET_CHANGED", function() Alert:Check("target") end)

return Alert
