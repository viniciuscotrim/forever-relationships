-- My profile: your own bands as your client witnessed them, endorsements
-- received (local and peer), attunements.
local _, TA = ...
local UI = TA.UI

UI:RegisterView("profile", function(frame)
  local view = {}
  local header = UI.Label(frame, "", "GameFontNormalLarge")
  header:SetPoint("TOPLEFT", 6, -4)
  local note = UI.Label(frame, "|cff888888Your own behavior as your client witnessed it. Others see their own view of you.|r", "GameFontHighlightSmall")
  note:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4)

  local trust = UI.TrustPanel(frame)
  trust:SetPoint("TOPLEFT", 0, -46)
  trust:SetSize(560, 360)

  local eh = UI.Label(frame, "Endorsements received", "GameFontNormal")
  eh:SetPoint("TOPLEFT", 590, -46)
  local list = UI.List(frame, 18, 18, function(row)
    row.text = UI.Label(row, "", "GameFontHighlightSmall"); row.text:SetPoint("LEFT", 4, 0); row.text:SetWidth(190)
  end, function(row, ev)
    row.text:SetText(string.format("%s |cff888888%s · %s|r", TA.ShortName(ev.details.endorserName), ev.source, date("%m-%d", ev.t)))
  end)
  list:SetPoint("TOPLEFT", 586, -64)
  list:SetSize(210, 340)

  function view:Refresh()
    local guid = TA.playerGUID
    if not guid then return end
    if not TA.db.players[guid] then
      local _, class = UnitClass("player")
      TA.Sessions:TouchPlayer({ guid = guid, name = TA.playerName, class = class, level = UnitLevel("player"), guild = TA.SafeCall(GetGuildInfo, "player") })
    end
    local _, class = UnitClass("player")
    header:SetText(UI.ClassColored(TA.playerName or "You", class))
    trust:SetGUID(guid, TA.playerName)
    local items = {}
    for _, ev in ipairs(TA.Log:ForSubject(guid)) do
      if ev.signal == "endorse" then table.insert(items, 1, ev) end
    end
    list:SetItems(items)
  end
  return view
end)
