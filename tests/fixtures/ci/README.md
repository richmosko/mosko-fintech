# `tests/fixtures/ci/` — CI fence golden-test fixtures

This directory holds **deliberately violation-shaped** fixtures that the
`scripts/ci/fence-*.sh` scripts catch. Every CI fence ships with a paired fixture
here; the fence's CI inversion-mode check fails closed if the fence does NOT
report violation against the fixture (the fence is unverified/broken).

## §10 attribution discipline

Fixtures here are paired with mechanisms in `scripts/ci/`. The §10 catalogued-
instance ledger lives at ADR-011 Decision 4; this directory is **enforcement-
adjacent**, not a §10 attribution surface. See `scripts/ci/README.md` for the
§10 cross-reference. TBC is NOT a third catalogued §10 instance.

## Fixture inventory

| Fixture | Fence | Purpose |
|---|---|---|
| `rt22-violation.Dockerfile` | RT-22 PDF worker Dockerfile audit | Violates BOTH catch criteria (i) `SUPABASE_*` env vars + (ii) Postgres client install in a single fixture. |
| `rt22-manifest-violation/manifest-direct/` (`package.json` + `package-lock.json`) | RT-22 dependency-manifest fence (SELF-350 A6) | **Manifest-scan route.** `pg` is listed directly in `package.json`'s `dependencies` (alongside a plausible non-violating dep, `puppeteer-core`); the lockfile mirrors it as a direct `node_modules/pg` entry. Proves the fence's direct-manifest-scan path catches an explicit driver dependency. |
| `rt22-manifest-violation/lockfile-transitive/` (`package.json` + `package-lock.json`) | RT-22 dependency-manifest fence (SELF-350 A6) | **Lockfile-scan route.** `package.json` names only `knex` (a query-builder that bundles a Postgres driver) — `pg` never appears there. `package-lock.json`'s resolved tree (lockfileVersion 3 `packages` map) carries `pg` as `node_modules/knex`'s own `dependencies` entry, i.e. `pg` is visible ONLY in the lockfile. Proves the fence's lockfile-scan path — the route a manifest-only scan cannot see, per AC item 1's `knex`/`sequelize`-class clause. |
| `rt26-violation/+page.svelte` | RT-26 `SUPABASE_SERVICE_ROLE_KEY` allowlist | Client-side Svelte page in routes-tree-shape path referencing the env var; path is NOT on the ADR-016 D1 allowlist registry. |
| `tbc-violation.py` | TBC `TenantBoundConnection` grep | Raw `psycopg2.connect()` invocations outside the `TenantBoundConnection` class. |
| `tbc-node-violation.ts` | TBC-node `TenantBoundClient` grep | LEG 1: raw `postgres()` / `new Pool()` / `new Client()` + banned `@supabase/supabase-js` `createClient()`/import outside the `TenantBoundClient` class. LEG 2: a literal `SUPABASE_SERVICE_ROLE_KEY` reference (Sec-condition absence tripwire). Node/TS provider-sync analogue. |
| `tbc-basename-collision/` (`db/core.py` + `etl/core.py`) | TBC `TenantBoundConnection` grep | **Production-mode** regression for the `grep --exclude=<basename>` false-negative (Sec, 2026-07-17): class file + a same-basename violator in a different dir. Fence MUST exit 1 (violator caught via full-path exclusion). |
| `tbc-node-basename-collision/` (`db/client.ts` + `adapters/client.ts`) | TBC-node `TenantBoundClient` grep | **Production-mode** regression (Node twin): class file + same-basename violator elsewhere. Fence MUST exit 1. |
| `dedup-hash-drift-source.ts` + `dedup-hash-drift-copy.ts` | `dedup-hash-identical` import_hash drift fence (SELF-204 / ADR-034 D4) | **Inversion pair.** A golden stand-in source + a deliberately-diverged copy (`toLowerCase`→`toUpperCase`, the invisible-canonicalization-break class D4 fears). The fence regenerates from the source and diffs against the copy; they MUST differ so the fence exits 1 (a fence without a failing golden is theater, Sec 2026-07-27). Stand-ins, NOT the real `importHash.ts` module. |

## Fixture path discipline (Sec rubric (b)3 #2 + agent-def)

Every fixture here is deliberately **NEVER runtime-loadable in any production
container**:

### mosko-fintech repo (this repo)

- `.dockerignore` at repo root excludes `tests/fixtures/` from both V1 web-app
  and PDF worker build contexts.
- Fixtures are NOT inside `src/**`; SvelteKit won't auto-discover them as routes
  or pages.
- The fixtures are scoped to `tests/fixtures/ci/`; the wider `tests/` tree is
  also conventionally excluded from production builds.

### Stronger isolation post-W0 (Coolify Base Directory)

Per ADR-019 (Phase 5 Step 4 W0), `pfin_back_etl` was absorbed into this monorepo at
`workers/etl/`; the cross-repo **vendored-copy convention retires** — there is no
second repo to vendor `tbc-violation.py` into, and this directory is now the single
source of truth.

This is a **posture strengthening**, not a relaxation. Each production container's
build context is scoped by Coolify **Base Directory** (e.g. `workers/etl/` for the
ETL container, `workers/pdf-render/` for the PDF worker). The repo-root
`tests/fixtures/` tree sits *outside* every per-container Base Directory
by-construction, so no fixture is reachable in any production build context —
without relying on per-repo `.dockerignore` + `packages`-exclusion discipline the
way the retired paired-PR convention did. The isolation guarantee is now
**structural rather than convention-maintained**.

See `scripts/ci/README.md` § Single-repo TBC posture (post-W0) for the
consolidated CI restructure.

## Why fixtures violate verbatim, not via mocks

Per Sec rubric (b)1 flag: "Fixture file content uses a literal mock variable
name instead of `SUPABASE_SERVICE_ROLE_KEY` verbatim → flag (fence might match
by exact-string; fixture must trip the real regex)."

The fixtures in this directory reference the real env-var names + real client
names + real install verbs verbatim. A mock variable name would not exercise the
fence's actual pattern set; the fixture would be testing the fixture, not the
fence.

## DO NOT use these fixtures as templates

These fixtures intentionally embody anti-patterns. They exist to be **caught**,
not to be **followed**. Production code in V1 must:

- Use `PDF_WORKER_SIGNING_KEY` only (per SD-20) and NO `SUPABASE_*` env vars in
  the PDF worker container.
- Reference `SUPABASE_SERVICE_ROLE_KEY` ONLY in the three ADR-016 D1 allowlist
  surfaces (Plaid webhook handler + onboard + revoke).
- Use the `TenantBoundConnection` class as the only entry point for raw Postgres
  connections in `pfin_back_etl`.
