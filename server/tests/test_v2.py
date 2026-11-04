"""Protocol v2: consent-gated layers, pseudonymization, exclusion list, profiles,
recommendations, backups, Battle.net self-service. Run: python -m unittest discover -s tests"""
import json
import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from trustnet.app import BadRequest, Service  # noqa: E402
from trustnet.store import Store  # noqa: E402

NOW = 1800000000
ME, A, B, C = "Player-1-000000E0", "Player-1-000000A0", "Player-1-000000B0", "Player-1-000000C0"


class FakeBnet:
    def __init__(self):
        self.chars, self.official = {}, {}

    def authorize_url(self, redirect, state):
        return "https://oauth.battle.net/authorize?state=" + state

    def exchange(self, code, redirect):
        return "tok-" + code

    def account_id(self, token):
        return token[4:]

    def forever_characters(self, token, region):
        return self.chars.get(token[4:], [])

    def official_profile(self, region, realm_slug, name, now):
        return self.official.get(name)


def session(a=NOW - 7200, members=(ME, A, B), gtype="dungeon", place="Deadmines"):
    return {"a": a, "b": a + 3600, "type": gtype, "place": place, "kills": 4,
            "m": [{"g": g, "class": "Warrior", "race": "Orc", "faction": "Horde", "level": 30} for g in members]}


