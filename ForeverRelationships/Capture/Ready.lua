-- Arriving ready (5.3): at raid ready checks, record each member's response
-- and count consumable categories from their auras. Raids only, out of combat.
local _, FR = ...

local Ready = {}
FR.Ready = Ready

FR:RegisterCapture("ready", "Ready checks and consumables", "READY_CHECK, READY_CHECK_CONFIRM, C_UnitAuras")

local check -- { started, responses = { guid = bool } }
local nameToCategory

local function BuildNames()
  nameToCategory = {}
  local data = FR.Consumables
  if not data then return end
  local getName = (C_Spell and C_Spell.GetSpellName) or (GetSpellInfo and function(id) return (GetSpellInfo(id)) end)
  if getName then
    for id, cat in pairs(data.spells) do
      local ok, n = pcall(getName, id)
      if ok and type(n) == "string" then nameToCategory[n] = cat end
    end
  end
  for _, n in ipairs(data.names or {}) do nameToCategory[n] = "food" end
end

function Ready:CountCategories(unit)
  if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then
    FR:CaptureUnavailable("ready", "C_UnitAuras.GetAuraDataByIndex", "aura API missing")
    return nil
  end
  if not nameToCategory then BuildNames() end
  local seen, n = {}, 0
  for i = 1, 40 do
    local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, "HELPFUL")
    if not ok or not aura then break end
    local id, name = aura.spellId, aura.name
    if FR.IsSecret(id) or FR.IsSecret(name) then
      FR:CaptureUnavailable("ready", "C_UnitAuras", "auras are secret values on this client")
      return nil
    end
    local cat = FR.Consumables.spells[id] or nameToCategory[name]
    if cat and not seen[cat] then seen[cat] = true; n = n + 1 end
  end
  return n
end

local function Finish()
  if not check then return end
  local c = check
  check = nil
  local s = FR.Sessions:Active()
  if not s or not IsInRaid() or FR.InCombat() then return end
  for _, unit in ipairs(FR.Sessions.GroupUnits()) do
    local guid = FR.Clean(UnitGUID(unit))
    local m = guid and s.members[guid]
    if m then
      local cats = Ready:CountCategories(unit)
      if cats == nil then return end -- capture disabled
      local isReady = c.responses[guid]
      FR.Log:Append({ signal = "ready", subjectGUID = guid, subjectName = m.name, sessionId = s.id,
        api = "READY_CHECK_CONFIRM + C_UnitAuras", details = { isReady = isReady == true,
          responded = isReady ~= nil, categories = cats, dataVersion = FR.Consumables.version } })
    end
  end
end

FR:On("READY_CHECK", function(_, initiator)
  if not IsInRaid() then return end
  check = { started = FR.Now(), responses = {} }
  -- the initiator is implicitly ready
  initiator = FR.Clean(initiator)
  if initiator then
    for _, unit in ipairs(FR.Sessions.GroupUnits()) do
      local n = FR.Clean(UnitName(unit))
      if n and FR.ShortName(n) == FR.ShortName(initiator) then
        local g = FR.Clean(UnitGUID(unit))
        if g then check.responses[g] = true end
      end
    end
  end
end, "ready")

FR:On("READY_CHECK_CONFIRM", function(_, unit, isReady)
  if not check then return end
  local guid = FR.Clean(UnitGUID(unit))
  if guid and not FR.IsSecret(isReady) then check.responses[guid] = isReady and true or false end
end, "ready")

FR:On("READY_CHECK_FINISHED", function() C_Timer.After(0.5, Finish) end, "ready")
