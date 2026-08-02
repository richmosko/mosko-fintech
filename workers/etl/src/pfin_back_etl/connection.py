"""
Project:       pfin-back-etl
Author:        Rich Mosko (mosko-fintech Backend)

Description:
    TenantBoundConnection — the single sanctioned SQLAlchemy engine factory
    for pfin_back_etl.

    Lock anchors:
        - DECISIONS.md ADR-011 Decision 17 / Lock 13 mod #3 (V1-SHIP-BLOCK):
          TenantBoundConnection is the ONLY allowed Postgres-client entry point
          in pfin_back_etl. Raw psycopg2/psycopg/asyncpg .connect() OR a bare
          sqla.create_engine() outside this class is a CI fence violation
          (scripts/ci/fence-tbc-pfin-back-etl.sh — DevOps-owned).
        - DECISIONS.md ADR-011 Decision 4 Privileged-context-surfaces bullet:
          TBC is a CODE-LAYER mechanism, parallel to RT-26. It is NOT a
          catalogued §10 numbered-list instance (that ledger stays at 2 =
          RT-22 + RT-26). The V1-SHIP-BLOCK axis is orthogonal to the
          §10-catalogued axis.
        - workers/CLAUDE.md — TBC discipline / same-transaction audit-log.

    V1.0 SCOPE (SELF-193 — honest scaffold, ratified DP1a/DP2a/DP3a/DP4a):
        The ETL currently writes ONLY global market-reference tables
        (pfin.cpi / asset / equity_profile / reporting_period /
        income_statement / balance_sheet_statement / cash_flow_statement /
        earning / eod_price). NONE of these has a `users_id` column — they are
        shared reference data, not per-tenant rows. There is no per-user pfin
        write path in the ETL yet (NAV / tax / monthly_report / per-user Plaid
        crons land in later Waves).

        Therefore TBC's V1.0 value is ARCHITECTURAL: it is the single sanctioned
        engine factory. Every DB engine in pfin_back_etl is created here, so the
        fence has a class to anchor on and every FUTURE per-user write is forced
        through this construction path.

        - `.system()`     — V1.0 usage. Service-context / global-reference
                            writes with no tenant. The per-query users_id
                            assertion is NOT registered in this mode.
        - `.for_tenant()` — The per-user write path. Registers a
                            `before_cursor_execute` assertion that binds
                            `users_id` and requires every DML/function statement
                            to EITHER literally carry that `users_id` OR run
                            under an active impersonation binding for it.
                            FIRST LIVE CALLER: the SELF-214 daily-NAV worker
                            (nav_daily.py) — W-1 impersonation model (see
                            `impersonate()`).

        Full per-tenant enforcement + mod #4 same-transaction audit-log wiring
        are V1.1+ (see `emit_audit_log` — DEPENDENCY-BLOCKED stub).
"""

import json
import logging
from contextlib import contextmanager

import sqlalchemy as sqla
from sqlalchemy import event

logger = logging.getLogger("pfin_etl")

# Connection-scoped (conn.info) key recording that impersonation is ACTIVE for a
# given users_id — set by the JWT-claims binding op, cleared on teardown. See
# TenantBoundConnection.impersonate() + _register_tenant_assertion (SELF-214 W-1).
_IMPERSONATION_KEY = "tbc_impersonated_users_id"

# GUC carrying the Supabase JWT claims; auth.uid() reads its 'sub'. Setting it
# (with sub = the bound users_id) is what establishes an impersonation binding.
_JWT_CLAIMS_GUC = "request.jwt.claims"


class TenantBindingError(RuntimeError):
    """Raised when a per-tenant-bound connection executes a statement that does
    not carry its bound users_id. Dormant in V1.0 (no `.for_tenant()` caller
    yet); the enforcement contract firms up with the first per-user write path
    (V1.1+)."""


