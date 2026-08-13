---
name: rls-qual-privilege-semantics
description: RLS policy quals invoke functions by stored OID — schema USAGE is never re-checked, only EXECUTE is; and a test harness missing the bootstrap's REVOKEs is more permissive than prod
metadata:
  type: reference
---

**Postgres semantics, established empirically by QA on 2026-08-12** (minimal repro on
a throwaway DB, not inferred): schema `USAGE` is a **parse-time name-resolution**
check. It is not re-checked when an already-parsed expression is evaluated.

- `CREATE POLICY` runs as the policy's creator (here `postgres`), resolving
  `auth.uid()` to an OID **once**, and stores that in the compiled qual.
- Every later evaluation of that qual — under any querying role — invokes the
  function **by OID**. Only `EXECUTE` on that specific function is checked. Schema
  `USAGE` never is.
- A **freshly typed** `auth.uid()` in a query's own SQL is parsed under the current
  role and **does** require schema `USAGE` to resolve the qualified name.

Discriminating repro: same role, same session — `SET ROLE authenticated; SELECT
auth.uid();` → `permission denied for schema auth`, while querying a table whose RLS
policy references `auth.uid()` **succeeds and filters correctly**.

**Why this is worth keeping:** it predicts which surfaces break when schema ACLs are
missing, and the prediction held across `062`/`063`/`054`/`058` (each types
`auth.uid()` directly in test SQL) versus `067`'s battery (never does — every tenant
check runs through the policies it exercises).

**How to apply:**
- When reasoning about whether a role can reach an RLS-fenced surface, do **not**
  infer from schema-level ACLs. The policy path and the direct-call path have
  different privilege requirements, and they can disagree in the same session.
- ⚠ **The security-relevant corollary, which is easy to miss.** In that scratch DB
  `auth.uid()`'s `pg_proc.proacl` was **NULL**, so EXECUTE fell back to Postgres's
  default — granted to PUBLIC — because `pg_dump --no-privileges` dropped the
  `REVOKE ALL FROM PUBLIC` the real Supabase bootstrap issues. **A harness built that
  way is MORE PERMISSIVE than production**, which is the dangerous direction: a leg
  asserting something is *denied* can pass vacuously because the denial was never
  installed.
- **A harness fix that only restores GRANTs is incomplete in the same direction it
  went wrong.** Mirroring a bootstrap means reproducing what it *takes away*, not
  only what it hands out.
- Corollary for migration authorship: an explicit `revoke execute … from public`
  in the migration makes that function's ACL independent of inherited defaults, so
  its assertions stay meaningful even in a permissive harness. `067` does this; it is
  why its ACL legs were not vacuous when six other batteries were affected.

Related: [[fixture-is-shared-state]]
