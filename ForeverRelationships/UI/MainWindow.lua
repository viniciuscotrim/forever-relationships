-- Main window (/fr) with six tabs: Circle, Relationship, My profile, Population, Event log, Privacy.
local _, FR = ...
local UI = FR.UI
local L = FR.L

UI.TABS = {
  { key = "circle", label = "Circle" },
  { key = "relationship", label = "Relationship" },
  { key = "profile", label = "My profile" },
  { key = "population", label = "Population" },
  { key = "log", label = "Event log" },
  { key = "privacy", label = "Privacy" },
}
UI.builders = {}

function UI:RegisterView(key, builder) self.builders[key] = builder end

local main

local function SelectTab(key)
  if not main then return end
  main.current = key
  for _, t in ipairs(UI.TABS) do
    local b = main.tabButtons[t.key]
    if t.key == key then b:LockHighlight(); b:GetFontString():SetTextColor(1, 0.82, 0)
    else b:UnlockHighlight(); b:GetFontString():SetTextColor(1, 1, 1) end
    local v = UI.views[t.key]
    if v then v.frame:SetShown(t.key == key) end
  end
  local v = UI.views[key]
  if not v and UI.builders[key] then
    local frame = CreateFrame("Frame", nil, main.content)
    frame:SetAllPoints()
    v = UI.builders[key](frame) or {}
    v.frame = frame
    UI.views[key] = v
  end
  if v then v.frame:Show(); if v.Refresh then v:Refresh() end end
  main.viewMark:SetText("|cff888888" .. (key == "population" and L["Census of Forever Relationships players"]
    or L["What the game recorded while you played together"]) .. "|r")
end
UI.SelectTab = SelectTab

function UI:Build()
  if main then return main end
  main = UI.Window("ForeverRelationshipsMainFrame", 820, 540, "HIGH")

  local title = UI.Label(main, "Forever Relationships", "GameFontHighlight")
  title:SetPoint("TOP", 0, -5)

  main.tabButtons = {}
  local prev
  for _, t in ipairs(UI.TABS) do
    local b = UI.Button(main, L[t.label], 104, 22, function() SelectTab(t.key) end)
    if prev then b:SetPoint("LEFT", prev, "RIGHT", 4, 0) else b:SetPoint("TOPLEFT", 12, -30) end
    main.tabButtons[t.key] = b
    prev = b
  end
  local fb = UI.Button(main, L["Feedback"], 90, 22, function() UI.ShowFeedback() end)
  fb:SetPoint("TOPRIGHT", -12, -30)
  UI.Tooltip(fb, L["Feedback"], { L["Report a bug or suggest an idea without leaving the game. Replies show up here too."] })
  main.viewMark = UI.Label(main, "", "GameFontNormalSmall")
  main.viewMark:SetPoint("TOPRIGHT", -36, -7)

  main.content = CreateFrame("Frame", nil, main)
  main.content:SetPoint("TOPLEFT", 12, -60)
  main.content:SetPoint("BOTTOMRIGHT", -12, 10)
  main:Hide()
  return main
end

function UI:Open(tab)
  self:Build()
  main:Show()
  SelectTab(tab or main.current or "circle")
end

function UI:Toggle()
  self:Build()
  if main:IsShown() then main:Hide() else self:Open() end
end

function UI:OpenPlayer(guid)
  self.cardGUID = guid
  self:Open("relationship")
end

function UI:RefreshCurrent()
  if main and main:IsShown() and main.current then SelectTab(main.current) end
end

local pending = false
local function QueueRefresh()
  if pending then return end
  pending = true
  C_Timer.After(0.5, function() pending = false; FR.Rel.Invalidate(); UI:RefreshCurrent() end)
end
FR:Listen("DATA_CHANGED", QueueRefresh)
FR:Listen("PLAYED_UPDATED", QueueRefresh)
FR:Listen("PARAMS_CHANGED", QueueRefresh)

-- Settings panel entry (Settings API): a small canvas that opens the main window.
FR:Listen("LOGIN", function()
  if not (Settings and Settings.RegisterCanvasLayoutCategory) then return end
  local panel = CreateFrame("Frame")
  local t = UI.Label(panel, "Forever Relationships", "GameFontNormalLarge"); t:SetPoint("TOPLEFT", 16, -16)
  local d = UI.Label(panel, L["An augmented view of how you relate to the people you play with. Type /fr."], "GameFontHighlight")
  d:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -8)
  local b = UI.Button(panel, L["Open Forever Relationships"], 180, 24, function()
    if SettingsPanel then HideUIPanel(SettingsPanel) end
    UI:Open("privacy")
  end)
  b:SetPoint("TOPLEFT", d, "BOTTOMLEFT", 0, -12)
  local ok, cat = pcall(Settings.RegisterCanvasLayoutCategory, panel, "Forever Relationships")
  if ok and cat then pcall(Settings.RegisterAddOnCategory, cat); UI.settingsCategory = cat end
end)
