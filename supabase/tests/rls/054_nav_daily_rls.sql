-- =====================================================================
-- Per-Wave battery — pfin.nav_daily append-only per-user daily NAV checkpoint
--   (SELF-214 / migration 054 / V1.1 "Net worth full"; ADR-040). V1-SHIP-BLOCK.
--   Implements **RT-31** (§4.5 RT catalog) for **SD-24** (§4.4, severity HIGH) — both LANDED by
--   Sec at the 2026-08-02 joint-review. SLOT CORRECTION: this battery originally read "RT-28";
--   RT-28 was ALREADY ALLOCATED (Plaid), so the correct slot is RT-31. Every RT reference here
--   now reads RT-31. Amended 2026-08-02 for the F/CTO-ratified B1/B2/B7 dispositions.
-- =====================================================================
-- ALSO BINDS TO: supabase/migrations/055_pfin_etl_role.sql — the ETL's dedicated login role
--   `pfin_etl` (B8 option (B) / ADR-041). Assertions (h10)-(h14b) read that role, so this battery
--   now has a CROSS-MIGRATION dependency: 055 must be applied. On the CI reset stack all
--   migrations are applied before the battery runs, so ordering is a non-issue there; a local
--   rolled-back verification must include 055 alongside 054. RED-until-055-applied is EXPECTED,
--   and RED if 055 were reverted or the role renamed.
--
-- BINDS TO MIGRATION: supabase/migrations/054_nav_daily.sql
--   - pfin.nav_daily                         (NEW tenant-scoped table: nav_id identity PK /
--                                             users_id uuid NOT NULL -> auth.users ON DELETE
--                                             CASCADE (SOLE tenant anchor) / nav_date DATE /
--                                             nav_value NUMERIC / created_at TIMESTAMPTZ)
--   - constraint nav_daily_value_finite      (CHECK nav_value <> NaN AND <> ±Infinity)
--   - unique (users_id, nav_date)            (one checkpoint per user per day — the worker's
--                                             ON CONFLICT (users_id, nav_date) DO NOTHING key)
--   - policy nav_daily_select                (FOR SELECT TO authenticated USING
--                                             users_id = auth.uid() AND <025 aal2 backstop>)
--   - grant select on pfin.nav_daily to authenticated       (ACL-before-RLS; SELECT ONLY)
--   - grant insert on pfin.nav_daily to service_role        (the W-1 cron append path)
--   - grant select (users_id, nav_date) on pfin.nav_daily to service_role
--                                            (COLUMN-scoped read — ONLY the two arbiter columns,
--                                             so the targeted `on conflict (users_id, nav_date)`
--                                             can arbitrate WITHOUT the writer ever being able to
--                                             read nav_value. service_role is NOT insert-only.)
--   - NO authenticated write policy / NO authenticated write grant  (a user cannot forge a checkpoint)
--   - pfin.fn_nav_daily_block_mutation()     (BEFORE UPDATE OR DELETE, ROW-level; raise — INVOKER)
--   - pfin.fn_nav_daily_block_truncate()     (BEFORE TRUNCATE, STATEMENT-level; raise — INVOKER)
--   - revoke truncate ... from public         (defensive; the statement trigger is the guarantee)
--   - pfin.fn_nav_daily_assert_computed_for() / trigger nav_daily_assert_computed_for
--                                            (B7 (c′) WRITE-TENANT BINDING FENCE — BEFORE INSERT,
--                                             ROW-level; SECURITY INVOKER + set search_path = '';
--                                             asserts new.users_id::text IS NOT DISTINCT FROM the
--                                             transaction-local GUC **`app.nav_computed_for`**,
--                                             with explicit NULL/'' rejects. SQLSTATE **P0001**,
--                                             greppable token **`write-tenant binding REJECTED`**
--                                             — deliberately DISJOINT from the immutability
--                                             fences' `is immutable` token. Covered by LEG (w).)
--
-- ┌─ WHAT THIS BATTERY IS (and why it is NOT the 053 shape) ──────────────────────────────────┐
-- │ nav_daily is TENANT-SCOPED (users_id = sole anchor, DIRECT-owner RLS — the 024 shape), so  │
-- │ the cross-tenant leg is REAL and load-bearing here (unlike 053/cpi_u_index, which is       │
-- │ global shared-read and has no tenant dimension at all). FIVE properties are guarded:       │
-- │  (I)   OWNER-ONLY READ — a user's net-worth trajectory is among the highest-signal figures │
-- │        in the app; a leak is the SD-24 (HIGH) disclosure event RT-31 exists to prevent.    │
-- │  (II)  NO-FORGE — authenticated holds SELECT only. A user cannot fabricate/edit a          │
-- │        checkpoint, so the trend chart cannot be authored by its own reader.                │
-- │  (III) APPEND-ONLY ACROSS **THREE** TIERS — UPDATE/DELETE/TRUNCATE fenced for              │
-- │        authenticated AND service_role AND **the table OWNER (`postgres`)**. Privileged     │
-- │        identities BYPASS RLS but NOT triggers, so the TRIGGERS (not RLS-default-deny) are  │
-- │        what close the privileged-context gap (Decision 2 / Lock 10 mod #8; 004 reproduced).│
-- │        The OWNER tier is the one a real incident runs through — see WHO THE WORKER IS.     │
-- │  (IV)  aal2 STEP-UP BACKSTOP INHERITED (C3 / ADR-029 / 025) — a totp reader at aal1 sees   │
-- │        NOTHING of its own, while a 'none' / missing-settings-row reader is UNAFFECTED      │
-- │        (the coalesce fail-safe — never a blanket aal2).                                    │
-- │  (V)   WRITE-TENANT BINDING (B7 (c′); NEW) — the row's tenant must EQUAL the tenant the    │
-- │        database actually served during the impersonated read. RLS cannot provide this:     │
-- │        the writer bypasses RLS, and the INSERT grant fences WHAT the writer may do, never  │
-- │        WHOSE row it is. Guarded by LEG (w). The failure it exists to stop is ONE user's    │
-- │        net worth written under EVERY other tenant's users_id — with no code bug, via the   │
-- │        legacy singular-GUC path — and because rows are append-only AND forward-only, such  │
-- │        a poisoned checkpoint could not be UPDATEd or DELETEd by ANY role afterwards. The   │
-- │        blast radius is permanent, which is why this fence is worth its own leg.            │
-- │  (VI)  BYPASS-CAPABLE ROLE SET HAS NOT GROWN (SD-24 tier boundary; NEW 2026-08-09) —       │
-- │        the ONE control this project actually owns over the DB-admin tier. SD-24's          │
-- │        "never cross-tenant" claim is scoped to the APPLICATION tier; the admin tier reads  │
-- │        across tenants and that residual is documented and non-remediable. What is ours is  │
-- │        that the set stays at the five known platform roles. Guarded by LEG (i), which is   │
-- │        set-complement-shaped by Sec mandate and re-proves its own non-vacuity on every     │
-- │        run. NOTE THE ASYMMETRY WITH EVERY OTHER PROPERTY HERE: (I)-(V) fence identities    │
-- │        RLS and triggers can reach; (VI) fences a tier they cannot, so its only instrument  │
-- │        is detection — it cannot prevent, and must never be read as if it does.             │
-- └───────────────────────────────────────────────────────────────────────────────────────────┘
--
-- ┌─ WHO THE WORKER ACTUALLY IS — B1 CREDENTIAL MODEL (F/CTO-ratified 2026-08-02) ─────────────┐
-- │ ⚠ CORRECTION OF AN EARLIER DRAFT OF THIS FILE. A prior revision asserted "the worker logs  │
-- │ in as `postgres`, the table owner", reasoning from `workers/etl/.env.example`. That was    │
-- │ WRONG, and the way it was wrong is worth recording: the .env.example value is a            │
-- │ PLACEHOLDER (`<example::postgres.your_project_ref>`), not a deployed identity. A template  │
-- │ is not evidence of what runs in production. Runtime identity is verified against the       │
-- │ secrets manifest and live catalog queries — never read off an example file.                │
-- │                                                                                            │
-- │ THE RATIFIED MODEL (B1 as amended by **B8 option (B)**), re-measured live from pg_roles /  │
-- │ pg_auth_members for this file:                                                             │
-- │   LOGIN role  = **`pfin_etl`** — the ETL's OWN dedicated role (migration 055 / ADR-041).   │
-- │                 rolinherit = f (**NOINHERIT**), rolsuper = f, rolbypassrls = f, owns       │
-- │                 nothing, holds NO direct table grant. Member of exactly service_role +     │
-- │                 authenticated, reachable ONLY via explicit SET ROLE. Ships **NOLOGIN with │
-- │                 no password** — inert by construction — and is flipped to a working        │
-- │                 credential only at deploy (one ALTER ROLE from the Coolify secret).        │
-- │                 ⚠ NOT `authenticator`. That role is still real — it fronts PostgREST and   │
-- │                 provider-sync — which is why an assertion left pointing at it stays GREEN  │
-- │                 while testing the wrong subject. B8 gave the ETL its own identity so it is │
-- │                 INDEPENDENTLY REVOCABLE and does not share the Data API credential.        │
-- │   READ  role  = `authenticated`  — via SET LOCAL ROLE + a synthetic JWT (RLS applies).     │
-- │   WRITE role  = `service_role`   — via **SET LOCAL ROLE service_role**. rolcanlogin = f    │
-- │                 (it cannot log in at all — it is only ever REACHED, never connected as).   │
-- │   postgres    = the table OWNER. **NOT the worker's identity.**                            │
-- │                                                                                            │
-- │ CONSEQUENCE FOR THIS BATTERY — the tiers mean something different than they did:           │
-- │  • LEG (c) / (h5)-(h7), the service_role tier, is now THE WORKER'S ACTUAL WRITE PATH, and  │
-- │    service_role's grant set is a REAL, load-bearing fence rather than an inherited detail: │
-- │    under NOINHERIT there is no ambient privilege, so what `service_role` is granted is     │
-- │    exactly what the worker can do. (h6)/(h7) are therefore load-bearing, not bookkeeping.  │
-- │  • LEG (o), the owner tier, NO LONGER documents the worker's path. It is retained as a     │
-- │    KNOWN-LIMIT RECORD — see the block below. Its assertions stay true and useful (they     │
-- │    fence a human psql session, a migration script, a manual "fix"), but the claim they     │
-- │    support has changed, and (o1) now pins the owner as an identity DISTINCT from the       │
-- │    worker's rather than identical to it.                                                   │
-- └───────────────────────────────────────────────────────────────────────────────────────────┘
--
-- ┌─ KNOWN LIMIT — owner-class logins CAN suppress these triggers (MEASURED; NOT asserted) ────┐
-- │ VERIFIED live in a rolled-back txn, as `postgres`: `set session_replication_role='replica'`│
-- │ SUCCEEDS, and with it in force the row-level trigger does NOT fire — an owner UPDATE went  │
-- │ through and nav_value really changed. `alter table … disable trigger` is the same class.   │
-- │ This is INHERENT to trigger-based immutability under an owner identity; it is NOT a 054    │
-- │ defect and applies identically to 004/account_trans and every Lock 10 mod #8 table.        │
-- │ ** THIS IS PRECISELY WHY THE NON-OWNER WORKER ROLE WAS RATIFIED (B1). ** The limit is not  │
-- │ a residual risk on the worker's path any more — it is the justification for moving the     │
-- │ worker OFF that path. Re-measured as `service_role` (the ratified write role):             │
-- │     set session_replication_role='replica'  -> ERROR: permission denied to set parameter   │
-- │     alter table … disable trigger           -> ERROR: must be owner of table nav_daily     │
-- │     drop trigger …                          -> ERROR: must be owner of relation nav_daily  │
-- │ (o6)/(o7) assert the first two POSITIVELY — the counterpart that turns this block from a   │
-- │ caveat into a tested property. The owner's own ability to bypass is deliberately NOT       │
-- │ asserted: a test claiming "the fence holds under session_replication_role=replica" would   │
-- │ be permanently and honestly RED against something triggers cannot provide. Recorded so the │
-- │ fence's strength is neither overstated nor quietly forgotten.                              │
-- └───────────────────────────────────────────────────────────────────────────────────────────┘
--
-- ┌─ LAYER HONESTY — which fence each assertion actually exercises (grant-then-RLS, PR #106) ──┐
-- │ Postgres checks the TABLE ACL **before** RLS, and RLS **before** a BEFORE-ROW trigger.     │
-- │ So a "denied" result must be attributed to the layer that really produced it:              │
-- │  • authenticated READ  -> ACL OPEN (SELECT granted) => the ONLY gate is RLS.  Leg (a)/(e)  │
-- │                            are therefore genuine RLS tests, not GRANT tests.               │
-- │  • authenticated WRITE -> NO write grant => denial is at the ACL layer ('permission denied │
-- │                            for table nav_daily'). The immutability trigger is NEVER        │
-- │                            reached under authenticated; asserting the trigger MESSAGE here │
-- │                            would be a false-RED. Leg (b) asserts the ACL message, and leg  │
-- │                            (b4) asserts the RLS-layer default-deny (zero write policies)   │
-- │                            behind it — the two layers proven separately, neither faked.    │
-- │  • service_role UPDATE/DELETE -> ALSO ACL-denied in production posture (its grant set is   │
-- │                            INSERT + SELECT on two columns only — no UPDATE, no DELETE).    │
-- │                            That would prove nothing about the TRIGGER. Leg (c) therefore   │
-- │                            holds the ACL OPEN with a TEST-ONLY grant (rolled back; the 004 │
-- │                            idiom) so the TRIGGER is the SOLE remaining gate — that is the  │
-- │                            load-bearing cross-tier assertion. Leg (h6)/(h7) separately     │
-- │                            assert the PRODUCTION least-privilege ACL, and they run BEFORE  │
-- │                            the test-only grant so the grant cannot mask them.              │
-- │  • OWNER (postgres) UPDATE/DELETE/TRUNCATE -> NO ACL layer exists to deny it (ownership    │
-- │                            confers the privilege intrinsically) and RLS is bypassed. So    │
-- │                            leg (o) needs NO test-only grant and NO setup at all: the       │
-- │                            TRIGGER is the sole gate by construction. This is the cleanest  │
-- │                            and least fragile tier in the battery (no grant, no role switch, │
-- │                            no BYPASSRLS dependency) — but per B1 it is NOT the worker.      │
-- └───────────────────────────────────────────────────────────────────────────────────────────┘
--
-- ┌─ BATTERY-DESIGN LESSON — an inversion suite proves LEG INDEPENDENCE, not just teeth ───────┐
-- │ Recorded because it is reusable beyond this file and is NOT visible from a green run.       │
-- │ An earlier revision had LEG (w) writing to tenants that the read legs count. Every          │
-- │ assertion passed. But when the inversion suite REMOVED the binding fence, the rejected      │
-- │ INSERTs started SUCCEEDING — and those stray rows perturbed the counts in (a1)/(a5)/(e3),   │
-- │ three unrelated legs that went RED for a reason having nothing to do with what they assert. │
-- │ The fix: LEG (w) writes only to tenant E (counted by no read leg) on per-assertion dates,   │
-- │ and (w6) is scoped to an exact (tenant, date). Now each inversion REDs exactly its own      │
-- │ assertions and nothing else.                                                                │
-- │ THE GENERAL POINT: a green battery cannot tell you whether your legs are independent —      │
-- │ coupling only shows up when something actually fails, which is the moment you most need a   │
-- │ precise signal. Running the inversion suite is therefore not only a teeth check; it is a    │
-- │ DIAGNOSABILITY check. Any future leg added here should be inverted once and checked for a   │
-- │ RED set that matches its own labels exactly.                                                │
-- └───────────────────────────────────────────────────────────────────────────────────────────┘
--
-- ┌─ ⚠ INSERT-PATH ORDERING — BEFORE-ROW TRIGGERS FIRE BEFORE CHECK/UNIQUE CONSTRAINTS ────────┐
-- │ The B7 binding fence is a BEFORE INSERT ROW trigger, so on EVERY insert path the order is: │
-- │        table ACL  ->  nav_daily_assert_computed_for (binding fence)  ->  CHECK / UNIQUE    │
-- │ MEASURED, both directions:                                                                 │
-- │     GUC unset + nav_value 'NaN'  ->  P0001  'write-tenant binding REJECTED'                │
-- │     GUC set   + nav_value 'NaN'  ->  23514  'violates check constraint                     │
-- │                                              "nav_daily_value_finite"'                     │
-- │ CONSEQUENCE: **every** INSERT in this file must set `app.nav_computed_for` to the row's    │
-- │ own users_id first, or it tests the binding fence while claiming to test something else.   │
-- │ EVERY INSERT site binds it first, with exactly two BY-DESIGN exceptions: (w1) and (w2),    │
-- │ which exist to test the unset/empty GUC. (pg_temp.qa_rc's insert is bound by its callers.) │
-- │ Stated as an INVARIANT, not a count, because                                                │
-- │ a census drifts silently as legs are added (this line once said "13 sites" and was stale by  │
-- │ six). THE VACUOUS-GREEN SHAPE THIS AVOIDS: a leg                                             │
-- │ that asserts only "it raises" would stay GREEN while proving nothing about the CHECK.      │
-- │ This battery does not have that shape — legs (f1)-(f3) match the CONSTRAINT NAME           │
-- │ (`%nav_daily_value_finite%`) and (k1) matches SQLSTATE 23505, both DISJOINT from the       │
-- │ binding fence's token, so an unbound-GUC regression there goes RED rather than false-GREEN.│
-- │ The message-precision discipline (004 all-42501 lesson) is what makes that true; it is not │
-- │ luck, and it is the reason to keep matching on names/SQLSTATEs and never on "raises".      │
-- │ NOT AFFECTED: (b1)-(b3)/(b5) — the ACL denies before any trigger runs; and legs (c)/(o2)/  │
-- │ (o3) — the binding fence is BEFORE **INSERT** only, so UPDATE/DELETE/TRUNCATE never reach  │
-- │ it and their assertions are unchanged. (Verified: leg (c) needs no GUC.)                   │
-- └───────────────────────────────────────────────────────────────────────────────────────────┘
--
-- ┌─ SIGNAL PRECISION — no fence can pass for another (the 004 all-42501 false-green lesson) ──┐
-- │  • authenticated write (no grant)   -> MESSAGE-precise 'permission denied for table nav_daily'│
-- │  • row-level immutability trigger   -> MESSAGE-precise 'pfin.nav_daily is immutable%UPDATE  │
-- │                                        blocked%' / '%DELETE blocked%'                       │
-- │  • statement-level TRUNCATE trigger -> MESSAGE-precise '...immutable%TRUNCATE blocked%'     │
-- │                                        (DISTINCT verb clause from the row-level fence —     │
-- │                                        this is what proves the two triggers are two fences) │
-- │  • nav_value NaN/±Infinity          -> CONSTRAINT-NAME-precise '%nav_daily_value_finite%'   │
-- │  • duplicate (users_id, nav_date)   -> SQLSTATE-precise 23505 unique_violation              │
-- └───────────────────────────────────────────────────────────────────────────────────────────┘
--
-- NON-VACUITY (supabase/CLAUDE.md convention 3(c)) — BOTH tenants are seeded with REAL
--   nav_daily rows BEFORE any isolation assertion, and every "sees 0" assertion is paired with
--   a positive control proving the rows exist and are visible to SOMEONE:
--     (a2) B sees 0 of A's rows   <-> (a1) A sees exactly its 2 rows        [rows really exist]
--     (a4) A sees 0 of B's rows   <-> (a3) B sees exactly its 1 row         [symmetric, both ways]
--     (a5) A's UNSCOPED full-table read returns 2 of the 5 seeded rows      [the direct leak probe]
--     (e1) totp@aal1 sees 0 own   <-> (e2) SAME user @aal2 sees its 1 row   [backstop, not emptiness]
--     (b*) authenticated write denied <-> (g1)/(f4) service_role write ACCEPTED  [not a dead table]
--     (c*)/(o2)/(o3)/(o4) trigger raises <-> (g1)/(o5) INSERT is NOT blocked  [not an over-broad fence]
--     (o2)-(o4) owner mutation blocked   <-> (o1) the owner really IS `postgres`  [right identity]
--
-- FAILS-CLOSED — the REAL defect each assertion would catch:
--   (a1) -> an over-restrictive/broken users_id predicate that hides the owner's own trajectory.
--   (w1) -> THE FENCE FAILING OPEN ON THE NULL TRAP. An unset GUC makes current_setting(…,true)
--            return NULL, and `new.users_id::text = NULL` is NULL — not false — so a naive
--            equality test would NOT raise in exactly the case it most needs to (the worker
--            forgot to bind). RED if IS DISTINCT FROM were ever "simplified" to `<>` or `=`.
--   (w2) -> the empty-string GUC slipping through (a set_config that ran with an empty value).
--   (w3) -> **THE WHOLE POINT OF THE FENCE**: a checkpoint written under a users_id that is NOT
--            the tenant the database actually served. This is the singular-GUC hijack path —
--            auth.uid() resolves the legacy `request.jwt.claim.sub` FIRST, so ONE tenant's NAV
--            could be written under EVERY tenant's users_id with no code bug and a cleanly
--            passing app-layer assertion. RED if the trigger were dropped. Append-only +
--            forward-only means such a row could never be corrected — the fence is the only
--            thing between that bug and permanent cross-tenant financial garbage.
--   (w4) -> an OVER-BROAD binding fence that rejects a correctly-bound write: the cron would be
--            dead. A fence that blocks the legitimate path is an outage, not a control.
--   (w5) -> the idempotent re-run path breaking: `ON CONFLICT (users_id, nav_date) DO NOTHING`
--            must be a CLEAN no-op, not a binding-fence trip. The fence fires BEFORE the conflict
--            is detected, so a re-run is exactly where a badly-scoped fence would break the cron.
--   (w6) -> a re-run silently OVERWRITING the existing checkpoint (DO NOTHING degraded to DO
--            UPDATE): proves (w5)'s no-op is a real no-op — row count AND value both unchanged.
--   (w7) -> the new BEFORE INSERT fence having somehow displaced the immutability fences: with a
--            correctly-bound GUC an UPDATE must STILL raise `is immutable`, never the binding
--            token. Proves the two fence families are independent and their signals disjoint.
--   (h10) -> **the B8 credential model silently collapsing**: `pfin_etl` NOINHERIT is the ONLY
--            reason the ETL's login role does not ambiently hold service_role's privileges. If
--            rolinherit flipped, the login session would inherit every granted role's rights and
--            the SET ROLE discipline — plus (h5)-(h7)'s entire meaning — would evaporate with no
--            other test going RED.
--   (h11) -> the same collapse caught at the PRIVILEGE layer rather than the catalog flag: the
--            ETL login identity must report NO ambient INSERT/SELECT on nav_daily even though it
--            is a member of the role that holds INSERT. Also RED if a direct grant to pfin_etl
--            were ever made, which would quietly bypass the SET ROLE discipline entirely.
--   (h12) -> a THIRD membership creeping onto the ETL role, widening its reach with no migration
--            to nav_daily itself and therefore no other assertion in this file noticing.
--   (h13) -> the ETL login identity acquiring superuser / BYPASSRLS / ownership — any of which
--            would put the owner-only bypasses (DISABLE TRIGGER, session_replication_role) back
--            within reach of the very process 054's fences exist to constrain, silently undoing
--            what B8 was ratified to achieve.
--   (h14a)/(h14b) -> a migration shipping a USABLE credential: a login-capable pfin_etl WITH a
--            password committed to the repo. Asserted as two half-specific invariants (§7.21
--            item 2 split) rather than one combined "cannot authenticate as shipped", so a RED
--            self-identifies which half fired and a legitimate NOLOGIN-vs-no-password change
--            does not produce a false RED on the wrong half.
--   (o6)/(o7) -> the ratified non-owner write role losing its non-owner-ness: if `service_role`
--            could set session_replication_role or DISABLE TRIGGER, it could suppress every fence
--            in this file, and the B1 move off the owner identity would have bought nothing.
--   (a2) -> THE RT-31 EVENT: tenant B reading tenant A's net-worth history. RED if nav_daily_select
--            were USING (true), keyed on the wrong column, or dropped (RLS enabled + no policy would
--            instead 0-row (a1), so both directions are covered).
--   (a3)/(a4) -> the same leak in the opposite direction (a one-way test can pass on a policy that
--            accidentally hard-codes one tenant).
--   (a5) -> a leak via ANY row, not just rows matching a users_id filter — the unscoped read is the
--            probe an attacker actually issues (`select * from pfin.nav_daily`).
--   (b1) -> a forged checkpoint: an authenticated user INSERTing a fabricated NAV into its own trend
--            (or another's). RED the moment an INSERT grant/policy is opened to authenticated.
--   (b2) -> a user REVISING history (e.g. deleting a drawdown) — the append-only promise from the
--            authenticated tier.
--   (b3) -> a user DELETING an inconvenient checkpoint.
--   (b4) -> an INSERT/UPDATE/DELETE/ALL policy landing on the table (RLS-layer default-deny lost);
--            defence-in-depth behind the ACL fence, and the assertion that survives if a future
--            migration adds a write GRANT without a policy audit.
--   (c1) -> removal of fn_nav_daily_block_mutation (or its trigger): the cron/service tier could
--            silently REWRITE a historical NAV. RLS cannot catch this — service_role bypasses RLS.
--   (c2) -> created_at rewritten post-INSERT (audit-class provenance destroyed; Lock 15 mod #1).
--   (c3) -> removal of the DELETE half of the same fence: privileged erasure of a checkpoint.
--   (b5) -> a TRUNCATE grant reaching authenticated.
--   (o1) -> the leg-(o) identity anchor: pfin.nav_daily's owner is `postgres` — an identity
--            DISTINCT from the worker's (B1/B8: the worker logs in as `pfin_etl` and writes AS
--            `service_role`). RED if ownership moved, at which point leg (o) would be fencing
--            some other identity and this leg would need re-targeting. Without this the owner
--            tier could drift off-target and still look green.
--   (o2) -> a NON-WORKER owner-class session silently REWRITING a historical NAV — a human psql
--            session, a migration script, a manual "fix", or any future job that mistakenly
--            connects as the owner. The owner holds UPDATE by ownership (no grant to revoke, RLS
--            bypassed) so ONLY fn_nav_daily_block_mutation stops it. RED if that trigger or its
--            binding is removed. NOTE the scope honestly: this stops ACCIDENTAL owner mutation,
--            not a deliberate owner who first disables replication triggers (see KNOWN LIMIT).
--   (o3) -> the same, for erasure: an owner-class session DELETING checkpoints.
--   (o4) -> removal of fn_nav_daily_block_truncate (or its STATEMENT-level trigger): the entire
--            net-worth trend history wiped in ONE statement by the identity that actually holds
--            TRUNCATE. Row-level triggers do NOT fire on TRUNCATE, so (c1)-(c3)/(o2)/(o3) passing
--            does NOT imply this — it is a genuinely distinct fence.
--   (o5) -> an OVER-BROAD immutability fence that also blocked the owner's INSERT. (The worker's
--            own append path is (g1) under service_role; (o5) guards the fence's shape at the
--            owner tier — e.g. a future migration widening BEFORE UPDATE OR DELETE to include
--            INSERT would break both, and (o5) catches it without needing the worker's role.)
--   (e1) -> the 025 aal2 backstop clause dropped from nav_daily_select's USING: a stolen-password
--            aal1 session on a totp-enrolled account would read the whole net-worth trajectory
--            through the direct PostgREST API (C6 exposure-gating — the backstop is the only layer).
--   (e2) -> an over-blocking backstop (the totp user locked out even at aal2) AND proves (e1) is
--            non-vacuous (the user really owns a row).
--   (e3) -> the clause degenerating into a BLANKET aal2 requirement — a 'none' user locked out of
--            their own data.
--   (e4) -> the coalesce(...,'none') fail-safe removed: a lazily-provisioned user with NO
--            user_settings row would get NULL not in (...) => NULL => filtered => permanent
--            self-lockout (the null-lockout bug 025 explicitly guards).
--   (e5) -> the aal conjunct REPLACING rather than ANDing with the tenant predicate: stepping up to
--            aal2 must never widen a reader beyond its own rows (ISOLATION ⟂ MFA).
--   (f1)/(f2)/(f3) -> a NaN / ±Infinity NAV frozen into the trend by the privileged writer
--            (service_role bypasses RLS but NOT a table CHECK). One poisoned checkpoint blows up
--            every downstream period-over-period delta and the whole §2.1.2 chart.
--   (f4) -> an OVER-BROAD finiteness CHECK that also rejects legitimate values.
--   (g1) -> the service_role INSERT grant being absent/revoked: the W-1 cron could not append and
--            the trend would silently stop accumulating. ALSO the control that makes (b*) and (c*)
--            meaningful — it proves the table is writable by SOMEONE, so the write fences are real
--            fences and not a vacuously locked table.
--   (k1) -> loss of UNIQUE (users_id, nav_date): the worker's ON CONFLICT (users_id, nav_date) DO
--            NOTHING idempotency key disappears and a re-run duplicates the day (double-counted
--            trend points). Cross-tenant-safe by construction: the key is (users_id, nav_date), so
--            tenant B writing the same DATE as tenant A must still succeed — (g1) covers that.
--   (h1) -> the authenticated SELECT grant missing => (a*)/(e*) would be ACL-denied and this
--            battery would be testing GRANTs, not RLS (PR #106 root-cause guard).
--   (h2)/(h3)/(h4) -> attribution proof for (b1)/(b2)/(b3): they are missing GRANTS, not RLS
--            rejections — and a guard against the SELECT-only authenticated grant being widened.
--   (h5) -> the service_role INSERT grant (the cron append path) present.
--   (h6)/(h7) -> LEAST PRIVILEGE: service_role must hold NO UPDATE and NO DELETE. The cron appends,
--            never mutates. RED if a future migration widens the worker's grant (the triggers would
--            still fence it, but defence-in-depth must not silently erode). ASSERTED BEFORE the
--            leg-(c) TEST-ONLY grant, so that grant cannot mask an erosion.
--   (h8) -> a TRUNCATE grant reaching service_role.
--   (h9) -> anon reachability: nav_daily must NEVER be anon-readable (SD-24 tenant-scoped).
--
-- §10 / DECISION 3 (Path B — reference ADR-011 Decision 4, do NOT restate the catalogued numbered
--   list): §10 catalogued ledger UNCHANGED at 3 (RT-22 + RT-26 + RT-27) — 054 introduces ZERO
--   catalogued instances, and this battery adds none.
--   LAYER-ATTRIBUTION (corrected for B1 — the earlier revision of this file inherited the wrong
--   credential framing): the nav_daily service_role INSERT grant is a DB-LAYER ACL, NOT the RT-26
--   code-layer SUPABASE_SERVICE_ROLE_KEY allowlist grep surface. Under the ratified model the W-1
--   worker reaches Postgres over a DIRECT connection, logging in as **`pfin_etl`** (its own
--   dedicated role per B8 option (B) / migration 055 — NOT the shared `authenticator`) and writing
--   AS service_role via SET ROLE — so it holds **no SUPABASE_SERVICE_ROLE_KEY at all** and is
--   already off the RT-26 code-layer allowlist (same posture as eod_price/019 + cpi_u_index/053 +
--   the scheduled-poll worker). The B1/B8 corrections change WHICH ROLE IS NAMED, not any catalogued
--   instance's layer: RT-22 / RT-26 / RT-27 attributions are UNCHANGED and nothing becomes
--   "four-layer".
--   NEITHER trigger class here is a catalogued instance: the append-only immutability triggers are
--   a Decision-2 AUDIT-CLASS mechanism, and the B7 write-tenant binding fence is a DB-LAYER
--   reinforcement of ADR-011 Decision 1 clause (c) — it composes with Decision 4's defense-in-depth
--   DISCIPLINE but adds no entry to the numbered list and no layer to any listed instance.
--   DECISION 3 UNCHANGED (15 labeled / 12 DDL-realized — read the ADR-011 D3 body live; it grows):
--   users_id is the table's SOLE tenant anchor under a DIRECT predicate, so there is no second
--   anchor to matched-tenant-validate (the 024 user_settings / 009 user_taxonomy shape). The B7
--   fence is NOT a Decision-3 matched-tenant fence either — it validates the row's OWN anchor
--   against the served tenant, not a REFERENCED row's tenant scope.
--   SECURITY-doc: this battery IS the **RT-31** proof for **SD-24 (HIGH)**, both landed by Sec.
--
-- POSTURE (SECURITY §4.5): SYNTHETIC ONLY — fixed-UUID tenants from _rls.tenant_a()/_b()/_c() plus
--   battery-local tenants D (aal2 leg) and E (binding-fence leg). NO PII / NO real account
--   numbers / NO production data. The `app.nav_computed_for` values are those same synthetic
--   UUIDs — the GUC carries a tenant identifier, never any financial value. nav_value
--   figures are invented round numbers, NOT the F/CTO's financial data. Fixture rows are seeded in
--   the PRIVILEGED (postgres) session — the only unblocked write path, since authenticated has no
--   write grant — so the RLS/backstop is exercised ONLY on the authenticated paths under assertion,
--   never during setup. Everything runs inside a single txn that ROLLS BACK, including the
--   TEST-ONLY service_role grant in leg (c).
--
-- ROLE/SCHEMA DISCIPLINE (PR #121 root-cause): `_rls` grants no USAGE to authenticated, so NO
--   `_rls.*` call appears inside SQL executed while switched to authenticated. Tenant UUIDs are
--   resolved to psql LITERALS via \gset at role=postgres; every _rls.* call is made at
--   role=postgres and each block restores role=postgres before the next.  \gset var names are
--   ALL-LOWERCASE (005 case-fold lesson).
--
-- ⟦WIRE-VALIDATE⟧ Cross-tier legs (c1)-(c3) depend on `service_role` (i) existing, (ii) having
--   BYPASSRLS — verified `rolbypassrls = t` on the local PG 17.6 stack — and (iii) being able to
--   run pgTAP fns (the 019 (g1) / 053 (f1) precedent). If service_role ever loses BYPASSRLS, RLS
--   default-deny would 0-row the UPDATE, the trigger would never fire, and (c1)-(c3) would go
--   FALSE-RED — THIS is the adjustment point. The authoritative run is the 001->054 reset stack in
--   CI (pg_prove directory-mode, db-tests.yml) after Backend applies 054. RED-until-054-applied is
--   EXPECTED on any pre-054 stack (the table would not exist).
--   Leg (o) has NO such dependency — it needs no grant, no role switch and no BYPASSRLS: ownership
--   is intrinsic. It is the tier least likely to go false-RED.
--   ⚠ GUC ORDERING CONSTRAINT (structural, not stylistic): `app.nav_computed_for` is
--   transaction-local and CANNOT be restored to NULL once set — MEASURED: set_config(…, NULL, true)
--   yields '' (empty string), not NULL. So (w1), the genuinely-UNSET case, MUST run before any
--   set_config of that GUC in this transaction. That is why LEG (w) sits ahead of the nav_daily
--   fixture rows rather than with the other write legs. Moving it later silently degrades (w1)
--   into a duplicate of (w2) — the assertion would still pass while no longer testing the NULL
--   trap it exists for. Do not reorder.
--   LOCAL VERIFICATION PERFORMED (non-destructive, the 053 precedent — NO `supabase db reset`, the
--   F/CTO's local data untouched): 055 + 054 + this file applied inside a single psql transaction
--   that was ROLLED BACK; plus INVERSION runs (each sabotaging one fence in its own rolled-back
--   txn) confirming the predicted assertions go RED and no others.
--   ⚠ ASSERTION COUNT IS NOT RESTATED HERE. The authoritative count is the executable
--   `select plan(N)` below — a prose copy of it drifts silently, and this block previously
--   carried a stale one. Read the call, do not cite this comment.
--   ⚠ NO ASSERTION IN THIS FILE IS SCHEDULED FOR DELETION. An earlier revision of this block
--   instructed a future reader to "delete (w8) and drop the plan by 1 when resolved", from when
--   (w8) was a defect marker for the ON CONFLICT privilege bug. That bug IS resolved, and (w8)
--   was REFRAMED into a positive least-privilege assertion (the targeted form succeeds under the
--   column grant) rather than removed — so following that instruction today would DELETE WORKING
--   COVERAGE and break the plan count. The instruction is retracted here. (w8)'s history is
--   recorded at its own leg, which is a narrative of what it USED to be and is correct to keep;
--   THIS block describes current state and must only ever describe current state. A header that
--   reads as authoritative while being untrue of the artifact is the most damaging kind of
--   staleness — it survives review precisely because it looks like instruction.
-- =====================================================================

begin;

-- shared verbs (Option C via \ir); nested case -> ../_fixtures/ per DESIGN.md.
\ir ../_fixtures/rls_verbs.psql

select plan(75);   -- 63 + 11 for RT-31 leg (i) (the bypass-capable role-set fence, 2026-08-09) + 1 for the h14a/h14b conjunction split (§7.21, 2026-08-17)

-- ---------------------------------------------------------------------
-- Local helpers (pg_temp — session-scoped, auto-dropped, rolled back with the txn).
--   qa_rc()  reproduces the worker's statement EXACTLY and returns GET DIAGNOSTICS ROW_COUNT,
--            which is precisely what psycopg's `result.rowcount` reads in nav_daily.py. Needed
--            because a data-modifying CTE cannot be nested in a scalar subquery, so the rowcount
--            cannot be captured inline. Keeping the statement text identical is the point (RT-31
--            leg (h)) — a simplified equivalent is what let the original ON CONFLICT defect
--            through four reviewers.
--   qa_pfin_etl_rolcanlogin_false() / qa_pfin_etl_rolpassword_null() guard the pg_authid read,
--            one per h14 half (§7.21 item 2 split — was one combined qa_pfin_etl_inert()). On a
--            stack where pg_authid is not readable each returns NULL, which pgTAP treats as a
--            FAILURE — deliberately RED rather than a silent skip. A security assertion that
--            quietly opts out when it cannot be evaluated is the vacuous-green shape this whole
--            battery exists to avoid; the guard is here to prevent a HARD ABORT (the (h11)
--            lesson), not to excuse an unevaluated assertion.
-- ---------------------------------------------------------------------
create function pg_temp.qa_rc(p_uid uuid, p_date date, p_val numeric) returns int
language plpgsql as $qa$
declare n int;
begin
  insert into pfin.nav_daily (users_id, nav_date, nav_value) values (p_uid, p_date, p_val)
    on conflict (users_id, nav_date) do nothing;      -- VERBATIM production shape
  get diagnostics n = row_count;
  return n;
exception when others then
  -- MUST NOT PROPAGATE. This function is called INSIDE is()'s argument list, and pgTAP
  -- evaluates arguments BEFORE the assertion runs — so an exception here does not fail an
  -- assertion, it ABORTS THE ENTIRE FILE. Measured: revoking the column grant killed the run
  -- at this line with 4 of 62 assertions executed and ZERO reported failures, which reads as
  -- "no problem found" rather than "the battery died". That is the same hard-abort class as
  -- the (h11) pg_roles lookup, and it is why every helper called from an assertion argument
  -- returns NULL on failure instead of raising: NULL makes is() go RED, legibly and locally.
  return null;
end $qa$;

-- §7.21 item 2 (Sec-ruled 2026-08-17): SPLIT into two half-specific helpers —
--   the single combined qa_pfin_etl_inert() (below, RETIRED but its shape is
--   preserved here as the historical reference for the split) returned ONE
--   boolean over BOTH halves, so a RED did not self-identify which half
--   fired and the half-specific EXPECTED-DIFFERENT annotation at (h14) had
--   to send the reader to a manual pg_authid query. Same guard pattern on
--   both: insufficient_privilege -> NULL -> pgTAP FAILS. Never a silent skip.
create function pg_temp.qa_pfin_etl_rolcanlogin_false() returns boolean
language plpgsql as $qa$
begin
  return (select not rolcanlogin from pg_authid where rolname = 'pfin_etl');
exception when insufficient_privilege then
  return null;
end $qa$;

create function pg_temp.qa_pfin_etl_rolpassword_null() returns boolean
language plpgsql as $qa$
begin
  return (select rolpassword is null from pg_authid where rolname = 'pfin_etl');
exception when insufficient_privilege then
  return null;
end $qa$;

-- Resolve the fixed tenant UUIDs to psql literals while privileged (role=postgres).
select _rls.tenant_a() as ta, _rls.tenant_b() as tb, _rls.tenant_c() as tc \gset
-- Tenant D is battery-local: the totp-enrolled reader for the aal2 backstop leg. (tenant_a/_b are
-- deliberately 'none' here so the ISOLATION leg tests the TENANT predicate, not the backstop — a
-- totp tenant at an aal-less session would see 0 of its OWN rows and (a1) would be a false-RED
-- while (a2) went vacuously green. Separating the two dimensions is the point.)
\set td '00000000-0000-0000-0000-00000000000d'
-- Tenant E is battery-local and used ONLY by LEG (w) (the write-tenant binding fence). It is
-- deliberately absent from every read assertion, so the row (w4) legitimately appends cannot
-- perturb any count in legs (a)/(e).
\set te '00000000-0000-0000-0000-00000000000e'

-- ---------------------------------------------------------------------
-- FIXTURE (PRIVILEGED postgres session — bypasses RLS AND the table ACL).
--   A = tenant_a, mfa_policy 'none', owns 2 checkpoints
--   B = tenant_b, mfa_policy 'none', owns 1 checkpoint   (the intruder, and an owner in its own right)
--   C = tenant_c, NO user_settings row,  owns 1 checkpoint (lazy-provision / coalesce case)
--   D = tenant d, mfa_policy 'totp',     owns 1 checkpoint (the aal2 backstop case)
--   E = tenant e, mfa_policy 'none',     owns 1 checkpoint written by LEG (w4) — used ONLY by the
--       binding-fence leg and by NO read assertion, so it cannot perturb any count below.
--   => 5 fixture rows (+ E's 1 from leg (w)). Every "sees 0" assertion below is against a NON-EMPTY table with
--      real rows owned by a real other tenant — the non-vacuity requirement.
--   B and C intentionally share nav_date '2026-07-31' with A: the UNIQUE key is (users_id,
--   nav_date), so a same-day checkpoint for a DIFFERENT user must be legal. If this fixture ever
--   fails to load, the uniqueness key has been mis-scoped to nav_date alone.
-- ---------------------------------------------------------------------
insert into auth.users (id) values (:'ta'), (:'tb'), (:'tc'), (:'td'), (:'te');

insert into pfin.user_settings (users_id, mfa_policy) values
  (:'ta', 'none'),
  (:'tb', 'none'),
  (:'td', 'totp'),
  (:'te', 'none');
-- (tenant_c deliberately gets NO user_settings row — the missing-row coalesce case for (e4).)

-- =====================================================================
-- LEG (w) WRITE-TENANT BINDING FENCE — B7 (c′); fn_nav_daily_assert_computed_for.
--   ⚠ POSITIONED HERE BY NECESSITY, NOT BY STYLE. `app.nav_computed_for` is transaction-local
--   and cannot be restored to NULL once set (MEASURED: set_config(…, NULL, true) yields '',
--   not NULL). (w1) — the genuinely-UNSET case, i.e. the NULL trap the fence's IS DISTINCT FROM
--   exists for — is therefore only testable BEFORE any set_config of that GUC in this txn.
--   Moving LEG (w) after the fixture would silently degrade (w1) into a duplicate of (w2): still
--   green, no longer testing anything. DO NOT REORDER.
--   Runs under **service_role**, the ratified B1 write role (reached via SET LOCAL ROLE; it
--   cannot log in). Uses tenant E and June dates exclusively, so nothing here perturbs the
--   fixture counts asserted in legs (a)/(e).
--   Signal: SQLSTATE P0001 + the token `write-tenant binding REJECTED` — textually DISJOINT
--   from the immutability fences' `is immutable`, so neither can ever pass for the other.
-- =====================================================================
select set_config('role', 'service_role', true);

-- (w1) GUC NEVER SET -> current_setting(...,true) is NULL -> MUST reject. The NULL trap.
select throws_like(
  format($$ insert into pfin.nav_daily (users_id, nav_date, nav_value) values (%L, '2026-06-01', 10000.00) $$, :'te'),
  '%write-tenant binding REJECTED%',
  '(w1) binding fence, NULL trap: an INSERT with app.nav_computed_for NEVER SET is REJECTED (P0001, ''write-tenant binding REJECTED''). This is the case a naive `new.users_id::text = current_setting(...)` would FAIL OPEN on — NULL is not false — so it is the assertion that guards the IS DISTINCT FROM implementation. Must run before any set_config of the GUC (see leg header)'
);

-- (w2) GUC = empty string -> MUST reject (a set_config that ran with an empty value).
select set_config('app.nav_computed_for', '', true);
select throws_like(
  format($$ insert into pfin.nav_daily (users_id, nav_date, nav_value) values (%L, '2026-06-02', 10000.00) $$, :'te'),
  '%write-tenant binding REJECTED%',
  '(w2) binding fence, empty-string reject: an INSERT with app.nav_computed_for = '''' is REJECTED — the explicit `= ''''` arm of the fence; a bound-but-empty GUC must never read as "bound"'
);

-- (w3) THE POINT OF THE WHOLE FENCE: the GUC names one tenant, the row claims another.
--      LEG-ISOLATION NOTE: the row targets tenant E, not tenant A, deliberately. If the fence
--      were broken this INSERT would SUCCEED, and a stray row on A would perturb the counts in
--      (a1)/(a5)/(e3) — three unrelated legs going RED for a reason that has nothing to do with
--      what they assert. Discovered by running the inversion: keeping the mismatch on a tenant no
--      read leg counts means a broken fence REDs (w3) and only (w3).
select set_config('app.nav_computed_for', :'tb', true);
select throws_like(
  format($$ insert into pfin.nav_daily (users_id, nav_date, nav_value) values (%L, '2026-06-03', 10000.00) $$, :'te'),
  '%write-tenant binding REJECTED%',
  '(w3) binding fence, CROSS-TENANT POISONING: the GUC says the database served tenant B, but the row claims a different tenant -> REJECTED. This is the singular-GUC hijack path (auth.uid() resolves the legacy request.jwt.claim.sub FIRST), where ONE tenant''s NAV would be written under EVERY tenant''s users_id with no code bug and a cleanly-passing app-layer assertion. Append-only + forward-only means such a row could never be corrected by ANY role — RED if the trigger were dropped'
);

-- (w4) CORRECTLY BOUND -> ACCEPTED. Without this the whole leg could be a table nobody can write.
select set_config('app.nav_computed_for', :'te', true);
select lives_ok(
  format($$ insert into pfin.nav_daily (users_id, nav_date, nav_value) values (%L, '2026-06-05', 10000.00) $$, :'te'),
  '(w4) binding fence, correctly-bound control: GUC = the row''s own users_id -> INSERT ACCEPTED. Proves (w1)-(w3) reject on the BINDING and not because the write path is dead, and guards an over-broad fence that would kill the cron outright'
);

-- (w5) IDEMPOTENT RE-RUN — Sec condition 2: the re-run must report ROW_COUNT = 0.
--   Uses the VERBATIM production statement (targeted `on conflict (users_id, nav_date) do
--   nothing`) via pg_temp.qa_rc, and asserts the rowcount the worker actually branches on.
--   The binding fence fires BEFORE conflict detection (Architect measured this; so did I), so a
--   same-day re-run still passes through the B7 fence rather than slipping past it — a re-run is
--   exactly where a badly-scoped fence would break the cron.
--   ⚠ WHY NOT `DO UPDATE`: DO NOTHING takes no UPDATE path, so the append-only trigger is never
--   tripped. `DO UPDATE` would hit fn_nav_daily_block_mutation and, more importantly, would be
--   semantically wrong — a frozen checkpoint is a historical fact. This is a CORRECTNESS
--   constraint, not a style preference: do not "fix" a stale checkpoint by reaching for DO UPDATE.
select is(
  pg_temp.qa_rc(:'te'::uuid, '2026-06-05', 99999.00),
  0,
  '(w5) idempotent re-run reports ROW_COUNT = 0: the VERBATIM production statement re-run against an existing (users_id, nav_date) inserts nothing and reports 0 — the value nav_daily.py branches on via result.rowcount. RED if the re-run started inserting or erroring, which would break the cron''s idempotency'
);

-- (w12) NON-VACUOUS CONTROL for (w5): the same statement on a NEW day reports ROW_COUNT = 1.
select is(
  pg_temp.qa_rc(:'te'::uuid, '2026-06-09', 1234.00),
  1,
  '(w12) rowcount control: the SAME production statement on a NEW (users_id, nav_date) reports ROW_COUNT = 1 — proving (w5)''s 0 means "already present", not "the statement silently does nothing". Without this, a fully broken append path would satisfy (w5)'
);
-- =====================================================================
-- (w8)-(w11) COLUMN-GRANT BOUNDARY — the ratified least-privilege shape.
--   HISTORY, because the retirement condition changed twice and THAT is the lesson:
--     · (w8) began as a DEFECT MARKER: the TARGETED `on conflict (users_id, nav_date) do
--       nothing` emitted by nav_daily.py raised 42501 — a specified conflict target requires
--       SELECT and service_role held INSERT only. The cron could not append AT ALL, on EVERY
--       run, not just re-runs.
--     · Inversion INV-B4 showed it self-retiring under remediation (b) (a full SELECT grant).
--     · Sec first ruled (C) (untargeted form, no grant change) — under which it does NOT
--       self-retire: targeted still fails, the assertion stays green, the worker simply stops
--       emitting that shape. RETIREMENT CONDITIONS ARE REMEDIATION-SPECIFIC (RT-31 leg (g)): an
--       inversion proves retirement under ONE remediation, not under the one actually chosen.
--     · Sec then RE-RULED for the COLUMN-LEVEL grant, the final shape:
--           grant select (users_id, nav_date) on pfin.nav_daily to service_role;
--       Under it the targeted form SUCCEEDS, so the original assertion genuinely DID retire —
--       and was REPLACED, not deleted. Deleting it would have dropped the coverage entirely.
--   SEC CONDITION 2 — the negatives below are LOAD-BEARING: without them the battery cannot
--   DISTINGUISH A COLUMN GRANT FROM A TABLE GRANT, and the grant could silently widen to a full
--   SELECT with nothing going RED. (h17) pins the same property as a catalog fact.
--   WHY THE COLUMN GRANT IS THE STRONGEST OF THE FOUR OPTIONS: the writer can ARBITRATE the
--   conflict — it reads users_id + nav_date, the key — while NEVER being able to read nav_value,
--   the actual financial figure. Least privilege is preserved at COLUMN granularity instead of
--   being traded away wholesale, which option (b) would have done.
--   NOTE ON SIGNAL: (w9)/(w10) both surface as 'permission denied for table nav_daily' —
--   PostgreSQL reports a column-privilege failure at TABLE granularity. They are distinguished
--   by the STATEMENT under test, not by the message.
-- =====================================================================
-- (w8) the PRODUCTION statement shape succeeds under the column grant.
select lives_ok(
  format($$ insert into pfin.nav_daily (users_id, nav_date, nav_value) values (%L, '2026-06-06', 500.00)
              on conflict (users_id, nav_date) do nothing $$, :'te'),
  '(w8) production statement shape: the TARGETED `on conflict (users_id, nav_date) do nothing` — the form nav_daily.py emits — SUCCEEDS under the 054 column grant `select (users_id, nav_date)`. RED if that grant were dropped, returning the W-1 cron to the 42501 that left it unable to append at all'
);

-- (w9) THE BOUNDARY the column grant buys: the writer cannot read the figure.
select throws_like(
  $$ select nav_value from pfin.nav_daily limit 1 $$,
  'permission denied for table nav_daily',
  '(w9) column boundary (Sec condition 2): service_role CANNOT read nav_value — the actual net-worth figure — even though it may read the key columns it needs to arbitrate a conflict. This is what makes the column grant strictly better than a full SELECT grant; RED the moment the grant widens to `select on pfin.nav_daily`'
);

-- (w10) the same boundary via the shape a careless refactor reaches for by reflex.
select throws_like(
  $$ select * from pfin.nav_daily limit 1 $$,
  'permission denied for table nav_daily',
  '(w10) column boundary, star form (Sec condition 2): service_role CANNOT `select *` from pfin.nav_daily — a bare star reaches nav_value and is denied. Asserted separately from (w9) because `select *` is what a refactor reaches for by reflex, and it must fail just as closed'
);

-- (w11) non-vacuous positive: the two granted columns ARE readable — so (w9)/(w10) are
--       COLUMN-scoped denials, not a blanket table lock (else (w8) could not arbitrate at all).
select lives_ok(
  format($$ select users_id, nav_date from pfin.nav_daily where users_id = %L $$, :'te'),
  '(w11) column boundary non-vacuous: service_role CAN read exactly (users_id, nav_date) — proving (w9)/(w10) are COLUMN-scoped denials rather than a blanket table lock, and that the conflict-arbitration path (w8) depends on is genuinely open'
);

select set_config('role', 'postgres', true);

-- (w6) ...and the re-run is a REAL no-op: still exactly one row, value UNCHANGED (not overwritten).
-- (numeric-typed array comparison, not text — so a trailing-zero/scale difference cannot make
--  this pass or fail for the wrong reason.)
select is(
  (select array[count(*)::numeric, max(nav_value)] from pfin.nav_daily
     where users_id = :'te'::uuid and nav_date = '2026-06-05'),
  array[1::numeric, 10000.00::numeric],
  '(w6) binding fence, re-run is a TRUE no-op: after (w5) the (tenant E, 2026-06-05) checkpoint is still exactly 1 row and nav_value is STILL 10000.00 (not the 99999.00 the re-run carried) — proves DO NOTHING did not silently degrade into DO UPDATE and overwrite a frozen checkpoint'
);

-- (w7) the new BEFORE INSERT fence has NOT displaced the immutability fences. With the GUC
--      correctly bound, an UPDATE still raises the IMMUTABILITY message, never the binding token.
--      Run at role=postgres (owner) so the ACL cannot be what stops it.
select throws_like(
  format($$ update pfin.nav_daily set nav_value = 1.00 where users_id = %L and nav_date = '2026-06-05' $$, :'te'),
  'pfin.nav_daily is immutable%UPDATE blocked%',
  '(w7) fence independence: with app.nav_computed_for CORRECTLY bound, an UPDATE is still blocked by the IMMUTABILITY fence and reports `is immutable`, never `write-tenant binding REJECTED` — the two fence families are independent and their signals are textually disjoint, so neither can mask or substitute for the other'
);

-- ---------------------------------------------------------------------
-- FIXTURE nav_daily rows (PRIVILEGED postgres session — bypasses RLS AND the table ACL).
-- Every INSERT binds app.nav_computed_for to the row's OWN users_id first: the B7 fence is
-- BEFORE INSERT and role-agnostic, so even the privileged fixture path must satisfy it.
-- ---------------------------------------------------------------------
select set_config('app.nav_computed_for', :'ta', true);
insert into pfin.nav_daily (users_id, nav_date, nav_value)
  values (:'ta', '2026-07-30', 100000.00) returning nav_id as nav_a1 \gset
insert into pfin.nav_daily (users_id, nav_date, nav_value)
  values (:'ta', '2026-07-31', 101000.00);
select set_config('app.nav_computed_for', :'tb', true);
insert into pfin.nav_daily (users_id, nav_date, nav_value)
  values (:'tb', '2026-07-31',  55000.00) returning nav_id as nav_b1 \gset
select set_config('app.nav_computed_for', :'tc', true);
insert into pfin.nav_daily (users_id, nav_date, nav_value)
  values (:'tc', '2026-07-31',   7000.00);
select set_config('app.nav_computed_for', :'td', true);
insert into pfin.nav_daily (users_id, nav_date, nav_value)
  values (:'td', '2026-07-31',  42000.00);

-- =====================================================================
-- LEG (h) — ACL POSTURE (catalog facts; role-agnostic, run as postgres).
--   RUNS FIRST BY NECESSITY: (h6)/(h7) assert the PRODUCTION least-privilege service_role ACL,
--   and leg (c) below installs a TEST-ONLY service_role UPDATE/DELETE grant. Asserting them
--   afterwards would read the test grant and pass vacuously forever.
-- =====================================================================
-- (h1) non-vacuous ACL positive — authenticated HOLDS SELECT, so legs (a)/(e) test RLS, not GRANTs.
select ok(
  has_table_privilege('authenticated', 'pfin.nav_daily', 'SELECT'),
  '(h1) ACL positive: authenticated HOLDS SELECT on pfin.nav_daily — the ACL is OPEN, so the isolation + backstop legs are genuine RLS tests and not GRANT tests (PR #106 grant-then-RLS root-cause guard)'
);
-- (h2) authenticated holds NO INSERT — attribution proof for (b1).
select ok(
  not has_table_privilege('authenticated', 'pfin.nav_daily', 'INSERT'),
  '(h2) least-privilege: authenticated holds NO INSERT on pfin.nav_daily (proves (b1) is a missing GRANT, not an RLS reject — a user cannot forge a NAV checkpoint)'
);
-- (h3) authenticated holds NO UPDATE — attribution proof for (b2).
select ok(
  not has_table_privilege('authenticated', 'pfin.nav_daily', 'UPDATE'),
  '(h3) least-privilege: authenticated holds NO UPDATE on pfin.nav_daily (append-only from the user tier; proves (b2) is an ACL denial)'
);
-- (h4) authenticated holds NO DELETE — attribution proof for (b3).
select ok(
  not has_table_privilege('authenticated', 'pfin.nav_daily', 'DELETE'),
  '(h4) least-privilege: authenticated holds NO DELETE on pfin.nav_daily (a user cannot erase an inconvenient checkpoint; proves (b3) is an ACL denial)'
);
-- (h5) service_role HOLDS INSERT — the W-1 cron append path.
select ok(
  has_table_privilege('service_role', 'pfin.nav_daily', 'INSERT'),
  '(h5) ACL positive: service_role HOLDS INSERT on pfin.nav_daily (the W-1 cron append path via TenantBoundConnection — RED if the writer grant were dropped and the trend silently stopped accumulating)'
);
-- (h6) LEAST-PRIVILEGE: service_role holds NO UPDATE (asserted BEFORE leg (c)'s test-only grant).
select ok(
  not has_table_privilege('service_role', 'pfin.nav_daily', 'UPDATE'),
  '(h6) LOAD-BEARING least-privilege: service_role — the W-1 worker''s actual WRITE role (reached via SET ROLE from the NOINHERIT `pfin_etl` login) — holds NO UPDATE on pfin.nav_daily. NOTE: service_role is NOT insert-only any more — the ratified column grant gives it SELECT on (users_id, nav_date) so it can arbitrate the ON CONFLICT target; that is asserted by (h17)/(w9)-(w11). What remains absolute is that it can never MUTATE. Because NOINHERIT means no ambient privilege, this grant IS the fence, not bookkeeping. Asserted BEFORE leg (c) opens a TEST-ONLY grant, so an erosion cannot be masked'
);
-- (h7) LEAST-PRIVILEGE: service_role holds NO DELETE (asserted BEFORE leg (c)'s test-only grant).
select ok(
  not has_table_privilege('service_role', 'pfin.nav_daily', 'DELETE'),
  '(h7) LOAD-BEARING least-privilege: service_role holds NO DELETE on pfin.nav_daily — defence-in-depth in FRONT of the immutability trigger, and under NOINHERIT a real fence rather than an inherited detail. Together with (h6)/(h8): the writer may APPEND and may READ THE TWO ARBITER COLUMNS, and may do nothing else — it cannot update, delete, truncate, or read nav_value'
);
-- (h8) neither privileged tier holds TRUNCATE (the statement trigger is the regardless-of-grant guarantee).
select ok(
  not has_table_privilege('service_role', 'pfin.nav_daily', 'TRUNCATE')
  and not has_table_privilege('authenticated', 'pfin.nav_daily', 'TRUNCATE'),
  '(h8) least-privilege: neither service_role nor authenticated holds TRUNCATE on pfin.nav_daily (the 054 REVOKE TRUNCATE FROM PUBLIC holds) — the statement-level trigger asserted in (d1) is the regardless-of-grant backstop behind this'
);
-- (h9) anon zero-grant — a tenant-scoped SD-24 table must never be anon-reachable.
select ok(
  not has_table_privilege('anon', 'pfin.nav_daily', 'SELECT'),
  '(h9) anon zero-grant: anon holds NO SELECT on pfin.nav_daily (SD-24 tenant-scoped net-worth history must never be reachable by an unauthenticated role)'
);
-- ---------------------------------------------------------------------
-- (h10)-(h14) B8 CREDENTIAL-MODEL INTEGRITY — the ETL's own login role `pfin_etl` (migration
--   055 / ADR-041; B8 option (B), F/CTO-ratified 2026-08-02).
--   ⚠ RETARGETED. An earlier revision asserted NOINHERIT on `authenticator`. Under B8 the ETL no
--   longer uses `authenticator` (that role remains real — it fronts PostgREST and provider-sync —
--   which is exactly what made the stale assertion DANGEROUS: it stayed GREEN while asserting a
--   true fact about the WRONG SUBJECT. A green test on the wrong subject is worse than a missing
--   one, because it reads as coverage.) The subject is now `pfin_etl`.
--   CROSS-MIGRATION DEPENDENCY: these six assertions require **055** applied. On the CI reset
--   stack every migration is applied before the battery runs, so ordering is a non-issue there;
--   locally, 055 must be in the rolled-back setup alongside 054. RED-until-055-applied is
--   EXPECTED, and RED if 055 were reverted or the role renamed.
-- ---------------------------------------------------------------------
-- (h10a) DEPENDENCY GUARD — must come first and must be LEGIBLE.
--   MEASURED: without 055 the battery does not merely go RED, it HARD-ABORTS here —
--   has_table_privilege('pfin_etl', …) raises `role "pfin_etl" does not exist`, which killed the
--   run at (h11) and left 35 of 53 assertions UNRUN. In CI that reads as a broken test file, not
--   as "a dependency is missing". This guard turns that into one unambiguous line, and (h11)
--   below is written fail-CLOSED so a missing role can never pass vacuously either.
select ok(
  (select count(*) = 1 from pg_roles where rolname = 'pfin_etl'),
  '(h10a) DEPENDENCY: migration 055 is applied and the role `pfin_etl` exists. If this is the only RED in the file, 055 has not been applied to this stack — apply it rather than editing (h10)-(h14b). All six credential-model assertions below read this role'
);

-- (h10) NOINHERIT — the flag the entire least-privilege model rests on.
select ok(
  (select not rolinherit from pg_roles where rolname = 'pfin_etl'),
  '(h10) B8 credential model: the ETL''s LOGIN role `pfin_etl` is NOINHERIT (rolinherit = f) — it is a member of service_role but holds NONE of its privileges ambiently, so a privileged write requires an explicit SET ROLE and a FORGOTTEN one fails 42501 loudly instead of silently running elevated. RED if rolinherit ever flipped, which would silently collapse the model (h5)-(h7) rest on'
);
-- (h11) NOINHERIT PROVEN AT THE PRIVILEGE LAYER, not just as a catalog flag. This is the
--       assertion with real teeth: has_table_privilege() honours inheritance, so pfin_etl must
--       report NO ambient INSERT even though it is a member of service_role, which (h5) proves
--       DOES hold INSERT. The pair (h5 true / h11 false) is the whole B8 property in two lines.
--       FAIL-CLOSED FORM: has_table_privilege() RAISES on a non-existent role, which would abort
--       the whole file. Guarding it through a pg_roles lookup makes a missing role yield NULL,
--       and the coalesce defaults to TRUE (= "has the privilege") so the assertion goes RED
--       rather than passing vacuously. Defaulting to FALSE here would have been the silent-pass
--       bug this very assertion exists to catch.
select ok(
  not coalesce((select has_table_privilege('pfin_etl', 'pfin.nav_daily', 'INSERT')
                  from pg_roles where rolname = 'pfin_etl'), true)
  and not coalesce((select has_table_privilege('pfin_etl', 'pfin.nav_daily', 'SELECT')
                  from pg_roles where rolname = 'pfin_etl'), true)
  and not coalesce((select has_schema_privilege('pfin_etl', 'pfin', 'USAGE')
                  from pg_roles where rolname = 'pfin_etl'), true),
  '(h11) B8 NOINHERIT proven at the PRIVILEGE layer: `pfin_etl` reports NO ambient INSERT and NO ambient SELECT on pfin.nav_daily even though it is a member of service_role, which (h5) proves DOES hold INSERT — it does not even hold USAGE on the pfin SCHEMA — the login identity''s entire reach is via explicit SET ROLE. RED if NOINHERIT were lost, or if a direct table grant or schema-USAGE grant were made to pfin_etl'
);
-- (h12) exactly the two ratified memberships — no third role crept in.
--   ⚠ NOT de-duplicated on PURPOSE (§7.21 item 1, Sec-ruled 2026-08-17):
--   `string_agg` with no `distinct` is what CAUGHT the 2026-08-17 doubled-
--   membership drift live (`authenticated,authenticated,service_role,
--   service_role` — the SAME membership recorded twice under TWO GRANTORS).
--   `distinct` is FORBIDDEN in this leg: it would make the assertion
--   PERMANENTLY TOLERATE exactly the drift it just caught. Sec, verbatim:
--   "The legs are correct; the environment is wrong." Fix a real
--   duplicate-grantor drift with `REVOKE service_role FROM pfin_etl GRANTED
--   BY <grantor>` (per grantor), never by loosening this query.
select is(
  (select string_agg(g.rolname, ',' order by g.rolname)
     from pg_auth_members m
     join pg_roles g on g.oid = m.roleid
     join pg_roles u on u.oid = m.member
    where u.rolname = 'pfin_etl'),
  'authenticated,service_role',
  '(h12) B8 membership set: `pfin_etl` holds EXACTLY the two ratified memberships — service_role (privileged writes) and authenticated (the W-1 session-impersonation read path under RLS). RED if a THIRD membership were granted (widening the ETL''s reach with no migration to nav_daily itself) OR if the SAME membership were granted TWICE under two grantors (the 2026-08-17 doubled-membership drift this exact query caught live — cause: duplicate grantor, not a third role; fix: `REVOKE ... GRANTED BY <grantor>` per grantor, never `string_agg(distinct ...)`, which would make this leg permanently tolerate the drift it just caught)'
);
-- (h13) NOT superuser / NOT bypassrls / NOT owner — this is what makes (o6)/(o7) true for the
--       ETL's REAL login identity rather than only for service_role, and therefore what makes
--       054's append-only + B7 fences un-bypassable BY THE WRITER.
select ok(
  (select not rolsuper and not rolbypassrls from pg_roles where rolname = 'pfin_etl')
  and (select tableowner <> 'pfin_etl' from pg_tables where schemaname = 'pfin' and tablename = 'nav_daily'),
  '(h13) B8 un-bypassable-by-the-writer: `pfin_etl` is NOT superuser, NOT BYPASSRLS, and is NOT the owner of pfin.nav_daily — so it can reach NEITHER owner-only bypass (ALTER TABLE … DISABLE TRIGGER, session_replication_role). This is what extends (o6)/(o7) from service_role to the ETL''s actual login identity, and it is why 054''s immutability + B7 binding fences cannot be switched off by the process they constrain'
);
-- (h14a)/(h14b) FAIL-CLOSED AT MIGRATION TIME — pinned to 055's ratified "inert by construction"
--       shape. SPLIT into two assertions per §7.21 item 2 (Sec-ruled 2026-08-17) — was one
--       leg named (h14); see the split note just above the assertions below for why.
--       ⚠ RE-PINNED MID-SESSION. 055 changed under this battery while it was being written:
--       Architect resolved the Sec passwordless-window NOTE by creating the role
--       **NOLOGIN + NOINHERIT + NO PASSWORD** ("inert by construction"; flipped with a single
--       `ALTER ROLE pfin_etl WITH LOGIN PASSWORD '<secret>'` at deploy) rather than the
--       LOGIN-with-no-password form the file previously carried.
--       An earlier draft here asserted the weaker DISJUNCTIVE invariant
--           (not rolcanlogin OR rolpassword is null)
--       which was chosen to survive either shape. Under NOLOGIN that disjunct is satisfied by
--       `not rolcanlogin` ALONE, so it would pass even if a password were committed — and the
--       inversion proved it: sabotaging the role WITH a password produced ZERO reds. The
--       assertion was true but had stopped discriminating. It now pins BOTH halves of the
--       ratified contract, so either erosion is caught:
--         · rolcanlogin = false  — the role cannot authenticate at all as shipped
--         · rolpassword is null  — no credential is committed to the repo, not even a dormant
--           one that would go live the instant someone flips LOGIN
--       If Architect ever returns to the LOGIN-with-no-password shape this goes RED, which is
--       correct: a change to the provisioning contract SHOULD require a deliberate test update.
--       ⚠ MUST READ pg_authid, NOT pg_roles. `pg_roles.rolpassword` is the literal string
--       '********' for EVERY role — MEASURED — so `rolpassword is null` is ALWAYS false there
--       and this assertion's second half would silently invert. This already caused one false
--       discrepancy report elsewhere today; do NOT "simplify" it back to pg_roles.
--       ⚠ THIS ASSERTS **MIGRATION-TIME** STATE. In a provisioned environment `rolcanlogin` is
--       legitimately TRUE — the deploy step flips it. A future reader hitting a RED here in a
--       deployed context is seeing an environment difference, not a regression. (055's CONTRACT
--       block carries the same warning.) NOLOGIN is the PRIMARY fence and no-password the
--       secondary: rolcanlogin is checked BEFORE any auth method, so it holds regardless of
--       pg_hba — which matters because the local stack's pg_hba grants `trust` on 127.0.0.1/32,
--       and `trust` never consults a password at all. That is why LOGIN-with-no-password was
--       rejected in favour of NOLOGIN-then-flip.
--
--       ⚠ HALF-SPECIFIC ANNOTATION (Sec-ruled, meta/battery-local-stack-disposition — the
--       assertion/helper below are UNTOUCHED; this is documentation only, NOT a blanket
--       file-level amnesty for a RED here). The local dev stack now carries the ADR-053-
--       ratified post-recovery state (docs/records/2026-08-14-db-reset-incident.md,
--       "Recovery completed" section): `pfin_etl` was armed LOGIN for the supervised recovery
--       run and re-disarmed to NOLOGIN afterward, but the PASSWORD was DELIBERATELY RETAINED
--       (F/CTO-ratified), not cleared. That makes THIS LEG'S TWO HALVES ASYMMETRIC on THIS
--       stack, and they must be read separately, never as one verdict:
--         · `rolpassword is null` going RED here = EXPECTED-DIFFERENT on this stack, cited
--           to the ADR-053 reissue + the incident record above. NOT a regression.
--         · `rolcanlogin = false` going RED here = NEVER excused, on any stack, for any
--           reason. A RED on rolcanlogin is a genuine finding requiring investigation, not
--           an environment difference — full stop. It matters MOST locally, specifically:
--           the local stack's pg_hba grants `trust` on 127.0.0.1/32, and `trust` never
--           consults a password at all — so on THIS stack, NOLOGIN is the ONLY thing
--           standing between an inert role and a directly-usable one. A password alone
--           (whatever its provenance) is not what protects this stack; rolcanlogin is.
--       Sec's own words on why this is written per-half rather than as a file-level note:
--       treating the WHOLE leg as "expected on the live stack" would be "the h14 defect
--       reproduced in prose, one layer up" — the exact blind-disjunction shape this leg was
--       hardened against in the first place. If this leg goes RED, check WHICH half via
--       `select rolcanlogin, rolpassword is null from pg_authid where rolname = 'pfin_etl'`
--       BEFORE concluding anything — do not assume it's the expected half.
--       ⚠ VENUE — and it is NOT a scratch DB (QA finding, this PR). Roles are CLUSTER-level:
--       `pg_authid` is a SHARED catalog, so `pfin_etl`'s retained password is identical in
--       EVERY database of this cluster — a scratch database created here inherits it, and a
--       RED on the password half there means nothing new. The scratch DB is the sanctioned
--       local venue for the DATA-dependent batteries (053 / 062 / 063 / 064); it does NOT
--       clear h14's password half. Only a FRESH CLUSTER does.
--       ⚠ One already exists and runs on every PR: CI (.github/workflows/db-tests.yml) does
--       `supabase start` on a clean runner, so `pfin_etl` is exactly as migration 055 ships
--       it and BOTH halves of h14 are genuinely verified there, every time. h14 is therefore
--       NOT unverifiable — it is VERIFIED IN CI and EXPECTED-DIFFERENT locally. Do not
--       "simplify" this assertion on the belief that nothing checks it.
--       ⚠ §7.21 item 2 (Sec-ruled 2026-08-17): SPLIT into two assertions (plan 1->2) so a RED
--       self-identifies which half fired without sending the reader to a manual query — the
--       whole point of the per-half annotation directly above. Semantics UNCHANGED (still both
--       halves of the same ratified contract); only the reporting granularity moves.
select ok(
  pg_temp.qa_pfin_etl_rolcanlogin_false(),
  '(h14a) B8 fail-closed provisioning, NEVER-EXCUSED half: as shipped by migration 055, `pfin_etl` is NOLOGIN (rolcanlogin = false) — cannot authenticate as shipped, flipped to a working credential only at deploy via a single ALTER ROLE from the Coolify secret. RED on ANY stack, for ANY reason — not an environment difference, a genuine finding. Most load-bearing locally: the local stack''s pg_hba grants `trust` on 127.0.0.1/32 (never consults a password), so NOLOGIN is the ONLY thing standing between an inert role and a directly-usable one here'
);
select ok(
  pg_temp.qa_pfin_etl_rolpassword_null(),
  '(h14b) B8 fail-closed provisioning, EXPECTED-DIFFERENT-LOCALLY half: as shipped by migration 055, `pfin_etl` carries NO PASSWORD (rolpassword is null) — no credential committed to the repo, not even a dormant one that would go live the instant someone flips LOGIN. RED in CI (fresh cluster, migration-055-shipped state) is a genuine finding. RED on THIS local stack is EXPECTED-DIFFERENT (meta/battery-local-stack-disposition, ADR-053 reissue + docs/records/2026-08-14-db-reset-incident.md "Recovery completed": the password was DELIBERATELY RETAINED, F/CTO-ratified) — verified in CI every PR (.github/workflows/db-tests.yml, clean-runner `supabase start`), not unverifiable'
);

-- (h18) `SET ROLE` MUST ACTUALLY WORK — the per-membership SET option.
--   ⚠ THE EXACT MIRROR OF THE (h15)/(h16) FINDING, and neither assertion catches the other's
--   failure. On PG16+ these are THREE independent per-membership/role settings:
--       rolinherit = false     governs FUTURE memberships           -> (h10)
--       MEMBER ∧ ¬USAGE        proves no implicit privilege TODAY   -> (h15)/(h16)
--       set_option = true      proves SET ROLE WILL ACTUALLY WORK   -> (h18, this one)
--   The symmetry: INHERIT can be silently turned ON behind a false `rolinherit` (caught by the
--   USAGE half of (h15)/(h16)); SET can be silently turned OFF behind a TRUE `MEMBER` — and
--   until this assertion, that was caught by NOTHING. MEASURED: `GRANT service_role TO pfin_etl
--   WITH SET FALSE` flips set_option to f while pg_has_role(...,'MEMBER') stays TRUE. The W-1
--   worker would then fail 42501 at `set local role service_role` on EVERY run while (h11)/(h12)
--   stayed green. Role-level flags read reassuringly; the PER-MEMBERSHIP option decides.
--   055 deliberately omits any SET clause so the SET-TRUE default applies — asserted rather than
--   assumed, because the worker's entire two-role sequence (SET ROLE authenticated to read, SET
--   ROLE service_role to write) rests on that default holding.
--   This is also the first CATALOG-LEVEL proof that the worker's SET ROLE path works at all:
--   the login->SET ROLE chain cannot be exercised end-to-end without a committed password
--   (055 ships NOLOGIN by design), so set_option on both edges is the closest verifiable
--   evidence — previously proven-but-unpinned.
--   FAIL-CLOSED: string_agg over a missing role yields NULL, which fails the is() — RED, and no
--   function call that could abort the file (the qa_rc/(h11) lesson).
--   LEG INDEPENDENCE: the query is SCOPED to the two required edges rather than aggregating every
--   membership. Unscoped, granting a THIRD membership would RED both this leg and (h12), giving
--   two failures for one defect. Scoped, the split is clean: (h12) owns "which memberships
--   exist", (h18) owns "can SET ROLE actually be used on the two that must". Verified by
--   inversion — this is the same leg-coupling rule stated in the BATTERY-DESIGN LESSON block,
--   applied to a leg added after it was written.
--   ⚠ §7.21 item 1 addendum (Sec-ruled 2026-08-17): this scoping was designed against
--   MEMBERSHIP-SET drift (a third role granted) — it does NOT model GRANTOR MULTIPLICITY. A
--   duplicate-grantor defect (the SAME edge granted twice under two grantors) reddens BOTH this
--   leg and (h12) exactly the way an unscoped query would for a third membership: `string_agg`
--   with no `distinct` (required here for the same reason as h12 — see its note) reports
--   `authenticated=true,authenticated=true,service_role=true,service_role=true` against the
--   expected two-entry string, RED on both legs for one root cause. A fence''s independence
--   argument is only as good as the drift dimensions it enumerated when written; grantor
--   multiplicity was not one of them.
select is(
  (select string_agg(g.rolname || '=' || m.set_option::text, ',' order by g.rolname)
     from pg_auth_members m
     join pg_roles g on g.oid = m.roleid
     join pg_roles u on u.oid = m.member
    where u.rolname = 'pfin_etl'
      and g.rolname in ('service_role', 'authenticated')),   -- scoped: see LEG INDEPENDENCE below
  'authenticated=true,service_role=true',
  '(h18) SET ROLE is actually permitted: BOTH pfin_etl memberships carry set_option = true, so the worker can `set local role authenticated` (read) and `set local role service_role` (write). RED on a re-grant WITH SET FALSE (which flips set_option to f while pg_has_role(...,''MEMBER'') stays TRUE, so (h11)/(h12)/(h15)/(h16) would ALL stay green while the cron failed 42501 at SET ROLE on every run) OR on the SAME membership granted twice under two grantors (the duplicate-grantor drift class this file also caught at h12 — cause: duplicate grantor, not a third role; fix: `REVOKE ... GRANTED BY <grantor>` per grantor, never `distinct`)'
);

-- (h17) THE COLUMN GRANT AS A CATALOG FACT — complements the behavioural (w9)-(w11).
--   Sec condition 2: the battery must DISTINGUISH a column grant from a table grant. That
--   distinction is invisible to the positive assertions alone — BOTH grant shapes make the
--   targeted ON CONFLICT succeed, so (w8)/(g1) pass under either. Only the negatives separate
--   them. (w9)/(w10) prove it behaviourally; this proves it in the ACL, so a widening is caught
--   even if someone later changes the statements those legs run.
--   ⚠ REPORTING TRAP — USE has_column_privilege(), NOT information_schema.column_privileges.
--   MEASURED: that view lists service_role against ALL FIVE columns, because table-level INSERT
--   expands per-column. Split by privilege_type it is INSERT -> 5 columns, SELECT -> 2. An
--   unsplit count therefore READS EXACTLY LIKE A TABLE-LEVEL GRANT and would lead a reader
--   either to write a wrong expectation here or to conclude the grant is broader than it is.
--   Do not "simplify" this assertion into that view.
--   ⚠ RELATEDLY: 054 carries `revoke all (nav_value) … from service_role`. That statement is a
--   NO-OP against the current grant set and does NOT survive a future table-level GRANT SELECT
--   — PostgreSQL has no negative grants. It is declarative documentation only. This assertion
--   deliberately pins the OUTCOME (nav_value not selectable), never the revoke, so it cannot be
--   read as evidence that the revoke protects anything.
--   Full column scope asserted — all five columns, measured, so a widening to ANY third column
--   is caught rather than only a widening to nav_value.
select ok(
  has_column_privilege('service_role', 'pfin.nav_daily', 'users_id', 'SELECT')
  and has_column_privilege('service_role', 'pfin.nav_daily', 'nav_date', 'SELECT')
  and not has_column_privilege('service_role', 'pfin.nav_daily', 'nav_value', 'SELECT')
  and not has_column_privilege('service_role', 'pfin.nav_daily', 'nav_id', 'SELECT')
  and not has_column_privilege('service_role', 'pfin.nav_daily', 'created_at', 'SELECT')
  and not has_table_privilege('service_role', 'pfin.nav_daily', 'SELECT'),
  '(h17) column-grant ACL shape: service_role holds SELECT on EXACTLY the two arbiter columns (users_id, nav_date) and on NO other column (nav_id, nav_value, created_at all denied), and holds NO table-level SELECT. This is what distinguishes a COLUMN grant from a TABLE grant at the catalog layer — a distinction the positive legs cannot make, since both shapes let the targeted ON CONFLICT succeed. RED if the grant widened to `grant select on pfin.nav_daily` or to any third column'
);

-- (h15)/(h16) NOINHERIT EXPRESSED IN THE TERMS THAT MATTER (Architect's formulation).
--   `rolinherit` is one attribute; the PROPERTY is the MEMBER-yes / USAGE-no split:
--     MEMBER = "may SET ROLE to it"        -> must be TRUE  (the ETL can reach its roles)
--     USAGE  = "holds its privileges now"  -> must be FALSE (only after an explicit SET ROLE)
--   Both guarded through a pg_roles lookup: pg_has_role() RAISES on a non-existent role, which
--   would ABORT the file rather than fail an assertion (the (h11)/qa_rc lesson, 4th instance —
--   every expression naming `pfin_etl` must degrade to a RED, never to an abort). The coalesce
--   defaults are chosen per-direction so a missing role fails CLOSED on both halves.
--   STRICTLY STRONGER THAN (h10), AND NOT REDUNDANT WITH IT — measured, not assumed:
--   in PostgreSQL 16+ inheritance is a PER-MEMBERSHIP option, and `rolinherit` is only the
--   DEFAULT applied when a membership is granted. Verified live: after `ALTER ROLE pfin_etl
--   INHERIT`, rolinherit flips to true but pg_has_role(...,'USAGE') stays FALSE for the existing
--   memberships; only `GRANT service_role TO pfin_etl WITH INHERIT TRUE` makes USAGE true.
--   So (h10) alone would MISS the modern way to break NOINHERIT — a per-membership inherit
--   grant — and (h15)/(h16) alone would miss a changed role default affecting FUTURE grants.
--   Both are needed; each catches what the other cannot. (This non-redundancy was surfaced by
--   running the inversion: sabotaging rolinherit REDded (h10) and left (h15)/(h16) green.)
select ok(
  coalesce((select pg_has_role('pfin_etl', 'service_role', 'MEMBER')
              from pg_roles where rolname = 'pfin_etl'), false)      -- missing role => RED
  and not coalesce((select pg_has_role('pfin_etl', 'service_role', 'USAGE')
              from pg_roles where rolname = 'pfin_etl'), true),      -- missing role => RED
  '(h15) B8 NOINHERIT as an authorization outcome: `pfin_etl` is a MEMBER of service_role (it MAY SET ROLE to it) but has NO USAGE (it does NOT hold its privileges without doing so). This MEMBER-yes/USAGE-no split IS the NOINHERIT posture stated in the terms that matter; RED if USAGE ever became true, which would mean the ETL runs privileged by default'
);
select ok(
  coalesce((select pg_has_role('pfin_etl', 'authenticated', 'MEMBER')
              from pg_roles where rolname = 'pfin_etl'), false)      -- missing role => RED
  and not coalesce((select pg_has_role('pfin_etl', 'authenticated', 'USAGE')
              from pg_roles where rolname = 'pfin_etl'), true),      -- missing role => RED
  '(h16) B8 NOINHERIT, read path: `pfin_etl` is a MEMBER of authenticated (the W-1 session-impersonation read path) but has NO USAGE — the ETL cannot read tenant data without an explicit SET ROLE, so an un-impersonated statement cannot silently run under a tenant identity'
);

-- =====================================================================
-- LEG (a) TENANT ISOLATION — the RT-31 core. Reads run FIRST (before any write leg) so the
--   counts are deterministic. Sessions are aal-LESS; A/B/C carry 'none' or no settings row, so
--   the aal2 backstop conjunct is TRUE for all of them and the ONLY active filter is the tenant
--   predicate. (The backstop dimension is isolated in leg (e).)
-- =====================================================================
-- (a1) non-vacuous positive: owner A reads EXACTLY its 2 own rows.
select _rls.expect_owner_can_read('pfin.nav_daily'::regclass, :'ta'::uuid, 2::bigint);

-- (a2) THE RT-31 ASSERTION: intruder B sees ZERO of A's rows.
select _rls.expect_cross_tenant_read_empty('pfin.nav_daily'::regclass, :'ta'::uuid, :'tb'::uuid);

-- (a3) non-vacuous positive, opposite direction: owner B reads EXACTLY its 1 own row.
select _rls.expect_owner_can_read('pfin.nav_daily'::regclass, :'tb'::uuid, 1::bigint);

-- (a4) symmetry: intruder A sees ZERO of B's rows (a one-way test can pass on a policy that
--      accidentally privileges one tenant).
select _rls.expect_cross_tenant_read_empty('pfin.nav_daily'::regclass, :'tb'::uuid, :'ta'::uuid);

-- (a5) UNSCOPED leak probe — the query an attacker actually issues. A reads the WHOLE table and
--      must get back exactly its own 2 of the 5 seeded rows. RED if nav_daily_select were
--      USING (true) / keyed on the wrong column / absent-with-a-permissive-default.
select is(
  _rls.count_as(:'ta'::uuid, null, 'select count(*) from pfin.nav_daily'),
  2::bigint,
  '(a5) unscoped leak probe: tenant A''s bare `select count(*) from pfin.nav_daily` returns 2 of the 5 seeded rows — its OWN only. RED if the SELECT policy were USING (true) or keyed on the wrong column; this is the read an attacker actually issues'
);

-- =====================================================================
-- LEG (b) NO-FORGE — authenticated cannot write a checkpoint at all.
--   Denial layer is the TABLE ACL (no write grant): message-precise, NOT a bare 42501 and NOT an
--   RLS WITH CHECK message. UPDATE/DELETE target REAL seeded rows (non-vacuous).
-- =====================================================================
select _rls.set_tenant(:'ta'::uuid);
-- (b1) authenticated INSERT of a checkpoint for ITSELF is denied (cannot forge own trend).
select throws_like(
  format($$ insert into pfin.nav_daily (users_id, nav_date, nav_value) values (%L, '2026-08-01', 999999.00) $$, :'ta'),
  'permission denied for table nav_daily',
  '(b1) LOAD-BEARING no-forge: authenticated INSERT denied at the GRANT layer (SELECT-only grant, no write policy) — a user cannot fabricate a NAV checkpoint into its own §2.1.2 trend'
);
-- (b2) authenticated UPDATE of its OWN real seeded row is denied (append-only from the user tier).
select throws_like(
  format($$ update pfin.nav_daily set nav_value = 1.00 where nav_id = %s $$, :nav_a1),
  'permission denied for table nav_daily',
  '(b2) LOAD-BEARING append-only: authenticated UPDATE of its OWN real seeded checkpoint denied at the GRANT layer — a user cannot revise recorded history (e.g. erase a drawdown)'
);
-- (b3) authenticated DELETE of its OWN real seeded row is denied.
select throws_like(
  format($$ delete from pfin.nav_daily where nav_id = %s $$, :nav_a1),
  'permission denied for table nav_daily',
  '(b3) LOAD-BEARING append-only: authenticated DELETE of its OWN real seeded checkpoint denied at the GRANT layer — a user cannot erase an inconvenient day'
);
-- (b5) authenticated TRUNCATE is fenced at the ACL layer, in FRONT of the statement trigger
--      (REVOKE TRUNCATE FROM PUBLIC + no grant). The trigger itself is proven at the OWNER tier
--      in (o4) — the only tier that actually holds TRUNCATE.
select throws_like(
  $$ truncate pfin.nav_daily $$,
  'permission denied for table nav_daily',
  '(b5) TRUNCATE, user tier: an authenticated TRUNCATE is denied at the GRANT layer before the statement trigger is even reached (REVOKE TRUNCATE FROM PUBLIC + no grant) — RED if a TRUNCATE grant ever reached authenticated'
);
select set_config('role', 'postgres', true);

-- (b4) RLS-LAYER default-deny BEHIND the ACL fence: ZERO non-SELECT policies exist. Catalog query,
--      role-independent — run privileged. This is the assertion that survives if a future migration
--      opens a write GRANT without auditing policies.
select is(
  (select count(*) from pg_policies
     where schemaname = 'pfin' and tablename = 'nav_daily' and cmd <> 'SELECT')::bigint,
  0::bigint,
  '(b4) RLS-layer write default-deny: ZERO non-SELECT (INSERT/UPDATE/DELETE/ALL) policies exist on pfin.nav_daily — defence-in-depth behind the ACL fence; RED the moment a write policy lands'
);

-- =====================================================================
-- LEG (e) aal2 STEP-UP BACKSTOP (C3 / ADR-029 / 025) — INHERITED, per-user-conditional.
--   Isolated from leg (a) on purpose: leg (a) proved the TENANT predicate with the backstop
--   trivially true; this leg varies the backstop with the tenant predicate held constant.
--   NOTE (spec deviation, deliberate — reported to Sec): RT-31 says "mfa_policy totp/passkey".
--   'passkey' is NOT a storable value in V1 — migration 025 PART 3 tightened the CHECK to
--   ('none','totp') and DEFERRED 'passkey' to Auth-6/SELF-289 (the 025 battery's cases D/E assert
--   that rejection with 23514). So the totp arm below is the ONLY reachable arm of the spec's
--   "totp/passkey" set; a 'passkey' arm here would be untestable-by-construction, and faking one
--   would be a false green. It re-arms with ZERO change when Auth-6 re-adds 'passkey' additively.
-- =====================================================================
-- (e1) THE BACKSTOP: totp-enrolled reader D at an aal1 session sees ZERO of its OWN rows.
select is(
  _rls.count_as(:'td'::uuid, 'aal1', format('select count(*) from pfin.nav_daily where users_id = %L', :'td')),
  0::bigint,
  '(e1) aal2 backstop: a totp-enrolled reader at aal1 sees 0 of its OWN nav_daily rows — RED if the backstop conjunct were dropped from nav_daily_select''s USING, which would let a stolen-password aal1 session read the entire net-worth trajectory through the direct PostgREST API (C6: the backstop is the ONLY layer there)'
);
-- (e2) NON-VACUITY + not-over-blocking: the SAME reader at aal2 sees its 1 row.
select is(
  _rls.count_as(:'td'::uuid, 'aal2', format('select count(*) from pfin.nav_daily where users_id = %L', :'td')),
  1::bigint,
  '(e2) aal2 backstop non-vacuous: the SAME totp reader stepped up to aal2 sees its 1 own row — proves (e1) blocks on aal and not on the user being row-less, and guards against an over-blocking backstop'
);
-- (e3) NOT-BLANKET: a 'none' reader at aal1 is UNAFFECTED.
select is(
  _rls.count_as(:'ta'::uuid, 'aal1', format('select count(*) from pfin.nav_daily where users_id = %L', :'ta')),
  2::bigint,
  '(e3) aal2 backstop NOT-BLANKET: a mfa_policy=''none'' reader at aal1 still sees its 2 own rows — RED if the clause degenerated into a blanket aal2 requirement (it gates the READER''s declared policy, never the row)'
);
-- (e4) COALESCE FAIL-SAFE: a reader with NO user_settings row (lazy provisioning) at aal1 is UNAFFECTED.
select is(
  _rls.count_as(:'tc'::uuid, 'aal1', format('select count(*) from pfin.nav_daily where users_id = %L', :'tc')),
  1::bigint,
  '(e4) aal2 backstop COALESCE fail-safe: a reader with NO pfin.user_settings row (lazy provisioning) at aal1 still sees its own row — RED if the subselect were not coalesced to ''none'' (NULL not in (...) evaluates NULL => the row is filtered => permanent self-lockout, the null-lockout bug 025 guards)'
);
-- (e5) ISOLATION ⟂ MFA: stepping up does not widen the reader beyond its own rows.
select is(
  _rls.count_as(:'tb'::uuid, 'aal2', format('select count(*) from pfin.nav_daily where users_id = %L', :'ta')),
  0::bigint,
  '(e5) ISOLATION ⟂ MFA: tenant B stepped up to aal2 STILL sees 0 of A''s rows — the aal conjunct is ANDed with, never replaces, users_id = auth.uid(); RED if a refactor made aal2 the sufficient condition'
);

-- =====================================================================
-- LEG (f) FINITENESS FENCE — nav_daily_value_finite under the service_role WRITER.
--   service_role bypasses RLS but NOT a table CHECK. Constraint-name-precise, plus a finite
--   positive control so an over-broad CHECK is caught too.
--   ⚠ GUC REQUIRED: the B7 binding fence is BEFORE INSERT and therefore fires BEFORE the CHECK.
--   Without app.nav_computed_for bound, every assertion here would meet `write-tenant binding
--   REJECTED` instead of the CHECK. Because these assertions match the CONSTRAINT NAME (disjoint
--   from the binding token) an unbound regression goes RED rather than false-GREEN — but RED for
--   the wrong reason is still wrong, so the GUC is bound explicitly per target tenant.
-- =====================================================================
select set_config('role', 'service_role', true);
select set_config('app.nav_computed_for', :'ta', true);   -- f1-f3 target tenant A
-- (f1) NaN rejected.
select throws_like(
  format($$ insert into pfin.nav_daily (users_id, nav_date, nav_value) values (%L, '2026-08-02', 'NaN'::numeric) $$, :'ta'),
  '%nav_daily_value_finite%',
  '(f1) finiteness fence: nav_value = NaN is REJECTED by nav_daily_value_finite (constraint-name-precise) even under the service_role writer — a NaN checkpoint would poison the §2.1.2 trend chart and every downstream period-over-period delta'
);
-- (f2) +Infinity rejected (unbounded numeric admits it — the 053 N1 lesson).
select throws_like(
  format($$ insert into pfin.nav_daily (users_id, nav_date, nav_value) values (%L, '2026-08-03', 'Infinity'::numeric) $$, :'ta'),
  '%nav_daily_value_finite%',
  '(f2) finiteness fence: nav_value = +Infinity is REJECTED by nav_daily_value_finite — PostgreSQL `numeric` admits ''Infinity'', so the explicit bar is load-bearing (the 053 N1 correction applied here)'
);
-- (f3) -Infinity rejected.
select throws_like(
  format($$ insert into pfin.nav_daily (users_id, nav_date, nav_value) values (%L, '2026-08-04', '-Infinity'::numeric) $$, :'ta'),
  '%nav_daily_value_finite%',
  '(f3) finiteness fence: nav_value = -Infinity is REJECTED by nav_daily_value_finite — the third numeric special value barred alongside NaN and +Infinity'
);
-- (f4) NOT over-broad: an ordinary finite value is ACCEPTED. (A negative NAV is legitimate — a
--      user can be underwater — so the control uses one, guarding a CHECK that over-reached to
--      `nav_value >= 0`.)
select set_config('app.nav_computed_for', :'tb', true);   -- f4 targets tenant B — rebind
select lives_ok(
  format($$ insert into pfin.nav_daily (users_id, nav_date, nav_value) values (%L, '2026-08-05', -1500.25) $$, :'tb'),
  '(f4) finiteness fence NOT over-broad: an ordinary finite (and NEGATIVE — an underwater net worth is legitimate) nav_value INSERTs successfully under service_role — proves the CHECK rejects ONLY NaN/±Infinity, not real checkpoints'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- LEG (g) SERVICE_ROLE WRITE PATH (positive) — without this, legs (b)/(c)/(d) would be
--   vacuously green against a table nobody can write at all.
-- =====================================================================
select set_config('role', 'service_role', true);
select set_config('app.nav_computed_for', :'ta', true);   -- the worker's own bind step, reproduced
-- RT-31 leg (h) — THIS LEG EXERCISES THE PRODUCTION STATEMENT SHAPE VERBATIM.
--   Sec's battery-wide rule: a privilege leg must run the REAL statement, not a simplified
--   equivalent, because statement shape is part of the contract under test. This leg previously
--   used a plain INSERT — which is exactly how the ON CONFLICT defect reached a green battery
--   through four reviewers: the plain form never needed the SELECT privilege the targeted form
--   requires, so it passed while the production statement failed 42501 on EVERY run.
--
--   ⚑ CROSS-ARTIFACT INVARIANT FENCED HERE (deliberate, not incidental — Backend's argument,
--     Sec-confirmed). The targeted form creates an invariant spanning TWO artifacts that must
--     move together: **the grant's column list must match the arbiter constraint.** Running the
--     production statement verbatim is what fences it. MEASURED both directions:
--       · arbiter changed without the grant  -> 42P10 'there is no unique or exclusion
--         constraint matching the ON CONFLICT specification' (verified live)
--       · grant narrowed/dropped             -> 42501 permission denied  (this is (w8))
--     So a PR that changes UNIQUE(users_id, nav_date) without updating the column grant fails
--     HERE, on that PR, rather than in production on the next cron run. If this leg were ever
--     "simplified" back to a plain INSERT, that fence silently disappears — which is the same
--     class of regression as the original defect.
--
--   NOT A SWEEP TARGET — (k1): its subject is the UNIQUE CONSTRAINT, not a privilege, and it
--   MUST keep a plain INSERT precisely because the production ON CONFLICT form would SWALLOW
--   the 23505 it exists to observe. A mechanical "make every insert match production" pass would
--   destroy it. Recording the distinction so that does not happen.
-- (g1) the W-1 cron append: service_role INSERTs a new (user, day) checkpoint -> ACCEPTED.
--      Same nav_date as the (f4) row but a DIFFERENT users_id — also proving the UNIQUE key is
--      (users_id, nav_date) and not nav_date alone (a per-day-global key would break multi-tenant).
select lives_ok(
  format($$ insert into pfin.nav_daily (users_id, nav_date, nav_value) values (%L, '2026-08-05', 102500.00)
              on conflict (users_id, nav_date) do nothing $$, :'ta'),
  '(g1) service_role writer, PRODUCTION STATEMENT VERBATIM: the targeted `insert … on conflict (users_id, nav_date) do nothing` — the exact statement nav_daily.py emits — SUCCEEDS for a NEW (users_id, nav_date). Proves the 054 INSERT grant AND the (users_id, nav_date) column grant are both LIVE, and fences the cross-artifact invariant that the grant''s column list must match the arbiter constraint (42P10 if the arbiter moves, 42501 if the grant does). The SAME nav_date already used by another tenant is accepted, proving the key is (users_id, nav_date), not nav_date alone'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- LEG (k) UNIQUE GRAIN — one checkpoint per user per day (the worker's ON CONFLICT key).
--   Run privileged (postgres); a unique constraint is role-agnostic. Targets a row that
--   definitely exists (A @ 2026-07-30, seeded). GUC bound to A so the BEFORE INSERT binding fence
--   passes and the UNIQUE index — matched SQLSTATE-precise on 23505, disjoint from P0001 — is
--   genuinely what rejects.
-- =====================================================================
select set_config('app.nav_computed_for', :'ta', true);
select throws_ok(
  format($$ insert into pfin.nav_daily (users_id, nav_date, nav_value) values (%L, '2026-07-30', 123.45) $$, :'ta'),
  '23505', null,
  '(k1) UNIQUE grain: a duplicate (users_id, nav_date) is REJECTED with unique_violation (23505) — the key the worker''s `ON CONFLICT (users_id, nav_date) DO NOTHING` idempotent re-run depends on; RED if the constraint were dropped and a re-run double-counted the day'
);

-- (k2) ONE-ARBITER FENCE — the invariant that makes the untargeted ON CONFLICT form SAFE.
--   `on conflict do nothing` WITHOUT a conflict target swallows a violation of ANY
--   conflict-arbitrable constraint. That is acceptable here for exactly one reason: there IS only
--   one. Current surface (MEASURED, and it matches the migration):
--       c  nav_daily_value_finite            CHECK        — not arbitrable (raises 23514)
--       f  nav_daily_users_id_fkey           FOREIGN KEY  — not arbitrable (raises 23503)
--       p  nav_daily_pkey                    PRIMARY KEY  — identity column, cannot collide
--       u  nav_daily_users_id_nav_date_key   UNIQUE       — THE SOLE ARBITER
--   So "do nothing" can only ever mean "this (users_id, nav_date) already exists" — precisely the
--   idempotent-re-run semantics the worker wants. Add a SECOND unique-or-exclusion constraint and
--   that stops being true: the untargeted form would begin silently swallowing a DIFFERENT class
--   of violation, and a genuinely bad row would vanish as a no-op with no error anywhere.
--   ⚠ DEMOTED TO DOCUMENTATION at the column-grant ruling. It was load-bearing under the
--   UNTARGETED form, where a second arbiter would have been silently swallowed. The ratified
--   statement is TARGETED, which fails LOUDLY (42P10) on any mismatching constraint change — so
--   the untargeted hazard no longer exists and this assertion is no longer the safety fence.
--   RETAINED anyway, because it is cheap and it documents the census a future reader would
--   otherwise have to re-derive before touching the ON CONFLICT shape. contype 'x' (EXCLUDE) is
--   included because exclusion constraints are arbitrable too.
select is(
  (select count(*) from pg_constraint
    where conrelid = 'pfin.nav_daily'::regclass and contype in ('u', 'x'))::int,
  1,
  '(k2) ONE-ARBITER FENCE: pfin.nav_daily carries EXACTLY ONE conflict-arbitrable constraint (contype u/x) — UNIQUE(users_id, nav_date). This is the precondition that makes the worker''s UNTARGETED `on conflict do nothing` safe: with one arbiter, "do nothing" can only mean "that (user, day) already exists". RED the moment a second unique/exclusion constraint is added, at which point the untargeted form would start silently swallowing a different violation class and the ON CONFLICT shape MUST be revisited'
);

-- =====================================================================
-- LEG (c) CROSS-TIER IMMUTABILITY — the load-bearing append-only fence.
--   In production posture service_role holds INSERT + a two-column SELECT and NO UPDATE/DELETE,
--   so an UPDATE/DELETE would be ACL-denied
--   and would prove NOTHING about the trigger. We hold the ACL OPEN with a TEST-ONLY grant (rolled
--   back with the txn; the 004 idiom) so the TRIGGER is the SOLE remaining gate. service_role also
--   BYPASSES RLS — so if the trigger were removed these writes would SUCCEED. That is exactly the
--   privileged-context gap RLS-default-deny cannot close.
--   (h6)/(h7) above already asserted the real production ACL, before this grant existed.
-- =====================================================================
grant select, update, delete on pfin.nav_daily to service_role;  -- TEST-ONLY (rolled back)

select set_config('role', 'service_role', true);
-- (c1) THE load-bearing assertion: a privileged, RLS-bypassing UPDATE of a checkpoint is stopped
--      by the trigger, not by RLS.
select throws_like(
  format($$ update pfin.nav_daily set nav_value = 999999.99 where nav_id = %s $$, :nav_a1),
  'pfin.nav_daily is immutable%UPDATE blocked%',
  '(c1) CROSS-TIER append-only: service_role UPDATE of nav_value blocked by the ROW-level immutability TRIGGER (RLS-bypass does NOT bypass a trigger) — RED if fn_nav_daily_block_mutation or its trigger were removed, which would let the privileged tier silently rewrite recorded net-worth history'
);
-- (c2) created_at is immutable post-INSERT — audit-class provenance (Lock 15 mod #1).
select throws_like(
  format($$ update pfin.nav_daily set created_at = now() where nav_id = %s $$, :nav_a1),
  'pfin.nav_daily is immutable%UPDATE blocked%',
  '(c2) CROSS-TIER append-only: service_role UPDATE of created_at blocked by the SAME row-level trigger — the audit-class provenance timestamp cannot be back-dated after the fact'
);
-- (c3) the DELETE half of the same fence, on a REAL seeded row owned by a DIFFERENT tenant
--      (proving the fence is table-wide, not accidentally scoped to one tenant's rows).
select throws_like(
  format($$ delete from pfin.nav_daily where nav_id = %s $$, :nav_b1),
  'pfin.nav_daily is immutable%DELETE blocked%',
  '(c3) CROSS-TIER append-only: service_role DELETE of a real seeded checkpoint blocked by the row-level immutability trigger (asserted on a DIFFERENT tenant''s row than (c1)/(c2), so the fence is proven table-wide) — RED if the DELETE half of the fence were removed'
);
select set_config('role', 'postgres', true);  -- restore before (d) + finish()

-- =====================================================================
-- LEG (o) OWNER TIER — a KNOWN-LIMIT RECORD, **not** the worker's path.
--   REFRAMED at the B1 ratification. An earlier revision of this file claimed `postgres` WAS the
--   worker identity (reasoning from a PLACEHOLDER in .env.example — see the B1 block in the
--   header). It is not: the worker logs in as `pfin_etl` (its own dedicated role, B8/055) and
--   writes AS `service_role`.
--   What this leg proves NOW:
--     (o2)-(o5) the immutability + append behaviour holds for an owner-class session — a human
--       psql session, a migration script, a manual "fix", or any future job that mistakenly
--       connects as the owner. Still true, still worth fencing, but no longer the worker's path.
--     (o6)-(o7) the POSITIVE COUNTERPART, and the reason B1 was ratified: the worker's actual
--       write role CANNOT reach the owner-only bypasses that would suppress every fence here.
--   The owner holds UPDATE/DELETE/TRUNCATE **by ownership** — no grant to revoke, RLS bypassed —
--   so NO setup and NO test-only grant is needed for (o2)-(o5): the TRIGGERS are the sole gate by
--   construction. Runs at role=postgres, already the ambient session role at this point.
--   nav_daily has NO inbound FK (no downstream migration depends on 054), so (o4) needs no CASCADE.
--   KNOWN LIMIT (measured, deliberately NOT asserted — see the header block): an OWNER that first
--   sets session_replication_role='replica' (or disables the trigger) DOES get through. That is
--   exactly what (o6)/(o7) show the ratified non-owner write role cannot do.
-- =====================================================================
-- (o1) IDENTITY ANCHOR — pin the tier. Without this, leg (o) could silently fence the wrong role.
select is(
  (select tableowner from pg_tables where schemaname = 'pfin' and tablename = 'nav_daily'),
  'postgres',
  '(o1) owner-tier identity anchor: pfin.nav_daily is owned by `postgres` — an identity DISTINCT from the worker''s under the ratified B1 model (the worker logs in as `pfin_etl`, NOINHERIT, and writes AS `service_role`). This leg fences owner-class sessions (human psql, migration scripts), not the cron. RED if ownership moved, at which point (o2)-(o5) would be fencing some other identity'
);

-- (o2) THE LOAD-BEARING ASSERTION OF THIS BATTERY: the real worker identity cannot rewrite history.
select throws_like(
  format($$ update pfin.nav_daily set nav_value = 999999.99 where nav_id = %s $$, :nav_a1),
  'pfin.nav_daily is immutable%UPDATE blocked%',
  '(o2) OWNER TIER append-only: an UPDATE by the TABLE OWNER `postgres` — the W-1 worker''s real login identity, which holds UPDATE by OWNERSHIP (no grant to revoke) and bypasses RLS — is blocked by the row-level immutability TRIGGER. The trigger is the ONLY control on this path; RED if fn_nav_daily_block_mutation or its binding were removed, and a mis-scoped cron UPDATE would then silently rewrite recorded net-worth history'
);

-- (o3) the erasure half, on a DIFFERENT tenant's real seeded row (fence proven table-wide).
select throws_like(
  format($$ delete from pfin.nav_daily where nav_id = %s $$, :nav_b1),
  'pfin.nav_daily is immutable%DELETE blocked%',
  '(o3) OWNER TIER append-only: a DELETE by the table owner `postgres` of a real seeded checkpoint is blocked by the row-level immutability trigger (asserted on a DIFFERENT tenant''s row than (o2), so the fence is proven table-wide) — the worker identity cannot erase a checkpoint'
);

-- (o4) the DISTINCT statement-level fence — the bulk history-wipe path, at the only tier that
--      actually holds TRUNCATE. Row-level triggers do NOT fire on TRUNCATE, so (o2)/(o3) passing
--      does NOT imply this.
select throws_like(
  $$ truncate pfin.nav_daily $$,
  'pfin.nav_daily is immutable%TRUNCATE blocked%',
  '(o4) OWNER TIER TRUNCATE fence: a TRUNCATE by the table owner `postgres` — the only identity that actually HOLDS TRUNCATE — is blocked by the STATEMENT-level trigger fn_nav_daily_block_truncate, with a message DISTINCT from the row-level fence (so one trigger can never pass for the other). RED if the statement-level trigger were removed, since row-level triggers do NOT fire on TRUNCATE and the entire trend history would go in one statement'
);

-- (o5) THE APPEND PATH MUST STAY OPEN at the owner tier. Guards an over-broad immutability fence
--      (e.g. a future migration widening BEFORE UPDATE OR DELETE to include INSERT). GUC bound —
--      the B7 fence is role-agnostic and applies to the owner exactly as it does to the worker.
select set_config('app.nav_computed_for', :'ta', true);
select lives_ok(
  format($$ insert into pfin.nav_daily (users_id, nav_date, nav_value) values (%L, '2026-08-06', 103750.00) $$, :'ta'),
  '(o5) OWNER TIER append allowed: an INSERT by the table owner `postgres` SUCCEEDS — the W-1 cron''s actual write path stays open. Together with (o2)-(o4) this is the full "append allowed, mutate blocked" property for the REAL worker identity; RED if the immutability fence were over-broad (which would be a silent cron outage, not a control)'
);

-- ---------------------------------------------------------------------
-- (o6)/(o7) THE POSITIVE COUNTERPART TO THE KNOWN LIMIT — and the tested justification for B1.
--   The owner can suppress these triggers (session_replication_role / DISABLE TRIGGER). The
--   ratified write role cannot. These two assertions are what turn that from a caveat in a
--   comment into a property with a test behind it: if `service_role` ever gained either
--   capability, it could switch off every fence in this file and moving the worker off the
--   owner identity would have bought nothing.
-- ---------------------------------------------------------------------
select set_config('role', 'service_role', true);
-- (o6) the write role cannot disable triggers wholesale via the replication switch.
select throws_like(
  $$ set session_replication_role = 'replica' $$,
  '%permission denied to set parameter%session_replication_role%',
  '(o6) B1 non-owner write role: `service_role` CANNOT set session_replication_role (permission denied) — the owner-only bypass that suppresses ALL row-level triggers is out of reach of the worker''s write role. This is the tested justification for moving the worker off the owner identity; RED if the write role were ever granted that parameter'
);
-- (o7) the write role cannot disable an individual trigger either (requires ownership).
select throws_like(
  $$ alter table pfin.nav_daily disable trigger nav_daily_block_mutation $$,
  'must be owner of table nav_daily',
  '(o7) B1 non-owner write role: `service_role` CANNOT ALTER TABLE … DISABLE TRIGGER (must be owner of table nav_daily) — the second owner-only bypass is also out of reach. Together with (o6) this proves the worker''s write role cannot switch off the immutability or binding fences that constrain it'
);
select set_config('role', 'postgres', true);

-- =====================================================================
-- LEG (i) BYPASS-CAPABLE ROLE-SET FENCE — the standing regression detector for the SD-24
--   TIER BOUNDARY. Authored 2026-08-09 (QA). Sec specified the catch criterion and the
--   mandatory query shape at PR #341; this leg is the NEW obligation carried from SELF-219.
--
--   WHAT IT GUARDS. SD-24's "never cross-tenant" claim is scoped to the APPLICATION tier.
--   The DB-admin tier reads across tenants and that is a documented, non-remediable residual —
--   RLS is not a control against it. What IS ours, and what this leg is, is the assertion that
--   the bypass-capable set HAS NOT GROWN: five platform roles hold it today, and a sixth
--   arriving is a change nobody would otherwise notice.
--
--   ⚠ SET-COMPLEMENT SHAPE, NON-NEGOTIABLE (Sec). `is_empty()` over a query that RETURNS the
--   offending rows — never a per-role deny-list. A deny-list cannot return the role nobody
--   thought of, and its silence reads as a clean bill of health. This is the direct remediation
--   of the failure recorded at DESIGN.md: "I asked a question that could not return the roles I
--   hadn't thought of, and read its silence as absence" — a probe over a hand-chosen role list
--   missed that five roles carry rolbypassrls.
--
--   ONE DEFINITION, THREE CALL SITES — and why the query is in a function rather than written
--   out three times. (i1) asserts the fence is green; (i2)/(i3) exist to prove that green MEANS
--   something. If those were three literal copies, an edit to one would leave the probes
--   validating a query the fence no longer runs — the probes would still pass, and they would be
--   proving a fence that is no longer deployed. That is exactly the defect #330 found in the TZ
--   sweep, where two copies each claimed to be kept identical to the other and the claim was
--   already false when it was written. qa_rt31_offenders() IS the mandated shape, verbatim and
--   once; read the function body as the fence. Defined here rather than with the other pg_temp
--   helpers at the top deliberately — a reviewer verifying non-vacuity must read the fence and
--   the probes together, and 800 lines of separation is how that check gets skipped.
--
--   NON-VACUITY IS RE-PROVEN ON EVERY RUN, not argued in a comment. (i2)/(i3) each create a
--   probe role of ONE violation shape and assert the fence names it. The two shapes are
--   independent — a BYPASSRLS-only role holds no pg_read_all_data, and a pg_read_all_data-only
--   role is not BYPASSRLS — so neither leg subsumes the other and deleting either reopens one
--   half. Sec demonstrated this once in a rolled-back transaction on 2026-08-08; QA reproduced
--   it while authoring rather than porting the green result, and then wired it in so it repeats.
--   A fence that has never been made to fail is an assumption.
--
--   THE PROBE ROLE CANNOT LEAK, under any path. qa_rt31_probe() creates the role inside a
--   plpgsql BEGIN…EXCEPTION block — an implicit subtransaction — and leaves that block by
--   RAISING, so the CREATE ROLE is unwound whether the fence caught the probe or not. The
--   fence's output rides out in the exception message. Any OTHER error returns NULL, which
--   makes the assertion RED rather than aborting the file: the (h11)/qa_rc hard-abort lesson,
--   where a raise inside an assertion's argument list killed a run with ZERO reported failures.
--   (i4) asserts the absence directly rather than trusting the mechanism.
--
--   SCOPE DISCIPLINE (team-lead ruling, DESIGN.md — "a wrongly-scoped fence is negative value,
--   not neutral"). This leg does NOT extend the (A5) EXECUTE fence to the other four bypassrls
--   roles. For postgres/supabase_admin that negative is unassertable; for supabase_etl_admin/
--   supabase_read_only_user it is a door beside an open wall, since pg_read_all_data already
--   reaches nav_value directly. A fence that CANNOT fail shows up in a coverage review as
--   GREEN — the same defect as a vacuous one, arriving from the opposite direction.
-- =====================================================================
create function pg_temp.qa_rt31_offenders() returns table (rolname text)
language sql volatile as $qa$
  -- THE FENCE. Sec-mandated set-complement shape, verbatim (PR #341 / RT-31 leg (i)).
  -- The allowlist is the platform set MEASURED on 2026-08-08 and re-measured 2026-08-09.
  -- Adding a role here is how this fence gets silently defeated — (i7)-(i9) exist because
  -- of that, and any addition is Sec joint-review-mandatory.
  select a.rolname::text
  from pg_authid a
  where (a.rolbypassrls or pg_has_role(a.rolname,'pg_read_all_data','USAGE'))
    and a.rolname not like 'pg\_%'
    and a.rolname not in ('postgres','supabase_admin','supabase_etl_admin',
                          'supabase_read_only_user','service_role')
$qa$;

create function pg_temp.qa_rt31_probe(p_shape text) returns text
language plpgsql as $qa$
declare result text;
begin
  begin
    if p_shape = 'bypassrls' then
      execute 'create role qa_rt31_probe_bypassrls bypassrls';
    elsif p_shape = 'read_all_data' then
      execute 'create role qa_rt31_probe_readall';
      execute 'grant pg_read_all_data to qa_rt31_probe_readall';
    else
      return null;                                   -- unknown shape => RED, never a silent pass
    end if;
    select coalesce(string_agg(o.rolname, ', ' order by o.rolname), '<fence returned nothing>')
      into result from pg_temp.qa_rt31_offenders() o;
    raise exception using errcode = 'QA031', message = result;   -- unwinds the CREATE ROLE
  exception
    when sqlstate 'QA031' then return sqlerrm;       -- probe rolled back; fence output carried out
    when others then return null;                    -- NULL => pgTAP FAILS. Never a hard abort.
  end;
end $qa$;

create function pg_temp.qa_rt31_can_probe() returns boolean
language plpgsql as $qa$
begin
  return (select a.rolcreaterole and a.rolbypassrls from pg_authid a where a.rolname = current_user)
     and not exists (select 1 from pg_authid where rolname like 'qa\_rt31\_probe%');
exception when insufficient_privilege then
  return null;   -- NULL => pgTAP FAILS the assertion. Never a silent skip.
end $qa$;

-- (i0) DEPENDENCY GUARD — must come first and must be LEGIBLE. (i2)/(i3) create roles, which no
--      other battery in this suite does; if the running identity cannot, they would abort the
--      FILE rather than fail an assertion. This turns that into one readable RED. It does not
--      cover admin-on-pg_read_all_data (not cheaply checkable) — that shows up as (i3) NULL.
select is(
  pg_temp.qa_rt31_can_probe(),
  true,
  '(i0) leg (i) dependency guard: the running identity can read pg_authid, holds CREATEROLE + BYPASSRLS (both required to mint the (i2)/(i3) probes), and neither probe name is already taken. RED here means (i1)-(i4) below cannot be trusted — read this before reading them'
);

-- (i1) THE FENCE ITSELF. Green today; (i2)/(i3) are what make that green mean something.
select is_empty(
  $$ select * from pg_temp.qa_rt31_offenders() $$,
  '(i1) RT-31 leg (i) BYPASS-CAPABLE ROLE-SET FENCE: no role outside the known platform set holds rolbypassrls or pg_read_all_data. Measured 0 rows on 2026-08-08 (Sec) and 2026-08-09 (QA), against 32 roles of which exactly five carry the capability. RED means the bypass-capable set has GROWN — a new role can read every tenant''s nav_value irrespective of the GRANTs this project writes, which is the SD-24 disclosure event with no application-tier symptom at all'
);

-- (i2) NON-VACUITY, SHAPE 1 of 2 — a BYPASSRLS-only role (holds NO pg_read_all_data).
select is(
  pg_temp.qa_rt31_probe('bypassrls'),
  'qa_rt31_probe_bypassrls',
  '(i2) leg (i) NON-VACUITY, BYPASSRLS shape: with a probe role holding BYPASSRLS and nothing else, the fence returns EXACTLY that role — proving (i1)''s green is a measurement and not a query that cannot return anything. Reproduced by QA at authoring, not ported from Sec''s 2026-08-08 run. RED means the fence has stopped observing the rolbypassrls disjunct, at which point (i1) is decorative'
);

-- (i3) NON-VACUITY, SHAPE 2 of 2 — a pg_read_all_data member that is NOT bypassrls. NOT redundant
--      with (i2): these are independent grants and the fence catches them through different
--      disjuncts. Deleting either leg silently reopens one half of the property.
select is(
  pg_temp.qa_rt31_probe('read_all_data'),
  'qa_rt31_probe_readall',
  '(i3) leg (i) NON-VACUITY, pg_read_all_data shape: with a probe role holding pg_read_all_data membership and NOT bypassrls, the fence returns EXACTLY that role. This is the mechanism SD-24 measured as the actual reach — a PostgreSQL predefined role granting SELECT on every table irrespective of our GRANTs — and it is caught through a DIFFERENT disjunct than (i2). RED means the fence sees only bypassrls, which would miss the two platform roles that reach nav_value that way'
);

-- (i4) THE PROBES LEFT NOTHING BEHIND. Asserted, not trusted: a leaked BYPASSRLS role would
--      sit in this transaction as a live cross-tenant reader for every assertion after it.
select is(
  (select count(*) from pg_authid where rolname like 'qa\_rt31\_probe%'),
  0::bigint,
  '(i4) leg (i) probe hygiene: neither (i2) nor (i3) leaked its probe role — the plpgsql subtransaction unwound both CREATE ROLEs. RED means a test-only BYPASSRLS role is live in this session, which would both contaminate every later assertion and, if the unwind ever failed outside a rolled-back battery, mint exactly the capability this leg exists to detect'
);

-- (i5) THE EXCLUSION IS SAFE — measured, not assumed. The fence excludes `pg_%` because those are
--      PostgreSQL's predefined roles. That is only sound if the prefix is RESERVED; if a role
--      could be named `pg_anything`, the exclusion would be a hiding place rather than a filter.
select throws_ok(
  $$ create role pg_qa_rt31_reserved_probe $$,
  '42939',
  null,
  '(i5) leg (i) exclusion soundness: PostgreSQL REFUSES a role name starting with `pg_` (SQLSTATE 42939, reserved_name) — measured on PG 17, not assumed. This is what makes the fence''s `rolname not like ''pg\_%''` clause a filter over predefined roles rather than an attacker- or mistake-usable hiding place. RED means the prefix stopped being reserved and the exclusion must be narrowed to the actual predefined set'
);

-- (i6) DO NOT "SIMPLIFY" pg_has_role() INTO A MEMBERSHIP LOOKUP. This assertion exists to stop
--      one specific, plausible edit. pg_read_all_data has exactly THREE real members here
--      (postgres, supabase_etl_admin, supabase_read_only_user) while pg_has_role() returns true
--      for FOUR roles; a reader who notices that gap may conclude the function is doing something
--      loose and swap in a pg_auth_members join. It is not loose — the fourth is a SUPERUSER, and
--      pg_has_role reports a superuser as holding every role.
--
--      ⚠ WHAT THIS ASSERTION MEASURES, AND WHAT IT DOES NOT. In-battery it measures only the
--      premise: supabase_admin is a superuser, is NOT a member, and pg_has_role says true anyway.
--      It does NOT measure the consequence, because the consequence needs a role this battery
--      cannot create — `postgres` is NOT a superuser on this stack (rolsuper = f), and only a
--      superuser may create one. An earlier draft of this message asserted the consequence as
--      though this assertion covered it; it does not, and the first differential run "confirming"
--      it was worthless because it used supabase_admin as the witness — a role that ALSO carries
--      rolbypassrls, so the FIRST disjunct caught it and pg_has_role was never load-bearing.
--
--      THE CONSEQUENCE IS MEASURED, out of band, on 2026-08-09, with the correct witness — a BARE
--      superuser (rolsuper = t, rolbypassrls = f). Re-runnable; this is the method, not a summary:
--        docker exec -i supabase_db_<project> psql -U supabase_admin -d postgres <<'EOF'
--        begin; create role qa_bare_super superuser;
--        -- mandated shape (pg_has_role)      -> returns qa_bare_super   [CAUGHT]
--        -- membership-join "simplification"  -> returns nothing          [BLIND]
--        -- has_column_privilege(...,'nav_value','SELECT') -> t           [hazard is real]
--        rollback; EOF
--      So the simplification would leave the fence blind to every superuser.
--
--      ⚠ AND THIS COMMENT IS THE ONLY CONTROL ON THAT EDIT — measured 2026-08-09 on Sec's flag
--      (PR #343): applying the swap passes THE ENTIRE BATTERY, all 74 assertions green, **(i6)
--      included**. Two independent reasons, and both have to be understood before anyone trusts
--      this leg to police the change: (i6) reads `pg_authid` directly and never calls
--      qa_rt31_offenders(), so no edit to the fence can red it; and (i3)'s probe IS a real
--      member of pg_read_all_data, so the membership join catches it too. Only a NON-MEMBER
--      superuser separates the two variants, and this battery cannot mint one.
--
--      An earlier draft of this line read "...which is precisely why this pin is an assertion
--      and not a comment." That was FALSE, and it is left recorded rather than quietly replaced
--      because it is the SECOND over-claim of the same shape at this one assertion — the first
--      was in the message, credited to coverage it did not have. What (i6) buys is that the
--      premise is re-measured on every run AT THE SITE where the edit would be made. That is
--      worth having. It is not a fence, and must not be read as one.
select is(
  (select array[ a.rolsuper,
                 exists (select 1 from pg_auth_members m join pg_roles g on g.oid = m.roleid
                          where m.member = a.oid and g.rolname = 'pg_read_all_data'),
                 pg_has_role(a.rolname,'pg_read_all_data','USAGE') ]
     from pg_authid a where a.rolname = 'supabase_admin'),
  array[true, false, true],
  '(i6) leg (i) mechanism pin — `supabase_admin` is a SUPERUSER, is NOT a member of pg_read_all_data, and pg_has_role() reports it as holding pg_read_all_data anyway. This assertion measures that PREMISE only. The consequence it protects — that swapping pg_has_role for a membership join blinds the fence to a bare SUPERUSER (rolbypassrls = f) — was measured out of band with a bare-superuser witness on 2026-08-09 and cannot be asserted here, because `postgres` is not a superuser on this stack and so cannot mint one. RED means the premise moved, and the fence''s superuser coverage must be re-measured by the method in the comment above before this leg is trusted'
);

-- (i7)-(i9) THE POSITIVE NEGATIVES. The complement query alone stays GREEN if one of OUR OWN
--   roles is quietly added to its allowlist by a future edit — the fence would then be excluding
--   the very thing it exists to catch, and reporting clean. These three assert the property
--   directly for every identity this project provisions, so an allowlist edit cannot hide here.
--   Each asserts the full triple [bypassrls, pg_read_all_data, nav_value SELECT]; the array form
--   is deliberate — a failure names WHICH of the three moved rather than just "false <> true".
select is(
  (select array[ a.rolbypassrls,
                 pg_has_role(a.rolname,'pg_read_all_data','USAGE'),
                 has_column_privilege(a.rolname,'pfin.nav_daily','nav_value','SELECT') ]
     from pg_authid a where a.rolname = 'pfin_etl'),
  array[false, false, false],
  '(i7) leg (i) positive negative — `pfin_etl`, the ETL''s dedicated login role (055): NOT bypassrls, NOT pg_read_all_data, and NO SELECT on nav_value. This is the identity the W-1 cron authenticates as, so it is the one an operator is most likely to "just give read access" to. RED means the worker''s own login can read every tenant''s frozen net worth, independent of anything RLS does'
);

select is(
  (select array[ a.rolbypassrls,
                 pg_has_role(a.rolname,'pg_read_all_data','USAGE'),
                 has_column_privilege(a.rolname,'pfin.nav_daily','nav_value','SELECT') ]
     from pg_authid a where a.rolname = 'authenticator'),
  array[false, false, false],
  '(i8) leg (i) positive negative — `authenticator`, the LOGIN role PostgREST connects as for EVERY web request: NOT bypassrls, NOT pg_read_all_data, NO SELECT on nav_value. The highest-consequence row of the three — this role is reached by every unauthenticated HTTP request that arrives, and #324 already measured a role-level GUC being silently attached to exactly this identity'
);

select is(
  (select array[ a.rolbypassrls,
                 pg_has_role(a.rolname,'pg_read_all_data','USAGE'),
                 has_column_privilege(a.rolname,'pfin.nav_daily','nav_value','SELECT') ]
     from pg_authid a where a.rolname = 'anon'),
  array[false, false, false],
  '(i9) leg (i) positive negative — `anon`, the pre-authentication identity: NOT bypassrls, NOT pg_read_all_data, NO SELECT on nav_value. Overlaps (h9)''s zero-grant assertion on the GRANT axis and is deliberately kept: (h9) proves no grant exists, this proves no BYPASS route exists, and a role can acquire the second without ever touching the first'
);

-- (i10) NON-VACUITY CONTROL for (i7)-(i9). Without it, three `false` triples cannot be told
--       apart from a column NO role can read — if the `authenticated` grant were ever dropped,
--       all three would stay green while measuring nothing about those three roles.
--       ⚠ The example this comment originally gave — "a renamed column" — was IMPOSSIBLE, and
--       the correction is worth more than the assertion it justifies: has_column_privilege()
--       on a column that does not exist RAISES 42703 (measured 2026-08-09 on Sec's flag,
--       PR #343); it does not return false. Against a rename, (i7)-(i9) would ERROR, not pass
--       vacuously. A rationale invented rather than measured, inside a battery whose subject is
--       that rationale must be measured — which is why it is corrected in place, not deleted.
select is(
  has_column_privilege('authenticated','pfin.nav_daily','nav_value','SELECT'),
  true,
  '(i10) leg (i) non-vacuity control: `authenticated` DOES hold SELECT on nav_value (RLS-filtered to the owner — intended, and the (a)/(e) legs are what fence it). This is what proves (i7)-(i9)''s three false triples are a measurement of those roles rather than an artifact of has_column_privilege returning false for everything on this column'
);

select * from finish();
rollback;
