#!/usr/bin/env python3
"""Translation keys of the addon, and the check that every language has them.

The English text is the key (FR.L["Time together"]). Keys are collected from:
  - L["..."] / FR.L["..."] literals and FR.Plural(n, "...", "...") in the addon code;
  - data tables whose labels are translated on display (EXTRA_PATTERNS below);
  - identifiers shown through L[...] at run time (EXTRA_KEYS below).
Usage:
  python3 tools/locale_keys.py            # list every key (one per line)
  python3 tools/locale_keys.py --json     # keys as a JSON list
  python3 tools/locale_keys.py --check    # every Locales/<code>.lua has every key, same placeholders (install.sh)
  python3 tools/locale_keys.py --missing ptBR   # keys a language still lacks
"""
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ADDON = os.path.join(ROOT, "ForeverRelationships")
LOCALES = ["deDE", "esES", "esMX", "frFR", "itIT", "koKR", "ptBR", "ruRU", "zhCN", "zhTW"]

STR = r'"((?:[^"\\]|\\.)*)"'
PATTERNS = [
    re.compile(r'\bL\[' + STR + r'\]'),
    re.compile(r'\bFR\.L\[' + STR + r'\]'),
    re.compile(r'\bFR\.T\(' + STR + r'\)'),
]
PLURAL = re.compile(r'\b(?:FR\.Plural|P)\([^,()]+(?:\([^()]*\))?[^,()]*,\s*' + STR + r'\s*,\s*' + STR + r'\s*\)')
# file -> regexes whose group 1 is a key (labels translated on display)
EXTRA_PATTERNS = {
    "Relationship/Stats.lua": [r'label = ' + STR, r'\{ "(%d [^"]+)", "(%d [^"]+)" \}'],
    "Relationship/Groups.lua": [r'name = ' + STR, r'desc = ' + STR],
    "UI/MainWindow.lua": [r'label = ' + STR],
    "UI/PrivacyView.lua": [r'label = ' + STR, r'note = ' + STR, r'head = ' + STR, r'^\s{4}"((?:[^"\\]|\\.)+)",\s*$', r'^\s{2}"((?:[^"\\]|\\.)+)",\s*$'],
    "UI/Welcome.lua": [r'label = ' + STR, r'note = ' + STR],
    "Core/Params.lua": [r'def\("[^"]+", "[^"]+", [^,]+, ' + STR],
    "Core/Slash.lua": [r'^\s{2}"(/fr[^"]*|Companion app: [^"]*)",\s*$'],
    "Cloud/Cloud.lua": [r'^\s{2}(?:off|waiting|missing|stale|ok) = ' + STR],
    "UI/Feedback.lua": [r'\{ "[0-9a-f]{6}", ' + STR + r' \}'],
    "UI/Widgets.lua": [],
    "UI/GroupPicker.lua": [r'text = ' + STR],
    "Comms/Announce.lua": [r'Announce\.TEXT = ' + STR],
}
CAPTURE = re.compile(r'RegisterCapture\("[^"]+",\s*' + STR)
POPUP = re.compile(r'UI\.Popup\("[^"]+", \{\s*text = ' + STR, re.S)
# identifiers shown with L[...] at run time
EXTRA_KEYS = [
    # time-of-day buckets (Stats HOURS), group types, leave reasons, help kinds, log filters
    "mornings", "afternoons", "evenings", "late nights", "quest", "dungeon", "raid", "voluntary", "removed",
    "buff", "rez", "summon", "portal", "act", "all", "game", "peer", "human", "questie",
    # races (census, rivals)
    "Human", "Dwarf", "Night Elf", "Gnome", "Draenei", "Orc", "Undead", "Tauren", "Troll", "Blood Elf", "Unknown",
]


def lua_unescape(s):
    return s.encode("utf-8").decode("unicode_escape").encode("latin-1").decode("utf-8") if "\\" in s else s


def keys():
    found = []
    seen = set()

    def add(k):
        k = lua_unescape(k)
        if k and k not in seen:
            seen.add(k)
            found.append(k)

    for dirpath, _, files in os.walk(ADDON):
        rel_dir = os.path.relpath(dirpath, ADDON)
        if rel_dir.startswith(("Locales", "Tests")):
            continue
        for fn in sorted(files):
            if not fn.endswith(".lua"):
                continue
            rel = os.path.normpath(os.path.join(rel_dir, fn)).replace(os.sep, "/")
            text = open(os.path.join(dirpath, fn), encoding="utf-8").read()
            for p in PATTERNS:
                for m in p.finditer(text):
                    add(m.group(1))
            for m in PLURAL.finditer(text):
                add(m.group(1)); add(m.group(2))
            for m in CAPTURE.finditer(text):
                add(m.group(1))
            for m in POPUP.finditer(text):
                add(m.group(1))
            for pat in EXTRA_PATTERNS.get(rel, []):
                for m in re.finditer(pat, text, re.M):
                    for g in m.groups():
                        add(g)
    for k in EXTRA_KEYS:
        add(k)
    return found


ENTRY = re.compile(r'^\s*\[' + STR + r'\]\s*=\s*' + STR + r',?\s*$', re.M)


def locale_table(code):
    path = os.path.join(ADDON, "Locales", code + ".lua")
    if not os.path.exists(path):
        return None
    return {lua_unescape(k): lua_unescape(v) for k, v in ENTRY.findall(open(path, encoding="utf-8").read())}


def placeholders(s):
    # same placeholders in the same order: Lua's string.format has no positional arguments
    return re.findall(r'%[-+0-9.]*[sdif%]', s)


def check():
    ks = keys()
    problems = []
    for code in LOCALES:
        t = locale_table(code)
        if t is None:
            problems.append("%s: Locales/%s.lua missing" % (code, code))
            continue
        missing = [k for k in ks if k not in t]
        if missing:
            problems.append("%s: %d keys missing, e.g. %r" % (code, len(missing), missing[0]))
        for k, v in t.items():
            if k not in ks:
                problems.append("%s: stale key no longer used: %r" % (code, k))
            elif placeholders(k) != placeholders(v):
                problems.append("%s: placeholders differ in %r -> %r" % (code, k, v))
            if "|r" in k and v.count("|r") != k.count("|r"):
                problems.append("%s: color codes differ in %r" % (code, k))
    return ks, problems


if __name__ == "__main__":
    arg = sys.argv[1] if len(sys.argv) > 1 else ""
    if arg == "--check":
        ks, problems = check()
        for p in problems:
            print(p)
        if problems:
            sys.exit(1)
        print("Translations complete: %d keys x %d languages" % (len(ks), len(LOCALES)))
    elif arg == "--missing":
        t = locale_table(sys.argv[2]) or {}
        for k in keys():
            if k not in t:
                print(k)
    elif arg == "--json":
        print(json.dumps(keys(), ensure_ascii=False, indent=1))
    else:
        for k in keys():
            print(k)
