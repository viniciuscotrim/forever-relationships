-- Attunement quests (GDD 5.4). Fact only, never scored. Shown as "self-reported".
-- Verify IDs on the live Forever client; add or fix entries here, not in code.
local _, FR = ...
FR = FR or {}

FR.Attunements = {
  version = "forever-1.0-a",
  verified = false,
  list = {
    { key = "mc",    label = "Molten Core",           quests = { 7848 } },
    { key = "ony",   label = "Onyxia's Lair",         quests = { 6502, 6602 } }, -- Alliance / Horde
    { key = "bwl",   label = "Blackwing Lair",        quests = { 7761 } },
    { key = "ubrs",  label = "Upper Blackrock Spire", quests = { 4743 } },
    { key = "naxx",  label = "Naxxramas",             quests = { 9121, 9122, 9123 } },
  },
}
