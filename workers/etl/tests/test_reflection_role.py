"""
Project:       pfin-back-etl
Author:        Rich Mosko (mosko-fintech Backend)

Description:
    Regression tests for the ROLE ASSUMED DURING REFLECTION — BACKLOG §7.6 S17.

    ⚠ WHY THIS FILE EXISTS. The S17 fix wrapped every data method in `_role()`
    and MISSED THE STATEMENT THAT RUNS FIRST. `metadata.reflect()` lives in
    `_sbase_setup`, called from `__init__`, ahead of every data path — so under
    the production login `PFinBackend()` died at construction with
    `permission denied for schema pfin`, and no data-layer test could observe
    it because none of them got that far.

    It was found by a HUMAN RUNNING THE ASSEMBLED PATH, which is the argument
    S10 was filed to make. Nothing in the suite caught it, and the suite was
    green.

    The fault is schema `USAGE`, one gate EARLIER than the table privileges
    S17 was filed against:
        has_schema_privilege('pfin_etl','pfin','USAGE')      -> f
        has_schema_privilege('authenticated','pfin','USAGE') -> t

    Tier `pgtest`: needs a real Postgres, no credentials, no project schema.
"""

import os

import pytest
import sqlalchemy as sqla

from pfin_back_etl.core import _READ_ROLE, _ROLE_ALLOWLIST, SBaseConn

_PG_URL_ENV = "PFIN_PGTEST_URL"


@pytest.fixture(scope="module")
def pg_url():
    url = os.getenv(_PG_URL_ENV)
    if not url:
        if os.getenv("CI"):
            raise AssertionError(
                f"{_PG_URL_ENV} is unset under CI — skipping would report green "
                f"for a lane that ran nothing."
            )
        pytest.skip(f"{_PG_URL_ENV} unset — no Postgres for the pgtest tier")
    return url


@pytest.mark.pgtest
def test_reflection_assumes_the_read_role(pg_url, monkeypatch):
    """⚠ THE REGRESSION. Construction must assume a role BEFORE reflecting.

    Spies on `_role` rather than asserting on source text: what must hold is
    that the role is actually assumed on the reflecting connection, not that
    some particular line appears in `_sbase_setup`. A source-text assertion
    would pass a refactor that moved reflection back outside the block.
    """
    seen = []
    original = SBaseConn._role

    def spy(self, session, role):
        seen.append(role)
        return original(self, session, role)

    monkeypatch.setattr(SBaseConn, "_role", spy)

    url = sqla.make_url(pg_url)
    for key, value in {
        "PFIN_DB_USER": url.username,
        "PFIN_DB_PASSWORD": url.password,
        "PFIN_DB_HOST": url.host,
        "PFIN_DB_PORT": str(url.port),
        "PFIN_DB_NAME": url.database,
        "PFIN_DB_SSLMODE": "disable",
    }.items():
        monkeypatch.setenv(key, value)

    import pfin_back_etl as pfbe

    pfbe.PFinBackend()

    assert seen, (
        "construction assumed NO role — reflection runs privilege-less and "
        "fails `permission denied for schema pfin` under the production login"
    )
    assert seen[0] == _READ_ROLE, (
        f"the FIRST role assumed during construction was {seen[0]!r}; "
        f"reflection is a read and must assume {_READ_ROLE!r}"
    )


@pytest.mark.pgtest
def test_reflection_needs_schema_usage_at_all(pg_url):
    """⚠ NON-VACUITY, and it pins the MECHANISM the fix depends on.

    Sec's NOTE 6 ruled that `_sbase_setup` reflects from world-readable
    `pg_catalog`, so construction succeeds privilege-less and the fault always
    surfaces at first DML. MEASURED FALSE — the dialect's reflection query
    filters on the schema, and Postgres requires USAGE to inspect a schema's
    objects, so CONSTRUCTION is the fault site.

    Without this, the test above would pass just as happily on a database where
    reflection never needed a privilege at all — proving nothing about why the
    role assumption is required.
    """
    engine = sqla.create_engine(pg_url)
    with engine.connect() as conn:
        with conn.begin():
            conn.execute(sqla.text("create schema if not exists pgtest_norole"))
            conn.execute(
                sqla.text("create table if not exists pgtest_norole.t(x int)")
            )
            conn.execute(sqla.text("drop role if exists pgtest_nousage"))
            conn.execute(sqla.text("create role pgtest_nousage nologin noinherit"))
            granted = conn.execute(
                sqla.text(
                    "select has_schema_privilege('pgtest_nousage', "
                    "'pgtest_norole', 'USAGE')"
                )
            ).scalar()
            conn.rollback()

    assert granted is False, (
        "a role with no explicit grant should NOT have USAGE on the schema — "
        "if this is True, the environment grants USAGE broadly and the "
        "privilege premise behind the role assumption no longer holds here"
    )


@pytest.mark.pgtest
def test_read_role_is_the_least_privileged_that_reflects(pg_url):
    """Why `authenticated` and not `service_role`, asserted rather than argued.

    The hazard that made this worth measuring: if the less-privileged role saw
    FEWER objects, reflection would silently produce a PARTIAL base and automap
    would omit tables — failing later, elsewhere, confusingly. This pins that
    both candidate roles reflect the SAME object set, which is what makes
    choosing the least-privileged one safe rather than merely tidy.
    """
    engine = sqla.create_engine(pg_url)

    def reflect_as(role):
        md = sqla.MetaData()
        with engine.connect() as conn:
            with conn.begin():
                conn.execute(sqla.text(f"set local role {role}"))
                md.reflect(bind=conn, schema="pfin")
                conn.rollback()
        return set(md.tables)

    assert _ROLE_ALLOWLIST == {"authenticated", "service_role"}
    read_set = reflect_as(_READ_ROLE)
    write_set = reflect_as("service_role")

    assert read_set, "the read role reflected nothing — schema absent or no USAGE"
    assert read_set == write_set, (
        f"the read role sees a DIFFERENT object set than the write role "
        f"(missing: {sorted(write_set - read_set)[:5]}). Reflecting under the "
        f"less-privileged role would produce a partial automap base."
    )
