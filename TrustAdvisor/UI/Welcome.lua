-- First-run welcome: what Forever Relationships is (an augmented view of your
-- relationships, from game data only) and the four layers, each with its own
-- plain-language consent. Everything that leaves your computer starts OFF.
local _, TA = ...
local UI = TA.UI

local CHOICES = {
  { key = "consent.backup", label = "Cloud backup", note = "Keep your history even after reinstalling. Encrypted: only you can read it.", text = "backup" },
  { key = "consent.profile", label = "Public profile", note = "Show others the numbers YOU pick about yourself.", text = "profile" },
  { key = "consent.community", label = "Community", note = "Help anonymous statistics about how people play together.", text = "community" },
  { key = "consent.recommend", label = "Recommend me", note = "Be suggested to other players who also opted in.", text = "recommend" },
}

local frame
local function Build()
  local f = UI.Window("TrustAdvisorWelcome", 580, 470, "DIALOG")
  UI.Label(f, "Welcome to Forever Relationships", "GameFontNormalLarge"):SetPoint("TOP", 0, -30)
  local intro = UI.Label(f,
    "Forever Relationships shows how you've related to the people around you: time together, dungeons completed, "
    .. "kills, trades, help, quests. It only uses what the game itself records while you play together. "
    .. "No chat, no opinions, no scores.\n\nHover a player to see your history with them, or right-click and choose Relationship. "
    .. "On this computer it works right away. Everything below is optional, starts off, and needs the free companion app.",
    "GameFontHighlight")
  intro:SetPoint("TOPLEFT", 20, -56); intro:SetWidth(540)
  f.rows = {}
  for i, c in ipairs(CHOICES) do
    local y = -186 - (i - 1) * 46
    local b = UI.Button(f, "", 64, 22); b:SetPoint("TOPLEFT", 20, y)
    local l = UI.Label(f, c.label, "GameFontHighlight"); l:SetPoint("TOPLEFT", 94, y - 1)
    local n = UI.Label(f, c.note, "GameFontDisableSmall"); n:SetPoint("TOPLEFT", 94, y - 16); n:SetWidth(380)
    local d = UI.Button(f, "Details", 70, 20, function() UI.ShowText(c.label, UI.CONSENT_TEXT[c.text]) end)
    d:SetPoint("TOPLEFT", 490, y)
    b:SetScript("OnClick", function()
      TA.Params:Set(c.key, not TA.Params:Get(c.key))
      if TA.Params:Get(c.key) then UI.ShowText(c.label, UI.CONSENT_TEXT[c.text]) end
      f:Refresh()
    end)
    f.rows[i] = { button = b, key = c.key }
  end
  local fb = UI.Label(f, "Found a bug or have an idea? Type /fr feedback. You never need to leave the game.", "GameFontHighlightSmall")
  fb:SetPoint("BOTTOMLEFT", 20, 46)
  local done = UI.Button(f, "Done", 120, 24, function() f:Hide() end); done:SetPoint("BOTTOMRIGHT", -16, 14)
  local open = UI.Button(f, "Open Forever Relationships", 160, 24, function() f:Hide(); UI:Open("circle") end)
  open:SetPoint("RIGHT", done, "LEFT", -8, 0)
  local comp = UI.Button(f, "Companion app", 130, 24, function() UI.ShowText("Companion app", TA.Cloud:SetupText()) end)
  comp:SetPoint("BOTTOMLEFT", 16, 14)
  function f:Refresh()
    for _, r in ipairs(self.rows) do r.button:SetText(TA.Params:Get(r.key) and "|cff66ff66On|r" or "|cffaaaaaaOff|r") end
  end
  return f
end

function UI.ShowWelcome()
  if TA.InCombat() then return end
  frame = frame or Build()
  frame:Refresh()
  frame:Show()
end

TA:Listen("LOGIN", function()
  if TA.db.welcomed == "v2" then return end
  C_Timer.After(6, function()
    if TA.InCombat() then return end
    TA.db.welcomed = "v2"   -- v1 users see the new layers once
    UI.ShowWelcome()
  end)
end)
