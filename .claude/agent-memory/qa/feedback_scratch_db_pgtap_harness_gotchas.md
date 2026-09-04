---
name: feedback-scratch-db-pgtap-harness-gotchas
description: Mechanical gotchas building a from-scratch pgTAP verification DB (docker exec -i, pgtap schema placement, permissive-direction privilege gap, pg_prove -v mount path, \'-escaping, psql :'var' inside do $$ $$, pg_catalog.coalesce, multi-unknown-literal UDF calls) — hit all three authoring the SELF-218 battery verification, 2026-08-12; #5 added SELF-245, 2026-08-25; #6 added SELF-248, 2026-08-25; #7 added SELF-250, 2026-08-26; #8/#9 added SELF-259, 2026-09-03.
metadata:
  type: feedback
---

Building a throwaway scratch database (new DB on the same running local Postgres
cluster, migrations applied fresh, `pg_prove` run against it, DB dropped) is the
sanctioned way to verify a pgTAP battery without touching F/CTO's real local dev
data. Three non-obvious failure modes cost real time on first use (SELF-218 / `067`
verification, 2026-08-12):

1. **`docker exec` silently no-ops on stdin without `-i`.** `docker exec container
   psql ... <<'EOF' ... EOF` (heredoc) or `psql ... < file.sql` against the
   container connects nothing to the process's stdin unless `-i` is passed —
   the command exits 0 having executed nothing. This produced a false "extensions
   ok" twice before being caught (verified by re-running each block with explicit
   `-c` flags and checking output). Always use `docker exec -i` for anything
   piping SQL into a containerized `psql`.

2. **pgTAP must be installed in the `public` schema, not `extensions`.** The
   `postgres` role has a role-level `search_path` override
   (`"$user", public, extensions`) that no other role (`authenticated`, `anon`,
   `service_role`) carries. `SET ROLE` / `set_config('role', ..., true)` DOES
   apply the target role's own role-level GUC settings, so after a test file
   switches to `authenticated`, pgTAP functions (`is`, `ok`, `plan`, ...)
   installed in `extensions` become invisible ("function is(...) does not
   exist") the moment any test does its tenant-switch. `public` is in every
   role's default search_path — install pgTAP there:
   `create extension pgtap schema public;`. [[reference_local_dev_run]]

3. **⚠ THE HARNESS IS PERMISSIVE IN THE DANGEROUS DIRECTION, not just incomplete.**
   Mirroring `auth` for FK purposes via `pg_dump --schema=auth --schema-only
   --no-privileges` drops BOTH the grants (`GRANT USAGE ON SCHEMA auth TO
   anon, authenticated, ...`) AND the revokes (`REVOKE ALL ... FROM PUBLIC`) the
   real bootstrap issues. Postgres's own default is PUBLIC EXECUTE on every
   newly created function unless explicitly revoked — so a function whose real
   posture is "denied to everyone except an explicit grant" reverts, in the
   scratch DB, to "allowed to everyone," silently. **Why: {an architect
   teammate pushed on my first (wrong) explanation for why one battery was
   unaffected by a related permission gap; the repro that resolved it also
   surfaced this — the fix I proposed (add the missing grants) would have
   restored the false-negative direction (a real fence reads as broken) while
   leaving the false-positive direction open (a fence reads as held when it
   was never installed) — the more dangerous one for a *verification*
   instrument specifically.} How to apply: if this harness gets reused, mirror
   BOTH halves of the real bootstrap's ACL posture (grants AND revokes) before
   trusting any privilege-denial assertion run against it, or flag privilege-
   denial legs as unverified by that harness until it does.**

Root cause of why RLS-embedded `auth.uid()` calls worked despite the missing
grants, while direct test-file calls to `auth.uid()` failed: schema `USAGE` is
checked only at NAME-RESOLUTION (parse) time. `CREATE POLICY` runs as a
superuser and resolves `auth.uid()` to its function OID once, at policy-creation
time; every later evaluation of that compiled qual — under any invoking role —
calls the function by OID and checks only EXECUTE (which defaulted to PUBLIC via
the missing revoke), never re-checking schema USAGE. A freshly-typed
`auth.uid()` in a test file's own SQL gets parsed fresh under the current role
and does need USAGE. Verified by direct repro (same role, same session: `SET
ROLE authenticated; SELECT auth.uid();` denied; querying a table whose RLS
policy references `auth.uid()` succeeds) — not inferred from the error message
alone. [[feedback_instrument_cannot_observe_the_property]]

4. **`CREATE DATABASE new TEMPLATE old` does NOT copy `pg_db_role_setting`
   (per-database `ALTER DATABASE ... SET param = value` GUC overrides).**
   `CREATE DATABASE ... TEMPLATE` clones the physical data files, but a
   database-level config override lives in `pg_db_role_setting`, keyed to the
   template database's own `pg_database` OID — that row is NOT part of what
   gets copied. Migration `061` pins `ALTER DATABASE current_database() SET
   TimeZone = 'UTC'` — dynamic, not hardcoded, so it applies correctly
   wherever it runs — but a scratch DB built by `CREATE DATABASE clone
   TEMPLATE already-migrated-scratch` (chaining clones instead of a genuine
   sequential `001..NNN` apply) inherits the DATA (a `pg_db_role_setting` row
   would exist for the row's own data if it were table data, but this isn't
   table data) with no `TimeZone=UTC` override, so `01_session_timezone.sql`'s
   (T2) MECHANISM leg fails there (`have: configuration file, want:
   database`) even though (T1) VALUE still reads UTC by coincidence (the
   container image default happens to already be UTC). Confirmed by direct
   query: `select datname, setconfig from pg_db_role_setting drs join
   pg_database d on d.oid = drs.setdatabase` — the template row has
   `{TimeZone=UTC}`, the clone has no row at all. This is a FALSE ALARM
   specific to template-cloning as a verification shortcut, not a real
   regression — a genuine fresh sequential migration apply (what a real CI
   run and what a "clean 001..NNN apply" scratch build both do) does not hit
   it. Only matters if `01_session_timezone.sql` or any other file asserting
   a per-database GUC override is in scope for a template-cloned run; harmless
   to every other file. [[feedback_pg_prove_scope_full_tests_tree_not_rls_only]]
   ⚠ **The direction it fails in is the part worth carrying (Architect's framing,
   confirmed jointly):** `pg_db_role_setting` is a shared catalog keyed by
   database OID, so a template clone gets a NEW OID and therefore NO row at
   all — a TEMPLATE clone is MORE PERMISSIVE than the real database on exactly
   the axis a migration like `061` exists to PIN. A test that only compared
   two timestamps would pass on the clone and tell you nothing; only a test
   that asserts the setting's SOURCE (like 01's T2) catches the gap. Usable
   rule: clone-to-save-time is fine for claims that read no per-database
   setting; anything touching timezone, JWT settings, or any `ALTER DATABASE
   ... SET` needs a real sequential chain apply, not a template clone.

