# Forever Relationships — GDD v2: augmented reality of your relationships

Nov 4, 2026 · supersedes the v1 reputation design (scores and witness verification).

## 1. Vision

Forever Relationships is an **augmented reality of how you relate to the people around you** in WoW: Forever. It answers a question every player asks and forgets: *"where do I know this person from, and how was it playing with them?"*

It does this using **only data the game itself produces** while you play together: time, kills, completed content, trades, help, quests. Three rules follow from that:
- **It never infers who someone is.** There are no scores, no bands, and no "Concern".
- **It never records opinions.** There are no notes, no ratings, and no "play again?" prompt.
- **It never reads conversations.**

### Information, Knowledge, Wisdom
| Layer | What it is | In Forever Relationships |
|---|---|---|
| Information | Facts the game records | Yes |
| Knowledge | Patterns about *your* relationship, computed for you | Yes |
| Wisdom | Inferences about *what kind of player* someone is | **No** (removed in v2) |

## 2. Data layers (each one chosen by the player)

| Layer | What | Who sees it | Mined |
|---|---|---|---|
| **0 · Local** (everyone) | Your relationship with each player: the tooltip (6 items you choose) and the **Relationship** window | You only | No |
| **1 · Cloud backup** (opt-in) | A copy of your history, **end-to-end encrypted**. The key stays on your computer, plus a recovery code you keep. You keep your history after reinstalling or changing computers. | You only. The server cannot read it. | **No** |
| **2 · Public profile** (opt-in, item by item) | What *you* choose to show about *yourself*: hours in groups, dungeons, people helped, achievements… Each item is marked **Official** (Blizzard API, character verified through Battle.net) or **Recorded by the addon** | Other Forever Relationships players | Yes |
| **3 · Community** (opt-in) | Anonymous contribution of your group sessions to statistics, plus a separate choice: **"recommend me to other players"** | Nobody individually. Aggregates appear in the admin cockpit. | Yes, pseudonymized |

**For everyone, always:**
- **Permanent exclusion list.** Anyone can ask to be removed, through `/fr` or the self-service page with Battle.net login. Their data is deleted, and data that arrives about them later is **discarded at ingest**.
- **Pseudonymization.** Every character identifier on the server is stored as a keyed HMAC, with the key kept outside the database.
- **Recommendations only involve players who opted in** to being recommended.

## 3. What is recorded (Information)
- **Group sessions:** start, end, zone or instance, type, and each member's join and leave times.
- **Encounters:** boss kills and wipes. **Completion:** present at the last boss.
- **Loot** received in the group.
- **Trades:** gold, items, enchants, crafted items.
- **Ready checks:** response and consumables.
- **Help:** buffs, resurrections, summons, free portals. **Hardcore deaths.**
- **Quest completions:** your own turn-ins, plus partners' through Questie or peer messages.
- **Visible identity:** name, class, race, faction, level, guild, and guild changes.
- **Social actions in the game:** grouping again on another day, friend status.

*Removed from v1:* scores and bands, early-leave and loot-and-leave verdicts, endorsements, private yes/no, personal notes, debt ledger, soft-reserve honesty, raid signups, and chat message counts.

## 4. What is computed for you (Knowledge)
Per player you've grouped with:
- time together, sessions, distinct days, first and last time together (and where);
- dungeons and raids completed together, kills and wipes together;
- trades (count, gold each way, crafts and enchants);
- help given and received, quests completed together, ready checks together, Hardcore deaths in your group;
- usual hours together, typical level difference, zones in common, guild history, friend status;
- their rank in your circle.

## 5. Interface
- **Tooltip:** up to **6 items you choose**. Defaults: time together, last together, days together, completed together, kills together, trades.
- **Right-click a player → "Relationship":** every item, grouped by Information and Knowledge, plus their **public profile** if they publish one.
- **Main window:**
  - **Circle:** everyone you've played with, sorted by time together, plus suggestions;
  - **Relationship**;
  - **My profile:** your own numbers and the public-profile checklist;
  - **Event log**;
  - **Privacy:** layers and consents, what is recorded and where, backup status, delete everything.
- **Welcome:** the four layers, with plain-language consent for each. Everything starts off.
- **Feedback:** `/fr feedback` remains the single channel.

## 6. Companion app
- Syncs the public profile, the community contribution and the recommendations.
- Delivers feedback.
- Runs the **end-to-end encrypted backup**: AES-256-GCM with a key in the OS keychain, plus a recovery code. `--restore <code>` restores the history on a new computer.
- Battle.net link (`--link`): verifies character ownership, which is needed for **Official** profile items.

## 7. Server
- **Sync API:** consents, own character, profile, community sessions, lookups of public profiles, recommendations.
- **Backup storage:** opaque encrypted blobs, addressed by an id derived from the key, with a write token.
- **Official data:** the Blizzard profile API (`profile-forever-<region>`) for verified characters.
- **Admin cockpit:** passkey + TOTP. Aggregates only, no identifiers, minimum group size 10.
- **Public pages:** `/privacy` (policy) and `/me` (self-service with Battle.net: see, download, delete and opt out).

## 8. Legal basis (summary)
| Layer | Legal basis |
|---|---|
| Local | Personal use by the player |
| Backup, profile, community | Consent, per layer, revocable at any time |
| Exclusion list | Legal obligation / legitimate interest; only a keyed hash is kept |

**Retention:**
- backups: latest version, deleted 180 days after the last sync;
- community sessions: 400 days;
- feedback: 2 years.

Recommended: a review by a data-protection lawyer once there are real users.
