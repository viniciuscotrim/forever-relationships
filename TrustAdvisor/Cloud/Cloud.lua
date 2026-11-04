-- Cloud layers (GDD v2 §2), addon side. Addons cannot use the internet: at
-- logout/reload this module writes what the player consented to into
-- TrustAdvisorDB.cloud; the companion app sends it and writes Cloud/NetData.lua
-- (public profiles, suggestions, backup and link status), loaded on /reload.
--   backup    -> the companion encrypts your SavedVariables end to end (nothing here)
--   profile   -> only the items YOU tick, about YOU
--   community -> your group sessions with members' game-visible attributes, for
--                anonymous statistics; the server pseudonymizes every identifier
local _, TA = ...

local Cloud = {}
TA.Cloud = Cloud

TA:RegisterCapture("cloud", "Companion app data", "Cloud/NetData.lua (companion app)")

Cloud.DOWNLOAD_URL = "github.com/viniciuscotrim/trust-advisor/releases"
local STALE = 7 * 86400
local YEAR = 400 * 86400
local MAX_SESSIONS = 2000

local function RandomHex(n)
  local t = {}
  for i = 1, n do t[i] = string.format("%x", math.random(0, 15)) end
  return table.concat(t)
end

function Cloud:State()
  local db = TA.db
  db.cloud = db.cloud or {}
  local c = db.cloud
  if not c.uploaderId then
    -- keep the identity of a v0.3 network participant if there was one
    c.uploaderId = (db.net and db.net.uploaderId) or nil
    if not c.uploaderId then
      math.randomseed(math.floor((GetTime and GetTime() or 0) * 1000) + TA.Now())
      c.uploaderId = RandomHex(32)
    end
  end
  c.profileItems = c.profileItems or {}
  return c
end

function Cloud:AnyLayer()
  return TA.Params:Get("consent.backup") or TA.Params:Get("consent.profile") or TA.Params:Get("consent.community")
end

-------------------------------------------------------------------------------
-- Outbox (written at logout / reload)
-------------------------------------------------------------------------------
local RACE_NAMES = { Scourge = "Undead", NightElf = "Night Elf", BloodElf = "Blood Elf" }
local function Title(s) return s and (s:sub(1, 1) .. s:sub(2):lower()) or nil end

function Cloud:OwnCharacter()
  local _, classFile = UnitClass("player")
  local _, raceFile = UnitRace("player")
  classFile, raceFile = TA.Clean(classFile), TA.Clean(raceFile)
  return {
    guid = TA.playerGUID, name = TA.playerName, guild = TA.SafeCall(GetGuildInfo, "player") or "",
    class = Title(classFile), race = raceFile and (RACE_NAMES[raceFile] or raceFile) or nil,
    faction = TA.Clean((UnitFactionGroup("player"))), level = TA.Clean(UnitLevel("player")),
    realm = GetRealmName and TA.Clean(GetRealmName()) or nil, locale = GetLocale and GetLocale() or nil,
  }
end

function Cloud:ProfileValues()
  local m = TA.Rel:Mine()
  local out = {}
  for _, item in ipairs(TA.Rel.PROFILE_ITEMS) do
    if self:State().profileItems[item.key] then out[item.key] = item.value(m) end
  end
  return out
end

