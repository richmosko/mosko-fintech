"""
Project:       pfin-back-etl
Author:        Rich Mosko (mosko-fintech Backend)

Description:
    Unit tests for the integration-fixture failure policy — BACKLOG §7.6 S16.

    `unit`-tier: pure functions and injected raisers, no database, no
    credentials — so these run in CI and therefore protect `main`. The
    integration lane they govern does NOT run in CI and cannot, which is
    exactly why the policy governing it needs hermetic coverage.

    ⚠ WHAT THE FIRST VERSION OF THIS FILE GOT WRONG, KEPT AS THE HEADER
    BECAUSE IT IS THE POINT. It pinned the PREDICATE exhaustively and never
    pinned that the fixtures CALLED it. QA reverted both fixtures to
    `except Exception: pytest.skip(...)` — the exact concealment shape S16
    exists to stop — and all 14 tests passed (reproduced here before fixing:
    14 passed, 0 failed). Both of the original inversions mutated the
    predicate; the mutation that mattered was at the CALL SITE.

    So the unit under test is now `construct_or_skip()`, exercised by
    INJECTING a raiser — which is behaviour, where `inspect.getsource()`
    assertions would only be a syntactic proxy for it.

    Imports come from `fixture_policy`, not `conftest`: importing a conftest as
    a module is fragile under a future pytest `importmode` change.
"""

import pytest
import sqlalchemy as sqla
from sqlalchemy import exc as sqla_exc

from fixture_policy import (
    _ATTRS_SQL,
    _FORBIDDEN_ROLE_ATTRS,
    _IDENTITY_SQL,
    _UNREACHABLE_EXC,
    ROLE_ENV_VAR,
    check_expected_role,
    check_role_attributes,
    construct_or_skip,
    is_database_unreachable,
)

Skipped = pytest.skip.Exception


def _operational_error():
    return sqla_exc.OperationalError("select 1", {}, Exception("connection refused"))


def _raiser(exc):
    def _make():
        raise exc

    return _make


def expect_raises_not_skip(exc_type, call):
    """Assert `call()` raises `exc_type` — and FAIL, loudly, if it skips.

    ⚠ THIS EXISTS BECAUSE `pytest.raises` CANNOT BE USED HERE, AND FINDING OUT
    COST A THIRD ITERATION OF THE SAME BUG. `pytest.skip()` raises `Skipped`,
    which is a BaseException that `pytest.raises(SomeError)` does not catch —
    so it propagates out of the test and pytest marks THE TEST ITSELF as
    SKIPPED. Not failed. Skipped.

    So a test written as `with pytest.raises(ArgumentError): fixture()` against
    a fixture that improperly skips reports **skipped, and the suite stays
    green**. Measured: the first version of the fixture-body tests reported
    "26 passed, 2 skipped" under QA's inversion — still no RED.

    That is the S16 concealment shape for a third time, one level further in:
    the test guarding against improper skipping was itself silently skippable.
    Any assertion about skip behaviour must convert `Skipped` into a failure
    explicitly, because the default is to be swallowed by the same mechanism
    under test.
    """
    try:
        call()
    except Skipped as exc_skip:
        pytest.fail(
            f"expected {exc_type.__name__} to propagate, but it was swallowed "
            f"into a SKIP ({exc_skip}) — this is the S16 concealment shape, "
            f"and a skipped test would have left the suite green."
        )
    except exc_type:
        return
    except BaseException as exc_other:  # noqa: BLE001 - deliberate: report, don't mask
        pytest.fail(
            f"expected {exc_type.__name__}, got "
            f"{type(exc_other).__name__}: {exc_other}"
        )
    pytest.fail(f"expected {exc_type.__name__}, but nothing was raised")


# ---------------------------------------------------------------------------
# THE CALL SITE — the unit QA's inversion proved was untested
# ---------------------------------------------------------------------------
@pytest.mark.unit
def test_successful_construction_is_returned():
    sentinel = object()
    assert construct_or_skip("thing", lambda: sentinel) is sentinel


@pytest.mark.unit
def test_call_site_skips_only_on_an_unreachable_database(monkeypatch):
    monkeypatch.delenv(ROLE_ENV_VAR, raising=False)
    with pytest.raises(Skipped):
        construct_or_skip("thing", _raiser(_operational_error()))


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
def test_call_site_propagates_real_defects(exc, entry, monkeypatch):
    """⚠ THE TEST WHOSE ABSENCE LET THE FENCE BE REMOVED WITH A GREEN SUITE.

    Asserts the ORIGINAL exception reaches the runner — not merely that
    "something raised", since `pytest.skip` also raises. Reverting the fixtures
    to `except Exception: pytest.skip(...)` now fails HERE.
    """
    monkeypatch.delenv(ROLE_ENV_VAR, raising=False)
    expect_raises_not_skip(type(exc), lambda: construct_or_skip("thing", _raiser(exc)))


