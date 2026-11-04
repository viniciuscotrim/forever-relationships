"""Admin CLI (run inside the container, as root on the VPS):
  python -m frnet.admin_cli setup-link     # one-time enrollment link, valid 30 minutes
  python -m frnet.admin_cli revoke-all     # remove passkeys, TOTP and sessions (re-enroll after)
"""
import os
import sys
from urllib.parse import urlparse

from .admin import Admin
from .store import Store


def main(argv):
    store = Store(os.environ.get("FR_DB", "frnet.sqlite3"))
    origin = os.environ.get("FR_ADMIN_ORIGIN", "https://forever.gameplaybr.com.br").rstrip("/")
    admin = Admin(store, None, urlparse(origin).hostname, origin)
    cmd = argv[0] if argv else ""
    if cmd == "setup-link":
        print(admin.create_setup_link())
        print("Valid for 30 minutes, single use. Open it in Safari on your Mac.")
    elif cmd == "revoke-all":
        with store.lock:
            for t in ("admin_credentials", "admin_kv", "admin_sessions", "admin_setup"):
                store.db.execute("DELETE FROM %s" % t)
            store.db.commit()
        print("All admin passkeys, TOTP and sessions removed. Create a new setup link to enroll again.")
    else:
        print(__doc__)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
