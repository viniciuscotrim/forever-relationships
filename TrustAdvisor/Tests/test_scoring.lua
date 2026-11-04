-- Standalone tests for the scoring engine. Run from the addon root:
--   luajit Tests/test_scoring.lua
-- No WoW API is loaded: Params, EventLog, Engine and Dimensions are pure Lua.
local root = (arg and arg[0] or ""):match("^(.*)Tests/") or "./"
local TA = {}
TA.Now = function() return TA._now end
TA.FormatGold = function(c) return tostring(c / 10000) .. "g" end
TA.FormatDuration = function(s) return tostring(math.floor(s / 60)) .. "m" end
date = os.date

local function load(path) assert(loadfile(root .. path))("TrustAdvisor", TA) end
load("Core/Params.lua")
load("Core/EventLog.lua")
load("Scoring/Engine.lua")
load("Scoring/Dimensions.lua")

local DAY, MIN = 86400, 60
local passed, failed = 0, 0
local function test(name, fn)
  TA._now = 1800000000
  TA.playerGUID = "Player-SELF"
  TA.Params:Bind({}, {}, function() return TA._now end)
  TA.Log:Bind({ events = {}, nextEventId = 1 })
  TA.Dimensions.Invalidate()
  local ok, err = pcall(fn)
  if ok then passed = passed + 1; print("  ok   " .. name)
  else failed = failed + 1; print("  FAIL " .. name .. "\n       " .. tostring(err)) end
end
local function near(a, b, eps, what)
  if math.abs(a - b) > (eps or 1e-6) then error(string.format("%s: expected %.6f got %.6f", what or "value", b, a), 2) end
end
local function eq(a, b, what)
  if a ~= b then error(string.format("%s: expected %s got %s", what or "value", tostring(b), tostring(a)), 2) end
end

local E, D = TA.Engine, TA.Dimensions
local function P() return TA.Params:Snapshot() end

-- Helpers to fabricate a dungeon session
local sid = 0
local function session(opts)
  sid = sid + 1
  local id = "S" .. sid
  local start = opts.start or (TA._now - 2 * 3600)
  TA.Log:Append({ signal = "session", sessionId = id, t = opts.endedAt or (start + 3600), details = {
    startedAt = start, endedAt = opts.endedAt or (start + 3600), groupType = opts.groupType or "dungeon",
    kills = opts.kills or {}, instanceName = "Test Keep" } })
  for _, m in ipairs(opts.members) do
    TA.Log:Append({ signal = "member", sessionId = id, subjectGUID = m.guid, subjectName = m.guid,
      t = opts.endedAt or (start + 3600), details = { level = m.level or 60, intervals = m.intervals or { { join = start } },
      lootTimes = m.lootTimes, carry = m.carry, srRolls = m.srRolls } })
  end
  return id, start
end

print("Trust Advisor scoring tests")

test("empty history = Unknown for every dimension", function()
  local prof = D.Profile("Player-X")
  for _, k in ipairs(prof.order) do eq(prof.dims[k].band, "Unknown", k) end
end)

test("one negative event decays to half at its half-life", function()
  near(E.Decay(60, 60), 0.5, 1e-9, "decay")
  near(E.Decay(0, 60), 1, 1e-9, "fresh")
  near(E.Decay(120, 60), 0.25, 1e-9, "two half-lives")
  near(E.Decay(9999, 0), 1, 1e-9, "half-life 0 never decays")
end)

test("prior pulls one event toward 0.75", function()
  local items = E.ApplyDecay({ { t = TA._now, x = 0, w = 1 } }, TA._now, 60, 365)
  local S = E.Ratio(items, 0.75, 3)
  near(S, (3 * 0.75 + 0) / 4, 1e-9, "S")
  local items2 = E.ApplyDecay({ { t = TA._now, x = 1, w = 1 } }, TA._now, 60, 365)
  near(E.Ratio(items2, 0.75, 3), (2.25 + 1) / 4, 1e-9, "S positive")
end)

test("accumulating dimensions never exceed 1", function()
  local items = {}
  for i = 1, 5000 do items[i] = { t = TA._now, x = 1, w = 10, lambda = 1 } end
  local A = E.Accumulate(items, 1)
  assert(A <= 1, "A > 1")
  assert(A >= 0.999, "A should approach 1")
end)

test("accumulating dimensions cannot produce Concern", function()
  local p = P()
  for _, s in ipairs({ 0, 0.1, 0.39, 0.5, 0.99 }) do
    assert(E.Band("acc", s, 100, p) ~= "Concern", "Concern on acc")
  end
end)

test("bands follow thresholds and Unknown under evidence", function()
  local p = P()
  eq(E.Band("ratio", 0.49, 10, p), "Concern")
  eq(E.Band("ratio", 0.50, 10, p), "Building")
  eq(E.Band("ratio", 0.75, 10, p), "Solid")
  eq(E.Band("ratio", 0.90, 10, p), "Exemplary")
  eq(E.Band("ratio", 0.10, 2.9, p), "Unknown")
  eq(E.Confidence(2, p), "Low"); eq(E.Confidence(5, p), "Medium"); eq(E.Confidence(10, p), "High")
end)

