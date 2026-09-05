"""
Project:       pfin-back-etl
Author:        Backend (mosko-fintech)

Description:
    `integration`-tier tests for NavDailyWorker.compute_and_checkpoint_user()'s
    SELF-353 / A9 addition — the per-account leaf write to
    pfin.nav_component_daily (migration 107), alongside the pre-existing scalar
    checkpoint write to pfin.nav_daily (migration 054), in the SAME transaction.

    Same harness shape as test_nav_backfill_write.py (Backend's own review,
    2026-08-12, reused here rather than re-derived): a REAL Postgres round trip
    through TenantBoundConnection is required — mocking the SQLAlchemy
    connection would test the mock instead of the two DB-layer fences these
    tests actually watch (the ADR-011 Decision 3 #19 matched-tenant trigger on
    the leaf table, and the SAME-TRANSACTION rollback property 107's own header
    names as the accepted residual of ADR-054 Decision 2's per-surface
    independence argument).

    SCRATCH DATABASE ONLY, never F/CTO's real local dev DB — a distinct
    database name and a throwaway login role this fixture creates and drops
    itself (NEVER `pfin_etl` — see test_nav_backfill_write.py's own fixture
    docstring for the incident this convention exists to prevent).

    ALL TENANT IDENTITIES AND FIGURES ARE SYNTHETIC — RT-15 parity-fixture
    posture (SECURITY §4.5). Tenant UUIDs are FRESH per test function (uuid4()),
    same reasoning as test_nav_backfill_write.py: pfin.nav_daily AND
    pfin.nav_component_daily are both append-only with mutation-block triggers
    that fence DELETE for every role including postgres/table-owner, so
    isolating tests means never reusing an identity, not clearing state.

    Requires (session-scoped fixture below, this file only):
      - Docker container `supabase_db_mosko-fintech` reachable.
      - `psql`/`pg_dump` inside that container (standard Supabase image).
    Skips cleanly if the container is unreachable.
"""

import subprocess
import uuid
from decimal import Decimal

import pytest

pytestmark = pytest.mark.integration

_CONTAINER = "supabase_db_mosko-fintech"
_SCRATCH_DB = "be_scratch_self353_nav_component_write_int"
_SCRATCH_LOGIN_ROLE = "be_scratch_self353_etl_login"  # created+dropped HERE, never pfin_etl
_SCRATCH_LOGIN_PASSWORD = "be_scratch_only_not_real"  # scratch-only; owned start to finish by this fixture


def _docker_psql(db, sql=None, sql_file=None, check=True):
    cmd = ["docker", "exec"]
    if sql_file:
        cmd = ["docker", "exec", "-i", _CONTAINER, "psql", "-U", "postgres", "-d", db,
               "-v", "ON_ERROR_STOP=1"]
        with open(sql_file, "rb") as f:
            return subprocess.run(cmd, stdin=f, capture_output=True, text=True, check=check)
    cmd += [_CONTAINER, "psql", "-U", "postgres", "-d", db, "-v", "ON_ERROR_STOP=1", "-c", sql]
    return subprocess.run(cmd, capture_output=True, text=True, check=check)


def _docker_available():
    try:
        r = subprocess.run(
            ["docker", "exec", _CONTAINER, "true"], capture_output=True, timeout=5
        )
        return r.returncode == 0
    except Exception:
        return False


