-- =====================================================================
-- Per-Wave battery — pfin.fn_create_manual_account extended to 7 args with
--   p_positions jsonb (SELF-325 — manual-account opening-value binding to
--   pfin.asset rows via instrument-routed acct_setup rows; V1-SHIP-BLOCK)
-- =====================================================================
-- BINDS TO MIGRATION: supabase/migrations/087_manual_account_value_binding.sql
--   (df5024e, feature/manual-value-binding) —
--   pfin.fn_create_manual_account(p_name text, p_account_type text, p_scope text,
--     p_tax_treatment text, p_initial_value numeric, p_as_of_date date,
--     p_positions jsonb default '[]'::jsonb) RETURNS bigint — SECURITY INVOKER,
--     set search_path = ''. DROP + CREATE over the 6-arg 048 signature (no
--     overload — measured: exactly one fn_create_manual_account in pg_proc).
--   Body, per position: INSERT pfin.asset (users_id = auth.uid(), pricing_source
--     = 'manual_valuation', currency = account's) -> INSERT pfin.eod_price
--     (source='manual_valuation', price_date=p_as_of_date, price=cost_basis/
--     quantity — F3) -> INSERT pfin.account_trans (acct_setup, amount=0 — F2,
--     security_id/quantity/cost_basis/price bound). Cash remainder row UNCHANGED
--     from 048: acct_setup, amount=p_initial_value, security_id NULL — F1.
-- Prereqs exercised (all on main / this branch): 003 (account + creator-grant),
--   004 (immutable ledger), 006 (account_trans rd/wr_access-JOIN RLS), 016
--   (pfin.asset hybrid registry + asset_asset_type_check + asset_user_name_uniq),
--   017 (account_trans investment cols + the #7 fn_account_trans_security_asset
--     fence + the {quantity,cost_basis,price}_finite CHECKs), 019 (eod_price +
--     fn_holdings_as_of + fn_compute_nav), 022 (user_asset_category — the
--     pending-classification target), 048 (the 6-arg predecessor), 050/056
--     (fn_compute_nav active-only split + fn_account_cash_as_of extraction +
--     fn_account_unrealized_gl), 076/081/086 (fn_subcat_market_value + the
--     086-ratified seam invariant Σfn_subcat_market_value(as_of,true) =
--     fn_compute_nav(as_of)).
-- Reuses the SELF-187.. idiom: \ir verbs, ALL-LOWERCASE \gset literals, role
--   restored to postgres between blocks (PR #121 root-cause).
--
-- ┌─ WHAT THIS BATTERY PROVES ─────────────────────────────────────────────────┐
-- │ L1 tenant isolation on the RPC-created position-asset surface, PLUS a       │
-- │   STRUCTURAL proof the #7 fence is still bound (unreachable THROUGH this    │
-- │   RPC by construction — no asset_id in the jsonb payload — so a catalog     │
-- │   check is the only observer that the fence itself was not silently        │
-- │   dropped when 087 replaced the function), PLUS a watcher on the body's    │
-- │   own auth.uid()-IS-NULL guard: an RLS-EXEMPT caller (role=postgres — a    │
-- │   DIFFERENT threat from anon, which never reaches the body at all) with    │
-- │   no JWT claims is rejected. MEASURED (inversion-tested): the account     │
-- │   INSERT's own users_id NOT NULL constraint was ALREADY the backstop on   │
-- │   this path, guard or not; the guard's real value is failing EARLY and    │
-- │   LEGIBLY on a named error instead of an incidental constraint on an      │
-- │   unrelated table. See (l1-10)/(l1-11)'s block comment for the detail.    │
-- │ L2 the RPC-created position lands in the derived pending-classification    │
-- │   set EXACTLY ONCE, and the global USD currency-asset never does (F1).     │
-- │ L3 F2 (double-count): fn_account_cash_as_of proves the cash remainder is   │
-- │   NOT inflated by the position's cost_basis, directly — not merely via a   │
-- │   seam-parity check that would stay green under a SHARED double-count      │
-- │   (both fn_subcat_market_value and fn_compute_nav read the SAME             │
-- │   fn_account_cash_as_of/fn_holdings_as_of primitives, so a bug in either    │
-- │   pollutes both sides of that parity identically — L3-1 is the actual      │
-- │   detector; L3-3/L3-4 prove the classification-layer composes correctly    │
-- │   on top of it, a real but DIFFERENT property).                            │
-- │ L4 F3 (zero-valuation): a blanket no-orphaned-bound-rows check across ALL   │
-- │   tenants, plus a direct value check that a position's opening cost_basis  │
-- │   actually reaches NAV (not silently zeroed by a missing eod_price write). │
-- │ L5 the $0 path (omitted / '[]' / NULL — all three, per architect's         │
-- │   confirmation) stays byte-identical to 048's existing behavior, PLUS the  │
-- │   Lock 14 adversarial-numeric matrix on quantity/cost_basis (9 classes ×2  │
-- │   columns), PLUS the individual body-owned guards (currency asset_type,    │
-- │   name shape, p_positions shape), PLUS atomicity: zero orphan pfin.account │
-- │   AND zero orphan pfin.asset rows survive ANY of the ~25 rejected calls.   │
-- └───────────────────────────────────────────────────────────────────────────┘
--
-- MESSAGE-OWNERSHIP DISCIPLINE (measured against the live catalog by Architect,
--   df5024e, in a rolled-back begin…rollback probe — not predicted):
--   Body-owned (exact prefix match, throws_like):
--     - quoted/missing quantity or cost_basis -> "…must be a JSON number
--       (unquoted). Quoted values…" (the em-dash after "values" is a REAL U+2014
--       — patterns below truncate before it, per Architect's warning).
--     - quantity/cost_basis <= 0 -> "…must be a finite number greater than
--       zero, got …".
--     - asset_type = 'currency' -> "…asset_type may not be 'currency': cash is
--       amount-carried, not i…" (F1 body-level guard — DISTINCT from the 016
--       vocab CHECK; 'currency' IS a valid 016 vocab value in general, so only
--       an explicit body guard can reject it here).
--     - name missing/wrong-type -> "…name must be a JSON string."; name empty
--       -> "…name must not be empty."
--     - p_positions non-array -> "…must be a JSON array of opening
--       positions, got object.…"; a non-object array element -> "…must be a
--       JSON object, got string."
--     - SEC CLEARANCE (a/b/c): quantity/cost_basis whose ROUNDED RATIO
--       (round(cost_basis/quantity,4)) is <= 0 -> the body's zero-price fence
--       (P0001), inserted between price computation and the eod_price INSERT.
--       Catches quantity=1000000/cost_basis=10.00 ((l5-price-floor)) AND,
--       LAYER-MOVED, quantity=1e400/cost_basis=10 ((l5-q-overflow) — see that
--       leg's block comment: no cost_basis choice keeps the 1e400-quantity
--       case on the OLD column-coercion layer any more, this fence fires
--       first for any representable cost_basis).
--   NOT body-owned (assert REJECTION ONLY — SQLSTATE, not message text; a
--     message-text leg here would test someone ELSE's error contract):
--     - cost_basis=1e400 (scientific-notation overflow, quantity held small
--       enough the ratio does NOT round to zero) -> 017's numeric(20,4)
--       COST_BASIS column coercion, SQLSTATE 22003 (numeric_value_out_of_range).
--       ⚠ quantity=1e400 is NO LONGER in this category (see above) — only
--       cost_basis=1e400 still reaches the column layer this way, since a
--       huge cost_basis over a small quantity does not zero the ratio.
--     - quantity=1e20 / cost_basis=1e16 ((l5-q-column-overflow)) -> 017's
--       numeric(28,8) QUANTITY column coercion, SQLSTATE 22003. A DIFFERENT
--       column from the cost_basis case above (20 vs 16 integer digits) — this
--       is the leg that restores quantity-column observability after
--       (l5-q-overflow)'s re-target, via the narrow window where quantity
--       clears its own column ceiling while cost_basis clears the zero-price
--       floor without overflowing ITS column (Architect, measured).
--     - asset_type outside 016's vocab entirely -> 016's asset_asset_type_check,
--       SQLSTATE 23514 (check_violation).
--     - duplicate position name in one payload -> 016's asset_user_name_uniq,
--       SQLSTATE 23505 (unique_violation).
--   'NaN'/'Infinity' as UNQUOTED JSON literals do not exist (invalid JSON) —
--     the four-disjunct body guard's `= 'NaN'` / `>= 'Infinity'` branches are
--     belt-and-braces, unreachable through jsonb input; NOT separately tested
--     here (no leg claims they fire — the header of 087 records the same).
--
-- §10 / DECISION 3: UNCHANGED (per 087's own §10 3-axis cross-check + governance
--   section). No FK-shaped column added — p_positions is a transient jsonb
--   ARGUMENT, not a stored column (every id it carries lands in a real, fenced
--   column — account_trans.security_id, #7 — within the same statement; ADR-056's
--   stored-jsonb-key-set rejection does not reach a transient argument). §10
--   ledger UNCHANGED (no new SD/RT instance; no service_role surface — every
--   write here is authenticated-tier). SECURITY DEFINER allowlist UNCHANGED
--   (fn_create_manual_account stays INVOKER — measured prosecdef=false, (l1-9)).
--
-- POSTURE (SECURITY §4.5): SYNTHETIC ONLY — fixed-UUID tenants from
--   _rls.tenant_a()/_b(); NO PII / NO real account numbers / NO prod data. All
--   fixture numerics chosen EXACTLY DIVISIBLE (e.g. 500/5=100.00 exact) to keep
--   L3/L4 assertions exact rather than tolerance-based — 087's own header
--   documents a rounding artifact on non-exact cost_basis/quantity pairs
--   (round(cost_basis/quantity,4), numeric(20,4)). ⚠ SEC-CORRECTED: this is
--   NOT bounded to "sub-cent" — the per-unit rounding error is at most 0.00005,
--   so the TOTAL artifact on a position's opening value is bounded by
--   quantity × 0.00005, which is sub-cent only up to quantity ≈ 200 and grows
--   unbounded with quantity (measured: quantity=1,000,000 / cost_basis=10.00
--   rounds to price=0.0000 — a $0-priced position, not a rounding footnote).
--   See L5's quantity/price-floor leg (Sec clearance (c)), which asserts the
--   RPC RAISES on that ratio rather than silently accepting a zero-valued
--   position. All in a rolled-back txn.
--
-- ROLE/SCHEMA DISCIPLINE (PR #121 root-cause): `_rls` grants no USAGE to
--   authenticated; tenant UUIDs resolved to psql LITERALS via \gset at
--   role=postgres; every _rls.set_tenant is called at role=postgres and each
--   block restores role=postgres before the next. \gset var names ALL-LOWERCASE.
--
-- ⟦WIRE-VALIDATE⟧ authored against 087 (df5024e) read live from the catalog by
--   Architect in a rolled-back probe — NOT applied to the local stack yet
--   (sits at 086; Backend applies via `supabase migration up`, no db reset —
--   F/CTO's local test data must survive). RED-until-087-applied is expected
--   locally; CI (pg_prove directory-mode) after Backend's apply is the green
--   gate. Verify with pg_prove — bare psql exits 0 on a plan-count failure.
--   plan(56).
-- =====================================================================

begin;

\ir ../_fixtures/rls_verbs.psql

select plan(56);

select _rls.tenant_a() as ta, _rls.tenant_b() as tb \gset

insert into auth.users (id) values (:'ta'), (:'tb');

-- global USD currency-asset (016 seed) — L2's F1 (USD-absent) watcher.
select asset_id as g_usd from pfin.asset where symbol = 'USD' and users_id is null \gset

-- =====================================================================
-- L1 — tenant isolation on the RPC-created position-asset surface, PLUS the
--   structural #7-fence-still-bound proof (unreachable THROUGH this RPC by
--   construction — no asset_id in the jsonb payload — so a catalog check is
--   the only observer).
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);

select pfin.fn_create_manual_account(
  'L1 A acct', 'depository', 'household', 'taxable', 500.00, '2026-04-01',
  '[{"asset_type":"equity","name":"L1 A Position","quantity":4,"cost_basis":400}]'::jsonb
) as rpc_acct_l1a \gset

select security_id as l1a_asset from pfin.account_trans
  where account_id = :rpc_acct_l1a and security_id is not null \gset

-- (l1-1) ownership: the created asset is A-owned (never NULL = global, never B).
select is(
  (select users_id from pfin.asset where asset_id = :l1a_asset),
  :'ta'::uuid,
  '(l1-1) RPC-created position asset is A-owned (users_id = auth.uid() = A) — never GLOBAL (NULL), never B'
);

-- (l1-2) owner reads own bound row (non-vacuous positive).
select is(
  (select count(*) from pfin.account_trans
     where account_id = :rpc_acct_l1a and security_id = :l1a_asset)::bigint,
  1::bigint,
  '(l1-2) A reads back exactly the one bound account_trans row it just created (non-vacuous: RLS is not over-restrictive)'
);
select set_config('role', 'postgres', true);

-- (l1-3) STRUCTURAL: the #7 fence trigger (017 fn_account_trans_security_asset)
--   is still bound + enabled on pfin.account_trans.
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
  '(l1-3) STRUCTURAL: the 017 #7 fence trigger (account_trans_security_asset) is still bound + enabled on pfin.account_trans — SELF-325 makes cross-tenant binding unreachable BY CONSTRUCTION (no asset_id in p_positions), so this catalog check is the only observer that the fence itself was not silently dropped'
);

