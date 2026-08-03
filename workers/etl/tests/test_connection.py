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
import logging
import re

import pytest
import sqlalchemy as sqla

import pfin_back_etl as pfbe
from pfin_back_etl.connection import (
    TenantBoundConnection,
    TenantBindingError,
    _is_tenant_exempt,
    _statement_carries_users_id,
    _check_tenant_statement,
    _claims_carry_users_id,
    _statement_head,
    _IMPERSONATION_KEY,
    _JWT_CLAIMS_GUC,
    _JWT_CLAIM_SUB_GUC,
)
from pfin_back_etl.nav_daily import (
    _BIND_WRITE_TENANT,
    _SET_WRITE_ROLE,
    _CHECKPOINT_INSERT,
    _ARBITER_COLUMNS,
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
_ON_CONFLICT_TARGET_RE = re.compile(
    r"on\s+conflict\s*\(([^)]*)\)\s*do\s+(\w+)", re.IGNORECASE
)


def _parse_conflict_target(statement):
    """Extract (arbiter_columns, conflict_action) from an ON CONFLICT clause.

    Returns (None, None) when the statement has no *targeted* ON CONFLICT — which
    the fence below treats as a failure, since an untargeted form silently swallows
    violations of any future second unique constraint."""
    match = _ON_CONFLICT_TARGET_RE.search(" ".join(statement.split()))
    if match is None:
        return None, None
    columns = tuple(c.strip().lower() for c in match.group(1).split(",") if c.strip())
    return columns, match.group(2).lower()


@pytest.mark.unit
def test_checkpoint_insert_pins_arbiter_columns():
    """APP-SIDE PIN of the three-artifact arbiter invariant (SELF-214, Sec-ruled).

    THREE artifacts must agree, and they live in three places owned by two roles:
      1. `unique (users_id, nav_date)` on pfin.nav_daily          — 054 (Architect)
      2. `grant select (users_id, nav_date) … to service_role`    — 054 (Architect)
      3. the ON CONFLICT target inside `_CHECKPOINT_INSERT`       — this worker

    QA's battery pins 1↔3 DB-side by executing the production statement verbatim
    (which is what makes the targeted form self-fencing: you cannot have a passing
    battery and a broken statement). This test pins 3 against `_ARBITER_COLUMNS` —
    the worker's DECLARED expectation of what the constraint and grant carry — so
    the coupling breaks a step EARLIER, at Python unit-test time, before anything
    touches a database.

    Deliberately written to encode the INVARIANT, not the answer. The predecessor
    asserted "the conflict target must be absent", which was the then-correct
    conclusion — so when the ruling changed it inverted rather than adapted. This
    version keeps holding whatever the arbiter columns become: change the constraint,
    update `_ARBITER_COLUMNS`, and the test tells you the statement still disagrees.

    Note this canNOT see the DB. It proves the worker is internally consistent with
    its own declared contract; that the contract matches the live constraint and
    grant is QA's half."""
    columns, action = _parse_conflict_target(_CHECKPOINT_INSERT)

    assert columns is not None, (
        "_CHECKPOINT_INSERT must use the TARGETED `on conflict (…)` form. The "
        "untargeted form would silently swallow violations of any future second "
        "unique constraint instead of raising loudly."
    )
    assert columns == _ARBITER_COLUMNS, (
        f"ON CONFLICT target {columns} disagrees with the declared arbiter contract "
        f"{_ARBITER_COLUMNS}. These must match the `unique (…)` constraint AND the "
        f"column-level grant in 054 — a mismatch is a 42P10/42501 on the nightly "
        f"cron, which is precisely what this pin exists to catch pre-merge."
    )
    assert action == "nothing", (
        "the checkpoint must be DO NOTHING, never DO UPDATE — an UPDATE path trips "
        "054's append-only trigger."
    )


@pytest.mark.unit
@pytest.mark.parametrize(
    "statement,expected",
    [
        # The production shape — the constant itself, never a retyped copy, so this
        # fixture cannot drift out from under the statement it claims to parse.
        (_CHECKPOINT_INSERT, (("users_id", "nav_date"), "nothing")),
        # Whitespace/newline/case variants must parse identically.
        ("INSERT … ON  CONFLICT\n( Users_Id , Nav_Date ) DO   NOTHING",
         (("users_id", "nav_date"), "nothing")),
        # A drifted arbiter list — the case the pin exists to catch.
        ("insert … on conflict (users_id) do nothing", (("users_id",), "nothing")),
        # DO UPDATE — must be distinguishable from DO NOTHING.
        ("insert … on conflict (users_id, nav_date) do update set nav_value = 1",
         (("users_id", "nav_date"), "update")),
        # Untargeted — no arbiter list to pin.
        ("insert … on conflict do nothing", (None, None)),
        ("insert into pfin.nav_daily values (1)", (None, None)),
    ],
)
def test_parse_conflict_target(statement, expected):
    """The pin is only as good as its parser — so the parser is tested directly
    rather than trusted. A parser that silently returned (None, None) on the real
    statement would make the fence above vacuous while still passing."""
    assert _parse_conflict_target(statement) == expected


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
        _check_tenant_statement(
            info, _CHECKPOINT_INSERT, {"uid": _UID_A, "nav": 100}, _UID_A
        )

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
                _CHECKPOINT_INSERT,
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
        # 1. N7 defensive clear of the legacy singular GUC (impersonate() entry)
        _check_tenant_statement(
            info, f"select set_config('{_JWT_CLAIM_SUB_GUC}', NULL, true)", {}, _UID_A
        )
        # 2. set role authenticated (exempt)
        _check_tenant_statement(info, "set local role authenticated", {}, _UID_A)
        # 3. establish impersonation (claims carry A)
        _check_tenant_statement(info, _claims_stmt(), _claims_params(_UID_A), _UID_A)
        assert info[_IMPERSONATION_KEY] == _UID_A
        # 4. B7 write-tenant binding GUC — a SELECT-shaped setter issued WHILE
        #    impersonation is active. Must pass the B2 read-only fence.
        _check_tenant_statement(info, _BIND_WRITE_TENANT, {}, _UID_A)
        assert info[_IMPERSONATION_KEY] == _UID_A  # B7 op must not disturb the binding
        # 5. impersonated INVOKER read (no literal uid) — allowed via RLS binding
        _check_tenant_statement(
            info, "select pfin.fn_compute_nav(current_date, true)", {}, _UID_A
        )
        # 6. teardown claims + reset role
        _check_tenant_statement(
            info, f"select set_config('{_JWT_CLAIMS_GUC}', NULL, true)", {}, _UID_A
        )
        _check_tenant_statement(info, "reset role", {}, _UID_A)
        assert _IMPERSONATION_KEY not in info
        # 7. assume the ADR-023 write role (exempt prefix) — B1(c)
        _check_tenant_statement(info, _SET_WRITE_ROLE, {}, _UID_A)
        # 8. privileged literal write (service_role) — allowed via literal binding
        _check_tenant_statement(
            info,
            _CHECKPOINT_INSERT,
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


# --------------------------------------------------------------------------- #
# SELF-214 Sec joint-review B4 — strict equality on the claims `sub`.
#
# The vector is FIELD-POSITION, not UUID-substring: a claims blob whose `sub` is
# tenant B while tenant A's uid sits in any OTHER field would, under the old
# containment check, register an impersonation binding for A while the database
# resolves auth.uid() to B — so every subsequent bare read returns B's data on an
# A-bound connection. None of these existed before this change.
# --------------------------------------------------------------------------- #
class TestClaimsSubStrictEquality:
    """B4 — equality-on-`sub`, not containment."""

    @pytest.mark.unit
    def test_matching_sub_establishes_binding(self):
        """The happy path still works: sub == bound uid ⇒ binding established."""
        assert (
            _claims_carry_users_id(_claims_stmt(), _claims_params(_UID_A), _UID_A)
            is True
        )

    @pytest.mark.unit
    def test_foreign_sub_with_target_in_another_field_is_rejected(self):
        """THE B4 NEGATIVE TEST. sub = B, but A's uid appears in another field.
        Containment said 'binding for A'; equality-on-sub says no binding."""
        params = {
            "claims": json.dumps(
                {
                    "sub": _UID_B,
                    "role": "authenticated",
                    "aal": "aal2",
                    "app_metadata": {"impersonated_by": _UID_A},
                }
            )
        }
        assert _claims_carry_users_id(_claims_stmt(), params, _UID_A) is False

    @pytest.mark.unit
    def test_foreign_sub_in_other_field_does_not_bind_via_check(self):
        """Same vector through the real decision core: no binding is registered, so
        the following bare read fails closed instead of returning B's data."""
        info = {}
        params = {
            "claims": json.dumps(
                {"sub": _UID_B, "role": "authenticated", "aal": "aal2",
                 "email": f"{_UID_A}@example.test"}
            )
        }
        _check_tenant_statement(info, _claims_stmt(), params, _UID_A)
        assert _IMPERSONATION_KEY not in info
        with pytest.raises(TenantBindingError):
            _check_tenant_statement(
                info, "select pfin.fn_compute_nav(current_date, true)", {}, _UID_A
            )

    @pytest.mark.unit
    def test_inline_literal_claims_blob_uses_equality_too(self):
        """The inline-literal path (blob in the SQL text, no bound param) gets the
        same strict treatment — it must not degrade to containment."""
        blob = json.dumps({"sub": _UID_B, "other": _UID_A})
        stmt = f"select set_config('{_JWT_CLAIMS_GUC}', '{blob}', true)"
        assert _claims_carry_users_id(stmt, {}, _UID_A) is False
        assert _claims_carry_users_id(
            f"select set_config('{_JWT_CLAIMS_GUC}', "
            f"'{json.dumps({'sub': _UID_A})}', true)",
            {},
            _UID_A,
        ) is True

    @pytest.mark.unit
    def test_null_clear_is_not_a_parse_failure(self):
        """Teardown carries no payload at all — False, and it must NOT take the
        unparseable/WARNING branch (that would warn on every single teardown)."""
        assert (
            _claims_carry_users_id(
                f"select set_config('{_JWT_CLAIMS_GUC}', NULL, true)", {}, _UID_A
            )
            is False
        )

    @pytest.mark.unit
    def test_unparseable_payload_falls_back_to_containment(self, caplog):
        """Sec's required fallback: a present-but-unparseable payload degrades to
        containment AND logs at WARNING."""
        params = {"claims": '{"sub": ' + _UID_A + '  <<not json>>'}
        with caplog.at_level(logging.WARNING, logger="pfin_etl"):
            assert _claims_carry_users_id(_claims_stmt(), params, _UID_A) is True
        assert any("CONTAINMENT" in rec.message for rec in caplog.records)


# --------------------------------------------------------------------------- #
# SELF-214 Sec joint-review B2 — impersonate() is a READ-ONLY primitive.
#
# Inside the block current_user = 'authenticated' AND the synthetic claim is
# aal2, which satisfies ADR-029 Decision 6's MB-1 downgrade guard and every other
# aal2-gated write path. Both directions are asserted: the sanctioned binding ops
# must PASS (a naive fence that treated `select set_config(...)` as a write would
# deadlock the whole design), and real DML must be REJECTED.
# --------------------------------------------------------------------------- #
class TestImpersonationReadOnlyFence:
    """B2 — write verbs rejected while impersonation is active."""

    def _impersonated(self):
        info = {}
        _check_tenant_statement(info, _claims_stmt(), _claims_params(_UID_A), _UID_A)
        assert info[_IMPERSONATION_KEY] == _UID_A
        return info

    # ---- direction 1: sanctioned ops MUST pass -------------------------------
    @pytest.mark.unit
    @pytest.mark.parametrize(
        "statement",
        [
            _BIND_WRITE_TENANT,  # B7 GUC — the exact string nav_daily issues
            "select pfin.fn_compute_nav(current_date, true)",
            "SELECT   pfin.fn_compute_nav(current_date, true)",
            "with base as (select 1 as n) select n from base",
            "set local role authenticated",
            "show server_version",
        ],
    )
    def test_sanctioned_ops_pass_while_impersonating(self, statement):
        """Reads, the B7 binding setter, and session-setup ops are NOT writes."""
        info = self._impersonated()
        _check_tenant_statement(info, statement, {}, _UID_A)

    @pytest.mark.unit
    def test_b7_binding_op_survives_the_fence_and_keeps_the_binding(self):
        """The B2/B7 interaction, asserted directly: the B7 set_config is a SELECT
        invoking a setter and runs WHILE impersonation is active. It must neither be
        blocked as a write nor mistaken for a claims op that clears the binding."""
        info = self._impersonated()
        _check_tenant_statement(info, _BIND_WRITE_TENANT, {}, _UID_A)
        assert info[_IMPERSONATION_KEY] == _UID_A

    @pytest.mark.unit
    def test_claims_teardown_still_works_under_the_fence(self):
        """Teardown must not be caught by the write fence (branch order proof)."""
        info = self._impersonated()
        _check_tenant_statement(
            info, f"select set_config('{_JWT_CLAIMS_GUC}', NULL, true)", {}, _UID_A
        )
        assert _IMPERSONATION_KEY not in info

    # ---- direction 2: real DML MUST be rejected ------------------------------
    @pytest.mark.unit
    @pytest.mark.parametrize(
        "statement",
        [
            # The MB-1 vector Sec named: an aal2-gated mfa_policy downgrade.
            "update pfin.user_settings set mfa_policy = 'none' where users_id = :uid",
            _CHECKPOINT_INSERT,
            "delete from pfin.account where users_id = :uid",
            "merge into pfin.account using x on true when matched then delete",
            "truncate pfin.nav_daily",
            "alter table pfin.nav_daily disable trigger all",
            "drop table pfin.nav_daily",
            "grant insert on pfin.nav_daily to authenticated",
            "copy pfin.nav_daily from stdin",
            "create table pfin.evil (x int)",
            "call pfin.some_proc()",
            "do $$ begin perform 1; end $$",
            # Data-modifying CTE hiding a write behind a read head.
            "with moved as (delete from pfin.nav_daily returning *) select * from moved",
            "with x as (select 1) insert into pfin.nav_daily select * from x",
        ],
    )
    def test_writes_rejected_while_impersonating(self, statement):
        """Every write/DDL shape fails closed inside the impersonated block —
        INCLUDING the literal-users_id INSERT, which would otherwise be admitted by
        the direct-write binding. The fence sits before that check deliberately."""
        info = self._impersonated()
        with pytest.raises(TenantBindingError, match="READ-ONLY"):
            _check_tenant_statement(info, statement, {"uid": _UID_A}, _UID_A)

    @pytest.mark.unit
    def test_write_allowed_once_impersonation_is_torn_down(self):
        """The fence is scoped to the impersonated block, not the connection: the
        real worker INSERT still passes after teardown."""
        info = self._impersonated()
        _check_tenant_statement(info, "reset role", {}, _UID_A)
        _check_tenant_statement(info, _SET_WRITE_ROLE, {}, _UID_A)
        _check_tenant_statement(
            info,
            _CHECKPOINT_INSERT,
            {"uid": _UID_A, "nav": 1},
            _UID_A,
        )

    @pytest.mark.unit
    def test_escalate_then_write_inside_block_still_rejected(self):
        """`set local role service_role` stays exempt-prefixed, but it does NOT clear
        the impersonation key — so a write following it inside the block is still
        rejected. Escalate-then-write does not slip through."""
        info = self._impersonated()
        _check_tenant_statement(info, _SET_WRITE_ROLE, {}, _UID_A)
        assert info[_IMPERSONATION_KEY] == _UID_A
        with pytest.raises(TenantBindingError, match="READ-ONLY"):
            _check_tenant_statement(
                info,
                _CHECKPOINT_INSERT,
                {"uid": _UID_A, "nav": 1},
                _UID_A,
            )

    @pytest.mark.unit
    def test_unrecognized_statement_head_fails_closed(self):
        """A statement that does not begin with an identifier-shaped token (e.g. a
        leading comment) is not provably a read, so it is rejected."""
        info = self._impersonated()
        with pytest.raises(TenantBindingError, match="READ-ONLY"):
            _check_tenant_statement(
                info, "-- sneaky\ninsert into pfin.nav_daily values (1)", {}, _UID_A
            )

    @pytest.mark.unit
    def test_fence_is_inactive_without_impersonation(self):
        """No behaviour change on the non-impersonated path: the direct-write
        contract is untouched."""
        info = {}
        _check_tenant_statement(
            info,
            _CHECKPOINT_INSERT,
            {"uid": _UID_A, "nav": 1},
            _UID_A,
        )

    @pytest.mark.unit
    def test_column_named_like_a_write_verb_is_not_a_false_positive(self):
        """`updated_at` tokenizes as one word — it must not trip the CTE scan."""
        info = self._impersonated()
        _check_tenant_statement(
            info,
            "with recent as (select updated_at from pfin.account) select * from recent",
            {},
            _UID_A,
        )

    @pytest.mark.unit
    @pytest.mark.parametrize(
        "statement,expected",
        [
            ("  select 1", "select"),
            ("\n\tWITH x AS (select 1) select 1", "with"),
            ("INSERT INTO t VALUES (1)", "insert"),
            ("-- comment\nselect 1", ""),
            ("", ""),
        ],
    )
    def test_statement_head_parsing(self, statement, expected):
        assert _statement_head(statement) == expected


# --------------------------------------------------------------------------- #
# SELF-214 Sec joint-review N7 — the legacy singular GUC.
#
# auth.uid() reads request.jwt.claim.sub in PREFERENCE to the request.jwt.claims
# blob impersonate() sets, so a value there resolves EVERY tenant to one user
# while the Python variable looks correct throughout.
# --------------------------------------------------------------------------- #
class TestLegacySingularGuc:
    """N7 — clear permitted, set forbidden."""

    @pytest.mark.unit
    def test_the_two_guc_names_are_disjoint(self):
        """The branch order in _check_tenant_statement relies on this. Asserted, not
        assumed — the whole finding came from reasoning past an unchecked premise."""
        assert _JWT_CLAIMS_GUC not in _JWT_CLAIM_SUB_GUC
        assert _JWT_CLAIM_SUB_GUC not in _JWT_CLAIMS_GUC

    @pytest.mark.unit
    def test_null_clear_is_permitted(self):
        """impersonate()'s defensive entry statement must pass the assertion — it
        carries no users_id and runs before any binding exists."""
        info = {}
        _check_tenant_statement(
            info, f"select set_config('{_JWT_CLAIM_SUB_GUC}', NULL, true)", {}, _UID_A
        )
        assert _IMPERSONATION_KEY not in info

    @pytest.mark.unit
    def test_clear_does_not_disturb_an_active_binding(self):
        info = {_IMPERSONATION_KEY: _UID_A}
        _check_tenant_statement(
            info, f"select set_config('{_JWT_CLAIM_SUB_GUC}', NULL, true)", {}, _UID_A
        )
        assert info[_IMPERSONATION_KEY] == _UID_A

    @pytest.mark.unit
    @pytest.mark.parametrize(
        "statement,params",
        [
            (f"select set_config('{_JWT_CLAIM_SUB_GUC}', :sub, true)", {"sub": _UID_A}),
            (f"select set_config('{_JWT_CLAIM_SUB_GUC}', '{_UID_B}', true)", {}),
            (f"set local \"{_JWT_CLAIM_SUB_GUC}\" = '{_UID_A}'", {}),
        ],
    )
    def test_setting_the_legacy_guc_fails_closed(self, statement, params):
        """Even setting it to the CORRECT tenant is rejected — the precedence hazard
        is the point, and worker code has no legitimate reason to write it."""
        info = {}
        with pytest.raises(TenantBindingError, match="legacy singular GUC"):
            _check_tenant_statement(info, statement, params, _UID_A)
