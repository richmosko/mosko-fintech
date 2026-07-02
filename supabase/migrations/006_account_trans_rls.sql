-- ============================================================================
-- Migration: pfin.account_trans RLS — rd_access/wr_access-JOIN policies
-- Phase 6 Build Loop (SELF-190 / Wave 1 B5 / V1.0 Platform foundation).
-- Lands the Lock 3 (ADR-011 Decision 7, Option B) account_trans RLS shape that
-- 004 deferred: account_users.rd_access-JOIN at SELECT + wr_access-JOIN WITH
-- CHECK at INSERT. Pure declarative RLS — no functions, no schema/column DDL.
--
-- Numbering: 006 follows 001 (foundation) / 002 (fn_mask) / 003 (account +
-- account_users + fn_grant_creator_access) / 004 (account_trans immutable) /
-- 005 (reconciliation_event family). Prerequisites: 004 created pfin.account_trans
-- with RLS enabled but NO policies (default-deny-all) and explicitly deferred the
-- JOIN policies here — 004 header: "the rd_access/wr_access-JOIN RLS policies
-- (Lock 3 / Decision 7) land at SELF-190 (B5)". 003 created pfin.account_users +
-- the fn_grant_creator_access creator-grant row that these policies JOIN against.
-- This migration DISCHARGES that 004 deferral; account_trans becomes reachable by
-- authenticated for the first time (it was fenced-but-inaccessible until now).
--
-- SCOPE — V1.0 = account_trans RLS ONLY.
--   ADDS to pfin.account_trans: a SELECT policy (rd_access-JOIN), an INSERT policy
--   (wr_access-JOIN WITH CHECK), and the paired table-level GRANT select, insert.
--   NO UPDATE/DELETE policy (Fork-2 = A; default-deny + 004's block triggers — see
--   POSTURE RATIONALE). This migration creates NO functions and NO tables/columns;
--   the SECURITY DEFINER allowlist is UNCHANGED at 3 (ADR-011 Decision 9) and no new
--   FK-shaped column is introduced (Decision 3 family +0 — see below).
--
-- LOCK 3 (Decision 7 / Option B) MOD DISPOSITION at SELF-190 (F/CTO-ratified):
--   - mod #1 (account_users column-level UPDATE restriction: REVOKE UPDATE; GRANT
--     UPDATE (nickname, notes)) — DEFERRED. See the dedicated block below.
--   - mod #2 (elevate fn_grant_creator_access to SECURITY DEFINER + verify it fires
--     under V1 RLS) — ALREADY LANDED at 003 (allowlist 2->3, Decision 9 SELF-187
--     amendment). VERIFY-ONLY here: no new DDL. The creator-grant row 003's trigger
--     inserts into account_users (account_id, users_id, rd_access=true, wr_access=true)
--     is EXACTLY the row these two policies JOIN against — so the account creator can
--     SELECT + INSERT their own account_trans, and QA asserts "fires under V1 RLS".
--   - mod #3 (write-path WITH CHECK uses wr_access, NOT rd_access) — IMPLEMENTED by
--     the account_trans_insert policy below.
--   - mod #4 (advisory SECURITY annotation noting V1 exercises V2 sharing-shape ACL)
--     — routes to Sec at joint-review (Fork-3 = A). This migration does NOT edit
--     docs/SECURITY/ (doc artifact; separate branch/flow); the advisory disposition
--     is Sec's to author at review.
--
-- ----------------------------------------------------------------------------
-- mod #1 DEFERRAL — documented forward-fence (F/CTO-ratified conscious deviation).
--   (i) WHY DEFERRED: SELF-190 introduces NO authenticated write to account_users.
--       The account_trans write path (INSERT policy below) reads the wr_access flag
--       on the creator-grant row 003's DEFINER trigger already made — it does NOT
--       write account_users. authenticated therefore keeps SELECT-only on
--       account_users (per 003); mod #1's REVOKE UPDATE; GRANT UPDATE (nickname,notes)
--       only becomes load-bearing once authenticated is first granted a write there.
--   (ii) ENFORCEMENT HOOK: the 003 pfin.account_users table comment carries the
--       HARD-GATE verbatim — the column-level UPDATE restriction "MUST land in the
--       SAME PR that first grants any authenticated write here, never after". That
--       comment is the durable, in-schema hook that forces mod #1 into the future
--       V2 sharing-UI write-grant PR. Deferral does not drop the fence; it relocates
--       it to the PR that actually opens the surface it fences.
--   (iii) AC DEVIATION (truthful + traceable): the SELF-190 issue AC-as-written
--       expected mod #1 to land in this PR. F/CTO ratified DEFER (Fork-1 = A) on the
--       V1/V2-boundary + feedback_incumbent_exceeds_v1_review grounds: landing mod #1
--       now would OPEN a dead nickname/notes write path (no V1 UI) AND require an
--       account_users UPDATE policy = activating the exact cross-tenant re-tenant
--       pivot surface Sec called load-bearing at Decision 7 ("would ship silently").
--       Deferring is the reversible, lower-surface choice; the hard-gate keeps it
--       non-droppable.
--
-- ----------------------------------------------------------------------------
-- §10 3-AXIS CROSS-CHECK (Path B — reference, do not restate the numbered list).
--   ZERO catalogued §10 instances; ledger stays at 2 (RT-22 + RT-26 per ADR-011
--   Decision 4). (i) numbering RT-22 first / RT-26 second — unchanged. (ii)
--   layer-attribution — no infra-credential-presence (RT-22) or service_role-
--   allowlist (RT-26) surface is touched (this is authenticated-tier RLS/ACL policy
--   work). (iii) Decision 4 is linked, not restated.
--
-- DECISION 3 (cross-tenant FK-bypass family) EVALUATION — family count +0 (stays 7).
--   This migration adds NO FK-shaped columns — it adds policies + a GRANT to the
--   existing pfin.account_trans table. Its two FK-shaped columns (account_id +
--   replaces_trans_id) were already evaluated at 004: account_id is the SOLE tenant
--   anchor (account_trans carries no own users_id; scope derives via account_id ->
--   account_users.rd_access-JOIN, Decision 7 / Lock 3 — no second anchor to mismatch,
--   so NOT a Decision-3 instance) and replaces_trans_id is the already-catalogued 2nd
--   instance (Lock 10 mod #2, fenced by 004's fn_account_trans_matched_account). The
--   rd_access/wr_access-JOIN policies below are the tenant-isolation MECHANISM these
--   columns rely on; they add no new matched-tenant obligation. Family stays 7.
--
-- ----------------------------------------------------------------------------
-- POSTURE RATIONALE — pure declarative RLS; NO functions authored.
--   This migration creates no SECURITY INVOKER or SECURITY DEFINER function — it is
--   CREATE POLICY + GRANT only. The SECURITY DEFINER allowlist is UNCHANGED at 3
--   (ADR-011 Decision 9 — fn_refresh_updated_at + audit-log helper + fn_grant_creator_
--   access; authored so far = 2). Tenant isolation is provided entirely by the two
--   policies' account_users-JOIN predicates evaluated in the caller's RLS context.
--   FORK-2 = A (no UPDATE/DELETE policy): account_trans is append-only audit-class.
--   UPDATE + DELETE are already blocked for ALL roles by 004's row-level
--   fn_account_trans_block_mutation trigger (+ statement-level fn_account_trans_block_
--   truncate + REVOKE TRUNCATE). Those TRIGGERS — not RLS — are the authoritative
--   immutability fence, because service_role BYPASSES RLS but NOT triggers. Adding an
--   explicit UPDATE/DELETE RLS policy would be enforcement-identical to the current
--   default-deny for authenticated and could MISLEAD a reader into thinking RLS is the
--   immutability mechanism. So we omit it: default-deny (no policy) fences authenticated;
--   the 004 triggers fence every role incl. service_role. The GRANT is select, insert
--   only — no update/delete/truncate grant.
--
-- CONTRACT
--   pfin.account_trans (existing table; 004) gains:
--     - account_trans_select — FOR SELECT TO authenticated USING (rd_access-JOIN to
--       account_users). A user reads only transactions of accounts they hold rd_access on.
--     - account_trans_insert — FOR INSERT TO authenticated WITH CHECK (wr_access-JOIN to
--       account_users; mod #3). A user inserts only into accounts they hold wr_access on.
--     - GRANT select, insert ON pfin.account_trans TO authenticated (ACL-before-RLS).
--   Security-load-bearing edges: rd_access at read / wr_access at write (Decision 7
--   Option B + mod #3); default-deny + 004 triggers cover the immutable UPDATE/DELETE/
--   TRUNCATE surface; NO account_users write introduced (mod #1 deferral holds).
-- ============================================================================

create schema if not exists pfin;
grant usage on schema pfin to authenticated;

-- ----------------------------------------------------------------------------
-- pfin.account_trans RLS policies (Lock 3 / Decision 7 Option B). Discharges the
-- 004 deferral ("rd_access/wr_access-JOIN policies land at SELF-190"). Mirrors the
-- 005 reconciliation_event rd_access/wr_access-JOIN shape.
-- ----------------------------------------------------------------------------

-- SELECT: rd_access-JOIN. A user sees a transaction only if they hold an
-- account_users row on its account_id with rd_access = true.
create policy account_trans_select on pfin.account_trans
  for select to authenticated
  using (exists (
    select 1 from pfin.account_users au
    where au.account_id = account_trans.account_id
      and au.users_id = auth.uid()
      and au.rd_access
  ));

comment on policy account_trans_select on pfin.account_trans is
  'Lock 3 / ADR-011 Decision 7 (Option B) SELECT policy: rd_access-JOIN to pfin.account_users. A user reads a transaction only for an account on which they hold an account_users grant with rd_access = true (the row fn_grant_creator_access seeded at account creation, per mod #2). Discharges the 004 deferred-RLS note (SELF-190 / B5). Mirrors the 005 reconciliation_event rd_access shape.';

-- INSERT: wr_access-JOIN WITH CHECK (mod #3 — write uses wr_access, NOT rd_access).
-- A user inserts a transaction only into an account on which they hold wr_access.
create policy account_trans_insert on pfin.account_trans
  for insert to authenticated
  with check (exists (
    select 1 from pfin.account_users au
    where au.account_id = account_trans.account_id
      and au.users_id = auth.uid()
      and au.wr_access
  ));

comment on policy account_trans_insert on pfin.account_trans is
  'Lock 3 / ADR-011 Decision 7 (Option B) INSERT policy: wr_access-JOIN WITH CHECK to pfin.account_users (mod #3 — the write path keys on wr_access, NOT rd_access). A user inserts a transaction only for an account on which they hold an account_users grant with wr_access = true. INSERT is the only mutation authenticated may perform: UPDATE/DELETE are default-denied (no policy) and additionally blocked for ALL roles by 004''s immutability triggers (append-only audit-class).';

-- NO UPDATE / DELETE policy (Fork-2 = A). account_trans is append-only audit-class:
-- UPDATE + DELETE are default-denied for authenticated (no policy) AND blocked for
-- ALL roles (incl. service_role, which bypasses RLS but not triggers) by 004's
-- fn_account_trans_block_mutation / fn_account_trans_block_truncate + REVOKE TRUNCATE.
-- Those triggers are the authoritative immutability fence; an explicit no-op RLS
-- policy would add nothing and could misattribute the mechanism.

-- ACL-before-RLS (PR #106 gotcha): the role needs table-level GRANTs even with RLS
-- on. SELECT + INSERT only — append-only (no update/delete/truncate grant).
grant select, insert on pfin.account_trans to authenticated;
