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

function Net:WriteOutbox()
  if not self:Enabled() or not TA.db or not TA.playerGUID then return end
  local n = self:State()
  local reports, guild = self:BuildReports()
  n.characters[TA.playerGUID] = { name = TA.playerName, guild = guild, t = TA.Now() }
  n.outbox = { protocol = TA.Params:Get("net.protocolVersion"), builtAt = TA.Now(), witness = TA.playerGUID,
    witnessGuild = guild, reports = reports }
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
