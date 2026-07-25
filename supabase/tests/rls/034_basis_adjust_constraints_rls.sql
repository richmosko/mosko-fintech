-- =====================================================================
-- Per-Wave battery — M3-basis (SELF-296): the basis_adjust ROW-SHAPE constraints. Two parts:
--   (1) the single-table CHECK account_trans_basis_adjust_shape on pfin.account_trans (the
--       reason-INDEPENDENT ledger shape: a basis_adjust row carries quantity=0 AND
--       security_id NOT NULL AND cost_basis NOT NULL; non-basis_adjust rows unconstrained);
--   (2) the cross-table SECURITY INVOKER trigger fn_account_trans_annotation_basis_adjust_
--       reason on pfin.account_trans_annotation (R1 reason-domain + R2 reason↔amount vs the
--       FROZEN 004 amount + R3 basis_adjust-only additive guard; BEFORE INSERT OR UPDATE
--       WHEN metadata IS NOT NULL; NULL-safe fail-closed; UPDATE path load-bearing).
--   This is a VALUE/SHAPE battery — basis_adjust is tenancy-NEUTRAL (no FK-shaped column, no
--   cross-tenant dimension; Decision-3-neutral), so there is NO two-tenant isolation axis.
--   V1-SHIP-BLOCK; JOINT-REVIEW-MANDATORY (money-flow / GL fact).
-- =====================================================================
-- BINDS TO MIGRATION: supabase/migrations/034_basis_adjust_constraints.sql
--   - CHECK account_trans_basis_adjust_shape (transaction_type <> 'basis_adjust' OR
--       (quantity = 0 AND security_id IS NOT NULL AND cost_basis IS NOT NULL)). Role-agnostic
--       table CHECK (fires under service_role ingest too); INSERT-time; 004-immutability untouched.
--   - fn_account_trans_annotation_basis_adjust_reason() + trigger account_trans_annotation_
--       basis_adjust_reason (BEFORE INSERT OR UPDATE WHEN new.metadata IS NOT NULL; INVOKER;
--       set search_path=''). R1: basis_adjust+reason ⟹ reason ∈ {depreciation,
--       return_of_capital, wash_sale}. R2: basis_adjust+reason ⟹ (return_of_capital ⟺
--       amount<>0). R3: reason present ⟹ transaction_type='basis_adjust'. NULL-safe (missing
--       fact → raise 'cannot resolve fact').
-- Prereqs on the reset stack: 001 (pfin), 003 (account + creator-grant rd=t/wr=t — the overlay
--   RLS the authenticated annotation path composes with), 004 (account_trans immutable ledger +
--   transaction_type/amount the CHECK + trigger read), 006 (account_trans rd/wr RLS + grant),
--   016/017 (pfin.asset + security_id/quantity/cost_basis + the #7 global-OR-owned fence + the
--   qty/NaN CHECKs the basis shape composes with), 023 (account_trans_annotation — the trigger
--   host), 030 (the basis_adjust transaction_type VALUE + the metadata jsonb column 034 constrains).
--
-- ┌─ ROLE MODEL (why this needs no two-tenant / no trigger-disabling device) ───────────────┐
-- │ basis_adjust is VALUE/SHAPE only — no cross-tenant dimension, so a single tenant (A) on   │
-- │ its OWN account/txns suffices. PART A (the CHECK) is role-AGNOSTIC (a table CHECK; fires  │
-- │ under any role incl. the 017 service_role ingest), so its INSERTs run PRIVILEGED          │
-- │ (role=postgres), mirroring 030 PHASE 1. PART B (the overlay trigger) runs under           │
-- │ AUTHENTICATED A on A's OWN basis_adjust txns — the REAL path (the INVOKER trigger reads    │
-- │ the frozen fact under A's RLS, exactly as in prod; 030 PHASE 2 model). CRITICAL: every    │
-- │ annotation row here carries ONLY metadata (sub_cat_id + journal_id NULL), so the 023 #10  │
-- │ sub_cat fence + the 033 #12 journal fence + the 030 trade fence all WHEN-SKIP — the 034   │
-- │ basis_adjust_reason trigger is the SOLE trigger firing. So (unlike 030's (7b), which had  │
-- │ to disable #10) the NULL-safe fail-closed test needs no trigger-disabling device: 034 is  │
-- │ already the only gate. Roles restored to postgres between phases (PR #121 discipline).    │
-- └───────────────────────────────────────────────────────────────────────────────────────┘
--
-- FAILS-CLOSED (each assertion guards a REAL violation):
--   PART A — CHECK account_trans_basis_adjust_shape (direct account_trans INSERT, postgres):
--   (A1) valid basis_adjust (qty=0, security set, cost_basis>0) PASSES -> RED if the CHECK
--        over-blocked a well-shaped basis_adjust (the settle-before-import fact would reject).
--   (A2) valid basis_adjust with NEGATIVE cost_basis (depreciation) PASSES -> RED if a >=0
--        CHECK crept in (017 has no >=0 fence; depreciation reduces basis).
--   (A3) basis_adjust with quantity <> 0 RAISES 23514 -> RED if the qty=0 clause were dropped
--        (a basis adjustment must move no shares).
--   (A4) basis_adjust with security_id NULL RAISES 23514 -> RED if the security-required clause
--        were dropped (a basis adjustment must name the adjusted asset).
--   (A5) basis_adjust with cost_basis NULL RAISES 23514 -> RED if the cost_basis-required clause
--        were dropped (a basis adjustment must carry the delta).
--   (A6) a NON-basis_adjust (standard) row of a shape that WOULD violate the basis clause
--        (security set, qty<>0, cost_basis NULL) PASSES -> RED if the CHECK wrongly applied to
--        non-basis rows (the transaction_type <> 'basis_adjust' disjunct is load-bearing).
--   PART B — trigger fn_account_trans_annotation_basis_adjust_reason (annotation, authenticated A):
--   (B1) R1/R2: depreciation on an amount=0 basis_adjust PASSES (domain + no-cash both ok).
--   (B2) R1/R2: wash_sale on an amount=0 basis_adjust PASSES (non-vacuous domain control).
--   (B3) R2: return_of_capital on an amount=0 basis_adjust RAISES (RoC requires cash;
--        the frozen amount=0 anchors it) -> RED if R2 dropped (a no-cash event relabeled RoC).
--   (B4) R1: reason='garbage' RAISES (domain) -> RED if the domain set were opened.
--   (B5) R1: reason='corporate_action' RAISES (promoted OUT to the corp_action event, Amendment
--        1 §5) -> RED if the stale 4th value lingered in the domain.
--   (B6) R2: return_of_capital on an amount<>0 basis_adjust PASSES (cash present) -> non-vacuous
--        R2 positive control (proves B3/B7 are amount-driven, not a blanket RoC/dep block).
--   (B7) R2: depreciation on an amount<>0 basis_adjust RAISES (depreciation moves no cash;
--        frozen amount<>0 anchors it) -> RED if R2 dropped (a cash event relabeled depreciation).
--   (B8) R3: a reason on a NON-basis_adjust (standard) row RAISES 'misplaced reason' -> RED if
--        the additive guard were dropped (a stray reason would confuse M4-GL).
--   (B9) R3 one-directional: metadata with only `action` (no `reason` key) on a corp_action row
--        PASSES -> RED if R3 keyed on metadata presence instead of the `reason` key (corp_action
--        metadata.action must be untouched).
--   (B10) basis_adjust with metadata but NO `reason` key PASSES (pending/Suspense — reason
--        optional) -> RED if the trigger required a reason on every basis_adjust.
--   (B11) UPDATE load-bearing: a valid (depreciation, amount=0) annotation, then UPDATE
--        metadata.reason -> 'return_of_capital' RAISES on UPDATE (R2 vs the frozen amount=0)
--        -> RED if the fence covered only INSERT (an overlay edit could break the invariant).
--   (B12) NULL-safe fail-closed: an annotation whose trans_id can't resolve a fact RAISES
--        'cannot resolve fact' (fires BEFORE the FK check) -> RED if the guard silently skipped.
--   (B13) UPDATE non-vacuous control: a valid (depreciation, amount=0) annotation UPDATED to
--        another amount=0-valid reason (wash_sale) PASSES -> proves B11 blocks on the invariant,
--        not on any UPDATE (the fence does not over-fire on a still-valid edit).
--
-- §10 / DECISION 3: §10 ledger UNCHANGED at 3 (RT-22 + RT-26 + RT-27; 034 adds ZERO catalogued
--   §10 instances — a table CHECK + one authenticated-tier INVOKER value-fence; no service_role
--   grant, no admission channel). Decision-3 family UNCHANGED (14 labeled / 12 DDL-realized):
--   both constraints are VALUE/CONSISTENCY mechanisms with NO FK-shaped reference column and NO
--   cross-tenant dimension (Decision-3-NEUTRAL). SECURITY DEFINER allowlist UNCHANGED at 4 (the
--   reason fence is INVOKER; the CHECK is not a function). This battery is the pgTAP proof the
--   shape CHECK + the reason fence catch REAL malformations; it introduces no catalogued instance.
--
-- POSTURE (SECURITY §4.5): SYNTHETIC ONLY — one fixed-UUID tenant _rls.tenant_a(); NO PII / NO
--   real account numbers / NO prod data. A owns acct-alpha + basis_adjust/standard/corp_action
--   txns; a GLOBAL asset (users_id NULL) backs every security_id (016/017 — legal for any tenant).
--   All in a rolled-back txn. (No tenant B — value/shape has no cross-tenant axis.)
--
-- ⟦WIRE-VALIDATE⟧ authored against 034's firmed contract; the authoritative run is the 001->034
--   reset stack under CI (pg_prove directory-mode, db-tests.yml, after Backend's clean-apply).
--   Locally the DB is at 027, so a net-zero rolled-back harness applies 028->034 transiently
--   (034 needs the 030 transaction_type value + metadata column; 028-033 are the intervening
--   sequence) to VERIFY green before merge; the committed file does NOT self-apply the migrations
--   (CI applies them on bring-up). Only the 034 basis_adjust_reason trigger fires on these
--   metadata-only annotations (sub_cat/journal NULL) — no trigger-disabling device needed. plan(19).
-- =====================================================================

begin;

-- shared verbs (Option C via \ir); nested case -> ../_fixtures/ per DESIGN.md.
\ir ../_fixtures/rls_verbs.psql

select plan(19);

-- Resolve the fixed tenant UUID to a psql literal while privileged (role=postgres).
select _rls.tenant_a() as ta \gset

-- ---------------------------------------------------------------------
-- Fixture (PRIVILEGED postgres — RLS + ACL bypassed; the CHECK still fires role-agnostically,
-- so the seed rows are themselves well-shaped basis_adjust facts).
--  - One tenant A owning acct-alpha (003 creator-grant seeds account_users rd=t/wr=t — the
--    overlay RLS state the authenticated PART B path composes with).
--  - ONE global asset (users_id NULL) backing every security_id (017 #7 fence: global is legal
--    for any tenant).
--  - basis_adjust rows: amount=0 rows (depreciation/wash_sale/pending/update targets) + amount<>0
--    rows (return_of_capital targets). A standard cash row + a corp_action row for R3.
-- ---------------------------------------------------------------------
insert into auth.users (id) values (:'ta');

insert into pfin.account (users_id, name, account_type, scope, tax_treatment)
  values (:'ta', 'acct-alpha', 'investment', 'household', 'taxable') returning account_id as accta \gset

insert into pfin.asset (users_id, asset_type, pricing_source, symbol, name)
  values (null, 'equity', 'market_feed', 'GBASX', 'Global Basis Sec') returning asset_id as g_asset \gset

-- basis_adjust amount=0 rows (well-shaped: qty=0, security set, cost_basis set). Distinct rows
-- for each COMMITTED annotation (annotation PK = trans_id); throws-based cases reuse a scratch row.
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, transaction_type, security_id, quantity, cost_basis)
  values (:accta, '2026-04-01', 0, 'vDEP0', 'ba dep',     'basis_adjust', :g_asset, 0, -50) returning trans_id as t_dep0 \gset
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, transaction_type, security_id, quantity, cost_basis)
  values (:accta, '2026-04-02', 0, 'vWASH0','ba wash',    'basis_adjust', :g_asset, 0, -30) returning trans_id as t_wash0 \gset
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, transaction_type, security_id, quantity, cost_basis)
  values (:accta, '2026-04-03', 0, 'vNORE', 'ba pending', 'basis_adjust', :g_asset, 0, 25)  returning trans_id as t_noreason0 \gset
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, transaction_type, security_id, quantity, cost_basis)
  values (:accta, '2026-04-04', 0, 'vUPD0', 'ba upd bad',  'basis_adjust', :g_asset, 0, 10)  returning trans_id as t_upd0 \gset
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, transaction_type, security_id, quantity, cost_basis)
  values (:accta, '2026-04-05', 0, 'vUPOK', 'ba upd ok',   'basis_adjust', :g_asset, 0, 15)  returning trans_id as t_updok0 \gset
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, transaction_type, security_id, quantity, cost_basis)
  values (:accta, '2026-04-06', 0, 'vSCR0', 'ba scratch0', 'basis_adjust', :g_asset, 0, 5)   returning trans_id as t_scratch0 \gset

