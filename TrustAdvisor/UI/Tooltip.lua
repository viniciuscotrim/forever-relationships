-- Tooltip line on unit tooltips and LFG entries (GDD 10).
--   "Trust Advisor: Finishing Solid · Paying Exemplary · 4 sessions"
--   "Trust Advisor: Unknown (no data)"
local _, TA = ...
local UI = TA.UI

function UI.TooltipLine(guid)
  if not guid or not TA.db.players[guid] then return "|cff33ccffTrust Advisor:|r |cff999999Unknown (no data)|r" end
  local prof = TA.Dimensions.Profile(guid)
  local onlyNotable = TA.Params:Get("tooltip.onlyNotable")
  local bits = {}
  for _, k in ipairs(prof.order) do
    local r = prof.dims[k]
    if r.band ~= "Unknown" and (not onlyNotable or r.band == "Concern" or r.band == "Exemplary") then
      bits[#bits + 1] = r.label .. " " .. UI.BandText(r.band)
    end
  end
  local tail = prof.sessions .. (prof.sessions == 1 and " session" or " sessions")
  local mark = prof.nonDefault and (" " .. UI.NONDEFAULT_MARK) or ""
  if #bits == 0 then
    return "|cff33ccffTrust Advisor:|r |cff999999Unknown (low evidence)|r · " .. tail .. mark
  end
  return "|cff33ccffTrust Advisor:|r " .. table.concat(bits, " · ") .. " · " .. tail .. mark
end

function UI.LFGMarker(guid)
  local prof = TA.Dimensions.Profile(guid)
  local star, concern = false, false
  for _, k in ipairs(prof.order) do
    local b = prof.dims[k].band
    if b == "Exemplary" then star = true elseif b == "Concern" then concern = true end
  end
  if prof.sessions == 0 then return "" end
  return (star and "|cff66bfff*|r" or "") .. (concern and "|cffff9933!|r" or "") .. "|cff33ccffTA|r|cff999999x" .. prof.sessions .. "|r"
end

local function AddToUnitTooltip(tooltip)
  if not TA.db or not TA.Params:Get("tooltip.enabled") then return end
  if tooltip ~= GameTooltip then return end
  local ok, _, unit = pcall(tooltip.GetUnit, tooltip)
  if not ok or not unit or TA.IsSecret(unit) then return end
  if not TA.SafeCall(UnitIsPlayer, unit) then return end
  local guid = TA.Clean(UnitGUID(unit))
  if not guid or guid == TA.playerGUID then return end
  tooltip:AddLine(UI.TooltipLine(guid), 1, 1, 1, true)
end

TA:Listen("LOGIN", function()
  if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip) pcall(AddToUnitTooltip, tooltip) end)
  elseif GameTooltip and GameTooltip.HookScript then
    pcall(GameTooltip.HookScript, GameTooltip, "OnTooltipSetUnit", function(tt) pcall(AddToUnitTooltip, tt) end)
  end

  -- LFG listings: leader's bands, if your client has data on them
  if LFGListUtil_SetSearchEntryTooltip and C_LFGList and C_LFGList.GetSearchResultInfo then
    hooksecurefunc("LFGListUtil_SetSearchEntryTooltip", function(tooltip, resultID)
      if not TA.Params:Get("tooltip.enabled") then return end
      local ok, info = pcall(C_LFGList.GetSearchResultInfo, resultID)
      local leader = ok and info and TA.Clean(info.leaderName)
      if not leader then return end
      local guid = TA.Sessions:GUIDByName(leader)
      tooltip:AddLine(" ")
      tooltip:AddLine(UI.TooltipLine(guid), 1, 1, 1, true)
      tooltip:Show()
    end)
  end

  -- LFG "column": a small marker after the listing name for leaders you know.
  -- Never a composite score: a star if any trait is Exemplary, "!" if any is Concern, and the session count.
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
      local guid = leader and TA.Sessions:GUIDByName(leader)
      if not guid then return end
      button.TAMark:SetText(UI.LFGMarker(guid))
    end)
  end
end)
