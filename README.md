<p align="center"><img src="branding/logo-400.png" width="160" alt="Trust Advisor logo"></p>

# Trust Advisor

**Remember who you'd group with again.** A World of Warcraft: Forever addon that builds a fair, forgiving reputation from what the game actually witnessed, with every rule visible and editable.

- Tooltip on players and LFG listings: *"Finishing Solid · Paying Exemplary · 4 sessions"*
- Twelve separate traits instead of one score, shown as bands (Unknown / Building / Solid / Exemplary / Concern) with confidence
- Forgiving by design: new players start Unknown, mistakes fade, disconnects/kicks/wipes are excused
- Full transparency: every parameter and formula is editable, and a "Why?" button shows the exact math behind every band
- Private affinity notes that never leave your computer; all sharing features are opt-in

Type `/ta` in game. See [`TrustAdvisor/README.md`](TrustAdvisor/README.md) for testing and design notes, and [`CHANGELOG.md`](CHANGELOG.md) for releases.

## Development
```sh
cd TrustAdvisor
luajit Tests/test_scoring.lua     # scoring engine and dimension rules
luajit Tests/test_questie.lua     # Questie announcement parser
luajit Tests/test_ingame_sim.lua  # all files on a mock WoW API, replaying a dungeon run
```
Network: [`server/`](server) (aggregation + API, Python stdlib + SQLite) and [`companion/`](companion) (desktop sync app).

`./install.sh` runs the tests and copies the addon into the Forever AddOns folder. `./publish.sh <projectId> [alpha|beta|release]` uploads a release to CurseForge (reads the author token from a local, git-ignored file).

## Status
Released (0.2.0). Network (Phase 3) code is complete and tested end to end; the server still has to be hosted (see [`docs/NETWORK.md`](docs/NETWORK.md)). Not yet verified on every live-client API; unavailable captures disable themselves safely.
