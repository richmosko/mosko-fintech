# tests/fixtures/ci/tbc-basename-collision/db/core.py
#
# REGRESSION FIXTURE (Python) for the grep --exclude=<basename> false-negative Sec
# caught 2026-07-17 — the Python-parity twin of tbc-node-basename-collision/. This
# file DECLARES `class TenantBoundConnection` and legitimately constructs the
# SQLAlchemy engine INSIDE the class, so a correct fence must treat THIS file's
# construction as allowed (full-path exclusion).
#
# The paired violator lives at ../etl/core.py — SAME BASENAME (core.py), DIFFERENT
# directory. The bug: grep --exclude=core.py would exclude BOTH by basename,
# silently skipping the violator. The fix (full-path-only exclusion) must skip THIS
# file but CATCH ../etl/core.py.
#
# CI expectation: fence-tbc-pfin-back-etl.sh run in PRODUCTION mode (class present,
# no --allow-missing-class) against this collision dir MUST exit 1 (the violator
# trips) — NOT exit 0. If it exits 0, the basename false-negative has regressed.
#
# Fixture path discipline: lives under tests/fixtures/ci/, excluded from all build
# contexts via .dockerignore `tests/`; never runtime-loadable. NOT a template.

import sqlalchemy as sqla


class TenantBoundConnection:
    def __init__(self, users_id):
        # Legitimate: the SOLE sanctioned engine construction, inside the class.
        self._engine = sqla.create_engine(
            "postgresql+psycopg2://service_role:fake-fixture-password@localhost/pfin"
        )
        self._users_id = users_id
