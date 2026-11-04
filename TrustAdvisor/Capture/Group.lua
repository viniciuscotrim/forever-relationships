-- Group captures: hardcore deaths (5.13), quest turn-ins for "stayed to help"
-- (5.12), questing session facts (5.11). Showing up / finishing / teaching /
-- guild stability are captured by Core/Sessions.lua as raw session facts.
local _, TA = ...

local Group = {}
TA.Group = Group

TA:RegisterCapture("hcDeath", "Hardcore party deaths", "UNIT_HEALTH, UnitIsDeadOrGhost")
TA:RegisterCapture("quests", "Your quest turn-ins", "QUEST_TURNED_IN, C_QuestLog")

-------------------------------------------------------------------------------
-- 5.12: record a partner's quest completion (from peer or Questie).
-------------------------------------------------------------------------------
function Group:MyQuestOpen(questID)
  if not (C_QuestLog and C_QuestLog.GetLogIndexForQuestID) then return false end
  local idx = TA.SafeCall(C_QuestLog.GetLogIndexForQuestID, questID)
  if not idx then return false end
  if C_QuestLog.IsComplete then
    local done = TA.SafeCall(C_QuestLog.IsComplete, questID)
    -- "open" = still in my log; complete-but-not-turned-in still counts as
    -- open because the partner is waiting for me to get back.
    return true, done
  end
  return true
end

local recentQuest = {}
function Group:RecordPartnerQuest(guid, name, questID, source, api)
  local s = TA.Sessions:Active()
  if not s or not guid or guid == TA.playerGUID or not questID then return end
  local key = guid .. ":" .. questID
  if recentQuest[key] and TA.Now() - recentQuest[key] < 300 then return end -- peer + Questie duplicates
  recentQuest[key] = TA.Now()
  local open = self:MyQuestOpen(questID)
  TA.Log:Append({ signal = "quest", subjectGUID = guid, subjectName = name, sessionId = s.id,
    source = source, api = api, details = { questID = questID, myOpen = open and true or false } })
end

-------------------------------------------------------------------------------
-- Own turn-ins (shared via Comms when consent.shareQuests is on)
-------------------------------------------------------------------------------
TA:On("QUEST_TURNED_IN", function(_, questID)
  questID = TA.Clean(questID)
  if not questID then return end
  TA:Fire("OWN_QUEST_TURNED_IN", questID)
end, "quests")

-------------------------------------------------------------------------------
-- 5.13 Hardcore: party member death, out of combat polling + UNIT_HEALTH
-------------------------------------------------------------------------------
local deadState = {}

local function CheckDeaths()
  local s = TA.Sessions:Active()
  if not s or not s.hardcore then return end
  for _, unit in ipairs(TA.Sessions.GroupUnits()) do
    if unit ~= "player" then
      local guid = TA.Clean(UnitGUID(unit))
      local dead = TA.SafeCall(UnitIsDeadOrGhost, unit)
      if guid and dead ~= nil then
        if dead and not deadState[guid] then
          local m = s.members[guid]
          TA.Log:Append({ signal = "hcDeath", subjectGUID = guid, subjectName = m and m.name, sessionId = s.id,
            api = "UnitIsDeadOrGhost", details = {} })
        end
        deadState[guid] = dead
      end
    end
  end
end

TA:On("UNIT_HEALTH", function(_, unit)
  if type(unit) == "string" and (unit:find("^party") or unit:find("^raid")) then CheckDeaths() end
end, "hcDeath")
TA:On("PLAYER_REGEN_ENABLED", CheckDeaths, "hcDeath")
TA:Listen("SESSION_END", function() wipe(deadState) end)
