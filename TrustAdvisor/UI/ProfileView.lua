-- My profile: your own bands as your client witnessed them, endorsements
-- received (local and peer), attunements.
local _, TA = ...
local UI = TA.UI

UI:RegisterView("profile", function(frame)
  local view = {}
  local header = UI.Label(frame, "", "GameFontNormalLarge")
  header:SetPoint("TOPLEFT", 6, -4)
  local note = UI.Label(frame, "|cff888888Your own behavior as your client witnessed it. Others see their own view of you.|r", "GameFontHighlightSmall")
  note:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4)

  local trust = UI.TrustPanel(frame)
  trust:SetPoint("TOPLEFT", 0, -46)
  trust:SetSize(560, 360)

  local eh = UI.Label(frame, "Endorsements received", "GameFontNormal")
  eh:SetPoint("TOPLEFT", 590, -46)
  local list = UI.List(frame, 18, 7, function(row)
    row.text = UI.Label(row, "", "GameFontHighlightSmall"); row.text:SetPoint("LEFT", 4, 0); row.text:SetWidth(190)
  end, function(row, ev)
    row.text:SetText(string.format("%s |cff888888%s · %s|r", TA.ShortName(ev.details.endorserName), ev.source, date("%m-%d", ev.t)))
  end)
  list:SetPoint("TOPLEFT", 586, -64)
  list:SetSize(210, 130)

  -- Network events about you (Phase 3): witness counts only, never identities.
  local nh = UI.Label(frame, "Network events about you", "GameFontNormal")
  nh:SetPoint("TOPLEFT", 590, -204)
  local nlist = UI.List(frame, 20, 9, function(row)
    row.text = UI.Label(row, "", "GameFontHighlightSmall"); row.text:SetPoint("LEFT", 4, 0); row.text:SetWidth(140); row.text:SetWordWrap(false)
    row.btn = UI.Button(row, "Dispute", 56, 18); row.btn:SetPoint("RIGHT", -2, 0)
    row.btn:SetScript("OnClick", function(self)
      local inc = self:GetParent().inc
      if inc then StaticPopup_Show("TRUSTADVISOR_DISPUTE", nil, nil, inc) end
    end)
    UI.Tooltip(row, "Network event", function()
      local inc = row.inc
      if not inc then return {} end
      return { string.format("%s, outcome %.2f", inc.d, inc.x),
        string.format("%d witness(es), %d cross-checked, from %d guild group(s)", inc.w or 0, inc.c or inc.w or 0, inc.g or 0),
        inc.verified and "Counts in the network view." or "Not verified: needs more independent witnesses. Does not count.",
        inc.disputed and "Disputed: excluded until reviewed." or "" }
    end)
  end, function(row, inc)
    row.inc = inc
    local color = inc.x < 1 and "ffff9933" or "ff66ff66"
    row.text:SetText(string.format("|c%s%s|r %s |cff888888w%d%s|r", color, inc.d, date("%m-%d", inc.t), inc.w or 0, inc.disputed and " disputed" or ""))
    row.btn:SetShown(inc.x < 1 and not inc.disputed)
  end)
  nlist:SetPoint("TOPLEFT", 586, -222)
  nlist:SetSize(210, 180)
  local nstatus = UI.Label(frame, "", "GameFontDisableSmall")
  nstatus:SetPoint("TOPLEFT", 590, -408); nstatus:SetWidth(210)

  function view:Refresh()
    local guid = TA.playerGUID
    if not guid then return end
    if not TA.db.players[guid] then
      local _, class = UnitClass("player")
      TA.Sessions:TouchPlayer({ guid = guid, name = TA.playerName, class = class, level = UnitLevel("player"), guild = TA.SafeCall(GetGuildInfo, "player") })
    end
    local _, class = UnitClass("player")
    header:SetText(UI.ClassColored(TA.playerName or "You", class))
    trust:SetGUID(guid, TA.playerName)
    local items = {}
    for _, ev in ipairs(TA.Log:ForSubject(guid)) do
      if ev.signal == "endorse" then table.insert(items, 1, ev) end
    end
    list:SetItems(items)
    nlist:SetItems(TA.Network:MyEvents())
    local synced = TA.Network:SyncedAt()
    nstatus:SetText(not TA.Network:Enabled() and "Network is off (Transparency > consent.network)."
      or synced and ("Synced " .. TA.FormatAgo(synced) .. " via the companion app.") or "Waiting for the companion app.")
  end
  return view
end)

StaticPopupDialogs["TRUSTADVISOR_DISPUTE"] = {
  text = "Dispute this network event? Add context for the reviewer (max 200 characters). It is excluded from the network view until reviewed.",
  button1 = ACCEPT or "Dispute", button2 = CANCEL, hasEditBox = true, maxLetters = 200,
  timeout = 0, whileDead = true, hideOnEscape = true,
  OnAccept = function(self, inc)
    local box = self.editBox or self.EditBox
    local ok, err = TA.Network:Dispute(inc.id, box and box:GetText() or "")
    TA.Print(ok and "Dispute recorded. The companion app sends it on the next sync." or err)
  end,
}
