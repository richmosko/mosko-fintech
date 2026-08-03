-- =====================================================================
-- 056 — pfin.fn_account_cash_as_of (ADR-042 build-sequence slice A): the shared cash measure.
-- =====================================================================
-- QA-owned. Authors NO schema. Pairs with Architect's `056` (UNTRACKED WIP draft, 2026-08-03 — nothing merged).
-- Sec joint-review-mandatory (financial calculation · the measure the close gate and the
-- NAV path both foot to).
--
-- ⚑ RETRACTED + RESTATED — my "056 is half the slice" finding is STALE, and the retraction
--   matters more than the finding did.
--   WHAT I SAW: at 10:43 the draft was 11710 bytes and contained ONE `create or replace
--   function` (the new measure), with no re-point of `049`/`050`. That was true then.
--   WHAT IS TRUE NOW: at 11:08 the draft is 16710 bytes and contains TWO — it re-points
--   `050` fn_compute_nav, which now reads `left join pfin.fn_account_cash_as_of(p_as_of) c`
--   and carries ZERO pfin.account_balance_checkpoint references in the re-pointed body.
--   So (E5a) / (E8) / (E10b) should go GREEN once applied. The half-slice claim is RESOLVED.
--   WHAT REMAINS OPEN, narrower and current: `049` fn_account_unrealized_gl is NOT mentioned
--   anywhere in the draft and is NOT re-pointed. ADR-042 says "refactor 049 AND 050". So
--   (E5b) / (E10c) stay RED on `049` alone. Flagged as OPEN, not as a defect — Architect is
--   mid-pass and treating the re-point as its own careful slice.
--
-- ⛔ MERGE GATE — BOTH RE-POINTS, OR NEITHER (Sec, confirmed 2026-08-03).
--   `056` MUST NOT MERGE with only `050` re-pointed. That intermediate state is TWO
--   DEFINITIONS — `049`'s inline copy plus the extracted function — which is the exact
--   outcome the extraction exists to remove.
--   It is not strictly undetectable: foot-to-NAV compares `049` to `050`, so a later edit to
--   the function moves `050`, leaves `049`, and breaks the invariant. **But "detectable by an
--   invariant that fires after the fact" is not the property the extraction was chosen for.**
--   It was chosen so fence and NAV CANNOT diverge; half a re-point restores the ability to.
--   >> If `049` is ever DELIBERATELY deferred to a later slice, that is an F/CTO RATIFICATION
--      DECISION, not a scheduling detail — it would leave the two-definitions state on `main`.
--   (E5b) / (E10c) are the assertions holding this gate. They stay RED until `049` lands.
--
-- ⚠ A CLAIM'S REFERENT MUST BE FIXED, OR THE CLAIM IS PROVISIONAL (Sec — the root cause of
--   the apparent Architect/QA contradiction, one layer BELOW the file-vs-database framing).
--   I read the draft at 10:43 (11710 bytes, ONE function). It was 16710 bytes and TWO
--   functions by 11:08. Both readings were honest. THE FILE CHANGED UNDERNEATH.
--   So naming the artifact is not enough — you need WHICH VERSION, and **an untracked file
--   has no version identity**: no hash, no tag, nothing citable. A verification claim against
--   an untracked file IS NOT REPRODUCIBLE BY ANYONE, INCLUDING ITS AUTHOR LATER.
--   >> THE COMPLETE RULE, of which the ⟦EXPECTED STACK⟧ header is only the first clause:
--        · a BEHAVIOURAL claim names the DATABASE STATE it ran against;
--        · a TEXTUAL claim names the ARTIFACT **and its VERSION**;
--        · an UNTRACKED artifact has no version, so a claim against one is PROVISIONAL BY
--          CONSTRUCTION and must say so.
--      Every claim in this file's headers about the `056` draft WAS provisional under that
--      rule, because the draft was untracked.
--   ✅ RESOLVED 2026-08-03 — THE DRAFT NOW HAS A VERSION IDENTITY. Architect committed it;
--      `056` is NOT in the working tree (verified: worktree on `main`, no such file) and is
--      readable ONLY as:
--          git show 58c9bd6:supabase/migrations/056_fn_account_cash_as_of.sql
--      Every textual claim in this file is re-stated against that ref and is therefore
--      REPRODUCIBLE — no longer provisional. Verified at 58c9bd6: TWO `create or replace
--      function` (fn_account_cash_as_of + the re-pointed fn_compute_nav), and
--      `fn_account_unrealized_gl` appears **0 times** — so the `049` gate below is pinned to
--      a citable ref rather than to a moving file.
--      ⚠ And note the failure this closes: Architect cut a branch and left the shared
--        worktree checked out on it, so a FILE read silently became branch-dependent. The
--        artifact had a version and the READER still couldn't fix the referent. Hence: cite
--        by ref, never by path.
--
-- ⚠ AND A CORRECTION TO HOW A RED IS ATTRIBUTED — the general lesson, caught by Sec.
--   I earlier reported that installing (E12)'s sentinel "did not move the NAV", and called
--   that "the half-slice defect demonstrated behaviourally". THAT ATTRIBUTION WAS WRONG.
--   The probe ran against the local dev DB at migration **051** — verified — where
--   fn_account_cash_as_of DOES NOT EXIST AT ALL (pg_proc count = 0; my probe created it
--   fresh) and no consumer has ever been pointed at it. A NON-MOVING NAV IS THE CORRECT AND
--   EXPECTED RESULT FOR THAT DATABASE STATE. It says nothing about Architect's re-point,
--   which is not in that database. I misattributed a PROPERTY OF THE SETUP to a CODE DEFECT
--   — the same shape as pg_get_functiondef's throw looking like a finding, and `019`'s
--   superseded on-disk text looking like a hit. Third instance, mine.
--   >> THE STANDING RULE THIS PRODUCES (Sec), which applies to EVERY behavioural assertion:
--      A BEHAVIOURAL RESULT IS UNINTERPRETABLE WITHOUT THE DATABASE STATE IT RAN AGAINST.
--      A red cannot be told from "this DB predates the change"; a green cannot be told from
--      "this DB already had it". (E12) therefore RECORDS the applied migration set — see its
--      header — and any run of this file must report that set alongside the result.
--
-- ⟦SIGNATURE CONFIRMED by Architect 2026-08-03 and verified against the WIP draft⟧
--   pfin.fn_account_cash_as_of(p_as_of date) returns table (account_id bigint,
--   balance_native numeric) — SECURITY INVOKER, STABLE, set search_path = ''.
--   TOTAL over pfin.account by construction (`from pfin.account acc`, no filter), including
--   inactive/closed accounts — filtering is the caller's job, because the gate must measure
--   an account exactly when it is about to stop being current-state.
--   NATIVE currency, NO FX multiplier — load-bearing, see (E4).
--
-- ⟦FIXTURE-VERIFIED 2026-08-03⟧ `056` is applied nowhere reachable (the local DB is at
--   `051`), so NO assertion below has run. What HAS run against the live DB in a rolled-back
--   txn: every seed statement, and the probes proving each trap actually discriminates —
--   because a fixture whose traps do not separate yields assertions that cannot fail:
--     · (E4) no-FX  → native reads 100.0000; an FX-applying implementation would read
--       150.00000000. Real separation, not an argued one.
--     · (E1a)       → the roll-forward computes 1300.0000 on this fixture.
--     · (E2a)       → the empty account reads 0 under the INLINE form — which is exactly why
--       it must also be PRESENT under the extracted form. That is the whole finding.
--   Two real fixture defects were caught by running it rather than reading it:
--     1. account_type 'brokerage' violates account_account_type_check.
--     2. a global EUR currency asset ALREADY EXISTS (asset_id 2) and
--        `asset_global_symbol_uniq` rejects a duplicate — a plain INSERT fails with a
--        duplicate-key error unrelated to what (E4) tests. Now insert-if-missing.
--
-- ┌─ ⟦EXPECTED STACK⟧ — READ BEFORE INTERPRETING ANY RESULT FROM THIS FILE ──────────┐
-- │ **A RESULT FROM THIS BATTERY IS UNINTERPRETABLE WITHOUT THE MIGRATION SET IT RAN │
-- │ AGAINST.** A red cannot be distinguished from "this DB predates the change"; a    │
-- │ green cannot be distinguished from "this DB already had it". Report the applied   │
-- │ set alongside the result, every run — `select max(version) from                   │
-- │ supabase_migrations.schema_migrations;`                                           │
-- │                                                                                   │
-- │ EXPECTED STACK: `056`-applied.                                                      │
-- │ fn_account_cash_as_of exists; `050` fn_compute_nav re-pointed onto it. Below `05
-- │   6` the measure does not exist and EVERY assertion here is RED for that reason 
-- │   alone — a state, not a defect.
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
-- POSTURE (SECURITY §4.5): SYNTHETIC ONLY; no PII, no real account numbers (SD-15), no prod
--   data; rolled-back txn; no `supabase db reset`.
-- =====================================================================

