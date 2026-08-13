"""
Project:       pfin-back-etl
Author:        QA (mosko-fintech)

Description:
    `unit`-tier tests for the SELF-217 historical NAV backfill's pure-function
    half: pfin_back_etl.nav_backfill.parse_baseline_csv() and
    split_before_first_checkpoint(). Both are DB-free and API-free by design
    (nav_backfill.py's own module docstring: "No DB access. Used by BOTH the
    dry-run and the --commit path so the two can never disagree about which
    rows are in scope.") — so these tests need no fixture DB and no
    credentials, and run in CI.

    ALL CSV CONTENT IS SYNTHETIC, CONSTRUCTED INLINE. Never F/CTO's real file
    at temp/nav-history/, never a real dollar figure — RT-15 parity-fixture
    posture (SECURITY §4.5): no PII, no real financial figures in any tracked
    test artifact.

    SCOPE — what this file does NOT cover, and why: NavBackfillWorker's
    DB-touching half (first_cron_checkpoint / write_backfill / run — the AC7
    impersonate -> read-auth.uid()-back -> bind -> INSERT chain; write_backfill
    is the ADR-053 Decision 6 whole-batch shape, replacing an earlier
    per-row backfill_row() the redesign removed) needs a live database
    round-trip to mean anything (mocking the SQLAlchemy connection risks
    testing the mock instead of the code, per this file's own decision NOT to
    reproduce test_role_assumption.py's RecordingSession idiom for that
    method) — that half is covered by the integration-tier
    test_nav_backfill_write.py instead.
    ⚠ computed_nav_today() and the --ack-delta / AC5 delta-threshold gate in
    run_nav_backfill.py's main() are NOT covered by EITHER test file as of
    this write — Backend's own end-to-end verification (2026-08-12, all 6
    boundary/gate combinations plus a live venv run) is the only proof of
    that surface right now. Recorded as an honest gap, not implied coverage.

    Catch-criteria this file targets (each fires on a REAL implementation
    defect, not a decorative check):
      - units scaling ($K -> $, exactly x1000 — a parse that forgot to scale,
        or scaled by the wrong power of ten, fails an EXACT Decimal comparison)
      - month-end date mapping, INCLUDING the leap-February asymmetry (Feb 28
        is month-end in a non-leap year and is NOT month-end in a leap year —
        a naive "day == 28 or day == 29" check would get the leap case backwards)
      - duplicate-date detection, and that it runs over the WHOLE file before
        range-filtering (a duplicate outside the requested window must still
        raise, not go unnoticed)
      - the first-cron-checkpoint boundary is STRICT (a row exactly ON the
        boundary date is refused, not admissible — off-by-one is a real
        failure mode here since it decides what becomes a permanent row)
"""

import datetime as dt
from decimal import Decimal

import pytest

from pfin_back_etl.nav_backfill import (
    BackfillRow,
    NavBackfillCsvError,
    parse_baseline_csv,
    split_before_first_checkpoint,
)