@pytest.mark.unit
def test_a_defect_is_not_merely_raised_it_is_not_a_skip(monkeypatch):
    """Guards the distinction the test above depends on.

    `Skipped` IS an exception, so a naive `pytest.raises(Exception)` would pass
    against the very concealment being fenced.
    """
    monkeypatch.delenv(ROLE_ENV_VAR, raising=False)
    with pytest.raises(sqla_exc.ArgumentError) as excinfo:
        construct_or_skip("thing", _raiser(sqla_exc.ArgumentError("boom")))
    assert not isinstance(excinfo.value, Skipped)


# ---------------------------------------------------------------------------
# THE FIXTURES THEMSELVES — the boundary the extraction alone does NOT close
# ---------------------------------------------------------------------------
# ⚠ EXTRACTING `construct_or_skip` AND TESTING IT IS NOT SUFFICIENT, AND I
# MEASURED THAT BEFORE BELIEVING IT. With the helper extracted and covered by
# every test above, re-running QA's inversion — reverting both fixtures to
# `except Exception: pytest.skip(...)` — STILL PASSED, 24/24. Testing the
# helper moves the untested boundary up one level; it does not remove it,
# because nothing asserted that the fixtures CALL the helper.
#
# The only thing that closes it is exercising the FIXTURE BODY. `__wrapped__`
# is the undecorated function, so these drive the real fixture with a raiser
# injected in place of the constructor. Now the inversion goes RED.
#
# This is why `conftest` is imported here despite the module-header preference
# for `fixture_policy`: the fixtures ARE the subject.
import conftest  # noqa: E402


def _fixture_body(name):
    """The undecorated fixture function — the fixture itself, not the policy."""
    return getattr(conftest, name).__wrapped__


@pytest.mark.unit
@pytest.mark.parametrize(
    "fixture_name, constructor",
    [("backend", "PFinBackend"), ("nav_worker", "NavDailyWorker")],
)
def test_fixture_body_propagates_a_defect(fixture_name, constructor, monkeypatch):
    """S13's shape, driven through the real fixture. Reverting the fixture to
    `except Exception: pytest.skip(...)` fails HERE and nowhere else."""
    import pfin_back_etl as pfbe

    monkeypatch.delenv(ROLE_ENV_VAR, raising=False)
    monkeypatch.setattr(
        pfbe, constructor, _raiser(sqla_exc.ArgumentError("automap collision"))
    )
    expect_raises_not_skip(sqla_exc.ArgumentError, _fixture_body(fixture_name))


@pytest.mark.unit
@pytest.mark.parametrize(
    "fixture_name, constructor",
    [("backend", "PFinBackend"), ("nav_worker", "NavDailyWorker")],
)
def test_fixture_body_still_skips_an_unreachable_database(
    fixture_name, constructor, monkeypatch
):
    """The permitted skip must survive the fence — otherwise the fix would be
    "make everything fail", which is not the policy."""
    import pfin_back_etl as pfbe

    monkeypatch.delenv(ROLE_ENV_VAR, raising=False)
    monkeypatch.setattr(pfbe, constructor, _raiser(_operational_error()))
    with pytest.raises(Skipped):
        _fixture_body(fixture_name)()


# ---------------------------------------------------------------------------
# #3 — a wrong DATABASE_URL is indistinguishable from no database
# ---------------------------------------------------------------------------
@pytest.mark.unit
def test_unreachable_database_is_a_failure_when_role_constrained(monkeypatch):
    """Declaring an expected role declares that a database is expected.

    Otherwise a run pointed at the wrong host reports green-with-skips, which
    reads as a pass — the third vacuity mode.
    """
    monkeypatch.setenv(ROLE_ENV_VAR, "pfin_etl")
    expect_raises_not_skip(
        AssertionError, lambda: construct_or_skip("thing", _raiser(_operational_error()))
    )


# ---------------------------------------------------------------------------
# The skip surface itself
# ---------------------------------------------------------------------------
@pytest.mark.unit
def test_operational_error_is_the_skip_surface():
    assert is_database_unreachable(_operational_error()) is True


@pytest.mark.unit
def test_skip_surface_is_exactly_one_type():
    """Anti-vacuity pin on the surface's SIZE — `Exception` here would make
    every other assertion pass vacuously while restoring the original defect."""
    assert _UNREACHABLE_EXC == (sqla_exc.OperationalError,)
    assert Exception not in _UNREACHABLE_EXC
    assert BaseException not in _UNREACHABLE_EXC


