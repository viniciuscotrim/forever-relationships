#!/usr/bin/env python3
"""Forever Relationships companion app. Python 3.8+ (`cryptography` for the encrypted backup).

WoW addons cannot use the internet, so this small program does it for them:
  1. reads ForeverRelationships.lua from SavedVariables (written on logout or /reload),
  2. sends only what the layers turned on in game allow (encrypted backup, public
     profile, community sessions, recommend me) plus feedback and deletion requests,
  3. writes profiles, suggestions and status to
     Interface/AddOns/ForeverRelationships/Cloud/NetData.lua (loaded on the next /reload).

Usage:
  python3 fr_companion.py --install       # start automatically with the computer (recommended)
  python3 fr_companion.py --uninstall     # stop starting automatically
  python3 fr_companion.py --link --region eu   # link Battle.net (needed for your negatives to count)
  python3 fr_companion.py                 # watch mode, official network
  python3 fr_companion.py --once          # one sync
  python3 fr_companion.py --server https://other.example.com   # another server
  python3 fr_companion.py --wow "/Applications/World of Warcraft/_forever_" --server ...
"""
import argparse
import base64
import glob
import gzip
import hashlib
import platform
import shutil
import subprocess
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request
import webbrowser

VERSION = "0.4.1"
PROTOCOL = 2
DEFAULT_WOW = [
    "/Applications/World of Warcraft/_forever_",
    r"C:\Program Files (x86)\World of Warcraft\_forever_",
    r"C:\Program Files\World of Warcraft\_forever_",
]
DEFAULT_SERVER = "https://forever.gameplaybr.com.br"
# Tried in order when no --server is given (the legacy address is kept during the DNS move).
FALLBACK_SERVERS = [DEFAULT_SERVER]
STATE_PATH = os.path.join(os.path.expanduser("~"), ".forever-relationships", "companion.json")


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
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write("-- Written by the Forever Relationships companion app %s. Do not edit by hand.\n" % VERSION)
        f.write("ForeverRelationshipsNetData = " + lua_literal(data) + "\n")
    os.replace(tmp, path)


# ---------------------------------------------------------------------------
# HTTP
# ---------------------------------------------------------------------------
class Client:
    def __init__(self, server, timeout=20, fallbacks=()):
        self.servers = [server.rstrip("/")] + [f.rstrip("/") for f in fallbacks if f.rstrip("/") != server.rstrip("/")]
        self.server = self.servers[0]
        self.timeout = timeout

    def _raw(self, method, path, data=None, headers=None):
        last = None
        for server in [self.server] + [s for s in self.servers if s != self.server]:
            h = {"User-Agent": "ForeverRelationshipsCompanion/" + VERSION}
            h.update(headers or {})
            req = urllib.request.Request(server + path, data=data, method=method, headers=h)
            try:
                with urllib.request.urlopen(req, timeout=self.timeout) as r:
                    self.server = server  # stick with the one that works
                    return r.status, r.read(), dict(r.headers)
            except urllib.error.HTTPError as e:
                return e.code, e.read(), dict(e.headers)
            except (urllib.error.URLError, OSError) as e:  # DNS or connection failure: try the next address
                last = e
        raise RuntimeError("%s %s -> no server reachable (%s)" % (method, path, last))

    def _req(self, method, path, body=None):
        data = json.dumps(body).encode("utf-8") if body is not None else None
        code, raw, _ = self._raw(method, path, data, {"Content-Type": "application/json"})
        if code >= 400:
            raise RuntimeError("%s %s -> HTTP %d: %s" % (method, path, code, raw.decode("utf-8", "replace")[:300]))
        return json.loads(raw.decode("utf-8"))

    def sync(self, body):
        return self._req("POST", "/v1/sync", body)

    def feedback(self, install_id, items):
        return self._req("POST", "/v1/feedback", {"installId": install_id, "items": items})

    def auth_begin(self, uploader_id, region):
        return self._req("POST", "/v1/auth/begin", {"uploaderId": uploader_id, "region": region})["url"]

    def auth_status(self, uploader_id):
        return self._req("POST", "/v1/auth/status", {"uploaderId": uploader_id})

    def backup_put(self, bid, token, blob):
        code, raw, _ = self._raw("PUT", "/v1/backup/" + bid, blob, {"X-Write-Token": token, "Content-Type": "application/octet-stream"})
        if code >= 400:
            raise RuntimeError("backup upload -> HTTP %d: %s" % (code, raw.decode("utf-8", "replace")[:200]))
        return json.loads(raw.decode("utf-8"))

    def backup_get(self, bid):
        code, raw, headers = self._raw("GET", "/v1/backup/" + bid)
        if code == 404:
            return None, None
        if code >= 400:
            raise RuntimeError("backup download -> HTTP %d" % code)
        return raw, headers.get("X-Backup-At")

    def backup_delete(self, bid, token):
        code, raw, _ = self._raw("DELETE", "/v1/backup/" + bid, None, {"X-Write-Token": token})
        return code < 400


