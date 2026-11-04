-- Group captures (Information): Hardcore deaths in your group, quests finished
-- together (yours while grouped, partners' via Questie or peer messages).
local _, FR = ...

local Group = {}
FR.Group = Group

FR:RegisterCapture("hcDeath", "Hardcore party deaths", "UNIT_HEALTH, UnitIsDeadOrGhost")
FR:RegisterCapture("quests", "Your quest turn-ins", "QUEST_TURNED_IN, C_QuestLog")

-------------------------------------------------------------------------------
-- 5.12: record a partner's quest completion (from peer or Questie).
-------------------------------------------------------------------------------
function Group:MyQuestOpen(questID)
  if not (C_QuestLog and C_QuestLog.GetLogIndexForQuestID) then return false end
  local idx = FR.SafeCall(C_QuestLog.GetLogIndexForQuestID, questID)
  if not idx then return false end
  if C_QuestLog.IsComplete then
    local done = FR.SafeCall(C_QuestLog.IsComplete, questID)
    -- "open" = still in my log; complete-but-not-turned-in still counts as
    -- open because the partner is waiting for me to get back.
    return true, done
  end
  return true
end

local recentQuest = {}
function Group:RecordPartnerQuest(guid, name, questID, source, api)
  local s = FR.Sessions:Active()
  if not s or not guid or guid == FR.playerGUID or not questID then return end
  local key = guid .. ":" .. questID
  if recentQuest[key] and FR.Now() - recentQuest[key] < 300 then return end -- peer + Questie duplicates
  recentQuest[key] = FR.Now()
  local open = self:MyQuestOpen(questID)
  FR.Log:Append({ signal = "quest", subjectGUID = guid, subjectName = name, sessionId = s.id,
    source = source, api = api, details = { questID = questID, myOpen = open and true or false } })
end

-------------------------------------------------------------------------------
-- Own turn-ins (shared via Comms when consent.shareQuests is on)
-------------------------------------------------------------------------------
FR:On("QUEST_TURNED_IN", function(_, questID)
  questID = FR.Clean(questID)
  if not questID then return end
  local s = FR.Sessions:Active()
  if s then   -- only quests finished while grouped: "quests completed together"
    FR.Log:Append({ signal = "questDone", subjectGUID = FR.playerGUID, subjectName = FR.playerName, sessionId = s.id,
      api = "QUEST_TURNED_IN", details = { questID = questID } })
  end
  FR:Fire("OWN_QUEST_TURNED_IN", questID)
end, "quests")

-------------------------------------------------------------------------------
-- 5.13 Hardcore: party member death, out of combat polling + UNIT_HEALTH
-------------------------------------------------------------------------------
local deadState = {}

local function CheckDeaths()
  local s = FR.Sessions:Active()
  if not s or not s.hardcore then return end
  for _, unit in ipairs(FR.Sessions.GroupUnits()) do
    if unit ~= "player" then
      local guid = FR.Clean(UnitGUID(unit))
      local dead = FR.SafeCall(UnitIsDeadOrGhost, unit)
      if guid and dead ~= nil then
        if dead and not deadState[guid] then
          local m = s.members[guid]
          FR.Log:Append({ signal = "hcDeath", subjectGUID = guid, subjectName = m and m.name, sessionId = s.id,
            api = "UnitIsDeadOrGhost", details = {} })
        end
        deadState[guid] = dead
      end
    end
  end
end

FR:On("UNIT_HEALTH", function(_, unit)
  if type(unit) == "string" and (unit:find("^party") or unit:find("^raid")) then CheckDeaths() end
end, "hcDeath")
FR:On("PLAYER_REGEN_ENABLED", CheckDeaths, "hcDeath")
FR:Listen("SESSION_END", function() wipe(deadState) end)
