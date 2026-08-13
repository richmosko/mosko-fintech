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

    TRACKED-SAFE SUMMARY (Sec-ruled). Every run also prints a clearly
    delimited, redacted block — pre-import first_cron_checkpoint, run date,
    requested date range, admissible/refused counts, an identity-agreement
    line (first-8-char uid PREFIX only), whether/why --ack-delta was
    required, and the AC5 delta as a PERCENTAGE of the boundary figure
    (never dollars) — safe to paste verbatim into a tracked artifact. The
    real dollar figures and the full UUID stay in the normal full output,
    written to LOG_FILE (temp/nav-history/, gitignored — beside the source
    CSV, not bare CWD) as the local record the summary block points at.

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

# Sec-ruled log location: BESIDE the source CSV in temp/nav-history/, not
# bare CWD — the whole temp/ tree is gitignored (repo .gitignore line 7),
# whereas a bare `pfin_back_etl.log` in an arbitrary CWD is not guaranteed
# to be. This log carries real dollar figures and a full tenant UUID (see
# print_run_record / print_ac5_comparand) — the local gitignored record the
# tracked-safe summary block below points at rather than duplicates.
LOG_FILE = os.path.join("temp", "nav-history", "nav_backfill_run.log")


def setup_logging():
    """Configure logging to write to both stdout and a log file."""
    logger = logging.getLogger("pfin_etl")
    logger.setLevel(logging.INFO)
    formatter = logging.Formatter("%(asctime)s [%(levelname)s] %(message)s")

    console = logging.StreamHandler(sys.stdout)
    console.setFormatter(formatter)
    logger.addHandler(console)

    os.makedirs(os.path.dirname(LOG_FILE), exist_ok=True)
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


