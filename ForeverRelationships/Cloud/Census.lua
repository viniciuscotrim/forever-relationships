-- Population census (Community layer only, off by default).
-- Counts the characters you SEE (mouseover, target, nameplates, your group) with
-- only what the game shows above their heads: faction, race, class, level, and the
-- realm id that is part of every character code. No names, no positions, no chat.
-- The companion sends it; the server pseudonymizes each code and only publishes
-- totals per realm type, faction and race (the Population tab).
local _, FR = ...

local Census = {}
FR.Census = Census

FR:RegisterCapture("census", "Population census (Community layer)",
  "UPDATE_MOUSEOVER_UNIT, PLAYER_TARGET_CHANGED, NAME_PLATE_UNIT_ADDED, GROUP_ROSTER_UPDATE")

Census.KEEP = 30 * 86400   -- the server counts the last 30 days
Census.MAX = 20000         -- local cap; the oldest sightings go first
Census.SEND = 5000         -- per sync, most recent first

local RACE_NAMES = { Scourge = "Undead", NightElf = "Night Elf", BloodElf = "Blood Elf" }
local function Title(s) return type(s) == "string" and (s:sub(1, 1) .. s:sub(2):lower()) or nil end

function Census.RaceName(raceFile)
  return raceFile and (RACE_NAMES[raceFile] or raceFile) or nil
end

function Census.RealmId(guid)
  return type(guid) == "string" and tonumber(guid:match("^Player%-(%d+)%-")) or nil
end

local function Store()
  local c = FR.db.census
  if type(c) ~= "table" then
    c = { seen = {}, realms = {}, count = 0 }
    FR.db.census = c
  end
  return c
end

function Census:Enabled()
  return FR.Params:Get("consent.community") and true or false
end

function Census:Observe(unit)
  if not self:Enabled() or not FR:CaptureOK("census") then return end
  if not FR.SafeCall(UnitIsPlayer, unit) then return end
  local guid = FR.Clean(FR.SafeCall(UnitGUID, unit))
  local realmId = self.RealmId(guid)
  if not realmId or guid == FR.playerGUID then return end
  local faction = FR.Clean((FR.SafeCall(UnitFactionGroup, unit)))
  if faction ~= "Alliance" and faction ~= "Horde" then return end
  local _, raceFile = FR.SafeCall(UnitRace, unit)
  local _, classFile = FR.SafeCall(UnitClass, unit)
  local level = FR.Clean(FR.SafeCall(UnitLevel, unit))
  local s = Store()
  local e = s.seen[guid]
  if not e then
    e = {}
    s.seen[guid] = e
    s.count = (s.count or 0) + 1
  end
  e.f, e.t = faction, FR.Now()
  e.r = FR.Clean(raceFile) or e.r
  e.c = FR.Clean(classFile) or e.c
  if type(level) == "number" and level > 0 then e.l = level end
  local _, realm = FR.SafeCall(UnitName, unit)   -- only set for characters from another realm
  realm = FR.Clean(realm)
  if type(realm) == "string" and realm ~= "" then s.realms[tostring(realmId)] = realm end
  if s.count > self.MAX then self:Prune() end
end

function Census:Prune(now)
  local s = Store()
  now = now or FR.Now()
  local list = {}
  for guid, e in pairs(s.seen) do
    if now - (e.t or 0) > self.KEEP then s.seen[guid] = nil else list[#list + 1] = { guid, e.t or 0 } end
  end
  if #list > self.MAX then
    table.sort(list, function(a, b) return a[2] > b[2] end)
    for i = self.MAX + 1, #list do s.seen[list[i][1]] = nil end
  end
  local n = 0
  for _ in pairs(s.seen) do n = n + 1 end
  s.count = n
end

-- What the companion sends: your own character plus everyone seen in the last 30 days.
function Census:Outbox(me)
  local s = Store()
  local now = FR.Now()
  self:Prune(now)
  local list = {}
  for guid, e in pairs(s.seen) do
    list[#list + 1] = { g = guid, f = e.f, r = self.RaceName(e.r), c = Title(e.c), l = e.l, t = e.t }
  end
  table.sort(list, function(a, b) return a.t > b.t end)
  while #list > self.SEND do list[#list] = nil end
  local realms = {}
  for k, v in pairs(s.realms) do realms[k] = v end
  local ownRealm = self.RealmId(FR.playerGUID)
  if me and ownRealm and (me.faction == "Alliance" or me.faction == "Horde") then
    list[#list + 1] = { g = FR.playerGUID, f = me.faction, r = me.race, c = me.class, l = me.level, t = now }
    if me.realm then realms[tostring(ownRealm)] = me.realm end
  end
  return list, realms
end

function Census:Forget()
  FR.db.census = nil
end

local function ObserveGroup()
  if IsInRaid and IsInRaid() then
    for i = 1, (GetNumGroupMembers and GetNumGroupMembers() or 0) do Census:Observe("raid" .. i) end
  else
    for i = 1, 4 do Census:Observe("party" .. i) end
  end
end

FR:On("UPDATE_MOUSEOVER_UNIT", function() Census:Observe("mouseover") end, "census")
FR:On("PLAYER_TARGET_CHANGED", function() Census:Observe("target") end, "census")
FR:On("NAME_PLATE_UNIT_ADDED", function(_, unit) Census:Observe(unit) end, "census")
FR:On("GROUP_ROSTER_UPDATE", ObserveGroup, "census")

-- Community turned off: nothing collected so far is kept.
FR:Listen("PARAMS_CHANGED", function(key)
  if key == "consent.community" and not FR.Params:Get("consent.community") then Census:Forget() end
end)

-------------------------------------------------------------------------------
-- Population (from the server, via the companion's NetData.lua)
-------------------------------------------------------------------------------
local function Data()
  local d = _G.ForeverRelationshipsNetData
  return type(d) == "table" and type(d.population) == "table" and d.population or nil
end

function Census:Population() return Data() end

-- "pvp" | "pve" | nil (not classified yet)
function Census:RealmType(realmId)
  local p = Data()
  local r = p and p.realms and p.realms[tostring(realmId)]
  return r and r.type or nil
end

function Census:MyRealmType()
  return self:RealmType(self.RealmId(FR.playerGUID))
end

-- rows sorted by count: { race, faction, n, pct } for a realm type and faction filter ("all" | "Alliance" | "Horde")
function Census:Summary(rtype, faction)
  local p = Data()
  local t = p and p.types and p.types[rtype] or {}
  local a = t.Alliance and t.Alliance.total or 0
  local h = t.Horde and t.Horde.total or 0
  local out = { alliance = a, horde = h, total = a + h, rows = {} }
  local base = 0
  for _, f in ipairs({ "Alliance", "Horde" }) do
    if faction == "all" or faction == f then
      base = base + (t[f] and t[f].total or 0)
      for race, n in pairs(t[f] and t[f].races or {}) do
        out.rows[#out.rows + 1] = { race = race, faction = f, n = n }
      end
    end
  end
  for _, r in ipairs(out.rows) do r.pct = base > 0 and r.n * 100 / base or 0 end
  table.sort(out.rows, function(x, y) if x.n ~= y.n then return x.n > y.n end return x.race < y.race end)
  out.base = base
  return out
end