# ---------------------------------------------------------------------------
# End-to-end encrypted backup (AES-256-GCM). The key never leaves this computer;
# the player keeps a recovery code. The server stores an opaque blob.
# ---------------------------------------------------------------------------
BACKUP_MAGIC = b"FRB1"
KEYCHAIN_SERVICE = "Forever Relationships backup"


def _aesgcm():
    try:
        from cryptography.hazmat.primitives.ciphers.aead import AESGCM
    except ImportError:
        raise RuntimeError("cloud backup needs the 'cryptography' package: pip install cryptography (the downloadable apps include it)")
    return AESGCM


def recovery_code(key):
    b32 = base64.b32encode(key).decode("ascii").rstrip("=")
    return "-".join(b32[i:i + 4] for i in range(0, len(b32), 4))


def key_from_code(code):
    s = (code or "").replace("-", "").replace(" ", "").upper()
    s += "=" * (-len(s) % 8)
    key = base64.b32decode(s)
    if len(key) != 32:
        raise ValueError("that recovery code is not valid")
    return key


def backup_ids(key):
    """Backup address and write token, both derived from the key (the server never sees the key)."""
    return (hashlib.sha256(b"fr-backup-id:" + key).hexdigest(), hashlib.sha256(b"fr-backup-write:" + key).hexdigest())


def encrypt_blob(key, plain):
    nonce = os.urandom(12)
    return BACKUP_MAGIC + nonce + _aesgcm()(key).encrypt(nonce, plain, BACKUP_MAGIC)


def decrypt_blob(key, blob):
    if not blob or blob[:4] != BACKUP_MAGIC:
        raise ValueError("not a Forever Relationships backup")
    return _aesgcm()(key).decrypt(blob[4:16], blob[16:], BACKUP_MAGIC)


def sv_files(wow):
    """Every Forever Relationships (ForeverRelationships) SavedVariables file (account-wide and per character), relative to WTF/Account."""
    root = os.path.join(wow, "WTF", "Account")
    out = {}
    for path in glob.glob(os.path.join(root, "**", "SavedVariables", "ForeverRelationships.lua"), recursive=True):
        with open(path, "rb") as f:
            out[os.path.relpath(path, root).replace(os.sep, "/")] = f.read()
    return out


def pack_files(files):
    return gzip.compress(json.dumps({"v": 1, "files": {k: base64.b64encode(v).decode("ascii") for k, v in files.items()}}).encode("utf-8"))


def unpack_files(plain):
    d = json.loads(gzip.decompress(plain).decode("utf-8"))
    return {k: base64.b64decode(v) for k, v in d["files"].items()}


