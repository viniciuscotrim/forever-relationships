# Trust Advisor 0.3.0

### New
- **In-game feedback: `/ta feedback`.** Report a bug or suggest an idea without leaving the game; there's also a Feedback button in the main window. It's the one feedback channel. Diagnostics are optional and you can preview them; they never include names, notes or chat. Replies and status (planned, fixed…) show up in the same window. Reports travel through the companion app, and are saved until it runs.
- **Error reports in one click.** If Trust Advisor hits an error, it offers to send a report with the details already attached. This only happens outside combat, and at most once per error.
- **Welcome screen** on first login. It explains what Trust Advisor does and gathers every sharing choice in one place, all **off** until you turn them on. Reopen it with `/ta welcome`.
- **Companion app detection.** If you joined the Network but the companion app isn't syncing, Trust Advisor tells you in game and shows the setup steps (`/ta network`). `/ta status` and Transparency › Network show the companion's status and version.
- **Companion app downloads:** ready-made Windows and Mac versions, no Python needed. Run once with `--install` and it starts with your computer. Get them from the project's GitHub Releases.
- **Battle.net verification for the Network.** Run the companion once with `--link` and log in with Battle.net. A negative now only counts from witnesses linked to a real Battle.net account, and several installs on the same account count as one witness. Once Blizzard lists WoW: Forever characters, reports must also come from a character you own. Only a one-way hash of your account id is stored. Without linking, your positive reports still count.
- The network now has its own address: `trustadvisor.gameplaybr.com.br`, protected by Cloudflare.

# Trust Advisor 0.2.0

### New
- **Trust Advisor Network (opt-in).** Join from Transparency › Network. The free companion app (see the project's GitHub) shares your game-witnessed reports and brings back a **Network** column on every player card.
  - A negative only counts when **2+ independent players from 2+ different guilds** witnessed it. Each witness must have been in the same group as the player and as each other at that moment, and must have an established, cross-checked history. Forged or copied reports don't count.
  - Only game-witnessed facts are shared, computed with the published rules, never your local edits.
  - Debts, signup lists, notes and chat never leave your computer.
  - Witnesses stay anonymous. You can see every network event about yourself and **dispute** it, and a disputed event is excluded until reviewed.
  - "Delete my network data" removes everything you shared and hides you from the network.
- **Free portals:** a group member's portal you take without paying counts as generosity for them.
- **Crafted gifts:** handing over an item you made (the "Made by" line) now counts as crafting for others, alongside enchants.
- **Ledger import (GDKP):** `/ta ledger` (they owe you) and `/ta ledger iowe` (you owe them). Paste one "Name amount" per line.
- **Match card:** click a nearby player to open their card, even if you've never grouped with them. It shows their zone, level, LFG flag and shared quests.
- **LFG marker:** listings whose leader you know show a small marker: TA, a star if any trait is Exemplary, "!" if any is Concern, and your session count.
- Player cards now show how many endorsements the player has received.

### Fixed
- A trade that only contained a crafted item could be ignored.

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
- Consumable, attunement and buff spell IDs are still being verified on the live client.

Bug reports and feedback are very welcome.
