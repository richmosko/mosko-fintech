---
name: dblink-in-a-test-is-a-privilege-boundary
description: A dblink fixture's auth failure is the non-superuser dblink_security_check, not a missing password — and dblink_connect_u / superuser elevation are the make-it-green moves to veto.
metadata:
  type: feedback
---

**The rule.** When a test fixture uses `dblink` and fails with
`password or GSSAPI delegated credentials required`, **read the connstr before accepting any
"add the password" fix** — and treat `dblink_connect_u` and role elevation as veto-shaped, not as
options.

**Why.** Measured at the sec-c re-verification of PR #636 (2026-09-06), `111`'s leg 8-i.

- **The proposed fallback was already the shipped shape.** The brief offered "password in the
  dblink connstr from the test env" as a fallback; `ee597b1:supabase/tests/rls/111_audit_log_rls.sql`
  L533 and L554 *already* read
  `format('dbname=%s host=%s port=%s user=postgres password=postgres', current_database(), inet_server_addr(), inet_server_port())`.
  Nothing was missing. **Grade a proposed fix against the current text before ruling on it** — a
  fallback that restates the status quo reads as progress and delivers none.
- **The real mechanism.** PG runs `dblink_security_check()` when the **calling** role is not a
  superuser. It requires the inner connection to have **actually authenticated with a password**,
  not that one was offered. If the `pg_hba` row matched by the inner source address is `trust`, no
  password is requested and the check raises that exact message. Two facts make it bite in a
  Supabase stack: the `postgres` role is **not** `rolsuper`, and `host=inet_server_addr()`
  traverses a *different* hba row than the outer client's `127.0.0.1:54322`.
- **`rolsuper` is the discriminator, so measure it.** `select current_user, usesuper from pg_user
  where usename = current_user;` falsifies the whole reading in one command. Say "this is my
  reading" until that has been run — I could not read the container's `pg_hba` from the repo.

**⚠ The two moves to refuse, and they are the obvious ones.**

- **`dblink_connect_u`, or any `GRANT EXECUTE` on it.** It exists *specifically* to skip
  `dblink_security_check`. Granting it to a non-superuser hands that role the ability to open a
  connection under the **server's ambient identity** to an arbitrary host — an SSRF and
  local-auth-bypass primitive. Grep first: if it appears zero times in the tree, introducing it to
  turn one leg green is a posture change disguised as a test fix.
- **Elevating the battery to a superuser role** (`supabase_admin` et al.) for the dblink block. A
  security battery running as superuser stops observing the perimeter it exists to test, and the
  elevation silently applies to every leg that follows it in the same session.

**How to apply.** Rank fallbacks by *what privilege they add*, not by what is quickest:
(1) re-point the inner connection at an hba path that genuinely requires a password — no new
privilege, one line; (2) commit the fixture out-of-transaction in a CI pre-step — costs
self-containment; (3) structural pin — acceptable **only** with the loss named in the leg text and
a follow-up carrying the behavioural form, because a pin stops observing the branch it replaced.
State which branch of the predicate loses its only behavioural observer, per
[[an-enumeration-and-its-watcher-both-stop-one-short]] and
[[a-probe-asserting-only-rc-neq-0-goes-vacuous]].

**Companion finding, same block, generalisable.** A dblink fixture writes **committed** rows that do
not roll back with the pgTAP transaction. If its cleanup is straight-line *after* the assertion,
`ON_ERROR_STOP` skips the cleanup on any intervening raise and the fixture leaks — making the
battery **non-re-runnable after a single failure** on a persistent DB (the next run PK-conflicts).
Ephemeral in CI, a footgun locally. Ask of any committed fixture: *what runs the teardown when the
leg between it and the teardown raises?* Cheap fix is `on conflict do nothing` plus
delete-before-insert. Related: [[corrupt-the-control-canary-boundary-tie]].