class KeyStore:
    """macOS Keychain when available; otherwise a private file next to the companion state."""
    def __init__(self, use_keychain=None):
        self.keychain = (platform.system() == "Darwin" and shutil.which("security") is not None) if use_keychain is None else use_keychain

    def _file(self, account):
        return os.path.join(os.path.dirname(STATE_PATH), "backup-%s.key" % account[:12])

    def load(self, account):
        if self.keychain:
            r = subprocess.run(["security", "find-generic-password", "-s", KEYCHAIN_SERVICE, "-a", account, "-w"], capture_output=True, text=True)
            if r.returncode == 0 and r.stdout.strip():
                return bytes.fromhex(r.stdout.strip())
            return None
        try:
            with open(self._file(account)) as f:
                return bytes.fromhex(f.read().strip())
        except OSError:
            return None

    def save(self, account, key):
        if self.keychain:
            subprocess.run(["security", "add-generic-password", "-U", "-s", KEYCHAIN_SERVICE, "-a", account, "-w", key.hex()],
                           capture_output=True, check=True)
            return
        os.makedirs(os.path.dirname(self._file(account)), exist_ok=True)
        fd = os.open(self._file(account), os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, "w") as f:
            f.write(key.hex())

    def delete(self, account):
        if self.keychain:
            subprocess.run(["security", "delete-generic-password", "-s", KEYCHAIN_SERVICE, "-a", account], capture_output=True)
        else:
            try:
                os.remove(self._file(account))
            except OSError:
                pass


def sync_backup(wow, uploader, client, state, keystore, log=print):
    """Encrypt and upload the history when it changed. Returns (info, new_recovery_code_or_None)."""
    key, new_code = keystore.load(uploader), None
    if key is None:
        key = os.urandom(32)
        keystore.save(uploader, key)
        new_code = recovery_code(key)
        log("  NEW BACKUP KEY. Save this recovery code in your Passwords app; without it nobody can restore your backup:")
        log("    " + new_code)
    files = sv_files(wow)
    if not files:
        return None, new_code
    plain = pack_files(files)
    digest = hashlib.sha256(plain).hexdigest()
    st = state.setdefault("backup-" + uploader[:8], {})
    bid, token = backup_ids(key)
    if st.get("digest") != digest:
        res = client.backup_put(bid, token, encrypt_blob(key, plain))
        st.update(digest=digest, at=res.get("at"), size=res.get("stored"))
        log("  backup: %d file(s) encrypted and uploaded (%d bytes)" % (len(files), res.get("stored", 0)))
    return {"at": st.get("at"), "size": st.get("size")}, new_code


def restore_backup(code, wow, client, keystore=None, log=print):
    """Download, decrypt and write back the history (run with the game closed)."""
    key = key_from_code(code)
    bid, _ = backup_ids(key)
    blob, at = client.backup_get(bid)
    if blob is None:
        raise RuntimeError("no backup found for that recovery code")
    files = unpack_files(decrypt_blob(key, blob))
    root = os.path.join(wow, "WTF", "Account")
    for rel, data in files.items():
        if ".." in rel.split("/"):
            continue
        path = os.path.join(root, *rel.split("/"))
        os.makedirs(os.path.dirname(path), exist_ok=True)
        if os.path.exists(path):
            os.replace(path, path + ".before-restore")
        with open(path, "wb") as f:
            f.write(data)
    uploader = None
    for rel, data in files.items():
        if rel.count("/") == 2:   # <ACCOUNT>/SavedVariables/ForeverRelationships.lua
            db = parse_saved_variables(data.decode("utf-8", "replace")).get("ForeverRelationshipsDB") or {}
            uploader = (db.get("cloud") or {}).get("uploaderId")
    if uploader:
        (keystore or KeyStore()).save(uploader, key)   # future backups keep using the same key
    log("Restored %d file(s) from the backup of %s. Start the game to see your history." % (
        len(files), time.strftime("%Y-%m-%d %H:%M", time.localtime(int(at))) if at else "?"))
    return len(files)


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
    return sorted(glob.glob(os.path.join(wow, "WTF", "Account", "*", "SavedVariables", "ForeverRelationships.lua")))


def netdata_path(wow):
    return os.path.join(wow, "Interface", "AddOns", "ForeverRelationships", "Cloud", "NetData.lua")


