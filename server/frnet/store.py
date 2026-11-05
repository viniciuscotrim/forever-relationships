"""SQLite storage, protocol v2 (GDD v2).

Every character identifier is stored ONLY as a keyed HMAC (see Pseudo); raw
GUIDs never reach the database. Uploader ids are stored as SHA-256. Backups are
opaque encrypted blobs on disk; the server cannot read them.
"""
import hashlib
import hmac
import os
import sqlite3
import threading

SCHEMA = """
CREATE TABLE IF NOT EXISTS uploaders (id TEXT PRIMARY KEY, created_at INTEGER, last_seen INTEGER);
CREATE TABLE IF NOT EXISTS participants (
  uploader TEXT PRIMARY KEY, guid_h TEXT, name TEXT, class TEXT, race TEXT, faction TEXT, level INTEGER,
  realm TEXT, locale TEXT, c_backup INTEGER, c_profile INTEGER, c_community INTEGER, c_recommend INTEGER,
  updated_at INTEGER
);
CREATE INDEX IF NOT EXISTS participants_guid ON participants (guid_h);
CREATE TABLE IF NOT EXISTS profiles (guid_h TEXT PRIMARY KEY, uploader TEXT, items TEXT, official TEXT, official_at INTEGER, updated_at INTEGER);
CREATE TABLE IF NOT EXISTS community_sessions (
  id INTEGER PRIMARY KEY AUTOINCREMENT, uploader TEXT, a INTEGER, b INTEGER, type TEXT, place TEXT, kills INTEGER,
  received_at INTEGER, UNIQUE (uploader, a)
);
CREATE TABLE IF NOT EXISTS community_members (
  session_id INTEGER, member_h TEXT, class TEXT, race TEXT, faction TEXT, level INTEGER, j INTEGER, l INTEGER,
  UNIQUE (session_id, member_h)
);
CREATE INDEX IF NOT EXISTS cm_member ON community_members (member_h);
CREATE TABLE IF NOT EXISTS optout (guid_h TEXT PRIMARY KEY, at INTEGER);
CREATE TABLE IF NOT EXISTS lookups (uploader TEXT, day INTEGER, n INTEGER, PRIMARY KEY (uploader, day));
CREATE TABLE IF NOT EXISTS backups (id TEXT PRIMARY KEY, token_hash TEXT, size INTEGER, created_at INTEGER, updated_at INTEGER);
CREATE TABLE IF NOT EXISTS links (uploader TEXT PRIMARY KEY, account TEXT, region TEXT, linked_at INTEGER);
CREATE TABLE IF NOT EXISTS owned (guid_h TEXT PRIMARY KEY, account TEXT, name TEXT, realm_slug TEXT, region TEXT, verified_at INTEGER);
CREATE TABLE IF NOT EXISTS oauth_states (state TEXT PRIMARY KEY, uploader TEXT, redirect TEXT, region TEXT, created_at INTEGER, kind TEXT);
CREATE TABLE IF NOT EXISTS me_sessions (token_hash TEXT PRIMARY KEY, account TEXT, region TEXT, expires_at INTEGER);
CREATE TABLE IF NOT EXISTS feedback (
  id TEXT PRIMARY KEY, install TEXT, kind TEXT, text TEXT, version TEXT, diag TEXT, t INTEGER,
  received_at INTEGER, status TEXT, reply TEXT, updated_at INTEGER
);
CREATE INDEX IF NOT EXISTS feedback_install ON feedback (install);
-- population census: one row per (pseudonymous) character seen by a Community participant
CREATE TABLE IF NOT EXISTS census (h TEXT PRIMARY KEY, realm INTEGER, race TEXT, faction TEXT, class TEXT, level INTEGER,
  seen_at INTEGER, uploader TEXT);
CREATE INDEX IF NOT EXISTS census_seen ON census (seen_at);
CREATE INDEX IF NOT EXISTS census_uploader ON census (uploader);
-- realm ids come from character GUIDs; the type (pvp/pve) is set by the admin in the cockpit
CREATE TABLE IF NOT EXISTS realms (id INTEGER PRIMARY KEY, name TEXT, type TEXT, first_seen INTEGER);
CREATE TABLE IF NOT EXISTS admin_credentials (id TEXT PRIMARY KEY, public_key BLOB, sign_count INTEGER, created_at INTEGER, last_used INTEGER, label TEXT);
CREATE TABLE IF NOT EXISTS admin_kv (k TEXT PRIMARY KEY, v TEXT);
CREATE TABLE IF NOT EXISTS admin_setup (token_hash TEXT PRIMARY KEY, created_at INTEGER, used_at INTEGER);
CREATE TABLE IF NOT EXISTS admin_sessions (token_hash TEXT PRIMARY KEY, created_at INTEGER, expires_at INTEGER, ip TEXT);
CREATE TABLE IF NOT EXISTS admin_failures (t INTEGER, ip TEXT, what TEXT);
"""

