"""Companion tests, including a cross-language end-to-end run:
addon (LuaJIT mock client) -> SavedVariables -> companion -> live server -> NetData.lua -> addon.
Run: cd companion && python3 -m unittest discover -s tests -v   (needs luajit for the e2e test)"""
import os
import shutil
import subprocess
import sys
import tempfile
import threading
import unittest
from http.server import ThreadingHTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.dirname(HERE))
sys.path.insert(0, os.path.join(ROOT, "server"))
import ta_companion as tc  # noqa: E402
from trustnet.app import Service, make_handler  # noqa: E402
from trustnet.store import Store  # noqa: E402

WOW_STYLE = '''
TrustAdvisorDB = {
\t["params"] = {
\t\t["consent.network"] = true,
\t},
\t["events"] = {
\t\t{
\t\t\t["signal"] = "member",
\t\t\t["t"] = 1800000000,
\t\t\t["subjectName"] = "Jos\\195\\169-Forever",
\t\t\t["details"] = {
\t\t\t\t["lootTimes"] = {
\t\t\t\t\t{
\t\t\t\t\t\t["q"] = 3,
\t\t\t\t\t\t["t"] = 1799999000,
\t\t\t\t\t}, -- [1]
\t\t\t\t},
\t\t\t\t["note"] = "say \\"hi\\"\\
next line",
\t\t\t\t["x"] = 0.375,
\t\t\t\t["neg"] = -2,
\t\t\t\t["big"] = 1e+15,
\t\t\t},
\t\t}, -- [1]
\t},
\t["debug"] = false,
\t["active"] = nil,
}
TrustAdvisorCharDB = {
}
'''


class Parser(unittest.TestCase):
    def test_wow_saved_variables(self):
        sv = tc.parse_saved_variables(WOW_STYLE)
        db = sv["TrustAdvisorDB"]
        self.assertIs(db["params"]["consent.network"], True)
        ev = db["events"][0]
        self.assertEqual(ev["details"]["lootTimes"][0]["q"], 3)
        self.assertEqual(ev["details"]["note"], 'say "hi"\nnext line')
        self.assertEqual(ev["details"]["x"], 0.375)
        self.assertEqual(ev["details"]["neg"], -2)
        self.assertEqual(ev["details"]["big"], 1e15)
        self.assertIs(db["debug"], False)
        self.assertEqual(sv["TrustAdvisorCharDB"], {})

    def test_lua_literal_roundtrip(self):
        data = {"players": {"Player-1-0A": {"incidents": [{"d": "finish", "x": 0, "m": 3, "t": 5}]}}, "s": 'a"b\\c\nd'}
        text = "TrustAdvisorNetData = " + tc.lua_literal(data)
        back = tc.parse_saved_variables(text)["TrustAdvisorNetData"]
        self.assertEqual(back["players"]["Player-1-0A"]["incidents"][0]["m"], 3)
        self.assertEqual(back["s"], 'a"b\\c\nd')


class Fallback(unittest.TestCase):
    def test_unreachable_primary_falls_back(self):
        svc = Service(Store(":memory:"))
        httpd = ThreadingHTTPServer(("127.0.0.1", 0), make_handler(svc))
        threading.Thread(target=httpd.serve_forever, daemon=True).start()
        try:
            good = "http://127.0.0.1:%d" % httpd.server_address[1]
            c = tc.Client("http://nonexistent.invalid", timeout=5, fallbacks=[good])
            self.assertEqual(c.players(["Player-1-0000000A"]), {})
            self.assertEqual(c.server, good)
        finally:
            httpd.shutdown()
            httpd.server_close()


