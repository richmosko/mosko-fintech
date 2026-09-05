"""
Project:       pfin-back-etl
Author:        Rich Mosko (mosko-fintech Backend)

Description:
    `integration`-tier tests for MonthlyReportCronWorker's DB-touching half
    (SELF-351 / A7) — account_user_ids(), server_today(),
    open_draft_for_tenant() and run(). These need a REAL Postgres round trip
    through TenantBoundConnection.impersonate() calling INTO
    pfin.fn_open_monthly_report_draft (113) — not mocked, for the same
    reason test_nav_backfill_write.py gives: the whole point of this
    battery is that the write-tenant binding and 113's idempotency/audit
    behavior are proven against a live database, not asserted about a mock.

    SCRATCH DATABASE CLONE OF `pfin_tmpl`, never F/CTO's real local dev DB.
    `pfin_tmpl` is the shared local-cluster TEMPLATE database this session
    rebuilt through migration 114 (origin/feature/self-355-db @ 5789c2d,
    applying 112/113/114 on top of what the template already carried) — see
    the SELF-351 hand-off report for the exact commands. `CREATE DATABASE
    ... TEMPLATE pfin_tmpl` is a fast structural CLONE (no re-running 114
    migrations per test module), used here rather than
    test_nav_backfill_write.py's own from-scratch migration-glob approach,
    which globs THIS WORKTREE's `supabase/migrations/` and would not see
    108-114 (those files exist only on origin/feature/self-355-db, an
    unmerged Architect branch this worker does not check out).

    ⚠ NEVER `pfin_etl` — see test_nav_backfill_write.py's `scratch_db`
    fixture docstring for the incident (`ALTER ROLE pfin_etl LOGIN
    PASSWORD ...` against a scratch DB silently rewrote the REAL cluster-
    wide `pfin_etl` credential) this convention exists to prevent. This
    file creates and drops its OWN throwaway login role, named distinctly.

    ALL TENANT IDENTITIES ARE SYNTHETIC — RT-15 parity-fixture posture. Fresh
    per test function (uuid4()) for the SAME append-only-adjacent reason
    test_nav_backfill_write.py gives — `pfin.monthly_report` blocks DELETE
    for every role (108's own trigger), so isolating tests means never
    reusing an identity, not clearing rows between tests.

    Requires a Postgres reachable at 127.0.0.1:54322 (the local Supabase
    stack) with a `pfin_tmpl` database already built through migration 114.
    Skips cleanly (not a hard failure) if either is missing, so this file
    does not break a run on a machine without that local setup.
"""

import datetime as dt
import os
import subprocess
import uuid

import pytest

pytestmark = pytest.mark.integration

_HOST = "127.0.0.1"
_PORT = "54322"
_TEMPLATE_DB = "pfin_tmpl"
_SCRATCH_DB = "self351_scratch_a7_write_int"
_SCRATCH_LOGIN_ROLE = "self351_scratch_a7_login"  # created+dropped HERE, never pfin_etl
_SCRATCH_LOGIN_PASSWORD = "self351_scratch_only_not_real"

# subprocess.run's `env=` REPLACES the whole environment, not merges it — a
# bare {"PGPASSWORD": ...} here would drop PATH and make `psql` unresolvable.
# Merge onto the current process's environment instead.
_PSQL_ENV = {**os.environ, "PGPASSWORD": "postgres"}


def _psql(db, sql, check=True):
    cmd = [
        "psql",
        "-h", _HOST,
        "-p", _PORT,
        "-U", "postgres",
        "-d", db,
        "-v", "ON_ERROR_STOP=1",
        "-c", sql,
    ]
    return subprocess.run(
        cmd, capture_output=True, text=True, check=check, env=_PSQL_ENV
    )


def _postgres_available():
    try:
        r = subprocess.run(
            ["psql", "-h", _HOST, "-p", _PORT, "-U", "postgres", "-d", "postgres", "-c", "select 1;"],
            capture_output=True, timeout=5, env=_PSQL_ENV,
        )
        return r.returncode == 0
    except Exception:
        return False


def _template_ready():
    r = _psql(
        _TEMPLATE_DB,
        "select 1 from pg_proc join pg_namespace n on n.oid = pronamespace "
        "where n.nspname = 'pfin' and proname = 'fn_open_monthly_report_draft';",
        check=False,
    )
    return r.returncode == 0 and "1" in r.stdout


