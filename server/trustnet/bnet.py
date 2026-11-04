"""Battle.net OAuth (authorization code flow) for witness identity.

The client secret lives only on the server. We request `openid wow.profile`,
keep only a salted hash of the Battle.net account id, and the GUIDs of the
player's WoW: Forever characters (namespace profile-forever-<region>).
The access token is used once and discarded.
"""
import base64
import json
import urllib.error
import urllib.parse
import urllib.request

AUTHORIZE_URL = "https://oauth.battle.net/authorize"
TOKEN_URL = "https://oauth.battle.net/token"
USERINFO_URL = "https://oauth.battle.net/userinfo"
REGIONS = {"us", "eu", "kr", "tw"}
SCOPE = "openid wow.profile"


def forever_guid(realm_id, character_id):
    """WoW GUID for a character: Player-<realmId>-<characterId as 8 hex digits>."""
    return "Player-%d-%08X" % (int(realm_id), int(character_id))


class BattleNet:
    def __init__(self, client_id, client_secret, timeout=15):
        self.client_id = client_id
        self.client_secret = client_secret
        self.timeout = timeout

    def authorize_url(self, redirect_uri, state):
        q = urllib.parse.urlencode({"client_id": self.client_id, "redirect_uri": redirect_uri,
                                    "response_type": "code", "scope": SCOPE, "state": state})
        return AUTHORIZE_URL + "?" + q

    def _json(self, req):
        try:
            with urllib.request.urlopen(req, timeout=self.timeout) as r:
                return json.loads(r.read().decode("utf-8"))
        except urllib.error.HTTPError as e:
            raise RuntimeError("Battle.net HTTP %d" % e.code)

    def exchange(self, code, redirect_uri):
        data = urllib.parse.urlencode({"grant_type": "authorization_code", "code": code,
                                       "redirect_uri": redirect_uri}).encode("ascii")
        basic = base64.b64encode(("%s:%s" % (self.client_id, self.client_secret)).encode("utf-8")).decode("ascii")
        req = urllib.request.Request(TOKEN_URL, data=data, method="POST",
                                     headers={"Authorization": "Basic " + basic,
                                              "Content-Type": "application/x-www-form-urlencoded"})
        return self._json(req)["access_token"]

    def account_id(self, token):
        req = urllib.request.Request(USERINFO_URL, headers={"Authorization": "Bearer " + token})
        return str(self._json(req)["sub"])

    def forever_characters(self, token, region):
        """GUIDs of the account's Forever characters. [] if none or not available yet."""
        url = "https://%s.api.blizzard.com/profile/user/wow?namespace=profile-forever-%s&locale=en_US" % (region, region)
        req = urllib.request.Request(url, headers={"Authorization": "Bearer " + token})
        try:
            d = self._json(req)
        except RuntimeError:
            return []
        out = []
        for acct in d.get("wow_accounts", []):
            for ch in acct.get("characters", []):
                realm = (ch.get("realm") or {}).get("id")
                if realm is not None and ch.get("id") is not None:
                    out.append(forever_guid(realm, ch["id"]))
        return out
