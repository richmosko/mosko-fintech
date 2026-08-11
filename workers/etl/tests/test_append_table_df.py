"""
Project:       pfin-back-etl
Author:        Rich Mosko (mosko-fintech Backend)

Description:
    Regression tests for `append_table_df` — the append-only write path that
    populates `pfin.cpi_u_nonpublication` (063 / ADR-049 Decision 1).

    ⚠ TIER: `pgtest` — needs a REAL POSTGRES, needs NO credentials, needs NO
    project schema. Temp tables only, plus the two role NAMES the tier already
    guarantees. `ON CONFLICT DO NOTHING` is a Postgres semantic: SQLite cannot
    model it and a mock would assert the mechanism back to itself.

    ⚠ WHY THIS EXISTS RATHER THAN A ONE-OFF MANUAL CHECK. When 063 was first
    applied (2026-08-11) the writer's CONFLICT branch was exercised end to end
    against the real table, but its INSERT branch was not — the only row in the
    table had been written by hand with `psql` moments earlier, and 063 blocks
    DELETE and TRUNCATE by trigger, so a clean insert could not be arranged
    there at all. A scratch database would have closed that once, manually, and
    proved nothing on any later change. This closes it on every PR: the lane is
    a required status check.

    ⚠ WHAT IS ACTUALLY UNDER TEST IS THE REAL METHOD. `SBaseConn.__new__` gives
    a real instance whose real `_role` and real `append_table_df` run; only the
    engine is supplied by the fixture. A re-typed copy of the statement would
    pin the pattern and never observe a refactor of the code it guards — the
    same trap `test_staging_update` calls out for `staging_seed_sql`.

    ⚠ THE TEMP TABLE MIRRORS 063 INCLUDING ITS CHECKS AND ITS GRANT, on purpose.
    The grant is `select, insert` — exactly what 063 gives `service_role`, and
    NOT `update`/`delete`. That makes two of this module's claims testable
    against a real ACL rather than asserted in a comment: that DO NOTHING needs
    the arbiter READ, and that the 64-char bound my truncation targets is the
    real constraint rather than a number someone typed twice.

    ⚠ ALL DDL HERE IS `pg_temp`-QUALIFIED, DELIBERATELY. `drop table if exists
    stg` resolves through `search_path` until a temp table of that name exists
    in the session — against a real database that is a live data-loss path.
    `test_staging_update.py` still carries the unqualified form; do not copy it.
"""

from datetime import date

import polars as pl
import pytest
import sqlalchemy as sqla
from sqlalchemy.dialects.postgresql import insert as pg_insert

import pgtest_support
from pfin_back_etl.core import CPI_U_RAW_TOKEN_MAX, SBaseConn

_TBL = "cpi_u_nonpublication_probe"

#: Mirrors migration 063's shape: PK on cpi_period, first-of-month CHECK, the
#: 64-char bound on published_value_raw, and observed_at DEFAULT now().
_DDL = f"""
create temp table {_TBL} (
  cpi_period           date        not null primary key,
  source               text        not null default 'BLS_CUUR0000SA0',
  published_value_raw  text        null,
  observed_at          timestamptz not null default now(),
  constraint probe_period_first_of_month
    check (extract(day from cpi_period) = 1),
  constraint probe_raw_bounded
    check (published_value_raw is null or length(published_value_raw) <= 64)
)
"""


@pytest.fixture(scope="module")
def engine():
    """One connection for the whole module.

    ⚠ StaticPool IS LOAD-BEARING, NOT TUNING. Temp tables are scoped to a
    CONNECTION, and `append_table_df` opens its own Session — which would draw
    a DIFFERENT connection from a normal pool and not see the table at all.
    The failure would look like "relation does not exist", i.e. like a bug in
    the code under test rather than in the fixture.
    """
    eng = sqla.create_engine(
        pgtest_support.resolve_url(), poolclass=sqla.pool.StaticPool
    )
    with eng.connect() as conn:
        pgtest_support.ensure_roles(conn)
        conn.commit()
    yield eng
    eng.dispose()


