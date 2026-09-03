-- =====================================================================
-- SELF-257 — §2.3.5 RLS VERIFICATION BATTERY — V1.3 CLOSE-GATE.
--   ACs re-derived at the V1.3 pre-flight recalibration (2026-08-22);
--   docs/records/v13-preflight/rederived-acs.md §SELF-257, read live before
--   drafting. Mirrors self244_v12_close_gate.sql's shape (the explicit
--   precedent): SEAM-ONLY, authors NO schema. Proves the §2.3 read/write
--   surface holds closed AS A WHOLE, under ONE shared multi-tenant fixture,
--   exercised together — which no single per-migration battery does.
--   Composes already-green per-migration batteries for the deep per-function
--   proofs; adds only the NET-NEW seam + cross-cutting legs neither
--   per-migration battery makes on its own.
--
-- Ratified AC coverage (verbatim mapping to the re-derived list):
--   AC1 — every §2.3 backend surface (SELF-248/092, SELF-250+reader/093,
--         SELF-252/090, SELF-253/094, SELF-255/096) carries a SESSION-BASED
--         two-tenant leg: a cross-tenant caller under INVOKER+RLS sees ZERO
--         rows and fails closed (the SELF-244 precedent) — NOT parameter
--         injection (p_users_id was struck project-wide; there is no tenant
--         parameter anywhere in §2.3 to inject against). BLOCK ISO
--         re-derives this for the three functions that genuinely SHARE
--         substrate (093/094/096 all compose on the ONE reader) — the seam
--         self244's own header describes. 090 (039 legs, incl. R1/R2/W1/W2/
--         DEL1-3) and 092 (23 legs, incl. V4/D1-D3/CC1-2) already prove
--         session-based isolation exhaustively with ZERO cross-function
--         substrate to re-derive against — COMPOSED, not re-derived, with one
--         direct pin each in BLOCK AC8/AC10 below so this gate does not rest
--         on citation alone.
--   AC2 — 094's per-account drill-down cross-tenant p_account_id leg: 094's
--         OWN battery already proves this (EMPTY-3: A calling
--         fn_cashflow_per_account(B's account_id, d) gets the IDENTICAL
--         ordinary-empty document as an owned-but-empty account) — COMPOSED.
--         ⚠ The AC's literal text says "via RLS on pfin.account" — 094 never
--         reads pfin.account at all (its own header: "reads exactly one
--         relation" — the reader). The real mechanism, cross-checked against
--         099's own CC0/CC1 corrupt-the-control pair on the sibling
--         fn_cashflow_contributors, is that isolation here is entirely
--         INHERITED from account_trans_select's rd_access-JOIN: A's own item
--         set never contains B's account_id in the first place, so filtering
--         the reader's output to p_account_id=B's id yields the empty set
--         regardless of what id is named. BLOCK AC2 adds the adversarial
--         variant EMPTY-3 does not cover: the SAME foreign-account probe
--         under an EXTREME as_of (folds into RT-25 below).
--   AC3 — as-of VARIED ACROSS the tenant boundary (A and B queried at
--         DIFFERENT, even wildly mismatched, as_of values) must not widen the
--         fence. BLOCK RT25 (below) proves this together with the RT-25
--         adversarial-input booking, since both ask the identical question:
--         does ANY as_of value, however extreme or however mismatched
--         between callers, ever cause a cross-tenant leak at the DB layer.
--   AC4 — Lock 15 input validation is an APP-LAYER (Zod) fence at the route
--         handler — Backend's `.strict()` battery, no SQL surface, cited not
--         duplicated (D19 Option A: the DB itself has NO date-range CHECK by
--         design — RT-25 exists precisely because the DB layer must stay
--         safe with NO validation of its own). The DB-LAYER HALF this AC also
--         asks for — "both inclusive-boundary legs, exactly-floor and
--         exactly-D accepted" — IS this battery's job: BLOCK AC4 proves the
--         floor (2015-12-01) fresh; the exactly-D leg is already 093's own
--         L15a — COMPOSED.
--   AC5 — full-household default (NO scope filter) for SELF-250 (093's
--         rollup) and SELF-255 (096) — BLOCK AC5, a two-scope fixture on ONE
--         tenant, self244's D-block shape (§2.3 has no p_scope parameter to
--         omit — AC6 strikes the drafted one — so this proves the ABSENCE of
--         any scope predicate the same way self244 proved it for §2.2:
--         independently reconstruct the two-scope sum and tie it to the
--         function's own bare total).
--   AC6 — STRUCK at the pre-flight recalibration: the drafted
--         `p_scope = '{personal,trust}'::pfin.scope[]` leg is DROPPED, not
--         re-expressed — `pfin.scope` is not a type and does not exist, and
--         `pfin.account.scope` is free text with no V1 surface filtering on
--         it. No leg authored for this AC; recorded so a reader does not
--         infer an oversight.
--   AC7 — Sub-Cat forgery against pfin.posting_prototype: the #10/#13
--         matched-tenant fences were RE-TARGETED at 084 from pfin.user_taxonomy
--         to pfin.posting_prototype. ⚠ The AC's literal text claims the
--         re-target's consequence is that a sub_cat_id naming a storage-side
--         pfin.user_taxonomy id "now fails at the FOREIGN KEY (23503), never
--         reaching the trigger" — MEASURED FALSE (routed to Architect
--         2026-09-03, pending confirmation): BEFORE ROW triggers fire before
--         Postgres checks FK constraints, so the #10 matched-tenant trigger's
--         own EXISTS/JOIN check (false for ANY sub_cat_id with no matching
--         posting_prototype row — wrong table entirely or cross-tenant, it
--         cannot tell them apart) always intercepts first and raises ITS OWN
--         message; the FK is never reached for this failure mode. BLOCK AC7
--         asserts the MEASURED mechanism instead. Fresh SQL either way, not
--         covered anywhere else (084/092's own batteries forge OWNERSHIP,
--         never TABLE — this is the first leg naming the WRONG TABLE case).
--   AC8 — cashflow_target: tenant A cannot read/write tenant B's row; the
--         DELETE leg isolates the DELETE policy's OWN clause (090's
--         DEL1-DEL3, the corrupt-the-control pair AC8 literally describes,
--         verbatim) — 090's OWN battery (39 legs: S1-S6b/F1a-c/UQ1/N1-N6/
--         U1a-U2b/R1-R2/W1-W2/DEL1-DEL3/X1/M1-M8/G1) already proves this
--         exhaustively and cashflow_target shares NO substrate with any
--         other §2.3 function — COMPOSED, with one direct read-isolation pin
--         in BLOCK AC8 so the gate does not rest on citation alone.
--   AC9 — shared-reader rule legs (mechanical exclusion M1-M4+is_reverse,
--         split XOR both grains, reversal-nets-to-0-and-stays-there, the E3
--         deliberately-un-annotated fixture, ΣQ1..Q4=YTD, created-ON-D
--         inclusion — the D19 literal-predicate defect no value assertion
--         can catch) are tested EXACTLY ONCE already, in
--         093_fn_cashflow_items_and_rollup_rls.sql (R1-R5/N1/N3/N4/R4 for
--         exclusion+netting, R3a-c split XOR, E3a un-annotated, S3a-c
--         partition identity, L15a-c the half-open bound incl. created-within-
--         D) — verified against Architect (2026-09-03): 094/096 compose on
--         the reader with ZERO rule restatement, so "once here rather than
--         three times across the consumers" is ALREADY the state of the
--         tree, not a gap to close. COMPOSED, no new SQL for this AC.
--   AC10 — SELF-248 fence legs (both orders, lives_ok Transfer+Trade
--         controls, corrupt-the-control pair) — 092's OWN battery (23 legs:
--         D1a-D3b/CC1-2/NS1/CTRL1-2/L1-L2/M5/V1-V4) already proves this
--         exhaustively per Sec's condition 3 verbatim — COMPOSED, with one
--         direct pin in BLOCK AC10.
--   AC11 — Sec review pass. Procedural; no SQL. Draft-ready signal fires
--         when this file is green.
--   AC12 — forward fence: no service_role reach in any §2.3 surface, all
--         execute under authenticated per ARCH §4.1 — BLOCK AC12, a
--         declarative sweep over the 8 live callable §2.3 functions.
--   AC13 — pg_prove, never bare psql — procedural; this file's own
--         verification used pg_prove throughout (see hand-off report), never
--         psql alone.
--
--   RT-25 BOOKING (the issue's own comment, verbatim per team-lead's relay —
--   a poisoned-source warning): "RT-25's DB-layer adversarial as-of legs are
--   NOT discharged by the 253 PR and are owed here — crafted as_of values
--   under the two-tenant fixture must never return the other tenant's data
--   at the DB layer (the direct RPC bypasses the app-layer Zod boundary by
--   ruling, ADR-011 D19 Option A). MUST be authored from ADR-011 D19 AS
--   AMENDED (the half-open bound, created_at < D+1) — NOT from
--   docs/SECURITY/index.html:630, whose RT-25 acceptance text still carries
--   the retracted predicate until Sec's doc PR lands." D19 read VERBATIM
--   from DECISIONS.md before drafting (Amendment 2026-08-22 Edit 1 — the
--   dual-column filter's upper bound is HALF-OPEN,
--   transaction_date <= $1 AND created_at < ($1 + 1) — exactly what 093's
--   reader already implements, cross-checked, not assumed). BLOCK RT25 below.
--
-- ┌─ COMPOSE (verified green by the full suite; this file re-proves the ────┐
-- │ cross-cutting seam) — 090_cashflow_target_rls.sql (SELF-252, 39 legs) ·   │
-- │ 092_classify_journaled_cat_fence_rls.sql (SELF-248, 23 legs) ·            │
-- │ 093_fn_cashflow_items_and_rollup_rls.sql (SELF-250 + the shared reader,   │
-- │ 35 legs) · 094_fn_cashflow_per_account_rls.sql (SELF-253) ·               │
-- │ 096_fn_historical_expenditures_rls.sql (SELF-255, 36 legs). Plan counts   │
-- │ are a derived, unwatched property — read each file's own plan() line     │
-- │ live, never transcribe it here (Sec F3, self244 precedent).               │
-- └───────────────────────────────────────────────────────────────────────────┘
--
-- Ledgers all FLAT (SEAM-only, no schema authored): §10 catalogued-instance
--   ledger (ADR-011 Decision 4) and the SECURITY DEFINER allowlist (ADR-011
--   Decision 9) are both untouched — every function this file exercises is
--   INVOKER. Decision-3 family unchanged (no column authored). Read ADR-011
--   Decisions 4/9 live at point of use — this file moves no ledger and states
--   no count of its own.
--
-- POSTURE (SECURITY §4.5): SYNTHETIC ONLY — fixed-UUID tenants from
--   _rls.tenant_a()/_b()/_c(). NO PII / NO real account numbers / NO
--   production data. All seeds PRIVILEGED (role=postgres; RLS+ACL bypassed)
--   with users_id set EXPLICITLY (auth.uid() is NULL under postgres);
--   functions invoked ONLY under the authenticated tenant contexts under
--   test. All in a rolled-back txn.
--
-- Sec joint-review-mandatory — this issue IS the RLS surface; the Sec
--   verdict is AC11 itself, per the migration/issue's own gate.
-- =====================================================================

