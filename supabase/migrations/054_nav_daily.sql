-- ============================================================================
-- Migration: pfin.nav_daily — precomputed per-user daily net-worth checkpoint
--   (the §2.1.2 net-worth-trend substrate). One row per (user, day) = the frozen
--   NAV computed at that day's close. Append-only audit-class: written ONLY by the
--   cron worker (service_role via TenantBoundConnection), read by the owning user.
--   Linear SELF-214 (V1.1 "Net worth full"). F/CTO-ratified 2026-08-02: Option B
--   (precomputed table) + W-1 worker model (session-impersonation reusing the
--   locked INVOKER fn_compute_nav) + uuid users_id + forward-only + numbering 054.
--   Design package temp/self214-230-design-package.md; ADR-040 (this PR).
--   apply-migration procedure applied. JOINT-REVIEW-MANDATORY (Sec veto surface):
--   tenant-scoped financial data + new RLS + immutability triggers + the worker
--   tenant-binding (AC7).
--
-- ----------------------------------------------------------------------------
-- WHY PRECOMPUTED (Option B; the 050 forward-flag): fn_compute_nav(p_as_of,
--   p_active_only) is temporally sound for active-only scoping ONLY at
--   p_as_of=current_date (050 TEMPORAL CONSTRAINT: is_active is current-state, so
--   filtering it into a past as_of retroactively rewrites history). 050 explicitly
--   forward-named this table: "§2.1.2 trajectory / a future pfin.nav_daily must
--   derive history from APPEND-ONLY PRECOMPUTED checkpoints (frozen at compute-
--   time), NOT on-the-fly fn_compute_nav(<past>, true)." nav_daily IS that store:
--   each day the worker freezes fn_compute_nav(current_date, true) into a row.
--   FORWARD-ONLY (ratified): the trajectory accumulates from first run; no
--   historical backfill (a past active-only NAV is unsound; a seeded all-accounts
--   backfill via fn_compute_nav(d,false) is a possible future decision, NOT V1.1).
--
-- ----------------------------------------------------------------------------
-- Numbering: 054 follows 053 (cpi_u_index). Depends on: 001 (pfin schema +
--   fn_refresh_updated_at, not used here), 003 (auth.users FK target + the
--   users_id=auth.uid() direct-owner RLS precedent), 024 (user_settings — the
--   direct users_id-PK RLS precedent + the mfa_policy the aal2 backstop reads),
--   025 (the aal2 step-up backstop clause this table inherits), 004 (the Lock 10
--   mod #8 append-only cross-tier trigger pattern reproduced here), 050
--   (fn_compute_nav active-only — the worker's read source; not a DDL dependency).
--   No downstream migration depends on 054. Standalone base table.
--
-- ----------------------------------------------------------------------------
-- POSTURE RATIONALE — allowlist STAYS 4 (ADR-011 Decision 9). ZERO new SECURITY
--   DEFINER. Both immutability triggers are SECURITY INVOKER (they read/write
--   nothing — just raise), exactly like 004's fences: keeping them INVOKER means
--   they do NOT touch the DEFINER allowlist. The W-1 worker model (F/CTO-ratified)
--   reuses the EXISTING INVOKER fn_compute_nav (050) via session-impersonation —
--   it authors NO new function here, so no new DEFINER entry (W-2's new-DEFINER
--   fn_compute_nav_for_user was REJECTED precisely to keep the allowlist at 4 and
--   avoid duplicating the locked valuation). set search_path = '' on both fences.
--
-- ----------------------------------------------------------------------------
-- aal2 STEP-UP BACKSTOP (C3 standing obligation / ADR-029 / 025) — INHERITED
--   (NOT excluded). nav_daily is a NEW sensitive tenant-owned pfin table with an
--   authenticated SELECT policy → it MUST carry the per-user-conditional aal2
--   backstop clause AND-ed into the SELECT USING, exactly as 025 does for the
--   current sensitive tables. NOT any of the three 025 exclusions: it is NOT
--   global shared-read (it is tenant-scoped), NOT service_role-only/default-deny
--   (it has an authenticated SELECT policy), and it is NOT user_settings itself.
--   Clause (verbatim from 025, COALESCE null-safe — no helper; gates on the
--   READER's own mfa_policy, never the row; a missing settings row reads as
--   'none' → unaffected, avoiding the lazy-provisioning null-lockout bug):
--     coalesce((select s.mfa_policy from pfin.user_settings s
--               where s.users_id = auth.uid()), 'none') not in ('totp','passkey')
--     or (auth.jwt() ->> 'aal') = 'aal2'
--   WORKER NOTE (W-1 tenant-binding — flagged for the Sec/Architect joint-review
--   of Backend's worker): the impersonation session that runs fn_compute_nav for a
--   user who DECLARED totp/passkey must present an aal2 JWT claim, else that user's
--   underlying account/holdings reads (also 025-aal2-gated) filter to zero and the
--   frozen NAV would be 0. The worker's synthetic session must claim aal2.
--
-- ----------------------------------------------------------------------------
-- §10 3-AXIS CROSS-CHECK (Path B — reference ADR-011 Decision 4; do NOT restate
--   the catalogued numbered list. Decision 4 read verbatim before drafting.) ZERO
--   catalogued §10 instances; the ledger STAYS at 3 (RT-22 + RT-26 + RT-27).
--   (i)   Instance-numbering: RT-22 first, RT-26 second, RT-27 third — untouched.
--   (ii)  Layer-attribution: nav_daily's service_role INSERT grant is a DB-LAYER
--         ACL — NOT the RT-26 code-layer SUPABASE_SERVICE_ROLE_KEY allowlist grep
--         fence, NOT the RT-22 PDF-worker container audit, NOT the RT-27 app→worker
--         admission network/config surface. The W-1 worker reaches Postgres via the
--         direct-transport service_role (TenantBoundConnection), already off the
--         RT-26 code-layer allowlist (same posture as eod_price/019 + the scheduled-
--         poll worker). Nothing becomes "four-layer."
--   (iii) Verbatim-vs-paraphrase: Decision 4 linked, not restated. 054 not the anchor.
--   NOTE (de-conflation guard): the append-only cross-tier immutability triggers are
--   a Decision-2 AUDIT-CLASS mechanism, NOT a §10 catalogued instance (same
--   separation as 004's fences). SD/RT SECURITY-doc additions (proposed SD-24 +
--   RT-28, Sec to ratify slots) are §4.4/§4.5 catalog growth, ALSO not a §10 ledger
--   change. The §10 ledger is untouched.
--
-- ----------------------------------------------------------------------------
-- DECISION 3 (cross-tenant FK-bypass family) — family UNCHANGED (+0). The only
--   FK-shaped column is users_id → auth.users(id). That is the table's OWN SOLE
--   tenant anchor under a DIRECT RLS predicate (users_id = auth.uid()), identical
--   shape to 024 user_settings.users_id / 009 user_taxonomy.users_id: there is NO
--   second anchor to mismatch, so it is NOT a matched-tenant Decision-3 instance —
--   nothing to validate. No self-FK, no INTEGER[] array, no cross-tenant reference.
--
-- ----------------------------------------------------------------------------
-- LEDGER DELTAS (confirmed): §10 catalogued instances = 3 (unchanged) · SECURITY
--   DEFINER allowlist = 4 (unchanged; W-1 authors no fn) · Decision-3 family =
--   unchanged (users_id = sole own anchor). SECURITY-doc: SD matrix +1 (proposed
--   SD-24 — medium severity, tenant-scoped, indefinite retention §4.6) + RT catalog
--   +1 (proposed RT-28, §4.5 — nav_daily cross-tenant read-leak, two-tenant fixture,
--   AC8). Sec ratifies the slot numbers + lands them in SECURITY (Sec-canonical doc).
--
-- ----------------------------------------------------------------------------
-- DECISION 2 / DECISION 14 / LOCK 10 mod #8 — append-only audit-class (verbatim
--   pattern from 004): rows immutable post-INSERT; UPDATE + DELETE blocked by a
--   row-level BEFORE trigger, TRUNCATE blocked by a statement-level BEFORE trigger
--   (row-level triggers do NOT fire on TRUNCATE) + a defensive REVOKE TRUNCATE,
--   across BOTH authenticated AND service_role (service_role bypasses RLS but NOT
--   triggers — so the trigger, not RLS-default-deny, closes the privileged-context
--   gap). A daily checkpoint is a historical fact; it is never edited or deleted.
--
-- ----------------------------------------------------------------------------
-- CONTRACT
--   pfin.nav_daily — append-only per-user daily NAV checkpoint. Columns: nav_id
--     (surrogate PK), users_id uuid (sole tenant anchor; → auth.users ON DELETE
--     CASCADE), nav_date DATE, nav_value NUMERIC (NaN + ±Infinity finiteness-
--     fenced), created_at TIMESTAMPTZ DEFAULT NOW(). UNIQUE(users_id, nav_date) —
--     one checkpoint per user per day (worker INSERT ... ON CONFLICT DO NOTHING for
--     idempotent re-runs). INSERT-only mutation (all roles); UPDATE + DELETE +
--     TRUNCATE blocked for ALL roles.
--   pfin.fn_nav_daily_block_mutation() — SECURITY INVOKER; BEFORE UPDATE OR DELETE
--     (row-level); raise (fail loud). set search_path = ''.
--   pfin.fn_nav_daily_block_truncate() — SECURITY INVOKER; BEFORE TRUNCATE
--     (statement-level); raise. set search_path = ''. + REVOKE TRUNCATE FROM PUBLIC.
--   RLS: SELECT to authenticated on users_id = auth.uid() AND the aal2 backstop;
--     INSERT/UPDATE/DELETE have NO authenticated policy (default-deny). Writes are
--     service_role-only via the INSERT grant (the W-1 cron worker).
--   Security-load-bearing edges: users_id = auth.uid() fences reads to the owner
--     (no JOIN — direct anchor); the aal2 conjunct gates a totp/passkey reader to
--     an aal2 session (never a blanket aal2 — 'none'/missing-row unaffected); the
--     immutability triggers close the privileged-context UPDATE/DELETE/TRUNCATE gap
--     for service_role; the finiteness CHECK keeps a poisoned NAV out of the trend;
--     service_role holds INSERT only (no UPDATE/DELETE grant) — the cron appends,
--     never mutates; authenticated holds SELECT only (cannot forge a checkpoint).
-- ============================================================================

create schema if not exists pfin;

-- ----------------------------------------------------------------------------
-- pfin.nav_daily — append-only per-user daily NAV checkpoint (Option B; SELF-214).
-- users_id is the sole tenant anchor (direct-owner RLS, 024 precedent). ON DELETE
-- CASCADE: a user's checkpoints are dependent data (removed with the user).
-- ----------------------------------------------------------------------------
create table if not exists pfin.nav_daily (
  nav_id      bigint generated always as identity primary key,
  users_id    uuid        not null references auth.users (id) on delete cascade,  -- sole tenant anchor (uuid, NOT integer)
  nav_date    date        not null,                                               -- the checkpoint day (compute date)
  nav_value   numeric     not null,                                               -- frozen net worth in USD (finiteness-fenced)
  created_at  timestamptz not null default now(),                                 -- IMMUTABLE post-INSERT
  constraint nav_daily_value_finite
    check (nav_value <> 'NaN'::numeric
       and nav_value <> 'Infinity'::numeric
       and nav_value <> '-Infinity'::numeric),                                    -- 014 finiteness idiom (NaN + ±Infinity; 053 N1 lesson)
  unique (users_id, nav_date)                                                     -- one checkpoint per user per day
);

comment on table pfin.nav_daily is
  'Append-only per-user daily net-worth checkpoint — the §2.1.2 net-worth-trend '
  'substrate (ADR-040; SELF-214; Option B precomputed table). One row per '
  '(users_id, nav_date) = the frozen NAV computed at that day''s close by the cron '
  'worker via fn_compute_nav(current_date, true) (050 active-only). FROZEN '
  'checkpoints, per 050''s TEMPORAL CONSTRAINT: historical NAV must NOT be '
  'recomputed on-the-fly (active-only + a past as_of rewrites history) — it is read '
  'from these rows. FORWARD-ONLY (ratified): accumulates from first run; no '
  'historical backfill in V1.1. users_id is the SOLE tenant anchor (direct-owner '
  'RLS users_id = auth.uid(), 024 precedent) → NOT a Decision-3 cross-tenant '
  'FK-bypass instance. WRITE PATH: service_role-only (the W-1 cron worker via '
  'TenantBoundConnection; INSERT ... ON CONFLICT (users_id, nav_date) DO NOTHING '
  'for idempotent re-runs) — authenticated holds SELECT only (cannot forge a '
  'checkpoint). Append-only audit-class (Decision 2 / Lock 10 mod #8): UPDATE + '
  'DELETE + TRUNCATE fenced for ALL roles (authenticated + service_role). aal2 '
  'step-up backstop INHERITED on the SELECT policy (C3 / 025). JOINT-REVIEW-'
  'MANDATORY (tenant-scoped financial data). §10 ledger stays 3; DEFINER allowlist '
  'stays 4 (W-1 authors no fn). SECURITY: proposed SD-24 + RT-28 (Sec to ratify).';

comment on column pfin.nav_daily.users_id is
  'Sole tenant anchor. uuid NOT NULL, FK → auth.users(id) ON DELETE CASCADE '
  '(NOT integer — auth.users.id is uuid; the RLS predicate is users_id = auth.uid(), '
  'uuid-typed). Direct-owner RLS (users_id = auth.uid(), no JOIN) — identical shape '
  'to 024 user_settings.users_id / 009 user_taxonomy.users_id: the tenant anchor '
  'IS the reference, no second anchor to mismatch → NOT a matched-tenant Decision-3 '
  'instance.';
comment on column pfin.nav_daily.nav_date is
  'The checkpoint day = the compute date (current_date at the worker run). Part of '
  'UNIQUE(users_id, nav_date): one checkpoint per user per day. The trend series is '
  'ORDER BY nav_date for a given user.';
comment on column pfin.nav_daily.nav_value is
  'The frozen net worth in USD for the user at nav_date, = fn_compute_nav('
  'current_date, true) (050 active-only current-state NAV) captured at compute time. '
  'Finiteness-fenced (nav_daily_value_finite: NaN AND ±Infinity rejected — any would '
  'poison the trend chart / downstream deltas; the 053 N1 lesson). Immutable once '
  'written (append-only).';
comment on column pfin.nav_daily.created_at is
  'Insert timestamp; IMMUTABLE post-INSERT (append-only audit-class). Distinct from '
  'nav_date (the checkpoint''s logical day): created_at is the wall-clock of the '
  'worker run, nav_date is the day the NAV is AS-OF.';

comment on constraint nav_daily_value_finite on pfin.nav_daily is
  'Rejects the numeric special values NaN AND +Infinity AND -Infinity on nav_value '
  '(014-pattern DB-layer defense-in-depth; a true finiteness guard — unbounded '
  'numeric admits ±Infinity, so all three are barred explicitly, per the 053 N1 '
  'correction). Any would poison the net-worth trend series and any downstream '
  'period-over-period delta. Role-agnostic table CHECK (service_role bypasses RLS '
  'but NOT CHECK); NOT NULL column, so no NULL-passes gap.';

-- ----------------------------------------------------------------------------
-- RLS — owner-only read (direct anchor + aal2 backstop); service_role-only write.
-- grant-before-RLS shape (PR #106): authenticated needs the SELECT grant even with
-- RLS enabled (RLS filters rows; the GRANT lets the role reach the table). No
-- authenticated write grant → cannot INSERT/UPDATE/DELETE regardless of policy.
-- service_role gets INSERT only (least privilege — cron appends checkpoints, never
-- updates/deletes; the immutability triggers block UPDATE/DELETE for it anyway) and
-- bypasses RLS. anon: nothing (schema USAGE denies before ACL).
-- ----------------------------------------------------------------------------
alter table pfin.nav_daily enable row level security;

-- SELECT — owner-only, direct anchor (no JOIN, 024 precedent) AND the 025 aal2
-- step-up backstop (INHERITED — nav_daily is sensitive tenant-owned, not an
-- exclusion). The aal2 conjunct gates a reader who DECLARED totp/passkey to an aal2
-- session; a 'none' / missing-settings-row reader is unaffected (coalesce ...,'none').
create policy nav_daily_select on pfin.nav_daily
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

comment on policy nav_daily_select on pfin.nav_daily is
  'SELECT: owner-only, users_id = auth.uid() (direct anchor, no JOIN — 024 '
  'precedent) AND the 025 aal2 step-up backstop (C3 standing obligation; INHERITED — '
  'nav_daily is a sensitive tenant-owned table, none of the three 025 exclusions). '
  'The aal2 conjunct requires a reader who DECLARED mfa_policy totp/passkey to '
  'present an aal2 JWT; a ''none'' / missing-settings-row reader is unaffected '
  '(coalesce(...,''none'') — avoids the lazy-provisioning null-lockout bug; gates on '
  'the READER''s own policy, never the row; never a blanket aal2). This is the ONLY '
  'authenticated policy: INSERT / UPDATE / DELETE have NO policy → default-deny, so '
  'authenticated cannot write a checkpoint. service_role writes bypass RLS.';

grant select on pfin.nav_daily to authenticated;
grant insert on pfin.nav_daily to service_role;

-- ----------------------------------------------------------------------------
-- Append-only immutability fences (Lock 10 mod #8, reproduced verbatim from 004).
-- Surface 1 — row-level UPDATE/DELETE block (the privileged-context fence).
-- ----------------------------------------------------------------------------
create or replace function pfin.fn_nav_daily_block_mutation()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  -- Fail LOUD (raise, NOT return null — return null would silently no-op the row
  -- and read as "succeeded"). Blocks UPDATE + DELETE for ALL roles; service_role
  -- bypasses RLS but NOT triggers, so this — not RLS-default-deny — closes the
  -- privileged-context immutability gap (ADR-011 Decision 2 / Lock 10 mod #8).
  raise exception
    'pfin.nav_daily is immutable (append-only checkpoint; ADR-011 Decision 2 / Lock 10). % blocked — daily NAV checkpoints are historical facts, never edited or deleted.', tg_op;
end;
$$;

revoke execute on function pfin.fn_nav_daily_block_mutation() from public;

comment on function pfin.fn_nav_daily_block_mutation() is
  'BEFORE UPDATE OR DELETE immutability fence on pfin.nav_daily (ADR-011 Decision 2 / Lock 10 mod #8; SELF-214). SECURITY INVOKER (touches nothing; not a DEFINER allowlist entry — allowlist stays 4). raise exception (fail loud). Blocks UPDATE + DELETE for ALL roles incl. service_role (which bypasses RLS but not triggers) — the privileged-context immutability fence RLS-default-deny alone cannot provide. INSERT is unblocked (the cron append path).';

create trigger nav_daily_block_mutation
  before update or delete on pfin.nav_daily
  for each row execute function pfin.fn_nav_daily_block_mutation();

-- ----------------------------------------------------------------------------
-- Surface 2 — statement-level TRUNCATE block. Row-level triggers do NOT fire on
-- TRUNCATE (Postgres runs only STATEMENT-level BEFORE TRUNCATE triggers), so a role
-- holding TRUNCATE could wipe the whole trend history without tripping Surface 1.
-- Statement-level fence (covers it regardless of grant) + a defensive REVOKE.
-- ----------------------------------------------------------------------------
create or replace function pfin.fn_nav_daily_block_truncate()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  raise exception
    'pfin.nav_daily is immutable (append-only checkpoint; ADR-011 Decision 2 / Lock 10). TRUNCATE blocked — the net-worth trend history cannot be wiped.';
end;
$$;

revoke execute on function pfin.fn_nav_daily_block_truncate() from public;

comment on function pfin.fn_nav_daily_block_truncate() is
  'BEFORE TRUNCATE (statement-level) immutability fence on pfin.nav_daily (ADR-011 Decision 2 / Lock 10 mod #8; SELF-214). SECURITY INVOKER (touches nothing; not a DEFINER allowlist entry). raise exception (fail loud). Closes the TRUNCATE bypass: row-level UPDATE/DELETE triggers do NOT fire on TRUNCATE, so this statement-level trigger fences the trend-history-wipe path for ALL roles regardless of grant state. Message distinct from the row-level fence for test-matching.';

create trigger nav_daily_block_truncate
  before truncate on pfin.nav_daily
  for each statement execute function pfin.fn_nav_daily_block_truncate();

-- Defense-in-depth: PUBLIC holds no TRUNCATE by default, but revoke explicitly so a
-- broad platform/default grant can't reintroduce it. The statement-level trigger
-- above is the regardless-of-grant guarantee.
revoke truncate on pfin.nav_daily from public;
