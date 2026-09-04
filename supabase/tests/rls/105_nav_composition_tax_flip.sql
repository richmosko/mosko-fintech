-- =====================================================================
-- Per-Wave battery — pfin.fn_nav_composition, the §2.5.4 TAX FLIP (SELF-268;
--   migration 105). Paired with the migration in the SAME PR
--   (verify-paired-artifacts discipline). Companion file to
--   051_fn_nav_composition_rls.sql (which carries the pre-existing §2.1.5
--   composition/grouping/debt-sign/is_active legs, RE-CUT in this same PR
--   for the envelope-shaped tax keys) — this file is the NEW SELF-268/105
--   surface: the tax scalars now reaching NAV as REAL VALUES instead of
--   0::numeric literals, per ADR-067 Decision 5 / Sec's pre-ruling P-16..P-19.
-- =====================================================================
-- BINDS TO MIGRATION: supabase/migrations/105_nav_composition_tax_flip.sql.
--   pfin.fn_nav_composition(p_as_of date default current_date) — SECURITY
--   INVOKER, STABLE, set search_path = ''. buildups.realized_tax_liab /
--   unrealized_tax_liab are now the ENVELOPE OBJECTS carried VERBATIM from
--   pfin.fn_compute_tax_liability(p_as_of)->'nav_components' (104 / SELF-262);
--   nav subtracts coalesce(amount, 0) for each. ONE call to 104 per
--   invocation (P-16), threaded with 051's OWN p_as_of (Seam C / rider 4).
--   fn_compute_nav (both overloads) is UNTOUCHED.
--
-- ┌─ WHAT THIS BATTERY PROVES — one line per required leg ─────────────────────┐
-- │ P   CATALOG POSTURE: prosecdef=f, provolatile=s, search_path='' pinned,    │
-- │       EXECUTE revoked PUBLIC / granted authenticated, on fn_nav_composition│
-- │       itself (051's own file does not carry this leg; self228's Block A    │
-- │       covers prosecdef only, across all six V1.1 functions).               │
-- │ NAV  fn_compute_nav(date) / fn_compute_nav(date,boolean) BYTE-UNCHANGED —  │
-- │       pinned against the SAME md5 values 104's own L20a/L20b carry, so a   │
-- │       drift in EITHER file's pin is caught by the other.                  │
-- │ ONE  P-16: fn_nav_composition's OWN catalog body calls                    │
-- │       fn_compute_tax_liability EXACTLY ONCE (call-shaped regex count on    │
-- │       prosrc, not a name-substring count — the header comment ALSO names  │
-- │       the helper in prose, which a bare substring count would double-     │
-- │       count; measured and stated below). "The planner MAY fold two        │
-- │       identical STABLE calls" is not a control (Sec P-16) — this asserts  │
-- │       the SOURCE calls it once, by construction, which the two-CTE shape  │
-- │       (`tax` then `tax_scalars`) delivers structurally.                    │
-- │ ENV  Both `buildups` envelope keys are BYTE-EQUAL to                       │
-- │       fn_compute_tax_liability(p_as_of)->'nav_components' read            │
-- │       independently, same as_of, same tenant — proves "carried verbatim"  │
-- │       rather than re-derived or re-shaped.                                 │
-- │ FOOT nav = gross_total − debt − coalesce(realized.amount,0) −             │
-- │       coalesce(unrealized.amount,0), computed from the RETURNED payload,  │
-- │       in BOTH boundary-pair states (051's own S6 leg now only exercises   │
-- │       the both-unavailable/zero-tax case; this exercises the NON-zero     │
-- │       case).                                                               │
-- │ GT   gross_total is UNMOVED across the boundary-pair transaction — the    │
-- │       only thing that changed is a balance on a DESIGNATED (excluded)     │
-- │       ledger.                                                              │
-- │ DES  DESIGNATED-LEDGER EXCLUSION, LIVE (102's anti-join, exercised through │
-- │       105's foot): gross_total = the UNFILTERED account sum MINUS the     │
-- │       sum of every fn_tax_authority_ledgers() account's current_market_   │
-- │       value — computed independently, non-vacuous (both designated       │
-- │       ledgers carry a real nonzero balance at this state).                │
-- │ BND  D-3 / Sec M-3 BOUNDARY PAIR, one tenant, one transaction apart, all   │
-- │       else identical: an UNDERPAID state (realized POSITIVE, nav LOWER    │
-- │       than the zero-tax baseline by exactly the combined-jurisdiction     │
-- │       sum) and an OVERPAID state (realized NEGATIVE after a single        │
-- │       payment, nav HIGHER than the same baseline by exactly the excess) — │
-- │       plus the direct transition (nav rises by EXACTLY the payment).      │
-- │ PI   (π) TAX-ADVANTAGED EXCLUSION reaching NAV: a tax_deferred account's   │
-- │       gain is excluded from Unrealized; RECLASSIFYING it to taxable moves  │
-- │       nav by EXACTLY minus its own contribution × the combined top rate — │
-- │       the inversion IS the fixture (104's own L12 pattern, one layer up   │
-- │       at the NAV composer rather than at fn_compute_tax_liability itself).│
-- │ R9   THE ZERO CLAMP, LIVE AT THE COMPOSER: a NEGATIVE aggregate taxable    │
-- │       unrealized G/L (independently confirmed negative via a raw query)   │
-- │       yields unrealized_tax_liab.amount = 0, not the negative pre-clamp   │
-- │       figure — nav is NOT raised by it.                                    │
-- │ X    CROSS-TENANT: under A's RLS, none of B's leaf accounts appear (and   │
-- │       vice versa) — both tenants' rich fixtures coexist in one database.  │
-- │ BOOT BOOTSTRAP / NEVER-NULL: a tenant with ZERO accounts and ZERO         │
-- │       schedules gets nav = 0 (never NULL), empty groups[], BOTH envelopes │
-- │       {unavailable, no_schedule_any_year} — the state every user is in on │
-- │       day one (E26 ruling 1 / rider 0b).                                  │
-- │ DAY  fn_nav_composition's OWN catalog body contains NO reference to       │
-- │       nav_daily (104's own L19 pattern, applied to 051's function).       │
-- └──────────────────────────────────────────────────────────────────────────┘
--
-- ⚠ INVERSION-TESTED, NOT AS COMMITTED LEGS (transient ALTER FUNCTION against
--   this branch's own scratch clone, verified then reverted — never committed,
--   consistent with 051's own "authored + smoke-verified GREEN via a transient
--   apply+rollback" convention): (1) removing the `coalesce(…, 0)` around
--   either `->>'amount'` unwrap turns `nav` to SQL NULL the moment either
--   scalar is `unavailable` — the BOOT block's `nav IS NOT NULL` leg goes RED.
--   (2) replacing 104's R9 `greatest(…, 0)` clamp with the bare unclamped
--   product turns the R9 leg's `unrealized_tax_liab.amount` from 0 to the
--   NEGATIVE pre-clamp figure this file's own independent query already
--   computes — the R9 leg goes RED, non-vacuously (the negative figure is
--   real, not a typo). (3) swapping the sign of the `unrealized_applied`
--   subtraction in the `nav` expression (i.e. ADDING instead of subtracting)
--   turns the FOOT legs RED in both boundary-pair states, because
--   `unrealized_applied` is nonzero in tenant B's fixture and the internal
--   foot no longer matches the returned `nav` — not exercised by tenant A's
--   own boundary pair, since its unrealized term is 0 there by construction.
--   All three reverted before this file was finalized; the committed body
--   below is the UN-mutated 105.
--
-- §10 / DECISION 3: §10 ledger UNCHANGED (ADR-011 Decision 4 read live before
--   drafting; no catalogued instance added/reordered/renumbered, no layer
--   re-attributed). Decision-3 family UNCHANGED (this file authors no
--   table/column; it exercises 105's read-composition only). SECURITY
--   DEFINER allowlist UNCHANGED (fn_nav_composition and fn_compute_tax_
--   liability are both INVOKER). This battery introduces no catalogued
--   instance; it is the pgTAP proof of SELF-268's NAV-composition tax flip.
--
-- POSTURE (SECURITY §4.5): SYNTHETIC ONLY — fixed-UUID tenants
--   _rls.tenant_a()/_b()/_c(); NO PII / NO real account numbers (SD-15) / NO
--   real Plaid tokens (SD-03) / NO prod data. All dollar/rate figures below
--   are synthetic test fixtures. All seeds PRIVILEGED (role=postgres;
--   RLS+ACL bypassed) with users_id set EXPLICITLY; the functions under test
--   are invoked ONLY under the authenticated tenant contexts. All in a
--   rolled-back txn — no `supabase db reset`.
--
-- Sec joint-review-mandatory (financial calculation + the definition of NAV
--   + multi-tenant isolation).
-- =====================================================================

begin;

\ir ../_fixtures/rls_verbs.psql

-- plan = 28: P 3 · NAV 2 · ONE 1 · ENV 2 · FOOT 2 · GT 1 · DES 2 · BND 5 ·
--   PI 4 · R9 2 · X 2 · BOOT 2 · DAY 1. (P is 3, not 4: prosecdef+provolatile+
--   search_path is ONE combined leg, ACL is a second, non-vacuity of the
--   name resolving to exactly one live function is folded into the ACL leg's
--   own has_function_privilege calls, which error on a missing/ambiguous
--   name rather than silently pass.)
select plan(28);

select _rls.tenant_a() as ta, _rls.tenant_b() as tb, _rls.tenant_c() as tc \gset

insert into auth.users (id) values (:'ta'), (:'tb'), (:'tc');

select set_config('role', 'postgres', true);

-- =====================================================================
-- CATALOG-LEVEL LEGS (P / NAV / ONE / DAY) — no fixture needed, run first.
-- =====================================================================

-- (P1) POSTURE: SECURITY INVOKER, STABLE, search_path pinned empty.
select is(
  (select array[p.prosecdef::text, p.provolatile::text, array_to_string(p.proconfig, ',')]
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'pfin' and p.proname = 'fn_nav_composition'),
  array['false', 's', 'search_path=""'],
  '(P1) fn_nav_composition(date) POSTURE: SECURITY INVOKER (prosecdef false), STABLE (provolatile s), search_path pinned empty — RE-ASSERTED, not changed, by 105''s CREATE OR REPLACE (which resets volatility unless re-declared in the body)'
);
-- (P2) ACL: EXECUTE revoked from PUBLIC, granted to authenticated.
select ok(
  not has_function_privilege('anon', 'pfin.fn_nav_composition(date)', 'execute')
  and has_function_privilege('authenticated', 'pfin.fn_nav_composition(date)', 'execute'),
  '(P2) fn_nav_composition(date) EXECUTE revoked from PUBLIC (anon denied), granted to authenticated only'
);
-- (P3 / DAY) fn_nav_composition's OWN catalog body contains no nav_daily reference.
select ok(
  (select prosrc !~ 'nav_daily' from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'pfin' and p.proname = 'fn_nav_composition'),
  '(P3 / DAY) pfin.fn_nav_composition''s CATALOG BODY (pg_proc.prosrc) contains NO reference to nav_daily — 105 threads only fn_compute_tax_liability''s output, never the checkpointed series'
);

-- (NAV1)/(NAV2) fn_compute_nav BOTH overloads BYTE-UNCHANGED by 105 — pinned
--   against the SAME values 104's own L20a/L20b measure, so a drift in either
--   file's pin surfaces in the other.
select is(
  (select md5(pg_get_functiondef(p.oid))
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'pfin' and p.proname = 'fn_compute_nav'
      and pg_get_function_arguments(p.oid) = 'p_as_of date'),
  'c207483f5e786fb5e90a03212b2de5e0',
  '(NAV1) fn_compute_nav(date) is BYTE-UNCHANGED by 105 — matches 104''s own L20a pin'
);
select is(
  (select md5(pg_get_functiondef(p.oid))
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'pfin' and p.proname = 'fn_compute_nav'
      and pg_get_function_arguments(p.oid) = 'p_as_of date, p_active_only boolean'),
  '9917963f130498c3614eb6d550f53f51',
  '(NAV2) fn_compute_nav(date,boolean) is BYTE-UNCHANGED by 105 — matches 104''s own L20b pin'
);

-- (ONE / P-16) fn_nav_composition calls fn_compute_tax_liability EXACTLY ONCE,
--   by a CALL-SHAPED regex (name immediately followed by an open paren) rather
--   than a bare substring count — the header comment ALSO names the helper in
--   prose ("ONE call to the keystone helper") without a trailing paren, so a
--   naive substring count reads 2 and is wrong for the wrong reason. Measured
--   directly against this branch: the call-shaped count is 1, the bare
--   substring count is 2 (confirms the regex is doing real discriminating
--   work, not coincidentally agreeing with a cruder count).
select is(
  (select count(*)::int from regexp_matches(
     (select prosrc from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'pfin' and p.proname = 'fn_nav_composition'),
     'fn_compute_tax_liability\s*\(', 'g')),
  1,
  '(ONE) fn_nav_composition''s OWN prosrc calls fn_compute_tax_liability EXACTLY ONCE (call-shaped occurrence, not a name-substring count) — P-16''s "one CTE, both readers" shape asserted structurally rather than trusted to planner call-folding'
);

-- =====================================================================
-- TENANT A FIXTURE — the D-3 / Sec M-3 BOUNDARY PAIR + the designated-ledger
--   exclusion, all on ONE account set, ONE transaction apart between states.
--   a_dep is the only non-designated leaf (gross_total's sole contributor);
--   acct_irs / acct_ftb are the two designated ledgers (federal / california)
--   and are EXCLUDED from the leaf set by 102's anti-join throughout.
-- =====================================================================
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'ta', 'a-dep-105', 'depository', 'household', 'taxable') returning account_id as a_dep \gset
insert into pfin.account_balance_checkpoint (account_id, balance, currency, as_of_date, source)
  values (:a_dep, 10000.0000, 'USD', '2026-01-01', 'seed');

insert into pfin.posting_prototype (users_id, cat, sub_cat, tax_relevant, tax_character, is_tax_payment)
  values (:'ta', 'Revenue', 'Salary105', true, null, false) returning id as a_sal \gset
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, created_at)
  values (:a_dep, '2026-01-10', 5000.0000, 'salary-105', '2026-01-10'::timestamptz)
  returning trans_id as t_sal \gset
insert into pfin.account_trans_annotation (trans_id, sub_cat_id) values (:t_sal, :a_sal);
-- a_dep current_market_value = 10000 (checkpoint) + 5000 (salary) = 15000 at any
-- as_of on/after 2026-01-10 — the fixture's gross_total, verified below (GT/FOOT).

-- Bracket schedules, tax_year 2026, ONE flat-rate bracket each (rates chosen
-- distinct — 0.10/0.05/0.10 — so no two schedules coincidentally cancel):
-- federal_ordinary + federal_lt_cg (both required for federal.computed) and
-- california_ordinary (california's sole required schedule). $5000 ordinary
-- income (no qualified_dividend / tax_exempt_interest) reaches BOTH federal
-- ordinary AND california — no LT CG income is seeded, so the LT CG walk
-- taxes 0 regardless of its own rate; its ONLY role here is making
-- federal.computed true.
insert into pfin.tax_bracket_schedule (users_id, schedule_type, tax_year, standard_deduction, schedule_label)
  values (:'ta', 'federal_ordinary', 2026, 0.0000, 'a-fedord-105') returning id as sch_fo \gset
insert into pfin.tax_bracket_row (users_id, schedule_id, bracket_floor, bracket_rate)
  values (:'ta', :sch_fo, 0, 0.10);
insert into pfin.tax_bracket_schedule (users_id, schedule_type, tax_year, standard_deduction, schedule_label)
  values (:'ta', 'federal_lt_cg', 2026, 0.0000, 'a-fedltcg-105') returning id as sch_fl \gset
insert into pfin.tax_bracket_row (users_id, schedule_id, bracket_floor, bracket_rate)
  values (:'ta', :sch_fl, 0, 0.05);
insert into pfin.tax_bracket_schedule (users_id, schedule_type, tax_year, standard_deduction, schedule_label)
  values (:'ta', 'california_ordinary', 2026, 0.0000, 'a-caord-105') returning id as sch_ca \gset
insert into pfin.tax_bracket_row (users_id, schedule_id, bracket_floor, bracket_rate)
  values (:'ta', :sch_ca, 0, 0.10);
-- obl_irs (federal, ordinary-only since no LT CG income) = 5000 x 0.10 = 500.00.
-- obl_ftb (california) = 5000 x 0.10 = 500.00. as_of below is 2026-12-31 —
-- installments_due_through_next = 4, so obligation_to_date = the ROUNDED
-- ANNUAL (500.00) for both, no quarterly proration to hand-verify.

-- The two designated ledgers — the ONLY two a tenant may hold, one per
-- jurisdiction (account_tax_jurisdiction_uniq, 102). acct_ftb carries a FIXED
-- $300 balance throughout (the DES leg's non-vacuous nonzero exclusion);
-- acct_irs starts at $0 (STATE 1: underpaid) and gets ONE $1000 payment
-- (STATE 2: overpaid) — the boundary-pair's one-transaction step.
insert into pfin.account (users_id, name, account_type, scope, tax_treatment, tax_jurisdiction)
  values (:'ta', 'a-irs-105', 'depository', 'household', 'taxable', 'irs') returning account_id as acct_irs \gset
insert into pfin.account (users_id, name, account_type, scope, tax_treatment, tax_jurisdiction)
  values (:'ta', 'a-ftb-105', 'depository', 'household', 'taxable', 'ftb') returning account_id as acct_ftb \gset
insert into pfin.account_balance_checkpoint (account_id, balance, currency, as_of_date, source)
  values (:acct_ftb, 300.0000, 'USD', '2026-01-01', 'seed');

select _rls.set_tenant(:'ta'::uuid);

-- ---- STATE 1 (UNDERPAID): acct_irs ytd_paid = 0 -> funds_due_irs = 500.00;
--   acct_ftb ytd_paid = 300 (fixed) -> funds_due_ftb = 200.00 -> realized =
--   700.00 (POSITIVE = underpaid, on BOTH jurisdictions combined). ----------
select is(
  jsonb_build_object(
    'status', pfin.fn_nav_composition('2026-12-31'::date) -> 'buildups' -> 'realized_tax_liab' ->> 'status',
    'amount', ((pfin.fn_nav_composition('2026-12-31'::date) -> 'buildups' -> 'realized_tax_liab' ->> 'amount')::numeric)
  ),
  jsonb_build_object('status', 'computed', 'amount', 700.0000::numeric),
  '(BND1) STATE 1 (underpaid): buildups.realized_tax_liab = {computed, 700.0000} = funds_due_irs(500.00, ytd 0) + funds_due_ftb(200.00, ytd 300 fixed) — POSITIVE, the combined-jurisdiction SUM the underpaid direction subtracts'
);
-- (ENV1/ENV2) byte-equal to fn_compute_tax_liability's OWN nav_components, read
--   independently, same tenant / same as_of — proves "carried verbatim".
select is(
  pfin.fn_nav_composition('2026-12-31'::date) -> 'buildups' -> 'realized_tax_liab',
  pfin.fn_compute_tax_liability('2026-12-31'::date) -> 'nav_components' -> 'realized_tax_liab',
  '(ENV1) buildups.realized_tax_liab is BYTE-EQUAL to fn_compute_tax_liability(as_of)->nav_components->realized_tax_liab, read independently — carried VERBATIM, not re-derived'
);
select is(
  pfin.fn_nav_composition('2026-12-31'::date) -> 'buildups' -> 'unrealized_tax_liab',
  pfin.fn_compute_tax_liability('2026-12-31'::date) -> 'nav_components' -> 'unrealized_tax_liab',
  '(ENV2) buildups.unrealized_tax_liab is BYTE-EQUAL to fn_compute_tax_liability(as_of)->nav_components->unrealized_tax_liab, read independently — carried VERBATIM, not re-derived'
);
-- (FOOT1) STATE 1: nav = gross_total - debt - coalesce(realized.amount,0) -
--   coalesce(unrealized.amount,0), from the RETURNED payload.
select is(
  (pfin.fn_nav_composition('2026-12-31'::date) ->> 'nav')::numeric,
  (
    (pfin.fn_nav_composition('2026-12-31'::date) -> 'buildups' ->> 'gross_total')::numeric
    - (pfin.fn_nav_composition('2026-12-31'::date) -> 'buildups' ->> 'debt')::numeric
    - coalesce((pfin.fn_nav_composition('2026-12-31'::date) -> 'buildups' -> 'realized_tax_liab' ->> 'amount')::numeric, 0)
    - coalesce((pfin.fn_nav_composition('2026-12-31'::date) -> 'buildups' -> 'unrealized_tax_liab' ->> 'amount')::numeric, 0)
  ),
  '(FOOT1) STATE 1: nav internal consistency with the tax keys UNWRAPPED (the raw ->>''realized_tax_liab''::numeric cast 051''s old S6 used is a hard ERROR now that the key is an envelope OBJECT)'
);
-- (BND3) STATE 1: nav is LOWER than the zero-tax baseline by EXACTLY the sum.
select is(
  (
    (pfin.fn_nav_composition('2026-12-31'::date) -> 'buildups' ->> 'gross_total')::numeric
    - (pfin.fn_nav_composition('2026-12-31'::date) -> 'buildups' ->> 'debt')::numeric
    - coalesce((pfin.fn_nav_composition('2026-12-31'::date) -> 'buildups' -> 'unrealized_tax_liab' ->> 'amount')::numeric, 0)
  ) - (pfin.fn_nav_composition('2026-12-31'::date) ->> 'nav')::numeric,
  700.0000::numeric,
  '(BND3) STATE 1 (underpaid): the zero-tax baseline (gross_total - debt - unrealized only) MINUS the actual nav = 700.0000 EXACTLY = the combined-jurisdiction underpayment sum (BND1) — "nav lower by exactly the sum"'
);

select 'STATE1' as marker, pfin.fn_nav_composition('2026-12-31'::date) ->> 'nav' as nav_state1 \gset

-- ---- STATE 2 (OVERPAID): ONE $1000 payment lands on acct_irs. ------------
select set_config('role', 'postgres', true);
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, created_at)
  values (:acct_irs, '2026-06-01', 1000.0000, 'irs-pay-105', '2026-06-01'::timestamptz);
select _rls.set_tenant(:'ta'::uuid);

select is(
  jsonb_build_object(
    'status', pfin.fn_nav_composition('2026-12-31'::date) -> 'buildups' -> 'realized_tax_liab' ->> 'status',
    'amount', ((pfin.fn_nav_composition('2026-12-31'::date) -> 'buildups' -> 'realized_tax_liab' ->> 'amount')::numeric)
  ),
  jsonb_build_object('status', 'computed', 'amount', -300.0000::numeric),
  '(BND2) STATE 2 (overpaid, ONE transaction later): buildups.realized_tax_liab = {computed, -300.0000} = funds_due_irs(500.00-1000.00=-500.00) + funds_due_ftb(200.00, unchanged) — NEGATIVE, the double-negation route Sec M-3 names would silently flip this'
);
-- (GT1) gross_total is UNMOVED — the only thing that changed is a balance on
--   a DESIGNATED (excluded) ledger.
select is(
  (pfin.fn_nav_composition('2026-12-31'::date) -> 'buildups' ->> 'gross_total')::numeric,
  15000.0000::numeric,
  '(GT1) STATE 2: buildups.gross_total is STILL 15000.0000, UNMOVED from STATE 1 — the $1000 payment landed on acct_irs, a DESIGNATED (anti-joined-out) ledger, and never touches the leaf set'
);
-- (FOOT2) STATE 2: nav internal consistency, same formula as FOOT1.
select is(
  (pfin.fn_nav_composition('2026-12-31'::date) ->> 'nav')::numeric,
  (
    (pfin.fn_nav_composition('2026-12-31'::date) -> 'buildups' ->> 'gross_total')::numeric
    - (pfin.fn_nav_composition('2026-12-31'::date) -> 'buildups' ->> 'debt')::numeric
    - coalesce((pfin.fn_nav_composition('2026-12-31'::date) -> 'buildups' -> 'realized_tax_liab' ->> 'amount')::numeric, 0)
    - coalesce((pfin.fn_nav_composition('2026-12-31'::date) -> 'buildups' -> 'unrealized_tax_liab' ->> 'amount')::numeric, 0)
  ),
  '(FOOT2) STATE 2: nav internal consistency holds with realized NOW NEGATIVE — the subtraction of a negative number is what "nav rises" MEANS arithmetically; a double-negation bug would make this leg fail even though FOOT1 passed'
);
-- (BND4) STATE 2: nav is HIGHER than the SAME zero-tax baseline by EXACTLY the excess.
select is(
  (pfin.fn_nav_composition('2026-12-31'::date) ->> 'nav')::numeric - (
    (pfin.fn_nav_composition('2026-12-31'::date) -> 'buildups' ->> 'gross_total')::numeric
    - (pfin.fn_nav_composition('2026-12-31'::date) -> 'buildups' ->> 'debt')::numeric
    - coalesce((pfin.fn_nav_composition('2026-12-31'::date) -> 'buildups' -> 'unrealized_tax_liab' ->> 'amount')::numeric, 0)
  ),
  300.0000::numeric,
  '(BND4) STATE 2 (overpaid): actual nav MINUS the zero-tax baseline = 300.0000 EXACTLY = the net overpayment excess (|realized| in BND2) — "nav higher by exactly the excess". This is the leg Sec M-3''s double-negation route flips: an abs() or a second sign-flip anywhere on the realized path renders 700 (BND1''s figure) here instead of 300'
);
-- (BND5) the DIRECT transition: nav rises by EXACTLY the $1000 payment,
--   one transaction apart, all else identical (gross_total pinned at GT1).
select is(
  (pfin.fn_nav_composition('2026-12-31'::date) ->> 'nav')::numeric - :'nav_state1'::numeric,
  1000.0000::numeric,
  '(BND5) the ONE-STEP transition: nav(STATE 2) - nav(STATE 1) = 1000.0000 EXACTLY = the single $1000 payment on acct_irs — "one step apart, all else identical"'
);

-- ---- DESIGNATED-LEDGER EXCLUSION, LIVE (at STATE 2, where BOTH designated
--   ledgers carry a real nonzero balance: acct_irs $1000, acct_ftb $300). ----
select ok(
  (select sum(g.current_market_value) from pfin.fn_tax_authority_ledgers() tal
     join pfin.fn_account_unrealized_gl('2026-12-31'::date) g on g.account_id = tal.account_id) = 1300.0000::numeric,
  '(DES-pin) non-vacuous: A''s two designated ledgers carry a combined 1300.0000 balance at STATE 2 (1000 + 300) — the exclusion leg below is not exercising a $0 exclusion'
);
select is(
  (pfin.fn_nav_composition('2026-12-31'::date) -> 'buildups' ->> 'gross_total')::numeric,
  (select sum(g.current_market_value) from pfin.fn_account_unrealized_gl('2026-12-31'::date) g)
    - coalesce((select sum(g.current_market_value) from pfin.fn_tax_authority_ledgers() tal
                  join pfin.fn_account_unrealized_gl('2026-12-31'::date) g on g.account_id = tal.account_id), 0),
  '(DES) gross_total = the UNFILTERED per-account sum MINUS the designated-ledgers'' sum, computed INDEPENDENTLY via fn_tax_authority_ledgers() — 102''s anti-join exclusion, exercised live through 105''s own foot, non-vacuously (DES-pin)'
);

select set_config('role', 'postgres', true);

-- =====================================================================
-- TENANT B FIXTURE — the (π) tax-advantaged exclusion reaching NAV, and the
--   R9 zero clamp, live at the composer. THREE sequential states on one
--   account set: baseline (b_pi tax_deferred) -> reclassified (b_pi taxable,
--   the (π) move) -> clamped (a big loss added, R9).
-- =====================================================================
insert into pfin.tax_bracket_schedule (users_id, schedule_type, tax_year, standard_deduction, schedule_label)
  values (:'tb', 'federal_lt_cg', 2026, 0.0000, 'b-fedltcg-105') returning id as sch_fl \gset
insert into pfin.tax_bracket_row (users_id, schedule_id, bracket_floor, bracket_rate)
  values (:'tb', :sch_fl, 0, 0.05);
insert into pfin.tax_bracket_schedule (users_id, schedule_type, tax_year, standard_deduction, schedule_label)
  values (:'tb', 'california_ordinary', 2026, 0.0000, 'b-caord-105') returning id as sch_ca \gset
insert into pfin.tax_bracket_row (users_id, schedule_id, bracket_floor, bracket_rate)
  values (:'tb', :sch_ca, 0, 0.10);
-- top_rate sum = 0.05 + 0.10 = 0.15 (single bracket each -> top_rate == the
-- only rate, independent of any income -- 104's `walked` computes it off the
-- bracket set alone). No federal_ordinary schedule is seeded for B, so
-- federal never resolves and realized_tax_liab stays unavailable throughout
-- this fixture -- not this block's concern (covered by BOOT for the fully-
-- bootstrap case and by tenant A's BND block for the computed case).

insert into pfin.asset (users_id, asset_type, pricing_source, symbol, name)
  values (null, 'equity', 'market_feed', 'SEC105B', 'Sec 105B (self268)') returning asset_id as ast \gset
insert into pfin.eod_price (asset_id, price_date, source, price) values (:ast, '2026-06-01', 'market_feed', 150.0000);

-- b_gain (taxable): 10 shares x 150 = 1500 mv, cost_basis 1000 -> +500 gain.
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'tb', 'b-gain-105', 'investment', 'household', 'taxable') returning account_id as b_gain \gset
insert into pfin.account_trans (account_id, transaction_date, amount, quantity, security_id, cost_basis, transaction_type, vendor, created_at)
  values (:b_gain, '2026-01-05', -1000.0000, 10, :ast, 1000.0000, 'standard', 'buy-bgain-105', '2026-01-05'::timestamptz);

-- b_pi (STARTS tax_deferred): 20 shares x 150 = 3000 mv, cost_basis 1100 -> +1900 gain.
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'tb', 'b-pi-105', 'investment', 'household', 'tax_deferred') returning account_id as b_pi \gset
insert into pfin.account_trans (account_id, transaction_date, amount, quantity, security_id, cost_basis, transaction_type, vendor, created_at)
  values (:b_pi, '2026-01-05', -1100.0000, 20, :ast, 1100.0000, 'standard', 'buy-bpi-105', '2026-01-05'::timestamptz);

select _rls.set_tenant(:'tb'::uuid);

-- ---- PI-BASELINE: b_pi excluded (tax_deferred) -> taxable aggregate = 500
--   (b_gain only) -> unrealized = 0.15 x 500 = 75.00, UNCLAMPED (positive). --
select is(
  jsonb_build_object(
    'status', pfin.fn_nav_composition('2026-08-01'::date) -> 'buildups' -> 'unrealized_tax_liab' ->> 'status',
    'amount', ((pfin.fn_nav_composition('2026-08-01'::date) -> 'buildups' -> 'unrealized_tax_liab' ->> 'amount')::numeric)
  ),
  jsonb_build_object('status', 'computed', 'amount', 75.00::numeric),
  '(PI1) BASELINE (b_pi tax_deferred, EXCLUDED): unrealized_tax_liab = {computed, 75.00} = 0.15 x 500 (b_gain''s taxable +500 only — b_pi''s +1900 does NOT leak in)'
);
select pfin.fn_nav_composition('2026-08-01'::date) ->> 'nav' as nav_pi_baseline \gset

-- ---- PI-RECLASS: b_pi moved to taxable -> aggregate = 500+1900 = 2400 ->
--   unrealized = 0.15 x 2400 = 360.00 -- Δ = 285.00 = 0.15 x 1900 EXACTLY
--   (b_pi's own contribution x the combined top rate). ----------------------
select set_config('role', 'postgres', true);
update pfin.account set tax_treatment = 'taxable' where account_id = :b_pi;
select _rls.set_tenant(:'tb'::uuid);

select is(
  jsonb_build_object(
    'status', pfin.fn_nav_composition('2026-08-01'::date) -> 'buildups' -> 'unrealized_tax_liab' ->> 'status',
    'amount', ((pfin.fn_nav_composition('2026-08-01'::date) -> 'buildups' -> 'unrealized_tax_liab' ->> 'amount')::numeric)
  ),
  jsonb_build_object('status', 'computed', 'amount', 360.00::numeric),
  '(PI2) RECLASSIFIED (b_pi now taxable): unrealized_tax_liab = {computed, 360.00} = 0.15 x 2400 (b_gain 500 + b_pi 1900, now BOTH taxable) — moving the account MOVES the figure by exactly its own contribution (104''s own L12 pattern)'
);
select is(
  (pfin.fn_nav_composition('2026-08-01'::date) ->> 'nav')::numeric - :'nav_pi_baseline'::numeric,
  -285.00::numeric,
  '(PI3) the (π) EXCLUSION REACHES NAV: nav(reclassified) - nav(baseline) = -285.00 EXACTLY = -(360.00-75.00) — the inversion IS the fixture: PI1''s {computed,75.00} could not have hidden a leak (a leaked +1900 would already have made PI1 read 360.00), so this delta is the (π) exclusion''s effect on NAV itself, not merely on 104''s own internal figure'
);
-- (PI4) gross_total, by contrast, is UNAFFECTED by tax_treatment (it is a
--   PROPERTY of the account, not of the leaf set) -- both states carry every
--   account's market value regardless of taxable/tax_deferred.
select is(
  (pfin.fn_nav_composition('2026-08-01'::date) -> 'buildups' ->> 'gross_total')::numeric,
  2400.0000::numeric,
  '(PI4) gross_total = 2400.0000 (500 + 1900) in BOTH the baseline and reclassified states — tax_treatment gates the UNREALIZED aggregate only, never the leaf set itself'
);

-- ---- R9 CLAMP: a big loss added -> aggregate = 2400 - 18500 = -16100
--   (NEGATIVE) -> unrealized CLAMPS to 0, not the negative pre-clamp figure. -
select set_config('role', 'postgres', true);
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'tb', 'b-loss-105', 'investment', 'household', 'taxable') returning account_id as b_loss \gset
insert into pfin.account_trans (account_id, transaction_date, amount, quantity, security_id, cost_basis, transaction_type, vendor, created_at)
  values (:b_loss, '2026-01-05', -20000.0000, 10, :ast, 20000.0000, 'standard', 'buy-bloss-105', '2026-01-05'::timestamptz);
select _rls.set_tenant(:'tb'::uuid);

select ok(
  0.15 * (select coalesce(sum(g.unrealized_gl), 0) from pfin.fn_account_unrealized_gl('2026-08-01'::date) g
             join pfin.account a on a.account_id = g.account_id where a.tax_treatment = 'taxable') < 0,
  '(R9-pin) non-vacuous: the PRE-CLAMP figure (0.15 x the taxable aggregate, computed INDEPENDENTLY of 104/105) is genuinely NEGATIVE at this state (500+1900-18500 = -16100) — the clamp leg below is not exercising an already-nonnegative case'
);
select is(
  jsonb_build_object(
    'status', pfin.fn_nav_composition('2026-08-01'::date) -> 'buildups' -> 'unrealized_tax_liab' ->> 'status',
    'amount', ((pfin.fn_nav_composition('2026-08-01'::date) -> 'buildups' -> 'unrealized_tax_liab' ->> 'amount')::numeric)
  ),
  jsonb_build_object('status', 'computed', 'amount', 0::numeric),
  '(R9) unrealized_tax_liab = {computed, 0}, NOT the negative pre-clamp figure (R9-pin) — nav is NOT raised by an unrealized LOSS; the clamp is LIVE at the composer, not merely inside 104''s own internal figure (which 104''s own L11 already proves — this proves it reaches NAV through 105)'
);

select set_config('role', 'postgres', true);

-- =====================================================================
-- CROSS-TENANT — both rich fixtures (A's boundary-pair accounts, B's π/R9
--   accounts) coexist in this database; each tenant's tree carries ONLY its
--   own leaves.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
select is(
  (select count(*)::int
     from jsonb_array_elements(pfin.fn_nav_composition('2026-12-31'::date) -> 'groups') g,
          jsonb_array_elements(g -> 'accounts') acc
    where (acc->>'account_id')::bigint in (:b_gain, :b_pi, :b_loss)),
  0,
  '(X1) under tenant A''s RLS, fn_nav_composition''s leaf set contains NONE of tenant B''s three accounts (b_gain/b_pi/b_loss) — both tenants'' rich fixtures coexist in this database'
);
select set_config('role', 'postgres', true);
select _rls.set_tenant(:'tb'::uuid);
select is(
  (select count(*)::int
     from jsonb_array_elements(pfin.fn_nav_composition('2026-08-01'::date) -> 'groups') g,
          jsonb_array_elements(g -> 'accounts') acc
    where (acc->>'account_id')::bigint in (:a_dep, :acct_irs, :acct_ftb)),
  0,
  '(X2) under tenant B''s RLS, fn_nav_composition''s leaf set contains NONE of tenant A''s three accounts (a_dep/acct_irs/acct_ftb) — the reverse direction of X1'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- BOOTSTRAP / NEVER-NULL — tenant C: ZERO accounts, ZERO schedules, ZERO
--   ledgers. The state every user is in on day one (E26 ruling 1 / rider 0b).
-- =====================================================================
select _rls.set_tenant(:'tc'::uuid);
select ok(
  (pfin.fn_nav_composition('2026-08-01'::date) ->> 'nav') is not null,
  '(BOOT1) tenant C (zero accounts, zero schedules): nav IS NOT NULL — the bootstrap default subtracts coalesce(amount,0), it never propagates a JSON-null envelope into the headline'
);
select is(
  pfin.fn_nav_composition('2026-08-01'::date),
  '{"nav": 0, "groups": [], "buildups": {"debt": 0, "gross_total": 0, "total_non_re": 0, "realized_tax_liab": {"status":"unavailable","reason":"no_schedule_any_year"}, "unrealized_tax_liab": {"status":"unavailable","reason":"no_schedule_any_year"}}}'::jsonb,
  '(BOOT2) tenant C: the FULL payload — nav 0, empty groups[], BOTH tax keys the ENVELOPE OBJECT {unavailable, no_schedule_any_year} carried verbatim from 104 — never a coalesced 0::numeric literal, never an error, never a leak of tenant A''s or B''s figures'
);
select set_config('role', 'postgres', true);

select * from finish();
rollback;
