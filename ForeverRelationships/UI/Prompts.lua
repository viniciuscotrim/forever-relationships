-- Prompts: friend suggestion and "they're online, invite?" toast, based on the
-- time you actually spent together. The addon suggests; the player clicks.
-- Nothing appears during combat.
local _, FR = ...
local UI = FR.UI
local L = FR.L

local DAY = 86400

-------------------------------------------------------------------------------
-- Toast queue (friend suggestion, regroup)
-------------------------------------------------------------------------------
local toast, queue = nil, {}

local function BuildToast()
  local f = CreateFrame("Frame", "ForeverRelationshipsToast", UIParent, "BackdropTemplate")
  f:SetSize(360, 74)
  f:SetPoint("TOP", 0, -140)
  f:SetFrameStrata("DIALOG")
  f:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 14, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
  f.title = UI.Label(f, "Forever Relationships", "GameFontNormalSmall"); f.title:SetPoint("TOPLEFT", 10, -8)
  f.text = UI.Label(f, "", "GameFontHighlight"); f.text:SetPoint("TOPLEFT", 10, -24); f.text:SetWidth(340)
  f.yes = UI.Button(f, "", 110, 20); f.yes:SetPoint("BOTTOMLEFT", 10, 8)
  f.no = UI.Button(f, L["Not now"], 90, 20); f.no:SetPoint("LEFT", f.yes, "RIGHT", 6, 0)
  f:Hide()
  return f
end

local ShowNext
ShowNext = function()
  if FR.InCombat() then return end
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
-- After a session: endorsement prompt + friend suggestions
-------------------------------------------------------------------------------
local function GoodSessions(guid)
  return FR.Rel:Compute(guid).sessions
end

local function IsFriend(guid)
  return C_FriendList and C_FriendList.IsFriend and FR.SafeCall(C_FriendList.IsFriend, guid) or false
end

FR:Listen("SESSION_END", function(s)
  local members = {}
  for guid, m in pairs(s.members) do
    if guid ~= FR.playerGUID then members[#members + 1] = { guid = guid, name = m.name } end
  end
  C_Timer.After(3, function()
    FR.Rel.Invalidate()
    for _, m in ipairs(members) do
      local dismissed = FR.cdb.suggestDismissed[m.guid]
      local n = GoodSessions(m.guid)
      if n >= FR.Params:Get("suggest.friendAfterSessions") and not IsFriend(m.guid)
        and not (dismissed and FR.Now() - dismissed < 30 * DAY) then
        UI.Toast({
          text = L["You've grouped with %s %d times. Add as a friend?"]:format(FR.ShortName(m.name), n),
          yesLabel = L["Add friend"],
          onYes = function() C_FriendList.AddFriend(FR.ShortName(m.name), "Forever Relationships") end,
          onNo = function() FR.cdb.suggestDismissed[m.guid] = FR.Now() end,
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
  if not guid or guid == FR.playerGUID or IsInGroup() and FR.Sessions:Member(guid) then return end
  if not FR.db.players[guid] or GoodSessions(guid) < FR.Params:Get("suggest.regroupMinSessions") then return end
  local cd = FR.Params:Get("suggest.regroupCooldownMinutes") * 60
  if lastToast[guid] and FR.Now() - lastToast[guid] < cd then return end
  lastToast[guid] = FR.Now()
  UI.Toast({
    text = L["%s is in %s. Invite?"]:format(FR.ShortName(name), zone or L["the world"]),
    yesLabel = L["Invite"],
    onYes = function()
      local invite = (C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit
      if invite then invite(name) end
    end,
  })
end

local online = {}
FR:On("FRIENDLIST_UPDATE", function()
  if not (C_FriendList and C_FriendList.GetNumFriends) then return end
  local n = FR.SafeCall(C_FriendList.GetNumFriends) or 0
  local seen = {}
  for i = 1, n do
    local info = FR.SafeCall(C_FriendList.GetFriendInfoByIndex, i)
    if info and info.guid and info.connected then
      seen[info.guid] = true
      if online[info.guid] == false then MaybeRegroup(info.guid, info.name, info.area) end
    end
  end
  for i = 1, n do
    local info = FR.SafeCall(C_FriendList.GetFriendInfoByIndex, i)
    if info and info.guid then online[info.guid] = seen[info.guid] and true or false end
  end
end)

FR:Listen("PRESENCE_SEEN", function(guid, p) MaybeRegroup(guid, p.name, p.zone) end)
