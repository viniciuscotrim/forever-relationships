-- Privacy: the four layers and their consents, what is recorded and where,
-- companion and backup status, settings, delete everything.
local _, FR = ...
local UI = FR.UI
local L = FR.L

-- Plain-language consent texts (shown when a layer is turned on, and in Welcome).
-- One paragraph per string: every paragraph is translated whole (Locales/).
local CONSENT = {
  backup = {
    "Cloud backup",
    "The companion app encrypts your Forever Relationships history on YOUR computer before sending it.",
    "The key never leaves your computer; you get a RECOVERY CODE once - save it in your Passwords app.",
    "Nobody else, including us, can read or recover it. Without the code the backup is lost.",
    "The backup includes the facts your game recorded about players you grouped with (times, places, trades, help). It is kept for 180 days after your last sync. You can delete it anytime.",
  },
  profile = {
    "Public profile",
    "Other Forever Relationships players will see the items YOU tick about yourself (e.g. /played, hours in groups, dungeons completed).",
    "Items confirmed by Blizzard's API for your Battle.net-linked character are marked Official; the others say 'Recorded by the addon'. Untick or turn off anytime.",
  },
  community = {
    "Community",
    "Your group sessions (times, place, kills) with each member's game-visible attributes (class, race, faction, level) are sent for anonymous statistics. No names.",
    "Every character identifier is replaced by a keyed code on the server. Players who opted out are discarded. Results are only shown in aggregate, never per person.",
    "Population census: for characters you see (mouseover, target, nameplates, group) the addon keeps only faction, race, class, level and the realm number from their character code, for 30 days.",
    "The server replaces each code by a keyed code and publishes only totals per realm type, faction and race (the Population tab). Turning Community off deletes it here and on the server.",
  },
  recommend = {
    "Recommend me",
    "Other participants may see your character name, class, level and realm as a suggestion of someone to play with.",
    "Only players who also turned this on are ever suggested.",
  },
}
-- Translated on use: UI.CONSENT_TEXT.backup is a list of lines in the active language.
UI.CONSENT_TEXT = setmetatable({}, { __index = function(_, k)
  local src = CONSENT[k]
  if not src then return nil end
  local out = { "|cffffd100" .. L[src[1]] .. "|r" }
  for i = 2, #src do out[#out + 1] = L[src[i]] end
  return out
end })

local LAYERS = {
  { key = "consent.backup", label = "Cloud backup", text = "backup", note = "Encrypted end to end. Only you can read it." },
  { key = "consent.profile", label = "Public profile", text = "profile", note = "Only the items you tick in My profile." },
  { key = "consent.community", label = "Community", text = "community", note = "Anonymous statistics, never per person." },
  { key = "consent.recommend", label = "Recommend me", text = "recommend", note = "Suggested to other opted-in players." },
}

