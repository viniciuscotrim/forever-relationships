-- Population: realm population by realm type (PvP / PvE), faction and race, from the
-- census of Forever Relationships players (Community layer), delivered by the companion.
local _, FR = ...
local UI = FR.UI

local FACTION_COLOR = { Alliance = { 0.29, 0.56, 1 }, Horde = { 0.9, 0.22, 0.2 } }
local TYPE_LABEL = { pvp = "PvP", pve = "PvE" }
local ROWS = 14

local function Num(n)
  n = math.floor(n or 0)
  if BreakUpLargeNumbers then return BreakUpLargeNumbers(n) end
  local s = tostring(n)
  while true do
    local r, k = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
    s = r
    if k == 0 then return s end
  end
end

local function Pct(x) return string.format("%.1f%%", x or 0) end

local function Hex(c) return string.format("|cff%02x%02x%02x", c[1] * 255, c[2] * 255, c[3] * 255) end

UI:RegisterView("population", function(frame)
  local view = { rtype = nil, faction = "all" }

  local title = UI.Label(frame, "Realm population", "GameFontNormalLarge"); title:SetPoint("TOPLEFT", 6, -4)
  view.realm = UI.Label(frame, "", "GameFontHighlightSmall"); view.realm:SetPoint("LEFT", title, "RIGHT", 12, -1)

  -- filters
  view.typeButtons, view.factionButtons = {}, {}
  local prev
  for _, t in ipairs({ { "pvp", "PvP realms" }, { "pve", "PvE realms" } }) do
    local b = UI.Button(frame, t[2], 104, 22, function() view.rtype = t[1]; view:Refresh() end)
    if prev then b:SetPoint("LEFT", prev, "RIGHT", 4, 0) else b:SetPoint("TOPLEFT", 6, -30) end
    view.typeButtons[t[1]] = b
    prev = b
  end
  for i, f in ipairs({ { "all", "Both factions" }, { "Alliance", "Alliance" }, { "Horde", "Horde" } }) do
    local b = UI.Button(frame, f[2], 104, 22, function() view.faction = f[1]; view:Refresh() end)
    b:SetPoint("LEFT", prev, "RIGHT", i == 1 and 24 or 4, 0)
    view.factionButtons[f[1]] = b
    prev = b
  end

  -- faction balance
  view.summary = UI.Label(frame, "", "GameFontHighlight"); view.summary:SetPoint("TOPLEFT", 6, -64)
  local barW = 780
  local barBg = frame:CreateTexture(nil, "ARTWORK"); barBg:SetPoint("TOPLEFT", 6, -86); barBg:SetSize(barW, 12)
  barBg:SetColorTexture(1, 1, 1, 0.08)
  view.barA = frame:CreateTexture(nil, "OVERLAY"); view.barA:SetPoint("TOPLEFT", barBg, "TOPLEFT"); view.barA:SetHeight(12)
  view.barA:SetColorTexture(unpack(FACTION_COLOR.Alliance))
  view.barH = frame:CreateTexture(nil, "OVERLAY"); view.barH:SetPoint("TOPRIGHT", barBg, "TOPRIGHT"); view.barH:SetHeight(12)
  view.barH:SetColorTexture(unpack(FACTION_COLOR.Horde))

  -- race table
  local cols = { { "Race", 6 }, { "Faction", 170 }, { "Characters", 290 }, { "%", 390 } }
  for _, c in ipairs(cols) do
    local h = UI.Label(frame, c[1], "GameFontNormalSmall"); h:SetPoint("TOPLEFT", c[2], -110)
  end
  view.rows = {}
  for i = 1, ROWS do
    local y = -128 - (i - 1) * 20
    local r = {}
    r.race = UI.Label(frame, "", "GameFontHighlight"); r.race:SetPoint("TOPLEFT", 6, y)
    r.faction = UI.Label(frame, "", "GameFontHighlight"); r.faction:SetPoint("TOPLEFT", 170, y)
    r.n = UI.Label(frame, "", "GameFontHighlight"); r.n:SetPoint("TOPLEFT", 290, y)
    r.pct = UI.Label(frame, "", "GameFontHighlight"); r.pct:SetPoint("TOPLEFT", 390, y)
    r.bar = frame:CreateTexture(nil, "ARTWORK"); r.bar:SetPoint("TOPLEFT", 460, y - 2); r.bar:SetHeight(10)
    view.rows[i] = r
  end
  view.empty = UI.Label(frame, "", "GameFontHighlight"); view.empty:SetPoint("TOPLEFT", 6, -130); view.empty:SetWidth(780)
  view.empty:SetJustifyV("TOP")

  view.footer = UI.Label(frame, "", "GameFontDisableSmall"); view.footer:SetPoint("BOTTOMLEFT", 6, 4); view.footer:SetWidth(780)
  view.footer:SetJustifyV("BOTTOM")

  local function Mark(buttons, current)
    for k, b in pairs(buttons) do
      if k == current then b:LockHighlight(); b:GetFontString():SetTextColor(1, 0.82, 0)
      else b:UnlockHighlight(); b:GetFontString():SetTextColor(1, 1, 1) end
    end
  end

  function view:Refresh()
    local C = FR.Census
    local pop = C:Population()
    local mine = C:MyRealmType()
    self.rtype = self.rtype or mine or "pvp"
    Mark(self.typeButtons, self.rtype)
    Mark(self.factionButtons, self.faction)
    local realmName = GetRealmName and FR.Clean(GetRealmName()) or "your realm"
    self.realm:SetText(UI.MUTED .. "Your realm: " .. tostring(realmName) .. (mine and (" (" .. TYPE_LABEL[mine] .. ")") or " (type not set yet)") .. "|r")

    local s = C:Summary(self.rtype, self.faction)
    local label = TYPE_LABEL[self.rtype] or self.rtype
    if s.total > 0 then
      self.summary:SetText(string.format("%sAlliance|r %s (%s)    %sHorde|r %s (%s)    Total %s on %s realms",
        Hex(FACTION_COLOR.Alliance), Num(s.alliance), Pct(s.alliance * 100 / s.total),
        Hex(FACTION_COLOR.Horde), Num(s.horde), Pct(s.horde * 100 / s.total), Num(s.total), label))
      self.barA:SetWidth(math.max(1, barW * s.alliance / s.total)); self.barA:Show()
      self.barH:SetWidth(math.max(1, barW * s.horde / s.total)); self.barH:Show()
    else
      self.summary:SetText("")
      self.barA:Hide(); self.barH:Hide()
    end

    local maxPct = s.rows[1] and s.rows[1].pct or 0
    for i, r in ipairs(self.rows) do
      local row = s.rows[i]
      local shown = row ~= nil
      for _, w in ipairs({ r.race, r.faction, r.n, r.pct, r.bar }) do w:SetShown(shown) end
      if row then
        local col = FACTION_COLOR[row.faction]
        r.race:SetText(row.race)
        r.faction:SetText(Hex(col) .. row.faction .. "|r")
        r.n:SetText(Num(row.n))
        r.pct:SetText(Pct(row.pct))
        r.bar:SetColorTexture(col[1], col[2], col[3], 0.85)
        r.bar:SetWidth(math.max(1, 320 * (maxPct > 0 and row.pct / maxPct or 0)))
      end
    end

    if not pop then
      self.empty:SetText("No population data yet.\n\nPopulation comes from the free companion app, even with every layer off. "
        .. "Type |cffffffff/fr cloud|r to set it up. It refreshes every hour; WoW loads the new numbers when you log in or /reload.")
    elseif s.base == 0 then
      self.empty:SetText(string.format("No characters counted on %s realms yet.", label))
    else
      self.empty:SetText("")
    end

    local lines = {}
    if pop then
      lines[#lines + 1] = string.format("Updated %s · characters seen in the last %d days by Forever Relationships players with Community on. Percentages are of the %s shown.",
        FR.FormatDate(pop.updatedAt), pop.windowDays or 30, self.faction == "all" and "characters" or (self.faction .. " characters"))
      lines[#lines + 1] = "The companion refreshes it every hour; WoW shows the new numbers after a login or /reload. Unofficial: a sample, not Blizzard's numbers."
    end
    self.footer:SetText(table.concat(lines, "\n"))
  end
  return view
end)
