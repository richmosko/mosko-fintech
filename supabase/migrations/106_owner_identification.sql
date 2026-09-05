-- ============================================================================
-- Migration: pfin.owner_identification — the per-user owner-identification
-- header string that names the monthly report (PRD §2.6.4 ψ-1). Phase 6 Build
-- Loop (SELF-352 / A8). Realizes the member of the ADR-011 Decision 18 / Lock 14
-- per-domain settings store that Decision 18's locked enumeration named and no
-- migration had built. Adds no SD entry, adds no RT entry, adds no Decision-3
-- label, and moves no ledger.
--
-- WHAT THIS DOES: creates `pfin.owner_identification`, ONE row per user carrying
-- ONE nullable plain-text scalar — `owner_id_header_text` — under
-- `unique (users_id)`. Owner-only RLS on all four verbs, each policy carrying
-- the 025 aal2 step-up clause. Full authenticated CRUD grant, anon zero-grant,
-- service_role ungranted. Authors NO function: the updated_at refresh rides the
-- existing 001 trigger helper.
--
-- ----------------------------------------------------------------------------
-- FAMILY POSITION, stated as a dated event rather than as a tally. Decision 18's
--   family-size amendment (2026-08-16) names the per-domain settings family's
--   membership; read it live there. Of the members it names, the ones other than
--   this table were built at `074` (planning_target, whose referent ADR-056
--   moved), `090` (cashflow_target) and `101` (tax_bracket_schedule +
--   tax_bracket_row). This file deliberately carries no family count: the family
--   has already grown once, at that amendment, so a count copied
--   here would acquire a maintenance obligation it would not honour.
--
-- SHAPE — RULED, NOT INHERITED. `users_id` + one nullable TEXT payload column +
--   created_at + updated_at, `unique (users_id)`: the SELF-352 AC as re-derived
--   and ruled by F/CTO at the 2026-09-04 V1.5 pre-flight sitting.
--   ⚠ SECURITY SD-11's acceptance cell RECORDS A DIFFERENT COLUMN, and the
--   divergence is named here rather than silently resolved. That cell describes
--   the storage surface as `pfin.owner_identification.owner_name`, declared
--   `owner_name TEXT NOT NULL`. The ruled shape is `owner_id_header_text` and it
--   is NULLABLE — the name because the AC names it, and the nullability because
--   PRD §2.6.4 ψ-1 requires an UNSET state to be representable (see UNSET
--   SEMANTICS below), which a NOT NULL column cannot carry. SD-11's recorded
--   column name and NOT NULL are superseded by this DDL. SECURITY is Sec-owned;
--   correcting that cell is its owner's and is routed to the joint review this
--   PR carries — nothing in this file assumes it done.
--
-- WHY A TABLE AND NOT COLUMNS ON pfin.user_settings: 025 excludes
--   pfin.user_settings from the aal2 backstop as a NON-NEGOTIABLE exclusion
--   (clausing it recurses into the policy that reads it), so sensitive tenant
--   data sited there could never carry the step-up fence every other
--   tenant-owned pfin table carries. Same ground 074 recorded for
--   planning_target and 090 for cashflow_target. Decision 18's Option B ruling —
--   per-domain tables rather than one generalized settings table — is the other
--   half of the answer and is unchanged here.
--
-- ----------------------------------------------------------------------------
-- UNSET SEMANTICS — NULL, AND ROW-ABSENT, MEAN THE SAME THING. PRD §2.6.4 ψ-1
--   states the product contract: until the string is set, the in-app header slot
--   shows a prompt to set it and the PDF carries no owner line. So "unset" is a
--   first-class state, not an error, and it must be storable.
--   BOTH unset representations are reachable: a user who has never opened the
--   editor has NO ROW, and a user who clears the field has a row with a NULL
--   column. They arrive as different result shapes (zero rows vs one row of
--   NULL). READER OBLIGATION, standing: every reader MUST treat row-absent and
--   NULL identically as "no owner header set", and MUST NOT render an empty
--   header line for either.
--   ⚠ THE BLANK STRING IS NOT A THIRD UNSET STATE, and this file refuses it
--   rather than leaving the question to each reader — see the not-blank CHECK
--   under TEXT FENCE. A write path that clears the field MUST send NULL.
--   THE DELETE VERB IS GRANTED AND FENCED, and it is a legitimate second way to
--   reach unset here: unlike 090 — where one row carries two independent facts,
--   so a row DELETE would unset both — this row carries exactly one fact, so a
--   DELETE and a NULL-write have the same meaning. Neither is privileged by this
--   DDL; the reader obligation above is what makes them equivalent, and the
--   DELETE policy is load-bearing regardless (see DELETE POLICY).
--
-- SETTINGS ARE NOT AUDIT-CLASS (ADR-011 Decision 18): UPSERT-in-place on the
--   `unique (users_id)` conflict target; no edit-history rows, no versioned
--   sibling. `updated_at` refresh is the only write-time side effect.
--   ⚠ CONSEQUENCE, STATED RATHER THAN DISCOVERED: with no history, a rename
--   cannot be read as-of. That is precisely why PRD §2.6.4 requires the header be
--   SNAPSHOTTED onto the monthly report at generation
--   (`owner_header_at_generation`) rather than read live: a historical report
--   shows the name in effect when it was generated. This table is the LIVE
--   settings value only; it is never the as-of source for a past month.
--   The snapshot column lives on the monthly-report table (SELF-350 / A1), is
--   not authored here, and this file states the property rather than asserting
--   that surface exists yet.
--
-- FORWARD-COMPAT FENCE (Decision 18, restated as the standing requirement it
--   is): no JSONB column in the settings store, under any future surface. One
--   named typed column here; a second owner-identification fact would acquire a
--   second named column. ⚠ The `101` amendment's `p_rows jsonb` carve-out is a
--   TRANSPORT parameter on a function and does not reach a stored column; this
--   table stores no JSONB and the fence binds it fully.
--
-- ----------------------------------------------------------------------------
-- TEXT FENCE — THREE NAMED CHECK CONSTRAINTS, each `is null or (...)` so the
--   unset state passes. They are named rather than left to Postgres's automatic
--   `_check`, `_check1`, `_check2` numbering, because a violation is reported by
--   constraint NAME and an opaque ordinal tells a caller nothing about which
--   rule it broke.
--   ⚠ A value violating more than one is reported in constraint-NAME order, not
--   in the order written here: `..._header_len_check` sorts before
--   `..._header_not_blank_check`, which sorts before
--   `..._header_single_line_check`. A battery leg asserting a specific
--   constraint name must therefore violate that rule ALONE.
--
--   (1) LENGTH — 120 characters (PM §12.4, ruled at the 2026-09-04 sitting; the
--       existing-system parity example is well inside it). `length()` counts
--       CODE POINTS. ⚠ THE ZOD MIRROR IS NOT AUTOMATICALLY EQUIVALENT: a
--       JavaScript string's `.length` counts UTF-16 CODE UNITS, so an astral
--       character (an emoji, a rare CJK glyph) counts 2 there and 1 here. A Zod
--       `.max(120)` on `.length` is therefore equal-or-STRICTER than this CHECK
--       and can never admit what the database refuses — which is the safe
--       direction. A mirror written to count code points instead (e.g. spreading
--       the string) is exactly equivalent. A mirror written to count BYTES would
--       be looser for multi-byte text and is the one form to avoid.
--   (2) SINGLE LINE — PRD §2.6.4 ψ-1 makes multi-line headers V2+, so a V1
--       header is one line. The class fenced is the Unicode line-boundary set,
--       not LF alone: LF, VT, FF, CR, NEL, LINE SEPARATOR, PARAGRAPH SEPARATOR.
--       A bare CR is a line break to a renderer and would pass an LF-only test,
--       so an LF-only fence would not cover the same class as the rule it
--       enforces.
--   (3) NOT BLANK — a present value contains at least one non-whitespace
--       character. ⚠ THIS CONSTRAINT IS NOT IN THE SELF-352 AC; it is an
--       Architect addition, flagged as such. Without it '' is storable and
--       becomes a THIRD unset representation, distinct from NULL and from
--       row-absent, which every reader and the generation-time snapshot would
--       each have to handle — and an editor that clears a text input by sending
--       '' would silently produce an empty owner line in a rendered report
--       instead of the ψ-1 prompt. With it, the write path MUST send NULL to
--       clear, and unset stays exactly the two states the reader obligation
--       already covers. Losing side, named: a clear-by-empty-string write now
--       fails with 23514 rather than succeeding, so the settings editor
--       (SELF-359 / P7) must map an emptied input to NULL. Additive and
--       reversible — dropping it needs no data migration.
--
--   WHAT THIS FENCE IS NOT. It is the DB half only, and it is necessary rather
--   than sufficient. RT-12 — the canonical test label for this surface, per
--   SECURITY §4.1 axis iv, which names "the §2.6.4 owner-identification
--   settings-store write path (RT-12)" — scopes an adversarial-input battery
--   (XSS / SQL injection / oversize / Unicode control / RTL override /
--   homoglyph) at the WRITE ENDPOINT, plus the requirement that the rendered PDF
--   header carry no executable content. A length bound and a line-boundary
--   rejection do not deliver any of that. The app-layer Zod `.strict()` schema
--   (P7) remains the first line and mirrors BOTH rules above; output escaping at
--   the render surface is a separate control on a separate layer. Nothing here
--   discharges RT-12.
--
-- ----------------------------------------------------------------------------
-- POSTURE RATIONALE — SECURITY INVOKER (default per ADR-011 Lock 11); NOT
--   SECURITY DEFINER. This migration authors NO function of any kind: the
--   `updated_at` refresh binds the EXISTING pfin.fn_refresh_updated_at() from
--   001, and the aal2 backstop is INLINED into each policy per 025's ratified
--   inline-not-helper posture (a `set search_path = ''` helper is not inlined by
--   the planner, so it would evaluate per row). The SECURITY DEFINER allowlist is
--   therefore UNCHANGED by this migration — read ADR-011 Decision 9 live for its
--   contents; no size is stated here.
--
-- ADR-011 DECISION 3 — NO LABEL DRAFTED, NONE RESERVED. The sole reference
--   column on this table is `users_id -> auth.users(id)`, the direct owner
--   anchor. Decision 3 governs FK-shaped columns that cross a tenant isolation
--   boundary; a table's own tenant anchor is not such a column, and the family is
--   unchanged by this migration. No label is drafted for this table in either
--   direction — Decision 18's own amendment gives the reason in its own words: a
--   recorded expectation of membership "is how a draft label gets invented and
--   then reasoned out of existence." Read Decision 3's body live for the family's
--   current shape; this file carries no tally.
--
-- aal2 STEP-UP BACKSTOP (ADR-029 / 025; C3 standing obligation; Sec F-9 at the
--   2026-09-04 sitting). This is a new sensitive tenant-owned pfin table, so it
--   inherits the per-user-conditional backstop clause on every authenticated
--   policy — AND-ed into the read USING and into the write WITH CHECK / USING.
--   It is NOT one of 025's named exclusions: it is not a global shared-read
--   table (its policies are tenant-scoped, never `using (true)`), not a
--   service_role-only / default-deny table (it has authenticated policies on all
--   four verbs), and it is not the `user_settings` substrate itself. ⚠ THE
--   `user_settings` EXCLUSION DOES NOT TRANSPLANT TO A NEIGHBOURING SETTINGS
--   TABLE: that exclusion exists solely because the clause's own subquery reads
--   `user_settings`, so clausing it would recurse. Nothing recurses here — this
--   table is not the clause's subquery target. The clause below is copied
--   byte-faithfully from 025.
--
-- DELETE POLICY — SHIPS WITH ITS OWN TENANT CLAUSE, NEVER TRIMMED (SECURITY
--   §4.6 "Lock-14 settings-family DELETE-policy fence", which binds every member
--   of this family and names this table among those it binds). No DELETE policy
--   in the family may be trimmed, weakened, or omitted on the reasoning that the
--   SELECT policy already covers it: Postgres consults the SELECT policy during a
--   DELETE only when the statement reads or filters by a column, so for an
--   unqualified `delete from pfin.owner_identification;` the DELETE policy's own
--   USING clause — its tenant conjunct and its aal2 conjunct alike — is the SOLE
--   DB-layer fence. QA measured that at 074 on 2026-08-20 with a complementary
--   corrupt-the-control pair; the reasoning is confirmed false, not merely
--   unproven. ⚠ The battery trap recorded with that fence applies to this table
--   too: a cross-tenant DELETE assertion written WITH a column filter is
--   satisfied by either policy, so it cannot isolate this one.
--
-- ----------------------------------------------------------------------------
-- §10 3-AXIS CROSS-CHECK (Path B — reference ADR-011 Decision 4; the catalogued
--   list is NOT restated here and no count is carried, deliberately). Decision 4
--   was read verbatim and live before drafting. This migration introduces ZERO
--   catalogued §10 instances: it is a Lock 14 user-facing-direct-DB-write
--   surface, and class membership is not a catalogued instance (ADR-042's ruling
--   for the 058 fences). It touches no infrastructure-credential-presence
--   surface, no service_role-key / code-layer allowlist surface, and no
--   network-exposure/config surface.
--     (i)   Instance-numbering: unchanged — no catalogued instance is added,
--           reordered, or renumbered.
--     (ii)  Layer-attribution: unchanged — no catalogued instance's layer is
--           re-attributed, and no surface becomes "four-layer".
--     (iii) Verbatim-vs-paraphrase: Decision 4 is linked, not restated.
--   ⚠ The §10 catalogued set and the CI-fenced RT set are DIFFERENT SETS and are
--   not reconciled here or anywhere. RT-12 is the canonical test label for this
--   surface and already exists in the Sec-owned RT catalog; this migration
--   creates no RT entry and moves no ledger.
--   ⚠ TRIGGER-BACKED LAYERS ARE INERT UNDER `session_replication_role =
--   replica` (Decision 4's 2026-09-03 amendment). This table's fences are RLS
--   POLICIES and CHECK CONSTRAINTS — neither is trigger-backed, so both survive
--   that GUC. The one trigger here refreshes `updated_at` and is not a fence.
--
-- ----------------------------------------------------------------------------
-- Numbering: 106 follows 105. Order-dependent — must run AFTER 001 (pfin schema
--   + fn_refresh_updated_at), AFTER 024 (pfin.user_settings, which the aal2
--   clause reads) and AFTER 025 (which authored the clause). No later migration
--   depends on 106 landing first.
--
-- ----------------------------------------------------------------------------
-- CONTRACT
--   pfin.owner_identification — one row per user; `unique (users_id)` is the ON
--     CONFLICT target for the UPSERT write path.
--   owner_id_header_text text NULL — the owner-identification header string.
--     NULL means UNSET, and row-absent means the same; '' is refused.
--     CHECKs: length <= 120 code points; no Unicode line boundary; at least one
--     non-whitespace character. The Zod schema mirrors the length and the
--     line-boundary rule (P7's obligation, not discharged here) and must not be
--     looser than either.
--   users_id — DEFAULT auth.uid(), load-bearing: it lets an authenticated INSERT
--     omit the column and still satisfy the INSERT policy's WITH CHECK. The
--     write path MUST derive the tenant from the session, never from the request
--     body (Lock 14 mod #1).
--   RLS: SELECT / INSERT / UPDATE / DELETE, each `users_id = auth.uid()` AND the
--     025 aal2 clause. Grants: authenticated only.
--   Trigger: BEFORE UPDATE FOR EACH ROW -> pfin.fn_refresh_updated_at() (001).
-- ============================================================================

create schema if not exists pfin;
grant usage on schema pfin to authenticated;

-- ----------------------------------------------------------------------------
-- TABLE
-- ----------------------------------------------------------------------------
create table if not exists pfin.owner_identification (
  id                    bigint generated always as identity primary key,
  users_id              uuid not null default auth.uid()
                          references auth.users (id) on delete cascade,
  owner_id_header_text  text,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  unique (users_id),
  constraint owner_identification_header_len_check
    check (owner_id_header_text is null
           or length(owner_id_header_text) <= 120),
  -- The Unicode line-boundary class, not LF alone: LF, VT, FF, CR, NEL, LINE
  -- SEPARATOR, PARAGRAPH SEPARATOR. A bare CR breaks a line in a renderer and
  -- would pass an LF-only test.
  constraint owner_identification_header_single_line_check
    check (owner_id_header_text is null
           or owner_id_header_text !~ '[\u000A\u000B\u000C\u000D\u0085\u2028\u2029]'),
  --   codepoints in order: LF VT FF CR NEL LINE-SEP PARA-SEP
  -- A present value carries at least one non-whitespace character, so '' and a
  -- whitespace-only string are refused and unset stays exactly two states
  -- (NULL, row-absent). Architect addition beyond the AC; see TEXT FENCE (3).
  constraint owner_identification_header_not_blank_check
    check (owner_id_header_text is null
           or owner_id_header_text ~ '[^[:space:]]')
);

comment on table pfin.owner_identification is
  'Per-user owner-identification header string for the monthly report (PRD §2.6.4 '
  'ψ-1; ADR-011 Decision 18 / Lock 14 per-domain settings store; SELF-352). ONE row '
  'per user carrying ONE nullable plain-text scalar, with unique (users_id) as the '
  'UPSERT conflict target. UNSET IS A FIRST-CLASS STATE and has TWO reachable '
  'representations that MUST be read identically as "no owner header set": the row '
  'is absent (the user never opened the editor), or the column is NULL (the user '
  'cleared it). No reader may render an empty header line for either. The blank '
  'string is NOT a third unset state — a CHECK refuses it, so a write path clearing '
  'the field MUST send NULL. The DELETE verb is granted and fenced and reaches the '
  'same unset state, because this row carries exactly one fact (unlike '
  'cashflow_target, where one row carries two and a DELETE would unset both). '
  'Settings are not audit-class (Decision 18): UPSERT-in-place, no edit-history '
  'rows — and therefore a rename CANNOT be read as-of, which is why PRD §2.6.4 '
  'requires the header be snapshotted onto the monthly report at generation rather '
  'than read live. This table holds the LIVE value only; it is never the as-of '
  'source for a past month. MUTABLE, full authenticated CRUD, RLS direct-owner '
  '(users_id = auth.uid()) with the ADR-029 / 025 aal2 step-up clause on every '
  'policy, the DELETE policy included and never trimmed (SECURITY §4.6 Lock-14 '
  'settings-family DELETE-policy fence, which binds this table by name). Carries NO '
  'ADR-011 Decision 3 instance and no label in either direction: users_id is the '
  'tenant anchor, not a cross-tenant reference, and no other FK-shaped column '
  'exists. No JSONB, per Decision 18''s forward-compat fence. anon zero-grant; '
  'service_role ungranted (the app writes as the user, under the user''s own JWT).';

comment on column pfin.owner_identification.users_id is
  'SOLE tenant anchor (users_id = auth.uid()). DEFAULT auth.uid() so an '
  'authenticated INSERT that omits it lands owned and satisfies the INSERT '
  'policy''s WITH CHECK; FK -> auth.users(id) ON DELETE CASCADE with the tenant. '
  'NOT a cross-tenant reference (it IS the anchor) -> ADR-011 Decision 3 does not '
  'apply to this column. Lock 14 mod #1 requires the write path derive this from '
  'the session (auth.uid()), never from the request body.';

comment on column pfin.owner_identification.owner_id_header_text is
  'The owner-identification header string rendered at the top of the monthly '
  'report (PRD §2.6.4 ψ-1). Plain text, single line. NULL = UNSET — the user has '
  'not set one; the in-app header slot shows a prompt and the rendered PDF carries '
  'no owner line. Row-absent means the same thing. THREE NAMED CHECKS, each '
  'permitting NULL: (1) length <= 120 CODE POINTS — a JavaScript .length counts '
  'UTF-16 code units, so a Zod .max(120) is equal-or-STRICTER and can never admit '
  'what this refuses, which is the safe direction; a byte-counting mirror would be '
  'looser and is the one form to avoid; (2) no Unicode line boundary — LF, VT, FF, '
  'CR, NEL, LINE SEPARATOR, PARAGRAPH SEPARATOR, because a bare CR breaks a line '
  'in a renderer and an LF-only test would not cover the rule it enforces; (3) at '
  'least one non-whitespace character, so the blank string cannot become a third '
  'unset state. A violation of more than one is reported in constraint-NAME order, '
  'which is not the order they are declared in. THESE CHECKS ARE THE DB HALF AND '
  'ARE NECESSARY RATHER THAN SUFFICIENT: RT-12 scopes the adversarial-input '
  'battery (XSS / SQL injection / oversize / Unicode control / RTL override / '
  'homoglyph) at the write endpoint and requires the rendered header carry no '
  'executable content — none of which a length bound and a line-boundary '
  'rejection deliver. The app-layer Zod .strict() schema is the first line and '
  'mirrors (1) and (2); output escaping at the render surface is a separate '
  'control on a separate layer.';

-- ----------------------------------------------------------------------------
-- RLS — owner-only on all four verbs. Each policy is
-- `(users_id = auth.uid()) and (<025 aal2 backstop clause>)`, the clause copied
-- byte-faithfully from 025 (COALESCE null-safe, inline — never a helper: 025
-- ratified inline because `set search_path = ''` disables SQL-function inlining,
-- so a helper would evaluate per row).
-- ----------------------------------------------------------------------------
alter table pfin.owner_identification enable row level security;

create policy owner_identification_select on pfin.owner_identification
  for select to authenticated
  using (
    (users_id = auth.uid())
    and (
      coalesce((select s.mfa_policy from pfin.user_settings s where s.users_id = auth.uid()), 'none') not in ('totp', 'passkey')
      or (auth.jwt() ->> 'aal') = 'aal2'
    )
  );

create policy owner_identification_insert on pfin.owner_identification
  for insert to authenticated
  with check (
    (users_id = auth.uid())
    and (
      coalesce((select s.mfa_policy from pfin.user_settings s where s.users_id = auth.uid()), 'none') not in ('totp', 'passkey')
      or (auth.jwt() ->> 'aal') = 'aal2'
    )
  );

create policy owner_identification_update on pfin.owner_identification
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
-- reasoning that owner_identification_select covers it — that reasoning is
-- confirmed false (SECURITY §4.6; QA-measured at 074, 2026-08-20). For a
-- statement with no column reference the SELECT policy is not consulted at all,
-- and this USING clause is the sole DB-layer fence.
create policy owner_identification_delete on pfin.owner_identification
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
-- table at all. Full V1 CRUD to authenticated — the DELETE grant is what makes
-- the row-delete route to unset writable, alongside the NULL-write route. No
-- service_role grant (008 grants per table and establishes no default
-- privileges, so service_role is ungranted by construction — this line records
-- that, it does not effect it). anon zero-grant (pfin schema USAGE is
-- authenticated-only).
-- ----------------------------------------------------------------------------
grant select, insert, update, delete on pfin.owner_identification to authenticated;

-- No separate users_id index: the `unique (users_id)` btree already serves the
-- RLS predicate (users_id = auth.uid()) and the UPSERT conflict target. Mirrors
-- 009 / 022 / 074 / 090.

-- updated_at auto-refresh via the EXISTING fn_refresh_updated_at (001). Adds no
-- SECURITY DEFINER allowlist entry.
create trigger owner_identification_set_updated_at
  before update on pfin.owner_identification
  for each row execute function pfin.fn_refresh_updated_at();
