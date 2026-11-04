"""Demo data for the admin cockpit (protocol v2), clearly marked and fully removable.
  python -m frnet.demo seed | clean | count
Every demo row is identifiable: uploaders/accounts/characters/feedback start with "demo-".
"""
import json
import os
import random
import sys
import time

from .store import Store

FACTIONS = {
    "Alliance": {"Human": ["Warrior", "Paladin", "Rogue", "Priest", "Mage", "Warlock"],
                 "Dwarf": ["Warrior", "Paladin", "Hunter", "Rogue", "Priest"],
                 "Night Elf": ["Warrior", "Hunter", "Rogue", "Priest", "Druid"],
                 "Gnome": ["Warrior", "Rogue", "Mage", "Warlock"]},
    "Horde": {"Orc": ["Warrior", "Hunter", "Rogue", "Shaman", "Warlock"],
              "Undead": ["Warrior", "Rogue", "Priest", "Mage", "Warlock"],
              "Tauren": ["Warrior", "Hunter", "Shaman", "Druid"],
              "Troll": ["Warrior", "Hunter", "Rogue", "Priest", "Shaman", "Mage"]},
}
REALMS = ["Forever US-1 PvE", "Forever US-1 PvP", "Forever US-2 PvE", "Forever EU-4 PvE", "Forever EU-4 PvP", "Forever BR-1 PvE"]
LOCALES = ["enUS"] * 6 + ["ptBR"] * 3 + ["esMX", "deDE", "frFR", "enGB"]
PLACES = {"dungeon": ["Deadmines", "Wailing Caverns", "Shadowfang Keep", "Scarlet Monastery", "Uldaman", "Zul'Farrak", "Maraudon",
                      "Blackrock Depths", "Stratholme", "Scholomance"],
          "raid": ["Molten Core", "Onyxia's Lair", "Blackwing Lair"],
          "quest": ["Westfall", "Stranglethorn Vale", "The Barrens", "Duskwood", "Arathi Highlands", "Tanaris", "Feralas", "Un'Goro Crater"]}
SYL = ["ka", "ri", "do", "mel", "thar", "ion", "va", "lor", "eth", "an", "gra", "mo", "sil", "dra", "nia", "bek"]
BUGS = ["Tooltip shows nothing for a groupmate I played with yesterday", "Relationship window empty after /reload",
        "Error after /reload while in a dungeon", "Companion says not detected even though it runs",
        "Questie completion not picked up from a ptBR partner", "Backup restore asked for the code twice", ""]
IDEAS = ["A minimap button would be great", "Show 'last seen together' in LFG", "Portuguese translation please!",
         "Let me export a Relationship card as text", "Weekly summary of who I grouped with",
         "Credit warlock summon helpers in raids", "Color-blind friendly colors", "Show achievements on profiles"]
ERRORS = ["ForeverRelationships/UI/Tooltip.lua:41: attempt to index a nil value", "ForeverRelationships/Capture/Ready.lua:58: bad argument #1 to 'pairs'",
          "ForeverRelationships/Core/Sessions.lua:212: attempt to compare number with nil"]


def _char(r):
    fac = r.choice(["Alliance", "Horde"])
    race = r.choice(list(FACTIONS[fac]))
    return fac, race, r.choice(FACTIONS[fac][race]), (60 if r.random() < 0.28 else max(1, min(59, int(r.gauss(32, 15)))))