@pytest.fixture(scope="module")
def scratch_db():
    """Session-for-this-module scratch database: fresh DB on the local
    Postgres cluster, auth schema mirrored, all migrations applied in order
    (through 107, since this glob picks up whatever is in the migrations dir
    at test time — no version pin needed here), a THROWAWAY login role armed
    for the write path. Dropped on teardown regardless of test outcome.

    ⚠ USES A ROLE THIS FIXTURE CREATES AND DROPS ITSELF — NEVER `pfin_etl`.
    See test_nav_backfill_write.py's own fixture docstring for the incident
    (POSTGRES ROLES ARE CLUSTER-LEVEL, NOT PER-DATABASE) this convention exists
    to prevent from recurring.
    """
    if not _docker_available():
        pytest.skip(f"docker container {_CONTAINER!r} not reachable — skipping integration tier")

    import pathlib
    # this file: <repo_root>/workers/etl/tests/test_nav_component_write.py
    repo_root = pathlib.Path(__file__).resolve().parents[3]
    migrations_dir = repo_root / "supabase" / "migrations"
    if not migrations_dir.is_dir():
        pytest.skip(f"migrations dir not found at {migrations_dir} — worktree layout unexpected")

    _docker_psql("postgres", sql=f"DROP DATABASE IF EXISTS {_SCRATCH_DB};")
    _docker_psql("postgres", sql=f"CREATE DATABASE {_SCRATCH_DB};")

    dump = subprocess.run(
        ["docker", "exec", _CONTAINER, "pg_dump", "-U", "postgres", "-d", "postgres",
         "--schema=auth", "--schema-only", "--no-owner", "--no-privileges"],
        capture_output=True, text=True, check=True,
    )
    restore = subprocess.run(
        ["docker", "exec", "-i", _CONTAINER, "psql", "-U", "postgres", "-d", _SCRATCH_DB,
         "-v", "ON_ERROR_STOP=1"],
        input=dump.stdout, capture_output=True, text=True,
    )
    assert restore.returncode == 0, f"auth schema restore failed: {restore.stderr}"

    ext_sql = (
        "create schema if not exists extensions;"
        "create extension if not exists pg_net schema extensions;"
        "create extension if not exists pg_stat_statements schema extensions;"
        "create extension if not exists pgcrypto schema extensions;"
        "create extension if not exists \"uuid-ossp\" schema extensions;"
        "create schema if not exists vault;"
        "create extension if not exists supabase_vault schema vault;"
    )
    r = _docker_psql(_SCRATCH_DB, sql=ext_sql)
    assert r.returncode == 0, f"extensions setup failed: {r.stderr}"

    # ⚠ THE PERMISSIVE-HARNESS LESSON (QA memory, SELF-218) — see
    # test_nav_backfill_write.py's own fixture for the full explanation:
    # `pg_dump --no-privileges` drops `grant usage on schema auth`, and this
    # suite's fresh `select auth.uid()` under `authenticated` needs it back.
    r = _docker_psql(
        _SCRATCH_DB,
        sql="grant usage on schema auth to authenticated, anon, service_role;",
    )
    assert r.returncode == 0, f"auth schema USAGE grant failed: {r.stderr}"

    for f in sorted(migrations_dir.glob("*.sql")):
        r = subprocess.run(
            ["docker", "exec", "-i", _CONTAINER, "psql", "-U", "postgres", "-d", _SCRATCH_DB,
             "-v", "ON_ERROR_STOP=1"],
            input=f.read_text(), capture_output=True, text=True,
        )
        assert r.returncode == 0, f"migration {f.name} failed: {r.stderr}"

    _docker_psql("postgres", sql=f"DROP ROLE IF EXISTS {_SCRATCH_LOGIN_ROLE};")
    r = _docker_psql(
        _SCRATCH_DB,
        sql=(
            f"create role {_SCRATCH_LOGIN_ROLE} noinherit login "
            f"password '{_SCRATCH_LOGIN_PASSWORD}';"
        ),
    )
    assert r.returncode == 0, f"scratch login role create failed: {r.stderr}"
    r = _docker_psql(
        _SCRATCH_DB,
        sql=f"grant service_role to {_SCRATCH_LOGIN_ROLE}; grant authenticated to {_SCRATCH_LOGIN_ROLE};",
    )
    assert r.returncode == 0, f"scratch login role membership grant failed: {r.stderr}"

    yield {"dbname": _SCRATCH_DB}

    _docker_psql("postgres", sql=f"DROP DATABASE IF EXISTS {_SCRATCH_DB};")
    _docker_psql("postgres", sql=f"DROP ROLE IF EXISTS {_SCRATCH_LOGIN_ROLE};")


@pytest.fixture
def pfin_env(scratch_db, monkeypatch):
    """Point PFIN_DB_* at the scratch DB for exactly one test."""
    monkeypatch.setenv("PFIN_DB_HOST", "127.0.0.1")
    monkeypatch.setenv("PFIN_DB_PORT", "54322")
    monkeypatch.setenv("PFIN_DB_NAME", _SCRATCH_DB)
    monkeypatch.setenv("PFIN_DB_USER", _SCRATCH_LOGIN_ROLE)
    monkeypatch.setenv("PFIN_DB_PASSWORD", _SCRATCH_LOGIN_PASSWORD)
    monkeypatch.setenv("PFIN_DB_SSLMODE", "disable")


