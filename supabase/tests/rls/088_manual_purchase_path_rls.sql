-- =====================================================================
-- Per-Wave battery — pfin.fn_create_manual_purchase (SELF-325 remaining scope —
--   the manual instrument-PURCHASE write path; V1-SHIP-BLOCK)
-- =====================================================================
-- BINDS TO MIGRATION: supabase/migrations/088_manual_purchase_path.sql
--   (verified against d141fed9e043c8956f1a40a437e43922cb7fb409,
--   feature/manual-purchase-path — the branch state this battery was verified
--   against, NOT this file's own commit: a file cannot name the commit that
--   contains it, so this locator is necessarily one commit behind whatever
--   lands it. RE-FROZEN per Architect; this is the re-point itself).
--   blob md5 fea8cdc3862e6cb9b8b3231a1f82e3b4 — the MIGRATION-IDENTITY pin.
--   ⚠ AN EARLIER REVISION OF THIS LINE CALLED b343304f3dde40eeab84a85e21c615bb
--   "FINAL per Architect" (a713c32), reasoning that 088's body had last changed
--   at e29b00f and nothing outstanding touched it again. THAT WAS WRONG, and
--   the wrongness was structural, not a measurement error: "final" was true of
--   088 read in isolation, and stopped being true the moment Sec's F1 fix
--   (089, fn_asset_priced_flags) replaced 088's inline `priced` block with a
--   call to it — a real body change, the first since ad7f2a1. A migration's
--   identity is only "final" relative to a stated set of outstanding work, and
--   that set can grow. Verified against the committed object, not the source
--   text — re-pulled and re-diffed after 8fa6526 superseded
--   ad7f2a1a2f9b9b680cec24ca55e71d7f06c77b2c (kept below as historical
--   provenance, NOT updated by this pin), and again after the 089 extraction
--   moved the blob to fea8cdc3. Every behavioural leg below was RE-RUN — not
--   re-verified as comment-only — against this revision (see the L3/priced
--   legs' own note) and held unchanged) —
--   pfin.fn_create_manual_purchase(p_account_id bigint, p_trade_date date,
--     p_quantity numeric, p_cost_basis numeric, p_security_id bigint default null,
--     p_asset_type text default null, p_asset_name text default null,
--     p_symbol text default null, p_sub_cat_id bigint default null,
--     p_description text default null, p_note text default null)
--     RETURNS (trans_id bigint, security_id bigint, priced boolean, price numeric)
--     SECURITY INVOKER, set search_path = ''. IN-arg identity for regprocedure /
--     has_function_privilege (OUT params are NOT part of the identity list):
--     (bigint, date, numeric, numeric, bigint, text, text, text, bigint, text, text).
-- Prereqs exercised (all on this branch): 003 (account + creator-grant; account_select
--   using (users_id = auth.uid()) — NO sharing in V1, account_users is dormant), 004
--   (immutable ledger), 006 (account_trans rd/wr_access-JOIN RLS), 015
--   (account.currency + linked_source_id), 016 (pfin.asset hybrid registry,
--   asset_select global-OR-owned), 017 (account_trans investment cols + the #7
--   fn_account_trans_security_asset fence + NaN/finite CHECKs +
--   numeric(28,8)/numeric(20,4) column grains), 019 (eod_price unique
--   (asset_id,price_date,source) + manual_valuation-on-owned write policy), 023
--   (account_trans_annotation + matched-tenant fence), 030 (the 'standard' vocab +
--   Trade biconditional), 039 (source-of-truth guard precedent), 040 (the sibling
--   cash-entry RPC this migration does NOT touch), 078 (the D-FIRST price pick this
--   file asserts the FORCED answer of, never re-derives), 084 (the P1/P2/P10 GL
--   branch set this row shape is written for), 087 (the create-time sibling; the
--   structural-vs-behavioural #7 distinction this file corrects).
-- Reuses the SELF-187.. idiom: \ir verbs, ALL-LOWERCASE \gset literals, role
--   restored to postgres between blocks (PR #121 root-cause).
--
-- ┌─ WHAT THIS BATTERY PROVES ─────────────────────────────────────────────────┐
-- │ L1 auth + two-tenant isolation + the Decision-3 #7 finding — the migration's  │
-- │   header agreed with an earlier draft's overclaim and now agrees with this   │
-- │   file (8fa6526 corrected it). MEASURED (scratch-DB probe, not derived): a   │
-- │   caller submitting another tenant's private asset_id is rejected by GUARD   │
-- │   (9) — 'security_id % is not a global or caller-owned asset' — and NEVER    │
-- │   reaches the #7 trigger. This is NOT a vacuity in the test; it is       │
-- │   structural in V1: account_select is `users_id = auth.uid()` with no        │
-- │   sharing (account_users is V1-dormant, creator-grant-only), so whoever can   │
-- │   even resolve p_account_id at (2) IS that account's tenant — making guard  │
-- │   (9)'s asset-visibility read and #7's JOIN predicate test the IDENTICAL     │
-- │   fact. #7 cannot independently fail through this RPC for the same         │
-- │   structural reason 087 gives for why it cannot fail there — reached via a  │
-- │   different route (a caller-supplied but RLS-invisible id, not a minted     │
-- │   one). #7's own real behavioural proof lives in 017_account_trans_investment │
-- │   _rls.sql (the raw-INSERT / service_role path it actually gates); this file  │
-- │   asserts #7 stays STRUCTURALLY bound (087's pattern) and that guard (9) is   │
-- │   the actual, live, behaviourally-reachable mechanism on THIS RPC — labelled  │
-- │   so neither is mistaken for the other.                                      │
-- │ L2 PROVENANCE: the 084 P1+P2+P10 row shape, GL-verified (fn_gl_entries),      │
-- │   never a Suspense or Opening-Balance-Equity plug row; fn_create_manual_trans │
-- │   (040) is a REGRESSION check — untouched, still cash-only.                  │
-- │ L3 the three-branch price companion, asserted as POST-CONDITIONS over the    │
-- │   picked price (a 0.0000 row would satisfy mere existence) — branch (a)      │
-- │   writes and its row IS the pick's forced answer (max date + top source      │
-- │   rank, asserted directly, no re-derived rank CASE); branch (b) SKIPS and    │
-- │   the pre-existing price stays byte-unchanged (the F4 retroactive-           │
-- │   revaluation fence — buying more must not restate a prior lot), while the   │
-- │   RETURNED `price` still reports the new call's own derived ratio, not the   │
-- │   pre-existing one — a real, easy-to-invert distinction, pinned explicitly;  │
-- │   branch (c) never writes and the position may be legitimately unpriced.     │
-- │   The zero-price floor (guard 8) is proven UNCONDITIONAL — it fires on the   │
-- │   no-write global branch too — and guard (12) proves the skip is watched:    │
-- │   a pre-existing WORTHLESS price refuses the purchase rather than silently   │
-- │   accepting it.                                                              │
-- │ L4 Lock 14: the RATIO surface (quantity 1,000,000 / cost_basis 10.00, no      │
-- │   single variable extreme) plus the magnitude matrix — direct-numeric NaN /  │
-- │   Infinity (reachable here, unlike 087's jsonb path), zero/negative, and the  │
-- │   two DISTINCT column-overflow ceilings (cost_basis numeric(20,4), quantity   │
-- │   numeric(28,8), each independently observed with its own non-vacuous        │
-- │   control) — plus every body-owned guard: binding-mode mutual exclusivity,   │
-- │   the MINT 'currency' + empty-name guards, the 039 source-of-truth guard,     │
-- │   and unknown-account / unknown-or-cross-tenant-security_id.                 │
-- │ L5 ATOMICITY, proven on the one call that writes to TWO tables before its    │
-- │   own rejection (a MINT that also lands branch (a)'s price write, THEN fails  │
-- │   at the ledger INSERT's column overflow): zero orphan pfin.asset AND zero   │
-- │   orphan pfin.eod_price rows survive it — a real cross-table proof, not two  │
-- │   single-table checks that happen to agree. Plus the annotation overlay      │
-- │   composes (note-only compose/no-compose; p_sub_cat_id composition is L6's). │
-- │ L6 instance #10 (023's matched-tenant fence, re-targeted to                  │
-- │   pfin.posting_prototype at 084 — UNLIKE #7, genuinely reachable through 088 │
-- │   because the body never reads posting_prototype itself, so no guard        │
-- │   shadows it). #10's own rejection is 023's battery to prove; what composing │
-- │   through 088 ADDS is the ROLLBACK 023's battery cannot exercise in          │
-- │   isolation — the asset mint, the eod_price write and the ledger row all     │
-- │   roll back when the LATER annotation INSERT is what fails. Three           │
-- │   independently-checked tables, plus the message pinned so a firing-order   │
-- │   change (trigger rename) would go RED rather than resting on Postgres's     │
-- │   documented alphabetical same-timing rule.                                 │
-- └───────────────────────────────────────────────────────────────────────────┘
--
-- MESSAGE-OWNERSHIP DISCIPLINE (every prefix below verified against the committed
--   088 blob in a rolled-back scratch-DB probe, 2026-08-21 — not retyped from the
--   header prose):
--   Body-owned (exact prefix match, throws_like):
--     - unauthenticated caller -> "fn_create_manual_purchase requires an
--       authenticated caller: auth.uid() is NULL…"
--     - both binding modes supplied -> "Supply either p_security_id…not both…"
--     - neither binding mode supplied -> "A purchase must name what was bought…"
--     - unknown/invisible account_id -> "Account % not found or not visible…"
--     - provider-linked account -> "Account % is provider-linked…"
--     - p_quantity non-finite/zero/negative -> "p_quantity must be a finite
--       number greater than zero, got %…"
--     - p_cost_basis non-finite/zero/negative -> "p_cost_basis must be a finite
--       number greater than zero, got %…"
--     - derived per-unit price rounds to 0.0000 (UNCONDITIONAL — fires on every
--       branch, including the no-write global one) -> "This purchase derives a
--       per-unit price of 0.0000…"
--     - p_security_id neither global nor caller-owned (the SAME message whether
--       the asset is cross-tenant-private, or simply does not exist — RLS makes
--       these indistinguishable by construction, and that IS the L1 finding) ->
--       "security_id % is not a global or caller-owned asset…"
--     - MINT asset_type='currency' -> "p_asset_type may not be 'currency'…"
--     - MINT empty p_asset_name -> "p_asset_name must not be empty…"
--     - branch (2) pre-existing price not positive -> "A manual valuation already
--       exists for this asset at % and its price is %…"
--   NOT body-owned (assert REJECTION ONLY — SQLSTATE, not message text):
--     - cost_basis/quantity BOTH huge enough that their ratio does not round to
--       zero (1e400/1e400) -> 017's numeric(20,4) COST_BASIS column coercion,
--       22003. The zero-price fence does not intercept this pair (ratio = 1).
--     - quantity=1e20 / cost_basis=9e15 (clears the zero-price floor; sits inside
--       the SAME narrow half-open window 087's battery derived, [5e15,1e16), so
--       cost_basis stays representable while quantity alone overflows) -> 017's
--       numeric(28,8) QUANTITY column coercion, 22003 — a DIFFERENT column from
--       the case above, independently observed.
--   Vacuity note: unlike 087, where quoted/locale-formatted numerics arrive via
--   jsonb and the type check is their sole observer, p_quantity/p_cost_basis here
--   are TYPED numeric PARAMETERS — a quoted/locale string never reaches this
--   function at all (rejected at parameter coercion, one layer earlier, not
--   tested in this file); a bare 'NaN'::numeric / 'Infinity'::numeric passed
--   AS numeric IS reachable here (087's jsonb path could never produce these) and
--   is what the disjunct legs below actually exercise.
--
-- §10 / DECISION 3: UNCHANGED (per 088's own §10 3-axis cross-check). No FK-shaped
--   column added; the FK-shaped columns WRITTEN THROUGH are existing DDL-realized
--   instances (#7, account_trans.security_id; the 023 sub_cat matched-tenant
--   fence when a category is supplied) — REACHABILITY, not the family, changes:
--   see the L1 header block above. §10 ledger UNCHANGED (no new SD/RT instance; NO
--   service_role anywhere in this path). SECURITY DEFINER allowlist UNCHANGED
--   (fn_create_manual_purchase stays INVOKER — measured prosecdef=false, (l1-9)).
--
-- POSTURE (SECURITY §4.5): SYNTHETIC ONLY — fixed-UUID tenants from
--   _rls.tenant_a()/_b(); NO PII / NO real account numbers / NO prod data. Every
--   ratio fixture is EXACTLY DIVISIBLE except where the ratio defect itself is the
--   thing under test (L3/L4's zero-price-floor and column-overflow legs, which
--   are deliberately NOT exact-divisible — that is the point of those legs).
--
-- ROLE/SCHEMA DISCIPLINE (PR #121 root-cause): `_rls` grants no USAGE to
--   authenticated; tenant UUIDs resolved to psql LITERALS via \gset at
--   role=postgres; every _rls.set_tenant is called at role=postgres and each
--   block restores role=postgres before the next. \gset var names ALL-LOWERCASE.
--   Every expected-error call runs inside its own SAVEPOINT (pgTAP's throws_*
--   verbs do this internally) so one rejected call cannot abort a later
--   assertion in the same transaction.
--
-- ⟦WIRE-VALIDATE⟧ authored against the committed 088 blob (originally ad7f2a1a;
--   re-verified against 8fa6526 after that commit corrected the #7-reachability
--   overclaim in comments only — see the BINDS TO MIGRATION line above for the
--   confirmed byte-diff), read live from the catalog and PROBED in a
--   rolled-back scratch-DB clone of the local stack at 087 + 088 applied on top
--   (2026-08-21) — every message prefix, every branch outcome and every
--   atomicity claim in this file was RUN, not derived from the header prose
--   alone (DESIGN.md's "build X and watch it go red").
--   NOT applied to the shared local stack yet (sits at 086/087; Backend applies
--   via `supabase migration up`, no db reset — F/CTO's local test data must
--   survive). RED-until-088-applied is expected on the shared stack; CI
--   (pg_prove directory-mode) after Backend's apply is the green gate. Verify
--   with pg_prove — bare psql exits 0 on a plan-count failure. plan(67)
--   (raised from an initial 49 after the row(...)::record idiom failed against
--   a live pg_prove run — "cannot compare dissimilar column types text and
--   unknown" — split into 63 per-column assertions instead (see L2/L3/L5);
--   raised again to 67 for L6, added per Architect's ruling on the
--   p_sub_cat_id -> posting_prototype (#10) rollback proof — the fence is
--   023's to prove, but composing through 088 needed its own atomicity leg).
-- =====================================================================

begin;

\ir ../_fixtures/rls_verbs.psql

select plan(67);

select _rls.tenant_a() as ta, _rls.tenant_b() as tb \gset

insert into auth.users (id) values (:'ta'), (:'tb');

-- =====================================================================
-- Setup — one account per tenant (creator-grant satisfies the wr_access-JOIN in
--   the same transaction, per 003).
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
insert into pfin.account (name, account_type, scope, tax_treatment)
values ('A acct', 'depository', 'household', 'taxable')
returning account_id as accta \gset
select set_config('role', 'postgres', true);

select _rls.set_tenant(:'tb'::uuid);
insert into pfin.account (name, account_type, scope, tax_treatment)
values ('B acct', 'depository', 'household', 'taxable')
returning account_id as acctb \gset
select set_config('role', 'postgres', true);

-- B's PRIVATE asset (not global) — the cross-tenant target for L1.
select _rls.set_tenant(:'tb'::uuid);
insert into pfin.asset (users_id, asset_type, pricing_source, name, currency)
values (:'tb', 'equity', 'manual_valuation', 'B Private Position', 'USD')
returning asset_id as b_private_asset \gset
select set_config('role', 'postgres', true);

-- A GLOBAL asset (postgres/service_role only — 016 asset_insert rejects a NULL
-- users_id under authenticated).
insert into pfin.asset (users_id, asset_type, pricing_source, symbol, name, currency)
values (null, 'equity', 'market_feed', 'GLBP', 'Global Purchase Co', 'USD')
returning asset_id as g_asset \gset

-- =====================================================================
-- L1 — auth guard, the D3 #7 finding (corrected), cross-tenant reads, catalog.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);

-- (l1-1) unauthenticated caller (RLS-exempt role, no JWT claims => auth.uid() IS
--   NULL) rejected by the body's own guard, same defense-in-depth posture as 087.
select set_config('role', 'postgres', true);
select set_config('request.jwt.claims', '', true);
select throws_like(
  $$ select pfin.fn_create_manual_purchase(1, '2026-04-01'::date, 1, 10, null, 'equity', 'x') $$,
  'fn_create_manual_purchase requires an authenticated caller: auth.uid() is NULL. This RPC is SECURITY%',
  '(l1-1) RLS-EXEMPT caller (role=postgres, no JWT claims => auth.uid() IS NULL) is REJECTED by the body''s own auth guard'
);

-- (l1-2) THE L1 FINDING, MEASURED: A submits B's PRIVATE asset_id as
--   p_security_id. Rejected by GUARD (9) — NOT #7. Labelled explicitly: this is
--   NOT the #7 test (see (l1-3) and the header block for why #7 cannot
--   independently fire through this RPC in V1).
select _rls.set_tenant(:'ta'::uuid);
select throws_like(
  format($$ select pfin.fn_create_manual_purchase(%s, '2026-04-01'::date, 1, 10, %s) $$, :accta, :b_private_asset),
  'security_id % is not a global or caller-owned asset (SELF-325 / 088)%',
  '(l1-2) A submitting B''s PRIVATE asset_id is rejected — MEASURED as GUARD (9)''s own message, NOT #7''s: this RPC never reaches the account_trans INSERT where #7 fires. This is the live, behaviourally-reachable mechanism on THIS RPC; it is NOT a #7 proof (see (l1-3))'
);
select set_config('role', 'postgres', true);

-- (l1-3) STRUCTURAL: the #7 fence trigger (017 fn_account_trans_security_asset)
--   is still bound + enabled on pfin.account_trans. Its own real behavioural
--   proof lives in 017_account_trans_investment_rls.sql (the raw-INSERT /
--   service_role path it actually gates) — NOT re-derived here, because (l1-2)
--   measurably cannot reach it: #7 is DORMANT through this RPC (088's header,
--   corrected at 8fa6526, now says so), and asserting (l1-2) as a #7 proof would
--   be exactly the "leg matching a different mechanism stands in for the fence" defect this
--   suite's own design discipline warns against.
select ok(
  exists (
    select 1 from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'pfin' and c.relname = 'account_trans'
      and t.tgname = 'account_trans_security_asset'
      and not t.tgisinternal
      and t.tgenabled <> 'D'
  ),
  '(l1-3) STRUCTURAL: the 017 #7 fence trigger (account_trans_security_asset) is still bound + enabled — 088 makes NO change to it; its live behavioural proof is 017''s own battery, not this file'
);

-- (l1-4) NON-VACUOUS COMPANION to (l1-2): a GLOBAL asset_id (the negative
--   control) is ACCEPTED, not rejected — proves (l1-2)'s rejection is about
--   cross-tenant ownership specifically, not about supplying any p_security_id.
select lives_ok(
  format($$ select pfin.fn_create_manual_purchase(%s, '2026-04-01'::date, 1, 10, %s) $$, :accta, :g_asset),
  '(l1-4) NON-VACUOUS: A buying the GLOBAL asset (same call shape as (l1-2), only the asset''s tenancy differs) is ACCEPTED — proves (l1-2)''s rejection is about cross-tenant ownership, not about supplying p_security_id at all'
);

-- (l1-5)/(l1-6)/(l1-7) cross-tenant reads fail closed: B sees none of A's rows
--   from A's successful purchases so far ((l1-4)'s global-asset buy).
select _rls.set_tenant(:'tb'::uuid);
select is(
  (select count(*) from pfin.account_trans where account_id = :accta)::bigint,
  0::bigint,
  '(l1-5) cross-tenant read fails closed: B sees 0 of A''s account_trans rows (006 rd_access-JOIN)'
);
select is(
  (select count(*) from pfin.eod_price e join pfin.account_trans t on t.security_id = e.asset_id
     where t.account_id = :accta)::bigint,
  0::bigint,
  '(l1-6) cross-tenant read fails closed: B sees 0 of A''s eod_price rows reachable via A''s account_trans'
);
select set_config('role', 'postgres', true);

-- (l1-7) catalog: exactly ONE fn_create_manual_purchase overload (11-arg IN
--   identity — OUT params excluded from the identity list).
select is(
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'pfin' and p.proname = 'fn_create_manual_purchase')::bigint,
  1::bigint,
  '(l1-7) exactly ONE fn_create_manual_purchase overload exists in pg_proc'
);

-- (l1-8) INVOKER, not DEFINER.
select is(
  (select p.prosecdef from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'pfin' and p.proname = 'fn_create_manual_purchase'),
  false,
  '(l1-8) fn_create_manual_purchase is SECURITY INVOKER (prosecdef=false)'
);

-- (l1-9) EXECUTE granted to authenticated only; denied to anon/public/service_role
--   (mirrors 078's has_function_privilege pattern).
select ok(
  has_function_privilege('authenticated',
    'pfin.fn_create_manual_purchase(bigint,date,numeric,numeric,bigint,text,text,text,bigint,text,text)'::regprocedure, 'EXECUTE')
  and not has_function_privilege('anon',
    'pfin.fn_create_manual_purchase(bigint,date,numeric,numeric,bigint,text,text,text,bigint,text,text)'::regprocedure, 'EXECUTE')
  and not has_function_privilege('public',
    'pfin.fn_create_manual_purchase(bigint,date,numeric,numeric,bigint,text,text,text,bigint,text,text)'::regprocedure, 'EXECUTE')
  and not has_function_privilege('service_role',
    'pfin.fn_create_manual_purchase(bigint,date,numeric,numeric,bigint,text,text,text,bigint,text,text)'::regprocedure, 'EXECUTE'),
  '(l1-9) EXECUTE granted to authenticated ONLY — anon, public and service_role all denied'
);

-- =====================================================================
-- L2 — PROVENANCE: the 084 P1+P2+P10 row shape, GL-verified. Regression on the
--   untouched cash path (040).
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);

select trans_id as l2_trans, security_id as l2_asset from pfin.fn_create_manual_purchase(
  :accta, '2026-04-02'::date, 5::numeric, 500::numeric, null, 'equity', 'L2 Provenance Position', 'L2P'
) \gset

-- (l2-1a..e) row shape: standard, security_id bound, quantity=+qty, cost_basis=+cost,
--   amount=-cost. Per-column (not a row(...)::record comparison — an untyped
--   literal in a row constructor compares as "unknown" against the query's real
--   column types and pgTAP's is() rejects the mismatch outright).
select is(
  (select transaction_type from pfin.account_trans where trans_id = :l2_trans),
  'standard', '(l2-1a) transaction_type=standard'
);
select ok(
  (select security_id is not null from pfin.account_trans where trans_id = :l2_trans),
  '(l2-1b) security_id is bound (NOT NULL)'
);
select is(
  (select quantity from pfin.account_trans where trans_id = :l2_trans),
  5::numeric, '(l2-1c) quantity = +qty (5)'
);
select is(
  (select cost_basis from pfin.account_trans where trans_id = :l2_trans),
  500::numeric, '(l2-1d) cost_basis = +cost (500)'
);
select is(
  (select amount from pfin.account_trans where trans_id = :l2_trans),
  -500::numeric, '(l2-1e) amount = -cost (-500)'
);

select set_config('role', 'postgres', true);

-- (l2-2) GL: exactly 2 rows for this trans_id — the cash leg (asset_liability,
--   -cost) and the position leg (trade_position, +cost). No Suspense, no
--   Opening-Balance-Equity plug.
select is(
  (select count(*) from pfin.fn_gl_entries('2026-04-02'::date) where source_trans_id = :l2_trans)::bigint,
  2::bigint,
  '(l2-2) fn_gl_entries emits EXACTLY 2 rows for this purchase''s trans_id (P1 cash + P2 position) — no Suspense plug survives the amount_book<>0 filter'
);

-- (l2-3) the two rows sum to zero (non-vacuous: cost_basis=500<>0, so this is not
-- a vacuous 0=0).
select is(
  (select coalesce(sum(amount_book), 0) from pfin.fn_gl_entries('2026-04-02'::date)
     where source_trans_id = :l2_trans),
  0::numeric,
  '(l2-3) the two GL rows for this trans_id sum to ZERO — balanced by construction, non-vacuous (cost_basis=500)'
);

-- (l2-4) NO Suspense / NO opening_equity entry_class row exists for this
-- trans_id — the direct provenance check (P5 must not fire; a P10 plug that
-- rounds to non-zero would also show up here).
select is(
  (select count(*) from pfin.fn_gl_entries('2026-04-02'::date)
     where source_trans_id = :l2_trans and entry_class in ('suspense', 'opening_equity'))::bigint,
  0::bigint,
  '(l2-4) NO Suspense and NO Opening-Balance-Equity row for this purchase''s trans_id — 084 P5 (acct_setup contra) never fires on a standard purchase, and P10''s residual plug is exactly zero'
);

-- (l2-5) REGRESSION: fn_create_manual_trans (040, the cash-entry sibling) is
-- UNTOUCHED — still writes security_id NULL, quantity 0, cost_basis NULL.
select _rls.set_tenant(:'ta'::uuid);
select pfin.fn_create_manual_trans(
  :accta, '2026-04-03'::date, 25.00, 'REGRESSION-VENDOR', 'regression check', null, null
) as l2reg_trans \gset
select set_config('role', 'postgres', true);
select is(
  (select security_id from pfin.account_trans where trans_id = :l2reg_trans),
  null::bigint, '(l2-5a) REGRESSION: fn_create_manual_trans (040) still writes security_id NULL'
);
select is(
  (select transaction_type from pfin.account_trans where trans_id = :l2reg_trans),
  'standard', '(l2-5b) REGRESSION: transaction_type still standard'
);
select is(
  (select amount from pfin.account_trans where trans_id = :l2reg_trans),
  25.00::numeric, '(l2-5c) REGRESSION: amount unaffected'
);
select is(
  (select quantity from pfin.account_trans where trans_id = :l2reg_trans),
  0::numeric, '(l2-5d) REGRESSION: quantity still 0'
);
select is(
  (select cost_basis from pfin.account_trans where trans_id = :l2reg_trans),
  null::numeric, '(l2-5e) REGRESSION: cost_basis still NULL — fn_create_manual_trans (040) writes cash-only, unaffected by 088'
);

-- =====================================================================
-- L3 — the three-branch price companion, asserted as POST-CONDITIONS over the
--   picked price, never by re-deriving 078's rank CASE.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);

-- BRANCH (a) — owned asset (MINT), first purchase at the trade date.
-- ⚠ `priced` here now flows through 089 (fn_asset_priced_flags) — 088's own
-- inline computation was replaced by a call to it (Sec F1/C3 remediation).
-- (l3-1) and (l3-6) below were RE-RUN, not re-verified as comment-only, against
-- that revision (blob fea8cdc3862e6cb9b8b3231a1f82e3b4, per the BINDS-TO block
-- above) and held unchanged — this is the measurement Architect's "semantically
-- identical" claim rests on, not merely a reading of both bodies.
select trans_id as l3a_trans, security_id as l3a_asset, priced as l3a_priced, price as l3a_price
  from pfin.fn_create_manual_purchase(
    :accta, '2026-04-04'::date, 4::numeric, 400::numeric, null, 'equity', 'L3 Branch A Position', 'L3A'
  ) \gset

-- (l3-1) branch (a): priced=true, price>0.
select ok(
  :'l3a_priced'::boolean and :l3a_price > 0,
  '(l3-1) BRANCH (a): owned asset, no prior manual_valuation -> priced=true and the derived price is positive'
);

select set_config('role', 'postgres', true);

-- (l3-2) branch (a) post-condition: exactly ONE eod_price row exists for this
-- asset, at price_date=trade_date, source=manual_valuation, price=the returned
-- price — and it sits at the MAXIMUM price_date <= trade_date with the TOP
-- source rank (manual_valuation), so it IS the row 078's pick would return. No
-- rank CASE is re-derived here; the row's own (date, source) makes the answer
-- forced.
select is(
  (select count(*) from pfin.eod_price where asset_id = :l3a_asset)::bigint,
  1::bigint,
  '(l3-2) BRANCH (a): exactly ONE eod_price row exists for the new asset'
);
select is(
  (select price_date from pfin.eod_price where asset_id = :l3a_asset),
  '2026-04-04'::date, '(l3-2v-a) that row sits at price_date=trade_date (the MAXIMUM price_date <= trade_date)'
);
select is(
  (select source from pfin.eod_price where asset_id = :l3a_asset),
  'manual_valuation', '(l3-2v-b) source=manual_valuation (the TOP source rank) — max date + top rank -> the FORCED pick answer, asserted directly rather than re-deriving 078''s rank CASE'
);
select is(
  (select price from pfin.eod_price where asset_id = :l3a_asset),
  :l3a_price, '(l3-2v-c) price = the returned price'
);

-- BRANCH (b) — buy MORE of the SAME asset, SAME trade date, a DIFFERENT
-- cost/qty ratio (2 units / 1000 -> derives 500.0000, sharply different from
-- branch (a)'s 100.0000). If the write-side fence ever regressed to an
-- unconditional overwrite, the existing price would become 500.0000.
select _rls.set_tenant(:'ta'::uuid);
select trans_id as l3b_trans, priced as l3b_priced, price as l3b_price
  from pfin.fn_create_manual_purchase(:accta, '2026-04-04'::date, 2::numeric, 1000::numeric, :l3a_asset) \gset
select set_config('role', 'postgres', true);

-- (l3-3) branch (b): still NO new eod_price row (count stays 1, not 2).
select is(
  (select count(*) from pfin.eod_price where asset_id = :l3a_asset)::bigint,
  1::bigint,
  '(l3-3) BRANCH (b): buying more of the SAME asset at the SAME trade date writes NO new eod_price row — count stays 1'
);

-- (l3-4) THE F4 FENCE: the pre-existing price is BYTE-UNCHANGED at 100.0000 —
-- not overwritten to 500.0000. Buying more must not restate the prior lot.
select is(
  (select price from pfin.eod_price where asset_id = :l3a_asset),
  :l3a_price,
  '(l3-4) F4 FENCE: the pre-existing manual_valuation price is UNCHANGED after branch (b) — NOT restated to the new purchase''s 500.0000 ratio'
);

-- (l3-5) THE EASY-TO-INVERT SUBTLETY: the RETURNED `price` on branch (b) is the
-- NEW call's own derived ratio (500.0000), NOT the pre-existing picked price
-- (100.0000) — pinned explicitly because both readings are plausible from the
-- header alone.
select is(
  :'l3b_priced'::boolean and :l3b_price = 500.0000,
  true,
  '(l3-5) branch (b) returns priced=true, price=500.0000 (THIS call''s own derived ratio) — NOT 100.0000 (the pre-existing/picked price); the two are easy to invert and only one is what the function actually returns'
);

-- BRANCH (c) — GLOBAL asset. No price write is possible by construction (019).
select _rls.set_tenant(:'ta'::uuid);
select trans_id as l3c_trans, priced as l3c_priced, price as l3c_price
  from pfin.fn_create_manual_purchase(:accta, '2026-04-05'::date, 3::numeric, 30::numeric, :g_asset) \gset
select set_config('role', 'postgres', true);

-- (l3-6) branch (c): priced=false.
select is(:'l3c_priced'::boolean, false,
  '(l3-6) BRANCH (c): a GLOBAL asset purchase returns priced=false — no provider has priced it and this caller cannot'
);

-- (l3-7) branch (c): ZERO eod_price rows exist for the global asset — the write
-- is unreachable, not merely undone.
select is(
  (select count(*) from pfin.eod_price where asset_id = :g_asset)::bigint,
  0::bigint,
  '(l3-7) BRANCH (c): zero eod_price rows exist for the global asset — 019''s policy makes the write unreachable, this is not a skip-by-choice'
);

-- (l3-8) branch (c): the account_trans row is STILL correctly shaped —
-- quantity/cost_basis/price all populated — despite the position being
-- legitimately unpriced. "Unpriced" is a valuation-layer fact, not a ledger gap.
select is(
  (select quantity from pfin.account_trans where trans_id = :l3c_trans),
  3::numeric, '(l3-8a) BRANCH (c): quantity=3, fully shaped despite being unpriced at the valuation layer'
);
select is(
  (select cost_basis from pfin.account_trans where trans_id = :l3c_trans),
  30::numeric, '(l3-8b) BRANCH (c): cost_basis=30'
);
select is(
  (select price from pfin.account_trans where trans_id = :l3c_trans),
  :l3c_price, '(l3-8c) BRANCH (c): price=the derived ratio — the ledger row is complete even though the position is legitimately unpriced'
);

-- (l3-9) guard (12): a pre-existing WORTHLESS (price<=0) manual_valuation row at
-- the trade date REFUSES the purchase rather than silently accepting it — the
-- F3-b spelling a presence check alone cannot see.
select _rls.set_tenant(:'ta'::uuid);
insert into pfin.asset (users_id, asset_type, pricing_source, name, currency)
values (:'ta', 'equity', 'manual_valuation', 'L3 Worthless Pre-existing', 'USD')
returning asset_id as l3worthless_asset \gset
select set_config('role', 'postgres', true);
insert into pfin.eod_price (asset_id, price_date, source, price)
values (:l3worthless_asset, '2026-04-06', 'manual_valuation', 0.0000);
select _rls.set_tenant(:'ta'::uuid);
select throws_like(
  format($$ select pfin.fn_create_manual_purchase(%s, '2026-04-06'::date, 1, 50, %s) $$, :accta, :l3worthless_asset),
  'A manual valuation already exists for this asset at % and its price is %',
  '(l3-9) guard (12): a pre-existing WORTHLESS (price=0.0000) manual_valuation row at the trade date REFUSES the purchase rather than silently accepting a zero-valued position'
);
select set_config('role', 'postgres', true);

-- (l3-10) guard (8) is UNCONDITIONAL: it fires on the GLOBAL branch too, which
-- writes no price row at all — proving the fence isn't skipped for the branch
-- that never touches eod_price.
select set_config('role', 'postgres', true);
insert into pfin.asset (users_id, asset_type, pricing_source, symbol, name, currency)
values (null, 'equity', 'market_feed', 'GLB2', 'Global Co 2', 'USD')
returning asset_id as g2_asset \gset
select _rls.set_tenant(:'ta'::uuid);
select throws_like(
  format($$ select pfin.fn_create_manual_purchase(%s, '2026-04-07'::date, 1000000, 10.00, %s) $$, :accta, :g2_asset),
  'This purchase derives a per-unit price of 0.0000 and would record a worthless trade: cost_basis%',
  '(l3-10) guard (8) fires on the GLOBAL branch too (quantity=1,000,000/cost_basis=10.00, no price row would ever be written) — proves the zero-price fence is UNCONDITIONAL, not scoped to the write branch'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- L4 — Lock 14 (ratio + magnitude, direct-numeric NaN/Infinity) + every
--   remaining body-owned guard.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);

-- (l4-1) direct NaN quantity (a bare numeric literal, not jsonb — reachable here,
-- unlike 087).
select throws_like(
  format($$ select pfin.fn_create_manual_purchase(%s, '2026-04-08'::date, 'NaN'::numeric, 10, null, 'equity', 'x') $$, :accta),
  'p_quantity must be a finite number greater than zero, got NaN%',
  '(l4-1) quantity=''NaN''::numeric (direct, not jsonb) rejected by the disjunct guard'
);

-- (l4-2) direct Infinity quantity.
select throws_like(
  format($$ select pfin.fn_create_manual_purchase(%s, '2026-04-08'::date, 'Infinity'::numeric, 10, null, 'equity', 'x') $$, :accta),
  'p_quantity must be a finite number greater than zero, got Infinity%',
  '(l4-2) quantity=''Infinity''::numeric rejected'
);

-- (l4-3) direct -Infinity quantity (also caught by the <=0 disjunct since
-- -Infinity <= 0).
select throws_like(
  format($$ select pfin.fn_create_manual_purchase(%s, '2026-04-08'::date, '-Infinity'::numeric, 10, null, 'equity', 'x') $$, :accta),
  'p_quantity must be a finite number greater than zero, got -Infinity%',
  '(l4-3) quantity=''-Infinity''::numeric rejected'
);

-- (l4-4) zero quantity.
select throws_like(
  format($$ select pfin.fn_create_manual_purchase(%s, '2026-04-08'::date, 0, 10, null, 'equity', 'x') $$, :accta),
  'p_quantity must be a finite number greater than zero, got 0%',
  '(l4-4) quantity=0 rejected by the positivity guard'
);

-- (l4-5) negative quantity.
select throws_like(
  format($$ select pfin.fn_create_manual_purchase(%s, '2026-04-08'::date, -5, 10, null, 'equity', 'x') $$, :accta),
  'p_quantity must be a finite number greater than zero, got -5%',
  '(l4-5) quantity=-5 rejected'
);

-- (l4-6) NaN cost_basis.
select throws_like(
  format($$ select pfin.fn_create_manual_purchase(%s, '2026-04-08'::date, 1, 'NaN'::numeric, null, 'equity', 'x') $$, :accta),
  'p_cost_basis must be a finite number greater than zero, got NaN%',
  '(l4-6) cost_basis=''NaN''::numeric rejected'
);

-- (l4-7) zero cost_basis.
select throws_like(
  format($$ select pfin.fn_create_manual_purchase(%s, '2026-04-08'::date, 1, 0, null, 'equity', 'x') $$, :accta),
  'p_cost_basis must be a finite number greater than zero, got 0%',
  '(l4-7) cost_basis=0 rejected'
);

-- (l4-8) negative cost_basis.
select throws_like(
  format($$ select pfin.fn_create_manual_purchase(%s, '2026-04-08'::date, 1, -5, null, 'equity', 'x') $$, :accta),
  'p_cost_basis must be a finite number greater than zero, got -5%',
  '(l4-8) cost_basis=-5 rejected'
);

-- (l4-9) THE RATIO SURFACE: quantity=1,000,000 / cost_basis=10.00 — no single
-- variable is extreme, and it passes every magnitude guard above. Rejected by
-- the zero-price floor (same mechanism as (l3-10), a different asset/branch).
select throws_like(
  format($$ select pfin.fn_create_manual_purchase(%s, '2026-04-08'::date, 1000000, 10.00, null, 'equity', 'ratio-defect') $$, :accta),
  'This purchase derives a per-unit price of 0.0000 and would record a worthless trade: cost_basis%',
  '(l4-9) RATIO SURFACE: quantity=1,000,000/cost_basis=10.00 passes every magnitude guard and is rejected only by the zero-price floor'
);

-- (l4-10) cost_basis=1e400 with quantity=1e400 (ratio=1, does NOT round to
-- zero) -> reaches 017's numeric(20,4) COST_BASIS column coercion. NOT the
-- body; assert rejection only.
select throws_ok(
  format($$ select pfin.fn_create_manual_purchase(%s, '2026-04-08'::date, 1e400, 1e400, null, 'equity', 'x') $$, :accta),
  '22003', null,
  '(l4-10) quantity=1e400/cost_basis=1e400 (ratio=1, clears the zero-price floor) rejected at 017''s numeric(20,4) cost_basis column coercion (22003) — NOT the body'
);

-- (l4-11) quantity=1e20 / cost_basis=9e15: clears the zero-price floor (ratio
-- 9e-5 rounds to 0.0001) AND cost_basis stays representable in numeric(20,4);
-- quantity alone overflows numeric(28,8). A DIFFERENT column from (l4-10),
-- independently observed.
select throws_ok(
  format($$ select pfin.fn_create_manual_purchase(%s, '2026-04-08'::date, 1e20, 9e15, null, 'equity', 'x') $$, :accta),
  '22003', null,
  '(l4-11) quantity=1e20/cost_basis=9e15 rejected at 017''s numeric(28,8) QUANTITY column coercion (22003) — a DIFFERENT column from (l4-10), restoring independent observation of the quantity ceiling'
);

-- (l4-11v) NON-VACUOUS CONTROL: quantity=1e19 (one order of magnitude under
-- (l4-11)'s ceiling) with the SAME cost_basis=9e15 is ACCEPTED — proves the
-- rejection above is about crossing quantity's ceiling specifically.
select lives_ok(
  format($$ select pfin.fn_create_manual_purchase(%s, '2026-04-08'::date, 1e19, 9e15, null, 'equity', 'qty-ctrl') $$, :accta),
  '(l4-11v) NON-VACUOUS: quantity=1e19 (fits numeric(28,8), one order of magnitude under (l4-11)''s 1e20) with the SAME cost_basis=9e15 is ACCEPTED'
);

-- (l4-12) mutual exclusivity: BOTH binding modes supplied.
select throws_like(
  format($$ select pfin.fn_create_manual_purchase(%s, '2026-04-08'::date, 1, 10, %s, 'equity', 'x') $$, :accta, :g_asset),
  'Supply either p_security_id (bind an existing asset) or p_asset_type + p_asset_name%',
  '(l4-12) both p_security_id AND p_asset_type/p_asset_name supplied is rejected'
);

-- (l4-13) mutual exclusivity: NEITHER binding mode supplied.
select throws_like(
  format($$ select pfin.fn_create_manual_purchase(%s, '2026-04-08'::date, 1, 10) $$, :accta),
  'A purchase must name what was bought%',
  '(l4-13) neither p_security_id nor p_asset_type/p_asset_name supplied is rejected'
);

-- (l4-14) MINT asset_type='currency' rejected.
select throws_like(
  format($$ select pfin.fn_create_manual_purchase(%s, '2026-04-08'::date, 1, 10, null, 'currency', 'usd-bound') $$, :accta),
  'p_asset_type may not be ''currency'': cash is amount-carried%',
  '(l4-14) MINT asset_type=''currency'' rejected — cash must never be instrument-bound on this path either'
);

-- (l4-15) MINT empty p_asset_name rejected.
select throws_like(
  format($$ select pfin.fn_create_manual_purchase(%s, '2026-04-08'::date, 1, 10, null, 'equity', '') $$, :accta),
  'p_asset_name must not be empty%',
  '(l4-15) MINT with an empty p_asset_name is rejected'
);

-- (l4-16) source-of-truth guard: a provider-linked account is refused.
select set_config('role', 'postgres', true);
insert into pfin.linked_source (users_id, provider, connection_status)
values (:'ta', 'plaid', 'healthy')
returning source_id as ls_source \gset
select _rls.set_tenant(:'ta'::uuid);
insert into pfin.account (name, account_type, scope, tax_treatment, linked_source_id)
values ('A linked acct', 'depository', 'household', 'taxable', :ls_source)
returning account_id as acct_linked \gset
select throws_like(
  format($$ select pfin.fn_create_manual_purchase(%s, '2026-04-08'::date, 1, 10, null, 'equity', 'x') $$, :acct_linked),
  'Account % is provider-linked, so its transactions come from the provider%',
  '(l4-16) the 039 source-of-truth guard: a provider-linked account refuses a manual purchase (double-count prevention)'
);
select set_config('role', 'postgres', true);

-- (l4-17) unknown account_id rejected.
select _rls.set_tenant(:'ta'::uuid);
select throws_like(
  $$ select pfin.fn_create_manual_purchase(999999999, '2026-04-08'::date, 1, 10, null, 'equity', 'x') $$,
  'Account % not found or not visible to this caller%',
  '(l4-17) a nonexistent account_id is rejected'
);

-- (l4-18) unknown security_id (does not exist at all, not merely cross-tenant)
-- rejected by the SAME message family as (l1-2) — RLS makes "does not exist" and
-- "exists but is another tenant's private row" indistinguishable by
-- construction, which is exactly the L1 finding restated on a different input.
select throws_like(
  format($$ select pfin.fn_create_manual_purchase(%s, '2026-04-08'::date, 1, 10, 999999999) $$, :accta),
  'security_id % is not a global or caller-owned asset%',
  '(l4-18) a nonexistent security_id is rejected by the SAME guard (9) message as a cross-tenant one — RLS cannot distinguish the two cases, which is the L1 finding restated'
);

-- =====================================================================
-- L5 — ATOMICITY across TWO tables, plus the annotation overlay.
-- =====================================================================
select set_config('role', 'postgres', true);
select _rls.set_tenant(:'ta'::uuid);

select
  (select count(*) from pfin.asset where users_id = :'ta') as l5_baseline_asset,
  (select count(*) from pfin.eod_price e join pfin.asset a on a.asset_id = e.asset_id where a.users_id = :'ta') as l5_baseline_price
\gset

-- (l5-1)/(l5-2) THE REAL CROSS-TABLE PROOF: a MINT call that reaches BRANCH (a)
-- (mints the asset, THEN writes its manual_valuation price row) and only THEN
-- fails, at the ledger INSERT's own numeric(28,8) quantity column overflow
-- (same shape as (l4-11), MINT mode here). Two tables were written to before the
-- rejection; both must show ZERO orphans — a check that could disagree (one
-- table rolling back and not the other) if the atomicity were only apparent.
select throws_ok(
  format($$ select pfin.fn_create_manual_purchase(%s, '2026-04-09'::date, 1e20, 9e15, null, 'equity', 'Atomicity Mint+Price Reject') $$, :accta),
  '22003', null,
  '(l5-atomicity-setup) MINT + branch-(a) price write, THEN column-overflow rejection at the ledger INSERT'
);
select is(
  (select count(*) from pfin.asset where users_id = :'ta')::bigint,
  :l5_baseline_asset::bigint,
  '(l5-1) ZERO orphan pfin.asset rows after the MINT-then-rejected call — the asset INSERT does not survive the later failure'
);
select is(
  (select count(*) from pfin.eod_price e join pfin.asset a on a.asset_id = e.asset_id where a.users_id = :'ta')::bigint,
  :l5_baseline_price::bigint,
  '(l5-2) ZERO orphan pfin.eod_price rows after the SAME rejected call — the branch-(a) price write does not survive either. Two independent tables, both rolled back — not one check that happens to agree with itself'
);

-- (l5-3) the annotation overlay composes: p_note supplied writes exactly one
-- account_trans_annotation row, sub_cat_id NULL. (p_sub_cat_id composition
-- against the 023 matched-tenant fence — #10, re-targeted to posting_prototype
-- at 084 — is L6's, below: the fence's own rejection is 023's battery to prove,
-- but composing through 088 needed its own rollback proof.)
select trans_id as l5note_trans from pfin.fn_create_manual_purchase(
  :accta, '2026-04-10'::date, 1::numeric, 100::numeric, null, 'equity', 'L5 Note Position', null, null, 'a description', 'a note'
) \gset
select set_config('role', 'postgres', true);
select is(
  (select count(*) from pfin.account_trans_annotation where trans_id = :l5note_trans)::bigint,
  1::bigint, '(l5-3a) supplying p_note writes exactly ONE account_trans_annotation row'
);
select is(
  (select sub_cat_id from pfin.account_trans_annotation where trans_id = :l5note_trans),
  null::bigint, '(l5-3b) sub_cat_id NULL (none was supplied)'
);
select is(
  (select note from pfin.account_trans_annotation where trans_id = :l5note_trans),
  'a note', '(l5-3c) note = the given note'
);

-- (l5-4) NON-VACUOUS COMPANION: neither p_sub_cat_id nor p_note supplied writes
-- NO annotation row at all.
select _rls.set_tenant(:'ta'::uuid);
select trans_id as l5noann_trans from pfin.fn_create_manual_purchase(
  :accta, '2026-04-11'::date, 1::numeric, 100::numeric, null, 'equity', 'L5 No Annotation Position'
) \gset
select set_config('role', 'postgres', true);
select is(
  (select count(*) from pfin.account_trans_annotation where trans_id = :l5noann_trans)::bigint,
  0::bigint,
  '(l5-4) NON-VACUOUS: neither p_sub_cat_id nor p_note supplied writes ZERO account_trans_annotation rows'
);

-- =====================================================================
-- L6 — item 2 (Architect's ruling): p_sub_cat_id -> pfin.posting_prototype is
--   instance #10 (023's matched-tenant fence, chain-resolved; re-targeted to
--   posting_prototype at 084/ADR-058 — the label is unchanged, only the FK
--   target moved). UNLIKE #7, THIS FENCE IS GENUINELY REACHABLE THROUGH 088:
--   the body never reads posting_prototype itself (p_sub_cat_id passes straight
--   to the annotation INSERT), so there is no shadowing guard. #10's own
--   rejection is 023's battery to prove — what's uncovered THERE is composing
--   through 088: a rejected annotation must roll back the asset mint, the
--   eod_price write and the ledger row, which 023's battery (which exercises
--   the fence in isolation) cannot exercise. Same cross-table zero-orphan shape
--   as L5, different trigger — the message assertion is what PINS the firing
--   order empirically (account_trans_annotation_matched_sub_cat sorts before
--   account_trans_annotation_trade_constraints alphabetically, so #10 fires
--   first): if Postgres's same-timing alphabetical rule were ever violated by a
--   rename, this leg goes red rather than resting on read-the-docs.
-- =====================================================================
select _rls.set_tenant(:'tb'::uuid);
insert into pfin.posting_prototype (users_id, cat, sub_cat)
values (:'tb', 'Trade', 'BTO')
returning id as b_private_subcat \gset
select set_config('role', 'postgres', true);

select
  (select count(*) from pfin.asset where users_id = :'ta') as l6_baseline_asset,
  (select count(*) from pfin.eod_price e join pfin.asset a on a.asset_id = e.asset_id where a.users_id = :'ta') as l6_baseline_price,
  (select count(*) from pfin.account_trans where account_id = :accta) as l6_baseline_trans
\gset

select _rls.set_tenant(:'ta'::uuid);

-- (l6-1) #10 fires and PINS the message — a MINT-mode purchase (asset mint +
-- eod_price write + ledger row, all real, THEN the annotation INSERT) with
-- tenant B's PRIVATE posting_prototype id as p_sub_cat_id.
select throws_like(
  format($$ select pfin.fn_create_manual_purchase(%s, '2026-04-12'::date, 1, 100, null, 'equity', 'L6 Cross-Tenant SubCat Buy', null, %s) $$,
    :accta, :b_private_subcat),
  'Sub-Cat reference rejected: sub_cat_id % is not a posting prototype owned by and visible to the tenant of trans_id %',
  '(l6-1) #10 fires on a cross-tenant p_sub_cat_id through 088 (genuinely reachable, unlike #7 — this body never reads posting_prototype itself) — message pinned so a firing-order change (trigger rename) would go RED here rather than resting on Postgres''s documented alphabetical rule'
);
select set_config('role', 'postgres', true);

-- (l6-2)/(l6-3)/(l6-4) THE ROLLBACK PROOF — the part #10's OWN battery (023)
-- cannot exercise, since it tests the fence in isolation: the asset mint, the
-- branch-(a) eod_price write, and the ledger row must ALL roll back together
-- when the LATER annotation INSERT is what fails. Three independent tables,
-- each checked, not one check assumed to cover the others.
select is(
  (select count(*) from pfin.asset where users_id = :'ta')::bigint,
  :l6_baseline_asset::bigint,
  '(l6-2) ZERO orphan pfin.asset rows — the #10 rejection rolls back the MINT that happened earlier in the same call'
);
select is(
  (select count(*) from pfin.eod_price e join pfin.asset a on a.asset_id = e.asset_id where a.users_id = :'ta')::bigint,
  :l6_baseline_price::bigint,
  '(l6-3) ZERO orphan pfin.eod_price rows — branch (a)''s price write also rolls back'
);
select is(
  (select count(*) from pfin.account_trans where account_id = :accta)::bigint,
  :l6_baseline_trans::bigint,
  '(l6-4) ZERO orphan pfin.account_trans rows — the ledger row itself rolls back, not just its would-be annotation'
);

select * from finish();
rollback;
