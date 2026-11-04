# Admin cockpit

**URL:** https://trustadvisor.gameplaybr.com.br/admindash/ (not indexed, not linked publicly)

It reads live from the network database:
- **Cockpit:** participants, activity, Battle.net links, feedback and disputes, plus 30-day trends and top errors.
- **Demographics:** faction, race, class, level, realm, language and region of participants' *own* characters.
- **Network:** the verification funnel per trait, and witnesses per incident.
- **Feedback:** read, set status, and reply. The reply reaches the player in game through their companion.
- **Disputes:** uphold or reject.

## Sign-in: two factors, both required
1. **A passkey** with Touch ID (Mac) or Face ID (iPhone). It's stored in Apple Passwords and synced by your Apple Account, so creating it on the Mac makes it available on the iPhone.
2. **A 6-digit code** from Apple Passwords (TOTP, RFC 6238).

Session security:
- the session cookie is `HttpOnly; Secure; SameSite=Strict`, scoped to `/admindash`, and lasts 12 h;
- 5 failures in 15 minutes lock sign-in for 15 minutes;
- the CSP allows no external code, and every POST must come from the cockpit's own origin.

## Enrollment (one time, or to add a device)
```sh
ssh root@VPS 'docker exec trustadvisor-net python -m trustnet.admin_cli setup-link'
```
This prints a single-use link that's valid for 30 minutes. Open it in Safari on the Mac:
1. Create the passkey with Touch ID.
2. Click **Add to Passwords**, or enter the setup key in Passwords.
3. Type the current code.

To start over: `python -m trustnet.admin_cli revoke-all`, then create a new setup link.

## Demo data
```sh
ssh root@VPS 'docker exec trustadvisor-net python -m trustnet.demo seed'    # fills every view
ssh root@VPS 'docker exec trustadvisor-net python -m trustnet.demo clean'   # removes every demo row
```
Demo rows are marked (ids starting with `demo-`, characters on the fictional realm `9999`). The cockpit shows a banner while any exist.
