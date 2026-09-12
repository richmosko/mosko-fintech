-- ============================================================================
-- Migration: migrator — the bounded DDL-apply login role for the ADR-072
--   Option-E `migrator` service. This is the identity that runs UNSUPERVISED
--   `supabase db push` in the resident migrator container, once the deploy
--   mechanism is built. **CREATED HERE AS `NOLOGIN`, `NOINHERIT`, `CREATEROLE`,
--   WITH NO PASSWORD** — the role ships inert and is switched on by the
--   supervised operator handoff; see the DEPLOY-TIME CREDENTIAL HANDOFF block.
--   Migration-time `rolcanlogin` is FALSE.
--   ADR-072 (Option E) Decision 4 + Amendment 1. Option-E build, chunk 1.
--   SELF-398 (Sec joint-review of the chunk-1 build). apply-migration procedure
--   applied.
--   JOINT-REVIEW-MANDATORY (Sec veto surface): a cluster-level identity holding a
--   standing DDL-capable credential (CREATEROLE + app-database ownership).
--
-- ----------------------------------------------------------------------------
-- Numbering: 118 follows 117 (pfin_etl comment-only re-attribution). Depends on
--   NOTHING in pfin — this migration creates no object in the pfin schema and
--   touches no table, no function and no policy. It depends only on the cluster
--   existing and on being FIRST-APPLIED by a superuser (`postgres`) at bootstrap,
--   which is the ADR-072 first-bootstrap model. No downstream migration depends on
--   118; it is order-independent and is numbered 118 only because it was authored
--   after 117. (Verified against the tree: 117 is the highest existing number.)
--
-- WHY A SEPARATE MIGRATION: this is a CLUSTER-LEVEL IDENTITY concern with its own
--   lifecycle and blast radius — the SAME reasoning that gave 055 (`pfin_etl`) and
--   116 (`pfin_provider_sync`) their own migrations. It is deliberately NOT folded
--   into any pfin-schema migration and it does NOT converge with 055/116: `migrator`
--   is a THIRD, distinct cluster role with a different purpose (DDL apply, not
--   worker data access) and a different privilege shape (CREATEROLE + DB-owner, no
--   app-role membership — the inverse of the worker roles, which hold app-role
--   membership and no CREATEROLE).
--
-- ----------------------------------------------------------------------------
-- WHY THIS ROLE EXISTS, AND WHY IT IS THE SMALLEST STANDING CREDENTIAL.
--   ADR-072 Option E makes the DDL credential STANDING — it is held at rest by a
--   resident service that a Coolify Scheduled Task can trigger. E's worst-case cost
--   is therefore a permanent, triggerable DDL credential, so the ratified answer
--   (Decision 4) is the SMALLEST credential that can apply the current migration
--   set without superuser:
--     · `CREATEROLE`     — the set's only role-creation driver is 055/116's
--                          `CREATE ROLE`. (Verified in-tree at ADR-072 Decision 4:
--                          `CREATE EXTENSION` is NOT a driver — extensions are
--                          provisioned by the infra db-init scripts as superuser at
--                          first-boot, never by `supabase/migrations/`.)
--     · OWNER of the app database — the set's `ALTER DATABASE … SET` driver (`061`)
--                          requires database ownership. ⚠ This is established at the
--                          OPERATOR HANDOFF, not here — see the ALTER DATABASE OWNER
--                          block below; a migration cannot and must not flip it.
--     · NON-superuser, and holding NO app-role membership and NO direct pfin grant.
--   The rejected simpler alternative is the `postgres` superuser (`POSTGRES_PASSWORD`,
--   already `production_only`): maximal blast radius for a standing, triggerable
--   service. A future migration that genuinely needs superuser (a new extension,
--   `ALTER SYSTEM`) FAILS against this bounded role — a deliberate Decision-4
--   TRIPWIRE, not a regression; it forces a supervised, superuser-run apply and a
--   Sec conversation rather than silently widening the standing credential.
--
-- ----------------------------------------------------------------------------
-- POSTURE RATIONALE — NO FUNCTION IS AUTHORED HERE, so the SECURITY DEFINER
--   allowlist (ADR-011 Decision 9 / Lock 11) is not engaged in either direction:
--   this migration authors neither a SECURITY INVOKER nor a SECURITY DEFINER
--   function. There is no `search_path` to pin and no function comment to write.
--   The posture question this migration answers is a role-privilege one, and the
--   answer is CREATEROLE + DB-owner, non-superuser, NOINHERIT, ZERO app-role
--   membership, ZERO direct object privilege.
--
-- WHY NOINHERIT (defense-in-depth, not load-bearing today). `migrator` holds NO
--   role memberships, so INHERIT-vs-NOINHERIT decides nothing about its CURRENT
--   reach — it acts under its OWN attributes (CREATEROLE, DB-owner), never by
--   `SET ROLE`. NOINHERIT is chosen anyway so that IF a membership were ever
--   erroneously granted, it would confer no privilege without an explicit SET ROLE
--   — the same fail-closed default 055/116 rely on. The C8 assertion below is the
--   real guarantee that the membership set stays empty; NOINHERIT is the backstop.
--
-- ----------------------------------------------------------------------------
-- ⚠ C8 CONSTRAINTS — SATISFIED **AND VERIFIABLE** (Sec requires real DDL
--   verification, not design-intent comments). The role is created with exactly
--   these attributes, and an apply-time structural assertion block below HARD-FAILS
--   if any is violated — on every apply, in both the bootstrap and post-handoff
--   states (cf. the migration-111 apply-time-assertion precedent). The invariants
--   asserted hold in ALL states, so a legitimately-provisioned (LOGIN, credentialed)
--   role still passes; only a tampered or mis-authored role fails.
--     (a) `rolcreaterole = true`  — the CREATEROLE driver. ASSERTED.
--     (b) `rolsuper = false`      — non-superuser. ASSERTED.
--     (c) `rolbypassrls = false`  — never bypasses RLS. ASSERTED (stronger than, and
--                                   in the spirit of, "non-superuser").
--     (d) `rolcreatedb = false`   — NOT CREATEDB. ASSERTED. This is also what makes
--                                   the ALTER DATABASE OWNER flip a superuser-only /
--                                   `postgres`-only step (see below): migrator itself
--                                   cannot run it.
--     (e) NOT a member of `service_role` / `authenticated` / `anon` (the app roles).
--                                   ASSERTED via pg_has_role(...,'MEMBER') = false for
--                                   each.
--   NOT apply-time-verifiable here, and the migration says so rather than pretending
--   otherwise:
--     · OWNER of the app database — at migration time (bootstrap) the DB is owned by
--       `postgres`, NOT migrator; ownership is flipped at the operator handoff, and
--       is verified THERE (runbook §6.3 verify block), not in this file.
--     · DISTINCT from `postgres` / `authenticator` / `pfin_etl` / `pfin_provider_sync`
--       — distinctness is guaranteed BY NAME (a role named `migrator` is not any of
--       those); the security-relevant half is non-membership, covered by (e). No
--       assertion can add to name-distinctness.
--     · NO direct pfin table/schema/function/sequence grant — this migration issues
--       no GRANT of any kind, so absence is BY CONSTRUCTION, exactly as for 055/116.
--
-- ----------------------------------------------------------------------------
-- ALTER DATABASE … OWNER TO migrator — PLACEMENT RESOLVED: OPERATOR HANDOFF, NOT
--   THIS MIGRATION. (The chunk-1 ruling left this ambiguous — it said the flip both
--   "rides this migration" and lives "in the handoff." This is the resolution.)
--   The decisive reason is a privilege fact, not a preference:
--     `ALTER DATABASE <db> OWNER TO <role>` requires the EXECUTOR to be a superuser,
--     or to hold CREATEDB **and** membership in the new owning role. `migrator` is
--     deliberately NEITHER superuser NOR CREATEDB (C8 (b)/(d) above). So migrator
--     can NEVER run this statement — not even to set the owner to itself.
--   Consequence if it rode the migration: at bootstrap `postgres` could run it, but
--   EVERY UNSUPERVISED RE-APPLY is run BY migrator, and migrator would fail the
--   statement (no CREATEDB) — turning the role's own migration into one it cannot
--   replay. A guard skipping the already-correct case would only paper over that the
--   statement does not belong in migrator's lane. The statement requires `postgres`;
--   the only `postgres`-run apply is the supervised bootstrap/handoff; therefore the
--   flip belongs in the handoff. This is exactly symmetric with the LOGIN/password
--   flip, which 055/116 also keep OUT of the migration for the same class of reason
--   (box-provisioning state, run supervised as an operator, not schema DDL).
--   Two further reasons reinforce it: (i) database ownership is box-level provisioning
--   state, not a pfin-schema fact; (ii) a migration cannot name the app database
--   without dynamic SQL over `current_database()`, and flipping ownership of the whole
--   database is not a schema migration's job.
--   ⚠ TIMING IS STILL SATISFIED: migrator must own the DB before its FIRST unsupervised
--   apply (so `061`'s `ALTER DATABASE … SET` succeeds under migrator). The handoff runs
--   at bootstrap, before any unsupervised apply, so placing the flip there meets the
--   requirement without placing it here.
--
-- ----------------------------------------------------------------------------
-- ⚠ THE BY-DESIGN DECISION-4 TRIPWIRE — DOCUMENTED, NOT A DEFECT. Because `postgres`
--   (not migrator) creates 055/116/117's roles at bootstrap, migrator holds NO ADMIN
--   OPTION on `pfin_etl` / `pfin_provider_sync` (nor on `postgres` / `authenticator`),
--   and it is not superuser. Therefore migrator CANNOT later `ALTER ROLE` or
--   `COMMENT ON ROLE` those roles: a future migration that tries to, applied
--   unsupervised as migrator, TRIPS (permission denied). That is the intended
--   Decision-4 behaviour — a role-graph change to the platform roles must be a
--   supervised, superuser-run act, not something a standing service performs.
--   ⚠ The same limit reaches migrator's OWN `comment on role` in this file: on a
--   full-chain replay run as migrator (a scratch rebuild, not a steady-state path —
--   Supabase migration tracking applies 118 exactly once, at bootstrap, under
--   `postgres`), the COMMENT would trip for lack of ADMIN-on-self. The migration is
--   re-runnable BY POSTGRES; that is the applier at every point where 118 actually
--   runs.
--
-- ----------------------------------------------------------------------------
-- *** DEPLOY-TIME CREDENTIAL HANDOFF — DO NOT MISS THIS ***
--   THIS MIGRATION DELIBERATELY CREATES `migrator` **NOLOGIN, WITH NO PASSWORD**. A
--   credential in the repository is a hard no (root CLAUDE.md: "Secrets never go in
--   the repo"), and a migration file is committed, diffed and mirrored to GitHub. The
--   role ships INERT and is switched on at deploy, in the SUPERVISED first bootstrap.
--
--   REQUIRED at deploy time, run ONCE by an operator against the target database as a
--   SUPERUSER (`postgres`) — the role governs only FUTURE unsupervised applies, never
--   its own switch-on. THREE statements; the `\password`→`LOGIN` PAIR is order-
--   load-bearing exactly as in 055/116, and the OWNER flip is independent of it:
--
--       ALTER DATABASE <app_db> OWNER TO migrator;  -- run as postgres; migrator is not
--                                                    -- CREATEDB so it cannot run this
--                                                    -- itself. Grants the DB ownership
--                                                    -- that `061`'s ALTER DATABASE … SET
--                                                    -- needs on future migrator applies.
--       \password migrator                          -- psql meta-command. Prompts;
--                                                    -- computes the SCRAM verifier
--                                                    -- CLIENT-SIDE; role still NOLOGIN
--                                                    -- here -> inert.
--       ALTER ROLE migrator LOGIN;                  -- carries NO secret.
--
--   Then set the migrator service's env: MIGRATOR_DB_USER=migrator (non-secret
--   username) and MIGRATOR_DB_PASSWORD = this role's secret (minted on-box by
--   `provision-supabase-stack.sh`'s MINT_SECRETS per ADR-072 Amendment 1 — the migrator
--   is a sibling service in the Supabase-stack compose, so its credential is NOT pushed
--   by `push-production-secrets.sh`).
--
--   *** THE SECRET MUST BE HIGH-ENTROPY AND MACHINE-GENERATED, NOT HUMAN-CHOSEN ***
--   (`openssl rand -hex 32`). This is what makes the logged SCRAM verifier's residual
--   offline attack economically irrelevant.
--
--   THE SINGLE-STATEMENT FORM `ALTER ROLE migrator WITH LOGIN PASSWORD '<plaintext>'`
--   IS PROHIBITED (Sec ruling B10, adopted for every role of this shape). Postgres does
--   not redact passwords from `log_statement`, so that form writes the credential to the
--   server log in cleartext; typing it also lands it in psql's plaintext ~/.psql_history.
--   The prohibition is MEASUREMENT-INDEPENDENT — do not measure a target, find statement
--   logging off, and conclude it lapses.
--
--   BE PRECISE ABOUT WHAT `\password` BUYS — do NOT write "the secret isn't logged". It
--   still sends `ALTER USER … PASSWORD 'SCRAM-SHA-256$4096:…'`, which is DDL and IS
--   logged. What changes is WHAT is logged: plaintext never leaves the client, and the
--   logged verifier is not a usable credential (it holds StoredKey + ServerKey; a client
--   proof needs ClientKey, and StoredKey = H(ClientKey) does not invert). The residual is
--   an offline attack bounded by secret entropy and the iteration count.
--
--   ORDERING: running `ALTER ROLE migrator LOGIN` without `\password` first leaves
--   LOGIN-with-no-password — reachable with no credential under any pg_hba `trust` line —
--   the exact state this shape exists to prevent, and what the re-apply WARNING branch
--   below detects. Splitting the statement does NOT reopen that window, because the
--   credential lands while the role is still NOLOGIN and LOGIN then flips onto an
--   already-credentialed role.
--
--   WHY NOLOGIN RATHER THAN LOGIN-WITHOUT-A-PASSWORD: `rolcanlogin` is checked from the
--   role attribute itself, BEFORE any pg_hba authentication method, so a passwordless
--   LOGIN role is reachable with NO credential under a `trust` line. NOLOGIN is
--   fail-closed BY CONSTRUCTION and does not outsource that property to a config file
--   outside this repo.
--
--   ⚠ SCRIPTED (NON-INTERACTIVE) BIND DEPENDS ON SELF-395. `\password` is interactive,
--   so the first bootstrap is SUPERVISED. SELF-395 (client-side SCRAM scripting,
--   SECURITY-GATED, not yet built) is what will let the bind be scripted for a fully
--   hands-off bootstrap; until then E cannot own the handoff (ADR-072 Decision 5 / §6).
--
-- ----------------------------------------------------------------------------
-- WHAT DEVOPS AND THE RUNBOOK OWE (routed, NOT edited here — Architect does not edit
--   secrets-manifest.yml, .env.example files, or Coolify/compose config):
--     · docs/deployment-runbook.md — a §6.1/§6.2-style supervised handoff section for
--       this role (§6.3). Authored in THIS PR (the paired runbook edit), because a
--       NOLOGIN role with no switch-on path is a half-artifact.
--     · secrets-manifest.yml — a new `production_only` name (MIGRATOR_DB_PASSWORD,
--       distinct from POSTGRES_PASSWORD and PFIN_DB_PASSWORD); a MINT_SECRETS entry;
--       MIGRATOR_DB_USER in NONSECRET_DEFAULTS; assert-array inclusion (ADR-072
--       Amendment 1's corrected three additions). DevOps; returns to Sec joint-review.
--     · infra/supabase/docker-compose.yml + the migrator's .env.example — the migrator
--       service block referencing ${MIGRATOR_DB_PASSWORD} (the confinement-by-non-
--       reference property). DevOps.
--
-- ----------------------------------------------------------------------------
-- §10 3-AXIS CROSS-CHECK (Path B — reference ADR-011 Decision 4; the catalogued
--   numbered list is NOT restated here and no count is carried into this file.
--   Decision 4 read VERBATIM and live before drafting, on 2026-09-12.)
--   LEDGER EFFECT: NONE.
--   (i)   Instance-numbering — no catalogued instance is added, removed, reordered or
--         renumbered. The relative ordering recorded in Decision 4 is untouched.
--   (ii)  Layer-attribution — `migrator` is a DB-LAYER cluster ROLE/identity. It is
--         NOT the code-layer SUPABASE_SERVICE_ROLE_KEY allowlist grep fence (this is a
--         direct-Postgres login credential; migrator holds no Supabase service-role
--         KEY), NOT the PDF-worker container credential-presence audit, and NOT the
--         app->worker admission network/config surface. No catalogued instance's layer
--         attribution moves, and no surface becomes "four-layer".
--   (iii) Verbatim-vs-paraphrase — Decision 4 is linked, not restated. 118 is not the
--         canonical anchor.
--   DE-CONFLATION GUARD: introducing a new LOGIN identity is a credential-posture
--   change, NOT a §10 catalogued-instance addition — the §10 ledger enumerates specific
--   defense-in-depth FENCE instances, not every role in the cluster (the 055/116
--   precedent, and ADR-072's own ledger-discipline note).
--   ⚠ The §10 CATALOGUED set and the CI-FENCED RT set (ADR-072 C9's RT-27/RT-32
--   config-lint coverage of the migrator service) are DIFFERENT SETS and are not
--   reconciled against one another; this migration changes neither.
--
-- ----------------------------------------------------------------------------
-- DECISION 3 (cross-tenant FK-bypass family) — UNCHANGED (+0). ADR-011 Decision 3
--   read verbatim and live on 2026-09-12. This migration creates NO table, NO column,
--   and therefore NO FK-shaped reference column of any kind — not a single FK, not a
--   self-FK, not an INTEGER[] array. There is nothing here for matched-tenant
--   validation to apply to, and no instance label is claimed.
--
-- OTHER LEDGERS — ALL FLAT (each confirmed by reading the canonical ADR-011 body live
--   on 2026-09-12, not from memory):
--     · SECURITY DEFINER allowlist — unchanged; this migration authors NO function.
--     · aal2 step-up backstop (ADR-029 / 025) — not engaged; no new table.
--     · SECURITY doc — no new SD/RT entry proposed here; the migrator's login-identity
--       and CI-fence posture are Sec-owned and routed to Sec, not edited by Architect.
--
-- ----------------------------------------------------------------------------
-- CONTRACT
--   migrator — cluster-level login role; the ADR-072 Option-E migrator service's
--     database identity, used for UNSUPERVISED `supabase db push` of migrations 119+
--     once the deploy mechanism is built. Attributes AS CREATED BY THIS MIGRATION:
--     **NOLOGIN**, **NOINHERIT**, **CREATEROLE**, NO PASSWORD — the role ships INERT.
--     Explicitly NOT: SUPERUSER, CREATEDB, REPLICATION, BYPASSRLS. Holds NO role
--     membership of any kind (in particular NOT service_role / authenticated / anon),
--     owns no object, and holds NO direct table, schema, function or sequence
--     privilege. It becomes usable only at the SUPERVISED deploy-time handoff above.
--     So `rolcanlogin` is FALSE at migration time and TRUE only in a provisioned
--     environment — a test asserting migration-time state must expect FALSE.
--   Privilege shape (the INVERSE of the worker roles): CREATEROLE + app-database
--     ownership (ownership set at the handoff, run as postgres), and NO app-role
--     membership — enough to apply the current migration set without superuser, and
--     no more. A migration needing true superuser fails against it, by design.
--   Security-load-bearing edges: NOLOGIN-at-creation makes the role unreachable by its
--     own attribute (checked before any pg_hba method), so it is inert even under a
--     `trust` line with no dependency on a config file outside this repo; not superuser
--     and not CREATEDB, so it cannot flip database ownership or run superuser-only DDL —
--     a migration needing either trips the Decision-4 tripwire; no ADMIN OPTION on the
--     platform roles `postgres`/`authenticator`/`pfin_etl`/`pfin_provider_sync`, so it
--     cannot ALTER or COMMENT them; NOINHERIT so a future erroneous membership grant
--     confers nothing without an explicit SET ROLE; holds no BYPASSRLS attribute.
--   Verifiability: the C8 attributes above are asserted at APPLY time (hard-fail) by the
--     block below, on every apply and in both the inert and provisioned states, so the
--     bound stays enforced rather than merely documented. This is NOT QA-pairing-
--     triggered: the migration adds no RLS policy and no SECURITY INVOKER helper, so the
--     two-tenant pgTAP battery has nothing to extend. A pgTAP leg asserting
--     rolcreaterole=true / rolsuper=false / non-membership is a reasonable belt-and-
--     suspenders addition but is not required by the RLS-surface pairing rule; the
--     apply-time assertion is the primary home.
--   Idempotency: CREATE ROLE has no IF NOT EXISTS, so creation is guarded on pg_roles in
--     a DO block. The guard does NOT reset attributes on a pre-existing role (deliberate:
--     after deploy the role is legitimately LOGIN, and resetting would take the migrator
--     service down), and the else-branch REPORTS the found attributes and WARNS on the
--     two states that would defeat the posture (INHERIT, LOGIN-with-no-password). COMMENT
--     is a straight overwrite. The whole migration is re-runnable BY POSTGRES.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Create the role, guarded (CREATE ROLE has no IF NOT EXISTS).
-- NOLOGIN + NOINHERIT + CREATEROLE + NO PASSWORD by design — see the DEPLOY-TIME
-- CREDENTIAL HANDOFF block. The role ships INERT: unreachable by its own attribute,
-- independent of pg_hba, and holding no membership and no object privilege.
-- ----------------------------------------------------------------------------
do $$
declare
  v_canlogin  boolean;
  v_inherit   boolean;
  v_haspass   text;
begin
  if not exists (select 1 from pg_catalog.pg_roles where rolname = 'migrator') then
    create role migrator with nologin noinherit createrole;
    raise notice 'migrator created NOLOGIN + NOINHERIT + CREATEROLE + no password (inert by construction). DEPLOY STEPS REQUIRED, run as postgres, IN ORDER: (0) ALTER DATABASE <app_db> OWNER TO migrator;  [migrator is not CREATEDB and cannot run this itself]  then (1) \password migrator  [prompts; verifier computed client-side; role still NOLOGIN so this is inert]  then (2) ALTER ROLE migrator LOGIN;  [carries no secret]. Do NOT use ALTER ROLE ... WITH LOGIN PASSWORD ''<plaintext>'' — statement logging captures it verbatim in the server log (Sec B10). THEN set the migrator service env: MIGRATOR_DB_USER=migrator + MIGRATOR_DB_PASSWORD (minted on-box by provision-supabase-stack.sh MINT_SECRETS).';
  else
    select r.rolcanlogin, r.rolinherit into v_canlogin, v_inherit
      from pg_catalog.pg_roles r where r.rolname = 'migrator';
    begin
      select case when a.rolpassword is null then 'NO' else 'yes' end into v_haspass
        from pg_catalog.pg_authid a where a.rolname = 'migrator';
    exception when insufficient_privilege then
      v_haspass := 'unreadable (pg_authid not visible to the applying role)';
    end;
    raise notice 'migrator already exists — creation SKIPPED; attributes NOT re-applied (deliberate: a deployed role is legitimately LOGIN, and resetting it would take the migrator service down). Found: rolcanlogin=% / rolinherit=% / password set=%.',
      v_canlogin, v_inherit, v_haspass;
    if v_inherit then
      raise warning 'migrator exists but is INHERIT — this weakens the 118 posture (a future erroneous membership grant would confer privilege without an explicit SET ROLE). Investigate before relying on it; fix with: ALTER ROLE migrator NOINHERIT;';
    end if;
    if v_canlogin and v_haspass = 'NO' then
      raise warning 'migrator exists as LOGIN with NO PASSWORD — reachable with NO CREDENTIAL under any pg_hba `trust` line (local/CI). This is the exact state 118 is shaped to avoid, and it is what running the LOGIN step without the \password step leaves behind. Either complete the deploy step (\password migrator) or disable it (ALTER ROLE migrator NOLOGIN).';
    end if;
  end if;
end
$$;

-- ----------------------------------------------------------------------------
-- ⚠ C8 APPLY-TIME STRUCTURAL ASSERTION — the verifiable half of C8.
-- These invariants hold in BOTH the inert (bootstrap) and provisioned (post-handoff)
-- states, so the block runs UNCONDITIONALLY and HARD-FAILS the apply if any is
-- violated — catching a tampered pre-existing role on re-apply AND a future edit to
-- this file that weakens the CREATE. It reads only pg_roles + pg_auth_members (both
-- world-readable), so it works when the applier is `migrator` as well as `postgres`.
-- Cf. the migration-111 apply-time watcher: a comment is not a check; this is.
-- NOTE: rolcanlogin is NOT asserted — it is FALSE at bootstrap and TRUE post-handoff,
-- a legitimate state change, so asserting it would break a correct re-apply.
-- OWNER-of-database is NOT asserted here — at bootstrap the DB is postgres-owned; the
-- ownership flip and its verification live in the operator handoff (runbook §6.3).
-- ----------------------------------------------------------------------------
do $c8$
declare
  r          pg_catalog.pg_roles%rowtype;
  v_bad      text[] := array[]::text[];
  v_approle  text;
begin
  select * into r from pg_catalog.pg_roles where rolname = 'migrator';
  if not found then
    raise exception 'migrator role missing after the create guard — 118 did not establish the role it exists to create.';
  end if;

  -- ⚠ array_append, NOT `v_bad || '<literal>'`: `text[] || <unknown-typed literal>`
  -- resolves to the array||array operator and tries to parse the literal AS an array
  -- ("malformed array literal"). Caught by the C8 inversion test. array_append picks
  -- the element form unambiguously.
  if not r.rolcreaterole then v_bad := array_append(v_bad, 'rolcreaterole must be TRUE (C8: the CREATEROLE driver)'); end if;
  if r.rolsuper        then v_bad := array_append(v_bad, 'rolsuper must be FALSE (C8: non-superuser)'); end if;
  if r.rolbypassrls    then v_bad := array_append(v_bad, 'rolbypassrls must be FALSE (must never bypass RLS)'); end if;
  if r.rolcreatedb     then v_bad := array_append(v_bad, 'rolcreatedb must be FALSE (not CREATEDB — this is also what keeps ALTER DATABASE OWNER a postgres-only step)'); end if;

  -- C8: NOT a member of any app role. pg_has_role(...,'MEMBER') is transitive, so this
  -- also catches an indirect membership acquired through another role.
  foreach v_approle in array array['service_role','authenticated','anon'] loop
    if exists (select 1 from pg_catalog.pg_roles where rolname = v_approle)
       and pg_catalog.pg_has_role('migrator', v_approle, 'MEMBER') then
      v_bad := array_append(v_bad, format('migrator must NOT be a member of the app role %L (C8)', v_approle));
    end if;
  end loop;

  if array_length(v_bad, 1) is not null then
    raise exception 'migrator role FAILS its C8 attribute constraints (ADR-072 Decision 4): %. This role governs a standing, triggerable DDL credential; a widened attribute must be reverted, not shipped. If the role was legitimately altered, that is a Sec-joint-review posture change, not a migration re-apply artifact.',
      array_to_string(v_bad, '; ');
  end if;

  raise notice 'migrator C8 attributes OK: CREATEROLE true / superuser false / bypassrls false / createdb false / no app-role membership.';
end
$c8$;

-- ----------------------------------------------------------------------------
-- Self-documenting comment (the role analogue of `comment on function`).
-- Deliberately carries no ledger count and no enumeration of any catalogued set:
-- a catalog comment is read by someone with no repo in front of them and can only be
-- corrected by a further migration, so it states durable properties and standing
-- requirements rather than facts about today's tree.
-- ----------------------------------------------------------------------------
comment on role migrator is
  'Bounded DDL-apply login identity for the ADR-072 Option-E migrator service (Decision 4 + Amendment 1; migration 118). Runs UNSUPERVISED `supabase db push` of later migrations once the Option-E deploy mechanism is built. Created NOLOGIN + NOINHERIT + CREATEROLE with NO PASSWORD (inert by construction); NOT superuser, NOT CREATEDB, NOT REPLICATION, NOT BYPASSRLS; owns no object; holds NO role membership of any kind — in particular NOT service_role, authenticated or anon — and NO direct table, schema, function or sequence privilege. Its privilege shape is the INVERSE of the worker roles (pfin_etl/pfin_provider_sync hold app-role membership and no CREATEROLE; this role holds CREATEROLE and no membership). CREATEROLE + app-database ownership is the SMALLEST standing credential that applies the current migration set without superuser: CREATEROLE for 055/116''s CREATE ROLE, database ownership for 061''s ALTER DATABASE … SET. A migration needing true superuser (a new extension, ALTER SYSTEM) FAILS against this role — a deliberate ADR-072 Decision-4 tripwire that forces a supervised superuser apply and a Sec conversation, never a silent widening of a standing credential. ⚠ APP-DATABASE OWNERSHIP IS SET AT THE OPERATOR HANDOFF, run as postgres, NOT by this migration: ALTER DATABASE … OWNER TO requires superuser or CREATEDB+membership, and this role is neither, so it cannot flip its own ownership — which is why the flip is a postgres-run bootstrap step, symmetric with the LOGIN/password flip. Because postgres (not migrator) creates the platform roles at bootstrap, migrator holds no ADMIN OPTION on postgres/authenticator/pfin_etl/pfin_provider_sync and cannot ALTER or COMMENT them: a future migration that tries, run unsupervised as migrator, trips by design. CREATED NOLOGIN WITH NO PASSWORD — a repo-committed credential is prohibited; an operator switches the role on at the SUPERVISED first bootstrap, as postgres, with (0) ALTER DATABASE <app_db> OWNER TO migrator, then (1) `\password migrator` (prompts, computes the SCRAM verifier CLIENT-SIDE, sets ONLY the password while the role is still NOLOGIN and therefore inert), then (2) `ALTER ROLE migrator LOGIN` (carries no secret). The single statement `ALTER ROLE ... WITH LOGIN PASSWORD ''<plaintext>''` is PROHIBITED per the Sec B10 ruling: statement logging captures it verbatim, writing the credential to the server log in cleartext, and typing it also lands it in ~/.psql_history. Be precise about what \password buys: plaintext never leaves the client, but the resulting ALTER USER carrying a SCRAM-SHA-256 verifier IS still logged — that verifier is not a usable credential (a client proof needs ClientKey, which StoredKey does not yield), leaving only an offline attack bounded by secret entropy and iteration count, which is why the secret MUST be high-entropy and machine-generated (openssl rand -hex 32). Do NOT claim "the secret isn''t logged". Ordering matters: running the LOGIN step without the \password step leaves LOGIN-with-no-password, the exact state this role is shaped to avoid, and it is what the re-apply WARNING branch in 118 detects. NOLOGIN rather than LOGIN-without-a-password because rolcanlogin is checked BEFORE any pg_hba auth method: a passwordless LOGIN role is reachable with NO credential under a `trust` line. Consequence for tests: rolcanlogin is FALSE at migration time and TRUE only in a provisioned environment. The credential is minted on-box by provision-supabase-stack.sh MINT_SECRETS (MIGRATOR_DB_PASSWORD, production_only) and confined to the migrator service by non-reference under Coolify''s interpolation-only compose (ADR-072 Amendment 1); the scripted non-interactive bind depends on SELF-395. The role''s C8 attributes (CREATEROLE true, superuser/bypassrls/createdb false, no app-role membership) are asserted at APPLY time by 118 and fail the apply if violated. Revoke with ALTER ROLE migrator NOLOGIN.';
