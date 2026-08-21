---
name: reference-postgrest-two-tenant-vitest-pattern
description: Reusable recipe for a REAL (non-mocked) two-tenant RLS integration test at the TS query-module layer — built for SELF-238 AC9, will recur for SELF-240 (same subcatMarketValue.ts consumer) and any future query module that merges multiple RLS-scoped reads in TS
metadata:
  type: reference
---

When a query module (e.g. `api/src/lib/server/queries/*.ts`) composes MULTIPLE
independently-RLS'd Supabase reads and merges them in TS (`new Map()` +
reduce/lookup logic), neither a mocked Vitest test (the house's existing
`*.io.test.ts` convention — proves wiring, not isolation, since a mock never
enforces RLS and can't fail closed) nor a pgTAP battery on the underlying
tables (proves the SQL layer, not the TS merge) can prove tenant B's render
contains none of tenant A's values. Only a real end-to-end call through the
actual function, against a real RLS-enforcing backend, with two real tenant
sessions, can.

**The recipe** (drafted for SELF-238's `loadNonReAllocation`; RUN END-TO-END FOR REAL for the
first time at the SELF-330 merge gate, 2026-08-21 — 5/5 green. Everything below reflects what
actually worked, not the original draft):

1. A throwaway PostgREST container (`public.ecr.aws/supabase/postgrest:v14.12`
   — same image the real stack uses) pointed at a **dedicated** scratch DB —
   fastest route: `create database scratch_xxx template scratch_yyy` from an
   already-migrated scratch DB (seconds, no manual migration replay; the
   auth-schema-ownership wall hit when trying to build a fresh DB from empty
   — see `feedback_documenting_a_caution_is_not_applying_it`'s sibling
   incident — doesn't apply to TEMPLATE cloning, only to hand-rolling `auth`
   from a `pg_dump`). Env: `PGRST_DB_URI=postgresql://postgres:postgres@
   <db-container-name>:5432/<db>` (same docker network as the DB container —
   `docker inspect <db-container> --format '{{range $k,$v :=
   .NetworkSettings.Networks}}{{$k}}{{end}}'` to find it), `PGRST_DB_SCHEMAS=
   pfin,public`, `PGRST_DB_ANON_ROLE=anon`, `PGRST_JWT_SECRET=<test-only
   secret, never reused>`. ⚠ The seed SQL for the venue's DB must be applied
   **without** `begin;...rollback;` — unlike every pgTAP battery, this data
   has to survive into a LATER, separate vitest process making real HTTP
   calls. Stop the PostgREST container before dropping/rebuilding its backing
   DB (it holds open connections that block `DROP DATABASE`).
2. **`@supabase/supabase-js`'s high-level `createClient()` hardcodes a
   `/rest/v1` prefix** (the Supabase-gateway/Kong convention) that bare
   PostgREST doesn't understand — symptom: `PGRST125 "Invalid path specified
   in request URL"`. Fix: a ~15-line Node `http` module reverse proxy
   stripping `/rest/v1` before forwarding — no new dependency.
3. Mint per-tenant JWTs with `jose` (already a dependency in `api/`):
   `{ sub: tenantUuid, role: 'authenticated' }`, HS256, signed with the same
   secret as step 1. Pass as a static `Authorization` header via
   `createClient(url, 'unused-anon-key', { global: { headers: {
   Authorization: \`Bearer ${jwt}\` } } })` — this is how a request-scoped
   client is faithfully reconstructed without needing GoTrue at all.
4. Call the REAL query-module function directly (not through a route) with
   two such clients, one per tenant.
5. **The blunt "contains none of" check must be scoped to VALUES, not
   labels.** Flattening every field (including `cat`/`sub_cat` taxonomy text)
   into one "must not overlap" set produces a false positive: two tenants
   BOTH legitimately holding a "Cash/CD" Sub-Cat is correct, not a leak.
   Scope the comprehensive check to financial VALUES (dollar/pct fields,
   totals); check identifying IDs (`sub_cat_id`) separately and explicitly.
6. Gate the whole suite behind two env vars (`describe.skipIf`), skipping
   (exit 0) when absent — this codebase's CI has no PostgREST leg today, and
   standing one up is a DevOps call, not something to force silently via an
   always-on test.
7. **Never write into a teammate's worktree to verify against their
   uncommitted branch** ([[feedback_never_write_into_a_teammates_worktree]]).
   Temporarily overlay their new/changed source files into YOUR OWN worktree,
   verify there, then fully restore (`git status`/`git diff` clean) before
   handing off. `git -C <their-worktree> show <branch>:<path>` reads their
   content without touching their tree at all. Plain `cp` from their worktree
   path works too and is simpler when several files need overlaying at once.
8. **Two fixture-authoring gotchas, both measured for real building the
   SELF-330 AC9 seed, neither obvious in advance:**
   - An **investment account with securities but no offsetting cash
     checkpoint** goes NEGATIVE by its own buy total, and that negative cash
     is real — it gets classified into the Cash group same as any other
     balance, silently corrupting that group's total (measured: Cash read
     -1065.00 instead of +300.00). Fund every investment account's checkpoint
     to net EXACTLY zero cash (checkpoint = sum of its own buys) unless the
     fixture actually wants it to carry cash.
   - The **"contains none of the other tenant's values" check catches
     collisions in EVERY flattened field, not just the obvious dollar
     amounts** — a `planning_target.target_percent` picked without checking
     it against the OTHER tenant's percentages produced a real two-directional
     leak report on an otherwise-correct fixture (`[15]` present in both). Pick
     every number in a two-tenant fixture — dollars, percentages, anything the
     test's flattening function collects — from two DISJOINT sets, checked
     explicitly, not assumed distinct because the dollar amounts already are.

**Why:** SELF-238's AC9 ("tenant B's render contains zero of tenant A's
values… no service_role anywhere in the path") could not be discharged by
either of the two existing test shapes in this codebase — team-lead's own
framing ("two Maps merged in one process is exactly where a leak would be
invisible to RLS") is the generalizable trigger: any FUTURE query module with
the same shape (SELF-240 reuses the SAME `subcatMarketValue.ts` — likely
needs the identical pattern) should reach for this recipe rather than
re-deriving it from scratch or defaulting to a mock.

**How to apply:** When a new/changed query module merges ≥2 independently-RLS'd
reads in TS and its AC calls for a two-tenant proof, use this recipe. Don't
apply it reflexively to modules with only ONE read (076-style single-RPC
callers) — that case is fully covered by the RPC's own pgTAP battery already.
