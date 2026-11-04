-- Trust Advisor: namespace, utilities, event bus, SavedVariables, migrations.
local ADDON, TA = ...
TA = TA or {}
TA.name = ADDON or "TrustAdvisor"
TA.version = "0.3.0"
TA.SCHEMA = 1
TA.PREFIX = "TrustAdv"

-------------------------------------------------------------------------------
-- Generic utilities (safe without the WoW API so the pure modules can be tested)
-------------------------------------------------------------------------------
function TA.Now()
  if GetServerTime then return GetServerTime() end
  return os.time()
end

-- Midnight Secret Values: any value read from unit/aura/combat-adjacent APIs is
-- checked before use. A secret value is never stored, compared or concatenated.
function TA.IsSecret(v)
  if issecretvalue then
    local ok, res = pcall(issecretvalue, v)
    return (not ok) or res and true or false
  end
  return false
end

-- Returns v, or nil if it is secret.
function TA.Clean(v)
  if v == nil or TA.IsSecret(v) then return nil end
  return v
end

-- pcall a function; returns its results only if none of the first 4 is secret.
function TA.SafeCall(fn, ...)
  if type(fn) ~= "function" then return nil end
  local r = { pcall(fn, ...) }
  if not r[1] then return nil end
  for i = 2, math.min(#r, 5) do
    if TA.IsSecret(r[i]) then return nil end
  end
  return select(2, unpack(r))
end

function TA.InCombat()
  return InCombatLockdown and InCombatLockdown() or false
end

function TA.CopyTable(t)
  if type(t) ~= "table" then return t end
  local c = {}
  for k, v in pairs(t) do c[k] = TA.CopyTable(v) end
  return c
end

function TA.Round(x, n)
  local m = 10 ^ (n or 0)
  return math.floor(x * m + 0.5) / m
end

function TA.FormatDuration(sec)
  sec = math.max(0, math.floor(sec or 0))
  local h, m = math.floor(sec / 3600), math.floor((sec % 3600) / 60)
  if h > 0 then return string.format("%dh %dm", h, m) end
  return string.format("%dm", m)
end

function TA.FormatAgo(t)
  if not t then return "never" end
  local d = TA.Now() - t
  if d < 3600 then return string.format("%dm ago", math.floor(d / 60)) end
  if d < 86400 then return string.format("%dh ago", math.floor(d / 3600)) end
  return string.format("%dd ago", math.floor(d / 86400))
end

function TA.FormatDate(t)
  return date("%Y-%m-%d %H:%M", t or TA.Now())
end

function TA.FormatGold(copper)
  copper = copper or 0
  local g = math.floor(copper / 10000)
  local s = math.floor((copper % 10000) / 100)
  local c = copper % 100
  if g > 0 then return string.format("%dg %ds", g, s) end
  if s > 0 then return string.format("%ds %dc", s, c) end
  return string.format("%dc", c)
end

-- "Name-Realm" normalisation. Realm defaults to the player's realm.
function TA.FullName(name, realm)
  if not name then return nil end
  if name:find("-", 1, true) then return name end
  realm = (realm and realm ~= "") and realm or (GetNormalizedRealmName and GetNormalizedRealmName()) or ""
  if realm == "" then return name end
  return name .. "-" .. realm
end

function TA.ShortName(full)
  if not full then return "?" end
  return (full:gsub("%-.*$", ""))
end

local function Join(...)
  local parts = {}
  for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
  return table.concat(parts, " ")
end
TA.Join = Join

function TA.Print(...)
  local msg = "|cff33ccffTrust Advisor|r: " .. Join(...)
  if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(msg) else print(msg) end
end

function TA.Debug(...)
  if TA.db and TA.db.debug then
    local msg = "|cff888888[TA debug]|r " .. Join(...)
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(msg) else print(msg) end
  end
end

-------------------------------------------------------------------------------
-- Internal message bus (addon-level, not WoW events)
-------------------------------------------------------------------------------
TA._listeners = {}
function TA:Listen(msg, fn)
  self._listeners[msg] = self._listeners[msg] or {}
  table.insert(self._listeners[msg], fn)
end

function TA:Fire(msg, ...)
  local list = self._listeners[msg]
  if not list then return end
  for _, fn in ipairs(list) do
    local ok, err = pcall(fn, ...)
    if not ok then
      TA.Debug("listener error", msg, err)
      TA:RecordError(err, "listener " .. tostring(msg))
    end
  end
end

-------------------------------------------------------------------------------
-- Error capture. Every Trust Advisor error (caught handler errors and uncaught
-- Lua errors from our files) is recorded, deduplicated, and offered to the
-- player as a one-click feedback report (UI/Feedback.lua). Other addons'
-- errors are passed through untouched.
-------------------------------------------------------------------------------
TA._pendingErrors = {}
local MAX_ERRORS = 20

local function CleanError(msg)
  msg = tostring(msg or "?")
  msg = msg:gsub("Interface[/\\]AddOns[/\\]", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
  return msg:sub(1, 300)
end

function TA:RecordError(msg, where)
  local clean = CleanError(msg)
  local store = self.db and self.db.errors
  if not store then
    table.insert(self._pendingErrors, { msg = clean, where = where })
    return
  end
  for _, e in ipairs(store) do
    if e.msg == clean then
      e.count, e.last = e.count + 1, TA.Now()
      return
    end
  end
  table.insert(store, { msg = clean, where = where, count = 1, first = TA.Now(), last = TA.Now(), version = TA.version })
  while #store > MAX_ERRORS do table.remove(store, 1) end
  self:Fire("ERROR_RECORDED", store[#store])
end

if geterrorhandler and seterrorhandler then
  local previous = geterrorhandler()
  seterrorhandler(function(msg, ...)
    if type(msg) == "string" and msg:find("TrustAdvisor", 1, true) then
      pcall(TA.RecordError, TA, msg, "lua")
    end
    if previous then return previous(msg, ...) end
  end)
end

-------------------------------------------------------------------------------
-- Capture availability registry. A capture whose API is missing or returns
-- secret values disables itself and shows as unavailable in Transparency.
-------------------------------------------------------------------------------
TA.Captures = {}
TA.CaptureOrder = {}

function TA:RegisterCapture(name, label, apis)
  if not self.Captures[name] then table.insert(self.CaptureOrder, name) end
  self.Captures[name] = { name = name, label = label, apis = apis, status = "ok" }
end

function TA:CaptureUnavailable(name, api, reason)
  local c = self.Captures[name]
  if not c or c.status == "unavailable" then return end
  c.status = "unavailable"
  c.reason = reason or "API unavailable"
  c.failedApi = api
  if TA.Log and TA.Log.ready then
    TA.Log:Append({ signal = "capture", source = "game", api = api or "?",
      details = { capture = name, reason = c.reason } })
  end
  TA.Debug("capture unavailable:", name, api, reason)
end

function TA:CaptureOK(name)
  local c = self.Captures[name]
  return c and c.status == "ok"
end

-------------------------------------------------------------------------------
-- WoW event bus. Registration of an event that does not exist on this client
-- fails safely and marks the owning capture unavailable.
-------------------------------------------------------------------------------
TA._handlers = {}
if CreateFrame then
  TA.frame = CreateFrame("Frame", "TrustAdvisorEventFrame")
  TA.frame:SetScript("OnEvent", function(_, event, ...)
    local list = TA._handlers[event]
    if not list then return end
    -- nothing runs before SavedVariables are ready
    if not TA.db and event ~= "ADDON_LOADED" then return end
    for _, h in ipairs(list) do
      local ok, err = pcall(h.fn, event, ...)
      if not ok then
        h.errors = (h.errors or 0) + 1
        TA.Debug("handler error", event, err)
        TA:RecordError(err, "event " .. event)
        -- a capture that keeps failing disables itself instead of spamming errors
        if h.capture and h.errors >= 3 then TA:CaptureUnavailable(h.capture, event, "handler error: " .. tostring(err)) end
      end
    end
  end)
end

function TA:On(event, fn, capture)
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
  schemaVersion = TA.SCHEMA,
  params = {},          -- local overrides only (absent = default)
  changeLog = {},       -- parameter edits
  events = {},          -- append-only raw event log (source of truth)
  nextEventId = 1,
  players = {},         -- identity cache: guid -> {name, class, level, lastSeen, guilds}
  active = nil,         -- in-progress session (crash safe)
  signups = {},         -- raid signup plans
  softReserves = {},    -- itemID -> { "Name-Realm", ... }
  obligations = {},     -- unused store kept for ledger UI state
  peerEndorseSeen = {}, -- dedupe of peer endorsements
  debug = false,
  invisible = false,
  errors = {},          -- Trust Advisor's own errors (deduplicated), for feedback reports
  feedback = {},        -- { installId, outbox = { report, ... } } sent by the companion app
}

local CHAR_DEFAULTS = {
  schemaVersion = TA.SCHEMA,
  affinity = {},        -- guid -> { sessions = { {s,e,zone,chat,hour,wday} }, note, privateNo, privateYes }
  ui = {},
  suggestDismissed = {},
  endorseGiven = {},    -- guid -> last endorsement time
}

local function ApplyDefaults(t, defaults)
  for k, v in pairs(defaults) do
    if t[k] == nil then t[k] = TA.CopyTable(v) end
  end
end

-- Migration steps keyed by the version they upgrade *to*.
TA.Migrations = {
  -- [2] = function(db, cdb) ... end,
}

function TA:Migrate(db, cdb)
  local from = db.schemaVersion or 0
  for v = from + 1, TA.SCHEMA do
    local step = TA.Migrations[v]
    if step then step(db, cdb) end
  end
  db.schemaVersion = TA.SCHEMA
  cdb.schemaVersion = TA.SCHEMA
end

function TA:InitDB()
  TrustAdvisorDB = TrustAdvisorDB or {}
  TrustAdvisorCharDB = TrustAdvisorCharDB or {}
  ApplyDefaults(TrustAdvisorDB, DB_DEFAULTS)
  ApplyDefaults(TrustAdvisorCharDB, CHAR_DEFAULTS)
  self:Migrate(TrustAdvisorDB, TrustAdvisorCharDB)
  self.db = TrustAdvisorDB
  self.cdb = TrustAdvisorCharDB
  self.Params:Bind(self.db.params, self.db.changeLog, TA.Now)
  self.Log:Bind(self.db)
  for _, e in ipairs(self._pendingErrors) do self:RecordError(e.msg, e.where) end
  self._pendingErrors = {}
end

function TA:WipeEverything()
  TrustAdvisorDB = nil
  TrustAdvisorCharDB = nil
  self:InitDB()
  self:Fire("DATA_CHANGED")
end

if TA.frame then
  TA:On("ADDON_LOADED", function(_, name)
    if name ~= TA.name then return end
    TA:InitDB()
    TA:Fire("DB_READY")
  end)
  TA:On("PLAYER_LOGIN", function()
    TA.playerGUID = UnitGUID("player")
    TA.playerName = TA.FullName(UnitName("player"))
    TA:Fire("LOGIN")
  end)
end

_G.TrustAdvisor = TA -- exposed for /dump and other addons (read-only use)