begin;

\ir ../_fixtures/rls_verbs.psql

-- plan = 31: ISO 12 (3 functions x 4 legs: own-value / non-vacuity / cross-
--   tenant-probe / empty-tenant-closed) + RT25/AC3/AC2-adversarial 6
--   (RT25-1 ancient, RT25-2/3 far-future both tenants, RT25-4a/4b mismatched
--   as_of the AC3 proper leg, RT25-5 the AC2 adversarial foreign-account+
--   extreme-as_of combination) + AC4 2 (exactly-floor inclusion + non-
--   vacuity companion) + AC5 4 (two-scope sum on 093's rollup + 096, each
--   with a single-scope companion) + AC7 2 (forgery rejection + non-
--   vacuous control) + AC8 2 (direct read-isolation pin) + AC10 1 (direct
--   enabled-trigger pin) + AC12 2 (service_role sweep + non-vacuous
--   function-count companion) = 31. Recorded so a silent plan-edit shows as
--   an arithmetic change. (AC2's PRIMARY leg is ISO-094b, already counted in
--   ISO's 12 — RT25-5 is its adversarial VARIANT, not a second primary leg,
--   which is why AC2 has no separate line item here.)
select plan(31);

select _rls.tenant_a() as ta, _rls.tenant_b() as tb, _rls.tenant_c() as tc \gset

