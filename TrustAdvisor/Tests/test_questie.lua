-- Questie announcement parser fixtures. Formats taken from Questie v12.5
-- Modules/QuestieAnnounce.lua + its localization tables. Replace/extend with
-- 10 real captured lines from the live client (GDD 12 checklist).
--   luajit Tests/test_questie.lua
local root = (arg and arg[0] or ""):match("^(.*)Tests/") or "./"
local TA = { RegisterCapture = function() end }
assert(loadfile(root .. "Capture/Questie.lua"))("TrustAdvisor", TA)
local P = TA.Questie.Parse
local link = "|cffffff00|Hquest:1234:20|h[The Defias Brotherhood]|h|r"
local cases = {
  { "{rt1} Questie: Quest Completed: " .. link, "complete", 1234 },
  { "{rt1} Questie: Quest Accepted: " .. link, "other", 1234 },
  { "{rt1} Questie: Quest Abandoned: " .. link, "other", 1234 },
  { "{rt1} Questie: 8/8 Defias Trapper slain for " .. link .. "!", "other", 1234 },
  { "{rt1} Questie : Quête Terminée : " .. link, "complete", 1234 },
  { "{rt1} Questie: Quest Abgeschlossen: " .. link, "complete", 1234 },
  { "{rt1} Questie: Misión Completada: " .. link, "complete", 1234 },
  { "{rt1} Questie: Missão Concluída: " .. link, "complete", 1234 },
  { "{звезда} Questie: Задание выполнено: " .. link, "complete", 1234 },
  { "{rt1} Questie: 任务已完成：" .. link, "complete", 1234 },
  { "Quest Completed: " .. link, nil },                 -- no Questie marker: ignored
  { "hey did you finish " .. link .. " yet?", nil },     -- ordinary chat: ignored
  { "lol {rt1} Questie: Quest Completed: " .. link, nil }, -- marker not at start: ignored
}
local fails = 0
for i, c in ipairs(cases) do
  local kind, id = P(c[1])
  local ok = kind == c[2] and (c[2] == nil or id == c[3])
  if not ok then fails = fails + 1; print("  FAIL #" .. i .. " got " .. tostring(kind) .. " " .. tostring(id)) end
end
print(string.format("Questie parser: %d/%d fixtures passed", #cases - fails, #cases))
if fails > 0 then os.exit(1) end
