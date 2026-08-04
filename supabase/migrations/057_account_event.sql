-- ============================================================================
-- 057_account_event.sql — pfin.account_event: the audit surface for account
--   open/closed state transitions (ADR-042 Decision 5 + 5a).
--
-- Numbering: 057 follows 056. MUST precede 058 — 058's close gate writes a row
--   here on every closed_at transition, so the table has to exist first.
--
-- ----------------------------------------------------------------------------
-- WHY A SIBLING TABLE AND NOT COLUMNS ON pfin.account (ADR-011 Decision 2):
--   the TRANSITION is audit-class; pfin.account itself is NOT and must not
--   become so (updateAttributes is a correct mutable path). Precedents:
--   015 linked_source_state_history, 031 reclass_history — append-only siblings
--   over a mutable entity.
--
-- NAMED FOR THE GENERAL CLASS, NOT `closure_history`. event_type's CHECK admits
--   only the closure values today and widens by a one-line ALTER (the 030
--   transaction_type CHECK-widen precedent under the ADR-022 code-coupled->CHECK
--   rule). A currency restatement is not a closure; a second near-identical
--   audit table later would duplicate RLS + grants + immutability triggers AND
--   add a Decision-3 instance.
--
--   *** WIDENING event_type IS SEC-JOINT-REVIEW-MANDATORY, NOT A ROUTINE ALTER. ***
--   Every downstream posture here was calibrated FOR CLOSURE EVENTS: the SD tier,
--   the read posture (SELECT policy + grant + the 025 aal2 conjunct), and
--   `indefinite` retention per SECURITY §4.6. A widening silently re-scopes all
--   three, and the SD tier rates WHAT THE CHECK ADMITS, not what the table is
--   named. Convention precedent: ADR-016's webhook-allowlist annotation.
--   A widening may also require NEW TYPED COLUMNS (see the column rule below) —
--   each its own review surface; an FK-shaped one extends the Decision-3 family.
--
-- ----------------------------------------------------------------------------
-- EVERY COLUMN HAS A NAMED WRITER, AND THE CRITERION IS NOT "HAS A WRITER"
--   (Sec, at the 057 concurrence — the criterion that keeps `actor` would kill
--   it under the weaker test):
--
--     >> Does the column ever take MORE THAN ONE VALUE across the writers that
--        exist? <<
--
--   `actor` YES — two values across the table's history: `user:<uid>` and the
--     migration identity. Remediation is one-time, so the VARIETY stops growing;
--     the DISTINCTION is permanent. A transient writer leaves a permanent record.
--   `matched_on` / `decided` NO — ZERO distinguishing values, ever. They were
--     provenance for the sync-path reactivation writer, and the ratified model
--     removed that writer (042 must not clear closed_at; sync writes are refused
--     by 058's transfer-in fence and record to linked_source_sync_audit). Every
--     row would carry the same NULL or the same constant. DROPPED, with
--     `provider_event_id` (no provider event drives a closure) and
--     `linked_source_id` (no system path resolves tenant via a connection —
--     so Decision-3 instance #17 IS NEVER CREATED; the family stays 16/13).
--
--   Do NOT re-add a column on the strength of a hypothetical writer. An unused
--   fenced column is an attractive nuisance: it exists, it looks authoritative,
--   someone eventually populates it BECAUSE IT IS THERE — at which point the
--   fence validates tenant-match but not MEANING.
--
-- NO FREE TEXT ANYWHERE ON THIS SURFACE (F/CTO-ratified 2026-08-03). reason_code
--   is a closed vocabulary; there is NO `other` + "please specify" companion
--   field — an escape-hatch free-text column reintroduces unredactable PII while
--   PRESENTING as a closed vocabulary. This table is audit-class immutable and
--   retained indefinitely, so ADMISSION IS THE ONLY CONTROL: there is no
--   redaction path after the fact, for anyone, including the row's own tenant.
--
-- ----------------------------------------------------------------------------
-- POSTURE RATIONALE
--   No SECURITY DEFINER anywhere. The #16 fence is a SECURITY INVOKER trigger
--   (set search_path = ''), as are both immutability fences. DEFINER allowlist
--   STAYS 4 (3 authored). Writers: the user's own close/reopen (a session write
--   under RLS — NOT an ADR-011 Decision 1 privileged-context surface, so clause
--   (d) does not apply to this table) and the one-time remediation, which runs
--   as the migration role and is RLS-exempt — which is exactly why #16 is
--   load-bearing rather than decorative.
-- ============================================================================

create schema if not exists pfin;

create table if not exists pfin.account_event (
  event_id       bigint generated always as identity primary key,
  users_id       uuid not null default auth.uid()
                   references auth.users (id) on delete cascade,
  account_id     bigint not null
                   references pfin.account (account_id) on delete restrict,
  event_type     text not null
                   check (event_type in ('closed', 'reopened')),
  -- VOCABULARY: PM-proposed, F/CTO-ratified 2026-08-03 (ADR-042 Amendment 1 A6).
  --   'closed' RENAMED to 'no_longer_used'. The sense is grounded in PRD §2.4.2
  --   and worth keeping; the NAME collided with event_type='closed', and a value
  --   that reads as a tautology against its own event_type becomes the
  --   safe-looking dumping ground — worse than 'other', because it looks
  --   informative.
  --   'institution_closed' is NEW: bank merges and product discontinuations are
  --   common, are NOT the user's decision, and were previously unrepresentable,
  --   so they landed in 'other' or were misfiled as a user-initiated closure.
  --
  -- ⚠ 'other' IS A BARE VOCABULARY MEMBER. NO COMPANION FREE-TEXT FIELD — no
  --   "please specify", not here, not in the UI, nowhere on this surface
  --   (F/CTO-ratified; ADR-042 Decision 5). An escape-hatch text box
  --   reintroduces the unredactable-PII problem while LOOKING like a closed
  --   vocabulary, and this table is append-only with no redaction path for
  --   anyone, including the row's own tenant. Stated here because a "please
  --   specify" box is how anyone would build an Other option by default, and
  --   THE PROHIBITION IS INVISIBLE FROM THE CHECK.
  --
  -- ⚠ 'other' IS NOT A WEAKENING. Requiredness below is MANDATORY, and 'other'
  --   is what makes mandatory safe: without it, mandatory FORCES
  --   misclassification, and this ADR ruled wrong classification is worse than
  --   absent classification on a row that can never be corrected.
  --   A HIGH 'other' RATE IS EVIDENCE THE VOCABULARY IS WRONG, NOT THAT THE
  --   MANDATE IS WRONG — revisit the values; do not relax the requirement, or
  --   the first signal of a bad taxonomy is lost along with the data.
  --
  -- ONE AXIS, PERMANENTLY (Amendment 1 A7; F/CTO-ratified). These values mix
  --   "why the account ended" with "where the value went", and that conflation
  --   is DECIDED, not pending. No `disposition` column, now or later — one
  --   added later is NULL for every prior row, unbackfillable. Do NOT reopen
  --   this if account_trans later gains transfer-pairing: the rows written
  --   before that change still cannot carry the distinction.
  reason_code    text
                   check (reason_code in
                     ('no_longer_used', 'sold', 'transferred_out',
                      'duplicate', 'institution_closed', 'other')),
  -- ENUMERATED, NOT OPEN-ENDED (Sec, 057 review). `system:[a-z_]+` would let a
  -- NEW SYSTEM WRITER APPEAR SILENTLY — and the whole matched_on/decided removal
  -- rests on there being exactly one non-session writer. An open pattern admits a
  -- second without firing anything. Enumerated, a new system identity FAILS THIS
  -- CHECK and forces the review that would re-examine the column set.
  actor          text not null
                   check (
                     actor ~ '^user:[0-9a-f-]{36}$'
                     or actor in ('system:remediation')
                   ),
  -- NULLABLE BY DECISION, requiredness enforced per event type below (Sec flag,
  -- ADR-042 Amendment 1 A5). A closure takes its date from the DATA
  -- (new.closed_at); a REOPEN has no carrier — the reopen path is a bare
  -- `closed_at = null` UPDATE with nowhere to say WHEN. The rejected fix was to
  -- default it to current_date. That is a GUESSED DATE, permanent and
  -- unredactable, in the same function that already prohibits a guessed
  -- reason_code — and worse, a real same-day reopen and an unknown-date reopen
  -- would produce BYTE-IDENTICAL rows. Not lossy: INDISTINGUISHABLE, forever,
  -- because this table has no redaction path.
  --
  -- This is ADR-011 D4's third bullet (Lock 15 catch on Lock 9) INVERTED, which
  -- is the harder shape: Lock 9 lost insertion-time by OMISSION, so the gap was
  -- visible. Defaulting here would lose the distinction BY VALUE — both columns
  -- present, effective_date === created_at::date on every reopen row, and the
  -- orthogonality collapsed while nothing looks missing.
  -- AN OMISSION ANNOUNCES ITSELF; A COLLAPSE LOOKS LIKE DATA.
  effective_date date,
  created_at     timestamptz not null default now(),

  -- Requiredness is PER EVENT TYPE, so it is a CHECK and NOT a column-level
  -- NOT NULL — a global NOT NULL would fail for the types that do not need it.
  constraint account_event_reason_required
    check (event_type <> 'closed' or reason_code is not null),

  -- SAME SHAPE, SAME REASON, deliberately mirroring the constraint above rather
  -- than inventing a mechanism: the table already had this pattern for exactly
  -- this problem. A closure must carry its date; a reopen may leave it NULL,
  -- and NULL means "not recorded" rather than "today".
  constraint account_event_effective_date_required
    check (event_type <> 'closed' or effective_date is not null)
);

comment on table pfin.account_event is
  'Append-only audit of pfin.account open/closed transitions (ADR-042 Decision 5 + 5a; ADR-011 Decision 2 audit-class). The TRANSITION is audit-class; pfin.account is not and must not become so. Named for the general class, NOT closure_history: event_type widens by one-line ALTER (030 precedent) rather than by a second near-identical table — but WIDENING IS SEC-JOINT-REVIEW-MANDATORY, because the SD tier, the read posture and indefinite retention were all calibrated for closure events, and the tier rates what the CHECK admits, not what the table is named. NO free text anywhere: this table is immutable and retained indefinitely, so admission is the ONLY control — there is no redaction path for anyone, including the row''s tenant. Every column takes more than one value across the writers that exist (Sec''s criterion); matched_on/decided/provider_event_id/linked_source_id were DROPPED because the ratified model removed their only writer, and #17 is therefore never created (Decision-3 family stays 16 labeled / 13 DDL-realized). Writers: the user''s own close/reopen (session write under RLS — NOT a Decision 1 privileged-context surface, so clause (d) does not apply) and the one-time remediation as the migration role, which is RLS-exempt and is why #16 is load-bearing.';

comment on column pfin.account_event.effective_date is
  'WHEN THE TRANSITION TOOK EFFECT — deliberately SEPARATE from created_at (row-insertion time), per ADR-011 Decision 4''s third bullet (the Lock 15 catch on Lock 9: conflating event-date with insertion-time is the documented schema-orthogonality failure). A backdated closure has effective_date < created_at and that is CORRECT, not drift. NULLABLE, and NULL means NOT RECORDED — never "today": a reopen has no date carrier unless the caller sets pfin.effective_date, and defaulting to current_date would make a real same-day reopen BYTE-IDENTICAL to an unknown-date one, indistinguishable forever on a table with no redaction path. Requiredness is asymmetric and enforced by account_event_effective_date_required: a closure MUST carry a date (it comes from the data, new.closed_at), a reopen MAY be NULL. ⚠ QUERY HAZARD, MEASURED: Postgres DESC defaults to NULLS FIRST, and account_event_account_idx is (account_id, effective_date desc) — so a naive `order by effective_date desc limit 1` returns a NULL-dated reopen AHEAD OF EVERY DATED EVENT. Verified: with a closure dated 2026-01-15 and a NULL-dated reopen, the naive query returns the reopen and `desc nulls last` returns the closure. ANY latest-event lookup MUST use `nulls last` or filter explicitly. The nullability is deliberate and correct; this ordering consequence rides with it.';

comment on column pfin.account_event.actor is
  'Discriminated: `user:<uuid>` or `system:<source>`. NEVER a bare uid that silently means "system" when null — the discrimination is the point. Justified by the REMEDIATION path (the one non-session writer, running as the migration role), where users_id (tenant) and the acting identity genuinely diverge. Without that path this column would be redundant with users_id and should have been dropped with the others.';

alter table pfin.account_event enable row level security;

-- Owner-scoped read + insert. INSERT is needed because 058's gate trigger is
-- SECURITY INVOKER and therefore writes AS THE CALLING USER. No UPDATE/DELETE
-- policy and no grant: audit-class, and the triggers below fence it for every
-- role regardless of grant state.
create policy account_event_select on pfin.account_event
  for select to authenticated
  using (
    (users_id = auth.uid())
    and (
      coalesce((select s.mfa_policy from pfin.user_settings s where s.users_id = auth.uid()), 'none') not in ('totp', 'passkey')
      or (auth.jwt() ->> 'aal') = 'aal2'
    )
  );

create policy account_event_insert on pfin.account_event
  for insert to authenticated
  with check (
    (users_id = auth.uid())
    and (
      coalesce((select s.mfa_policy from pfin.user_settings s where s.users_id = auth.uid()), 'none') not in ('totp', 'passkey')
      or (auth.jwt() ->> 'aal') = 'aal2'
    )
  );

comment on policy account_event_select on pfin.account_event is
  'Direct-owner read (users_id = auth.uid()) AND the 025 aal2 step-up conjunct, INHERITED not re-argued — a closure history exposes account existence, names, closure dates and reasons, which is at least as sensitive as the account rows it describes. Character-identical conjunct to account_select (025:201) by construction.';

-- ACL-before-RLS (PR #106 gotcha): the role needs table-level GRANTs even with
-- RLS on. SELECT + INSERT only — never UPDATE or DELETE.
grant select, insert on pfin.account_event to authenticated;

-- RLS-predicate index + the per-account history read path.
create index if not exists account_event_uid_idx on pfin.account_event (users_id);
-- NULLS LAST IS NOT AN OPTIMIZATION — IT COMPLETES THE NULL-DATE FIX (Sec ruling).
--   Postgres DESC defaults to NULLS FIRST. Since effective_date became nullable,
--   a plain `desc` index sorts an UNKNOWN-DATE reopen AHEAD OF EVERY DATED EVENT,
--   which partially reintroduces the harm the nullability removed:
--     current_date  made an unknown date look like TODAY'S event;
--     NULLS FIRST   makes an unknown date sort as the LATEST event.
--   Both make ABSENCE READ AS RECENCY. Measured with rows (2026-01-10 closed),
--   (2026-02-20 closed), (NULL reopened): `order by effective_date desc limit 1`
--   returns the NULL row; `desc nulls last` returns 2026-02-20.
--
--   And telling consumers to write `nulls last` is NOT sufficient — measured on
--   20k rows, ANALYZEd: the correct query against a plain `desc` index acquires a
--   Sort node, while against `desc nulls last` it is an Index Only Scan. The
--   index declaration IS the choice of which ordering is intended.
--
--   INTENDED CONSUMER: latest-event-per-account lookups
--     (order by effective_date desc nulls last limit 1).
--   This index serves exactly ONE of the two orderings. Anyone adding an
--   `order by` on this table should find that written here rather than infer it.
create index if not exists account_event_account_idx
  on pfin.account_event (account_id, effective_date desc nulls last);

-- ----------------------------------------------------------------------------
-- Decision-3 canonical instance #16 — account_event.account_id -> pfin.account.
--   P1 matched-tenant, LOCAL ANCHOR: this row carries its own resolved users_id,
--   validated equal to the referenced account's users_id (the 012 shape, and the
--   #15 shape at 044 which this copies).
--   BEFORE INSERT ONLY — the table is immutable audit-class, so UPDATE/DELETE
--   are trigger-blocked below and an UPDATE fence would be dead code (019/044
--   precedent).
--   LOAD-BEARING, not decorative: the remediation writer runs as the migration
--   role and is RLS-EXEMPT, so it could write a mismatched (account_id, users_id)
--   pair that no policy would catch. This fence is the only thing that does.
-- ----------------------------------------------------------------------------
create or replace function pfin.fn_account_event_matched_account()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if not exists (
    select 1 from pfin.account a
    where a.account_id = new.account_id
      and a.users_id = new.users_id
  ) then
    raise exception
      'cross-tenant account_event rejected: account_id % is not owned by users_id % (ADR-011 Decision 3 #16 matched-tenant fence)',
      new.account_id, new.users_id;
  end if;
  return new;
end;
$$;

comment on function pfin.fn_account_event_matched_account() is
  'BEFORE INSERT matched-tenant fence on pfin.account_event.account_id (ADR-011 Decision 3 CANONICAL INSTANCE #16; P1 local-anchor, copying the #15 shape at 044). The row carries its own resolved users_id; the referenced pfin.account row must share it. NULL-safe fail-closed (NOT EXISTS -> raise). SECURITY INVOKER + set search_path = '''' — NOT a DEFINER allowlist entry, allowlist stays 4. BEFORE INSERT only: the table is immutable audit-class so UPDATE/DELETE are trigger-blocked and an UPDATE fence would be dead. LOAD-BEARING for the one RLS-exempt writer — the migration-role remediation path could otherwise write a mismatched (account_id, users_id) pair that no policy would catch.';

create trigger account_event_matched_account
  before insert on pfin.account_event
  for each row execute function pfin.fn_account_event_matched_account();

-- ----------------------------------------------------------------------------
-- Immutability, Lock 10 mod #8 CROSS-TIER (the 004 / 054 pattern reproduced).
--   Blocks UPDATE + DELETE for ALL roles including service_role — which bypasses
--   RLS but NOT triggers — and TRUNCATE at statement level, because row-level
--   triggers do NOT fire on TRUNCATE. Messages are DELIBERATELY DISTINCT so a
--   battery can assert WHICH fence fired (the 054 distinct-message precedent);
--   an assertion that cannot identify the fence proves less than it appears to.
-- ----------------------------------------------------------------------------
create or replace function pfin.fn_account_event_block_mutation()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  raise exception
    'pfin.account_event is immutable (append-only audit-class; ADR-011 Decision 2 / ADR-042 Decision 5). % blocked — a state transition is a historical fact and is never revised; record a new event instead.', tg_op;
end;
$$;

comment on function pfin.fn_account_event_block_mutation() is
  'BEFORE UPDATE OR DELETE immutability fence on pfin.account_event (ADR-011 Decision 2 / Lock 10 mod #8). SECURITY INVOKER (touches nothing; not a DEFINER allowlist entry). raise, NOT return null — return null would silently no-op the row and read as success. Blocks UPDATE + DELETE for ALL roles incl. service_role (bypasses RLS, not triggers) — the privileged-context immutability fence RLS-default-deny alone cannot provide. Message distinct from the TRUNCATE fence for test-matching.';

create trigger account_event_block_mutation
  before update or delete on pfin.account_event
  for each row execute function pfin.fn_account_event_block_mutation();

create or replace function pfin.fn_account_event_block_truncate()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  raise exception
    'pfin.account_event is immutable (append-only audit-class; ADR-011 Decision 2 / ADR-042 Decision 5). TRUNCATE blocked — the closure-history retention path is not a wipe surface.';
end;
$$;

comment on function pfin.fn_account_event_block_truncate() is
  'BEFORE TRUNCATE (statement-level) immutability fence on pfin.account_event. Row-level triggers do NOT fire on TRUNCATE, so this statement-level fence plus the absent TRUNCATE grant close the audit-retention-wipe path for ALL roles regardless of grant state. SECURITY INVOKER. Message distinct from the row-level fence for test-matching.';

create trigger account_event_block_truncate
  before truncate on pfin.account_event
  for each statement execute function pfin.fn_account_event_block_truncate();