def print_run_record(logger, *, resolved_uid, pre_import_first_checkpoint, admissible):
    """Sec AMBER clause (d) — the RUN RECORD. Printed in BOTH dry-run and
    --commit, and always includes the resolved tenant, because a
    SUCCESSFUL import erases the pre-import first_cron_checkpoint boundary
    (the imported rows become the new one) — the run record is the only
    surviving evidence that the tenant-resolution chain resolved correctly
    for THIS run, once that boundary is gone.

    `resolved_uid` is auth.uid() AS THE DATABASE RESOLVED IT while
    impersonating the CLI-supplied users_id (NavBackfillWorker.resolve_uid)
    — not the CLI argument echoed back; the whole point is that this is a
    value the database confirmed, not one this script merely repeated.

    Where this record durably lives at the production run (a log, a ticket,
    a file) is being reconciled with Sec separately — real tenant UUIDs and
    NAV figures cannot enter the repo per the redaction rule, so that
    storage decision is out of this script's scope. This function's only
    job is to make sure every figure that record will need is actually
    EMITTED somewhere a human can capture it.
    """
    logger.info("=== RUN RECORD (Sec AMBER clause (d)) ===")
    logger.info(
        f"RUN RECORD — resolved tenant (auth.uid(), DB-confirmed): "
        f"{resolved_uid}"
    )
    logger.info(
        "RUN RECORD — pre-import first_cron_checkpoint: "
        + (
            pre_import_first_checkpoint.isoformat()
            if pre_import_first_checkpoint
            else "NONE (no prior checkpoint for this tenant)"
        )
    )
    logger.info(f"RUN RECORD — rows to import: {len(admissible)}")
    if admissible:
        logger.info(
            f"RUN RECORD — import date range: "
            f"{admissible[0].nav_date.isoformat()} .. "
            f"{admissible[-1].nav_date.isoformat()}"
        )
    logger.info(
        "RUN RECORD — AC5 comparand figures printed separately below "
        "(imported boundary-month NAV / computed NAV today / delta)."
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


def _uid_prefix(uid):
    """First 8 chars only — the seed.sql precedent for letting a human
    recognize/match a tenant identity in tracked text without the full UUID
    ever landing there."""
    return str(uid)[:8]


def _fmt_percent(delta, boundary_value):
    """AC5 delta AS A PERCENTAGE of the boundary-month figure — Sec's
    keep-structure-redact-dollars shape for the tracked-safe summary: the
    RATIO is safe to paste into a tracked artifact; the dollar figures
    behind it (see print_ac5_comparand) are not."""
    if boundary_value == 0:
        return "N/A (boundary figure is $0)"
    pct = (delta / boundary_value) * 100
    sign = "+" if pct >= 0 else ""
    return f"{sign}{pct:.2f}%"


def print_tracked_safe_summary(
    logger,
    *,
    run_started_at,
    args,
    admissible,
    refused,
    first_checkpoint,
    resolved_uid,
    boundary_row,
    delta,
):
    """Sec-ruled TRACKED-SAFE SUMMARY BLOCK. NO dollar figures, NO full
    UUID — every field here is deliberately safe to paste VERBATIM into a
    tracked artifact (a PR, a doc, a Linear comment) at the F/CTO-gated
    production run. Printed in BOTH dry-run and --commit, after the AC5
    comparand is computed (the percentage below needs it) and before the
    commit gate's decision, so it reflects the run's state regardless of
    whether --commit goes on to proceed or refuse.

    Deliberately a POINTER, not a duplicate, for anything sensitive: the
    full dollar figures live in print_ac5_comparand's output and the full
    UUID lives in print_run_record's — both already written to LOG_FILE
    (temp/nav-history/, gitignored) as part of "the normal full output".
    This block's last line names that file rather than repeating its
    contents.

    `resolved_uid` (not the raw CLI string) backs the identity-agreement
    line: by the time this runs, worker.resolve_uid() has already RAISED if
    the CLI-supplied and DB-resolved identities disagreed (see main()), so
    printing "AGREED" here states a property this function did not have to
    re-check — it was already enforced upstream, fail-closed, before this
    block could ever be reached.
    """
    ack_required = delta is not None and abs(delta) >= _AC5_ACK_THRESHOLD
    logger.info(
        "=== TRACKED-SAFE SUMMARY (no dollar figures, no full UUID — safe "
        "to paste into a tracked artifact) ==="
    )
    logger.info(
        "Pre-import first_cron_checkpoint (the fact this import ERASES): "
        + (
            first_checkpoint.isoformat()
            if first_checkpoint
            else "NONE (no prior checkpoint for this tenant)"
        )
    )
    logger.info(f"Run date (UTC): {run_started_at.date().isoformat()}")
    logger.info(
        f"Requested date range (inclusive): {args.start_date} .. {args.end_date}"
    )
    logger.info(f"Admissible rows: {len(admissible)} | Refused rows: {len(refused)}")
    logger.info(
        f"Tenant identity: CLI-supplied and DB-resolved uid AGREED "
        f"(prefix {_uid_prefix(resolved_uid)}...)"
    )
    logger.info(f"--commit requested: {args.commit}")
    logger.info(
        f"--ack-delta passed: {args.ack_delta} (required for this run: "
        f"{ack_required})"
    )
    if boundary_row is not None and delta is not None:
        logger.info(
            f"AC5 delta as % of the boundary-month figure: "
            f"{_fmt_percent(delta, boundary_row.nav_value_dollars)}"
        )
    else:
        logger.info("AC5 delta: N/A (no admissible rows to compare)")
    logger.info(f"Full local record (dollar figures + full UUID): {LOG_FILE}")


def main(argv=None):
    argv = sys.argv if argv is None else argv
    logger = setup_logging()
    run_started_at = dt.datetime.now(dt.timezone.utc)

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

    # Sec AMBER clause (d) — read-only, runs in BOTH dry-run and --commit,
    # and runs FIRST: if the tenant-resolution chain is broken, nothing
    # downstream (the AC5 comparand, the commit gate, the write itself) is
    # worth attempting either. See NavBackfillWorker.resolve_uid for why
    # this is a separate read from write_backfill's own internal one.
    try:
        resolved_uid = worker.resolve_uid(args.users_id)
    except RuntimeError as exc:
        raise SystemExit(
            f"Tenant resolution failed before anything else ran — refusing "
            f"to proceed. Error: {exc}"
        ) from exc

    print_dry_run_summary(logger, rows, admissible, refused, first_checkpoint)
    print_run_record(
        logger,
        resolved_uid=resolved_uid,
        pre_import_first_checkpoint=first_checkpoint,
        admissible=admissible,
    )

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

    # Sec-ruled TRACKED-SAFE SUMMARY — printed AFTER the AC5 comparand (the
    # percentage line needs `delta`) and BEFORE the commit gate's decision,
    # so it reflects the run's state whether --commit goes on to proceed or
    # refuse. See print_tracked_safe_summary's docstring for why every field
    # in it is safe to paste into a tracked artifact.
    print_tracked_safe_summary(
        logger,
        run_started_at=run_started_at,
        args=args,
        admissible=admissible,
        refused=refused,
        first_checkpoint=first_checkpoint,
        resolved_uid=resolved_uid,
        boundary_row=boundary_row,
        delta=delta,
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
