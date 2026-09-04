-- =====================================================================
-- Per-Wave battery — pfin.posting_prototype + pfin.posting_prototype_default gain
--   `is_tax_payment` (SELF-245 / ADR-062). `is_tax_payment boolean not null`, NO DEFAULT
--   (Decision 2 — fail-closed: every INSERT must state the value), NO CHECK (a boolean
--   NOT NULL domain is already exactly {true,false} — a named CHECK over it would be a leg
--   that cannot fail, ADR-062's own words). Same column, same shape, on BOTH tables (Decision
--   1, the `085`-precedent pair discipline). The Equity seed pair (Contribution/Distribution)
--   lands in `pfin.posting_prototype_default` in the SAME migration (Decision 4), closing the
--   gap where §2.3.3's ratified "Other Cash Flows" (Transfer ∪ Equity) section had zero seeded
--   Equity rows. Reach to already-provisioned users is EXPLICIT BACKFILL (Decision 5) — the
--   app's existence-guarded `provisionCashflowPrototypes` never re-visits a user who already
--   holds ≥1 `posting_prototype` row.
-- =====================================================================
-- BINDS TO MIGRATION: supabase/migrations/091_posting_prototype_is_tax_payment.sql
--   (Architect, `feature/self-245-is-tax-payment`, committed 09e4743, blob md5
--   aad8e41e0b2f1bffa569f56a903b383c — re-hash before trusting this line). Authored
--   against the committed blob: DDL sequence is (1) add column NULLABLE on both tables,
--   (2) total backfill `is_tax_payment = false where is_tax_payment is null` on both tables
--   (covers every pre-091 row, not only the 2 new Equity ones), (3) `set not null` on both
--   (fails loudly if (2) missed a row — no separate count check in the migration itself), (4)
--   no CHECK, (5) the Equity seed pair INSERT into posting_prototype_default (`on conflict
--   (cat, sub_cat) do nothing`), (6) the backfill INSERT into posting_prototype reproduced
--   VERBATIM below (BLOCK BF / IDEM) — column list, select list, and the `cross join (select
--   distinct pp.users_id from pfin.posting_prototype pp) provisioned` population predicate all
--   match the committed statement byte-for-byte, checked against it directly, not reconstructed
--   from memory of the ADR alone.
--
-- ┌─ WHAT THIS BATTERY PROVES ───────────────────────────────────────────────────────────┐
-- │ (S) SHAPE — is_tax_payment exists, boolean, NOT NULL, on BOTH tables; NO DEFAULT        │
-- │     (pg_attrdef absence, not merely "no DEFAULT clause read from DDL text"); NO CHECK   │
-- │     referencing the column on either table (Decision 2 — do not invent a leg asserting  │
-- │     a CHECK that does not exist BY DESIGN; this leg asserts the DESIGNED absence).       │
-- │ (E) EQUITY SEED PAIR — both rows land in posting_prototype_default with the exact        │
-- │     Decision 4 contract: Contribution tax_relevant=true + the notes rider verbatim,      │
-- │     Distribution tax_relevant=false; BOTH is_tax_payment=false (an owner capital         │
-- │     movement is not a tax payment — Decision 4's own words).                             │
-- │ (V) VOCABULARY — Equity rows never carry cat='Expense' (structurally absent from the     │
-- │     §2.3.4 discretionary-expense filter, which reads cat='Expense'); the §2.3.3 "Other    │
-- │     Cash Flows" composition (Transfer ∪ Equity) is NON-VACUOUS on BOTH halves — the       │
-- │     global default set AND a backfilled per-user table each carry >=1 Transfer row AND    │
-- │     >=1 Equity row (DESIGN.md rule 3: an "every X is Y" claim over an empty X is vacuous;  │
-- │     this is the non-vacuity precondition for that composition claim).                     │
-- │ (BF) BACKFILL REACH — a tenant already-provisioned BEFORE 091 (>=1 pre-existing            │
-- │     posting_prototype row) receives BOTH Equity rows AFTER the backfill re-run, via        │
-- │     091's OWN backfill statement RE-DERIVED here (077/080 precedent — the ONLY way to      │
-- │     exercise a migration-time backfill against a non-empty table on a scratch DB where     │
-- │     091 already ran once against zero real historical users). A tenant with ZERO           │
-- │     pre-existing rows is correctly UNREACHED by the backfill (Decision 5 scopes reach to   │
-- │     ALREADY-provisioned users only — a zero-row tenant gets the full set, incl. Equity,    │
-- │     from first-access provisioning once that lands, not from this backfill) — asserted     │
-- │     as a leg, not assumed.                                                                 │
-- │ (FS) FRESH-SIGNUP COPY SEMANTICS — ⚠ SCOPE, stated exactly per the team-lead brief: this    │
-- │     leg re-derives the DB-level copy statement provisioning needs to run (full               │
-- │     posting_prototype_default column set INCLUDING is_tax_payment) and asserts the          │
-- │     resulting row count on the target equals the full default-set count, by ROW COUNT       │
-- │     (ADR-062 Consequences: the app branch is fail-soft, so a broken path returns cleanly     │
-- │     with zero rows and no error — an error-absence assertion is vacuous). THIS LEG DOES      │
-- │     NOT EXERCISE api/src/lib/server/queries/taxonomy.ts and CANNOT — pgTAP runs SQL, not     │
-- │     TypeScript. Backend's `7d8516f` (this branch) already lands the real fix:                │
-- │     `provisionCashflowPrototypes` now selects `CASHFLOW_DEFAULT_PROVISION_COLUMNS`           │
-- │     (`DEFAULT_PROVISION_COLUMNS, is_tax_payment` — its OWN column set, not the shared         │
-- │     constant the asset branch also reads, mirroring the 085 `element` pattern exactly).       │
-- │     This leg is therefore a NECESSARY-not-sufficient companion to that change, not a          │
-- │     workaround for its absence: it proves the DB-layer copy semantics `taxonomy.ts` depends    │
-- │     on are sound; whether `provisionCashflowPrototypes` itself calls them correctly is         │
-- │     Backend's surface, exercised at the Vitest layer. Measured at `7d8516f` (informational,    │
-- │     not a QA finding I can act on — `api/` is read-only to me): `api/src/lib/server/queries/   │
-- │     taxonomy.test.ts` had ZERO references to `is_tax_payment` at that sha — flagged in the      │
-- │     hand-off, CLOSED at `e2c60e9` (re-verify live before trusting this line past that sha).      │
-- └───────────────────────────────────────────────────────────────────────────────────────┘
--
-- §10 / DECISION 3: §10 ledger UNCHANGED (read ADR-011 Decision 4 live before trusting this
--   line). Decision-3 family UNCHANGED (+0) — is_tax_payment is not FK-shaped (ADR-062
--   Consequences, re-verified here rather than merely cited).
--
-- POSTURE (SECURITY §4.5): SYNTHETIC ONLY — fixed-UUID tenants from _rls.tenant_a()/_b()
--   (+ two migration-local tenants for the backfill fixture, same idiom as 077's c/d);
--   NO PII / NO real account numbers / NO prod data. All in a rolled-back txn.
-- =====================================================================

begin;

\ir ../_fixtures/rls_verbs.psql

select plan(30);  -- S1-S10 + E1-E3 + Z1-Z2 + V1-V2 + P1 + BF1-BF4 + IDEM1-IDEM2 + ISO1-ISO3 + FS0-FS2

select _rls.tenant_a() as ta, _rls.tenant_b() as tb \gset
\set tc '00000000-0000-0000-0000-0000000000c1'
\set td '00000000-0000-0000-0000-0000000000d1'
insert into auth.users (id) values (:'ta'), (:'tb'), (:'tc'), (:'td');

-- =====================================================================
-- BLOCK S — shape (catalog-level, role-independent).
-- =====================================================================
select has_column('pfin', 'posting_prototype', 'is_tax_payment',
  '(S1) pfin.posting_prototype.is_tax_payment column exists');
select col_type_is('pfin', 'posting_prototype', 'is_tax_payment', 'boolean',
  '(S2) pfin.posting_prototype.is_tax_payment is type boolean');
select col_not_null('pfin', 'posting_prototype', 'is_tax_payment',
  '(S3) pfin.posting_prototype.is_tax_payment is NOT NULL');
select has_column('pfin', 'posting_prototype_default', 'is_tax_payment',
  '(S4) pfin.posting_prototype_default.is_tax_payment column exists');
select col_type_is('pfin', 'posting_prototype_default', 'is_tax_payment', 'boolean',
  '(S5) pfin.posting_prototype_default.is_tax_payment is type boolean');
select col_not_null('pfin', 'posting_prototype_default', 'is_tax_payment',
  '(S6) pfin.posting_prototype_default.is_tax_payment is NOT NULL');

-- (S7)/(S8) NO DEFAULT — pg_attrdef catalog absence, not a DDL-text inference (Decision 2:
--   the absence is what delivers fail-closed; a fixture/provisioning INSERT that omits the
--   column must error, never silently default).
select is(
  (select count(*)::bigint from pg_attrdef ad
     join pg_attribute a on a.attrelid = ad.adrelid and a.attnum = ad.adnum
    where ad.adrelid = 'pfin.posting_prototype'::regclass and a.attname = 'is_tax_payment'),
  0::bigint,
  '(S7) NO DEFAULT: pfin.posting_prototype.is_tax_payment carries no pg_attrdef entry'
);
select is(
  (select count(*)::bigint from pg_attrdef ad
     join pg_attribute a on a.attrelid = ad.adrelid and a.attnum = ad.adnum
    where ad.adrelid = 'pfin.posting_prototype_default'::regclass and a.attname = 'is_tax_payment'),
  0::bigint,
  '(S8) NO DEFAULT: pfin.posting_prototype_default.is_tax_payment carries no pg_attrdef entry'
);

-- (S9)/(S10) NO CHECK referencing is_tax_payment (Decision 2 — the deliberate absence;
--   asserted as the DESIGNED shape, not merely "not yet added"). Scans pg_constraint's
--   actual definition text, not this file's own prose (DESIGN.md sweep-completeness rule).
select is(
  (select count(*)::bigint from pg_constraint
    where conrelid = 'pfin.posting_prototype'::regclass and contype = 'c'
      and pg_get_constraintdef(oid) ilike '%is_tax_payment%'),
  0::bigint,
  '(S9) NO CHECK: no CHECK constraint on pfin.posting_prototype references is_tax_payment (Decision 2 — a NOT NULL boolean''s domain is already exactly {true,false}; a named CHECK over it cannot fail)'
);
select is(
  (select count(*)::bigint from pg_constraint
    where conrelid = 'pfin.posting_prototype_default'::regclass and contype = 'c'
      and pg_get_constraintdef(oid) ilike '%is_tax_payment%'),
  0::bigint,
  '(S10) NO CHECK: no CHECK constraint on pfin.posting_prototype_default references is_tax_payment'
);

-- =====================================================================
-- BLOCK E — the Equity seed pair, posting_prototype_default (Decision 4's exact contract).
-- =====================================================================
-- (E1) INVERTED at 100 (SELF-263) — was: Equity/Contribution tax_relevant=true
--   (flag-for-review) carrying the ADR-062 Decision 4 rider VERBATIM. 100's E4 D-i
--   ruling retargets this exact row: a contribution of capital is not income, so
--   tax_relevant flips to FALSE and the rider is REMOVED (replaced with a
--   user-facing description) — see 100_tax_value_inventory_seed_delta_rls.sql's
--   own (BF1)/(IDEM1) legs for the paired proof against a replayed pre-100
--   fixture. This leg watches the transition directly against the REAL,
--   already-migrated default row (100 applies before this file's txn opens on
--   the 001->100 stack), not a replay.
select ok(
  (select tax_relevant = false
      and tax_character is null
      and is_tax_payment = false
      and notes not like '%resolve per account type at the V1.4 tax inventory%'
     from pfin.posting_prototype_default
    where cat = 'Equity' and sub_cat = 'Contribution'),
  '(E1) Equity/Contribution POST-100 (SELF-263 E4 D-i, INVERTS this leg''s pre-100 assertion): tax_relevant=FALSE, tax_character IS NULL, is_tax_payment=false, notes NO LONGER carries the ADR-062 Decision 4 review-flag rider — a contribution of capital is not income'
);
select ok(
  (select tax_relevant = false
      and tax_character is null
      and is_tax_payment = false
      and notes = 'Owner capital distribution — value moved out of the portfolio to the owner'
     from pfin.posting_prototype_default
    where cat = 'Equity' and sub_cat = 'Distribution'),
  '(E2) Equity/Distribution: tax_relevant=false, tax_character IS NULL, is_tax_payment=false, notes carries the committed descriptive text VERBATIM'
);
select is(
  (select count(*)::bigint from pfin.posting_prototype_default
    where cat = 'Equity' and sub_cat in ('Contribution', 'Distribution')),
  2::bigint,
  '(E3) exactly the two ratified Equity sub-cats exist in posting_prototype_default — no stray third row'
);

-- =====================================================================
-- BLOCK Z — zero-NULL, both tables, post-backfill-of-pre-existing-rows (mirrors 085's Block Z
--   — every pre-091 row on either table must ALSO have received a value before NOT NULL could
--   land; a stray NULL here means 091's own backfill missed a row class).
-- =====================================================================
select is(
  (select count(*)::bigint from pfin.posting_prototype where is_tax_payment is null),
  0::bigint,
  '(Z1) zero-NULL: no pfin.posting_prototype row has a NULL is_tax_payment'
);
select is(
  (select count(*)::bigint from pfin.posting_prototype_default where is_tax_payment is null),
  0::bigint,
  '(Z2) zero-NULL: no pfin.posting_prototype_default row has a NULL is_tax_payment'
);

-- =====================================================================
-- BLOCK V — vocabulary composition (§2.3.4 exclusion / §2.3.3 non-vacuity).
-- =====================================================================
select is(
  (select count(*)::bigint from pfin.posting_prototype_default
    where sub_cat in ('Contribution', 'Distribution') and cat = 'Expense'),
  0::bigint,
  '(V1) Equity rows are ABSENT from the §2.3.4 expense series: neither Contribution nor Distribution carries cat=''Expense'' (the filter''s own predicate) — structural, not merely a naming convention'
);
select cmp_ok(
  (select count(*) from pfin.posting_prototype_default where cat in ('Transfer', 'Equity')),
  '>', 0::bigint,
  '(V2) precondition/non-vacuity: posting_prototype_default carries >=1 row in the §2.3.3 "Other Cash Flows" composition (Transfer UNION Equity)'
);

-- =====================================================================
-- BLOCK BF — backfill reach (Decision 5). Tenant C: already-provisioned BEFORE 091 (one
--   pre-existing posting_prototype row, some non-Equity cat). Tenant D: NEVER provisioned
--   (zero rows) — the correctly-unreached control (Decision 5 scopes reach to ALREADY-
--   provisioned users; D gets the full set incl. Equity from first-access provisioning once
--   that ships, not from this migration-time backfill).
-- =====================================================================
insert into pfin.posting_prototype (users_id, cat, sub_cat, is_tax_payment) values
  (:'tc', 'Revenue', 'Salary', false);
-- tenant D: deliberately zero rows.

-- (P1) precondition: neither C nor D carries an Equity row before the backfill re-run.
select is(
  (select count(*)::bigint from pfin.posting_prototype
    where users_id in (:'tc', :'td') and cat = 'Equity'),
  0::bigint,
  '(P1) precondition: neither C nor D carries an Equity row before the backfill re-run'
);

-- RE-DERIVED from 091's own committed statement (6), checked byte-for-byte against
-- `git show 09e4743:supabase/migrations/091_posting_prototype_is_tax_payment.sql` — column
-- list, select list, and the `cross join (select distinct pp.users_id from
-- pfin.posting_prototype pp) provisioned` population predicate all match. 077/080 precedent:
-- the only way to exercise a migration-time backfill against a non-empty table on a scratch DB
-- where 091 already ran once against zero real historical users.
insert into pfin.posting_prototype
  (users_id, cat, sub_cat, tax_relevant, tax_character, display_order, notes, is_tax_payment)
select
  provisioned.users_id,
  d.cat, d.sub_cat, d.tax_relevant, d.tax_character, d.display_order, d.notes, d.is_tax_payment
from pfin.posting_prototype_default d
cross join (select distinct pp.users_id from pfin.posting_prototype pp) provisioned
where d.cat = 'Equity' and d.sub_cat in ('Contribution', 'Distribution')
on conflict (users_id, cat, sub_cat) do nothing;

-- (BF1) already-provisioned tenant C receives exactly 2 Equity rows from the backfill re-run.
select is(
  (select count(*)::bigint from pfin.posting_prototype where users_id = :'tc' and cat = 'Equity'),
  2::bigint,
  '(BF1) already-provisioned tenant C receives exactly 2 Equity rows (Contribution + Distribution) from the backfill re-run'
);
-- (BF2) unreached-by-design: tenant D (zero pre-existing rows) receives NOTHING.
select is(
  (select count(*)::bigint from pfin.posting_prototype where users_id = :'td'),
  0::bigint,
  '(BF2) tenant D (zero pre-existing posting_prototype rows) is correctly UNREACHED by the backfill — still zero rows total, not stranded with only the 2 Equity rows (Decision 5 scopes reach to already-provisioned users; D receives the full set from first-access provisioning instead)'
);
-- (BF3) contract fields, SELECTed not hardcoded: C's backfilled Contribution row matches
--   posting_prototype_default's own Contribution row exactly.
select ok(
  (select pp.tax_relevant = pd.tax_relevant
      and pp.tax_character is not distinct from pd.tax_character
      and pp.is_tax_payment = pd.is_tax_payment
      and pp.notes = pd.notes
     from pfin.posting_prototype pp, pfin.posting_prototype_default pd
    where pp.users_id = :'tc' and pp.cat = 'Equity' and pp.sub_cat = 'Contribution'
      and pd.cat = 'Equity' and pd.sub_cat = 'Contribution'),
  '(BF3) C''s backfilled Contribution row matches posting_prototype_default''s contract exactly (tax_relevant, tax_character, is_tax_payment, notes — read from the source table, not re-asserted as a literal)'
);
-- (BF4) tenant binding inherited correctly.
select is(
  (select array_agg(distinct users_id) from pfin.posting_prototype where cat = 'Equity'),
  array[:'tc'::uuid],
  '(BF4) tenant binding: every Equity row post-backfill belongs to C — no stray users_id'
);

-- (IDEM1)/(IDEM2) idempotency — re-run the SAME backfill statement a second time. No second
--   pair for C, D stays unreached.
insert into pfin.posting_prototype
  (users_id, cat, sub_cat, tax_relevant, tax_character, display_order, notes, is_tax_payment)
select
  provisioned.users_id,
  d.cat, d.sub_cat, d.tax_relevant, d.tax_character, d.display_order, d.notes, d.is_tax_payment
from pfin.posting_prototype_default d
cross join (select distinct pp.users_id from pfin.posting_prototype pp) provisioned
where d.cat = 'Equity' and d.sub_cat in ('Contribution', 'Distribution')
on conflict (users_id, cat, sub_cat) do nothing;

select is(
  (select count(*)::bigint from pfin.posting_prototype where users_id = :'tc' and cat = 'Equity'),
  2::bigint,
  '(IDEM1) idempotent re-run: C STILL owns exactly 2 Equity rows after the second backfill pass — no duplicate pair'
);
select is(
  (select count(*)::bigint from pfin.posting_prototype where users_id = :'td'),
  0::bigint,
  '(IDEM2) idempotent re-run: D stays unreached across repeated passes, not just a single one'
);

-- =====================================================================
-- BLOCK ISO — two-tenant isolation on the backfilled rows, under REAL RLS context (SECURITY
--   §4.5) — the standing two-tenant fixture discipline applied to the backfill leg.
-- =====================================================================
select _rls.set_tenant(:'tc'::uuid);
select is(
  (select count(*)::bigint from pfin.posting_prototype where cat = 'Equity'),
  2::bigint,
  '(ISO1) under RLS as tenant C: sees exactly its OWN 2 backfilled Equity rows'
);
select set_config('role', 'postgres', true);

select _rls.expect_cross_tenant_read_empty(
  'pfin.posting_prototype'::regclass, :'tc'::uuid, :'tb'::uuid
);  -- (ISO2) tenant B (never touched C's rows) sees ZERO of C's Equity rows.

select _rls.expect_cross_tenant_write_blocked(
  :'tb'::uuid,
  format($$ insert into pfin.posting_prototype (users_id, cat, sub_cat, is_tax_payment) values (%L, 'Equity', 'Contribution', false) $$, :'tc'),
  '(ISO3) cross-tenant write fails closed: B cannot forge a users_id=C Equity row (WITH CHECK rejects)'
);

-- =====================================================================
-- BLOCK FS — fresh-signup copy semantics, DB layer ONLY. ⚠ Does NOT exercise
--   api/src/lib/server/queries/taxonomy.ts — see the file header for the exact scope of what
--   this leg does and does not observe.
-- =====================================================================
-- Sec-flagged (PR #555 review): (ISO3)'s expect_cross_tenant_write_blocked leaves the session
-- as the INTRUDER tenant (rls_verbs.psql:91-97 — the helper does not self-restore) — the
-- restore MUST sit here, above (FS0), not after it (084's own battery is the correct pattern:
-- restore immediately after the write-blocked call). Without this, (FS0) runs under tenant B's
-- RLS context and its count of A's rows reads 0 unconditionally, regardless of table contents —
-- unfalsifiable. RED-then-GREEN inversion confirmed locally before finalizing this fix.
select set_config('role', 'postgres', true);

select is(
  (select count(*)::bigint from pfin.posting_prototype where users_id = :'ta'),
  0::bigint,
  '(FS0) precondition: tenant A carries zero posting_prototype rows before the fresh-signup copy'
);

insert into pfin.posting_prototype
  (users_id, cat, sub_cat, tax_relevant, tax_character, display_order, notes, is_tax_payment)
select :'ta', d.cat, d.sub_cat, d.tax_relevant, d.tax_character, d.display_order, d.notes, d.is_tax_payment
from pfin.posting_prototype_default d
on conflict (users_id, cat, sub_cat) do nothing;

-- (FS1) expected side HARDCODED at 30 (041's own hardcode-is-an-asset discipline, header
-- note there) — NOT a live `select count(*) from posting_prototype_default` comparison.
-- Sec-noted (PR #555): comparing against a live count of the same table this file's own
-- unfiltered insert-select just copied from is a near-self-comparison that would pass with 2
-- rows on both sides just as readily as with the real 30 — it does not pin the actual expected
-- cardinality the way a hardcoded value does. Re-pinned 29 -> 30 (100/SELF-263 added the
-- Revenue / Dividend - Qualified row to posting_prototype_default).
select is(
  (select count(*)::bigint from pfin.posting_prototype where users_id = :'ta'),
  30::bigint,
  '(FS1) posting_prototype_default rows after 100 = 30 (29 at 091 + Dividend - Qualified): fresh-signup receives the FULL cash-flow set, asserted by ROW COUNT (not error-absence — the app branch is fail-soft and a broken path returns cleanly with zero rows)'
);
select is(
  (select count(*)::bigint from pfin.posting_prototype pp
     join pfin.posting_prototype_default pd
       on pd.cat = pp.cat and pd.sub_cat = pp.sub_cat
    where pp.users_id = :'ta' and pp.is_tax_payment is distinct from pd.is_tax_payment),
  0::bigint,
  '(FS2) every copied row''s is_tax_payment matches its posting_prototype_default source exactly — zero mismatches (companion to FS1''s row-count proof; a count match alone would not catch a wrong-value copy)'
);

select * from finish();
rollback;
