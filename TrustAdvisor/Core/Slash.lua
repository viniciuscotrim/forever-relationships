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

local function FindDimension(q)
  if not q then return nil end
  q = q:lower()
  for _, d in ipairs(TA.Dimensions.list) do
    if d.key:lower() == q then return d.key end
  end
  for _, d in ipairs(TA.Dimensions.list) do
    if d.label:lower():find(q, 1, true) then return d.key end
  end
end

-- Paste window for soft-reserve imports
local importWindow
local function ShowImport()
  if not importWindow then
    local f = UI.Window("TrustAdvisorImportWindow", 520, 360, "DIALOG")
    UI.Label(f, "Import soft reserves", "GameFontHighlight"):SetPoint("TOP", 0, -5)
    UI.Label(f, "Paste a softres.it CSV export, or lines like 'Name: 12345' (item ID).", "GameFontHighlightSmall"):SetPoint("TOPLEFT", 12, -30)
    local sf = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 12, -50); sf:SetPoint("BOTTOMRIGHT", -32, 40)
    local eb = CreateFrame("EditBox", nil, sf)
    eb:SetMultiLine(true); eb:SetFontObject(ChatFontNormal); eb:SetWidth(460); eb:SetAutoFocus(false)
    eb:SetScript("OnEscapePressed", function() f:Hide() end)
    sf:SetScrollChild(eb)
    local go = UI.Button(f, "Import", 100, 22, function()
      local n = TA.Loot:ImportSoftReserves(eb:GetText())
      TA.Print(string.format("Imported %d soft reserves.", n))
      f:Hide()
    end)
    go:SetPoint("BOTTOMRIGHT", -12, 10)
    local clear = UI.Button(f, "Clear current list", 140, 22, function() TA.Loot:ClearSoftReserves(); TA.Print("Soft reserves cleared."); f:Hide() end)
    clear:SetPoint("BOTTOMLEFT", 12, 10)
    f.edit = eb
    importWindow = f
  end
  importWindow.edit:SetText("")
  importWindow:Show()
  importWindow.edit:SetFocus()
end

local HELP = {
  "/ta - open the main window",
  "/ta player <name> - open a player card",
  "/ta why <name> <dimension> - print the explainer to chat",
  "/ta config - open Transparency",
  "/ta invisible - toggle invisible mode (stop all broadcasting)",
  "/ta export - open the export frame",
  "/ta debug - toggle verbose capture logging",
  "/ta reset params - reset all local parameters",
  "/ta owe <name> <gold> - record that <name> owes you gold  |  /ta iowe <name> <gold> - you owe them",
  "/ta sr - import soft reserves  |  /ta sr clear",
  "/ta signup add <names> | start <minutes> | withdraw <name> | close | show",
  "/ta lfg - toggle your looking-for-group flag in presence",
  "/ta status - client, interface and capture status",
}

