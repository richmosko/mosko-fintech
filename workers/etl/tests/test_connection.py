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

import json

import pytest
import sqlalchemy as sqla

import pfin_back_etl as pfbe
from pfin_back_etl.connection import (
    TenantBoundConnection,
    TenantBindingError,
    _is_tenant_exempt,
    _statement_carries_users_id,
    _check_tenant_statement,
    _IMPERSONATION_KEY,
    _JWT_CLAIMS_GUC,
)

# Two synthetic tenant uuids for the impersonation / cross-tenant assertion tests.
_UID_A = "11111111-1111-1111-1111-111111111111"
_UID_B = "22222222-2222-2222-2222-222222222222"


def _claims_stmt():
    """The impersonation-establishing statement shape emitted by impersonate()."""
    return f"select set_config('{_JWT_CLAIMS_GUC}', :claims, true)"


def _claims_params(uid):
    # Mirrors impersonate(): includes the aal2 claim required by the 025 backstop
    # (054 WORKER NOTE) so a totp/passkey user's underlying reads are not zeroed.
    return {"claims": json.dumps({"sub": uid, "role": "authenticated", "aal": "aal2"})}

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


# --------------------------------------------------------------------------- #
# SELF-214 W-1 — firmed impersonation-aware per-tenant assertion.
#   _check_tenant_statement is the pure decision core (mutates an `info` dict =
#   conn.info; raises TenantBindingError on an unbound-tenant statement).
# --------------------------------------------------------------------------- #
class TestImpersonationAssertion:
    """Fail-closed coverage for the firmed for_tenant() assertion (W-1)."""

    @pytest.mark.unit
    def test_bare_read_without_binding_fails_closed(self):
        """A read carrying no users_id and no impersonation is rejected — the
        fence that stops a for_tenant(A) connection acting tenant-less."""
        info = {}
        with pytest.raises(TenantBindingError):
            _check_tenant_statement(
                info, "select pfin.fn_compute_nav(current_date, true)", {}, _UID_A
            )

    @pytest.mark.unit
    def test_claims_op_establishes_impersonation(self):
        """set_config('request.jwt.claims', …sub=A…) carrying the bound uid marks
        impersonation active for A on the connection."""
        info = {}
        _check_tenant_statement(info, _claims_stmt(), _claims_params(_UID_A), _UID_A)
        assert info[_IMPERSONATION_KEY] == _UID_A

    @pytest.mark.unit
    def test_impersonated_read_is_allowed(self):
        """Once impersonation for A is active, a bare INVOKER read (no literal uid)
        is allowed — RLS/auth.uid() enforces isolation."""
        info = {}
        _check_tenant_statement(info, _claims_stmt(), _claims_params(_UID_A), _UID_A)
        # Must NOT raise:
        _check_tenant_statement(
            info, "select pfin.fn_compute_nav(current_date, true)", {}, _UID_A
        )

    @pytest.mark.unit
    def test_literal_write_allowed_without_impersonation(self):
        """The nav_daily INSERT carries users_id literally → allowed as a direct
        write even after impersonation is torn down (it runs as service_role)."""
        info = {}
        stmt = (
            "insert into pfin.nav_daily (users_id, nav_date, nav_value) "
            "values (:uid, current_date, :nav) "
            "on conflict (users_id, nav_date) do nothing"
        )
        _check_tenant_statement(info, stmt, {"uid": _UID_A, "nav": 100}, _UID_A)

    @pytest.mark.unit
    def test_cross_tenant_impersonation_rejected(self):
        """A connection bound to A whose impersonation somehow reads as B still
        rejects a bare read — impersonation for the WRONG tenant is not a pass."""
        info = {_IMPERSONATION_KEY: _UID_B}
        with pytest.raises(TenantBindingError):
            _check_tenant_statement(
                info, "select pfin.fn_compute_nav(current_date, true)", {}, _UID_A
            )

    @pytest.mark.unit
    def test_cross_tenant_literal_rejected(self):
        """A statement naming a DIFFERENT tenant (B) on an A-bound connection, with
        no impersonation, fails closed."""
        info = {}
        with pytest.raises(TenantBindingError):
            _check_tenant_statement(
                info,
                "insert into pfin.nav_daily (users_id, nav_date, nav_value) "
                "values (:uid, current_date, :nav)",
                {"uid": _UID_B, "nav": 100},
                _UID_A,
            )

    @pytest.mark.unit
    def test_claims_clear_tears_down_impersonation(self):
        """Clearing the JWT claims (NULL — no uid) removes the impersonation, so a
        subsequent bare read fails closed again."""
        info = {_IMPERSONATION_KEY: _UID_A}
        _check_tenant_statement(
            info,
            f"select set_config('{_JWT_CLAIMS_GUC}', NULL, true)",
            {},
            _UID_A,
        )
        assert _IMPERSONATION_KEY not in info
        with pytest.raises(TenantBindingError):
            _check_tenant_statement(
                info, "select pfin.fn_compute_nav(current_date, true)", {}, _UID_A
            )

    @pytest.mark.unit
    def test_reset_role_tears_down_impersonation(self):
        """RESET ROLE tears down impersonation (defensive teardown)."""
        info = {_IMPERSONATION_KEY: _UID_A}
        _check_tenant_statement(info, "reset role", {}, _UID_A)
        assert _IMPERSONATION_KEY not in info

    @pytest.mark.unit
    def test_full_worker_transaction_sequence(self):
        """End-to-end: the exact statement sequence the NAV worker issues in one
        for_tenant(A) transaction must all pass through the assertion with a single
        shared info dict, and the impersonation must be torn down before the write.
        """
        info = {}
        # 1. set role authenticated (exempt)
        _check_tenant_statement(info, "set local role authenticated", {}, _UID_A)
        # 2. establish impersonation (claims carry A)
        _check_tenant_statement(info, _claims_stmt(), _claims_params(_UID_A), _UID_A)
        assert info[_IMPERSONATION_KEY] == _UID_A
        # 3. impersonated INVOKER read (no literal uid) — allowed via RLS binding
        _check_tenant_statement(
            info, "select pfin.fn_compute_nav(current_date, true)", {}, _UID_A
        )
        # 4. teardown claims + reset role
        _check_tenant_statement(
            info, f"select set_config('{_JWT_CLAIMS_GUC}', NULL, true)", {}, _UID_A
        )
        _check_tenant_statement(info, "reset role", {}, _UID_A)
        assert _IMPERSONATION_KEY not in info
        # 5. privileged literal write (service_role) — allowed via literal binding
        _check_tenant_statement(
            info,
            "insert into pfin.nav_daily (users_id, nav_date, nav_value) "
            "values (:uid, current_date, :nav) "
            "on conflict (users_id, nav_date) do nothing",
            {"uid": _UID_A, "nav": 12345.67},
            _UID_A,
        )

    @pytest.mark.unit
    def test_impersonate_rejects_system_mode(self):
        """impersonate() requires a for_tenant()-bound TBC — a system-mode TBC has
        no tenant, so entering the context raises before touching the connection."""
        tbc = TenantBoundConnection.system(_SQLITE_URL)
        with pytest.raises(TenantBindingError):
            with tbc.impersonate(conn=None):
                pass
