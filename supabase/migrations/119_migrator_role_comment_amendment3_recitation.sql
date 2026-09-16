-- ============================================================================
-- Migration: migrator role comment — ADR-072 AMENDMENTS 3-4 RE-CITATION.
--   COMMENT-ONLY. Re-issues `comment on role migrator` (created at 118) with
--   FOUR changed regions and nothing else:
--     (S1) the citation, re-pointed from "Decision 4 + Amendment 1" to
--          "Decision 4 + Amendments 3-4", carrying a dated parenthetical
--          recording what it previously read (the 117 convention);
--     (S2) the confinement clause, which asserted confinement-by-non-reference
--          as a live property under Amendment 1 and now states it as a
--          REQUIREMENT AWAITING ITS REMEDY, records Amendment 1's PRESERVED
--          claim as WITHDRAWN, names Amendment 4's ratified remedy, and hands
--          the reader the instrument that settles it (container Config.Env,
--          names only) instead of a claim they cannot check;
--     (S3) the supervised first bootstrap, re-attributed from `postgres` to the
--          image's TRUE SUPERUSER (`supabase_admin`), with the operator handed a
--          one-line check, and the statement set corrected from three to FOUR by
--          the `supabase_migrations` owner transfer;
--     (S4) the COMMENT/ALTER limit, extended to the case it omitted — this role
--          itself — AND re-framed as an INSTANCE of the general object-ownership
--          gap rather than a property of role comments, per Sec's one condition
--          on this PR: every pfin object is owned by the bootstrap role, so
--          ALTER / COMMENT / DROP fail for migrator on tables, views, sequences,
--          types and functions the same way; role comments are only where the
--          gap was met first. Without that clause the next reader concludes role
--          comments are the affected class and rediscovers this at the first
--          ALTER TABLE.
--   ⚠ DESCRIBED, NOT QUOTED. The shipped wording is the literal at the foot of
--   this file; read it there. A quotation here would have to elide, and an
--   elision inside a quotation is the defect class 117 exists to record.
--   Nothing else in the comment changes. No role attribute, no membership, no
--   grant, no privilege, no function, no table, no policy, no column is created,
--   altered or dropped by this file.
--   BACKLOG §7.36 items 27 / 29 / 31 / 32. ADR-072 Amendment 3 (2026-09-14) +
--   Amendment 4 (F/CTO-ratified 2026-09-16). apply-migration Step 1.6 (A) applied.
--   JOINT-REVIEW-MANDATORY (Sec veto surface): 118 is Sec-load-bearing and this
--   re-issues its catalog text on a standing DDL credential's identity.
--
-- ----------------------------------------------------------------------------
-- ⚠⚠ THE APPLIER IS LOAD-BEARING, AND IT IS NOT `migrator`. MEASURED, NOT
--   ASSUMED. This migration CANNOT be applied by the migrator service, and that
--   is the ADR-072 Decision-4 tripwire operating exactly as designed rather than
--   a defect in this file:
--     · Measured on `public.ecr.aws/supabase/postgres:17.6.1.132` (PG 17.6), the
--       deployed image family, in a disposable cluster: a role with the C8
--       attribute set (NOINHERIT, CREATEROLE, non-superuser, LOGIN) running
--       `comment on role migrator` gets
--         ERROR: permission denied
--         DETAIL: The current user must have the ADMIN option on role "migrator".
--     · The gap is NOT closable by a grant. `grant migrator to migrator with
--       admin option` is refused by Postgres itself —
--         ERROR: role "migrator" is a member of role "migrator"
--       — so no supervised step, and no widening short of superuser, gives this
--       role ADMIN OPTION on itself. 118's header predicted this for a replay;
--       the measurement above establishes it for a FIRST apply as well.
--   CONSEQUENCE, stated plainly because it changes who merges this and when:
--   119 must be applied in the SUPERVISED superuser pass (runbook §6.3, as
--   `supabase_admin`), NOT by the Phase D Scheduled Task. Routed to F/CTO.
--
-- ----------------------------------------------------------------------------
-- Numbering: 119 follows 118 (migrator role). Depends on 118 having created the
--   role `migrator` — `comment on role` on a non-existent role errors. Depends on
--   NOTHING in the pfin schema and creates no pfin object. Nothing downstream
--   depends on 119. Order-independent past 118.
--
-- ----------------------------------------------------------------------------
-- WHY A NEW MIGRATION AND NOT AN EDIT TO 118 (apply-migration Step 1.6 (A)):
--   `comment on role` has a DATABASE REPRESENTATION — it ships into the SHARED
--   catalog pg_shdescription and is read at `\du+` / shobj_description() by an
--   operator with no repo in front of them. Text with a database representation
--   can only change by issuing new SQL, so the vehicle is a comment-only
--   migration (the 052 shape), never an edit to the merged file.
--   ⚠ THE CONVERSE IS ALSO IN PLAY AND IS DELIBERATELY NOT TAKEN HERE: 118's
--   FILE-HEADER `--` claims that the first bootstrap runs as `postgres` have NO
--   database representation and are therefore corrected IN PLACE, under Step
--   1.6 (B)'s three conditions, as BACKLOG §7.36 item 31. That is a separate
--   vehicle and a separate change; 118 is NOT touched by this PR.
--
-- ----------------------------------------------------------------------------
-- WHAT DID NOT CHANGE, stated because a reader may expect this migration to have
--   touched it: the comment's B10 prohibition on the single-statement
--   `ALTER ROLE ... WITH LOGIN PASSWORD` form, its `\password` precision note,
--   its NOLOGIN-rather-than-passwordless-LOGIN rationale, its C8 attribute
--   recital and its privilege-shape paragraph are all UNTOUCHED and already
--   correct. Nothing an operator is told to do changes except the identity they
--   run as (S3) and the fourth statement they run (S3).
--
-- ----------------------------------------------------------------------------
-- POSTURE RATIONALE — NO FUNCTION IS AUTHORED HERE, so the SECURITY INVOKER /
--   SECURITY DEFINER question does not arise. This migration issues no `create`,
--   `create or replace`, `alter` or `drop` of any function, so the ADR-011
--   Decision 9 SECURITY DEFINER allowlist is UNCHANGED in both directions.
--   ON `set search_path = ''`, stated precisely rather than claimed: a `do`
--   block takes no SET clause in PostgreSQL, so the guard below cannot carry
--   one. It achieves the same property the harder way — EVERY catalog relation
--   and function it references is `pg_catalog`-qualified, so no search_path can
--   re-resolve them. The `comment on` statement itself resolves one role name in
--   a shared catalog and evaluates no expression.
--
-- CONTRACT
--   comment on role migrator — replaces the role's pg_shdescription entry with a
--     regenerated copy of 118's literal carrying exactly four changed regions.
--     No behaviour, no privilege and no attribute is contingent on this
--     statement; a catalog comment is documentation.
--   applier guard (do block) — reads pg_roles + pg_auth_members and RAISES with
--     an operator instruction when the applying role can be shown to lack the
--     ADMIN OPTION the `comment on role` needs. It issues no DDL, grants
--     nothing, and changes no state. It exists to convert Postgres's bare
--     `permission denied` into the named remedy (run §6.3 as `supabase_admin`),
--     because the failing applier here is an unattended Scheduled Task whose
--     operator reads an exit status, not a psql transcript.
--     ⚠ It is a NECESSARY-not-SUFFICIENT check and says so: it reproduces
--     Postgres's own rule (superuser, or ADMIN OPTION reachable from the current
--     user), so a FALSE from it is authoritative while a TRUE only means the
--     statement is not refused for THAT reason. Postgres remains the decider.
--   ⚠ pg_shdescription is a SHARED catalog: a role comment is CLUSTER-WIDE, not
--     per-database. Applying this against a scratch DATABASE mutates the comment
--     for every database in that cluster. Render-verify and replay therefore run
--     in a DISPOSABLE CLUSTER (a fresh container), never a scratch database
--     inside a cluster anyone else is using — 117's C7 finding, applied.
--   IDEMPOTENCE: `comment on role` REPLACES rather than accumulates; re-applying
--     119 is a no-op onto its own outcome. Re-applying 118 AFTER 119 would
--     restore the OLD text, but 118 is earlier in the sorted chain, so a
--     sorted-order apply always leaves 119's text last.
--
-- ----------------------------------------------------------------------------
-- §10 3-AXIS CROSS-CHECK — ADR-011 Decision 4 read VERBATIM, live, before
--   drafting (2026-09-16). Path B: this file LINKS to Decision 4 and restates
--   neither its catalogued list nor its size. Result: NO CHANGE ON ANY AXIS.
--   (i)   Instance-numbering: 119 catalogues no §10 instance, adds none, removes
--         none, reorders none, renumbers none. The ledger is untouched.
--   (ii)  Layer-attribution: no layer moves and no surface becomes "four-layer".
--         This file creates no fence at any layer — it replaces documentation
--         text in a shared catalog.
--   (iii) Verbatim-vs-paraphrase: Decision 4 is referenced, not restated, and no
--         count is carried into this file. 119 is not its canonical anchor.
--   ⚠ The §10 CATALOGUED set and the CI-FENCED RT set are DIFFERENT SETS and are
--     not reconciled here or anywhere. Nothing in this migration touches either.
--     The ADR-072 Amendment 4 sibling-fence target is a CI-fenced-set change and
--     lands in the DevOps remedy PR, not in this file.
--   DE-CONFLATION GUARD: no FK-shaped reference column is added (no column at
--     all), so the ADR-011 Decision 3 cross-tenant family is UNCHANGED and gains
--     no instance (Decision 3 read live, 2026-09-16). No new sensitive
--     tenant-owned pfin table, so the ADR-029 / 025 aal2 step-up backstop
--     inheritance obligation does not arise. SECURITY DEFINER allowlist
--     unchanged. No SD/RT entry is proposed here.
--
-- ----------------------------------------------------------------------------
-- JOINT-REVIEW routing: Sec joint-review before merge (118 is Sec-load-bearing;
--   this re-issues its catalog text and re-grades a Sec condition, C7, from
--   satisfied to awaiting-remedy). QA: no RLS surface is extended and no policy
--   changes, so the two-tenant verification battery is not extended by this
--   file; a pgTAP leg reading shobj_description('migrator') ships in this PR
--   because that leg is what would observe a regression in the changed text.
--   DevOps: no CI fixture change is required. F/CTO: the applier finding above.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Applier guard. Necessary-not-sufficient; see CONTRACT. Issues no DDL.
-- ----------------------------------------------------------------------------
do $guard$
declare
  v_admin boolean;
