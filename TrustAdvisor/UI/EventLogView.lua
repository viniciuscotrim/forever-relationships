-- Event log viewer: every raw event, filterable by player, signal and source.
-- Each row says which API or rule produced it. Export as copyable text.
local _, TA = ...
local UI = TA.UI

local SIGNALS = { "all", "session", "member", "ready", "trade", "generosity", "quest", "questDone", "hcDeath", "capture" }
local SOURCES = { "all", "game", "peer", "human", "questie" }

local function Summary(ev)
  local d = ev.details or {}
  local s = ev.signal
  if s == "session" then
    return string.format("%s %s, %s, %d members, %d kills", d.groupType or "?", d.instanceName or d.zone or "",
      TA.FormatDuration((d.endedAt or 0) - (d.startedAt or 0)), d.memberCount or 0, d.kills and #d.kills or 0)
  elseif s == "member" then
    local last = d.intervals and d.intervals[#d.intervals]
    return string.format("lvl %s, %d interval(s), %s", d.level or "?", d.intervals and #d.intervals or 0,
      last and last.leave and ("left: " .. (last.reason or "?")) or "present at end")
  elseif s == "ready" then
    return string.format("%s, %d consumable categories", d.isReady and "ready" or (d.responded and "not ready" or "no response"), d.categories or 0)
  elseif s == "trade" then
    local bits = {}
    if (d.givenCopper or 0) > 0 then bits[#bits + 1] = "gave " .. TA.FormatGold(d.givenCopper) end
    if (d.receivedCopper or 0) > 0 then bits[#bits + 1] = "got " .. TA.FormatGold(d.receivedCopper) end
    if d.givenItems then bits[#bits + 1] = "gave items" end
    if d.receivedItems then bits[#bits + 1] = "got items" end
    if d.enchantByThem then bits[#bits + 1] = "they enchanted" end
    if d.enchantByMe then bits[#bits + 1] = "you enchanted" end
    return table.concat(bits, ", ")
  elseif s == "generosity" then
    return (d.kind or "act") .. (d.recipientName and (" for " .. d.recipientName) or "")
  elseif s == "quest" then
    return string.format("finished quest %s%s", tostring(d.questID), d.myOpen and " (yours still open)" or "")
  elseif s == "questDone" then
    return "you turned in quest " .. tostring(d.questID) .. " while grouped"
  elseif s == "capture" then
    return (d.capture or "?") .. " unavailable: " .. (d.reason or "")
  end
  return ""
end
UI.EventSummary = Summary

function UI.ExportEvents(events)
  local lines = { "# Forever Relationships event log export " .. TA.FormatDate(), "# id\tdate\tsignal\tsubject\tsource\tapi\tsummary" }
  for _, ev in ipairs(events) do
    lines[#lines + 1] = table.concat({ ev.id, TA.FormatDate(ev.t), ev.signal, ev.subjectName or "", ev.source, ev.api, Summary(ev) }, "\t")
  end
  return lines
end

UI:RegisterView("log", function(frame)
  local view = { signal = 1, source = 1 }

  local search = UI.EditBox(frame, 160)
  search:SetPoint("TOPLEFT", 6, -4)
  local hint = UI.Label(search, "Player name", "GameFontDisableSmall"); hint:SetPoint("LEFT", 4, 0)
  search:SetScript("OnTextChanged", function(self) hint:SetShown(self:GetText() == ""); UI.logFilterGUID = nil; view:Refresh() end)

  local sigBtn = UI.Button(frame, "Signal: all", 140, 22, function(self)
    view.signal = view.signal % #SIGNALS + 1
    self:SetText("Signal: " .. SIGNALS[view.signal]); view:Refresh()
  end)
  sigBtn:SetPoint("LEFT", search, "RIGHT", 8, 0)
  local srcBtn = UI.Button(frame, "Source: all", 120, 22, function(self)
    view.source = view.source % #SOURCES + 1
    self:SetText("Source: " .. SOURCES[view.source]); view:Refresh()
  end)
  srcBtn:SetPoint("LEFT", sigBtn, "RIGHT", 4, 0)
  local exportBtn = UI.Button(frame, "Export", 80, 22, function() UI.ShowText("Event log export", UI.ExportEvents(view.items or {})) end)
  exportBtn:SetPoint("LEFT", srcBtn, "RIGHT", 4, 0)
  local count = UI.Label(frame, "", "GameFontDisableSmall")
  count:SetPoint("LEFT", exportBtn, "RIGHT", 8, 0)

  local cols = { { "Date", 4 }, { "Signal", 104 }, { "Player", 184 }, { "Source", 314 }, { "What happened", 374 }, { "API / rule", 620 } }
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
      if self.ev and self.ev.subjectGUID and TA.db.players[self.ev.subjectGUID] then UI:OpenPlayer(self.ev.subjectGUID) end
    end)
  end, function(row, ev)
    row.ev = ev
    local vals = { date("%m-%d %H:%M", ev.t), ev.signal, TA.ShortName(ev.subjectName or "-"), ev.source, Summary(ev), ev.api }
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
    self.items = TA.Log:Query(filter)
    count:SetText(string.format("%d of %d events%s", #self.items, TA.Log.count,
      UI.logFilterGUID and (" · " .. TA.ShortName((TA.db.players[UI.logFilterGUID] or {}).name or "?")) or ""))
    list:SetItems(self.items)
  end
  return view
end)
