# Forever Relationships 0.5.1

### New
- **Your /played in the public profile.** *My profile* has a new item, "/played on this character", in hours and minutes. Like every profile item, it's off until you tick it. Others only ever see the /played of the character they're looking at.
- **See other players' /played.** New tooltip and Relationship item, "Their /played". It shows a player's /played if they published it in their public profile, otherwise "not public". Pick it in *My profile › Tooltip*.
- **/played of all your characters,** shown only to you, under the profile items. Each character counts from its last login with the addon.
- The addon asks the game for /played a few seconds after login, without printing the usual chat line. A /played you type still shows as usual.
- **Party welcome.** When a party forms, and whenever someone joins it later, the addon says in party chat: *"Welcome to party! Forever Relationships addon being used to eternize our time together!"* It posts at most once per player every 30 minutes and never in raids or invisible mode. If several members have the addon, only one posts. Turn it off in Privacy › Settings (`announce.party`).

# Forever Relationships 0.5.0

### New
- **Realm population (`/fr population`, or the Population tab).** See the Horde/Alliance balance and every race, in numbers and percentages. Filter by PvP or PvE realms (yours is selected first) and by faction. The tab shows the date and time the numbers were updated.
- Needs the free **companion app 0.5.0**. It refreshes the numbers every hour, even with every layer off. WoW shows new numbers after a login or `/reload`.
- The numbers come from a **population census** that is part of the **Community** layer (off by default). For characters you see (mouseover, target, nameplates, your group), the addon keeps only faction, race, class, level and the realm number from their character code. It never keeps names or locations. The server replaces each code with a keyed code and publishes only totals. Turning Community off deletes the census on your computer and on the server.
- This is a sample from Forever Relationships players, not Blizzard's numbers: Blizzard's API doesn't publish population for WoW: Forever.

### Changed
- Companion app 0.5.0: syncs right after each `/reload` or logout and again every hour; its log is now written live.

# Forever Relationships 0.4.2

### Fixed
- **Cloud layers now reach the companion app.** In 0.4.1 the addon hit an error at logout and `/reload`, so backup, public profile, community and recommend me never synced, and the companion kept asking for a `/reload`.
- **`/fr feedback` works again.** The same error stopped feedback from being saved.
- Loot quality is read correctly on the current client.
- Companion app 0.4.2 (Mac): if you opened it straight from Downloads, it now still starts after you restart your computer, as long as a copy is in Applications.

# Forever Relationships 0.4.1

### Changed
- **The addon folder is now `ForeverRelationships`.** Everything carries the new name, inside and out.
- **Your history moves automatically:** companion app 0.4.1 moves your saved data to the new name the next time it runs with WoW closed, and removes the previous addon folder. Update the companion app together with the addon.
- The short command is `/fr` (`/forever` works too).
- Server address: `forever.gameplaybr.com.br` only.

# Forever Relationships 0.4.0

**New name: Forever Relationships.** Your history carries over automatically. The command is now `/fr` (`/forever` works too).

The addon was rebuilt around one idea: an augmented view of how you relate to the people you play with, made only from facts the game recorded. Ratings, endorsements, notes and the witness Network are gone. Nothing about anyone can be typed in, so nothing can be used against anyone.

### New
- **Tooltip with your 6 facts.** Pick what the player tooltip shows: time together, last time together, days, dungeons and raids completed, kills, trades, first meeting, typical play time, level gap, zones, quests, help, crafts, loot, ready checks, Hardcore deaths witnessed, guild history or circle rank.
- **Relationship window.** Right-click any player you've played with and choose *Relationship*: **Information** (what the game recorded) next to **Knowledge** (patterns computed for you), plus the public profile they chose to publish.
- **My circle.** Everyone you've played with, sorted by time together, with search. Also: suggestions and nearby players.
- **Four optional layers, all off by default** (Privacy tab and welcome screen):
  - **Cloud backup:** encrypted on your computer, only you hold the key (a recovery code). Your history survives a reinstall or a new computer.
  - **Public profile:** show off the stats you pick about yourself. Blizzard-confirmed stats get an *Official* badge.
  - **Community:** anonymous statistics from group sessions. No names; character codes are pseudonymized on arrival.
  - **Recommend me:** suggestions among players who also opted in.
