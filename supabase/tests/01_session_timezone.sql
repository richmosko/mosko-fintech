-- =====================================================================
-- HARNESS PROPERTY — the session TimeZone this suite runs under
-- =====================================================================
-- QA-owned. Authors no schema. Not tied to a migration, so it lives beside the inversion
-- self-test rather than in rls/, which is per-migration.
--
-- ┌─ ⚠ READ THIS BEFORE TREATING A GREEN HERE AS "THE TIMEZONE IS PINNED" ────────────┐
-- │ **IT IS NOT. THIS ASSERTS A PROPERTY OF WHICHEVER DATABASE THE SUITE JUST RAN      │
-- │ AGAINST — in CI, an ephemeral container that is NOT the deployment.** It cannot    │
-- │ observe production and must never be cited as evidence about it.                    │
-- │                                                                                      │
-- │ THE DEFECT THIS IS ADJACENT TO (Sec, 2026-08-04) IS NOT FIXED BY THIS FILE:         │
-- │   `+page.server.ts` computes the NAV as-of as `new Date().toISOString().slice(0,10)` │
-- │   — unconditionally UTC, in the NODE process. Postgres evaluates `closed_at::date`   │
-- │   in the SESSION's TimeZone. Two clocks in two processes; they agree only if the     │
-- │   session is UTC. MEASURED, reproducing Sec's construction:                          │
-- │     session Asia/Tokyo, instant 2026-03-01 23:00Z                                    │
-- │       -> closed_at::date = 2026-03-02, Node says 2026-03-01                          │
-- │       -> `closed_at::date > '2026-03-01'` is TRUE                                    │
-- │       -> A JUST-CLOSED ACCOUNT STAYS IN THE NAV HEADLINE FOR ~9 HOURS.               │
-- │     session UTC                 -> FALSE, correctly excluded.                        │
-- │     session America/Los_Angeles -> FALSE. **West of UTC fails SAFE, which is WORSE   │
-- │       than failing loudly: the defect becomes hemisphere-dependent and a US-based    │
-- │       reviewer cannot reproduce it.**                                                │
-- │                                                                                      │
-- │ THE LOAD-BEARING VERIFICATION IS AT DEPLOY TIME AND IS NOT MINE (devops). This file  │
-- │ covers the CI stack only. Two claims, two instruments; do not let a green here       │
-- │ stand in for the other one.                                                           │
-- └──────────────────────────────────────────────────────────────────────────────────────┘
--
-- ┌─ WHY THIS FILE EXISTS AT ALL, given the above ─────────────────────────────────────┐
-- │ I measured whether the EXISTING suite depends on the pin, expecting it did. **IT    │
-- │ DOES NOT.** `049`'s boundary battery — including the non-midnight (1i)/(1j)/(1k)    │
-- │ assertions — returns 33/33 with 0 failures under UTC, Asia/Tokyo AND                 │
-- │ America/Los_Angeles. The fixture inserts NAIVE timestamps (`'2026-06-30 14:00'`),    │
-- │ which are interpreted in the session zone, and the as-of comparison happens in that  │
-- │ same zone — so both shift together and cancel.                                       │
-- │                                                                                      │
-- │ That measurement is the reason this file is worth ~10 lines and not more, and it is  │
-- │ recorded because it CUTS AGAINST the case for adding it: **nothing in the suite      │
-- │ currently relies on the session zone.** Its value is forward-looking and narrow —    │
-- │ the moment someone writes a date assertion that ISN'T zone-invariant (an absolute    │
-- │ `timestamptz` literal, a `now()`-relative fixture, a `current_date` comparison), they │
-- │ silently acquire a dependency on an unpinned property, and the failure would present  │
-- │ as a mysterious date-off-by-one in CI rather than as a configuration problem.        │
-- │ THIS FILE MAKES THAT ARRIVE AS A NAMED RED INSTEAD.                                   │
-- └──────────────────────────────────────────────────────────────────────────────────────┘
--
-- ┌─ ⚑⚑ THE TIGHTENING THIS FILE PROMISED, NOW DONE — and the premise it was deferred on ──┐
-- │ was FALSE WHEN WRITTEN. Recorded rather than deleted, because the correction is the     │
-- │ instructive part and the deferral reasoning would otherwise look sound.                  │
-- │                                                                                          │
-- │ WHAT THE NOTE SAID: *"Architect has not authored the pin, so the LAYER is unruled"* —    │
-- │ therefore assert `source` only in the NEGATIVE form, since pinning an expected `source`  │
-- │ would encode an unruled decision as a requirement.                                        │
-- │ WHY IT WAS FALSE: the layer was ruled in this branch's OWN history, at `08153b2`, under  │
-- │ an explicit heading **"WHY A MIGRATION AND NOT THE PROVISIONING LAYER — the layer        │
-- │ question, ruled"**, settled on `055_pfin_etl_role.sql` / ADR-041 precedent. I deferred   │
-- │ to a ruling that was already sitting two commits behind me. **THE LESSON IS NOT "check   │
-- │ harder" — it is that a deferral note must name the ARTIFACT that would resolve it, so    │
-- │ the trigger is checkable rather than remembered.** This one named a person's future      │
-- │ action instead of a file, and so it went stale silently.                                  │
-- │                                                                                          │
-- │ THE LAYER IS `database`: `061` executes                                                   │
-- │   `execute format('alter database %I set timezone = %L', current_database(), 'UTC')`      │
-- │ so the declaration lives in `pg_db_role_setting` at `setrole = 0`, and `pg_settings`      │
-- │ reports `source = 'database'`. (T2) is now that positive assertion.                       │
-- │                                                                                          │
-- │ >> WHY THE POSITIVE FORM SUBSUMES THE NEGATIVE ONE AND REPLACES IT RATHER THAN JOINING   │
-- │    IT: `source = 'database'` excludes `client`/`user`/`session` by construction, so the   │
-- │    negative form asserts nothing the positive one does not. **AND IT EXCLUDES ONE MORE    │
-- │    VALUE, WHICH IS THE ENTIRE POINT: `configuration file` — the image default.** That is  │
-- │    what makes the tightening non-cosmetic. MEASURED READ-ONLY ON THE LIVE LOCAL CLUSTER   │
-- │    across 4 conditions, by CONNECTING rather than by mutating anything:                   │
-- │                                                                                          │
-- │      condition                                | value=UTC | source             | old(T2)| new(T2)│
-- │      A. pinned db (`postgres`)                 |   true    | database           |  PASS  |  PASS  │
-- │      B. UNPINNED db (`_supabase`, SAME image)  |   true    | configuration file |  PASS  |  FAIL  │
-- │      C. pinned db + `PGTZ=Asia/Tokyo`          |   false   | client             |  FAIL  |  FAIL  │
-- │      D. pinned db, connected as `authenticator`|   false   | user               |  FAIL  |  FAIL  │
-- │                                                                                          │
-- │    **ROW B IS THE FINDING.** `_supabase` is a database in this same cluster, same image,  │
-- │    carrying no `ALTER DATABASE` pin — i.e. it is exactly "this stack without `061`". The  │
-- │    OLD (T2), INCLUDING THE NEGATIVE `source not in (...)` FORM, IS GREEN THERE. So the    │
-- │    negative form was invariant to the very thing it was written to eventually verify,     │
-- │    and by this suite's own standing rule — an assertion that passes with and without the  │
-- │    thing it verifies is invariant to it, and invariance is evidence the input is not      │
-- │    reaching the assertion — it was not yet earning its plan slot. THE NEW FORM REDS.      │
-- │    That is this tightening's "make it fail once", and it cost no `db reset` and no data.  │
-- │                                                                                          │
-- │ >> AND WHY (T1) SURVIVES ALONGSIDE IT rather than being folded in: they are independent,  │
-- │    not nested. (T1) is the VALUE claim, (T2) is the MECHANISM claim, and each catches a   │
-- │    case the other passes. `alter database ... set timezone='Asia/Tokyo'` reports          │
-- │    `source = 'database'` — (T2) GREEN, (T1) RED: a correctly-LAYERED pin with the WRONG   │
-- │    ZONE. Row B is the converse: right value, no declaration. Two failure modes, two       │
-- │    assertions; collapsing them would drop one.                                            │
-- └──────────────────────────────────────────────────────────────────────────────────────────┘
--
-- ┌─ ⚑⚑⚑ THE VECTOR THIS FILE DOCUMENTED IN PROSE BUT COULD NOT SEE — now (T3), and the ────┐
-- │ gap was NOT hypothetical: **THE LOCAL STACK WAS DEFEATED WHILE THIS SUITE RAN GREEN.**   │
-- │                                                                                          │
-- │ THE CRITICISM (Architect, cross-checked by team-lead; it is my own rule turned on my own │
-- │ artifact a second time): (T2) reads `pg_settings.source`, which reports *the session you  │
-- │ are IN*. `pg_prove` connects as `postgres`. Role-level GUCs are applied at SESSION        │
-- │ ESTABLISHMENT from the role that AUTHENTICATED — a fact this file's own (T2) comment      │
-- │ already stated — so an `ALTER ROLE authenticator SET TimeZone` never surfaces as          │
-- │ `source = 'user'` here. **The file described, in prose, the exact vector its assertions   │
-- │ were structurally incapable of observing.** Prose is not a fence.                          │
-- │                                                                                          │
-- │ MEASURED 2026-08-04 ON THE LIVE LOCAL STACK, BEFORE WRITING (T3):                         │
-- │   `pg_db_role_setting` carried `TimeZone=Asia/Tokyo` on role `authenticator` — the LOGIN   │
-- │   role PostgREST connects as, i.e. EVERY web request. Simultaneously:                      │
-- │     as `postgres`      -> setting = UTC,        source = database   (T1)+(T2) BOTH GREEN   │
-- │     as `authenticator` -> setting = Asia/Tokyo, source = user                              │
-- │   and `supabase test db` on this file returned **`Files=1, Tests=2, Result: PASS`**.        │
-- │   >> A GREEN SUITE ON A DATABASE WHOSE EVERY APPLICATION REQUEST WAS IN TOKYO. << That is  │
-- │   the "half-pinned deployment that INSPECTS CLEAN" shape `061` warns about, observed in    │
-- │   the wild rather than reasoned about. Nothing in the repo sets it (`grep` for `alter      │
-- │   role` over `supabase/` + `.github/` finds none), so it was manual — left behind by an    │
-- │   adversarial probe and never reset, which is exactly how this arrives in real life.       │
-- │                                                                                          │
-- │ CLOSED IN-SUITE, DECLARATIVELY, rather than scoped out. `pg_db_role_setting` is a CLUSTER  │
-- │ catalog and is readable from the `postgres` session `pg_prove` already has, so the check   │
-- │ does not need the session it cannot get. This is the same move ADR-011 rules for           │
-- │ unfalsifiable `WITH CHECK` conjuncts — when a runtime probe structurally cannot reach the  │
-- │ property, PROVE IT DECLARATIVELY FROM THE CATALOG. (T3) is the runbook §4.1 sweep          │
-- │ (`pg_db_role_setting … ilike '%timezone%'`, zero rows required) as an executable           │
-- │ assertion, and it is deliberately the SAME query so the two cannot drift.                  │
-- │                                                                                          │
-- │ ⚠ WHAT (T3) DOES **NOT** CLOSE — stated per the standing rule that a fence must name where │
-- │   its sufficiency comes from. (T3) inspects THE DATABASE THE SUITE RAN AGAINST, like       │
-- │   everything else in this file. Of the three ways this vector actually arrives:            │
-- │     1. a migration/seed IN THIS REPO adds a role-level override  -> (T3) REDS in CI  ✅    │
-- │     2. a human runs `ALTER ROLE` against a DEV stack             -> (T3) REDS locally ✅   │
-- │        (that is the case measured above — (T3) catches the actual live instance)           │
-- │     3. a human runs `ALTER ROLE` against PRODUCTION              -> (T3) CANNOT SEE  ❌    │
-- │   **CASE 3 REMAINS A DEPLOY-TIME HUMAN STEP (runbook §10 TZ-1 / the §4.1 sweep) AND IS     │
-- │   NOT CLOSED BY THIS FILE.** Promoting that deploy-time sweep to an executable gate is R3  │
-- │   in Architect's 2026-08-04 decision brief; it is DevOps-owned and it is NOT mine. Do not  │
-- │   read a green (T3) as evidence about production — same scope caveat as (T1)/(T2), and     │
-- │   the reason this file opens with the box it opens with.                                    │
-- └──────────────────────────────────────────────────────────────────────────────────────────┘
--
-- POSTURE (SECURITY §4.5): reads catalog/GUC state only. No fixture, no tenant, no data.

