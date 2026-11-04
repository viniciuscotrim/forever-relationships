"""SQLite storage for the Trust Advisor network. Uploader ids are bearer secrets:
only their SHA-256 is stored."""
import hashlib
import sqlite3
import threading
import time

SCHEMA = """
CREATE TABLE IF NOT EXISTS uploaders (
  id TEXT PRIMARY KEY, created_at INTEGER, last_seen INTEGER
);
CREATE TABLE IF NOT EXISTS characters (
  uploader TEXT, guid TEXT, name TEXT, guild TEXT, seen_at INTEGER,
  PRIMARY KEY (uploader, guid)
);
CREATE TABLE IF NOT EXISTS reports (
  uploader TEXT, witness TEXT, wguild TEXT, s TEXT, d TEXT, x REAL, m REAL, t INTEGER, k TEXT,
  received_at INTEGER, UNIQUE (uploader, s, d, k, t)
);
CREATE INDEX IF NOT EXISTS reports_s ON reports (s);
CREATE TABLE IF NOT EXISTS disputes (
  id TEXT PRIMARY KEY, uploader TEXT, subject TEXT, d TEXT, k TEXT, t INTEGER,
  reason TEXT, status TEXT, created_at INTEGER, reviewed_at INTEGER
);
CREATE TABLE IF NOT EXISTS optout (guid TEXT PRIMARY KEY, at INTEGER);
CREATE TABLE IF NOT EXISTS presence (
  uploader TEXT, a INTEGER, b INTEGER, member TEXT, UNIQUE (uploader, a, member)
);
CREATE INDEX IF NOT EXISTS presence_u ON presence (uploader);
CREATE TABLE IF NOT EXISTS links (uploader TEXT PRIMARY KEY, account TEXT, region TEXT, linked_at INTEGER);
CREATE TABLE IF NOT EXISTS owned (guid TEXT PRIMARY KEY, account TEXT, verified_at INTEGER);
CREATE TABLE IF NOT EXISTS feedback (
  id TEXT PRIMARY KEY, install TEXT, kind TEXT, text TEXT, version TEXT, diag TEXT, t INTEGER,
  received_at INTEGER, status TEXT, reply TEXT, updated_at INTEGER
);
CREATE INDEX IF NOT EXISTS feedback_install ON feedback (install);
CREATE TABLE IF NOT EXISTS admin_credentials (
  id TEXT PRIMARY KEY, public_key BLOB, sign_count INTEGER, created_at INTEGER, last_used INTEGER, label TEXT
);
CREATE TABLE IF NOT EXISTS admin_kv (k TEXT PRIMARY KEY, v TEXT);
CREATE TABLE IF NOT EXISTS admin_setup (token_hash TEXT PRIMARY KEY, created_at INTEGER, used_at INTEGER);
CREATE TABLE IF NOT EXISTS admin_sessions (token_hash TEXT PRIMARY KEY, created_at INTEGER, expires_at INTEGER, ip TEXT);
CREATE TABLE IF NOT EXISTS admin_failures (t INTEGER, ip TEXT, what TEXT);
CREATE TABLE IF NOT EXISTS oauth_states (state TEXT PRIMARY KEY, uploader TEXT, redirect TEXT, region TEXT, created_at INTEGER);
"""


def hash_id(uploader_id):
    return hashlib.sha256(uploader_id.encode("utf-8")).hexdigest()


