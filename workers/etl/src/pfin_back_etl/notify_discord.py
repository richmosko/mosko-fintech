"""
Project:       pfin-back-etl
Author:        Rich Mosko (mosko-fintech Backend)

Description:
    SELF-351 (A7) OPERATOR notification — Coolify->Discord, run
    success/failure ONLY (PM A-14, authorized at R10). NEVER a user-facing
    notice: this module has no concept of a user, only a run summary
    ({total, ok, failed, target_month}).

    NEW MODULE, judgment call flagged: there is no existing PYTHON Discord
    notifier in this tree to import. The existing notifier is
    `workers/provider-sync/src/notify/discord.ts` — a different runtime
    (Node/TypeScript, a separate worker container) and a different alert
    domain (CA-2 admission-endpoint-reachability positive detections, with
    its own payload shape). Nothing there is literally importable from a
    Python cron container. What IS reused is its STRUCTURE, deliberately
    mirrored:
      - a PURE payload-builder (build_run_summary_alert) — no I/O, no clock
        read (the timestamp is an injected argument), unit-testable against
        literals;
      - a THIN, FAIL-SAFE poster (post_discord) that SWALLOWS every error
        and NEVER RAISES — a Discord outage must never fail the cron run
        itself (mirrors discord.ts's own C3 property, restated for this
        worker's own failure model: a monthly report cron's job is
        generating drafts, not delivering a notification).

    Uses `requests` (already a resolved, lockfile-pinned dependency of this
    project via `utils.py`'s own `requests.post` call for the BLS CPI fetch
    — see uv.lock) rather than adding a new HTTP dependency or reaching for
    bare `urllib` — supply-chain minimalism cuts both ways: reuse what is
    already vendored before adding OR reinventing.

    `DISCORD_WEBHOOK_URL` — the SAME production_only secret name
    provider-sync's worker and the V1 web-app both already hold
    (secrets-manifest.yml names three consumers; this cron container is
    documented here as a fourth). Read from the environment by the caller
    (run_monthly_report.py), never hardcoded, never logged.
"""

import logging

import requests

logger = logging.getLogger("pfin_etl")

_POST_TIMEOUT_SECONDS = 5


def build_run_summary_alert(summary, now_iso):
    """PURE — build the Discord payload for one monthly_report cron run.

    `summary` is the dict MonthlyReportCronWorker.run() returns
    ({total, ok, failed, target_month}). `now_iso` is an INJECTED
    timestamp string (no clock read here), matching discord.ts's
    buildCa2Alert's own determinism convention so this function
    unit-tests against literals.

    Content carries ONLY counts, the target month, and the timestamp —
    never a users_id, a report_id, or any field from a tenant's own data.
    This is an OPERATOR summary of the RUN, not a per-tenant report.
    """
    failed = summary["failed"]
    ok = summary["ok"]
    total = summary["total"]
    target_month = summary["target_month"]

    if failed == 0:
        emoji = "✅"
        title = "monthly_report cron — run complete"
    else:
        emoji = "\U0001f6a8"
        title = "monthly_report cron — run completed WITH FAILURES"

    return {
        "content": f"{emoji} monthly_report cron: {ok}/{total} tenants ok, {failed} failed",
        "embeds": [
            {
                "title": title,
                "description": (
                    "SELF-351 (A7) — one scheduled run generates the prior "
                    "month's draft per tenant under tenant binding; "
                    "per-tenant failures are isolated (one bad tenant costs "
                    "one tenant)."
                ),
                "fields": [
                    {"name": "target_month", "value": str(target_month)},
                    {"name": "total", "value": str(total)},
                    {"name": "ok", "value": str(ok)},
                    {"name": "failed", "value": str(failed)},
                    {"name": "run_at_utc", "value": now_iso},
                ],
            }
        ],
    }


def post_discord(webhook_url, payload):
    """THIN, FAIL-SAFE poster. Returns True on an apparent success (2xx),
    False on ANY failure (bad status, network error, timeout, missing URL)
    — NEVER raises. A Discord outage, a revoked webhook, or a missing
    DISCORD_WEBHOOK_URL must never fail the cron run this notification is
    ABOUT; the run's own exit code (see run_monthly_report.py) is the real
    fleet-fatal signal, not this best-effort courtesy notice.

    `webhook_url` is a FALSY-checked argument (never read from the
    environment inside this function) so a caller can pass `None` when
    unset and get a clean, logged no-op rather than this module needing its
    own environment-reading convention.
    """
    if not webhook_url:
        logger.info(
            "notify_discord: DISCORD_WEBHOOK_URL not set — skipping the "
            "operator notification (the cron run itself is unaffected)."
        )
        return False
    try:
        response = requests.post(
            webhook_url, json=payload, timeout=_POST_TIMEOUT_SECONDS
        )
        if response.status_code >= 200 and response.status_code < 300:
            return True
        logger.warning(
            f"notify_discord: webhook returned status {response.status_code} "
            "(cron run result is unaffected)."
        )
        return False
    except Exception:
        logger.exception(
            "notify_discord: POST to Discord webhook failed (cron run "
            "result is unaffected)."
        )
        return False
