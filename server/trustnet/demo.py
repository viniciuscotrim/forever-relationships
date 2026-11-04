"""Demo data for the admin cockpit, clearly marked and fully removable.
  python -m trustnet.demo seed     # adds coherent fake data (realm 9999, ids starting with demo-)
  python -m trustnet.demo clean    # removes every demo row
  python -m trustnet.demo count
Demo uploaders/accounts/feedback ids start with "demo-"; demo characters and
players use the fictional realm id 9999 (Player-9999-...).
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
GUILDS = ["Demo Steadfast", "Demo Lantern", "Demo Ironbark", "Demo Last Light", "Demo Moonfall", "Demo Ashen Pact",
          "Demo Thornwatch", "Demo Bloodhoof", "Demo Silver Oath", "Demo Nightshade", ""]
SYL = ["ka", "ri", "do", "mel", "thar", "ion", "va", "lor", "eth", "an", "gra", "mo", "sil", "dra", "nia", "bek"]
DIMS_POS = ["finish", "finish", "finish", "ready", "generosity", "teach", "help", "craft", "loot", "carry", "hc"]
BUGS = ["Tooltip line missing on LFG listings for some leaders", "Ready check rows not recorded in my raid",
        "Error after /reload while in a dungeon", "Companion says not detected even though it runs",
        "Questie completion not picked up from a ptBR partner", "Endorsement prompt appeared during a boss pull",
        "Trade with enchant didn't count as crafting", ""]
IDEAS = ["A minimap button would be great", "Show the network band directly on the tooltip",
         "Portuguese translation please!", "Let me export a player's card as text", "Add a filter for Exemplary players",
         "Weekly summary of who I grouped with", "Credit warlock summon helpers in raids", "Color-blind friendly band colors"]
ERRORS = ["TrustAdvisor/UI/Tooltip.lua:41: attempt to index a nil value", "TrustAdvisor/Capture/Ready.lua:58: bad argument #1 to 'pairs'",
          "TrustAdvisor/Core/Sessions.lua:212: attempt to compare number with nil"]


def name(r):
    return "".join(r.choice(SYL) for _ in range(r.randint(2, 3))).capitalize()


def seed(store, now=None, n_uploaders=140, n_players=420):
    r = random.Random(42)
    now = int(now or time.time())
    day = 86400
    db = store.db
    with store.lock:
        uploaders = []
        for i in range(n_uploaders):
            uid = "demo-u%03d" % i
            created = now - int((r.random() ** 1.6) * 30 * day) - 3 * day
            last = min(now, created + r.randint(0, 33 * day))
            fac = r.choice(["Alliance", "Horde"])
            race = r.choice(list(FACTIONS[fac]))
            cls = r.choice(FACTIONS[fac][race])
            lvl = 60 if r.random() < 0.28 else max(1, min(59, int(r.gauss(32, 15))))
            guid = "Player-9999-%08X" % (0x10000 + i)
            guild = r.choice(GUILDS)
            db.execute("INSERT OR REPLACE INTO uploaders (id, created_at, last_seen) VALUES (?, ?, ?)", (uid, created, last))
            db.execute("INSERT OR REPLACE INTO characters (uploader, guid, name, guild, seen_at, class, race, faction, level, realm, locale) "
                       "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                       (uid, guid, name(r), guild, last, cls, race, fac, lvl, r.choice(REALMS), r.choice(LOCALES)))
            if r.random() < 0.62:
                acct = "demo-acct%03d" % i
                db.execute("INSERT OR REPLACE INTO links (uploader, account, region, linked_at) VALUES (?, ?, ?, ?)",
                           (uid, acct, "eu" if "EU" in guild + str(r.random() < 0.3) else r.choice(["us", "us", "us", "eu"]), created + 600))
                db.execute("INSERT OR REPLACE INTO owned (guid, account, verified_at) VALUES (?, ?, ?)", (guid, acct, created + 600))
            uploaders.append((uid, guid, guild))
        players = ["Player-9999-%08X" % (0x200000 + j) for j in range(n_players)]
        # group sessions: 3-5 uploaders + 1-3 strangers, with presence and reports
        for g in range(900):
            t0 = now - r.randint(0, 29 * day) - r.randint(0, day)
            crew = r.sample(uploaders, r.randint(3, 5))
            strangers = r.sample(players, r.randint(1, 3))
            members = [c[1] for c in crew] + strangers
            for uid, _, _ in crew:
                for m in members:
                    db.execute("INSERT OR IGNORE INTO presence (uploader, a, b, member) VALUES (?, ?, ?, ?)", (uid, t0, t0 + 5400, m))
            last_kill = t0 + 5000
            for s in strangers:
                bad = r.random() < 0.07
                dim = "finish" if bad else r.choice(DIMS_POS)
                x, k = (0.0, "finish:0.00:3.00") if bad else (1.0, "%s:1.00:1.00" % dim)
                m = 3.0 if bad else 1.0
                t = last_kill - 1200 if bad else last_kill
                for uid, wguid, wguild in crew:
                    if r.random() < 0.8:
                        db.execute("INSERT OR IGNORE INTO reports (uploader, witness, wguild, s, d, x, m, t, k, received_at) "
                                   "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                                   (uid, wguid, wguild, s, dim, x, m, t + r.randint(0, 40), k, min(now, t + r.randint(600, 2 * day))))
        statuses = ["received"] * 5 + ["planned", "fixed", "done", "wontfix", "duplicate"]
        for i in range(48):
            kind = "bug" if r.random() < 0.45 else "idea"
            text = r.choice(BUGS if kind == "bug" else IDEAS)
            st = r.choice(statuses)
            fac = r.choice(["Alliance", "Horde"])
            diag = {"addon": r.choice(["0.2.0", "0.3.0", "0.3.0", "0.3.0"]), "build": "70755", "interface": "16001",
                    "locale": r.choice(LOCALES), "companion": r.choice(["ok", "ok", "missing", "off"]),
                    "companionVersion": r.choice(["0.3.3", "0.3.2", None]), "network": r.random() < 0.6,
                    "players": r.randint(5, 400), "events": r.randint(100, 20000),
                    "unavailable": ["ready: auras are secret values on this client"] if r.random() < 0.2 else [],
                    "errors": ["x%d %s" % (r.randint(1, 9), r.choice(ERRORS))] if kind == "bug" and r.random() < 0.6 else []}
            rec = now - r.randint(0, 25 * day)
            db.execute("INSERT OR REPLACE INTO feedback (id, install, kind, text, version, diag, t, received_at, status, reply, updated_at) "
                       "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                       ("demo-fb%03d" % i, "demo-install%02d" % (i % 30), kind, text, diag["addon"], json.dumps(diag), rec - 300, rec, st,
                        {"planned": "On the roadmap, thanks!", "fixed": "Fixed in the next version.",
                         "wontfix": "Not planned, but thanks for the idea."}.get(st), rec + 3600))
        for i in range(5):
            db.execute("INSERT OR REPLACE INTO disputes (id, uploader, subject, d, k, t, reason, status, created_at, reviewed_at) "
                       "VALUES (?, ?, ?, 'finish', 'finish:0.00:3.00', ?, ?, ?, ?, NULL)",
                       ("demo-dsp%02d" % i, "demo-u%03d" % i, players[i], now - (i + 1) * day,
                        ["I disconnected, the group knows", "Leader kicked me", "We agreed I'd leave early", "Wrong person", "Lag"][i],
                        "open" if i < 3 else "rejected", now - i * day))
        db.commit()
    return count(store)


def clean(store):
    with store.lock:
        db = store.db
        for sql in ("DELETE FROM reports WHERE uploader LIKE 'demo-%'", "DELETE FROM presence WHERE uploader LIKE 'demo-%'",
                    "DELETE FROM characters WHERE uploader LIKE 'demo-%' OR guid LIKE 'Player-9999-%'",
                    "DELETE FROM links WHERE uploader LIKE 'demo-%'", "DELETE FROM owned WHERE account LIKE 'demo-%'",
                    "DELETE FROM uploaders WHERE id LIKE 'demo-%'", "DELETE FROM feedback WHERE id LIKE 'demo-%'",
                    "DELETE FROM disputes WHERE id LIKE 'demo-%'", "DELETE FROM optout WHERE guid LIKE 'Player-9999-%'"):
            db.execute(sql)
        db.commit()
    return count(store)


def count(store):
    q = lambda sql: store.db.execute(sql).fetchone()[0]
    with store.lock:
        return {"uploaders": q("SELECT count(*) FROM uploaders WHERE id LIKE 'demo-%'"),
                "reports": q("SELECT count(*) FROM reports WHERE uploader LIKE 'demo-%'"),
                "feedback": q("SELECT count(*) FROM feedback WHERE id LIKE 'demo-%'"),
                "disputes": q("SELECT count(*) FROM disputes WHERE id LIKE 'demo-%'")}


def main(argv):
    store = Store(os.environ.get("TA_DB", "trustnet.sqlite3"))
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