-- (l1-4) cross-tenant read fails closed: B sees 0 of A's position-asset rows.
select _rls.expect_cross_tenant_read_empty('pfin.asset'::regclass, :'ta'::uuid, :'tb'::uuid);

-- (l1-5) cross-tenant read fails closed: B sees 0 eod_price rows for A's position
--   asset (eod_price has no own users_id -> asset-anchored; the generic verb
--   doesn't apply).
select _rls.set_tenant(:'tb'::uuid);
select is(
  (select count(*) from pfin.eod_price where asset_id = :l1a_asset)::bigint,
  0::bigint,
  '(l1-5) cross-tenant read fails closed: B sees 0 eod_price rows for A''s RPC-created position asset (019 eod_price_select asset-JOIN scope)'
);

-- (l1-6) cross-tenant read fails closed: B sees 0 of A's account_trans rows.
select is(
  (select count(*) from pfin.account_trans where account_id = :rpc_acct_l1a)::bigint,
  0::bigint,
  '(l1-6) cross-tenant read fails closed: B sees 0 of A''s account_trans rows (006 rd_access-JOIN)'
);

-- (l1-7) B's own RPC call creates a B-owned asset (mirrors 013 (2a), extended to
--   the position-asset surface).
select pfin.fn_create_manual_account(
  'L1 B acct', 'depository', 'household', 'taxable', 300.00, '2026-04-01',
  '[{"asset_type":"equity","name":"L1 B Position","quantity":3,"cost_basis":300}]'::jsonb
) as rpc_acct_l1b \gset
select security_id as l1b_asset from pfin.account_trans
  where account_id = :rpc_acct_l1b and security_id is not null \gset