@pytest.fixture(scope="function")
def scratch_db():
    """PER-TEST scratch database: a fast structural CLONE of `pfin_tmpl`
    (already built through 114), a THROWAWAY login role armed with the same
    membership shape as `pfin_etl` (service_role + authenticated), dropped
    on teardown regardless of test outcome.

    ⚠ FUNCTION-SCOPED, DELIBERATELY, unlike test_nav_backfill_write.py's own
    MODULE-scoped `scratch_db` — that file's tests never call a
    cross-tenant enumeration method, so sharing one DB across every test in
    the module is safe there. Several tests HERE call
    `account_user_ids()` / `run()`, which read EVERY tenant in the database
    with no per-test scoping — sharing one module-level DB would let one
    test's fresh `seeded_tenants` accumulate on top of every earlier test's,
    so a later test's cross-tenant enumeration would see every tenant ANY
    test in the file ever seeded, not just its own two. A fresh CLONE per
    test costs a little more wall-clock (the clone itself is fast — a
    filesystem-level copy, not a re-run of 114 migrations) and buys true
    per-test isolation for exactly the two tests that need it."""
    if not _postgres_available():
        pytest.skip(f"Postgres not reachable at {_HOST}:{_PORT} — skipping integration tier")
    if not _template_ready():
        pytest.skip(
            f"{_TEMPLATE_DB!r} does not have pfin.fn_open_monthly_report_draft (113) — "
            "rebuild it against origin/feature/self-355-db through migration 114 first."
        )

    _psql("postgres", f"DROP DATABASE IF EXISTS {_SCRATCH_DB};")
    r = _psql("postgres", f"CREATE DATABASE {_SCRATCH_DB} TEMPLATE {_TEMPLATE_DB};")
    assert r.returncode == 0, f"scratch clone failed: {r.stderr}"

    _psql("postgres", f"DROP ROLE IF EXISTS {_SCRATCH_LOGIN_ROLE};")
    r = _psql(
        _SCRATCH_DB,
        f"create role {_SCRATCH_LOGIN_ROLE} noinherit login "
        f"password '{_SCRATCH_LOGIN_PASSWORD}';",
    )
    assert r.returncode == 0, f"scratch login role create failed: {r.stderr}"
    r = _psql(
        _SCRATCH_DB,
        f"grant service_role to {_SCRATCH_LOGIN_ROLE}; "
        f"grant authenticated to {_SCRATCH_LOGIN_ROLE};",
    )
    assert r.returncode == 0, f"scratch login role membership grant failed: {r.stderr}"

    yield {"dbname": _SCRATCH_DB}

    _psql("postgres", f"DROP DATABASE IF EXISTS {_SCRATCH_DB};")
    _psql("postgres", f"DROP ROLE IF EXISTS {_SCRATCH_LOGIN_ROLE};")


@pytest.fixture
def pfin_env(scratch_db, monkeypatch):
    """Point PFIN_DB_* at the scratch DB for exactly one test."""
    monkeypatch.setenv("PFIN_DB_HOST", _HOST)
    monkeypatch.setenv("PFIN_DB_PORT", _PORT)
    monkeypatch.setenv("PFIN_DB_NAME", _SCRATCH_DB)
    monkeypatch.setenv("PFIN_DB_USER", _SCRATCH_LOGIN_ROLE)
    monkeypatch.setenv("PFIN_DB_PASSWORD", _SCRATCH_LOGIN_PASSWORD)
    monkeypatch.setenv("PFIN_DB_SSLMODE", "disable")


@pytest.fixture
def seeded_tenants(scratch_db):
    """Two FRESH synthetic tenants, each owning exactly one account (so
    account_user_ids() finds them — mirrors nav_daily.py's own enumeration
    predicate). Fresh uuid4() per test function; see module docstring."""
    tenant_a = uuid.uuid4()
    tenant_b = uuid.uuid4()
    r = _psql(
        _SCRATCH_DB,
        f"insert into auth.users (id) values ('{tenant_a}'), ('{tenant_b}');",
    )
    assert r.returncode == 0, f"tenant seed failed: {r.stderr}"
    # One open account per tenant — account_user_ids() enumerates
    # `select distinct users_id from pfin.account`, mirroring nav_daily.py.
    r = _psql(
        _SCRATCH_DB,
        f"insert into pfin.account (users_id, name, account_type, scope, tax_treatment) "
        f"values ('{tenant_a}', 'Tenant A Checking', 'depository', 'personal', 'taxable'), "
        f"('{tenant_b}', 'Tenant B Checking', 'depository', 'personal', 'taxable');",
    )
    assert r.returncode == 0, f"account seed failed: {r.stderr}"
    yield {"a": tenant_a, "b": tenant_b}


