"""
Project:       pfin-back-etl
Author:        Rich Mosko (mosko-fintech Backend)

Description:
    Regression tests for `_staging_update`'s generated SQL — BACKLOG §7.6 S17
    requirement (a′).

    ⚠ TIER: `pgtest` — needs a REAL POSTGRES, needs NO credentials, needs NO
    project schema. These touch only `create temp table`, so they are CI-
    runnable against a bare `postgres` service with ZERO secrets.

    That distinction was not obvious and I had it wrong first. The property
    these tests need is REAL POSTGRES, not MANUAL — and I conflated the two,
    filing them as `integration` and accepting they could never gate CI. A
    SQLite version would indeed be worse than absent (it cannot model the
    defect, so it would report coverage of the exact thing it cannot observe),
    but that was a false dichotomy: hermetic-against-Postgres is a third
    option, and it is what this actually is.

    ⚠ AND IT CLOSED A HAZARD THE `integration` TIER INHERITED. Using the
    `backend` fixture coupled these to `PFinBackend` construction — hence to
    both API keys and the whole V1 schema — purely to obtain an ENGINE. With no
    reachable database the fixture skips, and all of these vanish SILENTLY,
    INCLUDING the non-vacuity test. Combined with "a wrong DATABASE_URL is
    indistinguishable from no database", the most important test in this PR was
    silently skippable and its skip read as green. The fix for the concealment
    thread had inherited the concealment, through a fixture it only ever wanted
    a connection from.

    ⚠ THESE PIN PROPERTIES, NOT MECHANISMS. The obvious test is "the seed
    contains WHERE false" — which would pass a refactor that reintroduced the
    problem another way (a CTE that reads the whole target, then dedupes). Same
    error class as asserting a role NAME instead of the privileges it implies.

    (a′) has TWO justifications and both are pinned separately:
      · CORRECTNESS — the update applies; untouched rows are not written; the
        join is unambiguous. A Postgres semantic.
      · SECURITY    — the seed performs NO unbounded read of the target. NOT a
        Postgres semantic: it is a fact about how many rows the seed reads, and
        it is directly observable. A dedupe-after-full-read refactor passes
        every correctness assertion while fully restoring the cross-tenant
        over-read under `service_role`.
"""

import pytest
import sqlalchemy as sqla

import pgtest_support
from pfin_back_etl.core import staging_seed_sql

#: ⚠ THE REAL STATEMENT, imported from the module under test — NOT a re-typed
#: copy. A test asserting on its own copy of the SQL pins the PATTERN and would
#: not observe a refactor of `_staging_update`, which is the code it exists to
#: guard. `pg_temp` stands in for the target schema; nothing else differs.
_SEED_FIXED = staging_seed_sql("stg", "pg_temp", "tgt")

#: The pre-fix shape, kept verbatim for the non-vacuity pair. This one IS a
#: local copy on purpose: it must not track the module, or "the defect no
#: longer reproduces" would silently become "the test now runs the fix twice".
_SEED_BROKEN = "create temp table stg as select * from pg_temp.tgt"


@pytest.fixture(scope="module")
def pg_conn():
    """A bare Postgres connection, rolled back at teardown.

    URL resolution and the CI-fails-rather-than-skips rule live in
    `pgtest_support`, so the tier has ONE definition rather than a copy per
    module — two copies of one policy drift, which is exactly what produced
    the second, ungoverned skip policy reconciled earlier in this work.

    These tests need nothing the tier provides beyond a connection: temp
    tables only, no roles, no schemas.
    """
    engine = sqla.create_engine(pgtest_support.resolve_url())
    with engine.connect() as conn:
        yield conn
        conn.rollback()


def _seed_and_stage(conn, seed_sql):
    """Target + staging seeded, BEFORE the update rows are inserted."""
    conn.execute(sqla.text("drop table if exists stg"))
    conn.execute(sqla.text("drop table if exists tgt"))
    conn.execute(
        sqla.text("create temp table tgt(k int primary key, v text, "
                  "touched int default 0)")
    )
    conn.execute(
        sqla.text("insert into tgt values (1,'OLD-1'),(2,'OLD-2'),(3,'UNTOUCHED')")
    )
    conn.execute(sqla.text(seed_sql))


def _apply_update(conn):
    """The generated UPDATE … FROM staging, joined on the key."""
    conn.execute(
        sqla.text("insert into stg(k,v,touched) values (1,'NEW-1',0),(2,'NEW-2',0)")
    )
    result = conn.execute(
        sqla.text(
            "update tgt as TG set v = ST.v, touched = TG.touched + 1 "
            "from stg as ST where TG.k = ST.k"
        )
    )
    rows = {
        k: (v, touched)
        for k, v, touched in conn.execute(
            sqla.text("select k, v, touched from tgt order by k")
        )
    }
    return result.rowcount, rows


