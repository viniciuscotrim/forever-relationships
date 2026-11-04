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
function UnitRace(u) if u == "player" then return "Undead", "Scourge" elseif U(u) then return "Orc", "Orc" end end
function UnitFactionGroup(u) if U(u) then return "Horde", "Horde" end end
function GetRealmName() return "Forever" end
function GetLocale() return "ptBR" end
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


-- Relationship (Information + Knowledge): facts and sums only, no scores
local rt = TA.Rel:Compute("Player-1-0000000A")
assert(rt.sessions == 1 and rt.kills == 2 and rt.dungeons == 1, "Tanky: 1 session, 2 kills together, dungeon completed together")
assert(rt.seconds > 2400 and rt.days == 1 and rt.trades == 1 and rt.craftsByThem == 1, "time together, trade with enchant by them")
assert(rt.quests == 0 and rt.levelGap == 8, "level gap: Tanky 8 above")
local rl = TA.Rel:Compute("Player-1-0000000B")
assert(rl.kills == 1 and rl.dungeons == 0 and rl.loot == 1 and rl.quests == 1, "Leafy left before the last boss: 1 kill together, no completion, 1 loot, 1 quest")
local circle = TA.Rel:Circle()
assert(circle[1].guid == "Player-1-0000000A" and circle[1].rank == 1, "circle sorted by time together")
local lines = TA.UI.TooltipLines("Player-1-0000000A")
assert(#lines == 6 and lines[1][1] == "Time together", "tooltip shows the 6 default items")
TA.UI.SetTooltipFields({ "kills", "zones" })
lines = TA.UI.TooltipLines("Player-1-0000000A")
assert(#lines == 2 and lines[1][2] == "2", "tooltip follows the player's choice")
TA.UI.SetTooltipFields(TA.Rel.DEFAULT_TOOLTIP)
assert(TA.UI.TooltipLines("Player-1-DEADBEEF") == nil, "nothing for strangers")
local mine = TA.Rel:Mine()
assert(mine.people == 2 and mine.dungeons == 1 and mine.kills == 2, "my own numbers")
print("  ok   relationship stats: time, kills, completions, loot, quests, trades, level gap, circle, tooltip choice")

-- no opinions, no scores anywhere
for _, ev in ipairs(TA.Log:All()) do
  assert(ev.signal ~= "endorse" and ev.signal ~= "obligation" and ev.signal ~= "lootNeed", "no v1 opinion/manual events")
end
assert(TA.Dimensions == nil and TA.Engine == nil and TA.Endorse == nil, "scoring modules removed")
print("  ok   no scores, no opinions, no manual inputs")

-- UI and slash commands
TA.UI:Open("circle")
for _, t in ipairs(TA.UI.TABS) do TA.UI.SelectTab(t.key) end
TA.UI:OpenPlayer("Player-1-0000000A")
TA.UI.ShowSettings()
for _, cmd in ipairs({ "help", "player Tanky", "status", "privacy", "cloud", "welcome", "invisible", "invisible", "export", "debug", "debug" }) do
  TA.HandleSlash(cmd)
end
-- malformed / spoofed peer messages are dropped
fire("CHAT_MSG_ADDON", "TrustAdv", "garbage", "PARTY", "Tanky")
fire("CHAT_MSG_ADDON", "TrustAdv", "1|QUEST|Player-1-DEADBEEF;5", "WHISPER", "Stranger")
advance(10)
print(string.format("  ok   UI tabs, settings and commands; %d malformed/spoofed messages dropped", TA.Protocol.dropped or 0))

-- Welcome + companion detection (cloud layers)
assert(TA.db.welcomed == "v2", "v2 welcome shown on first login")
assert(TA.Cloud:CompanionStatus() == "off", "all cloud layers off by default")
TA.Params:Set("consent.backup", true)
assert(TA.Cloud:CompanionStatus() == "waiting", "just turned on: waiting for first sync")
TA.loginAt = TA.Now() + 1
assert(TA.Cloud:CompanionStatus() == "missing", "companion missing after relog")
TrustAdvisorNetData = { protocol = 2, players = {}, companion = { version = "0.4.0", syncedAt = TA.Now() + 2 }, me = { linked = true, verifiedCharacters = 2 } }
assert(TA.Cloud:CompanionStatus() == "ok" and TA.Cloud:CompanionVersion() == "0.4.0", "companion syncing")
assert(TA.Cloud:LinkText():find("linked, 2"), "battle.net link shown")
TrustAdvisorNetData = { protocol = 2 }
TA.Params:Set("consent.backup", false)
print("  ok   welcome v2 and companion detection (off/waiting/missing/ok)")

-- Warlock summons, both directions
party = { { guid = "Player-1-0000000A", name = "Tanky", class = "WARRIOR", level = 38 } }
fire("GROUP_ROSTER_UPDATE"); advance(1)
C_SummonInfo = { GetSummonConfirmSummoner = function() return "Tanky" end }
fire("CONFIRM_SUMMON")                                                     -- Tanky summons me
fire("UNIT_SPELLCAST_SENT", "player", "Tanky", "cast-summon-1", 698)        -- I summon Tanky (group member)
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-summon-1", 698)
local gotIn, gotOut = false, false
for _, ev in ipairs(TA.Log:All()) do
  if ev.signal == "generosity" and ev.details.kind == "summon" then
    if ev.subjectGUID == "Player-1-0000000A" then gotIn = true end
    if ev.subjectGUID == TA.playerGUID and ev.details.recipientGUID == "Player-1-0000000A" then gotOut = true end
  end
end
assert(gotIn, "summon received from a warlock is credited to them")
assert(gotOut, "my own summon of a group member is credited to me")
-- a buff on a group member is NOT generosity (only strangers count)
fire("UNIT_SPELLCAST_SENT", "player", "Tanky", "cast-buff-1", 1459)
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-buff-1", 1459)
for _, ev in ipairs(TA.Log:All()) do
  assert(not (ev.signal == "generosity" and ev.details.kind == "buff" and ev.details.recipientGUID == "Player-1-0000000A"), "group buff not counted")
end
-- developer probe records group casts and summon offers
TA.HandleSlash("probe on")
fire("UNIT_SPELLCAST_CHANNEL_START", "party1", "c-1", 698)
fire("UNIT_SPELLCAST_SUCCEEDED", "party1", "c-2", 7720)
fire("UNIT_SPELLCAST_SUCCEEDED", "target", "c-3", 1)          -- not a group unit: ignored
fire("CONFIRM_SUMMON")
TA.HandleSlash("probe off")
fire("UNIT_SPELLCAST_SUCCEEDED", "party1", "c-4", 7720)       -- probe off: ignored
local probeText = table.concat(TA.Probe:Text(), "\n")
assert(#TA.db.probe.rows == 3 and probeText:find("698") and probeText:find("7720") and probeText:find("SUMMON OFFER from Tanky"), "probe rows: " .. probeText)
TA.HandleSlash("probe show"); TA.HandleSlash("probe clear")
assert(#TA.db.probe.rows == 0, "probe cleared")
party = {}; fire("GROUP_LEFT"); advance(5)
print("  ok   developer probe (/ta probe) records group casts and summon offers")
print("  ok   warlock summons: received and given (inside the group); group buffs still excluded")

-- In-game feedback and error capture
local okFb, report = TA.Feedback:Submit("idea", "Please add a minimap button", true)
assert(okFb and report.id and report.diag and report.diag.addon == TA.version, "feedback saved with diagnostics")
local diagText = table.concat(TA.Feedback:DiagnosticsText(), "\n")
assert(not diagText:find("Tanky") and not diagText:find("Leafy"), "diagnostics never include player names")
assert(TA.Feedback:StatusText(report):find("Waiting"), "waiting until the companion sends it")
assert(TA.Feedback:DeliveryNote():find("companion app runs here"), "explains delivery without companion")
TrustAdvisorNetData.companion = { version = "0.4.0", syncedAt = TA.Now() }
assert(TA.Feedback:DeliveryNote():find("Sent automatically"), "companion seen (even with every cloud layer off)")
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

-- Crafted item gift: Tanky hands me an item he made
C_TooltipInfo = { GetTradeTargetItem = function(i) if i == 1 then return { lines = { { leftText = "<Made by Tanky>" } } } end end,
  GetTradePlayerItem = function() end }
ITEM_CREATED_BY = "<Made by %s>"
GetTargetTradeMoney = function() return 0 end
GetTradePlayerItemInfo = function() end
units.npc = { guid = "Player-1-0000000A", name = "Tanky", class = "WARRIOR", level = 38 }
local before = TA.Rel:Compute("Player-1-0000000A").craftsByThem
fire("TRADE_SHOW"); fire("TRADE_TARGET_ITEM_CHANGED"); fire("UI_INFO_MESSAGE", 0, "Trade complete.")
TA.Rel.Invalidate()
assert(TA.Rel:Compute("Player-1-0000000A").craftsByThem == before + 1, "crafted item gift counted")
print("  ok   crafted item gift detected from the tooltip")

-- Cloud outbox: nothing without consent; with consent only what was chosen
fire("PLAYER_LOGOUT")
local ob = TA.db.cloud.outbox
assert(ob and not ob.profile and not ob.community and not ob.me, "no consent: nothing to send")
TA.Params:Set("consent.profile", true)
TA.Cloud:State().profileItems.dungeons = true
TA.Cloud:State().profileItems.hours = true
TA.Params:Set("consent.community", true)
fire("PLAYER_LOGOUT")
ob = TA.db.cloud.outbox
assert(ob.profile.dungeons == 1 and ob.profile.hours ~= nil and ob.profile.kills == nil, "profile: only ticked items")
assert(ob.me.race == "Undead" and ob.me.faction == "Horde" and ob.me.class == "Priest" and ob.me.locale == "ptBR", "own character")
local sawDungeon = false
for _, sess in ipairs(ob.community) do
  for _, m in ipairs(sess.m) do assert(m.name == nil, "community members carry no names") end
  if #sess.m == 3 and sess.type == "dungeon" then
    sawDungeon = true
    for _, m in ipairs(sess.m) do if m.g == "Player-1-0000000A" then assert(m.race == "Orc" and m.faction == "Horde" and m.class == "Warrior", "member attributes") end end
  end
end
assert(sawDungeon, "community includes the dungeon session with its 3 members")
assert(#ob.lookups >= 2, "profile lookups for players in my circle")
print(string.format("  ok   cloud outbox: consent-gated profile (%d items) and community (%d sessions, no names)",
  (function() local n = 0 for _ in pairs(ob.profile) do n = n + 1 end return n end)(), #ob.community))

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

-- optional: load companion-written NetData and check profiles / suggestions
if os.getenv("TA_NETDATA") then
  dofile(os.getenv("TA_NETDATA"))
  local prof = TA.Cloud:Profile(os.getenv("TA_EXPECT_PROFILE") or "Player-1-0000000A")
  assert(prof and prof.items and #prof.items > 0, "public profile delivered")
  TA.UI:OpenPlayer("Player-1-0000000A")
  TA.UI.SelectTab("circle")
  print(string.format("  ok   NetData: public profile with %d item(s), %d suggestion(s)", #prof.items, #TA.Cloud:Suggestions()))
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
