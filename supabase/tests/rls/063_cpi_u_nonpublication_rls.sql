-- =====================================================================
-- Per-Wave battery — pfin.cpi_u_nonpublication  GLOBAL, APPEND-ONLY, IMMUTABLE
--   (CPI-U non-publication record; ADR-049 Decision 1 Option C / migration 063)
-- =====================================================================
-- ⚠ EXPECTED-TO-FAIL AGAINST A LIVE LOCAL STACK carrying the real committed CPI reference
--   data (the 2026-08-14 recovery; docs/records/2026-08-14-db-reset-incident.md) — the
--   fixture's `2025-10-01` row collides with the table's real, PERMANENT, IMMUTABLE
--   nonpublication record for that same period. This file is a HARDER case than a bare
--   date-pick collision: `2025-10-01` is used DELIBERATELY, because it is the actual
--   real-world period ADR-049 was written around (see the fixture's own note below) — a
--   substitute synthetic date would sacrifice that grounding, not just dodge a collision.
--   THE SANCTIONED LOCAL RUN for this file is a hand-built scratch DB (`createdb` +
--   `psql -f` per migration, never `supabase db reset` — mechanically banned). CI's
--   clean-apply lane builds a fresh DB every run and is UNAFFECTED — it is the actual
--   gating venue for this file. A deeper follow-up (splitting the real-event-anchored
--   narrative leg from the mechanical CRUD/permission legs, so only the former needs the
--   authentic date) is tracked separately, not built here (meta/battery-local-stack-
--   disposition PR body).
-- =====================================================================
-- BINDS TO MIGRATION: supabase/migrations/063_cpi_u_nonpublication.sql
--   - pfin.cpi_u_nonpublication              (NEW global reference table: cpi_period DATE PK
--                                            (first-of-month) / source TEXT DEFAULT
--                                            'BLS_CUUR0000SA0' / published_value_raw TEXT NULL
--                                            (<= 64) / observed_at TIMESTAMPTZ DEFAULT now())
--   - constraint cpi_u_nonpublication_period_first_of_month  (CHECK extract(day)=1)
--   - constraint cpi_u_nonpublication_raw_bounded            (CHECK length <= 64)
--   - pfin.fn_cpi_u_nonpublication_block_mutation()  (BEFORE UPDATE OR DELETE, ROW-level; raise)
--   - pfin.fn_cpi_u_nonpublication_block_truncate()  (BEFORE TRUNCATE, STATEMENT-level; raise)
--   - revoke truncate ... from public          (defensive; the statement trigger is the guarantee)
--   - policy cpi_u_nonpublication_select       (FOR SELECT TO authenticated USING (true))
--   - grant select on ... to authenticated     (ACL-before-RLS; SELECT only)
--   - grant select, insert on ... to service_role   (append-only writer; NO UPDATE/DELETE)
--   - anon: ZERO grant                         (denied at pfin schema-USAGE, one layer in FRONT)
--
-- ┌─ ⚠ WHAT "TWO-TENANT" MEANS ON A TABLE WITH NO TENANT COLUMN (read before extending) ───────┐
-- │ SECURITY §4.5's catalog is written around a two-tenant SQL fixture in which tenant A owns   │
-- │ rows and tenant B must see none of them. THAT SHAPE DOES NOT TRANSFER HERE, and porting it  │
-- │ mechanically would produce a green suite that proves nothing: cpi_u_nonpublication has NO   │
-- │ users_id, NO FK-shaped column and NO tenant anchor (063 header, Decision-3 evaluation, two  │
-- │ independent grounds), so "B sees 0 of A's rows" is an assertion about an empty set — it     │
-- │ passes on a correct table, on a broken table, and on a table that does not exist.           │
-- │                                                                                             │
-- │ THE ISOLATION QUESTION HERE IS "CAN THE WRONG **ROLE** READ OR WRITE", NOT "CAN TENANT B    │
-- │ SEE TENANT A". So the battery varies the LOGIN ROLE — the variable a same-role suite is     │
-- │ blind to — across all four tiers that actually exist on this table, each proven BOTH ways:  │
-- │     anon           -> nothing at all      (h10)/(h11)/(n1)  <-> (V2) proves the fence real   │
-- │     authenticated  -> SELECT and ONLY SELECT   (a*)/(b*)/(h1)-(h4)                           │
-- │     service_role   -> SELECT + INSERT and NOTHING ELSE  (c*)/(h5)-(h9)                       │
-- │     OWNER postgres -> ACL and RLS both cease to apply; TRIGGERS are the sole gate  (d*)      │
-- │ The two-tenant fixture is still used, with its POLARITY INVERTED: two DISTINCT authenticated │
-- │ identities must read the SAME rows (global shared-read, USING (true)) — the exact inverse   │
-- │ of a per-user isolation battery. (a0a)/(a0b) pin that the two contexts really are different │
-- │ identities first, because an invariance assertion over a variable that never varied is      │
-- │ blindness, not robustness. Mirrors 011_tax_character_rls / 053_cpi_u_index_rls.              │
-- └────────────────────────────────────────────────────────────────────────────────────────────┘
--
-- ┌─ LAYER HONESTY — which fence each assertion actually exercises (grant-then-RLS, PR #106) ──┐
-- │ Postgres checks schema USAGE, then the TABLE ACL, then RLS, then a BEFORE-ROW trigger. A    │
-- │ "denied" result must be attributed to the layer that really produced it. MEASURED, live:    │
-- │   anon SELECT             -> 42501 'permission denied for SCHEMA pfin'   (never reaches ACL)│
-- │   authenticated write     -> 42501 'permission denied for TABLE cpi_u_nonpublication' (ACL) │
-- │   service_role UPD/DEL/TRUNC -> 42501 'permission denied for TABLE ...'  (ACL — NOT the     │
-- │                              trigger; asserting the trigger message here would be a         │
-- │                              false-RED, and believing it had been proven would be worse)    │
-- │   OWNER postgres UPD/DEL/TRUNC -> P0001, the TRIGGER message (no ACL layer exists to deny   │
-- │                              the owner, and RLS is bypassed: the trigger is the sole gate)  │
-- │ Leg (d5)-(d7) is the load-bearing cross-tier assertion: a TEST-ONLY grant (rolled back; the │
-- │ 004/054 idiom) opens service_role's ACL so the TRIGGER becomes the sole remaining gate for  │
-- │ the REAL WRITER identity. (h5)-(h9) assert the PRODUCTION least-privilege ACL and run       │
-- │ BEFORE that grant, so the grant cannot mask them.                                           │
-- │                                                                                             │
-- │ ⚠ THIS BATTERY AND 063's OWN COMMENTS NOW SAY THE SAME THING, AND THE ORDER MATTERS:        │
-- │ 063 states that the WITHHELD GRANTS ARE THE OPERATIVE FENCE and the triggers are the        │
-- │ BACKSTOP that "becomes load-bearing if a future migration widens that grant". This file is  │
-- │ structured to prove exactly that division rather than to blur it: (c3)-(c5) prove the ACL   │
-- │ refuses FIRST for the writer (the operative half), and (d5)-(d7) prove the conditional the  │
-- │ backstop claim rests on — WITH the grant widened, the trigger still holds. A battery that   │
-- │ asserted only "the mutation was blocked" would be satisfied by the ACL alone and would go   │
-- │ on passing if the triggers were deleted; one that asserted only the trigger message under   │
-- │ service_role would be permanently RED against a fence that is working. Two mechanisms, two  │
-- │ fences, and every leg here names which one it exercises.                                    │
-- └────────────────────────────────────────────────────────────────────────────────────────────┘
--
-- ┌─ SIGNAL PRECISION — no fence can pass for another (the 004 all-42501 false-green lesson) ──┐
-- │   ACL denial (any role)      -> MESSAGE-precise 'permission denied for table cpi_u_nonpub…' │
-- │   row-level immutability     -> MESSAGE-precise '%is immutable%UPDATE blocked%' / '%DELETE  │
-- │                                 blocked%'                                                   │
-- │   statement-level TRUNCATE   -> MESSAGE-precise '%is immutable%TRUNCATE blocked%'  (DISTINCT│
-- │                                 verb clause — this is what proves the two triggers are TWO  │
-- │                                 fences and not one being credited twice)                    │
-- │   non-first-of-month         -> CONSTRAINT-NAME-precise '%cpi_u_nonpublication_period_first │
-- │                                 _of_month%'                                                 │
-- │   over-long raw token        -> CONSTRAINT-NAME-precise '%cpi_u_nonpublication_raw_bounded%'│
-- │   duplicate cpi_period       -> SQLSTATE-precise 23505 unique_violation                     │
-- └────────────────────────────────────────────────────────────────────────────────────────────┘
--
-- ┌─ NON-VACUITY IS ENCODED, NOT REPORTED — leg (V) ───────────────────────────────────────────┐
-- │ Every high-value NEGATIVE in this file is paired with an INVERSION leg that breaks the      │
-- │ fence inside a savepoint, asserts the negative FLIPS, and rolls back. This is the 062       │
-- │ (V*) idiom. It matters because an absence assertion whose subject can never appear is       │
-- │ indistinguishable from a real fence on a green run (rls/DESIGN.md §10): `not               │
-- │ has_table_privilege('anon', …)` looks identical against a genuine REVOKE and against a role │
-- │ that simply never holds grants anywhere. Each (V) leg was ALSO reproduced by hand at        │
-- │ authoring — broken, watched go RED, restored — and the (V) legs are the durable half.       │
-- │   (V1) grant INSERT to authenticated   -> (h2) flips                                        │
-- │   (V2) grant USAGE+SELECT to anon      -> (h10)/(h11)/(n1) flip — and anon STILL reads zero │
-- │                                          rows, because a THIRD fence (the policy's TO       │
-- │                                          authenticated role list) survives both grants.     │
-- │                                          That was a REFUTED HYPOTHESIS: the leg was written │
-- │                                          claiming the opposite and the run said 0. (V2c)    │
-- │                                          opens the role list too and reaches the property   │
-- │                                          the wrong claim was about; (b6) pins the fence the │
-- │                                          refutation found, which nothing else here covered. │
-- │   (V3) drop the TRUNCATE trigger       -> (d3) flips and the whole record wipes in one      │
-- │                                          statement (row triggers do NOT fire on TRUNCATE)   │
-- │   (V4) drop the row-level trigger      -> (d1) flips and the stored value really changes    │
-- │   (V5) structural, OUTSIDE any savepoint: the fences are all back, and the plan counter is  │
-- │                                          re-armed (see the harness note below)              │
-- └────────────────────────────────────────────────────────────────────────────────────────────┘
--
-- ┌─ HARNESS NOTE — a rolled-back savepoint REWINDS pgTAP's plan counter ──────────────────────┐
-- │ …while the emitted test NUMBERING marches on from a non-transactional sequence (rls/       │
-- │ DESIGN.md §9; the 062 idiom). MEASURED here: with the (V) legs all inside savepoints,       │
-- │ finish() reported "planned 51 but ran 44" — 44 being the counter's value at the FIRST       │
-- │ savepoint, which every later rollback rewound it to. ⚠ DO NOT "fix" that by lowering the    │
-- │ plan to the reported figure: pg_prove compares the PRINTED plan against the PRINTED test    │
-- │ lines, so lowering it turns a cosmetic diagnostic into a real failure. The fix is that      │
-- │ (V5) sits OUTSIDE every savepoint and runs LAST, which re-sets the counter to its own       │
-- │ emitted number. That is structural, not coincidence — moving (V5) re-breaks it.             │
-- └────────────────────────────────────────────────────────────────────────────────────────────┘
--
-- ┌─ KNOWN LIMIT — the strongest tier this harness reaches is the TABLE OWNER, not a superuser ┐
-- │ MEASURED on the local stack: `postgres` has usesuper = FALSE and holds no membership in     │
-- │ `supabase_admin` (the only superuser), so `set role supabase_admin` is not available to     │
-- │ this battery and a genuine-superuser tier CANNOT be asserted here. That is stated rather    │
-- │ than papered over. What IS asserted is the property the migration actually claims: the      │
-- │ owner tier is where the table ACL and RLS BOTH cease to apply, and the triggers still hold  │
-- │ there (d1)-(d3).                                                                            │
-- │ ⚠ And the honest converse, which no assertion in this file may be read as denying: an       │
-- │ owner can `alter table … disable trigger`, and a superuser can `set session_replication_    │
-- │ role='replica'` — legs (V3)/(V4) DO EXACTLY THAT to prove the fences have teeth. Trigger-   │
-- │ based immutability is INHERENTLY bounded by ownership; this is not a 063 defect (it applies │
-- │ identically to 004 / 054 and every Lock 10 mod #8 table) and a leg claiming "the fence      │
-- │ holds under session_replication_role='replica'" would be permanently and honestly RED.      │
-- └────────────────────────────────────────────────────────────────────────────────────────────┘
--
-- FAILS-CLOSED (the REAL defect each assertion would catch):
--   (z1)  -> a battery whose counts silently depend on ambient rows. Pins the table EMPTY before
--            the fixture, so (a1)/(a2)/(V3) mean what they say on any DB this runs against.
--   (a0a)/(a0b) -> a two-tenant fixture that never actually varied the tenant (both contexts the
--            same identity). Without this, (a3)'s "identical under A and B" is blindness.
--   (a1)  -> an over-restrictive SELECT policy that hides even the global rows.
--   (a2)/(a3) -> a users_id-scoped (or otherwise discriminating) SELECT policy on a table that
--            has no users_id — the INVERSE failure of a per-user battery. (a3) compares the full
--            row content, not a count, so a policy leaking a DIFFERENT row set of the same size
--            is caught too.
--   (b1)-(b4) -> a write grant reaching authenticated: a user could FORGE a non-publication
--            record (making a real gap read as explained) or ERASE one (destroying the only
--            evidence that a period was published valueless). Both feed inflation-adjusted
--            figures through 064.
--   (b5)  -> an INSERT/UPDATE/DELETE/ALL policy landing on the table (RLS-layer default-deny,
--            defence-in-depth behind the ACL fence).
--   (c1)/(c2) -> the writer path being dead: a green write-fence over a vacuously-absent grant.
--   (c3)-(c5) -> a widening of the writer's ACL beyond append-only.
--   (d0)  -> ownership moving, at which point (d1)-(d4) would be fencing some other identity.
--   (d1)/(d2) -> removal of the row-level trigger: an owner-class session (human psql, a
--            migration script, a "fix") silently rewriting or erasing a recorded non-publication.
--   (d3)  -> removal of the STATEMENT-level trigger. Row-level triggers do NOT fire on TRUNCATE,
--            so (d1)/(d2) passing tells you NOTHING about this path — the entire record could go
--            in one statement.
--   (d4)  -> an over-broad immutability fence that also blocked the append path (a silent ingest
--            outage, not a control).
--   (d5)-(d7) -> THE CROSS-TIER ASSERTION: if the writer's ACL were ever widened (one plausible
--            future grant), the triggers must still hold. Proven by opening the ACL test-only.
--   (d8)  -> the writer using `on conflict DO UPDATE`: 063's STANDING REQUIREMENT says it must
--            reach the UPDATE fence and fail loud rather than silently restating a first
--            observation. This asserts the failure is real, not documentation.
--   (d9a)/(d9b) -> `on conflict DO NOTHING` NOT being a no-op: a monthly re-fetch must be bounded
--            and must NOT move observed_at or the raw token off the FIRST observation.
--   (e1)  -> a mis-keyed (non-first-of-month) row, which would silently never join cpi_u_index or
--            match a 064 lookup — a WRITTEN record indistinguishable from one NEVER WRITTEN.
--   (e2)  -> an unbounded-text write vector on a global service_role-writable table.
--   (e3)/(e4) -> an over-broad CHECK rejecting legitimate records (64 chars exactly; NULL raw).
--   (f1)  -> loss of the one-row-per-period PK grain the writer's ON CONFLICT depends on.
--   (h1)-(h9) -> the production least-privilege ACL drifting in either direction.
--   (h10)/(h11)/(n1) -> anon reachability. CRITICAL on a USING (true) table: the policy has NO
--            row filter, so anon reads EVERY row the instant a grant lands — (V2) measures it.
--   (V1)-(V4) -> the fences above having quietly stopped being fences (see the (V) block).
--
-- §10 / DECISION 3 (Path B — ADR-011 Decision 4 is LINKED, not restated; read it live. This file
--   is not the canonical anchor, so NO count appears here: a derived surface that copies a count
--   acquires a maintenance obligation it will not honour). §10 catalogued instances: DELTA = 0 —
--   063's service_role SELECT+INSERT grant is a DB-LAYER ACL, NOT the code-layer
--   SUPABASE_SERVICE_ROLE_KEY allowlist grep fence, NOT the PDF-worker container credential
--   audit, NOT the app->worker admission surface (identical reasoning to 053 and eod_price/019).
--   ADR-011 Decision 3 family: DELTA = 0 — no users_id, no FK-shaped column, no INTEGER[] array,
--   and both this table and cpi_u_index are GLOBAL, so there is no tenant boundary to bypass even
--   if such a column existed (063's two independent grounds). SECURITY DEFINER allowlist:
--   DELTA = 0 — the two trigger fences are SECURITY INVOKER. This battery changes no ledger.
--
-- POSTURE (SECURITY §4.5): SYNTHETIC ONLY. The fixed-UUID tenants from _rls.tenant_a()/_b()
--   supply the authenticated RLS CONTEXT only (there is no per-tenant data on this GLOBAL table).
--   NO PII / NO real account numbers / NO production data. The seeded rows are synthetic macro
--   reference records; '2025-10-01' is used because it is the real-world period ADR-049 was
--   written for, but the row is authored here, not copied from production. No auth.users rows are
--   needed (no auth.users FK; USING (true) never dereferences auth.uid()). All in a rolled-back
--   txn — including every (V) leg, each additionally savepoint-scoped.
--
-- ROLE/SCHEMA DISCIPLINE (PR #121 root-cause): `_rls` grants no USAGE to authenticated, so no
--   `_rls.*` call runs while switched to authenticated. Tenant UUIDs are resolved to psql
--   LITERALS via \gset at role=postgres; every _rls.set_tenant is called at role=postgres and
--   each block restores role=postgres before the next. \gset var names are ALL-LOWERCASE (005
--   case-fold lesson). anon and service_role denials are probed via _rls.stmt_denied_as (called
--   and asserted at postgres) rather than by running pgTAP under those roles.
--
-- ⟦WIRE-VALIDATE⟧ VERIFIED LOCALLY, NON-DESTRUCTIVELY: 063 + this file applied inside a single
--   psql transaction that was ROLLED BACK (no `supabase db reset`; the F/CTO's local data was
--   untouched — re-counted after the run). The authoritative run is CI's 001->064 reset stack
--   (pg_prove directory-mode). RED-until-063-applied is EXPECTED on any pre-063 stack.
-- =====================================================================

begin;

-- shared verbs (Option C via \ir); nested case -> ../_fixtures/ per DESIGN.md.
\ir ../_fixtures/rls_verbs.psql

select plan(54);

-- Resolve the fixed tenant UUIDs to psql literals while privileged (role=postgres).
select _rls.tenant_a() as ta, _rls.tenant_b() as tb \gset

-- =====================================================================
-- (z1) BASELINE PIN — assert the table is EMPTY before the fixture.
--   Not ceremony: (a1)/(a2) assert exact counts and (V3) asserts a TRUNCATE emptied the table.
--   Both are silently wrong if ambient rows exist. The table is also IMMUTABLE, so there is no
--   `delete from` escape hatch to normalize it with — the assumption has to be checked, not
--   enforced. A RED here means the DB under test already holds non-publication records and the
--   count-based legs must be re-scoped, NOT that the fences failed.
-- =====================================================================
select is(
  (select count(*) from pfin.cpi_u_nonpublication)::bigint, 0::bigint,
  '(z1) baseline: pfin.cpi_u_nonpublication is EMPTY before the fixture — the count-based legs (a1)/(a2)/(V3) are scoped to the rows THIS file seeds. RED means the DB under test carries pre-existing records (the table is immutable, so they cannot be cleared) and the counts need re-scoping'
);

-- ---------------------------------------------------------------------
-- FIXTURE (PRIVILEGED postgres session). Two SYNTHETIC records. INSERT is the only
-- mutation the triggers permit, at every tier. READS ARE ASSERTED FIRST (053 idiom) so the
-- later writer legs cannot perturb the counts.
-- ---------------------------------------------------------------------
insert into pfin.cpi_u_nonpublication (cpi_period, published_value_raw)
  values ('2025-10-01', '-');
insert into pfin.cpi_u_nonpublication (cpi_period, published_value_raw)
  values ('2024-03-01', null);

-- =====================================================================
-- LEG (a) GLOBAL SHARED-READ — the two-tenant fixture with its polarity INVERTED.
-- =====================================================================
-- (a0a)/(a0b) IDENTITY ANCHOR — the two contexts are DIFFERENT identities. Without this pair,
--   (a3)'s equality is invariance over a variable that never varied.
select _rls.set_tenant(:'ta'::uuid);
select is(
  (select auth.uid()), :'ta'::uuid,
  '(a0a) identity anchor: under tenant A''s context auth.uid() really IS tenant A — the identity the RLS layer would key on if this table had a tenant column'
);
select set_config('role', 'postgres', true);

select _rls.set_tenant(:'tb'::uuid);
select isnt(
  (select auth.uid()), :'ta'::uuid,
  '(a0b) identity anchor: under tenant B''s context auth.uid() is NOT tenant A — the two read contexts below are genuinely two identities, so (a3)''s equality is INVARIANCE and not blindness (rls/DESIGN.md §12)'
);
select set_config('role', 'postgres', true);

-- (a1) non-vacuous positive: tenant A reads both seeded rows.
select _rls.set_tenant(:'ta'::uuid);
select is(
  (select count(*) from pfin.cpi_u_nonpublication)::bigint, 2::bigint,
  '(a1) global shared-read: tenant A reads both seeded non-publication rows (USING (true) — not over-restrictive, and the rows really exist)'
);
select md5(coalesce(string_agg(t::text, '|' order by t.cpi_period), '')) as diga
  from pfin.cpi_u_nonpublication t \gset
select set_config('role', 'postgres', true);

-- (a2) the golden property: tenant B reads the SAME rows (shared, not isolated).
select _rls.set_tenant(:'tb'::uuid);
select is(
  (select count(*) from pfin.cpi_u_nonpublication)::bigint, 2::bigint,
  '(a2) global shared-read: tenant B ALSO reads both rows — shared public reference. RED if the SELECT policy were users_id-scoped or otherwise tenant-discriminating, which on a table with NO users_id would be a defect, not isolation'
);
select md5(coalesce(string_agg(t::text, '|' order by t.cpi_period), '')) as digb
  from pfin.cpi_u_nonpublication t \gset
select set_config('role', 'postgres', true);

-- (a3) content equality, not merely cardinality: a policy leaking a DIFFERENT row set of the
--      same size would pass (a1)/(a2) and fail here.
select is(
  :'diga'::text, :'digb'::text,
  '(a3) global shared-read, CONTENT-equal: tenant A and tenant B receive byte-identical row sets (full-row digest, not a count) — RED if any per-identity discrimination were introduced on a table that has no identity column'
);

-- =====================================================================
-- LEG (b) NO-FORGE / NO-ERASE at authenticated — ACL-layer denial, message-precise.
--   Run under authenticated A: even a legitimate tenant cannot write reference data.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
select throws_like(
  $$ insert into pfin.cpi_u_nonpublication (cpi_period, published_value_raw) values ('2023-01-01', 'x') $$,
  'permission denied for table cpi_u_nonpublication',
  '(b1) LOAD-BEARING no-forge: authenticated INSERT denied at the GRANT layer (SELECT-only grant, no write policy) — a user cannot FORGE a non-publication record, which would make a real unexplained gap read as "the source published no value" in 064''s classification'
);
select throws_like(
  $$ update pfin.cpi_u_nonpublication set published_value_raw = 'forged' where cpi_period = '2025-10-01' $$,
  'permission denied for table cpi_u_nonpublication',
  '(b2) LOAD-BEARING no-forge: authenticated UPDATE of a real seeded record denied at the GRANT layer (no UPDATE grant)'
);
select throws_like(
  $$ delete from pfin.cpi_u_nonpublication where cpi_period = '2025-10-01' $$,
  'permission denied for table cpi_u_nonpublication',
  '(b3) LOAD-BEARING no-erase: authenticated DELETE of a real seeded record denied at the GRANT layer — the evidence that a period was published valueless cannot be destroyed by a user'
);
select throws_like(
  $$ truncate pfin.cpi_u_nonpublication $$,
  'permission denied for table cpi_u_nonpublication',
  '(b4) authenticated TRUNCATE is denied at the GRANT layer, in FRONT of the statement-level trigger (REVOKE TRUNCATE FROM PUBLIC + no grant) — the trigger itself is proven at the OWNER tier in (d3), the only tier that actually holds TRUNCATE'
);
select set_config('role', 'postgres', true);

-- (b5) RLS-layer write denial (catalog fact; role-independent — run privileged).
select is(
  (select count(*) from pg_policies
     where schemaname = 'pfin' and tablename = 'cpi_u_nonpublication' and cmd <> 'SELECT')::bigint,
  0::bigint,
  '(b5) write fails closed at the RLS layer too: ZERO non-SELECT (write/ALL) policies exist on cpi_u_nonpublication — defence-in-depth BEHIND the ACL fence asserted in (b1)-(b4). RED if an INSERT/UPDATE/DELETE/ALL policy were added'
);

-- (b6) THE THIRD ANON FENCE, and the one that is easiest to lose. Discovered by MEASUREMENT
--      while building (V2): with schema USAGE and a table SELECT both granted to anon, anon
--      still reads ZERO rows — because this policy is `TO authenticated`, and a role outside a
--      policy's role list matches no policy at all, so RLS default-denies. That role list is
--      therefore a fence in its own right, and nothing else in this file would notice its loss.
select is(
  (select roles::text from pg_policies
     where schemaname = 'pfin' and tablename = 'cpi_u_nonpublication'
       and policyname = 'cpi_u_nonpublication_select'),
  '{authenticated}',
  '(b6) the SELECT policy is scoped TO authenticated and to NOTHING ELSE — the third independent anon fence, behind schema USAGE (h11) and the table ACL (h10). MEASURED in (V2b): with both of those opened, this one still holds. RED if `anon` (or `public`) were ever added to the policy''s role list, which is a one-line change no grant-oriented review would flag'
);

-- =====================================================================
-- LEG (c) SERVICE_ROLE — the writer, in its PRODUCTION ACL posture (append-only).
--   These run BEFORE leg (d5)'s test-only grant, so that grant cannot mask them.
-- =====================================================================
select set_config('role', 'service_role', true);
-- (c1) the append path is LIVE (a green write-fence is not a vacuously-absent grant).
select lives_ok(
  $$ insert into pfin.cpi_u_nonpublication (cpi_period, published_value_raw) values ('2022-05-01', '-') $$,
  '(c1) service_role writer: INSERT of a NEW period SUCCEEDS — proves the 063 service_role INSERT grant is LIVE, and therefore that (b1) is a MISSING authenticated grant rather than a blanket table lock'
);
-- (c2) the writer can read its own record back (the `on conflict do nothing` path needs SELECT).
select isnt(
  (select count(*) from pfin.cpi_u_nonpublication)::bigint, 0::bigint,
  '(c2) service_role writer: SELECT is granted and returns rows — the writer can read the record back (its `on conflict (cpi_period) do nothing` append depends on reaching the table at all)'
);
-- (c3)-(c5) least-privilege: everything ELSE is denied, and denied at the ACL layer.
select throws_like(
  $$ update pfin.cpi_u_nonpublication set published_value_raw = 'x' where cpi_period = '2025-10-01' $$,
  'permission denied for table cpi_u_nonpublication',
  '(c3) service_role least-privilege: UPDATE is denied at the GRANT layer — MEASURED, and stated as the ACL layer deliberately: the immutability trigger is NEVER REACHED on this path, so asserting the trigger message here would be a false-RED. The trigger is proven against this same role in (d5), with the ACL opened test-only'
);
select throws_like(
  $$ delete from pfin.cpi_u_nonpublication where cpi_period = '2025-10-01' $$,
  'permission denied for table cpi_u_nonpublication',
  '(c4) service_role least-privilege: DELETE is denied at the GRANT layer (the ACL half of append-only; the trigger half is (d6))'
);
select throws_like(
  $$ truncate pfin.cpi_u_nonpublication $$,
  'permission denied for table cpi_u_nonpublication',
  '(c5) service_role least-privilege: TRUNCATE is denied at the GRANT layer (063''s REVOKE TRUNCATE FROM PUBLIC holds and no grant restores it; the trigger half is (d7))'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- LEG (h) PRODUCTION ACL MATRIX (has_table_privilege facts; role-agnostic, run privileged).
--   Asserted BEFORE leg (d5)'s test-only grant.
-- =====================================================================
select ok(
  has_table_privilege('authenticated', 'pfin.cpi_u_nonpublication', 'SELECT'),
  '(h1) ACL positive: authenticated HOLDS SELECT (the global-read path — (a1)/(a2) are not vacuously blocked at the ACL layer, so they are genuine RLS tests)'
);
select ok(
  not has_table_privilege('authenticated', 'pfin.cpi_u_nonpublication', 'INSERT'),
  '(h2) least-privilege: authenticated holds NO INSERT — proves (b1) is a missing grant rather than an RLS reject, and guards the SELECT-only grant against widening. (V1) proves this negative has teeth'
);
select ok(
  not has_table_privilege('authenticated', 'pfin.cpi_u_nonpublication', 'UPDATE')
  and not has_table_privilege('authenticated', 'pfin.cpi_u_nonpublication', 'DELETE'),
  '(h3) least-privilege: authenticated holds neither UPDATE nor DELETE — a user can neither revise nor erase a recorded non-publication'
);
select ok(
  not has_table_privilege('authenticated', 'pfin.cpi_u_nonpublication', 'TRUNCATE'),
  '(h4) least-privilege: authenticated holds NO TRUNCATE (063''s explicit REVOKE ... FROM PUBLIC holds against a broad platform default grant)'
);
select ok(
  has_table_privilege('service_role', 'pfin.cpi_u_nonpublication', 'SELECT'),
  '(h5) ACL positive: service_role HOLDS SELECT (the writer reads the record back)'
);
select ok(
  has_table_privilege('service_role', 'pfin.cpi_u_nonpublication', 'INSERT'),
  '(h6) ACL positive: service_role HOLDS INSERT — the append path, and the ONLY mutation any role is meant to have'
);
select ok(
  not has_table_privilege('service_role', 'pfin.cpi_u_nonpublication', 'UPDATE'),
  '(h7) LOAD-BEARING least-privilege: service_role holds NO UPDATE — the ACL half of append-only, in FRONT of the immutability trigger. RED if a `grant update` ever reached the writer (the plausible drift: someone "fixing" a failing `on conflict do update`)'
);
select ok(
  not has_table_privilege('service_role', 'pfin.cpi_u_nonpublication', 'DELETE'),
  '(h8) LOAD-BEARING least-privilege: service_role holds NO DELETE — a recorded non-publication is retained even after the period is later published; there is no erase path for the writer'
);
select ok(
  not has_table_privilege('service_role', 'pfin.cpi_u_nonpublication', 'TRUNCATE'),
  '(h9) least-privilege: service_role holds NO TRUNCATE (the statement-level trigger asserted in (d3) is the regardless-of-grant backstop behind this)'
);
select ok(
  not has_table_privilege('anon', 'pfin.cpi_u_nonpublication', 'SELECT'),
  '(h10) anon zero-grant: anon holds NO SELECT. CRITICAL on a USING (true) table — the policy has NO row filter to fall back on, so anon would read EVERY row the instant a grant landed. (V2) measures exactly that. ⚠ REMOTE CONSUMER: 064''s (A2) triage message cites this leg (with (h11) and 053''s (h6)) as a fact its downgrade-to-least-privilege depends on. A red here VOIDS that downgrade'
);
select ok(
  not has_schema_privilege('anon', 'pfin', 'USAGE'),
  '(h11) anon is fenced ONE LAYER IN FRONT of the table ACL: it holds no USAGE on schema pfin (MEASURED: anon''s denial message is "permission denied for schema pfin", never the table ACL message) — so (h10) is the second fence, not the only one. ⚠ REMOTE CONSUMER: 064''s (A2) triage message cites this leg (with (h10) and 053''s (h6)) as a fact its downgrade-to-least-privilege depends on. A red here VOIDS that downgrade. 064''s D9 fence ladder measures the same three-fence structure from the function side and agrees with this leg''s measured denial message'
);

-- (n1) anon behavioural probe — the ACL facts above, exercised rather than inspected.
select ok(
  _rls.stmt_denied_as('anon', 'select 1 from pfin.cpi_u_nonpublication'),
  '(n1) anon behavioural: an actual SELECT attempted AS anon is REFUSED with insufficient_privilege (42501). Probed via _rls.stmt_denied_as (called and asserted at postgres) because anon holds no USAGE on the pgTAP schema either — running the assertion under anon would fail for the wrong reason'
);

-- =====================================================================
-- LEG (d) IMMUTABILITY TRIGGERS — the ONLY fence that holds where ACL and RLS do not.
-- =====================================================================
-- (d0) tier identity anchor: without it, leg (d) could be fencing some other role.
select is(
  (select tableowner from pg_tables where schemaname = 'pfin' and tablename = 'cpi_u_nonpublication'),
  'postgres',
  '(d0) owner-tier identity anchor: pfin.cpi_u_nonpublication is owned by `postgres` — the identity for which NO ACL layer exists (ownership confers the privilege intrinsically) and RLS is bypassed, so (d1)-(d4) have the TRIGGERS as their sole gate by construction. RED if ownership moved'
);
-- (d1) row-level UPDATE fence, at the tier where nothing else can deny it.
select throws_like(
  $$ update pfin.cpi_u_nonpublication set published_value_raw = 'rewritten' where cpi_period = '2025-10-01' $$,
  '%is immutable%UPDATE blocked%',
  '(d1) OWNER TIER immutability: an UPDATE by the table owner is blocked by the ROW-level trigger, message-precise. This is the privileged-context fence RLS default-deny cannot provide — RED if fn_cpi_u_nonpublication_block_mutation or its binding were removed, after which a migration script or a human psql session could silently rewrite the observed evidence. (V4) proves this has teeth'
);
-- (d2) the erasure half, asserted on a DIFFERENT row so the fence is proven table-wide.
select throws_like(
  $$ delete from pfin.cpi_u_nonpublication where cpi_period = '2024-03-01' $$,
  '%is immutable%DELETE blocked%',
  '(d2) OWNER TIER immutability: a DELETE by the table owner is blocked by the ROW-level trigger, asserted on a DIFFERENT row than (d1) so the fence is proven table-wide. Per ADR-049 a gap you did not record cannot be retrospectively classified — an erased record is unrecoverable in DATA, not just in schema'
);
-- (d3) the DISTINCT statement-level fence — the bulk-wipe path, at the only tier holding TRUNCATE.
select throws_like(
  $$ truncate pfin.cpi_u_nonpublication $$,
  '%is immutable%TRUNCATE blocked%',
  '(d3) OWNER TIER TRUNCATE fence: blocked by the STATEMENT-level trigger, with a message DISTINCT from the row-level fence so one trigger can never be credited for the other. Row-level triggers do NOT fire on TRUNCATE, so (d1)/(d2) passing says NOTHING about this path — the entire record would go in one statement. (V3) measures that world'
);
-- (d4) the append path must stay OPEN at the owner tier (guards an over-broad fence).
select lives_ok(
  $$ insert into pfin.cpi_u_nonpublication (cpi_period, published_value_raw) values ('2021-07-01', '-') $$,
  '(d4) OWNER TIER append allowed: an INSERT by the owner SUCCEEDS. Together with (d1)-(d3) this is the full "append allowed, mutate blocked" property. RED if the immutability fence were over-broad — which would be a silent ingest outage presenting as a control'
);

-- ---------------------------------------------------------------------
-- (d5)-(d7) THE CROSS-TIER ASSERTION. service_role's production ACL denies UPDATE/DELETE/
--   TRUNCATE before any trigger runs (c3)-(c5), so those legs prove nothing about the TRIGGERS
--   for the real writer identity. Here the ACL is opened TEST-ONLY (the 004/054 idiom, inside a
--   savepoint, rolled back) so the TRIGGER is the sole remaining gate. This is the assertion
--   that survives a future grant-widening PR: even then, the record cannot be rewritten.
--   The production ACL is asserted separately in (h5)-(h9), ABOVE, so this grant cannot mask it.
-- ---------------------------------------------------------------------
savepoint d_testonly_grant;
grant update, delete, truncate on pfin.cpi_u_nonpublication to service_role;
select set_config('role', 'service_role', true);
select throws_like(
  $$ update pfin.cpi_u_nonpublication set published_value_raw = 'rewritten' where cpi_period = '2025-10-01' $$,
  '%is immutable%UPDATE blocked%',
  '(d5) ⭐ CROSS-TIER: with the writer''s ACL opened TEST-ONLY, a service_role UPDATE is stopped by the TRIGGER rather than by the grant — the property that survives a future `grant update to service_role` landing in some unrelated PR. service_role also bypasses RLS, so the trigger is genuinely the last fence here'
);
select throws_like(
  $$ delete from pfin.cpi_u_nonpublication where cpi_period = '2025-10-01' $$,
  '%is immutable%DELETE blocked%',
  '(d6) CROSS-TIER: with DELETE granted test-only, a service_role DELETE is stopped by the row-level TRIGGER — the erase path is fenced for the writer identity independently of its ACL'
);
select throws_like(
  $$ truncate pfin.cpi_u_nonpublication $$,
  '%is immutable%TRUNCATE blocked%',
  '(d7) CROSS-TIER: with TRUNCATE granted test-only, a service_role TRUNCATE is stopped by the STATEMENT-level trigger — the bulk-wipe path is fenced for the writer identity independently of its ACL'
);
select set_config('role', 'postgres', true);
rollback to savepoint d_testonly_grant;

-- ---------------------------------------------------------------------
-- (d8)/(d9) THE WRITER'S DOCUMENTED CONTRACT, asserted as behaviour rather than trusted as a
--   comment. 063: "the ingest MUST append with `on conflict (cpi_period) do nothing`;
--   `do update` reaches the UPDATE fence and fails loud. First observation wins; a re-run is a
--   no-op." Run at the owner tier: under service_role's production ACL, `do update` would be
--   ACL-denied and would prove nothing about the fence.
-- ---------------------------------------------------------------------
select throws_like(
  $$ insert into pfin.cpi_u_nonpublication (cpi_period, published_value_raw) values ('2025-10-01', 'restated')
     on conflict (cpi_period) do update set published_value_raw = excluded.published_value_raw $$,
  '%is immutable%UPDATE blocked%',
  '(d8) writer contract: `on conflict DO UPDATE` REACHES THE UPDATE FENCE and fails loud — 063''s STANDING REQUIREMENT asserted as behaviour. RED if the fence let a restatement through, which would silently overwrite a FIRST observation with a later one'
);
select set_config('role', 'service_role', true);
select lives_ok(
  $$ insert into pfin.cpi_u_nonpublication (cpi_period, published_value_raw) values ('2025-10-01', 'ignored')
     on conflict (cpi_period) do nothing $$,
  '(d9a) writer contract: `on conflict DO NOTHING` is accepted — a monthly re-fetch of the same series is BOUNDED rather than accumulating one duplicate row per run, forever'
);
select set_config('role', 'postgres', true);
select is(
  (select published_value_raw from pfin.cpi_u_nonpublication where cpi_period = '2025-10-01'),
  '-',
  '(d9b) writer contract, FIRST-OBSERVATION-WINS: after the re-run above, the stored row is UNCHANGED (still the original ''-'' token, not ''ignored''). (d9a) alone would pass on a silently-updating upsert — this is the assertion that makes the no-op real'
);

-- =====================================================================
-- LEG (e) VALUE FENCES — role-agnostic CHECKs, asserted under the REAL WRITER (service_role
--   bypasses RLS but NOT a table CHECK). Constraint-name-precise.
-- =====================================================================
select set_config('role', 'service_role', true);
select throws_like(
  $$ insert into pfin.cpi_u_nonpublication (cpi_period) values ('2025-12-15') $$,
  '%cpi_u_nonpublication_period_first_of_month%',
  '(e1) grain fence: a non-first-of-month cpi_period is REJECTED by cpi_u_nonpublication_period_first_of_month (constraint-name-precise) even under the writer. LOAD-BEARING: a mis-keyed row would silently never join cpi_u_index and never match a 064 lookup, making a WRITTEN record indistinguishable from one NEVER WRITTEN — which defeats the table''s entire purpose'
);
select throws_like(
  $$ insert into pfin.cpi_u_nonpublication (cpi_period, published_value_raw) values ('2025-12-01', repeat('x', 65)) $$,
  '%cpi_u_nonpublication_raw_bounded%',
  '(e2) bound fence: a 65-character published_value_raw is REJECTED by cpi_u_nonpublication_raw_bounded — the column is service_role-written on a GLOBAL table with no tenant scoping to limit blast radius, so the bound removes an unbounded-text write vector by construction'
);
select lives_ok(
  $$ insert into pfin.cpi_u_nonpublication (cpi_period, published_value_raw) values ('2025-12-01', repeat('x', 64)) $$,
  '(e3) non-vacuous bound control: exactly 64 characters is ACCEPTED — proves (e2) fences the stated boundary and not legitimate tokens (the observed real case is ONE character). Guards an over-broad CHECK'
);
select lives_ok(
  $$ insert into pfin.cpi_u_nonpublication (cpi_period, published_value_raw) values ('2025-11-01', null) $$,
  '(e4) NULL raw control: published_value_raw NULL is ACCEPTED — 063 documents NULL as "the ingest did not capture the raw token", NOT as "the source emitted an empty value". RED if the column were tightened to NOT NULL, which would make an uncaptured token unrecordable'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- LEG (f) PK GRAIN — one row per period (the key the writer's ON CONFLICT depends on).
-- =====================================================================
select throws_ok(
  $$ insert into pfin.cpi_u_nonpublication (cpi_period, published_value_raw) values ('2025-10-01', 'dup') $$,
  '23505', null,
  '(f1) PK grain: a duplicate cpi_period on a BARE insert is REJECTED with unique_violation (23505), SQLSTATE-precise so it can never be credited to the immutability trigger — this is the one-row-per-period key that makes `on conflict (cpi_period) do nothing` well-defined'
);

-- =====================================================================
-- LEG (V) INVERSION — the negatives above, broken on purpose, inside savepoints.
--   Each proves an assertion has TEETH. See the (V) block in the header.
-- =====================================================================

-- ---- (V1) does the authenticated-write negative have teeth? ----
savepoint v_auth_grant;
grant insert on pfin.cpi_u_nonpublication to authenticated;
select ok(
  has_table_privilege('authenticated', 'pfin.cpi_u_nonpublication', 'INSERT'),
  '(V1-AUTHENTICATED-WRITE-NEGATIVE-HAS-TEETH) (h2) is not vacuous: a single `grant insert to authenticated` flips it. Needed because an absence assertion whose subject can never appear proves nothing (rls/DESIGN.md §10) — `not has_table_privilege` against a role that never holds grants looks identical to a real REVOKE'
);
rollback to savepoint v_auth_grant;

-- ---- (V2) does the anon fence have teeth, and what exactly does it hold back? ----
savepoint v_anon_grant;
grant usage on schema pfin to anon;
grant select on pfin.cpi_u_nonpublication to anon;
select ok(
  not _rls.stmt_denied_as('anon', 'select 1 from pfin.cpi_u_nonpublication'),
  '(V2a-ANON-ACL-FENCES-HAVE-TEETH) (n1)/(h10)/(h11) are not vacuous: with schema USAGE and a table SELECT granted, the statement anon was refused for is no longer refused — so the 42501 in (n1) really came from those two fences and not from something incidental. BOTH had to be opened, which is itself the measurement: (h11) is a real second fence, not a restatement of (h10)'
);
-- The privileged total is captured FIRST, as postgres, so the comparison below is against a
-- known quantity rather than against itself (a `count = count` form would be tautological).
select count(*) as privtotal from pfin.cpi_u_nonpublication \gset
select set_config('role', 'anon', true);
select count(*) as anontotal from pfin.cpi_u_nonpublication \gset
select set_config('role', 'postgres', true);
-- ⚠ REFUTED HYPOTHESIS, KEPT AS THE ASSERTION. This leg was first written to claim "…and now
--   anon reads every row", on the reasoning that USING (true) has no row predicate to fall back
--   on. THE RUN SAID OTHERWISE: 0 rows. The policy is `TO authenticated`, and a role outside a
--   policy's role list matches NO policy, so RLS default-denies regardless of the grants. The
--   claim was wrong and the fence is stronger than the claim; the leg now asserts what was
--   measured, and (b6) pins the role list that produced it.
select is(
  :'anontotal'::bigint, 0::bigint,
  '(V2b-A-THIRD-FENCE-SURVIVES-BOTH-GRANTS) ⚠ …and yet anon STILL reads ZERO rows with USAGE and SELECT both granted, because policy cpi_u_nonpublication_select is TO authenticated — a role outside a policy''s role list matches no policy at all and RLS default-denies. MEASURED, not reasoned: the first draft of this leg asserted the opposite and was refuted by the run'
);
-- (V2c) …and now reach the property the refuted claim was about, by opening the LAST fence.
create policy cpi_u_nonpublication_qa_anon_probe on pfin.cpi_u_nonpublication
  for select to anon using (true);
select set_config('role', 'anon', true);
select count(*) as anontotal2 from pfin.cpi_u_nonpublication \gset
select set_config('role', 'postgres', true);
select is(
  :'anontotal2'::bigint, :'privtotal'::bigint,
  '(V2c-USING-TRUE-HAS-NO-ROW-FILTER) ⭐ with the role list ALSO opened, anon reads EVERY row the privileged session can see — not a filtered subset. THE POINT: on a tenant-scoped table a stray grant leaks one tenant''s rows and the tenant predicate still bounds the damage; here USING (true) has no predicate to fall back on, so the last fence to fall exposes the entire table. That is what makes (h10)/(h11)/(b6) merge-gate assertions rather than hygiene — and note it took THREE independent changes to get here'
);
rollback to savepoint v_anon_grant;

-- ---- (V3) does the TRUNCATE fence have teeth — and are row-level triggers really blind to it? ----
savepoint v_truncate_fence;
drop trigger cpi_u_nonpublication_block_truncate on pfin.cpi_u_nonpublication;
select lives_ok(
  $$ truncate pfin.cpi_u_nonpublication $$,
  '(V3a-TRUNCATE-FENCE-HAS-TEETH) (d3) is not vacuous: with ONLY the statement-level trigger dropped — the row-level UPDATE/DELETE fence left fully in place — a TRUNCATE succeeds. That is the measured proof that row-level triggers do NOT fire on TRUNCATE, so (d1)/(d2) can never cover this path'
);
select is(
  (select count(*) from pfin.cpi_u_nonpublication)::bigint, 0::bigint,
  '(V3b-THE-WHOLE-RECORD-GOES-IN-ONE-STATEMENT) …and the table is EMPTY afterwards. The consequence is stated as data, not as risk language: every recorded non-publication is gone in one statement, and per ADR-049 a gap you did not record cannot be retrospectively classified — this loss is irreversible in DATA, not merely in schema'
);
rollback to savepoint v_truncate_fence;

-- ---- (V4) does the row-level immutability fence have teeth? ----
savepoint v_row_fence;
drop trigger cpi_u_nonpublication_block_mutation on pfin.cpi_u_nonpublication;
select lives_ok(
  $$ update pfin.cpi_u_nonpublication set published_value_raw = 'rewritten' where cpi_period = '2025-10-01' $$,
  '(V4a-ROW-FENCE-HAS-TEETH) (d1)/(d2)/(d5)/(d6)/(d8) are not vacuous: with the row-level trigger dropped, the owner UPDATE that (d1) asserts is blocked goes straight through'
);
select is(
  (select published_value_raw from pfin.cpi_u_nonpublication where cpi_period = '2025-10-01'),
  'rewritten',
  '(V4b-THE-EVIDENCE-REALLY-CHANGES) …and the STORED VALUE really changed — asserted on the datum, not merely on the absence of an exception, so (V4a) cannot pass on a silently-no-op UPDATE. The rewritten token is the evidence 063 exists to preserve'
);
rollback to savepoint v_row_fence;

-- ---- (V5) STRUCTURAL, AND DELIBERATELY LAST + OUTSIDE ANY SAVEPOINT ----
--   Two jobs, both real. (i) It asserts that the (V) block undid everything it did: both
--   triggers are back, and neither of the two grants it opened survived. A (V) block that
--   silently left a fence broken would make every assertion above it untrustworthy from that
--   point on, and nothing else in this file looks. (ii) It re-establishes pgTAP's plan counter
--   after the savepoint rewinds — see the harness note in the header. Moving this leg off the
--   end, or inside a savepoint, silently re-breaks the plan arithmetic.
select ok(
  (select count(*) from pg_trigger t
     where t.tgrelid = 'pfin.cpi_u_nonpublication'::regclass
       and not t.tgisinternal
       and t.tgname in ('cpi_u_nonpublication_block_mutation', 'cpi_u_nonpublication_block_truncate')) = 2
  and not has_table_privilege('authenticated', 'pfin.cpi_u_nonpublication', 'INSERT')
  and not has_table_privilege('anon', 'pfin.cpi_u_nonpublication', 'SELECT')
  and not has_schema_privilege('anon', 'pfin', 'USAGE'),
  '(V5-FENCES-RESTORED-AND-PLAN-COUNTER-REARMED) structural: after the inversion block, BOTH immutability triggers are present again and neither grant it opened survived — the (V) legs undid everything they did, so no assertion above was evaluated against a fence this file had quietly broken. It also re-arms pgTAP''s plan counter after the savepoint rewinds, so this file cannot emit a spurious "planned N but ran M" that would train a reader to discount the one diagnostic distinguishing a genuinely aborted run'
);

select * from finish();
rollback;
