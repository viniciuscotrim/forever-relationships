-- Relationship: everything the game recorded while you played with someone
-- (Information) and the patterns computed for you (Knowledge), plus the public
-- profile they chose to publish, if any. Opened from the Circle or by
-- right-clicking a player ("Relationship").
local _, FR = ...
local UI = FR.UI

UI:RegisterView("relationship", function(frame)
  local view = {}
  view.header = UI.Label(frame, "", "GameFontNormalLarge"); view.header:SetPoint("TOPLEFT", 6, -4)
  view.sub = UI.Label(frame, "", "GameFontHighlightSmall"); view.sub:SetPoint("TOPLEFT", view.header, "BOTTOMLEFT", 0, -4)
  view.empty = UI.Label(frame, "Pick someone in your Circle, or right-click a player and choose Relationship.", "GameFontDisable")
  view.empty:SetPoint("CENTER")

  local function Column(x, title)
    local c = CreateFrame("Frame", nil, frame)
    c:SetPoint("TOPLEFT", x, -46); c:SetSize(380, 380)
    c.title = UI.Label(c, title, "GameFontNormal"); c.title:SetPoint("TOPLEFT", 0, 0)
    c.rows = {}
    return c
  end
  view.info = Column(6, "Information |cff8f97ab· facts the game recorded|r")
  view.know = Column(400, "Knowledge |cff8f97ab· patterns, for you|r")

  local function Fill(col, rows)
    for i, r in ipairs(rows) do
      local row = col.rows[i]
      if not row then
        row = {}
        row.l = UI.Label(col, "", "GameFontHighlightSmall"); row.l:SetPoint("TOPLEFT", 0, -20 - (i - 1) * 20); row.l:SetWidth(160)
        row.v = UI.Label(col, "", "GameFontHighlight"); row.v:SetPoint("TOPLEFT", 164, -20 - (i - 1) * 20); row.v:SetWidth(214); row.v:SetWordWrap(false)
        col.rows[i] = row
      end
      row.l:SetText(UI.MUTED .. r[1] .. "|r"); row.v:SetText(r[2]); row.l:Show(); row.v:Show()
    end
    for i = #rows + 1, #col.rows do col.rows[i].l:Hide(); col.rows[i].v:Hide() end
  end

  view.profileBox = UI.Label(frame, "", "GameFontHighlightSmall")
  view.profileBox:SetPoint("TOPLEFT", 400, -300); view.profileBox:SetWidth(380); view.profileBox:SetJustifyV("TOP")

  view.friendBtn = UI.Button(frame, "Add friend", 110, 22, function()
    if C_FriendList and C_FriendList.AddFriend then C_FriendList.AddFriend(FR.ShortName(view.name), "Forever Relationships") end
  end)
  view.friendBtn:SetPoint("BOTTOMLEFT", 4, 2)
  view.inviteBtn = UI.Button(frame, "Invite", 90, 22, function()
    local invite = (C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit
    if invite then invite(view.name) end
  end)
  view.inviteBtn:SetPoint("LEFT", view.friendBtn, "RIGHT", 6, 0)
  view.logBtn = UI.Button(frame, "Their events", 110, 22, function() UI.logFilterGUID = view.guid; UI:Open("log") end)
  view.logBtn:SetPoint("LEFT", view.inviteBtn, "RIGHT", 6, 0)

  function view:Refresh()
    local guid = UI.cardGUID
    local p = guid and FR.db.players[guid]
    self.guid = guid
    local has = p ~= nil
    self.empty:SetShown(not has)
    for _, w in ipairs({ self.info, self.know, self.profileBox, self.friendBtn, self.inviteBtn, self.logBtn }) do w:SetShown(has) end
    if not has then self.header:SetText(""); self.sub:SetText(""); return end
    self.name = p.name
    self.header:SetText(UI.ClassColored(p.name, p.class))
    local bits = { "Level " .. tostring(p.level or "?") }
    if p.race then bits[#bits + 1] = p.race end
    if p.faction then bits[#bits + 1] = p.faction end
    local isFriend = C_FriendList and C_FriendList.IsFriend and FR.SafeCall(C_FriendList.IsFriend, guid)
    if isFriend then bits[#bits + 1] = "|cff66ff66your friend|r" end
    self.sub:SetText(table.concat(bits, " · "))
    self.friendBtn:SetEnabled(not isFriend)

    local r = FR.Rel:Compute(guid)
    local info, know = {}, {}
    for _, f in ipairs(FR.Rel.FIELDS) do
      local row = { f.label, f.value(r) }
      if f.layer == "info" then info[#info + 1] = row else know[#know + 1] = row end
    end
    Fill(self.info, info)
    Fill(self.know, know)

    local prof = FR.Cloud:Profile(guid)
    if prof and prof.items and #prof.items > 0 then
      local L = { UI.GOLD .. "Public profile|r " .. UI.MUTED .. "(published by them)|r" }
      for _, it in ipairs(prof.items) do
        L[#L + 1] = string.format("%s: |cffffffff%s|r %s", it.label or it.key, tostring(it.value),
          it.official and "|cff66ccff[Official]|r" or "|cff8f97ab[Recorded by the addon]|r")
      end
      self.profileBox:SetText(table.concat(L, "\n"))
    else
      self.profileBox:SetText(UI.MUTED .. "No public profile." .. "|r")
    end
  end
  return view
end)

-- Right-click a player anywhere -> "Relationship" (modern Menu API, if present)
FR:Listen("LOGIN", function()
  if not (Menu and Menu.ModifyMenu) then return end
  local function add(owner, root, ctx)
    local guid = ctx and (ctx.unit and FR.Clean(UnitGUID(ctx.unit)) or (ctx.name and FR.Sessions:GUIDByName(ctx.name)))
    if not guid or guid == FR.playerGUID or not FR.db.players[guid] then return end
    root:CreateDivider()
    root:CreateButton("Relationship", function() UI:OpenPlayer(guid) end)
  end
  for _, tag in ipairs({ "MENU_UNIT_PLAYER", "MENU_UNIT_PARTY", "MENU_UNIT_RAID_PLAYER", "MENU_UNIT_FRIEND", "MENU_UNIT_TARGET", "MENU_UNIT_FOCUS" }) do
    pcall(Menu.ModifyMenu, tag, add)
  end
end)
