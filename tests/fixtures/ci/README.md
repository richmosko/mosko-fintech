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
| `rt26-violation/+page.svelte` | RT-26 `SUPABASE_SERVICE_ROLE_KEY` allowlist | Client-side Svelte page in routes-tree-shape path referencing the env var; path is NOT on the ADR-016 D1 allowlist registry. |
| `tbc-violation.py` | TBC `TenantBoundConnection` grep | Raw `psycopg2.connect()` invocations outside the `TenantBoundConnection` class. |

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

### `pfin_back_etl` repo (paired-PR responsibility)

Per the α paired-PR shape (per F/CTO ratify 2026-06-08), `pfin_back_etl` repo
vendors `tbc-violation.py` (literal copy). That repo's paired PR is responsible
for excluding `tests/fixtures/` from:

- `.dockerignore` (production build context).
- `pyproject.toml` / `setup.py` `packages` declaration (Python module
  discovery).
- `__pycache__` cleanup (no compiled bytecode in production).

See `scripts/ci/README.md` § Cross-repo TBC posture for the full paired-PR file
map + isolation requirements.

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
