"""Admin cockpit: passkey + TOTP authentication, sessions, HTTP surface, overview + demo data.
Needs the `cryptography` package (server/requirements.txt)."""
import hashlib
import json
import os
import struct
import sys
import threading
import unittest
import urllib.error
import urllib.request
from http.server import ThreadingHTTPServer

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from cryptography.hazmat.primitives import hashes  # noqa: E402
from cryptography.hazmat.primitives.asymmetric import ec  # noqa: E402

from trustnet import admin as admin_mod, demo, totp, webauthn  # noqa: E402
from trustnet.app import Service, make_handler  # noqa: E402
from trustnet.store import Store  # noqa: E402

ORIGIN, RP = "https://ta.example", "ta.example"
NOW = 1800000000


# --- a tiny CBOR encoder, only to build authenticator responses in tests
def cbor(v):
    def head(major, n):
        if n < 24:
            return bytes([major << 5 | n])
        for info, size in ((24, 1), (25, 2), (26, 4), (27, 8)):
            if n < 1 << (8 * size):
                return bytes([major << 5 | info]) + n.to_bytes(size, "big")
    if isinstance(v, bool):
        return b"\xf5" if v else b"\xf4"
    if isinstance(v, int):
        return head(0, v) if v >= 0 else head(1, -1 - v)
    if isinstance(v, bytes):
        return head(2, len(v)) + v
    if isinstance(v, str):
        b = v.encode()
        return head(3, len(b)) + b
    if isinstance(v, list):
        return head(4, len(v)) + b"".join(cbor(x) for x in v)
    if isinstance(v, dict):
        return head(5, len(v)) + b"".join(cbor(k) + cbor(x) for k, x in v.items())
    raise TypeError(v)


class FakeAuthenticator:
    """Behaves like Touch ID / Face ID with a passkey."""
    def __init__(self, uv=True, origin=ORIGIN, rp=RP):
        self.key = ec.generate_private_key(ec.SECP256R1())
        self.cred_id = os.urandom(16)
        self.uv, self.origin, self.rp = uv, origin, rp

    def _flags(self, at=False):
        return 0x01 | (0x04 if self.uv else 0) | (0x40 if at else 0)

    def create(self, options):
        nums = self.key.public_key().public_numbers()
        cose = {1: 2, 3: -7, -1: 1, -2: nums.x.to_bytes(32, "big"), -3: nums.y.to_bytes(32, "big")}
        auth = (hashlib.sha256(self.rp.encode()).digest() + bytes([self._flags(True)]) + struct.pack(">I", 0)
                + b"\0" * 16 + struct.pack(">H", len(self.cred_id)) + self.cred_id + cbor(cose))
        cd = json.dumps({"type": "webauthn.create", "challenge": options["publicKey"]["challenge"], "origin": self.origin}).encode()
        return {"id": webauthn.b64url_encode(self.cred_id), "rawId": webauthn.b64url_encode(self.cred_id), "type": "public-key",
                "response": {"clientDataJSON": webauthn.b64url_encode(cd),
                             "attestationObject": webauthn.b64url_encode(cbor({"fmt": "none", "attStmt": {}, "authData": auth}))}}

    def get(self, options, tamper=False):
        auth = hashlib.sha256(self.rp.encode()).digest() + bytes([self._flags()]) + struct.pack(">I", 0)
        cd = json.dumps({"type": "webauthn.get", "challenge": options["publicKey"]["challenge"], "origin": self.origin}).encode()
        sig = self.key.sign(auth + hashlib.sha256(cd).digest(), ec.ECDSA(hashes.SHA256()))
        if tamper:
            sig = sig[:-1] + bytes([sig[-1] ^ 1])
        return {"id": webauthn.b64url_encode(self.cred_id), "rawId": webauthn.b64url_encode(self.cred_id), "type": "public-key",
                "response": {"clientDataJSON": webauthn.b64url_encode(cd), "authenticatorData": webauthn.b64url_encode(auth),
                             "signature": webauthn.b64url_encode(sig)}}


