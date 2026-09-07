-- tests/fixtures/ci/c3-set-config-violation.sql
--
-- Golden violation fixture for scripts/ci/fence-set-config-non-literal.sh
-- (Sec C3). Applied ONLY on a disposable scratch clone in CI's inversion
-- step (security-scan.yml, job fence-set-config) — never on a real
-- database. This is exactly the shape the fence exists to catch: an
-- authenticated-EXECUTE function in a PostgREST-exposed schema (pfin) that
-- calls set_config() with a NON-LITERAL first argument — a parameter the
-- caller controls. If this shape existed for real, an ordinary
-- authenticated user could invoke it over the Data API to set an arbitrary
-- transaction-local GUC, including app.nav_computed_for (054/107) or the
-- forward-looking app.report_generation_source (111) — spoofing the
-- trust-boundary those trigger/audit checks derive from, with no RLS
-- violation anywhere in the picture.
--
-- The fence's own header names this precisely: it CATCHES THE SETTER,
-- which is the point — 054/107/111 only ever READ these GUCs; this fixture
-- plays the role of the (currently nonexistent) function that could SET
-- one under caller control.

create or replace function pfin.__c3_fixture_guc_spoof(p_guc_name text, p_guc_value text)
returns void
language plpgsql
security invoker
as $$
begin
  -- The violation: p_guc_name is a caller-supplied parameter, not a
  -- string literal. An ordinary authenticated caller picks the GUC NAME,
  -- not just its value.
  perform set_config(p_guc_name, p_guc_value, true);
end;
$$;

grant execute on function pfin.__c3_fixture_guc_spoof(text, text) to authenticated;

-- Second golden case (Sec FLAG, 2026-09-06): the SAME violation shape, but
-- authored as a PG14+ SQL-standard-body function (`language sql begin
-- atomic ... end`) instead of the traditional `AS $$ ... $$` string body.
-- This shape stores its source in `prosqlbody`, NOT `pg_proc.prosrc` —
-- `prosrc` is NULL for it. Before the fence's FLAG fix, `regexp_replace`
-- and `~*` over a NULL prosrc both evaluate to NULL (not false), and the
-- fence's own filter treated that as EXCLUDE rather than FLAG — a silent
-- pass on exactly this function class. The fence now scans
-- `coalesce(p.prosrc, pg_get_functiondef(p.oid))`, which renders this
-- body back into text; this fixture is the standing proof that path is
-- live, not merely written.
create or replace function pfin.__c3_fixture_guc_spoof_sqlbody(p_guc_name text, p_guc_value text)
returns void
language sql
begin atomic
  select set_config(p_guc_name, p_guc_value, true);
end;

grant execute on function pfin.__c3_fixture_guc_spoof_sqlbody(text, text) to authenticated;