begin;

-- plan = 3. Deliberately small: this file's honest claim is narrow, and padding it with
-- assertions about Postgres's own `::date` semantics would be testing the platform.
-- The three are one claim each — VALUE (T1), MECHANISM (T2), CLUSTER (T3) — and the notes
-- above record why none of the three collapses into another.
select plan(3);

-- (T1) THE SESSION THIS SUITE RUNS IN IS UTC.  [the VALUE claim]
--   Read back via current_setting rather than trusting a config file — a pinned setting nobody
--   reads back is the same class of unmeasured premise as an unpinned one, which is the whole
--   argument for this assertion existing.
--   Kept alongside (T2) because a pin at the RIGHT layer with the WRONG zone
--   (`alter database ... set timezone='Asia/Tokyo'`) passes (T2) and fails only here.
select is(
  current_setting('TimeZone'),
  'UTC',
  '(T1) VALUE: the session TimeZone of the database THIS SUITE RAN AGAINST is UTC. ⚠ SCOPE: the CI/local stack ONLY — this file cannot observe the deployment, and a green here is NOT evidence the production database is pinned (that check is deploy-time and DevOps-owned). What it does buy: any future date assertion that is not zone-invariant fails HERE, by name, instead of surfacing as an off-by-one-day mystery somewhere downstream. Paired with (T2): this one catches a pin carrying the WRONG ZONE, which (T2) cannot see'
);

