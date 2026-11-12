-- Party welcome. When a party forms, and whenever someone joins it later, one line
-- in party chat says the group uses Forever Relationships, so everyone knows.
-- Setting: announce.party (on by default). Off in raids and in invisible mode.
-- If several members run the addon only one posts: whoever posts first tells the
-- others with an addon message (WELCOME) and they drop their pending line.
local _, FR = ...

local Announce = {}
FR.Announce = Announce

Announce.TEXT = "Welcome to party! Forever Relationships addon being used to eternize our time together!"
-- in your language when it has a translation (party members usually share your client's language)

local REPEAT = 30 * 60   -- the same player is not welcomed again within this many seconds
local MIN_GAP = 20       -- seconds between two of our lines; joiners in between are batched
local CLAIM = 15         -- a WELCOME from another member this recent covers our pending line

local pending, welcomed = {}, {}
local scheduled, lastSent, claimedAt = false, -math.huge, -math.huge

local function Clock() return GetTime and GetTime() or 0 end

function Announce:Enabled()
  return FR.Params:Get("announce.party") and not (FR.db and FR.db.invisible)
end

-- A home party (not a raid, not a queued instance group).
function Announce:InParty()
  if not IsInGroup or IsInRaid() then return false end
  if LE_PARTY_CATEGORY_HOME then return IsInGroup(LE_PARTY_CATEGORY_HOME) and true or false end
  return IsInGroup() and true or false
end

local function InGroupNow(guid)
  for _, unit in ipairs(FR.Sessions.GroupUnits()) do
    if FR.Clean(UnitGUID(unit)) == guid then return true end
  end
  return false
end

local function Flush()
  scheduled = false
  local now = Clock()
  local any = false
  for guid in pairs(pending) do
    if InGroupNow(guid) then any = true end
    welcomed[guid] = FR.Now()
  end
  wipe(pending)
  if not any or not Announce:Enabled() or not Announce:InParty() then return end
  if now - claimedAt < CLAIM then return end   -- another member already welcomed them
  pcall(SendChatMessage, FR.L[Announce.TEXT], "PARTY")
  lastSent = now
  if FR.Protocol and FR.playerGUID then FR.Protocol:SendGroup("WELCOME", { FR.playerGUID }) end
end

local function Schedule()
  if scheduled or not C_Timer then return end
  scheduled = true
  -- the leader goes first; the others wait a little longer, in a random order
  local leader = UnitIsGroupLeader and FR.SafeCall(UnitIsGroupLeader, "player")
  local delay = leader and 2 or (4 + math.random() * 3)
  local wait = MIN_GAP - (Clock() - lastSent)
  if wait > delay then delay = wait end
  C_Timer.After(delay, Flush)
end

function Announce:Joined(guid)
  if not guid or guid == FR.playerGUID or not self:Enabled() or not self:InParty() then return end
  local last = welcomed[guid]
  if last and FR.Now() - last < REPEAT then return end
  pending[guid] = true
  Schedule()
end

FR:Listen("MEMBER_JOINED", function(guid) Announce:Joined(guid) end)

-- Ding! One line in party and/or guild chat when you level up (announce.dingParty / dingGuild).
function Announce:DingChannels()
  if FR.db and FR.db.invisible then return {} end
  local out = {}
  if FR.Params:Get("announce.dingParty") and IsInGroup then
    if LE_PARTY_CATEGORY_HOME and IsInGroup(LE_PARTY_CATEGORY_HOME) then out[#out + 1] = "PARTY"
    elseif LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then out[#out + 1] = "INSTANCE_CHAT"
    elseif not LE_PARTY_CATEGORY_HOME and IsInGroup() then out[#out + 1] = "PARTY" end
  end
  if FR.Params:Get("announce.dingGuild") and IsInGuild and IsInGuild() then out[#out + 1] = "GUILD" end
  return out
end

function Announce:Ding(level)
  level = tonumber(FR.Clean(level))
  if not level or level < 2 then return end
  local text = FR.L["Ding! I've reached level %d!"]:format(level)
  for _, channel in ipairs(self:DingChannels()) do pcall(SendChatMessage, text, channel) end
end

FR:On("PLAYER_LEVEL_UP", function(_, level) Announce:Ding(level) end)

if FR.Protocol then
  FR.Protocol.schema.WELCOME = { function(v) return type(v) == "string" and v:find("^Player%-%d+%-%x+$") ~= nil end }
  FR.Protocol.handlers.WELCOME = function(_, _, _, real)
    if not real then return end   -- must be a verified group member
    claimedAt = Clock()
    for guid in pairs(pending) do welcomed[guid] = FR.Now() end
    wipe(pending)
  end
end

return Announce