insert into auth.users (id) values (:'ta'), (:'tb'), (:'tc');

-- =====================================================================
-- FIXTURE — TENANT A: two accounts in DIFFERENT scopes (a_pers/personal,
--   a_trust/trust) both classified into the SAME Sub-Cat (Groceries257) —
--   AC5's two-scope full-household proof. a_floor carries the AC4
--   exactly-floor item. a_fkprobe is a fresh unclassified item for AC7.
--   TENANT B: one account (b_acc), its own classified activity — the
--   isolation referent throughout. TENANT C: zero accounts — fail-closed
--   control.
-- =====================================================================
insert into pfin.posting_prototype (users_id, cat, sub_cat, is_tax_payment) values
  (:'ta', 'Expense', 'Groceries257', false) returning id as a_groceries \gset
insert into pfin.posting_prototype (users_id, cat, sub_cat, is_tax_payment) values
  (:'ta', 'Expense', 'FloorLeg257', false) returning id as a_floorcat \gset
insert into pfin.user_taxonomy (users_id, cat, sub_cat, element) values
  (:'ta', 'Marketable Securities', 'US-06-Financials257', 'asset') returning id as a_usertax \gset

insert into pfin.posting_prototype (users_id, cat, sub_cat, is_tax_payment) values
  (:'tb', 'Expense', 'BStuff257', false) returning id as b_exp \gset

insert into pfin.account (users_id, name, account_type, scope, tax_treatment) values
  (:'ta', 'a-pers-257', 'depository', 'personal', 'taxable') returning account_id as a_pers \gset
insert into pfin.account (users_id, name, account_type, scope, tax_treatment) values
  (:'ta', 'a-trust-257', 'depository', 'trust', 'taxable') returning account_id as a_trust \gset
insert into pfin.account (users_id, name, account_type, scope, tax_treatment) values
  (:'tb', 'b-acc-257', 'depository', 'household', 'taxable') returning account_id as b_acc \gset

