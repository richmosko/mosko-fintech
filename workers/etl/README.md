# (pfin-back-etl) Personal Finance Backend Extract/Transform/Load

## Description
This project consists of a set of backend scripts to extract data from external
APIs, and transform them to data formats that align with the overall PFin project
table structures in SupaBase.

## Some External Requirements
For this to work, this project will need a few external things set up:

### UV installation
This project (and all of the connected projects) uses uv as a python and package
manager. It's fast and pretty idiot proof... which is perfect for my skill level.
- macOS: `brew install uv`
- Linux: `curl -LsSf https://astral.sh/uv/install.sh | sh`
- Windows: `powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"`

### Environmental Variables
A `.env` file will need to get added to the project root directory `pfin_back_etl`.
This file contains environmental variables that the scripts use to define API Keys
and database connection variables. An example of this file sits in this
directory as `.env.example` with non-valid entries (Phase 5 Step 8: `.env.example`
supersedes the prior `sample.env`, matching the repo-wide `.env.example` convention).

**`.env.example` is the single source of truth for this contract — copy it, don't
copy a listing from here.** This README previously duplicated the variable block,
and the duplicate drifted: it carried `PFIN_DB_USER=<example::postgres.your_project_ref>`
(the Supabase-pooler username form for the schema **owner**) and
`PFIN_DB_HOST=<example::pfindash.com>` (the *incumbent* cax21 host, not the V1
greenfield target). Pasting either would have produced a worker running as the
`pfin` owner — which inverts every fence migration `054` depends on, since an owner
can `ALTER TABLE … DISABLE TRIGGER` and bypasses RLS by ownership. That placeholder
is what SELF-214's Sec joint-review (B1) was raised about; the duplicate here is
removed rather than re-synced so it cannot drift again.

```sh
cp .env.example .env      # then fill in the secrets
```

The DB login role is **`pfin_etl`** (dedicated, NOINHERIT; writes execute AS
`service_role` via `SET LOCAL ROLE` per ADR-023). See the `DB LOGIN ROLE` block in
`.env.example` for the full model, the two-step deploy-time credential handoff
(`\password` then `ALTER ROLE … LOGIN` — order is load-bearing, and the single
atomic `ALTER ROLE … WITH LOGIN PASSWORD` is prohibited), and the `42501` gotcha
that bites any new write path. Migration `055`'s header is canonical for the handoff.

### A Valid Financial Modeling Prep API Key
This is what I'm using as a stock financials data source. Other sources could work
perfectly well with some modification... but this is what I'm currently using. The
starter plan supplies most of the data for 2-years of historical data and a pretty
reasonable price. TBD: I should look at what kind of features should be disabled if
the free plan was used instead.
TBD: LINK_TO_FINANCIAL_MODELING_PREP_PLANS

### A BLS API Key
The U.S. Bureau of Labor & Statistics requires registration for an API key (free)
to query data about historical consumer price indexes.
TBD: LINK_TO_BLS_REGISTRATION

### A Running SupaBase Instance
This could be self-hosted or cloud hosted on supabase.com. Or a docker instance on
AWS, etc. The free hosting tier on supabase.com should be sufficient for the database
size and query load for this application. The connection information there
(shared pool) should be added to the `.env` file in the root directory
(see notes above).
TBD: LINK_TO_SUPABASE_SITE

### A Running pfin Schema on Your SupaBase Instance
This requires the pfin-dash project. It has the SQL Data Definition Language (DDL)
commands and migrations under revision control to execute to the postgresql database
on SupaBase.
TBD: Add a link to project and how to setup the database.

## Installation
1. Install uv (see above)
2. Clone the project
3. Navigate to your cloned repository: `cd <Project Directory>/pfin_back_etl`
4. Initialize uv and the environment: `uv sync`

## Testing

### Setup

Install the test dependencies:

```bash
uv sync --group test
```

This pulls in `pytest` and `pytest-cov` on top of the core project dependencies.

### Test Markers

Tests are organized into two tiers using pytest markers (configured in
`pyproject.toml` with `--strict-markers` enforced):

| Marker          | Description                                                    |
| --------------- | -------------------------------------------------------------- |
| `unit`          | Fast tests with no external dependencies (no DB, no API)       |
| `integration`   | Tests that require database and/or API connections             |

### Running Tests

```bash
# Run all tests
uv run pytest

# Run only unit tests (no credentials needed)
uv run pytest -m unit

# Run only integration tests (requires .env with valid credentials)
uv run pytest -m integration

# Run unit tests with coverage report
uv run pytest -m unit --cov=pfin_back_etl --cov-report=term-missing
```

### Test Structure

```
tests/
  conftest.py          # Shared fixtures (sample API responses, DataFrames)
  test_utils.py        # Unit tests for utility functions
  test_core.py         # Unit tests for core ETL classes (SBaseConn, PFinFMP)
  test_dbase_setup.py  # Integration tests for DB init and table reflection
  test_dbase_update.py # Integration tests for ETL update operations
```

