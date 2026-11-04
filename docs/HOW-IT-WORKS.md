# How Trust Advisor works

## Raw facts in, scores out
The addon only **records raw facts** while you play: who was in the group and when, boss kills, loot, trades, ready checks, and leave messages. Every rule that turns facts into scores runs **at scoring time**, from the parameters in Transparency. Change a parameter and all history is rescored instantly; **Why?** shows the exact events and math.

## Scoring (per trait)
- **Decay:** each event's weight halves every *half-life* days. Negatives fade faster than positives.
- **Ratio traits** (can go up or down): a Bayesian average that starts at a neutral prior (0.75, "assume decent") worth 3 events.
- **Accumulating traits** (positive only): grow toward 1 with a soft cap, and can never show Concern.
- **Bands:**
  - *Unknown* below 3 units of evidence;
  - otherwise *Concern*, *Building*, *Solid* or *Exemplary*.
  - All thresholds are parameters.
- **No composite score,** ever.

## Known limits
- **Early leaves need proof.** With `finish.requireLeaveMessage` on (the default), an early leave counts only when the game printed a voluntary-leave message. A leader's kick by someone else can't be told apart from a leave, so unconfirmed leaves are shown but not scored.
- **Carry detection is heuristic.** A gold trade inside an instance before the final boss counts as a carry. Turn it off with `carry.autoDetect`.
- **Debts are entered by hand** (`/ta owe`, `/ta ledger`). Only the trades you take part in are witnessed, and debts never go to the Network.
- **Portals** count as generosity only when you zone right after a group member's portal and paid them nothing. **Crafted gifts** are detected from the item's "Made by" line.
- **Interface is English only.**

## The Network
See [NETWORK.md](NETWORK.md) for:
- the architecture;
- exactly what is uploaded;
- the fairness rules (witnesses, guilds, presence, Battle.net identity, disputes, deletion);
- the risks that remain.
