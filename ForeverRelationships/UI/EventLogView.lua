-- Event log viewer: every raw event, filterable by player, signal and source.
-- Each row says which API or rule produced it. Export as copyable text.
local _, FR = ...
local UI = FR.UI
local L = FR.L

local SIGNALS = { "all", "session", "member", "ready", "trade", "generosity", "quest", "questDone", "hcDeath", "capture" }
local SOURCES = { "all", "game", "peer", "human", "questie" }

local function Summary(ev)
  local d = ev.details or {}
  local s = ev.signal
  if s == "session" then
    return string.format("%s %s, %s, %s, %s", L[d.groupType or "?"], d.instanceName or d.zone or "",
      FR.FormatDuration((d.endedAt or 0) - (d.startedAt or 0)), FR.Plural(d.memberCount or 0, "%d member", "%d members"),
      FR.Plural(d.kills and #d.kills or 0, "%d kill", "%d kills"))
  elseif s == "member" then
    local last = d.intervals and d.intervals[#d.intervals]
    return L["lvl %s, %d interval(s), %s"]:format(tostring(d.level or "?"), d.intervals and #d.intervals or 0,
      last and last.leave and L["left: %s"]:format(L[last.reason or "?"]) or L["present at end"])
  elseif s == "ready" then
    return L["%s, %d consumable categories"]:format(d.isReady and L["ready"] or (d.responded and L["not ready"] or L["no response"]), d.categories or 0)
  elseif s == "trade" then
    local bits = {}
    if (d.givenCopper or 0) > 0 then bits[#bits + 1] = L["gave %s"]:format(FR.FormatGold(d.givenCopper)) end
    if (d.receivedCopper or 0) > 0 then bits[#bits + 1] = L["got %s"]:format(FR.FormatGold(d.receivedCopper)) end
    if d.givenItems then bits[#bits + 1] = L["gave items"] end
    if d.receivedItems then bits[#bits + 1] = L["got items"] end
    if d.enchantByThem then bits[#bits + 1] = L["they enchanted"] end
    if d.enchantByMe then bits[#bits + 1] = L["you enchanted"] end
    return table.concat(bits, ", ")
  elseif s == "generosity" then
    return L[d.kind or "act"] .. (d.recipientName and (" " .. L["for %s"]:format(d.recipientName)) or "")
  elseif s == "quest" then
    return L["finished quest %s"]:format(tostring(d.questID)) .. (d.myOpen and (" " .. L["(yours still open)"]) or "")
  elseif s == "questDone" then
    return L["you turned in quest %s while grouped"]:format(tostring(d.questID))
  elseif s == "capture" then
    return L["%s unavailable: %s"]:format(d.capture or "?", d.reason or "")
  end
  return ""
end
UI.EventSummary = Summary

function UI.ExportEvents(events)
  local lines = { "# Forever Relationships event log export " .. FR.FormatDate(), "# id\tdate\tsignal\tsubject\tsource\tapi\tsummary" }
  for _, ev in ipairs(events) do
    lines[#lines + 1] = table.concat({ ev.id, FR.FormatDate(ev.t), ev.signal, ev.subjectName or "", ev.source, ev.api, Summary(ev) }, "\t")
  end
  return lines
end

UI:RegisterView("log", function(frame)
  local view = { signal = 1, source = 1 }

  local search = UI.EditBox(frame, 160)
  search:SetPoint("TOPLEFT", 6, -4)
  local hint = UI.Label(search, L["Player name"], "GameFontDisableSmall"); hint:SetPoint("LEFT", 4, 0)
  search:SetScript("OnTextChanged", function(self) hint:SetShown(self:GetText() == ""); UI.logFilterGUID = nil; view:Refresh() end)

  local sigBtn = UI.Button(frame, L["Signal: %s"]:format(L["all"]), 140, 22, function(self)
    view.signal = view.signal % #SIGNALS + 1
    self:SetText(L["Signal: %s"]:format(L[SIGNALS[view.signal]])); view:Refresh()
  end)
  sigBtn:SetPoint("LEFT", search, "RIGHT", 8, 0)
  local srcBtn = UI.Button(frame, L["Source: %s"]:format(L["all"]), 120, 22, function(self)
    view.source = view.source % #SOURCES + 1
    self:SetText(L["Source: %s"]:format(L[SOURCES[view.source]])); view:Refresh()
  end)
  srcBtn:SetPoint("LEFT", sigBtn, "RIGHT", 4, 0)
  local exportBtn = UI.Button(frame, L["Export"], 80, 22, function() UI.ShowText(L["Event log export"], UI.ExportEvents(view.items or {})) end)
  exportBtn:SetPoint("LEFT", srcBtn, "RIGHT", 4, 0)
  local count = UI.Label(frame, "", "GameFontDisableSmall")
  count:SetPoint("LEFT", exportBtn, "RIGHT", 8, 0)

  local cols = { { L["Date"], 4 }, { L["Signal"], 104 }, { L["Player"], 184 }, { L["Source"], 314 }, { L["What happened"], 374 }, { L["API / rule"], 620 } }
  for _, c in ipairs(cols) do UI.Label(frame, c[1], "GameFontNormalSmall"):SetPoint("TOPLEFT", c[2], -32) end

  local list = UI.List(frame, 18, 23, function(row)
    row.cells = {}
    for i, c in ipairs(cols) do
      local fs = UI.Label(row, "", "GameFontHighlightSmall")
      fs:SetPoint("LEFT", c[2], 0)
      fs:SetWidth((cols[i + 1] and cols[i + 1][2] or 790) - c[2] - 6)
      fs:SetWordWrap(false)
      row.cells[i] = fs
    end
    row:SetScript("OnClick", function(self)
      if self.ev and self.ev.subjectGUID and FR.db.players[self.ev.subjectGUID] then UI:OpenPlayer(self.ev.subjectGUID) end
    end)
  end, function(row, ev)
    row.ev = ev
    local vals = { date("%m-%d %H:%M", ev.t), ev.signal, FR.ShortName(ev.subjectName or "-"), ev.source, Summary(ev), ev.api }
    for i, v in ipairs(vals) do row.cells[i]:SetText(v) end
  end)
  list:SetPoint("TOPLEFT", 0, -48)
  list:SetPoint("BOTTOMRIGHT", 0, 0)

  function view:Refresh()
    local filter = {
      signal = SIGNALS[self.signal] ~= "all" and SIGNALS[self.signal] or nil,
      source = SOURCES[self.source] ~= "all" and SOURCES[self.source] or nil,
      subject = UI.logFilterGUID,
      text = UI.logFilterGUID and nil or search:GetText(),
    }
    self.items = FR.Log:Query(filter)
    count:SetText(string.format("%s%s", L["%d of %d events"]:format(#self.items, FR.Log.count),
      UI.logFilterGUID and (" · " .. FR.ShortName((FR.db.players[UI.logFilterGUID] or {}).name or "?")) or ""))
    list:SetItems(self.items)
  end
  return view
end)