class Feedback(unittest.TestCase):
    def test_feedback_is_sent_without_network_and_status_comes_back(self):
        tmp = tempfile.mkdtemp()
        try:
            wow = os.path.join(tmp, "_forever_")
            svdir = os.path.join(wow, "WTF", "Account", "X", "SavedVariables")
            os.makedirs(svdir)
            os.makedirs(os.path.join(wow, "Interface", "AddOns", "TrustAdvisor", "Network"))
            sv = os.path.join(svdir, "TrustAdvisor.lua")
            with open(sv, "w") as f:
                f.write('TrustAdvisorDB = { ["feedback"] = { ["installId"] = "%s", ["outbox"] = { '
                        '{ ["id"] = "aaaaaaaa-1-beef", ["kind"] = "bug", ["text"] = "it broke", ["version"] = "0.3.0", '
                        '["diag"] = { ["addon"] = "0.3.0" }, ["t"] = 1800000000 } } } }' % ("a" * 32))
            svc = Service(Store(":memory:"))
            httpd = ThreadingHTTPServer(("127.0.0.1", 0), make_handler(svc))
            threading.Thread(target=httpd.serve_forever, daemon=True).start()
            client = tc.Client("http://127.0.0.1:%d" % httpd.server_address[1])
            state = {}
            self.assertTrue(tc.sync_file(sv, client, wow, state, log=lambda *_: None))
            self.assertEqual(len(svc.store.list_feedback()), 1)
            svc.store.update_feedback("aaaaaaaa-1-beef", "fixed", "Thanks!", 1)
            tc.sync_file(sv, client, wow, state, log=lambda *_: None)
            nd = tc.parse_saved_variables(open(tc.netdata_path(wow), encoding="utf-8").read())["TrustAdvisorNetData"]
            self.assertEqual(nd["feedback"]["aaaaaaaa-1-beef"], {"status": "fixed", "reply": "Thanks!"})
            self.assertEqual(nd["players"], {})                       # no network data without consent
            self.assertTrue(nd["companion"]["syncedAt"] > 0)
            self.assertEqual(len(svc.store.list_feedback()), 1)       # not sent twice
            httpd.shutdown()
            httpd.server_close()
        finally:
            shutil.rmtree(tmp)


class Link(unittest.TestCase):
    def test_link_opens_browser_and_waits_for_confirmation(self):
        tmp = tempfile.mkdtemp()
        try:
            svdir = os.path.join(tmp, "WTF", "Account", "X", "SavedVariables")
            os.makedirs(svdir)
            with open(os.path.join(svdir, "TrustAdvisor.lua"), "w") as f:
                f.write('TrustAdvisorDB = { ["net"] = { ["uploaderId"] = "%s" } }' % ("a" * 32))

            class FakeClient:
                calls = 0

                def auth_begin(self, uid, region):
                    assert uid == "a" * 32 and region == "eu"
                    return "https://oauth.battle.net/authorize?x"

                def auth_status(self, uid):
                    self.calls += 1
                    return {"linked": self.calls >= 2, "characters": 1}

            opened, logs = [], []
            ok = tc.link_battlenet(FakeClient(), tmp, "eu", open_browser=opened.append, wait=5, poll=0, log=logs.append)
            self.assertTrue(ok)
            self.assertEqual(opened, ["https://oauth.battle.net/authorize?x"])
            self.assertIn("Linked to Battle.net", logs[-1])
        finally:
            shutil.rmtree(tmp)

    def test_link_without_network_join(self):
        tmp = tempfile.mkdtemp()
        logs = []
        self.assertFalse(tc.link_battlenet(object(), tmp, "us", log=logs.append))
        self.assertIn("Join the network", logs[0])
        shutil.rmtree(tmp)


class Autostart(unittest.TestCase):
    def test_mac_plist_is_valid_and_keeps_running(self):
        import plistlib
        xml = tc.mac_plist(["/usr/bin/python3", "/path with space/ta_companion.py", "--wow", "A&B"], "/tmp/log")
        d = plistlib.loads(xml.encode("utf-8"))
        self.assertEqual(d["Label"], tc.LABEL)
        self.assertEqual(d["ProgramArguments"][3], "A&B")
        self.assertTrue(d["RunAtLoad"] and d["KeepAlive"])

    def test_windows_script_quotes_paths(self):
        s = tc.windows_startup_script([r"C:\Program Files\TA\TrustAdvisorCompanion.exe", "--wow", r"D:\Games\WoW"])
        self.assertIn('"C:\\Program Files\\TA\\TrustAdvisorCompanion.exe"', s)
        self.assertTrue(s.startswith("@echo off"))

    def test_autostart_runs_in_watch_mode(self):
        captured = {}
        orig_paths, orig_run, orig_popen = tc.autostart_paths, tc.subprocess.run, tc.subprocess.Popen
        tmp = tempfile.mkdtemp()
        try:
            tc.autostart_paths = lambda: {"file": os.path.join(tmp, "x.plist"), "log": os.path.join(tmp, "log")}
            tc.subprocess.run = lambda *a, **k: captured.setdefault("run", a)
            tc.subprocess.Popen = lambda *a, **k: captured.setdefault("popen", a)
            import contextlib
            import io
            with contextlib.redirect_stdout(io.StringIO()):
                tc.install_autostart(["--wow", "/x"])
            text = open(os.path.join(tmp, "x.plist")).read()
            self.assertIn("--watch", text)   # never re-enters the double-click app mode
        finally:
            tc.autostart_paths, tc.subprocess.run, tc.subprocess.Popen = orig_paths, orig_run, orig_popen
            shutil.rmtree(tmp)

    def test_app_mode_only_for_argumentless_app_bundle_launch(self):
        self.assertFalse(tc.is_mac_app_launch([]))           # not frozen in tests
        self.assertFalse(tc.is_mac_app_launch(["--once"]))

    def test_launch_command_points_at_this_script(self):
        cmd = tc.launch_command(["--once"])
        self.assertTrue(cmd[-2].endswith("ta_companion.py") and cmd[-1] == "--once")


