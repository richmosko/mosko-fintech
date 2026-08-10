"""
Project:       pfin-back-etl
Author:        Rich Mosko (mosko-fintech Backend)

Description:
    The integration-fixture failure policy — BACKLOG §7.6 S16 — extracted from
    `conftest.py` so the CALL SITE is a testable unit.

    ⚠ WHY THIS MODULE EXISTS, WHICH IS A LESSON NOT A PREFERENCE. The first
    version of this policy lived inline in `conftest.py`, with a separate
    `is_database_unreachable()` predicate that the tests pinned thoroughly.
    QA then ran the inversion nobody had: revert both fixtures to
    `except Exception: pytest.skip(...)` and **all 14 tests still passed**
    (reproduced: 14 passed, 0 failed). The predicate was pinned; that the
    fixtures CALLED it was not. The entire concealment shape S16 exists to
    stop was restorable with a fully green suite.

    Both of the original inversions mutated the PREDICATE. The mutation that
    mattered was at the CALL SITE — which is exactly the class of defect where
    a test suite and the code it guards share an author's frame.

    So `construct_or_skip()` is the unit under test, and the fixtures are thin
    enough to be read at a glance. Testing it by INJECTING a raiser is stronger
    than asserting on `inspect.getsource(...)`, which is a syntactic proxy for
    behaviour rather than the behaviour.
"""

import logging
import os

import pytest
import sqlalchemy as sqla
from sqlalchemy import exc as sqla_exc

logger = logging.getLogger("pfin_etl")


# ---------------------------------------------------------------------------
# THE SKIP SURFACE
# ---------------------------------------------------------------------------
# A fixture may SKIP for exactly one reason — THERE IS NO DATABASE TO TALK TO.
# Every other failure is a defect and must PROPAGATE.
#
# ⚠ WHY isinstance AND NOT SQLSTATE. The obvious discriminator is "the server
# answered and refused" vs "no server answered". MEASURED against psycopg2 over
# the SCRAM path: `pgcode` is None for connection refused, password
# authentication failed, nonexistent role, and NOLOGIN role alike. No
# discriminator is available there, so this also deliberately does NOT match on
# message text (assert by code, never by message).
#
# ⚠ THAT MEASUREMENT IS PATH-SCOPED, AND AN EARLIER FORM OF THIS COMMENT
# OVERSTATED IT AS "EVERY connect-time failure". Corrected, because the
# over-broad version was wrong in an instructive way. The local stack's
# published `:54322` is a DOCKER NAT HOP — a host-side client presents to the
# server as `192.168.65.1`, NOT loopback (verified via
# `select host(inet_client_addr())`) — so it matches a `scram-sha-256` line and
# CANNOT REACH the `host all all 127.0.0.1/32 trust` line that also exists in
# that same `pg_hba.conf` (verified in-container). On the TRUST path the server
# DOES emit distinctive errors — `role "pfin_etl" is not permitted to log in`,
# `role "…" does not exist`, both measured from inside the container — so a
# discriminator plausibly exists there. The generic collapse is the SCRAM path's
# anti-enumeration behaviour, not a protocol-wide fact. A measurement that
# cannot reach the path it generalises about is not evidence about that path.
#
# WHY THE DESIGN IS UNCHANGED ANYWAY, which is the part that matters: this code
# never runs on the trust path. Local dev reaches the database through the NAT
# hop (scram); production is a remote TLS connection (scram). On every path this
# policy actually executes on, no discriminator is available.
#
# RESIDUAL, stated rather than left implicit: psycopg2's `pgcode` on the TRUST
# path is UNMEASURED — the DB container has no Python and the trust path is not
# reachable from the host. Do not assume it is None there.
#
# Consequence, stated rather than discovered later: a missing credential FAILS
# this lane instead of skipping it, because `load_env_variables` raises
# ValueError. That is the S12 defect becoming visible, and it is intended.
_UNREACHABLE_EXC = (sqla_exc.OperationalError,)

#: Set to a role name (e.g. `pfin_etl`) to ASSERT which login role the lane ran
#: as, AND to assert the privilege attributes that make the role meaningful.
ROLE_ENV_VAR = "PFIN_TEST_EXPECT_ROLE"

#: Role attributes that must be FALSE when the lane is role-constrained. Each
#: for a distinct reason — see check_role_attributes().
_FORBIDDEN_ROLE_ATTRS = ("rolsuper", "rolbypassrls", "rolinherit")