def _seed_tenant_with_account(users_id, cash_amount):
    """A fresh tenant with ONE depository account carrying ONE account_trans
    cash deposit — the minimal fixture that gives
    pfin.fn_account_unrealized_gl(current_date) a real, deterministic
    (account_id, current_market_value) leaf: for a cash-only depository
    account the securities leg is empty and current_market_value is exactly
    the account_trans sum (fn_account_cash_as_of), so nav_value and the leaf's
    component_value both equal `cash_amount` exactly — no annotation, no
    posting_prototype row needed for this shape (measured directly against
    this fixture before writing these assertions, not assumed from reading
    049's SQL alone).

    Returns the account_id (bigint) — tests use it to assert the leaf's own
    account_id, not just its value.
    """
    r = _docker_psql(_SCRATCH_DB, sql=f"insert into auth.users (id) values ('{users_id}');")
    assert r.returncode == 0, f"tenant seed failed: {r.stderr}"
    r = _docker_psql(
        _SCRATCH_DB,
        sql=(
            "insert into pfin.account (users_id, name, account_type, scope, tax_treatment, currency) "
            f"values ('{users_id}', 'Test Checking', 'depository', 'Personal', 'taxable', 'USD') "
            "returning account_id;"
        ),
    )
    assert r.returncode == 0, f"account seed failed: {r.stderr}"
    account_id = None
    for line in r.stdout.splitlines():
        line = line.strip()
        if line.isdigit():
            account_id = int(line)
    assert account_id is not None, f"could not parse account_id from: {r.stdout!r}"
    r = _docker_psql(
        _SCRATCH_DB,
        sql=(
            f"insert into pfin.account_trans (account_id, transaction_date, amount) "
            f"values ({account_id}, current_date - 1, {cash_amount});"
        ),
    )
    assert r.returncode == 0, f"account_trans seed failed: {r.stderr}"
    return account_id


def _nav_daily_rows(users_id):
    r = _docker_psql(
        _SCRATCH_DB,
        sql=f"select count(*) from pfin.nav_daily where users_id = '{users_id}';",
    )
    for line in r.stdout.splitlines():
        line = line.strip()
        if line.isdigit():
            return int(line)
    raise AssertionError(f"could not parse row count from psql output: {r.stdout!r}")


def _leaf_rows(users_id):
    r = _docker_psql(
        _SCRATCH_DB,
        sql=(
            "select account_id, component_value from pfin.nav_component_daily "
            f"where users_id = '{users_id}' order by account_id;"
        ),
    )
    rows = []
    for line in r.stdout.splitlines():
        line = line.strip()
        parts = [p.strip() for p in line.split("|")]
        if len(parts) == 2 and parts[0].isdigit():
            rows.append((int(parts[0]), Decimal(parts[1])))
    return rows


# ---------------------------------------------------------------------------
# Happy path — leaves written alongside the scalar, on the FIRST insert.
# ---------------------------------------------------------------------------
def test_leaves_written_when_scalar_inserted(pfin_env):
    from pfin_back_etl.nav_daily import NavDailyWorker

    tenant = uuid.uuid4()
    other_tenant = uuid.uuid4()
    account_id = _seed_tenant_with_account(tenant, "1000.00")
    _seed_tenant_with_account(other_tenant, "9999.00")  # non-vacuity control

    worker = NavDailyWorker()
    nav_value, inserted, leaves_written = worker.compute_and_checkpoint_user(tenant)

    assert inserted == 1
    assert leaves_written == 1
    assert nav_value == Decimal("1000.00000")

    leaves = _leaf_rows(tenant)
    assert leaves == [(account_id, Decimal("1000.00000"))]
    # non-vacuity: checkpointing `tenant` writes nothing under `other_tenant`
    assert _leaf_rows(other_tenant) == []


