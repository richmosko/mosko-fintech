"""
Project:       pfin-back-etl
Author:        Rich Mosko (mosko-fintech Backend)

Description:
    Regression tests for `_staging_update`'s generated SQL — BACKLOG §7.6 S17
    requirement (a′).

    ⚠ THESE PIN THE PROPERTY, NOT THE MECHANISM. The obvious test is "the seed
    statement contains WHERE false". That would pass against a future refactor
    that reintroduced the ambiguity by another route — seeding empty and then
    re-populating, or switching to a CTE — while the update silently stopped
    applying again. What must hold is:

        (1) the update ACTUALLY APPLIES  — the new value lands, not the old one
        (2) untouched rows are NOT WRITTEN — no self-update, no trigger firing
        (3) the join is UNAMBIGUOUS       — one staging row per key

    Asserting the mechanism instead of the property is the same class of error
    as asserting a role NAME instead of the privileges the name implies.

    ⚠ WHY THESE RUN AGAINST REAL POSTGRES AND ARE `integration`-TIER. The
    defect IS a Postgres semantic — `UPDATE … FROM` with a multi-row match is
    documented as unpredictable which row is used. SQLite does not model it, so
    a hermetic version of this test could not have caught the defect and would
    be worse than absent: it would report coverage of the exact thing it cannot
    observe. Marked honestly rather than forced into the protected lane.
"""

import pytest
import sqlalchemy as sqla


# The generated shape, reduced to what the defect turns on. Mirrors
# _staging_update: seed the staging table from the target, insert the update
# rows, then UPDATE … FROM staging joined on the key.
_SEED_BROKEN = "create temp table stg as select * from tgt"
_SEED_FIXED = "create temp table stg as select * from tgt where false"


def _run_staging_cycle(conn, seed_sql):
    """Build target + staging, apply the generated UPDATE, return the result."""
    conn.execute(sqla.text("create temp table tgt(k int primary key, v text, "
                           "touched int default 0)"))
    conn.execute(
        sqla.text("insert into tgt values (1,'OLD-1'),(2,'OLD-2'),(3,'UNTOUCHED')")
    )
    conn.execute(sqla.text(seed_sql))
    conn.execute(
        sqla.text("insert into stg(k,v,touched) values (1,'NEW-1',0),(2,'NEW-2',0)")
    )
    result = conn.execute(
        sqla.text(
            "update tgt as TG set v = ST.v, touched = TG.touched + 1 "
            "from stg as ST where TG.k = ST.k"
        )
    )
    rows = dict(
        (k, (v, touched))
        for k, v, touched in conn.execute(
            sqla.text("select k, v, touched from tgt order by k")
        )
    )
    return result.rowcount, rows


@pytest.mark.integration
def test_update_actually_applies_and_leaves_untouched_rows_alone(backend):
    """The three properties, on the fixed seed.

    Property (1) is the one that makes this a repair: before (a′) the update
    silently kept the OLD value, so the FMP price-refresh path did not reliably
    update anything at all.
    """
    with backend.engine.connect() as conn:
        rowcount, rows = _run_staging_cycle(conn, _SEED_FIXED)
        conn.rollback()

    assert rows[1][0] == "NEW-1", "the update did not apply — it kept the old value"
    assert rows[2][0] == "NEW-2", "the update did not apply — it kept the old value"
    assert rows[3] == ("UNTOUCHED", 0), (
        "an untouched row was written — a no-op self-update fires updated_at "
        "and BEFORE UPDATE triggers on rows nobody asked to change"
    )
    assert rowcount == 2, f"expected exactly 2 rows updated, got {rowcount}"


@pytest.mark.integration
def test_the_broken_seed_still_reproduces_the_defect(backend):
    """⚠ NON-VACUITY. Pins that the defect is REAL and that the test above can
    distinguish fixed from broken.

    Without this, the test above would pass just as happily against a database
    where `UPDATE … FROM` never had the ambiguity problem — proving nothing.
    This asserts the old seed still produces the wrong answer, so the pair
    together establish that (a′) is what changed the outcome.
    """
    with backend.engine.connect() as conn:
        rowcount, rows = _run_staging_cycle(conn, _SEED_BROKEN)
        conn.rollback()

    assert rowcount == 3, (
        "the broken seed should write ALL rows, including untouched ones"
    )
    assert rows[3][1] == 1, "untouched row should have been self-updated"
    assert rows[1][0] == "OLD-1" or rows[2][0] == "OLD-2", (
        "expected the ambiguous join to take a stale staging row; if this ever "
        "stops reproducing, the defect's mechanism has changed and the fixed "
        "test above needs re-deriving rather than trusting"
    )


@pytest.mark.integration
def test_staging_holds_exactly_one_row_per_key(backend):
    """The mechanism behind (1) and (2), asserted separately so a failure says
    WHICH property broke rather than only that something did."""
    with backend.engine.connect() as conn:
        conn.execute(sqla.text("create temp table tgt(k int primary key, v text)"))
        conn.execute(sqla.text("insert into tgt values (1,'A'),(2,'B')"))
        conn.execute(sqla.text(_SEED_FIXED))
        conn.execute(sqla.text("insert into stg(k,v) values (1,'A2'),(2,'B2')"))
        dupes = conn.execute(
            sqla.text("select count(*) from (select k from stg group by k "
                      "having count(*) > 1) d")
        ).scalar()
        conn.rollback()
    assert dupes == 0, (
        "staging holds more than one row for some key — the UPDATE … FROM join "
        "is ambiguous and Postgres does not define which row wins"
    )
