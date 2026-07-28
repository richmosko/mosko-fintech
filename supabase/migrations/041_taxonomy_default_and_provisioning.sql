-- ============================================================================
-- Migration: pfin.taxonomy_default (canonical default-taxonomy home) + the
-- pfin.user_taxonomy first-access provisioning write path.
-- Phase 6 Build Loop (SELF-311 / default-taxonomy provisioning on signup).
-- Implements ADR-036 (F/CTO-ratified 2026-07-28: B1 + A1 + first-access-lazy).
--
-- WHY: F/CTO ruled V1 signup is OPEN → provisioning a default user_taxonomy is a
-- V1-SHIP-BLOCK (else the asset classify picker §2.2.1 + the §2.4.3 cashflow
-- Sub-Cat dropdowns dead-end for every new user). Two coupled gaps close here:
--   (A1) the default set had NO canonical home — it lived ONLY in the gitignored
--        dev-only seed.sql (63 hardcoded rows). This migration creates
--        pfin.taxonomy_default, a global reference table populated with those 63
--        rows (verbatim; 36 asset + 27 cashflow; incl. the 010 `notes` column), as
--        the single committed source. seed.sql is refactored to seed the dev user
--        FROM this table (one source, no drift) — see the seed.sql change in the
--        same PR.
--   (B1) 009 user_taxonomy is V1-WRITE-DORMANT (authenticated SELECT only). This
--        migration adds a SCOPED authenticated INSERT grant + user_taxonomy_insert
--        policy (with check users_id = auth.uid(); INSERT ONLY — no UPDATE/DELETE),
--        the minimum write path for the app to lazily upsert the default set under
--        the user's OWN JWT (mirrors the 024 lazy-upsert precedent). This is a
--        SCOPED, DELIBERATE early un-defer of Lock 7 write-dormancy (INSERT only;
--        the V2 taxonomy-CRUD-UI PR still owns UPDATE/DELETE).
--
-- WHAT THIS DOES NOT DO: no function is authored (no DEFINER, no INVOKER — the
--   provision path is authenticated SQL run by the app). The actual first-access
--   lazy-provision CALL lives in the authenticated server bootstrap (Backend,
--   +layout.server.ts / hooks.server.ts) — NOT in this migration. It is
--   EXISTENCE-GUARDED: the bootstrap first checks `select 1 from pfin.user_taxonomy
--   where users_id = auth.uid() limit 1` and SKIPS the INSERT if any row exists, so
--   an already-provisioned user never re-runs it. Canonical provision statement
--   (documented here; executed app-side under the user JWT, only when the guard
--   finds no existing rows):
--     insert into pfin.user_taxonomy
--       (users_id, domain, cat, sub_cat, tax_relevant, tax_character, display_order, notes)
--     select auth.uid(), domain, cat, sub_cat, tax_relevant, tax_character, display_order, notes
--     from pfin.taxonomy_default
--     on conflict (users_id, domain, cat, sub_cat) do nothing;
--   Data-idempotent (009's unique (users_id, domain, cat, sub_cat) + on conflict do
--   nothing prevents duplicate rows). NOTE (QA-proven 2026-07-28): `on conflict do
--   nothing` is NOT a safe blind-re-run for a totp@aal1 caller — RLS WITH CHECK is
--   evaluated on each proposed row BEFORE conflict resolution, so a raw re-run RAISES
--   rather than no-op'ing. The EXISTENCE-GUARD (above), not conflict-skipping, is
--   what makes re-invocation safe — see AAL2 BACKSTOP DECISION.
--
-- ----------------------------------------------------------------------------
-- Numbering: 041 follows 040 (dedup_detection_and_sync_history). Depends on:
--   009 (pfin.user_taxonomy — the INSERT policy/grant target + its unique index),
--   010 (added user_taxonomy.notes — the default set carries it),
--   024 (pfin.user_settings — read by the aal2 backstop subselect on the new
--        INSERT policy, see AAL2 DECISION), and
--   025 (the aal2 backstop already claused user_taxonomy_select; this migration
--        keeps the new INSERT policy consistent with it — see AAL2 DECISION).
--   Order-dependent: must run AFTER 009/010/024/025. No later migration depends on
--   041 landing first. taxonomy_default is a fresh table (depends only on the pfin
--   schema, 001).
--
-- ----------------------------------------------------------------------------
-- POSTURE RATIONALE — NO function authored with elevated privilege.
--   This migration creates NO SECURITY DEFINER and NO SECURITY INVOKER function.
--   It is: CREATE TABLE pfin.taxonomy_default + its 63-row seed + RLS/GRANT;
--   one new RLS INSERT policy + INSERT grant on pfin.user_taxonomy. The SECURITY
--   DEFINER allowlist is UNCHANGED at 4 (ADR-011 Decision 9; authored = 3:
--   fn_refresh_updated_at @001 + fn_grant_creator_access @003 +
--   fn_reclass_history_insert @031; the general audit-log helper still reserved).
--   ADR-036 chose B1 (authenticated lazy upsert) precisely to AVOID authoring a
--   DEFINER provisioning function (B2, which would have grown the allowlist 4->5)
--   and to avoid a service_role write path (B3). `set search_path = ''` is N/A
--   (no function defined here).
--
-- ----------------------------------------------------------------------------
-- §10 3-AXIS CROSS-CHECK (Path B — reference ADR-011 Decision 4; do NOT restate
-- the catalogued numbered list; Decision 4 read VERBATIM before drafting). This
-- migration introduces ZERO catalogued §10 instances; the ledger stays at 3
-- (RT-22 first / RT-26 second / RT-27 third, per ADR-011 Decision 4). A global
-- reference table + an authenticated-tier INSERT policy/grant touch none of the
-- three catalogued surfaces:
--   (i)   Instance-numbering: UNCHANGED — RT-22 first, RT-26 second, RT-27 third.
--   (ii)  Layer-attribution: UNCHANGED —
--           · RT-22 = PDF-worker infrastructure-credential-presence layer (no
--             container / infra-credential surface touched);
--           · RT-26 = SUPABASE_SERVICE_ROLE_KEY code-layer allowlist grep fence (no
--             service_role key, no code-layer surface — this is DB DDL under the
--             authenticated tier; service_role is NEITHER granted NOR referenced,
--             on either table. ADR-036 chose B1 over B3 specifically to keep
--             service_role off this write path);
--           · RT-27 = app→worker credential-admission network-exposure/config layer
--             (no admission-endpoint / network-bind surface touched).
--   (iii) Verbatim-vs-paraphrase: Decision 4 is linked, not restated.
--
-- ----------------------------------------------------------------------------
-- DECISION 3 (cross-tenant FK-bypass family) EVALUATION — family count +0
-- (UNCHANGED). Stated explicitly per the mandatory FK-shaped-column check:
--   · pfin.taxonomy_default has NO users_id and NO reference column of ANY kind
--     (no FK, no self-FK, no INTEGER[] array) — it is global, non-tenant reference
--     data. Nothing to matched-tenant-validate; it cannot join the family.
--   · The new user_taxonomy_insert policy introduces NO new reference column. The
--     app-side provision INSERT sets user_taxonomy.users_id = auth.uid() — the SAME
--     tenant-anchor shape 009 already evaluated (users_id IS the tenant anchor, not
--     a cross-tenant reference; there is no second anchor to mismatch). The WITH
--     CHECK (users_id = auth.uid()) is the standard C5 own-write shape, not a
--     cross-tenant-FK validation.
--   (Unrelated + still deferred: the account_trans.sub_cat_id -> user_taxonomy FK
--    that 004 deferred remains its OWN future Decision-3 evaluation — NOT here.)
--   Decision 3 family UNCHANGED.
--
-- ----------------------------------------------------------------------------
-- AAL2 BACKSTOP DECISION (the item flagged for Sec sign-off — ADR-036 handoff #4).
--   CONTEXT: 025 already ANDs the per-user-conditional aal2 backstop clause into
--   user_taxonomy_select. This migration adds an authenticated INSERT policy, so it
--   must decide whether that policy carries the same clause. The design worry —
--   "a brand-new user is aal1 and hasn't set up MFA, so requiring aal2 would make
--   provisioning impossible" — is RESOLVED BY THE CLAUSE'S OWN DESIGN, not by
--   dropping it: the clause is COALESCE null-safe and FAILS OPEN on 'none'/missing
--   (025 lines 61-70) —
--     (coalesce((select s.mfa_policy from pfin.user_settings s
--                where s.users_id = auth.uid()), 'none') not in ('totp','passkey')
--      or (auth.jwt() ->> 'aal') = 'aal2')
--   A brand-new user has NO user_settings row (lazy per 024) OR mfa_policy='none' →
--   coalesce → 'none' → 'none' not in ('totp','passkey') → TRUE → the clause is
--   satisfied at aal1. So provisioning works at aal1 for the ENTIRE new-user
--   population (every new user is 'none' at first access). The clause can only
--   evaluate FALSE for a user who has DECLARED totp/passkey AND is at aal1.
--
--   CORRECTION (QA empirical psql probe, 2026-07-28): an earlier draft of this block
--   claimed a totp@aal1 re-provision is a harmless no-op because "all rows conflict
--   → do nothing → zero rows checked → passes regardless." That is FALSE. `INSERT …
--   ON CONFLICT DO NOTHING` evaluates the RLS WITH CHECK on each PROPOSED row BEFORE
--   conflict resolution, so the RAW statement RAISES `new row violates row-level
--   security policy` (NOT a silent no-op) for a totp@aal1 caller. Conflict-skipping
--   is therefore NOT the safety mechanism.
--
--   WHY SHAPE A NONETHELESS NEVER BLOCKS A REAL PROVISIONING PATH — the safety is the
--   Backend EXISTENCE-GUARD (skip-if-any-row), not conflict-skipping:
--     (1) The bootstrap provision path is existence-guarded (`select 1 from
--         pfin.user_taxonomy where users_id = auth.uid() limit 1` → SKIP the INSERT
--         if any row exists). An already-provisioned user NEVER re-runs the INSERT,
--         so the aal2-gated statement is never reached for them.
--     (2) A totp user was provisioned back when they were 'none'/aal1 (first-access
--         provisioning precedes MFA enrollment), so their guarded path completed
--         while the clause was fail-open — it never hit the aal2 gate.
--     (3) A PRE-041 totp user with no taxonomy yet provisions via the layout guard
--         AFTER their next step-up to aal2 — fail-soft empty until then (acceptable:
--         non-sensitive reference data; the classify surface simply shows no Sub-Cats
--         until step-up completes their one-time provision).
--   Net: the only caller the clause can block is a totp@aal1 user with NO taxonomy — a
--   pre-041 edge who provisions on their next aal2, never a steady-state new user. The
--   existence-guard (Backend, ADR-036 handoff #2) is load-bearing here and MUST ship
--   with the migration.
--
--   DECISION (Architect; Shape A — CARRY THE CLAUSE): user_taxonomy_insert carries
--   the IDENTICAL backstop clause as user_taxonomy_select. Rationale: (1) it is
--   aal1-permitting for the entire provisioning population (fail-open on 'none'),
--   so it satisfies "provisioning must work at aal1"; (2) it preserves the uniform
--   C3 invariant that EVERY authenticated write path on a sensitive tenant table
--   carries the backstop (apply-migration Step 4 aal2-inheritance obligation) — no
--   un-claused write-path hole; (3) it is byte-consistent with the SELECT policy a
--   totp-user already lives under (they can't read taxonomy at aal1 either).
--   GROWTH NOTE (reframed per the QA correction): because the provision path is
--   existence-guarded (skip-if-ANY-row), EXISTING users do not receive default-set
--   additions through it AT ALL — regardless of aal, and regardless of Shape A vs B.
--   So a future default-set growth is NOT a "totp@aal1 UX lag" (the earlier framing
--   was wrong); it simply does not reach already-provisioned users via first-access
--   provisioning under either shape. Moot in V1 anyway (fixed 63-row set, no editor);
--   a future set-growth that must reach existing users would be its own data-
--   migration/backfill decision, independent of this clause.
--   ALTERNATIVE (Shape B — clause-free INSERT: with check (users_id = auth.uid())
--   only): its SOLE functional difference from Shape A (under the existence-guard) is
--   that the one blocked caller — a totp@aal1 user with NO taxonomy (the pre-041 edge,
--   case 3) — would provision immediately at aal1 instead of on their next aal2. In
--   exchange, Shape B creates the project's ONLY un-claused authenticated write path
--   on a sensitive tenant table (a new exclusion category: "bootstrap write of global
--   non-sensitive reference content"). Judged not worth it: the case-3 edge self-heals
--   on the user's next step-up (fail-soft empty until then), so Shape A keeps the
--   uniform C3 invariant at effectively zero functional cost. SEC DECIDES: this
--   migration ships Shape A; if Sec prefers Shape B, it is a one-line edit (drop the
--   `and (...)` conjunct from user_taxonomy_insert). This is the explicit Sec sign-off
--   item.
--
-- ----------------------------------------------------------------------------
-- EXPOSURE / C6 RLS-COVERAGE NOTE (ADR-023 C6 — pfin is in [api] schemas, so both
-- surfaces are internet-facing the moment they are granted):
--   pfin.taxonomy_default — GLOBAL SHARED-READ reference data (category names +
--     definitional notes; NO tenant rows, NO $-figures). RLS ENABLED with a
--     `using (true)` SELECT policy for authenticated (mirrors pfin.tax_character,
--     ADR-024 global-registry pattern) + SELECT grant to authenticated. anon
--     ZERO-grant (pfin schema-usage denial, ADR-023 C2 outer fence). service_role
--     NOT granted (provisioning is authenticated). EXCLUDED from the 025 aal2
--     backstop per exclusion (i) global-shared-read (`using(true)`) — stated per
--     the 025 exclusion-reasoning discipline: it holds no sensitive/tenant data, so
--     the step-up threat model does not apply. No write policy/grant for any tier
--     (content is migration-authored + immutable-by-omission in V1).
--   pfin.user_taxonomy — the INSERT policy is a LIVE (scoped) write path now.
--     POLICIES: user_taxonomy_select (009, aal2-claused at 025) + the NEW
--     user_taxonomy_insert (aal2-claused here — Shape A). No UPDATE/DELETE policy or
--     grant (still deferred to the V2 CRUD-UI PR — writes-that-mutate remain
--     default-denied at BOTH the ACL and RLS layers). GRANT: authenticated gains
--     INSERT (added to the existing SELECT). anon ZERO; service_role NONE.
--   Neither table ships without the paired QA two-tenant pgTAP battery (SECURITY
--   §4.5, EXPOSURE-gating per C6). Battery asserts (QA-authored): owner provisions
--   own rows PASS; tenant B cannot INSERT A's users_id (WITH CHECK fail-closed);
--   re-provision is idempotent (no duplicate rows); taxonomy_default readable by
--   any authenticated user but carries NO tenant rows; UPDATE/DELETE on
--   user_taxonomy still fail closed at the grant layer (dormant). Architect does
--   not edit tests/; Sec sign-off gates the V1-SHIP-BLOCK merge.
--
-- ----------------------------------------------------------------------------
-- CONTRACT
--   pfin.taxonomy_default — global canonical default two-level taxonomy (the
--     provisioning source). Columns mirror the user_taxonomy value columns MINUS
--     users_id: domain ('asset'|'cashflow' CHECK) / cat / sub_cat / tax_relevant /
--     tax_character (same 5-value CHECK as 009) / display_order / notes.
--     UNIQUE (domain, cat, sub_cat). NO users_id, NO FK — global reference data.
--   pfin.user_taxonomy — gains user_taxonomy_insert (authenticated, INSERT, WITH
--     CHECK users_id = auth.uid() AND <025 aal2 backstop clause>) + an INSERT grant.
--     Security-load-bearing edges: WITH CHECK fences the write to the owner's own
--     users_id; the aal2 conjunct is ANDed (never replaces) the tenant predicate;
--     INSERT-only (no UPDATE/DELETE) keeps Lock 7's mutate-dormancy intact.
-- ============================================================================

create schema if not exists pfin;
grant usage on schema pfin to authenticated;

-- ----------------------------------------------------------------------------
-- pfin.taxonomy_default — canonical default taxonomy (A1; ADR-036). Global,
-- non-tenant reference data; the single committed source the provisioning path and
-- the dev seed both read. NO users_id / NO FK (Decision 3 family untouched).
-- ----------------------------------------------------------------------------
create table if not exists pfin.taxonomy_default (
  id             bigint generated always as identity primary key,
  domain         text not null
                   check (domain in ('asset', 'cashflow')),
  cat            text not null,
  sub_cat        text not null,
  tax_relevant   boolean not null default false,
  tax_character  text
                   check (tax_character in (
                     'ordinary', 'qualified_dividend', 'tax_exempt_interest',
                     'long_term_capital_gain_eligible', 'short_term_only')),
  display_order  integer,
  notes          text,
  unique (domain, cat, sub_cat)
);

comment on table pfin.taxonomy_default is
  'Global canonical default two-level Cat x Sub-Cat taxonomy (ADR-036 / SELF-311, '
  'B1+A1). The single committed source for default-taxonomy provisioning — 63 rows '
  '(36 asset §2.2.1 + 27 cashflow §2.3.1), ported verbatim from the pre-041 '
  'gitignored seed.sql (which now seeds the dev user FROM this table). Columns '
  'mirror pfin.user_taxonomy MINUS users_id. GLOBAL SHARED-READ (RLS using(true), '
  'authenticated SELECT; anon zero; service_role none) — non-tenant reference data '
  '(category names + notes; no $-figures), so EXCLUDED from the 025 aal2 backstop '
  'per exclusion (i). NO users_id / NO FK — Decision 3 family UNCHANGED. Content is '
  'migration-authored; changing the default set later is a data migration.';

alter table pfin.taxonomy_default enable row level security;

-- Global shared-read: any authenticated user reads the whole default set (it is the
-- provisioning source). using(true) — no tenant predicate (mirrors tax_character,
-- ADR-024). EXCLUDED from the 025 aal2 backstop (exclusion (i) global-shared-read).
create policy taxonomy_default_select on pfin.taxonomy_default
  for select to authenticated using (true);

-- ACL-before-RLS (PR #106): SELECT grant required even with RLS on. Read-only:
-- no insert/update/delete grant for any tier (content is migration-authored).
grant select on pfin.taxonomy_default to authenticated;

-- ---------------------------------------------------------------------------
-- ASSET domain (§2.2.1) — 36 rows, tax-neutral in V1 (ADR-006 Axis 2 dormant;
-- tax_relevant=false / tax_character=null for all asset rows).
-- ---------------------------------------------------------------------------
insert into pfin.taxonomy_default
  (domain, cat, sub_cat, tax_relevant, tax_character, display_order, notes)
values
  ('asset', 'Cash',         'FDIC',                        false, null, 10,  'Federal Deposit Insurance Corp.'),
  ('asset', 'Cash',         'SPIC',                        false, null, 20,  'Securities Investor Protection Corp.'),
  ('asset', 'Cash',         'T-Bill',                      false, null, 30,  'Treasury Bill (less than 1 year duration)'),
  ('asset', 'Cash',         'CD',                          false, null, 40,  'Certificate of Deposit'),
  ('asset', 'Bonds',        'IGL',                         false, null, 50,  'Investment Grade (A and above) Long Duration (3-7 year)'),
  ('asset', 'Bonds',        'IGI',                         false, null, 60,  'Investment Grate (A and above) Intermediate Duration (under 3 year)'),
  ('asset', 'Bonds',        'HYI',                         false, null, 70,  'High Yield (B and above) Intermediate Duration (under 3 year)'),
  ('asset', 'Bonds',        'INTL',                        false, null, 80,  'International (A and above) Long Duration (3-7 year)'),
  ('asset', 'Equity',       'UNKNOWN',                     false, null, 90,  'To be defined (initial adding), or otherwise unknown sub-category'),
  ('asset', 'Equity',       'US-01-Basic_Materials',       false, null, 100, 'US (GICS) Basic Materials Sector'),
  ('asset', 'Equity',       'US-02-Telecom',               false, null, 110, 'US (GICS) Telecommunications Sector'),
  ('asset', 'Equity',       'US-03-Consumer_Discretionary',false, null, 120, 'US (GICS) Consumer Discretionary Sector'),
  ('asset', 'Equity',       'US-04-Consumer_Staples',      false, null, 130, 'US (GICS) Consumer Staples Sector'),
  ('asset', 'Equity',       'US-05-Energy',                false, null, 140, 'US (GICS) Energy Sector'),
  ('asset', 'Equity',       'US-06-Financials',            false, null, 150, 'US (GICS) Financials Sector'),
  ('asset', 'Equity',       'US-07-Health_Care',           false, null, 160, 'US (GICS) Health Care Sector'),
  ('asset', 'Equity',       'US-08-Industrials',           false, null, 170, 'US (GICS) Industrial Manufaaturing Sector'),
  ('asset', 'Equity',       'US-09-Information_Technology', false, null, 180, 'US (GICS) Information Technology Sector'),
  ('asset', 'Equity',       'US-10-Utilities',             false, null, 190, 'US (GICS) Utilities Sector'),
  ('asset', 'Equity',       'US-Index-Non_Sector',         false, null, 200, 'US non-sector based broad market index ETF'),
  ('asset', 'Equity',       'US-Growth-Non_Sector',        false, null, 210, 'US Growth stock or ETF'),
  ('asset', 'Equity',       'ExUS-Developed_Market',       false, null, 220, 'Developed Market stock or ETF outside the US'),
  ('asset', 'Equity',       'ExUS-Emerging_Market',        false, null, 230, 'Emerging Market stock or ETF'),
  ('asset', 'Alternatives', 'REIT',                        false, null, 240, 'Real Estate Investemnt Trust ETF'),
  ('asset', 'Alternatives', 'Crypto-Fx',                   false, null, 250, 'Cryptocurrency or Foreign Currency'),
  ('asset', 'Alternatives', 'Commodities-Other',           false, null, 260, 'Commoditiy or Other non-revenue producing asset'),
  ('asset', 'Alternatives', 'Volatility-Hedges',           false, null, 270, 'Option or Future as a hedge investent'),
  ('asset', 'Alternatives', 'Volatility-60/40',            false, null, 280, 'IRS Section 1256 contract on Index/ForEx/Commodity'),
  ('asset', 'Liabilities',  'Credit-Balance',              false, null, 290, 'Credit Card or other Revolving Credit Balance'),
  ('asset', 'Liabilities',  'EstTax-Pending',              false, null, 300, 'Estimated Taxes Due but not yet paid'),
  ('asset', 'Liabilities',  'Loan-Balance',                false, null, 310, 'Outstanding Balance on a loan'),
  ('asset', 'Real Estate',  'Residential',                 false, null, 320, 'Residential Property'),
  ('asset', 'Real Estate',  'Commercial',                  false, null, 330, 'Commercial Property'),
  ('asset', 'Real Estate',  'Remodel-Equity',              false, null, 340, 'In-Progress Equity from a remodel that isn''t assesed yet'),
  ('asset', 'Real Estate',  'Vehicle',                     false, null, 350, 'Vehicles and similar depreciating assets'),
  ('asset', 'Real Estate',  'Misc',                        false, null, 360, 'Miscellaneous other tangible/sellable assets')
on conflict (domain, cat, sub_cat) do nothing;

-- ---------------------------------------------------------------------------
-- CASHFLOW domain (§2.3.1) — 27 rows. Revenue rows carry the V1 default
-- tax_character (ADR-006 Axis 2); Expense/Transfer tax-neutral; Trade CLOSE rows
-- (STC/BTC) are tax events with character derived from holding period (§2.4.3).
-- ---------------------------------------------------------------------------
insert into pfin.taxonomy_default
  (domain, cat, sub_cat, tax_relevant, tax_character, display_order, notes)
values
  ('cashflow', 'Revenue',   'Interest - Tax Free',     true,  'tax_exempt_interest', 10,  'Tax Free Interest Income'),
  ('cashflow', 'Revenue',   'Interest - Ordinary Inc', true,  'ordinary',            20,  'Interest Income from Cash'),
  ('cashflow', 'Revenue',   'Interest - Bond/CD',      true,  'ordinary',            30,  'Interest Income from a Bond or Certificate of Deposit'),
  ('cashflow', 'Revenue',   'Rent Misc',               true,  'ordinary',            40,  'Miscellaneous Rental Income'),
  ('cashflow', 'Revenue',   'Bond Premium',            true,  'ordinary',            50,  'Mark-to-Market Gain for Tax Purposes'),
  ('cashflow', 'Revenue',   'Dividend',                true,  'qualified_dividend',  60,  'Dividend from a Stock or ETF'),
  ('cashflow', 'Revenue',   'Salary Untagged',         true,  'ordinary',            70,  'Income from Salary - Untagged Person'),
  ('cashflow', 'Expense',   'Auto & Transport',        false, null, 80,  'Auto and Transportation Expenses'),
  ('cashflow', 'Expense',   'Bills & Utilities',       false, null, 90,  'Utilities and other Bills'),
  ('cashflow', 'Expense',   'Cash & ATM',              false, null, 100, 'Cash and ATM withdrawls'),
  ('cashflow', 'Expense',   'Entertainment',           false, null, 110, 'Entertainment Expenses'),
  ('cashflow', 'Expense',   'Food, Dining, & Alcohol', false, null, 120, 'Food, Dining, and Alcohol Expenses'),
  ('cashflow', 'Expense',   'Gifts and Donations',     false, null, 130, 'Gifts and Donation Expenses'),
  ('cashflow', 'Expense',   'Health & Fitness',        false, null, 140, 'Health and Fitness Expenses'),
  ('cashflow', 'Expense',   'Home',                    false, null, 150, 'Home and Home Maintenance Expenses'),
  ('cashflow', 'Expense',   'Misc',                    false, null, 160, 'Miscellaneous Expenses'),
  ('cashflow', 'Expense',   'Personal Care',           false, null, 170, 'Hair Cuts, Massages, and other Person Care Expenses'),
  ('cashflow', 'Expense',   'Shopping',                false, null, 180, 'Shopping Expenses'),
  ('cashflow', 'Expense',   'Travel',                  false, null, 190, 'Travel related Expenses'),
  ('cashflow', 'Transfer',  'Cash',             false, null, 200, 'Transfer between Accounts'),
  ('cashflow', 'Transfer',  'Tax - US Federal', false, null, 210, 'Federal Tax Payments / Witholding - Transfer to Government'),
  ('cashflow', 'Transfer',  'Tax - California', false, null, 220, 'California Tax Payments / Witholding - Transfer to Government'),
  ('cashflow', 'Transfer',  'Fixed Assets',     false, null, 230, 'Fixed-asset purchase - transfer to slush fund'),
  ('cashflow', 'Trade',     'BTO',              false, null, 240, 'Buy to Open (Long) Asset Transaction'),
  ('cashflow', 'Trade',     'STC',              true,  null, 250, 'Sell to Close (Long) Asset Transaction — tax event; character from holding period (§2.4.3)'),
  ('cashflow', 'Trade',     'STO',              false, null, 260, 'Sell to Open (Short) Asset Transaction'),
  ('cashflow', 'Trade',     'BTC',              true,  null, 270, 'Buy to Close (Short) Asset Transaction — tax event; character from holding period (§2.4.3)')
on conflict (domain, cat, sub_cat) do nothing;

-- ----------------------------------------------------------------------------
-- pfin.user_taxonomy — scoped write path (B1): authenticated INSERT only.
-- Un-defers Lock 7 write-dormancy for INSERT ONLY (UPDATE/DELETE still deferred to
-- the V2 CRUD-UI PR). WITH CHECK fences the write to the owner AND carries the 025
-- aal2 backstop clause (Shape A — see AAL2 BACKSTOP DECISION; Sec sign-off item).
-- ----------------------------------------------------------------------------
create policy user_taxonomy_insert on pfin.user_taxonomy
  for insert to authenticated
  with check (
    (users_id = auth.uid())
    and (
      coalesce((select s.mfa_policy from pfin.user_settings s where s.users_id = auth.uid()), 'none') not in ('totp', 'passkey')
      or (auth.jwt() ->> 'aal') = 'aal2'
    )
  );

-- ACL-before-RLS (PR #106): add INSERT to the existing authenticated SELECT grant
-- (009). NO update/delete grant (mutate-dormancy preserved). anon/service_role
-- untouched (zero / none).
grant insert on pfin.user_taxonomy to authenticated;