class Store:
    def __init__(self, path):
        self.db = sqlite3.connect(path, check_same_thread=False)
        self.db.row_factory = sqlite3.Row
        self.lock = threading.Lock()
        with self.lock:
            self.db.executescript(SCHEMA)
            self._migrate()
            self.db.commit()

    def _migrate(self):
        # demographics of the uploader's OWN characters (network participants only)
        have = {r[1] for r in self.db.execute("PRAGMA table_info(characters)")}
        for col, typ in (("class", "TEXT"), ("race", "TEXT"), ("faction", "TEXT"), ("level", "INTEGER"),
                         ("realm", "TEXT"), ("locale", "TEXT")):
            if col not in have:
                self.db.execute("ALTER TABLE characters ADD COLUMN %s %s" % (col, typ))

    # -- writes ---------------------------------------------------------------
    def upload(self, uploader, witness, wguild, characters, reports, now=None):
        now = now or int(time.time())
        with self.lock:
            c = self.db.cursor()
            c.execute("INSERT INTO uploaders (id, created_at, last_seen) VALUES (?, ?, ?) "
                      "ON CONFLICT(id) DO UPDATE SET last_seen = excluded.last_seen", (uploader, now, now))
            for ch in characters:
                c.execute("INSERT OR REPLACE INTO characters (uploader, guid, name, guild, seen_at, class, race, faction, level, realm, locale) "
                          "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                          (uploader, ch["guid"], ch.get("name", ""), ch.get("guild", ""), now, ch.get("class"), ch.get("race"),
                           ch.get("faction"), ch.get("level"), ch.get("realm"), ch.get("locale")))
            n = 0
            for r in reports:
                c.execute("INSERT OR IGNORE INTO reports (uploader, witness, wguild, s, d, x, m, t, k, received_at) "
                          "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                          (uploader, witness, wguild or "", r["s"], r["d"], r["x"], r["m"], r["t"], r["k"], now))
                n += c.rowcount
            self.db.commit()
            return n

    def add_presence(self, uploader, sessions):
        """sessions: [(a, b, [member guids])] - the uploader's own group history."""
        with self.lock:
            c = self.db.cursor()
            for a, b, members in sessions:
                for g in members:
                    c.execute("INSERT OR IGNORE INTO presence (uploader, a, b, member) VALUES (?, ?, ?, ?)", (uploader, a, b, g))
            self.db.commit()

    def presence_of(self, uploader):
        with self.lock:
            rows = self.db.execute("SELECT a, b, member FROM presence WHERE uploader = ?", (uploader,)).fetchall()
        sessions = {}
        for a, b, m in rows:
            sessions.setdefault((a, b), set()).add(m)
        return [(a, b, frozenset(ms)) for (a, b), ms in sessions.items()]

    def uploader_created(self, uploader):
        with self.lock:
            r = self.db.execute("SELECT created_at FROM uploaders WHERE id = ?", (uploader,)).fetchone()
        return r[0] if r else None

    def shared_reports_by(self, uploader, dims, limit=500):
        q = ",".join("?" * len(dims))
        with self.lock:
            rows = self.db.execute("SELECT witness, s, d, k, t FROM reports WHERE uploader = ? AND d IN (%s) "
                                   "ORDER BY t DESC LIMIT ?" % q, [uploader] + list(dims) + [limit]).fetchall()
        return [dict(r) for r in rows]

    def matching_reports(self, r, window, exclude_uploader):
        with self.lock:
            rows = self.db.execute("SELECT uploader, witness FROM reports WHERE s = ? AND d = ? AND k = ? "
                                   "AND t BETWEEN ? AND ? AND uploader != ?",
                                   (r["s"], r["d"], r["k"], r["t"] - window, r["t"] + window, exclude_uploader)).fetchall()
        return [dict(x) for x in rows]

    # -- Battle.net identity ---------------------------------------------------
    def create_state(self, state, uploader, redirect, region, now):
        with self.lock:
            self.db.execute("DELETE FROM oauth_states WHERE created_at < ?", (now - 900,))
            self.db.execute("INSERT INTO oauth_states (state, uploader, redirect, region, created_at) VALUES (?, ?, ?, ?, ?)",
                            (state, uploader, redirect, region, now))
            self.db.commit()

    def pop_state(self, state, now):
        with self.lock:
            r = self.db.execute("SELECT uploader, redirect, region, created_at FROM oauth_states WHERE state = ?", (state,)).fetchone()
            self.db.execute("DELETE FROM oauth_states WHERE state = ?", (state,))
            self.db.commit()
        if not r or now - r[3] > 900:
            return None
        return {"uploader": r[0], "redirect": r[1], "region": r[2]}

    def link(self, uploader, account, region, guids, now):
        with self.lock:
            self.db.execute("INSERT OR REPLACE INTO links (uploader, account, region, linked_at) VALUES (?, ?, ?, ?)",
                            (uploader, account, region, now))
            for g in guids:
                self.db.execute("INSERT OR REPLACE INTO owned (guid, account, verified_at) VALUES (?, ?, ?)", (g, account, now))
            self.db.commit()

    def identity_map(self):
        with self.lock:
            return {r[0]: r[1] for r in self.db.execute("SELECT uploader, account FROM links")}

    def owned_map(self):
        out = {}
        with self.lock:
            for g, a in self.db.execute("SELECT guid, account FROM owned"):
                out.setdefault(a, set()).add(g)
        return out

    def owner_of(self, guid):
        with self.lock:
            r = self.db.execute("SELECT account FROM owned WHERE guid = ?", (guid,)).fetchone()
        return r[0] if r else None

    def link_of(self, uploader):
        with self.lock:
            r = self.db.execute("SELECT account, region, linked_at FROM links WHERE uploader = ?", (uploader,)).fetchone()
        return {"account": r[0], "region": r[1], "linked_at": r[2]} if r else None

    # -- feedback ---------------------------------------------------------------
    def feedback_recent_count(self, install, since):
        with self.lock:
            return self.db.execute("SELECT count(*) FROM feedback WHERE install = ? AND received_at >= ?", (install, since)).fetchone()[0]

    def add_feedback(self, install, item, now):
        with self.lock:
            cur = self.db.execute("INSERT OR IGNORE INTO feedback (id, install, kind, text, version, diag, t, received_at, status, reply, updated_at) "
                                  "VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'received', NULL, ?)",
                                  (item["id"], install, item["kind"], item["text"], item["version"], item["diag"], item["t"], now, now))
            self.db.commit()
            return cur.rowcount

    def feedback_statuses(self, install):
        with self.lock:
            rows = self.db.execute("SELECT id, status, reply FROM feedback WHERE install = ?", (install,)).fetchall()
        return {r[0]: ({"status": r[1], "reply": r[2]} if r[2] else {"status": r[1]}) for r in rows}

    def list_feedback(self, status=None, limit=200):
        q, args = "SELECT id, kind, text, version, diag, t, received_at, status, reply FROM feedback", []
        if status:
            q, args = q + " WHERE status = ?", [status]
        with self.lock:
            rows = self.db.execute(q + " ORDER BY received_at DESC LIMIT ?", args + [limit]).fetchall()
        return [dict(r) for r in rows]

    def update_feedback(self, fid, status, reply, now):
        with self.lock:
            cur = self.db.execute("UPDATE feedback SET status = ?, reply = COALESCE(?, reply), updated_at = ? WHERE id = ?",
                                  (status, reply, now, fid))
            self.db.commit()
            return cur.rowcount

    def add_dispute(self, uploader, inc, reason, now=None):
        now = now or int(time.time())
        with self.lock:
            self.db.execute("INSERT OR IGNORE INTO disputes (id, uploader, subject, d, k, t, reason, status, created_at) "
                            "VALUES (?, ?, ?, ?, ?, ?, ?, 'open', ?)",
                            (inc["id"], uploader, inc["s"], inc["d"], inc["k"], inc["t0"], reason[:200], now))
            self.db.commit()

    def review_dispute(self, dispute_id, status, now=None):
        assert status in ("upheld", "rejected")
        with self.lock:
            cur = self.db.execute("UPDATE disputes SET status = ?, reviewed_at = ? WHERE id = ?",
                                  (status, now or int(time.time()), dispute_id))
            self.db.commit()
            return cur.rowcount

    def delete_uploader(self, uploader, now=None, skip=()):
        """Data rights: remove everything this uploader sent and hide their characters
        (except contested ones, which someone else also claims)."""
        now = now or int(time.time())
        with self.lock:
            guids = [r[0] for r in self.db.execute("SELECT guid FROM characters WHERE uploader = ?", (uploader,))]
            for g in guids:
                if g in skip:
                    continue
                self.db.execute("INSERT OR REPLACE INTO optout (guid, at) VALUES (?, ?)", (g, now))
            self.db.execute("DELETE FROM reports WHERE uploader = ?", (uploader,))
            self.db.execute("DELETE FROM presence WHERE uploader = ?", (uploader,))
            self.db.execute("DELETE FROM characters WHERE uploader = ?", (uploader,))
            self.db.execute("DELETE FROM disputes WHERE uploader = ?", (uploader,))
            self.db.execute("DELETE FROM uploaders WHERE id = ?", (uploader,))
            acct = self.db.execute("SELECT account FROM links WHERE uploader = ?", (uploader,)).fetchone()
            self.db.execute("DELETE FROM links WHERE uploader = ?", (uploader,))
            if acct and not self.db.execute("SELECT 1 FROM links WHERE account = ?", (acct[0],)).fetchone():
                self.db.execute("DELETE FROM owned WHERE account = ?", (acct[0],))
            self.db.commit()
            return guids

    # -- reads ----------------------------------------------------------------
    def reports_about(self, guids):
        if not guids:
            return []
        q = ",".join("?" * len(guids))
        with self.lock:
            rows = self.db.execute("SELECT uploader, witness, wguild, s, d, x, m, t, k FROM reports WHERE s IN (%s)" % q, list(guids)).fetchall()
        return [dict(r) for r in rows]

    def disputes_about(self, guids):
        if not guids:
            return []
        q = ",".join("?" * len(guids))
        with self.lock:
            rows = self.db.execute("SELECT * FROM disputes WHERE subject IN (%s)" % q, list(guids)).fetchall()
        return [dict(r) for r in rows]

    def open_disputes(self):
        with self.lock:
            return [dict(r) for r in self.db.execute("SELECT * FROM disputes WHERE status = 'open' ORDER BY created_at").fetchall()]

    def optouts(self):
        with self.lock:
            return {r[0] for r in self.db.execute("SELECT guid FROM optout")}

    def self_claims(self, uploaders=None):
        with self.lock:
            rows = self.db.execute("SELECT uploader, guid FROM characters").fetchall()
        out = {}
        for r in rows:
            out.setdefault(r[0], set()).add(r[1])
        return out

    def claimed_by(self, uploader):
        with self.lock:
            return {r[0] for r in self.db.execute("SELECT guid FROM characters WHERE uploader = ?", (uploader,))}
