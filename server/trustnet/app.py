"""Trust Advisor network HTTP API (stdlib only). Run behind a TLS reverse proxy.

  GET  /healthz
  GET  /v1/protocol                       published locked parameters
  POST /v1/upload                         companion upload (reports, disputes, deletion)
  GET  /v1/players?guids=a,b,c            verified, undisputed incidents (public view)
  POST /v1/self                           every incident about your own characters
  POST /v1/auth/begin                     {uploaderId, region} -> Battle.net login URL
  GET  /v1/auth/callback                  Battle.net redirect target (HTML page)
  POST /v1/auth/status                    {uploaderId} -> linked?, verified characters
  POST /v1/feedback                       {installId, items} -> stores reports, returns status/replies
  GET  /v1/admin/feedback[?status=]       X-Admin-Token
  POST /v1/admin/feedback/<id>            X-Admin-Token, {"status": ..., "reply": "..."}
  GET  /v1/admin/disputes                 X-Admin-Token
  POST /v1/admin/disputes/<id>            X-Admin-Token, {"status": "upheld"|"rejected"}

Env: TA_DB (sqlite path), TA_ADMIN_TOKEN, TA_PORT (default 8080), TA_HASH_SALT,
     TA_BNET_CLIENT_ID, TA_BNET_CLIENT_SECRET, TA_PUBLIC_URLS (comma list of public base URLs).
"""
import hashlib
import html
import json
import os
import re
import secrets
import sys
import threading
import time
from http.cookies import SimpleCookie
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

from . import admin as admin_mod, aggregate, bnet as bnet_mod
from .store import Store, hash_id

GUID_RE = re.compile(r"^Player-\d+-[0-9A-Fa-f]+$")
UPLOADER_RE = re.compile(r"^[0-9a-f]{32}$")
MAX_BODY = 4 * 1024 * 1024
MAX_REPORTS = 20000
MAX_GUIDS = 500
MAX_SESSIONS = 5000
MAX_MEMBERS = 40
FEEDBACK_ID_RE = re.compile(r"^[A-Za-z0-9-]{8,64}$")
FEEDBACK_STATUSES = ("received", "planned", "fixed", "done", "wontfix", "duplicate")
FEEDBACK_PER_DAY = 20
RATE_PER_MIN = 60
YEAR = 400 * 86400


class BadRequest(Exception):
    pass


def _word(v, n=24):
    """A short label (class/race/realm/locale): letters, digits, space, ' and - only."""
    if not isinstance(v, str):
        return None
    v = re.sub(r"[^\w '\-]", "", v, flags=re.UNICODE)[:n].strip()
    return v or None


def validate_report(r, now):
    if not isinstance(r, dict):
        raise BadRequest("report must be an object")
    s, d, k = r.get("s"), r.get("d"), r.get("k")
    x, m, t = r.get("x"), r.get("m", 1), r.get("t")
    if not (isinstance(s, str) and GUID_RE.match(s)):
        raise BadRequest("bad subject guid")
    if d not in aggregate.ELIGIBLE:
        raise BadRequest("dimension not eligible for the network: %r" % d)
    if not isinstance(x, (int, float)) or not 0 <= x <= 1:
        raise BadRequest("x must be in [0,1]")
    if not isinstance(m, (int, float)) or not 0 < m <= 10:
        raise BadRequest("m must be in (0,10]")
    if not isinstance(t, int) or not (now - YEAR <= t <= now + 86400):
        raise BadRequest("t out of range")
    if not (isinstance(k, str) and 0 < len(k) <= 120):
        raise BadRequest("bad kind")
    return {"s": s, "d": d, "x": float(x), "m": float(m), "t": t, "k": k}


def validate_presence(raw, now):
    out = []
    if not isinstance(raw, list) or len(raw) > MAX_SESSIONS:
        raise BadRequest("bad presence")
    for sess in raw:
        if not isinstance(sess, dict):
            raise BadRequest("bad presence session")
        a, b, members = sess.get("a"), sess.get("b"), sess.get("m")
        if not (isinstance(a, int) and isinstance(b, int) and now - YEAR <= a <= b <= now + 86400 and b - a <= 86400):
            raise BadRequest("bad presence window")
        if not (isinstance(members, list) and 0 < len(members) <= MAX_MEMBERS and all(isinstance(g, str) and GUID_RE.match(g) for g in members)):
            raise BadRequest("bad presence members")
        out.append((a, b, members))
    return out


