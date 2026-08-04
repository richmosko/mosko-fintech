-- =====================================================================
-- 058 — ACCOUNT CLOSURE, PHASE 1 (ADR-042): the dated `closed_at` column, the three-leg
--        close gate, the `currency` conjunct, the transfer-in fences, and the transitional
--        `is_active` sync trigger.
-- =====================================================================
-- QA-owned. Authors NO schema. Pairs with Architect's `058`.
-- Sec joint-review-mandatory (financial calculation · multi-tenant isolation · new fences
-- on a privileged-context write path).
--
-- ⟦DESIGN: TWO-PHASE — Sec-adjudicated + Architect-confirmed 2026-08-03⟧
--   The DECLARED-SET mechanism is WITHDRAWN. This battery was originally authored against
--   it and BLOCK A has been deleted. Under two-phase:
--     `058` (this file) — `closed_at` + gate + currency conjunct + transfer-in fences +
--                         the transitional sync trigger. **`is_active` UNTOUCHED.**
--     operator step     — each inactive account is closed THROUGH THE REAL GATED CONTROL
--                         (which validates it) or reactivated.
--     `059`             — assert the biconditional, drop the assert function, drop
--                         `is_active`, then the as-of re-point. See 059_*_rls.sql.
--   WHY IT WINS, and it changes what this file proves: the migration-time check stops being
--   a PROXY for the gate and BECOMES the gate — the actual trigger, per account. Sec's
--   standing requirement was "the migration's check must BE the gate's check"; two-phase
--   satisfies it literally rather than fencing a workaround. Every gate assertion below is
--   therefore now exercising THE PRODUCTION PATH, not an approximation of it (ADR-040 B9).
--
--   It also deletes a disclosure channel: no declared list means no cross-tenant
--   `account_id`s committed to a migration file and preserved in git history.
--
-- ┌─ WHY THIS FILE EXISTS ─────────────────────────────────────────────────────────────┐
-- │ `pfin.account` holds 4 rows, ALL ACTIVE — zero inactive (measured on the live local │
-- │ DB 2026-08-03). So on production data the operator step has NOTHING to disposition  │
-- │ and every closure fence ships UNEXERCISED — it evaluates, takes the pass branch, and│
-- │ reports success without ever having fired. A guard that never fires has never been  │
-- │ shown to fire; the same failure class as a `grep` pattern that cannot match         │
-- │ returning "clean" (ADR-042 checkpoint 7). This file seeds deliberate violators of   │
-- │ every shape and asserts each fence ABORTS on its own.                               │
-- └────────────────────────────────────────────────────────────────────────────────────┘
--
-- LAYER DISCIPLINE — three separate traps on this surface, all verified against the LIVE
--   catalog rather than assumed:
--   (1) NONE OF THESE FENCES IS RLS (Sec). They are BEFORE-trigger raises. An RLS-denial
--       assertion would go GREEN FOR THE WRONG REASON — RLS denies CROSS-TENANT, a
--       different property that holds independently and would keep holding if every fence
--       in this ADR were deleted. Every fence assertion below matches the RAISE TEXT.
--   (2) `account_balance_checkpoint` + `holdings_checkpoint` grant authenticated **SELECT
--       ONLY** (service_role holds SELECT+INSERT). An authenticated INSERT into either is
--       refused at the TABLE ACL before any trigger runs — a green that exercised the grant
--       and reported it as the fence. Both are therefore driven at **service_role** (C3/C4)
--       with the grant held open, so the TRIGGER is the sole gate (the `self209` (b3)/(b4)
--       grant-then-trigger pattern). `account_trans` DOES grant INSERT to authenticated,
--       so C1 runs there and asserts the trigger message.
--   (3) 42501 is ambiguous: schema-USAGE-denied, table-ACL-denied and RLS-WITH-CHECK are
--       ALL 42501. ACL denials are matched on 'permission denied for table X', RLS on
--       'new row violates row-level security policy%for table "X"'. A bare SQLSTATE match
--       would be satisfied by any of the three.
--   Sec also notes P0001 (raise_exception) is expected for the trigger raises — so a bare
--   P0001 match would pass on ANY raise, including an unrelated one. Hence message matching
--   throughout, never SQLSTATE alone.
--
-- ┌─ LAYER MAP — WHICH MECHANISM EACH ASSERTION ACTUALLY TARGETS ──────────────────────┐
-- │ Required by Sec 2026-08-03. The file was originally named `..._rls.sql`; that name  │
-- │ was WRONG and is why this block exists. **NOT ONE ASSERTION IN THIS FILE TARGETS    │
-- │ RLS.** An RLS-denial assertion here would go GREEN — RLS denies cross-tenant, a      │
-- │ property that holds independently and would keep holding if every trigger in this    │
-- │ ADR were deleted. A green that survives deleting the thing under test is not a test. │
-- │ Renamed `..._fences.sql` for that reason.                                            │
-- │                                                                                      │
-- │   BEFORE UPDATE trigger on pfin.account (the close gate)                             │
-- │     B1 · B2 · B3 · B4 · B6a · B6b · B7 · B8 · B9 · G2                                │
-- │   BEFORE UPDATE trigger, currency conjunct (D4)                                      │
-- │     B10 · B11a · B11b                                                                │
-- │   BEFORE INSERT triggers (transfer-in fences, 3 tables)                              │
-- │     C1 · C2 · C3 · C4 · C5a · C5b · C5c · G1                                         │
-- │   Transitional is_active sync trigger                                                │
-- │     S1 · S2a · S2b · S3 · S4a · S4b · S4c                                            │
-- │   Audit-row side effect (pfin.account_event insert)                                  │
-- │     B1b                                                                              │
-- │   pg_catalog / information_schema — structural, no runtime mechanism                 │
-- │     B5 · C6b · C7 · P1 · P2 · P3 · P5                                                │
-- │   CHECK constraint `account_closure_biconditional` — covers INSERT *and* UPDATE      │
-- │     P4                                                                               │
-- │   Table ACL — none in this file. Where a probe RUNS as `authenticated` (C1, S4a) it   │
-- │     asserts a TRIGGER raise or a successful write, never `permission denied`.         │
-- │                                                                                      │
-- │ ADDING A CASE: state its mechanism here first. If you cannot name one, the assertion │
-- │ is probably testing a property that holds without the fence.                         │
-- └────────────────────────────────────────────────────────────────────────────────────┘
--
-- CORRESPONDENCE (Sec's joint-review check — run on this file before sending): does at
--   least one assertion reference an object existing ONLY in the migration this battery
--   names? YES — `pfin.account.closed_at`, the close-gate trigger, and all three transfer-in
--   triggers are created in `058` and exist nowhere earlier. `P1` additionally FAILS against
--   `059` (which drops `is_active`), so this file discriminates in BOTH directions rather
--   than merely being present alongside the right migration.
--
-- ┌─ ⟦EXPECTED STACK⟧ — READ BEFORE INTERPRETING ANY RESULT FROM THIS FILE ──────────┐
-- │ **A RESULT FROM THIS BATTERY IS UNINTERPRETABLE WITHOUT THE MIGRATION SET IT RAN │
-- │ AGAINST.** A red cannot be distinguished from "this DB predates the change"; a    │
-- │ green cannot be distinguished from "this DB already had it". Report the applied   │
-- │ set alongside the result, every run — `select max(version) from                   │
-- │ supabase_migrations.schema_migrations;`                                           │
-- │                                                                                   │
-- │ EXPECTED STACK: `058`-applied.                                                      │
-- │ `closed_at` + close gate + currency conjunct + transfer-in fences + the transiti
-- │   onal sync trigger, with `is_active` STILL PRESENT. Below `058`: all RED (no co
-- │   lumn). At/above `059`: (P1) RED because `is_active` is gone — this file is onl
-- │   y meaningful in the `058`-applied, pre-`059` window.
-- │                                                                                   │
-- │ ⚠ SECOND STATE VARIABLE, added after it bit us: **WHICH BRANCH / WORKTREE.** A     │
-- │ FILE read is branch-dependent, so "I read the migration" is not a fixed referent   │
-- │ either. Cite migrations by COMMIT REF, never by working-tree path:                 │
-- │   git show <ref>:supabase/migrations/<file>                                        │
-- │ So a claim needs THREE coordinates, not one: DATABASE STATE (this block) +         │
-- │ ARTIFACT REF + the assertion itself. Two of the three bit this review.             │
-- │                                                                                   │
-- │ Convention follows `self209_close_gate.sql`'s ⟦WIRE-VALIDATE⟧ note. Generalized    │
-- │ to every file 2026-08-03 after I reported a pre-`056` database's expected red as   │
-- │ a code defect — the error was mine and this header is the fence on repeating it.   │
-- └───────────────────────────────────────────────────────────────────────────────────┘
--
-- POSTURE (SECURITY §4.5): SYNTHETIC ONLY — fixed-UUID tenants; NO PII / no real account
--   numbers (SD-15) / no real Plaid tokens (SD-03) / no prod data. Rolled-back txn.
--   This file requires NO `supabase db reset` and drops no column — it seeds and rolls back
--   in place. (The COLUMN DROP lives in `059`; see that file's scratch-DB note.)
--
-- ⟦FIXTURE-VERIFIED 2026-08-03⟧ The DDL does not exist yet, so NO assertion below has run.
--   What HAS run against the live local DB in a rolled-back txn: every seed statement, and
--   the three probes that give this file its discriminating power. Measured, not assumed:
--     · :unp (unpriced holding) → QUANTITY reads 10.00000000, MARKET VALUE reads 0. The
--       (B8) fail-open trap is REAL on this schema, not merely argued from the ADR.
--     · :asof                   → 800.0000 as of 2026-05-31, 0.0000 as of 2026-06-30.
--     · :tiny                   → 0.0001 survives numeric(20,4).
--   A fixture whose violators do not actually violate yields assertions that cannot fail.
--   One real defect was caught by that run: account_type 'brokerage' violates
--   account_account_type_check (vocabulary: depository/investment/retirement/crypto/
--   manual_other/real_estate/liability) — fixed to 'investment'.
--
-- ⟦WIRE — raise messages PROVISIONAL per Architect 2026-08-03⟧ bound ONCE below. Patterns
--   are held deliberately loose (the discriminating phrase only) until Architect pins the
--   literals in the DDL header. Rebind there, never inline.
-- =====================================================================

begin;

\ir ../_fixtures/rls_verbs.psql

-- ---------------------------------------------------------------------
-- ⟦WIRE⟧ Architect confirmed THREE DISTINGUISHABLE gate messages and PER-TABLE transfer-in
--   messages, for the reason (B5) asserts: an assertion that cannot identify which leg
--   fired proves less than it appears to. `054` is the cited distinct-message precedent.
-- ---------------------------------------------------------------------
-- ⟦WIRE-BOUND 2026-08-03 against the REAL DDL at `407b190` — verified by reading
--   `git show 407b190:supabase/migrations/058_account_closure.sql`, not from a summary.
--   THREE corrections the rebinding forced, all of which would have produced wrong results:
--     · the fence message interpolates `tg_table_name`, which is the BARE table name — my
--       patterns said `(pfin.account_trans)` and the actual text is `(account_trans)`.
--       A schema-qualified pattern matches NOTHING and every fence assertion goes red for
--       a reason unrelated to the fence.
--     · trigger names carry NO `trg_` prefix — see the inversion block.
--     · the gate has FOUR raises, not three. See (B4b).⟧
\set m_gate_holdings   '%closure blocked%leg 1 of 3: holdings%'
\set m_gate_cash       '%closure blocked%leg 2 of 3: cash%'
\set m_gate_activity   '%closure blocked%leg 3 of 3: post-closure activity%'
\set m_gate_future     '%closure blocked%future closed_at%not-in-the-future%'
\set m_fence_trans     '%write blocked%is closed (account_trans)%'
\set m_fence_bal       '%write blocked%is closed (account_balance_checkpoint)%'
\set m_fence_hold      '%write blocked%is closed (holdings_checkpoint)%'
\set m_currency_frozen '%currency is immutable on a closed account%'

-- plan = 40: BLOCK B 16 · C 10 · S 7 · P 5 · G 2. Recorded so a silent plan-edit — the
-- cheapest way to make a battery green — shows up in review as an arithmetic change.
select plan(40);

select _rls.tenant_a() as ta, _rls.tenant_b() as tb \gset

-- ---------------------------------------------------------------------
-- FIXTURE (PRIVILEGED postgres — RLS-bypassed; the sole seed path).
--   Each account isolates exactly ONE property of the gate.
-- ---------------------------------------------------------------------
insert into auth.users (id) values (:'ta'), (:'tb');

-- A global PRICED equity and a global UNPRICED equity. The unpriced one is the fail-open
-- trap: a MARKET-VALUE zero test drops its NULL price term via SUM and reads the account as
-- empty. Only a QUANTITY-based test sees it (ADR-042 D3: "price coverage is not a security
-- control"). Verified live: quantity 10.00000000 vs market value 0.
insert into pfin.asset (users_id, asset_type, pricing_source, symbol, name)
  values (null, 'equity', 'market_feed', 'QAPRC', 'Priced Equity') returning asset_id as a_priced \gset
insert into pfin.asset (users_id, asset_type, pricing_source, symbol, name)
  values (null, 'equity', 'market_feed', 'QAUNP', 'Unpriced Equity') returning asset_id as a_unpriced \gset
insert into pfin.eod_price (asset_id, price_date, source, price)
  values (:a_priced, '2026-01-31', 'market_feed', 100.0000);
-- NOTE: NO eod_price row for :a_unpriced. That absence IS the assertion surface.

insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'ta', 'zero-open', 'depository', 'household', 'taxable') returning account_id as z \gset
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'ta', 'nonzero-cash', 'depository', 'household', 'taxable') returning account_id as cash \gset
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'ta', 'nonzero-holdings', 'investment', 'household', 'taxable') returning account_id as hold \gset
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'ta', 'unpriced-holdings', 'investment', 'household', 'taxable') returning account_id as unp \gset
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'ta', 'asof-zeroed-in-june', 'depository', 'household', 'taxable') returning account_id as asof \gset
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'ta', 'activity-after', 'depository', 'household', 'taxable') returning account_id as post \gset
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'ta', 'sub-cent-residue', 'depository', 'household', 'taxable') returning account_id as tiny \gset
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'ta', 'stays-open', 'depository', 'household', 'taxable') returning account_id as open1 \gset

