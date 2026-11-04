-- Session model and roster tracking (GDD 5 "Common session model").
-- A session starts when the player joins a party or raid and ends when the
-- group disbands or the player leaves. Raw facts only: every rule that turns
-- these facts into scores lives in Scoring/Dimensions.lua.
local _, TA = ...

local Sessions = {}
TA.Sessions = Sessions

TA:RegisterCapture("roster", "Group roster and sessions", "GROUP_ROSTER_UPDATE, UnitGUID, UnitLevel")
TA:RegisterCapture("encounters", "Boss kills and wipes", "ENCOUNTER_END, BOSS_KILL")
TA:RegisterCapture("leaves", "Voluntary-leave detection", "CHAT_MSG_SYSTEM (ERR_LEFT_GROUP_S)")
TA:RegisterCapture("connection", "Disconnects", "UNIT_CONNECTION")
TA:RegisterCapture("chatCount", "Party chat message counts (text discarded)", "CHAT_MSG_PARTY")

local RANK = { quest = 1, dungeon = 2, raid = 3 }

-------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------
function TA.PatternFromFormat(fmt)
  if type(fmt) ~= "string" then return nil end
  local p = fmt:gsub("%%%d?%$?s", "\001"):gsub("%%%d?%$?d", "\002")
  p = p:gsub("[%(%)%.%%%+%-%*%?%[%]%^%$]", "%%%0")
  p = p:gsub("\001", "(.+)"):gsub("\002", "(%%d+)")
  return "^" .. p .. "$"
end