-- (T2) THE VALUE IS SUPPLIED BY THE 061 DECLARATION, NOT BY THE IMAGE DEFAULT.  [MECHANISM claim]
--   ⚑ THIS REPLACED A NEGATIVE FORM (`source not in ('client','user','session')`) THAT WAS
--     INVARIANT TO THE PIN. Measured read-only against `_supabase` — a database in this same
--     cluster with no ALTER DATABASE pin — where the negative form is GREEN and this one REDS.
--     `supabase/postgres:17.6.1.132` already defaults to UTC at `source = 'configuration file'`,
--     so ONLY the positive form can tell *"the pin is applied"* from *"the image happens to
--     default to UTC"*. The layer was ruled at `08153b2` (migration channel, on `055`/ADR-041
--     precedent); `database` is that ruling's observable consequence, not a guess.
--   ⚑ IT ALSO STILL CATCHES BOTH OVERRIDE VECTORS the negative form was written for, because
--     `database` excludes them by construction: `client` is a stray `PGTZ` startup parameter
--     (libpq sends it, so `psycopg` in workers/etl and every libpq-backed client can move its
--     OWN session zone while the database still reads UTC to anyone inspecting it), and `user`
--     is a role-level `ALTER ROLE` on the LOGIN role — measured to be `authenticator`, NOT
--     `authenticated`, because per-role GUCs apply at LOGIN and do not survive `SET ROLE`.
--     ⚠ BUT ONLY FOR THIS SESSION'S OWN LOGIN ROLE, WHICH IS `postgres` — see (T3), which
--     exists precisely because that limitation makes this blind to the `authenticator` vector.
select is(
  (select source from pg_settings where name = 'TimeZone'),
  'database',
  '(T2) MECHANISM: the session TimeZone is supplied by the 061 ALTER DATABASE declaration (pg_settings.source = `database`), not by the container image default (`configuration file`) and not by an override vector (`client` = a stray PGTZ startup parameter; `user` = a role-level ALTER ROLE). RED means: read pg_settings.source FIRST — if it says `configuration file` the pin did not apply and the UTC you are reading is the image being right by accident; if it says `client` or `user` something is overriding the declaration. ⚠ `user` is visible here ONLY for THIS session''s login role (`postgres`); the role vector that actually matters is `authenticator`, and (T3) is what covers it'
);

