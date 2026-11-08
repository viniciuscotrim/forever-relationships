-- Relationship: everything the game recorded while you played with someone
-- (Information) and the patterns computed for you (Knowledge), plus the public
-- profile they chose to publish, if any. Opened from the Circle or by
-- right-clicking a player ("Relationship").
local _, FR = ...
local UI = FR.UI
local L = FR.L

UI:RegisterView("relationship", function(frame)
  local view = {}
  view.header = UI.Label(frame, "", "GameFontNormalLarge"); view.header:SetPoint("TOPLEFT", 6, -4)
  view.sub = UI.Label(frame, "", "GameFontHighlightSmall"); view.sub:SetPoint("TOPLEFT", view.header, "BOTTOMLEFT", 0, -4)
  view.empty = UI.Label(frame, L["Pick someone in your Circle, or right-click a player and choose Relationship."], "GameFontDisable")
  view.empty:SetPoint("CENTER")

  local function Column(x, title)
    local c = CreateFrame("Frame", nil, frame)
    c:SetPoint("TOPLEFT", x, -46); c:SetSize(380, 380)
    c.title = UI.Label(c, title, "GameFontNormal"); c.title:SetPoint("TOPLEFT", 0, 0)
    c.rows = {}
    return c
  end
  view.info = Column(6, L["Information"] .. " |cff8f97ab· " .. L["facts the game recorded"] .. "|r")
  view.know = Column(400, L["Knowledge"] .. " |cff8f97ab· " .. L["patterns, for you"] .. "|r")

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

  view.friendBtn = UI.Button(frame, L["Add friend"], 110, 22, function()
    if C_FriendList and C_FriendList.AddFriend then C_FriendList.AddFriend(FR.ShortName(view.name), "Forever Relationships") end
  end)
  view.friendBtn:SetPoint("BOTTOMLEFT", 4, 2)
  view.inviteBtn = UI.Button(frame, L["Invite"], 90, 22, function()
    local invite = (C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit
    if invite then invite(view.name) end
  end)
  view.inviteBtn:SetPoint("LEFT", view.friendBtn, "RIGHT", 6, 0)
  view.logBtn = UI.Button(frame, L["Their events"], 110, 22, function() UI.logFilterGUID = view.guid; UI:Open("log") end)
  view.logBtn:SetPoint("LEFT", view.inviteBtn, "RIGHT", 6, 0)
  view.groupsBtn = UI.Button(frame, L["Groups"], 110, 22, function() if view.guid then UI.GroupPicker:Open(view.guid) end end)
  view.groupsBtn:SetPoint("LEFT", view.logBtn, "RIGHT", 6, 0)
  view.groupsLine = UI.Label(frame, "", "GameFontHighlightSmall")
  view.groupsLine:SetPoint("LEFT", view.groupsBtn, "RIGHT", 10, 0); view.groupsLine:SetWidth(330); view.groupsLine:SetWordWrap(false)

  function view:Refresh()
    local guid = UI.cardGUID
    local p = guid and FR.db.players[guid]
    local rv = guid and FR.Rivals and FR.Rivals:Get(guid)
    self.guid = guid
    local has = p ~= nil or rv ~= nil
    self.empty:SetShown(not has)
    for _, w in ipairs({ self.info, self.know, self.profileBox, self.groupsBtn, self.groupsLine }) do w:SetShown(has) end
    for _, w in ipairs({ self.friendBtn, self.inviteBtn, self.logBtn }) do w:SetShown(p ~= nil) end
    if not has then self.header:SetText(""); self.sub:SetText(""); return end
    local groups = FR.Groups:Label(guid)
    self.groupsLine:SetText(groups ~= "" and (UI.MUTED .. L["Groups"] .. ":|r " .. groups) or (UI.MUTED .. L["No group yet. Click to add one."] .. "|r"))
    if not p then
      -- an opposite-faction player: crossings, battles, victories and deaths
      self.name = rv.name
      self.header:SetText(UI.ClassColored(rv.name or "?", rv.class) .. "  |cffff5555" .. L["Rival"] .. "|r")
      local bits = { L["Level %s"]:format(tostring(rv.level or "?")) }
      if rv.race then bits[#bits + 1] = rv.race end
      if rv.faction then bits[#bits + 1] = rv.faction end
      if rv.guild then bits[#bits + 1] = "<" .. rv.guild .. ">" end
      self.sub:SetText(table.concat(bits, " · "))
      local info, know = FR.Rivals:Rows(rv)
      self.info.title:SetText(L["Rivalry"] .. " |cff8f97ab· " .. L["facts the game recorded"] .. "|r")
      self.know.title:SetText(L["Compared with all your rivals"])
      Fill(self.info, info)
      Fill(self.know, know)
      self.profileBox:SetText("")
      return
    end
    self.info.title:SetText(L["Information"] .. " |cff8f97ab· " .. L["facts the game recorded"] .. "|r")
    self.know.title:SetText(L["Knowledge"] .. " |cff8f97ab· " .. L["patterns, for you"] .. "|r")
    self.name = p.name
    self.header:SetText(UI.ClassColored(p.name, p.class))
    local bits = { L["Level %s"]:format(tostring(p.level or "?")) }
    if p.race then bits[#bits + 1] = p.race end
    if p.faction then bits[#bits + 1] = p.faction end
    local isFriend = C_FriendList and C_FriendList.IsFriend and FR.SafeCall(C_FriendList.IsFriend, guid)
    if isFriend then bits[#bits + 1] = "|cff66ff66" .. L["your friend"] .. "|r" end
    self.sub:SetText(table.concat(bits, " · "))
    self.friendBtn:SetEnabled(not isFriend)

    local r = FR.Rel:Compute(guid)
    local info, know = {}, {}
    for _, f in ipairs(FR.Rel.FIELDS) do
      local row = { L[f.label], f.value(r) }
      if f.layer == "info" then info[#info + 1] = row else know[#know + 1] = row end
    end
    Fill(self.info, info)
    Fill(self.know, know)

    local prof = FR.Cloud:Profile(guid)
    if prof and prof.items and #prof.items > 0 then
      local lines = { UI.GOLD .. L["Public profile"] .. "|r " .. UI.MUTED .. L["(published by them)"] .. "|r" }
      for _, it in ipairs(prof.items) do
        lines[#lines + 1] = string.format("%s: |cffffffff%s|r %s", L[it.label or it.key], tostring(it.value),
          it.official and ("|cff66ccff[" .. L["Official"] .. "]|r") or ("|cff8f97ab[" .. L["Recorded by the addon"] .. "]|r"))
      end
      self.profileBox:SetText(table.concat(lines, "\n"))
    else
      self.profileBox:SetText(UI.MUTED .. L["No public profile."] .. "|r")
    end
  end
  return view
end)

-- Right-click a player anywhere -> "Relationship" (modern Menu API, if present)
FR:Listen("LOGIN", function()
  if not (Menu and Menu.ModifyMenu) then return end
  local function add(owner, root, ctx)
    local guid = ctx and (ctx.unit and FR.Clean(UnitGUID(ctx.unit)) or (ctx.name and FR.Sessions:GUIDByName(ctx.name)))
    if not guid or guid == FR.playerGUID or not (FR.db.players[guid] or FR.Rivals:Get(guid)) then return end
    root:CreateDivider()
    root:CreateButton(L["Relationship"], function() UI:OpenPlayer(guid) end)
    root:CreateButton(L["Groups"], function() UI.GroupPicker:Open(guid) end)
  end
  for _, tag in ipairs({ "MENU_UNIT_PLAYER", "MENU_UNIT_PARTY", "MENU_UNIT_RAID_PLAYER", "MENU_UNIT_FRIEND", "MENU_UNIT_TARGET", "MENU_UNIT_FOCUS" }) do
    pcall(Menu.ModifyMenu, tag, add)
  end
end)
