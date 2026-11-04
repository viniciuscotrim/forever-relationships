-- Append-only raw event log (GDD 3, 13). Pure Lua, no WoW API.
-- The log is the source of truth; every score is derived from it.
--
-- Event schema:
-- { id, t, signal, subjectGUID, subjectName, sessionId,
--   outcome (0..1 or nil), weight, source ("game"|"peer"|"human"|"questie"),
--   api (event/function that produced it), details (table) }
local _, TA = ...
TA = TA or {}

local Log = { ready = false, bySubject = {}, bySession = {}, count = 0 }
TA.Log = Log

local VALID_SOURCES = { game = true, peer = true, human = true, questie = true, system = true }

-- Keys that are never allowed anywhere in an event (no chat text, ever).
local FORBIDDEN = { text = true, message = true, msg = true, chat = true, body = true }

local function Scrub(t, depth)
  if type(t) ~= "table" or depth > 4 then return end
  for k, v in pairs(t) do
    if FORBIDDEN[k] then t[k] = nil
    elseif type(v) == "table" then Scrub(v, depth + 1) end
  end
end

function Log:Bind(db)
  self.db = db
  db.events = db.events or {}
  db.nextEventId = db.nextEventId or 1
  self:Reindex()
  self.ready = true
end

function Log:Reindex()
  self.bySubject, self.bySession = {}, {}
  for _, ev in ipairs(self.db.events) do self:_index(ev) end
  self.count = #self.db.events
end

function Log:_index(ev)
  if ev.subjectGUID then
    local l = self.bySubject[ev.subjectGUID]
    if not l then l = {}; self.bySubject[ev.subjectGUID] = l end
    l[#l + 1] = ev
  end
  if ev.sessionId then
    local l = self.bySession[ev.sessionId]
    if not l then l = {}; self.bySession[ev.sessionId] = l end
    l[#l + 1] = ev
  end
end

function Log:Append(ev)
  assert(self.db, "event log not bound")
  assert(type(ev.signal) == "string", "event needs a signal")
  ev.source = ev.source or "game"
  if not VALID_SOURCES[ev.source] then ev.source = "game" end
  ev.api = ev.api or "?"
  ev.details = ev.details or {}
  Scrub(ev.details, 0)
  ev.id = self.db.nextEventId
  self.db.nextEventId = ev.id + 1
  ev.t = ev.t or (TA.Now and TA.Now() or os.time())
  table.insert(self.db.events, ev)
  self:_index(ev)
  self.count = self.count + 1
  self:Prune()
  if TA.Fire then TA:Fire("EVENT_APPENDED", ev) end
  if TA.Debug then TA.Debug("event", ev.signal, ev.subjectName or "", ev.api) end
  return ev
end

function Log:Prune()
  local max = TA.Params and TA.Params.byKey["log.maxEvents"] and TA.Params:Get("log.maxEvents") or 100000
  local n = #self.db.events
  if n <= max then return end
  local drop = n - max
  for _ = 1, drop do table.remove(self.db.events, 1) end
  self:Reindex()
end

function Log:ForSubject(guid) return self.bySubject[guid] or {} end
function Log:ForSession(id) return self.bySession[id] or {} end
function Log:All() return self.db and self.db.events or {} end

-- filter = { subject = guid, signal = name, since = t, source = s, text = substring of name }
function Log:Query(filter)
  filter = filter or {}
  local src = filter.subject and self:ForSubject(filter.subject) or self:All()
  local out = {}
  local needle = filter.text and filter.text ~= "" and filter.text:lower() or nil
  for i = #src, 1, -1 do
    local ev = src[i]
    if (not filter.signal or ev.signal == filter.signal)
      and (not filter.since or ev.t >= filter.since)
      and (not filter.source or ev.source == filter.source)
      and (not needle or ((ev.subjectName or ""):lower():find(needle, 1, true))) then
      out[#out + 1] = ev
    end
  end
  return out
end

return Log
