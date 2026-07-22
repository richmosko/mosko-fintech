-- ============================================================================
-- Migration: pfin aal2 step-up backstop — per-user-conditional MFA enforcement
-- at the DB/RLS layer. Phase 6 Build Loop (SELF-291 / Auth-3b, Slice 1 —
-- ENFORCEMENT unit). F/CTO-ratified 2026-07-21 (see temp/auth-3b-design-spec.md
-- § "RATIFIED — F/CTO 2026-07-21"). Closes Sec's C2 hard gate: the direct data
-- API (PostgREST + public anon key, C6) is reachable, and base RLS checks
-- users_id = auth.uid() but NOT aal — so an aal1 session (password entered,
-- TOTP not completed) could read/write the user's OWN financial rows via the
-- direct API. The app-layer step-up guard enforces NOTHING on that surface;
-- THIS clause is the only layer that actually enforces step-up there.
--
-- WHAT THIS DOES (three parts):
--   (1) ANDs a per-user-conditional aal2 predicate (the "backstop clause") into the
--       RLS of the 14 sensitive tenant-owned pfin tables — into the USING of every
--       authenticated read policy AND into the write policies (INSERT WITH CHECK /
--       UPDATE USING+WITH CHECK / DELETE USING) on the authenticated write paths
--       (ratified reads+writes scope — a stolen-password aal1 attacker must be
--       blocked from destructive WRITES too, not just reads).
--   (2) THE MB-1 GUARD (Sec BLOCK fix, F/CTO-ratified Option A 2026-07-21): a BEFORE
--       UPDATE trigger on pfin.user_settings that blocks LOWERING assurance out of
--       the aal2-capable set unless the session is aal2. Without it the backstop is
--       self-defeating — see MB-1 block below.
--   (3) mfa_policy DOMAIN TIGHTENING (F/CTO-ratified 2026-07-21): restrict the STORED
--       domain from ('none','totp','passkey') to ('none','totp') — defer 'passkey'
--       to Auth-6/SELF-289. Makes the attacker's aal1 lateral totp->passkey flip a
--       DB-rejected invalid value (23514) at the schema layer; the clause + guard
--       keep referencing the full {'totp','passkey'} set so Auth-6 re-adds passkey
--       with ZERO change to them. See PART 3 below.
-- No table or column is created. ONE SECURITY INVOKER trigger function is authored
-- (the MB-1 guard) — it is NOT a SECURITY DEFINER entry, so the DEFINER allowlist is
-- UNCHANGED at 3. The §10 catalogued ledger is UNCHANGED at 3 (RT-22 / RT-26 /
-- RT-27); the Decision-3 family is UNCHANGED (a CHECK tighten touches none).
--
-- ----------------------------------------------------------------------------
-- MB-1 (Sec BLOCK — the backstop's control variable is aal1-settable). The clause
--   reads pfin.user_settings.mfa_policy as its control variable. 024 grants the
--   authenticated tier an unguarded column-level UPDATE and user_settings_update's
--   policy has NO aal gate — so an aal1 attacker on the DIRECT PostgREST API could
--   `PATCH mfa_policy -> 'none'`, after which coalesce(...,'none') not in
--   ('totp','passkey') returns TRUE on ALL 31 policies → full aal1 read+write. 025's
--   clause alone CANNOT fix this: user_settings is excluded from the backstop
--   (clausing it would recurse). Option A (ratified) closes it with a BEFORE UPDATE
--   trigger — see the guard's CONTRACT + POSTURE at the end of this file. Sec's
--   doc-twin F-ADR1 is folded into ADR-029 Decision 5 (fail-open-on-'none' is sound
--   ONLY BECAUSE this guard makes 'none' non-adversarially-settable at aal1).
--
-- THE BACKSTOP CLAUSE (ratified INLINE, COALESCE null-safe — no helper fn):
--   (
--     coalesce(
--       (select s.mfa_policy from pfin.user_settings s where s.users_id = auth.uid()),
--       'none'
--     ) not in ('totp', 'passkey')
--     or (auth.jwt() ->> 'aal') = 'aal2'
--   )
-- Reads: a user who DECLARED mfa_policy 'totp'/'passkey' must present an aal2 JWT;
-- everyone else (mfa_policy 'none', OR NO settings row) is unaffected. It gates on
-- the READER's own policy, never the row — NEVER a blanket aal2 (that would lock
-- out 'none' users). Factor-agnostic over the aal2-capable set: passkey (SELF-289)
-- rides this identical clause with zero change.
--
-- AC-CLAUSE AMENDMENT (empirically required — capability-verify 2026-07-21 on the
-- local PG 17.6 stack): the SELF-291 AC's VERBATIM clause,
--   (select mfa_policy ...) not in ('totp','passkey') or (auth.jwt()->>'aal')='aal2'
-- has a NULL-LOCKOUT BUG. For a user with NO settings row the bare subselect is
-- NULL, and `NULL not in (...)` is NULL (not true) → the row is FILTERED. Because
-- provisioning is LAZY (024 ratified D3), a settings row can be legitimately absent
-- at first read → a brand-new 'none'/un-enrolled user would be locked out of their
-- OWN data at aal1. The ratified fix wraps the subselect in coalesce(...,'none')
-- (probe test T4: missing-row + aal1 → row VISIBLE, as intended). This migration
-- encodes the COALESCE-guarded form; the AC clause text is superseded by it.
--
-- INLINE-vs-HELPER POSTURE (ratified crux; empirically decided): the clause is
-- INLINED into each policy — NOT delivered via a helper function. EXPLAIN on the
-- inline form shows `InitPlan 1` (the user_settings subquery evaluated ONCE per
-- statement — an index scan on user_settings_pkey — not per row). An equivalent
-- STABLE SECURITY INVOKER SQL helper is NOT inlined by the planner because
-- `set search_path=''` (mandatory function discipline) DISABLES SQL-function
-- inlining → it evaluates PER ROW. So inline is both faster (single-eval) AND
-- needs no new DB object (allowlist stays 3 by construction). The DRY cost — the
-- clause repeats across policies — is accepted: for a security predicate, the
-- exact expression being visible in every policy is an auditability feature, not
-- a defect. See temp/auth-3b-design-spec.md §2.2 for the full options table.
--
-- ----------------------------------------------------------------------------
-- MECHANISM: ALTER POLICY (not drop-and-recreate). ALTER POLICY REPLACES the
--   qual/with_check while preserving the policy's identity (name / command / roles
--   / comment). Each ALTER restates the FULL composed predicate
--   `(<existing base predicate, byte-faithful to its source migration>) and (<clause>)`
--   — the base predicate is reproduced EXACTLY from its authoring migration (003 /
--   005 / 006 / 009 / 015 / 016 / 018 / 019 / 022 / 023); it is never dropped or
--   paraphrased. Because ALTER POLICY REPLACES (not appends), a double-apply is
--   idempotent in effect (re-setting the same full expression cannot double-AND).
--   Under `supabase db reset` the target policies already exist (their migrations
--   run 001→024 before this), so the ALTERs are deterministic.
--
-- Numbering: 025 follows 024 (user_settings). Depends on 024 (reads
--   pfin.user_settings) AND on every migration that created a target policy
--   (003 / 005 / 006 / 009 / 015 / 016 / 018 / 019 / 022 / 023). Order-dependent:
--   must run AFTER all of them. No later migration depends on 025 landing first.
--
-- ----------------------------------------------------------------------------
-- POSTURE RATIONALE — SECURITY INVOKER (default per ADR-011 Lock 11); NOT DEFINER.
--   The 31 ALTER POLICY rewrites author NO function (the backstop clause is inlined,
--   never a helper — the helper route was rejected precisely because `set
--   search_path=''` would disable SQL-function inlining → per-row eval). The MB-1
--   guard (part 2) authors exactly ONE function,
--   pfin.fn_user_settings_block_mfa_downgrade, declared SECURITY INVOKER with `set
--   search_path = ''`. It reads ONLY the trigger pseudo-records OLD/NEW, current_user,
--   and auth.jwt() — NO table reads (so NO recursion with the user_settings RLS it
--   guards) and NO elevated privilege. It is therefore NOT a SECURITY DEFINER
--   allowlist entry: the allowlist is UNCHANGED at 3 (ADR-011 Decision 9 / SELF-187:
--   fn_refresh_updated_at + the audit-log insert helper + fn_grant_creator_access).
--   A TRIGGER (not an RLS WITH CHECK) is REQUIRED: the guard must see the OLD->NEW
--   transition, which an RLS WITH CHECK (NEW-only) cannot express — a WITH CHECK on
--   NEW.mfa_policy='none' would also block a 'none' user editing an unrelated (future
--   SELF-232) settings column at aal1. Sec gate = RLS-predicate + the new INVOKER
--   trigger fn joint-review; NOT a DEFINER-allowlist review.
--
-- ----------------------------------------------------------------------------
-- §10 3-AXIS CROSS-CHECK (Path B — reference ADR-011 Decision 4; do NOT restate
-- the catalogued numbered list; Decision 4 read VERBATIM before drafting). This
-- migration introduces ZERO catalogued §10 instances; the ledger stays at 3
-- (RT-22 first / RT-26 second / RT-27 third, per ADR-011 Decision 4 — count moved
-- 2→3 at the ADR-027 amendment (hh) / SELF-212 flip, F/CTO-ratified 2026-07-19).
-- Adding an aal-claim RLS predicate touches NONE of the three catalogued surfaces:
--   (i)   Instance-numbering: unchanged — RT-22 first, RT-26 second, RT-27 third.
--   (ii)  Layer-attribution: unchanged —
--           · RT-22 = the PDF-worker infrastructure-credential-presence layer
--             (no container/infra-credential surface is touched here);
--           · RT-26 = the SUPABASE_SERVICE_ROLE_KEY code-layer allowlist grep fence
--             (no service_role key, and no code-layer surface, is touched — this is
--             a DB-RLS-predicate change under the `authenticated` tier, reading
--             auth.jwt()->>'aal' and pfin.user_settings; service_role is neither
--             granted nor referenced);
--           · RT-27 = the app→worker credential-admission network-exposure/config
--             layer (no admission-endpoint / network-bind surface is touched here).
--   (iii) Verbatim-vs-paraphrase: Decision 4 is linked, not restated.
--   (Forward note: Auth-3b Slice 2's recovery-code REDEMPTION code path MAY, if
--   GoTrue blocks aal1 self-unenroll (capability-verify CV-R1 pending), need a 4th
--   RT-26-adjacent service_role surface — that would be an ADR-016 amendment + Sec
--   review. That is a CODE-layer question for Slice 2, NOT this DDL; the ledger is
--   untouched here.)
--
-- ----------------------------------------------------------------------------
-- DECISION 3 (cross-tenant FK-bypass family) EVALUATION — family count +0
-- (UNCHANGED). This migration adds NO reference column of any kind (no FK, no
-- self-FK, no INTEGER[] array): it only ANDs a predicate into existing policies.
-- The inline subselect reads pfin.user_settings keyed on the tenant anchor
-- (users_id = auth.uid()) — an own-row read, not a cross-tenant reference. Family
-- UNCHANGED. (Stated explicitly per the mandatory FK-shaped-column check.)
--
-- ----------------------------------------------------------------------------
-- AC#6 ISOLATION INVARIANT (documented here as a canonical anchor). Tenant
--   isolation = the UNIVERSAL RLS predicate users_id = auth.uid() (direct-owner) or
--   its rd_access/wr_access-JOIN equivalent, enforced on every table INDEPENDENT of
--   MFA. This backstop is ORTHOGONAL to tenant isolation: it bounds ONLY a user's
--   OWN step-up risk (whether THEIR session must be aal2 to touch THEIR OWN rows). A
--   user's mfa_policy can NEVER weaken another tenant's fence — the aal2 conjunct is
--   ANDed with (never replaces) the pre-existing tenant predicate, so cross-tenant
--   access still fails closed at every aal. MFA strength ⟂ tenant isolation.
--
-- LAYER-POSTURE ASYMMETRY (deliberate). This DB backstop FAILS OPEN on a
--   missing/'none' policy (coalesce → 'none' → clause true → reads/writes allowed) —
--   because the universal tenant RLS still fully fences the user, and the backstop
--   enforces only the POSITIVE assertion "this user DECLARED totp/passkey." The
--   app-layer step-up guard (Auth-3b Backend, hooks.server.ts) is the COMPLEMENT: it
--   FAILS CLOSED on indeterminate state (unknown/missing MFA state ⇒ requires
--   step-up). Two layers, two postures, on purpose.
--
-- ----------------------------------------------------------------------------
-- TARGET SET (14 tenant-owned tables; verified against the LIVE schema, migrations
--   001–024, NOT the memo). EXCLUSIONS (deliberate, not oversight):
--     - pfin.tax_character         — global shared-read value-registry (using(true),
--                                    ADR-024); not tenant data.
--     - pfin.user_settings         — the backstop's OWN substrate; ANDing the clause
--                                    here would make the clause's subselect recurse
--                                    into a policy that reads user_settings
--                                    (`infinite recursion detected in policy`).
--                                    NON-NEGOTIABLE exclusion.
--     - pfin.linked_source_sync_audit — RLS-enabled but ZERO authenticated policy
--                                    (default-deny; service_role-only, RLS-bypassing).
--                                    Not an authenticated surface → nothing to clause.
--   Per-table write scope is stated inline below: where a table has NO authenticated
--   write policy (service_role sole writer, or a DEFINER trigger, or V1 write-dormant),
--   there is nothing to clause on the write side — stated explicitly per table.
--
-- ----------------------------------------------------------------------------
-- QA PAIRING (same-milestone; SECURITY §4.5 two-tenant + the aal dimension). The
--   pgTAP battery (QA-authored) must assert, on representative tables: totp-user +
--   aal1 → refused at the DB (0 rows on read; write fails closed); same user + aal2
--   → passes; 'none'/missing-row user + aal1 → passes (NOT-blanket proof);
--   cross-tenant still fails closed at EVERY aal (isolation ⟂ MFA). Architect does
--   not author tests/; Sec sign-off gates the V1-SHIP-BLOCK merge.
-- ============================================================================

