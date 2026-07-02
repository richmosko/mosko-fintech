# tests/fixtures/ci/tbc-violation.py
#
# DELIBERATELY OUTSIDE TenantBoundConnection — TBC golden-test fixture per ARCH §6
# Phase 5 detail item (d). Covers all four violation shapes outside the class
# binding users_id: (1) raw psycopg2.connect(); (2) from-import connect();
# (3) bare sqla.create_engine() — the ETL's REAL SQLAlchemy connection path;
# (4) unqualified create_engine() from-import. The TBC fence MUST report
# violation against this file at every CI invocation.
#
# CI inversion check (per Sec rubric (b)3 + ARCH §6.1 TBC row):
#   The TBC fence script MUST flag this fixture at every CI invocation. If the
#   fence reports clean, CI fails closed — the fence is broken.
#
# Fixture path discipline (per Sec rubric (b)3 #2 + agent-def):
#   This file lives at tests/fixtures/ci/ and is excluded from:
#     (a) mosko-fintech production build contexts via .dockerignore.
#     (b) pfin_back_etl production module discovery via pyproject.toml /
#         setup.py packages exclusion + .dockerignore (paired-PR responsibility
#         per the α cross-repo posture; coordinated via scripts/ci/README.md).
#   Net effect: this file is NEVER runtime-loadable in any production container.
#   Without that exclusion, the raw connect() below would be a real security
#   hazard — fixture-as-attack-surface is what Sec rubric (b)3 #2 catches.
#
# DO NOT use this file as a template for any production work; use the
# TenantBoundConnection class instead.

import psycopg2

# Raw connect — bypasses TenantBoundConnection tenant binding.
# Lock 13 mod #3 V1-SHIP-BLOCK: TenantBoundConnection is the only allowed
# Postgres-client entry point in pfin_back_etl. This invocation pattern violates
# that by-construction.
conn = psycopg2.connect(
    host="localhost",
    database="pfin",
    user="service_role",
    password="fake-fixture-password",
)

# A second violation shape: from-import.
from psycopg2 import connect  # noqa: E402, F811
conn2 = connect(host="localhost", database="pfin")

# A third violation shape: bare SQLAlchemy engine construction outside the
# TenantBoundConnection class. This is the ETL's REAL DB connection path —
# core.py routes it through TenantBoundConnection.system(); a bare
# sqla.create_engine() here bypasses the sole sanctioned engine factory.
# Lock 13 mod #3 V1-SHIP-BLOCK: the TBC fence MUST flag this. This is the
# pattern the pre-fix fence missed (it greped only psycopg2.connect()), which
# is why it failed OPEN against the actual SQLAlchemy-based ETL code.
import sqlalchemy as sqla  # noqa: E402
engine = sqla.create_engine(  # noqa: F841
    "postgresql+psycopg2://service_role:fake-fixture-password@localhost/pfin"
)

# A fourth violation shape: unqualified create_engine from-import.
from sqlalchemy import create_engine  # noqa: E402, F811
engine2 = create_engine(  # noqa: F841
    "postgresql+psycopg2://service_role:fake-fixture-password@localhost/pfin"
)