@unittest.skipUnless(shutil.which("luajit"), "luajit not installed")
class EndToEnd(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.wow = os.path.join(self.tmp, "_forever_")
        self.svdir = os.path.join(self.wow, "WTF", "Account", "TEST", "SavedVariables")
        os.makedirs(self.svdir)
        os.makedirs(os.path.join(self.wow, "Interface", "AddOns", "TrustAdvisor", "Network"))
        tc.STATE_PATH = os.path.join(self.tmp, "state.json")
        # same clock as the LuaJIT mock client (Tests/test_ingame_sim.lua). Standing thresholds are
        # zeroed here only because a fresh test database has no history; server tests cover them.
        self.service = Service(Store(":memory:"), clock=lambda: 1800000000 + 7200,
                               params={"net.minUploaderAgeDays": 0, "net.minCorroborated": 0,
                                       "net.requireBattlenet": False})
        self.httpd = ThreadingHTTPServer(("127.0.0.1", 0), make_handler(self.service))
        threading.Thread(target=self.httpd.serve_forever, daemon=True).start()
        self.url = "http://127.0.0.1:%d" % self.httpd.server_address[1]

    def tearDown(self):
        self.httpd.shutdown()
        shutil.rmtree(self.tmp)

    def run_sim(self, **env):
        e = dict(os.environ, **env)
        addon = os.path.join(ROOT, "TrustAdvisor")
        r = subprocess.run(["luajit", "Tests/test_ingame_sim.lua"], cwd=addon, env=e, capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stdout[-2000:] + r.stderr[-2000:])
        return r.stdout

    def test_full_loop(self):
        sv = os.path.join(self.svdir, "TrustAdvisor.lua")
        self.run_sim(TA_DUMP_SV=sv)
        db = tc.parse_saved_variables(open(sv, encoding="utf-8").read())["TrustAdvisorDB"]
        leafy = "Player-1-0000000B"
        neg = [r for r in tc.as_list(db["net"]["outbox"]["reports"]) if r["s"] == leafy and r["d"] == "finish"][0]

        client = tc.Client(self.url)
        # Tanky (in the same party, another guild) also runs Trust Advisor and saw the same loot-and-leave.
        me, tanky = "Player-1-00000001", "Player-1-0000000A"
        second = {k: neg[k] for k in ("s", "d", "x", "m", "k")}
        second["t"] = int(neg["t"]) + 30
        sess = tc.as_list(db["net"]["outbox"]["presence"])[0]
        tanky_body = {"uploaderId": "b" * 32, "protocol": 1, "witness": tanky, "witnessGuild": "Other Guild",
                      "characters": [], "reports": [second],
                      "presence": [{"a": int(sess["a"]), "b": int(sess["b"]), "m": [tanky, me, leafy]}]}
        # a forger who was never in that group claims the same thing: must not help
        client.upload({"uploaderId": "c" * 32, "protocol": 1, "witness": "Player-3-000000CC", "witnessGuild": "Third",
                       "characters": [], "reports": [second], "presence": [{"a": int(sess["a"]), "b": int(sess["b"]), "m": ["Player-3-000000CC", leafy]}]})
        logs = []
        self.assertTrue(tc.sync_file(sv, client, self.wow, {}, log=logs.append))
        netdata = tc.netdata_path(self.wow)
        nd = tc.parse_saved_variables(open(netdata, encoding="utf-8").read())["TrustAdvisorNetData"]
        incs = (nd["players"].get(leafy) or {}).get("incidents", [])
        self.assertFalse(any(i["d"] == "finish" and i["x"] == 0 for i in incs), "forger + me must not verify")
        # now the real second witness uploads
        client.upload(tanky_body)
        tc.sync_file(sv, client, self.wow, {}, log=logs.append)
        nd = tc.parse_saved_variables(open(netdata, encoding="utf-8").read())["TrustAdvisorNetData"]
        incs = nd["players"][leafy]["incidents"]
        self.assertTrue(any(i["d"] == "finish" and i["x"] == 0 and i["w"] == 2 for i in incs), incs)
        out = self.run_sim(TA_NETDATA=netdata)
        self.assertIn("network view for Leafy: finish", out)
        self.assertIn("ok   network view rendered", out)
        self.assertEqual(nd["companion"]["version"], tc.VERSION)


if __name__ == "__main__":
    unittest.main()
