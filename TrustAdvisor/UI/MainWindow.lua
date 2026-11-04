-- Main window (/ta) with five tabs: Players, Player card, My profile, Event log, Transparency.
local _, TA = ...
local UI = TA.UI

UI.TABS = {
  { key = "players", label = "Players" },
  { key = "card", label = "Player card" },
  { key = "profile", label = "My profile" },
  { key = "log", label = "Event log" },
  { key = "transparency", label = "Transparency" },
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
  main.viewMark:SetText(TA.Params:AnyScoringNonDefault() and (UI.NONDEFAULT_MARK .. " |cffff9933Your view uses non-default parameters|r") or "|cff888888Your view (local witness)|r")
end
UI.SelectTab = SelectTab

function UI:Build()
  if main then return main end
  main = UI.Window("TrustAdvisorMainFrame", 820, 540, "HIGH")

  local title = UI.Label(main, "Trust Advisor", "GameFontHighlight")
  title:SetPoint("TOP", 0, -5)

  main.tabButtons = {}
  local prev
  for _, t in ipairs(UI.TABS) do
    local b = UI.Button(main, t.label, 120, 22, function() SelectTab(t.key) end)
    if prev then b:SetPoint("LEFT", prev, "RIGHT", 4, 0) else b:SetPoint("TOPLEFT", 12, -30) end
    main.tabButtons[t.key] = b
    prev = b
  end
  main.viewMark = UI.Label(main, "", "GameFontNormalSmall")
  main.viewMark:SetPoint("TOPRIGHT", -14, -35)

  main.content = CreateFrame("Frame", nil, main)
  main.content:SetPoint("TOPLEFT", 12, -60)
  main.content:SetPoint("BOTTOMRIGHT", -12, 10)
  main:Hide()
  return main
end

function UI:Open(tab)
  self:Build()
  main:Show()
  SelectTab(tab or main.current or "players")
end

function UI:Toggle()
  self:Build()
  if main:IsShown() then main:Hide() else self:Open() end
end

function UI:OpenPlayer(guid)
  self.cardGUID = guid
  self:Open("card")
end

function UI:RefreshCurrent()
  if main and main:IsShown() and main.current then SelectTab(main.current) end
end

local pending = false
local function QueueRefresh()
  if pending then return end
  pending = true
  C_Timer.After(0.5, function() pending = false; TA.Dimensions.Invalidate(); UI:RefreshCurrent() end)
end
TA:Listen("DATA_CHANGED", QueueRefresh)
TA:Listen("PARAMS_CHANGED", QueueRefresh)

-- Settings panel entry (Settings API): a small canvas that opens the main window.
TA:Listen("LOGIN", function()
  if not (Settings and Settings.RegisterCanvasLayoutCategory) then return end
  local panel = CreateFrame("Frame")
  local t = UI.Label(panel, "Trust Advisor", "GameFontNormalLarge"); t:SetPoint("TOPLEFT", 16, -16)
  local d = UI.Label(panel, "Every rule, weight and threshold is visible and editable in the Transparency tab.", "GameFontHighlight")
  d:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -8)
  local b = UI.Button(panel, "Open Trust Advisor", 180, 24, function()
    if SettingsPanel then HideUIPanel(SettingsPanel) end
    UI:Open("transparency")
  end)
  b:SetPoint("TOPLEFT", d, "BOTTOMLEFT", 0, -12)
  local ok, cat = pcall(Settings.RegisterCanvasLayoutCategory, panel, "Trust Advisor")
  if ok and cat then pcall(Settings.RegisterAddOnCategory, cat); UI.settingsCategory = cat end
end)
