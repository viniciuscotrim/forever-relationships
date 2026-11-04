-- In-game feedback: the ONLY feedback channel. /ta feedback
-- Reports are stored in SavedVariables and delivered by the companion app on
-- the next sync (addons cannot use the internet). Status and replies come back
-- through the same companion and show here. Lua errors from Trust Advisor offer
-- a one-click, pre-filled report.
local _, TA = ...
local UI = TA.UI

local FB = {}
TA.Feedback = FB

local MAX_TEXT = 1000
local MAX_OUTBOX = 50

local function RandomHex(n)
  local t = {}
  for i = 1, n do t[i] = string.format("%x", math.random(0, 15)) end
  return table.concat(t)
end

function FB:State()
  local f = TA.db.feedback
  if not f.installId then
    math.randomseed(math.floor((GetTime and GetTime() or 0) * 1000) + TA.Now())
    f.installId = RandomHex(32)   -- separate from the network identity, on purpose
  end
  f.outbox = f.outbox or {}
  return f
end

-- Diagnostics: versions, client, what is unavailable, recent errors, counts.
-- Never names, notes, chat or anything about other players.
function FB:Diagnostics()
  local _, build, _, iface = GetBuildInfo()
  local d = {
    addon = TA.version, build = tostring(build), interface = tostring(iface),
    locale = GetLocale and GetLocale() or "?",
    companion = TA.Cloud and TA.Cloud:CompanionStatus() or "?",
    companionVersion = TA.Cloud and TA.Cloud:CompanionVersion() or nil,
    layers = (TA.Params:Get("consent.backup") and "B" or "") .. (TA.Params:Get("consent.profile") and "P" or "") .. (TA.Params:Get("consent.community") and "C" or ""),
    players = 0, events = TA.Log.count, unavailable = {}, errors = {},
  }
  for _ in pairs(TA.db.players) do d.players = d.players + 1 end
  for _, n in ipairs(TA.CaptureOrder) do
    local c = TA.Captures[n]
    if c.status ~= "ok" then d.unavailable[#d.unavailable + 1] = n .. ": " .. tostring(c.reason) end
  end
  local errs = TA.db.errors or {}
  for i = math.max(1, #errs - 4), #errs do
    local e = errs[i]
    if e then d.errors[#d.errors + 1] = string.format("x%d %s", e.count, e.msg) end
  end
  return d
end

function FB:DiagnosticsText(d)
  d = d or self:Diagnostics()
  local L = {
    "Trust Advisor " .. d.addon .. " · client " .. d.build .. " · interface " .. d.interface .. " · " .. d.locale,
    "Companion: " .. d.companion .. (d.companionVersion and (" (" .. d.companionVersion .. ")") or "") .. " · layers " .. (d.layers ~= "" and d.layers or "none"),
    string.format("%d players known, %d events recorded", d.players, d.events),
    "Unavailable features: " .. (#d.unavailable > 0 and table.concat(d.unavailable, "; ") or "none"),
  }
  if #d.errors > 0 then
    L[#L + 1] = "Recent errors:"
    for _, e in ipairs(d.errors) do L[#L + 1] = "  " .. e end
  else
    L[#L + 1] = "Recent errors: none"
  end
  return L
end

function FB:Submit(kind, text, withDiag)
  text = tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if text == "" and kind ~= "bug" then return false, "Please write a few words." end
  local f = self:State()
  if #f.outbox >= MAX_OUTBOX then return false, "Too many reports are waiting to be sent. Is the companion app running?" end
  local report = {
    id = f.installId:sub(1, 8) .. "-" .. TA.Now() .. "-" .. RandomHex(4),
    t = TA.Now(), kind = kind, text = text:sub(1, MAX_TEXT), version = TA.version,
    diag = withDiag and self:Diagnostics() or nil,
  }
  table.insert(f.outbox, report)
  TA:Fire("DATA_CHANGED")
  return true, report
end

-- Status/replies written into NetData.lua by the companion.
function FB:StatusOf(id)
  local nd = _G.TrustAdvisorNetData
  local s = nd and nd.feedback and nd.feedback[id]
  return s
end

local STATUS_TEXT = {
  received = "|cff66ccffReceived|r", planned = "|cffffd100Planned|r", fixed = "|cff66ff66Fixed|r",
  done = "|cff66ff66Done|r", wontfix = "|cffaaaaaaWon't do|r", duplicate = "|cffaaaaaaDuplicate|r",
}

function FB:StatusText(report)
  local s = self:StatusOf(report.id)
  if s then return STATUS_TEXT[s.status] or ("|cff66ccff" .. tostring(s.status) .. "|r"), s.reply end
  return "|cffff9933Waiting to be sent|r", nil
end

function FB:DeliveryNote()
  if TA.Cloud and TA.Cloud:CompanionSeen() then
    return "|cff66ff66Sent automatically the next time you log out or /reload.|r"
  end
  return "|cffff9933Addons can't use the internet: your report is saved on this computer and sent automatically as soon as the free "
    .. "Trust Advisor companion app runs here (setup: /ta cloud). Status and replies show up in this window.|r"
end

-------------------------------------------------------------------------------
-- Window
-------------------------------------------------------------------------------
local win

local function Build()
  local f = UI.Window("TrustAdvisorFeedback", 600, 470, "DIALOG")
  UI.Label(f, "Send feedback to the Trust Advisor developer", "GameFontNormalLarge"):SetPoint("TOP", 0, -28)
  local sub = UI.Label(f, "This is the one place for bug reports and ideas. You never need to leave the game.", "GameFontHighlightSmall")
  sub:SetPoint("TOP", 0, -48)

  f.kind = "bug"
  f.bugBtn = UI.Button(f, "Something's broken", 160, 22, function() f.kind = "bug"; f:Refresh() end)
  f.bugBtn:SetPoint("TOPLEFT", 20, -70)
  f.ideaBtn = UI.Button(f, "Idea / suggestion", 160, 22, function() f.kind = "idea"; f:Refresh() end)
  f.ideaBtn:SetPoint("LEFT", f.bugBtn, "RIGHT", 6, 0)

  local bg = CreateFrame("Frame", nil, f, BackdropTemplateMixin and "BackdropTemplate" or nil)
  bg:SetPoint("TOPLEFT", 20, -100); bg:SetSize(560, 130)
  if bg.SetBackdrop then
    bg:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    bg:SetBackdropColor(0, 0, 0, 0.6)
  end
  local eb = CreateFrame("EditBox", nil, bg)
  eb:SetMultiLine(true); eb:SetFontObject(ChatFontNormal); eb:SetAutoFocus(false); eb:SetMaxLetters(MAX_TEXT)
  eb:SetPoint("TOPLEFT", 8, -8); eb:SetPoint("BOTTOMRIGHT", -8, 8)
  eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  eb:SetScript("OnTextChanged", function(self) f.count:SetText(#self:GetText() .. "/" .. MAX_TEXT) end)
  bg:EnableMouse(true); bg:SetScript("OnMouseDown", function() eb:SetFocus() end)
  f.edit = eb
  f.hint = UI.Label(bg, "", "GameFontDisableSmall"); f.hint:SetPoint("TOPLEFT", 10, -10); f.hint:SetWidth(530)
  eb:SetScript("OnEditFocusGained", function() f.hint:Hide() end)
  f.count = UI.Label(f, "0/" .. MAX_TEXT, "GameFontDisableSmall"); f.count:SetPoint("TOPRIGHT", bg, "BOTTOMRIGHT", 0, -2)

  f.withDiag = true
  f.diagBtn = UI.Button(f, "", 190, 20, function() f.withDiag = not f.withDiag; f:Refresh() end)
  f.diagBtn:SetPoint("TOPLEFT", bg, "BOTTOMLEFT", 0, -6)
  local see = UI.Button(f, "What's included?", 130, 20, function() UI.ShowText("Diagnostics sent with your report", FB:DiagnosticsText()) end)
  see:SetPoint("LEFT", f.diagBtn, "RIGHT", 6, 0)
  UI.Tooltip(see, "Diagnostics", { "Addon and client versions, which features are unavailable on your client, recent Trust Advisor errors, and simple counts. Never names, notes, chat or anything about other players." })

  f.send = UI.Button(f, "Send", 100, 24, function()
    local ok, res = FB:Submit(f.kind, f.edit:GetText(), f.withDiag)
    if not ok then TA.Print(res); return end
    f.edit:SetText(""); f.edit:ClearFocus(); f.hint:Show()
    TA.Print("Thanks! Feedback saved. " .. (TA.Cloud:CompanionSeen() and "It will be sent on your next logout or /reload."
      or "It will be sent when the companion app runs (/ta cloud)."))
    f:Refresh()
  end)
  f.send:SetPoint("TOPRIGHT", bg, "BOTTOMRIGHT", 0, -22)

  f.note = UI.Label(f, "", "GameFontHighlightSmall"); f.note:SetPoint("TOPLEFT", 20, -290); f.note:SetWidth(560)

  UI.Label(f, "Your reports", "GameFontNormal"):SetPoint("TOPLEFT", 20, -330)
  f.list = UI.List(f, 18, 6, function(row)
    row.text = UI.Label(row, "", "GameFontHighlightSmall"); row.text:SetPoint("LEFT", 4, 0); row.text:SetWidth(400); row.text:SetWordWrap(false)
    row.status = UI.Label(row, "", "GameFontHighlightSmall"); row.status:SetPoint("LEFT", 410, 0)
    row:SetScript("OnEnter", function(self)
      if not self.report then return end
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:SetText(self.report.kind == "bug" and "Bug report" or "Idea", 1, 1, 1)
      GameTooltip:AddLine(self.report.text ~= "" and self.report.text or "(no text, diagnostics only)", 0.9, 0.9, 0.9, true)
      local st, reply = FB:StatusText(self.report)
      GameTooltip:AddLine("Status: " .. st)
      if reply then GameTooltip:AddLine("Reply: " .. reply, 0.4, 1, 0.4, true) end
      GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end, function(row, r)
    row.report = r
    local st, reply = FB:StatusText(r)
    row.text:SetText(string.format("%s  %s  %s", date("%m-%d", r.t), r.kind == "bug" and "|cffff9933Bug|r" or "|cff66ccffIdea|r",
      (r.text ~= "" and r.text or "(diagnostics only)"):gsub("\n", " ")))
    row.status:SetText(st .. (reply and " |cff66ff66(reply)|r" or ""))
  end)
  f.list:SetPoint("TOPLEFT", 16, -348)
  f.list:SetSize(570, 110)

  function f:Refresh()
    self.bugBtn:SetText(self.kind == "bug" and "|cffffd100> Something's broken|r" or "Something's broken")
    self.ideaBtn:SetText(self.kind == "idea" and "|cffffd100> Idea / suggestion|r" or "Idea / suggestion")
    self.hint:SetText(self.kind == "bug" and "What happened, and what did you expect? (Diagnostics are attached, so a short note is enough.)"
      or "What would you like Trust Advisor to do differently?")
    if self.edit:GetText() ~= "" or self.edit:HasFocus() then self.hint:Hide() else self.hint:Show() end
    self.diagBtn:SetText(self.withDiag and "|cff66ff66Include diagnostics: On|r" or "Include diagnostics: Off")
    self.note:SetText(FB:DeliveryNote())
    local items = {}
    local outbox = FB:State().outbox
    for i = #outbox, 1, -1 do items[#items + 1] = outbox[i] end
    self.list:SetItems(items)
  end
  return f
end

function UI.ShowFeedback(kind, prefill)
  if TA.InCombat() then TA.Print("Feedback opens after combat."); return end
  win = win or Build()
  win.kind = kind or win.kind
  if prefill then win.edit:SetText(prefill) end
  win:Refresh()
  win:Show()
end

-------------------------------------------------------------------------------
-- Error -> suggest a report (once per distinct error per session, max 3, never in combat)
-------------------------------------------------------------------------------
local prompted, promptCount = {}, 0
TA:Listen("ERROR_RECORDED", function(e)
  if prompted[e.msg] or promptCount >= 3 or not UI.Toast then return end
  prompted[e.msg] = true
  promptCount = promptCount + 1
  local function offer()
    if TA.InCombat() then C_Timer.After(5, offer); return end
    UI.Toast({
      text = "Trust Advisor hit an error. Send a report so it gets fixed? The error details are attached for you.",
      yesLabel = "Report it",
      onYes = function() UI.ShowFeedback("bug", "") end,
    })
  end
  C_Timer.After(2, offer)
end)
