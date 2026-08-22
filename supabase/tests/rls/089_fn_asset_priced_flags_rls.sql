-- =====================================================================
-- Per-Wave battery — pfin.fn_asset_priced_flags (SELF-325 — Sec C3/F1
--   remediation: the single definition of "does this asset have a usable
--   price", called by both 088 and the account-detail read path; V1-SHIP-BLOCK)
-- =====================================================================
-- BINDS TO MIGRATION: supabase/migrations/089_fn_asset_priced_flags.sql
--   pfin.fn_asset_priced_flags(p_asset_ids bigint[], p_as_of date)
--     RETURNS TABLE (asset_id bigint, priced boolean)
--     SECURITY INVOKER, STABLE, set search_path = ''.
--   One row per DISTINCT non-null input id; an id with no visible usable price
--     returns FALSE — never NULL, never absent.
-- Prereqs exercised: 019 (pfin.eod_price, its unique (asset_id, price_date,
--   source), and eod_price_select's global-OR-owned read policy this composes
--   under), 016 (pfin.asset hybrid registry — global vs per-user), 001 (pfin
--   schema). Sibling: 088 (replaces its inline `priced` block with a call to
--   this function, same PR — this file does NOT re-verify that composition;
--   088's own battery (088_manual_purchase_path_rls.sql) does, and its plan
--   count is UNCHANGED at 67 through the body edit because Architect verified
--   the replacement is semantically identical — a claim this file's own legs
--   independently support by holding the SAME predicate to the SAME standard).
-- Reuses the SELF-187.. idiom: \ir verbs, ALL-LOWERCASE \gset literals, role
--   restored to postgres between blocks (PR #121 root-cause).
--
-- ┌─ WHAT THIS BATTERY PROVES ─────────────────────────────────────────────────┐
-- │ A — POSTURE: exactly one overload; SECURITY INVOKER (prosecdef=false);      │
-- │   STABLE (provolatile=s — it reads a table, not IMMUTABLE); the injection   │
-- │   fence (search_path=""); EXECUTE granted to authenticated only, anon/      │
-- │   public/service_role all denied (service_role is DELIBERATELY ungranted — │
-- │   no worker path uses this helper).                                        │
-- │ B — THE PREDICATE, the four properties Sec's C3/F1 fix depends on and      │
-- │   that were tested NOWHERE as of this migration: a same-date tie resolves  │
-- │   to TRUE regardless of INSERTION ORDER (inversion-tested — see the leg's  │
-- │   own comment; this is the C3 catch, which is why both orders are          │
-- │   separate legs and not one); a zero-valued row alone is FALSE; an older   │
-- │   positive row does NOT rescue a newer zero row (the leg a naive "any      │
-- │   positive row exists" implementation uniquely fails); a no-rows asset     │
-- │   returns FALSE as a PRESENT, NOT-NULL row.                                │
-- │ C — THE F1 SCALE PROOF, as a COMMITTED pg_prove leg per Sec's ruling (F1   │
-- │   is closed on the merits but gated on this NOT being a one-off manual     │
-- │   session): >1000 eod_price rows across 2 held global assets — the         │
-- │   function still returns EXACTLY 2 rows (bounded by INPUT size, not price  │
-- │   history — that boundedness is BY CONSTRUCTION, which is what makes       │
-- │   PostgREST's row cap unreachable), and the HIGHER asset_id (the one the   │
-- │   original ascending-order truncation dropped) reads priced=TRUE.          │
-- │   Inversion-tested — see the leg's own comment.                            │
-- │ D — TWO-TENANT ISOLATION + THE SHAPE PIN + INDISTINGUISHABILITY: a caller  │
-- │   supplying another tenant's PRIVATE asset_id learns NOTHING — the SAME    │
-- │   answer (a PRESENT row, priced=FALSE) as their own genuinely-unpriced     │
-- │   asset. The shape is PINNED explicitly (a row IS returned, not absent —   │
-- │   089's own documented contract) because the app's `?? false` fallback     │
-- │   would mask either shape equally, which is exactly why the contract needs │
-- │   its own watcher rather than resting on a caller's defensive default.     │
-- │   Non-vacuous: the probed asset is seeded with a REAL price, so the owner  │
-- │   reading TRUE on their own asset proves the FALSE the intruder reads is   │
-- │   about invisibility, not a genuinely-unpriced asset.                      │
-- └───────────────────────────────────────────────────────────────────────────┘
--
-- §10 / DECISION 3: UNCHANGED. p_asset_ids is a TRANSIENT ARGUMENT, not a
--   stored column — 089's own header states the isolation this would otherwise
--   need is supplied by RLS (INVOKER + 019's eod_price_select), and that
--   substitution holds only while this function stays INVOKER and read-only.
--   §10 ledger UNCHANGED (no new SD/RT instance; NO service_role anywhere in
--   this function). SECURITY DEFINER allowlist UNCHANGED (INVOKER — measured
--   prosecdef=false, (a-2)).
--
-- POSTURE (SECURITY §4.5): SYNTHETIC ONLY — fixed-UUID tenants from
--   _rls.tenant_a()/_b(); NO PII / NO real account numbers / NO prod data. The
--   scale fixture's 1198 rows are synthetic daily prices on two throwaway
--   global test assets, not real market data.
--
-- ⟦WIRE-VALIDATE⟧ authored against the committed 089 blob, read live from the
--   catalog and PROBED in a rolled-back scratch-DB clone of the local stack
--   with 088+089 applied — every property in this file was RUN, not derived
--   from the header prose alone (DESIGN.md's "build X and watch it go red").
--   Every inversion claim below was independently measured in a rolled-back
--   sabotage probe, not assumed. Verify with pg_prove — bare psql exits 0 on a
--   plan-count failure. plan(20).
-- =====================================================================

begin;

\ir ../_fixtures/rls_verbs.psql

select plan(20);

select _rls.tenant_a() as ta, _rls.tenant_b() as tb \gset

insert into auth.users (id) values (:'ta'), (:'tb');

-- =====================================================================
-- A — POSTURE.
-- =====================================================================

-- (a-1) catalog: exactly ONE fn_asset_priced_flags overload.
select is(
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'pfin' and p.proname = 'fn_asset_priced_flags')::bigint,
  1::bigint,
  '(a-1) exactly ONE fn_asset_priced_flags overload exists in pg_proc'
);

-- (a-2) INVOKER (prosecdef=false) and STABLE (provolatile='s') — both pinned
--   on the signature per 089's own header, not left to language defaults.
select ok(
  (select p.prosecdef = false and p.provolatile = 's'
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'pfin' and p.proname = 'fn_asset_priced_flags'),
  '(a-2) fn_asset_priced_flags is SECURITY INVOKER (prosecdef=false) and STABLE (provolatile=s)'
);

-- (a-3) the injection fence: search_path pinned to empty on the signature.
select ok(
  (select 'search_path=""' = any(p.proconfig)
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'pfin' and p.proname = 'fn_asset_priced_flags'),
  '(a-3) search_path is pinned empty on the function signature (injection fence)'
);

-- (a-4) EXECUTE granted to authenticated only; anon/public/service_role denied
--   — service_role is DELIBERATELY ungranted (no worker path uses this helper).
select ok(
  has_function_privilege('authenticated',
    'pfin.fn_asset_priced_flags(bigint[],date)'::regprocedure, 'EXECUTE')
  and not has_function_privilege('anon',
    'pfin.fn_asset_priced_flags(bigint[],date)'::regprocedure, 'EXECUTE')
  and not has_function_privilege('public',
    'pfin.fn_asset_priced_flags(bigint[],date)'::regprocedure, 'EXECUTE')
  and not has_function_privilege('service_role',
    'pfin.fn_asset_priced_flags(bigint[],date)'::regprocedure, 'EXECUTE'),
  '(a-4) EXECUTE granted to authenticated ONLY — anon, public and service_role all denied'
);

-- =====================================================================
-- B — THE PREDICATE. Two same-date ties, DELIBERATELY seeded in OPPOSITE
--   insertion orders — the variable under test IS insertion order, since C3
--   was about order-dependence, not about the predicate. INVERSION-TESTED (not
--   part of this file — a rolled-back sabotage probe): striking the aggregate
--   back to `order by price_id limit 1` (088's pre-089 "first row, no
--   tiebreak" shape) left (b-1)'s order GREEN (its first inserted row happened
--   to be the positive one) but flipped (b-2)'s order RED (false where true is
--   required) — MEASURED. That asymmetry is exactly why both orders are
--   separate legs: a battery testing only one would have missed the defect
--   Sec's C3 finding was about, the same way the pre-fix code did.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);

insert into pfin.asset (asset_type, pricing_source, name, currency)
values ('equity', 'manual_valuation', 'B Tie A (pos-then-zero)', 'USD')
returning asset_id as tie_a \gset
insert into pfin.eod_price (asset_id, price_date, source, price) values (:tie_a, '2026-04-15', 'manual_valuation', 10.00);
select set_config('role', 'postgres', true);
insert into pfin.eod_price (asset_id, price_date, source, price) values (:tie_a, '2026-04-15', 'fx_feed', 0);
select _rls.set_tenant(:'ta'::uuid);

insert into pfin.asset (asset_type, pricing_source, name, currency)
values ('equity', 'manual_valuation', 'B Tie B (zero-then-pos)', 'USD')
returning asset_id as tie_b \gset
select set_config('role', 'postgres', true);
insert into pfin.eod_price (asset_id, price_date, source, price) values (:tie_b, '2026-04-15', 'fx_feed', 0);
select _rls.set_tenant(:'ta'::uuid);
insert into pfin.eod_price (asset_id, price_date, source, price) values (:tie_b, '2026-04-15', 'manual_valuation', 10.00);

insert into pfin.asset (asset_type, pricing_source, name, currency)
values ('equity', 'manual_valuation', 'B Zero Alone', 'USD')
returning asset_id as zero_alone \gset
insert into pfin.eod_price (asset_id, price_date, source, price) values (:zero_alone, '2026-04-15', 'manual_valuation', 0);

insert into pfin.asset (asset_type, pricing_source, name, currency)
values ('equity', 'manual_valuation', 'B Older Positive Newer Zero', 'USD')
returning asset_id as stale_positive \gset
insert into pfin.eod_price (asset_id, price_date, source, price) values (:stale_positive, '2026-03-15', 'manual_valuation', 10.00);
select set_config('role', 'postgres', true);
insert into pfin.eod_price (asset_id, price_date, source, price) values (:stale_positive, '2026-04-15', 'fx_feed', 0);
select _rls.set_tenant(:'ta'::uuid);

insert into pfin.asset (asset_type, pricing_source, name, currency)
values ('equity', 'manual_valuation', 'B No Rows', 'USD')
returning asset_id as no_rows \gset

select set_config('role', 'postgres', true);

-- (b-1) tie, order A (positive inserted first): priced=TRUE.
select is(
  (select priced from pfin.fn_asset_priced_flags(array[:tie_a]::bigint[], '2026-04-15'::date)),
  true,
  '(b-1) same-date tie, positive-then-zero insertion order: priced=TRUE'
);

-- (b-2) tie, order B (zero inserted first): priced=TRUE — THE C3 catch.
select is(
  (select priced from pfin.fn_asset_priced_flags(array[:tie_b]::bigint[], '2026-04-15'::date)),
  true,
  '(b-2) same-date tie, ZERO-then-positive insertion order: priced=TRUE — order-independence, the C3 catch (inversion-tested, see header)'
);

-- (b-3) zero-valued row alone at the max date: priced=FALSE.
select is(
  (select priced from pfin.fn_asset_priced_flags(array[:zero_alone]::bigint[], '2026-04-15'::date)),
  false,
  '(b-3) a zero-valued row alone at the max date: priced=FALSE'
);

-- (b-4) MAX-DATE PICKING: an older positive row does not rescue a newer zero
--   row. The leg a naive "any positive row exists" implementation uniquely
--   fails — it passes every other leg in this section.
select is(
  (select priced from pfin.fn_asset_priced_flags(array[:stale_positive]::bigint[], '2026-04-15'::date)),
  false,
  '(b-4) MAX-DATE PICKING: an older positive row does not override a newer zero row — priced=FALSE, not rescued by history'
);

-- (b-5) no rows at all: priced=FALSE, and (b-6) NEVER NULL, and PRESENT
--   (count=1) — 089's own documented contract: a row for every id passed.
select is(
  (select priced from pfin.fn_asset_priced_flags(array[:no_rows]::bigint[], '2026-04-15'::date)),
  false,
  '(b-5) an asset with NO eod_price rows at all: priced=FALSE'
);
select ok(
  (select priced is not null from pfin.fn_asset_priced_flags(array[:no_rows]::bigint[], '2026-04-15'::date)),
  '(b-6) FAIL-CLOSED ON ABSENCE: priced is NEVER NULL for a no-rows asset — a NULL is exactly what a consumer could misread as truthy/unhandled'
);
select is(
  (select count(*) from pfin.fn_asset_priced_flags(array[:no_rows]::bigint[], '2026-04-15'::date))::bigint,
  1::bigint,
  '(b-7) NON-VACUOUS: the no-rows asset still gets exactly ONE returned row (present, not absent) — proves (b-5)/(b-6) are a real FALSE, not a missing row read as false'
);

-- =====================================================================
-- C — THE F1 SCALE PROOF, committed (Sec's gating requirement: F1 is closed
--   on the merits but gated on this NOT being Backend's one-off manual psql
--   session). Fixture per Backend's measured recipe. INVERSION-TESTED (not
--   part of this file — a rolled-back sabotage probe): replacing the
--   per-asset aggregation with a bare LEFT JOIN (cardinality per PRICE ROW,
--   not per asset — a plausible "simplification" regression) turned the
--   2-row result into 1198 rows — MEASURED. (c-3)'s row-count assertion is
--   what catches that; (c-4)'s boolean-only assertion would NOT have, which is
--   why row count is asserted as its own leg and not folded into (c-4).
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);

insert into pfin.asset (asset_type, pricing_source, name, currency)
values ('equity', 'manual_valuation', 'C Scale A (lower asset_id)', 'USD')
returning asset_id as scale_a \gset
insert into pfin.asset (asset_type, pricing_source, name, currency)
values ('equity', 'manual_valuation', 'C Scale B (higher asset_id)', 'USD')
returning asset_id as scale_b \gset

-- 599 daily rows per asset, 2024-01-01..2025-08-21 inclusive = 1198 total.
-- ⚠ 1198 is chosen to EXCEED PostgREST's max_rows=1000 (supabase/config.toml:23)
-- — the ORIGINAL F1 defect. Shrinking this count for test speed RETIRES THE
-- WATCHER: below 1000 total rows the old, truncating read path would have
-- passed too, and this leg would no longer distinguish fixed from broken.
insert into pfin.eod_price (asset_id, price_date, source, price)
select :scale_a, d::date, 'manual_valuation', 100.00
from generate_series('2024-01-01'::date, '2025-08-21'::date, '1 day'::interval) d;
insert into pfin.eod_price (asset_id, price_date, source, price)
select :scale_b, d::date, 'manual_valuation', 200.00
from generate_series('2024-01-01'::date, '2025-08-21'::date, '1 day'::interval) d;

select set_config('role', 'postgres', true);

-- (c-1) the seed itself landed IN FULL — LOAD-BEARING. A total seeding failure
--   would red (c-3)/(c-4) anyway, but a PARTIAL seeding failure (e.g. one
--   asset's rows silently short) would NOT — it would leave (c-3)/(c-4) green
--   while the >1000-row axis is silently no longer exercised. This is the leg
--   that catches that.
select is(
  (select count(*) from pfin.eod_price where asset_id in (:scale_a, :scale_b))::bigint,
  1198::bigint,
  '(c-1) LOAD-BEARING: the scale fixture seeded exactly 1198 eod_price rows across the two assets — exceeds max_rows=1000 (config.toml:23); a partial seed would leave (c-3)/(c-4) green while silently not exercising the >1000-row axis'
);

-- (c-2) non-vacuous: both assets individually have real rows (guards a
--   lopsided seed where all 1198 rows landed on one asset_id).
select is(
  (select count(*) from pfin.eod_price where asset_id = :scale_a)::bigint,
  599::bigint,
  '(c-2) NON-VACUOUS: scale_a alone has 599 rows (not a lopsided seed)'
);

-- (c-3) THE CARDINALITY PROOF: exactly 2 rows back, not 1198 — bounded by
--   INPUT size, not price history. This is the assertion the inversion probe
--   (header) actually catches; (c-4) alone would not.
select is(
  (select count(*) from pfin.fn_asset_priced_flags(array[:scale_a, :scale_b]::bigint[], '2025-08-21'::date))::bigint,
  2::bigint,
  '(c-3) CARDINALITY: 1198 input price rows across 2 assets still returns EXACTLY 2 rows — bounded by input size, which is what makes PostgREST''s row cap unreachable (inversion-tested, see header: a per-price-row regression returns 1198 here)'
);

-- (c-4) the HIGHER asset_id — the one the original ascending-order
--   truncation dropped — reads priced=TRUE. Sec's F1 catch criterion,
--   verbatim.
select is(
  (select priced from pfin.fn_asset_priced_flags(array[:scale_a, :scale_b]::bigint[], '2025-08-21'::date)
     where asset_id = :scale_b),
  true,
  '(c-4) Sec F1 catch criterion: the HIGHER asset_id (the one ascending-order truncation used to drop) reads priced=TRUE at scale'
);

-- =====================================================================
-- D — TWO-TENANT ISOLATION + THE SHAPE PIN + INDISTINGUISHABILITY. 089 must
--   not become an existence oracle for another tenant's private asset_ids.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);

-- A's PRIVATE asset, given a REAL, USABLE price — load-bearing: if visibility
-- ever leaked, B would see priced=TRUE and learn A holds a priced asset.
insert into pfin.asset (asset_type, pricing_source, name, currency)
values ('equity', 'manual_valuation', 'D A Private Priced', 'USD')
returning asset_id as a_private \gset
insert into pfin.eod_price (asset_id, price_date, source, price) values (:a_private, '2026-04-16', 'manual_valuation', 42.00);

-- (d-1) NON-VACUOUS CONTROL: A, calling on their OWN asset, reads priced=TRUE
--   — proves the asset genuinely IS priced, so (d-2) below is about
--   invisibility, not about the asset being unpriced.
select is(
  (select priced from pfin.fn_asset_priced_flags(array[:a_private]::bigint[], '2026-04-16'::date)),
  true,
  '(d-1) NON-VACUOUS CONTROL: A reads priced=TRUE on their own private, actually-priced asset'
);
select set_config('role', 'postgres', true);

-- B's OWN visible-but-genuinely-unpriced asset.
select _rls.set_tenant(:'tb'::uuid);
insert into pfin.asset (asset_type, pricing_source, name, currency)
values ('equity', 'manual_valuation', 'D B Visible Unpriced', 'USD')
returning asset_id as b_unpriced \gset

-- (d-2) BEHAVIOURAL TWO-TENANT ISOLATION: B calls with A's PRIVATE (and
--   actually-priced) asset_id in the array. THE SHAPE PIN, load-bearing: a row
--   IS returned (not absent — 089's own documented contract), with
--   priced=FALSE. The app's `pricedByAssetId.get(id) ?? false` fallback would
--   mask either shape (row-absent or row-present-false) equally, which is
--   exactly why the CONTRACT needs its own watcher rather than resting on a
--   caller's defensive default.
select is(
  (select count(*) from pfin.fn_asset_priced_flags(array[:a_private]::bigint[], '2026-04-16'::date))::bigint,
  1::bigint,
  '(d-2) SHAPE PIN: B probing A''s private asset_id gets back exactly ONE row (present, not absent) — 089''s documented per-input-id contract'
);
select is(
  (select priced from pfin.fn_asset_priced_flags(array[:a_private]::bigint[], '2026-04-16'::date)),
  false,
  '(d-3) ISOLATION: B probing A''s PRIVATE, ACTUALLY-PRICED asset_id reads priced=FALSE — B learns nothing about A''s asset'
);

-- (d-4) INDISTINGUISHABILITY: B's own visible-but-unpriced asset ALSO reads
--   priced=FALSE — the SAME answer as (d-3). A future "helpful" fix that
--   distinguished the two cases would go red here.
select is(
  (select priced from pfin.fn_asset_priced_flags(array[:b_unpriced]::bigint[], '2026-04-16'::date)),
  false,
  '(d-4) INDISTINGUISHABLE from (d-3): B''s own genuinely-unpriced asset ALSO reads priced=FALSE — invisible and unpriced cannot be told apart from the output, by design (089''s header)'
);

-- (d-5) cross-tenant read fails closed on the underlying table too (the
--   isolation 089 rests on, not 089 itself): B sees 0 of A's eod_price rows.
select is(
  (select count(*) from pfin.eod_price where asset_id = :a_private)::bigint,
  0::bigint,
  '(d-5) cross-tenant read fails closed: B sees 0 of A''s eod_price rows directly (019 eod_price_select asset-JOIN scope) — the fence 089''s isolation rests on'
);
select set_config('role', 'postgres', true);

select * from finish();
rollback;