def sync_feedback(db, client, state, log=print):
    """Send new in-game feedback reports; return {id: {status, reply}} or None."""
    fb = db.get("feedback") or {}
    iid = fb.get("installId")
    if not isinstance(iid, str) or not iid:
        return None
    st = state.setdefault("fb-" + iid[:8], {})
    sent = set(st.get("sent", []))
    items = []
    for r in as_list(fb.get("outbox")):
        if isinstance(r, dict) and r.get("id") and r["id"] not in sent:
            items.append({k: r.get(k) for k in ("id", "kind", "text", "version", "diag", "t")})
    res = client.feedback(iid, items[:20])
    statuses = res.get("statuses") or {}
    st["sent"] = sorted(sent | set(statuses))
    if items:
        log("  feedback: %d new report(s) sent" % res.get("accepted", 0))
    return statuses


def sync_file(sv_path, client, wow, state, log=print, keystore=None):
    """One sync for one WoW account. Returns a dict (newRecoveryCode when a backup key was just created)."""
    with open(sv_path, encoding="utf-8", errors="replace") as f:
        sv = parse_saved_variables(f.read())
    db = sv.get("ForeverRelationshipsDB") or {}
    keystore = keystore or KeyStore()
    data = {"protocol": PROTOCOL, "generatedAt": int(time.time()), "companion": {"version": VERSION, "syncedAt": int(time.time())}}
    result = {}

    feedback = sync_feedback(db, client, state, log)   # sent whenever the player pressed Send
    if feedback is not None:
        data["feedback"] = feedback

    cloud = db.get("cloud") or {}
    uploader, outbox = cloud.get("uploaderId"), cloud.get("outbox") or {}
    if uploader:
        st = state.setdefault(uploader[:8], {})
        if cloud.get("deleteRequested") and st.get("deletedFor") != cloud["deleteRequested"]:
            client.sync({"uploaderId": uploader, "protocol": PROTOCOL, "deleteRequested": True, "me": outbox.get("me")})
            key = keystore.load(uploader)
            if key:
                bid, token = backup_ids(key)
                client.backup_delete(bid, token)
                keystore.delete(uploader)
            st["deletedFor"] = cloud["deleteRequested"]
            log("  cloud data deleted and excluded")
        elif outbox:
            consents = {k: bool((outbox.get("consents") or {}).get(k)) for k in ("backup", "profile", "community", "recommend")}
            body = {"uploaderId": uploader, "protocol": PROTOCOL, "consents": consents, "me": outbox.get("me"),
                    "profile": outbox.get("profile"), "community": as_list(outbox.get("community")), "lookups": as_list(outbox.get("lookups"))}
            res = client.sync(body)
            data["profiles"] = res.get("profiles") or {}
            data["suggestions"] = res.get("suggestions") or []
            data["me"] = res.get("me") or {}
            if res.get("storedSessions"):
                log("  community: %d new session(s) shared" % res["storedSessions"])
            if consents["backup"]:
                info, code = sync_backup(wow, uploader, client, state, keystore, log)
                data["backup"] = info
                if code:
                    result["newRecoveryCode"] = code
            else:
                key = keystore.load(uploader)
                if key:   # consent withdrawn: the backup is deleted
                    bid, token = backup_ids(key)
                    client.backup_delete(bid, token)
                    keystore.delete(uploader)
                    log("  backup turned off: deleted from the cloud")
    write_netdata(netdata_path(wow), data)
    log("  synced -> %s" % netdata_path(wow))
    return result


# ---------------------------------------------------------------------------
# Battle.net link (--link): proves each network witness is a unique, real account
# ---------------------------------------------------------------------------
def find_uploader_id(wow):
    for sv in find_saved_variables(wow):
        with open(sv, encoding="utf-8", errors="replace") as f:
            db = parse_saved_variables(f.read()).get("ForeverRelationshipsDB") or {}
        uid = (db.get("cloud") or {}).get("uploaderId") or (db.get("net") or {}).get("uploaderId")
        if uid:
            return uid
    return None


def link_battlenet(client, wow, region, open_browser=webbrowser.open, wait=300, poll=5, log=print):
    uid = find_uploader_id(wow)
    if not uid:
        log("Turn on a cloud layer in game first (Privacy), then log out or /reload once.")
        return False
    url = client.auth_begin(uid, region)
    log("Opening Battle.net login in your browser. If it does not open, visit:\n  " + url)
    open_browser(url)
    deadline = time.time() + wait
    while time.time() < deadline:
        st = client.auth_status(uid)
        if st.get("linked"):
            log("Linked to Battle.net. Verified Forever characters: %d. /reload in game to see it." % st.get("characters", 0))
            return True
        time.sleep(poll)
    log("Not linked yet. You can run --link again anytime.")
    return False


