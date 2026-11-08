-- Group picker: tick the groups a player belongs to, create your own groups,
-- rename or delete them. Opened from the "Groups" button on each Circle row and
-- from the Relationship window.
local _, FR = ...
local UI = FR.UI
local L = FR.L

local Picker = {}
UI.GroupPicker = Picker

local ROWS, ROW_H = 10, 22

function Picker:Build()
  if self.frame then return self.frame end
  local f = UI.Window("ForeverRelationshipsGroupPicker", 330, 120 + ROWS * ROW_H, "DIALOG")
  f.title = UI.Label(f, "", "GameFontHighlight"); f.title:SetPoint("TOP", 0, -5)
  f.hint = UI.Label(f, L["Automatic groups fill themselves from what the game recorded."], "GameFontDisableSmall")
  f.hint:SetPoint("TOPLEFT", 12, -30); f.hint:SetWidth(300)
  f.list = UI.List(f, ROW_H, ROWS, function(row)
    row.toggle = UI.Button(row, "", 44, 18)
    row.toggle:SetPoint("LEFT", 4, 0)
    row.label = UI.Label(row, "", "GameFontHighlightSmall"); row.label:SetPoint("LEFT", 54, 0); row.label:SetWidth(170)
    row.rename = UI.Button(row, L["Rename"], 60, 18); row.rename:SetPoint("RIGHT", -26, 0)
    row.delete = UI.Button(row, "X", 22, 18); row.delete:SetPoint("RIGHT", -2, 0)
    row.toggle:SetScript("OnClick", function()
      FR.Groups:Set(f.guid, row.key, not FR.Groups:Has(f.guid, row.key))
      Picker:Refresh()
    end)
    row.rename:SetScript("OnClick", function()
      local d = StaticPopup_Show("FOREVERRELATIONSHIPS_RENAME_GROUP", row.name)
      if d then d.data = row.key end
    end)
    row.delete:SetScript("OnClick", function()
      local d = StaticPopup_Show("FOREVERRELATIONSHIPS_DELETE_GROUP", row.name)
      if d then d.data = row.key end
    end)
  end, function(row, item)
    row.key, row.name = item.key, item.name
    local on = f.guid and item.member
    row.toggle:SetText(on and "|cff66ff66" .. L["On"] .. "|r" or "|cffaaaaaa" .. L["Off"] .. "|r")
    row.toggle:SetShown(f.guid ~= nil)
    row.label:SetText(item.name .. (item.isAuto and (" " .. UI.MUTED .. L["(auto)"] .. "|r") or ""))
    row.rename:SetShown(not item.builtin)
    row.delete:SetShown(not item.builtin)
    if item.desc then UI.Tooltip(row.toggle, item.name, { item.desc }) else row.toggle:SetScript("OnEnter", nil) end
  end)
  f.list:SetPoint("TOPLEFT", 8, -50)
  f.list:SetPoint("BOTTOMRIGHT", -8, 44)
  f.newName = UI.EditBox(f, 190)
  f.newName:SetPoint("BOTTOMLEFT", 16, 14)
  f.newName:SetMaxLetters(32)
  local create = function()
    local key, err = FR.Groups:Create(f.newName:GetText())
    if not key then FR.Print(err); return end
    f.newName:SetText("")
    f.newName:ClearFocus()
    if f.guid then FR.Groups:Set(f.guid, key, true) end
    Picker:Refresh()
  end
  f.newName:SetScript("OnEnterPressed", create)
  local add = UI.Button(f, L["New group"], 100, 22, create)
  add:SetPoint("LEFT", f.newName, "RIGHT", 8, 0)
  f:Hide()
  self.frame = f
  return f
end

function Picker:Refresh()
  local f = self.frame
  if not f then return end
  local set, auto = {}, {}
  if f.guid then set, auto = FR.Groups:Of(f.guid) end
  local items = {}
  for _, g in ipairs(FR.Groups:All()) do
    items[#items + 1] = { key = g.key, name = g.name, builtin = g.builtin, desc = g.desc, member = set[g.key], isAuto = auto[g.key] }
  end
  f.list:SetItems(items)
  FR:Fire("DATA_CHANGED")
end

-- guid = a player to categorize; nil = just manage the groups.
function Picker:Open(guid)
  local f = self:Build()
  f.guid = guid
  local p = guid and (FR.db.players[guid] or (FR.Rivals and FR.Rivals:Get(guid)))
  f.title:SetText(p and L["Groups · %s"]:format(FR.ShortName(p.name)) or L["Your groups"])
  self:Refresh()
  f:Show()
end

UI.Popup("FOREVERRELATIONSHIPS_RENAME_GROUP", {
  text = "Rename the group \"%s\":", button1 = ACCEPT or "OK", button2 = CANCEL, hasEditBox = true, maxLetters = 32,
  timeout = 0, whileDead = true, hideOnEscape = true,
  OnAccept = function(self, key)
    local box = self.editBox or self.EditBox
    if box and FR.Groups:Rename(key, box:GetText()) then Picker:Refresh() end
  end,
})
UI.Popup("FOREVERRELATIONSHIPS_DELETE_GROUP", {
  text = "Delete the group \"%s\"? Players stay in your Circle.", button1 = DELETE or "Delete", button2 = CANCEL,
  timeout = 0, whileDead = true, hideOnEscape = true, showAlert = true,
  OnAccept = function(_, key) FR.Groups:Delete(key); Picker:Refresh() end,
})

return Picker
