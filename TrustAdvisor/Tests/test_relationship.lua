-- Relationship statistics (pure Lua, no WoW API) and the v1 -> v2 migration.
--   luajit Tests/test_relationship.lua
local root = (arg and arg[0] or ""):match("^(.*)Tests/") or "./"
local TA = {}
TA.Now = function() return 1800000000 end
TA.FormatDuration = function(s) return math.floor(s / 60) .. "m" end
TA.FormatAgo = function() return "ago" end
TA.FormatGold = function(c) return c .. "c" end
date = os.date
local function load(path) assert(loadfile(root .. path))("TrustAdvisor", TA) end
load("Core/Params.lua"); load("Core/EventLog.lua"); load("Relationship/Stats.lua")

local passed, failed = 0, 0
local function test(name, fn)
  TA.playerGUID = "Player-1-ME"
  TA.Params:Bind({}, {}, TA.Now)
  TA.db = { events = {}, nextEventId = 1, players = {} }
  TA.Log:Bind(TA.db)
  TA.Rel.Invalidate()
  local ok, err = pcall(fn)
  if ok then passed = passed + 1; print("  ok   " .. name) else failed = failed + 1; print("  FAIL " .. name .. "\n       " .. tostring(err)) end
end
local function eq(a, b, w) if a ~= b then error(("%s: expected %s got %s"):format(w, tostring(b), tostring(a)), 2) end end

local T0 = 1799990000
local function session(id, gtype, kills, members)
  TA.Log:Append({ signal = "session", sessionId = id, t = T0 + 3600, details = { startedAt = T0, endedAt = T0 + 3600, groupType = gtype, kills = kills, instanceName = "Keep" } })
  for _, m in ipairs(members) do
    TA.db.players[m.g] = TA.db.players[m.g] or { name = m.g }
    TA.Log:Append({ signal = "member", sessionId = id, subjectGUID = m.g, t = T0 + 3600, details = { level = m.lvl or 30, intervals = m.iv, lootTimes = m.loot } })
  end
end

print("Relationship tests")

test("overlap of membership intervals", function()
  local w = TA.Rel.Overlaps({ { join = 0, leave = 100 } }, { { join = 50 }, }, 200)
  eq(#w, 1, "one window"); eq(w[1].s, 50, "start"); eq(w[1].e, 100, "end")
  eq(#TA.Rel.Overlaps({ { join = 0, leave = 10 } }, { { join = 20 } }, 30), 0, "no overlap")
end)

test("kills and completion count only while both were present", function()
  session("S1", "dungeon", { T0 + 600, T0 + 3000 }, {
    { g = "Player-1-ME", iv = { { join = T0 } } },
    { g = "Player-1-A", iv = { { join = T0 } } },
    { g = "Player-1-B", iv = { { join = T0, leave = T0 + 1200 } } },
  })
  local a, b = TA.Rel:Compute("Player-1-A"), TA.Rel:Compute("Player-1-B")
  eq(a.kills, 2, "A kills"); eq(a.dungeons, 1, "A completed"); eq(a.seconds, 3600, "A time")
  eq(b.kills, 1, "B kills"); eq(b.dungeons, 0, "B left before the last boss: no completion"); eq(b.seconds, 1200, "B time")
end)

test("short groups don't count; circle ordered by time together", function()
  TA.Log:Append({ signal = "session", sessionId = "S2", t = T0 + 60, details = { startedAt = T0, endedAt = T0 + 60, groupType = "quest", kills = {} } })
  TA.db.players["Player-1-C"] = { name = "C" }
  TA.Log:Append({ signal = "member", sessionId = "S2", subjectGUID = "Player-1-ME", details = { intervals = { { join = T0 } } } })
  TA.Log:Append({ signal = "member", sessionId = "S2", subjectGUID = "Player-1-C", details = { intervals = { { join = T0 } } } })
  eq(TA.Rel:Compute("Player-1-C").sessions, 0, "1-minute group ignored")
  session("S3", "quest", {}, { { g = "Player-1-ME", iv = { { join = T0 } } }, { g = "Player-1-A", iv = { { join = T0 } } }, { g = "Player-1-D", iv = { { join = T0, leave = T0 + 900 } } } })
  local c = TA.Rel:Circle()
  eq(c[1].guid, "Player-1-A", "most time first"); eq(c[2].guid, "Player-1-D", "then D")
end)

test("trades and help in both directions", function()
  TA.db.players["Player-1-A"] = { name = "A" }
  TA.Log:Append({ signal = "trade", subjectGUID = "Player-1-A", details = { givenCopper = 500, receivedCopper = 0, enchantByThem = true } })
  TA.Log:Append({ signal = "generosity", subjectGUID = "Player-1-A", details = { kind = "summon" } })
  TA.Log:Append({ signal = "generosity", subjectGUID = "Player-1-ME", details = { kind = "buff", recipientGUID = "Player-1-A" } })
  local r = TA.Rel:Compute("Player-1-A")
  eq(r.trades, 1, "trades"); eq(r.goldGiven, 500, "gold given"); eq(r.craftsByThem, 1, "craft by them")
  eq(r.helpReceived.summon, 1, "summon received"); eq(r.helpGiven.buff, 1, "buff given")
end)

test("every field renders without errors", function()
  session("S4", "raid", { T0 + 100 }, { { g = "Player-1-ME", iv = { { join = T0 } }, lvl = 60 }, { g = "Player-1-A", iv = { { join = T0 } }, lvl = 58 } })
  local r = TA.Rel:Compute("Player-1-A")
  for _, f in ipairs(TA.Rel.FIELDS) do assert(type(f.value(r)) == "string", f.key) end
  eq(r.levelGap, -2, "2 below you")
  local m = TA.Rel:Mine()
  for _, item in ipairs(TA.Rel.PROFILE_ITEMS) do assert(item.value(m) ~= nil, item.key) end
  eq(m.raids, 1, "my raids")
end)

test("v1 -> v2 migration deletes opinions and manual inputs", function()
  TA.CopyTable = function(t) return t end
  load("Core/Init.lua")
  local db = { events = {
    { signal = "member", details = { srRolls = 2, carry = {} } }, { signal = "endorse" }, { signal = "obligation" },
    { signal = "lootNeed" }, { signal = "attendance" }, { signal = "trade" } },
    signups = {}, softReserves = {}, obligations = {}, net = { uploaderId = "abc" }, params = { ["consent.network"] = true, ["session.minMinutes"] = 7 } }
  local cdb = { affinity = { x = { note = "secret opinion" } }, endorseGiven = {} }
  TA.Migrations[2](db, cdb)
  eq(#db.events, 2, "only facts kept"); eq(db.events[1].details.srRolls, nil, "sr rolls dropped")
  eq(cdb.affinity, nil, "notes and private yes/no deleted"); eq(db.signups, nil, "signups deleted")
  eq(db.cloud.uploaderId, "abc", "cloud identity kept"); eq(db.params["consent.network"], nil, "obsolete params dropped")
  eq(db.params["session.minMinutes"], 7, "valid params kept")
end)

print(("\n%d passed, %d failed"):format(passed, failed))
if failed > 0 then os.exit(1) end
