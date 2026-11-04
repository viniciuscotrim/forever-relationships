-- Versioned consumables table for "Arriving ready" (GDD 5.3).
-- Buff rules in Forever changed late in beta: keep this in data, not code.
-- Keys are aura spell IDs; values are categories. Spell names are also
-- resolved at load so localized auras with other IDs still match.
local _, FR = ...
FR = FR or {}

FR.Consumables = {
  version = "forever-1.0-a",
  verified = false, -- flip to true once checked on the live client
  categories = { "flask", "battleElixir", "guardianElixir", "food", "zanza", "juju", "other" },
  spells = {
    -- Flasks
    [17626] = "flask", [17627] = "flask", [17628] = "flask", [17629] = "flask",
    -- Battle elixirs
    [17538] = "battleElixir", [11405] = "battleElixir", [11334] = "battleElixir",
    [17539] = "battleElixir", [11474] = "battleElixir", [26276] = "battleElixir",
    [17537] = "battleElixir", [11390] = "battleElixir", [21920] = "battleElixir",
    -- Guardian elixirs
    [11348] = "guardianElixir", [24361] = "guardianElixir", [3593] = "guardianElixir",
    [11396] = "guardianElixir", [17535] = "guardianElixir", [11349] = "guardianElixir",
    -- Food (Well Fed and stat foods)
    [19705] = "food", [19706] = "food", [19708] = "food", [19709] = "food", [19710] = "food",
    [19711] = "food", [24799] = "food", [25661] = "food", [18192] = "food", [22730] = "food",
    [18194] = "food", [18141] = "food", [18125] = "food", [24870] = "food",
    -- Zanza
    [24382] = "zanza", [24383] = "zanza", [24417] = "zanza",
    -- Juju / Blasted Lands / misc
    [16323] = "juju", [16329] = "juju", [16325] = "juju", [16321] = "juju",
    [10667] = "other", [10669] = "other", [10668] = "other", [10692] = "other",
    [10693] = "other", [25804] = "other", [15233] = "other", [15231] = "other",
  },
  -- aura names that always count as food regardless of ID
  names = { "Well Fed" },
}
