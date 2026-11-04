-- Small generosity (5.8). Positive only.
--  * Others -> you: a helpful aura from a non-group player, a resurrection
--    offer from a non-group player, a summon (warlock ritual or meeting stone),
--    a free mage portal. Detected generically.
--  * You -> others: your buff/rez cast on a non-group player, and your summons
--    (Ritual of Summoning on a group member). Spells in Data/Generosity.lua.
local _, FR = ...

local Gen = {}
FR.Generosity = Gen

FR:RegisterCapture("generosityIn", "Generosity shown to you", "UNIT_AURA, RESURRECT_REQUEST, CONFIRM_SUMMON")
FR:RegisterCapture("generosityOut", "Your generosity to others", "UNIT_SPELLCAST_SENT, UNIT_SPELLCAST_SUCCEEDED")

local spellKind -- spell name -> kind
local dedupe = {}

local function BuildSpells()
  spellKind = {}
  local getName = (C_Spell and C_Spell.GetSpellName) or (GetSpellInfo and function(id) return (GetSpellInfo(id)) end)
  if not getName then return end
  for kind, list in pairs({ buff = FR.GenerositySpells.buffs, rez = FR.GenerositySpells.rez, summon = FR.GenerositySpells.summon }) do
    for _, id in ipairs(list or {}) do
      local ok, n = pcall(getName, id)
      if ok and type(n) == "string" then spellKind[n] = kind end
    end
  end
end

local function InMyGroup(guid)
  if not guid then return false end
  if guid == FR.playerGUID then return true end
  local s = FR.Sessions:Active()
  if s and s.members[guid] then
    local iv = s.members[guid].intervals[#s.members[guid].intervals]
    return iv and iv.leave == nil
  end
  return false
end

local function Record(guid, name, kind, api, extra)
  if not guid or not guid:find("^Player%-") then return end
  local key = guid .. ":" .. kind .. ":" .. tostring(extra or "")
  if dedupe[key] and FR.Now() - dedupe[key] < 600 then return end
  dedupe[key] = FR.Now()
  local s = FR.Sessions:Active()
  FR.Log:Append({ signal = "generosity", subjectGUID = guid, subjectName = name, sessionId = s and s.id,
    api = api, details = { kind = kind, spell = extra } })
end

local function GUIDForName(name)
  if not name then return nil end
  for _, u in ipairs({ "target", "mouseover", "focus" }) do
    local n = FR.Clean(UnitName(u))
    if n and FR.ShortName(n) == FR.ShortName(name) then return FR.Clean(UnitGUID(u)) end
  end
  return FR.Sessions:GUIDByName(name)
end

-- Others -> you: helpful auras from non-group players
FR:On("UNIT_AURA", function(_, unit, info)
  if unit ~= "player" or FR.InCombat() or type(info) ~= "table" or not info.addedAuras then return end
  for _, aura in ipairs(info.addedAuras) do
    local src, helpful = aura.sourceUnit, aura.isHelpful
    if not FR.IsSecret(src) and not FR.IsSecret(helpful) and helpful and type(src) == "string" then
      local guid = FR.Clean(UnitGUID(src))
      if guid and not InMyGroup(guid) and FR.SafeCall(UnitIsPlayer, src) then
        local n, r = UnitName(src)
        Record(guid, FR.FullName(FR.Clean(n), FR.Clean(r)), "buff", "UNIT_AURA", FR.Clean(aura.spellId))
      end
    end
  end
end, "generosityIn")

FR:On("RESURRECT_REQUEST", function(_, inviter)
  inviter = FR.Clean(inviter)
  local guid = GUIDForName(inviter)
  if guid and not InMyGroup(guid) then Record(guid, FR.FullName(inviter), "rez", "RESURRECT_REQUEST") end
end, "generosityIn")

FR:On("CONFIRM_SUMMON", function()
  local name = C_SummonInfo and FR.SafeCall(C_SummonInfo.GetSummonConfirmSummoner)
  local guid = GUIDForName(name)
  if guid then Record(guid, FR.FullName(name), "summon", "CONFIRM_SUMMON") end
end, "generosityIn")

-- You -> others
local pending = {}
FR:On("UNIT_SPELLCAST_SENT", function(_, unit, target, castGUID, spellID)
  if unit ~= "player" or FR.InCombat() then return end
  target, castGUID, spellID = FR.Clean(target), FR.Clean(castGUID), FR.Clean(spellID)
  if not (target and castGUID and spellID) or target == "" then return end
  pending[castGUID] = { target = target, spellID = spellID }
end, "generosityOut")

FR:On("UNIT_SPELLCAST_SUCCEEDED", function(_, unit, castGUID, spellID)
  if unit ~= "player" then return end
  castGUID = FR.Clean(castGUID)
  local p = castGUID and pending[castGUID]
  if not p then return end
  pending[castGUID] = nil
  if not spellKind then BuildSpells() end
  local getName = (C_Spell and C_Spell.GetSpellName) or (GetSpellInfo and function(id) return (GetSpellInfo(id)) end)
  local ok, n = pcall(getName, p.spellID)
  local kind = ok and spellKind[n]
  if not kind then return end
  local guid = GUIDForName(p.target)
  -- Buffs and rezzes count when given to strangers (outside your group). A summon is
  -- always cast on a group member, so it counts inside the group.
  if guid and guid ~= FR.playerGUID and (kind == "summon" or not InMyGroup(guid)) then
    -- the act is yours: subject is you, the recipient is kept for context
    local key = FR.playerGUID .. ":" .. kind .. ":" .. guid
    if dedupe[key] and FR.Now() - dedupe[key] < 600 then return end
    dedupe[key] = FR.Now()
    local s = FR.Sessions:Active()
    FR.Log:Append({ signal = "generosity", subjectGUID = FR.playerGUID, subjectName = FR.playerName,
      sessionId = s and s.id, api = "UNIT_SPELLCAST_SUCCEEDED",
      details = { kind = kind, spell = p.spellID, recipientGUID = guid, recipientName = FR.FullName(p.target) } })
  end
end, "generosityOut")

-- Free portals: a group member casts a portal, you zone, and you paid them nothing.
local portalNames
local lastPortal -- { guid, name, t }
local function IsPortal(spellID)
  if not portalNames then
    portalNames = {}
    local getName = (C_Spell and C_Spell.GetSpellName) or (GetSpellInfo and function(id) return (GetSpellInfo(id)) end)
    for _, id in ipairs(FR.GenerositySpells.portal or {}) do
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

FR:On("UNIT_SPELLCAST_SUCCEEDED", function(_, unit, _, spellID)
  if type(unit) ~= "string" or not (unit:find("^party%d") or unit:find("^raid%d")) then return end
  spellID = FR.Clean(spellID)
  if not spellID or not IsPortal(spellID) then return end
  local guid = FR.Clean(UnitGUID(unit))
  if not guid then return end
  local n, r = UnitName(unit)
  lastPortal = { guid = guid, name = FR.FullName(FR.Clean(n), FR.Clean(r)), t = FR.Now(), spell = spellID }
end, "generosityIn")

local function PaidCaster(p, since)
  for _, ev in ipairs(FR.Log:ForSubject(p.guid)) do
    if ev.signal == "trade" and ev.t >= since and (ev.details.givenCopper or 0) > 0 then return true end
  end
  return false
end

FR:On("PLAYER_ENTERING_WORLD", function()
  local p = lastPortal
  if not p then return end
  local window = FR.Params:Get("generosity.portalWindowMinutes") * 60
  if FR.Now() - p.t > window then lastPortal = nil; return end
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