class Totp(unittest.TestCase):
    def test_rfc6238_vector(self):
        secret = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"   # "12345678901234567890"
        self.assertEqual(totp.code_at(secret, 59), "287082")
        self.assertEqual(totp.code_at(secret, 1111111109), "081804")

    def test_window_and_replay(self):
        s = totp.new_secret()
        step = totp.verify(s, totp.code_at(s, NOW - 30), NOW)
        self.assertIsNotNone(step)                                       # one step of drift accepted
        self.assertIsNone(totp.verify(s, totp.code_at(s, NOW - 30), NOW, last_used_step=step))  # no replay
        self.assertIsNone(totp.verify(s, "12345", NOW))
        self.assertTrue(totp.otpauth_uri(s, "admin@x").startswith("otpauth://totp/"))


class AdminAuth(unittest.TestCase):
    def setUp(self):
        self.clock = [NOW]
        self.store = Store(":memory:")
        self.svc = Service(self.store, clock=lambda: self.clock[0])
        self.adm = admin_mod.Admin(self.store, self.svc, RP, ORIGIN, clock=lambda: self.clock[0])
        self.auth = FakeAuthenticator()

    def enroll(self):
        token = self.adm.create_setup_link().split("#setup=")[1]
        begin = self.adm.setup_begin({"setupToken": token})
        fin = self.adm.setup_finish({"nonce": begin["nonce"], "credential": self.auth.create(begin)})
        self.secret = fin["totpSecret"]
        self.adm.setup_totp({"nonce": fin["nonce"], "code": totp.code_at(self.secret, self.clock[0])})
        return token

    def login(self, authenticator=None, code=None):
        begin = self.adm.login_begin("1.2.3.4")
        self.adm.login_passkey({"nonce": begin["nonce"], "credential": (authenticator or self.auth).get(begin)}, "1.2.3.4")
        self.clock[0] += 30
        return self.adm.login_code({"nonce": begin["nonce"], "code": code or totp.code_at(self.secret, self.clock[0])}, "1.2.3.4")

    def test_full_enroll_and_login(self):
        self.assertFalse(self.adm.enrolled())
        token = self.enroll()
        self.assertTrue(self.adm.enrolled())
        with self.assertRaises(admin_mod.AuthError):                     # setup link is single use
            self.adm.setup_begin({"setupToken": token})
        session = self.login()
        self.assertTrue(self.adm.session_ok(session))
        self.adm.logout(session)
        self.assertFalse(self.adm.session_ok(session))

    def test_setup_link_expires(self):
        token = self.adm.create_setup_link().split("#setup=")[1]
        self.clock[0] += admin_mod.SETUP_TTL + 1
        with self.assertRaises(admin_mod.AuthError):
            self.adm.setup_begin({"setupToken": token})

    def test_passkey_must_verify_the_user(self):
        token = self.adm.create_setup_link().split("#setup=")[1]
        begin = self.adm.setup_begin({"setupToken": token})
        with self.assertRaises(admin_mod.AuthError) as cm:
            self.adm.setup_finish({"nonce": begin["nonce"], "credential": FakeAuthenticator(uv=False).create(begin)})
        self.assertIn("Touch ID", str(cm.exception))

    def test_wrong_origin_unknown_key_and_bad_signature_rejected(self):
        self.enroll()
        for bad in (FakeAuthenticator(origin="https://evil.example"), FakeAuthenticator()):   # phishing origin, unknown passkey
            begin = self.adm.login_begin()
            with self.assertRaises(admin_mod.AuthError):
                self.adm.login_passkey({"nonce": begin["nonce"], "credential": bad.get(begin)})
        begin = self.adm.login_begin()
        with self.assertRaises(admin_mod.AuthError):
            self.adm.login_passkey({"nonce": begin["nonce"], "credential": self.auth.get(begin, tamper=True)})

    def test_code_required_after_passkey_and_not_reusable(self):
        self.enroll()
        begin = self.adm.login_begin()
        with self.assertRaises(admin_mod.AuthError):                     # code without passkey
            self.adm.login_code({"nonce": begin["nonce"], "code": totp.code_at(self.secret, self.clock[0])})
        self.login()
        with self.assertRaises(admin_mod.AuthError):                     # same 30 s step again
            self.login(code=totp.code_at(self.secret, self.clock[0]))

    def test_lockout_after_failures(self):
        self.enroll()
        for _ in range(5):
            begin = self.adm.login_begin()
            self.adm.login_passkey({"nonce": begin["nonce"], "credential": self.auth.get(begin)})
            with self.assertRaises(admin_mod.AuthError):
                self.adm.login_code({"nonce": begin["nonce"], "code": "000000"})
        with self.assertRaises(admin_mod.AuthError) as cm:
            self.adm.login_begin()
        self.assertEqual(cm.exception.status, 429)
        self.clock[0] += admin_mod.LOCK_WINDOW + 1
        self.adm.login_begin()                                            # unlocks after 15 minutes

    def test_overview_with_demo_data_then_clean(self):
        demo.seed(self.store, now=NOW)
        o = self.adm.overview()
        k = o["kpis"]
        self.assertGreater(k["participants"], 100)
        self.assertGreater(k["verifiedIncidents"], 0)
        self.assertGreater(k["verifiedNegatives"], 0)                     # multi-witness, multi-guild negatives verify
        self.assertGreater(k["feedbackTotal"], 0)
        self.assertGreater(o["demoRows"], 0)
        factions = {r["k"] for r in o["demographics"]["faction"]}
        self.assertEqual(factions, {"Alliance", "Horde"})
        self.assertTrue(o["demographics"]["race"] and o["demographics"]["levels"])
        self.assertEqual(len(o["series"]["reports"]), 30)
        after = demo.clean(self.store)
        self.assertEqual(after, {"uploaders": 0, "reports": 0, "feedback": 0, "disputes": 0})
        self.assertEqual(self.adm.overview()["demoRows"], 0)


