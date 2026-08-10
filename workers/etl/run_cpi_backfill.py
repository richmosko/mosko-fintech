"""
Project:       pfin-back-etl
Author:        Rich Mosko (mosko-fintech Backend)

Description:
    Runnable entry point for the one-shot CPI-U historical backfill into
    pfin.cpi_u_index (BLS series CUUR0000SA0). Lays down a row for every month
    from Dec-2015 through the current month; idempotent, because the underlying
    write is an UPSERT on cpi_period — re-running rewrites the same values and
    never duplicates.

    Manually runnable:  python run_cpi_backfill.py [start_year]

    ⚠ WHY THIS FILE EXISTS AT ALL — BACKLOG §7.6 S18. `backfill_cpi_u_index()`
    had ZERO callers outside a single integration test. `run_nav_daily.py`
    existed; this did not. So the only ways to run the backfill were (i) pytest
    through the `backend` fixture, whose over-broad `except` was S16's
    concealment, or (ii) an uncommitted scratchpad — which is precisely the
    shape S10 named: a verification gate that cannot be run without writing
    code outside the repo tends not to get run. S11 is this project's own
    worked example of what that costs (a barrier nobody had to name kept the
    assembled path unrun, and the defect behind it sat latent ~50 migrations).

    Committing the runner is what makes an acceptance run REPRODUCIBLE BY
    SOMEONE OTHER THAN ITS AUTHOR, which is the property that distinguishes a
    discharge from an anecdote.

    ⚠ THIS IS NOT REACHABLE VIA `main.py`, AND THAT IS NOT AN OVERSIGHT.
    `update_table_all()` calls `update_table_cpi()` — targeting `pfin.cpi`,
    which NO V1 migration creates — BEFORE the CPI-U step, so the container
    entry point raises UndefinedTable and never reaches CPI-U. That scope
    question (7 of 10 ingest paths target tables V1 does not create) is PM +
    Architect's and tracked separately; this runner exists so the CPI-U path is
    reachable regardless of how it resolves.

    Phase-7 Coolify cron scheduling is DEFERRED (F/CTO-ratified). This is the
    entry point a scheduler would invoke, not the schedule.
"""

import logging
import os
import sys
from datetime import datetime, timezone

from pfin_back_etl import PFinBackend
from pfin_back_etl.core import CPI_U_BASE_YEAR

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

    logging.getLogger("FMPStab").setLevel(logging.WARNING)
    return logger


def parse_start_year(argv):
    """First positional arg, or CPI_U_BASE_YEAR.

    Rejects a non-integer loudly rather than silently falling back to the
    default: a typo'd year that quietly becomes 2015 would look like a
    successful full backfill while having been asked for something else.
    """
    if len(argv) < 2:
        return CPI_U_BASE_YEAR
    try:
        return int(argv[1])
    except ValueError:
        raise SystemExit(
            f"start_year must be an integer year, got {argv[1]!r}. Refusing to "
            f"fall back to {CPI_U_BASE_YEAR} — a silent default would report a "
            f"full backfill for a run that asked for something else."
        )


def main(argv=None):
    argv = sys.argv if argv is None else argv
    logger = setup_logging()
    start_year = parse_start_year(argv)

    t_start = datetime.now(timezone.utc)
    logger.info(
        f"Starting CPI-U backfill at {t_start.isoformat()} "
        f"(start_year={start_year})"
    )

    pfb = PFinBackend()
    pfb.backfill_cpi_u_index(start_year=start_year)

    t_end = datetime.now(timezone.utc)
    logger.info(
        f"Finished at {t_end.isoformat()} (elapsed: {t_end - t_start})"
    )


if __name__ == "__main__":
    main()
