-- Network (GDD Phase 3), addon side.
-- Addons cannot reach the internet. The flow is:
--   1. At logout/reload (SavedVariables write), with consent.network ON, this
--      module writes witness REPORTS into TrustAdvisorDB.net.
--   2. The companion app uploads them, downloads the verified network view,
--      and writes Network/NetData.lua, loaded on the next /reload.
-- Reports are computed with the PUBLISHED default parameters (never your local
-- overrides), contain only game-witnessed facts, and never include private data.
local _, TA = ...

local Net = {}
TA.Network = Net

TA:RegisterCapture("network", "Network companion data", "Network/NetData.lua (companion app)")

-- Dimensions that may enter the network view. Paying (human-declared debts)
-- and Showing up (human signup lists) never leave your client.
Net.ELIGIBLE = { finish = true, ready = true, loot = true, carry = true, generosity = true,
  teach = true, craft = true, help = true, hc = true, endorse = true }
-- Shared incidents are seen by several witnesses (matched across reports).
-- Personal ones (a buff you received, a trade you made) belong to one witness.
Net.SHARED = { finish = true, ready = true, loot = true, carry = true, teach = true, help = true, hc = true }

local MAX_REPORTS = 20000
local STALE = 7 * 86400
local YEAR = 365 * 86400

local function RandomId()
  local t = {}
  math.randomseed(math.floor((GetTime and GetTime() or 0) * 1000) + TA.Now())
  for i = 1, 32 do t[i] = string.format("%x", math.random(0, 15)) end
  return table.concat(t)
end

function Net:State()
  local db = TA.db
  db.net = db.net or {}
  local n = db.net
  n.uploaderId = n.uploaderId or RandomId()
  n.characters = n.characters or {}
  n.disputes = n.disputes or {}
  return n
end

function Net:Enabled() return TA.Params:Get("consent.network") end

-------------------------------------------------------------------------------
-- Building reports
-------------------------------------------------------------------------------
local function Kind(dim, item, witness)
  local k = string.format("%s:%.2f:%.2f", dim, item.x or 1, item.mult or 1)
  if dim == "endorse" then return k .. ":" .. (item.endorser or witness) end
  if not Net.SHARED[dim] then return k .. ":" .. witness end
  return k
end

function Net:BuildReports(now)
  now = now or TA.Now()
  local P = TA.Params:DefaultSnapshot()   -- locked protocol parameters
  local me = TA.playerGUID
  local myGuild = TA.SafeCall(GetGuildInfo, "player") or ""
  local reports = {}
  for guid, p in pairs(TA.db.players) do
    if guid ~= me then
      for dim in pairs(Net.ELIGIBLE) do
        local items = TA.Dimensions.collectors[dim](guid, P, now)
        for _, it in ipairs(items) do
          local ev = it.eventId and TA.Log.byId and TA.Log.byId[it.eventId]
          local okSource = true
          if dim == "endorse" then
            -- only endorsements YOU gave; others upload their own
            okSource = ev and ev.source == "human" and ev.details.endorserGUID == me
          end
          if not it.skip and okSource and now - (it.it or it.t) <= YEAR and #reports < MAX_REPORTS then
            reports[#reports + 1] = {
              s = guid, n = p.name, d = dim, x = it.x or 1, m = it.mult or 1,
              t = math.floor(it.it or it.t), k = Kind(dim, it, me),
            }
          end
        end
      end
    end
  end
  return reports, myGuild
end

-- Group history for cross-witness verification: for every session in the last
-- year, its time window and the GUIDs of everyone in it (you included).
-- The server only lets two witnesses confirm a negative if each lists the
-- other (and the subject) in a group at that moment.
local MAX_SESSIONS = 2000
function Net:BuildPresence(now)
  now = now or TA.Now()
  local out = {}
  local events = TA.Log:All()
  for i = #events, 1, -1 do
    local ev = events[i]
    if ev.signal == "session" and ev.sessionId and #out < MAX_SESSIONS then
      local d = ev.details
      local a, b = math.floor(d.startedAt or ev.t), math.floor(d.endedAt or ev.t)
      if now - b <= YEAR and b >= a and b - a <= 86400 then
        local members = {}
        for _, m in ipairs(TA.Log:ForSession(ev.sessionId)) do
          if m.signal == "member" and m.subjectGUID and #members < 40 then members[#members + 1] = m.subjectGUID end
        end
        if #members > 0 then out[#out + 1] = { a = a, b = b, m = members } end
      end
    end
  end
  return out
