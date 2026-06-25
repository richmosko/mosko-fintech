# `workers/` — scoped context for Claude Code

> **Per-directory `CLAUDE.md`** (WORKFLOW.md Phase 5 Step 5). Scoped conventions for working inside `workers/`. The root [`CLAUDE.md`](../CLAUDE.md) + canonical artifacts ([ARCH](../docs/ARCH/index.html) · [SECURITY](../docs/SECURITY/index.html) · [DECISIONS](../DECISIONS.md)) stay source-of-truth; this file is the surface-local quick reference.

**Owner role:** Backend Engineer. Per WORKFLOW.md Agent Roster.

## What lives here

Two of the three V1 background-worker containers (the third is the V1 web-app in `api/`) per [ADR-011](../DECISIONS.md#adr-011) Decision 17 / Lock 13's hybrid 3-container runtime topology on Hetzner cax21:

- **`workers/etl/`** — `pfin_back_etl` Python ETL (BLS CPI + FMP financials ingestion → Supabase). Folded into the monorepo from the former sibling repo per [ADR-019](../DECISIONS.md#adr-019); the `github.com/richmosko/pfin_back_etl` repo is archived. Source package is `pfin_back_etl` under `src/`; deployed as a Coolify container with **Base Directory** `workers/etl/`.
- **`workers/pdf-render/`** — Node/Puppeteer PDF worker (Lock 13 mod #2). Currently a placeholder `Dockerfile`; Backend extends with the Puppeteer + Node app code at Wave 6.

Dockerfiles are **DevOps-owned** — do not edit them here; flag changes to DevOps.

## Conventions

- **ETL Python** (`workers/etl/`): `uv` + `pyproject.toml` dependency management (Python ≥3.14); **ruff** lint/format; **pytest** with marker discipline (`unit` / `integration` / `deployment` / `replay` — `--strict-markers`). Polars for dataframes; `psycopg2-binary` + SQLAlchemy for DB. Replay-parity fixtures live in `workers/etl/tests/` (`test_replay_parity.py`, `conftest.py`, `fixtures/`).
- **TenantBoundConnection (TBC)** ([Lock 13 mod #3](../DECISIONS.md#adr-011)): ANY worker code touching `pfin` constructs DB connections through the TBC wrapper — binds `users_id` at construction, asserts every query's WHERE clause carries that `users_id`. Raw `psycopg.connect()` / `psycopg2.connect()` is a **CI fence violation**. The `fence-tbc` job (production-mode + inversion-mode in one job per [ADR-019](../DECISIONS.md#adr-019) sub-decision 2) greps `workers/etl/` on every PR. **If it fires, fix at source** — never work around the fence.
- **Same-transaction audit-log**: every state-changing write to `pfin` emits its audit-log row in the **same transaction** as the state change. No retry queues, no separate transactions, no fire-and-forget. (TypeScript-side analogue lives in `api/`; the discipline is identical.)
- **Cron via Coolify**: scheduled work (the `pfin_back_etl` poll; the Wave 6 `monthly_report` cron per Gate F) runs as **native Coolify cron containers**, not an in-app scheduler. Failure/health notifications route to **Discord** (incumbent Coolify→Discord routing on cax21). Worker-scheduling decisions route to DevOps.
- **Plaid SDK** (worker side) lives in `workers/etl/`; sandbox tier in V1.0, production tier post-`SELF-212` (F/CTO-gated). New Plaid endpoints need QA sandbox-fixture coverage.

## Canonical references

- [ADR-019](../DECISIONS.md#adr-019) — monorepo consolidation; `pfin_back_etl` source now at `workers/etl/`; single-PR CI shape (paired-PR pattern retired).
- [ADR-011](../DECISIONS.md#adr-011) Decision 17 / Lock 13 — hybrid 3-container topology + full mod inventory (#1–#10).
- [ADR-011](../DECISIONS.md#adr-011) Decision 4 — §10 defense-in-depth ledger (RT-22 infra-credential-presence layer; TBC at the Privileged-context-surfaces bullet — **explicitly not a catalogued §10 instance**).
- [SECURITY §4.5](../docs/SECURITY/index.html#sec-4-5) — RT-15 parity-fixture posture + RT-22 PDF-worker Dockerfile credential-absence audit.
- `reference_pfin_back_etl` (memory) — production ETL background.

## Fail-closed / gotchas

- **The PDF worker has ZERO database access by design** ([Lock 13 mod #2](../DECISIONS.md#adr-011)). Do **not** add `psycopg` / `psycopg2` / `asyncpg` / `pg` / `node-postgres` / `supabase-py` to `workers/pdf-render/` deps — even for "logging." It reaches the data layer ONLY via the V1 web-app's `/internal/pdf-render` endpoint under a short-lived signed JWT (Lock 13 mod #1). **TBC does NOT apply to `pdf-render`** — that's a category error. The DB-isolation guarantee there is enforced by **RT-22**, an *infrastructure-credential-presence* audit on the Dockerfile (a §10 catalogued instance) — do not conflate it with the code-layer TBC fence on `workers/etl/`.
- **ETL CI coverage is a tracked follow-up, not yet wired** — ruff + pytest + uv-aware dep-vuln audit are not yet in CI for `workers/etl/`. `test_replay_parity.py` is the first-green target. Don't assume green CI here implies lint/test enforcement until that lands (route to DevOps).
- Any new cross-tenant FK reference is a [Decision 3](../DECISIONS.md#adr-011) family instance (7 catalogued at Phase 4 close) — Sec-consult + ARCH §10 ledger update required, even when the parent FK "feels safe" because it's RLS-protected.
- New `SECURITY DEFINER` need → route to Architect + Sec. Migrations are Architect-owned; `workers/` consumes them, does not author them.
