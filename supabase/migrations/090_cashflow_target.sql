-- ============================================================================
-- Migration: pfin.cashflow_target — per-user cash-flow planning targets
-- (annual income + monthly expense). Phase 6 Build Loop (SELF-246). Realizes a
-- member of the ADR-011 Decision 18 / Lock 14 per-domain settings store, closes
-- the PRD §2.3.2 target scalars, and discharges the DB-layer half of the
-- SECURITY SD-22 obligations. Adds no SD entry (SD-22 was assigned to this
-- surface on 2026-08-16) and adds no Decision-3 label.
--
-- WHAT THIS DOES: creates `pfin.cashflow_target`, ONE row per user carrying two
-- independent nullable scalars — `income_target_annual` and
-- `expense_target_monthly`. Owner-only RLS on all four verbs, each policy
-- carrying the 025 aal2 step-up clause. Full authenticated CRUD grant, anon
-- zero-grant, service_role ungranted. Authors NO function: the updated_at
-- refresh rides the existing 001 trigger helper.
--
-- ----------------------------------------------------------------------------
-- SHAPE, CONFIRMED AT BUILD RATHER THAN INHERITED. The shape built here is ONE
--   row per user with two named scalar columns and `unique (users_id)` — the
--   Wave-4 Gate-A ratify ("Option B with internal C"), re-affirmed at the V1.3
--   pre-flight recalibration (2026-08-22, sitting item 17).
--   ⚠ TWO ARTIFACTS RECORD A DIFFERENT KEY SHAPE, and both label it INHERITED:
--   ADR-011 Decision 18's forward note on this table and SECURITY SD-22's
--   acceptance cell each describe 2 rows per tenant keyed
--   `unique (users_id, target_kind)`, each states that the structure is the one
--   Decision 18 locked for the then-`planning_target` and was inherited at the
--   Wave-4 Gate-A ratify rather than independently specified, and each
--   instructs: confirm the key shape at build. That instruction is discharged
--   HERE, and the answer is the wide row. The two artifacts' recorded key shape
--   is superseded by this DDL; correcting them is their owners' (SECURITY is
--   Sec-owned; Decision 18's forward note takes the ADR route) and is not
--   assumed done by anything in this file.
--
-- WHY THE WIDE ROW AND NOT (users_id, target_kind): the two scalars are
--   independent facts with different periods (annual income, monthly expense)
--   and are read together by the §2.3.2 rollup. On the tall shape, "unset" and
--   "row absent" would multiply out per kind; on the wide shape the unset
--   question is answered once per column. See UNSET SEMANTICS.
--
-- WHY A TABLE AND NOT COLUMNS ON pfin.user_settings: 025 excludes
--   pfin.user_settings from the aal2 backstop as NON-NEGOTIABLE (clausing it
--   recurses into the policy that reads it), so sensitive tenant data sited
--   there could never carry the step-up fence every other tenant-owned pfin
--   table carries. Same ground 074 recorded for planning_target.
--
-- ----------------------------------------------------------------------------
-- UNSET SEMANTICS — NULL, WRITTEN BY UPSERT; NEVER A ROW DELETE (ruled at the
--   V1.3 pre-flight sitting, items 19 + 19a). A stored $0 is a target ("I intend
--   to spend nothing"); absence of a value is "I have not set one", so the two
--   are different facts and unset MUST NOT be written as zero.
--   ⚠ THE 074 / SELF-242 PRECEDENT'S VERB DOES NOT TRANSPLANT. planning_target
--   is keyed per (users_id, sub_cat_id), so one row carries one fact and unset
--   is a row DELETE. THIS table carries TWO independent scalars in one row: a
--   row DELETE would unset BOTH, so a user clearing an income target would
--   silently lose their expense target. The unset write here sets the column to
--   NULL and leaves the row.
--   READER OBLIGATION, referenced not absorbed: a row that exists with both
--   columns NULL and a row that does not exist MUST never carry different
--   meanings — both are "no targets set". Both states are reachable and they
--   arrive as different result shapes (zero rows vs one row of NULLs). The
--   obligation is honoured at the §2.3.2 reader; it is specified at SELF-250
--   AC6 and is not restated here.
--
-- SETTINGS ARE NOT AUDIT-CLASS (ADR-011 Decision 18): UPSERT-in-place on the
--   `unique (users_id)` conflict target; no edit-history rows, no versioned
--   sibling. `updated_at` refresh is the only write-time side effect.
--
-- FORWARD-COMPAT FENCE (Decision 18, restated as the standing requirement it
--   is): no JSONB column in the settings store, under any future surface. Two
--   named typed columns only; a third target acquires a third named column.
--
-- ----------------------------------------------------------------------------
-- NUMERIC FENCE — the CHECK is two-sided per column, and the reason is not
--   range-checking. `numeric(20,4)` refuses ±Infinity at coercion (typmod
--   precision overflow — measured at 014), so the non-finite value that still
--   reaches a CHECK is NaN. NaN IS storable in a constrained numeric and sorts
--   ABOVE every non-NaN numeric, so a one-sided `>= 0` ADMITS IT. The explicit
--   `<> 'NaN'::numeric` literal is the 014 / 053 idiom and is what refuses it.
--   NO UPPER BOUND IS INVENTED: a dollar target has no natural ceiling, so
--   074's `<= 100` percentage bound — which is where 074's NaN rejection
--   happens to live — is not copyable here, and the guard is written
--   explicitly instead of borrowed from a range.
--   The columns are NULLABLE, so each CHECK is `x is null or (...)`: NULL is the
--   unset representation and must pass.
--   This is the DB half of the Lock 14 mod #2 numeric-input discipline. It does
--   NOT replace the app-layer adversarial battery (Zod .strict() +
--   NaN/Inf/currency-string/overflow/scientific-notation/locale rejection),
--   which remains the first line and is owed at the write surface.
--
-- ----------------------------------------------------------------------------
-- POSTURE RATIONALE — SECURITY INVOKER (default per ADR-011 Lock 11); NOT
--   SECURITY DEFINER. This migration authors NO function of any kind: the
--   `updated_at` refresh binds the EXISTING pfin.fn_refresh_updated_at() from
--   001, and the aal2 backstop is INLINED into each policy per 025's ratified
--   inline-not-helper posture. The SECURITY DEFINER allowlist is therefore
--   UNCHANGED by this migration — read ADR-011 Decision 9 live for its contents.
--
-- ADR-011 DECISION 3 — FAMILY +0, NO LABEL CLAIMED. This table carries no
-- FK-shaped reference column. `users_id -> auth.users(id)` IS the tenant
--   anchor, not a cross-tenant reference, and Decision 3 does not apply to it —
--   the disposition Decision 3's own body records for the same column shape
--   ("`pfin.posting_prototype.users_id` is that table's own tenant anchor"),
--   and the one Decision 9's 2026-07-24 amendment records for the
--   reclassification-history table ("the history table's `trans_id` is the sole
--   anchor / NOT-D3").
--   ⚠ `053` / `063` ARE NOT THE PRECEDENT FOR THIS CLAUSE, and the citation is
--   corrected here rather than inherited. Both carry NO `users_id` at all and no
--   FK-shaped column (their own table comments say so), so they sit outside the
--   family on the NO-TENANT-DIMENSION ground — not on the anchor ground this
--   table stands on. The 053/063 citation comes from Decision 18's forward note,
--   where it attached to the recorded TALL shape's absence of an FK-shaped
--   REFERENCE column; narrowed onto the anchor itself it no longer holds.
--   Decision 18's forward note on this table anticipated exactly this outcome
--   for the recorded shape and barred any label being drafted in advance; the
--   built shape introduces no such column either, so no canonical instance is
--   added, and no label is reserved. Read Decision 3's body live for the
--   family's current shape — this file deliberately carries no tally.
--
-- aal2 STEP-UP BACKSTOP (ADR-029 / 025; C3 standing obligation). This is a new
--   sensitive tenant-owned pfin table, so it inherits the per-user-conditional
--   backstop clause on every authenticated policy — AND-ed into the read USING
--   and into the write WITH CHECK / USING. It is NOT one of 025's named
--   exclusions: it is not a global shared-read table, not a
--   service_role-only/default-deny table, and it is not the user_settings
--   substrate. The clause below is copied byte-faithfully from 025.
--
-- DELETE POLICY — SHIPS WITH ITS OWN TENANT CLAUSE, NEVER TRIMMED (SECURITY
--   §4.6 "Lock-14 settings-family DELETE-policy fence"; standing constraint on
--   this table by name). No DELETE policy in the Lock 14 family may be trimmed,
--   weakened, or omitted on the reasoning that the SELECT policy already covers
--   it: Postgres consults the SELECT policy during a DELETE only when the
--   statement reads or filters by a column, so for an unqualified
--   `delete from pfin.cashflow_target;` the DELETE policy's own USING clause is
--   the SOLE DB-layer fence. QA measured that at 074 on 2026-08-20 with a
--   complementary corrupt-the-control pair; the reasoning is confirmed false,
--   not merely unproven.
--   ⚠ The DELETE verb is granted and fenced, and it is NOT the unset mechanism
--   (see UNSET SEMANTICS). Its policy is load-bearing for any path that reaches
--   the table with a delete — the grant makes that statement shape expressible
--   independently of what the settings editor sends.
--
-- ----------------------------------------------------------------------------
-- §10 3-AXIS CROSS-CHECK (Path B — reference ADR-011 Decision 4; the catalogued
--   list is NOT restated here and no count is carried, deliberately). Decision 4
--   was read verbatim and live before drafting. This migration introduces ZERO
--   catalogued §10 instances: it is a Lock 14 user-facing-direct-DB-write
--   surface, and class membership is not a catalogued instance (ADR-042's
--   ruling for the 058 fences). It touches no infrastructure-credential-presence
--   surface, no service_role-key / code-layer allowlist surface, and no
--   network-exposure/config surface.
--     (i)   Instance-numbering: unchanged — no catalogued instance is added,
--           reordered, or renumbered.
--     (ii)  Layer-attribution: unchanged — no catalogued instance's layer is
--           re-attributed, and no surface becomes "four-layer".
--     (iii) Verbatim-vs-paraphrase: Decision 4 is linked, not restated.
--   ⚠ The §10 catalogued set and the CI-fenced RT set are DIFFERENT SETS and are
--   not reconciled here or anywhere.
--   SECURITY SD-22 scopes this surface and records that an RT is owed at build,
--   modelled on RT-23. The RT catalog is Sec-owned; that entry is routed to the
--   joint review this PR carries, not authored here.
--
-- ----------------------------------------------------------------------------
-- Numbering: 090 follows 089. Order-dependent — must run AFTER 001 (pfin schema
--   + fn_refresh_updated_at), AFTER 024 (pfin.user_settings, which the aal2
--   clause reads) and AFTER 025 (which authored the clause). No later migration
--   depends on 090 landing first.
--
-- ----------------------------------------------------------------------------
-- CONTRACT
--   pfin.cashflow_target — one row per user; `unique (users_id)` is the ON
--     CONFLICT target for the UPSERT write path.
--   income_target_annual  numeric(20,4) NULL — NULL means unset, never 0.
--   expense_target_monthly numeric(20,4) NULL — NULL means unset, never 0.
--   Both: CHECK (col is null or (col >= 0 and col <> 'NaN'::numeric)).
--   users_id — DEFAULT auth.uid(), load-bearing: it lets an authenticated INSERT
--     omit the column and still satisfy the INSERT policy's WITH CHECK. The
--     write path MUST derive the tenant from the session, never from the
--     request body (Lock 14 mod #1).
--   RLS: SELECT / INSERT / UPDATE / DELETE, each `users_id = auth.uid()` AND the
--     025 aal2 clause. Grants: authenticated only.
--   Trigger: BEFORE UPDATE FOR EACH ROW -> pfin.fn_refresh_updated_at() (001).
-- ============================================================================

create schema if not exists pfin;
grant usage on schema pfin to authenticated;

-- ----------------------------------------------------------------------------
-- TABLE
-- ----------------------------------------------------------------------------
create table if not exists pfin.cashflow_target (
  id                      bigint generated always as identity primary key,
  users_id                uuid not null default auth.uid()
                            references auth.users (id) on delete cascade,
  income_target_annual    numeric(20, 4)
                            check (income_target_annual is null
                                   or (income_target_annual >= 0
                                       and income_target_annual <> 'NaN'::numeric)),
  expense_target_monthly  numeric(20, 4)
                            check (expense_target_monthly is null
                                   or (expense_target_monthly >= 0
                                       and expense_target_monthly <> 'NaN'::numeric)),
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now(),
  unique (users_id)
);

comment on table pfin.cashflow_target is
  'Per-user cash-flow planning targets (PRD §2.3.2; ADR-011 Decision 18 / Lock 14 '
  'per-domain settings store; SELF-246). ONE row per user carrying TWO independent '
  'nullable scalars — annual income target and monthly expense target — with '
  'unique (users_id) as the UPSERT conflict target. UNSET IS NULL, WRITTEN BY '
  'UPSERT: the write sets the column to NULL and leaves the row, and a row DELETE '
  'MUST NOT be used to unset. The sibling planning_target uses a row DELETE '
  'because it is keyed per Sub-Cat and one row carries one fact; here one row '
  'carries two independent facts, so a DELETE would unset both and clearing an '
  'income target would silently discard the expense target. A stored 0 is a '
  'target ("intend to spend nothing") and is a DIFFERENT fact from unset. '
  'Row-absent and both-columns-NULL MUST be read as the same state — "no targets '
  'set" — by every reader; both are reachable and they arrive as different result '
  'shapes. Settings are not audit-class (Decision 18): UPSERT-in-place, no '
  'edit-history rows. MUTABLE, full authenticated CRUD, RLS direct-owner '
  '(users_id = auth.uid()) with the ADR-029 / 025 aal2 step-up clause on every '
  'policy, the DELETE policy included and never trimmed (SECURITY §4.6 Lock-14 '
  'settings-family DELETE-policy fence, which binds this table by name). Carries '
  'NO ADR-011 Decision 3 instance: users_id is the tenant anchor, not a '
  'cross-tenant reference, and no other FK-shaped column exists. No JSONB, per '
  'Decision 18''s forward-compat fence. anon zero-grant; service_role ungranted '
  '(the app writes as the user, under the user''s own JWT).';

comment on column pfin.cashflow_target.users_id is
  'SOLE tenant anchor (users_id = auth.uid()). DEFAULT auth.uid() so an '
  'authenticated INSERT that omits it lands owned and satisfies the INSERT '
  'policy''s WITH CHECK; FK -> auth.users(id) ON DELETE CASCADE with the tenant. '
  'NOT a cross-tenant reference (it IS the anchor) -> ADR-011 Decision 3 does not '
  'apply to this column. Lock 14 mod #1 requires the write path derive this from '
  'the session (auth.uid()), never from the request body.';

comment on column pfin.cashflow_target.income_target_annual is
  'The user''s intended ANNUAL income, in account currency. NULL = unset — the '
  'user has not stated a target; 0 is a stated target and a different fact. '
  'numeric(20,4). THE CHECK IS TWO-SIDED FOR A REASON THAT IS NOT RANGE-CHECKING: '
  'the typmod refuses ±Infinity at coercion (a numeric(20,4) field cannot hold an '
  'infinite value, measured at 014), so the non-finite value that still reaches a '
  'CHECK is NaN — which is storable in a constrained numeric and sorts ABOVE every '
  'non-NaN numeric, so a one-sided `>= 0` would ADMIT IT. The explicit '
  '`<> ''NaN''::numeric` literal (the 014 / 053 idiom) is what refuses it. There is '
  'deliberately NO upper bound: a dollar target has no natural ceiling, so '
  '074''s percentage bound is not copyable and the NaN guard is written '
  'explicitly rather than borrowed from a range. This is the DB half of the Lock '
  '14 mod #2 numeric-input discipline and does not replace the app-layer '
  'adversarial battery, which remains the first line.';

comment on column pfin.cashflow_target.expense_target_monthly is
  'The user''s intended MONTHLY expense, in account currency. NULL = unset — the '
  'user has not stated a target; 0 is a stated target and a different fact. '
  'Independent of income_target_annual: the two are set, cleared and read '
  'separately, and clearing one MUST leave the other intact. Note the differing '
  'periods — this column is MONTHLY while income_target_annual is ANNUAL; any '
  'reader comparing them MUST normalize. numeric(20,4), with the same two-sided '
  'CHECK and for the same reason: the typmod refuses ±Infinity, NaN is storable '
  'and sorts above every non-NaN numeric, so the explicit '
  '`<> ''NaN''::numeric` literal is what refuses it and a one-sided `>= 0` would '
  'not. No upper bound, deliberately.';

-- ----------------------------------------------------------------------------
-- RLS — owner-only on all four verbs. Each policy is
-- `(users_id = auth.uid()) and (<025 aal2 backstop clause>)`, the clause copied
-- byte-faithfully from 025 (COALESCE null-safe, inline — never a helper: 025
-- ratified inline because `set search_path = ''` disables SQL-function inlining,
-- so a helper would evaluate per row).
-- ----------------------------------------------------------------------------
alter table pfin.cashflow_target enable row level security;

create policy cashflow_target_select on pfin.cashflow_target
  for select to authenticated
  using (
    (users_id = auth.uid())
    and (
      coalesce((select s.mfa_policy from pfin.user_settings s where s.users_id = auth.uid()), 'none') not in ('totp', 'passkey')
      or (auth.jwt() ->> 'aal') = 'aal2'
    )
  );

create policy cashflow_target_insert on pfin.cashflow_target
  for insert to authenticated
  with check (
    (users_id = auth.uid())
    and (
      coalesce((select s.mfa_policy from pfin.user_settings s where s.users_id = auth.uid()), 'none') not in ('totp', 'passkey')
      or (auth.jwt() ->> 'aal') = 'aal2'
    )
  );

create policy cashflow_target_update on pfin.cashflow_target
  for update to authenticated
  using (
    (users_id = auth.uid())
    and (
      coalesce((select s.mfa_policy from pfin.user_settings s where s.users_id = auth.uid()), 'none') not in ('totp', 'passkey')
      or (auth.jwt() ->> 'aal') = 'aal2'
    )
  )
  with check (
    (users_id = auth.uid())
    and (
      coalesce((select s.mfa_policy from pfin.user_settings s where s.users_id = auth.uid()), 'none') not in ('totp', 'passkey')
      or (auth.jwt() ->> 'aal') = 'aal2'
    )
  );

-- The DELETE policy carries its OWN tenant clause and is never trimmed on the
-- reasoning that cashflow_target_select covers it — that reasoning is confirmed
-- false (SECURITY §4.6; QA-measured at 074, 2026-08-20). For a statement with no
-- column reference the SELECT policy is not consulted at all, and this USING
-- clause is the sole DB-layer fence.
create policy cashflow_target_delete on pfin.cashflow_target
  for delete to authenticated
  using (
    (users_id = auth.uid())
    and (
      coalesce((select s.mfa_policy from pfin.user_settings s where s.users_id = auth.uid()), 'none') not in ('totp', 'passkey')
      or (auth.jwt() ->> 'aal') = 'aal2'
    )
  );

-- ----------------------------------------------------------------------------
-- GRANTS — ACL-before-RLS (PR #106 gotcha): the role needs table-level GRANTs
-- even with RLS on. RLS filters rows; the GRANT is what lets the role reach the
-- table at all. Full V1 CRUD to authenticated. No service_role grant (008 grants
-- per table and establishes no default privileges, so service_role is ungranted
-- by construction — this line records that, it does not effect it). anon
-- zero-grant (pfin schema USAGE is authenticated-only).
-- ----------------------------------------------------------------------------
grant select, insert, update, delete on pfin.cashflow_target to authenticated;

-- No separate users_id index: the `unique (users_id)` btree already serves the
-- RLS predicate (users_id = auth.uid()) and the UPSERT conflict target. Mirrors
-- 009 / 022 / 074.

-- updated_at auto-refresh via the EXISTING fn_refresh_updated_at (001). Adds no
-- SECURITY DEFINER allowlist entry.
create trigger cashflow_target_set_updated_at
  before update on pfin.cashflow_target
  for each row execute function pfin.fn_refresh_updated_at();