5. **The `pg_prove` verification container is a SEPARATE `docker run`, not the same
   filesystem as the `supabase_db_*` container — a `-v` mount must name a real HOST
   path, not a path that only exists inside the OTHER container.** SELF-245, 2026-08-25:
   ran `docker cp <tests-dir> supabase_db_mosko-fintech:/tmp/self245_tests` (copying
   host files INTO the db container), then tried `docker run ... -v
   /tmp/self245_tests:/tests ... pg_prove` — mounting the HOST's (nonexistent)
   `/tmp/self245_tests`. `--network container:X` shares only the network namespace,
   not the mount namespace, so `pg_prove`'s own `docker run` never goes through
   `supabase_db`'s filesystem at all. Symptom was misleading: `pg_prove` errored
   `Cannot detect source of '<path>'!` — reads like the ALREADY-DOCUMENTED
   explicit-files-vs-directory-mode gotcha (see `rls_verbs.psql`'s own header), not a
   missing-mount one, and cost a wasted retry in that wrong direction first. Diagnosed
   by `docker run --entrypoint sh ... -v <path>:/tests -- ls /tests/...` — empty/
   absent, confirming the mount itself was the problem. Fix: point `-v` at the actual
   host path (`$HOME/Projects/.../supabase/tests:/tests`) directly — no `docker cp`
   into `supabase_db` needed for this step at all.
   ⚠ Recurred alongside gotcha #1 in the SAME session: `docker exec ... psql ...
   <<'EOF'` without `-i` silently no-op'd on `create extension` — confirmed via
   `pg_extension` showing only `plpgsql` after a "successful" (exit 0) run; re-ran with
   `-i` and it worked. Both are the same root lesson: never trust a "success" exit code
   from a container/mount boundary — independently verify the thing on the far side
   actually exists (`ls` the mount, `select extname from pg_extension` the load)
   before building on top of it.

6. **A backslash-escaped quote (`\'`) inside a plain (non-`E`-prefixed) SQL string
   literal is NOT a valid escape and breaks the statement, not just the string.**
   Wrote a pgTAP description literal containing `(Sec (C\'\'))` — meant as
   `(Sec (C''))`, the double-prime label from a Sec doc. Standard SQL escapes an
   embedded quote by DOUBLING it (`''`), not backslash-escaping; `\'` is only special
   inside an `E'...'`-prefixed string. psql saw the backslash as a literal character,
   the FIRST unescaped `'` ended the string early, and the leftover `''))'` was parsed
   as a stray command — `pg_prove` reported `error: invalid command \'))'` at the
   line, which reads like a mount/file problem (matches gotcha #5's symptom class)
   but is a plain SQL-quoting bug in the test file itself, caught only by actually
   running it through pg_prove (never `psql` — SELF-298's own lesson generalizes:
   both a plan-count check and a raw-SQL-syntax check need the real consumer, not eyes
   alone). Fix: never backslash-escape a quote in a plain string literal — double it,
   or (safer for a stylistic mark like a prime symbol) just spell it out in words
   ("C double-prime") and skip the quote entirely.

7. **psql does NOT interpolate `:'var'` / `:var` inside a `do $$ ... $$` body.**
   Wrote `do $$ declare v_idx text := :'indexname'; begin execute format('drop
   index pfin.%I', v_idx); end $$;` to invert a dynamically-discovered index
   (SELF-250, 2026-08-26) — reproducible in isolation with a two-line repro
   (`\gset` the var, `select :'var'` substitutes fine, the identical `:'var'`
   inside a `do $$ $$` two lines later throws `syntax error at or near ":"`,
   proving the variable WAS set correctly and the failure is specific to
   dollar-quoted bodies). Root cause: psql's colon-substitution is a dumb text
   scan that treats dollar-quoted content as opaque (the same reason it
   doesn't mangle a `::` cast or an array slice inside one) — it never fires
   inside `$$...$$` at all, isn't merely fooled by the dollar-quote delimiter.
   Fix: never reference a psql variable inside a `do $$ $$` body. Build the
   target statement as a plain SQL fragment via `format(...)` in an ordinary
   `select`, capture it with `\gset`, then execute it as a BARE (unquoted)
   psql variable — `select format('drop index pfin.%I', :'name') as dropsql
   \gset` then `:dropsql;` on its own line. The unquoted form substitutes the
   captured text as raw SQL outside any dollar-quoting, so it composes
   correctly with a following `savepoint` / `rollback to savepoint` pair for
   an index-drop inversion leg.

8. **`pg_catalog.coalesce(...)` (schema-qualified) does NOT exist and errors —
   `coalesce` is a special parser form, not a callable pg_catalog function.**
   Found this while testing `fn_tax_bracket_schedule_replace_all` (SELF-259,
   101): the migration's own p_rows-shape RAISE calls
   `pg_catalog.coalesce(pg_catalog.jsonb_typeof(p_rows), 'null')`. Every other
   `pg_catalog.*` call beside it (`jsonb_typeof`, `jsonb_array_elements`,
   `array_agg`, `jsonb_object_keys`) is a REAL function and schema-qualifies
   fine — only `coalesce` breaks, with `function pg_catalog.coalesce(text,
   unknown) does not exist`. Reproduced standalone: `select
   pg_catalog.coalesce('x'::text, 'y');` fails; `select coalesce('x'::text,
   'y');` works. `coalesce`/`case`/`nullif`/`greatest`/`least` are SQL
   special forms the parser recognizes by bare name only — explicit schema
   qualification routes them into ordinary function-call resolution, where no
   such catalog entry exists. This was a genuine BUG IN THE MIGRATION CODE
   (Architect's file, not mine to fix) that my battery caught and correctly
   left red rather than routing the assertion around it — never
   schema-qualify these five names, and treat a battery leg that surfaces one
   as a real finding, not something to weaken the assertion to match.

9. **A UDF call with several "unknown"-typed literal arguments AND a custom
   enum parameter can fail to resolve even with exactly one candidate
   function — cast every literal explicitly.** `select
   pfin.fn_tax_bracket_schedule_replace_all(999999999, 2026,
   'federal_ordinary', 10000.00, null, '[]'::jsonb)` against a function typed
   `(bigint, smallint, pfin.tax_schedule_type_enum, numeric, numeric, jsonb)`
   errored `function ... (integer, integer, unknown, numeric, unknown,
   jsonb) does not exist`, even though only one function of that name
   exists. Adding an explicit cast to EVERY literal argument
   (`999999999::bigint, 2026::smallint,
   'federal_ordinary'::pfin.tax_schedule_type_enum, 10000.00::numeric,
   null::numeric, '[]'::jsonb`) fixed it immediately — confirmed by isolated
   repro before touching the battery file. Root cause not fully chased (looks
   like Postgres's overload-resolution algorithm giving up when it can't
   simultaneously narrow several unknown literals across mixed type
   categories including a non-preferred custom enum), but the fix is cheap
   and mechanical: when calling a multi-arg pgTAP-tested function that mixes
   plain numerics, a custom enum, and jsonb, cast every literal, don't rely
   on implicit resolution — even for a signature with a single candidate.
