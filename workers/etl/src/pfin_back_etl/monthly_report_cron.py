"""
Project:       pfin-back-etl
Author:        Rich Mosko (mosko-fintech Backend)

Description:
    SELF-351 (A7) monthly_report cron worker. Native Coolify cron container,
    fires on the 1st of each month, and generates the PRIOR month's
    `pfin.monthly_report` DRAFT for every account-owning tenant.

    Tenant binding — RULED at R3 (i), option alpha: IMPERSONATION, reusing
    the shipped module (connection.py's TenantBoundConnection). This file
    does not re-specify that primitive; it calls it exactly as nav_daily.py
    / nav_backfill.py already do for tenant ENUMERATION (system-mode,
    service_role) and per-tenant IMPERSONATION.

    WHAT THIS WORKER DOES, IN ONE PARAGRAPH. Enumerate every account-owning
    tenant (service_role; cross-tenant enumeration is legitimate here, same
    reasoning as nav_daily.py's account_user_ids). For each tenant, in its
    own transaction: impersonate the tenant and call
    `pfin.fn_open_monthly_report_draft(p_target_month)` — the SAME
    INSERT-new-version shape A10 (the on-demand endpoint) uses, per AC 2/7 —
    which is idempotent (opens an existing live draft rather than duplicating
    it) and writes its own same-transaction audit row. This worker NEVER
    finalizes, never skips, and never writes anything else (AC 5).

    ⚠⚠ FLAG 1 (routed to Sec's mandatory joint review, NOT resolved here) —
    THIS IS THE FIRST CALLER TO PERFORM A WRITE FROM INSIDE
    `TenantBoundConnection.impersonate()`'s BLOCK.

    connection.py's own docstring is explicit: "THIS IS A READ-ONLY
    PRIMITIVE... and it MUST NEVER WRAP A WRITE," enforced (mostly) by
    `_reject_write_while_impersonating`, which fails closed on any
    write/DDL-headed statement. But `select
    pfin.fn_open_monthly_report_draft(:target_month)` has HEAD 'select' — a
    member of `_IMPERSONATION_ALLOWED_HEADS` — because it is a FUNCTION CALL
    via SELECT, not a literal INSERT statement. connection.py's own comment
    names exactly this residual: "a select that invokes a data-modifying
    function... is not statically detectable and passes. The fence bounds
    the statement surface, not function bodies." So this call is NOT
    rejected by the Python-side assertion, even though the function's BODY
    performs a real, privileged INSERT (into `pfin.monthly_report`) plus a
    call to a SECURITY DEFINER audit helper.

    This is not a shortcut taken for convenience — it is FORCED by 113's own
    signature: `fn_open_monthly_report_draft(p_target_month date) returns
    bigint` takes NO `p_users_id` parameter. Per its own AC 1 / header ("NO
    TENANT PARAMETER ANYWHERE... the session IS the tenant binding"), it
    attributes the INSERT's `users_id` ENTIRELY via `pfin.monthly_report`'s
    `auth.uid()` column DEFAULT — there is no argument through which this
    Python code could hand it a database-resolved literal, the way
    nav_daily.py / nav_backfill.py's OWN INSERT statements do (they build
    their own SQL naming `users_id` as a bound parameter, entirely outside
    `impersonate()`, which is why THEIR writes correctly happen AFTER
    teardown under `service_role`). And `fn_open_monthly_report_draft`'s
    EXECUTE grant is to `authenticated` ONLY (`revoke ... from public; grant
    ... to authenticated;` — no grant to `service_role` at all), so the
    established "exit impersonation, assume service_role, write" shape used
    everywhere else in this codebase is not merely a style choice here — it
    is MECHANICALLY UNAVAILABLE: `service_role` has no EXECUTE grant on this
    function, and even if it did, `service_role`'s own `auth.uid()` is NULL
    once impersonation's teardown clears the JWT-claims GUC, which would
    violate `pfin.monthly_report.users_id`'s NOT NULL constraint via its own
    DEFAULT.

    SELF-351 AC 2 rules "IMPERSONATION, reusing the shipped module. Do not
    re-specify it" for this exact tenant-binding need, and this file takes
    that as having already decided the SHAPE — but the specific tension with
    connection.py's own "must never wrap a write" invariant is NOT spelled
    out anywhere on the tree, and connection.py's docstring has not been
    amended to name an exception. Flagged prominently here and in the SELF-
    351 hand-off report for Sec's mandatory joint review (AC 10) to rule:
    (a) accept this as a ratified exception and amend connection.py's
    docstring to name it, or (b) give `fn_open_monthly_report_draft` (or a
    cron-specific sibling) a `p_users_id` parameter usable from a
    `service_role` write, matching every OTHER writer in this codebase, and
    rebuild this call site against the new signature. This file does
    NEITHER unilaterally — it implements the dispatched shape and names the
    tension rather than silently resolving or silently ignoring it.

    ⚠⚠ FLAG 2 (routed to Architect, NOT resolved here) — THE AUDIT ROW'S
    `trigger_source` IS HARDCODED TO THE LITERAL 'on_demand' INSIDE 113's
    BODY, WITH NO PARAMETER OR GUC TO VARY IT.

    `fn_open_monthly_report_draft`'s own `perform pfin.fn_emit_audit_log(...)`
    call passes the literal string `'on_demand'` as the trigger-source
    argument — there is no `p_trigger_source` parameter on the function and
    no GUC read for it. SELF-351 AC 6 requires this cron's audit row to
    carry `trigger_source = 'cron'` (ADR-011 Decision 1 clause (d); R12
    clause (2) reads exactly this field). AS 113 IS CURRENTLY AUTHORED, every
    draft this worker opens is audit-logged indistinguishably from A10's own
    on-demand path — a real, measured contradiction of AC 6, not a
    hypothetical one. This module does NOT work around it (no second
    `fn_emit_audit_log` call is issued from here — that would produce TWO
    audit rows for one generation event, which block AH's own design
    explicitly does not want: "the ROW MUST BE WRITTEN IN THE SAME
    TRANSACTION AS THE PRIVILEGED WRITE IT DESCRIBES," singular). Migration
    113 is Architect-owned and read-only to Backend; this needs EITHER a
    `p_trigger_source text default 'on_demand'` parameter Architect adds (A10
    keeps passing nothing / the default, unchanged behavior) or another
    Architect-ruled mechanism. Flagged in the hand-off report; the test
    battery below asserts the CURRENT, measured value so this gap is visible
    in the tree rather than merely described in prose.

    Coolify->Discord (PM A-14, SELF-351 AC 5): the OPERATOR channel for run
    success/failure ONLY, never a user-facing notice. See
    notify_discord.py — a new, minimal Python module (no existing Python
    Discord notifier to reuse; workers/provider-sync/src/notify/discord.ts is
    the existing PATTERN this mirrors — pure payload builder + a thin,
    fail-safe poster that never raises — but it is a different runtime
    (Node) and a different alert domain (CA-2 probe detections), so nothing
    there is literally importable here).

    Lock anchors: Lock 11 mod #4 (cron tenant binding) · Lock 13 mod #3 (TBC)
    · migration 108 (pfin.monthly_report) · migration 111
    (pfin.fn_emit_audit_log / block AH) · migration 113
    (pfin.fn_open_monthly_report_draft).
"""