class V2(unittest.TestCase):
    def setUp(self):
        self.store = Store(":memory:")
        self.bnet = FakeBnet()
        self.svc = Service(self.store, clock=lambda: NOW, bnet=self.bnet, public_urls=["https://forever.example"], hash_salt="k3y")

    def raw_dump(self):
        return "\n".join(str(tuple(r)) for t in ("participants", "profiles", "community_members", "optout", "owned")
                         for r in self.store.q("SELECT * FROM %s" % t))

    def test_nothing_without_consent(self):
        self.svc.sync({"uploaderId": "a" * 32, "protocol": 2, "consents": {}, "me": {"guid": ME, "name": "Me"},
                       "community": [session()], "profile": {"hours": 10}})
        self.assertEqual(self.store.q("SELECT count(*) FROM participants", one=True)[0], 0)
        self.assertEqual(self.store.q("SELECT count(*) FROM community_sessions", one=True)[0], 0)
        self.assertEqual(self.store.q("SELECT count(*) FROM profiles", one=True)[0], 0)

    def test_raw_guids_never_stored(self):
        body = {"uploaderId": "a" * 32, "protocol": 2, "consents": {"profile": True, "community": True},
                "me": {"guid": ME, "name": "Me"}, "profile": {"hours": 10}, "community": [session()]}
        self.svc.sync(body)
        dump = self.raw_dump()
        for g in (ME, A, B):
            self.assertNotIn(g, dump)
        self.assertEqual(self.store.q("SELECT count(*) FROM community_members", one=True)[0], 3)

    def test_community_has_no_names_and_needs_two_members(self):
        body = {"uploaderId": "a" * 32, "protocol": 2, "consents": {"community": True}, "me": {"guid": ME},
                "community": [session(), session(a=NOW - 9000, members=(ME,))]}
        self.assertEqual(self.svc.sync(body)["storedSessions"], 1)
        cols = {r[1] for r in self.store.q("PRAGMA table_info(community_members)")}
        self.assertNotIn("name", cols)

    def test_opt_out_discarded_at_ingest_and_only_owner_can_lift(self):
        self.store.forget_character(self.svc.pseudo(A), NOW)
        body = {"uploaderId": "a" * 32, "protocol": 2, "consents": {"community": True}, "me": {"guid": ME}, "community": [session()]}
        self.svc.sync(body)
        self.assertNotIn(self.svc.pseudo(A), {r[0] for r in self.store.q("SELECT member_h FROM community_members")})
        # an impostor claiming A cannot bring A back
        imp = self.svc.sync({"uploaderId": "b" * 32, "protocol": 2, "consents": {"profile": True}, "me": {"guid": A}, "profile": {"hours": 1}})
        self.assertTrue(imp["optedOut"])
        self.assertTrue(self.store.optedout(self.svc.pseudo(A)))
        # the Battle.net-verified owner can
        self.bnet.chars["acctA"] = [{"guid": A, "name": "Aa", "realm_slug": "br-1"}]
        url = self.svc.auth_begin({"uploaderId": "c" * 32, "region": "us"}, "forever.example")["url"]
        self.svc.auth_callback({"state": url.rsplit("state=", 1)[1], "code": "acctA"})
        own = self.svc.sync({"uploaderId": "c" * 32, "protocol": 2, "consents": {"profile": True}, "me": {"guid": A}, "profile": {"hours": 1}})
        self.assertFalse(own["optedOut"])

    def test_profiles_lookup_and_official_only_for_verified(self):
        self.bnet.official["Bee"] = {"level": 42, "achievementPoints": 900}
        self.bnet.chars["acctB"] = [{"guid": B, "name": "Bee", "realm_slug": "br-1"}]
        url = self.svc.auth_begin({"uploaderId": "b" * 32, "region": "us"}, None)["url"]
        self.svc.auth_callback({"state": url.rsplit("state=", 1)[1], "code": "acctB"})
        self.svc.sync({"uploaderId": "b" * 32, "protocol": 2, "consents": {"profile": True}, "me": {"guid": B, "name": "Bee"},
                       "profile": {"hours": 77, "dungeons": 5, "evil": "x"}})
        # a self-declared (unverified) claim of A gets no official items
        self.svc.sync({"uploaderId": "d" * 32, "protocol": 2, "consents": {"profile": True}, "me": {"guid": A}, "profile": {"hours": 3}})
        out = self.svc.sync({"uploaderId": "a" * 32, "protocol": 2, "consents": {"profile": True}, "me": {"guid": ME}, "lookups": [A, B, C]})
        prof_b = {i["key"]: i for i in out["profiles"][B]["items"]}
        self.assertEqual(prof_b["hours"]["value"], 77)
        self.assertNotIn("evil", prof_b)
        self.assertTrue(prof_b["level"]["official"] and prof_b["level"]["value"] == 42)
        self.assertFalse(any(i["official"] for i in out["profiles"][A]["items"]))
        self.assertNotIn(C, out["profiles"])

    def test_profile_disappears_when_turned_off(self):
        self.svc.sync({"uploaderId": "b" * 32, "protocol": 2, "consents": {"profile": True}, "me": {"guid": B}, "profile": {"hours": 1}})
        self.svc.sync({"uploaderId": "b" * 32, "protocol": 2, "consents": {"community": True}, "me": {"guid": B}})
        out = self.svc.sync({"uploaderId": "a" * 32, "protocol": 2, "consents": {"profile": True}, "me": {"guid": ME}, "lookups": [B]})
        self.assertEqual(out["profiles"], {})

    def test_recommendations_only_opted_in_players(self):
        # me shares community with A and B; C (opted in to recommend) played with A and B too
        self.svc.sync({"uploaderId": "a" * 32, "protocol": 2, "consents": {"community": True}, "me": {"guid": ME, "realm": "BR-1"},
                       "community": [session()]})
        self.svc.sync({"uploaderId": "c" * 32, "protocol": 2, "consents": {"community": True, "recommend": True},
                       "me": {"guid": C, "name": "Cee", "realm": "BR-1", "faction": "Horde", "level": 31},
                       "community": [session(a=NOW - 5000, members=(C, A, B))]})
        self.svc.sync({"uploaderId": "d" * 32, "protocol": 2, "consents": {"community": True},   # not recommendable
                       "me": {"guid": "Player-1-000000D0", "name": "Dee", "realm": "BR-1"}, "community": [session(a=NOW - 6000, members=("Player-1-000000D0", A))]})
        sug = self.svc.sync({"uploaderId": "a" * 32, "protocol": 2, "consents": {"community": True}, "me": {"guid": ME, "realm": "BR-1"}})["suggestions"]
        self.assertEqual([s["name"] for s in sug], ["Cee"])
        self.assertIn("2 people you know", sug[0]["reason"])

    def test_turning_everything_off_forgets_the_uploader(self):
        self.svc.sync({"uploaderId": "a" * 32, "protocol": 2, "consents": {"community": True, "profile": True}, "me": {"guid": ME},
                       "profile": {"hours": 1}, "community": [session()]})
        self.svc.sync({"uploaderId": "a" * 32, "protocol": 2, "consents": {}, "me": {"guid": ME}})
        for t in ("participants", "profiles", "community_sessions", "community_members"):
            self.assertEqual(self.store.q("SELECT count(*) FROM %s" % t, one=True)[0], 0, t)

    def test_delete_request_excludes(self):
        self.svc.sync({"uploaderId": "a" * 32, "protocol": 2, "consents": {"community": True}, "me": {"guid": ME}, "community": [session()]})
        self.assertTrue(self.svc.sync({"uploaderId": "a" * 32, "protocol": 2, "me": {"guid": ME}, "deleteRequested": True})["deleted"])
        self.assertTrue(self.store.optedout(self.svc.pseudo(ME)))
        self.assertEqual(self.store.q("SELECT count(*) FROM community_sessions", one=True)[0], 0)

    def test_backup_token_protects_overwrite_and_delete(self):
        bid = "f" * 64
        self.svc.backup_put(bid, "t" * 40, b"ciphertext-1")
        self.assertEqual(self.svc.backup_get(bid)[0], b"ciphertext-1")
        with self.assertRaises(PermissionError):
            self.svc.backup_put(bid, "x" * 40, b"evil")
        self.assertFalse(self.svc.backup_delete(bid, "x" * 40)["deleted"])
        self.assertTrue(self.svc.backup_delete(bid, "t" * 40)["deleted"])
        self.assertIsNone(self.svc.backup_get(bid)[0])
        with self.assertRaises(BadRequest):
            self.svc.backup_put("../etc", "t" * 40, b"x")

    def test_me_self_service_without_addon(self):
        self.bnet.chars["acctZ"] = [{"guid": A, "name": "Aa", "realm_slug": "br-1"}]
        self.svc.sync({"uploaderId": "a" * 32, "protocol": 2, "consents": {"community": True}, "me": {"guid": ME}, "community": [session()]})
        url = self.svc.me_login("eu")
        code, title, _, token = self.svc.auth_callback({"state": url.rsplit("state=", 1)[1], "code": "acctZ"})
        self.assertEqual((code, title), (200, "Signed in"))
        data = self.svc.me_data(token)
        self.assertEqual(data["characters"][0]["seenInCommunitySessions"], 1)
        out = self.svc.me_delete(token)
        self.assertEqual(out["excludedCharacters"], 1)
        self.assertTrue(self.store.optedout(self.svc.pseudo(A)))
        self.assertNotIn(self.svc.pseudo(A), {r[0] for r in self.store.q("SELECT member_h FROM community_members")})
        with self.assertRaises(PermissionError):
            self.svc.me_data(token)                      # session ended with the account data

    def test_feedback_roundtrip(self):
        res = self.svc.feedback({"installId": "f" * 32, "items": [{"id": "ffffffff-1-ab", "kind": "bug", "text": "x"}]})
        self.assertEqual(res["statuses"], {"ffffffff-1-ab": {"status": "received"}})

    def test_protocol_version_enforced(self):
        with self.assertRaises(BadRequest):
            self.svc.sync({"uploaderId": "a" * 32, "protocol": 1})


if __name__ == "__main__":
    unittest.main()