# ---------------------------------------------------------------------------
# One-time move from the addon's previous name (0.3.x / 0.4.0). Runs only while
# WoW is closed, so the game can't overwrite migrated SavedVariables on logout.
# ---------------------------------------------------------------------------
_OLD = "Trust" + "Advisor"                       # previous addon/SavedVariables name
_OLD_LOWER = "trust" + "advisor"
_NEW = "ForeverRelationships"


def wow_running():
    try:
        if platform.system() == "Windows":
            out = subprocess.run(["tasklist"], capture_output=True, text=True).stdout.lower()
            return "wow.exe" in out or "wowclassic.exe" in out
        out = subprocess.run(["ps", "-axo", "comm"], capture_output=True, text=True).stdout
        return any(n in out for n in ("World of Warcraft", "/Wow", "WowClassic"))
    except Exception:
        return True   # unsure: don't touch game files


def _fresh_db(path):
    """True if a SavedVariables file has no recorded history (safe to replace)."""
    try:
        with open(path, encoding="utf-8") as f:
            sv = parse_saved_variables(f.read())
    except Exception:
        return False
    db = sv.get(_NEW + "DB")
    return not (isinstance(db, dict) and (db.get("events") or db.get("players")))


def migrate_legacy(wow):
    """Move data and autostart entries from the previous name. Returns a list of what was done."""
    done = []
    home = os.path.expanduser("~")
    old_state = os.path.join(home, "." + _OLD_LOWER)
    new_state = os.path.dirname(STATE_PATH)
    if os.path.isdir(old_state) and not os.path.exists(new_state):
        shutil.move(old_state, new_state)
        done.append("state folder")
    # old autostart entries
    system = platform.system()
    if system == "Darwin":
        plist = os.path.join(home, "Library", "LaunchAgents", "com.%s.companion.plist" % _OLD_LOWER)
        if os.path.exists(plist):
            subprocess.run(["launchctl", "unload", "-w", plist], capture_output=True)
            os.remove(plist)
            done.append("old background service")
        # unload alone doesn't stop a running job on current macOS
        subprocess.run(["launchctl", "bootout", "gui/%d/com.%s.companion" % (os.getuid(), _OLD_LOWER)], capture_output=True)
        log = os.path.join(home, "Library", "Logs", _OLD + "Companion.log")
        if os.path.exists(log):
            os.remove(log)
    elif system == "Windows":
        appdata = os.environ.get("APPDATA", os.path.join(home, "AppData", "Roaming"))
        cmd = os.path.join(appdata, "Microsoft", "Windows", "Start Menu", "Programs", "Startup", _OLD + "Companion.cmd")
        if os.path.exists(cmd):
            os.remove(cmd)
            done.append("old startup entry")
    else:
        unit = os.path.join(home, ".config", "systemd", "user", "%s-companion.service" % _OLD_LOWER)
        if os.path.exists(unit):
            if shutil.which("systemctl"):
                subprocess.run(["systemctl", "--user", "disable", "--now", os.path.basename(unit)], capture_output=True)
            os.remove(unit)
            done.append("old service")
    if not wow or wow_running():
        return done
    # SavedVariables: account-wide and per character
    for old in glob.glob(os.path.join(wow, "WTF", "Account", "**", "SavedVariables", _OLD + ".lua"), recursive=True):
        new = os.path.join(os.path.dirname(old), _NEW + ".lua")
        if os.path.exists(new) and not _fresh_db(new):
            continue
        with open(old, encoding="utf-8") as f:
            text = f.read()
        with open(new, "w", encoding="utf-8") as f:
            f.write(text.replace(_OLD + "CharDB", _NEW + "CharDB").replace(_OLD + "DB", _NEW + "DB"))
        os.replace(old, old + ".migrated")
        for extra in (old + ".bak",):
            if os.path.exists(extra):
                os.remove(extra)
        done.append("saved data " + os.path.relpath(new, wow))
    # the old addon folder, once the new one is installed (both would load otherwise)
    addons = os.path.join(wow, "Interface", "AddOns")
    if os.path.isdir(os.path.join(addons, _NEW)) and os.path.isdir(os.path.join(addons, _OLD)):
        shutil.rmtree(os.path.join(addons, _OLD))
        done.append("old addon folder")
    return done


