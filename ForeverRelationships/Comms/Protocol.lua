-- Peer protocol (GDD 3, Phase 2). Prefix "ForeverRel", messages "version|type|payload",
-- chunked under 255 bytes, schema-validated and throttled in both directions.
-- Types: HELLO, QUEST, ATTUNE, ENDORSE, PRESENCE.
local _, FR = ...

local Proto = { VERSION = 1, handlers = {}, peers = {}, schema = {} }
FR.Protocol = Proto

FR:RegisterCapture("comms", "Addon-to-addon messages", "C_ChatInfo.SendAddonMessage, CHAT_MSG_ADDON")

local MAX = 250
local SEP = ";"

-- Schema: field count and per-field validators. Malformed messages are dropped and logged.
local function isGUID(v) return type(v) == "string" and v:find("^Player%-%d+%-%x+$") ~= nil end
local function isInt(v) return tonumber(v) ~= nil and tonumber(v) == math.floor(tonumber(v)) end
local function isName(v) return type(v) == "string" and #v > 0 and #v <= 64 and not v:find("[|;]") end
local function any() return true end
Proto.schema.HELLO    = { isGUID, isInt, any }                 -- guid;version;caps
Proto.schema.QUEST    = { isGUID, isInt }                      -- guid;questID
Proto.schema.ATTUNE   = { isGUID, any }                        -- guid;key,key,...
Proto.schema.ENDORSE  = { isGUID, isGUID, isName, any }        -- endorser;subject;subjectName;sameGuild(0/1)
Proto.schema.PRESENCE = { isGUID, isInt, isInt, any, isInt, any } -- guid;level;mapID;zone;lfg;quests

function Proto.Encode(fields)
  local out = {}
  for i, f in ipairs(fields) do out[i] = tostring(f):gsub("[|;]", "") end
  return table.concat(out, SEP)
end

