-- ============================================================================
-- Migration: pfin.journal — the M2 double-entry GROUPING parent (N real
--   account_trans legs tied with Σ=0 via a shared journal, the Escrow/compound
--   pattern) + journal_id attachment column on the 023 MUTABLE annotation overlay
--   + the Decision-3 #12 matched-tenant leg fence. Header-comes-AFTER-the-lines:
--   feed-sourced legs arrive async and are grouped POST-HOC on the overlay (no
--   stored journal_line table — grouping, not journal-lines).
-- Phase 6 Build Loop — M2 of the Double-Entry GL track (Linear SELF-295).
--   F/CTO-ratified 2026-07-24 (A2 write-dormant-balance / B-ii / C-i / D + the
--   journal_group→journal table harmonization). Design paper
--   temp/self-295-m2-journal-group-design.md. Source: ADR-031 Decision 5 (GL
--   engine / grouping) + Decision 7 (Sec M2 binding conditions, one standing
--   VETO) + Decision 8 (Decision-3 #12) + Amendment 1 item 8 (ratified naming
--   journal_id) + the 2026-07-24 table harmonization (below).
--
-- WHAT THIS DOES:
--   (1) Creates pfin.journal — the grouping parent (group identity + group_type +
--       open/closed status + description). users_id is the SOLE tenant anchor
--       (direct-owner RLS, default auth.uid(); NOT-D3). WRITE-LIVE full authenticated
--       CRUD (users author + close/reopen their own groups).
--   (2) Adds journal_id (nullable FK) to pfin.account_trans_annotation (023) — the
--       leg → group attachment. Set via the existing 023 CRUD path.
--   (3) Realizes the Decision-3 #12 matched-tenant leg fence (BEFORE INSERT OR
--       UPDATE on 023 WHEN journal_id IS NOT NULL): the leg's tenant (chain-resolved
--       trans_id → account_trans.account_id → account.users_id) must equal the
--       journal's users_id. A clone of the shipped #10 sub_cat fence, HYBRID-resolved
--       (chain-resolve the leg, direct-read the group — see DECISION 3 below).
--   (4) Inherits the 025 aal2 step-up backstop clause on pfin.journal's authenticated
--       policies (new sensitive tenant-owned pfin table — not an exclusion).
--
--   SCOPE (A2, ratified): the Σ=0-AT-CLOSE BALANCE CHECK is DEFERRED to M4-GL (it runs
--     the book-value imputation engine fn_gl_entries — the realized-gain plug + imputed
--     contras are DERIVED, not stored; testing "does the group net to zero" = running
--     that derivation, so it belongs with fn_gl_entries, NOT forked here). This
--     migration ships the grouping STRUCTURE + tenancy fences; the balance INVARIANT is
--     documented as the M4-GL obligation (see M4-GL CONTRACT below). status is a plain
--     column (C-i): user closes; a closed group may reopen same-tenant — reopen is a status
--     UPDATE on pfin.journal gated by journal_update WITH CHECK (NOT the #12 fence, which
--     fires only on account_trans_annotation leg writes; no extra DDL). Scratch/Suspense is a RUNTIME per-tenant
--     pfin.account row (fn_create_manual_account, 013) — NO DDL here (D; global = VETO).
--
-- Numbering: 033 follows 032 (M1-evt Slice B lot_match). Depends on 004 (pfin.account_
--   trans — the trans_id the fence chain-resolves + the 023 FK target), 003 (pfin.account
--   — the users_id the fence chain-resolves), 006 (account_users rd/wr_access-JOIN — the
--   023 overlay's parent-chain RLS the journal_id write path inherits), 023 (pfin.account_
--   trans_annotation — the overlay that gains journal_id), 025 (the aal2 backstop clause
--   this table inherits), and 001 (pfin schema + fn_refresh_updated_at, reused for
--   updated_at). config.toml already exposes pfin to [api] (ADR-023) — pfin.journal is
--   internet-facing the moment it is granted, so C6 exposure-gating binds (below). No
--   downstream migration depends on 033 landing first.
--
-- ----------------------------------------------------------------------------
-- TABLE HARMONIZATION (F/CTO-ratified 2026-07-24 — extends ADR-031 Amendment 1 item 8
--   scope): Amendment 1 item 8 ratified journal_id (was group_id PK + journal_group_id
--   FK column) but named the PARENT TABLE only as pfin.journal_group. F/CTO ratified
--   full harmonization on 2026-07-24: the parent table is pfin.journal (NOT
--   pfin.journal_group), so the table + its PK + the overlay FK all read journal /
--   journal_id (a journal_group table with a journal_id PK was the awkwardness this
--   resolves). A one-line ADR-031 annotation records this (doc PR, team-lead). The
--   Decision-3 instance numbering is UNCHANGED (#12, per item 8 / Decision 8).
--
-- ----------------------------------------------------------------------------
-- §10 3-AXIS CROSS-CHECK (Path B — reference ADR-011 Decision 4; do NOT restate the
--   catalogued numbered list. Read Decision 4 verbatim before drafting.) This migration
--   introduces ZERO catalogued §10 instances; the ledger STAYS at 3 (RT-22 + RT-26 +
--   RT-27 per ADR-011 Decision 4).
--   (i)   Instance-numbering: RT-22 first, RT-26 second, RT-27 third — unchanged.
--   (ii)  Layer-attribution: no infrastructure-credential-presence surface (RT-22 =
--         PDF-worker container), no code-layer SUPABASE_SERVICE_ROLE_KEY allowlist
--         surface (RT-26 = web-app/worker SOURCE grep fence), and no network-exposure/
--         config admission surface (RT-27 = the SELF-212 admission-app inbound fence) is
--         touched. This is authenticated-tier RLS/FK/trigger DDL only — full authenticated
--         CRUD, NO service_role grant: no admission channel is opened, 008's DB-ACL
--         posture is unchanged, no surface becomes "four-layer".
--   (iii) Verbatim-vs-paraphrase: Decision 4 is linked, not restated. 033 is not the
--         canonical §10 anchor.
--   DE-CONFLATION GUARD: the Decision-3 #12 matched-tenant leg fence below is a
--   Decision-3 mechanism, NOT a §10 catalogued instance (the separation 012 / 017 / 022 /
--   023 / 029 / 032 drew). The aal2 backstop clause is an ADR-029 mechanism, also NOT §10.
--
-- ----------------------------------------------------------------------------
-- DECISION 3 (cross-tenant FK-bypass family) — CANONICAL INSTANCE #12 (the ADR-031
--   Decision 8 reservation, realized here). Two reference columns considered:
--     - pfin.journal.users_id → auth.users(id): the SOLE tenant anchor (direct-owner RLS,
--       = auth.uid()). The tenant anchor ITSELF, not a cross-tenant reference → NOT D3
--       (same class as account.users_id @ 003 / linked_source.users_id @ 015).
--     - pfin.account_trans_annotation.journal_id → pfin.journal(journal_id): BOTH the
--       leg's owning tenant AND the journal's users_id are per-user; a PG FK is
--       existence-only → a user could attach their leg to ANOTHER tenant's journal (or
--       pull a foreign leg into their journal), cross-contaminating the group's Σ=0
--       balance + NAV. CANONICAL #12, matched-tenant fence.
--
--   HYBRID RESOLUTION (the one shape-difference from the #10 sub_cat clone): the leg
--     (023 annotation) has NO own users_id → its tenant is CHAIN-RESOLVED (trans_id →
--     account_trans.account_id → account.users_id, mirroring #10 / 017). The journal HAS
--     its own users_id → read DIRECTLY. The fence requires leg-tenant = journal-tenant.
--     (Contrast #10, which chain-matches user_taxonomy.users_id — also per-user with no
--     direct anchor on one side; here one side, the journal, carries a direct users_id.)
--
--   COUNT: numbered #12 per ADR-031 Decision 8 ("journal_group_id labeled #12 … now the
--     journal_id FK, numbering unchanged", Amendment 1 item 8). Realization order is
--     NON-CONTIGUOUS: 029 (M2.5 split) realized #13 and 032 (lot-match) realized #14
--     AHEAD of #12 (M2 ships after M2.5 + M1-evt), so #12 realizes LAST of the three
--     forward-flagged labels — exactly as #11 (@019) realized before #8/#9 (@022) and
--     #10 (@023). No committed label is renumbered. After 033: canonical family = 14
--     labeled / 12 DDL-realized (only #3 + #4, the monthly_report family, remain DDL-
--     deferred to V1.3+). ENUMERATION: no new DECISIONS.md ADR in THIS PR beyond the
--     one-line harmonization annotation — the in-header evaluation + Sec numbering
--     sign-off at joint-review is the obligation (mirrors 023 #10 / 029 #13 / 032 #14).
--     Sec pins the authoritative figure; NOT overclaimed here.
--
--   REALIZATION MECHANISM — ONE BEFORE INSERT OR UPDATE trigger on account_trans_
--     annotation (mutable overlay — the user attaches/detaches journal_id via the 023
--     CRUD path, so UPDATE is load-bearing, not just INSERT). A single-row CHECK cannot
--     subquery + JOIN the account chain AND the journal row, so Decision 3's "trigger
--     where PG cannot express the constraint declaratively" applies.
--
-- ----------------------------------------------------------------------------
-- POSTURE RATIONALE — SECURITY INVOKER (default per ADR-011 Lock 11); NO new SECURITY
--   DEFINER. The SECURITY DEFINER allowlist STAYS 4 (ADR-011 Decision 9 + Amendment
--   2026-07-24: fn_refresh_updated_at + fn_grant_creator_access + fn_reclass_history_
--   insert + the reserved general-audit-log helper). ONE function is authored:
--     - fn_account_trans_annotation_matched_journal (the #12 fence) — SECURITY INVOKER,
--       set search_path = ''. Reads the referenced journal + account chain under the
--       caller's RLS; the explicit j.users_id = acc.users_id predicate is authoritative
--       regardless of RLS (load-bearing if a future feed/worker path ever attaches groups
--       under service_role — ADR-031 Decision 7 M2 cond 3; today authenticated-only).
--       Needs no elevated privilege → INVOKER → not an allowlist entry.
--   The updated_at trigger reuses the EXISTING pfin.fn_refresh_updated_at (001, allowlist
--   entry #1) — no new entry. ZERO new SECURITY DEFINER in 033.
--
-- ----------------------------------------------------------------------------
-- aal2 STEP-UP BACKSTOP (ADR-029 / 025 — C3 standing obligation). pfin.journal is a NEW
--   sensitive tenant-owned pfin table reachable on the direct PostgREST API (C6), so it
--   INHERITS the per-user-conditional aal2 backstop clause: AND-ed into the SELECT USING
--   and into every write policy (INSERT WITH CHECK / UPDATE USING+WITH CHECK / DELETE
--   USING). It is NOT an exclusion (not global-shared-read; not service_role-only; not
--   the user_settings substrate itself). Without it a stolen-password aal1 session could
--   read/write the user's own journals on the direct API before TOTP step-up (Sec's C2
--   threat). The clause is inline + COALESCE null-safe (no helper) — the 025 verbatim
--   shape. Adding journal_id to 023 does NOT re-clause 023 (adding a column does not
--   touch existing policies — the MB-1 corollary); only THIS new table takes the clause.
--   Sec confirms the clause placement at joint-review.
--
-- ----------------------------------------------------------------------------
-- EXPOSURE / C6 RLS-COVERAGE NOTE (ADR-023 C6 — pfin is [api]-exposed):
--   - RLS ENABLED on pfin.journal. POLICIES: journal_select (USING) / journal_insert
--     (WITH CHECK) / journal_update (USING + WITH CHECK — no cross-tenant close/reopen,
--     no users_id reassignment, ADR-031 Decision 7 M2 cond 4) / journal_delete (USING) —
--     each users_id = auth.uid() AND the aal2 clause. WRITE-LIVE full CRUD (users author +
--     close/reopen their own groups). service_role gets NOTHING in V1 (Decision 7 M2 cond
--     5). anon zero-grant (schema-usage denial per ADR-023 C2).
--   - This table does NOT ship without the paired QA two-tenant pgTAP battery (SECURITY
--     §4.5, EXPOSURE-gating per C6). QA authors it (Architect does not edit tests/); Sec
--     sign-off gates merge. Not a vacuous green — the fixture must populate two tenants
--     each with an account + a transaction + a journal. Assertions: (a) owner CRUD on own
--     journal PASS; (b) tenant B reads 0 of tenant A's journals PASS; (c) tenant B cannot
--     INSERT/UPDATE/DELETE tenant A's journal PASS; (d) the #12 fence — a user cannot
--     attach a leg to another tenant's journal, BOTH directions (foreign journal × own
--     leg, own journal × foreign leg) → RAISE; (e) NULL journal_id detach PASS; (f) the
--     aal2 backstop — an aal1 session with mfa_policy 'totp' is blocked read+write, an
--     aal1 session with mfa_policy 'none' passes.
--
-- ----------------------------------------------------------------------------
-- M4-GL CONTRACT (the DEFERRED Σ=0-at-close balance invariant — B-ii; documented here,
--   authored at M4-GL). At group-CLOSE (status → 'closed'), fn_gl_entries enforces Σ=0
--   in BOOK VALUE over STORED facts (amount / quantity / cost_basis / transaction-time
--   price @017 — NOT a market quote; market value plays NO role — ADR-031 Decision 4:
--   the balancing double-entry is book value, market NAV is a parallel view, the gap is
--   the Unrealized-Gains equity MEMO). group_type selects the conservation law:
--     - transfer         → cash conservation: Σ(amount) = 0 over cash-bearing legs.
--     - transfer_in_kind → per-security quantity conservation: Σ(quantity) = 0 per
--                          security_id over in-kind legs (no valuation at all).
--     - compound         → book-value imputation: each leg imaged to its book-value Dr/Cr
--                          pair by fn_gl_entries (cash from amount, position at cost_basis,
--                          realized-gain plug = proceeds − cost_basis to equity — all
--                          stored facts), snapshotted deterministically at close, NEVER
--                          re-valued (a re-valued check lets a closed group silently
--                          un-balance later — Decision 7 M2 cond 7).
--   Open groups park residual in the per-tenant scratch/Suspense pfin.account row; NAV/GL
--   must include that residual in net worth (Decision 7 M2 cond 6). Whether the compound
--   close snapshot needs a storage column (closed_at / a book-value snapshot) is a B-ii
--   M4-GL decision (additive ALTER, reversible-while-empty) — NOT reserved here.
--
-- ----------------------------------------------------------------------------
-- ONE-WAY DOORS: the group_type + status enum vocabularies imprint on the incumbent
--   import once groups are populated (each group is tagged with a type selecting its
--   conservation law) — F/CTO-ratified 2026-07-24; additive-extend easy (ADR-022 CHECK-
--   widening), re-tagging existing groups is the migration cost. The #12 fence shape is
--   baked once legs attach. All reversible while greenfield/empty. The ON DELETE
--   dispositions (journal.users_id CASCADE from auth.users; account_trans_annotation.
--   journal_id has NO explicit ON DELETE — default NO ACTION, i.e. a journal cannot be
--   deleted while legs reference it, fail-loud) are reversible via ALTER while empty.
--
-- ----------------------------------------------------------------------------
-- CONTRACT
--   pfin.journal — the M2 double-entry grouping parent (SELF-295; ADR-031 Decision 5).
--     - journal_id (bigint identity PK): the group identity.
--     - users_id (uuid NOT NULL default auth.uid() → auth.users(id) ON DELETE CASCADE):
--       SOLE tenant anchor (direct-owner RLS). NOT D3.
--     - group_type (text NOT NULL, CHECK in transfer/transfer_in_kind/compound): selects
--       the M4-GL conservation law.
--     - status (text NOT NULL default 'open', CHECK in open/closed): open = residual →
--       per-tenant Suspense (no balance requirement); closed = Σ=0 must hold (M4-GL). C-i:
--       user closes; same-tenant reopen allowed (a journal UPDATE gated by journal_update
--       WITH CHECK — NOT the #12 fence, which fires only on annotation leg writes).
--     - description (text NULL): user label. (metadata jsonb is the account_trans.reason
--       home per Amendment 1 item 8 — NOT on journal; description stays.)
--     - created_at / updated_at (timestamptz NOT NULL default now()): updated_at auto-
--       refreshed via fn_refresh_updated_at BEFORE UPDATE.
--   pfin.account_trans_annotation.journal_id (bigint NULL → pfin.journal(journal_id)):
--     the leg → group attachment. NULL = unattached (default). Decision-3 CANONICAL #12,
--     matched-tenant fence (hybrid-resolved).
--   pfin.fn_account_trans_annotation_matched_journal() — BEFORE INSERT OR UPDATE WHEN
--     (new.journal_id IS NOT NULL); SECURITY INVOKER; set search_path=''; NULL-safe
--     fail-closed; rejects attaching a leg to a journal whose users_id != the leg's owning
--     tenant (leg tenant chain-resolved via trans_id → account_trans → account.users_id;
--     journal tenant read directly).
--   Security-load-bearing edges: the #12 fence fails-closed (NOT EXISTS → raise) + is
--     NULL-safe + INVOKER-composes-with-RLS + chain-resolves the leg tenant (authoritative
--     regardless of writer); journal RLS bounds every verb to the caller's own rows +
--     AND-s the aal2 backstop; UPDATE WITH CHECK blocks cross-tenant close/reopen +
--     users_id reassignment; the Σ=0-at-close balance is the DEFERRED M4-GL invariant
--     (book-value, stored facts, no market data).
-- ============================================================================

create schema if not exists pfin;
grant usage on schema pfin to authenticated;

-- ----------------------------------------------------------------------------
-- pfin.journal — the M2 double-entry grouping parent.
-- ----------------------------------------------------------------------------
create table if not exists pfin.journal (
  journal_id   bigint generated always as identity primary key,
  users_id     uuid not null default auth.uid()
                 references auth.users (id) on delete cascade,
  group_type   text not null
                 constraint journal_group_type_valid
                   check (group_type in ('transfer', 'transfer_in_kind', 'compound')),
  status       text not null default 'open'
                 constraint journal_status_valid
                   check (status in ('open', 'closed')),
  description  text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

comment on table pfin.journal is
  'M2 double-entry GROUPING parent (SELF-295; ADR-031 Decision 5 + Decision 8 + Amendment '
  '1 item 8 naming + the 2026-07-24 journal_group→journal harmonization). Ties N real '
  'account_trans legs with Σ=0 via a shared journal (grouping, NOT a stored journal_line '
  'table) — the Escrow/compound pattern; header-comes-after-the-lines (legs grouped '
  'post-hoc on the 023 overlay). users_id = SOLE tenant anchor (direct-owner RLS, default '
  'auth.uid(); NOT-D3). group_type selects the M4-GL conservation law; status open/closed '
  '(open = residual → per-tenant Suspense; closed = Σ=0 must hold at M4-GL). WRITE-LIVE '
  'full authenticated CRUD (users author + close/reopen own groups); UPDATE WITH CHECK '
  'blocks cross-tenant close/reopen (Decision 7 M2 cond 4). Inherits the 025 aal2 backstop '
  'clause (new sensitive tenant-owned table). service_role gets nothing (cond 5); anon '
  'zero-grant. Σ=0-AT-CLOSE is DEFERRED to M4-GL (A2 ratified — the book-value imputation '
  'engine fn_gl_entries runs the check; NO market data). Scratch/Suspense is a runtime '
  'per-tenant pfin.account row (013) — no DDL here (global = VETO). Carries Decision-3 #12 '
  '(the journal_id leg fence on 023). §10 stays 3; DEFINER stays 4.';

comment on column pfin.journal.users_id is
  'SOLE tenant anchor — direct-owner RLS (= auth.uid()), default auth.uid(), ON DELETE '
  'CASCADE from auth.users. The tenant anchor itself, NOT a cross-tenant reference → '
  'Decision 3 does not apply (same class as account.users_id @ 003). Code-bind from the '
  'validated session if any service_role path ever authors groups (Decision 7 M2 cond 3); '
  'authenticated-only in V1.';
comment on column pfin.journal.group_type is
  'transfer | transfer_in_kind | compound — selects the M4-GL Σ=0 conservation law '
  '(transfer → cash Σ(amount)=0; transfer_in_kind → per-security Σ(quantity)=0; compound '
  '→ book-value imputation via fn_gl_entries, snapshotted at close, never re-valued). '
  'One-way-door vocabulary (imprints on import; additive-extend per ADR-022).';
comment on column pfin.journal.status is
  'open | closed (default open). open = legs still arriving, residual parks in the '
  'per-tenant scratch/Suspense pfin.account row, no balance requirement; closed = the '
  'Σ=0 book-value check must hold (DEFERRED to M4-GL under A2). C-i: user closes; a closed '
  'group may reopen same-tenant (a journal UPDATE gated by journal_update WITH CHECK — NOT '
  'the #12 fence, which fires only on annotation leg writes). Cross-tenant close/reopen '
  'blocked by the UPDATE WITH CHECK.';
comment on column pfin.journal.description is
  'Optional user label for the group. metadata jsonb is the account_trans.reason home '
  '(Amendment 1 item 8), NOT on journal — description stays.';

alter table pfin.journal enable row level security;

-- ----------------------------------------------------------------------------
-- RLS — WRITE-LIVE full CRUD, direct-owner (users_id = auth.uid()) AND the 025 aal2
-- backstop clause (inline, COALESCE null-safe — the 025 verbatim shape). SELECT keys on
-- the read USING; writes on WITH CHECK / USING. UPDATE gates BOTH USING + WITH CHECK so a
-- group cannot be closed/reopened or re-tenanted cross-tenant (Decision 7 M2 cond 4).
-- drop-if-exists for idempotency.
-- ----------------------------------------------------------------------------
drop policy if exists journal_select on pfin.journal;
create policy journal_select on pfin.journal
  for select to authenticated
  using (
    users_id = auth.uid()
    and (
      coalesce(
        (select s.mfa_policy from pfin.user_settings s where s.users_id = auth.uid()),
        'none'
      ) not in ('totp', 'passkey')
      or (auth.jwt() ->> 'aal') = 'aal2'
    )
  );

comment on policy journal_select on pfin.journal is
  'Direct-owner SELECT (users_id = auth.uid()) AND the 025 aal2 backstop clause. A user '
  'reads only their own journals, and an aal1 session that declared mfa_policy totp/passkey '
  'is blocked until step-up (C2/C3).';

drop policy if exists journal_insert on pfin.journal;
create policy journal_insert on pfin.journal
  for insert to authenticated
  with check (
    users_id = auth.uid()
    and (
      coalesce(
        (select s.mfa_policy from pfin.user_settings s where s.users_id = auth.uid()),
        'none'
      ) not in ('totp', 'passkey')
      or (auth.jwt() ->> 'aal') = 'aal2'
    )
  );

comment on policy journal_insert on pfin.journal is
  'Direct-owner INSERT WITH CHECK (users_id = auth.uid()) AND the aal2 backstop. A user '
  'creates a journal only under their own tenant (users_id defaults to auth.uid()); the '
  'WITH CHECK blocks forging another tenant''s users_id.';

drop policy if exists journal_update on pfin.journal;
create policy journal_update on pfin.journal
  for update to authenticated
  using (
    users_id = auth.uid()
    and (
      coalesce(
        (select s.mfa_policy from pfin.user_settings s where s.users_id = auth.uid()),
        'none'
      ) not in ('totp', 'passkey')
      or (auth.jwt() ->> 'aal') = 'aal2'
    )
  )
  with check (
    users_id = auth.uid()
    and (
      coalesce(
        (select s.mfa_policy from pfin.user_settings s where s.users_id = auth.uid()),
        'none'
      ) not in ('totp', 'passkey')
      or (auth.jwt() ->> 'aal') = 'aal2'
    )
  );

comment on policy journal_update on pfin.journal is
  'Direct-owner UPDATE, USING + WITH CHECK both (users_id = auth.uid()) AND the aal2 '
  'backstop (Decision 7 M2 cond 4). The close/reopen path (status open↔closed) + '
  'description edits. Both clauses block cross-tenant close/reopen AND users_id '
  'reassignment (a row cannot be re-tenanted). C-i: reopen (status closed→open) is gated by '
  'this policy''s WITH CHECK, NOT the #12 fence (which fires only on annotation leg writes).';

drop policy if exists journal_delete on pfin.journal;
create policy journal_delete on pfin.journal
  for delete to authenticated
  using (
    users_id = auth.uid()
    and (
      coalesce(
        (select s.mfa_policy from pfin.user_settings s where s.users_id = auth.uid()),
        'none'
      ) not in ('totp', 'passkey')
      or (auth.jwt() ->> 'aal') = 'aal2'
    )
  );

comment on policy journal_delete on pfin.journal is
  'Direct-owner DELETE USING (users_id = auth.uid()) AND the aal2 backstop. A user deletes '
  'only their own journal; a journal with attached legs cannot be deleted (the 023 '
  'journal_id FK is NO ACTION — fail-loud) until the legs are detached.';

-- ACL-before-RLS (PR #106 gotcha): the role needs table-level GRANTs even with RLS on.
-- Full V1 CRUD (WRITE-LIVE grouping parent). anon zero-grant. service_role UNGRANTED
-- (Decision 7 M2 cond 5 — service_role gets nothing in V1).
grant select, insert, update, delete on pfin.journal to authenticated;

-- updated_at auto-refresh via the existing DEFINER allowlist entry #1 (001). Adds NO new
-- DEFINER entry (allowlist stays 4).
drop trigger if exists journal_set_updated_at on pfin.journal;
create trigger journal_set_updated_at
  before update on pfin.journal
  for each row execute function pfin.fn_refresh_updated_at();

-- ----------------------------------------------------------------------------
-- journal_id attachment column on the 023 MUTABLE annotation overlay (the leg → group
-- link). Nullable (NULL = unattached, the default). Set via the existing 023 CRUD path
-- (023 is already full authenticated CRUD). ON DELETE default NO ACTION (a journal cannot
-- be deleted while legs reference it — fail-loud). Adding this column does NOT touch 023's
-- existing policies (the MB-1 corollary — new columns are covered by existing policies).
-- ----------------------------------------------------------------------------
alter table pfin.account_trans_annotation
  add column if not exists journal_id bigint references pfin.journal (journal_id);

comment on column pfin.account_trans_annotation.journal_id is
  'FK → pfin.journal(journal_id) — the leg → group attachment (M2 / SELF-295). NULLABLE: '
  'NULL = unattached (default). Decision-3 CANONICAL #12: matched-tenant fence, HYBRID-'
  'resolved — the referenced journal''s users_id must equal the leg''s owning tenant, '
  'resolved via trans_id → account_trans.account_id → account.users_id (the 023 overlay '
  'has no own users_id; the journal has a direct users_id, read directly). Fenced by '
  'fn_account_trans_annotation_matched_journal (BEFORE INSERT OR UPDATE). ON DELETE NO '
  'ACTION (a journal with attached legs cannot be deleted — fail-loud).';

-- ----------------------------------------------------------------------------
-- Decision-3 CANONICAL #12 — matched-tenant leg fence on account_trans_annotation.
-- journal_id (a clone of the shipped #10 sub_cat fence, HYBRID-resolved). BEFORE INSERT
-- OR UPDATE (mutable overlay — attach/detach via the 023 CRUD path, so UPDATE is
-- load-bearing). SECURITY INVOKER. NULL-safe fail-closed (NOT EXISTS → raise).
-- ----------------------------------------------------------------------------
create or replace function pfin.fn_account_trans_annotation_matched_journal()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  -- Trigger WHEN clause guarantees new.journal_id IS NOT NULL.
  -- HYBRID matched-tenant: resolve the leg's owning tenant via trans_id →
  -- account_trans.account_id → account.users_id (the 023 overlay has no own users_id),
  -- and read the journal's users_id DIRECTLY; require them equal.
  -- NULL-SAFE FAIL-CLOSED: a missing/unreadable journal, transaction, or account, OR a
  -- users_id mismatch yields NOT EXISTS → raise. (Never `(subquery) <> ...` — that returns
  -- NULL on a missing row, the IF is skipped, and the write would leak.)
  -- LOAD-BEARING regardless of writer: the explicit j.users_id = acc.users_id predicate is
  -- authoritative even if RLS is bypassed (a hypothetical service_role grouping writer
  -- under Decision 7 M2 cond 3); under authenticated it composes with the journal RLS +
  -- the 023 account-chain RLS as belt-and-suspenders.
  if not exists (
    select 1
    from pfin.journal j
    join pfin.account_trans t on t.trans_id = new.trans_id
    join pfin.account acc on acc.account_id = t.account_id
    where j.journal_id = new.journal_id
      and j.users_id = acc.users_id
  ) then
    raise exception
      'journal attach rejected: journal_id % is not a journal owned by and visible to the tenant of trans_id % — not found, not visible under current AAL, or cross-tenant (ADR-011 Decision 3 canonical instance #12 / matched-tenant leg fence, hybrid-resolved; M2 / SELF-295)',
      new.journal_id, new.trans_id;
  end if;
  return new;
end;
$$;

revoke execute on function pfin.fn_account_trans_annotation_matched_journal() from public;

comment on function pfin.fn_account_trans_annotation_matched_journal() is
  'BEFORE INSERT OR UPDATE matched-tenant leg fence on pfin.account_trans_annotation.'
  'journal_id (ADR-011 Decision 3 canonical instance #12; ADR-031 Decision 8 / Amendment 1 '
  'item 8; M2 / SELF-295). Rejects attaching a leg to another tenant''s journal: the '
  'referenced journal''s users_id must equal the leg''s OWNING tenant — the leg tenant '
  'CHAIN-RESOLVED via trans_id → account_trans.account_id → account.users_id (the 023 '
  'overlay has no own users_id; mirrors #10 / 017 chain-JOIN resolution), the journal '
  'tenant read DIRECTLY (it carries a users_id — the one shape-difference from the #10 '
  'clone: HYBRID resolution). NULL-safe fail-closed (NOT EXISTS → raise). SECURITY INVOKER '
  '+ set search_path='''' — the explicit j.users_id = acc.users_id predicate is '
  'authoritative regardless of RLS (load-bearing if a service_role grouping writer is ever '
  'added — Decision 7 M2 cond 3); under authenticated it composes with the journal RLS + '
  'the 023 account-chain RLS. Covers UPDATE (attach/detach via the overlay), not just '
  'INSERT. Trigger (not a bare CHECK) because it subqueries + JOINs the journal + account '
  'chain — Decision 3 permits a trigger where PG cannot express the constraint '
  'declaratively. NOT a DEFINER allowlist entry (INVOKER); allowlist stays 4. Numbering '
  '#12 per Decision 8 (realized LAST of the three forward-flagged labels — #13@029 / '
  '#14@032 realized ahead; non-contiguous, like #11@019); Sec pins at joint-review.';

create trigger account_trans_annotation_matched_journal
  before insert or update on pfin.account_trans_annotation
  for each row
  when (new.journal_id is not null)
  execute function pfin.fn_account_trans_annotation_matched_journal();