-- (T3) NO ROLE IN THE CLUSTER CARRIES A TimeZone OVERRIDE.  [the CLUSTER claim]
--   ⚑⚑ THIS IS THE ASSERTION THAT SEES WHAT (T1) AND (T2) STRUCTURALLY CANNOT. `pg_settings`
--     reports the session you are IN; `pg_prove` connects as `postgres`; role GUCs apply at the
--     LOGIN of the role that authenticated. So `ALTER ROLE authenticator SET TimeZone` — which
--     moves EVERY PostgREST request in the cluster — is invisible to (T1)/(T2) forever.
--     MEASURED: this file returned PASS 2/2 while `authenticator` carried `TimeZone=Asia/Tokyo`.
--   ⚑ SO IT ASSERTS OVER THE CATALOG, NOT OVER THE SESSION. `pg_db_role_setting` is cluster-wide
--     and readable from the session pg_prove already has — the property is reachable
--     DECLARATIVELY even though it is unreachable at runtime. `setrole <> 0` scopes this to
--     ROLE-level entries and therefore deliberately does NOT match 061's own database-level pin
--     (which is `setrole = 0`); it covers both `ALTER ROLE r SET` (setdatabase = 0) and
--     `ALTER ROLE r IN DATABASE d SET`. `is_empty` rather than `ok(not exists ...)` so a failure
--     PRINTS THE OFFENDING ROLE instead of just saying false — the diagnostic IS the point.
select is_empty(
  $$ select r.rolname, d.datname, c as setting
       from pg_db_role_setting s
       join pg_roles r on r.oid = s.setrole
       left join pg_database d on d.oid = s.setdatabase
       cross join lateral unnest(s.setconfig) as c
      where s.setrole <> 0
        and c ilike 'timezone=%' $$,
  '(T3) CLUSTER: no ROLE carries a TimeZone override in pg_db_role_setting — the runbook §4.1 catalog sweep as an executable assertion, kept query-identical to the runbook so the two cannot drift. This is the ONLY check here that can see `ALTER ROLE authenticator SET TimeZone`, the vector that moves every PostgREST request while a `postgres`-session inspection still reads a clean UTC/`database`. RED prints the offending role: reset it with `alter role <role> reset timezone`. ⚠ SCOPE, unchanged from the rest of this file: it inspects the database THE SUITE RAN AGAINST. It catches the override arriving via a repo migration/seed (CI) or via a hand-run statement on a dev stack (local) — it CANNOT see production, where this remains the runbook §10 TZ-1 deploy gate (promoting THAT to an executable gate is R3, DevOps-owned)'
);

select * from finish();
rollback;