function Proto.Decode(payload)
  local out = {}
  for f in (payload .. SEP):gmatch("([^;]*);") do out[#out + 1] = f end
  return out
end

function Proto.Validate(mtype, fields)
  local sch = Proto.schema[mtype]
  if not sch then return false, "unknown type" end
  if #fields < #sch then return false, "too few fields" end
  for i, check in ipairs(sch) do
    if not check(fields[i]) then return false, "bad field " .. i end
  end
  return true
end

-- Split a full message into chunks: "1|C|id|i|n|piece"
function Proto.Chunk(msg, id)
  if #msg <= MAX then return { msg } end
  local pieceSize = MAX - 24
  local n = math.ceil(#msg / pieceSize)
  local out = {}
  for i = 1, n do
    out[i] = string.format("%d|C|%s|%d|%d|%s", Proto.VERSION, id, i, n, msg:sub((i - 1) * pieceSize + 1, i * pieceSize))
  end
  return out
end

-------------------------------------------------------------------------------
-- Outgoing queue with a token bucket (stays under Blizzard's comms throttle)
-------------------------------------------------------------------------------
local queue, tokens, msgCounter = {}, 8, 0

local function Flush()
  tokens = math.min(8, tokens + 1)
  while tokens > 0 and #queue > 0 do
    local q = table.remove(queue, 1)
    local ok, res = pcall(C_ChatInfo.SendAddonMessage, FR.PREFIX, q.msg, q.channel, q.target)
    if not ok then
      FR.Debug("send failed", res)
      break
    end
    -- Mainline returns a result enum; anything other than Success means throttled/blocked
    if type(res) == "number" and Enum and Enum.SendAddonMessageResult and res ~= Enum.SendAddonMessageResult.Success then
      table.insert(queue, 1, q)
      break
    end
    tokens = tokens - 1
  end
end

function Proto:Send(mtype, fields, channel, target)
  if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return false end
  if not FR:CaptureOK("comms") then return false end
  msgCounter = msgCounter + 1
  local msg = string.format("%d|%s|%s", Proto.VERSION, mtype, Proto.Encode(fields))
  for _, piece in ipairs(Proto.Chunk(msg, tostring(msgCounter % 1000))) do
    if #queue < 200 then table.insert(queue, { msg = piece, channel = channel, target = target }) end
  end
  return true
end

function Proto:SendGroup(mtype, fields)
  if not IsInGroup() then return false end
  local channel = IsInRaid() and "RAID" or (IsInGroup(LE_PARTY_CATEGORY_INSTANCE) and "INSTANCE_CHAT") or "PARTY"
  return self:Send(mtype, fields, channel)
end

-------------------------------------------------------------------------------
-- Incoming: reassembly, rate limiting, sender verification
-------------------------------------------------------------------------------
local partial, rate = {}, {}

-- GUID of a sender we can verify: they must be in our group (or targetable).
function Proto.VerifiedGUID(sender)
  local short = FR.ShortName(sender)
  for _, unit in ipairs(FR.Sessions.GroupUnits()) do
    local n = FR.Clean(UnitName(unit))
    if n and n == short then return FR.Clean(UnitGUID(unit)) end
  end
  return nil
end

local function Drop(sender, why)
  FR.Debug("dropped message from", sender, why)
  Proto.dropped = (Proto.dropped or 0) + 1
end

function Proto:Dispatch(msg, channel, sender)
  local v, mtype, payload = msg:match("^(%d+)|(%u+)|(.*)$")
  if not v then return Drop(sender, "malformed") end
  if mtype == "C" then
    local id, i, n, piece = payload:match("^([^|]+)|(%d+)|(%d+)|(.*)$")
    i, n = tonumber(i), tonumber(n)
    if not id or not i or not n or n > 20 or i > n then return Drop(sender, "bad chunk") end
    local key = sender .. ":" .. id
    local p = partial[key] or { parts = {}, got = 0, t = FR.Now() }
    partial[key] = p
    if not p.parts[i] then p.parts[i] = piece; p.got = p.got + 1 end
    if p.got == n then
      partial[key] = nil
      return self:Dispatch(table.concat(p.parts), channel, sender)
    end
    return
  end
  local fields = Proto.Decode(payload)
  local ok, err = Proto.Validate(mtype, fields)
  if not ok then return Drop(sender, mtype .. ": " .. err) end
  -- the GUID in the payload must be the sender's real GUID when we can check it
  local real = Proto.VerifiedGUID(sender)
  if real and real ~= fields[1] then return Drop(sender, "sender GUID mismatch") end
  local h = self.handlers[mtype]
  if h then h(fields, sender, channel, real) end
end

FR:On("CHAT_MSG_ADDON", function(_, prefix, msg, channel, sender)
  if prefix ~= FR.PREFIX or FR.IsSecret(msg) or FR.IsSecret(sender) then return end
  if not sender or FR.ShortName(sender) == FR.ShortName(FR.playerName or "") then return end
  local now = GetTime()
  local r = rate[sender]
  if not r or now - r.start > 10 then r = { start = now, n = 0 }; rate[sender] = r end
  r.n = r.n + 1
  if r.n > 30 then return Drop(sender, "rate limit") end
  Proto:Dispatch(msg, channel, sender)
end, "comms")

-------------------------------------------------------------------------------
-- HELLO / QUEST / ATTUNE
-------------------------------------------------------------------------------
Proto.handlers.HELLO = function(f, sender, channel, real)
  Proto.peers[f[1]] = { name = sender, version = tonumber(f[2]), caps = f[3], t = FR.Now() }
  if channel ~= "WHISPER" and not Proto.helloReplied then
    -- a newly joined peer gets our HELLO once per roster change
    Proto.helloReplied = true
    Proto:SendHello()
  end
end

function Proto:SendHello()
  if not FR.playerGUID then return end
  self:SendGroup("HELLO", { FR.playerGUID, self.VERSION, "Q,A,E,P" })
  if FR.Params:Get("consent.shareAttunements") then self:SendAttunements() end
end

Proto.handlers.QUEST = function(f, sender, _, real)
  if not real then return end -- must be a verified group member
  FR.Group:RecordPartnerQuest(real, FR.FullName(sender), tonumber(f[2]), "peer", "ForeverRel QUEST")
end

Proto.handlers.ATTUNE = function(f, sender, _, real)
  if not real then return end
  local p = FR.db.players[real]
  if not p then return end
  local keys = {}
  for k in (f[2] or ""):gmatch("[^,]+") do keys[#keys + 1] = k end
  p.attunements = { keys = keys, t = FR.Now(), selfReported = true }
  FR:Fire("DATA_CHANGED")
end

function Proto:OwnAttunements()
  local keys = {}
  if not (C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted) then return keys end
  for _, a in ipairs(FR.Attunements.list) do
    for _, q in ipairs(a.quests) do
      if FR.SafeCall(C_QuestLog.IsQuestFlaggedCompleted, q) then keys[#keys + 1] = a.key; break end
    end
  end
  return keys
end

function Proto:SendAttunements()
  self:SendGroup("ATTUNE", { FR.playerGUID, table.concat(self:OwnAttunements(), ",") })
end

FR:Listen("LOGIN", function()
  if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    local ok = pcall(C_ChatInfo.RegisterAddonMessagePrefix, FR.PREFIX)
    if not ok then FR:CaptureUnavailable("comms", "RegisterAddonMessagePrefix", "prefix registration failed") end
  else
    FR:CaptureUnavailable("comms", "C_ChatInfo", "addon messaging unavailable")
  end
  C_Timer.NewTicker(0.25, Flush)
  C_Timer.NewTicker(30, function()
    local now = FR.Now()
    for k, p in pairs(partial) do if now - p.t > 30 then partial[k] = nil end end
  end)
end)

FR:Listen("MEMBER_JOINED", function()
  Proto.helloReplied = false
  C_Timer.After(2, function() Proto:SendHello() end)
end)

FR:Listen("OWN_QUEST_TURNED_IN", function(questID)
  if FR.Params:Get("consent.shareQuests") and IsInGroup() then
    Proto:SendGroup("QUEST", { FR.playerGUID, questID })
  end
end)
