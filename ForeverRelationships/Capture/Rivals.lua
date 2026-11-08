-- Rivals: players of the opposite faction. Not time together, but how often your
-- paths crossed, how often you fought, and who won. Counters only, per player, in
-- ForeverRelationshipsDB.rivals[guid] = { name, class, race, faction, level, guild,
--   crossed, battles, wins, deaths, first, lastSeen, lastBattle, lastZone }
-- Sources (each one disables itself if the client hides it):
--   crossed: nameplates, mouseover, target (a new crossing after rivals.crossingGapMinutes apart)
--   battles: while you are in combat, an enemy player who targets you or whom you target, both in combat
--   wins:    an enemy you fought dies, or an honorable kill of them
--   deaths:  you die while fighting them (the enemy you fought most recently)
local _, FR = ...

local Rivals = {}
FR.Rivals = Rivals

FR:RegisterCapture("rivalsSeen", "Opposite-faction players you cross", "NAME_PLATE_UNIT_ADDED, UPDATE_MOUSEOVER_UNIT, PLAYER_TARGET_CHANGED")
FR:RegisterCapture("rivalsCombat", "Fights with opposite-faction players", "PLAYER_REGEN_DISABLED, UnitAffectingCombat, UnitIsUnit")
FR:RegisterCapture("rivalsHonor", "Honorable kills", "CHAT_MSG_COMBAT_HONOR_GAIN")

local MAX_RIVALS = 5000
local CONTACT_DEATH = 20   -- seconds: you died "while fighting them" if they were in contact this recently
local CONTACT_WIN = 30     -- seconds: an enemy who dies this soon after fighting you counts as your victory
local SCAN_EVERY = 0.5

local function Clock() return GetTime and GetTime() or 0 end

function Rivals:Store()
  FR.db.rivals = FR.db.rivals or {}
  return FR.db.rivals
end

function Rivals:Get(guid)
  return guid and FR.db and FR.db.rivals and FR.db.rivals[guid] or nil
end

local function MyFaction() return FR.Clean((UnitFactionGroup("player"))) end

-- An opposite-faction player unit, read safely; nil for anything else.
function Rivals.ReadEnemy(unit)
  if not FR.SafeCall(UnitIsPlayer, unit) then return nil end
  local u = FR.Sessions.ReadUnit(unit)
  if not u or u.guid == FR.playerGUID then return nil end
  local mine = MyFaction()
  if not mine or not u.faction or u.faction == mine or u.faction == "Neutral" then return nil end
  return u
end

function Rivals:Touch(u)
  local s = self:Store()
  local r = s[u.guid]
  if not r then
    r = { crossed = 0, battles = 0, wins = 0, deaths = 0, first = FR.Now() }
    s[u.guid] = r
  end
  r.name = u.name or r.name
  r.class = u.class or r.class
  r.race = u.race or r.race
  r.faction = u.faction or r.faction
  r.level = u.level or r.level
  if type(u.guild) == "string" and u.guild ~= "" then r.guild = u.guild end
  return r
end

-- A sighting. Continuous presence is one crossing; a new one starts after the gap.
function Rivals:Seen(unit)
  if not FR:CaptureOK("rivalsSeen") then return end
  local u = self.ReadEnemy(unit)
  if not u then return end
  local now = FR.Now()
  local r = self:Touch(u)
  if not r.lastSeen or now - r.lastSeen >= FR.Params:Get("rivals.crossingGapMinutes") * 60 then
    r.crossed = r.crossed + 1
    r.lastZone = GetRealZoneText and FR.Clean(GetRealZoneText()) or r.lastZone
    FR:Fire("RIVAL_CROSSED", u.guid, r)
  end
  r.lastSeen = now
  return u, r
end

-------------------------------------------------------------------------------
-- Combat episodes: one battle per enemy per episode
-------------------------------------------------------------------------------
local episode = { foes = {}, won = {} }   -- foes[guid] = last contact (GetTime)
Rivals.episode = episode

local function NewEpisode()
  episode.foes, episode.won, episode.started = {}, {}, Clock()
end

function Rivals:Contact(guid, r)
  if not r then return end
  if FR.Sessions.InGroupWith and FR.Sessions:InGroupWith(guid) then return end
  local now = FR.Now()
  if not episode.foes[guid] then
    r.battles = r.battles + 1
    r.lastBattle = now
    -- a fight is also a crossing, even when the nameplate was never shown
    if r.crossed == 0 then r.crossed = 1 end
    r.lastSeen = now
    FR:Fire("RIVAL_BATTLE", guid, r)
  end
  episode.foes[guid] = Clock()
