-- Loads every addon file in TOC order against a mock WoW API, then replays a
-- dungeon run (event fixture) and drives the UI and slash commands.
-- Catches load errors, nil-calls and handler errors before going in game.
--   luajit Tests/test_ingame_sim.lua
local root = (arg and arg[0] or ""):match("^(.*)Tests/") or "./"
local errors = {}

-------------------------------------------------------------------------------
-- Mock WoW API
-------------------------------------------------------------------------------
local clock = 1800000000
local timers = {}
local function advance(sec)
  local target = clock + sec
  while true do
    table.sort(timers, function(a, b) return a.at < b.at end)
    local t = timers[1]
    if not t or t.at > target then break end
    table.remove(timers, 1)
    clock = t.at
    local ok, err = pcall(t.fn)
    if not ok then errors[#errors + 1] = "timer: " .. tostring(err) end
    if t.every and not t.cancelled then t.at = clock + t.every; table.insert(timers, t) end
  end
  clock = target
end

local Stub
local stubMeta = {}
stubMeta.__index = function(t, k)
  local special = {
    GetText = function() return rawget(t, "_text") or "" end,
    SetText = function(self, v) rawset(self, "_text", v) end,
    HasFocus = function() return false end,
    GetStringHeight = function() return 12 end,
    IsShown = function(self) return rawget(self, "_shown") or false end,
    Show = function(self) rawset(self, "_shown", true) end,
    Hide = function(self) rawset(self, "_shown", false) end,
    SetShown = function(self, v) rawset(self, "_shown", v and true or false) end,
    GetFontString = function() return Stub() end,
    CreateFontString = function() return Stub() end,
    CreateTexture = function() return Stub() end,
    RegisterEvent = function(self, e) rawget(self, "_events")[e] = true end,
    SetScript = function(self, name, fn) rawget(self, "_scripts")[name] = fn end,
    GetScript = function(self, name) return rawget(self, "_scripts")[name] end,
    GetUnit = function() return "Tanky", "mouseover" end,
  }
  if special[k] then return special[k] end
  return function() return nil end
end
Stub = function() return setmetatable({ _events = {}, _scripts = {} }, stubMeta) end

local frames = {}
function CreateFrame(kind, name, parent, template)
  local f = Stub()
  frames[#frames + 1] = f
  if name then _G[name] = f end
  return f
end
UIParent = Stub(); GameTooltip = Stub(); DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) print("  [chat] " .. m) end }
UISpecialFrames = {}; StaticPopupDialogs = {}; SlashCmdList = {}
RAID_CLASS_COLORS = { WARRIOR = { r = 0.78, g = 0.61, b = 0.43 }, PRIEST = { r = 1, g = 1, b = 1 } }
tinsert, wipe, date = table.insert, function(t) for k in pairs(t) do t[k] = nil end return t end, os.date
unpack = unpack or table.unpack
function hooksecurefunc() end
function issecretvalue(v) return v == "SECRET" end
function GetServerTime() return clock end
function GetTime() return clock end
function InCombatLockdown() return false end
function GetBuildInfo() return "1.60.1", "70755", "Nov 2026", 16001 end
function GetNormalizedRealmName() return "Forever" end
function FauxScrollFrame_GetOffset() return 0 end
function FauxScrollFrame_Update() end
function FauxScrollFrame_OnVerticalScroll() end
function StaticPopup_Show() end
C_Timer = {
  After = function(s, fn) table.insert(timers, { at = clock + s, fn = fn }) end,
  NewTicker = function(s, fn) local t = { at = clock + s, fn = fn, every = s }; t.Cancel = function() t.cancelled = true end; table.insert(timers, t); return t end,
}
C_ChatInfo = { RegisterAddonMessagePrefix = function() return true end, SendAddonMessage = function(p, m, c, t) _G.__sent = (_G.__sent or 0) + 1 end }
C_FriendList = { IsFriend = function() return false end, AddFriend = function() end, GetNumFriends = function() return 0 end }
C_QuestLog = { GetLogIndexForQuestID = function(q) return q == 100 and 3 or nil end, IsComplete = function() return false end,
  IsQuestFlaggedCompleted = function(q) return q == 7848 end }
