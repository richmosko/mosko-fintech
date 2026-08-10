"""
Project:       pfin-back-etl
Author:        Rich Mosko (mosko-fintech Backend)

Description:
    Shared support for the `pgtest` tier — one definition of what the tier
    guarantees, used by every `pgtest` module.

    ⚠ WHY THIS IS SHARED RATHER THAN COPIED. Two copies of one policy drift;
    that is not a hypothetical here — it is what produced the second,
    ungoverned skip policy in `test_dbase_setup`, reconciled earlier in this
    same work. The URL resolution, the CI-fails-rather-than-skips rule, and the
    tier's preconditions live here once.

    ⚠ THE TIER'S PREMISE, STATED SO IT CAN BE CHECKED RATHER THAN ASSUMED.
    `pgtest` means: **a real Postgres, no credentials, no project schema.** It
    runs against a bare `postgres:17` service with zero secrets.

    That premise DRIFTED and the fence caught it. The tier was defined for the
    staging-update tests, which touch only temp tables and hold the premise
    exactly. The reflection tests then joined the tier while needing something
    the premise never promised: **the role NAMES must exist.** `authenticated`
    and `service_role` are Supabase-provisioned; a bare `postgres:17` has
    neither, and `set local role authenticated` fails
    `InvalidParameterValue: role "authenticated" does not exist`.

    The fix is to make the tier PROVIDE what its tests need, not to weaken the
    premise or to demote the tests to a manual lane. `ensure_roles()` creates
    the names with NO privileges — existence is all `SET ROLE` requires — so
    the tier still promises no schema and no secrets.

    ⚠ WHAT ELSE IN `pgtest` ASSUMES SUPABASE-PROVISIONED STATE — the question
    worth re-asking, because it is the claim that will go stale next.
    Audited at this commit:
      · test_staging_update.py  — temp tables only. Assumes NOTHING. Holds.
      · test_reflection_role.py — needs the two role NAMES (provided here) and
        two empty schemas for the construction path (provided here). Needs no
        project TABLES: the properties under test are "a role was assumed" and
        "catalog visibility is gated by schema USAGE, not per-table grants",
        and both are demonstrated on self-provisioned fixtures.
    If a future `pgtest` needs anything beyond roles and empty schemas, it has
    outgrown the tier — extend this module deliberately and update this list,
    rather than letting the premise drift again in silence.
"""

import os

import pytest
import sqlalchemy as sqla

#: Bare connection URL for the tier. NOT the `backend` fixture — these need a
#: Postgres, not a configured ETL.
PG_URL_ENV = "PFIN_PGTEST_URL"

#: Role NAMES the tier guarantees exist. They are created without privileges:
#: `SET ROLE` requires only that the name exist, and granting anything here
#: would make the tier quietly stronger than a bare container.
REQUIRED_ROLE_NAMES = ("authenticated", "service_role")

#: Empty schemas the tier guarantees exist, so `PFinBackend` construction can
#: reflect. Deliberately EMPTY — no project tables. A test needing real tables
#: is not a `pgtest`.
REQUIRED_SCHEMA_NAMES = ("auth", "pfin")


def resolve_url():
    """The tier's URL, or a decision about why there isn't one.

    ⚠ SKIPPING IS A FAILURE UNDER CI. A skip is indistinguishable from a pass
    in a summary line, and these tests are the only automated detector for
    properties that are otherwise checked by hand — so under `CI` an
    unconfigured URL FAILS. Outside CI a skip is legitimate: a developer
    without a Postgres is not a defect.
    """
    url = os.getenv(PG_URL_ENV)
    if url:
        return url
    if os.getenv("CI"):
        raise AssertionError(
            f"{PG_URL_ENV} is unset under CI. The pgtest tier is the only "
            f"automated detector for these properties; skipping would report "
            f"green for a lane that ran nothing."
        )
    pytest.skip(f"{PG_URL_ENV} unset — no Postgres for the pgtest tier")


def ensure_roles(conn, names=REQUIRED_ROLE_NAMES):
    """Create the tier's role NAMES if absent. No privileges granted.

    Idempotent and safe against a Supabase stack, where they already exist.
    `create role` has no `if not exists`, hence the guard.
    """
    for name in names:
        conn.execute(
            sqla.text(
                "do $$ begin "
                f"if not exists (select 1 from pg_roles where rolname = '{name}') "
                f"then create role {name}; "
                "end if; end $$;"
            )
        )


def ensure_schemas(conn, names=REQUIRED_SCHEMA_NAMES, usage_to=REQUIRED_ROLE_NAMES):
    """Create the tier's EMPTY schemas if absent, with USAGE to the tier roles.

    USAGE is granted because it is precisely the privilege the reflection path
    needs and the one whose absence caused the production failure — a tier that
    withheld it would make the construction test fail for the right reason in
    the wrong place.
    """
    for name in names:
        conn.execute(sqla.text(f"create schema if not exists {name}"))
        for role in usage_to:
            conn.execute(sqla.text(f"grant usage on schema {name} to {role}"))


def prepare(conn):
    """Everything the tier guarantees, in one call."""
    ensure_roles(conn)
    ensure_schemas(conn)
