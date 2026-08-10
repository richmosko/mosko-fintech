"""
Project:       pfin-back-etl
Author:        Rich Mosko

Description:
    Shared pytest fixtures and configuration for the test suite.

    Test tiers:
        - unit:        Fast tests with no external dependencies (mocked DB/API)
        - integration: Tests that hit the real database and/or APIs

    Usage:
        uv run pytest -m unit          # fast, no credentials needed
        uv run pytest -m integration   # requires .env with valid credentials
        uv run pytest                  # runs everything
"""

import logging
import os

import pytest
import polars as pl
import sqlalchemy as sqla
from sqlalchemy import exc as sqla_exc

logger = logging.getLogger("pfin_etl")


# ---------------------------------------------------------------------------
# FIXTURE FAILURE POLICY — BACKLOG §7.6 S16 (the actionable half)
# ---------------------------------------------------------------------------
# These fixtures used to wrap construction in `except Exception:
# pytest.skip(...)`, which converted a PRODUCTION-FATAL failure into a GREEN
# SKIP. Measured during S13: the pre-existing fixture-based tests SKIPPED on
# the very ArgumentError that blocked the production entry point, while
# purpose-built tests failed. That is why "the ETL tests are green" carried no
# information about whether the ETL could start.
#
# The policy is now: a fixture may SKIP for exactly one reason — THERE IS NO
# DATABASE TO TALK TO. Every other failure is a defect and must PROPAGATE.
#
# ⚠ WHY THIS IS AN `isinstance` CHECK AND NOT A SQLSTATE CHECK. The obvious
# design is to discriminate on SQLSTATE — "the server answered and refused" vs
# "no server answered". MEASURED 2026-08-09 against psycopg2 + the local
# stack: `pgcode` is None for EVERY connect-time failure — connection refused,
# password authentication failed, nonexistent role, and NOLOGIN role alike.
# The discriminator does not exist at connect time, so this deliberately does
# NOT match on message text either (see the S17 acceptance controls: assert by
# code, never by message). `OperationalError` is the whole of the skip surface.
#
# Consequence, stated rather than discovered later: a missing credential now
# FAILS this lane instead of skipping it, because `load_env_variables` raises
# ValueError and ValueError is not a connection failure. That is the S12
# defect becoming visible, and it is intended — a lane that goes green when
# the worker cannot even be constructed is the thing S16 exists to stop.
_UNREACHABLE_EXC = (sqla_exc.OperationalError,)

#: Set to a role name (e.g. `pfin_etl`) to ASSERT which login role the lane ran
#: as. Unset means "don't care", which is the pre-existing behaviour.
ROLE_ENV_VAR = "PFIN_TEST_EXPECT_ROLE"


def is_database_unreachable(exc):
    """True only when the failure means *there is no database to talk to*.

    The single sanctioned reason an integration fixture may skip. Everything
    else — automap ArgumentError (S13), permission denied (S17), ImportError,
    a missing credential (S12) — is a defect and must reach the test runner as
    a FAILURE.
    """
    return isinstance(exc, _UNREACHABLE_EXC)


def check_expected_role(actual_role, expected_role):
    """Pure comparison, extracted so it is unit-testable without a database.

    Returns None when the run is unconstrained; raises AssertionError when the
    lane ran as a role other than the one it was told to run as.

    ⚠ THIS IS THE OTHER HALF OF S16, AND IT IS THE HALF NARROWING THE `except`
    DOES NOT REACH. Every run of this lane to date has authenticated as
    `postgres`, a superuser that needs no role assumption — so a role-privilege
    defect is INVARIANT under every run anyone has performed, and no amount of
    exception-narrowing surfaces it. A suite that passes under every value of a
    variable is blind to that variable, not robust to it. The variable here is
    the login role.
    """
    if not expected_role:
        return None
    if actual_role != expected_role:
        raise AssertionError(
            f"{ROLE_ENV_VAR}={expected_role!r} but the lane authenticated as "
            f"{actual_role!r}. Refusing to run: a role-privilege result "
            f"measured under the wrong role is worse than no result, because "
            f"it reads as evidence."
        )
    return actual_role


def _report_login_identity(engine, what):
    """Log the effective login identity and enforce ROLE_ENV_VAR if set.

    Makes the login role VISIBLE in every run's output. `session_user` is the
    role that authenticated; `current_user` is whatever a SET ROLE has made
    effective. Requires no privileges of its own.
    """
    with engine.connect() as conn:
        session_user, current_user = conn.execute(
            sqla.text("select session_user, current_user")
        ).one()
    logger.info(
        f"{what}: session_user={session_user!r} current_user={current_user!r}"
    )
    check_expected_role(session_user, os.getenv(ROLE_ENV_VAR))
    return session_user


# ---------------------------------------------------------------------------
# Session-scoped backend fixture (shared across all integration tests)
# ---------------------------------------------------------------------------
@pytest.fixture(scope="session")
def backend():
    """
    Create a single PFinBackend instance for all integration tests.
    This avoids re-connecting to the database for every test function.

    Skips ONLY when there is no database to talk to (see the failure policy
    above). Any other construction failure propagates as a FAILURE.
    """
    import pfin_back_etl as pfbe

    try:
        pfb = pfbe.PFinBackend()
    except Exception as e:
        if is_database_unreachable(e):
            pytest.skip(f"No database reachable for PFinBackend: {e}")
        raise
    _report_login_identity(pfb.engine, "PFinBackend")
    return pfb