# ---------------------------------------------------------------------------
# Same-day re-run — idempotent no-op on BOTH tables (107 WORKER CONTRACT W3).
# ---------------------------------------------------------------------------
def test_second_run_same_day_writes_no_leaves(pfin_env):
    from pfin_back_etl.nav_daily import NavDailyWorker

    tenant = uuid.uuid4()
    _seed_tenant_with_account(tenant, "1000.00")

    worker = NavDailyWorker()
    first = worker.compute_and_checkpoint_user(tenant)
    assert first[1:] == (1, 1)  # (inserted, leaves_written)

    second = worker.compute_and_checkpoint_user(tenant)
    assert second[1:] == (0, 0), "a same-day re-run must write NO leaves either"

    assert _nav_daily_rows(tenant) == 1  # still exactly one scalar row
    assert len(_leaf_rows(tenant)) == 1  # still exactly one leaf row (not duplicated)


# ---------------------------------------------------------------------------
# The reconciliation identity AC 6 watches — measured on this exact fixture.
# ---------------------------------------------------------------------------
def test_sum_of_leaves_equals_nav_value(pfin_env):
    from pfin_back_etl.nav_daily import NavDailyWorker

    tenant = uuid.uuid4()
    _seed_tenant_with_account(tenant, "1234.56")

    worker = NavDailyWorker()
    nav_value, inserted, leaves_written = worker.compute_and_checkpoint_user(tenant)
    assert inserted == 1
    assert leaves_written == 1

    leaves = _leaf_rows(tenant)
    leaf_sum = sum(v for _, v in leaves)
    assert leaf_sum == nav_value == Decimal("1234.56000")


# ---------------------------------------------------------------------------
# ⭐ THE CATCH-CRITERION SAME-TRANSACTION EXISTS FOR: a leaf-side raise must
# roll back the scalar checkpoint too — not leave a scalar with no leaves.
# ---------------------------------------------------------------------------
def test_leaf_side_failure_rolls_back_the_scalar(pfin_env):
    """Poison the leaf read (monkeypatch `nav_daily._LEAF_READ`, the narrowest
    seam that changes WHAT is read without touching HOW the write executes) so
    it returns the tenant's own real leaf UNION a literal row naming a SECOND
    tenant's real account_id — a genuine cross-tenant leaf under this tenant's
    `app.nav_computed_for` binding. The ADR-011 Decision 3 #19 matched-tenant
    trigger on pfin.nav_component_daily (107) MUST raise on that row, and
    because the scalar INSERT and the leaf INSERT share ONE transaction (107's
    own accepted residual — see nav_daily.py's module docstring), the raise
    must roll back the scalar too: zero rows on EITHER table for this tenant,
    not a scalar checkpoint with no matching leaves.
    """
    import pfin_back_etl.nav_daily as nd_module

    tenant = uuid.uuid4()
    foreign_tenant = uuid.uuid4()
    _seed_tenant_with_account(tenant, "500.00")
    foreign_account_id = _seed_tenant_with_account(foreign_tenant, "1.00")

    original_leaf_read = nd_module._LEAF_READ
    nd_module._LEAF_READ = (
        "select account_id, current_market_value from pfin.fn_account_unrealized_gl(current_date) "
        f"union all select {foreign_account_id}::bigint, 1.0::numeric"
    )
    try:
        worker = nd_module.NavDailyWorker()
        with pytest.raises(Exception, match="matched-tenant"):
            worker.compute_and_checkpoint_user(tenant)
    finally:
        nd_module._LEAF_READ = original_leaf_read

    assert _nav_daily_rows(tenant) == 0, "the scalar checkpoint must roll back with the failed leaf write"
    assert _leaf_rows(tenant) == []
    # the foreign tenant's own checkpoint run is untouched by this failure
    assert _nav_daily_rows(foreign_tenant) == 0  # never ran for foreign_tenant in this test


# ---------------------------------------------------------------------------
# All-closed-accounts edge — an empty leaf set must not attempt an invalid
# zero-row INSERT (empty VALUES list is not valid SQL).
# ---------------------------------------------------------------------------
def test_zero_accounts_writes_scalar_zero_and_no_leaves(pfin_env):
    from pfin_back_etl.nav_daily import NavDailyWorker

    tenant = uuid.uuid4()
    r = _docker_psql(_SCRATCH_DB, sql=f"insert into auth.users (id) values ('{tenant}');")
    assert r.returncode == 0

    worker = NavDailyWorker()
    nav_value, inserted, leaves_written = worker.compute_and_checkpoint_user(tenant)

    assert nav_value == Decimal("0")
    assert inserted == 1
    assert leaves_written == 0
    assert _leaf_rows(tenant) == []
