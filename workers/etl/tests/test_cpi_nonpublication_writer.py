"""
Project:       pfin-back-etl
Author:        Rich Mosko (mosko-fintech Backend)

Description:
    Unit tests for the `pfin.cpi_u_nonpublication` writer (063 / ADR-049
    Decision 1) and — the load-bearing half — the count reconciliation that
    gates it, `PFinBackend._prepare_cpi_u_frames`.

    ⚠ WHY THE GATE IS TESTED HARDER THAN THE MAPPER. Before BACKLOG §7.6 S21,
    `pfin.cpi_u_nonpublication` was EMPTY and empty was CORRECT — the transport
    discarded value-null rows from its own return value, so empty was the
    table's only reachable state. The moment the transport lift lands, "empty"
    silently changes meaning to BROKEN, and no constraint, no query and no other
    test can tell the two worlds apart: they are identical at every layer. The
    reconciliation is the only thing that can, which is why the lift and this
    gate are one change.

    ⚠ THE VENUE IS DELIBERATE. This is `workers/etl` pytest, not the DB layer,
    because NO DATABASE TEST CAN SEE A PROCESS THAT NEVER RAN (QA stated this as
    explicit non-coverage rather than leaving it implied). A pgTAP test against
    an empty table cannot distinguish "correctly empty" from "the writer never
    fired".

    ⚠ EVERY TEST HERE IS MARKED `unit` ON PURPOSE. CI runs `ruff check src` plus
    `pytest -m unit` and nothing else — the `integration` / `deployment` /
    `replay` lanes are not in CI and cannot be. An unmarked (or otherwise
    marked) test here would be DESELECTED and would not run at all, which is
    how `test_replay_parity.py` came to be a first-green target that has never
    run. There is also NO skip sink anywhere in this file: `Skipped` is a
    `BaseException`, so a test body that reaches one loses every assertion it
    already made and reports green.

    No network, no BLS key, no database: the HTTP seam is stubbed and the frames
    are built by the real `utils.fetch_cpi_df`, so what is under test is the
    production composition rather than a hand-shaped stand-in.
"""

import json
import logging
from datetime import date

import polars as pl
import pytest

from pfin_back_etl import utils
from pfin_back_etl.core import (
    CPI_U_SOURCE,
    CpiReconciliationError,
    PFinBackend,
)

_SERIES = "CUUR0000SA0"


def _bls_payload(rows):
    """A BLS v2 response shaped exactly like the live one.

    rows: iterable of (year, period_code, value) — period_code is the RAW BLS
    code, so a caller can inject a non-monthly `M13` / `S01` the way the live
    API would if the request ever asked for one.
    """
    return json.dumps(
        {
            "status": "REQUEST_SUCCEEDED",
            "Results": {
                "series": [
                    {
                        "seriesID": _SERIES,
                        "data": [
                            {
                                "year": str(year),
                                "period": period,
                                "periodName": "Month",
                                "value": value,
                                "footnotes": [{}],
                            }
                            for year, period, value in rows
                        ],
                    }
                ]
            },
        }
    )


@pytest.fixture
def fetch(monkeypatch):
    """Return a callable that runs the REAL transport over a stubbed response."""

    def _fetch(rows):
        class _Resp:
            text = _bls_payload(rows)

        monkeypatch.setattr(utils.requests, "post", lambda *a, **k: _Resp())
        return utils.fetch_cpi_df("key", 2025, 2025, [_SERIES])

    return _fetch


# ---------------------------------------------------------------------------
# The mapper — the complement of _map_cpi_u_index_df on value, its twin on grain
# ---------------------------------------------------------------------------
@pytest.mark.unit
def test_the_measured_2025_10_shape_becomes_a_nonpublication_row(fetch):
    """The exact subject of 063: BLS returned 2025-M10 with value '-'."""
    df_api = fetch([(2025, "M09", "324.800"), (2025, "M10", "-")])
    out = PFinBackend._map_cpi_u_nonpublication_df(df_api)

    assert out["cpi_period"].to_list() == [date(2025, 10, 1)]
    assert out["published_value_raw"].to_list() == ["-"]
    assert out["source"].to_list() == [CPI_U_SOURCE]
    assert list(out.columns) == ["cpi_period", "source", "published_value_raw"]


@pytest.mark.unit
def test_observed_at_is_not_written_by_the_worker(fetch):
    """063's DEFAULT now() stamps the FIRST observation and `on conflict do
    nothing` preserves it. A worker-supplied observed_at would be re-proposed on
    every re-fetch, and the day someone switches the append to `do update` it
    would quietly become a "last run" clock instead of an audit trail."""
    df_api = fetch([(2025, "M10", "-")])
    out = PFinBackend._map_cpi_u_nonpublication_df(df_api)
    assert "observed_at" not in out.columns


