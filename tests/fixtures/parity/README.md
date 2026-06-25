# `tests/fixtures/parity/` — RT-15 parity-fixture access-control governance

**Status:** Phase 5 Step 4 W3-A — scaffold-independent slice. **Sec-consult-mandatory** (this
README is the review hook). DB-load half (ephemeral Supabase `pfin.*` seed) is **HELD** pending
the `supabase/` project-scaffold ownership/sequencing decision routed to F/CTO.

This file is the **central governance surface** for the `pfin_back_etl` parity fixture
(RT-15 — *§3.3 parity-fixture test-environment RLS posture*). It defines **what a parity
fixture MAY and MUST NOT contain**, **where fixture artifacts live**, and **who may read
them**. The fixture payloads consumed by the pytest suite are **co-located with their
consumer** at `workers/etl/tests/fixtures/replay/` (pytest discovery + `conftest` live
there); this README governs them by reference. See *Artifact locations* below.

## Why RT-15 needs a parity fixture

`pfin_back_etl` (now in-repo at `workers/etl/` post-W0) is a production Python ETL ingesting
**BLS** (CPI) + **FMP** (equity financials) data into Supabase. Its integration test tier
(`workers/etl/tests/test_dbase_setup.py` + `test_dbase_update.py`) currently:

- connects to a **real** Supabase via `.env` creds and `pytest.skip`s when they are absent
  (`conftest.py` `backend` fixture), and
- calls `update_table_*` methods that hit **live** BLS + FMP HTTP endpoints.

That is non-deterministic and untestable in CI without production credentials. **The RT-15
parity fixture makes the ETL testable without production data** by (1) record-replaying the
external HTTP responses (no live API, no API keys) and (2) seeding an ephemeral Supabase with
**synthetic, production-shape** data (no production rows). Without it the ETL is a black box
that ships untested.

## What a parity fixture MUST NOT contain — fail-closed list

