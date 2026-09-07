"""
Project:       pfin-back-etl
Author:        Rich Mosko

Description:
    Runnable entry point for the SELF-351 (A7) monthly_report cron worker.
    Generates the PRIOR month's `pfin.monthly_report` draft for every
    account-owning tenant.

    Manually runnable:  python run_monthly_report.py   (or via the container).
    COMMAND NAME PROPOSED TO DEVOPS for the Coolify native cron container
    (1st-of-month schedule, DevOps-owned): `python run_monthly_report.py` —
    mirrors run_nav_daily.py / run_nav_backfill.py / run_cpi_backfill.py's
    existing naming convention exactly, so the fourth cron entrypoint reads
    the same way as the first three at a glance.

    Coolify->Discord (PM A-14): a best-effort OPERATOR notification of run
    success/failure is posted after the run completes, via
    notify_discord.py. It NEVER affects this script's own exit code — a
    Discord outage must not be confused with a monthly_report generation
    failure. The real fleet-fatal signal for Coolify's own routing is this
    process's exit code: non-zero when even one tenant failed (`failed > 0`),
    matching nav_daily.py's/nav_backfill.py's own posture of surfacing a
    per-tenant failure count rather than treating any single failure as
    fully fleet-fatal (the run still generates every OTHER tenant's draft).
"""

import logging
import os
import sys
from datetime import datetime, timezone

from pfin_back_etl import MonthlyReportCronWorker
from pfin_back_etl.notify_discord import build_run_summary_alert, post_discord

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
    logger.info(f"Starting monthly_report cron run at {t_start.isoformat()}")

    worker = MonthlyReportCronWorker()
    summary = worker.run()

    t_end = datetime.now(timezone.utc)
    elapsed = t_end - t_start
    logger.info(
        f"Finished at {t_end.isoformat()} (elapsed: {elapsed}) — summary: {summary}"
    )

    payload = build_run_summary_alert(summary, t_end.isoformat())
    post_discord(os.environ.get("DISCORD_WEBHOOK_URL"), payload)

    if summary["failed"] > 0:
        sys.exit(1)


if __name__ == "__main__":
    main()
