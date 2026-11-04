# Trust Advisor Network (GDD Phase 3)

## Architecture
```
Addon (in game)            Companion (desktop)              Server
 events -> reports  --SV-->  parse SavedVariables  --HTTPS-->  /v1/upload  -> SQLite
 NetData.lua  <--write--     write NetData.lua    <--HTTPS--  /v1/players, /v1/self
```
Addons cannot reach the internet, so the companion reads SavedVariables and writes a Lua data file that the addon loads on `/reload`.

## What leaves the player's machine (only with `consent.network`)
- Witness reports for **game-witnessed** dimensions only: finish, ready, loot, carry, generosity, teach, craft, help, hc, and endorsements the player gave.
- Never sent: paying and showing up (they depend on human-entered debts and signup lists), notes, affinity, chat.
- Reports use the **published protocol parameters** (`Params:DefaultSnapshot`), never local edits.
- Report = `{subject guid, dimension, outcome x, multiplier m, incident time t, kind k}`. The time is a moment all witnesses share (the leave time, last boss kill, or ready check).

## Fairness rules (locked, protocol v1): `server/trustnet/aggregate.py`
| Rule | Value |
|---|---|
| Same incident | same subject + dimension + kind, within `net.matchWindowSeconds` (600 s) |
| Each uploader counts | once per incident |
| Positive counts with | 1 witness |
| Negative or partial counts with | ≥ `net.minWitnesses` (2) uploaders from ≥ `net.minGuilds` (2) guild groups; all unguilded witnesses form one group |
| Self-reports | ignored (witness = subject, or subject among the uploader's own characters) |
| Disputes | open or upheld: excluded; rejected: counts. Only about your own characters |
| Deletion | removes everything you uploaded and hides your characters from the network view (positives and negatives) |
| Witness identity | never exposed; the public view shows only counts |

The addon computes network bands with the same engine and published parameters, from verified incidents only.

## Known risks (read before launch)
1. **Identity / sockpuppets.** Without account authentication, one person running two companion instances with forged SavedVariables can pose as two witnesses. Guild diversity (unguilded = one group) raises the bar but does not remove it.
   **Recommended before a public network launch:** Battle.net OAuth to bind uploaders to real characters (if Blizzard's API covers Forever), or a manual allowlist / invite-only beta.
2. **Character claims.** Characters are self-declared. A GUID claimed by two uploaders is *contested*: neither can see its events or hide it, and an admin must resolve it.
3. **Moderation.** Disputes need a human reviewer (admin endpoints). Budget time for this.
4. **Hosting.** Deployed at https://trustadvisor.72-62-142-237.sslip.io with daily backups. See `DEPLOY.md`.
