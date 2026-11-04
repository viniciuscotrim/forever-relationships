#!/usr/bin/env python3
"""Keep every public description identical.

branding/curseforge-description.md is the single source of truth. Its
PUBLIC-DESCRIPTION block is copied verbatim into README.md (between the same
markers). Usage:
  python3 tools/sync_docs.py          # rewrite README.md from the source
  python3 tools/sync_docs.py --check  # exit 1 if README.md has drifted (used by install.sh)
  python3 tools/sync_docs.py --summary  # print the Summary (CurseForge + GitHub description)
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE = os.path.join(ROOT, "branding", "curseforge-description.md")
TARGETS = [os.path.join(ROOT, "README.md")]
BLOCK = re.compile(r"<!-- PUBLIC-DESCRIPTION:START -->.*?<!-- PUBLIC-DESCRIPTION:END -->", re.S)


def source_block():
    m = BLOCK.search(open(SOURCE, encoding="utf-8").read())
    if not m:
        sys.exit("no PUBLIC-DESCRIPTION block in %s" % SOURCE)
    return m.group(0)


def summary():
    text = open(SOURCE, encoding="utf-8").read()
    m = re.search(r"## Summary \(short field\)\s+(.+?)\n\n", text, re.S)
    return m.group(1).strip()


def main(argv):
    block = source_block()
    if "--summary" in argv:
        print(summary())
        return 0
    drift = []
    for path in TARGETS:
        text = open(path, encoding="utf-8").read()
        if not BLOCK.search(text):
            sys.exit("no PUBLIC-DESCRIPTION markers in %s" % path)
        new = BLOCK.sub(lambda _: block, text)
        if new != text:
            drift.append(os.path.relpath(path, ROOT))
            if "--check" not in argv:
                open(path, "w", encoding="utf-8").write(new)
    if "--check" in argv:
        if drift:
            print("Public description drifted in: %s. Run: python3 tools/sync_docs.py" % ", ".join(drift))
            return 1
        print("Public descriptions in sync")
        return 0
    print("Updated: %s" % (", ".join(drift) if drift else "nothing (already in sync)"))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