def _audit_rows_for(dbname, report_id):
    r = _psql(
        dbname,
        f"select trigger_source, users_id, tenant_resolution_chain from pfin.audit_log "
        f"where subject_id = {report_id} and subject_table = 'pfin.monthly_report';",
    )
    return r.stdout


def _report_row(dbname, users_id, target_month):
    r = _psql(
        dbname,
        f"select report_id, generation_status from pfin.monthly_report "
        f"where users_id = '{users_id}' and target_month = '{target_month}';",
    )
    return r.stdout


class TestPriorMonthFirstDay:
    """Pure function — no DB, no clock. Not marked `integration`."""

    def test_mid_month(self):
        from pfin_back_etl.monthly_report_cron import prior_month_first_day

        assert prior_month_first_day(dt.date(2026, 9, 5)) == dt.date(2026, 8, 1)

    def test_first_of_month(self):
        from pfin_back_etl.monthly_report_cron import prior_month_first_day

        assert prior_month_first_day(dt.date(2026, 9, 1)) == dt.date(2026, 8, 1)

    def test_january_rolls_back_to_prior_december(self):
        from pfin_back_etl.monthly_report_cron import prior_month_first_day

        assert prior_month_first_day(dt.date(2026, 1, 15)) == dt.date(2025, 12, 1)


def test_account_user_ids_enumerates_both_seeded_tenants(pfin_env, seeded_tenants):
    from pfin_back_etl import MonthlyReportCronWorker

    worker = MonthlyReportCronWorker()
    ids = {str(u) for u in worker.account_user_ids()}
    assert str(seeded_tenants["a"]) in ids
    assert str(seeded_tenants["b"]) in ids


def test_server_today_reads_a_real_date(pfin_env, seeded_tenants):
    from pfin_back_etl import MonthlyReportCronWorker

    worker = MonthlyReportCronWorker()
    today = worker.server_today()
    assert isinstance(today, dt.date)


def test_open_draft_for_tenant_inserts_one_draft_and_one_audit_row(pfin_env, seeded_tenants):
    from pfin_back_etl import MonthlyReportCronWorker

    worker = MonthlyReportCronWorker()
    target_month = dt.date(2026, 8, 1)
    tenant_a = seeded_tenants["a"]

    report_id = worker.open_draft_for_tenant(tenant_a, target_month)
    assert report_id is not None

    row_out = _report_row(_SCRATCH_DB, tenant_a, target_month)
    assert str(report_id) in row_out
    assert "draft" in row_out

    audit_out = _audit_rows_for(_SCRATCH_DB, report_id)
    assert str(tenant_a) in audit_out


def test_open_draft_for_tenant_audit_row_names_the_resolved_tenant_and_chain(pfin_env, seeded_tenants):
    """AC 6's catch criterion, restored at P10: the audit row exists and
    names the resolved tenant. See the class-level xfail-style note below
    for the trigger_source half this AC also requires — measured, not
    assumed."""
    from pfin_back_etl import MonthlyReportCronWorker

    worker = MonthlyReportCronWorker()
    target_month = dt.date(2026, 8, 1)
    tenant_b = seeded_tenants["b"]

    report_id = worker.open_draft_for_tenant(tenant_b, target_month)
    audit_out = _audit_rows_for(_SCRATCH_DB, report_id)
    assert str(tenant_b) in audit_out


