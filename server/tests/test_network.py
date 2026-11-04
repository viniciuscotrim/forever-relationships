"""Fairness rules and API behavior of the Trust Advisor network.
Run: cd server && python3 -m unittest discover -s tests -v"""
import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from trustnet import aggregate  # noqa: E402
from trustnet.app import BadRequest, Service  # noqa: E402
from trustnet.store import Store  # noqa: E402

NOW = 1800000000
T = "Player-1-000000FF"   # target
A, B, C = "Player-1-000000AA", "Player-1-000000BB", "Player-1-000000CC"


def rep(uploader, witness, guild, x=0.0, t=NOW - 3600, d="finish", k="finish:0.00:1.00", s=T):
    return {"uploader": uploader, "witness": witness, "wguild": guild, "s": s, "d": d, "x": x, "m": 1, "t": t, "k": k}


def group(*members, a=NOW - 7200, b=NOW):
    return [(a, b, frozenset(members))]


# u1 (A), u2 (B), u3 (C) all grouped with T; everyone trusted unless a test says otherwise
PRESENCE = {"u1": group(A, B, C, T), "u2": group(A, B, C, T), "u3": group(A, B, C, T)}
TRUSTED = {"u1", "u2", "u3"}


class Aggregate(unittest.TestCase):
    def one(self, reports, **kw):
        kw.setdefault("presence", PRESENCE)
        kw.setdefault("trusted", TRUSTED)
        incs = aggregate.build_incidents(reports, **kw).get(T, [])
        self.assertEqual(len(incs), 1)
        return incs[0]

    # --- presence and standing (anti-forgery) ---
    def test_untrusted_witness_does_not_count(self):
        inc = self.one([rep("u1", A, "G1"), rep("u2", B, "G2")], trusted={"u1"})
        self.assertFalse(inc["verified"])
        self.assertEqual(inc["c"], 1)

    def test_witness_without_subject_in_group_does_not_count(self):
        pres = {"u1": group(A, B, T), "u2": group(A, B)}   # u2 never grouped with T
        self.assertFalse(self.one([rep("u1", A, "G1"), rep("u2", B, "G2")], presence=pres)["verified"])

    def test_witnesses_must_list_each_other(self):
        pres = {"u1": group(A, T), "u2": group(B, T)}      # same target, but not the same group
        self.assertFalse(self.one([rep("u1", A, "G1"), rep("u2", B, "G2")], presence=pres)["verified"])

    def test_presence_must_cover_the_incident_time(self):
        old = {"u1": group(A, B, T, a=NOW - 90000, b=NOW - 86400), "u2": group(A, B, T, a=NOW - 90000, b=NOW - 86400)}
        self.assertFalse(self.one([rep("u1", A, "G1"), rep("u2", B, "G2")], presence=old)["verified"])

    def test_one_way_presence_is_not_enough(self):
        pres = {"u1": group(A, B, T), "u2": group(B, T)}   # u2 does not list A
        self.assertFalse(self.one([rep("u1", A, "G1"), rep("u2", B, "G2")], presence=pres)["verified"])

    def test_standing_rule(self):
        self.assertFalse(aggregate.standing(1.9, 10))
        self.assertFalse(aggregate.standing(10, 2))
        self.assertTrue(aggregate.standing(2, 3))

    def test_single_witness_negative_does_not_count(self):
        self.assertFalse(self.one([rep("u1", A, "G1")])["verified"])

    def test_two_witnesses_same_guild_do_not_count(self):
        self.assertFalse(self.one([rep("u1", A, "G1"), rep("u2", B, "G1")])["verified"])

    def test_two_witnesses_two_guilds_count(self):
        inc = self.one([rep("u1", A, "G1"), rep("u2", B, "G2", t=NOW - 3500)])
        self.assertTrue(inc["verified"])
        self.assertEqual((inc["w"], inc["g"]), (2, 2))

    def test_unguilded_witnesses_are_one_group(self):
        self.assertFalse(self.one([rep("u1", A, ""), rep("u2", B, ""), rep("u3", C, "")])["verified"])

    def test_same_uploader_counts_once(self):
        inc = self.one([rep("u1", A, "G1"), rep("u1", A, "G2", t=NOW - 3590)])
        self.assertEqual(inc["w"], 1)
        self.assertFalse(inc["verified"])

    def test_positive_needs_one_witness(self):
        self.assertTrue(self.one([rep("u1", A, "G1", x=1, k="finish:1.00:1.00")])["verified"])

    def test_outside_window_is_a_different_incident(self):
        incs = aggregate.build_incidents([rep("u1", A, "G1"), rep("u2", B, "G2", t=NOW - 3600 + 601)])[T]
        self.assertEqual(len(incs), 2)
        self.assertFalse(any(i["verified"] for i in incs))

    def test_self_report_ignored(self):
        self.assertEqual(aggregate.build_incidents([rep("u1", T, "G1")]), {})
        self.assertEqual(aggregate.build_incidents([rep("u1", A, "G1")], self_claims={"u1": {T}}), {})

    def test_ineligible_dimension_ignored(self):
        self.assertEqual(aggregate.build_incidents([rep("u1", A, "G1", d="pay")]), {})

    def test_open_dispute_excludes_rejected_restores(self):
        reports = [rep("u1", A, "G1"), rep("u2", B, "G2")]
        dsp = {"subject": T, "d": "finish", "k": "finish:0.00:1.00", "t": NOW - 3600, "status": "open"}
        inc = self.one(reports, disputes=[dsp])
        self.assertTrue(inc["disputed"])
        self.assertEqual(aggregate.public_view([inc]), [])
        dsp["status"] = "rejected"
        self.assertEqual(len(aggregate.public_view([self.one(reports, disputes=[dsp])])), 1)

    def test_opted_out_player_has_no_incidents(self):
        self.assertEqual(aggregate.build_incidents([rep("u1", A, "G1", x=1)], opted_out={T}), {})


