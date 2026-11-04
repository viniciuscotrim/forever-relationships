# Development backlog

Internal work items. Player feedback arrives through `/fr feedback` (read it with `tools/feedback.sh`).

## FR-1 · Credit the helpers who click a summoning portal (raids)

**Status:** live validation scheduled for 2026-11-05.

**Why:** in raids, the two players who click a warlock's Ritual of Summoning portal, or a meeting stone, spend real time getting the raid together. Today only the warlock gets credit: the receiver's client sees the summon offer via `CONFIRM_SUMMON` and `C_SummonInfo.GetSummonConfirmSummoner`, and the warlock's own cast is credited since `3613d87`. The clickers aren't recorded.

**What we don't know yet (validate live on WoW: Forever):**
1. The spell id of Ritual of Summoning on this client. `Data/Generosity.lua` uses vanilla `698`.
2. Which spell or event a clicker produces when right-clicking the portal: a channel on the clicker? a `UNIT_SPELLCAST_*` with what id? Is it visible to other raid members' clients?
3. The same for meeting stones (vanilla "Meeting Stone Summon").
4. Whether these unit spellcast events carry secret values in raids out of combat (Midnight restrictions).

**Live test plan:**
1. Use the current local build (`./install.sh`). Everyone with Forever Relationships types `/fr probe clear`, then `/fr probe on`.
2. Warlock + 2 clickers summon a 4th player, once in the open world, then once inside a raid group. If possible, also use a meeting stone.
3. `/fr probe off`, then `/reload` so SavedVariables are written.
4. Read `ForeverRelationshipsDB.probe` from each participant's `WTF/Account/*/SavedVariables/ForeverRelationships.lua`, or use `/fr probe show` and copy the text.

**Done when:**
- The spell ids for the ritual, the clicker action and the meeting stone are confirmed and added to `Data/Generosity.lua`, with `verified = true`.
- A clicker gets a `generosity` event of kind `summonAssist`, witnessed by any group member's client. It's deduplicated per clicker per summon, and the daily cap still applies.
- Tests:
  - fixtures from the real probe output replayed in `Tests/test_ingame_sim.lua`;
  - the clicker gets credit;
  - the warlock is not double counted;
  - nothing is recorded outside group units.
- `summonAssist` is network-eligible as a positive, with a per-witness kind like other generosity.
- CHANGELOG entry. Published after the in-game re-test.

## FR-2 · Confirm the first real certificate renewal

**Status:** watch around 2027-01-03. Certbot renews 30 days before the 2027-02-02 expiry.

`certbot renew --dry-run` fails on this VPS because the server cannot reach Let's Encrypt *staging* (connection reset). It does reach *production*, which issued the certificates on 2026-11-04. So check the real renewal instead:

```sh
ssh root@VPS 'certbot certificates | grep -A2 forever'
```

HTTP-01 for `forever.gameplaybr.com.br` goes through Cloudflare: the redirect to HTTPS is followed, and the 443 block serves `/.well-known/acme-challenge/` from Cloudflare's ranges.
