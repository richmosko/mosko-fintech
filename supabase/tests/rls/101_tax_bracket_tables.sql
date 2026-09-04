-- =====================================================================
-- Per-Wave battery — pfin.tax_bracket_schedule + pfin.tax_bracket_row:
--   grain (C), ADR-011 Decision 3 CANONICAL #18 (matched-tenant, P1 local
--   anchor, the 012/074 shape) on tax_bracket_row.schedule_id + a DEFERRED
--   CONSTRAINT TRIGGER carrying TWO SET PROPERTIES (leg A zero-floor, leg B
--   rate-monotonicity) that a per-row BEFORE trigger cannot observe + full
--   authenticated CRUD RLS on BOTH tables + the 025 aal2 step-up backstop on
--   every policy (SELF-259; V1.4 pre-flight sitting R4; V1-SHIP-BLOCK;
--   JOINT-REVIEW-MANDATORY per the migration's own Sec-gate)
-- =====================================================================
-- BINDS TO MIGRATION: supabase/migrations/101_tax_bracket_tables.sql
--   - pfin.tax_bracket_schedule (id, users_id NOT NULL DEFAULT auth.uid() ->
--       auth.users ON DELETE CASCADE, tax_year smallint, schedule_type
--       pfin.tax_schedule_type_enum, schedule_label text NOT NULL (length
--       between 1 and 500, named tax_bracket_schedule_schedule_label_check —
--       ADDED at Sec's SELF-260 review, rulings E27/E29, b073641; NOT
--       FK-shaped, joins no Decision-3 family, adds no §10 instance — see the
--       migration header's own per-column disposition), standard_deduction
--       numeric(20,4) NOT NULL >= 0 <> NaN, tax_balance_prior_year
--       numeric(20,4) NULL <> NaN (no sign bound — an overpayment is real),
--       created/updated_at, unique(users_id, tax_year, schedule_type)). RLS
--       direct-owner ANDed with the 025 aal2 clause on all four verbs; full
--       authenticated CRUD; anon zero-grant; service_role ungranted.
--   - pfin.tax_bracket_row (id, users_id NOT NULL DEFAULT auth.uid() ->
--       auth.users ON DELETE CASCADE — grain (C): the CHILD'S OWN tenant
--       fact, beside schedule_id, not instead of it — schedule_id bigint NOT
--       NULL -> tax_bracket_schedule(id) ON DELETE CASCADE, bracket_floor
--       numeric(20,4) >= 0 <> NaN, bracket_rate numeric(12,8) 0<=x<=1 <> NaN
--       (FRACTION unit, 0.22 = 22%), created_at, unique(schedule_id,
--       bracket_floor)). RLS is a DIRECT users_id = auth.uid() equality, NOT
--       a join to the parent (grain (C) supersedes the drafted (A) join
--       form). Same aal2 clause on all four verbs.
--   - pfin.fn_tax_bracket_row_matched_schedule() — BEFORE INSERT OR UPDATE,
--       ADR-011 Decision 3 CANONICAL #18, P1 local-anchor (the 012/074
--       shape). Two legs: 1 unresolvable (no such schedule, or RLS hides
--       it — where a plain cross-tenant reference lands), 2 cross-tenant
--       (resolved, owner differs — reachable BOTH by a plain authenticated
--       ownership-forge AND by an RLS-exempt writer). SECURITY INVOKER,
--       set search_path = '', NULL-safe fail-closed, NO EXECUTE grant to
--       authenticated (Postgres does not check EXECUTE when firing a
--       trigger — 074 precedent).
--   - pfin.fn_tax_bracket_row_schedule_invariants() — AFTER INSERT OR UPDATE
--       OR DELETE CONSTRAINT TRIGGER, DEFERRABLE INITIALLY DEFERRED (fires
--       at COMMIT / SET CONSTRAINTS IMMEDIATE — the 029/038 DEFERRED-Σ test
--       model, reused here for the FIRST deferred set-fence on a settings
--       table). LEG A: non-empty schedule's lowest bracket_floor must be 0
--       (monotonicity cannot see this). LEG B: bracket_rate must be
--       NON-DECREASING in ascending bracket_floor order (floor ordering is
--       NOT a leg — unique(schedule_id, bracket_floor) already makes floors
--       a distinct, hence totally ordered, set; a floor-ordering leg could
--       never fire — E6, team-lead ruling under delegation, 2026-09-03).
--       SECURITY INVOKER, set search_path = ''. Its sufficiency rests on
--       #18: strike the tenant fence and this one narrows silently. Gained a
--       `for update` lock on the parent schedule row as its FIRST statement
--       after the schedule resolves (Sec F-1 option B, GREEN re-review
--       2026-09-04, 6b3aa61) — pinned below at (SF-L1)/(SF-L2), the second
--       load-bearing on ORDER, not merely presence. Its THIRD raise (the
--       unresolved-parent path, the observer for #18's absence) is
--       UNTESTABLE in pgTAP: reaching it needs the matched-tenant FK inert
--       (session_replication_role = replica, a superuser-only GUC) or the FK
--       itself struck, and 054's own battery already declines to assert
--       under that GUC — recorded here rather than left silent (Sec R-1).
--   - trigger tax_bracket_schedule_set_updated_at -> fn_refresh_updated_at
--       (001 DEFINER allowlist entry), PARENT ONLY.
--   - pfin.fn_tax_bracket_schedule_replace_all(...) — ADDED at fcd8e98/
--       a2498ea (origin/feature/self-259), AFTER this file's original
--       drafting and NOT in the original 10-item dispatch (BLOCK RA below).
--       The atomic replace-all write body: SECURITY INVOKER, EXECUTE granted
--       to authenticated (the opposite grant shape from the two trigger
--       fences — a direct call IS its only use). Its FIRST statement is a
--       `FOR UPDATE` lock on the caller's own schedule row, which — under
--       INVOKER, composing with RLS — IS the tenant fence: another tenant's
--       schedule_id, or an absent one, resolves to zero rows and raises, ONE
--       message for both cases (never an existence oracle). Takes NO TENANT
--       PARAMETER. Validates p_rows' shape (a JSON array of {bracket_floor,
--       bracket_rate} objects, both JSON numbers) before delete-then-insert-
--       then-update. The deferred set fence and #18 still fire at COMMIT,
--       AFTER the function returns — a caller with no exception from the
--       call has not yet been told the write is valid.
--       ⚠ AT b073641 (Sec's SELF-260 E27/E29) THE SIGNATURE GAINED
--       `p_schedule_label text` AS THE FOURTH POSITIONAL PARAMETER —
--       (p_schedule_id, p_tax_year, p_schedule_type, p_schedule_label,
--       p_standard_deduction, p_tax_balance_prior_year, p_rows). Every one of
--       this file's 12 pre-existing calls (BLOCK RA) was re-pinned to supply
--       it in position; none changed shape otherwise. The function's own
--       UPDATE step now also writes schedule_label, asserted at (RA7e).
--   - the parent's `tax_year` now carries `check (tax_year >= 1913)`
--       (`tax_bracket_schedule_tax_year_check`, added at fcd8e98) — 1913 is
--       the first US federal income-tax year. Not independently battery-
--       tested here (added after this file's original 10-item scope; every
--       tax_year literal this file uses is already >= 1913, so no existing
--       leg depends on a value the new CHECK would reject).
-- Prereqs exercised (already on main / applied by Backend on the reset
--   stack): 001 (pfin schema + fn_refresh_updated_at), 024
--   (pfin.user_settings.mfa_policy), 025 (the aal2 backstop clause shape
--   this migration reuses byte-faithfully), auth.users.
-- Reuses the 090/074/029/038 idiom: \ir verbs, ALL-LOWERCASE \gset literals,
--   MESSAGE-precise throws_like / SQLSTATE-precise throws_ok, role restored
--   to postgres between blocks (PR #121 root-cause), savepoint/rollback
--   around every exception-raising probe, AND the 029/038 DEFERRED-Σ
--   `set constraints all deferred` / `... all immediate` choreography for
--   the two set-fence legs (item 3/4/5 below) — the FIRST reuse of that
--   idiom on a Lock-14 settings table rather than an audit-class ledger.
--
-- ┌─ WHY `set constraints all immediate` IS THE FIRING LEVER, NOT A REAL COMMIT ┐
-- │ tax_bracket_row_schedule_invariants is DEFERRABLE INITIALLY DEFERRED — it   │
-- │ fires at COMMIT. This whole file is ONE `begin … rollback` transaction that │
-- │ never commits (deliberately — the two-tenant isolation posture). `set       │
-- │ constraints all immediate` forces the pending trigger events to fire NOW,   │
-- │ inside the transaction, with EXACT control over the moment — the 029/038    │
-- │ idiom, reused verbatim: (i) `set constraints all deferred` before staging a │
-- │ batch, (ii) fire the check by asserting ON the `set constraints all         │
-- │ immediate` statement itself (lives_ok = the batch was valid; throws_ok /    │
-- │ throws_like = it wasn't), (iii) `set constraints all deferred` again before │
-- │ staging the next batch. ⚠ Unlike 029's savepoint-wrapped exception legs, a  │
-- │ RAISE caught by `throws_ok`/`throws_like` does NOT roll back the earlier    │
-- │ INSERT statements in the same batch (pgTAP's exception trap is scoped to    │
-- │ the failing statement alone) — this file explicitly DELETEs a raised        │
-- │ batch's rows before staging the next one, exactly as 029/(1b) does, rather  │
-- │ than relying on an enclosing savepoint to clean up.                         │
-- └───────────────────────────────────────────────────────────────────────────┘
--
-- ┌─ E6 — "monotonicity" is bracket_RATE, never bracket_floor (team-lead ruling │
-- │ under delegation, 2026-09-03, quoted in the migration header) ─────────────┐
-- │ unique(schedule_id, bracket_floor) already makes one schedule's floors a    │
-- │ DISTINCT, hence TOTALLY ORDERED, set — a floor-ordering leg could never     │
-- │ fire (the by-construction-property watcher ADR-062 D2 rejects). Every       │
-- │ non-monotone-batch leg in this file (item 3, SF-M block) is written against │
-- │ RATES, per E6's explicit instruction, never against floor order.            │
-- └───────────────────────────────────────────────────────────────────────────┘
--
-- ┌─ AAL2 SHADOW ON ROW INSERT — INVESTIGATED, not assumed (074/(M5) precedent) ┐
-- │ fn_tax_bracket_row_matched_schedule is SECURITY INVOKER; its own read of    │
-- │ tax_bracket_schedule composes with tax_bracket_schedule_select's aal2       │
-- │ clause. If a totp caller below aal2 cannot see even their OWN schedule      │
-- │ through that composed read, INSERTing a row against it would raise LEG 1    │
-- │ unresolvable, not a WITH CHECK 42501 — the exact 074/(M5) shadow, on a      │
-- │ different table. (AAL-R-INS1) below asserts WHATEVER THIS FILE'S OWN        │
-- │ `pg_prove` RUN ACTUALLY SHOWS, not a prediction carried over from 074 —     │
-- │ see the leg's own comment for the measured mechanism.                       │
-- └───────────────────────────────────────────────────────────────────────────┘
--
-- §10 / DECISION 3: §10 catalogued ledger — read ADR-011 Decision 4 live,
--   never from here; this migration adds ZERO catalogued instances (Lock-14
--   user-facing-direct-DB-write surface). Decision-3 family: this migration
--   REALIZES CANONICAL #18 (tax_bracket_row.schedule_id -> tax_bracket_
--   schedule, matched-tenant, P1 local anchor). The fold-in into Decision
--   3's live enumeration is OWED BY THIS PR per E7 and is Architect's, not
--   this file's — this battery is the pgTAP proof the fence catches both
--   reachable legs (plain-authenticated ownership-forge AND RLS-exempt
--   writer), which the migration's own header states is BOTH, not either.
--
-- POSTURE (SECURITY §4.5): SYNTHETIC ONLY — fixed-UUID tenants from
--   _rls.tenant_a()/_rls.tenant_b(), plus a raw literal for the totp tenant
--   (D, suffixed '01' for migration 101 to keep this file's fixture
--   diffable against other batteries' fixed literals in the same cluster —
--   each file's txn rolls back independently so collision is not actually
--   live). NO PII / NO real account numbers / NO prod data. All inside one
--   rolled-back transaction.
--
-- ROLE/SCHEMA DISCIPLINE (PR #121 root-cause): `_rls` grants no USAGE to
--   authenticated, so NO `_rls.*` call runs under authenticated. Tenant
--   UUIDs are resolved to psql LITERALS via \gset at role=postgres; every
--   _rls.set_tenant(_aal) call happens at role=postgres and each block
--   restores role=postgres before the next. \gset var names are
--   ALL-LOWERCASE.
--
-- ⟦WIRE-VALIDATE⟧ originally authored against 101's sha 5f69249; RE-VERIFIED
--   against a2498ea (origin/feature/self-259) after Architect's two follow-on
--   commits (fcd8e98 tax_year CHECK + Decision 3 fold-in; a2498ea
--   fn_tax_bracket_schedule_replace_all) landed mid-authoring — BLOCK RA was
--   added to cover the new function, then EXTENDED per team-lead's own
--   follow-up briefing (its 5-item list, 11-15 — the paired control on 11,
--   updated_at on 13, the tax_year=1900 leg on 14, the FOR UPDATE catalog pin
--   + recorded-not-asserted race modes on 15, and the prior-row-set-intact
--   proof on 12). FURTHER EXTENDED at Sec's GREEN re-review flag R-1
--   (feature/self-259-sec, 6b3aa61) to pin the set fence's OWN parent-row
--   lock — both its presence (SF-L1) and, the load-bearing half, its ORDER
--   ahead of the set read (SF-L2) — since (RA10) pinned the FOR UPDATE lock
--   only on the replace-all function and left the set fence's own lock
--   unwatched.
--   RE-VERIFIED AGAIN against b073641 after Sec's SELF-260 review (rulings
--   E27/E29) added `schedule_label text not null` (CHECK length 1-500,
--   named tax_bracket_schedule_schedule_label_check) to the parent table and
--   inserted `p_schedule_label text` as the FOURTH positional parameter of
--   fn_tax_bracket_schedule_replace_all: every existing schedule INSERT (7
--   sites) and every existing replace-all call (12 sites) was re-pinned to
--   supply it, and 7 new legs were added (CAT6/CAT7 column-shape catalog
--   pins, CHK9-CHK11 the CHECK bound by constraint name, LBL-R per-tenant
--   isolation on the new column, RA7e the replace-all write-then-read-back).
--   Verified on a scratch DB built FRESH via sequential migration apply
--   (001→099 + 101 at b073641, NOT a `pfin_tmpl` clone — a `create or
--   replace` that changes a function's parameter list ADDS an overload
--   rather than replacing it on a DB that already had the old
--   7-argument-without-label signature, so a stale template could silently
--   carry both) via `pg_prove` (never bare `psql` — a plan under-run exits 0
--   there). `supabase db reset` is mechanically banned and was not used;
--   F/CTO's local dev DB was not touched.
--   plan(100): 8 structural policy (S1-S8, tenant/aal2 split per table,
--   USING/WITH CHECK halves per 090's S6a/b masking lesson) + 5 grants
--   (GR1-GR5: anon zero both tables, service_role zero both tables,
--   authenticated full CRUD per table x2, anon behavioral throw) + 1
--   function posture (FN1, all THREE functions combined) + 7 catalog pins
--   (CAT1-CAT5: both triggers' deferrable flags, the enum's 3 labels, both
--   unique keys; CAT6-CAT7: schedule_label column exists + is NOT NULL,
--   E27/E29) + 1 updated_at refresh (UPD1) + 4 two-tenant read
--   isolation (R1-R4) + 1 per-tenant label isolation (LBL-R: authenticated A
--   cannot read B's schedule_label, E27/E29) + 6 cross-tenant write (W1-W6)
--   + 3 D3 #18 adversarial (D0-D2, RLS-exempt writer via service_role) + 12
--   deferred set-fence
--   (SF-M1/M2/M3a/M3b rate monotonicity, SF-Z1/Z2/Z3/Z4 zero-floor,
--   SF-E1/E2 empty-schedule, SF-L1/L2 the row-fence's own parent-row lock
--   presence + ordering-before-the-set-read, Sec R-1) + 11 CHECK constraint
--   (CHK1-CHK8: NaN x3,
--   Infinity x3, rate=22 rejected, rate=0.22 control; CHK9-CHK11:
--   schedule_label's own CHECK by constraint name — empty string rejected,
--   a 501-char string rejected, a 500-char string accepted as control,
--   E27/E29) + 8 aal2 backstop on
--   schedule (AAL-S, mirrors 090 M1-M8) + 8 aal2 backstop on row (AAL-R,
--   incl. the investigated INSERT shadow) + 1 cross-tenant-at-aal2 (AAL-X,
--   the aal conjunct never replaces the tenant predicate) + 1 corrupt-the-
--   control leak proof (X1) + 23 replace-all coverage (BLOCK RA — RA1/RA1b/
--   RA1c/RA2 the lock-is-the-fence plus its paired control, RA3-RA6 p_rows
--   shape validation, RA7+RA7a-RA7e the call itself plus its atomic-replace
--   effects incl. updated_at AND schedule_label read-back (E27/E29), RA8+RA8b
--   the call itself plus its
--   empty-clears effect, RA9 grant structural, RA10 the FOR UPDATE catalog
--   pin, RA-TY1 the tax_year>=1913 CHECK by name, RA11a-RA11d the deferred
--   fence surviving a function boundary plus the prior-row-set-intact proof)
--   = 100.
-- =====================================================================

begin;

-- shared verbs (Option C via \ir); nested case -> ../_fixtures/ per DESIGN.md.
\ir ../_fixtures/rls_verbs.psql

select plan(100);

-- Resolve the fixed tenant UUIDs to psql literals while privileged (role=postgres).
select _rls.tenant_a() as ta, _rls.tenant_b() as tb \gset
\set td '00000000-0000-0000-0000-000000000d01'

-- ---------------------------------------------------------------------
-- Fixture (PRIVILEGED postgres session — RLS-bypassed seed path).
--  - Three tenants in auth.users: A/B (plain 'none' mfa_policy — the
--    two-tenant cross-read/write/delete baseline), D (totp — the aal2
--    backstop subject; builds its OWN rows via authenticated INSERT in the
--    AAL blocks so the INSERT leg of the backstop is genuinely exercised).
-- ---------------------------------------------------------------------
insert into auth.users (id) values (:'ta'), (:'tb'), (:'td');

insert into pfin.user_settings (users_id, mfa_policy) values
  (:'ta', 'none'), (:'tb', 'none'), (:'td', 'totp');

-- =====================================================================
-- BLOCK S (postgres — pg_policy catalog) — STRUCTURAL tenant + aal2
--   presence proof, SPLIT by clause half per 090's S6a/S6b masking lesson:
--   an OR-combined count goes green if a clause survives in EITHER half,
--   masking a WITH-CHECK-only regression on the *_update policy.
-- =====================================================================
select is(
  (select count(*)::bigint from pg_policy
    where polrelid = 'pfin.tax_bracket_schedule'::regclass
      and coalesce(pg_get_expr(polqual, polrelid), '') ilike '%users_id = auth.uid()%'),
  3::bigint,
  '(S1) STRUCTURAL schedule — USING half carries the tenant predicate: select/update/delete (pg_policy)'
);
select is(
  (select count(*)::bigint from pg_policy
    where polrelid = 'pfin.tax_bracket_schedule'::regclass
      and coalesce(pg_get_expr(polwithcheck, polrelid), '') ilike '%users_id = auth.uid()%'),
  2::bigint,
  '(S2) STRUCTURAL schedule — WITH CHECK half carries the tenant predicate: insert/update (pg_policy)'
);
select is(
  (select count(*)::bigint from pg_policy
    where polrelid = 'pfin.tax_bracket_schedule'::regclass
      and coalesce(pg_get_expr(polqual, polrelid), '') ilike '%aal2%'),
  3::bigint,
  '(S3) STRUCTURAL schedule — USING half carries the ADR-029/025 aal2 backstop: select/update/delete'
);
select is(
  (select count(*)::bigint from pg_policy
    where polrelid = 'pfin.tax_bracket_schedule'::regclass
      and coalesce(pg_get_expr(polwithcheck, polrelid), '') ilike '%aal2%'),
  2::bigint,
  '(S4) STRUCTURAL schedule — WITH CHECK half carries the aal2 backstop: insert/update — RED if update lost it in WITH CHECK while keeping it in USING'
);
select is(
  (select count(*)::bigint from pg_policy
    where polrelid = 'pfin.tax_bracket_row'::regclass
      and coalesce(pg_get_expr(polqual, polrelid), '') ilike '%users_id = auth.uid()%'),
  3::bigint,
  '(S5) STRUCTURAL row — USING half carries a DIRECT tenant predicate (not a join to schedule, per grain (C)): select/update/delete'
);
select is(
  (select count(*)::bigint from pg_policy
    where polrelid = 'pfin.tax_bracket_row'::regclass
      and coalesce(pg_get_expr(polwithcheck, polrelid), '') ilike '%users_id = auth.uid()%'),
  2::bigint,
  '(S6) STRUCTURAL row — WITH CHECK half carries the tenant predicate: insert/update'
);
select is(
  (select count(*)::bigint from pg_policy
    where polrelid = 'pfin.tax_bracket_row'::regclass
      and coalesce(pg_get_expr(polqual, polrelid), '') ilike '%aal2%'),
  3::bigint,
  '(S7) STRUCTURAL row — USING half carries the aal2 backstop: select/update/delete'
);
select is(
  (select count(*)::bigint from pg_policy
    where polrelid = 'pfin.tax_bracket_row'::regclass
      and coalesce(pg_get_expr(polwithcheck, polrelid), '') ilike '%aal2%'),
  2::bigint,
  '(S8) STRUCTURAL row — WITH CHECK half carries the aal2 backstop: insert/update — RED if update lost it in WITH CHECK while keeping it in USING'
);

-- =====================================================================
-- BLOCK GR (postgres — grants) — anon/service_role zero-grant, authenticated
--   full CRUD, on BOTH tables, structurally, PLUS one behavioral proof.
-- =====================================================================
select ok(
  not has_table_privilege('anon', 'pfin.tax_bracket_schedule', 'SELECT')
  and not has_table_privilege('anon', 'pfin.tax_bracket_schedule', 'INSERT')
  and not has_table_privilege('anon', 'pfin.tax_bracket_schedule', 'UPDATE')
  and not has_table_privilege('anon', 'pfin.tax_bracket_schedule', 'DELETE')
  and not has_table_privilege('anon', 'pfin.tax_bracket_row', 'SELECT')
  and not has_table_privilege('anon', 'pfin.tax_bracket_row', 'INSERT')
  and not has_table_privilege('anon', 'pfin.tax_bracket_row', 'UPDATE')
  and not has_table_privilege('anon', 'pfin.tax_bracket_row', 'DELETE'),
  '(GR1) anon holds ZERO table-level privileges on BOTH tables, all four verbs (pg_catalog has_table_privilege)'
);
select ok(
  not has_table_privilege('service_role', 'pfin.tax_bracket_schedule', 'SELECT')
  and not has_table_privilege('service_role', 'pfin.tax_bracket_schedule', 'INSERT')
  and not has_table_privilege('service_role', 'pfin.tax_bracket_schedule', 'UPDATE')
  and not has_table_privilege('service_role', 'pfin.tax_bracket_schedule', 'DELETE')
  and not has_table_privilege('service_role', 'pfin.tax_bracket_row', 'SELECT')
  and not has_table_privilege('service_role', 'pfin.tax_bracket_row', 'INSERT')
  and not has_table_privilege('service_role', 'pfin.tax_bracket_row', 'UPDATE')
  and not has_table_privilege('service_role', 'pfin.tax_bracket_row', 'DELETE'),
  '(GR2) service_role holds ZERO table-level privileges on BOTH tables, all four verbs — 008 establishes no default privileges, this records rather than effects that (measured BEFORE BLOCK D''s own temporary grant, which this file undoes via the final rollback, never an explicit revoke)'
);
select ok(
  has_table_privilege('authenticated', 'pfin.tax_bracket_schedule', 'SELECT')
  and has_table_privilege('authenticated', 'pfin.tax_bracket_schedule', 'INSERT')
  and has_table_privilege('authenticated', 'pfin.tax_bracket_schedule', 'UPDATE')
  and has_table_privilege('authenticated', 'pfin.tax_bracket_schedule', 'DELETE'),
  '(GR3) authenticated holds all FOUR verbs on tax_bracket_schedule (replace-all requires DELETE too, never trimmed per SECURITY §4.6)'
);
select ok(
  has_table_privilege('authenticated', 'pfin.tax_bracket_row', 'SELECT')
  and has_table_privilege('authenticated', 'pfin.tax_bracket_row', 'INSERT')
  and has_table_privilege('authenticated', 'pfin.tax_bracket_row', 'UPDATE')
  and has_table_privilege('authenticated', 'pfin.tax_bracket_row', 'DELETE'),
  '(GR4) authenticated holds all FOUR verbs on tax_bracket_row'
);
select set_config('role', 'anon', true);
select throws_ok(
  'select count(*) from pfin.tax_bracket_schedule',
  '42501', null,
  '(GR5) BEHAVIORAL: anon holds no USAGE on schema pfin -> SELECT is denied at the ACL layer (42501), before RLS is ever consulted'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK FN (postgres — pg_proc) — both trigger functions' posture, combined
--   (a count-of-2 masks nothing: EITHER function losing any of the three
--   predicates drops the count below 2).
-- =====================================================================
select is(
  (select count(*)::bigint
     from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'pfin'
      and p.proname in ('fn_tax_bracket_row_matched_schedule', 'fn_tax_bracket_row_schedule_invariants', 'fn_tax_bracket_schedule_replace_all')
      and p.prosecdef = false
      and not has_function_privilege('public', p.oid, 'EXECUTE')
      and exists (select 1 from unnest(coalesce(p.proconfig, '{}'::text[])) cfg where cfg = 'search_path=""')),
  3::bigint,
  '(FN1) ALL THREE functions this migration authors (both trigger fences AND the replace-all write body): prosecdef=false (SECURITY INVOKER — deliberate even for the directly-callable replace-all, per its own header: the caller''s RLS composing with its FOR UPDATE lock IS the tenant fence), PUBLIC EXECUTE revoked, proconfig carries search_path="" — count=3 means none of the three lost any of the three predicates. (Whether authenticated ALSO holds EXECUTE differs per function — RA9 below asserts that half for the replace-all function specifically.)'
);

-- =====================================================================
-- BLOCK CAT (postgres — trigger/enum/unique catalog pins).
-- =====================================================================
select is(
  (select count(*)::bigint from pg_trigger
    where tgrelid = 'pfin.tax_bracket_row'::regclass
      and tgname = 'tax_bracket_row_matched_schedule'
      and not tgdeferrable
      and not tginitdeferred),
  1::bigint,
  '(CAT1) tax_bracket_row_matched_schedule EXISTS and is NOT deferrable (BEFORE INSERT OR UPDATE — the matched-tenant fence must gate synchronously, not at commit)'
);
select is(
  (select count(*)::bigint from pg_trigger
    where tgrelid = 'pfin.tax_bracket_row'::regclass
      and tgname = 'tax_bracket_row_schedule_invariants'
      and tgdeferrable
      and tginitdeferred),
  1::bigint,
  '(CAT2) tax_bracket_row_schedule_invariants EXISTS, IS deferrable AND initially deferred — the set-fence CANNOT be the BEFORE-ROW shape (it would pass a collectively-invalid multi-row INSERT)'
);
select is(
  (select array_agg(e.enumlabel::text order by e.enumsortorder) from pg_enum e
     join pg_type t on t.oid = e.enumtypid
     join pg_namespace n on n.oid = t.typnamespace
    where n.nspname = 'pfin' and t.typname = 'tax_schedule_type_enum'),
  array['federal_ordinary', 'federal_lt_cg', 'california_ordinary']::text[],
  '(CAT3) pfin.tax_schedule_type_enum carries EXACTLY these three labels, in this order — RED if a value were added, removed, or reordered'
);
select ok(
  exists (
    select 1 from pg_constraint c
     where c.conrelid = 'pfin.tax_bracket_schedule'::regclass
       and c.contype = 'u'
       and c.conkey = array[
         (select attnum from pg_attribute where attrelid = 'pfin.tax_bracket_schedule'::regclass and attname = 'users_id'),
         (select attnum from pg_attribute where attrelid = 'pfin.tax_bracket_schedule'::regclass and attname = 'tax_year'),
         (select attnum from pg_attribute where attrelid = 'pfin.tax_bracket_schedule'::regclass and attname = 'schedule_type')
       ]
  ),
  '(CAT4) unique (users_id, tax_year, schedule_type) EXISTS on tax_bracket_schedule (the UPSERT ON CONFLICT target)'
);
select ok(
  exists (
    select 1 from pg_constraint c
     where c.conrelid = 'pfin.tax_bracket_row'::regclass
       and c.contype = 'u'
       and c.conkey = array[
         (select attnum from pg_attribute where attrelid = 'pfin.tax_bracket_row'::regclass and attname = 'schedule_id'),
         (select attnum from pg_attribute where attrelid = 'pfin.tax_bracket_row'::regclass and attname = 'bracket_floor')
       ]
  ),
  '(CAT5) unique (schedule_id, bracket_floor) EXISTS on tax_bracket_row (makes one schedule''s floors pairwise distinct — the premise E6''s ruling rests on)'
);
select has_column('pfin', 'tax_bracket_schedule', 'schedule_label',
  '(CAT6) pfin.tax_bracket_schedule.schedule_label column EXISTS — added at Sec''s SELF-260 review, rulings E27/E29'
);
select col_not_null('pfin', 'tax_bracket_schedule', 'schedule_label',
  '(CAT7) pfin.tax_bracket_schedule.schedule_label is NOT NULL'
);

-- =====================================================================
-- FIXTURE — real committed schedules + one valid bracket row each, via
--   authenticated INSERT (exercises the INSERT policy + fence naturally,
--   074/090's convention over a privileged pre-seed).
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
insert into pfin.tax_bracket_schedule (tax_year, schedule_type, schedule_label, standard_deduction)
  values (2026, 'federal_ordinary', 'A Federal 2026', 14600.00) returning id as sched_a \gset
insert into pfin.tax_bracket_row (schedule_id, bracket_floor, bracket_rate)
  values (:sched_a, 0, 0.10);
select set_config('role', 'postgres', true);

select _rls.set_tenant(:'tb'::uuid);
insert into pfin.tax_bracket_schedule (tax_year, schedule_type, schedule_label, standard_deduction)
  values (2026, 'federal_ordinary', 'B Federal 2026', 5000.00) returning id as sched_b \gset
insert into pfin.tax_bracket_row (schedule_id, bracket_floor, bracket_rate)
  values (:sched_b, 0, 0.10);
select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK UPD (updated_at refresh) — `now()` is TRANSACTION-CONSTANT across
--   this whole file (fn_refresh_updated_at sets NEW.updated_at := now()), so
--   a wall-clock before/after comparison would be a FALSE NEGATIVE — the
--   trigger correctly resets updated_at to the SAME transaction-start value
--   it already held from the row's own INSERT default. The sentinel
--   technique sidesteps that: force updated_at to an old value directly
--   (privileged, bypassing the trigger), then perform the REAL authenticated
--   UPDATE, and assert it moved AWAY from the sentinel.
-- =====================================================================
update pfin.tax_bracket_schedule set updated_at = '2000-01-01'::timestamptz where id = :sched_a;
select _rls.set_tenant(:'ta'::uuid);
update pfin.tax_bracket_schedule set standard_deduction = 15000.00 where id = :sched_a;
select set_config('role', 'postgres', true);
select ok(
  (select updated_at > '2000-01-01'::timestamptz from pfin.tax_bracket_schedule where id = :sched_a),
  '(UPD1) tax_bracket_schedule_set_updated_at fires on UPDATE: updated_at was forced to a 2000-01-01 sentinel (privileged, bypassing the trigger), then A''s authenticated UPDATE reset it away from that sentinel'
);
-- restore the fixture's real standard_deduction for later legs (R1/X1 do not
-- depend on this value, but keep the fixture state predictable).
update pfin.tax_bracket_schedule set standard_deduction = 14600.00 where id = :sched_a;

-- =====================================================================
-- BLOCK R (postgres — _rls verbs) — two-tenant read isolation, both tables.
-- =====================================================================
select _rls.expect_owner_can_read('pfin.tax_bracket_schedule'::regclass, :'ta'::uuid, 1::bigint);
select _rls.expect_cross_tenant_read_empty('pfin.tax_bracket_schedule'::regclass, :'ta'::uuid, :'tb'::uuid);
select _rls.expect_owner_can_read('pfin.tax_bracket_row'::regclass, :'ta'::uuid, 1::bigint);
select _rls.expect_cross_tenant_read_empty('pfin.tax_bracket_row'::regclass, :'ta'::uuid, :'tb'::uuid);

-- (LBL-R) schedule_label is per-tenant LIKE EVERY OTHER COLUMN on this table
--   (E27/E29): A's query filtered on B's OWN KNOWN schedule_label value
--   ('B Federal 2026', set at this file's fixture INSERT) returns 0 rows —
--   RLS hides the whole row, column value included, not merely the id.
select is(
  _rls.count_as(:'ta'::uuid, null, format('select count(*) from pfin.tax_bracket_schedule where schedule_label = %L', 'B Federal 2026')),
  0::bigint,
  '(LBL-R) schedule_label is per-tenant like every other column: authenticated A''s query filtered on B''s known schedule_label value returns 0 rows'
);

-- =====================================================================
-- BLOCK D (adversarial matched-tenant leg, R4 rider 7 / item 2) — an
--   RLS-EXEMPT writer (service_role, rolbypassrls=true): the row's users_id
--   = A but schedule_id = B's REAL schedule. RLS cannot filter this (it is
--   bypassed at the ROLE-ATTRIBUTE level, not by any grant), so the fence's
--   own explicit users_id equality is the ONLY defense — the ADR-042
--   Decision 5a case #18 is named for.
-- =====================================================================
select ok(
  (select rolbypassrls from pg_roles where rolname = 'service_role'),
  '(D0) service_role carries rolbypassrls = true — WHY service_role is the role used below: RLS does not gate its read of tax_bracket_schedule at all, so the leg 2 raise that follows is proof of the TRIGGER''s own predicate, not of RLS'
);

grant usage on schema pfin to service_role;
grant select on pfin.tax_bracket_schedule to service_role;
grant insert on pfin.tax_bracket_row to service_role;

savepoint sp_d1;
select set_config('role', 'service_role', true);
select throws_like(
  format($$ insert into pfin.tax_bracket_row (users_id, schedule_id, bracket_floor, bracket_rate) values (%L, %s, 100000, 0.10) $$, :'ta', :sched_b),
  '%is owned by another tenant, not by users_id%leg 2 cross-tenant%',
  '(D1) ⭐ ADVERSARIAL: under service_role (RLS bypassed), users_id=A + schedule_id=B''s REAL schedule -> the trigger resolves B''s TRUE ownership vs the mismatched new.users_id=A and RAISES leg 2 cross-tenant — RLS never gets a chance to catch this, so this is proof the fence itself is the defense'
);
select set_config('role', 'postgres', true);
rollback to savepoint sp_d1;

savepoint sp_d2;
select set_config('role', 'service_role', true);
select lives_ok(
  format($$ insert into pfin.tax_bracket_row (users_id, schedule_id, bracket_floor, bracket_rate) values (%L, %s, 100000, 0.10) $$, :'tb', :sched_b),
  '(D2) non-vacuous control: SAME service_role writer, users_id=B matched to B''s OWN real schedule -- ACCEPTED -- proves (D1) is owner-mismatch-driven, not a blanket service_role block'
);
select set_config('role', 'postgres', true);
rollback to savepoint sp_d2;

-- =====================================================================
-- BLOCK W (cross-tenant write, both tables, four verbs). B is the intruder
--   throughout — the SECURITY §4.5 "Tenant A inserts, Tenant B attempts"
--   framing.
-- =====================================================================
-- (W1) schedule INSERT forge: B forges users_id=A. No trigger sits in front
--      of tax_bracket_schedule, so this is a DIRECT WITH CHECK 42501.
select _rls.set_tenant(:'tb'::uuid);
savepoint sp_w1;
select throws_ok(
  format($$ insert into pfin.tax_bracket_schedule (users_id, tax_year, schedule_type, schedule_label, standard_deduction) values (%L, 2027, 'federal_ordinary', 'W1 forge label', 1000.00) $$, :'ta'),
  '42501', null,
  '(W1) schedule cross-tenant INSERT forge: B claims users_id=A -> RLS WITH CHECK rejects (42501) directly — no trigger shadows this table''s WITH CHECK (schedule_label supplied so the NOT NULL constraint, which enforces before RLS WITH CHECK, is not what fires here)'
);
rollback to savepoint sp_w1;
select set_config('role', 'postgres', true);

-- (W2) schedule UPDATE cross-tenant: B's qualified UPDATE matches 0 of A's rows.
select _rls.set_tenant(:'tb'::uuid);
update pfin.tax_bracket_schedule set standard_deduction = 999.00 where users_id = :'ta';
select set_config('role', 'postgres', true);
select is(
  (select standard_deduction from pfin.tax_bracket_schedule where id = :sched_a),
  14600.00::numeric(20,4),
  '(W2) schedule cross-tenant UPDATE: B''s UPDATE where users_id=A matches 0 rows under RLS -- A''s row UNCHANGED'
);

-- (W3) schedule DELETE cross-tenant: B's qualified DELETE matches 0 of A's rows.
select _rls.set_tenant(:'tb'::uuid);
delete from pfin.tax_bracket_schedule where users_id = :'ta';
select set_config('role', 'postgres', true);
select is(
  (select count(*) from pfin.tax_bracket_schedule where id = :sched_a)::bigint,
  1::bigint,
  '(W3) schedule cross-tenant DELETE: B''s DELETE where users_id=A matches 0 rows under RLS -- A''s row SURVIVES'
);

-- (W4) ⭐ row INSERT forge (ownership-forge, the 074/(L2a) shape): A forges
--      users_id=B on A's OWN real schedule_id (sched_a). The trigger
--      resolves sched_a's TRUE owner (A) vs the forged new.users_id (B) ->
--      MISMATCH -> leg 2 raises, from PLAIN authenticated, BEFORE RLS's own
--      WITH CHECK is ever reached. Distinct from BLOCK D's RLS-exempt case:
--      this is the route a plain authenticated attacker actually has.
select _rls.set_tenant(:'ta'::uuid);
savepoint sp_w4;
select throws_like(
  format($$ insert into pfin.tax_bracket_row (users_id, schedule_id, bracket_floor, bracket_rate) values (%L, %s, 200000, 0.10) $$, :'tb', :sched_a),
  '%is owned by another tenant, not by users_id%leg 2 cross-tenant%',
  '(W4) ⭐ row cross-tenant INSERT forge: A forges users_id=B on A''s OWN real schedule_id -> the trigger raises leg 2 cross-tenant, reachable from PLAIN authenticated (the 074/(L2a) ownership-forge shape, structurally identical on #18)'
);
rollback to savepoint sp_w4;
select set_config('role', 'postgres', true);

-- (W5) row UPDATE cross-tenant: B's qualified UPDATE matches 0 of A's rows.
select _rls.set_tenant(:'tb'::uuid);
update pfin.tax_bracket_row set bracket_rate = 0.99 where users_id = :'ta';
select set_config('role', 'postgres', true);
select is(
  (select bracket_rate from pfin.tax_bracket_row where schedule_id = :sched_a and bracket_floor = 0),
  0.10::numeric(12,8),
  '(W5) row cross-tenant UPDATE: B''s UPDATE where users_id=A matches 0 rows under RLS -- A''s row UNCHANGED'
);

-- (W6) row DELETE cross-tenant: B's qualified DELETE matches 0 of A's rows.
select _rls.set_tenant(:'tb'::uuid);
delete from pfin.tax_bracket_row where users_id = :'ta';
select set_config('role', 'postgres', true);
select is(
  (select count(*) from pfin.tax_bracket_row where schedule_id = :sched_a)::bigint,
  1::bigint,
  '(W6) row cross-tenant DELETE: B''s DELETE where users_id=A matches 0 rows under RLS -- A''s row SURVIVES'
);

-- =====================================================================
-- BLOCK SF (deferred set-fence legs, items 3/4/5) — a FRESH schedule
--   (sched_sf, A-owned) dedicated to this block so it never disturbs
--   sched_a's single fixture row used elsewhere. `set constraints all
--   deferred` / `... all immediate` per the 029/038 idiom (see header box).
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
insert into pfin.tax_bracket_schedule (tax_year, schedule_type, schedule_label, standard_deduction)
  values (2026, 'california_ordinary', 'A California SF 2026', 5202.00) returning id as sched_sf \gset

-- --- SF-M: RATE MONOTONICITY (E6: over rate, never floor order) ---
set constraints all deferred;
insert into pfin.tax_bracket_row (schedule_id, bracket_floor, bracket_rate) values (:sched_sf, 0, 0.20);
select lives_ok(
  format($$ insert into pfin.tax_bracket_row (schedule_id, bracket_floor, bracket_rate) values (%s, 50000, 0.10) $$, :sched_sf),
  '(SF-M1) multi-row batch with a DECREASING rate (0.20 then 0.10 as floor ascends) SUCCEEDS as a statement — the deferred trigger has not fired yet'
);
select throws_like(
  'set constraints all immediate',
  '%rate monotonicity%',
  '(SF-M2) SET CONSTRAINTS ALL IMMEDIATE forces the deferred set-fence to fire NOW (commit-equivalent) and it RAISES leg B rate monotonicity on the non-monotone batch staged at (SF-M1)'
);
delete from pfin.tax_bracket_row where schedule_id = :sched_sf;
set constraints all deferred;

select lives_ok(
  format($$ insert into pfin.tax_bracket_row (schedule_id, bracket_floor, bracket_rate) values (%s, 0, 0.10), (%s, 50000, 0.20) $$, :sched_sf, :sched_sf),
  '(SF-M3a) CONTROL: the SAME batch shape with a NON-DECREASING rate (0.10 then 0.20) succeeds as a statement'
);
select lives_ok(
  'set constraints all immediate',
  '(SF-M3b) CONTROL: SET CONSTRAINTS ALL IMMEDIATE now COMMITS cleanly — proves (SF-M2) is non-vacuous (the fence itself was the blocker, not something else about a multi-row batch)'
);
delete from pfin.tax_bracket_row where schedule_id = :sched_sf;
set constraints all deferred;

-- --- SF-Z: ZERO FLOOR (a DIFFERENT property from monotonicity) ---
select lives_ok(
  format($$ insert into pfin.tax_bracket_row (schedule_id, bracket_floor, bracket_rate) values (%s, 5000, 0.10), (%s, 10000, 0.20) $$, :sched_sf, :sched_sf),
  '(SF-Z1) a MONOTONE batch whose lowest floor is NON-ZERO (5000, ascending) succeeds as a statement — monotonicity alone cannot catch this'
);
select throws_like(
  'set constraints all immediate',
  '%leg A zero-floor%',
  '(SF-Z2) SET CONSTRAINTS ALL IMMEDIATE RAISES leg A zero-floor — the batch is perfectly monotone (0.10 then 0.20) yet still rejected, proving zero-floor is a genuinely SEPARATE control from rate-monotonicity'
);
delete from pfin.tax_bracket_row where schedule_id = :sched_sf;
set constraints all deferred;

select lives_ok(
  format($$ insert into pfin.tax_bracket_row (schedule_id, bracket_floor, bracket_rate) values (%s, 0, 0.10), (%s, 10000, 0.20) $$, :sched_sf, :sched_sf),
  '(SF-Z3) CONTROL: the SAME monotone shape with a 0 floor succeeds as a statement'
);
select lives_ok(
  'set constraints all immediate',
  '(SF-Z4) CONTROL: SET CONSTRAINTS ALL IMMEDIATE now COMMITS cleanly — proves (SF-Z2) is non-vacuous'
);

-- --- SF-E: EMPTY SCHEDULE (absence-is-unset; reuses SF-Z3/Z4's 2 committed rows) ---
select lives_ok(
  format($$ delete from pfin.tax_bracket_row where schedule_id = %s $$, :sched_sf),
  '(SF-E1) deleting ALL of a schedule''s rows (the replace-all path''s own delete-then-reinsert shape) succeeds as a statement'
);
select lives_ok(
  'set constraints all immediate',
  '(SF-E2) SET CONSTRAINTS ALL IMMEDIATE COMMITS cleanly on the now-EMPTY schedule — absence of brackets is the unset representation, not a malformed set (deliberate per the migration''s own POSTURE)'
);
set constraints all deferred;
select set_config('role', 'postgres', true);

-- --- SF-L: THE SET FENCE'S OWN PARENT-ROW LOCK (Sec R-1, GREEN re-review
--   2026-09-04) — fn_tax_bracket_row_schedule_invariants gained a `for
--   update` lock on the parent schedule row as its FIRST statement, but
--   until now this battery pinned `for update` only on the replace-all
--   function (RA10); a reader comparing the two would reasonably conclude
--   the set fence carries no lock at all. Both legs are CATALOG PINS, not
--   behavioral (pgTAP cannot hold two concurrent sessions) — same posture
--   as (RA10): presence and effect are different claims, and only presence
--   is checkable here.
select ok(
  (select lower(pg_get_functiondef(p.oid)) ~ 'for update'
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'pfin' and p.proname = 'fn_tax_bracket_row_schedule_invariants'),
  '(SF-L1) CATALOG PIN: fn_tax_bracket_row_schedule_invariants''s body contains a FOR UPDATE lock (pg_get_functiondef, a real catalog read) — like RA10, this pin evidences PRESENCE, never EFFECT'
);
select ok(
  (
    with body as (
      select lower(pg_get_functiondef(p.oid)) as src
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'pfin' and p.proname = 'fn_tax_bracket_row_schedule_invariants'
    )
    select position('for update' in src) > 0
       and position('count(*)' in src) > 0
       and position('for update' in src) < position('count(*)' in src)
      from body
  ),
  '(SF-L2) LOAD-BEARING, NOT MERE PRESENCE: the FOR UPDATE lock''s position in the function body PRECEDES the position of the set read it must precede (`count(*)`, the schedule''s row-count read) — the function''s own header states this lock "must be the FIRST statement after the schedule is resolved", and an edit that moved the lock AFTER the read would kill this control while every existing leg in this file (SF-M/SF-Z/SF-E, all behavioral, none of which can observe statement ORDER) stayed green'
);

-- =====================================================================
-- BLOCK CHK (CHECK constraints) — against sched_a's real fixture row/schedule
--   (owned by A), each probe individually savepoint/rollback-isolated.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);

savepoint sp_chk1;
select throws_ok(
  format($$ update pfin.tax_bracket_schedule set standard_deduction = 'NaN'::numeric where id = %s $$, :sched_a),
  '23514', null,
  '(CHK1) standard_deduction NaN rejected (23514) — NaN is storable in numeric(20,4) and sorts above every non-NaN numeric, so a one-sided >= 0 would ADMIT it; the explicit <> ''NaN''::numeric literal refuses it'
);
rollback to savepoint sp_chk1;

savepoint sp_chk2;
select throws_ok(
  format($$ update pfin.tax_bracket_schedule set standard_deduction = 'Infinity'::numeric where id = %s $$, :sched_a),
  '22003', null,
  '(CHK2) standard_deduction +Infinity rejected by the numeric(20,4) TYPMOD (22003) — a DIFFERENT mechanism and SQLSTATE than (CHK1): the typmod refuses the value before the CHECK is ever reached'
);
rollback to savepoint sp_chk2;

savepoint sp_chk3;
select throws_ok(
  format($$ insert into pfin.tax_bracket_row (schedule_id, bracket_floor, bracket_rate) values (%s, 'NaN'::numeric, 0.10) $$, :sched_a),
  '23514', null,
  '(CHK3) bracket_floor NaN rejected (23514) — same NaN-admits-a-one-sided-bound mechanism as (CHK1), asserted independently on this column''s own CHECK'
);
rollback to savepoint sp_chk3;

savepoint sp_chk4;
select throws_ok(
  format($$ insert into pfin.tax_bracket_row (schedule_id, bracket_floor, bracket_rate) values (%s, 'Infinity'::numeric, 0.10) $$, :sched_a),
  '22003', null,
  '(CHK4) bracket_floor +Infinity rejected by the numeric(20,4) TYPMOD (22003)'
);
rollback to savepoint sp_chk4;

savepoint sp_chk5;
select throws_ok(
  format($$ insert into pfin.tax_bracket_row (schedule_id, bracket_floor, bracket_rate) values (%s, 999000, 'NaN'::numeric) $$, :sched_a),
  '23514', null,
  '(CHK5) bracket_rate NaN rejected (23514) — same mechanism, asserted independently on the sibling column''s own CHECK'
);
rollback to savepoint sp_chk5;

savepoint sp_chk6;
select throws_ok(
  format($$ insert into pfin.tax_bracket_row (schedule_id, bracket_floor, bracket_rate) values (%s, 999000, 22) $$, :sched_a),
  '23514', null,
  '(CHK6) bracket_rate = 22 rejected (23514, upper-bound violation) — the UNIT is a FRACTION (0.22 = 22%%), so the common mis-entry (typing the published percent) fails LOUDLY at the <= 1 bound'
);
rollback to savepoint sp_chk6;

savepoint sp_chk7;
select lives_ok(
  format($$ insert into pfin.tax_bracket_row (schedule_id, bracket_floor, bracket_rate) values (%s, 999000, 0.22) $$, :sched_a),
  '(CHK7) CONTROL: bracket_rate = 0.22 (the correct FRACTION unit) is ACCEPTED — proves (CHK6) is unit-driven, not a blanket rejection of any value near 22'
);
rollback to savepoint sp_chk7;

savepoint sp_chk8;
select throws_ok(
  format($$ insert into pfin.tax_bracket_row (schedule_id, bracket_floor, bracket_rate) values (%s, 999000, 'Infinity'::numeric) $$, :sched_a),
  '22003', null,
  '(CHK8) bracket_rate +Infinity rejected by the numeric(12,8) TYPMOD (22003) — a DIFFERENT mechanism and SQLSTATE than (CHK5)/(CHK6)'
);
rollback to savepoint sp_chk8;

-- --- schedule_label's OWN CHECK (E27/E29), by CONSTRAINT NAME ---
savepoint sp_chk9;
select throws_like(
  format($$ update pfin.tax_bracket_schedule set schedule_label = '' where id = %s $$, :sched_a),
  '%tax_bracket_schedule_schedule_label_check%',
  '(CHK9) schedule_label = '''' (empty string, below the length>=1 bound) rejected BY NAME — tax_bracket_schedule_schedule_label_check'
);
rollback to savepoint sp_chk9;

savepoint sp_chk10;
select throws_like(
  format($$ update pfin.tax_bracket_schedule set schedule_label = %L where id = %s $$, repeat('x', 501), :sched_a),
  '%tax_bracket_schedule_schedule_label_check%',
  '(CHK10) schedule_label at 501 characters (one over the length<=500 bound) rejected BY NAME — tax_bracket_schedule_schedule_label_check'
);
rollback to savepoint sp_chk10;

savepoint sp_chk11;
select lives_ok(
  format($$ update pfin.tax_bracket_schedule set schedule_label = %L where id = %s $$, repeat('x', 500), :sched_a),
  '(CHK11) CONTROL: schedule_label at EXACTLY 500 characters (the upper bound itself) is ACCEPTED — proves (CHK10) is bound-driven, not a blanket rejection of long strings'
);
rollback to savepoint sp_chk11;
select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK X (authenticated A, tax_bracket_schedule_select corrupted) —
--   corrupt-the-control: prove RLS, not application logic, confines A to
--   its own rows. Plain equality-filtered read (no limit-1 selector), so
--   immune to the #474 displacement class.
-- =====================================================================
savepoint sp_leak;
alter policy tax_bracket_schedule_select on pfin.tax_bracket_schedule using (true);
select _rls.set_tenant(:'ta'::uuid);
select is(
  (select standard_deduction from pfin.tax_bracket_schedule where id = :sched_b),
  5000.00::numeric(20,4),
  '(X1) CORRUPT-THE-CONTROL: with tax_bracket_schedule_select broken OPEN, authenticated A''s query for B''s schedule returns B''s REAL value (5000.00) -- proving RLS, not application logic, is what confines A to its own rows'
);
select set_config('role', 'postgres', true);
rollback to savepoint sp_leak;

-- =====================================================================
-- BLOCK AAL-S (aal2 backstop, ADR-029/025 shape, all FOUR verbs, schedule
--   table) — mirrors 090's M1-M8 exactly. D (totp) builds its own row via
--   authenticated INSERT.
-- =====================================================================
select _rls.set_tenant_aal(:'td'::uuid, 'aal1');
savepoint sp_aal_s_ins1;
select throws_ok(
  $$ insert into pfin.tax_bracket_schedule (tax_year, schedule_type, schedule_label, standard_deduction) values (2026, 'federal_ordinary', 'D aal1 attempt', 12000.00) $$,
  '42501', null,
  '(AAL-S-INS1) INSERT: totp-declared D at aal1 -- the aal2 WITH CHECK conjunct rejects (42501), directly (no trigger sits in front of tax_bracket_schedule; schedule_label supplied so NOT NULL, which enforces before the RLS WITH CHECK, is not what fires here)'
);
rollback to savepoint sp_aal_s_ins1;
select set_config('role', 'postgres', true);

select _rls.set_tenant_aal(:'td'::uuid, 'aal2');
select lives_ok(
  $$ insert into pfin.tax_bracket_schedule (tax_year, schedule_type, schedule_label, standard_deduction) values (2026, 'federal_ordinary', 'D aal2 schedule', 12000.00) $$,
  '(AAL-S-INS2) INSERT: SAME totp D at aal2 -- succeeds -- proves (AAL-S-INS1) is non-vacuous and creates D''s schedule for the rest of this block'
);
select set_config('role', 'postgres', true);
select id as d_sched from pfin.tax_bracket_schedule where users_id = :'td' \gset

select is(_rls.count_as(:'td'::uuid, 'aal1', format('select count(*) from pfin.tax_bracket_schedule where users_id = %L', :'td')),
  0::bigint,
  '(AAL-S-SEL1) SELECT: totp D at aal1 sees 0 of its OWN rows -- the aal2 backstop blocks the read even though D genuinely has one (from AAL-S-INS2)');

select is(_rls.count_as(:'td'::uuid, 'aal2', format('select count(*) from pfin.tax_bracket_schedule where users_id = %L', :'td')),
  1::bigint,
  '(AAL-S-SEL2) SELECT: SAME totp D at aal2 sees its 1 own row -- proves (AAL-S-SEL1) is non-vacuous');

select _rls.set_tenant_aal(:'td'::uuid, 'aal1');
update pfin.tax_bracket_schedule set standard_deduction = 99999.00 where users_id = :'td';
select set_config('role', 'postgres', true);
select is(
  (select standard_deduction from pfin.tax_bracket_schedule where id = :d_sched),
  12000.00::numeric(20,4),
  '(AAL-S-UPD1) UPDATE: totp D at aal1 -- USING aal2 backstop hides D''s own row (0 rows affected); value UNCHANGED'
);

select _rls.set_tenant_aal(:'td'::uuid, 'aal2');
update pfin.tax_bracket_schedule set standard_deduction = 99999.00 where users_id = :'td';
select set_config('role', 'postgres', true);
select is(
  (select standard_deduction from pfin.tax_bracket_schedule where id = :d_sched),
  99999.00::numeric(20,4),
  '(AAL-S-UPD2) UPDATE: SAME totp D at aal2 -- APPLIES (value changed) -- proves (AAL-S-UPD1) is non-vacuous'
);

select _rls.set_tenant_aal(:'td'::uuid, 'aal1');
delete from pfin.tax_bracket_schedule where users_id = :'td';
select set_config('role', 'postgres', true);
select is(
  (select count(*) from pfin.tax_bracket_schedule where id = :d_sched)::bigint,
  1::bigint,
  '(AAL-S-DEL1) DELETE: totp D at aal1 -- USING aal2 backstop hides D''s own row (0 rows affected); row STILL EXISTS'
);

select _rls.set_tenant_aal(:'td'::uuid, 'aal2');
delete from pfin.tax_bracket_schedule where users_id = :'td';
select set_config('role', 'postgres', true);
select is(
  (select count(*) from pfin.tax_bracket_schedule where id = :d_sched)::bigint,
  0::bigint,
  '(AAL-S-DEL2) DELETE: SAME totp D at aal2 -- APPLIES (row GONE) -- proves (AAL-S-DEL1) is non-vacuous'
);

-- =====================================================================
-- BLOCK AAL-R (aal2 backstop, row table, all FOUR verbs). D needs its OWN
--   schedule to attach rows to (AAL-S deleted D's earlier one) — created at
--   aal2 (INSERT on tax_bracket_schedule requires it).
-- =====================================================================
select _rls.set_tenant_aal(:'td'::uuid, 'aal2');
insert into pfin.tax_bracket_schedule (tax_year, schedule_type, schedule_label, standard_deduction)
  values (2026, 'federal_lt_cg', 'D aal2 row schedule', 0.00) returning id as d_sched2 \gset
select set_config('role', 'postgres', true);

-- (AAL-R-INS1) ⭐ INVESTIGATED, not assumed (see header box): fn_tax_bracket_
--   row_matched_schedule is SECURITY INVOKER, and tax_bracket_schedule_select
--   is ITSELF aal2-claused -- so at aal1 the trigger's OWN read of D's OWN
--   schedule may return NOT FOUND (leg 1 unresolvable) BEFORE
--   tax_bracket_row_insert's WITH CHECK is ever reached -- the 074/(M5)
--   shadow, on a different table. This assertion matches the mechanism THIS
--   FILE'S pg_prove RUN actually measured.
select _rls.set_tenant_aal(:'td'::uuid, 'aal1');
savepoint sp_aal_r_ins1;
select throws_like(
  format($$ insert into pfin.tax_bracket_row (schedule_id, bracket_floor, bracket_rate) values (%s, 0, 0.10) $$, :d_sched2),
  '%does not resolve to a tax_bracket_schedule row readable by users_id%leg 1 unresolvable%',
  '(AAL-R-INS1) ⭐ INSERT: totp D at aal1 targeting D''s OWN schedule -- the trigger''s own SECURITY INVOKER read of tax_bracket_schedule is ITSELF aal2-gated (tax_bracket_schedule_select), so at aal1 it cannot see d_sched2 even though D owns it -- LEG 1 unresolvable fires, NOT a WITH CHECK 42501 -- the aal2-gated READ shadows the aal2-gated WRITE (074/(M5) shape, measured empirically on this table too)'
);
rollback to savepoint sp_aal_r_ins1;
select set_config('role', 'postgres', true);

select _rls.set_tenant_aal(:'td'::uuid, 'aal2');
select lives_ok(
  format($$ insert into pfin.tax_bracket_row (schedule_id, bracket_floor, bracket_rate) values (%s, 0, 0.10) $$, :d_sched2),
  '(AAL-R-INS2) INSERT: SAME totp D at aal2 -- succeeds -- proves (AAL-R-INS1) is non-vacuous and creates D''s row for the rest of this block'
);
select set_config('role', 'postgres', true);

select is(_rls.count_as(:'td'::uuid, 'aal1', format('select count(*) from pfin.tax_bracket_row where users_id = %L', :'td')),
  0::bigint,
  '(AAL-R-SEL1) SELECT: totp D at aal1 sees 0 of its OWN rows -- the aal2 backstop blocks the read even though D genuinely has one (from AAL-R-INS2)');

select is(_rls.count_as(:'td'::uuid, 'aal2', format('select count(*) from pfin.tax_bracket_row where users_id = %L', :'td')),
  1::bigint,
  '(AAL-R-SEL2) SELECT: SAME totp D at aal2 sees its 1 own row -- proves (AAL-R-SEL1) is non-vacuous');

-- (AAL-R-UPD1)/(UPD2): the row's OWN USING clause filters candidate rows
--   BEFORE the BEFORE-ROW trigger ever fires (the 074 mechanism, verified
--   there for planning_target's UPDATE/DELETE) -- so this is a plain
--   aal2-backstop test, not another shadow instance.
select _rls.set_tenant_aal(:'td'::uuid, 'aal1');
update pfin.tax_bracket_row set bracket_rate = 0.55 where users_id = :'td';
select set_config('role', 'postgres', true);
select is(
  (select bracket_rate from pfin.tax_bracket_row where schedule_id = :d_sched2),
  0.10::numeric(12,8),
  '(AAL-R-UPD1) UPDATE: totp D at aal1 -- USING aal2 backstop hides D''s own row (0 rows affected); value UNCHANGED'
);

select _rls.set_tenant_aal(:'td'::uuid, 'aal2');
update pfin.tax_bracket_row set bracket_rate = 0.55 where users_id = :'td';
select set_config('role', 'postgres', true);
select is(
  (select bracket_rate from pfin.tax_bracket_row where schedule_id = :d_sched2),
  0.55::numeric(12,8),
  '(AAL-R-UPD2) UPDATE: SAME totp D at aal2 -- APPLIES (value changed) -- proves (AAL-R-UPD1) is non-vacuous'
);

select _rls.set_tenant_aal(:'td'::uuid, 'aal1');
delete from pfin.tax_bracket_row where users_id = :'td';
select set_config('role', 'postgres', true);
select is(
  (select count(*) from pfin.tax_bracket_row where schedule_id = :d_sched2)::bigint,
  1::bigint,
  '(AAL-R-DEL1) DELETE: totp D at aal1 -- USING aal2 backstop hides D''s own row (0 rows affected); row STILL EXISTS'
);

select _rls.set_tenant_aal(:'td'::uuid, 'aal2');
delete from pfin.tax_bracket_row where users_id = :'td';
select set_config('role', 'postgres', true);
select is(
  (select count(*) from pfin.tax_bracket_row where schedule_id = :d_sched2)::bigint,
  0::bigint,
  '(AAL-R-DEL2) DELETE: SAME totp D at aal2 -- APPLIES (row GONE) -- proves (AAL-R-DEL1) is non-vacuous'
);

-- (AAL-X) cross-tenant-at-aal2: intruder B, even CLAIMING aal2, still sees 0
--   of A's row(s) -- the aal conjunct is ANDed with the tenant predicate, it
--   never REPLACES it (the 074/(M11) shape).
select is(_rls.count_as(:'tb'::uuid, 'aal2', format('select count(*) from pfin.tax_bracket_row where users_id = %L', :'ta')),
  0::bigint,
  '(AAL-X) cross-tenant-at-aal2: intruder B, EVEN claiming aal2, STILL sees 0 of A''s rows -- MFA strength never weakens another tenant''s fence');

-- =====================================================================
-- BLOCK RA — pfin.fn_tax_bracket_schedule_replace_all. ADDED IN THIS PASS,
--   NOT PART OF THE ORIGINAL DISPATCH: this function did not exist at
--   dispatch time and landed on origin/feature/self-259 (fcd8e98/a2498ea)
--   AFTER this branch was checked out — a directly-callable, EXECUTE-
--   granted-to-authenticated SECURITY INVOKER function is exactly the
--   surface this role's mandate requires cross-tenant verification for, in
--   the SAME PR, so coverage is added here rather than left as a gap.
--   Team-lead's follow-up briefing (its own 5-item list, 11-15) is folded in
--   here under this file's own RA-numbering; correspondence noted per leg.
-- =====================================================================
-- (RA1)/(RA1b)/(RA1c) — team-lead item 11. THE LOCK IS THE TENANT FENCE —
--   one message for BOTH cases (another tenant's schedule, or none at all),
--   deliberately, so the error cannot be used as an existence oracle.
--   (RA1c) is the REQUIRED PAIRED CONTROL: without it, (RA1) alone would
--   pass even if the function raised UNCONDITIONALLY for every caller, not
--   just cross-tenant ones.
select _rls.set_tenant(:'tb'::uuid);
savepoint sp_ra1;
select throws_like(
  format($$ select pfin.fn_tax_bracket_schedule_replace_all(%s::bigint, 2026::smallint, 'federal_ordinary'::pfin.tax_schedule_type_enum, 'ra1 label'::text, 10000.00::numeric, null::numeric, '[]'::jsonb) $$, :sched_a),
  '%is not a schedule this caller owns%',
  '(RA1) B calls replace-all naming A''s REAL schedule_id -> the FOR UPDATE lock runs under B''s own RLS, resolves ZERO ROWS, and RAISES -- the lock IS the tenant fence'
);
select set_config('role', 'postgres', true);
select is(
  (select count(*) from pfin.tax_bracket_row where schedule_id = :sched_b)::bigint,
  1::bigint,
  '(RA1b) B''S OWN rows are UNCHANGED (still the 1 fixture row) after the raise -- the function raises at the lock/fence, its FIRST statement, before touching any row'
);
rollback to savepoint sp_ra1;
select set_config('role', 'postgres', true);

select _rls.set_tenant(:'tb'::uuid);
savepoint sp_ra1c;
select lives_ok(
  format($$ select pfin.fn_tax_bracket_schedule_replace_all(%s::bigint, 2026::smallint, 'federal_ordinary'::pfin.tax_schedule_type_enum, 'ra1c label'::text, 6000.00::numeric, null::numeric, '[]'::jsonb) $$, :sched_b),
  '(RA1c) CONTROL (team-lead item 11''s required pairing): B calls replace-all on B''S OWN schedule -- SUCCEEDS -- proves (RA1)''s raise is owner-mismatch-driven, not a blanket refusal'
);
rollback to savepoint sp_ra1c;
select set_config('role', 'postgres', true);

select _rls.set_tenant(:'ta'::uuid);
savepoint sp_ra2;
select throws_like(
  $$ select pfin.fn_tax_bracket_schedule_replace_all(999999999::bigint, 2026::smallint, 'federal_ordinary'::pfin.tax_schedule_type_enum, 'ra2 label'::text, 10000.00::numeric, null::numeric, '[]'::jsonb) $$,
  '%is not a schedule this caller owns%',
  '(RA2) A calls replace-all naming a NONEXISTENT schedule_id -> SAME message as (RA1) -- confirms the two cases (foreign vs. absent) are deliberately not distinguished'
);
rollback to savepoint sp_ra2;

-- (RA3)-(RA6) p_rows SHAPE VALIDATION -- the layer that still holds when a
--   caller reaches PostgREST directly, bypassing the app's own Zod layer.
savepoint sp_ra3;
select throws_like(
  format($$ select pfin.fn_tax_bracket_schedule_replace_all(%s::bigint, 2026::smallint, 'federal_ordinary'::pfin.tax_schedule_type_enum, 'ra3 label'::text, 10000.00::numeric, null::numeric, '"not-an-array"'::jsonb) $$, :sched_a),
  '%must be a JSON array of bracket objects%',
  '(RA3) p_rows is a JSON STRING, not an array -> RAISES p_rows-shape'
);
rollback to savepoint sp_ra3;

savepoint sp_ra4;
select throws_like(
  format($$ select pfin.fn_tax_bracket_schedule_replace_all(%s::bigint, 2026::smallint, 'federal_ordinary'::pfin.tax_schedule_type_enum, 'ra4 label'::text, 10000.00::numeric, null::numeric, '[1,2]'::jsonb) $$, :sched_a),
  '%every p_rows element must be an object%',
  '(RA4) p_rows is an array of NUMBERS, not objects -> RAISES p_rows-shape'
);
rollback to savepoint sp_ra4;

savepoint sp_ra5;
select throws_like(
  format($$ select pfin.fn_tax_bracket_schedule_replace_all(%s::bigint, 2026::smallint, 'federal_ordinary'::pfin.tax_schedule_type_enum, 'ra5 label'::text, 10000.00::numeric, null::numeric, '[{"bracket_floor": 0}]'::jsonb) $$, :sched_a),
  '%must carry EXACTLY the keys bracket_floor and bracket_rate%',
  '(RA5) an element is MISSING bracket_rate -> RAISES p_rows-shape (exact-key check, not a subset check)'
);
rollback to savepoint sp_ra5;

savepoint sp_ra6;
select throws_like(
  format($$ select pfin.fn_tax_bracket_schedule_replace_all(%s::bigint, 2026::smallint, 'federal_ordinary'::pfin.tax_schedule_type_enum, 'ra6 label'::text, 10000.00::numeric, null::numeric, '[{"bracket_floor": "0", "bracket_rate": 0.10}]'::jsonb) $$, :sched_a),
  '%must both be JSON numbers%',
  '(RA6) bracket_floor arrives as a QUOTED numeric STRING, not a JSON number -> RAISES -- refused deliberately, per the function''s own comment'
);
rollback to savepoint sp_ra6;
select set_config('role', 'postgres', true);

-- (RA7) team-lead item 13 — SUCCESSFUL ATOMIC REPLACE. A's own schedule
--   (sched_a), a REAL effect (not savepoint-rolled-back): delete-then-insert
--   the row set AND update the three scalars, INCLUDING updated_at, in one
--   call. updated_at sentinel technique per (UPD1) above: `now()` is
--   transaction-constant across this whole file, so forcing an old sentinel
--   directly (privileged) first is what makes "moved" observable.
update pfin.tax_bracket_schedule set updated_at = '2000-01-01'::timestamptz where id = :sched_a;
select _rls.set_tenant(:'ta'::uuid);
select lives_ok(
  format($$ select pfin.fn_tax_bracket_schedule_replace_all(%s::bigint, 2026::smallint, 'federal_ordinary'::pfin.tax_schedule_type_enum, 'RA7 replaced label'::text, 15000.00::numeric, 250.00::numeric, '[{"bracket_floor":0,"bracket_rate":0.12},{"bracket_floor":45000,"bracket_rate":0.22}]'::jsonb) $$, :sched_a),
  '(RA7) A replaces its OWN schedule''s brackets and scalars in one call -- succeeds'
);
select set_config('role', 'postgres', true);
select is(
  (select count(*) from pfin.tax_bracket_row where schedule_id = :sched_a)::bigint,
  2::bigint,
  '(RA7a) the OLD single row (floor=0/rate=0.10 from the file''s fixture) is GONE and the NEW two-row set is in place -- delete-then-insert, not an append'
);
select is(
  (select bracket_rate from pfin.tax_bracket_row where schedule_id = :sched_a and bracket_floor = 45000),
  0.22::numeric(12,8),
  '(RA7b) the new row at floor=45000 carries the NEW rate 0.22 -- the insert half landed correctly'
);
select ok(
  (select standard_deduction = 15000.00 and tax_balance_prior_year = 250.00
     from pfin.tax_bracket_schedule where id = :sched_a),
  '(RA7c) the schedule''s scalars (standard_deduction, tax_balance_prior_year) were updated by the SAME call -- the update half landed correctly'
);
select ok(
  (select updated_at > '2000-01-01'::timestamptz from pfin.tax_bracket_schedule where id = :sched_a),
  '(RA7d) updated_at MOVED away from the forced 2000-01-01 sentinel -- the function''s own UPDATE step fires tax_bracket_schedule_set_updated_at just like a direct authenticated UPDATE does'
);
select is(
  (select schedule_label from pfin.tax_bracket_schedule where id = :sched_a),
  'RA7 replaced label',
  '(RA7e) E27/E29: fn_tax_bracket_schedule_replace_all writes p_schedule_label -- read back matches the exact value ("RA7 replaced label") passed at (RA7), not merely a non-null placeholder'
);

-- (RA8) EMPTY ARRAY CLEARS THE SCHEDULE -- legal, per the migration's own
--   absence-is-unset posture.
select _rls.set_tenant(:'ta'::uuid);
select lives_ok(
  format($$ select pfin.fn_tax_bracket_schedule_replace_all(%s::bigint, 2026::smallint, 'federal_ordinary'::pfin.tax_schedule_type_enum, 'ra8 label'::text, 15000.00::numeric, 250.00::numeric, '[]'::jsonb) $$, :sched_a),
  '(RA8) an EMPTY p_rows array is legal and CLEARS the schedule''s brackets -- succeeds'
);
select set_config('role', 'postgres', true);
select is(
  (select count(*) from pfin.tax_bracket_row where schedule_id = :sched_a)::bigint,
  0::bigint,
  '(RA8b) sched_a now carries ZERO bracket rows after the empty-array call'
);

-- (RA9) GRANT STRUCTURAL: authenticated holds EXECUTE; anon/service_role/
--   PUBLIC do not -- the opposite grant shape from the two trigger fences.
select ok(
  (select has_function_privilege('authenticated', p.oid, 'EXECUTE')
     and not has_function_privilege('anon', p.oid, 'EXECUTE')
     and not has_function_privilege('service_role', p.oid, 'EXECUTE')
     and not has_function_privilege('public', p.oid, 'EXECUTE')
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'pfin' and p.proname = 'fn_tax_bracket_schedule_replace_all'),
  '(RA9) fn_tax_bracket_schedule_replace_all: authenticated holds EXECUTE (a direct call is its only use); anon, service_role and PUBLIC do not -- the OPPOSITE grant shape from the two trigger fences, deliberately (a direct call IS how this one is used)'
);

-- (RA10) team-lead item 15 (the concurrency half). CATALOG PIN, not a
--   behavioral concurrency leg: pgTAP cannot hold two concurrent sessions,
--   so the FOR UPDATE lock that serializes the replace-all (execution-log
--   E8) is verified by pinning that the function's body CONTAINS a `for
--   update` clause, via pg_get_functiondef (a real catalog read, not a
--   textual grep for the words "security invoker" or similar prose, which
--   would prove nothing about the actual attribute).
--   ⚠ THE TWO RACE MODES E8 MEASURED ARE RECORDED HERE AS A COMMENT, NOT
--   ASSERTED — team-lead's explicit instruction, because no single-session
--   pgTAP probe can observe either: (i) both callers send a non-empty set ->
--   the SECOND aborts on a duplicate-key violation
--   (tax_bracket_row_schedule_id_bracket_floor_key), because leg A forces
--   bracket_floor 0 into every non-empty schedule and any two non-empty sets
--   therefore collide there; (ii) the second caller sends an EMPTY set to
--   clear the schedule -> NO ERROR AT ALL, and the schedule silently keeps
--   the first caller's rows (a silent lost CLEAR). A ∪ B is NOT reachable on
--   this pair and is deliberately not what this pin, or any leg in this
--   file, claims to prove.
select ok(
  (select pg_get_functiondef(p.oid) ~* 'for update'
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'pfin' and p.proname = 'fn_tax_bracket_schedule_replace_all'),
  '(RA10) CATALOG PIN: fn_tax_bracket_schedule_replace_all''s body contains a FOR UPDATE lock (pg_get_functiondef, a real catalog read) -- this pin stands in for the concurrency proof no single-session pgTAP probe can give; the two measured race modes are recorded in this leg''s own comment above, not asserted'
);

-- (RA-TY1) team-lead item 14 — tax_year = 1900 rejected BY NAME (the new
--   `tax_bracket_schedule_tax_year_check`, fcd8e98). Exercised via the
--   replace-all function itself (this surface's actual write path), not a
--   bare UPDATE, since that CHECK applies regardless of write path.
select _rls.set_tenant(:'ta'::uuid);
savepoint sp_ra_ty1;
select throws_like(
  format($$ select pfin.fn_tax_bracket_schedule_replace_all(%s::bigint, 1900::smallint, 'federal_ordinary'::pfin.tax_schedule_type_enum, 'ra-ty1 label'::text, 15000.00::numeric, null::numeric, '[]'::jsonb) $$, :sched_a),
  '%tax_bracket_schedule_tax_year_check%',
  '(RA-TY1) tax_year = 1900 (before the first US federal income-tax year, 1913) REJECTED BY NAME -- the CHECK constraint tax_bracket_schedule_tax_year_check fires, not merely SOME 23514'
);
rollback to savepoint sp_ra_ty1;
select set_config('role', 'postgres', true);

-- (RA11) team-lead item 12 — the DEFERRED set fence still fires even when
--   the write goes through the function, AND (its explicit ask) "after the
--   failure the prior row set is intact". Chosen instrument: `set
--   constraints all immediate` issued RIGHT AFTER the call (stated
--   explicitly, per team-lead's either/or). A KNOWN prior valid row set is
--   established FIRST (sched_a is empty at this point, from (RA8) — an empty
--   "prior" would make the intact-proof vacuous), the whole probe runs
--   inside ONE outer savepoint, and that savepoint is rolled back AFTER both
--   assertions — simulating what a REAL caller's aborted transaction does
--   (PostgREST wraps each RPC call in its own transaction; an uncaught
--   exception aborts the whole thing, so the function's own DELETE+INSERT
--   never actually commits) — then the prior state is asserted to survive.
--   pgTAP's own throws_like catches the raise via an implicit savepoint
--   scoped to ONLY the failing `set constraints all immediate` statement, so
--   without this file's OWN outer rollback the bad (non-monotone) row set
--   would be left sitting in the table, not the prior one.
select _rls.set_tenant(:'ta'::uuid);
select pfin.fn_tax_bracket_schedule_replace_all(:sched_a::bigint, 2026::smallint, 'federal_ordinary'::pfin.tax_schedule_type_enum, 'ra11-setup label'::text, 15000.00::numeric, 250.00::numeric, '[{"bracket_floor":0,"bracket_rate":0.05}]'::jsonb);
select set_config('role', 'postgres', true);

savepoint sp_ra11;
select _rls.set_tenant(:'ta'::uuid);
set constraints all deferred;
select lives_ok(
  format($$ select pfin.fn_tax_bracket_schedule_replace_all(%s::bigint, 2026::smallint, 'federal_ordinary'::pfin.tax_schedule_type_enum, 'ra11a label'::text, 15000.00::numeric, 250.00::numeric, '[{"bracket_floor":0,"bracket_rate":0.30},{"bracket_floor":40000,"bracket_rate":0.10}]'::jsonb) $$, :sched_a),
  '(RA11a) the CALL ITSELF succeeds even though the batch is non-monotone (0.30 then 0.10) -- the set fence is DEFERRED and has not fired yet, so the function RETURNS CLEANLY'
);
select throws_like(
  'set constraints all immediate',
  '%leg B rate monotonicity%',
  '(RA11b) SET CONSTRAINTS ALL IMMEDIATE, issued RIGHT AFTER the function already returned successfully, RAISES leg B -- proving a caller with no exception from fn_tax_bracket_schedule_replace_all has NOT yet been told the write is valid'
);
select set_config('role', 'postgres', true);
rollback to savepoint sp_ra11;
set constraints all deferred;

select is(
  (select count(*) from pfin.tax_bracket_row where schedule_id = :sched_a)::bigint,
  1::bigint,
  '(RA11c) team-lead item 12''s "after the failure the prior row set is intact": rolling back the failed call (as a real caller''s aborted transaction would) restores the PRIOR set (1 row) -- the non-monotone batch never actually replaced it'
);
select is(
  (select bracket_rate from pfin.tax_bracket_row where schedule_id = :sched_a and bracket_floor = 0),
  0.05::numeric(12,8),
  '(RA11d) the PRIOR row''s exact value (rate=0.05, set up before (RA11) ran) survives -- not merely a row count coincidence'
);

select * from finish();
rollback;
