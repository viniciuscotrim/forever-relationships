# Trust Advisor companion app

**Optional.** Trust Advisor works fully without it. It is only needed for the Trust Advisor Network.

WoW addons cannot use the internet, so this small program does it for them:

1. Reads `WTF/Account/*/SavedVariables/TrustAdvisor.lua` (written on logout or `/reload`).
2. If you joined the network in game, it uploads your witness reports, group history, disputes and deletion requests.
3. Downloads the network view for the players you know into `Interface/AddOns/TrustAdvisor/Network/NetData.lua`. Type `/reload` in game to see it.

## Install
Download from **[Releases](https://github.com/viniciuscotrim/trust-advisor/releases)**:
- Windows: `.exe`
- Mac: `TrustAdvisorCompanion-macos.zip`, universal, signed and notarized by Apple, so it opens without warnings
- any OS: `ta_companion.py` (needs Python 3.8+)

Then run it once with `--install`:

```sh
TrustAdvisorCompanion-windows.exe --install       # Windows: starts with Windows (Startup folder, no admin)
./TrustAdvisorCompanion-macos --install           # Mac: LaunchAgent, restarts if it stops
python3 ta_companion.py --install                 # any OS with Python
```

Then link your Battle.net account once (it opens your browser). This is needed for your negative reports to count as a witness:

```sh
TrustAdvisorCompanion-windows.exe --link --region us    # or eu / kr / tw
```

Other options:
- `--wow "<path to _forever_>"` if WoW isn't in the default folder.
- `--once` for a single sync.
- `--uninstall` to stop the automatic start.
- `--server URL` for a self-hosted server.

In game, `/ta network` shows whether the companion is syncing.

Nothing is sent unless `consent.network` is ON in the addon. Notes, affinity and chat are never read.

Tests: `python3 -m unittest discover -s tests -v` (the end-to-end test needs `luajit`). Releases: push a `companion-v*` tag. CI tests both platforms and publishes the Windows build. Then run `companion/release-mac.sh` on a Mac to attach the signed and notarized macOS build.
