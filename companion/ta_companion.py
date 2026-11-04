#!/usr/bin/env python3
"""Trust Advisor companion app (GDD Phase 3). Python 3.8+, standard library only.

WoW addons cannot use the internet, so this small program does it for them:
  1. reads TrustAdvisor.lua from SavedVariables (written on logout or /reload),
  2. if the player joined the network (consent.network), uploads their witness
     reports, disputes and deletion requests,
  3. downloads the network view for every player they know and writes
     Interface/AddOns/TrustAdvisor/Network/NetData.lua (loaded on the next /reload).

Usage:
  python3 ta_companion.py --server https://net.example.com           # watch mode
  python3 ta_companion.py --server https://net.example.com --once
  python3 ta_companion.py --wow "/Applications/World of Warcraft/_forever_" --server ...
"""
import argparse
import glob
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request

VERSION = "0.2.0"
PROTOCOL = 1
DEFAULT_WOW = [
    "/Applications/World of Warcraft/_forever_",
    r"C:\Program Files (x86)\World of Warcraft\_forever_",
    r"C:\Program Files\World of Warcraft\_forever_",
]
STATE_PATH = os.path.join(os.path.expanduser("~"), ".trustadvisor", "companion.json")


# ---------------------------------------------------------------------------
# SavedVariables (Lua table subset) parser
# ---------------------------------------------------------------------------
class LuaParseError(ValueError):
    pass


class _Lua:
    NUM = re.compile(r"-?(?:\d+\.?\d*(?:[eE][-+]?\d+)?|\.\d+(?:[eE][-+]?\d+)?|0[xX][0-9a-fA-F]+)")
    NAME = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")

    def __init__(self, text):
        self.s, self.i, self.n = text, 0, len(text)

    def ws(self):
        s, n = self.s, self.n
        while self.i < n:
            c = s[self.i]
            if c in " \t\r\n,;":
                self.i += 1
            elif s.startswith("--", self.i):
                if s.startswith("--[[", self.i):
                    j = s.find("]]", self.i)
                    self.i = n if j < 0 else j + 2
                else:
                    j = s.find("\n", self.i)
                    self.i = n if j < 0 else j + 1
            else:
                break

    def peek(self, tok):
        return self.s.startswith(tok, self.i)

    def string(self):
        q = self.s[self.i]
        self.i += 1
        out = []
        esc = {"n": "\n", "t": "\t", "r": "\r", "\\": "\\", '"': '"', "'": "'", "\n": "\n", "a": "\a", "b": "\b", "f": "\f", "v": "\v"}
        while self.i < self.n:
            c = self.s[self.i]
            if c == q:
                self.i += 1
                return "".join(out)
            if c == "\\":
                self.i += 1
                c = self.s[self.i]
                if c.isdigit():
                    m = re.match(r"\d{1,3}", self.s[self.i:])
                    out.append(chr(int(m.group(0))))
                    self.i += len(m.group(0))
                    continue
                out.append(esc.get(c, c))
                self.i += 1
                continue
            out.append(c)
            self.i += 1
        raise LuaParseError("unterminated string")

    def value(self):
        self.ws()
        if self.i >= self.n:
            raise LuaParseError("unexpected end")
        c = self.s[self.i]
        if c == "{":
            return self.table()
        if c in "\"'":
            # WoW writes Latin-1-safe bytes; strings were decoded as UTF-8 already
            return self.string()
        for word, val in (("true", True), ("false", False), ("nil", None)):
            if self.peek(word):
                self.i += len(word)
                return val
        m = self.NUM.match(self.s, self.i)
        if m:
            self.i = m.end()
            t = m.group(0)
            if t.lower().startswith(("0x", "-0x")):
                return int(t, 16)
            v = float(t)
            return int(v) if v.is_integer() and "." not in t and "e" not in t.lower() else v
        raise LuaParseError("unexpected %r at %d" % (c, self.i))

    def table(self):
        self.i += 1
        arr, obj = [], {}
        while True:
            self.ws()
            if self.peek("}"):
                self.i += 1
                break
            if self.peek("["):
                self.i += 1
                key = self.value()
                self.ws()
                if not self.peek("]"):
                    raise LuaParseError("expected ]")
                self.i += 1
                self.ws()
                if not self.peek("="):
                    raise LuaParseError("expected =")
                self.i += 1
                obj[key] = self.value()
            else:
                m = self.NAME.match(self.s, self.i)
                save = self.i
                if m and m.group(0) not in ("true", "false", "nil"):
                    self.i = m.end()
                    self.ws()
                    if self.peek("=") and not self.peek("=="):
                        self.i += 1
                        obj[m.group(0)] = self.value()
                        continue
                    self.i = save
                arr.append(self.value())
        if obj and arr:
            for k, v in enumerate(arr, 1):
                obj.setdefault(k, v)
            return obj
        if arr:
            return arr
        # integer-keyed dict that is really an array
        if obj and all(isinstance(k, int) for k in obj) and sorted(obj) == list(range(1, len(obj) + 1)):
            return [obj[k] for k in range(1, len(obj) + 1)]
        return obj