end

function Rivals:Win(guid, r, source)
  if not r or episode.won[guid] then return end
  episode.won[guid] = true
  r.wins = r.wins + 1
  r.lastWin, r.lastWinSource = FR.Now(), source
  FR:Fire("RIVAL_WIN", guid, r, source)
end

function Rivals:Died()
  local best, bestT = nil, -math.huge
  for guid, t in pairs(episode.foes) do
    if Clock() - t <= CONTACT_DEATH and t > bestT then best, bestT = guid, t end
  end
  local r = best and self:Get(best)
  if not r then return end
  r.deaths = r.deaths + 1
  r.lastDeath = FR.Now()
  episode.foes[best] = nil   -- a later fight after resurrecting is a new battle
  FR:Fire("RIVAL_DEATH", best, r)
end

-- Units an enemy can be on: target, focus, mouseover and every nameplate.
local SCAN_UNITS = { "target", "focus", "mouseover" }
for i = 1, 40 do SCAN_UNITS[#SCAN_UNITS + 1] = "nameplate" .. i end

local function Truthy(fn, ...)
  local v = FR.SafeCall(fn, ...)
  return v and true or false
end

function Rivals:Scan()
  if not FR:CaptureOK("rivalsCombat") then return end
  local fighting = FR.InCombat()
  for _, unit in ipairs(SCAN_UNITS) do
    if Truthy(UnitExists, unit) then
      local u = self.ReadEnemy(unit)
      if u then
        local r = self:Touch(u)
        local dead = Truthy(UnitIsDeadOrGhost, unit)
        if fighting and not dead and Truthy(UnitAffectingCombat, unit)
          and (Truthy(UnitIsUnit, unit .. "target", "player") or Truthy(UnitIsUnit, "target", unit)) then
          self:Contact(u.guid, r)
        elseif dead and episode.foes[u.guid] and Clock() - episode.foes[u.guid] <= CONTACT_WIN then
          self:Win(u.guid, r, "seen")
        end
      end
    end
  end
end

local ticker
FR:On("PLAYER_REGEN_DISABLED", function()
  if not FR.db then return end
  if not episode.started or (not ticker and Clock() - (episode.ended or 0) > CONTACT_WIN) then NewEpisode() end
  Rivals:Scan()
  if not ticker and C_Timer and C_Timer.NewTicker then
    ticker = C_Timer.NewTicker(SCAN_EVERY, function() Rivals:Scan() end)
  end
end, "rivalsCombat")

FR:On("PLAYER_REGEN_ENABLED", function()
  Rivals:Scan()   -- a last look: who died at the end of the fight
  episode.ended = Clock()
  if ticker then ticker:Cancel(); ticker = nil end
end, "rivalsCombat")

FR:On("PLAYER_DEAD", function() Rivals:Died() end, "rivalsCombat")

-------------------------------------------------------------------------------
-- Honorable kills: "<name> dies, honorable kill Rank: ..."
-------------------------------------------------------------------------------
function Rivals:ByName(name)
  if not name then return nil end
  local short = FR.ShortName(name):lower()
  local best, bestT
  for guid, r in pairs(self:Store()) do
    if r.name and FR.ShortName(r.name):lower() == short then
      local t = episode.foes[guid] or 0
      if not best or t > bestT then best, bestT = guid, t end
    end
  end
  return best
end

local honorPattern
FR:On("CHAT_MSG_COMBAT_HONOR_GAIN", function(_, msg)
  msg = FR.Clean(msg)
  if type(msg) ~= "string" then return end
  honorPattern = honorPattern or FR.PatternFromFormat(COMBAT_HONOR_GAIN)
  local name = honorPattern and msg:match(honorPattern)
  local guid = Rivals:ByName(name)
  if guid then Rivals:Win(guid, Rivals:Get(guid), "honor") end
end, "rivalsHonor")

-- No combat log: on this client registering COMBAT_LOG_EVENT_UNFILTERED is reserved
-- to the Blizzard UI and makes the game block the addon (0.6.0 did it; fixed in 0.6.1).

-------------------------------------------------------------------------------
-- Sightings
-------------------------------------------------------------------------------
FR:On("NAME_PLATE_UNIT_ADDED", function(_, unit) Rivals:Seen(unit) end, "rivalsSeen")
FR:On("UPDATE_MOUSEOVER_UNIT", function() Rivals:Seen("mouseover") end, "rivalsSeen")
FR:On("PLAYER_TARGET_CHANGED", function() Rivals:Seen("target") end, "rivalsSeen")

-------------------------------------------------------------------------------
-- Numbers for the UI
-------------------------------------------------------------------------------
function Rivals.Pct(part, whole)
  if not whole or whole <= 0 then return 0 end
  return math.floor(part * 100 / whole + 0.5)
end

function Rivals:Totals()
  local t = { players = 0, crossed = 0, battles = 0, wins = 0, deaths = 0 }
  for _, r in pairs(FR.db and FR.db.rivals or {}) do
    t.players = t.players + 1
    t.crossed, t.battles, t.wins, t.deaths = t.crossed + r.crossed, t.battles + r.battles, t.wins + r.wins, t.deaths + r.deaths
  end
  return t
end

-- Everyone you fought first (most battles), then everyone you crossed most.
function Rivals:List()
  local out = {}
  for guid, r in pairs(FR.db and FR.db.rivals or {}) do out[#out + 1] = { guid = guid, name = r.name, class = r.class, level = r.level, rv = r } end
  table.sort(out, function(a, b)
    if a.rv.battles ~= b.rv.battles then return a.rv.battles > b.rv.battles end
    if a.rv.crossed ~= b.rv.crossed then return a.rv.crossed > b.rv.crossed end
    return (a.rv.lastSeen or 0) > (b.rv.lastSeen or 0)
  end)
  return out
end

-- One line: "Crossed 5 · Battles 3 (60%) · Won 2 (67%) · Lost 1 (33%)"
function Rivals:Summary(r)
  local L = FR.L
  return L["Crossed %d · Battles %d (%d%%) · Won %d (%d%%) · Lost %d (%d%%)"]:format(
    r.crossed, r.battles, self.Pct(r.battles, r.crossed), r.wins, self.Pct(r.wins, r.battles), r.deaths, self.Pct(r.deaths, r.battles))
end

-- Detail rows { label, value } for the Relationship window.
function Rivals:Rows(r)
  local L, t = FR.L, self:Totals()
  local pct = self.Pct
  return {
    { L["Times your paths crossed"], tostring(r.crossed) },
    { L["Battles"], L["%d (%d%% of your crossings)"]:format(r.battles, pct(r.battles, r.crossed)) },
    { L["Victories"], L["%d (%d%% of your battles with them)"]:format(r.wins, pct(r.wins, r.battles)) },
    { L["Deaths to them"], L["%d (%d%% of your battles with them)"]:format(r.deaths, pct(r.deaths, r.battles)) },
    { L["First seen"], r.first and FR.FormatDate(r.first) or "-" },
    { L["Last seen"], r.lastSeen and (FR.FormatAgo(r.lastSeen) .. (r.lastZone and (", " .. r.lastZone) or "")) or "-" },
  }, {
    { L["Share of all your crossings"], pct(r.crossed, t.crossed) .. "%" },
    { L["Share of all your battles"], pct(r.battles, t.battles) .. "%" },
    { L["Share of all your victories"], pct(r.wins, t.wins) .. "%" },
    { L["Share of all your deaths in PvP"], pct(r.deaths, t.deaths) .. "%" },
    { L["All rivals"], L["%d players · %d battles · won %d%%"]:format(t.players, t.battles, pct(t.wins, t.battles)) },
  }
end

-------------------------------------------------------------------------------
-- Retention and size: old crossings without fights go first
-------------------------------------------------------------------------------
function Rivals:Prune()
  local s = FR.db and FR.db.rivals
  if not s then return 0 end
  local days = FR.Params:Get("history.retentionDays")
  local cutoff = days and days > 0 and (FR.Now() - days * 86400) or nil
  local list, dropped = {}, 0
  for guid, r in pairs(s) do
    if cutoff and (r.lastSeen or r.first or 0) < cutoff then s[guid] = nil; dropped = dropped + 1
    else list[#list + 1] = { guid = guid, r = r } end
  end
  if #list > MAX_RIVALS then
    table.sort(list, function(a, b)
      if a.r.battles ~= b.r.battles then return a.r.battles < b.r.battles end
      return (a.r.lastSeen or 0) < (b.r.lastSeen or 0)
    end)
    for i = 1, #list - MAX_RIVALS do s[list[i].guid] = nil; dropped = dropped + 1 end
  end
  return dropped
end

FR:Listen("LOGIN", function() Rivals:Prune() end)

return Rivals
