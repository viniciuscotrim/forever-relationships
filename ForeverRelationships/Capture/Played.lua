-- /played (your own characters only). The game answers RequestTimePlayed() with
-- TIME_PLAYED_MSG. We ask once per login and hide that one chat line; a /played you
-- type yourself is shown as usual and recorded too.
--   ForeverRelationshipsCharDB.played  = { total, level, t }   this character
--   ForeverRelationshipsDB.playedChars = { [guid] = { name, total, t } }  all your characters
local _, FR = ...

local Played = {}
FR.Played = Played

FR:RegisterCapture("played", "Your /played time", "RequestTimePlayed, TIME_PLAYED_MSG")

local ASK_DELAY = 8      -- seconds after login (other addons ask too; the first answer is enough)
local HIDE_WINDOW = 10   -- seconds the silent request's chat line may take to arrive
local hideUntil = 0
local liveSince = nil    -- set when this session's /played arrived: time keeps counting from it

local function Clock() return GetTime and GetTime() or 0 end

-- Wrap the chat display once; it prints normally except for our own silent request.
local function WrapDisplay()
  if Played.wrapped then return end
  local function wrap(orig)
    return function(...)
      if Clock() < hideUntil then return end
      return orig(...)
    end
  end
  if type(_G.ChatFrame_DisplayTimePlayed) == "function" then
    _G.ChatFrame_DisplayTimePlayed = wrap(_G.ChatFrame_DisplayTimePlayed)
    Played.wrapped = true
  elseif type(_G.ChatFrameUtil) == "table" and type(_G.ChatFrameUtil.DisplayTimePlayed) == "function" then
    _G.ChatFrameUtil.DisplayTimePlayed = wrap(_G.ChatFrameUtil.DisplayTimePlayed)
    Played.wrapped = true
  end
end

function Played:Ask()
  if not RequestTimePlayed then return FR:CaptureUnavailable("played", "RequestTimePlayed", "API not present") end
  WrapDisplay()
  -- without a display hook we still ask, but the game prints the usual /played line
  if self.wrapped then hideUntil = Clock() + HIDE_WINDOW end
  pcall(RequestTimePlayed)
end

local function Save(total, level)
  local now = FR.Now()
  FR.cdb.played = { total = total, level = level, t = now }
  if FR.playerGUID then
    FR.db.playedChars = FR.db.playedChars or {}
    FR.db.playedChars[FR.playerGUID] = { name = FR.playerName, total = total, t = now }
  end
end

function Played:Record(total, level)
  total, level = FR.Clean(total), FR.Clean(level)
  if type(total) ~= "number" or total < 0 then return end
  Save(math.floor(total), type(level) == "number" and math.floor(level) or nil)
  liveSince = FR.Now()
  -- the chat frames may print after us: stop hiding right after this answer
  if hideUntil > Clock() and C_Timer then C_Timer.After(0.5, function() hideUntil = 0 end) end
  FR:Fire("PLAYED_UPDATED")
end

-- This character's /played in seconds (nil until the game has answered once).
-- Logged-in time after the answer is added, so the number stays current.
function Played:Seconds()
  local p = FR.cdb and FR.cdb.played
  if not p or type(p.total) ~= "number" then return nil end
  if liveSince then return p.total + math.max(0, FR.Now() - p.t) end
  return p.total
end

function Played:Hours()
  local s = self:Seconds()
  return s and math.floor(s / 3600) or nil
end

-- Every character of yours that answered /played at least once with the addon on.
function Played:Account()
  local total, n, list = 0, 0, {}
  for guid, c in pairs(FR.db and FR.db.playedChars or {}) do
    local s = (guid == FR.playerGUID and self:Seconds()) or c.total or 0
    total, n = total + s, n + 1
    list[#list + 1] = { name = c.name, seconds = s, t = c.t }
  end
  table.sort(list, function(a, b) return a.seconds > b.seconds end)
  return total, n, list
end

if FR.frame then
  FR:On("TIME_PLAYED_MSG", function(_, total, level) Played:Record(total, level) end, "played")
  FR:Listen("LOGIN", function()
    if C_Timer then C_Timer.After(ASK_DELAY, function() Played:Ask() end) end
  end)
  -- keep the stored total current for the all-characters view
  FR:On("PLAYER_LOGOUT", function()
    local s = Played:Seconds()
    if s and liveSince then Save(s, FR.cdb.played.level) end
  end, "played")
end

return Played
