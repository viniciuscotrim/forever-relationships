-- Developer probe: /ta probe on|off|show|clear
-- Records spells cast by you and your group/raid (spell id, name, caster), plus
-- summon/zone events, so mechanics can be validated on the live client
-- (e.g. which spell the Ritual of Summoning / meeting stone "clickers" cast).
-- Off by default, never broadcast, no chat text. Stored in TrustAdvisorDB.probe.
local _, TA = ...

local Probe = {}
TA.Probe = Probe

local MAX = 1000

local function Store()
  TA.db.probe = TA.db.probe or { on = false, rows = {} }
  return TA.db.probe
end

function Probe:On() return TA.db and Store().on end

function Probe:Set(on)
  local p = Store()
  p.on = on and true or false
  if on then p.startedAt = TA.Now() end
  TA.Print("Probe " .. (p.on and "ON: recording spells cast by you and your group. /ta probe off when done." or "off.") .. " " .. #p.rows .. " rows recorded.")
end

function Probe:Add(kind, fields)
  if not self:On() then return end
  local rows = Store().rows
  fields.t = TA.Now()
  fields.kind = kind
  fields.zone = GetRealZoneText and GetRealZoneText() or nil
  table.insert(rows, fields)
  while #rows > MAX do table.remove(rows, 1) end
end

local function SpellName(id)
  local getName = (C_Spell and C_Spell.GetSpellName) or (GetSpellInfo and function(x) return (GetSpellInfo(x)) end)
  local ok, n = pcall(getName, id)
  return ok and type(n) == "string" and n or nil
end

local function GroupUnit(unit)
  return type(unit) == "string" and (unit == "player" or unit:find("^party%d") or unit:find("^raid%d"))
end

for _, ev in ipairs({ "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_SUCCEEDED" }) do
  TA:On(ev, function(event, unit, _, spellID)
    if not Probe:On() or not GroupUnit(unit) then return end
    spellID = TA.Clean(spellID)
    if not spellID then return end
    local n, r = UnitName(unit)
    Probe:Add("cast", { event = event, unit = unit, caster = TA.FullName(TA.Clean(n), TA.Clean(r)),
      spellID = spellID, spell = SpellName(spellID) })
  end)
end

TA:On("UNIT_SPELLCAST_SENT", function(_, unit, target, _, spellID)
  if not Probe:On() or unit ~= "player" then return end
  spellID = TA.Clean(spellID)
  if spellID then Probe:Add("sent", { spellID = spellID, spell = SpellName(spellID), target = TA.Clean(target) }) end
end)

TA:On("CONFIRM_SUMMON", function()
  if not Probe:On() then return end
  local summoner = C_SummonInfo and TA.SafeCall(C_SummonInfo.GetSummonConfirmSummoner)
  local area = C_SummonInfo and TA.SafeCall(C_SummonInfo.GetSummonConfirmAreaName)
  Probe:Add("summonOffer", { summoner = summoner, area = area })
end)

TA:On("PLAYER_ENTERING_WORLD", function() Probe:Add("zone", {}) end)

function Probe:Text()
  local p = Store()
  local L = { string.format("Trust Advisor probe: %d rows (%s)", #p.rows, p.on and "recording" or "stopped") }
  for _, r in ipairs(p.rows) do
    if r.kind == "cast" then
      L[#L + 1] = string.format("%s  %-26s %-9s %-8s %6s %s", date("%H:%M:%S", r.t), r.event, r.unit, TA.ShortName(r.caster or "?"), r.spellID, r.spell or "?")
    elseif r.kind == "sent" then
      L[#L + 1] = string.format("%s  SENT  %6s %s -> %s", date("%H:%M:%S", r.t), r.spellID, r.spell or "?", r.target or "-")
    elseif r.kind == "summonOffer" then
      L[#L + 1] = string.format("%s  SUMMON OFFER from %s to %s", date("%H:%M:%S", r.t), r.summoner or "?", r.area or "?")
    else
      L[#L + 1] = string.format("%s  ZONE %s", date("%H:%M:%S", r.t), r.zone or "?")
    end
  end
  return L
end

function Probe:Clear() Store().rows = {} end
