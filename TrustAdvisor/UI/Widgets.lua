-- Shared UI helpers. Native Blizzard templates only, no external libraries.
local _, TA = ...

local UI = { views = {} }
TA.UI = UI

UI.BAND_COLORS = {
  Unknown   = { 0.60, 0.60, 0.60 },
  Concern   = { 1.00, 0.55, 0.15 },
  Building  = { 0.95, 0.85, 0.35 },
  Solid     = { 0.35, 0.85, 0.40 },
  Exemplary = { 0.40, 0.75, 1.00 },
}

function UI.BandHex(band)
  local c = UI.BAND_COLORS[band] or UI.BAND_COLORS.Unknown
  return string.format("ff%02x%02x%02x", c[1] * 255, c[2] * 255, c[3] * 255)
end

function UI.BandText(band)
  return "|c" .. UI.BandHex(band) .. band .. "|r"
end

function UI.ClassColored(name, class)
  local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
  if c then return string.format("|cff%02x%02x%02x%s|r", c.r * 255, c.g * 255, c.b * 255, name) end
  return name
end

UI.NONDEFAULT_MARK = "|cffff9933*|r"

function UI.Label(parent, text, template)
  local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight")
  fs:SetText(text or "")
  fs:SetJustifyH("LEFT")
  return fs
end

function UI.Button(parent, text, w, h, onClick)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(w or 100, h or 22)
  b:SetText(text)
  if onClick then b:SetScript("OnClick", onClick) end
  return b
end

function UI.EditBox(parent, w, h)
  local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
  e:SetSize(w or 120, h or 20)
  e:SetAutoFocus(false)
  e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  return e
end

function UI.Tooltip(frame, title, lines)
  frame:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(type(title) == "function" and title() or title, 1, 1, 1)
    local l = type(lines) == "function" and lines() or lines
    for _, line in ipairs(l or {}) do GameTooltip:AddLine(line, nil, nil, nil, true) end
    GameTooltip:Show()
  end)
  frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- Virtual list on FauxScrollFrame. buildRow(row, i) once; updateRow(row, item, index) on refresh.
function UI.List(parent, rowHeight, numRows, buildRow, updateRow)
  local holder = CreateFrame("Frame", nil, parent)
  holder.items = {}
  holder.rows = {}
  local scroll = CreateFrame("ScrollFrame", nil, holder, "FauxScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT")
  scroll:SetPoint("BOTTOMRIGHT", -26, 0)
  holder.scroll = scroll
  for i = 1, numRows do
    local row = CreateFrame("Button", nil, holder)
    row:SetHeight(rowHeight)
    row:SetPoint("TOPLEFT", 0, -(i - 1) * rowHeight)
    row:SetPoint("RIGHT", scroll, "RIGHT")
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.08)
    if i % 2 == 0 then
      local bg = row:CreateTexture(nil, "BACKGROUND")
      bg:SetAllPoints()
      bg:SetColorTexture(1, 1, 1, 0.03)
    end
    buildRow(row, i)
    holder.rows[i] = row
  end
  function holder:Refresh()
    local offset = FauxScrollFrame_GetOffset(scroll)
    FauxScrollFrame_Update(scroll, #self.items, numRows, rowHeight)
    for i, row in ipairs(self.rows) do
      local item = self.items[i + offset]
      if item then updateRow(row, item, i + offset); row:Show() else row:Hide() end
    end
  end
  function holder:SetItems(items) self.items = items or {}; self:Refresh() end
  scroll:SetScript("OnVerticalScroll", function(self, offset)
    FauxScrollFrame_OnVerticalScroll(self, offset, rowHeight, function() holder:Refresh() end)
  end)
  return holder
end

-- Movable top-level window. Prefers BasicFrameTemplateWithInset; falls back to a
-- plain backdrop frame with its own close button if the template is missing.
function UI.Window(name, w, h, strata)
  local ok, f = pcall(CreateFrame, "Frame", name, UIParent, "BasicFrameTemplateWithInset")
  if not ok or not f then
    f = CreateFrame("Frame", name, UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    if f.SetBackdrop then
      f:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 24, insets = { left = 6, right = 6, top = 6, bottom = 6 } })
    end
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)
  end
  f:SetSize(w, h)
  f:SetPoint("CENTER")
  f:SetFrameStrata(strata or "HIGH")
  f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:SetClampedToScreen(true)
  if name then tinsert(UISpecialFrames, name) end
  return f
end

