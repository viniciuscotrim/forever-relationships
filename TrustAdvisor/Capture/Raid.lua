-- Showing up (5.1): a light signup module. A raid plan has a start time and a
-- list of signed names. When the plan closes, one attendance event per
-- signup records raw facts (start, join time, withdrawal); the on-time/late/
-- no-show outcome is derived at scoring time from the parameters.
local _, TA = ...

local Raid = {}
TA.Raid = Raid

TA:RegisterCapture("attendance", "Raid signups vs attendance", "Trust Advisor signups + GROUP_ROSTER_UPDATE")

function Raid:Plan() return TA.db.signups.current end

function Raid:NewPlan(startInMinutes)
  local start = TA.Now() + math.floor((tonumber(startInMinutes) or 0) * 60)
  TA.db.signups.current = { id = "R" .. TA.Now(), startAt = start, names = {}, joined = {} }
  TA:Fire("DATA_CHANGED")
  return TA.db.signups.current
end

function Raid:Add(names)
  local plan = self:Plan() or self:NewPlan(0)
  local n = 0
  for name in (names or ""):gmatch("[^,%s]+") do
    local key = TA.ShortName(name):lower()
    if not plan.names[key] then
      plan.names[key] = { name = name, signedAt = TA.Now() }
      n = n + 1
    end
  end
  TA:Fire("DATA_CHANGED")
  return n
end

function Raid:Withdraw(name)
  local plan = self:Plan()
  local e = plan and plan.names[TA.ShortName(name or ""):lower()]
  if not e then return false end
  e.withdrawnAt = TA.Now()
  return true
end

-- Track first join time of signed names once the raid has started.
local function Track()
  local plan = Raid:Plan()
  local s = TA.Sessions:Active()
  if not plan or not s or s.groupType ~= "raid" then return end
  local now = TA.Now()
  for guid, m in pairs(s.members) do
    local key = TA.ShortName(m.name):lower()
    if plan.names[key] and not plan.joined[key] then
      local first = m.intervals[1] and m.intervals[1].join or now
      plan.joined[key] = { guid = guid, name = m.name, at = math.max(first, plan.startAt) }
    end
  end
end

function Raid:Close()
  local plan = self:Plan()
  if not plan then return 0 end
  Track()
  local n = 0
  for key, e in pairs(plan.names) do
    local j = plan.joined[key]
    local guid = (j and j.guid) or TA.Sessions:GUIDByName(e.name)
    if guid then
      TA.Log:Append({ signal = "attendance", subjectGUID = guid, subjectName = (j and j.name) or e.name,
        source = "game", api = "signup + GROUP_ROSTER_UPDATE",
        details = { planId = plan.id, startAt = plan.startAt, signedAt = e.signedAt,
          withdrawnAt = e.withdrawnAt, joinedAt = j and j.at or nil } })
      n = n + 1
    else
      TA.Debug("attendance: cannot identify", e.name, "(never seen) - not recorded")
    end
  end
  TA.db.signups.current = nil
  TA:Fire("DATA_CHANGED")
  return n
end

TA:Listen("ROSTER_SCANNED", function()
  local plan = Raid:Plan()
  if plan and TA.Now() >= plan.startAt then Track() end
end)

TA:Listen("SESSION_END", function(s)
  local plan = Raid:Plan()
  if plan and s.groupType == "raid" and TA.Now() >= plan.startAt then Raid:Close() end
end)