@pytest.mark.unit
def test_operational_error_is_not_a_superclass_of_the_defect_types():
    """An `isinstance` surface is only as narrow as the class tree beneath it;
    an upstream change could widen it with no diff in this repo."""
    assert not issubclass(sqla_exc.ArgumentError, sqla_exc.OperationalError)
    assert not issubclass(sqla_exc.ProgrammingError, sqla_exc.OperationalError)


# ---------------------------------------------------------------------------
# Role NAME
# ---------------------------------------------------------------------------
@pytest.mark.unit
@pytest.mark.parametrize("unset", [None, ""])
def test_role_check_is_inert_when_unconstrained(unset):
    assert check_expected_role("postgres", unset) is None


@pytest.mark.unit
def test_role_check_passes_on_match():
    assert check_expected_role("pfin_etl", "pfin_etl") == "pfin_etl"


@pytest.mark.unit
def test_role_check_fails_when_the_lane_ran_as_the_wrong_role():
    with pytest.raises(AssertionError) as excinfo:
        check_expected_role("postgres", "pfin_etl")
    message = str(excinfo.value)
    assert "postgres" in message and "pfin_etl" in message
    assert ROLE_ENV_VAR in message


@pytest.mark.unit
def test_role_check_is_exact_not_substring():
    with pytest.raises(AssertionError):
        check_expected_role("pfin_etl", "pfin_etl_readonly")
    with pytest.raises(AssertionError):
        check_expected_role("pfin_etl_readonly", "pfin_etl")


# ---------------------------------------------------------------------------
# Role ATTRIBUTES — a name proves nothing about privilege
# ---------------------------------------------------------------------------
def _attrs(**overrides):
    base = dict.fromkeys(_FORBIDDEN_ROLE_ATTRS, False)
    base.update(overrides)
    return base


@pytest.mark.unit
def test_attribute_check_is_inert_when_unconstrained():
    assert check_role_attributes(_attrs(rolsuper=True), None) is None


@pytest.mark.unit
def test_all_false_attributes_pass():
    assert check_role_attributes(_attrs(), "pfin_etl") == _attrs()


@pytest.mark.unit
@pytest.mark.parametrize("attr", _FORBIDDEN_ROLE_ATTRS)
def test_each_forbidden_attribute_fails_on_its_own(attr):
    """Each is disqualifying independently, so each is checked independently.

    ⚠ `rolinherit` is the essential one: an inheriting login holds its granted
    privileges with NO `SET ROLE`, so the S17 acceptance test would pass
    AGAINST AN UNFIXED `SBaseConn` — a test that can go green without the fix
    is not evidence for the fix.
    """
    with pytest.raises(AssertionError, match=attr):
        check_role_attributes(_attrs(**{attr: True}), "pfin_etl")


@pytest.mark.unit
def test_forbidden_attribute_set_is_exactly_the_three_ruled():
    """Anti-vacuity pin: the parametrize above iterates the same tuple it
    guards, so it cannot notice the tuple shrinking. Dropping `rolinherit`
    would silently stop protecting the acceptance run."""
    assert _FORBIDDEN_ROLE_ATTRS == ("rolsuper", "rolbypassrls", "rolinherit")


# ---------------------------------------------------------------------------
# The identity SQL must stay privilege-free
# ---------------------------------------------------------------------------
@pytest.mark.unit
def test_identity_sql_reads_only_privilege_free_catalog_sources():
    """⚠ REWRITTEN — the previous version asserted `"from" not in sql`, which
    was a SYNTACTIC PROXY for privilege-freedom, not the property. It broke the
    moment a legitimately privilege-free `pg_roles` read was added.

    The property: these statements run BEFORE any role is assumed, on a
    NOINHERIT login that holds nothing. Built-ins and `pg_catalog` are
    world-readable; anything in `pfin` is not and would fail 42501 in exactly
    the configuration the lane exists to test — the failure would then look
    like the defect rather than like the instrument.
    """
    allowed_sources = {"pg_roles"}
    for sql in (_IDENTITY_SQL, _ATTRS_SQL):
        text = str(sqla.text(sql)).lower()
        assert "pfin" not in text
        for token in text.split():
            if token.startswith("pfin.") or "." in token.strip(";,"):
                pytest.fail(f"schema-qualified reference in privilege-free SQL: {token}")
        if " from " in text:
            source = text.split(" from ", 1)[1].split()[0]
            assert source in allowed_sources, (
                f"{source!r} is not a known world-readable catalog source"
            )
