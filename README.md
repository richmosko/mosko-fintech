# mosko-fintech

A personal fintech app — multi-user by construction, run as a mini-business by a solo Founder/CTO with a synthetic agent team. It aggregates financial accounts (Plaid primary, SimpleFIN secondary), computes net worth, cash flow, allocation, and tax views over per-user data, and ships on a self-hosted stack.

Private repo. Not accepting external contributions.

## Layout

| Path | What lives there |
|---|---|
| `api/` | SvelteKit web app — UI plus the server-source surfaces (RLS-trusting, per the SECURITY §4.1 allowlist) |
| `workers/` | Background workers: `etl/` (Python ingest — BLS, FMP, Plaid), `pdf-render/` (Node, zero-DB by design), `provider-sync/` |
| `supabase/` | Migrations (the only way schema changes) and pgTAP test batteries |
| `tests/` | Cross-cutting test fixtures and verification batteries (two-tenant RLS posture) |
| `docs/` | Canonical product/architecture/security docs as HTML (`PRD/`, `ARCH/`, `SECURITY/`, `DESIGN/`) plus operational runbooks |
| `scripts/` | Dev and CI helper scripts |

## Where to orient

Everything here is pointer, not content — these stay canonical so this file can stay short:

- **`CLAUDE.md`** — project conventions and the read-first map (agents and humans alike).
- **`WORKFLOW.md`** — how the project operates: phases, agent roster, artifact ownership.
- **`MILESTONES.md`** — current phase, active feature, recent activity. The live state ledger.
- **`DECISIONS.md`** — ADRs: what was chosen and why.
- **`BACKLOG.md`** — deferred candidates (§5) and the V1 staging queue (§7).

## Running locally

See **`docs/local-dev.md`** for the local run (app + workers + local Supabase), and the per-directory READMEs (`api/`, `workers/etl/`) for surface-specific setup. Secrets live in gitignored `.env` files — see the per-surface `.env.example` files and `secrets-manifest.yml` for which secret belongs to which store. Nothing sensitive is committed.

## Ground rules

- Stack: SvelteKit + Supabase (Postgres with RLS as the tenant-isolation primitive) + Python/Node workers, deployed via Coolify.
- Migrations live in `supabase/migrations/`, never applied by hand in a dashboard.
- `main` is branch-protected; everything merges by PR through CI.