Per SECURITY §4.5 + ARCH §3 (e)/§4.6 (*"fixture artifacts themselves are stored under
access-controlled paths"*) + the QA agent-def parity-fixture posture. **No production data
enters any test environment. Ever.** Specifically, the following classes are **never** present
in any file under the parity-fixture surface — they are mocked or replaced with synthetic
equivalents:

| Banned class | §10 ref | Why | Synthetic substitute |
|---|---|---|---|
| Plaid access tokens / Item secrets | **SD-03** (credential) | Production Plaid credential | omitted entirely; Plaid surface is not in the ETL fixture |
| Real account numbers | **SD-15** | masked-only even in prod; never in CI | synthetic non-routable digits if a value is structurally required |
| PII / owner identity / IRS-FTB ledger state | **SD-09 / SD-11** | real owner-financial data | synthetic tenant identities only |
| Real DB connection creds (`PFIN_DB_*`) | — | production Supabase access | record-replay needs **no** DB creds; ephemeral DB uses throwaway local creds |
| Real BLS / FMP API keys (`BLS_API_KEY` / `FMP_API_KEY`) | — | production API credentials | record-replay needs **no** API keys |
| Real user-financial rows (`pfin.account` / `account_trans` / `account_users` / `nav` / `user_profile`) | SD-00 family | production balances/holdings | synthetic two-tenant rows only, when the DB-half lands |

The market-data tables the ETL writes (`pfin.cpi` / `eod_price` / `income_statement` /
`balance_sheet_statement` / `cash_flow_statement` / `earning` / `equity_profile` /
`reporting_period`) hold **public** market data, not user-financial data — so synthetic
equivalents here are *production-shape* without being *production-sensitive*. The discipline
above still applies: the **user-financial** `pfin.*` tables (when seeded for the DB-half) get
synthetic two-tenant rows only.

## Determinism discipline

- **Fixtures are deterministic.** No live API calls, no clocks, no random seeds. A replay
  payload is a frozen, checked-in JSON artifact; the same input always produces the same
  assertion outcome. Flakiness is a bug in the fixture, not a runner quirk.
- **Record-replay, not live-sandbox**, for BLS + FMP: the external HTTP response is recorded
  once (synthetically, from `conftest.py` sample shapes — see below) and replayed. The
  external-service-internal-state surface is isolated from the assertion surface.
- **No production response is ever recorded into a fixture.** Replay payloads are authored
  from the synthetic sample shapes already in `workers/etl/tests/conftest.py`
  (`sample_fmp_income_json` / `sample_fmp_profile_json` / `sample_bls_cpi_json`), grown to
  production *shape* (column set, nesting) — never copied from a live call against production
  keys.

> **Plaid note (forward-looking):** when Backend extends to a Plaid endpoint, Plaid sandbox
> tier sometimes drifts on its own internal state. Per the QA agent-def, Plaid endpoint tests
> use **record-replay of sandbox responses** with the Plaid-internal-state surface isolated
> from the assertion surface. That posture is **not** in scope for the ETL parity fixture
> (the ETL has no Plaid surface) and is tracked separately.

## Artifact locations + access control

| Artifact | Location | Access posture |
|---|---|---|
| This governance README | `tests/fixtures/parity/README.md` (central) | repo-readable; **Sec-review-bound** for any change to the MUST-NOT list |
| Replay payloads (BLS/FMP synthetic JSON) | `workers/etl/tests/fixtures/replay/` (co-located w/ pytest consumer) | repo-readable; synthetic-only by this README's discipline |
| Synthetic DB seed (`pfin.*` production-shape) | `supabase/seed.test.sql` — **HELD** (needs scaffold) | local/ephemeral only; never points at a production project ref |

**Access-controlled-path discipline:** parity fixtures are **never runtime-loadable in any
production container** — mirroring the `tests/fixtures/ci/` posture. The isolation has **two
tiers** depending on where the artifact sits relative to the Coolify **Base Directory**:

- **Repo-root `tests/fixtures/parity/`** (this governance README) — isolated **structurally,
  not convention-maintained**. Per ADR-019 each production container's build context is scoped
  by Coolify **Base Directory** (`workers/etl/`, `workers/pdf-render/`, …); the repo-root
  `tests/fixtures/` tree sits *outside* every per-container Base Directory by construction, so
  it is unreachable in any production build context regardless of any ignore file.

- **Co-located `workers/etl/tests/fixtures/replay/`** (the consumed payloads) — these sit
  *inside* the ETL Base Directory (`workers/etl/`), so Base-Directory scoping does **not** on
  its own exclude them. Their isolation is: (1) the ETL `Dockerfile` uses **selective `COPY`**
  (`COPY src/`, `main.py`, `mini.py`, `pyproject.toml`, `uv.lock` — **never `COPY tests/`**) —
  this is the real **structural backstop**; plus (2) `.dockerignore` excludes `tests/` — a
  **convention** that defends the build context as a second layer. The selective-COPY backstop
  holds even if the `.dockerignore` entry were removed; the two are belt-and-suspenders.

## What is HELD (not in this slice)

Per the Phase 5 Step 4 W3 dependency split, the following are **held** until the `supabase/`
project scaffold + sequencing decision lands (routed to F/CTO):

- The **DB-half** of the parity fixture: `supabase/seed.test.sql` synthetic `pfin.*` seed +
  the `supabase` CLI ephemeral-instance spin-up + DevOps CI wiring.
- The **two-tenant RLS-isolation harness** + the **per-Wave RLS verification battery
  framework** (pgTAP via `supabase test`, per the confirmed framework-shape decision).
- All **schema-exercising** cases (SD-15 `fn_mask_acct_number` etc.) — synced after W2 lands.

This slice delivers: this governance README + the synthetic record-replay payloads + the
record-replay loader for the ETL integration tier (deterministic, offline, zero production
creds).

### Held-item note — MUST-NOT enumeration to extend with the DB-half (Phase 6)

When the DB-half lands (synthetic `pfin.*` seed, post-scaffold), the MUST-NOT fail-closed
table above gains explicit rows for the user-financial classes that enter the fixture at that
point but are not in the incumbent ETL surface:

- **SD-12** — `pfin.monthly_report` + `monthly_report_account_snapshot` (HIGH; tenant-scoped
  derivative).
- **SD-16** — `pfin.reconciliation_event` (HIGH).

Both are **already covered today** by the general *"user-financial `pfin.*` → synthetic
two-tenant rows only"* principle in the MUST-NOT table; explicit rows are added when those
surfaces actually enter the fixture, so the enumeration stays exhaustive at that grain. (Per
Sec posture review NOTE 2 — forward-pointer, not a present gap.)
