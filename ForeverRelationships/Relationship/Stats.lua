-- Relationship statistics (GDD v2 §3-4): Information and Knowledge only.
-- Pure Lua over the event log (no WoW API except the optional friend check), so
-- it is testable outside the game. Nothing here judges anyone: it counts what
-- happened while you played together.
local _, FR = ...
FR = FR or {}

local Rel = {}
FR.Rel = Rel

local DAY = 86400

local function SessionsById()
  local out = {}
  for _, ev in ipairs(FR.Log:All()) do
    if ev.signal == "session" and ev.sessionId then out[ev.sessionId] = ev end
  end
  return out
end

-- Overlap of two lists of intervals {join, leave|nil}; nil leave = until endedAt.
local function Overlaps(a, b, endedAt)
  local out = {}
  for _, x in ipairs(a or {}) do
    for _, y in ipairs(b or {}) do
      local s = math.max(x.join or 0, y.join or 0)
      local e = math.min(x.leave or endedAt, y.leave or endedAt)
      if e > s then out[#out + 1] = { s = s, e = e } end
    end
  end
  return out
end
Rel.Overlaps = Overlaps

local function Inside(windows, t)
  for _, w in ipairs(windows) do if t >= w.s and t <= w.e then return true end end
  return false
end

local function Counts(sess, P)
  if not sess then return false end
  local d = sess.details
  return ((d.endedAt or sess.t) - (d.startedAt or sess.t)) >= P["session.minMinutes"] * 60
end

local function Where(sd)
  return sd.instanceName or sd.zone or "?"
end

local function DayKey(t) return math.floor(t / DAY) end

local cache, cacheKey = {}, nil
local function CacheKey() return tostring(FR.Log.count) .. ":" .. tostring(FR.Params.version) end

-- Shared sessions with a player: { session, me = memberEvent, them = memberEvent, windows }
function Rel:Shared(guid)
  local me = FR.playerGUID
  local P = FR.Params:Snapshot()
  local sessions = SessionsById()
  local mine = {}
  for _, ev in ipairs(FR.Log:ForSubject(me or "")) do
    if ev.signal == "member" then mine[ev.sessionId] = ev end
  end
  local out = {}
  for _, ev in ipairs(FR.Log:ForSubject(guid)) do
    if ev.signal == "member" and ev.sessionId and guid ~= me then
      local s = sessions[ev.sessionId]
      local myEv = mine[ev.sessionId]
      if s and myEv and Counts(s, P) then
        local w = Overlaps(myEv.details.intervals, ev.details.intervals, s.details.endedAt or s.t)
        if #w > 0 then out[#out + 1] = { session = s, me = myEv, them = ev, windows = w } end
      end
    end
  end
  return out
end

local HOURS = { { 5, 12, "mornings" }, { 12, 18, "afternoons" }, { 18, 24, "evenings" }, { 0, 5, "late nights" } }

-- Full relationship with one player.
function Rel:Compute(guid)
  local key = CacheKey()
  if key ~= cacheKey then cache, cacheKey = {}, key end
  if cache[guid] then return cache[guid] end

  local me = FR.playerGUID
  local r = {
    guid = guid, sessions = 0, seconds = 0, days = 0, dungeons = 0, raids = 0, kills = 0, readyChecks = 0,
    trades = 0, goldGiven = 0, goldReceived = 0, itemsGiven = 0, itemsReceived = 0, craftsByThem = 0, craftsByMe = 0,
    helpReceived = { buff = 0, rez = 0, summon = 0, portal = 0 }, helpGiven = { buff = 0, rez = 0, summon = 0, portal = 0 },
    quests = 0, hcDeaths = 0, loot = 0, zones = {}, hourBuckets = {}, levelGaps = {},
  }
  local days, zones, sessionIds = {}, {}, {}
  for _, sh in ipairs(self:Shared(guid)) do
    local sd = sh.session.details
    sessionIds[sh.session.sessionId] = sh
    r.sessions = r.sessions + 1
    for _, w in ipairs(sh.windows) do
      r.seconds = r.seconds + (w.e - w.s)
      days[DayKey(w.s)] = true
    end
    local start = sh.windows[1].s
    if not r.first or start < r.first then r.first, r.firstWhere = start, Where(sd) end
    local stop = sh.windows[#sh.windows].e
    if not r.last or stop > r.last then r.last, r.lastWhere = stop, Where(sd) end
    zones[Where(sd)] = (zones[Where(sd)] or 0) + 1
    local hour = tonumber(date("%H", start)) or 0
    for _, b in ipairs(HOURS) do if hour >= b[1] and hour < b[2] then r.hourBuckets[b[3]] = (r.hourBuckets[b[3]] or 0) + 1 end end
    if sh.them.details.level and sh.me.details.level then
      r.levelGaps[#r.levelGaps + 1] = sh.them.details.level - sh.me.details.level
    end
    local kills = sd.kills or {}
    for _, k in ipairs(kills) do if Inside(sh.windows, k) then r.kills = r.kills + 1 end end
    local last = kills[#kills]
    if last and Inside(sh.windows, last) then
      if sd.groupType == "raid" then r.raids = r.raids + 1 elseif sd.groupType == "dungeon" then r.dungeons = r.dungeons + 1 end
    end
    for _, l in ipairs(sh.them.details.lootTimes or {}) do
      local t, q = type(l) == "table" and l.t or l, type(l) == "table" and l.q or 2
      if q >= 2 and Inside(sh.windows, t) then r.loot = r.loot + 1 end
    end
  end
  for _ in pairs(days) do r.days = r.days + 1 end

  -- session-scoped facts (ready checks, quests, Hardcore deaths) inside shared windows
  for sid, sh in pairs(sessionIds) do
    for _, ev in ipairs(FR.Log:ForSession(sid)) do
      if Inside(sh.windows, ev.t) then
        if ev.signal == "ready" and ev.subjectGUID == guid then r.readyChecks = r.readyChecks + 1
        elseif ev.signal == "quest" and ev.subjectGUID == guid then r.quests = r.quests + 1
        elseif ev.signal == "questDone" and ev.subjectGUID == me then r.quests = r.quests + 1
        elseif ev.signal == "hcDeath" then r.hcDeaths = r.hcDeaths + 1 end
      end
    end
  end

  -- trades and help (not tied to sessions)
  for _, ev in ipairs(FR.Log:ForSubject(guid)) do
    local d = ev.details
    if ev.signal == "trade" then
      r.trades = r.trades + 1
      r.goldGiven, r.goldReceived = r.goldGiven + (d.givenCopper or 0), r.goldReceived + (d.receivedCopper or 0)
      for _ in pairs(d.givenItems or {}) do r.itemsGiven = r.itemsGiven + 1 end
      for _ in pairs(d.receivedItems or {}) do r.itemsReceived = r.itemsReceived + 1 end
      if d.enchantByThem or d.craftedByThem then r.craftsByThem = r.craftsByThem + 1 end
      if d.enchantByMe or d.craftedByMe then r.craftsByMe = r.craftsByMe + 1 end
    elseif ev.signal == "generosity" and r.helpReceived[d.kind] then
      r.helpReceived[d.kind] = r.helpReceived[d.kind] + 1
    end
  end
  for _, ev in ipairs(FR.Log:ForSubject(me or "")) do
    if ev.signal == "generosity" and ev.details.recipientGUID == guid and r.helpGiven[ev.details.kind] then
      r.helpGiven[ev.details.kind] = r.helpGiven[ev.details.kind] + 1
    end
  end

  -- knowledge: zones, typical time, level gap
  local zl = {}
  for z, n in pairs(zones) do zl[#zl + 1] = { z = z, n = n } end
  table.sort(zl, function(a, b) return a.n > b.n end)
  for i = 1, math.min(3, #zl) do r.zones[i] = zl[i].z end
  local best, bestN = nil, 0
  for label, n in pairs(r.hourBuckets) do if n > bestN then best, bestN = label, n end end
  r.typicalTime = best
  if #r.levelGaps > 0 then
    local sum = 0
    for _, g in ipairs(r.levelGaps) do sum = sum + g end
    r.levelGap = math.floor(sum / #r.levelGaps + 0.5)
  end
  local p = FR.db and FR.db.players[guid]
  r.guild = p and p.guilds and p.guilds[#p.guilds] and p.guilds[#p.guilds].name or nil
  r.guildChanges = p and p.guilds and math.max(0, #p.guilds - 1) or 0
  cache[guid] = r
  return r
end

-- Everyone you've played with, most time together first.
function Rel:Circle()
  local out = {}
  for guid, p in pairs(FR.db and FR.db.players or {}) do
    if guid ~= FR.playerGUID then
      local r = self:Compute(guid)
      if r.sessions > 0 or r.trades > 0 then
        out[#out + 1] = { guid = guid, name = p.name, class = p.class, level = p.level, r = r }
      end
    end
  end
  table.sort(out, function(a, b)
    if a.r.seconds ~= b.r.seconds then return a.r.seconds > b.r.seconds end
    return (a.r.last or 0) > (b.r.last or 0)
  end)
  for i, e in ipairs(out) do e.rank = i end
  return out
end

function Rel:Rank(guid)
  for _, e in ipairs(self:Circle()) do if e.guid == guid then return e.rank end end
  return nil
end

-- Your own numbers (for "My profile" and the opt-in public profile).
function Rel:Mine()
  local me = FR.playerGUID
  local P = FR.Params:Snapshot()
  local sessions = SessionsById()
  local m = { seconds = 0, sessions = 0, people = 0, dungeons = 0, raids = 0, kills = 0, quests = 0,
    helpGiven = 0, crafts = 0, instances = {} }
  local people = {}
  for _, ev in ipairs(FR.Log:ForSubject(me or "")) do
    if ev.signal == "member" then
      local s = sessions[ev.sessionId]
      if s and Counts(s, P) then
        local sd = s.details
        m.sessions = m.sessions + 1
        local windows = {}
        for _, iv in ipairs(ev.details.intervals or {}) do
          local e = iv.leave or sd.endedAt or s.t
          m.seconds = m.seconds + (e - iv.join)
          windows[#windows + 1] = { s = iv.join, e = e }
        end
        for _, k in ipairs(sd.kills or {}) do if Inside(windows, k) then m.kills = m.kills + 1 end end
        local last = sd.kills and sd.kills[#sd.kills]
        if last and Inside(windows, last) then
          if sd.groupType == "raid" then m.raids = m.raids + 1 elseif sd.groupType == "dungeon" then m.dungeons = m.dungeons + 1 end
          local inst = sd.instanceName or sd.zone
          if inst then m.instances[inst] = (m.instances[inst] or 0) + 1 end
        end
        for _, other in ipairs(FR.Log:ForSession(ev.sessionId)) do
          if other.signal == "member" and other.subjectGUID ~= me then people[other.subjectGUID] = true end
        end
      end
    elseif ev.signal == "questDone" and ev.sessionId then m.quests = m.quests + 1
    elseif ev.signal == "generosity" and ev.details.recipientGUID then m.helpGiven = m.helpGiven + 1 end
  end
  for _ in pairs(people) do m.people = m.people + 1 end
  for _, ev in ipairs(FR.Log:All()) do
    if ev.signal == "trade" and (ev.details.enchantByMe or ev.details.craftedByMe) then m.crafts = m.crafts + 1 end
  end
  local best, n = nil, 0
  for inst, c in pairs(m.instances) do if c > n then best, n = inst, c end end
  m.favorite = best
  return m
end

function Rel.Invalidate() cacheKey = nil end

-------------------------------------------------------------------------------
-- Field registry: what the tooltip (6 chosen) and the Relationship window show.
-------------------------------------------------------------------------------
local function dur(s) return FR.FormatDuration and FR.FormatDuration(s) or tostring(s) end
local function ago(t) return FR.FormatAgo and FR.FormatAgo(t) or tostring(t) end
local function gold(c) return FR.FormatGold and FR.FormatGold(c) or tostring(c) end
local function sumHelp(h) return h.buff + h.rez + h.summon + h.portal end
local function helpText(h)
  local bits = {}
  for _, k in ipairs({ "buff", "rez", "summon", "portal" }) do
    if h[k] > 0 then bits[#bits + 1] = h[k] .. " " .. (k == "rez" and "rez" or k) .. (h[k] > 1 and "s" or "") end
  end
  return #bits > 0 and table.concat(bits, ", ") or "none"
end

-- layer: "info" (facts) or "knowledge" (patterns for you)
Rel.FIELDS = {
  { key = "time", layer = "knowledge", label = "Time together", value = function(r) return dur(r.seconds) .. " in " .. r.sessions .. " session" .. (r.sessions == 1 and "" or "s") end },
  { key = "last", layer = "info", label = "Last together", value = function(r) return r.last and (ago(r.last) .. ", " .. r.lastWhere) or "never" end },
  { key = "days", layer = "knowledge", label = "Days together", value = function(r) return r.days .. " day" .. (r.days == 1 and "" or "s") end },
  { key = "completed", layer = "info", label = "Completed together", value = function(r) return r.dungeons .. " dungeon" .. (r.dungeons == 1 and "" or "s") .. ", " .. r.raids .. " raid" .. (r.raids == 1 and "" or "s") end },
  { key = "kills", layer = "info", label = "Kills together", value = function(r) return tostring(r.kills) end },
  { key = "trades", layer = "info", label = "Trades", value = function(r) return r.trades .. (r.trades > 0 and (" (gave " .. gold(r.goldGiven) .. ", got " .. gold(r.goldReceived) .. ")") or "") end },
  { key = "first", layer = "info", label = "First together", value = function(r) return r.first and (date("%Y-%m-%d", r.first) .. ", " .. r.firstWhere) or "never" end },
  { key = "rhythm", layer = "knowledge", label = "You usually play together", value = function(r) return r.typicalTime or "-" end },
  { key = "levelGap", layer = "knowledge", label = "Typical level difference", value = function(r)
      if not r.levelGap then return "-" end
      if r.levelGap == 0 then return "same level" end
      return (r.levelGap > 0 and ("+" .. r.levelGap .. " above you") or (-r.levelGap .. " below you")) end },
  { key = "zones", layer = "knowledge", label = "Places in common", value = function(r) return #r.zones > 0 and table.concat(r.zones, ", ") or "-" end },
  { key = "quests", layer = "info", label = "Quests completed together", value = function(r) return tostring(r.quests) end },
  { key = "helpReceived", layer = "info", label = "Help you received", value = function(r) return helpText(r.helpReceived) end, total = function(r) return sumHelp(r.helpReceived) end },
  { key = "helpGiven", layer = "info", label = "Help you gave", value = function(r) return helpText(r.helpGiven) end, total = function(r) return sumHelp(r.helpGiven) end },
  { key = "crafts", layer = "info", label = "Crafts and enchants", value = function(r) return ("by them: %d, by you: %d"):format(r.craftsByThem, r.craftsByMe) end },
  { key = "loot", layer = "info", label = "Items they looted with you", value = function(r) return tostring(r.loot) end },
  { key = "ready", layer = "info", label = "Ready checks together", value = function(r) return tostring(r.readyChecks) end },
  { key = "hc", layer = "info", label = "Hardcore deaths in your group", value = function(r) return tostring(r.hcDeaths) end },
  { key = "guild", layer = "info", label = "Guild", value = function(r) return (r.guild and r.guild ~= "" and ("<" .. r.guild .. ">") or "none") .. (r.guildChanges > 0 and (" · " .. r.guildChanges .. " change" .. (r.guildChanges == 1 and "" or "s") .. " seen") or "") end },
  { key = "rank", layer = "knowledge", label = "In your circle", value = function(r) local n = Rel:Rank(r.guid); return n and ("#" .. n .. " by time together") or "-" end },
}
Rel.FIELD_BY_KEY = {}
for _, f in ipairs(Rel.FIELDS) do Rel.FIELD_BY_KEY[f.key] = f end
Rel.DEFAULT_TOOLTIP = { "time", "last", "days", "completed", "kills", "trades" }
Rel.MAX_TOOLTIP = 6

-- Your own numbers that can be published (opt-in, item by item).
Rel.PROFILE_ITEMS = {
  { key = "hours", label = "Hours played in groups", value = function(m) return math.floor(m.seconds / 3600) end },
  { key = "people", label = "Different people played with", value = function(m) return m.people end },
  { key = "dungeons", label = "Dungeons completed", value = function(m) return m.dungeons end },
  { key = "raids", label = "Raids completed", value = function(m) return m.raids end },
  { key = "kills", label = "Kills in groups", value = function(m) return m.kills end },
  { key = "quests", label = "Quests completed in groups", value = function(m) return m.quests end },
  { key = "help", label = "Times I helped other players", value = function(m) return m.helpGiven end },
  { key = "crafts", label = "Crafts and enchants for others", value = function(m) return m.crafts end },
  { key = "favorite", label = "Favorite dungeon", value = function(m) return m.favorite or "-" end },
}

return Rel
