-- Invite / join macro. Click it with the mouse over a player (or with a target) to
-- invite them; Shift+click asks to join their group. Self-contained: it works without
-- the addon too, so it can be shared. "Create macro" saves it as an account macro and
-- puts it on the cursor, ready to drop on an action bar (out of combat only).
local _, FR = ...
local UI = FR.UI
local L = FR.L

local Macro = {}
UI.Macro = Macro

Macro.NAME = "FR Invite"
Macro.ICON = 134400   -- question mark: the game shows the macro's name on the button
Macro.BODY = '/run local u=UnitExists("mouseover") and "mouseover" or "target" local n=UnitIsPlayer(u) and GetUnitName(u,true) '
  .. 'local P=C_PartyInfo if n then (IsShiftKeyDown() and P.RequestInviteFromUnit or P.InviteUnit)(n) end'
assert(#Macro.BODY <= 255, "macros hold 255 characters")

-- Creates (or updates) the account macro and puts it on the cursor. Returns ok, message.
function Macro:Create()
  if FR.InCombat() then return false, L["Not possible in combat. Try again after the fight."] end
  if not (CreateMacro and GetMacroIndexByName) then return false, L["This client can't create macros from an addon. Copy the text instead."] end
  local index = GetMacroIndexByName(self.NAME)
  if index and index > 0 then
    local ok = pcall(EditMacro, index, self.NAME, self.ICON, self.BODY)
    if not ok then return false, L["This client can't create macros from an addon. Copy the text instead."] end
  else
    local general = GetNumMacros and GetNumMacros() or 0
    if general >= (MAX_ACCOUNT_MACROS or 120) then return false, L["Your general macro list is full. Delete one and try again."] end
    local ok, idx = pcall(CreateMacro, self.NAME, self.ICON, self.BODY, nil)
    if not ok or not idx then return false, L["This client can't create macros from an addon. Copy the text instead."] end
    index = idx
  end
  if PickupMacro then pcall(PickupMacro, index) end
  return true, L["Macro \"%s\" is ready and on your cursor: drop it on an action bar."]:format(self.NAME)
end

local win
function UI.ShowMacro()
  if not win then
    local f = UI.Window("ForeverRelationshipsMacro", 560, 250, "DIALOG")
    UI.Label(f, L["Invite macro"], "GameFontHighlight"):SetPoint("TOP", 0, -5)
    local how = UI.Label(f, L["Click it with the mouse over a player (or with a target) to invite them. Shift+click asks to join their group."], "GameFontHighlightSmall")
    how:SetPoint("TOPLEFT", 14, -32); how:SetWidth(530); how:SetJustifyH("LEFT")
    local eb = CreateFrame("EditBox", nil, f, BackdropTemplateMixin and "BackdropTemplate" or nil)
    eb:SetPoint("TOPLEFT", 14, -66); eb:SetPoint("TOPRIGHT", -14, -66); eb:SetHeight(92)
    eb:SetMultiLine(true); eb:SetAutoFocus(false); eb:SetFontObject(ChatFontNormal); eb:SetTextInsets(6, 6, 6, 6)
    if eb.SetBackdrop then
      eb:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
      eb:SetBackdropColor(0, 0, 0, 0.6)
    end
    eb:SetScript("OnTextChanged", function(self, user) if user then self:SetText(Macro.BODY); self:HighlightText() end end) -- read-only
    eb:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus(); f:Hide() end)
    eb:SetText(Macro.BODY)
    f.edit = eb
    local status = UI.Label(f, "", "GameFontHighlightSmall")
    status:SetPoint("TOPLEFT", eb, "BOTTOMLEFT", 0, -8); status:SetWidth(530); status:SetJustifyH("LEFT")
    f.status = status
    local create = UI.Button(f, L["Create macro"], 150, 24, function()
      local ok, msg = Macro:Create()
      status:SetText((ok and "|cff66ff66" or "|cffff9933") .. msg .. "|r")
    end)
    create:SetPoint("BOTTOMLEFT", 14, 10)
    UI.Tooltip(create, L["Create macro"], { L["Saves it in your general macros and puts it on your cursor."] })
    local copy = UI.Button(f, L["Copy"], 110, 24, function()
      eb:SetFocus(); eb:HighlightText()
      status:SetText("|cffffd100" .. L["The text is selected: press Ctrl+C (Cmd+C on Mac)."] .. "|r")
    end)
    copy:SetPoint("LEFT", create, "RIGHT", 8, 0)
    win = f
  end
  win.status:SetText("")
  win:Show()
end
