"""
Project:       pfin-back-etl
Author:        Rich Mosko (mosko-fintech Backend)

Description:
    Runnable entry point for the SELF-217 one-shot historical NAV backfill.
    Reads F/CTO's exported net-worth spreadsheet (baseline_nav.csv) and lays
    down pfin.nav_daily checkpoints for the period BEFORE the SELF-214
    forward-only cron existed for the target tenant. See
    pfin_back_etl/nav_backfill.py for the full contract (AC7 write path,
    first-cron-checkpoint refusal boundary, CSV parsing rules).

    DRY-RUN BY DEFAULT. Parses the CSV, determines the target tenant's
    first-cron-checkpoint boundary (a READ — safe in dry-run), and prints row
    count / date range / first & last row / admissible vs refused counts, all
    IN DOLLARS. Writes nothing to any database without an explicit --commit.
    ⚠ F/CTO ruling: dollars, never $K — a units error here becomes a
    PERMANENT row in an append-only, trigger-immutable table (054).

    EVERY ARGUMENT BELOW IS REQUIRED, WITH NO DEFAULT, DELIBERATELY. A silent
    default for the CSV path, the date range, or the target tenant would let
    this script run against the wrong file, the wrong window, or the wrong
    user without saying so — for a write with no UPDATE path to correct it
    afterward, "ran with the default" is not an acceptable failure mode.

    Manually runnable:
        python run_nav_backfill.py \\
            --csv temp/nav-history/baseline_nav.csv \\
            --start-date 2015-12-31 --end-date 2026-12-31 \\
            --users-id <uuid>
        # add --commit to actually write, after reviewing the dry run.
        # if the printed AC5 delta is >= $1,000, --commit also needs --ack-delta.

    AC5 (F/CTO-ratified 2026-08-12). Every run — dry-run AND --commit — reads
    (read-only) and prints the imported boundary-month NAV (the most recent
    row this backfill would admit) alongside this app's own computed NAV
    today, and their delta, in dollars. This is a continuity sanity check,
    not a reconciliation — the two dates differ, so a nonzero delta is
    expected. F/CTO judges the number; --commit additionally REFUSES to run
    without --ack-delta whenever |delta| >= $1,000 (the source CSV's
    whole-$K quantization floor — see nav_backfill.py's precision note).

    This is a ONE-SHOT script, not a recurring worker — there is no cron
    entry for it and none is planned. The real seeding run against a
    production tenant is F/CTO-gated, after this ships.
"""

import argparse
import datetime as dt
import logging
import os
import sys
from decimal import Decimal

from pfin_back_etl import NavBackfillWorker
from pfin_back_etl.nav_backfill import NavBackfillCsvError, parse_baseline_csv, split_before_first_checkpoint

# AC5 (F/CTO-ratified 2026-08-12): the source's whole-$K quantization floor —
# see the CSV-precision report (temp/nav-history/ inspection, 2026-08-12).
# No tighter automatic gate; this is where --commit starts requiring
# --ack-delta, not a claim that a smaller delta is "fine".
_AC5_ACK_THRESHOLD = Decimal(1000)

LOG_FILE = os.path.join(os.getcwd(), "pfin_back_etl.log")


def setup_logging():
    """Configure logging to write to both stdout and a log file."""
    logger = logging.getLogger("pfin_etl")
    logger.setLevel(logging.INFO)
    formatter = logging.Formatter("%(asctime)s [%(levelname)s] %(message)s")

    console = logging.StreamHandler(sys.stdout)
    console.setFormatter(formatter)
    logger.addHandler(console)

    file_handler = logging.FileHandler(LOG_FILE, mode="a")
    file_handler.setFormatter(formatter)
    logger.addHandler(file_handler)

    return logger


def _parse_date_arg(raw):
    try:
        return dt.date.fromisoformat(raw)
    except ValueError as exc:
        raise argparse.ArgumentTypeError(f"{raw!r} is not YYYY-MM-DD: {exc}")


