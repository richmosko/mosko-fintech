"""
Project:       pfin-back-etl
Author:        QA (mosko-fintech)

Description:
    `unit`-tier tests for run_nav_backfill.main()'s AC5 --ack-delta commit
    gate — flagged by Sec (AMBER round, 2026-08-12) as the only automated
    control standing between a units/parse error and a PERMANENT row in an
    append-only, trigger-immutable table (054), with zero coverage at the
    time of the flag.

    STUB-WORKER, NOT A LIVE DATABASE. This file tests CONTROL FLOW ONLY — the
    `abs(delta) >= threshold` branch and the SystemExit-or-proceed it drives —
    not the real computed_nav_today()/write_backfill() round trip, which
    test_nav_backfill_write.py already covers against a real scratch DB. A
    `_StubWorker` stands in for NavBackfillWorker (monkeypatched into
    run_nav_backfill's own namespace, matching where `main()` actually looks
    it up) so every test here runs fully offline: no docker, no scratch DB,
    no credentials. `computed_nav_today` returns a Decimal the test chooses
    directly, so the delta lands exactly where each test needs it — no
    dependence on this app's real computed NAV or any live figure.

    ALL FIGURES ARE SYNTHETIC, chosen only to land on one side or the other
    of the $1,000 threshold — RT-15 parity-fixture posture (SECURITY §4.5):
    no PII, no real account numbers, no real dollar figure anywhere here.

    Runs from a temp cwd (`monkeypatch.chdir(tmp_path)`) so
    run_nav_backfill.py's log FileHandler (which writes `pfin_back_etl.log`
    to whatever the current working directory is) never touches this repo
    checkout.

    IMPORT PATH — self-contained, does not depend on invocation. `uv pip
    install -e .` (both locally and in CI's unit lane) makes src/pfin_back_etl
    importable, but run_nav_backfill.py is a ROOT-level script at
    workers/etl/, outside that src-layout package, so an editable install
    does not put it on sys.path. A local `PYTHONPATH=src:.` invocation masked
    this (the `.` component put workers/etl on sys.path incidentally); CI's
    hermetic `uv run --no-sync pytest -m unit` sets no PYTHONPATH and failed
    with ModuleNotFoundError on every test in this file — reproduced locally
    under CI's exact invocation before this fix, not assumed. The bootstrap
    below derives workers/etl's path from THIS FILE's own location (parent of
    tests/), so the import resolves under any invocation, not just the one
    that happened to work on this machine.
"""

import logging
import sys
from decimal import Decimal
from pathlib import Path

import pytest

_ETL_ROOT = Path(__file__).resolve().parent.parent  # tests/.. == workers/etl
if str(_ETL_ROOT) not in sys.path:
    sys.path.insert(0, str(_ETL_ROOT))

pytestmark = pytest.mark.unit