@pytest.fixture
def probe(engine):
    """A fresh 063-shaped temp table, granted exactly what 063 grants."""
    with engine.connect() as conn:
        conn.execute(sqla.text(f"drop table if exists pg_temp.{_TBL}"))
        conn.execute(sqla.text(_DDL))
        # Exactly 063's ACL: SELECT + INSERT, no UPDATE, no DELETE.
        conn.execute(
            sqla.text(f"grant select, insert on pg_temp.{_TBL} to service_role")
        )
        conn.commit()

    md = sqla.MetaData()
    tab = sqla.Table(_TBL, md, autoload_with=engine)

    class _Probe:
        __table__ = tab

    return _Probe


@pytest.fixture
def backend(engine):
    """A real SBaseConn whose only supplied attribute is the engine."""
    obj = SBaseConn.__new__(SBaseConn)
    obj.engine = engine
    return obj


def _rows(engine):
    with engine.connect() as conn:
        return conn.execute(
            sqla.text(
                f"select cpi_period, source, published_value_raw, observed_at "
                f"from pg_temp.{_TBL} order by cpi_period"
            )
        ).mappings().all()


def _df(*triples):
    return pl.DataFrame(
        [
            {"cpi_period": p, "source": s, "published_value_raw": r}
            for p, s, r in triples
        ],
        schema={
            "cpi_period": pl.Date,
            "source": pl.String,
            "published_value_raw": pl.String,
        },
    )


# ---------------------------------------------------------------------------
# The INSERT branch — the sliver the first real apply could not reach
# ---------------------------------------------------------------------------
@pytest.mark.pgtest
def test_a_new_period_is_inserted(backend, probe, engine):
    """The writer's own first INSERT of a period, which is what the 2026-08-11
    apply could NOT demonstrate: the only row there had been written by hand,
    so every subsequent run took the conflict path."""
    backend.append_table_df(probe, ["cpi_period"], _df((date(2025, 10, 1), "BLS_CUUR0000SA0", "-")))

    rows = _rows(engine)
    assert len(rows) == 1
    assert rows[0]["cpi_period"] == date(2025, 10, 1)
    assert rows[0]["published_value_raw"] == "-"
    assert rows[0]["observed_at"] is not None, "the DB DEFAULT must stamp it"


@pytest.mark.pgtest
def test_observed_at_is_stamped_by_the_database_not_the_worker(
    backend, probe, engine
):
    """The mapper deliberately does not carry observed_at. It must therefore
    arrive from the column DEFAULT, or the audit trail records nothing.

    ⚠ THE BRACKETS ARE READ FROM THE DATABASE, NOT FROM PYTHON, and that is the
    point of the test rather than a detail of it. Bracketing a DB-generated
    timestamp with `datetime.now()` compares two DIFFERENT MACHINES' clocks —
    it failed first time by 446µs of container-vs-host skew. That version was
    not a stricter test of the stamp; it was a test of clock agreement, which
    is not a property this code has or should have. Only the server's own clock
    can order the server's own stamp.
    """
    def _db_now():
        with engine.connect() as conn:
            return conn.execute(sqla.text("select now()")).scalar_one()

    before = _db_now()
    backend.append_table_df(probe, ["cpi_period"], _df((date(2025, 10, 1), "BLS_CUUR0000SA0", "-")))
    after = _db_now()

    stamped = _rows(engine)[0]["observed_at"]
    assert before <= stamped <= after, (
        "observed_at did not fall between two readings of the server clock "
        "taken either side of the append — it was not stamped by this write"
    )


