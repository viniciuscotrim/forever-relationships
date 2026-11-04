-- Parameter registry (GDD 8.3). Pure Lua, no WoW API.
-- Every number that influences any score lives here. A hard-coded scoring
-- constant anywhere else is a bug.
local _, TA = ...
TA = TA or {}

local Params = {}
TA.Params = Params

-- Dimension defaults (GDD 6.6). Half-life 0 = never decays.
-- type: "ratio" can go up or down; "acc" accumulates positive evidence only.
TA.DimensionDefaults = {
  { key = "attend",     label = "Showing up",             type = "ratio", weight = 1,   halfLifeNeg = 60,  halfLifePos = 365 },
  { key = "finish",     label = "Finishing",              type = "ratio", weight = 1,   halfLifeNeg = 60,  halfLifePos = 365 },
  { key = "ready",      label = "Arriving ready",         type = "ratio", weight = 0.5, halfLifeNeg = 30,  halfLifePos = 180 },
  { key = "pay",        label = "Paying what's owed",     type = "ratio", weight = 3,   halfLifeNeg = 180, halfLifePos = 365 },
  { key = "loot",       label = "Loot honesty",           type = "ratio", weight = 2,   halfLifeNeg = 120, halfLifePos = 365 },
  { key = "carry",      label = "Carry delivered",        type = "ratio", weight = 3,   halfLifeNeg = 180, halfLifePos = 365 },
  { key = "generosity", label = "Small generosity",       type = "acc",   weight = 0.2, halfLifePos = 180, cap = 10 },
  { key = "teach",      label = "Higher-level partner",   type = "acc",   weight = 1,   halfLifePos = 365, cap = 8 },
  { key = "craft",      label = "Crafting for others",    type = "acc",   weight = 0.5, halfLifePos = 365, cap = 10 },
  { key = "help",       label = "Stayed to help",         type = "acc",   weight = 1,   halfLifePos = 365, cap = 5 },
  { key = "hc",         label = "Hardcore steadfastness", type = "acc",   weight = 1,   halfLifePos = 365, cap = 5 },
  { key = "endorse",    label = "Endorsements",           type = "acc",   weight = 1,   halfLifePos = 180, cap = 6 },
}

local DEFS = {}      -- ordered list
local BY_KEY = {}

local function def(category, key, default, desc, opts)
  opts = opts or {}
  local d = {
    category = category, key = key, default = default, desc = desc,
    type = type(default) == "boolean" and "bool" or "number",
    min = opts.min, max = opts.max, affects = opts.affects or {},
    locked = opts.locked or false, scoring = opts.scoring ~= false,
  }
  if d.type == "number" and d.min == nil then d.min = 0 end
  table.insert(DEFS, d)
  BY_KEY[key] = d
end