create schema if not exists pfin;

-- ============================================================================
-- account (003) — direct-owner. Authenticated read + write (insert/update).
-- ============================================================================
alter policy account_select on pfin.account
  using (
    (users_id = auth.uid())
    and (
      coalesce((select s.mfa_policy from pfin.user_settings s where s.users_id = auth.uid()), 'none') not in ('totp', 'passkey')
      or (auth.jwt() ->> 'aal') = 'aal2'
    )
  );

alter policy account_insert on pfin.account
  with check (
    (users_id = auth.uid())
    and (
      coalesce((select s.mfa_policy from pfin.user_settings s where s.users_id = auth.uid()), 'none') not in ('totp', 'passkey')
      or (auth.jwt() ->> 'aal') = 'aal2'
    )
  );

alter policy account_update on pfin.account
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
-- account has NO authenticated DELETE policy (is_active soft-delete) — nothing to clause.

-- ============================================================================
-- account_users (003) — direct-owner SELECT only. Authenticated writes are
-- default-denied (the fn_grant_creator_access DEFINER trigger is the SOLE writer);
-- there is NO authenticated INSERT/UPDATE/DELETE policy to clause.
-- ============================================================================
alter policy account_users_select on pfin.account_users
  using (
    (users_id = auth.uid())
    and (
      coalesce((select s.mfa_policy from pfin.user_settings s where s.users_id = auth.uid()), 'none') not in ('totp', 'passkey')
      or (auth.jwt() ->> 'aal') = 'aal2'
    )
  );