C_Spell = { GetSpellName = function(id) return "Spell" .. id end }
C_UnitAuras = { GetAuraDataByIndex = function(unit, i) if i == 1 then return { spellId = 17626, name = "Flask" } end end }
Enum = { TooltipDataType = { Unit = 2 } }
ERR_LEFT_GROUP_S = "%s leaves the party."
ERR_RAID_MEMBER_REMOVED_S = "%s has left the raid group."
ERR_PARTY_LFG_BOOT_VOTE_SUCCEEDED = "The vote to kick %s has passed."
LOOT_ITEM = "%s receives loot: %s."
LOOT_ITEM_SELF = "You receive loot: %s."
LOOT_ITEM_MULTIPLE = "%s receives loot: %sx%d."
LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %sx%d."
LOOT_ROLL_NEED = "%s has selected Need for: %s"
LOOT_ROLL_NEED_SELF = "You have selected Need for: %s"
LOOT_ROLL_GREED = "%s has selected Greed for: %s"
LOOT_ROLL_GREED_SELF = "You have selected Greed for: %s"
ERR_TRADE_COMPLETE = "Trade complete."
YES, NO, CANCEL = "Yes", "No", "Cancel"

-- group state
local units = {
  player = { guid = "Player-1-00000001", name = "Me", class = "PRIEST", level = 30 },
}
local party = {}
function IsInGroup() return #party > 0 end
function IsInRaid() return false end
function GetNumSubgroupMembers() return #party end
function GetNumGroupMembers() return #party + 1 end
local function U(unit)
  if unit == "player" then return units.player end
  local i = tonumber((unit or ""):match("^party(%d)$"))
  if i then return party[i] end
  if unit == "NPC" then return units.npc end
  if unit == "mouseover" then return party[1] end
end
function UnitGUID(u) local x = U(u); return x and x.guid end
function UnitName(u) local x = U(u); return x and x.name, nil end
function UnitClass(u) local x = U(u); return x and x.class, x and x.class end
function UnitLevel(u) local x = U(u); return x and x.level end
function UnitIsConnected(u) return U(u) ~= nil end
function UnitIsPlayer(u) return U(u) ~= nil end
function UnitIsDeadOrGhost() return false end
function GetGuildInfo(u) return u == "player" and "Mine" or "Other Guild" end
function GetInstanceInfo() return "Test Keep", "party" end
function GetRealZoneText() return "Test Keep" end
function GetPlayerTradeMoney() return 0 end
function GetTargetTradeMoney() return 50000 end
function GetTradePlayerItemLink() end
function GetTradeTargetItemLink() end
function GetTradePlayerItemInfo(i) if i == 7 then return "Bracers", 1, 1, 2, nil, "Enchant Bracer - Stamina" end end
function GetTradeTargetItemInfo() end
function GetItemInfo(link) return "Item", link, 3 end
function GetChannelName() return 0 end

