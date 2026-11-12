-- Slash commands (GDD 10) plus ledger, soft-reserve and signup helpers.
local _, FR = ...
local UI = FR.UI
local L = FR.L

local function FindPlayer(name)
  if not name or name == "" then return nil end
  if name:lower() == "me" then return FR.playerGUID end
  for _, u in ipairs({ "target", "mouseover" }) do
    local n = FR.Clean(UnitName(u))
    if n and n:lower() == FR.ShortName(name):lower() then
      local g = FR.Clean(UnitGUID(u))
      if g then return g end
    end
  end
  return FR.Sessions:GUIDByName(name)
end


local HELP = {
  "/fr - open the main window",
  "/fr alert - show a sample nearby alert to move it (reset: back to the default place, range: maximum nameplate distance)",
  "/fr groups - create, rename or delete your groups",
  "/fr language <code> - language of the addon (enUS, deDE, esES, esMX, frFR, itIT, koKR, ptBR, ruRU, zhCN, zhTW; auto = the game's)",
  "/fr feedback - report a bug or suggest an idea (right here in game)",
  "/fr translate - suggest a better translation for a text in your language",
  "/fr player <name> - open your Relationship with a player",
  "/fr settings - every option of the addon",
  "/fr macro - the invite / join-group macro (one click to create it)",
  "/fr privacy - layers, consents and what is recorded",
  "/fr cloud - companion app, backup and Battle.net status",
  "/fr population - realm population by faction and race (PvP / PvE)",
  "/fr welcome - show the welcome and the layer choices again",
  "/fr invisible - toggle invisible mode (stop presence broadcasting)",
  "/fr export - copy your local event log as text",
  "/fr debug - toggle verbose capture logging",
  "/fr probe on|off|show|clear - developer: record spells cast by your group for live validation",
  "/fr status - client, interface and capture status",
  "Companion app: github.com/viniciuscotrim/forever-relationships",
}

local function Handle(msg)
  msg = msg or ""
  local cmd, rest = msg:match("^(%S*)%s*(.-)$")
  cmd = (cmd or ""):lower()
  if cmd == "" then UI:Toggle()
  elseif cmd == "help" or cmd == "?" then for _, l in ipairs(HELP) do FR.Print(L[l]) end
  elseif cmd == "player" then
    local guid = FindPlayer(rest) or (FR.Rivals and FR.Rivals:ByName(rest))
    if guid and (FR.db.players[guid] or FR.Rivals:Get(guid)) then UI:OpenPlayer(guid) else FR.Print(L["You haven't played with '%s' yet."]:format(rest)) end
  elseif cmd == "alert" then
    local a = rest:lower()
    if a == "reset" then UI.NearbyAlert:ResetPosition(); UI.NearbyAlert:Test()
    elseif a == "range" then
      local d = UI.NearbyAlert:MaxRange()
      FR.Print(d and L["Nameplate distance set to %d yards, the most the game allows. Turn on friendly nameplates (Shift+V) to see friends from afar."]:format(d)
        or L["Not possible in combat. Try again after the fight."])
    else UI.NearbyAlert:Test() end
  elseif cmd == "groups" then UI.GroupPicker:Open(nil)
  elseif cmd == "language" or cmd == "lang" then
    local code = rest ~= "" and rest or nil
    local found
    for _, c in ipairs(FR.LOCALES) do if code and c:lower() == code:lower() then found = c end end
    if found or code == "auto" then
      FR.db.ui.locale = found
      FR.Print(L["Language: %s. Type /reload to apply."]:format(found and FR.LOCALE_NAMES[found] or L["the game's language"]))
    else
      local list = {}
      for _, c in ipairs(FR.LOCALES) do list[#list + 1] = c .. " (" .. FR.LOCALE_NAMES[c] .. ")" end
      FR.Print(L["Languages: %s"]:format(table.concat(list, ", ")))
    end
  elseif cmd == "settings" or cmd == "options" then UI:Open(); UI.ShowSettings()
  elseif cmd == "macro" or cmd == "invite" then UI.ShowMacro()
  elseif cmd == "privacy" or cmd == "config" then UI:Open("privacy")
  elseif cmd == "population" or cmd == "pop" then UI:Open("population")
  elseif cmd == "cloud" or cmd == "network" then UI.ShowText(L["Companion app"], FR.Cloud:SetupText())
  elseif cmd == "welcome" then UI.ShowWelcome()
  elseif cmd == "feedback" or cmd == "bug" or cmd == "idea" or cmd == "translate" or cmd == "translation" then
    local kind = (cmd == "idea" and "idea") or (cmd == "bug" and "bug") or ((cmd == "translate" or cmd == "translation") and "translation") or nil
    UI.ShowFeedback(kind, rest ~= "" and rest or nil)
  elseif cmd == "invisible" then
    FR.Presence:SetInvisible(not FR.db.invisible)
    FR.Print(FR.db.invisible and L["Invisible mode ON: nothing is broadcast."] or L["Invisible mode off."])
  elseif cmd == "export" then UI.ShowText(L["Forever Relationships event log"], UI.ExportEvents(FR.Log:Query({})))
  elseif cmd == "debug" then
    FR.db.debug = not FR.db.debug
    FR.Print(FR.db.debug and L["Debug logging ON."] or L["Debug logging off."])
  elseif cmd == "probe" then
    local a = rest:lower()
    if a == "on" then FR.Probe:Set(true)
    elseif a == "off" then FR.Probe:Set(false)
    elseif a == "clear" then FR.Probe:Clear(); FR.Print(L["Probe cleared."])
    else UI.ShowText("Forever Relationships probe", FR.Probe:Text()) end
  elseif cmd == "status" then
    local _, build, _, iface = GetBuildInfo()
    FR.Print(string.format("v%s · client build %s · interface %s · %d events · schema %d", FR.version, tostring(build), tostring(iface), FR.Log.count, FR.db.schemaVersion))
    FR.Print("  " .. L["Companion:"] .. " " .. L[FR.Cloud.STATUS_TEXT[FR.Cloud:CompanionStatus()]] .. (FR.Cloud:CompanionVersion() and (" (" .. FR.Cloud:CompanionVersion() .. ")") or ""))
    for _, n in ipairs(FR.CaptureOrder) do
      local c = FR.Captures[n]
      FR.Print(string.format("  %s %s%s", c.status == "ok" and "|cff66ff66ok|r" or "|cffff9933unavailable|r", c.label,
        c.status == "ok" and "" or (" - " .. (c.reason or ""))))
    end
  else
    for _, l in ipairs(HELP) do FR.Print(l) end
  end
end

SLASH_FOREVERRELATIONSHIPS1 = "/fr"
SLASH_FOREVERRELATIONSHIPS2 = "/forever"
SlashCmdList.FOREVERRELATIONSHIPS = Handle
FR.HandleSlash = Handle

FR:Listen("LOGIN", function()
  FR.Print(L["loaded. Type /fr to open, /fr help for commands."] .. (FR.db.invisible and (" " .. L["(Invisible mode is on)"]) or ""))
end)