@pytest.mark.unit
def test_a_valued_period_is_never_recorded_as_a_nonpublication(fetch):
    """Non-vacuity. Without this, a mapper that recorded EVERY period would pass
    every other test in this section."""
    df_api = fetch([(2025, "M09", "324.800"), (2025, "M11", "324.122")])
    out = PFinBackend._map_cpi_u_nonpublication_df(df_api)
    assert out.is_empty()


@pytest.mark.unit
def test_a_non_monthly_period_is_excluded_even_when_it_has_no_value(fetch):
    """⚠ THE GRAIN CONJUNCTS ARE REUSED; THE VALUE CONJUNCTS ARE NOT.

    063's standing requirement: a period may be recorded only from an EXPLICITLY
    MONTHLY-PROJECTED source, filtered to a real calendar month BEFORE any date
    is constructed. M13 is the ANNUAL AVERAGE, not a month. 063's first-of-month
    CHECK could not catch this — `date(2025, 13, 1)` is not even constructible,
    and a code mapped onto a valid first-of-month date would pass the CHECK
    while being the wrong grain entirely.
    """
    df_api = fetch([(2025, "M10", "-"), (2025, "M13", "-")])
    out = PFinBackend._map_cpi_u_nonpublication_df(df_api)
    assert out["cpi_period"].to_list() == [date(2025, 10, 1)]


@pytest.mark.unit
def test_a_non_finite_value_is_recorded_not_silently_lost(fetch):
    """The complement must be EXACT. `_map_cpi_u_index_df` requires
    `series_value` non-null AND finite, so its negation is null OR non-finite.
    A NaN that satisfied neither mapper would vanish from both tables — and the
    reconciliation is what would catch it, but only if this predicate is the
    true complement."""
    df_api = fetch([(2025, "M09", "324.800"), (2025, "M10", "NaN")])
    out = PFinBackend._map_cpi_u_nonpublication_df(df_api)
    assert out["cpi_period"].to_list() == [date(2025, 10, 1)]


@pytest.mark.unit
def test_a_frame_without_the_raw_token_fails_loud():
    """⚠ published_value_raw is NULLABLE, so a transport that stopped supplying
    the token would fill the table with legal, evidence-free rows and nothing
    downstream would ever notice. Refuse instead."""
    df_api = pl.DataFrame(
        {"year": [2025], "month": [10], "series_value": [None]},
        schema={"year": pl.Int64, "month": pl.Int64, "series_value": pl.Float64},
    )
    with pytest.raises(CpiReconciliationError, match="series_value_raw"):
        PFinBackend._map_cpi_u_nonpublication_df(df_api)


# ---------------------------------------------------------------------------
# The gate — periods returned = 053 rows + 063 rows + non-monthly
# ---------------------------------------------------------------------------
@pytest.mark.unit
def test_the_two_frames_partition_the_fetch(fetch, caplog):
    """The whole-window shape: two valued months, one non-publication."""
    df_api = fetch(
        [
            (2025, "M09", "324.800"),
            (2025, "M10", "-"),
            (2025, "M11", "324.122"),
        ]
    )
    with caplog.at_level(logging.INFO, logger="pfin_etl"):
        df_index, df_nonpub = PFinBackend._prepare_cpi_u_frames(df_api)

    assert df_index["cpi_period"].to_list() == [date(2025, 9, 1), date(2025, 11, 1)]
    assert df_nonpub["cpi_period"].to_list() == [date(2025, 10, 1)]

    recon = [m for m in (r.message for r in caplog.records) if "reconciliation" in m]
    assert recon, "the balance must be logged, not just checked"
    assert "3 period(s) returned" in recon[0], recon[0]
    assert "2 for pfin.cpi_u_index" in recon[0], recon[0]
    assert "1 for pfin.cpi_u_nonpublication" in recon[0], recon[0]


@pytest.mark.unit
def test_the_reconciliation_is_logged_even_when_nothing_is_unpublished(fetch, caplog):
    """⚠ ANTI-VACUITY ON THE LOG. If the balance line only appeared when
    something was unpublished, its ABSENCE would be ambiguous — "a clean
    window" and "the writer never ran" would look identical, which is the exact
    indistinguishability this whole change exists to remove."""
    df_api = fetch([(2025, "M09", "324.800"), (2025, "M11", "324.122")])
    with caplog.at_level(logging.INFO, logger="pfin_etl"):
        PFinBackend._prepare_cpi_u_frames(df_api)
    recon = [m for m in (r.message for r in caplog.records) if "reconciliation" in m]
    assert recon, "the balance must be logged unconditionally"
    assert "0 for pfin.cpi_u_nonpublication" in recon[0], recon[0]


