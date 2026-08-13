---
name: feedback-scratch-db-pgtap-harness-gotchas
description: Mechanical gotchas building a from-scratch pgTAP verification DB (docker exec -i, pgtap schema placement, permissive-direction privilege gap) — hit all three authoring the SELF-218 battery verification, 2026-08-12.
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