class AdminHttp(unittest.TestCase):
    def setUp(self):
        store = Store(":memory:")
        svc = Service(store)
        self.adm = admin_mod.Admin(store, svc, RP, ORIGIN)
        self.httpd = ThreadingHTTPServer(("127.0.0.1", 0), make_handler(svc, self.adm))
        threading.Thread(target=self.httpd.serve_forever, daemon=True).start()
        self.base = "http://127.0.0.1:%d" % self.httpd.server_address[1]

    def tearDown(self):
        self.httpd.shutdown()
        self.httpd.server_close()

    def req(self, path, method="GET", body=None, headers=None):
        r = urllib.request.Request(self.base + path, data=json.dumps(body).encode() if body is not None else None,
                                   method=method, headers=dict({"Content-Type": "application/json"}, **(headers or {})))
        try:
            with urllib.request.urlopen(r) as resp:
                return resp.status, dict(resp.headers), resp.read()
        except urllib.error.HTTPError as e:
            return e.code, dict(e.headers), e.read()

    def test_static_page_with_security_headers(self):
        code, h, body = self.req("/admindash/")
        self.assertEqual(code, 200)
        self.assertIn(b"Trust Advisor Cockpit", body)
        self.assertIn("frame-ancestors 'none'", h["Content-Security-Policy"])
        self.assertEqual(h["Cache-Control"], "no-store")
        self.assertEqual(self.req("/admindash/../app.py")[0], 404)

    def test_data_requires_login_and_posts_require_origin(self):
        self.assertEqual(self.req("/admindash/api/overview")[0], 401)
        self.assertEqual(self.req("/admindash/api/login/begin", "POST", {})[0], 403)          # no Origin header
        code, _, body = self.req("/admindash/api/login/begin", "POST", {}, {"Origin": ORIGIN})
        self.assertEqual(code, 403)                                                         # nobody enrolled yet
        self.assertIn(b"setup link", body)
        self.assertEqual(json.loads(self.req("/admindash/api/status")[2]), {"enrolled": False, "session": False})


if __name__ == "__main__":
    unittest.main()
