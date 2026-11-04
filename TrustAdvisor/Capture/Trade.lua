-- Trade capture: paying what's owed (5.5), carry payment (5.7), crafting for
-- others (5.10). Only trades your own client takes part in are witnessed.
local _, TA = ...

local Trade = {}
TA.Trade = Trade

TA:RegisterCapture("trades", "Trades (gold, items, enchants)", "TRADE_SHOW, GetTargetTradeMoney, GetTradeTargetItemLink")

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
    if type(v) == "string" and v ~= "" and v ~= name and not TA.IsSecret(v) then return v end
  end
end

-- 5.10 crafted items: the tooltip of a crafted item carries "<Made by %s>".
local madeByPattern
local function CrafterOf(getter, i)
  if not (C_TooltipInfo and getter) then return nil end
  madeByPattern = madeByPattern or TA.PatternFromFormat(ITEM_CREATED_BY)
  if not madeByPattern then return nil end
  local ok, data = pcall(getter, i)
  if not ok or type(data) ~= "table" or not data.lines then return nil end
  for _, line in ipairs(data.lines) do
    local text = line.leftText
    if type(text) == "string" and not TA.IsSecret(text) then
      local who = text:match(madeByPattern)
      if who then return (who:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
    end
  end
end

local function Snapshot()
  if not current then return end
  current.givenCopper = TA.SafeCall(GetPlayerTradeMoney) or current.givenCopper or 0
  current.receivedCopper = TA.SafeCall(GetTargetTradeMoney) or current.receivedCopper or 0
  local given, received = {}, {}
  local ng, nr = 0, 0
  for i = 1, 6 do
    local g = ItemIDFromLink(TA.SafeCall(GetTradePlayerItemLink, i))
    local r = ItemIDFromLink(TA.SafeCall(GetTradeTargetItemLink, i))
    if g then given[g] = true; ng = ng + 1 end
    if r then received[r] = true; nr = nr + 1 end
  end
  current.givenItems = ng > 0 and given or nil
  current.receivedItems = nr > 0 and received or nil
  -- crafted items handed over by the person who made them
  local myName = TA.ShortName(TA.playerName or "")
  local craftedByMe, craftedByThem = 0, 0
  for i = 1, 6 do
    local mine = CrafterOf(C_TooltipInfo and C_TooltipInfo.GetTradePlayerItem, i)
    if mine and TA.ShortName(mine) == myName then craftedByMe = craftedByMe + 1 end
    local theirs = CrafterOf(C_TooltipInfo and C_TooltipInfo.GetTradeTargetItem, i)
    if theirs and TA.ShortName(theirs) == TA.ShortName(current.name or "") then craftedByThem = craftedByThem + 1 end
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
  local s = TA.Sessions:Active()
  local details = {
    givenCopper = c.givenCopper, receivedCopper = c.receivedCopper,
    givenItems = c.givenItems, receivedItems = c.receivedItems,
    enchantByThem = c.enchantByThem or nil, enchantByMe = c.enchantByMe or nil,
    craftedByThem = c.craftedByThem, craftedByMe = c.craftedByMe,
    inInstance = TA.Sessions:InInstanceSession() or nil,
  }
  if (c.givenCopper or 0) == 0 and (c.receivedCopper or 0) == 0 and not c.givenItems
    and not c.receivedItems and not c.enchantByMe and not c.enchantByThem
    and not c.craftedByMe and not c.craftedByThem then
    return
  end
  TA.Log:Append({ signal = "trade", subjectGUID = c.guid, subjectName = c.name, sessionId = s and s.id,
    api = "TRADE_ACCEPT_UPDATE + ERR_TRADE_COMPLETE", details = details })

  -- 5.7: gold trade inside an instance session marks the recipient as carrier.
  if s and TA.Sessions:InInstanceSession() then
    local payer, carrier, copper
    if (c.givenCopper or 0) > 0 then payer, carrier, copper = TA.playerGUID, c.guid, c.givenCopper
    elseif (c.receivedCopper or 0) > 0 then payer, carrier, copper = c.guid, TA.playerGUID, c.receivedCopper end
    local m = carrier and s.members[carrier]
    if m and s.members[payer] then
      if m.carry then
        m.carry.copper = m.carry.copper + copper
      else
        m.carry = { paidAt = TA.Now(), copper = copper, payerGUID = payer }
      end
    end
  end
  TA:Fire("DATA_CHANGED")
end

TA:On("TRADE_SHOW", function()
  local guid = TA.Clean(UnitGUID("NPC"))
  local name, realm = UnitName("NPC")
  name, realm = TA.Clean(name), TA.Clean(realm)
  if not guid or not guid:find("^Player%-") then current = nil; return end
  current = { guid = guid, name = TA.FullName(name, realm), givenCopper = 0, receivedCopper = 0 }
  if TA.Sessions.TouchPlayer and name then
    local _, classFile = UnitClass("NPC")
    TA.Sessions:TouchPlayer({ guid = guid, name = current.name, class = TA.Clean(classFile), level = TA.Clean(UnitLevel("NPC")) })
  end
end, "trades")

for _, ev in ipairs({ "TRADE_MONEY_CHANGED", "TRADE_PLAYER_ITEM_CHANGED", "TRADE_TARGET_ITEM_CHANGED", "TRADE_ACCEPT_UPDATE" }) do
  TA:On(ev, Snapshot, "trades")
end

TA:On("UI_INFO_MESSAGE", function(_, a, b)
  local msg = type(b) == "string" and b or a
  if TA.IsSecret(msg) then return end
  if msg == ERR_TRADE_COMPLETE then Commit() end
end, "trades")

TA:On("TRADE_CLOSED", function()
  -- TRADE_CLOSED can fire before UI_INFO_MESSAGE; give the completion message a moment.
  local c = current
  C_Timer.After(1, function() if current == c then current = nil end end)
end, "trades")

-------------------------------------------------------------------------------
-- Obligation ledger (GDKP / debts). "<name> owes <creditor> <gold>".
-------------------------------------------------------------------------------
function Trade:AddObligation(debtorGUID, debtorName, creditorGUID, creditorName, gold)
  local copper = math.floor((tonumber(gold) or 0) * 10000)
  if copper <= 0 or not debtorGUID or not creditorGUID then return false, "need a known player and an amount" end
  TA.Log:Append({ signal = "obligation", subjectGUID = debtorGUID, subjectName = debtorName, source = "human",
    api = "/ta owe", details = { creditorGUID = creditorGUID, creditorName = creditorName, copper = copper } })
  TA:Fire("DATA_CHANGED")
  return true
end

-- Bulk ledger import (GDKP pots, cuts, spreadsheets). One "Name amount" per line.
-- direction "owedToMe": Name owes me; "iOwe": I owe Name. Unknown players are skipped.
function Trade.ParseLedger(text)
  local out = {}
  for line in (text or ""):gmatch("[^\r\n]+") do
    local clean = line:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    local name = clean:match("([%a\128-\255][%a\128-\255%-']+)")
    local amount = clean:match("(%d[%d,%.]*)%s*[gG]?")
    if name and amount then
      amount = tonumber((amount:gsub(",", "")))
      if amount and amount > 0 then out[#out + 1] = { name = name, gold = amount } end
    end
  end
  return out
end

function Trade:ImportLedger(text, direction)
  local ok, skipped = 0, {}
  for _, row in ipairs(Trade.ParseLedger(text)) do
    local guid = TA.Sessions:GUIDByName(row.name)
    if guid then
      local pname = TA.db.players[guid].name
      if direction == "iOwe" then
        self:AddObligation(TA.playerGUID, TA.playerName, guid, pname, row.gold)
      else
        self:AddObligation(guid, pname, TA.playerGUID, TA.playerName, row.gold)
      end
      ok = ok + 1
    else
      skipped[#skipped + 1] = row.name
    end
  end
  local msg = string.format("Imported %d debts (deadline %dh).", ok, TA.Params:Get("pay.deadlineHours"))
  if #skipped > 0 then msg = msg .. " Skipped (never grouped with, unknown GUID): " .. table.concat(skipped, ", ") end
  return msg
end