end

-- Your own character, for anonymous statistics (class, race, faction, level,
-- realm, game language). English tokens so statistics don't split by locale.
-- Nothing about other players is ever included here.
local RACE_NAMES = { Scourge = "Undead", NightElf = "Night Elf", BloodElf = "Blood Elf", HighmountainTauren = "Highmountain Tauren",
  LightforgedDraenei = "Lightforged Draenei", VoidElf = "Void Elf", DarkIronDwarf = "Dark Iron Dwarf", MagharOrc = "Mag'har Orc",
  KulTiran = "Kul Tiran", ZandalariTroll = "Zandalari Troll" }
function Net:OwnCharacter(guild)
  local _, classFile = UnitClass("player")
  local _, raceFile = UnitRace("player")
  classFile, raceFile = TA.Clean(classFile), TA.Clean(raceFile)
  local faction = TA.Clean((UnitFactionGroup("player")))
  return {
    name = TA.playerName, guild = guild, t = TA.Now(),
    class = classFile and (classFile:sub(1, 1) .. classFile:sub(2):lower()) or nil,
    race = raceFile and (RACE_NAMES[raceFile] or raceFile) or nil,
    faction = faction, level = TA.Clean(UnitLevel("player")),
    realm = GetRealmName and TA.Clean(GetRealmName()) or nil,
    locale = GetLocale and GetLocale() or nil,
  }
end

function Net:WriteOutbox()
  if not self:Enabled() or not TA.db or not TA.playerGUID then return end
  local n = self:State()
  local reports, guild = self:BuildReports()
  n.characters[TA.playerGUID] = self:OwnCharacter(guild)
  n.outbox = { protocol = TA.Params:Get("net.protocolVersion"), builtAt = TA.Now(), witness = TA.playerGUID,
    witnessGuild = guild, reports = reports, presence = self:BuildPresence() }
end

TA:On("PLAYER_LOGOUT", function() Net:WriteOutbox() end, "network")

-------------------------------------------------------------------------------
-- Network view (from NetData.lua)
-------------------------------------------------------------------------------
local function Data()
  local d = _G.TrustAdvisorNetData
  return type(d) == "table" and d or nil
end

function Net:SyncedAt()
  local d = Data()
  return d and d.generatedAt and d.generatedAt > 0 and d.generatedAt or nil
end

function Net:HasData(guid)
  local d = Data()
  return d and d.players and d.players[guid] ~= nil
end

