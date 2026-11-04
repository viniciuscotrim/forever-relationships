-- Slash commands (GDD 10) plus ledger, soft-reserve and signup helpers.
local _, FR = ...
local UI = FR.UI

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
  "/fr feedback - report a bug or suggest an idea (right here in game)",
  "/fr player <name> - open your Relationship with a player",
  "/fr privacy - layers, consents and what is recorded",
  "/fr cloud - companion app, backup and Battle.net status",
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
  elseif cmd == "help" or cmd == "?" then for _, l in ipairs(HELP) do FR.Print(l) end
  elseif cmd == "player" then
    local guid = FindPlayer(rest)
    if guid and FR.db.players[guid] then UI:OpenPlayer(guid) else FR.Print("You haven't played with '" .. rest .. "' yet.") end
  elseif cmd == "privacy" or cmd == "config" then UI:Open("privacy")
  elseif cmd == "cloud" or cmd == "network" then UI.ShowText("Companion app", FR.Cloud:SetupText())
  elseif cmd == "welcome" then UI.ShowWelcome()
  elseif cmd == "feedback" or cmd == "bug" or cmd == "idea" then
    UI.ShowFeedback(cmd == "idea" and "idea" or (cmd == "bug" and "bug" or nil), rest ~= "" and rest or nil)
  elseif cmd == "invisible" then
    FR.Presence:SetInvisible(not FR.db.invisible)
    FR.Print(FR.db.invisible and "Invisible mode ON: nothing is broadcast." or "Invisible mode off.")
  elseif cmd == "export" then UI.ShowText("Forever Relationships event log", UI.ExportEvents(FR.Log:Query({})))
  elseif cmd == "debug" then
    FR.db.debug = not FR.db.debug
    FR.Print("Debug logging " .. (FR.db.debug and "ON" or "off") .. ".")
  elseif cmd == "probe" then
    local a = rest:lower()
    if a == "on" then FR.Probe:Set(true)
    elseif a == "off" then FR.Probe:Set(false)
    elseif a == "clear" then FR.Probe:Clear(); FR.Print("Probe cleared.")
    else UI.ShowText("Forever Relationships probe", FR.Probe:Text()) end
  elseif cmd == "status" then
    local _, build, _, iface = GetBuildInfo()
    FR.Print(string.format("v%s · client build %s · interface %s · %d events · schema %d", FR.version, tostring(build), tostring(iface), FR.Log.count, FR.db.schemaVersion))
    FR.Print("  Companion: " .. FR.Cloud.STATUS_TEXT[FR.Cloud:CompanionStatus()] .. (FR.Cloud:CompanionVersion() and (" (" .. FR.Cloud:CompanionVersion() .. ")") or ""))
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
  FR.Print("loaded. Type /fr to open, /fr help for commands." .. (FR.db.invisible and " (Invisible mode is on)" or ""))
end)
