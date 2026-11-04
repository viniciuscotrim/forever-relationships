-- Loot capture: who received what in your group (Information). Reads the
-- game's own system loot lines, built from Blizzard's global format strings.
local _, TA = ...

local Loot = {}
TA.Loot = Loot

TA:RegisterCapture("lootReceived", "Loot received", "CHAT_MSG_LOOT (LOOT_ITEM)")

local receivePatterns, rollPatterns

local function Build()
  receivePatterns, rollPatterns = {}, {}
  local function add(list, g, extra)
    local p = TA.PatternFromFormat(_G[g])
    if p then local e = extra or {}; e.p = p; list[#list + 1] = e end
  end
  add(receivePatterns, "LOOT_ITEM_SELF_MULTIPLE", { self = true })
  add(receivePatterns, "LOOT_ITEM_SELF", { self = true })
  add(receivePatterns, "LOOT_ITEM_MULTIPLE", {})
  add(receivePatterns, "LOOT_ITEM", {})
  if #receivePatterns == 0 then TA:CaptureUnavailable("lootReceived", "LOOT_ITEM", "loot format strings missing") end
end

local function ItemIDFromLink(link)
  return link and tonumber(link:match("item:(%d+)"))
end

local function QualityOf(link)
  local q = link and select(3, GetItemInfo(link))
  if q then return q end
  local hex = link and link:match("|c%x%x(%x%x%x%x%x%x)")
  local map = { ["9d9d9d"] = 0, ffffff = 1, ["1eff00"] = 2, ["0070dd"] = 3, a335ee = 4, ff8000 = 5 }
  return hex and map[hex:lower()] or 1
end

local function ResolveMember(name, isSelf)
  if isSelf then return TA.playerGUID end
  local s = TA.Sessions:Active()
  if not s or not name then return nil end
  local short = TA.ShortName(name):lower()
  for guid, m in pairs(s.members) do
    if TA.ShortName(m.name):lower() == short then return guid, m end
  end
end

function Loot:IsMasterLoot()
  if C_PartyInfo and C_PartyInfo.GetLootMethod then
    local ok, method = pcall(C_PartyInfo.GetLootMethod)
    if ok and method ~= nil and not TA.IsSecret(method) then
      if type(method) == "string" then return method == "master" end
      local enum = Enum and Enum.LootMethod
      return enum and (method == enum.Masterlooter or method == enum.MasterLooter) or false
    end
  end
  if GetLootMethod then
    local ok, method = pcall(GetLootMethod)
    return ok and method == "master"
  end
  return false
end

-------------------------------------------------------------------------------
-- Events
-------------------------------------------------------------------------------
TA:On("CHAT_MSG_LOOT", function(_, text)
  if not receivePatterns then Build() end
  if TA.IsSecret(text) or type(text) ~= "string" then return end
  local s = TA.Sessions:Active()
  if not s then return end

  for _, rp in ipairs(receivePatterns) do
    local a, b = text:match(rp.p)
    if a then
      local name, link = rp.self and nil or a, rp.self and a or b
      local guid, m = ResolveMember(name, rp.self)
      m = m or (guid and s.members[guid])
      if m then
        table.insert(m.lootTimes, { t = TA.Now(), q = QualityOf(link) })
      end
      return
    end
  end

end, "lootReceived")
