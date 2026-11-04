-- Nearby presence (GDD 9, Phase 2). Off by default (presence.enabled).
-- Broadcasts zone, level, LFG flag and (separately opt-in) active quest IDs on
-- a hidden addon channel. Received presence lives in memory only and is never
-- saved. Invisible mode stops all broadcasting without disabling local capture.
local _, TA = ...

local Presence = { nearby = {}, lfg = false }
TA.Presence = Presence

TA:RegisterCapture("presence", "Nearby presence channel", "JoinTemporaryChannel, SendAddonMessage(CHANNEL)")

local CHANNEL = "TrustAdvPresence"
local ticker

local function ChannelIndex()
  local id = GetChannelName(CHANNEL)
  return (id and id > 0) and id or nil
end

function Presence:Active()
  return TA.Params:Get("presence.enabled") and not TA.db.invisible
end

function Presence:Join()
  if ChannelIndex() then return true end
  local ok = pcall(JoinTemporaryChannel, CHANNEL)
  if not ok then TA:CaptureUnavailable("presence", "JoinTemporaryChannel", "cannot join channel"); return false end
  C_Timer.After(1, function()
    -- keep it out of every chat window
    for i = 1, NUM_CHAT_WINDOWS or 10 do
      local f = _G["ChatFrame" .. i]
      if f and ChatFrame_RemoveChannel then pcall(ChatFrame_RemoveChannel, f, CHANNEL) end
    end
  end)
  return true
end

function Presence:Leave()
  if ChannelIndex() then pcall(LeaveChannelByName, CHANNEL) end
end

local function ActiveQuests()
  local ids = {}
  if not TA.Params:Get("presence.shareQuests") or not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries) then return ids end
  local n = TA.SafeCall(C_QuestLog.GetNumQuestLogEntries) or 0
  for i = 1, n do
    local info = TA.SafeCall(C_QuestLog.GetInfo, i)
    if info and not info.isHeader and info.questID and #ids < 12 then ids[#ids + 1] = info.questID end
  end
  return ids
end

function Presence:Broadcast()
  if not self:Active() then return end
  local idx = ChannelIndex()
  if not idx then self:Join(); return end
  local mapID = C_Map and TA.SafeCall(C_Map.GetBestMapForUnit, "player") or 0
  local zone = (GetRealZoneText and GetRealZoneText() or ""):sub(1, 30)
  local lfg = self.lfg or (C_LFGList and C_LFGList.HasActiveEntryInfo and TA.SafeCall(C_LFGList.HasActiveEntryInfo)) or false
  TA.Protocol:Send("PRESENCE", { TA.playerGUID, UnitLevel("player"), mapID or 0, zone, lfg and 1 or 0,
    table.concat(ActiveQuests(), ",") }, "CHANNEL", idx)
end

function Presence:Apply()
  if ticker then ticker:Cancel(); ticker = nil end
  if self:Active() then
    self:Join()
    ticker = C_Timer.NewTicker(TA.Params:Get("presence.intervalSeconds"), function() Presence:Broadcast() end)
    C_Timer.After(3, function() Presence:Broadcast() end)
  else
    self:Leave()
  end
end

function Presence:SetInvisible(on)
  TA.db.invisible = on and true or false
  self:Apply()
  TA:Fire("DATA_CHANGED")
end

-- Nearby matches for the UI: same map, level within range, overlapping quests.
function Presence:Matches()
  local out = {}
  local now = TA.Now()
  local myMap = C_Map and TA.SafeCall(C_Map.GetBestMapForUnit, "player")
  local myLevel = UnitLevel("player")
  local myQuests = {}
  for _, q in ipairs(ActiveQuests()) do myQuests[q] = true end
  local range = TA.Params:Get("presence.levelRange")
  local ttl = TA.Params:Get("presence.intervalSeconds") * 3
  for guid, p in pairs(self.nearby) do
    if now - p.t > ttl then
      self.nearby[guid] = nil
    else
      local overlap = 0
      for _, q in ipairs(p.quests) do if myQuests[q] then overlap = overlap + 1 end end
      p.sameZone = myMap and p.mapID == myMap
      p.levelOK = math.abs((p.level or 0) - (myLevel or 0)) <= range
      p.overlap = overlap
      out[#out + 1] = p
    end
  end
  table.sort(out, function(a, b)
    local sa = (a.sameZone and 4 or 0) + (a.levelOK and 2 or 0) + a.overlap
    local sb = (b.sameZone and 4 or 0) + (b.levelOK and 2 or 0) + b.overlap
    return sa > sb
  end)
  return out
end

TA.Protocol.handlers.PRESENCE = function(f, sender, channel)
  if channel ~= "CHANNEL" or not Presence:Active() then return end
  local guid = f[1]
  -- a presence claim must be consistent with what we already know about this GUID
  local known = TA.db.players[guid]
  if known and TA.ShortName(known.name):lower() ~= TA.ShortName(sender):lower() then return end
  local quests = {}
  for q in (f[6] or ""):gmatch("%d+") do quests[#quests + 1] = tonumber(q) end
  local first = Presence.nearby[guid] == nil
  Presence.nearby[guid] = { guid = guid, name = TA.FullName(sender), level = tonumber(f[2]), mapID = tonumber(f[3]),
    zone = f[4], lfg = f[5] == "1", quests = quests, t = TA.Now() }
  if first then TA:Fire("PRESENCE_SEEN", guid, Presence.nearby[guid]) end
end

TA:Listen("LOGIN", function() C_Timer.After(5, function() Presence:Apply() end) end)
TA:Listen("PARAMS_CHANGED", function(key)
  if key == "presence.enabled" or key == "presence.intervalSeconds" then Presence:Apply() end
end)
