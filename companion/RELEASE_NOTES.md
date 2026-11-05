**Optional.** Forever Relationships works fully without this app. It's needed for the cloud layers (encrypted backup, public profile, community, recommend me) and to deliver the feedback you write in game with `/fr feedback` (and bring the developer's replies back). It only sends what the layers you turned on in game allow.

**Version 0.5.0:** brings the **realm population** to the addon's Population tab (`/fr population`, addon 0.5.0), refreshed every hour, even with every layer off. Syncs right after each `/reload` or logout and again every hour. The Mac app includes encryption, so the cloud backup works on Mac. Keeps starting with your computer even if you first opened it from Downloads.

### Install
- **Mac (Apple Silicon and Intel, signed and notarized by Apple):** download `ForeverRelationshipsCompanion-macos-app.zip`, double-click it, drag **Forever Relationships Companion** into Applications and open it. It sets itself up to run in the background, shows your backup **recovery code** (save it in Passwords) and offers to link Battle.net. No Terminal needed.
- **Windows:** download `ForeverRelationshipsCompanion-windows.exe`, put it somewhere permanent (e.g. `Documents\ForeverRelationships`), then open a terminal there and run
  `ForeverRelationshipsCompanion-windows.exe --install`
  From then on it starts with Windows. SmartScreen may warn about an unsigned app: choose *More info › Run anyway*.
- **Any OS with Python 3.8+:** `pip install cryptography`, then `python3 fr_companion.py --install`

Restore your history on a new computer: `--restore <recovery code>`. Show the code again: `--show-recovery-code`. Link Battle.net (Windows/Python): `--link --region us` (or `eu`, `kr`, `tw`). Remove the autostart with `--uninstall`.

In game: `/reload`, then check `/fr cloud`.