- **Your rights in one place:** see, download and delete your cloud data in game or at https://forever.gameplaybr.com.br/me (Battle.net login, works without the addon). Opting out is permanent: later data about you is discarded on arrival. Privacy policy: https://forever.gameplaybr.com.br/privacy.
- **History retention:** local history keeps 365 days by default (Settings).
- **Companion app 0.4.0** with the encrypted backup, `--restore` and `--show-recovery-code`. The old companion (0.3.x) won't sync with this version: update it from GitHub Releases.

### Removed
- Trait bands, scores, endorsements, private notes and yes/no, the Transparency tab, soft reserves, GDKP ledgers and raid signups, chat message counts, and the witness Network. Their stored data is deleted on update.

# Forever Relationships 0.3.0

### New
- **In-game feedback: `/fr feedback`.** Report a bug or suggest an idea without leaving the game; there's also a Feedback button in the main window. It's the one feedback channel. Diagnostics are optional and you can preview them; they never include names, notes or chat. Replies and status (planned, fixed…) show up in the same window. Reports travel through the companion app, and are saved until it runs.
- **Error reports in one click.** If Forever Relationships hits an error, it offers to send a report with the details already attached. This only happens outside combat, and at most once per error.
- **Welcome screen** on first login. It explains what Forever Relationships does and gathers every sharing choice in one place, all **off** until you turn them on. Reopen it with `/fr welcome`.
- **Companion app detection.** If you joined the Network but the companion app isn't syncing, Forever Relationships tells you in game and shows the setup steps (`/fr network`). `/fr status` and Transparency › Network show the companion's status and version.
- **Companion app downloads:** ready-made Windows and Mac versions, no Python needed. Run once with `--install` and it starts with your computer. Get them from the project's GitHub Releases.
- **Battle.net verification for the Network.** Run the companion once with `--link` and log in with Battle.net. A negative now only counts from witnesses linked to a real Battle.net account, and several installs on the same account count as one witness. Once Blizzard lists WoW: Forever characters, reports must also come from a character you own. Only a one-way hash of your account id is stored. Without linking, your positive reports still count.
- The network now has its own address: `forever.gameplaybr.com.br`, protected by Cloudflare.

# Forever Relationships 0.2.0

### New
- **Network (opt-in).** Join from Transparency › Network. The free companion app (see the project's GitHub) shares your game-witnessed reports and brings back a **Network** column on every player card.
  - A negative only counts when **2+ independent players from 2+ different guilds** witnessed it. Each witness must have been in the same group as the player and as each other at that moment, and must have an established, cross-checked history. Forged or copied reports don't count.
  - Only game-witnessed facts are shared, computed with the published rules, never your local edits.
  - Debts, signup lists, notes and chat never leave your computer.
  - Witnesses stay anonymous. You can see every network event about yourself and **dispute** it, and a disputed event is excluded until reviewed.
  - "Delete my network data" removes everything you shared and hides you from the network.
- **Free portals:** a group member's portal you take without paying counts as generosity for them.
- **Crafted gifts:** handing over an item you made (the "Made by" line) now counts as crafting for others, alongside enchants.
- **Ledger import (GDKP):** `/fr ledger` (they owe you) and `/fr ledger iowe` (you owe them). Paste one "Name amount" per line.
- **Match card:** click a nearby player to open their card, even if you've never grouped with them. It shows their zone, level, LFG flag and shared quests.
- **LFG marker:** listings whose leader you know show a small marker: FR, a star if any trait is Exemplary, "!" if any is Concern, and your session count.
- Player cards now show how many endorsements the player has received.

### Fixed
- A trade that only contained a crafted item could be ignored.

# Forever Relationships 0.1.1

Now on the **Release** channel, so it shows up for everyone in the CurseForge app. Same features as 0.1.0.

# Forever Relationships 0.1.0

First public release for **WoW: Forever**. Type `/fr` to open.

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
  - Soft-reserve import (`/fr sr`, softres.it CSV).
  - Raid signups with attendance tracking (`/fr signup`).
  - A debt ledger (`/fr owe`, `/fr iowe`).
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
