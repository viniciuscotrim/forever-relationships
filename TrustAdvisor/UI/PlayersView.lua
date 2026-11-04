-- Players tab: everyone you've grouped with, plus a Nearby (presence) mode.
local _, TA = ...
local UI = TA.UI

UI:RegisterView("players", function(frame)
  local view = { mode = "all" }

  local search = UI.EditBox(frame, 200)
  search:SetPoint("TOPLEFT", 6, -4)
  local hint = UI.Label(search, "Search name or guild", "GameFontDisableSmall")
  hint:SetPoint("LEFT", 4, 0)
  search:SetScript("OnTextChanged", function(self)
    hint:SetShown(self:GetText() == "")
    view:Refresh()
  end)

  local modeBtn = UI.Button(frame, "Show nearby", 120, 22)
  modeBtn:SetPoint("LEFT", search, "RIGHT", 10, 0)
  modeBtn:SetScript("OnClick", function()
    view.mode = view.mode == "all" and "nearby" or "all"
    modeBtn:SetText(view.mode == "all" and "Show nearby" or "Show all")
    view:Refresh()
  end)
  UI.Tooltip(modeBtn, "Nearby", { "Trust Advisor users broadcasting presence near you (requires presence.enabled). Presence data is never saved." })

  local count = UI.Label(frame, "", "GameFontDisableSmall")
  count:SetPoint("LEFT", modeBtn, "RIGHT", 10, 0)

  -- header
  local cols = { { "Name", 6 }, { "Last seen", 230 }, { "Sessions", 320 }, { "Trust (your view)", 400 } }
  for _, c in ipairs(cols) do
    local h = UI.Label(frame, c[1], "GameFontNormalSmall")
    h:SetPoint("TOPLEFT", c[2], -32)
  end

  local list = UI.List(frame, 22, 18, function(row)
    row.name = UI.Label(row, "", "GameFontHighlight"); row.name:SetPoint("LEFT", 6, 0); row.name:SetWidth(220)
    row.seen = UI.Label(row, "", "GameFontHighlightSmall"); row.seen:SetPoint("LEFT", 230, 0)
    row.sessions = UI.Label(row, "", "GameFontHighlightSmall"); row.sessions:SetPoint("LEFT", 320, 0)
    row.strip = UI.BandStrip(row, 12); row.strip:SetPoint("LEFT", 400, 0)
    row.extra = UI.Label(row, "", "GameFontHighlightSmall"); row.extra:SetPoint("LEFT", 570, 0); row.extra:SetWidth(190)
    row:SetScript("OnClick", function(self)
      if not self.guid then return end
      if self.item and self.item.nearby and not TA.db.players[self.guid] then
        UI.transient = { guid = self.guid, name = self.item.name, level = self.item.level, transient = true }
      end
      UI:OpenPlayer(self.guid)
    end)
  end, function(row, item)
    row.guid = item.guid
    row.item = item
    row.name:SetText(UI.ClassColored(TA.ShortName(item.name), item.class) .. (item.level and ("  |cff888888" .. item.level .. "|r") or ""))
    local prof = TA.Dimensions.Profile(item.guid)
    row.seen:SetText(item.nearby and ("|cff66ccff" .. (item.zone or "nearby") .. "|r") or TA.FormatAgo(item.lastSeen))
    row.sessions:SetText(tostring(prof.sessions))
    row.strip:SetProfile(prof)
    local notable = {}
    for _, k in ipairs(prof.order) do
      local b = prof.dims[k].band
      if b == "Exemplary" or b == "Concern" then notable[#notable + 1] = UI.BandText(b == "Exemplary" and "Exemplary" or "Concern") .. " " .. prof.dims[k].label end
    end
    if item.nearby then
      local bits = {}
      if item.lfg then bits[#bits + 1] = "|cff66ff66LFG|r" end
      if item.overlap and item.overlap > 0 then bits[#bits + 1] = item.overlap .. " shared quests" end
      row.extra:SetText(table.concat(bits, " · "))
    else
      row.extra:SetText(notable[1] or "")
    end
  end)
  list:SetPoint("TOPLEFT", 0, -48)
  list:SetPoint("BOTTOMRIGHT", 0, 0)

  function view:Refresh()
    local q = (search:GetText() or ""):lower()
    local items = {}
    if self.mode == "nearby" then
      if not TA.Presence:Active() then
        count:SetText(TA.db.invisible and "Invisible mode is on." or "Presence is off (Transparency > Social > presence.enabled).")
      end
      for _, p in ipairs(TA.Presence:Matches()) do
        local known = TA.db.players[p.guid] or {}
        items[#items + 1] = { guid = p.guid, name = p.name, class = known.class, level = p.level, nearby = true,
          zone = p.zone, lfg = p.lfg, overlap = p.overlap }
      end
    else
      for guid, p in pairs(TA.db.players) do
        if guid ~= TA.playerGUID then
          local guild = p.guilds and p.guilds[#p.guilds] and p.guilds[#p.guilds].name or ""
          if q == "" or (p.name or ""):lower():find(q, 1, true) or guild:lower():find(q, 1, true) then
            items[#items + 1] = { guid = guid, name = p.name or "?", class = p.class, level = p.level, lastSeen = p.lastSeen or 0 }
          end
        end
      end
      table.sort(items, function(a, b) return a.lastSeen > b.lastSeen end)
      count:SetText(#items .. " players")
    end
    list:SetItems(items)
  end
  return view
end)
