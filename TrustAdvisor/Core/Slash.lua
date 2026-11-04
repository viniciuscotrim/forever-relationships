-- Slash commands (GDD 10) plus ledger, soft-reserve and signup helpers.
local _, TA = ...
local UI = TA.UI

local function FindPlayer(name)
  if not name or name == "" then return nil end
  if name:lower() == "me" then return TA.playerGUID end
  for _, u in ipairs({ "target", "mouseover" }) do
    local n = TA.Clean(UnitName(u))
    if n and n:lower() == TA.ShortName(name):lower() then
      local g = TA.Clean(UnitGUID(u))
      if g then return g end
    end
  end
  return TA.Sessions:GUIDByName(name)
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
  "Companion app: github.com/viniciuscotrim/trust-advisor",
}

local function Handle(msg)
  msg = msg or ""
  local cmd, rest = msg:match("^(%S*)%s*(.-)$")
  cmd = (cmd or ""):lower()
  if cmd == "" then UI:Toggle()
  elseif cmd == "help" or cmd == "?" then for _, l in ipairs(HELP) do TA.Print(l) end
  elseif cmd == "player" then
    local guid = FindPlayer(rest)
    if guid and TA.db.players[guid] then UI:OpenPlayer(guid) else TA.Print("You haven't played with '" .. rest .. "' yet.") end
  elseif cmd == "privacy" or cmd == "config" then UI:Open("privacy")
  elseif cmd == "cloud" or cmd == "network" then UI.ShowText("Companion app", TA.Cloud:SetupText())
  elseif cmd == "welcome" then UI.ShowWelcome()
  elseif cmd == "feedback" or cmd == "bug" or cmd == "idea" then
    UI.ShowFeedback(cmd == "idea" and "idea" or (cmd == "bug" and "bug" or nil), rest ~= "" and rest or nil)
  elseif cmd == "invisible" then
    TA.Presence:SetInvisible(not TA.db.invisible)
    TA.Print(TA.db.invisible and "Invisible mode ON: nothing is broadcast." or "Invisible mode off.")
  elseif cmd == "export" then UI.ShowText("Forever Relationships event log", UI.ExportEvents(TA.Log:Query({})))
  elseif cmd == "debug" then
    TA.db.debug = not TA.db.debug
    TA.Print("Debug logging " .. (TA.db.debug and "ON" or "off") .. ".")
  elseif cmd == "probe" then
    local a = rest:lower()
    if a == "on" then TA.Probe:Set(true)
    elseif a == "off" then TA.Probe:Set(false)
    elseif a == "clear" then TA.Probe:Clear(); TA.Print("Probe cleared.")
    else UI.ShowText("Forever Relationships probe", TA.Probe:Text()) end
  elseif cmd == "status" then
    local _, build, _, iface = GetBuildInfo()
    TA.Print(string.format("v%s · client build %s · interface %s · %d events · schema %d", TA.version, tostring(build), tostring(iface), TA.Log.count, TA.db.schemaVersion))
    TA.Print("  Companion: " .. TA.Cloud.STATUS_TEXT[TA.Cloud:CompanionStatus()] .. (TA.Cloud:CompanionVersion() and (" (" .. TA.Cloud:CompanionVersion() .. ")") or ""))
    for _, n in ipairs(TA.CaptureOrder) do
      local c = TA.Captures[n]
      TA.Print(string.format("  %s %s%s", c.status == "ok" and "|cff66ff66ok|r" or "|cffff9933unavailable|r", c.label,
        c.status == "ok" and "" or (" - " .. (c.reason or ""))))
    end
  else
    for _, l in ipairs(HELP) do TA.Print(l) end
  end
end

SLASH_TRUSTADVISOR1 = "/fr"
SLASH_TRUSTADVISOR2 = "/forever"
SLASH_TRUSTADVISOR3 = "/ta"   -- v0.3 command, kept as an alias
SlashCmdList.TRUSTADVISOR = Handle
TA.HandleSlash = Handle

TA:Listen("LOGIN", function()
  TA.Print("loaded. Type /fr to open, /fr help for commands." .. (TA.db.invisible and " (Invisible mode is on)" or ""))
end)