begin
  select coalesce((select r.rolsuper from pg_catalog.pg_roles r
                    where r.rolname = current_user), false)
      or exists (
           select 1
             from pg_catalog.pg_auth_members m
             join pg_catalog.pg_roles tgt     on tgt.oid = m.roleid
             join pg_catalog.pg_roles grantee on grantee.oid = m.member
            where tgt.rolname = 'migrator'
              and m.admin_option
              and pg_catalog.pg_has_role(current_user, grantee.oid, 'USAGE'))
    into v_admin;

  if not v_admin then
    raise exception using
      errcode = '42501',
      message = pg_catalog.format('migration 119 cannot be applied by %I: COMMENT ON ROLE migrator requires superuser, or the ADMIN option on role migrator.', current_user),
      detail  = 'Postgres refuses to grant any role the ADMIN option on itself (GRANT migrator TO migrator WITH ADMIN OPTION errors "role migrator is a member of role migrator"), so the migrator service can never apply this migration and no grant closes the gap. This is the ADR-072 Decision-4 tripwire behaving as designed, not a defect in the migration.',
      hint    = 'Apply 119 in the supervised superuser pass: deployment-runbook.md §6.3, as supabase_admin (the true superuser on the Supabase Postgres image; postgres measures rolsuper = f there). Do NOT widen the migrator role to get past this.';
  end if;