select is(
  (select users_id from pfin.asset where asset_id = :l1b_asset),
  :'tb'::uuid,
  '(l1-7) B''s own RPC call creates a B-owned position asset (users_id = auth.uid() = B — caller-bound, mirrors 013 (2a))'
);
select set_config('role', 'postgres', true);

-- (l1-8) exactly ONE fn_create_manual_account overload exists (7-arg; the 6-arg
--   was DROPped, not overloaded — no signature ambiguity).
select is(
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'pfin' and p.proname = 'fn_create_manual_account')::bigint,
  1::bigint,
  '(l1-8) exactly ONE fn_create_manual_account overload exists in pg_proc (7-arg; the 6-arg was DROPped, not overloaded) — no signature ambiguity'
);

-- (l1-9) INVOKER, not DEFINER (prosecdef=false) — DEFINER allowlist unaffected.
select is(
  (select p.prosecdef from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'pfin' and p.proname = 'fn_create_manual_account'),
  false,
  '(l1-9) fn_create_manual_account is SECURITY INVOKER (prosecdef=false) — DEFINER allowlist stays unchanged'
);

-- (l1-10)/(l1-11) — architect-requested watcher on the body's own
--   auth.uid()-IS-NULL guard: an RLS-EXEMPT caller (role=postgres — superuser
--   bypasses the EXECUTE grant entirely; a DIFFERENT threat class from anon,
--   which never reaches the body at all — 013's (6a)/(7) and 048's (6)/(7)
--   legs watch THAT, not this) with NO JWT claims set, so auth.uid() IS NULL.
--   Explicitly clear request.jwt.claims first — role=postgres is already
--   active from (l1-8)/(l1-9), but a STALE claim from an earlier
--   _rls.set_tenant call in this transaction would otherwise leak a real
--   tenant's auth.uid() into the probe and silently pass. ⚠ auth.uid() reads
--   request.jwt.claim.sub FIRST, falling back to the plural request.jwt.claims
--   — this probe is sound today because nothing in this file or
--   _rls.set_tenant ever sets the singular form, but it would silently stop
--   being sound if a future fixture did (Architect, measured — noted here so
--   the next author of a fixture in this family sees it before hitting it).
--
--   MEASURED (Architect's inversion test — the guard removed from a copy of
--   the function, battery re-run): (l1-10) goes RED without the guard — it IS
--   the observer. (l1-11) stays GREEN either way — it is NOT independently
--   detective. The reason is upstream of the guard: pfin.account.users_id is
--   NOT NULL, so an RLS-exempt call already fails at statement (1) (the
--   account INSERT, 23502) before ever reaching the position-asset INSERT the
--   guard was originally believed to protect — the account INSERT's own
--   NOT NULL constraint was ALREADY the backstop on this path, guard or not
--   (087's original header claim was wrong; corrected there and retracted to
--   Sec). What the guard actually buys: FAILING EARLY AND LEGIBLY with a
--   named, function-specific error instead of an incidental NOT NULL
--   violation on an unrelated table, and pinning the caller-context
--   requirement inside the function that needs it rather than borrowing it
--   from account's own constraint. (l1-11) is kept as a companion
--   no-partial-write sanity check, NOT as a second detector of the guard.
--
--   PRECISION NOTE (Sec): (l1-10) is deliberately pinned to the GUARD'S OWN
--   message text, not a bare throws_ok/SQLSTATE. A bare throws_ok would be
--   VACUOUS here — the call throws EITHER WAY (23502 from account's NOT NULL
--   if the guard were removed, the guard's own error if present) — so only a
--   message-text match distinguishes "the guard fired" from "something else,
--   downstream, fired instead." This is the same discipline every other
--   body-owned leg in this file follows; it is stated explicitly here because
--   this is the one leg where the alternative (no guard) ALSO throws, which
--   makes the vacuity risk concrete rather than hypothetical.
select set_config('request.jwt.claims', '', true);
select throws_like(
  $$ select pfin.fn_create_manual_account('L1 unauth attempt','depository','household','taxable',
       10, '2026-04-01', '[{"asset_type":"equity","name":"unauth-pos","quantity":1,"cost_basis":10}]'::jsonb) $$,
  'fn_create_manual_account requires an authenticated caller: auth.uid() is NULL. This RPC is SECURITY%',
  '(l1-10) RLS-EXEMPT caller (role=postgres, no JWT claims => auth.uid() IS NULL) is REJECTED by the body''s explicit auth-guard — MEASURED as the actual observer (inversion-tested: removing the guard flips this RED; see the block comment for what the guard does NOT catch)'
);
select is(
  (select count(*) from pfin.asset where name = 'unauth-pos' and users_id is null)::bigint,
  0::bigint,
  '(l1-11) companion, NOT independently detective (measured): no orphan GLOBAL (users_id IS NULL) pfin.asset row named ''unauth-pos'' exists after the rejected call — but pfin.account.users_id NOT NULL already blocks this upstream of the guard; kept as a no-partial-write sanity check, not a second watcher on the guard'
);

-- =====================================================================
-- L2 — pending-classification set: the new asset appears EXACTLY ONCE, USD
--   never appears (F1 watcher).
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);