-- A movable window with a selectable multi-line text box (explainers, export).
local textWindow
function UI.ShowText(title, text)
  if not textWindow then
    local f = UI.Window("TrustAdvisorTextWindow", 640, 420, "DIALOG")
    f.title = UI.Label(f, "", "GameFontHighlight")
    f.title:SetPoint("TOP", 0, -5)
    local sf = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 12, -30)
    sf:SetPoint("BOTTOMRIGHT", -32, 36)
    local eb = CreateFrame("EditBox", nil, sf)
    eb:SetMultiLine(true)
    eb:SetFontObject(ChatFontNormal)
    eb:SetWidth(590)
    eb:SetAutoFocus(false)
    eb:SetScript("OnEscapePressed", function() f:Hide() end)
    eb:SetScript("OnTextChanged", function(self, user) if user then self:SetText(f.text or "") end end) -- read-only
    sf:SetScrollChild(eb)
    f.edit = eb
    local sel = UI.Button(f, "Select all", 110, 22, function() eb:SetFocus(); eb:HighlightText() end)
    sel:SetPoint("BOTTOMLEFT", 12, 8)
    local hint = UI.Label(f, "Select all, then Ctrl+C / Cmd+C to copy.", "GameFontDisableSmall")
    hint:SetPoint("LEFT", sel, "RIGHT", 10, 0)
    textWindow = f
  end
  textWindow.title:SetText(title)
  textWindow.text = type(text) == "table" and table.concat(text, "\n") or text
  textWindow.edit:SetText(textWindow.text)
  textWindow.edit:SetCursorPosition(0)
  textWindow:Show()
end

-- Band strip: one small square per trust dimension
function UI.BandStrip(parent, size)
  local strip = CreateFrame("Frame", nil, parent)
  size = size or 10
  strip:SetSize(#TA.Dimensions.list * (size + 2), size)
  strip.cells = {}
  for i, d in ipairs(TA.Dimensions.list) do
    local cell = CreateFrame("Frame", nil, strip)
    cell:SetSize(size, size)
    cell:SetPoint("LEFT", (i - 1) * (size + 2), 0)
    cell.tex = cell:CreateTexture(nil, "ARTWORK")
    cell.tex:SetAllPoints()
    cell.key = d.key
    cell:EnableMouse(true)
    cell:SetScript("OnEnter", function(self)
      if not self.result then return end
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:SetText(self.result.label, 1, 1, 1)
      GameTooltip:AddLine(UI.BandText(self.result.band) .. "  ·  confidence " .. self.result.confidence)
      GameTooltip:Show()
    end)
    cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
    strip.cells[i] = cell
  end
  function strip:SetProfile(prof)
    for _, cell in ipairs(self.cells) do
      local r = prof.dims[cell.key]
      cell.result = r
      local c = UI.BAND_COLORS[r.band]
      cell.tex:SetColorTexture(c[1], c[2], c[3], r.band == "Unknown" and 0.25 or 0.95)
    end
  end
  return strip
end

-- Shared affinity summary text (private, shown to you only)
function UI.AffinitySummary(guid)
  local a = TA.cdb.affinity[guid]
  if not a or not a.sessions or #a.sessions == 0 then return "No sessions together yet." end
  local window = TA.Params:Get("affinity.windowDays") * 86400
  local now = TA.Now()
  local n, total, last, hours, wdays, chat = 0, 0, 0, {}, {}, 0
  for _, s in ipairs(a.sessions) do
    if now - s.s <= window then
      n = n + 1
      total = total + (s.e - s.s)
      last = math.max(last, s.e)
      chat = chat + (s.chat or 0)
      if s.hour then hours[s.hour] = (hours[s.hour] or 0) + 1 end
      if s.wday then wdays[s.wday] = (wdays[s.wday] or 0) + 1 end
    end
  end
  if n == 0 then return "No sessions in the last " .. TA.Params:Get("affinity.windowDays") .. " days." end
  local evening, morning, afternoon, night, weekend, weekday = 0, 0, 0, 0, 0, 0
  for h, c in pairs(hours) do
    if h >= 18 then evening = evening + c elseif h >= 12 then afternoon = afternoon + c
    elseif h >= 6 then morning = morning + c else night = night + c end
  end
  for d, c in pairs(wdays) do if d == 0 or d == 6 then weekend = weekend + c else weekday = weekday + c end end
  local part = ({ [evening] = "evenings", [afternoon] = "afternoons", [morning] = "mornings", [night] = "late nights" })[math.max(evening, afternoon, morning, night)]
  local days = weekday >= weekend and "weekday" or "weekend"
  return string.format("Grouped %d time%s, %s total, last %s. You played together mostly %s %s. %d party messages counted (text never stored).",
    n, n == 1 and "" or "s", TA.FormatDuration(total), TA.FormatAgo(last), days, part or "", chat)
end
