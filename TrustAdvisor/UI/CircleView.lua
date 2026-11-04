-- Circle: everyone you've played with, most time together first, plus nearby
-- Forever Relationships users and suggestions from the community (opt-in participants only).
local _, TA = ...
local UI = TA.UI

UI:RegisterView("circle", function(frame)
  local view = { mode = "circle" }

  local search = UI.EditBox(frame, 200)
  search:SetPoint("TOPLEFT", 6, -4)
  local hint = UI.Label(search, "Search name or guild", "GameFontDisableSmall")
  hint:SetPoint("LEFT", 4, 0)
  search:SetScript("OnTextChanged", function(self) hint:SetShown(self:GetText() == ""); view:Refresh() end)

  local modes = { { "circle", "My circle" }, { "suggested", "Suggested" }, { "nearby", "Nearby" } }
  local prev
  view.modeButtons = {}
  for _, m in ipairs(modes) do
    local b = UI.Button(frame, m[2], 100, 22, function() view.mode = m[1]; view:Refresh() end)
    if prev then b:SetPoint("LEFT", prev, "RIGHT", 4, 0) else b:SetPoint("LEFT", search, "RIGHT", 10, 0) end
    view.modeButtons[m[1]] = b
    prev = b
  end
  local count = UI.Label(frame, "", "GameFontDisableSmall")
  count:SetPoint("LEFT", prev, "RIGHT", 10, 0)

  local cols = { { "Name", 6 }, { "Time together", 230 }, { "Days", 340 }, { "Last together", 400 }, { "Completed", 560 }, { "", 680 } }
  view.header = {}
  for i, c in ipairs(cols) do
    local h = UI.Label(frame, c[1], "GameFontNormalSmall"); h:SetPoint("TOPLEFT", c[2], -32); view.header[i] = h
  end

  local list = UI.List(frame, 22, 18, function(row)
    row.cells = {}
    for i, c in ipairs(cols) do
      local fs = UI.Label(row, "", i == 1 and "GameFontHighlight" or "GameFontHighlightSmall")
      fs:SetPoint("LEFT", c[2], 0)
      fs:SetWidth((cols[i + 1] and cols[i + 1][2] or 790) - c[2] - 6)
      fs:SetWordWrap(false)
      row.cells[i] = fs
    end
    row:SetScript("OnClick", function(self)
      if self.guid and TA.db.players[self.guid] then UI:OpenPlayer(self.guid) end
    end)
  end, function(row, item)
    row.guid = item.guid
    local name = UI.ClassColored(TA.ShortName(item.name or "?"), item.class) .. (item.level and (" " .. UI.MUTED .. item.level .. "|r") or "")
    if item.r then
      local r = item.r
      row.cells[1]:SetText(name)
      row.cells[2]:SetText(TA.FormatDuration(r.seconds))
      row.cells[3]:SetText(tostring(r.days))
      row.cells[4]:SetText(r.last and (TA.FormatAgo(r.last) .. " · " .. (r.lastWhere or "")) or "-")
      row.cells[5]:SetText(r.dungeons + r.raids > 0 and ((r.dungeons + r.raids) .. " together") or "-")
      row.cells[6]:SetText(item.rank and item.rank <= 10 and (UI.GOLD .. "#" .. item.rank .. "|r") or "")
    else
      row.cells[1]:SetText(name)
      row.cells[2]:SetText(item.where or "")
      row.cells[3]:SetText("")
      row.cells[4]:SetText(item.reason or "")
      row.cells[5]:SetText(item.extra or "")
      row.cells[6]:SetText("")
    end
  end)
  list:SetPoint("TOPLEFT", 0, -48)
  list:SetPoint("BOTTOMRIGHT", 0, 0)

  function view:Refresh()
    for k, b in pairs(self.modeButtons) do if k == self.mode then b:LockHighlight() else b:UnlockHighlight() end end
    local q = (search:GetText() or ""):lower()
    local items = {}
    if self.mode == "circle" then
      self.header[2]:SetText("Time together"); self.header[3]:SetText("Days"); self.header[4]:SetText("Last together"); self.header[5]:SetText("Completed")
      for _, e in ipairs(TA.Rel:Circle()) do
        local p = TA.db.players[e.guid] or {}
        local guild = p.guilds and p.guilds[#p.guilds] and p.guilds[#p.guilds].name or ""
        if q == "" or (e.name or ""):lower():find(q, 1, true) or guild:lower():find(q, 1, true) then items[#items + 1] = e end
      end
      count:SetText(#items .. " players")
    elseif self.mode == "suggested" then
      self.header[2]:SetText("Realm"); self.header[3]:SetText(""); self.header[4]:SetText("Why"); self.header[5]:SetText("")
      for _, s in ipairs(TA.Cloud:Suggestions()) do
        items[#items + 1] = { name = s.name, class = s.class and s.class:upper(), level = s.level, where = s.realm, reason = s.reason }
      end
      count:SetText(TA.Params:Get("consent.community") and (#items .. " suggestions from players who chose to be recommended")
        or "Turn on Community in Privacy to get suggestions.")
    else
      self.header[2]:SetText("Zone"); self.header[3]:SetText(""); self.header[4]:SetText(""); self.header[5]:SetText("Shared quests")
      if not TA.Presence:Active() then
        count:SetText(TA.db.invisible and "Invisible mode is on." or "Nearby is off (Privacy > presence.enabled).")
      end
      for _, p in ipairs(TA.Presence:Matches()) do
        local known = TA.db.players[p.guid] or {}
        items[#items + 1] = { guid = p.guid, name = p.name, class = known.class, level = p.level, where = p.zone,
          reason = p.lfg and "|cff66ff66looking for group|r" or "", extra = p.overlap > 0 and (p.overlap .. " shared") or "" }
      end
    end
    list:SetItems(items)
  end
  return view
end)