def _write_csv(tmp_path, date_str, dollars_str):
    """One-row synthetic baseline CSV — see test_nav_backfill.py's _write_csv
    for why csv.writer (not naive string joining) matters for any value that
    could contain the delimiter; these fixture values never do, but the
    idiom is kept consistent across this test suite regardless."""
    import csv

    path = tmp_path / "synthetic_baseline_nav.csv"
    with open(path, "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(["Date", "NAV ($K)"])
        writer.writerow([date_str, dollars_str])
    return str(path)


class _StubWorker:
    """Offline stand-in for NavBackfillWorker. No DB, no docker — just the
    four methods run_nav_backfill.main() actually calls, each returning a
    value the test controls directly."""

    def __init__(self, computed_today):
        self._computed_today = computed_today
        self.run_calls = []

    def resolve_uid(self, users_id):
        # Sec AMBER clause (d) — the run-record tenant-resolution read,
        # added to main() after this file was first drafted (re-synced
        # against Backend's current file before finalizing). Echoing
        # users_id back simulates a CLEAN resolution (no mismatch) so this
        # gate-focused suite isn't exercising that failure mode too — it has
        # its own coverage in test_nav_backfill_write.py's GUC-vacuity test.
        return users_id

    def first_cron_checkpoint(self, users_id):
        # None => nothing to refuse against => the one CSV row is admissible,
        # which is what makes it the boundary_row main() computes AC5 from.
        return None

    def computed_nav_today(self, users_id):
        return self._computed_today

    def run(self, users_id, rows, *, commit):
        self.run_calls.append({"users_id": users_id, "rows": list(rows), "commit": commit})
        return {"total": len(rows), "inserted": len(rows)}


@pytest.fixture
def stubbed_main(tmp_path, monkeypatch):
    """Patches run_nav_backfill.NavBackfillWorker with a factory that
    captures the LAST stub instance constructed, so a test can both control
    computed_nav_today's return value AND inspect whether worker.run() was
    actually invoked (the thing the gate is supposed to prevent when it
    fires). Returns (call_main, get_stub) — call_main(argv, computed_today)
    constructs a fresh stub for that computed_today value on each call."""
    import run_nav_backfill as rnb

    monkeypatch.chdir(tmp_path)
    logging.getLogger("pfin_etl").handlers.clear()  # avoid duplicate handlers across tests

    holder = {}

    def _factory(computed_today):
        def _ctor():
            stub = _StubWorker(computed_today)
            holder["stub"] = stub
            return stub
        monkeypatch.setattr(rnb, "NavBackfillWorker", _ctor)

    def call_main(extra_args, computed_today):
        _factory(computed_today)
        csv_path = _write_csv(tmp_path, "12/31/2025", "$500")  # -> 500000 dollars
        argv = [
            "run_nav_backfill.py",
            "--csv", csv_path,
            "--start-date", "2025-01-01",
            "--end-date", "2025-12-31",
            "--users-id", "00000000-0000-0000-0000-000000000abc",
        ] + extra_args
        rnb.main(argv)

    def get_stub():
        return holder["stub"]

    return call_main, get_stub


# Boundary row is always $500,000 (see _write_csv above) — each test picks
# computed_today so the delta lands exactly where that test needs it.
_BOUNDARY_DOLLARS = Decimal("500000")


def test_commit_refuses_without_ack_delta_when_delta_at_or_above_threshold(stubbed_main):
    """⭐ THE CATCH-CRITERION: a $1,500 delta (>= the $1,000 threshold),
    --commit WITHOUT --ack-delta, must SystemExit and must NOT reach
    worker.run() — the write must never happen, not just the process must
    exit nonzero eventually."""
    call_main, get_stub = stubbed_main
    with pytest.raises(SystemExit):
        call_main(["--commit"], computed_today=_BOUNDARY_DOLLARS + Decimal("1500"))
    assert get_stub().run_calls == []  # the write path was never reached


def test_commit_proceeds_with_ack_delta_at_same_large_delta(stubbed_main):
    """The non-vacuity companion: the IDENTICAL delta that refused above
    proceeds (no SystemExit, worker.run() IS called) once --ack-delta is
    passed — proves the previous test's refusal was the ack-delta gate
    specifically, not some other reason main() might exit early."""
    call_main, get_stub = stubbed_main
    call_main(["--commit", "--ack-delta"], computed_today=_BOUNDARY_DOLLARS + Decimal("1500"))
    assert len(get_stub().run_calls) == 1
    assert get_stub().run_calls[0]["commit"] is True


def test_commit_refuses_at_exact_threshold_boundary(stubbed_main):
    """⭐ THE OFF-BY-ONE CASE: delta of EXACTLY $1,000 must refuse — the gate
    is `>=`, not `>`. A delta of $999.99 (tested below) must NOT refuse; the
    pair proves the boundary sits exactly at $1,000 rather than one cent to
    either side."""
    call_main, get_stub = stubbed_main
    with pytest.raises(SystemExit):
        call_main(["--commit"], computed_today=_BOUNDARY_DOLLARS + Decimal("1000"))
    assert get_stub().run_calls == []


def test_commit_proceeds_just_under_threshold_without_ack_delta(stubbed_main):
    call_main, get_stub = stubbed_main
    call_main(["--commit"], computed_today=_BOUNDARY_DOLLARS + Decimal("999.99"))
    assert len(get_stub().run_calls) == 1


def test_commit_refuses_at_exact_threshold_on_negative_side_too(stubbed_main):
    """The gate reads `abs(delta) >= threshold` — a delta of exactly
    -$1,000 (computed NAV BELOW the imported boundary) must refuse too, not
    just the positive-delta direction exercised above."""
    call_main, get_stub = stubbed_main
    with pytest.raises(SystemExit):
        call_main(["--commit"], computed_today=_BOUNDARY_DOLLARS - Decimal("1000"))
    assert get_stub().run_calls == []


def test_dry_run_never_gates_regardless_of_delta_size(stubbed_main):
    """The ack-delta gate is checked AFTER the dry-run early-return in
    main() — a dry run (no --commit) must never SystemExit on a large delta,
    with or without --ack-delta, because it performs no write for the gate
    to be protecting in the first place."""
    call_main, get_stub = stubbed_main
    call_main([], computed_today=_BOUNDARY_DOLLARS + Decimal("50000"))  # no --commit
    assert get_stub().run_calls == []  # dry run: never reaches worker.run() either
