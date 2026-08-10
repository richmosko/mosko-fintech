"""
Project:       pfin-back-etl
Author:        Rich Mosko (mosko-fintech Backend)

Description:
    Unit tests for the integration-fixture failure policy — BACKLOG §7.6 S16.

    These are `unit`-tier: pure predicates, no database, no credentials, so
    they run in CI (`pytest -m unit`) and therefore actually protect `main`.
    The integration lane they govern does NOT run in CI and cannot — which is
    exactly why the policy governing it needs hermetic coverage.

    What is under test is a POLICY, not a behaviour: which failures an
    integration fixture is permitted to swallow. The fixture used to swallow
    all of them (`except Exception: pytest.skip(...)`), converting a
    production-fatal failure into a green skip. These tests pin the narrowed
    surface so it cannot silently widen again.
"""

import pytest
import sqlalchemy as sqla
from sqlalchemy import exc as sqla_exc

from conftest import (
    ROLE_ENV_VAR,
    check_expected_role,
    is_database_unreachable,
    _UNREACHABLE_EXC,
)


def _operational_error():
    """A connect-time failure: the only thing a fixture may skip on."""
    return sqla_exc.OperationalError("select 1", {}, Exception("connection refused"))


# ---------------------------------------------------------------------------
# The skip surface — what a fixture MAY swallow
# ---------------------------------------------------------------------------
@pytest.mark.unit
def test_operational_error_is_the_skip_surface():
    """No database to talk to is the ONE sanctioned reason to skip."""
    assert is_database_unreachable(_operational_error()) is True


# ---------------------------------------------------------------------------
# The defect surface — what a fixture MUST NOT swallow.
#
# Each case is named for the BACKLOG entry whose defect wears that exception
# type, so a future widening of _UNREACHABLE_EXC fails against the specific
# concealment it would re-enable rather than against an abstract rule.
# ---------------------------------------------------------------------------
@pytest.mark.unit
@pytest.mark.parametrize(
    "exc, entry",
    [
        (sqla_exc.ArgumentError("relationship conflicts with column"), "S13"),
        (
            sqla_exc.ProgrammingError(
                "insert into pfin.cpi_u_index", {}, Exception("permission denied")
            ),
            "S17",
        ),
        (ValueError("Environment variable BLS_API_KEY does not exist"), "S12"),
        (ImportError("No module named 'polars'"), "environment/build"),
        (Exception("anything else at all"), "unclassified"),
    ],
)
def test_real_defects_are_not_skippable(exc, entry):
    """A defect must reach the runner as a FAILURE, never as a green skip."""
    assert is_database_unreachable(exc) is False, (
        f"{type(exc).__name__} ({entry}) would be swallowed as a skip — "
        f"this is the S16 concealment shape re-opening."
    )


@pytest.mark.unit
def test_skip_surface_is_exactly_one_type():
    """Non-vacuity pin on the surface itself.

    The parametrized test above proves specific types are excluded; it cannot
    prove the surface did not grow a fourth member nobody enumerated. This
    asserts the surface's SIZE, so widening it fails here even if the new
    member is a type no other test names.

    ⚠ `Exception` in this tuple would make every test above pass vacuously
    while restoring the original defect, so it is checked explicitly.
    """
    assert _UNREACHABLE_EXC == (sqla_exc.OperationalError,)
    assert Exception not in _UNREACHABLE_EXC
    assert BaseException not in _UNREACHABLE_EXC


@pytest.mark.unit
def test_operational_error_is_not_a_superclass_of_the_defect_types():
    """Guards the isinstance() semantics rather than the tuple's contents.

    A skip surface built on isinstance() is only as narrow as the class tree
    beneath it. If ArgumentError or ProgrammingError ever became a subclass of
    OperationalError upstream, the tuple could stay `(OperationalError,)` and
    still swallow both — the surface would widen with no diff in this repo.
    """
    assert not issubclass(sqla_exc.ArgumentError, sqla_exc.OperationalError)
    assert not issubclass(sqla_exc.ProgrammingError, sqla_exc.OperationalError)


# ---------------------------------------------------------------------------
# Role variance — the half narrowing the `except` does NOT reach
# ---------------------------------------------------------------------------
@pytest.mark.unit
@pytest.mark.parametrize("unset", [None, ""])
def test_role_check_is_inert_when_unconstrained(unset):
    """Unset means "don't care" — the pre-existing behaviour is preserved."""
    assert check_expected_role("postgres", unset) is None


@pytest.mark.unit
def test_role_check_passes_on_match():
    assert check_expected_role("pfin_etl", "pfin_etl") == "pfin_etl"


@pytest.mark.unit
def test_role_check_fails_when_the_lane_ran_as_the_wrong_role():
    """The case this exists for: a run INTENDED as `pfin_etl` that silently
    authenticated as the superuser would otherwise report a clean pass while
    measuring nothing about privileges."""
    with pytest.raises(AssertionError) as excinfo:
        check_expected_role("postgres", "pfin_etl")
    message = str(excinfo.value)
    assert "postgres" in message and "pfin_etl" in message, (
        "the failure must name BOTH roles — 'wrong role' without saying which "
        "sends the reader back to the environment to guess"
    )
    assert ROLE_ENV_VAR in message


@pytest.mark.unit
def test_role_check_is_exact_not_substring():
    """`pfin_etl` must not satisfy an expectation of `pfin_etl_readonly`, and
    a superuser must not satisfy one by prefix. Role names are identifiers,
    not patterns."""
    with pytest.raises(AssertionError):
        check_expected_role("pfin_etl", "pfin_etl_readonly")
    with pytest.raises(AssertionError):
        check_expected_role("pfin_etl_readonly", "pfin_etl")


# ---------------------------------------------------------------------------
# The identity query itself — hermetic, against SQLite-free real SQL semantics
# ---------------------------------------------------------------------------
@pytest.mark.unit
def test_identity_query_is_privilege_free_sql():
    """`select session_user, current_user` must stay privilege-free.

    Pinned because the fixture runs it BEFORE any role is assumed, on a
    NOINHERIT login that holds nothing. If this ever grew a table reference it
    would fail 42501 in exactly the configuration the lane exists to test, and
    the failure would look like the defect rather than like the instrument.
    """
    stmt = sqla.text("select session_user, current_user")
    text = str(stmt).lower()
    assert "from" not in text
    assert "pfin" not in text
