"""Trust Advisor server, protocol v2 (GDD v2). Python stdlib + `cryptography` (passkeys).

Public API (companion app)
  POST /v1/sync                 layers the player consented to; returns public profiles + suggestions
  POST /v1/feedback             in-game feedback, returns status/replies
  PUT/GET/DELETE /v1/backup/<id> opaque end-to-end encrypted backups (write token required)
  POST /v1/auth/begin|status, GET /v1/auth/callback   Battle.net link (character ownership)
Public pages
  /privacy                      privacy policy
  /me                           self-service with Battle.net: see, download, delete, opt out
Admin
  /admindash                    cockpit (passkey + TOTP), aggregates only

Env: TA_DB, TA_PORT, TA_ADMIN_TOKEN, TA_HASH_SALT (also the GUID pseudonymization key),
     TA_BNET_CLIENT_ID, TA_BNET_CLIENT_SECRET, TA_PUBLIC_URLS, TA_ADMIN_ORIGIN.
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

from . import admin as admin_mod, bnet as bnet_mod
from .store import Pseudo, Store, hash_id

PROTOCOL = 2
GUID_RE = re.compile(r"^Player-\d+-[0-9A-Fa-f]+$")
UPLOADER_RE = re.compile(r"^[0-9a-f]{32}$")
BACKUP_ID_RE = re.compile(r"^[0-9a-f]{64}$")
FEEDBACK_ID_RE = re.compile(r"^[A-Za-z0-9-]{8,64}$")
FEEDBACK_STATUSES = ("received", "planned", "fixed", "done", "wontfix", "duplicate")
FEEDBACK_PER_DAY = 20
MAX_BODY = 4 * 1024 * 1024
MAX_BACKUP = 25 * 1024 * 1024
MAX_SESSIONS = 2000
MAX_MEMBERS = 40
MAX_LOOKUPS = 2000
LOOKUPS_PER_DAY = 5000
RATE_PER_MIN = 120
YEAR = 400 * 86400
ME_TTL = 1800

PROFILE_LABELS = {
    "hours": "Hours played in groups", "people": "Different people played with", "dungeons": "Dungeons completed",
    "raids": "Raids completed", "kills": "Kills in groups", "quests": "Quests completed in groups",
    "help": "Times I helped other players", "crafts": "Crafts and enchants for others", "favorite": "Favorite dungeon",
}
OFFICIAL_LABELS = {"level": "Level", "achievementPoints": "Achievement points"}


class BadRequest(Exception):
    pass


def _word(v, n=24):
    """A short label (class/race/realm/place): letters, digits, space, ' : and - only."""
    if not isinstance(v, str):
        return None
    v = re.sub(r"[^\w '\-:]", "", v, flags=re.UNICODE)[:n].strip()
    return v or None


def _int(v, lo, hi):
    return v if isinstance(v, int) and not isinstance(v, bool) and lo <= v <= hi else None


