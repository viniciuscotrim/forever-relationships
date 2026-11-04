-- First-run welcome: what Trust Advisor does, and every sharing choice in one
-- place. Everything starts OFF (GDD 11); nothing is shared until you choose.
local _, TA = ...
local UI = TA.UI

local CHOICES = {
  { key = "consent.endorsePrompts", label = "Ask \"Play with them again?\" after long sessions", note = "Local only unless you also share endorsements." },
  { key = "consent.shareEndorsements", label = "Share my endorsements with the people I endorse", note = "Needs Trust Advisor on their side." },
  { key = "consent.shareQuests", label = "Tell my group when I turn in a quest", note = "Lets partners credit you for staying to help." },
  { key = "consent.shareAttunements", label = "Share my attunements with my group", note = "Shown to them as self-reported." },
  { key = "presence.enabled", label = "Show me to nearby Trust Advisor users", note = "Zone, level, LFG flag. Invisible mode stops it anytime." },
  { key = "consent.network", label = "Join the Trust Advisor Network", note = "Needs the free companion app (/ta network)." },
}

local frame

local function Build()
  local f = UI.Window("TrustAdvisorWelcome", 560, 460, "DIALOG")
  UI.Label(f, "Welcome to Trust Advisor", "GameFontNormalLarge"):SetPoint("TOP", 0, -30)
  local intro = UI.Label(f,
    "Trust Advisor remembers how the people you group with actually behave: finishing runs, paying debts, loot honesty, "
    .. "helping, generosity. It uses only what your game witnessed, and it is fair: new players start as Unknown, "
    .. "mistakes fade, and disconnects or kicks are excused. Every rule is visible and editable in the Transparency tab.\n\n"
    .. "Nothing leaves your computer unless you turn it on below. You can change these anytime (Transparency › Parameters).\n\n"
    .. "Found a bug or have an idea? Type /ta feedback. You never need to leave the game.",
    "GameFontHighlight")
  intro:SetPoint("TOPLEFT", 20, -56)
  intro:SetWidth(520)
  f.rows = {}
  for i, c in ipairs(CHOICES) do
    local y = -196 - (i - 1) * 34
    local b = UI.Button(f, "", 64, 22)
    b:SetPoint("TOPLEFT", 20, y)
    local l = UI.Label(f, c.label, "GameFontHighlight"); l:SetPoint("TOPLEFT", 94, y - 1)
    local n = UI.Label(f, c.note, "GameFontDisableSmall"); n:SetPoint("TOPLEFT", 94, y - 15)
    b:SetScript("OnClick", function()
      TA.Params:Set(c.key, not TA.Params:Get(c.key))
      f:Refresh()
      if c.key == "consent.network" and TA.Params:Get(c.key) then UI.ShowText("Trust Advisor Network", TA.Network:SetupText()) end
    end)
    f.rows[i] = { button = b, key = c.key }
  end
  local done = UI.Button(f, "Done", 120, 24, function() f:Hide() end)
  done:SetPoint("BOTTOMRIGHT", -16, 14)
  local open = UI.Button(f, "Open Trust Advisor", 160, 24, function() f:Hide(); UI:Open("players") end)
  open:SetPoint("RIGHT", done, "LEFT", -8, 0)
  function f:Refresh()
    for _, r in ipairs(self.rows) do
      r.button:SetText(TA.Params:Get(r.key) and "|cff66ff66On|r" or "|cffaaaaaaOff|r")
    end
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
  if TA.db.welcomed then return end
  C_Timer.After(6, function()
    if TA.InCombat() then return end
    TA.db.welcomed = TA.version
    UI.ShowWelcome()
  end)
end)
