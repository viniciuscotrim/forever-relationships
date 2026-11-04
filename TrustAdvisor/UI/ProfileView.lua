-- My profile: your own numbers, the public-profile checklist (opt-in, item by
-- item, about YOU only) and the choice of the 6 tooltip items.
local _, TA = ...
local UI = TA.UI

UI:RegisterView("profile", function(frame)
  local view = {}
  local header = UI.Label(frame, "", "GameFontNormalLarge"); header:SetPoint("TOPLEFT", 6, -4)

  -- left: your numbers + public profile checklist
  local pubTitle = UI.Label(frame, "Your numbers · tick what others may see", "GameFontNormal")
  pubTitle:SetPoint("TOPLEFT", 6, -30)
  view.pubState = UI.Label(frame, "", "GameFontHighlightSmall"); view.pubState:SetPoint("TOPLEFT", 6, -48); view.pubState:SetWidth(380)
  view.items = {}
  for i, item in ipairs(TA.Rel.PROFILE_ITEMS) do
    local y = -70 - (i - 1) * 24
    local b = UI.Button(frame, "", 44, 20)
    b:SetPoint("TOPLEFT", 6, y)
    local l = UI.Label(frame, item.label, "GameFontHighlight"); l:SetPoint("TOPLEFT", 58, y - 3); l:SetWidth(220)
    local v = UI.Label(frame, "", "GameFontHighlight"); v:SetPoint("TOPLEFT", 282, y - 3); v:SetWidth(110)
    b:SetScript("OnClick", function()
      local st = TA.Cloud:State().profileItems
      st[item.key] = not st[item.key] or nil
      view:Refresh()
    end)
    view.items[i] = { button = b, value = v, item = item }
  end
  view.pubBtn = UI.Button(frame, "", 210, 22, function()
    TA.Params:Set("consent.profile", not TA.Params:Get("consent.profile"))
    if TA.Params:Get("consent.profile") then UI.ShowText("Public profile", UI.CONSENT_TEXT.profile) end
    view:Refresh()
  end)
  view.pubBtn:SetPoint("TOPLEFT", 6, -70 - #TA.Rel.PROFILE_ITEMS * 24 - 8)

  -- right: tooltip fields (max 6)
  local ttTitle = UI.Label(frame, "Tooltip · choose up to 6", "GameFontNormal")
  ttTitle:SetPoint("TOPLEFT", 420, -30)
  view.tt = {}
  for i, f in ipairs(TA.Rel.FIELDS) do
    local y = -52 - (i - 1) * 20
    local b = UI.Button(frame, "", 44, 18)
    b:SetPoint("TOPLEFT", 420, y)
    local l = UI.Label(frame, f.label, "GameFontHighlightSmall"); l:SetPoint("TOPLEFT", 470, y - 3)
    b:SetScript("OnClick", function()
      local cur, out, found = UI.TooltipFields(), {}, false
      for _, k in ipairs(cur) do if k == f.key then found = true else out[#out + 1] = k end end
      if not found then
        if #out >= TA.Rel.MAX_TOOLTIP then TA.Print("The tooltip shows at most 6 items. Untick one first."); return end
        out[#out + 1] = f.key
      end
      UI.SetTooltipFields(out)
      view:Refresh()
    end)
    view.tt[i] = { button = b, key = f.key }
  end
  local reset = UI.Button(frame, "Default 6", 90, 20, function() UI.SetTooltipFields(TA.Rel.DEFAULT_TOOLTIP); view:Refresh() end)
  reset:SetPoint("TOPLEFT", 420, -52 - #TA.Rel.FIELDS * 20 - 6)

  function view:Refresh()
    local _, class = UnitClass("player")
    header:SetText(UI.ClassColored(TA.playerName or "You", class))
    local m = TA.Rel:Mine()
    local st = TA.Cloud:State().profileItems
    local on = TA.Params:Get("consent.profile")
    for _, e in ipairs(self.items) do
      e.button:SetText(st[e.item.key] and "|cff66ff66On|r" or "|cffaaaaaaOff|r")
      e.value:SetText(tostring(e.item.value(m)))
    end
    self.pubBtn:SetText(on and "|cff66ff66Public profile: ON|r" or "Publish my profile")
    self.pubState:SetText(on and "Ticked items are sent by the companion app. Others see them in your Relationship window."
      or UI.MUTED .. "Nothing is public. Tick items, then publish." .. "|r")
    local chosen = {}
    for _, k in ipairs(UI.TooltipFields()) do chosen[k] = true end
    for _, e in ipairs(self.tt) do e.button:SetText(chosen[e.key] and "|cff66ff66On|r" or "|cffaaaaaaOff|r") end
  end
  return view
end)