-- Group sessions with each member's game-visible attributes (no names).
function Cloud:CommunitySessions(now)
  now = now or TA.Now()
  local out = {}
  local events = TA.Log:All()
  for i = #events, 1, -1 do
    local ev = events[i]
    if ev.signal == "session" and ev.sessionId and #out < MAX_SESSIONS then
      local d = ev.details
      local a, b = math.floor(d.startedAt or ev.t), math.floor(d.endedAt or ev.t)
      if now - b <= YEAR and b > a and b - a <= 86400 and b - a >= TA.Params:Get("session.minMinutes") * 60 then
        local members = {}
        for _, m in ipairs(TA.Log:ForSession(ev.sessionId)) do
          if m.signal == "member" and m.subjectGUID and #members < 40 then
            local md = m.details
            local first = md.intervals and md.intervals[1]
            local last = md.intervals and md.intervals[#md.intervals]
            members[#members + 1] = { g = m.subjectGUID, class = Title(md.class), race = md.race and (RACE_NAMES[md.race] or md.race) or nil,
              faction = md.faction, level = md.level, j = first and first.join or a, l = last and last.leave or b }
          end
        end
        if #members > 0 then
          out[#out + 1] = { a = a, b = b, type = d.groupType, place = d.instanceName or d.zone, kills = d.kills and #d.kills or 0, m = members }
        end
      end
    end
  end
  return out
end

function Cloud:WriteOutbox()
  if not TA.db or not TA.playerGUID then return end
  local c = self:State()
  local consents = {
    backup = TA.Params:Get("consent.backup"), profile = TA.Params:Get("consent.profile"),
    community = TA.Params:Get("consent.community"), recommend = TA.Params:Get("consent.recommend"),
  }
  c.outbox = { protocol = 2, builtAt = TA.Now(), consents = consents,
    me = (consents.profile or consents.community or consents.recommend or c.deleteRequested) and self:OwnCharacter() or nil,
    profile = consents.profile and self:ProfileValues() or nil,
    community = consents.community and self:CommunitySessions() or nil,
    lookups = consents.profile and self:Lookups() or nil }
end

-- Public profiles are fetched for the players already in your circle.
function Cloud:Lookups()
  local out = {}
  for guid in pairs(TA.db.players) do
    if guid ~= TA.playerGUID and #out < 2000 then out[#out + 1] = guid end
  end
  return out
end

TA:On("PLAYER_LOGOUT", function() Cloud:WriteOutbox() end, "cloud")

-------------------------------------------------------------------------------
-- NetData (written by the companion)
-------------------------------------------------------------------------------
local function Data()
  local d = _G.TrustAdvisorNetData
  return type(d) == "table" and d or nil
end

function Cloud:Profile(guid)
  local d = Data()
  return d and d.profiles and d.profiles[guid] or nil
end

function Cloud:Suggestions()
  local d = Data()
  return d and d.suggestions or {}
end

function Cloud:Backup()
  local d = Data()
  return d and d.backup or nil
end

function Cloud:SyncedAt()
  local d = Data()
  return d and d.companion and d.companion.syncedAt or nil
end

function Cloud:CompanionSeen()
  local at = self:SyncedAt()
  return at ~= nil and TA.Now() - at <= STALE
end

function Cloud:CompanionVersion()
  local d = Data()
  return d and d.companion and d.companion.version
end

-- Battle.net link status as last reported by the companion (nil = unknown)
function Cloud:Linked()
  local d = Data()
  if not (d and d.me) then return nil end
  return d.me.linked, d.me.verifiedCharacters or 0
end

-- "off" | "waiting" | "missing" | "stale" | "ok"
function Cloud:CompanionStatus()
  if not self:AnyLayer() then return "off" end
  local at = self:SyncedAt()
  if not at then return (TA.loginAt and (self:State().consentAt or 0) >= TA.loginAt) and "waiting" or "missing" end
  if TA.Now() - at > STALE then return "stale" end
  return "ok"
end

Cloud.STATUS_TEXT = {
  off = "No cloud layer is on.",
  waiting = "Turned on. Log out or /reload so the companion app can sync, then /reload again.",
  missing = "Companion app not detected: nothing has synced yet.",
  stale = "Companion app seems stopped: the last sync is more than 7 days old.",
  ok = "Companion app is syncing.",
}

function Cloud:LinkText()
  local linked, chars = self:Linked()
  if linked == nil then return "unknown until the companion syncs" end
  if not linked then return "not linked (needed for Official profile items)" end
  return string.format("linked, %d Forever character(s) verified", chars)
end

function Cloud:SetupText()
  return {
    "|cffffd100Trust Advisor companion app|r",
    "",
    "WoW addons cannot use the internet. The free companion app does it for Trust Advisor:",
    "your encrypted cloud backup, your public profile, community statistics, and /ta feedback.",
    "",
    "1. Download it from:  https://" .. Cloud.DOWNLOAD_URL,
    "   Mac: open Trust Advisor Companion.app. It installs itself and offers the Battle.net link.",
    "   Windows: put TrustAdvisorCompanion-windows.exe in a permanent folder, then in a terminal there:",
    "     TrustAdvisorCompanion-windows.exe --install",
    "     TrustAdvisorCompanion-windows.exe --link --region us      (eu / kr / tw for other regions)",
    "2. Cloud backup: the companion shows a RECOVERY CODE once. Save it in your Passwords app.",
    "   Without the code nobody, not even us, can recover your backup.",
    "3. In game, /reload.",
    "",
    "Status: " .. Cloud.STATUS_TEXT[self:CompanionStatus()],
    "Battle.net: " .. self:LinkText(),
    "Without the companion, everything local in Trust Advisor works normally.",
  }
end

function Cloud:RequestDeletion()
  local c = self:State()
  c.deleteRequested = TA.Now()
  for _, k in ipairs({ "consent.backup", "consent.profile", "consent.community", "consent.recommend" }) do TA.Params:Set(k, false) end
  TA:Fire("DATA_CHANGED")
end

TA:Listen("PARAMS_CHANGED", function(key)
  if type(key) == "string" and key:find("^consent%.") and TA.Params:Get(key) then Cloud:State().consentAt = TA.Now() end
end)

TA:Listen("LOGIN", function()
  TA.loginAt = TA.Now()
  C_Timer.After(12, function()
    local st = Cloud:CompanionStatus()
    if st == "missing" or st == "stale" then
      TA.Print("|cffff9933Cloud:|r " .. Cloud.STATUS_TEXT[st] .. " Type |cffffffff/ta cloud|r for setup.")
    end
  end)
end)
