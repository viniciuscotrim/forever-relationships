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
from unittest import mock
from http.server import ThreadingHTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.dirname(HERE))
sys.path.insert(0, os.path.join(ROOT, "server"))
import fr_companion as tc  # noqa: E402
from frnet.app import Service, make_handler  # noqa: E402
from frnet.store import Store  # noqa: E402

WOW_STYLE = '''
ForeverRelationshipsDB = {
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
ForeverRelationshipsCharDB = {
}
'''


class Parser(unittest.TestCase):
    def test_wow_saved_variables(self):
        sv = tc.parse_saved_variables(WOW_STYLE)
        db = sv["ForeverRelationshipsDB"]
        self.assertIs(db["params"]["consent.network"], True)
        ev = db["events"][0]
        self.assertEqual(ev["details"]["lootTimes"][0]["q"], 3)
        self.assertEqual(ev["details"]["note"], 'say "hi"\nnext line')
        self.assertEqual(ev["details"]["x"], 0.375)
        self.assertEqual(ev["details"]["neg"], -2)
        self.assertEqual(ev["details"]["big"], 1e15)
        self.assertIs(db["debug"], False)
        self.assertEqual(sv["ForeverRelationshipsCharDB"], {})

    def test_lua_literal_roundtrip(self):
        data = {"players": {"Player-1-0A": {"incidents": [{"d": "finish", "x": 0, "m": 3, "t": 5}]}}, "s": 'a"b\\c\nd'}
        text = "ForeverRelationshipsNetData = " + tc.lua_literal(data)
        back = tc.parse_saved_variables(text)["ForeverRelationshipsNetData"]
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
            self.assertEqual(c.feedback("c" * 32, [])["statuses"], {})
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
            os.makedirs(os.path.join(wow, "Interface", "AddOns", "ForeverRelationships", "Cloud"))
            sv = os.path.join(svdir, "ForeverRelationships.lua")
            with open(sv, "w") as f:
                f.write('ForeverRelationshipsDB = { ["feedback"] = { ["installId"] = "%s", ["outbox"] = { '
                        '{ ["id"] = "aaaaaaaa-1-beef", ["kind"] = "bug", ["text"] = "it broke", ["version"] = "0.3.0", '
                        '["diag"] = { ["addon"] = "0.3.0" }, ["t"] = 1800000000 } } } }' % ("a" * 32))
            svc = Service(Store(":memory:"))
            httpd = ThreadingHTTPServer(("127.0.0.1", 0), make_handler(svc))
            threading.Thread(target=httpd.serve_forever, daemon=True).start()
            client = tc.Client("http://127.0.0.1:%d" % httpd.server_address[1])
            state = {}
            tc.sync_file(sv, client, wow, state, log=lambda *_: None)
            self.assertEqual(len(svc.store.list_feedback()), 1)
            svc.store.update_feedback("aaaaaaaa-1-beef", "fixed", "Thanks!", 1)
            tc.sync_file(sv, client, wow, state, log=lambda *_: None)
            nd = tc.parse_saved_variables(open(tc.netdata_path(wow), encoding="utf-8").read())["ForeverRelationshipsNetData"]
            self.assertEqual(nd["feedback"]["aaaaaaaa-1-beef"], {"status": "fixed", "reply": "Thanks!"})
            self.assertNotIn("profiles", nd)                          # no cloud layer data without consent
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
            with open(os.path.join(svdir, "ForeverRelationships.lua"), "w") as f:
                f.write('ForeverRelationshipsDB = { ["net"] = { ["uploaderId"] = "%s" } }' % ("a" * 32))

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
        self.assertIn("Turn on a cloud layer", logs[0])
        shutil.rmtree(tmp)


class Autostart(unittest.TestCase):
    def test_mac_plist_is_valid_and_keeps_running(self):
        import plistlib
        xml = tc.mac_plist(["/usr/bin/python3", "/path with space/fr_companion.py", "--wow", "A&B"], "/tmp/log")
        d = plistlib.loads(xml.encode("utf-8"))
        self.assertEqual(d["Label"], tc.LABEL)
        self.assertEqual(d["ProgramArguments"][3], "A&B")
        self.assertTrue(d["RunAtLoad"] and d["KeepAlive"])

    def test_windows_script_quotes_paths(self):
        s = tc.windows_startup_script([r"C:\Program Files\FR\ForeverRelationshipsCompanion.exe", "--wow", r"D:\Games\WoW"])
        self.assertIn('"C:\\Program Files\\FR\\ForeverRelationshipsCompanion.exe"', s)
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
        self.assertTrue(cmd[-2].endswith("fr_companion.py") and cmd[-1] == "--once")


