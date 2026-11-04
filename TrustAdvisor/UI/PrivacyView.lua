-- Privacy: the four layers and their consents, what is recorded and where,
-- companion and backup status, settings, delete everything.
local _, TA = ...
local UI = TA.UI

-- Plain-language consent texts (shown when a layer is turned on, and in Welcome)
UI.CONSENT_TEXT = {
  backup = {
    "|cffffd100Cloud backup|r",
    "The companion app encrypts your Forever Relationships history on YOUR computer before sending it.",
    "The key never leaves your computer; you get a RECOVERY CODE once - save it in your Passwords app.",
    "Nobody else, including us, can read or recover it. Without the code the backup is lost.",
    "The backup includes the facts your game recorded about players you grouped with (times, places,",
    "trades, help). It is kept for 180 days after your last sync. You can delete it anytime.",
  },
  profile = {
    "|cffffd100Public profile|r",
    "Other Forever Relationships players will see the items YOU tick about yourself (e.g. hours in groups,",
    "dungeons completed). Items confirmed by Blizzard's API for your Battle.net-linked character are",
    "marked Official; the others say 'Recorded by the addon'. Untick or turn off anytime.",
  },
  community = {
    "|cffffd100Community|r",
    "Your group sessions (times, place, kills) with each member's game-visible attributes",
    "(class, race, faction, level) are sent for anonymous statistics. No names. Every character",
    "identifier is replaced by a keyed code on the server. Players who opted out are discarded.",
    "Results are only shown in aggregate, never per person.",
  },
  recommend = {
    "|cffffd100Recommend me|r",
    "Other participants may see your character name, class, level and realm as a suggestion of",
    "someone to play with. Only players who also turned this on are ever suggested.",
  },
}

local LAYERS = {
  { key = "consent.backup", label = "Cloud backup", text = "backup", note = "Encrypted end to end. Only you can read it." },
  { key = "consent.profile", label = "Public profile", text = "profile", note = "Only the items you tick in My profile." },
  { key = "consent.community", label = "Community", text = "community", note = "Anonymous statistics, never per person." },
  { key = "consent.recommend", label = "Recommend me", text = "recommend", note = "Suggested to other opted-in players." },
}

UI.DATA_INVENTORY = {
  "|cffffd100On this computer (everyone)|r",
  "  The facts your game recorded while you played with others: group times and places, kills,",
  "  completed content, loot, trades, help, quests, ready checks, Hardcore deaths, and their",
  "  game-visible name, class, race, faction, level and guild. No chat, no opinions, no scores.",
  "  Kept for history.retentionDays (default 365). Saved on logout or /reload.",
  "",
  "|cffffd100Sent only if you turn a layer on (companion app)|r",
  "  Cloud backup: your history, encrypted with your key (unreadable to anyone else).",
  "  Public profile: the items you tick about yourself.",
  "  Community: your group sessions + members' class/race/faction/level, pseudonymized on arrival.",
  "  Feedback: only what you write in /fr feedback (and optional diagnostics).",
  "",
  "|cffffd100Never|r",
  "  Chat text or message counts, notes or ratings about anyone, inferences about anyone.",
  "",
  "|cffffd100Your rights|r: see, download and delete your data and opt out for good:",
  "  in game (Delete my cloud data below) or https://forever.gameplaybr.com.br/me (Battle.net login).",
  "  Privacy policy: https://forever.gameplaybr.com.br/privacy  ·  Questions: /fr feedback",
}