# ---------------------------------------------------------------------------
# (a′) SECURITY — the seed must not read the target's rows
# ---------------------------------------------------------------------------
@pytest.mark.pgtest
def test_the_seed_reads_no_rows_from_the_target(pg_conn):
    """⚠ THE VETO-LEVEL HALF OF (a′), AND THE ONE THE CORRECTNESS TESTS MISS.

    Under the write role the seed runs with the privileges to read EVERY
    TENANT'S ROWS, and `pfin.eod_price` carries per-user `manual_valuation`
    rows — user-entered money. A refactor that reads the whole target into a
    CTE and dedupes properly passes every correctness assertion below while
    fully restoring that over-read.

    Asserted as a COUNT immediately after the seed and BEFORE the update rows
    are inserted, so it is mechanism-agnostic: `WHERE false`, a CTE, or
    anything else passes iff the seed is actually bounded.
    """
    _seed_and_stage(pg_conn, _SEED_FIXED)
    seeded = pg_conn.execute(sqla.text("select count(*) from stg")).scalar()
    pg_conn.rollback()
    assert seeded == 0, (
        f"the staging seed read {seeded} row(s) from the target — an unbounded "
        f"read inside the write path, which under service_role copies every "
        f"tenant's rows into staging"
    )


@pytest.mark.pgtest
def test_the_broken_seed_did_read_the_target(pg_conn):
    """Non-vacuity for the security assertion: the old seed really did read
    rows, so the test above can distinguish bounded from unbounded."""
    _seed_and_stage(pg_conn, _SEED_BROKEN)
    seeded = pg_conn.execute(sqla.text("select count(*) from stg")).scalar()
    pg_conn.rollback()
    assert seeded == 3


# ---------------------------------------------------------------------------
# (a′) CORRECTNESS — the update must actually apply
# ---------------------------------------------------------------------------
@pytest.mark.pgtest
def test_update_applies_and_untouched_rows_are_not_written(pg_conn):
    """Before (a′) the update silently kept the OLD value, so the FMP
    price-refresh path did not reliably update anything at all."""
    _seed_and_stage(pg_conn, _SEED_FIXED)
    rowcount, rows = _apply_update(pg_conn)
    pg_conn.rollback()

    assert rows[1][0] == "NEW-1", "the update did not apply — it kept the old value"
    assert rows[2][0] == "NEW-2", "the update did not apply — it kept the old value"
    assert rows[3] == ("UNTOUCHED", 0), (
        "an untouched row was written — a no-op self-update fires updated_at "
        "and BEFORE UPDATE triggers on rows nobody asked to change"
    )
    assert rowcount == 2, f"expected exactly 2 rows updated, got {rowcount}"


@pytest.mark.pgtest
def test_staging_holds_exactly_one_row_per_key(pg_conn):
    """The precondition the defect turns on, asserted separately so a failure
    says WHICH property broke rather than only that something did."""
    _seed_and_stage(pg_conn, _SEED_FIXED)
    pg_conn.execute(
        sqla.text("insert into stg(k,v,touched) values (1,'NEW-1',0),(2,'NEW-2',0)")
    )
    worst = pg_conn.execute(
        sqla.text("select coalesce(max(c), 0) from "
                  "(select count(*) c from stg group by k) d")
    ).scalar()
    pg_conn.rollback()
    assert worst == 1, (
        f"staging holds up to {worst} rows for one key — `UPDATE … FROM` with a "
        f"multi-row match is documented as unpredictable which row wins"
    )


@pytest.mark.pgtest
def test_the_broken_seed_reproduces_the_ambiguity(pg_conn):
    """⚠ NON-VACUITY, ASSERTING THE AMBIGUITY RATHER THAN ITS OUTCOME.

    The tempting assertion is that the target keeps its OLD values — which is
    what was measured. But WHICH staging row Postgres picks is precisely the
    UNDEFINED behaviour under test, so gating on that outcome means a planner
    change would read as "the fix regressed".

    The duplicate-row count is DEFINED behaviour and is the actual precondition
    the defect turns on, so that is what gates. The outcome is recorded as a
    non-gating observation below.
    """
    _seed_and_stage(pg_conn, _SEED_BROKEN)
    rowcount, rows = _apply_update(pg_conn)
    dupes = pg_conn.execute(
        sqla.text("select count(*) from stg where k = 1")
    ).scalar()
    pg_conn.rollback()

    assert dupes == 2, (
        "the broken seed should leave TWO staging rows for an updated key — "
        "that duplication IS the defect; if it stops reproducing, the "
        "mechanism has changed and the fixed tests need re-deriving"
    )
    assert rowcount == 3, (
        "the broken seed should write ALL rows, including untouched ones"
    )
    # NON-GATING observation: measured 2026-08-09, the ambiguous join took the
    # STALE row (k=1 kept 'OLD-1'), silently discarding the update. Recorded
    # rather than asserted — it is undefined behaviour and a planner change may
    # legitimately alter it without the defect having changed.
    if rows[1][0] == "OLD-1":
        pass  # the measured behaviour; no assertion on undefined semantics
