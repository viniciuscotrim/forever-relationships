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


@unittest.skipUnless(shutil.which("luajit"), "luajit not installed")
class EndToEnd(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.wow = os.path.join(self.tmp, "_forever_")
        self.svdir = os.path.join(self.wow, "WTF", "Account", "TEST", "SavedVariables")
        os.makedirs(self.svdir)
        os.makedirs(os.path.join(self.wow, "Interface", "AddOns", "TrustAdvisor", "Network"))
        tc.STATE_PATH = os.path.join(self.tmp, "state.json")
        # same clock as the LuaJIT mock client (Tests/test_ingame_sim.lua)
        self.service = Service(Store(":memory:"), clock=lambda: 1800000000 + 7200)
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
        # a second, independent witness from another guild saw the same loot-and-leave
        second = {k: neg[k] for k in ("s", "d", "x", "m", "k")}
        second["t"] = int(neg["t"]) + 30
        client.upload({"uploaderId": "b" * 32, "protocol": 1, "witness": "Player-2-000000EE",
                       "witnessGuild": "Other Guild", "characters": [], "reports": [second]})
        logs = []
        self.assertTrue(tc.sync_file(sv, client, self.wow, {}, log=logs.append))
        netdata = tc.netdata_path(self.wow)
        nd = tc.parse_saved_variables(open(netdata, encoding="utf-8").read())["TrustAdvisorNetData"]
        incs = nd["players"][leafy]["incidents"]
        self.assertTrue(any(i["d"] == "finish" and i["x"] == 0 and i["w"] == 2 for i in incs), incs)
        out = self.run_sim(TA_NETDATA=netdata)
        self.assertIn("network view for Leafy: finish", out)
        self.assertIn("ok   network view rendered", out)


if __name__ == "__main__":
    unittest.main()
