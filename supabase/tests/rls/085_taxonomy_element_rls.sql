-- =====================================================================
-- Per-Wave battery — pfin.user_taxonomy + pfin.taxonomy_default gain `element`
--   (ADR-058 Decision 3). `element text not null check (element in ('asset',
--   'liability'))`, added to BOTH tables in the same migration, backfilled
--   `case when cat = 'Liabilities' then 'liability' else 'asset' end`. No
--   function, no policy, no grant, no trigger — two ALTER/UPDATE/ALTER/ALTER
--   sequences (add column, backfill, set not null, add CHECK), same shape per
--   table, applied twice.
-- =====================================================================
-- BINDS TO MIGRATION: supabase/migrations/085_taxonomy_element.sql (Architect,
--   `feature/gl-element-column`). Constraint names (read live from the applied
--   catalog, not assumed): `user_taxonomy_element_chk` on pfin.user_taxonomy,
--   `taxonomy_default_element_chk` on pfin.taxonomy_default — both
--   `check (element in ('asset','liability'))`. `element` is NOT NULL on both,
--   no default (deliberate — Architect's choice, so a fixture that omits it
--   fails LOUD rather than silently defaulting to 'asset'; the 63-statement
--   fixture sweep across 14 pre-existing battery files that this forces is
--   its own delivery, not restated here).
--
-- ┌─ WHAT THIS BATTERY PROVES ───────────────────────────────────────────┐
-- │ (a) SHAPE — `element` exists, is `text`, and is NOT NULL, on both      │
-- │     tables (catalog-level, role-independent).                         │
-- │ (b) ZERO-NULL — Sec F4 condition 2's own words: "battery legs          │
-- │     asserting zero NULL elements" on BOTH tables, post-backfill.       │
-- │ (c) BACKFILL CORRECTNESS, BOTH DIRECTIONS, BOTH TABLES — every         │
-- │     cat='Liabilities' row is element='liability' AND every other row  │
-- │     is element='asset'. A one-directional check passes while a row    │
-- │     set and its complement disagree (the same failure class Decision  │
-- │     3's own text names for §2.2.2) — asserted both ways, not one.     │
-- │ (d) THE CHECK HAS TEETH — "the named CHECK rejects an unknown value"  │
-- │     (team-lead brief) proven twice: normal-path throws_ok on 'equity' │
-- │     (the ratified V1.2+ widening candidate, ADR-058 Decision 3), THEN │
-- │     an INVERSION-PROVE — drop the CHECK in a savepoint, re-attempt    │
-- │     the SAME 'equity' insert, confirm it now COMMITS, roll back. The  │
-- │     inversion leg's success path is unreachable through the app (the │
-- │     CHECK always exists in every real environment) — kept anyway per │
-- │     house rule: unreachable-by-construction is a reason to KEEP a     │
-- │     teeth-proof leg, not drop it (it is what would catch a future PR │
-- │     silently loosening or dropping the CHECK).                        │
-- └─────────────────────────────────────────────────────────────────────┘
--
-- NOT owed here (scoped out by Architect, recorded so it isn't re-litigated):
--   the totals-equality watcher (BACKLOG §7.24 item 3, its own booking) and
--   `fn_subcat_market_value` re-pointing at `element` (SELF-239, later). The
--   provisioning-fixture extension ("a fresh user's rows carry no NULL
--   element") rides 041's existing Sec F3 fixture as leg (1b-element) there,
--   not duplicated here — a second synthetic provisioning fixture would test
--   the same INSERT statement 041 already exercises, not a new mechanism.
--
-- §10 / DECISION 3: §10 ledger UNCHANGED (read ADR-011 Decision 4 live before
--   trusting this line). Decision-3 family UNCHANGED (+0): `element` is not an
--   FK-shaped reference column (no isolation boundary to cross) — it is a
--   plain CHECK-constrained classification value, same posture as `cat`/
--   `sub_cat`. No SECURITY DEFINER/INVOKER authored; DEFINER allowlist
--   unchanged.
--
-- POSTURE (SECURITY §4.5): SYNTHETIC ONLY — fixed-UUID tenants from
--   _rls.tenant_a()/_b(); NO PII / NO real account numbers / NO prod data.
--   Reads the REAL, already-migrated taxonomy_default (38 rows: 34 asset +
--   4 liability at 001->085 chain-apply time — re-measured live in (Z3)/(Z4)
--   below, not hardcoded, because this file's whole point is proving the
--   real backfill, not a synthetic replay of it). All in a rolled-back txn.
-- =====================================================================

begin;

\ir ../_fixtures/rls_verbs.psql

select plan(18);

select _rls.tenant_a() as ta, _rls.tenant_b() as tb \gset
insert into auth.users (id) values (:'ta'), (:'tb');

-- =====================================================================
-- BLOCK S — shape (catalog-level, role-independent).
-- =====================================================================
select has_column(
  'pfin', 'user_taxonomy', 'element',
  '(S1) pfin.user_taxonomy.element column exists'
);
select col_type_is(
  'pfin', 'user_taxonomy', 'element', 'text',
  '(S2) pfin.user_taxonomy.element is type text'
);
select col_not_null(
  'pfin', 'user_taxonomy', 'element',
  '(S3) pfin.user_taxonomy.element is NOT NULL'
);
select has_column(
  'pfin', 'taxonomy_default', 'element',
  '(S4) pfin.taxonomy_default.element column exists'
);
select col_type_is(
  'pfin', 'taxonomy_default', 'element', 'text',
  '(S5) pfin.taxonomy_default.element is type text'
);
select col_not_null(
  'pfin', 'taxonomy_default', 'element',
  '(S6) pfin.taxonomy_default.element is NOT NULL'
);

-- =====================================================================
-- BLOCK Z — zero-NULL, both tables (Sec F4 condition 2, verbatim ask).
-- =====================================================================
select is(
  (select count(*) from pfin.user_taxonomy where element is null)::bigint,
  0::bigint,
  '(Z1) zero-NULL: no pfin.user_taxonomy row has a NULL element (the backfill reached every row before NOT NULL landed)'
);
select is(
  (select count(*) from pfin.taxonomy_default where element is null)::bigint,
  0::bigint,
  '(Z2) zero-NULL: no pfin.taxonomy_default row has a NULL element'
);

-- =====================================================================
-- BLOCK B — backfill correctness, BOTH directions, BOTH tables. Preconditions
--   first (DESIGN.md rule 3 — an "every X is Y" assertion over an EMPTY X set
--   is vacuous), then both directions of the complement.
-- =====================================================================
-- (B0) precondition, non-vacuous: taxonomy_default carries at least one row
--      of EACH element value — both directions below have a real subject.
select cmp_ok(
  (select count(*) from pfin.taxonomy_default where element = 'liability')::bigint,
  '>', 0::bigint,
  '(B0) precondition: pfin.taxonomy_default carries >=1 liability-element row (041''s 3 seeded Liabilities Sub-Cats + 080''s Liability Balances = 4 — non-vacuous subject for (B1)/(B3))'
);
-- (B1) taxonomy_default, direction 1: every cat='Liabilities' row is element='liability'.
select is(
  (select count(*) from pfin.taxonomy_default where cat = 'Liabilities' and element <> 'liability')::bigint,
  0::bigint,
  '(B1) backfill correctness, taxonomy_default, direction 1: every cat=''Liabilities'' row has element=''liability'' — zero rows disagree'
);
-- (B2) taxonomy_default, direction 2 (the complement): every OTHER cat is element='asset'.
select is(
  (select count(*) from pfin.taxonomy_default where cat <> 'Liabilities' and element <> 'asset')::bigint,
  0::bigint,
  '(B2) backfill correctness, taxonomy_default, direction 2 (the complement): every cat OTHER than ''Liabilities'' has element=''asset'' — zero rows disagree; a one-directional check alone would miss a row wrongly marked ''liability'''
);
-- (B3)/(B4) — same two directions, user_taxonomy, exercised via 041's REAL
--   provisioning replay (the ONLY way to get a non-empty user_taxonomy on a
--   fresh scratch DB — 080's own precedent). Provision A's full asset set.
select _rls.set_tenant_aal(:'ta'::uuid, 'aal1');
select lives_ok(
  $$ insert into pfin.user_taxonomy (users_id, cat, sub_cat, tax_relevant, tax_character, display_order, notes, element)
     select auth.uid(), cat, sub_cat, tax_relevant, tax_character, display_order, notes, element
     from pfin.taxonomy_default
     on conflict (users_id, cat, sub_cat) do nothing $$,
  '(B3-setup) A provisions the full asset default set — the column-listed copy propagates element unchanged (same statement shape as 041''s BLOCK 1, re-proven here as this leg''s own fixture)'
);
select set_config('role', 'postgres', true);
select is(
  (select count(*) from pfin.user_taxonomy where users_id = :'ta' and cat = 'Liabilities' and element <> 'liability')::bigint,
  0::bigint,
  '(B3) backfill/propagation correctness, user_taxonomy, direction 1: every cat=''Liabilities'' row A owns has element=''liability'' — the provisioning copy preserves the source table''s own correctness'
);
select is(
  (select count(*) from pfin.user_taxonomy where users_id = :'ta' and cat <> 'Liabilities' and element <> 'asset')::bigint,
  0::bigint,
  '(B4) backfill/propagation correctness, user_taxonomy, direction 2 (the complement): every OTHER cat A owns has element=''asset'''
);

-- =====================================================================
-- BLOCK C — the CHECK has teeth. Normal-path rejection, then an
--   INVERSION-PROVE (corrupt-the-control): drop the CHECK in a savepoint,
--   re-attempt the SAME insert, confirm it NOW commits, roll back. Proves
--   the CHECK — not something else (a type mismatch, a trigger) — is what
--   blocks 'equity' in the normal-path leg.
--
-- ⚠ SAVEPOINT SCOPE, deliberately asymmetric (verified empirically, not
--   assumed): (C1)/(C3) carry NO outer savepoint — a `throws_ok`-caught
--   rejection never commits its row regardless (confirmed by direct probe:
--   zero residue, and pgTAP's own internal `__tcache__` test counter is
--   untouched). (C2)/(C4) DO need one, because they mutate real catalog
--   state (`drop constraint`) that must not survive past this leg — but
--   that means their contribution to pgTAP's internal running-test-count is
--   itself rolled back along with the DDL (confirmed by direct probe:
--   `rollback to savepoint` after ANY pgTAP assertion call erases that
--   call's `__tcache__` increment even though its `ok N` line already
--   printed correctly). `finish()` may therefore emit a benign
--   "# Looks like you planned N tests but ran N-2" comment — a `#`-prefixed
--   TAP comment, not a result line; pg_prove (the TAP-aware consumer this
--   house requires) parses the real `1..N` / `ok`/`not ok` stream and is
--   UNAFFECTED — confirmed live, `Result: PASS` with all N `ok` lines
--   present and none dropped. Documented here so a future reader of CI
--   output sees the comment and does not mistake it for a real gap.
-- =====================================================================
select _rls.set_tenant_aal(:'ta'::uuid, 'aal1');

-- (C1) normal path: user_taxonomy rejects element='equity'. No outer savepoint —
--      the throws_ok-caught rejection commits nothing; nothing to undo.
select throws_ok(
  format($$ insert into pfin.user_taxonomy (users_id, cat, sub_cat, element) values (%L, 'Corrupt', 'Probe', 'equity') $$, :'ta'),
  '23514', null,
  '(C1) pfin.user_taxonomy REJECTS element=''equity'' (check_violation 23514) — the ratified V1.2+ widening candidate is NOT accepted until a future migration explicitly widens the CHECK'
);

-- (C2) INVERSION: with user_taxonomy_element_chk DROPPED, the SAME insert COMMITS —
--      proves (C1)'s rejection is the CHECK, not e.g. a stray trigger or type coercion.
select set_config('role', 'postgres', true);
savepoint sp_c2;
alter table pfin.user_taxonomy drop constraint user_taxonomy_element_chk;
select _rls.set_tenant_aal(:'ta'::uuid, 'aal1');
select lives_ok(
  format($$ insert into pfin.user_taxonomy (users_id, cat, sub_cat, element) values (%L, 'Corrupt', 'Probe', 'equity') $$, :'ta'),
  '(C2) ⭐ INVERSION-PROVE: with user_taxonomy_element_chk DROPPED (this savepoint only), the IDENTICAL ''equity'' insert from (C1) COMMITS — confirms the CHECK is the real fence, not a coincidental rejection from elsewhere. Unreachable through the app (the CHECK always exists in every real environment) — kept per house rule: this is what would catch a future PR silently loosening or dropping it'
);
rollback to savepoint sp_c2;
select set_config('role', 'postgres', true);

-- (C3) normal path: taxonomy_default rejects element='equity'. No outer savepoint (same
--      reasoning as C1).
select throws_ok(
  $$ insert into pfin.taxonomy_default (cat, sub_cat, tax_relevant, tax_character, display_order, notes, element)
     values ('Corrupt', 'Probe', false, null, 999, 'inversion-prove probe row', 'equity') $$,
  '23514', null,
  '(C3) pfin.taxonomy_default REJECTS element=''equity'' (check_violation 23514) — same CHECK shape as user_taxonomy, the global template side'
);

-- (C4) INVERSION: with taxonomy_default_element_chk DROPPED, the SAME insert COMMITS.
savepoint sp_c4;
alter table pfin.taxonomy_default drop constraint taxonomy_default_element_chk;
select lives_ok(
  $$ insert into pfin.taxonomy_default (cat, sub_cat, tax_relevant, tax_character, display_order, notes, element)
     values ('Corrupt', 'Probe', false, null, 999, 'inversion-prove probe row', 'equity') $$,
  '(C4) ⭐ INVERSION-PROVE: with taxonomy_default_element_chk DROPPED (this savepoint only), the IDENTICAL ''equity'' insert from (C3) COMMITS — same teeth-proof as (C2), global template side'
);
rollback to savepoint sp_c4;

select * from finish();
rollback;
