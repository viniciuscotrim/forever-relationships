# Trust Advisor 0.1.1

Now on the **Release** channel, so it shows up for everyone in the CurseForge app. Same features as 0.1.0.

# Trust Advisor 0.1.0

First public release for **WoW: Forever**. Type `/ta` to open.

### New
- **Player tooltips:** your history with a player at a glance, e.g. "Finishing Solid · Paying Exemplary · 4 sessions". Also shown on LFG listings.
- **Twelve separate traits instead of one score:** showing up, finishing runs, arriving ready, paying what's owed, loot honesty, carries delivered, small generosity, higher-level partner, crafting for others, stayed to help, Hardcore steadfastness, endorsements.
- **Bands, not decimals:** Unknown / Building / Solid / Exemplary, plus Concern. Every band shows its confidence.
- **Fair by design:**
  - New players start as Unknown, never as bad.
  - Mistakes fade over time while good behavior keeps adding up.
  - Disconnects, kicks, wipe streaks and disbands are excused.
  - An early leave only counts when the game itself reported a voluntary leave.
- **Player card:** a Trust tab with a "Why?" button for every trait, plus a private Affinity tab with your time together, a private yes/no and a personal note.
- **My profile:** your own traits as your client saw them, the endorsements you've received, and your attunements.
- **Transparency tab:**
  - Every parameter, formula (with live values) and capture status is visible.
  - Each parameter can be edited and reset, and every change is logged.
  - A data inventory lists everything stored and everything that can be sent.
- **Event log:** every recorded event, filterable by player, signal and source, with copy-and-paste export.
- **Questie support:** detects when a partner finishes a shared quest (requires their Questie announcements).
- **Raid tools:**
  - Soft-reserve import (`/ta sr`, softres.it CSV).
  - Raid signups with attendance tracking (`/ta signup`).
  - A debt ledger (`/ta owe`, `/ta iowe`).
- **Social:** "Play with them again?" endorsements, friend suggestions after good sessions, and invite offers when a past partner comes online. These are suggestions only; nothing happens without your click.
- **Peer features (both players need the addon, all opt-in):** shared endorsements, quest completion sharing, attunement sharing, and a "nearby players" presence channel with an invisible mode.

### Privacy
- Chat text is never stored. Only message counts are kept.
- Notes, private opinions and affinity data never leave your computer.
- Every sharing feature starts **off**.
- "Delete everything" wipes all addon data in one click.

### Known limitations
- Early release: not every live-client API has been verified yet. A capture whose API is unavailable turns itself off and shows as "unavailable" in Transparency › Captures instead of throwing errors.
- Portals and gifts of crafted items are not tracked yet. Only enchants count as crafting.
- Consumable, attunement and buff spell IDs are still being verified on the live client.

Bug reports and feedback are very welcome.