# ---------------------------------------------------------------------------
# Autostart (--install / --uninstall): start with the computer, no admin rights
# ---------------------------------------------------------------------------
LABEL = "com.foreverrelationships.companion"


def stable_executable(exe):
    """macOS runs a downloaded app from a random read-only copy (App Translocation)
    that disappears after a restart. Point autostart at the real app instead."""
    if "/AppTranslocation/" not in exe or ".app/Contents/MacOS/" not in exe:
        return exe
    app, inner = exe.split(".app/Contents/MacOS/", 1)
    name = os.path.basename(app) + ".app"
    for base in ("/Applications", os.path.expanduser("~/Applications")):
        candidate = os.path.join(base, name, "Contents", "MacOS", inner)
        if os.path.exists(candidate):
            return candidate
    print("This app is running from a temporary copy. Move it to Applications and open it again.")
    return exe


def launch_command(extra_args):
    """The command that starts this companion, frozen executable or script."""
    if getattr(sys, "frozen", False):
        return [stable_executable(sys.executable)] + extra_args
    py = sys.executable
    if platform.system() == "Windows":
        pyw = os.path.join(os.path.dirname(py), "pythonw.exe")
        if os.path.exists(pyw):
            py = pyw  # no console window
    return [py, os.path.abspath(__file__)] + extra_args


def mac_plist(cmd, log_path):
    args = "".join("    <string>%s</string>\n" % a.replace("&", "&amp;").replace("<", "&lt;") for a in cmd)
    return ("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
            "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n"
            "<plist version=\"1.0\"><dict>\n"
            "  <key>Label</key><string>%s</string>\n"
            "  <key>ProgramArguments</key><array>\n%s  </array>\n"
            "  <key>RunAtLoad</key><true/>\n  <key>KeepAlive</key><true/>\n"
            "  <key>StandardOutPath</key><string>%s</string>\n  <key>StandardErrorPath</key><string>%s</string>\n"
            "</dict></plist>\n") % (LABEL, args, log_path, log_path)


def windows_startup_script(cmd):
    quoted = " ".join('"%s"' % a for a in cmd)
    return '@echo off\r\nstart "" /min %s\r\n' % quoted


def autostart_paths():
    home = os.path.expanduser("~")
    system = platform.system()
    if system == "Darwin":
        return {"file": os.path.join(home, "Library", "LaunchAgents", LABEL + ".plist"),
                "log": os.path.join(home, "Library", "Logs", "ForeverRelationshipsCompanion.log")}
    if system == "Windows":
        appdata = os.environ.get("APPDATA", os.path.join(home, "AppData", "Roaming"))
        return {"file": os.path.join(appdata, "Microsoft", "Windows", "Start Menu", "Programs", "Startup", "ForeverRelationshipsCompanion.cmd")}
    return {"file": os.path.join(home, ".config", "systemd", "user", "forever-relationships-companion.service")}


