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
    it because none of them got that far. Every automated check passed on the
    unfixed code; a human running the assembled path found it.

    The fault is schema `USAGE`, one gate EARLIER than the table privileges
    S17 was filed against:
        has_schema_privilege('pfin_etl','pfin','USAGE')      -> f
        has_schema_privilege('authenticated','pfin','USAGE') -> t

    Tier `pgtest` — a real Postgres, no credentials, no project schema. See
    `pgtest_support` for what the tier guarantees and why these tests need the
    role NAMES to exist (the drift that made the fence fire on this very file).
"""

import pytest
import sqlalchemy as sqla

import pgtest_support
from pfin_back_etl.core import _READ_ROLE, _ROLE_ALLOWLIST, SBaseConn


@pytest.fixture(scope="module")
def pg_url():
    """The tier's URL, with the tier's guarantees applied."""
    url = pgtest_support.resolve_url()
    engine = sqla.create_engine(url)
    with engine.connect() as conn:
        with conn.begin():
            pgtest_support.prepare(conn)
    return url


@pytest.mark.pgtest
def test_reflection_assumes_the_read_role(pg_url, monkeypatch):
    """⚠ THE REGRESSION. Construction must assume a role BEFORE reflecting.

    Spies on `_role` rather than asserting on source text: what must hold is
    that a role is actually assumed on the reflecting connection, not that some
    particular line appears in `_sbase_setup`. A source-text assertion would
    pass a refactor that moved reflection back outside the block.

    Needs no project TABLES — the schemas may be empty. The property is "a role
    was assumed, and it was the read role", which is independent of what the
    reflection finds.
    """
    seen = []
    original = SBaseConn._role

    def spy(self, executor, role):
        seen.append(role)
        return original(self, executor, role)

    monkeypatch.setattr(SBaseConn, "_role", spy)

    url = sqla.make_url(pg_url)
    for key, value in {
        "PFIN_DB_USER": url.username,
        "PFIN_DB_PASSWORD": url.password or "",
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
def test_catalog_visibility_is_gated_by_schema_usage_not_table_grants(pg_url):
    """⚠ WHY REFLECTING AS THE LESS-PRIVILEGED ROLE IS SAFE — STRUCTURALLY.

    The worry this answers is reasonable and was mine: if `authenticated` could
    not see tables it has no SELECT on, reflection would silently produce a
    PARTIAL base, automap would omit tables, and the failure would surface
    later, elsewhere, and confusingly.

    Measuring "both roles reflect 50 tables today" would only be an
    OBSERVATION — true now, re-checkable, and liable to drift as tables are
    added. The stronger form is the MECHANISM: catalog visibility is gated by
    schema `USAGE`, **not** by per-table grants. So a table the role cannot
    SELECT is still REFLECTED, and the result cannot drift as tables are added.

    Demonstrated on self-provisioned fixtures rather than on `pfin`, so it
    holds on a bare Postgres and does not depend on project state:
      · two tables in one schema, SELECT granted on ONE of them
      · under `set role authenticated`: BOTH visible in pg_class
      · and `has_table_privilege` differs between them — proving the roles
        really are differently privileged, so the equal visibility is a fact
        about catalog gating rather than about the grants being identical.
    """
    engine = sqla.create_engine(pg_url)
    with engine.connect() as conn:
        with conn.begin():
            conn.execute(sqla.text("create schema if not exists pgtest_vis"))
            conn.execute(
                sqla.text("create table if not exists pgtest_vis.granted(x int)")
            )
            conn.execute(
                sqla.text("create table if not exists pgtest_vis.withheld(x int)")
            )
            conn.execute(sqla.text("grant usage on schema pgtest_vis to authenticated"))
            conn.execute(
                sqla.text("grant select on pgtest_vis.granted to authenticated")
            )
            conn.execute(
                sqla.text("revoke all on pgtest_vis.withheld from authenticated")
            )

            md = sqla.MetaData()
            conn.execute(sqla.text("set local role authenticated"))
            md.reflect(bind=conn, schema="pgtest_vis")
            can_select = {
                name: conn.execute(
                    sqla.text(
                        f"select has_table_privilege('pgtest_vis.{name}', 'select')"
                    )
                ).scalar()
                for name in ("granted", "withheld")
            }
            conn.execute(sqla.text("reset role"))
            reflected = {t.split(".")[-1] for t in md.tables}
            conn.rollback()

    assert can_select["granted"] is True
    assert can_select["withheld"] is False, (
        "the two tables are equally privileged, so equal visibility below "
        "would prove nothing — the fixture has stopped discriminating"
    )
    assert {"granted", "withheld"} <= reflected, (
        f"reflection under a role WITHOUT select on `withheld` omitted it "
        f"(saw {sorted(reflected)}). Catalog visibility would then depend on "
        f"table grants, and reflecting as the read role could silently produce "
        f"a partial automap base."
    )


@pytest.mark.pgtest
def test_a_role_without_a_grant_has_no_schema_usage(pg_url):
    """⚠ NON-VACUITY, and it pins the mechanism the fix depends on.

    A prior ruling held that `_sbase_setup` reflects from world-readable
    `pg_catalog`, so construction succeeds privilege-less and the fault always
    surfaces at first DML. Measured FALSE — the dialect's reflection query
    filters on the schema and Postgres requires USAGE to inspect it, so
    CONSTRUCTION is the fault site.

    Without this, the tests above would pass just as happily on a database
    where schemas needed no privilege at all — proving nothing about why the
    role assumption is required.
    """
    engine = sqla.create_engine(pg_url)
    with engine.connect() as conn:
        with conn.begin():
            conn.execute(sqla.text("create schema if not exists pgtest_norole"))
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
        "if this is True the environment grants USAGE broadly, and the "
        "privilege premise behind the role assumption does not hold here"
    )


@pytest.mark.pgtest
def test_the_read_role_is_the_less_privileged_of_the_two(pg_url):
    """The choice, asserted rather than argued: reflection assumes the READ
    role, and the allowlist holds exactly the two ruled roles."""
    assert _ROLE_ALLOWLIST == {"authenticated", "service_role"}
    assert _READ_ROLE == "authenticated"