-- ============================================================================
-- account_trans (006) — rd_access/wr_access-JOIN. Append-only audit-class:
-- authenticated SELECT + INSERT only (UPDATE/DELETE trigger-blocked for all roles).
-- ============================================================================
alter policy account_trans_select on pfin.account_trans
  using (
    (exists (
      select 1 from pfin.account_users au
      where au.account_id = account_trans.account_id
        and au.users_id = auth.uid()
        and au.rd_access
    ))
    and (
      coalesce((select s.mfa_policy from pfin.user_settings s where s.users_id = auth.uid()), 'none') not in ('totp', 'passkey')
      or (auth.jwt() ->> 'aal') = 'aal2'
    )
  );

alter policy account_trans_insert on pfin.account_trans
  with check (
    (exists (
      select 1 from pfin.account_users au
      where au.account_id = account_trans.account_id
        and au.users_id = auth.uid()
        and au.wr_access
    ))
    and (
      coalesce((select s.mfa_policy from pfin.user_settings s where s.users_id = auth.uid()), 'none') not in ('totp', 'passkey')
      or (auth.jwt() ->> 'aal') = 'aal2'
    )
  );

-- ============================================================================
-- account_trans_annotation (023) — parent-FK-chain (trans → account_users).
-- MUTABLE overlay: authenticated SELECT + INSERT + UPDATE + DELETE.
-- ============================================================================
alter policy ata_select on pfin.account_trans_annotation
  using (
    (exists (
      select 1
      from pfin.account_trans t
      join pfin.account_users au on au.account_id = t.account_id
      where t.trans_id = account_trans_annotation.trans_id
        and au.users_id = auth.uid()
        and au.rd_access
    ))
    and (
      coalesce((select s.mfa_policy from pfin.user_settings s where s.users_id = auth.uid()), 'none') not in ('totp', 'passkey')
      or (auth.jwt() ->> 'aal') = 'aal2'
    )
  );

