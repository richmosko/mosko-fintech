-- =====================================================================
-- SELF-228 — §2.1.7 V1.1 CLOSE-GATE (consolidated multi-function cross-tenant
--   RLS battery). F/CTO-ratified AC package, 2026-08-15.
-- =====================================================================
-- SEAM-ONLY. Authors NO schema (no migration / function / policy / column). Proves the
-- SIX §2.1.x V1.1 NAV read functions hold closed AS A WHOLE, under ONE shared two-tenant
-- fixture, exercised together — which no single per-migration battery does. This file
-- COMPOSES those already-green batteries for the deep per-function proofs (arithmetic,
-- NULL-vs-zero, foot-to-NAV, as-of history, AC#6 perf) and adds only the NET-NEW seam.
--
-- Ratified AC coverage (verbatim mapping; AC4 = Sec joint-review verdict, not authored here):
--   AC1 — per-function two-tenant isolation (own-only, zero-owner fails closed) +
--         cross-tenant parameter-probing on the 4 parameterized functions.  BLOCK C.
--   AC2 — full-household-by-construction: (a) signature-level, no scope/tenant param on
--         any of the 6 (live catalog check); (b) behavioral, full-household total = sum
--         over every distinct account.scope.                                BLOCK B + BLOCK D.
--   AC3 — scope-aware filtering verified at the APPLICATION-QUERY layer (SQL join on
--         account.scope), scoped to the account-leaf substrate (fn_account_unrealized_gl)
--         per the ratified caveat — 062/067/072/073 read pre-aggregated full-household
--         nav_daily rows and are structurally out of per-scope filtering (the design, not
--         a gap). NO V1 UI surface.                                          BLOCK D.
--   AC5 — read-path fence: pg_proc.prosecdef = false, live, for all 6.       BLOCK A.
--   PERF (ADR-038 AC#6) — binds to fn_account_unrealized_gl ONLY. Already proven in
--         049_fn_account_unrealized_gl_rls.sql's own T9 (plan legs 9a/9b, performs_ok
--         ≤300ms/20 accts) — COMPOSED, not re-derived here (self209 precedent: this gate
--         does not re-derive a per-migration battery's heavy fixture).
--
-- ┌─ COMPOSE (verified green by the full suite; this file re-proves the cross-cutting seam) ─┐
-- │ 049_fn_account_unrealized_gl_rls.sql (latest DEFINITION is 059 — retired the is_active     │
-- │   boolean per ADR-042 — signature/posture unchanged throughout 049→056→059) ·               │
-- │ 051_fn_nav_composition_rls.sql · 062_fn_nav_series_rls.sql (SELF-219) ·                     │
-- │ 067_fn_nav_series_inflation_adjusted_rls.sql · 071_fn_nav_delta_panel_rls.sql (extended IN  │
-- │   PLACE for 072's real-terms-percent amendment; the battery file stays keyed to 071, the    │
-- │   function's ORIGINAL migration) · 073_fn_nav_reference_dates_rls.sql. SELF-227 (§2.1.6     │
-- │   audit issue) is OUT of this gate's function list — its surfaces are already fenced by     │
-- │   self227_investment_mv_verification.sql. Plan counts are a derived, unwatched property —   │
-- │   read each file's own plan() line live, never transcribe it here (Sec F3).                 │
-- │ Per-function arithmetic, NULL-vs-zero, foot-to-NAV, as-of history, and the AC#6 perf smoke  │
-- │ are COMPOSED from those green batteries — this gate does not re-derive their fixtures; it   │
-- │ proves the seam: all 6 exercised TOGETHER under ONE shared two-tenant fixture (no existing  │
-- │ file does this), plus the two net-new AC2/AC3 assertions neither battery makes.             │
-- └───────────────────────────────────────────────────────────────────────────────────────────┘
--
-- Ledgers all FLAT (SEAM-only, no schema authored): §10 catalogued-instance ledger (ADR-011
-- Decision 4) and the SECURITY DEFINER allowlist (ADR-011 Decision 9) are both untouched — all
-- 6 functions here are INVOKER, so they touch neither. Decision-3 family unchanged. Read ADR-011
-- Decisions 4/9 live at point of use (Path B; Sec N1) — this file moves no ledger and states no
-- count of its own.
--
-- POSTURE (SECURITY §4.5): SYNTHETIC ONLY — fixed-UUID tenants from _rls.tenant_a()/_b()/_c();
-- NO PII / NO real account numbers (SD-15) / NO production data. All seeds PRIVILEGED
-- (role=postgres; RLS+ACL bypassed) with users_id set EXPLICITLY (auth.uid() is NULL under
-- postgres); the six functions are invoked ONLY under the authenticated tenant contexts under
-- test. All in a rolled-back txn — NO INSERT/UPDATE/DELETE against the real tenant's data;
-- every row this file writes carries one of the three fixed synthetic tenant UUIDs.
--
-- Sec joint-review-mandatory (financial calculation + multi-tenant isolation surface). This
-- file must be GREEN before Sec review, and the PR must not merge before Sec's verdict (AC4).
-- =====================================================================

begin;

-- shared cross-tenant verbs (Option C via \ir); nested case -> ../_fixtures/ per DESIGN.md.
\ir ../_fixtures/rls_verbs.psql

-- plan = 34: A 1 (AC5 posture) + B 7 (AC2a: 6 positive-pin IN-argument-vector legs, one
-- per function per Sec F1, + 1 non-vacuous six-function match) + C 20 (fn_nav_series and
-- fn_nav_series_inflation_adjusted carry 4 legs each — A-only / B-side non-vacuity (Sec F2)
-- / zero-owner-closed / cross-tenant parameter-probe; the other 4 functions carry 3 each —
-- A-only / B-side non-vacuity / zero-owner-closed, zero-arg so no separate probe leg) +
-- D 6 (D0 fixture pin + AC2b x2 + AC3 x3). Recorded so a silent plan-edit shows as an
-- arithmetic change.
select plan(34);

-- Resolve the fixed tenant UUIDs to psql literals while privileged (role=postgres).
select _rls.tenant_a() as ta, _rls.tenant_b() as tb, _rls.tenant_c() as tc \gset

insert into auth.users (id) values (:'ta'), (:'tb'), (:'tc');
insert into pfin.user_settings (users_id, mfa_policy) values (:'ta', 'none'), (:'tb', 'none');
-- (tenant_c deliberately gets NO user_settings row — mirrors 062's lazy-provision precedent;
-- tenant_c's zero-owner legs below prove fail-closed even without one.)

-- =====================================================================
-- FIXTURE 1 — nav_daily, FIXED historical dates (062/067 substrate). Two months, one
--   checkpoint each, so 'monthly' resolves cleanly with no risk of the R1 "never emit a
--   period-end after the tenant's overall max checkpoint" edge (both tenants' true overall
--   max is FIXTURE 2's :today point, seeded below, comfortably after this window).
--   A and B hold checkpoints on the SAME dates with DIFFERENT values — the 062 non-vacuity
--   discipline (a same-value fixture would pass under a broken tenant predicate).
-- =====================================================================
select set_config('app.nav_computed_for', :'ta', true);
insert into pfin.nav_daily (users_id, nav_date, nav_value) values
  (:'ta', '2024-01-15', 100000), (:'ta', '2024-02-20', 110000);
select set_config('role', 'postgres', true);
select set_config('app.nav_computed_for', :'tb', true);
insert into pfin.nav_daily (users_id, nav_date, nav_value) values
  (:'tb', '2024-01-15', 900000), (:'tb', '2024-02-20', 910000);
select set_config('role', 'postgres', true);

-- =====================================================================
-- FIXTURE 2 — nav_daily, TODAY-RELATIVE (072/073 substrate; both are zero-arg and read
--   pfin.fn_server_today() internally, so their fixture MUST be anchored to the real clock,
--   not an authored literal). Scaffolding mirrors the 071/073 migrations' OWN date
--   expressions exactly — not the thing under test, just how this file knows which
--   calendar dates to seed regardless of which real day the battery runs on.
--   ⚠ SELF-344/097: :monthanchor (NOT the old :base) is the month/prior_month anchor
--   both 072 and 073 now use — derived by the SAME independent route (integer
--   day-of-month subtraction) 071's and 073's own batteries use, not by copying the
--   body's date_trunc CASE (071's header rule (c), the rule the original defect
--   violated). :monthanchor is ALWAYS in the calendar month strictly before :today,
--   so it can never collide with :today the way the old :base did on a month-end day.
-- =====================================================================
select pfin.fn_server_today() as today \gset
select (:'today'::date - extract(day from :'today'::date)::int) as monthanchor \gset
select (date_trunc('year', :'today'::date::timestamp) - '1 day'::interval)::date as ytdanchor \gset

select set_config('app.nav_computed_for', :'ta', true);
insert into pfin.nav_daily (users_id, nav_date, nav_value) values
  (:'ta', :'today'::date, 500000),
  (:'ta', (:'monthanchor'::date - 2), 490000),
  (:'ta', :'ytdanchor'::date, 400000)
on conflict (users_id, nav_date) do nothing;
select set_config('role', 'postgres', true);
select set_config('app.nav_computed_for', :'tb', true);
insert into pfin.nav_daily (users_id, nav_date, nav_value) values
  (:'tb', :'today'::date, 5000000),
  (:'tb', (:'monthanchor'::date - 2), 4900000),
  (:'tb', :'ytdanchor'::date, 4000000)
on conflict (users_id, nav_date) do nothing;
select set_config('role', 'postgres', true);

-- =====================================================================
-- FIXTURE 3 — accounts, MULTI-SCOPE (049/051 substrate; also AC2b/AC3's substrate).
--   Tenant A: THREE depository accounts, THREE DISTINCT free-text scopes (personal/
--   trust/business — ADR-004 Decision B; no pfin.scope type exists). Depository keeps
--   current_market_value = checkpoint balance with no securities/eod_price rig needed
--   (cost_basis/unrealized_gl NULL by design — already proven elsewhere; not this file's
--   concern). Tenant B: ONE depository account, checkpoint dated the SAME as_of_date as
--   A's (2026-06-01) with a DIFFERENT value — same-date-different-value doubles as the
--   AC1 parameter-probe for the two p_as_of-taking functions (049/051): a broken tenant
--   predicate cannot serve both answers off the identical as_of.
-- =====================================================================
insert into pfin.account (users_id, name, account_type, scope, tax_treatment) values
  (:'ta', 'a-personal', 'depository', 'personal', 'taxable'),
  (:'ta', 'a-trust',    'depository', 'trust',    'taxable'),
  (:'ta', 'a-business', 'depository', 'business', 'taxable');
insert into pfin.account_balance_checkpoint (account_id, balance, currency, as_of_date, source)
  select account_id,
         case scope when 'personal' then 2000 when 'trust' then 3000 else 1500 end,
         'USD', '2026-06-01', 'seed'
  from pfin.account where users_id = :'ta';

insert into pfin.account (users_id, name, account_type, scope, tax_treatment) values
  (:'tb', 'b-household', 'depository', 'household', 'taxable');
insert into pfin.account_balance_checkpoint (account_id, balance, currency, as_of_date, source)
  select account_id, 777, 'USD', '2026-06-01', 'seed'
  from pfin.account where users_id = :'tb';

-- =====================================================================
-- BLOCK A — AC5: read-path fence. pg_proc.prosecdef = false, live, for all six.
-- =====================================================================
select set_eq(
  $$ select p.proname::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'pfin' and p.prosecdef = false
         and p.proname in ('fn_nav_series','fn_nav_series_inflation_adjusted',
                            'fn_nav_delta_panel','fn_nav_reference_dates',
                            'fn_nav_composition','fn_account_unrealized_gl') $$,
  $$ values ('fn_nav_series'::text), ('fn_nav_series_inflation_adjusted'),
            ('fn_nav_delta_panel'), ('fn_nav_reference_dates'),
            ('fn_nav_composition'), ('fn_account_unrealized_gl') $$,
  '(A1) AC5: all SIX V1.1 NAV read functions are SECURITY INVOKER (prosecdef=false), live catalog check — executes under the caller''s authenticated identity per ARCH §4.1; the pfin_etl ingest write path is a separate ratified privileged-writer surface explicitly OUT of this claim'
);

-- =====================================================================
-- BLOCK B — AC2(a): full-household-by-construction, SIGNATURE level. POSITIVE PIN (Sec F1
--   — replaces a prior five-name denylist, which could only ever catch those five spellings).
--   Each leg asserts a function's ORDERED IN-argument name vector via proargnames[1:pronargs].
--   pronargs counts IN/INOUT/VARIADIC parameters only (Sec's caveat) — CONFIRMED live against
--   proargmodes before writing these six legs (not taken on Sec's word): for every RETURNS
--   TABLE function among the six, the 'i'-mode entries are a CONTIGUOUS PREFIX of proargnames
--   of length EXACTLY pronargs, and every entry after that prefix is 't' (the implicit
--   table-output column PostgreSQL appends for RETURNS TABLE — never an 'i' argument). The
--   slice therefore isolates true IN arguments only, in declaration order, for all six shapes
--   (0-arg / 1-arg / 3-arg alike) with no risk of an OUT/table-column name leaking into the
--   comparison. A positive pin also catches an ADDED param under ANY name (e.g. a differently
--   spelled scope/tenant param) — the old denylist only ever covered five specific spellings.
-- =====================================================================
select is(
  (select proargnames[1:pronargs] from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'pfin' and p.proname = 'fn_nav_series'),
  array['p_granularity', 'p_start_date', 'p_end_date']::text[],
  '(B1a) fn_nav_series IN-argument vector = {p_granularity,p_start_date,p_end_date} exactly — no scope/tenant/household parameter present'
);
select is(
  (select proargnames[1:pronargs] from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'pfin' and p.proname = 'fn_nav_series_inflation_adjusted'),
  array['p_granularity', 'p_start_date', 'p_end_date']::text[],
  '(B1b) fn_nav_series_inflation_adjusted IN-argument vector = {p_granularity,p_start_date,p_end_date} exactly'
);
select is(
  (select proargnames[1:pronargs] from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'pfin' and p.proname = 'fn_nav_delta_panel'),
  array[]::text[],
  '(B1c) fn_nav_delta_panel IN-argument vector = {} exactly — zero-arg, confirmed against proargmodes (every entry is the ''t'' table-output mode, none ''i'')'
);
select is(
  (select proargnames[1:pronargs] from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'pfin' and p.proname = 'fn_nav_reference_dates'),
  array[]::text[],
  '(B1d) fn_nav_reference_dates IN-argument vector = {} exactly — zero-arg'
);
select is(
  (select proargnames[1:pronargs] from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'pfin' and p.proname = 'fn_nav_composition'),
  array['p_as_of']::text[],
  '(B1e) fn_nav_composition IN-argument vector = {p_as_of} exactly — no scope/tenant/household parameter'
);
select is(
  (select proargnames[1:pronargs] from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'pfin' and p.proname = 'fn_account_unrealized_gl'),
  array['p_as_of']::text[],
  '(B1f) fn_account_unrealized_gl IN-argument vector = {p_as_of} exactly — no scope/tenant/household parameter'
);
select is(
  (select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'pfin'
       and p.proname in ('fn_nav_series','fn_nav_series_inflation_adjusted',
                          'fn_nav_delta_panel','fn_nav_reference_dates',
                          'fn_nav_composition','fn_account_unrealized_gl')),
  6,
  '(B2) non-vacuous companion: the six-name IN-list resolves to EXACTLY 6 live pfin functions — (A1)/(B1a-f) are not silently narrowed by a typo''d name nor inflated by an unexpected overload'
);

-- =====================================================================
-- BLOCK C — AC1: per-function two-tenant isolation, non-vacuously, + cross-tenant
--   parameter-probing on the four parameterized functions.
-- =====================================================================

-- --- C1: pfin.fn_nav_series(p_granularity, p_start_date, p_end_date) [062] ---
select _rls.set_tenant(:'ta'::uuid);
select is(
  (select array_agg(nav_value order by point_date)
     from pfin.fn_nav_series('monthly', '2024-01-01', '2024-02-29')),
  array[100000, 110000]::numeric[],
  '(C1a) fn_nav_series: A''s monthly series over the FIXTURE-1 window is EXACTLY {100000,110000} — reflects ONLY tenant-A rows, numeric equality against a tenant-A-only expected value'
);
select ok(
  not exists (
    select 1 from pfin.fn_nav_series('monthly', '2024-01-01', :'today'::date)
     where nav_value in (900000, 910000, 5000000, 4900000, 4000000)
  ),
  '(C1c) fn_nav_series PARAMETER-PROBE: widening the window to span BOTH fixtures'' full date range (2024-01-01 through today), still under tenant A auth — no returned point carries ANY of tenant B''s five known values, regardless of how wide the caller-chosen range is'
);
select set_config('role', 'postgres', true);
select _rls.set_tenant(:'tb'::uuid);
select is(
  (select array_agg(nav_value order by point_date)
     from pfin.fn_nav_series('monthly', '2024-01-01', '2024-02-29')),
  array[900000, 910000]::numeric[],
  '(C1d) fn_nav_series NON-VACUITY (Sec F2): the IDENTICAL call under tenant B returns EXACTLY {900000,910000}, not {100000,110000} — 062''s checkpoint selector is `order by nav_date desc limit 1` with NO tiebreak, and A/B share the SAME nav_date values in FIXTURE 1; under a hypothetical RLS leak, (C1a) and (C1d) cannot BOTH hold, whatever an implementation-defined tie resolves to'
);
select set_config('role', 'postgres', true);
select _rls.set_tenant(:'tc'::uuid);
select is(
  (select count(*)::int from pfin.fn_nav_series('monthly', '2024-01-01', :'today'::date)),
  0,
  '(C1b) fn_nav_series: tenant C (zero checkpoints, zero rows anywhere) fails closed — ZERO rows, never an error, never another tenant''s data'
);
select set_config('role', 'postgres', true);

-- --- C2: pfin.fn_nav_series_inflation_adjusted(p_granularity, p_start_date, p_end_date) [067] ---
-- Reuses FIXTURE 1 (same nav_daily rows) — no re-seed; the nominal column is what this
-- gate asserts on (CPI-adjusted columns are the composed 067 battery's own concern).
select _rls.set_tenant(:'ta'::uuid);
select is(
  (select array_agg(nav_nominal order by point_date)
     from pfin.fn_nav_series_inflation_adjusted('monthly', '2024-01-01', '2024-02-29')),
  array[100000, 110000]::numeric[],
  '(C2a) fn_nav_series_inflation_adjusted: A''s monthly nav_nominal series over the FIXTURE-1 window is EXACTLY {100000,110000} — reflects ONLY tenant-A rows'
);
select ok(
  not exists (
    select 1 from pfin.fn_nav_series_inflation_adjusted('monthly', '2024-01-01', :'today'::date)
     where nav_nominal in (900000, 910000, 5000000, 4900000, 4000000)
  ),
  '(C2c) fn_nav_series_inflation_adjusted PARAMETER-PROBE: widened window (2024-01-01 through today), still under tenant A auth — no returned nav_nominal carries ANY of tenant B''s five known values'
);
select set_config('role', 'postgres', true);
select _rls.set_tenant(:'tb'::uuid);
select is(
  (select array_agg(nav_nominal order by point_date)
     from pfin.fn_nav_series_inflation_adjusted('monthly', '2024-01-01', '2024-02-29')),
  array[900000, 910000]::numeric[],
  '(C2d) fn_nav_series_inflation_adjusted NON-VACUITY (Sec F2): the IDENTICAL call under tenant B returns EXACTLY {900000,910000}, not {100000,110000} — 067 inherits 062''s no-tiebreak checkpoint selector via composition; under a hypothetical RLS leak, (C2a) and (C2d) cannot BOTH hold'
);
select set_config('role', 'postgres', true);
select _rls.set_tenant(:'tc'::uuid);
select is(
  (select count(*)::int from pfin.fn_nav_series_inflation_adjusted('monthly', '2024-01-01', :'today'::date)),
  0,
  '(C2b) fn_nav_series_inflation_adjusted: tenant C fails closed — ZERO rows'
);
select set_config('role', 'postgres', true);

-- --- C3: pfin.fn_nav_delta_panel() [072, battery file 071] — zero-arg: no parameter
--   to inject, so no separate probe leg (per the ratified AC1 isolation-shape note). ---
select _rls.set_tenant(:'ta'::uuid);
select is(
  (select delta_nominal from pfin.fn_nav_delta_panel() where horizon = 'month'),
  10000::numeric,
  '(C3a) fn_nav_delta_panel: A''s month-horizon delta_nominal (500000 @ today - 490000 @ month anchor) = 10000 — reflects ONLY tenant-A rows'
);
select set_config('role', 'postgres', true);
select _rls.set_tenant(:'tb'::uuid);
select is(
  (select delta_nominal from pfin.fn_nav_delta_panel() where horizon = 'month'),
  100000::numeric,
  '(C3b) NON-VACUITY: the IDENTICAL call under B returns 100000 (5000000-4900000), not 10000 — A and B hold checkpoints on the SAME dates with DIFFERENT values, so a broken tenant predicate cannot produce both answers'
);
select set_config('role', 'postgres', true);
select _rls.set_tenant(:'tc'::uuid);
select is(
  (select count(*) from pfin.fn_nav_delta_panel()
    where anchor_checkpoint_date is null and delta_nominal is null and delta_percent is null
      and delta_inflation_adjusted is null and delta_inflation_adjusted_percent is null)::int,
  5,
  '(C3c) fn_nav_delta_panel: tenant C (zero checkpoints) — all FIVE horizon rows present with every value-bearing column NULL, fails closed, never an error'
);
select set_config('role', 'postgres', true);

-- --- C4: pfin.fn_nav_reference_dates() [073] — zero-arg: no separate probe leg. ---
select _rls.set_tenant(:'ta'::uuid);
select is(
  (select nav from pfin.fn_nav_reference_dates() where reference = 'this_month'),
  500000::numeric,
  '(C4a) fn_nav_reference_dates: A''s this_month nav = 500000 (the :today checkpoint) — reflects ONLY tenant-A rows'
);
select set_config('role', 'postgres', true);
select _rls.set_tenant(:'tb'::uuid);
select is(
  (select nav from pfin.fn_nav_reference_dates() where reference = 'this_month'),
  5000000::numeric,
  '(C4b) NON-VACUITY: the IDENTICAL call under B returns 5000000, not 500000'
);
select set_config('role', 'postgres', true);
select _rls.set_tenant(:'tc'::uuid);
select is(
  (select count(*) from pfin.fn_nav_reference_dates()
    where reference_checkpoint_date is null and nav is null and nav_prior_yr_dollars is null)::int,
  3,
  '(C4c) fn_nav_reference_dates: tenant C (zero checkpoints) — all THREE reference rows present with every value-bearing column NULL, fails closed, never an error'
);
select set_config('role', 'postgres', true);

-- --- C5: pfin.fn_nav_composition(p_as_of default current_date) [051] ---
select _rls.set_tenant(:'ta'::uuid);
select is(
  (select (pfin.fn_nav_composition('2026-06-01')->>'nav')::numeric),
  6500::numeric,
  '(C5a) fn_nav_composition: A''s nav at as_of 2026-06-01 = 6500 (2000+3000+1500 across three scopes) — reflects ONLY tenant-A rows. PARAMETER-PROBE: as_of is the SAME date B''s own checkpoint sits on (see FIXTURE 3) — a broken tenant predicate serving both answers off the identical as_of cannot pass both (C5a) and (C5b)'
);
select set_config('role', 'postgres', true);
select _rls.set_tenant(:'tb'::uuid);
select is(
  (select (pfin.fn_nav_composition('2026-06-01')->>'nav')::numeric),
  777::numeric,
  '(C5b) NON-VACUITY: the IDENTICAL call (same as_of) under B returns 777, not 6500'
);
select set_config('role', 'postgres', true);
select _rls.set_tenant(:'tc'::uuid);
select is(
  (select pfin.fn_nav_composition('2026-06-01')),
  '{"nav": 0, "groups": [], "buildups": {"debt": 0, "gross_total": 0, "total_non_re": 0, "realized_tax_liab": 0, "unrealized_tax_liab": 0}}'::jsonb,
  '(C5c) fn_nav_composition: tenant C (zero accounts) — nav 0, empty groups[], fails closed, never an error'
);
select set_config('role', 'postgres', true);

-- --- C6: pfin.fn_account_unrealized_gl(p_as_of default current_date) [049; latest def 059] ---
select _rls.set_tenant(:'ta'::uuid);
select is(
  (select sum(current_market_value) from pfin.fn_account_unrealized_gl('2026-06-01')),
  6500::numeric,
  '(C6a) fn_account_unrealized_gl: Σ current_market_value across A''s 3 rows at as_of 2026-06-01 = 6500 — reflects ONLY tenant-A rows. PARAMETER-PROBE: same shared as_of as B (FIXTURE 3)'
);
select set_config('role', 'postgres', true);
select _rls.set_tenant(:'tb'::uuid);
select is(
  (select sum(current_market_value) from pfin.fn_account_unrealized_gl('2026-06-01')),
  777::numeric,
  '(C6b) NON-VACUITY: the IDENTICAL call (same as_of) under B returns 777, not 6500'
);
select set_config('role', 'postgres', true);
select _rls.set_tenant(:'tc'::uuid);
select is(
  (select count(*)::int from pfin.fn_account_unrealized_gl('2026-06-01')),
  0,
  '(C6c) fn_account_unrealized_gl: tenant C (zero accounts) — ZERO rows, fails closed'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK D — AC2(b) full-household-by-construction (BEHAVIORAL) + AC3 scope-aware
--   filtering at the SQL layer. Reuses FIXTURE 3's tenant-A multi-scope accounts.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);

-- (D0) fixture pin: the partition below is only meaningful if the three scopes are
--   genuinely distinct — guards against a typo collapsing them into one.
select is(
  (select count(distinct scope)::int from pfin.account where users_id = :'ta'),
  3,
  '(D0) fixture pin: tenant A''s three accounts carry THREE DISTINCT scope values (personal/trust/business) — the AC2(b)/AC3 sums below are only meaningful if this partition is real, not accidentally collapsed'
);

-- (D1) AC2(b) behavioral: fn_account_unrealized_gl's UNFILTERED total already equals the
--   sum over EVERY distinct scope — calling the function bare is full-household BY
--   CONSTRUCTION, not by accident of a missing filter (per ADR-004 Decision B + SECURITY
--   §4.1 axis-ii).
select is(
  (select sum(current_market_value) from pfin.fn_account_unrealized_gl('2026-06-01')),
  (select sum(g.current_market_value)
     from pfin.fn_account_unrealized_gl('2026-06-01') g
     join pfin.account a on a.account_id = g.account_id
    where a.scope in ('personal', 'trust', 'business')),
  '(D1) AC2(b): fn_account_unrealized_gl''s bare (unfiltered) total EQUALS the sum re-computed by explicitly grouping over every distinct scope — full-household is the DEFAULT, not a coincidence of an absent filter'
);

-- (D2) AC2(b) cross-function companion: fn_nav_composition's nav agrees with the SAME
--   independently-summed total (the two functions compose on the same substrate).
select is(
  (select (pfin.fn_nav_composition('2026-06-01')->>'nav')::numeric),
  (select sum(g.current_market_value)
     from pfin.fn_account_unrealized_gl('2026-06-01') g
     join pfin.account a on a.account_id = g.account_id
    where a.scope in ('personal', 'trust', 'business')),
  '(D2) AC2(b) cross-function companion: fn_nav_composition''s nav agrees EXACTLY with the independently-summed full-household total — both functions are full-household by construction, not just one of them'
);

-- (D3)/(D4)/(D5) AC3: scope-aware filtering at the SQL LAYER (no V1 UI surface; no native
--   function parameter exists — see (B1)). A query joining fn_account_unrealized_gl to
--   pfin.account on account.scope sums ONLY the requested scopes.
select is(
  (select sum(g.current_market_value)
     from pfin.fn_account_unrealized_gl('2026-06-01') g
     join pfin.account a on a.account_id = g.account_id
    where a.scope in ('personal', 'trust')),
  5000::numeric,
  '(D3) AC3: SQL-layer scope filter restricted to (personal,trust) sums to EXACTLY 5000 (2000+3000) — excludes the business-scope leaf'
);
select is(
  (select sum(g.current_market_value)
     from pfin.fn_account_unrealized_gl('2026-06-01') g
     join pfin.account a on a.account_id = g.account_id
    where a.scope not in ('personal', 'trust')),
  1500::numeric,
  '(D4) AC3 companion: the EXCLUDED scope (business) sums to EXACTLY 1500 — the restricted sum in (D3) is a real partition, not a filter that happens to admit everything'
);
select is(
  (select
     (select sum(g.current_market_value) from pfin.fn_account_unrealized_gl('2026-06-01') g
        join pfin.account a on a.account_id = g.account_id where a.scope in ('personal', 'trust'))
     +
     (select sum(g.current_market_value) from pfin.fn_account_unrealized_gl('2026-06-01') g
        join pfin.account a on a.account_id = g.account_id where a.scope not in ('personal', 'trust'))
  ),
  (select sum(current_market_value) from pfin.fn_account_unrealized_gl('2026-06-01')),
  '(D5) AC3 closes the loop: restricted-scope sum (D3) + excluded-scope sum (D4) = the full unfiltered total — the SQL-layer partition is exhaustive, no leaf double-counted or dropped'
);
select set_config('role', 'postgres', true);

select * from finish();
rollback;