select pfin.fn_create_manual_account(
  'L2 A acct', 'depository', 'household', 'taxable', 50.00, '2026-04-02',
  '[{"asset_type":"equity","name":"L2 A Position","quantity":2,"cost_basis":200}]'::jsonb
) as rpc_acct_l2 \gset
select security_id as l2_asset from pfin.account_trans
  where account_id = :rpc_acct_l2 and security_id is not null \gset

-- (l2-1) WRITE-level exactly-once: only ONE account_trans row is bound to the
--   new position asset (guards a double-row F2 variant).
select is(
  (select count(*) from pfin.account_trans where security_id = :l2_asset)::bigint,
  1::bigint,
  '(l2-1) exactly ONE account_trans row is bound to the new position asset (write-level; guards a double-row F2 variant)'
);

-- (l2-2) DERIVED-SET exactly-once: the self200 anti-join (ever-transacted MINUS
--   classified) contains the new asset exactly once.
select is(
  (select count(*) from (
     select distinct t.security_id from pfin.account_trans t
      where t.security_id is not null
        and t.security_id not in (select c.asset_id from pfin.user_asset_category c)
   ) s where s.security_id = :l2_asset)::bigint,
  1::bigint,
  '(l2-2) the derived pending-classification set (pendingSymbols.ts anti-join shape) contains the new position asset EXACTLY ONCE'
);

-- (l2-3) F1 watcher: the global USD currency-asset does NOT appear in A's
--   pending set.
select is(
  (select :g_usd = any(
     select distinct t.security_id from pfin.account_trans t
      where t.security_id is not null
        and t.security_id not in (select c.asset_id from pfin.user_asset_category c))),
  false,
  '(l2-3) F1 watcher: the global USD currency-asset does NOT appear in A''s pending-classification set — cash stays amount-carried, never instrument-bound'
);
select set_config('role', 'postgres', true);

-- (l2-4) cross-tenant: B's pending set does not include A's new asset.
select _rls.set_tenant(:'tb'::uuid);
select is(
  (select count(*) from (
     select distinct t.security_id from pfin.account_trans t
      where t.security_id is not null
        and t.security_id not in (select c.asset_id from pfin.user_asset_category c)
   ) s where s.security_id = :l2_asset)::bigint,
  0::bigint,
  '(l2-4) B''s derived pending-classification set does NOT include A''s new position asset'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- L3 — F2 double-count watcher. Exactly-divisible fixture (500/5=100.00 exact).
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);

select pfin.fn_create_manual_account(
  'L3 A acct', 'depository', 'household', 'taxable', 300.00, '2026-04-03',
  '[{"asset_type":"equity","name":"L3 A Position","quantity":5,"cost_basis":500}]'::jsonb
) as rpc_acct_l3 \gset
select security_id as l3_asset from pfin.account_trans
  where account_id = :rpc_acct_l3 and security_id is not null \gset

-- (l3-1) F2 DIRECT DETECTOR: fn_account_cash_as_of = EXACTLY the cash remainder
--   (300.00), NOT cash+cost_basis (800.00).
select is(
  (select balance_native from pfin.fn_account_cash_as_of('2026-04-03'::date)
     where account_id = :rpc_acct_l3),
  300.00::numeric,
  '(l3-1) F2 DIRECT DETECTOR: fn_account_cash_as_of = EXACTLY the cash remainder (300.00), not remainder+cost_basis (800.00) — RED iff the position acct_setup row carries amount <> 0'
);

-- (l3-2) holdings roll-forward sees the position quantity.
select is(
  (select quantity from pfin.fn_holdings_as_of('2026-04-03'::date)
     where account_id = :rpc_acct_l3 and asset_id = :l3_asset),
  5::numeric,
  '(l3-2) fn_holdings_as_of returns the position quantity (5) for (L3 account, L3 asset)'
);

-- (l3-3) seam parity — Σ fn_subcat_market_value(as_of,true) = fn_compute_nav(as_of)
--   for A, at an as_of covering every position created so far (L1+L2+L3).
--   Legitimate 086-ratified invariant, but NOT itself an F2 detector (both sides
--   share fn_account_cash_as_of/fn_holdings_as_of — a shared double-count
--   pollutes both identically). (l3-1) is the actual F2 detector; this proves
--   the classification-layer read composes correctly on top of it.
select is(
  (select coalesce(sum(market_value), 0) from pfin.fn_subcat_market_value('2026-04-03'::date, true)),
  (select pfin.fn_compute_nav('2026-04-03'::date)),
  '(l3-3) seam parity: Σ fn_subcat_market_value(as_of, true) = fn_compute_nav(as_of) for A after create-with-positions (086-ratified invariant; NOT itself an F2 detector — see (l3-1))'
);

