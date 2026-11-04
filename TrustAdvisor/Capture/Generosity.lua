-- Small generosity (5.8). Positive only.
--  * Others -> you: a helpful aura from a non-group player, a resurrection
--    offer from a non-group player, a summon. Detected generically.
--  * You -> others: your buff/rez cast on a non-group player (Data/Generosity.lua).
local _, TA = ...

local Gen = {}
TA.Generosity = Gen

TA:RegisterCapture("generosityIn", "Generosity shown to you", "UNIT_AURA, RESURRECT_REQUEST, CONFIRM_SUMMON")
TA:RegisterCapture("generosityOut", "Your generosity to others", "UNIT_SPELLCAST_SENT, UNIT_SPELLCAST_SUCCEEDED")

local spellKind -- spell name -> kind
local dedupe = {}

local function BuildSpells()
  spellKind = {}
  local getName = (C_Spell and C_Spell.GetSpellName) or (GetSpellInfo and function(id) return (GetSpellInfo(id)) end)
  if not getName then return end
  for kind, list in pairs({ buff = TA.GenerositySpells.buffs, rez = TA.GenerositySpells.rez, summon = TA.GenerositySpells.summon }) do
    for _, id in ipairs(list or {}) do
      local ok, n = pcall(getName, id)
      if ok and type(n) == "string" then spellKind[n] = kind end
    end
  end
end