insert into pfin.account_balance_checkpoint (account_id, balance, currency, as_of_date, source)
  values (:cash, 500.0000, 'USD', '2026-01-31', 'seed');
insert into pfin.holdings_checkpoint (account_id, symbol, as_of_date, quantity, balance, security_id)
  values (:hold, 'QAPRC', '2026-01-31', 10, 1000, :a_priced);
insert into pfin.holdings_checkpoint (account_id, symbol, as_of_date, quantity, balance, security_id)
  values (:unp, 'QAUNP', '2026-01-31', 10, 0, :a_unpriced);
insert into pfin.account_balance_checkpoint (account_id, balance, currency, as_of_date, source)
  values (:asof, 800.0000, 'USD', '2026-04-30', 'seed');
insert into pfin.account_trans (account_id, transaction_date, amount, quantity, vendor)
  values (:asof, '2026-06-15', -800.0000, 0, 'zeroed');
insert into pfin.account_trans (account_id, transaction_date, amount, quantity, vendor)
  values (:post, '2026-07-10', 0.0000, 0, 'post-closure activity');
insert into pfin.account_balance_checkpoint (account_id, balance, currency, as_of_date, source)
  values (:tiny, 0.0001, 'USD', '2026-01-31', 'seed');

-- =====================================================================
-- BLOCK B — THE THREE-LEG CLOSE GATE  (Sec revised cases 1 + 2)
--   Invariant (ADR-042 D3): a closed account's position AS OF closed_at is zero, and no
--   activity is dated after closed_at. Enforced at the NULL -> NOT NULL transition.
--   Under two-phase these run through THE REAL PRODUCTION CONTROL — the BEFORE UPDATE
--   trigger on pfin.account — not a migration-time proxy of it.
-- =====================================================================

