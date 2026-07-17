# tests/fixtures/ci/tbc-basename-collision/etl/core.py
#
# The VIOLATOR half of the Python same-basename collision regression fixture. SAME
# BASENAME (core.py) as the class file at ../db/core.py, DIFFERENT directory.
# Constructs a bare SQLAlchemy engine OUTSIDE the TenantBoundConnection class — a
# real Lock 13 mod #3 violation a correct fence MUST catch.
#
# Under the buggy grep --exclude=core.py pre-filter this line was silently skipped
# (excluded by basename). Full-path-only exclusion catches it because this file's
# full path (.../etl/core.py) does NOT match the allowed class file (.../db/core.py).
# NOT a template.

import sqlalchemy as sqla

# VIOLATION: bare engine construction outside TenantBoundConnection.
engine = sqla.create_engine(
    "postgresql+psycopg2://service_role:fake-fixture-password@localhost/pfin"
)