-- A's activity, dated within 2026 (the ISO/AC2/RT25/AC3 as_of D = 2026-06-15).
-- ⚠ FIXTURE-CLOCK TRAP (standing trap, named in the dispatch): reader rule 6
--   is `created_at < (p_as_of + 1)`, and created_at DEFAULTS to the real
--   wall-clock now() on INSERT — NOT to transaction_date. Every row below
--   pins created_at EXPLICITLY to a value on/before its own transaction_date,
--   so every leg's expected result is independent of whenever this battery
--   is actually run (never relying on "today" being after 2026-06-15).
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, created_at) values
  (:a_pers, '2026-06-01', -50, 'vGroceriesPers', '257 personal-scope groceries leg', '2026-06-01T00:00:00Z')
  returning trans_id as t_pers \gset
insert into pfin.account_trans_annotation (trans_id, sub_cat_id) values (:t_pers, :a_groceries);

insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, created_at) values
  (:a_trust, '2026-06-05', -30, 'vGroceriesTrust', '257 trust-scope groceries leg, SAME Sub-Cat as a_pers', '2026-06-05T00:00:00Z')
  returning trans_id as t_trust \gset
insert into pfin.account_trans_annotation (trans_id, sub_cat_id) values (:t_trust, :a_groceries);

-- AC4 exactly-floor leg: dated EXACTLY the D19 Zod floor (2015-12-01).
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, created_at) values
  (:a_pers, '2015-12-01', -10, 'vFloor', '257 AC4 exactly-floor item', '2015-12-01T00:00:00Z')
  returning trans_id as t_floor \gset
insert into pfin.account_trans_annotation (trans_id, sub_cat_id) values (:t_floor, :a_floorcat);

-- AC7 probe leg: fresh, UNCLASSIFIED (no annotation yet — the forgery attempt below is the FIRST write).
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, created_at) values
  (:a_pers, '2026-07-01', -5, 'vFkProbe', '257 AC7 FK-forgery probe, pre-annotation', '2026-07-01T00:00:00Z')
  returning trans_id as t_fkprobe \gset

-- B's activity (isolation referent).
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, created_at) values
  (:b_acc, '2026-06-01', -25, 'vB', '257 tenant-B own classified item', '2026-06-01T00:00:00Z')
  returning trans_id as t_b \gset
insert into pfin.account_trans_annotation (trans_id, sub_cat_id) values (:t_b, :b_exp);

\set d_asof '2026-06-15'
-- ⚠ fn_historical_expenditures (096) excludes the CURRENT INCOMPLETE month
--   relative to its OWN p_as_of (096's own "no-leading-pad" window — the
--   grid anchors on the last COMPLETE month, ms_last). d_asof (mid-June)
--   would make June itself the excluded current-incomplete month, so every
--   096 leg below uses a LATER as_of (d_asof_096, mid-JULY) instead, at
--   which June is a genuine COMPLETE prior month and t_pers/t_trust's June
--   activity is included. 093/094/092/090 are unaffected by this window
--   rule (it is 096's own, not the shared reader's) and keep using d_asof.
\set d_asof_096 '2026-07-15'

