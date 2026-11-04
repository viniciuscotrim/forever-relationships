-- Questie fallback (GDD 4): parse Questie's fixed-pattern party announcements.
-- Only lines that start with Questie's marker are inspected; every other chat
-- line is discarded unread. Nothing from chat is ever stored except the quest ID.
--
-- Format (Questie v12.5 QuestieAnnounce.lua, sent in the *sender's* locale):
--   "{rt1} Questie: Quest Completed: |cff...|Hquest:1234:20|h[Name]|h|r"
--   frFR: "{rt1} Questie : Quête Terminée : ..."   ruRU: "{звезда} Questie: ..."
local _, TA = ...

local Q = {}
TA.Questie = Q

TA:RegisterCapture("questie", "Questie party announcements (fallback)", "CHAT_MSG_PARTY (Questie prefix only)")

-- "Completed" in every Questie locale (Localization/Translations/Journey/QuestsByZone.lua)
Q.completedWords = {
  "Completed", "Abgeschlossen", "Completada", "Terminée", "완료", "Concluída", "выполнено", "已完成",
}
-- Markers Questie prefixes announcements with
Q.markers = { "{rt1} Questie%s?:", "{звезда} Questie%s?:", "{star} Questie%s?:", "|T[^|]*questie[^|]*|t" }

-- Returns "complete", questID  |  "other", questID  |  nil
function Q.Parse(text)
  if type(text) ~= "string" then return nil end
  local body
  for _, m in ipairs(Q.markers) do
    local s, e = text:find(m)
    if s == 1 then body = text:sub(e + 1); break end
  end
  if not body then return nil end
  local questID = tonumber(body:match("|Hquest:(%d+)"))
  if not questID then return nil end
  local before = body:match("^(.-)|") or body
  for _, w in ipairs(Q.completedWords) do
    if before:find(w, 1, true) then return "complete", questID end
  end
  return "other", questID
end

function Q:Inspect(text, guid, name)
  if not TA:CaptureOK("questie") then return end
  local kind, questID = Q.Parse(text)
  if kind == "complete" then
    TA.Group:RecordPartnerQuest(guid, name, questID, "questie", "CHAT_MSG_PARTY (Questie announce)")
  end
end
