-- Scoring engine (GDD 6). Pure Lua 5.1, no WoW API: testable outside the game.
-- All constants come from the parameter snapshot P.
local _, TA = ...
TA = TA or {}

local Engine = {}
TA.Engine = Engine

local DAY = 86400

-- 6.1 Decay: lambda = 0.5 ^ (age / h); h = 0 means never decays.
function Engine.Decay(ageDays, halfLife)
  if not halfLife or halfLife <= 0 then return 1 end
  if ageDays <= 0 then return 1 end
  return 0.5 ^ (ageDays / halfLife)
end

function Engine.AgeDays(t, now) return math.max(0, (now - t) / DAY) end

-- Attach lambda to each contribution: c = { t, x, w, negative }
-- dim = { halfLifeNeg, halfLifePos }
function Engine.ApplyDecay(items, now, hNeg, hPos)
  for _, c in ipairs(items) do
    local negative = c.negative
    if negative == nil then negative = (c.x ~= nil and c.x < 1) end
    c.negative = negative
    c.lambda = Engine.Decay(Engine.AgeDays(c.t, now), negative and hNeg or hPos)
  end
  return items
end

-- 6.2 Ratio dimension: S = (k p + sum w l x) / (k + sum w l)
function Engine.Ratio(items, p, k)
  local num, den = k * p, k
  local N = 0
  for _, c in ipairs(items) do
    local wl = c.w * c.lambda
    c.contribution = wl * c.x
    num = num + c.contribution
    den = den + wl
    N = N + wl
  end
  local S = den > 0 and num / den or p
  return S, N
end

-- 6.3 Accumulating dimension: A = 1 - exp(-(sum w l) / c)
-- Items with negative evidence (only when explicitly configured, e.g.
-- hc.fleeScored) subtract; the sum is floored at 0 so A stays in [0, 1).
function Engine.Accumulate(items, cap)
  local sum = 0
  for _, c in ipairs(items) do
    local wl = c.w * c.lambda
    c.contribution = c.subtract and -wl or wl
    sum = sum + c.contribution
  end
  if sum < 0 then sum = 0 end
  cap = (cap and cap > 0) and cap or 1
  local A = 1 - math.exp(-sum / cap)
  return A, sum
end

-- 6.4 Confidence
function Engine.Confidence(N, P)
  if N < P["conf.minEvidence"] then return "Low" end
  if N >= P["conf.highAt"] then return "High" end
  return "Medium"
end

-- 6.5 Bands
function Engine.Band(dimType, score, N, P)
  if N < P["conf.minEvidence"] then return "Unknown" end
  if dimType == "ratio" then
    if score < P["band.concern"] then return "Concern" end
    if score >= P["band.exemplary"] then return "Exemplary" end
    if score >= P["band.solid"] then return "Solid" end
    return "Building"
  else
    if score >= P["band.accExemplary"] then return "Exemplary" end
    if score >= P["band.accSolid"] then return "Solid" end
    return "Building"
  end
end

-- Full evaluation of one dimension from its contributions.
-- dimDef = { key, type }, P = parameter snapshot.
function Engine.Evaluate(dimDef, items, P, now)
  local k = dimDef.key
  local hNeg = P["dim." .. k .. ".halfLifeNeg"] or 0
  local hPos = P["dim." .. k .. ".halfLifePos"] or 0
  local base = P["dim." .. k .. ".weight"] or 1
  for _, c in ipairs(items) do
    c.baseWeight = base
    c.w = base * (c.mult or 1)
  end
  Engine.ApplyDecay(items, now, hNeg, hPos)
  local score, N
  if dimDef.type == "ratio" then
    score, N = Engine.Ratio(items, P["prior.value"], P["prior.strength"])
  else
    local sum
    score, sum = Engine.Accumulate(items, P["dim." .. k .. ".cap"])
    N = 0
    for _, c in ipairs(items) do N = N + c.w * c.lambda end
  end
  return {
    key = k, type = dimDef.type, score = score, evidence = N,
    band = Engine.Band(dimDef.type, score, N, P),
    confidence = Engine.Confidence(N, P),
    items = items,
  }
end

-- 6.7 Endorsement weight multiplier (applied on top of the base weight).
function Engine.EndorseMultiplier(endorserMeanTrust, sameGuild, P)
  local m = 0.5 + 0.5 * endorserMeanTrust
  if sameGuild then m = m * P["endorse.sameGuildMultiplier"] end
  return m
end

function Engine.Median(list)
  local n = #list
  if n == 0 then return 0 end
  local s = {}
  for i = 1, n do s[i] = list[i] end
  table.sort(s)
  if n % 2 == 1 then return s[(n + 1) / 2] end
  return (s[n / 2] + s[n / 2 + 1]) / 2
end

return Engine