local function Handle(msg)
  msg = msg or ""
  local cmd, rest = msg:match("^(%S*)%s*(.-)$")
  cmd = (cmd or ""):lower()

  if cmd == "" then UI:Toggle()
  elseif cmd == "help" or cmd == "?" then for _, l in ipairs(HELP) do TA.Print(l) end
  elseif cmd == "player" then
    local guid = FindPlayer(rest)
    if guid and TA.db.players[guid] then UI:OpenPlayer(guid) else TA.Print("No data on '" .. rest .. "'.") end
  elseif cmd == "why" then
    local name, dim = rest:match("^(%S+)%s+(.+)$")
    local guid, key = FindPlayer(name), FindDimension(dim)
    if not guid then TA.Print("Unknown player. Usage: /ta why <name> <dimension>"); return end
    if not key then TA.Print("Unknown dimension. Try: finish, attend, ready, pay, loot, carry, generosity, teach, craft, help, hc, endorse"); return end
    for _, line in ipairs((TA.Dimensions.Explain(guid, key))) do DEFAULT_CHAT_FRAME:AddMessage("|cff33ccffTA|r " .. line) end
  elseif cmd == "config" then UI:Open("transparency")
  elseif cmd == "invisible" then
    TA.Presence:SetInvisible(not TA.db.invisible)
    TA.Print(TA.db.invisible and "Invisible mode ON: nothing is broadcast. Local capture continues." or "Invisible mode off.")
  elseif cmd == "export" then UI.ShowText("Trust Advisor export", UI.FullExport())
  elseif cmd == "debug" then
    TA.db.debug = not TA.db.debug
    TA.Print("Debug logging " .. (TA.db.debug and "ON" or "off") .. ".")
  elseif cmd == "reset" and rest:lower() == "params" then
    TA.Params:ResetAll(); TA.Print("All parameters reset to defaults.")
  elseif cmd == "owe" or cmd == "iowe" then
    local name, gold = rest:match("^(%S+)%s+([%d%.]+)")
    local guid = FindPlayer(name)
    if not guid then TA.Print("Usage: /ta " .. cmd .. " <name> <gold> (player must be known)"); return end
    local pname = TA.db.players[guid] and TA.db.players[guid].name or name
    local ok, err
    if cmd == "owe" then ok, err = TA.Trade:AddObligation(guid, pname, TA.playerGUID, TA.playerName, gold)
    else ok, err = TA.Trade:AddObligation(TA.playerGUID, TA.playerName, guid, pname, gold) end
    local who = cmd == "owe" and (TA.ShortName(pname) .. " owes you") or ("you owe " .. TA.ShortName(pname))
    TA.Print(ok and string.format("Recorded: %s %sg (deadline %dh).", who, gold, TA.Params:Get("pay.deadlineHours")) or err)
  elseif cmd == "sr" then
    if rest:lower() == "clear" then TA.Loot:ClearSoftReserves(); TA.Print("Soft reserves cleared.") else ShowImport() end
  elseif cmd == "signup" then
    local sub, args = rest:match("^(%S*)%s*(.-)$")
    sub = (sub or ""):lower()
    if sub == "add" then TA.Print(TA.Raid:Add(args) .. " signups added.")
    elseif sub == "start" then
      local plan = TA.Raid:Plan()
      if plan then plan.startAt = TA.Now() + math.floor((tonumber(args) or 0) * 60) else plan = TA.Raid:NewPlan(args) end
      TA.Print("Raid start set to " .. TA.FormatDate(plan.startAt) .. ".")
    elseif sub == "withdraw" then TA.Print(TA.Raid:Withdraw(args) and "Withdrawal recorded." or "Not signed up.")
    elseif sub == "close" then TA.Print(TA.Raid:Close() .. " attendance records written.")
    else
      local plan = TA.Raid:Plan()
      if not plan then TA.Print("No raid plan. /ta signup add <names>, then /ta signup start <minutes>."); return end
      local names = {}
      for _, e in pairs(plan.names) do names[#names + 1] = e.name .. (e.withdrawnAt and " (withdrawn)" or "") end
      TA.Print("Raid at " .. TA.FormatDate(plan.startAt) .. ": " .. table.concat(names, ", "))
    end
  elseif cmd == "lfg" then
    TA.Presence.lfg = not TA.Presence.lfg
    TA.Print("Presence LFG flag " .. (TA.Presence.lfg and "ON" or "off") .. (TA.Presence:Active() and "" or " (presence is off)") .. ".")
  elseif cmd == "status" then
    local _, build, _, iface = GetBuildInfo()
    TA.Print(string.format("v%s · client build %s · interface %s · %d events · schema %d", TA.version, tostring(build), tostring(iface), TA.Log.count, TA.db.schemaVersion))
    for _, n in ipairs(TA.CaptureOrder) do
      local c = TA.Captures[n]
      TA.Print(string.format("  %s %s%s", c.status == "ok" and "|cff66ff66ok|r" or "|cffff9933unavailable|r", c.label,
        c.status == "ok" and "" or (" - " .. (c.reason or ""))))
    end
  else
    for _, l in ipairs(HELP) do TA.Print(l) end
  end
end

SLASH_TRUSTADVISOR1 = "/ta"
SLASH_TRUSTADVISOR2 = "/trustadvisor"
SlashCmdList.TRUSTADVISOR = Handle
TA.HandleSlash = Handle

TA:Listen("LOGIN", function()
  TA.Print("loaded. Type /ta to open, /ta help for commands." .. (TA.db.invisible and " (Invisible mode is on)" or ""))
end)