def _write_csv(tmp_path, rows, *, date_header="Date", nav_header="NAV ($K)"):
    """Write a synthetic baseline CSV. `rows` is a list of (date_str, nav_str)
    tuples already in the sheet's own formats (M/D/YYYY, '$K' money) — this
    helper does no interpretation, only file assembly, so a test's fixture
    values are visible at the call site rather than hidden in a builder.

    ⚠ USES csv.writer, NOT NAIVE f-STRING JOINING — a fixture-authoring defect
    caught by Backend (2026-08-12): an earlier version of this helper built
    lines via `f"{d},{v}"`, and a nav value containing its own comma (e.g. the
    thousands-separator case, "$1,234.5") produced an UNQUOTED internal comma.
    csv.DictReader then split that one field into two on read, so the 'NAV
    ($K)' column bound to '$1' instead of '$1,234.5' — a 10x-class fixture bug
    that read as a scaling defect in the CODE under test. csv.writer quotes
    any field containing the delimiter automatically (QUOTE_MINIMAL, the
    default), which is what a real spreadsheet export does too, so this
    mirrors the real CSV's own quoting rather than reinventing it."""
    import csv

    path = tmp_path / "synthetic_baseline_nav.csv"
    with open(path, "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow([date_header, nav_header])
        writer.writerows(rows)
    return str(path)


# ---------------------------------------------------------------------------
# Units scaling: $K -> $, exactly x1000 (Decimal, never float)
# ---------------------------------------------------------------------------
@pytest.mark.unit
def test_dollars_scaling_is_exact_1000x(tmp_path):
    """A '$500' cell must become exactly $500,000 — not $500, not $5,000,000.
    Asserted as an EXACT Decimal equality (not 'close to' or 'greater than')
    so a 10x or 100x scaling defect fails this test, not just a 1000x one."""
    csv_path = _write_csv(tmp_path, [("12/31/2025", "$500")])
    rows = parse_baseline_csv(csv_path, dt.date(2025, 1, 1), dt.date(2025, 12, 31))
    assert len(rows) == 1
    assert rows[0].nav_value_dollars == Decimal("500000")


@pytest.mark.unit
def test_dollars_scaling_handles_thousands_comma_and_cents(tmp_path):
    """'$1,234.5' ($K, with a thousands-comma AND a fractional-K cent) must
    scale to exactly $1,234,500 — proves the comma-strip and the x1000 compose
    correctly rather than one silently masking a defect in the other."""
    csv_path = _write_csv(tmp_path, [("6/30/2025", "$1,234.5")])
    rows = parse_baseline_csv(csv_path, dt.date(2025, 1, 1), dt.date(2025, 12, 31))
    assert rows[0].nav_value_dollars == Decimal("1234500")


@pytest.mark.unit
@pytest.mark.parametrize("raw,expected", [("($100)", "-100000"), ("-$100", "-100000")])
def test_dollars_scaling_negative_forms(tmp_path, raw, expected):
    """Both negative spellings the sheet uses elsewhere (parens and leading
    '-') must scale correctly too, in case a future export carries a negative
    NAV cell — the module docstring notes neither form appears in the current
    sample but does not assume that holds for every future export."""
    csv_path = _write_csv(tmp_path, [("3/31/2025", raw)])
    rows = parse_baseline_csv(csv_path, dt.date(2025, 1, 1), dt.date(2025, 12, 31))
    assert rows[0].nav_value_dollars == Decimal(expected)


@pytest.mark.unit
def test_dollar_sign_required_no_guessing(tmp_path):
    """A unit-less number ('500', no '$') must RAISE rather than be silently
    assumed to already be dollars or already be thousands — a wrong guess
    here is a 1000x error with no downstream signal."""
    csv_path = _write_csv(tmp_path, [("12/31/2025", "500")])
    with pytest.raises(NavBackfillCsvError):
        parse_baseline_csv(csv_path, dt.date(2025, 1, 1), dt.date(2025, 12, 31))


@pytest.mark.unit
def test_empty_money_cell_raises_not_zero(tmp_path):
    """A blank NAV cell must RAISE, never be treated as $0 — a fabricated
    zero on a financial trend is the same class of defect this project
    fences elsewhere (ADR-042 'absence is not a value')."""
    csv_path = _write_csv(tmp_path, [("12/31/2025", "")])
    with pytest.raises(NavBackfillCsvError):
        parse_baseline_csv(csv_path, dt.date(2025, 1, 1), dt.date(2025, 12, 31))


# ---------------------------------------------------------------------------
# Month-end date mapping, including the leap-February asymmetry
# ---------------------------------------------------------------------------
@pytest.mark.unit
def test_mid_month_date_rejected(tmp_path):
    csv_path = _write_csv(tmp_path, [("12/15/2025", "$500")])
    with pytest.raises(NavBackfillCsvError, match="not a month-end date"):
        parse_baseline_csv(csv_path, dt.date(2025, 1, 1), dt.date(2025, 12, 31))


@pytest.mark.unit
def test_first_of_month_rejected_as_not_month_end(tmp_path):
    """The first calendar day of a month is NOT its month-end — a naive
    'day <= 1 or day >= 28' heuristic would wrongly accept this."""
    csv_path = _write_csv(tmp_path, [("1/1/2026", "$500")])
    with pytest.raises(NavBackfillCsvError, match="not a month-end date"):
        parse_baseline_csv(csv_path, dt.date(2025, 1, 1), dt.date(2026, 12, 31))


@pytest.mark.unit
def test_leap_february_29_is_month_end(tmp_path):
    """2026 is not a leap year in this fixture's neighbourhood, so anchor on
    a real leap year: 2/29/2016 IS a valid month-end (2016 is divisible by 4
    and not a century exception)."""
    csv_path = _write_csv(tmp_path, [("2/29/2016", "$500")])
    rows = parse_baseline_csv(csv_path, dt.date(2016, 1, 1), dt.date(2016, 12, 31))
    assert len(rows) == 1
    assert rows[0].nav_date == dt.date(2016, 2, 29)


@pytest.mark.unit
def test_february_29_in_a_non_leap_year_does_not_exist(tmp_path):
    """2/29/2015 is not a calendar date at all (2015 is not a leap year) —
    must raise at the strptime layer, not silently roll over to March 1."""
    csv_path = _write_csv(tmp_path, [("2/29/2015", "$500")])
    with pytest.raises(NavBackfillCsvError):
        parse_baseline_csv(csv_path, dt.date(2015, 1, 1), dt.date(2015, 12, 31))


@pytest.mark.unit
def test_february_28_is_month_end_in_a_non_leap_year(tmp_path):
    csv_path = _write_csv(tmp_path, [("2/28/2015", "$500")])
    rows = parse_baseline_csv(csv_path, dt.date(2015, 1, 1), dt.date(2015, 12, 31))
    assert rows[0].nav_date == dt.date(2015, 2, 28)


@pytest.mark.unit
def test_february_28_is_NOT_month_end_in_a_leap_year(tmp_path):
    """⭐ THE ASYMMETRIC CASE, and the reason 'leap-Feb' is its own catch-
    criterion rather than folded into the generic month-end test. In 2016
    (leap), February has 29 days, so the 28th is a MID-month date and must be
    REJECTED — the exact opposite disposition from the 2015 case immediately
    above, over what is otherwise the identical string '2/28/YYYY'. A parser
    that hardcodes 'day 28 or 29 is always month-end' passes the non-leap
    case and fails silently here by ACCEPTING a row it should reject."""
    csv_path = _write_csv(tmp_path, [("2/28/2016", "$500")])
    with pytest.raises(NavBackfillCsvError, match="not a month-end date"):
        parse_baseline_csv(csv_path, dt.date(2016, 1, 1), dt.date(2016, 12, 31))


# ---------------------------------------------------------------------------
# Duplicate-date detection and its scope (whole file, before range-filtering)
# ---------------------------------------------------------------------------
@pytest.mark.unit
def test_duplicate_nav_date_raises(tmp_path):
    csv_path = _write_csv(
        tmp_path, [("1/31/2025", "$100"), ("1/31/2025", "$200")]
    )
    with pytest.raises(NavBackfillCsvError, match="duplicate nav_date"):
        parse_baseline_csv(csv_path, dt.date(2025, 1, 1), dt.date(2025, 12, 31))


@pytest.mark.unit
def test_duplicate_outside_requested_window_still_raises(tmp_path):
    """A duplicate pair BOTH outside [start_date, end_date] must still raise —
    duplicate-detection runs over the whole file before range-filtering
    (module docstring), so a caller narrowing the window cannot accidentally
    hide a data-integrity defect in the untouched portion of the sheet."""
    csv_path = _write_csv(
        tmp_path, [("1/31/2020", "$100"), ("1/31/2020", "$200"), ("6/30/2025", "$300")]
    )
    with pytest.raises(NavBackfillCsvError, match="duplicate nav_date"):
        parse_baseline_csv(csv_path, dt.date(2025, 1, 1), dt.date(2025, 12, 31))


@pytest.mark.unit
def test_out_of_range_rows_silently_excluded_not_an_error(tmp_path):
    """A row genuinely outside the window is a normal, expected shape of a
    caller narrowing scope — NOT a data defect — so it is excluded without
    raising, distinct from the duplicate case immediately above."""
    csv_path = _write_csv(
        tmp_path, [("1/31/2020", "$100"), ("6/30/2025", "$300")]
    )
    rows = parse_baseline_csv(csv_path, dt.date(2025, 1, 1), dt.date(2025, 12, 31))
    assert len(rows) == 1
    assert rows[0].nav_date == dt.date(2025, 6, 30)


@pytest.mark.unit
def test_rows_returned_ascending_by_nav_date(tmp_path):
    csv_path = _write_csv(
        tmp_path, [("6/30/2025", "$300"), ("1/31/2025", "$100"), ("3/31/2025", "$200")]
    )
    rows = parse_baseline_csv(csv_path, dt.date(2025, 1, 1), dt.date(2025, 12, 31))
    assert [r.nav_date for r in rows] == [
        dt.date(2025, 1, 31), dt.date(2025, 3, 31), dt.date(2025, 6, 30)
    ]


@pytest.mark.unit
def test_missing_nav_column_raises(tmp_path):
    csv_path = _write_csv(tmp_path, [("12/31/2025", "$500")], nav_header="NAV (dollars)")
    with pytest.raises(NavBackfillCsvError, match="NAV"):
        parse_baseline_csv(csv_path, dt.date(2025, 1, 1), dt.date(2025, 12, 31))


@pytest.mark.unit
def test_start_after_end_raises():
    with pytest.raises(NavBackfillCsvError):
        parse_baseline_csv("/nonexistent.csv", dt.date(2025, 12, 31), dt.date(2025, 1, 1))


# ---------------------------------------------------------------------------
# First-cron-checkpoint boundary — STRICT, not inclusive
# ---------------------------------------------------------------------------
def _row(date_str, dollars="100000"):
    return BackfillRow(
        nav_date=dt.date.fromisoformat(date_str),
        nav_value_dollars=Decimal(dollars),
        source_row_num=1,
    )


@pytest.mark.unit
def test_no_existing_checkpoint_all_rows_admissible():
    rows = [_row("2020-01-31"), _row("2024-12-31")]
    admissible, refused = split_before_first_checkpoint(rows, None)
    assert admissible == rows
    assert refused == []


@pytest.mark.unit
def test_boundary_is_strict_row_on_boundary_is_refused():
    """⭐ THE OFF-BY-ONE CASE: a row whose nav_date EQUALS the first cron
    checkpoint date must be REFUSED, not admissible — 'strictly before' per
    the module contract, not 'at or before'. Getting this wrong in the
    admissive direction would attempt to write a checkpoint the cron already
    holds (harmless under ON CONFLICT DO NOTHING) but getting it wrong in the
    refusive direction — treating the day BEFORE the boundary as refused too —
    would silently shrink the backfill's admissible range by one row with no
    error, which is the failure mode this test actually guards."""
    first_checkpoint = dt.date(2025, 1, 5)
    rows = [_row("2024-12-31"), _row("2025-01-05"), _row("2025-06-30")]
    admissible, refused = split_before_first_checkpoint(rows, first_checkpoint)
    assert [r.nav_date for r in admissible] == [dt.date(2024, 12, 31)]
    assert [r.nav_date for r in refused] == [dt.date(2025, 1, 5), dt.date(2025, 6, 30)]


@pytest.mark.unit
def test_boundary_day_before_is_admissible():
    """The complement of the case above, stated as its own assertion so the
    two together prove the cut is at the boundary itself and not one day
    early or late in either direction."""
    first_checkpoint = dt.date(2025, 1, 5)
    admissible, refused = split_before_first_checkpoint([_row("2025-01-04")], first_checkpoint)
    assert len(admissible) == 1
    assert refused == []