begin;

\ir ../_fixtures/rls_verbs.psql

-- plan = 22: E1 2 · E2 2 · E3 2 · E4 3 · E5 2 · E6 1 · E8 1 · E9 2 · E10 3 · E11 1 · E12 2 · E7 1.
select plan(22);

select _rls.tenant_a() as ta, _rls.tenant_b() as tb \gset

insert into auth.users (id) values (:'ta'), (:'tb');

insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'ta', 'A-cash', 'depository', 'household', 'taxable') returning account_id as a1 \gset
-- ⚑ Sec-requested fixture row: an account with NO checkpoint and NO transactions AT ALL.
--   This is the ONLY row in the fixture that distinguishes "total over pfin.account" from
--   "returns rows for accounts with activity" — every other row has data and produces a
--   function row either way. See (E2a).
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'ta', 'A-empty', 'depository', 'household', 'taxable') returning account_id as aempty \gset
-- A EUR-denominated account, for the no-FX-multiplier assertion.
insert into pfin.account (users_id, name, account_type, scope, tax_treatment, currency)
  values (:'ta', 'A-eur', 'depository', 'household', 'taxable', 'EUR') returning account_id as aeur \gset
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'tb', 'B-cash', 'depository', 'household', 'taxable') returning account_id as b1 \gset

-- A: anchor 1000 @01-31, +500 @02-15, -200 @03-10 (both AFTER the anchor -> both roll
-- forward). Cash @2026-03-31 = 1300. Cash @2026-02-01 = 1000.
insert into pfin.account_balance_checkpoint (account_id, balance, currency, as_of_date, source)
  values (:a1, 1000.0000, 'USD', '2026-01-31', 'seed');
insert into pfin.account_trans (account_id, transaction_date, amount, quantity, vendor)
  values (:a1, '2026-02-15', 500.0000, 0, 'after-anchor');
insert into pfin.account_trans (account_id, transaction_date, amount, quantity, vendor)
  values (:a1, '2026-03-10', -200.0000, 0, 'after-anchor-2');

-- EUR account holds 100 native, with a LIVE fx_feed rate of 1.5 available. If the measure
-- applied FX this would read 150.
insert into pfin.account_balance_checkpoint (account_id, balance, currency, as_of_date, source)
  values (:aeur, 100.0000, 'EUR', '2026-01-31', 'seed');
-- ⚑ The global EUR currency asset ALREADY EXISTS on a seeded stack (asset_id 2 on the live
--   local DB) and `asset_global_symbol_uniq` rejects a duplicate. Insert-if-missing then
--   look up, so this fixture is correct on BOTH a seeded stack and a bare CI stack. A plain
--   INSERT here fails with a duplicate-key error that has nothing to do with what (E4) is
--   testing — caught by running the fixture rather than by reading it.
insert into pfin.asset (users_id, asset_type, pricing_source, symbol, name)
  select null, 'currency', 'fx_feed', 'EUR', 'Euro'
   where not exists (select 1 from pfin.asset
                      where users_id is null and asset_type = 'currency' and symbol = 'EUR');
select asset_id as eurasset from pfin.asset
 where users_id is null and asset_type = 'currency' and symbol = 'EUR' limit 1 \gset
insert into pfin.eod_price (asset_id, price_date, source, price)
  values (:eurasset, '2026-01-31', 'fx_feed', 1.5000);

-- ⚑ Sec-requested (2nd fixture correction): an account holding BOTH cash AND a priced
--   security, so the SECURITIES LEG IS GENUINELY NON-ZERO. Without it the securities leg is
--   trivially 0, per-leg and total-only become THE SAME ASSERTION on this fixture, and the
--   thing per-leg exists to catch — a refactor preserving the TOTAL while SHIFTING VALUE
--   BETWEEN LEGS — cannot be exercised at all. A per-leg assertion on a fixture with an empty
--   leg is a total-only assertion wearing per-leg clothes. See (E9a)/(E9b).
insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'ta', 'A-cash-and-securities', 'investment', 'household', 'taxable') returning account_id as asec \gset
insert into pfin.asset (users_id, asset_type, pricing_source, symbol, name)
  values (null, 'equity', 'market_feed', 'QAPRC', 'Priced Equity') returning asset_id as a_priced \gset
insert into pfin.eod_price (asset_id, price_date, source, price)
  values (:a_priced, '2026-01-31', 'market_feed', 100.0000);
insert into pfin.account_balance_checkpoint (account_id, balance, currency, as_of_date, source)
  values (:asec, 300.0000, 'USD', '2026-01-31', 'seed');          -- cash leg      = 300
