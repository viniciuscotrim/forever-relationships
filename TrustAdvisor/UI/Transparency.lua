-- Transparency tab (GDD 8): parameter registry (visible, editable, resettable,
-- logged), formulas with live values, capture status, change log, data
-- inventory, reset and delete-everything.
local _, TA = ...
local UI = TA.UI

local SUBVIEWS = { "Parameters", "Formulas", "Captures", "Change log", "Data inventory" }

local function InlineText(parent)
  local sf = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
  local child = CreateFrame("Frame", nil, sf)
  child:SetSize(760, 10)
  sf:SetScrollChild(child)
  local fs = child:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  fs:SetPoint("TOPLEFT", 4, -4)
  fs:SetWidth(750)
  fs:SetJustifyH("LEFT")
  fs:SetJustifyV("TOP")
  function sf:SetText(t)
    fs:SetText(type(t) == "table" and table.concat(t, "\n") or t)
    child:SetHeight(fs:GetStringHeight() + 10)
  end
  return sf
end

function UI.FormulaText()
  local P = TA.Params:Snapshot()
  local L = {}
  local function add(s) L[#L + 1] = s end
  add("|cffffd100Decay (6.1)|r  lambda = 0.5 ^ (age_days / h), h = half-life of the event's sign (0 = never decays).")
  add("")
  add("|cffffd100Ratio dimensions (6.2)|r  S = (k*p + sum w*lambda*x) / (k + sum w*lambda)")
  add(string.format("   p = prior.value = %s,  k = prior.strength = %s", P["prior.value"], P["prior.strength"]))
  add("")
  add("|cffffd100Accumulating dimensions (6.3)|r  A = 1 - exp(-(sum w*lambda) / c)   (positive only, never above 1)")
  add("")
  add(string.format("|cffffd100Confidence (6.4)|r  N = sum w*lambda.  Unknown if N < %s.  Low < %s <= Medium < %s <= High",
    P["conf.minEvidence"], P["conf.minEvidence"], P["conf.highAt"]))
  add("")
  add(string.format("|cffffd100Bands (6.5)|r  Ratio: Concern < %.2f <= Building < %.2f <= Solid < %.2f <= Exemplary",
    P["band.concern"], P["band.solid"], P["band.exemplary"]))
  add(string.format("   Accumulating: Building < %.2f <= Solid < %.2f <= Exemplary  (Concern is impossible)", P["band.accSolid"], P["band.accExemplary"]))
  add("")
  add(string.format("|cffffd100Endorsement weight (6.7)|r  w = w_base * (0.5 + 0.5 * T_endorser) * (same guild ? %s : 1)",
    P["endorse.sameGuildMultiplier"]))
  add("   T_endorser = mean of the endorser's known ratio-dimension scores (prior if unknown).")
  add("")
  add("|cffffd100Per-dimension values (6.6)|r")
  for _, d in ipairs(TA.Dimensions.list) do
    local k = d.key
    if d.type == "ratio" then
      add(string.format("   %-24s ratio  weight %-5s  h_neg %-4s  h_pos %-4s", d.label, P["dim." .. k .. ".weight"], P["dim." .. k .. ".halfLifeNeg"], P["dim." .. k .. ".halfLifePos"]))
    else
      add(string.format("   %-24s acc    weight %-5s  h_pos %-4s  c %-4s", d.label, P["dim." .. k .. ".weight"], P["dim." .. k .. ".halfLifePos"], P["dim." .. k .. ".cap"]))
    end
  end
  add("")
  add("|cffffd100Rules|r")
  add(string.format("   Sessions shorter than %s min are ignored. Finishing needs at least one boss kill.", P["session.minMinutes"]))
  add(string.format("   Loot-and-leave: left within %s min of receiving loot (quality >= %s) before the final boss, weight x%s.",
    P["finish.lootLeaveMinutes"], P["finish.lootMinQuality"], P["finish.lootLeaveWeight"]))
  add(string.format("   Excused: rejoined within %s min, removed by leader, disband, disconnect, after %s consecutive wipes.%s",
    P["finish.dcGraceMinutes"], P["finish.wipeCountExcuse"], P["finish.requireLeaveMessage"] and " Unconfirmed leaves are not scored." or ""))
  add(string.format("   Showing up: on time within %s min (1), late (%s), no-show (0); withdrawals > %sh before start ignored.",
    P["attend.lateMinutes"], P["attend.lateOutcome"], P["attend.withdrawHours"]))
  add(string.format("   Paying: on time within %sh (1), late (%s), unpaid after deadline (0).", P["pay.deadlineHours"], P["pay.lateOutcome"]))
  add(string.format("   Generosity: at most %s acts per day.  Teaching: >= %s levels above median for >= %s min (Learning listing x%s).",
    P["generosity.dailyCap"], P["teach.levelGap"], P["teach.minMinutes"], P["teach.learningBonus"]))
  add(string.format("   Hardcore: leaving within %ss of a party death = fled (%s).", P["hc.fleeSeconds"], P["hc.fleeScored"] and "subtracts evidence" or "context only"))
  add(string.format("   Network view (Phase 3, locked): negatives need %s witnesses from %s guilds.", P["net.minWitnesses"], P["net.minGuilds"]))
  return L
end

UI.DATA_INVENTORY = {
  "|cffffd100TrustAdvisorDB (account-wide, this computer only)|r",
  "  params       - your local parameter overrides",
  "  changeLog    - every parameter edit (time, old, new)",
  "  events       - the raw event log: sessions, membership intervals, ready checks, trades, rolls, generosity,",
  "                 quest completions, deaths, endorsements, attendance. Names, GUIDs, levels, guilds, times.",
  "  players      - identity cache: name, class, level, first/last seen, guilds observed, self-reported attunements",
  "  signups / softReserves - imported raid plans and soft-reserve lists",
  "",
  "|cffffd100TrustAdvisorCharDB (this character only, private)|r",
  "  affinity     - sessions together (times, zone, party message COUNT), private yes/no, personal notes",
  "  endorseGiven - when you last endorsed each player (cooldown)",
  "",
  "|cffffd100Never stored|r: chat text, whisper content, presence data from other players.",
  "",
  "|cffffd100Ever transmitted (only with consent, only to Trust Advisor users)|r",
  "  HELLO     - your GUID, addon version (to group members)",
  "  QUEST     - quest ID you turned in            (consent.shareQuests)",
  "  ATTUNE    - your attunement list               (consent.shareAttunements)",
  "  ENDORSE   - your 'play again' endorsements     (consent.shareEndorsements)",
  "  PRESENCE  - zone, level, LFG flag, quest IDs   (presence.enabled, presence.shareQuests; off in invisible mode)",
  "  Never transmitted: notes, private yes/no, affinity, scores, the event log.",
  "",
  "Addons cannot access the internet. Data is saved on logout or /reload.",
}

UI:RegisterView("transparency", function(frame)
  local view = { sub = "Parameters" }
  local subFrames = {}
  local subButtons = {}
  local prev
  for _, name in ipairs(SUBVIEWS) do
    local b = UI.Button(frame, name, 118, 20, function() view.sub = name; view:Refresh() end)
    if prev then b:SetPoint("LEFT", prev, "RIGHT", 3, 0) else b:SetPoint("TOPLEFT", 4, -2) end
    subButtons[name] = b
    prev = b
    local f = CreateFrame("Frame", nil, frame)
    f:SetPoint("TOPLEFT", 0, -28)
    f:SetPoint("BOTTOMRIGHT", 0, 28)
    subFrames[name] = f
  end

  -- footer
  local resetAll = UI.Button(frame, "Reset all parameters", 170, 22, function() StaticPopup_Show("TRUSTADVISOR_RESET_PARAMS") end)
  resetAll:SetPoint("BOTTOMLEFT", 4, 2)
  local wipeBtn = UI.Button(frame, "Delete everything", 150, 22, function() StaticPopup_Show("TRUSTADVISOR_DELETE_ALL") end)
  wipeBtn:SetPoint("BOTTOMRIGHT", -4, 2)
  local invisible = UI.Button(frame, "", 150, 22, function()
    TA.Presence:SetInvisible(not TA.db.invisible); view:Refresh()
  end)
  invisible:SetPoint("LEFT", resetAll, "RIGHT", 6, 0)
  local exportBtn = UI.Button(frame, "Export all", 100, 22, function() UI.ShowText("Trust Advisor export", UI.FullExport()) end)
  exportBtn:SetPoint("LEFT", invisible, "RIGHT", 6, 0)

  ---------------------------------------------------------------------------
  -- Parameters
  ---------------------------------------------------------------------------
  local pf = subFrames.Parameters
  local search = UI.EditBox(pf, 200)
  search:SetPoint("TOPLEFT", 6, -2)
  local hint = UI.Label(search, "Search parameters", "GameFontDisableSmall"); hint:SetPoint("LEFT", 4, 0)
  search:SetScript("OnTextChanged", function(self) hint:SetShown(self:GetText() == ""); view:RefreshParams() end)
  local legend = UI.Label(pf, UI.NONDEFAULT_MARK .. " = differs from default.   Locked = network protocol (Phase 3).   Press Enter to apply a value.", "GameFontDisableSmall")
  legend:SetPoint("LEFT", search, "RIGHT", 12, 0)

  local cols = { { "Category", 4 }, { "Key", 100 }, { "Value", 330 }, { "Default", 420 }, { "Meaning", 480 } }
  for _, c in ipairs(cols) do UI.Label(pf, c[1], "GameFontNormalSmall"):SetPoint("TOPLEFT", c[2], -26) end

  local plist = UI.List(pf, 22, 17, function(row)
    row.cat = UI.Label(row, "", "GameFontDisableSmall"); row.cat:SetPoint("LEFT", 4, 0); row.cat:SetWidth(92); row.cat:SetWordWrap(false)
    row.key = UI.Label(row, "", "GameFontHighlightSmall"); row.key:SetPoint("LEFT", 100, 0); row.key:SetWidth(226); row.key:SetWordWrap(false)
    row.edit = UI.EditBox(row, 70, 18); row.edit:SetPoint("LEFT", 336, 0)
    row.toggle = UI.Button(row, "", 76, 18); row.toggle:SetPoint("LEFT", 330, 0)
    row.def = UI.Label(row, "", "GameFontDisableSmall"); row.def:SetPoint("LEFT", 420, 0)
    row.desc = UI.Label(row, "", "GameFontHighlightSmall"); row.desc:SetPoint("LEFT", 480, 0); row.desc:SetWidth(240); row.desc:SetWordWrap(false)
    row.reset = UI.Button(row, "Reset", 50, 18); row.reset:SetPoint("RIGHT", -2, 0)
    row.edit:SetScript("OnEnterPressed", function(self)
      local ok, err = TA.Params:Set(row.d.key, self:GetText())
      if not ok then TA.Print(row.d.key .. ": " .. tostring(err)) end
      self:ClearFocus()
      view:RefreshParams()
    end)
    row.edit:SetScript("OnEditFocusLost", function(self) self:SetText(tostring(TA.Params:Get(row.d.key))) end)
    row.toggle:SetScript("OnClick", function()
      TA.Params:Set(row.d.key, not TA.Params:Get(row.d.key)); view:RefreshParams()
    end)
    row.reset:SetScript("OnClick", function() TA.Params:Reset(row.d.key); view:RefreshParams() end)
    row:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
      GameTooltip:SetText(self.d.key, 1, 1, 1)
      GameTooltip:AddLine(self.d.desc, nil, nil, nil, true)
      GameTooltip:AddLine("Default: " .. tostring(self.d.default) .. "   Current: " .. tostring(TA.Params:Get(self.d.key)), 0.8, 0.8, 0.8)
      if self.d.min or self.d.max then GameTooltip:AddLine(string.format("Range: %s to %s", tostring(self.d.min or "-"), tostring(self.d.max or "-")), 0.8, 0.8, 0.8) end
      GameTooltip:AddLine("Affects: " .. (#self.d.affects > 0 and table.concat(self.d.affects, ", ") or "display / behavior only"), 0.6, 0.8, 1, true)
      if not self.d.scoring then GameTooltip:AddLine("Does not change any score.", 0.6, 0.6, 0.6) end
      if self.d.locked then GameTooltip:AddLine("Locked to the published network protocol version.", 1, 0.6, 0.2, true) end
      GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end, function(row, d)
    row.d = d
    local isDef = TA.Params:IsDefault(d.key)
    row.cat:SetText(d.category)
    row.key:SetText((isDef and "" or (UI.NONDEFAULT_MARK .. " ")) .. (isDef and d.key or ("|cffffcc66" .. d.key .. "|r")))
    local v = TA.Params:Get(d.key)
    if d.type == "bool" then
      row.edit:Hide(); row.toggle:Show()
      row.toggle:SetText(v and "|cff66ff66On|r" or "|cffaaaaaaOff|r")
      row.toggle:SetEnabled(not d.locked)
    else
      row.toggle:Hide(); row.edit:Show()
      if not row.edit:HasFocus() then row.edit:SetText(tostring(v)) end
      row.edit:SetEnabled(not d.locked)
    end
    row.def:SetText(d.locked and "|cffff9933locked|r" or tostring(d.default))
    row.desc:SetText(d.desc)
    row.reset:SetEnabled(not isDef and not d.locked)
  end)
  plist:SetPoint("TOPLEFT", 0, -40)
  plist:SetPoint("BOTTOMRIGHT", 0, 0)

  function view:RefreshParams()
    local q = (search:GetText() or ""):lower()
    local items = {}
    for _, d in ipairs(TA.Params.defs) do
      if q == "" or d.key:lower():find(q, 1, true) or d.category:lower():find(q, 1, true) or d.desc:lower():find(q, 1, true) then
        items[#items + 1] = d
      end
    end
    plist:SetItems(items)
  end

  ---------------------------------------------------------------------------
  -- Formulas / Data inventory
  ---------------------------------------------------------------------------
  local formulas = InlineText(subFrames.Formulas)
  formulas:SetPoint("TOPLEFT", 4, -4); formulas:SetPoint("BOTTOMRIGHT", -26, 4)
  local inventory = InlineText(subFrames["Data inventory"])
  inventory:SetPoint("TOPLEFT", 4, -4); inventory:SetPoint("BOTTOMRIGHT", -26, 4)

  ---------------------------------------------------------------------------
  -- Captures
  ---------------------------------------------------------------------------
  local clist = UI.List(subFrames.Captures, 20, 20, function(row)
    row.status = UI.Label(row, "", "GameFontHighlightSmall"); row.status:SetPoint("LEFT", 4, 0); row.status:SetWidth(90)
    row.label = UI.Label(row, "", "GameFontHighlight"); row.label:SetPoint("LEFT", 100, 0); row.label:SetWidth(280)
    row.api = UI.Label(row, "", "GameFontDisableSmall"); row.api:SetPoint("LEFT", 390, 0); row.api:SetWidth(380); row.api:SetWordWrap(false)
  end, function(row, c)
    row.status:SetText(c.status == "ok" and "|cff66ff66available|r" or "|cffff9933unavailable|r")
    row.label:SetText(c.label)
    row.api:SetText(c.status == "ok" and c.apis or ((c.failedApi or "?") .. ": " .. (c.reason or "")))
  end)
  clist:SetPoint("TOPLEFT", 0, -4); clist:SetPoint("BOTTOMRIGHT", 0, 0)

  ---------------------------------------------------------------------------
  -- Change log
  ---------------------------------------------------------------------------
  local llist = UI.List(subFrames["Change log"], 18, 22, function(row)
    row.text = UI.Label(row, "", "GameFontHighlightSmall"); row.text:SetPoint("LEFT", 4, 0)
  end, function(row, e)
    row.text:SetText(string.format("%s   %s   %s  ->  %s", TA.FormatDate(e.t), e.key, tostring(e.old), tostring(e.new)))
  end)
  llist:SetPoint("TOPLEFT", 0, -4); llist:SetPoint("BOTTOMRIGHT", 0, 0)

  function view:Refresh()
    for name, f in pairs(subFrames) do f:SetShown(name == self.sub) end
    for name, b in pairs(subButtons) do if name == self.sub then b:LockHighlight() else b:UnlockHighlight() end end
    invisible:SetText(TA.db.invisible and "|cffff9933Invisible: ON|r" or "Invisible: off")
    if self.sub == "Parameters" then self:RefreshParams()
    elseif self.sub == "Formulas" then formulas:SetText(UI.FormulaText())
    elseif self.sub == "Data inventory" then inventory:SetText(UI.DATA_INVENTORY)
    elseif self.sub == "Captures" then
      local items = {}
      for _, n in ipairs(TA.CaptureOrder) do items[#items + 1] = TA.Captures[n] end
      clist:SetItems(items)
    elseif self.sub == "Change log" then
      local items = {}
      for i = #TA.db.changeLog, 1, -1 do items[#items + 1] = TA.db.changeLog[i] end
      llist:SetItems(items)
    end
  end
  return view
end)

function UI.FullExport()
  local L = { "# Trust Advisor full export " .. TA.FormatDate(), "", "## Parameters (key = value [default])" }
  for _, d in ipairs(TA.Params.defs) do
    L[#L + 1] = string.format("%s = %s [%s]%s", d.key, tostring(TA.Params:Get(d.key)), tostring(d.default), TA.Params:IsDefault(d.key) and "" or "  *")
  end
  L[#L + 1] = ""
  L[#L + 1] = "## Scores (your view): name, then band per dimension"
  for guid, p in pairs(TA.db.players) do
    local prof = TA.Dimensions.Profile(guid)
    local bits = {}
    for _, k in ipairs(prof.order) do
      local r = prof.dims[k]
      bits[#bits + 1] = string.format("%s=%s(%.2f,N=%.1f)", k, r.band, r.score, r.evidence)
    end
    L[#L + 1] = (p.name or guid) .. "\t" .. table.concat(bits, " ")
  end
  L[#L + 1] = ""
  L[#L + 1] = "## Events"
  for _, line in ipairs(UI.ExportEvents(TA.Log:Query({}))) do L[#L + 1] = line end
  return L
end

StaticPopupDialogs["TRUSTADVISOR_RESET_PARAMS"] = {
  text = "Reset every Trust Advisor parameter to its default? Each change is logged.",
  button1 = YES, button2 = NO, timeout = 0, whileDead = true, hideOnEscape = true,
  OnAccept = function() TA.Params:ResetAll(); TA.Print("All parameters reset to defaults.") end,
}
StaticPopupDialogs["TRUSTADVISOR_DELETE_ALL"] = {
  text = "Delete ALL Trust Advisor data (event log, players, notes, parameters) on this account? This cannot be undone.",
  button1 = DELETE or "Delete", button2 = CANCEL, timeout = 0, whileDead = true, hideOnEscape = true, showAlert = true,
  OnAccept = function() TA:WipeEverything(); TA.Print("All Trust Advisor data deleted.") end,
}