**Unit tests** (`test_utils.py`, `test_core.py`) use `unittest.mock` to isolate
logic from external services. They cover:
- camelCase to snake_case column conversion
- Empty string cleaning in DataFrames
- Schema casting between source and target DataFrames
- List-of-dicts to Polars DataFrame conversion
- BLS CPI data parsing (mocked HTTP)
- Environment variable loading and validation
- Row isolation logic (new rows via anti-join, updated rows via semi-join)
- FMP API response conversion and concatenation
- SQLAlchemy automap module name resolution

**Integration tests** (`test_dbase_setup.py`, `test_dbase_update.py`) connect to the
real SupaBase database and external APIs. They verify:
- Backend initialization and schema reflection
- Table structure against an expected list of `pfin` schema tables
- Full ETL update cycle for each table type (CPI, assets, equity profiles,
  income statements, balance sheets, cash flows, earnings, EOD prices)

> **Note:** Integration tests write to the production database. Run them locally
> only, not in CI. They require a valid `.env` file with real credentials.

### Fixtures

Shared fixtures live in `tests/conftest.py`:

- `backend` -- Session-scoped `PFinBackend` instance reused across all integration
  tests. Automatically skips the entire integration suite if the DB connection fails.
- `sample_fmp_income_json`, `sample_fmp_profile_json` -- Sample FMP API response
  payloads for mocking.
- `sample_bls_cpi_json` -- Sample BLS CPI API response structure.
- `sample_camel_case_columns` -- Column name list for snake_case conversion tests.
- `sample_df_old`, `sample_df_new` -- Polars DataFrames for testing row isolation
  (INSERT vs UPDATE) logic.

### Data Validation

Data validation happens at several points in the ETL pipeline:

- **Column normalization** (`utils.col_to_snake`) -- API responses arrive in
  camelCase; columns are converted to snake_case before any DB operations.
- **Empty string cleaning** (`utils.clean_empty_str_df`) -- Replaces `""` with
  `None` so nullable DB columns get proper NULLs.
- **Schema casting** (`utils.apply_schema_df`) -- Ensures DataFrame dtypes match
  the target table schema before insert/update (uses `strict=False` for lenient
  casting).
- **Common column calculation** (`core.SBaseConn._calc_common_cols_df`) -- Only
  columns present in both the API response and the DB table are carried forward,
  preventing mismatched inserts.
- **Row isolation** (`_isolate_new_rows_df`, `_isolate_updated_rows_df`) --
  Anti-join and semi-join logic separates rows into INSERT vs UPDATE sets based on
  key columns.
- **API response validation** -- BLS responses are checked for
  `status == "REQUEST_SUCCEEDED"` before parsing; failures raise an exception.
- **Environment variable validation** (`utils.load_env_variables`) -- Raises
  `ValueError` immediately if required keys (`FMP_API_KEY`, `BLS_API_KEY`, DB
  connection params) are missing.

## CI/CD

> **Monorepo note (2026-06-16, W0):** This worker was absorbed into the
> [mosko-fintech](https://github.com/richmosko/mosko-fintech) monorepo at
> `workers/etl/`. The standalone `.github/workflows/ci.yml` did NOT migrate. CI
> posture in the monorepo: the `TenantBoundConnection` fence runs in mosko-fintech
> `.github/workflows/security-scan.yml`; re-homing this worker's ruff + pytest
> lint/test jobs into the monorepo CI is a tracked follow-up. The jobs described
> below reflect the pre-monorepo standalone posture and run locally via the
> commands in the Usage section.

GitHub Actions previously ran on every push and pull request to `main`
(`.github/workflows/ci.yml`):

### Lint Job
- Checks code style with **ruff** (`ruff check` and `ruff format --check`) across
  `src/` and `tests/`.

### Unit Tests Job
- Installs test dependencies with `uv sync --group test`
- Runs `uv run pytest -m unit --cov=pfin_back_etl --cov-report=term-missing`
- No credentials or external services required.

### Integration Tests (local only)
Integration tests are **not** run in CI. They require a `.env` with valid database
and API credentials and write to the production database. Run them locally:

```bash
uv run pytest -m integration
```

## Docker

Build and run the production ETL job:

```bash
docker compose up --build
```

The container installs dependencies from the lockfile (`uv sync --frozen`), installs
the package in editable mode, and runs `main.py` as the entrypoint.

## Usage
- Run Tests: `uv run pytest` (see Testing section above for more options)
- Run ETL: `uv run python main.py`
- Docker: `docker compose up --build`
- Lint: `uv run ruff check src/ tests/`
- Format check: `uv run ruff format --check src/ tests/`

## Contributing
... Just me so far...

## License
MIT License

## Contact
TBD