insert into pfin.holdings_checkpoint (account_id, symbol, as_of_date, quantity, balance, security_id)
  values (:asec, 'QAPRC', '2026-01-31', 10, 1000, :a_priced);      -- securities leg = 1000

-- B: 9999 — the cross-tenant leak target.
insert into pfin.account_balance_checkpoint (account_id, balance, currency, as_of_date, source)
  values (:b1, 9999.0000, 'USD', '2026-01-31', 'seed');

-- =====================================================================
-- E1 — THE ROLL-FORWARD ARITHMETIC, AT TWO DATES
--   Two dates, not one: a single date is satisfied by an implementation that ignores
--   p_as_of and returns the current balance — the current-state-vs-as-of confusion this
--   entire ADR exists to remove.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
select is(
  (select balance_native from pfin.fn_account_cash_as_of('2026-03-31'::date) where account_id = :a1),
  1300.0000::numeric,
  '(E1a) anchor 1000 @01-31 + 500 @02-15 - 200 @03-10 = 1300 as of 2026-03-31 — exact, no tolerance (numeric(20,4) addition only; no division, no multiplier)'
);
select is(
  (select balance_native from pfin.fn_account_cash_as_of('2026-02-01'::date) where account_id = :a1),
  1000.0000::numeric,
  '(E1b) the SAME account reads 1000 as of 2026-02-01 — later entries correctly EXCLUDED. Without a second date, (E1a) also passes for an implementation that ignores p_as_of entirely'
);

-- =====================================================================
-- E2 — TOTALITY: absent-row vs zero-row (Sec, the CP4 class applied to a refactor)
--   `056` extracts an inline CORRELATED SUBQUERY into a SET-RETURNING FUNCTION. Inline, an
--   empty account evaluates to coalesce(...,0)+coalesce(...,0) = 0 and STAYS in the result.
--   Extracted-and-joined, an account ABSENT from the function's output DISAPPEARS from the
--   result rather than contributing zero. The empty account is the sole fixture row where
--   those two give different answers — every other row has data and produces a function row
--   either way. A total-only comparison passes regardless, which is why this is asserted
--   per-row.
-- =====================================================================
select is(
  (select balance_native from pfin.fn_account_cash_as_of('2026-03-31'::date) where account_id = :aempty),
  0.0000::numeric,
  '(E2a) ABSENT-ROW vs ZERO-ROW: an account with NO checkpoint and NO transactions is PRESENT in the output with balance_native 0.0000, not missing. If a later optimization narrows the function to accounts-with-activity, this is the only assertion in the file that goes red — every other row produces a function row either way'
);
select is(
  (select count(*)::int from pfin.fn_account_cash_as_of('2026-03-31'::date)),
  (select count(*)::int from pfin.account),
  '(E2b) TOTALITY BY CONSTRUCTION: the function returns exactly one row per caller-visible pfin.account row. Asserted as a count identity rather than trusting the `from pfin.account acc` source line, so a later WHERE clause or inner join anywhere in the body surfaces here'
);

-- =====================================================================
-- E3 — CROSS-TENANT: SECURITY INVOKER fails closed
-- =====================================================================
select is(
  (select count(*)::int from pfin.fn_account_cash_as_of('2026-03-31'::date) where account_id = :b1),
  0,
  '(E3a) INVOKER FAILS CLOSED: tenant A sees NO row for B''s account — an empty set, not B''s 9999. Inherited RLS on pfin.account filters the driving table; the function adds no bypass'
);
select set_config('role', 'postgres', true);
select is(
  (select prosecdef from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'pfin' and p.proname = 'fn_account_cash_as_of'),
  false,
  '(E3b) the measure is SECURITY INVOKER, not DEFINER -> (E3a)''s empty set is inherited RLS rather than a filter the function chose to apply. A DEFINER version returns the same empty set today and leaks the moment its predicate is edited'
);

