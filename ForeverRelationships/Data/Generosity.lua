-- Spells that count as small generosity when YOU cast them on a non-party
-- player (GDD 5.8). Others' generosity toward you is detected generically
-- from helpful auras and resurrection/summon offers, so it needs no table.
local _, FR = ...
FR = FR or {}

FR.GenerositySpells = {
  version = "forever-1.0-a",
  verified = false,
  -- base-rank spell IDs; names are resolved at load so every rank matches
  buffs = { 1459, 1243, 1126, 19740, 19742, 20217, 19977, 1038, 20911, 14752, 976, 5697, 21562, 21849 },
  rez = { 2006, 7328, 2008, 20484, 20707 },
  summon = { 698 },
  -- Mage portals. A portal counts as generosity only when you used it (zoned
  -- shortly after the cast) and gave the mage no gold (generosity.portalWindowMinutes).
  portal = { 10059, 11416, 11419, 11417, 11418, 11420, 32266, 32267, 33691, 35717, 49360, 49361 },
}