class Service:
    """Transport-independent API logic (tested directly)."""

    def __init__(self, store, admin_token=None, clock=time.time, bnet=None, public_urls=(), hash_salt=""):
        self.store = store
        self.admin_token = admin_token
        self.clock = clock
        self.bnet = bnet
        self.public_urls = [u.rstrip("/") for u in public_urls if u]
        self.hash_salt = hash_salt
        self.pseudo = Pseudo(hash_salt)

    def now(self):
        return int(self.clock())

    def _uploader(self, body):
        uid = body.get("uploaderId")
        if not (isinstance(uid, str) and UPLOADER_RE.match(uid)):
            raise BadRequest("bad uploaderId")
        return hash_id(uid)

    def account_hash(self, account_id):
        return hashlib.sha256(("%s:%s" % (self.hash_salt, account_id)).encode("utf-8")).hexdigest()

    # ------------------------------------------------------------------ sync (layers)
    def sync(self, body):
        now = self.now()
        uploader = self._uploader(body)
        if body.get("protocol") != PROTOCOL:
            raise BadRequest("unsupported protocol version (update the companion app)")
        self.store.touch_uploader(uploader, now)
        me = body.get("me") if isinstance(body.get("me"), dict) else None
        me_h = self.pseudo(me["guid"]) if me and isinstance(me.get("guid"), str) and GUID_RE.match(me["guid"]) else None

        if body.get("deleteRequested"):
            self.store.forget_uploader(uploader)
            if me_h:
                self.store.forget_character(me_h, now)
            return {"deleted": True}

        c = body.get("consents") if isinstance(body.get("consents"), dict) else {}
        consents = {k: bool(c.get(k)) for k in ("backup", "profile", "community", "recommend")}
        link = self.store.link_of(uploader)
        opted_out = False
        if me_h and self.store.optedout(me_h):
            owner = self.store.owner_of(me_h)
            if link and owner and owner["account"] == link["account"] and any(consents.values()):
                self.store.lift_optout(me_h)   # the verified owner chose to participate again
            else:
                opted_out = True

        if me_h and not opted_out and any(consents.values()):
            self.store.upsert_participant(uploader, me_h, {
                "name": _word(me.get("name"), 48), "class": _word(me.get("class")), "race": _word(me.get("race")),
                "faction": me.get("faction") if me.get("faction") in ("Alliance", "Horde") else None,
                "level": _int(me.get("level"), 1, 100), "realm": _word(me.get("realm"), 48), "locale": _word(me.get("locale"), 8),
            }, consents, now)
        elif not any(consents.values()):
            self.store.forget_uploader(uploader)   # every layer off: nothing about this uploader is kept

        # public profile: only the player's own, only what they ticked
        if consents["profile"] and me_h and not opted_out:
            items = {}
            raw = body.get("profile") if isinstance(body.get("profile"), dict) else {}
            for k, v in raw.items():
                if k not in PROFILE_LABELS:
                    continue
                if isinstance(v, str):
                    items[k] = _word(v, 48)
                elif isinstance(v, (int, float)) and not isinstance(v, bool):
                    items[k] = v
            self.store.set_profile(me_h, uploader, json.dumps(items), now)
            self._refresh_official(me_h, link, now)
        else:
            self.store.drop_profile(uploader)

        # community: pseudonymize every identifier, skip opted-out players
        stored = 0
        if consents["community"] and not opted_out:
            optout = self.store.optout_set()
            for s in (body.get("community") or [])[:MAX_SESSIONS]:
                sess, members = self._validate_session(s, now, optout)
                if sess and self.store.add_session(uploader, sess, members, now):
                    stored += 1
        else:
            self.store.forget_sessions("uploader = ?", (uploader,))

        out = {"protocol": PROTOCOL, "optedOut": opted_out, "storedSessions": stored,
               "me": {"linked": bool(link), "verifiedCharacters": len(self.store.owned_by(link["account"])) if link else 0}}
        if (consents["profile"] or consents["community"]) and not opted_out:
            out["profiles"] = self._lookups(uploader, body.get("lookups") or [], now)
        if consents["community"] and not opted_out:
            out["suggestions"] = self.suggestions(uploader, me_h)
        return out

    def _validate_session(self, s, now, optout):
        if not isinstance(s, dict):
            return None, None
        a, b = _int(s.get("a"), now - YEAR, now + 86400), _int(s.get("b"), now - YEAR, now + 86400)
        if a is None or b is None or not (a < b <= a + 86400):
            return None, None
        members = []
        for m in (s.get("m") or [])[:MAX_MEMBERS]:
            if not (isinstance(m, dict) and isinstance(m.get("g"), str) and GUID_RE.match(m["g"])):
                continue
            h = self.pseudo(m["g"])
            if h in optout:
                continue   # permanent exclusion list: discarded at ingest
            members.append({"h": h, "class": _word(m.get("class")), "race": _word(m.get("race")),
                            "faction": m.get("faction") if m.get("faction") in ("Alliance", "Horde") else None,
                            "level": _int(m.get("level"), 1, 100), "j": _int(m.get("j"), a - 86400, b + 86400) or a,
                            "l": _int(m.get("l"), a - 86400, b + 86400) or b})
        if len(members) < 2:
            return None, None
        gtype = s.get("type") if s.get("type") in ("quest", "dungeon", "raid") else "quest"
        return {"a": a, "b": b, "type": gtype, "place": _word(s.get("place"), 48), "kills": _int(s.get("kills"), 0, 500) or 0}, members

    def _lookups(self, uploader, guids, now):
        guids = [g for g in guids if isinstance(g, str) and GUID_RE.match(g)][:MAX_LOOKUPS]
        if not guids:
            return {}
        if self.store.count_lookups(uploader, now // 86400, len(guids)) > LOOKUPS_PER_DAY:
            return {}   # daily quota: bulk collection is slow and attributable
        by_hash = {self.pseudo(g): g for g in guids}
        out = {}
        for h, (items_json, official_json) in self.store.profiles_for(by_hash.keys()).items():
            items = [{"key": k, "label": PROFILE_LABELS.get(k, k), "value": v, "official": False}
                     for k, v in json.loads(items_json or "{}").items()]
            items += [{"key": k, "label": OFFICIAL_LABELS.get(k, k), "value": v, "official": True}
                      for k, v in json.loads(official_json or "{}").items()]
            if items:
                out[by_hash[h]] = {"items": items}
        return out

    def _refresh_official(self, me_h, link, now):
        if not (self.bnet and link):
            return
        owner = self.store.owner_of(me_h)
        if not owner or owner["account"] != link["account"]:
            return   # only characters proven to belong to this Battle.net account
        row = self.store.profile_row(me_h)
        if row and row.get("official_at") and now - row["official_at"] < 86400:
            return
        data = self.bnet.official_profile(owner["region"], owner["realm_slug"], owner["name"], now)
        self.store.set_official(me_h, json.dumps(data or {}), now)

    # ------------------------------------------------------------------ recommendations
    def _co_players(self, uploader):
        return {r[0] for r in self.store.q("SELECT DISTINCT cm.member_h FROM community_members cm JOIN community_sessions cs "
                                           "ON cs.id = cm.session_id WHERE cs.uploader = ?", (uploader,))}

    def suggestions(self, uploader, me_h, limit=8):
        q = self.store.q
        mine = q("SELECT faction, realm, level FROM participants WHERE uploader = ?", (uploader,), one=True)
        known = self._co_players(uploader)
        optout = self.store.optout_set()
        cands = q("SELECT uploader, guid_h, name, class, level, realm, faction FROM participants "
                  "WHERE c_recommend = 1 AND name IS NOT NULL AND uploader != ? AND updated_at >= ?", (uploader, self.now() - 30 * 86400))
        out = []
        for c in cands:
            if c["guid_h"] in optout or c["guid_h"] == me_h or c["guid_h"] in known:
                continue   # already in your circle, or excluded
            shared = len((self._co_players(c["uploader"]) & known) - {me_h})
            score, why = 3 * shared, []
            if shared:
                why.append("played with %d %s you know" % (shared, "person" if shared == 1 else "people"))
            if mine:
                if mine["realm"] and c["realm"] == mine["realm"]:
                    score += 2
                    why.append("same realm")
                if mine["faction"] and c["faction"] == mine["faction"]:
                    score += 2
                if mine["level"] and c["level"] and abs(mine["level"] - c["level"]) <= 5:
                    score += 1
                    why.append("similar level")
            if score > 2:
                out.append({"name": c["name"], "class": c["class"], "level": c["level"], "realm": c["realm"],
                            "reason": ", ".join(why) or "plays like you", "score": score})
        out.sort(key=lambda s: -s["score"])
        for s in out:
            s.pop("score")
        return out[:limit]

    # ------------------------------------------------------------------ feedback
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
                break
            accepted += self.store.add_feedback(install, {
                "id": fid, "kind": kind, "text": str(it.get("text") or "")[:1000],
                "version": str(it.get("version") or "")[:20], "diag": diag_json, "t": int(it.get("t") or now)}, now)
        return {"accepted": accepted, "statuses": self.store.feedback_statuses(install)}

    # ------------------------------------------------------------------ backups
    def backup_put(self, bid, token, data):
        if not BACKUP_ID_RE.match(bid or "") or not (isinstance(token, str) and 32 <= len(token) <= 128):
            raise BadRequest("bad backup id or token")
        if not data or len(data) > MAX_BACKUP:
            raise BadRequest("backup must be 1 byte to 25 MB")
        if not self.store.put_backup(bid, hashlib.sha256(token.encode()).hexdigest(), data, self.now()):
            raise PermissionError("wrong write token for this backup")
        return {"stored": len(data), "at": self.now()}

    def backup_get(self, bid):
        if not BACKUP_ID_RE.match(bid or ""):
            raise BadRequest("bad backup id")
        return self.store.get_backup(bid)

    def backup_delete(self, bid, token):
        if not BACKUP_ID_RE.match(bid or "") or not isinstance(token, str):
            raise BadRequest("bad backup id or token")
        return {"deleted": self.store.delete_backup(bid, hashlib.sha256(token.encode()).hexdigest())}

    # ------------------------------------------------------------------ Battle.net (link + self-service)
    def _base(self, host):
        base = self.public_urls[0] if self.public_urls else ""
        for u in self.public_urls:
            if host and u.split("://", 1)[-1] == host:
                base = u
        return base

    def auth_begin(self, body, host=None):
        if not self.bnet or not self.public_urls:
            raise BadRequest("Battle.net login is not configured on this server")
        uploader = self._uploader(body)
        region = str(body.get("region") or "us").lower()
        if region not in bnet_mod.REGIONS:
            raise BadRequest("region must be one of us, eu, kr, tw")
        redirect = self._base(host) + "/v1/auth/callback"
        state = secrets.token_urlsafe(24)
        self.store.create_state(state, uploader, redirect, region, self.now(), "link")
        return {"url": self.bnet.authorize_url(redirect, state), "expiresIn": 900}

    def me_login(self, region, host=None):
        if not self.bnet or not self.public_urls:
            raise BadRequest("Battle.net login is not configured on this server")
        region = (region or "us").lower()
        if region not in bnet_mod.REGIONS:
            raise BadRequest("region must be one of us, eu, kr, tw")
        redirect = self._base(host) + "/v1/auth/callback"
        state = secrets.token_urlsafe(24)
        self.store.create_state(state, None, redirect, region, self.now(), "me")
        return self.bnet.authorize_url(redirect, state)

    def auth_callback(self, query):
        """Returns (status, title, message, me_token_or_None)."""
        if query.get("error"):
            return 400, "Login cancelled", "Battle.net login was cancelled. You can close this window.", None
        st = self.store.pop_state(query.get("state", ""), self.now())
        if not st or not query.get("code"):
            return 400, "Link expired", "This login link expired or was already used. Please start again.", None
        try:
            token = self.bnet.exchange(query["code"], st["redirect"])
            account = self.account_hash(self.bnet.account_id(token))
            chars = [{"h": self.pseudo(c["guid"]), "name": c.get("name"), "realm_slug": c.get("realm_slug")}
                     for c in self.bnet.forever_characters(token, st["region"]) if GUID_RE.match(c.get("guid", ""))]
        except Exception:
            return 502, "Battle.net error", "Battle.net did not answer correctly. Please try again in a few minutes.", None
        self.store.link(st["uploader"], account, st["region"], chars, self.now())
        if st["kind"] == "me":
            tok = secrets.token_urlsafe(32)
            self.store.q("INSERT INTO me_sessions (token_hash, account, region, expires_at) VALUES (?, ?, ?, ?)",
                         (hashlib.sha256(tok.encode()).hexdigest(), account, st["region"], self.now() + ME_TTL), commit=True)
            return 200, "Signed in", "", tok
        msg = ("%d WoW: Forever character(s) verified." % len(chars)) if chars else \
            "No WoW: Forever characters were listed by Battle.net yet; your account is linked and characters will be verified when available."
        return 200, "Linked", "Your Trust Advisor identity is now linked to your Battle.net account. " + msg + \
            " Only a one-way code of your account id is stored. You can close this window.", None

    def auth_status(self, body):
        uploader = self._uploader(body)
        link = self.store.link_of(uploader)
        if not link:
            return {"linked": False}
        return {"linked": True, "region": link["region"], "linkedAt": link["linked_at"],
                "characters": len(self.store.owned_by(link["account"]))}

    def _me_account(self, token):
        if not token:
            return None
        r = self.store.q("SELECT account, expires_at FROM me_sessions WHERE token_hash = ?",
                         (hashlib.sha256(token.encode()).hexdigest(),), one=True)
        return r[0] if r and r[1] > self.now() else None

    def me_data(self, token):
        account = self._me_account(token)
        if not account:
            raise PermissionError("please sign in with Battle.net")
        q = self.store.q
        chars = []
        for c in self.store.owned_by(account):
            h = c["guid_h"]
            prof = self.store.profile_row(h)
            part = q("SELECT c_backup, c_profile, c_community, c_recommend, updated_at FROM participants WHERE guid_h = ?", (h,), one=True)
            chars.append({
                "name": c["name"], "realm": c["realm_slug"], "optedOut": self.store.optedout(h),
                "participant": dict(part) if part else None,
                "publicProfile": json.loads(prof["items"]) if prof and prof.get("items") else None,
                "officialProfile": json.loads(prof["official"]) if prof and prof.get("official") else None,
                "seenInCommunitySessions": q("SELECT count(*) FROM community_members WHERE member_h = ?", (h,), one=True)[0],
            })
        ups = self.store.uploaders_of(account)
        shared = sum(q("SELECT count(*) FROM community_sessions WHERE uploader = ?", (u,), one=True)[0] for u in ups)
        return {"characters": chars, "linkedInstalls": len(ups), "sessionsYouShared": shared,
                "note": "Character identifiers are stored only as keyed codes. This is everything linked to your Battle.net account."}

    def me_delete(self, token):
        account = self._me_account(token)
        if not account:
            raise PermissionError("please sign in with Battle.net")
        hashes = [c["guid_h"] for c in self.store.owned_by(account)]
        for h in hashes:
            self.store.forget_character(h, self.now())   # deleted + permanently excluded
        self.store.forget_account(account)
        return {"deleted": True, "excludedCharacters": len(hashes)}


# ---------------------------------------------------------------------- HTTP
STATIC_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "static")
ADMIN_FILES = {"": "index.html", "index.html": "index.html", "app.js": "app.js", "app.css": "app.css", "logo.png": "logo.png"}
PUBLIC_FILES = {"/privacy": "privacy.html", "/me": "me.html", "/me/": "me.html", "/me/me.js": "me.js",
                "/public.css": "public.css", "/logo.png": "logo.png"}
