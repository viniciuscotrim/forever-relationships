# Server protocol (v2)

The addon can't reach the internet. The companion app reads the addon's SavedVariables, talks to the server and writes `Cloud/NetData.lua` back. Full design and legal basis: `GDD-v2.md`. Public policy: https://forever.gameplaybr.com.br/privacy.

## What is sent, per layer (all off by default)

| Layer | Sent | Stored as | Kept |
|---|---|---|---|
| Cloud backup | the addon's SavedVariables, AES-256-GCM encrypted on the computer | opaque blob, id and write token derived from the user's key | 180 days after the last sync |
| Public profile | the items the player ticked about their own character | per pseudonymized character; Battle.net-verified values marked Official | until turned off |
| Community | group sessions (times, place, type, kills) with members' class, race, faction, level; no names | every character id replaced by an HMAC pseudonym on arrival; excluded players dropped at ingest | 400 days |
| Community: population census | characters seen in game (mouseover, target, nameplates, group): faction, race, class, level, realm id from the GUID; no names | HMAC pseudonym on arrival, one row per character (latest sighting); excluded players dropped; deleted when Community is turned off | 90 days after last seen |
| Recommend me | own name, class, level, realm | shown only to other opted-in players | until turned off |
| Feedback | what the player wrote, optional diagnostics | as is | 2 years |

Turning every layer off makes the server forget the install. "Delete my cloud data" (in game) or https://forever.gameplaybr.com.br/me (Battle.net login, no addon needed) deletes everything and adds the character to the permanent exclusion list. Only a Battle.net-verified owner can lift an exclusion.

## Endpoints

- `POST /v1/sync`: consents, own character, profile, community sessions, census, realm names, profile lookups → profiles, suggestions, feedback replies, link status.
- `GET /v1/population`: public aggregate for the Population tab: characters seen in the last 30 days per realm type (`pvp`/`pve`, set by the admin in the cockpit's Realms view), faction and race, plus `updatedAt`. The companion fetches it on every sync (at least hourly), even with every layer off.
- `PUT|GET|DELETE /v1/backup/<id>`: encrypted backup (write token required to change it).
- `POST /v1/feedback`, `GET /v1/protocol`, `GET /healthz`.
- `/v1/auth/begin|status|callback`: Battle.net OAuth (link an install, or log in to `/me`).
- `/me`, `/privacy`: public pages. `/admindash`: cockpit (passkey + TOTP), aggregates only, minimum group size 10.

Limits: 120 requests/minute per IP; 2,000 profile lookups per request and 5,000 per day per install.