def parse_args(argv):
    parser = argparse.ArgumentParser(
        description=(
            "SELF-217 one-shot historical NAV backfill (dry-run by default; "
            "pass --commit to write)."
        )
    )
    parser.add_argument(
        "--csv",
        required=True,
        help="Path to the baseline NAV CSV. No default — must be given explicitly.",
    )
    parser.add_argument(
        "--start-date",
        required=True,
        type=_parse_date_arg,
        help="Inclusive lower bound, YYYY-MM-DD. No default.",
    )
    parser.add_argument(
        "--end-date",
        required=True,
        type=_parse_date_arg,
        help="Inclusive upper bound, YYYY-MM-DD. No default.",
    )
    parser.add_argument(
        "--users-id",
        required=True,
        help=(
            "Target tenant users_id (UUID). No default — a wrong or omitted "
            "tenant would misattribute a permanent financial record to the "
            "wrong account."
        ),
    )
    parser.add_argument(
        "--commit",
        action="store_true",
        default=False,
        help="Actually write. Omit for a dry run (default).",
    )
    parser.add_argument(
        "--ack-delta",
        action="store_true",
        default=False,
        help=(
            "AC5: required alongside --commit whenever the reported "
            "|delta| between the imported boundary-month NAV and this "
            "app's own computed NAV today is >= $1,000. Read the printed "
            "numbers before passing this — it is an acknowledgement, not a "
            "formality."
        ),
    )
    args = parser.parse_args(argv[1:])
    if args.start_date > args.end_date:
        parser.error(
            f"--start-date {args.start_date} is after --end-date {args.end_date}"
        )
    return args


def _fmt_dollars(value):
    """DOLLARS, never $K. See module docstring — this is the F/CTO-ruled
    units-safety print for every row this script reports."""
    return f"${value:,.2f}"


def print_dry_run_summary(logger, rows, admissible, refused, first_checkpoint):
    logger.info(f"Parsed {len(rows)} row(s) in the requested date range.")
    if rows:
        logger.info(
            f"Date range: {rows[0].nav_date.isoformat()} .. "
            f"{rows[-1].nav_date.isoformat()}"
        )
        logger.info(
            f"First row: {rows[0].nav_date.isoformat()} = "
            f"{_fmt_dollars(rows[0].nav_value_dollars)}"
        )
        logger.info(
            f"Last row:  {rows[-1].nav_date.isoformat()} = "
            f"{_fmt_dollars(rows[-1].nav_value_dollars)}"
        )
    logger.info(
        "Tenant's first recorded pfin.nav_daily checkpoint: "
        + (first_checkpoint.isoformat() if first_checkpoint else "NONE yet")
    )
    logger.info(f"Admissible (would write): {len(admissible)}")
    logger.info(f"Refused (nav_date >= first checkpoint): {len(refused)}")
    if refused:
        logger.warning(
            f"Refused date range: {refused[0].nav_date.isoformat()} .. "
            f"{refused[-1].nav_date.isoformat()} — these overlap (or follow) "
            f"the tenant's existing checkpoint history and are OUT OF SCOPE "
            f"for this backfill."
        )


def print_ac5_comparand(logger, boundary_row, computed_today, delta):
    """AC5 (F/CTO-ratified 2026-08-12): the imported boundary-month NAV
    alongside this app's own computed NAV today, and their delta — always in
    dollars, always printed, never collapsed to a pass/fail. The reader
    judges the numbers; this function's only job is to make sure the numbers
    are the ones actually reported."""
    logger.info(
        f"AC5 comparand — imported boundary-month NAV "
        f"({boundary_row.nav_date.isoformat()}): "
        f"{_fmt_dollars(boundary_row.nav_value_dollars)}"
    )
    logger.info(
        f"AC5 comparand — this app's own computed NAV today: "
        f"{_fmt_dollars(computed_today)}"
    )
    logger.info(
        f"AC5 comparand — delta (computed today - imported boundary-month): "
        f"{_fmt_dollars(delta)}"
    )
    if abs(delta) >= _AC5_ACK_THRESHOLD:
        logger.warning(
            f"AC5 comparand: |delta| = {_fmt_dollars(abs(delta))} >= "
            f"{_fmt_dollars(_AC5_ACK_THRESHOLD)} (the source's whole-$K "
            f"quantization floor). --commit will refuse to run without "
            f"--ack-delta."
        )