_IDENTITY_SQL = "select session_user, current_user"
_ATTRS_SQL = (
    "select rolsuper, rolbypassrls, rolinherit "
    "from pg_roles where rolname = session_user"
)


def is_database_unreachable(exc):
    """True only when the failure means *there is no database to talk to*."""
    return isinstance(exc, _UNREACHABLE_EXC)


def construct_or_skip(what, make):
    """Construct via `make()`, applying the failure policy. THE UNIT UNDER TEST.

    `make` is a zero-argument callable so this can be exercised by injecting a
    raiser, without a database and without patching the fixtures.

    ⚠ AN UNREACHABLE DATABASE IS A FAILURE, NOT A SKIP, WHEN THE RUN IS
    ROLE-CONSTRAINED. A wrong `DATABASE_URL` and no database at all are the
    same `OperationalError`, so a run pointed at the wrong host would otherwise
    report green-with-skips and read as a pass. Declaring which role you expect
    is declaring that you expect a database.
    """
    try:
        return make()
    except Exception as e:
        if is_database_unreachable(e):
            expected = os.getenv(ROLE_ENV_VAR)
            if expected:
                raise AssertionError(
                    f"No database reachable for {what}, but {ROLE_ENV_VAR}="
                    f"{expected!r} is set. Declaring an expected role declares "
                    f"that a database is expected — skipping here would report "
                    f"green-with-skips for a run pointed at the wrong host, "
                    f"which is indistinguishable from a pass. Original: {e}"
                ) from e
            pytest.skip(f"No database reachable for {what}: {e}")
        raise


def check_expected_role(actual_role, expected_role):
    """Pure comparison. None when unconstrained; raises on mismatch."""
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


def check_role_attributes(attrs, expected_role):
    """Assert the login role's privilege ATTRIBUTES, not just its name.

    ⚠ A ROLE NAME PROVES NOTHING ABOUT PRIVILEGE. `session_user == 'pfin_etl'`
    is satisfied by a `pfin_etl` that is superuser, or BYPASSRLS, or
    INHERITing. Each is disqualifying for a different reason:

      • rolinherit  — THE ESSENTIAL ONE. An inheriting login holds its granted
                      privileges with NO `SET ROLE` at all, so the S17
                      acceptance test would PASS AGAINST AN UNFIXED
                      `SBaseConn`. A test that can go green without the fix is
                      not evidence for the fix.
      • rolbypassrls— voids the tenant fence on `authenticated` reads
                      SILENTLY, making the ADR-023 read-partition rule inert.
      • rolsuper    — the attribute that concealed S17 in the first place:
                      every local run was `postgres`, which never needs a role
                      assumption.

    ⚠ COMPOSITION, so neither half gets "simplified" away later: this asserts
    the role's ATTRIBUTES. Control (i)'s RED asserts that a bare query actually
    FAILS 42501 before any `SET ROLE`. Together they prove NOINHERIT is doing
    the work rather than merely being declared. NEITHER IS SUFFICIENT ALONE.
    """
    if not expected_role:
        return None
    offenders = sorted(name for name, value in attrs.items() if value)
    if offenders:
        raise AssertionError(
            f"login role {expected_role!r} has {', '.join(offenders)} set. "
            f"All of {', '.join(_FORBIDDEN_ROLE_ATTRS)} must be FALSE for a "
            f"role-privilege result to mean anything — an inheriting or "
            f"superuser login passes the S17 acceptance test WITHOUT the fix."
        )
    return attrs


def report_login_identity(engine, what):
    """Log the effective login identity; enforce ROLE_ENV_VAR when set.

    Privilege-free by construction: `session_user` / `current_user` are
    built-ins, and `pg_roles` is world-readable — so this runs before any role
    is assumed, on a NOINHERIT login that holds nothing.
    """
    with engine.connect() as conn:
        session_user, current_user = conn.execute(sqla.text(_IDENTITY_SQL)).one()
        row = conn.execute(sqla.text(_ATTRS_SQL)).one()
    attrs = dict(zip(_FORBIDDEN_ROLE_ATTRS, row))
    logger.info(
        f"{what}: session_user={session_user!r} current_user={current_user!r} "
        f"attrs={attrs}"
    )
    expected = os.getenv(ROLE_ENV_VAR)
    check_expected_role(session_user, expected)
    check_role_attributes(attrs, expected)
    return session_user