-- =====================================================================
-- BLOCK ISO — AC1: session-based two-tenant isolation, re-derived TOGETHER
--   on the shared fixture (the seam self244's own header describes) for the
--   three functions that genuinely compose on ONE substrate: 093's reader
--   (via the rollup), 094's drill-down, 096's historical-expenditures.
--   Each: (a) A's own value is non-vacuous, (b) B sees NONE of A's data,
--   (c) A sees NONE of B's data, (d) C (zero accounts) fails closed.
-- =====================================================================

-- --- ISO-093: fn_cashflow_cross_account_rollup ---
select _rls.set_tenant(:'ta'::uuid);
select is(
  (select (row ->> 'ytd')::numeric
     from jsonb_array_elements(pfin.fn_cashflow_cross_account_rollup(:'d_asof'::date) -> 'sections') s,
          jsonb_array_elements(s -> 'rows') row
    where row ->> 'sub_cat' = 'Groceries257'),
  80.00::numeric,
  '(ISO-093a) AC1 non-vacuous: A''s Groceries257 rollup total reflects ONLY A''s own two accounts (outflow-positive display convention: raw sum -80 displays as +80)'
);
select set_config('role', 'postgres', true);
select _rls.set_tenant(:'tb'::uuid);
select is(
  (select count(*) from jsonb_array_elements(pfin.fn_cashflow_cross_account_rollup(:'d_asof'::date) -> 'sections') s,
                        jsonb_array_elements(s -> 'rows') row
    where row ->> 'sub_cat' = 'Groceries257'),
  0::bigint,
  '(ISO-093b) AC1 cross-tenant fails closed: B''s rollup carries NO Groceries257 row at all — A''s Sub-Cat name never leaks even as an empty-valued row'
);
select set_config('role', 'postgres', true);
select _rls.set_tenant(:'ta'::uuid);
select is(
  (select count(*) from jsonb_array_elements(pfin.fn_cashflow_cross_account_rollup(:'d_asof'::date) -> 'sections') s,
                        jsonb_array_elements(s -> 'rows') row
    where row ->> 'sub_cat' = 'BStuff257'),
  0::bigint,
  '(ISO-093c) AC1 cross-tenant fails closed (reverse): A''s rollup carries NO BStuff257 row (B''s own Sub-Cat)'
);
select set_config('role', 'postgres', true);
select _rls.set_tenant(:'tc'::uuid);
select is(
  (select count(*) from jsonb_array_elements(pfin.fn_cashflow_cross_account_rollup(:'d_asof'::date) -> 'sections') s,
                        jsonb_array_elements(s -> 'rows') row),
  0::bigint,
  '(ISO-093d) AC1 empty-tenant fails closed: C (zero accounts) gets zero Sub-Cat rows across both sections'
);
select set_config('role', 'postgres', true);

-- --- ISO-094: fn_cashflow_per_account (A's own account) ---
select _rls.set_tenant(:'ta'::uuid);
select is(
  (select (row ->> 'ytd')::numeric
     from jsonb_array_elements(pfin.fn_cashflow_per_account(:a_pers, :'d_asof'::date) -> 'sections') s,
          jsonb_array_elements(s -> 'rows') row
    where row ->> 'sub_cat' = 'Groceries257'),
  50.00::numeric,
  '(ISO-094a) AC1 non-vacuous: A''s own drill-down (a_pers) reflects ONLY a_pers''s 50, not a_trust''s 30 (outflow-positive display convention)'
);
select is(
  (select count(*) from jsonb_array_elements(pfin.fn_cashflow_per_account(:b_acc, :'d_asof'::date) -> 'sections') s,
                        jsonb_array_elements(s -> 'rows') row),
  0::bigint,
  '(ISO-094b) AC2/AC1 cross-tenant fails closed: A passing B''s account_id (b_acc) gets the ordinary EMPTY document — zero rows in every section (094''s own EMPTY-3 shape, re-derived on this gate''s fixture)'
);
select set_config('role', 'postgres', true);
select _rls.set_tenant(:'tb'::uuid);
select is(
  (select count(*) from jsonb_array_elements(pfin.fn_cashflow_per_account(:a_pers, :'d_asof'::date) -> 'sections') s,
                        jsonb_array_elements(s -> 'rows') row),
  0::bigint,
  '(ISO-094c) AC1 cross-tenant fails closed (reverse): B passing A''s account_id (a_pers) ALSO gets the empty document'
);
select set_config('role', 'postgres', true);
select _rls.set_tenant(:'tc'::uuid);
select is(
  (select count(*) from jsonb_array_elements(pfin.fn_cashflow_per_account(:a_pers, :'d_asof'::date) -> 'sections') s,
                        jsonb_array_elements(s -> 'rows') row),
  0::bigint,
  '(ISO-094d) AC1 empty-tenant fails closed: C passing A''s REAL account_id still gets the empty document — RLS, not application logic, confines the read'
);
select set_config('role', 'postgres', true);

-- --- ISO-096: fn_historical_expenditures ---
select _rls.set_tenant(:'ta'::uuid);
select is(
  (select expense_monthly_nominal from pfin.fn_historical_expenditures(:'d_asof_096'::date)
    where date_trunc('month', month_end) = '2026-06-01'::date),
  80.00::numeric,
  '(ISO-096a) AC1/AC5 non-vacuous: A''s June-2026 expense total is 80.00 (50+30 across BOTH scoped accounts) — reflects ONLY A''s own activity'
);
select set_config('role', 'postgres', true);
select _rls.set_tenant(:'tb'::uuid);
select is(
  (select expense_monthly_nominal from pfin.fn_historical_expenditures(:'d_asof_096'::date)
    where date_trunc('month', month_end) = '2026-06-01'::date),
  25.00::numeric,
  '(ISO-096b) AC1 non-vacuity companion: the IDENTICAL as_of under tenant B returns 25.00 (B''s own single item), not 80.00'
);
select set_config('role', 'postgres', true);
select _rls.set_tenant(:'ta'::uuid);
select isnt(
  (select expense_monthly_nominal from pfin.fn_historical_expenditures(:'d_asof_096'::date)
    where date_trunc('month', month_end) = '2026-06-01'::date),
  25.00::numeric,
  '(ISO-096c) AC1 cross-tenant fails closed: A''s June total is NOT B''s value (25.00) — no cross-tenant contamination of the same month'
);
select set_config('role', 'postgres', true);
select _rls.set_tenant(:'tc'::uuid);
select is(
  (select count(*) from pfin.fn_historical_expenditures(:'d_asof_096'::date) where expense_monthly_nominal <> 0),
  0::bigint,
  '(ISO-096d) AC1 empty-tenant fails closed: C has zero non-zero expense months across the entire 60-month series'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK RT25/AC3 — as-of VARIED ACROSS the tenant boundary, incl. ADVERSARIAL
--   extremes, at the DB layer (RT-25: the direct RPC bypasses the app-layer
--   Zod boundary by ruling, D19 Option A — the DB has NO date-range CHECK of
--   its own, so isolation must hold for ANY value, not just the app-validated
--   range). Uses fn_cashflow_cross_account_rollup as the reader-composed
--   surface; the mechanism is identical across every §2.3 reader-composed
--   function (isolation is entirely account_trans_select-inherited, never
--   as_of-conditioned).
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
-- (RT25-1) ancient as_of (before every seeded row, in ANY tenant's data):
--   the ordinary EMPTY answer, never an error, never a foreign row.
select is(
  (select count(*) from jsonb_array_elements(pfin.fn_cashflow_cross_account_rollup('0001-01-01'::date) -> 'sections') s,
                        jsonb_array_elements(s -> 'rows') row),
  0::bigint,
  '(RT25-1) adversarial as_of (year 1, centuries before any data): A''s rollup returns the ordinary EMPTY set, no error'
);
-- (RT25-2) far-future as_of (year 9999): the reader scopes to the SAME
--   calendar year as p_as_of (rule 5), so NEITHER tenant's real 2026 data
--   can appear at this as_of BY CONSTRUCTION — the meaningful adversarial
--   proof is that this does not error and does not admit ANYTHING (not "A
--   sees only its own", which is impossible here since even A's own 2026
--   data is out of THIS year's window): the ordinary EMPTY SET, same shape
--   as RT25-1, from the opposite extreme.
select is(
  (select count(*) from jsonb_array_elements(pfin.fn_cashflow_cross_account_rollup('9999-12-31'::date) -> 'sections') s,
                        jsonb_array_elements(s -> 'rows') row),
  0::bigint,
  '(RT25-2) adversarial as_of (far future, year 9999): A''s rollup is the ordinary EMPTY set (2026 data is out of year 9999''s window by construction) — no error, no unexpected inclusion of ANY data'
);
select set_config('role', 'postgres', true);
-- (RT25-3) the IDENTICAL extreme as_of under tenant B: ALSO the ordinary
--   empty set — a shared wide as_of between two sessions does not admit
--   either tenant's data, let alone create a union-like cross-tenant leak.
select _rls.set_tenant(:'tb'::uuid);
select is(
  (select count(*) from jsonb_array_elements(pfin.fn_cashflow_cross_account_rollup('9999-12-31'::date) -> 'sections') s,
                        jsonb_array_elements(s -> 'rows') row),
  0::bigint,
  '(RT25-3) the IDENTICAL extreme as_of (9999-12-31) under tenant B: ALSO the ordinary EMPTY set — the shared adversarial value admits neither tenant''s data'
);
select set_config('role', 'postgres', true);
-- (RT25-4/AC3) MISMATCHED as_of across the boundary: A queried at its OWN
--   real as_of (D) while B is queried at a COMPLETELY DIFFERENT, unrelated
--   as_of — neither sees the other's data under either date.
select _rls.set_tenant(:'ta'::uuid);
select ok(
  not exists (select 1 from jsonb_array_elements(pfin.fn_cashflow_cross_account_rollup(:'d_asof'::date) -> 'sections') s,
                          jsonb_array_elements(s -> 'rows') row
               where row ->> 'sub_cat' = 'BStuff257'),
  '(RT25-4a) AC3: A at its OWN as_of (D=2026-06-15) sees no trace of B''s BStuff257, regardless of what as_of B itself might use'
);
select set_config('role', 'postgres', true);
select _rls.set_tenant(:'tb'::uuid);
select ok(
  not exists (select 1 from jsonb_array_elements(pfin.fn_cashflow_cross_account_rollup('2030-01-01'::date) -> 'sections') s,
                          jsonb_array_elements(s -> 'rows') row
               where row ->> 'sub_cat' = 'Groceries257'),
  '(RT25-4b) AC3: B at a DIFFERENT as_of (2030-01-01, unrelated to A''s D) sees no trace of A''s Groceries257 — mismatched as_of values across tenants do not cross-contaminate'
);
select set_config('role', 'postgres', true);
-- (RT25-5) AC2 adversarial variant: A's foreign-account probe (094, b_acc)
--   under the SAME far-future adversarial as_of used in RT25-2 — still empty.
select _rls.set_tenant(:'ta'::uuid);
select is(
  (select count(*) from jsonb_array_elements(pfin.fn_cashflow_per_account(:b_acc, '9999-12-31'::date) -> 'sections') s,
                        jsonb_array_elements(s -> 'rows') row),
  0::bigint,
  '(RT25-5/AC2) adversarial: A passing B''s account_id (b_acc) AND an extreme as_of (9999-12-31) together — still the ordinary empty document, not an error and not a leak'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK AC4 — DB-layer inclusive-boundary: EXACTLY the D19 Zod floor
--   (2015-12-01) is INCLUDED when p_as_of = the SAME floor date. (The
--   exactly-D leg is already 093's own L15a — COMPOSED, not re-derived.)
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
select ok(
  exists (select 1 from jsonb_array_elements(pfin.fn_cashflow_cross_account_rollup('2015-12-01'::date) -> 'sections') s,
                       jsonb_array_elements(s -> 'rows') row
           where row ->> 'sub_cat' = 'FloorLeg257'),
  '(AC4-1) DB-layer inclusive boundary: an item dated EXACTLY the D19 floor (2015-12-01), queried at p_as_of=2015-12-01, IS INCLUDED — the DB has no redundant floor check of its own that could reject its own boundary'
);
select is(
  (select (row ->> 'ytd')::numeric
     from jsonb_array_elements(pfin.fn_cashflow_cross_account_rollup('2015-12-01'::date) -> 'sections') s,
          jsonb_array_elements(s -> 'rows') row
    where row ->> 'sub_cat' = 'FloorLeg257'),
  10.00::numeric,
  '(AC4-2) non-vacuous companion: the floor-date row carries its REAL value (10.00, outflow-positive), not a phantom zero row'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK AC5 — full-household default (NO scope filter): the two-scope sum
--   independently reconstructed from the substrate, tied back to the
--   function's own bare total (self244's D-block discipline).
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
select is(
  (select (row ->> 'ytd')::numeric
     from jsonb_array_elements(pfin.fn_cashflow_cross_account_rollup(:'d_asof'::date) -> 'sections') s,
          jsonb_array_elements(s -> 'rows') row
    where row ->> 'sub_cat' = 'Groceries257'),
  (select -1 * sum(t.amount)
     from pfin.account_trans t
     join pfin.account a on a.account_id = t.account_id
    where a.users_id = :'ta' and a.scope in ('personal', 'trust')
      and t.trans_id in (:t_pers, :t_trust)),
  '(AC5-1) SELF-250 full-household: fn_cashflow_cross_account_rollup''s bare Groceries257 total EQUALS the independently-reconstructed SQL-layer sum across BOTH distinct scopes (personal + trust) — full-household is the DEFAULT, not a coincidence of an absent filter'
);
select is(
  (select -1 * sum(t.amount) from pfin.account_trans t where t.trans_id = :t_pers),
  50.00::numeric,
  '(AC5-2) companion: the personal-scope leg ALONE is 50.00 — (AC5-1)''s 80.00 total genuinely sums two distinct scopes, not one scope''s value read twice'
);
select set_config('role', 'postgres', true);

-- AC5, SELF-255 (096) — same two-scope fixture, same discipline.
select _rls.set_tenant(:'ta'::uuid);
select is(
  (select expense_monthly_nominal from pfin.fn_historical_expenditures(:'d_asof_096'::date)
    where date_trunc('month', month_end) = '2026-06-01'::date),
  (select sum(t.amount) * -1
     from pfin.account_trans t
     join pfin.account a on a.account_id = t.account_id
    where a.users_id = :'ta' and a.scope in ('personal', 'trust')
      and t.trans_id in (:t_pers, :t_trust)),
  '(AC5-3) SELF-255 full-household: fn_historical_expenditures'' June-2026 total EQUALS the independently-reconstructed two-scope sum — same full-household default holds on the sibling surface'
);
select is(
  (select -1 * sum(t.amount) from pfin.account_trans t where t.trans_id = :t_trust),
  30.00::numeric,
  '(AC5-4) companion: the trust-scope leg ALONE is 30.00 — (AC5-3)''s 80.00 genuinely sums two distinct scopes'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK AC7 — Sub-Cat forgery against pfin.posting_prototype: a sub_cat_id
--   naming a REAL, storage-side pfin.user_taxonomy id now fails at the FK
--   (23503), never reaching the #10 trigger — the re-target's own
--   consequence (084). posting_prototype's id-space starts at 1000000000;
--   user_taxonomy's starts at 1 — the two spaces cannot collide, so this is
--   a genuine FK-shape failure, not an accidental valid reference.
-- =====================================================================
-- ⚠ MEASURED, corrected from the AC's literal wording (routed to Architect
-- 2026-09-03, pending confirmation): "fails at the FK, not the trigger" does
-- NOT hold as literally stated. BEFORE ROW triggers fire before Postgres
-- checks FK constraints, so the #10 matched-tenant trigger's own EXISTS/JOIN
-- check — which returns false (and raises ITS OWN message) for ANY
-- sub_cat_id with no matching posting_prototype row, whether that id doesn't
-- exist at all, lives in a different table's id-space, or is cross-tenant —
-- always intercepts first. The FK is never reached for this failure mode.
-- This leg asserts the MEASURED mechanism (the #10 trigger's own rejection),
-- not the AC's literal FK claim, pending Architect's confirmation.
select _rls.set_tenant(:'ta'::uuid);
savepoint sp_ac7;
select throws_like(
  format($$ insert into pfin.account_trans_annotation (trans_id, sub_cat_id) values (%s, %s) $$, :t_fkprobe, :a_usertax),
  '%is not a posting prototype owned by and visible to the tenant of trans_id%',
  '(AC7-1) Sub-Cat forgery against the RE-TARGETED reference: a sub_cat_id naming a REAL storage-side pfin.user_taxonomy id (a_usertax, wrong table entirely post-084''s re-target) is REJECTED — MEASURED mechanism is the #10 matched-tenant trigger''s own rejection (BEFORE ROW fires before the FK constraint is ever checked), not a bare 23503 as the AC''s literal text describes; either way the write fails closed'
);
rollback to savepoint sp_ac7;
-- (AC7-2) non-vacuous control: the SAME trans_id classified with a REAL
--   posting_prototype id (own tenant) COMMITS — proving (AC7-1) is the
--   FK's own discriminator, not a blanket write-block on t_fkprobe.
savepoint sp_ac7b;
select lives_ok(
  format($$ insert into pfin.account_trans_annotation (trans_id, sub_cat_id) values (%s, %s) $$, :t_fkprobe, :a_groceries),
  '(AC7-2) non-vacuous control: the SAME trans_id (t_fkprobe) classified with a REAL posting_prototype id (a_groceries, own tenant) COMMITS — (AC7-1)''s rejection is FK-shape-driven, not a block on the row itself'
);
rollback to savepoint sp_ac7b;
select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK AC8 — cashflow_target: one direct read-isolation pin under THIS
--   gate's own fixture (090's OWN 39-leg battery — S1-S6b/F1a-c/UQ1/N1-N6/
--   U1a-U2b/R1-R2/W1-W2/DEL1-DEL3/X1/M1-M8/G1 — is COMPOSED, not
--   re-derived; cashflow_target shares no substrate with any other §2.3
--   function, so there is no seam interaction to prove beyond this pin).
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
insert into pfin.cashflow_target (income_target_annual) values (72000.00);
select is(
  (select income_target_annual from pfin.cashflow_target where users_id = auth.uid()),
  72000.00::numeric,
  '(AC8-1) AC8 direct pin: A reads its own cashflow_target row on THIS gate''s fixture'
);
select set_config('role', 'postgres', true);
select _rls.set_tenant(:'tb'::uuid);
select is(
  (select count(*) from pfin.cashflow_target where users_id = :'ta'),
  0::bigint,
  '(AC8-2) AC8 direct pin: B''s call for A''s cashflow_target row (by users_id) resolves to ZERO rows — cross-tenant fails closed on this gate''s own fixture (090''s DEL1-DEL3 is the exhaustive DELETE-policy-isolation proof, composed not repeated here)'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK AC10 — SELF-248 fence: one direct existence/enabled pin under this
--   gate's own posting_prototype fixture (092's OWN 23-leg battery —
--   D1a-D3b/CC1-2/NS1/CTRL1-2/L1-L2/M5/V1-V4, Sec's condition-3 both-orders
--   + lives_ok controls + corrupt-the-control pair — is COMPOSED, not
--   re-derived).
-- =====================================================================
select ok(
  (select tgenabled = 'O' from pg_trigger
    where tgname = 'account_trans_annotation_journaled_cat_fence'
      and tgrelid = 'pfin.account_trans_annotation'::regclass),
  '(AC10-1) AC10 direct pin: the SELF-248 M3 journaled-cat fence trigger exists and is ENABLED on THIS gate''s own account_trans_annotation table — 092''s own battery is the exhaustive both-orders/controls/corrupt-the-control proof, composed not repeated here'
);

-- =====================================================================
-- BLOCK AC12 — forward fence: NO §2.3 function is reachable by service_role;
--   every one executes under authenticated only (ARCH §4.1).
-- =====================================================================
select is(
  (select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'pfin'
       and p.proname in ('fn_cashflow_items', 'fn_cashflow_cross_account_rollup',
                          'fn_cashflow_per_account', 'fn_historical_expenditures',
                          'fn_expenditure_window', 'fn_expenditures_unclassified_count',
                          'fn_cashflow_contributors', 'fn_suggest_subcat_for_vendor')),
  8,
  '(AC12-1) non-vacuous companion: the 8-name §2.3 function IN-list resolves to EXACTLY 8 live pfin functions — the sweep below is not silently narrowed by a typo''d name'
);
select ok(
  (select bool_and(not has_function_privilege('service_role', p.oid, 'execute'))
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'pfin'
      and p.proname in ('fn_cashflow_items', 'fn_cashflow_cross_account_rollup',
                         'fn_cashflow_per_account', 'fn_historical_expenditures',
                         'fn_expenditure_window', 'fn_expenditures_unclassified_count',
                         'fn_cashflow_contributors', 'fn_suggest_subcat_for_vendor')),
  '(AC12-2) forward fence: NONE of the 8 live §2.3 functions grant EXECUTE to service_role — every one is reachable ONLY under authenticated, per ARCH §4.1'
);

select * from finish();
rollback;
