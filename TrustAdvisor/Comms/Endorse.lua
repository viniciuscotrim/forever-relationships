-- Endorsements (5.16, 6.7). Local endorsements work in Phase 1; sharing them
-- with peers (Phase 2) requires consent.shareEndorsements.
-- A peer endorsement about a third party only counts if your own client
-- witnessed the endorser and the subject grouped together recently.
local _, TA = ...

local Endorse = {}
TA.Endorse = Endorse

local DAY = 86400

-- Recently ended sessions (memory only): sessionId -> { members = {guid=true}, endedAt }
Endorse.recent = {}

TA:Listen("SESSION_END", function(s, endedAt)
  local set = {}
  for guid in pairs(s.members) do set[guid] = true end
  table.insert(Endorse.recent, 1, { id = s.id, members = set, endedAt = endedAt, names = s.members })
  while #Endorse.recent > 5 do table.remove(Endorse.recent) end
end)

local function SameGuild(guid)
  local mine = TA.SafeCall(GetGuildInfo, "player")
  local p = TA.db.players[guid]
  local theirs = p and p.guilds and p.guilds[#p.guilds] and p.guilds[#p.guilds].name
  return mine ~= nil and mine ~= "" and theirs == mine
end

function Endorse:CanEndorse(guid)
  local last = TA.cdb.endorseGiven[guid]
  local cd = TA.Params:Get("endorse.cooldownDays") * DAY
  if last and TA.Now() - last < cd then return false, "already endorsed within " .. TA.Params:Get("endorse.cooldownDays") .. " days" end
  if guid == TA.playerGUID then return false, "cannot endorse yourself" end
  return true
end

function Endorse:Give(guid, name, sessionId)
  local ok, why = self:CanEndorse(guid)
  if not ok then return false, why end
  local same = SameGuild(guid)
  TA.cdb.endorseGiven[guid] = TA.Now()
  TA.Log:Append({ signal = "endorse", subjectGUID = guid, subjectName = name, sessionId = sessionId,
    source = "human", api = "Play again? prompt",
    details = { endorserGUID = TA.playerGUID, endorserName = TA.playerName, sameGuild = same } })
  local a = TA.cdb.affinity[guid] or { sessions = {} }
  TA.cdb.affinity[guid] = a
  a.privateYes, a.privateNo = TA.Now(), nil
  if TA.Params:Get("consent.shareEndorsements") and not TA.db.invisible then
    local fields = { TA.playerGUID, guid, TA.ShortName(name), same and 1 or 0 }
    TA.Protocol:Send("ENDORSE", fields, "WHISPER", name)
    if IsInGroup() then TA.Protocol:SendGroup("ENDORSE", fields) end
  end
  TA:Fire("DATA_CHANGED")
  return true
end

-- Private "no": affinity only, never transmitted, never touches trust.
function Endorse:PrivateNo(guid, name)
  local a = TA.cdb.affinity[guid] or { sessions = {} }
  TA.cdb.affinity[guid] = a
  a.name = a.name or name
  a.privateNo, a.privateYes = TA.Now(), nil
  TA:Fire("DATA_CHANGED")
end

local function WitnessedTogether(a, b)
  local s = TA.Sessions:Active()
  if s and s.members[a] and s.members[b] then return s.id end
  for _, r in ipairs(Endorse.recent) do
    if r.members[a] and r.members[b] and TA.Now() - r.endedAt < 2 * 3600 then return r.id end
  end
  return nil
end

TA.Protocol.handlers.ENDORSE = function(f, sender, channel, real)
  local endorser, subject, subjectName, same = f[1], f[2], f[3], f[4] == "1"
  if endorser == subject then return end
  if not real then
    -- not verifiable via a group unit: the sender name must match what we witnessed for that GUID
    local p = TA.db.players[endorser]
    if not p or TA.ShortName(p.name):lower() ~= TA.ShortName(sender):lower() then
      TA.Debug("endorsement sender/GUID mismatch, ignored", sender)
      return
    end
  end
  local key = endorser .. ">" .. subject
  local seen = TA.db.peerEndorseSeen[key]
  if seen and TA.Now() - seen < TA.Params:Get("endorse.cooldownDays") * DAY then return end
  local sessionId
  if subject == TA.playerGUID then
    -- endorsement about me: accept if I witnessed grouping with the sender
    sessionId = WitnessedTogether(endorser, TA.playerGUID)
  else
    sessionId = WitnessedTogether(endorser, subject)
  end
  if not sessionId then TA.Debug("peer endorsement not witnessed, ignored", sender); return end
  TA.db.peerEndorseSeen[key] = TA.Now()
  TA.Log:Append({ signal = "endorse", subjectGUID = subject,
    subjectName = subject == TA.playerGUID and TA.playerName or TA.FullName(subjectName),
    sessionId = sessionId, source = "peer", api = "TrustAdv ENDORSE",
    details = { endorserGUID = endorser, endorserName = TA.FullName(sender), sameGuild = same } })
  if subject == TA.playerGUID then
    TA.Print(string.format("%s would play with you again.", TA.ShortName(sender)))
  end
  TA:Fire("DATA_CHANGED")
end
