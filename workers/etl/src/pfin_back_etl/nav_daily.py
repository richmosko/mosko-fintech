"""
Project:       pfin-back-etl
Author:        Rich Mosko (mosko-fintech Backend)

Description:
    SELF-214 daily-NAV checkpoint worker — the FIRST live per-user worker write
    path in pfin_back_etl. Computes each account-owning tenant's net-asset-value
    for the current day and appends a frozen checkpoint row to pfin.nav_daily.

    DB identity model (SELF-214 Sec joint-review v3 B1 + B8 option (B), both
    F/CTO-ratified. The ADR-023 login-as-broker / write-as-service_role MODEL is
    inherited from provider-sync; the ROLE is this worker's own.)
    -----------------------------------------------------------
    The worker LOGS IN as `pfin_etl` — the ETL's DEDICATED NOINHERIT login role
    (SELF-214 B8 option (B), F/CTO-ratified 2026-08-02; an Architect migration
    creates it with membership in `service_role` + `authenticated`). Distinct from
    provider-sync's `authenticator`, so ADR-023 condition C1's rotation coupling
    does not reach this worker.
    `service_role` is `rolcanlogin = f` (MEASURED) and can NEVER be a direct-
    Postgres login identity; any claim that a worker "connects as service_role"
    names a transport-impossible role. Roles are assumed explicitly, per
    transaction:
        READ  → `set local role authenticated` + synthetic JWT claims (impersonate)
        WRITE → `set local role service_role`  (ADR-023 write role-of-record)
    Because `pfin_etl` is NOINHERIT, an unqualified statement holds NO
    privileges and fails 42501 — every path below assumes its role deliberately.
    That is also what makes 054's `grant insert on pfin.nav_daily to service_role`
    LOAD-BEARING rather than decorative, and what makes 054's append-only triggers
    UN-BYPASSABLE by the writer (`service_role` is neither table owner nor
    superuser, so it can neither `ALTER TABLE … DISABLE TRIGGER` nor set
    `session_replication_role`).

    W-1 impersonation model (F/CTO-ratified; Sec-joint-reviewed)
    -----------------------------------------------------------
    The valuation truth is the LOCKED SECURITY INVOKER function pfin.fn_compute_nav
    (migration 050) — reused verbatim (no Python NAV reimplementation, no new
    SECURITY DEFINER; the DEFINER allowlist stays 4). But an INVOKER read with no
    user session would see auth.uid() NULL → 0. So, per tenant, inside ONE
    for_tenant()-bound transaction:

        1. IMPERSONATE (TenantBoundConnection.impersonate): clear the legacy
           singular request.jwt.claim.sub GUC (N7), SET LOCAL ROLE authenticated,
           set request.jwt.claims = {sub: <users_id>, role: authenticated, aal:
           aal2}, so auth.uid() resolves to that tenant and RLS scopes the read.
           The aal2 claim is REQUIRED (054 WORKER NOTE / 025 aal2 backstop): a
           totp-declared user's account/holdings reads are aal2-gated, so without it
           fn_compute_nav would read zero and freeze a wrong 0 NAV. The block is a
           FENCED READ-ONLY primitive (Sec B2) — no write may run inside it.
        2. BIND the write tenant (Sec B7): set app.nav_computed_for from
           auth.uid() — the tenant as THE DATABASE resolved it, not the Python
           variable. Architect's 054 BEFORE INSERT trigger rejects any row whose
           users_id disagrees, and fails closed when the GUC is unset.
        3. READ: select pfin.fn_compute_nav(current_date, true)  -- the headline
           NAV, scoped to accounts OPEN AS OF the valuation date.
           ⚠ 050's "sound only at current_date" TEMPORAL CONSTRAINT IS STRUCK at
           059 (ADR-042), NOT relaxed: it rested entirely on is_active being a
           current-state boolean, and closed_at IS temporal, so fn_compute_nav is
           now sound at ANY p_as_of. THIS WORKER REMAINS FORWARD-ONLY ANYWAY —
           but the reason is now the only reason it ever really had: historical
           backfill is SELF-217's scope, and freezing a checkpoint for a past date
           is a decision about nav_daily's append-only semantics, not about
           whether the valuation is trustworthy. Do NOT cite the struck constraint
           as the justification; if backfill is wanted, the blocker is SELF-217.
        4. Teardown (impersonate() exit: claims cleared, RESET ROLE) → back to the
           privilege-less `pfin_etl`. Then `set local role service_role` and
           the PRIVILEGED append-only checkpoint INSERT. `authenticated` holds no
           write grant on nav_daily; `service_role` holds INSERT only.

    Idempotency vs append-only (migration 054, Architect-owned)
    -----------------------------------------------------------
    nav_daily is append-only, one row per (users_id, nav_date). `service_role`
    holds INSERT plus a column-level SELECT on the two arbiter columns ONLY — it
    can never read a nav_value. The checkpoint write is
    INSERT ... ON CONFLICT (users_id, nav_date) DO NOTHING — insert-if-absent: a
    same-day re-run is a clean no-op (no UPDATE → respects the append-only trigger;
    no error). First-write-wins freezes the day's checkpoint. The targeted conflict
    form is self-fencing — the QA battery executes this exact statement, so grant /
    constraint / statement drift fails in CI rather than on the nightly cron. See
    _CHECKPOINT_INSERT + _ARBITER_COLUMNS for the three-artifact invariant.

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

# ADR-023 write role-of-record. The login role (`pfin_etl`) is NOINHERIT and
# holds NO privileges, so every privileged statement assumes this role explicitly,
# transaction-locally. `set local` is exempt-prefixed for the TBC assertion and
# auto-reverts at COMMIT/ROLLBACK.
_SET_WRITE_ROLE = "set local role service_role"

# SELF-214 Sec joint-review B7 — the write-tenant binding GUC. PINNED CONTRACT:
# Architect's 054 BEFORE INSERT trigger reads this exact name and rejects any row
# whose users_id disagrees, failing closed when it is unset. Do not rename without
# a coordinated migration change.
#
# The value MUST come from auth.uid() — the tenant AS THE DATABASE RESOLVED IT —
# and NOT from the Python users_id variable. That is the entire security property:
# it proves the row's tenant IS the tenant actually served, and it closes the
# legacy-singular-GUC path in which request.jwt.claim.sub could resolve every
# tenant to one user while the Python variable looked correct throughout. Deriving
# it from self._users_id would make both sides of the check the same variable and
# defeat the fence — Sec rejected that variant explicitly.
#
# Transaction-local (`true`), so it survives impersonate()'s `reset role` (which
# clears only request.jwt.claims + the role) and auto-clears at COMMIT/ROLLBACK.
_NAV_TENANT_GUC = "app.nav_computed_for"
_BIND_WRITE_TENANT = (
    f"select set_config('{_NAV_TENANT_GUC}', auth.uid()::text, true)"
)

# ARBITER CONTRACT — the columns of the unique constraint the checkpoint INSERT
# conflicts on, and therefore EXACTLY the columns the column-level grant must make
# readable to `service_role`:
#
#     unique (users_id, nav_date) on pfin.nav_daily            -- 054, Architect
#     grant select (users_id, nav_date) on pfin.nav_daily
#           to service_role;                                   -- 054, Architect
#
# THREE artifacts must agree: the constraint, the grant, and the ON CONFLICT target
# in _CHECKPOINT_INSERT below. This constant is the app-side pin of that agreement —
# test_checkpoint_insert_pins_arbiter_columns parses the arbiter list back out of
# the production statement and asserts it matches. If Architect changes the
# constraint's shape, updating this tuple is what makes the Python side fail loudly
# at test time rather than the cron failing at runtime.
_ARBITER_COLUMNS = ("users_id", "nav_date")

# The append-only checkpoint write. THE PRODUCTION STATEMENT SHAPE, verbatim —
# tests import this constant rather than retyping a simplified equivalent, per the
# battery-wide rule (RT-31 leg (h)) generalized from this exact defect: a leg that
# asserts a permission using a simplified statement can pass on privileges the real
# statement never needed.
#
# TARGETED `on conflict (users_id, nav_date) do nothing` — Sec-ruled, NOT a style
# choice, and NOT the same as the earlier untargeted form (that ruling was
# superseded). Naming the arbiter columns requires them to be READABLE, which is
# admitted by a column-level grant on exactly those two columns. That grant is the
# MINIMUM admitting this form — a targeted ON CONFLICT needs every arbiter column
# readable, so no narrower grant exists. `nav_value` and `select *` stay DENIED
# 42501, so the worker still cannot read a single financial value.
#
# PRECISE CLAIM, because the older blanket phrasing no longer holds: the cron
# appends and NEVER READS A VALUE. It CAN read the (users_id, nav_date) pair — i.e.
# per-tenant checkpoint dating. SD-24 carries that residual explicitly; it is
# narrower than it first appears because holdings_checkpoint and
# account_balance_checkpoint already disclose per-tenant dated cadence to
# service_role, leaving NAV-cron success/failure dating as the true increment.
#
# WHY TARGETED IS SAFER, and this is the load-bearing reason: **the fence IS the
# production statement.** The QA battery executes this statement verbatim, so you
# cannot have a passing battery and a broken statement. Every drift direction is
# caught PRE-MERGE in CI: constraint gains a column -> 42P10; an arbiter column is
# renamed -> fails; the grant loses a column -> 42501; a SECOND unique constraint is
# added -> this statement stays valid and the new constraint raises LOUDLY at
# runtime, which is the desired behaviour rather than a silent swallow. The
# untargeted form had none of this intrinsically — it needed a separate assertion
# bolted on that someone had to remember to write and keep aligned. Targeted is
# self-fencing; untargeted was fenced.
#
# ⚠ INVARIANT: the grant's column list MUST match the arbiter constraint. Fenced
# app-side by _ARBITER_COLUMNS above, DB-side by QA's production-shape legs. Do not
# "simplify" either fence away.
#
# DO NOTHING, never DO UPDATE: an UPDATE path would trip 054's append-only trigger.
# The 054 BEFORE INSERT write-tenant trigger still fires on a same-day re-run
# (BEFORE INSERT precedes conflict detection, so B7 is NOT bypassed), and
# `result.rowcount` remains a valid inserted/skipped signal.
_CHECKPOINT_INSERT = (
    "insert into pfin.nav_daily "
    "(users_id, nav_date, nav_value) "
    "values (:uid, current_date, :nav) "
    "on conflict (users_id, nav_date) do nothing"
)


class NavDailyWorker:
    """Daily per-user NAV checkpoint worker (SELF-214 W-1).

    Construct once, then call run() (all account-owning tenants) or
    compute_and_checkpoint_user(users_id) (a single tenant).
    """

    def __init__(self, env_prefix="PFIN_"):
        self._params = utils.load_env_variables(env_prefix)
        self._db_url = utils.build_database_url(self._params)
        # System-mode engine for tenant ENUMERATION only (no per-tenant assertion
        # registered; the enumeration query assumes `service_role` itself — see
        # account_user_ids). Per-tenant reads/writes go through a fresh
        # for_tenant() TBC each — never this engine.
        self._system_tbc = TenantBoundConnection.system(self._db_url)

    # ------------------------------------------------------------------ #
    # Tenant enumeration (service_role; legitimate cross-tenant read).
    # ------------------------------------------------------------------ #
    def account_user_ids(self):
        """Distinct users_id owning AT LEAST ONE ACCOUNT — the tenants to checkpoint.
        A deliberate cross-tenant enumeration of WHOM to value, NOT a per-tenant data
        read (it returns users_id values only, no financial data), so it runs on the
        system-mode TBC where no per-tenant assertion registers — exemption by
        construction, not a bypass.

        ⚠ THE FILTER IS GONE, AND IT WAS DELIBERATELY *NOT* RE-POINTED TO A CLOSURE
        PREDICATE (ADR-042 / migration 059; BACKLOG §7.7 + §7.9). Two reasons, and the
        second is the one a faithful-looking translation would have missed:

        (1) `where is_active = true` no longer resolves — the column drops at 059. This
            method is why that break is FORCED work inside this slice rather than a
            latent one: it raises at runtime, in the nightly cron, at tenant
            enumeration, before any tenant is valued.

        (2) Re-pointing it to `closed_at is null` would have PRESERVED A LIVE DEFECT
            while looking like a careful translation. The old filter meant a tenant
            whose accounts were ALL inactive was skipped, so that tenant got NO
            nav_daily ROW — a GAP. A gap conflates four distinct states (not a user /
            owns no accounts / owns only closed accounts / the job never ran), while a
            `0` row asserts one fact and is distinguishable from every one of them.
            Absence is not a value. Enumerating every tenant that owns any account
            yields a real 0 for the all-closed case, which is both true and legible.

        The as-of scoping still happens, and still happens in exactly ONE place:
        fn_compute_nav(current_date, true) applies `closed_at is null or closed_at >
        p_as_of` per tenant, under that tenant's RLS. Filtering here as well would
        restate that predicate in a second language, where the two would drift apart
        silently — and the DB's copy is the one with the battery behind it.

        Runs AS `service_role`, assumed explicitly: the login role `pfin_etl`
        is NOINHERIT and holds no privileges, so a bare SELECT here would fail
        42501. `service_role` bypasses RLS (so the enumeration sees all tenants) and
        holds `grant select on pfin.account` from migration 008.
        """
        stmt = sqla.text("select distinct users_id from pfin.account")
        with self._system_tbc.engine.connect() as conn:
            with conn.begin():  # `set local` needs an explicit transaction scope
                conn.execute(sqla.text(_SET_WRITE_ROLE))
                rows = conn.execute(stmt).fetchall()
        return [row[0] for row in rows]

    # ------------------------------------------------------------------ #
    # Per-tenant impersonated compute + append-only checkpoint (one txn).
    # ------------------------------------------------------------------ #
    def compute_and_checkpoint_user(self, users_id):
        """Impersonate `users_id`, compute today's NAV via the locked INVOKER
        fn_compute_nav(current_date, true) under RLS, then append the frozen
        checkpoint to pfin.nav_daily AS `service_role` — one atomic transaction.

        Idempotent + forward-only: ON CONFLICT (users_id, nav_date) DO NOTHING (see
        _CHECKPOINT_INSERT — the targeted form is admitted by a minimal column-level
        grant on exactly the two arbiter columns), so a same-day re-run is a no-op
        (rowcount 0). Returns (nav_value, inserted).
        """
        tbc = TenantBoundConnection.for_tenant(self._db_url, users_id)
        with tbc.engine.connect() as conn:
            with conn.begin():
                # (1) impersonated read under RLS (authenticated + jwt sub=users_id).
                # FENCED READ-ONLY (Sec B2) — nothing in this block may write.
                with tbc.impersonate(conn):
                    # (1a) B7 write-tenant binding, captured from auth.uid() as the
                    # DATABASE resolved it (never from self._users_id — see
                    # _NAV_TENANT_GUC). Must be set INSIDE the block, while the
                    # claims are live; it survives teardown and clears at COMMIT.
                    conn.execute(sqla.text(_BIND_WRITE_TENANT))

                    nav_value = conn.execute(
                        sqla.text("select pfin.fn_compute_nav(current_date, true)")
                    ).scalar()

                # (2) privileged append-only checkpoint. impersonate()'s teardown
                # left the session back on the NOINHERIT login role, which holds no
                # privileges — assume the ADR-023 write role explicitly or the
                # INSERT fails 42501 (Sec joint-review v3 B1(c)).
                conn.execute(sqla.text(_SET_WRITE_ROLE))

                # VALUES carries users_id literally → satisfies the TBC assertion's
                # direct-write (literal) binding, and 054's BEFORE INSERT trigger
                # independently checks it against app.nav_computed_for at the DB
                # layer. DO NOTHING = insert-if-absent.
                result = conn.execute(
                    sqla.text(_CHECKPOINT_INSERT),
                    {"uid": str(users_id), "nav": nav_value},
                )
                inserted = result.rowcount

        logger.info(
            f"nav_daily checkpoint users_id={users_id} nav_value={nav_value} "
            f"inserted={inserted} (0 = already checkpointed today)"
        )
        return nav_value, inserted

    # ------------------------------------------------------------------ #
    # Nightly entry — checkpoint every account-owning tenant for today.
    # ------------------------------------------------------------------ #
    def run(self):
        """Checkpoint today's NAV for every account-owning tenant. Forward-only
        (today only; backfill is SELF-217). Per-tenant failures are isolated and
        logged so one bad tenant does not abort the whole run. Returns a summary
        dict {total, ok, failed}.
        """
        logger.info("==== " * 16)
        logger.info("==== Running daily NAV checkpoint (SELF-214 W-1; forward-only)")
        user_ids = self.account_user_ids()
        logger.info(f"Tenants to checkpoint: {len(user_ids)}")

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