import datetime as dt
import logging

import sqlalchemy as sqla

from pfin_back_etl import utils
from pfin_back_etl.connection import TenantBoundConnection

logger = logging.getLogger("pfin_etl")

# ADR-023 write role-of-record — identical constant to nav_daily.py /
# nav_backfill.py. `pfin_etl` is NOINHERIT; tenant enumeration needs
# `service_role`'s cross-tenant `select` grant on `pfin.account`.
_SET_WRITE_ROLE = "set local role service_role"

# The single call this worker makes per tenant. HEAD 'select' — see module
# docstring FLAG 1 for why this passes connection.py's read-only assertion
# even though the function body writes.
_OPEN_DRAFT_STMT = (
    "select pfin.fn_open_monthly_report_draft(:target_month) as report_id"
)


def prior_month_first_day(today):
    """The first calendar day of the month BEFORE `today`'s month. Pure,
    unit-testable without a clock or a DB connection — the caller supplies
    `today`, which this module derives from the WORKER'S OWN Postgres
    session (`select current_date`), NOT Python's local clock.

    ⚠ WHY `current_date` FROM THIS WORKER'S OWN SESSION, NOT
    `pfin.fn_server_today()`: migration 070's own comment states this
    explicitly — "THE ETL WORKER IS THE DOCUMENTED EXCEPTION, NOT A TARGET:
    it already derives current_date in its own session, and ADR-044
    explicitly warns against 'harmonizing' it onto this helper — that adds a
    round trip and buys nothing." nav_daily.py's own checkpoint INSERT
    already relies on the identical convention (`current_date` inline in the
    production SQL, never a Python `datetime.date.today()` read). This
    function mirrors that: ONE read, at the start of a run, applied to
    EVERY tenant in it (ONE CALL, ONE CLOCK) — not a per-tenant clock read
    that could disagree with itself mid-run.

    `p_target_month` (unlike `p_data_as_of`, which 113 derives internally
    and never accepts as a parameter — RT-25) is explicitly "the caller's
    legitimate choice" per 113's own docstring; a wrong target_month due to
    a session-timezone residual (AC 9's recorded-not-discharged UTC-pin
    concern) targets the wrong MONTH, which 108's own CHECK/RLS/uniqueness
    still safely constrains — it is not a security bypass, only a possible
    off-by-one-month edge near a boundary, the SAME residual AC 9 already
    names and explicitly declines to discharge here.
    """
    first_of_this_month = today.replace(day=1)
    last_of_prior_month = first_of_this_month - dt.timedelta(days=1)
    return last_of_prior_month.replace(day=1)


