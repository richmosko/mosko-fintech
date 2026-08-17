-- =====================================================================
-- Per-Wave battery — the price-pick same-date tie-break made TOTAL, across
--   every live copy of the kernel (Sec joint-review ruling (1), PR #480 /
--   SELF-237; V1-SHIP-BLOCK). Read-only fix: NO new table, NO new DEFINER,
--   NO new FK-shaped column, NO signature/grant/comment change.
-- =====================================================================
-- BINDS TO MIGRATION: supabase/migrations/078_price_pick_tiebreak_cross_copy.sql
--   Appends `ep.price_id desc` as a FINAL tiebreak (after price_date desc, then
--   the source-rank CASE) to the price-pick site in THREE live kernel copies:
--     · pfin.fn_account_unrealized_gl(date)
--     · pfin.fn_compute_nav(date, boolean)
--     · pfin.fn_subcat_market_value(date, boolean)
--   `eod_price` is unique on (asset_id, price_date, source) but the CASE
--   assigns rank 2 to THREE sources (market_feed / spot_feed / fx_feed), so an
--   asset with two same-date rank-2 observations was previously a genuine tie
--   — `limit 1` resolved it nondeterministically. price_id is a bigint identity
--   PK (019), so appending it makes the order TOTAL: the tie now resolves,
--   repeatably, to the MOST RECENTLY INSERTED observation (highest price_id).
--
-- ┌─ WHY A TOTALS-ONLY BATTERY WOULD PASS EITHER WAY (078''s own header) ───┐
-- │ "On data with no same-date same-rank tie the output is identical, which │
-- │ is most fixtures — so a battery that only asserts totals will go green  │
-- │ whether or not this migration applied. The assertion that discriminates │
-- │ is a fixture that PLANTS the tie ... and asserts the higher price_id    │
-- │ wins, repeatably. Without that leg the fix has no watcher."             │
-- │ The fixture below plants EXACTLY that shape, ANTI-CORRELATED with price │
-- │ magnitude on purpose: the HIGHER-price row is inserted FIRST (lower     │
-- │ price_id) and the LOWER-price row SECOND (higher price_id). The correct │
-- │ (post-fix) answer is the LOWER price — a regression that fell back to   │
-- │ "highest price wins" or any other plausible-looking heuristic would go  │
-- │ RED here, not silently agree by coincidence.                            │
-- └───────────────────────────────────────────────────────────────────────┘
--
-- Prereqs exercised (on the 001->078 stack): 016/017 (global asset registry,
--   currency assets); 019 (eod_price unique(asset_id,price_date,source) +
--   price_id identity PK + fn_holdings_as_of); 041 (seeded taxonomy
--   vocabulary, reused for the fn_subcat_market_value leg); 076
--   (fn_subcat_market_value, the third live kernel copy).
--
-- §10 / DECISION 3: §10 ledger UNCHANGED (078 changes an ORDER BY inside three
--   read-only SQL functions — no credential surface, no code-layer fence, no
--   network/config surface; read ADR-011 Decision 4 live). Decision-3 family
--   UNCHANGED — `ep.price_id` is eod_price''s own PK read inside an ORDER BY,
--   not a stored reference. This battery introduces no catalogued instance.
--
-- POSTURE (SECURITY §4.5): SYNTHETIC ONLY — fixed-UUID tenants (raw literals,
--   suffixed '78'). NO PII / NO real account numbers / NO prod data. All seeds
--   PRIVILEGED (role=postgres) with users_id set EXPLICITLY. Whole file in one
--   rolled-back txn.
--
-- ----------------------------------------------------------------------------
-- KERNEL-IDENTITY FENCE + GOLDEN FIXTURE + EXECUTE-ACL (SELF-328, added on
--   feature/self328-kernel-fence — Sec ruling, F/CTO-funded at the SELF-237
--   review; spec CORRECTED at PR #485 once 078 itself split the kernel into
--   two generations, see FENCE1a/b/c below). Riding this same file per
--   SELF-328's own scope: "a pgTAP catalog leg in the 078 battery, owned by
--   QA." FENCE1c added at Sec''s AMBER verdict on this branch (below) —
--   closes a NULL-hole Sec found in FENCE1b, their own spec gap ("they never
--   specified assert the extraction matched").
-- ----------------------------------------------------------------------------
--
-- ⟦WIRE-VALIDATE⟧ authored + fixture-verified GREEN via a transient apply of
--   001->079 against a POSTGRES-OWNED scratch DB with ZERO cluster-level
--   grants (evidence for SELF-327 — see the hand-off). plan(14): 1 structural
--   (S1) + 3 cross-copy value (K1-K3) + 1 cross-copy identity (K4) + 1
--   repeatability (REPEAT1) + 1 isolation (I1) + 3 kernel-identity fence
--   (FENCE1a-c) + 2 golden-fixture (GOLDEN1-2) + 2 EXECUTE-ACL (ACL1-2) = 14.
--   One fixture mistake caught this way before landing: an EARLY DRAFT left
--   a_inv/b_inv UNFUNDED (no checkpoint) — fn_account_cash_as_of sums
--   account_trans.amount back to -infinity with no checkpoint to bound it, so
--   the buy''s own -100.00/-60.00 cash debit exactly cancelled the security
--   value in K1/K2/K4/I1 (all read 0.00, measured, not assumed), while K3
--   (fn_subcat_market_value) passed regardless because its cash leg lands in a
--   DIFFERENT, unclassified row. Fixed the same way 076 was: fund each account
--   to net exactly zero.
-- =====================================================================

begin;

\ir ../_fixtures/rls_verbs.psql

select plan(14);

\set ta '00000000-0000-0000-0000-00000000a078'
\set tb '00000000-0000-0000-0000-00000000b078'

insert into auth.users (id) values (:'ta'), (:'tb');

-- ---------------------------------------------------------------------
-- STRUCTURAL (S1) — the `ep.price_id desc` tiebreak text is present in the
--   prosrc of all THREE live kernel copies. Scoped to a substring that can
--   ONLY appear in the executable ORDER BY (062''s lesson: a bare grep can
--   hit header prose, but these function bodies carry no inline comments).
-- ---------------------------------------------------------------------
select ok(
  (select p.prosrc ilike '%ep.price_id desc%'
     from pg_proc p
    where p.proname = 'fn_account_unrealized_gl' and p.pronamespace = 'pfin'::regnamespace)
  and
  (select p.prosrc ilike '%ep.price_id desc%'
     from pg_proc p
    where p.proname = 'fn_compute_nav' and p.pronargs = 2 and p.pronamespace = 'pfin'::regnamespace)
  and
  (select p.prosrc ilike '%ep.price_id desc%'
     from pg_proc p
    where p.proname = 'fn_subcat_market_value' and p.pronamespace = 'pfin'::regnamespace),
  '(S1) STRUCTURAL: `ep.price_id desc` is present in prosrc of all THREE live kernel copies (fn_account_unrealized_gl, fn_compute_nav(date,boolean), fn_subcat_market_value) — a future CREATE OR REPLACE that silently drops the tiebreak text goes RED here even on fixtures with no planted tie'
);

-- ---------------------------------------------------------------------
-- FIXTURE. Tenant A: one investment account (a_inv) holding ONE security
--   (secT, qty 1) with a PLANTED same-date tie: 'market_feed' @150.00
--   inserted FIRST (lower price_id), 'spot_feed' @100.00 inserted SECOND
--   (higher price_id). Both source ranks = 2 (tied on price_date AND rank).
--   Correct post-fix answer: 100.00 (highest price_id), NOT 150.00.
--   Classified to Equity for the fn_subcat_market_value leg. a_inv is FUNDED
--   via a checkpoint dated BEFORE the trade, to EXACTLY offset the buy''s cash
--   debit (076''s own convention: fn_account_cash_as_of sums account_trans
--   amounts back to -infinity when NO checkpoint bounds them, so an unfunded
--   buy would net the security''s value to ZERO against its own -100.00 cash
--   debit — measured while drafting this fixture, then fixed the same way 076
--   was; see 076''s header, "funded to net exactly zero... so the arithmetic
--   stays legible").
-- Tenant B: isolation control — one DIFFERENT security (secB, qty 1,
--   single UNTIED price 60.00) in its own account, funded the same way.
--   Real, non-vacuous value, distinct from A''s 100.00.
-- ---------------------------------------------------------------------
insert into pfin.asset (users_id, asset_type, pricing_source, symbol, name) values
  (null,'equity','market_feed','SBT78','Sec T tie-planted') returning asset_id as sect \gset
insert into pfin.asset (users_id, asset_type, pricing_source, symbol, name) values
  (null,'equity','market_feed','SBB78','Sec B isolation control') returning asset_id as secb \gset

-- planted tie: higher price first (lower price_id), lower price second
-- (higher price_id) — anti-correlates price magnitude with price_id so a
-- "highest price wins" regression cannot pass by coincidence.
insert into pfin.eod_price (asset_id, price_date, source, price) values
  (:sect,'2026-08-01','market_feed',150.00);
insert into pfin.eod_price (asset_id, price_date, source, price) values
  (:sect,'2026-08-01','spot_feed',100.00);
insert into pfin.eod_price (asset_id, price_date, source, price) values
  (:secb,'2026-08-01','market_feed',60.00);

insert into pfin.user_taxonomy (users_id, domain, cat, sub_cat) values
  (:'ta','asset','Equity','US-06-Financials') returning id as a_eq \gset

insert into pfin.account (users_id, name, account_type, scope, tax_treatment) values
  (:'ta','a-inv-78','investment','household','taxable') returning account_id as a_inv \gset
insert into pfin.account_balance_checkpoint (account_id, balance, currency, as_of_date, source) values
  (:a_inv, 100.00, 'USD', '2026-07-25', 'seed');
insert into pfin.account_trans (account_id, transaction_date, amount, quantity, security_id, cost_basis, transaction_type, vendor) values
  (:a_inv,'2026-08-01',-100.00,1,:sect,100.00,'standard','buy-t');
insert into pfin.user_asset_category (users_id, asset_id, sub_cat_id) values
  (:'ta', :sect, :a_eq);

insert into pfin.account (users_id, name, account_type, scope, tax_treatment) values
  (:'tb','b-inv-78','investment','household','taxable') returning account_id as b_inv \gset
insert into pfin.account_balance_checkpoint (account_id, balance, currency, as_of_date, source) values
  (:b_inv, 60.00, 'USD', '2026-07-25', 'seed');
insert into pfin.account_trans (account_id, transaction_date, amount, quantity, security_id, cost_basis, transaction_type, vendor) values
  (:b_inv,'2026-08-01',-60.00,1,:secb,60.00,'standard','buy-b');

-- =====================================================================
-- CROSS-COPY VALUE (K1-K3) — same planted tie, same expected winner
-- (100.00 = the higher price_id row), asserted through all THREE live
-- kernel copies independently.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);

select is(
  (select current_market_value from pfin.fn_account_unrealized_gl('2026-08-05'::date) where account_id = :a_inv),
  100.00::numeric,
  '(K1) fn_account_unrealized_gl: current_market_value = EXACTLY 100.00 (the higher-price_id observation, spot_feed@100.00 inserted SECOND) — NOT 150.00 (market_feed, inserted first, still lower price_id)'
);
select is(
  pfin.fn_compute_nav('2026-08-05'::date, false),
  100.00::numeric,
  '(K2) fn_compute_nav(date,boolean), the SECOND live kernel copy: NAV = EXACTLY 100.00 (identical tie-break result to K1, cash leg netted to 0 by construction — no checkpoint seeded)'
);
select is(
  (select market_value from pfin.fn_subcat_market_value('2026-08-05'::date, true) where sub_cat_id = :a_eq),
  100.00::numeric,
  '(K3) fn_subcat_market_value, the THIRD live kernel copy: the classified Equity Sub-Cat''s market_value = EXACTLY 100.00 (identical tie-break result to K1/K2)'
);

-- =====================================================================
-- (K4) CROSS-COPY IDENTITY — the point of "cross_copy" in the migration''s
--   own name: all three copies resolve the SAME tie to the SAME value, not
--   merely each individually matching 100.00 by chance of independent bugs.
-- =====================================================================
select ok(
  (select current_market_value from pfin.fn_account_unrealized_gl('2026-08-05'::date) where account_id = :a_inv)
    = pfin.fn_compute_nav('2026-08-05'::date, false)
  and
  pfin.fn_compute_nav('2026-08-05'::date, false)
    = (select market_value from pfin.fn_subcat_market_value('2026-08-05'::date, true) where sub_cat_id = :a_eq),
  '(K4) ⭐ CROSS-COPY IDENTITY: fn_account_unrealized_gl, fn_compute_nav(date,boolean) and fn_subcat_market_value resolve the SAME planted tie to the IDENTICAL value — the textual-identity protected property (076: "copies that read identically can be diffed; copies that read differently cannot") holds for this fix specifically, not just in the abstract'
);

-- =====================================================================
-- (REPEAT1) REPEATABILITY — 078''s header: "asserting the higher price_id
--   wins repeatably". Two consecutive calls, same statement, same txn,
--   return the IDENTICAL value — guards against a plan that happens to be
--   deterministic once but not on re-evaluation.
-- =====================================================================
select is(
  (select current_market_value from pfin.fn_account_unrealized_gl('2026-08-05'::date) where account_id = :a_inv),
  (select current_market_value from pfin.fn_account_unrealized_gl('2026-08-05'::date) where account_id = :a_inv),
  '(REPEAT1) repeatability: two consecutive calls to fn_account_unrealized_gl over the SAME planted tie return the IDENTICAL value (100.00) within the same transaction'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- (I1) ISOLATION — tenant B''s own (untied) value is unaffected by, and does
--   not include, A''s tie-planted value. Real, non-vacuous companion.
-- =====================================================================
select _rls.set_tenant(:'tb'::uuid);
select is(
  (select current_market_value from pfin.fn_account_unrealized_gl('2026-08-05'::date) where account_id = :b_inv),
  60.00::numeric,
  '(I1) isolation, non-vacuous: tenant B''s current_market_value = EXACTLY 60.00 (B''s OWN untied holding) — does not include A''s 100.00, and the tie-break fix does not perturb an unrelated tenant''s unrelated data'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- KERNEL-IDENTITY FENCE (SELF-328) — LIVE CATALOG ONLY (pg_proc.prosrc), NOT
--   migration text. Sec''s ORIGINAL predicate ("every migration containing the
--   manual_valuation rank clause -> one hash") was CORRECTED at PR #485: after
--   078 itself, migration TEXT spans TWO kernel generations (8 pre-078 blocks
--   in applied history + these 3 post-078 copies), so a text-grep predicate
--   would go RED on CORRECT code. The catalog holds only LIVE definitions —
--   "live" is free.
--
--   Over the set of pfin functions whose prosrc matches the price-pick rank
--   clause: extract the kernel block from `case ep.source` through the
--   price-pick subquery''s OWN closing `limit 1)` — deliberately NOT anchored
--   on `ep.price_id desc`, because that text is EXACTLY what the golden
--   fixture below removes; anchoring there would make a corrupted copy fail
--   to match at all (substring -> NULL -> excluded by `count(distinct)`,
--   which IGNORES nulls) and the fence would silently pass on its own target
--   mutation. Anchoring on `limit 1)` instead means a corrupted block is still
--   CAPTURED, just SHORTER — and hashes differently, which is what makes
--   GOLDEN1 below a real RED rather than a false green.
--
--   Then normalize LEADING whitespace per line (`regexp_replace(..., '^[ \t]+',
--   '', 'ng')`) — the three copies sit at genuinely different nesting depths.
--   MEASURED, not assumed: fn_account_unrealized_gl''s raw block is 390 chars,
--   the other two are 372 — byte-identical ONLY after normalization. Then
--   assert ALL THREE:
--     FENCE1a — count(*) = 3.        DISCOVERY half (ADR-057''s discriminator
--       shape): a 4th kernel copy anywhere is a RED that FORCES A DECISION,
--       the same deliberate-watcher shape as 041''s hardcoded counts.
--     FENCE1b — count(distinct md5(normalized)) = 1.   IDENTITY half: every
--       live copy reads byte-for-byte the same after normalization.
--     FENCE1c — count(kernel_block) = 3.   EXTRACTION half (Sec AMBER
--       condition, PR #485 review of this branch — closed here). MEASURED
--       COMPOSITION GAP: the population filter (`ilike`) is case-INSENSITIVE
--       but the extraction (`substring ... from '(?s)case ep\.source...'`) is
--       case-SENSITIVE. An uppercase `CASE ep.source` rewrite stays IN the
--       population (FENCE1a green) but extracts to NULL, and
--       `count(distinct)` IGNORES nulls (FENCE1b green too) — an arbitrarily
--       diverged copy passes BOTH existing legs. REPRODUCED before fixing:
--       corrupting fn_compute_nav''s `case` to `CASE` (derived from its own
--       live prosrc, not hand-typed) measured population=3 / distinct=1
--       (both falsely green) / count(kernel_block)=2 — FENCE1c is what turns
--       that 2 into the RED. GENERAL by construction, not per-vector: catches
--       ANY reason extraction fails (case, a whitespace-tokenization miss, the
--       anchor text itself moving) — Sec explicitly REJECTED an `(?i)` patch
--       as "the evasion I happened to find," not a structural fix.
--   ⚠ Sec STANDING CONSTRAINT, satisfied by construction: asserts the
--   count-distinct PREDICATE, never equality against a PINNED digest — a hash
--   is a property of the NORMALIZATION PIPELINE, not of the code; two
--   independently-written correct pipelines measured DIFFERENT literal values
--   over identical blocks (Sec, PR #485). No literal md5 string appears
--   anywhere in this file.
--   ⚠ MAINTENANCE NOTE (the meta-lesson under the AMBER condition): the
--   `kernel_fns` extraction CTE is intentionally DUPLICATED across FENCE1b /
--   FENCE1c / GOLDEN1 / GOLDEN2 (pgTAP''s `is()` needs a self-contained
--   subquery per assertion — no shared view/function exists for it in this
--   file). Any FUTURE change to the extraction pattern (the substring anchor
--   or the `ilike` population filter) MUST be applied at all FOUR sites, or
--   it silently reopens a hole of exactly this shape at whichever site was
--   missed — this is the general form of the specific gap FENCE1c closes.
-- =====================================================================
select is(
  (select count(*) from pg_proc p
    where p.pronamespace = 'pfin'::regnamespace
      and p.prosrc ilike '%when ''manual_valuation'' then 1%'),
  3::bigint,
  '(FENCE1a) kernel-identity DISCOVERY: exactly 3 live pfin functions carry the price-pick rank clause (fn_account_unrealized_gl, fn_compute_nav(date,boolean), fn_subcat_market_value) — a 4th copy anywhere is the intended RED, forcing a decision rather than silent drift (ADR-057''s discriminator shape)'
);
select is(
  (with kernel_fns as (
     select p.oid,
            substring(p.prosrc from '(?s)case ep\.source.*?limit 1\)') as kernel_block
       from pg_proc p
      where p.pronamespace = 'pfin'::regnamespace
        and p.prosrc ilike '%when ''manual_valuation'' then 1%'
   )
   select count(distinct md5(regexp_replace(kernel_block, '^[ \t]+', '', 'ng')))
     from kernel_fns),
  1::bigint,
  '(FENCE1b) kernel-identity IDENTITY: all 3 live copies'' price-pick blocks are byte-identical after LEADING-WHITESPACE normalization (count(distinct md5)=1) — asserts the PREDICATE, never a pinned digest (Sec standing constraint: two correct pipelines measured different literal hash values over identical blocks)'
);
select is(
  (with kernel_fns as (
     select p.oid,
            substring(p.prosrc from '(?s)case ep\.source.*?limit 1\)') as kernel_block
       from pg_proc p
      where p.pronamespace = 'pfin'::regnamespace
        and p.prosrc ilike '%when ''manual_valuation'' then 1%'
   )
   select count(kernel_block) from kernel_fns),
  3::bigint,
  '(FENCE1c) ⭐ kernel-identity EXTRACTION (Sec AMBER condition, closed): all 3 population-matched functions ALSO extracted a non-null kernel block — closes the case-sensitivity hole where FENCE1a (case-INsensitive population filter) and FENCE1b (count(distinct) ignoring nulls) both stay green on a case-rewritten copy that silently fails the case-SENSITIVE extraction. RED means "extraction failed for at least one copy", a DIFFERENT diagnosis from FENCE1b RED ("copies diverged in content") — general by construction, not tied to any one rewrite vector'
);

-- =====================================================================
-- GOLDEN FIXTURE (SELF-328 MANDATORY PAIR) — "a fence that does not fail
--   closed is theater." SAVEPOINT-scoped so it is restored before any later
--   assertion runs (076''s corrupt-the-control shape) and contained within
--   this file''s own outer rolled-back transaction, per Sec''s "same rolled-
--   back txn" requirement. CREATE OR REPLACEs fn_account_unrealized_gl with
--   the `ep.price_id desc` tiebreak removed — DERIVED FROM THE LIVE prosrc
--   via `pg_get_functiondef` + `regexp_replace`, never hand-copied (Architect
--   memory: a hand-copied corrupted body is one future edit away from
--   silently drifting from what''s actually live — this reads the catalog at
--   the moment the test runs, so it cannot drift).
--   ⚠ A non-savepoint assertion (ACL1/ACL2 below) MUST run after the
--   `rollback to savepoint` — DESIGN.md''s harness note: a rolled-back
--   savepoint rewinds pgTAP''s plan COUNTER (transactional) while the emitted
--   TAP numbering (non-transactional) marches on, producing a false
--   "planned N but ran N-2" abort alarm on an all-green file if the LAST
--   assertion in the file sits inside the rolled-back savepoint. ACL1/ACL2
--   are plain reads with no savepoint, and they are LAST in this file.
-- =====================================================================
savepoint sp_kernel_corrupt;
do $$
declare
  v_def text;
  v_corrupted text;
begin
  v_def := pg_get_functiondef('pfin.fn_account_unrealized_gl(date)'::regprocedure);
  v_corrupted := regexp_replace(v_def, ',\s*ep\.price_id desc', '', 's');
  if v_corrupted = v_def then
    raise exception 'SELF-328 golden fixture: corruption pattern did not match the live body — the FIXTURE is broken, not the kernel; do not let this silently pass';
  end if;
  execute v_corrupted;
end $$;

-- (GOLDEN1) ⭐ IDENTITY leg goes RED: with the tiebreak removed, the
--   corrupted copy''s normalized block no longer matches the other two ->
--   distinct-hash count goes from 1 to 2. This is the EXACT predicate
--   FENCE1b asserts, now proven false — the fence''s own RED, not a
--   description of one.
select is(
  (with kernel_fns as (
     select p.oid,
            substring(p.prosrc from '(?s)case ep\.source.*?limit 1\)') as kernel_block
       from pg_proc p
      where p.pronamespace = 'pfin'::regnamespace
        and p.prosrc ilike '%when ''manual_valuation'' then 1%'
   )
   select count(distinct md5(regexp_replace(kernel_block, '^[ \t]+', '', 'ng')))
     from kernel_fns),
  2::bigint,
  '(GOLDEN1) ⭐ fence fails closed: with fn_account_unrealized_gl''s tiebreak REMOVED (live catalog, derived from its own prosrc — never hand-copied), the IDENTITY leg''s distinct-hash count goes from 1 to 2, exactly the shape that would flip FENCE1b RED. A fence that has only ever been observed green is unproven; this is the counter-example measured, not asserted'
);
-- (GOLDEN2) POPULATION leg stays green (=3) under this SAME mutation —
--   proves FENCE1a and FENCE1b fence DIFFERENT mutation classes and neither
--   subsumes the other: population catches a copy ADDED to or REMOVED from
--   the set; identity catches a copy that DIVERGED without leaving it (the
--   corrupted function still carries the `manual_valuation` CASE the
--   population filter matches on — only its tiebreak diverged).
select is(
  (select count(*) from pg_proc p
    where p.pronamespace = 'pfin'::regnamespace
      and p.prosrc ilike '%when ''manual_valuation'' then 1%'),
  3::bigint,
  '(GOLDEN2) population leg is UNCHANGED (still 3) under the same corruption that reddens FENCE1b: the corrupted function still carries the CASE clause the population filter matches on, only its tiebreak diverged — proving FENCE1a (discovery) and FENCE1b (identity) fence DIFFERENT mutation classes, neither subsumes the other'
);
rollback to savepoint sp_kernel_corrupt;

-- =====================================================================
-- EXECUTE-ACL (SELF-328 FOLD-IN, per Sec at PR #485) — pre-existing gap: no
--   battery watched these three functions'' EXECUTE grants. Reads what the
--   migrations ESTABLISH (Sec #480 ruling: authenticated-only EXECUTE),
--   asserted both directions per the hand-off ask — the grant PRESENT for the
--   role that must hold it, and its ABSENCE for every role that must not.
--   Live-measured before drafting (has_function_privilege), not assumed from
--   the migration text alone.
-- =====================================================================
select ok(
  has_function_privilege('authenticated', 'pfin.fn_account_unrealized_gl(date)'::regprocedure, 'EXECUTE')
  and has_function_privilege('authenticated', 'pfin.fn_compute_nav(date, boolean)'::regprocedure, 'EXECUTE')
  and has_function_privilege('authenticated', 'pfin.fn_subcat_market_value(date, boolean)'::regprocedure, 'EXECUTE'),
  '(ACL1) EXECUTE-ACL, the grant PRESENT: `authenticated` holds EXECUTE on all three kernel functions (fn_account_unrealized_gl, fn_compute_nav(date,boolean), fn_subcat_market_value) — the app''s own session can call them, per Sec''s #480 ruling'
);
select ok(
  not has_function_privilege('anon', 'pfin.fn_account_unrealized_gl(date)'::regprocedure, 'EXECUTE')
  and not has_function_privilege('anon', 'pfin.fn_compute_nav(date, boolean)'::regprocedure, 'EXECUTE')
  and not has_function_privilege('anon', 'pfin.fn_subcat_market_value(date, boolean)'::regprocedure, 'EXECUTE')
  and not has_function_privilege('service_role', 'pfin.fn_account_unrealized_gl(date)'::regprocedure, 'EXECUTE')
  and not has_function_privilege('service_role', 'pfin.fn_compute_nav(date, boolean)'::regprocedure, 'EXECUTE')
  and not has_function_privilege('service_role', 'pfin.fn_subcat_market_value(date, boolean)'::regprocedure, 'EXECUTE')
  and not has_function_privilege('public', 'pfin.fn_account_unrealized_gl(date)'::regprocedure, 'EXECUTE')
  and not has_function_privilege('public', 'pfin.fn_compute_nav(date, boolean)'::regprocedure, 'EXECUTE')
  and not has_function_privilege('public', 'pfin.fn_subcat_market_value(date, boolean)'::regprocedure, 'EXECUTE'),
  '(ACL2) EXECUTE-ACL, the ABSENCE for roles that must lack it: NEITHER anon NOR service_role NOR PUBLIC holds EXECUTE on any of the three kernel functions — authenticated-only per Sec''s #480 ruling, not merely "not anon"'
);

select * from finish();
rollback;
