-- ============================================================================
-- Migration: pfin.account_trans_split — 1:many receipt-split child overlay over
--   the immutable account_trans ledger. Each child carries its own Sub-Cat + a
--   signed amount; the children of a split parent sum to the parent's amount
--   (Σ = parent.amount). The parent stays immutable (004 triple-fence untouched);
--   the split children are a MUTABLE interpretation overlay (sibling of the 023
--   1:1 annotation overlay — this is its 1:many cousin, the everyday receipt split).
-- Phase 6 Build Loop — M2.5 of the Double-Entry GL track (Linear SELF-294).
--   F/CTO-ratified 2026-07-23 (all 4 decisions): design paper
--   temp/self-294-m2.5-split-design.md; double-entry-design-v2.md L189 (M2.5 row) +
--   L137/L141 (Σ-at-commit, not per-row) + L61 (clearing pattern);
--   double-entry-transaction-column-map.md #17/#69 (Costco $220 → 3 split-children).
--
-- WHAT THIS DOES:
--   Creates pfin.account_trans_split — a MUTABLE 1:many child table on
--   pfin.account_trans. RATIFIED shape (the 4 F/CTO decisions):
--     (1) ANCHOR = α (parent-chain tenancy; NO own users_id). Tenancy resolves via
--         account_trans_id → account_trans.account_id → account_users (the 023/006/005
--         parent-FK-chain). Single tenancy source; mirrors the 023 sibling overlay.
--     (2) Σ=parent = (a) a DEFERRABLE INITIALLY DEFERRED constraint trigger: at COMMIT,
--         IF a parent has >=1 split child THEN Σ(signed children.amount) MUST equal
--         account_trans.amount; an unsplit parent (0 children) always passes. INVOKER.
--         PLUS a reconciliation VIEW (security_invoker) shaped to feed a mini T-account
--         (Dr/Cr) rendering: parent amount + Σ(children) + imbalance delta + per-line
--         debit/credit-friendly data.
--     (3) WRITE POSTURE = write-DORMANT (009 pattern): RLS + a parent-chain SELECT
--         policy + SELECT grant to authenticated; NO write policies, NO write grants
--         (deferred to the future split-UI PR). The Σ-trigger + the sub_cat fence + the
--         view still LAND now (dormant-but-ready, like 009's updated_at trigger).
--     (4) sub_cat_id = NULLABLE (uncategorized line → Unsorted/Suspense downstream);
--         PRECEDENCE = (iii) SOFT — NO cross-table 023<->split constraint; the
--         "a txn is 023-single-categorized XOR split" rule is an M4-GL READ rule,
--         documented in CONTRACT, NOT enforced here.
--
-- Numbering: 029 follows 028 (user_taxonomy cashflow-class CHECK — a different region;
--   no interaction). Depends on 004 (pfin.account_trans — the account_trans_id FK target
--   + its numeric(20,4) amount, mirrored here), 003 (pfin.account — the users_id anchor
--   the sub_cat fence chain-resolves via), 006 (account_trans rd/wr_access-JOIN RLS + the
--   account_users grant-chain this table's SELECT policy mirrors), 009 (pfin.user_taxonomy
--   — the sub_cat_id FK target), and 001 (pfin schema + fn_refresh_updated_at, reused for
--   the updated_at trigger). Does NOT depend on 028 (independent). No downstream migration
--   depends on 029 landing first. config.toml already exposes pfin to [api] (ADR-023) —
--   internet-facing the moment it is granted, so C6 exposure-gating binds (below).
--
-- ----------------------------------------------------------------------------
-- §10 3-AXIS CROSS-CHECK (Path B — reference ADR-011 Decision 4; do NOT restate the
--   catalogued numbered list. Read Decision 4 verbatim before drafting.) This migration
--   introduces ZERO catalogued §10 instances; the ledger STAYS at 3 (RT-22 + RT-26 +
--   RT-27 per ADR-011 Decision 4 — RT-27 appended third at SELF-212, F/CTO-ratified
--   2026-07-19; earlier 009–024 headers reading "stays 2" predate that move — the current
--   canonical count is 3, as 022/023 recorded).
--   (i)   Instance-numbering: RT-22 first, RT-26 second, RT-27 third — unchanged
--         (not touched).
--   (ii)  Layer-attribution: no infrastructure-credential-presence surface (RT-22 =
--         PDF-worker container), no code-layer SUPABASE_SERVICE_ROLE_KEY allowlist
--         surface (RT-26 = web-app/worker SOURCE grep fence), and no network-exposure/
--         config surface (RT-27 = the SELF-212 admission-app inbound fence) is touched.
--         This is authenticated-tier RLS/FK/trigger/view DDL only — write-DORMANT SELECT
--         path, NO service_role grant: no admission channel is opened, 008's DB-ACL
--         posture is unchanged, no surface becomes "four-layer".
--   (iii) Verbatim-vs-paraphrase: Decision 4 is linked, not restated. 029 is not the
--         canonical §10 anchor.
--   DE-CONFLATION GUARD: the Decision-3 matched-tenant sub_cat fence below is a
--   Decision-3 mechanism, NOT a §10 catalogued instance (the same separation 012 / 017 /
--   022 / 023 drew).
--
-- ----------------------------------------------------------------------------
-- DECISION 3 (cross-tenant FK-bypass family) — family delta = +1. This table carries
--   TWO reference columns; the ledger moves on ONE (verbatim mirror of the 023 split):
--     - account_trans_id → pfin.account_trans(trans_id): the SOLE tenant anchor (the
--       split child has NO own users_id; tenancy derives via account_trans_id →
--       account_trans.account_id → account_users, the parent-FK-chain). No second anchor
--       to mismatch → NOT D3. A cross-tenant attach is blocked by the parent-chain RLS
--       (the SELECT policy today; the wr_access WITH CHECK write policy when the split-UI
--       PR un-dorms writes). Same class as account_trans.account_id @ 004 /
--       account_trans_annotation.trans_id @ 023.
--     - sub_cat_id → pfin.user_taxonomy(id): the split child's owning tenant (resolved via
--       the account chain) and the taxonomy row's users_id are BOTH per-user → a GENUINE
--       matched-tenant fence (the 012 Pattern 1 shape, CHAIN-RESOLVED like 023 #10) — a PG
--       FK is existence-only and would let a user tag a split line with ANOTHER tenant's
--       Sub-Cat, the exact chain attack Decision 3 fences. Realized by
--       fn_account_trans_split_matched_sub_cat (BEFORE INSERT OR UPDATE, INVOKER,
--       NULL-safe fail-closed).
--
--   NUMBERING — PROVISIONAL; Sec pins the authoritative canonical label at joint-review.
--     Current canonical family = 11 LABELED instances / 9 DDL-realized (#3 + #4 =
--     monthly_report family, DDL-deferred to V1.3+), per the 023 header + the ADR-011 D3
--     body reconciliation. ADR-031 Decision 8 forward-flags TWO not-yet-realized labels:
--     #12 = journal_group_id (@ M2) and the M1-evt lot-match buy-reference FK (label
--     assigned at ITS migration). This split fence is the NEXT canonical label —
--     provisionally #13 — but the authoritative number is SEC'S to pin at joint-review,
--     and it MUST NOT collide with the #12 / journal_group reservation. Do NOT overclaim
--     the number (the 023 non-overclaim discipline). After 029: family = 12 LABELED /
--     10 DDL-realized (this one realized; #3 + #4 still pending V1.3+; #12 + the lot-match
--     label still UNREALIZED — authored at M2 / M1-evt).
--   ENUMERATION: no new DECISIONS.md ADR/amendment in THIS PR — the header evaluation +
--     Sec numbering sign-off at joint-review is the obligation (mirrors 015 #6 / 017 #7 /
--     022 #8+#9 / 023 #10). Sec pins the authoritative figure.
--
-- ----------------------------------------------------------------------------
-- POSTURE RATIONALE — the SECURITY DEFINER allowlist STAYS 3 (ADR-011 Decision 9:
--   fn_refresh_updated_at + fn_grant_creator_access + the still-unauthored audit-log
--   helper). THREE new objects are authored — ALL non-DEFINER:
--     - fn_account_trans_split_balance (the Σ=parent deferred constraint-trigger fn) —
--       SECURITY INVOKER, set search_path = ''. Reads account_trans_split + the parent
--       account_trans.amount under the caller's RLS; needs no elevated privilege → INVOKER
--       → not an allowlist entry.
--     - fn_account_trans_split_matched_sub_cat (the Decision-3 chain-resolved fence) —
--       SECURITY INVOKER, set search_path = '' (verbatim mirror of 023's fence posture).
--     - the account_trans_split_balance reconciliation VIEW — security_invoker = true
--       (RLS composes; the caller sees only their own splits).
--   The updated_at trigger reuses the EXISTING pfin.fn_refresh_updated_at (001, allowlist
--   entry #1) — no new entry. ZERO new SECURITY DEFINER in 029.
--
-- ----------------------------------------------------------------------------
-- DOMAIN NOTE (mirrors 012 / 022 / 023): matched-DOMAIN (user_taxonomy.domain =
--   'cashflow' — a split line is a cashflow-domain categorization) is NOT enforced in the
--   fence for V1; it is left to the app-layer Sub-Cat dropdown filter (a one-line
--   `and ut.domain = 'cashflow'` addition later if desired). The matched-TENANT check is
--   non-negotiable + DB-enforced; matched-DOMAIN is a value-correctness constraint left
--   flexible in V1.
--
-- ONE-WAY DOORS: the two ratified soft-one-way-doors (Σ-enforcement model; anchor shape α)
--   are DECIDED (F/CTO 2026-07-23) and realized here. The Σ-model imprints on the incumbent
--   import backfill + sets the app contract: split create/edit MUST be transactional (all
--   lines in one txn; edit = re-post the balanced set) — flagged for Backend at the future
--   split-UI PR. The sub_cat_id ON DELETE disposition (RESTRICT) is reversible via ALTER
--   while greenfield/empty.
--
-- ----------------------------------------------------------------------------
-- EXPOSURE / C6 RLS-COVERAGE NOTE (ADR-023 C6 standing obligation — pfin is in [api]
--   schemas, so this table is internet-facing the moment it is granted):
--   - RLS ENABLED on pfin.account_trans_split (below).
--   - POLICY PRESENT: account_trans_split_select ONLY — a parent-FK-chain rd_access-JOIN
--     (the 023 ata_select read shape) via account_trans_id → account_trans.account_id →
--     account_users. WRITE-DORMANT: NO insert/update/delete policy (writes are default-
--     denied at BOTH the ACL layer (no write grant) and the RLS layer (no write policy) —
--     strictly more locked-down than a present-but-ungranted write policy). The future
--     split-UI PR adds the wr_access-JOIN write policies + write grants together.
--   - GRANT: authenticated SELECT only (write-dormant). anon ZERO-grant (schema-usage-
--     layer denial — anon holds no USAGE on pfin per ADR-023 C2). service_role UNGRANTED
--     (no service_role split writer in V1).
--   - This table does NOT ship without the paired QA two-tenant pgTAP battery (SECURITY
--     §4.5, EXPOSURE-gating per C6). QA authors it (Architect does not edit tests/); Sec
--     sign-off gates merge. Not a vacuous green — the fixture must populate two tenants.
--
-- ----------------------------------------------------------------------------
-- CONTRACT
--   pfin.account_trans_split — MUTABLE 1:many receipt-split child overlay (M2.5 / SELF-294).
--     - id (bigint identity PK): surrogate key (this is a 1:many child — contrast 023's
--       PK=trans_id 1:1).
--     - account_trans_id (bigint NOT NULL → pfin.account_trans(trans_id) ON DELETE
--       RESTRICT): the split parent. SOLE tenant anchor (tenancy via the account chain).
--       NOT D3. ON DELETE RESTRICT is fail-loud + moot (account_trans is immutable — no
--       DELETE path exists).
--     - sub_cat_id (bigint NULL → pfin.user_taxonomy(id) ON DELETE RESTRICT): this line's
--       Sub-Cat (cashflow-domain). NULL = Unsorted-pending line (→ Suspense downstream).
--       Decision-3 matched-tenant fence (chain-resolved; provisional #13 — Sec pins).
--     - amount (numeric(20,4) NOT NULL, CHECK <> 'NaN'): the line's SIGNED amount (mirrors
--       account_trans.amount type + the 014 finite discipline — numeric(20,4) rejects
--       ±Infinity at coercion; the CHECK rejects NaN). Σ over a parent's children = the
--       parent's amount (deferred constraint below).
--     - display_order (int NULL) / note (text NULL): UI ordering + optional per-line note.
--     - created_at / updated_at (timestamptz): updated_at auto-refreshed via
--       fn_refresh_updated_at BEFORE UPDATE (dormant until writes un-dorm).
--   pfin.fn_account_trans_split_balance() — AFTER INSERT OR UPDATE OR DELETE constraint
--     trigger, DEFERRABLE INITIALLY DEFERRED (fires at COMMIT); SECURITY INVOKER;
--     set search_path=''. For each affected parent (NEW and, on re-parent/DELETE, OLD): IF
--     >=1 child THEN Σ(children.amount) MUST equal account_trans.amount, else raise;
--     0 children (unsplit) passes. NULL-safe fail-closed (missing/unreadable parent → raise).
--   pfin.fn_account_trans_split_matched_sub_cat() — BEFORE INSERT OR UPDATE WHEN
--     (new.sub_cat_id IS NOT NULL); SECURITY INVOKER; set search_path=''; NULL-safe
--     fail-closed; rejects a sub_cat_id whose user_taxonomy.users_id != the split child's
--     owning tenant (resolved via account_trans_id → account_trans → account.users_id).
--   pfin.account_trans_split_balance — security_invoker reconciliation VIEW (T-account
--     shape): per split line + windowed parent aggregates (parent_amount, parent_side,
--     children_sum, imbalance_delta, child_count, is_balanced, line_amount, line_magnitude,
--     line_side). See the view comment for the column contract (Frontend T-account render).
--   PRECEDENCE (soft, decision 4-iii): a transaction is EITHER 023-single-categorized
--     (023.sub_cat_id set, no split rows) OR split (N children here; 023.sub_cat_id moot).
--     This is an M4-GL READ rule (GL reads split children when present, else the 023
--     annotation) — NOT DB-enforced here (no cross-table constraint).
--   Security-load-bearing edges: the matched-tenant fence fails-closed + is NULL-safe +
--     INVOKER-composes-with-RLS + chain-resolves the tenant; the parent-chain SELECT policy
--     bounds reads to an account the caller holds rd_access on; the deferred Σ constraint is
--     the money-correctness invariant (INVOKER); write-dormant (SELECT-only) until the
--     split-UI PR.
-- ============================================================================

create schema if not exists pfin;
grant usage on schema pfin to authenticated;

-- ----------------------------------------------------------------------------
-- pfin.account_trans_split — the M2.5 1:many receipt-split child overlay (shape α).
-- ----------------------------------------------------------------------------
create table if not exists pfin.account_trans_split (
  id                bigint generated always as identity primary key,
  account_trans_id  bigint not null
                      references pfin.account_trans (trans_id) on delete restrict,
  sub_cat_id        bigint
                      references pfin.user_taxonomy (id) on delete restrict,
  amount            numeric(20, 4) not null
                      constraint account_trans_split_amount_finite
                        check (amount <> 'NaN'::numeric),
  display_order     integer,
  note              text,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

comment on table pfin.account_trans_split is
  'MUTABLE 1:many receipt-split child overlay on the immutable account_trans ledger (M2.5 '
  '/ SELF-294; F/CTO-ratified 2026-07-23). The 1:many cousin of the 023 1:1 annotation '
  'overlay — the everyday receipt split (Costco $220 → Groceries/Household/Auto). Each '
  'child carries its own Sub-Cat + a signed amount; a parent''s children sum to '
  'account_trans.amount (Σ=parent, deferred constraint trigger). ANCHOR α: NO own users_id '
  '— tenancy via account_trans_id → account_trans.account_id → account_users (parent-FK-'
  'chain, 023/006/005 shape). WRITE-DORMANT (009 pattern): authenticated SELECT only '
  '(parent-chain rd_access policy); write policies + write grants DEFERRED to the split-UI '
  'PR (writes default-denied at BOTH ACL + RLS). The Σ-trigger + sub_cat matched-tenant '
  'fence + reconciliation view land now (dormant-but-ready). Carries ONE Decision-3 fence: '
  'sub_cat_id → user_taxonomy = matched-tenant, chain-resolved (provisional #13 — Sec pins '
  'at joint-review; must not collide with the #12/journal_group reservation). '
  'account_trans_id is the sole anchor (NOT D3). anon zero-grant; service_role ungranted. '
  'DEFINER allowlist unchanged at 3 (Σ-trigger + fence + view all INVOKER); §10 ledger '
  'unchanged at 3 (RT-22 + RT-26 + RT-27). PRECEDENCE (soft): a txn is 023-single-'
  'categorized XOR split — an M4-GL read rule, NOT DB-enforced here.';

comment on column pfin.account_trans_split.account_trans_id is
  'FK → pfin.account_trans(trans_id) ON DELETE RESTRICT. The split parent. SOLE tenant '
  'anchor — the split child has no own users_id; tenancy derives via account_trans_id → '
  'account_trans.account_id → account_users (parent-FK-chain). NOT a cross-tenant '
  'reference → Decision 3 does not apply (same class as account_trans.account_id @ 004 / '
  'account_trans_annotation.trans_id @ 023). ON DELETE RESTRICT is fail-loud + moot '
  '(account_trans is immutable — no DELETE).';
comment on column pfin.account_trans_split.sub_cat_id is
  'FK → pfin.user_taxonomy(id) ON DELETE RESTRICT — this split line''s Sub-Cat (cashflow-'
  'domain). NULLABLE: NULL = Unsorted-pending line (→ Suspense downstream). Decision-3 '
  'matched-tenant fence, CHAIN-RESOLVED (012 Pattern 1 / 023 #10 shape) — the referenced '
  'user_taxonomy row must share the split child''s owning tenant, resolved via '
  'account_trans_id → account_trans → account.users_id (this table has no local users_id). '
  'Fenced by fn_account_trans_split_matched_sub_cat (BEFORE INSERT OR UPDATE). Provisional '
  'canonical #13 — Sec pins the authoritative label at joint-review. Matched-DOMAIN '
  '(domain=''cashflow'') is app-layer in V1.';
comment on column pfin.account_trans_split.amount is
  'Signed line amount, numeric(20,4) (mirrors account_trans.amount + the 014 finite '
  'discipline: numeric(20,4) rejects ±Infinity at coercion; the CHECK '
  'account_trans_split_amount_finite rejects NaN — `<> ''NaN''` because numeric NaN=NaN is '
  'TRUE). Σ over a parent''s children = the parent''s amount (deferred constraint trigger). '
  'Same sign as the parent (children partition the parent''s signed amount).';

alter table pfin.account_trans_split enable row level security;

-- ----------------------------------------------------------------------------
-- RLS — WRITE-DORMANT (009 pattern): parent-FK-chain SELECT policy ONLY (the 023
-- ata_select read shape). The split child has no own users_id — the policy resolves
-- tenancy via account_trans_id → account_trans.account_id → account_users, keyed on
-- rd_access. Write policies (insert/update/delete, each wr_access-JOIN WITH CHECK) are
-- DEFERRED to the split-UI PR; V1 writes are default-denied at BOTH the ACL layer (no
-- write grant) and the RLS layer (no write policy). drop-if-exists for idempotency.
-- ----------------------------------------------------------------------------
drop policy if exists account_trans_split_select on pfin.account_trans_split;
create policy account_trans_split_select on pfin.account_trans_split
  for select to authenticated
  using (exists (
    select 1
    from pfin.account_trans t
    join pfin.account_users au on au.account_id = t.account_id
    where t.trans_id = account_trans_split.account_trans_id
      and au.users_id = auth.uid()
      and au.rd_access
  ));

comment on policy account_trans_split_select on pfin.account_trans_split is
  'Parent-FK-chain SELECT policy (023/006/005 shape): rd_access-JOIN via account_trans_id '
  '→ account_trans.account_id → account_users. A user reads a split child only for a '
  'transaction whose account they hold an account_users grant with rd_access on. The split '
  'child carries no own users_id — this chain IS its tenancy. WRITE-DORMANT: no write '
  'policy in V1 (deferred to the split-UI PR).';

-- ACL-before-RLS (PR #106 gotcha): the role needs table-level GRANTs even with RLS on.
-- WRITE-DORMANT — SELECT only (no insert/update/delete grant). anon zero-grant. No
-- service_role grant (no service_role split writer in V1).
grant select on pfin.account_trans_split to authenticated;

-- No separate account_trans_id index for RLS: add one for the FK-chain JOIN + the Σ
-- aggregate scan (the parent-scoped child lookup is the hot path for both the trigger and
-- the recon view).
create index if not exists account_trans_split_account_trans_id_idx
  on pfin.account_trans_split (account_trans_id);

-- updated_at auto-refresh via the existing DEFINER allowlist entry #1 (001). Dormant in
-- V1 (write-dormant); wired for the split-UI PR. Adds NO new DEFINER entry (allowlist 3).
drop trigger if exists account_trans_split_set_updated_at on pfin.account_trans_split;
create trigger account_trans_split_set_updated_at
  before update on pfin.account_trans_split
  for each row execute function pfin.fn_refresh_updated_at();

-- ----------------------------------------------------------------------------
-- Σ = parent — decision (2)(a): DEFERRABLE INITIALLY DEFERRED constraint trigger.
-- Fires at COMMIT (so all sibling children authored in one txn are present). For each
-- affected parent (NEW on INSERT/UPDATE; OLD on DELETE; BOTH on a re-parent UPDATE): IF
-- the parent has >=1 split child THEN Σ(signed children.amount) MUST equal
-- account_trans.amount; an unsplit parent (0 children) always passes (the ≥1-child gate).
-- SECURITY INVOKER — reads the split children + the parent amount under the caller's RLS.
-- NULL-safe fail-closed. App contract (Backend, split-UI PR): split create/edit is
-- transactional (all lines in one txn; edit = re-post the balanced set).
-- ----------------------------------------------------------------------------
create or replace function pfin.fn_account_trans_split_balance()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_parent  bigint;
  v_count   integer;
  v_sum     numeric(20, 4);
  v_amount  numeric(20, 4);
begin
  -- Affected parent id(s): NEW (INSERT/UPDATE) + OLD (UPDATE re-parent / DELETE), deduped,
  -- non-null. On INSERT old.* is NULL; on DELETE new.* is NULL (both filtered out).
  for v_parent in
    select distinct p
    from (values (new.account_trans_id), (old.account_trans_id)) as v(p)
    where p is not null
  loop
    select count(*), coalesce(sum(s.amount), 0)
      into v_count, v_sum
      from pfin.account_trans_split s
     where s.account_trans_id = v_parent;

    -- ≥1-child gate: an unsplit parent (0 children) always passes.
    if v_count >= 1 then
      select t.amount into v_amount
        from pfin.account_trans t
       where t.trans_id = v_parent;
      -- NULL-safe fail-closed: parent.amount is NOT NULL; a missing/unreadable parent
      -- yields v_amount NULL → raise (never a silent skip).
      if v_amount is null or v_sum <> v_amount then
        raise exception
          'split imbalance: children of account_trans_id % sum to % but parent.amount is % (M2.5 Σ=parent deferred balance; ADR-031 / SELF-294)',
          v_parent, v_sum, v_amount;
      end if;
    end if;
  end loop;

  return null;  -- AFTER-trigger return is ignored.
end;
$$;

revoke execute on function pfin.fn_account_trans_split_balance() from public;

comment on function pfin.fn_account_trans_split_balance() is
  'Σ=parent deferred balance check for pfin.account_trans_split (M2.5 decision 2(a); '
  'SELF-294). AFTER INSERT OR UPDATE OR DELETE constraint trigger, DEFERRABLE INITIALLY '
  'DEFERRED — fires at COMMIT so all sibling children authored in one txn are present. For '
  'each affected parent (NEW + OLD on re-parent/DELETE): IF >=1 child THEN Σ(signed '
  'children.amount) MUST equal account_trans.amount, else raise; an unsplit parent (0 '
  'children) passes (the ≥1-child gate). NULL-safe fail-closed (missing/unreadable parent '
  '→ raise). SECURITY INVOKER + set search_path='''' — reads under the caller''s RLS; needs '
  'no elevated privilege → NOT a DEFINER allowlist entry (stays 3). App contract: split '
  'create/edit is transactional (all lines one txn; edit = re-post the balanced set). '
  'Contrast M2''s group-close/Suspense model for genuinely-async multi-leg journals — a '
  'receipt split is atomic, so a commit-time deferred check is the right fit.';

drop trigger if exists account_trans_split_balance on pfin.account_trans_split;
create constraint trigger account_trans_split_balance
  after insert or update or delete on pfin.account_trans_split
  deferrable initially deferred
  for each row
  execute function pfin.fn_account_trans_split_balance();

-- ----------------------------------------------------------------------------
-- Decision-3 matched-tenant fence on sub_cat_id (chain-resolved; verbatim mirror of 023
-- #10's fn_account_trans_annotation_matched_sub_cat, swapping trans_id→account_trans_id).
-- The split child has NO own users_id, so the owning tenant is resolved via
-- account_trans_id → account_trans.account_id → account.users_id, then matched against
-- user_taxonomy.users_id. BEFORE INSERT OR UPDATE (mutable table). SECURITY INVOKER.
-- ----------------------------------------------------------------------------
create or replace function pfin.fn_account_trans_split_matched_sub_cat()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  -- Trigger WHEN clause guarantees new.sub_cat_id IS NOT NULL.
  -- CHAIN-RESOLVED matched-tenant: resolve the split child's owning tenant via
  -- account_trans_id → account_trans.account_id → account.users_id, then require the
  -- referenced user_taxonomy row to share it. NULL-SAFE FAIL-CLOSED: a missing taxonomy
  -- row, a missing/unreadable transaction/account, OR a users_id mismatch → NOT EXISTS →
  -- raise (never `(subquery) <> ...`, which returns NULL on a missing row → the IF is
  -- skipped → the write would leak). LOAD-BEARING regardless of writer: the explicit
  -- ut.users_id = acc.users_id predicate is authoritative even if RLS is bypassed (a
  -- hypothetical service_role split writer); under authenticated it composes with
  -- user_taxonomy_select + the account-chain RLS as belt-and-suspenders.
  if not exists (
    select 1
    from pfin.user_taxonomy ut
    join pfin.account_trans t on t.trans_id = new.account_trans_id
    join pfin.account acc on acc.account_id = t.account_id
    where ut.id = new.sub_cat_id
      and ut.users_id = acc.users_id
  ) then
    raise exception
      'cross-tenant Sub-Cat rejected: sub_cat_id % is not a taxonomy row owned by the tenant of account_trans_id % (ADR-011 Decision 3 matched-tenant fence, chain-resolved; M2.5 / SELF-294)',
      new.sub_cat_id, new.account_trans_id;
  end if;
  return new;
end;
$$;

revoke execute on function pfin.fn_account_trans_split_matched_sub_cat() from public;

comment on function pfin.fn_account_trans_split_matched_sub_cat() is
  'BEFORE INSERT OR UPDATE matched-tenant fence on pfin.account_trans_split.sub_cat_id '
  '(ADR-011 Decision 3, CHAIN-RESOLVED; verbatim mirror of 023 #10; M2.5 / SELF-294). '
  'Rejects tagging a split line with another tenant''s Sub-Cat: the referenced '
  'user_taxonomy row must share the split child''s OWNING tenant — resolved via '
  'account_trans_id → account_trans.account_id → account.users_id (this table has NO own '
  'users_id; mirrors 017/023 chain-JOIN tenant resolution). NULL-safe fail-closed (NOT '
  'EXISTS → raise). SECURITY INVOKER + set search_path='''' — the explicit ut.users_id = '
  'acc.users_id predicate is authoritative regardless of RLS; under authenticated it '
  'composes with user_taxonomy_select (auth.uid()-scoped) + the account-chain RLS. Covers '
  'UPDATE (re-categorization), not just INSERT. Trigger (not a bare CHECK) because it '
  'subqueries + JOINs the referenced taxonomy + account chain — Decision 3 permits a '
  'trigger where PG cannot express the constraint declaratively. NOT a DEFINER allowlist '
  'entry (INVOKER); allowlist stays 3. Provisional canonical #13 — Sec pins the '
  'authoritative label at joint-review (must not collide with #12/journal_group). '
  'Matched-DOMAIN (domain=''cashflow'') is app-layer in V1.';

create trigger account_trans_split_matched_sub_cat
  before insert or update on pfin.account_trans_split
  for each row
  when (new.sub_cat_id is not null)
  execute function pfin.fn_account_trans_split_matched_sub_cat();

-- ----------------------------------------------------------------------------
-- Reconciliation VIEW — decision 2's T-account (Dr/Cr) rendering feed. security_invoker
-- so RLS composes (the caller sees only their own splits via the underlying SELECT
-- policies). Per split LINE, with windowed PARENT aggregates so Frontend can render a mini
-- T-account per parent: the account (parent) on one side, the category lines on the other,
-- plus the imbalance check. The *_side columns are a PRESENTATION hint under the everyday-
-- split convention (parent = the real account; children = the category contras) — NOT the
-- authoritative M4-GL imputation (which images the full double entry). Grouped by
-- account_trans_id. Only parents that HAVE splits appear (unsplit txns are absent).
-- ----------------------------------------------------------------------------
create or replace view pfin.account_trans_split_balance
  with (security_invoker = true) as
select
  s.account_trans_id,
  -- parent context
  t.amount                                                             as parent_amount,
  case when t.amount < 0 then 'credit'
       when t.amount > 0 then 'debit'
       else 'zero' end                                                 as parent_side,
  -- windowed parent aggregates (same for every line of a parent)
  sum(s.amount) over (partition by s.account_trans_id)                 as children_sum,
  t.amount - sum(s.amount) over (partition by s.account_trans_id)      as imbalance_delta,
  count(*) over (partition by s.account_trans_id)                      as child_count,
  (t.amount - sum(s.amount) over (partition by s.account_trans_id) = 0) as is_balanced,
  -- per-line detail (T-account line, Dr/Cr-friendly)
  s.id                                                                 as split_id,
  s.sub_cat_id,
  s.amount                                                             as line_amount,
  abs(s.amount)                                                        as line_magnitude,
  case when s.amount < 0 then 'debit'
       when s.amount > 0 then 'credit'
       else 'zero' end                                                 as line_side,
  s.display_order,
  s.note
from pfin.account_trans_split s
join pfin.account_trans t on t.trans_id = s.account_trans_id;

comment on view pfin.account_trans_split_balance is
  'Reconciliation / T-account render feed for pfin.account_trans_split (M2.5 decision 2; '
  'SELF-294). security_invoker = true → RLS composes (a caller sees only their own splits '
  'via the underlying SELECT policies). Grain = one row per split LINE, carrying windowed '
  'PARENT aggregates so Frontend renders a mini T-account per account_trans_id. Columns: '
  'account_trans_id (group key) · parent_amount + parent_side (the real account''s '
  'debit/credit side) · children_sum · imbalance_delta (parent_amount − children_sum; 0 = '
  'balanced) · child_count · is_balanced · split_id · sub_cat_id · line_amount · '
  'line_magnitude (abs) · line_side (this category line''s debit/credit side) · '
  'display_order · note. The *_side columns are a PRESENTATION hint under the everyday-'
  'split convention (parent = the real account; children = category contras — expense: '
  'parent credit / lines debit) — NOT the authoritative M4-GL double-entry imputation. '
  'Only parents that HAVE splits appear (unsplit txns are absent). imbalance_delta ≠ 0 '
  'surfaces drift (the recon to-do); under the deferred Σ constraint a committed split is '
  'always balanced, so a nonzero delta indicates an in-flight/uncommitted or admin-seeded '
  'state.';

grant select on pfin.account_trans_split_balance to authenticated;