-- basis_adjust amount<>0 rows (return_of_capital carries cash).
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, transaction_type, security_id, quantity, cost_basis)
  values (:accta, '2026-04-07', 100, 'vROC', 'ba roc',      'basis_adjust', :g_asset, 0, -40) returning trans_id as t_roc_nz \gset
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, transaction_type, security_id, quantity, cost_basis)
  values (:accta, '2026-04-08', 100, 'vSCRN','ba scratchNZ','basis_adjust', :g_asset, 0, -20) returning trans_id as t_scratchnz \gset

-- a standard (non-basis_adjust) cash row + a corp_action row (for R3).
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description)
  values (:accta, '2026-04-09', -50, 'vSTD', 'standard cash') returning trans_id as t_std \gset
insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, transaction_type)
  values (:accta, '2026-04-10', 0, 'vCA', 'corp action', 'corp_action') returning trans_id as t_ca \gset

-- =====================================================================
-- PART A (role=postgres) — CHECK account_trans_basis_adjust_shape (role-agnostic; direct INSERT).
-- =====================================================================
-- (A1) valid basis_adjust (qty=0, security set, cost_basis>0) PASSES.
select lives_ok(
  format($$ insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, transaction_type, security_id, quantity, cost_basis)
              values (%s, '2026-04-20', 0, 'vA1', 'A1 valid ba', 'basis_adjust', %s, 0, 75) $$, :accta, :g_asset),
  '(A1) shape CHECK: a well-shaped basis_adjust (quantity=0, security_id set, cost_basis set) INSERT PASSES'
);
-- (A2) valid basis_adjust with NEGATIVE cost_basis (depreciation reduces basis) PASSES.
select lives_ok(
  format($$ insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, transaction_type, security_id, quantity, cost_basis)
              values (%s, '2026-04-21', 0, 'vA2', 'A2 neg ba', 'basis_adjust', %s, 0, -75) $$, :accta, :g_asset),
  '(A2) shape CHECK: a basis_adjust with a NEGATIVE cost_basis (depreciation) PASSES (017 has no >=0 fence)'
);
-- (A3) basis_adjust with quantity <> 0 RAISES 23514.
select throws_ok(
  format($$ insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, transaction_type, security_id, quantity, cost_basis)
              values (%s, '2026-04-22', 0, 'vA3', 'A3 qty', 'basis_adjust', %s, 3, 75) $$, :accta, :g_asset),
  '23514', null,
  '(A3) shape CHECK fails closed: a basis_adjust with quantity<>0 RAISES check_violation (23514) — a basis adjustment moves no shares'
);
-- (A4) basis_adjust with security_id NULL RAISES 23514.
select throws_ok(
  format($$ insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, transaction_type, security_id, quantity, cost_basis)
              values (%s, '2026-04-23', 0, 'vA4', 'A4 nosec', 'basis_adjust', null, 0, 75) $$, :accta),
  '23514', null,
  '(A4) shape CHECK fails closed: a basis_adjust with security_id NULL RAISES 23514 — must name the adjusted asset'
);
-- (A5) basis_adjust with cost_basis NULL RAISES 23514.
select throws_ok(
  format($$ insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, transaction_type, security_id, quantity, cost_basis)
              values (%s, '2026-04-24', 0, 'vA5', 'A5 nocb', 'basis_adjust', %s, 0, null) $$, :accta, :g_asset),
  '23514', null,
  '(A5) shape CHECK fails closed: a basis_adjust with cost_basis NULL RAISES 23514 — must carry the delta'
);
-- (A6) a NON-basis_adjust (standard) row of a shape that WOULD violate the basis clause
--      (security set, quantity<>0, cost_basis NULL) PASSES — the transaction_type<>'basis_adjust'
--      disjunct is load-bearing (the CHECK must NOT constrain non-basis rows).
select lives_ok(
  format($$ insert into pfin.account_trans (account_id, transaction_date, amount, vendor, description, transaction_type, security_id, quantity, cost_basis)
              values (%s, '2026-04-25', -100, 'vA6', 'A6 std', 'standard', %s, 5, null) $$, :accta, :g_asset),
  '(A6) shape CHECK is basis_adjust-scoped: a STANDARD row (security set, quantity<>0, cost_basis NULL — would violate if it were basis_adjust) PASSES (the transaction_type<>basis_adjust disjunct)'
);