alter policy ata_insert on pfin.account_trans_annotation
  with check (
    (exists (
      select 1
      from pfin.account_trans t
      join pfin.account_users au on au.account_id = t.account_id
      where t.trans_id = account_trans_annotation.trans_id
        and au.users_id = auth.uid()
        and au.wr_access
    ))
    and (
      coalesce((select s.mfa_policy from pfin.user_settings s where s.users_id = auth.uid()), 'none') not in ('totp', 'passkey')
      or (auth.jwt() ->> 'aal') = 'aal2'
    )
  );

alter policy ata_update on pfin.account_trans_annotation
  using (
    (exists (
      select 1
      from pfin.account_trans t
      join pfin.account_users au on au.account_id = t.account_id
      where t.trans_id = account_trans_annotation.trans_id
        and au.users_id = auth.uid()
        and au.wr_access
    ))
    and (
      coalesce((select s.mfa_policy from pfin.user_settings s where s.users_id = auth.uid()), 'none') not in ('totp', 'passkey')
      or (auth.jwt() ->> 'aal') = 'aal2'
    )
  )
  with check (
    (exists (
      select 1
      from pfin.account_trans t
      join pfin.account_users au on au.account_id = t.account_id
      where t.trans_id = account_trans_annotation.trans_id
        and au.users_id = auth.uid()
        and au.wr_access
    ))
    and (
      coalesce((select s.mfa_policy from pfin.user_settings s where s.users_id = auth.uid()), 'none') not in ('totp', 'passkey')
      or (auth.jwt() ->> 'aal') = 'aal2'
    )
  );

alter policy ata_delete on pfin.account_trans_annotation
  using (
    (exists (
      select 1
      from pfin.account_trans t
      join pfin.account_users au on au.account_id = t.account_id
      where t.trans_id = account_trans_annotation.trans_id
        and au.users_id = auth.uid()
        and au.wr_access
    ))
    and (
      coalesce((select s.mfa_policy from pfin.user_settings s where s.users_id = auth.uid()), 'none') not in ('totp', 'passkey')
      or (auth.jwt() ->> 'aal') = 'aal2'
    )
  );

