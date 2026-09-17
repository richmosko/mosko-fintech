"""
Project:       pfin-back-etl
Author:        QA (mosko-fintech)

Description:
    `integration`-tier tests for NavBackfillWorker's DB-touching half —
    write_backfill() (ADR-053 Decision 6: one transaction, all rows or
    none), run(), and computed_nav_today(). These need a REAL Postgres round
    trip through TenantBoundConnection (impersonate -> read auth.uid() back
    -> bind -> INSERT), so — per Backend's own review (2026-08-12) — they are
    NOT mocked: mocking the SQLAlchemy connection here would test the mock
    instead of the code, and the whole point of AC7 is that the write-tenant
    binding is proven against a live database, not asserted about one.

    SCRATCH DATABASE ONLY, never F/CTO's real local dev DB. Per Backend's own
    coordination reply, this deliberately does NOT reuse the `.env`-pointing
    `construct_or_skip`/`nav_worker` fixture shape those tests use — this
    file's tests WRITE rows, which is exactly what a scratch-DB-per-module
    harness exists to keep off the real stack.

    ⚠ ADR-072 Amendment 5 / Sec H2 harness-identity ruling (2026-09-17): this
    fixture used to build its own scratch DB by hand (create DB -> `pg_dump
    --schema=auth` mirror -> re-create extensions -> re-apply every
    `supabase/migrations/*.sql` file in order via raw `docker exec ... psql`)
    — a SECOND, hand-rolled migration-apply path that diverged from the
    pgTAP harness's own and from `db-template-build.sh`, and which started
    failing "permission denied for database" at `001_pfin_foundation.sql`
    once ADR-072 Amendment 5 changed pfin object ownership: `postgres`
    reaching the freshly-created scratch DB no longer has the same implicit
    per-database bootstrap posture the old one-off DB had. Rebuilding that
    posture by hand here — a THIRD copy of "how a fresh pfin DB gets set
    up" — is exactly the drift DevOps's `scripts/db-template-clone.sh`
    exists to close (it already builds/refreshes `pfin_tmpl` via
    `db-template-build.sh` and stamps + checks a staleness marker so a clone
    is never silently served against a stale schema). This fixture now
    SHELLS OUT to that script instead of re-implementing scratch-DB
    construction: one harness path, not three.
    ⚠ NEVER `pfin_etl` — see the `scratch_db` fixture's own docstring for the
    incident this recipe exists to prevent from recurring.

    ALL TENANT IDENTITIES AND FIGURES ARE SYNTHETIC — RT-15 parity-fixture
    posture (SECURITY §4.5): no PII, no real account numbers, no real dollar
    figure anywhere in this file. Tenant UUIDs are FRESH per test function
    (uuid4(), see `seeded_tenants` below), not fixed constants: pfin.nav_daily
    is append-only and its mutation-block trigger fences DELETE for every
    role including postgres/table-owner (054's own irreversibility design —
    this suite deliberately does not fight it), so isolating tests from each
    other's rows means never reusing a tenant identity, not clearing state
    between tests.

    Requires (session-scoped fixture below, this file only):
      - Docker container `supabase_db_mosko-fintech` reachable (same local
        cluster the pgTAP scratch harness uses).
      - `psql`/`pg_dump` inside that container (standard Supabase image).
    Skips cleanly (not a hard failure) if the container is unreachable — see
    `_docker_available()` — so this file does not break a run on a machine
    without the local Supabase stack up.
"""

import datetime as dt
import subprocess
import uuid
from decimal import Decimal

import pytest

pytestmark = pytest.mark.integration

_CONTAINER = "supabase_db_mosko-fintech"
_SCRATCH_DB = "qa_scratch_self217_write_int"
_SCRATCH_LOGIN_ROLE = "qa_scratch_self217_etl_login"  # created+dropped HERE, never pfin_etl
_SCRATCH_LOGIN_PASSWORD = "qa_scratch_only_not_real"  # scratch-only; owned start to finish by this fixture


def _docker_psql(db, sql=None, sql_file=None, check=True):
    cmd = ["docker", "exec"]
    if sql_file:
        cmd = ["docker", "exec", "-i", _CONTAINER, "psql", "-U", "postgres", "-d", db,
               "-v", "ON_ERROR_STOP=1"]
        with open(sql_file, "rb") as f:
            return subprocess.run(cmd, stdin=f, capture_output=True, text=True, check=check)
    cmd += [_CONTAINER, "psql", "-U", "postgres", "-d", db, "-v", "ON_ERROR_STOP=1", "-c", sql]
    return subprocess.run(cmd, capture_output=True, text=True, check=check)