-- (l3-4) non-vacuous companion: fn_compute_nav is NOT zero (guards (l3-3)
--   against a vacuous 0=0 pass — e.g. eod_price never resolving).
select ok(
  (select pfin.fn_compute_nav('2026-04-03'::date)) <> 0,
  '(l3-4) non-vacuous: fn_compute_nav(as_of) for A is NOT zero (guards (l3-3) against a vacuous 0=0 pass)'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- L4 — F3 watcher: a bound position's price row must EXIST and be USABLE
--   (resolvable AND positive-valued — a price=0.0000 row exists but is worth
--   nothing, and is F3's actual failure mode, not merely a missing row).
-- =====================================================================
-- (l4-1) BLANKET, privileged, ALL TENANTS: every acct_setup row with
--   security_id NOT NULL has a resolvable, POSITIVE-VALUED eod_price
--   (source=manual_valuation, price_date <= transaction_date, price > 0).
--   Covers L1(A)+L1(B)+L2(A)+L3(A) = 4 rows (+ whatever L5's price-floor leg
--   below adds, once Architect's clearance-(a) guard makes that row
--   unreachable rather than merely present-but-zero).
--   SEC-CORRECTED (clearance (b)): the ORIGINAL query asserted only that a
--   matching eod_price ROW existed — a row with price=0.0000 satisfies 019's
--   NaN-only CHECK (no positivity constraint) and would have passed this
--   watcher while still contributing $0 to NAV, which is the EXACT failure
--   F3 exists to catch. `and ep.price > 0` makes this observe the VALUE, not
--   merely the row's existence. The exactly-divisible L3/L4 fixtures can't
--   surface this on their own (their ratios never round to zero) — this is
--   why L5's new price-floor leg exists: it is what actually exercises the
--   defect Sec found (quantity ~ 1,000,000 against a small cost_basis rounds
--   round(cost_basis/quantity,4) to 0.0000).
select is(
  (select count(*) from pfin.account_trans t
     where t.security_id is not null
       and t.transaction_type = 'acct_setup'
       and not exists (
         select 1 from pfin.eod_price ep
         where ep.asset_id = t.security_id
           and ep.source = 'manual_valuation'
           and ep.price_date <= t.transaction_date
           and ep.price > 0
       ))::bigint,
  0::bigint,
  '(l4-1) BLANKET F3 watcher: every instrument-bound acct_setup row (all tenants) has a resolvable manual_valuation eod_price at or before its transaction_date, AND that price is > 0 (SEC-CORRECTED — observes the VALUE, not just the row''s existence; a price=0.0000 row satisfies 019''s NaN-only CHECK and would otherwise pass this watcher while still zeroing the position''s NAV contribution) — zero orphans'
);

-- (l4-2) F3 DIRECT VALUE DETECTOR: L3's account current_market_value = cash(300)
--   + cost_basis(500) = 800.00 — NOT cash alone (300). current_market_value is
--   populated for ALL account_type values (049/056 live definition); only
--   cost_basis/unrealized_gl are type-gated to investment/retirement/crypto —
--   not asserted here (account_type is 'depository').
select _rls.set_tenant(:'ta'::uuid);
select is(
  (select current_market_value from pfin.fn_account_unrealized_gl('2026-04-03'::date)
     where account_id = :rpc_acct_l3),
  800.00::numeric,
  '(l4-2) F3 DIRECT DETECTOR: fn_account_unrealized_gl.current_market_value for L3''s account = cash(300) + cost_basis(500) = 800.00 — RED (would read 300.00) iff the eod_price write is ever dropped from the RPC body'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- L5 — the $0 path stays first-class (omitted / '[]' / NULL) + the Lock 14
--   adversarial-numeric matrix + the individual body-owned guards + atomicity.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);

-- baselines, captured BEFORE any L5 call.
select
  (select count(*) from pfin.asset where users_id = :'ta') as l5_baseline_asset,
  (select count(*) from pfin.account where users_id = :'ta') as l5_baseline_account
\gset

-- (l5-1) p_positions OMITTED (6-arg call — the default absorbs it).
select pfin.fn_create_manual_account(
  'L5 omitted', 'depository', 'household', 'taxable', 111.00, '2026-04-04'
) as rpc_acct_l5a \gset
select is(
  (select count(*) from pfin.account_trans
     where account_id = :rpc_acct_l5a and security_id is null and amount = 111.00)::bigint,
  1::bigint,
  '(l5-1) $0 path (p_positions OMITTED): exactly one security_id-NULL acct_setup row, amount = p_initial_value'
);
select is(
  (select count(*) from pfin.account_trans where account_id = :rpc_acct_l5a)::bigint,
  1::bigint,
  '(l5-1v) $0 path (omitted): exactly ONE account_trans row total — no stray position row'
);

-- (l5-2) p_positions = '[]'::jsonb explicit.
select pfin.fn_create_manual_account(
  'L5 empty array', 'depository', 'household', 'taxable', 112.00, '2026-04-04', '[]'::jsonb
) as rpc_acct_l5b \gset
select is(
  (select count(*) from pfin.account_trans
     where account_id = :rpc_acct_l5b and security_id is null and amount = 112.00)::bigint,
  1::bigint,
  '(l5-2) $0 path (p_positions = ''[]''::jsonb): exactly one security_id-NULL acct_setup row'
);

-- (l5-3) p_positions = NULL (architect-confirmed: behaves identically to
--   omitted/'[]').
select pfin.fn_create_manual_account(
  'L5 null positions', 'depository', 'household', 'taxable', 113.00, '2026-04-04', null::jsonb
) as rpc_acct_l5c \gset
select is(
  (select count(*) from pfin.account_trans
     where account_id = :rpc_acct_l5c and security_id is null and amount = 113.00)::bigint,
  1::bigint,
  '(l5-3) $0 path (p_positions = NULL): exactly one security_id-NULL acct_setup row'
);

-- (l5-4) zero new pfin.asset rows from the three $0-path calls.
select is(
  (select count(*) from pfin.asset where users_id = :'ta')::bigint,
  :l5_baseline_asset::bigint,
  '(l5-4) the three $0-path calls (omitted/[]/NULL) create ZERO new pfin.asset rows'
);

-- (l5-5) exactly 3 new pfin.account rows from the three $0-path calls (one each,
--   no more no less).
select is(
  (select count(*) from pfin.account where users_id = :'ta')::bigint,
  (:l5_baseline_account + 3)::bigint,
  '(l5-5) the three $0-path calls create exactly 3 new pfin.account rows (one each)'
);

-- ---------------------------------------------------------------------
-- Adversarial-numeric matrix (Lock 14 DB backstop on p_positions[1].quantity /
--   .cost_basis). Message-ownership per the header table above.
-- ---------------------------------------------------------------------

-- quantity: quoted "NaN" -> JSON-type-check guard.
select throws_like(
  $$ select pfin.fn_create_manual_account('L5 rej qty nan','depository','household','taxable',
       10, '2026-04-05', '[{"asset_type":"equity","name":"qty-nan","quantity":"NaN","cost_basis":10}]'::jsonb) $$,
  'p_positions[1].quantity must be a JSON number (unquoted). Quoted values%',
  '(l5-q-nan) quantity="NaN" (quoted) rejected by the JSON-type-check guard'
);
-- quantity: quoted "Infinity".
select throws_like(
  $$ select pfin.fn_create_manual_account('L5 rej qty inf','depository','household','taxable',
       10, '2026-04-05', '[{"asset_type":"equity","name":"qty-inf","quantity":"Infinity","cost_basis":10}]'::jsonb) $$,
  'p_positions[1].quantity must be a JSON number (unquoted). Quoted values%',
  '(l5-q-inf) quantity="Infinity" (quoted) rejected by the JSON-type-check guard'
);
-- quantity: quoted "-Infinity".
select throws_like(
  $$ select pfin.fn_create_manual_account('L5 rej qty neginf','depository','household','taxable',
       10, '2026-04-05', '[{"asset_type":"equity","name":"qty-neginf","quantity":"-Infinity","cost_basis":10}]'::jsonb) $$,
  'p_positions[1].quantity must be a JSON number (unquoted). Quoted values%',
  '(l5-q-neginf) quantity="-Infinity" (quoted) rejected by the JSON-type-check guard'
);
-- quantity: currency-formatted string.
select throws_like(
  $$ select pfin.fn_create_manual_account('L5 rej qty dollar','depository','household','taxable',
       10, '2026-04-05', '[{"asset_type":"equity","name":"qty-dollar","quantity":"$1,000","cost_basis":10}]'::jsonb) $$,
  'p_positions[1].quantity must be a JSON number (unquoted). Quoted values%',
  '(l5-q-dollar) quantity="$1,000" (currency-formatted string) rejected by the JSON-type-check guard'
);
-- quantity: locale-formatted string.
select throws_like(
  $$ select pfin.fn_create_manual_account('L5 rej qty locale','depository','household','taxable',
       10, '2026-04-05', '[{"asset_type":"equity","name":"qty-locale","quantity":"1.000,50","cost_basis":10}]'::jsonb) $$,
  'p_positions[1].quantity must be a JSON number (unquoted). Quoted values%',
  '(l5-q-locale) quantity="1.000,50" (locale-formatted string) rejected by the JSON-type-check guard'
);
-- quantity: missing key entirely.
select throws_like(
  $$ select pfin.fn_create_manual_account('L5 rej qty missing','depository','household','taxable',
       10, '2026-04-05', '[{"asset_type":"equity","name":"qty-missing","cost_basis":10}]'::jsonb) $$,
  'p_positions[1].quantity must be a JSON number (unquoted). Quoted values%',
  '(l5-q-missing) quantity key ABSENT rejected by the same JSON-type-check guard (jsonb_typeof of a missing key <> ''number'')'
);
-- quantity: zero.
select throws_like(
  $$ select pfin.fn_create_manual_account('L5 rej qty zero','depository','household','taxable',
       10, '2026-04-05', '[{"asset_type":"equity","name":"qty-zero","quantity":0,"cost_basis":10}]'::jsonb) $$,
  'p_positions[1].quantity must be a finite number greater than zero, got%',
  '(l5-q-zero) quantity=0 rejected by the explicit positivity guard'
);
-- quantity: negative.
select throws_like(
  $$ select pfin.fn_create_manual_account('L5 rej qty neg','depository','household','taxable',
       10, '2026-04-05', '[{"asset_type":"equity","name":"qty-neg","quantity":-5,"cost_basis":10}]'::jsonb) $$,
  'p_positions[1].quantity must be a finite number greater than zero, got%',
  '(l5-q-neg) quantity=-5 rejected by the explicit positivity guard'
);
-- quantity: 1e400. LAYER MOVED (SEC clearance (a) — measured by Architect,
--   confirmed here): this fixture (quantity=1e400, cost_basis=10) used to
--   reach 017's numeric(28,8) column coercion (22003) FIRST, because nothing
--   upstream rejected it. Now Architect's new zero-price fence (round(
--   cost_basis/quantity,4) <= 0, inserted between price computation and the
--   eod_price write) fires FIRST instead — 10/1e400 rounds to 0.0000 — and
--   raises P0001 with the SAME message as (l5-price-floor) below, BEFORE the
--   column is ever reached. This is NOT a fixture choice we can route around:
--   ANY numeric cost_basis representable in a numeric(20,4) column divided by
--   1e400 also rounds to 0 (the column's own ~10^16 ceiling is astronomically
--   smaller than what would be needed to keep the ratio non-zero against a
--   1e400 quantity), so 017's column-overflow layer is NOT independently
--   observable at this magnitude any more — the body-owned fence is now the
--   layer that actually catches it, and pinning "assert rejection only, not
--   message text" here would be documenting a layer this case no longer
--   exercises. Re-targeted to the SAME message-ownership treatment as every
--   other body-owned guard in this file (exact prefix, not SQLSTATE-only).
--   ⚠ (l5-c-overflow) immediately below proves 017's numeric(20,4)
--   COST_BASIS column overflows at 1e400 — a DIFFERENT column with a
--   DIFFERENT integer-digit ceiling (16 vs quantity's 20, numeric(28,8)) — it
--   does NOT stand in for the quantity column. Moving THIS leg off that layer
--   left 017's quantity-column overflow with NO observer at all anywhere in
--   this file (Architect, caught before commit). (l5-q-column-overflow)
--   below restores it via the narrow fixture window where the fence does
--   NOT win: quantity must clear numeric(28,8)'s ~1e20 ceiling while
--   cost_basis stays under the zero-price floor (cost_basis >= quantity x
--   0.00005) AND under its OWN numeric(20,4) ~1e16 ceiling — measured window
--   at quantity=1e20: cost_basis in [5e15, 1e16].
select throws_like(
  $$ select pfin.fn_create_manual_account('L5 rej qty overflow','depository','household','taxable',
       10, '2026-04-05', '[{"asset_type":"equity","name":"qty-overflow","quantity":1e400,"cost_basis":10}]'::jsonb) $$,
  'p_positions[1] derives a price of 0.0000 and would value at zero: cost_basis%',
  '(l5-q-overflow) quantity=1e400 / cost_basis=10 (rounds to price=0.0000): LAYER MOVED — now caught by the body''s zero-price fence (P0001), NOT 017''s column coercion (22003) — no cost_basis choice keeps this case on the old layer, see block comment'
);

-- (l5-q-column-overflow) restores the quantity-column (numeric(28,8))
--   observer the re-target above removed. quantity=1e20 clears the column's
--   ~1e20 integer-digit ceiling; cost_basis=1e16 sits inside the narrow
--   window that BOTH clears the zero-price floor (1e16 >= 1e20 x 0.00005 =
--   5e15) AND stays under cost_basis's OWN numeric(20,4) ~1e16 ceiling —
--   measured by Architect: 22003, the fence does NOT fire here. NOT
--   body-owned; assert rejection only, per the same discipline as every
--   other catalog-owned leg in this file.
select throws_ok(
  $$ select pfin.fn_create_manual_account('L5 rej qty column overflow','depository','household','taxable',
       10, '2026-04-05', '[{"asset_type":"equity","name":"qty-col-overflow","quantity":1e20,"cost_basis":1e16}]'::jsonb) $$,
  '22003', null,
  '(l5-q-column-overflow) quantity=1e20 (clears 017''s numeric(28,8) ceiling) with cost_basis=1e16 (inside the narrow window that also clears the zero-price floor) rejected at 22003 — restores independent observation of the quantity column, which (l5-q-overflow)''s re-target left uncovered'
);

-- cost_basis: mirror the same 9-variant matrix.
select throws_like(
  $$ select pfin.fn_create_manual_account('L5 rej cb nan','depository','household','taxable',
       10, '2026-04-05', '[{"asset_type":"equity","name":"cb-nan","quantity":1,"cost_basis":"NaN"}]'::jsonb) $$,
  'p_positions[1].cost_basis must be a JSON number (unquoted). Quoted values%',
  '(l5-c-nan) cost_basis="NaN" (quoted) rejected by the JSON-type-check guard'
);
select throws_like(
  $$ select pfin.fn_create_manual_account('L5 rej cb inf','depository','household','taxable',
       10, '2026-04-05', '[{"asset_type":"equity","name":"cb-inf","quantity":1,"cost_basis":"Infinity"}]'::jsonb) $$,
  'p_positions[1].cost_basis must be a JSON number (unquoted). Quoted values%',
  '(l5-c-inf) cost_basis="Infinity" (quoted) rejected by the JSON-type-check guard'
);
select throws_like(
  $$ select pfin.fn_create_manual_account('L5 rej cb neginf','depository','household','taxable',
       10, '2026-04-05', '[{"asset_type":"equity","name":"cb-neginf","quantity":1,"cost_basis":"-Infinity"}]'::jsonb) $$,
  'p_positions[1].cost_basis must be a JSON number (unquoted). Quoted values%',
  '(l5-c-neginf) cost_basis="-Infinity" (quoted) rejected by the JSON-type-check guard'
);
select throws_like(
  $$ select pfin.fn_create_manual_account('L5 rej cb dollar','depository','household','taxable',
       10, '2026-04-05', '[{"asset_type":"equity","name":"cb-dollar","quantity":1,"cost_basis":"$1,000"}]'::jsonb) $$,
  'p_positions[1].cost_basis must be a JSON number (unquoted). Quoted values%',
  '(l5-c-dollar) cost_basis="$1,000" (currency-formatted string) rejected by the JSON-type-check guard'
);
select throws_like(
  $$ select pfin.fn_create_manual_account('L5 rej cb locale','depository','household','taxable',
       10, '2026-04-05', '[{"asset_type":"equity","name":"cb-locale","quantity":1,"cost_basis":"1.000,50"}]'::jsonb) $$,
  'p_positions[1].cost_basis must be a JSON number (unquoted). Quoted values%',
  '(l5-c-locale) cost_basis="1.000,50" (locale-formatted string) rejected by the JSON-type-check guard'
);
select throws_like(
  $$ select pfin.fn_create_manual_account('L5 rej cb missing','depository','household','taxable',
       10, '2026-04-05', '[{"asset_type":"equity","name":"cb-missing","quantity":1}]'::jsonb) $$,
  'p_positions[1].cost_basis must be a JSON number (unquoted). Quoted values%',
  '(l5-c-missing) cost_basis key ABSENT rejected by the same JSON-type-check guard'
);
select throws_like(
  $$ select pfin.fn_create_manual_account('L5 rej cb zero','depository','household','taxable',
       10, '2026-04-05', '[{"asset_type":"equity","name":"cb-zero","quantity":1,"cost_basis":0}]'::jsonb) $$,
  'p_positions[1].cost_basis must be a finite number greater than zero, got%',
  '(l5-c-zero) cost_basis=0 rejected by the explicit positivity guard'
);
select throws_like(
  $$ select pfin.fn_create_manual_account('L5 rej cb neg','depository','household','taxable',
       10, '2026-04-05', '[{"asset_type":"equity","name":"cb-neg","quantity":1,"cost_basis":-5}]'::jsonb) $$,
  'p_positions[1].cost_basis must be a finite number greater than zero, got%',
  '(l5-c-neg) cost_basis=-5 rejected by the explicit positivity guard'
);
select throws_ok(
  $$ select pfin.fn_create_manual_account('L5 rej cb overflow','depository','household','taxable',
       10, '2026-04-05', '[{"asset_type":"equity","name":"cb-overflow","quantity":1,"cost_basis":1e400}]'::jsonb) $$,
  '22003', null,
  '(l5-c-overflow) cost_basis=1e400 rejected at 017''s numeric(20,4) column coercion (22003) — NOT the body; assert rejection only'
);

-- (l5-price-floor) SEC CLEARANCE (c): quantity=1,000,000 against cost_basis=
--   10.00 rounds round(cost_basis/quantity,4) to 0.0000 — a $0-priced position
--   the PRE-CLEARANCE body would have silently ACCEPTED. This is F3's actual
--   defect, more precisely than L4's original framing: not a MISSING
--   eod_price row, a ZERO-VALUED one that 019's NaN-only CHECK admits (no
--   positivity constraint). Sec's ask, stated exactly: assert the RPC RAISES
--   (not that it succeeds with a caveat). This leg is the F3-completeness
--   counterpart to (l4-1)'s corrected `and ep.price > 0` clause — that clause
--   detects a zero-priced row if one lands; THIS leg proves one can no longer
--   land at all, once Architect's clearance-(a) guard
--   (round(cost_basis/quantity,4) <= 0 rejected in the body) is committed.
--   Message verified live by Architect against the fenced function (SQLSTATE
--   P0001); pattern truncates before the %-interpolated cost_basis/quantity
--   values so it can't break on numeric formatting.
select throws_like(
  $$ select pfin.fn_create_manual_account('L5 rej price floor','depository','household','taxable',
       10, '2026-04-05', '[{"asset_type":"equity","name":"price-floor","quantity":1000000,"cost_basis":10.00}]'::jsonb) $$,
  'p_positions[1] derives a price of 0.0000 and would value at zero: cost_basis%',
  '(l5-price-floor) SEC CLEARANCE (c): quantity=1,000,000 / cost_basis=10.00 (rounds to price=0.0000) is REJECTED by the body — not silently accepted at a zero-valued price'
);