test("parameter change recomputes scores", function()
  for i = 1, 4 do
    session({ start = TA._now - i * DAY, kills = { TA._now - i * DAY + 1800 },
      members = { { guid = "Player-A", intervals = { { join = TA._now - i * DAY } } } } })
  end
  local before = D.Profile("Player-A").dims.finish
  eq(before.band, "Solid", "4 completions with prior")
  TA.Params:Set("conf.minEvidence", 4.5)
  local after = D.Profile("Player-A").dims.finish
  eq(after.band, "Unknown", "raised evidence threshold")
  TA.Params:Set("conf.minEvidence", 3)
  TA.Params:Set("band.exemplary", 0.85)
  eq(D.Profile("Player-A").dims.finish.band, "Exemplary", "lowered exemplary threshold")
  eq(#TA.Params.log, 3, "change log entries")
end)

test("loot-and-leave weighs x3 and confirmed voluntary leave is required", function()
  local start = TA._now - DAY
  session({ start = start, kills = { start + 600, start + 3000 }, members = {
    { guid = "Player-B", lootTimes = { start + 700 }, intervals = { { join = start, leave = start + 900, reason = "voluntary" } } } } })
  local r = D.Profile("Player-B").dims.finish
  eq(#r.items, 1, "items"); near(r.items[1].w, 3, 1e-9, "weight"); eq(r.items[1].x, 0, "x")
  -- same but leave reason unknown: not scored
  session({ start = start, kills = { start + 3000 }, members = {
    { guid = "Player-C", intervals = { { join = start, leave = start + 900, reason = "unknown" } } } } })
  local rc = D.Profile("Player-C").dims.finish
  eq(#rc.items, 0, "unknown reason not scored"); eq(#rc.skipped, 1, "shown as skipped")
end)

test("disconnect rejoin within grace counts as completed", function()
  local start = TA._now - DAY
  session({ start = start, kills = { start + 3000 }, members = {
    { guid = "Player-D", intervals = { { join = start, leave = start + 600, reason = "voluntary" }, { join = start + 900 } } } } })
  local r = D.Profile("Player-D").dims.finish
  eq(r.items[1].x, 1, "completed after rejoin")
end)

test("wipes excuse leaving", function()
  local start = TA._now - DAY
  session({ start = start, kills = { start + 3000 }, members = {
    { guid = "Player-E", intervals = { { join = start, leave = start + 600, reason = "voluntary", wipeStreak = 3 } } } } })
  local r = D.Profile("Player-E").dims.finish
  eq(#r.items, 0, "excused"); eq(#r.skipped, 1, "explained")
end)

test("payment on time, late, unpaid", function()
  local t0 = TA._now - 3 * DAY
  TA.Log:Append({ signal = "obligation", subjectGUID = "Player-F", t = t0, details = { creditorGUID = "Player-SELF", copper = 1000000 } })
  TA.Log:Append({ signal = "trade", subjectGUID = "Player-F", t = t0 + 3600, details = { receivedCopper = 1000000 } })
  TA.Log:Append({ signal = "obligation", subjectGUID = "Player-G", t = t0, details = { creditorGUID = "Player-SELF", copper = 500000 } })
  TA.Log:Append({ signal = "trade", subjectGUID = "Player-G", t = t0 + 2 * DAY, details = { receivedCopper = 500000 } })
  TA.Log:Append({ signal = "obligation", subjectGUID = "Player-H", t = t0, details = { creditorGUID = "Player-SELF", copper = 500000 } })
  eq(D.Profile("Player-F").dims.pay.items[1].x, 1, "on time")
  eq(D.Profile("Player-G").dims.pay.items[1].x, 0.5, "late")
  eq(D.Profile("Player-H").dims.pay.items[1].x, 0, "unpaid")
end)

test("loot strike cancelled by trading the item back", function()
  local t0 = TA._now - DAY
  TA.Log:Append({ signal = "lootNeed", subjectGUID = "Player-SELF", sessionId = "L1", t = t0,
    details = { itemID = 123, reservedBy = { "Res" }, reservedByGUIDs = { "Player-R" } } })
  TA.Log:Append({ signal = "trade", subjectGUID = "Player-R", t = t0 + 600, details = { givenItems = { [123] = true } } })
  local r = D.Profile("Player-SELF").dims.loot
  eq(#r.items, 0, "strike cancelled")
  TA.Log:Append({ signal = "lootNeed", subjectGUID = "Player-I", sessionId = "L2", t = t0,
    details = { itemID = 5, reservedBy = { "Res" }, reservedByGUIDs = { "Player-R2" } } })
  eq(D.Profile("Player-I").dims.loot.items[1].x, 0, "strike stands")
end)

test("generosity daily cap", function()
  for i = 1, 15 do TA.Log:Append({ signal = "generosity", subjectGUID = "Player-J", t = TA._now - 100 - i, details = { kind = "buff" } }) end
  local r = D.Profile("Player-J").dims.generosity
  eq(#r.items, 10, "capped"); eq(#r.skipped, 5, "rest explained")
end)

test("endorsements: cooldown per pair and same-guild multiplier", function()
  TA.Log:Append({ signal = "endorse", subjectGUID = "Player-K", t = TA._now - 3 * DAY, details = { endorserGUID = "Player-L", endorserName = "L" } })
  TA.Log:Append({ signal = "endorse", subjectGUID = "Player-K", t = TA._now - 1 * DAY, details = { endorserGUID = "Player-L", endorserName = "L" } })
  TA.Log:Append({ signal = "endorse", subjectGUID = "Player-K", t = TA._now - 1 * DAY, details = { endorserGUID = "Player-M", endorserName = "M", sameGuild = true } })
  local r = D.Profile("Player-K").dims.endorse
  eq(#r.items, 2, "one per pair in cooldown")
  near(r.items[1].mult, 0.5 + 0.5 * 0.75, 1e-9, "unknown endorser uses prior")
  near(r.items[2].mult, (0.5 + 0.5 * 0.75) * 0.5, 1e-9, "same guild halves")
end)

test("teaching: higher-level partner counted", function()
  local start = TA._now - DAY
  session({ start = start, groupType = "quest", endedAt = start + 3600, members = {
    { guid = "Player-N", level = 30 }, { guid = "Player-O", level = 20 }, { guid = "Player-P", level = 21 } } })
  eq(#D.Profile("Player-N").dims.teach.items, 1, "N teaches")
  eq(#D.Profile("Player-O").dims.teach.items, 0, "O does not")
end)

test("hardcore: stayed counts, fled is context only by default", function()
  local start = TA._now - DAY
  local id = session({ start = start, groupType = "quest", endedAt = start + 3600, members = {
    { guid = "Player-Q" }, { guid = "Player-R", intervals = { { join = start, leave = start + 1210, reason = "voluntary" } } }, { guid = "Player-S" } } })
  TA.Log:Append({ signal = "hcDeath", subjectGUID = "Player-S", subjectName = "S", sessionId = id, t = start + 1200 })
  eq(#D.Profile("Player-Q").dims.hc.items, 1, "Q stayed")
  local r = D.Profile("Player-R").dims.hc
  eq(#r.items, 0, "fled not scored"); eq(#r.skipped, 1, "fled shown as context")
end)

test("explainer shows arithmetic", function()
  session({ start = TA._now - DAY, kills = { TA._now - DAY + 100 }, members = { { guid = "Player-T" } } })
  local lines = D.Explain("Player-T", "finish")
  local all = table.concat(lines, "\n")
  assert(all:find("S = %(k%*p"), "formula line missing")
  assert(all:find("Completed"), "event row missing")
end)

test("locked network parameters cannot be edited", function()
  local ok = TA.Params:Set("net.minWitnesses", 1)
  eq(ok, false, "locked")
  eq(TA.Params:Get("net.minWitnesses"), 2, "unchanged")
end)

test("no chat text can enter the event log", function()
  local ev = TA.Log:Append({ signal = "member", subjectGUID = "Player-U", details = { text = "hello", nested = { message = "x" } } })
  eq(ev.details.text, nil, "text scrubbed"); eq(ev.details.nested.message, nil, "nested scrubbed")
end)

test("sessions shorter than session.minMinutes are ignored", function()
  local start = TA._now - DAY
  session({ start = start, endedAt = start + 120, kills = { start + 60 }, members = { { guid = "Player-V" } } })
  eq(#D.Profile("Player-V").dims.finish.items, 0, "2-minute session ignored")
  eq(D.Profile("Player-V").sessions, 0, "not counted as a session")
  TA.Params:Set("session.minMinutes", 1)
  eq(#D.Profile("Player-V").dims.finish.items, 1, "counts once the threshold is lowered")
end)

test("attendance: on time, late, no-show, early withdrawal ignored", function()
  local st = TA._now - DAY
  local function att(guid, d) d.startAt = st; TA.Log:Append({ signal = "attendance", subjectGUID = guid, t = st, details = d }) end
  att("Player-W", { joinedAt = st + 300 })
  att("Player-W", { joinedAt = st + 1800 })
  att("Player-W", {})
  att("Player-W", { withdrawnAt = st - 5 * 3600 })
  local r = D.Profile("Player-W").dims.attend
  eq(#r.items, 3, "withdrawal ignored")
  eq(r.items[1].x, 1, "on time"); eq(r.items[2].x, 0.5, "late"); eq(r.items[3].x, 0, "no-show")
end)

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