class TenantBoundConnection:
    """Single sanctioned SQLAlchemy engine factory for pfin_back_etl
    (Lock 13 mod #3).

    Construct via the classmethods, never the initializer directly:

        # V1.0 — global market-reference writes (no tenant):
        tbc = TenantBoundConnection.system(DATABASE_URL)
        engine = tbc.engine

        # V1.1+ — per-user write path (scaffolded, no live caller yet):
        tbc = TenantBoundConnection.for_tenant(DATABASE_URL, users_id)
        engine = tbc.engine

    NullPool is preserved to match the pre-TBC engine posture (short-lived
    Coolify cron process; no connection pooling across runs).
    """

    # Sentinel distinguishing service-context (global-reference) construction
    # from a real per-tenant binding. Identity-compared, never a real users_id.
    _SYSTEM = object()

    def __init__(self, database_url, users_id):
        """Prefer the `.system()` / `.for_tenant()` classmethods. Direct
        construction is allowed but the classmethods document intent."""
        self._users_id = users_id
        self._engine = sqla.create_engine(
            database_url, poolclass=sqla.pool.NullPool
        )
        if users_id is self._SYSTEM:
            logger.info(
                "TenantBoundConnection: engine created in SYSTEM mode "
                "(global market-reference writes; no per-tenant assertion)."
            )
        else:
            logger.info(
                "TenantBoundConnection: engine created in PER-TENANT mode "
                "(users_id bound; dormant assertion registered — V1.1+)."
            )
            self._register_tenant_assertion()

    @classmethod
    def system(cls, database_url):
        """V1.0 usage. Service-context engine for global market-reference
        writes that legitimately have no `users_id` column."""
        return cls(database_url, cls._SYSTEM)

    @classmethod
    def for_tenant(cls, database_url, users_id):
        """The per-user write path. Binds `users_id` and registers the per-query
        assertion (impersonation-aware — see _register_tenant_assertion). First
        live caller: the SELF-214 daily-NAV worker via impersonate()."""
        if users_id is None or users_id is cls._SYSTEM:
            raise ValueError(
                "for_tenant() requires a real users_id; use system() for "
                "service-context global-reference writes."
            )
        return cls(database_url, users_id)

    @property
    def engine(self):
        """The SQLAlchemy Engine. All existing call sites keep using
        `sqla.orm.Session(engine)` / `metadata.reflect(bind=engine)` /
        `base.prepare(autoload_with=engine)` unchanged."""
        return self._engine

    @property
    def is_system(self):
        """True when constructed in service-context (global-reference) mode."""
        return self._users_id is self._SYSTEM

    # ------------------------------------------------------------------ #
    # Per-tenant impersonation (SELF-214 W-1). First live for_tenant() use.
    # ------------------------------------------------------------------ #
    @contextmanager
    def impersonate(self, conn):
        """Impersonate the bound tenant on `conn` for the duration of the block so
        SECURITY INVOKER reads (e.g. pfin.fn_compute_nav) resolve `auth.uid()` to
        the bound users_id under RLS.

        SELF-214 W-1 (first live per-user worker write path; Sec-joint-reviewed):
        the worker connects as service_role (BYPASSRLS) with no user session, so an
        INVOKER read would see `auth.uid()` NULL and return 0. Within a
        for_tenant()-bound transaction this sets, transaction-locally:
            SET LOCAL ROLE authenticated;
            select set_config('request.jwt.claims', '{"sub": <users_id>, ...}', true);
        making `auth.uid()` = the bound users_id for the block. On exit it tears the
        binding down (claims cleared, RESET ROLE) so a following PRIVILEGED write
        (e.g. the service_role-only INSERT into pfin.nav_daily) runs back as the
        connection's original service_role — authenticated has no write grant there.

        Contract:
          - MUST be a for_tenant()-bound TBC (raises in system mode).
          - MUST run inside an open transaction — SET LOCAL / set_config(..., true)
            are transaction-scoped; they auto-clear at COMMIT/ROLLBACK even if the
            explicit teardown is skipped.
          - Isolation for reads in the block is enforced by RLS via the JWT claim;
            the firmed per-tenant assertion verifies the impersonation binding
            matches the bound users_id before permitting non-users_id-carrying reads.
        """
        if self.is_system:
            raise TenantBindingError(
                "impersonate() requires a for_tenant()-bound connection; a "
                "system-mode TBC has no tenant to impersonate."
            )
        # aal2 IS REQUIRED (migration 054 WORKER NOTE + 025 aal2 step-up backstop;
        # Sec-joint-review surface): the 025 backstop AND-s an aal2 conjunct into the
        # RLS of sensitive tenant tables (nav_daily + the account/holdings/txns that
        # fn_compute_nav reads). A user who DECLARED mfa_policy totp/passkey is gated
        # to an aal2 session; without an 'aal':'aal2' claim their underlying reads
        # filter to ZERO and the frozen NAV would be a wrong 0. The trusted worker's
        # synthetic session presents aal2 (ratified W-1 expectation). Users with
        # mfa_policy 'none'/missing are unaffected by the conjunct either way.
        claims = json.dumps(
            {"sub": str(self._users_id), "role": "authenticated", "aal": "aal2"}
        )
        conn.execute(sqla.text("set local role authenticated"))
        conn.execute(
            sqla.text(f"select set_config('{_JWT_CLAIMS_GUC}', :claims, true)"),
            {"claims": claims},
        )
        try:
            yield conn
        finally:
            conn.execute(
                sqla.text(f"select set_config('{_JWT_CLAIMS_GUC}', NULL, true)")
            )
            conn.execute(sqla.text("reset role"))

    # ------------------------------------------------------------------ #
    # Per-tenant assertion. Registered only in for_tenant() mode.
    # ------------------------------------------------------------------ #
    def _register_tenant_assertion(self):
        """Register a `before_cursor_execute` hook that asserts every DML/function
        statement on this per-tenant-bound connection is scoped to the bound
        users_id — by ONE of two sanctioned bindings:

          (a) LITERAL: the statement carries the bound users_id in its parameters
              or SQL text (the direct-write contract — e.g. the nav_daily INSERT
              whose VALUES carry the users_id).
          (b) IMPERSONATION: `set_config('request.jwt.claims', …sub=users_id…)` +
              `SET ROLE authenticated` are active on this connection (established by
              impersonate()), so RLS (`auth.uid()`) enforces isolation for a read
              that does not itself name the users_id (e.g. fn_compute_nav).

        Transaction-control / session-setup / introspection statements are exempt;
        the JWT-claims binding op is recognized and toggles impersonation state on
        conn.info; RESET ROLE / DISCARD tear it down. A statement that satisfies
        neither binding fails closed (TenantBindingError) — this is the fence that
        keeps a for_tenant(A) connection from silently acting on tenant B."""
        users_id = self._users_id

        @event.listens_for(self._engine, "before_cursor_execute")
        def _assert_tenant_bound(
            conn, cursor, statement, parameters, context, executemany
        ):  # noqa: ANN001
            # Pure decision core (module-level, unit-testable): conn.info carries
            # the per-connection impersonation state across statements.
            _check_tenant_statement(conn.info, statement, parameters, users_id)

    # ------------------------------------------------------------------ #
    # mod #4 — same-transaction audit-log (DEPENDENCY-BLOCKED stub).
    # ------------------------------------------------------------------ #
    def emit_audit_log(self, session, event):  # noqa: A002 (shadow ok in stub)
        """Emit a mod #4 audit-log row on the SAME SQLAlchemy `session` /
        transaction as the state change it records (never a separate tx, never
        fire-and-forget).

        PROVISIONAL SIGNATURE — DEPENDENCY-BLOCKED. This is a stub. Wiring is
        blocked on the Architect authoring:
            (1) `pfin.plaid_sync_audit` — the mod #8 cross-language audit table
                with a `source` ENUM discriminator (schema-as-contract shared
                with the TypeScript api/ side); and
            (2) the `SECURITY DEFINER` audit-log insert helper — the still-
                unauthored entry in the Decision-9 DEFINER allowlist.

        Until both land (a later PR), and until a real state-changing per-user
        write exists to audit, this raises. The `(session, event)` signature is
        provisional and will be reconciled against `plaid_sync_audit` when it is
        authored."""
        raise NotImplementedError(
            "mod #4 same-transaction audit-log is not yet wired: blocked on "
            "pfin.plaid_sync_audit + the SECURITY DEFINER audit-log insert "
            "helper (Architect-owned migration, later PR). Signature is "
            "provisional."
        )


