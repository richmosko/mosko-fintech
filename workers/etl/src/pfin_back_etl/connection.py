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
          catalogued §10 numbered-list instance (that ledger stays at 3 =
          RT-22 first / RT-26 second / RT-27 third — moved 2→3 at the ADR-027
          (hh) / SELF-212 flip, 2026-07-19). The V1-SHIP-BLOCK axis is
          orthogonal to the §10-catalogued axis.
        - workers/CLAUDE.md — TBC discipline / same-transaction audit-log.

    DB IDENTITY MODEL (SELF-214 Sec joint-review v3 B1 + B8 option (B), both
    F/CTO-ratified). Read this before copying the pattern:

        LOGIN role  = `pfin_etl` — the ETL's DEDICATED NOINHERIT login role
                      (B8 option (B), ratified 2026-08-02; created by an
                      Architect migration with membership in `service_role` +
                      `authenticated`). `rolcanlogin = t`, `rolinherit = f`,
                      NOT BYPASSRLS, NOT the `pfin` owner. Because it is
                      NOINHERIT it holds NO privileges until an explicit
                      `SET [LOCAL] ROLE`.
                      NOT shared with workers/provider-sync, which stays on
                      `authenticator` per ADR-023 — so that ADR's condition-C1
                      rotation coupling (PostgREST + provider-sync) does NOT
                      reach the ETL; this credential rotates independently.
        READ  role  = `authenticated` via `SET LOCAL ROLE` + a synthetic JWT
                      claims GUC — see impersonate(). RLS applies.
        WRITE role  = `service_role` via `SET LOCAL ROLE service_role` — the
                      Decision-1 privileged non-JWT writer, whose least-privilege
                      per-table grants (migration 008 + friends) are what make
                      the write path's ACL fence real.

        `service_role` is `rolcanlogin = f` (MEASURED): it can NEVER be a
        direct-Postgres login identity. Any doc or docstring saying a worker
        "connects as service_role" names a transport-impossible role — that
        exact phrasing is what SELF-214's Sec review retracted. Say "logs in as
        `pfin_etl`, writes AS `service_role` via SET LOCAL ROLE" instead.

        CONSEQUENCE, and it bites: under NOINHERIT `pfin_etl`, ANY pfin
        statement issued without a prior `SET [LOCAL] ROLE` fails `42501`. That
        includes system()-mode global-reference writes. Every call site is
        responsible for setting the role it needs inside its transaction.

    V1.0 SCOPE (SELF-193 — honest scaffold, ratified DP1a/DP2a/DP3a/DP4a):
        Against the V1 greenfield schema the ETL writes ONLY global
        market-reference tables: **pfin.asset (016) / pfin.eod_price (019) /
        pfin.cpi_u_index (053)**. NONE of these has a `users_id` column
        (VERIFIED against the CREATE TABLE blocks, 2026-08-02) — they are shared
        reference data, not per-tenant rows. THAT is the security rationale for
        `.system()` mode registering no per-tenant assertion: there is no tenant
        to bind, so the exemption is by-construction rather than a bypass. There
        is no per-user pfin write path in the ETL beyond the SELF-214 NAV worker
        below (tax / monthly_report / per-user Plaid crons land in later Waves).

        STALE ENUMERATION CORRECTED (SELF-214 Sec joint-review v5, folded into
        B6 as the same drift class). This paragraph previously also listed
        pfin.cpi / equity_profile / reporting_period / income_statement /
        balance_sheet_statement / cash_flow_statement / earning / asset_cat.
        **No V1 migration creates any of those eight** (verified: zero
        `create table` matches across supabase/migrations/) — they are incumbent
        cax21/pfindash.com tables that came in with the ADR-019 monorepo fold.
        The conclusion above was never wrong; only the list was. Correcting it
        matters because this docstring is the stated justification for a
        fence-exemption, in the file that anchors TBC discipline project-wide.
        See `core.py` + workers/CLAUDE.md for the un-reconciled incumbent path.

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
import re
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