def parse_saved_variables(text):
    """Returns {GlobalName: value} for every `Name = value` assignment."""
    p = _Lua(text)
    out = {}
    while True:
        p.ws()
        if p.i >= p.n:
            return out
        m = _Lua.NAME.match(p.s, p.i)
        if not m:
            raise LuaParseError("expected a global name at %d" % p.i)
        p.i = m.end()
        p.ws()
        if not p.peek("="):
            raise LuaParseError("expected =")
        p.i += 1
        out[m.group(0)] = p.value()


def as_list(v):
    if v is None:
        return []
    if isinstance(v, list):
        return v
    if isinstance(v, dict):
        return [v[k] for k in sorted(k for k in v if isinstance(k, int))]
    return []


# ---------------------------------------------------------------------------
# NetData.lua writer
# ---------------------------------------------------------------------------
def lua_literal(v, indent=0):
    pad = "  " * indent
    if v is None:
        return "nil"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return repr(int(v)) if float(v).is_integer() else repr(float(v))
    if isinstance(v, str):
        return '"' + "".join(
            "\\\\" if ch == "\\" else '\\"' if ch == '"' else "\\n" if ch == "\n" else
            ("\\%d" % ord(ch)) if ord(ch) < 32 else ch for ch in v) + '"'
    if isinstance(v, list):
        if not v:
            return "{}"
        return "{\n" + "".join(pad + "  " + lua_literal(x, indent + 1) + ",\n" for x in v) + pad + "}"
    if isinstance(v, dict):
        if not v:
            return "{}"
        parts = []
        for k in sorted(v, key=str):
            key = ("[%d]" % k) if isinstance(k, int) else ("[" + lua_literal(str(k)) + "]")
            parts.append(pad + "  " + key + " = " + lua_literal(v[k], indent + 1) + ",\n")
        return "{\n" + "".join(parts) + pad + "}"
    raise TypeError("cannot serialize %r" % type(v))


def write_netdata(path, data):
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write("-- Written by the Trust Advisor companion app %s. Do not edit by hand.\n" % VERSION)
        f.write("TrustAdvisorNetData = " + lua_literal(data) + "\n")
    os.replace(tmp, path)


# ---------------------------------------------------------------------------
# HTTP
# ---------------------------------------------------------------------------
class Client:
    def __init__(self, server, timeout=20):
        self.server = server.rstrip("/")
        self.timeout = timeout

    def _req(self, method, path, body=None):
        data = json.dumps(body).encode("utf-8") if body is not None else None
        req = urllib.request.Request(self.server + path, data=data, method=method,
                                     headers={"Content-Type": "application/json", "User-Agent": "TrustAdvisorCompanion/" + VERSION})
        try:
            with urllib.request.urlopen(req, timeout=self.timeout) as r:
                return json.loads(r.read().decode("utf-8"))
        except urllib.error.HTTPError as e:
            raise RuntimeError("%s %s -> HTTP %d: %s" % (method, path, e.code, e.read().decode("utf-8", "replace")[:300]))

    def upload(self, body):
        return self._req("POST", "/v1/upload", body)

    def players(self, guids):
        out = {}
        for i in range(0, len(guids), 200):
            chunk = guids[i:i + 200]
            res = self._req("GET", "/v1/players?guids=" + ",".join(chunk))
            out.update(res.get("players", {}))
        return out

    def self_events(self, uploader_id):
        return self._req("POST", "/v1/self", {"uploaderId": uploader_id}).get("events", [])