local INVENTORY = {
  { head = "On this computer (everyone)" },
  "The facts your game recorded while you played with others: group times and places, kills, completed content, loot, trades, help, quests, ready checks, Hardcore deaths, and their game-visible name, class, race, faction, level and guild. No chat, no opinions, no scores.",
  "Opposite-faction players you cross: how often you crossed, fought, won and died, nothing else.",
  "Your groups: the labels you give players. Only on this computer, never sent.",
  "Kept for history.retentionDays (default 365). Saved on logout or /reload.",
  "",
  { head = "Sent only if you turn a layer on (companion app)" },
  "Cloud backup: your history, encrypted with your key (unreadable to anyone else).",
  "Public profile: the items you tick about yourself.",
  "Community: your group sessions + members' class/race/faction/level, pseudonymized on arrival.",
  "Feedback: only what you write in /fr feedback (and optional diagnostics).",
  "",
  { head = "Party chat" },
  "One welcome line when a party forms or someone joins (Settings: announce.party).",
  "",
  { head = "Never" },
  "Chat text or message counts, notes or ratings about anyone, inferences about anyone.",
  "",
  { head = "Your rights" },
  "See, download and delete your data and opt out for good: in game (Delete my cloud data below) or https://forever.gameplaybr.com.br/me (Battle.net login).",
  "Privacy policy: https://forever.gameplaybr.com.br/privacy  ·  Questions: /fr feedback",
}
UI.DATA_INVENTORY = setmetatable({}, { __index = function(_, k)
  if k ~= "lines" then return nil end
  local out = {}
  for _, l in ipairs(INVENTORY) do
    if type(l) == "table" then out[#out + 1] = "|cffffd100" .. L[l.head] .. "|r"
    elseif l == "" then out[#out + 1] = ""
    else out[#out + 1] = "  " .. L[l] end
  end
  return out
end })

UI:RegisterView("privacy", function(frame)
  local view = {}
  UI.Label(frame, L["Layers · everything that leaves your computer starts OFF"], "GameFontNormal"):SetPoint("TOPLEFT", 6, -4)
  view.layers = {}
  for i, l in ipairs(LAYERS) do
    local y = -26 - (i - 1) * 28
    local b = UI.Button(frame, "", 60, 22)
    b:SetPoint("TOPLEFT", 6, y)
    local t = UI.Label(frame, L[l.label], "GameFontHighlight"); t:SetPoint("TOPLEFT", 74, y - 2)
    local n = UI.Label(frame, L[l.note], "GameFontDisableSmall"); n:SetPoint("TOPLEFT", 200, y - 4)
    local why = UI.Button(frame, L["Details"], 70, 20, function() UI.ShowText(L[l.label], UI.CONSENT_TEXT[l.text]) end)
    why:SetPoint("TOPLEFT", 470, y)
    b:SetScript("OnClick", function()
      FR.Params:Set(l.key, not FR.Params:Get(l.key))
      if FR.Params:Get(l.key) then UI.ShowText(L[l.label], UI.CONSENT_TEXT[l.text]) end
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
  inv:SetText(table.concat(UI.DATA_INVENTORY.lines, "\n"))
  child:SetHeight(inv:GetStringHeight() + 10)

  local setup = UI.Button(frame, L["Companion app"], 130, 22, function() UI.ShowText(L["Companion app"], FR.Cloud:SetupText()) end)
  setup:SetPoint("BOTTOMLEFT", 4, 2)
  local settings = UI.Button(frame, L["Settings"], 100, 22, function() UI.ShowSettings() end)
  settings:SetPoint("LEFT", setup, "RIGHT", 6, 0)
  view.invisible = UI.Button(frame, "", 140, 22, function() FR.Presence:SetInvisible(not FR.db.invisible); view:Refresh() end)
  view.invisible:SetPoint("LEFT", settings, "RIGHT", 6, 0)
  local delCloud = UI.Button(frame, L["Delete my cloud data"], 170, 22, function() StaticPopup_Show("FOREVERRELATIONSHIPS_CLOUD_DELETE") end)
  delCloud:SetPoint("LEFT", view.invisible, "RIGHT", 6, 0)
  local delAll = UI.Button(frame, L["Delete everything here"], 170, 22, function() StaticPopup_Show("FOREVERRELATIONSHIPS_DELETE_ALL") end)
  delAll:SetPoint("BOTTOMRIGHT", -4, 2)

  function view:Refresh()
    for _, e in ipairs(self.layers) do e.button:SetText(FR.Params:Get(e.key) and ("|cff66ff66" .. FR.L["On"] .. "|r") or ("|cffaaaaaa" .. FR.L["Off"] .. "|r")) end
    local bk = FR.Cloud:Backup()
    local days = FR.Params:Get("history.retentionDays")
    local lines = {
      L["Companion:"] .. " " .. L[FR.Cloud.STATUS_TEXT[FR.Cloud:CompanionStatus()]] .. (FR.Cloud:CompanionVersion() and (" (v" .. FR.Cloud:CompanionVersion() .. ")") or ""),
      "Battle.net: " .. FR.Cloud:LinkText(),
      L["Backup:"] .. " " .. (bk and bk.at and L["%s, %d KB, encrypted"]:format(FR.FormatAgo(bk.at), math.floor((bk.size or 0) / 1024)) or L["none yet"]),
      L["Local history: %d events, %d players, kept %s"]:format(FR.Log.count, (function() local n = 0 for _ in pairs(FR.db.players) do n = n + 1 end return n end)(),
        days > 0 and FR.Plural(days, "%d day", "%d days") or L["forever"]),
    }
    if FR.Cloud:State().deleteRequested then lines[#lines + 1] = "|cffff9933" .. L["Cloud deletion requested: sent on the next companion sync."] .. "|r" end
    self.status:SetText(table.concat(lines, "\n"))
    self.invisible:SetText(FR.db.invisible and ("|cffff9933" .. L["Invisible: ON"] .. "|r") or L["Invisible: off"])
  end
  return view
end)

-- Settings (all non-consent parameters), simple list with edit boxes / toggles
local settingsWin
function UI.ShowSettings()
  if not settingsWin then
    local f = UI.Window("ForeverRelationshipsSettings", 620, 440, "DIALOG")
    UI.Label(f, L["Settings"], "GameFontHighlight"):SetPoint("TOP", 0, -5)
    f.list = UI.List(f, 22, 17, function(row)
      row.key = UI.Label(row, "", "GameFontHighlightSmall"); row.key:SetPoint("LEFT", 4, 0); row.key:SetWidth(330); row.key:SetWordWrap(false)
      row.edit = UI.EditBox(row, 70, 18); row.edit:SetPoint("LEFT", 346, 0)
      row.toggle = UI.Button(row, "", 76, 18); row.toggle:SetPoint("LEFT", 340, 0)
      row.reset = UI.Button(row, L["Reset"], 50, 18); row.reset:SetPoint("RIGHT", -2, 0)
      row.edit:SetScript("OnEnterPressed", function(self)
        local ok, err = FR.Params:Set(row.d.key, self:GetText())
        if not ok then FR.Print(row.d.key .. ": " .. tostring(err)) end
        self:ClearFocus(); f.list:Refresh()
      end)
      row.toggle:SetScript("OnClick", function() FR.Params:Set(row.d.key, not FR.Params:Get(row.d.key)); f.list:Refresh() end)
      row.reset:SetScript("OnClick", function() FR.Params:Reset(row.d.key); f.list:Refresh() end)
      UI.Tooltip(row, function() return row.d and row.d.key or "" end, function() return row.d and { L[row.d.desc], L["Default: %s"]:format(tostring(row.d.default)) } or {} end)
    end, function(row, d)
      row.d = d
      row.key:SetText((FR.Params:IsDefault(d.key) and "" or (UI.NONDEFAULT_MARK .. " ")) .. L[d.desc])
      local v = FR.Params:Get(d.key)
      row.edit:SetShown(d.type ~= "bool"); row.toggle:SetShown(d.type == "bool")
      if d.type == "bool" then row.toggle:SetText(v and ("|cff66ff66" .. FR.L["On"] .. "|r") or ("|cffaaaaaa" .. FR.L["Off"] .. "|r"))
      elseif not row.edit:HasFocus() then row.edit:SetText(tostring(v)) end
      row.reset:SetEnabled(not FR.Params:IsDefault(d.key))
    end)
    f.list:SetPoint("TOPLEFT", 12, -30); f.list:SetPoint("BOTTOMRIGHT", -12, 12)
    settingsWin = f
  end
  local items = {}
  for _, d in ipairs(FR.Params.defs) do if d.category ~= "Consent" then items[#items + 1] = d end end
  settingsWin.list:SetItems(items)
  settingsWin:Show()
end

UI.Popup("FOREVERRELATIONSHIPS_CLOUD_DELETE", {
  text = "Delete your cloud data? The companion app will delete your backup, public profile and community contribution, turn every cloud layer off, and keep you excluded. Local history stays.",
  button1 = DELETE or "Delete", button2 = CANCEL, timeout = 0, whileDead = true, hideOnEscape = true, showAlert = true,
  OnAccept = function() FR.Cloud:RequestDeletion(); FR.Print(L["Cloud deletion requested. It is sent on the next companion sync."]) end,
})
UI.Popup("FOREVERRELATIONSHIPS_DELETE_ALL", {
  text = "Delete ALL Forever Relationships data on this computer (history, settings)? This cannot be undone. Cloud data is not affected.",
  button1 = DELETE or "Delete", button2 = CANCEL, timeout = 0, whileDead = true, hideOnEscape = true, showAlert = true,
  OnAccept = function() FR:WipeEverything(); FR.Print(L["All local Forever Relationships data deleted."]) end,
})
