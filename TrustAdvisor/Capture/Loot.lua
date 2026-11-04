-- Loot capture: loot received (for loot-and-leave, 5.2) and loot honesty
-- against an imported soft-reserve list (5.6). Reads the game's own
-- system loot lines, built from Blizzard's global format strings.
local _, TA = ...

local Loot = {}
TA.Loot = Loot

TA:RegisterCapture("lootReceived", "Loot received", "CHAT_MSG_LOOT (LOOT_ITEM)")
TA:RegisterCapture("lootRolls", "Group-loot rolls vs soft reserves", "CHAT_MSG_LOOT (LOOT_ROLL_NEED), C_PartyInfo.GetLootMethod")

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
  add(rollPatterns, "LOOT_ROLL_NEED_SELF", { self = true, kind = "need" })
  add(rollPatterns, "LOOT_ROLL_NEED", { kind = "need" })
  add(rollPatterns, "LOOT_ROLL_GREED_SELF", { self = true, kind = "greed" })
  add(rollPatterns, "LOOT_ROLL_GREED", { kind = "greed" })
  if #receivePatterns == 0 then TA:CaptureUnavailable("lootReceived", "LOOT_ITEM", "loot format strings missing") end
  if #rollPatterns == 0 then TA:CaptureUnavailable("lootRolls", "LOOT_ROLL_NEED", "roll format strings missing") end
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
-- Soft reserves (import)
-------------------------------------------------------------------------------
-- Accepts:
--  * softres.it CSV export (header with ItemId and Name columns)
--  * lines like "Name: 12345" / "12345, Name" / "Name - [item link]"
function Loot:ImportSoftReserves(text)
  local items, count = {}, 0
  local header
  for line in (text or ""):gmatch("[^\r\n]+") do
    local cols = {}
    for c in (line .. ","):gmatch('%s*"?([^,"]*)"?%s*,') do cols[#cols + 1] = c end
    if not header and line:lower():find("itemid") then
      header = {}
      for i, c in ipairs(cols) do header[c:lower()] = i end
    else
      local itemID, name
      if header and header.itemid and header.name then
        itemID, name = tonumber(cols[header.itemid]), cols[header.name]
      else
        itemID = ItemIDFromLink(line) or tonumber(line:match("(%d%d%d+)"))
        name = line:gsub("|c.-|r", ""):gsub("%d%d%d+", ""):gsub("[%[%]:,%-]", " "):match("([%a\128-\255]+)")
      end
      if itemID and name and name ~= "" then
        items[itemID] = items[itemID] or {}
        table.insert(items[itemID], name)
        count = count + 1
      end
    end
  end
  TA.db.softReserves = { items = items, importedAt = TA.Now(), count = count }
  return count
end

function Loot:ClearSoftReserves() TA.db.softReserves = {} end

function Loot:SoftReservesActive()
  local sr = TA.db.softReserves
  return sr and sr.items and (sr.count or 0) > 0
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

  for _, rp in ipairs(rollPatterns) do
    local a, b = text:match(rp.p)
    if a then
      local name, link = rp.self and nil or a, rp.self and a or b
      local guid, m = ResolveMember(name, rp.self)
      m = m or (guid and s.members[guid])
      if not (guid and m) or not Loot:SoftReservesActive() then return end
      m.srRolls = (m.srRolls or 0) + 1
      if rp.kind == "need" then
        local itemID = ItemIDFromLink(link)
        local reservers = itemID and TA.db.softReserves.items[itemID]
        if reservers then
          local short = TA.ShortName(m.name):lower()
          local others, guids, selfReserved = {}, {}, false
          for _, rn in ipairs(reservers) do
            if TA.ShortName(rn):lower() == short then selfReserved = true
            else
              others[#others + 1] = rn
              local rg = ResolveMember(rn) or TA.Sessions:GUIDByName(rn)
              if rg then guids[#guids + 1] = rg end
            end
          end
          TA.Log:Append({ signal = "lootNeed", subjectGUID = guid, subjectName = m.name, sessionId = s.id,
            api = "CHAT_MSG_LOOT", details = { itemID = itemID, reservedBy = others, reservedByGUIDs = guids,
              selfReserved = selfReserved, master = Loot:IsMasterLoot() } })
        end
      end
      return
    end
  end
end, "lootReceived")