local function GroupUnits()
  local units = { "player" }
  if IsInRaid() then
    for i = 1, GetNumGroupMembers() do units[#units + 1] = "raid" .. i end
  else
    for i = 1, GetNumSubgroupMembers() do units[#units + 1] = "party" .. i end
  end
  return units
end
Sessions.GroupUnits = GroupUnits

local function ReadUnit(unit)
  local guid = TA.Clean(UnitGUID(unit))
  if not guid or not guid:find("^Player%-") then return nil end
  local name, realm = UnitName(unit)
  name, realm = TA.Clean(name), TA.Clean(realm)
  if not name or name == UNKNOWNOBJECT then return nil end
  local _, classFile = UnitClass(unit)
  local guild = TA.SafeCall(GetGuildInfo, unit)
  return {
    guid = guid, name = TA.FullName(name, realm), class = TA.Clean(classFile),
    level = TA.Clean(UnitLevel(unit)), guild = guild,
    connected = TA.Clean(UnitIsConnected(unit)),
  }
end
Sessions.ReadUnit = ReadUnit

local function CurrentGroupType()
  if IsInRaid() then return "raid" end
  local _, instanceType = GetInstanceInfo()
  if instanceType == "party" then return "dungeon" end
  if instanceType == "raid" then return "raid" end
  return "quest"
end

local function IsHardcore()
  if C_GameRules and C_GameRules.IsHardcoreActive then
    local ok, v = pcall(C_GameRules.IsHardcoreActive)
    return ok and v and true or false
  end
  return false
end

local function LearningListing()
  if not (C_LFGList and C_LFGList.GetActiveEntryInfo and Enum and Enum.LFGEntryPlaystyle) then return false end
  local ok, info = pcall(C_LFGList.GetActiveEntryInfo)
  local learning = Enum.LFGEntryPlaystyle.Learning
  return ok and info and learning and info.playstyle == learning or false
end

-------------------------------------------------------------------------------
-- Player identity cache (TrustAdvisorDB.players)
-------------------------------------------------------------------------------
function Sessions:TouchPlayer(u)
  local p = TA.db.players[u.guid]
  if not p then
    p = { name = u.name, class = u.class, level = u.level, firstSeen = TA.Now(), guilds = {} }
    TA.db.players[u.guid] = p
  end
  p.name = u.name or p.name
  p.class = u.class or p.class
  p.level = u.level or p.level
  p.lastSeen = TA.Now()
  local g = u.guild or ""
  local last = p.guilds[#p.guilds]
  if not last or last.name ~= g then
    table.insert(p.guilds, { name = g, t = TA.Now() })
    while #p.guilds > 20 do table.remove(p.guilds, 1) end
  end
  return p
end

function Sessions:GUIDByName(name)
  if not name then return nil end
  local full = TA.FullName(name):lower()
  local short = TA.ShortName(name):lower()
  local best
  for guid, p in pairs(TA.db.players) do
    local pn = (p.name or ""):lower()
    if pn == full then return guid end
    if TA.ShortName(pn) == short then best = best or guid end
  end
  return best
end

-------------------------------------------------------------------------------
-- Active session lifecycle
-------------------------------------------------------------------------------
function Sessions:Active() return TA.db and TA.db.active end

function Sessions:InInstanceSession()
  local s = self:Active()
  return s and (s.groupType == "dungeon" or s.groupType == "raid")
end

function Sessions:Start()
  local now = TA.Now()
  local instName, instanceType = GetInstanceInfo()
  local s = {
    id = string.format("%s-%d", (TA.playerGUID or "P"):sub(-8), now),
    startedAt = now, lastUpdate = now,
    zone = GetRealZoneText and GetRealZoneText() or "?",
    instanceName = (instanceType == "party" or instanceType == "raid") and instName or nil,
    groupType = CurrentGroupType(),
    hardcore = IsHardcore(),
    learning = LearningListing(),
    members = {}, kills = {}, wipeStreak = 0, wipes = 0,
  }
  TA.db.active = s
  TA.Debug("session start", s.id, s.groupType, s.zone)
  TA:Fire("SESSION_START", s)
  return s
end

function Sessions:Member(guid)
  local s = self:Active()
  return s and s.members[guid]
end

local function OpenInterval(m)
  local iv = m.intervals[#m.intervals]
  return iv and iv.leave == nil and iv or nil
end

function Sessions:Scan()
  if not TA.db then return end
  if not IsInGroup() then
    if self:Active() then self:End("left group") end
    return
  end
  local s = self:Active() or self:Start()
  local now = TA.Now()
  s.lastUpdate = now
  local gt = CurrentGroupType()
  if RANK[gt] > RANK[s.groupType] then s.groupType = gt end
  local instName, instanceType = GetInstanceInfo()
  if (instanceType == "party" or instanceType == "raid") and instName then s.instanceName = instName end

  local present = {}
  for _, unit in ipairs(GroupUnits()) do
    local u = ReadUnit(unit)
    if u then
      present[u.guid] = true
      self:TouchPlayer(u)
      local m = s.members[u.guid]
      if not m then
        m = { name = u.name, class = u.class, level = u.level, guild = u.guild, intervals = {},
              lootTimes = {}, chat = 0, srRolls = 0, isSelf = (u.guid == TA.playerGUID) }
        s.members[u.guid] = m
        TA:Fire("MEMBER_JOINED", u.guid, m)
      end
      m.level = m.level or u.level
      if not OpenInterval(m) then
        table.insert(m.intervals, { join = now })
        TA.Debug("member join", u.name)
      end
      if u.connected == false then m.offlineSince = m.offlineSince or now
      elseif u.connected then m.offlineSince = nil end
    end
  end

  for guid, m in pairs(s.members) do
    local iv = OpenInterval(m)
    if iv and not present[guid] then
      iv.leave = now
      iv.reason = self:ConsumeLeaveReason(m.name)
      iv.offline = m.offlineSince ~= nil
      iv.wipeStreak = s.wipeStreak
      TA.Debug("member left", m.name, iv.reason)
      TA:Fire("MEMBER_LEFT", guid, m, iv)
    end
  end
  TA:Fire("ROSTER_SCANNED", s)
end

-- Leave reasons are learned from system messages and our own kicks, then
-- consumed by the next roster diff.
Sessions.pendingLeave = {}
function Sessions:NoteLeave(name, reason)
  if not name then return end
  self.pendingLeave[TA.ShortName(name):lower()] = { reason = reason, t = TA.Now() }
end

function Sessions:ConsumeLeaveReason(fullName)
  local key = TA.ShortName(fullName):lower()
  local p = self.pendingLeave[key]
  self.pendingLeave[key] = nil
  if p and TA.Now() - p.t <= 10 then return p.reason end
  return "unknown"
end

function Sessions:End(why)
  local s = self:Active()
  if not s then return end
  local endedAt = (why == "recovered") and s.lastUpdate or TA.Now()
  -- members still present are present at the end ("disband" is not a leave)
  local session = {
    signal = "session", sessionId = s.id, source = "game", api = "GROUP_ROSTER_UPDATE",
    t = endedAt,
    details = {
      startedAt = s.startedAt, endedAt = endedAt, groupType = s.groupType, zone = s.zone,
      instanceName = s.instanceName, kills = s.kills, wipes = s.wipes, hardcore = s.hardcore,
      learning = s.learning, memberCount = 0, endReason = why,
    },
  }
  local count = 0
  for _ in pairs(s.members) do count = count + 1 end
  session.details.memberCount = count
  TA.Log:Append(session)

  for guid, m in pairs(s.members) do
    TA.Log:Append({
      signal = "member", sessionId = s.id, subjectGUID = guid, subjectName = m.name,
      source = "game", api = "GROUP_ROSTER_UPDATE", t = endedAt,
      details = {
        class = m.class, level = m.level, guild = m.guild, intervals = m.intervals,
        lootTimes = m.lootTimes, srRolls = m.srRolls, carry = m.carry, isSelf = m.isSelf,
      },
    })
  end
  TA.db.active = nil
  TA.Debug("session end", s.id, why, TA.FormatDuration(endedAt - s.startedAt), count, "members")
  TA:Fire("SESSION_END", s, endedAt)
  TA:Fire("DATA_CHANGED")
end

-------------------------------------------------------------------------------
-- Encounters (boss kills and wipes)
-------------------------------------------------------------------------------
function Sessions:BossKill(api)
  local s = self:Active()
  if not s then return end
  local now = TA.Now()
  local last = s.kills[#s.kills]
  if last and now - last < 5 then return end -- ENCOUNTER_END and BOSS_KILL both fire
  table.insert(s.kills, now)
  s.wipeStreak = 0
  s.lastUpdate = now
  TA.Debug("boss kill via", api)
  TA:Fire("BOSS_KILL", s)
end

-------------------------------------------------------------------------------
-- Events
-------------------------------------------------------------------------------
local scanPending = false
local function QueueScan()
  if scanPending then return end
  scanPending = true
  C_Timer.After(0.3, function() scanPending = false; Sessions:Scan() end)
end
Sessions.QueueScan = QueueScan

TA:Listen("LOGIN", function()
  local s = Sessions:Active()
  if s then
    if IsInGroup() and TA.Now() - (s.lastUpdate or 0) < 30 * 60 then
      TA.Debug("resuming session", s.id)
    else
      Sessions:End("recovered")
    end
  end
  QueueScan()
  -- light heartbeat so a crash loses at most a minute of session time
  C_Timer.NewTicker(60, function()
    local a = Sessions:Active()
    if a then a.lastUpdate = TA.Now() end
  end)
end)

TA:On("GROUP_ROSTER_UPDATE", QueueScan, "roster")
TA:On("GROUP_JOINED", QueueScan, "roster")
TA:On("GROUP_LEFT", function() Sessions:Scan() end, "roster")
TA:On("PLAYER_ENTERING_WORLD", QueueScan, "roster")
TA:On("ZONE_CHANGED_NEW_AREA", QueueScan, "roster")

TA:On("ENCOUNTER_END", function(_, encounterID, encounterName, difficultyID, groupSize, success)
  local s = Sessions:Active()
  if not s or TA.IsSecret(success) then return end
  if success == 1 or success == true then
    Sessions:BossKill("ENCOUNTER_END")
  else
    s.wipeStreak = s.wipeStreak + 1
    s.wipes = s.wipes + 1
    TA.Debug("wipe", s.wipeStreak)
  end
end, "encounters")
TA:On("BOSS_KILL", function() Sessions:BossKill("BOSS_KILL") end, "encounters")

TA:On("UNIT_CONNECTION", function(_, unit, isConnected)
  local s = Sessions:Active()
  if not s or TA.IsSecret(isConnected) then return end
  local guid = TA.Clean(UnitGUID(unit))
  local m = guid and s.members[guid]
  if not m then return end
  if isConnected then m.offlineSince = nil else m.offlineSince = TA.Now() end
end, "connection")

-- System messages tell us whether a leave was voluntary.
local leavePatterns
local function BuildLeavePatterns()
  leavePatterns = {}
  for _, g in ipairs({ "ERR_LEFT_GROUP_S", "ERR_RAID_MEMBER_REMOVED_S" }) do
    local p = TA.PatternFromFormat(_G[g])
    if p then leavePatterns[#leavePatterns + 1] = { p = p, reason = "voluntary" } end
  end
  for _, g in ipairs({ "ERR_PARTY_LFG_BOOT_VOTE_SUCCEEDED" }) do
    local p = TA.PatternFromFormat(_G[g])
    if p then leavePatterns[#leavePatterns + 1] = { p = p, reason = "removed" } end
  end
  if #leavePatterns == 0 then TA:CaptureUnavailable("leaves", "ERR_LEFT_GROUP_S", "leave message strings not found") end
end

TA:On("CHAT_MSG_SYSTEM", function(_, msg)
  if not leavePatterns then BuildLeavePatterns() end
  if TA.IsSecret(msg) or type(msg) ~= "string" then return end
  for _, lp in ipairs(leavePatterns) do
    local name = msg:match(lp.p)
    if name then Sessions:NoteLeave(name, lp.reason); return end
  end
end, "leaves")

-- Our own kicks are "removed", never "voluntary".
if hooksecurefunc then
  if UninviteUnit then
    hooksecurefunc("UninviteUnit", function(name) Sessions:NoteLeave(type(name) == "string" and name or nil, "removed") end)
  end
  if C_PartyInfo and C_PartyInfo.UninviteUnit then
    hooksecurefunc(C_PartyInfo, "UninviteUnit", function(name) Sessions:NoteLeave(type(name) == "string" and name or nil, "removed") end)
  end
end

-- Party chat: count messages per sender, discard the text immediately.
-- The only text ever inspected is a Questie announcement prefix (Capture/Questie.lua).
local function OnGroupChat(event, text, sender, _, _, _, _, _, _, _, _, _, guid)
  local s = Sessions:Active()
  if not s then return end
  guid = TA.Clean(guid)
  if not guid then return end
  local m = s.members[guid]
  if m then m.chat = (m.chat or 0) + 1 end
  if TA.Questie and not TA.IsSecret(text) and guid ~= TA.playerGUID then
    TA.Questie:Inspect(text, guid, m and m.name or TA.Clean(sender))
  end
  text = nil -- never stored
end
for _, ev in ipairs({ "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER",
  "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER" }) do
  TA:On(ev, OnGroupChat, "chatCount")
end

-------------------------------------------------------------------------------
-- Affinity (private, per character). Never touches trust scoring.
-------------------------------------------------------------------------------
TA:Listen("SESSION_END", function(s, endedAt)
  local cdb = TA.cdb
  local minSec = TA.Params:Get("session.minMinutes") * 60
  if endedAt - s.startedAt < minSec then return end
  for guid, m in pairs(s.members) do
    if guid ~= TA.playerGUID then
      local a = cdb.affinity[guid]
      if not a then a = { sessions = {} }; cdb.affinity[guid] = a end
      a.name = m.name
      local first = m.intervals[1] and m.intervals[1].join or s.startedAt
      local lastIv = m.intervals[#m.intervals]
      local leave = lastIv and lastIv.leave or endedAt
      table.insert(a.sessions, {
        s = first, e = leave, zone = s.instanceName or s.zone, chat = m.chat or 0,
        groupType = s.groupType, hour = tonumber(date("%H", first)), wday = tonumber(date("%w", first)),
      })
      while #a.sessions > 200 do table.remove(a.sessions, 1) end
    end
  end
end)
