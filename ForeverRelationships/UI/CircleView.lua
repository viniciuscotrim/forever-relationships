-- Circle: everyone you've played with, most time together first; the rivals you
-- crossed and fought; nearby Forever Relationships users; and suggestions from
-- the community (opt-in participants only). Every row has a Groups button.
local _, FR = ...
local UI = FR.UI
local L = FR.L

UI:RegisterView("circle", function(frame)
  local view = { mode = "circle", group = nil }

  local search = UI.EditBox(frame, 170)
  search:SetPoint("TOPLEFT", 6, -4)
  local hint = UI.Label(search, L["Search name or guild"], "GameFontDisableSmall")
  hint:SetPoint("LEFT", 4, 0)
  search:SetScript("OnTextChanged", function(self) hint:SetShown(self:GetText() == ""); view:Refresh() end)

  local modes = { { "circle", L["My circle"] }, { "rivals", L["Rivals"] }, { "suggested", L["Suggested"] }, { "nearby", L["Nearby"] } }
  local prev
  view.modeButtons = {}
  for _, m in ipairs(modes) do
    local b = UI.Button(frame, m[2], 86, 22, function() view.mode = m[1]; view:Refresh() end)
    if prev then b:SetPoint("LEFT", prev, "RIGHT", 3, 0) else b:SetPoint("LEFT", search, "RIGHT", 8, 0) end
    view.modeButtons[m[1]] = b
    prev = b
  end
  -- group filter: left-click cycles through the groups, right-click shows everyone
  view.groupBtn = UI.Button(frame, "", 130, 22)
  view.groupBtn:SetPoint("LEFT", prev, "RIGHT", 8, 0)
  view.groupBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  view.groupBtn:SetScript("OnClick", function(_, button)
    if button == "RightButton" then view.group = nil
    else
      local all, nextKey = FR.Groups:All(), nil
      if not view.group then nextKey = all[1] and all[1].key
      else
        for i, g in ipairs(all) do if g.key == view.group then nextKey = all[i + 1] and all[i + 1].key end end
      end
      view.group = nextKey
    end
    view:Refresh()
  end)
  UI.Tooltip(view.groupBtn, L["Groups"], { L["Click: show one group at a time."], L["Right-click: show everyone."] })
  local manage = UI.Button(frame, L["Groups"], 70, 22, function() UI.GroupPicker:Open(nil) end)
  manage:SetPoint("LEFT", view.groupBtn, "RIGHT", 3, 0)
  UI.Tooltip(manage, L["Your groups"], { L["Create, rename or delete your own groups."] })

  local count = UI.Label(frame, "", "GameFontDisableSmall")
  count:SetPoint("TOPRIGHT", -30, -32)

  local cols = { { "name", 6 }, { "c2", 200 }, { "c3", 300 }, { "c4", 370 }, { "c5", 540 }, { "rank", 650 }, { "groups", 690 } }
  view.header = {}
  for i, c in ipairs(cols) do
    local h = UI.Label(frame, "", "GameFontNormalSmall"); h:SetPoint("TOPLEFT", c[2], -32); view.header[i] = h
  end

  local function Known(guid) return guid and (FR.db.players[guid] or (FR.Rivals and FR.Rivals:Get(guid))) end

  local list = UI.List(frame, 22, 18, function(row)
    row.cells = {}
    for i = 1, 6 do
      local c = cols[i]
      local fs = UI.Label(row, "", i == 1 and "GameFontHighlight" or "GameFontHighlightSmall")
      fs:SetPoint("LEFT", c[2], 0)
      fs:SetWidth(cols[i + 1][2] - c[2] - 6)
      fs:SetWordWrap(false)
      row.cells[i] = fs
    end
    row.groups = UI.Button(row, L["Groups"], 74, 18, function() if row.guid then UI.GroupPicker:Open(row.guid) end end)
    row.groups:SetPoint("LEFT", cols[7][2], 0)
    row.groups:SetScript("OnEnter", function(self)
      if not row.guid then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText(L["Groups"], 1, 1, 1)
      local label = FR.Groups:Label(row.guid)
      GameTooltip:AddLine(label ~= "" and label or L["No group yet. Click to add one."], nil, nil, nil, true)
      GameTooltip:Show()
    end)
    row.groups:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:SetScript("OnClick", function(self)
      if Known(self.guid) then UI:OpenPlayer(self.guid) end
    end)
  end, function(row, item)
    row.guid = item.guid
    local name = UI.ClassColored(FR.ShortName(item.name or "?"), item.class) .. (item.level and (" " .. UI.MUTED .. item.level .. "|r") or "")
    row.cells[1]:SetText(name)
    for i = 2, 6 do row.cells[i]:SetText(item.cells and item.cells[i] or "") end
    local n = 0
    if item.guid then for _ in pairs(FR.Groups:Of(item.guid)) do n = n + 1 end end
    row.groups:SetText(n > 0 and (L["Groups"] .. " (" .. n .. ")") or L["Groups"])
    row.groups:SetShown(Known(item.guid) ~= nil)
  end)
  list:SetPoint("TOPLEFT", 0, -48)
  list:SetPoint("BOTTOMRIGHT", 0, 0)

  local function Headers(...)
    local h = { ... }
    view.header[1]:SetText(L["Name"])
    for i = 2, 6 do view.header[i]:SetText(h[i - 1] or "") end
    view.header[7]:SetText("")
  end

  local function Matches(q, name, guid)
    if view.group and not (guid and FR.Groups:Has(guid, view.group)) then return false end
    if q == "" then return true end
    if (name or ""):lower():find(q, 1, true) then return true end
    local p = guid and FR.db.players[guid]
    local guild = p and p.guilds and p.guilds[#p.guilds] and p.guilds[#p.guilds].name or (guid and FR.Rivals:Get(guid) or {}).guild or ""
    return guild:lower():find(q, 1, true) ~= nil
  end

  function view:Refresh()
    for k, b in pairs(self.modeButtons) do if k == self.mode then b:LockHighlight() else b:UnlockHighlight() end end
    self.groupBtn:SetText(self.group and (FR.Groups:Name(self.group) or L["All groups"]) or L["All groups"])
    if self.group and not FR.Groups:Name(self.group) then self.group = nil end
    local q = (search:GetText() or ""):lower()
    local items = {}
    if self.mode == "circle" then
      Headers(L["Time together"], L["Days"], L["Last together"], L["Completed"], "")
      for _, e in ipairs(FR.Rel:Circle()) do
        if Matches(q, e.name, e.guid) then
          local r = e.r
          e.cells = { nil, FR.FormatDuration(r.seconds), tostring(r.days),
            r.last and (FR.FormatAgo(r.last) .. " · " .. (r.lastWhere or "")) or "-",
            r.dungeons + r.raids > 0 and L["%d together"]:format(r.dungeons + r.raids) or "-",
            e.rank and e.rank <= 10 and (UI.GOLD .. "#" .. e.rank .. "|r") or "" }
          items[#items + 1] = e
        end
      end
      count:SetText(FR.Plural(#items, "%d player", "%d players"))
    elseif self.mode == "rivals" then
      Headers(L["Crossed"], L["Battles"], L["Won · Lost"], L["Last seen"], "")
      local pct = FR.Rivals.Pct
      for _, e in ipairs(FR.Rivals:List()) do
        if Matches(q, e.name, e.guid) then
          local rv = e.rv
          e.cells = { nil, tostring(rv.crossed), ("%d (%d%%)"):format(rv.battles, pct(rv.battles, rv.crossed)),
            ("|cff66ff66%d (%d%%)|r · |cffff6666%d (%d%%)|r"):format(rv.wins, pct(rv.wins, rv.battles), rv.deaths, pct(rv.deaths, rv.battles)),
            rv.lastSeen and FR.FormatAgo(rv.lastSeen) or "-", "" }
          items[#items + 1] = e
        end
      end
      local t = FR.Rivals:Totals()
      count:SetText(L["%d rivals · %d battles · won %d%% · lost %d%%"]:format(t.players, t.battles, pct(t.wins, t.battles), pct(t.deaths, t.battles)))
    elseif self.mode == "suggested" then
      Headers(L["Realm"], "", L["Why"], "", "")
      for _, s in ipairs(FR.Cloud:Suggestions()) do
        items[#items + 1] = { name = s.name, class = s.class and s.class:upper(), level = s.level, cells = { nil, s.realm or "", "", s.reason or "", "", "" } }
      end
      count:SetText(FR.Params:Get("consent.community") and L["%d suggestions from players who chose to be recommended"]:format(#items)
        or L["Turn on Community in Privacy to get suggestions."])
    else
      Headers(L["Zone"], "", "", L["Shared quests"], "")
      if not FR.Presence:Active() then
        count:SetText(FR.db.invisible and L["Invisible mode is on."] or L["Nearby is off (Privacy > presence.enabled)."])
      else
        count:SetText("")
      end
      for _, p in ipairs(FR.Presence:Matches()) do
        local known = FR.db.players[p.guid] or {}
        if Matches(q, p.name, p.guid) then
          items[#items + 1] = { guid = p.guid, name = p.name, class = known.class, level = p.level,
            cells = { nil, p.zone or "", "", p.lfg and ("|cff66ff66" .. L["looking for group"] .. "|r") or "",
              p.overlap > 0 and L["%d shared"]:format(p.overlap) or "", "" } }
        end
      end
    end
    list:SetItems(items)
  end
  FR:Listen("GROUPS_CHANGED", function() if frame:IsShown() then view:Refresh() end end)
  return view
end)