def _docker_psql_admin(db, sql, check=False):
    # ⚠ `db-template-clone.sh` creates the clone as `supabase_admin`, NOT
    # `postgres` (its own header: "once a clone is created as
    # supabase_admin, $SUPERUSER no longer owns it either" — createdb's
    # owner is whoever connects to run it). `postgres` therefore cannot
    # DROP DATABASE on this scratch DB post-clone; teardown must use the
    # same identity the script used to create it. `check=False` by default:
    # teardown best-effort, same posture the pre-clone-script version had.
    cmd = ["docker", "exec", _CONTAINER, "psql", "-U", "supabase_admin", "-d", db,
           "-v", "ON_ERROR_STOP=1", "-c", sql]
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
    """Session-for-this-module scratch database: a fast structural CLONE of
    `pfin_tmpl` (DevOps's `scripts/db-template-clone.sh`), a THROWAWAY login
    role armed for the write path. Dropped on teardown regardless of test
    outcome. NEVER touches F/CTO's real local dev DB — a distinct database
    name on the same cluster, created and dropped here.

    ⚠ ROUTES THROUGH `db-template-clone.sh` RATHER THAN BUILDING THE SCRATCH
    DB BY HAND — ADR-072 Amendment 5 / Sec H2 harness-identity ruling
    (2026-09-17). This fixture used to DROP/CREATE DATABASE, mirror `auth`
    via `pg_dump --schema=auth`, re-create the `extensions`/`vault`
    extensions, and re-apply every `supabase/migrations/*.sql` file in
    order — a second, hand-rolled construction path that started failing
    "permission denied for database" at `001_pfin_foundation.sql` once the
    ownership sweep landed (the fresh scratch DB no longer inherited the
    same per-database bootstrap posture `postgres` had before). Rebuilding
    that logic here — a THIRD copy of "how a pfin DB gets set up," after the
    pgTAP harness's own and `db-template-build.sh` — is the drift the clone
    script exists to close: it clones the already-built, already-migrated,
    already-granted `pfin_tmpl` template (built by `db-template-build.sh`,
    which this repo's CI wires in ahead of this job — see that script's own
    header for the staleness fence it enforces) and hands back a scratch DB
    `postgres` can read/write immediately, no further setup. `auth-schema`
    privileges and the H2 `pfin_owner` INHERIT grant are baked into
    `pfin_tmpl` at build time and copied by the clone — this fixture does
    not re-apply either.

    ⚠ USES A ROLE THIS FIXTURE CREATES AND DROPS ITSELF — NEVER `pfin_etl`.
    Incident recorded here so it is not repeated: an earlier version of this
    fixture ran `ALTER ROLE pfin_etl LOGIN PASSWORD ...` against the scratch
    DB, on the wrong assumption that the role attribute was scoped to the
    database connected to. POSTGRES ROLES ARE CLUSTER-LEVEL, NOT PER-
    DATABASE — that command silently overwrote the REAL `pfin_etl` role's
    password verifier (a SCRAM hash, unrecoverable) cluster-wide, affecting
    F/CTO's real local dev environment. Root cause and incident report: see
    the QA/team-lead message thread, 2026-08-12. `_SCRATCH_LOGIN_ROLE` below
    is a role this fixture owns end to end — created here, dropped here,
    named distinctly from anything a migration creates — so this class of
    mistake cannot recur through this file. The clone script does NOT create
    this role either — that stays this fixture's own step, unchanged.
    """
    if not _docker_available():
        pytest.skip(f"docker container {_CONTAINER!r} not reachable — skipping integration tier")

    import pathlib
    # this file: <repo_root>/workers/etl/tests/test_nav_backfill_write.py
    repo_root = pathlib.Path(__file__).resolve().parents[3]
    clone_script = repo_root / "scripts" / "db-template-clone.sh"
    if not clone_script.is_file():
        pytest.skip(f"{clone_script} not found — worktree layout unexpected")

    # Non-zero exit = clone failed (no template, stale template, or a real
    # DB error) — a hard failure, not a skip: the container IS reachable
    # (checked above), so a clone failure here is a real problem the script
    # already reports with a specific cause (see its own die() messages).
    subprocess.run(
        ["bash", str(clone_script), _SCRATCH_DB],
        cwd=repo_root, capture_output=True, text=True, check=True,
    )

    # Throwaway login role — NOINHERIT + membership shape mirrors 055's
    # pfin_etl exactly (that shape is what TenantBoundConnection's SET
    # LOCAL ROLE dance depends on), but this identity is owned start to
    # finish by this fixture, never the shared cluster role. The clone does
    # NOT create it — that stays this fixture's own step, per DevOps's
    # interface note.
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

    _docker_psql_admin("postgres", f"DROP DATABASE IF EXISTS {_SCRATCH_DB};")
    _docker_psql("postgres", sql=f"DROP ROLE IF EXISTS {_SCRATCH_LOGIN_ROLE};")