-- =====================================================================
-- E4 — NO FX MULTIPLIER, AND THIS IS A SECURITY PROPERTY NOT A FORMATTING ONE
--   `056`'s own contract: eod_price carries only a NaN fence (`019:220-223`, no positivity
--   constraint), so a zero-or-negative fx_feed rate would ZERO or SIGN-FLIP the leg. A
--   fence whose correctness depends on price data is not a fence. The fixture seeds a LIVE
--   1.5 EUR rate specifically so that an implementation which applied FX would read 150.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
select is(
  (select balance_native from pfin.fn_account_cash_as_of('2026-03-31'::date) where account_id = :aeur),
  100.0000::numeric,
  '(E4) NATIVE, NO FX: a EUR account holding 100 reads 100 even with a live fx_feed rate of 1.5 available (an FX-applying implementation reads 150). Load-bearing rather than cosmetic: a zero-or-negative rate would zero or SIGN-FLIP the leg and silently admit a closure on a value-bearing account'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- E4b/E4c — WHY (E4) IS A SECURITY PROPERTY, DEMONSTRATED RATHER THAN ARGUED
--   ADR-042 D3: "a fence whose correctness depends on price data is not a fence."
--   `056`'s contract says eod_price carries only a NaN fence (`019:220-223`, no positivity
--   constraint), so a zero-or-negative fx_feed rate would ZERO or SIGN-FLIP the leg. That
--   was an argument. These two assertions make it a measurement.
--   ⟦MEASURED 2026-08-03 with the EUR rate flipped to -1.5000 in a rolled-back savepoint:
--       fn_account_cash_as_of  -> 100.0000      UNAFFECTED
--       fn_compute_nav         -> -150.00000000 SIGN-FLIPPED
--     The measure is IMMUNE to a poisoned rate; the NAV INVERTS. Since the close gate reads
--     the MEASURE, the gate is immune to a rate an attacker or a bad feed controls — which
--     is the whole reason the extraction is native. A sign-flipped NAV is non-null and
--     non-zero, so every liveness-style check passes it; only a QUANTITATIVE assertion sees
--     it. That is why (E4c) asserts a value and not a predicate.⟧
--   ⚑ FIXTURE PROVENANCE (Architect's question, verified rather than recalled): the
--     persistent stack carries **0 eod_price rows, 0 fx_feed rows, 0 non-USD accounts**.
--     EVERY FX row these assertions rely on is seeded INSIDE this transaction. The fixture
--     REACHES the multiplier rather than merely containing a currency column.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
select is(
  (select balance_native from pfin.fn_account_cash_as_of('2026-03-31'::date) where account_id = :aeur),
  100.0000::numeric,
  '(E4b) POISONED-RATE IMMUNITY: with the EUR fx_feed rate NEGATIVE, the measure still reads 100 native. The close gate consumes this function, so a zero-or-negative rate — which eod_price has no constraint against (019:220-223 is a NaN fence only) — cannot move what the gate measures. This is (E4) shown to be load-bearing rather than cosmetic'
);
select set_config('role', 'postgres', true);
savepoint sp_badfx;
update pfin.eod_price set price = -1.5000
 where asset_id = (select asset_id from pfin.asset
                    where users_id is null and asset_type = 'currency' and symbol = 'EUR');
select _rls.set_tenant(:'ta'::uuid);
select cmp_ok(
  (select pfin.fn_compute_nav('2026-03-31'::date, false)), '<', 2750.0000::numeric,
  '(E4c) …AND THE NAV IS NOT IMMUNE — the same negative rate SIGN-FLIPS the cash leg (measured: EUR contributes -150 instead of +150), so the NAV falls below its true value. Asserted QUANTITATIVELY because a sign-flipped NAV is non-null and non-zero and passes every liveness check. ⚑ A RED HERE MEANS THE HAZARD WAS FIXED — an eod_price positivity constraint landed; update this assertion and close the BACKLOG §7.7 item rather than relaxing it'
);
select set_config('role', 'postgres', true);
rollback to savepoint sp_badfx;

-- =====================================================================
-- E5 — ONE DEFINITION, NOT TWO  ⚑ EXPECTED RED against the WIP draft (see header)
--   ADR-042 D3: "fence and NAV share one definition and CAN ONLY FAIL TOGETHER". Asserted
--   structurally, deliberately: two implementations agreeing today is no barrier to
--   divergence tomorrow, and divergence is the entire risk this slice exists to remove.
-- =====================================================================
select ok(
  (select pg_get_functiondef(p.oid) like '%fn_account_cash_as_of%'
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'pfin' and p.proname = 'fn_compute_nav'
      and pg_get_function_arguments(p.oid) = 'p_as_of date, p_active_only boolean'),
  '(E5a) `050` fn_compute_nav CONSUMES the extracted measure rather than keeping its own inline cash_leg. ⚑ EXPECTED RED against the WIP draft — the file creates the function but never re-points its consumers, leaving TWO copies of the roll-forward. Goes green when the refactor half of the slice lands; NOT to be relaxed'
);
select ok(
  (select pg_get_functiondef(p.oid) like '%fn_account_cash_as_of%'
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'pfin' and p.proname = 'fn_account_unrealized_gl'),
  '(E5b) `049` fn_account_unrealized_gl likewise consumes it -> all consumers plus the close gate resolve to ONE definition, which is what makes the ADR-038 foot-to-NAV invariant a real detector rather than a coincidence. ⚑ EXPECTED RED against the WIP draft, same cause as (E5a)'
);

-- =====================================================================
-- E6 — FOOT-TO-NAV, PER LEG (Sec: per-leg, not total-only)
--   With no securities leg seeded for :a1/:aempty, the USD cash sum IS the NAV. A refactor
--   that drifts the cash arithmetic does not FAIL anything — it silently produces a wrong
--   NAV on a surface whose statement-vs-GL detector is unbuilt (BACKLOG §7.4).
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
select is(
  (select sum(balance_native) from pfin.fn_account_cash_as_of('2026-03-31'::date)
     where account_id in (:a1, :aempty)),
  1300.0000::numeric,
  '(E6) FOOT-TO-NAV, cash leg summed over the USD accounts = 1300, matching the NAV cash contribution. Restricted to the USD accounts deliberately: including :aeur would fold the caller''s FX term into a measure that deliberately has none, and the comparison would test the test'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- E8 — CALL SITES USE **LEFT** JOIN (Architect's structural guarantee)
--   The point is asymmetric degradation. If totality ever breaks — a later optimization
--   narrows the function to accounts-with-activity — then:
--     LEFT JOIN  -> missing row becomes NULL -> coalesce -> 0 -> the OLD behaviour. Quiet,
--                   but CORRECT, and (E2a) is the assertion that catches the narrowing.
--     INNER JOIN -> the account VANISHES from the NAV entirely. Silent, and WRONG.
--   One fails safe and one fails wrong. That is worth an assertion by itself.
-- =====================================================================
select ok(
  (select pg_get_functiondef(p.oid) ~* 'left\s+join[^;]*fn_account_cash_as_of|fn_account_cash_as_of[^;]*\)\s*\w*\s*on\s'
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'pfin' and p.proname = 'fn_compute_nav'
      and pg_get_function_arguments(p.oid) = 'p_as_of date, p_active_only boolean'),
  '(E8) `050` joins the measure with a LEFT JOIN, not an inner join. Asymmetric degradation is the whole reason: if totality ever breaks, a LEFT JOIN degrades to NULL->coalesce->0 (the old, correct behaviour) while an INNER JOIN makes the account VANISH from the NAV. One failure mode is loud and recoverable, the other is silent and wrong. ⚑ EXPECTED RED against the WIP draft — the call sites are not re-pointed yet'
);

-- =====================================================================
-- E9 — PER-LEG SEPARATION, ON AN ACCOUNT WHERE BOTH LEGS ARE NON-ZERO
--   ⚑ CORRECTED after Sec's second review, and the correction matters. This assertion
--   previously read "the fixture yields ZERO holdings rows, so the total is the cash leg
--   alone" — which is TRUE and USELESS. With an empty securities leg, per-leg and total-only
--   are THE SAME ASSERTION, and the defect per-leg exists to catch — a refactor that
--   PRESERVES THE TOTAL while SHIFTING VALUE BETWEEN LEGS — cannot occur, let alone be
--   detected. It would have read as covered to anyone auditing the battery later.
--   :asec now holds cash 300 AND 10 shares @ 100 = 1000 securities. The two legs can now
--   disagree, which is the only configuration where the per-leg form beats the total.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
select is(
  (select balance_native from pfin.fn_account_cash_as_of('2026-03-31'::date) where account_id = :asec),
  300.0000::numeric,
  '(E9a) PER-LEG SEPARATION: on an account holding BOTH 300 cash AND 1000 of securities, the cash measure returns exactly 300 — it does NOT absorb the securities value into the cash leg. A refactor that shifted value between legs while preserving the 1300 total passes every total-based check and fails HERE. This is the assertion the empty-leg version could not make'
);
select is(
  (select quantity from pfin.fn_holdings_as_of('2026-03-31'::date)
    where account_id = :asec and asset_id = :a_priced),
  10::numeric,
  '(E9b) FIXTURE ADEQUACY for (E9a): the securities leg is GENUINELY NON-ZERO (10 shares). Without this, (E9a)''s 300 would also be the total and the separation would be untestable — the assertion would look per-leg while being total-only. Same standard as the empty-account row: the fixture must be able to distinguish the two outcomes, or it is not testing the distinction'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- E10 — THE SINGLE-DEFINITION ASSERTION (Sec, closing a gap in its own spec)
--   ⚑ WHY BYTE-IDENTITY IS NOT ENOUGH, and this is the sharp point: if `049`/`050` are
--   NEVER re-pointed, per-leg byte-identity passes TRIVIALLY — nothing changed, so the
--   numbers match by construction. **The check is satisfied most easily by not doing the
--   work.** Byte-identity proves RESULTS MATCH; it cannot prove THE REFACTOR HAPPENED.
--   Two different properties, two assertions. And foot-to-NAV cannot cover the gap either:
--   it compares `049` to `050`, both inline and both unchanged, so it passes. It was never
--   designed to count definitions.
--
--   Runs against the LIVE DATABASE, never the migration files: migrations are append-only,
--   so `049`/`050`'s original inline text survives on disk permanently and a file grep would
--   report the old copy forever.
--
--   ⟦CP7 ADVERSARIAL PROBE — RUN 2026-08-03, and it found TWO defects in the anchor I was
--     given. A pattern that matches nothing reports success on a re-point that never
--     happened, which is precisely the failure this assertion exists to catch, so the
--     pattern was fired against the PRE-re-point definitions before being trusted.
--     Sec proposed anchoring on the `'-infinity'::date` sentinel. Measured on the live DB:
--       fn_account_unrealized_gl          -> 1 hit   ✓ fires
--       fn_compute_nav(date, boolean)     -> 1 hit   ✓ fires
--       fn_compute_nav(date)              -> 0 hits  ✗ the 1-arg WRAPPER never had one; its
--                                            body is `select fn_compute_nav(p_as_of,false)`.
--                                            Asserting on it would be VACUOUS — Sec's spec
--                                            said "both arities".
--       fn_holdings_as_of                 -> 1 hit   ✗ FALSE POSITIVE: it carries its own
--                                            SECURITIES roll-forward, which is legitimate
--                                            and must NOT be removed. The sentinel is not
--                                            unique to the CASH roll-forward.
--     ANCHOR CHANGED to `account_balance_checkpoint` — the cash roll-forward's anchor table,
--     which after the re-point should be reachable ONLY from inside fn_account_cash_as_of.
--     Re-probed on the live DB:
--       fn_account_unrealized_gl      -> 3 refs  ✓ fires, must go to 0
--       fn_compute_nav(date, boolean) -> 2 refs  ✓ fires, must go to 0
--       fn_compute_nav(date)          -> 0 refs  (wrapper — correctly EXCLUDED below)
--       fn_holdings_as_of             -> 0 refs  ✓ no false positive (uses holdings_checkpoint)
--       fn_nav_composition (`051`)    -> 0 refs  ✓ consistent with it composing on `049`
--     Fires where it must, silent where it must be. ⟧
-- =====================================================================
-- ┌─ (E10a) SCHEMA-WIDE SET — ⚠ **REVIEW SIGNAL, NOT A DEFECT SIGNAL** ────────────────┐
-- │ WHAT A RED HERE MEANS: a NEW pfin routine references pfin.account_balance_checkpoint.│
-- │ That may be a LEGITIMATE new consumer (a V1.6 statement-vs-GL tie-out detector would │
-- │ properly read this table) or a FRESH INLINE PASTE of the roll-forward. **YOU CANNOT  │
-- │ TELL WHICH WITHOUT LOOKING.**                                                        │
-- │ WHAT TO DO: read the new routine. If it is a legitimate consumer, EXTEND THE SET     │
-- │ under review. If it re-implements the roll-forward, that is the defect this catches. │
-- │ **DO NOT resolve a red here by deleting the assertion.** An ambiguous red gets        │
-- │ resolved by whoever is fastest, which means relaxed.                                 │
-- │ Contrast (E10b)/(E10c): those are DEFECT signals and are never relaxed.              │
-- └────────────────────────────────────────────────────────────────────────────────────┘
--   ANCHOR: `pfin.account_balance_checkpoint` — SCHEMA-QUALIFIED, and the qualification is
--   load-bearing. Third iteration on this one anchor, each time the same lesson: ANCHOR ON
--   THE PRECISE SUBJECT REFERENCE, NOT ON A TOKEN THAT MERELY CO-OCCURS WITH IT.
--     1. `'-infinity'::date`            — co-occurs with the CASH roll-forward, but is a
--                                         shared idiom; false-positives fn_holdings_as_of.
--     2. bare `account_balance_checkpoint` — co-occurs with functions NAMED for the table.
--                                         pg_get_functiondef returns the HEADER as well as
--                                         the body, so `fn_account_balance_checkpoint_*`
--                                         matches on its own name.
--     3. `pfin.account_balance_checkpoint` — matches only an actual qualified REFERENCE.
--                                         The `fn_` sits between schema and table name, so
--                                         the guard names cannot match.
--   ⟦CORRECTED — I GOT THIS WRONG FIRST TIME. I reported to Sec that the two `018` guards
--     "reference the table for real". They DO NOT. Architect checked the bodies; I then read
--     them myself rather than take either account. The single qualified match is INSIDE A
--     RAISE-MESSAGE STRING LITERAL:
--        raise exception 'pfin.account_balance_checkpoint is immutable (append-only
--        audit-class; ADR-011 Decision 2 / ADR-027 018). % blocked — …', tg_op;
--     The body is plpgsql, uses `tg_op`, and NEVER READS THE TABLE. My bare-vs-qualified
--     count (2 -> 1) correctly showed one match was the function NAME — but I then asserted
--     the surviving match was a reference, which does not follow. A qualified name inside a
--     string literal is indistinguishable from a reference to ANY text anchor.
--     And there is no catalog fallback: Postgres records NO pg_depend edge from a function
--     BODY to a table (which is why a column a function reads can be dropped without
--     complaint), so dependency tracking cannot substitute for text matching here.
--     MEMBERSHIP IS UNCHANGED — they stay in the set — but the REASON is different, and the
--     reason is what a future reader will act on. Verified independently by team-lead at
--     `018:320` and `018:341`: the ONLY occurrences in either body are inside
--     `raise exception '...'` message strings. So these two match the anchor for TWO
--     COSMETIC REASONS AND ZERO SEMANTIC ONES — their own function names, and raise text.
--       fn_account_balance_checkpoint_block_mutation / _block_truncate — `018` immutability
--       triggers bound to the table. They are members because THE ANCHOR MATCHES THE TABLE
--       NAME WHEREVER IT APPEARS — including function names and raise-message text — and
--       these two match on both WITHOUT COMPUTING CASH AT ALL. Bodies use tg_op and never
--       read the table. PERMANENT, EXPECTED, NOT DRIFT. ⟧
--
--   ⚠ THE HONEST LIMIT OF (E10a), stated because a reader who mis-reads it will MIS-SCOPE it:
--     THIS IS A SYNTAX MATCH STANDING IN FOR A SEMANTIC PROPERTY. The set it computes is
--     "routines that MENTION pfin.account_balance_checkpoint" — NOT "routines that COMPUTE
--     CASH". Those are different sets, and the expected membership is the FIRST one.
--     CONSEQUENCE: a NEW cash-computing routine that happens NOT to name the table IS NOT
--     CAUGHT HERE. Anyone assuming the semantic reading will believe this assertion covers
--     a case it does not.
--     >> That gap is what (E12) exists for. (E12) MEASURES THE DEPENDENCY behaviourally
--        rather than describing it syntactically, so it is the assertion that carries the
--        semantic property. (E10a) is strictly more sensitive than the sentinel form it
--        replaced — a partial inline copy escapes a sentinel-keyed check — but it is a
--        proxy, and (E12) is the evidence.
--
--   ⚠ DO NOT "CLEAN" THIS SET BY EXCLUDING TRIGGER FUNCTIONS (`prorettype = 'trigger'`).
--     It is the obvious next simplification — it would collapse the set to
--     {fn_account_cash_as_of} via a principled rule instead of two named members — and it
--     would be a SERIOUS MISTAKE (Sec):
--       THE CLOSE GATE IS ITSELF IMPLEMENTED AS TRIGGERS, AND THE GATE MEASURES CASH.
--       Under correct implementation it calls fn_account_cash_as_of. An INLINE COPY IN THE
--       GATE TRIGGER is exactly the proliferation this assertion exists to catch — the most
--       tempting to write and the most harmful if written, because the fence and NAV would
--       then diverge SILENTLY, which is the whole D2-vs-D3 argument the extraction rests on.
--     Excluding trigger functions makes this assertion BLIND TO THE SINGLE WORST CASE IT
--     COULD EVER CATCH. Two named members with a recorded reason is the cheap price.
--
--   ⚑ THE PATTERN, worth one line because it is the same assertion every time: THREE
--     "cleaner" versions of this check would each have been WEAKER —
--       sentinel anchor      -> collides with the holdings roll-forward
--       bare table name      -> matches routines NAMED for the table
--       exclude triggers     -> blind to an inline copy in the close gate
--     Each simplification traded COVERAGE for TIDINESS. The elaboration was the tell that
--     the assertion is a REVIEW signal, whose category tolerates named exemptions —
--     unlike (E10b)/(E10c), which are DEFECT signals on named functions where an anchor
--     collision cannot reach them and no exemption is ever acceptable.
--
--   ⟦SWEEP SHAPE — MEASURED 2026-08-03, and the cause is not what either reviewer stated.
--     pfin contains 51 routines, ALL prokind='f'. ZERO aggregates. So the `array_agg` throw
--     was never about an aggregate living in pfin.
--       A: `join pg_namespace n ... where n.nspname='pfin' and <fn> like ...`  -> THROWS
--       B: `where pronamespace='pfin'::regnamespace and <fn> like ...`         -> works (4)
--     ⟦RESOLVED 2026-08-03 — mechanism REPRODUCED INDEPENDENTLY, so this is no longer a
--       single-source claim. Plan evidence (QA) + execution evidence (Architect), same DB:
--         EXPLAIN alone            -> succeeds (plans, does NOT execute the qual)
--         EXPLAIN ANALYZE / bare   -> THROWS
--         issued via psql -f       -> THROWS (not a shell/quoting artifact)
--       Plan: `Filter: pg_get_functiondef(oid) ~~ ...` sits on the **Seq Scan on pg_proc**
--       (cluster-wide) while `nspname='pfin'` survives only as a **Join Filter** applied
--       after. Scoped in text, unscoped in execution.
--       ⟦THE CONSOLIDATION — read this instead of collecting per-tool traps (Sec).
--         SIX instrument failures surfaced across this battery's review. They are NOT six
--         rules. Every one has the SAME structure:
--             **THE PASS CONDITION WAS REACHABLE WITHOUT ENGAGING THE SUBJECT.**
--
--           instrument                              | passed without
--           ----------------------------------------|----------------
--           EXPLAIN (no ANALYZE)                     | executing
--           count(*) over an unconsumed projection   | evaluating
--           under-matching grep (omitted `cmp_ok`)   | matching
--           `prokind='f'` allowlist / `\.test\.` filter | covering
--           fixture with an empty securities leg     | distinguishing
--           the paired-artifact check                | CORRESPONDING
--           the close-gate guard on 4 active rows    | firing
--
--         SEVEN now. The `covering` row has TWO instances from two people and two tools —
--         my `prokind='f'` (drops procedures) and Architect's `\.test\.` filter (excluded
--         TypeScript tests but not `test_*.py`, asymmetric by language, inside the sweep
--         demonstrating reachability-scoping). Two authors, same row: that is what makes it
--         a class rather than either person's style.
--         The `CORRESPONDING` row is Sec's and is a genuinely distinct axis — not executing,
--         evaluating, matching, covering, distinguishing or firing. When these batteries were
--         authored against the WITHDRAWN single-file design, the standing paired-artifact
--         check (migration + battery both in the diff) PASSED: both files present, correctly
--         named, correctly numbered — while the battery tested a contract that had MOVED TO A
--         DIFFERENT FILE. Presence is not correspondence.
--
--         That is LAZIEST-SATISFIER (Architect's rule) applied to MEASUREMENTS rather than
--         to ASSERTIONS: *ask what the least work is that produces this result; if that work
--         is "nothing", it is not evidence.* For the count(*) case, the least work producing
--         "51, no error" is never evaluating the function.
--         And CP7 is how you TEST it — probe with a known-present case, **at the INVOCATION
--         level, not merely the method level.** That refinement is what catches the count(*)
--         case: `count(*)` is a perfectly good instrument, CORRECTLY CHOSEN AND VACUOUSLY
--         CALLED. The tool choice survives review — "did you run a real query rather than an
--         EXPLAIN?" gets a yes — because the defect is INSIDE the query.
--
--         ⚠ THE ASYMMETRY, which is the reason any of this matters:
--           a vacuous ASSERTION fails SAFE — reports green, someone eventually notices.
--           a vacuous MEASUREMENT reports "does not reproduce" and ACTIVELY OVERTURNS A
--           CORRECT OBSERVATION. Same defect class, opposite blast radius, and only one of
--           the two is on anybody's checklist.
--
--         The two named instruments below are EXAMPLES UNDER THIS RULE, not rules of their
--         own — otherwise the list grows one entry per tool and still misses the seventh:
--         (1) `count(*)`-ELISION — Architect's, REPRODUCED, **the actual cause here.**
--         (2) `EXPLAIN`-CANNOT-THROW — mine, MEASURED and TRUE, **not the cause here.**
--             I offered it as the explanation of Architect's non-reproduction and that
--             ATTRIBUTION was wrong; their shapes were real executions. The FACT stands
--             and is kept deliberately: someone will reach for EXPLAIN as a cheap
--             "does it run?" check exactly as Architect reached for count(*).
--             Recorded separately because binding a fact to the argument it arrived in is
--             how a TRUE finding gets discarded when its attribution is corrected. Usually
--             a WRONG claim survives because its conclusion was right; here a RIGHT claim
--             was at risk because its conclusion was wrong. Same root, opposite direction.⟧
--       ⚠ AND A TRAP FOR ANYONE TESTING A SWEEP LIKE THIS — Architect's non-reproduction was
--         caused by it: `select count(*) from (select pg_get_functiondef(...) d from ... ) s`
--         returns a clean row count and NEVER THROWS, because **`d` is never consumed, so
--         Postgres elides the function call entirely.** The test passes by not doing the
--         work. Restoring the `LIKE` — which forces evaluation — makes it throw. If you are
--         checking whether a catalog sweep executes, the function's result MUST be consumed
--         by a predicate; a bare projection proves nothing.
--       >> BOTH FORMS ARE PLAN-DEPENDENT: the join form pushes the qual down, and the no-join
--          form works only by COST-BASED ORDERING within a single filter. Neither is a
--          semantic guarantee. **The fence is the only unconditional form** — which is why
--          the instruction was correct throughout, including while the mechanism was unknown.⟧
--     THE CAUSE IS THE JOIN: the planner may evaluate pg_get_functiondef BEFORE the
--     namespace filter is applied, reaching pg_catalog's array_agg. The query is LOGICALLY
--     scoped but not EVALUATION-ORDER scoped. A direct predicate on pg_proc filters first.
--     So the rule is not "scope the sweep" (mine was scoped) but: A NAMESPACE FILTER REACHED
--     THROUGH A JOIN DOES NOT CONSTRAIN EVALUATION ORDER.
--     >> AND THE LESSON GOES ONE LAYER FURTHER (Sec). Form B works because the planner
--        HAPPENS to apply the pronamespace predicate at scan time before evaluating
--        pg_get_functiondef — a PLAN CHOICE, not a semantic guarantee. Postgres does not
--        guarantee WHERE-clause evaluation order, so a different row count, statistics
--        snapshot or PG version can reorder it and form A's error returns from a query
--        nobody edited. Form D — the `offset 0` optimization fence — is the documented
--        barrier for exactly this case ("a function that errors on some rows") and is
--        correct BY CONSTRUCTION rather than by predicate ordering. **Form D adopted.**
--        This is the same distinction as the `'-infinity'` anchor "only ever worked as an
--        accident of predicate ordering" — which applies to the REPLACEMENT as much as to
--        the thing replaced.
--     `prokind` is a DENYLIST here, not an allowlist, per Sec's rule — a fence too narrow is
--     loud, a DETECTOR too narrow MISSES and its silence reads as absence. Exclude only what
--     actually throws, MEASURED rather than assumed:
--       prokind='a' (aggregate) -> THROWS       -> excluded
--       prokind='w' (window)    -> does NOT throw -> NOT excluded (measured, not guessed)
--       prokind='p' (procedure) -> handled fine   -> NOT excluded; an allowlist would have
--                                  silently dropped a procedure carrying an inline copy ⟧
select set_eq(
  $$ select q.proname::text from (
         select p.oid, p.proname from pg_proc p
          where p.pronamespace = 'pfin'::regnamespace and p.prokind <> 'a'
          offset 0                      -- OPTIMIZATION FENCE: see the sweep-shape note
       ) q
      where pg_get_functiondef(q.oid) like '%pfin.account_balance_checkpoint%' $$,
  $$ values ('fn_account_balance_checkpoint_block_mutation'::text),
            ('fn_account_balance_checkpoint_block_truncate'),
            ('fn_account_cash_as_of') $$,
  '(E10a) REVIEW SIGNAL — schema-wide TEXT-MENTION set (NOT a computes-cash set; see the honest-limit note): the pfin routines whose TEXT MENTIONS pfin.account_balance_checkpoint are EXACTLY the table''s two `018` mutation/truncate GUARDS (members because the anchor matches the table NAME wherever it appears — their own function names AND raise-message text — without computing cash at all; bodies use tg_op and never read it. Permanent, expected, NOT drift) plus fn_account_cash_as_of (the one cash home). A red means a NEW routine touches the table: LOOK, then extend the set under review. Do NOT delete this assertion to resolve a red. Catches PROLIFERATION into unknown consumers, which (E10b)/(E10c) structurally cannot. ⚑ EXPECTED RED until the re-point lands — measured live pre-re-point the set also contains fn_account_unrealized_gl and fn_compute_nav(date,boolean)'
);
select is(
  (select (length(pg_get_functiondef(p.oid))
           - length(replace(pg_get_functiondef(p.oid), 'pfin.account_balance_checkpoint', '')))
          / length('pfin.account_balance_checkpoint')
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'pfin' and p.proname = 'fn_compute_nav'
      and pg_get_function_arguments(p.oid) = 'p_as_of date, p_active_only boolean'),
  0,
  '(E10b) DEFECT SIGNAL — NEVER RELAX: `050` fn_compute_nav(date,boolean) reaches account_balance_checkpoint ZERO times (probed at 2 refs pre-re-point, so it demonstrably fires). A red here means the re-point REGRESSED or never happened — unambiguous, unlike (E10a). Paired with (E5a)''s MUST-CONTAIN half: absence-of-inline alone is satisfiable by DELETING the cash leg, presence-of-call alone by calling it and ignoring the result. Neither has a lazy satisfier once paired. ⚑ EXPECTED RED until the re-point lands'
);
select is(
  (select (length(pg_get_functiondef(p.oid))
           - length(replace(pg_get_functiondef(p.oid), 'pfin.account_balance_checkpoint', '')))
          / length('pfin.account_balance_checkpoint')
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'pfin' and p.proname = 'fn_account_unrealized_gl'),
  0,
  '(E10c) DEFECT SIGNAL — NEVER RELAX: `049` fn_account_unrealized_gl likewise reaches it zero times (probed at 3 refs pre-re-point). Asserted per-function ALONGSIDE the schema-wide (E10a), not instead of it: per-function catches REGRESSION in the two known consumers; only schema-wide catches PROLIFERATION into new ones. ⚑ EXPECTED RED until the re-point lands'
);

-- =====================================================================
-- E11 — THE 1-ARG WRAPPER STILL DELEGATES (Architect; replaces a vacuous assertion)
--   Sec's original spec said to assert the no-inline property on `fn_compute_nav` "both
--   arities". The 1-arg is PURE DELEGATION — `select pfin.fn_compute_nav(p_as_of, false)` —
--   so it carries neither the sentinel nor any table reference, and "must not contain X"
--   passes on it VACUOUSLY. An assertion that cannot fail is not evidence, so the wrapper
--   is excluded from (E5)/(E10b)/(E10c).
--   ⚑ But DELETING it would leave the wrapper untested and read as scope reduction. The
--   property actually worth asserting is the one `037`'s GL memo depends on: that the
--   wrapper still delegates to the 2-arg with false. Replacing a vacuous assertion beats
--   removing one.
-- =====================================================================
select ok(
  (select pg_get_functiondef(p.oid) like '%fn_compute_nav(p_as_of, false)%'
       or pg_get_functiondef(p.oid) like '%fn_compute_nav(p_as_of,false)%'
     from pg_proc p
    where p.pronamespace = 'pfin'::regnamespace and p.proname = 'fn_compute_nav'
      and pg_get_function_arguments(p.oid) = 'p_as_of date'),
  '(E11) the 1-arg fn_compute_nav wrapper still DELEGATES to the 2-arg with false — the all-accounts book/as-of engine `037`''s GL memo depends on. Replaces the vacuous "wrapper contains no inline roll-forward", which passes by construction because the wrapper is pure delegation and never had one. The re-point must not quietly turn the wrapper into a second implementation'
);

-- =====================================================================
-- E12 — ⭐ BEHAVIOURAL DEPENDENCY PROOF (Sec) — the assertion that makes E5/E10 belt-and-braces
--   THE PROBLEM IT SOLVES: every other single-definition assertion in this file inspects
--   CATALOG TEXT. Text inspection has no natural failure mode to calibrate against — every
--   anchor LOOKS fine until someone enumerates, which is why that one assertion took four
--   anchors and three corrections. This one MEASURES THE DEPENDENCY instead of describing it.
--
--   METHOD: substitute a SENTINEL fn_account_cash_as_of that returns 0.0000 for every
--   account, in a rolled-back savepoint, then re-read the NAV.
--     · consumer genuinely DEPENDS on the function -> its cash leg collapses to zero
--     · consumer carries an INLINE COPY            -> its output DOES NOT MOVE
--     · consumer carries a PARTIAL copy            -> it moves by LESS than the full delta
--   A quantitative behavioural assertion catches what no text pattern can, because a
--   partial inline copy is invisible to any anchor that the partial copy happens to omit.
--
--   ⟦MEASURED ON THE LIVE FIXTURE 2026-08-03 so the expected values are pinned, not guessed:
--     baseline nav(2026-03-31, false) under tenant A = 2750.0000
--       = cash 1750 (a1 1300 + aempty 0 + aeur 100 EUR x 1.5 fx + asec 300)
--       + securities 1000 (asec: 10 QAPRC @ 100; QAPRC.currency = 'USD', so NO fx term)
--     With the cash function zeroed, nav must fall to the SECURITIES LEG ALONE = 1000.0000.
--     Zeroing sidesteps FX entirely — any multiplier times 0 is 0 — so the expected value
--     needs no re-implementation of the fx logic in the test. ⟧
--
--   ⚠⚠ MANDATORY — RECORD THE DATABASE STATE WHEN YOU RUN THIS. A BEHAVIOURAL RESULT IS
--     UNINTERPRETABLE WITHOUT IT (Sec, after I misattributed exactly this). Interpretation
--     table for (E12b):
--       DB at < `056`     -> fn_account_cash_as_of does not exist / no consumer re-pointed.
--                            NAV does NOT move. **RED IS EXPECTED AND MEANS NOTHING.** This
--                            is NOT evidence of a defect in anyone's re-point.
--       DB at >= `056`    -> NAV MUST fall to 1000.0000. A red here IS a genuine finding:
--                            a consumer is not actually depending on the function.
--     A red cannot be distinguished from "this DB predates the change", and a green cannot be
--     distinguished from "this DB already had it", unless the applied migration set is
--     reported alongside the result. Report it every run.
--     ⟦My own probe 2026-08-03 ran at migration **051** — verified, fn_account_cash_as_of
--       absent from pg_proc — so its non-moving NAV was the CORRECT result for that state and
--       I wrongly reported it as the half-slice defect demonstrated. Recorded so the next
--       reader does not repeat the inference.⟧
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
select is(
  (select pfin.fn_compute_nav('2026-03-31'::date, false)),
  2750.0000::numeric,
  '(E12a) BASELINE, non-vacuity anchor for (E12b): tenant A''s NAV is 2750.0000 (cash 1750 incl. the EUR account at fx 1.5, plus securities 1000). Without a pinned baseline, (E12b) could pass against a NAV that was already 1000 for unrelated reasons'
);
select set_config('role', 'postgres', true);
savepoint sp_perturb;
-- Sentinel substitution. NOT a re-implementation of the real body — a deliberately trivial
-- stand-in, so this does not repeat the "test your own copy" mistake the battery refuses
-- elsewhere. Signature/volatility/security posture preserved so the swap is transparent.
create or replace function pfin.fn_account_cash_as_of(p_as_of date)
returns table (account_id bigint, balance_native numeric)
language sql security invoker stable set search_path = '' as $sentinel$
  select acc.account_id, 0.0000::numeric from pfin.account acc
$sentinel$;
select _rls.set_tenant(:'ta'::uuid);
select is(
  (select pfin.fn_compute_nav('2026-03-31'::date, false)),
  1000.0000::numeric,
  '(E12b) ⭐ BEHAVIOURAL DEPENDENCY: with fn_account_cash_as_of substituted by a sentinel returning 0 for every account, the NAV falls to the SECURITIES LEG ALONE (1000.0000). This proves `050` genuinely DEPENDS on the function rather than merely MENTIONING it — the property (E5)/(E10) can only proxy for. An inline copy leaves the NAV at 2750; a PARTIAL copy lands strictly between, which no text anchor can detect. ⚑ EXPECTED RED until the re-point lands — and its red IS the half-slice defect, demonstrated'
);
select set_config('role', 'postgres', true);
rollback to savepoint sp_perturb;

-- =====================================================================
-- E7 — GRANT POSTURE
-- =====================================================================
select ok(
  not has_function_privilege('anon', 'pfin.fn_account_cash_as_of(date)', 'execute')
  and has_function_privilege('authenticated', 'pfin.fn_account_cash_as_of(date)', 'execute'),
  '(E7) EXECUTE revoked from PUBLIC (so anon cannot reach it) and granted to authenticated only. Asserted as a PAIR: the revoke alone would also pass if the grant had been forgotten, leaving the read path broken rather than merely closed'
);

select * from finish();
rollback;