@pytest.fixture(scope="session")
def nav_worker():
    """SELF-214 daily-NAV worker (W-1). Live tests additionally require
    migration 054 (pfin.nav_daily) applied in the fixture DB — see the test
    docstrings.

    Same failure policy as `backend`: skips only when no database is
    reachable; every other failure propagates.
    """
    import pfin_back_etl as pfbe

    try:
        worker = pfbe.NavDailyWorker()
    except Exception as e:
        if is_database_unreachable(e):
            pytest.skip(f"No database reachable for NavDailyWorker: {e}")
        raise
    _report_login_identity(worker._system_tbc.engine, "NavDailyWorker")
    return worker


# ---------------------------------------------------------------------------
# Sample data fixtures for unit tests
# ---------------------------------------------------------------------------
@pytest.fixture
def sample_fmp_income_json():
    """Sample FMP income statement API response (single record)."""
    return [
        {
            "date": "2024-09-30",
            "symbol": "AAPL",
            "reportedCurrency": "USD",
            "cik": "0000320193",
            "fillingDate": "2024-11-01",
            "acceptedDate": "2024-11-01 06:01:36",
            "calendarYear": "2024",
            "period": "Q4",
            "revenue": 94930000000,
            "costOfRevenue": 52553000000,
            "grossProfit": 42377000000,
            "operatingIncome": 29592000000,
            "netIncome": 14736000000,
            "eps": 0.97,
            "epsdiluted": 0.97,
            "weightedAverageShsOut": 15204137000,
            "weightedAverageShsOutDil": 15204137000,
        }
    ]


@pytest.fixture
def sample_fmp_profile_json():
    """Sample FMP company profile API response."""
    return [
        {
            "symbol": "AAPL",
            "companyName": "Apple Inc.",
            "currency": "USD",
            "exchange": "NASDAQ",
            "exchangeShortName": "NASDAQ",
            "industry": "Consumer Electronics",
            "sector": "Technology",
            "country": "US",
            "mktCap": 3500000000000,
            "price": 230.50,
            "beta": 1.24,
            "volAvg": 55000000,
            "lastDiv": 1.00,
            "ipoDate": "1980-12-12",
            "description": "Apple Inc. designs, manufactures...",
        }
    ]


@pytest.fixture
def sample_bls_cpi_json():
    """Sample BLS CPI API response structure."""
    return {
        "status": "REQUEST_SUCCEEDED",
        "Results": {
            "series": [
                {
                    "seriesID": "CUUR0000SA0",
                    "data": [
                        {
                            "year": "2024",
                            "period": "M12",
                            "periodName": "December",
                            "value": "315.605",
                            "footnotes": [{}],
                        },
                        {
                            "year": "2024",
                            "period": "M11",
                            "periodName": "November",
                            "value": "315.493",
                            "footnotes": [{}],
                        },
                    ],
                }
            ]
        },
    }


@pytest.fixture
def sample_camel_case_columns():
    """Sample camelCase column names for testing snake_case conversion."""
    return [
        "reportedCurrency",
        "fillingDate",
        "acceptedDate",
        "calendarYear",
        "costOfRevenue",
        "grossProfit",
        "operatingIncome",
        "netIncome",
        "weightedAverageShsOut",
    ]


@pytest.fixture
def sample_df_old():
    """Sample 'existing' dataframe for testing row isolation logic."""
    return pl.DataFrame(
        {
            "id": [1, 2, 3],
            "symbol": ["AAPL", "NVDA", "GOOGL"],
            "description": ["Apple Inc.", "NVIDIA Corp.", "Alphabet Inc."],
        }
    )


@pytest.fixture
def sample_df_new():
    """Sample 'new' dataframe with some overlapping and some new entries."""
    return pl.DataFrame(
        {
            "symbol": ["AAPL", "NVDA", "META", "MSFT"],
            "description": [
                "Apple Inc.",
                "NVIDIA Corporation",  # updated description
                "Meta Platforms",  # new entry
                "Microsoft Corp.",  # new entry
            ],
        }
    )


# ---------------------------------------------------------------------------
# RT-15 parity — record-replay fixtures (synthetic, offline, credential-free)
# ---------------------------------------------------------------------------
# Replays frozen *synthetic* BLS + FMP HTTP responses so deterministic tests
# run with no live API and no API keys. Governance + MUST-NOT discipline:
# tests/fixtures/parity/README.md (central). Payloads: tests/fixtures/replay/.
# Pair with `@pytest.mark.replay`.
import replay as _replay  # sibling module; tests/ dir is on sys.path under pytest


@pytest.fixture
def bls_replay(monkeypatch):
    """Patch the BLS `requests.post` seam to replay a synthetic CPI payload.

    No network, no BLS_API_KEY. Returns the synthetic payload for assertions.
    """
    _replay.install_bls_replay(monkeypatch)
    return _replay.load_replay("bls_cpi")


@pytest.fixture
def fmp_replay():
    """Factory for synthetic FMP `fmp_func` stubs for `PFinFMP.fetch_fmp_df`.

    No network, no FMP_API_KEY. Call e.g. `fmp_replay("fmp_income_statement")`
    to get a replay `fmp_func` suitable for `fetch_fmp_df(fmp_func, ...)`.
    """
    return _replay.make_fmp_func