class Backup(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        tc.STATE_PATH = os.path.join(self.tmp, "state", "companion.json")
        self.wow = os.path.join(self.tmp, "_forever_")
        self.acct = os.path.join(self.wow, "WTF", "Account", "ACC", "SavedVariables")
        self.char = os.path.join(self.wow, "WTF", "Account", "ACC", "Realm", "Char", "SavedVariables")
        os.makedirs(self.acct)
        os.makedirs(self.char)
        with open(os.path.join(self.acct, "ForeverRelationships.lua"), "w") as f:
            f.write('ForeverRelationshipsDB = { ["cloud"] = { ["uploaderId"] = "%s" }, ["events"] = { { ["signal"] = "session" } } }' % ("a" * 32))
        with open(os.path.join(self.char, "ForeverRelationships.lua"), "w") as f:
            f.write("ForeverRelationshipsCharDB = { }")
        self.svc = Service(Store(":memory:"), hash_salt="k")
        self.httpd = ThreadingHTTPServer(("127.0.0.1", 0), make_handler(self.svc))
        threading.Thread(target=self.httpd.serve_forever, daemon=True).start()
        self.client = tc.Client("http://127.0.0.1:%d" % self.httpd.server_address[1])
        self.ks = tc.KeyStore(use_keychain=False)

    def tearDown(self):
        self.httpd.shutdown()
        self.httpd.server_close()
        shutil.rmtree(self.tmp)

    def test_crypto_and_recovery_code(self):
        key = os.urandom(32)
        code = tc.recovery_code(key)
        self.assertEqual(tc.key_from_code(code.lower().replace("-", " ")), key)
        blob = tc.encrypt_blob(key, b"history")
        self.assertNotIn(b"history", blob)
        self.assertEqual(tc.decrypt_blob(key, blob), b"history")
        with self.assertRaises(Exception):
            tc.decrypt_blob(os.urandom(32), blob)            # wrong key: authentication fails
        bid, tok = tc.backup_ids(key)
        self.assertEqual((len(bid), len(tok)), (64, 64))
        self.assertNotEqual(bid, tok)

    def test_backup_upload_is_unreadable_and_restores_everything(self):
        logs = []
        info, code = tc.sync_backup(self.wow, "a" * 32, self.client, {}, self.ks, log=logs.append)
        self.assertTrue(code and info["size"] > 0)
        self.assertTrue(any("recovery code" in l.lower() for l in logs))
        stored = list(self.svc.store._mem_blobs.values())[0]
        self.assertNotIn(b"ForeverRelationshipsDB", stored)          # the server only holds ciphertext
        # second sync without changes uploads nothing new
        _, code2 = tc.sync_backup(self.wow, "a" * 32, self.client, {"backup-aaaaaaaa": {"digest": "x"}}, self.ks, log=lambda *_: None)
        self.assertIsNone(code2)
        # new computer: wipe the files and the key, restore from the code
        shutil.rmtree(os.path.join(self.wow, "WTF"))
        self.ks.delete("a" * 32)
        n = tc.restore_backup(code, self.wow, self.client, self.ks, log=lambda *_: None)
        self.assertEqual(n, 2)
        with open(os.path.join(self.char, "ForeverRelationships.lua")) as f:
            self.assertIn("ForeverRelationshipsCharDB", f.read())
        self.assertIsNotNone(self.ks.load("a" * 32))           # future backups use the same key
        with self.assertRaises(RuntimeError):
            tc.restore_backup(tc.recovery_code(os.urandom(32)), self.wow, self.client, self.ks, log=lambda *_: None)


@unittest.skipUnless(shutil.which("luajit"), "luajit not installed")
class EndToEnd(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.wow = os.path.join(self.tmp, "_forever_")
        self.svdir = os.path.join(self.wow, "WTF", "Account", "TEST", "SavedVariables")
        os.makedirs(self.svdir)
        os.makedirs(os.path.join(self.wow, "Interface", "AddOns", "ForeverRelationships", "Cloud"))
        tc.STATE_PATH = os.path.join(self.tmp, "state.json")
        # same clock as the LuaJIT mock client (Tests/test_ingame_sim.lua)
        self.service = Service(Store(":memory:"), clock=lambda: 1800000000 + 7200, hash_salt="k")
        self.httpd = ThreadingHTTPServer(("127.0.0.1", 0), make_handler(self.service))
        threading.Thread(target=self.httpd.serve_forever, daemon=True).start()
        self.url = "http://127.0.0.1:%d" % self.httpd.server_address[1]

    def tearDown(self):
        self.httpd.shutdown()
        self.httpd.server_close()
        shutil.rmtree(self.tmp)

    def run_sim(self, **env):
        e = dict(os.environ, **env)
        r = subprocess.run(["luajit", "Tests/test_ingame_sim.lua"], cwd=os.path.join(ROOT, "ForeverRelationships"), env=e, capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stdout[-2000:] + r.stderr[-2000:])
        return r.stdout

    def test_full_loop(self):
        sv = os.path.join(self.svdir, "ForeverRelationships.lua")
        self.run_sim(FR_DUMP_SV=sv)
        db = tc.parse_saved_variables(open(sv, encoding="utf-8").read())["ForeverRelationshipsDB"]
        self.assertTrue(db["cloud"]["outbox"]["consents"]["community"])
        client = tc.Client(self.url)
        # Tanky also uses the addon and publishes a profile
        self.service.sync({"uploaderId": "b" * 32, "protocol": 2, "consents": {"profile": True},
                           "me": {"guid": "Player-1-0000000A", "name": "Tanky"}, "profile": {"hours": 120, "dungeons": 40}})
        tc.sync_file(sv, client, self.wow, {}, log=lambda *_: None, keystore=tc.KeyStore(use_keychain=False))
        stored = self.service.store.q("SELECT count(*) FROM community_sessions", one=True)[0]
        self.assertGreaterEqual(stored, 1)
        dump = "\n".join(str(tuple(r)) for r in self.service.store.q("SELECT * FROM community_members"))
        self.assertNotIn("Player-1-", dump)                     # pseudonymized on arrival
        nd = tc.parse_saved_variables(open(tc.netdata_path(self.wow), encoding="utf-8").read())["ForeverRelationshipsNetData"]
        self.assertIn("Player-1-0000000A", nd["profiles"])
        self.assertEqual(nd["companion"]["version"], tc.VERSION)
        out = self.run_sim(FR_NETDATA=tc.netdata_path(self.wow))
        self.assertIn("ok   NetData: public profile", out)
        # population census: pseudonymized on arrival, published by realm type once the realm is classified
        census = self.service.store.q("SELECT * FROM census")
        self.assertGreaterEqual(len(census), 3)
        self.assertNotIn("Player-", "\n".join(str(tuple(r)) for r in census))
        self.assertEqual(self.service.store.q("SELECT name FROM realms WHERE id = 2", one=True)[0], "Other Realm")
        self.service.store.set_realm_type(1, "pvp")
        self.service.store.set_realm_type(2, "pve")
        self.service._population = (0, None)
        tc.sync_file(sv, client, self.wow, {}, log=lambda *_: None, keystore=tc.KeyStore(use_keychain=False))
        nd = tc.parse_saved_variables(open(tc.netdata_path(self.wow), encoding="utf-8").read())["ForeverRelationshipsNetData"]
        pop = nd["population"]
        self.assertGreaterEqual(pop["types"]["pvp"]["Horde"]["total"], 2)          # me (Undead) + the Orc I targeted
        self.assertEqual(pop["types"]["pve"]["Alliance"]["races"], {"Night Elf": 1})
        self.assertEqual(pop["realms"]["1"]["type"], "pvp")

    def test_population_reaches_players_with_every_layer_off(self):
        sv = os.path.join(self.svdir, "ForeverRelationships.lua")
        with open(sv, "w") as f:
            f.write("ForeverRelationshipsDB = {\n}\n")
        tc.sync_file(sv, tc.Client(self.url), self.wow, {}, log=lambda *_: None, keystore=tc.KeyStore(use_keychain=False))
        nd = tc.parse_saved_variables(open(tc.netdata_path(self.wow), encoding="utf-8").read())["ForeverRelationshipsNetData"]
        self.assertIn("updatedAt", nd["population"])



class Legacy(unittest.TestCase):
    def test_migrates_old_name_when_game_closed(self):
        old = "Trust" + "Advisor"
        with tempfile.TemporaryDirectory() as wow, tempfile.TemporaryDirectory() as home:
            sv = os.path.join(wow, "WTF", "Account", "ACC", "SavedVariables")
            ch = os.path.join(wow, "WTF", "Account", "ACC", "Realm", "Char", "SavedVariables")
            os.makedirs(sv); os.makedirs(ch)
            with open(os.path.join(sv, old + ".lua"), "w") as f:
                f.write(old + 'DB = {\n["events"] = {\n{\n["signal"] = "trade",\n},\n},\n}\n')
            with open(os.path.join(ch, old + ".lua"), "w") as f:
                f.write(old + 'CharDB = {\n["ui"] = {},\n}\n')
            # the new addon already ran once and wrote an empty file: it gets replaced
            with open(os.path.join(sv, "ForeverRelationships.lua"), "w") as f:
                f.write('ForeverRelationshipsDB = {\n["events"] = {},\n}\n')
            for d in (old, "ForeverRelationships"):
                os.makedirs(os.path.join(wow, "Interface", "AddOns", d))
            with mock.patch.object(tc, "wow_running", return_value=False), \
                 mock.patch.object(tc, "STATE_PATH", os.path.join(home, ".forever-relationships", "companion.json")), \
                 mock.patch.dict(os.environ, {"HOME": home, "APPDATA": home}), \
                 mock.patch.object(tc.subprocess, "run"):
                done = tc.migrate_legacy(wow)
                self.assertEqual(tc.migrate_legacy(wow), [], "second run is a no-op")
            with open(os.path.join(sv, "ForeverRelationships.lua")) as f:
                db = tc.parse_saved_variables(f.read())["ForeverRelationshipsDB"]
            self.assertEqual(db["events"][0]["signal"], "trade")
            with open(os.path.join(ch, "ForeverRelationships.lua")) as f:
                self.assertIn("ForeverRelationshipsCharDB", tc.parse_saved_variables(f.read()))
            self.assertTrue(os.path.exists(os.path.join(sv, old + ".lua.migrated")))
            self.assertFalse(os.path.isdir(os.path.join(wow, "Interface", "AddOns", old)))
            self.assertIn("old addon folder", done)

    def test_leaves_files_alone_while_game_runs(self):
        old = "Trust" + "Advisor"
        with tempfile.TemporaryDirectory() as wow:
            sv = os.path.join(wow, "WTF", "Account", "ACC", "SavedVariables"); os.makedirs(sv)
            with open(os.path.join(sv, old + ".lua"), "w") as f:
                f.write(old + "DB = {}\n")
            with mock.patch.object(tc, "wow_running", return_value=True), mock.patch.object(tc.subprocess, "run"):
                tc.migrate_legacy(wow)
            self.assertTrue(os.path.exists(os.path.join(sv, old + ".lua")))

@unittest.skipUnless(sys.platform == "darwin", "App Translocation is macOS only")
class Translocation(unittest.TestCase):
    def test_autostart_points_at_the_real_app(self):
        with tempfile.TemporaryDirectory() as home:
            real = os.path.join(home, "Applications", "X.app", "Contents", "MacOS")
            os.makedirs(real); open(os.path.join(real, "X"), "w").close()
            moved = "/private/var/folders/aa/T/AppTranslocation/ABC/d/X.app/Contents/MacOS/X"
            with mock.patch.dict(os.environ, {"HOME": home}):
                self.assertEqual(tc.stable_executable(moved), os.path.join(real, "X"))
            self.assertEqual(tc.stable_executable("/Applications/X.app/Contents/MacOS/X"), "/Applications/X.app/Contents/MacOS/X")


class WatchLoop(unittest.TestCase):
    def test_self_test_passes_with_encryption(self):
        self.assertEqual(tc.main(["--self-test"]), 0)

    def test_syncs_on_change_and_again_every_hour(self):
        clock = [1000.0]
        calls = []

        class Stop(Exception):
            pass

        def sleep(sec):
            clock[0] += sec
            if clock[0] > 1000 + 2 * 3600 + 60:
                raise Stop()

        with tempfile.TemporaryDirectory() as wow, tempfile.TemporaryDirectory() as home:
            sv = os.path.join(wow, "a.lua")
            open(sv, "w").close()
            with mock.patch.object(tc, "find_saved_variables", return_value=[sv]), \
                 mock.patch.object(tc, "sync_file", side_effect=lambda *a: calls.append(clock[0]) or {}), \
                 mock.patch.object(tc, "migrate_legacy", return_value=[]), \
                 mock.patch.object(tc, "STATE_PATH", os.path.join(home, "s.json")), \
                 mock.patch.object(tc.time, "time", side_effect=lambda: clock[0]), \
                 mock.patch.object(tc.time, "sleep", side_effect=sleep), \
                 mock.patch("builtins.print"):
                with self.assertRaises(Stop):
                    tc.main(["--wow", wow, "--server", "http://127.0.0.1:9", "--interval", "30"])
        # first sight, then once per hour with the file unchanged (not every 30 s)
        self.assertEqual(len(calls), 3, calls)
        self.assertGreaterEqual(calls[1] - calls[0], 3600)


if __name__ == "__main__":
    unittest.main()
