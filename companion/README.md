# Trust Advisor companion app

WoW addons cannot use the internet. This small program (Python 3.8+, no dependencies) connects Trust Advisor to the network:

1. Reads `WTF/Account/*/SavedVariables/TrustAdvisor.lua` (written on logout or `/reload`).
2. If you joined the network in game (Transparency › Network), it uploads your witness reports, disputes and deletion requests.
3. Downloads the network view for players you know into `Interface/AddOns/TrustAdvisor/Network/NetData.lua`. Type `/reload` in game to see it.

```sh
python3 ta_companion.py --server https://YOUR-SERVER          # keeps watching
python3 ta_companion.py --server https://YOUR-SERVER --once   # one sync
python3 ta_companion.py --wow "D:\Games\World of Warcraft\_forever_" --server ...
```

Nothing is sent unless `consent.network` is ON in the addon. Notes, affinity and chat are never read.

Tests: `python3 -m unittest discover -s tests -v` (the end-to-end test needs `luajit`).
