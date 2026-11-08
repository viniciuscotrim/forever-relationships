-- Translations. The English text is the key: FR.L["Time together"] returns the
-- translation for the active language, or the English text when there is none.
-- Every language WoW supports has a file in Locales/ (enUS needs none).
-- The language follows the game client; /fr language <code> overrides it (after /reload).
local _, FR = ...

FR.LOCALES = { "enUS", "deDE", "esES", "esMX", "frFR", "itIT", "koKR", "ptBR", "ruRU", "zhCN", "zhTW" }
FR.LOCALE_NAMES = {
  enUS = "English", deDE = "Deutsch", esES = "Español (España)", esMX = "Español (México)", frFR = "Français",
  itIT = "Italiano", koKR = "한국어", ptBR = "Português (Brasil)", ruRU = "Русский", zhCN = "简体中文", zhTW = "繁體中文",
}

FR._locales = {}
local active = nil   -- table of the active language, nil = English

local function ClientLocale()
  local l = GetLocale and GetLocale() or "enUS"
  if l == "enGB" then l = "enUS" end
  return l
end
FR.locale = ClientLocale()

function FR:RegisterLocale(code, strings)
  self._locales[code] = strings
  if code == self.locale then active = strings end
end

-- Choose the language (called again once SavedVariables are loaded).
function FR:SetLocale(code)
  if not code or (code ~= "enUS" and not self._locales[code]) then code = ClientLocale() end
  self.locale = code
  active = self._locales[code]
end

FR.L = setmetatable({}, {
  __index = function(_, key)
    local v = active and active[key]
    if v ~= nil and v ~= "" then return v end
    return key
  end,
  __newindex = function() error("FR.L is read-only; add strings to Locales/<code>.lua") end,
})

-- Translate a string that may be nil (labels stored in data tables).
function FR.T(s)
  if s == nil then return nil end
  return FR.L[s]
end

-- "1 session" / "3 sessions": both forms are keys, so every language can translate them.
function FR.Plural(n, one, many)
  return (FR.L[n == 1 and one or many]):format(n)
end
