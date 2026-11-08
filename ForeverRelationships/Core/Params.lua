-- Parameter registry (GDD 8.3). Pure Lua, no WoW API.
-- Every number that influences any score lives here. A hard-coded scoring
-- constant anywhere else is a bug.
local _, FR = ...
FR = FR or {}

local Params = {}
FR.Params = Params

local DEFS = {}      -- ordered list
local BY_KEY = {}

local function def(category, key, default, desc, opts)
  opts = opts or {}
  local d = {
    category = category, key = key, default = default, desc = desc,
    type = type(default) == "boolean" and "bool" or "number",
    min = opts.min, max = opts.max, affects = opts.affects or {},
    locked = opts.locked or false, scoring = false,
  }
  if d.type == "number" and d.min == nil then d.min = 0 end
  table.insert(DEFS, d)
  BY_KEY[key] = d
end

-- What counts (GDD v2: facts and patterns only; no scores)
def("History", "session.minMinutes", 5, "Groups shorter than this don't count as time together (layer hops, quick invites).")
def("History", "history.retentionDays", 365, "Local history older than this is deleted automatically (0 = keep forever).")
def("History", "generosity.portalWindowMinutes", 10, "A group member's portal counts as help if you zone within this many minutes and paid them nothing.")
-- Consent: every layer that leaves your computer starts OFF (GDD v2 §2)
def("Consent", "consent.backup", false, "Cloud backup: an end-to-end encrypted copy of your history. Only you can read it (key + recovery code on your side).")
def("Consent", "consent.profile", false, "Public profile: other Forever Relationships players can see the items YOU choose about yourself.")
def("Consent", "consent.community", false, "Community: contribute your group sessions, pseudonymized, to anonymous statistics.")
def("Consent", "consent.recommend", false, "Recommend me: other participants may get you suggested as someone to play with.")
def("Consent", "consent.shareQuests", false, "Tell group members (with Forever Relationships) when you turn in a quest.")
def("Consent", "consent.shareAttunements", false, "Share your attunement list with group members who have Forever Relationships.")
-- Social (suggestions, never automatic actions)
def("Social", "presence.enabled", false, "Show you to nearby Forever Relationships users (zone, level, LFG flag).")
def("Social", "presence.intervalSeconds", 60, "Presence broadcast interval.", { min = 15 })
def("Social", "presence.shareQuests", false, "Include active quest IDs in presence broadcasts.")
def("Social", "presence.levelRange", 5, "Level difference that still counts as a nearby match.")
def("Social", "suggest.friendAfterSessions", 3, "Sessions together before suggesting to add a friend.", { min = 1 })
def("Social", "suggest.regroupMinSessions", 2, "Sessions together before a 'they're online, invite?' toast.", { min = 1 })
def("Social", "suggest.regroupCooldownMinutes", 60, "Minimum minutes between invite toasts for the same player.")
def("Social", "announce.party", true, "Say in party chat that the group uses Forever Relationships when a party forms and when someone joins (one line; only one addon user posts).")
-- Nearby alert (pop-up when someone you have history with comes into view)
def("Nearby", "nearby.alert", true, "Show a pop-up when someone you have history with comes into view (nameplates, mouseover, target).")
def("Nearby", "nearby.alertRivals", true, "Also alert for opposite-faction players you have fought.")
def("Nearby", "nearby.alertCooldownMinutes", 30, "Minutes before the same player can trigger the alert again.", { min = 1 })
def("Nearby", "nearby.alertSeconds", 10, "Seconds the alert stays on screen (0 = until you close it).")
def("Nearby", "nearby.alertSound", true, "Play a sound with the alert.")
-- Rivals (opposite faction)
def("Rivals", "rivals.crossingGapMinutes", 15, "Minutes without seeing a rival before seeing them again counts as a new crossing.", { min = 1 })
-- Groups (automatic membership)
def("Groups", "groups.questHelper", 3, "Quests completed together (or help received) to join Quest Helper automatically.", { min = 1 })
def("Groups", "groups.dungeonBuddy", 2, "Dungeons completed together to join Dungeon Buddy automatically.", { min = 1 })
def("Groups", "groups.raidChampion", 2, "Raids completed together to join Raid Champion automatically.", { min = 1 })
def("Groups", "groups.rival", 1, "Battles with an opposite-faction player to join Rival automatically.", { min = 1 })
-- Display
def("Display", "tooltip.rivals", true, "Show your rivalry (crossings, battles, victories) in the tooltip of opposite-faction players.")
def("Display", "tooltip.enabled", true, "Show your relationship in unit tooltips.")
def("Display", "tooltip.lfgMarker", true, "Show a small marker on LFG listings whose leader you've played with.")
-- Storage
def("Storage", "log.maxEvents", 100000, "Oldest events are pruned beyond this count.", { min = 1000 })

