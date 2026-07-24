-- ============================================================================
-- Migration: pfin.user_taxonomy — domain-conditional cashflow-class CHECK.
-- Phase 6 Build Loop (SELF-292 / M1 — first migration of the Double-Entry GL
-- track). Implements ADR-031 (double-entry accounting model) Decision 1 (C —
-- Category-as-class) as amended by ADR-031 Amendment 1 (the RATIFIED
-- settle-before-import conventions, 2026-07-23). Constrains the CASHFLOW-domain
-- top-level `cat` to the ratified 5-class accounting enum so the Category IS the
-- enforced accounting class — no separate `flow_class` column, no
-- `normal_balance` column (normal-balance derives from the class).
--
-- WHAT THIS DOES: adds ONE domain-conditional named CHECK constraint
--   (user_taxonomy_cashflow_class_chk) to the existing pfin.user_taxonomy table:
--     domain <> 'cashflow'  OR  cat in ('Revenue','Expense','Transfer','Equity','Trade')
--   Asset-domain rows (domain='asset', e.g. "US Equity" allocation cats) are
--   UNCONSTRAINED — their cat stays free text (the CHECK short-circuits true via
--   the `domain <> 'cashflow'` disjunct). sub_cat stays free text in BOTH domains.
--
--   RATIFIED 5-CLASS ENUM (ADR-031 Amendment 1 §1 — supersedes the STALE
--   {Income,Expense,Transfer,Distribution,Equity} sketch at
--   temp/double-entry-design-v2.md:83):
--     Revenue   (was Income)                     — credit-normal
--     Expense   (was Expenses; singular)         — debit-normal
--     Transfer  (tax-neutral real<->real moves)  — no contra
--     Equity    (Contribution/Distribution;      — credit-normal
--                Distribution demoted from a top-level class to Equity::Distribution)
--     Trade     (NEW; securities buy/sell,        — self-balancing + realized G/L
--                sub-cats BTO/STC/STO/BTC)          on close
--
-- WHAT THIS IS NOT: no new column (no flow_class, no normal_balance — both
--   derive from the class). No FK. No new function. No RLS policy / GRANT / ACL
--   change. No SECURITY DEFINER. No backfill / no UPDATE — pfin.user_taxonomy
--   carries ZERO data at migration time (see EMPTY-TABLE PROPERTY), so there are
--   no rows to remap; the incumbent cashflow seed is gitignored/local and loads
--   AFTER migrations at `db reset` (see COUPLED SEED FOLLOW-UP).
--
-- ----------------------------------------------------------------------------
-- Numbering: 028 follows 027 (mfa_recovery_attempt). This is a purely additive
--   ALTER TABLE ... ADD CONSTRAINT on pfin.user_taxonomy. Depends ONLY on 009
--   (the user_taxonomy base table + its `domain` and `cat` columns, both NOT
--   NULL) — the closest model is 010 (also a standalone additive ALTER on
--   user_taxonomy). It does NOT depend on 010 (notes) or 011 (tax_character FK):
--   different columns, no interaction. No downstream migration depends on 028
--   landing first.
--
-- EMPTY-TABLE PROPERTY (why ADD CONSTRAINT is a clean, no-backfill ALTER):
--   pfin.user_taxonomy is V1-write-dormant (009: authenticated SELECT-only; no
--   write policy/grant) and carries ZERO data at migration time — the taxonomy
--   seed runs at `db reset` UNDER the admin migration connection, AFTER all
--   migrations, and is gitignored/local (supabase/seed.sql, F/CTO's personal
--   taxonomy). So ADD CONSTRAINT validates against zero rows and always succeeds.
--   FORWARD-ONLY: 009/010/011 are merged to main -> immutable; this migration
--   does NOT re-baseline them. That no-data property is the same one 011 relied
--   on for its CHECK->FK swap — it is why the constraint is cheap to add NOW, not
--   a license to edit an earlier migration.
--
-- ----------------------------------------------------------------------------
-- POSTURE RATIONALE — NO function authored (no elevated-privilege surface).
--   This migration authors NO function — no SECURITY DEFINER and no SECURITY
--   INVOKER. It is a single additive ALTER TABLE ... ADD CONSTRAINT + a
--   `comment on constraint`. The SECURITY DEFINER allowlist is UNCHANGED at 3
--   (ADR-011 Decision 9 / SELF-187 amendment: fn_refresh_updated_at +
--   fn_grant_creator_access + the still-unauthored audit-log insert helper). No
--   new DEFINER entry -> no Sec-DEFINER-review trigger. `set search_path = ''` is
--   N/A (a function-body guard; this migration defines no function).
--
-- ----------------------------------------------------------------------------
-- §10 3-AXIS CROSS-CHECK (Path B — reference ADR-011 Decision 4; do NOT restate
-- the catalogued numbered list). This migration introduces ZERO catalogued §10
-- instances; the ledger stays at 3 (RT-22 + RT-26 + RT-27 per ADR-011
-- Decision 4, count moved 2->3 at the RT-27 catalogue flip 2026-07-19; see the
-- LEDGER-COUNT NOTE below). A domain-conditional attribute CHECK on an
-- authenticated-tier, V1-write-dormant table touches no fenced surface on any of
-- the three catalogued layers.
--   (i)   Instance-numbering: UNCHANGED (not touched) — RT-22 first /
--         RT-26 second / RT-27 third.
--   (ii)  Layer-attribution: UNCHANGED — no infrastructure-credential-presence
--         surface (RT-22), no code-layer SUPABASE_SERVICE_ROLE_KEY allowlist
--         surface (RT-26), and no network-exposure/config app->worker
--         credential-admission surface (RT-27) is touched. This is a pure
--         table-level CHECK constraint; it grants nothing and exposes nothing.
--   (iii) Verbatim-vs-paraphrase: Decision 4 is LINKED, not restated (Path B).
--   LEDGER-COUNT NOTE: earlier migrations 009/010/011/024 state "stays at 2".
--   That count PRE-DATES the RT-27 cataloguing (ADR-011 Decision 4 count-move
--   flip-point, 2026-07-19; corroborated at ADR-031 Decision 8). The canonical
--   count is now 3 (RT-22 + RT-26 + RT-27); this migration states the current
--   canonical value. This is a read-forward correction, NOT a ledger change by
--   this migration (count-of-record was already 3 before 028) — so it is not
--   itself a Sec-joint-review-triggering ledger move. Flagged to team-lead so the
--   stale "2" in supabase/CLAUDE.md + the apply-migration skill can be reconciled.
--
-- ----------------------------------------------------------------------------
-- DECISION 3 (cross-tenant FK-bypass family) EVALUATION — family count +0
-- (UNCHANGED; canonical 11 labeled instances / 9 DDL-realized per ADR-011
-- Decision 3 as extended by ADR-031 Decision 8). This migration adds NO
-- FK-shaped reference column of any kind: it is a CHECK on the EXISTING
-- `cat` text column (a value-domain constraint), with NO FOREIGN KEY, NO
-- INTEGER[]/array element, NO self-FK, NO cross-table reference, NO tenant
-- anchor. There is nothing to matched-tenant-validate. Decision 3 family
-- UNCHANGED. (Stated explicitly per the mandatory FK-shaped-column check.)
--   NOT-THIS-MIGRATION: the two ADR-031-forward-flagged Decision-3 additions —
--   `journal_group_id` (#12, at M2) + the lot-matching buy-reference FK (at
--   M1-evt) — are matched-tenant-MANDATORY and land at THEIR migrations, not
--   here. M1 introduces no FK; do not conflate.
--
-- ----------------------------------------------------------------------------
-- GRANTS / RLS / EXPOSURE — NO change required.
--   A CHECK constraint carries no ACL and no RLS. The existing 009 posture is
--   untouched: authenticated SELECT-only (V1-write-dormant); no write grant/
--   policy; anon zero-grant (pfin schema-usage denial); service_role ungranted
--   (seed runs under the admin migration connection at db reset). No new table,
--   no new policy -> no new C6 exposure surface (ADR-023). The existing two-layer
--   fence (anon zero pfin grant outer; RLS users_id = auth.uid() inner) is
--   unaffected. The QA pairing is a lightweight extension of the existing 009
--   two-tenant battery (see QA HOOKS), not a new battery.
--
-- UNTOUCHED-CONFIRM (explicit, per brief): this ALTER ADDs exactly one new named
--   constraint and touches nothing else on the table.
--     - 009 `domain in ('asset','cashflow')` CHECK (auto-named
--       user_taxonomy_domain_check) — UNTOUCHED (this migration READS `domain`
--       in the new CHECK's guard; it does not alter the domain CHECK).
--     - 010 `notes text` column — UNTOUCHED.
--     - 011 `fk_user_taxonomy_tax_character` FK — UNTOUCHED.
--     - pkey / unique(users_id,domain,cat,sub_cat) / users_id FK — UNTOUCHED.
--
-- ----------------------------------------------------------------------------
-- COUPLED SEED FOLLOW-UP (Backend — flagged, NOT actioned here; Architect does
-- not edit the gitignored seed). The local cashflow seed (supabase/seed.sql)
-- currently writes the STALE class names and WILL fail this CHECK at `db reset`
-- seed-load (which runs AFTER migrations) until rewritten to the ratified enum:
--     Income      -> Revenue
--     Expenses    -> Expense
--     Distribution-> Equity            (sub_cat 'Distribution' under Equity)
--     OtherCF     -> dissolve          (-> Transfer / Trade / event-axis per Amendment 1 §1)
--     AcctSetup   -> dissolve          (-> acct_setup / corp_action / basis_adjust event-types)
--     (add Trade   with sub-cats BTO/STC/STO/BTC)
--   Transfer + Equity cashflow cats already conform. Asset-domain rows are
--   unaffected (CHECK short-circuits on domain <> 'cashflow'). This is the
--   settle-before-import imprint (ADR-031 Decision 9 one-way-door): the class
--   map settles BEFORE the incumbent transaction import backfills history.
--
-- ----------------------------------------------------------------------------
-- CONTRACT
--   pfin.user_taxonomy — new constraint user_taxonomy_cashflow_class_chk:
--       CHECK ( domain <> 'cashflow'
--               OR cat IN ('Revenue','Expense','Transfer','Equity','Trade') )
--     - Semantics: for cashflow-domain rows, the top-level Category IS the
--       accounting class and MUST be one of the 5 ratified classes; asset-domain
--       rows are unconstrained (free cat). Both `domain` and `cat` are NOT NULL
--       (009), so the CHECK has no NULL-truth edge — every row evaluates to a
--       definite TRUE/FALSE.
--     - Security-load-bearing edges: NONE new — a value-domain CHECK introduces
--       no reference, no privilege, no write path, no §10 surface, no
--       cross-tenant FK. It narrows the accepted value set for one existing
--       column on cashflow-domain rows and nothing else.
-- ============================================================================

-- Idempotent add: drop-if-exists the named constraint before adding, so re-apply
-- is clean (mirrors the 011 drop-if-exists-then-add pattern). The name is
-- explicit (not auto-generated) precisely so this guard is deterministic.
alter table pfin.user_taxonomy
  drop constraint if exists user_taxonomy_cashflow_class_chk;

alter table pfin.user_taxonomy
  add constraint user_taxonomy_cashflow_class_chk check (
    domain <> 'cashflow'
    or cat in ('Revenue', 'Expense', 'Transfer', 'Equity', 'Trade')
  );

comment on constraint user_taxonomy_cashflow_class_chk on pfin.user_taxonomy is
  'Domain-conditional cashflow-class CHECK (SELF-292 / M1; ADR-031 Decision 1 as '
  'amended by ADR-031 Amendment 1). Constrains cashflow-domain top-level cat to '
  'the ratified 5-class accounting enum (Revenue/Expense/Transfer/Equity/Trade) '
  'so the Category IS the enforced accounting class — no flow_class column, no '
  'normal_balance column (both derive from the class). Asset-domain rows are '
  'unconstrained (free cat) via the domain <> ''cashflow'' disjunct; sub_cat is '
  'free text in both domains. Clean no-backfill add — user_taxonomy is empty at '
  'migration time (V1-write-dormant; gitignored seed loads post-migration and '
  'must be rewritten to the ratified names first). Not an FK (Decision 3 family '
  'unchanged); no elevated privilege (DEFINER allowlist stays 3); no §10 surface '
  '(catalogued ledger stays 3: RT-22 + RT-26 + RT-27).';
