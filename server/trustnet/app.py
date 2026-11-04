"""Trust Advisor network HTTP API (stdlib only). Run behind a TLS reverse proxy.

  GET  /healthz
  GET  /v1/protocol                       published locked parameters
  POST /v1/upload                         companion upload (reports, disputes, deletion)
  GET  /v1/players?guids=a,b,c            verified, undisputed incidents (public view)
  POST /v1/self                           every incident about your own characters
  GET  /v1/admin/disputes                 X-Admin-Token
  POST /v1/admin/disputes/<id>            X-Admin-Token, {"status": "upheld"|"rejected"}

Env: TA_DB (sqlite path), TA_ADMIN_TOKEN, TA_PORT (default 8080).
"""
import json
import os
import re
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

from . import aggregate
from .store import Store, hash_id

GUID_RE = re.compile(r"^Player-\d+-[0-9A-Fa-f]+$")
UPLOADER_RE = re.compile(r"^[0-9a-f]{32}$")
MAX_BODY = 4 * 1024 * 1024
MAX_REPORTS = 20000
MAX_GUIDS = 500
RATE_PER_MIN = 60
YEAR = 400 * 86400


class BadRequest(Exception):
    pass


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


class Service:
    """Transport-independent API logic (tested directly)."""

    def __init__(self, store, admin_token=None, clock=time.time):
        self.store = store
        self.admin_token = admin_token
        self.clock = clock

    def now(self):
        return int(self.clock())

    def protocol(self):
        return {"protocol": aggregate.PROTOCOL_VERSION, "params": aggregate.PARAMS,
                "eligible": sorted(aggregate.ELIGIBLE)}

    def _uploader(self, body):
        uid = body.get("uploaderId")
        if not (isinstance(uid, str) and UPLOADER_RE.match(uid)):
            raise BadRequest("bad uploaderId")
        return hash_id(uid)

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
            contested = self._contested()
            guids = self.store.delete_uploader(uploader, now, skip=contested)
            return {"deleted": True, "hidden": [g for g in guids if g not in contested]}
        witness = body.get("witness")
        if not (isinstance(witness, str) and GUID_RE.match(witness)):
            raise BadRequest("bad witness guid")
        wguild = str(body.get("witnessGuild") or "")[:64]
        chars = []
        for ch in (body.get("characters") or [])[:50]:
            if isinstance(ch, dict) and isinstance(ch.get("guid"), str) and GUID_RE.match(ch["guid"]):
                chars.append({"guid": ch["guid"], "name": str(ch.get("name", ""))[:64], "guild": str(ch.get("guild", ""))[:64]})
        if witness not in {c["guid"] for c in chars}:
            chars.append({"guid": witness, "name": "", "guild": wguild})
        raw = body.get("reports") or []
        if len(raw) > MAX_REPORTS:
            raise BadRequest("too many reports")
        reports = [validate_report(r, now) for r in raw]
        stored = self.store.upload(uploader, witness, wguild, chars, reports, now)

        disputed = 0
        own = self.store.claimed_by(uploader) - self._contested()
        if body.get("disputes"):
            incs = self._incidents(list(own))
            by_id = {i["id"]: i for lst in incs.values() for i in lst}
            for dsp in body["disputes"][:50]:
                inc = by_id.get(str(dsp.get("id", "")))
                if inc:  # you may only dispute incidents about your own characters
                    self.store.add_dispute(uploader, inc, str(dsp.get("reason", "")), now)
                    disputed += 1
        return {"stored": stored, "received": len(reports), "disputes": disputed}

    def _incidents(self, guids):
        return aggregate.build_incidents(
            self.store.reports_about(guids),
            disputes=self.store.disputes_about(guids),
            opted_out=self.store.optouts(),
            self_claims=self.store.self_claims(),
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

    def self_events(self, body):
        uploader = self._uploader(body)
        own = self.store.claimed_by(uploader) - self._contested()
        incs = self._incidents(sorted(own))
        events = []
        for g in own:
            events.extend(aggregate.self_view(incs.get(g, [])))
        events.sort(key=lambda e: -e["t"])
        return {"events": events}

    def check_admin(self, token):
        if not self.admin_token or token != self.admin_token:
            raise PermissionError("admin token required")


def make_handler(service):
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

        def _send(self, code, obj):
            data = json.dumps(obj).encode("utf-8")
            self.send_response(code)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(data)))
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
    service = Service(store, admin_token=os.environ.get("TA_ADMIN_TOKEN"))
    port = int(os.environ.get("TA_PORT", "8080"))
    server = ThreadingHTTPServer(("0.0.0.0", port), make_handler(service))
    print("Trust Advisor network listening on :%d" % port)
    server.serve_forever()


if __name__ == "__main__":
    main()