select _rls.set_tenant(:'ta'::uuid);

-- (B1) SEC CASE 2, and the non-vacuous positive the whole block rests on. Without it every
--   refusal below could be a blanket refusal of all closures, indistinguishable from a
--   broken column.
select lives_ok(
  format($$ update pfin.account set closed_at = '2026-06-30'::timestamptz where account_id = %s $$, :z),
  '(B1) SEC CASE 2: a zero-valued account CLOSES through the real control. NON-VACUOUS ANCHOR — without it, (B2)-(B8) would all pass against a gate that refuses everything'
);
-- (B1b) …and the closure is AUDITED. Sec case 2 is two properties, not one.
select set_config('role', 'postgres', true);
select is(
  (select count(*)::int from pfin.account_event where account_id = :z and event_type = 'closed'),
  1,
  '(B1b) SEC CASE 2, second half: the successful closure WROTE a pfin.account_event row. A gate that admits the right closures but records none of them satisfies the invariant and leaves no trail — and the audit surface is the only durable evidence of which accounts were dispositioned and by whom'
);
select _rls.set_tenant(:'ta'::uuid);

-- (B2)/(B3)/(B4) SEC CASE 1 — the three legs, each on its own message.
select throws_like(
  format($$ update pfin.account set closed_at = '2026-06-30'::timestamptz where account_id = %s $$, :cash),
  :'m_gate_cash',
  '(B2) SEC CASE 1, CASH LEG: closing an account holding 500 cash as of closed_at is REFUSED by the gate trigger'
);
select throws_like(
  format($$ update pfin.account set closed_at = '2026-06-30'::timestamptz where account_id = %s $$, :hold),
  :'m_gate_holdings',
  '(B3) SEC CASE 1, HOLDINGS LEG: closing an account holding 10 shares as of closed_at is REFUSED'
);
select throws_like(
  format($$ update pfin.account set closed_at = '2026-06-30'::timestamptz where account_id = %s $$, :post),
  :'m_gate_activity',
  '(B4) SEC CASE 1, POST-ACTIVITY LEG: closing with an entry dated 2026-07-10 (after the proposed closed_at) is REFUSED. This is the leg most likely to be omitted — at closed_at=now() it is trivially satisfied, so ONLY a backdated closure exercises it'
);