@pytest.fixture
def pfin_env(scratch_db, monkeypatch):
    """Point PFIN_DB_* at the scratch DB for exactly one test — utils.
    load_db_params(env_prefix='PFIN_') reads these, so NavBackfillWorker()
    constructed inside a test using this fixture connects to the scratch DB,
    never to whatever `.env` would otherwise resolve."""
    monkeypatch.setenv("PFIN_DB_HOST", "127.0.0.1")
    monkeypatch.setenv("PFIN_DB_PORT", "54322")
    monkeypatch.setenv("PFIN_DB_NAME", _SCRATCH_DB)
    monkeypatch.setenv("PFIN_DB_USER", _SCRATCH_LOGIN_ROLE)
    monkeypatch.setenv("PFIN_DB_PASSWORD", _SCRATCH_LOGIN_PASSWORD)
    monkeypatch.setenv("PFIN_DB_SSLMODE", "disable")


@pytest.fixture
def seeded_tenants(scratch_db):
    """FRESH auth.users rows for two synthetic tenants, generated new for
    EVERY test function (uuid4(), never a fixed constant). This is how tests
    are isolated from each other on an append-only table that structurally
    cannot be cleared between tests (see the module docstring) — a fresh
    identity per test means there is no prior row for any test to collide
    with, so nothing needs deleting."""
    tenant_a = uuid.uuid4()
    tenant_b = uuid.uuid4()
    r = _docker_psql(
        _SCRATCH_DB,
        sql=f"insert into auth.users (id) values ('{tenant_a}'), ('{tenant_b}');",
    )
    assert r.returncode == 0, f"tenant seed failed: {r.stderr}"
    yield {"a": tenant_a, "b": tenant_b}


def _row_count(users_id):
    r = _docker_psql(
        _SCRATCH_DB,
        sql=f"select count(*) from pfin.nav_daily where users_id = '{users_id}';",
    )
    # psql -c output: header line(s), then the value, then "(1 row)" — parse defensively.
    for line in r.stdout.splitlines():
        line = line.strip()
        if line.isdigit():
            return int(line)
    raise AssertionError(f"could not parse row count from psql output: {r.stdout!r}")


def _row(date_str, dollars):
    from pfin_back_etl.nav_backfill import BackfillRow

    return BackfillRow(
        nav_date=dt.date.fromisoformat(date_str),
        nav_value_dollars=Decimal(dollars),
        source_row_num=1,
    )


# ---------------------------------------------------------------------------
# Happy path — the write-tenant binding fence is non-vacuous end to end.
# ---------------------------------------------------------------------------
def test_write_backfill_happy_path_writes_all_rows(pfin_env, seeded_tenants):
    from pfin_back_etl import NavBackfillWorker

    tenant_a, tenant_b = seeded_tenants["a"], seeded_tenants["b"]
    worker = NavBackfillWorker()
    rows = [_row("2015-12-31", "500000"), _row("2016-01-31", "510000")]
    inserted = worker.write_backfill(tenant_a, rows)
    assert inserted == 2
    assert _row_count(tenant_a) == 2
    assert _row_count(tenant_b) == 0  # non-vacuity: the OTHER tenant sees nothing


# ---------------------------------------------------------------------------
# ADR-053 Decision 6 — whole-batch rollback, not per-row isolation.
# ---------------------------------------------------------------------------
def test_write_backfill_poisoned_row_rolls_back_whole_batch(pfin_env, seeded_tenants):
    """⭐ THE CATCH-CRITERION THE REDESIGN EXISTS FOR: two GOOD rows ahead of
    one POISONED row (nav_value_dollars=None, violating nav_daily's NOT NULL)
    must leave ZERO rows written — not two, not "two committed, one failed".
    A per-row-transaction implementation (the shape this replaced) would
    pass a weaker version of this test by leaving the two good rows behind;
    asserting count == 0 specifically is what distinguishes ADR-053 Decision
    6 compliance from the reverted per-row shape."""
    from pfin_back_etl.nav_backfill import BackfillRow
    from pfin_back_etl import NavBackfillWorker

    tenant_a = seeded_tenants["a"]
    worker = NavBackfillWorker()
    poisoned = BackfillRow(nav_date=dt.date(2016, 2, 29), nav_value_dollars=None, source_row_num=3)
    rows = [_row("2015-12-31", "500000"), _row("2016-01-31", "510000"), poisoned]
    with pytest.raises(Exception):
        worker.write_backfill(tenant_a, rows)
    assert _row_count(tenant_a) == 0