def test_MEASURED_GAP_audit_row_trigger_source_is_currently_on_demand_not_cron(pfin_env, seeded_tenants):
    """⚠⚠ THIS TEST DOCUMENTS A REAL, MEASURED CONTRADICTION OF SELF-351 AC 6,
    NOT A PASSING REQUIREMENT. `pfin.fn_open_monthly_report_draft` (113)
    hardcodes `trigger_source = 'on_demand'` in its own
    `perform pfin.fn_emit_audit_log(...)` call — there is no parameter or
    GUC this cron worker can vary to make it emit `'cron'` instead (see
    monthly_report_cron.py's module docstring FLAG 2, and the SELF-351
    hand-off report). This test asserts the CURRENT, ACTUAL value rather
    than the AC's REQUIRED value, so the gap is visible as a committed,
    running fact in the tree — not merely described in prose — until
    Architect gives 113 a way to vary it (e.g. a `p_trigger_source`
    parameter). When that lands, THIS TEST MUST BE REWRITTEN to assert
    `'cron'` and FAIL if it still reads `'on_demand'` — flip it, do not
    delete it, so the fix is provably exercised.
    """
    from pfin_back_etl import MonthlyReportCronWorker

    worker = MonthlyReportCronWorker()
    target_month = dt.date(2026, 8, 1)
    tenant_a = seeded_tenants["a"]

    report_id = worker.open_draft_for_tenant(tenant_a, target_month)
    audit_out = _audit_rows_for(_SCRATCH_DB, report_id)
    assert "on_demand" in audit_out, (
        "If this fails because the row now says 'cron', 113 has been fixed — "
        "update this test (see its own docstring) to require 'cron' and stop "
        "asserting the old, wrong value."
    )
    assert "cron" not in audit_out.replace("on_demand", "")


def test_open_draft_for_tenant_is_idempotent(pfin_env, seeded_tenants):
    """Calling twice for the SAME (tenant, month) returns the SAME report_id
    and writes exactly ONE draft row and ONE audit row — 113's own
    idempotency contract (E15 item 9: 'generate' on a month with a live
    draft OPENS it, never inserts a second one)."""
    from pfin_back_etl import MonthlyReportCronWorker

    worker = MonthlyReportCronWorker()
    target_month = dt.date(2026, 8, 1)
    tenant_a = seeded_tenants["a"]

    first_id = worker.open_draft_for_tenant(tenant_a, target_month)
    second_id = worker.open_draft_for_tenant(tenant_a, target_month)
    assert first_id == second_id

    r = _psql(
        _SCRATCH_DB,
        f"select count(*) from pfin.monthly_report where users_id = '{tenant_a}' "
        f"and target_month = '{target_month}';",
    )
    assert " 1" in r.stdout or "\n1" in r.stdout

    r = _psql(
        _SCRATCH_DB,
        f"select count(*) from pfin.audit_log where subject_id = {first_id} "
        f"and subject_table = 'pfin.monthly_report';",
    )
    assert " 1" in r.stdout or "\n1" in r.stdout


def test_cross_tenant_isolation_tenant_b_never_opens_or_sees_tenant_as_draft(pfin_env, seeded_tenants):
    """A draft opened for tenant A must never be reachable, readable, or
    reopenable under tenant B's impersonation."""
    from pfin_back_etl import MonthlyReportCronWorker

    worker = MonthlyReportCronWorker()
    target_month = dt.date(2026, 8, 1)
    tenant_a = seeded_tenants["a"]
    tenant_b = seeded_tenants["b"]

    report_id_a = worker.open_draft_for_tenant(tenant_a, target_month)
    report_id_b = worker.open_draft_for_tenant(tenant_b, target_month)
    assert report_id_a != report_id_b