CTYPES = {".html": "text/html; charset=utf-8", ".js": "text/javascript; charset=utf-8", ".css": "text/css; charset=utf-8", ".png": "image/png"}
SEC_HEADERS = {
    "Content-Security-Policy": "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; "
                               "connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'",
    "X-Frame-Options": "DENY", "X-Content-Type-Options": "nosniff", "Referrer-Policy": "no-referrer",
    "Cache-Control": "no-store", "Permissions-Policy": "camera=(), microphone=(), geolocation=()",
}
ADMIN_HEADERS = SEC_HEADERS


def make_handler(service, admin=None):
    buckets = {}
    lock = threading.Lock()

    class Handler(BaseHTTPRequestHandler):
        server_version = "TrustAdvisor/2"

        def log_message(self, fmt, *args):
            sys.stderr.write("%s %s\n" % (self.address_string(), fmt % args))

        def _client_ip(self):
            return self.headers.get("X-Forwarded-For", self.client_address[0]).split(",")[0].strip()

        def _limited(self):
            ip, now = self._client_ip(), time.time()
            with lock:
                b = buckets.get(ip)
                if not b or now - b[0] > 60:
                    b = [now, 0]
                    buckets[ip] = b
                b[1] += 1
                return b[1] > RATE_PER_MIN

        def _raw(self, code, data, ctype, headers=None):
            self.send_response(code)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(len(data)))
            for k, v in (headers or {}).items():
                self.send_header(k, v)
            self.end_headers()
            self.wfile.write(data)

        def _send(self, code, obj, headers=None):
            self._raw(code, json.dumps(obj).encode("utf-8"), "application/json", headers)

        def _redirect(self, url, headers=None):
            self.send_response(302)
            self.send_header("Location", url)
            self.send_header("Content-Length", "0")
            for k, v in (headers or {}).items():
                self.send_header(k, v)
            self.end_headers()

        def _file(self, rel):
            path = os.path.join(STATIC_DIR, rel)
            with open(path, "rb") as f:
                data = f.read()
            self._raw(200, data, CTYPES[os.path.splitext(path)[1]], SEC_HEADERS)

        def _send_html(self, code, title, message):
            page = ("<!doctype html><html><head><meta charset='utf-8'><meta name='viewport' content='width=device-width, initial-scale=1'>"
                    "<title>Trust Advisor - %s</title><link rel='stylesheet' href='/public.css'></head>"
                    "<body><main class='card'><h1>%s</h1><p>%s</p></main></body></html>") % (html.escape(title), html.escape(title), html.escape(message))
            self._raw(code, page.encode("utf-8"), "text/html; charset=utf-8", SEC_HEADERS)

        def _cookie(self, name):
            c = SimpleCookie(self.headers.get("Cookie") or "")
            return c[name].value if name in c else None

        def _body_bytes(self, limit):
            n = int(self.headers.get("Content-Length") or 0)
            if n <= 0 or n > limit:
                raise BadRequest("body size")
            return self.rfile.read(n)

        def _body(self):
            try:
                return json.loads(self._body_bytes(MAX_BODY).decode("utf-8"))
            except ValueError:
                raise BadRequest("invalid JSON")

        # ---------------------------------------------------------------- admin cockpit
        def _admin(self, method, path):
            if admin is None:
                return self._send(404, {"error": "not found"})
            sub = path[len("/admindash"):].lstrip("/")
            if not sub.startswith("api/"):
                if method != "GET" or sub not in ADMIN_FILES:
                    return self._send(404, {"error": "not found"}, SEC_HEADERS)
                return self._file(os.path.join("admindash", ADMIN_FILES[sub]))
            api = sub[len("api/"):]
            if method == "POST" and self.headers.get("Origin") != admin.origin:
                return self._send(403, {"error": "bad origin"}, SEC_HEADERS)
            ip = self._client_ip()
            try:
                if method == "POST" and api == "setup/begin":
                    return self._send(200, admin.setup_begin(self._body()), SEC_HEADERS)
                if method == "POST" and api == "setup/finish":
                    return self._send(200, admin.setup_finish(self._body()), SEC_HEADERS)
                if method == "POST" and api == "setup/totp":
                    return self._send(200, admin.setup_totp(self._body()), SEC_HEADERS)
                if method == "POST" and api == "login/begin":
                    return self._send(200, admin.login_begin(ip), SEC_HEADERS)
                if method == "POST" and api == "login/passkey":
                    return self._send(200, admin.login_passkey(self._body(), ip), SEC_HEADERS)
                if method == "POST" and api == "login/code":
                    token = admin.login_code(self._body(), ip)
                    h = dict(SEC_HEADERS)
                    h["Set-Cookie"] = "%s=%s; Path=/admindash; HttpOnly; Secure; SameSite=Strict; Max-Age=%d" % (
                        admin_mod.COOKIE, token, admin_mod.SESSION_TTL)
                    return self._send(200, {"ok": True}, h)
                if method == "GET" and api == "status":
                    return self._send(200, {"enrolled": admin.enrolled(), "session": admin.session_ok(self._cookie(admin_mod.COOKIE))}, SEC_HEADERS)
                token = self._cookie(admin_mod.COOKIE)
                if not admin.session_ok(token):
                    return self._send(401, {"error": "login required"}, SEC_HEADERS)
                if method == "POST" and api == "logout":
                    admin.logout(token)
                    h = dict(SEC_HEADERS)
                    h["Set-Cookie"] = "%s=; Path=/admindash; HttpOnly; Secure; SameSite=Strict; Max-Age=0" % admin_mod.COOKIE
                    return self._send(200, {"ok": True}, h)
                if method == "GET" and api == "overview":
                    return self._send(200, admin.overview(), SEC_HEADERS)
                if method == "GET" and api == "feedback":
                    st = parse_qs(urlparse(self.path).query).get("status", [None])[0]
                    return self._send(200, {"feedback": admin.feedback_list(st)}, SEC_HEADERS)
                if method == "POST" and api.startswith("feedback/"):
                    body = self._body()
                    if body.get("status") not in FEEDBACK_STATUSES:
                        raise BadRequest("status must be one of " + ", ".join(FEEDBACK_STATUSES))
                    reply = body.get("reply")
                    n = service.store.update_feedback(api.split("/", 1)[1], body["status"], str(reply)[:500] if reply else None, service.now())
                    return self._send(200, {"updated": n}, SEC_HEADERS)
                return self._send(404, {"error": "not found"}, SEC_HEADERS)
            except admin_mod.AuthError as e:
                return self._send(e.status, {"error": str(e)}, SEC_HEADERS)

        # ---------------------------------------------------------------- self-service /me
        def _me(self, method, url):
            if url.path == "/me/login":
                region = parse_qs(url.query).get("region", ["us"])[0]
                return self._redirect(service.me_login(region, self.headers.get("Host")))
            if url.path.startswith("/me/api/"):
                if method == "POST" and self.headers.get("Origin") not in service.public_urls:
                    return self._send(403, {"error": "bad origin"}, SEC_HEADERS)
                token = self._cookie("ta_me")
                if method == "GET" and url.path == "/me/api/data":
                    return self._send(200, service.me_data(token), SEC_HEADERS)
                if method == "POST" and url.path == "/me/api/delete":
                    return self._send(200, service.me_delete(token), SEC_HEADERS)
                if method == "POST" and url.path == "/me/api/logout":
                    h = dict(SEC_HEADERS)
                    h["Set-Cookie"] = "ta_me=; Path=/me; HttpOnly; Secure; SameSite=Lax; Max-Age=0"
                    return self._send(200, {"ok": True}, h)
                return self._send(404, {"error": "not found"}, SEC_HEADERS)
            if method == "GET" and url.path in PUBLIC_FILES:
                return self._file(os.path.join("public", PUBLIC_FILES[url.path]))
            return self._send(404, {"error": "not found"})

        # ---------------------------------------------------------------- dispatch
        def _dispatch(self, method):
            if self._limited():
                return self._send(429, {"error": "rate limited"})
            url = urlparse(self.path)
            try:
                if url.path == "/admindash" or url.path.startswith("/admindash/"):
                    return self._admin(method, url.path)
                if url.path == "/me" or url.path.startswith("/me/"):
                    return self._me(method, url)
                if method == "GET" and url.path in PUBLIC_FILES:
                    return self._file(os.path.join("public", PUBLIC_FILES[url.path]))
                if method == "GET" and url.path == "/healthz":
                    return self._send(200, {"ok": True})
                if method == "GET" and url.path == "/v1/protocol":
                    return self._send(200, {"protocol": PROTOCOL, "profileItems": PROFILE_LABELS})
                if method == "POST" and url.path == "/v1/sync":
                    return self._send(200, service.sync(self._body()))
                if method == "POST" and url.path == "/v1/feedback":
                    return self._send(200, service.feedback(self._body()))
                if url.path.startswith("/v1/backup/"):
                    bid = url.path.rsplit("/", 1)[-1]
                    if method == "PUT":
                        return self._send(200, service.backup_put(bid, self.headers.get("X-Write-Token"), self._body_bytes(MAX_BACKUP)))
                    if method == "GET":
                        data, at = service.backup_get(bid)
                        if data is None:
                            return self._send(404, {"error": "no backup"})
                        return self._raw(200, data, "application/octet-stream", {"X-Backup-At": str(at)})
                    if method == "DELETE":
                        return self._send(200, service.backup_delete(bid, self.headers.get("X-Write-Token")))
                if method == "POST" and url.path == "/v1/auth/begin":
                    return self._send(200, service.auth_begin(self._body(), self.headers.get("Host")))
                if method == "POST" and url.path == "/v1/auth/status":
                    return self._send(200, service.auth_status(self._body()))
                if method == "GET" and url.path == "/v1/auth/callback":
                    code, title, msg, me_token = service.auth_callback({k: v[0] for k, v in parse_qs(url.query).items()})
                    if me_token:
                        return self._redirect("/me", {"Set-Cookie": "ta_me=%s; Path=/me; HttpOnly; Secure; SameSite=Lax; Max-Age=%d" % (me_token, ME_TTL)})
                    return self._send_html(code, title, msg)
                return self._send(404, {"error": "not found"})
            except BadRequest as e:
                return self._send(400, {"error": str(e)})
            except PermissionError as e:
                return self._send(403, {"error": str(e)})

        def do_GET(self):
            self._dispatch("GET")

        def do_POST(self):
            self._dispatch("POST")

        def do_PUT(self):
            self._dispatch("PUT")

        def do_DELETE(self):
            self._dispatch("DELETE")

    return Handler