-- (B4b) THE FOURTH GATE CHECK — a PLAUSIBILITY BOUND I did not know existed until I read
--   the DDL. `058` raises on a closed_at in the FUTURE. Architect's comment records why it
--   lives in the trigger and not a CHECK: now() is STABLE, so a temporal CHECK is a
--   dump/restore foot-gun. And it is deliberately ONE-SIDED — `closed_at >= created_at`
--   would be wrong, because a historical account may legitimately be closed as of a date
--   before its row existed.
--   ⚑ This assertion exists because I ENUMERATED the raises rather than assuming the three
--     legs I had been told about were all of them. A fence with no test is the defect this
--     battery was created for; I nearly shipped one.
select throws_like(
  format($$ update pfin.account set closed_at = (now() + interval '1 year') where account_id = %s $$, :z),
  :'m_gate_future',
  '(B4b) PLAUSIBILITY BOUND: a closed_at dated one year in the FUTURE is REFUSED. One-sided by design — a past closed_at before created_at is legitimate for a historical account, so only the future bound is fenced. Found by enumerating the gate''s raises against the DDL, not by working from the three legs I was told about'
);

-- (B5) LEG INDEPENDENCE. B2/B3/B4 are three assertions only if their messages are three
--   messages. Under one merged 'closure gate failed' each would pass on ANY leg's fire and
--   this file would assert one thing three times while appearing to assert three.
select is(
  (select (length(pg_get_functiondef(p.oid))
           - length(replace(pg_get_functiondef(p.oid), 'raise exception', '')))
          / length('raise exception')
     from pg_proc p where p.pronamespace = 'pfin'::regnamespace
      and p.proname = 'fn_account_closure_gate'),
  6,
  '(B5) RAISE-SITE COUNT — the gate has EXACTLY 6 raise sites. ⚑ REPLACES a version keyed on the `leg N of 3` tag, which was LOSSY: raises 4 and 5 BOTH end `(leg 2 of 3: cash)`, so a distinct-tag check finds 3 values across 6 messages and REPORTS SUCCESS. The tag distinguishes LEGS; I was using it to distinguish RAISES. Counting sites fails when the gate changes SHAPE, not merely when a message changes value — the same correction as `drop trigger if exists` -> bare `drop trigger`. A red here means a raise was added or removed: go read it, then assert it'
);
-- (B4c) ⭐ THE TOTALITY-CONTRACT RAISE — reachable ONLY by a code edit, never by data.
--   `058` raises if fn_account_cash_as_of returns NO ROW for the account, because `056`'s
--   contract is that it is TOTAL over pfin.account. A missing row means that contract is
--   broken, and the gate refuses rather than treating absent-as-zero.
--   ⚑ WHY I MISSED IT, and it generalises: every OTHER raise is reachable by setting up a
--     DATA STATE. This one is reachable only by BREAKING `056`. So the method that correctly
--     found (B4b) — "enumerate the states I must construct" — CANNOT surface it, because
--     there is no state that produces it. **A fence against a code-edit hazard is unreachable
--     from data fixtures by construction**, and is therefore systematically missed by
--     fixture-driven enumeration. Found by Architect re-running my own raise-enumeration
--     against my count.
--   ⟦HARNESS PRECONDITIONS VERIFIED 2026-08-03, not assumed (Architect asked for both):
--     · the test role CAN `create or replace` a function in pfin inside a txn — measured
--     · the replacement ROLLS BACK — measured, and independently confirmed by (E12) in the
--       `056` battery, whose sentinel did not leak: the live fn is still the real one.⟧
-- ⚠ PENDING REBIND — Sec ruled option A 2026-08-03: the NULL fail-open folds into THIS
--   raise (`if not found or v_cash is null`) rather than becoming a seventh distinct one,
--   because both causes mean the same thing to an operator: **`056` is wrong, fix `056`.**
--   >> CONSEQUENCE FOR THIS ASSERTION: ONE RAISE, **TWO SEEDED CONDITIONS**. It must be
--      shown to fire on a MISSING ROW (below) *and* on a NULL `balance_native`. Only the
--      first is written, because Architect has not yet committed option A and I will not
--      harden against the superseded gate. **Asserting one cause of a two-cause raise is
--      testing half a guard** — the exact shape this battery exists to remove — so this
--      note stands in for the missing half until the rebind, rather than the gap being
--      invisible.
--   >> AND THE STAKES ARE THE INVERSE OF WHAT THEY LOOK LIKE: of the gate's runtime guards
--      this was the LAST one untested, and it is the one guarding the contract MOST likely
--      to break silently — someone adding a filter to `056`. The untested guard was the
--      load-bearing one.
select set_config('role', 'postgres', true);
savepoint sp_totality;
create or replace function pfin.fn_account_cash_as_of(p_as_of date)
returns table (account_id bigint, balance_native numeric)
language sql security invoker stable set search_path = '' as $totality$
  select acc.account_id, 0.0000::numeric from pfin.account acc where acc.account_id <> $totality$ || :z || $totality$