def seed(store, now=None, n_uploaders=140, n_population=620):
    r = random.Random(42)
    now = int(now or time.time())
    day = 86400
    q = []
    parts = []
    for i in range(n_uploaders):
        uid, gh = "demo-u%03d" % i, "demo-g%03d" % i
        created = now - int((r.random() ** 1.6) * 30 * day) - 3 * day
        last = min(now, created + r.randint(0, 33 * day))
        fac, race, cls, lvl = _char(r)
        cons = {"b": r.random() < 0.55, "p": r.random() < 0.6, "c": r.random() < 0.75, "r": r.random() < 0.4}
        name = "".join(r.choice(SYL) for _ in range(r.randint(2, 3))).capitalize()
        realm = r.choice(REALMS)
        q.append(("INSERT OR REPLACE INTO uploaders (id, created_at, last_seen) VALUES (?, ?, ?)", (uid, created, last)))
        q.append(("INSERT OR REPLACE INTO participants (uploader, guid_h, name, class, race, faction, level, realm, locale, c_backup, c_profile, "
                  "c_community, c_recommend, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                  (uid, gh, name if (cons["p"] or cons["r"]) else None, cls, race, fac, lvl, realm, r.choice(LOCALES),
                   int(cons["b"]), int(cons["p"]), int(cons["c"]), int(cons["r"]), last)))
        if cons["p"]:
            q.append(("INSERT OR REPLACE INTO profiles (guid_h, uploader, items, official, official_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)",
                      (gh, uid, json.dumps({"hours": r.randint(5, 400), "dungeons": r.randint(0, 120)}),
                       json.dumps({"level": lvl, "achievementPoints": r.randint(100, 4000)}) if r.random() < 0.5 else None, last, last)))
        if cons["b"]:
            q.append(("INSERT OR REPLACE INTO backups (id, token_hash, size, created_at, updated_at) VALUES (?, ?, ?, ?, ?)",
                      ("demo-b%03d" % i, "x", r.randint(80000, 4000000), created, last)))
        if r.random() < 0.62:
            acct = "demo-acct%03d" % i
            q.append(("INSERT OR REPLACE INTO links (uploader, account, region, linked_at) VALUES (?, ?, ?, ?)",
                      (uid, acct, "eu" if "EU" in realm else "us", created + 600)))
            q.append(("INSERT OR REPLACE INTO owned (guid_h, account, name, realm_slug, region, verified_at) VALUES (?, ?, ?, ?, ?, ?)",
                      (gh, acct, name, realm.lower().replace(" ", "-"), "us", created + 600)))
        parts.append((uid, gh, fac, cls, race, lvl, cons["c"]))
    population = []
    for j in range(n_population):
        fac, race, cls, lvl = _char(r)
        population.append(("demo-m%04d" % j, fac, cls, race, lvl))
    store.ex(q)
    sharers = [p for p in parts if p[6]]
    for g in range(950):
        uid, gh, fac, cls, race, lvl, _ = r.choice(sharers)
        gtype = r.choices(["quest", "dungeon", "raid"], weights=[5, 4, 1])[0]
        a = now - r.randint(0, 29 * day) - r.randint(0, day)
        b = a + r.randint(900, 3 * 3600)
        size = {"quest": r.randint(2, 3), "dungeon": 5, "raid": r.randint(15, 40)}[gtype]
        same_faction = [m for m in population if m[1] == fac]
        others = r.sample(same_faction, min(size - 1, len(same_faction)))
        members = [{"h": gh, "class": cls, "race": race, "faction": fac, "level": lvl, "j": a, "l": b}] + \
                  [{"h": m[0], "class": m[2], "race": m[3], "faction": m[1], "level": m[4], "j": a, "l": b} for m in others]
        store.add_session(uid, {"a": a, "b": b, "type": gtype, "place": r.choice(PLACES[gtype]),
                                "kills": 0 if gtype == "quest" else r.randint(1, 10)}, members, min(now, b + 600))
    fq = []
    statuses = ["received"] * 5 + ["planned", "fixed", "done", "wontfix", "duplicate"]
    for i in range(48):
        kind = "bug" if r.random() < 0.45 else "idea"
        st = r.choice(statuses)
        diag = {"addon": r.choice(["0.3.0", "0.4.0", "0.4.0"]), "build": "70755", "interface": "16001", "locale": r.choice(LOCALES),
                "companion": r.choice(["ok", "ok", "missing", "off"]), "companionVersion": r.choice(["0.4.0", "0.3.4", None]),
                "layers": r.choice(["", "C", "PC", "BPC"]), "players": r.randint(5, 400), "events": r.randint(100, 20000),
                "unavailable": ["ready: auras are secret values on this client"] if r.random() < 0.2 else [],
                "errors": ["x%d %s" % (r.randint(1, 9), r.choice(ERRORS))] if kind == "bug" and r.random() < 0.6 else []}
        rec = now - r.randint(0, 25 * day)
        fq.append(("INSERT OR REPLACE INTO feedback (id, install, kind, text, version, diag, t, received_at, status, reply, updated_at) "
                   "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                   ("demo-fb%03d" % i, "demo-install%02d" % (i % 30), kind, r.choice(BUGS if kind == "bug" else IDEAS), diag["addon"],
                    json.dumps(diag), rec - 300, rec, st,
                    {"planned": "On the roadmap, thanks!", "fixed": "Fixed in the next version.",
                     "wontfix": "Not planned, but thanks for the idea."}.get(st), rec + 3600)))
    for i in range(6):
        fq.append(("INSERT OR REPLACE INTO optout (guid_h, at) VALUES (?, ?)", ("demo-o%02d" % i, now - i * day)))
    store.ex(fq)
    return count(store)


def clean(store):
    store.forget_sessions("uploader LIKE 'demo-%'", ())
    store.ex([("DELETE FROM community_members WHERE member_h LIKE 'demo-%'", ()),
              ("DELETE FROM participants WHERE uploader LIKE 'demo-%'", ()),
              ("DELETE FROM profiles WHERE uploader LIKE 'demo-%'", ()),
              ("DELETE FROM backups WHERE id LIKE 'demo-%'", ()),
              ("DELETE FROM links WHERE uploader LIKE 'demo-%'", ()),
              ("DELETE FROM owned WHERE account LIKE 'demo-%'", ()),
              ("DELETE FROM uploaders WHERE id LIKE 'demo-%'", ()),
              ("DELETE FROM feedback WHERE id LIKE 'demo-%'", ()),
              ("DELETE FROM optout WHERE guid_h LIKE 'demo-%'", ())])
    return count(store)


def count(store):
    c = lambda sql: store.q(sql, one=True)[0]
    return {"participants": c("SELECT count(*) FROM participants WHERE uploader LIKE 'demo-%'"),
            "communitySessions": c("SELECT count(*) FROM community_sessions WHERE uploader LIKE 'demo-%'"),
            "feedback": c("SELECT count(*) FROM feedback WHERE id LIKE 'demo-%'")}


def main(argv):
    store = Store(os.environ.get("FR_DB", "frnet.sqlite3"))
    cmd = argv[0] if argv else "count"
    if cmd == "seed":
        print("seeded:", seed(store))
    elif cmd == "clean":
        print("after clean:", clean(store))
    else:
        print("demo rows:", count(store))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