-- =====================================================================
-- PART B (authenticated A) — reason fence (R1 domain + R2 reason↔amount + R3 additive + UPDATE
--   + NULL-safe). A annotates its OWN basis_adjust txns; metadata-only (sub_cat/journal NULL) so
--   the 034 basis_adjust_reason trigger is the SOLE trigger firing.
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);

-- (B1) R1+R2: depreciation on an amount=0 basis_adjust PASSES.
select lives_ok(
  format($$ insert into pfin.account_trans_annotation (trans_id, metadata) values (%s, '{"reason":"depreciation"}'::jsonb) $$, :t_dep0),
  '(B1) reason PASS: depreciation on an amount=0 basis_adjust (domain ok + no-cash consistent) ACCEPTED'
);
-- (B2) R1+R2: wash_sale on an amount=0 basis_adjust PASSES (non-vacuous domain control).
select lives_ok(
  format($$ insert into pfin.account_trans_annotation (trans_id, metadata) values (%s, '{"reason":"wash_sale"}'::jsonb) $$, :t_wash0),
  '(B2) reason PASS: wash_sale on an amount=0 basis_adjust ACCEPTED (non-vacuous domain control)'
);
-- (B3) R2: return_of_capital on an amount=0 basis_adjust RAISES (RoC requires cash).
select throws_like(
  format($$ insert into pfin.account_trans_annotation (trans_id, metadata) values (%s, '{"reason":"return_of_capital"}'::jsonb) $$, :t_scratch0),
  '%amount mismatch%',
  '(B3) R2 fails closed: return_of_capital on an amount=0 basis_adjust RAISES reason↔amount mismatch (RoC requires amount<>0; the frozen amount anchors it)'
);
-- (B4) R1: reason='garbage' RAISES (domain).
select throws_like(
  format($$ insert into pfin.account_trans_annotation (trans_id, metadata) values (%s, '{"reason":"garbage"}'::jsonb) $$, :t_scratch0),
  '%not in {depreciation%',
  '(B4) R1 fails closed: reason=''garbage'' RAISES domain violation (reason ∉ {depreciation, return_of_capital, wash_sale})'
);
-- (B5) R1: reason='corporate_action' RAISES (promoted OUT to the corp_action event, Amendment 1 §5).
select throws_like(
  format($$ insert into pfin.account_trans_annotation (trans_id, metadata) values (%s, '{"reason":"corporate_action"}'::jsonb) $$, :t_scratch0),
  '%not in {depreciation%',
  '(B5) R1 fails closed: reason=''corporate_action'' RAISES — promoted OUT of the reason set (it is the corp_action event type, not a reason)'
);
-- (B6) R2: return_of_capital on an amount<>0 basis_adjust PASSES (non-vacuous R2 positive control).
select lives_ok(
  format($$ insert into pfin.account_trans_annotation (trans_id, metadata) values (%s, '{"reason":"return_of_capital"}'::jsonb) $$, :t_roc_nz),
  '(B6) R2 PASS: return_of_capital on an amount<>0 basis_adjust ACCEPTED (cash present — proves B3/B7 are amount-driven, not a blanket block)'
);
-- (B7) R2: depreciation on an amount<>0 basis_adjust RAISES (depreciation moves no cash).
select throws_like(
  format($$ insert into pfin.account_trans_annotation (trans_id, metadata) values (%s, '{"reason":"depreciation"}'::jsonb) $$, :t_scratchnz),
  '%amount mismatch%',
  '(B7) R2 fails closed: depreciation on an amount<>0 basis_adjust RAISES reason↔amount mismatch (depreciation requires amount=0)'
);
-- (B8) R3: a reason on a NON-basis_adjust (standard) row RAISES 'misplaced reason'.
select throws_like(
  format($$ insert into pfin.account_trans_annotation (trans_id, metadata) values (%s, '{"reason":"depreciation"}'::jsonb) $$, :t_std),
  '%misplaced reason%',
  '(B8) R3 fails closed: a metadata.reason on a NON-basis_adjust (standard) row RAISES ''misplaced reason'' (reason is a basis_adjust-only concept)'
);
-- (B9) R3 one-directional: metadata with only `action` (no `reason` key) on a corp_action row PASSES.
select lives_ok(
  format($$ insert into pfin.account_trans_annotation (trans_id, metadata) values (%s, '{"action":"split"}'::jsonb) $$, :t_ca),
  '(B9) R3 one-directional: metadata with only `action` (no `reason` key) on a corp_action row PASSES — R3 keys on the `reason` key, so corp_action metadata.action is untouched'
);
-- (B10) basis_adjust with metadata but NO `reason` key PASSES (pending/Suspense — reason optional).
select lives_ok(
  format($$ insert into pfin.account_trans_annotation (trans_id, metadata) values (%s, '{"note":"pending"}'::jsonb) $$, :t_noreason0),
  '(B10) reason optional: a basis_adjust annotation with metadata but NO `reason` key PASSES (pending/Suspense — a basis_adjust may carry no reason yet)'
);
-- (B11) UPDATE load-bearing: valid (depreciation, amount=0), then UPDATE reason -> return_of_capital RAISES.
insert into pfin.account_trans_annotation (trans_id, metadata) values (:t_upd0, '{"reason":"depreciation"}'::jsonb);
select throws_like(
  format($$ update pfin.account_trans_annotation set metadata = '{"reason":"return_of_capital"}'::jsonb where trans_id = %s $$, :t_upd0),
  '%amount mismatch%',
  '(B11) UPDATE load-bearing: re-labeling a depreciation annotation to return_of_capital on a frozen amount=0 row RAISES on UPDATE (the fence covers UPDATE, not only INSERT; re-validates vs the frozen amount)'
);
-- (B12) NULL-safe fail-closed: an unresolvable trans_id RAISES 'cannot resolve fact' (before the FK check).
--   Only the 034 trigger fires here (metadata set; sub_cat/journal NULL) — no #10-style masking.
select throws_ok(
  $$ insert into pfin.account_trans_annotation (trans_id, metadata) values (9999999, '{"reason":"depreciation"}'::jsonb) $$,
  'P0001', null,
  '(B12) NULL-safe fail-closed: an annotation whose trans_id cannot resolve a fact RAISES the fence (fires BEFORE the FK check; the frozen fact is the integrity anchor). SQLSTATE-match (P0001, distinct from RLS 42501) so the SELF-298 message softening cannot RED this.'
);
-- (B13) UPDATE non-vacuous control: valid depreciation (amount=0), UPDATE reason -> wash_sale (also amount=0-valid) PASSES.
insert into pfin.account_trans_annotation (trans_id, metadata) values (:t_updok0, '{"reason":"depreciation"}'::jsonb);
select lives_ok(
  format($$ update pfin.account_trans_annotation set metadata = '{"reason":"wash_sale"}'::jsonb where trans_id = %s $$, :t_updok0),
  '(B13) UPDATE control: re-labeling depreciation -> wash_sale on an amount=0 row PASSES — the fence re-validates but does not over-fire on a still-valid edit (proves B11 blocks on the invariant)'
);

select set_config('role', 'postgres', true);

select * from finish();
rollback;
