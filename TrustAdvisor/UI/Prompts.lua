-- Prompts (GDD 9, 10): endorsement after qualifying sessions, friend
-- suggestion, regroup toast. The addon suggests; the player clicks to act.
-- Nothing appears during combat.
local _, TA = ...
local UI = TA.UI

local DAY = 86400
local AUTO_HIDE = 30

-------------------------------------------------------------------------------
-- Toast queue (friend suggestion, regroup)
-------------------------------------------------------------------------------
local toast, queue = nil, {}

local function BuildToast()
  local f = CreateFrame("Frame", "TrustAdvisorToast", UIParent, "BackdropTemplate")
  f:SetSize(360, 74)
  f:SetPoint("TOP", 0, -140)
  f:SetFrameStrata("DIALOG")
  f:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 14, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
  f.title = UI.Label(f, "Trust Advisor", "GameFontNormalSmall"); f.title:SetPoint("TOPLEFT", 10, -8)
  f.text = UI.Label(f, "", "GameFontHighlight"); f.text:SetPoint("TOPLEFT", 10, -24); f.text:SetWidth(340)
  f.yes = UI.Button(f, "", 110, 20); f.yes:SetPoint("BOTTOMLEFT", 10, 8)
  f.no = UI.Button(f, "Not now", 90, 20); f.no:SetPoint("LEFT", f.yes, "RIGHT", 6, 0)
  f:Hide()
  return f
end

local ShowNext
ShowNext = function()
  if TA.InCombat() then return end
  if toast and toast:IsShown() then return end
  local t = table.remove(queue, 1)
  if not t then return end
  toast = toast or BuildToast()
  toast.text:SetText(t.text)
  toast.yes:SetText(t.yesLabel)
  toast.yes:SetScript("OnClick", function() toast:Hide(); t.onYes(); ShowNext() end)
  toast.no:SetScript("OnClick", function() toast:Hide(); if t.onNo then t.onNo() end; ShowNext() end)
  toast:Show()
  local token = {}
  toast.token = token
  C_Timer.After(20, function()
    if toast.token == token and toast:IsShown() then toast:Hide(); ShowNext() end
  end)
end

function UI.Toast(t)
  table.insert(queue, t)
  ShowNext()
end

-------------------------------------------------------------------------------
-- Endorsement prompt: one prompt for the whole group
-------------------------------------------------------------------------------
local prompt
local function BuildPrompt()
  local f = CreateFrame("Frame", "TrustAdvisorEndorsePrompt", UIParent, "BackdropTemplate")
  f:SetSize(380, 60)
  f:SetPoint("TOP", 0, -220)
  f:SetFrameStrata("DIALOG")
  f:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 14, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
  f.title = UI.Label(f, "Play with them again?", "GameFontNormal"); f.title:SetPoint("TOPLEFT", 10, -8)
  local close = UI.Button(f, "Skip all", 70, 18, function() f:Hide() end)
  close:SetPoint("TOPRIGHT", -8, -6)
  f.rows = {}
  for i = 1, 4 do
    local r = CreateFrame("Frame", nil, f)
    r:SetSize(360, 22)
    r:SetPoint("TOPLEFT", 10, -26 - (i - 1) * 24)
    r.name = UI.Label(r, "", "GameFontHighlight"); r.name:SetPoint("LEFT", 0, 0); r.name:SetWidth(130)
    r.yes = UI.Button(r, "Yes", 50, 20); r.yes:SetPoint("LEFT", 134, 0)
    r.skip = UI.Button(r, "Skip", 50, 20); r.skip:SetPoint("LEFT", r.yes, "RIGHT", 4, 0)
    r.no = UI.Button(r, "Private no", 86, 20); r.no:SetPoint("LEFT", r.skip, "RIGHT", 4, 0)
    f.rows[i] = r
  end
  f:Hide()
  return f
end

