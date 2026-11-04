-- Tooltip: your relationship with the player under the mouse, using the up to
-- 6 items you chose in My profile. Nothing is shown for people you never met.
local _, TA = ...
local UI = TA.UI

function UI.TooltipLines(guid)
  if not guid or not TA.db.players[guid] then return nil end
  local r = TA.Rel:Compute(guid)
  if r.sessions == 0 and r.trades == 0 then return nil end
  local lines = {}
  for _, key in ipairs(UI.TooltipFields()) do
    local f = TA.Rel.FIELD_BY_KEY[key]
    if f then lines[#lines + 1] = { f.label, f.value(r) } end
  end
  return lines
end

local function AddToUnitTooltip(tooltip)
  if not TA.db or not TA.Params:Get("tooltip.enabled") or tooltip ~= GameTooltip then return end
  local ok, _, unit = pcall(tooltip.GetUnit, tooltip)
  if not ok or not unit or TA.IsSecret(unit) then return end
  if not TA.SafeCall(UnitIsPlayer, unit) then return end
  local guid = TA.Clean(UnitGUID(unit))
  if not guid or guid == TA.playerGUID then return end
  local lines = UI.TooltipLines(guid)
  if not lines then return end
  tooltip:AddLine("|cffe8b94aYour relationship|r")
  for _, l in ipairs(lines) do tooltip:AddDoubleLine(l[1], l[2], 0.6, 0.62, 0.7, 1, 1, 1) end
end

function UI.LFGMarker(guid)
  local r = guid and TA.db.players[guid] and TA.Rel:Compute(guid)
  if not r or r.sessions == 0 then return "" end
  return "|cffe8b94aFR|r |cff999999" .. TA.FormatDuration(r.seconds) .. "|r"
end

TA:Listen("LOGIN", function()
  if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip) pcall(AddToUnitTooltip, tooltip) end)
  elseif GameTooltip and GameTooltip.HookScript then
    pcall(GameTooltip.HookScript, GameTooltip, "OnTooltipSetUnit", function(tt) pcall(AddToUnitTooltip, tt) end)
  end
  if LFGListUtil_SetSearchEntryTooltip and C_LFGList and C_LFGList.GetSearchResultInfo then
    hooksecurefunc("LFGListUtil_SetSearchEntryTooltip", function(tooltip, resultID)
      if not TA.Params:Get("tooltip.enabled") then return end
      local ok, info = pcall(C_LFGList.GetSearchResultInfo, resultID)
      local leader = ok and info and TA.Clean(info.leaderName)
      local lines = leader and UI.TooltipLines(TA.Sessions:GUIDByName(leader))
      if not lines then return end
      tooltip:AddLine(" ")
      tooltip:AddLine("|cffe8b94aYou and the leader|r")
      for _, l in ipairs(lines) do tooltip:AddDoubleLine(l[1], l[2], 0.6, 0.62, 0.7, 1, 1, 1) end
      tooltip:Show()
    end)
  end
  if LFGListSearchEntry_Update and C_LFGList and C_LFGList.GetSearchResultInfo then
    hooksecurefunc("LFGListSearchEntry_Update", function(button)
      if not button or not button.resultID then return end
      if not button.TAMark then
        button.TAMark = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        button.TAMark:SetPoint("RIGHT", button, "RIGHT", -6, 0)
      end
      button.TAMark:SetText("")
      if not TA.Params:Get("tooltip.lfgMarker") then return end
      local ok, info = pcall(C_LFGList.GetSearchResultInfo, button.resultID)
      local leader = ok and info and TA.Clean(info.leaderName)
      if leader then button.TAMark:SetText(UI.LFGMarker(TA.Sessions:GUIDByName(leader))) end
    end)
  end
end)
