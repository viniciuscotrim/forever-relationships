-- Player card: Trust tab (bands + confidence + "Why?") and Affinity tab
-- (private summary, private yes/no, personal note). Trust and affinity are
-- shown side by side but never combined.
local _, TA = ...
local UI = TA.UI

-- Reusable trust panel (also used by My profile)
function UI.TrustPanel(parent)
  local p = CreateFrame("Frame", nil, parent)
  local hdr = { { "Dimension", 6 }, { "Band", 200 }, { "Confidence", 300 }, { "Evidence", 390 }, { "Network", 540 } }
  for _, h in ipairs(hdr) do
    local l = UI.Label(p, h[1], "GameFontNormalSmall"); l:SetPoint("TOPLEFT", h[2], 0)
  end
  p.rows = {}
  for i, d in ipairs(TA.Dimensions.list) do
    local row = CreateFrame("Frame", nil, p)
    row:SetSize(700, 20)
    row:SetPoint("TOPLEFT", 0, -16 - (i - 1) * 21)
    row.label = UI.Label(row, d.label, "GameFontHighlight"); row.label:SetPoint("LEFT", 6, 0)
    row.band = UI.Label(row, "", "GameFontHighlight"); row.band:SetPoint("LEFT", 200, 0)
    row.conf = UI.Label(row, "", "GameFontHighlightSmall"); row.conf:SetPoint("LEFT", 300, 0)
    row.ev = UI.Label(row, "", "GameFontHighlightSmall"); row.ev:SetPoint("LEFT", 390, 0)
    row.why = UI.Button(row, "Why?", 60, 18, function()
      local lines = TA.Dimensions.Explain(p.guid, d.key)
      UI.ShowText("Why this band? " .. (p.name or "") .. " · " .. d.label, lines)
    end)
    row.why:SetPoint("LEFT", 470, 0)
    row.net = UI.Label(row, "", "GameFontHighlightSmall"); row.net:SetPoint("LEFT", 540, 0)
    UI.Tooltip(row, d.label, function()
      return { d.type == "ratio" and "Ratio dimension: can go up or down (Bayesian average with a prior)."
        or "Accumulating dimension: positive evidence only, soft-capped. Cannot show Concern." }
    end)
    row.key = d.key
    p.rows[i] = row
  end
  p.context = UI.Label(p, "", "GameFontHighlightSmall")
  p.context:SetPoint("TOPLEFT", 6, -16 - #TA.Dimensions.list * 21 - 8)
  p.context:SetWidth(780)
  p.context:SetJustifyV("TOP")

  function p:SetGUID(guid, name)
    self.guid, self.name = guid, name
    local prof = TA.Dimensions.Profile(guid)
    local net = TA.Network:Profile(guid)
    for _, row in ipairs(self.rows) do
      local r = prof.dims[row.key]
      row.band:SetText(UI.BandText(r.band))
      row.conf:SetText(r.confidence)
      row.ev:SetText(string.format("%.1f", r.evidence))
      local nr = net and net.dims[row.key]
      if not TA.Network.ELIGIBLE[row.key] then row.net:SetText("|cff666666local only|r")
      elseif nr then row.net:SetText(UI.BandText(nr.band) .. " |cff888888" .. nr.confidence .. "|r")
      else row.net:SetText("|cff666666-|r") end
    end
    -- context facts (never scored)
    local lines = {}
    local pl = TA.db.players[guid]
    if pl and pl.guilds then
      local n, cutoff, prev = 0, TA.Now() - 90 * 86400, nil
      for _, g in ipairs(pl.guilds) do
        if prev and g.t >= cutoff and g.name ~= prev then n = n + 1 end
        prev = g.name
      end
      local cur = pl.guilds[#pl.guilds] and pl.guilds[#pl.guilds].name
      lines[#lines + 1] = string.format("Guild: %s  ·  Guild changes seen: %d in 90 days (context only, never scored)",
        (cur and cur ~= "") and ("<" .. cur .. ">") or "none", n)
    end
    local att = pl and pl.attunements
    if guid == TA.playerGUID then
      local own = TA.Protocol:OwnAttunements()
      att = { keys = own, selfReported = true }
    end
    if att and #att.keys > 0 then
      local labels = {}
      for _, k in ipairs(att.keys) do
        for _, a in ipairs(TA.Attunements.list) do if a.key == k then labels[#labels + 1] = a.label end end
      end
      lines[#lines + 1] = "Attunements (self-reported): " .. table.concat(labels, ", ")
    end
    lines[#lines + 1] = string.format("%d sessions witnessed by your client.", prof.sessions)
    self.context:SetText(table.concat(lines, "\n"))
  end
  return p
end

UI:RegisterView("card", function(frame)
  local view = { tab = "trust" }

  view.header = UI.Label(frame, "", "GameFontNormalLarge")
  view.header:SetPoint("TOPLEFT", 6, -4)
  view.sub = UI.Label(frame, "", "GameFontHighlightSmall")
  view.sub:SetPoint("TOPLEFT", view.header, "BOTTOMLEFT", 0, -4)

  local trustBtn = UI.Button(frame, "Trust", 90, 22, function() view.tab = "trust"; view:Refresh() end)
  trustBtn:SetPoint("TOPRIGHT", -100, -2)
  local affBtn = UI.Button(frame, "Affinity", 90, 22, function() view.tab = "affinity"; view:Refresh() end)
  affBtn:SetPoint("LEFT", trustBtn, "RIGHT", 4, 0)

  view.empty = UI.Label(frame, "Pick a player in the Players tab, or type /ta player <name>.", "GameFontDisable")
  view.empty:SetPoint("CENTER")

  view.trust = UI.TrustPanel(frame)
  view.trust:SetPoint("TOPLEFT", 0, -46)
  view.trust:SetPoint("BOTTOMRIGHT", 0, 30)

  view.endorseBtn = UI.Button(frame, "Play with them again", 170, 22, function()
    local ok, why = TA.Endorse:Give(view.guid, view.name)
    if not ok then TA.Print(why) end
    view:Refresh()
  end)
  view.endorseBtn:SetPoint("BOTTOMLEFT", 4, 2)
  UI.Tooltip(view.endorseBtn, "Endorse", function()
    return { "Adds a positive endorsement in your view (one per " .. TA.Params:Get("endorse.cooldownDays") .. " days).",
      TA.Params:Get("consent.shareEndorsements") and "Sharing is ON: they and your group will receive it." or "Sharing is OFF: it stays on your client." }
  end)

  view.friendBtn = UI.Button(frame, "Add friend", 110, 22, function()
    if C_FriendList and C_FriendList.AddFriend then C_FriendList.AddFriend(TA.ShortName(view.name), "Trust Advisor: questing partner") end
  end)
  view.friendBtn:SetPoint("LEFT", view.endorseBtn, "RIGHT", 6, 0)
  view.inviteBtn = UI.Button(frame, "Invite", 90, 22, function()
    local invite = (C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit
    if invite then invite(view.name) end
  end)
  view.inviteBtn:SetPoint("LEFT", view.friendBtn, "RIGHT", 6, 0)
  view.logBtn = UI.Button(frame, "Their events", 110, 22, function()
    UI.logFilterGUID = view.guid
    UI:Open("log")
  end)
  view.logBtn:SetPoint("LEFT", view.inviteBtn, "RIGHT", 6, 0)

  -- Affinity panel (private)
  local aff = CreateFrame("Frame", nil, frame)
  aff:SetPoint("TOPLEFT", 0, -46)
  aff:SetPoint("BOTTOMRIGHT", 0, 30)
  view.aff = aff
  local privacy = UI.Label(aff, "|cff888888Private: affinity is stored only on this character and is never transmitted or used for trust.|r", "GameFontHighlightSmall")
  privacy:SetPoint("TOPLEFT", 6, 0)
  aff.summary = UI.Label(aff, "", "GameFontHighlight")
  aff.summary:SetPoint("TOPLEFT", 6, -20)
  aff.summary:SetWidth(780)
  aff.verdict = UI.Label(aff, "", "GameFontHighlight")
  aff.verdict:SetPoint("TOPLEFT", 6, -66)
  local yes = UI.Button(aff, "Private yes", 110, 22, function()
    local a = TA.cdb.affinity[view.guid] or { sessions = {} }; TA.cdb.affinity[view.guid] = a
    a.privateYes, a.privateNo = TA.Now(), nil; view:Refresh()
  end)
  yes:SetPoint("TOPLEFT", 6, -86)
  local no = UI.Button(aff, "Private no", 110, 22, function() TA.Endorse:PrivateNo(view.guid, view.name); view:Refresh() end)
  no:SetPoint("LEFT", yes, "RIGHT", 6, 0)
  local clear = UI.Button(aff, "Clear", 70, 22, function()
    local a = TA.cdb.affinity[view.guid]; if a then a.privateYes, a.privateNo = nil, nil end; view:Refresh()
  end)
  clear:SetPoint("LEFT", no, "RIGHT", 6, 0)
  local noteLabel = UI.Label(aff, "Personal note (never transmitted):", "GameFontNormalSmall")
  noteLabel:SetPoint("TOPLEFT", 6, -122)
  local noteBg = CreateFrame("Frame", nil, aff, BackdropTemplateMixin and "BackdropTemplate" or nil)
  noteBg:SetPoint("TOPLEFT", 6, -138); noteBg:SetSize(560, 120)
  if noteBg.SetBackdrop then
    noteBg:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    noteBg:SetBackdropColor(0, 0, 0, 0.6)
  end
  local note = CreateFrame("EditBox", nil, noteBg)
  note:SetMultiLine(true); note:SetFontObject(ChatFontNormal); note:SetAutoFocus(false)
  note:SetPoint("TOPLEFT", 8, -8); note:SetPoint("BOTTOMRIGHT", -8, 8)
  note:SetMaxLetters(1000)
  note:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  note:SetScript("OnTextChanged", function(self, user)
    if not user or not view.guid then return end
    local a = TA.cdb.affinity[view.guid] or { sessions = {} }; TA.cdb.affinity[view.guid] = a
    a.note = self:GetText()
  end)
  noteBg:EnableMouse(true)
  noteBg:SetScript("OnMouseDown", function() note:SetFocus() end)
  aff.note = note

  function view:Refresh()
    local guid = UI.cardGUID
    self.guid = guid
    local p = guid and (TA.db.players[guid] or (UI.transient and UI.transient.guid == guid and UI.transient))
    local has = p ~= nil
    self.empty:SetShown(not has)
    for _, w in ipairs({ self.trust, self.aff, self.endorseBtn, self.friendBtn, self.inviteBtn, self.logBtn, trustBtn, affBtn }) do w:SetShown(has) end
    if not has then self.header:SetText(""); self.sub:SetText(""); return end
    self.name = p.name
    self.header:SetText(UI.ClassColored(p.name, p.class))
    local nd = TA.Params:AnyScoringNonDefault() and (" " .. UI.NONDEFAULT_MARK .. " non-default parameters") or ""
    -- match-card facts: presence and endorsements received
    local extra = {}
    local near = TA.Presence.nearby[guid]
    if near then
      extra[#extra + 1] = string.format("|cff66ccffNearby: %s · lvl %s%s%s|r", near.zone or "?", near.level or "?",
        near.lfg and " · LFG" or "", (near.overlap or 0) > 0 and (" · " .. near.overlap .. " shared quests") or "")
    end
    local endorsements = 0
    for _, ev in ipairs(TA.Log:ForSubject(guid)) do if ev.signal == "endorse" then endorsements = endorsements + 1 end end
    extra[#extra + 1] = endorsements .. " endorsement" .. (endorsements == 1 and "" or "s") .. " received"
    if TA.Network and TA.Network:HasData(guid) then extra[#extra + 1] = "|cffb48cffNetwork data available|r" end
    self.sub:SetText(string.format("%s · %s · |cff888888Your view%s|r\n%s",
      p.transient and "Never grouped with you" or ("Level " .. tostring(p.level or "?") .. " · first seen " .. TA.FormatAgo(p.firstSeen)),
      p.transient and ("level " .. tostring(p.level or "?")) or ("last seen " .. TA.FormatAgo(p.lastSeen)), nd, table.concat(extra, " · ")))
    self.trust:SetShown(self.tab == "trust")
    self.aff:SetShown(self.tab == "affinity")
    if self.tab == "trust" then
      self.trust:SetGUID(guid, p.name)
    else
      local a = TA.cdb.affinity[guid] or {}
      self.aff.summary:SetText(UI.AffinitySummary(guid))
      self.aff.verdict:SetText(a.privateYes and "|cff66ff66Your private verdict: yes|r" or a.privateNo and "|cffff9933Your private verdict: no|r" or "|cff888888No private verdict.|r")
      if not self.aff.note:HasFocus() then self.aff.note:SetText(a.note or "") end
    end
    local can = TA.Endorse:CanEndorse(guid)
    self.endorseBtn:SetEnabled(can)
    local isFriend = C_FriendList and C_FriendList.IsFriend and TA.SafeCall(C_FriendList.IsFriend, guid)
    self.friendBtn:SetEnabled(not isFriend)
  end
  return view
end)