# ---------------------------------------------------------------------------
# The CONFLICT branch — first observation wins
# ---------------------------------------------------------------------------
@pytest.mark.pgtest
def test_a_re_run_does_not_overwrite_the_first_observation(
    backend, probe, engine
):
    """⚠ THE AUDIT-TRAIL PROPERTY. `observed_at` records when WE FIRST OBSERVED
    the non-publication. A monthly re-fetch proposes the same period again; if
    that re-stamped the row, the column would silently become a "last run"
    clock and the trail would be destroyed — not corrupted visibly, REPLACED by
    something that looks equally plausible."""
    backend.append_table_df(probe, ["cpi_period"], _df((date(2025, 10, 1), "BLS_CUUR0000SA0", "-")))
    first = _rows(engine)[0]

    backend.append_table_df(
        probe,
        ["cpi_period"],
        _df((date(2025, 10, 1), "BLS_CUUR0000SA0", "SHOULD-NOT-OVERWRITE")),
    )
    after = _rows(engine)

    assert len(after) == 1, "a re-run must not accumulate a duplicate row"
    assert after[0]["published_value_raw"] == "-", "first observation must win"
    assert after[0]["observed_at"] == first["observed_at"], (
        "observed_at was re-stamped — the audit trail became a last-run clock"
    )


@pytest.mark.pgtest
def test_a_mixed_batch_inserts_the_new_and_leaves_the_existing(
    backend, probe, engine
):
    """The real nightly shape: a window containing one already-recorded period
    and one newly-observed one. Both branches in a single statement."""
    backend.append_table_df(probe, ["cpi_period"], _df((date(2025, 10, 1), "BLS_CUUR0000SA0", "-")))
    first = _rows(engine)[0]

    backend.append_table_df(
        probe,
        ["cpi_period"],
        _df(
            (date(2025, 10, 1), "BLS_CUUR0000SA0", "IGNORED"),
            (date(2026, 3, 1), "BLS_CUUR0000SA0", "-"),
        ),
    )
    rows = _rows(engine)

    assert [r["cpi_period"] for r in rows] == [date(2025, 10, 1), date(2026, 3, 1)]
    assert rows[0]["published_value_raw"] == "-"
    assert rows[0]["observed_at"] == first["observed_at"]


@pytest.mark.pgtest
def test_duplicate_keys_within_one_batch_do_not_raise(backend, probe, engine):
    """⚠ A PROPERTY OF `DO NOTHING` THAT `DO UPDATE` DOES NOT HAVE, and the
    writer depends on it. `ON CONFLICT DO UPDATE` raises "cannot affect row a
    second time" when one statement proposes the same key twice; DO NOTHING
    tolerates it. Both CPI-U mappers dedupe on cpi_period, so this should not
    arise — but "should not arise" is exactly the assumption worth pinning,
    since the failure would be a hard raise in a nightly cron."""
    backend.append_table_df(
        probe,
        ["cpi_period"],
        _df(
            (date(2025, 10, 1), "BLS_CUUR0000SA0", "-"),
            (date(2025, 10, 1), "BLS_CUUR0000SA0", "-"),
        ),
    )
    assert len(_rows(engine)) == 1


@pytest.mark.pgtest
def test_an_empty_frame_writes_nothing_and_does_not_raise(backend, probe, engine):
    """A clean window — no non-publications — is the common case."""
    backend.append_table_df(probe, ["cpi_period"], _df())
    assert _rows(engine) == []