# ---------------------------------------------------------------------------
# Sync
# ---------------------------------------------------------------------------
def load_state():
    try:
        with open(STATE_PATH, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def save_state(state):
    os.makedirs(os.path.dirname(STATE_PATH), exist_ok=True)
    with open(STATE_PATH, "w", encoding="utf-8") as f:
        json.dump(state, f, indent=1)


def find_saved_variables(wow):
    return sorted(glob.glob(os.path.join(wow, "WTF", "Account", "*", "SavedVariables", "TrustAdvisor.lua")))


def netdata_path(wow):
    return os.path.join(wow, "Interface", "AddOns", "TrustAdvisor", "Network", "NetData.lua")


def sync_file(sv_path, client, wow, state, log=print):
    with open(sv_path, encoding="utf-8", errors="replace") as f:
        sv = parse_saved_variables(f.read())
    db = sv.get("TrustAdvisorDB") or {}
    params = db.get("params") or {}
    net = db.get("net") or {}
    uploader = net.get("uploaderId")
    if not uploader:
        log("  %s: network never joined, skipping" % sv_path)
        return False
    st = state.setdefault(uploader[:8], {})

    # data rights first: a deletion request is honored even after leaving
    if net.get("deleteRequested") and st.get("deletedFor") != net["deleteRequested"]:
        res = client.upload({"uploaderId": uploader, "protocol": PROTOCOL, "deleteRequested": True})
        st["deletedFor"] = net["deleteRequested"]
        log("  deletion sent: %s" % res)
        write_netdata(netdata_path(wow), {"protocol": PROTOCOL, "generatedAt": 0, "players": {}})
        return True

    if params.get("consent.network") is not True:
        log("  %s: consent.network is off, nothing sent" % os.path.basename(os.path.dirname(os.path.dirname(sv_path))))
        return False

    outbox = net.get("outbox") or {}
    characters = [{"guid": g, "name": c.get("name", ""), "guild": c.get("guild", "")}
                  for g, c in (net.get("characters") or {}).items() if isinstance(c, dict)]
    sent_disputes = set(st.get("disputes", []))
    disputes = [{"id": d.get("id"), "reason": d.get("reason", "")} for d in as_list(net.get("disputes"))
                if isinstance(d, dict) and d.get("id") not in sent_disputes]
    if outbox.get("witness") and (outbox.get("builtAt") != st.get("builtAt") or disputes):
        body = {"uploaderId": uploader, "protocol": PROTOCOL, "witness": outbox["witness"],
                "witnessGuild": outbox.get("witnessGuild", ""), "characters": characters,
                "reports": [{k: r[k] for k in ("s", "d", "x", "m", "t", "k") if k in r} for r in as_list(outbox.get("reports"))],
                "disputes": disputes}
        res = client.upload(body)
        st["builtAt"] = outbox.get("builtAt")
        st["disputes"] = sorted(sent_disputes | {d["id"] for d in disputes})
        log("  uploaded: %s" % res)

    guids = [g for g in (db.get("players") or {}) if isinstance(g, str)]
    players = client.players(guids) if guids else {}
    me = {"events": client.self_events(uploader)}
    write_netdata(netdata_path(wow), {"protocol": PROTOCOL, "generatedAt": int(time.time()), "players": players, "me": me})
    log("  network view: %d players with network data, %d events about you -> %s" % (len(players), len(me["events"]), netdata_path(wow)))
    return True


def main(argv=None):
    ap = argparse.ArgumentParser(description="Trust Advisor companion app")
    ap.add_argument("--server", default=os.environ.get("TA_SERVER"), help="network server URL")
    ap.add_argument("--wow", help="WoW: Forever folder (contains WTF and Interface)")
    ap.add_argument("--once", action="store_true", help="sync once and exit")
    ap.add_argument("--interval", type=int, default=30, help="seconds between checks in watch mode")
    args = ap.parse_args(argv)
    if not args.server:
        ap.error("--server (or TA_SERVER) is required")
    wow = args.wow or next((p for p in DEFAULT_WOW if os.path.isdir(p)), None)
    if not wow:
        ap.error("WoW: Forever folder not found; pass --wow")
    client = Client(args.server)
    state = load_state()
    seen = {}
    print("Trust Advisor companion %s - %s - server %s" % (VERSION, wow, args.server))
    while True:
        for sv in find_saved_variables(wow):
            mtime = os.path.getmtime(sv)
            if seen.get(sv) == mtime:
                continue
            seen[sv] = mtime
            print("[%s] %s changed" % (time.strftime("%H:%M:%S"), sv))
            try:
                sync_file(sv, client, wow, state)
                save_state(state)
            except Exception as e:  # keep watching on network/parse errors
                print("  sync failed: %s" % e)
                seen.pop(sv, None)
        if args.once:
            return 0
        time.sleep(args.interval)


if __name__ == "__main__":
    sys.exit(main())