local pendingPrompt
local function ShowEndorsePrompt(members, sessionId)
  if TA.InCombat() then pendingPrompt = { members, sessionId }; return end
  prompt = prompt or BuildPrompt()
  local list = {}
  for _, m in ipairs(members) do if TA.Endorse:CanEndorse(m.guid) then list[#list + 1] = m end end
  if #list == 0 then return end
  local shown = math.min(#list, #prompt.rows)
  local done = 0
  for i, r in ipairs(prompt.rows) do
    local m = list[i]
    r:SetShown(m ~= nil)
    if m then
      r.name:SetText(UI.ClassColored(TA.ShortName(m.name), m.class))
      for _, b in ipairs({ r.yes, r.skip, r.no }) do b:Enable() end
      local function finish()
        for _, b in ipairs({ r.yes, r.skip, r.no }) do b:Disable() end
        done = done + 1
        if done >= shown then prompt:Hide() end
      end
      r.yes:SetScript("OnClick", function() TA.Endorse:Give(m.guid, m.name, sessionId); finish() end)
      r.skip:SetScript("OnClick", finish)
      r.no:SetScript("OnClick", function() TA.Endorse:PrivateNo(m.guid, m.name); finish() end)
    end
  end
  prompt:SetHeight(34 + shown * 24)
  prompt:Show()
  local token = {}
  prompt.token = token
  C_Timer.After(AUTO_HIDE, function() if prompt.token == token then prompt:Hide() end end)
end

TA:On("PLAYER_REGEN_ENABLED", function()
  if pendingPrompt then local p = pendingPrompt; pendingPrompt = nil; ShowEndorsePrompt(p[1], p[2]) end
  ShowNext()
end)

-------------------------------------------------------------------------------
-- After a session: endorsement prompt + friend suggestions
-------------------------------------------------------------------------------
local function GoodSessions(guid)
  local a = TA.cdb.affinity[guid]
  if not a or a.privateNo then return 0 end
  return #(a.sessions or {})
end

local function IsFriend(guid)
  return C_FriendList and C_FriendList.IsFriend and TA.SafeCall(C_FriendList.IsFriend, guid) or false
end

TA:Listen("SESSION_END", function(s, endedAt)
  local members = {}
  for guid, m in pairs(s.members) do
    if guid ~= TA.playerGUID then members[#members + 1] = { guid = guid, name = m.name, class = m.class } end
  end
  if #members == 0 then return end
  local minutes = (endedAt - s.startedAt) / 60
  C_Timer.After(2, function()
    if TA.Params:Get("consent.endorsePrompts") and minutes >= TA.Params:Get("endorse.minMinutes") then
      ShowEndorsePrompt(members, s.id)
    end
    for _, m in ipairs(members) do
      local dismissed = TA.cdb.suggestDismissed[m.guid]
      if GoodSessions(m.guid) >= TA.Params:Get("suggest.friendAfterSessions") and not IsFriend(m.guid)
        and not (dismissed and TA.Now() - dismissed < 30 * DAY) then
        UI.Toast({
          text = string.format("You've grouped with %s %d times. Add as a friend?", TA.ShortName(m.name), GoodSessions(m.guid)),
          yesLabel = "Add friend",
          onYes = function() C_FriendList.AddFriend(TA.ShortName(m.name), "Trust Advisor: questing partner") end,
          onNo = function() TA.cdb.suggestDismissed[m.guid] = TA.Now() end,
        })
      end
    end
  end)
end)

-------------------------------------------------------------------------------
-- Regroup toast: a past partner comes online or is detected nearby
-------------------------------------------------------------------------------
local lastToast = {}
local function MaybeRegroup(guid, name, zone)
  if not guid or guid == TA.playerGUID or IsInGroup() and TA.Sessions:Member(guid) then return end
  local a = TA.cdb.affinity[guid]
  if not a or a.privateNo or #(a.sessions or {}) < TA.Params:Get("suggest.regroupMinSessions") then return end
  local cd = TA.Params:Get("suggest.regroupCooldownMinutes") * 60
  if lastToast[guid] and TA.Now() - lastToast[guid] < cd then return end
  lastToast[guid] = TA.Now()
  UI.Toast({
    text = string.format("%s is in %s. Invite?", TA.ShortName(name), zone or "the world"),
    yesLabel = "Invite",
    onYes = function()
      local invite = (C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit
      if invite then invite(name) end
    end,
  })
end

local online = {}
TA:On("FRIENDLIST_UPDATE", function()
  if not (C_FriendList and C_FriendList.GetNumFriends) then return end
  local n = TA.SafeCall(C_FriendList.GetNumFriends) or 0
  local seen = {}
  for i = 1, n do
    local info = TA.SafeCall(C_FriendList.GetFriendInfoByIndex, i)
    if info and info.guid and info.connected then
      seen[info.guid] = true
      if online[info.guid] == false then MaybeRegroup(info.guid, info.name, info.area) end
    end
  end
  for i = 1, n do
    local info = TA.SafeCall(C_FriendList.GetFriendInfoByIndex, i)
    if info and info.guid then online[info.guid] = seen[info.guid] and true or false end
  end
end)

TA:Listen("PRESENCE_SEEN", function(guid, p) MaybeRegroup(guid, p.name, p.zone) end)