# ---------------------------------------------------------------------------
# Module-level helpers for the dormant per-tenant assertion.
# ---------------------------------------------------------------------------
# Statement prefixes that carry no tenant predicate and are exempt from the
# users_id assertion (transaction control, session setup, reflection/
# introspection). Compared case-insensitively against the stripped statement.
_TENANT_EXEMPT_PREFIXES = (
    "begin",
    "commit",
    "rollback",
    "savepoint",
    "release",
    "set ",
    "reset ",
    "discard ",
    "show ",
    "select pg_",  # introspection helpers
)


def _is_tenant_exempt(statement):
    """True for transaction-control / session-setup / introspection statements
    that carry no tenant predicate."""
    head = statement.lstrip().lower()
    return head.startswith(_TENANT_EXEMPT_PREFIXES)


def _claims_carry_users_id(statement, parameters, target):
    """True if the bound users_id (`target`, already stringified) appears anywhere
    in a JWT-claims binding op. The sub is embedded in a JSON claims blob
    ({"sub": "<uid>", …}) passed as a bound parameter or inline literal, so this is
    a CONTAINMENT check — deliberately distinct from _statement_carries_users_id's
    equality-on-params contract used for direct writes."""
    if target in statement:
        return True
    for value in _iter_param_values(parameters):
        if target in str(value):
            return True
    return False