-- Session
def("Session", "session.minMinutes", 5, "Sessions shorter than this are discarded as noise.", { affects = { "all" } })
-- Showing up
def("Showing up", "attend.lateMinutes", 10, "Minutes after raid start that still count as on time.", { affects = { "attend" } })
def("Showing up", "attend.lateOutcome", 0.5, "Outcome value for arriving late to a signed raid.", { affects = { "attend" }, max = 1 })
def("Showing up", "attend.withdrawHours", 4, "Signups withdrawn earlier than this before start don't count.", { affects = { "attend" } })
-- Finishing
def("Finishing", "finish.lootLeaveMinutes", 10, "Leaving within this many minutes of receiving loot, before the final boss, is loot-and-leave.", { affects = { "finish" } })
def("Finishing", "finish.lootMinQuality", 2, "Minimum item quality (0 poor, 1 common, 2 uncommon, 3 rare, 4 epic) that counts as loot for loot-and-leave.", { affects = { "finish" }, max = 5 })
def("Finishing", "finish.lootLeaveWeight", 3, "Weight multiplier for a loot-and-leave.", { affects = { "finish" } })
def("Finishing", "finish.dcGraceMinutes", 10, "A disconnect that returns within this period is excused.", { affects = { "finish" } })
def("Finishing", "finish.wipeCountExcuse", 3, "Leaving after this many consecutive wipes is excused.", { affects = { "finish" } })
def("Finishing", "finish.requireLeaveMessage", true, "Only count an early leave if the game printed a voluntary-leave message (protects people who were removed).", { affects = { "finish", "carry" } })
-- Ready
def("Arriving ready", "ready.minBuffCategories", 1, "Consumable categories required at a raid ready check.", { affects = { "ready" } })
-- Paying
def("Paying", "pay.deadlineHours", 24, "Hours to settle an obligation. Paid later counts as late (0.5).", { affects = { "pay" } })
def("Paying", "pay.lateOutcome", 0.5, "Outcome value for an obligation paid after the deadline.", { affects = { "pay" }, max = 1 })
-- Loot
def("Loot honesty", "loot.returnMinutes", 60, "An item traded back to its reserver within this cancels the strike.", { affects = { "loot" } })
-- Carry
def("Carry", "carry.minGold", 1, "Minimum gold traded to mark a run as a paid carry.", { affects = { "carry" } })
def("Carry", "carry.autoDetect", true, "Treat a gold trade inside an instance, before the final boss, as carry payment.", { affects = { "carry" } })
-- Generosity
def("Generosity", "generosity.dailyCap", 10, "Maximum acts of generosity counted per player per day.", { affects = { "generosity" } })
-- Teaching
def("Teaching", "teach.levelGap", 5, "Levels above the group median to count as a higher-level partner.", { affects = { "teach" } })
def("Teaching", "teach.minMinutes", 20, "Minimum time in the session to count.", { affects = { "teach" } })
def("Teaching", "teach.learningBonus", 1.5, "Weight multiplier when the group listing used the Learning playstyle.", { affects = { "teach" } })
-- Crafting
def("Crafting", "craft.atCostMultiplier", 2, "Weight multiplier for free or at-cost crafts.", { affects = { "craft" } })
def("Crafting", "craft.atCostGold", 1, "Payment at or below this many gold counts as free/at cost.", { affects = { "craft" } })
-- Helping
def("Helping", "help.stayMinutes", 10, "Minutes a partner must stay grouped after finishing their own shared quest.", { affects = { "help" } })
-- Hardcore
def("Hardcore", "hc.fleeSeconds", 30, "Leaving the group within this many seconds of a party death counts as fled.", { affects = { "hc" } })
def("Hardcore", "hc.fleeScored", false, "Whether fleeing reduces steadfastness evidence (fleeing can be correct play).", { affects = { "hc" } })
-- Endorsement
def("Endorsement", "endorse.minMinutes", 30, "Session length before the 'Play again?' prompt appears.", { affects = { "endorse" } })
def("Endorsement", "endorse.cooldownDays", 7, "One endorsement per pair per this many days.", { affects = { "endorse" } })
def("Endorsement", "endorse.sameGuildMultiplier", 0.5, "Weight of an endorsement from the same guild.", { affects = { "endorse" }, max = 1 })
-- Affinity (never touches trust)
def("Affinity", "affinity.windowDays", 90, "Days of history used for the private affinity summary.", { affects = { "affinity" }, scoring = false })
-- Prior
def("Prior", "prior.value", 0.75, "Starting assumption for ratio dimensions ('assume decent').", { affects = { "ratio" }, max = 1 })
def("Prior", "prior.strength", 3, "Weight of the prior, in equivalent events.", { affects = { "ratio" } })
-- Confidence
def("Confidence", "conf.minEvidence", 3, "Below this much evidence the band shows Unknown.", { affects = { "all" } })
def("Confidence", "conf.highAt", 10, "Evidence at or above this is High confidence.", { affects = { "all" } })
-- Bands
def("Bands", "band.concern", 0.50, "Ratio score below this is Concern.", { affects = { "ratio" }, max = 1 })
def("Bands", "band.solid", 0.75, "Ratio score at or above this is Solid.", { affects = { "ratio" }, max = 1 })
def("Bands", "band.exemplary", 0.90, "Ratio score at or above this is Exemplary.", { affects = { "ratio" }, max = 1 })
def("Bands", "band.accSolid", 0.40, "Accumulating score at or above this is Solid.", { affects = { "acc" }, max = 1 })
def("Bands", "band.accExemplary", 0.75, "Accumulating score at or above this is Exemplary.", { affects = { "acc" }, max = 1 })