# v1 reputation tables are removed in v2 (witness reports, presence, disputes, raw-GUID characters)
DROPPED_V1 = ("reports", "presence", "disputes", "characters")
COMMUNITY_RETENTION = 400 * 86400
CENSUS_RETENTION = 90 * 86400
BACKUP_RETENTION = 180 * 86400


def hash_id(uploader_id):
    return hashlib.sha256(uploader_id.encode("utf-8")).hexdigest()


class Pseudo:
    """Keyed pseudonymization of character GUIDs. The key lives in the
    environment (FR_HASH_SALT), never in the database."""
    def __init__(self, key):
        self.key = (key or "").encode("utf-8")

    def __call__(self, guid):
        return hmac.new(self.key, ("guid:" + guid).encode("utf-8"), hashlib.sha256).hexdigest()[:40]


class Store:
    def __init__(self, path, blob_dir=None):
        self.db = sqlite3.connect(path, check_same_thread=False)
        self.db.row_factory = sqlite3.Row
        self.lock = threading.Lock()
        if blob_dir is None and path != ":memory:":
            blob_dir = os.path.join(os.path.dirname(os.path.abspath(path)), "backups-user")
        self.blob_dir = blob_dir
        self._mem_blobs = {}
        with self.lock:
            for t in DROPPED_V1:
                self.db.execute("DROP TABLE IF EXISTS %s" % t)
            for table, old_col in (("owned", "guid"), ("optout", "guid")):
                cols = {r[1] for r in self.db.execute("PRAGMA table_info(%s)" % table)}
                if old_col in cols:   # v1 stored raw GUIDs: drop (re-verified / re-requested in v2)
                    self.db.execute("DROP TABLE %s" % table)
            cols = {r[1] for r in self.db.execute("PRAGMA table_info(oauth_states)")}
            if cols and "kind" not in cols:
                self.db.execute("DROP TABLE oauth_states")
            self.db.executescript(SCHEMA)
            self.db.commit()

    def q(self, sql, args=(), one=False, commit=False):
        with self.lock:
            cur = self.db.execute(sql, args)
            rows = cur.fetchone() if one else cur.fetchall()
            if commit:
                self.db.commit()
            return rows

    def ex(self, statements):
        """Run several (sql, args) in one transaction."""
        with self.lock:
            for sql, args in statements:
                self.db.execute(sql, args)
            self.db.commit()

    # -- uploaders / participants ---------------------------------------------------
    def touch_uploader(self, uploader, now):
        self.q("INSERT INTO uploaders (id, created_at, last_seen) VALUES (?, ?, ?) "
               "ON CONFLICT(id) DO UPDATE SET last_seen = excluded.last_seen", (uploader, now, now), commit=True)

    def upsert_participant(self, uploader, me_h, me, consents, now):
        public_name = me.get("name") if (consents.get("profile") or consents.get("recommend")) else None
        self.q("INSERT OR REPLACE INTO participants (uploader, guid_h, name, class, race, faction, level, realm, locale, "
               "c_backup, c_profile, c_community, c_recommend, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
               (uploader, me_h, public_name, me.get("class"), me.get("race"), me.get("faction"), me.get("level"),
                me.get("realm"), me.get("locale"), int(bool(consents.get("backup"))), int(bool(consents.get("profile"))),
                int(bool(consents.get("community"))), int(bool(consents.get("recommend"))), now), commit=True)

    def optedout(self, guid_h):
        return bool(self.q("SELECT 1 FROM optout WHERE guid_h = ?", (guid_h,), one=True))

    def optout_set(self):
        return {r[0] for r in self.q("SELECT guid_h FROM optout")}

    def lift_optout(self, guid_h):
        self.q("DELETE FROM optout WHERE guid_h = ?", (guid_h,), commit=True)

    def forget_character(self, guid_h, now):
        """Delete everything about a character and keep it excluded for good."""
        self.ex([("DELETE FROM profiles WHERE guid_h = ?", (guid_h,)),
                 ("DELETE FROM community_members WHERE member_h = ?", (guid_h,)),
                 ("DELETE FROM participants WHERE guid_h = ?", (guid_h,)),
                 ("DELETE FROM census WHERE h = ?", (guid_h,)),
                 ("INSERT OR REPLACE INTO optout (guid_h, at) VALUES (?, ?)", (guid_h, now))])

    def forget_sessions(self, where, args):
        sids = [r[0] for r in self.q("SELECT id FROM community_sessions WHERE " + where, args)]
        self.ex([("DELETE FROM community_members WHERE session_id = ?", (s,)) for s in sids] +
                [("DELETE FROM community_sessions WHERE " + where, args)])

    def forget_uploader(self, uploader):
        self.forget_sessions("uploader = ?", (uploader,))
        self.ex([("DELETE FROM profiles WHERE uploader = ?", (uploader,)),
                 ("DELETE FROM participants WHERE uploader = ?", (uploader,)),
                 ("DELETE FROM lookups WHERE uploader = ?", (uploader,)),
                 ("DELETE FROM census WHERE uploader = ?", (uploader,)),
                 ("DELETE FROM links WHERE uploader = ?", (uploader,)),
                 ("DELETE FROM uploaders WHERE id = ?", (uploader,))])

    # -- profiles ---------------------------------------------------------------------
    def set_profile(self, guid_h, uploader, items_json, now):
        self.q("INSERT INTO profiles (guid_h, uploader, items, updated_at) VALUES (?, ?, ?, ?) "
               "ON CONFLICT(guid_h) DO UPDATE SET uploader = excluded.uploader, items = excluded.items, updated_at = excluded.updated_at",
               (guid_h, uploader, items_json, now), commit=True)

    def profile_row(self, guid_h):
        r = self.q("SELECT items, official, official_at FROM profiles WHERE guid_h = ?", (guid_h,), one=True)
        return dict(r) if r else None

    def set_official(self, guid_h, official_json, now):
        self.q("UPDATE profiles SET official = ?, official_at = ? WHERE guid_h = ?", (official_json, now, guid_h), commit=True)

    def drop_profile(self, uploader):
        self.q("DELETE FROM profiles WHERE uploader = ?", (uploader,), commit=True)

    def profiles_for(self, hashes):
        out = {}
        hashes = list(hashes)
        for i in range(0, len(hashes), 500):
            chunk = hashes[i:i + 500]
            rows = self.q("SELECT p.guid_h, p.items, p.official FROM profiles p JOIN participants pa ON pa.uploader = p.uploader "
                          "WHERE pa.c_profile = 1 AND p.guid_h IN (%s)" % ",".join("?" * len(chunk)), chunk)
            for r in rows:
                out[r[0]] = (r[1], r[2])
        return out

    def count_lookups(self, uploader, day, n):
        self.q("INSERT INTO lookups (uploader, day, n) VALUES (?, ?, ?) ON CONFLICT(uploader, day) DO UPDATE SET n = n + excluded.n",
               (uploader, day, n), commit=True)
        return self.q("SELECT n FROM lookups WHERE uploader = ? AND day = ?", (uploader, day), one=True)[0]

    # -- community ---------------------------------------------------------------------
    def add_session(self, uploader, s, members, now):
        with self.lock:
            cur = self.db.execute("INSERT OR IGNORE INTO community_sessions (uploader, a, b, type, place, kills, received_at) "
                                  "VALUES (?, ?, ?, ?, ?, ?, ?)", (uploader, s["a"], s["b"], s["type"], s["place"], s["kills"], now))
            if cur.rowcount == 0:
                self.db.commit()
                return False
            sid = cur.lastrowid
            for m in members:
                self.db.execute("INSERT OR IGNORE INTO community_members (session_id, member_h, class, race, faction, level, j, l) "
                                "VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                                (sid, m["h"], m["class"], m["race"], m["faction"], m["level"], m["j"], m["l"]))
            self.db.commit()
            return True

    # -- population census ---------------------------------------------------------------
    def add_census(self, uploader, rows, realms, now):
        """rows: [{h, realm, race, faction, class, level, t}]; realms: {id: name or None}."""
        stmts = [("INSERT INTO realms (id, name, type, first_seen) VALUES (?, ?, NULL, ?) "
                  "ON CONFLICT(id) DO UPDATE SET name = COALESCE(excluded.name, realms.name)", (rid, name, now))
                 for rid, name in realms.items()]
        stmts += [("INSERT INTO census (h, realm, race, faction, class, level, seen_at, uploader) VALUES (?, ?, ?, ?, ?, ?, ?, ?) "
                   "ON CONFLICT(h) DO UPDATE SET realm = excluded.realm, race = COALESCE(excluded.race, census.race), "
                   "faction = excluded.faction, class = COALESCE(excluded.class, census.class), "
                   "level = COALESCE(excluded.level, census.level), seen_at = excluded.seen_at, uploader = excluded.uploader "
                   "WHERE excluded.seen_at >= census.seen_at",
                   (r["h"], r["realm"], r["race"], r["faction"], r["class"], r["level"], r["t"], uploader)) for r in rows]
        if stmts:
            self.ex(stmts)

    def set_realm_type(self, rid, rtype):
        with self.lock:
            cur = self.db.execute("UPDATE realms SET type = ? WHERE id = ?", (rtype, rid))
            self.db.commit()
            return cur.rowcount

    def cleanup(self, now):
        self.forget_sessions("b < ?", (now - COMMUNITY_RETENTION,))
        self.q("DELETE FROM census WHERE seen_at < ?", (now - CENSUS_RETENTION,), commit=True)
        for r in self.q("SELECT id FROM backups WHERE updated_at < ?", (now - BACKUP_RETENTION,)):
            self.delete_backup(r[0])

    # -- backups (opaque encrypted blobs) -------------------------------------------------
    def _blob_path(self, bid):
        return os.path.join(self.blob_dir, bid + ".bin")

    def put_backup(self, bid, token_hash, data, now):
        row = self.q("SELECT token_hash FROM backups WHERE id = ?", (bid,), one=True)
        if row and not hmac.compare_digest(row[0], token_hash):
            return False
        if self.blob_dir:
            os.makedirs(self.blob_dir, exist_ok=True)
            tmp = self._blob_path(bid) + ".tmp"
            with open(tmp, "wb") as f:
                f.write(data)
            os.replace(tmp, self._blob_path(bid))
        else:
            self._mem_blobs[bid] = data
        self.q("INSERT INTO backups (id, token_hash, size, created_at, updated_at) VALUES (?, ?, ?, ?, ?) "
               "ON CONFLICT(id) DO UPDATE SET size = excluded.size, updated_at = excluded.updated_at",
               (bid, token_hash, len(data), now, now), commit=True)
        return True

    def get_backup(self, bid):
        row = self.q("SELECT size, updated_at FROM backups WHERE id = ?", (bid,), one=True)
        if not row:
            return None, None
        if self.blob_dir:
            try:
                with open(self._blob_path(bid), "rb") as f:
                    return f.read(), row[1]
            except OSError:
                return None, None
        return self._mem_blobs.get(bid), row[1]

    def delete_backup(self, bid, token_hash=None):
        row = self.q("SELECT token_hash FROM backups WHERE id = ?", (bid,), one=True)
        if not row or (token_hash is not None and not hmac.compare_digest(row[0], token_hash)):
            return False
        if self.blob_dir:
            try:
                os.remove(self._blob_path(bid))
            except OSError:
                pass
        self._mem_blobs.pop(bid, None)
        self.q("DELETE FROM backups WHERE id = ?", (bid,), commit=True)
        return True

    # -- Battle.net identity ------------------------------------------------------------------
    def create_state(self, state, uploader, redirect, region, now, kind="link"):
        self.ex([("DELETE FROM oauth_states WHERE created_at < ?", (now - 900,)),
                 ("INSERT INTO oauth_states (state, uploader, redirect, region, created_at, kind) VALUES (?, ?, ?, ?, ?, ?)",
                  (state, uploader, redirect, region, now, kind))])

    def pop_state(self, state, now):
        with self.lock:
            r = self.db.execute("SELECT uploader, redirect, region, created_at, kind FROM oauth_states WHERE state = ?", (state,)).fetchone()
            self.db.execute("DELETE FROM oauth_states WHERE state = ?", (state,))
            self.db.commit()
        if not r or now - r[3] > 900:
            return None
        return {"uploader": r[0], "redirect": r[1], "region": r[2], "kind": r[4]}

    def link(self, uploader, account, region, characters, now):
        stmts = []
        if uploader:
            stmts.append(("INSERT OR REPLACE INTO links (uploader, account, region, linked_at) VALUES (?, ?, ?, ?)",
                          (uploader, account, region, now)))
        for c in characters:   # c: {h, name, realm_slug}
            stmts.append(("INSERT OR REPLACE INTO owned (guid_h, account, name, realm_slug, region, verified_at) VALUES (?, ?, ?, ?, ?, ?)",
                          (c["h"], account, c.get("name"), c.get("realm_slug"), region, now)))
        if stmts:
            self.ex(stmts)

    def link_of(self, uploader):
        r = self.q("SELECT account, region, linked_at FROM links WHERE uploader = ?", (uploader,), one=True)
        return {"account": r[0], "region": r[1], "linked_at": r[2]} if r else None

    def owned_by(self, account):
        return [dict(r) for r in self.q("SELECT guid_h, name, realm_slug, region FROM owned WHERE account = ?", (account,))]

    def owner_of(self, guid_h):
        r = self.q("SELECT account, name, realm_slug, region FROM owned WHERE guid_h = ?", (guid_h,), one=True)
        return dict(r) if r else None

    def uploaders_of(self, account):
        return [r[0] for r in self.q("SELECT uploader FROM links WHERE account = ?", (account,))]

    def forget_account(self, account):
        for up in self.uploaders_of(account):
            self.forget_uploader(up)
        self.ex([("DELETE FROM links WHERE account = ?", (account,)), ("DELETE FROM owned WHERE account = ?", (account,)),
                 ("DELETE FROM me_sessions WHERE account = ?", (account,))])

    # -- feedback ------------------------------------------------------------------------------
    def feedback_recent_count(self, install, since):
        return self.q("SELECT count(*) FROM feedback WHERE install = ? AND received_at >= ?", (install, since), one=True)[0]

    def add_feedback(self, install, item, now):
        with self.lock:
            cur = self.db.execute("INSERT OR IGNORE INTO feedback (id, install, kind, text, version, diag, t, received_at, status, reply, updated_at) "
                                  "VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'received', NULL, ?)",
                                  (item["id"], install, item["kind"], item["text"], item["version"], item["diag"], item["t"], now, now))
            self.db.commit()
            return cur.rowcount

    def feedback_statuses(self, install):
        rows = self.q("SELECT id, status, reply FROM feedback WHERE install = ?", (install,))
        return {r[0]: ({"status": r[1], "reply": r[2]} if r[2] else {"status": r[1]}) for r in rows}

    def list_feedback(self, status=None, limit=200):
        sql, args = "SELECT id, kind, text, version, diag, t, received_at, status, reply FROM feedback", []
        if status:
            sql, args = sql + " WHERE status = ?", [status]
        return [dict(r) for r in self.q(sql + " ORDER BY received_at DESC LIMIT ?", args + [limit])]

    def update_feedback(self, fid, status, reply, now):
        with self.lock:
            cur = self.db.execute("UPDATE feedback SET status = ?, reply = COALESCE(?, reply), updated_at = ? WHERE id = ?",
                                  (status, reply, now, fid))
            self.db.commit()
            return cur.rowcount