-- individual body-owned guards.
select throws_like(
  $$ select pfin.fn_create_manual_account('L5 rej currency','depository','household','taxable',
       10, '2026-04-05', '[{"asset_type":"currency","name":"usd-bound","quantity":1,"cost_basis":10}]'::jsonb) $$,
  'p_positions[1].asset_type may not be ''currency'': cash is amount-carried, not i%',
  '(l5-currency) F1 guard: asset_type=''currency'' rejected — cash must never be instrument-bound'
);
select throws_like(
  $$ select pfin.fn_create_manual_account('L5 rej name missing','depository','household','taxable',
       10, '2026-04-05', '[{"asset_type":"equity","quantity":1,"cost_basis":10}]'::jsonb) $$,
  'p_positions[1].name must be a JSON string.',
  '(l5-noname) missing name key rejected'
);
select throws_like(
  $$ select pfin.fn_create_manual_account('L5 rej name empty','depository','household','taxable',
       10, '2026-04-05', '[{"asset_type":"equity","name":"","quantity":1,"cost_basis":10}]'::jsonb) $$,
  'p_positions[1].name must not be empty.',
  '(l5-emptyname) empty-string name rejected'
);
select throws_like(
  $$ select pfin.fn_create_manual_account('L5 rej nonarray','depository','household','taxable',
       10, '2026-04-05', '{"asset_type":"equity","name":"x","quantity":1,"cost_basis":10}'::jsonb) $$,
  'p_positions must be a JSON array of opening positions, got object.%',
  '(l5-nonarray) non-array p_positions (a bare JSON object) rejected'
);
select throws_like(
  $$ select pfin.fn_create_manual_account('L5 rej nonobject','depository','household','taxable',
       10, '2026-04-05', '["not an object"]'::jsonb) $$,
  'p_positions[1] must be a JSON object, got string.',
  '(l5-nonobject) a non-object p_positions array element (a JSON string) rejected'
);
select throws_ok(
  $$ select pfin.fn_create_manual_account('L5 rej badvocab','depository','household','taxable',
       10, '2026-04-05', '[{"asset_type":"not_a_real_type","name":"bogus","quantity":1,"cost_basis":10}]'::jsonb) $$,
  '23514', null,
  '(l5-badvocab) asset_type outside 016''s vocab entirely rejected at asset_asset_type_check (23514) — NOT the body; assert rejection only'
);
select throws_ok(
  $$ select pfin.fn_create_manual_account('L5 rej dupname','depository','household','taxable',
       10, '2026-04-05', '[{"asset_type":"equity","name":"dup","quantity":1,"cost_basis":10},
                           {"asset_type":"equity","name":"dup","quantity":2,"cost_basis":20}]'::jsonb) $$,
  '23505', null,
  '(l5-dupname) a duplicate position name within ONE payload rejected at 016''s asset_user_name_uniq (23505) — NOT the body; assert rejection only'
);

-- (l5-atomicity-account) LOAD-BEARING: after ALL ~25 rejected calls above, A''s
--   pfin.account count is STILL exactly baseline+3 (the 3 accepted $0-path
--   calls) — zero orphan accounts from any rejection. This is the property
--   that makes Option 2 (atomic RPC) beat app-layer composition.
select is(
  (select count(*) from pfin.account where users_id = :'ta')::bigint,
  (:l5_baseline_account + 3)::bigint,
  '(l5-atomicity-account) LOAD-BEARING ATOMICITY: after every rejected L5 call, A''s pfin.account count is STILL baseline+3 — ZERO orphan accounts from any rejection'
);

-- (l5-atomicity-asset) companion: zero orphan pfin.asset rows either (guards a
--   partial-write where the asset INSERT commits before a later statement in
--   the same position's write sequence raises).
select is(
  (select count(*) from pfin.asset where users_id = :'ta')::bigint,
  :l5_baseline_asset::bigint,
  '(l5-atomicity-asset) companion atomicity: ZERO orphan pfin.asset rows from any rejected L5 call'
);
select set_config('role', 'postgres', true);

select * from finish();
rollback;
