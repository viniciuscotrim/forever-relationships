**Optional.** Trust Advisor works fully without this app. You only need it to join the Trust Advisor Network.

WoW addons cannot use the internet. This small app syncs Trust Advisor's network data for you. It only reads Trust Advisor's own saved data, and it only sends anything if you turned on **Join the Trust Advisor Network** in game.

### Install
- **Windows:** download `TrustAdvisorCompanion-windows.exe`, put it somewhere permanent (e.g. `Documents\TrustAdvisor`), then open a terminal there and run
  `TrustAdvisorCompanion-windows.exe --install`
  From then on it starts with Windows. Windows SmartScreen may warn about an unsigned app: choose *More info › Run anyway*.
- **Mac (Apple Silicon and Intel, signed and notarized by Apple):** download `TrustAdvisorCompanion-macos-app.zip`, double-click it, drag **Trust Advisor Companion** into Applications and open it. It sets itself up to run in the background and offers to link Battle.net. No Terminal needed. If you prefer the command line: `TrustAdvisorCompanion-macos.zip`.
- **Any OS with Python 3.8+:** `python3 ta_companion.py --install`

On Windows or with the command line, link Battle.net once (opens your browser): `--link --region us` (or `eu`, `kr`, `tw`). On Mac, the app offers it when you open it. Only a one-way hash of your account id is stored.

If your game is not in the default folder, add `--wow "<path to _forever_>"`. Remove the autostart with `--uninstall`.

In game: `/reload`, then check `/ta network`.
