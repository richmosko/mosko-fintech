-- ============================================================================
-- Migration: pfin.nav_daily — precomputed per-user daily net-worth checkpoint
--   (the §2.1.2 net-worth-trend substrate). One row per (user, day) = the frozen
--   NAV computed at that day's close. Append-only audit-class: written ONLY by the
--   W-1 cron worker (writes execute AS service_role via SET LOCAL ROLE — see the
--   WRITE-PATH CREDENTIAL MODEL block below), read by the owning user.
--   Linear SELF-214 (V1.1 "Net worth full"). F/CTO-ratified 2026-08-02: Option B
--   (precomputed table) + W-1 worker model (session-impersonation reusing the
--   locked INVOKER fn_compute_nav) + uuid users_id + forward-only + numbering 054.
--   Design package temp/self214-230-design-package.md; ADR-040 (this PR).
--   apply-migration procedure applied. JOINT-REVIEW-MANDATORY (Sec veto surface):
--   tenant-scoped financial data + new RLS + immutability triggers + the worker
--   tenant-binding (AC7).
--
-- ----------------------------------------------------------------------------
-- AMENDED IN PLACE 2026-08-02 (NOT a drop-replace; NOT an edited-live-migration
--   violation). This file gained the write-tenant binding fence (B7 (c′)) + the
--   corrected credential-model language (B1) AFTER Sec's joint-review v1/v2/v3, on
--   the SAME unmerged branch (feature/214-nav-daily). 054 has NEVER been merged to
--   main and has NEVER been applied to any environment — local, CI, or production
--   (V1 is greenfield per ADR-021; no deployed database exists to have received it).
--   There is therefore no applied state to drop-replace and no migration-ordering
--   contract to preserve: amending in place is the CORRECT shape, and adding a
--   follow-on migration to patch an unapplied 054 would leave a permanent two-file
--   scar recording a review round that never reached an environment. (Do NOT
--   confuse this with migration 055 — 055 exists, but it creates the cluster-level
--   `pfin_etl` LOGIN role and patches nothing in this file; it is a separate
--   concern with a separate lifecycle, which is exactly why it is its own
--   migration rather than more amendment here.) A future reader must NOT read
--   this as the drop-replace discipline (docs/MILESTONE-FRAMING.md) being skipped —
--   that discipline binds migrations that HAVE been applied somewhere. Sec's
--   joint-review dispositions this amendment discharges: B1 (credential model),
--   B7 (c′) (write-tenant binding fence), and the RT-28→RT-31 slot correction.
--
-- ----------------------------------------------------------------------------
-- WRITE-PATH CREDENTIAL MODEL (B1 — F/CTO-ratified 2026-08-02; the ADR-023 /
--   workers/provider-sync precedent, now extended to workers/etl). Stated up front
--   because every privilege claim below depends on it:
--     LOGIN role  = `pfin_etl` — a DEDICATED NOINHERIT broker created at migration
--                   055 (rolinherit = f, rolcanlogin = t, NOT superuser, NOT
--                   BYPASSRLS, NOT the pfin owner, owns nothing, holds NO direct
--                   table privilege; member of `service_role` + `authenticated` so
--                   the W-1 impersonation and the privileged append both work under
--                   it). Ratified at ADR-041 (Sec joint-review B8, option (B)) —
--                   NOT provider-sync's shared `authenticator`, so the ETL is
--                   independently revocable and independently rotatable.
--     WRITE role  = `service_role` — reached via `SET LOCAL ROLE service_role`
--                   inside the transaction, per ADR-023's write role-of-record.
--   `service_role` has rolcanlogin = f — it can NEVER be a direct-Postgres login
--   identity. Any "the worker CONNECTS AS service_role" phrasing (which this header
--   previously carried, and which Sec's B1 caught) names a transport-impossible
--   role. The correct framing is: it LOGS IN as `pfin_etl` and WRITES AS
--   `service_role`. Corrected here + in ADR-040; workers/etl docstrings + .env.example
--   are Backend's half of the same fix.
--   WHY THIS MAKES THIS FILE'S FENCES REAL (measured live under the production role,
--   read-only / rolled-back):
--     · `grant insert on pfin.nav_daily to service_role` (below) is LOAD-BEARING
--       exactly as claimed — under this model it is the privilege that admits the
--       write, not table ownership. UPDATE as service_role is denied at the ACL
--       before any trigger is consulted.
--     · `service_role` is NEITHER the table owner NOR superuser, so it can neither
--       `ALTER TABLE … DISABLE TRIGGER` (denied — must be owner) nor set
--       `session_replication_role` (denied). The append-only fences below are
--       therefore UN-BYPASSABLE BY THE WRITER.
--     · Under an owner-class login (e.g. `postgres`) every one of those inverts:
--       the grant goes inert (ownership authorizes the write) and BOTH trigger-
--       bypass mechanisms succeed (reproduced live — `session_replication_role =
--       'replica'` then an owner UPDATE mutated a row). That is the outcome this
--       decision exists to avoid; see SECURITY §4.4 SD-24 + §4.5 RT-31 (c-i)/(c-ii).
--   ADR-011 Decision 1 clause (b) ("writes execute under service_role") is satisfied
--   LITERALLY under this model — Sec's interim "violated in the letter" ruling was
--   withdrawn at joint-review v3. Clause (d) is NOT satisfied; see ADR-040's named
--   D1(d) deferral (the audit-log helper is dependency-blocked, not skipped).
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
--   ⚠ SUPERSEDED IN PART at SELF-217 (F/CTO ratify 2026-08-12; ADR-053; catalog
--   half issued as migration 068). THE PARAGRAPH ABOVE IS LEFT INTACT ON PURPOSE
--   — it records what was ratified on 2026-08-02, and rewriting a ratified record
--   destroys the evidence of what was believed when. Read it together with this:
--     · STILL TRUE, and the amendment does not touch it: no RECOMPUTED history.
--       A past active-only NAV is unsound and a seeded backfill via
--       fn_compute_nav(d, false) remains UNAUTHORIZED. 050's TEMPORAL CONSTRAINT
--       above stands unchanged.
--     · NO LONGER TRUE: "no historical backfill" as a blanket statement.
--       Externally-measured NAV may be IMPORTED at nav_dates preceding the first
--       cron checkpoint, landing at month-end.
--   >> THE DISTINCTION IS PROVENANCE, NOT DATES. The forward-only rule was a rule
--      against FABRICATION, not against IMPORT — 062's header records the hazard
--      it was guarding: the valuation path values an unpriced asset at zero
--      silently, so a RECOMPUTED historical point is a confident, plausible,
--      wrong number. An IMPORTED figure was measured contemporaneously by the
--      system that held the positions and carries none of that. <<
--   Whoever reads only the paragraph above will conclude the import is forbidden.
--   That is the misreading this note exists to prevent, and it is why ADR-053
--   exists rather than a one-line edit.
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
-- POSTURE RATIONALE — allowlist STAYS 4 (ADR-011 Decision 9, read verbatim
--   2026-08-02: committed allowlist = 4 = fn_refresh_updated_at + fn_grant_creator_
--   access + fn_reclass_history_insert + the reserved, still-unauthored general
--   audit-log insert helper; authored so far = 3). ZERO new SECURITY DEFINER — this
--   migration authors THREE functions and ALL THREE are SECURITY INVOKER: both
--   immutability triggers AND the new write-tenant binding fence
--   (fn_nav_daily_assert_computed_for, added by this amendment). Each reads no table
--   and needs no elevated privilege — they only read a transaction-local GUC and
--   raise, exactly like 004's fences: keeping them INVOKER means they do NOT touch
--   the DEFINER allowlist. The W-1 worker model (F/CTO-ratified)
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
--         admission network/config surface. The W-1 worker reaches Postgres over a
--         DIRECT connection (TenantBoundConnection) — logging in as `pfin_etl`
--         and writing AS service_role via SET LOCAL ROLE (see WRITE-PATH CREDENTIAL
--         MODEL) — so it holds no SUPABASE_SERVICE_ROLE_KEY and is already off the
--         RT-26 code-layer allowlist (same posture as eod_price/019 + the scheduled-
--         poll worker + workers/provider-sync). The B1 correction is a correction to
--         WHICH ROLE IS NAMED, not a re-attribution of any catalogued instance's
--         layer: RT-22 / RT-26 / RT-27 attributions are UNCHANGED, and the Decision-4
--         per-surface layer-composition language is UNCHANGED — nothing becomes
--         "four-layer."
--   (iii) Verbatim-vs-paraphrase: Decision 4 linked, not restated. 054 not the anchor.
--   NOTE (de-conflation guard): NEITHER trigger class here is a §10 catalogued
--   instance. (1) The append-only cross-tier immutability triggers are a Decision-2
--   AUDIT-CLASS mechanism (same separation as 004's fences). (2) The write-tenant
--   binding fence added by this amendment (B7 (c′)) is a DB-LAYER reinforcement of
--   ADR-011 Decision 1 clause (c) — it gives the database its own proof of write-
--   tenant correctness where previously only the app-layer TenantBoundConnection
--   assertion existed. It composes with Decision 4's defense-in-depth DISCIPLINE but
--   adds NO entry to the catalogued numbered list and adds NO layer to any listed
--   instance. SD/RT SECURITY-doc additions (SD-24 + RT-31, both landed by Sec at the
--   2026-08-02 joint-review) are §4.4/§4.5 catalog growth, ALSO not a §10 ledger
--   change. The §10 ledger is untouched at 3.
--
-- ----------------------------------------------------------------------------
-- DECISION 3 (cross-tenant FK-bypass family) — family UNCHANGED (+0). Read
--   verbatim 2026-08-02: the canonical family is FIFTEEN LABELED instances (#1–#15),
--   TWELVE DDL-realized; #5 (account.sub_cat_id) DROPPED at 048; #3 + #4 (the
--   monthly_report family) canonically-locked but DDL-deferred to V1.3+. 054 adds
--   NOTHING to it. The only FK-shaped column is users_id → auth.users(id). That is
--   the table's OWN SOLE tenant anchor under a DIRECT RLS predicate (users_id =
--   auth.uid()), identical shape to 024 user_settings.users_id / 009
--   user_taxonomy.users_id: there is NO second anchor to mismatch, so it is NOT a
--   matched-tenant Decision-3 instance — nothing to validate. No self-FK, no
--   INTEGER[] array, no cross-tenant reference.
--   AND the write-tenant binding fence added by this amendment does NOT create one:
--   a Decision-3 fence validates that a REFERENCED ROW sits inside the referring
--   row's tenant scope. This fence validates something categorically different —
--   that the ROW'S OWN users_id equals the tenant the DATABASE ACTUALLY SERVED
--   during the impersonated read. Same syntax family (BEFORE INSERT + INVOKER +
--   search_path = '' + NULL-safe fail-closed), different discipline: Decision 1
--   clause (c), not Decision 3. Counting it as #16 would corrupt the family's
--   meaning. Family stays 15 labeled / 12 DDL-realized.
--
-- ----------------------------------------------------------------------------
-- LEDGER DELTAS (each confirmed by reading the canonical ADR body verbatim on
--   2026-08-02, not cited from memory): §10 catalogued instances = 3 (unchanged —
--   RT-22 first / RT-26 second / RT-27 third, per ADR-011 Decision 4) · SECURITY
--   DEFINER allowlist = 4 (unchanged, per ADR-011 Decision 9 — all three functions
--   authored here are INVOKER) · Decision-3 family = 15 labeled / 12 DDL-realized
--   (unchanged; users_id = sole own anchor). SECURITY-doc (Sec-canonical; LANDED by
--   Sec at the 2026-08-02 joint-review, no longer "proposed"): SD matrix +1 =
--   **SD-24** (severity HIGH — Sec bumped Architect's proposed `medium` per the
--   SD-13 derivative-persistence rule, since fn_compute_nav's sources include SD-00;
--   storage class `tenant-scoped-derivative` on the SD-12 precedent — an existing
--   closed-enum member, so NO ADR-008 amendment; retention `indefinite` per §4.6) +
--   RT catalog +1 = **RT-31** (severity high). SLOT CORRECTION: this file and
--   ADR-040 originally proposed "RT-28" — RT-28 was ALREADY ALLOCATED to the Plaid
--   Link CSP allowlist (ADR-028 / SELF-212) and the catalog stood at RT-30, so the
--   correct slot is RT-31. Had the original proposal landed, SECURITY §4.5 would
--   carry two RT-28s. Every RT reference in this file now reads RT-31.
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
--     one checkpoint per user per day. IDEMPOTENCY: the worker uses the TARGETED
--     form `insert ... on conflict (users_id, nav_date) do nothing`, which requires
--     the column-level SELECT grant on those two arbiter columns (see the grant
--     block — without it the cron raises 42501 on EVERY run, the B9 defect). MUTATION SURFACE, per role (the loose "INSERT-only
--     mutation (all roles)" phrasing QA flagged is corrected here — `authenticated`
--     has NO write path at all, so "INSERT-only" never described it):
--       · authenticated — SELECT only. NO write grant and NO write policy: INSERT /
--         UPDATE / DELETE are denied at the table ACL, BEFORE RLS and BEFORE any
--         trigger is reached. Cannot forge a checkpoint.
--       · service_role (the W-1 write role, reached via SET LOCAL ROLE) — INSERT
--         only, and every INSERT must additionally satisfy the write-tenant binding
--         fence below. UPDATE / DELETE denied at the ACL (no grant); TRUNCATE
--         denied by REVOKE + the statement-level fence.
--       · any role that DOES hold UPDATE/DELETE/TRUNCATE (i.e. an owner-class role)
--         — blocked by the immutability triggers, which fire for the owner too.
--         KNOWN LIMIT, stated honestly: an owner-class role can suppress those
--         triggers (DISABLE TRIGGER / session_replication_role = 'replica'), which
--         is precisely why the ratified login role is NOT owner-class.
--   pfin.fn_nav_daily_block_mutation() — SECURITY INVOKER; BEFORE UPDATE OR DELETE
--     (row-level); raise (fail loud). set search_path = ''.
--   pfin.fn_nav_daily_block_truncate() — SECURITY INVOKER; BEFORE TRUNCATE
--     (statement-level); raise. set search_path = ''. + REVOKE TRUNCATE FROM PUBLIC.
--   pfin.fn_nav_daily_assert_computed_for() — SECURITY INVOKER; BEFORE INSERT
--     (row-level); set search_path = ''. Asserts new.users_id::text equals the
--     transaction-local GUC `app.nav_computed_for`. FAIL-CLOSED on unset / empty /
--     NULL / mismatch. See WRITE-TENANT BINDING FENCE below for the full contract.
--   RLS: SELECT to authenticated on users_id = auth.uid() AND the aal2 backstop;
--     INSERT/UPDATE/DELETE have NO authenticated policy (default-deny). Writes
--     execute AS service_role via the INSERT grant (the W-1 cron worker, logged in
--     as `pfin_etl` — see WRITE-PATH CREDENTIAL MODEL).
--   Security-load-bearing edges: users_id = auth.uid() fences reads to the owner
--     (no JOIN — direct anchor); the aal2 conjunct gates a totp/passkey reader to
--     an aal2 session (never a blanket aal2 — 'none'/missing-row unaffected); the
--     immutability triggers close the privileged-context UPDATE/DELETE/TRUNCATE gap
--     (service_role bypasses RLS but NOT triggers, and cannot disable them);
--     the write-tenant binding fence closes the write-side tenant gap RLS cannot
--     (there is no INSERT policy and the writer bypasses RLS); the finiteness CHECK
--     keeps a poisoned NAV out of the trend; service_role holds INSERT plus a
--     COLUMN-LEVEL SELECT on (users_id, nav_date) ONLY — it can append and can read
--     the arbiter columns its idempotency check requires, but holds NO UPDATE and NO
--     DELETE grant and CANNOT read nav_value at all, so it never mutates and never
--     sees a monetary figure; authenticated holds SELECT only (cannot forge a
--     checkpoint).
--
-- ----------------------------------------------------------------------------
-- ONE-ARBITER INVARIANT — DOCUMENTATION ONLY, NOT LOAD-BEARING (Sec joint-review
--   B9 condition 4). Recorded because it was load-bearing under the REJECTED
--   untargeted `on conflict do nothing`, and a future reader may find that shape in
--   this thread's history and wonder whether the invariant still binds. It does not.
--
--   Conflict-arbitrable constraint census on pfin.nav_daily (verified 2026-08-02):
--     u  nav_daily_users_id_nav_date_key  UNIQUE       ← the SOLE arbiter
--     p  nav_daily_pkey                   PRIMARY KEY  — `generated always as
--                                                        identity`, cannot collide
--     c  nav_daily_value_finite           CHECK        — not arbitrable (23514)
--     f  nav_daily_users_id_fkey          FOREIGN KEY  — not arbitrable (23503)
--
--   WHY IT NO LONGER BINDS: the worker uses the TARGETED form,
--   `on conflict (users_id, nav_date) do nothing`, which names its arbiter
--   explicitly. Adding a second unique-or-exclusion constraint therefore CANNOT be
--   silently absorbed — a violation of the new constraint raises 23505 loudly,
--   exactly as it should. Under the untargeted form it WOULD have been swallowed,
--   silently converting a real conflict into a no-op on a financial-correctness
--   path; that silent-absorption risk is what the targeted form buys out, and it is
--   why 054's own fail-loud principle (see fn_nav_daily_block_mutation's inline
--   comment — "raise, NOT return null") pointed away from untargeted.
--
--   STILL WORTH KNOWING when adding a constraint here: the targeted form's arbiter
--   column list must continue to match a real unique index, and the service_role
--   column grant must continue to cover those columns — see the CROSS-ARTIFACT
--   INVARIANT note at the grant. Both failures are loud (42P10 / 42501), not silent.
--
--   DO NOT reach for `on conflict ... DO UPDATE` to "fix" a stale checkpoint. That
--   is a correctness bar, not a style preference: DO UPDATE takes an UPDATE path,
--   which the append-only immutability trigger blocks by design — a checkpoint is a
--   historical fact and is never revised. `DO NOTHING` is first-write-wins, which is
--   the intended semantic. (Verified: the B7 binding fence still fires on a same-day
--   re-run — BEFORE INSERT precedes conflict detection, so a conflicting row does
--   NOT slip past the tenant check.)
--
-- ----------------------------------------------------------------------------
-- WRITE-TENANT BINDING FENCE (Sec joint-review B7, remedy (c′); F/CTO-ratified
--   2026-08-02). ADDED BY THE 2026-08-02 IN-PLACE AMENDMENT.
--
--   THE GAP IT CLOSES. This table has a SELECT policy only — no INSERT policy, no
--   WITH CHECK — and the writer bypasses RLS. So NOTHING in the database validated
--   that a row's users_id was the tenant whose data was actually read. Write-path
--   tenant correctness was an APPLICATION-LAYER guarantee only (ADR-011 Decision 1
--   clause (c), realized in TenantBoundConnection's per-tenant assertion), with
--   nothing behind it. That assertion structurally CANNOT catch this class: it
--   compares the statement against the same variable that would be wrong, so it
--   catches "statement names a different tenant than the binding" but never "the
--   binding itself is wrong."
--
--   WHY IT IS WORTH A DB FENCE even though today's worker is consistent-by-
--   construction (one users_id drives both the impersonated read and the INSERT;
--   fresh per-tenant connection under NullPool):
--     (1) IRREVERSIBILITY. Rows are append-only and forward-only. A checkpoint
--         written under the WRONG users_id cannot be UPDATEd or DELETEd by ANY
--         role — removing it would require a migration to drop or disable a
--         trigger. The blast radius of a write-tenant bug is permanent.
--     (2) NO GRANT-LAYER BACKSTOP for tenant identity — the INSERT grant fences
--         WHAT the writer may do, never WHOSE row it is.
--     (3) W-1 IS PRECEDENT. ADR-040 calls it "the durable per-user worker pattern";
--         the next per-user worker copies this shape and may not preserve
--         one-variable-drives-both.
--     (4) A CODE-BUG-FREE FAILURE PATH EXISTS. auth.uid() resolves the LEGACY
--         SINGULAR GUC `request.jwt.claim.sub` FIRST and only falls back to the
--         plural `request.jwt.claims ->> 'sub'`. The worker sets only the plural
--         form and never clears the singular one. If the singular GUC were ever set
--         at session or role scope (ALTER ROLE … SET, or an `options=-c` connection
--         parameter), auth.uid() would resolve to that ONE value for EVERY tenant in
--         the run: fn_compute_nav would return that user's NAV each time and the
--         INSERT — using the app's own users_id — would write ONE user's net worth
--         under EVERY other tenant's users_id. The app-layer assertion passes
--         cleanly throughout, because the statement does carry the bound users_id.
--
--   THE CONTRACT — a two-party protocol; BOTH halves are required.
--     Worker half (Backend, workers/etl — NOT this file). INSIDE the impersonated
--       block, execute:
--           select set_config('app.nav_computed_for', auth.uid()::text, true)
--       THE SECURITY-CRITICAL PROPERTY is that the value is captured from
--       auth.uid() AS THE DATABASE RESOLVED IT — NOT from the app's Python
--       variable. That is what makes the fence prove "the row's tenant IS the
--       tenant served", and it is what closes path (4) above: if the singular GUC
--       hijacked the read, auth.uid() returns the HIJACKING uid, the GUC records
--       the HIJACKING uid, and the INSERT (carrying the app's intended users_id)
--       MISMATCHES and is rejected. A GUC derived from the app's variable instead
--       would agree with the wrong row and close nothing.
--       Transaction-local (`true`): it survives impersonate()'s `reset role` within
--       the same transaction (teardown clears only request.jwt.claims + the role)
--       and auto-clears at COMMIT/ROLLBACK. GUC NAME IS PINNED — `app.nav_computed_for`,
--       exact; renaming it silently breaks the fence open on one side and closed on
--       the other.
--     DB half (this file). fn_nav_daily_assert_computed_for() reads that GUC at
--       INSERT time — running as service_role, which can read it fine — and asserts
--       equality with new.users_id::text.
--
--   FAIL-CLOSED, including the NULL-comparison trap. current_setting(…, true)
--   returns NULL when the GUC is unset. `new.users_id::text = NULL` evaluates to
--   NULL, NOT false — so a naive `if not (new.users_id::text = current_setting(...))`
--   would NOT raise on an unset GUC and the fence would fail OPEN in exactly the
--   case it most needs to close. The implementation therefore uses IS DISTINCT FROM
--   (NULL-safe) and additionally rejects NULL and '' explicitly. Unset / empty /
--   NULL / mismatch ALL reject.
--
--   CONSEQUENCE FOR EVERY OTHER INSERT PATH: any INSERT into pfin.nav_daily — QA
--   fixtures, seeds, future backfills, manual repair — MUST set the GUC first, in
--   the same transaction. This is deliberate: an unfenced convenience path would
--   re-open the gap. QA's battery asserts on the raise message below.
--
--   NOT a DEFINER entry (INVOKER — allowlist stays 4). NOT a Decision-3 instance
--   (see the DECISION 3 block above). NOT a §10 catalogued instance (see the §10
--   block above).
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
  'FK-bypass instance. WRITE PATH (ADR-023 credential model, F/CTO-ratified '
  '2026-08-02): the W-1 cron worker LOGS IN as `pfin_etl` (the dedicated NOINHERIT '
  'broker; service_role is rolcanlogin=f and can NEVER be a login identity) and '
  'WRITES AS `service_role` via SET LOCAL ROLE, over TenantBoundConnection; INSERT '
  '... ON CONFLICT (users_id, nav_date) DO NOTHING for idempotent re-runs — the '
  'TARGETED form, which is why service_role additionally holds a COLUMN-LEVEL '
  'select (users_id, nav_date): a targeted ON CONFLICT requires SELECT on its '
  'arbiter columns (Sec joint-review B9, 2026-08-02; without it the cron raises '
  '42501 on EVERY run). service_role CANNOT read nav_value and CANNOT select * — '
  'both denied, and QA asserts both negatives, since a positive assertion alone '
  'cannot distinguish a column grant from a table grant. Widening that grant (any '
  'extra column, or a move to table-level) is SEC JOINT-REVIEW-MANDATORY. '
  '`authenticated` holds SELECT only — no write grant and no write policy, so its '
  'writes are denied at the ACL before RLS (it cannot forge a checkpoint). '
  'Append-only audit-class (Decision 2 / Lock 10 mod #8): UPDATE + DELETE + TRUNCATE '
  'fenced for ALL roles; service_role bypasses RLS but not triggers, and is neither '
  'owner nor superuser so it cannot suppress them. WRITE-TENANT BINDING FENCE (B7 '
  '(c′)): a BEFORE INSERT trigger requires new.users_id to equal the transaction-'
  'local GUC app.nav_computed_for, which the worker sets from auth.uid() as the DB '
  'resolved it — so the row''s tenant is proven to BE the tenant served. Every INSERT '
  'path (incl. QA fixtures + seeds) must set that GUC. aal2 step-up backstop '
  'INHERITED on the SELECT policy (C3 / 025). JOINT-REVIEW-MANDATORY (tenant-scoped '
  'financial data). §10 ledger stays 3; DEFINER allowlist stays 4 (all three fences '
  'here are INVOKER; W-1 authors no fn); Decision-3 family stays 15 labeled / 12 '
  'DDL-realized. SECURITY: SD-24 (high) + RT-31 — both landed by Sec 2026-08-02.';

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
-- RLS — owner-only read (direct anchor + aal2 backstop); writes AS service_role.
-- grant-before-RLS shape (PR #106): authenticated needs the SELECT grant even with
-- RLS enabled (RLS filters rows; the GRANT lets the role reach the table). No
-- authenticated write grant → cannot INSERT/UPDATE/DELETE regardless of policy.
-- service_role gets INSERT + a COLUMN-LEVEL SELECT on (users_id, nav_date) only
-- (least privilege — the cron appends checkpoints and reads ONLY the two arbiter
-- columns its targeted ON CONFLICT requires; it never updates or deletes, UPDATE and
-- DELETE are denied at the ACL for it, the immutability triggers stand behind that
-- for any role that does hold them, and nav_value is withheld outright) and bypasses
-- RLS.
-- Under the ratified credential model this grant is LOAD-BEARING, not forward
-- posture: the worker logs in as `pfin_etl` (which holds nothing here) and
-- SET LOCAL ROLE service_role for the append, so this grant is the privilege that
-- admits the write. anon: nothing (schema USAGE denies before ACL).
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
  'authenticated cannot write a checkpoint. Writes execute AS service_role and '
  'bypass RLS — which is exactly why the write side needs its own DB-layer tenant '
  'proof: see the nav_daily_assert_computed_for BEFORE INSERT binding fence.';

grant select on pfin.nav_daily to authenticated;
grant insert on pfin.nav_daily to service_role;

-- ----------------------------------------------------------------------------
-- COLUMN-LEVEL SELECT for service_role — the arbiter columns ONLY (Sec joint-review
-- B9 ruling, 2026-08-02). REQUIRED for the worker's idempotency mechanism: a
-- TARGETED `on conflict (users_id, nav_date) do nothing` needs SELECT on the arbiter
-- columns. Without this the W-1 cron raises 42501 on EVERY run — not just re-runs —
-- because 054 previously granted INSERT alone while its own CONTRACT specified the
-- targeted form. (Found only by executing the assembled worker statement sequence
-- end-to-end; see ADR-040's verification-discipline consequence.)
--
-- WHY COLUMN-LEVEL AND NOT `grant select on pfin.nav_daily` — Sec REJECTED the
-- table-level grant. Precisely BECAUSE service_role bypasses RLS, the ACL is the
-- ONLY remaining fence on it; "RLS doesn't constrain it, so the ACL needn't either"
-- would justify granting SELECT on every table in pfin and dissolves 008's per-table
-- least-privilege model. A table grant would also hand service_role every tenant's
-- full net-worth trajectory — exactly the datum SD-24 is rated HIGH to protect
-- ("the sensitivity is in the sequence"). This grant withholds nav_value entirely.
--
-- ESTABLISHED IDIOM, NOT A NOVEL RELAXATION — column-level grants are the existing
-- least-privilege shape in this schema: 026:196 `grant select (users_id), update
-- (mfa_policy) on pfin.user_settings to service_role` (the closest precedent — same
-- role, same intent); 007:214 and 015:225 both column-grant a multi-column list to
-- `authenticated` while withholding a Vault secret handle. This grant follows all
-- three in the COLUMN-GRANT shape — which is the whole of what is cited here.
-- NOTE: 007 and 015 each pair their grant with a column-level REVOKE justified as
-- ensuring the withheld column "is not reachable via a broad grant". That
-- justification is FALSE (Postgres has no negative grants — measured), and it is
-- pre-existing drift on two Vault-credential surfaces, flagged to Sec as a
-- follow-up beyond this PR. It is NOT cited here and NOT reproduced below.
--
-- *** RESIDUAL — STATED PLAINLY, because the 026 precedent is NOT an exact match ***
--   026 grants ONE column (`users_id`) and no sequence. This grants TWO, and the
--   second is TEMPORAL. So service_role gains, across all tenants: checkpoint
--   EXISTENCE, the FIRST-VALUED date, and EVERY GAP in the series since. It does NOT
--   gain any monetary value. Sec's zero-marginal-disclosure finding covers the
--   tenant roster (service_role already reads pfin.account, so the users_id list is
--   not new) — it does NOT cover the per-tenant checkpoint-DATE SEQUENCE, which is
--   genuinely new information: it reveals when a tenant started using the product
--   and when the cron failed for them. That is a real, if narrow, disclosure and it
--   is not equivalent to 026. Recorded here rather than allowing the 026 citation to
--   imply exact equivalence.
--
-- WIDENING THIS GRANT IS SEC JOINT-REVIEW-MANDATORY. It is exactly
-- `select (users_id, nav_date)`. NEVER table-level. NEVER nav_value. Any addition of
-- a column, or any move to a table-level grant, re-opens the B9 ruling and must go
-- back to Sec before it lands.
--
-- CROSS-ARTIFACT INVARIANT (fenced at CI, not merely documented): the column list in
-- THIS grant must match the arbiter columns of the UNIQUE constraint the worker names
-- in its `on conflict (...)` target. Those are two artifacts in two files that must
-- move together. The fence is Sec's requirement that QA's battery exercise the
-- PRODUCTION statement verbatim: change the constraint without the grant and the
-- battery fails 42501; change the arbiter without matching the constraint and it
-- fails 42P10 (no unique index matching the ON CONFLICT specification). Either way
-- the PR that breaks the pairing is the PR that goes red — so the invariant cannot
-- drift silently. Do not "simplify" the battery to a plain INSERT; that is precisely
-- what let the original defect ship green.
-- ----------------------------------------------------------------------------
grant select (users_id, nav_date) on pfin.nav_daily to service_role;

-- nav_value IS DELIBERATELY NOT GRANTED — and there is deliberately NO `revoke`
-- statement here. Read this before adding one back.
--
-- An earlier draft of this migration carried `revoke all (nav_value) on
-- pfin.nav_daily from service_role;` as "belt-and-braces". Sec ruled it REMOVED
-- (B9 tail, 2026-08-02), and the reasoning is worth preserving because it will
-- otherwise be re-added by a well-meaning future reader:
--
--   AN EXECUTABLE STATEMENT THAT ENFORCES NOTHING IS WORSE THAN A COMMENT SAYING
--   THE SAME THING, BECAUSE CODE IMPLIES ENFORCEMENT. A reader who sees a `revoke`
--   reasonably infers that a protection exists. That is a FALSE FENCE. Keeping it
--   with corrected reasoning still leaves the next reader one skim away from the
--   wrong conclusion; removing it leaves nothing to misread.
--
-- The statement was also powerless in BOTH directions — Postgres has NO NEGATIVE
-- GRANTS (measured 2026-08-02, rolled-back txn): a later `grant select on
-- pfin.nav_daily to service_role` makes nav_value selectable regardless of any
-- earlier column revoke, AND issuing the column revoke AFTER a table-level grant
-- does not claw it back either. It protected against nothing.
--
-- THE ACTUAL CONTROLS on nav_value are, in order:
--   1. the NARROWNESS of the column grant above — `select (users_id, nav_date)`
--      confers nothing on nav_value, which is why it is unreadable today;
--   2. the SEC-JOINT-REVIEW-MANDATORY trigger recorded at that grant — any extra
--      column, or a move to table-level, goes back to Sec before it lands;
--   3. QA's two NEGATIVE assertions, which fail the moment a broad grant appears.
--
-- QA asserts BOTH negatives — `select nav_value` DENIED and `select *` DENIED —
-- because without them a battery CANNOT DISTINGUISH a column grant from a table
-- grant: both make the targeted ON CONFLICT succeed, so the positive assertion alone
-- would pass under either. The negatives are the only thing that pins the posture.

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
  'BEFORE UPDATE OR DELETE immutability fence on pfin.nav_daily (ADR-011 Decision 2 / Lock 10 mod #8; SELF-214). SECURITY INVOKER (touches nothing; not a DEFINER allowlist entry — allowlist stays 4). raise exception (fail loud). Blocks UPDATE + DELETE for ALL roles incl. service_role (which bypasses RLS but not triggers) — the privileged-context immutability fence RLS-default-deny alone cannot provide. INSERT is NOT blocked here (it is the cron append path) — but it is separately gated by fn_nav_daily_assert_computed_for, the BEFORE INSERT write-tenant binding fence.';

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

-- ----------------------------------------------------------------------------
-- Surface 3 — WRITE-TENANT BINDING FENCE (Sec joint-review B7 remedy (c′);
-- F/CTO-ratified 2026-08-02). Proves at the DB layer that the row's tenant IS the
-- tenant the database actually served during the impersonated read. Full rationale,
-- the two-party protocol, and the NULL-trap analysis are in the WRITE-TENANT
-- BINDING FENCE header block above. GUC name `app.nav_computed_for` is PINNED —
-- Backend's worker half sets it from auth.uid() (NOT from the app's variable)
-- inside the impersonated block, transaction-local.
-- ----------------------------------------------------------------------------
create or replace function pfin.fn_nav_daily_assert_computed_for()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  -- current_setting(..., true) = missing_ok: returns NULL rather than raising 42704
  -- when the GUC was never set in this transaction. We handle that NULL explicitly
  -- below — it must REJECT, not pass.
  v_computed_for text := current_setting('app.nav_computed_for', true);
begin
  -- FAIL CLOSED on all four cases: GUC unset (NULL) / empty string / mismatch /
  -- anything non-equal. IS DISTINCT FROM is the NULL-SAFE comparison: plain
  -- `new.users_id::text = v_computed_for` yields NULL (not false) when
  -- v_computed_for is NULL, and `if not NULL then` does NOT execute — which would
  -- fail OPEN precisely when the worker forgot to bind. The explicit NULL and ''
  -- tests are belt-and-braces and keep the intent legible.
  -- new.users_id is NOT NULL by column constraint, so only the GUC side can be NULL.
  if v_computed_for is null
     or v_computed_for = ''
     or new.users_id::text is distinct from v_computed_for
  then
    raise exception
      'pfin.nav_daily write-tenant binding REJECTED (ADR-011 Decision 1 clause (c) DB fence; SELF-214 B7). Row users_id=% does not match app.nav_computed_for=% — the checkpoint''s tenant must equal the tenant the database actually served during the impersonated read. Set app.nav_computed_for from auth.uid() inside the impersonated block (transaction-local) before INSERT.',
      new.users_id, coalesce(nullif(v_computed_for, ''), '<UNSET>');
  end if;

  return new;
end;
$$;

revoke execute on function pfin.fn_nav_daily_assert_computed_for() from public;

comment on function pfin.fn_nav_daily_assert_computed_for() is
  'BEFORE INSERT write-tenant binding fence on pfin.nav_daily (ADR-011 Decision 1 clause (c) realized at the DB layer; ADR-040; SELF-214 Sec joint-review B7 remedy (c′), F/CTO-ratified 2026-08-02). SECURITY INVOKER, set search_path = '''' — reads only a transaction-local GUC and raises; NOT a DEFINER allowlist entry (allowlist stays 4). CONTRACT: asserts new.users_id::text equals the transaction-local GUC ''app.nav_computed_for'', which the W-1 worker sets INSIDE the impersonated block via set_config(''app.nav_computed_for'', auth.uid()::text, true) — captured from auth.uid() AS THE DATABASE RESOLVED IT, never from the application''s own variable. That is the security-critical property: it proves the row''s tenant IS the tenant whose data was actually served, which a GUC derived from the app variable could not. It closes the legacy singular-GUC path (auth.uid() prefers request.jwt.claim.sub over the plural claims blob; a session/role-scoped singular GUC would otherwise silently serve ONE tenant''s NAV for EVERY tenant with no code bug and no app-layer assertion failure). FAIL-CLOSED on unset / empty / NULL / mismatch — IS DISTINCT FROM is used because new.users_id::text = NULL is NULL, not false, and would fail OPEN. Transaction-local so it survives impersonate()''s reset role and auto-clears at COMMIT. This is NOT a Decision-3 matched-tenant fence (it validates the row''s OWN anchor against the served tenant, not a referenced row''s tenant scope) — Decision-3 family unchanged at 15 labeled / 12 DDL-realized. Every INSERT path (worker, QA fixture, seed, future backfill) must set the GUC first.';

create trigger nav_daily_assert_computed_for
  before insert on pfin.nav_daily
  for each row execute function pfin.fn_nav_daily_assert_computed_for();