class Service:
    """Transport-independent API logic (tested directly)."""

    def __init__(self, store, admin_token=None, clock=time.time, params=None, bnet=None,
                 public_urls=(), hash_salt=""):
        self.store = store
        self.admin_token = admin_token
        self.clock = clock
        self.bnet = bnet
        self.public_urls = [u.rstrip("/") for u in public_urls if u]
        self.hash_salt = hash_salt
        self.params = dict(aggregate.PARAMS)
        if params:  # tests only; production always uses the published protocol
            self.params.update(params)

    def now(self):
        return int(self.clock())

    def protocol(self):
        return {"protocol": aggregate.PROTOCOL_VERSION, "params": self.params,
                "eligible": sorted(aggregate.ELIGIBLE)}

    def _uploader(self, body):
        uid = body.get("uploaderId")
        if not (isinstance(uid, str) and UPLOADER_RE.match(uid)):
            raise BadRequest("bad uploaderId")
        return hash_id(uid)

    # -- Battle.net identity ---------------------------------------------------
    def account_hash(self, account_id):
        return hashlib.sha256(("%s:%s" % (self.hash_salt, account_id)).encode("utf-8")).hexdigest()

    def auth_begin(self, body, host=None):
        if not self.bnet or not self.public_urls:
            raise BadRequest("Battle.net login is not configured on this server")
        uploader = self._uploader(body)
        region = str(body.get("region") or "us").lower()
        if region not in bnet_mod.REGIONS:
            raise BadRequest("region must be one of us, eu, kr, tw")
        base = self.public_urls[0]
        for u in self.public_urls:
            if host and u.split("://", 1)[-1] == host:
                base = u
        redirect = base + "/v1/auth/callback"
        state = secrets.token_urlsafe(24)
        self.store.create_state(state, uploader, redirect, region, self.now())
        return {"url": self.bnet.authorize_url(redirect, state), "expiresIn": 900}

    def auth_callback(self, query):
        """Returns (http_status, title, message) for a small HTML page."""
        if query.get("error"):
            return 400, "Login cancelled", "Battle.net login was cancelled. You can close this window and run --link again."
        st = self.store.pop_state(query.get("state", ""), self.now())
        if not st or not query.get("code"):
            return 400, "Link expired", "This login link expired or was already used. Run the companion with --link again."
        try:
            token = self.bnet.exchange(query["code"], st["redirect"])
            account = self.account_hash(self.bnet.account_id(token))
            guids = [g for g in self.bnet.forever_characters(token, st["region"]) if GUID_RE.match(g)]
        except Exception:
            return 502, "Battle.net error", "Battle.net did not answer correctly. Please try again in a few minutes."
        self.store.link(st["uploader"], account, st["region"], guids, self.now())
        chars = ("%d WoW: Forever character(s) verified." % len(guids)) if guids else \
            "No WoW: Forever characters were listed by Battle.net yet; your account is linked and characters will be verified when available."
        return 200, "Linked", "Your Trust Advisor network identity is now linked to your Battle.net account. " + chars + \
            " Only a one-way hash of your account id is stored. You can close this window."

    def auth_status(self, body):
        uploader = self._uploader(body)
        link = self.store.link_of(uploader)
        if not link:
            return {"linked": False}
        owned = self.store.owned_map().get(link["account"], set())
        return {"linked": True, "region": link["region"], "linkedAt": link["linked_at"], "characters": len(owned)}

    # -- feedback (in-game, delivered by the companion; independent of the network) --
    def _install(self, body):
        iid = body.get("installId")
        if not (isinstance(iid, str) and UPLOADER_RE.match(iid)):
            raise BadRequest("bad installId")
        return hash_id(iid)

    def feedback(self, body):
        now = self.now()
        install = self._install(body)
        items = body.get("items") or []
        if not isinstance(items, list) or len(items) > 20:
            raise BadRequest("items must be a list of at most 20")
        accepted = 0
        for it in items:
            if not isinstance(it, dict):
                raise BadRequest("bad item")
            fid, kind = it.get("id"), it.get("kind")
            if not (isinstance(fid, str) and FEEDBACK_ID_RE.match(fid)):
                raise BadRequest("bad feedback id")
            if kind not in ("bug", "idea"):
                raise BadRequest("kind must be bug or idea")
            diag = it.get("diag")
            diag_json = json.dumps(diag)[:8192] if isinstance(diag, (dict, list)) else None
            if self.store.feedback_recent_count(install, now - 86400) >= FEEDBACK_PER_DAY:
                break  # quietly stop: per-install daily limit
            accepted += self.store.add_feedback(install, {
                "id": fid, "kind": kind, "text": str(it.get("text") or "")[:1000],
                "version": str(it.get("version") or "")[:20], "diag": diag_json,
                "t": int(it.get("t") or now)}, now)
        return {"accepted": accepted, "statuses": self.store.feedback_statuses(install)}

    def _contested(self):
        claims = self.store.self_claims()
        owners = {}
        for up, guids in claims.items():
            for g in guids:
                owners.setdefault(g, set()).add(up)
        return {g for g, ups in owners.items() if len(ups) > 1}

    def upload(self, body):
        now = self.now()
        uploader = self._uploader(body)
        if body.get("protocol") != aggregate.PROTOCOL_VERSION:
            raise BadRequest("unsupported protocol version")
        if body.get("deleteRequested"):
            mine = self._own_guids(uploader)
            claimed = self.store.claimed_by(uploader)
            skip = claimed - mine
            guids = self.store.delete_uploader(uploader, now, skip=skip)
            return {"deleted": True, "hidden": sorted(g for g in guids if g not in skip)}
        witness = body.get("witness")
        if not (isinstance(witness, str) and GUID_RE.match(witness)):
            raise BadRequest("bad witness guid")
        wguild = str(body.get("witnessGuild") or "")[:64]
        chars = []
        for ch in (body.get("characters") or [])[:50]:
            if isinstance(ch, dict) and isinstance(ch.get("guid"), str) and GUID_RE.match(ch["guid"]):
                lvl = ch.get("level")
                chars.append({"guid": ch["guid"], "name": str(ch.get("name", ""))[:64], "guild": str(ch.get("guild", ""))[:64],
                              # own-character demographics (anonymous statistics in the admin cockpit)
                              "class": _word(ch.get("class")), "race": _word(ch.get("race")),
                              "faction": ch.get("faction") if ch.get("faction") in ("Alliance", "Horde", "Neutral") else None,
                              "level": lvl if isinstance(lvl, int) and 1 <= lvl <= 100 else None,
                              "realm": _word(ch.get("realm"), 48), "locale": _word(ch.get("locale"), 8)})
        if witness not in {c["guid"] for c in chars}:
            chars.append({"guid": witness, "name": "", "guild": wguild})
        raw = body.get("reports") or []
        if len(raw) > MAX_REPORTS:
            raise BadRequest("too many reports")
        reports = [validate_report(r, now) for r in raw]
        presence = validate_presence(body.get("presence") or [], now)
        stored = self.store.upload(uploader, witness, wguild, chars, reports, now)
        if presence:
            self.store.add_presence(uploader, presence)

        disputed = 0
        own = self._own_guids(uploader)
        if body.get("disputes"):
            incs = self._incidents(list(own))
            by_id = {i["id"]: i for lst in incs.values() for i in lst}
            for dsp in body["disputes"][:50]:
                inc = by_id.get(str(dsp.get("id", "")))
                if inc:  # you may only dispute incidents about your own characters
                    self.store.add_dispute(uploader, inc, str(dsp.get("reason", "")), now)
                    disputed += 1
        return {"stored": stored, "received": len(reports), "disputes": disputed}

    def _corroborations(self, uploader, presence_cache, need):
        """How many of this uploader's shared reports were matched by another
        uploader with mutual presence. Stops counting at `need`."""
        p = self.params
        pu = presence_cache.setdefault(uploader, self.store.presence_of(uploader))
        seen, n = set(), 0
        for r in self.store.shared_reports_by(uploader, aggregate.SHARED):
            for other in self.store.matching_reports(r, p["net.matchWindowSeconds"], uploader):
                v = other["uploader"]
                pv = presence_cache.setdefault(v, self.store.presence_of(v))
                key = (r["s"], r["d"], r["k"], r["t"] // max(1, p["net.matchWindowSeconds"]))
                if key not in seen and aggregate.mutually_present(pu, r["witness"], pv, other["witness"], r["t"], p["net.presenceSlackSeconds"]):
                    seen.add(key)
                    n += 1
                    break
            if n >= need:
                break
        return n

    def _incidents(self, guids):
        reports = self.store.reports_about(guids)
        involved = {r["uploader"] for r in reports if r["x"] < 1}
        presence_cache, trusted = {}, set()
        now = self.now()
        for u in involved:
            created = self.store.uploader_created(u) or now
            age = (now - created) / 86400.0
            need = self.params["net.minCorroborated"]
            if age >= self.params["net.minUploaderAgeDays"] and aggregate.standing(age, self._corroborations(u, presence_cache, need), self.params):
                trusted.add(u)
        for u in involved:
            presence_cache.setdefault(u, self.store.presence_of(u))
        return aggregate.build_incidents(
            reports, params=self.params,
            disputes=self.store.disputes_about(guids),
            opted_out=self.store.optouts(),
            self_claims=self.store.self_claims(),
            presence=presence_cache, trusted=trusted,
            identity=self.store.identity_map(), owned=self.store.owned_map(),
        )

    def players(self, guids):
        guids = [g for g in guids if GUID_RE.match(g)][:MAX_GUIDS]
        incs = self._incidents(guids)
        players = {}
        for g in guids:
            view = aggregate.public_view(incs.get(g, []))
            if view:
                players[g] = {"incidents": view}
        return {"protocol": aggregate.PROTOCOL_VERSION, "generatedAt": self.now(), "players": players}

    def _own_guids(self, uploader):
        """Characters this uploader may act for (self view, disputes, deletion).
        A character verified through Battle.net belongs only to that account;
        otherwise self-declared claims count unless contested."""
        acct = self.store.identity_map().get(uploader)
        contested = self._contested()
        out = set()
        for g in self.store.claimed_by(uploader):
            owner = self.store.owner_of(g)
            if owner:
                if owner == acct:
                    out.add(g)
            elif g not in contested:
                out.add(g)
        if acct:
            out |= self.store.owned_map().get(acct, set())
        return out

    def self_events(self, body):
        uploader = self._uploader(body)
        own = self._own_guids(uploader)
        incs = self._incidents(sorted(own))
        events = []
        for g in own:
            events.extend(aggregate.self_view(incs.get(g, [])))
        events.sort(key=lambda e: -e["t"])
        return {"events": events}

    def check_admin(self, token):
        if not self.admin_token or token != self.admin_token:
            raise PermissionError("admin token required")


STATIC_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "static", "admindash")
STATIC_FILES = {"": ("index.html", "text/html; charset=utf-8"), "index.html": ("index.html", "text/html; charset=utf-8"),
                "app.js": ("app.js", "text/javascript; charset=utf-8"), "app.css": ("app.css", "text/css; charset=utf-8"),
                "logo.png": ("logo.png", "image/png")}