-- ============================================================================
-- reconciliation_event (005) — rd_access/wr_access-JOIN. Append-only:
-- authenticated SELECT + INSERT only (UPDATE/DELETE trigger-blocked for all roles).
-- ============================================================================
alter policy reconciliation_event_select on pfin.reconciliation_event
  using (
    (exists (
      select 1 from pfin.account_users au
      where au.account_id = reconciliation_event.account_id
        and au.users_id = auth.uid()
        and au.rd_access
    ))
    and (
      coalesce((select s.mfa_policy from pfin.user_settings s where s.users_id = auth.uid()), 'none') not in ('totp', 'passkey')
      or (auth.jwt() ->> 'aal') = 'aal2'
    )
  );

alter policy reconciliation_event_insert on pfin.reconciliation_event
  with check (
    (exists (
      select 1 from pfin.account_users au
      where au.account_id = reconciliation_event.account_id
        and au.users_id = auth.uid()
        and au.wr_access
    ))
    and (
      coalesce((select s.mfa_policy from pfin.user_settings s where s.users_id = auth.uid()), 'none') not in ('totp', 'passkey')
      or (auth.jwt() ->> 'aal') = 'aal2'
    )
  );

-- ============================================================================
-- reconciliation_event_trans (005) — parent-FK-chain (reconciliation_event →
-- account_users). Append-only: authenticated SELECT + INSERT only.
-- ============================================================================
alter policy reconciliation_event_trans_select on pfin.reconciliation_event_trans
  using (
    (exists (
      select 1
      from pfin.reconciliation_event re
      join pfin.account_users au on au.account_id = re.account_id
      where re.event_id = reconciliation_event_trans.event_id
        and au.users_id = auth.uid()
        and au.rd_access
    ))
    and (
      coalesce((select s.mfa_policy from pfin.user_settings s where s.users_id = auth.uid()), 'none') not in ('totp', 'passkey')
      or (auth.jwt() ->> 'aal') = 'aal2'
    )
  );

alter policy reconciliation_event_trans_insert on pfin.reconciliation_event_trans
  with check (
    (exists (
      select 1
      from pfin.reconciliation_event re
      join pfin.account_users au on au.account_id = re.account_id
      where re.event_id = reconciliation_event_trans.event_id
        and au.users_id = auth.uid()
        and au.wr_access
    ))
    and (
      coalesce((select s.mfa_policy from pfin.user_settings s where s.users_id = auth.uid()), 'none') not in ('totp', 'passkey')
      or (auth.jwt() ->> 'aal') = 'aal2'
    )
  );

-- ============================================================================
-- holdings_checkpoint (005) — rd_access-JOIN SELECT only. NO authenticated write
-- policy (service_role is the sole RLS-bypassing writer; UPDATE/DELETE trigger-
-- blocked for all roles) — nothing to clause on the write side.
-- ============================================================================
alter policy holdings_checkpoint_select on pfin.holdings_checkpoint
  using (
    (exists (
      select 1 from pfin.account_users au
      where au.account_id = holdings_checkpoint.account_id
        and au.users_id = auth.uid()
        and au.rd_access
    ))
    and (
      coalesce((select s.mfa_policy from pfin.user_settings s where s.users_id = auth.uid()), 'none') not in ('totp', 'passkey')
      or (auth.jwt() ->> 'aal') = 'aal2'
    )
  );

-- ============================================================================
-- account_balance_checkpoint (018) — rd_access-JOIN SELECT only. NO authenticated
-- write policy (service_role sole writer; UPDATE/DELETE trigger-blocked) — nothing
-- to clause on the write side.
-- ============================================================================
alter policy account_balance_checkpoint_select on pfin.account_balance_checkpoint
  using (
    (exists (
      select 1 from pfin.account_users au
      where au.account_id = account_balance_checkpoint.account_id
        and au.users_id = auth.uid()
        and au.rd_access
    ))
    and (
      coalesce((select s.mfa_policy from pfin.user_settings s where s.users_id = auth.uid()), 'none') not in ('totp', 'passkey')
      or (auth.jwt() ->> 'aal') = 'aal2'
    )
  );

-- ============================================================================
-- asset (016) — HYBRID global-OR-owned. SELECT reads global (users_id IS NULL) OR
-- own rows; INSERT/UPDATE/DELETE are own-row only (SELF-201 write path). The clause
-- gates the READER's mfa_policy, not the row: a totp reader is either aal2 (sees
-- global + own) or aal1 (sees nothing) — no partial-leak path via the global rows.
-- ============================================================================
alter policy asset_select on pfin.asset
  using (
    (users_id is null or users_id = auth.uid())
    and (
      coalesce((select s.mfa_policy from pfin.user_settings s where s.users_id = auth.uid()), 'none') not in ('totp', 'passkey')
      or (auth.jwt() ->> 'aal') = 'aal2'
    )
  );