def main():
    store = Store(os.environ.get("TA_DB", "trustnet.sqlite3"))
    cid, csec = os.environ.get("TA_BNET_CLIENT_ID"), os.environ.get("TA_BNET_CLIENT_SECRET")
    service = Service(store, admin_token=os.environ.get("TA_ADMIN_TOKEN"),
                      bnet=bnet_mod.BattleNet(cid, csec) if cid and csec else None,
                      public_urls=(os.environ.get("TA_PUBLIC_URLS") or "").split(","),
                      hash_salt=os.environ.get("TA_HASH_SALT", ""))
    print("Battle.net login: %s" % ("enabled" if service.bnet else "NOT configured"), flush=True)
    origin = os.environ.get("TA_ADMIN_ORIGIN", "https://trustadvisor.gameplaybr.com.br").rstrip("/")
    admin = admin_mod.Admin(store, service, rp_id=urlparse(origin).hostname, origin=origin)

    def janitor():
        while True:
            try:
                store.cleanup(int(time.time()))
            except Exception as e:  # keep serving
                print("cleanup failed: %s" % e, flush=True)
            time.sleep(6 * 3600)
    threading.Thread(target=janitor, daemon=True).start()
    port = int(os.environ.get("TA_PORT", "8080"))
    server = ThreadingHTTPServer(("0.0.0.0", port), make_handler(service, admin))
    print("Trust Advisor listening on :%d" % port, flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
