# CurseForge texts — Trust Advisor

<!--
SINGLE SOURCE OF TRUTH for every public description.
- "Summary" -> the CurseForge Summary field (and the GitHub repository description).
- "Description" -> the CurseForge Description field, AND copied verbatim into the
  repository README by tools/sync_docs.py. install.sh fails if they drift.
Edit here, then run: python3 tools/sync_docs.py
-->

## Summary (short field)

Remember who you'd group with again. Fair, forgiving reputation built from what the game actually saw, with every rule visible.

## Description (long field)

<!-- PUBLIC-DESCRIPTION:START -->
### Remember who you'd play with again.

You've had a great run with a stranger. They stayed after their quest was done, waited while you finished yours, and gave you a buff on the way out. A week later you can't remember their name.

You've also met the other kind: the one who grabbed the drop and was gone before the last boss.

**Trust Advisor remembers both for you, and it's fair about it.**

> **Found a bug or have an idea? Type `/ta feedback` in game.**
> It's the one place for all feedback. You never need to leave the game, and replies from the developer show up right there. If Trust Advisor ever hits an error, it offers to send a report for you with one click.

### What it does

- **Hover a player, see your history.** One tooltip line shows how much you've grouped with them and what stood out, for example *"Finishing Solid · Paying Exemplary · 4 sessions"*. LFG listings get the same line, plus a small marker for leaders you know.
- **Twelve separate traits, never one score.** Showing up, finishing runs, arriving ready, paying what's owed, loot honesty, delivering carries, small generosity, being a higher-level partner, crafting for others, staying to help, Hardcore steadfastness, and endorsements. Each one is shown on its own as a band (*Unknown, Building, Solid, Exemplary*, or *Concern*), together with how confident it is.
- **Built from what the game saw, not from gossip.** Trust Advisor records group sessions, boss kills, loot, trades and ready checks. Only an event your own game client witnessed can lower a band, so it can't be used to badmouth anyone.
- **Your private notes.** A personal note, a private yes/no, and a summary like *"Grouped 4 times, 3h 20m, you both play weekday evenings"*. This never leaves your computer and never affects anyone's reputation.
- **Keep the good ones.** After a few good sessions it suggests adding the player as a friend. When a past partner comes online, it offers a one-click invite. It only suggests; you always click.
- **Works with Questie.** If your partner has Questie announcements on, Trust Advisor notices when they finish a shared quest and stay to help you.
- **Raid and GDKP tools.** Import soft reserves (softres.it CSV) and GDKP ledgers, and track raid signups against who actually showed up.

### Fair by design

- **New players start as *Unknown*, never as bad.** Little data shows as low confidence, not as a low score.
- **Old mistakes fade, while good behavior keeps adding up.**
- **Bad luck isn't punished.** Disconnects, being kicked, wipe streaks and groups that disband are excused automatically. An early leave only counts when the game itself reported a voluntary leave.

### Fully transparent, no black box

Every weight, timer, threshold and formula is visible in the **Transparency** tab, and you can change any of them. Click **"Why?"** on any rating to see every event behind it and the exact math. You can also browse the raw event log, export it, or delete everything with one button.

### Private and opt-in

- Chat text is **never** stored. Only message counts are kept.
- Notes and private opinions are **never** sent to anyone.
- **Every sharing feature starts off.** A welcome screen on first login lets you choose: endorsement prompts, sharing endorsements, quest and attunement sharing, the "nearby players" presence channel, and the Network. Invisible mode stops all broadcasting with one click.

### Trust Advisor Network (optional)

Join the Network to also see what *other* players witnessed.
- **It needs the free companion app,** because WoW addons can't use the internet. Download it from the GitHub page linked below.
- **Mac:** open *Trust Advisor Companion.app*, which is signed and notarized by Apple, and it sets itself up.
- **Windows:** run the companion once with `--install`.

The rules are built so the Network can't be used to harm anyone:
- **Only game-witnessed facts are shared.** They're computed with the published rules, never your local edits. Debts, signup lists, notes and chat stay on your computer.
- **A negative only counts when two or more independent players, from two or more different guilds, witnessed it.** Each of those witnesses must:
  - have been in the same group as you and as each other at that moment;
  - have an established, cross-checked history;
  - be linked to a real Battle.net account. One account counts as one witness, however many installs it has.
- **Witnesses stay anonymous.** You can see everything the Network says about you and dispute it, and a disputed event is excluded until it's reviewed.
- **"Delete my network data" removes everything you shared** and hides you from the Network.
- **You don't have to link Battle.net.** Linking is what lets *your* negative reports count. Your positive reports count either way. Only a one-way hash of your account id is stored.

### Better with friends, works alone

Everything works even if nobody else has the addon. If your group mates also run Trust Advisor, you can exchange "I'd play with you again" endorsements and see who's questing nearby. Both are opt-in.

### Commands

`/ta` opens the window. Other useful commands:
- `/ta feedback`: report a bug or suggest an idea, without leaving the game
- `/ta network`: Network status and companion setup
- `/ta welcome`: your sharing choices
- `/ta why <name> <trait>`: the math behind a band
- `/ta help`: every command

### Good to know

- Made for **WoW: Forever**. The interface is in English.
- **Early release.** If a game feature isn't available on your client, that part turns itself off safely and shows as "unavailable" in Transparency › Captures instead of throwing errors.
- **Feedback and bug reports: `/ta feedback` in game.** It's the only channel, so please don't use comments for bug reports. That way nothing gets lost.
- **The companion app also delivers your feedback.** Without it, reports are saved and sent the first time it runs.
- Source code and companion downloads: **https://github.com/viniciuscotrim/trust-advisor**
<!-- PUBLIC-DESCRIPTION:END -->
