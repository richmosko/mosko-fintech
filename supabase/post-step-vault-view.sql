-- ============================================================================
-- ⚠ NOT A MIGRATION. Deliberately outside supabase/migrations/ so the CLI never
-- applies it: it must run AFTER the main pass (its base table is created there) and
-- as a privileged identity. Referenced BY PATH from docs/deployment-runbook.md §6.3
-- and ADR-072 Amendment 5 Decision I — the runbook must not restate this SQL.
-- CI applies it too, after the migrations, so the standing battery observes the same
-- end state a production box does.
-- ADR-072 Amendment 5 — (iv‴) SUPERVISED POST-STEP. Run ONCE, as the image's true
-- superuser (`supabase_admin`), AFTER the main `supabase db push` completes and
-- BEFORE the §7 container bring-up. It is safe to re-run.
-- WHY A POST-STEP AND NOT A PRE-STEP: the view reads pfin.linked_source, which the
-- MAIN PASS creates. A pre-step cannot create this view; it does not yet have a
-- table to read (measured).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- (0) ORDERING GATE — refuse to run before the main pass finished, so nobody
--     hand-creates the view with the wrong owner mid-outage.
-- ⚠ Asserted as "migration 118 is present", NOT as "the ledger has 118 rows".
--     Sec's condition named a row COUNT; a count rots the moment 120+ land and
--     would then refuse a correct box. "118 is present" answers the same
--     question and stays true forever. Flagged to Sec as a refinement, not
--     taken silently.
-- ----------------------------------------------------------------------------
do $gate$
begin
  if not exists (select 1 from supabase_migrations.schema_migrations where version = '118') then
    raise exception using errcode = '55000',
      message = 'ADR-072 (iv‴) post-step REFUSED: migration 118 is not in the ledger, so the main pass has not completed.',
      detail  = 'Creating the decrypt view before the main pass risks landing it with the wrong owner or without security_invoker — the exact defect this shape exists to prevent, arriving during an outage when it is most tempting.',
      hint    = 'Run the main `supabase db push` to completion first, then re-run this post-step.';
  end if;
  if to_regclass('pfin.linked_source') is null then
    raise exception using errcode = '42P01',
      message = 'ADR-072 (iv‴) post-step REFUSED: pfin.linked_source does not exist.',
      hint    = 'The main pass must create the base table before this view can read it.';
  end if;
end
$gate$;

-- ----------------------------------------------------------------------------
-- (1) THE VIEW UNIT — create + comment + revokes + grant, exactly as migration
--     015 carries it. Create-through-grant or nothing: a view that lands without
--     its REVOKEs exists under a default ACL, the RT-02 hazard 015's header names.
-- ----------------------------------------------------------------------------
create or replace view pfin.decrypted_source_credential
  with (security_invoker = true) as
  select
    ls.source_id,
    ls.users_id,
    ls.provider,
    ls.external_connection_id,
    ds.decrypted_secret as decrypted_credential
  from pfin.linked_source ls
  join vault.decrypted_secrets ds on ds.id = ls.credential_secret_id;

comment on view pfin.decrypted_source_credential is
  'SD-03 decrypt view (ADR-011 Decision 8 / Lock 4 mod #1). security_invoker = true: runs as the CALLER, so its vault-less owner pfin_owner is not the identity that resolves the vault join (ADR-072 Amendment 5 (iv‴)). Created by the supervised post-step because its base table is created by the main pass. service_role is the only grantee and already holds SELECT on vault.decrypted_secrets in the image ACL.';

revoke all on pfin.decrypted_source_credential from public;
revoke all on pfin.decrypted_source_credential from anon;
revoke all on pfin.decrypted_source_credential from authenticated;
grant select on pfin.decrypted_source_credential to service_role;

-- ----------------------------------------------------------------------------
-- (2) OWNERSHIP TRANSFER. ALTER VIEW ... OWNER TO does not re-validate the body
--     (measured), so this succeeds even though pfin_owner holds no vault reach.
--     security_invoker = true above is what keeps the view WORKING afterwards.
-- ----------------------------------------------------------------------------
alter view pfin.decrypted_source_credential owner to pfin_owner;

-- ----------------------------------------------------------------------------
-- (3) ⛔ THE ASSERTION THAT FAILS THE STEP — Sec's condition. This is the ONLY
--     watcher that observes the PRODUCTION database at the moment it can be
--     wrong. The runbook verify is a human double-check; the pgTAP leg is a
--     regression watcher on the DEFINITION in CI. Neither is a production
--     observer, and they must not be counted as one.
-- ----------------------------------------------------------------------------
do $verify$
declare
  v_n     integer;
  v_owner text;
  v_inv   text;
begin
  select count(*) into v_n
    from pg_catalog.pg_class c join pg_catalog.pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'pfin' and c.relkind = 'v' and c.relname like 'decrypted%';
  if v_n <> 1 then
    raise exception using errcode = '55000',
      message = format('ADR-072 (iv‴) post-step FAILED: expected exactly ONE pfin decrypt view, found %s.', v_n),
      detail  = 'The final database carries exactly one: pfin.decrypted_source_credential. 015 drops 007''s. A second one means a stale 007 view survived a mixed history — which is the case this leg exists to catch.';
  end if;

  select pg_catalog.pg_get_userbyid(c.relowner),
         (select option_value from pg_catalog.pg_options_to_table(c.reloptions) where option_name = 'security_invoker')
    into v_owner, v_inv
    from pg_catalog.pg_class c join pg_catalog.pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'pfin' and c.relname = 'decrypted_source_credential';

  if v_owner is distinct from 'pfin_owner' then
    raise exception using errcode = '55000',
      message = format('ADR-072 (iv‴) post-step FAILED: pfin.decrypted_source_credential is owned by %s, expected pfin_owner.', coalesce(v_owner,'(absent)'));
  end if;
  if v_inv is distinct from 'true' then
    raise exception using errcode = '55000',
      message = format('ADR-072 (iv‴) post-step FAILED: pfin.decrypted_source_credential has security_invoker = %s, expected true.', coalesce(v_inv,'(unset)')),
      detail  = 'Without it the view executes as its vault-less owner pfin_owner and is broken — measured.';
  end if;

  raise notice 'ADR-072 (iv‴) post-step OK: exactly one decrypt view, named decrypted_source_credential, owned by pfin_owner, security_invoker = true.';
end
$verify$;