UI:RegisterView("privacy", function(frame)
  local view = {}
  UI.Label(frame, "Layers · everything that leaves your computer starts OFF", "GameFontNormal"):SetPoint("TOPLEFT", 6, -4)
  view.layers = {}
  for i, l in ipairs(LAYERS) do
    local y = -26 - (i - 1) * 28
    local b = UI.Button(frame, "", 60, 22)
    b:SetPoint("TOPLEFT", 6, y)
    local t = UI.Label(frame, l.label, "GameFontHighlight"); t:SetPoint("TOPLEFT", 74, y - 2)
    local n = UI.Label(frame, l.note, "GameFontDisableSmall"); n:SetPoint("TOPLEFT", 200, y - 4)
    local why = UI.Button(frame, "Details", 70, 20, function() UI.ShowText(l.label, UI.CONSENT_TEXT[l.text]) end)
    why:SetPoint("TOPLEFT", 470, y)
    b:SetScript("OnClick", function()
      TA.Params:Set(l.key, not TA.Params:Get(l.key))
      if TA.Params:Get(l.key) then UI.ShowText(l.label, UI.CONSENT_TEXT[l.text]) end
      view:Refresh()
    end)
    view.layers[i] = { button = b, key = l.key }
  end
  view.status = UI.Label(frame, "", "GameFontHighlightSmall")
  view.status:SetPoint("TOPLEFT", 6, -146); view.status:SetWidth(780); view.status:SetJustifyV("TOP")

  local sf = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
  sf:SetPoint("TOPLEFT", 6, -212); sf:SetPoint("BOTTOMRIGHT", -26, 34)
  local child = CreateFrame("Frame", nil, sf); child:SetSize(760, 10); sf:SetScrollChild(child)
  local inv = child:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  inv:SetPoint("TOPLEFT", 2, -2); inv:SetWidth(750); inv:SetJustifyH("LEFT"); inv:SetJustifyV("TOP")
  inv:SetText(table.concat(UI.DATA_INVENTORY, "\n"))
  child:SetHeight(inv:GetStringHeight() + 10)

  local setup = UI.Button(frame, "Companion app", 130, 22, function() UI.ShowText("Companion app", TA.Cloud:SetupText()) end)
  setup:SetPoint("BOTTOMLEFT", 4, 2)
  local settings = UI.Button(frame, "Settings", 100, 22, function() UI.ShowSettings() end)
  settings:SetPoint("LEFT", setup, "RIGHT", 6, 0)
  view.invisible = UI.Button(frame, "", 140, 22, function() TA.Presence:SetInvisible(not TA.db.invisible); view:Refresh() end)
  view.invisible:SetPoint("LEFT", settings, "RIGHT", 6, 0)
  local delCloud = UI.Button(frame, "Delete my cloud data", 170, 22, function() StaticPopup_Show("TRUSTADVISOR_CLOUD_DELETE") end)
  delCloud:SetPoint("LEFT", view.invisible, "RIGHT", 6, 0)
  local delAll = UI.Button(frame, "Delete everything here", 170, 22, function() StaticPopup_Show("TRUSTADVISOR_DELETE_ALL") end)
  delAll:SetPoint("BOTTOMRIGHT", -4, 2)

  function view:Refresh()
    for _, e in ipairs(self.layers) do e.button:SetText(TA.Params:Get(e.key) and "|cff66ff66On|r" or "|cffaaaaaaOff|r") end
    local bk = TA.Cloud:Backup()
    local L = {
      "Companion: " .. TA.Cloud.STATUS_TEXT[TA.Cloud:CompanionStatus()] .. (TA.Cloud:CompanionVersion() and (" (v" .. TA.Cloud:CompanionVersion() .. ")") or ""),
      "Battle.net: " .. TA.Cloud:LinkText(),
      "Backup: " .. (bk and bk.at and (TA.FormatAgo(bk.at) .. ", " .. math.floor((bk.size or 0) / 1024) .. " KB, encrypted") or "none yet"),
      string.format("Local history: %d events, %d players, kept %s", TA.Log.count, (function() local n = 0 for _ in pairs(TA.db.players) do n = n + 1 end return n end)(),
        TA.Params:Get("history.retentionDays") > 0 and (TA.Params:Get("history.retentionDays") .. " days") or "forever"),
    }
    if TA.Cloud:State().deleteRequested then L[#L + 1] = "|cffff9933Cloud deletion requested: sent on the next companion sync.|r" end
    self.status:SetText(table.concat(L, "\n"))
    self.invisible:SetText(TA.db.invisible and "|cffff9933Invisible: ON|r" or "Invisible: off")
  end
  return view
end)

-- Settings (all non-consent parameters), simple list with edit boxes / toggles
local settingsWin
function UI.ShowSettings()
  if not settingsWin then
    local f = UI.Window("TrustAdvisorSettings", 620, 440, "DIALOG")
    UI.Label(f, "Settings", "GameFontHighlight"):SetPoint("TOP", 0, -5)
    f.list = UI.List(f, 22, 17, function(row)
      row.key = UI.Label(row, "", "GameFontHighlightSmall"); row.key:SetPoint("LEFT", 4, 0); row.key:SetWidth(330); row.key:SetWordWrap(false)
      row.edit = UI.EditBox(row, 70, 18); row.edit:SetPoint("LEFT", 346, 0)
      row.toggle = UI.Button(row, "", 76, 18); row.toggle:SetPoint("LEFT", 340, 0)
      row.reset = UI.Button(row, "Reset", 50, 18); row.reset:SetPoint("RIGHT", -2, 0)
      row.edit:SetScript("OnEnterPressed", function(self)
        local ok, err = TA.Params:Set(row.d.key, self:GetText())
        if not ok then TA.Print(row.d.key .. ": " .. tostring(err)) end
        self:ClearFocus(); f.list:Refresh()
      end)
      row.toggle:SetScript("OnClick", function() TA.Params:Set(row.d.key, not TA.Params:Get(row.d.key)); f.list:Refresh() end)
      row.reset:SetScript("OnClick", function() TA.Params:Reset(row.d.key); f.list:Refresh() end)
      UI.Tooltip(row, function() return row.d and row.d.key or "" end, function() return row.d and { row.d.desc, "Default: " .. tostring(row.d.default) } or {} end)
    end, function(row, d)
      row.d = d
      row.key:SetText((TA.Params:IsDefault(d.key) and "" or (UI.NONDEFAULT_MARK .. " ")) .. d.desc)
      local v = TA.Params:Get(d.key)
      row.edit:SetShown(d.type ~= "bool"); row.toggle:SetShown(d.type == "bool")
      if d.type == "bool" then row.toggle:SetText(v and "|cff66ff66On|r" or "|cffaaaaaaOff|r")
      elseif not row.edit:HasFocus() then row.edit:SetText(tostring(v)) end
      row.reset:SetEnabled(not TA.Params:IsDefault(d.key))
    end)
    f.list:SetPoint("TOPLEFT", 12, -30); f.list:SetPoint("BOTTOMRIGHT", -12, 12)
    settingsWin = f
  end
  local items = {}
  for _, d in ipairs(TA.Params.defs) do if d.category ~= "Consent" then items[#items + 1] = d end end
  settingsWin.list:SetItems(items)
  settingsWin:Show()
end

StaticPopupDialogs["TRUSTADVISOR_CLOUD_DELETE"] = {
  text = "Delete your cloud data? The companion app will delete your backup, public profile and community contribution, turn every cloud layer off, and keep you excluded. Local history stays.",
  button1 = DELETE or "Delete", button2 = CANCEL, timeout = 0, whileDead = true, hideOnEscape = true, showAlert = true,
  OnAccept = function() TA.Cloud:RequestDeletion(); TA.Print("Cloud deletion requested. It is sent on the next companion sync.") end,
}
StaticPopupDialogs["TRUSTADVISOR_DELETE_ALL"] = {
  text = "Delete ALL Forever Relationships data on this computer (history, settings)? This cannot be undone. Cloud data is not affected.",
  button1 = DELETE or "Delete", button2 = CANCEL, timeout = 0, whileDead = true, hideOnEscape = true, showAlert = true,
  OnAccept = function() TA:WipeEverything(); TA.Print("All local Forever Relationships data deleted.") end,
}
