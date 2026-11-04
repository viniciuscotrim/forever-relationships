# How Forever Relationships works

## Game facts in, no opinions
The addon only **records facts the game produced** while you play with others: who was in the group and when, where, boss kills and completed content, loot, trades, ready checks, buffs, resurrections, summons and portals, quests, Hardcore deaths, and each player's game-visible name, class, race, faction, level and guild. There is nothing to type about anyone: no notes, ratings, scores or guesses.

## Information and Knowledge
- **Information** is what happened: time together, places, kills, trades, help.
- **Knowledge** is patterns computed for you from that information: when you usually play together, favorite zones, level gap, where someone ranks in your circle.

Both are recomputed from the event log when you look (`Relationship/Stats.lua`). The tooltip shows the 6 facts you choose; the Relationship window shows them all.

## Known limits
- **Summons and portals:** your own warlock summons and a group member's free portal are credited. Who clicked a summoning portal is being validated on the live client (BACKLOG FR-1).
- **Crafted gifts** are detected from the item's "Made by" line.
- **Quests from partners** need Questie announcements or the addon on their side.
- If a game API isn't available on your client, that capture turns itself off and `/fr status` shows it as unavailable.
- **Interface is English only.**

## Cloud layers
All off by default: encrypted backup, public profile, community, recommend me. They need the companion app. See [NETWORK.md](NETWORK.md) for exactly what is sent, how it is stored and for how long.
