-- Shared UI helpers. Native Blizzard templates only, no external libraries.
local _, FR = ...

local UI = { views = {} }
FR.UI = UI

UI.GOLD = "|cffe8b94a"
UI.MUTED = "|cff8f97ab"

function UI.ClassColored(name, class)
  local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
  if c then return string.format("|cff%02x%02x%02x%s|r", c.r * 255, c.g * 255, c.b * 255, name) end
  return name
end

UI.NONDEFAULT_MARK = "|cffff9933*|r"

-- Our StaticPopup dialogs: English text in the definition, translated once the
-- language is known (after SavedVariables load, so /fr language applies).
function UI.Popup(name, def)
  def.en = def.text
  StaticPopupDialogs[name] = def
end
FR:Listen("DB_READY", function()
  for name, d in pairs(StaticPopupDialogs) do
    if type(name) == "string" and name:find("^FOREVERRELATIONSHIPS_") and d.en then d.text = FR.L[d.en] end
  end
end)

-- Selected tooltip fields (account-wide), at most FR.Rel.MAX_TOOLTIP
function UI.TooltipFields()
  local f = FR.db.ui and FR.db.ui.tooltipFields
  if type(f) ~= "table" or #f == 0 then return FR.Rel.DEFAULT_TOOLTIP end
  return f
end

function UI.SetTooltipFields(list)
  FR.db.ui = FR.db.ui or {}
  FR.db.ui.tooltipFields = list
  FR:Fire("DATA_CHANGED")
end

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
  -- Every window lives in the same strata, so the one opened (or clicked) last is on top:
  -- Show() raises it even when it was already open behind another window.
  f:SetToplevel(true)
  local show = f.Show
  f.Show = function(self, ...) show(self, ...); self:Raise() end
  if name then tinsert(UISpecialFrames, name) end
  return f
end

-- A movable window with a selectable multi-line text box (explainers, export).
local textWindow
function UI.ShowText(title, text)
  if not textWindow then
    local f = UI.Window("ForeverRelationshipsTextWindow", 640, 420, "HIGH")
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
    local sel = UI.Button(f, FR.L["Select all"], 110, 22, function() eb:SetFocus(); eb:HighlightText() end)
    sel:SetPoint("BOTTOMLEFT", 12, 8)
    local hint = UI.Label(f, FR.L["Select all, then Ctrl+C / Cmd+C to copy."], "GameFontDisableSmall")
    hint:SetPoint("LEFT", sel, "RIGHT", 10, 0)
    textWindow = f
  end
  textWindow.title:SetText(title)
  textWindow.text = type(text) == "table" and table.concat(text, "\n") or text
  textWindow.edit:SetText(textWindow.text)
  textWindow.edit:SetCursorPosition(0)
  textWindow:Show()
end