alter policy asset_insert on pfin.asset
  with check (
    (users_id = auth.uid())
    and (
      coalesce((select s.mfa_policy from pfin.user_settings s where s.users_id = auth.uid()), 'none') not in ('totp', 'passkey')
      or (auth.jwt() ->> 'aal') = 'aal2'
    )
  );

alter policy asset_update on pfin.asset
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

alter policy asset_delete on pfin.asset
  using (
    (users_id = auth.uid())
    and (
      coalesce((select s.mfa_policy from pfin.user_settings s where s.users_id = auth.uid()), 'none') not in ('totp', 'passkey')
      or (auth.jwt() ->> 'aal') = 'aal2'
    )
  );

-- ============================================================================
-- eod_price (019) — asset-anchored. SELECT reads prices for global-OR-owned assets;
-- INSERT/UPDATE/DELETE are manual_valuation-on-own-asset only (OWD-E write gate).
-- The base source='manual_valuation' + own-asset predicate is preserved EXACTLY.
-- ============================================================================
alter policy eod_price_select on pfin.eod_price
  using (
    (exists (
      select 1 from pfin.asset a
      where a.asset_id = eod_price.asset_id
        and (a.users_id is null or a.users_id = auth.uid())
    ))
    and (
      coalesce((select s.mfa_policy from pfin.user_settings s where s.users_id = auth.uid()), 'none') not in ('totp', 'passkey')
      or (auth.jwt() ->> 'aal') = 'aal2'
    )
  );

alter policy eod_price_insert on pfin.eod_price
  with check (
    (
      source = 'manual_valuation'
      and exists (select 1 from pfin.asset a
                  where a.asset_id = eod_price.asset_id and a.users_id = auth.uid())
    )
    and (
      coalesce((select s.mfa_policy from pfin.user_settings s where s.users_id = auth.uid()), 'none') not in ('totp', 'passkey')
      or (auth.jwt() ->> 'aal') = 'aal2'
    )
  );

alter policy eod_price_update on pfin.eod_price
  using (
    (
      source = 'manual_valuation'
      and exists (select 1 from pfin.asset a
                  where a.asset_id = eod_price.asset_id and a.users_id = auth.uid())
    )
    and (
      coalesce((select s.mfa_policy from pfin.user_settings s where s.users_id = auth.uid()), 'none') not in ('totp', 'passkey')
      or (auth.jwt() ->> 'aal') = 'aal2'
    )
  )
  with check (
    (
      source = 'manual_valuation'
      and exists (select 1 from pfin.asset a
                  where a.asset_id = eod_price.asset_id and a.users_id = auth.uid())
    )
    and (
      coalesce((select s.mfa_policy from pfin.user_settings s where s.users_id = auth.uid()), 'none') not in ('totp', 'passkey')
      or (auth.jwt() ->> 'aal') = 'aal2'
    )
  );

alter policy eod_price_delete on pfin.eod_price
  using (
    (
      source = 'manual_valuation'
      and exists (select 1 from pfin.asset a
                  where a.asset_id = eod_price.asset_id and a.users_id = auth.uid())
    )
    and (
      coalesce((select s.mfa_policy from pfin.user_settings s where s.users_id = auth.uid()), 'none') not in ('totp', 'passkey')
      or (auth.jwt() ->> 'aal') = 'aal2'
    )
  );

-- ============================================================================
-- linked_source (015) — direct-owner SELECT only. NO authenticated write policy
-- (service_role is the sole writer, privileged-context-write Decision 1) — nothing
-- to clause on the write side. (The SELECT is a COLUMN-LEVEL grant excluding the
-- Vault credential handle; the clause does not affect column-level ACL.)
-- ============================================================================
alter policy linked_source_select on pfin.linked_source
  using (
    (users_id = auth.uid())
    and (
      coalesce((select s.mfa_policy from pfin.user_settings s where s.users_id = auth.uid()), 'none') not in ('totp', 'passkey')
      or (auth.jwt() ->> 'aal') = 'aal2'
    )
  );

-- ============================================================================
-- linked_source_state_history (015) — source-FK-chain SELECT only. Immutable
-- audit-class; NO authenticated write policy (service_role sole writer) — nothing
-- to clause on the write side.
-- ============================================================================
alter policy linked_source_state_history_select on pfin.linked_source_state_history
  using (
    (exists (
      select 1 from pfin.linked_source ls
      where ls.source_id = linked_source_state_history.source_id
        and ls.users_id = auth.uid()
    ))
    and (
      coalesce((select s.mfa_policy from pfin.user_settings s where s.users_id = auth.uid()), 'none') not in ('totp', 'passkey')
      or (auth.jwt() ->> 'aal') = 'aal2'
    )
  );

