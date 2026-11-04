# Testing

## Outside the game (every change)
`./install.sh` runs all of these, then installs the addon locally:

```sh
cd ForeverRelationships
luajit Tests/test_relationship.lua # relationship stats, tooltip fields, v1 -> v2 migration
luajit Tests/test_questie.lua      # Questie announcement parser, all locales
luajit Tests/test_ingame_sim.lua   # every addon file on a mock WoW API: a dungeon run, UI, slash commands, cloud outbox
cd ../server    && python3 -m unittest discover -s tests   # consents, pseudonyms, exclusions, backups, /me, cockpit
cd ../companion && python3 -m unittest discover -s tests   # SavedVariables parser, autostart, --link, backup encryption, end-to-end addon -> server -> addon
python3 tools/sync_docs.py --check                         # README matches the public description
```

## In game (on every new client build)
1. `/fr status`: the interface should read 16001 and every capture should say "ok".
2. `/fr debug`, form a party, run one dungeon. In the **Event log** tab, look for:
   - `session`, and one `member` row per player;
   - `kill`, `trade`, `loot`, and `quest` (from Questie or a peer).
3. Hover a group member: the tooltip shows "Your relationship" with your 6 chosen facts. Right-click them → **Relationship**: Information and Knowledge are filled.
4. **My profile:** change the tooltip facts; the tooltip follows.
5. Raid: run a ready check and confirm `ready` rows. If auras are secret on this client, `/fr status` shows "unavailable". That is the intended safe failure.
6. Questie: ask a partner with Questie announcements on to turn in a quest. Copy 10 real lines into `ForeverRelationships/Tests/test_questie.lua`.
7. Check the IDs in `ForeverRelationships/Data/*.lua` (consumables, attunements, generosity spells) on the live client, then set `verified = true`.
8. Feedback: `/fr feedback` → send a test idea → `/reload`. Then `tools/feedback.sh` should show it. Reply with `tools/feedback.sh reply <id> planned "test"` and `/reload` twice: the status and reply appear in the window.
9. Cloud:
   - in **Privacy**, turn on Cloud backup and Public profile, then `/reload`;
   - open the companion: save the recovery code, link Battle.net;
   - `/reload` again: `/fr cloud` should say *syncing* and *linked*, and Privacy shows the backup size.
