-- Loads every addon file in TOC order against a mock WoW API, then replays a
-- dungeon run (event fixture) and drives the UI and slash commands.
-- Catches load errors, nil-calls and handler errors before going in game.
--   luajit Tests/test_ingame_sim.lua
local root = (arg and arg[0] or ""):match("^(.*)Tests/") or "./"
local errors = {}

-------------------------------------------------------------------------------
-- Mock WoW API
-------------------------------------------------------------------------------
-- the WoW client has no math.randomseed, and GetItemInfo lives in C_Item
math.randomseed = nil
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
  if unit ~= "npc" and units[unit] then return units[unit] end
  local i = tonumber((unit or ""):match("^party(%d)$"))
  if i then return party[i] end
  if unit == "NPC" then return units.npc end
  if unit == "mouseover" then return party[1] end
end
function UnitGUID(u) local x = U(u); return x and x.guid end
function UnitName(u) local x = U(u); return x and x.name, x and x.realm end
function UnitClass(u) local x = U(u); return x and x.class, x and x.class end
function UnitRace(u) local x = U(u); if u == "player" then return "Undead", "Scourge" elseif x then return x.race or "Orc", x.race or "Orc" end end
function UnitFactionGroup(u) local x = U(u); if x then return x.faction or "Horde", x.faction or "Horde" end end
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
C_Item = { GetItemInfo = function(link) return "Item", link, 3 end }
function GetChannelName() return 0 end
-- /played: the game answers RequestTimePlayed with TIME_PLAYED_MSG and prints a chat line
local playedShown, partyChat, playedTotal = 0, {}, 360000
function ChatFrame_DisplayTimePlayed() playedShown = playedShown + 1 end
function SendChatMessage(msg, channel) table.insert(partyChat, { msg = msg, channel = channel }) end
function UnitIsGroupLeader(u) return u == "player" end
local fireEvent
function RequestTimePlayed() C_Timer.After(1, function() fireEvent("TIME_PLAYED_MSG", playedTotal, 3600) end) end

