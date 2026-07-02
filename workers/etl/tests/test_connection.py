"""
Project:       pfin-back-etl
Author:        Rich Mosko (mosko-fintech Backend)

Description:
    Unit tests for TenantBoundConnection (SELF-193 / Lock 13 mod #3).

    These are `unit`-tier: they use an in-memory SQLite engine, so they need
    no .env credentials and no live Postgres. They verify the V1.0 honest
    scaffold — the single sanctioned engine factory (`.system()`), the
    scaffolded-but-dormant per-tenant assertion (`.for_tenant()`), and the
    dependency-blocked mod #4 audit-log stub.

    Covers RT-09 sub-case a/b territory: the class is importable and `.system()`
    returns a working engine.
"""

import pytest
import sqlalchemy as sqla

import pfin_back_etl as pfbe
from pfin_back_etl.connection import (
    TenantBoundConnection,
    TenantBindingError,
    _is_tenant_exempt,
    _statement_carries_users_id,
)

# In-memory SQLite — no creds, no Postgres. Engine creation + execution work
# identically for exercising the factory + the assertion event listener.
_SQLITE_URL = "sqlite://"


@pytest.mark.unit
def test_class_is_importable_from_package():
    """The fence anchors on the TenantBoundConnection class declaration; the
    symbol must be a real, importable name re-exported from the package root."""
    assert TenantBoundConnection is pfbe.TenantBoundConnection
    assert TenantBindingError is pfbe.TenantBindingError


@pytest.mark.unit
def test_system_returns_working_engine():
    """`.system()` (the V1.0 usage) returns a real, usable SQLAlchemy engine."""
    tbc = TenantBoundConnection.system(_SQLITE_URL)
    engine = tbc.engine
    assert isinstance(engine, sqla.Engine)
    assert tbc.is_system is True
    with engine.connect() as conn:
        assert conn.execute(sqla.text("select 1")).scalar() == 1


@pytest.mark.unit
def test_system_preserves_nullpool():
    """NullPool posture is preserved through the factory (matches the pre-TBC
    engine; short-lived cron process, no cross-run pooling)."""
    engine = TenantBoundConnection.system(_SQLITE_URL).engine
    assert isinstance(engine.pool, sqla.pool.NullPool)


@pytest.mark.unit
def test_for_tenant_rejects_missing_users_id():
    """`.for_tenant()` requires a real users_id — None routes callers to
    `.system()` instead of silently binding a null tenant."""
    with pytest.raises(ValueError):
        TenantBoundConnection.for_tenant(_SQLITE_URL, None)


@pytest.mark.unit
def test_for_tenant_is_not_system():
    """A per-tenant connection is not in system mode."""
    tbc = TenantBoundConnection.for_tenant(_SQLITE_URL, users_id=42)
    assert tbc.is_system is False
    assert isinstance(tbc.engine, sqla.Engine)


@pytest.mark.unit
def test_system_mode_does_not_assert_tenant():
    """System mode registers NO per-tenant assertion — a tenant-less statement
    executes cleanly (global market-reference writes have no users_id)."""
    engine = TenantBoundConnection.system(_SQLITE_URL).engine
    with engine.connect() as conn:
        # No users_id anywhere; must NOT raise in system mode.
        assert conn.execute(sqla.text("select 1")).scalar() == 1


@pytest.mark.unit
def test_for_tenant_assertion_is_live_and_fails_closed():
    """The dormant per-tenant assertion, when a `.for_tenant()` engine IS used,
    fails closed on a statement that does not carry the bound users_id.
    (No production caller in V1.0; this proves the scaffold is real, not
    vacuous.)"""
    engine = TenantBoundConnection.for_tenant(_SQLITE_URL, users_id=7).engine
    with engine.connect() as conn:
        with pytest.raises(TenantBindingError):
            conn.execute(sqla.text("select 42"))


@pytest.mark.unit
def test_for_tenant_assertion_passes_when_users_id_present():
    """The assertion passes when the bound users_id is carried as a parameter."""
    engine = TenantBoundConnection.for_tenant(_SQLITE_URL, users_id=7).engine
    with engine.connect() as conn:
        result = conn.execute(
            sqla.text("select :uid"), {"uid": 7}
        ).scalar()
        assert result == 7


@pytest.mark.unit
def test_emit_audit_log_is_dependency_blocked_stub():
    """mod #4 audit-log is not yet wired (blocked on Architect's
    pfin.plaid_sync_audit + DEFINER helper). The stub must raise, not
    silently no-op."""
    tbc = TenantBoundConnection.system(_SQLITE_URL)
    with pytest.raises(NotImplementedError):
        tbc.emit_audit_log(session=None, event={"kind": "noop"})


# --------------------------------------------------------------------------- #
# Helper-level coverage for the dormant assertion predicate.
# --------------------------------------------------------------------------- #
@pytest.mark.unit
@pytest.mark.parametrize(
    "statement",
    [
        "BEGIN",
        "commit",
        "ROLLBACK",
        "SET search_path = ''",
        "SHOW server_version",
        "select pg_backend_pid()",
    ],
)
def test_tenant_exempt_statements(statement):
    """Transaction-control / session-setup / introspection statements carry no
    tenant predicate and are exempt from the assertion."""
    assert _is_tenant_exempt(statement) is True


@pytest.mark.unit
def test_non_exempt_statement_requires_users_id():
    """A normal DML/SELECT is not exempt and must carry the users_id."""
    assert _is_tenant_exempt("select * from pfin.nav") is False
    assert (
        _statement_carries_users_id(
            "select * from pfin.nav where users_id = :uid", {"uid": 7}, 7
        )
        is True
    )
    assert (
        _statement_carries_users_id(
            "select * from pfin.nav", {}, 7
        )
        is False
    )