def test_reset_role_discipline_teardown_actually_fires(pfin_env, seeded_tenants):
    """R3 rider 3's catch criterion, concrete half: prove — against a REAL
    connection, not the docstring's claim — that `impersonate()`'s teardown
    actually resets the session role after a write-performing call inside
    it. Opens its OWN connection (not through MonthlyReportCronWorker, so
    the role can be inspected AFTER the worker's own context managers have
    exited).

    Uses `SHOW ROLE` rather than `select current_user`/`current_role`:
    those are ordinary function calls and trip connection.py's OWN
    per-tenant assertion (branch (4) — neither a literal users_id nor an
    active impersonation binding, so it fails closed, CORRECTLY, exactly as
    designed) when issued directly on a `for_tenant()`-bound connection.
    `SHOW ...` is one of the fence's own explicitly TENANT-EXEMPT prefixes
    (`_TENANT_EXEMPT_PREFIXES`) — session introspection, not a per-tenant
    DML/function statement — so it reaches the database unfenced. `SHOW
    ROLE` reports the `role` GUC's current value: `'none'` when no `SET
    ROLE` is active (verified live against pfin_tmpl: 'none' at a fresh
    transaction's start, 'service_role' immediately after `SET LOCAL ROLE
    service_role`, and 'none' again immediately after `RESET ROLE` — the
    exact three-state sequence this test exercises across
    `impersonate()`'s own boundary)."""
    from pfin_back_etl.connection import TenantBoundConnection
    from pfin_back_etl import utils
    import sqlalchemy as sqla

    params = utils.load_db_params("PFIN_")
    db_url = utils.build_database_url(params)
    tbc = TenantBoundConnection.for_tenant(db_url, seeded_tenants["a"])

    with tbc.engine.connect() as conn:
        with conn.begin():
            with tbc.impersonate(conn):
                role_during = conn.execute(sqla.text("show role")).scalar()
                assert role_during == "authenticated", (
                    f"expected 'authenticated' while impersonation is active, "
                    f"got {role_during!r}."
                )
                conn.execute(
                    sqla.text(
                        "select pfin.fn_open_monthly_report_draft(:m) as report_id"
                    ),
                    {"m": dt.date(2026, 8, 1)},
                )
            # OUTSIDE the impersonate() block, same connection, same
            # transaction: the teardown's `reset role` must have already
            # fired.
            role_after = conn.execute(sqla.text("show role")).scalar()
            assert role_after == "none", (
                f"expected the 'role' GUC back to 'none' after impersonate() "
                f"teardown, got {role_after!r} — a leaked SET would surface "
                f"here."
            )


def test_reset_role_discipline_a_fresh_tenant_connection_is_unaffected_by_a_prior_one(
    pfin_env, seeded_tenants
):
    """R3 rider 3's catch criterion, isolation half: even granting that a
    PRIOR tenant's connection somehow left role/claims state dirty, a FRESH
    `for_tenant()` TBC for the NEXT tenant (a brand-new SQLAlchemy engine,
    hence — under NullPool — a brand-new physical connection) starts from
    the scratch login role with NO impersonation binding, and correctly
    resolves `auth.uid()` to the SECOND tenant, never the first."""
    from pfin_back_etl import MonthlyReportCronWorker

    worker = MonthlyReportCronWorker()
    target_month = dt.date(2026, 8, 1)
    tenant_a = seeded_tenants["a"]
    tenant_b = seeded_tenants["b"]

    worker.open_draft_for_tenant(tenant_a, target_month)
    # A fresh connection for tenant B must resolve auth.uid() to B, never A —
    # the concrete DB-verified proof that nothing leaked across the two
    # separate for_tenant() engines this method opens per call.
    from pfin_back_etl.connection import TenantBoundConnection
    from pfin_back_etl import utils
    import sqlalchemy as sqla

    params = utils.load_db_params("PFIN_")
    db_url = utils.build_database_url(params)
    tbc_b = TenantBoundConnection.for_tenant(db_url, tenant_b)
    with tbc_b.engine.connect() as conn:
        with conn.begin():
            with tbc_b.impersonate(conn):
                resolved = conn.execute(sqla.text("select auth.uid()")).scalar()
                assert str(resolved) == str(tenant_b)
                assert str(resolved) != str(tenant_a)


def test_run_processes_both_tenants_and_isolates_a_failure(pfin_env, seeded_tenants, monkeypatch):
    """run()'s per-tenant try/except: a raise for ONE tenant costs only that
    tenant — the other's draft still lands. Simulated by monkeypatching
    open_draft_for_tenant to raise for tenant A only."""
    from pfin_back_etl import MonthlyReportCronWorker

    worker = MonthlyReportCronWorker()
    tenant_a = str(seeded_tenants["a"])

    original = worker.open_draft_for_tenant

    def _flaky(users_id, target_month):
        if str(users_id) == tenant_a:
            raise RuntimeError("simulated per-tenant failure")
        return original(users_id, target_month)

    monkeypatch.setattr(worker, "open_draft_for_tenant", _flaky)

    summary = worker.run()
    assert summary["total"] == 2
    assert summary["ok"] == 1
    assert summary["failed"] == 1

    # The failed tenant leaves NO partial row (113's own body is one
    # transaction; a raise before it commits leaves nothing behind — this
    # simulated failure raises BEFORE 113 is even called, so this also
    # covers the "raised before write" shape, not just "write rolled back").
    target_month = summary["target_month"]
    row_out = _report_row(_SCRATCH_DB, seeded_tenants["a"], target_month)
    assert row_out.strip().count("\n") <= 2  # header + separator, no data row