end
$guard$;

-- ----------------------------------------------------------------------------
-- The role comment, REGENERATED from 118's literal (never retyped) by four
-- anchored substitutions, each asserted to match EXACTLY ONCE, with a
-- containment proof that inverting the four substitutions reproduces 118's
-- literal byte-for-byte. The generator and its proof are recorded in the PR body.
-- ----------------------------------------------------------------------------
comment on role migrator is
  'Bounded DDL-apply login identity for the ADR-072 Option-E migrator service (Decision 4 + Amendments 3–4; migration 118, re-cited by migration 119 on 2026-09-16 — this citation previously read "Decision 4 + Amendment 1", and Amendment 3 withdrew that amendment''s confinement claim). Runs UNSUPERVISED `supabase db push` of later migrations once the Option-E deploy mechanism is built. Created NOLOGIN + NOINHERIT + CREATEROLE with NO PASSWORD (inert by construction); NOT superuser, NOT CREATEDB, NOT REPLICATION, NOT BYPASSRLS; owns no object; holds NO role membership of any kind — in particular NOT service_role, authenticated or anon — and NO direct table, schema, function or sequence privilege. Its privilege shape is the INVERSE of the worker roles (pfin_etl/pfin_provider_sync hold app-role membership and no CREATEROLE; this role holds CREATEROLE and no membership). CREATEROLE + app-database ownership is the SMALLEST standing credential that applies the current migration set without superuser: CREATEROLE for 055/116''s CREATE ROLE, database ownership for 061''s ALTER DATABASE … SET. A migration needing true superuser (a new extension, ALTER SYSTEM) FAILS against this role — a deliberate ADR-072 Decision-4 tripwire that forces a supervised superuser apply and a Sec conversation, never a silent widening of a standing credential. ⚠ APP-DATABASE OWNERSHIP IS SET AT THE OPERATOR HANDOFF, run as postgres, NOT by this migration: ALTER DATABASE … OWNER TO requires superuser or CREATEDB+membership, and this role is neither, so it cannot flip its own ownership — which is why the flip is a postgres-run bootstrap step, symmetric with the LOGIN/password flip. Because postgres (not migrator) creates the platform roles at bootstrap, migrator holds no ADMIN OPTION on postgres/authenticator/pfin_etl/pfin_provider_sync and cannot ALTER or COMMENT them: a future migration that tries, run unsupervised as migrator, trips by design. ⚠ THE SAME LIMIT REACHES THIS ROLE ITSELF, and it is not removable: Postgres refuses to grant a role ADMIN OPTION on itself (GRANT migrator TO migrator WITH ADMIN OPTION errors ''role "migrator" is a member of role "migrator"''), so migrator cannot COMMENT ON ROLE migrator either — measured on this image at PG 17.6, which answers ''permission denied / The current user must have the ADMIN option on role "migrator"''. EVERY correction to THIS comment is therefore a SUPERVISED superuser act and can never be an unsupervised migrator apply; migration 119 is such a correction and must be applied that way. ⚠⚠ AND THIS IS AN INSTANCE OF A GENERAL GAP, NOT A PROPERTY OF ROLE COMMENTS. Owning the DATABASE confers CREATE within it, ALTER DATABASE ... SET and DROP DATABASE, and confers NO ownership of any object INSIDE it; ALTER, COMMENT and DROP on an existing object require ownership of that object or membership in its owner. Every pfin object created by the bootstrap role is owned by that role, so those verbs fail for migrator on tables, views, sequences, types and functions exactly as this statement does — role comments are simply where it was met first. Do not infer object ownership from database ownership: read it, with select pg_get_userbyid(relowner) from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = ''pfin''. The remedy is an OWNERSHIP SHAPE, decided under ADR-072, and is never a widening of this role''s attributes. CREATED NOLOGIN WITH NO PASSWORD — a repo-committed credential is prohibited; an operator switches the role on at the SUPERVISED first bootstrap, run as the image''s TRUE SUPERUSER — `supabase_admin` on the Supabase Postgres image, NOT `postgres`, which measures rolsuper = f there and fails the OWNER statement with "must be able to SET ROLE migrator"; check it with `select rolsuper from pg_roles where rolname in (''postgres'',''supabase_admin'')` before starting — with FOUR statements: (0) ALTER DATABASE <app_db> OWNER TO migrator, then (1) `\password migrator` (prompts, computes the SCRAM verifier CLIENT-SIDE, sets ONLY the password while the role is still NOLOGIN and therefore inert), then (2) `ALTER ROLE migrator LOGIN` (carries no secret), then (3) ALTER SCHEMA supabase_migrations OWNER TO migrator plus one ALTER TABLE ... OWNER TO migrator per table in that schema, enumerated at run time rather than copied — owning the DATABASE does not extend to owning the migration-ledger SCHEMA, which the bootstrap created before this role existed. The single statement `ALTER ROLE ... WITH LOGIN PASSWORD ''<plaintext>''` is PROHIBITED per the Sec B10 ruling: statement logging captures it verbatim, writing the credential to the server log in cleartext, and typing it also lands it in ~/.psql_history. Be precise about what \password buys: plaintext never leaves the client, but the resulting ALTER USER carrying a SCRAM-SHA-256 verifier IS still logged — that verifier is not a usable credential (a client proof needs ClientKey, which StoredKey does not yield), leaving only an offline attack bounded by secret entropy and iteration count, which is why the secret MUST be high-entropy and machine-generated (openssl rand -hex 32). Do NOT claim "the secret isn''t logged". Ordering matters: running the LOGIN step without the \password step leaves LOGIN-with-no-password, the exact state this role is shaped to avoid, and it is what the re-apply WARNING branch in 118 detects. NOLOGIN rather than LOGIN-without-a-password because rolcanlogin is checked BEFORE any pg_hba auth method: a passwordless LOGIN role is reachable with NO credential under a `trust` line. Consequence for tests: rolcanlogin is FALSE at migration time and TRUE only in a provisioned environment. The credential is minted on-box by provision-supabase-stack.sh MINT_SECRETS (MIGRATOR_DB_PASSWORD, production_only) ⚠ CONFINEMENT OF THIS CREDENTIAL TO THIS SERVICE IS A REQUIREMENT AWAITING ITS REMEDY, NOT A PROPERTY THE DEPLOYMENT PROVIDES. ADR-072 Amendment 3 (2026-09-14) measured, on the running stack, that every service in the Supabase-stack Coolify application receives that application''s entire env store through an env_file which a service''s own declared environment block does not bound — so this credential reaches every service of that application, and this service correspondingly holds every other secret in it, including the cluster superuser password and the RLS-bypassing service-role key. Amendment 1''s claim that confinement was PRESERVED by non-reference is WITHDRAWN. Amendment 4 (2026-09-16) ratified the remedy: the migrator moves to its OWN Coolify resource, minted on-box into that resource''s own store, with this credential ROTATED at cutover. Whether that remedy has landed is a question about the deployment and not about this catalog — answer it with `docker inspect` over the container''s own Config.Env reduced to NAMES, never from a declared environment block, which is precisely the evidence that failed. The scripted non-interactive bind depends on SELF-395. The role''s C8 attributes (CREATEROLE true, superuser/bypassrls/createdb false, no app-role membership) are asserted at APPLY time by 118 and fail the apply if violated. Revoke with ALTER ROLE migrator NOLOGIN.';
