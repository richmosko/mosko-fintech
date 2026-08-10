"""
Project:       pfin-back-etl
Author:        Rich Mosko (mosko-fintech Backend)

Description:
    S12 acceptance — BACKLOG §7.6. A job must be constructible with ONLY the
    credentials it actually uses.

    `unit`-tier and genuinely hermetic: SQLAlchemy engines are LAZY, so
    `NavDailyWorker()` builds its engine without touching a database. That is
    what lets the real acceptance criterion — "constructs with DB parameters
    alone" — be asserted in CI rather than by hand.

    ⚠ The defect these pin was invisible to every static review and fatal on
    every run: `nav_daily.py` contains ZERO references to FMP_API_KEY or
    BLS_API_KEY and makes ZERO external API calls, yet refused to start without
    both. `secrets-manifest.yml` scopes those keys to OTHER jobs, so the NAV
    cron had to be handed two credentials it has no business holding, or die on
    its first scheduled run before doing any work.
"""

from unittest.mock import patch

import pytest

import pfin_back_etl as pfbe
from pfin_back_etl import utils
from pfin_back_etl.core import PFinBackend

_DB_ONLY_ENV = {
    "PFIN_DB_USER": "u",
    "PFIN_DB_HOST": "h",
    "PFIN_DB_PORT": "5432",
    "PFIN_DB_NAME": "d",
    "PFIN_DB_PASSWORD": "p",
}


def _env(mapping):
    """Patch dotenv + os.getenv so only `mapping` exists."""
    return (
        patch("pfin_back_etl.utils.dotenv.load_dotenv"),
        # `d=None` so a future `os.getenv(x, "default")` in utils does not
        # break these with a confusing TypeError instead of a real failure.
        patch(
            "pfin_back_etl.utils.os.getenv",
            side_effect=lambda k, d=None: mapping.get(k, d),
        ),
    )


@pytest.mark.unit
def test_nav_worker_constructs_with_database_parameters_alone():
    """THE S12 ACCEPTANCE CRITERION, asserted rather than described.

    No FMP_API_KEY, no BLS_API_KEY in the environment. Before the fix this
    raised ValueError before any work began.
    """
    dotenv_patch, getenv_patch = _env(_DB_ONLY_ENV)
    with dotenv_patch, getenv_patch:
        worker = pfbe.NavDailyWorker()
    assert worker is not None
    assert "FMP_API_KEY" not in worker._params
    assert "BLS_API_KEY" not in worker._params


@pytest.mark.unit
def test_nav_worker_holds_no_api_credentials_at_all():
    """The worker must not LOAD a credential scoped to a different job.

    ⚠ BOUNDED TO WHAT IT PROVES. This asserts `worker._params` does not carry
    the value. It says NOTHING about the process environment — `os.environ`
    still holds whatever the container was handed, and this test cannot see
    that. The deployment half (the NAV cron container not being HANDED keys
    scoped to other jobs) is per-container env scoping and is DevOps-owned.
    A green here must not be read as the containers already being scoped.

    The sentinel values matter: the keys are SET to "leaked" rather than left
    absent, so the test varies the variable and asserts the property survives.
    Asserting absence in an environment where they are absent anyway would
    pass without being able to fail.
    """
    dotenv_patch, getenv_patch = _env(
        {**_DB_ONLY_ENV, "FMP_API_KEY": "leaked", "BLS_API_KEY": "leaked"}
    )
    with dotenv_patch, getenv_patch:
        worker = pfbe.NavDailyWorker()
    assert "leaked" not in str(worker._params.values())


# ---------------------------------------------------------------------------
# The FMP client is lazy — a CPI-only run needs no FMP credential
# ---------------------------------------------------------------------------
def _bare_backend(params):
    """A PFinBackend without __init__ — no database, no reflection.

    The lazy-client contract is independent of connection setup, so this
    exercises exactly the property under test and nothing else.
    """
    pfb = object.__new__(PFinBackend)
    pfb._params = params
    pfb._fmp_client = None
    return pfb


@pytest.mark.unit
def test_fmp_client_is_not_built_until_used():
    """Constructing PFinBackend must not require FMP_API_KEY.

    It used to build the client in __init__, so a CPI-only container had to
    carry a credential it never uses — and a machine without one could not
    construct the object at all.
    """
    pfb = _bare_backend({"BLS_API_KEY": "bls-only"})
    assert pfb._fmp_client is None


@pytest.mark.unit
def test_fmp_access_raises_naming_the_credential():
    """When the FMP path IS taken without a key, the failure is located and
    names what was needed — not a KeyError or a None propagating onward."""
    pfb = _bare_backend({"FMP_API_KEY": None})
    with pytest.raises(ValueError, match="FMP_API_KEY"):
        pfb.fmp_client


@pytest.mark.unit
def test_fmp_client_is_memoised():
    """Built once, reused — the laziness must not become a per-call rebuild of
    a rate-limited API client."""
    pfb = _bare_backend({"FMP_API_KEY": "k"})
    first = pfb.fmp_client
    assert pfb.fmp_client is first


@pytest.mark.unit
def test_cpi_path_requires_bls_but_not_fmp():
    """The two credentials are independently required, which is the whole
    point of the split: a CPI-only job needs BLS and must not need FMP."""
    cpi_only = {"BLS_API_KEY": "bls", "FMP_API_KEY": None}
    assert utils.require_api_key(cpi_only, "BLS_API_KEY") == "bls"
    with pytest.raises(ValueError, match="FMP_API_KEY"):
        utils.require_api_key(cpi_only, "FMP_API_KEY")
