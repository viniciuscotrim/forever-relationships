# CurseForge texts — Forever Relationships

<!--
SINGLE SOURCE OF TRUTH for every public description.
- "Summary" -> the CurseForge Summary field (and the GitHub repository description).
- "Description" -> the CurseForge Description field, AND copied verbatim into the
  repository README by tools/sync_docs.py. install.sh fails if they drift.
Edit here, then run: python3 tools/sync_docs.py
-->

## Summary (short field)

See your history with everyone you play with: time together, dungeons cleared, help given. Game facts only, no ratings. Optional encrypted backup.

## Description (long field)

<!-- PUBLIC-DESCRIPTION:START -->
### Every group leaves a story. Forever Relationships keeps it.

You spent an evening clearing a dungeon with a stranger. A week later they whisper you, and you can't remember the name.

**Hover them and it's all there:** *"6h 40m together · 3 days · last together yesterday in Stratholme · 4 dungeons completed · 112 kills · 2 trades."*

Forever Relationships is an augmented view of how you relate to the people you play with. It only uses what your game recorded. There are no ratings, no notes about people and no guesses.

> **Found a bug or have an idea? Type `/fr feedback` in game.**
> It's the one place for all feedback. You never need to leave the game, and replies from the developer show up right there. If the addon ever hits an error, it offers to send a report for you with one click.

### What it does

- **Hover a player, see your shared history.** You choose the 6 facts the tooltip shows, from time together, last time together, days played, dungeons and raids completed, kills, trades, first meeting, typical play time, level gap, zones, shared quests, help, crafts, loot and more. LFG listings show a small marker for people you've played with before.
- **Right-click any player, then choose *Relationship*.** You get the full picture on one page:
  - **Information:** the facts the game recorded, such as group time, places, completed content, kills, trades, buffs, resurrections, summons and portals, ready checks, loot, and Hardcore deaths you witnessed together.
  - **Knowledge:** patterns computed for you from those facts. Examples: when you usually play together, your favorite zones together, and where they rank in your circle.
- **My circle.** Everyone you've played with, sorted by time together, searchable by name or guild.
- **Know who's coming.** When someone you have history with comes into view, a pop-up tells you who it is and what you've done together, even from nameplate distance. Drag it anywhere; turn it off in Settings (`nearby.alert`). `/fr alert` shows a sample to place it.
- **Rivals.** Players of the other faction are counted too, but not by time together: how often your paths crossed, how many battles you fought, your victories and your deaths, each with its percentage, plus how each rival compares with all your rivals. Fought rivals can trigger the pop-up as well.
- **Groups.** Sort the people in your circle into groups. *Quest Helper*, *Dungeon Buddy*, *Raid Champion* and *Rival* fill themselves from what the game recorded; add or remove anyone by hand, and create your own groups. Filter the Circle by group. Groups stay on your computer.
- **Keep the good ones.** After you've spent real time together, it suggests adding the player as a friend, and offers a one-click invite when a past partner comes online. It only suggests; you always click.
- **Realm population.** The *Population* tab shows the Horde/Alliance balance and every race, in numbers and percentages, for PvP or PvE realms (yours by default), with the date and time of the last update. It comes from the companion app and refreshes every hour.
- **Says hello to your party.** When a party forms, and when someone joins, one line in party chat tells everyone the group uses Forever Relationships. If several members have the addon, only one of them posts. Turn it off in Settings (`announce.party`).
- **Ding!** When you level up, one line in party and guild chat: "Ding! I've reached level 30!", in your language. Turn each one off in Settings (`announce.dingParty`, `announce.dingGuild`).
- **Invite macro, ready to use.** `/fr macro` (or Settings › Invite macro) creates it in one click and puts it on your cursor. Mouse over a player and click to invite them; Shift+click asks to join their group. You can also copy the text to share it.
- **Your /played, all characters.** *My profile* shows your total /played across your characters, for your eyes only. Publish one character's /played if you like, and see the /played others published in their tooltip.
- **Works with Questie.** If your partner has Questie announcements on, shared quest completions are recorded too.

### Game facts only

Forever Relationships records **information** (what happened) and **knowledge** (patterns in it). It never records opinions:
- no scores, ratings, likes or dislikes;
- no notes about anyone (group names are your own labels and never leave your computer);
- no chat text;
- no guesses about anyone's intentions.

Nobody can use it to badmouth anyone: nothing you type is ever shared.

### Four optional layers, all off by default

Everything above works on your computer, alone. If you want more, the welcome screen lets you turn on any of these:

1. **Cloud backup.** Your history survives a reinstall, a new computer or a wiped WTF folder. It's encrypted on your computer before it leaves, and only you hold the key, as a recovery code you save in your password manager. Nobody else can read it, including us.
2. **Public profile.** Show off the stats *you* pick about yourself, like /played on that character, hours in groups, dungeons completed or people met. Stats Blizzard confirms for your Battle.net-linked character get an *Official* badge; the others say *Recorded by the addon*.
3. **Community.** Share your group sessions and a population census (only faction, race, class and level of characters you see) for anonymous statistics. Names never leave your computer, every character code is pseudonymized on arrival, and results are only shown in aggregate.
4. **Recommend me.** Get suggested to other players looking for company, and see suggestions yourself. Only players who also turned this on are ever suggested.

The cloud layers need the free **companion app**, because WoW addons can't use the internet:
- **Mac:** open *Forever Relationships Companion.app* (signed and notarized by Apple). It sets itself up.
- **Windows:** run the companion once with `--install`.

### Your data, your rules

- **See, download and delete** your cloud data anytime, in game or at https://forever.gameplaybr.com.br/me with your Battle.net login. That page works even if you never installed the addon.
- **Opt out for good.** If you ask to be excluded, the server throws away any data about you that arrives later.
- Built to follow **GDPR** and **LGPD**. Read the privacy policy at https://forever.gameplaybr.com.br/privacy.
- **Delete everything here** wipes the local history with one button.

### Commands

`/fr` opens the window (`/forever` works too). Other useful commands:
- `/fr feedback`: report a bug or suggest an idea, without leaving the game
- `/fr translate`: suggest a better translation in your language
- `/fr population`: realm population by faction and race
- `/fr settings`: every option (also the **Settings** button at the top of `/fr`)
- `/fr macro`: the invite / join-group macro
- `/fr privacy`: your layers, the companion app and your data
- `/fr player <name>`: your relationship with a player
- `/fr help`: every command

### Good to know

- Made for **WoW: Forever**. Available in every language WoW supports: English, Deutsch, Español (España and México), Français, Italiano, 한국어, Português (Brasil), Русский, 简体中文 and 繁體中文. It follows your game's language; `/fr language <code>` picks another. Spotted a clumsy translation? `/fr translate` sends a better one from inside the game.
- **Updating from an older version?** Your history carries over automatically.
- **Early release.** If a game feature isn't available on your client, that part turns itself off safely instead of throwing errors.
- **Feedback and bug reports: `/fr feedback` in game.** It's the only channel, so please don't use comments for bug reports. That way nothing gets lost.
- **The companion app also delivers your feedback.** Without it, reports are saved and sent the first time it runs.
- Unofficial addon, not affiliated with Blizzard Entertainment.
- Source code and companion downloads: **https://github.com/viniciuscotrim/forever-relationships**
<!-- PUBLIC-DESCRIPTION:END -->