-- Dimensions (generated from GDD 6.6)
for _, d in ipairs(TA.DimensionDefaults) do
  def("Dimensions", "dim." .. d.key .. ".weight", d.weight, d.label .. ": base weight per event.", { affects = { d.key } })
  if d.type == "ratio" then
    def("Dimensions", "dim." .. d.key .. ".halfLifeNeg", d.halfLifeNeg, d.label .. ": negative event half-life in days (0 = never decays).", { affects = { d.key } })
  end
  def("Dimensions", "dim." .. d.key .. ".halfLifePos", d.halfLifePos, d.label .. ": positive event half-life in days (0 = never decays).", { affects = { d.key } })
  if d.type == "acc" then
    def("Dimensions", "dim." .. d.key .. ".cap", d.cap, d.label .. ": soft-cap constant c (higher = slower growth).", { affects = { d.key }, min = 0.1 })
  end
end

-- Social (do not affect scores)
def("Social", "presence.enabled", false, "Broadcast presence (zone, level, LFG flag) to nearby Trust Advisor users.", { scoring = false })
def("Social", "presence.intervalSeconds", 60, "Presence broadcast interval.", { scoring = false, min = 15 })
def("Social", "presence.shareQuests", false, "Include active quest IDs in presence broadcasts.", { scoring = false })
def("Social", "presence.levelRange", 5, "Level difference that still counts as a nearby match.", { scoring = false })
def("Social", "suggest.friendAfterSessions", 3, "Good sessions before suggesting to add a friend.", { scoring = false, min = 1 })
def("Social", "suggest.regroupMinSessions", 2, "Past sessions before a 'group again?' toast.", { scoring = false, min = 1 })
def("Social", "suggest.regroupCooldownMinutes", 60, "Minimum minutes between regroup toasts for the same player.", { scoring = false })
-- Consent (all off until enabled, GDD 11)
def("Consent", "consent.endorsePrompts", false, "Show the 'Play with them again?' prompt after qualifying sessions.", { scoring = false })
def("Consent", "consent.shareEndorsements", false, "Send your endorsements to the endorsed player and your group (Phase 2).", { scoring = false })
def("Consent", "consent.shareQuests", false, "Tell group members (with Trust Advisor) when you turn in a quest.", { scoring = false })
def("Consent", "consent.shareAttunements", false, "Share your attunement list with group members who have Trust Advisor.", { scoring = false })
def("Consent", "consent.acceptPeerEndorsements", true, "Count endorsements other Trust Advisor users send about people you witnessed grouping with them.", { affects = { "endorse" } })
-- Display
def("Display", "tooltip.enabled", true, "Show the Trust Advisor line in unit tooltips.", { scoring = false })
def("Display", "tooltip.onlyNotable", false, "Tooltip shows only Concern and Exemplary bands, to reduce noise.", { scoring = false })
-- Storage
def("Storage", "log.maxEvents", 100000, "Oldest events are pruned beyond this count (the log is the source of truth, keep it large).", { scoring = false, min = 1000 })
-- Network (Phase 3, visible but locked to the published protocol)
def("Network", "net.minWitnesses", 2, "Independent witnesses required for a network-view negative.", { locked = true })
def("Network", "net.minGuilds", 2, "Distinct guilds required among those witnesses.", { locked = true })

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
  if not d then error("Unknown Trust Advisor parameter: " .. tostring(key)) end
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
  if TA.Fire then TA:Fire("PARAMS_CHANGED", key) end
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

-- Flat snapshot table used by the scoring engine.
function Params:Snapshot()
  local P = {}
  for _, d in ipairs(DEFS) do P[d.key] = self:Get(d.key) end
  return P
end

return Params