def main(argv=None):
    argv = sys.argv if argv is None else argv
    logger = setup_logging()

    try:
        args = parse_args(argv)
    except SystemExit:
        raise

    logger.info(
        f"SELF-217 NAV backfill: csv={args.csv!r} range=[{args.start_date}, "
        f"{args.end_date}] users_id={args.users_id} commit={args.commit}"
    )

    try:
        rows = parse_baseline_csv(args.csv, args.start_date, args.end_date)
    except NavBackfillCsvError as exc:
        raise SystemExit(f"CSV parse failed, refusing to proceed: {exc}") from exc

    worker = NavBackfillWorker()
    first_checkpoint = worker.first_cron_checkpoint(args.users_id)
    admissible, refused = split_before_first_checkpoint(rows, first_checkpoint)

    print_dry_run_summary(logger, rows, admissible, refused, first_checkpoint)

    # AC5 (F/CTO-ratified 2026-08-12) — read-only, runs in BOTH dry-run and
    # --commit. boundary_row is the most recent ADMISSIBLE row (the historical
    # figure closest to where the live cron takes over); no admissible rows
    # means nothing to compare, and --commit would write zero rows anyway.
    boundary_row = admissible[-1] if admissible else None
    delta = None
    if boundary_row is not None:
        computed_today = worker.computed_nav_today(args.users_id)
        delta = computed_today - boundary_row.nav_value_dollars
        print_ac5_comparand(logger, boundary_row, computed_today, delta)
    else:
        logger.info(
            "AC5 comparand: no admissible rows — nothing to compare against "
            "this app's own computed NAV."
        )

    if not args.commit:
        logger.info("DRY RUN — no writes performed. Pass --commit to write for real.")
        return

    if delta is not None and abs(delta) >= _AC5_ACK_THRESHOLD and not args.ack_delta:
        raise SystemExit(
            f"Refusing to commit: |delta| = {_fmt_dollars(abs(delta))} >= "
            f"{_fmt_dollars(_AC5_ACK_THRESHOLD)} between the imported "
            f"boundary-month NAV ({_fmt_dollars(boundary_row.nav_value_dollars)} "
            f"@ {boundary_row.nav_date.isoformat()}) and this app's own "
            f"computed NAV today. Review the numbers printed above and "
            f"re-run with --ack-delta to proceed."
        )

    logger.warning(
        f"COMMIT — writing {len(admissible)} checkpoint(s) for "
        f"users_id={args.users_id} in ONE transaction (ADR-053 Decision 6: "
        f"all rows or none)."
    )
    t_start = dt.datetime.now(dt.timezone.utc)
    try:
        summary = worker.run(args.users_id, admissible, commit=True)
    except Exception as exc:
        # ADR-053 Decision 6 — write_backfill() is all-or-nothing and does
        # NOT isolate a per-row failure, so anything raised here means the
        # WHOLE transaction rolled back: ZERO rows committed. Converted to a
        # SystemExit (not a bare traceback) for the same reason the CSV-parse
        # failure above is — a fail-loud, human-readable exit rather than a
        # stack trace to reinterpret.
        raise SystemExit(
            f"Backfill FAILED and rolled back — ZERO rows committed "
            f"(ADR-053 Decision 6: all rows or none). Error: {exc}"
        ) from exc
    t_end = dt.datetime.now(dt.timezone.utc)
    logger.info(
        f"Backfill complete (elapsed: {t_end - t_start}) — summary: {summary}"
    )


if __name__ == "__main__":
    main()