-- ============================================================================
-- user_asset_category (022) — direct-owner. Full authenticated CRUD.
-- ============================================================================
alter policy uac_select on pfin.user_asset_category
  using (
    (users_id = auth.uid())
    and (
      coalesce((select s.mfa_policy from pfin.user_settings s where s.users_id = auth.uid()), 'none') not in ('totp', 'passkey')
      or (auth.jwt() ->> 'aal') = 'aal2'
    )
  );

alter policy uac_insert on pfin.user_asset_category
  with check (
    (users_id = auth.uid())
    and (
      coalesce((select s.mfa_policy from pfin.user_settings s where s.users_id = auth.uid()), 'none') not in ('totp', 'passkey')
      or (auth.jwt() ->> 'aal') = 'aal2'
    )
  );

alter policy uac_update on pfin.user_asset_category
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

alter policy uac_delete on pfin.user_asset_category
  using (
    (users_id = auth.uid())
    and (
      coalesce((select s.mfa_policy from pfin.user_settings s where s.users_id = auth.uid()), 'none') not in ('totp', 'passkey')
      or (auth.jwt() ->> 'aal') = 'aal2'
    )
  );

-- ============================================================================
-- user_taxonomy (009) — direct-owner SELECT only (V1 write-dormant: no
-- authenticated INSERT/UPDATE/DELETE grant or policy) — nothing to clause on the
-- write side.
-- ============================================================================
alter policy user_taxonomy_select on pfin.user_taxonomy
  using (
    (users_id = auth.uid())
    and (
      coalesce((select s.mfa_policy from pfin.user_settings s where s.users_id = auth.uid()), 'none') not in ('totp', 'passkey')
      or (auth.jwt() ->> 'aal') = 'aal2'
    )
  );

-- ============================================================================
-- PART 2 — MB-1 GUARD: block aal1 downgrade of the backstop's control variable.
-- (Sec BLOCK fix; F/CTO-ratified Option A 2026-07-21.)
--
-- CONTRACT
--   pfin.fn_user_settings_block_mfa_downgrade() RETURNS trigger — a BEFORE UPDATE
--     FOR EACH ROW guard on pfin.user_settings. RAISES insufficient_privilege
--     (SQLSTATE 42501) iff ALL of:
--       (a) current_user = 'authenticated'  — the untrusted DIRECT-API tier ONLY.
--           service_role (the Slice-2 server-side recovery downgrade, invariant 1/2b)
--           and postgres (admin / seed / migration) are NOT gated — they carry no aal
--           JWT and MUST remain able to downgrade; and
--       (b) OLD.mfa_policy IN ('totp','passkey')  — the row was in the aal2-capable
--           (backstop-gated) set; and
--       (c) NEW.mfa_policy NOT IN ('totp','passkey')  — the update LEAVES that set
--           (the load-bearing case is -> 'none'). This mirrors the backstop's gated
--           set EXACTLY; and
--       (d) the session is not aal2  (coalesce(auth.jwt()->>'aal','') <> 'aal2').
--   "WEAKEN" is defined as leaving the aal2-capable set {'totp','passkey'}. NOT
--     weakenings (all FREE at aal1): enrollment 'none'->'totp'/'passkey' (a user must
--     turn MFA on before they can ever reach aal2); lateral 'totp'<->'passkey' (both
--     aal2-capable + assurance-neutral — a lateral move never changes whether the row
--     is backstop-gated); and any UPDATE that does not change mfa_policy (e.g. a
--     future SELF-232 settings-column edit).
--   The aal2 self-service disable ('totp'/'passkey' -> 'none' at aal2; Slice-2
--     invariant 2a) passes via (d) directly — standard GoTrue unenroll-at-aal2, no
--     server process, no backup code.
--   Security-load-bearing edges: SECURITY INVOKER (current_user reflects the real
--     calling tier); reads OLD/NEW/current_user/auth.jwt() only — NO table read, so
--     no recursion with the user_settings RLS; set search_path=''. NOT a DEFINER
--     entry (allowlist stays 3). No DELETE vector to guard: 024 grants authenticated
--     no DELETE (ACL) and defines no DELETE policy (RLS) on user_settings, and
--     service_role is ungranted — the only DELETE is the auth.users cascade (postgres).
--     ON CONFLICT DO UPDATE upserts fire BEFORE UPDATE triggers, so the upsert-
--     downgrade vector is covered too.
-- ============================================================================
create or replace function pfin.fn_user_settings_block_mfa_downgrade()
  returns trigger
  language plpgsql
  security invoker
  set search_path = ''
as $$
begin
  -- Block a downgrade OUT of the aal2-capable set, on the authenticated tier, unless
  -- the session is aal2. Enrollment + lateral moves + non-mfa edits fall through.
  if current_user = 'authenticated'
     and old.mfa_policy in ('totp', 'passkey')
     and new.mfa_policy not in ('totp', 'passkey')
     and coalesce(auth.jwt() ->> 'aal', '') <> 'aal2'
  then
    raise exception using
      errcode = 'insufficient_privilege',
      message = 'mfa_policy downgrade out of a step-up factor requires an aal2 session (MB-1 backstop-integrity guard)';
  end if;
  return new;
