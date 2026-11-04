-- Trade capture (Information): gold, items, enchants and crafted items you
-- exchanged with someone. Only trades your own client takes part in.
local _, FR = ...

local Trade = {}
FR.Trade = Trade

FR:RegisterCapture("trades", "Trades (gold, items, enchants)", "TRADE_SHOW, GetTargetTradeMoney, GetTradeTargetItemLink")

local current -- snapshot of the open trade

local function ItemIDFromLink(link)
  return link and tonumber(link:match("item:(%d+)"))
end

-- Slot 7 is the "will not be traded" slot. Its enchantment field is set when
-- someone applies an enchant. Return-value order differs between Mainline
-- and Classic, so take the first string after the item name.
local function SlotEnchant(fn)
  if not fn then return nil end
  local r = { pcall(fn, 7) }
  if not r[1] then return nil end
  local name = r[2]
  for i = 6, 7 do
    local v = r[i]
    if type(v) == "string" and v ~= "" and v ~= name and not FR.IsSecret(v) then return v end
  end
end

-- 5.10 crafted items: the tooltip of a crafted item carries "<Made by %s>".
local madeByPattern
local function CrafterOf(getter, i)
  if not (C_TooltipInfo and getter) then return nil end
  madeByPattern = madeByPattern or FR.PatternFromFormat(ITEM_CREATED_BY)
  if not madeByPattern then return nil end
  local ok, data = pcall(getter, i)
  if not ok or type(data) ~= "table" or not data.lines then return nil end
  for _, line in ipairs(data.lines) do
    local text = line.leftText
    if type(text) == "string" and not FR.IsSecret(text) then
      local who = text:match(madeByPattern)
      if who then return (who:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
    end
  end
end

local function Snapshot()
  if not current then return end
  current.givenCopper = FR.SafeCall(GetPlayerTradeMoney) or current.givenCopper or 0
  current.receivedCopper = FR.SafeCall(GetTargetTradeMoney) or current.receivedCopper or 0
  local given, received = {}, {}
  local ng, nr = 0, 0
  for i = 1, 6 do
    local g = ItemIDFromLink(FR.SafeCall(GetTradePlayerItemLink, i))
    local r = ItemIDFromLink(FR.SafeCall(GetTradeTargetItemLink, i))
    if g then given[g] = true; ng = ng + 1 end
    if r then received[r] = true; nr = nr + 1 end
  end
  current.givenItems = ng > 0 and given or nil
  current.receivedItems = nr > 0 and received or nil
  -- crafted items handed over by the person who made them
  local myName = FR.ShortName(FR.playerName or "")
  local craftedByMe, craftedByThem = 0, 0
  for i = 1, 6 do
    local mine = CrafterOf(C_TooltipInfo and C_TooltipInfo.GetTradePlayerItem, i)
    if mine and FR.ShortName(mine) == myName then craftedByMe = craftedByMe + 1 end
    local theirs = CrafterOf(C_TooltipInfo and C_TooltipInfo.GetTradeTargetItem, i)
    if theirs and FR.ShortName(theirs) == FR.ShortName(current.name or "") then craftedByThem = craftedByThem + 1 end
  end
  current.craftedByMe = craftedByMe > 0 and craftedByMe or nil
  current.craftedByThem = craftedByThem > 0 and craftedByThem or nil
  -- they enchanted MY item (sits in my slot 7), or I enchanted THEIRS
  current.enchantByThem = SlotEnchant(GetTradePlayerItemInfo) ~= nil
  current.enchantByMe = SlotEnchant(GetTradeTargetItemInfo) ~= nil
end

local function Commit()
  if not current or not current.guid then current = nil; return end
  local c = current
  current = nil
  local s = FR.Sessions:Active()
  local details = {
    givenCopper = c.givenCopper, receivedCopper = c.receivedCopper,
    givenItems = c.givenItems, receivedItems = c.receivedItems,
    enchantByThem = c.enchantByThem or nil, enchantByMe = c.enchantByMe or nil,
    craftedByThem = c.craftedByThem, craftedByMe = c.craftedByMe,
    inInstance = FR.Sessions:InInstanceSession() or nil,
  }
  if (c.givenCopper or 0) == 0 and (c.receivedCopper or 0) == 0 and not c.givenItems
    and not c.receivedItems and not c.enchantByMe and not c.enchantByThem
    and not c.craftedByMe and not c.craftedByThem then
    return
  end
  FR.Log:Append({ signal = "trade", subjectGUID = c.guid, subjectName = c.name, sessionId = s and s.id,
    api = "TRADE_ACCEPT_UPDATE + ERR_TRADE_COMPLETE", details = details })

  FR:Fire("DATA_CHANGED")
end

FR:On("TRADE_SHOW", function()
  local guid = FR.Clean(UnitGUID("NPC"))
  local name, realm = UnitName("NPC")
  name, realm = FR.Clean(name), FR.Clean(realm)
  if not guid or not guid:find("^Player%-") then current = nil; return end
  current = { guid = guid, name = FR.FullName(name, realm), givenCopper = 0, receivedCopper = 0 }
  if FR.Sessions.TouchPlayer and name then
    local _, classFile = UnitClass("NPC")
    FR.Sessions:TouchPlayer({ guid = guid, name = current.name, class = FR.Clean(classFile), level = FR.Clean(UnitLevel("NPC")) })
  end
end, "trades")

for _, ev in ipairs({ "TRADE_MONEY_CHANGED", "TRADE_PLAYER_ITEM_CHANGED", "TRADE_TARGET_ITEM_CHANGED", "TRADE_ACCEPT_UPDATE" }) do
  FR:On(ev, Snapshot, "trades")
end

FR:On("UI_INFO_MESSAGE", function(_, a, b)
  local msg = type(b) == "string" and b or a
  if FR.IsSecret(msg) then return end
  if msg == ERR_TRADE_COMPLETE then Commit() end
end, "trades")

FR:On("TRADE_CLOSED", function()
  -- TRADE_CLOSED can fire before UI_INFO_MESSAGE; give the completion message a moment.
  local c = current
  C_Timer.After(1, function() if current == c then current = nil end end)
end, "trades")