Params.defs = DEFS
Params.byKey = BY_KEY
Params.version = 0
Params.values = {}
Params.log = {}
Params.clock = os and os.time or function() return 0 end

function Params:Bind(store, changeLog, clock)
  self.values = store or {}
  self.log = changeLog or {}
  self.clock = clock or self.clock
  -- drop overrides for keys that no longer exist or are locked
  for k in pairs(self.values) do
    if not BY_KEY[k] or BY_KEY[k].locked then self.values[k] = nil end
  end
  self.version = self.version + 1
end

function Params:Get(key)
  local d = BY_KEY[key]
  if not d then error("Unknown Forever Relationships parameter: " .. tostring(key)) end
  local v = self.values[key]
  if v == nil then return d.default end
  return v
end

function Params:Default(key) return BY_KEY[key] and BY_KEY[key].default end

function Params:IsDefault(key)
  return self.values[key] == nil or self.values[key] == BY_KEY[key].default
end

-- Validate and coerce. Returns value or nil, err.
function Params:Validate(key, value)
  local d = BY_KEY[key]
  if not d then return nil, "unknown parameter" end
  if d.locked then return nil, "locked to the published network protocol" end
  if d.type == "bool" then
    if type(value) == "string" then
      value = value:lower()
      if value == "true" or value == "1" or value == "on" or value == "yes" then return true end
      if value == "false" or value == "0" or value == "off" or value == "no" then return false end
      return nil, "expected true/false"
    end
    return value and true or false
  end
  value = tonumber(value)
  if not value then return nil, "expected a number" end
  if d.min and value < d.min then return nil, "minimum is " .. d.min end
  if d.max and value > d.max then return nil, "maximum is " .. d.max end
  return value
end

function Params:Set(key, value)
  local v, err = self:Validate(key, value)
  if v == nil then return false, err end
  local old = self:Get(key)
  if old == v then return true end
  if v == BY_KEY[key].default then self.values[key] = nil else self.values[key] = v end
  table.insert(self.log, { t = self.clock(), key = key, old = old, new = v })
  self.version = self.version + 1
  if FR.Fire then FR:Fire("PARAMS_CHANGED", key) end
  return true
end

function Params:Reset(key)
  return self:Set(key, BY_KEY[key].default)
end

function Params:ResetAll()
  for _, d in ipairs(DEFS) do
    if not d.locked and not self:IsDefault(d.key) then self:Set(d.key, d.default) end
  end
end

-- True if any parameter that affects scoring differs from default.
function Params:AnyScoringNonDefault()
  for k in pairs(self.values) do
    local d = BY_KEY[k]
    if d and d.scoring and not self:IsDefault(k) then return true end
  end
  return false
end

function Params:NonDefaultList()
  local out = {}
  for _, d in ipairs(DEFS) do
    if not self:IsDefault(d.key) then table.insert(out, d) end
  end
  return out
end

-- Snapshot of the published defaults (network view ignores local overrides).
function Params:DefaultSnapshot()
  local P = {}
  for _, d in ipairs(DEFS) do P[d.key] = d.default end
  return P
end

-- Flat snapshot table used by the scoring engine.
function Params:Snapshot()
  local P = {}
  for _, d in ipairs(DEFS) do P[d.key] = self:Get(d.key) end
  return P
end

return Params