end;
$$;

comment on function pfin.fn_user_settings_block_mfa_downgrade() is
  'MB-1 backstop-integrity guard (SELF-291 / Auth-3b Slice 1, migration 025; F/CTO '
  'Option A 2026-07-21). BEFORE UPDATE on pfin.user_settings: blocks the authenticated '
  'tier from lowering mfa_policy OUT of the aal2-capable set {totp,passkey} unless the '
  'session is aal2 — closing the aal1 self-downgrade that would otherwise defeat the '
  '025 aal2 backstop (whose control variable is mfa_policy). SECURITY INVOKER; reads '
  'OLD/NEW/current_user/auth.jwt() only (no table read → no recursion); NOT a DEFINER '
  'allowlist entry (stays 3). Enrollment (none->totp/passkey), lateral totp<->passkey, '
  'and the aal2 self-service disable all pass; service_role (Slice-2 recovery) + '
  'postgres are not gated (they carry no aal JWT and are the trusted downgrade channel).';

create trigger user_settings_block_mfa_downgrade
  before update on pfin.user_settings
  for each row execute function pfin.fn_user_settings_block_mfa_downgrade();

-- ============================================================================
-- PART 3 — mfa_policy DOMAIN TIGHTENING: defer 'passkey' out of the V1 stored domain.
-- (F/CTO-ratified 2026-07-21 — caught via an F/CTO design question.)
--
-- 024 (shipped on main) declared `check (mfa_policy in ('none','totp','passkey'))`.
-- V1 restricts the STORED domain to ('none','totp'). Rationale: the totp-vs-passkey
-- distinction is UNUSED for enforcement in V1 (aal2 is factor-agnostic — the backstop
-- gates on aal, not factor type); the legitimate app only ever offers none|totp until
-- Auth-6; and 'passkey' being a LEGAL value was the ONLY thing that made an attacker's
-- aal1 lateral totp->passkey flip possible. Tightening turns that flip into a
-- DB-rejected invalid value (SQLSTATE 23514) at the SCHEMA layer — below the guard —
-- so the lateral-flip concern vanishes structurally, not just behaviorally.
--
-- INTERACTION WITH THE GUARD (PART 2), confirmed: for an aal1 authenticated
--   totp->passkey UPDATE, the BEFORE UPDATE guard sees new='passkey' IN {'totp',
--   'passkey'} → it does NOT raise (not a weakening) → the CHECK then rejects
--   'passkey' with 23514. For totp->none at aal1 the guard still raises
--   insufficient_privilege (42501) first. Net: the only legal downgrade remains
--   totp->none (blocked at aal1); lateral is now impossible. The guard is UNCHANGED.
--
-- SAFE ALTER (greenfield): no existing 'passkey' row can exist — 024 defaults 'none',
--   the app never sets 'passkey', and no seed/migration inserts one (verified) — so
--   the re-validated tighter CHECK cannot fail on existing data.
--
-- FORWARD-COMPAT (NOT a one-way door): 'passkey' re-adds ADDITIVELY at Auth-6 /
--   SELF-289 via a one-line CHECK widen (ADR-022 additive). Crucially, the 025
--   backstop clause AND the MB-1 guard both keep referencing the FULL {'totp',
--   'passkey'} set internally (UNCHANGED) — so re-adding 'passkey' to the domain needs
--   ZERO change to either. Best-of-both: the stored value can't be 'passkey' in V1
--   (CHECK), but nothing about the enforcement machinery has to move at Auth-6.
--
-- LEDGERS FLAT: a CHECK-constraint tighten authors no function, no RLS change, no
--   reference column — §10 stays 3 (RT-22/RT-26/RT-27, none touched); DEFINER stays
--   3; Decision-3 unchanged.
-- ============================================================================
alter table pfin.user_settings
  drop constraint if exists user_settings_mfa_policy_check;
alter table pfin.user_settings
  add constraint user_settings_mfa_policy_check check (mfa_policy in ('none', 'totp'));

comment on column pfin.user_settings.mfa_policy is
  'Per-user MFA choice. V1 STORED domain = text NOT NULL DEFAULT ''none'' CHECK IN '
  '(''none'',''totp'') — ''passkey'' DEFERRED to Auth-6/SELF-289 (025 PART 3, F/CTO '
  '2026-07-21; tightened from 024''s (''none'',''totp'',''passkey'')). ''email'' was '
  'DROPPED from the ratified model. TEXT+CHECK per ADR-022 (behavior lives in code — '
  'the app-layer guard + the 025 aal2 backstop — no per-value metadata; ADR-024 '
  'promote-to-registry available if that changes). The 025 backstop clause + the MB-1 '
  'downgrade guard reference the full {''totp'',''passkey''} aal2-capable set so Auth-6 '
  're-adds ''passkey'' additively with ZERO change to them. A missing row reads as '
  '''none'' (lazy provisioning). Adding values later is a cheap additive CHECK alter — '
  'not a one-way door.';