# LEGACY SINGULAR GUC (SELF-214 Sec joint-review N7). auth.uid() is:
#     coalesce(
#       nullif(current_setting('request.jwt.claim.sub', true), ''),
#       (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
#     )::uuid
# — the SINGULAR form WINS over the plural blob impersonate() sets. If it were ever
# set at session or role scope (`ALTER ROLE … SET`, an `options=-c` DSN parameter),
# auth.uid() would resolve to that one value for EVERY tenant in the run while the
# Python variable looked correct throughout. impersonate() therefore CLEARS it
# defensively at block entry, and the assertion below permits ONLY the NULL clear —
# worker code setting this GUC to a value is a fence violation by construction.
_JWT_CLAIM_SUB_GUC = "request.jwt.claim.sub"
# NOTE (checked, not assumed): the two GUC names are NOT substrings of one another
# ("request.jwt.claims" ends in `s`; "request.jwt.claim.sub" has `.` there), so the
# two containment branches in _check_tenant_statement are disjoint.


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

        THIS IS A READ-ONLY PRIMITIVE. It mints a synthetic `aal2` claim, and it
        MUST NEVER WRAP A WRITE. The read-only property is ENFORCED, not merely
        documented: while the binding is active the per-tenant assertion rejects
        every write/DDL statement (see _reject_write_while_impersonating).

        SELF-214 W-1 (first live per-user worker write path; Sec-joint-reviewed):
        the worker LOGS IN as `pfin_etl` (dedicated NOINHERIT role; see the module
        docstring — `service_role` is NOLOGIN and can never be a login identity)
        and carries no user session, so an INVOKER read would see `auth.uid()`
        NULL and return 0. Within a for_tenant()-bound transaction this sets,
        transaction-locally:
            select set_config('request.jwt.claim.sub', NULL, true);  -- N7
            SET LOCAL ROLE authenticated;
            select set_config('request.jwt.claims', '{"sub": <users_id>, ...}', true);
        making `auth.uid()` = the bound users_id for the block. On exit it tears the
        binding down (claims cleared, RESET ROLE).

        WHAT THE CALLER MUST DO AFTER THE BLOCK. `reset role` returns the session to
        `pfin_etl`, which is NOINHERIT — it holds NO privileges. A privileged
        write therefore requires an explicit `set local role service_role` at the
        call site (ADR-023 write-role-of-record). Without it the write fails 42501.
        impersonate() deliberately does NOT do this for you: assuming the write role
        is the caller's decision, and the primitive stays read-only end to end.

        Contract:
          - MUST be a for_tenant()-bound TBC (raises in system mode).
          - MUST run inside an open transaction — SET LOCAL / set_config(..., true)
            are transaction-scoped; they auto-clear at COMMIT/ROLLBACK even if the
            explicit teardown is skipped.
          - Isolation for reads in the block is enforced by RLS via the JWT claim;
            the firmed per-tenant assertion verifies the impersonation binding
            matches the bound users_id (strict equality on the claims `sub`) before
            permitting non-users_id-carrying reads.
          - The block is READ-ONLY (fenced). Writes belong after teardown, under an
            explicitly assumed write role.
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
        # N7 (Sec joint-review v2 advisory): clear the LEGACY SINGULAR GUC first.
        # auth.uid() prefers request.jwt.claim.sub over the plural blob we are about
        # to set, so a session/role-scoped value there would silently resolve EVERY
        # tenant to one user. Transaction-local; removes the precedence hazard at
        # source. See _JWT_CLAIM_SUB_GUC.
        conn.execute(
            sqla.text(f"select set_config('{_JWT_CLAIM_SUB_GUC}', NULL, true)")
        )
        conn.execute(sqla.text("set local role authenticated"))
        conn.execute(
            sqla.text(f"select set_config('{_JWT_CLAIMS_GUC}', :claims, true)"),
            {"claims": claims},
        )
        try:
            yield conn
        finally:
            # N1 (Sec joint-review advisory): if the block raised a DB error the
            # transaction is ABORTED and these two statements raise
            # InFailedSqlTransaction, REPLACING the original exception — destroying
            # diagnosis on exactly the path where it matters most. Swallow and log;
            # the original propagates. Safe because SET LOCAL ROLE +
            # set_config(..., true) are transaction-scoped and auto-clear at
            # COMMIT/ROLLBACK regardless, and an aborted txn cannot carry a
            # privileged write afterwards (fail-closed).
            try:
                conn.execute(
                    sqla.text(f"select set_config('{_JWT_CLAIMS_GUC}', NULL, true)")
                )
                conn.execute(sqla.text("reset role"))
            except Exception:
                logger.warning(
                    "impersonate() teardown failed (transaction likely already "
                    "aborted). Swallowed so the ORIGINAL exception is not masked; "
                    "the transaction-local role + claims auto-clear at "
                    "COMMIT/ROLLBACK.",
                    exc_info=True,
                )

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
        keeps a for_tenant(A) connection from silently acting on tenant B.

        Additionally (SELF-214 Sec joint-review B2): while binding (b) is active the
        hook is READ-ONLY — every write/DDL statement is rejected outright, because
        the impersonated session is `authenticated` + synthetic `aal2` and would
        otherwise satisfy every aal2-gated write path in the schema."""
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


# --------------------------------------------------------------------------- #
# B2 read-only fence on the impersonation primitive (SELF-214 Sec joint-review).
# --------------------------------------------------------------------------- #
# Statement HEADS permitted while an impersonation binding is active. Inside the
# block current_user = 'authenticated' AND auth.jwt() ->> 'aal' = 'aal2', which
# satisfies EVERY aal2-gated write path on the 025-backstopped tables — including
# ADR-029 Decision 6's MB-1 `mfa_policy` totp→none downgrade guard, the very
# control whose un-downgradability makes nav_daily's inherited fail-open posture
# sound. Latent today (the block issues one SELECT), but ADR-040 makes W-1 the
# durable per-user worker pattern and the next caller will not re-derive this.
_IMPERSONATION_ALLOWED_HEADS = frozenset(
    {"select", "with", "values", "table", "explain", "show"}
)

# Write/DDL keywords rejected inside a `with`-headed statement — a data-modifying
# CTE (`with x as (…) insert into …`) hides the write verb behind a read head.
# Matched as WHOLE WORDS against `[a-z_][a-z0-9_]*` tokens, so a column named
# `updated_at` is one token and is NOT mistaken for `update`.
_IMPERSONATION_WRITE_TOKENS = frozenset(
    {
        "insert", "update", "delete", "merge", "truncate", "copy",
        "alter", "drop", "create", "grant", "revoke",
        "call", "do", "lock", "refresh", "reindex", "vacuum", "cluster",
        "comment", "import", "prepare", "execute",
    }
)

_HEAD_TOKEN_RE = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
_WORD_TOKEN_RE = re.compile(r"[a-z_][a-z0-9_]*")


def _statement_head(statement):
    """The first SQL keyword token, lowercased. Returns '' when the statement does
    not begin with an identifier-shaped token (e.g. a leading comment) — which the
    read-only fence treats as NOT-allowed, i.e. fails closed."""
    match = _HEAD_TOKEN_RE.match(statement.lstrip())
    return match.group(0).lower() if match else ""


def _reject_write_while_impersonating(statement):
    """Fail closed on any write/DDL statement issued while an impersonation binding
    is active (B2). impersonate() is a READ primitive; this is what makes that a
    property rather than a comment.

    Deliberately permits the SANCTIONED BINDING OPS, which are `SELECT`s invoking a
    setter and must not be mistaken for writes:
      - `select set_config('request.jwt.claims', …)`     — handled earlier (branch 1)
      - `select set_config('request.jwt.claim.sub', …)`  — handled earlier (branch 0)
      - `select set_config('app.nav_computed_for', auth.uid()::text, true)` — the
        B7 write-tenant binding GUC, head `select`, permitted here.
    A naive verb fence that pattern-matched `set_config` or treated these as writes
    would deadlock the whole design; the head-verb shape is why it does not.

    RESIDUAL, stated rather than hidden: a `select` that invokes a data-modifying
    function (`select some_writing_fn()`) is not statically detectable and passes.
    The fence bounds the statement surface, not function bodies. Also note that a
    `set local role service_role` inside the block stays exempt-prefixed — but the
    impersonation key remains set, so any write that follows it is still rejected;
    escalate-then-write does not slip through."""
    head = _statement_head(statement)
    if head not in _IMPERSONATION_ALLOWED_HEADS:
        raise TenantBindingError(
            "impersonate() is a READ-ONLY primitive (SELF-214 Sec joint-review B2): "
            "the impersonated session is `authenticated` + synthetic aal2 and would "
            "satisfy every aal2-gated write path. Rejected write/DDL statement "
            f"(head={head!r}) while impersonation is active: "
            f"{statement.strip()[:200]}"
        )
    if head == "with":
        offending = sorted(
            set(_WORD_TOKEN_RE.findall(statement.lower())) & _IMPERSONATION_WRITE_TOKENS
        )
        if offending:
            raise TenantBindingError(
                "impersonate() is a READ-ONLY primitive (SELF-214 Sec joint-review "
                "B2): data-modifying CTE rejected while impersonation is active "
                f"(write keywords {offending}): {statement.strip()[:200]}"
            )


# --------------------------------------------------------------------------- #
# B4 — strict equality on the claims `sub` (SELF-214 Sec joint-review).
# --------------------------------------------------------------------------- #
def _extract_claims_payloads(statement, parameters):
    """Candidate JSON claims payloads carried by a request.jwt.claims binding op —
    from bound parameters (the normal path) or an inline literal in the SQL text.

    An EMPTY result means the op carries no payload at all, i.e. it is a NULL clear
    (teardown) — not a parse failure. The distinction matters: teardown must not
    emit a WARNING on every single call."""
    payloads = []
    for value in _iter_param_values(parameters):
        text = str(value)
        if "{" in text:
            payloads.append(text)
    start = statement.find("{")
    end = statement.rfind("}")
    if start != -1 and end > start:
        payloads.append(statement[start : end + 1])
    return payloads


def _claims_carry_users_id(statement, parameters, target):
    """True iff a JWT-claims binding op establishes a binding for `target` — by
    STRICT EQUALITY on the claims `sub`, not containment.

    B4 (Sec joint-review, blocking). The old containment check returned True if the
    target uid appeared ANYWHERE in the statement or ANY parameter value. The
    exploitable shape is FIELD-POSITION, not UUID-substring: a claims blob whose
    `sub` is tenant B but which carries tenant A's uid in any OTHER field (email,
    app_metadata, …) would register an impersonation binding for A while the
    database resolves auth.uid() to B — and every subsequent bare read would then
    pass the fence and return B's data on an A-bound connection. Containment cannot
    distinguish that; equality-on-`sub` can. The direct-write path
    (_statement_carries_users_id) already used strict equality; the asymmetry WAS
    the defect.

    Fallback: containment, ONLY when a payload is present but unparseable or has no
    `sub` — logged at WARNING, per Sec's required shape. A parsed payload whose
    `sub` is some OTHER tenant returns False definitively; it never falls back."""
    payloads = _extract_claims_payloads(statement, parameters)
    if not payloads:
        # No payload at all → a NULL clear (teardown). No binding, no warning.
        return False

    unparseable = []
    for payload in payloads:
        try:
            claims = json.loads(payload)
        except (ValueError, TypeError):
            unparseable.append(payload)
            continue
        if not isinstance(claims, dict) or "sub" not in claims:
            unparseable.append(payload)
            continue
        # Parsed and authoritative: equality on `sub` decides, both ways.
        return str(claims["sub"]) == target

    logger.warning(
        "TenantBoundConnection: JWT-claims payload could not be parsed for a "
        "strict `sub` equality check (B4); falling back to CONTAINMENT, which is "
        "weaker than the mistake this fence guards against. Fix the caller to pass "
        "a well-formed JSON claims blob."
    )
    return any(target in payload for payload in unparseable) or target in statement


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
      (b) IMPERSONATION — SET ROLE authenticated + request.jwt.claims.sub ==
          users_id (STRICT equality, B4) are active on this connection (established
          by impersonate()), so RLS/auth.uid() enforces isolation for a read that
          does not name users_id. Binding (b) admits READS ONLY (B2).
    """
    target = str(users_id)
    lowered = statement.lower()

    # (0) LEGACY SINGULAR GUC (N7). auth.uid() reads request.jwt.claim.sub in
    # PREFERENCE to the plural blob, so worker code may CLEAR it (impersonate()'s
    # defensive entry statement) but may NEVER SET it — setting it would let one
    # value resolve every tenant while the Python variable still looked correct.
    # Disjoint from branch (1): neither GUC name contains the other.
    if _JWT_CLAIM_SUB_GUC in lowered:
        if "null" in lowered and not list(_iter_param_values(parameters)):
            return  # sanctioned defensive clear
        raise TenantBindingError(
            "setting the legacy singular GUC "
            f"'{_JWT_CLAIM_SUB_GUC}' is forbidden in worker code (SELF-214 N7): "
            "auth.uid() prefers it over request.jwt.claims, so a value here would "
            "silently override the per-tenant impersonation binding. Only the "
            f"NULL clear is permitted: {statement.strip()[:200]}"
        )

    # (1) Impersonation binding op: sets the JWT-claims GUC (via SET LOCAL
    # "request.jwt.claims" = … or select set_config('request.jwt.claims', …)).
    # A claims blob whose `sub` EQUALS the bound users_id ESTABLISHES impersonation;
    # anything else (a different sub, or a NULL clear) CLEARS it. The binding op
    # itself is always allowed. Strict equality on `sub`, not containment — B4.
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

    # (3) B2 READ-ONLY FENCE — while ANY impersonation binding is active (whichever
    # tenant), reject writes/DDL outright. Placed AFTER (1) and (2) so the sanctioned
    # binding + teardown + session-setup ops are already returned, and BEFORE (4) so
    # a write cannot be admitted by the impersonation binding it is abusing.
    if _IMPERSONATION_KEY in info:
        _reject_write_while_impersonating(statement)

    # (4) DML / function statement — require binding (a) OR (b), else fail closed.
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
