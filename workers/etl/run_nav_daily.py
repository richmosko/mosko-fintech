"""
Project:       pfin-back-etl
Author:        Rich Mosko

Description:
    Runnable entry point for the SELF-214 daily-NAV checkpoint worker (W-1
    impersonation model). Computes today's active-only NAV for every
    active-account tenant and appends a frozen checkpoint to pfin.nav_daily.

    Manually runnable:  python run_nav_daily.py   (or via the container).
    Phase-7 Coolify cron scheduling is DEFERRED (F/CTO-ratified) — this file is
    the worker entry point the scheduler will eventually invoke, not the schedule.
"""

import logging
import os
import sys
from datetime import datetime, timezone

from pfin_back_etl import NavDailyWorker

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


def main():
    logger = setup_logging()

    t_start = datetime.now(timezone.utc)
    logger.info(f"Starting daily-NAV checkpoint run at {t_start.isoformat()}")

    worker = NavDailyWorker()
    summary = worker.run()

    t_end = datetime.now(timezone.utc)
    elapsed = t_end - t_start
    logger.info(
        f"Finished at {t_end.isoformat()} (elapsed: {elapsed}) — summary: {summary}"
    )


if __name__ == "__main__":
    main()
