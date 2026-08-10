"""
Project:       pfin-back-etl
Author:        Rich Mosko (mosko-fintech Backend)

Description:
    Unit tests for SBaseConn._role() — BACKLOG §7.6 S17, Sec D-A option (c).

    `unit`-tier: a recording fake stands in for the Session, so these need no
    database and no credentials and therefore run in CI, where they actually
    protect `main`. The privilege behaviour itself cannot be proven here —
    SQLite has no roles and no grants — so it is proven by the live acceptance
    run instead. What IS provable hermetically is the CONTRACT: which role is
    assumed, that nothing unvetted reaches the interpolation, and that teardown
    never eats the original exception.
"""

import pytest

from pfin_back_etl.core import (
    SBaseConn,
    _READ_ROLE,
    _ROLE_ALLOWLIST,
    _WRITE_ROLE,
)


class RecordingSession:
    """Minimal Session stand-in: records rendered SQL, optionally raises."""

    def __init__(self, fail_on=None):
        self.statements = []
        self._fail_on = fail_on

    def execute(self, stmt):
        rendered = str(stmt)
        self.statements.append(rendered)
        if self._fail_on and self._fail_on in rendered:
            raise RuntimeError(f"simulated failure on {rendered!r}")
        return None


def _role_cm(session, role):
    """`_role` never touches `self`; bind None so no DB is needed."""
    return SBaseConn._role(None, session, role)


# ---------------------------------------------------------------------------
# The role actually assumed
# ---------------------------------------------------------------------------
@pytest.mark.unit
@pytest.mark.parametrize("role", sorted(_ROLE_ALLOWLIST))
def test_allowlisted_role_is_assumed_and_reset(role):
    session = RecordingSession()
    with _role_cm(session, role):
        session.execute("select 1")
    assert session.statements == [f"set local role {role}", "select 1", "reset role"]


@pytest.mark.unit
def test_set_local_not_set_session_wide():
    """`SET LOCAL` is required, not `SET`.

    Plain `SET ROLE` survives COMMIT and outlives the block, which is ambient
    privilege on a pooled connection — SQLAlchemy's pool_reset_on_return does
    not reset role, so a missed teardown poisons whatever borrows it next.
    """
    session = RecordingSession()
    with _role_cm(session, _WRITE_ROLE):
        pass
    assert session.statements[0].startswith("set local role ")


# ---------------------------------------------------------------------------
# The allowlist as the injection fence
# ---------------------------------------------------------------------------
@pytest.mark.unit
@pytest.mark.parametrize(
    "bad",
    [
        "postgres",
        "service_role; drop table pfin.asset",
        "SERVICE_ROLE",
        "service_role --",
        "",
        None,
    ],
)
def test_unvetted_role_raises_and_executes_nothing(bad):
    """⚠ The "executes nothing" half is the load-bearing one.

    `SET ROLE` takes an identifier and cannot be parameterised, so the role
    name is interpolated. Raising AFTER emitting would mean the unvetted value
    already reached the database.
    """
    session = RecordingSession()
    with pytest.raises(ValueError):
        with _role_cm(session, bad):
            pytest.fail("body must not run")
    assert session.statements == []


@pytest.mark.unit
def test_allowlist_is_exactly_the_two_ruled_roles():
    """Anti-vacuity pin on the fence itself.

    Every test above passes unchanged if a third role is added, so the surface
    needs its own assertion. `postgres` in particular would re-admit the
    superuser whose ambient privilege concealed S17 in the first place.
    """
    assert _ROLE_ALLOWLIST == frozenset({"authenticated", "service_role"})
    assert "postgres" not in _ROLE_ALLOWLIST


@pytest.mark.unit
def test_reads_are_authenticated_not_service_role():
    """Pins the Sec veto, which is the opposite of the intuitive choice.

    `service_role` for reads pulls every tenant's private rows from the two
    non-global tables (`asset` is HYBRID; `eod_price` carries per-user
    manual_valuation rows) — and `update_table_df` bulk-UPDATEs from that same
    frame, so widening the READ role manufactures a cross-tenant WRITE hazard.
    """
    assert _READ_ROLE == "authenticated"
    assert _WRITE_ROLE == "service_role"
    assert _READ_ROLE != _WRITE_ROLE


# ---------------------------------------------------------------------------
# N1 teardown shape
# ---------------------------------------------------------------------------
@pytest.mark.unit
def test_role_is_reset_even_when_the_body_raises():
    session = RecordingSession()
    with pytest.raises(RuntimeError, match="body exploded"):
        with _role_cm(session, _WRITE_ROLE):
            raise RuntimeError("body exploded")
    assert session.statements[-1] == "reset role"


@pytest.mark.unit
def test_teardown_failure_does_not_replace_the_original_exception():
    """The N1 case, and the reason it exists.

    If the block raised a DB error the transaction is ABORTED, so `reset role`
    raises InFailedSqlTransaction. Letting that propagate would REPLACE the
    original exception — destroying diagnosis on exactly the path where it
    matters most. Here the teardown is rigged to fail; the body's exception
    must still be what surfaces.
    """
    session = RecordingSession(fail_on="reset role")
    with pytest.raises(RuntimeError, match="the real failure"):
        with _role_cm(session, _WRITE_ROLE):
            raise RuntimeError("the real failure")


@pytest.mark.unit
def test_teardown_failure_on_a_clean_body_is_swallowed():
    """A teardown failure must not manufacture a failure that did not occur.

    SET LOCAL clears at COMMIT/ROLLBACK regardless, so a failed `reset role` is
    not a correctness problem — turning it into a raised exception would report
    a defect where there is none.
    """
    session = RecordingSession(fail_on="reset role")
    with _role_cm(session, _READ_ROLE):
        pass


# ---------------------------------------------------------------------------
# No default role argument (Sec requirement)
# ---------------------------------------------------------------------------
@pytest.mark.unit
def test_role_argument_is_required():
    """A default would make the privileged choice invisible at the call site —
    the engine-level defect in a different costume."""
    session = RecordingSession()
    with pytest.raises(TypeError):
        SBaseConn._role(None, session)