def _check_tenant_statement(info, statement, parameters, users_id):
    """Pure decision core of the per-tenant assertion (SELF-214 W-1).

    `info` is the per-connection state dict (conn.info) tracking whether
    impersonation is active for a users_id. This function MUTATES `info` on binding
    ops and RAISES TenantBindingError on a statement that is scoped to neither the
    bound users_id (literal) nor an active impersonation binding for it. Returns
    None on allow. Factored out of the before_cursor_execute closure so the
    fail-closed logic is unit-testable without a live database.

    Two sanctioned per-tenant bindings for a DML/function statement:
      (a) LITERAL — the bound users_id appears in the statement params or SQL text
          (the direct-write contract, e.g. the nav_daily INSERT VALUES users_id).
      (b) IMPERSONATION — SET ROLE authenticated + request.jwt.claims.sub =
          users_id are active on this connection (established by impersonate()), so
          RLS/auth.uid() enforces isolation for a read that does not name users_id.
    """
    target = str(users_id)
    lowered = statement.lower()

    # (1) Impersonation binding op: sets the JWT-claims GUC (via SET LOCAL
    # "request.jwt.claims" = … or select set_config('request.jwt.claims', …)).
    # Carrying the bound users_id ESTABLISHES impersonation; otherwise it CLEARS it
    # (teardown). The binding op itself is always allowed. NOTE: the users_id here
    # is embedded in a JSON claims blob ({"sub": "<uid>", …}), so this is a
    # CONTAINMENT check — distinct from the equality-based literal-write contract.
    if _JWT_CLAIMS_GUC in lowered:
        if _claims_carry_users_id(statement, parameters, target):
            info[_IMPERSONATION_KEY] = target
        else:
            info.pop(_IMPERSONATION_KEY, None)
        return

    # (2) Transaction-control / session-setup / introspection — exempt. RESET ROLE
    # / DISCARD also tear down any active impersonation (defensive).
    if _is_tenant_exempt(statement):
        if lowered.lstrip().startswith(("reset", "discard")):
            info.pop(_IMPERSONATION_KEY, None)
        return

    # (3) DML / function statement — require binding (a) OR (b), else fail closed.
    if _statement_carries_users_id(statement, parameters, users_id):
        return
    if info.get(_IMPERSONATION_KEY) == target:
        return
    raise TenantBindingError(
        "per-tenant statement carries neither the bound users_id="
        f"{users_id!r} nor an active impersonation binding for it: "
        f"{statement.strip()[:200]}"
    )


def _statement_carries_users_id(statement, parameters, users_id):
    """True if the bound users_id appears in the statement parameters or the
    literal SQL text. Conservative dormant default (V1.1+ firms the contract)."""
    target = str(users_id)

    # Check bound parameters first (the normal, parameterized path).
    for value in _iter_param_values(parameters):
        if str(value) == target:
            return True

    # Fallback: literal appearance in the SQL text (e.g. inlined constants).
    return target in statement


def _iter_param_values(parameters):
    """Flatten SQLAlchemy DBAPI parameters (dict, sequence, or executemany
    sequence-of-those) into a flat value iterator."""
    if parameters is None:
        return
    if isinstance(parameters, dict):
        yield from parameters.values()
    elif isinstance(parameters, (list, tuple)):
        for item in parameters:
            if isinstance(item, dict):
                yield from item.values()
            elif isinstance(item, (list, tuple)):
                yield from item
            else:
                yield item
    else:
        yield parameters
