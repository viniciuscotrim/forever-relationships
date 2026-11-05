-- Forever Relationships: namespace, utilities, event bus, SavedVariables, migrations.
local ADDON, FR = ...
FR = FR or {}
FR.name = ADDON or "ForeverRelationships"
FR.version = "0.4.2"
FR.SCHEMA = 2
FR.PREFIX = "ForeverRel"

-------------------------------------------------------------------------------
-- Generic utilities (safe without the WoW API so the pure modules can be tested)
-------------------------------------------------------------------------------
function FR.Now()
  if GetServerTime then return GetServerTime() end
  return os.time()
end

-- Midnight Secret Values: any value read from unit/aura/combat-adjacent APIs is
-- checked before use. A secret value is never stored, compared or concatenated.
function FR.IsSecret(v)
  if issecretvalue then
    local ok, res = pcall(issecretvalue, v)
    return (not ok) or res and true or false
  end
  return false
end

-- Returns v, or nil if it is secret.
function FR.Clean(v)
  if v == nil or FR.IsSecret(v) then return nil end
  return v
end

-- pcall a function; returns its results only if none of the first 4 is secret.
function FR.SafeCall(fn, ...)
  if type(fn) ~= "function" then return nil end
  local r = { pcall(fn, ...) }
  if not r[1] then return nil end
  for i = 2, math.min(#r, 5) do
    if FR.IsSecret(r[i]) then return nil end
  end
  return select(2, unpack(r))
end

function FR.InCombat()
  return InCombatLockdown and InCombatLockdown() or false
end

function FR.CopyTable(t)
  if type(t) ~= "table" then return t end
  local c = {}
  for k, v in pairs(t) do c[k] = FR.CopyTable(v) end
  return c
end

function FR.Round(x, n)
  local m = 10 ^ (n or 0)
  return math.floor(x * m + 0.5) / m
end

function FR.FormatDuration(sec)
  sec = math.max(0, math.floor(sec or 0))
  local h, m = math.floor(sec / 3600), math.floor((sec % 3600) / 60)
  if h > 0 then return string.format("%dh %dm", h, m) end
  return string.format("%dm", m)
end

function FR.FormatAgo(t)
  if not t then return "never" end
  local d = FR.Now() - t
  if d < 3600 then return string.format("%dm ago", math.floor(d / 60)) end
  if d < 86400 then return string.format("%dh ago", math.floor(d / 3600)) end
  return string.format("%dd ago", math.floor(d / 86400))
end

function FR.FormatDate(t)
  return date("%Y-%m-%d %H:%M", t or FR.Now())
end

function FR.FormatGold(copper)
  copper = copper or 0
  local g = math.floor(copper / 10000)
  local s = math.floor((copper % 10000) / 100)
  local c = copper % 100
  if g > 0 then return string.format("%dg %ds", g, s) end
  if s > 0 then return string.format("%ds %dc", s, c) end
  return string.format("%dc", c)
end

-- "Name-Realm" normalisation. Realm defaults to the player's realm.
function FR.FullName(name, realm)
  if not name then return nil end
  if name:find("-", 1, true) then return name end
  realm = (realm and realm ~= "") and realm or (GetNormalizedRealmName and GetNormalizedRealmName()) or ""
  if realm == "" then return name end
  return name .. "-" .. realm
end

function FR.ShortName(full)
  if not full then return "?" end
  return (full:gsub("%-.*$", ""))
end

local function Join(...)
  local parts = {}
  for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
  return table.concat(parts, " ")
end
FR.Join = Join

function FR.Print(...)
  local msg = "|cff33ccffForever Relationships|r: " .. Join(...)
  if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(msg) else print(msg) end
end

function FR.Debug(...)
  if FR.db and FR.db.debug then
    local msg = "|cff888888[FR debug]|r " .. Join(...)
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(msg) else print(msg) end
  end
end

-------------------------------------------------------------------------------
-- Internal message bus (addon-level, not WoW events)
-------------------------------------------------------------------------------
FR._listeners = {}
function FR:Listen(msg, fn)
  self._listeners[msg] = self._listeners[msg] or {}
  table.insert(self._listeners[msg], fn)
end

function FR:Fire(msg, ...)
  local list = self._listeners[msg]
  if not list then return end
  for _, fn in ipairs(list) do
    local ok, err = pcall(fn, ...)
    if not ok then
      FR.Debug("listener error", msg, err)
      FR:RecordError(err, "listener " .. tostring(msg))
    end
  end
end

-------------------------------------------------------------------------------
-- Error capture. Every Forever Relationships error (caught handler errors and uncaught
-- Lua errors from our files) is recorded, deduplicated, and offered to the
-- player as a one-click feedback report (UI/Feedback.lua). Other addons'
-- errors are passed through untouched.
-------------------------------------------------------------------------------
FR._pendingErrors = {}
local MAX_ERRORS = 20

local function CleanError(msg)
  msg = tostring(msg or "?")
  msg = msg:gsub("Interface[/\\]AddOns[/\\]", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
  return msg:sub(1, 300)
end

function FR:RecordError(msg, where)
  local clean = CleanError(msg)
  local store = self.db and self.db.errors
  if not store then
    table.insert(self._pendingErrors, { msg = clean, where = where })
    return
  end
  for _, e in ipairs(store) do
    if e.msg == clean then
      e.count, e.last = e.count + 1, FR.Now()
      return
    end
  end
  table.insert(store, { msg = clean, where = where, count = 1, first = FR.Now(), last = FR.Now(), version = FR.version })
  while #store > MAX_ERRORS do table.remove(store, 1) end
  self:Fire("ERROR_RECORDED", store[#store])
end

if geterrorhandler and seterrorhandler then
  local previous = geterrorhandler()
  seterrorhandler(function(msg, ...)
    if type(msg) == "string" and msg:find("ForeverRelationships", 1, true) then
      pcall(FR.RecordError, FR, msg, "lua")
    end
    if previous then return previous(msg, ...) end
  end)
end

-------------------------------------------------------------------------------
-- Capture availability registry. A capture whose API is missing or returns
-- secret values disables itself and shows as unavailable in Transparency.
-------------------------------------------------------------------------------
FR.Captures = {}
FR.CaptureOrder = {}

function FR:RegisterCapture(name, label, apis)
  if not self.Captures[name] then table.insert(self.CaptureOrder, name) end
  self.Captures[name] = { name = name, label = label, apis = apis, status = "ok" }
end

function FR:CaptureUnavailable(name, api, reason)
  local c = self.Captures[name]
  if not c or c.status == "unavailable" then return end
  c.status = "unavailable"
  c.reason = reason or "API unavailable"
  c.failedApi = api
  if FR.Log and FR.Log.ready then
    FR.Log:Append({ signal = "capture", source = "game", api = api or "?",
      details = { capture = name, reason = c.reason } })
  end
  FR.Debug("capture unavailable:", name, api, reason)
end

function FR:CaptureOK(name)
  local c = self.Captures[name]
  return c and c.status == "ok"
end

-------------------------------------------------------------------------------
-- WoW event bus. Registration of an event that does not exist on this client
-- fails safely and marks the owning capture unavailable.
-------------------------------------------------------------------------------
FR._handlers = {}
if CreateFrame then
  FR.frame = CreateFrame("Frame", "ForeverRelationshipsEventFrame")
  FR.frame:SetScript("OnEvent", function(_, event, ...)
    local list = FR._handlers[event]
    if not list then return end
    -- nothing runs before SavedVariables are ready
    if not FR.db and event ~= "ADDON_LOADED" then return end
    for _, h in ipairs(list) do
      local ok, err = pcall(h.fn, event, ...)
      if not ok then
        h.errors = (h.errors or 0) + 1
        FR.Debug("handler error", event, err)
        FR:RecordError(err, "event " .. event)
        -- a capture that keeps failing disables itself instead of spamming errors
        if h.capture and h.errors >= 3 then FR:CaptureUnavailable(h.capture, event, "handler error: " .. tostring(err)) end
      end
    end
  end)
end

function FR:On(event, fn, capture)
  if not self.frame then return false end
  if not self._handlers[event] then
    local ok = pcall(self.frame.RegisterEvent, self.frame, event)
    if not ok then
      if capture then self:CaptureUnavailable(capture, event, "event not present on this client") end
      return false
    end
    self._handlers[event] = {}
  end
  table.insert(self._handlers[event], { fn = fn, capture = capture })
  return true
end

-------------------------------------------------------------------------------
-- SavedVariables + migrations
-------------------------------------------------------------------------------
local DB_DEFAULTS = {
  schemaVersion = FR.SCHEMA,
  params = {},          -- local overrides only (absent = default)
  changeLog = {},       -- parameter edits
  events = {},          -- append-only raw event log (source of truth)
  nextEventId = 1,
  players = {},         -- identity cache: guid -> {name, class, level, lastSeen, guilds}
  active = nil,         -- in-progress session (crash safe)
  ui = {},              -- tooltipFields etc.
  debug = false,
  invisible = false,
  errors = {},          -- Forever Relationships's own errors (deduplicated), for feedback reports
  feedback = {},        -- { installId, outbox = { report, ... } } sent by the companion app
}

local CHAR_DEFAULTS = {
  schemaVersion = FR.SCHEMA,
  ui = {},
  suggestDismissed = {},
}

local function ApplyDefaults(t, defaults)
  for k, v in pairs(defaults) do
    if t[k] == nil then t[k] = FR.CopyTable(v) end
  end
end

-- Migration steps keyed by the version they upgrade *to*.
FR.Migrations = {
  -- v2 (GDD v2): game data only. Opinions and manual inputs from v1 are deleted:
  -- notes, private yes/no, endorsements, debts, soft reserves, raid signups.
  [2] = function(db, cdb)
    local drop = { endorse = true, obligation = true, lootNeed = true, attendance = true }
    local kept = {}
    for _, ev in ipairs(db.events or {}) do
      if not drop[ev.signal] then
        if ev.signal == "member" and ev.details then ev.details.srRolls, ev.details.carry = nil, nil end
        kept[#kept + 1] = ev
      end
    end
    db.events = kept
    db.signups, db.softReserves, db.obligations, db.peerEndorseSeen = nil, nil, nil, nil
    if db.net then
      db.cloud = db.cloud or {}
      db.cloud.uploaderId = db.cloud.uploaderId or db.net.uploaderId
      db.net = nil
    end
    if db.params then
      for k in pairs(db.params) do if not FR.Params.byKey[k] then db.params[k] = nil end end
    end
  end,
}

-- Per-character steps run on each character's own schema version, so alts that
-- log in later are cleaned too (v1 kept notes and yes/no per character).
FR.CharMigrations = {
  [2] = function(cdb) cdb.affinity, cdb.endorseGiven = nil, nil end,
}

function FR:Migrate(db, cdb)
  local from = db.schemaVersion or 0
  for v = from + 1, FR.SCHEMA do
    local step = FR.Migrations[v]
    if step then step(db, cdb) end
  end
  db.schemaVersion = FR.SCHEMA
  for v = (cdb.schemaVersion or 0) + 1, FR.SCHEMA do
    local step = FR.CharMigrations[v]
    if step then step(cdb) end
  end
  cdb.schemaVersion = FR.SCHEMA
end

function FR:InitDB()
  ForeverRelationshipsDB = ForeverRelationshipsDB or {}
  ForeverRelationshipsCharDB = ForeverRelationshipsCharDB or {}
  ApplyDefaults(ForeverRelationshipsDB, DB_DEFAULTS)
  ApplyDefaults(ForeverRelationshipsCharDB, CHAR_DEFAULTS)
  self:Migrate(ForeverRelationshipsDB, ForeverRelationshipsCharDB)
  self.db = ForeverRelationshipsDB
  self.cdb = ForeverRelationshipsCharDB
  self.Params:Bind(self.db.params, self.db.changeLog, FR.Now)
  self.Log:Bind(self.db)
  for _, e in ipairs(self._pendingErrors) do self:RecordError(e.msg, e.where) end
  self._pendingErrors = {}
end

function FR:WipeEverything()
  ForeverRelationshipsDB = nil
  ForeverRelationshipsCharDB = nil
  self:InitDB()
  self:Fire("DATA_CHANGED")
end

if FR.frame then
  FR:On("ADDON_LOADED", function(_, name)
    if name ~= FR.name then return end
    FR:InitDB()
    FR:Fire("DB_READY")
  end)
  FR:On("PLAYER_LOGIN", function()
    FR.playerGUID = UnitGUID("player")
    FR.playerName = FR.FullName(UnitName("player"))
    FR:Fire("LOGIN")
  end)
end

_G.ForeverRelationships = FR -- exposed for /dump and other addons (read-only use)