# ---------------------------------------------------------------------------
# AC7 GUC-vacuity — the fence must actually fire on a real identity mismatch.
# ---------------------------------------------------------------------------
def test_write_backfill_guc_mismatch_raises_and_writes_nothing(pfin_env, seeded_tenants, monkeypatch):
    """⭐ THE GUC-VACUITY DISTINGUISHING TEST (Backend's suggested seam,
    2026-08-12). Rig write_backfill(users_id=TENANT_A, ...) so the
    TenantBoundConnection it actually gets back is impersonating TENANT_B
    instead — a real disagreement between what the caller asked for and what
    the DB-resolved identity is. A hypothetical implementation that bound
    app.nav_computed_for straight from the `users_id` ARGUMENT (skipping the
    read-back this function's entire job is to perform) would never notice
    this and would write rows under a forged tenant binding; the correct
    implementation raises and writes nothing for EITHER tenant."""
    import pfin_back_etl.nav_backfill as nb_module

    tenant_a, tenant_b = seeded_tenants["a"], seeded_tenants["b"]
    real_for_tenant = nb_module.TenantBoundConnection.for_tenant
    monkeypatch.setattr(
        nb_module.TenantBoundConnection,
        "for_tenant",
        classmethod(lambda cls, url, users_id: real_for_tenant(url, tenant_b)),
    )

    worker = nb_module.NavBackfillWorker()
    rows = [_row("2015-12-31", "500000")]
    with pytest.raises(RuntimeError, match="auth.uid"):
        worker.write_backfill(tenant_a, rows)
    assert _row_count(tenant_a) == 0
    assert _row_count(tenant_b) == 0  # the impersonated identity wrote nothing either


# ---------------------------------------------------------------------------
# First-write-wins idempotence — ON CONFLICT DO NOTHING, re-run is a no-op.
# ---------------------------------------------------------------------------
def test_write_backfill_second_run_is_idempotent_no_op(pfin_env, seeded_tenants):
    from pfin_back_etl import NavBackfillWorker

    tenant_a = seeded_tenants["a"]
    worker = NavBackfillWorker()
    rows = [_row("2015-12-31", "500000"), _row("2016-01-31", "510000")]
    first = worker.write_backfill(tenant_a, rows)
    assert first == 2
    second = worker.write_backfill(tenant_a, rows)
    assert second == 0  # ON CONFLICT DO NOTHING — nothing NEW inserted
    assert _row_count(tenant_a) == 2  # and the original two rows are untouched, not duplicated


# ---------------------------------------------------------------------------
# run() orchestration — dry-run writes nothing; commit propagates a failure
# rather than returning a partial-success summary (ADR-053 Decision 6).
# ---------------------------------------------------------------------------
def test_run_dry_run_writes_nothing(pfin_env, seeded_tenants):
    from pfin_back_etl import NavBackfillWorker

    tenant_a = seeded_tenants["a"]
    worker = NavBackfillWorker()
    rows = [_row("2015-12-31", "500000"), _row("2016-01-31", "510000")]
    summary = worker.run(tenant_a, rows, commit=False)
    assert summary == {"total": 2, "inserted": 0}
    assert _row_count(tenant_a) == 0


def test_run_commit_true_matches_write_backfill_count(pfin_env, seeded_tenants):
    from pfin_back_etl import NavBackfillWorker

    tenant_a = seeded_tenants["a"]
    worker = NavBackfillWorker()
    rows = [_row("2015-12-31", "500000"), _row("2016-01-31", "510000")]
    summary = worker.run(tenant_a, rows, commit=True)
    assert summary == {"total": 2, "inserted": 2}
    assert _row_count(tenant_a) == 2


def test_run_commit_true_raises_rather_than_returning_partial_summary(pfin_env, seeded_tenants):
    """⭐ Pins the new run() contract explicitly: on a failing batch it RAISES
    (propagates write_backfill's exception) rather than returning a
    `{"failed": N}` shape — that shape is exactly what Backend's fix removed,
    because it let a rolled-back transaction report as a normal outcome."""
    from pfin_back_etl.nav_backfill import BackfillRow
    from pfin_back_etl import NavBackfillWorker

    tenant_a = seeded_tenants["a"]
    worker = NavBackfillWorker()
    poisoned = BackfillRow(nav_date=dt.date(2016, 2, 29), nav_value_dollars=None, source_row_num=3)
    rows = [_row("2015-12-31", "500000"), poisoned]
    with pytest.raises(Exception):
        worker.run(tenant_a, rows, commit=True)
    assert _row_count(tenant_a) == 0
