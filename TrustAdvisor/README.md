# Trust Advisor (WoW: Forever)

Fair, forgiving, transparent reputation for the people you group with. Built from
`Trust Advisor — Game Design Document.md` (Phases 1 and 2; Phase 3 network is not built).

## Install / update
`./install.sh` (one folder up) runs all tests, then copies the addon into
`/Applications/World of Warcraft/_forever_/Interface/AddOns/TrustAdvisor`. In game: `/reload`.

## Tests (outside the game)
```
cd TrustAdvisor
luajit Tests/test_scoring.lua     # engine + every dimension rule (GDD 12 cases)
luajit Tests/test_questie.lua     # Questie announcement fixtures, all locales
luajit Tests/test_ingame_sim.lua  # loads every file on a mock WoW API, replays a dungeon run, drives UI + slash commands
```

## Launch-day checklist (GDD 12), in game
1. `/ta status`: interface should read 16001 and every capture should say "ok".
2. `/ta debug`, form a party, run one dungeon. In the **Event log** tab, check for
   `session`, `member` (one per player), `trade`, `lootNeed` (if soft reserves are loaded), and `quest` (Questie/peer).
3. Make someone leave mid-run. Their member row should say `left: voluntary`.
4. In **Transparency › Parameters**, change `conf.minEvidence` to 1. Bands should change instantly, and **Why?** shows the arithmetic.
5. Raid: run a ready check and confirm `ready` rows with consumable counts. If auras are secret, Transparency › Captures shows "unavailable". That is the intended safe failure.
6. Questie: ask a partner with Questie announcements on to turn in a quest. Copy 10 real lines into `Tests/test_questie.lua`.
7. Check the IDs in `Data/*.lua` (consumables, attunements, generosity spells) on the live client. Set `verified = true` once checked.

## Design notes / known limits
- **Raw facts only at capture. All rules run at scoring time.** Session length, loot-and-leave windows, DC grace, wipe excuses, late/no-show, and pay deadlines are all parameters. Changing any of them rescores history retroactively.
- **Early leaves need proof.** With `finish.requireLeaveMessage` on (the default), an early leave is scored only when the game printed a voluntary-leave message. A leader's kick by someone else can't be told apart from a leave, so unconfirmed leaves are shown but not scored.
- **Carry detection is heuristic.** A gold trade inside an instance before the final boss counts as a carry. Turn it off with `carry.autoDetect`.
- **Obligations are human-entered** (`/ta owe`), and only the trades you take part in are witnessed.
- **Portals** count only when you zone shortly after a group member's portal and gave them no gold. **Crafted gifts** are detected from the item's "Made by" tooltip line.
- **Network (Phase 3)** needs the companion app and a hosted server. See `../docs/NETWORK.md`, including the known identity risks.
- **Opt-in by default.** Presence, quest sharing, attunement sharing, endorsement sharing, and endorsement prompts all start OFF (Transparency › Consent / Social).