# ---------------------------------------------------------------------------
# ⚠ NON-VACUITY. Each of these varies the thing a test above watches and
# requires the OPPOSITE outcome, so none of the assertions can be passing for
# a reason unrelated to the behaviour they name.
# ---------------------------------------------------------------------------
@pytest.mark.pgtest
def test_do_update_WOULD_have_overwritten_the_first_observation(probe, engine):
    """⚠ THE FIXTURE MUST BE ABLE TO SEE AN OVERWRITE, or
    `test_a_re_run_does_not_overwrite_the_first_observation` proves nothing —
    a table that simply ignored every second write would pass it.

    This runs the conflict clause `upsert_table_df` builds (every non-key
    column from EXCLUDED) against the same fixture and requires the row TO
    change. It is what 063's header means by "`do update` reaches the UPDATE
    fence and fails loud": here there is no such fence, so we get to observe
    the damage the fence exists to prevent.
    """
    tab = probe.__table__
    with engine.connect() as conn:
        conn.execute(
            sqla.text(
                f"insert into pg_temp.{_TBL}(cpi_period, source, published_value_raw) "
                "values ('2025-10-01', 'BLS_CUUR0000SA0', '-')"
            )
        )
        conn.commit()
        first = _rows(engine)[0]

        stmt = pg_insert(tab).values(
            [{"cpi_period": date(2025, 10, 1), "source": "BLS_CUUR0000SA0",
              "published_value_raw": "OVERWRITTEN"}]
        )
        stmt = stmt.on_conflict_do_update(
            index_elements=["cpi_period"],
            set_={c.name: stmt.excluded[c.name]
                  for c in tab.columns if c.name != "cpi_period"},
        )
        conn.execute(stmt)
        conn.commit()

    changed = _rows(engine)[0]
    assert changed["published_value_raw"] == "OVERWRITTEN", (
        "the fixture cannot observe an overwrite, so the DO NOTHING tests above "
        "would pass even against a table that silently dropped every write"
    )
    assert changed["observed_at"] != first["observed_at"], (
        "observed_at must be re-stampable here — that is the damage DO NOTHING "
        "and 063's UPDATE fence exist to prevent"
    )


@pytest.mark.pgtest
def test_the_arbiter_read_really_is_required(backend, probe, engine):
    """⚠ PINS A CLAIM THIS CODEBASE MAKES IN A COMMENT. `append_table_df` says
    DO NOTHING needs the arbiter READ as well as the write, and that 063's
    SELECT grant must not be tightened to insert-only. Untested, that is an
    assertion about Postgres someone could 'clean up' at any time.

    Revoking SELECT must break the append. If this ever stops failing, the
    comment — and 063's grant rationale — need rewriting, not the test.
    """
    with engine.connect() as conn:
        conn.execute(sqla.text(f"revoke select on pg_temp.{_TBL} from service_role"))
        conn.commit()

    with pytest.raises(Exception) as exc:
        backend.append_table_df(
            probe, ["cpi_period"], _df((date(2025, 10, 1), "BLS_CUUR0000SA0", "-"))
        )
    assert "permission denied" in str(exc.value).lower(), str(exc.value)


@pytest.mark.pgtest
def test_the_64_char_bound_is_the_real_constraint(backend, probe, engine):
    """⚠ PINS `CPI_U_RAW_TOKEN_MAX` AGAINST THE DATABASE, not against itself.
    The worker truncates to that constant precisely so the DB CHECK never
    aborts the append. If 063's bound and the constant ever diverge, the
    truncation stops protecting anything and the first overlong token takes
    down a whole nightly append — so the two must be pinned together, and the
    only way to do that is against a real CHECK.
    """
    at_bound = "x" * CPI_U_RAW_TOKEN_MAX
    backend.append_table_df(
        probe, ["cpi_period"], _df((date(2025, 10, 1), "BLS_CUUR0000SA0", at_bound))
    )
    assert _rows(engine)[0]["published_value_raw"] == at_bound

    # And one char more must be refused BY THE DATABASE — otherwise the bound
    # this constant targets is not where we think it is.
    with engine.connect() as conn:
        with pytest.raises(Exception) as exc:
            conn.execute(
                sqla.text(
                    f"insert into pg_temp.{_TBL}(cpi_period, published_value_raw) "
                    "values ('2026-03-01', :tok)"
                ),
                {"tok": "x" * (CPI_U_RAW_TOKEN_MAX + 1)},
            )
        assert "probe_raw_bounded" in str(exc.value), str(exc.value)