@pytest.mark.unit
def test_a_non_monthly_period_balances_as_its_own_term(fetch):
    """M13 belongs to neither table. It must be ACCOUNTED FOR rather than
    absorbed, or the third term would be a residual and the sum could never
    fail."""
    df_api = fetch([(2025, "M10", "-"), (2025, "M12", "324.9"), (2025, "M13", "324.1")])
    df_index, df_nonpub = PFinBackend._prepare_cpi_u_frames(df_api)
    assert len(df_index) == 1 and len(df_nonpub) == 1 and len(df_api) == 3


# ---------------------------------------------------------------------------
# ⚠ THE INDUCED FAILURES. A suite that passes under every value of a variable is
# BLIND to that variable, not robust to it. Each test below varies exactly the
# thing the gate watches and requires it to FAIL.
# ---------------------------------------------------------------------------
@pytest.mark.unit
def test_a_filter_added_to_the_index_mapper_breaks_the_balance(fetch, monkeypatch):
    """⚠ THE CLASS, NOT THE INSTANCE — this is the test the gate exists for.

    Nobody has to predict WHY a future change might drop a row. Here the index
    mapper acquires an extra filter for a reason that does not exist yet; the
    gate notices because its third term is computed independently of both
    mappers and the other two are the mappers' ACTUAL output counts.
    """
    df_api = fetch([(2025, "M09", "324.800"), (2025, "M10", "-")])
    real_mapper = PFinBackend._map_cpi_u_index_df
    monkeypatch.setattr(
        PFinBackend,
        "_map_cpi_u_index_df",
        staticmethod(lambda df: real_mapper(df).filter(pl.col("cpi_value") > 999)),
    )
    with pytest.raises(CpiReconciliationError, match="reconciliation FAILED"):
        PFinBackend._prepare_cpi_u_frames(df_api)


@pytest.mark.unit
def test_the_value_fence_returning_is_caught_at_the_writer(fetch, monkeypatch):
    """⚠ THE SPECIFIC REGRESSION S21 CLOSES. Someone re-adds a value filter —
    this time to the non-publication mapper, "to keep the table clean". The
    period then reaches NEITHER table and the sum comes up short."""
    df_api = fetch([(2025, "M09", "324.800"), (2025, "M10", "-")])
    # ⚠ Built with an explicit schema rather than `head(0).select(pl.lit(...))`:
    # selecting only literals from a 0-row frame BROADCASTS to one row, so the
    # "empty" stand-in silently balanced and this test passed vacuously on the
    # first run. Caught by the test failing to fail.
    empty = pl.DataFrame(
        schema={
            "cpi_period": pl.Date,
            "source": pl.String,
            "published_value_raw": pl.String,
        }
    )
    assert empty.is_empty(), "precondition: the stand-in really is empty"
    monkeypatch.setattr(
        PFinBackend,
        "_map_cpi_u_nonpublication_df",
        staticmethod(lambda df: empty),
    )
    with pytest.raises(CpiReconciliationError, match="reconciliation FAILED"):
        PFinBackend._prepare_cpi_u_frames(df_api)


@pytest.mark.unit
def test_a_period_staged_for_both_tables_is_refused(fetch, monkeypatch):
    """⚠ THE HOLE THE COUNT CANNOT SEE. Both mappers dedupe on cpi_period, so
    two rows for the SAME period — one valued, one not — put that period in both
    frames while the counts still balance (2 = 1 + 1 + 0). Recording a period as
    unpublished in the same breath as storing its value is wrong, and only the
    disjointness check catches it.

    (Across RUNS the two tables sharing a period is CORRECT — it is the
    "unpublished when we looked, published later" audit trail. This is about one
    response.)
    """
    df_api = fetch([(2025, "M10", "324.800"), (2025, "M10", "-")])
    df_index, df_nonpub = PFinBackend._map_cpi_u_index_df(df_api), None
    assert len(df_index) == 1, "precondition: the index mapper deduped"
    with pytest.raises(CpiReconciliationError, match="BOTH"):
        PFinBackend._prepare_cpi_u_frames(df_api)
    assert df_nonpub is None  # nothing was written; the gate raised first


@pytest.mark.unit
def test_the_gate_can_actually_pass(fetch):
    """⚠ ANTI-VACUITY ON THE INDUCED FAILURES THEMSELVES. Three tests above
    demand a raise; if `_prepare_cpi_u_frames` raised unconditionally they would
    all pass and the gate would be useless. It must also succeed on the live
    shape."""
    df_api = fetch([(2025, "M09", "324.800"), (2025, "M10", "-")])
    df_index, df_nonpub = PFinBackend._prepare_cpi_u_frames(df_api)
    assert len(df_index) == 1 and len(df_nonpub) == 1