local function InMyGroup(guid)
  if not guid then return false end
  if guid == TA.playerGUID then return true end
  local s = TA.Sessions:Active()
  if s and s.members[guid] then
    local iv = s.members[guid].intervals[#s.members[guid].intervals]
    return iv and iv.leave == nil
  end
  return false
end

local function Record(guid, name, kind, api, extra)
  if not guid or not guid:find("^Player%-") then return end
  local key = guid .. ":" .. kind .. ":" .. tostring(extra or "")
  if dedupe[key] and TA.Now() - dedupe[key] < 600 then return end
  dedupe[key] = TA.Now()
  local s = TA.Sessions:Active()
  TA.Log:Append({ signal = "generosity", subjectGUID = guid, subjectName = name, sessionId = s and s.id,
    api = api, details = { kind = kind, spell = extra } })
end

local function GUIDForName(name)
  if not name then return nil end
  for _, u in ipairs({ "target", "mouseover", "focus" }) do
    local n = TA.Clean(UnitName(u))
    if n and TA.ShortName(n) == TA.ShortName(name) then return TA.Clean(UnitGUID(u)) end
  end
  return TA.Sessions:GUIDByName(name)
end

-- Others -> you: helpful auras from non-group players
TA:On("UNIT_AURA", function(_, unit, info)
  if unit ~= "player" or TA.InCombat() or type(info) ~= "table" or not info.addedAuras then return end
  for _, aura in ipairs(info.addedAuras) do
    local src, helpful = aura.sourceUnit, aura.isHelpful
    if not TA.IsSecret(src) and not TA.IsSecret(helpful) and helpful and type(src) == "string" then
      local guid = TA.Clean(UnitGUID(src))
      if guid and not InMyGroup(guid) and TA.SafeCall(UnitIsPlayer, src) then
        local n, r = UnitName(src)
        Record(guid, TA.FullName(TA.Clean(n), TA.Clean(r)), "buff", "UNIT_AURA", TA.Clean(aura.spellId))
      end
    end
  end
end, "generosityIn")

TA:On("RESURRECT_REQUEST", function(_, inviter)
  inviter = TA.Clean(inviter)
  local guid = GUIDForName(inviter)
  if guid and not InMyGroup(guid) then Record(guid, TA.FullName(inviter), "rez", "RESURRECT_REQUEST") end
end, "generosityIn")

TA:On("CONFIRM_SUMMON", function()
  local name = C_SummonInfo and TA.SafeCall(C_SummonInfo.GetSummonConfirmSummoner)
  local guid = GUIDForName(name)
  if guid then Record(guid, TA.FullName(name), "summon", "CONFIRM_SUMMON") end
end, "generosityIn")

-- You -> others
local pending = {}
TA:On("UNIT_SPELLCAST_SENT", function(_, unit, target, castGUID, spellID)
  if unit ~= "player" or TA.InCombat() then return end
  target, castGUID, spellID = TA.Clean(target), TA.Clean(castGUID), TA.Clean(spellID)
  if not (target and castGUID and spellID) or target == "" then return end
  pending[castGUID] = { target = target, spellID = spellID }
end, "generosityOut")

TA:On("UNIT_SPELLCAST_SUCCEEDED", function(_, unit, castGUID, spellID)
  if unit ~= "player" then return end
  castGUID = TA.Clean(castGUID)
  local p = castGUID and pending[castGUID]
  if not p then return end
  pending[castGUID] = nil
  if not spellKind then BuildSpells() end
  local getName = (C_Spell and C_Spell.GetSpellName) or (GetSpellInfo and function(id) return (GetSpellInfo(id)) end)
  local ok, n = pcall(getName, p.spellID)
  local kind = ok and spellKind[n]
  if not kind then return end
  local guid = GUIDForName(p.target)
  if guid and guid ~= TA.playerGUID and not InMyGroup(guid) then
    -- the act is yours: subject is you, the recipient is kept for context
    local key = TA.playerGUID .. ":" .. kind .. ":" .. guid
    if dedupe[key] and TA.Now() - dedupe[key] < 600 then return end
    dedupe[key] = TA.Now()
    local s = TA.Sessions:Active()
    TA.Log:Append({ signal = "generosity", subjectGUID = TA.playerGUID, subjectName = TA.playerName,
      sessionId = s and s.id, api = "UNIT_SPELLCAST_SUCCEEDED",
      details = { kind = kind, spell = p.spellID, recipientGUID = guid, recipientName = TA.FullName(p.target) } })
  end
end, "generosityOut")

-- Free portals: a group member casts a portal, you zone, and you paid them nothing.
local portalNames
local lastPortal -- { guid, name, t }
local function IsPortal(spellID)
  if not portalNames then
    portalNames = {}
    local getName = (C_Spell and C_Spell.GetSpellName) or (GetSpellInfo and function(id) return (GetSpellInfo(id)) end)
    for _, id in ipairs(TA.GenerositySpells.portal or {}) do
      portalNames[id] = true
      local ok, n = pcall(getName, id)
      if ok and type(n) == "string" then portalNames[n] = true end
    end
  end
  if portalNames[spellID] then return true end
  local getName = (C_Spell and C_Spell.GetSpellName) or (GetSpellInfo and function(id) return (GetSpellInfo(id)) end)
  local ok, n = pcall(getName, spellID)
  return ok and n and portalNames[n] or false
end

TA:On("UNIT_SPELLCAST_SUCCEEDED", function(_, unit, _, spellID)
  if type(unit) ~= "string" or not (unit:find("^party%d") or unit:find("^raid%d")) then return end
  spellID = TA.Clean(spellID)
  if not spellID or not IsPortal(spellID) then return end
  local guid = TA.Clean(UnitGUID(unit))
  if not guid then return end
  local n, r = UnitName(unit)
  lastPortal = { guid = guid, name = TA.FullName(TA.Clean(n), TA.Clean(r)), t = TA.Now(), spell = spellID }
end, "generosityIn")

local function PaidCaster(p, since)
  for _, ev in ipairs(TA.Log:ForSubject(p.guid)) do
    if ev.signal == "trade" and ev.t >= since and (ev.details.givenCopper or 0) > 0 then return true end
  end
  return false
end

TA:On("PLAYER_ENTERING_WORLD", function()
  local p = lastPortal
  if not p then return end
  local window = TA.Params:Get("generosity.portalWindowMinutes") * 60
  if TA.Now() - p.t > window then lastPortal = nil; return end
  lastPortal = nil
  -- give a tip made right after arrival a chance to land before judging
  C_Timer.After(window, function()
    if not PaidCaster(p, p.t - window) then
      Record(p.guid, p.name, "portal", "UNIT_SPELLCAST_SUCCEEDED (party portal) + zone change", p.spell)
    end
  end)
end, "generosityIn")

-- keep the pending table small
C_Timer.NewTicker(120, function() wipe(pending) end)
