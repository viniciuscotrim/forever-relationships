"""Trust Advisor network aggregation (GDD 6.8, 11). Pure functions, no I/O.

Turns raw witness reports into incidents and decides which ones count.
The fairness rules ARE the product, so they live here, small and tested:

  * A report about yourself (witness == subject) never counts.
  * Reports of the same (subject, dimension, kind) within `matchWindowSeconds`
    of the first report are one incident. Each uploader counts once per incident.
  * Positive incidents (x >= 1) count with one witness.
  * Negative or partial incidents (x < 1) count only with >= minWitnesses
    distinct uploaders from >= minGuilds distinct guild groups.
    Witnesses without a guild form ONE group ("no guild"), so unguilded
    sockpuppets cannot satisfy the guild-diversity rule on their own.
  * Open or upheld disputes exclude the incident. Rejected disputes do not.
  * Opted-out (deleted) players produce no incidents at all.
"""
import hashlib
from statistics import median

PROTOCOL_VERSION = 1

# Published, locked protocol parameters (mirror of the addon's net.* keys).
PARAMS = {
    "net.protocolVersion": PROTOCOL_VERSION,
    "net.minWitnesses": 2,
    "net.minGuilds": 2,
    "net.matchWindowSeconds": 600,
}

ELIGIBLE = {"finish", "ready", "loot", "carry", "generosity", "teach", "craft", "help", "hc", "endorse"}

NO_GUILD = "\u0000no-guild"


def incident_id(subject, dim, kind, t0):
    raw = "%s|%s|%s|%d" % (subject, dim, kind, int(t0))
    return hashlib.sha1(raw.encode("utf-8")).hexdigest()[:16]


def cluster(reports, window):
    """Group reports (same subject/dim/kind) whose time is within `window` of the
    cluster's first report. Returns list of lists."""
    by_key = {}
    for r in reports:
        by_key.setdefault((r["s"], r["d"], r["k"]), []).append(r)
    out = []
    for key in sorted(by_key):
        rows = sorted(by_key[key], key=lambda r: r["t"])
        cur = []
        for r in rows:
            if cur and r["t"] - cur[0]["t"] > window:
                out.append(cur)
                cur = []
            cur.append(r)
        if cur:
            out.append(cur)
    return out


def _dispute_for(inc, disputes, window):
    for d in disputes:
        if d["subject"] == inc["s"] and d["d"] == inc["d"] and d["k"] == inc["k"] and abs(d["t"] - inc["t0"]) <= window:
            return d
    return None


def build_incidents(reports, params=None, disputes=(), opted_out=(), self_claims=None):
    """reports: dicts with uploader, witness, wguild, s, d, x, m, t, k.
    self_claims: {uploader: set(guids)} characters each uploader claims as their own.
    Returns {subject: [incident, ...]} with every incident (verified or not)."""
    p = dict(PARAMS)
    if params:
        p.update(params)
    window = p["net.matchWindowSeconds"]
    opted_out = set(opted_out)
    self_claims = self_claims or {}
    clean = []
    for r in reports:
        if r["s"] in opted_out or r["d"] not in ELIGIBLE:
            continue
        if r["witness"] == r["s"] or r["s"] in self_claims.get(r["uploader"], ()):
            continue  # nobody witnesses themselves
        clean.append(r)

    result = {}
    for group in cluster(clean, window):
        first = group[0]
        uploaders = {}
        for r in group:
            uploaders.setdefault(r["uploader"], r)
        guilds = {(r.get("wguild") or NO_GUILD) for r in uploaders.values()}
        x = median([r["x"] for r in uploaders.values()])
        m = median([r["m"] for r in uploaders.values()])
        inc = {
            "id": incident_id(first["s"], first["d"], first["k"], first["t"]),
            "s": first["s"], "d": first["d"], "k": first["k"],
            "t0": first["t"], "t": int(median([r["t"] for r in group])),
            "x": x, "m": m, "w": len(uploaders), "g": len(guilds),
        }
        if x >= 1:
            inc["verified"] = inc["w"] >= 1
        else:
            inc["verified"] = inc["w"] >= p["net.minWitnesses"] and inc["g"] >= p["net.minGuilds"]
        dispute = _dispute_for(inc, disputes, window)
        inc["disputed"] = bool(dispute and dispute["status"] in ("open", "upheld"))
        inc["disputeStatus"] = dispute["status"] if dispute else None
        result.setdefault(inc["s"], []).append(inc)
    return result


def public_view(incidents):
    """What everyone may see: verified, undisputed incidents, no witness identities."""
    out = []
    for inc in incidents:
        if inc["verified"] and not inc["disputed"]:
            out.append({"id": inc["id"], "d": inc["d"], "x": inc["x"], "m": inc["m"], "t": inc["t"], "w": inc["w"], "g": inc["g"]})
    return out


def self_view(incidents):
    """What the subject may see about themselves: everything, with counts."""
    return [{"id": i["id"], "d": i["d"], "x": i["x"], "m": i["m"], "t": i["t"], "w": i["w"], "g": i["g"],
             "verified": i["verified"], "disputed": i["disputed"], "disputeStatus": i["disputeStatus"]}
            for i in incidents]
