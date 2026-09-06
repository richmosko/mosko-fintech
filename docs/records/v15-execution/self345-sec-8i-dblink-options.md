# Sec-c — leg 8-i dblink failure: mechanism + acceptable fallbacks

Written 2026-09-06. Refs: `feature/self-345-qa` @ `ee597b1`, assembled unit @ `e730fd6`.

## The brief's proposed fallback #1 is already the shipped shape

`git show ee597b1:supabase/tests/rls/111_audit_log_rls.sql` L533 and L554 both read:

```
format('dbname=%s host=%s port=%s user=postgres password=postgres', current_database(), inet_server_addr(), inet_server_port())
```

The password is **already in the connstr**. "Add the password from the test env" cannot be the
fix, because nothing is missing.

## The mechanism (my reading; falsifiable — see below)

PostgreSQL applies `dblink_security_check()` when the **calling** role is not a superuser. It
requires that the inner connection **actually authenticated with a password**, not that a password
was offered. If the `pg_hba` rule matched by the inner connection's source address is `trust`, no
password is requested, the check fails, and PG raises exactly
`password or GSSAPI delegated credentials required`.

Two supporting measurements from the tree:

- Session role at L533 is `postgres` — last role statement before it is
  `select set_config('role', 'postgres', true);` at L463 (measured:
  `git show ee597b1:supabase/tests/rls/111_audit_log_rls.sql | sed -n '1,532p' | grep -n "set_config('role'\|_rls.set_tenant"`).
- In a Supabase stack the `postgres` role is **not** `rolsuper`, so the security check applies.

The inner connection uses `host=inet_server_addr()` — the container's own address — which is a
**different `pg_hba` row** from the one the outer pgTAP client traverses
(`postgresql://postgres:postgres@127.0.0.1:54322`, per `db-tests.yml` L133). That outer path
demonstrably requires a password. The inner one apparently does not.

**Falsifier QA should run before acting on any of this:**
`select current_user, usesuper from pg_user where usename = current_user;` and
`select inet_server_addr();` on the CI stack, plus the container's `pg_hba.conf` rows.
If `usesuper` is `t`, my reading is wrong and the cause is elsewhere.

## Acceptable fallbacks, in preference order

1. **Re-point the inner connection at the hba path that requires a password.** Replace
   `host=inet_server_addr()` with the host/address whose `pg_hba` row is `scram-sha-256`
   (measured, not assumed). Keeps 8-i behavioural, adds no privilege, one-line change.
2. **Move the earlier-committed fixture out of the battery transaction.** A CI pre-step commits
   tenant E's `auth.users` + `pfin.monthly_report` row before `supabase test db`; the battery
   reads it. Keeps the leg behavioural. Costs battery self-containment and needs an explicit
   teardown step.
3. **Structural pin (QA's own named fallback) — ACCEPTABLE, with the loss stated in the leg text.**
   The "genuinely earlier, separate, committed transaction" branch of C2 then has **no behavioural
   observer**. That branch is half of VETO-1's same-transaction requirement. I accept it to unblock
   the merge because the other branches keep behavioural coverage — 8-ii (other tenant, refused),
   8-iii (same-transaction bare INSERT, succeeds), 7d/7e (subtransaction shape) — and because
   `pg_xact_status` returning `'committed'` for an earlier row is the least surprising half of the
   predicate. **Condition:** the leg comment must name what was lost, and a Linear follow-up must
   carry the behavioural form.

## NOT acceptable — VETO if proposed (nobody has proposed these)

- **`dblink_connect_u`**, or any `GRANT EXECUTE` on it. It exists precisely to skip
  `dblink_security_check`. Granting it to a non-superuser hands that role the ability to open a
  connection using the **server's ambient identity** to an arbitrary host — an SSRF and
  local-auth-bypass primitive. Measured: `dblink_connect_u` appears **zero** times in the tree
  (`git grep -n dblink_connect_u e730fd6`). Introducing it to turn one test green is not a trade
  I will clear.
- **Elevating the battery to a superuser role** (e.g. `supabase_admin`) for the dblink block. A
  security battery that runs as superuser stops observing the perimeter it exists to test, and the
  elevation would silently apply to whatever legs follow it.

## Separate, smaller finding on the same block (FLAG for QA, not a merge blocker)

The dblink cleanup at L554–556 is **straight-line after** the assertion. Under `ON_ERROR_STOP`,
any raise between L534 and L553 skips it, and tenant E's **committed** `auth.users` row persists
(its `pfin.monthly_report` child does cascade — `108` L545–546 is
`references auth.users (id) on delete cascade`). The next run's dblink
`insert into auth.users (id) values ('<te>')` then hits a PK conflict, so **the battery is not
re-runnable after a single failure on a persistent database.** Ephemeral in CI, a footgun locally.
Cheap fix: `on conflict do nothing` on the fixture insert, plus a delete-before-insert.