-------------------------------------------------------------------------------
-- Load addon files in TOC order with a shared namespace
-------------------------------------------------------------------------------
local ns = {}
local files = {}
for line in io.lines(root .. "ForeverRelationships.toc") do
  if not line:find("^##") and line:find("%.lua$") then files[#files + 1] = (line:gsub("\\", "/")) end
end
for _, f in ipairs(files) do
  local chunk, err = loadfile(root .. f)
  if not chunk then errors[#errors + 1] = "load " .. f .. ": " .. err
  else
    local ok, e = pcall(chunk, "ForeverRelationships", ns)
    if not ok then errors[#errors + 1] = "run " .. f .. ": " .. tostring(e) end
  end
end
local FR = ns
local mainFrame = _G.ForeverRelationshipsEventFrame
local function fire(event, ...)
  local fn = mainFrame._scripts.OnEvent
  fn(mainFrame, event, ...)
  -- the chat frames show /played after the addon saw the event
  if event == "TIME_PLAYED_MSG" then ChatFrame_DisplayTimePlayed(...) end
end
fireEvent = fire

-- surface any internal handler errors
local origDebug = FR.Debug
FR.Debug = function(...)
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
print("Forever Relationships in-game simulation")
fire("ADDON_LOADED", "ForeverRelationships")
fire("PLAYER_LOGIN")
advance(1)

-- form a party of 3
party = {
  { guid = "Player-1-0000000A", name = "Tanky", class = "WARRIOR", level = 38 },
  { guid = "Player-1-0000000B", name = "Leafy", class = "PRIEST", level = 29 },
}
fire("GROUP_ROSTER_UPDATE"); advance(1)
assert(FR.Sessions:Active(), "session should start")
-- /played was asked silently after login
advance(10)
assert(FR.Played:Hours() == 100 and playedShown == 0, "/played recorded silently: " .. tostring(FR.Played:Hours()) .. " shown " .. playedShown)
fire("TIME_PLAYED_MSG", playedTotal + 60, 3660)   -- the player types /played: shown as usual
assert(playedShown == 1, "a typed /played is still shown")
FR.db.playedChars["Player-1-000000AA"] = { name = "Alt-Forever", total = 7200, t = clock - 86400 }
local accTotal, accN = FR.Played:Account()
assert(accN == 2 and accTotal >= playedTotal + 60 + 7200, "account /played sums every character")
print("  ok   /played: asked silently at login, this character + all characters")
-- party welcome: one line, after the leader's short delay
assert(#partyChat == 1 and partyChat[1].channel == "PARTY" and partyChat[1].msg:find("Forever Relationships addon"), "party welcome when the party forms")
-- peer HELLO & quest from Tanky (Forever Relationships user)
fire("CHAT_MSG_ADDON", "ForeverRel", "1|HELLO|Player-1-0000000A;1;Q,A,E,P", "PARTY", "Tanky")
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

assert(not FR.Sessions:Active(), "session should end")
local counts = {}
for _, ev in ipairs(FR.Log:All()) do counts[ev.signal] = (counts[ev.signal] or 0) + 1 end
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
scan(ForeverRelationshipsDB); scan(ForeverRelationshipsCharDB)
print("  ok   no chat text in SavedVariables")


-- Relationship (Information + Knowledge): facts and sums only, no scores
local rt = FR.Rel:Compute("Player-1-0000000A")
assert(rt.sessions == 1 and rt.kills == 2 and rt.dungeons == 1, "Tanky: 1 session, 2 kills together, dungeon completed together")
assert(rt.seconds > 2400 and rt.days == 1 and rt.trades == 1 and rt.craftsByThem == 1, "time together, trade with enchant by them")
assert(rt.quests == 0 and rt.levelGap == 8, "level gap: Tanky 8 above")
local rl = FR.Rel:Compute("Player-1-0000000B")
assert(rl.kills == 1 and rl.dungeons == 0 and rl.loot == 1 and rl.quests == 1, "Leafy left before the last boss: 1 kill together, no completion, 1 loot, 1 quest")
local circle = FR.Rel:Circle()
assert(circle[1].guid == "Player-1-0000000A" and circle[1].rank == 1, "circle sorted by time together")
local lines = FR.UI.TooltipLines("Player-1-0000000A")
assert(#lines == 6 and lines[1][1] == "Time together", "tooltip shows the 6 default items")
FR.UI.SetTooltipFields({ "kills", "zones" })
lines = FR.UI.TooltipLines("Player-1-0000000A")
assert(#lines == 2 and lines[1][2] == "2", "tooltip follows the player's choice")
FR.UI.SetTooltipFields(FR.Rel.DEFAULT_TOOLTIP)
assert(FR.UI.TooltipLines("Player-1-DEADBEEF") == nil, "nothing for strangers")
local mine = FR.Rel:Mine()
assert(mine.people == 2 and mine.dungeons == 1 and mine.kills == 2, "my own numbers")
print("  ok   relationship stats: time, kills, completions, loot, quests, trades, level gap, circle, tooltip choice")

-- no opinions, no scores anywhere
for _, ev in ipairs(FR.Log:All()) do
  assert(ev.signal ~= "endorse" and ev.signal ~= "obligation" and ev.signal ~= "lootNeed", "no v1 opinion/manual events")
end
assert(FR.Dimensions == nil and FR.Engine == nil and FR.Endorse == nil, "scoring modules removed")
print("  ok   no scores, no opinions, no manual inputs")

-- UI and slash commands
FR.UI:Open("circle")
for _, t in ipairs(FR.UI.TABS) do FR.UI.SelectTab(t.key) end
FR.UI:OpenPlayer("Player-1-0000000A")
FR.UI.ShowSettings()
for _, cmd in ipairs({ "help", "player Tanky", "status", "privacy", "cloud", "welcome", "invisible", "invisible", "export", "debug", "debug" }) do
  FR.HandleSlash(cmd)
end
-- malformed / spoofed peer messages are dropped
fire("CHAT_MSG_ADDON", "ForeverRel", "garbage", "PARTY", "Tanky")
fire("CHAT_MSG_ADDON", "ForeverRel", "1|QUEST|Player-1-DEADBEEF;5", "WHISPER", "Stranger")
advance(10)
print(string.format("  ok   UI tabs, settings and commands; %d malformed/spoofed messages dropped", FR.Protocol.dropped or 0))

-- Welcome + companion detection (cloud layers)
assert(FR.db.welcomed == "v2", "v2 welcome shown on first login")
assert(FR.Cloud:CompanionStatus() == "off", "all cloud layers off by default")
FR.Params:Set("consent.backup", true)
assert(FR.Cloud:CompanionStatus() == "waiting", "just turned on: waiting for first sync")
FR.loginAt = FR.Now() + 1
assert(FR.Cloud:CompanionStatus() == "missing", "companion missing after relog")
ForeverRelationshipsNetData = { protocol = 2, players = {}, companion = { version = "0.4.0", syncedAt = FR.Now() + 2 }, me = { linked = true, verifiedCharacters = 2 } }
assert(FR.Cloud:CompanionStatus() == "ok" and FR.Cloud:CompanionVersion() == "0.4.0", "companion syncing")
assert(FR.Cloud:LinkText():find("linked, 2"), "battle.net link shown")
ForeverRelationshipsNetData = { protocol = 2 }
FR.Params:Set("consent.backup", false)
for _, k in ipairs({ "backup", "profile", "community", "recommend" }) do FR.Params:Set("consent." .. k, true) end
fire("PLAYER_LOGOUT")
local ob = FR.db.cloud.outbox
assert(ob and ob.consents.backup and ob.consents.recommend and ob.me and ob.profile and ob.community, "logout writes the outbox for the companion")
assert(FR.db.cloud.uploaderId and #FR.db.cloud.uploaderId == 32, "uploader id created without math.randomseed")
for _, k in ipairs({ "backup", "profile", "community", "recommend" }) do FR.Params:Set("consent." .. k, false) end
print("  ok   welcome v2, companion detection (off/waiting/missing/ok), outbox written at logout")

-- Warlock summons, both directions
party = { { guid = "Player-1-0000000A", name = "Tanky", class = "WARRIOR", level = 38 } }
fire("GROUP_ROSTER_UPDATE"); advance(1)
C_SummonInfo = { GetSummonConfirmSummoner = function() return "Tanky" end }
fire("CONFIRM_SUMMON")                                                     -- Tanky summons me
fire("UNIT_SPELLCAST_SENT", "player", "Tanky", "cast-summon-1", 698)        -- I summon Tanky (group member)
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-summon-1", 698)
local gotIn, gotOut = false, false
for _, ev in ipairs(FR.Log:All()) do
  if ev.signal == "generosity" and ev.details.kind == "summon" then
    if ev.subjectGUID == "Player-1-0000000A" then gotIn = true end
    if ev.subjectGUID == FR.playerGUID and ev.details.recipientGUID == "Player-1-0000000A" then gotOut = true end
  end
end
assert(gotIn, "summon received from a warlock is credited to them")
assert(gotOut, "my own summon of a group member is credited to me")
-- a buff on a group member is NOT generosity (only strangers count)
fire("UNIT_SPELLCAST_SENT", "player", "Tanky", "cast-buff-1", 1459)
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-buff-1", 1459)
for _, ev in ipairs(FR.Log:All()) do
  assert(not (ev.signal == "generosity" and ev.details.kind == "buff" and ev.details.recipientGUID == "Player-1-0000000A"), "group buff not counted")
end
-- developer probe records group casts and summon offers
FR.HandleSlash("probe on")
fire("UNIT_SPELLCAST_CHANNEL_START", "party1", "c-1", 698)
fire("UNIT_SPELLCAST_SUCCEEDED", "party1", "c-2", 7720)
fire("UNIT_SPELLCAST_SUCCEEDED", "target", "c-3", 1)          -- not a group unit: ignored
fire("CONFIRM_SUMMON")
FR.HandleSlash("probe off")
fire("UNIT_SPELLCAST_SUCCEEDED", "party1", "c-4", 7720)       -- probe off: ignored
local probeText = table.concat(FR.Probe:Text(), "\n")
assert(#FR.db.probe.rows == 3 and probeText:find("698") and probeText:find("7720") and probeText:find("SUMMON OFFER from Tanky"), "probe rows: " .. probeText)
FR.HandleSlash("probe show"); FR.HandleSlash("probe clear")
assert(#FR.db.probe.rows == 0, "probe cleared")
party = {}; fire("GROUP_LEFT"); advance(5)
print("  ok   developer probe (/fr probe) records group casts and summon offers")
print("  ok   warlock summons: received and given (inside the group); group buffs still excluded")

-- In-game feedback and error capture
local okFb, report = FR.Feedback:Submit("idea", "Please add a minimap button", true)
assert(okFb and report.id and report.diag and report.diag.addon == FR.version, "feedback saved with diagnostics")
local diagText = table.concat(FR.Feedback:DiagnosticsText(), "\n")
assert(not diagText:find("Tanky") and not diagText:find("Leafy"), "diagnostics never include player names")
assert(FR.Feedback:StatusText(report):find("Waiting"), "waiting until the companion sends it")
assert(FR.Feedback:DeliveryNote():find("companion app runs here"), "explains delivery without companion")
ForeverRelationshipsNetData.companion = { version = "0.4.0", syncedAt = FR.Now() }
assert(FR.Feedback:DeliveryNote():find("Sent automatically"), "companion seen (even with every cloud layer off)")
ForeverRelationshipsNetData.feedback = { [report.id] = { status = "planned", reply = "Coming in 0.4" } }
local st, reply = FR.Feedback:StatusText(report)
assert(st:find("Planned") and reply == "Coming in 0.4", "status and reply shown in game")
ForeverRelationshipsNetData.feedback = nil
FR.UI.ShowFeedback("bug")
FR.HandleSlash("feedback")
-- an error inside a Forever Relationships handler is recorded once (deduplicated) and offers a report
local toasts = 0
local origToast = FR.UI.Toast
FR.UI.Toast = function(t) toasts = toasts + 1; assert(t.text:find("hit an error")) end
FR:On("FR_SIM_BOOM", function() error("boom from a test handler") end)
fire("FR_SIM_BOOM"); fire("FR_SIM_BOOM")
advance(5)
local found
for _, e in ipairs(FR.db.errors) do if e.msg:find("boom from a test handler") then found = e end end
assert(found and found.count == 2, "error recorded and deduplicated")
assert(toasts == 1, "one report prompt per distinct error")
FR.UI.Toast = origToast
assert(table.concat(FR.Feedback:DiagnosticsText(), "\n"):find("boom"), "recent errors attached to diagnostics")
for i = #errors, 1, -1 do if tostring(errors[i]):find("boom from a test handler") then table.remove(errors, i) end end -- the deliberate one
print("  ok   in-game feedback (diagnostics without names, status/reply), error capture + one-click report prompt")

-- Crafted item gift: Tanky hands me an item he made
C_TooltipInfo = { GetTradeTargetItem = function(i) if i == 1 then return { lines = { { leftText = "<Made by Tanky>" } } } end end,
  GetTradePlayerItem = function() end }
ITEM_CREATED_BY = "<Made by %s>"
GetTargetTradeMoney = function() return 0 end
GetTradePlayerItemInfo = function() end
units.npc = { guid = "Player-1-0000000A", name = "Tanky", class = "WARRIOR", level = 38 }
local before = FR.Rel:Compute("Player-1-0000000A").craftsByThem
fire("TRADE_SHOW"); fire("TRADE_TARGET_ITEM_CHANGED"); fire("UI_INFO_MESSAGE", 0, "Trade complete.")
FR.Rel.Invalidate()
assert(FR.Rel:Compute("Player-1-0000000A").craftsByThem == before + 1, "crafted item gift counted")
print("  ok   crafted item gift detected from the tooltip")

-- a later party with Stabby: a new member joins and is welcomed; next time another member with the addon welcomes first
party = { { guid = "Player-1-0000000C", name = "Stabby", class = "ROGUE", level = 31 } }
fire("GROUP_ROSTER_UPDATE"); advance(30)
assert(#partyChat == 2, "new party welcomed: " .. #partyChat)
table.insert(party, { guid = "Player-1-0000000F", name = "Magey", class = "MAGE", level = 31 })
fire("GROUP_ROSTER_UPDATE"); advance(30)
assert(#partyChat == 3, "joiner welcomed: " .. #partyChat)
table.insert(party, { guid = "Player-1-0000000D", name = "Healy", class = "PRIEST", level = 30 })
fire("GROUP_ROSTER_UPDATE"); advance(1)
fire("CHAT_MSG_ADDON", "ForeverRel", "1|WELCOME|Player-1-0000000C", "PARTY", "Stabby")
advance(30)
assert(#partyChat == 3, "no duplicate when another member already welcomed")
FR.Params:Set("announce.party", false)
table.insert(party, { guid = "Player-1-0000000E", name = "Shieldy", class = "WARRIOR", level = 30 })
fire("GROUP_ROSTER_UPDATE"); advance(30)
assert(#partyChat == 3, "setting off: no welcome")
FR.Params:Set("announce.party", true)
party = {}
fire("GROUP_LEFT"); advance(5)
print("  ok   party welcome: on forming and on join, one poster, setting respected")

-- Cloud outbox: nothing without consent; with consent only what was chosen
fire("PLAYER_LOGOUT")
local ob = FR.db.cloud.outbox
assert(ob and not ob.profile and not ob.community and not ob.me, "no consent: nothing to send")
FR.Params:Set("consent.profile", true)
FR.Cloud:State().profileItems.dungeons = true
FR.Cloud:State().profileItems.hours = true
FR.Cloud:State().profileItems.played = true
FR.Params:Set("consent.community", true)
fire("PLAYER_LOGOUT")
ob = FR.db.cloud.outbox
assert(ob.profile.dungeons == 1 and ob.profile.hours ~= nil and ob.profile.kills == nil, "profile: only ticked items")
assert(type(ob.profile.played) == "string" and ob.profile.played:find("^1%d%dh %d+m$"), "profile: /played of this character only, hours and minutes: " .. tostring(ob.profile.played))
-- their /played, from their public profile, as a tooltip / Relationship field
local savedProfiles = ForeverRelationshipsNetData
ForeverRelationshipsNetData = { protocol = 2, profiles = { ["Player-1-0000000A"] = { items = { { key = "played", label = "/played on this character", value = "321h 7m" } } } } }
FR.Rel.Invalidate()
assert(FR.Rel.FIELD_BY_KEY.played.value(FR.Rel:Compute("Player-1-0000000A")) == "321h 7m", "their /played shown")
assert(FR.Rel.FIELD_BY_KEY.played.value(FR.Rel:Compute("Player-1-0000000C")) == "not public", "no profile: not public")
FR.UI.SetTooltipFields({ "time", "played" })
local ttl = FR.UI.TooltipLines("Player-1-0000000A")
assert(ttl[2][1] == "Their /played" and ttl[2][2] == "321h 7m", "tooltip can show their /played")
FR.UI.SetTooltipFields(FR.Rel.DEFAULT_TOOLTIP)
ForeverRelationshipsNetData = savedProfiles
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

-- Population census (Community layer): characters seen nearby, no names
units.stranger = { guid = "Player-2-000000C1", name = "Elfy", realm = "Other Realm", class = "DRUID", level = 22, race = "NightElf", faction = "Alliance" }
units.target = { guid = "Player-1-000000C2", name = "Grunt", class = "ROGUE", level = 40, race = "Orc", faction = "Horde" }
fire("NAME_PLATE_UNIT_ADDED", "stranger")
fire("PLAYER_TARGET_CHANGED")
fire("PLAYER_LOGOUT")
ob = FR.db.cloud.outbox
local byG = {}
for _, c in ipairs(ob.census) do assert(c.name == nil, "census carries no names"); byG[c.g] = c end
local elf = byG["Player-2-000000C1"]
assert(elf and elf.r == "Night Elf" and elf.f == "Alliance" and elf.c == "Druid" and elf.l == 22, "nameplate sighting")
assert(byG["Player-1-000000C2"] and byG["Player-1-000000C2"].f == "Horde", "target sighting")
assert(byG[FR.playerGUID] and byG[FR.playerGUID].r == "Undead", "own character counted")
assert(ob.realms["2"] == "Other Realm" and ob.realms["1"] == "Forever", "realm names by id")
-- Population tab from the companion's NetData
local savedND = ForeverRelationshipsNetData
ForeverRelationshipsNetData = { protocol = 2, population = { updatedAt = FR.Now(), windowDays = 30,
  realms = { ["1"] = { name = "Forever", type = "pvp" } },
  types = { pvp = { Alliance = { total = 3, races = { Human = 2, Gnome = 1 } }, Horde = { total = 1, races = { Orc = 1 } } } } } }
assert(FR.Census:MyRealmType() == "pvp", "my realm type")
local sum = FR.Census:Summary("pvp", "all")
assert(sum.total == 4 and sum.alliance == 3 and sum.rows[1].race == "Human" and math.abs(sum.rows[1].pct - 50) < 0.01, "summary, both factions")
sum = FR.Census:Summary("pvp", "Horde")
assert(#sum.rows == 1 and sum.rows[1].pct == 100 and sum.total == 4, "Horde filter: % within the faction")
assert(FR.Census:Summary("pve", "all").total == 0, "no PvE data")
FR.HandleSlash("population")
FR.UI.SelectTab("population")
ForeverRelationshipsNetData = savedND
-- Community off: the local census is deleted
FR.Params:Set("consent.community", false)
assert(FR.db.census == nil, "census deleted when Community is turned off")
fire("NAME_PLATE_UNIT_ADDED", "stranger")
assert(FR.db.census == nil, "nothing collected while Community is off")
FR.Params:Set("consent.community", true)
fire("NAME_PLATE_UNIT_ADDED", "stranger")
fire("PLAYER_TARGET_CHANGED")
fire("PLAYER_LOGOUT")
print("  ok   population census: nameplates/target, no names, own character, realm ids; Population tab and filters")

-- optional: dump SavedVariables for the cross-language end-to-end test
if os.getenv("FR_DUMP_SV") then
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
  local f = assert(io.open(os.getenv("FR_DUMP_SV"), "w"))
  f:write("\nForeverRelationshipsDB = " .. ser(ForeverRelationshipsDB) .. "\n")
  f:close()
  print("  dumped SavedVariables to " .. os.getenv("FR_DUMP_SV"))
end

-- optional: load companion-written NetData and check profiles / suggestions
if os.getenv("FR_NETDATA") then
  dofile(os.getenv("FR_NETDATA"))
  local prof = FR.Cloud:Profile(os.getenv("FR_EXPECT_PROFILE") or "Player-1-0000000A")
  assert(prof and prof.items and #prof.items > 0, "public profile delivered")
  FR.UI:OpenPlayer("Player-1-0000000A")
  FR.UI.SelectTab("circle")
  print(string.format("  ok   NetData: public profile with %d item(s), %d suggestion(s)", #prof.items, #FR.Cloud:Suggestions()))
end

FR:WipeEverything()
assert(FR.Log.count == 0, "delete everything")
print("  ok   delete everything")

if #errors > 0 then
  print("\nERRORS:")
  for _, e in ipairs(errors) do print("  " .. e) end
  os.exit(1)
end
print("\nsimulation passed")
