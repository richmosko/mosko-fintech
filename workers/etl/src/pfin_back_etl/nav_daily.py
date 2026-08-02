"""
Project:       pfin-back-etl
Author:        Rich Mosko (mosko-fintech Backend)

Description:
    SELF-214 daily-NAV checkpoint worker — the FIRST live per-user worker write
    path in pfin_back_etl. Computes each active-account tenant's net-asset-value
    for the current day and appends a frozen checkpoint row to pfin.nav_daily.

    W-1 impersonation model (F/CTO-ratified; Sec-joint-reviewed)
    -----------------------------------------------------------
    The worker connects as service_role (BYPASSRLS) with no user session. The
    valuation truth is the LOCKED SECURITY INVOKER function pfin.fn_compute_nav
    (migration 050) — reused verbatim (no Python NAV reimplementation, no new
    SECURITY DEFINER; the DEFINER allowlist stays 4). But an INVOKER read as
    service_role would see auth.uid() NULL → 0. So, per tenant, inside ONE
    for_tenant()-bound transaction:

        1. IMPERSONATE (TenantBoundConnection.impersonate): SET LOCAL ROLE
           authenticated + set request.jwt.claims = {sub: <users_id>, role:
           authenticated, aal: aal2}, so auth.uid() resolves to that tenant and RLS
           scopes the read. The aal2 claim is REQUIRED (054 WORKER NOTE / 025 aal2
           backstop): a totp/passkey user's account/holdings reads are aal2-gated,
           so without it fn_compute_nav would read zero and freeze a wrong 0 NAV.
        2. READ: select pfin.fn_compute_nav(current_date, true)  -- active-only,
           current-state headline NAV (sound only at current_date per 050's
           TEMPORAL CONSTRAINT — hence FORWARD-ONLY: today's checkpoint only;
           historical backfill is SELF-217, not this worker).
        3. RESET ROLE back to service_role (impersonate() teardown), then the
           PRIVILEGED append-only checkpoint INSERT — authenticated holds no write
           grant on nav_daily; service_role does.

    Idempotency vs append-only (migration 054, Architect-owned)
    -----------------------------------------------------------
    nav_daily is append-only + service_role-INSERT-only, one row per (users_id,
    nav_date). The checkpoint write is INSERT ... ON CONFLICT (users_id, nav_date)
    DO NOTHING — insert-if-absent: a same-day re-run is a clean no-op (no UPDATE →
    respects the append-only trigger; no error). First-write-wins freezes the
    day's checkpoint.

    Scheduling: wired as a runnable worker entry point (run_nav_daily.py); the
    Phase-7 Coolify cron scheduling is DEFERRED (F/CTO-ratified).

    Lock anchors: Lock 11 (INVOKER read-composition) · Lock 13 mod #3 (TBC) ·
    migration 050 (fn_compute_nav) · migration 054 (pfin.nav_daily — consumed).
"""

import logging

import sqlalchemy as sqla

from pfin_back_etl import utils
from pfin_back_etl.connection import TenantBoundConnection

logger = logging.getLogger("pfin_etl")


class NavDailyWorker:
    """Daily per-user NAV checkpoint worker (SELF-214 W-1).

    Construct once, then call run() (all active-account tenants) or
    compute_and_checkpoint_user(users_id) (a single tenant).
    """

    def __init__(self, env_prefix="PFIN_"):
        self._params = utils.load_env_variables(env_prefix)
        self._db_url = utils.build_database_url(self._params)
        # System-mode engine for tenant ENUMERATION only (service_role, BYPASSRLS;
        # no per-tenant assertion registered). Per-tenant WRITES go through a fresh
        # for_tenant() TBC each — never this engine.
        self._system_tbc = TenantBoundConnection.system(self._db_url)

    # ------------------------------------------------------------------ #
    # Tenant enumeration (service_role; legitimate cross-tenant read).
    # ------------------------------------------------------------------ #
    def active_account_user_ids(self):
        """Distinct users_id having at least one ACTIVE account — the tenants to
        checkpoint. Runs as service_role (system TBC, BYPASSRLS): a deliberate
        cross-tenant enumeration of WHOM to value, NOT a per-tenant data read. The
        active-account filter mirrors fn_compute_nav(_, true)'s active-only scope
        (a user with only inactive accounts has a 0 active NAV — nothing to freeze).
        """
        stmt = sqla.text(
            "select distinct users_id from pfin.account where is_active = true"
        )
        with self._system_tbc.engine.connect() as conn:
            rows = conn.execute(stmt).fetchall()
        return [row[0] for row in rows]

    # ------------------------------------------------------------------ #
    # Per-tenant impersonated compute + append-only checkpoint (one txn).
    # ------------------------------------------------------------------ #
    def compute_and_checkpoint_user(self, users_id):
        """Impersonate `users_id`, compute today's NAV via the locked INVOKER
        fn_compute_nav(current_date, true) under RLS, then append the frozen
        checkpoint to pfin.nav_daily as service_role — one atomic transaction.

        Idempotent + forward-only: ON CONFLICT (users_id, nav_date) DO NOTHING, so
        a same-day re-run is a no-op (rowcount 0). Returns (nav_value, inserted).
        """
        tbc = TenantBoundConnection.for_tenant(self._db_url, users_id)
        with tbc.engine.connect() as conn:
            with conn.begin():
                # (1) impersonated read under RLS (authenticated + jwt sub=users_id)
                with tbc.impersonate(conn):
                    nav_value = conn.execute(
                        sqla.text("select pfin.fn_compute_nav(current_date, true)")
                    ).scalar()

                # (2) privileged append-only checkpoint, back as service_role.
                # VALUES carries users_id literally → satisfies the TBC assertion's
                # direct-write (literal) binding. DO NOTHING = insert-if-absent.
                result = conn.execute(
                    sqla.text(
                        "insert into pfin.nav_daily "
                        "(users_id, nav_date, nav_value) "
                        "values (:uid, current_date, :nav) "
                        "on conflict (users_id, nav_date) do nothing"
                    ),
                    {"uid": str(users_id), "nav": nav_value},
                )
                inserted = result.rowcount

        logger.info(
            f"nav_daily checkpoint users_id={users_id} nav_value={nav_value} "
            f"inserted={inserted} (0 = already checkpointed today)"
        )
        return nav_value, inserted

    # ------------------------------------------------------------------ #
    # Nightly entry — checkpoint every active-account tenant for today.
    # ------------------------------------------------------------------ #
    def run(self):
        """Checkpoint today's NAV for every active-account tenant. Forward-only
        (today only; backfill is SELF-217). Per-tenant failures are isolated and
        logged so one bad tenant does not abort the whole run. Returns a summary
        dict {total, ok, failed}.
        """
        logger.info("==== " * 16)
        logger.info("==== Running daily NAV checkpoint (SELF-214 W-1; forward-only)")
        user_ids = self.active_account_user_ids()
        logger.info(f"Active-account tenants to checkpoint: {len(user_ids)}")

        ok = 0
        failed = 0
        for users_id in user_ids:
            try:
                self.compute_and_checkpoint_user(users_id)
                ok += 1
            except Exception as exc:  # isolate per-tenant failures
                failed += 1
                logger.exception(
                    f"nav_daily checkpoint FAILED for users_id={users_id}: {exc}"
                )
        logger.info(
            f"Daily NAV checkpoint complete: {ok} ok, {failed} failed, "
            f"{len(user_ids)} total."
        )
        return {"total": len(user_ids), "ok": ok, "failed": failed}
