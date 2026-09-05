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
    re-specify it" for this exact tenant-binding need. Architect's 113 fix
    (migration `c24a000`) now records this call site's own status directly
    in 113's comment: "PROVISIONAL RULING, SEC RATIFIES AT SELF-351:
    because there is no tenant parameter and EXECUTE is authenticated-only,
    the cron's only route in is a select of this function inside
    TenantBoundConnection.impersonate() — a write through a primitive
    documented never to wrap one, arriving through that fence's own named
    residual. Ruled provisionally to BE the R3 (i) shape... the never-wrap-
    a-write rule was written for direct DML by an RLS-exempt role." A
    `p_users_id` parameter for a `service_role` call was considered and
    explicitly NOT taken, because it would reopen Gate A (no tenant
    parameter, ever). This module implements exactly that provisional
    shape and changes nothing here pending Sec's ratification —
    connection.py's own docstring is left untouched until Sec rules (not
    this file's decision to make), and this residual comment stays in
    place as the pointer for the next reader until it does.

    ⚠⚠ FLAG 2 — RESOLVED at 113's fix (migration `c24a000`, A7 AC 6):
    `trigger_source` IS NOW DERIVED FROM A TRANSACTION-LOCAL GUC, NOT
    HARDCODED.

    113 now reads `current_setting('app.report_generation_source', true)`
    — EXACT match `'cron'`, any other value (including unset/NULL/blank)
    falls to `'on_demand'` (113's own comment: "under-claiming provenance
    is the fail-closed direction — a cron that forgets the GUC under-
    counts a month it really did generate, whereas the opposite default
    would let UI clicking inflate the metric"). This worker sets that GUC
    — see `open_draft_for_tenant`'s own docstring for the exact mechanism
    and the transaction-locality requirement.

    ⚠ WHAT THIS DOES NOT CLOSE (113's own comment, carried forward here
    rather than restated independently): deriving from the GUC makes 113
    itself incapable of mislabelling a row it writes, but it does NOT make
    `'cron'` unforgeable on `pfin.audit_log` — `pfin.fn_emit_audit_log`
    (111) is SECURITY DEFINER, EXECUTE-granted to `authenticated` in a
    Data-API-exposed schema, and takes `p_trigger_source` FROM ITS CALLER;
    113's own comment records a live measurement (2026-09-05) that an
    ordinary authenticated session minted a `'cron'` row by calling that
    helper directly. That residual belongs to 111, is routed to Sec's
    joint review there, and nothing in this module reaches or could close
    it — flagged for visibility, not because this file has any lever on
    it.

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

# 113's fix (A7 AC 6) — the transaction-local GUC 113 reads to derive the
# audit row's trigger_source. EXACT match 'cron', else 'on_demand' — see
# open_draft_for_tenant's own docstring for the transaction-locality
# requirement (`true` as set_config's third argument; a session-level set
# would leak into a LATER transaction on the same connection, per 113's own
# measured comment). PINNED CONTRACT, same convention as nav_daily.py's
# `_NAV_TENANT_GUC` — do not rename without a coordinated migration change.
_PROVENANCE_GUC = "app.report_generation_source"

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

        PROVENANCE GUC (113's fix, A7 AC 6): 113 derives the audit row's
        `trigger_source` from the transaction-local GUC
        `app.report_generation_source` — EXACT match `'cron'`, else
        `'on_demand'` (113's own comment: "under-claiming provenance is the
        fail-closed direction"). Set here via `set_config(...,
        true)` — `true` is the THIRD argument, meaning transaction-local,
        the SAME requirement 054's `app.nav_computed_for` GUC carries (a
        session-level set would leak into a LATER transaction's row on the
        same pooled connection — 113's own comment measures this directly:
        "a session-level set DOES reach a later transaction's row"). Set
        INSIDE the impersonated block, immediately before the call it
        labels — 113's own comment frames the production shape as "before
        its SET LOCAL ROLE," which `impersonate()`'s internal `SET LOCAL
        ROLE authenticated` already is; ORDER relative to that specific
        statement does not change correctness (a transaction-local GUC
        survives a role switch either way — 113's own comment says so
        explicitly), but setting it here keeps it visibly adjacent to the
        ONE call it exists to label, rather than separated from it by
        `impersonate()`'s own internals.

        `impersonate()`'s own teardown (connection.py's `finally` block)
        unconditionally clears the JWT-claims GUC and issues `reset role` on
        exit — success or exception — which is this call's ONLY reset-role
        discipline: a fresh `for_tenant()` TBC (hence a fresh engine, hence
        under `NullPool` a fresh physical connection) is opened per tenant,
        so there is nothing for one tenant's session state to leak INTO for
        the next — see test_monthly_report_cron.py's leaked-SET legs for the
        concrete, DB-verified proof of both halves (teardown fires; a
        subsequent tenant is unaffected even if it didn't). The
        `app.report_generation_source` GUC set below is likewise
        transaction-local (`true`) and therefore falls under the SAME
        auto-clear-at-COMMIT/ROLLBACK guarantee — nothing further is needed
        to keep it from leaking into a later tenant's transaction on a
        fresh connection.
        """
        tbc = TenantBoundConnection.for_tenant(self._db_url, users_id)
        with tbc.engine.connect() as conn:
            with conn.begin():
                with tbc.impersonate(conn):
                    conn.execute(
                        sqla.text(
                            f"select set_config('{_PROVENANCE_GUC}', 'cron', true)"
                        )
                    )
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