$totality$;
select _rls.set_tenant(:'ta'::uuid);
select throws_like(
  format($$ update pfin.account set closed_at = '2026-06-30'::timestamptz where account_id = %s $$, :z),
  '%returned no row from fn_account_cash_as_of%totality contract is broken%',
  '(B4c) TOTALITY BREACH: with fn_account_cash_as_of sabotaged to omit this account, the gate REFUSES rather than reading absent-as-zero. Fails CLOSED on a broken upstream contract — the alternative is a closure admitted because the measure went silent. This is the CP4 absent-row-vs-zero-row class at the FENCE layer, and the only gate raise no data fixture can reach'
);
select set_config('role', 'postgres', true);
rollback to savepoint sp_totality;
select _rls.set_tenant(:'ta'::uuid);

-- (B6) THE AS-OF PROPERTY — the entire point of the dated model. :asof held 800 through May
--   and was zeroed 2026-06-15. Verified live: 800.0000 @05-31, 0.0000 @06-30.
select lives_ok(
  format($$ update pfin.account set closed_at = '2026-06-30'::timestamptz where account_id = %s $$, :asof),
  '(B6a) AS-OF: closing :asof dated 2026-06-30 SUCCEEDS — it is zero as of that instant'
);
select throws_like(
  format($$ update pfin.account set closed_at = '2026-05-31'::timestamptz where account_id = %s $$, :asof),
  :'m_gate_cash',
  '(B6b) AS-OF, THE DEFECT THE MODEL REMOVES: the SAME account closed dated 2026-05-31 is REFUSED — it held 800 then. A boolean flag cannot express this distinction, which is precisely why is_active could not be retained as a derived column'
);

-- (B7) EXACT ZERO, NO TOLERANCE. `056`'s contract: numeric(20,4) addition only, no division
--   and no multiplier, so exact zero is exactly representable and the gate needs no epsilon.
select throws_like(
  format($$ update pfin.account set closed_at = '2026-06-30'::timestamptz where account_id = %s $$, :tiny),
  :'m_gate_cash',
  '(B7) EXACT ZERO, NO TOLERANCE: a 0.0001 cash residue is REFUSED. Any epsilon tolerance is an invented allowance on a surface whose arithmetic is exactly representable — this goes RED the moment one is introduced'
);

-- (B8) QUANTITY-NOT-VALUE. The fail-open trap, verified live (quantity 10, market value 0).
select throws_like(
  format($$ update pfin.account set closed_at = '2026-06-30'::timestamptz where account_id = %s $$, :unp),
  :'m_gate_holdings',
  '(B8) QUANTITY-NOT-VALUE: 10 shares of an UNPRICED asset are REFUSED. A market-value gate reads this account as EMPTY and admits the closure, stranding a real position inside a closed account. This single assertion separates a gate that measures POSITION from one that trusts PRICE COVERAGE'
);

-- (B9) REOPEN IS UNGATED AND DELIBERATELY ASYMMETRIC (ADR-042 D3). Gating the exit would be
--   incoherent: a closed account is already at zero by the gate that admitted it.
select lives_ok(
  format($$ update pfin.account set closed_at = null where account_id = %s $$, :z),
  '(B9) REOPEN IS UNGATED: NOT NULL -> NULL succeeds. Asymmetric by design — closure entries are historical facts and are not un-booked; a reopened account starts at zero and is funded by new dated entries'
);
select set_config('role', 'postgres', true);
update pfin.account set closed_at = '2026-06-30'::timestamptz where account_id = :z;  -- re-close for BLOCK C
select _rls.set_tenant(:'ta'::uuid);

