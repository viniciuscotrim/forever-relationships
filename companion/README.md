# Forever Relationships companion app

**Optional.** The addon works fully without it. The companion is needed for the cloud layers (backup, public profile, community, recommend me) and to deliver the feedback you write in game with `/fr feedback`, along with the developer's replies.

WoW addons cannot use the internet, so this small program does it for them:

1. Reads the addon's SavedVariables (`ForeverRelationships.lua`, written on logout or `/reload`).
2. Sends only what the layers you turned on allow: the encrypted backup, your chosen profile items, pseudonymized community sessions, feedback and deletion requests.
3. Writes public profiles, suggestions and status into `Interface/AddOns/ForeverRelationships/Cloud/NetData.lua`. Type `/reload` in game to see them.

**Cloud backup** is encrypted on your computer with AES-256-GCM before upload. The key stays on your computer (macOS Keychain, or a private file), and you get a **recovery code** once: save it in your Passwords app. Nobody else, including the developer, can read the backup. Without the code, it can't be restored.

## Install
Download from **[Releases](https://github.com/viniciuscotrim/forever-relationships/releases)**:
- Mac: `ForeverRelationshipsCompanion-macos-app.zip`. Open **Forever Relationships Companion.app**: it installs the background service, shows your recovery code and offers the Battle.net link, no Terminal needed. Universal, signed, notarized and stapled by Apple.
- Windows: `ForeverRelationshipsCompanion-windows.exe`. It isn't code-signed yet, so SmartScreen may warn: choose *More info › Run anyway*. Put it somewhere permanent, then run it once with `--install`.
- Any OS: `fr_companion.py` (needs Python 3.8+ and the `cryptography` package for the backup).

```sh
ForeverRelationshipsCompanion-windows.exe --install        # starts with Windows (Startup folder, no admin)
ForeverRelationshipsCompanion-windows.exe --link --region us   # link Battle.net once (us / eu / kr / tw)
```

Other options:
- `--show-recovery-code`: show your backup recovery code again.
- `--restore CODE`: restore your history from the cloud backup (new computer, reinstall).
- `--wow "<path to _forever_>"` if WoW isn't in the default folder.
- `--once` for a single sync, `--uninstall` to stop the automatic start, `--server URL` for a self-hosted server.

In game, `/fr cloud` shows whether the companion is syncing.

Tests: `python3 -m unittest discover -s tests -v` (the end-to-end test needs `luajit`). Releases: push a `companion-v*` tag. CI tests both platforms and publishes the Windows build. Then run `companion/release-mac.sh` on a Mac to attach the signed, notarized and stapled macOS app.