ADMIN_HEADERS = {
    "Content-Security-Policy": "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; "
                               "connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'",
    "X-Frame-Options": "DENY", "X-Content-Type-Options": "nosniff", "Referrer-Policy": "no-referrer",
    "Cache-Control": "no-store", "Permissions-Policy": "camera=(), microphone=(), geolocation=()",
}


def make_handler(service, admin=None):
    buckets = {}
    lock = threading.Lock()

    class Handler(BaseHTTPRequestHandler):
        server_version = "TrustAdvisorNet/1"

        def log_message(self, fmt, *args):
            sys.stderr.write("%s %s\n" % (self.address_string(), fmt % args))

        def _limited(self):
            ip = self.headers.get("X-Forwarded-For", self.client_address[0]).split(",")[0].strip()
            now = time.time()
            with lock:
                b = buckets.get(ip)
                if not b or now - b[0] > 60:
                    b = [now, 0]
                    buckets[ip] = b
                b[1] += 1
                return b[1] > RATE_PER_MIN

        def _send(self, code, obj, headers=None):
            data = json.dumps(obj).encode("utf-8")
            self.send_response(code)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(data)))
            for k, v in (headers or {}).items():
                self.send_header(k, v)
            self.end_headers()
            self.wfile.write(data)

        # ---------------------------------------------------------------- admin cockpit
        def _client_ip(self):
            return self.headers.get("X-Forwarded-For", self.client_address[0]).split(",")[0].strip()

        def _cookie(self):
            c = SimpleCookie(self.headers.get("Cookie") or "")
            return c[admin_mod.COOKIE].value if admin_mod.COOKIE in c else None

        def _session_cookie(self, token, max_age):
            return "%s=%s; Path=/admindash; HttpOnly; Secure; SameSite=Strict; Max-Age=%d" % (admin_mod.COOKIE, token, max_age)

        def _admin(self, method, path):
            if admin is None:
                return self._send(404, {"error": "not found"})
            sub = path[len("/admindash"):].lstrip("/")
            if not sub.startswith("api/"):
                if method != "GET" or sub not in STATIC_FILES:
                    return self._send(404, {"error": "not found"}, ADMIN_HEADERS)
                name, ctype = STATIC_FILES[sub]
                with open(os.path.join(STATIC_DIR, name), "rb") as f:
                    data = f.read()
                self.send_response(200)
                self.send_header("Content-Type", ctype)
                self.send_header("Content-Length", str(len(data)))
                for k, v in ADMIN_HEADERS.items():
                    self.send_header(k, v)
                self.end_headers()
                self.wfile.write(data)
                return
            api = sub[len("api/"):]
            if method == "POST" and self.headers.get("Origin") != admin.origin:
                return self._send(403, {"error": "bad origin"}, ADMIN_HEADERS)
            ip = self._client_ip()
            try:
                # public (pre-login) steps
                if method == "POST" and api == "setup/begin":
                    return self._send(200, admin.setup_begin(self._body()), ADMIN_HEADERS)
                if method == "POST" and api == "setup/finish":
                    return self._send(200, admin.setup_finish(self._body()), ADMIN_HEADERS)
                if method == "POST" and api == "setup/totp":
                    return self._send(200, admin.setup_totp(self._body()), ADMIN_HEADERS)
                if method == "POST" and api == "login/begin":
                    return self._send(200, admin.login_begin(ip), ADMIN_HEADERS)
                if method == "POST" and api == "login/passkey":
                    return self._send(200, admin.login_passkey(self._body(), ip), ADMIN_HEADERS)
                if method == "POST" and api == "login/code":
                    token = admin.login_code(self._body(), ip)
                    h = dict(ADMIN_HEADERS)
                    h["Set-Cookie"] = self._session_cookie(token, admin_mod.SESSION_TTL)
                    return self._send(200, {"ok": True}, h)
                if method == "GET" and api == "status":
                    return self._send(200, {"enrolled": admin.enrolled(), "session": admin.session_ok(self._cookie())}, ADMIN_HEADERS)
                # everything below needs a session
                token = self._cookie()
                if not admin.session_ok(token):
                    return self._send(401, {"error": "login required"}, ADMIN_HEADERS)
                if method == "POST" and api == "logout":
                    admin.logout(token)
                    h = dict(ADMIN_HEADERS)
                    h["Set-Cookie"] = self._session_cookie("", 0)
                    return self._send(200, {"ok": True}, h)
                if method == "GET" and api == "overview":
                    return self._send(200, admin.overview(), ADMIN_HEADERS)
                if method == "GET" and api == "feedback":
                    st = parse_qs(urlparse(self.path).query).get("status", [None])[0]
                    return self._send(200, {"feedback": service.store.list_feedback(st or None, 500)}, ADMIN_HEADERS)
                if method == "POST" and api.startswith("feedback/"):
                    body = self._body()
                    if body.get("status") not in FEEDBACK_STATUSES:
                        raise BadRequest("status must be one of " + ", ".join(FEEDBACK_STATUSES))
                    reply = body.get("reply")
                    n = service.store.update_feedback(api.split("/", 1)[1], body["status"],
                                                      str(reply)[:500] if reply else None, service.now())
                    return self._send(200, {"updated": n}, ADMIN_HEADERS)
                if method == "GET" and api == "disputes":
                    return self._send(200, {"disputes": admin.disputes()}, ADMIN_HEADERS)
                if method == "POST" and api.startswith("disputes/"):
                    status = self._body().get("status")
                    if status not in ("upheld", "rejected"):
                        raise BadRequest("status must be upheld or rejected")
                    return self._send(200, {"updated": service.store.review_dispute(api.split("/", 1)[1], status)}, ADMIN_HEADERS)
                return self._send(404, {"error": "not found"}, ADMIN_HEADERS)
            except admin_mod.AuthError as e:
                return self._send(e.status, {"error": str(e)}, ADMIN_HEADERS)

        def _send_html(self, code, title, message):
            page = ("<!doctype html><html><head><meta charset='utf-8'><title>Trust Advisor - %s</title>"
                    "<style>body{font-family:system-ui,sans-serif;background:#0f1a30;color:#eee;display:flex;"
                    "align-items:center;justify-content:center;height:100vh;margin:0}main{max-width:520px;padding:32px;"
                    "background:#16294d;border:2px solid #e8b94a;border-radius:16px}h1{color:#e8b94a}</style></head>"
                    "<body><main><h1>%s</h1><p>%s</p></main></body></html>") % (html.escape(title), html.escape(title), html.escape(message))
            data = page.encode("utf-8")
            self.send_response(code)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(data)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(data)

        def _body(self):
            n = int(self.headers.get("Content-Length") or 0)
            if n <= 0 or n > MAX_BODY:
                raise BadRequest("body size")
            try:
                return json.loads(self.rfile.read(n).decode("utf-8"))
            except ValueError:
                raise BadRequest("invalid JSON")

        def _dispatch(self, method):
            if self._limited():
                return self._send(429, {"error": "rate limited"})
            url = urlparse(self.path)
            try:
                if url.path == "/admindash" or url.path.startswith("/admindash/"):
                    return self._admin(method, url.path)
                if method == "GET" and url.path == "/healthz":
                    return self._send(200, {"ok": True})
                if method == "GET" and url.path == "/v1/protocol":
                    return self._send(200, service.protocol())
                if method == "GET" and url.path == "/v1/players":
                    guids = parse_qs(url.query).get("guids", [""])[0].split(",")
                    return self._send(200, service.players(guids))
                if method == "POST" and url.path == "/v1/upload":
                    return self._send(200, service.upload(self._body()))
                if method == "POST" and url.path == "/v1/self":
                    return self._send(200, service.self_events(self._body()))
                if method == "POST" and url.path == "/v1/auth/begin":
                    return self._send(200, service.auth_begin(self._body(), self.headers.get("Host")))
                if method == "POST" and url.path == "/v1/auth/status":
                    return self._send(200, service.auth_status(self._body()))
                if method == "GET" and url.path == "/v1/auth/callback":
                    q = {k: v[0] for k, v in parse_qs(url.query).items()}
                    return self._send_html(*service.auth_callback(q))
                if method == "POST" and url.path == "/v1/feedback":
                    return self._send(200, service.feedback(self._body()))
                if url.path.startswith("/v1/admin/feedback"):
                    service.check_admin(self.headers.get("X-Admin-Token"))
                    if method == "GET":
                        st = parse_qs(url.query).get("status", [None])[0]
                        return self._send(200, {"feedback": service.store.list_feedback(st)})
                    fid = url.path.rsplit("/", 1)[-1]
                    body = self._body()
                    if body.get("status") not in FEEDBACK_STATUSES:
                        raise BadRequest("status must be one of " + ", ".join(FEEDBACK_STATUSES))
                    reply = body.get("reply")
                    return self._send(200, {"updated": service.store.update_feedback(
                        fid, body["status"], str(reply)[:500] if reply else None, service.now())})
                if url.path.startswith("/v1/admin/disputes"):
                    service.check_admin(self.headers.get("X-Admin-Token"))
                    if method == "GET":
                        return self._send(200, {"disputes": service.store.open_disputes()})
                    did = url.path.rsplit("/", 1)[-1]
                    status = self._body().get("status")
                    if status not in ("upheld", "rejected"):
                        raise BadRequest("status must be upheld or rejected")
                    return self._send(200, {"updated": service.store.review_dispute(did, status)})
                return self._send(404, {"error": "not found"})
            except BadRequest as e:
                return self._send(400, {"error": str(e)})
            except PermissionError as e:
                return self._send(403, {"error": str(e)})

        def do_GET(self):
            self._dispatch("GET")

        def do_POST(self):
            self._dispatch("POST")

    return Handler


def main():
    store = Store(os.environ.get("TA_DB", "trustnet.sqlite3"))
    cid, csec = os.environ.get("TA_BNET_CLIENT_ID"), os.environ.get("TA_BNET_CLIENT_SECRET")
    service = Service(store, admin_token=os.environ.get("TA_ADMIN_TOKEN"),
                      bnet=bnet_mod.BattleNet(cid, csec) if cid and csec else None,
                      public_urls=(os.environ.get("TA_PUBLIC_URLS") or "").split(","),
                      hash_salt=os.environ.get("TA_HASH_SALT", ""))
    print("Battle.net login: %s" % ("enabled" if service.bnet else "NOT configured"))
    origin = os.environ.get("TA_ADMIN_ORIGIN", "https://trustadvisor.gameplaybr.com.br").rstrip("/")
    admin = admin_mod.Admin(store, service, rp_id=urlparse(origin).hostname, origin=origin)
    port = int(os.environ.get("TA_PORT", "8080"))
    server = ThreadingHTTPServer(("0.0.0.0", port), make_handler(service, admin))
    print("Trust Advisor network listening on :%d" % port)
    server.serve_forever()


if __name__ == "__main__":
    main()
