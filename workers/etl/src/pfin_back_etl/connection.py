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
        - `.for_tenant()` — Scaffolded for the first per-user write path
                            (V1.1+). Registers a dormant `before_cursor_execute`
                            assertion that binds `users_id` and checks each
                            statement carries it. No live caller yet.

        Full per-tenant enforcement + mod #4 same-transaction audit-log wiring
        are V1.1+ (see `emit_audit_log` — DEPENDENCY-BLOCKED stub).
"""

import logging

import sqlalchemy as sqla
from sqlalchemy import event

logger = logging.getLogger("pfin_etl")


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
        """Scaffolded for the first per-user write path (V1.1+). Binds
        `users_id` and registers the dormant per-query assertion. No live
        caller in V1.0."""
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
    # Per-tenant assertion (dormant in V1.0 — registered only in
    # for_tenant() mode, which has no live caller yet).
    # ------------------------------------------------------------------ #
    def _register_tenant_assertion(self):
        """Register a `before_cursor_execute` hook that asserts the bound
        users_id is carried by each executed statement.

        PROVISIONAL: the exact predicate contract (which tables/columns count
        as per-tenant; how the users_id must appear) firms up with the first
        per-user write path in V1.1+. This dormant default is conservative —
        it skips transaction-control / session-setup / reflection-introspection
        statements and otherwise requires the bound users_id to appear in the
        statement parameters or literal SQL."""
        users_id = self._users_id

        @event.listens_for(self._engine, "before_cursor_execute")
        def _assert_tenant_bound(
            conn, cursor, statement, parameters, context, executemany
        ):  # noqa: ANN001
            if _is_tenant_exempt(statement):
                return
            if not _statement_carries_users_id(statement, parameters, users_id):
                raise TenantBindingError(
                    "per-tenant statement does not carry bound users_id="
                    f"{users_id!r}: {statement.strip()[:200]}"
                )

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