-- (B10)/(B11) DECISION 4 — `currency` immutable on a closed account. Reachable because
--   `003:124` grants authenticated table-level UPDATE with NO COLUMN LIST (verified live)
--   and pfin is Data-API-exposed; updateAttributes' Zod schema is app-layer, not a control.
select throws_like(
  format($$ update pfin.account set currency = 'EUR' where account_id = %s $$, :z),
  :'m_currency_frozen',
  '(B10) D4: UPDATE currency on a CLOSED account is REFUSED. currency feeds the fn_compute_nav cash-leg FX multiplier, so changing it retroactively re-values every date INCLUDING closed_at — falsifying the very invariant that admitted the closure'
);
select lives_ok(
  format($$ update pfin.account set name = 'renamed-while-closed' where account_id = %s $$, :z),
  '(B11a) COLUMN-SCOPED: renaming a CLOSED account still SUCCEEDS -> (B10) fences the currency column, not the row. A whole-row freeze would pass (B10) while silently breaking every legitimate attribute correction'
);
select lives_ok(
  format($$ update pfin.account set currency = 'EUR' where account_id = %s $$, :open1),
  '(B11b) CLOSURE-SCOPED: UPDATE currency on an OPEN account still SUCCEEDS -> (B10) is closure-conditional, by design. The open-account restatement half is explicitly OUT OF SCOPE (BACKLOG §7.7); this pins it as genuinely out of scope rather than accidentally covered'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- BLOCK C — THE STANDING TRANSFER-IN FENCES  (Sec case 6, DB HALF ONLY)
--   ⚑ SEC: CASE 6 SPLITS ACROSS TWO LAYERS AND THEY MUST NOT BE CONFLATED.
--     The DATABASE REFUSES — trigger raise, asserted here.
--     The RECORDING of the refusal is the ingest worker's skip-and-record loop plus a NEW
--     named scalar COUNT key on the `040` view — APPLICATION LAYER, BACKEND-OWNED, and NOT
--     a DB assertion. Asserting that the database records the refusal would fail for the
--     right reason and read as a spec error. Asserting only the raise and calling case 6
--     done would leave the quarantine path unproven.
--     >> THIS FILE COVERS THE REFUSAL ONLY. The recording half is REPORTED AS AN OPEN GAP
--        routed to Backend — it is not silently counted as covered here. Its requirements
--        (a NEW key, not `transactions_skipped`; NULL != 0 so historical rows read "we
--        weren't counting" rather than "nothing was refused") are Backend's to satisfy and
--        need an integration-layer test, which pgTAP cannot provide.
-- =====================================================================

-- (C1) account_trans, AUTHENTICATED tier — grants INSERT to authenticated, so this reaches
--   the TRIGGER. Matched on the raise text; a bare 42501 or P0001 would also match an ACL
--   denial or an unrelated raise.
select _rls.set_tenant(:'ta'::uuid);
select throws_like(
  format($$ insert into pfin.account_trans (account_id, transaction_date, amount, vendor)
              values (%s, '2026-08-01', 25, 'transfer-in') $$, :z),
  :'m_fence_trans',
  '(C1) SEC CASE 6 (DB half), authenticated -> TRIGGER: the INSERT reaches the trigger (the grant exists) and is refused BY THE TRIGGER, not by a missing grant'
);
select set_config('role', 'postgres', true);

-- (C2) account_trans, SERVICE_ROLE tier — the tier provider sync actually runs at.
grant usage on schema pfin to service_role;
grant insert on pfin.account_trans to service_role;
select set_config('role', 'service_role', true);
select throws_like(
  format($$ insert into pfin.account_trans (account_id, transaction_date, amount, vendor)
              values (%s, '2026-08-01', 25, 'sync-transfer-in') $$, :z),
  :'m_fence_trans',
  '(C2) CROSS-TIER: service_role INSERT into a closed account is refused BY THE TRIGGER (RLS-bypass is not trigger-bypass, `004:165`). This is the tier provider sync runs at — the fence is only load-bearing if it holds here'
);

-- (C3)/(C4) the checkpoint tables, at service_role. ⚑ authenticated holds SELECT ONLY on
--   both (verified live), so an authenticated probe is refused at the ACL and would
--   exercise the grant rather than the fence.
select throws_like(
  format($$ insert into pfin.account_balance_checkpoint (account_id, balance, currency, as_of_date, source)
              values (%s, 25.0000, 'USD', '2026-08-01', 'sync') $$, :z),
  :'m_fence_bal',
  '(C3) account_balance_checkpoint INSERT into a closed account refused BY THE TRIGGER at service_role. Driven at service_role deliberately: an authenticated probe hits the SELECT-only ACL first and reports a grant as a fence'
);
select throws_like(
  format($$ insert into pfin.holdings_checkpoint (account_id, symbol, as_of_date, quantity, balance, security_id)
              values (%s, 'QAPRC', '2026-08-01', 5, 500, %s) $$, :z, :a_priced),
  :'m_fence_hold',
  '(C4) holdings_checkpoint INSERT into a closed account refused BY THE TRIGGER at service_role (same layer discipline as C3). Per-table messages confirmed by Architect so (C2)/(C3)/(C4) identify WHICH fence fired'
);

-- (C5) NON-VACUOUS COMPANIONS — the identical writes into an OPEN account SUCCEED.
select lives_ok(
  format($$ insert into pfin.account_trans (account_id, transaction_date, amount, vendor)
              values (%s, '2026-08-01', 25, 'open-ok') $$, :open1),
  '(C5a) NON-VACUOUS: the identical account_trans INSERT into an OPEN account SUCCEEDS -> (C1)/(C2) are closure-driven refusals, not malformed statements'
);
select lives_ok(
  format($$ insert into pfin.account_balance_checkpoint (account_id, balance, currency, as_of_date, source)
              values (%s, 25.0000, 'USD', '2026-08-01', 'sync') $$, :open1),
  '(C5b) NON-VACUOUS companion for (C3)'
);
select lives_ok(
  format($$ insert into pfin.holdings_checkpoint (account_id, symbol, as_of_date, quantity, balance, security_id)
              values (%s, 'QAPRC', '2026-08-01', 5, 500, %s) $$, :open1, :a_priced),
  '(C5c) NON-VACUOUS companion for (C4)'
);
select set_config('role', 'postgres', true);

-- (C6) FENCE SCOPE — the EXEMPT tables must STILL ACCEPT writes against a closed account.
--   ADR-042 D3 names every exemption's dependency; these pin them so an over-broadened
--   fence is visible. Nothing else in this file tests the fence's OUTER boundary.
select lives_ok(
  format($$ insert into pfin.account_trans_annotation (trans_id, sub_cat_id)
              values ((select trans_id from pfin.account_trans where account_id = %s limit 1), null) $$, :open1),
  '(C6a) EXEMPTION HOLDS — account_trans_annotation is NOT fenced. Dependency: `004` immutability of account_trans.account_id + amount, so an annotation can only re-classify a value it cannot change'
);
select ok(
  (select count(*)::int from pg_trigger t join pg_class c on c.oid = t.tgrelid
     join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'pfin' and c.relname in ('account_trans_split', 'account_trans_annotation')
      and t.tgname like '%closed%' and not t.tgisinternal) = 0,
  '(C6b) EXEMPTION HOLDS — neither account_trans_split nor account_trans_annotation carries a closed-account fence. split''s dependency is `029`''s Sigma=parent deferred constraint. Asserted STRUCTURALLY because a passing INSERT could also mean the fence exists but did not fire'
);

-- (C7) `042` MUST NOT CLEAR closed_at ON RE-LAND. Landing is concept 3; reopening is
--   concept 2; a concept-3 action must not silently perform a concept-2 transition.
select ok(
  (select pg_get_functiondef(p.oid) not like '%closed_at = null%'
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'pfin' and p.proname = 'fn_land_linked_accounts'),
  '(C7) fn_land_linked_accounts (`042`) does NOT clear closed_at on re-land -> a landing action cannot silently perform a reopen. Also closes the unaudited-silent-reopen finding. SOURCE-LEVEL, not behavioural — the behavioural path needs a full provider payload; flagged as such in the report'
);

-- =====================================================================
-- BLOCK S — THE TRANSITIONAL SYNC TRIGGER  (Sec case 7 — CONFIRMED, not conditional)
--   Sec required this: without it, every account the operator correctly closes through the
--   gate lands `closed_at` SET while `is_active` stays TRUE — and `059`'s reconciliation
--   then ABORTS ON EXACTLY THE ACCOUNTS THAT WERE DISPOSITIONED PROPERLY. The trigger makes
--   the biconditional hold BY CONSTRUCTION across the `058`->`059` window.
--   It lives in `058` and is DROPPED in `059`.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
-- (S1) closing sets BOTH.
select is(
  (select is_active from pfin.account where account_id = :asof),
  false,
  '(S1) SEC CASE 7: closing :asof through the gate ALSO set is_active = false. Without this sync, `059` aborts on precisely the accounts the operator dispositioned CORRECTLY — the reconciliation would fire on good work and pass over nothing'
);
-- (S2) clearing sets BOTH back.
select lives_ok(
  format($$ update pfin.account set closed_at = null where account_id = %s $$, :asof),
  '(S2a) reopening :asof succeeds (reopen is ungated)'
);
select set_config('role', 'postgres', true);
select is(
  (select is_active from pfin.account where account_id = :asof),
  true,
  '(S2b) SEC CASE 7, reverse direction: clearing closed_at set is_active back to TRUE. A one-directional sync would leave reopened accounts inactive and `059` would abort on those instead — the same defect mirrored'
);
-- (S3) THE BICONDITIONAL, over every row — the property `059` will assert and the reason
--   this trigger exists. Asserted here too so a sync gap surfaces in `058`'s own PR rather
--   than as an unexplained `059` abort one migration later.
select is(
  (select count(*)::int from pfin.account
    where (is_active = false) is distinct from (closed_at is not null)),
  0,
  '(S3) THE BICONDITIONAL HOLDS across every row after all of BLOCK B''s closures and reopens: is_active = false <=> closed_at IS NOT NULL. This is exactly what `059` asserts — checked here so a sync gap surfaces in `058`''s own PR instead of as an unexplained `059` abort a migration later'
);

-- (S4) ⚑ THE SYNC TRIGGER IS ONE-DIRECTIONAL, AND THIS IS A GATE-BYPASS ASSERTION.
--   Architect's precision, relayed 2026-08-03: a BIDIRECTIONAL sync would let a user close
--   an account by flipping the legacy boolean — `closed_at` would follow, and THE THREE-LEG
--   GATE WOULD NEVER RUN. That is not a tidiness concern: `003:124` grants authenticated
--   table-level UPDATE on pfin.account with NO COLUMN LIST (verified live), and pfin is
--   Data-API-exposed, so `update pfin.account set is_active = false` is reachable from a
--   tenant session TODAY. A bidirectional trigger would turn that statement into an
--   unvalidated closure of a value-bearing account — the exact write the entire ADR exists
--   to make impossible.
--   Driven at AUTHENTICATED deliberately: that is the tier the bypass would be reached from,
--   and a privileged probe would not prove the tenant-facing path is closed.
select _rls.set_tenant(:'ta'::uuid);
select lives_ok(
  format($$ update pfin.account set is_active = false where account_id = %s $$, :cash),
  '(S4a) setup + reachability: a tenant session CAN still flip is_active directly during the `058`->`059` window (table-level UPDATE grant, no column list). This must SUCCEED — the legacy column is deliberately still writable in phase 1; what must not happen is (S4b)'
);
select set_config('role', 'postgres', true);
select is(
  (select closed_at from pfin.account where account_id = :cash),
  null::timestamptz,
  '(S4b) GATE-BYPASS FENCE: flipping is_active = false on a NON-ZERO account did NOT set closed_at. The sync is ONE-DIRECTIONAL (closed_at drives is_active, never the reverse). A bidirectional trigger would let any tenant close a value-bearing account with `update pfin.account set is_active = false` — reachable today via the no-column-list UPDATE grant — and the three-leg gate would never run. This is the single assertion standing between the legacy column and an unvalidated closure'
);
-- (S4c) …and the resulting row is a DELIBERATE, VISIBLE mismatch rather than a silent
--   closure. This is why `059`'s reconciliation exists: one-directionality does not paper
--   over the un-dispositioned row, it leaves it standing where the migration will abort on it.
select is(
  (select count(*)::int from pfin.account
    where account_id = :cash and (is_active = false) is distinct from (closed_at is not null)),
  1,
  '(S4c) the flip leaves a VISIBLE biconditional mismatch, not a silent closure -> `059`''s reconciliation aborts on exactly this row (Sec case 3). One-directionality and the reconciliation are the same control seen from two ends: the trigger refuses to invent a closure, and the migration refuses to drop the evidence'
);
update pfin.account set is_active = true where account_id = :cash;  -- restore for BLOCK P

-- =====================================================================
-- BLOCK P — TWO-PHASE POSTURE
-- =====================================================================
-- (P1) THE ASSERTION THAT CATCHES `058` BEING BUILT FROM THE SUPERSEDED SINGLE-FILE DESIGN.
select has_column('pfin', 'account', 'is_active',
  '(P1) TWO-PHASE: `058` leaves is_active IN PLACE — it does NOT drop it. The drop belongs to `059`, AFTER the operator has dispositioned each account through the real control. RED if `058` is built from the withdrawn single-file/declared-set design, which dropped the column in the same file');
select col_type_is('pfin', 'account', 'closed_at', 'timestamp with time zone',
  '(P2) closed_at is timestamptz — a DATED closure, which is what makes "closed in June still counts in a May NAV" expressible at all');
select is(
  (select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'pfin' and p.prosecdef
       and p.proname not in ('fn_refresh_updated_at', 'fn_grant_creator_access', 'fn_reclass_history_insert')),
  0,
  '(P3) `058` authors ZERO SECURITY DEFINER functions — every fence is INVOKER per ADR-042 Consequences and Architect''s confirmation. NOTE the referent: this counts AUTHORED DEFINER functions (3); the ALLOWLIST is 4, the fourth being the reserved-but-unauthored audit-log helper. Both numbers are correct and they measure different things — do not "correct" 3 to 4, which would silently widen the fence by one slot'
);

-- (P4) THE INSERT PATH — the specific hole the design changed shape to close.
--   `058:66-73` records why the biconditional is a CHECK and not a trigger: **a BEFORE
--   UPDATE trigger does not see an INSERT**, and the `049`/`050`/`051` batteries INSERT
--   `is_active` in the column list, so `INSERT (is_active=false, closed_at=null)` creates
--   exactly the state `059` must abort on. A CHECK covers INSERT and UPDATE for ALL ROLES
--   (a CHECK is not RLS) with no ordering concerns.
--   Driven PRIVILEGED deliberately — that proves the "all roles" property. An authenticated
--   probe would meet the RLS WITH CHECK first and would prove only that RLS works.
select throws_like(
  format($$ insert into pfin.account (users_id, name, account_type, scope, tax_treatment, is_active, closed_at)
              values (%L, 'insert-path-violator', 'depository', 'household', 'taxable', false, null) $$, :'ta'),
  '%violates check constraint "account_closure_biconditional"%',
  '(P4) INSERT PATH: an INSERT carrying (is_active=false, closed_at=null) is REJECTED by the CHECK, privileged. That is the state `059` aborts on and it is INVISIBLE to a BEFORE UPDATE trigger — the reason the biconditional is a CHECK rather than a trigger. Without this, the design decision that closed the hole has a comment and no test'
);

-- (P5) THE NULL TRIPWIRE — converts a recorded caveat into a mechanical check.
--   `058:88` and the constraint comment both record it: **a CHECK PASSES ON NULL.** The
--   plain `=` is correct only because `is_active` is NOT NULL — and that is INHERITED from
--   `003:104`, not restated by `058`. So if `is_active` were ever made nullable,
--   `account_closure_biconditional` would SILENTLY PASS EVERYTHING and `059`'s VALIDATE
--   would succeed over a table full of violators.
select col_not_null('pfin', 'account', 'is_active',
  '(P5) NULL TRIPWIRE: pfin.account.is_active is still NOT NULL (inherited from `003:104`, not restated by `058`). A CHECK passes on NULL, so a nullable is_active makes the biconditional silently pass EVERYTHING and `059`''s VALIDATE succeed over a table of violators. RED here means the fence was disarmed by a change somewhere else entirely — the only way this defect can arrive');

-- =====================================================================
-- BLOCK G — INVERSION (non-vacuity, proved IN FILE)
--   Assertion-count integrity: pgTAP's plan(33) + finish() IS the executed-assertion count.
--   A partial or aborted run reports "planned 33 but ran N" and FAILS, so a 0-RED result is
--   never inferred from the absence of failures. Demonstrated live on this suite 2026-08-03:
--   `053` reported "planned 19 but ran 0" and `054` "planned 63 but ran 10" on a stale DB —
--   both correctly FAILED rather than passing quietly.
-- =====================================================================
savepoint sp_g1;
drop trigger account_trans_block_closed_account on pfin.account_trans;  -- real name @407b190; bare DROP (not IF EXISTS) so a rename fails LOUDLY here rather than making G1 a silent no-op
select lives_ok(
  format($$ insert into pfin.account_trans (account_id, transaction_date, amount, vendor)
              values (%s, '2026-08-02', 25, 'canary') $$, :z),
  '(G1) TEETH: with the closed-account trigger DROPPED, the (C1)/(C2) INSERT SUCCEEDS -> those refusals are trigger-driven and non-vacuous. Had it still failed, C1/C2 were passing on something other than the fence'
);
rollback to savepoint sp_g1;

savepoint sp_g2;
drop trigger account_closure_gate on pfin.account;  -- real name @407b190; bare DROP so a rename fails loudly
select lives_ok(
  format($$ update pfin.account set closed_at = '2026-06-30'::timestamptz where account_id = %s $$, :cash),
  '(G2) TEETH: with the close-gate trigger DROPPED, the (B2) non-zero account CLOSES -> (B2)/(B3)/(B4)/(B7)/(B8) are gate-driven and non-vacuous'
);
rollback to savepoint sp_g2;

select * from finish();
rollback;