-------------------------------------------------------------------------------
-- Load addon files in TOC order with a shared namespace
-------------------------------------------------------------------------------
local ns = {}
local files = {}
for line in io.lines(root .. "TrustAdvisor.toc") do
  if not line:find("^##") and line:find("%.lua$") then files[#files + 1] = (line:gsub("\\", "/")) end
end
for _, f in ipairs(files) do
  local chunk, err = loadfile(root .. f)
  if not chunk then errors[#errors + 1] = "load " .. f .. ": " .. err
  else
    local ok, e = pcall(chunk, "TrustAdvisor", ns)
    if not ok then errors[#errors + 1] = "run " .. f .. ": " .. tostring(e) end
  end
end
local TA = ns
local mainFrame = _G.TrustAdvisorEventFrame
local function fire(event, ...)
  local fn = mainFrame._scripts.OnEvent
  fn(mainFrame, event, ...)
end

-- surface any internal handler errors
local origDebug = TA.Debug
TA.Debug = function(...)
  local s = table.concat({ ... }, " ", 1, select("#", ...) > 0 and 1 or 0)
  local first = tostring((...))
  if first == "handler error" or first == "listener error" then
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    errors[#errors + 1] = table.concat(parts, " ")
  end
end

-------------------------------------------------------------------------------
-- Scenario
-------------------------------------------------------------------------------
print("Trust Advisor in-game simulation")
fire("ADDON_LOADED", "TrustAdvisor")
fire("PLAYER_LOGIN")
advance(1)

-- form a party of 3
party = {
  { guid = "Player-1-0000000A", name = "Tanky", class = "WARRIOR", level = 38 },
  { guid = "Player-1-0000000B", name = "Leafy", class = "PRIEST", level = 29 },
}
fire("GROUP_ROSTER_UPDATE"); advance(1)
assert(TA.Sessions:Active(), "session should start")
-- peer HELLO & quest from Tanky (Trust Advisor user)
fire("CHAT_MSG_ADDON", "TrustAdv", "1|HELLO|Player-1-0000000A;1;Q,A,E,P", "PARTY", "Tanky")
advance(60)
-- Questie announcement from Leafy, plus ordinary chat that must not be stored
fire("CHAT_MSG_PARTY", "{rt1} Questie: Quest Completed: |cffffff00|Hquest:100:30|h[The Test]|h|r", "Leafy", nil, nil, nil, nil, nil, nil, nil, nil, nil, "Player-1-0000000B")
fire("CHAT_MSG_PARTY", "my secret plans for tonight", "Tanky", nil, nil, nil, nil, nil, nil, nil, nil, nil, "Player-1-0000000A")
-- boss kill, loot to Leafy, Leafy leaves voluntarily soon after (loot-and-leave)
advance(600)
fire("ENCOUNTER_END", 1, "Boss One", 1, 5, 1)
fire("CHAT_MSG_LOOT", "Leafy receives loot: |cff0070dd|Hitem:999::::::::|h[Shiny]|h|r.")
advance(120)
fire("CHAT_MSG_SYSTEM", "Leafy leaves the party.")
table.remove(party, 2)
fire("GROUP_ROSTER_UPDATE"); advance(1)
-- trade: Tanky enchants my bracers and I receive 5s (sim)
units.npc = party[1]
fire("TRADE_SHOW"); fire("TRADE_ACCEPT_UPDATE", 1, 1); fire("UI_INFO_MESSAGE", 0, "Trade complete.")
advance(1500)
fire("ENCOUNTER_END", 2, "Boss Two", 1, 5, 1)
advance(300)
-- disband
party = {}
fire("GROUP_LEFT"); advance(5)

assert(not TA.Sessions:Active(), "session should end")
local counts = {}
for _, ev in ipairs(TA.Log:All()) do counts[ev.signal] = (counts[ev.signal] or 0) + 1 end
for k, v in pairs(counts) do print(string.format("  logged %-10s x%d", k, v)) end
assert(counts.session == 1 and counts.member == 3, "session + 3 members")
assert(counts.quest == 1, "Questie completion captured")
assert(counts.trade == 1, "trade captured")

-- no chat text anywhere in SavedVariables
local function scan(t, depth)
  depth = depth or 0
  if depth > 12 then return end
  for k, v in pairs(t) do
    if type(v) == "string" and (v:find("secret plans") or v:find("Questie:")) then error("chat text stored at key " .. tostring(k)) end
    if type(v) == "table" then scan(v, depth + 1) end
  end
end
scan(TrustAdvisorDB); scan(TrustAdvisorCharDB)
print("  ok   no chat text in SavedVariables")

-- scoring outcomes
local leafy = TA.Dimensions.Profile("Player-1-0000000B")
local f = leafy.dims.finish.items[1]
assert(f and f.x == 0 and f.w == 3, "Leafy loot-and-leave weighted x3")
print("  ok   loot-and-leave detected for Leafy")
local tanky = TA.Dimensions.Profile("Player-1-0000000A")
assert(tanky.dims.finish.items[1].x == 1, "Tanky completed")
assert(#tanky.dims.craft.items == 1, "Tanky crafted for me")
assert(#tanky.dims.teach.items == 1, "Tanky higher-level partner")
print("  ok   Tanky: completed, crafted, higher-level partner")
assert(TA.cdb.affinity["Player-1-0000000A"].sessions[1].chat >= 1, "chat counted")
print("  ok   affinity counted chat without text")

-- UI and slash commands
TA.UI:Open("players")
for _, t in ipairs(TA.UI.TABS) do TA.UI.SelectTab(t.key) end
TA.UI:OpenPlayer("Player-1-0000000A")
TA.UI.views.card.tab = "affinity"; TA.UI.views.card:Refresh()
TA.UI.views.transparency.sub = "Formulas"; TA.UI.views.transparency:Refresh()
for _, s in ipairs({ "Captures", "Change log", "Data inventory", "Parameters" }) do TA.UI.views.transparency.sub = s; TA.UI.views.transparency:Refresh() end
print("  line " .. TA.UI.TooltipLine("Player-1-0000000A"))
for _, cmd in ipairs({ "help", "why Leafy finish", "player Tanky", "status", "owe Tanky 10", "iowe Tanky 2", "signup add Tanky Leafy",
  "signup start 0", "signup show", "signup close", "invisible", "invisible", "lfg", "export", "debug", "debug", "reset params", "sr clear" }) do
  TA.HandleSlash(cmd)
end
-- endorsement flow
local ok = TA.Endorse:Give("Player-1-0000000A", "Tanky-Forever")
assert(ok, "endorse ok")
assert(not TA.Endorse:Give("Player-1-0000000A", "Tanky-Forever"), "cooldown blocks second endorsement")
-- param edit rescoring
TA.Params:Set("finish.lootLeaveWeight", 5)
TA.Dimensions.Invalidate()
assert(TA.Dimensions.Profile("Player-1-0000000B").dims.finish.items[1].w == 5, "retroactive rescoring")
print("  ok   parameter edit rescored retroactively")
-- malformed / spoofed peer messages are dropped
fire("CHAT_MSG_ADDON", "TrustAdv", "garbage", "PARTY", "Tanky")
fire("CHAT_MSG_ADDON", "TrustAdv", "1|QUEST|Player-1-DEADBEEF;5", "WHISPER", "Stranger")
advance(10)
print(string.format("  ok   %d malformed/spoofed messages dropped", TA.Protocol.dropped or 0))
-- Welcome screen and companion detection
assert(TA.db.welcomed, "welcome shown on first login")
TA.UI.ShowWelcome()
assert(TA.Network:CompanionStatus() == "off", "network off by default")
TA.Params:Set("consent.network", true)
assert(TA.Network:CompanionStatus() == "waiting", "just joined: waiting for first sync")
TA.loginAt = TA.Now() + 1                       -- simulate a later login with no NetData
assert(TA.Network:CompanionStatus() == "missing", "companion missing after relog")
TrustAdvisorNetData = { protocol = 1, generatedAt = TA.Now() + 2, players = {}, companion = { version = "0.3.0" } }
assert(TA.Network:CompanionStatus() == "ok" and TA.Network:CompanionVersion() == "0.3.0", "companion syncing")
assert(TA.Network:LinkText():find("unknown"), "link unknown without companion data")
TrustAdvisorNetData.me = { events = {}, linked = true, verifiedCharacters = 2 }
assert(TA.Network:LinkText():find("linked, 2"), "battle.net link shown")
TA.HandleSlash("network")
TrustAdvisorNetData = { protocol = 1, generatedAt = 0, players = {} }
TA.Params:Set("consent.network", false)
print("  ok   welcome screen, companion detection (off/waiting/missing/ok), /ta network")

-- In-game feedback and error capture
local okFb, report = TA.Feedback:Submit("idea", "Please add a minimap button", true)
assert(okFb and report.id and report.diag and report.diag.addon == TA.version, "feedback saved with diagnostics")
local diagText = table.concat(TA.Feedback:DiagnosticsText(), "\n")
assert(not diagText:find("Tanky") and not diagText:find("Leafy"), "diagnostics never include player names")
assert(TA.Feedback:StatusText(report):find("Waiting"), "waiting until the companion sends it")
TrustAdvisorNetData.feedback = { [report.id] = { status = "planned", reply = "Coming in 0.4" } }
local st, reply = TA.Feedback:StatusText(report)
assert(st:find("Planned") and reply == "Coming in 0.4", "status and reply shown in game")
TrustAdvisorNetData.feedback = nil
TA.UI.ShowFeedback("bug")
TA.HandleSlash("feedback")
-- an error inside a Trust Advisor handler is recorded once (deduplicated) and offers a report
local toasts = 0
local origToast = TA.UI.Toast
TA.UI.Toast = function(t) toasts = toasts + 1; assert(t.text:find("hit an error")) end
TA:On("TA_SIM_BOOM", function() error("boom from a test handler") end)
fire("TA_SIM_BOOM"); fire("TA_SIM_BOOM")
advance(5)
local found
for _, e in ipairs(TA.db.errors) do if e.msg:find("boom from a test handler") then found = e end end
assert(found and found.count == 2, "error recorded and deduplicated")
assert(toasts == 1, "one report prompt per distinct error")
TA.UI.Toast = origToast
assert(table.concat(TA.Feedback:DiagnosticsText(), "\n"):find("boom"), "recent errors attached to diagnostics")
for i = #errors, 1, -1 do if tostring(errors[i]):find("boom from a test handler") then table.remove(errors, i) end end -- the deliberate one
print("  ok   in-game feedback (diagnostics without names, status/reply), error capture + one-click report prompt")

-- Ledger import (GDKP) parsing
local rows = TA.Trade.ParseLedger("Tanky 1,500g\nLeafy: 200\n|cffffffffJosé|r - 75.5 gold\njunk line")
assert(#rows == 3 and rows[1].gold == 1500 and rows[2].name == "Leafy" and rows[3].gold == 75.5, "ledger parse")
local msg = TA.Trade:ImportLedger("Tanky 100\nNobody 5", "owedToMe")
assert(msg:find("Imported 1") and msg:find("Nobody"), "ledger import skips unknown players: " .. msg)
print("  ok   ledger import (GDKP) parses and skips unknown players")

-- Crafted item gift: Tanky hands me an item he made
C_TooltipInfo = { GetTradeTargetItem = function(i) if i == 1 then return { lines = { { leftText = "<Made by Tanky>" } } } end end,
  GetTradePlayerItem = function() end }
ITEM_CREATED_BY = "<Made by %s>"
GetTargetTradeMoney = function() return 0 end
GetTradePlayerItemInfo = function() end
units.npc = { guid = "Player-1-0000000A", name = "Tanky", class = "WARRIOR", level = 38 }
fire("TRADE_SHOW"); fire("TRADE_TARGET_ITEM_CHANGED"); fire("UI_INFO_MESSAGE", 0, "Trade complete.")
TA.Dimensions.Invalidate()
local crafts = TA.Dimensions.Profile("Player-1-0000000A").dims.craft.items
assert(crafts[#crafts].label:find("crafted item") and crafts[#crafts].mult == 2, "free crafted gift counted at-cost x2")
print("  ok   crafted item gift detected from tooltip, free = x2")

-- Network (Phase 3): outbox built at logout with published parameters only
TA.Params:Set("finish.lootLeaveWeight", 9) -- a local edit must NOT leak into network reports
TA.Params:Set("consent.network", true)
fire("PLAYER_LOGOUT")
local outbox = TA.db.net.outbox
assert(outbox and #outbox.reports > 0, "network outbox built")
local sawLeafyNeg = false
for _, r in ipairs(outbox.reports) do
  assert(r.d ~= "pay" and r.d ~= "attend", "human-declared dimensions never uploaded")
  assert(r.s ~= TA.playerGUID, "no reports about yourself")
  if r.s == "Player-1-0000000B" and r.d == "finish" and r.x == 0 then sawLeafyNeg = true; assert(r.m == 3, "published weight, not local edit") end
end
assert(sawLeafyNeg, "Leafy's loot-and-leave reported")
assert(#outbox.presence >= 1 and #outbox.presence[1].m == 3, "group history uploaded with all 3 members")
print(string.format("  ok   network outbox: %d reports, published parameters only", #outbox.reports))

-- optional: dump SavedVariables for the cross-language end-to-end test
if os.getenv("TA_DUMP_SV") then
  local function ser(v, ind)
    ind = ind or ""
    local t = type(v)
    if t == "string" then return string.format("%q", v) end
    if t == "number" or t == "boolean" then return tostring(v) end
    if t ~= "table" then return "nil" end
    local parts = { "{\n" }
    for k, val in pairs(v) do
      local key = type(k) == "number" and ("[" .. k .. "]") or ("[" .. string.format("%q", tostring(k)) .. "]")
      parts[#parts + 1] = ind .. "\t" .. key .. " = " .. ser(val, ind .. "\t") .. ",\n"
    end
    parts[#parts + 1] = ind .. "}"
    return table.concat(parts)
  end
  local f = assert(io.open(os.getenv("TA_DUMP_SV"), "w"))
  f:write("\nTrustAdvisorDB = " .. ser(TrustAdvisorDB) .. "\n")
  f:close()
  print("  dumped SavedVariables to " .. os.getenv("TA_DUMP_SV"))
end

-- optional: load companion-written NetData and check the network view
if os.getenv("TA_NETDATA") then
  dofile(os.getenv("TA_NETDATA"))
  local np = TA.Network:Profile("Player-1-0000000B")
  assert(np, "network data present for Leafy")
  print("  network view for Leafy: finish " .. np.dims.finish.band .. string.format(" (S=%.3f, N=%.1f, %d incidents)", np.dims.finish.score, np.dims.finish.evidence, np.incidents))
  -- the verified negative (2 witnesses, 2 guilds, weight 3) is counted and pulls the score below band.concern;
  -- the band itself is Unknown until evidence reaches conf.minEvidence (decay makes N just under 3 here)
  assert(#np.dims.finish.items == 1 and np.dims.finish.items[1].x == 0, "verified multi-witness negative counted")
  assert(np.dims.finish.score < 0.5, "score in Concern territory")
  TA.UI:OpenPlayer("Player-1-0000000B")
  TA.UI.SelectTab("profile")
  TA.UI.views.transparency.sub = "Network"; TA.UI.views.transparency:Refresh()
  print("  ok   network view rendered in card, profile and Transparency")
end

TA:WipeEverything()
assert(TA.Log.count == 0, "delete everything")
print("  ok   delete everything")

if #errors > 0 then
  print("\nERRORS:")
  for _, e in ipairs(errors) do print("  " .. e) end
  os.exit(1)
end
print("\nsimulation passed")
