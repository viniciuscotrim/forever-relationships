# Testing

## Outside the game (every change)
`./install.sh` runs all of these, then installs the addon locally:

```sh
cd TrustAdvisor
luajit Tests/test_scoring.lua      # scoring engine and every trait rule
luajit Tests/test_questie.lua      # Questie announcement parser, all locales
luajit Tests/test_ingame_sim.lua   # every addon file on a mock WoW API: a dungeon run, UI, slash commands, network outbox
cd ../server    && python3 -m unittest discover -s tests   # fairness rules, Battle.net identity, API
cd ../companion && python3 -m unittest discover -s tests   # SavedVariables parser, autostart, --link, end-to-end addon -> server -> addon
python3 tools/sync_docs.py --check                         # README matches the public description
```

## In game (on every new client build)
1. `/ta status`: the interface should read 16001 and every capture should say "ok".
2. `/ta debug`, form a party, run one dungeon. In the **Event log** tab, look for:
   - `session`, and one `member` row per player;
   - `trade`, and `lootNeed` if soft reserves are loaded;
   - `quest`, from Questie or a peer.
3. Have someone leave mid-run. Their member row should say `left: voluntary`.
4. In **Transparency › Parameters**, set `conf.minEvidence` to 1. Bands should change instantly, and **Why?** should show the arithmetic.
5. Raid: run a ready check and confirm `ready` rows with consumable counts. If auras are secret on this client, Transparency › Captures shows "unavailable". That is the intended safe failure.
6. Questie: ask a partner with Questie announcements on to turn in a quest. Copy 10 real lines into `TrustAdvisor/Tests/test_questie.lua`.
7. Check the IDs in `TrustAdvisor/Data/*.lua` (consumables, attunements, generosity spells) on the live client, then set `verified = true`.
8. Network:
   - turn on **Join the Trust Advisor Network**, then `/reload`;
   - open the companion and link Battle.net;
   - `/reload` again: `/ta network` should say *syncing* and *linked*.
