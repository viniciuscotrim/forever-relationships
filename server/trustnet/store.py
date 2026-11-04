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
            self.db.commit()

    # -- writes ---------------------------------------------------------------
    def upload(self, uploader, witness, wguild, characters, reports, now=None):
        now = now or int(time.time())
        with self.lock:
            c = self.db.cursor()
            c.execute("INSERT INTO uploaders (id, created_at, last_seen) VALUES (?, ?, ?) "
                      "ON CONFLICT(id) DO UPDATE SET last_seen = excluded.last_seen", (uploader, now, now))
            for ch in characters:
                c.execute("INSERT OR REPLACE INTO characters (uploader, guid, name, guild, seen_at) VALUES (?, ?, ?, ?, ?)",
                          (uploader, ch["guid"], ch.get("name", ""), ch.get("guild", ""), now))
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