def install_autostart(extra_args):
    paths = autostart_paths()
    cmd = launch_command(list(extra_args) + ["--watch"])
    os.makedirs(os.path.dirname(paths["file"]), exist_ok=True)
    system = platform.system()
    if system == "Darwin":
        with open(paths["file"], "w", encoding="utf-8") as f:
            f.write(mac_plist(cmd, paths["log"]))
        subprocess.run(["launchctl", "unload", paths["file"]], capture_output=True)
        subprocess.run(["launchctl", "load", "-w", paths["file"]], check=False)
    elif system == "Windows":
        with open(paths["file"], "w", encoding="utf-8") as f:
            f.write(windows_startup_script(cmd))
        subprocess.Popen(cmd, creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
    else:
        with open(paths["file"], "w", encoding="utf-8") as f:
            f.write("[Unit]\nDescription=Forever Relationships companion\n[Service]\nExecStart=%s\nRestart=always\n"
                    "[Install]\nWantedBy=default.target\n" % " ".join(cmd))
        if shutil.which("systemctl"):
            subprocess.run(["systemctl", "--user", "enable", "--now", "forever-relationships-companion.service"], check=False)
    print("Installed: the companion now starts with your computer (%s)" % paths["file"])
    return paths["file"]


def uninstall_autostart():
    paths = autostart_paths()
    if platform.system() == "Darwin" and os.path.exists(paths["file"]):
        subprocess.run(["launchctl", "unload", "-w", paths["file"]], capture_output=True)
        subprocess.run(["launchctl", "bootout", "gui/%d/%s" % (os.getuid(), LABEL)], capture_output=True)
    elif platform.system() not in ("Darwin", "Windows") and shutil.which("systemctl"):
        subprocess.run(["systemctl", "--user", "disable", "--now", "forever-relationships-companion.service"], capture_output=True)
    if os.path.exists(paths["file"]):
        os.remove(paths["file"])
        print("Removed autostart (%s). Running copies stop at the next restart." % paths["file"])
    else:
        print("Autostart was not installed.")


# ---------------------------------------------------------------------------
# macOS app mode: double-clicking "Forever Relationships Companion.app" (no arguments)
# installs the background service and offers the Battle.net link with native dialogs.
# ---------------------------------------------------------------------------
def is_mac_app_bundle():
    return platform.system() == "Darwin" and getattr(sys, "frozen", False) and ".app/Contents/MacOS/" in sys.executable


def is_mac_app_launch(argv):
    return (platform.system() == "Darwin" and getattr(sys, "frozen", False)
            and ".app/Contents/MacOS/" in sys.executable and not argv)


def _osascript(script):
    r = subprocess.run(["osascript", "-e", script], capture_output=True, text=True)
    return r.stdout.strip() if r.returncode == 0 else None


def mac_dialog(text, buttons=("OK",), default=None):
    btns = ", ".join('"%s"' % b for b in buttons)
    script = 'display dialog "%s" with title "Forever Relationships Companion" buttons {%s} default button "%s" with icon note' % (
        text.replace('"', "'"), btns, default or buttons[-1])
    out = _osascript(script) or ""
    return out.split("button returned:", 1)[-1].strip() if "button returned:" in out else None


def mac_choose_region():
    out = _osascript('choose from list {"Americas (us)", "Europe (eu)", "Korea (kr)", "Taiwan (tw)"} '
                     'with title "Forever Relationships Companion" with prompt "Your Battle.net region:" default items {"Americas (us)"}')
    if not out or out == "false":
        return None
    return out.split("(")[-1].rstrip(")")


def mac_show_code(code):
    """Recovery code in a dialog with a selectable text field (copy it into Passwords)."""
    _osascript('display dialog "Your cloud backup RECOVERY CODE. Save it in your Passwords app now: without it, nobody (not even us) '
               'can restore your backup." default answer "%s" with title "Forever Relationships" buttons {"I saved it"} '
               'default button "I saved it" with icon caution' % code)


def mac_app_main(wow, client):
    install_autostart([])
    msg = "Forever Relationships Companion is installed and runs in the background whenever your Mac starts."
    uid = find_uploader_id(wow) if wow else None
    if not uid:
        mac_dialog(msg + "\n\nNext: in game, turn on a cloud layer you want (/fr privacy) and /reload. "
                   "Open this app again anytime to link Battle.net or see your backup recovery code.", ("OK",))
        return 0
    key = KeyStore().load(uid)
    if key and mac_dialog(msg + "\n\nYour cloud backup is on.", ("OK", "Show recovery code")) == "Show recovery code":
        mac_show_code(recovery_code(key))
    if client.auth_status(uid).get("linked"):
        mac_dialog("Your Battle.net account is linked. You're all set.", ("OK",))
        return 0
    if mac_dialog("Link your Battle.net account? It proves your characters are yours, so your public profile can show "
                  "Official data. Only a one-way code of your account id is stored.", ("Later", "Link Battle.net")) != "Link Battle.net":
        return 0
    region = mac_choose_region()
    if not region:
        return 0
    logs = []
    ok = link_battlenet(client, wow, region, log=logs.append)
    mac_dialog(logs[-1] if logs else ("Linked." if ok else "Not linked yet."), ("OK",))
    return 0 if ok else 1


def main(argv=None):
    ap = argparse.ArgumentParser(description="Forever Relationships companion app")
    ap.add_argument("--server", default=os.environ.get("FR_SERVER", DEFAULT_SERVER), help="network server URL (default: the official Forever Relationships server)")
    ap.add_argument("--wow", help="WoW: Forever folder (contains WTF and Interface)")
    ap.add_argument("--once", action="store_true", help="sync once and exit")
    ap.add_argument("--interval", type=int, default=30, help="seconds between checks in watch mode")
    ap.add_argument("--install", action="store_true", help="start the companion automatically with your computer")
    ap.add_argument("--uninstall", action="store_true", help="remove the automatic start")
    ap.add_argument("--link", action="store_true", help="link your Battle.net account (proves your characters are yours)")
    ap.add_argument("--restore", metavar="CODE", help="restore your history from the cloud backup (game closed)")
    ap.add_argument("--show-recovery-code", action="store_true", help="show the recovery code of your cloud backup again")
    ap.add_argument("--region", default="us", choices=["us", "eu", "kr", "tw"], help="Battle.net region for --link")
    ap.add_argument("--watch", action="store_true", help="keep syncing in the background (default when no other action)")
    ap.add_argument("--version", action="version", version="Forever Relationships companion " + VERSION)
    raw = sys.argv[1:] if argv is None else argv
    app_launch = is_mac_app_launch(raw)
    args = ap.parse_args(raw)
    if args.uninstall:
        uninstall_autostart()
        return 0
    wow = args.wow or next((p for p in DEFAULT_WOW if os.path.isdir(p)), None)
    for what in migrate_legacy(wow):
        print("Moved from the previous name: " + what)
    if args.install:
        extra = []
        if args.wow:
            extra += ["--wow", args.wow]
        if args.server and args.server != DEFAULT_SERVER:
            extra += ["--server", args.server]
        install_autostart(extra)
        return 0
    if not args.server:
        ap.error("--server (or FR_SERVER) is required")
    client = Client(args.server, fallbacks=FALLBACK_SERVERS if args.server == DEFAULT_SERVER else ())
    if app_launch:
        if not wow:
            mac_dialog("World of Warcraft: Forever was not found in /Applications. Install it there, or run this app "
                       "from Terminal with --wow \"<path to _forever_>\".", ("OK",))
            return 1
        return mac_app_main(wow, client)
    if not wow:
        ap.error("WoW: Forever folder not found; pass --wow")
    if args.link:
        return 0 if link_battlenet(client, wow, args.region) else 1
    if args.restore:
        restore_backup(args.restore, wow, client)
        return 0
    if args.show_recovery_code:
        uid = find_uploader_id(wow)
        key = uid and KeyStore().load(uid)
        print(recovery_code(key) if key else "No cloud backup key on this computer.")
        return 0
    state = load_state()
    seen = {}
    print("Forever Relationships companion %s - %s - server %s" % (VERSION, wow, args.server))
    while True:
        for what in migrate_legacy(wow):
            print("Moved from the previous name: " + what)
        for sv in find_saved_variables(wow):
            mtime = os.path.getmtime(sv)
            if seen.get(sv) == mtime:
                continue
            seen[sv] = mtime
            print("[%s] %s changed" % (time.strftime("%H:%M:%S"), sv))
            try:
                res = sync_file(sv, client, wow, state)
                save_state(state)
                if res.get("newRecoveryCode") and is_mac_app_bundle():
                    mac_show_code(res["newRecoveryCode"])
            except Exception as e:  # keep watching on network/parse errors
                print("  sync failed: %s" % e)
                seen.pop(sv, None)
        if args.once:
            return 0
        time.sleep(args.interval)


if __name__ == "__main__":
    sys.exit(main())