class Api(unittest.TestCase):
    def setUp(self):
        self.clock = [NOW]
        self.svc = Service(Store(":memory:"), admin_token="adm", clock=lambda: self.clock[0])

    def session(self, *members, a=NOW - 7200, b=NOW):
        return {"a": a, "b": b, "m": list(members)}

    def upload(self, uid, witness, guild, reports, presence=None, **extra):
        if presence is None:
            presence = [self.session(A, B, C, T)]
        body = {"uploaderId": uid, "protocol": 1, "witness": witness, "witnessGuild": guild,
                "characters": [{"guid": witness, "name": "x", "guild": guild}], "reports": reports,
                "presence": presence}
        body.update(extra)
        return self.svc.upload(body)

    def r(self, x=0.0, t=NOW - 3600):
        return {"s": T, "n": "Target", "d": "finish", "x": x, "m": 1, "t": t, "k": "finish:%.2f:1.00" % x}

    def build_standing(self, uids_witnesses):
        """Give uploaders a corroborated history: 3 past group runs they all reported,
        then let 3 days pass."""
        for i in range(3):
            t = NOW - 86400 * 10 + i * 3600
            other = "Player-1-0000%04X" % (100 + i)
            for uid, (w, g) in uids_witnesses.items():
                self.upload(uid, w, g, [{"s": other, "d": "finish", "x": 1, "m": 1, "t": t, "k": "finish:1.00:1.00"}],
                            presence=[self.session(A, B, C, T, other, a=t - 1800, b=t + 1800)])
        self.clock[0] = NOW + 3 * 86400

    def test_new_accounts_cannot_verify_negatives(self):
        self.upload("a" * 32, A, "G1", [self.r()])
        self.upload("b" * 32, B, "G2", [self.r(t=NOW - 3550)])
        self.assertEqual(self.svc.players([T])["players"], {})       # no standing yet

    def test_end_to_end_verification_and_dispute(self):
        self.build_standing({"a" * 32: (A, "G1"), "b" * 32: (B, "G2")})
        self.upload("a" * 32, A, "G1", [self.r()])
        self.assertEqual(self.svc.players([T])["players"], {})        # one witness: hidden
        self.upload("b" * 32, B, "G2", [self.r(t=NOW - 3550)])
        view = self.svc.players([T])["players"][T]["incidents"]
        self.assertEqual(len(view), 1)
        self.assertNotIn("uploader", str(view))                       # no witness identities
        # the target sees it about themselves and disputes it
        self.upload("c" * 32, T, "G3", [])
        mine = self.svc.self_events({"uploaderId": "c" * 32})["events"]
        self.assertEqual(len(mine), 1)
        self.upload("c" * 32, T, "G3", [], disputes=[{"id": mine[0]["id"], "reason": "I was kicked"}])
        self.assertEqual(self.svc.players([T])["players"], {})        # excluded while open
        self.svc.store.review_dispute(mine[0]["id"], "rejected")
        self.assertEqual(len(self.svc.players([T])["players"][T]["incidents"]), 1)

    def test_forged_reports_without_shared_history_fail(self):
        # two trusted accounts each claim to have seen T leave, but their group histories never overlap
        self.build_standing({"a" * 32: (A, "G1"), "b" * 32: (B, "G2")})
        self.upload("a" * 32, A, "G1", [self.r()], presence=[self.session(A, T)])
        self.upload("b" * 32, B, "G2", [self.r()], presence=[self.session(B, T, a=NOW - 100000, b=NOW - 90000)])
        # their earlier shared sessions do not cover the incident time either
        self.assertEqual(self.svc.players([T])["players"], {})

    def test_presence_validation(self):
        with self.assertRaises(BadRequest):
            self.upload("a" * 32, A, "G1", [], presence=[{"a": NOW, "b": NOW - 10, "m": [A]}])
        with self.assertRaises(BadRequest):
            self.upload("a" * 32, A, "G1", [], presence=[{"a": NOW - 10, "b": NOW, "m": ["nope"]}])

    def test_cannot_dispute_someone_else(self):
        self.upload("a" * 32, A, "G1", [self.r()])
        self.upload("b" * 32, B, "G2", [self.r()])
        inc_id = aggregate.build_incidents(self.svc.store.reports_about([T]))[T][0]["id"]
        res = self.upload("d" * 32, C, "G4", [], disputes=[{"id": inc_id, "reason": "nope"}])
        self.assertEqual(res["disputes"], 0)

    def test_deletion_hides_player_and_removes_reports(self):
        self.upload("a" * 32, A, "G1", [dict(self.r(x=1), k="finish:1.00:1.00")])
        self.upload("c" * 32, T, "G3", [])
        self.assertIn(T, self.svc.players([T])["players"])
        res = self.svc.upload({"uploaderId": "c" * 32, "protocol": 1, "deleteRequested": True})
        self.assertEqual(res["hidden"], [T])
        self.assertEqual(self.svc.players([T])["players"], {})

    def test_contested_guid_cannot_be_hidden_or_viewed(self):
        self.upload("a" * 32, A, "G1", [dict(self.r(x=1), k="finish:1.00:1.00")])
        self.upload("c" * 32, T, "G3", [])
        self.upload("e" * 32, T, "G9", [])   # an impostor claims the same character
        self.assertEqual(self.svc.self_events({"uploaderId": "e" * 32})["events"], [])
        self.svc.upload({"uploaderId": "e" * 32, "protocol": 1, "deleteRequested": True})
        self.assertIn(T, self.svc.players([T])["players"])

    def test_validation(self):
        with self.assertRaises(BadRequest):
            self.upload("a" * 32, A, "G1", [dict(self.r(), d="pay")])
        with self.assertRaises(BadRequest):
            self.upload("a" * 32, A, "G1", [dict(self.r(), x=2)])
        with self.assertRaises(BadRequest):
            self.svc.upload({"uploaderId": "short", "protocol": 1})


if __name__ == "__main__":
    unittest.main()