-- Network profile: same engine, published parameters, verified incidents only.
function Net:Profile(guid, now)
  local d = Data()
  local entry = d and d.players and d.players[guid]
  if not entry then return nil end
  now = now or TA.Now()
  local P = TA.Params:DefaultSnapshot()
  local prof = { dims = {}, order = {}, witnesses = 0 }
  for _, def in ipairs(TA.Dimensions.list) do
    if Net.ELIGIBLE[def.key] then
      local items = {}
      for _, inc in ipairs(entry.incidents or {}) do
        if inc.d == def.key and not inc.disputed then
          items[#items + 1] = { t = inc.t, x = inc.x, mult = inc.m or 1, label = string.format("%d witness%s", inc.w or 1, (inc.w or 1) == 1 and "" or "es") }
          prof.witnesses = math.max(prof.witnesses, inc.w or 1)
        end
      end
      local r = TA.Engine.Evaluate(def, items, P, now)
      r.label = def.label
      prof.dims[def.key] = r
      prof.order[#prof.order + 1] = def.key
    end
  end
  prof.incidents = #(entry.incidents or {})
  return prof
end

-- Every network event about you, with witness counts (no witness identities).
function Net:MyEvents()
  local d = Data()
  return d and d.me and d.me.events or {}
end

function Net:Dispute(incidentId, reason)
  if not incidentId then return false, "unknown incident" end
  reason = tostring(reason or ""):sub(1, 200)
  local n = self:State()
  for _, x in ipairs(n.disputes) do if x.id == incidentId then return false, "already disputed" end end
  table.insert(n.disputes, { id = incidentId, reason = reason, t = TA.Now() })
  TA:Fire("DATA_CHANGED")
  return true
end

function Net:RequestDeletion()
  local n = self:State()
  n.deleteRequested = TA.Now()
  TA.Params:Set("consent.network", false)
  TA:Fire("DATA_CHANGED")
end

TA:Listen("DB_READY", function()
  if Data() and Data().generatedAt and Data().generatedAt > 0 and (Data().protocol or 1) ~= TA.Params:Get("net.protocolVersion") then
    TA:CaptureUnavailable("network", "NetData.lua", "network data uses a different protocol version")
  end
end)

-------------------------------------------------------------------------------
-- Companion detection. An addon cannot see other programs, so it infers the
-- companion's health from NetData.lua: the companion rewrites it after every
-- logout/reload, so after you join the network it must be newer than the
-- moment you joined, and never older than a week.
-------------------------------------------------------------------------------
Net.DOWNLOAD_URL = "github.com/viniciuscotrim/trust-advisor/releases"

TA:Listen("PARAMS_CHANGED", function(key)
  if key == "consent.network" and TA.Params:Get("consent.network") then
    Net:State().consentAt = TA.Now()
  end
end)

-- "off" | "waiting" (joined this session, nothing to sync yet) | "missing" | "stale" | "ok"
function Net:CompanionStatus()
  if not self:Enabled() then return "off" end
  local n = self:State()
  local synced = self:SyncedAt()
  local joined = n.consentAt or 0
  if not synced then
    return (TA.loginAt and joined >= TA.loginAt) and "waiting" or "missing"
  end
  if synced < joined then
    return (TA.loginAt and joined >= TA.loginAt) and "waiting" or "missing"
  end
  if TA.Now() - synced > STALE then return "stale" end
  return "ok"
end

-- Battle.net link status as last reported by the companion (nil = unknown)
function Net:Linked()
  local d = Data()
  if not (d and d.me) then return nil end
  return d.me.linked, d.me.verifiedCharacters or 0
end

-- True if the companion synced on this computer in the last week (network or not).
function Net:CompanionSeen()
  local d = Data()
  local at = d and d.companion and d.companion.syncedAt
  return at ~= nil and TA.Now() - at <= STALE
end

function Net:CompanionVersion()
  local d = Data()
  return d and d.companion and d.companion.version
end

Net.STATUS_TEXT = {
  off = "You have not joined the network.",
  waiting = "Joined. Log out or /reload so the companion app can sync, then /reload again to see the network view.",
  missing = "Companion app not detected: the network view never arrived since you joined.",
  stale = "Companion app seems stopped: the network view is more than 7 days old.",
  ok = "Companion app is syncing.",
}

function Net:LinkText()
  local linked, chars = self:Linked()
  if linked == nil then return "unknown until the companion syncs" end
  if not linked then return "not linked (your positives count, your negatives do not; run --link)" end
  return string.format("linked, %d Forever character(s) verified", chars)
end

function Net:SetupText()
  return {
    "|cffffd100Trust Advisor Network - companion app setup|r",
    "",
    "WoW addons cannot use the internet, so a small free companion app does it for Trust Advisor:",
    "it syncs the Network and delivers your /ta feedback reports (and the developer's replies).",
    "It only reads Trust Advisor's own saved data and only sends anything if you joined the network.",
    "",
    "1. Download it from:  https://" .. Net.DOWNLOAD_URL,
    "   Mac: open Trust Advisor Companion.app. It installs itself and offers the Battle.net link. Done.",
    "   Windows: put TrustAdvisorCompanion-windows.exe in a permanent folder, then in a terminal there:",
    "     TrustAdvisorCompanion-windows.exe --install",
    "     TrustAdvisorCompanion-windows.exe --link --region us      (eu / kr / tw for other regions)",
    "   (any OS with Python 3: ta_companion.py --install, then --link)",
    "   Linking Battle.net proves you are one real player. Only a one-way hash of your account id is stored.",
    "2. In game, /reload. The network column appears on player cards after the next sync.",
    "",
    "Status: " .. Net.STATUS_TEXT[self:CompanionStatus()],
    "Battle.net: " .. Net:LinkText(),
    "Without the companion, everything else in Trust Advisor works normally.",
  }
end

TA:Listen("LOGIN", function()
  TA.loginAt = TA.Now()
  C_Timer.After(12, function()
    local st = Net:CompanionStatus()
    if st == "missing" or st == "stale" then
      TA.Print("|cffff9933Network:|r " .. Net.STATUS_TEXT[st] .. " Type |cffffffff/ta network|r for setup.")
    end
  end)
end)