class MonthlyReportCronWorker:
    """SELF-351 (A7) monthly_report cron worker.

    Construct once, then call run() to generate the PRIOR month's draft for
    every account-owning tenant. See module docstring for the two flags
    (impersonate()-wraps-a-write; trigger_source hardcoding) this
    implementation carries forward rather than silently resolving.
    """

    def __init__(self, env_prefix="PFIN_"):
        # DB parameters ONLY (S12 precedent) — this worker makes no external
        # API call other than the Discord operator notification, which reads
        # its own DISCORD_WEBHOOK_URL separately (see notify_discord.py); it
        # is never handed a data-source credential it does not need.
        self._params = utils.load_db_params(env_prefix)
        self._db_url = utils.build_database_url(self._params)
        # System-mode engine for tenant ENUMERATION only (no per-tenant
        # assertion registers — exemption by construction, identical
        # reasoning to nav_daily.py's account_user_ids). Per-tenant work
        # below always opens a FRESH for_tenant() TBC — never this engine.
        self._system_tbc = TenantBoundConnection.system(self._db_url)

    # ------------------------------------------------------------------ #
    # Tenant enumeration (service_role; legitimate cross-tenant read).
    # ------------------------------------------------------------------ #
    def account_user_ids(self):
        """Distinct users_id owning AT LEAST ONE ACCOUNT — mirrors
        nav_daily.py's account_user_ids() verbatim rationale: a monthly
        financial report is only meaningful for a tenant who owns an
        account, and enumerating every account-owning tenant (rather than
        every `auth.users` row) yields a real, distinguishable outcome for
        a tenant who owns only closed accounts, instead of a silent gap.

        Judgment call, flagged: SELF-351's AC does not pin this predicate
        explicitly (unlike A9's/nav_daily's own ACs, which are the model
        this mirrors) — this is the ONLY existing per-tenant enumeration
        precedent in this codebase, so it is the default rather than an
        independently-derived choice; call it out if PM/Architect intended
        a different population (e.g. every registered user regardless of
        accounts).

        Runs AS `service_role`, assumed explicitly — see nav_daily.py's
        identical method for the full grant/RLS-bypass rationale.
        """
        stmt = sqla.text("select distinct users_id from pfin.account")
        with self._system_tbc.engine.connect() as conn:
            with conn.begin():
                conn.execute(sqla.text(_SET_WRITE_ROLE))
                rows = conn.execute(stmt).fetchall()
        return [row[0] for row in rows]

    # ------------------------------------------------------------------ #
    # Server-derived "today" — ONE read, reused for every tenant in a run.
    # ------------------------------------------------------------------ #
    def server_today(self):
        """`current_date` as THIS WORKER'S OWN Postgres session resolves it
        (system-mode; no tenant context needed — see prior_month_first_day's
        docstring for why this is NOT `pfin.fn_server_today()`)."""
        with self._system_tbc.engine.connect() as conn:
            with conn.begin():
                return conn.execute(sqla.text("select current_date")).scalar()

    # ------------------------------------------------------------------ #
    # Per-tenant impersonated draft-open (one txn). See module docstring
    # FLAG 1 for why the write happens INSIDE impersonate()'s block here,
    # unlike every other writer in this codebase.
    # ------------------------------------------------------------------ #
    def open_draft_for_tenant(self, users_id, target_month):
        """Open (or find) `users_id`'s live draft for `target_month` via
        `pfin.fn_open_monthly_report_draft` — ONE call, ONE transaction, per
        tenant. Idempotent (108's partial unique index + 113's own
        insert-then-reread-on-conflict shape — see 113's header): a re-run
        for a month that already has a live draft returns that draft's id
        and writes nothing new.

        Returns the report_id.

        `impersonate()`'s own teardown (connection.py's `finally` block)
        unconditionally clears the JWT-claims GUC and issues `reset role` on
        exit — success or exception — which is this call's ONLY reset-role
        discipline: a fresh `for_tenant()` TBC (hence a fresh engine, hence
        under `NullPool` a fresh physical connection) is opened per tenant,
        so there is nothing for one tenant's session state to leak INTO for
        the next — see test_monthly_report_cron.py's leaked-SET legs for the
        concrete, DB-verified proof of both halves (teardown fires; a
        subsequent tenant is unaffected even if it didn't).
        """
        tbc = TenantBoundConnection.for_tenant(self._db_url, users_id)
        with tbc.engine.connect() as conn:
            with conn.begin():
                with tbc.impersonate(conn):
                    report_id = conn.execute(
                        sqla.text(_OPEN_DRAFT_STMT),
                        {"target_month": target_month},
                    ).scalar()
        logger.info(
            f"monthly_report draft users_id={users_id} "
            f"target_month={target_month} report_id={report_id}"
        )
        return report_id

    # ------------------------------------------------------------------ #
    # Monthly entry — the prior month's draft for every account-owning
    # tenant. Fires on Coolify's 1st-of-month schedule (DevOps-owned).
    # ------------------------------------------------------------------ #
    def run(self):
        """Generate the PRIOR month's `pfin.monthly_report` draft for every
        account-owning tenant. Per-tenant failures are isolated and logged
        (mirrors nav_daily.py's run()) — one bad tenant does not abort the
        whole run, and a tenant whose call raises leaves no partial row
        (113's own body is one transaction; a raised exception rolls the
        WHOLE transaction back, including the audit row — see 113's
        header). Never finalizes, never skips a tenant's turn, never writes
        anything beyond the one `fn_open_monthly_report_draft` call (AC 5).

        Returns a summary dict {total, ok, failed, target_month}.
        """
        logger.info("==== " * 16)
        logger.info(
            "==== Running monthly_report cron (SELF-351 A7; prior month, "
            "impersonation-bound, no finalize, no skip)"
        )
        today = self.server_today()
        target_month = prior_month_first_day(today)
        logger.info(f"Server today={today}; target_month={target_month}")

        user_ids = self.account_user_ids()
        logger.info(f"Tenants to generate: {len(user_ids)}")

        ok = 0
        failed = 0
        for users_id in user_ids:
            try:
                self.open_draft_for_tenant(users_id, target_month)
                ok += 1
            except Exception as exc:  # isolate per-tenant failures
                failed += 1
                logger.exception(
                    f"monthly_report draft FAILED for users_id={users_id}: {exc}"
                )
        logger.info(
            f"monthly_report cron complete: {ok} ok, {failed} failed, "
            f"{len(user_ids)} total, target_month={target_month}."
        )
        return {
            "total": len(user_ids),
            "ok": ok,
            "failed": failed,
            "target_month": target_month,
        }
