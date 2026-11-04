-- Dimension definitions (GDD 5, 6.6): map raw events to scored contributions.
-- Pure Lua, no WoW API. Every rule reads its thresholds from the parameter
-- snapshot P at scoring time, so a parameter change retroactively rescores
-- everything and the explainer always matches the math.
local _, TA = ...
TA = TA or {}

local Engine = TA.Engine
local Dims = {}
TA.Dimensions = Dims

local MIN, HOUR, DAY = 60, 3600, 86400

Dims.list = TA.DimensionDefaults
Dims.byKey = {}
for _, d in ipairs(Dims.list) do Dims.byKey[d.key] = d end

-------------------------------------------------------------------------------
-- Helpers over session/member facts
-------------------------------------------------------------------------------
local function SessionOf(ev)
  if not ev.sessionId then return nil end
  for _, e in ipairs(TA.Log:ForSession(ev.sessionId)) do
    if e.signal == "session" then return e end
  end
end
Dims.SessionOf = SessionOf

-- Sessions shorter than session.minMinutes are noise (layer hops, quick invites).
local function SessionCounts(s, P)
  if not s then return false end
  local d = s.details
  return ((d.endedAt or s.t) - (d.startedAt or s.t)) >= P["session.minMinutes"] * MIN
end
Dims.SessionCounts = SessionCounts

-- Member events of a subject whose session counts.
local function MemberEvents(guid, P)
  local out = {}
  for _, ev in ipairs(TA.Log:ForSubject(guid)) do
    if ev.signal == "member" and SessionCounts(SessionOf(ev), P) then out[#out + 1] = ev end
  end
  return out
end
Dims.MemberEvents = MemberEvents

local function MembersOf(sessionId)
  local out = {}
  for _, e in ipairs(TA.Log:ForSession(sessionId)) do
    if e.signal == "member" then out[#out + 1] = e end
  end
  return out
end

local function MemberEventFor(sessionId, guid)
  for _, e in ipairs(TA.Log:ForSession(sessionId)) do
    if e.signal == "member" and e.subjectGUID == guid then return e end
  end
end

-- Merge membership intervals whose gap is within the disconnect grace.
-- Returns merged list; the final interval's leave == nil means present at end.
function Dims.MergeIntervals(intervals, graceSec)
  local out = {}
  for _, iv in ipairs(intervals or {}) do
    local last = out[#out]
    if last and last.leave and iv.join and (iv.join - last.leave) <= graceSec then
      last.leave, last.reason, last.offline, last.wipeStreak = iv.leave, iv.reason, iv.offline, iv.wipeStreak
      last.rejoined = true
    else
      out[#out + 1] = { join = iv.join, leave = iv.leave, reason = iv.reason, offline = iv.offline, wipeStreak = iv.wipeStreak }
    end
  end
  return out
end

local FinalInterval
-- A moment every witness of a session agrees on: the last boss kill if any,
-- otherwise the subject's first join. Used to match reports across witnesses.
function Dims.AnchorTime(member, P)
  local s = SessionOf(member)
  local kills = s and s.details.kills
  if kills and #kills > 0 then return kills[#kills] end
  local _, merged = FinalInterval(member, P)
  return merged[1] and merged[1].join or member.t
end

FinalInterval = function(member, P)
  local merged = Dims.MergeIntervals(member.details.intervals, P["finish.dcGraceMinutes"] * MIN)
  return merged[#merged], merged
end

local function PresentAt(merged, t)
  for _, iv in ipairs(merged) do
    if iv.join <= t and (iv.leave == nil or iv.leave >= t) then return true end
  end
  return false
end

local function TimeIn(merged, endedAt)
  local s = 0
  for _, iv in ipairs(merged) do s = s + ((iv.leave or endedAt or iv.join) - iv.join) end
  return s
end

-- Decide whether an early leave is scored. Returns scored(bool), reason(string)
local function EarlyLeaveVerdict(iv, P)
  if iv.reason == "removed" then return false, "removed by the leader (excused)" end
  if iv.reason == "disband" then return false, "group disbanded (excused)" end
  if iv.offline then return false, "disconnected and did not return within grace (excused)" end
  if (iv.wipeStreak or 0) >= P["finish.wipeCountExcuse"] then
    return false, string.format("left after %d consecutive wipes (excused)", iv.wipeStreak)
  end
  if P["finish.requireLeaveMessage"] and iv.reason ~= "voluntary" then
    return false, "leave reason not confirmed by the game (not scored)"
  end
  return true, "left before the final boss"
end

-------------------------------------------------------------------------------
-- Collectors: each returns a list of contributions
-- { t, x, mult, label, eventId, negative?, subtract? }
-- Ratio dims use x in [0,1]. Accumulating dims use x = 1.
-------------------------------------------------------------------------------
local C = {}
Dims.collectors = C

-- 5.1 Showing up
C.attend = function(guid, P)
  local out = {}
  for _, ev in ipairs(TA.Log:ForSubject(guid)) do
    if ev.signal == "attendance" then
      local d = ev.details
      if d.withdrawnAt and (d.startAt - d.withdrawnAt) >= P["attend.withdrawHours"] * HOUR then
        -- early withdrawal: not counted
      elseif not d.joinedAt then
        out[#out + 1] = { t = ev.t, x = 0, label = "No-show for signed raid", eventId = ev.id }
      elseif d.joinedAt - d.startAt <= P["attend.lateMinutes"] * MIN then
        out[#out + 1] = { t = ev.t, x = 1, label = "On time for raid", eventId = ev.id }
      else
        out[#out + 1] = { t = ev.t, x = P["attend.lateOutcome"], label = string.format("Late to raid (%d min)", (d.joinedAt - d.startAt) / MIN), eventId = ev.id }
      end
    end
  end
  return out
end

-- 5.2 Finishing (instances with at least one boss kill)
C.finish = function(guid, P)
  local out = {}
  for _, ev in ipairs(MemberEvents(guid, P)) do
    do
      local s = SessionOf(ev)
      local sd = s and s.details
      if sd and sd.groupType ~= "quest" and sd.kills and #sd.kills > 0 then
        local lastKill = sd.kills[#sd.kills]
        local final, merged = FinalInterval(ev, P)
        local where = sd.instanceName or sd.zone or "instance"
        if final and (final.leave == nil or final.leave >= lastKill or PresentAt(merged, lastKill)) then
          out[#out + 1] = { t = ev.t, it = lastKill, x = 1, label = "Completed " .. where, eventId = ev.id }
        elseif final then
          local scored, why = EarlyLeaveVerdict(final, P)
          if scored then
            local lootLeave = false
            for _, l in ipairs(ev.details.lootTimes or {}) do
              local lt, q = type(l) == "table" and l.t or l, type(l) == "table" and l.q or 99
              if q >= P["finish.lootMinQuality"] and lt <= final.leave
                and (final.leave - lt) <= P["finish.lootLeaveMinutes"] * MIN then lootLeave = true end
            end
            if lootLeave then
              out[#out + 1] = { t = ev.t, it = final.leave, x = 0, mult = P["finish.lootLeaveWeight"], label = "Loot-and-leave in " .. where, eventId = ev.id }
            else
              out[#out + 1] = { t = ev.t, it = final.leave, x = 0, label = "Left " .. where .. " before the final boss", eventId = ev.id }
            end
          else
            out[#out + 1] = { t = ev.t, x = nil, skip = true, label = "Early leave in " .. where .. ": " .. why, eventId = ev.id }
          end
        end
      end
    end
  end
  return out
end

-- 5.3 Arriving ready (raids)
C.ready = function(guid, P)
  local out = {}
  for _, ev in ipairs(TA.Log:ForSubject(guid)) do
    if ev.signal == "ready" then
      local d = ev.details
      local ok = d.isReady and (d.categories or 0) >= P["ready.minBuffCategories"]
      out[#out + 1] = { t = ev.t, x = ok and 1 or 0, eventId = ev.id,
        label = ok and string.format("Ready (%d consumable categories)", d.categories or 0)
          or (d.isReady and string.format("Ready but %d/%d consumable categories", d.categories or 0, P["ready.minBuffCategories"]) or "Not ready at ready check") }
    end
  end
  return out
end

-- Trades between guid and a counterparty, from the witnessing client's view.
-- Returns list of { t, from, to, copper, items = {itemID=true}, ev }
local function TradesBetween(a, b)
  local selfGUID = TA.playerGUID
  local out = {}
  local other = (a == selfGUID) and b or a
  for _, ev in ipairs(TA.Log:ForSubject(other)) do
    if ev.signal == "trade" then
      local d = ev.details
      -- subject = the other party; "given" = I gave them
      if (d.receivedCopper or 0) > 0 or d.receivedItems then
        out[#out + 1] = { t = ev.t, from = other, to = selfGUID, copper = d.receivedCopper or 0, items = d.receivedItems or {}, ev = ev }
      end
      if (d.givenCopper or 0) > 0 or d.givenItems then
        out[#out + 1] = { t = ev.t, from = selfGUID, to = other, copper = d.givenCopper or 0, items = d.givenItems or {}, ev = ev }
      end
    end
  end
  return out
end
Dims.TradesBetween = TradesBetween

-- 5.5 Paying what's owed
C.pay = function(guid, P, now)
  local out = {}
  for _, ev in ipairs(TA.Log:ForSubject(guid)) do
    if ev.signal == "obligation" then
      local d = ev.details
      local deadline = ev.t + P["pay.deadlineHours"] * HOUR
      local paid, paidAt = 0, nil
      local trades = TradesBetween(guid, d.creditorGUID)
      table.sort(trades, function(x, y) return x.t < y.t end)
      for _, tr in ipairs(trades) do
        if tr.from == guid and tr.to == d.creditorGUID and tr.t >= ev.t then
          paid = paid + tr.copper
          if paid >= d.copper then paidAt = tr.t; break end
        end
      end
      local owed = TA.FormatGold and TA.FormatGold(d.copper) or tostring(d.copper)
      if paidAt and paidAt <= deadline then
        out[#out + 1] = { t = ev.t, x = 1, label = "Paid " .. owed .. " on time", eventId = ev.id }
      elseif paidAt then
        out[#out + 1] = { t = ev.t, x = P["pay.lateOutcome"], label = "Paid " .. owed .. " late", eventId = ev.id }
      elseif now > deadline then
        out[#out + 1] = { t = ev.t, x = 0, label = "Unpaid " .. owed .. " past deadline", eventId = ev.id }
      else
        out[#out + 1] = { t = ev.t, skip = true, label = "Pending obligation " .. owed .. " (not scored yet)", eventId = ev.id }
      end
    end
  end
  return out
end

-- 5.6 Loot honesty
local function StrikeCancelled(guid, strike, P)
  local d = strike.details
  for _, reserverGUID in ipairs(d.reservedByGUIDs or {}) do
    for _, tr in ipairs(TradesBetween(guid, reserverGUID)) do
      if tr.from == guid and tr.to == reserverGUID and tr.items[d.itemID]
        and tr.t >= strike.t and (tr.t - strike.t) <= P["loot.returnMinutes"] * MIN then
        return true
      end
    end
  end
  return false
end

C.loot = function(guid, P)
  local out = {}
  local strikeSessions = {}
  for _, ev in ipairs(TA.Log:ForSubject(guid)) do
    if ev.signal == "lootNeed" then
      local d = ev.details
      local isStrike = not d.master and not d.selfReserved and d.reservedBy and #d.reservedBy > 0
      if isStrike then
        if StrikeCancelled(guid, ev, P) then
          out[#out + 1] = { t = ev.t, skip = true, label = "Need on reserved item, traded back (cancelled)", eventId = ev.id }
        else
          strikeSessions[ev.sessionId or 0] = true
          out[#out + 1] = { t = ev.t, x = 0, label = "Need on an item reserved by " .. table.concat(d.reservedBy, ", "), eventId = ev.id }
        end
      end
    end
  end
  for _, ev in ipairs(MemberEvents(guid, P)) do
    if (ev.details.srRolls or 0) > 0 and not strikeSessions[ev.sessionId] then
      out[#out + 1] = { t = ev.t, it = Dims.AnchorTime(ev, P), x = 1, label = "Clean rolls in a soft-reserve run", eventId = ev.id }
    end
  end
  return out
end

-- 5.7 Carry delivered (guid = carrier)
C.carry = function(guid, P)
  local out = {}
  if not P["carry.autoDetect"] then return out end
  for _, ev in ipairs(MemberEvents(guid, P)) do
    local cy = ev.details.carry
    if cy and (cy.copper or 0) >= P["carry.minGold"] * 10000 then
      local s = SessionOf(ev)
      local kills = s and s.details.kills or {}
      local lastKill = kills[#kills]
      if lastKill and cy.paidAt <= lastKill then
        local final, merged = FinalInterval(ev, P)
        if final.leave == nil or final.leave >= lastKill or PresentAt(merged, lastKill) then
          out[#out + 1] = { t = ev.t, it = lastKill, x = 1, label = "Delivered a paid carry", eventId = ev.id }
        else
          local scored, why = EarlyLeaveVerdict(final, P)
          if scored then
            out[#out + 1] = { t = ev.t, it = final.leave, x = 0, mult = P["finish.lootLeaveWeight"], label = "Left a paid carry early", eventId = ev.id }
          else
            out[#out + 1] = { t = ev.t, skip = true, label = "Carry early leave: " .. why, eventId = ev.id }
          end
        end
      end
    end
  end
  return out
end

-- 5.8 Small generosity (daily cap)
C.generosity = function(guid, P)
  local out, perDay = {}, {}
  local list = TA.Log:ForSubject(guid)
  for _, ev in ipairs(list) do
    if ev.signal == "generosity" then
      local day = math.floor(ev.t / DAY)
      perDay[day] = (perDay[day] or 0) + 1
      if perDay[day] <= P["generosity.dailyCap"] then
        out[#out + 1] = { t = ev.t, x = 1, label = "Generosity: " .. (ev.details.kind or "act"), eventId = ev.id }
      else
        out[#out + 1] = { t = ev.t, skip = true, label = "Generosity over daily cap (not counted)", eventId = ev.id }
      end
    end
  end
  return out
end

-- 5.9 Teaching / higher-level partner
C.teach = function(guid, P)
  local out = {}
  for _, ev in ipairs(MemberEvents(guid, P)) do
    if ev.details.level then
      local levels = {}
      for _, m in ipairs(MembersOf(ev.sessionId)) do
        if m.details.level then levels[#levels + 1] = m.details.level end
      end
      if #levels >= 2 then
        local median = Engine.Median(levels)
        local s = SessionOf(ev)
        local _, merged = FinalInterval(ev, P)
        local stayed = TimeIn(merged, s and s.details.endedAt)
        if ev.details.level - median >= P["teach.levelGap"] and stayed >= P["teach.minMinutes"] * MIN then
          out[#out + 1] = { t = ev.t, it = Dims.AnchorTime(ev, P), x = 1, mult = (s and s.details.learning) and P["teach.learningBonus"] or 1,
            label = string.format("Grouped %d levels above median for %s", ev.details.level - median, TA.FormatDuration and TA.FormatDuration(stayed) or stayed), eventId = ev.id }
        end
      end
    end
  end
  return out
end

-- 5.10 Crafting for others
C.craft = function(guid, P)
  local out = {}
  local selfGUID = TA.playerGUID
  local function add(ev, paidCopper, what)
    local atCost = (paidCopper or 0) <= P["craft.atCostGold"] * 10000
    out[#out + 1] = { t = ev.t, x = 1, mult = atCost and P["craft.atCostMultiplier"] or 1, eventId = ev.id,
      label = what .. (atCost and " for free/at cost" or " for gold") }
  end
  local function scan(ev, mine)
    local d = ev.details
    local paid = mine and d.receivedCopper or d.givenCopper
    if (mine and d.enchantByMe) or (not mine and d.enchantByThem) then add(ev, paid, "Enchanted") end
    local crafted = mine and d.craftedByMe or d.craftedByThem
    if crafted then add(ev, paid, "Gave crafted item" .. (crafted > 1 and "s" or "")) end
  end
  if guid == selfGUID then
    for _, ev in ipairs(TA.Log:All()) do
      if ev.signal == "trade" then scan(ev, true) end
    end
  else
    for _, ev in ipairs(TA.Log:ForSubject(guid)) do
      if ev.signal == "trade" then scan(ev, false) end
    end
  end
  return out
end

-- 5.12 Stayed to help
C.help = function(guid, P)
  local out = {}
  for _, ev in ipairs(TA.Log:ForSubject(guid)) do
    if ev.signal == "quest" and ev.details.myOpen and ev.sessionId then
      local m = MemberEventFor(ev.sessionId, guid)
      if m then
        local final = FinalInterval(m, P)
        local s = SessionOf(m)
        local leftAt = final.leave or (s and s.details.endedAt) or m.t
        if leftAt - ev.t >= P["help.stayMinutes"] * MIN then
          out[#out + 1] = { t = ev.t, x = 1, label = string.format("Stayed %s after finishing quest %d", TA.FormatDuration and TA.FormatDuration(leftAt - ev.t) or "", ev.details.questID or 0), eventId = ev.id }
        end
      end
    end
  end
  return out
end

-- 5.13 Hardcore steadfastness
C.hc = function(guid, P)
  local out = {}
  for _, m in ipairs(MemberEvents(guid, P)) do
    do
      for _, ev in ipairs(TA.Log:ForSession(m.sessionId)) do
        if ev.signal == "hcDeath" and ev.subjectGUID ~= guid then
          local _, merged = FinalInterval(m, P)
          if PresentAt(merged, ev.t) then
            local fled = false
            for _, iv in ipairs(merged) do
              if iv.leave and iv.leave >= ev.t and iv.leave - ev.t <= P["hc.fleeSeconds"] then fled = true end
            end
            if not fled then
              out[#out + 1] = { t = ev.t, x = 1, label = "Stayed after " .. (ev.subjectName or "a party member") .. " died", eventId = ev.id }
            elseif P["hc.fleeScored"] then
              out[#out + 1] = { t = ev.t, x = 1, subtract = true, label = "Left within " .. P["hc.fleeSeconds"] .. "s of a party death", eventId = ev.id }
            else
              out[#out + 1] = { t = ev.t, skip = true, label = "Left soon after a party death (context only)", eventId = ev.id }
            end
          end
        end
      end
    end
  end
  return out
end

-- 5.16 Endorsements (6.7 weighting)
C.endorse = function(guid, P)
  local out, lastByPair = {}, {}
  local list = TA.Log:ForSubject(guid)
  local cooldown = P["endorse.cooldownDays"] * DAY
  for _, ev in ipairs(list) do
    if ev.signal == "endorse" then
      local d = ev.details
      local who = d.endorserGUID or "?"
      if ev.source == "peer" and not P["consent.acceptPeerEndorsements"] then
        out[#out + 1] = { t = ev.t, skip = true, label = "Peer endorsement (peer endorsements disabled)", eventId = ev.id }
      elseif who == guid then
        -- self-endorsement is never counted
      elseif lastByPair[who] and ev.t - lastByPair[who] < cooldown then
        out[#out + 1] = { t = ev.t, skip = true, label = "Endorsement within cooldown (not counted)", eventId = ev.id }
      else
        lastByPair[who] = ev.t
        local trust = Dims.MeanTrust(who, P)
        local mult = Engine.EndorseMultiplier(trust, d.sameGuild, P)
        out[#out + 1] = { t = ev.t, x = 1, mult = mult, eventId = ev.id, endorser = who,
          label = string.format("Endorsed by %s (trust %.2f%s)", d.endorserName or "?", trust, d.sameGuild and ", same guild" or "") }
      end
    end
  end
  return out
end

-------------------------------------------------------------------------------
-- Profiles and caching
-------------------------------------------------------------------------------
local cache, cacheKey = {}, nil

local function CurrentKey(now)
  return string.format("%d:%d:%d", TA.Log.count or 0, TA.Params.version or 0, math.floor(now / 600))
end

function Dims.EvaluateDimension(guid, key, P, now)
  local def = Dims.byKey[key]
  local items = C[key](guid, P, now)
  local scored, skipped = {}, {}
  for _, it in ipairs(items) do
    if it.skip then skipped[#skipped + 1] = it else scored[#scored + 1] = it end
  end
  local r = Engine.Evaluate(def, scored, P, now)
  r.label = def.label
  r.skipped = skipped
  return r
end

-- Mean ratio-dimension score of a player (prior if unknown). Used for 6.7.
function Dims.MeanTrust(guid, P, now)
  now = now or (TA.Now and TA.Now() or os.time())
  local sum, n = 0, 0
  for _, d in ipairs(Dims.list) do
    if d.type == "ratio" then
      local r = Dims.EvaluateDimension(guid, d.key, P, now)
      if r.band ~= "Unknown" then sum, n = sum + r.score, n + 1 end
    end
  end
  if n == 0 then return P["prior.value"] end
  return sum / n
end

-- Returns { dims = { key -> result }, order = {...}, nonDefault = bool, sessions = n }
function Dims.Profile(guid, now)
  now = now or (TA.Now and TA.Now() or os.time())
  local key = CurrentKey(now)
  if key ~= cacheKey then cache, cacheKey = {}, key end
  if cache[guid] then return cache[guid] end
  local P = TA.Params:Snapshot()
  local prof = { guid = guid, dims = {}, order = {}, nonDefault = TA.Params:AnyScoringNonDefault(), computedAt = now }
  for _, d in ipairs(Dims.list) do
    prof.dims[d.key] = Dims.EvaluateDimension(guid, d.key, P, now)
    prof.order[#prof.order + 1] = d.key
  end
  prof.sessions = #MemberEvents(guid, P)
  cache[guid] = prof
  return prof
end

function Dims.Invalidate() cacheKey = nil end

-- Plain-text "Why this band?" explainer with the arithmetic.
function Dims.Explain(guid, key, now)
  now = now or (TA.Now and TA.Now() or os.time())
  local P = TA.Params:Snapshot()
  local r = Dims.EvaluateDimension(guid, key, P, now)
  local lines = {}
  local function add(s) lines[#lines + 1] = s end
  add(string.format("%s (%s dimension) - band %s, confidence %s", r.label, r.type == "ratio" and "ratio" or "accumulating", r.band, r.confidence))
  local hNeg, hPos = P["dim." .. key .. ".halfLifeNeg"], P["dim." .. key .. ".halfLifePos"]
  add(string.format("Base weight %.2f, half-life neg %s / pos %s days", P["dim." .. key .. ".weight"],
    hNeg and (hNeg == 0 and "never" or tostring(hNeg)) or "-", hPos == 0 and "never" or tostring(hPos)))
  if #r.items == 0 then add("No scored events.") end
  local sumWL, sumWLX = 0, 0
  for _, c in ipairs(r.items) do
    local wl = c.w * c.lambda
    sumWL = sumWL + wl
    sumWLX = sumWLX + wl * (c.x or 0)
    add(string.format("  %s  %s  x=%s  w=%.2f  decay=%.3f  contribution=%s%.3f",
      date and date("%Y-%m-%d", c.t) or tostring(c.t), c.label, c.x and string.format("%.2f", c.x) or "-",
      c.w, c.lambda, c.subtract and "-" or "", r.type == "ratio" and wl * c.x or wl))
  end
  for _, c in ipairs(r.skipped) do
    add(string.format("  %s  %s  (not scored)", date and date("%Y-%m-%d", c.t) or tostring(c.t), c.label))
  end
  if r.type == "ratio" then
    local k, p = P["prior.strength"], P["prior.value"]
    add(string.format("S = (k*p + sum w*l*x) / (k + sum w*l) = (%.2f*%.2f + %.3f) / (%.2f + %.3f) = %.3f",
      k, p, sumWLX, k, sumWL, r.score))
    add(string.format("Evidence N = %.3f (Unknown below %s). Bands: Concern <%.2f, Building <%.2f, Solid <%.2f, Exemplary >=%.2f",
      r.evidence, P["conf.minEvidence"], P["band.concern"], P["band.solid"], P["band.exemplary"], P["band.exemplary"]))
  else
    local cap = P["dim." .. key .. ".cap"]
    local net = 0
    for _, c in ipairs(r.items) do net = net + (c.contribution or 0) end
    add(string.format("A = 1 - exp(-(sum w*l) / c) = 1 - exp(-%.3f / %.2f) = %.3f", math.max(0, net), cap, r.score))
    add(string.format("Evidence N = %.3f (Unknown below %s). Bands: Building <%.2f, Solid <%.2f, Exemplary >=%.2f",
      r.evidence, P["conf.minEvidence"], P["band.accSolid"], P["band.accExemplary"], P["band.accExemplary"]))
  end
  add("Result: " .. r.band .. (TA.Params:AnyScoringNonDefault() and "  [your view uses non-default parameters]" or ""))
  return lines, r
end

return Dims
